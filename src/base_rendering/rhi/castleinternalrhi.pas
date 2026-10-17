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

{ Abstract Render Hardware Interface (RHI) for Castle Game Engine.
  Provides an explicit, low-overhead rendering abstraction capable of driving
  both modern explicit APIs (Vulkan) and state-machine APIs (OpenGL / OpenGLES). }
unit CastleInternalRHI;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Generics.Collections,
  CastleVectors, CastleColors, CastleRectangles, CastleImages, CastleRenderOptions;

type
  { Forward declarations }
  TRHIDevice = class;
  TRHIBuffer = class;
  TRHITexture = class;
  TRHISampler = class;
  TRHIShaderModule = class;
  TRHIDescriptorSetLayout = class;
  TRHIDescriptorSet = class;
  TRHIPipeline = class;
  TRHIComputePipeline = class;
  TRHIQueryPool = class;
  TRHICommandList = class;

  { Exceptions }
  ERHIError = class(Exception);
  ERHIOutOfMemory = class(ERHIError);
  ERHIShaderCompilationError = class(ERHIError);

  { -------------------------------------------------------------------------- }
  { Fundamental Enums & Types                                                  }
  { -------------------------------------------------------------------------- }

  TRHIBackendType = (
    rbOpenGL,
    rbOpenGLES,
    rbVulkan
  );

  { Memory residency and CPU/GPU access patterns }
  TRHIMemoryUsage = (
    { GPU-only memory (VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT).
      Fastest for rendering; requires a staging buffer upload. }
    muGpuOnly,
    { CPU-writable, GPU-readable (HOST_VISIBLE | HOST_COHERENT).
      Ideal for per-frame dynamic UBOs, streaming vertices, and UI batches. }
    muCpuToGpu,
    { GPU-writable, CPU-readable. Used for screenshots / framebuffer readbacks. }
    muGpuToCpu
  );

  TRHIBufferUsage = (
    buVertex,
    buIndex,
    buUniform,
    buStorage,
    buIndirect,
    buTransferSrc,
    buTransferDst
  );
  TRHIBufferUsageFlags = set of TRHIBufferUsage;

  TRHIIndexType = (
    itUInt16,
    itUInt32
  );

  TRHIPixelFormat = (
    pfUndefined,
    { 8-bit normalized }
    pfR8_UNorm,
    pfRG8_UNorm,
    pfRGBA8_UNorm,
    pfRGBA8_sRGB,
    pfBGRA8_UNorm,
    pfBGRA8_sRGB,
    { 16-bit / 32-bit float (HDR & Data) }
    pfRG16_Float,
    pfRGBA16_Float,
    pfR32_Float,
    pfRGBA32_Float,
    { Depth / Stencil }
    pfD16_UNorm,
    pfD24_UNorm_S8_UInt,
    pfD32_Float,
    pfD32_Float_S8_UInt,
    { Compressed formats (BC / ASTC / ETC2) }
    pfBC1_RGBA_UNorm,
    pfBC1_RGBA_sRGB,
    pfBC3_RGBA_UNorm,
    pfBC3_RGBA_sRGB,
    pfBC5_RG_UNorm,
    pfBC7_RGBA_UNorm,
    pfBC7_RGBA_sRGB,
    pfASTC_4x4_UNorm,
    pfASTC_4x4_sRGB,
    pfETC2_RGB8_UNorm,
    pfETC2_RGBA8_UNorm
  );

  TRHITextureDimension = (
    td2D,
    td2DArray,
    td3D,
    tdCube,
    tdCubeArray
  );

  TRHITextureUsage = (
    tuSampled,            // Sampled in shaders
    tuColorAttachment,    // Render target color attachment
    tuDepthStencil,       // Render target depth/stencil attachment
    tuStorage,            // Compute shader image load/store
    tuTransferSrc,        // Blit / readback source
    tuTransferDst         // Upload / blit destination
  );
  TRHITextureUsageFlags = set of TRHITextureUsage;

  { Explicit resource states for Vulkan pipeline barriers (no-op in OpenGL) }
  TRHIResourceState = (
    rsUndefined,
    rsTransferDst,
    rsTransferSrc,
    rsShaderRead,
    rsColorAttachment,
    rsDepthStencilWrite,
    rsDepthStencilRead,
    rsPresent
  );

  TRHIShaderStage = (
    ssVertex,
    ssFragment,
    ssGeometry,
    ssCompute
  );
  TRHIShaderStageFlags = set of TRHIShaderStage;

  TRHIPrimitiveTopology = (
    ptTriangleList,
    ptTriangleStrip,
    ptLineList,
    ptLineStrip,
    ptPointList
  );

  TRHIPolygonMode = (
    pmFill,
    pmLine,
    pmPoint
  );

  TRHICullMode = (
    cmNone,
    cmBack,
    cmFront
  );

  TRHIFrontFace = (
    ffCounterClockwise,
    ffClockwise
  );

  TRHICompareOp = (
    coNever,
    coLess,
    coEqual,
    coLessOrEqual,
    coGreater,
    coNotEqual,
    coGreaterOrEqual,
    coAlways
  );

  TRHIBlendFactor = (
    bfZero,
    bfOne,
    bfSrcColor,
    bfOneMinusSrcColor,
    bfDstColor,
    bfOneMinusDstColor,
    bfSrcAlpha,
    bfOneMinusSrcAlpha,
    bfDstAlpha,
    bfOneMinusDstAlpha
  );

  TRHIBlendOp = (
    boAdd,
    boSubtract,
    boReverseSubtract,
    boMin,
    boMax
  );

  TRHISamplerFilter = (
    sfNearest,
    sfLinear
  );

  TRHISamplerAddressMode = (
    amRepeat,
    amMirroredRepeat,
    amClampToEdge,
    amClampToBorder
  );

  TRHIAttachmentLoadOp = (
    loLoad,
    loClear,
    loDontCare
  );

  TRHIAttachmentStoreOp = (
    soStore,
    soDontCare
  );

  { Multisample attachment resolve mode (VK_RESOLVE_MODE_*_BIT) }
  TRHIResolveMode = (
    rmNone,
    rmAverage,
    rmSampleZero,
    rmMin,
    rmMax
  );

  { Hardware query pool type (VK_QUERY_TYPE_OCCLUSION / VK_QUERY_TYPE_TIMESTAMP) }
  TRHIQueryType = (
    qtOcclusion,
    qtTimestamp
  );

  TRHIVertexAttributeFormat = (
    vafFloat,
    vafVector2,
    vafVector3,
    vafVector4,
    vafByte4Normalized,
    vafUByte4Normalized,
    vafShort2,
    vafShort4,
    vafUInt4
  );

  TRHICommandListLevel = (
    cllPrimary,
    cllSecondary
  );

  { Indirect draw command matching standard GPU layout (VkDrawIndirectCommand, OpenGL DrawArraysIndirect). }
  TRHIDrawIndirectCommand = record
    VertexCount: Cardinal;
    InstanceCount: Cardinal;
    FirstVertex: Cardinal;
    FirstInstance: Cardinal;
  end;
  PRHIDrawIndirectCommand = ^TRHIDrawIndirectCommand;

  { Indirect indexed draw command matching standard GPU layout (VkDrawIndexedIndirectCommand, OpenGL DrawElementsIndirect). }
  TRHIDrawIndexedIndirectCommand = record
    IndexCount: Cardinal;
    InstanceCount: Cardinal;
    FirstIndex: Cardinal;
    VertexOffset: Integer;
    FirstInstance: Cardinal;
  end;
  PRHIDrawIndexedIndirectCommand = ^TRHIDrawIndexedIndirectCommand;

  { Indirect compute dispatch command matching standard GPU layout (VkDispatchIndirectCommand). }
  TRHIDispatchIndirectCommand = record
    GroupCountX: Cardinal;
    GroupCountY: Cardinal;
    GroupCountZ: Cardinal;
  end;
  PRHIDispatchIndirectCommand = ^TRHIDispatchIndirectCommand;

  TRHIBufferDesc = record
    Size: PtrUInt;
    Usage: TRHIBufferUsageFlags;
    MemoryUsage: TRHIMemoryUsage;
    DebugName: String;
    class function Create(const ASize: PtrUInt;
      const AUsage: TRHIBufferUsageFlags;
      const AMemoryUsage: TRHIMemoryUsage = muGpuOnly;
      const ADebugName: String = ''): TRHIBufferDesc; static;
  end;

  TRHITextureDesc = record
    Dimension: TRHITextureDimension;
    Width: Cardinal;
    Height: Cardinal;
    DepthOrArrayLayers: Cardinal;
    MipLevels: Cardinal;
    SampleCount: Cardinal;
    Format: TRHIPixelFormat;
    Usage: TRHITextureUsageFlags;
    DebugName: String;
    class function Create2D(const AWidth, AHeight: Cardinal;
      const AFormat: TRHIPixelFormat;
      const AUsage: TRHITextureUsageFlags = [tuSampled, tuTransferDst];
      const AMipLevels: Cardinal = 1;
      const ASampleCount: Cardinal = 1): TRHITextureDesc; static;
    class function CreateCube(const ASize: Cardinal;
      const AFormat: TRHIPixelFormat;
      const AUsage: TRHITextureUsageFlags = [tuSampled, tuTransferDst];
      const AMipLevels: Cardinal = 1): TRHITextureDesc; static;
  end;

  TRHISamplerDesc = record
    MinFilter: TRHISamplerFilter;
    MagFilter: TRHISamplerFilter;
    MipFilter: TRHISamplerFilter;
    AddressModeU: TRHISamplerAddressMode;
    AddressModeV: TRHISamplerAddressMode;
    AddressModeW: TRHISamplerAddressMode;
    MaxAnisotropy: Single;
    CompareEnable: Boolean;
    CompareOp: TRHICompareOp;
    MinLod: Single;
    MaxLod: Single;
  end;

  { Vertex Input Layout }

  TRHIVertexBindingDesc = record
    Binding: Cardinal;
    Stride: Cardinal;
    PerInstance: Boolean;
  end;

  TRHIVertexAttributeDesc = record
    Location: Cardinal;
    Binding: Cardinal;
    Format: TRHIVertexAttributeFormat;
    Offset: Cardinal;
    { Attribute name for OpenGL 2/3 fallback binding if layout(location) is absent }
    AttributeName: String;
  end;

  TRHIVertexInputDesc = record
    Bindings: array of TRHIVertexBindingDesc;
    Attributes: array of TRHIVertexAttributeDesc;
  end;

  { Descriptor Set Layout }

  TRHIDescriptorType = (
    dtUniformBuffer,
    dtUniformBufferDynamic,
    dtStorageBuffer,
    dtCombinedImageSampler,
    dtSampledImage,
    dtSampler,
    dtStorageImage
  );

  { Optional descriptor binding flags for Vulkan 1.2 / VK_EXT_descriptor_indexing bindless arrays }
  TRHIDescriptorBindingFlag = (
    dbfPartiallyBound,
    dbfUpdateUnusedWhilePending,
    dbfUpdateAfterBind,
    dbfVariableDescriptorCount
  );
  TRHIDescriptorBindingFlags = set of TRHIDescriptorBindingFlag;

  TRHIDescriptorBindingDesc = record
    Binding: Cardinal;
    DescriptorType: TRHIDescriptorType;
    Count: Cardinal;
    StageFlags: TRHIShaderStageFlags;
    BindingFlags: TRHIDescriptorBindingFlags;
  end;

  { Graphics Pipeline State Object (PSO) Description }

  TRHIBlendStateDesc = record
    BlendEnable: Boolean;
    SrcColorBlendFactor: TRHIBlendFactor;
    DstColorBlendFactor: TRHIBlendFactor;
    ColorBlendOp: TRHIBlendOp;
    SrcAlphaBlendFactor: TRHIBlendFactor;
    DstAlphaBlendFactor: TRHIBlendFactor;
    AlphaBlendOp: TRHIBlendOp;
    ColorWriteMask: Byte; // Bitmask: R=1, G=2, B=4, A=8 ($0F = all)
    class function DefaultOpaque: TRHIBlendStateDesc; static;
    class function DefaultAlphaBlend: TRHIBlendStateDesc; static;
  end;

  TRHIRasterizerStateDesc = record
    PolygonMode: TRHIPolygonMode;
    CullMode: TRHICullMode;
    FrontFace: TRHIFrontFace;
    DepthBiasEnable: Boolean;
    DepthClampEnable: Boolean;
    class function DefaultCullBack: TRHIRasterizerStateDesc; static;
  end;

  TRHIDepthStencilStateDesc = record
    DepthTestEnable: Boolean;
    DepthWriteEnable: Boolean;
    DepthCompareOp: TRHICompareOp;
    StencilTestEnable: Boolean;
    class function DefaultDepthTestWrite: TRHIDepthStencilStateDesc; static;
    class function DefaultDepthReadOnly: TRHIDepthStencilStateDesc; static;
    class function DefaultDisabled: TRHIDepthStencilStateDesc; static;
    class function DefaultShadowMap: TRHIDepthStencilStateDesc; static;
  end;

  TRHIGraphicsPipelineDesc = record
    VertexShader: TRHIShaderModule;
    FragmentShader: TRHIShaderModule;
    GeometryShader: TRHIShaderModule; // Optional (nil if unused)
    VertexInput: TRHIVertexInputDesc;
    Topology: TRHIPrimitiveTopology;
    Rasterizer: TRHIRasterizerStateDesc;
    DepthStencil: TRHIDepthStencilStateDesc;
    BlendState: TRHIBlendStateDesc;
    { Descriptor Set Layouts (Set 0 = Global/Pass, Set 1 = Material, Set 2 = Object) }
    DescriptorSetLayouts: array of TRHIDescriptorSetLayout;
    PushConstantSize: Cardinal;
    PushConstantStages: TRHIShaderStageFlags;
    { Attachment formats for Vulkan 1.3 Dynamic Rendering }
    ColorAttachmentFormats: array of TRHIPixelFormat;
    DepthAttachmentFormat: TRHIPixelFormat;
    SampleCount: Cardinal;
    DebugName: String;
  end;

  { Compute Pipeline State Object (PSO) Description }
  TRHIComputePipelineDesc = record
    ComputeShader: TRHIShaderModule;
    DescriptorSetLayouts: array of TRHIDescriptorSetLayout;
    PushConstantSize: Cardinal;
    PushConstantStages: TRHIShaderStageFlags;
    DebugName: String;
  end;

  { Hardware Query Pool Description (Timestamp / Occlusion Queries) }
  TRHIQueryPoolDesc = record
    QueryType: TRHIQueryType;
    QueryCount: Cardinal;
    DebugName: String;
    class function Create(const AQueryType: TRHIQueryType;
      const AQueryCount: Cardinal;
      const ADebugName: String = ''): TRHIQueryPoolDesc; static;
  end;

  { Dynamic Rendering Pass Attachments (Vulkan VK_KHR_dynamic_rendering) }

  TRHIRenderingAttachment = record
    Texture: TRHITexture;
    MipLevel: Cardinal;
    ArrayLayer: Cardinal;
    LoadOp: TRHIAttachmentLoadOp;
    StoreOp: TRHIAttachmentStoreOp;
    ClearColor: TCastleColor;
    ClearDepth: Single;
    ClearStencil: Byte;
    { Single-pass MSAA resolve target (1x SampleCount texture) and mode.
      When ResolveTexture <> nil and Texture.Desc.SampleCount > 1, the GPU resolves
      the multisampled attachment into ResolveTexture at the end of the pass. }
    ResolveTexture: TRHITexture;
    ResolveMipLevel: Cardinal;
    ResolveArrayLayer: Cardinal;
    ResolveMode: TRHIResolveMode;
  end;

  TRHIRenderingInfo = record
    RenderArea: TRectangle;
    ColorAttachments: array of TRHIRenderingAttachment;
    HasDepthAttachment: Boolean;
    DepthAttachment: TRHIRenderingAttachment;
    class function CreateColorDepth(const ARenderArea: TRectangle;
      const AColorTexture: TRHITexture; const AColorLoadOp: TRHIAttachmentLoadOp;
      const AClearColor: TCastleColor; const ADepthTexture: TRHITexture;
      const ADepthLoadOp: TRHIAttachmentLoadOp; const AClearDepth: Single = 1.0): TRHIRenderingInfo; static;
    class function CreateColorDepthMSAA(const ARenderArea: TRectangle;
      const AMSAAColorTexture, AResolveColorTexture: TRHITexture;
      const AColorLoadOp: TRHIAttachmentLoadOp; const AClearColor: TCastleColor;
      const AMSAADepthTexture: TRHITexture; const ADepthLoadOp: TRHIAttachmentLoadOp;
      const AClearDepth: Single = 1.0;
      const AResolveDepthTexture: TRHITexture = nil): TRHIRenderingInfo; static;
    class function CreateDepthOnly(const ARenderArea: TRectangle;
      const ADepthTexture: TRHITexture; const ADepthLoadOp: TRHIAttachmentLoadOp;
      const ADepthStoreOp: TRHIAttachmentStoreOp = soStore;
      const AClearDepth: Single = 1.0): TRHIRenderingInfo; static;
  end;

  { Device Capabilities & Limits }

  TRHIDeviceCapabilities = record
    Backend: TRHIBackendType;
    DeviceName: String;
    VendorId: Cardinal;
    MaxTextureSize: Cardinal;
    MaxAnisotropy: Single;
    MaxUniformBufferRange: Cardinal;
    MinUniformBufferOffsetAlignment: Cardinal;
    MaxPushConstantsSize: Cardinal;
    MaxFramebufferSampleCount: Cardinal;
    SupportsBCCompression: Boolean;
    SupportsASTCCompression: Boolean;
    SupportsETC2Compression: Boolean;
    SupportsComputeShaders: Boolean;
    SupportsMultiDrawIndirect: Boolean;
    SupportsBindlessTextures: Boolean;
    MaxBindlessTextures: Cardinal;
    SupportsExtendedDynamicState: Boolean;
    SupportsSynchronization2: Boolean;
    SupportsTimelineSemaphores: Boolean;
    TimestampPeriodNanoseconds: Single;
  end;

  { -------------------------------------------------------------------------- }
  { Resource Classes                                                           }
  { -------------------------------------------------------------------------- }

  { Base class for all GPU resources owned by a TRHIDevice. }
  TRHIResource = class abstract
  private
    FDevice: TRHIDevice;
    FDebugName: String;
  public
    constructor Create(const ADevice: TRHIDevice; const ADebugName: String = '');
    property Device: TRHIDevice read FDevice;
    property DebugName: String read FDebugName;
  end;

  { GPU Buffer (Vertex, Index, Uniform, Storage, or Staging). }
  TRHIBuffer = class abstract(TRHIResource)
  protected
    FDesc: TRHIBufferDesc;
  public
    constructor Create(const ADevice: TRHIDevice; const ADesc: TRHIBufferDesc);
    { Maps CPU-visible memory (muCpuToGpu or muGpuToCpu). }
    function Map: Pointer; virtual; abstract;
    procedure Unmap; virtual; abstract;
    { Convenience helper to upload data. Uses staging buffer if muGpuOnly. }
    procedure UploadData(const Data; const Size: PtrUInt; const Offset: PtrUInt = 0); virtual; abstract;
    property Desc: TRHIBufferDesc read FDesc;
  end;

  { GPU Texture (2D, 3D, Cube, Array, Render Target). }
  TRHITexture = class abstract(TRHIResource)
  protected
    FDesc: TRHITextureDesc;
    FCurrentState: TRHIResourceState;
  public
    constructor Create(const ADevice: TRHIDevice; const ADesc: TRHITextureDesc);
    { Uploads a TEncodedImage (TCastleImage or TGPUCompressedImage) into a mip/layer. }
    procedure UploadImage(const AImage: TEncodedImage;
      const AMipLevel: Cardinal = 0; const AArrayLayer: Cardinal = 0); virtual; abstract;
    property Desc: TRHITextureDesc read FDesc;
    property CurrentState: TRHIResourceState read FCurrentState write FCurrentState;
  end;

  { Immutable texture sampler state. }
  TRHISampler = class abstract(TRHIResource)
  protected
    FDesc: TRHISamplerDesc;
  public
    constructor Create(const ADevice: TRHIDevice; const ADesc: TRHISamplerDesc);
    property Desc: TRHISamplerDesc read FDesc;
  end;

  { Compiled shader stage (SPIR-V module on Vulkan, GLuint shader on OpenGL). }
  TRHIShaderModule = class abstract(TRHIResource)
  protected
    FStage: TRHIShaderStage;
  public
    constructor Create(const ADevice: TRHIDevice; const AStage: TRHIShaderStage;
      const ADebugName: String = '');
    property Stage: TRHIShaderStage read FStage;
  end;

  { Layout schema for a Descriptor Set (Set 0, Set 1, etc.). }
  TRHIDescriptorSetLayout = class abstract(TRHIResource)
  end;

  { Bound collection of UBOs, SSBOs, and Combined Image Samplers. }
  TRHIDescriptorSet = class abstract(TRHIResource)
  public
    procedure BindUniformBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); virtual; abstract;
    procedure BindStorageBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); virtual; abstract;
    procedure BindTexture(const Binding: Cardinal; const Texture: TRHITexture;
      const Sampler: TRHISampler); virtual; abstract;
    { Binds a combined image sampler into a specific descriptor array element
      (e.g. for Vulkan 1.2 / VK_EXT_descriptor_indexing bindless texture arrays). }
    procedure BindTextureAtIndex(const Binding, ArrayElement: Cardinal;
      const Texture: TRHITexture; const Sampler: TRHISampler); virtual;
    { Commits pending binding updates to the underlying descriptor set. }
    procedure Update; virtual; abstract;
  end;

  { Baked Graphics Pipeline State Object (PSO). }
  TRHIPipeline = class abstract(TRHIResource)
  protected
    FDesc: TRHIGraphicsPipelineDesc;
  public
    constructor Create(const ADevice: TRHIDevice; const ADesc: TRHIGraphicsPipelineDesc);
    property Desc: TRHIGraphicsPipelineDesc read FDesc;
  end;

  { Baked Compute Pipeline State Object (PSO). }
  TRHIComputePipeline = class abstract(TRHIResource)
  protected
    FDesc: TRHIComputePipelineDesc;
  public
    constructor Create(const ADevice: TRHIDevice; const ADesc: TRHIComputePipelineDesc);
    property Desc: TRHIComputePipelineDesc read FDesc;
  end;

  { Hardware Query Pool (GPU Timestamps and Occlusion Queries). }
  TRHIQueryPool = class abstract(TRHIResource)
  protected
    FDesc: TRHIQueryPoolDesc;
  public
    constructor Create(const ADevice: TRHIDevice; const ADesc: TRHIQueryPoolDesc);
    { Reads back 64-bit query results for [FirstQuery .. FirstQuery + QueryCount - 1].
      Returns True if all requested queries have completed and Results is populated. }
    function GetResults(const FirstQuery, QueryCount: Cardinal;
      out Results: array of UInt64; const WaitForResults: Boolean = False): Boolean; virtual; abstract;
    property Desc: TRHIQueryPoolDesc read FDesc;
  end;

  { -------------------------------------------------------------------------- }
  { Command List (Command Buffer Recording)                                    }
  { -------------------------------------------------------------------------- }

  { Records rendering, compute, and transfer commands for execution on the GPU.
    In Vulkan, wraps VkCommandBuffer. In OpenGL, executes immediately or via a lightweight queue. }
  TRHICommandList = class abstract
  protected
    FLevel: TRHICommandListLevel;
  public
    constructor Create(const ALevel: TRHICommandListLevel = cllPrimary);
    property Level: TRHICommandListLevel read FLevel;

    procedure BeginRecording; virtual; abstract;
    procedure EndRecording; virtual; abstract;

    { Resource Barriers & Transitions }
    procedure TransitionTexture(const Texture: TRHITexture;
      const NewState: TRHIResourceState); virtual; abstract;
    procedure GenerateMipmaps(const Texture: TRHITexture); virtual; abstract;

    { Dynamic Rendering Pass Delimiters }
    procedure BeginRendering(const Info: TRHIRenderingInfo); virtual; abstract;
    procedure EndRendering; virtual; abstract;

    { Dynamic Viewport & Scissor State }
    procedure SetViewport(const ViewportRect: TFloatRectangle;
      const MinDepth: Single = 0.0; const MaxDepth: Single = 1.0); virtual; abstract;
    procedure SetScissor(const ScissorRect: TRectangle); virtual; abstract;
    procedure SetDepthBias(const ConstantFactor, SlopeFactor: Single); virtual; abstract;

    { Extended Dynamic State (VK_EXT_extended_dynamic_state / Vulkan 1.3 Core) }
    procedure SetCullMode(const CullMode: TRHICullMode); virtual;
    procedure SetFrontFace(const FrontFace: TRHIFrontFace); virtual;
    procedure SetDepthTestEnable(const Enable: Boolean); virtual;
    procedure SetDepthWriteEnable(const Enable: Boolean); virtual;
    procedure SetDepthCompareOp(const CompareOp: TRHICompareOp); virtual;
    procedure SetPrimitiveTopology(const Topology: TRHIPrimitiveTopology); virtual;

    { Pipeline & Resource Binding }
    procedure BindPipeline(const Pipeline: TRHIPipeline); virtual; abstract;
    procedure BindDescriptorSet(const SetIndex: Cardinal;
      const DescriptorSet: TRHIDescriptorSet;
      const DynamicOffsets: array of Cardinal); virtual; abstract;
    procedure PushConstants(const StageFlags: TRHIShaderStageFlags;
      const Offset, Size: Cardinal; const Data); virtual; abstract;

    { Compute Pipeline & Dispatch (Phase 6.5) }
    procedure BindComputePipeline(const Pipeline: TRHIComputePipeline); virtual;
    procedure BindComputeDescriptorSet(const SetIndex: Cardinal;
      const DescriptorSet: TRHIDescriptorSet;
      const DynamicOffsets: array of Cardinal); virtual;
    procedure Dispatch(const GroupCountX, GroupCountY, GroupCountZ: Cardinal); reintroduce; virtual;
    procedure DispatchIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt = 0); virtual;

    { Hardware Queries (Timestamps & Occlusion Queries - Phase 6.7) }
    procedure ResetQueryPool(const QueryPool: TRHIQueryPool;
      const FirstQuery, QueryCount: Cardinal); virtual;
    procedure BeginQuery(const QueryPool: TRHIQueryPool;
      const QueryIndex: Cardinal; const Precise: Boolean = False); virtual;
    procedure EndQuery(const QueryPool: TRHIQueryPool;
      const QueryIndex: Cardinal); virtual;
    procedure WriteTimestamp(const QueryPool: TRHIQueryPool;
      const QueryIndex: Cardinal; const Stage: TRHIShaderStage = ssFragment); virtual;

    { Geometry Buffers }
    procedure BindVertexBuffers(const FirstBinding: Cardinal;
      const Buffers: array of TRHIBuffer;
      const Offsets: array of PtrUInt); virtual; abstract;
    procedure BindIndexBuffer(const Buffer: TRHIBuffer;
      const Offset: PtrUInt; const IndexType: TRHIIndexType); virtual; abstract;

    { Draw Calls }
    procedure Draw(const VertexCount, InstanceCount, FirstVertex, FirstInstance: Cardinal); virtual; abstract;
    procedure DrawIndexed(const IndexCount, InstanceCount, FirstIndex: Cardinal;
      const VertexOffset: Integer; const FirstInstance: Cardinal); virtual; abstract;
    procedure DrawIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const DrawCount, Stride: Cardinal); virtual; abstract;
    procedure DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const DrawCount, Stride: Cardinal); virtual; abstract;

    { Secondary Command List Execution (Multi-threaded recording) }
    procedure ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList); virtual; abstract;

    { Debug Markers (RenderDoc / NSight integration) }
    procedure PushDebugGroup(const LabelName: String; const Color: TCastleColor); virtual; abstract;
    procedure PopDebugGroup; virtual; abstract;
  end;

  { -------------------------------------------------------------------------- }
  { Render Device (Factory & Frame Lifecycle)                                  }
  { -------------------------------------------------------------------------- }

  { Main entry point for the RHI backend. Manages GPU device lifecycles,
    swapchain presentation, frames-in-flight synchronization, and resource creation. }
  TRHIDevice = class abstract
  protected
    FCapabilities: TRHIDeviceCapabilities;
    FFrameIndex: Cardinal;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    { Frame Lifecycle & Swapchain }
    function BeginFrame: TRHICommandList; virtual; abstract;
    procedure EndFrameAndPresent; virtual; abstract;
    procedure ResizeSwapchain(const NewWidth, NewHeight: Cardinal); virtual; abstract;
    procedure WaitIdle; virtual; abstract;

    { Secondary Command List Allocation (for multi-threaded command recording) }
    function CreateSecondaryCommandList: TRHICommandList; virtual; abstract;

    { Returns the backbuffer color and depth targets for the current frame in flight }
    function GetSwapchainColorTexture: TRHITexture; virtual; abstract;
    function GetSwapchainDepthTexture: TRHITexture; virtual; abstract;

    { Resource Creation Factory Methods }
    function CreateBuffer(const ADesc: TRHIBufferDesc;
      const InitialData: Pointer = nil): TRHIBuffer; virtual; abstract;
    function CreateTexture(const ADesc: TRHITextureDesc): TRHITexture; virtual; abstract;
    function CreateSampler(const ADesc: TRHISamplerDesc): TRHISampler; virtual; abstract;

    { Compiles GLSL source (or loads cached SPIR-V) into a Shader Module. }
    function CreateShaderModuleFromGLSL(const AStage: TRHIShaderStage;
      const AGLSLSource: String; const ADebugName: String = ''): TRHIShaderModule; virtual; abstract;
    function CreateShaderModuleFromSPIRV(const AStage: TRHIShaderStage;
      const ASPIRVBinary: Pointer; const ASizeInBytes: PtrUInt;
      const ADebugName: String = ''): TRHIShaderModule; virtual; abstract;

    function CreateDescriptorSetLayout(
      const Bindings: array of TRHIDescriptorBindingDesc): TRHIDescriptorSetLayout; virtual; abstract;
    function CreateDescriptorSet(
      const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet; virtual; abstract;

    { Creates or retrieves a cached Pipeline State Object matching ADesc. }
    function GetOrCreatePipeline(const ADesc: TRHIGraphicsPipelineDesc): TRHIPipeline; virtual; abstract;

    { Creates or retrieves a cached Compute Pipeline State Object matching ADesc. }
    function CreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline; virtual;

    { Creates a hardware query pool for GPU timestamps or occlusion queries. }
    function CreateQueryPool(const ADesc: TRHIQueryPoolDesc): TRHIQueryPool; virtual;

    { Readback current swapchain or texture into a CPU TCastleImage (for TCastleWindow.SaveScreen). }
    function GrabTextureImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle): TRGBAlphaImage; virtual; abstract;

    { Pipeline Cache persistence (loads/saves VkPipelineCache to disk) }
    procedure LoadPipelineCache(const CacheFileUrl: String); virtual; abstract;
    procedure SavePipelineCache(const CacheFileUrl: String); virtual; abstract;

    property Capabilities: TRHIDeviceCapabilities read FCapabilities;
    { Current frame-in-flight index (0 .. MaxFramesInFlight - 1) }
    property FrameIndex: Cardinal read FFrameIndex;
  end;

