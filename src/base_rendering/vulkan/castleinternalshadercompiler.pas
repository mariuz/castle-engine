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
  CastleUtils, CastleDynLib, CastleFilesUtils, CastleFindFiles, CastleUriUtils, CastleDownload, CastleLog,
  CastleInternalRHI, CastleInternalShaderRHI, CastleInternalSPIRVReflection;

const
  DefaultDiskShaderCacheBaseUrl    = 'castle-config:/shader_cache/';
  DefaultBundledShaderCacheBaseUrl = 'castle-data:/shader_cache/';

type
  TSPIRVBytecode = CastleInternalSPIRVReflection.TSPIRVBytecode;
  TSPIRVReflectedBinding = CastleInternalSPIRVReflection.TSPIRVReflectedBinding;
  TSPIRVReflectedBindingArray = CastleInternalSPIRVReflection.TSPIRVReflectedBindingArray;
  TSPIRVReflectedStageIO = CastleInternalSPIRVReflection.TSPIRVReflectedStageIO;
  TSPIRVReflectedStageIOArray = CastleInternalSPIRVReflection.TSPIRVReflectedStageIOArray;
  TSPIRVReflectionInfo = CastleInternalSPIRVReflection.TSPIRVReflectionInfo;
  TUInt64Array = array of UInt64;

  { Runtime compiler backend selection mode for TCastleShaderCompiler }
  TShaderCompilerMode = (
    scmAuto,            // Prefer in-process libshaderc, fall back to external CLI (glslangValidator/glslc), then built-in SPIR-V
    scmShadercOnly,     // Only use in-process libshaderc
    scmExternalCLIOnly, // Only use external CLI compiler (glslangValidator / glslc)
    scmBuiltInOnly      // Force zero-dependency built-in SPIR-V fallback (simulates clean end-user machine)
  );

  { Thread-safe GLSL-to-SPIR-V compiler with memory and disk caching. }
  TCastleShaderCompiler = class
  private
    class var FInstance: TCastleShaderCompiler;
  private
    FShadercLib: TDynLib;
    FShadercLibName: String;
    FCompilerHandle: Pointer;
    FOptionsHandle: Pointer;
    FOptionsVulkan13Handle: Pointer;
    FExternalCompilerPath: String;
    FExternalCompilerIsGlslc: Boolean;
    FCompilerMode: TShaderCompilerMode;
    FRuntimeCompiledCount: Cardinal;
    FBuiltInFallbackCount: Cardinal;
    FLock: TCriticalSection;
    FMemoryCache: {$ifdef FPC}specialize{$endif} TDictionary<UInt64, TSPIRVBytecode>;
    FDiskCacheEnabled: Boolean;
    FDiskCacheBaseUrl: String;
    FBundledCacheBaseUrl: String;
    FBundlingTargetShaderDir: String;
    FBundledCopiedCount: Cardinal;

    procedure LoadShadercLibrary;
    procedure UnloadShadercLibrary;
    procedure DetectExternalCompiler;
    function BuildCacheFileUrl(const ABaseUrl: String; const AHash: UInt64;
      const AStage: TRHIShaderStage): String;
    function GetCacheFileUrl(const AHash: UInt64; const AStage: TRHIShaderStage): String;
    function TryLoadFromCacheUrl(const ACacheUrl: String; const AHash: UInt64;
      const AStage: TRHIShaderStage; out ASPIRV: TSPIRVBytecode): Boolean;
    function TryLoadFromDiskCache(const AHash: UInt64; const AStage: TRHIShaderStage;
      out ASPIRV: TSPIRVBytecode): Boolean;
    procedure SaveSPIRVToCacheUrl(const ACacheUrl: String; const AHash: UInt64;
      const AStage: TRHIShaderStage; const ASPIRV: TSPIRVBytecode);
    procedure SaveToDiskCache(const AHash: UInt64; const AStage: TRHIShaderStage;
      const ASPIRV: TSPIRVBytecode);
    procedure CopyCachedSpvFileCallback(const FileInfo: TFileInfo; var StopSearch: Boolean);
    function CompileGLSLToSPIRVInternal(const AStage: TRHIShaderStage;
      const AGLSLSource, ADebugName: String): TSPIRVBytecode;
    function CompileGLSLWithExternalCLI(const AStage: TRHIShaderStage;
      const AGLSLSource, ADebugName: String): TSPIRVBytecode;
  public
    constructor Create;
    destructor Destroy; override;

    { Compiles GLSL #version 450 source code into SPIR-V bytecode, or retrieves
      it immediately from memory/disk cache if the FNV-1a hash matches. }
    function GetOrCompileSPIRV(const AStage: TRHIShaderStage;
      const AGLSLSource: String; const ADebugName: String = 'castle_shader'): TSPIRVBytecode;

    { Resolves built-in, zero-dependency SPIR-V 1.0 bytecode for core CGE RHI
      shaders (DrawPrimitive2D, TCastleBatch2DRenderer, TCastleRenderUnlitMesh)
      so real Vulkan GPUs (including Mesa Lavapipe) can execute 2D UI, fonts,
      sprites, unlit meshes, stencil shadow volumes, and occlusion culling boxes
      even when neither libshaderc_shared nor external CLI compilers are installed. }
    function TryGetBuiltInSPIRV(const AStage: TRHIShaderStage;
      const AGLSLSource, ADebugName: String; out ASPIRV: TSPIRVBytecode): Boolean;

    { Returns a complete, spec-valid minimal SPIR-V 1.0 no-op shader module for AStage. }
    function GetMinimalValidSPIRVFallback(const AStage: TRHIShaderStage): TSPIRVBytecode;

    { Pre-warms a single GLSL 450 shader stage (compiles and caches to disk if
      libshaderc is available) and returns its deterministic 64-bit FNV-1a hash. }
    function PrewarmShaderSource(const AStage: TRHIShaderStage;
      const AGLSLSource: String; const ADebugName: String = 'prewarmed_shader'): UInt64;

    { Pre-warms known core engine shaders (3D forward pass vertex/fragment,
      depth-only shadow pass, and post-processing screen effect shaders)
      and returns the array of their deterministic source hashes. }
    function PrewarmCoreEngineShaders: TUInt64Array;

    { Bundles pre-warmed and built-in core engine SPIR-V shader cache files (.spv)
      into <ATargetDataDir>/shader_cache/ (and optionally copies a pre-baked
      vulkan_pipeline_cache.bin seed from ASourcePipelineCacheUrl if present),
      returning the total number of bundled .spv files in <ATargetDataDir>/shader_cache/. }
    function BundleCoreAndCachedShadersToDataDirectory(const ATargetDataDir: String;
      const ASourcePipelineCacheUrl: String = ''): Cardinal;

    { Clears all cached SPIR-V binaries from memory (and optionally disk). }
    procedure ClearCache(const AlsoClearDisk: Boolean = False);

    { True if libshaderc_shared/libshaderc or an external CLI compiler (glslangValidator/glslc)
      is active under the current @link(CompilerMode).
      Even if False, pre-cached .spv files and built-in core SPIR-V shaders can still be loaded! }
    function IsRuntimeCompilationAvailable: Boolean;
    function HasShadercLibrary: Boolean;
    function HasExternalCLICompiler: Boolean;
    function ActiveCompilerBackendName: String;
    procedure Reinitialize;
    procedure ResetStats;
    procedure RecordBuiltInFallbackHit;

    property CompilerMode: TShaderCompilerMode read FCompilerMode write FCompilerMode default scmAuto;
    property ShadercLibName: String read FShadercLibName;
    property ExternalCompilerPath: String read FExternalCompilerPath;
    property RuntimeCompiledCount: Cardinal read FRuntimeCompiledCount;
    property BuiltInFallbackCount: Cardinal read FBuiltInFallbackCount;
    property DiskCacheEnabled: Boolean read FDiskCacheEnabled write FDiskCacheEnabled default True;
    property DiskCacheBaseUrl: String read FDiskCacheBaseUrl write FDiskCacheBaseUrl;
    property BundledCacheBaseUrl: String read FBundledCacheBaseUrl write FBundledCacheBaseUrl;

    class function Instance: TCastleShaderCompiler;
    class destructor DestroyClass;
  end;


