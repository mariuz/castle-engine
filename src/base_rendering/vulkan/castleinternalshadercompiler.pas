{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Runtime GLSL-to-SPIR-V compiler and persistent disk cache for Castle Game Engine.
  Dynamically binds Google's libshaderc_shared library (bundled with the Vulkan SDK
  or CGE distributables) and caches compiled SPIR-V blobs in ApplicationConfig. }
unit CastleInternalShaderCompiler;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Generics.Collections, SyncObjs,
  CastleDynLib, CastleFilesUtils, CastleUriUtils, CastleDownload, CastleLog,
  CastleInternalRHI, CastleInternalShaderRHI;

type
  { Raw byte array holding 32-bit aligned SPIR-V words }
  TSPIRVBytecode = TBytes;
  TUInt64Array = array of UInt64;

  { Reflected descriptor binding extracted from a SPIR-V binary module }
  TSPIRVReflectedBinding = record
    SetIndex: Cardinal;
    Binding: Cardinal;
    DescriptorType: TRHIDescriptorType;
    { Array element count (1 for scalar descriptor, >1 for OpTypeArray, 0 for OpTypeRuntimeArray) }
    Count: Cardinal;
    { Struct size in bytes for Uniform/Storage buffer blocks; 0 for opaque image/sampler bindings }
    BlockSize: Cardinal;
    Name: String;
  end;
  TSPIRVReflectedBindingArray = array of TSPIRVReflectedBinding;

  { Reflected stage input/output attribute extracted from a SPIR-V binary module }
  TSPIRVReflectedStageIO = record
    Location: Cardinal;
    IsOutput: Boolean;
    ComponentCount: Cardinal;
    Name: String;
  end;
  TSPIRVReflectedStageIOArray = array of TSPIRVReflectedStageIO;

  { Complete pure-Pascal reflection metadata extracted from a pre-compiled SPIR-V binary }
  TSPIRVReflectionInfo = record
    IsValid: Boolean;
    ByteSwapped: Boolean;
    VersionMajor: Byte;
    VersionMinor: Byte;
    GeneratorMagic: Cardinal;
    Bound: Cardinal;
    Stage: TRHIShaderStage;
    EntryPointName: String;
    Bindings: TSPIRVReflectedBindingArray;
    StageIO: TSPIRVReflectedStageIOArray;
    HasPushConstants: Boolean;
    PushConstantOffset: Cardinal;
    PushConstantSize: Cardinal;
    PushConstantName: String;

    function FindBinding(const ASetIndex, ABinding: Cardinal;
      out AFound: TSPIRVReflectedBinding): Boolean;
    function FindStageInput(const ALocation: Cardinal;
      out AFound: TSPIRVReflectedStageIO): Boolean;
    function FindStageOutput(const ALocation: Cardinal;
      out AFound: TSPIRVReflectedStageIO): Boolean;
  end;

  { Thread-safe GLSL-to-SPIR-V compiler with memory and disk caching. }
  TCastleShaderCompiler = class
  private
    class var FInstance: TCastleShaderCompiler;
  private
    FShadercLib: TDynLib;
    FCompilerHandle: Pointer;
    FOptionsHandle: Pointer;
    FLock: TCriticalSection;
    FMemoryCache: {$ifdef FPC}specialize{$endif} TDictionary<UInt64, TSPIRVBytecode>;
    FDiskCacheEnabled: Boolean;
    FDiskCacheBaseUrl: String;

    procedure LoadShadercLibrary;
    procedure UnloadShadercLibrary;
    function GetCacheFileUrl(const AHash: UInt64; const AStage: TRHIShaderStage): String;
    function TryLoadFromDiskCache(const AHash: UInt64; const AStage: TRHIShaderStage;
      out ASPIRV: TSPIRVBytecode): Boolean;
    procedure SaveToDiskCache(const AHash: UInt64; const AStage: TRHIShaderStage;
      const ASPIRV: TSPIRVBytecode);
    function CompileGLSLToSPIRVInternal(const AStage: TRHIShaderStage;
      const AGLSLSource, ADebugName: String): TSPIRVBytecode;
  public
    constructor Create;
    destructor Destroy; override;

    { Compiles GLSL #version 450 source code into SPIR-V bytecode, or retrieves
      it immediately from memory/disk cache if the FNV-1a hash matches. }
    function GetOrCompileSPIRV(const AStage: TRHIShaderStage;
      const AGLSLSource: String; const ADebugName: String = 'castle_shader'): TSPIRVBytecode;

    { Pre-warms a single GLSL 450 shader stage (compiles and caches to disk if
      libshaderc is available) and returns its deterministic 64-bit FNV-1a hash. }
    function PrewarmShaderSource(const AStage: TRHIShaderStage;
      const AGLSLSource: String; const ADebugName: String = 'prewarmed_shader'): UInt64;

    { Pre-warms known core engine shaders (3D forward pass vertex/fragment,
      depth-only shadow pass, and post-processing screen effect shaders)
      and returns the array of their deterministic source hashes. }
    function PrewarmCoreEngineShaders: TUInt64Array;

    { Clears all cached SPIR-V binaries from memory (and optionally disk). }
    procedure ClearCache(const AlsoClearDisk: Boolean = False);

    { True if libshaderc_shared was found and initialized.
      Even if False, pre-cached .spv files from disk/package can still be loaded! }
    function IsRuntimeCompilationAvailable: Boolean;

    property DiskCacheEnabled: Boolean read FDiskCacheEnabled write FDiskCacheEnabled default True;

    class function Instance: TCastleShaderCompiler;
    class destructor DestroyClass;
  end;

{ Pure Pascal SPIR-V binary header & instruction stream inspector.
  Works with zero external C/C++ dependencies (does not require libshaderc),
  allowing pre-compiled .spv shaders to be reflected and validated on any platform. }
function InspectSPIRVBytecode(const AData: Pointer; const ASizeInBytes: PtrUInt;
  out AInfo: TSPIRVReflectionInfo): Boolean; overload;
function InspectSPIRVBytecode(const ABytecode: TSPIRVBytecode;
  out AInfo: TSPIRVReflectionInfo): Boolean; overload;

{ Validates that all descriptor bindings referenced in the reflected SPIR-V module
  for ASetIndex match the expected RHI descriptor set layout bindings.
  Returns True if valid; returns False and populates ADiagnosticMessage on mismatch. }
function ValidateSPIRVDescriptorBindings(const AInfo: TSPIRVReflectionInfo;
  const ASetIndex: Cardinal;
  const AExpectedBindings: array of TRHIDescriptorBindingDesc;
  out ADiagnosticMessage: String): Boolean;

