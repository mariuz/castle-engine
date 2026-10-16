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
  CastleInternalRHI, CastleInternalVulkan, CastleInternalVulkanWSI;

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
    FRenderPass: VkRenderPass;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHIGraphicsPipelineDesc);
    destructor Destroy; override;
    property Handle: VkPipeline read FHandle;
    property PipelineLayout: VkPipelineLayout read FPipelineLayout;
    property RenderPass: VkRenderPass read FRenderPass;
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
    FInFallbackRenderPass: Boolean;
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
    property InFallbackRenderPass: Boolean read FInFallbackRenderPass;
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
  TVulkanRenderPassMap = {$ifdef FPC}specialize{$endif} TDictionary<UInt64, VkRenderPass>;
  TVulkanFramebufferMap = {$ifdef FPC}specialize{$endif} TDictionary<UInt64, VkFramebuffer>;

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

    { Descriptor, Pipeline & Vulkan 1.1 RenderPass/Framebuffer Caches }
    FDescriptorPool: VkDescriptorPool;
    FPipelineCache: VkPipelineCache;
    FPipelineMap: TVulkanPipelineMap;
    FRenderPassMap: TVulkanRenderPassMap;
    FFramebufferMap: TVulkanFramebufferMap;
    FPipelineCacheLoaded: Boolean;
    FPrewarm3DVertexShader: TRHIShaderModule;
    FPrewarm3DFragmentShader: TRHIShaderModule;
    FPrewarm2DVertexShader: TRHIShaderModule;
    FPrewarm2DFragmentShader: TRHIShaderModule;

    { Diagnostics, VK_EXT_memory_budget & Vulkan 1.1/1.2 Fallback tracking }
    FInstanceApiVersion: Cardinal;
    FDeviceApiVersion: Cardinal;
    FSupportsMemoryBudgetExt: Boolean;
    FSupportsDynamicRendering: Boolean;
    FPipelineCacheHits: Cardinal;
    FPipelineCacheMisses: Cardinal;
    FDescriptorSetAllocations: Cardinal;
    FFallbackRenderPassBeginCount: Cardinal;
    FAllocatedMemoryBytes: Int64;

    procedure CreateInstance(const EnableValidation: Boolean);
    procedure PickPhysicalDevice;
    procedure CreateLogicalDevice;
    procedure CreateSwapchain(const Width, Height: Cardinal);
    procedure DestroySwapchain;
    procedure CreateFrameContexts;
    procedure CreateDescriptorPool;
    procedure ClearFallbackFramebuffers;
    procedure ClearFallbackRenderPasses;
    function IsDeviceExtensionSupported(const AExtensionName: AnsiString): Boolean;
    function ComputePipelineHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
    function GetPipelineCount: Cardinal;
    function GetFallbackRenderPassCount: Cardinal;
    function GetFallbackFramebufferCount: Cardinal;
  public
    constructor Create(const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
      const InitialWidth, InitialHeight: Cardinal;
      const EnableValidation: Boolean = True); reintroduce; overload;
    { Creates a headless Vulkan RHI device instance (for offscreen/unit testing). }
    constructor CreateHeadless(const APhysicalDevice: VkPhysicalDevice;
      const ASupportsMemoryBudgetExt: Boolean = True;
      const ASupportsDynamicRendering: Boolean = True;
      const ADeviceApiVersion: Cardinal = VK_API_VERSION_1_3); overload;
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

    { Pre-warms standard 3D/2D graphics pipeline state objects (PSOs) and loads/saves
      the Vulkan pipeline cache (DefaultVulkanPipelineCacheUrl) so PSOs are baked
      before the first rendered frame. Returns total cached pipeline count. }
    function PrewarmStandardPipelines(const AIncludeBlending: Boolean = True;
      const AIncludeShadowDepth: Boolean = True;
      const ACacheFileUrl: String = ''): Cardinal;

    { Acquires or creates a cached VkRenderPass for Vulkan 1.1/1.2 devices that lack
      VK_KHR_dynamic_rendering. Supports explicit LoadOp/StoreOp for multi-pass rendering
      (e.g. preserving 3D scene contents during 2D UI overlay passes). }
    function GetOrCreateFallbackRenderPass(
      const AColorFormats: array of TRHIPixelFormat;
      const ADepthFormat: TRHIPixelFormat;
      const ASampleCount: Cardinal = 1;
      const AColorLoadOp: TRHIAttachmentLoadOp = loClear;
      const ADepthLoadOp: TRHIAttachmentLoadOp = loClear;
      const AColorStoreOp: TRHIAttachmentStoreOp = soStore;
      const ADepthStoreOp: TRHIAttachmentStoreOp = soStore): VkRenderPass;

    { Acquires or creates a cached VkFramebuffer for Vulkan 1.1/1.2 devices that lack
      VK_KHR_dynamic_rendering. }
    function GetOrCreateFallbackFramebuffer(const ARenderPass: VkRenderPass;
      const AAttachments: array of VkImageView;
      const AWidth, AHeight: Cardinal): VkFramebuffer;

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
    property InstanceApiVersion: Cardinal read FInstanceApiVersion;
    property DeviceApiVersion: Cardinal read FDeviceApiVersion write FDeviceApiVersion;
    property DescriptorPool: VkDescriptorPool read FDescriptorPool;
    property PipelineCache: VkPipelineCache read FPipelineCache;
    property PipelineCount: Cardinal read GetPipelineCount;
    property PipelineCacheLoaded: Boolean read FPipelineCacheLoaded;
    property SupportsMemoryBudgetExt: Boolean read FSupportsMemoryBudgetExt;
    property SupportsDynamicRendering: Boolean read FSupportsDynamicRendering write FSupportsDynamicRendering;
    property FallbackRenderPassCount: Cardinal read GetFallbackRenderPassCount;
    property FallbackFramebufferCount: Cardinal read GetFallbackFramebufferCount;
    property FallbackRenderPassBeginCount: Cardinal read FFallbackRenderPassBeginCount;
    property PipelineCacheHits: Cardinal read FPipelineCacheHits;
    property PipelineCacheMisses: Cardinal read FPipelineCacheMisses;
    property DescriptorSetAllocations: Cardinal read FDescriptorSetAllocations;
    property AllocatedMemoryBytes: Int64 read FAllocatedMemoryBytes;
  end;