const
  { Maximum number of frames simultaneously processed by CPU and GPU. }
  MaxFramesInFlight = 2;

{ Global active RHI device instance managed by CastleWindow / TCastleViewport. }
function RHIDevice: TRHIDevice;
procedure SetRHIDevice(const ADevice: TRHIDevice);

{ Global active RHI command list being recorded for current frame/pass. }
function ActiveCommandList: TRHICommandList;
procedure SetActiveCommandList(const ACmdList: TRHICommandList);

{ Converts TCastleWindow.AntiAliasing (TAntiAliasing) to an RHI MSAA sample count (1, 2, 4, 8, 16). }
function AntiAliasingToSampleCount(const AAntiAliasing: TAntiAliasing): Cardinal;

{ Clamps a requested MSAA sample count to the highest power-of-two sample count
  (1, 2, 4, 8, 16, 32, 64) supported by the device's MaxSupportedSamples. }
function ClampSampleCountToCapabilities(const ARequestedSamples, AMaxSupportedSamples: Cardinal): Cardinal;

{ Compares two framebuffer readback images (e.g. OpenGL vs Vulkan GrabTextureImage)
  by computing the normalized Root Mean Square Error (RMSE in [0..1]) across all channels.
  Returns True if dimensions/formats match and OutNormalizedRMSE <= MaxNormalizedRMSE. }
function CompareImagesPerceptualDiff(const ImageA, ImageB: TCastleImage;
  const MaxNormalizedRMSE: Single; out OutNormalizedRMSE: Single): Boolean;

implementation

var
  FRHIDevice: TRHIDevice = nil;
  FActiveCommandList: TRHICommandList = nil;

function RHIDevice: TRHIDevice;
begin
  Result := FRHIDevice;
end;

procedure SetRHIDevice(const ADevice: TRHIDevice);
begin
  FRHIDevice := ADevice;
end;

function ActiveCommandList: TRHICommandList;
begin
  Result := FActiveCommandList;
end;

procedure SetActiveCommandList(const ACmdList: TRHICommandList);
begin
  FActiveCommandList := ACmdList;
end;

function AntiAliasingToSampleCount(const AAntiAliasing: TAntiAliasing): Cardinal;
begin
  case AAntiAliasing of
    aaNone: Result := 1;
    aa2SamplesFaster, aa2SamplesNicer: Result := 2;
    aa4SamplesFaster, aa4SamplesNicer: Result := 4;
    aa8SamplesFaster, aa8SamplesNicer: Result := 8;
    aa16SamplesFaster, aa16SamplesNicer: Result := 16;
  else
    Result := 1;
  end;
end;

function ClampSampleCountToCapabilities(const ARequestedSamples, AMaxSupportedSamples: Cardinal): Cardinal;
var
  MaxAllowed: Cardinal;
begin
  if (ARequestedSamples <= 1) or (AMaxSupportedSamples <= 1) then
    Exit(1);
  MaxAllowed := ARequestedSamples;
  if MaxAllowed > AMaxSupportedSamples then
    MaxAllowed := AMaxSupportedSamples;
  if MaxAllowed >= 64 then Result := 64 else
  if MaxAllowed >= 32 then Result := 32 else
  if MaxAllowed >= 16 then Result := 16 else
  if MaxAllowed >= 8 then Result := 8 else
  if MaxAllowed >= 4 then Result := 4 else
  if MaxAllowed >= 2 then Result := 2 else
    Result := 1;
end;

function CompareImagesPerceptualDiff(const ImageA, ImageB: TCastleImage;
  const MaxNormalizedRMSE: Single; out OutNormalizedRMSE: Single): Boolean;
var
  TotalSamples, I: PtrUInt;
  PA, PB: PByte;
  Diff, SumSq: Double;
begin
  OutNormalizedRMSE := 1.0;
  if (ImageA = nil) or (ImageB = nil) or
     (ImageA.Width <> ImageB.Width) or
     (ImageA.Height <> ImageB.Height) or
     (ImageA.Depth <> ImageB.Depth) or
     (ImageA.PixelSize <> ImageB.PixelSize) then
    Exit(False);

  TotalSamples := PtrUInt(ImageA.Width) * PtrUInt(ImageA.Height) *
                  PtrUInt(ImageA.Depth) * PtrUInt(ImageA.PixelSize);
  if TotalSamples = 0 then
  begin
    OutNormalizedRMSE := 0.0;
    Exit(True);
  end;

  PA := PByte(ImageA.RawPixels);
  PB := PByte(ImageB.RawPixels);
  SumSq := 0.0;
  for I := 0 to TotalSamples - 1 do
  begin
    Diff := (Integer(PA[I]) - Integer(PB[I])) / 255.0;
    SumSq := SumSq + Diff * Diff;
  end;

  OutNormalizedRMSE := Sqrt(SumSq / TotalSamples);
  Result := OutNormalizedRMSE <= MaxNormalizedRMSE;
end;

{ TRHIBufferDesc }

class function TRHIBufferDesc.Create(const ASize: PtrUInt;
  const AUsage: TRHIBufferUsageFlags;
  const AMemoryUsage: TRHIMemoryUsage;
  const ADebugName: String): TRHIBufferDesc;
begin
  Result.Size := ASize;
  Result.Usage := AUsage;
  Result.MemoryUsage := AMemoryUsage;
  Result.DebugName := ADebugName;
end;

{ TRHITextureDesc }

class function TRHITextureDesc.Create2D(const AWidth, AHeight: Cardinal;
  const AFormat: TRHIPixelFormat; const AUsage: TRHITextureUsageFlags;
  const AMipLevels: Cardinal; const ASampleCount: Cardinal): TRHITextureDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Dimension := td2D;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.DepthOrArrayLayers := 1;
  Result.MipLevels := AMipLevels;
  if ASampleCount > 1 then
    Result.SampleCount := ASampleCount
  else
    Result.SampleCount := 1;
  Result.Format := AFormat;
  Result.Usage := AUsage;
end;

class function TRHITextureDesc.CreateCube(const ASize: Cardinal;
  const AFormat: TRHIPixelFormat; const AUsage: TRHITextureUsageFlags;
  const AMipLevels: Cardinal): TRHITextureDesc;
begin
  Result := Create2D(ASize, ASize, AFormat, AUsage, AMipLevels, 1);
  Result.Dimension := tdCube;
  Result.DepthOrArrayLayers := 6;
end;

{ TRHIQueryPoolDesc }

class function TRHIQueryPoolDesc.Create(const AQueryType: TRHIQueryType;
  const AQueryCount: Cardinal; const ADebugName: String): TRHIQueryPoolDesc;
begin
  Result.QueryType := AQueryType;
  Result.QueryCount := AQueryCount;
  Result.DebugName := ADebugName;
end;

{ TRHIBlendStateDesc }

class function TRHIBlendStateDesc.DefaultOpaque: TRHIBlendStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.BlendEnable := False;
  Result.SrcColorBlendFactor := bfOne;
  Result.DstColorBlendFactor := bfZero;
  Result.ColorBlendOp := boAdd;
  Result.SrcAlphaBlendFactor := bfOne;
  Result.DstAlphaBlendFactor := bfZero;
  Result.AlphaBlendOp := boAdd;
  Result.ColorWriteMask := $0F;
end;

class function TRHIBlendStateDesc.DefaultAlphaBlend: TRHIBlendStateDesc;
begin
  Result := DefaultOpaque;
  Result.BlendEnable := True;
  Result.SrcColorBlendFactor := bfSrcAlpha;
  Result.DstColorBlendFactor := bfOneMinusSrcAlpha;
  Result.SrcAlphaBlendFactor := bfOne;
  Result.DstAlphaBlendFactor := bfOneMinusSrcAlpha;
end;

{ TRHIRasterizerStateDesc }

class function TRHIRasterizerStateDesc.DefaultCullBack: TRHIRasterizerStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.PolygonMode := pmFill;
  Result.CullMode := cmBack;
  Result.FrontFace := ffCounterClockwise;
  Result.DepthBiasEnable := False;
  Result.DepthClampEnable := False;
end;

{ TRHIDepthStencilStateDesc }

class function TRHIDepthStencilStateDesc.DefaultDepthTestWrite: TRHIDepthStencilStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.DepthTestEnable := True;
  Result.DepthWriteEnable := True;
  Result.DepthCompareOp := coLessOrEqual;
  Result.StencilTestEnable := False;
end;

class function TRHIDepthStencilStateDesc.DefaultDepthReadOnly: TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthTestWrite;
  Result.DepthWriteEnable := False;
end;

class function TRHIDepthStencilStateDesc.DefaultDisabled: TRHIDepthStencilStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.DepthTestEnable := False;
  Result.DepthWriteEnable := False;
  Result.DepthCompareOp := coAlways;
  Result.StencilTestEnable := False;
end;

class function TRHIDepthStencilStateDesc.DefaultShadowMap: TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthTestWrite;
end;

{ TRHIRenderingInfo }

class function TRHIRenderingInfo.CreateColorDepth(const ARenderArea: TRectangle;
  const AColorTexture: TRHITexture; const AColorLoadOp: TRHIAttachmentLoadOp;
  const AClearColor: TCastleColor; const ADepthTexture: TRHITexture;
  const ADepthLoadOp: TRHIAttachmentLoadOp; const AClearDepth: Single): TRHIRenderingInfo;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RenderArea := ARenderArea;
  if AColorTexture <> nil then
  begin
    SetLength(Result.ColorAttachments, 1);
    Result.ColorAttachments[0].Texture := AColorTexture;
    Result.ColorAttachments[0].LoadOp := AColorLoadOp;
    Result.ColorAttachments[0].StoreOp := soStore;
    Result.ColorAttachments[0].ClearColor := AClearColor;
  end;
  if ADepthTexture <> nil then
  begin
    Result.HasDepthAttachment := True;
    Result.DepthAttachment.Texture := ADepthTexture;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    Result.DepthAttachment.StoreOp := soStore;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end;
end;

class function TRHIRenderingInfo.CreateColorDepthMSAA(const ARenderArea: TRectangle;
  const AMSAAColorTexture, AResolveColorTexture: TRHITexture;
  const AColorLoadOp: TRHIAttachmentLoadOp; const AClearColor: TCastleColor;
  const AMSAADepthTexture: TRHITexture; const ADepthLoadOp: TRHIAttachmentLoadOp;
  const AClearDepth: Single;
  const AResolveDepthTexture: TRHITexture): TRHIRenderingInfo;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RenderArea := ARenderArea;
  if AMSAAColorTexture <> nil then
  begin
    SetLength(Result.ColorAttachments, 1);
    Result.ColorAttachments[0].Texture := AMSAAColorTexture;
    Result.ColorAttachments[0].LoadOp := AColorLoadOp;
    { When resolving in a single tile-local pass, transient MSAA samples do not need
      to be written back to external memory after resolving into AResolveColorTexture. }
    if AResolveColorTexture <> nil then
    begin
      Result.ColorAttachments[0].StoreOp := soDontCare;
      Result.ColorAttachments[0].ResolveTexture := AResolveColorTexture;
      Result.ColorAttachments[0].ResolveMode := rmAverage;
    end else
      Result.ColorAttachments[0].StoreOp := soStore;
    Result.ColorAttachments[0].ClearColor := AClearColor;
  end;
  if AMSAADepthTexture <> nil then
  begin
    Result.HasDepthAttachment := True;
    Result.DepthAttachment.Texture := AMSAADepthTexture;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    if AResolveDepthTexture <> nil then
    begin
      Result.DepthAttachment.StoreOp := soDontCare;
      Result.DepthAttachment.ResolveTexture := AResolveDepthTexture;
      Result.DepthAttachment.ResolveMode := rmSampleZero;
    end else
      Result.DepthAttachment.StoreOp := soDontCare;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end;
end;

class function TRHIRenderingInfo.CreateDepthOnly(const ARenderArea: TRectangle;
  const ADepthTexture: TRHITexture; const ADepthLoadOp: TRHIAttachmentLoadOp;
  const ADepthStoreOp: TRHIAttachmentStoreOp;
  const AClearDepth: Single): TRHIRenderingInfo;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RenderArea := ARenderArea;
  SetLength(Result.ColorAttachments, 0);
  Result.HasDepthAttachment := True;
  Result.DepthAttachment.Texture := ADepthTexture;
  Result.DepthAttachment.LoadOp := ADepthLoadOp;
  Result.DepthAttachment.StoreOp := ADepthStoreOp;
  Result.DepthAttachment.ClearDepth := AClearDepth;
end;

{ TRHIResource }

constructor TRHIResource.Create(const ADevice: TRHIDevice; const ADebugName: String);
begin
  inherited Create;
  FDevice := ADevice;
  FDebugName := ADebugName;
end;

{ TRHIBuffer }

constructor TRHIBuffer.Create(const ADevice: TRHIDevice; const ADesc: TRHIBufferDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
end;

{ TRHITexture }

constructor TRHITexture.Create(const ADevice: TRHIDevice; const ADesc: TRHITextureDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
  FCurrentState := rsUndefined;
end;

{ TRHISampler }

constructor TRHISampler.Create(const ADevice: TRHIDevice; const ADesc: TRHISamplerDesc);
begin
  inherited Create(ADevice, '');
  FDesc := ADesc;
end;

{ TRHIShaderModule }

constructor TRHIShaderModule.Create(const ADevice: TRHIDevice;
  const AStage: TRHIShaderStage; const ADebugName: String);
begin
  inherited Create(ADevice, ADebugName);
  FStage := AStage;
end;

{ TRHIDescriptorSet }

procedure TRHIDescriptorSet.BindTextureAtIndex(const Binding, ArrayElement: Cardinal;
  const Texture: TRHITexture; const Sampler: TRHISampler);
begin
  BindTexture(Binding, Texture, Sampler);
end;

{ TRHIPipeline }

constructor TRHIPipeline.Create(const ADevice: TRHIDevice; const ADesc: TRHIGraphicsPipelineDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
end;

{ TRHIComputePipeline }

constructor TRHIComputePipeline.Create(const ADevice: TRHIDevice; const ADesc: TRHIComputePipelineDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
end;

{ TRHIQueryPool }

constructor TRHIQueryPool.Create(const ADevice: TRHIDevice; const ADesc: TRHIQueryPoolDesc);
begin
  inherited Create(ADevice, ADesc.DebugName);
  FDesc := ADesc;
end;

{ TRHICommandList }

constructor TRHICommandList.Create(const ALevel: TRHICommandListLevel);
begin
  inherited Create;
  FLevel := ALevel;
end;

procedure TRHICommandList.SetCullMode(const CullMode: TRHICullMode);
begin
end;

procedure TRHICommandList.SetFrontFace(const FrontFace: TRHIFrontFace);
begin
end;

procedure TRHICommandList.SetDepthTestEnable(const Enable: Boolean);
begin
end;

procedure TRHICommandList.SetDepthWriteEnable(const Enable: Boolean);
begin
end;

procedure TRHICommandList.SetDepthCompareOp(const CompareOp: TRHICompareOp);
begin
end;

procedure TRHICommandList.SetPrimitiveTopology(const Topology: TRHIPrimitiveTopology);
begin
end;

procedure TRHICommandList.BindComputePipeline(const Pipeline: TRHIComputePipeline);
begin
end;

procedure TRHICommandList.BindComputeDescriptorSet(const SetIndex: Cardinal;
  const DescriptorSet: TRHIDescriptorSet;
  const DynamicOffsets: array of Cardinal);
begin
  BindDescriptorSet(SetIndex, DescriptorSet, DynamicOffsets);
end;

procedure TRHICommandList.Dispatch(const GroupCountX, GroupCountY, GroupCountZ: Cardinal);
begin
end;

procedure TRHICommandList.DispatchIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt);
begin
end;

procedure TRHICommandList.ResetQueryPool(const QueryPool: TRHIQueryPool;
  const FirstQuery, QueryCount: Cardinal);
begin
end;

procedure TRHICommandList.BeginQuery(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal; const Precise: Boolean);
begin
end;

procedure TRHICommandList.EndQuery(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal);
begin
end;

procedure TRHICommandList.WriteTimestamp(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal; const Stage: TRHIShaderStage);
begin
end;

{ TRHIDevice }

constructor TRHIDevice.Create;
begin
  inherited Create;
  FFrameIndex := 0;
end;

destructor TRHIDevice.Destroy;
begin
  if FRHIDevice = Self then
    FRHIDevice := nil;
  inherited;
end;

function TRHIDevice.CreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline;
begin
  Result := nil;
end;

function TRHIDevice.CreateQueryPool(const ADesc: TRHIQueryPoolDesc): TRHIQueryPool;
begin
  Result := nil;
end;

end.
