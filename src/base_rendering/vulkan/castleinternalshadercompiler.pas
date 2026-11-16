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
    FExternalCompilerPath: String;
    FExternalCompilerIsGlslc: Boolean;
    FLock: TCriticalSection;
    FMemoryCache: {$ifdef FPC}specialize{$endif} TDictionary<UInt64, TSPIRVBytecode>;
    FDiskCacheEnabled: Boolean;
    FDiskCacheBaseUrl: String;

    procedure LoadShadercLibrary;
    procedure UnloadShadercLibrary;
    procedure DetectExternalCompiler;
    function GetCacheFileUrl(const AHash: UInt64; const AStage: TRHIShaderStage): String;
    function TryLoadFromDiskCache(const AHash: UInt64; const AStage: TRHIShaderStage;
      out ASPIRV: TSPIRVBytecode): Boolean;
    procedure SaveToDiskCache(const AHash: UInt64; const AStage: TRHIShaderStage;
      const ASPIRV: TSPIRVBytecode);
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

    { Clears all cached SPIR-V binaries from memory (and optionally disk). }
    procedure ClearCache(const AlsoClearDisk: Boolean = False);

    { True if libshaderc_shared or an external CLI compiler (glslangValidator/glslc) was found.
      Even if False, pre-cached .spv files and built-in core SPIR-V shaders can still be loaded! }
    function IsRuntimeCompilationAvailable: Boolean;
    function HasExternalCLICompiler: Boolean;

    property ExternalCompilerPath: String read FExternalCompilerPath;
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

{$if defined(FPC) and (defined(UNIX) or defined(MSWINDOWS))}
uses
  Process;
{$endif}

{ ---------------------------------------------------------------------------- }
{ Built-In Zero-Dependency SPIR-V 1.0 Core Shaders                             }
{ ---------------------------------------------------------------------------- }

const
  { 1. DrawPrimitive2D Vertex Shader (Primitive2D_VS):
       layout(location = 0) in vec2 vertex;
       PushConstants(vec2 viewport_size; float point_size; float padding; vec4 color) pc;
       gl_Position = vec4(vertex * 2.0 / pc.viewport_size - vec2(1.0), 0.0, 1.0);
       gl_PointSize = pc.point_size; }
  BuiltInPrimitive2DVertSPIRV: array[0..230] of UInt32 = (
    $07230203, $00010000, $00000000, $00000028, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0007000F, 0, 1, $6E69616D, $00000000, 8, 12,
    $00050048, 6, 0, 11, 0,
    $00050048, 6, 1, 11, 1,
    $00030047, 6, 2,
    $00040047, 12, 30, 0,
    $00050048, 13, 0, 35, 0,
    $00050048, 13, 1, 35, 8,
    $00050048, 13, 2, 35, 12,
    $00050048, 13, 3, 35, 16,
    $00030047, 13, 2,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $0004001E, 6, 5, 4,
    $00040020, 7, 3, 6,
    $0004003B, 7, 8, 3,
    $00040015, 9, 32, 1,
    $00040017, 10, 4, 2,
    $00040020, 11, 1, 10,
    $0004003B, 11, 12, 1,
    $0006001E, 13, 10, 4, 4, 5,
    $00040020, 14, 9, 13,
    $0004003B, 14, 15, 9,
    $00040020, 16, 9, 10,
    $00040020, 17, 9, 4,
    $00040020, 18, 3, 5,
    $00040020, 19, 3, 4,
    $0004002B, 9, 20, 0,
    $0004002B, 9, 21, 1,
    $0004002B, 4, 22, $00000000,
    $0004002B, 4, 23, $3F800000,
    $0004002B, 4, 24, $40000000,
    $0005002C, 10, 25, 23, 23,
    $00050036, 2, 1, 0, 3,
    $000200F8, 26,
    $0004003D, 10, 27, 12,
    $0005008E, 10, 28, 27, 24,
    $00050041, 16, 29, 15, 20,
    $0004003D, 10, 30, 29,
    $00050088, 10, 31, 28, 30,
    $00050083, 10, 32, 31, 25,
    $00050051, 4, 33, 32, 0,
    $00050051, 4, 34, 32, 1,
    $00070050, 5, 35, 33, 34, 22, 23,
    $00050041, 18, 36, 8, 20,
    $0003003E, 36, 35,
    $00050041, 17, 37, 15, 21,
    $0004003D, 4, 38, 37,
    $00050041, 19, 39, 8, 21,
    $0003003E, 39, 38,
    $000100FD,
    $00010038
  );

  { 2. DrawPrimitive2D Fragment Shader (Primitive2D_FS):
       PushConstants(vec2 viewport_size; float point_size; float padding; vec4 color) pc;
       layout(location = 0) out vec4 out_Color;
       out_Color = pc.color; }
  BuiltInPrimitive2DFragSPIRV: array[0..116] of UInt32 = (
    $07230203, $00010000, $00000000, $00000012, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0006000F, 4, 1, $6E69616D, $00000000, 7,
    $00030010, 1, 7,
    $00040047, 7, 30, 0,
    $00050048, 9, 0, 35, 0,
    $00050048, 9, 1, 35, 8,
    $00050048, 9, 2, 35, 12,
    $00050048, 9, 3, 35, 16,
    $00030047, 9, 2,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $00040020, 6, 3, 5,
    $0004003B, 6, 7, 3,
    $00040017, 8, 4, 2,
    $0006001E, 9, 8, 4, 4, 5,
    $00040020, 10, 9, 9,
    $0004003B, 10, 11, 9,
    $00040015, 12, 32, 1,
    $0004002B, 12, 13, 3,
    $00040020, 14, 9, 5,
    $00050036, 2, 1, 0, 3,
    $000200F8, 15,
    $00050041, 14, 16, 11, 13,
    $0004003D, 5, 17, 16,
    $0003003E, 7, 17,
    $000100FD,
    $00010038
  );

  { 3. TCastleRenderUnlitMesh Vertex Shader (UnlitMesh_VS):
       layout(location = 0) in vec4 castle_Vertex;
       PushConstants(mat4 u_MVP; vec4 u_Color) pc;
       gl_Position = pc.u_MVP * castle_Vertex;
       gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5; }
  BuiltInUnlitMeshVertSPIRV: array[0..178] of UInt32 = (
    $07230203, $00010000, $00000000, $0000001F, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0007000F, 0, 1, $6E69616D, $00000000, 8, 12,
    $00050048, 6, 0, 11, 0,
    $00030047, 6, 2,
    $00040047, 12, 30, 0,
    $00040048, 14, 0, 5,
    $00050048, 14, 0, 35, 0,
    $00050048, 14, 0, 7, 16,
    $00050048, 14, 1, 35, 64,
    $00030047, 14, 2,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $0003001E, 6, 5,
    $00040020, 7, 3, 6,
    $0004003B, 7, 8, 3,
    $00040015, 9, 32, 1,
    $0004002B, 9, 10, 0,
    $00040020, 11, 1, 5,
    $0004003B, 11, 12, 1,
    $00040018, 13, 5, 4,
    $0004001E, 14, 13, 5,
    $00040020, 15, 9, 14,
    $0004003B, 15, 16, 9,
    $00040020, 17, 9, 13,
    $00040020, 18, 3, 5,
    $0004002B, 4, 19, $3F000000,
    $00050036, 2, 1, 0, 3,
    $000200F8, 20,
    $00050041, 17, 21, 16, 10,
    $0004003D, 13, 22, 21,
    $0004003D, 5, 23, 12,
    $00050091, 5, 24, 22, 23,
    $00050051, 4, 25, 24, 2,
    $00050051, 4, 26, 24, 3,
    $00050081, 4, 27, 25, 26,
    $00050085, 4, 28, 27, 19,
    $00060052, 5, 29, 28, 24, 2,
    $00050041, 18, 30, 8, 10,
    $0003003E, 30, 29,
    $000100FD,
    $00010038
  );

  { 4. TCastleRenderUnlitMesh Fragment Shader (UnlitMesh_FS):
       PushConstants(mat4 u_MVP; vec4 u_Color) pc;
       layout(location = 0) out vec4 out_Color;
       out_Color = pc.u_Color; }
  BuiltInUnlitMeshFragSPIRV: array[0..113] of UInt32 = (
    $07230203, $00010000, $00000000, $00000012, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0006000F, 4, 1, $6E69616D, $00000000, 7,
    $00030010, 1, 7,
    $00040047, 7, 30, 0,
    $00040048, 9, 0, 5,
    $00050048, 9, 0, 35, 0,
    $00050048, 9, 0, 7, 16,
    $00050048, 9, 1, 35, 64,
    $00030047, 9, 2,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $00040020, 6, 3, 5,
    $0004003B, 6, 7, 3,
    $00040018, 8, 5, 4,
    $0004001E, 9, 8, 5,
    $00040020, 10, 9, 9,
    $0004003B, 10, 11, 9,
    $00040015, 12, 32, 1,
    $0004002B, 12, 13, 1,
    $00040020, 14, 9, 5,
    $00050036, 2, 1, 0, 3,
    $000200F8, 15,
    $00050041, 14, 16, 11, 13,
    $0004003D, 5, 17, 16,
    $0003003E, 7, 17,
    $000100FD,
    $00010038
  );

  { 5. TCastleBatch2DRenderer Vertex Shader (CastleBatch2D.vert):
       layout(location = 0) in vec2 castle_Vertex;
       layout(location = 2) in vec2 castle_MultiTexCoord0;
       layout(location = 4) in vec4 castle_ColorPerVertex;
       layout(location = 0) out vec2 castle_tex_coord0;
       layout(location = 1) out vec4 castle_color_per_vertex;
       PushConstants(vec4 m0; vec4 m1; vec4 m2; vec4 m3) pc;
       gl_Position = vec4(castle_Vertex * pc.m0.xy + pc.m0.zw, 0.0, 1.0); }
  BuiltInBatch2DVertSPIRV: array[0..253] of UInt32 = (
    $07230203, $00010000, $00000000, $00000029, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $000B000F, 0, 1, $6E69616D, $00000000, 8, 12, 14, 16, 18, 20,
    $00050048, 6, 0, 11, 0,
    $00030047, 6, 2,
    $00040047, 12, 30, 0,
    $00040047, 14, 30, 2,
    $00040047, 16, 30, 4,
    $00040047, 18, 30, 0,
    $00040047, 20, 30, 1,
    $00050048, 21, 0, 35, 0,
    $00050048, 21, 1, 35, 16,
    $00050048, 21, 2, 35, 32,
    $00050048, 21, 3, 35, 48,
    $00030047, 21, 2,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $0003001E, 6, 5,
    $00040020, 7, 3, 6,
    $0004003B, 7, 8, 3,
    $00040015, 9, 32, 1,
    $00040017, 10, 4, 2,
    $00040020, 11, 1, 10,
    $0004003B, 11, 12, 1,
    $0004003B, 11, 14, 1,
    $00040020, 15, 1, 5,
    $0004003B, 15, 16, 1,
    $00040020, 17, 3, 10,
    $0004003B, 17, 18, 3,
    $00040020, 19, 3, 5,
    $0004003B, 19, 20, 3,
    $0006001E, 21, 5, 5, 5, 5,
    $00040020, 22, 9, 21,
    $0004003B, 22, 23, 9,
    $00040020, 24, 9, 5,
    $0004002B, 9, 13, 0,
    $0004002B, 4, 25, $00000000,
    $0004002B, 4, 26, $3F800000,
    $00050036, 2, 1, 0, 3,
    $000200F8, 27,
    $0004003D, 10, 28, 14,
    $0003003E, 18, 28,
    $0004003D, 5, 29, 16,
    $0003003E, 20, 29,
    $0004003D, 10, 30, 12,
    $00050041, 24, 31, 23, 13,
    $0004003D, 5, 32, 31,
    $0007004F, 10, 33, 32, 32, 0, 1,
    $0007004F, 10, 34, 32, 32, 2, 3,
    $00050085, 10, 35, 30, 33,
    $00050081, 10, 36, 35, 34,
    $00050051, 4, 37, 36, 0,
    $00050051, 4, 38, 36, 1,
    $00070050, 5, 39, 37, 38, 25, 26,
    $00050041, 19, 40, 8, 13,
    $0003003E, 40, 39,
    $000100FD,
    $00010038
  );

  { 6. TCastleBatch2DRenderer Fragment Shader (CastleBatch2D.frag):
       layout(set = 0, binding = 0) uniform sampler2D u_SpriteTexture;
       layout(location = 0) in vec2 castle_tex_coord0;
       layout(location = 1) in vec4 castle_color_per_vertex;
       layout(location = 0) out vec4 castle_FragColor;
       PushConstants(vec4 ViewportScaleBias; vec4 ClipLineAndEnable; vec4 AlphaParams; vec4 CustomParams) pc;
       Supports RGBA texture sampling, vertex RGBA8 tint modulation,
       TextureHasOnlyAlpha font glyph alpha mode, AlphaCutoff discard, and ClipLine half-plane discard. }
  BuiltInBatch2DFragSPIRV: array[0..340] of UInt32 = (
    $07230203, $00010000, $00000000, $0000003D, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0008000F, 4, 1, $6E69616D, $00000000, 7, 10, 12,
    $00030010, 1, 7,
    $00040047, 7, 30, 0,
    $00040047, 10, 30, 0,
    $00040047, 12, 30, 1,
    $00040047, 16, 34, 0,
    $00040047, 16, 33, 0,
    $00050048, 17, 0, 35, 0,
    $00050048, 17, 1, 35, 16,
    $00050048, 17, 2, 35, 32,
    $00050048, 17, 3, 35, 48,
    $00030047, 17, 2,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 4,
    $00040020, 6, 3, 5,
    $0004003B, 6, 7, 3,
    $00040017, 8, 4, 2,
    $00040020, 9, 1, 8,
    $0004003B, 9, 10, 1,
    $00040020, 11, 1, 5,
    $0004003B, 11, 12, 1,
    $00090019, 13, 4, 1, 0, 0, 0, 1, 0,
    $0003001B, 14, 13,
    $00040020, 15, 0, 14,
    $0004003B, 15, 16, 0,
    $0006001E, 17, 5, 5, 5, 5,
    $00040020, 18, 9, 17,
    $0004003B, 18, 19, 9,
    $00040020, 20, 9, 5,
    $00040015, 21, 32, 1,
    $0004002B, 21, 22, 1,
    $0004002B, 21, 23, 2,
    $00020014, 24,
    $00040017, 25, 24, 4,
    $0003002A, 24, 26,
    $0004002B, 4, 27, $00000000,
    $0004002B, 4, 28, $3F000000,
    $0004002B, 4, 29, $3F800000,
    $0007002C, 5, 30, 29, 29, 29, 29,
    $00050036, 2, 1, 0, 3,
    $000200F8, 31,
    $0004003D, 8, 32, 10,
    $0004003D, 5, 33, 12,
    $0004003D, 14, 34, 16,
    $00050057, 5, 35, 34, 32,
    $00050041, 20, 36, 19, 22,
    $0004003D, 5, 37, 36,
    $00050051, 4, 38, 37, 3,
    $000500BA, 24, 39, 38, 28,
    $0007004F, 8, 40, 37, 37, 0, 1,
    $00050094, 4, 41, 40, 32,
    $00050051, 4, 42, 37, 2,
    $00050081, 4, 43, 41, 42,
    $000500B8, 24, 44, 43, 27,
    $000500A7, 24, 45, 39, 44,
    $00050041, 20, 46, 19, 23,
    $0004003D, 5, 47, 46,
    $00050051, 4, 48, 47, 1,
    $000500BA, 24, 49, 48, 28,
    $00070050, 25, 50, 49, 49, 49, 26,
    $000600A9, 5, 51, 50, 30, 35,
    $00050085, 5, 52, 51, 33,
    $00050051, 4, 53, 47, 0,
    $000500BA, 24, 54, 53, 27,
    $00050051, 4, 55, 52, 3,
    $000500B8, 24, 56, 55, 53,
    $000500A7, 24, 57, 54, 56,
    $000500A6, 24, 58, 45, 57,
    $000300F7, 60, 0,
    $000400FA, 58, 59, 60,
    $000200F8, 59,
    $000100FC,
    $000200F8, 60,
    $0003003E, 7, 52,
    $000100FD,
    $00010038
  );

  { 7. BuiltIn3DPosNormUVVertSPIRV:
       - location 0: in vec3 castle_Vertex
       - location 1: in vec3 castle_Normal
       - location 2: in vec2 castle_MultiTexCoord0
       - BuiltIn Position: out vec4 gl_Position (with OpenGL->Vulkan depth remap z = (z + w) * 0.5)
       - location 0: out vec4 castle_vertex_eye
       - location 1: out vec3 castle_normal_eye
       - location 2: out vec2 castle_tex_coord0
       - set 0 binding 0: uniform CastleSceneBlock (mat4 u_ProjectionMatrix at offset 0)
       - push_constant: CastlePushConstants (mat4 u_ModelViewMatrix at 0, vec4 u_NormalMatrixRow0..2 at 64..96, vec4 u_ObjectParams at 112) }
  BuiltIn3DPosNormUVVertSPIRV: array[0..430] of UInt32 = (
    $07230203, $00010000, $00000000, $00000045, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $000C000F, 0, 36, $6E69616D, $00000000, 20, 21, 22, 23, 24, 25, 26,
    $00040047, 20, 30, 0,
    $00040047, 21, 30, 1,
    $00040047, 22, 30, 2,
    $00040047, 23, 11, 0,
    $00040047, 24, 30, 0,
    $00040047, 25, 30, 1,
    $00040047, 26, 30, 2,
    $00030047, 27, 2,
    $00040048, 27, 0, 5,
    $00050048, 27, 0, 35, 0,
    $00050048, 27, 0, 7, 16,
    $00040047, 29, 34, 0,
    $00040047, 29, 33, 0,
    $00030047, 31, 2,
    $00040048, 31, 0, 5,
    $00050048, 31, 0, 35, 0,
    $00050048, 31, 0, 7, 16,
    $00050048, 31, 1, 35, 64,
    $00050048, 31, 2, 35, 80,
    $00050048, 31, 3, 35, 96,
    $00050048, 31, 4, 35, 112,
    $00020013, 1,
    $00030021, 2, 1,
    $00030016, 3, 32,
    $00040017, 4, 3, 2,
    $00040017, 5, 3, 3,
    $00040017, 6, 3, 4,
    $00040018, 7, 6, 4,
    $00040015, 8, 32, 1,
    $0004002B, 8, 9, 0,
    $0004002B, 8, 10, 1,
    $0004002B, 8, 11, 2,
    $0004002B, 8, 12, 3,
    $0004002B, 3, 13, $3F800000,
    $0004002B, 3, 14, $3F000000,
    $00040020, 15, 1, 5,
    $00040020, 16, 1, 4,
    $00040020, 17, 3, 6,
    $00040020, 18, 3, 5,
    $00040020, 19, 3, 4,
    $0004003B, 15, 20, 1,
    $0004003B, 15, 21, 1,
    $0004003B, 16, 22, 1,
    $0004003B, 17, 23, 3,
    $0004003B, 17, 24, 3,
    $0004003B, 18, 25, 3,
    $0004003B, 19, 26, 3,
    $0003001E, 27, 7,
    $00040020, 28, 2, 27,
    $0004003B, 28, 29, 2,
    $00040020, 30, 2, 7,
    $0007001E, 31, 7, 6, 6, 6, 6,
    $00040020, 32, 9, 31,
    $0004003B, 32, 33, 9,
    $00040020, 34, 9, 7,
    $00040020, 35, 9, 6,
    $00050036, 1, 36, 0, 2,
    $000200F8, 37,
    $0004003D, 5, 38, 20,
    $00050051, 3, 39, 38, 0,
    $00050051, 3, 40, 38, 1,
    $00050051, 3, 41, 38, 2,
    $00070050, 6, 42, 39, 40, 41, 13,
    $00050041, 34, 43, 33, 9,
    $0004003D, 7, 44, 43,
    $00050091, 6, 45, 44, 42,
    $0003003E, 24, 45,
    $0004003D, 5, 46, 21,
    $00050041, 35, 47, 33, 10,
    $0004003D, 6, 48, 47,
    $0008004F, 5, 49, 48, 48, 0, 1, 2,
    $00050094, 3, 50, 49, 46,
    $00050041, 35, 51, 33, 11,
    $0004003D, 6, 52, 51,
    $0008004F, 5, 53, 52, 52, 0, 1, 2,
    $00050094, 3, 54, 53, 46,
    $00050041, 35, 55, 33, 12,
    $0004003D, 6, 56, 55,
    $0008004F, 5, 57, 56, 56, 0, 1, 2,
    $00050094, 3, 58, 57, 46,
    $00060050, 5, 59, 50, 54, 58,
    $0003003E, 25, 59,
    $0004003D, 4, 60, 22,
    $0003003E, 26, 60,
    $00050041, 30, 61, 29, 9,
    $0004003D, 7, 62, 61,
    $00050091, 6, 63, 62, 45,
    $00050051, 3, 64, 63, 2,
    $00050051, 3, 65, 63, 3,
    $00050081, 3, 66, 64, 65,
    $00050085, 3, 67, 66, 14,
    $00060052, 6, 68, 67, 63, 2,
    $0003003E, 23, 68,
    $000100FD,
    $00010038
  );

  { 8. BuiltIn3DForwardFragSPIRV (untextured 3D forward lit/unlit/alpha-cutoff fragment shader):
       - location 0: in vec4 castle_vertex_eye
       - location 1: in vec3 castle_normal_eye
       - location 2: in vec2 castle_tex_coord0
       - location 0: out vec4 castle_FragColor
       - set 0 binding 1: uniform CastleLightsBlock (u_LightCount at 0, u_L0_Position at 16, u_L0_Color at 32, u_L0_AmbientColor at 96)
       - set 1 binding 0: uniform CastleMaterialBlock (u_BaseColor at 0, u_SpecularColor at 16, u_EmissiveColor at 32, u_PBRParams at 48) }
  BuiltIn3DForwardFragSPIRV: array[0..550] of UInt32 = (
    $07230203, $00010000, $00000000, $0000005D, $00000000,
    $00020011, 1,
    $0006000B, 1, $4C534C47, $6474732E, $3035342E, $00000000,
    $0003000E, 0, 1,
    $0009000F, 4, 34, $6E69616D, $00000000, 22, 23, 24, 25,
    $00030010, 34, 7,
    $00040047, 22, 30, 0,
    $00040047, 23, 30, 1,
    $00040047, 24, 30, 2,
    $00040047, 25, 30, 0,
    $00030047, 26, 2,
    $00050048, 26, 0, 35, 0,
    $00050048, 26, 1, 35, 16,
    $00050048, 26, 2, 35, 32,
    $00050048, 26, 3, 35, 96,
    $00040047, 28, 34, 0,
    $00040047, 28, 33, 1,
    $00030047, 29, 2,
    $00050048, 29, 0, 35, 0,
    $00050048, 29, 1, 35, 16,
    $00050048, 29, 2, 35, 32,
    $00050048, 29, 3, 35, 48,
    $00040047, 31, 34, 1,
    $00040047, 31, 33, 0,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 2,
    $00040017, 6, 4, 3,
    $00040017, 7, 4, 4,
    $00020014, 8,
    $00040017, 9, 8, 3,
    $00040015, 10, 32, 1,
    $00040015, 11, 32, 0,
    $0004002B, 10, 12, 0,
    $0004002B, 10, 13, 1,
    $0004002B, 10, 14, 2,
    $0004002B, 10, 15, 3,
    $0004002B, 11, 16, 0,
    $0004002B, 4, 17, $00000000,
    $00040020, 18, 1, 7,
    $00040020, 19, 1, 6,
    $00040020, 20, 1, 5,
    $00040020, 21, 3, 7,
    $0004003B, 18, 22, 1,
    $0004003B, 19, 23, 1,
    $0004003B, 20, 24, 1,
    $0004003B, 21, 25, 3,
    $0006001E, 26, 11, 7, 7, 7,
    $00040020, 27, 2, 26,
    $0004003B, 27, 28, 2,
    $0006001E, 29, 7, 7, 7, 7,
    $00040020, 30, 2, 29,
    $0004003B, 30, 31, 2,
    $00040020, 32, 2, 11,
    $00040020, 33, 2, 7,
    $00050036, 2, 34, 0, 3,
    $000200F8, 35,
    $00050041, 33, 36, 31, 12,
    $0004003D, 7, 37, 36,
    $00050051, 4, 38, 37, 3,
    $00050041, 33, 39, 31, 15,
    $0004003D, 7, 40, 39,
    $00050051, 4, 41, 40, 3,
    $000500B8, 8, 42, 38, 41,
    $000300F7, 44, 0,
    $000400FA, 42, 43, 44,
    $000200F8, 43,
    $000100FC,
    $000200F8, 44,
    $0008004F, 6, 45, 37, 37, 0, 1, 2,
    $00050041, 33, 46, 31, 14,
    $0004003D, 7, 47, 46,
    $0008004F, 6, 48, 47, 47, 0, 1, 2,
    $00050081, 6, 49, 45, 48,
    $00050041, 32, 50, 28, 12,
    $0004003D, 11, 51, 50,
    $000500AC, 8, 52, 51, 16,
    $00060050, 9, 53, 52, 52, 52,
    $00050041, 33, 54, 28, 13,
    $0004003D, 7, 55, 54,
    $0008004F, 6, 56, 55, 55, 0, 1, 2,
    $00050051, 4, 57, 55, 3,
    $0004003D, 7, 58, 22,
    $0008004F, 6, 59, 58, 58, 0, 1, 2,
    $00050083, 6, 60, 56, 59,
    $0004007F, 6, 92, 56,
    $000500B4, 8, 61, 57, 17,
    $00060050, 9, 62, 61, 61, 61,
    $000600A9, 6, 63, 62, 92, 60,
    $0006000C, 6, 64, 1, 69, 63,
    $0004003D, 6, 65, 23,
    $0006000C, 6, 66, 1, 69, 65,
    $00050094, 4, 67, 66, 64,
    $0007000C, 4, 68, 1, 40, 67, 17,
    $00060050, 6, 69, 68, 68, 68,
    $00050041, 33, 70, 28, 14,
    $0004003D, 7, 71, 70,
    $0008004F, 6, 72, 71, 71, 0, 1, 2,
    $00050085, 6, 73, 69, 72,
    $00050085, 6, 74, 73, 45,
    $00050041, 33, 75, 28, 15,
    $0004003D, 7, 76, 75,
    $0008004F, 6, 77, 76, 76, 0, 1, 2,
    $00050085, 6, 78, 77, 45,
    $00050081, 6, 79, 74, 78,
    $00050081, 6, 80, 79, 48,
    $000600A9, 6, 81, 53, 80, 48,
    $00050041, 33, 82, 31, 13,
    $0004003D, 7, 83, 82,
    $00050051, 4, 84, 83, 3,
    $000500B8, 8, 85, 84, 17,
    $00060050, 9, 86, 85, 85, 85,
    $000600A9, 6, 87, 86, 49, 81,
    $00050051, 4, 88, 87, 0,
    $00050051, 4, 89, 87, 1,
    $00050051, 4, 90, 87, 2,
    $00070050, 7, 91, 88, 89, 90, 38,
    $0003003E, 25, 91,
    $000100FD,
    $00010038
  );

  { 9. BuiltIn3DForwardTexturedFragSPIRV (textured 3D forward lit/unlit/alpha-cutoff fragment shader):
       Same as BuiltIn3DForwardFragSPIRV, plus:
       - set 1 binding 1: uniform sampler2D castle_base_color_texture
       - baseColor = u_BaseColor * texture(castle_base_color_texture, castle_tex_coord0) }
  BuiltIn3DForwardTexturedFragSPIRV: array[0..596] of UInt32 = (
    $07230203, $00010000, $00000000, $00000065, $00000000,
    $00020011, 1,
    $0006000B, 1, $4C534C47, $6474732E, $3035342E, $00000000,
    $0003000E, 0, 1,
    $0009000F, 4, 34, $6E69616D, $00000000, 22, 23, 24, 25,
    $00030010, 34, 7,
    $00040047, 22, 30, 0,
    $00040047, 23, 30, 1,
    $00040047, 24, 30, 2,
    $00040047, 25, 30, 0,
    $00030047, 26, 2,
    $00050048, 26, 0, 35, 0,
    $00050048, 26, 1, 35, 16,
    $00050048, 26, 2, 35, 32,
    $00050048, 26, 3, 35, 96,
    $00040047, 28, 34, 0,
    $00040047, 28, 33, 1,
    $00030047, 29, 2,
    $00050048, 29, 0, 35, 0,
    $00050048, 29, 1, 35, 16,
    $00050048, 29, 2, 35, 32,
    $00050048, 29, 3, 35, 48,
    $00040047, 31, 34, 1,
    $00040047, 31, 33, 0,
    $00040047, 95, 34, 1,
    $00040047, 95, 33, 1,
    $00020013, 2,
    $00030021, 3, 2,
    $00030016, 4, 32,
    $00040017, 5, 4, 2,
    $00040017, 6, 4, 3,
    $00040017, 7, 4, 4,
    $00020014, 8,
    $00040017, 9, 8, 3,
    $00040015, 10, 32, 1,
    $00040015, 11, 32, 0,
    $0004002B, 10, 12, 0,
    $0004002B, 10, 13, 1,
    $0004002B, 10, 14, 2,
    $0004002B, 10, 15, 3,
    $0004002B, 11, 16, 0,
    $0004002B, 4, 17, $00000000,
    $00040020, 18, 1, 7,
    $00040020, 19, 1, 6,
    $00040020, 20, 1, 5,
    $00040020, 21, 3, 7,
    $0004003B, 18, 22, 1,
    $0004003B, 19, 23, 1,
    $0004003B, 20, 24, 1,
    $0004003B, 21, 25, 3,
    $0006001E, 26, 11, 7, 7, 7,
    $00040020, 27, 2, 26,
    $0004003B, 27, 28, 2,
    $0006001E, 29, 7, 7, 7, 7,
    $00040020, 30, 2, 29,
    $0004003B, 30, 31, 2,
    $00040020, 32, 2, 11,
    $00040020, 33, 2, 7,
    $00090019, 92, 4, 1, 0, 0, 0, 1, 0,
    $0003001B, 93, 92,
    $00040020, 94, 0, 93,
    $0004003B, 94, 95, 0,
    $00050036, 2, 34, 0, 3,
    $000200F8, 35,
    $00050041, 33, 36, 31, 12,
    $0004003D, 7, 96, 36,
    $0004003D, 93, 97, 95,
    $0004003D, 5, 98, 24,
    $00050057, 7, 99, 97, 98,
    $00050085, 7, 37, 96, 99,
    $00050051, 4, 38, 37, 3,
    $00050041, 33, 39, 31, 15,
    $0004003D, 7, 40, 39,
    $00050051, 4, 41, 40, 3,
    $000500B8, 8, 42, 38, 41,
    $000300F7, 44, 0,
    $000400FA, 42, 43, 44,
    $000200F8, 43,
    $000100FC,
    $000200F8, 44,
    $0008004F, 6, 45, 37, 37, 0, 1, 2,
    $00050041, 33, 46, 31, 14,
    $0004003D, 7, 47, 46,
    $0008004F, 6, 48, 47, 47, 0, 1, 2,
    $00050081, 6, 49, 45, 48,
    $00050041, 32, 50, 28, 12,
    $0004003D, 11, 51, 50,
    $000500AC, 8, 52, 51, 16,
    $00060050, 9, 53, 52, 52, 52,
    $00050041, 33, 54, 28, 13,
    $0004003D, 7, 55, 54,
    $0008004F, 6, 56, 55, 55, 0, 1, 2,
    $00050051, 4, 57, 55, 3,
    $0004003D, 7, 58, 22,
    $0008004F, 6, 59, 58, 58, 0, 1, 2,
    $00050083, 6, 60, 56, 59,
    $0004007F, 6, 100, 56,
    $000500B4, 8, 61, 57, 17,
    $00060050, 9, 62, 61, 61, 61,
    $000600A9, 6, 63, 62, 100, 60,
    $0006000C, 6, 64, 1, 69, 63,
    $0004003D, 6, 65, 23,
    $0006000C, 6, 66, 1, 69, 65,
    $00050094, 4, 67, 66, 64,
    $0007000C, 4, 68, 1, 40, 67, 17,
    $00060050, 6, 69, 68, 68, 68,
    $00050041, 33, 70, 28, 14,
    $0004003D, 7, 71, 70,
    $0008004F, 6, 72, 71, 71, 0, 1, 2,
    $00050085, 6, 73, 69, 72,
    $00050085, 6, 74, 73, 45,
    $00050041, 33, 75, 28, 15,
    $0004003D, 7, 76, 75,
    $0008004F, 6, 77, 76, 76, 0, 1, 2,
    $00050085, 6, 78, 77, 45,
    $00050081, 6, 79, 74, 78,
    $00050081, 6, 80, 79, 48,
    $000600A9, 6, 81, 53, 80, 48,
    $00050041, 33, 82, 31, 13,
    $0004003D, 7, 83, 82,
    $00050051, 4, 84, 83, 3,
    $000500B8, 8, 85, 84, 17,
    $00060050, 9, 86, 85, 85, 85,
    $000600A9, 6, 87, 86, 49, 81,
    $00050051, 4, 88, 87, 0,
    $00050051, 4, 89, 87, 1,
    $00050051, 4, 90, 87, 2,
    $00070050, 7, 91, 88, 89, 90, 38,
    $0003003E, 25, 91,
    $000100FD,
    $00010038
  );

  { 10. BuiltInVSMCasterFragSPIRV (Variance Shadow Map moments caster fragment shader):
        - BuiltIn FragCoord: in vec4 gl_FragCoord
        - location 0: out vec4 out_Moments = vec4(z, z*z, 0.0, 1.0) }
  BuiltInVSMCasterFragSPIRV: array[0..96] of UInt32 = (
    $07230203, $00010000, $00000000, $00000011, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0007000F, 4, 11, $6E69616D, $00000000, 9, 10,
    $00030010, 11, 7,
    $00040047, 9, 11, 15,
    $00040047, 10, 30, 0,
    $00020013, 1,
    $00030021, 2, 1,
    $00030016, 3, 32,
    $00040017, 4, 3, 4,
    $0004002B, 3, 5, $00000000,
    $0004002B, 3, 6, $3F800000,
    $00040020, 7, 1, 4,
    $00040020, 8, 3, 4,
    $0004003B, 7, 9, 1,
    $0004003B, 8, 10, 3,
    $00050036, 1, 11, 0, 2,
    $000200F8, 12,
    $0004003D, 4, 13, 9,
    $00050051, 3, 14, 13, 2,
    $00050085, 3, 15, 14, 14,
    $00070050, 4, 16, 14, 15, 5, 6,
    $0003003E, 10, 16,
    $000100FD,
    $00010038
  );

  { 11. BuiltInScreenEffectVertSPIRV (fullscreen post-processing quad vertex shader):
        - location 0: in vec2 vertex
        - location 1: in vec2 tex_coord
        - BuiltIn Position: out vec4 gl_Position = vec4(vertex, 0.0, 1.0)
        - location 0: out vec2 v_tex_coord = tex_coord }
  BuiltInScreenEffectVertSPIRV: array[0..126] of UInt32 = (
    $07230203, $00010000, $00000000, $00000016, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0009000F, 0, 15, $6E69616D, $00000000, 11, 12, 13, 14,
    $00040047, 11, 30, 0,
    $00040047, 12, 30, 1,
    $00040047, 13, 11, 0,
    $00040047, 14, 30, 0,
    $00020013, 1,
    $00030021, 2, 1,
    $00030016, 3, 32,
    $00040017, 4, 3, 2,
    $00040017, 5, 3, 4,
    $0004002B, 3, 6, $00000000,
    $0004002B, 3, 7, $3F800000,
    $00040020, 8, 1, 4,
    $00040020, 9, 3, 5,
    $00040020, 10, 3, 4,
    $0004003B, 8, 11, 1,
    $0004003B, 8, 12, 1,
    $0004003B, 9, 13, 3,
    $0004003B, 10, 14, 3,
    $00050036, 1, 15, 0, 2,
    $000200F8, 16,
    $0004003D, 4, 17, 11,
    $0004003D, 4, 18, 12,
    $0003003E, 14, 18,
    $00050051, 3, 19, 17, 0,
    $00050051, 3, 20, 17, 1,
    $00070050, 5, 21, 19, 20, 6, 7,
    $0003003E, 13, 21,
    $000100FD,
    $00010038
  );

  { 12. BuiltInScreenEffectPassthroughFragSPIRV (default fullscreen screen-effect blit):
        - set 0 binding 0: uniform sampler2D screen
        - location 0: in vec2 v_tex_coord
        - location 0: out vec4 castle_FragColor = texture(screen, v_tex_coord) }
  BuiltInScreenEffectPassthroughFragSPIRV: array[0..112] of UInt32 = (
    $07230203, $00010000, $00000000, $00000013, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0007000F, 4, 14, $6E69616D, $00000000, 12, 13,
    $00030010, 14, 7,
    $00040047, 9, 34, 0,
    $00040047, 9, 33, 0,
    $00040047, 12, 30, 0,
    $00040047, 13, 30, 0,
    $00020013, 1,
    $00030021, 2, 1,
    $00030016, 3, 32,
    $00040017, 4, 3, 2,
    $00040017, 5, 3, 4,
    $00090019, 6, 3, 1, 0, 0, 0, 1, 0,
    $0003001B, 7, 6,
    $00040020, 8, 0, 7,
    $0004003B, 8, 9, 0,
    $00040020, 10, 1, 4,
    $00040020, 11, 3, 5,
    $0004003B, 10, 12, 1,
    $0004003B, 11, 13, 3,
    $00050036, 1, 14, 0, 2,
    $000200F8, 15,
    $0004003D, 7, 16, 9,
    $0004003D, 4, 17, 12,
    $00050057, 5, 18, 16, 17,
    $0003003E, 13, 18,
    $000100FD,
    $00010038
  );

  { 13. BuiltInScreenEffectInvertFragSPIRV (color-invert screen-effect post-processing shader):
        - set 0 binding 0: uniform sampler2D screen
        - location 0: in vec2 v_tex_coord
        - location 0: out vec4 castle_FragColor = vec4(1.0 - c.rgb, c.a) }
  BuiltInScreenEffectInvertFragSPIRV: array[0..158] of UInt32 = (
    $07230203, $00010000, $00000000, $0000001C, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0007000F, 4, 14, $6E69616D, $00000000, 12, 13,
    $00030010, 14, 7,
    $00040047, 9, 34, 0,
    $00040047, 9, 33, 0,
    $00040047, 12, 30, 0,
    $00040047, 13, 30, 0,
    $00020013, 1,
    $00030021, 2, 1,
    $00030016, 3, 32,
    $00040017, 4, 3, 2,
    $00040017, 5, 3, 4,
    $00090019, 6, 3, 1, 0, 0, 0, 1, 0,
    $0003001B, 7, 6,
    $00040020, 8, 0, 7,
    $0004003B, 8, 9, 0,
    $00040020, 10, 1, 4,
    $00040020, 11, 3, 5,
    $0004003B, 10, 12, 1,
    $0004003B, 11, 13, 3,
    $0004002B, 3, 19, $3F800000,
    $00050036, 1, 14, 0, 2,
    $000200F8, 15,
    $0004003D, 7, 16, 9,
    $0004003D, 4, 17, 12,
    $00050057, 5, 18, 16, 17,
    $00050051, 3, 20, 18, 0,
    $00050051, 3, 21, 18, 1,
    $00050051, 3, 22, 18, 2,
    $00050051, 3, 23, 18, 3,
    $00050083, 3, 24, 19, 20,
    $00050083, 3, 25, 19, 21,
    $00050083, 3, 26, 19, 22,
    $00070050, 5, 27, 24, 25, 26, 23,
    $0003003E, 13, 27,
    $000100FD,
    $00010038
  );

  { Phase 110: Bindless Indirect & GPU Compute Culling / Hi-Z / Material Binning SPIR-V }