implementation

{ ---------------------------------------------------------------------------- }
{ Flat C-ABI Bindings for Google libshaderc_shared                             }
{ ---------------------------------------------------------------------------- }

type
  PShadercCompiler = Pointer;
  PShadercCompileOptions = Pointer;
  PShadercCompilationResult = Pointer;

  TShadercShaderKind = Integer;
  TShadercCompilationStatus = Integer;
  TShadercOptimizationLevel = Integer;
  TShadercTargetEnv = Integer;
  TShadercEnvVersion = UInt32;

const
  { shaderc_shader_kind }
  shaderc_vertex_shader   = 0;
  shaderc_fragment_shader = 1;
  shaderc_compute_shader  = 2;
  shaderc_geometry_shader = 3;

  { shaderc_compilation_status }
  shaderc_compilation_status_success            = 0;
  shaderc_compilation_status_invalid_stage      = 1;
  shaderc_compilation_status_compilation_error  = 2;
  shaderc_compilation_status_internal_error     = 3;
  shaderc_compilation_status_null_result_object = 4;

  { shaderc_optimization_level }
  shaderc_optimization_level_zero        = 0;
  shaderc_optimization_level_size        = 1;
  shaderc_optimization_level_performance = 2;

  { shaderc_target_env & shaderc_env_version }
  shaderc_target_env_vulkan         = 0;
  shaderc_env_version_vulkan_1_3    = (UInt32(1) shl 22) or (3 shl 12);

  { On-disk cache file magic header ('CSPV' + Version 1) }
  SPIRV_CACHE_FILE_MAGIC: UInt32   = $56505343; // 'CSPV'
  SPIRV_CACHE_FILE_VERSION: UInt32 = 1;
  SPIRV_MAGIC_NUMBER: UInt32       = $07230203;

type
  TCastleSPIRVCacheHeader = packed record
    FileMagic: UInt32;
    CacheVersion: UInt32;
    SourceHash: UInt64;
    Stage: UInt32;
    BytecodeSize: UInt32;
  end;

var
  shaderc_compiler_initialize: function(): PShadercCompiler; cdecl;
  shaderc_compiler_release: procedure(Compiler: PShadercCompiler); cdecl;

  shaderc_compile_options_initialize: function(): PShadercCompileOptions; cdecl;
  shaderc_compile_options_release: procedure(Options: PShadercCompileOptions); cdecl;
  shaderc_compile_options_set_optimization_level: procedure(
    Options: PShadercCompileOptions; Level: TShadercOptimizationLevel); cdecl;
  shaderc_compile_options_set_target_env: procedure(
    Options: PShadercCompileOptions; Target: TShadercTargetEnv; Version: TShadercEnvVersion); cdecl;
  shaderc_compile_options_set_generate_debug_info: procedure(
    Options: PShadercCompileOptions); cdecl;

  shaderc_compile_into_spv: function(
    const Compiler: PShadercCompiler;
    const SourceText: PAnsiChar;
    SourceTextSize: PtrUInt;
    ShaderKind: TShadercShaderKind;
    const InputFileName: PAnsiChar;
    const EntryPointName: PAnsiChar;
    const AdditionalOptions: PShadercCompileOptions): PShadercCompilationResult; cdecl;

  shaderc_result_release: procedure(Res: PShadercCompilationResult); cdecl;
  shaderc_result_get_length: function(const Res: PShadercCompilationResult): PtrUInt; cdecl;
  shaderc_result_get_num_warnings: function(const Res: PShadercCompilationResult): PtrUInt; cdecl;
  shaderc_result_get_num_errors: function(const Res: PShadercCompilationResult): PtrUInt; cdecl;
  shaderc_result_get_compilation_status: function(
    const Res: PShadercCompilationResult): TShadercCompilationStatus; cdecl;
  shaderc_result_get_bytes: function(const Res: PShadercCompilationResult): PByte; cdecl;
  shaderc_result_get_error_message: function(const Res: PShadercCompilationResult): PAnsiChar; cdecl;

{ ---------------------------------------------------------------------------- }
{ TCastleShaderCompiler                                                        }
{ ---------------------------------------------------------------------------- }

constructor TCastleShaderCompiler.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FMemoryCache := {$ifdef FPC}specialize{$endif} TDictionary<UInt64, TSPIRVBytecode>.Create;
  FDiskCacheEnabled := True;
  FDiskCacheBaseUrl := 'castle-config:/shader_cache/';

  LoadShadercLibrary;
end;

destructor TCastleShaderCompiler.Destroy;
begin
  UnloadShadercLibrary;
  FreeAndNil(FMemoryCache);
  FreeAndNil(FLock);
  inherited;
end;

class function TCastleShaderCompiler.Instance: TCastleShaderCompiler;
begin
  if FInstance = nil then
    FInstance := TCastleShaderCompiler.Create;
  Result := FInstance;
end;

class destructor TCastleShaderCompiler.DestroyClass;
begin
  FreeAndNil(FInstance);
end;

procedure TCastleShaderCompiler.LoadShadercLibrary;
const
  {$if defined(MSWINDOWS)}
  ShadercLibName = 'shaderc_shared.dll';
  {$elseif defined(DARWIN)}
  ShadercLibName = 'libshaderc_shared.1.dylib';
  {$else}
  ShadercLibName = 'libshaderc_shared.so.1';
  {$endif}
