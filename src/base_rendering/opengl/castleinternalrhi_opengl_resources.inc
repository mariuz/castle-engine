{%MainUnit castleinternalrhi_opengl.pas}
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

{$ifdef read_interface}
  { -------------------------------------------------------------------------- }
  { Concrete OpenGL Resource Classes                                           }
  { -------------------------------------------------------------------------- }

  TOpenGLRHIBuffer = class(TRHIBuffer)
  private
    FHandle: TGLuint;
    FTarget: TGLenum;
    FMappedFallback: Pointer;
    FIsMappedForWrite: Boolean;
    FMappedUploadedViaSubData: Boolean;
    FHostShadow: TBytes;
    function OpenGLDevice: TOpenGLRHIDevice;
    procedure SyncMappedToGL(const AOffset: PtrUInt = 0; const ASize: PtrUInt = 0);
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TOpenGLRHIDevice; const ADesc: TRHIBufferDesc;
      const InitialData: Pointer);
    destructor Destroy; override;

    function Map: Pointer; override;
    procedure Unmap; override;
    procedure UploadData(const Data; const Size: PtrUInt; const Offset: PtrUInt = 0); override;
    procedure ReadData(out Data; const Size: PtrUInt; const Offset: PtrUInt = 0);

    property Handle: TGLuint read FHandle;
    property Target: TGLenum read FTarget;
  end;

  TOpenGLRHITexture = class(TRHITexture)
  private
    FHandle: TGLuint;
    FTarget: TGLenum;
    FInternalFormat: TGLint;
    FImageUnitFormat: TGLenum;
    FIsDefaultBackbuffer: Boolean;
    FImmutableStorage: Boolean;
    FHostPixels: TBytes;
    function OpenGLDevice: TOpenGLRHIDevice;
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TOpenGLRHIDevice; const ADesc: TRHITextureDesc); overload;
    constructor CreateDefaultBackbufferWrapper(const ADevice: TOpenGLRHIDevice;
      const ADesc: TRHITextureDesc); overload;
    destructor Destroy; override;

    procedure UploadImage(const AImage: TEncodedImage;
      const AMipLevel: Cardinal = 0; const AArrayLayer: Cardinal = 0); override;

    property Handle: TGLuint read FHandle;
    property Target: TGLenum read FTarget;
    property InternalFormat: TGLint read FInternalFormat;
    property ImageUnitFormat: TGLenum read FImageUnitFormat;
    property IsDefaultBackbuffer: Boolean read FIsDefaultBackbuffer;
    property ImmutableStorage: Boolean read FImmutableStorage;
  end;

  TOpenGLRHISampler = class(TRHISampler)
  private
    FHandle: TGLuint;
    function OpenGLDevice: TOpenGLRHIDevice;
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TOpenGLRHIDevice; const ADesc: TRHISamplerDesc);
    destructor Destroy; override;
    property Handle: TGLuint read FHandle;
  end;

  TOpenGLRHIShaderModule = class(TRHIShaderModule)
  private
    FHandle: TGLuint;
    FTranslatedSource: String;
    FSourceHash: UInt64;
    function OpenGLDevice: TOpenGLRHIDevice;
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TOpenGLRHIDevice; const AStage: TRHIShaderStage;
      const AGLSLSource: String; const ADebugName: String);
    destructor Destroy; override;
    property Handle: TGLuint read FHandle;
    property TranslatedSource: String read FTranslatedSource;
    property SourceHash: UInt64 read FSourceHash;
  end;

  TOpenGLRHIDescriptorSetLayout = class(TRHIDescriptorSetLayout)
  private
    FBindings: array of TRHIDescriptorBindingDesc;
  public
    constructor Create(const ADevice: TOpenGLRHIDevice;
      const ABindings: array of TRHIDescriptorBindingDesc);
    function FindBindingType(const ABinding: Cardinal;
      out AType: TRHIDescriptorType): Boolean;
    function BindingCount: Integer;
    function GetBinding(const AIndex: Integer): TRHIDescriptorBindingDesc;
  end;

  TOpenGLBoundBuffer = record
    Binding: Cardinal;
    Buffer: TOpenGLRHIBuffer;
    Offset: PtrUInt;
    Range: PtrUInt;
    IsStorage: Boolean;
    IsDynamic: Boolean;
  end;

  TOpenGLBoundTexture = record
    Binding: Cardinal;
    ArrayElement: Cardinal;
    Texture: TOpenGLRHITexture;
    Sampler: TOpenGLRHISampler;
    MipLevel: Cardinal;
    ArrayLayer: Cardinal;
    HasSubresourceOverride: Boolean;
    IsStorageImage: Boolean;
  end;

  TOpenGLRHIDescriptorSet = class(TRHIDescriptorSet)
  private
    FLayout: TOpenGLRHIDescriptorSetLayout;
    FBoundBuffers: array of TOpenGLBoundBuffer;
    FBoundTextures: array of TOpenGLBoundTexture;
    FUpdateCount: Cardinal;
    procedure SetBufferEntry(const ABinding: Cardinal; const ABuffer: TOpenGLRHIBuffer;
      const AOffset, ARange: PtrUInt; const AIsStorage: Boolean);
    procedure SetTextureEntry(const ABinding, AArrayElement: Cardinal;
      const ATexture: TOpenGLRHITexture; const ASampler: TOpenGLRHISampler;
      const AMipLevel, AArrayLayer: Cardinal; const AHasSubresource: Boolean;
      const AForceStorageImage: Boolean);
  public
    constructor Create(const ADevice: TOpenGLRHIDevice;
      const ALayout: TOpenGLRHIDescriptorSetLayout);
    procedure BindUniformBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); override;
    procedure BindStorageBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); override;
    procedure BindTexture(const Binding: Cardinal; const Texture: TRHITexture;
      const Sampler: TRHISampler); override;
    procedure BindTextureAtIndex(const Binding, ArrayElement: Cardinal;
      const Texture: TRHITexture; const Sampler: TRHISampler); override;
    procedure BindTextureSubresource(const Binding: Cardinal;
      const Texture: TRHITexture; const MipLevel, ArrayLayer: Cardinal;
      const Sampler: TRHISampler = nil); override;
    procedure BindStorageImage(const Binding: Cardinal;
      const Texture: TRHITexture; const MipLevel: Cardinal = 0;
      const ArrayLayer: Cardinal = 0);
    procedure Update; override;

    property Layout: TOpenGLRHIDescriptorSetLayout read FLayout;
    property UpdateCount: Cardinal read FUpdateCount;
  end;

  TOpenGLRHIPipeline = class(TRHIPipeline)
  private
    FProgramHandle: TGLuint;
    FVAOHandle: TGLuint;
    FPushConstantUBO: TGLuint;
    FPushConstantCapacity: Cardinal;
    FPrimitiveMode: TGLenum;
    function OpenGLDevice: TOpenGLRHIDevice;
    procedure EnsurePushConstantCapacity(const AMinBytes: Cardinal);
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TOpenGLRHIDevice;
      const ADesc: TRHIGraphicsPipelineDesc);
    destructor Destroy; override;

    property ProgramHandle: TGLuint read FProgramHandle;
    property VAOHandle: TGLuint read FVAOHandle;
    property PrimitiveMode: TGLenum read FPrimitiveMode;
    property PushConstantUBO: TGLuint read FPushConstantUBO;
  end;

  TOpenGLRHIComputePipeline = class(TRHIComputePipeline)
  private
    FProgramHandle: TGLuint;
    FPushConstantUBO: TGLuint;
    FPushConstantCapacity: Cardinal;
    FWorkGroupSize: TVector3Cardinal;
    function OpenGLDevice: TOpenGLRHIDevice;
    procedure EnsurePushConstantCapacity(const AMinBytes: Cardinal);
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TOpenGLRHIDevice;
      const ADesc: TRHIComputePipelineDesc);
    destructor Destroy; override;

    property ProgramHandle: TGLuint read FProgramHandle;
    property PushConstantUBO: TGLuint read FPushConstantUBO;
    property WorkGroupSize: TVector3Cardinal read FWorkGroupSize;
  end;

  TOpenGLRHIQueryPool = class(TRHIQueryPool)
  private
    FQueries: array of TGLuint;
    FActiveTargets: array of TGLenum;
    FQueryWritten: array of Boolean;
    FSimulatedResults: array of UInt64;
    FResetCount: Cardinal;
    function OpenGLDevice: TOpenGLRHIDevice;
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TOpenGLRHIDevice; const ADesc: TRHIQueryPoolDesc);
    destructor Destroy; override;

    function GetResults(const FirstQuery, QueryCount: Cardinal;
      out Results: array of UInt64; const WaitForResults: Boolean = False): Boolean; override;

    property ResetCount: Cardinal read FResetCount;
  end;

  { -------------------------------------------------------------------------- }
  { OpenGL Command List (Immediate State Machine Execution)                    }
  { -------------------------------------------------------------------------- }

  TOpenGLRHICommandList = class(TRHICommandList)
  private
    FDevice: TOpenGLRHIDevice;
    FScratchFBO: TGLuint;
    FResolveFBO: TGLuint;
    FCurrentPipeline: TOpenGLRHIPipeline;
    FCurrentComputePipeline: TOpenGLRHIComputePipeline;
    FCurrentPrimitiveMode: TGLenum;
    FCurrentIndexBuffer: TOpenGLRHIBuffer;
    FCurrentIndexOffset: PtrUInt;
    FCurrentIndexType: TGLenum;
    FCurrentIndexSize: Cardinal;
    FScissorEnabled: Boolean;
    FDynamicScissorRect: TRectangle;
    FDynamicViewportRect: TFloatRectangle;
    FIsRecording: Boolean;
    FComputeDispatchCount: Cardinal;
    FDrawCallCount: Cardinal;
    FIndirectDrawCallCount: Cardinal;
    FBarrierCount: Cardinal;
    FAliasingBarrierCount: Cardinal;
    FDebugGroupDepth: Integer;
    FDebugGroupPushCount: Cardinal;
    FDebugMarkerCount: Cardinal;
    procedure ApplyPipelineState(const NewPipeline: TOpenGLRHIPipeline);
    procedure ApplyDescriptorSetInternal(const SetIndex: Cardinal;
      const DescriptorSet: TRHIDescriptorSet;
      const DynamicOffsets: array of Cardinal);
    procedure ApplyVertexLayout(const Pipeline: TOpenGLRHIPipeline;
      const FirstBinding: Cardinal; const Buffers: array of TRHIBuffer;
      const Offsets: array of PtrUInt);
    procedure EmitMemoryBarrierForState(const NewState: TRHIResourceState);
  public
    constructor Create(const ADevice: TOpenGLRHIDevice;
      const ALevel: TRHICommandListLevel = cllPrimary);
    destructor Destroy; override;

    procedure BeginRecording; override;
    procedure EndRecording; override;

    procedure TransitionTexture(const Texture: TRHITexture;
      const NewState: TRHIResourceState); override;
    procedure EmitAliasingBarrier(const OldTexture, NewTexture: TRHITexture); override;
    procedure GenerateMipmaps(const Texture: TRHITexture); override;

    procedure BeginRendering(const Info: TRHIRenderingInfo); override;
    procedure EndRendering; override;
    procedure ClearAttachments(const ClearColorBuf: Boolean; const ClearColor: TCastleColor;
      const ClearDepthBuf: Boolean = False; const ClearDepth: Single = 1.0;
      const ClearStencilBuf: Boolean = False; const ClearStencil: Byte = 0); override;

    procedure SetViewport(const ViewportRect: TFloatRectangle;
      const MinDepth: Single = 0.0; const MaxDepth: Single = 1.0); override;
    procedure SetScissor(const ScissorRect: TRectangle); override;
    procedure SetDepthBias(const ConstantFactor, SlopeFactor: Single); override;
    procedure SetLineWidth(const LineWidth: Single); override;
    procedure SetBlendConstants(const ABlendConstants: TVector4); override;

    procedure SetCullMode(const CullMode: TRHICullMode); override;
    procedure SetFrontFace(const FrontFace: TRHIFrontFace); override;
    procedure SetDepthTestEnable(const Enable: Boolean); override;
    procedure SetDepthWriteEnable(const Enable: Boolean); override;
    procedure SetDepthCompareOp(const CompareOp: TRHICompareOp); override;
    procedure SetPrimitiveTopology(const Topology: TRHIPrimitiveTopology); override;

    procedure BindPipeline(const Pipeline: TRHIPipeline); override;
    procedure BindDescriptorSet(const SetIndex: Cardinal;
      const DescriptorSet: TRHIDescriptorSet;
      const DynamicOffsets: array of Cardinal); override;
    procedure PushConstants(const StageFlags: TRHIShaderStageFlags;
      const Offset, Size: Cardinal; const Data); override;

    procedure BindComputePipeline(const Pipeline: TRHIComputePipeline); override;
    procedure BindComputeDescriptorSet(const SetIndex: Cardinal;
      const DescriptorSet: TRHIDescriptorSet;
      const DynamicOffsets: array of Cardinal); override;
    procedure Dispatch(const GroupCountX, GroupCountY, GroupCountZ: Cardinal); override;
    procedure DispatchIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt = 0); override;

    procedure ResetQueryPool(const QueryPool: TRHIQueryPool;
      const FirstQuery, QueryCount: Cardinal); override;
    procedure BeginQuery(const QueryPool: TRHIQueryPool;
      const QueryIndex: Cardinal; const Precise: Boolean = False); override;
    procedure EndQuery(const QueryPool: TRHIQueryPool;
      const QueryIndex: Cardinal); override;
    procedure WriteTimestamp(const QueryPool: TRHIQueryPool;
      const QueryIndex: Cardinal; const Stage: TRHIShaderStage = ssFragment); override;

    procedure BindVertexBuffers(const FirstBinding: Cardinal;
      const Buffers: array of TRHIBuffer;
      const Offsets: array of PtrUInt); override;
    procedure BindIndexBuffer(const Buffer: TRHIBuffer;
      const Offset: PtrUInt; const IndexType: TRHIIndexType); override;

    procedure Draw(const VertexCount, InstanceCount, FirstVertex, FirstInstance: Cardinal); override;
    procedure DrawIndexed(const IndexCount, InstanceCount, FirstIndex: Cardinal;
      const VertexOffset: Integer; const FirstInstance: Cardinal); override;
    procedure DrawIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure DrawIndirectCount(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
      const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal); override;
    procedure DrawIndexedIndirectCount(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
      const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal); override;

    procedure ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList); override;

    procedure PushDebugGroup(const LabelName: String; const Color: TCastleColor); override;
    procedure PopDebugGroup; override;
    procedure InsertDebugMarker(const LabelName: String; const Color: TCastleColor); override;

    property IsRecording: Boolean read FIsRecording;
    property ComputeDispatchCount: Cardinal read FComputeDispatchCount;
    property DrawCallCount: Cardinal read FDrawCallCount;
    property IndirectDrawCallCount: Cardinal read FIndirectDrawCallCount;
    property BarrierCount: Cardinal read FBarrierCount;
    property AliasingBarrierCount: Cardinal read FAliasingBarrierCount;
    property DebugGroupPushCount: Cardinal read FDebugGroupPushCount;
    property DebugMarkerCount: Cardinal read FDebugMarkerCount;
  end;

  { -------------------------------------------------------------------------- }
  { OpenGL Render Device                                                       }
  { -------------------------------------------------------------------------- }

  TOpenGLPipelineMap = {$ifdef FPC}specialize{$endif} TObjectDictionary<UInt64, TOpenGLRHIPipeline>;
  TOpenGLComputePipelineMap = {$ifdef FPC}specialize{$endif} TObjectDictionary<UInt64, TOpenGLRHIComputePipeline>;

  TOpenGLRHIDevice = class(TRHIDevice)
  private
    FHasLiveGLContext: Boolean;
    FCommandList: TOpenGLRHICommandList;
    FDefaultColorTarget: TOpenGLRHITexture;
    FDefaultDepthTarget: TOpenGLRHITexture;
    FPipelineMap: TOpenGLPipelineMap;
    FComputePipelineMap: TOpenGLComputePipelineMap;
    FReadbackFBO: TGLuint;
    FReadbackResolveFBO: TGLuint;
    FMaxImageUnits: Cardinal;
    FPipelineCacheHits: Cardinal;
    FPipelineCacheMisses: Cardinal;
    FComputePipelineCacheHits: Cardinal;
    FComputePipelineCacheMisses: Cardinal;
    FComputeDispatchCount: Cardinal;
    FIndirectDrawCallCount: Cardinal;
    procedure QueryDeviceCapabilities;
    function ComputePipelineHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
    function ComputeComputePipelineHash(const ADesc: TRHIComputePipelineDesc): UInt64;
    function GetPipelineCount: Integer;
    function GetComputePipelineCount: Integer;
  public
    { Creates an OpenGL RHI device wrapping the currently active CGE OpenGL/OpenGLES context. }
    constructor Create(const InitialWidth, InitialHeight: Cardinal); reintroduce; overload;
    { Creates a deterministic headless OpenGL RHI device for unit testing without an active GL context. }
    constructor CreateHeadless(const InitialWidth: Cardinal = 128;
      const InitialHeight: Cardinal = 128;
      const ASupportsCompute: Boolean = True;
      const ASupportsMultiDrawIndirect: Boolean = True;
      const ASupportsDrawIndirectCount: Boolean = True); overload;
    class function TryCreateFromCurrentGLContext(out ADevice: TOpenGLRHIDevice;
      const InitialWidth, InitialHeight: Cardinal): Boolean;
    destructor Destroy; override;

    function BeginFrame: TRHICommandList; override;
    procedure EndFrameAndPresent; override;
    function BeginOffscreenFrame: TRHICommandList; override;
    procedure EndOffscreenFrame; override;
    procedure ResizeSwapchain(const NewWidth, NewHeight: Cardinal); override;
    procedure WaitIdle; override;
    function CreateSecondaryCommandList: TRHICommandList; override;

    function GetSwapchainColorTexture: TRHITexture; override;
    function GetSwapchainDepthTexture: TRHITexture; override;

    function CreateBuffer(const ADesc: TRHIBufferDesc;
      const InitialData: Pointer = nil): TRHIBuffer; override;
    function CreateTexture(const ADesc: TRHITextureDesc): TRHITexture; override;
    function CreateSampler(const ADesc: TRHISamplerDesc): TRHISampler; override;

    function CreateShaderModuleFromGLSL(const AStage: TRHIShaderStage;
      const AGLSLSource: String; const ADebugName: String = ''): TRHIShaderModule; override;
    function CreateShaderModuleFromSPIRV(const AStage: TRHIShaderStage;
      const ASPIRVBinary: Pointer; const ASizeInBytes: PtrUInt;
      const ADebugName: String = ''): TRHIShaderModule; override;

    function CreateDescriptorSetLayout(
      const Bindings: array of TRHIDescriptorBindingDesc): TRHIDescriptorSetLayout; override;
    function CreateDescriptorSet(
      const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet; override;

    function GetOrCreatePipeline(const ADesc: TRHIGraphicsPipelineDesc): TRHIPipeline; override;
    function GetOrCreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline; override;
    function CreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline; override;
    function CreateQueryPool(const ADesc: TRHIQueryPoolDesc): TRHIQueryPool; override;

    function GrabTextureImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle): TRGBAlphaImage; overload; override;
    function GrabTextureSubresourceImage(const SourceTexture: TRHITexture;
      const AMipLevel, AArrayLayer: Cardinal): TRGBAlphaImage; override;
    function GrabTextureFloatImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle): TRGBAlphaFloatImage; override;

    procedure LoadPipelineCache(const CacheFileUrl: String); override;
    procedure SavePipelineCache(const CacheFileUrl: String); override;

    property HasLiveGLContext: Boolean read FHasLiveGLContext;
    property MaxImageUnits: Cardinal read FMaxImageUnits;
    property PipelineCount: Integer read GetPipelineCount;
    property ComputePipelineCount: Integer read GetComputePipelineCount;
    property PipelineCacheHits: Cardinal read FPipelineCacheHits;
    property PipelineCacheMisses: Cardinal read FPipelineCacheMisses;
    property ComputePipelineCacheHits: Cardinal read FComputePipelineCacheHits;
    property ComputePipelineCacheMisses: Cardinal read FComputePipelineCacheMisses;
    property ComputeDispatchCount: Cardinal read FComputeDispatchCount;
    property IndirectDrawCallCount: Cardinal read FIndirectDrawCallCount;
  end;