function InspectSPIRVBytecode(const AData: Pointer; const ASizeInBytes: PtrUInt;
  out AInfo: TSPIRVReflectionInfo): Boolean; overload; inline;
function InspectSPIRVBytecode(const ABytecode: TSPIRVBytecode;
  out AInfo: TSPIRVReflectionInfo): Boolean; overload; inline;
function ValidateSPIRVDescriptorBindings(const AInfo: TSPIRVReflectionInfo;
  const ASetIndex: Cardinal;
  const AExpectedBindings: array of TRHIDescriptorBindingDesc;
  out ADiagnosticMessage: String): Boolean; inline;

implementation

uses
  Math{$if defined(FPC) and (defined(UNIX) or defined(MSWINDOWS))}, Process{$endif};

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
  shaderc_vertex_shader       = 0;
  shaderc_fragment_shader     = 1;
  shaderc_compute_shader      = 2;
  shaderc_geometry_shader     = 3;
  shaderc_raygen_shader       = 14;
  shaderc_anyhit_shader       = 15;
  shaderc_closesthit_shader   = 16;
  shaderc_miss_shader         = 17;
  shaderc_intersection_shader = 18;
  shaderc_callable_shader     = 19;
  shaderc_task_shader         = 26;
  shaderc_mesh_shader         = 27;

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
  shaderc_env_version_vulkan_1_0    = (UInt32(1) shl 22);
  shaderc_env_version_vulkan_1_3    = (UInt32(1) shl 22) or (3 shl 12);

  { On-disk cache file magic header ('CSPV' + Version 2) }
  SPIRV_CACHE_FILE_MAGIC: UInt32   = $56505343; // 'CSPV'
  SPIRV_CACHE_FILE_VERSION: UInt32 = 2;
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
var
  EnvMode: String;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FMemoryCache := {$ifdef FPC}specialize{$endif} TDictionary<UInt64, TSPIRVBytecode>.Create;
  FDiskCacheEnabled := True;
  FDiskCacheBaseUrl := DefaultDiskShaderCacheBaseUrl;
  FBundledCacheBaseUrl := DefaultBundledShaderCacheBaseUrl;
  FCompilerMode := scmAuto;
  EnvMode := LowerCase(Trim(GetEnvironmentVariable('CASTLE_SHADER_COMPILER')));
  if (EnvMode = 'shaderc') or (EnvMode = 'libshaderc') then
    FCompilerMode := scmShadercOnly
  else if (EnvMode = 'cli') or (EnvMode = 'glslang') or (EnvMode = 'glslc') then
    FCompilerMode := scmExternalCLIOnly
  else if (EnvMode = 'builtin') or (EnvMode = 'built-in') or (EnvMode = 'none') then
    FCompilerMode := scmBuiltInOnly;

  LoadShadercLibrary;
  DetectExternalCompiler;
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
  ShadercCandidates: array[0..3] of String = (
    'shaderc_shared.dll',
    'libshaderc_shared.dll',
    'shaderc.dll',
    'libshaderc.dll'
  );
  SdkRelDir = 'Bin';
  {$elseif defined(DARWIN)}
  ShadercCandidates: array[0..7] of String = (
    'libshaderc_shared.1.dylib',
    'libshaderc_shared.dylib',
    '/opt/homebrew/lib/libshaderc_shared.1.dylib',
    '/opt/homebrew/lib/libshaderc_shared.dylib',
    '/usr/local/lib/libshaderc_shared.1.dylib',
    '/usr/local/lib/libshaderc_shared.dylib',
    'libshaderc.1.dylib',
    'libshaderc.dylib'
  );
  SdkRelDir = 'lib';
  {$else}
  ShadercCandidates: array[0..3] of String = (
    'libshaderc_shared.so.1',
    'libshaderc_shared.so',
    'libshaderc.so.1',
    'libshaderc.so'
  );
  SdkRelDir = 'lib';
  {$endif}