begin
  FShadercLib := TDynLib.Load(ShadercLibName, False);
  {$ifdef UNIX}
  if FShadercLib = nil then
    FShadercLib := TDynLib.Load('libshaderc_shared.so', False);
  {$endif}

  if FShadercLib = nil then
  begin
    WritelnLog('RHI/ShaderCompiler',
      'libshaderc_shared not found. Runtime GLSL-to-SPIR-V compilation disabled; relying on pre-cached .spv files.');
    Exit;
  end;

  FShadercLib.SymbolError := seRaise;
  Pointer(shaderc_compiler_initialize) := FShadercLib.Symbol('shaderc_compiler_initialize');
  Pointer(shaderc_compiler_release) := FShadercLib.Symbol('shaderc_compiler_release');
  Pointer(shaderc_compile_options_initialize) := FShadercLib.Symbol('shaderc_compile_options_initialize');
  Pointer(shaderc_compile_options_release) := FShadercLib.Symbol('shaderc_compile_options_release');
  Pointer(shaderc_compile_options_set_optimization_level) := FShadercLib.Symbol('shaderc_compile_options_set_optimization_level');
  Pointer(shaderc_compile_options_set_target_env) := FShadercLib.Symbol('shaderc_compile_options_set_target_env');
  Pointer(shaderc_compile_options_set_generate_debug_info) := FShadercLib.Symbol('shaderc_compile_options_set_generate_debug_info');
  Pointer(shaderc_compile_into_spv) := FShadercLib.Symbol('shaderc_compile_into_spv');
  Pointer(shaderc_result_release) := FShadercLib.Symbol('shaderc_result_release');
  Pointer(shaderc_result_get_length) := FShadercLib.Symbol('shaderc_result_get_length');
  Pointer(shaderc_result_get_num_warnings) := FShadercLib.Symbol('shaderc_result_get_num_warnings');
  Pointer(shaderc_result_get_num_errors) := FShadercLib.Symbol('shaderc_result_get_num_errors');
  Pointer(shaderc_result_get_compilation_status) := FShadercLib.Symbol('shaderc_result_get_compilation_status');
  Pointer(shaderc_result_get_bytes) := FShadercLib.Symbol('shaderc_result_get_bytes');
  Pointer(shaderc_result_get_error_message) := FShadercLib.Symbol('shaderc_result_get_error_message');

  FCompilerHandle := shaderc_compiler_initialize();
  FOptionsHandle := shaderc_compile_options_initialize();

  if (FCompilerHandle <> nil) and (FOptionsHandle <> nil) then
  begin
    shaderc_compile_options_set_target_env(
      FOptionsHandle, shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_3);
    shaderc_compile_options_set_optimization_level(
      FOptionsHandle, shaderc_optimization_level_performance);
    {$ifdef DEBUG}
    shaderc_compile_options_set_generate_debug_info(FOptionsHandle);
    {$endif}
  end;
end;

procedure TCastleShaderCompiler.UnloadShadercLibrary;
begin
  if FOptionsHandle <> nil then
  begin
    shaderc_compile_options_release(FOptionsHandle);
    FOptionsHandle := nil;
  end;
  if FCompilerHandle <> nil then
  begin
    shaderc_compiler_release(FCompilerHandle);
    FCompilerHandle := nil;
  end;
  FreeAndNil(FShadercLib);
end;

function TCastleShaderCompiler.IsRuntimeCompilationAvailable: Boolean;
begin
  Result := (FShadercLib <> nil) and (FCompilerHandle <> nil);
end;

function TCastleShaderCompiler.GetCacheFileUrl(const AHash: UInt64;
  const AStage: TRHIShaderStage): String;
const
  StageExt: array[TRHIShaderStage] of String = ('vert', 'frag', 'geom', 'comp');
begin
  Result := FDiskCacheBaseUrl + IntToHex(AHash, 16) + '.' + StageExt[AStage] + '.spv';
end;

function TCastleShaderCompiler.TryLoadFromDiskCache(const AHash: UInt64;
  const AStage: TRHIShaderStage; out ASPIRV: TSPIRVBytecode): Boolean;
var
  CacheUrl: String;
  Stream: TStream;
  Header: TCastleSPIRVCacheHeader;
  FirstWord: UInt32;
begin
  Result := False;
  if not FDiskCacheEnabled then Exit;

  CacheUrl := GetCacheFileUrl(AHash, AStage);
  if not UriFileExists(CacheUrl) then Exit;

  try
    Stream := Download(CacheUrl, []);
    try
      if Stream.Size <= SizeOf(TCastleSPIRVCacheHeader) then Exit;
      Stream.ReadBuffer(Header, SizeOf(Header));

      { Validate cache header and ensure SPIR-V word alignment (multiple of 4 bytes) }
      if (Header.FileMagic <> SPIRV_CACHE_FILE_MAGIC) or
         (Header.CacheVersion <> SPIRV_CACHE_FILE_VERSION) or
         (Header.SourceHash <> AHash) or
         (Header.Stage <> UInt32(Ord(AStage))) or
         (Header.BytecodeSize = 0) or
         ((Header.BytecodeSize mod 4) <> 0) then
        Exit;

      SetLength(ASPIRV, Header.BytecodeSize);
      Stream.ReadBuffer(ASPIRV[0], Header.BytecodeSize);

      { Verify the SPIR-V magic word ($07230203) at the start of the payload }
      Move(ASPIRV[0], FirstWord, SizeOf(UInt32));
      if FirstWord <> SPIRV_MAGIC_NUMBER then
      begin
        SetLength(ASPIRV, 0);
        Exit;
      end;

      Result := True;
    finally
      FreeAndNil(Stream);
    end;
  except
    on E: Exception do
    begin
      WritelnWarning('RHI/ShaderCompiler', 'Failed to read cached SPIR-V (%s): %s',
        [CacheUrl, E.Message]);
      Result := False;
    end;
  end;
end;

procedure TCastleShaderCompiler.SaveToDiskCache(const AHash: UInt64;
  const AStage: TRHIShaderStage; const ASPIRV: TSPIRVBytecode);
var
  CacheUrl: String;
  Stream: TStream;
  Header: TCastleSPIRVCacheHeader;
begin
  if (not FDiskCacheEnabled) or (Length(ASPIRV) = 0) then Exit;

  CacheUrl := GetCacheFileUrl(AHash, AStage);
  try
    Header.FileMagic := SPIRV_CACHE_FILE_MAGIC;
    Header.CacheVersion := SPIRV_CACHE_FILE_VERSION;
    Header.SourceHash := AHash;
    Header.Stage := UInt32(Ord(AStage));
    Header.BytecodeSize := UInt32(Length(ASPIRV));

    Stream := UrlSaveStream(CacheUrl);
    try
      Stream.WriteBuffer(Header, SizeOf(Header));
      Stream.WriteBuffer(ASPIRV[0], Length(ASPIRV));
    finally
      FreeAndNil(Stream);
    end;
  except
    on E: Exception do
      WritelnWarning('RHI/ShaderCompiler', 'Could not write SPIR-V disk cache (%s): %s',
        [CacheUrl, E.Message]);
  end;
end;

function TCastleShaderCompiler.CompileGLSLToSPIRVInternal(
  const AStage: TRHIShaderStage; const AGLSLSource, ADebugName: String): TSPIRVBytecode;
var
  Kind: TShadercShaderKind;
  AnsiSrc, AnsiName: AnsiString;
  CompRes: PShadercCompilationResult;
  Status: TShadercCompilationStatus;
  ByteLen: PtrUInt;
  BytePtr: PByte;
  ErrMsg: String;
