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

{ Vulkan 1.3 implementation of CastleInternalRHI.
  Uses VK_KHR_dynamic_rendering (core in 1.3) and negative viewport height
  (VK_KHR_maintenance1) to match Castle Game Engine's OpenGL clip-space conventions. }
unit CastleInternalRHI_Vulkan;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, Generics.Collections, Generics.Defaults,
  CastleVectors, CastleColors, CastleRectangles, CastleImages, CastleLog,
  CastleInternalRHI, CastleInternalVulkan;

type
  TVulkanRHIDevice = class;

  { Callback provided by TCastleWindow to create the platform-specific VkSurfaceKHR }
  TVulkanCreateSurfaceEvent = function(const Instance: VkInstance): VkSurfaceKHR of object;

  { -------------------------------------------------------------------------- }
  { Concrete Vulkan Resource Classes                                           }
  { -------------------------------------------------------------------------- }

  TVulkanRHIBuffer = class(TRHIBuffer)
  private
    FHandle: VkBuffer;
    FDeviceMemory: VkDeviceMemory;
    FMemoryOffset: VkDeviceSize;
    FAllocatedSize: VkDeviceSize;
    FMappedPtr: Pointer;
    function VulkanDevice: TVulkanRHIDevice;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHIBufferDesc;
      const InitialData: Pointer);
    destructor Destroy; override;

    function Map: Pointer; override;
    procedure Unmap; override;
    procedure UploadData(const Data; const Size: PtrUInt; const Offset: PtrUInt = 0); override;

    property Handle: VkBuffer read FHandle;
  end;

  TVulkanRHITexture = class(TRHITexture)
  private
    FImage: VkImage;
    FImageView: VkImageView;
    FDeviceMemory: VkDeviceMemory;
    FAllocatedSize: VkDeviceSize;
    FOwnsImage: Boolean;
    FAspectMask: VkImageAspectFlags;
    function VulkanDevice: TVulkanRHIDevice;
  public
    { Standard constructor that allocates a new VkImage and VkImageView }
    constructor Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHITextureDesc); overload;
    { Wrapper constructor for existing VkSwapchainKHR images }
    constructor CreateSwapchainWrapper(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHITextureDesc; const AExistingImage: VkImage;
      const AExistingView: VkImageView); overload;
    destructor Destroy; override;

    procedure UploadImage(const AImage: TEncodedImage;
      const AMipLevel: Cardinal = 0; const AArrayLayer: Cardinal = 0); override;

    property Image: VkImage read FImage;
    property ImageView: VkImageView read FImageView;
    property AspectMask: VkImageAspectFlags read FAspectMask;
  end;

  TVulkanRHISampler = class(TRHISampler)
  private
    FHandle: VkSampler;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHISamplerDesc);
    destructor Destroy; override;
    property Handle: VkSampler read FHandle;
  end;

  TVulkanRHIShaderModule = class(TRHIShaderModule)
  private
    FHandle: VkShaderModule;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const AStage: TRHIShaderStage;
      const ASPIRVBinary: Pointer; const ASizeInBytes: PtrUInt; const ADebugName: String);
    destructor Destroy; override;
    property Handle: VkShaderModule read FHandle;
  end;

  TVulkanRHIDescriptorSetLayout = class(TRHIDescriptorSetLayout)
  private
    FHandle: VkDescriptorSetLayout;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const Bindings: array of TRHIDescriptorBindingDesc);
    destructor Destroy; override;
    property Handle: VkDescriptorSetLayout read FHandle;
  end;

  TVulkanRHIDescriptorSet = class(TRHIDescriptorSet)
  private
    FHandle: VkDescriptorSet;
    FLayout: TVulkanRHIDescriptorSetLayout;
    FPendingWrites: array of VkWriteDescriptorSet;
    FBufferInfos: array of VkDescriptorBufferInfo;
    FImageInfos: array of VkDescriptorImageInfo;
    function VulkanDevice: TVulkanRHIDevice;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ALayout: TVulkanRHIDescriptorSetLayout);
    destructor Destroy; override;

    procedure BindUniformBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); override;
    procedure BindStorageBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); override;
    procedure BindTexture(const Binding: Cardinal; const Texture: TRHITexture;
      const Sampler: TRHISampler); override;
    procedure Update; override;

    property Handle: VkDescriptorSet read FHandle;
  end;

  TVulkanRHIPipeline = class(TRHIPipeline)
  private
    FHandle: VkPipeline;
    FPipelineLayout: VkPipelineLayout;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHIGraphicsPipelineDesc);
    destructor Destroy; override;
    property Handle: VkPipeline read FHandle;
    property PipelineLayout: VkPipelineLayout read FPipelineLayout;
  end;

  { -------------------------------------------------------------------------- }
  { Vulkan Command List                                                        }
  { -------------------------------------------------------------------------- }

  TVulkanRHICommandList = class(TRHICommandList)
  private
    FDevice: TVulkanRHIDevice;
    FCommandPool: VkCommandPool;
    FHandle: VkCommandBuffer;
    FCurrentPipeline: TVulkanRHIPipeline;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const AQueueFamilyIndex: Cardinal;
      const ALevel: TRHICommandListLevel = cllPrimary);
    destructor Destroy; override;

    procedure BeginRecording; override;
    procedure EndRecording; override;

    procedure TransitionTexture(const Texture: TRHITexture;
      const NewState: TRHIResourceState); override;
    procedure GenerateMipmaps(const Texture: TRHITexture); override;

    procedure BeginRendering(const Info: TRHIRenderingInfo); override;
    procedure EndRendering; override;

    procedure SetViewport(const ViewportRect: TFloatRectangle;
      const MinDepth: Single = 0.0; const MaxDepth: Single = 1.0); override;
    procedure SetScissor(const ScissorRect: TRectangle); override;
    procedure SetDepthBias(const ConstantFactor, SlopeFactor: Single); override;

    procedure BindPipeline(const Pipeline: TRHIPipeline); override;
    procedure BindDescriptorSet(const SetIndex: Cardinal;
      const DescriptorSet: TRHIDescriptorSet;
      const DynamicOffsets: array of Cardinal); override;
    procedure PushConstants(const StageFlags: TRHIShaderStageFlags;
      const Offset, Size: Cardinal; const Data); override;

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

    procedure ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList); override;

    procedure PushDebugGroup(const LabelName: String; const Color: TCastleColor); override;
    procedure PopDebugGroup; override;

    property Handle: VkCommandBuffer read FHandle;
  end;

  { -------------------------------------------------------------------------- }
  { Vulkan Render Device                                                       }
  { -------------------------------------------------------------------------- }

  TVulkanFrameContext = record
    ImageAvailableSemaphore: VkSemaphore;
    RenderFinishedSemaphore: VkSemaphore;
    InFlightFence: VkFence;
    CommandList: TVulkanRHICommandList;
  end;

  TVulkanPipelineMap = {$ifdef FPC}specialize{$endif} TObjectDictionary<UInt64, TVulkanRHIPipeline>;

  TVulkanRHIDevice = class(TRHIDevice)
  private
    FInstance: VkInstance;
    FDebugMessenger: VkDebugUtilsMessengerEXT;
    FSurface: VkSurfaceKHR;
    FPhysicalDevice: VkPhysicalDevice;
    FDevice: VkDevice;
    FDeviceId: Cardinal;
    FGraphicsQueue: VkQueue;
    FPresentQueue: VkQueue;
    FGraphicsQueueFamily: Cardinal;
    FPresentQueueFamily: Cardinal;

    { Swapchain state }
    FSwapchain: VkSwapchainKHR;
    FSwapchainFormat: TRHIPixelFormat;
    FSwapchainExtent: VkExtent2D;
    FSwapchainColorTextures: array of TVulkanRHITexture;
    FSwapchainDepthTexture: TVulkanRHITexture;
    FCurrentSwapchainImageIndex: Cardinal;

    { Frame synchronization & command recording }
    FFrames: array[0 .. MaxFramesInFlight - 1] of TVulkanFrameContext;

    { Descriptor & Pipeline Caches }
    FDescriptorPool: VkDescriptorPool;
    FPipelineCache: VkPipelineCache;
    FPipelineMap: TVulkanPipelineMap;

    { Diagnostics & VK_EXT_memory_budget tracking }
    FSupportsMemoryBudgetExt: Boolean;
    FPipelineCacheHits: Cardinal;
    FPipelineCacheMisses: Cardinal;
    FDescriptorSetAllocations: Cardinal;
    FAllocatedMemoryBytes: Int64;

    procedure CreateInstance(const EnableValidation: Boolean);
    procedure PickPhysicalDevice;
    procedure CreateLogicalDevice;
    procedure CreateSwapchain(const Width, Height: Cardinal);
    procedure DestroySwapchain;
    procedure CreateFrameContexts;
    procedure CreateDescriptorPool;
    function IsDeviceExtensionSupported(const AExtensionName: AnsiString): Boolean;
    function ComputePipelineHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
  public
    constructor Create(const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
      const InitialWidth, InitialHeight: Cardinal;
      const EnableValidation: Boolean = True); reintroduce; overload;
    { Creates a headless Vulkan RHI device instance (for offscreen/unit testing). }
    constructor CreateHeadless(const APhysicalDevice: VkPhysicalDevice;
      const ASupportsMemoryBudgetExt: Boolean = True); overload;
    destructor Destroy; override;

    { Helper for one-shot transfer commands (texture/buffer uploads) }
    function BeginSingleTimeCommands: VkCommandBuffer;
    procedure EndSingleTimeCommands(const CmdBuf: VkCommandBuffer);
    function FindMemoryType(const TypeFilter: Cardinal;
      const Properties: VkMemoryPropertyFlags): Cardinal;

    { Queries live GPU VRAM usage and budget via VK_EXT_memory_budget (or heap fallback).
      Returns True if VK_EXT_memory_budget was used. }
    function QueryMemoryBudget(out AUsedBytes, ABudgetBytes: UInt64;
      out AUsedMB, ABudgetMB: Cardinal): Boolean;

    { Records diagnostic counters for testing or custom pass tracking. }
    procedure RecordDiagnostics(const APipelineHits, APipelineMisses,
      ADescriptorAllocs: Cardinal; const AAllocatedBytes: UInt64 = 0);

    { TRHIDevice overrides }
    function BeginFrame: TRHICommandList; override;
    procedure EndFrameAndPresent; override;
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

    function GrabTextureImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle): TRGBAlphaImage; override;

    procedure LoadPipelineCache(const CacheFileUrl: String); override;
    procedure SavePipelineCache(const CacheFileUrl: String); override;

    property Handle: VkDevice read FDevice;
    property PhysicalDevice: VkPhysicalDevice read FPhysicalDevice;
    property DescriptorPool: VkDescriptorPool read FDescriptorPool;
    property PipelineCache: VkPipelineCache read FPipelineCache;
    property SupportsMemoryBudgetExt: Boolean read FSupportsMemoryBudgetExt;
    property PipelineCacheHits: Cardinal read FPipelineCacheHits;
    property PipelineCacheMisses: Cardinal read FPipelineCacheMisses;
    property DescriptorSetAllocations: Cardinal read FDescriptorSetAllocations;
    property AllocatedMemoryBytes: Int64 read FAllocatedMemoryBytes;
  end;

{ Computes a deterministic 64-bit FNV-1a hash for a graphics pipeline state descriptor. }
function ComputePipelineKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;

const
  PipelineCacheDiskMagic = $43474550; // 'CGEP'
  PipelineCacheDiskVersion = 1;

type
  { Header stored on disk before raw VkPipelineCache data to validate hardware compatibility. }
  TPipelineCacheDiskHeader = packed record
    Magic: Cardinal;
    Version: Cardinal;
    VendorId: Cardinal;
    DeviceId: Cardinal;
    DataSize: Cardinal;
    DataHash: UInt64;
  end;

{ Writes a hardware-tagged VkPipelineCache binary blob to a stream. }
procedure SavePipelineCacheBlobToStream(const AStream: TStream;
  const AVendorId, ADeviceId: Cardinal; const AData: Pointer; const ASize: PtrUInt);

{ Reads and validates a hardware-tagged VkPipelineCache binary blob from a stream.
  Returns False if the stream is corrupt, empty, or belongs to a different GPU vendor/device. }
function LoadPipelineCacheBlobFromStream(const AStream: TStream;
  const AExpectedVendorId, AExpectedDeviceId: Cardinal; out ABlob: TBytes): Boolean;

implementation

uses
  CastleDownload, CastleInternalShaderCompiler, CastleInternalVulkanWSI,
  CastleInternalVulkanMemory;

const
  FNV1aOffsetBasis64 = UInt64($CBF29CE484222325);
  FNV1aPrime64 = UInt64($00000100000001B3);

{$push}{$Q-}{$R-}
procedure HashBytesFNV1a(var AHash: UInt64; const AData; const ASize: PtrUInt);
var
  P: PByte;
  I: PtrUInt;
begin
  if ASize = 0 then Exit;
  P := @AData;
  for I := 0 to ASize - 1 do
  begin
    AHash := (AHash xor UInt64(P[I])) * FNV1aPrime64;
  end;
end;

procedure HashUInt64FNV1a(var AHash: UInt64; const AValue: UInt64);
begin
  HashBytesFNV1a(AHash, AValue, SizeOf(AValue));
end;
{$pop}

function ComputePipelineKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
var
  I: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, PtrUInt(ADesc.VertexShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.FragmentShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.GeometryShader));
  HashBytesFNV1a(Result, ADesc.Topology, SizeOf(ADesc.Topology));
  HashBytesFNV1a(Result, ADesc.Rasterizer, SizeOf(ADesc.Rasterizer));
  HashBytesFNV1a(Result, ADesc.DepthStencil, SizeOf(ADesc.DepthStencil));
  HashBytesFNV1a(Result, ADesc.BlendState, SizeOf(ADesc.BlendState));
  HashBytesFNV1a(Result, ADesc.PushConstantSize, SizeOf(ADesc.PushConstantSize));
  HashBytesFNV1a(Result, ADesc.PushConstantStages, SizeOf(ADesc.PushConstantStages));
  HashBytesFNV1a(Result, ADesc.DepthAttachmentFormat, SizeOf(ADesc.DepthAttachmentFormat));
  HashBytesFNV1a(Result, ADesc.SampleCount, SizeOf(ADesc.SampleCount));

  for I := 0 to High(ADesc.VertexInput.Bindings) do
    HashBytesFNV1a(Result, ADesc.VertexInput.Bindings[I], SizeOf(TRHIVertexBindingDesc));

  for I := 0 to High(ADesc.VertexInput.Attributes) do
  begin
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Location, SizeOf(Cardinal));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Binding, SizeOf(Cardinal));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Format, SizeOf(TRHIVertexAttributeFormat));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Offset, SizeOf(Cardinal));
  end;

  for I := 0 to High(ADesc.ColorAttachmentFormats) do
    HashBytesFNV1a(Result, ADesc.ColorAttachmentFormats[I], SizeOf(TRHIPixelFormat));
end;

procedure SavePipelineCacheBlobToStream(const AStream: TStream;
  const AVendorId, ADeviceId: Cardinal; const AData: Pointer; const ASize: PtrUInt);
var
  Header: TPipelineCacheDiskHeader;
  HashVal: UInt64;
begin
  if (AStream = nil) or (AData = nil) or (ASize = 0) then Exit;

  HashVal := FNV1aOffsetBasis64;
  HashBytesFNV1a(HashVal, AData^, ASize);

  FillChar(Header, SizeOf(Header), 0);
  Header.Magic := PipelineCacheDiskMagic;
  Header.Version := PipelineCacheDiskVersion;
  Header.VendorId := AVendorId;
  Header.DeviceId := ADeviceId;
  Header.DataSize := Cardinal(ASize);
  Header.DataHash := HashVal;

  AStream.WriteBuffer(Header, SizeOf(Header));
  AStream.WriteBuffer(AData^, ASize);
end;

function LoadPipelineCacheBlobFromStream(const AStream: TStream;
  const AExpectedVendorId, AExpectedDeviceId: Cardinal; out ABlob: TBytes): Boolean;
var
  Header: TPipelineCacheDiskHeader;
  ComputedHash: UInt64;
begin
  SetLength(ABlob, 0);
  if (AStream = nil) or (AStream.Size - AStream.Position < SizeOf(Header)) then
    Exit(False);

  AStream.ReadBuffer(Header, SizeOf(Header));
  if (Header.Magic <> PipelineCacheDiskMagic) or
     (Header.Version <> PipelineCacheDiskVersion) or
     (Header.DataSize = 0) or
     ((AExpectedVendorId <> 0) and (Header.VendorId <> AExpectedVendorId)) or
     ((AExpectedDeviceId <> 0) and (Header.DeviceId <> AExpectedDeviceId)) or
     (AStream.Size - AStream.Position < Header.DataSize) then
    Exit(False);

  SetLength(ABlob, Header.DataSize);
  AStream.ReadBuffer(ABlob[0], Header.DataSize);

  ComputedHash := FNV1aOffsetBasis64;
  HashBytesFNV1a(ComputedHash, ABlob[0], Header.DataSize);
  if ComputedHash <> Header.DataHash then
  begin
    SetLength(ABlob, 0);
    Exit(False);
  end;

  Result := True;
end;

{ ---------------------------------------------------------------------------- }
{ Type Conversion Helpers (RHI <-> Vulkan)                                     }
{ ---------------------------------------------------------------------------- }

procedure CheckVk(const Res: VkResult; const Context: String);
begin
  if Res <> VK_SUCCESS then
    raise ERHIError.CreateFmt('Vulkan error (%d) in %s', [ Ord(Res), Context ]);
end;

function RHIToVkFormat(const Format: TRHIPixelFormat): VkFormat;
begin
  case Format of
    pfR8_UNorm:           Result := VK_FORMAT_R8_UNORM;
    pfRG8_UNorm:          Result := VK_FORMAT_R8G8_UNORM;
    pfRGBA8_UNorm:        Result := VK_FORMAT_R8G8B8A8_UNORM;
    pfRGBA8_sRGB:         Result := VK_FORMAT_R8G8B8A8_SRGB;
    pfBGRA8_UNorm:        Result := VK_FORMAT_B8G8R8A8_UNORM;
    pfBGRA8_sRGB:         Result := VK_FORMAT_B8G8R8A8_SRGB;
    pfRG16_Float:         Result := VK_FORMAT_R16G16_SFLOAT;
    pfRGBA16_Float:       Result := VK_FORMAT_R16G16B16A16_SFLOAT;
    pfR32_Float:          Result := VK_FORMAT_R32_SFLOAT;
    pfRGBA32_Float:       Result := VK_FORMAT_R32G32B32A32_SFLOAT;
    pfD16_UNorm:          Result := VK_FORMAT_D16_UNORM;
    pfD24_UNorm_S8_UInt:  Result := VK_FORMAT_D24_UNORM_S8_UINT;
    pfD32_Float:          Result := VK_FORMAT_D32_SFLOAT;
    pfD32_Float_S8_UInt:  Result := VK_FORMAT_D32_SFLOAT_S8_UINT;
    pfBC1_RGBA_UNorm:     Result := VK_FORMAT_BC1_RGBA_UNORM_BLOCK;
    pfBC1_RGBA_sRGB:      Result := VK_FORMAT_BC1_RGBA_SRGB_BLOCK;
    pfBC3_RGBA_UNorm:     Result := VK_FORMAT_BC3_UNORM_BLOCK;
    pfBC3_RGBA_sRGB:      Result := VK_FORMAT_BC3_SRGB_BLOCK;
    pfBC5_RG_UNorm:       Result := VK_FORMAT_BC5_UNORM_BLOCK;
    pfBC7_RGBA_UNorm:     Result := VK_FORMAT_BC7_UNORM_BLOCK;
    pfBC7_RGBA_sRGB:      Result := VK_FORMAT_BC7_SRGB_BLOCK;
    pfASTC_4x4_UNorm:     Result := VK_FORMAT_ASTC_4x4_UNORM_BLOCK;
    pfASTC_4x4_sRGB:      Result := VK_FORMAT_ASTC_4x4_SRGB_BLOCK;
    pfETC2_RGB8_UNorm:    Result := VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK;
    pfETC2_RGBA8_UNorm:   Result := VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK;
    else                  Result := VK_FORMAT_UNDEFINED;
  end;
end;

function RHIToVkVertexFormat(const Format: TRHIVertexAttributeFormat): VkFormat;
begin
  case Format of
    vafFloat:            Result := VK_FORMAT_R32_SFLOAT;
    vafVector2:          Result := VK_FORMAT_R32G32_SFLOAT;
    vafVector3:          Result := VK_FORMAT_R32G32B32_SFLOAT;
    vafVector4:          Result := VK_FORMAT_R32G32B32A32_SFLOAT;
    vafByte4Normalized,
    vafUByte4Normalized: Result := VK_FORMAT_R8G8B8A8_UNORM;
    else                 Result := VK_FORMAT_R32G32B32A32_SFLOAT;
  end;
end;

function RHIToVkTopology(const Topology: TRHIPrimitiveTopology): VkPrimitiveTopology;
begin
  case Topology of
    ptPointList:     Result := VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
    ptLineList:      Result := VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    ptLineStrip:     Result := VK_PRIMITIVE_TOPOLOGY_LINE_STRIP;
    ptTriangleList:  Result := VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    ptTriangleStrip: Result := VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
    else             Result := VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
  end;
end;

function RHIToVkPolygonMode(const Mode: TRHIPolygonMode): VkPolygonMode;
begin
  case Mode of
    pmFill:  Result := VK_POLYGON_MODE_FILL;
    pmLine:  Result := VK_POLYGON_MODE_LINE;
    pmPoint: Result := VK_POLYGON_MODE_POINT;
    else     Result := VK_POLYGON_MODE_FILL;
  end;
end;

function RHIToVkCullMode(const Mode: TRHICullMode): VkCullModeFlags;
begin
  case Mode of
    cmNone:  Result := VK_CULL_MODE_NONE;
    cmFront: Result := VK_CULL_MODE_FRONT_BIT;
    cmBack:  Result := VK_CULL_MODE_BACK_BIT;
    else     Result := VK_CULL_MODE_NONE;
  end;
end;

function RHIToVkFrontFace(const Face: TRHIFrontFace): VkFrontFace;
begin
  if Face = ffClockwise then
    Result := VK_FRONT_FACE_CLOCKWISE
  else
    Result := VK_FRONT_FACE_COUNTER_CLOCKWISE;
end;

function RHIToVkCompareOp(const Op: TRHICompareOp): VkCompareOp;
begin
  case Op of
    coNever:          Result := VK_COMPARE_OP_NEVER;
    coLess:           Result := VK_COMPARE_OP_LESS;
    coEqual:          Result := VK_COMPARE_OP_EQUAL;
    coLessOrEqual:    Result := VK_COMPARE_OP_LESS_OR_EQUAL;
    coGreater:        Result := VK_COMPARE_OP_GREATER;
    coNotEqual:       Result := VK_COMPARE_OP_NOT_EQUAL;
    coGreaterOrEqual: Result := VK_COMPARE_OP_GREATER_OR_EQUAL;
    coAlways:         Result := VK_COMPARE_OP_ALWAYS;
    else              Result := VK_COMPARE_OP_LESS_OR_EQUAL;
  end;
end;

function RHIToVkBlendFactor(const Factor: TRHIBlendFactor): Integer;
begin
  case Factor of
    bfZero:             Result := VK_BLEND_FACTOR_ZERO;
    bfOne:              Result := VK_BLEND_FACTOR_ONE;
    bfSrcColor:         Result := VK_BLEND_FACTOR_SRC_COLOR;
    bfOneMinusSrcColor: Result := VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR;
    bfDstColor:         Result := VK_BLEND_FACTOR_DST_COLOR;
    bfOneMinusDstColor: Result := VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR;
    bfSrcAlpha:         Result := VK_BLEND_FACTOR_SRC_ALPHA;
    bfOneMinusSrcAlpha: Result := VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    bfDstAlpha:         Result := VK_BLEND_FACTOR_DST_ALPHA;
    bfOneMinusDstAlpha: Result := VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA;
    else                Result := VK_BLEND_FACTOR_ONE;
  end;
end;

function RHIToVkBlendOp(const Op: TRHIBlendOp): Integer;
begin
  case Op of
    boAdd:             Result := VK_BLEND_OP_ADD;
    boSubtract:        Result := VK_BLEND_OP_SUBTRACT;
    boReverseSubtract: Result := VK_BLEND_OP_REVERSE_SUBTRACT;
    boMin:             Result := VK_BLEND_OP_MIN;
    boMax:             Result := VK_BLEND_OP_MAX;
    else               Result := VK_BLEND_OP_ADD;
  end;
end;

function RHIToVkShaderStageFlags(const Stages: TRHIShaderStageFlags): VkShaderStageFlags;
begin
  Result := 0;
  if ssVertex in Stages then Result := Result or VK_SHADER_STAGE_VERTEX_BIT;
  if ssFragment in Stages then Result := Result or VK_SHADER_STAGE_FRAGMENT_BIT;
  if ssGeometry in Stages then Result := Result or VK_SHADER_STAGE_GEOMETRY_BIT;
  if ssCompute in Stages then Result := Result or VK_SHADER_STAGE_COMPUTE_BIT;
end;

procedure RHIStateToVkLayoutAndAccess(const State: TRHIResourceState;
  out Layout: VkImageLayout; out Access: VkAccessFlags; out Stage: VkPipelineStageFlags);
begin
  case State of
    rsUndefined:
      begin
        Layout := VK_IMAGE_LAYOUT_UNDEFINED;
        Access := 0;
        Stage  := VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
      end;
    rsTransferDst:
      begin
        Layout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        Access := VK_ACCESS_TRANSFER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_TRANSFER_BIT;
      end;
    rsTransferSrc:
      begin
        Layout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        Access := VK_ACCESS_TRANSFER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_TRANSFER_BIT;
      end;
    rsShaderRead:
      begin
        Layout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        Access := VK_ACCESS_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
      end;
    rsColorAttachment:
      begin
        Layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        Access := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
      end;
    rsDepthStencilWrite:
      begin
        Layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        Access := VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
      end;
    rsDepthStencilRead:
      begin
        Layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL;
        Access := VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT or VK_ACCESS_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
      end;
    rsPresent:
      begin
        Layout := VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        Access := 0;
        Stage  := VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
      end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHIBuffer                                                             }
{ ---------------------------------------------------------------------------- }

function TVulkanRHIBuffer.VulkanDevice: TVulkanRHIDevice;
begin
  Result := TVulkanRHIDevice(Device);
end;

constructor TVulkanRHIBuffer.Create(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHIBufferDesc; const InitialData: Pointer);
var
  BufInfo: VkBufferCreateInfo;
  MemReq: VkMemoryRequirements;
  AllocInfo: VkMemoryAllocateInfo;
  MemProps: VkMemoryPropertyFlags;