var
  CustomPath, SdkRoot, CandidatePath, CandidateName: String;
begin
  FShadercLibName := '';
  CustomPath := Trim(GetEnvironmentVariable('CASTLE_SHADERC_PATH'));
  if CustomPath <> '' then
  begin
    FShadercLib := TDynLib.Load(CustomPath, False);
    if FShadercLib <> nil then
      FShadercLibName := CustomPath;
  end;

  if FShadercLib = nil then
    for CandidateName in ShadercCandidates do
    begin
      FShadercLib := TDynLib.Load(CandidateName, False);
      if FShadercLib <> nil then
      begin
        FShadercLibName := CandidateName;
        Break;
      end;
    end;

  if FShadercLib = nil then
  begin
    SdkRoot := Trim(GetEnvironmentVariable('VULKAN_SDK'));
    if SdkRoot <> '' then
      for CandidateName in ShadercCandidates do
      begin
        CandidatePath := IncludeTrailingPathDelimiter(SdkRoot) +
          IncludeTrailingPathDelimiter(SdkRelDir) + CandidateName;
        if FileExists(CandidatePath) then
        begin
          FShadercLib := TDynLib.Load(CandidatePath, False);
          if FShadercLib <> nil then
          begin
            FShadercLibName := CandidatePath;
            Break;
          end;
        end;
      end;
  end;

  if FShadercLib = nil then
  begin
    WritelnLog('RHI/ShaderCompiler',
      'libshaderc not found. Checking external CLI SPIR-V compilers / pre-cached .spv files.');
    Exit;
  end;

  try
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
  except
    on E: Exception do
    begin
      WritelnWarning('RHI/ShaderCompiler',
        'Failed to bind shaderc C symbols from "%s": %s', [FShadercLibName, E.Message]);
      FreeAndNil(FShadercLib);
      FShadercLibName := '';
      Exit;
    end;
  end;

  FCompilerHandle := shaderc_compiler_initialize();
  FOptionsHandle := shaderc_compile_options_initialize();
  FOptionsVulkan13Handle := shaderc_compile_options_initialize();

  if (FCompilerHandle <> nil) and (FOptionsHandle <> nil) then
  begin
    shaderc_compile_options_set_target_env(
      FOptionsHandle, shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_0);
    shaderc_compile_options_set_optimization_level(
      FOptionsHandle, shaderc_optimization_level_performance);
    {$ifdef DEBUG}
    shaderc_compile_options_set_generate_debug_info(FOptionsHandle);
    {$endif}
  end;

  if (FCompilerHandle <> nil) and (FOptionsVulkan13Handle <> nil) then
  begin
    shaderc_compile_options_set_target_env(
      FOptionsVulkan13Handle, shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_3);
    shaderc_compile_options_set_optimization_level(
      FOptionsVulkan13Handle, shaderc_optimization_level_performance);
    {$ifdef DEBUG}
    shaderc_compile_options_set_generate_debug_info(FOptionsVulkan13Handle);
    {$endif}
  end;

  WritelnLog('RHI/ShaderCompiler',
    'Loaded in-process runtime GLSL->SPIR-V compiler: %s', [FShadercLibName]);
end;