begin
  if not IsRuntimeCompilationAvailable then
    raise ERHIShaderCompilationError.CreateFmt(
      'Cannot compile shader "%s": libshaderc_shared is not loaded and shader was not found in disk cache.',
      [ADebugName]);

  case AStage of
    ssVertex:   Kind := shaderc_vertex_shader;
    ssFragment: Kind := shaderc_fragment_shader;
    ssGeometry: Kind := shaderc_geometry_shader;
    ssCompute:  Kind := shaderc_compute_shader;
    else        Kind := shaderc_vertex_shader;
  end;

  AnsiSrc := AnsiString(AGLSLSource);
  AnsiName := AnsiString(ADebugName);

  CompRes := shaderc_compile_into_spv(
    FCompilerHandle,
    PAnsiChar(AnsiSrc),
    Length(AnsiSrc),
    Kind,
    PAnsiChar(AnsiName),
    'main',
    FOptionsHandle);

  if CompRes = nil then
    raise ERHIShaderCompilationError.CreateFmt('shaderc_compile_into_spv returned nil for %s', [ADebugName]);

  try
    Status := shaderc_result_get_compilation_status(CompRes);
    if Status <> shaderc_compilation_status_success then
    begin
      ErrMsg := String(shaderc_result_get_error_message(CompRes));
      raise ERHIShaderCompilationError.CreateFmt(
        'Vulkan SPIR-V compilation failed for "%s" (status %d):%s%s%s--- Source ---%s%s',
        [ADebugName, Status, LineEnding, ErrMsg, LineEnding, LineEnding, AGLSLSource]);
    end;

    if shaderc_result_get_num_warnings(CompRes) > 0 then
    begin
      ErrMsg := String(shaderc_result_get_error_message(CompRes));
      WritelnWarning('RHI/ShaderCompiler', 'Warnings compiling "%s": %s', [ADebugName, ErrMsg]);
    end;

    ByteLen := shaderc_result_get_length(CompRes);
    BytePtr := shaderc_result_get_bytes(CompRes);

    SetLength(Result, ByteLen);
    if ByteLen > 0 then
      Move(BytePtr^, Result[0], ByteLen);
  finally
    shaderc_result_release(CompRes);
  end;
end;

function TCastleShaderCompiler.GetOrCompileSPIRV(const AStage: TRHIShaderStage;
  const AGLSLSource: String; const ADebugName: String): TSPIRVBytecode;
var
  SourceHash: UInt64;
begin
  SourceHash := TCastleShaderGeneratorRHI.ComputeSourceHash(AGLSLSource);

  FLock.Acquire;
  try
    if FMemoryCache.TryGetValue(SourceHash, Result) then
      Exit;

    if TryLoadFromDiskCache(SourceHash, AStage, Result) then
    begin
      FMemoryCache.Add(SourceHash, Result);
      Exit;
    end;

    Result := CompileGLSLToSPIRVInternal(AStage, AGLSLSource, ADebugName);
    FMemoryCache.Add(SourceHash, Result);
    SaveToDiskCache(SourceHash, AStage, Result);
  finally
    FLock.Release;
  end;
end;

function TCastleShaderCompiler.PrewarmShaderSource(const AStage: TRHIShaderStage;
  const AGLSLSource: String; const ADebugName: String): UInt64;
var
  DummySPIRV: TSPIRVBytecode;
begin
  Result := TCastleShaderGeneratorRHI.ComputeSourceHash(AGLSLSource);
  if IsRuntimeCompilationAvailable then
    DummySPIRV := GetOrCompileSPIRV(AStage, AGLSLSource, ADebugName)
  else
    TryLoadFromDiskCache(Result, AStage, DummySPIRV);
end;

function TCastleShaderCompiler.PrewarmCoreEngineShaders: TUInt64Array;
var
  Gen: TCastleShaderGeneratorRHI;
  ForwardVS, ForwardFS, DepthOnlyVS, ScreenVS, ScreenFS: String;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    ForwardVS := Gen.FinalizeVertexShaderSource(
      Gen.GeneratePreamble(ssVertex) +
      'void main() {' + LineEnding +
      '  castle_vertex_eye = castle_ModelViewMatrix * castle_Vertex;' + LineEnding +
      '  castle_normal_eye = normalize(castle_NormalMatrix * castle_Normal);' + LineEnding +
      '  castle_tex_coord0 = castle_MultiTexCoord0;' + LineEnding +
      '  gl_Position = castle_ProjectionMatrix * castle_vertex_eye;' + LineEnding +
      '}');
    ForwardFS := Gen.GeneratePreamble(ssFragment) +
      'void main() {' + LineEnding +
      '  castle_FragColor = castle_MaterialBaseColor;' + LineEnding +
      '}';
    DepthOnlyVS := Gen.FinalizeVertexShaderSource(
      Gen.GeneratePreamble(ssVertex) +
      'void main() {' + LineEnding +
      '  gl_Position = castle_ProjectionMatrix * (castle_ModelViewMatrix * castle_Vertex);' + LineEnding +
      '}');
    ScreenVS := Gen.FinalizeVertexShaderSource(
      Gen.GenerateScreenEffectPreamble(ssVertex, True) +
      'void main() {' + LineEnding +
      '  v_tex_coord = tex_coord;' + LineEnding +
      '  gl_Position = vec4(vertex * 2.0 - 1.0, 0.0, 1.0);' + LineEnding +
      '}');
    ScreenFS := Gen.GenerateScreenEffectPreamble(ssFragment, True) +
      'void main() {' + LineEnding +
      '  castle_FragColor = texture(screen, tex_coord);' + LineEnding +
      '}';

    SetLength(Result, 5);
    Result[0] := PrewarmShaderSource(ssVertex, ForwardVS, 'core_forward_vs');
    Result[1] := PrewarmShaderSource(ssFragment, ForwardFS, 'core_forward_fs');
    Result[2] := PrewarmShaderSource(ssVertex, DepthOnlyVS, 'core_shadow_depth_vs');
    Result[3] := PrewarmShaderSource(ssVertex, ScreenVS, 'core_screen_effect_vs');
    Result[4] := PrewarmShaderSource(ssFragment, ScreenFS, 'core_screen_effect_fs');
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TCastleShaderCompiler.ClearCache(const AlsoClearDisk: Boolean);
begin
  FLock.Acquire;
  try
    FMemoryCache.Clear;
    if AlsoClearDisk and UriFileExists(FDiskCacheBaseUrl) then
      RemoveNonEmptyDir(UriToFilenameSafe(FDiskCacheBaseUrl), True);
  finally
    FLock.Release;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ Pure Pascal SPIR-V Binary Reflection & Descriptor Validation                 }
{ ---------------------------------------------------------------------------- }