begin
  inherited Create(ADevice, ADesc);

  FillChar(BufInfo, SizeOf(BufInfo), 0);
  BufInfo.sType := VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
  BufInfo.size := ADesc.Size;
  BufInfo.sharingMode := VK_SHARING_MODE_EXCLUSIVE;

  if buVertex in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
  if buIndex in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
  if buUniform in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
  if buStorage in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
  if buIndirect in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
  if (buTransferSrc in ADesc.Usage) then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
  if (buTransferDst in ADesc.Usage) or (ADesc.MemoryUsage = muGpuOnly) then
    BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_TRANSFER_DST_BIT;

  CheckVk(vkCreateBuffer(ADevice.Handle, @BufInfo, nil, @FHandle), 'vkCreateBuffer');

  vkGetBufferMemoryRequirements(ADevice.Handle, FHandle, @MemReq);

  case ADesc.MemoryUsage of
    muGpuOnly:  MemProps := VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    muCpuToGpu: MemProps := VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    muGpuToCpu: MemProps := VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
  end;

  { Note: Production code replaces raw vkAllocateMemory with TCastleVulkanMemoryAllocator }
  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  AllocInfo.allocationSize := MemReq.size;
  AllocInfo.memoryTypeIndex := ADevice.FindMemoryType(MemReq.memoryTypeBits, MemProps);

  CheckVk(vkAllocateMemory(ADevice.Handle, @AllocInfo, nil, @FDeviceMemory), 'vkAllocateMemory(Buffer)');
  CheckVk(vkBindBufferMemory(ADevice.Handle, FHandle, FDeviceMemory, 0), 'vkBindBufferMemory');
  FAllocatedSize := MemReq.size;
  Inc(ADevice.FAllocatedMemoryBytes, FAllocatedSize);

  if InitialData <> nil then
    UploadData(InitialData^, ADesc.Size, 0);
end;

destructor TVulkanRHIBuffer.Destroy;
begin
  if FMappedPtr <> nil then
    Unmap;
  if FHandle <> VK_NULL_HANDLE then
    vkDestroyBuffer(VulkanDevice.Handle, FHandle, nil);
  if FDeviceMemory <> VK_NULL_HANDLE then
  begin
    vkFreeMemory(VulkanDevice.Handle, FDeviceMemory, nil);
    if VulkanDevice <> nil then
      Dec(VulkanDevice.FAllocatedMemoryBytes, FAllocatedSize);
  end;
  inherited;
end;

function TVulkanRHIBuffer.Map: Pointer;
begin
  if FMappedPtr = nil then
    CheckVk(vkMapMemory(VulkanDevice.Handle, FDeviceMemory, FMemoryOffset, FDesc.Size, 0, @FMappedPtr), 'vkMapMemory');
  Result := FMappedPtr;
end;

procedure TVulkanRHIBuffer.Unmap;
begin
  if FMappedPtr <> nil then
  begin
    vkUnmapMemory(VulkanDevice.Handle, FDeviceMemory);
    FMappedPtr := nil;
  end;
end;

procedure TVulkanRHIBuffer.UploadData(const Data; const Size: PtrUInt; const Offset: PtrUInt);
var
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  CopyRegion: VkBufferCopy;
  DestPtr: PByte;
begin
  if FDesc.MemoryUsage = muCpuToGpu then
  begin
    DestPtr := PByte(Map);
    Inc(DestPtr, Offset);
    Move(Data, DestPtr^, Size);
    Unmap;
  end else
  begin
    { Upload via host-visible staging buffer }
    FillChar(StagingDesc, SizeOf(StagingDesc), 0);
    StagingDesc.Size := Size;
    StagingDesc.Usage := [buTransferSrc];
    StagingDesc.MemoryUsage := muCpuToGpu;

    StagingBuf := TVulkanRHIBuffer.Create(VulkanDevice, StagingDesc, @Data);
    try
      Cmd := VulkanDevice.BeginSingleTimeCommands;
      CopyRegion.srcOffset := 0;
      CopyRegion.dstOffset := Offset;
      CopyRegion.size := Size;
      vkCmdCopyBuffer(Cmd, StagingBuf.Handle, FHandle, 1, @CopyRegion);
      VulkanDevice.EndSingleTimeCommands(Cmd);
    finally
      FreeAndNil(StagingBuf);
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHITexture                                                            }
{ ---------------------------------------------------------------------------- }

function TVulkanRHITexture.VulkanDevice: TVulkanRHIDevice;
begin
  Result := TVulkanRHIDevice(Device);
end;

constructor TVulkanRHITexture.Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHITextureDesc);
var
  ImgInfo: VkImageCreateInfo;
  ViewInfo: VkImageViewCreateInfo;
  MemReq: VkMemoryRequirements;
  AllocInfo: VkMemoryAllocateInfo;
begin
  inherited Create(ADevice, ADesc);
  FOwnsImage := True;

  if tuDepthStencil in ADesc.Usage then
    FAspectMask := VK_IMAGE_ASPECT_DEPTH_BIT
  else
    FAspectMask := VK_IMAGE_ASPECT_COLOR_BIT;

  FillChar(ImgInfo, SizeOf(ImgInfo), 0);
  ImgInfo.sType := VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  ImgInfo.imageType := VK_IMAGE_TYPE_2D;
  if ADesc.Dimension in [tdCube, tdCubeArray] then
    ImgInfo.flags := VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
  ImgInfo.format := RHIToVkFormat(ADesc.Format);
  ImgInfo.extent.width := ADesc.Width;
  ImgInfo.extent.height := ADesc.Height;
  ImgInfo.extent.depth := 1;
  ImgInfo.mipLevels := ADesc.MipLevels;
  ImgInfo.arrayLayers := ADesc.DepthOrArrayLayers;
  ImgInfo.samples := VK_SAMPLE_COUNT_1_BIT;
  ImgInfo.tiling := VK_IMAGE_TILING_OPTIMAL;
  ImgInfo.initialLayout := VK_IMAGE_LAYOUT_UNDEFINED;

  if tuSampled in ADesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_SAMPLED_BIT;
  if tuColorAttachment in ADesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  if tuDepthStencil in ADesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
  if tuTransferSrc in ADesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  if tuTransferDst in ADesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_DST_BIT;

  CheckVk(vkCreateImage(ADevice.Handle, @ImgInfo, nil, @FImage), 'vkCreateImage');

  vkGetImageMemoryRequirements(ADevice.Handle, FImage, @MemReq);
  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  AllocInfo.allocationSize := MemReq.size;
  AllocInfo.memoryTypeIndex := ADevice.FindMemoryType(MemReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

  CheckVk(vkAllocateMemory(ADevice.Handle, @AllocInfo, nil, @FDeviceMemory), 'vkAllocateMemory(Image)');
  CheckVk(vkBindImageMemory(ADevice.Handle, FImage, FDeviceMemory, 0), 'vkBindImageMemory');
  FAllocatedSize := MemReq.size;
  Inc(ADevice.FAllocatedMemoryBytes, FAllocatedSize);

  FillChar(ViewInfo, SizeOf(ViewInfo), 0);
  ViewInfo.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  ViewInfo.image := FImage;
  case ADesc.Dimension of
    td2D: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D;
    td2DArray: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D_ARRAY;
    td3D: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_3D;
    tdCube: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_CUBE;
    tdCubeArray: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_CUBE_ARRAY;
  end;
  ViewInfo.format := ImgInfo.format;
  ViewInfo.subresourceRange.aspectMask := FAspectMask;
  ViewInfo.subresourceRange.baseMipLevel := 0;
  ViewInfo.subresourceRange.levelCount := ADesc.MipLevels;
  ViewInfo.subresourceRange.baseArrayLayer := 0;
  ViewInfo.subresourceRange.layerCount := ADesc.DepthOrArrayLayers;

  CheckVk(vkCreateImageView(ADevice.Handle, @ViewInfo, nil, @FImageView), 'vkCreateImageView');
end;

constructor TVulkanRHITexture.CreateSwapchainWrapper(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHITextureDesc; const AExistingImage: VkImage; const AExistingView: VkImageView);
begin
  inherited Create(ADevice, ADesc);
  FOwnsImage := False;
  FImage := AExistingImage;
  FImageView := AExistingView;
  FAspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
end;

destructor TVulkanRHITexture.Destroy;
begin
  if FImageView <> VK_NULL_HANDLE then
    vkDestroyImageView(VulkanDevice.Handle, FImageView, nil);
  if FOwnsImage then
  begin
    if FImage <> VK_NULL_HANDLE then
      vkDestroyImage(VulkanDevice.Handle, FImage, nil);
    if FDeviceMemory <> VK_NULL_HANDLE then
    begin
      vkFreeMemory(VulkanDevice.Handle, FDeviceMemory, nil);
      if VulkanDevice <> nil then
        Dec(VulkanDevice.FAllocatedMemoryBytes, FAllocatedSize);
    end;
  end;
  inherited;
end;

procedure TVulkanRHITexture.UploadImage(const AImage: TEncodedImage;
  const AMipLevel: Cardinal; const AArrayLayer: Cardinal);
var
  RgbaImage: TRGBAlphaImage;
  NeedsFreeRgba: Boolean;
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  Region: VkBufferImageCopy;
  Barrier: VkImageMemoryBarrier;
  DataSize: PtrUInt;
  PixelsPtr: Pointer;
begin
  if AImage = nil then Exit;
  if FImage = VK_NULL_HANDLE then Exit;

  NeedsFreeRgba := False;
  if AImage is TRGBAlphaImage then
  begin
    RgbaImage := TRGBAlphaImage(AImage);
  end else
  if AImage is TCastleImage then
  begin
    RgbaImage := TRGBAlphaImage.Create(AImage.Width, AImage.Height);
    RgbaImage.Assign(TCastleImage(AImage));
    NeedsFreeRgba := True;
  end else
    Exit;

  try
    DataSize := PtrUInt(RgbaImage.Width) * PtrUInt(RgbaImage.Height) * 4;
    PixelsPtr := RgbaImage.RawPixels;

    FillChar(StagingDesc, SizeOf(StagingDesc), 0);
    StagingDesc.Size := DataSize;
    StagingDesc.Usage := [buTransferSrc];
    StagingDesc.MemoryUsage := muCpuToGpu;

    StagingBuf := TVulkanRHIBuffer.Create(VulkanDevice, StagingDesc, PixelsPtr);
    try
      Cmd := VulkanDevice.BeginSingleTimeCommands;

      { Transition from current layout to TRANSFER_DST_OPTIMAL }
      FillChar(Barrier, SizeOf(Barrier), 0);
      Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
      Barrier.oldLayout := VK_IMAGE_LAYOUT_UNDEFINED;
      Barrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.image := FImage;
      Barrier.subresourceRange.aspectMask := FAspectMask;
      Barrier.subresourceRange.baseMipLevel := AMipLevel;
      Barrier.subresourceRange.levelCount := 1;
      Barrier.subresourceRange.baseArrayLayer := AArrayLayer;
      Barrier.subresourceRange.layerCount := 1;
      Barrier.srcAccessMask := 0;
      Barrier.dstAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;

      vkCmdPipelineBarrier(Cmd,
        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, nil, 0, nil, 1, @Barrier);

      { Copy buffer to image }
      FillChar(Region, SizeOf(Region), 0);
      Region.bufferOffset := 0;
      Region.bufferRowLength := 0;
      Region.bufferImageHeight := 0;
      Region.imageSubresource.aspectMask := FAspectMask;
      Region.imageSubresource.mipLevel := AMipLevel;
      Region.imageSubresource.baseArrayLayer := AArrayLayer;
      Region.imageSubresource.layerCount := 1;
      Region.imageOffset.x := 0;
      Region.imageOffset.y := 0;
      Region.imageOffset.z := 0;
      Region.imageExtent.width := RgbaImage.Width;
      Region.imageExtent.height := RgbaImage.Height;
      Region.imageExtent.depth := 1;

      vkCmdCopyBufferToImage(Cmd, StagingBuf.Handle, FImage,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, @Region);

      { Transition from TRANSFER_DST_OPTIMAL to SHADER_READ_ONLY_OPTIMAL }
      Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      Barrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
      Barrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
      Barrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;

      vkCmdPipelineBarrier(Cmd,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        0, 0, nil, 0, nil, 1, @Barrier);

      VulkanDevice.EndSingleTimeCommands(Cmd);
      FCurrentState := rsShaderRead;
    finally
      FreeAndNil(StagingBuf);
    end;
  finally
    if NeedsFreeRgba then
      FreeAndNil(RgbaImage);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHISampler, ShaderModule, DescriptorSetLayout, DescriptorSet, Pipeline}
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHISampler.Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHISamplerDesc);
var
  SamplerInfo: VkSamplerCreateInfo;
begin
  inherited Create(ADevice, ADesc);
  FillChar(SamplerInfo, SizeOf(SamplerInfo), 0);
  SamplerInfo.sType := VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
  SamplerInfo.magFilter := VK_FILTER_LINEAR;
  SamplerInfo.minFilter := VK_FILTER_LINEAR;
  SamplerInfo.mipmapMode := VK_SAMPLER_MIPMAP_MODE_LINEAR;
  SamplerInfo.maxLod := ADesc.MaxLod;
  CheckVk(vkCreateSampler(ADevice.Handle, @SamplerInfo, nil, @FHandle), 'vkCreateSampler');
end;

