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
    SupportsDrawIndirectCount: Boolean;
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
    procedure ClearAttachments(const ClearColorBuf: Boolean; const ClearColor: TCastleColor;
      const ClearDepthBuf: Boolean = False; const ClearDepth: Single = 1.0;
      const ClearStencilBuf: Boolean = False; const ClearStencil: Byte = 0); virtual;

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
    { GPU-driven indirect draw with count read from a GPU buffer
      (Vulkan 1.2 Core / VK_KHR_draw_indirect_count). }
    procedure DrawIndirectCount(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
      const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal); virtual;
    procedure DrawIndexedIndirectCount(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
      const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal); virtual;

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
      const ReadArea: TRectangle): TRGBAlphaImage; overload; virtual; abstract;
    function GrabTextureImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle; const DestImage: TCastleImage): Boolean; overload; virtual;

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
      const AWriteState: TRHIResourceState = rsTransferDst);

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
      TTransientPoolSlot = record
        Desc: TRHITextureDesc;
        Texture: TRHITexture;
        LastAssignedOrder: Integer;
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
    FTransientTextureCount: Integer;
    FAliasedTextureSavingsCount: Integer;
    FExecutionCount: Cardinal;
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
    property ExecutionCount: Cardinal read FExecutionCount;
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

class function TRHITextureDesc.Create3D(const AWidth, AHeight, ADepth: Cardinal;
  const AFormat: TRHIPixelFormat; const AUsage: TRHITextureUsageFlags;
  const AMipLevels: Cardinal): TRHITextureDesc;
begin
  Result := Create2D(AWidth, AHeight, AFormat, AUsage, AMipLevels, 1);
  Result.Dimension := td3D;
  if ADepth > 1 then
    Result.DepthOrArrayLayers := ADepth
  else
    Result.DepthOrArrayLayers := 1;
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
  Result.DisableColorWrites := False;
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

class function TRHIBlendStateDesc.DefaultColorMaskNone: TRHIBlendStateDesc;
begin
  Result := DefaultOpaque;
  Result.ColorWriteMask := 0;
  Result.DisableColorWrites := True;
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

{ TRHIStencilOpStateDesc }

class function TRHIStencilOpStateDesc.DefaultKeep: TRHIStencilOpStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.FailOp := soKeep;
  Result.PassOp := soKeep;
  Result.DepthFailOp := soKeep;
  Result.CompareOp := coAlways;
  Result.CompareMask := $FF;
  Result.WriteMask := $FF;
  Result.Reference := 0;
end;

{ TRHIDepthStencilStateDesc }

class function TRHIDepthStencilStateDesc.DefaultDepthTestWrite: TRHIDepthStencilStateDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.DepthTestEnable := True;
  Result.DepthWriteEnable := True;
  Result.DepthCompareOp := coLessOrEqual;
  Result.StencilTestEnable := False;
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.BackStencil := TRHIStencilOpStateDesc.DefaultKeep;
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
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.BackStencil := TRHIStencilOpStateDesc.DefaultKeep;
end;

class function TRHIDepthStencilStateDesc.DefaultShadowMap: TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthTestWrite;
end;

class function TRHIDepthStencilStateDesc.DefaultStencilShadowVolumeZPass: TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthReadOnly;
  Result.StencilTestEnable := True;
  { Front faces: increment stencil (with wrap) when depth test passes }
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.FrontStencil.PassOp := soIncrementAndWrap;
  { Back faces: decrement stencil (with wrap) when depth test passes }
  Result.BackStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.BackStencil.PassOp := soDecrementAndWrap;
end;

class function TRHIDepthStencilStateDesc.DefaultStencilShadowVolumeZFail: TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthReadOnly;
  Result.StencilTestEnable := True;
  { Front faces: decrement stencil (with wrap) when depth test fails }
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.FrontStencil.DepthFailOp := soDecrementAndWrap;
  { Back faces: increment stencil (with wrap) when depth test fails }
  Result.BackStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.BackStencil.DepthFailOp := soIncrementAndWrap;
end;

class function TRHIDepthStencilStateDesc.DefaultStencilLitPass(
  const AStencilReference: Cardinal; const ACompareMask: Cardinal): TRHIDepthStencilStateDesc;
begin
  Result := DefaultDepthReadOnly;
  Result.StencilTestEnable := True;
  Result.FrontStencil := TRHIStencilOpStateDesc.DefaultKeep;
  Result.FrontStencil.CompareOp := coEqual;
  Result.FrontStencil.CompareMask := ACompareMask;
  Result.FrontStencil.WriteMask := 0;
  Result.FrontStencil.Reference := AStencilReference;
  Result.BackStencil := Result.FrontStencil;
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

procedure TRHICommandList.ClearAttachments(const ClearColorBuf: Boolean; const ClearColor: TCastleColor;
  const ClearDepthBuf: Boolean; const ClearDepth: Single;
  const ClearStencilBuf: Boolean; const ClearStencil: Byte);
