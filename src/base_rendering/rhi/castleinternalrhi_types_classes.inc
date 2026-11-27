{%MainUnit castleinternalrhi.pas}
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
  TRHIRenderGraphPass = class;
  TRHIRenderGraph = class;

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
    buTransferDst,
    buShaderDeviceAddress,
    buAccelerationStructureBuildInput,
    buAccelerationStructureStorage,
    buShaderBindingTable
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
    pfR16_Float,
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
    rsUnorderedAccess,
    rsIndirectRead,
    rsColorAttachment,
    rsDepthStencilWrite,
    rsDepthStencilRead,
    rsPresent
  );

  TRHIShaderStage = (
    ssVertex,
    ssFragment,
    ssGeometry,
    ssCompute,
    ssTask,
    ssMesh,
    ssRayGen,
    ssAnyHit,
    ssClosestHit,
    ssMiss,
    ssIntersection,
    ssCallable
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

  { Stencil buffer operation (VK_STENCIL_OP_* / GL_KEEP..GL_DECR_WRAP) }
  TRHIStencilOp = (
    soKeep,
    soZero,
    soReplace,
    soIncrementAndClamp,
    soDecrementAndClamp,
    soInvert,
    soIncrementAndWrap,
    soDecrementAndWrap
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
    bfOneMinusDstAlpha,
    bfConstantColor,
    bfOneMinusConstantColor,
    bfConstantAlpha,
    bfOneMinusConstantAlpha,
    bfSrcAlphaSaturate
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
    class function Create3D(const AWidth, AHeight, ADepth: Cardinal;
      const AFormat: TRHIPixelFormat;
      const AUsage: TRHITextureUsageFlags = [tuSampled, tuTransferDst];
      const AMipLevels: Cardinal = 1): TRHITextureDesc; static;
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
    dtStorageImage,
    dtAccelerationStructure
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
    DisableColorWrites: Boolean; // When True, forces colorWriteMask = 0 (e.g. stencil-only shadow volume pass)
    class function DefaultOpaque: TRHIBlendStateDesc; static;
    class function DefaultAlphaBlend: TRHIBlendStateDesc; static;
    class function DefaultColorMaskNone: TRHIBlendStateDesc; static;
  end;

  TRHIRasterizerStateDesc = record
    PolygonMode: TRHIPolygonMode;
    CullMode: TRHICullMode;
    FrontFace: TRHIFrontFace;
    DepthBiasEnable: Boolean;
    DepthClampEnable: Boolean;
    class function DefaultCullBack: TRHIRasterizerStateDesc; static;
  end;

  { Per-face stencil operation and comparison state (VkStencilOpState). }
  TRHIStencilOpStateDesc = record
    FailOp: TRHIStencilOp;
    PassOp: TRHIStencilOp;
    DepthFailOp: TRHIStencilOp;
    CompareOp: TRHICompareOp;
    CompareMask: Cardinal;
    WriteMask: Cardinal;
    Reference: Cardinal;
    class function DefaultKeep: TRHIStencilOpStateDesc; static;
  end;

  TRHIDepthStencilStateDesc = record
    DepthTestEnable: Boolean;
    DepthWriteEnable: Boolean;
    DepthCompareOp: TRHICompareOp;
    StencilTestEnable: Boolean;
    FrontStencil: TRHIStencilOpStateDesc;
    BackStencil: TRHIStencilOpStateDesc;
    class function DefaultDepthTestWrite: TRHIDepthStencilStateDesc; static;
    class function DefaultDepthReadOnly: TRHIDepthStencilStateDesc; static;
    class function DefaultDisabled: TRHIDepthStencilStateDesc; static;
    class function DefaultShadowMap: TRHIDepthStencilStateDesc; static;
    { Two-sided stencil shadow volume Z-Pass state:
      Front faces increment (wrap) on depth pass; back faces decrement (wrap) on depth pass. }
    class function DefaultStencilShadowVolumeZPass: TRHIDepthStencilStateDesc; static;
    { Two-sided stencil shadow volume Z-Fail (Carmack's Reverse) state:
      Front faces decrement (wrap) on depth fail; back faces increment (wrap) on depth fail. }
    class function DefaultStencilShadowVolumeZFail: TRHIDepthStencilStateDesc; static;
    { Stencil-masked lit scene pass state (renders only where stencil == AStencilReference). }
    class function DefaultStencilLitPass(const AStencilReference: Cardinal = 0;
      const ACompareMask: Cardinal = $FF): TRHIDepthStencilStateDesc; static;
  end;

  TRHIGraphicsPipelineDesc = record
    VertexShader: TRHIShaderModule;
    FragmentShader: TRHIShaderModule;
    GeometryShader: TRHIShaderModule; // Optional (nil if unused)
    TaskShader: TRHIShaderModule;     // Optional (VK_EXT_mesh_shader task stage)
    MeshShader: TRHIShaderModule;     // Optional (VK_EXT_mesh_shader mesh stage)
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
    ContentsSecondaryCommandBuffers: Boolean;
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
    SupportsDrawIndirectCount: Boolean;
    SupportsBindlessTextures: Boolean;
    MaxBindlessTextures: Cardinal;
    SupportsExtendedDynamicState: Boolean;
    SupportsSynchronization2: Boolean;
    SupportsTimelineSemaphores: Boolean;
    SupportsBufferDeviceAddress: Boolean;
    SupportsAccelerationStructure: Boolean;
    SupportsRayQuery: Boolean;
    SupportsRayTracingPipeline: Boolean;
    SupportsMeshShaders: Boolean;
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
    FUniqueId: QWord;
  protected
    { Releases backend GPU handles owned by this resource while FDevice is still live.
      Invoked either from Destroy or by TRHIDevice.ReleaseRemainingDeviceResources
      when a resource wrapper outlives its TRHIDevice. }
    procedure ReleaseDeviceResources; virtual;
  public
    constructor Create(const ADevice: TRHIDevice; const ADebugName: String = '');
    destructor Destroy; override;
    property Device: TRHIDevice read FDevice;
    property DebugName: String read FDebugName;
    property UniqueId: QWord read FUniqueId;
  end;

  { GPU Buffer (Vertex, Index, Uniform, Storage, Staging, AccelerationStructure, SBT). }
  TRHIBuffer = class abstract(TRHIResource)
  protected
    FDesc: TRHIBufferDesc;
    function GetDeviceAddress: UInt64; virtual;
  public
    constructor Create(const ADevice: TRHIDevice; const ADesc: TRHIBufferDesc);
    { Maps CPU-visible memory (muCpuToGpu or muGpuToCpu). }
    function Map: Pointer; virtual; abstract;
    procedure Unmap; virtual; abstract;
    { Convenience helper to upload data. Uses staging buffer if muGpuOnly. }
    procedure UploadData(const Data; const Size: PtrUInt; const Offset: PtrUInt = 0); virtual; abstract;
    property Desc: TRHIBufferDesc read FDesc;
    property DeviceAddress: UInt64 read GetDeviceAddress;
  end;

  { GPU Texture (2D, 3D, Cube, Array, Render Target). }
  TRHITexture = class abstract(TRHIResource)
  protected
    FDesc: TRHITextureDesc;
    FCurrentState: TRHIResourceState;
    FIsMemoryAliased: Boolean;
    FAliasedCarrierTexture: TRHITexture;
    function GetEstimatedByteSize: UInt64; virtual;
    function GetRenderedLayerMask: Cardinal; virtual;
  public
    constructor Create(const ADevice: TRHIDevice; const ADesc: TRHITextureDesc);
    { Uploads a TEncodedImage (TCastleImage or TGPUCompressedImage) into a mip/layer. }
    procedure UploadImage(const AImage: TEncodedImage;
      const AMipLevel: Cardinal = 0; const AArrayLayer: Cardinal = 0); virtual; abstract;
    { Generates the full mipmap chain from mip level 0 down to Desc.MipLevels - 1. }
    procedure GenerateMipmaps; virtual;
    class function EstimateDescriptorByteSize(const ADesc: TRHITextureDesc): UInt64; static;
    property Desc: TRHITextureDesc read FDesc;
    property CurrentState: TRHIResourceState read FCurrentState write FCurrentState;
    property IsMemoryAliased: Boolean read FIsMemoryAliased;
    property AliasedCarrierTexture: TRHITexture read FAliasedCarrierTexture;
    property EstimatedByteSize: UInt64 read GetEstimatedByteSize;
    property RenderedLayerMask: Cardinal read GetRenderedLayerMask;
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
    { Binds a specific 2D subresource slice (MipLevel, ArrayLayer) of a 2D, array, or cubemap texture. }
    procedure BindTextureSubresource(const Binding: Cardinal;
      const Texture: TRHITexture; const MipLevel, ArrayLayer: Cardinal;
      const Sampler: TRHISampler = nil); virtual;
    { Commits pending binding updates to the underlying descriptor set. }
    procedure Update; virtual; abstract;
  end;

  { Baked Graphics Pipeline State Object (PSO). }
  TRHIPipeline = class abstract(TRHIResource)
  protected
    FDesc: TRHIGraphicsPipelineDesc;
  public
    constructor Create(const ADevice: TRHIDevice; const ADesc: TRHIGraphicsPipelineDesc);
    procedure UpdateDynamicStateDesc(const ADesc: TRHIGraphicsPipelineDesc);
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
    FIsRendering: Boolean;
    FActiveRenderingInfo: TRHIRenderingInfo;
    FActiveRenderingHasColor: Boolean;
    FActiveRenderingColorFormat: TRHIPixelFormat;
    FActiveRenderingHasDepth: Boolean;
    FActiveRenderingDepthFormat: TRHIPixelFormat;
    FActiveRenderingSampleCount: Cardinal;
    FCurrentPassHasCommands: Boolean;
  public
    constructor Create(const ALevel: TRHICommandListLevel = cllPrimary);
    property Level: TRHICommandListLevel read FLevel;
    property IsRendering: Boolean read FIsRendering;
    property CurrentPassHasCommands: Boolean read FCurrentPassHasCommands;
    property ActiveRenderingInfo: TRHIRenderingInfo read FActiveRenderingInfo;
    property ActiveRenderingHasColor: Boolean read FActiveRenderingHasColor;
    property ActiveRenderingColorFormat: TRHIPixelFormat read FActiveRenderingColorFormat;
    property ActiveRenderingHasDepth: Boolean read FActiveRenderingHasDepth;
    property ActiveRenderingDepthFormat: TRHIPixelFormat read FActiveRenderingDepthFormat;
    property ActiveRenderingSampleCount: Cardinal read FActiveRenderingSampleCount;

    procedure BeginRecording; virtual; abstract;
    procedure EndRecording; virtual; abstract;

    { Resource Barriers & Transitions }
    procedure TransitionTexture(const Texture: TRHITexture;
      const NewState: TRHIResourceState); virtual; abstract;
    { Emits an explicit physical memory aliasing barrier before activating NewTexture
      on shared transient memory previously written/read through OldTexture (Phase 111.1). }
    procedure EmitAliasingBarrier(const OldTexture, NewTexture: TRHITexture); virtual;
    procedure GenerateMipmaps(const Texture: TRHITexture); virtual; abstract;

    { Dynamic Rendering Pass Delimiters }
    procedure BeginRendering(const Info: TRHIRenderingInfo); virtual; abstract;
    procedure EndRendering; virtual; abstract;
    procedure ClearAttachments(const ClearColorBuf: Boolean; const ClearColor: TCastleColor;
      const ClearDepthBuf: Boolean = False; const ClearDepth: Single = 1.0;
      const ClearStencilBuf: Boolean = False; const ClearStencil: Byte = 0); virtual;

    { Dynamic Viewport & Scissor State }
    procedure SetViewport(const ViewportRect: TFloatRectangle;
      const MinDepth: Single = 0.0; const MaxDepth: Single = 1.0); virtual; abstract;
    procedure SetScissor(const ScissorRect: TRectangle); virtual; abstract;
    procedure SetDepthBias(const ConstantFactor, SlopeFactor: Single); virtual; abstract;
    procedure SetLineWidth(const LineWidth: Single); virtual;
    procedure SetBlendConstants(const ABlendConstants: TVector4); virtual;

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
    { GPU-driven indirect draw with count read from a GPU buffer
      (Vulkan 1.2 Core / VK_KHR_draw_indirect_count). }
    procedure DrawIndirectCount(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
      const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal); virtual;
    procedure DrawIndexedIndirectCount(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
      const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal); virtual;
    { Mesh Shader Task/Mesh Workgroup Dispatch (VK_EXT_mesh_shader). }
    procedure DrawMeshTasks(const GroupCountX, GroupCountY, GroupCountZ: Cardinal); virtual;
    procedure DrawMeshTasksIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const DrawCount, Stride: Cardinal); virtual;

    { Secondary Command List Recording & Execution (Multi-threaded recording) }
    procedure BeginSecondaryRecording(const AInheritedInfo: TRHIRenderingInfo); overload; virtual;
    procedure BeginSecondaryRecording(const AInheritedInfo: TRHIRenderingInfo;
      const AViewportRect: TFloatRectangle; const AScissorRect: TRectangle;
      const AMinDepth: Single = 0.0; const AMaxDepth: Single = 1.0); overload; virtual;
    procedure ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList); virtual; abstract;
    procedure ExecuteSecondaryCommandsInPass(
      const SecondaryCommandLists: array of TRHICommandList); virtual;

    { Debug Markers (RenderDoc / NSight / VK_EXT_debug_utils integration) }
    procedure PushDebugGroup(const LabelName: String; const Color: TCastleColor); virtual; abstract;
    procedure PopDebugGroup; virtual; abstract;
    procedure InsertDebugMarker(const LabelName: String; const Color: TCastleColor); virtual;
  end;

  { -------------------------------------------------------------------------- }
  { Render Device (Factory & Frame Lifecycle)                                  }
  { -------------------------------------------------------------------------- }

  { Main entry point for the RHI backend. Manages GPU device lifecycles,
    swapchain presentation, frames-in-flight synchronization, and resource creation. }
  TRHIDevice = class abstract
  private
    FResources: TFPList;
  protected
    FCapabilities: TRHIDeviceCapabilities;
    FFrameIndex: Cardinal;
    FTotalFramesStarted: Cardinal;
    { Releases backend GPU handles on any surviving TRHIResource wrappers still tracked
      in FResources and detaches their FDevice reference before native device teardown. }
    procedure ReleaseRemainingDeviceResources;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    { Frame Lifecycle & Swapchain }
    function BeginFrame: TRHICommandList; virtual; abstract;
    procedure EndFrameAndPresent; virtual; abstract;
    { Records and submits an offscreen command list without acquiring or presenting
      a window swapchain image (used e.g. by out-of-frame TCastleContainer.SaveScreen). }
    function BeginOffscreenFrame: TRHICommandList; virtual;
    procedure EndOffscreenFrame; virtual;
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
    { Creates a transient carrier texture (with VK_IMAGE_CREATE_ALIAS_BIT on Vulkan)
      backed by at least AMinCarrierBytes so non-overlapping transient textures of
      different formats, resolutions, or usages can alias its physical GPU memory. }
    function CreateTransientCarrierTexture(const ADesc: TRHITextureDesc;
      const AMinCarrierBytes: UInt64 = 0): TRHITexture; virtual;
    { Attempts to create an aliased texture bound to the exact physical GPU memory
      of ACarrierTexture without allocating any new VRAM (Phase 111.1).
      Returns nil if ACarrierTexture cannot host ADesc. }
    function TryCreateAliasedTexture(const ADesc: TRHITextureDesc;
      const ACarrierTexture: TRHITexture): TRHITexture; virtual;
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
    function GetOrCreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline; virtual;
    function CreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline; virtual;

    { Creates a hardware query pool for GPU timestamps or occlusion queries. }
    function CreateQueryPool(const ADesc: TRHIQueryPoolDesc): TRHIQueryPool; virtual;

    { Readback current swapchain or texture into a CPU TCastleImage (for TCastleWindow.SaveScreen). }
    function GrabTextureImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle): TRGBAlphaImage; overload; virtual; abstract;
    function GrabTextureImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle; const DestImage: TCastleImage): Boolean; overload; virtual;
    { Reads back a specific 2D subresource slice (MipLevel, ArrayLayer) into a TRGBAlphaImage. }
    function GrabTextureSubresourceImage(const SourceTexture: TRHITexture;
      const AMipLevel, AArrayLayer: Cardinal): TRGBAlphaImage; virtual;
    { Reads back any color/HDR/float/depth texture into a full-precision TRGBAlphaFloatImage. }
    function GrabTextureFloatImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle): TRGBAlphaFloatImage; virtual;

    { Pipeline Cache persistence (loads/saves VkPipelineCache to disk) }
    procedure LoadPipelineCache(const CacheFileUrl: String); virtual; abstract;
    procedure SavePipelineCache(const CacheFileUrl: String); virtual; abstract;

    { Multiline and one-line summary strings describing the active RHI device and capabilities. }
    function GetInformationString: String; virtual;
    function GetInformationStringSummary: String; virtual;

    { Registers a (Texture, Sampler) pair in the device's global bindless descriptor array
      (Set 1, Binding 0) and returns its 0-based bindless slot index (or 0 if Texture = nil). }
    function RegisterBindlessTexture(const ATexture: TRHITexture;
      const ASampler: TRHISampler = nil): Cardinal; virtual;

    { Registers or updates an 80-byte std430 bindless material entry in the device's
      global Material SSBO table (Set 1, Binding 1) and returns its 0-based material index. }
    function RegisterOrUpdateBindlessMaterial(var AMaterialIndex: Cardinal;
      var AAlreadyRegistered: Boolean;
      const AEntryData; const AEntrySizeInBytes: Cardinal): Cardinal; virtual;

    { Returns the device's global bindless descriptor set (Set 1, holding castle_BindlessTextures[]
      at Binding 0 and CastleBindlessMaterialsBlock at Binding 1), or nil if not supported. }
    function GetBindlessDescriptorSet: TRHIDescriptorSet; virtual;

    property Capabilities: TRHIDeviceCapabilities read FCapabilities;
    { Current frame-in-flight index (0 .. MaxFramesInFlight - 1) }
    property FrameIndex: Cardinal read FFrameIndex;
    { Monotonically increasing count of frames started via BeginFrame / BeginOffscreenFrame }
    property TotalFramesStarted: Cardinal read FTotalFramesStarted;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 15.1: Declarative Render Dependency Graph (TRHIRenderGraph)          }
  { -------------------------------------------------------------------------- }

  TRHIRenderGraphPassType = (
    rgptGraphics,
    rgptCompute,
    rgptTransfer
  );

  TRHIRenderGraphResourceHandle = Integer;

  TRHIRenderGraphTextureBarrier = record
    TextureHandle: TRHIRenderGraphResourceHandle;
    PreviousAliasedTexture: TRHITexture;
    IsAliasingHandoff: Boolean;
    BeforeState: TRHIResourceState;
    AfterState: TRHIResourceState;
  end;

  TRHIRenderGraphTextureAccess = record
    Handle: TRHIRenderGraphResourceHandle;
    State: TRHIResourceState;
    LoadOp: TRHIAttachmentLoadOp;
    StoreOp: TRHIAttachmentStoreOp;
    ClearColor: TCastleColor;
    ClearDepth: Single;
    IsDepthAttachment: Boolean;
    IsColorAttachment: Boolean;
  end;

  TRHIRenderGraphPassExecuteEvent = procedure(const AGraph: TRHIRenderGraph;
    const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList) of object;
  TRHIRenderGraphPassExecuteProc = procedure(const AGraph: TRHIRenderGraph;
    const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);

  { Represents a single graphics, compute, or transfer pass registered in TRHIRenderGraph. }
  TRHIRenderGraphPass = class
  private
    FName: String;
    FPassIndex: Integer;
    FPassType: TRHIRenderGraphPassType;
    FHasSideEffects: Boolean;
    FIsCulled: Boolean;
    FExecutionOrder: Integer;
    FTextureReads: array of TRHIRenderGraphTextureAccess;
    FTextureWrites: array of TRHIRenderGraphTextureAccess;
    FBufferReads: array of TRHIRenderGraphResourceHandle;
    FBufferWrites: array of TRHIRenderGraphResourceHandle;
    FPrePassBarriers: array of TRHIRenderGraphTextureBarrier;
    FOnExecute: TRHIRenderGraphPassExecuteEvent;
    FOnExecuteProc: TRHIRenderGraphPassExecuteProc;
  public
    constructor Create(const AName: String; const APassIndex: Integer;
      const APassType: TRHIRenderGraphPassType; const AHasSideEffects: Boolean = False);

    { Declares that this pass reads AHandle in AReadState (default rsShaderRead). }
    procedure ReadTexture(const AHandle: TRHIRenderGraphResourceHandle;
      const AReadState: TRHIResourceState = rsShaderRead);

    { Declares that this pass renders into AHandle as a color attachment. }
    procedure WriteColorAttachment(const AHandle: TRHIRenderGraphResourceHandle;
      const ALoadOp: TRHIAttachmentLoadOp = loClear;
      const AStoreOp: TRHIAttachmentStoreOp = soStore); overload;
    procedure WriteColorAttachment(const AHandle: TRHIRenderGraphResourceHandle;
      const ALoadOp: TRHIAttachmentLoadOp;
      const AClearColor: TCastleColor;
      const AStoreOp: TRHIAttachmentStoreOp = soStore); overload;

    { Declares that this pass writes into AHandle as a depth/stencil attachment. }
    procedure WriteDepthAttachment(const AHandle: TRHIRenderGraphResourceHandle;
      const ALoadOp: TRHIAttachmentLoadOp = loClear;
      const AClearDepth: Single = 1.0;
      const AStoreOp: TRHIAttachmentStoreOp = soStore);

    { Declares that this compute/transfer pass writes into AHandle in AWriteState. }
    procedure WriteStorageTexture(const AHandle: TRHIRenderGraphResourceHandle;
      const AWriteState: TRHIResourceState = rsUnorderedAccess);

    { Declares buffer read/write dependencies for topological ordering. }
    procedure ReadBuffer(const AHandle: TRHIRenderGraphResourceHandle);
    procedure WriteBuffer(const AHandle: TRHIRenderGraphResourceHandle);

    function PrePassBarriersCount: Integer;
    function GetPrePassBarrier(const AIndex: Integer): TRHIRenderGraphTextureBarrier;

    property Name: String read FName;
    property PassIndex: Integer read FPassIndex;
    property PassType: TRHIRenderGraphPassType read FPassType;
    property HasSideEffects: Boolean read FHasSideEffects write FHasSideEffects;
    property IsCulled: Boolean read FIsCulled;
    property ExecutionOrder: Integer read FExecutionOrder;
    property OnExecute: TRHIRenderGraphPassExecuteEvent read FOnExecute write FOnExecute;
    property OnExecuteProc: TRHIRenderGraphPassExecuteProc read FOnExecuteProc write FOnExecuteProc;
  end;

  { Declarative Frame Render Graph performing:
    1. Pass-level read/write dependency analysis and topological sorting (Kahn's DAG algorithm).
    2. Backward liveness analysis to automatically cull unused passes (dead-pass culling).
    3. Transient render-target lifetime tracking and physical texture aliasing across non-overlapping passes.
    4. Automatic pre-pass TransitionTexture barrier hoisting and Dynamic Rendering BeginRendering/EndRendering. }
  TRHIRenderGraph = class
  private
    type
      TVirtualTextureEntry = record
        Name: String;
        Desc: TRHITextureDesc;
        IsImported: Boolean;
        InitialState: TRHIResourceState;
        FinalState: TRHIResourceState;
        PhysicalTexture: TRHITexture;
        PoolSlotIndex: Integer;
        FirstUseOrder: Integer;
        LastUseOrder: Integer;
        LastProducerPass: Integer;
      end;
      TVirtualBufferEntry = record
        Name: String;
        PhysicalBuffer: TRHIBuffer;
        LastProducerPass: Integer;
      end;
      TAliasedTextureVariant = record
        Desc: TRHITextureDesc;
        Texture: TRHITexture;
      end;
      TTransientPoolSlot = record
        Desc: TRHITextureDesc;
        Texture: TRHITexture;
        CarrierCapacityBytes: UInt64;
        AliasedVariants: array of TAliasedTextureVariant;
        LastAssignedOrder: Integer;
        LastActiveTexture: TRHITexture;
      end;
      TRHIRenderGraphPassList = {$ifdef FPC}specialize{$endif} TObjectList<TRHIRenderGraphPass>;
  private
    FDevice: TRHIDevice;
    FPasses: TRHIRenderGraphPassList;
    FCompiledPasses: array of TRHIRenderGraphPass;
    FVirtualTextures: array of TVirtualTextureEntry;
    FVirtualBuffers: array of TVirtualBufferEntry;
    FTransientPool: array of TTransientPoolSlot;
    FFinalExportBarriers: array of TRHIRenderGraphTextureBarrier;
    FIsCompiled: Boolean;
    FCulledPassCount: Integer;
    FEmittedBarrierCount: Integer;
    FAliasingBarrierCount: Integer;
    FTransientTextureCount: Integer;
    FAliasedTextureSavingsCount: Integer;
    FMemoryAliasedTextureCount: Integer;
    FAliasedMemorySavedBytes: UInt64;
    FExecutionCount: Cardinal;
    FDebugScopesEmittedCount: Cardinal;
    class function AreTextureDescsCompatibleForAliasing(
      const A, B: TRHITextureDesc): Boolean; static;
    function GetPassCount: Integer;
    function GetCompiledPassCount: Integer;
    function GetPhysicalTransientTextureCount: Integer;
  public
    constructor Create(const ADevice: TRHIDevice);
    destructor Destroy; override;

    { Clears declared passes and virtual resources for a new frame while keeping
      the pooled physical transient textures alive for zero-allocation frame reuse. }
    procedure Reset;

    { Destroys all pooled physical transient textures. }
    procedure ReleaseTransientPool;

    { Declares a transient graph-managed texture that will be allocated (or aliased) during Compile. }
    function DeclareTransientTexture(const AName: String;
      const ADesc: TRHITextureDesc): TRHIRenderGraphResourceHandle;

    { Imports an persistent external texture (e.g. Swapchain backbuffer or persistent history target). }
    function ImportExternalTexture(const AName: String;
      const ATexture: TRHITexture;
      const AInitialState: TRHIResourceState = rsUndefined;
      const AFinalState: TRHIResourceState = rsUndefined): TRHIRenderGraphResourceHandle;

    { Imports an external buffer for pass dependency tracking. }
    function ImportExternalBuffer(const AName: String;
      const ABuffer: TRHIBuffer): TRHIRenderGraphResourceHandle;

    { Adds a pass to the render graph. }
    function AddPass(const AName: String;
      const APassType: TRHIRenderGraphPassType = rgptGraphics;
      const AHasSideEffects: Boolean = False): TRHIRenderGraphPass;

    { Compiles the render graph: resolves producer-consumer edges, culls dead passes,
      topologically sorts active passes, aliases non-overlapping transient textures,
      and hoists pre-pass resource state transitions. }
    procedure Compile;

    { Executes the compiled render graph onto ACmd, automatically recording hoisted
      TransitionTexture barriers and wrapping graphics passes in BeginRendering/EndRendering. }
    procedure Execute(const ACmd: TRHICommandList);

    { Returns the physical TRHITexture bound to AHandle (after Compile). }
    function ResolvePhysicalTexture(const AHandle: TRHIRenderGraphResourceHandle): TRHITexture;

    { Returns the physical TRHIBuffer bound to AHandle. }
    function ResolvePhysicalBuffer(const AHandle: TRHIRenderGraphResourceHandle): TRHIBuffer;

    { Returns the compiled pass at AOrderIndex (0 .. CompiledPassCount - 1). }
    function GetCompiledPass(const AOrderIndex: Integer): TRHIRenderGraphPass;

    property Device: TRHIDevice read FDevice;
    property IsCompiled: Boolean read FIsCompiled;
    property PassCount: Integer read GetPassCount;
    property CompiledPassCount: Integer read GetCompiledPassCount;
    property CulledPassCount: Integer read FCulledPassCount;
    property EmittedBarrierCount: Integer read FEmittedBarrierCount;
    property TransientTextureCount: Integer read FTransientTextureCount;
    property PhysicalTransientTextureCount: Integer read GetPhysicalTransientTextureCount;
    property AliasedTextureSavingsCount: Integer read FAliasedTextureSavingsCount;
    property MemoryAliasedTextureCount: Integer read FMemoryAliasedTextureCount;
    property AliasedMemorySavedBytes: UInt64 read FAliasedMemorySavedBytes;
    property AliasingBarrierCount: Integer read FAliasingBarrierCount;
    property ExecutionCount: Cardinal read FExecutionCount;
    property DebugScopesEmittedCount: Cardinal read FDebugScopesEmittedCount;
  end;

const
  { Maximum number of frames simultaneously processed by CPU and GPU. }
  MaxFramesInFlight = 2;

type
  TRHIDeviceChangeCallback = procedure(const ADevice: TRHIDevice);

{ Global active RHI device instance managed by CastleWindow / TCastleViewport. }
function RHIDevice: TRHIDevice;
procedure SetRHIDevice(const ADevice: TRHIDevice);
procedure RegisterRHIDeviceChangeCallback(const ACallback: TRHIDeviceChangeCallback);

{ Global active RHI command list being recorded for current frame/pass. }
function ActiveCommandList: TRHICommandList;
procedure SetActiveCommandList(const ACmdList: TRHICommandList);

{ Converts TCastleWindow.AntiAliasing (TAntiAliasing) to an RHI MSAA sample count (1, 2, 4, 8, 16). }
function AntiAliasingToSampleCount(const AAntiAliasing: TAntiAliasing): Cardinal;

{ Clamps a requested MSAA sample count to the highest power-of-two sample count
  (1, 2, 4, 8, 16, 32, 64) supported by the device's MaxSupportedSamples. }
function ClampSampleCountToCapabilities(const ARequestedSamples, AMaxSupportedSamples: Cardinal): Cardinal;

{ Computes the exact full mipmap pyramid level count (floor(log2(max(1, AMaxDimension))) + 1)
  using integer bit-shifting (avoiding IEEE-754 Double Ln(8)/Ln(2) = 2.9999999999999996
  truncation on Win64 and ARM targets). }
function CalculateTextureMipLevels(const AMaxDimension: Cardinal): Cardinal;

{ Compares two framebuffer readback images (e.g. OpenGL vs Vulkan GrabTextureImage)
  by computing the normalized Root Mean Square Error (RMSE in [0..1]) across all channels.
  Returns True if dimensions/formats match and OutNormalizedRMSE <= MaxNormalizedRMSE. }
function CompareImagesPerceptualDiff(const ImageA, ImageB: TCastleImage;
  const MaxNormalizedRMSE: Single; out OutNormalizedRMSE: Single): Boolean;

type
  { Detailed perceptual comparison metrics between two rendered framebuffer images
    (e.g. side-by-side rbOpenGL vs rbVulkan visual regression verification, Phase 112.2). }
  TRHIVisualDiffMetrics = record
    DimensionsMatch: Boolean;
    NormalizedRMSE: Single;
    PSNRdB: Single;
    MaxChannelDelta: Byte;
    DiffPixelCount: Cardinal;
    TotalPixelCount: Cardinal;
    DiffPixelRatio: Single;
    Passed: Boolean;
  end;

  { Named visual regression comparison entry recorded by TRHIVisualRegressionSuite. }
  TRHIVisualRegressionCaseResult = record
    CaseName: String;
    MaxAllowedRMSE: Single;
    Metrics: TRHIVisualDiffMetrics;
  end;

  { Structured side-by-side rbOpenGL vs rbVulkan visual regression suite runner
    and summary report generator (Phase 112.2). }
  TRHIVisualRegressionSuite = class
  private
    FCases: array of TRHIVisualRegressionCaseResult;
    FChannelDeltaTolerance: Byte;
    function GetCaseCount: Integer;
    function GetPassedCount: Integer;
    function GetFailedCount: Integer;
    function GetAllPassed: Boolean;
    function GetWorstRMSE: Single;
  public
    constructor Create(const AChannelDeltaTolerance: Byte = 2);
    procedure Clear;
    function RecordComparison(const ACaseName: String;
      const AReferenceImage, ACandidateImage: TCastleImage;
      const AMaxAllowedRMSE: Single): TRHIVisualRegressionCaseResult;
    function GetCaseResult(const AIndex: Integer): TRHIVisualRegressionCaseResult;
    function BuildSummaryReport: String;

    property ChannelDeltaTolerance: Byte read FChannelDeltaTolerance write FChannelDeltaTolerance;
    property CaseCount: Integer read GetCaseCount;
    property PassedCount: Integer read GetPassedCount;
    property FailedCount: Integer read GetFailedCount;
    property AllPassed: Boolean read GetAllPassed;
    property WorstRMSE: Single read GetWorstRMSE;
  end;

{ Computes full perceptual diff metrics (NormalizedRMSE, PSNRdB, MaxChannelDelta,
  DiffPixelCount, DiffPixelRatio) between two images and sets OutMetrics.Passed :=
  DimensionsMatch and (NormalizedRMSE <= MaxNormalizedRMSE). }
function CompareImagesDetailedDiff(const ImageA, ImageB: TCastleImage;
  const MaxNormalizedRMSE: Single; out OutMetrics: TRHIVisualDiffMetrics;
  const ChannelDeltaTolerance: Byte = 2): Boolean;

{ Maps any TEncodedImage (including floating-point images TRGBAlphaFloatImage,
  TRGBFloatImage, TGrayscaleFloatImage, TGrayscaleAlphaFloatImage and GPU-compressed
  images TGPUCompressedImage) to the corresponding TRHIPixelFormat. }
function EncodedImageToRHIPixelFormat(const AImage: TEncodedImage): TRHIPixelFormat;

{ Returns the GPU texture memory size in bytes for AImage uploaded with AFormat. }
function EncodedImageToRHIGpuBytes(const AImage: TEncodedImage;
  const AFormat: TRHIPixelFormat): Int64;

{$endif read_interface}