const
  SPIRV_MAGIC_BYTESWAPPED: UInt32 = $03022307;
  SPIRV_MAX_TRACKED_IDS           = 262144;

  { SPIR-V Opcodes }
  SpvOpName            = 5;
  SpvOpMemberName      = 6;
  SpvOpEntryPoint      = 15;
  SpvOpTypeBool        = 20;
  SpvOpTypeInt         = 21;
  SpvOpTypeFloat       = 22;
  SpvOpTypeVector      = 23;
  SpvOpTypeMatrix      = 24;
  SpvOpTypeImage       = 25;
  SpvOpTypeSampler     = 26;
  SpvOpTypeSampledImage = 27;
  SpvOpTypeArray       = 28;
  SpvOpTypeRuntimeArray = 29;
  SpvOpTypeStruct      = 30;
  SpvOpTypePointer     = 32;
  SpvOpConstant        = 43;
  SpvOpVariable        = 59;
  SpvOpDecorate        = 71;
  SpvOpMemberDecorate  = 72;

  { SPIR-V ExecutionModel }
  SpvExecutionModelVertex    = 0;
  SpvExecutionModelGeometry  = 3;
  SpvExecutionModelFragment  = 4;
  SpvExecutionModelGLCompute = 5;

  { SPIR-V StorageClass }
  SpvStorageClassUniformConstant = 0;
  SpvStorageClassInput           = 1;
  SpvStorageClassUniform         = 2;
  SpvStorageClassOutput          = 3;
  SpvStorageClassPushConstant    = 9;
  SpvStorageClassStorageBuffer   = 12;

  { SPIR-V Decorations }
  SpvDecorationBlock         = 2;
  SpvDecorationBufferBlock   = 3;
  SpvDecorationBuiltIn       = 11;
  SpvDecorationLocation      = 30;
  SpvDecorationBinding       = 33;
  SpvDecorationDescriptorSet = 34;
  SpvDecorationOffset        = 35;

type
  TSPIRVTypeKind = (
    stkNone,
    stkBool,
    stkInt,
    stkFloat,
    stkVector,
    stkMatrix,
    stkImage,
    stkSampler,
    stkSampledImage,
    stkArray,
    stkRuntimeArray,
    stkStruct,
    stkPointer
  );

  TSPIRVIdInfo = record
    Name: String;
    TypeKind: TSPIRVTypeKind;
    BitWidth: Cardinal;
    ComponentCount: Cardinal;
    ElementTypeId: Cardinal;
    ArrayLengthId: Cardinal;
    StorageClass: Cardinal;
    ImageDim: Cardinal;
    ImageSampled: Cardinal;
    ConstValue: Cardinal;
    HasConstValue: Boolean;
    HasDescriptorSet: Boolean;
    DescriptorSet: Cardinal;
    HasBinding: Boolean;
    Binding: Cardinal;
    HasLocation: Boolean;
    Location: Cardinal;
    IsBlock: Boolean;
    IsBufferBlock: Boolean;
    IsBuiltIn: Boolean;
    StructMemberTypeIds: array of Cardinal;
    StructMemberOffsets: array of Cardinal;
    StructMemberHasOffset: array of Boolean;
    IsVariable: Boolean;
    VarTypeId: Cardinal;
  end;

function TSPIRVReflectionInfo.FindBinding(const ASetIndex, ABinding: Cardinal;
  out AFound: TSPIRVReflectedBinding): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Bindings) do
    if (Bindings[I].SetIndex = ASetIndex) and (Bindings[I].Binding = ABinding) then
    begin
      AFound := Bindings[I];
      Exit(True);
    end;
  FillChar(AFound, SizeOf(AFound), 0);
  Result := False;
end;

function TSPIRVReflectionInfo.FindStageInput(const ALocation: Cardinal;
  out AFound: TSPIRVReflectedStageIO): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(StageIO) do
    if (not StageIO[I].IsOutput) and (StageIO[I].Location = ALocation) then
    begin
      AFound := StageIO[I];
      Exit(True);
    end;
  FillChar(AFound, SizeOf(AFound), 0);
  Result := False;
end;

function TSPIRVReflectionInfo.FindStageOutput(const ALocation: Cardinal;
  out AFound: TSPIRVReflectedStageIO): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(StageIO) do
    if StageIO[I].IsOutput and (StageIO[I].Location = ALocation) then
    begin
      AFound := StageIO[I];
      Exit(True);
    end;
  FillChar(AFound, SizeOf(AFound), 0);
  Result := False;
end;

function ReadSPIRVWord(const AWords: PUInt32; const AIndex: Cardinal;
  const AByteSwapped: Boolean): UInt32; inline;
begin
  Result := AWords[AIndex];
  if AByteSwapped then
    Result := SwapEndian(Result);
end;

function ReadSPIRVString(const AWords: PUInt32; const AStartWord, AEndWord: Cardinal;
  const AByteSwapped: Boolean; out ANextWord: Cardinal): String;
var
  WIndex, ByteIdx: Cardinal;
  WordVal: UInt32;
  ChByte: Byte;
begin
  Result := '';
  WIndex := AStartWord;
  while WIndex < AEndWord do
  begin
    WordVal := ReadSPIRVWord(AWords, WIndex, AByteSwapped);
    Inc(WIndex);
    for ByteIdx := 0 to 3 do
    begin
      ChByte := Byte((WordVal shr (ByteIdx * 8)) and $FF);
      if ChByte = 0 then
      begin
        ANextWord := WIndex;
        Exit;
      end;
      Result := Result + Chr(ChByte);
    end;
  end;
  ANextWord := WIndex;
end;

function ComputeSPIRVTypeByteSize(const AIds: array of TSPIRVIdInfo;
  const ATypeId: Cardinal; const ADepth: Integer = 0): Cardinal;
var
  ElemSize, ArrCount, MaxEnd, MemberOffset, MemberSize: Cardinal;
  M: Integer;