begin
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

procedure TRHICommandList.DrawIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
begin
  DrawIndirect(IndirectBuffer, Offset, MaxDrawCount, Stride);
end;

procedure TRHICommandList.DrawIndexedIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
begin
  DrawIndexedIndirect(IndirectBuffer, Offset, MaxDrawCount, Stride);
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

function TRHIDevice.GrabTextureImage(const SourceTexture: TRHITexture;
  const ReadArea: TRectangle; const DestImage: TCastleImage): Boolean;
var
  Grabbed: TRGBAlphaImage;
begin
  Result := False;
  if DestImage = nil then
    Exit;
  Grabbed := GrabTextureImage(SourceTexture, ReadArea);
  if Grabbed <> nil then
  try
    DestImage.Assign(Grabbed);
    Result := True;
  finally
    FreeAndNil(Grabbed);
  end;
end;

function TRHIDevice.GetInformationString: String;
const
  BackendNames: array[TRHIBackendType] of String = ('OpenGL', 'OpenGLES', 'Vulkan');
begin
  Result :=
    BackendNames[FCapabilities.Backend] + ' RHI information:' + LineEnding +
    '  Device: ' + FCapabilities.DeviceName + LineEnding +
    '  Vendor ID: ' + IntToStr(FCapabilities.VendorId) + LineEnding +
    '  Max texture size: ' + IntToStr(FCapabilities.MaxTextureSize) + LineEnding +
    '  Max framebuffer MSAA samples: ' + IntToStr(FCapabilities.MaxFramebufferSampleCount) + LineEnding +
    '  Compute shaders: ' + BoolToStr(FCapabilities.SupportsComputeShaders, True) + LineEnding +
    '  Multi-draw indirect: ' + BoolToStr(FCapabilities.SupportsMultiDrawIndirect, True) + LineEnding +
    '  Draw indirect count: ' + BoolToStr(FCapabilities.SupportsDrawIndirectCount, True) + LineEnding +
    '  Bindless textures: ' + BoolToStr(FCapabilities.SupportsBindlessTextures, True) + LineEnding +
    '  Extended dynamic state: ' + BoolToStr(FCapabilities.SupportsExtendedDynamicState, True) + LineEnding +
    '  Synchronization2: ' + BoolToStr(FCapabilities.SupportsSynchronization2, True) + LineEnding +
    '  Timeline semaphores: ' + BoolToStr(FCapabilities.SupportsTimelineSemaphores, True);
end;

function TRHIDevice.RegisterBindlessTexture(const ATexture: TRHITexture;
  const ASampler: TRHISampler): Cardinal;
begin
  Result := 0;
end;

function TRHIDevice.RegisterOrUpdateBindlessMaterial(var AMaterialIndex: Cardinal;
  var AAlreadyRegistered: Boolean;
  const AEntryData; const AEntrySizeInBytes: Cardinal): Cardinal;
begin
  AAlreadyRegistered := True;
  Result := AMaterialIndex;
end;

function TRHIDevice.GetBindlessDescriptorSet: TRHIDescriptorSet;
begin
  Result := nil;
end;

function TRHIDevice.GetInformationStringSummary: String;
const
  BackendNames: array[TRHIBackendType] of String = ('OpenGL', 'OpenGLES', 'Vulkan');
begin
  if FCapabilities.DeviceName <> '' then
    Result := Format('%s (%s, modern rendering: True)', [
      BackendNames[FCapabilities.Backend],
      FCapabilities.DeviceName
    ])
  else
    Result := Format('%s (modern rendering: True)', [
      BackendNames[FCapabilities.Backend]
    ]);
end;

{ ---------------------------------------------------------------------------- }
{ TRHIRenderGraphPass                                                          }
{ ---------------------------------------------------------------------------- }

constructor TRHIRenderGraphPass.Create(const AName: String;
  const APassIndex: Integer; const APassType: TRHIRenderGraphPassType;
  const AHasSideEffects: Boolean);
begin
  inherited Create;
  FName := AName;
  FPassIndex := APassIndex;
  FPassType := APassType;
  FHasSideEffects := AHasSideEffects;
  FIsCulled := False;
  FExecutionOrder := -1;
end;

procedure TRHIRenderGraphPass.ReadTexture(
  const AHandle: TRHIRenderGraphResourceHandle;
  const AReadState: TRHIResourceState);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FTextureReads);
  SetLength(FTextureReads, Idx + 1);
  FillChar(FTextureReads[Idx], SizeOf(TRHIRenderGraphTextureAccess), 0);
  FTextureReads[Idx].Handle := AHandle;
  FTextureReads[Idx].State := AReadState;
end;

procedure TRHIRenderGraphPass.WriteColorAttachment(
  const AHandle: TRHIRenderGraphResourceHandle;
  const ALoadOp: TRHIAttachmentLoadOp;
  const AStoreOp: TRHIAttachmentStoreOp);
begin
  WriteColorAttachment(AHandle, ALoadOp, Vector4(0.0, 0.0, 0.0, 1.0), AStoreOp);