BuiltInGpuCullingCompSPIRV: array[0..1095] of UInt32 = (
    $07230203, $00010000, $00000000, $000000A4, $00000000, $00020011, $00000001, $0006000B,
    $00000001, $4C534C47, $6474732E, $3035342E, $00000000, $0003000E, $00000000, $00000001,
    $0006000F, $00000005, $00000002, $6E69616D, $00000000, $00000017, $00060010, $00000002,
    $00000011, $00000040, $00000001, $00000001, $00040047, $00000017, $0000000B, $0000001C,
    $00040047, $00000018, $00000006, $00000010, $00030047, $00000019, $00000002, $00050048,
    $00000019, $00000000, $00000023, $00000000, $00050048, $00000019, $00000001, $00000023,
    $00000060, $00050048, $00000019, $00000002, $00000023, $00000070, $00050048, $00000019,
    $00000003, $00000023, $00000080, $00050048, $00000019, $00000004, $00000023, $00000084,
    $00050048, $00000019, $00000005, $00000023, $00000088, $00050048, $00000019, $00000006,
    $00000023, $0000008C, $00040047, $0000001B, $00000022, $00000000, $00040047, $0000001B,
    $00000021, $00000000, $00050048, $0000001C, $00000000, $00000023, $00000000, $00050048,
    $0000001C, $00000001, $00000023, $00000010, $00050048, $0000001C, $00000002, $00000023,
    $00000020, $00050048, $0000001C, $00000003, $00000023, $00000030, $00050048, $0000001C,
    $00000004, $00000023, $00000034, $00050048, $0000001C, $00000005, $00000023, $00000038,
    $00050048, $0000001C, $00000006, $00000023, $0000003C, $00050048, $0000001C, $00000007,
    $00000023, $00000040, $00050048, $0000001C, $00000008, $00000023, $00000044, $00050048,
    $0000001C, $00000009, $00000023, $00000048, $00050048, $0000001C, $0000000A, $00000023,
    $0000004C, $00040047, $0000001D, $00000006, $00000050, $00030047, $0000001E, $00000003,
    $00050048, $0000001E, $00000000, $00000023, $00000000, $00040048, $0000001E, $00000000,
    $00000018, $00040047, $00000020, $00000022, $00000000, $00040047, $00000020, $00000021,
    $00000001, $00050048, $00000021, $00000000, $00000023, $00000000, $00050048, $00000021,
    $00000001, $00000023, $00000004, $00050048, $00000021, $00000002, $00000023, $00000008,
    $00050048, $00000021, $00000003, $00000023, $0000000C, $00050048, $00000021, $00000004,
    $00000023, $00000010, $00040047, $00000022, $00000006, $00000014, $00030047, $00000023,
    $00000003, $00050048, $00000023, $00000000, $00000023, $00000000, $00040047, $00000025,
    $00000022, $00000000, $00040047, $00000025, $00000021, $00000002, $00040047, $00000026,
    $00000006, $00000004, $00030047, $00000027, $00000003, $00050048, $00000027, $00000000,
    $00000023, $00000000, $00040047, $00000029, $00000022, $00000000, $00040047, $00000029,
    $00000021, $00000003, $00020013, $00000003, $00030021, $00000004, $00000003, $00020014,
    $00000005, $00040015, $00000006, $00000020, $00000000, $00030016, $00000007, $00000020,
    $00040017, $00000008, $00000006, $00000003, $00040017, $00000009, $00000007, $00000003,
    $00040017, $0000000A, $00000007, $00000004, $00030029, $00000005, $0000000B, $0004002B,
    $00000006, $0000000C, $00000000, $0004002B, $00000006, $0000000D, $00000001, $0004002B,
    $00000006, $0000000E, $00000002, $0004002B, $00000006, $0000000F, $00000003, $0004002B,
    $00000006, $00000010, $00000004, $0004002B, $00000006, $00000011, $00000005, $0004002B,
    $00000006, $00000012, $00000006, $0004002B, $00000006, $00000013, $00000007, $0004002B,
    $00000007, $00000014, $00000000, $00040020, $00000015, $00000001, $00000008, $00040020,
    $00000016, $00000001, $00000006, $0004003B, $00000015, $00000017, $00000001, $0004001C,
    $00000018, $0000000A, $00000012, $0009001E, $00000019, $00000018, $0000000A, $0000000A,
    $00000006, $00000006, $00000006, $00000006, $00040020, $0000001A, $00000002, $00000019,
    $0004003B, $0000001A, $0000001B, $00000002, $000D001E, $0000001C, $0000000A, $0000000A,
    $0000000A, $00000006, $00000006, $00000006, $00000006, $00000006, $00000006, $00000006,
    $00000006, $0003001D, $0000001D, $0000001C, $0003001E, $0000001E, $0000001D, $00040020,
    $0000001F, $00000002, $0000001E, $0004003B, $0000001F, $00000020, $00000002, $0007001E,
    $00000021, $00000006, $00000006, $00000006, $00000006, $00000006, $0003001D, $00000022,
    $00000021, $0003001E, $00000023, $00000022, $00040020, $00000024, $00000002, $00000023,
    $0004003B, $00000024, $00000025, $00000002, $0003001D, $00000026, $00000006, $0003001E,
    $00000027, $00000026, $00040020, $00000028, $00000002, $00000027, $0004003B, $00000028,
    $00000029, $00000002, $00040020, $0000002A, $00000002, $00000006, $00040020, $0000002B,
    $00000002, $0000000A, $00050036, $00000003, $00000002, $00000000, $00000004, $000200F8,
    $0000002C, $00050041, $00000016, $00000036, $00000017, $0000000C, $0004003D, $00000006,
    $00000037, $00000036, $00050041, $0000002A, $00000038, $0000001B, $0000000F, $0004003D,
    $00000006, $00000039, $00000038, $000500B0, $00000005, $0000003A, $00000037, $00000039,
    $000300F7, $0000002E, $00000000, $000400FA, $0000003A, $0000002D, $0000002E, $000200F8,
    $0000002D, $00070041, $0000002B, $0000003B, $00000020, $0000000C, $00000037, $0000000C,
    $0004003D, $0000000A, $0000003C, $0000003B, $0008004F, $00000009, $0000003D, $0000003C,
    $0000003C, $00000000, $00000001, $00000002, $00050051, $00000007, $0000003E, $0000003C,
    $00000003, $0007000C, $00000007, $0000003F, $00000001, $00000028, $0000003E, $00000014,
    $0004007F, $00000007, $00000040, $0000003F, $00050041, $0000002A, $00000041, $0000001B,
    $00000010, $0004003D, $00000006, $00000042, $00000041, $000500AA, $00000005, $00000043,
    $00000042, $0000000C, $00060041, $0000002B, $00000044, $0000001B, $0000000C, $0000000C,
    $0004003D, $0000000A, $00000045, $00000044, $0008004F, $00000009, $00000046, $00000045,
    $00000045, $00000000, $00000001, $00000002, $00050051, $00000007, $00000047, $00000045,
    $00000003, $00050094, $00000007, $00000048, $00000046, $0000003D, $00050081, $00000007,
    $00000049, $00000048, $00000047, $000500BA, $00000005, $0000004A, $00000049, $00000040,
    $000500A7, $00000005, $0000004B, $0000000B, $0000004A, $00060041, $0000002B, $0000004C,
    $0000001B, $0000000C, $0000000D, $0004003D, $0000000A, $0000004D, $0000004C, $0008004F,
    $00000009, $0000004E, $0000004D, $0000004D, $00000000, $00000001, $00000002, $00050051,
    $00000007, $0000004F, $0000004D, $00000003, $00050094, $00000007, $00000050, $0000004E,
    $0000003D, $00050081, $00000007, $00000051, $00000050, $0000004F, $000500BA, $00000005,
    $00000052, $00000051, $00000040, $000500A7, $00000005, $00000053, $0000004B, $00000052,
    $00060041, $0000002B, $00000054, $0000001B, $0000000C, $0000000E, $0004003D, $0000000A,
    $00000055, $00000054, $0008004F, $00000009, $00000056, $00000055, $00000055, $00000000,
    $00000001, $00000002, $00050051, $00000007, $00000057, $00000055, $00000003, $00050094,
    $00000007, $00000058, $00000056, $0000003D, $00050081, $00000007, $00000059, $00000058,
    $00000057, $000500BA, $00000005, $0000005A, $00000059, $00000040, $000500A7, $00000005,
    $0000005B, $00000053, $0000005A, $00060041, $0000002B, $0000005C, $0000001B, $0000000C,
    $0000000F, $0004003D, $0000000A, $0000005D, $0000005C, $0008004F, $00000009, $0000005E,
    $0000005D, $0000005D, $00000000, $00000001, $00000002, $00050051, $00000007, $0000005F,
    $0000005D, $00000003, $00050094, $00000007, $00000060, $0000005E, $0000003D, $00050081,
    $00000007, $00000061, $00000060, $0000005F, $000500BA, $00000005, $00000062, $00000061,
    $00000040, $000500A7, $00000005, $00000063, $0000005B, $00000062, $00060041, $0000002B,
    $00000064, $0000001B, $0000000C, $00000010, $0004003D, $0000000A, $00000065, $00000064,
    $0008004F, $00000009, $00000066, $00000065, $00000065, $00000000, $00000001, $00000002,
    $00050051, $00000007, $00000067, $00000065, $00000003, $00050094, $00000007, $00000068,
    $00000066, $0000003D, $00050081, $00000007, $00000069, $00000068, $00000067, $000500BA,
    $00000005, $0000006A, $00000069, $00000040, $000500A7, $00000005, $0000006B, $00000063,
    $0000006A, $00060041, $0000002B, $0000006C, $0000001B, $0000000C, $00000011, $0004003D,
    $0000000A, $0000006D, $0000006C, $0008004F, $00000009, $0000006E, $0000006D, $0000006D,
    $00000000, $00000001, $00000002, $00050051, $00000007, $0000006F, $0000006D, $00000003,
    $00050094, $00000007, $00000070, $0000006E, $0000003D, $00050081, $00000007, $00000071,
    $00000070, $0000006F, $000500BA, $00000005, $00000072, $00000071, $00000040, $000500A7,
    $00000005, $00000073, $0000006B, $00000072, $000500A6, $00000005, $00000074, $00000043,
    $00000073, $00050041, $0000002A, $00000075, $0000001B, $00000011, $0004003D, $00000006,
    $00000076, $00000075, $000500AB, $00000005, $00000077, $00000076, $0000000C, $00050041,
    $0000002B, $00000078, $0000001B, $0000000D, $0004003D, $0000000A, $00000079, $00000078,
    $0008004F, $00000009, $0000007A, $00000079, $00000079, $00000000, $00000001, $00000002,
    $00050051, $00000007, $0000007B, $00000079, $00000003, $000500B6, $00000005, $0000007C,
    $0000007B, $00000014, $000500A7, $00000005, $0000007D, $00000077, $0000007C, $000400A8,
    $00000005, $0000007E, $0000007D, $00050083, $00000009, $0000007F, $0000003D, $0000007A,
    $0006000C, $00000007, $00000080, $00000001, $00000042, $0000007F, $00050083, $00000007,
    $00000081, $00000080, $0000003F, $000500BC, $00000005, $00000082, $00000081, $0000007B,
    $000500A6, $00000005, $00000083, $0000007E, $00000082, $000500A7, $00000005, $00000084,
    $00000074, $00000083, $00050080, $00000006, $00000085, $00000037, $0000000D, $000600A9,
    $00000006, $00000086, $00000084, $0000000D, $0000000C, $00060041, $0000002A, $00000087,
    $00000029, $0000000C, $00000085, $0003003E, $00000087, $00000086, $00070041, $0000002A,
    $00000088, $00000020, $0000000C, $00000037, $0000000F, $0004003D, $00000006, $00000089,
    $00000088, $00070041, $0000002A, $0000008A, $00000020, $0000000C, $00000037, $00000010,
    $0004003D, $00000006, $0000008B, $0000008A, $00070041, $0000002A, $0000008C, $00000020,
    $0000000C, $00000037, $00000011, $0004003D, $00000006, $0000008D, $0000008C, $00070041,
    $0000002A, $0000008E, $00000020, $0000000C, $00000037, $00000012, $0004003D, $00000006,
    $0000008F, $0000008E, $00070041, $0000002A, $00000090, $00000020, $0000000C, $00000037,
    $00000013, $0004003D, $00000006, $00000091, $00000090, $00050041, $0000002A, $00000092,
    $0000001B, $00000012, $0004003D, $00000006, $00000093, $00000092, $000500AB, $00000005,
    $00000094, $00000093, $0000000C, $000300F7, $00000031, $00000000, $000400FA, $00000094,
    $0000002F, $00000030, $000200F8, $0000002F, $000300F7, $00000033, $00000000, $000400FA,
    $00000084, $00000032, $00000033, $000200F8, $00000032, $00060041, $0000002A, $00000095,
    $00000029, $0000000C, $0000000C, $000700EA, $00000006, $00000096, $00000095, $0000000D,
    $0000000C, $0000000D, $00070041, $0000002A, $00000097, $00000025, $0000000C, $00000096,
    $0000000C, $0003003E, $00000097, $00000089, $00070041, $0000002A, $00000098, $00000025,
    $0000000C, $00000096, $0000000D, $0003003E, $00000098, $00000091, $00070041, $0000002A,
    $00000099, $00000025, $0000000C, $00000096, $0000000E, $0003003E, $00000099, $0000008B,
    $00070041, $0000002A, $0000009A, $00000025, $0000000C, $00000096, $0000000F, $0003003E,
    $0000009A, $0000008D, $00070041, $0000002A, $0000009B, $00000025, $0000000C, $00000096,
    $00000010, $0003003E, $0000009B, $0000008F, $000200F9, $00000033, $000200F8, $00000033,
    $000200F9, $00000031, $000200F8, $00000030, $000600A9, $00000006, $0000009C, $00000084,
    $00000091, $0000000C, $00070041, $0000002A, $0000009D, $00000025, $0000000C, $00000037,
    $0000000C, $0003003E, $0000009D, $00000089, $00070041, $0000002A, $0000009E, $00000025,
    $0000000C, $00000037, $0000000D, $0003003E, $0000009E, $0000009C, $00070041, $0000002A,
    $0000009F, $00000025, $0000000C, $00000037, $0000000E, $0003003E, $0000009F, $0000008B,
    $00070041, $0000002A, $000000A0, $00000025, $0000000C, $00000037, $0000000F, $0003003E,
    $000000A0, $0000008D, $00070041, $0000002A, $000000A1, $00000025, $0000000C, $00000037,
    $00000010, $0003003E, $000000A1, $0000008F, $000300F7, $00000035, $00000000, $000400FA,
    $00000084, $00000034, $00000035, $000200F8, $00000034, $00060041, $0000002A, $000000A2,
    $00000029, $0000000C, $0000000C, $000700EA, $00000006, $000000A3, $000000A2, $0000000D,
    $0000000C, $0000000D, $000200F9, $00000035, $000200F8, $00000035, $000200F9, $00000031,
    $000200F8, $00000031, $000200F9, $0000002E, $000200F8, $0000002E, $000100FD, $00010038
  );

  BuiltInHiZDownsampleCompSPIRV: array[0..590] of UInt32 = (
    $07230203, $00010000, $00000000, $0000006D, $00000000, $00020011, $00000001, $0006000B,
    $00000001, $4C534C47, $6474732E, $3035342E, $00000000, $0003000E, $00000000, $00000001,
    $0006000F, $00000005, $00000002, $6E69616D, $00000000, $00000016, $00060010, $00000002,
    $00000011, $00000008, $00000008, $00000001, $00040047, $00000016, $0000000B, $0000001C,
    $00040047, $0000001A, $00000022, $00000000, $00040047, $0000001A, $00000021, $00000000,
    $00040047, $0000001D, $00000022, $00000000, $00040047, $0000001D, $00000021, $00000001,
    $00030047, $0000001D, $00000019, $00030047, $0000001E, $00000002, $00050048, $0000001E,
    $00000000, $00000023, $00000000, $00050048, $0000001E, $00000001, $00000023, $00000004,
    $00050048, $0000001E, $00000002, $00000023, $00000008, $00050048, $0000001E, $00000003,
    $00000023, $0000000C, $00020013, $00000003, $00030021, $00000004, $00000003, $00020014,
    $00000005, $00040015, $00000006, $00000020, $00000000, $00040015, $00000007, $00000020,
    $00000001, $00030016, $00000008, $00000020, $00040017, $00000009, $00000006, $00000002,
    $00040017, $0000000A, $00000007, $00000002, $00040017, $0000000B, $00000006, $00000003,
    $00040017, $0000000C, $00000008, $00000002, $00040017, $0000000D, $00000008, $00000004,
    $0004002B, $00000006, $0000000E, $00000000, $0004002B, $00000006, $0000000F, $00000001,
    $0004002B, $00000006, $00000010, $00000002, $0004002B, $00000006, $00000011, $00000003,
    $0004002B, $00000008, $00000012, $00000000, $0004002B, $00000008, $00000013, $3F000000,
    $0004002B, $00000008, $00000014, $3F800000, $00040020, $00000015, $00000001, $0000000B,
    $0004003B, $00000015, $00000016, $00000001, $00090019, $00000017, $00000008, $00000001,
    $00000000, $00000000, $00000000, $00000001, $00000000, $0003001B, $00000018, $00000017,
    $00040020, $00000019, $00000000, $00000018, $0004003B, $00000019, $0000001A, $00000000,
    $00090019, $0000001B, $00000008, $00000001, $00000000, $00000000, $00000000, $00000002,
    $00000003, $00040020, $0000001C, $00000000, $0000001B, $0004003B, $0000001C, $0000001D,
    $00000000, $0006001E, $0000001E, $00000006, $00000006, $00000006, $00000006, $00040020,
    $0000001F, $00000009, $0000001E, $00040020, $00000020, $00000009, $00000006, $0004003B,
    $0000001F, $00000021, $00000009, $00050036, $00000003, $00000002, $00000000, $00000004,
    $000200F8, $00000022, $0004003D, $0000000B, $00000025, $00000016, $00050051, $00000006,
    $00000026, $00000025, $00000000, $00050051, $00000006, $00000027, $00000025, $00000001,
    $00050041, $00000020, $00000028, $00000021, $0000000E, $0004003D, $00000006, $00000029,
    $00000028, $00050041, $00000020, $0000002A, $00000021, $0000000F, $0004003D, $00000006,
    $0000002B, $0000002A, $000500B0, $00000005, $0000002C, $00000026, $00000029, $000500B0,
    $00000005, $0000002D, $00000027, $0000002B, $000500A7, $00000005, $0000002E, $0000002C,
    $0000002D, $000300F7, $00000024, $00000000, $000400FA, $0000002E, $00000023, $00000024,
    $000200F8, $00000023, $00050041, $00000020, $0000002F, $00000021, $00000010, $0004003D,
    $00000006, $00000030, $0000002F, $00050041, $00000020, $00000031, $00000021, $00000011,
    $0004003D, $00000006, $00000032, $00000031, $00040070, $00000008, $00000033, $00000030,
    $00040070, $00000008, $00000034, $00000032, $0007000C, $00000008, $00000035, $00000001,
    $00000028, $00000033, $00000014, $0007000C, $00000008, $00000036, $00000001, $00000028,
    $00000034, $00000014, $00050084, $00000006, $00000037, $00000026, $00000010, $00050084,
    $00000006, $00000038, $00000027, $00000010, $0004003D, $00000018, $00000039, $0000001A,
    $00050080, $00000006, $0000003A, $00000037, $0000000E, $00050080, $00000006, $0000003B,
    $00000038, $0000000E, $00040070, $00000008, $0000003C, $0000003A, $00040070, $00000008,
    $0000003D, $0000003B, $00050081, $00000008, $0000003E, $0000003C, $00000013, $00050081,
    $00000008, $0000003F, $0000003D, $00000013, $00050088, $00000008, $00000040, $0000003E,
    $00000035, $00050088, $00000008, $00000041, $0000003F, $00000036, $00050050, $0000000C,
    $00000042, $00000040, $00000041, $00070058, $0000000D, $00000043, $00000039, $00000042,
    $00000002, $00000012, $00050051, $00000008, $00000044, $00000043, $00000000, $00050080,
    $00000006, $00000045, $00000037, $0000000F, $00050080, $00000006, $00000046, $00000038,
    $0000000E, $00040070, $00000008, $00000047, $00000045, $00040070, $00000008, $00000048,
    $00000046, $00050081, $00000008, $00000049, $00000047, $00000013, $00050081, $00000008,
    $0000004A, $00000048, $00000013, $00050088, $00000008, $0000004B, $00000049, $00000035,
    $00050088, $00000008, $0000004C, $0000004A, $00000036, $00050050, $0000000C, $0000004D,
    $0000004B, $0000004C, $00070058, $0000000D, $0000004E, $00000039, $0000004D, $00000002,
    $00000012, $00050051, $00000008, $0000004F, $0000004E, $00000000, $00050080, $00000006,
    $00000050, $00000037, $0000000E, $00050080, $00000006, $00000051, $00000038, $0000000F,
    $00040070, $00000008, $00000052, $00000050, $00040070, $00000008, $00000053, $00000051,
    $00050081, $00000008, $00000054, $00000052, $00000013, $00050081, $00000008, $00000055,
    $00000053, $00000013, $00050088, $00000008, $00000056, $00000054, $00000035, $00050088,
    $00000008, $00000057, $00000055, $00000036, $00050050, $0000000C, $00000058, $00000056,
    $00000057, $00070058, $0000000D, $00000059, $00000039, $00000058, $00000002, $00000012,
    $00050051, $00000008, $0000005A, $00000059, $00000000, $00050080, $00000006, $0000005B,
    $00000037, $0000000F, $00050080, $00000006, $0000005C, $00000038, $0000000F, $00040070,
    $00000008, $0000005D, $0000005B, $00040070, $00000008, $0000005E, $0000005C, $00050081,
    $00000008, $0000005F, $0000005D, $00000013, $00050081, $00000008, $00000060, $0000005E,
    $00000013, $00050088, $00000008, $00000061, $0000005F, $00000035, $00050088, $00000008,
    $00000062, $00000060, $00000036, $00050050, $0000000C, $00000063, $00000061, $00000062,
    $00070058, $0000000D, $00000064, $00000039, $00000063, $00000002, $00000012, $00050051,
    $00000008, $00000065, $00000064, $00000000, $0007000C, $00000008, $00000066, $00000001,
    $00000028, $00000044, $0000004F, $0007000C, $00000008, $00000067, $00000001, $00000028,
    $0000005A, $00000065, $0007000C, $00000008, $00000068, $00000001, $00000028, $00000066,
    $00000067, $00070050, $0000000D, $00000069, $00000068, $00000012, $00000012, $00000014,
    $00050050, $00000009, $0000006A, $00000026, $00000027, $0004007C, $0000000A, $0000006B,
    $0000006A, $0004003D, $0000001B, $0000006C, $0000001D, $00040063, $0000006C, $0000006B,
    $00000069, $000200F9, $00000024, $000200F8, $00000024, $000100FD, $00010038
  );

  BuiltInMaterialBinHistCompSPIRV: array[0..291] of UInt32 = (
    $07230203, $00010000, $00000000, $0000002E, $00000000, $00020011, $00000001, $0003000E,
    $00000000, $00000001, $0006000F, $00000005, $00000001, $6E69616D, $00000000, $0000000B,
    $00060010, $00000001, $00000011, $00000040, $00000001, $00000001, $00040047, $0000000B,
    $0000000B, $0000001C, $00040047, $0000000C, $00000006, $00000004, $00030047, $0000000D,
    $00000003, $00050048, $0000000D, $00000000, $00000023, $00000000, $00040048, $0000000D,
    $00000000, $00000018, $00040047, $0000000F, $00000022, $00000000, $00040047, $0000000F,
    $00000021, $00000000, $00040047, $00000010, $00000006, $00000004, $00030047, $00000011,
    $00000003, $00050048, $00000011, $00000000, $00000023, $00000000, $00040047, $00000013,
    $00000022, $00000000, $00040047, $00000013, $00000021, $00000001, $00040047, $00000014,
    $00000006, $00000004, $00030047, $00000015, $00000003, $00050048, $00000015, $00000000,
    $00000023, $00000000, $00040047, $00000017, $00000022, $00000000, $00040047, $00000017,
    $00000021, $00000002, $00030047, $00000018, $00000002, $00050048, $00000018, $00000000,
    $00000023, $00000000, $00050048, $00000018, $00000001, $00000023, $00000004, $00020013,
    $00000002, $00030021, $00000003, $00000002, $00020014, $00000004, $00040015, $00000005,
    $00000020, $00000000, $00040017, $00000006, $00000005, $00000003, $0004002B, $00000005,
    $00000007, $00000000, $0004002B, $00000005, $00000008, $00000001, $00040020, $00000009,
    $00000001, $00000006, $00040020, $0000000A, $00000001, $00000005, $0004003B, $00000009,
    $0000000B, $00000001, $0003001D, $0000000C, $00000005, $0003001E, $0000000D, $0000000C,
    $00040020, $0000000E, $00000002, $0000000D, $0004003B, $0000000E, $0000000F, $00000002,
    $0003001D, $00000010, $00000005, $0003001E, $00000011, $00000010, $00040020, $00000012,
    $00000002, $00000011, $0004003B, $00000012, $00000013, $00000002, $0003001D, $00000014,
    $00000005, $0003001E, $00000015, $00000014, $00040020, $00000016, $00000002, $00000015,
    $0004003B, $00000016, $00000017, $00000002, $0004001E, $00000018, $00000005, $00000005,
    $00040020, $00000019, $00000009, $00000018, $00040020, $0000001A, $00000009, $00000005,
    $0004003B, $00000019, $0000001B, $00000009, $00040020, $0000001C, $00000002, $00000005,
    $00050036, $00000002, $00000001, $00000000, $00000003, $000200F8, $0000001D, $00050041,
    $0000000A, $00000020, $0000000B, $00000007, $0004003D, $00000005, $00000021, $00000020,
    $00050041, $0000001A, $00000022, $0000001B, $00000007, $0004003D, $00000005, $00000023,
    $00000022, $00050041, $0000001A, $00000024, $0000001B, $00000008, $0004003D, $00000005,
    $00000025, $00000024, $000500B0, $00000004, $00000026, $00000021, $00000023, $000500AC,
    $00000004, $00000027, $00000025, $00000007, $000500A7, $00000004, $00000028, $00000026,
    $00000027, $000300F7, $0000001F, $00000000, $000400FA, $00000028, $0000001E, $0000001F,
    $000200F8, $0000001E, $00060041, $0000001C, $00000029, $0000000F, $00000007, $00000021,
    $0004003D, $00000005, $0000002A, $00000029, $0005008A, $00000005, $0000002B, $0000002A,
    $00000025, $00060041, $0000001C, $0000002C, $00000013, $00000007, $0000002B, $000700EA,
    $00000005, $0000002D, $0000002C, $00000008, $00000007, $00000008, $000200F9, $0000001F,
    $000200F8, $0000001F, $000100FD, $00010038
  );

  BuiltInMaterialBinScanCompSPIRV: array[0..292] of UInt32 = (
    $07230203, $00010000, $00000000, $0000002C, $00000000, $00020011, $00000001, $0003000E,
    $00000000, $00000001, $0005000F, $00000005, $00000001, $6E69616D, $00000000, $00060010,
    $00000001, $00000011, $00000001, $00000001, $00000001, $00040047, $00000008, $00000006,
    $00000004, $00030047, $00000009, $00000003, $00050048, $00000009, $00000000, $00000023,
    $00000000, $00040048, $00000009, $00000000, $00000018, $00040047, $0000000B, $00000022,
    $00000000, $00040047, $0000000B, $00000021, $00000000, $00040047, $0000000C, $00000006,
    $00000004, $00030047, $0000000D, $00000003, $00050048, $0000000D, $00000000, $00000023,
    $00000000, $00040048, $0000000D, $00000000, $00000018, $00040047, $0000000F, $00000022,
    $00000000, $00040047, $0000000F, $00000021, $00000001, $00040047, $00000010, $00000006,
    $00000004, $00030047, $00000011, $00000003, $00050048, $00000011, $00000000, $00000023,
    $00000000, $00040047, $00000013, $00000022, $00000000, $00040047, $00000013, $00000021,
    $00000002, $00030047, $00000014, $00000002, $00050048, $00000014, $00000000, $00000023,
    $00000000, $00050048, $00000014, $00000001, $00000023, $00000004, $00020013, $00000002,
    $00030021, $00000003, $00000002, $00020014, $00000004, $00040015, $00000005, $00000020,
    $00000000, $0004002B, $00000005, $00000006, $00000000, $0004002B, $00000005, $00000007,
    $00000001, $0003001D, $00000008, $00000005, $0003001E, $00000009, $00000008, $00040020,
    $0000000A, $00000002, $00000009, $0004003B, $0000000A, $0000000B, $00000002, $0003001D,
    $0000000C, $00000005, $0003001E, $0000000D, $0000000C, $00040020, $0000000E, $00000002,
    $0000000D, $0004003B, $0000000E, $0000000F, $00000002, $0003001D, $00000010, $00000005,
    $0003001E, $00000011, $00000010, $00040020, $00000012, $00000002, $00000011, $0004003B,
    $00000012, $00000013, $00000002, $0004001E, $00000014, $00000005, $00000005, $00040020,
    $00000015, $00000009, $00000014, $00040020, $00000016, $00000009, $00000005, $0004003B,
    $00000015, $00000017, $00000009, $00040020, $00000018, $00000002, $00000005, $00040020,
    $00000019, $00000007, $00000005, $00050036, $00000002, $00000001, $00000000, $00000003,
    $000200F8, $0000001A, $0004003B, $00000019, $0000001F, $00000007, $0004003B, $00000019,
    $00000020, $00000007, $0003003E, $0000001F, $00000006, $0003003E, $00000020, $00000006,
    $00050041, $00000016, $00000021, $00000017, $00000007, $0004003D, $00000005, $00000022,
    $00000021, $000200F9, $0000001B, $000200F8, $0000001B, $0004003D, $00000005, $00000023,
    $0000001F, $000500B0, $00000004, $00000024, $00000023, $00000022, $000400F6, $0000001E,
    $0000001D, $00000000, $000400FA, $00000024, $0000001C, $0000001E, $000200F8, $0000001C,
    $00060041, $00000018, $00000025, $0000000F, $00000006, $00000023, $0004003D, $00000005,
    $00000026, $00000025, $0004003D, $00000005, $00000027, $00000020, $00060041, $00000018,
    $00000028, $00000013, $00000006, $00000023, $0003003E, $00000028, $00000027, $00050080,
    $00000005, $00000029, $00000027, $00000026, $0003003E, $00000020, $00000029, $000200F9,
    $0000001D, $000200F8, $0000001D, $0004003D, $00000005, $0000002A, $0000001F, $00050080,
    $00000005, $0000002B, $0000002A, $00000007, $0003003E, $0000001F, $0000002B, $000200F9,
    $0000001B, $000200F8, $0000001E, $000100FD, $00010038
  );

  BuiltInBindlessIndirectVertSPIRV: array[0..498] of UInt32 = (
    $07230203, $00010000, $00000000, $0000004C, $00000000, $00020011, $00000001, $0003000E,
    $00000000, $00000001, $000E000F, $00000000, $00000001, $6E69616D, $00000000, $00000014,
    $00000015, $00000016, $00000017, $0000001C, $0000001D, $0000001E, $0000001F, $00000020,
    $00040047, $00000014, $0000001E, $00000000, $00040047, $00000015, $0000001E, $00000001,
    $00040047, $00000016, $0000001E, $00000002, $00040047, $00000017, $0000000B, $0000002B,
    $00040047, $0000001C, $0000000B, $00000000, $00040047, $0000001D, $0000001E, $00000000,
    $00040047, $0000001E, $0000001E, $00000001, $00040047, $0000001F, $0000001E, $00000002,
    $00030047, $0000001F, $0000000E, $00040047, $00000020, $0000001E, $00000003, $00030047,
    $00000020, $0000000E, $00030047, $00000021, $00000002, $00040048, $00000021, $00000000,
    $00000005, $00050048, $00000021, $00000000, $00000023, $00000000, $00050048, $00000021,
    $00000000, $00000007, $00000010, $00050048, $00000021, $00000001, $00000023, $00000040,
    $00040047, $00000023, $00000022, $00000000, $00040047, $00000023, $00000021, $00000000,
    $00040048, $00000024, $00000000, $00000005, $00050048, $00000024, $00000000, $00000023,
    $00000000, $00050048, $00000024, $00000000, $00000007, $00000010, $00050048, $00000024,
    $00000001, $00000023, $00000040, $00050048, $00000024, $00000002, $00000023, $00000044,
    $00050048, $00000024, $00000003, $00000023, $00000048, $00040047, $00000025, $00000006,
    $00000050, $00030047, $00000026, $00000003, $00050048, $00000026, $00000000, $00000023,
    $00000000, $00040048, $00000026, $00000000, $00000018, $00040047, $00000028, $00000022,
    $00000000, $00040047, $00000028, $00000021, $00000001, $00020013, $00000002, $00030021,
    $00000003, $00000002, $00040015, $00000004, $00000020, $00000000, $00040015, $00000005,
    $00000020, $00000001, $00030016, $00000006, $00000020, $00040017, $00000007, $00000006,
    $00000002, $00040017, $00000008, $00000006, $00000003, $00040017, $00000009, $00000006,
    $00000004, $00040018, $0000000A, $00000009, $00000004, $0004002B, $00000004, $0000000B,
    $00000000, $0004002B, $00000004, $0000000C, $00000001, $0004002B, $00000004, $0000000D,
    $00000002, $0004002B, $00000006, $0000000E, $00000000, $0004002B, $00000006, $0000000F,
    $3F000000, $0004002B, $00000006, $00000010, $3F800000, $00040020, $00000011, $00000001,
    $00000008, $00040020, $00000012, $00000001, $00000007, $00040020, $00000013, $00000001,
    $00000005, $0004003B, $00000011, $00000014, $00000001, $0004003B, $00000011, $00000015,
    $00000001, $0004003B, $00000012, $00000016, $00000001, $0004003B, $00000013, $00000017,
    $00000001, $00040020, $00000018, $00000003, $00000009, $00040020, $00000019, $00000003,
    $00000008, $00040020, $0000001A, $00000003, $00000007, $00040020, $0000001B, $00000003,
    $00000004, $0004003B, $00000018, $0000001C, $00000003, $0004003B, $00000019, $0000001D,
    $00000003, $0004003B, $0000001A, $0000001E, $00000003, $0004003B, $0000001B, $0000001F,
    $00000003, $0004003B, $0000001B, $00000020, $00000003, $0004001E, $00000021, $0000000A,
    $00000009, $00040020, $00000022, $00000002, $00000021, $0004003B, $00000022, $00000023,
    $00000002, $0006001E, $00000024, $0000000A, $00000004, $00000004, $00000007, $0003001D,
    $00000025, $00000024, $0003001E, $00000026, $00000025, $00040020, $00000027, $00000002,
    $00000026, $0004003B, $00000027, $00000028, $00000002, $00040020, $00000029, $00000002,
    $0000000A, $00040020, $0000002A, $00000002, $00000004, $00050036, $00000002, $00000001,
    $00000000, $00000003, $000200F8, $0000002B, $0004003D, $00000005, $0000002C, $00000017,
    $0004007C, $00000004, $0000002D, $0000002C, $00070041, $00000029, $0000002E, $00000028,
    $0000000B, $0000002D, $0000000B, $0004003D, $0000000A, $0000002F, $0000002E, $00050041,
    $00000029, $00000030, $00000023, $0000000B, $0004003D, $0000000A, $00000031, $00000030,
    $0004003D, $00000008, $00000032, $00000014, $00050051, $00000006, $00000033, $00000032,
    $00000000, $00050051, $00000006, $00000034, $00000032, $00000001, $00050051, $00000006,
    $00000035, $00000032, $00000002, $00070050, $00000009, $00000036, $00000033, $00000034,
    $00000035, $00000010, $00050091, $00000009, $00000037, $0000002F, $00000036, $00050091,
    $00000009, $00000038, $00000031, $00000037, $00050051, $00000006, $00000039, $00000038,
    $00000000, $00050051, $00000006, $0000003A, $00000038, $00000001, $00050051, $00000006,
    $0000003B, $00000038, $00000002, $00050051, $00000006, $0000003C, $00000038, $00000003,
    $00050081, $00000006, $0000003D, $0000003B, $0000003C, $00050085, $00000006, $0000003E,
    $0000003D, $0000000F, $00070050, $00000009, $0000003F, $00000039, $0000003A, $0000003E,
    $0000003C, $0003003E, $0000001C, $0000003F, $0004003D, $00000008, $00000040, $00000015,
    $00050051, $00000006, $00000041, $00000040, $00000000, $00050051, $00000006, $00000042,
    $00000040, $00000001, $00050051, $00000006, $00000043, $00000040, $00000002, $00070050,
    $00000009, $00000044, $00000041, $00000042, $00000043, $0000000E, $00050091, $00000009,
    $00000045, $0000002F, $00000044, $0008004F, $00000008, $00000046, $00000045, $00000045,
    $00000000, $00000001, $00000002, $0003003E, $0000001D, $00000046, $0004003D, $00000007,
    $00000047, $00000016, $0003003E, $0000001E, $00000047, $00070041, $0000002A, $00000048,
    $00000028, $0000000B, $0000002D, $0000000C, $0004003D, $00000004, $00000049, $00000048,
    $0003003E, $0000001F, $00000049, $00070041, $0000002A, $0000004A, $00000028, $0000000B,
    $0000002D, $0000000D, $0004003D, $00000004, $0000004B, $0000004A, $0003003E, $00000020,
    $0000004B, $000100FD, $00010038
  );

  BuiltInBindlessIndirectFragSPIRV: array[0..693] of UInt32 = (
    $07230203, $00010300, $00000000, $0000006B, $00000000, $00020011, $00000001, $00020011,
    $000014B5, $00020011, $000014B6, $00020011, $000014BB, $0008000A, $5F565053, $5F545845,
    $63736564, $74706972, $695F726F, $7865646E, $00676E69, $0006000B, $00000001, $4C534C47,
    $6474732E, $3035342E, $00000000, $0003000E, $00000000, $00000001, $000A000F, $00000004,
    $00000002, $6E69616D, $00000000, $00000016, $00000017, $00000018, $00000019, $0000001B,
    $00030010, $00000002, $00000007, $00040047, $00000016, $0000001E, $00000000, $00040047,
    $00000017, $0000001E, $00000001, $00040047, $00000018, $0000001E, $00000002, $00030047,
    $00000018, $0000000E, $00040047, $00000019, $0000001E, $00000003, $00030047, $00000019,
    $0000000E, $00040047, $0000001B, $0000001E, $00000000, $00030047, $0000001C, $00000002,
    $00040048, $0000001C, $00000000, $00000005, $00050048, $0000001C, $00000000, $00000023,
    $00000000, $00050048, $0000001C, $00000000, $00000007, $00000010, $00050048, $0000001C,
    $00000001, $00000023, $00000040, $00040047, $0000001F, $00000022, $00000000, $00040047,
    $0000001F, $00000021, $00000000, $00040047, $00000025, $00000022, $00000001, $00040047,
    $00000025, $00000021, $00000000, $00050048, $00000026, $00000000, $00000023, $00000000,
    $00050048, $00000026, $00000001, $00000023, $00000010, $00050048, $00000026, $00000002,
    $00000023, $00000020, $00050048, $00000026, $00000003, $00000023, $00000030, $00050048,
    $00000026, $00000004, $00000023, $00000040, $00050048, $00000026, $00000005, $00000023,
    $00000044, $00050048, $00000026, $00000006, $00000023, $00000048, $00050048, $00000026,
    $00000007, $00000023, $0000004C, $00040047, $00000027, $00000006, $00000050, $00030047,
    $00000028, $00000002, $00050048, $00000028, $00000000, $00000023, $00000000, $00040048,
    $00000028, $00000000, $00000018, $00040047, $0000002C, $00000022, $00000001, $00040047,
    $0000002C, $00000021, $00000001, $00030047, $00000047, $000014B4, $00030047, $00000048,
    $000014B4, $00030047, $00000049, $000014B4, $00020013, $00000003, $00030021, $00000004,
    $00000003, $00020014, $00000005, $00040015, $00000006, $00000020, $00000000, $00030016,
    $00000007, $00000020, $00040017, $00000008, $00000007, $00000002, $00040017, $00000009,
    $00000007, $00000003, $00040017, $0000000A, $00000007, $00000004, $00040018, $0000000B,
    $0000000A, $00000004, $0004002B, $00000006, $0000000C, $00000000, $0004002B, $00000006,
    $0000000D, $00000001, $0004002B, $00000006, $0000000E, $00000002, $0004002B, $00000006,
    $0000000F, $00000003, $0004002B, $00000006, $00000010, $00000004, $0004002B, $00000007,
    $00000011, $00000000, $0004002B, $00000007, $00000012, $3F800000, $00040020, $00000013,
    $00000001, $00000009, $00040020, $00000014, $00000001, $00000008, $00040020, $00000015,
    $00000001, $00000006, $0004003B, $00000013, $00000016, $00000001, $0004003B, $00000014,
    $00000017, $00000001, $0004003B, $00000015, $00000018, $00000001, $0004003B, $00000015,
    $00000019, $00000001, $00040020, $0000001A, $00000003, $0000000A, $0004003B, $0000001A,
    $0000001B, $00000003, $0004001E, $0000001C, $0000000B, $0000000A, $00040020, $0000001D,
    $00000002, $0000001C, $00040020, $0000001E, $00000002, $0000000A, $0004003B, $0000001D,
    $0000001F, $00000002, $00090019, $00000020, $00000007, $00000001, $00000000, $00000000,
    $00000000, $00000001, $00000000, $0003001B, $00000021, $00000020, $0003001D, $00000022,
    $00000021, $00040020, $00000023, $00000000, $00000022, $00040020, $00000024, $00000000,
    $00000021, $0004003B, $00000023, $00000025, $00000000, $000A001E, $00000026, $0000000A,
    $0000000A, $0000000A, $0000000A, $00000006, $00000006, $00000006, $00000006, $0003001D,
    $00000027, $00000026, $0003001E, $00000028, $00000027, $00040020, $00000029, $0000000C,
    $00000028, $00040020, $0000002A, $0000000C, $0000000A, $00040020, $0000002B, $0000000C,
    $00000006, $0004003B, $00000029, $0000002C, $0000000C, $00040020, $0000002D, $00000007,
    $0000000A, $00040020, $0000002E, $00000007, $00000009, $00050036, $00000003, $00000002,
    $00000000, $00000004, $000200F8, $0000002F, $0004003B, $0000002D, $00000037, $00000007,
    $0004003B, $0000002E, $00000038, $00000007, $0004003D, $00000006, $00000039, $00000018,
    $0004003D, $00000006, $0000003A, $00000019, $0004003D, $00000008, $0000003B, $00000017,
    $00070041, $0000002A, $0000003C, $0000002C, $0000000C, $00000039, $0000000C, $0004003D,
    $0000000A, $0000003D, $0000003C, $0003003E, $00000037, $0000003D, $00070041, $0000002A,
    $0000003E, $0000002C, $0000000C, $00000039, $0000000E, $0004003D, $0000000A, $0000003F,
    $0000003E, $0008004F, $00000009, $00000040, $0000003F, $0000003F, $00000000, $00000001,
    $00000002, $00070041, $0000002A, $00000041, $0000002C, $0000000C, $00000039, $0000000F,
    $0004003D, $0000000A, $00000042, $00000041, $00050051, $00000007, $00000043, $00000042,
    $00000003, $000500C7, $00000006, $00000044, $0000003A, $0000000D, $000500AB, $00000005,
    $00000045, $00000044, $0000000C, $000300F7, $00000031, $00000000, $000400FA, $00000045,
    $00000030, $00000031, $000200F8, $00000030, $00070041, $0000002B, $00000046, $0000002C,
    $0000000C, $00000039, $00000010, $0004003D, $00000006, $00000047, $00000046, $00050041,
    $00000024, $00000048, $00000025, $00000047, $0004003D, $00000021, $00000049, $00000048,
    $00050057, $0000000A, $0000004A, $00000049, $0000003B, $0004003D, $0000000A, $0000004B,
    $00000037, $00050085, $0000000A, $0000004C, $0000004B, $0000004A, $0003003E, $00000037,
    $0000004C, $000200F9, $00000031, $000200F8, $00000031, $0004003D, $0000000A, $0000004D,
    $00000037, $00050051, $00000007, $0000004E, $0000004D, $00000003, $000500C7, $00000006,
    $0000004F, $0000003A, $00000010, $000500AB, $00000005, $00000050, $0000004F, $0000000C,
    $000500B8, $00000005, $00000051, $0000004E, $00000043, $000500A7, $00000005, $00000052,
    $00000050, $00000051, $000300F7, $00000033, $00000000, $000400FA, $00000052, $00000032,
    $00000033, $000200F8, $00000032, $000100FC, $000200F8, $00000033, $0008004F, $00000009,
    $00000053, $0000004D, $0000004D, $00000000, $00000001, $00000002, $000500C7, $00000006,
    $00000054, $0000003A, $0000000E, $000500AB, $00000005, $00000055, $00000054, $0000000C,
    $000300F7, $00000036, $00000000, $000400FA, $00000055, $00000034, $00000035, $000200F8,
    $00000034, $0004003D, $00000009, $00000056, $00000016, $0006000C, $00000009, $00000057,
    $00000001, $00000045, $00000056, $00050041, $0000001E, $00000058, $0000001F, $0000000D,
    $0004003D, $0000000A, $00000059, $00000058, $0008004F, $00000009, $0000005A, $00000059,
    $00000059, $00000000, $00000001, $00000002, $0006000C, $00000009, $0000005B, $00000001,
    $00000045, $0000005A, $00050051, $00000007, $0000005C, $00000059, $00000003, $00050094,
    $00000007, $0000005D, $00000057, $0000005B, $0007000C, $00000007, $0000005E, $00000001,
    $00000028, $0000005D, $00000011, $00050083, $00000007, $0000005F, $00000012, $0000005C,
    $00050085, $00000007, $00000060, $0000005F, $0000005E, $00050081, $00000007, $00000061,
    $0000005C, $00000060, $0008000C, $00000007, $00000062, $00000001, $0000002B, $00000061,
    $00000011, $00000012, $0005008E, $00000009, $00000063, $00000053, $00000062, $00050081,
    $00000009, $00000064, $00000063, $00000040, $0003003E, $00000038, $00000064, $000200F9,
    $00000036, $000200F8, $00000035, $00050081, $00000009, $00000065, $00000053, $00000040,
    $0003003E, $00000038, $00000065, $000200F9, $00000036, $000200F8, $00000036, $0004003D,
    $00000009, $00000066, $00000038, $00050051, $00000007, $00000067, $00000066, $00000000,
    $00050051, $00000007, $00000068, $00000066, $00000001, $00050051, $00000007, $00000069,
    $00000066, $00000002, $00070050, $0000000A, $0000006A, $00000067, $00000068, $00000069,
    $0000004E, $0003003E, $0000001B, $0000006A, $000100FD, $00010038
  );

  { Phase 111: Zero-Dependency Built-In Post-Processing SPIR-V 1.0 Shaders }
  BuiltInBloomDownsampleCompSPIRV: array[0..1415] of UInt32 = (
    $07230203, $00010000, $00000000, $00000100, $00000000, $00020011, $00000001, $0006000B,
    $00000001, $4C534C47, $6474732E, $3035342E, $00000000, $0003000E, $00000000, $00000001,
    $0006000F, $00000005, $00000002, $6E69616D, $00000000, $00000037, $00060010, $00000002,
    $00000011, $00000008, $00000008, $00000001, $00040047, $00000037, $0000000B, $0000001C,
    $00040047, $0000003B, $00000022, $00000000, $00040047, $0000003B, $00000021, $00000000,
    $00040047, $0000003E, $00000022, $00000000, $00040047, $0000003E, $00000021, $00000001,
    $00030047, $0000003E, $00000019, $00030047, $0000003F, $00000002, $00050048, $0000003F,
    $00000000, $00000023, $00000000, $00050048, $0000003F, $00000001, $00000023, $00000008,
    $00050048, $0000003F, $00000002, $00000023, $0000000C, $00050048, $0000003F, $00000003,
    $00000023, $00000010, $00050048, $0000003F, $00000004, $00000023, $00000014, $00050048,
    $0000003F, $00000005, $00000023, $00000018, $00050048, $0000003F, $00000006, $00000023,
    $0000001C, $00020013, $00000003, $00030021, $00000004, $00000003, $00020014, $00000005,
    $00040015, $00000006, $00000020, $00000000, $00040015, $00000007, $00000020, $00000001,
    $00030016, $00000008, $00000020, $00040017, $00000009, $00000006, $00000002, $00040017,
    $0000000A, $00000007, $00000002, $00040017, $0000000B, $00000006, $00000003, $00040017,
    $0000000C, $00000008, $00000002, $00040017, $0000000D, $00000008, $00000003, $00040017,
    $0000000E, $00000008, $00000004, $0004002B, $00000006, $0000000F, $00000000, $0004002B,
    $00000006, $00000010, $00000001, $0004002B, $00000006, $00000011, $00000002, $0004002B,
    $00000006, $00000012, $00000005, $0004002B, $00000006, $00000013, $00000006, $0004002B,
    $00000006, $00000014, $00000010, $0004002B, $00000006, $00000015, $0000FFFF, $0004002B,
    $00000008, $00000016, $C0000000, $0004002B, $00000008, $00000017, $BF800000, $0004002B,
    $00000008, $00000018, $00000000, $0004002B, $00000008, $00000019, $3F000000, $0004002B,
    $00000008, $0000001A, $3F800000, $0004002B, $00000008, $0000001B, $40000000, $0004002B,
    $00000008, $0000001C, $40800000, $0004002B, $00000008, $0000001D, $3E800000, $0004002B,
    $00000008, $0000001E, $3E000000, $0004002B, $00000008, $0000001F, $3D800000, $0004002B,
    $00000008, $00000020, $3D000000, $0004002B, $00000008, $00000021, $3727C5AC, $0004002B,
    $00000008, $00000022, $3E59B3D0, $0004002B, $00000008, $00000023, $3F371759, $0004002B,
    $00000008, $00000024, $3D93DD98, $0006002C, $0000000D, $00000025, $00000022, $00000023,
    $00000024, $0006002C, $0000000D, $00000026, $00000018, $00000018, $00000018, $0005002C,
    $0000000C, $00000027, $00000019, $00000019, $0005002C, $0000000C, $00000028, $0000001A,
    $0000001A, $0005002C, $0000000C, $00000029, $00000016, $00000016, $0005002C, $0000000C,
    $0000002A, $00000018, $00000016, $0005002C, $0000000C, $0000002B, $0000001B, $00000016,
    $0005002C, $0000000C, $0000002C, $00000016, $00000018, $0005002C, $0000000C, $0000002D,
    $00000018, $00000018, $0005002C, $0000000C, $0000002E, $0000001B, $00000018, $0005002C,
    $0000000C, $0000002F, $00000016, $0000001B, $0005002C, $0000000C, $00000030, $00000018,
    $0000001B, $0005002C, $0000000C, $00000031, $0000001B, $0000001B, $0005002C, $0000000C,
    $00000032, $00000017, $00000017, $0005002C, $0000000C, $00000033, $0000001A, $00000017,
    $0005002C, $0000000C, $00000034, $00000017, $0000001A, $0005002C, $0000000C, $00000035,
    $0000001A, $0000001A, $00040020, $00000036, $00000001, $0000000B, $0004003B, $00000036,
    $00000037, $00000001, $00090019, $00000038, $00000008, $00000001, $00000000, $00000000,
    $00000000, $00000001, $00000000, $0003001B, $00000039, $00000038, $00040020, $0000003A,
    $00000000, $00000039, $0004003B, $0000003A, $0000003B, $00000000, $00090019, $0000003C,
    $00000008, $00000001, $00000000, $00000000, $00000000, $00000002, $00000002, $00040020,
    $0000003D, $00000000, $0000003C, $0004003B, $0000003D, $0000003E, $00000000, $0009001E,
    $0000003F, $0000000C, $00000008, $00000008, $00000008, $00000006, $00000006, $00000006,
    $00040020, $00000040, $00000009, $0000003F, $00040020, $00000041, $00000009, $0000000C,
    $00040020, $00000042, $00000009, $00000008, $00040020, $00000043, $00000009, $00000006,
    $0004003B, $00000040, $00000044, $00000009, $00040020, $00000045, $00000007, $0000000D,
    $00050036, $00000003, $00000002, $00000000, $00000004, $000200F8, $00000046, $0004003B,
    $00000045, $0000004C, $00000007, $0004003D, $0000000B, $0000004D, $00000037, $00050051,
    $00000006, $0000004E, $0000004D, $00000000, $00050051, $00000006, $0000004F, $0000004D,
    $00000001, $00050041, $00000043, $00000050, $00000044, $00000013, $0004003D, $00000006,
    $00000051, $00000050, $000500C7, $00000006, $00000052, $00000051, $00000015, $000500C2,
    $00000006, $00000053, $00000051, $00000014, $000500B0, $00000005, $00000054, $0000004E,
    $00000052, $000500B0, $00000005, $00000055, $0000004F, $00000053, $000500A7, $00000005,
    $00000056, $00000054, $00000055, $000300F7, $0000004B, $00000000, $000400FA, $00000056,
    $00000047, $0000004B, $000200F8, $00000047, $00040070, $00000008, $00000057, $0000004E,
    $00040070, $00000008, $00000058, $0000004F, $00050050, $0000000C, $00000059, $00000057,
    $00000058, $00050081, $0000000C, $0000005A, $00000059, $00000027, $00040070, $00000008,
    $0000005B, $00000052, $00040070, $00000008, $0000005C, $00000053, $00050050, $0000000C,
    $0000005D, $0000005B, $0000005C, $0007000C, $0000000C, $0000005E, $00000001, $00000028,
    $0000005D, $00000028, $00050088, $0000000C, $0000005F, $0000005A, $0000005E, $00050041,
    $00000041, $00000060, $00000044, $0000000F, $0004003D, $0000000C, $00000061, $00000060,
    $0004003D, $00000039, $00000062, $0000003B, $00050085, $0000000C, $00000063, $00000029,
    $00000061, $00050081, $0000000C, $00000064, $0000005F, $00000063, $00070058, $0000000E,
    $00000065, $00000062, $00000064, $00000002, $00000018, $0008004F, $0000000D, $00000066,
    $00000065, $00000065, $00000000, $00000001, $00000002, $00050085, $0000000C, $00000067,
    $0000002A, $00000061, $00050081, $0000000C, $00000068, $0000005F, $00000067, $00070058,
    $0000000E, $00000069, $00000062, $00000068, $00000002, $00000018, $0008004F, $0000000D,
    $0000006A, $00000069, $00000069, $00000000, $00000001, $00000002, $00050085, $0000000C,
    $0000006B, $0000002B, $00000061, $00050081, $0000000C, $0000006C, $0000005F, $0000006B,
    $00070058, $0000000E, $0000006D, $00000062, $0000006C, $00000002, $00000018, $0008004F,
    $0000000D, $0000006E, $0000006D, $0000006D, $00000000, $00000001, $00000002, $00050085,
    $0000000C, $0000006F, $0000002C, $00000061, $00050081, $0000000C, $00000070, $0000005F,
    $0000006F, $00070058, $0000000E, $00000071, $00000062, $00000070, $00000002, $00000018,
    $0008004F, $0000000D, $00000072, $00000071, $00000071, $00000000, $00000001, $00000002,
    $00050085, $0000000C, $00000073, $0000002D, $00000061, $00050081, $0000000C, $00000074,
    $0000005F, $00000073, $00070058, $0000000E, $00000075, $00000062, $00000074, $00000002,
    $00000018, $0008004F, $0000000D, $00000076, $00000075, $00000075, $00000000, $00000001,
    $00000002, $00050085, $0000000C, $00000077, $0000002E, $00000061, $00050081, $0000000C,
    $00000078, $0000005F, $00000077, $00070058, $0000000E, $00000079, $00000062, $00000078,
    $00000002, $00000018, $0008004F, $0000000D, $0000007A, $00000079, $00000079, $00000000,
    $00000001, $00000002, $00050085, $0000000C, $0000007B, $0000002F, $00000061, $00050081,
    $0000000C, $0000007C, $0000005F, $0000007B, $00070058, $0000000E, $0000007D, $00000062,
    $0000007C, $00000002, $00000018, $0008004F, $0000000D, $0000007E, $0000007D, $0000007D,
    $00000000, $00000001, $00000002, $00050085, $0000000C, $0000007F, $00000030, $00000061,
    $00050081, $0000000C, $00000080, $0000005F, $0000007F, $00070058, $0000000E, $00000081,
    $00000062, $00000080, $00000002, $00000018, $0008004F, $0000000D, $00000082, $00000081,
    $00000081, $00000000, $00000001, $00000002, $00050085, $0000000C, $00000083, $00000031,
    $00000061, $00050081, $0000000C, $00000084, $0000005F, $00000083, $00070058, $0000000E,
    $00000085, $00000062, $00000084, $00000002, $00000018, $0008004F, $0000000D, $00000086,
    $00000085, $00000085, $00000000, $00000001, $00000002, $00050085, $0000000C, $00000087,
    $00000032, $00000061, $00050081, $0000000C, $00000088, $0000005F, $00000087, $00070058,
    $0000000E, $00000089, $00000062, $00000088, $00000002, $00000018, $0008004F, $0000000D,
    $0000008A, $00000089, $00000089, $00000000, $00000001, $00000002, $00050085, $0000000C,
    $0000008B, $00000033, $00000061, $00050081, $0000000C, $0000008C, $0000005F, $0000008B,
    $00070058, $0000000E, $0000008D, $00000062, $0000008C, $00000002, $00000018, $0008004F,
    $0000000D, $0000008E, $0000008D, $0000008D, $00000000, $00000001, $00000002, $00050085,
    $0000000C, $0000008F, $00000034, $00000061, $00050081, $0000000C, $00000090, $0000005F,
    $0000008F, $00070058, $0000000E, $00000091, $00000062, $00000090, $00000002, $00000018,
    $0008004F, $0000000D, $00000092, $00000091, $00000091, $00000000, $00000001, $00000002,
    $00050085, $0000000C, $00000093, $00000035, $00000061, $00050081, $0000000C, $00000094,
    $0000005F, $00000093, $00070058, $0000000E, $00000095, $00000062, $00000094, $00000002,
    $00000018, $0008004F, $0000000D, $00000096, $00000095, $00000095, $00000000, $00000001,
    $00000002, $00050041, $00000043, $00000097, $00000044, $00000012, $0004003D, $00000006,
    $00000098, $00000097, $000500AB, $00000005, $00000099, $00000098, $0000000F, $000300F7,
    $0000004A, $00000000, $000400FA, $00000099, $00000048, $00000049, $000200F8, $00000048,
    $00050081, $0000000D, $0000009A, $00000066, $0000006A, $00050081, $0000000D, $0000009B,
    $00000072, $00000076, $00050081, $0000000D, $0000009C, $0000009A, $0000009B, $0005008E,
    $0000000D, $0000009D, $0000009C, $0000001D, $00050081, $0000000D, $0000009E, $0000006A,
    $0000006E, $00050081, $0000000D, $0000009F, $00000076, $0000007A, $00050081, $0000000D,
    $000000A0, $0000009E, $0000009F, $0005008E, $0000000D, $000000A1, $000000A0, $0000001D,
    $00050081, $0000000D, $000000A2, $00000072, $00000076, $00050081, $0000000D, $000000A3,
    $0000007E, $00000082, $00050081, $0000000D, $000000A4, $000000A2, $000000A3, $0005008E,
    $0000000D, $000000A5, $000000A4, $0000001D, $00050081, $0000000D, $000000A6, $00000076,
    $0000007A, $00050081, $0000000D, $000000A7, $00000082, $00000086, $00050081, $0000000D,
    $000000A8, $000000A6, $000000A7, $0005008E, $0000000D, $000000A9, $000000A8, $0000001D,
    $00050081, $0000000D, $000000AA, $0000008A, $0000008E, $00050081, $0000000D, $000000AB,
    $00000092, $00000096, $00050081, $0000000D, $000000AC, $000000AA, $000000AB, $0005008E,
    $0000000D, $000000AD, $000000AC, $0000001D, $00050094, $00000008, $000000AE, $0000009D,
    $00000025, $0007000C, $00000008, $000000AF, $00000001, $00000028, $000000AE, $00000018,
    $00050081, $00000008, $000000B0, $0000001A, $000000AF, $00050088, $00000008, $000000B1,
    $0000001A, $000000B0, $00050094, $00000008, $000000B2, $000000A1, $00000025, $0007000C,
    $00000008, $000000B3, $00000001, $00000028, $000000B2, $00000018, $00050081, $00000008,
    $000000B4, $0000001A, $000000B3, $00050088, $00000008, $000000B5, $0000001A, $000000B4,
    $00050094, $00000008, $000000B6, $000000A5, $00000025, $0007000C, $00000008, $000000B7,
    $00000001, $00000028, $000000B6, $00000018, $00050081, $00000008, $000000B8, $0000001A,
    $000000B7, $00050088, $00000008, $000000B9, $0000001A, $000000B8, $00050094, $00000008,
    $000000BA, $000000A9, $00000025, $0007000C, $00000008, $000000BB, $00000001, $00000028,
    $000000BA, $00000018, $00050081, $00000008, $000000BC, $0000001A, $000000BB, $00050088,
    $00000008, $000000BD, $0000001A, $000000BC, $0005008E, $0000000D, $000000BE, $0000009D,
    $000000B1, $0005008E, $0000000D, $000000BF, $000000A1, $000000B5, $0005008E, $0000000D,
    $000000C0, $000000A5, $000000B9, $0005008E, $0000000D, $000000C1, $000000A9, $000000BD,
    $00050081, $0000000D, $000000C2, $000000BE, $000000BF, $00050081, $0000000D, $000000C3,
    $000000C0, $000000C1, $00050081, $0000000D, $000000C4, $000000C2, $000000C3, $0005008E,
    $0000000D, $000000C5, $000000C4, $0000001E, $00050081, $00000008, $000000C6, $000000B1,
    $000000B5, $00050081, $00000008, $000000C7, $000000B9, $000000BD, $00050081, $00000008,
    $000000C8, $000000C6, $000000C7, $00050085, $00000008, $000000C9, $000000C8, $0000001D,
    $0007000C, $00000008, $000000CA, $00000001, $00000028, $000000C9, $00000021, $00050088,
    $00000008, $000000CB, $0000001A, $000000CA, $0005008E, $0000000D, $000000CC, $000000C5,
    $000000CB, $0005008E, $0000000D, $000000CD, $000000AD, $00000019, $00050081, $0000000D,
    $000000CE, $000000CC, $000000CD, $00050041, $00000042, $000000CF, $00000044, $00000010,
    $0004003D, $00000008, $000000D0, $000000CF, $00050041, $00000042, $000000D1, $00000044,
    $00000011, $0004003D, $00000008, $000000D2, $000000D1, $00050051, $00000008, $000000D3,
    $000000CE, $00000000, $00050051, $00000008, $000000D4, $000000CE, $00000001, $00050051,
    $00000008, $000000D5, $000000CE, $00000002, $0007000C, $00000008, $000000D6, $00000001,
    $00000028, $000000D3, $000000D4, $0007000C, $00000008, $000000D7, $00000001, $00000028,
    $000000D6, $000000D5, $00050083, $00000008, $000000D8, $000000D7, $000000D0, $00050081,
    $00000008, $000000D9, $000000D8, $000000D2, $00050085, $00000008, $000000DA, $0000001B,
    $000000D2, $0007000C, $00000008, $000000DB, $00000001, $00000028, $000000DA, $00000018,
    $0008000C, $00000008, $000000DC, $00000001, $0000002B, $000000D9, $00000018, $000000DB,
    $00050085, $00000008, $000000DD, $000000DC, $000000DC, $00050085, $00000008, $000000DE,
    $0000001C, $000000D2, $00050081, $00000008, $000000DF, $000000DE, $00000021, $0007000C,
    $00000008, $000000E0, $00000001, $00000028, $000000DF, $00000021, $00050088, $00000008,
    $000000E1, $000000DD, $000000E0, $0007000C, $00000008, $000000E2, $00000001, $00000028,
    $000000E1, $000000D8, $0007000C, $00000008, $000000E3, $00000001, $00000028, $000000D7,
    $00000021, $00050088, $00000008, $000000E4, $000000E2, $000000E3, $0007000C, $00000008,
    $000000E5, $00000001, $00000028, $000000E4, $00000018, $0005008E, $0000000D, $000000E6,
    $000000CE, $000000E5, $0003003E, $0000004C, $000000E6, $000200F9, $0000004A, $000200F8,
    $00000049, $0005008E, $0000000D, $000000E7, $00000076, $0000001E, $00050081, $0000000D,
    $000000E8, $00000066, $0000006E, $00050081, $0000000D, $000000E9, $0000007E, $00000086,
    $00050081, $0000000D, $000000EA, $000000E8, $000000E9, $0005008E, $0000000D, $000000EB,
    $000000EA, $00000020, $00050081, $0000000D, $000000EC, $0000006A, $00000072, $00050081,
    $0000000D, $000000ED, $0000007A, $00000082, $00050081, $0000000D, $000000EE, $000000EC,
    $000000ED, $0005008E, $0000000D, $000000EF, $000000EE, $0000001F, $00050081, $0000000D,
    $000000F0, $0000008A, $0000008E, $00050081, $0000000D, $000000F1, $00000092, $00000096,
    $00050081, $0000000D, $000000F2, $000000F0, $000000F1, $0005008E, $0000000D, $000000F3,
    $000000F2, $0000001E, $00050081, $0000000D, $000000F4, $000000E7, $000000EB, $00050081,
    $0000000D, $000000F5, $000000EF, $000000F3, $00050081, $0000000D, $000000F6, $000000F4,
    $000000F5, $0003003E, $0000004C, $000000F6, $000200F9, $0000004A, $000200F8, $0000004A,
    $0004003D, $0000000D, $000000F7, $0000004C, $0007000C, $0000000D, $000000F8, $00000001,
    $00000028, $000000F7, $00000026, $00050051, $00000008, $000000F9, $000000F8, $00000000,
    $00050051, $00000008, $000000FA, $000000F8, $00000001, $00050051, $00000008, $000000FB,
    $000000F8, $00000002, $00070050, $0000000E, $000000FC, $000000F9, $000000FA, $000000FB,
    $0000001A, $00050050, $00000009, $000000FD, $0000004E, $0000004F, $0004007C, $0000000A,
    $000000FE, $000000FD, $0004003D, $0000003C, $000000FF, $0000003E, $00040063, $000000FF,
    $000000FE, $000000FC, $000200F9, $0000004B, $000200F8, $0000004B, $000100FD, $00010038
  );

  BuiltInBloomUpsampleCompSPIRV: array[0..792] of UInt32 = (
    $07230203, $00010000, $00000000, $0000008C, $00000000, $00020011, $00000001, $0006000B,
    $00000001, $4C534C47, $6474732E, $3035342E, $00000000, $0003000E, $00000000, $00000001,
    $0006000F, $00000005, $00000002, $6E69616D, $00000000, $00000028, $00060010, $00000002,
    $00000011, $00000008, $00000008, $00000001, $00040047, $00000028, $0000000B, $0000001C,
    $00040047, $0000002C, $00000022, $00000000, $00040047, $0000002C, $00000021, $00000000,
    $00040047, $0000002F, $00000022, $00000000, $00040047, $0000002F, $00000021, $00000001,
    $00030047, $00000030, $00000002, $00050048, $00000030, $00000000, $00000023, $00000000,
    $00050048, $00000030, $00000001, $00000023, $00000008, $00050048, $00000030, $00000002,
    $00000023, $0000000C, $00050048, $00000030, $00000003, $00000023, $00000010, $00050048,
    $00000030, $00000004, $00000023, $00000014, $00050048, $00000030, $00000005, $00000023,
    $00000018, $00050048, $00000030, $00000006, $00000023, $0000001C, $00020013, $00000003,
    $00030021, $00000004, $00000003, $00020014, $00000005, $00040015, $00000006, $00000020,
    $00000000, $00040015, $00000007, $00000020, $00000001, $00030016, $00000008, $00000020,
    $00040017, $00000009, $00000006, $00000002, $00040017, $0000000A, $00000007, $00000002,
    $00040017, $0000000B, $00000006, $00000003, $00040017, $0000000C, $00000008, $00000002,
    $00040017, $0000000D, $00000008, $00000003, $00040017, $0000000E, $00000008, $00000004,
    $0004002B, $00000006, $0000000F, $00000000, $0004002B, $00000006, $00000010, $00000003,
    $0004002B, $00000006, $00000011, $00000006, $0004002B, $00000006, $00000012, $00000010,
    $0004002B, $00000006, $00000013, $0000FFFF, $0004002B, $00000008, $00000014, $BF800000,
    $0004002B, $00000008, $00000015, $00000000, $0004002B, $00000008, $00000016, $3F000000,
    $0004002B, $00000008, $00000017, $3F800000, $0004002B, $00000008, $00000018, $40000000,
    $0004002B, $00000008, $00000019, $40800000, $0004002B, $00000008, $0000001A, $3D800000,
    $0004002B, $00000008, $0000001B, $38D1B717, $0005002C, $0000000C, $0000001C, $00000016,
    $00000016, $0005002C, $0000000C, $0000001D, $00000017, $00000017, $0005002C, $0000000C,
    $0000001E, $00000014, $00000014, $0005002C, $0000000C, $0000001F, $00000015, $00000014,
    $0005002C, $0000000C, $00000020, $00000017, $00000014, $0005002C, $0000000C, $00000021,
    $00000014, $00000015, $0005002C, $0000000C, $00000022, $00000015, $00000015, $0005002C,
    $0000000C, $00000023, $00000017, $00000015, $0005002C, $0000000C, $00000024, $00000014,
    $00000017, $0005002C, $0000000C, $00000025, $00000015, $00000017, $0005002C, $0000000C,
    $00000026, $00000017, $00000017, $00040020, $00000027, $00000001, $0000000B, $0004003B,
    $00000027, $00000028, $00000001, $00090019, $00000029, $00000008, $00000001, $00000000,
    $00000000, $00000000, $00000001, $00000000, $0003001B, $0000002A, $00000029, $00040020,
    $0000002B, $00000000, $0000002A, $0004003B, $0000002B, $0000002C, $00000000, $00090019,
    $0000002D, $00000008, $00000001, $00000000, $00000000, $00000000, $00000002, $00000002,
    $00040020, $0000002E, $00000000, $0000002D, $0004003B, $0000002E, $0000002F, $00000000,
    $0009001E, $00000030, $0000000C, $00000008, $00000008, $00000008, $00000006, $00000006,
    $00000006, $00040020, $00000031, $00000009, $00000030, $00040020, $00000032, $00000009,
    $0000000C, $00040020, $00000033, $00000009, $00000008, $00040020, $00000034, $00000009,
    $00000006, $0004003B, $00000031, $00000035, $00000009, $00050036, $00000003, $00000002,
    $00000000, $00000004, $000200F8, $00000036, $0004003D, $0000000B, $00000039, $00000028,
    $00050051, $00000006, $0000003A, $00000039, $00000000, $00050051, $00000006, $0000003B,
    $00000039, $00000001, $00050041, $00000034, $0000003C, $00000035, $00000011, $0004003D,
    $00000006, $0000003D, $0000003C, $000500C7, $00000006, $0000003E, $0000003D, $00000013,
    $000500C2, $00000006, $0000003F, $0000003D, $00000012, $000500B0, $00000005, $00000040,
    $0000003A, $0000003E, $000500B0, $00000005, $00000041, $0000003B, $0000003F, $000500A7,
    $00000005, $00000042, $00000040, $00000041, $000300F7, $00000038, $00000000, $000400FA,
    $00000042, $00000037, $00000038, $000200F8, $00000037, $00040070, $00000008, $00000043,
    $0000003A, $00040070, $00000008, $00000044, $0000003B, $00050050, $0000000C, $00000045,
    $00000043, $00000044, $00050081, $0000000C, $00000046, $00000045, $0000001C, $00040070,
    $00000008, $00000047, $0000003E, $00040070, $00000008, $00000048, $0000003F, $00050050,
    $0000000C, $00000049, $00000047, $00000048, $0007000C, $0000000C, $0000004A, $00000001,
    $00000028, $00000049, $0000001D, $00050088, $0000000C, $0000004B, $00000046, $0000004A,
    $00050041, $00000032, $0000004C, $00000035, $0000000F, $0004003D, $0000000C, $0000004D,
    $0000004C, $00050041, $00000033, $0000004E, $00000035, $00000010, $0004003D, $00000008,
    $0000004F, $0000004E, $0007000C, $00000008, $00000050, $00000001, $00000028, $0000004F,
    $0000001B, $0005008E, $0000000C, $00000051, $0000004D, $00000050, $0004003D, $0000002A,
    $00000052, $0000002C, $00050085, $0000000C, $00000053, $0000001E, $00000051, $00050081,
    $0000000C, $00000054, $0000004B, $00000053, $00070058, $0000000E, $00000055, $00000052,
    $00000054, $00000002, $00000015, $0008004F, $0000000D, $00000056, $00000055, $00000055,
    $00000000, $00000001, $00000002, $00050085, $0000000C, $00000057, $0000001F, $00000051,
    $00050081, $0000000C, $00000058, $0000004B, $00000057, $00070058, $0000000E, $00000059,
    $00000052, $00000058, $00000002, $00000015, $0008004F, $0000000D, $0000005A, $00000059,
    $00000059, $00000000, $00000001, $00000002, $00050085, $0000000C, $0000005B, $00000020,
    $00000051, $00050081, $0000000C, $0000005C, $0000004B, $0000005B, $00070058, $0000000E,
    $0000005D, $00000052, $0000005C, $00000002, $00000015, $0008004F, $0000000D, $0000005E,
    $0000005D, $0000005D, $00000000, $00000001, $00000002, $00050085, $0000000C, $0000005F,
    $00000021, $00000051, $00050081, $0000000C, $00000060, $0000004B, $0000005F, $00070058,
    $0000000E, $00000061, $00000052, $00000060, $00000002, $00000015, $0008004F, $0000000D,
    $00000062, $00000061, $00000061, $00000000, $00000001, $00000002, $00050085, $0000000C,
    $00000063, $00000022, $00000051, $00050081, $0000000C, $00000064, $0000004B, $00000063,
    $00070058, $0000000E, $00000065, $00000052, $00000064, $00000002, $00000015, $0008004F,
    $0000000D, $00000066, $00000065, $00000065, $00000000, $00000001, $00000002, $00050085,
    $0000000C, $00000067, $00000023, $00000051, $00050081, $0000000C, $00000068, $0000004B,
    $00000067, $00070058, $0000000E, $00000069, $00000052, $00000068, $00000002, $00000015,
    $0008004F, $0000000D, $0000006A, $00000069, $00000069, $00000000, $00000001, $00000002,
    $00050085, $0000000C, $0000006B, $00000024, $00000051, $00050081, $0000000C, $0000006C,
    $0000004B, $0000006B, $00070058, $0000000E, $0000006D, $00000052, $0000006C, $00000002,
    $00000015, $0008004F, $0000000D, $0000006E, $0000006D, $0000006D, $00000000, $00000001,
    $00000002, $00050085, $0000000C, $0000006F, $00000025, $00000051, $00050081, $0000000C,
    $00000070, $0000004B, $0000006F, $00070058, $0000000E, $00000071, $00000052, $00000070,
    $00000002, $00000015, $0008004F, $0000000D, $00000072, $00000071, $00000071, $00000000,
    $00000001, $00000002, $00050085, $0000000C, $00000073, $00000026, $00000051, $00050081,
    $0000000C, $00000074, $0000004B, $00000073, $00070058, $0000000E, $00000075, $00000052,
    $00000074, $00000002, $00000015, $0008004F, $0000000D, $00000076, $00000075, $00000075,
    $00000000, $00000001, $00000002, $0005008E, $0000000D, $00000077, $00000066, $00000019,
    $00050081, $0000000D, $00000078, $0000005A, $00000062, $00050081, $0000000D, $00000079,
    $0000006A, $00000072, $00050081, $0000000D, $0000007A, $00000078, $00000079, $0005008E,
    $0000000D, $0000007B, $0000007A, $00000018, $00050081, $0000000D, $0000007C, $00000056,
    $0000005E, $00050081, $0000000D, $0000007D, $0000006E, $00000076, $00050081, $0000000D,
    $0000007E, $0000007C, $0000007D, $00050081, $0000000D, $0000007F, $00000077, $0000007B,
    $00050081, $0000000D, $00000080, $0000007F, $0000007E, $0005008E, $0000000D, $00000081,
    $00000080, $0000001A, $00050050, $00000009, $00000082, $0000003A, $0000003B, $0004007C,
    $0000000A, $00000083, $00000082, $0004003D, $0000002D, $00000084, $0000002F, $00050062,
    $0000000E, $00000085, $00000084, $00000083, $0008004F, $0000000D, $00000086, $00000085,
    $00000085, $00000000, $00000001, $00000002, $00050081, $0000000D, $00000087, $00000086,
    $00000081, $00050051, $00000008, $00000088, $00000087, $00000000, $00050051, $00000008,
    $00000089, $00000087, $00000001, $00050051, $00000008, $0000008A, $00000087, $00000002,
    $00070050, $0000000E, $0000008B, $00000088, $00000089, $0000008A, $00000017, $00040063,
    $00000084, $00000083, $0000008B, $000200F9, $00000038, $000200F8, $00000038, $000100FD,
    $00010038
  );

  BuiltInLuminanceHistogramCompSPIRV: array[0..529] of UInt32 = (
    $07230203, $00010000, $00000000, $00000055, $00000000, $00020011, $00000001, $00020011,
    $00000032, $0006000B, $00000001, $4C534C47, $6474732E, $3035342E, $00000000, $0003000E,
    $00000000, $00000001, $0006000F, $00000005, $00000002, $6E69616D, $00000000, $0000001C,
    $00060010, $00000002, $00000011, $00000010, $00000010, $00000001, $00040047, $0000001C,
    $0000000B, $0000001C, $00040047, $00000020, $00000022, $00000000, $00040047, $00000020,
    $00000021, $00000000, $00040047, $00000021, $00000006, $00000004, $00030047, $00000022,
    $00000003, $00050048, $00000022, $00000000, $00000023, $00000000, $00040047, $00000024,
    $00000022, $00000000, $00040047, $00000024, $00000021, $00000001, $00030047, $00000026,
    $00000003, $00050048, $00000026, $00000000, $00000023, $00000000, $00050048, $00000026,
    $00000001, $00000023, $00000004, $00050048, $00000026, $00000002, $00000023, $00000008,
    $00050048, $00000026, $00000003, $00000023, $0000000C, $00040047, $00000028, $00000022,
    $00000000, $00040047, $00000028, $00000021, $00000002, $00030047, $00000029, $00000002,
    $00050048, $00000029, $00000000, $00000023, $00000000, $00050048, $00000029, $00000001,
    $00000023, $00000004, $00050048, $00000029, $00000002, $00000023, $00000008, $00050048,
    $00000029, $00000003, $00000023, $0000000C, $00050048, $00000029, $00000004, $00000023,
    $00000010, $00050048, $00000029, $00000005, $00000023, $00000014, $00050048, $00000029,
    $00000006, $00000023, $00000018, $00050048, $00000029, $00000007, $00000023, $0000001C,
    $00020013, $00000003, $00030021, $00000004, $00000003, $00020014, $00000005, $00040015,
    $00000006, $00000020, $00000000, $00040015, $00000007, $00000020, $00000001, $00030016,
    $00000008, $00000020, $00040017, $00000009, $00000006, $00000002, $00040017, $0000000A,
    $00000007, $00000002, $00040017, $0000000B, $00000006, $00000003, $00040017, $0000000C,
    $00000008, $00000003, $00040017, $0000000D, $00000008, $00000004, $0004002B, $00000006,
    $0000000E, $00000000, $0004002B, $00000006, $0000000F, $00000001, $0004002B, $00000006,
    $00000010, $000000FF, $0004002B, $00000006, $00000011, $00000100, $0004002B, $00000007,
    $00000012, $00000000, $0004002B, $00000008, $00000013, $00000000, $0004002B, $00000008,
    $00000014, $3F800000, $0004002B, $00000008, $00000015, $437E0000, $0004002B, $00000008,
    $00000016, $38D1B717, $0004002B, $00000008, $00000017, $3E59B3D0, $0004002B, $00000008,
    $00000018, $3F371759, $0004002B, $00000008, $00000019, $3D93DD98, $0006002C, $0000000C,
    $0000001A, $00000017, $00000018, $00000019, $00040020, $0000001B, $00000001, $0000000B,
    $0004003B, $0000001B, $0000001C, $00000001, $00090019, $0000001D, $00000008, $00000001,
    $00000000, $00000000, $00000000, $00000001, $00000000, $0003001B, $0000001E, $0000001D,
    $00040020, $0000001F, $00000000, $0000001E, $0004003B, $0000001F, $00000020, $00000000,
    $0004001C, $00000021, $00000006, $00000011, $0003001E, $00000022, $00000021, $00040020,
    $00000023, $00000002, $00000022, $0004003B, $00000023, $00000024, $00000002, $00040020,
    $00000025, $00000002, $00000006, $0006001E, $00000026, $00000008, $00000008, $00000008,
    $00000008, $00040020, $00000027, $00000002, $00000026, $0004003B, $00000027, $00000028,
    $00000002, $000A001E, $00000029, $00000008, $00000008, $00000008, $00000008, $00000008,
    $00000008, $00000008, $00000006, $00040020, $0000002A, $00000009, $00000029, $00040020,
    $0000002B, $00000009, $00000008, $0004003B, $0000002A, $0000002C, $00000009, $00050036,
    $00000003, $00000002, $00000000, $00000004, $000200F8, $0000002D, $0004003D, $0000000B,
    $00000030, $0000001C, $00050051, $00000006, $00000031, $00000030, $00000000, $00050051,
    $00000006, $00000032, $00000030, $00000001, $00050050, $00000009, $00000033, $00000031,
    $00000032, $0004007C, $0000000A, $00000034, $00000033, $00050051, $00000007, $00000035,
    $00000034, $00000000, $00050051, $00000007, $00000036, $00000034, $00000001, $0004003D,
    $0000001E, $00000037, $00000020, $00040064, $0000001D, $00000038, $00000037, $00050067,
    $0000000A, $00000039, $00000038, $00000012, $00050051, $00000007, $0000003A, $00000039,
    $00000000, $00050051, $00000007, $0000003B, $00000039, $00000001, $000500B1, $00000005,
    $0000003C, $00000035, $0000003A, $000500B1, $00000005, $0000003D, $00000036, $0000003B,
    $000500A7, $00000005, $0000003E, $0000003C, $0000003D, $000300F7, $0000002F, $00000000,
    $000400FA, $0000003E, $0000002E, $0000002F, $000200F8, $0000002E, $0007005F, $0000000D,
    $0000003F, $00000038, $00000034, $00000002, $00000012, $0008004F, $0000000C, $00000040,
    $0000003F, $0000003F, $00000000, $00000001, $00000002, $00050094, $00000008, $00000041,
    $00000040, $0000001A, $000500B8, $00000005, $00000042, $00000041, $00000016, $0007000C,
    $00000008, $00000043, $00000001, $00000028, $00000041, $00000016, $0006000C, $00000008,
    $00000044, $00000001, $0000001E, $00000043, $00050041, $0000002B, $00000045, $0000002C,
    $0000000E, $0004003D, $00000008, $00000046, $00000045, $00050041, $0000002B, $00000047,
    $0000002C, $0000000F, $0004003D, $00000008, $00000048, $00000047, $00050083, $00000008,
    $00000049, $00000044, $00000046, $00050083, $00000008, $0000004A, $00000048, $00000046,
    $0007000C, $00000008, $0000004B, $00000001, $00000028, $0000004A, $00000016, $00050088,
    $00000008, $0000004C, $00000049, $0000004B, $0008000C, $00000008, $0000004D, $00000001,
    $0000002B, $0000004C, $00000013, $00000014, $00050085, $00000008, $0000004E, $0000004D,
    $00000015, $00050081, $00000008, $0000004F, $0000004E, $00000014, $0004006D, $00000006,
    $00000050, $0000004F, $0007000C, $00000006, $00000051, $00000001, $00000026, $00000050,
    $00000010, $000600A9, $00000006, $00000052, $00000042, $0000000E, $00000051, $00060041,
    $00000025, $00000053, $00000024, $0000000E, $00000052, $000700EA, $00000006, $00000054,
    $00000053, $0000000F, $0000000E, $0000000F, $000200F9, $0000002F, $000200F8, $0000002F,
    $000100FD, $00010038
  );

  BuiltInHDRCompositeVertSPIRV: array[0..176] of UInt32 = (
    $07230203, $00010000, $00000000, $00000022, $00000000, $00020011, $00000001, $0003000E,
    $00000000, $00000001, $0008000F, $00000000, $00000001, $6E69616D, $00000000, $00000011,
    $00000013, $00000015, $00040047, $00000011, $0000000B, $0000002A, $00040047, $00000013,
    $0000000B, $00000000, $00040047, $00000015, $0000001E, $00000000, $00020013, $00000002,
    $00030021, $00000003, $00000002, $00020014, $00000004, $00040015, $00000005, $00000020,
    $00000001, $00030016, $00000006, $00000020, $00040017, $00000007, $00000006, $00000002,
    $00040017, $00000008, $00000006, $00000004, $0004002B, $00000005, $00000009, $00000001,
    $0004002B, $00000005, $0000000A, $00000002, $0004002B, $00000006, $0000000B, $BF800000,
    $0004002B, $00000006, $0000000C, $00000000, $0004002B, $00000006, $0000000D, $3F000000,
    $0004002B, $00000006, $0000000E, $3F800000, $0004002B, $00000006, $0000000F, $40400000,
    $00040020, $00000010, $00000001, $00000005, $0004003B, $00000010, $00000011, $00000001,
    $00040020, $00000012, $00000003, $00000008, $0004003B, $00000012, $00000013, $00000003,
    $00040020, $00000014, $00000003, $00000007, $0004003B, $00000014, $00000015, $00000003,
    $00050036, $00000002, $00000001, $00000000, $00000003, $000200F8, $00000016, $0004003D,
    $00000005, $00000017, $00000011, $000500AA, $00000004, $00000018, $00000017, $00000009,
    $000500AA, $00000004, $00000019, $00000017, $0000000A, $000600A9, $00000006, $0000001A,
    $00000018, $0000000F, $0000000B, $000600A9, $00000006, $0000001B, $00000019, $0000000F,
    $0000000B, $00050081, $00000006, $0000001C, $0000001A, $0000000E, $00050085, $00000006,
    $0000001D, $0000001C, $0000000D, $00050083, $00000006, $0000001E, $0000000E, $0000001B,
    $00050085, $00000006, $0000001F, $0000001E, $0000000D, $00050050, $00000007, $00000020,
    $0000001D, $0000001F, $0003003E, $00000015, $00000020, $00070050, $00000008, $00000021,
    $0000001A, $0000001B, $0000000C, $0000000E, $0003003E, $00000013, $00000021, $000100FD,
    $00010038
  );

  BuiltInHDRCompositeFragSPIRV: array[0..1286] of UInt32 = (
    $07230203, $00010000, $00000000, $000000E7, $00000000, $00020011, $00000001, $0006000B,
    $00000001, $4C534C47, $6474732E, $3035342E, $00000000, $0003000E, $00000000, $00000001,
    $0007000F, $00000004, $00000002, $6E69616D, $00000000, $0000005C, $0000005E, $00030010,
    $00000002, $00000007, $00040047, $0000005C, $0000001E, $00000000, $00040047, $0000005E,
    $0000001E, $00000000, $00040047, $00000062, $00000022, $00000000, $00040047, $00000062,
    $00000021, $00000000, $00040047, $00000063, $00000022, $00000000, $00040047, $00000063,
    $00000021, $00000001, $00030047, $00000064, $00000003, $00050048, $00000064, $00000000,
    $00000023, $00000000, $00050048, $00000064, $00000001, $00000023, $00000004, $00050048,
    $00000064, $00000002, $00000023, $00000008, $00050048, $00000064, $00000003, $00000023,
    $0000000C, $00040047, $00000066, $00000022, $00000000, $00040047, $00000066, $00000021,
    $00000002, $00030047, $00000066, $00000018, $00030047, $00000068, $00000002, $00050048,
    $00000068, $00000000, $00000023, $00000000, $00050048, $00000068, $00000001, $00000023,
    $00000004, $00050048, $00000068, $00000002, $00000023, $00000008, $00050048, $00000068,
    $00000003, $00000023, $0000000C, $00050048, $00000068, $00000004, $00000023, $00000010,
    $00050048, $00000068, $00000005, $00000023, $00000014, $00050048, $00000068, $00000006,
    $00000023, $00000018, $00050048, $00000068, $00000007, $00000023, $0000001C, $00020013,
    $00000003, $00030021, $00000004, $00000003, $00020014, $00000005, $00040015, $00000006,
    $00000020, $00000000, $00030016, $00000007, $00000020, $00040017, $00000008, $00000007,
    $00000002, $00040017, $00000009, $00000007, $00000003, $00040017, $0000000A, $00000007,
    $00000004, $00040018, $0000000B, $00000009, $00000003, $0004002B, $00000006, $0000000C,
    $00000000, $0004002B, $00000006, $0000000D, $00000001, $0004002B, $00000006, $0000000E,
    $00000002, $0004002B, $00000006, $0000000F, $00000003, $0004002B, $00000006, $00000010,
    $00000004, $0004002B, $00000006, $00000011, $00000005, $0004002B, $00000006, $00000012,
    $00000006, $0004002B, $00000006, $00000013, $00000007, $0004002B, $00000007, $00000014,
    $00000000, $0004002B, $00000007, $00000015, $3F800000, $0004002B, $00000007, $00000016,
    $3E3851EC, $0004002B, $00000007, $00000017, $38D1B717, $0004002B, $00000007, $00000018,
    $3A83126F, $0004002B, $00000007, $00000019, $358637BD, $0004002B, $00000007, $0000001A,
    $400CCCCD, $0006002C, $00000009, $0000001B, $00000014, $00000014, $00000014, $0006002C,
    $00000009, $0000001C, $00000015, $00000015, $00000015, $0006002C, $00000009, $0000001D,
    $00000016, $00000016, $00000016, $0006002C, $00000009, $0000001E, $00000019, $00000019,
    $00000019, $0006002C, $00000009, $0000001F, $0000001A, $0000001A, $0000001A, $0004002B,
    $00000007, $00000020, $3E59B3D0, $0004002B, $00000007, $00000021, $3F371759, $0004002B,
    $00000007, $00000022, $3D93DD98, $0006002C, $00000009, $00000023, $00000020, $00000021,
    $00000022, $0004002B, $00000007, $00000024, $4020A3D7, $0004002B, $00000007, $00000025,
    $3CF5C28F, $0006002C, $00000009, $00000026, $00000025, $00000025, $00000025, $0004002B,
    $00000007, $00000027, $401B851F, $0004002B, $00000007, $00000028, $3F170A3D, $0006002C,
    $00000009, $00000029, $00000028, $00000028, $00000028, $0004002B, $00000007, $0000002A,
    $3E0F5C29, $0006002C, $00000009, $0000002B, $0000002A, $0000002A, $0000002A, $0004002B,
    $00000007, $0000002C, $3F57ACB5, $0004002B, $00000007, $0000002D, $3D2D6061, $0004002B,
    $00000007, $0000002E, $3D2D9218, $0006002C, $00000009, $0000002F, $0000002C, $0000002D,
    $0000002E, $0004002B, $00000007, $00000030, $3DA0A1CC, $0004002B, $00000007, $00000031,
    $3F60E352, $0004002B, $00000007, $00000032, $3DA0A1CC, $0006002C, $00000009, $00000033,
    $00000030, $00000031, $00000032, $0004002B, $00000007, $00000034, $3DA2400F, $0004002B,
    $00000007, $00000035, $3DA221DA, $0004002B, $00000007, $00000036, $3F610F84, $0006002C,
    $00000009, $00000037, $00000034, $00000035, $00000036, $0006002C, $0000000B, $00000038,
    $0000002F, $00000033, $00000037, $0004002B, $00000007, $00000039, $3F993355, $0004002B,
    $00000007, $0000003A, $BD58AA5F, $0004002B, $00000007, $0000003B, $BD58F8C9, $0006002C,
    $00000009, $0000003C, $00000039, $0000003A, $0000003B, $0004002B, $00000007, $0000003D,
    $BDC8BF2C, $0004002B, $00000007, $0000003E, $3F937190, $0004002B, $00000007, $0000003F,
    $BDC8CB01, $0006002C, $00000009, $00000040, $0000003D, $0000003E, $0000003F, $0004002B,
    $00000007, $00000041, $BDCAD01B, $0004002B, $00000007, $00000042, $BDCAAC28, $0004002B,
    $00000007, $00000043, $3F935662, $0006002C, $00000009, $00000044, $00000041, $00000042,
    $00000043, $0006002C, $0000000B, $00000045, $0000003C, $00000040, $00000044, $0004002B,
    $00000007, $00000046, $C1479538, $0006002C, $00000009, $00000047, $00000046, $00000046,
    $00000046, $0004002B, $00000007, $00000048, $4080D58F, $0006002C, $00000009, $00000049,
    $00000048, $00000048, $00000048, $0004002B, $00000007, $0000004A, $3D783E11, $0004002B,
    $00000007, $0000004B, $41780000, $0004002B, $00000007, $0000004C, $C2208F5C, $0004002B,
    $00000007, $0000004D, $41FFAE14, $0004002B, $00000007, $0000004E, $C0DBC6A8, $0004002B,
    $00000007, $0000004F, $3EDC0EBF, $0004002B, $00000007, $00000050, $3DF3EAB3, $0004002B,
    $00000007, $00000051, $BB180B24, $0006002C, $00000009, $00000052, $00000051, $00000051,
    $00000051, $0004002B, $00000007, $00000053, $414EB852, $0004002B, $00000007, $00000054,
    $3F870A3D, $0004002B, $00000007, $00000055, $3D6147AE, $0006002C, $00000009, $00000056,
    $00000055, $00000055, $00000055, $0004002B, $00000007, $00000057, $3ED55555, $0006002C,
    $00000009, $00000058, $00000057, $00000057, $00000057, $0004002B, $00000007, $00000059,
    $3B4D2E1C, $0006002C, $00000009, $0000005A, $00000059, $00000059, $00000059, $00040020,
    $0000005B, $00000001, $00000008, $0004003B, $0000005B, $0000005C, $00000001, $00040020,
    $0000005D, $00000003, $0000000A, $0004003B, $0000005D, $0000005E, $00000003, $00090019,
    $0000005F, $00000007, $00000001, $00000000, $00000000, $00000000, $00000001, $00000000,
    $0003001B, $00000060, $0000005F, $00040020, $00000061, $00000000, $00000060, $0004003B,
    $00000061, $00000062, $00000000, $0004003B, $00000061, $00000063, $00000000, $0006001E,
    $00000064, $00000007, $00000007, $00000007, $00000007, $00040020, $00000065, $00000002,
    $00000064, $0004003B, $00000065, $00000066, $00000002, $00040020, $00000067, $00000002,
    $00000007, $000A001E, $00000068, $00000007, $00000007, $00000007, $00000007, $00000007,
    $00000006, $00000006, $00000006, $00040020, $00000069, $00000009, $00000068, $00040020,
    $0000006A, $00000009, $00000007, $00040020, $0000006B, $00000009, $00000006, $0004003B,
    $00000069, $0000006C, $00000009, $00040020, $0000006D, $00000007, $00000009, $00050036,
    $00000003, $00000002, $00000000, $00000004, $000200F8, $0000006E, $0004003B, $0000006D,
    $00000079, $00000007, $0004003B, $0000006D, $0000007A, $00000007, $0004003D, $00000008,
    $0000007B, $0000005C, $0004003D, $00000060, $0000007C, $00000062, $00050057, $0000000A,
    $0000007D, $0000007C, $0000007B, $0008004F, $00000009, $0000007E, $0000007D, $0000007D,
    $00000000, $00000001, $00000002, $0004003D, $00000060, $0000007F, $00000063, $00050057,
    $0000000A, $00000080, $0000007F, $0000007B, $0008004F, $00000009, $00000081, $00000080,
    $00000080, $00000000, $00000001, $00000002, $00050041, $0000006A, $00000082, $0000006C,
    $0000000D, $0004003D, $00000007, $00000083, $00000082, $00050041, $0000006B, $00000084,
    $0000006C, $00000012, $0004003D, $00000006, $00000085, $00000084, $000500AB, $00000005,
    $00000086, $00000085, $0000000C, $000600A9, $00000007, $00000087, $00000086, $00000083,
    $00000014, $0005008E, $00000009, $00000088, $00000081, $00000087, $00050081, $00000009,
    $00000089, $0000007E, $00000088, $00050041, $0000006A, $0000008A, $0000006C, $0000000C,
    $0004003D, $00000007, $0000008B, $0000008A, $00050041, $0000006B, $0000008C, $0000006C,
    $00000013, $0004003D, $00000006, $0000008D, $0000008C, $000500AB, $00000005, $0000008E,
    $0000008D, $0000000C, $00050041, $00000067, $0000008F, $00000066, $0000000D, $0004003D,
    $00000007, $00000090, $0000008F, $0007000C, $00000007, $00000091, $00000001, $00000028,
    $00000090, $00000017, $000600A9, $00000007, $00000092, $0000008E, $00000091, $00000015,
    $00050085, $00000007, $00000093, $0000008B, $00000092, $0005008E, $00000009, $00000094,
    $00000089, $00000093, $00050041, $0000006A, $00000095, $0000006C, $0000000F, $0004003D,
    $00000007, $00000096, $00000095, $00050041, $0000006A, $00000097, $0000006C, $00000010,
    $0004003D, $00000007, $00000098, $00000097, $00050094, $00000007, $00000099, $00000094,
    $00000023, $00060050, $00000009, $0000009A, $00000099, $00000099, $00000099, $00060050,
    $00000009, $0000009B, $00000096, $00000096, $00000096, $0008000C, $00000009, $0000009C,
    $00000001, $0000002E, $0000009A, $00000094, $0000009B, $00050083, $00000009, $0000009D,
    $0000009C, $0000001D, $0005008E, $00000009, $0000009E, $0000009D, $00000098, $00050081,
    $00000009, $0000009F, $0000009E, $0000001D, $0007000C, $00000009, $000000A0, $00000001,
    $00000028, $0000009F, $0000001B, $00050041, $0000006B, $000000A1, $0000006C, $00000011,
    $0004003D, $00000006, $000000A2, $000000A1, $000500AA, $00000005, $000000A3, $000000A2,
    $0000000D, $000300F7, $00000075, $00000000, $000400FA, $000000A3, $0000006F, $00000070,
    $000200F8, $0000006F, $00050081, $00000009, $000000A6, $000000A0, $0000001C, $00050088,
    $00000009, $000000A7, $000000A0, $000000A6, $0003003E, $00000079, $000000A7, $000200F9,
    $00000075, $000200F8, $00000070, $000500AA, $00000005, $000000A8, $000000A2, $0000000E,
    $000300F7, $000000A4, $00000000, $000400FA, $000000A8, $00000071, $00000072, $000200F8,
    $00000071, $0005008E, $00000009, $000000A9, $000000A0, $00000024, $00050081, $00000009,
    $000000AA, $000000A9, $00000026, $00050085, $00000009, $000000AB, $000000A0, $000000AA,
    $0005008E, $00000009, $000000AC, $000000A0, $00000027, $00050081, $00000009, $000000AD,
    $000000AC, $00000029, $00050085, $00000009, $000000AE, $000000A0, $000000AD, $00050081,
    $00000009, $000000AF, $000000AE, $0000002B, $00050088, $00000009, $000000B0, $000000AB,
    $000000AF, $0008000C, $00000009, $000000B1, $00000001, $0000002B, $000000B0, $0000001B,
    $0000001C, $0003003E, $00000079, $000000B1, $000200F9, $000000A4, $000200F8, $00000072,
    $000500AA, $00000005, $000000B2, $000000A2, $0000000F, $000300F7, $000000A5, $00000000,
    $000400FA, $000000B2, $00000073, $00000074, $000200F8, $00000073, $0007000C, $00000009,
    $000000B3, $00000001, $00000028, $000000A0, $0000001E, $00050091, $00000009, $000000B4,
    $00000038, $000000B3, $0007000C, $00000009, $000000B5, $00000001, $00000028, $000000B4,
    $0000001E, $0006000C, $00000009, $000000B6, $00000001, $0000001E, $000000B5, $0008000C,
    $00000009, $000000B7, $00000001, $0000002B, $000000B6, $00000047, $00000049, $00050083,
    $00000009, $000000B8, $000000B7, $00000047, $0005008E, $00000009, $000000B9, $000000B8,
    $0000004A, $00050085, $00000009, $000000BA, $000000B9, $000000B9, $00050085, $00000009,
    $000000BB, $000000BA, $000000B9, $00050085, $00000009, $000000BC, $000000BA, $000000BA,
    $00050085, $00000009, $000000BD, $000000BC, $000000B9, $00050085, $00000009, $000000BE,
    $000000BC, $000000BA, $0005008E, $00000009, $000000BF, $000000BE, $0000004B, $0005008E,
    $00000009, $000000C0, $000000BD, $0000004C, $0005008E, $00000009, $000000C1, $000000BC,
    $0000004D, $0005008E, $00000009, $000000C2, $000000BB, $0000004E, $0005008E, $00000009,
    $000000C3, $000000BA, $0000004F, $0005008E, $00000009, $000000C4, $000000B9, $00000050,
    $00050081, $00000009, $000000C5, $000000BF, $000000C0, $00050081, $00000009, $000000C6,
    $000000C5, $000000C1, $00050081, $00000009, $000000C7, $000000C6, $000000C2, $00050081,
    $00000009, $000000C8, $000000C7, $000000C3, $00050081, $00000009, $000000C9, $000000C8,
    $000000C4, $00050081, $00000009, $000000CA, $000000C9, $00000052, $00050091, $00000009,
    $000000CB, $00000045, $000000CA, $0007000C, $00000009, $000000CC, $00000001, $00000028,
    $000000CB, $0000001B, $0007000C, $00000009, $000000CD, $00000001, $0000001A, $000000CC,
    $0000001F, $0008000C, $00000009, $000000CE, $00000001, $0000002B, $000000CD, $0000001B,
    $0000001C, $0003003E, $00000079, $000000CE, $000200F9, $000000A5, $000200F8, $00000074,
    $0008000C, $00000009, $000000CF, $00000001, $0000002B, $000000A0, $0000001B, $0000001C,
    $0003003E, $00000079, $000000CF, $000200F9, $000000A5, $000200F8, $000000A5, $000200F9,
    $000000A4, $000200F8, $000000A4, $000200F9, $00000075, $000200F8, $00000075, $0004003D,
    $00000009, $000000D0, $00000079, $0007000C, $00000009, $000000D1, $00000001, $00000028,
    $000000D0, $0000001B, $00050041, $0000006A, $000000D2, $0000006C, $0000000E, $0004003D,
    $00000007, $000000D3, $000000D2, $00050083, $00000007, $000000D4, $000000D3, $0000001A,
    $0006000C, $00000007, $000000D5, $00000001, $00000004, $000000D4, $000500B8, $00000005,
    $000000D6, $000000D5, $00000018, $000300F7, $00000078, $00000000, $000400FA, $000000D6,
    $00000076, $00000077, $000200F8, $00000076, $0005008E, $00000009, $000000D7, $000000D1,
    $00000053, $0007000C, $00000009, $000000D8, $00000001, $0000001A, $000000D1, $00000058,
    $0005008E, $00000009, $000000D9, $000000D8, $00000054, $00050083, $00000009, $000000DA,
    $000000D9, $00000056, $0007000C, $00000009, $000000DB, $00000001, $00000030, $0000005A,
    $000000D1, $0008000C, $00000009, $000000DC, $00000001, $0000002E, $000000D7, $000000DA,
    $000000DB, $0003003E, $0000007A, $000000DC, $000200F9, $00000078, $000200F8, $00000077,
    $0007000C, $00000007, $000000DD, $00000001, $00000028, $000000D3, $00000018, $00050088,
    $00000007, $000000DE, $00000015, $000000DD, $00060050, $00000009, $000000DF, $000000DE,
    $000000DE, $000000DE, $0007000C, $00000009, $000000E0, $00000001, $0000001A, $000000D1,
    $000000DF, $0003003E, $0000007A, $000000E0, $000200F9, $00000078, $000200F8, $00000078,
    $0004003D, $00000009, $000000E1, $0000007A, $0008000C, $00000009, $000000E2, $00000001,
    $0000002B, $000000E1, $0000001B, $0000001C, $00050051, $00000007, $000000E3, $000000E2,
    $00000000, $00050051, $00000007, $000000E4, $000000E2, $00000001, $00050051, $00000007,
    $000000E5, $000000E2, $00000002, $00070050, $0000000A, $000000E6, $000000E3, $000000E4,
    $000000E5, $00000015, $0003003E, $0000005E, $000000E6, $000100FD, $00010038
  );

  BuiltInGTAOHorizonCompSPIRV: array[0..3872] of UInt32 = (
    $07230203, $00010000, $00000000, $000002BF, $00000000, $00020011, $00000001, $00020011,
    $00000031, $00020011, $00000032, $0006000B, $00000001, $4C534C47, $6474732E, $3035342E,
    $00000000, $0003000E, $00000000, $00000001, $0006000F, $00000005, $00000002, $6E69616D,
    $00000000, $0000002D, $00060010, $00000002, $00000011, $00000008, $00000008, $00000001,
    $00040047, $0000002D, $0000000B, $0000001C, $00040047, $00000031, $00000022, $00000000,
    $00040047, $00000031, $00000021, $00000000, $00040047, $00000034, $00000022, $00000000,
    $00040047, $00000034, $00000021, $00000001, $00030047, $00000034, $00000019, $00030047,
    $00000035, $00000002, $00050048, $00000035, $00000000, $00000023, $00000000, $00050048,
    $00000035, $00000001, $00000023, $00000008, $00050048, $00000035, $00000002, $00000023,
    $00000010, $00050048, $00000035, $00000003, $00000023, $00000014, $00050048, $00000035,
    $00000004, $00000023, $00000018, $00050048, $00000035, $00000005, $00000023, $0000001C,
    $00050048, $00000035, $00000006, $00000023, $00000020, $00050048, $00000035, $00000007,
    $00000023, $00000024, $00050048, $00000035, $00000008, $00000023, $00000028, $00050048,
    $00000035, $00000009, $00000023, $0000002C, $00020013, $00000003, $00030021, $00000004,
    $00000003, $00020014, $00000005, $00040015, $00000006, $00000020, $00000000, $00040015,
    $00000007, $00000020, $00000001, $00030016, $00000008, $00000020, $00040017, $00000009,
    $00000006, $00000002, $00040017, $0000000A, $00000007, $00000002, $00040017, $0000000B,
    $00000006, $00000003, $00040017, $0000000C, $00000008, $00000002, $00040017, $0000000D,
    $00000008, $00000003, $00040017, $0000000E, $00000008, $00000004, $00040017, $0000000F,
    $00000005, $00000003, $0004002B, $00000006, $00000010, $00000000, $0004002B, $00000006,
    $00000011, $00000001, $0004002B, $00000006, $00000012, $00000002, $0004002B, $00000006,
    $00000013, $00000003, $0004002B, $00000006, $00000014, $00000004, $0004002B, $00000006,
    $00000015, $00000005, $0004002B, $00000006, $00000016, $00000006, $0004002B, $00000008,
    $00000017, $BF800000, $0004002B, $00000008, $00000018, $00000000, $0004002B, $00000008,
    $00000019, $3CA3D70A, $0004002B, $00000008, $0000001A, $3E800000, $0004002B, $00000008,
    $0000001B, $3F000000, $0004002B, $00000008, $0000001C, $3F800000, $0004002B, $00000008,
    $0000001D, $40000000, $0004002B, $00000008, $0000001E, $40800000, $0004002B, $00000008,
    $0000001F, $40C00000, $0004002B, $00000008, $00000020, $41000000, $0004002B, $00000008,
    $00000021, $3F7FF972, $0004002B, $00000008, $00000022, $3727C5AC, $0004002B, $00000008,
    $00000023, $3A83126F, $0004002B, $00000008, $00000024, $3C23D70A, $0005002C, $0000000C,
    $00000025, $0000001B, $0000001B, $0005002C, $0000000C, $00000026, $0000001C, $0000001C,
    $0007002C, $0000000E, $00000027, $0000001C, $00000018, $00000018, $0000001C, $0005002C,
    $0000000C, $00000028, $0000001C, $00000018, $0005002C, $0000000C, $00000029, $00000017,
    $00000018, $0005002C, $0000000C, $0000002A, $00000018, $0000001C, $0005002C, $0000000C,
    $0000002B, $00000018, $00000017, $00040020, $0000002C, $00000001, $0000000B, $0004003B,
    $0000002C, $0000002D, $00000001, $00090019, $0000002E, $00000008, $00000001, $00000000,
    $00000000, $00000000, $00000001, $00000000, $0003001B, $0000002F, $0000002E, $00040020,
    $00000030, $00000000, $0000002F, $0004003B, $00000030, $00000031, $00000000, $00090019,
    $00000032, $00000008, $00000001, $00000000, $00000000, $00000000, $00000002, $00000009,
    $00040020, $00000033, $00000000, $00000032, $0004003B, $00000033, $00000034, $00000000,
    $000C001E, $00000035, $0000000C, $0000000C, $00000008, $00000008, $00000008, $00000008,
    $00000008, $00000006, $00000006, $00000006, $00040020, $00000036, $00000009, $00000035,
    $00040020, $00000037, $00000009, $0000000C, $00040020, $00000038, $00000009, $00000008,
    $0004003B, $00000036, $00000039, $00000009, $00050036, $00000003, $00000002, $00000000,
    $00000004, $000200F8, $0000003A, $0004003D, $0000000B, $0000003F, $0000002D, $00050051,
    $00000006, $00000040, $0000003F, $00000000, $00050051, $00000006, $00000041, $0000003F,
    $00000001, $00050050, $00000009, $00000042, $00000040, $00000041, $0004007C, $0000000A,
    $00000043, $00000042, $00050051, $00000007, $00000044, $00000043, $00000000, $00050051,
    $00000007, $00000045, $00000043, $00000001, $0004003D, $00000032, $00000046, $00000034,
    $00040068, $0000000A, $00000047, $00000046, $00050051, $00000007, $00000048, $00000047,
    $00000000, $00050051, $00000007, $00000049, $00000047, $00000001, $000500B1, $00000005,
    $0000004A, $00000044, $00000048, $000500B1, $00000005, $0000004B, $00000045, $00000049,
    $000500A7, $00000005, $0000004C, $0000004A, $0000004B, $000300F7, $0000003E, $00000000,
    $000400FA, $0000004C, $0000003B, $0000003E, $000200F8, $0000003B, $00040070, $00000008,
    $0000004D, $00000040, $00040070, $00000008, $0000004E, $00000041, $00050050, $0000000C,
    $0000004F, $0000004D, $0000004E, $00050081, $0000000C, $00000050, $0000004F, $00000025,
    $00050041, $00000037, $00000051, $00000039, $00000010, $0004003D, $0000000C, $00000052,
    $00000051, $00050085, $0000000C, $00000053, $00000050, $00000052, $0004003D, $0000002F,
    $00000054, $00000031, $00070058, $0000000E, $00000055, $00000054, $00000053, $00000002,
    $00000018, $00050051, $00000008, $00000056, $00000055, $00000000, $000500BA, $00000005,
    $00000057, $00000056, $00000021, $000300F7, $00000058, $00000000, $000400FA, $00000057,
    $0000003C, $0000003D, $000200F8, $0000003C, $00040063, $00000046, $00000043, $00000027,
    $000200F9, $00000058, $000200F8, $0000003D, $00050041, $00000038, $00000059, $00000039,
    $00000012, $0004003D, $00000008, $0000005A, $00000059, $0007000C, $00000008, $0000005B,
    $00000001, $00000028, $0000005A, $00000023, $00050041, $00000038, $0000005C, $00000039,
    $00000013, $0004003D, $00000008, $0000005D, $0000005C, $00050081, $00000008, $0000005E,
    $0000005B, $0000001C, $0007000C, $00000008, $0000005F, $00000001, $00000028, $0000005D,
    $0000005E, $00050085, $00000008, $00000060, $0000005B, $0000005F, $00050083, $00000008,
    $00000061, $0000005F, $0000005B, $00050041, $00000037, $00000062, $00000039, $00000011,
    $0004003D, $0000000C, $00000063, $00000062, $00050041, $00000038, $00000064, $00000039,
    $00000014, $0004003D, $00000008, $00000065, $00000064, $00050041, $00000038, $00000066,
    $00000039, $00000015, $0004003D, $00000008, $00000067, $00000066, $00050041, $00000038,
    $00000068, $00000039, $00000016, $0004003D, $00000008, $00000069, $00000068, $0007000C,
    $00000008, $0000006A, $00000001, $00000028, $00000069, $00000024, $00050085, $00000008,
    $0000006B, $00000056, $00000061, $00050083, $00000008, $0000006C, $0000005F, $0000006B,
    $0007000C, $00000008, $0000006D, $00000001, $00000028, $0000006C, $00000022, $00050088,
    $00000008, $0000006E, $00000060, $0000006D, $0005008E, $0000000C, $0000006F, $00000053,
    $0000001D, $00050083, $0000000C, $00000070, $0000006F, $00000026, $00050085, $0000000C,
    $00000071, $00000070, $00000063, $0005008E, $0000000C, $00000072, $00000071, $0000006E,
    $00050051, $00000008, $00000073, $00000072, $00000000, $00050051, $00000008, $00000074,
    $00000072, $00000001, $0004007F, $00000008, $00000075, $0000006E, $00060050, $0000000D,
    $00000076, $00000073, $00000074, $00000075, $0004007F, $0000000D, $00000077, $00000076,
    $0006000C, $0000000D, $00000078, $00000001, $00000045, $00000077, $00050051, $00000008,
    $00000079, $00000052, $00000000, $00050051, $00000008, $0000007A, $00000052, $00000001,
    $00050050, $0000000C, $0000007B, $00000079, $00000018, $00050050, $0000000C, $0000007C,
    $00000018, $0000007A, $00050081, $0000000C, $0000007D, $00000053, $0000007B, $00050083,
    $0000000C, $0000007E, $00000053, $0000007B, $00050081, $0000000C, $0000007F, $00000053,
    $0000007C, $00050083, $0000000C, $00000080, $00000053, $0000007C, $00070058, $0000000E,
    $00000081, $00000054, $0000007D, $00000002, $00000018, $00050051, $00000008, $00000082,
    $00000081, $00000000, $00050085, $00000008, $00000083, $00000082, $00000061, $00050083,
    $00000008, $00000084, $0000005F, $00000083, $0007000C, $00000008, $00000085, $00000001,
    $00000028, $00000084, $00000022, $00050088, $00000008, $00000086, $00000060, $00000085,
    $0005008E, $0000000C, $00000087, $0000007D, $0000001D, $00050083, $0000000C, $00000088,
    $00000087, $00000026, $00050085, $0000000C, $00000089, $00000088, $00000063, $0005008E,
    $0000000C, $0000008A, $00000089, $00000086, $00050051, $00000008, $0000008B, $0000008A,
    $00000000, $00050051, $00000008, $0000008C, $0000008A, $00000001, $0004007F, $00000008,
    $0000008D, $00000086, $00060050, $0000000D, $0000008E, $0000008B, $0000008C, $0000008D,
    $00050083, $0000000D, $0000008F, $0000008E, $00000076, $00070058, $0000000E, $00000090,
    $00000054, $0000007E, $00000002, $00000018, $00050051, $00000008, $00000091, $00000090,
    $00000000, $00050085, $00000008, $00000092, $00000091, $00000061, $00050083, $00000008,
    $00000093, $0000005F, $00000092, $0007000C, $00000008, $00000094, $00000001, $00000028,
    $00000093, $00000022, $00050088, $00000008, $00000095, $00000060, $00000094, $0005008E,
    $0000000C, $00000096, $0000007E, $0000001D, $00050083, $0000000C, $00000097, $00000096,
    $00000026, $00050085, $0000000C, $00000098, $00000097, $00000063, $0005008E, $0000000C,
    $00000099, $00000098, $00000095, $00050051, $00000008, $0000009A, $00000099, $00000000,
    $00050051, $00000008, $0000009B, $00000099, $00000001, $0004007F, $00000008, $0000009C,
    $00000095, $00060050, $0000000D, $0000009D, $0000009A, $0000009B, $0000009C, $00050083,
    $0000000D, $0000009E, $00000076, $0000009D, $00070058, $0000000E, $0000009F, $00000054,
    $0000007F, $00000002, $00000018, $00050051, $00000008, $000000A0, $0000009F, $00000000,
    $00050085, $00000008, $000000A1, $000000A0, $00000061, $00050083, $00000008, $000000A2,
    $0000005F, $000000A1, $0007000C, $00000008, $000000A3, $00000001, $00000028, $000000A2,
    $00000022, $00050088, $00000008, $000000A4, $00000060, $000000A3, $0005008E, $0000000C,
    $000000A5, $0000007F, $0000001D, $00050083, $0000000C, $000000A6, $000000A5, $00000026,
    $00050085, $0000000C, $000000A7, $000000A6, $00000063, $0005008E, $0000000C, $000000A8,
    $000000A7, $000000A4, $00050051, $00000008, $000000A9, $000000A8, $00000000, $00050051,
    $00000008, $000000AA, $000000A8, $00000001, $0004007F, $00000008, $000000AB, $000000A4,
    $00060050, $0000000D, $000000AC, $000000A9, $000000AA, $000000AB, $00050083, $0000000D,
    $000000AD, $000000AC, $00000076, $00070058, $0000000E, $000000AE, $00000054, $00000080,
    $00000002, $00000018, $00050051, $00000008, $000000AF, $000000AE, $00000000, $00050085,
    $00000008, $000000B0, $000000AF, $00000061, $00050083, $00000008, $000000B1, $0000005F,
    $000000B0, $0007000C, $00000008, $000000B2, $00000001, $00000028, $000000B1, $00000022,
    $00050088, $00000008, $000000B3, $00000060, $000000B2, $0005008E, $0000000C, $000000B4,
    $00000080, $0000001D, $00050083, $0000000C, $000000B5, $000000B4, $00000026, $00050085,
    $0000000C, $000000B6, $000000B5, $00000063, $0005008E, $0000000C, $000000B7, $000000B6,
    $000000B3, $00050051, $00000008, $000000B8, $000000B7, $00000000, $00050051, $00000008,
    $000000B9, $000000B7, $00000001, $0004007F, $00000008, $000000BA, $000000B3, $00060050,
    $0000000D, $000000BB, $000000B8, $000000B9, $000000BA, $00050083, $0000000D, $000000BC,
    $00000076, $000000BB, $00050051, $00000008, $000000BD, $0000008F, $00000002, $00050051,
    $00000008, $000000BE, $0000009E, $00000002, $00050051, $00000008, $000000BF, $000000AD,
    $00000002, $00050051, $00000008, $000000C0, $000000BC, $00000002, $0006000C, $00000008,
    $000000C1, $00000001, $00000004, $000000BD, $0006000C, $00000008, $000000C2, $00000001,
    $00000004, $000000BE, $0006000C, $00000008, $000000C3, $00000001, $00000004, $000000BF,
    $0006000C, $00000008, $000000C4, $00000001, $00000004, $000000C0, $000500B8, $00000005,
    $000000C5, $000000C1, $000000C2, $00060050, $0000000F, $000000C6, $000000C5, $000000C5,
    $000000C5, $000600A9, $0000000D, $000000C7, $000000C6, $0000008F, $0000009E, $000500B8,
    $00000005, $000000C8, $000000C3, $000000C4, $00060050, $0000000F, $000000C9, $000000C8,
    $000000C8, $000000C8, $000600A9, $0000000D, $000000CA, $000000C9, $000000AD, $000000BC,
    $0007000C, $0000000D, $000000CB, $00000001, $00000044, $000000C7, $000000CA, $0006000C,
    $00000008, $000000CC, $00000001, $00000042, $000000CB, $0007000C, $00000008, $000000CD,
    $00000001, $00000028, $000000CC, $00000022, $00050088, $00000008, $000000CE, $0000001C,
    $000000CD, $0005008E, $0000000D, $000000CF, $000000CB, $000000CE, $0004007F, $0000000D,
    $000000D0, $000000CF, $00050094, $00000008, $000000D1, $000000CF, $00000078, $000500B8,
    $00000005, $000000D2, $000000D1, $00000018, $00060050, $0000000F, $000000D3, $000000D2,
    $000000D2, $000000D2, $000600A9, $0000000D, $000000D4, $000000D3, $000000D0, $000000CF,
    $0007000C, $00000008, $000000D5, $00000001, $00000028, $0000006E, $0000001C, $00050088,
    $00000008, $000000D6, $00000065, $000000D5, $00050081, $00000008, $000000D7, $0000001C,
    $00000067, $00050085, $00000008, $000000D8, $00000065, $000000D7, $0007000C, $00000008,
    $000000D9, $00000001, $00000028, $000000D8, $00000022, $00050085, $0000000C, $000000DA,
    $00000028, $00000052, $0005008E, $0000000C, $000000DB, $000000DA, $000000D6, $0005008E,
    $0000000C, $000000DC, $000000DB, $0000001D, $00050081, $0000000C, $000000DD, $00000053,
    $000000DC, $00070058, $0000000E, $000000DE, $00000054, $000000DD, $00000002, $00000018,
    $00050051, $00000008, $000000DF, $000000DE, $00000000, $00050085, $00000008, $000000E0,
    $000000DF, $00000061, $00050083, $00000008, $000000E1, $0000005F, $000000E0, $0007000C,
    $00000008, $000000E2, $00000001, $00000028, $000000E1, $00000022, $00050088, $00000008,
    $000000E3, $00000060, $000000E2, $0005008E, $0000000C, $000000E4, $000000DD, $0000001D,
    $00050083, $0000000C, $000000E5, $000000E4, $00000026, $00050085, $0000000C, $000000E6,
    $000000E5, $00000063, $0005008E, $0000000C, $000000E7, $000000E6, $000000E3, $00050051,
    $00000008, $000000E8, $000000E7, $00000000, $00050051, $00000008, $000000E9, $000000E7,
    $00000001, $0004007F, $00000008, $000000EA, $000000E3, $00060050, $0000000D, $000000EB,
    $000000E8, $000000E9, $000000EA, $00050083, $0000000D, $000000EC, $000000EB, $00000076,
    $0006000C, $00000008, $000000ED, $00000001, $00000042, $000000EC, $0007000C, $00000008,
    $000000EE, $00000001, $00000028, $000000ED, $00000022, $00050088, $00000008, $000000EF,
    $0000001C, $000000EE, $0005008E, $0000000D, $000000F0, $000000EC, $000000EF, $00050094,
    $00000008, $000000F1, $000000F0, $000000D4, $00050083, $00000008, $000000F2, $000000F1,
    $00000019, $0008000C, $00000008, $000000F3, $00000001, $0000002B, $000000F2, $00000018,
    $0000001C, $00050088, $00000008, $000000F4, $000000ED, $000000D9, $00050083, $00000008,
    $000000F5, $0000001C, $000000F4, $0008000C, $00000008, $000000F6, $00000001, $0000002B,
    $000000F5, $00000018, $0000001C, $00050085, $00000008, $000000F7, $000000F3, $000000F6,
    $0007000C, $00000008, $000000F8, $00000001, $00000028, $00000018, $000000F7, $0005008E,
    $0000000C, $000000F9, $000000DB, $0000001E, $00050081, $0000000C, $000000FA, $00000053,
    $000000F9, $00070058, $0000000E, $000000FB, $00000054, $000000FA, $00000002, $00000018,
    $00050051, $00000008, $000000FC, $000000FB, $00000000, $00050085, $00000008, $000000FD,
    $000000FC, $00000061, $00050083, $00000008, $000000FE, $0000005F, $000000FD, $0007000C,
    $00000008, $000000FF, $00000001, $00000028, $000000FE, $00000022, $00050088, $00000008,
    $00000100, $00000060, $000000FF, $0005008E, $0000000C, $00000101, $000000FA, $0000001D,
    $00050083, $0000000C, $00000102, $00000101, $00000026, $00050085, $0000000C, $00000103,
    $00000102, $00000063, $0005008E, $0000000C, $00000104, $00000103, $00000100, $00050051,
    $00000008, $00000105, $00000104, $00000000, $00050051, $00000008, $00000106, $00000104,
    $00000001, $0004007F, $00000008, $00000107, $00000100, $00060050, $0000000D, $00000108,
    $00000105, $00000106, $00000107, $00050083, $0000000D, $00000109, $00000108, $00000076,
    $0006000C, $00000008, $0000010A, $00000001, $00000042, $00000109, $0007000C, $00000008,
    $0000010B, $00000001, $00000028, $0000010A, $00000022, $00050088, $00000008, $0000010C,
    $0000001C, $0000010B, $0005008E, $0000000D, $0000010D, $00000109, $0000010C, $00050094,
    $00000008, $0000010E, $0000010D, $000000D4, $00050083, $00000008, $0000010F, $0000010E,
    $00000019, $0008000C, $00000008, $00000110, $00000001, $0000002B, $0000010F, $00000018,
    $0000001C, $00050088, $00000008, $00000111, $0000010A, $000000D9, $00050083, $00000008,
    $00000112, $0000001C, $00000111, $0008000C, $00000008, $00000113, $00000001, $0000002B,
    $00000112, $00000018, $0000001C, $00050085, $00000008, $00000114, $00000110, $00000113,
    $0007000C, $00000008, $00000115, $00000001, $00000028, $000000F8, $00000114, $0005008E,
    $0000000C, $00000116, $000000DB, $0000001F, $00050081, $0000000C, $00000117, $00000053,
    $00000116, $00070058, $0000000E, $00000118, $00000054, $00000117, $00000002, $00000018,
    $00050051, $00000008, $00000119, $00000118, $00000000, $00050085, $00000008, $0000011A,
    $00000119, $00000061, $00050083, $00000008, $0000011B, $0000005F, $0000011A, $0007000C,
    $00000008, $0000011C, $00000001, $00000028, $0000011B, $00000022, $00050088, $00000008,
    $0000011D, $00000060, $0000011C, $0005008E, $0000000C, $0000011E, $00000117, $0000001D,
    $00050083, $0000000C, $0000011F, $0000011E, $00000026, $00050085, $0000000C, $00000120,
    $0000011F, $00000063, $0005008E, $0000000C, $00000121, $00000120, $0000011D, $00050051,
    $00000008, $00000122, $00000121, $00000000, $00050051, $00000008, $00000123, $00000121,
    $00000001, $0004007F, $00000008, $00000124, $0000011D, $00060050, $0000000D, $00000125,
    $00000122, $00000123, $00000124, $00050083, $0000000D, $00000126, $00000125, $00000076,
    $0006000C, $00000008, $00000127, $00000001, $00000042, $00000126, $0007000C, $00000008,
    $00000128, $00000001, $00000028, $00000127, $00000022, $00050088, $00000008, $00000129,
    $0000001C, $00000128, $0005008E, $0000000D, $0000012A, $00000126, $00000129, $00050094,
    $00000008, $0000012B, $0000012A, $000000D4, $00050083, $00000008, $0000012C, $0000012B,
    $00000019, $0008000C, $00000008, $0000012D, $00000001, $0000002B, $0000012C, $00000018,
    $0000001C, $00050088, $00000008, $0000012E, $00000127, $000000D9, $00050083, $00000008,
    $0000012F, $0000001C, $0000012E, $0008000C, $00000008, $00000130, $00000001, $0000002B,
    $0000012F, $00000018, $0000001C, $00050085, $00000008, $00000131, $0000012D, $00000130,
    $0007000C, $00000008, $00000132, $00000001, $00000028, $00000115, $00000131, $0005008E,
    $0000000C, $00000133, $000000DB, $00000020, $00050081, $0000000C, $00000134, $00000053,
    $00000133, $00070058, $0000000E, $00000135, $00000054, $00000134, $00000002, $00000018,
    $00050051, $00000008, $00000136, $00000135, $00000000, $00050085, $00000008, $00000137,
    $00000136, $00000061, $00050083, $00000008, $00000138, $0000005F, $00000137, $0007000C,
    $00000008, $00000139, $00000001, $00000028, $00000138, $00000022, $00050088, $00000008,
    $0000013A, $00000060, $00000139, $0005008E, $0000000C, $0000013B, $00000134, $0000001D,
    $00050083, $0000000C, $0000013C, $0000013B, $00000026, $00050085, $0000000C, $0000013D,
    $0000013C, $00000063, $0005008E, $0000000C, $0000013E, $0000013D, $0000013A, $00050051,
    $00000008, $0000013F, $0000013E, $00000000, $00050051, $00000008, $00000140, $0000013E,
    $00000001, $0004007F, $00000008, $00000141, $0000013A, $00060050, $0000000D, $00000142,
    $0000013F, $00000140, $00000141, $00050083, $0000000D, $00000143, $00000142, $00000076,
    $0006000C, $00000008, $00000144, $00000001, $00000042, $00000143, $0007000C, $00000008,
    $00000145, $00000001, $00000028, $00000144, $00000022, $00050088, $00000008, $00000146,
    $0000001C, $00000145, $0005008E, $0000000D, $00000147, $00000143, $00000146, $00050094,
    $00000008, $00000148, $00000147, $000000D4, $00050083, $00000008, $00000149, $00000148,
    $00000019, $0008000C, $00000008, $0000014A, $00000001, $0000002B, $00000149, $00000018,
    $0000001C, $00050088, $00000008, $0000014B, $00000144, $000000D9, $00050083, $00000008,
    $0000014C, $0000001C, $0000014B, $0008000C, $00000008, $0000014D, $00000001, $0000002B,
    $0000014C, $00000018, $0000001C, $00050085, $00000008, $0000014E, $0000014A, $0000014D,
    $0007000C, $00000008, $0000014F, $00000001, $00000028, $00000132, $0000014E, $00050085,
    $0000000C, $00000150, $00000029, $00000052, $0005008E, $0000000C, $00000151, $00000150,
    $000000D6, $0005008E, $0000000C, $00000152, $00000151, $0000001D, $00050081, $0000000C,
    $00000153, $00000053, $00000152, $00070058, $0000000E, $00000154, $00000054, $00000153,
    $00000002, $00000018, $00050051, $00000008, $00000155, $00000154, $00000000, $00050085,
    $00000008, $00000156, $00000155, $00000061, $00050083, $00000008, $00000157, $0000005F,
    $00000156, $0007000C, $00000008, $00000158, $00000001, $00000028, $00000157, $00000022,
    $00050088, $00000008, $00000159, $00000060, $00000158, $0005008E, $0000000C, $0000015A,
    $00000153, $0000001D, $00050083, $0000000C, $0000015B, $0000015A, $00000026, $00050085,
    $0000000C, $0000015C, $0000015B, $00000063, $0005008E, $0000000C, $0000015D, $0000015C,
    $00000159, $00050051, $00000008, $0000015E, $0000015D, $00000000, $00050051, $00000008,
    $0000015F, $0000015D, $00000001, $0004007F, $00000008, $00000160, $00000159, $00060050,
    $0000000D, $00000161, $0000015E, $0000015F, $00000160, $00050083, $0000000D, $00000162,
    $00000161, $00000076, $0006000C, $00000008, $00000163, $00000001, $00000042, $00000162,
    $0007000C, $00000008, $00000164, $00000001, $00000028, $00000163, $00000022, $00050088,
    $00000008, $00000165, $0000001C, $00000164, $0005008E, $0000000D, $00000166, $00000162,
    $00000165, $00050094, $00000008, $00000167, $00000166, $000000D4, $00050083, $00000008,
    $00000168, $00000167, $00000019, $0008000C, $00000008, $00000169, $00000001, $0000002B,
    $00000168, $00000018, $0000001C, $00050088, $00000008, $0000016A, $00000163, $000000D9,
    $00050083, $00000008, $0000016B, $0000001C, $0000016A, $0008000C, $00000008, $0000016C,
    $00000001, $0000002B, $0000016B, $00000018, $0000001C, $00050085, $00000008, $0000016D,
    $00000169, $0000016C, $0007000C, $00000008, $0000016E, $00000001, $00000028, $00000018,
    $0000016D, $0005008E, $0000000C, $0000016F, $00000151, $0000001E, $00050081, $0000000C,
    $00000170, $00000053, $0000016F, $00070058, $0000000E, $00000171, $00000054, $00000170,
    $00000002, $00000018, $00050051, $00000008, $00000172, $00000171, $00000000, $00050085,
    $00000008, $00000173, $00000172, $00000061, $00050083, $00000008, $00000174, $0000005F,
    $00000173, $0007000C, $00000008, $00000175, $00000001, $00000028, $00000174, $00000022,
    $00050088, $00000008, $00000176, $00000060, $00000175, $0005008E, $0000000C, $00000177,
    $00000170, $0000001D, $00050083, $0000000C, $00000178, $00000177, $00000026, $00050085,
    $0000000C, $00000179, $00000178, $00000063, $0005008E, $0000000C, $0000017A, $00000179,
    $00000176, $00050051, $00000008, $0000017B, $0000017A, $00000000, $00050051, $00000008,
    $0000017C, $0000017A, $00000001, $0004007F, $00000008, $0000017D, $00000176, $00060050,
    $0000000D, $0000017E, $0000017B, $0000017C, $0000017D, $00050083, $0000000D, $0000017F,
    $0000017E, $00000076, $0006000C, $00000008, $00000180, $00000001, $00000042, $0000017F,
    $0007000C, $00000008, $00000181, $00000001, $00000028, $00000180, $00000022, $00050088,
    $00000008, $00000182, $0000001C, $00000181, $0005008E, $0000000D, $00000183, $0000017F,
    $00000182, $00050094, $00000008, $00000184, $00000183, $000000D4, $00050083, $00000008,
    $00000185, $00000184, $00000019, $0008000C, $00000008, $00000186, $00000001, $0000002B,
    $00000185, $00000018, $0000001C, $00050088, $00000008, $00000187, $00000180, $000000D9,
    $00050083, $00000008, $00000188, $0000001C, $00000187, $0008000C, $00000008, $00000189,
    $00000001, $0000002B, $00000188, $00000018, $0000001C, $00050085, $00000008, $0000018A,
    $00000186, $00000189, $0007000C, $00000008, $0000018B, $00000001, $00000028, $0000016E,
    $0000018A, $0005008E, $0000000C, $0000018C, $00000151, $0000001F, $00050081, $0000000C,
    $0000018D, $00000053, $0000018C, $00070058, $0000000E, $0000018E, $00000054, $0000018D,
    $00000002, $00000018, $00050051, $00000008, $0000018F, $0000018E, $00000000, $00050085,
    $00000008, $00000190, $0000018F, $00000061, $00050083, $00000008, $00000191, $0000005F,
    $00000190, $0007000C, $00000008, $00000192, $00000001, $00000028, $00000191, $00000022,
    $00050088, $00000008, $00000193, $00000060, $00000192, $0005008E, $0000000C, $00000194,
    $0000018D, $0000001D, $00050083, $0000000C, $00000195, $00000194, $00000026, $00050085,
    $0000000C, $00000196, $00000195, $00000063, $0005008E, $0000000C, $00000197, $00000196,
    $00000193, $00050051, $00000008, $00000198, $00000197, $00000000, $00050051, $00000008,
    $00000199, $00000197, $00000001, $0004007F, $00000008, $0000019A, $00000193, $00060050,
    $0000000D, $0000019B, $00000198, $00000199, $0000019A, $00050083, $0000000D, $0000019C,
    $0000019B, $00000076, $0006000C, $00000008, $0000019D, $00000001, $00000042, $0000019C,
    $0007000C, $00000008, $0000019E, $00000001, $00000028, $0000019D, $00000022, $00050088,
    $00000008, $0000019F, $0000001C, $0000019E, $0005008E, $0000000D, $000001A0, $0000019C,
    $0000019F, $00050094, $00000008, $000001A1, $000001A0, $000000D4, $00050083, $00000008,
    $000001A2, $000001A1, $00000019, $0008000C, $00000008, $000001A3, $00000001, $0000002B,
    $000001A2, $00000018, $0000001C, $00050088, $00000008, $000001A4, $0000019D, $000000D9,
    $00050083, $00000008, $000001A5, $0000001C, $000001A4, $0008000C, $00000008, $000001A6,
    $00000001, $0000002B, $000001A5, $00000018, $0000001C, $00050085, $00000008, $000001A7,
    $000001A3, $000001A6, $0007000C, $00000008, $000001A8, $00000001, $00000028, $0000018B,
    $000001A7, $0005008E, $0000000C, $000001A9, $00000151, $00000020, $00050081, $0000000C,
    $000001AA, $00000053, $000001A9, $00070058, $0000000E, $000001AB, $00000054, $000001AA,
    $00000002, $00000018, $00050051, $00000008, $000001AC, $000001AB, $00000000, $00050085,
    $00000008, $000001AD, $000001AC, $00000061, $00050083, $00000008, $000001AE, $0000005F,
    $000001AD, $0007000C, $00000008, $000001AF, $00000001, $00000028, $000001AE, $00000022,
    $00050088, $00000008, $000001B0, $00000060, $000001AF, $0005008E, $0000000C, $000001B1,
    $000001AA, $0000001D, $00050083, $0000000C, $000001B2, $000001B1, $00000026, $00050085,
    $0000000C, $000001B3, $000001B2, $00000063, $0005008E, $0000000C, $000001B4, $000001B3,
    $000001B0, $00050051, $00000008, $000001B5, $000001B4, $00000000, $00050051, $00000008,
    $000001B6, $000001B4, $00000001, $0004007F, $00000008, $000001B7, $000001B0, $00060050,
    $0000000D, $000001B8, $000001B5, $000001B6, $000001B7, $00050083, $0000000D, $000001B9,
    $000001B8, $00000076, $0006000C, $00000008, $000001BA, $00000001, $00000042, $000001B9,
    $0007000C, $00000008, $000001BB, $00000001, $00000028, $000001BA, $00000022, $00050088,
    $00000008, $000001BC, $0000001C, $000001BB, $0005008E, $0000000D, $000001BD, $000001B9,
    $000001BC, $00050094, $00000008, $000001BE, $000001BD, $000000D4, $00050083, $00000008,
    $000001BF, $000001BE, $00000019, $0008000C, $00000008, $000001C0, $00000001, $0000002B,
    $000001BF, $00000018, $0000001C, $00050088, $00000008, $000001C1, $000001BA, $000000D9,
    $00050083, $00000008, $000001C2, $0000001C, $000001C1, $0008000C, $00000008, $000001C3,
    $00000001, $0000002B, $000001C2, $00000018, $0000001C, $00050085, $00000008, $000001C4,
    $000001C0, $000001C3, $0007000C, $00000008, $000001C5, $00000001, $00000028, $000001A8,
    $000001C4, $00050081, $00000008, $000001C6, $0000014F, $000001C5, $00050085, $00000008,
    $000001C7, $000001C6, $0000001B, $00050083, $00000008, $000001C8, $0000001C, $000001C7,
    $0008000C, $00000008, $000001C9, $00000001, $0000002B, $000001C8, $00000018, $0000001C,
    $00050085, $0000000C, $000001CA, $0000002A, $00000052, $0005008E, $0000000C, $000001CB,
    $000001CA, $000000D6, $0005008E, $0000000C, $000001CC, $000001CB, $0000001D, $00050081,
    $0000000C, $000001CD, $00000053, $000001CC, $00070058, $0000000E, $000001CE, $00000054,
    $000001CD, $00000002, $00000018, $00050051, $00000008, $000001CF, $000001CE, $00000000,
    $00050085, $00000008, $000001D0, $000001CF, $00000061, $00050083, $00000008, $000001D1,
    $0000005F, $000001D0, $0007000C, $00000008, $000001D2, $00000001, $00000028, $000001D1,
    $00000022, $00050088, $00000008, $000001D3, $00000060, $000001D2, $0005008E, $0000000C,
    $000001D4, $000001CD, $0000001D, $00050083, $0000000C, $000001D5, $000001D4, $00000026,
    $00050085, $0000000C, $000001D6, $000001D5, $00000063, $0005008E, $0000000C, $000001D7,
    $000001D6, $000001D3, $00050051, $00000008, $000001D8, $000001D7, $00000000, $00050051,
    $00000008, $000001D9, $000001D7, $00000001, $0004007F, $00000008, $000001DA, $000001D3,
    $00060050, $0000000D, $000001DB, $000001D8, $000001D9, $000001DA, $00050083, $0000000D,
    $000001DC, $000001DB, $00000076, $0006000C, $00000008, $000001DD, $00000001, $00000042,
    $000001DC, $0007000C, $00000008, $000001DE, $00000001, $00000028, $000001DD, $00000022,
    $00050088, $00000008, $000001DF, $0000001C, $000001DE, $0005008E, $0000000D, $000001E0,
    $000001DC, $000001DF, $00050094, $00000008, $000001E1, $000001E0, $000000D4, $00050083,
    $00000008, $000001E2, $000001E1, $00000019, $0008000C, $00000008, $000001E3, $00000001,
    $0000002B, $000001E2, $00000018, $0000001C, $00050088, $00000008, $000001E4, $000001DD,
    $000000D9, $00050083, $00000008, $000001E5, $0000001C, $000001E4, $0008000C, $00000008,
    $000001E6, $00000001, $0000002B, $000001E5, $00000018, $0000001C, $00050085, $00000008,
    $000001E7, $000001E3, $000001E6, $0007000C, $00000008, $000001E8, $00000001, $00000028,
    $00000018, $000001E7, $0005008E, $0000000C, $000001E9, $000001CB, $0000001E, $00050081,
    $0000000C, $000001EA, $00000053, $000001E9, $00070058, $0000000E, $000001EB, $00000054,
    $000001EA, $00000002, $00000018, $00050051, $00000008, $000001EC, $000001EB, $00000000,
    $00050085, $00000008, $000001ED, $000001EC, $00000061, $00050083, $00000008, $000001EE,
    $0000005F, $000001ED, $0007000C, $00000008, $000001EF, $00000001, $00000028, $000001EE,
    $00000022, $00050088, $00000008, $000001F0, $00000060, $000001EF, $0005008E, $0000000C,
    $000001F1, $000001EA, $0000001D, $00050083, $0000000C, $000001F2, $000001F1, $00000026,
    $00050085, $0000000C, $000001F3, $000001F2, $00000063, $0005008E, $0000000C, $000001F4,
    $000001F3, $000001F0, $00050051, $00000008, $000001F5, $000001F4, $00000000, $00050051,
    $00000008, $000001F6, $000001F4, $00000001, $0004007F, $00000008, $000001F7, $000001F0,
    $00060050, $0000000D, $000001F8, $000001F5, $000001F6, $000001F7, $00050083, $0000000D,
    $000001F9, $000001F8, $00000076, $0006000C, $00000008, $000001FA, $00000001, $00000042,
    $000001F9, $0007000C, $00000008, $000001FB, $00000001, $00000028, $000001FA, $00000022,
    $00050088, $00000008, $000001FC, $0000001C, $000001FB, $0005008E, $0000000D, $000001FD,
    $000001F9, $000001FC, $00050094, $00000008, $000001FE, $000001FD, $000000D4, $00050083,
    $00000008, $000001FF, $000001FE, $00000019, $0008000C, $00000008, $00000200, $00000001,
    $0000002B, $000001FF, $00000018, $0000001C, $00050088, $00000008, $00000201, $000001FA,
    $000000D9, $00050083, $00000008, $00000202, $0000001C, $00000201, $0008000C, $00000008,
    $00000203, $00000001, $0000002B, $00000202, $00000018, $0000001C, $00050085, $00000008,
    $00000204, $00000200, $00000203, $0007000C, $00000008, $00000205, $00000001, $00000028,
    $000001E8, $00000204, $0005008E, $0000000C, $00000206, $000001CB, $0000001F, $00050081,
    $0000000C, $00000207, $00000053, $00000206, $00070058, $0000000E, $00000208, $00000054,
    $00000207, $00000002, $00000018, $00050051, $00000008, $00000209, $00000208, $00000000,
    $00050085, $00000008, $0000020A, $00000209, $00000061, $00050083, $00000008, $0000020B,
    $0000005F, $0000020A, $0007000C, $00000008, $0000020C, $00000001, $00000028, $0000020B,
    $00000022, $00050088, $00000008, $0000020D, $00000060, $0000020C, $0005008E, $0000000C,
    $0000020E, $00000207, $0000001D, $00050083, $0000000C, $0000020F, $0000020E, $00000026,
    $00050085, $0000000C, $00000210, $0000020F, $00000063, $0005008E, $0000000C, $00000211,
    $00000210, $0000020D, $00050051, $00000008, $00000212, $00000211, $00000000, $00050051,
    $00000008, $00000213, $00000211, $00000001, $0004007F, $00000008, $00000214, $0000020D,
    $00060050, $0000000D, $00000215, $00000212, $00000213, $00000214, $00050083, $0000000D,
    $00000216, $00000215, $00000076, $0006000C, $00000008, $00000217, $00000001, $00000042,
    $00000216, $0007000C, $00000008, $00000218, $00000001, $00000028, $00000217, $00000022,
    $00050088, $00000008, $00000219, $0000001C, $00000218, $0005008E, $0000000D, $0000021A,
    $00000216, $00000219, $00050094, $00000008, $0000021B, $0000021A, $000000D4, $00050083,
    $00000008, $0000021C, $0000021B, $00000019, $0008000C, $00000008, $0000021D, $00000001,
    $0000002B, $0000021C, $00000018, $0000001C, $00050088, $00000008, $0000021E, $00000217,
    $000000D9, $00050083, $00000008, $0000021F, $0000001C, $0000021E, $0008000C, $00000008,
    $00000220, $00000001, $0000002B, $0000021F, $00000018, $0000001C, $00050085, $00000008,
    $00000221, $0000021D, $00000220, $0007000C, $00000008, $00000222, $00000001, $00000028,
    $00000205, $00000221, $0005008E, $0000000C, $00000223, $000001CB, $00000020, $00050081,
    $0000000C, $00000224, $00000053, $00000223, $00070058, $0000000E, $00000225, $00000054,
    $00000224, $00000002, $00000018, $00050051, $00000008, $00000226, $00000225, $00000000,
    $00050085, $00000008, $00000227, $00000226, $00000061, $00050083, $00000008, $00000228,
    $0000005F, $00000227, $0007000C, $00000008, $00000229, $00000001, $00000028, $00000228,
    $00000022, $00050088, $00000008, $0000022A, $00000060, $00000229, $0005008E, $0000000C,
    $0000022B, $00000224, $0000001D, $00050083, $0000000C, $0000022C, $0000022B, $00000026,
    $00050085, $0000000C, $0000022D, $0000022C, $00000063, $0005008E, $0000000C, $0000022E,
    $0000022D, $0000022A, $00050051, $00000008, $0000022F, $0000022E, $00000000, $00050051,
    $00000008, $00000230, $0000022E, $00000001, $0004007F, $00000008, $00000231, $0000022A,
    $00060050, $0000000D, $00000232, $0000022F, $00000230, $00000231, $00050083, $0000000D,
    $00000233, $00000232, $00000076, $0006000C, $00000008, $00000234, $00000001, $00000042,
    $00000233, $0007000C, $00000008, $00000235, $00000001, $00000028, $00000234, $00000022,
    $00050088, $00000008, $00000236, $0000001C, $00000235, $0005008E, $0000000D, $00000237,
    $00000233, $00000236, $00050094, $00000008, $00000238, $00000237, $000000D4, $00050083,
    $00000008, $00000239, $00000238, $00000019, $0008000C, $00000008, $0000023A, $00000001,
    $0000002B, $00000239, $00000018, $0000001C, $00050088, $00000008, $0000023B, $00000234,
    $000000D9, $00050083, $00000008, $0000023C, $0000001C, $0000023B, $0008000C, $00000008,
    $0000023D, $00000001, $0000002B, $0000023C, $00000018, $0000001C, $00050085, $00000008,
    $0000023E, $0000023A, $0000023D, $0007000C, $00000008, $0000023F, $00000001, $00000028,
    $00000222, $0000023E, $00050085, $0000000C, $00000240, $0000002B, $00000052, $0005008E,
    $0000000C, $00000241, $00000240, $000000D6, $0005008E, $0000000C, $00000242, $00000241,
    $0000001D, $00050081, $0000000C, $00000243, $00000053, $00000242, $00070058, $0000000E,
    $00000244, $00000054, $00000243, $00000002, $00000018, $00050051, $00000008, $00000245,
    $00000244, $00000000, $00050085, $00000008, $00000246, $00000245, $00000061, $00050083,
    $00000008, $00000247, $0000005F, $00000246, $0007000C, $00000008, $00000248, $00000001,
    $00000028, $00000247, $00000022, $00050088, $00000008, $00000249, $00000060, $00000248,
    $0005008E, $0000000C, $0000024A, $00000243, $0000001D, $00050083, $0000000C, $0000024B,
    $0000024A, $00000026, $00050085, $0000000C, $0000024C, $0000024B, $00000063, $0005008E,
    $0000000C, $0000024D, $0000024C, $00000249, $00050051, $00000008, $0000024E, $0000024D,
    $00000000, $00050051, $00000008, $0000024F, $0000024D, $00000001, $0004007F, $00000008,
    $00000250, $00000249, $00060050, $0000000D, $00000251, $0000024E, $0000024F, $00000250,
    $00050083, $0000000D, $00000252, $00000251, $00000076, $0006000C, $00000008, $00000253,
    $00000001, $00000042, $00000252, $0007000C, $00000008, $00000254, $00000001, $00000028,
    $00000253, $00000022, $00050088, $00000008, $00000255, $0000001C, $00000254, $0005008E,
    $0000000D, $00000256, $00000252, $00000255, $00050094, $00000008, $00000257, $00000256,
    $000000D4, $00050083, $00000008, $00000258, $00000257, $00000019, $0008000C, $00000008,
    $00000259, $00000001, $0000002B, $00000258, $00000018, $0000001C, $00050088, $00000008,
    $0000025A, $00000253, $000000D9, $00050083, $00000008, $0000025B, $0000001C, $0000025A,
    $0008000C, $00000008, $0000025C, $00000001, $0000002B, $0000025B, $00000018, $0000001C,
    $00050085, $00000008, $0000025D, $00000259, $0000025C, $0007000C, $00000008, $0000025E,
    $00000001, $00000028, $00000018, $0000025D, $0005008E, $0000000C, $0000025F, $00000241,
    $0000001E, $00050081, $0000000C, $00000260, $00000053, $0000025F, $00070058, $0000000E,
    $00000261, $00000054, $00000260, $00000002, $00000018, $00050051, $00000008, $00000262,
    $00000261, $00000000, $00050085, $00000008, $00000263, $00000262, $00000061, $00050083,
    $00000008, $00000264, $0000005F, $00000263, $0007000C, $00000008, $00000265, $00000001,
    $00000028, $00000264, $00000022, $00050088, $00000008, $00000266, $00000060, $00000265,
    $0005008E, $0000000C, $00000267, $00000260, $0000001D, $00050083, $0000000C, $00000268,
    $00000267, $00000026, $00050085, $0000000C, $00000269, $00000268, $00000063, $0005008E,
    $0000000C, $0000026A, $00000269, $00000266, $00050051, $00000008, $0000026B, $0000026A,
    $00000000, $00050051, $00000008, $0000026C, $0000026A, $00000001, $0004007F, $00000008,
    $0000026D, $00000266, $00060050, $0000000D, $0000026E, $0000026B, $0000026C, $0000026D,
    $00050083, $0000000D, $0000026F, $0000026E, $00000076, $0006000C, $00000008, $00000270,
    $00000001, $00000042, $0000026F, $0007000C, $00000008, $00000271, $00000001, $00000028,
    $00000270, $00000022, $00050088, $00000008, $00000272, $0000001C, $00000271, $0005008E,
    $0000000D, $00000273, $0000026F, $00000272, $00050094, $00000008, $00000274, $00000273,
    $000000D4, $00050083, $00000008, $00000275, $00000274, $00000019, $0008000C, $00000008,
    $00000276, $00000001, $0000002B, $00000275, $00000018, $0000001C, $00050088, $00000008,
    $00000277, $00000270, $000000D9, $00050083, $00000008, $00000278, $0000001C, $00000277,
    $0008000C, $00000008, $00000279, $00000001, $0000002B, $00000278, $00000018, $0000001C,
    $00050085, $00000008, $0000027A, $00000276, $00000279, $0007000C, $00000008, $0000027B,
    $00000001, $00000028, $0000025E, $0000027A, $0005008E, $0000000C, $0000027C, $00000241,
    $0000001F, $00050081, $0000000C, $0000027D, $00000053, $0000027C, $00070058, $0000000E,
    $0000027E, $00000054, $0000027D, $00000002, $00000018, $00050051, $00000008, $0000027F,
    $0000027E, $00000000, $00050085, $00000008, $00000280, $0000027F, $00000061, $00050083,
    $00000008, $00000281, $0000005F, $00000280, $0007000C, $00000008, $00000282, $00000001,
    $00000028, $00000281, $00000022, $00050088, $00000008, $00000283, $00000060, $00000282,
    $0005008E, $0000000C, $00000284, $0000027D, $0000001D, $00050083, $0000000C, $00000285,
    $00000284, $00000026, $00050085, $0000000C, $00000286, $00000285, $00000063, $0005008E,
    $0000000C, $00000287, $00000286, $00000283, $00050051, $00000008, $00000288, $00000287,
    $00000000, $00050051, $00000008, $00000289, $00000287, $00000001, $0004007F, $00000008,
    $0000028A, $00000283, $00060050, $0000000D, $0000028B, $00000288, $00000289, $0000028A,
    $00050083, $0000000D, $0000028C, $0000028B, $00000076, $0006000C, $00000008, $0000028D,
    $00000001, $00000042, $0000028C, $0007000C, $00000008, $0000028E, $00000001, $00000028,
    $0000028D, $00000022, $00050088, $00000008, $0000028F, $0000001C, $0000028E, $0005008E,
    $0000000D, $00000290, $0000028C, $0000028F, $00050094, $00000008, $00000291, $00000290,
    $000000D4, $00050083, $00000008, $00000292, $00000291, $00000019, $0008000C, $00000008,
    $00000293, $00000001, $0000002B, $00000292, $00000018, $0000001C, $00050088, $00000008,
    $00000294, $0000028D, $000000D9, $00050083, $00000008, $00000295, $0000001C, $00000294,
    $0008000C, $00000008, $00000296, $00000001, $0000002B, $00000295, $00000018, $0000001C,
    $00050085, $00000008, $00000297, $00000293, $00000296, $0007000C, $00000008, $00000298,
    $00000001, $00000028, $0000027B, $00000297, $0005008E, $0000000C, $00000299, $00000241,
    $00000020, $00050081, $0000000C, $0000029A, $00000053, $00000299, $00070058, $0000000E,
    $0000029B, $00000054, $0000029A, $00000002, $00000018, $00050051, $00000008, $0000029C,
    $0000029B, $00000000, $00050085, $00000008, $0000029D, $0000029C, $00000061, $00050083,
    $00000008, $0000029E, $0000005F, $0000029D, $0007000C, $00000008, $0000029F, $00000001,
    $00000028, $0000029E, $00000022, $00050088, $00000008, $000002A0, $00000060, $0000029F,
    $0005008E, $0000000C, $000002A1, $0000029A, $0000001D, $00050083, $0000000C, $000002A2,
    $000002A1, $00000026, $00050085, $0000000C, $000002A3, $000002A2, $00000063, $0005008E,
    $0000000C, $000002A4, $000002A3, $000002A0, $00050051, $00000008, $000002A5, $000002A4,
    $00000000, $00050051, $00000008, $000002A6, $000002A4, $00000001, $0004007F, $00000008,
    $000002A7, $000002A0, $00060050, $0000000D, $000002A8, $000002A5, $000002A6, $000002A7,
    $00050083, $0000000D, $000002A9, $000002A8, $00000076, $0006000C, $00000008, $000002AA,
    $00000001, $00000042, $000002A9, $0007000C, $00000008, $000002AB, $00000001, $00000028,
    $000002AA, $00000022, $00050088, $00000008, $000002AC, $0000001C, $000002AB, $0005008E,
    $0000000D, $000002AD, $000002A9, $000002AC, $00050094, $00000008, $000002AE, $000002AD,
    $000000D4, $00050083, $00000008, $000002AF, $000002AE, $00000019, $0008000C, $00000008,
    $000002B0, $00000001, $0000002B, $000002AF, $00000018, $0000001C, $00050088, $00000008,
    $000002B1, $000002AA, $000000D9, $00050083, $00000008, $000002B2, $0000001C, $000002B1,
    $0008000C, $00000008, $000002B3, $00000001, $0000002B, $000002B2, $00000018, $0000001C,
    $00050085, $00000008, $000002B4, $000002B0, $000002B3, $0007000C, $00000008, $000002B5,
    $00000001, $00000028, $00000298, $000002B4, $00050081, $00000008, $000002B6, $0000023F,
    $000002B5, $00050085, $00000008, $000002B7, $000002B6, $0000001B, $00050083, $00000008,
    $000002B8, $0000001C, $000002B7, $0008000C, $00000008, $000002B9, $00000001, $0000002B,
    $000002B8, $00000018, $0000001C, $00050081, $00000008, $000002BA, $000001C9, $000002B9,
    $00050085, $00000008, $000002BB, $000002BA, $0000001B, $0008000C, $00000008, $000002BC,
    $00000001, $0000002B, $000002BB, $00000018, $0000001C, $0007000C, $00000008, $000002BD,
    $00000001, $0000001A, $000002BC, $0000006A, $00070050, $0000000E, $000002BE, $000002BD,
    $00000018, $00000018, $0000001C, $00040063, $00000046, $00000043, $000002BE, $000200F9,
    $00000058, $000200F8, $00000058, $000200F9, $0000003E, $000200F8, $0000003E, $000100FD,
    $00010038
  );

  BuiltInGTAODenoiseCompSPIRV: array[0..1214] of UInt32 = (
    $07230203, $00010000, $00000000, $000000DC, $00000000, $00020011, $00000001, $00020011,
    $00000031, $00020011, $00000032, $0006000B, $00000001, $4C534C47, $6474732E, $3035342E,
    $00000000, $0003000E, $00000000, $00000001, $0006000F, $00000005, $00000002, $6E69616D,
    $00000000, $00000029, $00060010, $00000002, $00000011, $00000008, $00000008, $00000001,
    $00040047, $00000029, $0000000B, $0000001C, $00040047, $0000002D, $00000022, $00000000,
    $00040047, $0000002D, $00000021, $00000000, $00040047, $0000002E, $00000022, $00000000,
    $00040047, $0000002E, $00000021, $00000001, $00040047, $00000031, $00000022, $00000000,
    $00040047, $00000031, $00000021, $00000002, $00030047, $00000031, $00000019, $00030047,
    $00000032, $00000002, $00050048, $00000032, $00000000, $00000023, $00000000, $00050048,
    $00000032, $00000001, $00000023, $00000008, $00050048, $00000032, $00000002, $00000023,
    $00000010, $00050048, $00000032, $00000003, $00000023, $00000014, $00050048, $00000032,
    $00000004, $00000023, $00000018, $00050048, $00000032, $00000005, $00000023, $0000001C,
    $00050048, $00000032, $00000006, $00000023, $00000020, $00050048, $00000032, $00000007,
    $00000023, $00000024, $00050048, $00000032, $00000008, $00000023, $00000028, $00050048,
    $00000032, $00000009, $00000023, $0000002C, $00020013, $00000003, $00030021, $00000004,
    $00000003, $00020014, $00000005, $00040015, $00000006, $00000020, $00000000, $00040015,
    $00000007, $00000020, $00000001, $00030016, $00000008, $00000020, $00040017, $00000009,
    $00000006, $00000002, $00040017, $0000000A, $00000007, $00000002, $00040017, $0000000B,
    $00000006, $00000003, $00040017, $0000000C, $00000008, $00000002, $00040017, $0000000D,
    $00000008, $00000004, $0004002B, $00000006, $0000000E, $00000000, $0004002B, $00000008,
    $0000000F, $BF800000, $0004002B, $00000008, $00000010, $00000000, $0004002B, $00000008,
    $00000011, $3F000000, $0004002B, $00000008, $00000012, $3F800000, $0004002B, $00000008,
    $00000013, $3727C5AC, $0004002B, $00000008, $00000014, $42855555, $0005002C, $0000000C,
    $00000015, $00000011, $00000011, $0004002B, $00000008, $00000016, $3F242466, $0005002C,
    $0000000C, $00000017, $0000000F, $0000000F, $0004002B, $00000008, $00000018, $3F4CFD20,
    $0005002C, $0000000C, $00000019, $00000010, $0000000F, $0004002B, $00000008, $0000001A,
    $3F242466, $0005002C, $0000000C, $0000001B, $00000012, $0000000F, $0004002B, $00000008,
    $0000001C, $3F4CFD20, $0005002C, $0000000C, $0000001D, $0000000F, $00000010, $0004002B,
    $00000008, $0000001E, $3F800000, $0005002C, $0000000C, $0000001F, $00000010, $00000010,
    $0004002B, $00000008, $00000020, $3F4CFD20, $0005002C, $0000000C, $00000021, $00000012,
    $00000010, $0004002B, $00000008, $00000022, $3F242466, $0005002C, $0000000C, $00000023,
    $0000000F, $00000012, $0004002B, $00000008, $00000024, $3F4CFD20, $0005002C, $0000000C,
    $00000025, $00000010, $00000012, $0004002B, $00000008, $00000026, $3F242466, $0005002C,
    $0000000C, $00000027, $00000012, $00000012, $00040020, $00000028, $00000001, $0000000B,
    $0004003B, $00000028, $00000029, $00000001, $00090019, $0000002A, $00000008, $00000001,
    $00000000, $00000000, $00000000, $00000001, $00000000, $0003001B, $0000002B, $0000002A,
    $00040020, $0000002C, $00000000, $0000002B, $0004003B, $0000002C, $0000002D, $00000000,
    $0004003B, $0000002C, $0000002E, $00000000, $00090019, $0000002F, $00000008, $00000001,
    $00000000, $00000000, $00000000, $00000002, $00000009, $00040020, $00000030, $00000000,
    $0000002F, $0004003B, $00000030, $00000031, $00000000, $000C001E, $00000032, $0000000C,
    $0000000C, $00000008, $00000008, $00000008, $00000008, $00000008, $00000006, $00000006,
    $00000006, $00040020, $00000033, $00000009, $00000032, $00040020, $00000034, $00000009,
    $0000000C, $0004003B, $00000033, $00000035, $00000009, $00050036, $00000003, $00000002,
    $00000000, $00000004, $000200F8, $00000036, $0004003D, $0000000B, $00000039, $00000029,
    $00050051, $00000006, $0000003A, $00000039, $00000000, $00050051, $00000006, $0000003B,
    $00000039, $00000001, $00050050, $00000009, $0000003C, $0000003A, $0000003B, $0004007C,
    $0000000A, $0000003D, $0000003C, $00050051, $00000007, $0000003E, $0000003D, $00000000,
    $00050051, $00000007, $0000003F, $0000003D, $00000001, $0004003D, $0000002F, $00000040,
    $00000031, $00040068, $0000000A, $00000041, $00000040, $00050051, $00000007, $00000042,
    $00000041, $00000000, $00050051, $00000007, $00000043, $00000041, $00000001, $000500B1,
    $00000005, $00000044, $0000003E, $00000042, $000500B1, $00000005, $00000045, $0000003F,
    $00000043, $000500A7, $00000005, $00000046, $00000044, $00000045, $000300F7, $00000038,
    $00000000, $000400FA, $00000046, $00000037, $00000038, $000200F8, $00000037, $00040070,
    $00000008, $00000047, $0000003A, $00040070, $00000008, $00000048, $0000003B, $00050050,
    $0000000C, $00000049, $00000047, $00000048, $00050081, $0000000C, $0000004A, $00000049,
    $00000015, $00050041, $00000034, $0000004B, $00000035, $0000000E, $0004003D, $0000000C,
    $0000004C, $0000004B, $00050085, $0000000C, $0000004D, $0000004A, $0000004C, $0004003D,
    $0000002B, $0000004E, $0000002D, $0004003D, $0000002B, $0000004F, $0000002E, $00070058,
    $0000000D, $00000050, $0000004E, $0000004D, $00000002, $00000010, $00050051, $00000008,
    $00000051, $00000050, $00000000, $00050085, $0000000C, $00000052, $00000017, $0000004C,
    $00050081, $0000000C, $00000053, $0000004D, $00000052, $00070058, $0000000D, $00000054,
    $0000004E, $00000053, $00000002, $00000010, $00050051, $00000008, $00000055, $00000054,
    $00000000, $00070058, $0000000D, $00000056, $0000004F, $00000053, $00000002, $00000010,
    $00050051, $00000008, $00000057, $00000056, $00000000, $00050083, $00000008, $00000058,
    $00000051, $00000055, $00050085, $00000008, $00000059, $00000058, $00000014, $00050085,
    $00000008, $0000005A, $00000059, $00000059, $0004007F, $00000008, $0000005B, $0000005A,
    $0006000C, $00000008, $0000005C, $00000001, $0000001B, $0000005B, $00050085, $00000008,
    $0000005D, $00000016, $0000005C, $00050085, $00000008, $0000005E, $00000057, $0000005D,
    $00050081, $00000008, $0000005F, $00000010, $0000005E, $00050081, $00000008, $00000060,
    $00000010, $0000005D, $00050085, $0000000C, $00000061, $00000019, $0000004C, $00050081,
    $0000000C, $00000062, $0000004D, $00000061, $00070058, $0000000D, $00000063, $0000004E,
    $00000062, $00000002, $00000010, $00050051, $00000008, $00000064, $00000063, $00000000,
    $00070058, $0000000D, $00000065, $0000004F, $00000062, $00000002, $00000010, $00050051,
    $00000008, $00000066, $00000065, $00000000, $00050083, $00000008, $00000067, $00000051,
    $00000064, $00050085, $00000008, $00000068, $00000067, $00000014, $00050085, $00000008,
    $00000069, $00000068, $00000068, $0004007F, $00000008, $0000006A, $00000069, $0006000C,
    $00000008, $0000006B, $00000001, $0000001B, $0000006A, $00050085, $00000008, $0000006C,
    $00000018, $0000006B, $00050085, $00000008, $0000006D, $00000066, $0000006C, $00050081,
    $00000008, $0000006E, $0000005F, $0000006D, $00050081, $00000008, $0000006F, $00000060,
    $0000006C, $00050085, $0000000C, $00000070, $0000001B, $0000004C, $00050081, $0000000C,
    $00000071, $0000004D, $00000070, $00070058, $0000000D, $00000072, $0000004E, $00000071,
    $00000002, $00000010, $00050051, $00000008, $00000073, $00000072, $00000000, $00070058,
    $0000000D, $00000074, $0000004F, $00000071, $00000002, $00000010, $00050051, $00000008,
    $00000075, $00000074, $00000000, $00050083, $00000008, $00000076, $00000051, $00000073,
    $00050085, $00000008, $00000077, $00000076, $00000014, $00050085, $00000008, $00000078,
    $00000077, $00000077, $0004007F, $00000008, $00000079, $00000078, $0006000C, $00000008,
    $0000007A, $00000001, $0000001B, $00000079, $00050085, $00000008, $0000007B, $0000001A,
    $0000007A, $00050085, $00000008, $0000007C, $00000075, $0000007B, $00050081, $00000008,
    $0000007D, $0000006E, $0000007C, $00050081, $00000008, $0000007E, $0000006F, $0000007B,
    $00050085, $0000000C, $0000007F, $0000001D, $0000004C, $00050081, $0000000C, $00000080,
    $0000004D, $0000007F, $00070058, $0000000D, $00000081, $0000004E, $00000080, $00000002,
    $00000010, $00050051, $00000008, $00000082, $00000081, $00000000, $00070058, $0000000D,
    $00000083, $0000004F, $00000080, $00000002, $00000010, $00050051, $00000008, $00000084,
    $00000083, $00000000, $00050083, $00000008, $00000085, $00000051, $00000082, $00050085,
    $00000008, $00000086, $00000085, $00000014, $00050085, $00000008, $00000087, $00000086,
    $00000086, $0004007F, $00000008, $00000088, $00000087, $0006000C, $00000008, $00000089,
    $00000001, $0000001B, $00000088, $00050085, $00000008, $0000008A, $0000001C, $00000089,
    $00050085, $00000008, $0000008B, $00000084, $0000008A, $00050081, $00000008, $0000008C,
    $0000007D, $0000008B, $00050081, $00000008, $0000008D, $0000007E, $0000008A, $00050085,
    $0000000C, $0000008E, $0000001F, $0000004C, $00050081, $0000000C, $0000008F, $0000004D,
    $0000008E, $00070058, $0000000D, $00000090, $0000004E, $0000008F, $00000002, $00000010,
    $00050051, $00000008, $00000091, $00000090, $00000000, $00070058, $0000000D, $00000092,
    $0000004F, $0000008F, $00000002, $00000010, $00050051, $00000008, $00000093, $00000092,
    $00000000, $00050083, $00000008, $00000094, $00000051, $00000091, $00050085, $00000008,
    $00000095, $00000094, $00000014, $00050085, $00000008, $00000096, $00000095, $00000095,
    $0004007F, $00000008, $00000097, $00000096, $0006000C, $00000008, $00000098, $00000001,
    $0000001B, $00000097, $00050085, $00000008, $00000099, $0000001E, $00000098, $00050085,
    $00000008, $0000009A, $00000093, $00000099, $00050081, $00000008, $0000009B, $0000008C,
    $0000009A, $00050081, $00000008, $0000009C, $0000008D, $00000099, $00050085, $0000000C,
    $0000009D, $00000021, $0000004C, $00050081, $0000000C, $0000009E, $0000004D, $0000009D,
    $00070058, $0000000D, $0000009F, $0000004E, $0000009E, $00000002, $00000010, $00050051,
    $00000008, $000000A0, $0000009F, $00000000, $00070058, $0000000D, $000000A1, $0000004F,
    $0000009E, $00000002, $00000010, $00050051, $00000008, $000000A2, $000000A1, $00000000,
    $00050083, $00000008, $000000A3, $00000051, $000000A0, $00050085, $00000008, $000000A4,
    $000000A3, $00000014, $00050085, $00000008, $000000A5, $000000A4, $000000A4, $0004007F,
    $00000008, $000000A6, $000000A5, $0006000C, $00000008, $000000A7, $00000001, $0000001B,
    $000000A6, $00050085, $00000008, $000000A8, $00000020, $000000A7, $00050085, $00000008,
    $000000A9, $000000A2, $000000A8, $00050081, $00000008, $000000AA, $0000009B, $000000A9,
    $00050081, $00000008, $000000AB, $0000009C, $000000A8, $00050085, $0000000C, $000000AC,
    $00000023, $0000004C, $00050081, $0000000C, $000000AD, $0000004D, $000000AC, $00070058,
    $0000000D, $000000AE, $0000004E, $000000AD, $00000002, $00000010, $00050051, $00000008,
    $000000AF, $000000AE, $00000000, $00070058, $0000000D, $000000B0, $0000004F, $000000AD,
    $00000002, $00000010, $00050051, $00000008, $000000B1, $000000B0, $00000000, $00050083,
    $00000008, $000000B2, $00000051, $000000AF, $00050085, $00000008, $000000B3, $000000B2,
    $00000014, $00050085, $00000008, $000000B4, $000000B3, $000000B3, $0004007F, $00000008,
    $000000B5, $000000B4, $0006000C, $00000008, $000000B6, $00000001, $0000001B, $000000B5,
    $00050085, $00000008, $000000B7, $00000022, $000000B6, $00050085, $00000008, $000000B8,
    $000000B1, $000000B7, $00050081, $00000008, $000000B9, $000000AA, $000000B8, $00050081,
    $00000008, $000000BA, $000000AB, $000000B7, $00050085, $0000000C, $000000BB, $00000025,
    $0000004C, $00050081, $0000000C, $000000BC, $0000004D, $000000BB, $00070058, $0000000D,
    $000000BD, $0000004E, $000000BC, $00000002, $00000010, $00050051, $00000008, $000000BE,
    $000000BD, $00000000, $00070058, $0000000D, $000000BF, $0000004F, $000000BC, $00000002,
    $00000010, $00050051, $00000008, $000000C0, $000000BF, $00000000, $00050083, $00000008,
    $000000C1, $00000051, $000000BE, $00050085, $00000008, $000000C2, $000000C1, $00000014,
    $00050085, $00000008, $000000C3, $000000C2, $000000C2, $0004007F, $00000008, $000000C4,
    $000000C3, $0006000C, $00000008, $000000C5, $00000001, $0000001B, $000000C4, $00050085,
    $00000008, $000000C6, $00000024, $000000C5, $00050085, $00000008, $000000C7, $000000C0,
    $000000C6, $00050081, $00000008, $000000C8, $000000B9, $000000C7, $00050081, $00000008,
    $000000C9, $000000BA, $000000C6, $00050085, $0000000C, $000000CA, $00000027, $0000004C,
    $00050081, $0000000C, $000000CB, $0000004D, $000000CA, $00070058, $0000000D, $000000CC,
    $0000004E, $000000CB, $00000002, $00000010, $00050051, $00000008, $000000CD, $000000CC,
    $00000000, $00070058, $0000000D, $000000CE, $0000004F, $000000CB, $00000002, $00000010,
    $00050051, $00000008, $000000CF, $000000CE, $00000000, $00050083, $00000008, $000000D0,
    $00000051, $000000CD, $00050085, $00000008, $000000D1, $000000D0, $00000014, $00050085,
    $00000008, $000000D2, $000000D1, $000000D1, $0004007F, $00000008, $000000D3, $000000D2,
    $0006000C, $00000008, $000000D4, $00000001, $0000001B, $000000D3, $00050085, $00000008,
    $000000D5, $00000026, $000000D4, $00050085, $00000008, $000000D6, $000000CF, $000000D5,
    $00050081, $00000008, $000000D7, $000000C8, $000000D6, $00050081, $00000008, $000000D8,
    $000000C9, $000000D5, $0007000C, $00000008, $000000D9, $00000001, $00000028, $000000D8,
    $00000013, $00050088, $00000008, $000000DA, $000000D7, $000000D9, $00070050, $0000000D,
    $000000DB, $000000DA, $00000010, $00000010, $00000012, $00040063, $00000040, $0000003D,
    $000000DB, $000200F9, $00000038, $000200F8, $00000038, $000100FD, $00010038
  );

  BuiltInHiZSSRCompSPIRV: array[0..1012] of UInt32 = (
    $07230203, $00010000, $00000000, $000000B4, $00000000, $00020011, $00000001, $00020011,
    $00000032, $0006000B, $00000001, $4C534C47, $6474732E, $3035342E, $00000000, $0003000E,
    $00000000, $00000001, $0006000F, $00000005, $00000002, $6E69616D, $00000000, $00000027,
    $00060010, $00000002, $00000011, $00000008, $00000008, $00000001, $00040047, $00000027,
    $0000000B, $0000001C, $00040047, $0000002B, $00000022, $00000000, $00040047, $0000002B,
    $00000021, $00000000, $00040047, $0000002C, $00000022, $00000000, $00040047, $0000002C,
    $00000021, $00000001, $00040047, $0000002F, $00000022, $00000000, $00040047, $0000002F,
    $00000021, $00000002, $00030047, $0000002F, $00000019, $00030047, $00000030, $00000002,
    $00050048, $00000030, $00000000, $00000023, $00000000, $00050048, $00000030, $00000001,
    $00000023, $00000008, $00050048, $00000030, $00000002, $00000023, $0000000C, $00050048,
    $00000030, $00000003, $00000023, $00000010, $00050048, $00000030, $00000004, $00000023,
    $00000014, $00050048, $00000030, $00000005, $00000023, $00000018, $00050048, $00000030,
    $00000006, $00000023, $0000001C, $00050048, $00000030, $00000007, $00000023, $00000020,
    $00050048, $00000030, $00000008, $00000023, $00000024, $00050048, $00000030, $00000009,
    $00000023, $00000028, $00050048, $00000030, $0000000A, $00000023, $0000002C, $00020013,
    $00000003, $00030021, $00000004, $00000003, $00020014, $00000005, $00040015, $00000006,
    $00000020, $00000000, $00040015, $00000007, $00000020, $00000001, $00030016, $00000008,
    $00000020, $00040017, $00000009, $00000006, $00000002, $00040017, $0000000A, $00000007,
    $00000002, $00040017, $0000000B, $00000006, $00000003, $00040017, $0000000C, $00000008,
    $00000002, $00040017, $0000000D, $00000008, $00000003, $00040017, $0000000E, $00000008,
    $00000004, $0004002B, $00000006, $0000000F, $00000000, $0004002B, $00000006, $00000010,
    $00000001, $0004002B, $00000006, $00000011, $00000004, $0004002B, $00000006, $00000012,
    $00000005, $0004002B, $00000006, $00000013, $00000006, $0004002B, $00000006, $00000014,
    $00000007, $0004002B, $00000006, $00000015, $00000009, $0004002B, $00000008, $00000016,
    $00000000, $0004002B, $00000008, $00000017, $3D23D70A, $0004002B, $00000008, $00000018,
    $3E19999A, $0004002B, $00000008, $00000019, $3F000000, $0004002B, $00000008, $0000001A,
    $3F59999A, $0004002B, $00000008, $0000001B, $3F800000, $0004002B, $00000008, $0000001C,
    $40000000, $0004002B, $00000008, $0000001D, $40A00000, $0004002B, $00000008, $0000001E,
    $3F7FF972, $0004002B, $00000008, $0000001F, $38D1B717, $0004002B, $00000008, $00000020,
    $BB03126F, $0005002C, $0000000C, $00000021, $00000016, $00000016, $0005002C, $0000000C,
    $00000022, $00000019, $00000019, $0005002C, $0000000C, $00000023, $0000001B, $0000001B,
    $0005002C, $0000000C, $00000024, $0000001F, $0000001F, $0007002C, $0000000E, $00000025,
    $00000016, $00000016, $00000016, $00000016, $00040020, $00000026, $00000001, $0000000B,
    $0004003B, $00000026, $00000027, $00000001, $00090019, $00000028, $00000008, $00000001,
    $00000000, $00000000, $00000000, $00000001, $00000000, $0003001B, $00000029, $00000028,
    $00040020, $0000002A, $00000000, $00000029, $0004003B, $0000002A, $0000002B, $00000000,
    $0004003B, $0000002A, $0000002C, $00000000, $00090019, $0000002D, $00000008, $00000001,
    $00000000, $00000000, $00000000, $00000002, $00000002, $00040020, $0000002E, $00000000,
    $0000002D, $0004003B, $0000002E, $0000002F, $00000000, $000D001E, $00000030, $0000000C,
    $00000008, $00000008, $00000008, $00000008, $00000008, $00000008, $00000006, $00000006,
    $00000008, $00000006, $00040020, $00000031, $00000009, $00000030, $00040020, $00000032,
    $00000009, $0000000C, $00040020, $00000033, $00000009, $00000008, $00040020, $00000034,
    $00000009, $00000006, $0004003B, $00000031, $00000035, $00000009, $00040020, $00000036,
    $00000007, $00000006, $00040020, $00000037, $00000007, $00000008, $00040020, $00000038,
    $00000007, $0000000C, $00040020, $00000039, $00000007, $00000005, $0003002A, $00000005,
    $0000003A, $00030029, $00000005, $0000003B, $00050036, $00000003, $00000002, $00000000,
    $00000004, $000200F8, $0000003C, $0004003B, $00000036, $00000049, $00000007, $0004003B,
    $00000038, $0000004A, $00000007, $0004003B, $00000037, $0000004B, $00000007, $0004003B,
    $00000039, $0000004C, $00000007, $0004003D, $0000000B, $0000004D, $00000027, $00050051,
    $00000006, $0000004E, $0000004D, $00000000, $00050051, $00000006, $0000004F, $0000004D,
    $00000001, $00050050, $00000009, $00000050, $0000004E, $0000004F, $0004007C, $0000000A,
    $00000051, $00000050, $00050051, $00000007, $00000052, $00000051, $00000000, $00050051,
    $00000007, $00000053, $00000051, $00000001, $0004003D, $0000002D, $00000054, $0000002F,
    $00040068, $0000000A, $00000055, $00000054, $00050051, $00000007, $00000056, $00000055,
    $00000000, $00050051, $00000007, $00000057, $00000055, $00000001, $000500B1, $00000005,
    $00000058, $00000052, $00000056, $000500B1, $00000005, $00000059, $00000053, $00000057,
    $000500A7, $00000005, $0000005A, $00000058, $00000059, $000300F7, $00000048, $00000000,
    $000400FA, $0000005A, $0000003D, $00000048, $000200F8, $0000003D, $00040070, $00000008,
    $0000005B, $0000004E, $00040070, $00000008, $0000005C, $0000004F, $00050050, $0000000C,
    $0000005D, $0000005B, $0000005C, $00050081, $0000000C, $0000005E, $0000005D, $00000022,
    $00050041, $00000032, $0000005F, $00000035, $0000000F, $0004003D, $0000000C, $00000060,
    $0000005F, $00050085, $0000000C, $00000061, $0000005E, $00000060, $0004003D, $00000029,
    $00000062, $0000002C, $00070058, $0000000E, $00000063, $00000062, $00000061, $00000002,
    $00000016, $00050051, $00000008, $00000064, $00000063, $00000000, $000500BA, $00000005,
    $00000065, $00000064, $0000001E, $000300F7, $00000066, $00000000, $000400FA, $00000065,
    $0000003E, $0000003F, $000200F8, $0000003E, $00040063, $00000054, $00000051, $00000025,
    $000200F9, $00000066, $000200F8, $0000003F, $00050083, $0000000C, $00000069, $00000061,
    $00000022, $00050081, $0000000C, $0000006A, $00000069, $00000024, $0006000C, $0000000C,
    $0000006B, $00000001, $00000045, $0000006A, $00050085, $0000000C, $0000006C, $0000006B,
    $00000060, $0005008E, $0000000C, $0000006D, $0000006C, $0000001C, $00050041, $00000033,
    $0000006E, $00000035, $00000011, $0004003D, $00000008, $0000006F, $0000006E, $00050041,
    $00000033, $00000070, $00000035, $00000012, $0004003D, $00000008, $00000071, $00000070,
    $00050041, $00000033, $00000072, $00000035, $00000013, $0004003D, $00000008, $00000073,
    $00000072, $00050041, $00000034, $00000074, $00000035, $00000014, $0004003D, $00000006,
    $00000075, $00000074, $00050041, $00000033, $00000076, $00000035, $00000015, $0004003D,
    $00000008, $00000077, $00000076, $0003003E, $00000049, $0000000F, $0003003E, $0000004A,
    $00000061, $0003003E, $0000004B, $00000064, $0003003E, $0000004C, $0000003A, $000200F9,
    $00000040, $000200F8, $00000040, $0004003D, $00000006, $00000078, $00000049, $0004003D,
    $00000005, $00000079, $0000004C, $000400A8, $00000005, $0000007A, $00000079, $000500B0,
    $00000005, $0000007B, $00000078, $00000075, $000500A7, $00000005, $0000007C, $0000007B,
    $0000007A, $000400F6, $00000045, $00000044, $00000000, $000400FA, $0000007C, $00000041,
    $00000045, $000200F8, $00000041, $0004003D, $0000000C, $0000007D, $0000004A, $0004003D,
    $00000008, $0000007E, $0000004B, $00050081, $0000000C, $0000007F, $0000007D, $0000006D,
    $00050081, $00000008, $00000080, $0000007E, $00000020, $00050051, $00000008, $00000081,
    $0000007F, $00000000, $00050051, $00000008, $00000082, $0000007F, $00000001, $000500BA,
    $00000005, $00000083, $00000081, $00000016, $000500BC, $00000005, $00000084, $00000081,
    $0000001B, $000500BA, $00000005, $00000085, $00000082, $00000016, $000500BC, $00000005,
    $00000086, $00000082, $0000001B, $000500A7, $00000005, $00000087, $00000083, $00000084,
    $000500A7, $00000005, $00000088, $00000085, $00000086, $000500A7, $00000005, $00000089,
    $00000087, $00000088, $0008000C, $0000000C, $0000008A, $00000001, $0000002B, $0000007F,
    $00000021, $00000023, $00070058, $0000000E, $0000008B, $00000062, $0000008A, $00000002,
    $00000016, $00050051, $00000008, $0000008C, $0000008B, $00000000, $00050083, $00000008,
    $0000008D, $00000080, $0000008C, $000500BA, $00000005, $0000008E, $0000008D, $00000016,
    $000500BC, $00000005, $0000008F, $0000008D, $0000006F, $000500A7, $00000005, $00000090,
    $0000008E, $0000008F, $000500A7, $00000005, $00000091, $00000089, $00000090, $0003003E,
    $0000004A, $0000007F, $0003003E, $0000004B, $00000080, $0003003E, $0000004C, $00000091,
    $000400A8, $00000005, $00000092, $00000089, $000600A9, $00000006, $00000093, $00000092,
    $00000075, $00000078, $000200F9, $00000044, $000200F8, $00000044, $00050080, $00000006,
    $00000094, $00000093, $00000010, $0003003E, $00000049, $00000094, $000200F9, $00000040,
    $000200F8, $00000045, $0004003D, $00000005, $00000095, $0000004C, $000300F7, $00000067,
    $00000000, $000400FA, $00000095, $00000046, $00000047, $000200F8, $00000047, $00040063,
    $00000054, $00000051, $00000025, $000200F9, $00000067, $000200F8, $00000046, $0004003D,
    $0000000C, $00000096, $0000004A, $0007000C, $00000008, $00000097, $00000001, $00000028,
    $00000073, $0000001F, $00050050, $0000000C, $00000098, $00000097, $00000097, $00050083,
    $0000000C, $00000099, $00000023, $00000096, $0008000C, $0000000C, $0000009A, $00000001,
    $00000031, $00000021, $00000098, $00000096, $0008000C, $0000000C, $0000009B, $00000001,
    $00000031, $00000021, $00000098, $00000099, $00050085, $0000000C, $0000009C, $0000009A,
    $0000009B, $00050051, $00000008, $0000009D, $0000009C, $00000000, $00050051, $00000008,
    $0000009E, $0000009C, $00000001, $00050085, $00000008, $0000009F, $0000009D, $0000009E,
    $0008000C, $00000008, $000000A0, $00000001, $0000002B, $0000009F, $00000016, $0000001B,
    $0007000C, $00000008, $000000A1, $00000001, $00000028, $00000071, $0000001F, $0008000C,
    $00000008, $000000A2, $00000001, $00000031, $00000016, $000000A1, $00000018, $00050083,
    $00000008, $000000A3, $0000001B, $000000A2, $000500B8, $00000005, $000000A4, $00000018,
    $00000071, $000600A9, $00000008, $000000A5, $000000A4, $000000A3, $00000016, $0007000C,
    $00000008, $000000A6, $00000001, $0000001A, $00000019, $0000001D, $0008000C, $00000008,
    $000000A7, $00000001, $0000002E, $00000017, $0000001A, $000000A6, $00050085, $00000008,
    $000000A8, $000000A5, $000000A7, $0008000C, $00000008, $000000A9, $00000001, $0000002B,
    $000000A8, $00000016, $0000001B, $00050085, $00000008, $000000AA, $000000A9, $000000A0,
    $00050085, $00000008, $000000AB, $000000AA, $00000077, $0004003D, $00000029, $000000AC,
    $0000002B, $00070058, $0000000E, $000000AD, $000000AC, $00000096, $00000002, $00000016,
    $0008004F, $0000000D, $000000AE, $000000AD, $000000AD, $00000000, $00000001, $00000002,
    $0005008E, $0000000D, $000000AF, $000000AE, $000000AB, $00050051, $00000008, $000000B0,
    $000000AF, $00000000, $00050051, $00000008, $000000B1, $000000AF, $00000001, $00050051,
    $00000008, $000000B2, $000000AF, $00000002, $00070050, $0000000E, $000000B3, $000000B0,
    $000000B1, $000000B2, $000000AB, $00040063, $00000054, $00000051, $000000B3, $000200F9,
    $00000067, $000200F8, $00000067, $000200F9, $00000066, $000200F8, $00000066, $000200F9,
    $00000048, $000200F8, $00000048, $000100FD, $00010038
  );

  BuiltInPostProcessModulateCompSPIRV: array[0..511] of UInt32 = (
    $07230203, $00010000, $00000000, $00000059, $00000000, $00020011, $00000001, $0006000B,
    $00000001, $4C534C47, $6474732E, $3035342E, $00000000, $0003000E, $00000000, $00000001,
    $0006000F, $00000005, $00000002, $6E69616D, $00000000, $0000001A, $00060010, $00000002,
    $00000011, $00000008, $00000008, $00000001, $00040047, $0000001A, $0000000B, $0000001C,
    $00040047, $0000001E, $00000022, $00000000, $00040047, $0000001E, $00000021, $00000000,
    $00040047, $0000001F, $00000022, $00000000, $00040047, $0000001F, $00000021, $00000001,
    $00040047, $00000020, $00000022, $00000000, $00040047, $00000020, $00000021, $00000002,
    $00040047, $00000023, $00000022, $00000000, $00040047, $00000023, $00000021, $00000003,
    $00030047, $00000023, $00000019, $00030047, $00000024, $00000002, $00050048, $00000024,
    $00000000, $00000023, $00000000, $00050048, $00000024, $00000001, $00000023, $00000004,
    $00050048, $00000024, $00000002, $00000023, $00000008, $00050048, $00000024, $00000003,
    $00000023, $0000000C, $00020013, $00000003, $00030021, $00000004, $00000003, $00020014,
    $00000005, $00040015, $00000006, $00000020, $00000000, $00040015, $00000007, $00000020,
    $00000001, $00030016, $00000008, $00000020, $00040017, $00000009, $00000006, $00000002,
    $00040017, $0000000A, $00000007, $00000002, $00040017, $0000000B, $00000006, $00000003,
    $00040017, $0000000C, $00000008, $00000002, $00040017, $0000000D, $00000008, $00000003,
    $00040017, $0000000E, $00000008, $00000004, $0004002B, $00000006, $0000000F, $00000000,
    $0004002B, $00000006, $00000010, $00000001, $0004002B, $00000006, $00000011, $00000002,
    $0004002B, $00000006, $00000012, $00000003, $0004002B, $00000008, $00000013, $00000000,
    $0004002B, $00000008, $00000014, $3F000000, $0004002B, $00000008, $00000015, $3F800000,
    $0005002C, $0000000C, $00000016, $00000014, $00000014, $0005002C, $0000000C, $00000017,
    $00000015, $00000015, $0006002C, $0000000D, $00000018, $00000013, $00000013, $00000013,
    $00040020, $00000019, $00000001, $0000000B, $0004003B, $00000019, $0000001A, $00000001,
    $00090019, $0000001B, $00000008, $00000001, $00000000, $00000000, $00000000, $00000001,
    $00000000, $0003001B, $0000001C, $0000001B, $00040020, $0000001D, $00000000, $0000001C,
    $0004003B, $0000001D, $0000001E, $00000000, $0004003B, $0000001D, $0000001F, $00000000,
    $0004003B, $0000001D, $00000020, $00000000, $00090019, $00000021, $00000008, $00000001,
    $00000000, $00000000, $00000000, $00000002, $00000002, $00040020, $00000022, $00000000,
    $00000021, $0004003B, $00000022, $00000023, $00000000, $0006001E, $00000024, $00000008,
    $00000008, $00000006, $00000006, $00040020, $00000025, $00000009, $00000024, $00040020,
    $00000026, $00000009, $00000008, $00040020, $00000027, $00000009, $00000006, $0004003B,
    $00000025, $00000028, $00000009, $00050036, $00000003, $00000002, $00000000, $00000004,
    $000200F8, $00000029, $0004003D, $0000000B, $0000002C, $0000001A, $00050051, $00000006,
    $0000002D, $0000002C, $00000000, $00050051, $00000006, $0000002E, $0000002C, $00000001,
    $00050041, $00000027, $0000002F, $00000028, $00000011, $0004003D, $00000006, $00000030,
    $0000002F, $00050041, $00000027, $00000031, $00000028, $00000012, $0004003D, $00000006,
    $00000032, $00000031, $000500B0, $00000005, $00000033, $0000002D, $00000030, $000500B0,
    $00000005, $00000034, $0000002E, $00000032, $000500A7, $00000005, $00000035, $00000033,
    $00000034, $000300F7, $0000002B, $00000000, $000400FA, $00000035, $0000002A, $0000002B,
    $000200F8, $0000002A, $00040070, $00000008, $00000036, $0000002D, $00040070, $00000008,
    $00000037, $0000002E, $00050050, $0000000C, $00000038, $00000036, $00000037, $00050081,
    $0000000C, $00000039, $00000038, $00000016, $00040070, $00000008, $0000003A, $00000030,
    $00040070, $00000008, $0000003B, $00000032, $00050050, $0000000C, $0000003C, $0000003A,
    $0000003B, $0007000C, $0000000C, $0000003D, $00000001, $00000028, $0000003C, $00000017,
    $00050088, $0000000C, $0000003E, $00000039, $0000003D, $0004003D, $0000001C, $0000003F,
    $0000001E, $0004003D, $0000001C, $00000040, $0000001F, $0004003D, $0000001C, $00000041,
    $00000020, $00070058, $0000000E, $00000042, $0000003F, $0000003E, $00000002, $00000013,
    $0008004F, $0000000D, $00000043, $00000042, $00000042, $00000000, $00000001, $00000002,
    $00070058, $0000000E, $00000044, $00000040, $0000003E, $00000002, $00000013, $00050051,
    $00000008, $00000045, $00000044, $00000000, $0008000C, $00000008, $00000046, $00000001,
    $0000002B, $00000045, $00000013, $00000015, $00070058, $0000000E, $00000047, $00000041,
    $0000003E, $00000002, $00000013, $0008004F, $0000000D, $00000048, $00000047, $00000047,
    $00000000, $00000001, $00000002, $00050041, $00000026, $00000049, $00000028, $0000000F,
    $0004003D, $00000008, $0000004A, $00000049, $00050041, $00000026, $0000004B, $00000028,
    $00000010, $0004003D, $00000008, $0000004C, $0000004B, $0008000C, $00000008, $0000004D,
    $00000001, $0000002E, $00000015, $00000046, $0000004A, $0005008E, $0000000D, $0000004E,
    $00000043, $0000004D, $0005008E, $0000000D, $0000004F, $00000048, $0000004C, $00050081,
    $0000000D, $00000050, $0000004E, $0000004F, $0007000C, $0000000D, $00000051, $00000001,
    $00000028, $00000050, $00000018, $00050051, $00000008, $00000052, $00000051, $00000000,
    $00050051, $00000008, $00000053, $00000051, $00000001, $00050051, $00000008, $00000054,
    $00000051, $00000002, $00070050, $0000000E, $00000055, $00000052, $00000053, $00000054,
    $00000015, $00050050, $00000009, $00000056, $0000002D, $0000002E, $0004007C, $0000000A,
    $00000057, $00000056, $0004003D, $00000021, $00000058, $00000023, $00040063, $00000058,
    $00000057, $00000055, $000200F9, $0000002B, $000200F8, $0000002B, $000100FD, $00010038
  );

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
  if FShadercLib = nil then
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