procedure TCastleShaderCompiler.UnloadShadercLibrary;
begin
  if FOptionsVulkan13Handle <> nil then
  begin
    shaderc_compile_options_release(FOptionsVulkan13Handle);
    FOptionsVulkan13Handle := nil;
  end;
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
  FShadercLibName := '';
end;

procedure TCastleShaderCompiler.DetectExternalCompiler;
const
  {$ifdef MSWINDOWS}
  ExeExt = '.exe';
  SdkBinSubdir = 'Bin';
  {$else}
  ExeExt = '';
  SdkBinSubdir = 'bin';
  {$endif}
var
  CustomExe, SdkRoot, Candidate: String;
begin
  FExternalCompilerPath := '';
  FExternalCompilerIsGlslc := False;

  CustomExe := Trim(GetEnvironmentVariable('CASTLE_GLSLANG_PATH'));
  if (CustomExe <> '') and FileExists(CustomExe) then
  begin
    FExternalCompilerPath := CustomExe;
    FExternalCompilerIsGlslc := Pos('glslc', LowerCase(ExtractFileName(CustomExe))) > 0;
    WritelnLog('RHI/ShaderCompiler', 'Using custom external SPIR-V compiler: %s', [FExternalCompilerPath]);
    Exit;
  end;

  Candidate := FindExe('glslangValidator');
  if Candidate = '' then
    Candidate := FindExe('glslang');
  if Candidate <> '' then
  begin
    FExternalCompilerPath := Candidate;
    FExternalCompilerIsGlslc := False;
    WritelnLog('RHI/ShaderCompiler', 'Found external SPIR-V compiler: %s', [FExternalCompilerPath]);
    Exit;
  end;

  Candidate := FindExe('glslc');
  if Candidate <> '' then
  begin
    FExternalCompilerPath := Candidate;
    FExternalCompilerIsGlslc := True;
    WritelnLog('RHI/ShaderCompiler', 'Found external SPIR-V compiler: %s', [FExternalCompilerPath]);
    Exit;
  end;

  {$ifdef DARWIN}
  for Candidate in [
    '/opt/homebrew/bin/glslangValidator',
    '/usr/local/bin/glslangValidator',
    '/opt/homebrew/bin/glslc',
    '/usr/local/bin/glslc'
  ] do
    if FileExists(Candidate) then
    begin
      FExternalCompilerPath := Candidate;
      FExternalCompilerIsGlslc := Pos('glslc', LowerCase(ExtractFileName(Candidate))) > 0;
      WritelnLog('RHI/ShaderCompiler', 'Found Homebrew SPIR-V compiler: %s', [FExternalCompilerPath]);
      Exit;
    end;
  {$endif}

  SdkRoot := Trim(GetEnvironmentVariable('VULKAN_SDK'));
  if SdkRoot <> '' then
  begin
    Candidate := IncludeTrailingPathDelimiter(SdkRoot) +
      IncludeTrailingPathDelimiter(SdkBinSubdir) + 'glslangValidator' + ExeExt;
    if FileExists(Candidate) then
    begin
      FExternalCompilerPath := Candidate;
      FExternalCompilerIsGlslc := False;
      WritelnLog('RHI/ShaderCompiler', 'Found Vulkan SDK SPIR-V compiler: %s', [FExternalCompilerPath]);
      Exit;
    end;
    Candidate := IncludeTrailingPathDelimiter(SdkRoot) +
      IncludeTrailingPathDelimiter(SdkBinSubdir) + 'glslc' + ExeExt;
    if FileExists(Candidate) then
    begin
      FExternalCompilerPath := Candidate;
      FExternalCompilerIsGlslc := True;
      WritelnLog('RHI/ShaderCompiler', 'Found Vulkan SDK SPIR-V compiler: %s', [FExternalCompilerPath]);
    end;
  end;
end;

function TCastleShaderCompiler.HasShadercLibrary: Boolean;
begin
  Result := (FShadercLib <> nil) and (FCompilerHandle <> nil);
end;

function TCastleShaderCompiler.HasExternalCLICompiler: Boolean;
begin
  Result := FExternalCompilerPath <> '';
end;

function TCastleShaderCompiler.IsRuntimeCompilationAvailable: Boolean;
begin
  case FCompilerMode of
    scmAuto:
      Result := HasShadercLibrary or HasExternalCLICompiler;
    scmShadercOnly:
      Result := HasShadercLibrary;
    scmExternalCLIOnly:
      Result := HasExternalCLICompiler;
    scmBuiltInOnly:
      Result := False;
  else
    Result := False;
  end;
end;

function TCastleShaderCompiler.ActiveCompilerBackendName: String;
begin
  case FCompilerMode of
    scmAuto:
      if HasShadercLibrary then
        Result := 'libshaderc (' + ExtractFileName(FShadercLibName) + ')'
      else if HasExternalCLICompiler then
        Result := 'external CLI (' + ExtractFileName(FExternalCompilerPath) + ')'
      else
        Result := 'built-in SPIR-V (56 embedded modules)';
    scmShadercOnly:
      if HasShadercLibrary then
        Result := 'libshaderc (' + ExtractFileName(FShadercLibName) + ')'
      else
        Result := 'unavailable (scmShadercOnly)';
    scmExternalCLIOnly:
      if HasExternalCLICompiler then
        Result := 'external CLI (' + ExtractFileName(FExternalCompilerPath) + ')'
      else
        Result := 'unavailable (scmExternalCLIOnly)';
    scmBuiltInOnly:
      Result := 'built-in SPIR-V (forced scmBuiltInOnly)';
  end;