begin
  Result := 0;
  if (ADepth > 16) or (ATypeId = 0) or (ATypeId >= Cardinal(Length(AIds))) then
    Exit;

  case AIds[ATypeId].TypeKind of
    stkBool:
      Result := 4;
    stkInt, stkFloat:
      begin
        Result := AIds[ATypeId].BitWidth div 8;
        if Result = 0 then
          Result := 4;
      end;
    stkVector, stkMatrix:
      begin
        ElemSize := ComputeSPIRVTypeByteSize(AIds, AIds[ATypeId].ElementTypeId, ADepth + 1);
        Result := AIds[ATypeId].ComponentCount * ElemSize;
      end;
    stkArray:
      begin
        ElemSize := ComputeSPIRVTypeByteSize(AIds, AIds[ATypeId].ElementTypeId, ADepth + 1);
        ArrCount := 1;
        if (AIds[ATypeId].ArrayLengthId > 0) and
           (AIds[ATypeId].ArrayLengthId < Cardinal(Length(AIds))) and
           AIds[AIds[ATypeId].ArrayLengthId].HasConstValue and
           (AIds[AIds[ATypeId].ArrayLengthId].ConstValue > 0) then
          ArrCount := AIds[AIds[ATypeId].ArrayLengthId].ConstValue;
        Result := ArrCount * ElemSize;
      end;
    stkStruct:
      begin
        MaxEnd := 0;
        for M := 0 to High(AIds[ATypeId].StructMemberTypeIds) do
        begin
          MemberSize := ComputeSPIRVTypeByteSize(
            AIds, AIds[ATypeId].StructMemberTypeIds[M], ADepth + 1);
          if (M < Length(AIds[ATypeId].StructMemberHasOffset)) and
             AIds[ATypeId].StructMemberHasOffset[M] then
            MemberOffset := AIds[ATypeId].StructMemberOffsets[M]
          else
            MemberOffset := MaxEnd;
          if MemberOffset + MemberSize > MaxEnd then
            MaxEnd := MemberOffset + MemberSize;
        end;
        Result := MaxEnd;
      end;
    else
      Result := 0;
  end;
end;

function InspectSPIRVBytecode(const AData: Pointer; const ASizeInBytes: PtrUInt;
  out AInfo: TSPIRVReflectionInfo): Boolean;
var
  Words: PUInt32;
  TotalWords, Pos, Word0, WordCount, Opcode, InstEnd, NextWord: Cardinal;
  Magic, VersionWord, MaxId, TargetId, MemberIdx, Deco, ResId, ResTypeId: Cardinal;
  ExecModel, PtrTypeId, PointeeId, BaseTypeId, VarStorageClass, DescCount: Cardinal;
  ByteSwapped, HasValidDescType: Boolean;
  Ids: array of TSPIRVIdInfo;
  I, J: Integer;
  NewBinding, TempBinding: TSPIRVReflectedBinding;
  NewIO, TempIO: TSPIRVReflectedStageIO;
  DescType: TRHIDescriptorType;