{ Negotiates the highest supported VkApplicationInfo.apiVersion (1.3, 1.2, 1.1, or 1.0)
  for a given loader version reported by vkEnumerateInstanceVersion. }
function NegotiateInstanceApiVersion(const ALoaderVersion: Cardinal): Cardinal;

{ Resolves whether a Vulkan 1.1, 1.2, or 1.3+ physical device can use dynamic rendering
  (and which KHR prerequisite extensions must be enabled on VkDeviceCreateInfo) or should
  fall back to standard Vulkan 1.1 VkRenderPass + VkFramebuffer passes. }
procedure ResolveVulkan11_12DeviceConfig(const ADeviceApiVersion: Cardinal;
  const AHasDynamicRenderingExt, AHasDepthStencilResolveExt, AHasCreateRenderPass2Ext: Boolean;
  out AUseDynamicRendering: Boolean; out ARequiredExtensions: TAnsiStringArray);

{ Computes a deterministic 64-bit FNV-1a hash for a graphics pipeline state descriptor. }
function ComputePipelineKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;

{ Computes a deterministic 64-bit FNV-1a hash for a fallback VkRenderPass signature. }
function ComputeRenderPassKeyHash(const AColorFormats: array of TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat; const ASampleCount: Cardinal = 1;
  const AColorLoadOp: TRHIAttachmentLoadOp = loClear;
  const ADepthLoadOp: TRHIAttachmentLoadOp = loClear;
  const AColorStoreOp: TRHIAttachmentStoreOp = soStore;
  const ADepthStoreOp: TRHIAttachmentStoreOp = soStore): UInt64;

{ Computes a deterministic 64-bit FNV-1a hash for a fallback VkFramebuffer signature. }
function ComputeFramebufferKeyHash(const ARenderPass: VkRenderPass;
  const AAttachments: array of VkImageView; const AWidth, AHeight: Cardinal): UInt64;

const
  DefaultVulkanPipelineCacheUrl = 'castle-config:/vulkan_pipeline_cache.bin';
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
  CastleDownload, CastleInternalShaderCompiler,
  CastleInternalVulkanMemory;

const
  FNV1aOffsetBasis64 = UInt64($CBF29CE484222325);
  FNV1aPrime64 = UInt64($00000100000001B3);

function NegotiateInstanceApiVersion(const ALoaderVersion: Cardinal): Cardinal;
begin
  if ALoaderVersion >= VK_API_VERSION_1_3 then
    Result := VK_API_VERSION_1_3
  else
  if ALoaderVersion >= VK_API_VERSION_1_2 then
    Result := VK_API_VERSION_1_2
  else
  if ALoaderVersion >= VK_API_VERSION_1_1 then
    Result := VK_API_VERSION_1_1
  else
    Result := VK_API_VERSION_1_0;
end;

procedure ResolveVulkan11_12DeviceConfig(const ADeviceApiVersion: Cardinal;
  const AHasDynamicRenderingExt, AHasDepthStencilResolveExt, AHasCreateRenderPass2Ext: Boolean;
  out AUseDynamicRendering: Boolean; out ARequiredExtensions: TAnsiStringArray);
begin
  SetLength(ARequiredExtensions, 0);
  if ADeviceApiVersion >= VK_API_VERSION_1_3 then
  begin
    { Vulkan 1.3+: Dynamic Rendering is core }
    AUseDynamicRendering := True;
  end else
  if ADeviceApiVersion >= VK_API_VERSION_1_2 then
  begin
    { Vulkan 1.2: VK_KHR_depth_stencil_resolve and VK_KHR_create_renderpass2 are core 1.2;
      only VK_KHR_dynamic_rendering extension is required if supported }
    if AHasDynamicRenderingExt then
    begin
      AUseDynamicRendering := True;
      SetLength(ARequiredExtensions, 1);
      ARequiredExtensions[0] := VK_KHR_dynamic_rendering;
    end else
      AUseDynamicRendering := False;
  end else
  if ADeviceApiVersion >= VK_API_VERSION_1_1 then
  begin
    { Vulkan 1.1: VK_KHR_multiview and VK_KHR_maintenance2 are core 1.1,
      while VK_KHR_dynamic_rendering requires VK_KHR_create_renderpass2 and VK_KHR_depth_stencil_resolve }
    if AHasDynamicRenderingExt and AHasDepthStencilResolveExt and AHasCreateRenderPass2Ext then
    begin
      AUseDynamicRendering := True;
      SetLength(ARequiredExtensions, 3);
      ARequiredExtensions[0] := VK_KHR_create_renderpass2;
      ARequiredExtensions[1] := VK_KHR_depth_stencil_resolve;
      ARequiredExtensions[2] := VK_KHR_dynamic_rendering;
    end else
      AUseDynamicRendering := False;
  end else
  begin
    { Pre-Vulkan 1.1 device: use standard VkRenderPass / VkFramebuffer fallback }
    AUseDynamicRendering := False;
  end;
end;

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

function ComputeRenderPassKeyHash(const AColorFormats: array of TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat; const ASampleCount: Cardinal;
  const AColorLoadOp: TRHIAttachmentLoadOp; const ADepthLoadOp: TRHIAttachmentLoadOp;
  const AColorStoreOp: TRHIAttachmentStoreOp; const ADepthStoreOp: TRHIAttachmentStoreOp): UInt64;
var
  I, ColorCount: Integer;