end;

procedure TCastleShaderCompiler.Reinitialize;
begin
  FLock.Acquire;
  try
    UnloadShadercLibrary;
    FExternalCompilerPath := '';
    FExternalCompilerIsGlslc := False;
    LoadShadercLibrary;
    DetectExternalCompiler;
  finally
    FLock.Release;
  end;
end;

procedure TCastleShaderCompiler.ResetStats;
begin
  FLock.Acquire;
  try
    FRuntimeCompiledCount := 0;
    FBuiltInFallbackCount := 0;
  finally
    FLock.Release;
  end;
end;

procedure TCastleShaderCompiler.RecordBuiltInFallbackHit;
begin
  FLock.Acquire;
  try
    Inc(FBuiltInFallbackCount);
  finally
    FLock.Release;
  end;
end;

function TCastleShaderCompiler.BuildCacheFileUrl(const ABaseUrl: String;
  const AHash: UInt64; const AStage: TRHIShaderStage): String;
const
  StageExt: array[TRHIShaderStage] of String = ('vert', 'frag', 'geom', 'comp', 'task', 'mesh', 'rgen', 'rahit', 'rchit', 'rmiss', 'rint', 'rcall');
var
  NormBase: String;
begin
  NormBase := ABaseUrl;
  if (NormBase <> '') and (NormBase[Length(NormBase)] <> '/') then
    NormBase := NormBase + '/';
  Result := NormBase + IntToHex(AHash, 16) + '.' + StageExt[AStage] + '.spv';
end;

function TCastleShaderCompiler.GetCacheFileUrl(const AHash: UInt64;
  const AStage: TRHIShaderStage): String;
begin
  Result := BuildCacheFileUrl(FDiskCacheBaseUrl, AHash, AStage);
end;

function TCastleShaderCompiler.TryLoadFromCacheUrl(const ACacheUrl: String;
  const AHash: UInt64; const AStage: TRHIShaderStage;
  out ASPIRV: TSPIRVBytecode): Boolean;
var
  Stream: TStream;
  Header: TCastleSPIRVCacheHeader;
  FirstWord: UInt32;
begin
  Result := False;
  if (ACacheUrl = '') or (not UriFileExists(ACacheUrl)) then Exit;

  try
    Stream := Download(ACacheUrl, []);
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
        [ACacheUrl, E.Message]);
      Result := False;
    end;
  end;
end;

function TCastleShaderCompiler.TryLoadFromDiskCache(const AHash: UInt64;
  const AStage: TRHIShaderStage; out ASPIRV: TSPIRVBytecode): Boolean;
begin
  Result := False;
  if not FDiskCacheEnabled then Exit;
  { When CASTLE_VULKAN_SPIRV_DIR is set, bypass disk cache so live external .spv
    overrides take effect immediately without stale cache shadowing. }
  if Trim(GetEnvironmentVariable('CASTLE_VULKAN_SPIRV_DIR')) <> '' then Exit;

  { 1. Check user-writable persistent disk cache (castle-config:/shader_cache/) }
  if (FDiskCacheBaseUrl <> '') and
     TryLoadFromCacheUrl(BuildCacheFileUrl(FDiskCacheBaseUrl, AHash, AStage), AHash, AStage, ASPIRV) then
    Exit(True);

  { 2. Fallback to read-only packaged asset cache (castle-data:/shader_cache/) }
  if (FBundledCacheBaseUrl <> '') and (FBundledCacheBaseUrl <> FDiskCacheBaseUrl) and
     TryLoadFromCacheUrl(BuildCacheFileUrl(FBundledCacheBaseUrl, AHash, AStage), AHash, AStage, ASPIRV) then
    Exit(True);
end;

procedure TCastleShaderCompiler.SaveSPIRVToCacheUrl(const ACacheUrl: String;
  const AHash: UInt64; const AStage: TRHIShaderStage; const ASPIRV: TSPIRVBytecode);
var
  LocalFileName, LocalDir: String;
  Stream: TStream;
  Header: TCastleSPIRVCacheHeader;
begin
  if (ACacheUrl = '') or (Length(ASPIRV) = 0) then Exit;

  try
    LocalFileName := UriToFilenameSafe(ACacheUrl);
    if LocalFileName <> '' then
    begin
      LocalDir := ExtractFilePath(LocalFileName);
      if LocalDir <> '' then
        CheckForceDirectories(LocalDir);
    end;
    Header.FileMagic := SPIRV_CACHE_FILE_MAGIC;
    Header.CacheVersion := SPIRV_CACHE_FILE_VERSION;
    Header.SourceHash := AHash;
    Header.Stage := UInt32(Ord(AStage));
    Header.BytecodeSize := UInt32(Length(ASPIRV));

    Stream := UrlSaveStream(ACacheUrl);
    try
      Stream.WriteBuffer(Header, SizeOf(Header));
      Stream.WriteBuffer(ASPIRV[0], Length(ASPIRV));
    finally
      FreeAndNil(Stream);
    end;
  except
    on E: Exception do
      WritelnWarning('RHI/ShaderCompiler', 'Could not write SPIR-V disk cache (%s): %s',
        [ACacheUrl, E.Message]);
  end;