procedure TCastleShaderCompiler.DetectExternalCompiler;
var
  Candidate: String;
begin
  FExternalCompilerPath := '';
  FExternalCompilerIsGlslc := False;
  Candidate := FindExe('glslangValidator');
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
  end;
end;

function TCastleShaderCompiler.HasExternalCLICompiler: Boolean;
begin
  Result := FExternalCompilerPath <> '';
end;

function TCastleShaderCompiler.IsRuntimeCompilationAvailable: Boolean;
begin
  Result := ((FShadercLib <> nil) and (FCompilerHandle <> nil)) or (FExternalCompilerPath <> '');
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
  CacheUrl, LocalFileName, LocalDir: String;
  Stream: TStream;
  Header: TCastleSPIRVCacheHeader;
begin
  if (not FDiskCacheEnabled) or (Length(ASPIRV) = 0) then Exit;

  CacheUrl := GetCacheFileUrl(AHash, AStage);
  try
    LocalFileName := UriToFilenameSafe(CacheUrl);
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

function TCastleShaderCompiler.CompileGLSLWithExternalCLI(
  const AStage: TRHIShaderStage; const AGLSLSource, ADebugName: String): TSPIRVBytecode;
{$if defined(FPC) and (defined(UNIX) or defined(MSWINDOWS))}
const
  StageNames: array[TRHIShaderStage] of String = ('vert', 'frag', 'geom', 'comp');
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
      Proc.Options := [poWaitOnExit, poUsePipes, poStderrToOutPut, poNoConsole];
      if FExternalCompilerIsGlslc then
      begin
        Proc.Parameters.Add('-fshader-stage=' + StageNames[AStage]);
        Proc.Parameters.Add('--target-env=vulkan1.0');
        Proc.Parameters.Add('-o');
        Proc.Parameters.Add(OutFile);
        Proc.Parameters.Add(InFile);
      end else
      begin
        Proc.Parameters.Add('-V');
        Proc.Parameters.Add('-S');
        Proc.Parameters.Add(StageNames[AStage]);
        Proc.Parameters.Add('-o');
        Proc.Parameters.Add(OutFile);
        Proc.Parameters.Add(InFile);
      end;
      Proc.Execute;
      CmdOutput := '';
      if (Proc.Output <> nil) and (Proc.Output.NumBytesAvailable > 0) then
      begin
        SetLength(CmdOutput, Proc.Output.NumBytesAvailable);
        Proc.Output.Read(CmdOutput[1], Length(CmdOutput));
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
  Status: TShadercCompilationStatus;
  ByteLen: PtrUInt;
  BytePtr: PByte;
  ErrMsg: String;