begin
  AInfo := Default(TSPIRVReflectionInfo);
  if (AData = nil) or (ASizeInBytes < 20) or ((ASizeInBytes mod 4) <> 0) then
    Exit(False);

  Words := PUInt32(AData);
  TotalWords := ASizeInBytes div 4;

  Magic := Words[0];
  if Magic = SPIRV_MAGIC_NUMBER then
    ByteSwapped := False
  else
  if Magic = SPIRV_MAGIC_BYTESWAPPED then
    ByteSwapped := True
  else
    Exit(False);

  VersionWord := ReadSPIRVWord(Words, 1, ByteSwapped);
  AInfo.ByteSwapped := ByteSwapped;
  AInfo.VersionMajor := Byte((VersionWord shr 16) and $FF);
  AInfo.VersionMinor := Byte((VersionWord shr 8) and $FF);
  AInfo.GeneratorMagic := ReadSPIRVWord(Words, 2, ByteSwapped);
  AInfo.Bound := ReadSPIRVWord(Words, 3, ByteSwapped);
  AInfo.Stage := ssVertex;
  AInfo.EntryPointName := 'main';

  if AInfo.Bound = 0 then
    Exit(False);

  MaxId := AInfo.Bound;
  if MaxId > SPIRV_MAX_TRACKED_IDS then
    MaxId := SPIRV_MAX_TRACKED_IDS;
  SetLength(Ids, MaxId);

  Pos := 5;
  while Pos < TotalWords do
  begin
    Word0 := ReadSPIRVWord(Words, Pos, ByteSwapped);
    WordCount := Word0 shr 16;
    Opcode := Word0 and $FFFF;

    if (WordCount = 0) or (Pos + WordCount > TotalWords) then
      Exit(False);

    InstEnd := Pos + WordCount;

    case Opcode of
      SpvOpEntryPoint:
        if WordCount >= 4 then
        begin
          ExecModel := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          case ExecModel of
            SpvExecutionModelVertex:    AInfo.Stage := ssVertex;
            SpvExecutionModelGeometry:  AInfo.Stage := ssGeometry;
            SpvExecutionModelFragment:  AInfo.Stage := ssFragment;
            SpvExecutionModelGLCompute: AInfo.Stage := ssCompute;
          end;
          AInfo.EntryPointName := ReadSPIRVString(Words, Pos + 3, InstEnd, ByteSwapped, NextWord);
        end;

      SpvOpName:
        if WordCount >= 3 then
        begin
          TargetId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if TargetId < MaxId then
            Ids[TargetId].Name := ReadSPIRVString(Words, Pos + 2, InstEnd, ByteSwapped, NextWord);
        end;

      SpvOpDecorate:
        if WordCount >= 3 then
        begin
          TargetId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          Deco := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          if TargetId < MaxId then
          begin
            case Deco of
              SpvDecorationBlock:
                Ids[TargetId].IsBlock := True;
              SpvDecorationBufferBlock:
                Ids[TargetId].IsBufferBlock := True;
              SpvDecorationBuiltIn:
                Ids[TargetId].IsBuiltIn := True;
              SpvDecorationLocation:
                if WordCount >= 4 then
                begin
                  Ids[TargetId].HasLocation := True;
                  Ids[TargetId].Location := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
                end;
              SpvDecorationBinding:
                if WordCount >= 4 then
                begin
                  Ids[TargetId].HasBinding := True;
                  Ids[TargetId].Binding := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
                end;
              SpvDecorationDescriptorSet:
                if WordCount >= 4 then
                begin
                  Ids[TargetId].HasDescriptorSet := True;
                  Ids[TargetId].DescriptorSet := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
                end;
            end;
          end;
        end;

      SpvOpMemberDecorate:
        if WordCount >= 4 then
        begin
          TargetId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          MemberIdx := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          Deco := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          if (TargetId < MaxId) and (MemberIdx < 4096) then
          begin
            if Deco = SpvDecorationBuiltIn then
              Ids[TargetId].IsBuiltIn := True
            else
            if (Deco = SpvDecorationOffset) and (WordCount >= 5) then
            begin
              if MemberIdx >= Cardinal(Length(Ids[TargetId].StructMemberOffsets)) then
              begin
                SetLength(Ids[TargetId].StructMemberOffsets, MemberIdx + 1);
                SetLength(Ids[TargetId].StructMemberHasOffset, MemberIdx + 1);
              end;
              Ids[TargetId].StructMemberOffsets[MemberIdx] :=
                ReadSPIRVWord(Words, Pos + 4, ByteSwapped);
              Ids[TargetId].StructMemberHasOffset[MemberIdx] := True;
            end;
          end;
        end;

      SpvOpTypeBool:
        if WordCount >= 2 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
            Ids[ResId].TypeKind := stkBool;
        end;

      SpvOpTypeInt:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkInt;
            Ids[ResId].BitWidth := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          end;
        end;

      SpvOpTypeFloat:
        if WordCount >= 3 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkFloat;
            Ids[ResId].BitWidth := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          end;
        end;

      SpvOpTypeVector:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkVector;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ComponentCount := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpTypeMatrix:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkMatrix;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ComponentCount := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpTypeImage:
        if WordCount >= 8 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkImage;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ImageDim := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
            Ids[ResId].ImageSampled := ReadSPIRVWord(Words, Pos + 7, ByteSwapped);
          end;
        end;

      SpvOpTypeSampler:
        if WordCount >= 2 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
            Ids[ResId].TypeKind := stkSampler;
        end;

      SpvOpTypeSampledImage:
        if WordCount >= 3 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkSampledImage;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          end;
        end;

      SpvOpTypeArray:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkArray;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ArrayLengthId := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpTypeRuntimeArray:
        if WordCount >= 3 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkRuntimeArray;
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          end;
        end;

      SpvOpTypeStruct:
        if WordCount >= 2 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkStruct;
            SetLength(Ids[ResId].StructMemberTypeIds, WordCount - 2);
            for I := 0 to Integer(WordCount) - 3 do
              Ids[ResId].StructMemberTypeIds[I] :=
                ReadSPIRVWord(Words, Pos + 2 + Cardinal(I), ByteSwapped);
          end;
        end;

      SpvOpTypePointer:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].TypeKind := stkPointer;
            Ids[ResId].StorageClass := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
            Ids[ResId].ElementTypeId := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpConstant:
        if WordCount >= 4 then
        begin
          ResId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].HasConstValue := True;
            Ids[ResId].ConstValue := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;

      SpvOpVariable:
        if WordCount >= 4 then
        begin
          ResTypeId := ReadSPIRVWord(Words, Pos + 1, ByteSwapped);
          ResId := ReadSPIRVWord(Words, Pos + 2, ByteSwapped);
          if ResId < MaxId then
          begin
            Ids[ResId].IsVariable := True;
            Ids[ResId].VarTypeId := ResTypeId;
            Ids[ResId].StorageClass := ReadSPIRVWord(Words, Pos + 3, ByteSwapped);
          end;
        end;
    end;

    Pos := InstEnd;
  end;

  { Resolve all OpVariable declarations into Bindings, PushConstants, and StageIO }
  for I := 1 to Integer(MaxId) - 1 do
    if Ids[I].IsVariable then
    begin
      VarStorageClass := Ids[I].StorageClass;
      PtrTypeId := Ids[I].VarTypeId;
      if (PtrTypeId > 0) and (PtrTypeId < MaxId) and
         (Ids[PtrTypeId].TypeKind = stkPointer) then
        PointeeId := Ids[PtrTypeId].ElementTypeId
      else
        PointeeId := PtrTypeId;

      if (PointeeId = 0) or (PointeeId >= MaxId) then
        Continue;

      DescCount := 1;
      BaseTypeId := PointeeId;
      if Ids[PointeeId].TypeKind = stkArray then
      begin
        BaseTypeId := Ids[PointeeId].ElementTypeId;
        if (Ids[PointeeId].ArrayLengthId > 0) and
           (Ids[PointeeId].ArrayLengthId < MaxId) and
           Ids[Ids[PointeeId].ArrayLengthId].HasConstValue then
          DescCount := Ids[Ids[PointeeId].ArrayLengthId].ConstValue;
      end else
      if Ids[PointeeId].TypeKind = stkRuntimeArray then
      begin
        BaseTypeId := Ids[PointeeId].ElementTypeId;
        DescCount := 0;
      end;

      if (BaseTypeId = 0) or (BaseTypeId >= MaxId) then
        Continue;

      case VarStorageClass of
        SpvStorageClassPushConstant:
          begin
            AInfo.HasPushConstants := True;
            AInfo.PushConstantOffset := 0;
            AInfo.PushConstantSize := ComputeSPIRVTypeByteSize(Ids, BaseTypeId);
            if Ids[I].Name <> '' then
              AInfo.PushConstantName := Ids[I].Name
            else
              AInfo.PushConstantName := Ids[BaseTypeId].Name;
          end;

        SpvStorageClassUniform,
        SpvStorageClassStorageBuffer,
        SpvStorageClassUniformConstant:
          if Ids[I].HasBinding or Ids[I].HasDescriptorSet then
          begin
            HasValidDescType := False;
            DescType := dtUniformBuffer;

            if VarStorageClass = SpvStorageClassStorageBuffer then
            begin
              DescType := dtStorageBuffer;
              HasValidDescType := True;
            end else
            if VarStorageClass = SpvStorageClassUniform then
            begin
              if Ids[BaseTypeId].IsBufferBlock then
                DescType := dtStorageBuffer
              else
                DescType := dtUniformBuffer;
              HasValidDescType := True;
            end else
            if VarStorageClass = SpvStorageClassUniformConstant then
            begin
              case Ids[BaseTypeId].TypeKind of
                stkSampledImage:
                  begin
                    DescType := dtCombinedImageSampler;
                    HasValidDescType := True;
                  end;
                stkSampler:
                  begin
                    DescType := dtSampler;
                    HasValidDescType := True;
                  end;
                stkImage:
                  begin
                    if Ids[BaseTypeId].ImageSampled = 2 then
                      DescType := dtStorageImage
                    else
                      DescType := dtSampledImage;
                    HasValidDescType := True;
                  end;
              end;
            end;

            if HasValidDescType then
            begin
              FillChar(NewBinding, SizeOf(NewBinding), 0);
              if Ids[I].HasDescriptorSet then
                NewBinding.SetIndex := Ids[I].DescriptorSet
              else
                NewBinding.SetIndex := 0;
              NewBinding.Binding := Ids[I].Binding;
              NewBinding.DescriptorType := DescType;
              NewBinding.Count := DescCount;
              if DescType in [dtUniformBuffer, dtStorageBuffer] then
                NewBinding.BlockSize := ComputeSPIRVTypeByteSize(Ids, BaseTypeId)
              else
                NewBinding.BlockSize := 0;
              if Ids[I].Name <> '' then
                NewBinding.Name := Ids[I].Name
              else
                NewBinding.Name := Ids[BaseTypeId].Name;

              SetLength(AInfo.Bindings, Length(AInfo.Bindings) + 1);
              AInfo.Bindings[High(AInfo.Bindings)] := NewBinding;
            end;
          end;

        SpvStorageClassInput,
        SpvStorageClassOutput:
          if Ids[I].HasLocation and (not Ids[I].IsBuiltIn) and
             (not Ids[BaseTypeId].IsBuiltIn) then
          begin
            FillChar(NewIO, SizeOf(NewIO), 0);
            NewIO.Location := Ids[I].Location;
            NewIO.IsOutput := VarStorageClass = SpvStorageClassOutput;
            if Ids[BaseTypeId].TypeKind in [stkVector, stkMatrix] then
              NewIO.ComponentCount := Ids[BaseTypeId].ComponentCount
            else
              NewIO.ComponentCount := 1;
            NewIO.Name := Ids[I].Name;

            SetLength(AInfo.StageIO, Length(AInfo.StageIO) + 1);
            AInfo.StageIO[High(AInfo.StageIO)] := NewIO;
          end;
      end;
    end;

  { Deterministic sort of Bindings by (SetIndex, Binding) }
  for I := 0 to High(AInfo.Bindings) - 1 do
    for J := I + 1 to High(AInfo.Bindings) do
      if (AInfo.Bindings[J].SetIndex < AInfo.Bindings[I].SetIndex) or
         ((AInfo.Bindings[J].SetIndex = AInfo.Bindings[I].SetIndex) and
          (AInfo.Bindings[J].Binding < AInfo.Bindings[I].Binding)) then
      begin
        TempBinding := AInfo.Bindings[I];
        AInfo.Bindings[I] := AInfo.Bindings[J];
        AInfo.Bindings[J] := TempBinding;
      end;

  { Deterministic sort of StageIO by (IsOutput, Location) }
  for I := 0 to High(AInfo.StageIO) - 1 do
    for J := I + 1 to High(AInfo.StageIO) do
      if (Ord(AInfo.StageIO[J].IsOutput) < Ord(AInfo.StageIO[I].IsOutput)) or
         ((AInfo.StageIO[J].IsOutput = AInfo.StageIO[I].IsOutput) and
          (AInfo.StageIO[J].Location < AInfo.StageIO[I].Location)) then
      begin
        TempIO := AInfo.StageIO[I];
        AInfo.StageIO[I] := AInfo.StageIO[J];
        AInfo.StageIO[J] := TempIO;
      end;

  AInfo.IsValid := True;
  Result := True;