destructor TVulkanRHISampler.Destroy;
begin
  if FHandle <> VK_NULL_HANDLE then
    vkDestroySampler(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  inherited;
end;

constructor TVulkanRHIShaderModule.Create(const ADevice: TVulkanRHIDevice;
  const AStage: TRHIShaderStage; const ASPIRVBinary: Pointer;
  const ASizeInBytes: PtrUInt; const ADebugName: String);
var
  CreateInfo: VkShaderModuleCreateInfo;
begin
  inherited Create(ADevice, AStage, ADebugName);
  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  CreateInfo.codeSize := ASizeInBytes;
  CreateInfo.pCode := PUInt32(ASPIRVBinary);
  CheckVk(vkCreateShaderModule(ADevice.Handle, @CreateInfo, nil, @FHandle), 'vkCreateShaderModule');
end;

destructor TVulkanRHIShaderModule.Destroy;
begin
  if FHandle <> VK_NULL_HANDLE then
    vkDestroyShaderModule(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  inherited;
end;

constructor TVulkanRHIDescriptorSetLayout.Create(const ADevice: TVulkanRHIDevice;
  const Bindings: array of TRHIDescriptorBindingDesc);
var
  VkBindings: array of VkDescriptorSetLayoutBinding;
  LayoutInfo: VkDescriptorSetLayoutCreateInfo;
  I: Integer;
begin
  inherited Create(ADevice, '');
  SetLength(VkBindings, Length(Bindings));
  for I := 0 to High(Bindings) do
  begin
    FillChar(VkBindings[I], SizeOf(VkDescriptorSetLayoutBinding), 0);
    VkBindings[I].binding := Bindings[I].Binding;
    VkBindings[I].descriptorCount := Bindings[I].Count;
    VkBindings[I].stageFlags := RHIToVkShaderStageFlags(Bindings[I].StageFlags);
    case Bindings[I].DescriptorType of
      dtUniformBuffer:        VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
      dtUniformBufferDynamic: VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
      dtStorageBuffer:        VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
      dtCombinedImageSampler: VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    end;
  end;

  FillChar(LayoutInfo, SizeOf(LayoutInfo), 0);
  LayoutInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
  LayoutInfo.bindingCount := Length(VkBindings);
  if Length(VkBindings) > 0 then
    LayoutInfo.pBindings := @VkBindings[0];

  CheckVk(vkCreateDescriptorSetLayout(ADevice.Handle, @LayoutInfo, nil, @FHandle), 'vkCreateDescriptorSetLayout');
end;

destructor TVulkanRHIDescriptorSetLayout.Destroy;
begin
  if FHandle <> VK_NULL_HANDLE then
    vkDestroyDescriptorSetLayout(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  inherited;
end;

function TVulkanRHIDescriptorSet.VulkanDevice: TVulkanRHIDevice;
begin
  Result := TVulkanRHIDevice(Device);
end;

constructor TVulkanRHIDescriptorSet.Create(const ADevice: TVulkanRHIDevice;
  const ALayout: TVulkanRHIDescriptorSetLayout);
var
  AllocInfo: VkDescriptorSetAllocateInfo;
  SetLayoutHandle: VkDescriptorSetLayout;
begin
  inherited Create(ADevice, '');
  FLayout := ALayout;
  SetLayoutHandle := ALayout.Handle;

  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
  AllocInfo.descriptorPool := ADevice.DescriptorPool;
  AllocInfo.descriptorSetCount := 1;
  AllocInfo.pSetLayouts := @SetLayoutHandle;

  CheckVk(vkAllocateDescriptorSets(ADevice.Handle, @AllocInfo, @FHandle), 'vkAllocateDescriptorSets');
end;

destructor TVulkanRHIDescriptorSet.Destroy;
begin
  inherited;
end;

procedure TVulkanRHIDescriptorSet.BindUniformBuffer(const Binding: Cardinal;
  const Buffer: TRHIBuffer; const Offset, Range: PtrUInt);
var
  Idx: Integer;
begin
  if Buffer = nil then Exit;
  Idx := Length(FBufferInfos);
  SetLength(FBufferInfos, Idx + 1);
  FillChar(FBufferInfos[Idx], SizeOf(VkDescriptorBufferInfo), 0);
  FBufferInfos[Idx].buffer := (Buffer as TVulkanRHIBuffer).Handle;
  FBufferInfos[Idx].offset := Offset;
  if Range > 0 then
    FBufferInfos[Idx].range := Range
  else
    FBufferInfos[Idx].range := Buffer.Desc.Size - Offset;

  SetLength(FPendingWrites, Length(FPendingWrites) + 1);
  FillChar(FPendingWrites[High(FPendingWrites)], SizeOf(VkWriteDescriptorSet), 0);
  FPendingWrites[High(FPendingWrites)].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  FPendingWrites[High(FPendingWrites)].dstSet := FHandle;
  FPendingWrites[High(FPendingWrites)].dstBinding := Binding;
  FPendingWrites[High(FPendingWrites)].dstArrayElement := Idx;
  FPendingWrites[High(FPendingWrites)].descriptorCount := 1;
  FPendingWrites[High(FPendingWrites)].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
end;

procedure TVulkanRHIDescriptorSet.BindStorageBuffer(const Binding: Cardinal;
  const Buffer: TRHIBuffer; const Offset, Range: PtrUInt);
var
  Idx: Integer;
begin
  if Buffer = nil then Exit;
  Idx := Length(FBufferInfos);
  SetLength(FBufferInfos, Idx + 1);
  FillChar(FBufferInfos[Idx], SizeOf(VkDescriptorBufferInfo), 0);
  FBufferInfos[Idx].buffer := (Buffer as TVulkanRHIBuffer).Handle;
  FBufferInfos[Idx].offset := Offset;
  if Range > 0 then
    FBufferInfos[Idx].range := Range
  else
    FBufferInfos[Idx].range := Buffer.Desc.Size - Offset;

  SetLength(FPendingWrites, Length(FPendingWrites) + 1);
  FillChar(FPendingWrites[High(FPendingWrites)], SizeOf(VkWriteDescriptorSet), 0);
  FPendingWrites[High(FPendingWrites)].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  FPendingWrites[High(FPendingWrites)].dstSet := FHandle;
  FPendingWrites[High(FPendingWrites)].dstBinding := Binding;
  FPendingWrites[High(FPendingWrites)].dstArrayElement := Idx;
  FPendingWrites[High(FPendingWrites)].descriptorCount := 1;
  FPendingWrites[High(FPendingWrites)].descriptorType := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
end;

procedure TVulkanRHIDescriptorSet.BindTexture(const Binding: Cardinal;
  const Texture: TRHITexture; const Sampler: TRHISampler);
var
  Idx: Integer;
begin
  if Texture = nil then Exit;
  Idx := Length(FImageInfos);
  SetLength(FImageInfos, Idx + 1);
  FillChar(FImageInfos[Idx], SizeOf(VkDescriptorImageInfo), 0);
  if Sampler <> nil then
    FImageInfos[Idx].sampler := (Sampler as TVulkanRHISampler).Handle
  else
    FImageInfos[Idx].sampler := VK_NULL_HANDLE;
  FImageInfos[Idx].imageView := (Texture as TVulkanRHITexture).ImageView;
  FImageInfos[Idx].imageLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

  SetLength(FPendingWrites, Length(FPendingWrites) + 1);
  FillChar(FPendingWrites[High(FPendingWrites)], SizeOf(VkWriteDescriptorSet), 0);
  FPendingWrites[High(FPendingWrites)].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  FPendingWrites[High(FPendingWrites)].dstSet := FHandle;
  FPendingWrites[High(FPendingWrites)].dstBinding := Binding;
  FPendingWrites[High(FPendingWrites)].dstArrayElement := Idx;
  FPendingWrites[High(FPendingWrites)].descriptorCount := 1;
  FPendingWrites[High(FPendingWrites)].descriptorType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
end;

procedure TVulkanRHIDescriptorSet.Update;
var
  I: Integer;
begin
  if Length(FPendingWrites) > 0 then
  begin
    for I := 0 to High(FPendingWrites) do
    begin
      if FPendingWrites[I].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER then
      begin
        FPendingWrites[I].pImageInfo := @FImageInfos[FPendingWrites[I].dstArrayElement];
        FPendingWrites[I].dstArrayElement := 0;
      end else
      begin
        FPendingWrites[I].pBufferInfo := @FBufferInfos[FPendingWrites[I].dstArrayElement];
        FPendingWrites[I].dstArrayElement := 0;
      end;
    end;
    vkUpdateDescriptorSets(VulkanDevice.Handle, Length(FPendingWrites), @FPendingWrites[0], 0, nil);
    SetLength(FPendingWrites, 0);
    SetLength(FBufferInfos, 0);
    SetLength(FImageInfos, 0);
  end;
end;

constructor TVulkanRHIPipeline.Create(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHIGraphicsPipelineDesc);
var
  SetLayouts: array of VkDescriptorSetLayout;
  PushRange: VkPushConstantRange;
  LayoutInfo: VkPipelineLayoutCreateInfo;
  Stages: array[0..2] of VkPipelineShaderStageCreateInfo;
  StageCount: Cardinal;
  VertexBindings: array of VkVertexInputBindingDescription;
  VertexAttrs: array of VkVertexInputAttributeDescription;
  VertexInputInfo: VkPipelineVertexInputStateCreateInfo;
  InputAssembly: VkPipelineInputAssemblyStateCreateInfo;
  ViewportState: VkPipelineViewportStateCreateInfo;
  Rasterizer: VkPipelineRasterizationStateCreateInfo;
  Multisampling: VkPipelineMultisampleStateCreateInfo;
  DepthStencil: VkPipelineDepthStencilStateCreateInfo;
  BlendAttachments: array of VkPipelineColorBlendAttachmentState;
  ColorBlending: VkPipelineColorBlendStateCreateInfo;
  DynamicStates: array[0..2] of VkDynamicState;
  DynamicStateInfo: VkPipelineDynamicStateCreateInfo;
  ColorFormats: array of VkFormat;
  RenderingInfo: VkPipelineRenderingCreateInfoKHR;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
  I: Integer;
begin
  inherited Create(ADevice, ADesc);
  if (ADevice = nil) or (ADevice.Handle = nil) then Exit;

  { 1. Construct VkPipelineLayout from ADesc.DescriptorSetLayouts and PushConstants }
  SetLength(SetLayouts, Length(ADesc.DescriptorSetLayouts));
  for I := 0 to High(ADesc.DescriptorSetLayouts) do
    if ADesc.DescriptorSetLayouts[I] <> nil then
      SetLayouts[I] := (ADesc.DescriptorSetLayouts[I] as TVulkanRHIDescriptorSetLayout).Handle
    else
      SetLayouts[I] := VK_NULL_HANDLE;

  FillChar(LayoutInfo, SizeOf(LayoutInfo), 0);
  LayoutInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  LayoutInfo.setLayoutCount := Length(SetLayouts);
  if Length(SetLayouts) > 0 then
    LayoutInfo.pSetLayouts := @SetLayouts[0];

  if ADesc.PushConstantSize > 0 then
  begin
    FillChar(PushRange, SizeOf(PushRange), 0);
    PushRange.stageFlags := RHIToVkShaderStageFlags(ADesc.PushConstantStages);
    if PushRange.stageFlags = 0 then
      PushRange.stageFlags := VK_SHADER_STAGE_ALL_GRAPHICS;
    PushRange.offset := 0;
    PushRange.size := ADesc.PushConstantSize;
    LayoutInfo.pushConstantRangeCount := 1;
    LayoutInfo.pPushConstantRanges := @PushRange;
  end;

  CheckVk(vkCreatePipelineLayout(ADevice.Handle, @LayoutInfo, nil, @FPipelineLayout), 'vkCreatePipelineLayout');

  { 2. Shader Stages }
  StageCount := 0;
  FillChar(Stages, SizeOf(Stages), 0);
  if ADesc.VertexShader <> nil then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_VERTEX_BIT;
    Stages[StageCount].module := (ADesc.VertexShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;
  if ADesc.FragmentShader <> nil then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_FRAGMENT_BIT;
    Stages[StageCount].module := (ADesc.FragmentShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;
  if ADesc.GeometryShader <> nil then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_GEOMETRY_BIT;
    Stages[StageCount].module := (ADesc.GeometryShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;

  { 3. Vertex Input Layout }
  SetLength(VertexBindings, Length(ADesc.VertexInput.Bindings));
  for I := 0 to High(ADesc.VertexInput.Bindings) do
  begin
    VertexBindings[I].binding := ADesc.VertexInput.Bindings[I].Binding;
    VertexBindings[I].stride := ADesc.VertexInput.Bindings[I].Stride;
    if ADesc.VertexInput.Bindings[I].PerInstance then
      VertexBindings[I].inputRate := VK_VERTEX_INPUT_RATE_INSTANCE
    else
      VertexBindings[I].inputRate := VK_VERTEX_INPUT_RATE_VERTEX;
  end;

  SetLength(VertexAttrs, Length(ADesc.VertexInput.Attributes));
  for I := 0 to High(ADesc.VertexInput.Attributes) do
  begin
    VertexAttrs[I].location := ADesc.VertexInput.Attributes[I].Location;
    VertexAttrs[I].binding := ADesc.VertexInput.Attributes[I].Binding;
    VertexAttrs[I].format := RHIToVkVertexFormat(ADesc.VertexInput.Attributes[I].Format);
    VertexAttrs[I].offset := ADesc.VertexInput.Attributes[I].Offset;
  end;

  FillChar(VertexInputInfo, SizeOf(VertexInputInfo), 0);
  VertexInputInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
  VertexInputInfo.vertexBindingDescriptionCount := Length(VertexBindings);
  if Length(VertexBindings) > 0 then
    VertexInputInfo.pVertexBindingDescriptions := @VertexBindings[0];
  VertexInputInfo.vertexAttributeDescriptionCount := Length(VertexAttrs);
  if Length(VertexAttrs) > 0 then
    VertexInputInfo.pVertexAttributeDescriptions := @VertexAttrs[0];

  { 4. Fixed-function states }
  FillChar(InputAssembly, SizeOf(InputAssembly), 0);
  InputAssembly.sType := VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  InputAssembly.topology := RHIToVkTopology(ADesc.Topology);
  InputAssembly.primitiveRestartEnable := VK_FALSE;

  FillChar(ViewportState, SizeOf(ViewportState), 0);
  ViewportState.sType := VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  ViewportState.viewportCount := 1;
  ViewportState.scissorCount := 1;

  FillChar(Rasterizer, SizeOf(Rasterizer), 0);
  Rasterizer.sType := VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  Rasterizer.depthClampEnable := Ord(ADesc.Rasterizer.DepthClampEnable);
  Rasterizer.rasterizerDiscardEnable := VK_FALSE;
  Rasterizer.polygonMode := RHIToVkPolygonMode(ADesc.Rasterizer.PolygonMode);
  Rasterizer.cullMode := RHIToVkCullMode(ADesc.Rasterizer.CullMode);
  Rasterizer.frontFace := RHIToVkFrontFace(ADesc.Rasterizer.FrontFace);
  Rasterizer.depthBiasEnable := Ord(ADesc.Rasterizer.DepthBiasEnable);
  Rasterizer.lineWidth := 1.0;

  FillChar(Multisampling, SizeOf(Multisampling), 0);
  Multisampling.sType := VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  if ADesc.SampleCount > 1 then
    Multisampling.rasterizationSamples := ADesc.SampleCount
  else
    Multisampling.rasterizationSamples := VK_SAMPLE_COUNT_1_BIT;

  FillChar(DepthStencil, SizeOf(DepthStencil), 0);
  DepthStencil.sType := VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
  DepthStencil.depthTestEnable := Ord(ADesc.DepthStencil.DepthTestEnable);
  DepthStencil.depthWriteEnable := Ord(ADesc.DepthStencil.DepthWriteEnable);
  DepthStencil.depthCompareOp := RHIToVkCompareOp(ADesc.DepthStencil.DepthCompareOp);
  DepthStencil.stencilTestEnable := Ord(ADesc.DepthStencil.StencilTestEnable);

  SetLength(BlendAttachments, Max(1, Length(ADesc.ColorAttachmentFormats)));
  for I := 0 to High(BlendAttachments) do
  begin
    FillChar(BlendAttachments[I], SizeOf(VkPipelineColorBlendAttachmentState), 0);
    BlendAttachments[I].blendEnable := Ord(ADesc.BlendState.BlendEnable);
    BlendAttachments[I].srcColorBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.SrcColorBlendFactor);
    BlendAttachments[I].dstColorBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.DstColorBlendFactor);
    BlendAttachments[I].colorBlendOp := RHIToVkBlendOp(ADesc.BlendState.ColorBlendOp);
    BlendAttachments[I].srcAlphaBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.SrcAlphaBlendFactor);
    BlendAttachments[I].dstAlphaBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.DstAlphaBlendFactor);
    BlendAttachments[I].alphaBlendOp := RHIToVkBlendOp(ADesc.BlendState.AlphaBlendOp);
    if ADesc.BlendState.ColorWriteMask <> 0 then
      BlendAttachments[I].colorWriteMask := ADesc.BlendState.ColorWriteMask
    else
      BlendAttachments[I].colorWriteMask := $0F;
  end;

  FillChar(ColorBlending, SizeOf(ColorBlending), 0);
  ColorBlending.sType := VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  ColorBlending.attachmentCount := Length(BlendAttachments);
  if Length(BlendAttachments) > 0 then
    ColorBlending.pAttachments := @BlendAttachments[0];

  DynamicStates[0] := VK_DYNAMIC_STATE_VIEWPORT;
  DynamicStates[1] := VK_DYNAMIC_STATE_SCISSOR;
  DynamicStates[2] := VK_DYNAMIC_STATE_DEPTH_BIAS;
  FillChar(DynamicStateInfo, SizeOf(DynamicStateInfo), 0);
  DynamicStateInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  if ADesc.Rasterizer.DepthBiasEnable then
    DynamicStateInfo.dynamicStateCount := 3
  else
    DynamicStateInfo.dynamicStateCount := 2;
  DynamicStateInfo.pDynamicStates := @DynamicStates[0];

  { 5. Set up VkPipelineRenderingCreateInfoKHR (Vulkan 1.3 Dynamic Rendering) }
  SetLength(ColorFormats, Length(ADesc.ColorAttachmentFormats));
  for I := 0 to High(ADesc.ColorAttachmentFormats) do
    ColorFormats[I] := RHIToVkFormat(ADesc.ColorAttachmentFormats[I]);

  FillChar(RenderingInfo, SizeOf(RenderingInfo), 0);
  RenderingInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;
  RenderingInfo.colorAttachmentCount := Length(ColorFormats);
  if Length(ColorFormats) > 0 then
    RenderingInfo.pColorAttachmentFormats := @ColorFormats[0];
  RenderingInfo.depthAttachmentFormat := RHIToVkFormat(ADesc.DepthAttachmentFormat);

  { 6. Create Graphics Pipeline }
  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PipelineInfo.pNext := @RenderingInfo;
  PipelineInfo.stageCount := StageCount;
  if StageCount > 0 then
    PipelineInfo.pStages := @Stages[0];
  PipelineInfo.pVertexInputState := @VertexInputInfo;
  PipelineInfo.pInputAssemblyState := @InputAssembly;
  PipelineInfo.pViewportState := @ViewportState;
  PipelineInfo.pRasterizationState := @Rasterizer;
  PipelineInfo.pMultisampleState := @Multisampling;
  PipelineInfo.pDepthStencilState := @DepthStencil;
  PipelineInfo.pColorBlendState := @ColorBlending;
  PipelineInfo.pDynamicState := @DynamicStateInfo;
  PipelineInfo.layout := FPipelineLayout;

  CheckVk(vkCreateGraphicsPipelines(ADevice.Handle, ADevice.PipelineCache, 1, @PipelineInfo, nil, @FHandle), 'vkCreateGraphicsPipelines');
end;

destructor TVulkanRHIPipeline.Destroy;
begin
  if FHandle <> VK_NULL_HANDLE then
    vkDestroyPipeline(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  if FPipelineLayout <> VK_NULL_HANDLE then
    vkDestroyPipelineLayout(TVulkanRHIDevice(Device).Handle, FPipelineLayout, nil);
  inherited;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHICommandList                                                        }
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHICommandList.Create(const ADevice: TVulkanRHIDevice;
  const AQueueFamilyIndex: Cardinal; const ALevel: TRHICommandListLevel);
var
  PoolInfo: VkCommandPoolCreateInfo;
  AllocInfo: VkCommandBufferAllocateInfo;
begin
  inherited Create(ALevel);
  FDevice := ADevice;

  FillChar(PoolInfo, SizeOf(PoolInfo), 0);
  PoolInfo.sType := VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  PoolInfo.flags := VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  PoolInfo.queueFamilyIndex := AQueueFamilyIndex;
  CheckVk(vkCreateCommandPool(FDevice.Handle, @PoolInfo, nil, @FCommandPool), 'vkCreateCommandPool');

  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  AllocInfo.commandPool := FCommandPool;
  if ALevel = cllSecondary then
    AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_SECONDARY
  else
    AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  AllocInfo.commandBufferCount := 1;
  CheckVk(vkAllocateCommandBuffers(FDevice.Handle, @AllocInfo, @FHandle), 'vkAllocateCommandBuffers');
end;

destructor TVulkanRHICommandList.Destroy;
begin
  if FCommandPool <> VK_NULL_HANDLE then
    vkDestroyCommandPool(FDevice.Handle, FCommandPool, nil);
  inherited;
end;

procedure TVulkanRHICommandList.BeginRecording;
var
  BeginInfo: VkCommandBufferBeginInfo;
  InheritanceInfo: VkCommandBufferInheritanceInfo;
begin
  CheckVk(vkResetCommandBuffer(FHandle, 0), 'vkResetCommandBuffer');
  FillChar(BeginInfo, SizeOf(BeginInfo), 0);
  BeginInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  BeginInfo.flags := VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  if FLevel = cllSecondary then
  begin
    BeginInfo.flags := BeginInfo.flags or VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT;
    FillChar(InheritanceInfo, SizeOf(InheritanceInfo), 0);
    InheritanceInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO;
    BeginInfo.pInheritanceInfo := @InheritanceInfo;
  end;
  CheckVk(vkBeginCommandBuffer(FHandle, @BeginInfo), 'vkBeginCommandBuffer');
  FCurrentPipeline := nil;
end;

procedure TVulkanRHICommandList.EndRecording;
begin
  CheckVk(vkEndCommandBuffer(FHandle), 'vkEndCommandBuffer');
end;

procedure TVulkanRHICommandList.TransitionTexture(const Texture: TRHITexture;
  const NewState: TRHIResourceState);
var
  VkTex: TVulkanRHITexture;
  Barrier: VkImageMemoryBarrier;
  SrcStage, DstStage: VkPipelineStageFlags;
begin
  if Texture.CurrentState = NewState then
    Exit;

  VkTex := Texture as TVulkanRHITexture;
  FillChar(Barrier, SizeOf(Barrier), 0);
  Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  RHIStateToVkLayoutAndAccess(Texture.CurrentState, Barrier.oldLayout, Barrier.srcAccessMask, SrcStage);
  RHIStateToVkLayoutAndAccess(NewState, Barrier.newLayout, Barrier.dstAccessMask, DstStage);

  Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.image := VkTex.Image;
  Barrier.subresourceRange.aspectMask := VkTex.AspectMask;
  Barrier.subresourceRange.baseMipLevel := 0;
  Barrier.subresourceRange.levelCount := VkTex.Desc.MipLevels;
  Barrier.subresourceRange.baseArrayLayer := 0;
  Barrier.subresourceRange.layerCount := VkTex.Desc.DepthOrArrayLayers;

  vkCmdPipelineBarrier(FHandle, SrcStage, DstStage, 0, 0, nil, 0, nil, 1, @Barrier);
  Texture.CurrentState := NewState;
end;

procedure TVulkanRHICommandList.GenerateMipmaps(const Texture: TRHITexture);
var
  VkTex: TVulkanRHITexture;
  Barrier: VkImageMemoryBarrier;
  Blit: VkImageBlit;
  MipWidth, MipHeight, NextWidth, NextHeight: Integer;
  I: Cardinal;
begin
  if (Texture = nil) or (Texture.Desc.MipLevels <= 1) or not Assigned(vkCmdBlitImage) then
    Exit;

  VkTex := Texture as TVulkanRHITexture;
  MipWidth := Integer(VkTex.Desc.Width);
  MipHeight := Integer(VkTex.Desc.Height);

  FillChar(Barrier, SizeOf(Barrier), 0);
  Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  Barrier.image := VkTex.Image;
  Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.subresourceRange.aspectMask := VkTex.AspectMask;
  Barrier.subresourceRange.baseArrayLayer := 0;
  Barrier.subresourceRange.layerCount := VkTex.Desc.DepthOrArrayLayers;
  Barrier.subresourceRange.levelCount := 1;

  for I := 1 to VkTex.Desc.MipLevels - 1 do
  begin
    Barrier.subresourceRange.baseMipLevel := I - 1;
    Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    Barrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    Barrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
    Barrier.dstAccessMask := VK_ACCESS_TRANSFER_READ_BIT;

    vkCmdPipelineBarrier(FHandle,
      VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
      0, 0, nil, 0, nil, 1, @Barrier);

    NextWidth := Max(1, MipWidth div 2);
    NextHeight := Max(1, MipHeight div 2);

    FillChar(Blit, SizeOf(Blit), 0);
    Blit.srcOffsets[1].x := MipWidth;
    Blit.srcOffsets[1].y := MipHeight;
    Blit.srcOffsets[1].z := 1;
    Blit.srcSubresource.aspectMask := VkTex.AspectMask;
    Blit.srcSubresource.mipLevel := I - 1;
    Blit.srcSubresource.baseArrayLayer := 0;
    Blit.srcSubresource.layerCount := VkTex.Desc.DepthOrArrayLayers;

    Blit.dstOffsets[1].x := NextWidth;
    Blit.dstOffsets[1].y := NextHeight;
    Blit.dstOffsets[1].z := 1;
    Blit.dstSubresource.aspectMask := VkTex.AspectMask;
    Blit.dstSubresource.mipLevel := I;
    Blit.dstSubresource.baseArrayLayer := 0;
    Blit.dstSubresource.layerCount := VkTex.Desc.DepthOrArrayLayers;

    vkCmdBlitImage(FHandle,
      VkTex.Image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      VkTex.Image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      1, @Blit, VK_FILTER_LINEAR);

    Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    Barrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    Barrier.srcAccessMask := VK_ACCESS_TRANSFER_READ_BIT;
    Barrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(FHandle,
      VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      0, 0, nil, 0, nil, 1, @Barrier);

    MipWidth := NextWidth;
    MipHeight := NextHeight;
  end;

  Barrier.subresourceRange.baseMipLevel := VkTex.Desc.MipLevels - 1;
  Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
  Barrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
  Barrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
  Barrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;

  vkCmdPipelineBarrier(FHandle,
    VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
    0, 0, nil, 0, nil, 1, @Barrier);

  Texture.CurrentState := rsShaderRead;
end;

procedure TVulkanRHICommandList.BeginRendering(const Info: TRHIRenderingInfo);
var
  RenderInfo: VkRenderingInfo;
  ColorAttachments: array of VkRenderingAttachmentInfo;
  DepthAttachment: VkRenderingAttachmentInfo;
  I: Integer;
begin
  SetLength(ColorAttachments, Length(Info.ColorAttachments));
  for I := 0 to High(Info.ColorAttachments) do
  begin
    FillChar(ColorAttachments[I], SizeOf(VkRenderingAttachmentInfo), 0);
    ColorAttachments[I].sType := VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
    ColorAttachments[I].imageView := (Info.ColorAttachments[I].Texture as TVulkanRHITexture).ImageView;
    ColorAttachments[I].imageLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    if Info.ColorAttachments[I].LoadOp = loClear then
      ColorAttachments[I].loadOp := VK_ATTACHMENT_LOAD_OP_CLEAR
    else
      ColorAttachments[I].loadOp := VK_ATTACHMENT_LOAD_OP_LOAD;
    if Info.ColorAttachments[I].StoreOp = soDontCare then
      ColorAttachments[I].storeOp := VK_ATTACHMENT_STORE_OP_DONT_CARE
    else
      ColorAttachments[I].storeOp := VK_ATTACHMENT_STORE_OP_STORE;
    Move(Info.ColorAttachments[I].ClearColor.Data, ColorAttachments[I].clearValue.color.float32, SizeOf( Single) * 4);
  end;

  FillChar(RenderInfo, SizeOf(RenderInfo), 0);
  RenderInfo.sType := VK_STRUCTURE_TYPE_RENDERING_INFO;
  RenderInfo.renderArea.offset.x := Info.RenderArea.Left;
  RenderInfo.renderArea.offset.y := Info.RenderArea.Bottom;
  RenderInfo.renderArea.extent.width := Info.RenderArea.Width;
  RenderInfo.renderArea.extent.height := Info.RenderArea.Height;
  RenderInfo.layerCount := 1;
  RenderInfo.colorAttachmentCount := Length(ColorAttachments);
  if Length(ColorAttachments) > 0 then
    RenderInfo.pColorAttachments := @ColorAttachments[0];

  if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
  begin
    FillChar(DepthAttachment, SizeOf(DepthAttachment), 0);
    DepthAttachment.sType := VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
    DepthAttachment.imageView := (Info.DepthAttachment.Texture as TVulkanRHITexture).ImageView;
    DepthAttachment.imageLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    if Info.DepthAttachment.LoadOp = loClear then
      DepthAttachment.loadOp := VK_ATTACHMENT_LOAD_OP_CLEAR
    else
      DepthAttachment.loadOp := VK_ATTACHMENT_LOAD_OP_LOAD;
    if Info.DepthAttachment.StoreOp = soDontCare then
      DepthAttachment.storeOp := VK_ATTACHMENT_STORE_OP_DONT_CARE
    else
      DepthAttachment.storeOp := VK_ATTACHMENT_STORE_OP_STORE;
    DepthAttachment.clearValue.depthStencil.depth := Info.DepthAttachment.ClearDepth;
    DepthAttachment.clearValue.depthStencil.stencil := Info.DepthAttachment.ClearStencil;
    RenderInfo.pDepthAttachment := @DepthAttachment;
  end;

  vkCmdBeginRendering(FHandle, @RenderInfo);
end;

procedure TVulkanRHICommandList.EndRendering;
begin
  vkCmdEndRendering(FHandle);
end;

procedure TVulkanRHICommandList.SetViewport(const ViewportRect: TFloatRectangle;
  const MinDepth, MaxDepth: Single);
var
  VkVP: VkViewport;
begin
  { Flip Y-axis using VK_KHR_maintenance1 negative height so CGE camera matrices
    and counter-clockwise winding orders work identically to OpenGL }
  VkVP.x := ViewportRect.Left;
  VkVP.y := ViewportRect.Bottom + ViewportRect.Height;
  VkVP.width := ViewportRect.Width;
  VkVP.height := -ViewportRect.Height;
  VkVP.minDepth := MinDepth;
  VkVP.maxDepth := MaxDepth;
  vkCmdSetViewport(FHandle, 0, 1, @VkVP);
end;

procedure TVulkanRHICommandList.SetScissor(const ScissorRect: TRectangle);
var
  VkRect: VkRect2D;
begin
  VkRect.offset.x := Max(0, ScissorRect.Left);
  VkRect.offset.y := Max(0, ScissorRect.Bottom);
  VkRect.extent.width := ScissorRect.Width;
  VkRect.extent.height := ScissorRect.Height;
  vkCmdSetScissor(FHandle, 0, 1, @VkRect);
end;

procedure TVulkanRHICommandList.SetDepthBias(const ConstantFactor, SlopeFactor: Single);
begin
  vkCmdSetDepthBias(FHandle, ConstantFactor, 0.0, SlopeFactor);
end;

procedure TVulkanRHICommandList.BindPipeline(const Pipeline: TRHIPipeline);
begin
  FCurrentPipeline := Pipeline as TVulkanRHIPipeline;
  vkCmdBindPipeline(FHandle, VK_PIPELINE_BIND_POINT_GRAPHICS, FCurrentPipeline.Handle);
end;

procedure TVulkanRHICommandList.BindDescriptorSet(const SetIndex: Cardinal;
  const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal);
var
  SetHandle: VkDescriptorSet;
  OffsetPtr: PUInt32;
begin
  Assert(FCurrentPipeline <> nil, 'BindPipeline must be called before BindDescriptorSet');
  SetHandle := (DescriptorSet as TVulkanRHIDescriptorSet).Handle;
  if Length(DynamicOffsets) > 0 then
    OffsetPtr := @DynamicOffsets[0]
  else
    OffsetPtr := nil;

  vkCmdBindDescriptorSets(FHandle, VK_PIPELINE_BIND_POINT_GRAPHICS,
    FCurrentPipeline.PipelineLayout, SetIndex, 1, @SetHandle,
    Length(DynamicOffsets), OffsetPtr);
end;

procedure TVulkanRHICommandList.PushConstants(const StageFlags: TRHIShaderStageFlags;
  const Offset, Size: Cardinal; const Data);
begin
  Assert(FCurrentPipeline <> nil, 'BindPipeline must be called before PushConstants');
  vkCmdPushConstants(FHandle, FCurrentPipeline.PipelineLayout,
    RHIToVkShaderStageFlags(StageFlags), Offset, Size, @Data);
end;

procedure TVulkanRHICommandList.BindVertexBuffers(const FirstBinding: Cardinal;
  const Buffers: array of TRHIBuffer; const Offsets: array of PtrUInt);
var
  VkBuffers: array of VkBuffer;
  VkOffsets: array of VkDeviceSize;
  I: Integer;
begin
  SetLength(VkBuffers, Length(Buffers));
  SetLength(VkOffsets, Length(Offsets));
  for I := 0 to High(Buffers) do
  begin
    VkBuffers[I] := (Buffers[I] as TVulkanRHIBuffer).Handle;
    VkOffsets[I] := Offsets[I];
  end;
  vkCmdBindVertexBuffers(FHandle, FirstBinding, Length(VkBuffers), @VkBuffers[0], @VkOffsets[0]);
end;

procedure TVulkanRHICommandList.BindIndexBuffer(const Buffer: TRHIBuffer;
  const Offset: PtrUInt; const IndexType: TRHIIndexType);
var
  VkIdxType: VkIndexType;
begin
  if IndexType = itUInt16 then
    VkIdxType := VK_INDEX_TYPE_UINT16
  else
    VkIdxType := VK_INDEX_TYPE_UINT32;

  vkCmdBindIndexBuffer(FHandle, (Buffer as TVulkanRHIBuffer).Handle, Offset, VkIdxType);
end;

procedure TVulkanRHICommandList.Draw(const VertexCount, InstanceCount,
  FirstVertex, FirstInstance: Cardinal);
begin
  vkCmdDraw(FHandle, VertexCount, InstanceCount, FirstVertex, FirstInstance);
end;

procedure TVulkanRHICommandList.DrawIndexed(const IndexCount, InstanceCount,
  FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal);
begin
  vkCmdDrawIndexed(FHandle, IndexCount, InstanceCount, FirstIndex, VertexOffset, FirstInstance);
end;

procedure TVulkanRHICommandList.DrawIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount, Stride: Cardinal);
begin
  if Assigned(vkCmdDrawIndirect) and Assigned(IndirectBuffer) then
    vkCmdDrawIndirect(FHandle, (IndirectBuffer as TVulkanRHIBuffer).Handle,
      Offset, DrawCount, Stride);
end;

procedure TVulkanRHICommandList.DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount, Stride: Cardinal);
begin
  vkCmdDrawIndexedIndirect(FHandle, (IndirectBuffer as TVulkanRHIBuffer).Handle,
    Offset, DrawCount, Stride);