end;

procedure TCastleShaderCompiler.SaveToDiskCache(const AHash: UInt64;
  const AStage: TRHIShaderStage; const ASPIRV: TSPIRVBytecode);
begin
  if (not FDiskCacheEnabled) or (Length(ASPIRV) = 0) then Exit;
  SaveSPIRVToCacheUrl(GetCacheFileUrl(AHash, AStage), AHash, AStage, ASPIRV);
end;

function TCastleShaderCompiler.CompileGLSLWithExternalCLI(
  const AStage: TRHIShaderStage; const AGLSLSource, ADebugName: String): TSPIRVBytecode;
{$if defined(FPC) and (defined(UNIX) or defined(MSWINDOWS))}
const
  StageNames: array[TRHIShaderStage] of String = ('vert', 'frag', 'geom', 'comp', 'task', 'mesh', 'rgen', 'rahit', 'rchit', 'rmiss', 'rint', 'rcall');
var
  SourceHash: UInt64;
  TempDir, InFile, OutFile: String;
  SrcStream, OutStream: TFileStream;
  AnsiSrc: AnsiString;
  Proc: TProcess;
  CmdOutput: AnsiString;
  ExitCode: Integer;
begin
  Result := nil;
  if FExternalCompilerPath = '' then
    raise ERHIShaderCompilationError.CreateFmt(
      'Cannot compile shader "%s": external CLI SPIR-V compiler is not available.',
      [ADebugName]);

  SourceHash := TCastleShaderGeneratorRHI.ComputeSourceHash(AGLSLSource);
  TempDir := GetTempDir(False);
  InFile := IncludeTrailingPathDelimiter(TempDir) + 'cge_spv_' + IntToHex(SourceHash, 16) + '.' + StageNames[AStage];
  OutFile := InFile + '.spv';

  SrcStream := TFileStream.Create(InFile, fmCreate);
  try
    AnsiSrc := AnsiString(AGLSLSource);
    if Length(AnsiSrc) > 0 then
      SrcStream.WriteBuffer(AnsiSrc[1], Length(AnsiSrc));
  finally
    FreeAndNil(SrcStream);
  end;

  try
    Proc := TProcess.Create(nil);
    try
      Proc.Executable := FExternalCompilerPath;
      Proc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
      if FExternalCompilerIsGlslc then
      begin
        Proc.Parameters.Add('-fshader-stage=' + StageNames[AStage]);
        if (AStage in [ssTask, ssMesh, ssRayGen, ssAnyHit, ssClosestHit, ssMiss, ssIntersection, ssCallable]) or
           (Pos('GL_EXT_ray_', AGLSLSource) > 0) or
           (Pos('GL_EXT_mesh_shader', AGLSLSource) > 0) or
           (Pos('GL_KHR_shader_subgroup', AGLSLSource) > 0) or
           (Pos('GL_EXT_nonuniform_qualifier', AGLSLSource) > 0) then
          Proc.Parameters.Add('--target-env=vulkan1.3')
        else
          Proc.Parameters.Add('--target-env=vulkan1.0');
        Proc.Parameters.Add('-o');
        Proc.Parameters.Add(OutFile);
        Proc.Parameters.Add(InFile);
      end else
      begin
        Proc.Parameters.Add('-V');
        if (AStage in [ssTask, ssMesh, ssRayGen, ssAnyHit, ssClosestHit, ssMiss, ssIntersection, ssCallable]) or
           (Pos('GL_EXT_ray_', AGLSLSource) > 0) or
           (Pos('GL_EXT_mesh_shader', AGLSLSource) > 0) or
           (Pos('GL_KHR_shader_subgroup', AGLSLSource) > 0) or
           (Pos('GL_EXT_nonuniform_qualifier', AGLSLSource) > 0) then
        begin
          Proc.Parameters.Add('--target-env');
          Proc.Parameters.Add('vulkan1.3');
        end;
        Proc.Parameters.Add('-S');
        Proc.Parameters.Add(StageNames[AStage]);
        Proc.Parameters.Add('-o');
        Proc.Parameters.Add(OutFile);
        Proc.Parameters.Add(InFile);
      end;
      Proc.Execute;
      CmdOutput := '';
      while Proc.Running or ((Proc.Output <> nil) and (Proc.Output.NumBytesAvailable > 0)) do
      begin
        if (Proc.Output <> nil) and (Proc.Output.NumBytesAvailable > 0) then
        begin
          ExitCode := Proc.Output.NumBytesAvailable;
          SetLength(AnsiSrc, ExitCode);
          ExitCode := Proc.Output.Read(AnsiSrc[1], ExitCode);
          if ExitCode > 0 then
            CmdOutput := CmdOutput + Copy(AnsiSrc, 1, ExitCode);
        end else
          Sleep(1);
      end;
      ExitCode := Proc.ExitStatus;
    finally
      FreeAndNil(Proc);
    end;

    if (ExitCode <> 0) or (not FileExists(OutFile)) then
      raise ERHIShaderCompilationError.CreateFmt(
        'External SPIR-V compilation failed for "%s" (exit %d):%s%s',
        [ADebugName, ExitCode, LineEnding, String(CmdOutput)]);

    OutStream := TFileStream.Create(OutFile, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, OutStream.Size);
      if OutStream.Size > 0 then
        OutStream.ReadBuffer(Result[0], OutStream.Size);
    finally
      FreeAndNil(OutStream);
    end;
  finally
    if FileExists(InFile) then
      DeleteFile(InFile);
    if FileExists(OutFile) then
      DeleteFile(OutFile);
  end;