begin
  Result := FNV1aOffsetBasis64;
  ColorCount := Length(AColorFormats);
  HashBytesFNV1a(Result, ColorCount, SizeOf(ColorCount));
  for I := 0 to High(AColorFormats) do
    HashBytesFNV1a(Result, AColorFormats[I], SizeOf(TRHIPixelFormat));
  HashBytesFNV1a(Result, ADepthFormat, SizeOf(ADepthFormat));
  HashBytesFNV1a(Result, ASampleCount, SizeOf(ASampleCount));
  HashBytesFNV1a(Result, AColorLoadOp, SizeOf(AColorLoadOp));
  HashBytesFNV1a(Result, ADepthLoadOp, SizeOf(ADepthLoadOp));
  HashBytesFNV1a(Result, AColorStoreOp, SizeOf(AColorStoreOp));
  HashBytesFNV1a(Result, ADepthStoreOp, SizeOf(ADepthStoreOp));
end;

function ComputeFramebufferKeyHash(const ARenderPass: VkRenderPass;
  const AAttachments: array of VkImageView; const AWidth, AHeight: Cardinal): UInt64;
var
  I, AttCount: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, UInt64(ARenderPass));
  AttCount := Length(AAttachments);
  HashBytesFNV1a(Result, AttCount, SizeOf(AttCount));
  for I := 0 to High(AAttachments) do
    HashUInt64FNV1a(Result, UInt64(AAttachments[I]));
  HashBytesFNV1a(Result, AWidth, SizeOf(AWidth));
  HashBytesFNV1a(Result, AHeight, SizeOf(AHeight));
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

  if (ADevice = nil) or (ADevice.Handle = nil) then
  begin
    FImageView := VkImageView(PtrUInt(Self));
    Exit;
  end;

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
  if (VulkanDevice = nil) or (VulkanDevice.Handle = nil) then
  begin
    inherited;
    Exit;
  end;
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
  if (ADevice = nil) or (ADevice.Handle = nil) or not Assigned(vkCreateShaderModule) then
    Exit;
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
  if (ADevice <> nil) and (not ADevice.SupportsDynamicRendering) then
    FRenderPass := ADevice.GetOrCreateFallbackRenderPass(
      ADesc.ColorAttachmentFormats, ADesc.DepthAttachmentFormat, ADesc.SampleCount);
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
  if (ADesc.VertexShader <> nil) and ((ADesc.VertexShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_VERTEX_BIT;
    Stages[StageCount].module := (ADesc.VertexShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;
  if (ADesc.FragmentShader <> nil) and ((ADesc.FragmentShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_FRAGMENT_BIT;
    Stages[StageCount].module := (ADesc.FragmentShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;
  if (ADesc.GeometryShader <> nil) and ((ADesc.GeometryShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
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

  { 5. Set up VkPipelineRenderingCreateInfoKHR (Vulkan 1.3 Dynamic Rendering)
    or fallback VkRenderPass (Vulkan 1.1/1.2 without VK_KHR_dynamic_rendering) }
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
  if ADevice.SupportsDynamicRendering then
  begin
    PipelineInfo.pNext := @RenderingInfo;
    PipelineInfo.renderPass := VK_NULL_HANDLE;
  end else
  begin
    PipelineInfo.pNext := nil;
    PipelineInfo.renderPass := FRenderPass;
    PipelineInfo.subpass := 0;
  end;
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

  if StageCount > 0 then
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
  if (FDevice = nil) or (FDevice.Handle = nil) then
    Exit;

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
  if (FDevice <> nil) and (FDevice.Handle <> nil) and (FCommandPool <> VK_NULL_HANDLE) then
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
  FallbackColorFormats: array of TRHIPixelFormat;
  FallbackDepthFormat: TRHIPixelFormat;
  FallbackViews: array of VkImageView;
  FallbackClears: array of VkClearValue;
  FallbackRP: VkRenderPass;
  FallbackFB: VkFramebuffer;
  RpBeginInfo: VkRenderPassBeginInfo;
  FbWidth, FbHeight: Cardinal;
  ColorLoadOp, DepthLoadOp: TRHIAttachmentLoadOp;
  ColorStoreOp, DepthStoreOp: TRHIAttachmentStoreOp;
  AttCount, I: Integer;
begin
  if (FDevice <> nil) and (not FDevice.SupportsDynamicRendering) then
  begin
    SetLength(FallbackColorFormats, Length(Info.ColorAttachments));
    AttCount := Length(Info.ColorAttachments);
    if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
      Inc(AttCount);
    SetLength(FallbackViews, AttCount);
    SetLength(FallbackClears, AttCount);

    FbWidth := Max(1, Info.RenderArea.Width);
    FbHeight := Max(1, Info.RenderArea.Height);

    for I := 0 to High(Info.ColorAttachments) do
    begin
      if Info.ColorAttachments[I].Texture <> nil then
      begin
        FallbackColorFormats[I] := Info.ColorAttachments[I].Texture.Desc.Format;
        FallbackViews[I] := (Info.ColorAttachments[I].Texture as TVulkanRHITexture).ImageView;
        FbWidth := Max(FbWidth, Info.ColorAttachments[I].Texture.Desc.Width);
        FbHeight := Max(FbHeight, Info.ColorAttachments[I].Texture.Desc.Height);
      end else
      begin
        FallbackColorFormats[I] := pfBGRA8_UNorm;
        FallbackViews[I] := VK_NULL_HANDLE;
      end;
      FillChar(FallbackClears[I], SizeOf(VkClearValue), 0);
      Move(Info.ColorAttachments[I].ClearColor.Data,
        FallbackClears[I].color.float32, SizeOf(Single) * 4);
    end;

    if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
    begin
      FallbackDepthFormat := Info.DepthAttachment.Texture.Desc.Format;
      FallbackViews[AttCount - 1] := (Info.DepthAttachment.Texture as TVulkanRHITexture).ImageView;
      FbWidth := Max(FbWidth, Info.DepthAttachment.Texture.Desc.Width);
      FbHeight := Max(FbHeight, Info.DepthAttachment.Texture.Desc.Height);
      FillChar(FallbackClears[AttCount - 1], SizeOf(VkClearValue), 0);
      FallbackClears[AttCount - 1].depthStencil.depth := Info.DepthAttachment.ClearDepth;
      FallbackClears[AttCount - 1].depthStencil.stencil := Info.DepthAttachment.ClearStencil;
    end else
      FallbackDepthFormat := pfUndefined;

    if Length(Info.ColorAttachments) > 0 then
    begin
      ColorLoadOp := Info.ColorAttachments[0].LoadOp;
      ColorStoreOp := Info.ColorAttachments[0].StoreOp;
    end else
    begin
      ColorLoadOp := loClear;
      ColorStoreOp := soStore;
    end;

    if Info.HasDepthAttachment then
    begin
      DepthLoadOp := Info.DepthAttachment.LoadOp;
      DepthStoreOp := Info.DepthAttachment.StoreOp;
    end else
    begin
      DepthLoadOp := loClear;
      DepthStoreOp := soStore;
    end;

    FallbackRP := FDevice.GetOrCreateFallbackRenderPass(
      FallbackColorFormats, FallbackDepthFormat, 1,
      ColorLoadOp, DepthLoadOp, ColorStoreOp, DepthStoreOp);
    FallbackFB := FDevice.GetOrCreateFallbackFramebuffer(
      FallbackRP, FallbackViews, FbWidth, FbHeight);

    FillChar(RpBeginInfo, SizeOf(RpBeginInfo), 0);
    RpBeginInfo.sType := VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    RpBeginInfo.renderPass := FallbackRP;
    RpBeginInfo.framebuffer := FallbackFB;
    RpBeginInfo.renderArea.offset.x := Max(0, Info.RenderArea.Left);
    RpBeginInfo.renderArea.offset.y := Max(0, Info.RenderArea.Bottom);
    RpBeginInfo.renderArea.extent.width := Max(1, Info.RenderArea.Width);
    RpBeginInfo.renderArea.extent.height := Max(1, Info.RenderArea.Height);
    RpBeginInfo.clearValueCount := Length(FallbackClears);
    if Length(FallbackClears) > 0 then
      RpBeginInfo.pClearValues := @FallbackClears[0];

    FInFallbackRenderPass := True;
    Inc(FDevice.FFallbackRenderPassBeginCount);
    if (FHandle <> nil) and Assigned(vkCmdBeginRenderPass) then
      vkCmdBeginRenderPass(FHandle, @RpBeginInfo, VK_SUBPASS_CONTENTS_INLINE);
    Exit;
  end;

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

  if (FHandle <> nil) and Assigned(vkCmdBeginRendering) then
    vkCmdBeginRendering(FHandle, @RenderInfo);
end;

procedure TVulkanRHICommandList.EndRendering;
begin
  if FInFallbackRenderPass then
  begin
    FInFallbackRenderPass := False;
    if (FHandle <> nil) and Assigned(vkCmdEndRenderPass) then
      vkCmdEndRenderPass(FHandle);
    Exit;
  end;
  if (FHandle <> nil) and Assigned(vkCmdEndRendering) then
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
  FRenderPassMap := TVulkanRenderPassMap.Create;
  FFramebufferMap := TVulkanFramebufferMap.Create;
  FSupportsDynamicRendering := True;

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
  const ASupportsMemoryBudgetExt: Boolean;
  const ASupportsDynamicRendering: Boolean;
  const ADeviceApiVersion: Cardinal);
begin
  inherited Create;
  FPipelineMap := TVulkanPipelineMap.Create([doOwnsValues]);
  FRenderPassMap := TVulkanRenderPassMap.Create;
  FFramebufferMap := TVulkanFramebufferMap.Create;
  FCapabilities.Backend := rbVulkan;
  FPhysicalDevice := APhysicalDevice;
  FInstanceApiVersion := ADeviceApiVersion;
  FDeviceApiVersion := ADeviceApiVersion;
  FSupportsMemoryBudgetExt := ASupportsMemoryBudgetExt;
  FSupportsDynamicRendering := ASupportsDynamicRendering;
end;

procedure TVulkanRHIDevice.ClearFallbackFramebuffers;
var
  FbHandle: VkFramebuffer;
begin
  if FFramebufferMap = nil then Exit;
  if (FDevice <> nil) and Assigned(vkDestroyFramebuffer) then
  begin
    for FbHandle in FFramebufferMap.Values do
      if FbHandle <> VK_NULL_HANDLE then
        vkDestroyFramebuffer(FDevice, FbHandle, nil);
  end;
  FFramebufferMap.Clear;
end;

procedure TVulkanRHIDevice.ClearFallbackRenderPasses;
var
  RpHandle: VkRenderPass;
begin
  if FRenderPassMap = nil then Exit;
  if (FDevice <> nil) and Assigned(vkDestroyRenderPass) then
  begin
    for RpHandle in FRenderPassMap.Values do
      if RpHandle <> VK_NULL_HANDLE then
        vkDestroyRenderPass(FDevice, RpHandle, nil);
  end;
  FRenderPassMap.Clear;
end;

function TVulkanRHIDevice.GetFallbackRenderPassCount: Cardinal;
begin
  if FRenderPassMap <> nil then
    Result := Cardinal(FRenderPassMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetFallbackFramebufferCount: Cardinal;
begin
  if FFramebufferMap <> nil then
    Result := Cardinal(FFramebufferMap.Count)
  else
    Result := 0;
end;

destructor TVulkanRHIDevice.Destroy;
var
  I: Integer;
begin
  SetActiveCommandList(nil);
  WaitIdle;
  DestroySwapchain;
  FreeAndNil(FPipelineMap);
  ClearFallbackFramebuffers;
  ClearFallbackRenderPasses;
  FreeAndNil(FFramebufferMap);
  FreeAndNil(FRenderPassMap);
  FreeAndNil(FPrewarm3DVertexShader);
  FreeAndNil(FPrewarm3DFragmentShader);
  FreeAndNil(FPrewarm2DVertexShader);
  FreeAndNil(FPrewarm2DFragmentShader);

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
const
  FallbackVersions: array[0..3] of Cardinal = (
    VK_API_VERSION_1_3,
    VK_API_VERSION_1_2,
    VK_API_VERSION_1_1,
    VK_API_VERSION_1_0
  );
var
  AppInfo: VkApplicationInfo;
  CreateInfo: VkInstanceCreateInfo;
  ExtNames: TAnsiStringArray;
  ExtPtrs: array of PAnsiChar;
  LayerName: PAnsiChar;
  LoaderVer: Cardinal;
  I: Integer;
  Res: VkResult;
begin
  LoaderVer := VK_API_VERSION_1_3;
  if Assigned(vkEnumerateInstanceVersion) then
  begin
    if vkEnumerateInstanceVersion(@LoaderVer) <> VK_SUCCESS then
      LoaderVer := VK_API_VERSION_1_0;
  end else
    LoaderVer := VK_API_VERSION_1_0;

  FInstanceApiVersion := NegotiateInstanceApiVersion(LoaderVer);

  FillChar(AppInfo, SizeOf(AppInfo), 0);
  AppInfo.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
  AppInfo.pApplicationName := 'Castle Game Engine Application';
  AppInfo.applicationVersion := VK_API_VERSION_1_0;
  AppInfo.pEngineName := 'Castle Game Engine';
  AppInfo.engineVersion := FInstanceApiVersion;
  AppInfo.apiVersion := FInstanceApiVersion;

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

  { Step down apiVersion if older Vulkan 1.1/1.2 loader rejects higher version }
  if Res = VK_ERROR_INCOMPATIBLE_DRIVER then
  begin
    for I := Low(FallbackVersions) to High(FallbackVersions) do
      if FallbackVersions[I] < AppInfo.apiVersion then
      begin
        AppInfo.apiVersion := FallbackVersions[I];
        FInstanceApiVersion := AppInfo.apiVersion;
        Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
        if Res = VK_SUCCESS then
          Break;
      end;
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
  ReqDynRenderExts: TAnsiStringArray;
begin
  DeviceCount := 0;
  CheckVk(vkEnumeratePhysicalDevices(FInstance, @DeviceCount, nil), 'vkEnumeratePhysicalDevices(count)');
  if DeviceCount = 0 then
    raise ERHIError.Create('No Vulkan physical devices found');

  SetLength(Devices, DeviceCount);
  CheckVk(vkEnumeratePhysicalDevices(FInstance, @DeviceCount, @Devices[0]), 'vkEnumeratePhysicalDevices');

  { Prefer discrete GPU meeting Vulkan 1.1+ baseline, otherwise any Vulkan 1.1+ GPU }
  FPhysicalDevice := Devices[0];
  for I := 0 to DeviceCount - 1 do
  begin
    vkGetPhysicalDeviceProperties(Devices[I], @Props);
    if (Props.deviceType = VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) and
       (Props.apiVersion >= VK_API_VERSION_1_1) then
    begin
      FPhysicalDevice := Devices[I];
      Break;
    end;
    if Props.apiVersion >= VK_API_VERSION_1_1 then
      FPhysicalDevice := Devices[I];
  end;

  vkGetPhysicalDeviceProperties(FPhysicalDevice, @ChosenProps);
  vkGetPhysicalDeviceFeatures(FPhysicalDevice, @Features);

  FDeviceId := ChosenProps.deviceID;
  FDeviceApiVersion := ChosenProps.apiVersion;

  ResolveVulkan11_12DeviceConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_dynamic_rendering),
    IsDeviceExtensionSupported(VK_KHR_depth_stencil_resolve),
    IsDeviceExtensionSupported(VK_KHR_create_renderpass2),
    FSupportsDynamicRendering,
    ReqDynRenderExts);

  WritelnLog('Vulkan', Format('Selected GPU "%s" (Vulkan %d.%d.%d, DynamicRendering=%s)', [
    String(PAnsiChar(@ChosenProps.deviceName[0])),
    VK_VERSION_MAJOR(FDeviceApiVersion),
    VK_VERSION_MINOR(FDeviceApiVersion),
    VK_VERSION_PATCH(FDeviceApiVersion),
    BoolToStr(FSupportsDynamicRendering, True)
  ]));

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
  ReqDynRenderExts: TAnsiStringArray;
  DeviceExts: array[0..7] of PAnsiChar;
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
    if (FDeviceApiVersion < VK_API_VERSION_1_1) and
       IsDeviceExtensionSupported(VK_KHR_get_physical_device_properties2) then
    begin
      DeviceExts[ExtCount] := VK_KHR_get_physical_device_properties2;
      Inc(ExtCount);
    end;
    DeviceExts[ExtCount] := VK_EXT_memory_budget;
    Inc(ExtCount);
  end;

  ResolveVulkan11_12DeviceConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_dynamic_rendering),
    IsDeviceExtensionSupported(VK_KHR_depth_stencil_resolve),
    IsDeviceExtensionSupported(VK_KHR_create_renderpass2),
    FSupportsDynamicRendering,
    ReqDynRenderExts);

  for I := 0 to High(ReqDynRenderExts) do
  begin
    DeviceExts[ExtCount] := PAnsiChar(ReqDynRenderExts[I]);
    Inc(ExtCount);
  end;

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  if FSupportsDynamicRendering then
    CreateInfo.pNext := @DynRenderFeatures
  else
  begin
    CreateInfo.pNext := nil;
    WritelnLog('Vulkan', Format('Device (Vulkan %d.%d) does not support VK_KHR_dynamic_rendering; using Vulkan 1.1/1.2 VkRenderPass / VkFramebuffer fallback.', [
      VK_VERSION_MAJOR(FDeviceApiVersion),
      VK_VERSION_MINOR(FDeviceApiVersion)
    ]));
  end;
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

function TVulkanRHIDevice.GetOrCreateFallbackRenderPass(
  const AColorFormats: array of TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat;
  const ASampleCount: Cardinal;
  const AColorLoadOp: TRHIAttachmentLoadOp;
  const ADepthLoadOp: TRHIAttachmentLoadOp;
  const AColorStoreOp: TRHIAttachmentStoreOp;
  const ADepthStoreOp: TRHIAttachmentStoreOp): VkRenderPass;

  function MapLoadOp(const AOp: TRHIAttachmentLoadOp): VkAttachmentLoadOp;
  begin
    case AOp of
      loLoad:     Result := VK_ATTACHMENT_LOAD_OP_LOAD;
      loClear:    Result := VK_ATTACHMENT_LOAD_OP_CLEAR;
      loDontCare: Result := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
      else        Result := VK_ATTACHMENT_LOAD_OP_CLEAR;
    end;
  end;

  function MapStoreOp(const AOp: TRHIAttachmentStoreOp): VkAttachmentStoreOp;
  begin
    case AOp of
      soStore:    Result := VK_ATTACHMENT_STORE_OP_STORE;
      soDontCare: Result := VK_ATTACHMENT_STORE_OP_DONT_CARE;
      else        Result := VK_ATTACHMENT_STORE_OP_STORE;
    end;
  end;

var
  KeyHash: UInt64;
  Attachments: array of VkAttachmentDescription;
  ColorRefs: array of VkAttachmentReference;
  DepthRef: VkAttachmentReference;
  Subpass: VkSubpassDescription;
  Dependency: VkSubpassDependency;
  RpInfo: VkRenderPassCreateInfo;
  SampleBits: VkSampleCountFlags;
  AttCount, DepthIdx, I: Integer;
begin
  KeyHash := ComputeRenderPassKeyHash(AColorFormats, ADepthFormat, ASampleCount,
    AColorLoadOp, ADepthLoadOp, AColorStoreOp, ADepthStoreOp);
  if (FRenderPassMap <> nil) and FRenderPassMap.TryGetValue(KeyHash, Result) then
    Exit;

  if ASampleCount > 1 then
    SampleBits := ASampleCount
  else
    SampleBits := VK_SAMPLE_COUNT_1_BIT;

  AttCount := Length(AColorFormats);
  if ADepthFormat <> pfUndefined then
    Inc(AttCount);

  SetLength(Attachments, AttCount);
  SetLength(ColorRefs, Length(AColorFormats));
  for I := 0 to High(AColorFormats) do
  begin
    FillChar(Attachments[I], SizeOf(VkAttachmentDescription), 0);
    Attachments[I].format := RHIToVkFormat(AColorFormats[I]);
    Attachments[I].samples := SampleBits;
    Attachments[I].loadOp := MapLoadOp(AColorLoadOp);
    Attachments[I].storeOp := MapStoreOp(AColorStoreOp);
    Attachments[I].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    Attachments[I].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
    Attachments[I].initialLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    Attachments[I].finalLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    ColorRefs[I].attachment := Cardinal(I);
    ColorRefs[I].layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  end;

  FillChar(Subpass, SizeOf(Subpass), 0);
  Subpass.pipelineBindPoint := VK_PIPELINE_BIND_POINT_GRAPHICS;
  Subpass.colorAttachmentCount := Length(ColorRefs);
  if Length(ColorRefs) > 0 then
    Subpass.pColorAttachments := @ColorRefs[0];

  if ADepthFormat <> pfUndefined then
  begin
    DepthIdx := Length(AColorFormats);
    FillChar(Attachments[DepthIdx], SizeOf(VkAttachmentDescription), 0);
    Attachments[DepthIdx].format := RHIToVkFormat(ADepthFormat);
    Attachments[DepthIdx].samples := SampleBits;
    Attachments[DepthIdx].loadOp := MapLoadOp(ADepthLoadOp);
    Attachments[DepthIdx].storeOp := MapStoreOp(ADepthStoreOp);
    Attachments[DepthIdx].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    Attachments[DepthIdx].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
    Attachments[DepthIdx].initialLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    Attachments[DepthIdx].finalLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    DepthRef.attachment := Cardinal(DepthIdx);
    DepthRef.layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    Subpass.pDepthStencilAttachment := @DepthRef;
  end;

  FillChar(Dependency, SizeOf(Dependency), 0);
  Dependency.srcSubpass := $FFFFFFFF; // VK_SUBPASS_EXTERNAL
  Dependency.dstSubpass := 0;
  Dependency.srcStageMask := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or
    VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
  Dependency.dstStageMask := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or
    VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
  Dependency.srcAccessMask := 0;
  Dependency.dstAccessMask := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT or
    VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

  FillChar(RpInfo, SizeOf(RpInfo), 0);
  RpInfo.sType := VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
  RpInfo.attachmentCount := Length(Attachments);
  if Length(Attachments) > 0 then
    RpInfo.pAttachments := @Attachments[0];
  RpInfo.subpassCount := 1;
  RpInfo.pSubpasses := @Subpass;
  RpInfo.dependencyCount := 1;
  RpInfo.pDependencies := @Dependency;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateRenderPass) then
    CheckVk(vkCreateRenderPass(FDevice, @RpInfo, nil, @Result), 'vkCreateRenderPass')
  else
  if FRenderPassMap <> nil then
    Result := VkRenderPass(FRenderPassMap.Count + 1);

  if FRenderPassMap <> nil then
    FRenderPassMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreateFallbackFramebuffer(
  const ARenderPass: VkRenderPass;
  const AAttachments: array of VkImageView;
  const AWidth, AHeight: Cardinal): VkFramebuffer;
var
  KeyHash: UInt64;
  FbInfo: VkFramebufferCreateInfo;
begin
  KeyHash := ComputeFramebufferKeyHash(ARenderPass, AAttachments, AWidth, AHeight);
  if (FFramebufferMap <> nil) and FFramebufferMap.TryGetValue(KeyHash, Result) then
    Exit;

  FillChar(FbInfo, SizeOf(FbInfo), 0);
  FbInfo.sType := VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
  FbInfo.renderPass := ARenderPass;
  FbInfo.attachmentCount := Length(AAttachments);
  if Length(AAttachments) > 0 then
    FbInfo.pAttachments := @AAttachments[0];
  FbInfo.width := Max(1, AWidth);
  FbInfo.height := Max(1, AHeight);
  FbInfo.layers := 1;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateFramebuffer) then
    CheckVk(vkCreateFramebuffer(FDevice, @FbInfo, nil, @Result), 'vkCreateFramebuffer')
  else
  if FFramebufferMap <> nil then
    Result := VkFramebuffer(FFramebufferMap.Count + 1);

  if FFramebufferMap <> nil then
    FFramebufferMap.AddOrSetValue(KeyHash, Result);
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
  ClearFallbackFramebuffers;
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

function TVulkanRHIDevice.GetPipelineCount: Cardinal;
begin
  if FPipelineMap <> nil then
    Result := Cardinal(FPipelineMap.Count)
  else
    Result := 0;
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

function TVulkanRHIDevice.PrewarmStandardPipelines(const AIncludeBlending: Boolean;
  const AIncludeShadowDepth: Boolean; const ACacheFileUrl: String): Cardinal;
const
  Default3DVertSrc =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec3 castle_Vertex;' + LineEnding +
    'layout(location = 1) in vec3 castle_Normal;' + LineEnding +
    'layout(location = 2) in vec2 castle_TexCoord0;' + LineEnding +
    'layout(push_constant) uniform PushData { mat4 mvp; } pc;' + LineEnding +
    'layout(location = 0) out vec3 vNormal;' + LineEnding +
    'layout(location = 1) out vec2 vTexCoord;' + LineEnding +
    'void main() {' + LineEnding +
    '  vNormal = castle_Normal;' + LineEnding +
    '  vTexCoord = castle_TexCoord0;' + LineEnding +
    '  gl_Position = pc.mvp * vec4(castle_Vertex, 1.0);' + LineEnding +
    '}';
  Default3DFragSrc =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec3 vNormal;' + LineEnding +
    'layout(location = 1) in vec2 vTexCoord;' + LineEnding +
    'layout(location = 0) out vec4 outColor;' + LineEnding +
    'void main() {' + LineEnding +
    '  outColor = vec4(normalize(vNormal) * 0.5 + 0.5, 1.0);' + LineEnding +
    '}';
  Default2DVertSrc =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec2 aPosition;' + LineEnding +
    'layout(location = 1) in vec2 aTexCoord;' + LineEnding +
    'layout(location = 2) in vec4 aColor;' + LineEnding +
    'layout(location = 0) out vec2 vTexCoord;' + LineEnding +
    'layout(location = 1) out vec4 vColor;' + LineEnding +
    'void main() {' + LineEnding +
    '  vTexCoord = aTexCoord;' + LineEnding +
    '  vColor = aColor;' + LineEnding +
    '  gl_Position = vec4(aPosition, 0.0, 1.0);' + LineEnding +
    '}';
  Default2DFragSrc =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec2 vTexCoord;' + LineEnding +
    'layout(location = 1) in vec4 vColor;' + LineEnding +
    'layout(location = 0) out vec4 outColor;' + LineEnding +
    'void main() {' + LineEnding +
    '  outColor = vColor;' + LineEnding +
    '}';
var
  EffectiveCacheUrl: String;
  MissesBefore: Cardinal;
  ColorFormat: TRHIPixelFormat;
  Desc3D, Desc2D, DescShadow: TRHIGraphicsPipelineDesc;
begin
  if ACacheFileUrl <> '' then
    EffectiveCacheUrl := ACacheFileUrl
  else
    EffectiveCacheUrl := DefaultVulkanPipelineCacheUrl;

  if not FPipelineCacheLoaded then
  begin
    FPipelineCacheLoaded := True;
    if EffectiveCacheUrl <> '' then
      LoadPipelineCache(EffectiveCacheUrl);
  end;

  { Pre-warm core GLSL -> SPIR-V shader blobs if shaderc is available }
  TCastleShaderCompiler.Instance.PrewarmCoreEngineShaders;

  if (FDevice <> nil) and TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable and
     (FPrewarm3DVertexShader = nil) then
  begin
    FPrewarm3DVertexShader := CreateShaderModuleFromGLSL(ssVertex, Default3DVertSrc, 'Prewarm3DVert');
    FPrewarm3DFragmentShader := CreateShaderModuleFromGLSL(ssFragment, Default3DFragSrc, 'Prewarm3DFrag');
    FPrewarm2DVertexShader := CreateShaderModuleFromGLSL(ssVertex, Default2DVertSrc, 'Prewarm2DVert');
    FPrewarm2DFragmentShader := CreateShaderModuleFromGLSL(ssFragment, Default2DFragSrc, 'Prewarm2DFrag');
  end;

  if FSwapchainFormat <> pfUndefined then
    ColorFormat := FSwapchainFormat
  else
    ColorFormat := pfBGRA8_UNorm;

  MissesBefore := FPipelineCacheMisses;

  { 1. Standard 3D Forward Opaque PSO (CullBack, DepthTestWrite, Opaque) }
  FillChar(Desc3D, SizeOf(Desc3D), 0);
  Desc3D.VertexShader := FPrewarm3DVertexShader;
  Desc3D.FragmentShader := FPrewarm3DFragmentShader;
  Desc3D.Topology := ptTriangleList;
  Desc3D.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc3D.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc3D.BlendState := TRHIBlendStateDesc.DefaultOpaque;
  Desc3D.PushConstantSize := 128;
  Desc3D.PushConstantStages := [ssVertex, ssFragment];
  SetLength(Desc3D.ColorAttachmentFormats, 1);
  Desc3D.ColorAttachmentFormats[0] := ColorFormat;
  Desc3D.DepthAttachmentFormat := pfD32_Float;
  Desc3D.SampleCount := 1;
  SetLength(Desc3D.VertexInput.Bindings, 1);
  Desc3D.VertexInput.Bindings[0].Binding := 0;
  Desc3D.VertexInput.Bindings[0].Stride := 32;
  Desc3D.VertexInput.Bindings[0].PerInstance := False;
  SetLength(Desc3D.VertexInput.Attributes, 3);
  Desc3D.VertexInput.Attributes[0].Location := 0;
  Desc3D.VertexInput.Attributes[0].Binding := 0;
  Desc3D.VertexInput.Attributes[0].Format := vafVector3;
  Desc3D.VertexInput.Attributes[0].Offset := 0;
  Desc3D.VertexInput.Attributes[0].AttributeName := 'castle_Vertex';
  Desc3D.VertexInput.Attributes[1].Location := 1;
  Desc3D.VertexInput.Attributes[1].Binding := 0;
  Desc3D.VertexInput.Attributes[1].Format := vafVector3;
  Desc3D.VertexInput.Attributes[1].Offset := 12;
  Desc3D.VertexInput.Attributes[1].AttributeName := 'castle_Normal';
  Desc3D.VertexInput.Attributes[2].Location := 2;
  Desc3D.VertexInput.Attributes[2].Binding := 0;
  Desc3D.VertexInput.Attributes[2].Format := vafVector2;
  Desc3D.VertexInput.Attributes[2].Offset := 24;
  Desc3D.VertexInput.Attributes[2].AttributeName := 'castle_TexCoord0';
  Desc3D.DebugName := 'Prewarm3DForwardOpaque';
  GetOrCreatePipeline(Desc3D);

  { 2. Two-Sided 3D Forward Opaque PSO (CullNone, DepthTestWrite, Opaque) }
  Desc3D.Rasterizer.CullMode := cmNone;
  Desc3D.DebugName := 'Prewarm3DForwardOpaqueTwoSided';
  GetOrCreatePipeline(Desc3D);

  { 3. Alpha-Blended 3D Forward PSO (CullNone, DepthReadOnly, AlphaBlend) }
  if AIncludeBlending then
  begin
    Desc3D.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthReadOnly;
    Desc3D.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
    Desc3D.DebugName := 'Prewarm3DForwardAlphaBlend';
    GetOrCreatePipeline(Desc3D);
  end;

  { 4. Shadow Map Depth-Only 3D PSO }
  if AIncludeShadowDepth then
  begin
    FillChar(DescShadow, SizeOf(DescShadow), 0);
    DescShadow.VertexShader := FPrewarm3DVertexShader;
    DescShadow.FragmentShader := nil;
    DescShadow.Topology := ptTriangleList;
    DescShadow.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    DescShadow.Rasterizer.DepthBiasEnable := True;
    DescShadow.DepthStencil := TRHIDepthStencilStateDesc.DefaultShadowMap;
    DescShadow.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    DescShadow.PushConstantSize := 128;
    DescShadow.PushConstantStages := [ssVertex];
    SetLength(DescShadow.ColorAttachmentFormats, 0);
    DescShadow.DepthAttachmentFormat := pfD32_Float;
    DescShadow.SampleCount := 1;
    DescShadow.VertexInput := Desc3D.VertexInput;
    DescShadow.DebugName := 'Prewarm3DShadowDepthOnly';
    GetOrCreatePipeline(DescShadow);
  end;

  { 5. 2D UI / Sprite Batch PSO (CullNone, DepthDisabled, AlphaBlend) }
  FillChar(Desc2D, SizeOf(Desc2D), 0);
  Desc2D.VertexShader := FPrewarm2DVertexShader;
  Desc2D.FragmentShader := FPrewarm2DFragmentShader;
  Desc2D.Topology := ptTriangleList;
  Desc2D.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc2D.Rasterizer.CullMode := cmNone;
  Desc2D.DepthStencil := TRHIDepthStencilStateDesc.DefaultDisabled;
  Desc2D.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc2D.PushConstantSize := 64;
  Desc2D.PushConstantStages := [ssVertex, ssFragment];
  SetLength(Desc2D.ColorAttachmentFormats, 1);
  Desc2D.ColorAttachmentFormats[0] := ColorFormat;
  Desc2D.DepthAttachmentFormat := pfD32_Float;
  Desc2D.SampleCount := 1;
  SetLength(Desc2D.VertexInput.Bindings, 1);
  Desc2D.VertexInput.Bindings[0].Binding := 0;
  Desc2D.VertexInput.Bindings[0].Stride := 20;
  Desc2D.VertexInput.Bindings[0].PerInstance := False;
  SetLength(Desc2D.VertexInput.Attributes, 3);
  Desc2D.VertexInput.Attributes[0].Location := 0;
  Desc2D.VertexInput.Attributes[0].Binding := 0;
  Desc2D.VertexInput.Attributes[0].Format := vafVector2;
  Desc2D.VertexInput.Attributes[0].Offset := 0;
  Desc2D.VertexInput.Attributes[0].AttributeName := 'aPosition';
  Desc2D.VertexInput.Attributes[1].Location := 1;
  Desc2D.VertexInput.Attributes[1].Binding := 0;
  Desc2D.VertexInput.Attributes[1].Format := vafVector2;
  Desc2D.VertexInput.Attributes[1].Offset := 8;
  Desc2D.VertexInput.Attributes[1].AttributeName := 'aTexCoord';
  Desc2D.VertexInput.Attributes[2].Location := 2;
  Desc2D.VertexInput.Attributes[2].Binding := 0;
  Desc2D.VertexInput.Attributes[2].Format := vafUByte4Normalized;
  Desc2D.VertexInput.Attributes[2].Offset := 16;
  Desc2D.VertexInput.Attributes[2].AttributeName := 'aColor';
  Desc2D.DebugName := 'Prewarm2DBatchAlphaBlend';
  GetOrCreatePipeline(Desc2D);

  if (FPipelineCacheMisses > MissesBefore) and (EffectiveCacheUrl <> '') then
    SavePipelineCache(EffectiveCacheUrl);

  Result := GetPipelineCount;
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