end;

procedure TVulkanRHICommandList.ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList);
var
  CmdBuffers: array of VkCommandBuffer;
  I: Integer;
begin
  if Length(SecondaryCommandLists) = 0 then Exit;
  SetLength(CmdBuffers, Length(SecondaryCommandLists));
  for I := 0 to High(SecondaryCommandLists) do
    CmdBuffers[I] := (SecondaryCommandLists[I] as TVulkanRHICommandList).Handle;
  vkCmdExecuteCommands(FHandle, Length(CmdBuffers), @CmdBuffers[0]);
end;

procedure TVulkanRHICommandList.PushDebugGroup(const LabelName: String; const Color: TCastleColor);
var
  LabelInfo: VkDebugUtilsLabelEXT;
  AnsiLabel: AnsiString;
begin
  if Assigned(vkCmdBeginDebugUtilsLabelEXT) and (FHandle <> nil) then
  begin
    AnsiLabel := AnsiString(LabelName);
    FillChar(LabelInfo, SizeOf(LabelInfo), 0);
    LabelInfo.sType := VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT;
    LabelInfo.pLabelName := PAnsiChar(AnsiLabel);
    Move(Color.Data, LabelInfo.color, SizeOf(Single) * 4);
    vkCmdBeginDebugUtilsLabelEXT(FHandle, @LabelInfo);
  end;