end;

procedure TRHIRenderGraphPass.WriteColorAttachment(
  const AHandle: TRHIRenderGraphResourceHandle;
  const ALoadOp: TRHIAttachmentLoadOp;
  const AClearColor: TCastleColor;
  const AStoreOp: TRHIAttachmentStoreOp);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FTextureWrites);
  SetLength(FTextureWrites, Idx + 1);
  FillChar(FTextureWrites[Idx], SizeOf(TRHIRenderGraphTextureAccess), 0);
  FTextureWrites[Idx].Handle := AHandle;
  FTextureWrites[Idx].State := rsColorAttachment;
  FTextureWrites[Idx].LoadOp := ALoadOp;
  FTextureWrites[Idx].StoreOp := AStoreOp;
  FTextureWrites[Idx].ClearColor := AClearColor;
  FTextureWrites[Idx].IsColorAttachment := True;
end;

procedure TRHIRenderGraphPass.WriteDepthAttachment(
  const AHandle: TRHIRenderGraphResourceHandle;
  const ALoadOp: TRHIAttachmentLoadOp;
  const AClearDepth: Single;
  const AStoreOp: TRHIAttachmentStoreOp);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FTextureWrites);
  SetLength(FTextureWrites, Idx + 1);
  FillChar(FTextureWrites[Idx], SizeOf(TRHIRenderGraphTextureAccess), 0);
  FTextureWrites[Idx].Handle := AHandle;
  FTextureWrites[Idx].State := rsDepthStencilWrite;
  FTextureWrites[Idx].LoadOp := ALoadOp;
  FTextureWrites[Idx].StoreOp := AStoreOp;
  FTextureWrites[Idx].ClearDepth := AClearDepth;
  FTextureWrites[Idx].IsDepthAttachment := True;
end;

procedure TRHIRenderGraphPass.WriteStorageTexture(
  const AHandle: TRHIRenderGraphResourceHandle;
  const AWriteState: TRHIResourceState);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FTextureWrites);
  SetLength(FTextureWrites, Idx + 1);
  FillChar(FTextureWrites[Idx], SizeOf(TRHIRenderGraphTextureAccess), 0);
  FTextureWrites[Idx].Handle := AHandle;
  FTextureWrites[Idx].State := AWriteState;
  FTextureWrites[Idx].StoreOp := soStore;
end;

procedure TRHIRenderGraphPass.ReadBuffer(
  const AHandle: TRHIRenderGraphResourceHandle);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FBufferReads);
  SetLength(FBufferReads, Idx + 1);
  FBufferReads[Idx] := AHandle;
end;

procedure TRHIRenderGraphPass.WriteBuffer(
  const AHandle: TRHIRenderGraphResourceHandle);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FBufferWrites);
  SetLength(FBufferWrites, Idx + 1);
  FBufferWrites[Idx] := AHandle;
end;

function TRHIRenderGraphPass.PrePassBarriersCount: Integer;
begin
  Result := Length(FPrePassBarriers);
end;

function TRHIRenderGraphPass.GetPrePassBarrier(
  const AIndex: Integer): TRHIRenderGraphTextureBarrier;