end;

function InspectSPIRVBytecode(const ABytecode: TSPIRVBytecode;
  out AInfo: TSPIRVReflectionInfo): Boolean;
begin
  if Length(ABytecode) = 0 then
  begin
    AInfo := Default(TSPIRVReflectionInfo);
    Exit(False);
  end;
  Result := InspectSPIRVBytecode(@ABytecode[0], Length(ABytecode), AInfo);
end;

function DescriptorTypesCompatible(const ASPIRVType, ALayoutType: TRHIDescriptorType): Boolean;
begin
  if ASPIRVType = ALayoutType then
    Exit(True);
  { A SPIR-V Uniform block (dtUniformBuffer) can be bound to either a static UBO
    (dtUniformBuffer) or a dynamic-offset UBO (dtUniformBufferDynamic) in the RHI layout }
  if (ASPIRVType = dtUniformBuffer) and (ALayoutType = dtUniformBufferDynamic) then
    Exit(True);
  Result := False;
end;

function ValidateSPIRVDescriptorBindings(const AInfo: TSPIRVReflectionInfo;
  const ASetIndex: Cardinal;
  const AExpectedBindings: array of TRHIDescriptorBindingDesc;
  out ADiagnosticMessage: String): Boolean;
var
  I, J: Integer;
  ReflBind: TSPIRVReflectedBinding;
  FoundInLayout: Boolean;
begin
  ADiagnosticMessage := '';
  if not AInfo.IsValid then
  begin
    ADiagnosticMessage := 'SPIR-V reflection info is invalid (corrupted or empty SPIR-V binary).';
    Exit(False);
  end;

  for I := 0 to High(AInfo.Bindings) do
  begin
    ReflBind := AInfo.Bindings[I];
    if ReflBind.SetIndex <> ASetIndex then
      Continue;

    FoundInLayout := False;
    for J := 0 to High(AExpectedBindings) do
      if AExpectedBindings[J].Binding = ReflBind.Binding then
      begin
        FoundInLayout := True;
        if not DescriptorTypesCompatible(ReflBind.DescriptorType, AExpectedBindings[J].DescriptorType) then
        begin
          ADiagnosticMessage := Format(
            'SPIR-V descriptor type mismatch at set=%d, binding=%d ("%s"): shader expects Ord(TRHIDescriptorType)=%d, layout provides Ord(TRHIDescriptorType)=%d.',
            [ASetIndex, ReflBind.Binding, ReflBind.Name,
             Ord(ReflBind.DescriptorType), Ord(AExpectedBindings[J].DescriptorType)]);
          Exit(False);
        end;
        if not (AInfo.Stage in AExpectedBindings[J].StageFlags) then
        begin
          ADiagnosticMessage := Format(
            'SPIR-V stage visibility mismatch at set=%d, binding=%d ("%s"): layout StageFlags excludes shader stage Ord(TRHIShaderStage)=%d.',
            [ASetIndex, ReflBind.Binding, ReflBind.Name, Ord(AInfo.Stage)]);
          Exit(False);
        end;
        if (ReflBind.Count > 0) and (AExpectedBindings[J].Count < ReflBind.Count) then
        begin
          ADiagnosticMessage := Format(
            'SPIR-V descriptor count mismatch at set=%d, binding=%d ("%s"): shader requires array count %d, layout provides %d.',
            [ASetIndex, ReflBind.Binding, ReflBind.Name,
             ReflBind.Count, AExpectedBindings[J].Count]);
          Exit(False);
        end;
        Break;
      end;

    if not FoundInLayout then
    begin
      ADiagnosticMessage := Format(
        'SPIR-V shader references undeclared descriptor at set=%d, binding=%d ("%s") not present in RHI descriptor set layout.',
        [ASetIndex, ReflBind.Binding, ReflBind.Name]);
      Exit(False);
    end;
  end;

  Result := True;
end;

end.