end;

procedure TVulkanRHICommandList.PopDebugGroup;
begin
  if Assigned(vkCmdEndDebugUtilsLabelEXT) and (FHandle <> nil) then
    vkCmdEndDebugUtilsLabelEXT(FHandle);
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHIDevice                                                             }
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHIDevice.Create(const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
  const InitialWidth, InitialHeight: Cardinal; const EnableValidation: Boolean);
begin
  inherited Create;
  FPipelineMap := TVulkanPipelineMap.Create([doOwnsValues]);

  LoadVulkan;
  CreateInstance(EnableValidation);

  FSurface := ACreateSurfaceCallback(FInstance);
  if FSurface = VK_NULL_HANDLE then
    raise ERHIError.Create('Failed to create Vulkan window surface (VkSurfaceKHR)');

  PickPhysicalDevice;
  CreateLogicalDevice;
  CreateDescriptorPool;
  CreateFrameContexts;
  CreateSwapchain(InitialWidth, InitialHeight);
end;

constructor TVulkanRHIDevice.CreateHeadless(const APhysicalDevice: VkPhysicalDevice;
  const ASupportsMemoryBudgetExt: Boolean);
begin
  inherited Create;
  FPipelineMap := TVulkanPipelineMap.Create([doOwnsValues]);
  FCapabilities.Backend := rbVulkan;
  FPhysicalDevice := APhysicalDevice;
  FSupportsMemoryBudgetExt := ASupportsMemoryBudgetExt;
end;

destructor TVulkanRHIDevice.Destroy;
var
  I: Integer;
begin
  SetActiveCommandList(nil);
  WaitIdle;
  DestroySwapchain;
  FreeAndNil(FPipelineMap);

  for I := 0 to MaxFramesInFlight - 1 do
  begin
    FreeAndNil(FFrames[I].CommandList);
    if (FDevice <> nil) and (FFrames[I].ImageAvailableSemaphore <> VK_NULL_HANDLE) then
      vkDestroySemaphore(FDevice, FFrames[I].ImageAvailableSemaphore, nil);
    if (FDevice <> nil) and (FFrames[I].RenderFinishedSemaphore <> VK_NULL_HANDLE) then
      vkDestroySemaphore(FDevice, FFrames[I].RenderFinishedSemaphore, nil);
    if (FDevice <> nil) and (FFrames[I].InFlightFence <> VK_NULL_HANDLE) then
      vkDestroyFence(FDevice, FFrames[I].InFlightFence, nil);
  end;

  if (FDevice <> nil) and (FDescriptorPool <> VK_NULL_HANDLE) then
    vkDestroyDescriptorPool(FDevice, FDescriptorPool, nil);
  if (FDevice <> nil) and (FPipelineCache <> VK_NULL_HANDLE) then
    vkDestroyPipelineCache(FDevice, FPipelineCache, nil);
  if FDevice <> nil then
    vkDestroyDevice(FDevice, nil);
  if (FInstance <> nil) and (FSurface <> VK_NULL_HANDLE) then
    vkDestroySurfaceKHR(FInstance, FSurface, nil);
  if FInstance <> nil then
    vkDestroyInstance(FInstance, nil);

  inherited;
end;

procedure TVulkanRHIDevice.CreateInstance(const EnableValidation: Boolean);
var
  AppInfo: VkApplicationInfo;
  CreateInfo: VkInstanceCreateInfo;
  ExtNames: TAnsiStringArray;
  ExtPtrs: array of PAnsiChar;
  LayerName: PAnsiChar;
  I: Integer;
  Res: VkResult;
begin
  FillChar(AppInfo, SizeOf(AppInfo), 0);
  AppInfo.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
  AppInfo.pApplicationName := 'Castle Game Engine Application';
  AppInfo.applicationVersion := VK_API_VERSION_1_0;
  AppInfo.pEngineName := 'Castle Game Engine';
  AppInfo.engineVersion := VK_API_VERSION_1_3;
  AppInfo.apiVersion := VK_API_VERSION_1_3;

  ExtNames := GetRequiredVulkanInstanceExtensions;
  SetLength(ExtPtrs, Length(ExtNames));
  for I := 0 to High(ExtNames) do
    ExtPtrs[I] := PAnsiChar(ExtNames[I]);

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  CreateInfo.pApplicationInfo := @AppInfo;
  CreateInfo.enabledExtensionCount := Length(ExtPtrs);
  if Length(ExtPtrs) > 0 then
    CreateInfo.ppEnabledExtensionNames := @ExtPtrs[0];

  LayerName := VK_LAYER_KHRONOS_validation;
  if EnableValidation then
  begin
    CreateInfo.enabledLayerCount := 1;
    CreateInfo.ppEnabledLayerNames := @LayerName;
  end;

  Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
  if (Res = VK_ERROR_LAYER_NOT_PRESENT) and EnableValidation then
  begin
    CreateInfo.enabledLayerCount := 0;
    CreateInfo.ppEnabledLayerNames := nil;
    Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
  end;
  CheckVk(Res, 'vkCreateInstance');
  LoadVulkanInstance(FInstance);
end;

procedure TVulkanRHIDevice.PickPhysicalDevice;
var
  DeviceCount, I: Cardinal;
  Devices: array of VkPhysicalDevice;
  Props, ChosenProps: VkPhysicalDeviceProperties;
  Features: VkPhysicalDeviceFeatures;