begin
  if (AIndex >= 0) and (AIndex < Length(FPrePassBarriers)) then
    Result := FPrePassBarriers[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

{ ---------------------------------------------------------------------------- }
{ TRHIRenderGraph                                                              }
{ ---------------------------------------------------------------------------- }

constructor TRHIRenderGraph.Create(const ADevice: TRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FPasses := TRHIRenderGraphPassList.Create(True);
  Reset;
end;

destructor TRHIRenderGraph.Destroy;
begin
  ReleaseTransientPool;
  FreeAndNil(FPasses);
  inherited;
end;

procedure TRHIRenderGraph.Reset;
begin
  FPasses.Clear;
  SetLength(FCompiledPasses, 0);
  SetLength(FVirtualTextures, 0);
  SetLength(FVirtualBuffers, 0);
  SetLength(FFinalExportBarriers, 0);
  FIsCompiled := False;
  FCulledPassCount := 0;
  FEmittedBarrierCount := 0;
  FTransientTextureCount := 0;
  FAliasedTextureSavingsCount := 0;
end;

procedure TRHIRenderGraph.ReleaseTransientPool;
var
  I: Integer;
begin
  for I := 0 to Length(FTransientPool) - 1 do
    FreeAndNil(FTransientPool[I].Texture);
  SetLength(FTransientPool, 0);
end;

class function TRHIRenderGraph.AreTextureDescsCompatibleForAliasing(
  const A, B: TRHITextureDesc): Boolean;
begin
  Result :=
    (A.Dimension = B.Dimension) and
    (A.Width = B.Width) and
    (A.Height = B.Height) and
    (A.DepthOrArrayLayers = B.DepthOrArrayLayers) and
    (A.MipLevels = B.MipLevels) and
    (A.SampleCount = B.SampleCount) and
    (A.Format = B.Format) and
    (A.Usage = B.Usage);
end;

function TRHIRenderGraph.GetPassCount: Integer;
begin
  Result := FPasses.Count;
end;

function TRHIRenderGraph.GetCompiledPassCount: Integer;
begin
  Result := Length(FCompiledPasses);
end;

function TRHIRenderGraph.GetPhysicalTransientTextureCount: Integer;
begin
  Result := Length(FTransientPool);
end;

function TRHIRenderGraph.DeclareTransientTexture(const AName: String;
  const ADesc: TRHITextureDesc): TRHIRenderGraphResourceHandle;
var
  Idx: Integer;
begin
  FIsCompiled := False;
  Idx := Length(FVirtualTextures);
  SetLength(FVirtualTextures, Idx + 1);
  FillChar(FVirtualTextures[Idx], SizeOf(TVirtualTextureEntry), 0);
  FVirtualTextures[Idx].Name := AName;
  FVirtualTextures[Idx].Desc := ADesc;
  FVirtualTextures[Idx].Desc.DebugName := AName;
  FVirtualTextures[Idx].IsImported := False;
  FVirtualTextures[Idx].InitialState := rsUndefined;
  FVirtualTextures[Idx].FinalState := rsUndefined;
  FVirtualTextures[Idx].PhysicalTexture := nil;
  FVirtualTextures[Idx].PoolSlotIndex := -1;
  FVirtualTextures[Idx].FirstUseOrder := High(Integer);
  FVirtualTextures[Idx].LastUseOrder := -1;
  FVirtualTextures[Idx].LastProducerPass := -1;
  Inc(FTransientTextureCount);
  Result := Idx;
end;

function TRHIRenderGraph.ImportExternalTexture(const AName: String;
  const ATexture: TRHITexture;
  const AInitialState, AFinalState: TRHIResourceState): TRHIRenderGraphResourceHandle;
var
  Idx: Integer;
begin
  FIsCompiled := False;
  Idx := Length(FVirtualTextures);
  SetLength(FVirtualTextures, Idx + 1);
  FillChar(FVirtualTextures[Idx], SizeOf(TVirtualTextureEntry), 0);
  FVirtualTextures[Idx].Name := AName;
  if ATexture <> nil then
    FVirtualTextures[Idx].Desc := ATexture.Desc;
  FVirtualTextures[Idx].IsImported := True;
  if (AInitialState = rsUndefined) and (ATexture <> nil) then
    FVirtualTextures[Idx].InitialState := ATexture.CurrentState
  else
    FVirtualTextures[Idx].InitialState := AInitialState;
  FVirtualTextures[Idx].FinalState := AFinalState;
  FVirtualTextures[Idx].PhysicalTexture := ATexture;
  FVirtualTextures[Idx].PoolSlotIndex := -1;
  FVirtualTextures[Idx].FirstUseOrder := High(Integer);
  FVirtualTextures[Idx].LastUseOrder := -1;
  FVirtualTextures[Idx].LastProducerPass := -1;
  Result := Idx;
end;

function TRHIRenderGraph.ImportExternalBuffer(const AName: String;
  const ABuffer: TRHIBuffer): TRHIRenderGraphResourceHandle;
var
  Idx: Integer;
begin
  FIsCompiled := False;
  Idx := Length(FVirtualBuffers);
  SetLength(FVirtualBuffers, Idx + 1);
  FVirtualBuffers[Idx].Name := AName;
  FVirtualBuffers[Idx].PhysicalBuffer := ABuffer;
  FVirtualBuffers[Idx].LastProducerPass := -1;
  Result := Idx;
end;

function TRHIRenderGraph.AddPass(const AName: String;
  const APassType: TRHIRenderGraphPassType;
  const AHasSideEffects: Boolean): TRHIRenderGraphPass;
begin
  FIsCompiled := False;
  Result := TRHIRenderGraphPass.Create(AName, FPasses.Count, APassType, AHasSideEffects);
  FPasses.Add(Result);
end;

procedure TRHIRenderGraph.Compile;
var
  NPasses, P, Q, I, J, H, OrderIdx, SlotIdx, ChosenSlot, BarrierIdx: Integer;
  Edges: array of array of Boolean;
  InDegree: array of Integer;
  IsLive: array of Boolean;
  Queue: array of Integer;
  QueueHead, QueueTail: Integer;
  Pass, OtherPass: TRHIRenderGraphPass;
  LastTexWriter: array of Integer;
  LastBufWriter: array of Integer;
  TrackedTexState: array of TRHIResourceState;
  PoolTexState: array of TRHIResourceState;
  CurState, NeededState: TRHIResourceState;
  AlreadyHasBarrier: Boolean;
begin
  NPasses := FPasses.Count;
  SetLength(FCompiledPasses, 0);
  SetLength(FFinalExportBarriers, 0);
  FCulledPassCount := 0;
  FEmittedBarrierCount := 0;
  FAliasedTextureSavingsCount := 0;

  if NPasses = 0 then
  begin
    FIsCompiled := True;
    Exit;
  end;

  { 1. Build DAG dependency edges between passes (Edges[Producer, Consumer] = True) }
  SetLength(Edges, NPasses, NPasses);
  for P := 0 to NPasses - 1 do
    for Q := 0 to NPasses - 1 do
      Edges[P][Q] := False;

  SetLength(LastTexWriter, Length(FVirtualTextures));
  for I := 0 to Length(LastTexWriter) - 1 do
    LastTexWriter[I] := -1;

  SetLength(LastBufWriter, Length(FVirtualBuffers));
  for I := 0 to Length(LastBufWriter) - 1 do
    LastBufWriter[I] := -1;

  { First pass: resolve producer -> consumer edges regardless of declaration order
    by matching any pass Q that reads resource R to any pass P that writes resource R }
  for P := 0 to NPasses - 1 do
  begin
    Pass := FPasses[P];
    for I := 0 to Length(Pass.FTextureWrites) - 1 do
    begin
      H := Pass.FTextureWrites[I].Handle;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        { Any earlier writer of the same texture must precede this writer (WAW) }
        if (LastTexWriter[H] >= 0) and (LastTexWriter[H] <> P) then
          Edges[LastTexWriter[H]][P] := True;
        LastTexWriter[H] := P;

        { Any pass Q that reads H depends on writer P (unless Q also writes H before P) }
        for Q := 0 to NPasses - 1 do
          if Q <> P then
          begin
            OtherPass := FPasses[Q];
            for J := 0 to Length(OtherPass.FTextureReads) - 1 do
              if OtherPass.FTextureReads[J].Handle = H then
              begin
                { Avoid creating a 2-cycle if Q already precedes P }
                if not Edges[Q][P] then
                  Edges[P][Q] := True;
              end;
          end;
      end;
    end;

    for I := 0 to Length(Pass.FBufferWrites) - 1 do
    begin
      H := Pass.FBufferWrites[I];
      if (H >= 0) and (H < Length(FVirtualBuffers)) then
      begin
        if (LastBufWriter[H] >= 0) and (LastBufWriter[H] <> P) then
          Edges[LastBufWriter[H]][P] := True;
        LastBufWriter[H] := P;

        for Q := 0 to NPasses - 1 do
          if Q <> P then
          begin
            OtherPass := FPasses[Q];
            for J := 0 to Length(OtherPass.FBufferReads) - 1 do
              if OtherPass.FBufferReads[J] = H then
                if not Edges[Q][P] then
                  Edges[P][Q] := True;
          end;
      end;
    end;
  end;

  { 2. Backward Liveness Analysis (Dead-Pass Culling) }
  SetLength(IsLive, NPasses);
  SetLength(Queue, NPasses);
  QueueHead := 0;
  QueueTail := 0;

  for P := 0 to NPasses - 1 do
  begin
    Pass := FPasses[P];
    IsLive[P] := Pass.FHasSideEffects;

    if not IsLive[P] then
    begin
      for I := 0 to Length(Pass.FTextureWrites) - 1 do
      begin
        H := Pass.FTextureWrites[I].Handle;
        if (H >= 0) and (H < Length(FVirtualTextures)) and FVirtualTextures[H].IsImported then
        begin
          IsLive[P] := True;
          Break;
        end;
      end;
    end;

    if not IsLive[P] then
    begin
      for I := 0 to Length(Pass.FBufferWrites) - 1 do
      begin
        H := Pass.FBufferWrites[I];
        if (H >= 0) and (H < Length(FVirtualBuffers)) then
        begin
          IsLive[P] := True;
          Break;
        end;
      end;
    end;

    if IsLive[P] then
    begin
      Queue[QueueTail] := P;
      Inc(QueueTail);
    end;
  end;

  while QueueHead < QueueTail do
  begin
    Q := Queue[QueueHead];
    Inc(QueueHead);
    for P := 0 to NPasses - 1 do
      if Edges[P][Q] and (not IsLive[P]) then
      begin
        IsLive[P] := True;
        Queue[QueueTail] := P;
        Inc(QueueTail);
      end;
  end;

  for P := 0 to NPasses - 1 do
  begin
    FPasses[P].FIsCulled := not IsLive[P];
    FPasses[P].FExecutionOrder := -1;
    SetLength(FPasses[P].FPrePassBarriers, 0);
    if not IsLive[P] then
      Inc(FCulledPassCount);
  end;

  { 3. Topological Sort (Kahn's Algorithm) over live passes }
  SetLength(InDegree, NPasses);
  for P := 0 to NPasses - 1 do
  begin
    InDegree[P] := 0;
    if IsLive[P] then
      for Q := 0 to NPasses - 1 do
        if IsLive[Q] and Edges[Q][P] then
          Inc(InDegree[P]);
  end;

  QueueHead := 0;
  QueueTail := 0;
  for P := 0 to NPasses - 1 do
    if IsLive[P] and (InDegree[P] = 0) then
    begin
      Queue[QueueTail] := P;
      Inc(QueueTail);
    end;

  OrderIdx := 0;
  SetLength(FCompiledPasses, NPasses - FCulledPassCount);
  while QueueHead < QueueTail do
  begin
    P := Queue[QueueHead];
    Inc(QueueHead);
    FPasses[P].FExecutionOrder := OrderIdx;
    FCompiledPasses[OrderIdx] := FPasses[P];
    Inc(OrderIdx);

    for Q := 0 to NPasses - 1 do
      if IsLive[Q] and Edges[P][Q] then
      begin
        Dec(InDegree[Q]);
        if InDegree[Q] = 0 then
        begin
          Queue[QueueTail] := Q;
          Inc(QueueTail);
        end;
      end;
  end;

  if OrderIdx <> (NPasses - FCulledPassCount) then
    raise ERHIError.Create('TRHIRenderGraph.Compile: Dependency cycle detected in render graph passes.');

  { 4. Compute Transient Texture Lifetimes & Perform Physical Texture Aliasing }
  for H := 0 to Length(FVirtualTextures) - 1 do
  begin
    FVirtualTextures[H].FirstUseOrder := High(Integer);
    FVirtualTextures[H].LastUseOrder := -1;
    FVirtualTextures[H].PoolSlotIndex := -1;
    if not FVirtualTextures[H].IsImported then
      FVirtualTextures[H].PhysicalTexture := nil;
  end;

  for OrderIdx := 0 to Length(FCompiledPasses) - 1 do
  begin
    Pass := FCompiledPasses[OrderIdx];
    for I := 0 to Length(Pass.FTextureReads) - 1 do
    begin
      H := Pass.FTextureReads[I].Handle;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        if OrderIdx < FVirtualTextures[H].FirstUseOrder then
          FVirtualTextures[H].FirstUseOrder := OrderIdx;
        if OrderIdx > FVirtualTextures[H].LastUseOrder then
          FVirtualTextures[H].LastUseOrder := OrderIdx;
      end;
    end;
    for I := 0 to Length(Pass.FTextureWrites) - 1 do
    begin
      H := Pass.FTextureWrites[I].Handle;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        if OrderIdx < FVirtualTextures[H].FirstUseOrder then
          FVirtualTextures[H].FirstUseOrder := OrderIdx;
        if OrderIdx > FVirtualTextures[H].LastUseOrder then
          FVirtualTextures[H].LastUseOrder := OrderIdx;
      end;
    end;
  end;

  { Reset pool slot usage for this compilation }
  for SlotIdx := 0 to Length(FTransientPool) - 1 do
    FTransientPool[SlotIdx].LastAssignedOrder := -1;

  { Assign physical textures in increasing FirstUseOrder }
  for OrderIdx := 0 to Length(FCompiledPasses) - 1 do
    for H := 0 to Length(FVirtualTextures) - 1 do
      if (not FVirtualTextures[H].IsImported) and
         (FVirtualTextures[H].FirstUseOrder = OrderIdx) and
         (FVirtualTextures[H].LastUseOrder >= OrderIdx) and
         (FVirtualTextures[H].PhysicalTexture = nil) then
      begin
        ChosenSlot := -1;
        for SlotIdx := 0 to Length(FTransientPool) - 1 do
          if (FTransientPool[SlotIdx].LastAssignedOrder < FVirtualTextures[H].FirstUseOrder) and
             AreTextureDescsCompatibleForAliasing(FTransientPool[SlotIdx].Desc, FVirtualTextures[H].Desc) then
          begin
            ChosenSlot := SlotIdx;
            if FTransientPool[SlotIdx].LastAssignedOrder >= 0 then
              Inc(FAliasedTextureSavingsCount);
            Break;
          end;

        if ChosenSlot < 0 then
        begin
          ChosenSlot := Length(FTransientPool);
          SetLength(FTransientPool, ChosenSlot + 1);
          FTransientPool[ChosenSlot].Desc := FVirtualTextures[H].Desc;
          if FDevice <> nil then
            FTransientPool[ChosenSlot].Texture := FDevice.CreateTexture(FVirtualTextures[H].Desc)
          else
            FTransientPool[ChosenSlot].Texture := nil;
        end;

        FTransientPool[ChosenSlot].LastAssignedOrder := FVirtualTextures[H].LastUseOrder;
        FVirtualTextures[H].PoolSlotIndex := ChosenSlot;
        FVirtualTextures[H].PhysicalTexture := FTransientPool[ChosenSlot].Texture;
      end;

  { 5. Hoist Pre-Pass Resource State Transitions }
  SetLength(TrackedTexState, Length(FVirtualTextures));
  for H := 0 to Length(FVirtualTextures) - 1 do
    TrackedTexState[H] := FVirtualTextures[H].InitialState;

  SetLength(PoolTexState, Length(FTransientPool));
  for SlotIdx := 0 to Length(FTransientPool) - 1 do
    if FTransientPool[SlotIdx].Texture <> nil then
      PoolTexState[SlotIdx] := FTransientPool[SlotIdx].Texture.CurrentState
    else
      PoolTexState[SlotIdx] := rsUndefined;

  for OrderIdx := 0 to Length(FCompiledPasses) - 1 do
  begin
    Pass := FCompiledPasses[OrderIdx];
    SetLength(Pass.FPrePassBarriers, 0);

    { Check texture reads }
    for I := 0 to Length(Pass.FTextureReads) - 1 do
    begin
      H := Pass.FTextureReads[I].Handle;
      NeededState := Pass.FTextureReads[I].State;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        SlotIdx := FVirtualTextures[H].PoolSlotIndex;
        if (not FVirtualTextures[H].IsImported) and (SlotIdx >= 0) then
          CurState := PoolTexState[SlotIdx]
        else
          CurState := TrackedTexState[H];

        if CurState <> NeededState then
        begin
          AlreadyHasBarrier := False;
          for J := 0 to Length(Pass.FPrePassBarriers) - 1 do
            if Pass.FPrePassBarriers[J].TextureHandle = H then
            begin
              AlreadyHasBarrier := True;
              Break;
            end;
          if not AlreadyHasBarrier then
          begin
            BarrierIdx := Length(Pass.FPrePassBarriers);
            SetLength(Pass.FPrePassBarriers, BarrierIdx + 1);
            Pass.FPrePassBarriers[BarrierIdx].TextureHandle := H;
            Pass.FPrePassBarriers[BarrierIdx].BeforeState := CurState;
            Pass.FPrePassBarriers[BarrierIdx].AfterState := NeededState;
            Inc(FEmittedBarrierCount);
          end;
          TrackedTexState[H] := NeededState;
          if (not FVirtualTextures[H].IsImported) and (SlotIdx >= 0) then
            PoolTexState[SlotIdx] := NeededState;
        end;
      end;
    end;

    { Check texture writes }
    for I := 0 to Length(Pass.FTextureWrites) - 1 do
    begin
      H := Pass.FTextureWrites[I].Handle;
      NeededState := Pass.FTextureWrites[I].State;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        SlotIdx := FVirtualTextures[H].PoolSlotIndex;
        if (not FVirtualTextures[H].IsImported) and (SlotIdx >= 0) then
          CurState := PoolTexState[SlotIdx]
        else
          CurState := TrackedTexState[H];

        if CurState <> NeededState then
        begin
          AlreadyHasBarrier := False;
          for J := 0 to Length(Pass.FPrePassBarriers) - 1 do
            if Pass.FPrePassBarriers[J].TextureHandle = H then
            begin
              Pass.FPrePassBarriers[J].AfterState := NeededState;
              AlreadyHasBarrier := True;
              Break;
            end;
          if not AlreadyHasBarrier then
          begin
            BarrierIdx := Length(Pass.FPrePassBarriers);
            SetLength(Pass.FPrePassBarriers, BarrierIdx + 1);
            Pass.FPrePassBarriers[BarrierIdx].TextureHandle := H;
            Pass.FPrePassBarriers[BarrierIdx].BeforeState := CurState;
            Pass.FPrePassBarriers[BarrierIdx].AfterState := NeededState;
            Inc(FEmittedBarrierCount);
          end;
          TrackedTexState[H] := NeededState;
          if (not FVirtualTextures[H].IsImported) and (SlotIdx >= 0) then
            PoolTexState[SlotIdx] := NeededState;
        end;
      end;
    end;
  end;

  { Check FinalState transitions for imported textures }
  for H := 0 to Length(FVirtualTextures) - 1 do
    if FVirtualTextures[H].IsImported and
       (FVirtualTextures[H].FinalState <> rsUndefined) and
       (TrackedTexState[H] <> FVirtualTextures[H].FinalState) then
    begin
      BarrierIdx := Length(FFinalExportBarriers);
      SetLength(FFinalExportBarriers, BarrierIdx + 1);
      FFinalExportBarriers[BarrierIdx].TextureHandle := H;
      FFinalExportBarriers[BarrierIdx].BeforeState := TrackedTexState[H];
      FFinalExportBarriers[BarrierIdx].AfterState := FVirtualTextures[H].FinalState;
      Inc(FEmittedBarrierCount);
    end;

  FIsCompiled := True;
end;

procedure TRHIRenderGraph.Execute(const ACmd: TRHICommandList);
var
  OrderIdx, I, ColorCount: Integer;
  Pass: TRHIRenderGraphPass;
  PhysTex: TRHITexture;
  RenderInfo: TRHIRenderingInfo;
  TargetW, TargetH: Cardinal;
  HasAttachments: Boolean;
begin
  if not FIsCompiled then
    Compile;

  for OrderIdx := 0 to Length(FCompiledPasses) - 1 do
  begin
    Pass := FCompiledPasses[OrderIdx];

    { 1. Emit hoisted pre-pass texture barriers }
    if ACmd <> nil then
      for I := 0 to Length(Pass.FPrePassBarriers) - 1 do
      begin
        PhysTex := ResolvePhysicalTexture(Pass.FPrePassBarriers[I].TextureHandle);
        if PhysTex <> nil then
          ACmd.TransitionTexture(PhysTex, Pass.FPrePassBarriers[I].AfterState);
      end;

    { 2. Automatically wrap graphics passes with attachments in BeginRendering/EndRendering }
    HasAttachments := False;
    if (ACmd <> nil) and (Pass.FPassType = rgptGraphics) and (Length(Pass.FTextureWrites) > 0) then
    begin
      FillChar(RenderInfo, SizeOf(RenderInfo), 0);
      ColorCount := 0;
      TargetW := 0;
      TargetH := 0;

      for I := 0 to Length(Pass.FTextureWrites) - 1 do
      begin
        PhysTex := ResolvePhysicalTexture(Pass.FTextureWrites[I].Handle);
        if (PhysTex <> nil) and (TargetW = 0) then
        begin
          TargetW := PhysTex.Desc.Width;
          TargetH := PhysTex.Desc.Height;
        end;

        if Pass.FTextureWrites[I].IsColorAttachment then
        begin
          SetLength(RenderInfo.ColorAttachments, ColorCount + 1);
          FillChar(RenderInfo.ColorAttachments[ColorCount], SizeOf(TRHIRenderingAttachment), 0);
          RenderInfo.ColorAttachments[ColorCount].Texture := PhysTex;
          RenderInfo.ColorAttachments[ColorCount].LoadOp := Pass.FTextureWrites[I].LoadOp;
          RenderInfo.ColorAttachments[ColorCount].StoreOp := Pass.FTextureWrites[I].StoreOp;
          RenderInfo.ColorAttachments[ColorCount].ClearColor := Pass.FTextureWrites[I].ClearColor;
          Inc(ColorCount);
          HasAttachments := True;
        end else
        if Pass.FTextureWrites[I].IsDepthAttachment then
        begin
          RenderInfo.HasDepthAttachment := True;
          FillChar(RenderInfo.DepthAttachment, SizeOf(TRHIRenderingAttachment), 0);
          RenderInfo.DepthAttachment.Texture := PhysTex;
          RenderInfo.DepthAttachment.LoadOp := Pass.FTextureWrites[I].LoadOp;
          RenderInfo.DepthAttachment.StoreOp := Pass.FTextureWrites[I].StoreOp;
          RenderInfo.DepthAttachment.ClearDepth := Pass.FTextureWrites[I].ClearDepth;
          HasAttachments := True;
        end;
      end;

      if HasAttachments then
      begin
        if (TargetW = 0) or (TargetH = 0) then
        begin
          TargetW := 1;
          TargetH := 1;
        end;
        RenderInfo.RenderArea := Rectangle(0, 0, TargetW, TargetH);
        ACmd.BeginRendering(RenderInfo);
        ACmd.SetViewport(FloatRectangle(0, 0, TargetW, TargetH));
        ACmd.SetScissor(RenderInfo.RenderArea);
      end;
    end;

    { 3. Execute pass callback }
    if Assigned(Pass.FOnExecute) then
      Pass.FOnExecute(Self, Pass, ACmd);
    if Assigned(Pass.FOnExecuteProc) then
      Pass.FOnExecuteProc(Self, Pass, ACmd);

    if (ACmd <> nil) and HasAttachments then
      ACmd.EndRendering;
  end;

  { 4. Emit final export barriers }
  if ACmd <> nil then
    for I := 0 to Length(FFinalExportBarriers) - 1 do
    begin
      PhysTex := ResolvePhysicalTexture(FFinalExportBarriers[I].TextureHandle);
      if PhysTex <> nil then
        ACmd.TransitionTexture(PhysTex, FFinalExportBarriers[I].AfterState);
    end;

  Inc(FExecutionCount);
end;

function TRHIRenderGraph.ResolvePhysicalTexture(
  const AHandle: TRHIRenderGraphResourceHandle): TRHITexture;
begin
  if (AHandle >= 0) and (AHandle < Length(FVirtualTextures)) then
    Result := FVirtualTextures[AHandle].PhysicalTexture
  else
    Result := nil;
end;

function TRHIRenderGraph.ResolvePhysicalBuffer(
  const AHandle: TRHIRenderGraphResourceHandle): TRHIBuffer;
begin
  if (AHandle >= 0) and (AHandle < Length(FVirtualBuffers)) then
    Result := FVirtualBuffers[AHandle].PhysicalBuffer
  else
    Result := nil;
end;

function TRHIRenderGraph.GetCompiledPass(const AOrderIndex: Integer): TRHIRenderGraphPass;
begin
  if (AOrderIndex >= 0) and (AOrderIndex < Length(FCompiledPasses)) then
    Result := FCompiledPasses[AOrderIndex]
  else
    Result := nil;
end;

end.