{ Translates Vulkan-style #version 450 / #version 460 RHI GLSL source
  (layout(set = S, binding = B), layout(push_constant), gl_VertexIndex, gl_InstanceIndex)
  into OpenGL 4.3+ (#version 430 core) or OpenGL ES 3.1+ (#version 310 es) GLSL
  with flattened binding slots (SetIdx * GL_DESCRIPTOR_SET_SLOT_STRIDE + BindIdx)
  and UBO push-constant binding slot GL_PUSH_CONSTANT_UBO_BINDING.
  Leaves native #version 330 / #version 430 / #version 300 es / #version 310 es
  sources intact unless Vulkan layout qualifiers are present. }
function TranslateVulkanGLSLToOpenGL(const AStage: TRHIShaderStage;
  const AGLSLSource: String;
  const ATargetOpenGLES: Boolean = {$ifdef OpenGLES}True{$else}False{$endif}): String;

{$endif read_interface}

{$ifdef read_implementation}
{ ---------------------------------------------------------------------------- }
{ TOpenGLRHIBuffer                                                             }
{ ---------------------------------------------------------------------------- }

function TOpenGLRHIBuffer.OpenGLDevice: TOpenGLRHIDevice;
begin
  Result := Device as TOpenGLRHIDevice;
end;

constructor TOpenGLRHIBuffer.Create(const ADevice: TOpenGLRHIDevice;
  const ADesc: TRHIBufferDesc; const InitialData: Pointer);
var
  GLUsage: TGLenum;
  ByteSize: PtrUInt;
begin
  inherited Create(ADevice, ADesc);

  if buIndex in ADesc.Usage then
    FTarget := GL_ELEMENT_ARRAY_BUFFER
  else if buUniform in ADesc.Usage then
    FTarget := GL_UNIFORM_BUFFER
  else if buStorage in ADesc.Usage then
    FTarget := GL_SHADER_STORAGE_BUFFER
  else if buIndirect in ADesc.Usage then
    FTarget := GL_DRAW_INDIRECT_BUFFER
  else
    FTarget := GL_ARRAY_BUFFER;

  if ADesc.MemoryUsage = muCpuToGpu then
    GLUsage := GL_DYNAMIC_DRAW
  else if ADesc.MemoryUsage = muGpuToCpu then
    GLUsage := GL_STREAM_READ
  else if (buStorage in ADesc.Usage) or (buIndirect in ADesc.Usage) then
    GLUsage := GL_DYNAMIC_DRAW
  else
    GLUsage := GL_STATIC_DRAW;

  ByteSize := Max(PtrUInt(1), ADesc.Size);

  if (ADevice <> nil) and ADevice.HasLiveGLContext then
  begin
    glGenBuffers(1, @FHandle);
    glBindBuffer(FTarget, FHandle);
    glBufferData(FTarget, ByteSize, InitialData, GLUsage);
    glBindBuffer(FTarget, 0);
  end else
  begin
    FHandle := TGLuint(UniqueId and $7FFFFFFF);
    if FHandle = 0 then
      FHandle := 1;
    SetLength(FHostShadow, ByteSize);
    if (InitialData <> nil) and (ADesc.Size > 0) then
      Move(InitialData^, FHostShadow[0], ADesc.Size)
    else if ByteSize > 0 then
      FillChar(FHostShadow[0], ByteSize, 0);
  end;
end;

procedure TOpenGLRHIBuffer.ReleaseDeviceResources;
begin
  if FMappedFallback <> nil then
  begin
    FreeMem(FMappedFallback);
    FMappedFallback := nil;
  end;
  FIsMappedForWrite := False;
  FMappedUploadedViaSubData := False;
  if (FHandle <> 0) and (OpenGLDevice <> nil) and OpenGLDevice.HasLiveGLContext then
    glDeleteBuffers(1, @FHandle);
  FHandle := 0;
  SetLength(FHostShadow, 0);
end;

destructor TOpenGLRHIBuffer.Destroy;
begin
  inherited;
end;

procedure TOpenGLRHIBuffer.SyncMappedToGL(const AOffset: PtrUInt; const ASize: PtrUInt);
var
  TotalBytes, SyncOffset, SyncBytes: PtrUInt;
begin
  if (not FIsMappedForWrite) or (FMappedFallback = nil) or
     (OpenGLDevice = nil) or (not OpenGLDevice.HasLiveGLContext) then
    Exit;

  TotalBytes := Max(PtrUInt(1), FDesc.Size);
  if AOffset >= TotalBytes then
    Exit;
  SyncOffset := AOffset;
  if (ASize = 0) or (SyncOffset + ASize > TotalBytes) then
    SyncBytes := TotalBytes - SyncOffset
  else
    SyncBytes := ASize;

  glBindBuffer(FTarget, FHandle);
  glBufferSubData(FTarget, SyncOffset, SyncBytes, PByte(FMappedFallback) + SyncOffset);
  glBindBuffer(FTarget, 0);
end;

function TOpenGLRHIBuffer.Map: Pointer;
var
  ByteSize: PtrUInt;
begin
  ByteSize := Max(PtrUInt(1), FDesc.Size);

  if (OpenGLDevice = nil) or (not OpenGLDevice.HasLiveGLContext) then
  begin
    if Length(FHostShadow) < PtrInt(ByteSize) then
      SetLength(FHostShadow, ByteSize);
    Exit(@FHostShadow[0]);
  end;

  { Use a persistent CPU staging mirror (FMappedFallback) instead of leaving the
    OpenGL buffer object in GL_BUFFER_MAPPED state via glMapBufferRange without
    GL_MAP_PERSISTENT_BIT. Per OpenGL 4.6 Core Spec 6.3.2, issuing glDraw* or
    glDispatch* while a buffer is mapped without MAP_PERSISTENT_BIT raises
    GL_INVALID_OPERATION on strict hardware drivers (NVIDIA, AMD, Intel), and
    GL_MAP_INVALIDATE_BUFFER_BIT would discard earlier sub-ranges written in
    multi-pass streaming ring buffers (such as TCastleBatch2DRenderer). }
  if FMappedFallback = nil then
  begin
    GetMem(FMappedFallback, ByteSize);
    FillChar(FMappedFallback^, ByteSize, 0);
  end;

  {$ifndef OpenGLES}
  if ((FDesc.MemoryUsage = muGpuToCpu) or (buStorage in FDesc.Usage) or (buIndirect in FDesc.Usage)) and
     Assigned(glGetBufferSubData) then
  begin
    glBindBuffer(FTarget, FHandle);
    glGetBufferSubData(FTarget, 0, ByteSize, FMappedFallback);
    glBindBuffer(FTarget, 0);
  end;
  {$endif}

  FIsMappedForWrite := (FDesc.MemoryUsage <> muGpuToCpu);
  FMappedUploadedViaSubData := False;
  Result := FMappedFallback;
end;

procedure TOpenGLRHIBuffer.Unmap;
begin
  if (OpenGLDevice = nil) or (not OpenGLDevice.HasLiveGLContext) then
    Exit;

  if FIsMappedForWrite and (not FMappedUploadedViaSubData) then
    SyncMappedToGL(0, 0);
  FIsMappedForWrite := False;
  FMappedUploadedViaSubData := False;
end;

procedure TOpenGLRHIBuffer.UploadData(const Data; const Size: PtrUInt; const Offset: PtrUInt);
var
  ByteSize: PtrUInt;
begin
  if Size = 0 then Exit;

  if (OpenGLDevice = nil) or (not OpenGLDevice.HasLiveGLContext) then
  begin
    if Offset + Size > PtrUInt(Length(FHostShadow)) then
      SetLength(FHostShadow, Offset + Size);
    Move(Data, FHostShadow[Offset], Size);
    Exit;
  end;

  ByteSize := Max(PtrUInt(1), FDesc.Size);
  if (FMappedFallback <> nil) and (Offset + Size <= ByteSize) and
     (Pointer(@Data) <> Pointer(PByte(FMappedFallback) + Offset)) then
    Move(Data, (PByte(FMappedFallback) + Offset)^, Size);
  if FIsMappedForWrite then
    FMappedUploadedViaSubData := True;

  glBindBuffer(FTarget, FHandle);
  glBufferSubData(FTarget, Offset, Size, @Data);
  glBindBuffer(FTarget, 0);
end;

procedure TOpenGLRHIBuffer.ReadData(out Data; const Size: PtrUInt; const Offset: PtrUInt);
var
  MappedPtr: PByte;
begin
  if Size = 0 then Exit;
  FillChar(Data, Size, 0);

  if (OpenGLDevice = nil) or (not OpenGLDevice.HasLiveGLContext) then
  begin
    if Offset + Size <= PtrUInt(Length(FHostShadow)) then
      Move(FHostShadow[Offset], Data, Size);
    Exit;
  end;

  {$ifndef OpenGLES}
  if Assigned(glGetBufferSubData) then
  begin
    glBindBuffer(FTarget, FHandle);
    glGetBufferSubData(FTarget, Offset, Size, @Data);
    glBindBuffer(FTarget, 0);
    Exit;
  end;
  {$endif}

  glBindBuffer(FTarget, FHandle);
  MappedPtr := PByte(glMapBufferRange(FTarget, Offset, Size, GL_MAP_READ_BIT));
  if MappedPtr <> nil then
  begin
    Move(MappedPtr^, Data, Size);
    glUnmapBuffer(FTarget);
  end;
  glBindBuffer(FTarget, 0);
end;

{ ---------------------------------------------------------------------------- }
{ TOpenGLRHITexture                                                            }
{ ---------------------------------------------------------------------------- }

function TOpenGLRHITexture.OpenGLDevice: TOpenGLRHIDevice;
begin
  Result := Device as TOpenGLRHIDevice;
end;

constructor TOpenGLRHITexture.Create(const ADevice: TOpenGLRHIDevice;
  const ADesc: TRHITextureDesc);
var
  PixelFormat, PixelType: TGLenum;
  Mip, MipCount, W, H, D, Face, Samples: Cardinal;
begin
  inherited Create(ADevice, ADesc);
  FIsDefaultBackbuffer := False;
  FImmutableStorage := False;

  Samples := Max(Cardinal(1), ADesc.SampleCount);
  MipCount := Max(Cardinal(1), ADesc.MipLevels);

  if (ADesc.Dimension = td2D) and (Samples > 1) then
    FTarget := GL_TEXTURE_2D_MULTISAMPLE
  else
  begin
    case ADesc.Dimension of
      td2D:      FTarget := GL_TEXTURE_2D;
      td2DArray: FTarget := GL_TEXTURE_2D_ARRAY;
      tdCube:    FTarget := GL_TEXTURE_CUBE_MAP;
      td3D:      FTarget := GL_TEXTURE_3D;
    else
      FTarget := GL_TEXTURE_2D;
    end;
  end;

  RHIToGLFormat(ADesc.Format, FInternalFormat, PixelFormat, PixelType, FImageUnitFormat);

  if (ADevice = nil) or (not ADevice.HasLiveGLContext) then
  begin
    FHandle := TGLuint(UniqueId and $7FFFFFFF);
    if FHandle = 0 then
      FHandle := 1;
    SetLength(FHostPixels,
      PtrUInt(Max(Cardinal(1), ADesc.Width)) *
      PtrUInt(Max(Cardinal(1), ADesc.Height)) * 4);
    Exit;
  end;

  glGenTextures(1, @FHandle);
  glBindTexture(FTarget, FHandle);

  {$ifndef OpenGLES}
  if FTarget = GL_TEXTURE_2D_MULTISAMPLE then
  begin
    if Assigned(glTexStorage2DMultisample) then
    begin
      glTexStorage2DMultisample(FTarget, Samples, TGLenum(FInternalFormat),
        Max(Cardinal(1), ADesc.Width), Max(Cardinal(1), ADesc.Height), GL_TRUE);
      FImmutableStorage := True;
    end else
    if Assigned(glTexImage2DMultisample) then
      glTexImage2DMultisample(FTarget, Samples, FInternalFormat,
        Max(Cardinal(1), ADesc.Width), Max(Cardinal(1), ADesc.Height), GL_TRUE);
    glBindTexture(FTarget, 0);
    Exit;
  end;
  {$endif}

  { Use immutable storage (glTexStorage2D / glTexStorage3D) when available, especially
    for tuStorage textures bound via glBindImageTexture where OpenGL requires immutable
    or level-complete mip pyramids. }
  {$ifndef OpenGLES}
  if Assigned(glTexStorage2D) and (ADesc.Dimension in [td2D, tdCube]) then
  begin
    glTexStorage2D(FTarget, MipCount, TGLenum(FInternalFormat),
      Max(Cardinal(1), ADesc.Width), Max(Cardinal(1), ADesc.Height));
    FImmutableStorage := True;
  end else
  if Assigned(glTexStorage3D) and (ADesc.Dimension in [td2DArray, td3D]) then
  begin
    glTexStorage3D(FTarget, MipCount, TGLenum(FInternalFormat),
      Max(Cardinal(1), ADesc.Width), Max(Cardinal(1), ADesc.Height),
      Max(Cardinal(1), ADesc.DepthOrArrayLayers));
    FImmutableStorage := True;
  end else
  {$endif}
  begin
    glTexParameteri(FTarget, GL_TEXTURE_BASE_LEVEL, 0);
    glTexParameteri(FTarget, GL_TEXTURE_MAX_LEVEL, TGLint(MipCount - 1));

    if ADesc.Dimension = tdCube then
    begin
      for Face := 0 to 5 do
      begin
        W := Max(Cardinal(1), ADesc.Width);
        H := Max(Cardinal(1), ADesc.Height);
        for Mip := 0 to MipCount - 1 do
        begin
          glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + Face, Mip, FInternalFormat,
            W, H, 0, PixelFormat, PixelType, nil);
          W := Max(1, W div 2);
          H := Max(1, H div 2);
        end;
      end;
    end else
    if ADesc.Dimension in [td2DArray, td3D] then
    begin
      W := Max(Cardinal(1), ADesc.Width);
      H := Max(Cardinal(1), ADesc.Height);
      D := Max(Cardinal(1), ADesc.DepthOrArrayLayers);
      for Mip := 0 to MipCount - 1 do
      begin
        glTexImage3D(FTarget, Mip, FInternalFormat, W, H, D, 0, PixelFormat, PixelType, nil);
        W := Max(1, W div 2);
        H := Max(1, H div 2);
        if ADesc.Dimension = td3D then
          D := Max(1, D div 2);
      end;
    end else
    begin
      W := Max(Cardinal(1), ADesc.Width);
      H := Max(Cardinal(1), ADesc.Height);
      for Mip := 0 to MipCount - 1 do
      begin
        glTexImage2D(FTarget, Mip, FInternalFormat, W, H, 0, PixelFormat, PixelType, nil);
        W := Max(1, W div 2);
        H := Max(1, H div 2);
      end;
    end;
  end;

  if FDesc.Format in [pfD16_UNorm, pfD24_UNorm_S8_UInt, pfD32_Float, pfD32_Float_S8_UInt] then
  begin
    glTexParameteri(FTarget, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(FTarget, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  end else
  begin
    if MipCount > 1 then
      glTexParameteri(FTarget, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
    else
      glTexParameteri(FTarget, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(FTarget, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  end;
  glTexParameteri(FTarget, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(FTarget, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  if ADesc.Dimension in [tdCube, td3D, td2DArray] then
    glTexParameteri(FTarget, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);

  glBindTexture(FTarget, 0);
end;

constructor TOpenGLRHITexture.CreateDefaultBackbufferWrapper(
  const ADevice: TOpenGLRHIDevice; const ADesc: TRHITextureDesc);
var
  PixelFormat, PixelType: TGLenum;
begin
  inherited Create(ADevice, ADesc);
  FIsDefaultBackbuffer := True;
  FHandle := 0;
  FTarget := GL_TEXTURE_2D;
  RHIToGLFormat(ADesc.Format, FInternalFormat, PixelFormat, PixelType, FImageUnitFormat);
end;

procedure TOpenGLRHITexture.ReleaseDeviceResources;
begin
  if (not FIsDefaultBackbuffer) and (FHandle <> 0) and
     (OpenGLDevice <> nil) and OpenGLDevice.HasLiveGLContext then
    glDeleteTextures(1, @FHandle);
  FHandle := 0;
  SetLength(FHostPixels, 0);
end;

destructor TOpenGLRHITexture.Destroy;
begin
  inherited;
end;

procedure TOpenGLRHITexture.UploadImage(const AImage: TEncodedImage;
  const AMipLevel: Cardinal; const AArrayLayer: Cardinal);
var
  UploadFormat, UploadType, SubTarget: TGLenum;
  ConvertedRgba: TRGBAlphaImage;
  ConvertedFloat: TRGBAlphaFloatImage;
  SrcPixels: Pointer;
  ImgW, ImgH, ImgD: Cardinal;
begin
  if FIsDefaultBackbuffer or (AImage = nil) then Exit;

  ImgW := Max(Cardinal(1), AImage.Width);
  ImgH := Max(Cardinal(1), AImage.Height);
  ImgD := Max(Cardinal(1), AImage.Depth);

  if (OpenGLDevice = nil) or (not OpenGLDevice.HasLiveGLContext) then
  begin
    if (AMipLevel = 0) and (AArrayLayer = 0) and (AImage is TCastleImage) then
    begin
      ConvertedRgba := TCastleImage(AImage).MakeCopy as TRGBAlphaImage;
      try
        SetLength(FHostPixels, PtrUInt(ImgW) * PtrUInt(ImgH) * 4);
        Move(ConvertedRgba.RawPixels^, FHostPixels[0], Length(FHostPixels));
      finally
        FreeAndNil(ConvertedRgba);
      end;
    end;
    Exit;
  end;

  glBindTexture(FTarget, FHandle);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

  ConvertedRgba := nil;
  ConvertedFloat := nil;
  try
    if FDesc.Format in [pfR16_Float, pfRG16_Float, pfRGBA16_Float, pfR32_Float, pfRGBA32_Float] then
    begin
      if AImage is TRGBAlphaFloatImage then
        SrcPixels := TRGBAlphaFloatImage(AImage).RawPixels
      else if AImage is TCastleImage then
      begin
        ConvertedFloat := TRGBAlphaFloatImage.Create(ImgW, ImgH, ImgD);
        ConvertedFloat.Assign(TCastleImage(AImage));
        SrcPixels := ConvertedFloat.RawPixels;
      end else
        Exit;
      UploadFormat := GL_RGBA;
      UploadType := GL_FLOAT;
    end else
    begin
      if AImage is TRGBAlphaImage then
        SrcPixels := TRGBAlphaImage(AImage).RawPixels
      else if AImage is TCastleImage then
      begin
        ConvertedRgba := TRGBAlphaImage.Create(ImgW, ImgH, ImgD);
        ConvertedRgba.Assign(TCastleImage(AImage));
        SrcPixels := ConvertedRgba.RawPixels;
      end else
        Exit;
      UploadFormat := GL_RGBA;
      UploadType := GL_UNSIGNED_BYTE;
    end;

    if FDesc.Dimension = tdCube then
    begin
      SubTarget := GL_TEXTURE_CUBE_MAP_POSITIVE_X + Min(Cardinal(5), AArrayLayer);
      glTexSubImage2D(SubTarget, AMipLevel, 0, 0, ImgW, ImgH,
        UploadFormat, UploadType, SrcPixels);
    end else
    if FDesc.Dimension = td2DArray then
      glTexSubImage3D(FTarget, AMipLevel, 0, 0, AArrayLayer, ImgW, ImgH, 1,
        UploadFormat, UploadType, SrcPixels)
    else
    if FDesc.Dimension = td3D then
      glTexSubImage3D(FTarget, AMipLevel, 0, 0, 0, ImgW, ImgH, ImgD,
        UploadFormat, UploadType, SrcPixels)
    else
      glTexSubImage2D(FTarget, AMipLevel, 0, 0, ImgW, ImgH,
        UploadFormat, UploadType, SrcPixels);
  finally
    FreeAndNil(ConvertedFloat);
    FreeAndNil(ConvertedRgba);
    glBindTexture(FTarget, 0);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TOpenGLRHISampler, ShaderModule, DescriptorSetLayout, DescriptorSet          }
{ ---------------------------------------------------------------------------- }

function TOpenGLRHISampler.OpenGLDevice: TOpenGLRHIDevice;
begin
  Result := Device as TOpenGLRHIDevice;
end;

constructor TOpenGLRHISampler.Create(const ADevice: TOpenGLRHIDevice; const ADesc: TRHISamplerDesc);
var
  MinFilterGL: TGLint;
begin
  inherited Create(ADevice, ADesc);

  if (ADevice = nil) or (not ADevice.HasLiveGLContext) then
  begin
    FHandle := TGLuint(UniqueId and $7FFFFFFF);
    if FHandle = 0 then
      FHandle := 1;
    Exit;
  end;

  glGenSamplers(1, @FHandle);
  if ADesc.MagFilter = sfNearest then
    glSamplerParameteri(FHandle, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  else
    glSamplerParameteri(FHandle, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  if ADesc.MaxLod > 0.0 then
  begin
    if ADesc.MinFilter = sfNearest then
    begin
      if ADesc.MipFilter = sfNearest then
        MinFilterGL := GL_NEAREST_MIPMAP_NEAREST
      else
        MinFilterGL := GL_NEAREST_MIPMAP_LINEAR;
    end else
    begin
      if ADesc.MipFilter = sfNearest then
        MinFilterGL := GL_LINEAR_MIPMAP_NEAREST
      else
        MinFilterGL := GL_LINEAR_MIPMAP_LINEAR;
    end;
  end else
  begin
    if ADesc.MinFilter = sfNearest then
      MinFilterGL := GL_NEAREST
    else
      MinFilterGL := GL_LINEAR;
  end;
  glSamplerParameteri(FHandle, GL_TEXTURE_MIN_FILTER, MinFilterGL);

  glSamplerParameteri(FHandle, GL_TEXTURE_WRAP_S, RHIToGLWrapMode(ADesc.AddressModeU));
  glSamplerParameteri(FHandle, GL_TEXTURE_WRAP_T, RHIToGLWrapMode(ADesc.AddressModeV));
  glSamplerParameteri(FHandle, GL_TEXTURE_WRAP_R, RHIToGLWrapMode(ADesc.AddressModeW));

  if ADesc.MinLod >= 0.0 then
    glSamplerParameterf(FHandle, GL_TEXTURE_MIN_LOD, ADesc.MinLod);
  if ADesc.MaxLod > 0.0 then
    glSamplerParameterf(FHandle, GL_TEXTURE_MAX_LOD, ADesc.MaxLod);

  {$ifndef OpenGLES}
  if (ADesc.MaxAnisotropy > 1.0) and (ADevice.Capabilities.MaxAnisotropy > 1.0) then
    glSamplerParameterf(FHandle, GL_TEXTURE_MAX_ANISOTROPY_EXT,
      EnsureRange(ADesc.MaxAnisotropy, 1.0, ADevice.Capabilities.MaxAnisotropy));
  {$endif}

  if ADesc.CompareEnable then
  begin
    glSamplerParameteri(FHandle, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
    glSamplerParameteri(FHandle, GL_TEXTURE_COMPARE_FUNC, RHIToGLCompareOp(ADesc.CompareOp));
  end;
end;

procedure TOpenGLRHISampler.ReleaseDeviceResources;
begin
  if (FHandle <> 0) and (OpenGLDevice <> nil) and OpenGLDevice.HasLiveGLContext then
    glDeleteSamplers(1, @FHandle);
  FHandle := 0;
end;

destructor TOpenGLRHISampler.Destroy;
begin
  inherited;
end;

function TOpenGLRHIShaderModule.OpenGLDevice: TOpenGLRHIDevice;
begin
  Result := Device as TOpenGLRHIDevice;
end;

constructor TOpenGLRHIShaderModule.Create(const ADevice: TOpenGLRHIDevice;
  const AStage: TRHIShaderStage; const AGLSLSource: String; const ADebugName: String);
var
  GLStage: TGLenum;
  AnsiSrc: AnsiString;
  SrcPtr: PGLchar;
  SrcLen, CompileStatus, LogLen: TGLint;
  ErrorLog: AnsiString;
begin
  inherited Create(ADevice, AStage, ADebugName);

  FTranslatedSource := TranslateVulkanGLSLToOpenGL(AStage, AGLSLSource);
  FSourceHash := FNV1aOffsetBasis64;
  HashStringFNV1a(FSourceHash, FTranslatedSource);

  if (ADevice = nil) or (not ADevice.HasLiveGLContext) then
  begin
    FHandle := TGLuint(UniqueId and $7FFFFFFF);
    if FHandle = 0 then
      FHandle := 1;
    Exit;
  end;

  case AStage of
    ssVertex:   GLStage := GL_VERTEX_SHADER;
    ssFragment: GLStage := GL_FRAGMENT_SHADER;
    {$ifndef OpenGLES}
    ssGeometry: GLStage := GL_GEOMETRY_SHADER;
    {$endif}
    ssCompute:  GLStage := GL_COMPUTE_SHADER;
  else
    GLStage := GL_VERTEX_SHADER;
  end;

  FHandle := glCreateShader(GLStage);
  AnsiSrc := AnsiString(FTranslatedSource);
  SrcPtr := PGLchar(AnsiSrc);
  SrcLen := Length(AnsiSrc);
  glShaderSource(FHandle, 1, @SrcPtr, @SrcLen);
  glCompileShader(FHandle);

  CompileStatus := GL_FALSE;
  glGetShaderiv(FHandle, GL_COMPILE_STATUS, @CompileStatus);
  if CompileStatus = GL_FALSE then
  begin
    LogLen := 0;
    glGetShaderiv(FHandle, GL_INFO_LOG_LENGTH, @LogLen);
    SetLength(ErrorLog, Max(0, LogLen));
    if LogLen > 0 then
      glGetShaderInfoLog(FHandle, LogLen, nil, PGLchar(ErrorLog));
    glDeleteShader(FHandle);
    FHandle := 0;
    raise ERHIShaderCompilationError.CreateFmt('OpenGL Shader (%s) compilation failed:%s%s',
      [ADebugName, LineEnding, String(ErrorLog)]);
  end;
end;

procedure TOpenGLRHIShaderModule.ReleaseDeviceResources;
begin
  if (FHandle <> 0) and (OpenGLDevice <> nil) and OpenGLDevice.HasLiveGLContext then
    glDeleteShader(FHandle);
  FHandle := 0;
end;

destructor TOpenGLRHIShaderModule.Destroy;
begin
  inherited;
end;

constructor TOpenGLRHIDescriptorSetLayout.Create(const ADevice: TOpenGLRHIDevice;
  const ABindings: array of TRHIDescriptorBindingDesc);
var
  I: Integer;
begin
  inherited Create(ADevice, '');
  SetLength(FBindings, Length(ABindings));
  for I := 0 to High(ABindings) do
    FBindings[I] := ABindings[I];
end;

function TOpenGLRHIDescriptorSetLayout.FindBindingType(const ABinding: Cardinal;
  out AType: TRHIDescriptorType): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FBindings) do
    if FBindings[I].Binding = ABinding then
    begin
      AType := FBindings[I].DescriptorType;
      Exit(True);
    end;
  AType := dtCombinedImageSampler;
  Result := False;
end;

function TOpenGLRHIDescriptorSetLayout.BindingCount: Integer;
begin
  Result := Length(FBindings);
end;

function TOpenGLRHIDescriptorSetLayout.GetBinding(const AIndex: Integer): TRHIDescriptorBindingDesc;
begin
  Result := FBindings[AIndex];
end;

constructor TOpenGLRHIDescriptorSet.Create(const ADevice: TOpenGLRHIDevice;
  const ALayout: TOpenGLRHIDescriptorSetLayout);
begin
  inherited Create(ADevice, '');
  FLayout := ALayout;
end;

procedure TOpenGLRHIDescriptorSet.SetBufferEntry(const ABinding: Cardinal;
  const ABuffer: TOpenGLRHIBuffer; const AOffset, ARange: PtrUInt;
  const AIsStorage: Boolean);
var
  I, Idx: Integer;
  DeclType: TRHIDescriptorType;
  EffStorage, EffDynamic: Boolean;
begin
  EffStorage := AIsStorage;
  EffDynamic := False;
  if (FLayout <> nil) and FLayout.FindBindingType(ABinding, DeclType) then
  begin
    if DeclType = dtStorageBuffer then
      EffStorage := True
    else if DeclType = dtUniformBufferDynamic then
      EffDynamic := True;
  end;

  Idx := -1;
  for I := 0 to High(FBoundBuffers) do
    if FBoundBuffers[I].Binding = ABinding then
    begin
      Idx := I;
      Break;
    end;

  if Idx < 0 then
  begin
    Idx := Length(FBoundBuffers);
    SetLength(FBoundBuffers, Idx + 1);
  end;

  FBoundBuffers[Idx].Binding := ABinding;
  FBoundBuffers[Idx].Buffer := ABuffer;
  FBoundBuffers[Idx].Offset := AOffset;
  if (ARange = 0) and (ABuffer <> nil) then
    FBoundBuffers[Idx].Range := Max(PtrUInt(1), ABuffer.Desc.Size - Min(AOffset, ABuffer.Desc.Size))
  else
    FBoundBuffers[Idx].Range := ARange;
  FBoundBuffers[Idx].IsStorage := EffStorage;
  FBoundBuffers[Idx].IsDynamic := EffDynamic;
end;

procedure TOpenGLRHIDescriptorSet.SetTextureEntry(const ABinding, AArrayElement: Cardinal;
  const ATexture: TOpenGLRHITexture; const ASampler: TOpenGLRHISampler;
  const AMipLevel, AArrayLayer: Cardinal; const AHasSubresource: Boolean;
  const AForceStorageImage: Boolean);
var
  I, Idx: Integer;
  DeclType: TRHIDescriptorType;
  EffStorageImg: Boolean;
begin
  EffStorageImg := AForceStorageImage;
  if not EffStorageImg then
  begin
    if (FLayout <> nil) and FLayout.FindBindingType(ABinding, DeclType) then
      EffStorageImg := (DeclType = dtStorageImage)
    else if (ASampler = nil) and (ATexture <> nil) and (tuStorage in ATexture.Desc.Usage) and
            not (tuSampled in ATexture.Desc.Usage) then
      EffStorageImg := True;
  end;

  Idx := -1;
  for I := 0 to High(FBoundTextures) do
    if (FBoundTextures[I].Binding = ABinding) and
       (FBoundTextures[I].ArrayElement = AArrayElement) then
    begin
      Idx := I;
      Break;
    end;

  if Idx < 0 then
  begin
    Idx := Length(FBoundTextures);
    SetLength(FBoundTextures, Idx + 1);
  end;

  FBoundTextures[Idx].Binding := ABinding;
  FBoundTextures[Idx].ArrayElement := AArrayElement;
  FBoundTextures[Idx].Texture := ATexture;
  FBoundTextures[Idx].Sampler := ASampler;
  FBoundTextures[Idx].MipLevel := AMipLevel;
  FBoundTextures[Idx].ArrayLayer := AArrayLayer;
  FBoundTextures[Idx].HasSubresourceOverride := AHasSubresource;
  FBoundTextures[Idx].IsStorageImage := EffStorageImg;
end;

procedure TOpenGLRHIDescriptorSet.BindUniformBuffer(const Binding: Cardinal;
  const Buffer: TRHIBuffer; const Offset, Range: PtrUInt);
begin
  SetBufferEntry(Binding, Buffer as TOpenGLRHIBuffer, Offset, Range, False);
end;

procedure TOpenGLRHIDescriptorSet.BindStorageBuffer(const Binding: Cardinal;
  const Buffer: TRHIBuffer; const Offset, Range: PtrUInt);
begin
  SetBufferEntry(Binding, Buffer as TOpenGLRHIBuffer, Offset, Range, True);
end;

procedure TOpenGLRHIDescriptorSet.BindTexture(const Binding: Cardinal;
  const Texture: TRHITexture; const Sampler: TRHISampler);
begin
  SetTextureEntry(Binding, 0, Texture as TOpenGLRHITexture,
    Sampler as TOpenGLRHISampler, 0, 0, False, False);
end;

procedure TOpenGLRHIDescriptorSet.BindTextureAtIndex(const Binding, ArrayElement: Cardinal;
  const Texture: TRHITexture; const Sampler: TRHISampler);
begin
  SetTextureEntry(Binding, ArrayElement, Texture as TOpenGLRHITexture,
    Sampler as TOpenGLRHISampler, 0, 0, False, False);
end;

procedure TOpenGLRHIDescriptorSet.BindTextureSubresource(const Binding: Cardinal;
  const Texture: TRHITexture; const MipLevel, ArrayLayer: Cardinal;
  const Sampler: TRHISampler);
begin
  SetTextureEntry(Binding, 0, Texture as TOpenGLRHITexture,
    Sampler as TOpenGLRHISampler, MipLevel, ArrayLayer, True, False);
end;

procedure TOpenGLRHIDescriptorSet.BindStorageImage(const Binding: Cardinal;
  const Texture: TRHITexture; const MipLevel, ArrayLayer: Cardinal);
begin
  SetTextureEntry(Binding, 0, Texture as TOpenGLRHITexture,
    nil, MipLevel, ArrayLayer, True, True);
end;

procedure TOpenGLRHIDescriptorSet.Update;
begin
  Inc(FUpdateCount);
end;

{ ---------------------------------------------------------------------------- }
{ TOpenGLRHIPipeline & TOpenGLRHIComputePipeline                               }
{ ---------------------------------------------------------------------------- }

function TOpenGLRHIPipeline.OpenGLDevice: TOpenGLRHIDevice;
begin
  Result := Device as TOpenGLRHIDevice;
end;

procedure TOpenGLRHIPipeline.EnsurePushConstantCapacity(const AMinBytes: Cardinal);
var
  AllocBytes: Cardinal;
begin
  if (OpenGLDevice = nil) or (not OpenGLDevice.HasLiveGLContext) or (AMinBytes = 0) then
    Exit;
  if (FPushConstantUBO <> 0) and (FPushConstantCapacity >= AMinBytes) then
    Exit;

  AllocBytes := Max(Cardinal(256), AMinBytes);
  if FPushConstantUBO = 0 then
    glGenBuffers(1, @FPushConstantUBO);
  glBindBuffer(GL_UNIFORM_BUFFER, FPushConstantUBO);
  glBufferData(GL_UNIFORM_BUFFER, AllocBytes, nil, GL_STREAM_DRAW);
  glBindBuffer(GL_UNIFORM_BUFFER, 0);
  FPushConstantCapacity := AllocBytes;
end;

constructor TOpenGLRHIPipeline.Create(const ADevice: TOpenGLRHIDevice;
  const ADesc: TRHIGraphicsPipelineDesc);
var
  LinkStatus, LogLen: TGLint;
  ErrorLog: AnsiString;
  I: Integer;
begin
  inherited Create(ADevice, ADesc);
  FPrimitiveMode := RHIToGLTopology(ADesc.Topology);

  if (ADevice = nil) or (not ADevice.HasLiveGLContext) then
  begin
    FProgramHandle := TGLuint(UniqueId and $7FFFFFFF);
    if FProgramHandle = 0 then
      FProgramHandle := 1;
    FVAOHandle := FProgramHandle;
    Exit;
  end;

  FProgramHandle := glCreateProgram();
  if ADesc.VertexShader <> nil then
    glAttachShader(FProgramHandle, (ADesc.VertexShader as TOpenGLRHIShaderModule).Handle);
  if ADesc.FragmentShader <> nil then
    glAttachShader(FProgramHandle, (ADesc.FragmentShader as TOpenGLRHIShaderModule).Handle);
  if ADesc.GeometryShader <> nil then
    glAttachShader(FProgramHandle, (ADesc.GeometryShader as TOpenGLRHIShaderModule).Handle);

  for I := 0 to High(ADesc.VertexInput.Attributes) do
    if ADesc.VertexInput.Attributes[I].AttributeName <> '' then
      glBindAttribLocation(FProgramHandle, ADesc.VertexInput.Attributes[I].Location,
        PGLchar(AnsiString(ADesc.VertexInput.Attributes[I].AttributeName)));

  glLinkProgram(FProgramHandle);
  LinkStatus := GL_FALSE;
  glGetProgramiv(FProgramHandle, GL_LINK_STATUS, @LinkStatus);
  if LinkStatus = GL_FALSE then
  begin
    LogLen := 0;
    glGetProgramiv(FProgramHandle, GL_INFO_LOG_LENGTH, @LogLen);
    SetLength(ErrorLog, Max(0, LogLen));
    if LogLen > 0 then
      glGetProgramInfoLog(FProgramHandle, LogLen, nil, PGLchar(ErrorLog));
    glDeleteProgram(FProgramHandle);
    FProgramHandle := 0;
    raise ERHIShaderCompilationError.CreateFmt('OpenGL Program (%s) link failed:%s%s',
      [ADesc.DebugName, LineEnding, String(ErrorLog)]);
  end;

  glGenVertexArrays(1, @FVAOHandle);
  if ADesc.PushConstantSize > 0 then
    EnsurePushConstantCapacity(ADesc.PushConstantSize);
end;

procedure TOpenGLRHIPipeline.ReleaseDeviceResources;
begin
  if (OpenGLDevice <> nil) and OpenGLDevice.HasLiveGLContext then
  begin
    if FPushConstantUBO <> 0 then
      glDeleteBuffers(1, @FPushConstantUBO);
    if FVAOHandle <> 0 then
      glDeleteVertexArrays(1, @FVAOHandle);
    if FProgramHandle <> 0 then
      glDeleteProgram(FProgramHandle);
  end;
  FPushConstantUBO := 0;
  FPushConstantCapacity := 0;
  FVAOHandle := 0;
  FProgramHandle := 0;
end;

destructor TOpenGLRHIPipeline.Destroy;
begin
  inherited;
end;

function TOpenGLRHIComputePipeline.OpenGLDevice: TOpenGLRHIDevice;
begin
  Result := Device as TOpenGLRHIDevice;
end;

procedure TOpenGLRHIComputePipeline.EnsurePushConstantCapacity(const AMinBytes: Cardinal);
var
  AllocBytes: Cardinal;
begin
  if (OpenGLDevice = nil) or (not OpenGLDevice.HasLiveGLContext) or (AMinBytes = 0) then
    Exit;
  if (FPushConstantUBO <> 0) and (FPushConstantCapacity >= AMinBytes) then
    Exit;

  AllocBytes := Max(Cardinal(256), AMinBytes);
  if FPushConstantUBO = 0 then
    glGenBuffers(1, @FPushConstantUBO);
  glBindBuffer(GL_UNIFORM_BUFFER, FPushConstantUBO);
  glBufferData(GL_UNIFORM_BUFFER, AllocBytes, nil, GL_STREAM_DRAW);
  glBindBuffer(GL_UNIFORM_BUFFER, 0);
  FPushConstantCapacity := AllocBytes;
end;

constructor TOpenGLRHIComputePipeline.Create(const ADevice: TOpenGLRHIDevice;
  const ADesc: TRHIComputePipelineDesc);
var
  LinkStatus, LogLen: TGLint;
  WgSizes: array[0..2] of TGLint;
  ErrorLog: AnsiString;
begin
  inherited Create(ADevice, ADesc);
  FWorkGroupSize := Vector3Cardinal(1, 1, 1);

  if (ADevice = nil) or (not ADevice.HasLiveGLContext) then
  begin
    FProgramHandle := TGLuint(UniqueId and $7FFFFFFF);
    if FProgramHandle = 0 then
      FProgramHandle := 1;
    Exit;
  end;

  if ADesc.ComputeShader = nil then
    raise ERHIShaderCompilationError.CreateFmt(
      'OpenGL Compute Pipeline (%s) requires a non-nil ComputeShader module',
      [ADesc.DebugName]);

  FProgramHandle := glCreateProgram();
  glAttachShader(FProgramHandle, (ADesc.ComputeShader as TOpenGLRHIShaderModule).Handle);
  glLinkProgram(FProgramHandle);

  LinkStatus := GL_FALSE;
  glGetProgramiv(FProgramHandle, GL_LINK_STATUS, @LinkStatus);
  if LinkStatus = GL_FALSE then
  begin
    LogLen := 0;
    glGetProgramiv(FProgramHandle, GL_INFO_LOG_LENGTH, @LogLen);
    SetLength(ErrorLog, Max(0, LogLen));
    if LogLen > 0 then
      glGetProgramInfoLog(FProgramHandle, LogLen, nil, PGLchar(ErrorLog));
    glDeleteProgram(FProgramHandle);
    FProgramHandle := 0;
    raise ERHIShaderCompilationError.CreateFmt('OpenGL Compute Program (%s) link failed:%s%s',
      [ADesc.DebugName, LineEnding, String(ErrorLog)]);
  end;

  WgSizes[0] := 1;
  WgSizes[1] := 1;
  WgSizes[2] := 1;
  glGetProgramiv(FProgramHandle, GL_COMPUTE_WORK_GROUP_SIZE, @WgSizes[0]);
  FWorkGroupSize := Vector3Cardinal(
    Max(1, WgSizes[0]),
    Max(1, WgSizes[1]),
    Max(1, WgSizes[2]));

  if ADesc.PushConstantSize > 0 then
    EnsurePushConstantCapacity(ADesc.PushConstantSize);
end;

procedure TOpenGLRHIComputePipeline.ReleaseDeviceResources;
begin
  if (OpenGLDevice <> nil) and OpenGLDevice.HasLiveGLContext then
  begin
    if FPushConstantUBO <> 0 then
      glDeleteBuffers(1, @FPushConstantUBO);
    if FProgramHandle <> 0 then
      glDeleteProgram(FProgramHandle);
  end;
  FPushConstantUBO := 0;
  FPushConstantCapacity := 0;
  FProgramHandle := 0;
end;

destructor TOpenGLRHIComputePipeline.Destroy;
begin
  inherited;
end;

{ ---------------------------------------------------------------------------- }
{ TOpenGLRHIQueryPool                                                          }
{ ---------------------------------------------------------------------------- }

function TOpenGLRHIQueryPool.OpenGLDevice: TOpenGLRHIDevice;
begin
  Result := Device as TOpenGLRHIDevice;
end;

constructor TOpenGLRHIQueryPool.Create(const ADevice: TOpenGLRHIDevice;
  const ADesc: TRHIQueryPoolDesc);
var
  Count, I: Cardinal;
begin
  inherited Create(ADevice, ADesc);
  Count := Max(Cardinal(1), ADesc.QueryCount);
  SetLength(FQueries, Count);
  SetLength(FActiveTargets, Count);
  SetLength(FQueryWritten, Count);
  SetLength(FSimulatedResults, Count);

  if (ADevice <> nil) and ADevice.HasLiveGLContext then
    glGenQueries(Count, @FQueries[0])
  else
    for I := 0 to Count - 1 do
      FQueries[I] := I + 1;
end;

procedure TOpenGLRHIQueryPool.ReleaseDeviceResources;
begin
  if (Length(FQueries) > 0) and (FQueries[0] <> 0) and
     (OpenGLDevice <> nil) and OpenGLDevice.HasLiveGLContext then
    glDeleteQueries(Length(FQueries), @FQueries[0]);
  SetLength(FQueries, 0);
  SetLength(FActiveTargets, 0);
  SetLength(FQueryWritten, 0);
  SetLength(FSimulatedResults, 0);
end;

destructor TOpenGLRHIQueryPool.Destroy;
begin
  inherited;
end;

function TOpenGLRHIQueryPool.GetResults(const FirstQuery, QueryCount: Cardinal;
  out Results: array of UInt64; const WaitForResults: Boolean): Boolean;
var
  I, Idx: Cardinal;
  Avail: TGLuint;
  {$ifndef OpenGLES}
  Val64: TGLuint64;
  {$endif}
  Val32: TGLuint;
begin
  Result := False;
  if QueryCount = 0 then
    Exit(True);
  if (FirstQuery + QueryCount > Cardinal(Length(FQueries))) or
     (Cardinal(Length(Results)) < QueryCount) then
    Exit(False);

  for I := 0 to QueryCount - 1 do
    if not FQueryWritten[FirstQuery + I] then
      Exit(False);

  if (OpenGLDevice = nil) or (not OpenGLDevice.HasLiveGLContext) then
  begin
    for I := 0 to QueryCount - 1 do
      Results[I] := FSimulatedResults[FirstQuery + I];
    Exit(True);
  end;

  if not WaitForResults then
  begin
    for I := 0 to QueryCount - 1 do
    begin
      Idx := FirstQuery + I;
      Avail := 0;
      glGetQueryObjectuiv(FQueries[Idx], GL_QUERY_RESULT_AVAILABLE, @Avail);
      if Avail = GL_FALSE then
        Exit(False);
    end;
  end;

  for I := 0 to QueryCount - 1 do
  begin
    Idx := FirstQuery + I;
    {$ifndef OpenGLES}
    if Assigned(glGetQueryObjectui64v) then
    begin
      Val64 := 0;
      glGetQueryObjectui64v(FQueries[Idx], GL_QUERY_RESULT, @Val64);
      Results[I] := UInt64(Val64);
      Continue;
    end;
    {$endif}
    Val32 := 0;
    glGetQueryObjectuiv(FQueries[Idx], GL_QUERY_RESULT, @Val32);
    Results[I] := UInt64(Val32);
  end;
  Result := True;
end;

{$endif read_implementation}