begin
  DeviceCount := 0;
  CheckVk(vkEnumeratePhysicalDevices(FInstance, @DeviceCount, nil), 'vkEnumeratePhysicalDevices(count)');
  if DeviceCount = 0 then
    raise ERHIError.Create('No Vulkan physical devices found');

  SetLength(Devices, DeviceCount);
  CheckVk(vkEnumeratePhysicalDevices(FInstance, @DeviceCount, @Devices[0]), 'vkEnumeratePhysicalDevices');

  FPhysicalDevice := Devices[0];
  for I := 0 to DeviceCount - 1 do
  begin
    vkGetPhysicalDeviceProperties(Devices[I], @Props);
    if Props.deviceType = VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU then
    begin
      FPhysicalDevice := Devices[I];
      Break;
    end;
  end;

  vkGetPhysicalDeviceProperties(FPhysicalDevice, @ChosenProps);
  vkGetPhysicalDeviceFeatures(FPhysicalDevice, @Features);

  FDeviceId := ChosenProps.deviceID;
  FCapabilities.Backend := rbVulkan;
  FCapabilities.DeviceName := String(PAnsiChar(@ChosenProps.deviceName[0]));
  FCapabilities.VendorId := ChosenProps.vendorID;
  FCapabilities.MaxTextureSize := ChosenProps.limits.maxImageDimension2D;
  FCapabilities.MaxAnisotropy := ChosenProps.limits.maxSamplerAnisotropy;
  FCapabilities.MaxUniformBufferRange := ChosenProps.limits.maxUniformBufferRange;
  FCapabilities.MinUniformBufferOffsetAlignment := Cardinal(ChosenProps.limits.minUniformBufferOffsetAlignment);
  FCapabilities.MaxPushConstantsSize := ChosenProps.limits.maxPushConstantsSize;
  FCapabilities.SupportsBCCompression := Features.textureCompressionBC = VK_TRUE;
  FCapabilities.SupportsASTCCompression := Features.textureCompressionASTC_LDR = VK_TRUE;
  FCapabilities.SupportsETC2Compression := Features.textureCompressionETC2 = VK_TRUE;
  FCapabilities.SupportsComputeShaders := True;
  FCapabilities.SupportsMultiDrawIndirect := Features.multiDrawIndirect = VK_TRUE;
end;

function TVulkanRHIDevice.IsDeviceExtensionSupported(const AExtensionName: AnsiString): Boolean;
var
  ExtCount, I: Cardinal;
  Exts: array of VkExtensionProperties;
  ExtStr: AnsiString;
begin
  Result := False;
  if (FPhysicalDevice = nil) or not Assigned(vkEnumerateDeviceExtensionProperties) then
    Exit;
  ExtCount := 0;
  if vkEnumerateDeviceExtensionProperties(FPhysicalDevice, nil, @ExtCount, nil) <> VK_SUCCESS then
    Exit;
  if ExtCount = 0 then
    Exit;
  SetLength(Exts, ExtCount);
  if vkEnumerateDeviceExtensionProperties(FPhysicalDevice, nil, @ExtCount, @Exts[0]) <> VK_SUCCESS then
    Exit;
  for I := 0 to ExtCount - 1 do
  begin
    ExtStr := PAnsiChar(@Exts[I].extensionName[0]);
    if ExtStr = AExtensionName then
      Exit(True);
  end;
end;

procedure TVulkanRHIDevice.CreateLogicalDevice;
var
  QueueCount, I, ExtCount: Cardinal;
  QueueProps: array of VkQueueFamilyProperties;
  PresentSupport: VkBool32;
  QueueInfos: array[0..1] of VkDeviceQueueCreateInfo;
  QueuePriority: Single;
  DynRenderFeatures: VkPhysicalDeviceDynamicRenderingFeatures;
  DeviceExts: array[0..1] of PAnsiChar;
  CreateInfo: VkDeviceCreateInfo;
  CacheInfo: VkPipelineCacheCreateInfo;
begin
  QueueCount := 0;
  vkGetPhysicalDeviceQueueFamilyProperties(FPhysicalDevice, @QueueCount, nil);
  SetLength(QueueProps, QueueCount);
  vkGetPhysicalDeviceQueueFamilyProperties(FPhysicalDevice, @QueueCount, @QueueProps[0]);

  FGraphicsQueueFamily := 0;
  FPresentQueueFamily := 0;
  for I := 0 to QueueCount - 1 do
  begin
    if (QueueProps[I].queueFlags and VK_QUEUE_GRAPHICS_BIT) <> 0 then
      FGraphicsQueueFamily := I;
    if (FSurface <> VK_NULL_HANDLE) and Assigned(vkGetPhysicalDeviceSurfaceSupportKHR) then
    begin
      PresentSupport := VK_FALSE;
      if vkGetPhysicalDeviceSurfaceSupportKHR(FPhysicalDevice, I, FSurface, @PresentSupport) = VK_SUCCESS then
        if PresentSupport = VK_TRUE then
          FPresentQueueFamily := I;
    end else
      FPresentQueueFamily := FGraphicsQueueFamily;
  end;

  QueuePriority := 1.0;
  FillChar(QueueInfos, SizeOf(QueueInfos), 0);
  QueueInfos[0].sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  QueueInfos[0].queueFamilyIndex := FGraphicsQueueFamily;
  QueueInfos[0].queueCount := 1;
  QueueInfos[0].pQueuePriorities := @QueuePriority;

  FillChar(DynRenderFeatures, SizeOf(DynRenderFeatures), 0);
  DynRenderFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR;
  DynRenderFeatures.dynamicRendering := VK_TRUE;

  DeviceExts[0] := VK_KHR_swapchain;
  ExtCount := 1;
  FSupportsMemoryBudgetExt := IsDeviceExtensionSupported(VK_EXT_memory_budget);
  if FSupportsMemoryBudgetExt then
  begin
    DeviceExts[1] := VK_EXT_memory_budget;
    ExtCount := 2;
  end;

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  CreateInfo.pNext := @DynRenderFeatures;
  if FPresentQueueFamily <> FGraphicsQueueFamily then
  begin
    QueueInfos[1].sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    QueueInfos[1].queueFamilyIndex := FPresentQueueFamily;
    QueueInfos[1].queueCount := 1;
    QueueInfos[1].pQueuePriorities := @QueuePriority;
    CreateInfo.queueCreateInfoCount := 2;
  end else
    CreateInfo.queueCreateInfoCount := 1;
  CreateInfo.pQueueCreateInfos := @QueueInfos[0];
  CreateInfo.enabledExtensionCount := ExtCount;
  CreateInfo.ppEnabledExtensionNames := @DeviceExts[0];

  CheckVk(vkCreateDevice(FPhysicalDevice, @CreateInfo, nil, @FDevice), 'vkCreateDevice');
  LoadVulkanDevice(FDevice);

  vkGetDeviceQueue(FDevice, FGraphicsQueueFamily, 0, @FGraphicsQueue);
  vkGetDeviceQueue(FDevice, FPresentQueueFamily, 0, @FPresentQueue);

  if Assigned(vkCreatePipelineCache) then
  begin
    FillChar(CacheInfo, SizeOf(CacheInfo), 0);
    CacheInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;
    CheckVk(vkCreatePipelineCache(FDevice, @CacheInfo, nil, @FPipelineCache), 'vkCreatePipelineCache');
  end;
end;

function TVulkanRHIDevice.QueryMemoryBudget(out AUsedBytes, ABudgetBytes: UInt64;
  out AUsedMB, ABudgetMB: Cardinal): Boolean;
begin
  Result := QueryPhysicalDeviceMemoryBudget(
    FPhysicalDevice, FSupportsMemoryBudgetExt,
    UInt64(Max(Int64(0), FAllocatedMemoryBytes)),
    AUsedBytes, ABudgetBytes, AUsedMB, ABudgetMB);
end;

procedure TVulkanRHIDevice.RecordDiagnostics(const APipelineHits, APipelineMisses,
  ADescriptorAllocs: Cardinal; const AAllocatedBytes: UInt64);
begin
  Inc(FPipelineCacheHits, APipelineHits);
  Inc(FPipelineCacheMisses, APipelineMisses);
  Inc(FDescriptorSetAllocations, ADescriptorAllocs);
  Inc(FAllocatedMemoryBytes, AAllocatedBytes);
end;

procedure TVulkanRHIDevice.CreateSwapchain(const Width, Height: Cardinal);
var
  Caps: VkSurfaceCapabilitiesKHR;
  ImageCount, I: Cardinal;
  CreateInfo: VkSwapchainCreateInfoKHR;
  Images: array of VkImage;
  ViewInfo: VkImageViewCreateInfo;
  ImgView: VkImageView;
  ColorDesc, DepthDesc: TRHITextureDesc;
begin
  if (FSurface = VK_NULL_HANDLE) or (FDevice = nil) then Exit;

  FillChar(Caps, SizeOf(Caps), 0);
  CheckVk(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(FPhysicalDevice, FSurface, @Caps),
    'vkGetPhysicalDeviceSurfaceCapabilitiesKHR');

  FSwapchainFormat := pfBGRA8_UNorm;
  FSwapchainExtent.width := Max(1, Width);
  FSwapchainExtent.height := Max(1, Height);
  if Caps.currentExtent.width <> High(Cardinal) then
    FSwapchainExtent := Caps.currentExtent;

  ImageCount := Max(2, Caps.minImageCount);
  if (Caps.maxImageCount > 0) and (ImageCount > Caps.maxImageCount) then
    ImageCount := Caps.maxImageCount;

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
  CreateInfo.surface := FSurface;
  CreateInfo.minImageCount := ImageCount;
  CreateInfo.imageFormat := RHIToVkFormat(FSwapchainFormat);
  CreateInfo.imageColorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  CreateInfo.imageExtent := FSwapchainExtent;
  CreateInfo.imageArrayLayers := 1;
  CreateInfo.imageUsage := VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  CreateInfo.imageSharingMode := VK_SHARING_MODE_EXCLUSIVE;
  CreateInfo.preTransform := Caps.currentTransform;
  CreateInfo.compositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  CreateInfo.presentMode := VK_PRESENT_MODE_FIFO_KHR;
  CreateInfo.clipped := VK_TRUE;

  CheckVk(vkCreateSwapchainKHR(FDevice, @CreateInfo, nil, @FSwapchain), 'vkCreateSwapchainKHR');

  CheckVk(vkGetSwapchainImagesKHR(FDevice, FSwapchain, @ImageCount, nil), 'vkGetSwapchainImagesKHR(count)');
  SetLength(Images, ImageCount);
  CheckVk(vkGetSwapchainImagesKHR(FDevice, FSwapchain, @ImageCount, @Images[0]), 'vkGetSwapchainImagesKHR');

  ColorDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    FSwapchainFormat, [tuColorAttachment, tuTransferSrc, tuTransferDst], 1);

  SetLength(FSwapchainColorTextures, ImageCount);
  for I := 0 to ImageCount - 1 do
  begin
    FillChar(ViewInfo, SizeOf(ViewInfo), 0);
    ViewInfo.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ViewInfo.image := Images[I];
    ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D;
    ViewInfo.format := CreateInfo.imageFormat;
    ViewInfo.subresourceRange.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
    ViewInfo.subresourceRange.baseMipLevel := 0;
    ViewInfo.subresourceRange.levelCount := 1;
    ViewInfo.subresourceRange.baseArrayLayer := 0;
    ViewInfo.subresourceRange.layerCount := 1;
    CheckVk(vkCreateImageView(FDevice, @ViewInfo, nil, @ImgView), 'vkCreateImageView(Swapchain)');
    FSwapchainColorTextures[I] := TVulkanRHITexture.CreateSwapchainWrapper(Self, ColorDesc, Images[I], ImgView);
  end;

  DepthDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    pfD32_Float, [tuDepthStencil], 1);
  FSwapchainDepthTexture := TVulkanRHITexture.Create(Self, DepthDesc);
end;

procedure TVulkanRHIDevice.DestroySwapchain;
var
  I: Integer;
begin
  FreeAndNil(FSwapchainDepthTexture);
  for I := 0 to High(FSwapchainColorTextures) do
    FreeAndNil(FSwapchainColorTextures[I]);
  SetLength(FSwapchainColorTextures, 0);

  if FSwapchain <> VK_NULL_HANDLE then
  begin
    vkDestroySwapchainKHR(FDevice, FSwapchain, nil);
    FSwapchain := VK_NULL_HANDLE;
  end;
end;

procedure TVulkanRHIDevice.CreateFrameContexts;
var
  I: Integer;
  SemInfo: VkSemaphoreCreateInfo;
  FenceInfo: VkFenceCreateInfo;
begin
  FillChar(SemInfo, SizeOf(SemInfo), 0);
  SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

  FillChar(FenceInfo, SizeOf(FenceInfo), 0);
  FenceInfo.sType := VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  FenceInfo.flags := VK_FENCE_CREATE_SIGNALED_BIT;

  for I := 0 to MaxFramesInFlight - 1 do
  begin
    CheckVk(vkCreateSemaphore(FDevice, @SemInfo, nil, @FFrames[I].ImageAvailableSemaphore), 'vkCreateSemaphore');
    CheckVk(vkCreateSemaphore(FDevice, @SemInfo, nil, @FFrames[I].RenderFinishedSemaphore), 'vkCreateSemaphore');
    CheckVk(vkCreateFence(FDevice, @FenceInfo, nil, @FFrames[I].InFlightFence), 'vkCreateFence');
    FFrames[I].CommandList := TVulkanRHICommandList.Create(Self, FGraphicsQueueFamily);
  end;
end;

procedure TVulkanRHIDevice.CreateDescriptorPool;
var
  PoolSizes: array[0..3] of VkDescriptorPoolSize;
  PoolInfo: VkDescriptorPoolCreateInfo;
begin
  if FDevice = nil then Exit;

  PoolSizes[0]._type := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  PoolSizes[0].descriptorCount := 2048;
  PoolSizes[1]._type := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
  PoolSizes[1].descriptorCount := 512;
  PoolSizes[2]._type := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  PoolSizes[2].descriptorCount := 512;
  PoolSizes[3]._type := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
  PoolSizes[3].descriptorCount := 4096;

  FillChar(PoolInfo, SizeOf(PoolInfo), 0);
  PoolInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  PoolInfo.maxSets := 2048;
  PoolInfo.poolSizeCount := Length(PoolSizes);
  PoolInfo.pPoolSizes := @PoolSizes[0];

  CheckVk(vkCreateDescriptorPool(FDevice, @PoolInfo, nil, @FDescriptorPool), 'vkCreateDescriptorPool');