begin
  if (FShadercLib = nil) or (FCompilerHandle = nil) then
  begin
    if FExternalCompilerPath <> '' then
      Exit(CompileGLSLWithExternalCLI(AStage, AGLSLSource, ADebugName));
    raise ERHIShaderCompilationError.CreateFmt(
      'Cannot compile shader "%s": libshaderc_shared is not loaded and shader was not found in disk cache.',
      [ADebugName]);
  end;

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

function TCastleShaderCompiler.TryGetBuiltInSPIRV(const AStage: TRHIShaderStage;
  const AGLSLSource, ADebugName: String; out ASPIRV: TSPIRVBytecode): Boolean;

  procedure CopyWords(const AWords: array of UInt32);
  var
    ByteSize: PtrInt;
  begin
    ByteSize := Length(AWords) * SizeOf(UInt32);
    SetLength(ASPIRV, ByteSize);
    if ByteSize > 0 then
      Move(AWords[0], ASPIRV[0], ByteSize);
    Result := True;
  end;

begin
  ASPIRV := nil;
  Result := False;

  case AStage of
    ssVertex:
      begin
        if (ADebugName = 'Primitive2D_VS') or
           ((Pos('viewport_size', AGLSLSource) > 0) and (Pos('point_size', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInPrimitive2DVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'UnlitMesh_VS') or
           ((Pos('u_MVP', AGLSLSource) > 0) and (Pos('castle_Vertex', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInUnlitMeshVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleBatch2D.vert') or
           (Pos('CastleDraw.u_ModelViewMatrix[0].xy', AGLSLSource) > 0) then
        begin
          CopyWords(BuiltInBatch2DVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'ScreenDefaultVS') or
           (ADebugName = 'ScreenEffectVS') or
           (Pos('v_tex_coord = tex_coord', AGLSLSource) > 0) then
        begin
          CopyWords(BuiltInScreenEffectVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'HDRCompositeVS') or
           (ADebugName = 'HDRComposite_VS') or
           (Pos('HDRCompositeVS', AGLSLSource) > 0) then
        begin
          CopyWords(BuiltInHDRCompositeVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleBindlessIndirectVS') or
           ((Pos('InstancesSSBO', AGLSLSource) > 0) and (Pos('gl_InstanceIndex', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInBindlessIndirectVertSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleDefault3DVert') or
           (ADebugName = 'CastleVSMCasterVert') or
           (Pos('CastleShapeVert', ADebugName) = 1) or
           ((Pos('CastleSceneBlock', AGLSLSource) > 0) and (Pos('CastlePushConstants', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltIn3DPosNormUVVertSPIRV);
          Exit;
        end;
      end;

    ssFragment:
      begin
        if (ADebugName = 'Primitive2D_FS') or
           ((Pos('viewport_size', AGLSLSource) > 0) and (Pos('out_Color = pc.color', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInPrimitive2DFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'UnlitMesh_FS') or
           ((Pos('u_MVP', AGLSLSource) > 0) and (Pos('out_Color = pc.u_Color', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInUnlitMeshFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleBatch2D.frag') or
           ((Pos('u_SpriteTexture', AGLSLSource) > 0) and (Pos('CastleDraw.u_ModelViewMatrix[1]', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInBatch2DFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleVSMCasterFrag') or
           (Pos('out_Moments = vec4(depth, moment2', AGLSLSource) > 0) then
        begin
          CopyWords(BuiltInVSMCasterFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'HDRCompositeFS') or
           (ADebugName = 'HDRComposite_FS') or
           ((Pos('u_HDRSceneTexture', AGLSLSource) > 0) and (Pos('u_BloomTexture', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInHDRCompositeFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'ScreenDefaultFS') or
           (ADebugName = 'ScreenEffectFS') or
           (Pos('sampler2D screen', AGLSLSource) > 0) then
        begin
          if (Pos('1.0 -', AGLSLSource) > 0) or (Pos('invert', LowerCase(AGLSLSource)) > 0) then
            CopyWords(BuiltInScreenEffectInvertFragSPIRV)
          else
            CopyWords(BuiltInScreenEffectPassthroughFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleBindlessIndirectFS') or
           ((Pos('CastleBindlessMaterialsBlock', AGLSLSource) > 0) and (Pos('castle_BindlessTextures', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInBindlessIndirectFragSPIRV);
          Exit;
        end;
        if (ADebugName = 'CastleDefault3DFrag') or
           (Pos('CastleShapeFrag', ADebugName) = 1) or
           ((Pos('CastleMaterialBlock', AGLSLSource) > 0) and (Pos('CastleLightsBlock', AGLSLSource) > 0)) then
        begin
          if Pos('texture(castle_base_color_texture,', AGLSLSource) > 0 then
            CopyWords(BuiltIn3DForwardTexturedFragSPIRV)
          else
            CopyWords(BuiltIn3DForwardFragSPIRV);
          Exit;
        end;
      end;

    ssCompute:
      begin
        if (ADebugName = 'GpuCullingCS') or
           ((Pos('GpuCullingUniformBlock', AGLSLSource) > 0) and (Pos('GpuCullingIndirectOutSSBO', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInGpuCullingCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'HiZDownsampleCS') or
           ((Pos('u_SrcMip', AGLSLSource) > 0) and (Pos('u_DstMip', AGLSLSource) > 0) and (Pos('r32f', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInHiZDownsampleCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'MaterialBinHistogramCS') or
           ((Pos('MaterialIDsSSBO', AGLSLSource) > 0) and (Pos('atomicAdd(BinCounts[', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInMaterialBinHistCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'MaterialBinPrefixSumCS') or
           ((Pos('BinOffsets[', AGLSLSource) > 0) and (Pos('RunningSum', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInMaterialBinScanCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'BloomDownsampleCS') or
           (ADebugName = 'BloomDown_CS') or
           ((Pos('KarisWeight', AGLSLSource) > 0) and (Pos('SoftThreshold', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInBloomDownsampleCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'BloomUpsampleCS') or
           (ADebugName = 'BloomUp_CS') or
           ((Pos('u_SrcMip', AGLSLSource) > 0) and (Pos('FilterRadius', AGLSLSource) > 0) and (Pos('KarisWeight', AGLSLSource) = 0)) then
        begin
          CopyWords(BuiltInBloomUpsampleCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'LuminanceHistogramCS') or
           (ADebugName = 'LumHist_CS') or
           ((Pos('HistogramBins', AGLSLSource) > 0) and (Pos('AutoExposureParams', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInLuminanceHistogramCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'GTAOHorizon_CS') or
           (ADebugName = 'GTAO_CS') or
           ((Pos('u_OutGTAO', AGLSLSource) > 0) and (Pos('IntegrateHorizonSlice', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInGTAOHorizonCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'GTAODenoise_CS') or
           ((Pos('u_RawGTAO', AGLSLSource) > 0) and (Pos('u_DenoisedGTAO', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInGTAODenoiseCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'HiZSSR_CS') or
           ((Pos('u_HiZPyramid', AGLSLSource) > 0) and (Pos('u_SSRReflectionOut', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInHiZSSRCompSPIRV);
          Exit;
        end;
        if (ADebugName = 'PostProcessModulateCS') or
           ((Pos('u_OutModulatedHDR', AGLSLSource) > 0) and (Pos('PostProcessModulatePC', AGLSLSource) > 0)) then
        begin
          CopyWords(BuiltInPostProcessModulateCompSPIRV);
          Exit;
        end;
      end;
  end;
end;

function TCastleShaderCompiler.GetMinimalValidSPIRVFallback(
  const AStage: TRHIShaderStage): TSPIRVBytecode;
const
  MinimalVertWords: array[0..28] of UInt32 = (
    $07230203, $00010000, $00000000, $00000005, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0005000F, 0, 1, $6E69616D, $00000000,
    $00020013, 2,
    $00030021, 3, 2,
    $00050036, 2, 1, 0, 3,
    $000200F8, 4,
    $000100FD,
    $00010038
  );
  MinimalFragWords: array[0..31] of UInt32 = (
    $07230203, $00010000, $00000000, $00000005, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0005000F, 4, 1, $6E69616D, $00000000,
    $00030010, 1, 7,
    $00020013, 2,
    $00030021, 3, 2,
    $00050036, 2, 1, 0, 3,
    $000200F8, 4,
    $000100FD,
    $00010038
  );
  MinimalCompWords: array[0..34] of UInt32 = (
    $07230203, $00010000, $00000000, $00000005, $00000000,
    $00020011, 1,
    $0003000E, 0, 1,
    $0005000F, 5, 1, $6E69616D, $00000000,
    $00060010, 1, 17, 1, 1, 1,
    $00020013, 2,
    $00030021, 3, 2,
    $00050036, 2, 1, 0, 3,
    $000200F8, 4,
    $000100FD,
    $00010038
  );
  MinimalGeomWords: array[0..38] of UInt32 = (
    $07230203, $00010000, $00000000, $00000005, $00000000,
    $00020011, 2,
    $0003000E, 0, 1,
    $0005000F, 3, 1, $6E69616D, $00000000,
    $00030010, 1, 22,
    $00040010, 1, 26, 3,
    $00030010, 1, 29,
    $00020013, 2,
    $00030021, 3, 2,
    $00050036, 2, 1, 0, 3,
    $000200F8, 4,
    $000100FD,
    $00010038
  );
begin
  Result := nil;
  case AStage of
    ssFragment:
      begin
        SetLength(Result, SizeOf(MinimalFragWords));
        Move(MinimalFragWords[0], Result[0], SizeOf(MinimalFragWords));
      end;
    ssCompute:
      begin
        SetLength(Result, SizeOf(MinimalCompWords));
        Move(MinimalCompWords[0], Result[0], SizeOf(MinimalCompWords));
      end;
    ssGeometry:
      begin
        SetLength(Result, SizeOf(MinimalGeomWords));
        Move(MinimalGeomWords[0], Result[0], SizeOf(MinimalGeomWords));
      end;
  else
    begin
      SetLength(Result, SizeOf(MinimalVertWords));
      Move(MinimalVertWords[0], Result[0], SizeOf(MinimalVertWords));
    end;
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