end;
{$else}
begin
  Result := nil;
  raise ERHIShaderCompilationError.CreateFmt(
    'Cannot compile shader "%s": external CLI SPIR-V compiler is not supported on this platform.',
    [ADebugName]);
end;
{$endif}

function TCastleShaderCompiler.CompileGLSLToSPIRVInternal(
  const AStage: TRHIShaderStage; const AGLSLSource, ADebugName: String): TSPIRVBytecode;
var
  Kind: TShadercShaderKind;
  AnsiSrc, AnsiName: AnsiString;
  CompRes: PShadercCompilationResult;
  SelectedOptions: PShadercCompileOptions;
  Status: TShadercCompilationStatus;
  ByteLen: PtrUInt;
  BytePtr: PByte;
  ErrMsg: String;
begin
  if FCompilerMode = scmBuiltInOnly then
    raise ERHIShaderCompilationError.CreateFmt(
      'Cannot runtime-compile shader "%s": CompilerMode is scmBuiltInOnly.',
      [ADebugName]);

  if FCompilerMode = scmExternalCLIOnly then
  begin
    Result := CompileGLSLWithExternalCLI(AStage, AGLSLSource, ADebugName);
    Inc(FRuntimeCompiledCount);
    Exit;
  end;

  if not HasShadercLibrary then
  begin
    if (FCompilerMode = scmAuto) and HasExternalCLICompiler then
    begin
      Result := CompileGLSLWithExternalCLI(AStage, AGLSLSource, ADebugName);
      Inc(FRuntimeCompiledCount);
      Exit;
    end;
    raise ERHIShaderCompilationError.CreateFmt(
      'Cannot compile shader "%s": libshaderc is not loaded and shader was not found in disk cache.',
      [ADebugName]);
  end;

  case AStage of
    ssVertex:       Kind := shaderc_vertex_shader;
    ssFragment:     Kind := shaderc_fragment_shader;
    ssGeometry:     Kind := shaderc_geometry_shader;
    ssCompute:      Kind := shaderc_compute_shader;
    ssTask:         Kind := shaderc_task_shader;
    ssMesh:         Kind := shaderc_mesh_shader;
    ssRayGen:       Kind := shaderc_raygen_shader;
    ssAnyHit:       Kind := shaderc_anyhit_shader;
    ssClosestHit:   Kind := shaderc_closesthit_shader;
    ssMiss:         Kind := shaderc_miss_shader;
    ssIntersection: Kind := shaderc_intersection_shader;
    ssCallable:     Kind := shaderc_callable_shader;
    else            Kind := shaderc_vertex_shader;
  end;

  if ((AStage in [ssTask, ssMesh, ssRayGen, ssAnyHit, ssClosestHit, ssMiss, ssIntersection, ssCallable]) or
      (Pos('GL_EXT_ray_', AGLSLSource) > 0) or
      (Pos('GL_EXT_mesh_shader', AGLSLSource) > 0) or
      (Pos('GL_KHR_shader_subgroup', AGLSLSource) > 0) or
      (Pos('GL_EXT_nonuniform_qualifier', AGLSLSource) > 0)) and
     (FOptionsVulkan13Handle <> nil) then
    SelectedOptions := FOptionsVulkan13Handle
  else
    SelectedOptions := FOptionsHandle;

  AnsiSrc := AnsiString(AGLSLSource);
  AnsiName := AnsiString(ADebugName);

  CompRes := shaderc_compile_into_spv(
    FCompilerHandle,
    PAnsiChar(AnsiSrc),
    Length(AnsiSrc),
    Kind,
    PAnsiChar(AnsiName),
    'main',
    SelectedOptions);

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
    Inc(FRuntimeCompiledCount);
  finally
    shaderc_result_release(CompRes);
  end;
end;


{$I castleinternalshadercompiler_builtins.inc}

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
  begin
    FLock.Acquire;
    try
      if not FMemoryCache.TryGetValue(Result, DummySPIRV) then
      begin
        if TryLoadFromDiskCache(Result, AStage, DummySPIRV) then
          FMemoryCache.Add(Result, DummySPIRV)
        else if TryGetBuiltInSPIRV(AStage, AGLSLSource, ADebugName, DummySPIRV) then
        begin
          FMemoryCache.Add(Result, DummySPIRV);
          SaveToDiskCache(Result, AStage, DummySPIRV);
        end;
      end;
    finally
      FLock.Release;
    end;
  end;
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