end;

function TVulkanRHIDevice.BeginFrame: TRHICommandList;
var
  Frame: TVulkanFrameContext;
  AcquireRes: VkResult;
begin
  Frame := FFrames[FFrameIndex];

  { 1. Wait for the GPU to finish executing the previous frame occupying this slot }
  CheckVk(vkWaitForFences(FDevice, 1, @Frame.InFlightFence, VK_TRUE, High(UInt64)), 'vkWaitForFences');

  { 2. Acquire next swapchain image }
  AcquireRes := vkAcquireNextImageKHR(FDevice, FSwapchain, High(UInt64),
    Frame.ImageAvailableSemaphore, VK_NULL_HANDLE, @FCurrentSwapchainImageIndex);

  if AcquireRes = VK_ERROR_OUT_OF_DATE_KHR then
  begin
    ResizeSwapchain(FSwapchainExtent.width, FSwapchainExtent.height);
    Exit(nil);
  end;

  CheckVk(vkResetFences(FDevice, 1, @Frame.InFlightFence), 'vkResetFences');

  { 3. Begin command list recording }
  Frame.CommandList.BeginRecording;
  Result := Frame.CommandList;
  SetActiveCommandList(Result);
end;

procedure TVulkanRHIDevice.EndFrameAndPresent;
var
  Frame: TVulkanFrameContext;
  SubmitInfo: VkSubmitInfo;
  WaitStages: VkPipelineStageFlags;
  PresentInfo: VkPresentInfoKHR;
  CmdHandle: VkCommandBuffer;
begin
  SetActiveCommandList(nil);
  Frame := FFrames[FFrameIndex];

  { Ensure swapchain backbuffer is transitioned to VK_IMAGE_LAYOUT_PRESENT_SRC_KHR }
  Frame.CommandList.TransitionTexture(GetSwapchainColorTexture, rsPresent);
  Frame.CommandList.EndRecording;

  WaitStages := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  CmdHandle := Frame.CommandList.Handle;

  FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
  SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
  SubmitInfo.waitSemaphoreCount := 1;
  SubmitInfo.pWaitSemaphores := @Frame.ImageAvailableSemaphore;
  SubmitInfo.pWaitDstStageMask := @WaitStages;
  SubmitInfo.commandBufferCount := 1;
  SubmitInfo.pCommandBuffers := @CmdHandle;
  SubmitInfo.signalSemaphoreCount := 1;
  SubmitInfo.pSignalSemaphores := @Frame.RenderFinishedSemaphore;

  CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, Frame.InFlightFence), 'vkQueueSubmit');

  FillChar(PresentInfo, SizeOf(PresentInfo), 0);
  PresentInfo.sType := VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  PresentInfo.waitSemaphoreCount := 1;
  PresentInfo.pWaitSemaphores := @Frame.RenderFinishedSemaphore;
  PresentInfo.swapchainCount := 1;
  PresentInfo.pSwapchains := @FSwapchain;
  PresentInfo.pImageIndices := @FCurrentSwapchainImageIndex;

  vkQueuePresentKHR(FPresentQueue, @PresentInfo);

  FFrameIndex := (FFrameIndex + 1) mod MaxFramesInFlight;
end;

procedure TVulkanRHIDevice.ResizeSwapchain(const NewWidth, NewHeight: Cardinal);
begin
  if (NewWidth = 0) or (NewHeight = 0) then Exit;
  WaitIdle;
  DestroySwapchain;
  CreateSwapchain(NewWidth, NewHeight);
end;

procedure TVulkanRHIDevice.WaitIdle;
begin
  if FDevice <> nil then
    vkDeviceWaitIdle(FDevice);
end;

function TVulkanRHIDevice.CreateSecondaryCommandList: TRHICommandList;
begin
  Result := TVulkanRHICommandList.Create(Self, FGraphicsQueueFamily, cllSecondary);
end;

function TVulkanRHIDevice.GetSwapchainColorTexture: TRHITexture;
begin
  Result := FSwapchainColorTextures[FCurrentSwapchainImageIndex];
end;

function TVulkanRHIDevice.GetSwapchainDepthTexture: TRHITexture;
begin
  Result := FSwapchainDepthTexture;
end;

function TVulkanRHIDevice.CreateBuffer(const ADesc: TRHIBufferDesc;
  const InitialData: Pointer): TRHIBuffer;
begin
  Result := TVulkanRHIBuffer.Create(Self, ADesc, InitialData);
end;

function TVulkanRHIDevice.CreateTexture(const ADesc: TRHITextureDesc): TRHITexture;
begin
  Result := TVulkanRHITexture.Create(Self, ADesc);
end;

function TVulkanRHIDevice.CreateSampler(const ADesc: TRHISamplerDesc): TRHISampler;
begin
  Result := TVulkanRHISampler.Create(Self, ADesc);
end;

function TVulkanRHIDevice.CreateShaderModuleFromGLSL(const AStage: TRHIShaderStage;
  const AGLSLSource: String; const ADebugName: String): TRHIShaderModule;
var
  SPIRV: TSPIRVBytecode;
begin
  SPIRV := TCastleShaderCompiler.Instance.GetOrCompileSPIRV(AStage, AGLSLSource, ADebugName);
  if Length(SPIRV) = 0 then
    Exit(nil);
  Result := CreateShaderModuleFromSPIRV(AStage, @SPIRV[0], Length(SPIRV), ADebugName);
end;

function TVulkanRHIDevice.CreateShaderModuleFromSPIRV(const AStage: TRHIShaderStage;
  const ASPIRVBinary: Pointer; const ASizeInBytes: PtrUInt;
  const ADebugName: String): TRHIShaderModule;
begin
  Result := TVulkanRHIShaderModule.Create(Self, AStage, ASPIRVBinary, ASizeInBytes, ADebugName);
end;

function TVulkanRHIDevice.CreateDescriptorSetLayout(
  const Bindings: array of TRHIDescriptorBindingDesc): TRHIDescriptorSetLayout;
begin
  Result := TVulkanRHIDescriptorSetLayout.Create(Self, Bindings);
end;

function TVulkanRHIDevice.CreateDescriptorSet(
  const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet;
begin
  Inc(FDescriptorSetAllocations);
  Result := TVulkanRHIDescriptorSet.Create(Self, Layout as TVulkanRHIDescriptorSetLayout);
end;

function TVulkanRHIDevice.ComputePipelineHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
begin
  Result := ComputePipelineKeyHash(ADesc);
end;

function TVulkanRHIDevice.GetOrCreatePipeline(const ADesc: TRHIGraphicsPipelineDesc): TRHIPipeline;
var
  HashKey: UInt64;
  FoundPipeline: TVulkanRHIPipeline;
begin
  HashKey := ComputePipelineHash(ADesc);
  if FPipelineMap.TryGetValue(HashKey, FoundPipeline) then
  begin
    Inc(FPipelineCacheHits);
  end else
  begin
    Inc(FPipelineCacheMisses);
    FoundPipeline := TVulkanRHIPipeline.Create(Self, ADesc);
    FPipelineMap.Add(HashKey, FoundPipeline);
  end;
  Result := FoundPipeline;
end;

function TVulkanRHIDevice.GrabTextureImage(const SourceTexture: TRHITexture;
  const ReadArea: TRectangle): TRGBAlphaImage;
var
  VkTex: TVulkanRHITexture;
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  Region: VkBufferImageCopy;
  ByteSize: PtrUInt;
  MappedPixels: Pointer;
begin
  if (SourceTexture = nil) or (ReadArea.Width <= 0) or (ReadArea.Height <= 0) then
    Exit(nil);

  Result := TRGBAlphaImage.Create(ReadArea.Width, ReadArea.Height);
  if (FDevice = nil) or not Assigned(vkCmdCopyImageToBuffer) then
    Exit;

  VkTex := SourceTexture as TVulkanRHITexture;
  ByteSize := PtrUInt(ReadArea.Width) * PtrUInt(ReadArea.Height) * 4;
  StagingDesc := TRHIBufferDesc.Create(ByteSize, [buTransferDst], muGpuToCpu, 'GrabTextureStaging');
  StagingBuf := TVulkanRHIBuffer.Create(Self, StagingDesc, nil);
  try
    Cmd := BeginSingleTimeCommands;
    FillChar(Region, SizeOf(Region), 0);
    Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
    Region.imageSubresource.layerCount := 1;
    Region.imageOffset.x := Max(0, ReadArea.Left);
    Region.imageOffset.y := Max(0, ReadArea.Bottom);
    Region.imageExtent.width := ReadArea.Width;
    Region.imageExtent.height := ReadArea.Height;
    Region.imageExtent.depth := 1;

    vkCmdCopyImageToBuffer(Cmd, VkTex.Image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      StagingBuf.Handle, 1, @Region);
    EndSingleTimeCommands(Cmd);

    MappedPixels := StagingBuf.Map;
    try
      Move(MappedPixels^, Result.RawPixels^, ByteSize);
    finally
      StagingBuf.Unmap;
    end;
  finally
    FreeAndNil(StagingBuf);
  end;
end;

procedure TVulkanRHIDevice.LoadPipelineCache(const CacheFileUrl: String);
var
  Stream: TStream;
  Blob: TBytes;
  CacheInfo: VkPipelineCacheCreateInfo;
begin
  if (FDevice = nil) or not Assigned(vkCreatePipelineCache) then Exit;
  try
    Stream := Download(CacheFileUrl);
    try
      if LoadPipelineCacheBlobFromStream(Stream, FCapabilities.VendorId, FDeviceId, Blob) then
      begin
        if FPipelineCache <> VK_NULL_HANDLE then
        begin
          vkDestroyPipelineCache(FDevice, FPipelineCache, nil);
          FPipelineCache := VK_NULL_HANDLE;
        end;
        FillChar(CacheInfo, SizeOf(CacheInfo), 0);
        CacheInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;
        CacheInfo.initialDataSize := Length(Blob);
        CacheInfo.pInitialData := @Blob[0];
        CheckVk(vkCreatePipelineCache(FDevice, @CacheInfo, nil, @FPipelineCache), 'vkCreatePipelineCache(Load)');
      end;
    finally
      FreeAndNil(Stream);
    end;
  except
    on E: Exception do
      WritelnLog('Vulkan', 'Could not load pipeline cache from "%s": %s', [CacheFileUrl, E.Message]);
  end;
end;

procedure TVulkanRHIDevice.SavePipelineCache(const CacheFileUrl: String);
var
  DataSize: PtrUInt;
  Blob: TBytes;
  Stream: TStream;
begin
  if (FDevice = nil) or (FPipelineCache = VK_NULL_HANDLE) or not Assigned(vkGetPipelineCacheData) then
    Exit;

  DataSize := 0;
  if vkGetPipelineCacheData(FDevice, FPipelineCache, @DataSize, nil) <> VK_SUCCESS then
    Exit;
  if DataSize = 0 then
    Exit;

  SetLength(Blob, DataSize);
  if vkGetPipelineCacheData(FDevice, FPipelineCache, @DataSize, @Blob[0]) <> VK_SUCCESS then
    Exit;

  try
    Stream := UrlSaveStream(CacheFileUrl);
    try
      SavePipelineCacheBlobToStream(Stream, FCapabilities.VendorId, FDeviceId, @Blob[0], DataSize);
    finally
      FreeAndNil(Stream);
    end;
  except
    on E: Exception do
      WritelnLog('Vulkan', 'Could not save pipeline cache to "%s": %s', [CacheFileUrl, E.Message]);
  end;
end;

function TVulkanRHIDevice.BeginSingleTimeCommands: VkCommandBuffer;
var
  AllocInfo: VkCommandBufferAllocateInfo;
  BeginInfo: VkCommandBufferBeginInfo;
begin
  Result := nil;
  if (FDevice = nil) or (FFrames[0].CommandList = nil) then Exit;

  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  AllocInfo.commandPool := FFrames[0].CommandList.FCommandPool;
  AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  AllocInfo.commandBufferCount := 1;
  CheckVk(vkAllocateCommandBuffers(FDevice, @AllocInfo, @Result), 'vkAllocateCommandBuffers(SingleTime)');

  FillChar(BeginInfo, SizeOf(BeginInfo), 0);
  BeginInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  BeginInfo.flags := VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  CheckVk(vkBeginCommandBuffer(Result, @BeginInfo), 'vkBeginCommandBuffer(SingleTime)');
end;

procedure TVulkanRHIDevice.EndSingleTimeCommands(const CmdBuf: VkCommandBuffer);
var
  SubmitInfo: VkSubmitInfo;
  LocalCmd: VkCommandBuffer;
begin
  if (FDevice = nil) or (CmdBuf = nil) then Exit;
  CheckVk(vkEndCommandBuffer(CmdBuf), 'vkEndCommandBuffer(SingleTime)');

  LocalCmd := CmdBuf;
  FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
  SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
  SubmitInfo.commandBufferCount := 1;
  SubmitInfo.pCommandBuffers := @LocalCmd;

  CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, VK_NULL_HANDLE), 'vkQueueSubmit(SingleTime)');
  CheckVk(vkQueueWaitIdle(FGraphicsQueue), 'vkQueueWaitIdle(SingleTime)');

  vkFreeCommandBuffers(FDevice, FFrames[0].CommandList.FCommandPool, 1, @LocalCmd);
end;

function TVulkanRHIDevice.FindMemoryType(const TypeFilter: Cardinal;
  const Properties: VkMemoryPropertyFlags): Cardinal;
var
  MemProps: VkPhysicalDeviceMemoryProperties;
  I: Cardinal;
begin
  vkGetPhysicalDeviceMemoryProperties(FPhysicalDevice, @MemProps);
  for I := 0 to MemProps.memoryTypeCount - 1 do
    if ((TypeFilter and (1 shl I)) <> 0) and
       ((MemProps.memoryTypes[I].propertyFlags and Properties) = Properties) then
      Exit(I);

  raise ERHIOutOfMemory.Create('Failed to find suitable Vulkan memory type');
end;

end.