procedure TCastleShaderCompiler.CopyCachedSpvFileCallback(
  const FileInfo: TFileInfo; var StopSearch: Boolean);
var
  DstFile: String;
begin
  StopSearch := False;
  if FileInfo.Directory or (FBundlingTargetShaderDir = '') then Exit;
  DstFile := InclPathDelim(FBundlingTargetShaderDir) + FileInfo.Name;
  if SameFileName(FileInfo.AbsoluteName, DstFile) then
  begin
    Inc(FBundledCopiedCount);
    Exit;
  end;
  CheckCopyFile(FileInfo.AbsoluteName, DstFile);
  Inc(FBundledCopiedCount);
end;

function TCastleShaderCompiler.BundleCoreAndCachedShadersToDataDirectory(
  const ATargetDataDir: String; const ASourcePipelineCacheUrl: String): Cardinal;
const
  CoreStages: array[0..4] of TRHIShaderStage = (
    ssVertex, ssFragment, ssVertex, ssVertex, ssFragment
  );
var
  Hashes: TUInt64Array;
  TargetShaderDir, TargetShaderBaseUrl, SourceDiskDir: String;
  SrcPipelineFile, DstPipelineFile: String;
  CachedSPIRV: TSPIRVBytecode;
  I: Integer;
begin
  Result := 0;
  if ATargetDataDir = '' then Exit;

  TargetShaderDir := InclPathDelim(ATargetDataDir) + 'shader_cache';
  CheckForceDirectories(TargetShaderDir);
  TargetShaderBaseUrl := FilenameToUriSafe(InclPathDelim(TargetShaderDir));

  { 1. Pre-warm core engine stages and write them directly into <ATargetDataDir>/shader_cache/ }
  Hashes := PrewarmCoreEngineShaders;
  FLock.Acquire;
  try
    for I := 0 to High(Hashes) do
      if FMemoryCache.TryGetValue(Hashes[I], CachedSPIRV) and (Length(CachedSPIRV) > 0) then
        SaveSPIRVToCacheUrl(
          BuildCacheFileUrl(TargetShaderBaseUrl, Hashes[I], CoreStages[I]),
          Hashes[I], CoreStages[I], CachedSPIRV);

    { 2. Copy any additional pre-cached .spv files from DiskCacheBaseUrl into <ATargetDataDir>/shader_cache/ }
    if FDiskCacheBaseUrl <> '' then
    begin
      SourceDiskDir := UriToFilenameSafe(FDiskCacheBaseUrl);
      if (SourceDiskDir <> '') and DirectoryExists(SourceDiskDir) and
         (not SameFileName(ExcludeTrailingPathDelimiter(SourceDiskDir),
                           ExcludeTrailingPathDelimiter(TargetShaderDir))) then
      begin
        FBundlingTargetShaderDir := TargetShaderDir;
        FBundledCopiedCount := 0;
        FindFiles(SourceDiskDir, '*.spv', False, @CopyCachedSpvFileCallback, []);
      end;
    end;

    { Count total bundled .spv files now present in TargetShaderDir }
    FBundlingTargetShaderDir := TargetShaderDir;
    FBundledCopiedCount := 0;
    FindFiles(TargetShaderDir, '*.spv', False, @CopyCachedSpvFileCallback, []);
    Result := FBundledCopiedCount;
  finally
    FLock.Release;
  end;

  { 3. Bundle optional pre-baked vulkan_pipeline_cache.bin seed if available and not already in data/ }
  if (ASourcePipelineCacheUrl <> '') and UriFileExists(ASourcePipelineCacheUrl) then
  begin
    SrcPipelineFile := UriToFilenameSafe(ASourcePipelineCacheUrl);
    DstPipelineFile := InclPathDelim(ATargetDataDir) + 'vulkan_pipeline_cache.bin';
    if (SrcPipelineFile <> '') and RegularFileExists(SrcPipelineFile) and
       (not RegularFileExists(DstPipelineFile)) and
       (not SameFileName(SrcPipelineFile, DstPipelineFile)) then
      CheckCopyFile(SrcPipelineFile, DstPipelineFile);
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


function InspectSPIRVBytecode(const AData: Pointer; const ASizeInBytes: PtrUInt;
  out AInfo: TSPIRVReflectionInfo): Boolean;
begin
  Result := CastleInternalSPIRVReflection.InspectSPIRVBytecode(AData, ASizeInBytes, AInfo);
end;

function InspectSPIRVBytecode(const ABytecode: TSPIRVBytecode;
  out AInfo: TSPIRVReflectionInfo): Boolean;
begin
  Result := CastleInternalSPIRVReflection.InspectSPIRVBytecode(ABytecode, AInfo);
end;

function ValidateSPIRVDescriptorBindings(const AInfo: TSPIRVReflectionInfo;
  const ASetIndex: Cardinal;
  const AExpectedBindings: array of TRHIDescriptorBindingDesc;
  out ADiagnosticMessage: String): Boolean;
begin
  Result := CastleInternalSPIRVReflection.ValidateSPIRVDescriptorBindings(
    AInfo, ASetIndex, AExpectedBindings, ADiagnosticMessage);
end;

end.
