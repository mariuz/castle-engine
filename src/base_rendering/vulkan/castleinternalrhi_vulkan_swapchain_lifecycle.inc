{%MainUnit castleinternalrhi_vulkan.pas}
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
  TCastleVulkanSwapchainSurface = class
  private
    FDevice: TVulkanRHIDevice;
    FSurface: VkSurfaceKHR;
    FOwnsSurface: Boolean;
    FSwapchain: VkSwapchainKHR;
    FSwapchainFormat: TRHIPixelFormat;
    FSwapchainDepthFormat: TRHIPixelFormat;
    FSwapchainColorSpace: VkColorSpaceKHR;
    FSwapchainPresentMode: VkPresentModeKHR;
    FSwapchainCompositeAlpha: Integer;
    FSwapchainPreTransform: Integer;
    FSwapchainRecreateCount: Cardinal;
    FSwapchainExtent: VkExtent2D;
    FRequestedWidth: Cardinal;
    FRequestedHeight: Cardinal;
    FSwapchainMinimized: Boolean;
    FSwapchainSuboptimal: Boolean;
    FColorTextures: array of TVulkanRHITexture;
    FImageAvailableSemaphores: array[0 .. MaxFramesInFlight - 1] of VkSemaphore;
    FRenderFinishedSemaphores: array of VkSemaphore;
    FImageInFlightFences: array of VkFence;
    FDepthTexture: TVulkanRHITexture;
    FMSAAColorTexture: TVulkanRHITexture;
    FMSAADepthTexture: TVulkanRHITexture;
    FCurrentImageIndex: Cardinal;
    FAntiAliasing: TAntiAliasing;
    FSampleCount: Cardinal;
    FFramesPresentedCount: Cardinal;
    FDebugName: String;
    procedure CreateSyncObjects;
    procedure DestroySyncObjects;
    procedure CreateSwapchain(const AWidth, AHeight: Cardinal);
    procedure DestroySwapchainResources(const ADestroySwapchainHandle: Boolean = True);
    procedure EnsureMSAATargets(const AWidth, AHeight: Cardinal;
      const AColorFormat, ADepthFormat: TRHIPixelFormat);
    function GetSwapchainImageCount: Cardinal;
    procedure SetAntiAliasing(const AValue: TAntiAliasing);
    procedure SetSampleCount(const AValue: Cardinal);
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
      const InitialWidth, InitialHeight: Cardinal;
      const ADebugName: String = ''); overload;
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ANativeDesc: TVulkanNativeSurfaceDesc;
      const InitialWidth, InitialHeight: Cardinal;
      const ADebugName: String = ''); overload;
    constructor CreateSimulatedForTesting(const ADevice: TVulkanRHIDevice;
      const AWidth, AHeight: Cardinal;
      const AImageCount: Cardinal = 2;
      const AColorFormat: TRHIPixelFormat = pfBGRA8_UNorm;
      const ADepthFormat: TRHIPixelFormat = pfD24_UNorm_S8_UInt;
      const ADebugName: String = '');
    destructor Destroy; override;

    procedure Resize(const NewWidth, NewHeight: Cardinal);
    procedure SimulateForTesting(const AWidth, AHeight: Cardinal;
      const AImageCount: Cardinal = 2;
      const AColorFormat: TRHIPixelFormat = pfBGRA8_UNorm;
      const ADepthFormat: TRHIPixelFormat = pfD24_UNorm_S8_UInt);
    function GetCurrentColorTexture: TVulkanRHITexture;
    function GetDepthTexture: TVulkanRHITexture;
    function BuildRenderingInfo(const ARenderArea: TRectangle;
      const AClearColor: TCastleColor;
      const AColorLoadOp: TRHIAttachmentLoadOp = loClear;
      const ADepthLoadOp: TRHIAttachmentLoadOp = loClear;
      const AClearDepth: Single = 1.0): TRHIRenderingInfo;

    property Device: TVulkanRHIDevice read FDevice;
    property SurfaceHandle: VkSurfaceKHR read FSurface;
    property SwapchainHandle: VkSwapchainKHR read FSwapchain;
    property SwapchainImageCount: Cardinal read GetSwapchainImageCount;
    property SwapchainExtent: VkExtent2D read FSwapchainExtent;
    property RequestedWidth: Cardinal read FRequestedWidth;
    property RequestedHeight: Cardinal read FRequestedHeight;
    property SwapchainFormat: TRHIPixelFormat read FSwapchainFormat;
    property SwapchainDepthFormat: TRHIPixelFormat read FSwapchainDepthFormat;
    property SwapchainColorSpace: VkColorSpaceKHR read FSwapchainColorSpace;
    property SwapchainPresentMode: VkPresentModeKHR read FSwapchainPresentMode;
    property SwapchainCompositeAlpha: Integer read FSwapchainCompositeAlpha;
    property SwapchainPreTransform: Integer read FSwapchainPreTransform;
    property SwapchainMinimized: Boolean read FSwapchainMinimized;
    property SwapchainSuboptimal: Boolean read FSwapchainSuboptimal;
    property SwapchainRecreateCount: Cardinal read FSwapchainRecreateCount;
    property CurrentImageIndex: Cardinal read FCurrentImageIndex;
    property MSAAColorTexture: TVulkanRHITexture read FMSAAColorTexture;
    property MSAADepthTexture: TVulkanRHITexture read FMSAADepthTexture;
    property AntiAliasing: TAntiAliasing read FAntiAliasing write SetAntiAliasing;
    property SampleCount: Cardinal read FSampleCount write SetSampleCount;
    property FramesPresentedCount: Cardinal read FFramesPresentedCount;
    property DebugName: String read FDebugName write FDebugName;
  end;

  TVulkanSwapchainSurfaceList = {$ifdef FPC}specialize{$endif} TObjectList<TCastleVulkanSwapchainSurface>;

  { Hardware GPU Vendor Classification (Phase 120: Desktop, Apple & Mobile Matrix) }
  TVulkanVendorID = (
    vvUnknown,
    vvNVIDIA,
    vvAMD,
    vvIntel,
    vvApple,
    vvARM,
    vvQualcomm,
    vvImgTec,
    vvBroadcom,
    vvSamsung,
    vvMesa,
    vvMicrosoft
  );

  { VK_KHR_portability_subset Capabilities & Limits (macOS / iOS MoltenVK) }
  TVulkanPortabilitySubsetCaps = record
    Active: Boolean;
    ConstantAlphaColorBlendFactors: Boolean;
    Events: Boolean;
    ImageViewFormatReinterpretation: Boolean;
    ImageViewFormatSwizzle: Boolean;
    ImageView2DOn3DImage: Boolean;
    MultisampleArrayImage: Boolean;
    MutableComparisonSamplers: Boolean;
    PointPolygons: Boolean;
    SamplerMipLodBias: Boolean;
    SeparateStencilMaskRef: Boolean;
    TriangleFans: Boolean;
    VertexAttributeAccessBeyondStride: Boolean;
    MinVertexInputBindingStrideAlignment: Cardinal;
    class function DefaultFullVulkan: TVulkanPortabilitySubsetCaps; static;
    class function DefaultMoltenVK: TVulkanPortabilitySubsetCaps; static;
  end;

  TVulkanPendingBufferRelocation = record
    Buffer: TVulkanRHIBuffer;
    OldVkBuffer: VkBuffer;
    NewVkBuffer: VkBuffer;
    CopySize: VkDeviceSize;
  end;

  TVulkanRHIDevice = class(TRHIDevice)
  private
    FInstance: VkInstance;
    FDebugMessenger: VkDebugUtilsMessengerEXT;
    FSurface: VkSurfaceKHR;
    FRequireWSISwapchain: Boolean;
    FSwapchainSurfaces: TVulkanSwapchainSurfaceList;
    FActiveSwapchainSurface: TCastleVulkanSwapchainSurface;
    FPhysicalDevice: VkPhysicalDevice;
    FDevice: VkDevice;
    FDeviceId: Cardinal;
    FGraphicsQueue: VkQueue;
    FPresentQueue: VkQueue;
    FTransferQueue: VkQueue;
    FGraphicsQueueFamily: Cardinal;
    FPresentQueueFamily: Cardinal;
    FTransferQueueFamily: Cardinal;
    FHasDedicatedTransferQueue: Boolean;

    { Swapchain & MSAA state }
    FSwapchain: VkSwapchainKHR;
    FSwapchainFormat: TRHIPixelFormat;
    FSwapchainDepthFormat: TRHIPixelFormat;
    FSwapchainColorSpace: VkColorSpaceKHR;
    FSwapchainPresentMode: VkPresentModeKHR;
    FSwapchainCompositeAlpha: Integer;
    FSwapchainPreTransform: Integer;
    FSwapchainRecreateCount: Cardinal;
    FSwapchainExtent: VkExtent2D;
    FRequestedSwapchainWidth: Cardinal;
    FRequestedSwapchainHeight: Cardinal;
    FSwapchainMinimized: Boolean;
    FSwapchainSuboptimal: Boolean;
    FSwapchainColorTextures: array of TVulkanRHITexture;
    FSwapchainRenderFinishedSemaphores: array of VkSemaphore;
    FSwapchainDepthTexture: TVulkanRHITexture;
    FSwapchainMSAAColorTexture: TVulkanRHITexture;
    FSwapchainMSAADepthTexture: TVulkanRHITexture;
    FCurrentSwapchainImageIndex: Cardinal;
    FAntiAliasing: TAntiAliasing;
    FSampleCount: Cardinal;
    FActiveColorTarget: TRHITexture;
    FActiveDepthTarget: TRHITexture;

    { Frame synchronization, deferred resource retirement & command recording }
    FFrames: array[0 .. MaxFramesInFlight - 1] of TVulkanFrameContext;
    FDeferredDeletions: array[0 .. MaxFramesInFlight - 1] of array of TVulkanDeferredDeletionItem;
    FDeferResourceDestruction: Boolean;
    FTotalFramesPresented: Cardinal;

    { GPU memory sub-allocator (pooled blocks + per-frame ring buffers), async staging uploader, bindless manager, timestamp profiler, compute culler, IBL generator, clustered culler, shadow atlas, HDR post-processor, GTAO, SSR, volumetric fog, TAA, reflection probes, decals, compute particles, OIT, contact shadows, compute skinner & CDLOD terrain }
    FMemoryAllocator: TCastleVulkanMemoryAllocator;
    FStagingUploader: TCastleVulkanStagingUploader;
    FBindlessTextureManager: TCastleVulkanBindlessTextureManager;
    FTimestampProfiler: TCastleVulkanTimestampProfiler;
    FComputeCuller: TCastleVulkanComputeCuller;
    FIBLGenerator: TCastleVulkanIBLGenerator;
    FClusteredLightCuller: TCastleVulkanClusteredLightCuller;
    FShadowAtlas: TCastleVulkanShadowAtlas;
    FHDRPostProcessor: TCastleVulkanHDRPostProcessor;
    FGTAO: TCastleVulkanGTAO;
    FSSR: TCastleVulkanSSR;
    FVolumetricFog: TCastleVulkanVolumetricFog;
    FTAA: TCastleVulkanTAA;
    FReflectionProbeManager: TCastleVulkanReflectionProbeManager;
    FDecalManager: TCastleVulkanDecalManager;
    FComputeParticles: TCastleVulkanComputeParticles;
    FWeightedBlendedOIT: TCastleVulkanWeightedBlendedOIT;
    FContactShadows: TCastleVulkanContactShadows;
    FComputeSkinner: TCastleVulkanComputeSkinner;
    FTerrainCDLOD: TCastleVulkanTerrainCDLOD;
    FAtmosphereRenderer: TCastleVulkanAtmosphereRenderer;
    FOceanSimulator: TCastleVulkanOceanSimulator;
    FDDGIGrid: TCastleVulkanDDGIGrid;
    FMeshletCuller: TCastleVulkanMeshletCuller;
    FVirtualShadowMap: TCastleVulkanVirtualShadowMap;
    FLODSelector: TCastleVulkanLODSelector;
    FTextureStreamer: TCastleVulkanTextureStreamer;
    FShadowCasterCuller: TCastleVulkanShadowCasterCuller;
    FClusterDAG: TCastleVulkanClusterDAG;
    FGlobalSDF: TCastleVulkanGlobalSDF;
    FSurfaceCache: TCastleVulkanSurfaceCache;
    FReSTIR: TCastleVulkanReSTIR;
    FTSRUpscaler: TCastleVulkanTSRUpscaler;
    FVRSManager: TCastleVulkanVRSManager;
    FRuntimeVirtualTexture: TCastleVulkanRuntimeVirtualTexture;
    FSparseVolumeAtlas: TCastleVulkanSparseVolumeAtlas;
    FBreadcrumbTracker: TCastleVulkanBreadcrumbTracker;
    FSVGFDenoiser: TCastleVulkanSVGFDenoiser;
    FShaderBindingTable: TCastleVulkanShaderBindingTable;
    FAccelerationStructureManager: TCastleVulkanAccelerationStructureManager;
    FXPBDSimulator: TCastleVulkanXPBDSimulator;
    FMultiviewStereoManager: TCastleVulkanMultiviewStereoManager;
    FPerInstanceCustomData: TCastleVulkanPerInstanceCustomData;
    FNeuralDenoiser: TCastleVulkanNeuralDenoiser;
    FProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations;
    FStreamCompactor: TCastleVulkanStreamCompactor;
    FVoxelConeTracer: TCastleVulkanVoxelConeTracer;
    FMaterialBinner: TCastleVulkanMaterialBinner;
    FPerPixelLinkedListOIT: TCastleVulkanPerPixelLinkedListOIT;
    FHostImageCopyManager: TCastleVulkanHostImageCopyManager;
    FGaussianSplatRenderer: TCastleVulkanGaussianSplatRenderer;
    FDescriptorBufferManager: TCastleVulkanDescriptorBufferManager;
    FHiZPyramidGenerator: TCastleVulkanHiZPyramidGenerator;
    FAutoExposureHistogram: TCastleVulkanAutoExposureHistogram;
    FFramePacer: TCastleVulkanFramePacer;
    FIndirectComputeDispatcher: TCastleVulkanIndirectComputeDispatcher;
    FBCnCompressor: TCastleVulkanBCnCompressor;
    FPipelineBinaryManager: TCastleVulkanPipelineBinaryManager;
    FWorkerCommandPoolManager: TCastleVulkanWorkerCommandPoolManager;
    FBindlessIndirectBatch: TCastleVulkanBindlessIndirectBatch;

    { Descriptor, Pipeline, Compute Pipeline, VK_EXT_graphics_pipeline_library & Vulkan 1.1 RenderPass/Framebuffer Caches }
    FPersistentDescriptorAllocator: TVulkanDescriptorPoolAllocator;
    FDescriptorPool: VkDescriptorPool;
    FSingleTimeCommandPool: VkCommandPool;
    FPipelineCache: VkPipelineCache;
    FPipelineMap: TVulkanPipelineMap;
    FComputePipelineMap: TVulkanComputePipelineMap;
    FVertexInputLibMap: TVulkanPipelineLibraryMap;
    FPreRasterLibMap: TVulkanPipelineLibraryMap;
    FFragmentShaderLibMap: TVulkanPipelineLibraryMap;
    FFragmentOutputLibMap: TVulkanPipelineLibraryMap;
    FRenderPassMap: TVulkanRenderPassMap;
    FFramebufferMap: TVulkanFramebufferMap;
    FPipelineCacheLoaded: Boolean;
    FPipelineCacheSeededFromBundle: Boolean;
    FBundledPipelineCacheFallbackUrl: String;
    FPrewarm3DVertexShader: TRHIShaderModule;
    FPrewarm3DFragmentShader: TRHIShaderModule;
    FPrewarm2DVertexShader: TRHIShaderModule;
    FPrewarm2DFragmentShader: TRHIShaderModule;
    FDefaultSampler: TVulkanRHISampler;
    FDefaultShadowSampler: TVulkanRHISampler;
    FDefaultBrdfLutSampler: TVulkanRHISampler;
    FDefaultWhiteTexture: TVulkanRHITexture;
    FDefaultBlackTexture: TVulkanRHITexture;
    FDefaultFlatNormalTexture: TVulkanRHITexture;
    FDefaultShadowDepthTexture: TVulkanRHITexture;
    FDefaultBrdfLutTexture: TVulkanRHITexture;
    FDefaultWhiteCubeTexture: TVulkanRHITexture;
    FDebugObjectsNamedCount: Cardinal;
    FLastNamedDebugObject: String;

    { Diagnostics, VK_EXT_memory_budget, VK_EXT_graphics_pipeline_library, Bindless, Extended Dynamic State, Sync2 & Fallback tracking }
    FInstanceApiVersion: Cardinal;
    FDeviceApiVersion: Cardinal;
    FVendorKind: TVulkanVendorID;
    FDriverId: Integer;
    FDriverName: String;
    FDriverInfo: String;
    FIsPortabilitySubsetDevice: Boolean;
    FPortabilitySubsetCaps: TVulkanPortabilitySubsetCaps;
    FMaxPerStageDescriptorSamplers: Cardinal;
    FPortabilitySubsetFeatures: VkPhysicalDevicePortabilitySubsetFeaturesKHR;
    FInstanceHasSurfaceExtension: Boolean;
    FCompletedIdleEpoch: UInt64;
    FSupportsMemoryBudgetExt: Boolean;
    FSupportsDynamicRendering: Boolean;
    FSupportsGraphicsPipelineLibrary: Boolean;
    FSupportsGPLFastLinking: Boolean;
    FSupportsBindlessTextures: Boolean;
    FSupportsBindlessUpdateAfterBind: Boolean;
    FSupportsExtendedDynamicState: Boolean;
    FSupportsSynchronization2: Boolean;
    FSupportsTimelineSemaphores: Boolean;
    FSupportsHostQueryReset: Boolean;
    FSupportsOcclusionQueryPrecise: Boolean;
    FSupportsDrawIndirectCountFeature: Boolean;
    FSupportsShaderDrawParameters: Boolean;
    FSupportsBufferDeviceAddress: Boolean;
    FSupportsAccelerationStructure: Boolean;
    FSupportsRayQuery: Boolean;
    FSupportsRayTracingPipeline: Boolean;
    FSupportsMeshShaders: Boolean;
    FSupportsTaskShaders: Boolean;
    FRTShaderGroupHandleSize: Cardinal;
    FRTShaderGroupHandleAlignment: Cardinal;
    FRTShaderGroupBaseAlignment: Cardinal;
    FMaxBindlessTextures: Cardinal;
    FPipelineCacheHits: Cardinal;
    FPipelineCacheMisses: Cardinal;
    FComputePipelineCacheHits: Cardinal;
    FComputePipelineCacheMisses: Cardinal;
    FGPLFastLinkedPipelineCount: Cardinal;
    FGPLLibraryCacheHits: Cardinal;
    FGPLLibraryCacheMisses: Cardinal;
    FDescriptorSetAllocations: Cardinal;
    FFallbackRenderPassBeginCount: Cardinal;
    FMSAAResolvePassCount: Cardinal;
    FCommandRecordingGeneration: UInt64;
    FComputeDispatchCount: Cardinal;
    FSync2BarrierCount: Cardinal;
    FAllocatedMemoryBytes: Int64;
    FValidationLock: TObject;
    FValidationLayerActive: Boolean;
    FDebugUtilsActive: Boolean;
    FStrictValidationGate: Boolean;
    FValidationErrorCount: Cardinal;
    FValidationWarningCount: Cardinal;
    FValidationInfoCount: Cardinal;
    FValidationMessages: array of String;
    FLiveDescriptorSets: TFPList;
    FPendingRelocations: array of TVulkanPendingBufferRelocation;
    FRelocatedBuffers: array of TVulkanRHIBuffer;

    procedure RegisterLiveDescriptorSet(const ASet: TVulkanRHIDescriptorSet);
    procedure UnregisterLiveDescriptorSet(const ASet: TVulkanRHIDescriptorSet);
    procedure UnbindDestroyedBufferFromDescriptorSets(const ABuffer: TVulkanRHIBuffer);
    procedure UnbindDestroyedTextureFromDescriptorSets(const ATexture: TVulkanRHITexture);
    procedure EnqueueInFlightDescriptorSetDeletion(const AOwnerPool: VkDescriptorPool;
      const ASet: VkDescriptorSet);
    function HandleDefragmentRelocate(const AUserData: Pointer;
      const AOldAlloc, ANewAlloc: TVulkanMemoryAllocation): Boolean;
    procedure HandleDefragmentFinalizeMoves;
    procedure CreateInstance(const EnableValidation: Boolean;
      const ARequireSurfaceExtensions: Boolean = True);
    function GetValidationMessageCount: Integer;
    procedure PickPhysicalDevice;
    procedure CreateLogicalDevice;
    procedure CreateSwapchain(const Width, Height: Cardinal);
    procedure DestroySwapchainResources(const ADestroySwapchainHandle: Boolean = True);
    procedure DestroySwapchain;
    function GetSurfaceHandle: VkSurfaceKHR;
    function GetSwapchainHandle: VkSwapchainKHR;
    function GetSwapchainImageCount: Cardinal;
    function GetSwapchainExtent: VkExtent2D;
    procedure EnsureMSAATargets(const AWidth, AHeight: Cardinal;
      const AColorFormat, ADepthFormat: TRHIPixelFormat);
    procedure CreateFrameContexts;
    procedure CreateDescriptorPool;
    function NeedsUpdateAfterBindSamplerLayouts: Boolean;
    procedure CaptureSwapchainReadbackShadowBeforePresent(
      const ACmdList: TVulkanRHICommandList; const ASwapchainTex: TVulkanRHITexture);
    procedure ClearPipelineLibraries;
    procedure ClearFallbackFramebuffers;
    procedure ClearFallbackRenderPasses;
    procedure SetAntiAliasing(const AValue: TAntiAliasing);
    procedure SetSampleCount(const AValue: Cardinal);
    procedure SetSupportsExtendedDynamicState(const AValue: Boolean);
    procedure SetSupportsSynchronization2(const AValue: Boolean);
    procedure SetSupportsTimelineSemaphores(const AValue: Boolean);
    function IsDeviceExtensionSupported(const AExtensionName: AnsiString): Boolean;
    function ComputePipelineHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
    function GetPipelineCount: Cardinal;
    function GetComputePipelineCount: Cardinal;
    function GetVertexInputLibraryCount: Cardinal;
    function GetPreRasterizationLibraryCount: Cardinal;
    function GetFragmentShaderLibraryCount: Cardinal;
    function GetFragmentOutputLibraryCount: Cardinal;
    function GetTotalPipelineLibraryCount: Cardinal;
    function GetFallbackRenderPassCount: Cardinal;
    function GetFallbackFramebufferCount: Cardinal;
    function GetPendingDeferredDeletionCount: Cardinal;
    function GetDescriptorPoolHandle: VkDescriptorPool;
    function GetComputeCuller: TCastleVulkanComputeCuller;
    function GetIBLGenerator: TCastleVulkanIBLGenerator;
    function GetClusteredLightCuller: TCastleVulkanClusteredLightCuller;
    function GetShadowAtlas: TCastleVulkanShadowAtlas;
    function GetHDRPostProcessor: TCastleVulkanHDRPostProcessor;
    function GetGTAO: TCastleVulkanGTAO;
    function GetSSR: TCastleVulkanSSR;
    function GetVolumetricFog: TCastleVulkanVolumetricFog;
    function GetTAA: TCastleVulkanTAA;
    function GetReflectionProbeManager: TCastleVulkanReflectionProbeManager;
    function GetDecalManager: TCastleVulkanDecalManager;
    function GetComputeParticles: TCastleVulkanComputeParticles;
    function GetWeightedBlendedOIT: TCastleVulkanWeightedBlendedOIT;
    function GetContactShadows: TCastleVulkanContactShadows;
    function GetComputeSkinner: TCastleVulkanComputeSkinner;
    function GetTerrainCDLOD: TCastleVulkanTerrainCDLOD;
    function GetAtmosphereRenderer: TCastleVulkanAtmosphereRenderer;
    function GetOceanSimulator: TCastleVulkanOceanSimulator;
    function GetDDGIGrid: TCastleVulkanDDGIGrid;
    function GetMeshletCuller: TCastleVulkanMeshletCuller;
    function GetVirtualShadowMap: TCastleVulkanVirtualShadowMap;
    function GetLODSelector: TCastleVulkanLODSelector;
    function GetTextureStreamer: TCastleVulkanTextureStreamer;
    function GetShadowCasterCuller: TCastleVulkanShadowCasterCuller;
    function GetClusterDAG: TCastleVulkanClusterDAG;
    function GetGlobalSDF: TCastleVulkanGlobalSDF;
    function GetSurfaceCache: TCastleVulkanSurfaceCache;
    function GetReSTIR: TCastleVulkanReSTIR;
    function GetTSRUpscaler: TCastleVulkanTSRUpscaler;
    function GetVRSManager: TCastleVulkanVRSManager;
    function GetRuntimeVirtualTexture: TCastleVulkanRuntimeVirtualTexture;
    function GetSparseVolumeAtlas: TCastleVulkanSparseVolumeAtlas;
    function GetBreadcrumbTracker: TCastleVulkanBreadcrumbTracker;
    function GetSVGFDenoiser: TCastleVulkanSVGFDenoiser;
    function GetShaderBindingTable: TCastleVulkanShaderBindingTable;
    function GetAccelerationStructureManager: TCastleVulkanAccelerationStructureManager;
    function GetXPBDSimulator: TCastleVulkanXPBDSimulator;
    function GetMultiviewStereoManager: TCastleVulkanMultiviewStereoManager;
    function GetPerInstanceCustomData: TCastleVulkanPerInstanceCustomData;
    function GetNeuralDenoiser: TCastleVulkanNeuralDenoiser;
    function GetProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations;
    function GetStreamCompactor: TCastleVulkanStreamCompactor;
    function GetVoxelConeTracer: TCastleVulkanVoxelConeTracer;
    function GetMaterialBinner: TCastleVulkanMaterialBinner;
    function GetPerPixelLinkedListOIT: TCastleVulkanPerPixelLinkedListOIT;
    function GetHostImageCopyManager: TCastleVulkanHostImageCopyManager;
    function GetGaussianSplatRenderer: TCastleVulkanGaussianSplatRenderer;
    function GetDescriptorBufferManager: TCastleVulkanDescriptorBufferManager;
    function GetHiZPyramidGenerator: TCastleVulkanHiZPyramidGenerator;
    function GetAutoExposureHistogram: TCastleVulkanAutoExposureHistogram;
    function GetFramePacer: TCastleVulkanFramePacer;
    function GetIndirectComputeDispatcher: TCastleVulkanIndirectComputeDispatcher;
    function GetBCnCompressor: TCastleVulkanBCnCompressor;
    function GetPipelineBinaryManager: TCastleVulkanPipelineBinaryManager;
    function GetWorkerCommandPoolManager: TCastleVulkanWorkerCommandPoolManager;
    function GetBindlessIndirectBatch: TCastleVulkanBindlessIndirectBatch;
    function GetSwapchainSurfaceCount: Cardinal;
    function GetVendorName: String;
  public
    constructor Create(const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
      const InitialWidth, InitialHeight: Cardinal;
      const EnableValidation: Boolean = True); reintroduce; overload;
    { Creates a shared WSI-capable Vulkan RHI device (with all supported OS surface
      instance extensions + VK_KHR_swapchain enabled) that can host 0..N independent
      TCastleVulkanSwapchainSurface child-widget swapchains (Phase 115: TCastleControl). }
    constructor CreateSharedWithWSI(const EnableValidation: Boolean = False;
      const AProbeSurfaceCallback: TVulkanCreateSurfaceEvent = nil); overload;
    class function TryCreateSharedWithWSI(out ADevice: TVulkanRHIDevice;
      const EnableValidation: Boolean = False;
      const AProbeSurfaceCallback: TVulkanCreateSurfaceEvent = nil): Boolean;
    { Creates a real offscreen Vulkan RHI device backed by a physical GPU or
      software rasterizer (e.g. Mesa Lavapipe) without requiring a window surface. }
    constructor CreateOffscreen(const EnableValidation: Boolean = False); overload;
    class function TryCreateOffscreen(out ADevice: TVulkanRHIDevice;
      const EnableValidation: Boolean = False): Boolean;
    { Creates a headless Vulkan RHI device instance (for offscreen/unit testing). }
    constructor CreateHeadless(const APhysicalDevice: VkPhysicalDevice;
      const ASupportsMemoryBudgetExt: Boolean = True;
      const ASupportsDynamicRendering: Boolean = True;
      const ADeviceApiVersion: Cardinal = VK_API_VERSION_1_3;
      const ASupportsGraphicsPipelineLibrary: Boolean = False;
      const ASupportsBindlessTextures: Boolean = True;
      const AMaxBindlessTextures: Cardinal = 4096;
      const ASupportsExtendedDynamicState: Boolean = False); overload;
    destructor Destroy; override;

    { Helper for one-shot transfer commands (texture/buffer uploads) }
    function BeginSingleTimeCommands: VkCommandBuffer;
    procedure EndSingleTimeCommands(const CmdBuf: VkCommandBuffer);
    function FindMemoryType(const TypeFilter: Cardinal;
      const Properties: VkMemoryPropertyFlags): Cardinal;

    { Enqueues or immediately destroys a buffer/image/descriptor-set and its pooled memory sub-allocation.
      When DeferResourceDestruction is True (during in-flight frame rendering), resources
      are retired into FDeferredDeletions[FrameIndex] and freed only after that frame's
      VkFence signals completion. }
    procedure DeferOrDestroyBuffer(const ABuffer: VkBuffer;
      var AAllocation: TVulkanMemoryAllocation; const ADeviceMemory: VkDeviceMemory;
      const AAllocatedSize: VkDeviceSize);
    procedure DeferOrDestroyTexture(const AImage: VkImage; const AImageView: VkImageView;
      var AAllocation: TVulkanMemoryAllocation; const ADeviceMemory: VkDeviceMemory;
      const AAllocatedSize: VkDeviceSize);
    procedure DeferOrDestroyDescriptorSet(const AOwnerPool: VkDescriptorPool;
      const ASet: VkDescriptorSet);
    procedure FlushDeferredDeletions(const AFrameSlot: Integer);
    procedure FlushAllDeferredDeletions;
    function FlushStagingUploads(const ACommandList: TVulkanRHICommandList = nil): Cardinal;

    { Returns the per-frame transient descriptor pool allocator for AFrameIndex. }
    function GetTransientDescriptorAllocator(const AFrameIndex: Cardinal): TVulkanDescriptorPoolAllocator;

    { Allocates a frame-local transient descriptor set from the current frame's
      TransientDescriptorAllocator (bulk-reset in O(1) at the start of BeginFrame). }
    function CreateTransientDescriptorSet(
      const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet;

    { Builds a TRHIRenderingInfo for the swapchain (or an offscreen target), automatically
      attaching transient MSAA color/depth targets and single-pass ResolveTexture when SampleCount > 1. }
    function BuildSwapchainRenderingInfo(const ARenderArea: TRectangle;
      const AResolveColorTarget: TRHITexture;
      const AResolveDepthTarget: TRHITexture;
      const AClearColor: TCastleColor;
      const AColorLoadOp: TRHIAttachmentLoadOp = loClear;
      const ADepthLoadOp: TRHIAttachmentLoadOp = loClear;
      const AClearDepth: Single = 1.0): TRHIRenderingInfo;

    { Queries live GPU VRAM usage and budget via VK_EXT_memory_budget (or heap fallback).
      Returns True if VK_EXT_memory_budget was used. }
    function QueryMemoryBudget(out AUsedBytes, ABudgetBytes: UInt64;
      out AUsedMB, ABudgetMB: Cardinal): Boolean;

    { Compacts fragmented Linear sub-allocations across TCastleVulkanMemoryAllocator blocks,
      relocating live TVulkanRHIBuffer handles via batched vkCmdCopyBuffer commands, refreshing
      any persistent TVulkanRHIDescriptorSet bindings, and freeing emptied VkDeviceMemory blocks (Phase 118). }
    function DefragmentMemoryPools(
      const AMaxBytesToMove: UInt64 = High(UInt64);
      const AMaxAllocationsToMove: Cardinal = High(Cardinal)): TVulkanDefragmentStats;

    { Records diagnostic counters for testing or custom pass tracking. }
    procedure RecordDiagnostics(const APipelineHits, APipelineMisses,
      ADescriptorAllocs: Cardinal; const AAllocatedBytes: UInt64 = 0);

    { Pre-warms standard 3D/2D graphics pipeline state objects (PSOs) and loads/saves
      the Vulkan pipeline cache (DefaultVulkanPipelineCacheUrl) so PSOs are baked
      before the first rendered frame. Returns total cached pipeline count. }
    function PrewarmStandardPipelines(const AIncludeBlending: Boolean = True;
      const AIncludeShadowDepth: Boolean = True;
      const ACacheFileUrl: String = ''): Cardinal;

    { Acquires or creates a cached VK_GRAPHICS_PIPELINE_LIBRARY_VERTEX_INPUT_INTERFACE_BIT_EXT library. }
    function GetOrCreateVertexInputLibrary(
      const AInputDesc: TRHIGraphicsPipelineDesc): VkPipeline;

    { Acquires or creates a cached VK_GRAPHICS_PIPELINE_LIBRARY_PRE_RASTERIZATION_SHADERS_BIT_EXT library. }
    function GetOrCreatePreRasterizationLibrary(
      const AInputDesc: TRHIGraphicsPipelineDesc;
      const ALayout: VkPipelineLayout;
      const ARenderPass: VkRenderPass): VkPipeline;

    { Acquires or creates a cached VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_SHADER_BIT_EXT library. }
    function GetOrCreateFragmentShaderLibrary(
      const AInputDesc: TRHIGraphicsPipelineDesc;
      const ALayout: VkPipelineLayout;
      const ARenderPass: VkRenderPass): VkPipeline;

    { Acquires or creates a cached VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_OUTPUT_INTERFACE_BIT_EXT library. }
    function GetOrCreateFragmentOutputLibrary(
      const AInputDesc: TRHIGraphicsPipelineDesc;
      const ARenderPass: VkRenderPass): VkPipeline;

    { Acquires or creates a cached VkRenderPass for Vulkan 1.1/1.2 devices that lack
      VK_KHR_dynamic_rendering. Supports explicit LoadOp/StoreOp for multi-pass rendering
      and single-pass MSAA resolve attachments (pResolveAttachments) when AHasColorResolve = True. }
    function GetOrCreateFallbackRenderPass(
      const AColorFormats: array of TRHIPixelFormat;
      const ADepthFormat: TRHIPixelFormat;
      const ASampleCount: Cardinal = 1;
      const AColorLoadOp: TRHIAttachmentLoadOp = loClear;
      const ADepthLoadOp: TRHIAttachmentLoadOp = loClear;
      const AColorStoreOp: TRHIAttachmentStoreOp = soStore;
      const ADepthStoreOp: TRHIAttachmentStoreOp = soStore;
      const AHasColorResolve: Boolean = False): VkRenderPass;

    { Acquires or creates a cached VkFramebuffer for Vulkan 1.1/1.2 devices that lack
      VK_KHR_dynamic_rendering. }
    function GetOrCreateFallbackFramebuffer(const ARenderPass: VkRenderPass;
      const AAttachments: array of VkImageView;
      const AWidth, AHeight: Cardinal): VkFramebuffer;

    { TRHIDevice overrides }
    function BeginFrame: TRHICommandList; override;
    procedure EndFrameAndPresent; override;
    function BeginOffscreenFrame: TRHICommandList; override;
    procedure EndOffscreenFrame; override;
    procedure ResizeSwapchain(const NewWidth, NewHeight: Cardinal); override;
    procedure SimulateSwapchainForTesting(const AWidth, AHeight: Cardinal;
      const AImageCount: Cardinal = 2;
      const AColorFormat: TRHIPixelFormat = pfBGRA8_UNorm;
      const ADepthFormat: TRHIPixelFormat = pfD24_UNorm_S8_UInt);
    { Multi-surface / multi-control WSI swapchain management (Phase 115: TCastleControl) }
    function CreateSwapchainSurface(const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
      const InitialWidth, InitialHeight: Cardinal;
      const ADebugName: String = ''): TCastleVulkanSwapchainSurface; overload;
    function CreateSwapchainSurface(const ANativeDesc: TVulkanNativeSurfaceDesc;
      const InitialWidth, InitialHeight: Cardinal;
      const ADebugName: String = ''): TCastleVulkanSwapchainSurface; overload;
    function CreateSimulatedSwapchainSurface(const AWidth, AHeight: Cardinal;
      const AImageCount: Cardinal = 2;
      const AColorFormat: TRHIPixelFormat = pfBGRA8_UNorm;
      const ADepthFormat: TRHIPixelFormat = pfD24_UNorm_S8_UInt;
      const ADebugName: String = ''): TCastleVulkanSwapchainSurface;
    procedure DestroySwapchainSurface(var ASurface: TCastleVulkanSwapchainSurface);
    function GetSwapchainSurface(const AIndex: Integer): TCastleVulkanSwapchainSurface;
    function BeginSurfaceFrame(const ASurface: TCastleVulkanSwapchainSurface): TRHICommandList;
    procedure EndSurfaceFrameAndPresent(const ASurface: TCastleVulkanSwapchainSurface);
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
    function CreateTimelineSemaphore(const AInitialValue: UInt64 = 0): TCastleVulkanTimelineSemaphore;

    function CreateTransientCarrierTexture(const ADesc: TRHITextureDesc;
      const AMinCarrierBytes: UInt64 = 0): TRHITexture; override;
    function TryCreateAliasedTexture(const ADesc: TRHITextureDesc;
      const ACarrierTexture: TRHITexture): TRHITexture; override;

    function GrabTextureImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle): TRGBAlphaImage; overload; override;
    function GrabTextureSubresourceImage(const SourceTexture: TRHITexture;
      const AMipLevel, AArrayLayer: Cardinal): TRGBAlphaImage; override;
    { Reads back any color/HDR/float/depth texture (pfRGBA16_Float, pfRGBA32_Float,
      pfRG16_Float, pfR16_Float, pfR32_Float, pfRGBA8_UNorm, pfBGRA8_UNorm, pfD32_Float)
      into a full-precision TRGBAlphaFloatImage without [0..1] 8-bit clamping. }
    function GrabTextureFloatImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle): TRGBAlphaFloatImage; override;

    procedure LoadPipelineCache(const CacheFileUrl: String); override;
    procedure SavePipelineCache(const CacheFileUrl: String); override;

    { Khronos Validation Layer (VK_LAYER_KHRONOS_validation) & VK_EXT_debug_utils CI Gate & Object Naming (Phases 112.1, 113.1) }
    procedure RecordValidationCallbackMessage(const ASeverity, AMessageTypes: VkFlags;
      const AMessageIdName, AMessage: String);
    function SubmitDebugUtilsMessage(const ASeverity, AMessageTypes: VkFlags;
      const AMessageIdName, AMessage: String): Boolean;
    procedure ResetValidationCounters;
    function GetValidationMessage(const AIndex: Integer): String;
    function GetValidationMessagesReport: String;
    procedure AssertZeroValidationErrors(const AContext: String = '');
    function SetDebugObjectName(const AObjectType: VkObjectType;
      const AObjectHandle: UInt64; const AObjectName: String): Boolean;
    procedure BeginQueueDebugLabel(const ALabelName: String; const AColor: TCastleColor);
    procedure EndQueueDebugLabel;
    procedure InsertQueueDebugLabel(const ALabelName: String; const AColor: TCastleColor);
    function GetDefaultSampler: TVulkanRHISampler;
    function GetDefaultShadowSampler: TVulkanRHISampler;
    function GetDefaultBrdfLutSampler: TVulkanRHISampler;
    function GetDefaultWhiteTexture: TVulkanRHITexture;
    function GetDefaultBlackTexture: TVulkanRHITexture;
    function GetDefaultFlatNormalTexture: TVulkanRHITexture;
    function GetDefaultShadowDepthTexture: TVulkanRHITexture;
    function GetDefaultBrdfLutTexture: TVulkanRHITexture;
    function GetDefaultWhiteCubeTexture: TVulkanRHITexture;

    function GetInformationString: String; override;
    function GetInformationStringSummary: String; override;

    function RegisterBindlessTexture(const ATexture: TRHITexture;
      const ASampler: TRHISampler = nil): Cardinal; override;
    function RegisterOrUpdateBindlessMaterial(var AMaterialIndex: Cardinal;
      var AAlreadyRegistered: Boolean;
      const AEntryData; const AEntrySizeInBytes: Cardinal): Cardinal; override;
    function GetBindlessDescriptorSet: TRHIDescriptorSet; override;

    property InstanceHandle: VkInstance read FInstance;
    property Handle: VkDevice read FDevice;
    property PhysicalDevice: VkPhysicalDevice read FPhysicalDevice;
    property SurfaceHandle: VkSurfaceKHR read GetSurfaceHandle;
    property SwapchainHandle: VkSwapchainKHR read GetSwapchainHandle;
    property ActiveSwapchainSurface: TCastleVulkanSwapchainSurface
      read FActiveSwapchainSurface write FActiveSwapchainSurface;
    property SwapchainSurfaceCount: Cardinal read GetSwapchainSurfaceCount;
    property SwapchainImageCount: Cardinal read GetSwapchainImageCount;
    property SwapchainExtent: VkExtent2D read GetSwapchainExtent;
    property InstanceApiVersion: Cardinal read FInstanceApiVersion;
    property DeviceApiVersion: Cardinal read FDeviceApiVersion write FDeviceApiVersion;
    property AntiAliasing: TAntiAliasing read FAntiAliasing write SetAntiAliasing;
    property SampleCount: Cardinal read FSampleCount write SetSampleCount;
    property ActiveColorTarget: TRHITexture read FActiveColorTarget write FActiveColorTarget;
    property ActiveDepthTarget: TRHITexture read FActiveDepthTarget write FActiveDepthTarget;
    property SwapchainFormat: TRHIPixelFormat read FSwapchainFormat;
    property SwapchainDepthFormat: TRHIPixelFormat read FSwapchainDepthFormat;
    property SwapchainColorSpace: VkColorSpaceKHR read FSwapchainColorSpace;
    property SwapchainPresentMode: VkPresentModeKHR read FSwapchainPresentMode;
    property SwapchainCompositeAlpha: Integer read FSwapchainCompositeAlpha;
    property SwapchainPreTransform: Integer read FSwapchainPreTransform;
    property SwapchainMinimized: Boolean read FSwapchainMinimized;
    property SwapchainSuboptimal: Boolean read FSwapchainSuboptimal;
    property SwapchainRecreateCount: Cardinal read FSwapchainRecreateCount;
    property CurrentSwapchainImageIndex: Cardinal read FCurrentSwapchainImageIndex;
    property SwapchainMSAAColorTexture: TVulkanRHITexture read FSwapchainMSAAColorTexture;
    property SwapchainMSAADepthTexture: TVulkanRHITexture read FSwapchainMSAADepthTexture;
    property MSAAResolvePassCount: Cardinal read FMSAAResolvePassCount;
    property DescriptorPool: VkDescriptorPool read GetDescriptorPoolHandle;
    property PersistentDescriptorAllocator: TVulkanDescriptorPoolAllocator read FPersistentDescriptorAllocator;
    property PipelineCache: VkPipelineCache read FPipelineCache;
    property PipelineCount: Cardinal read GetPipelineCount;
    property ComputePipelineCount: Cardinal read GetComputePipelineCount;
    property PipelineCacheLoaded: Boolean read FPipelineCacheLoaded;
    property PipelineCacheSeededFromBundle: Boolean read FPipelineCacheSeededFromBundle;
    property BundledPipelineCacheFallbackUrl: String read FBundledPipelineCacheFallbackUrl write FBundledPipelineCacheFallbackUrl;
    property DebugMessengerHandle: VkDebugUtilsMessengerEXT read FDebugMessenger;
    property ValidationLayerActive: Boolean read FValidationLayerActive;
    property DebugUtilsActive: Boolean read FDebugUtilsActive;
    property StrictValidationGate: Boolean read FStrictValidationGate write FStrictValidationGate;
    property ValidationErrorCount: Cardinal read FValidationErrorCount;
    property ValidationWarningCount: Cardinal read FValidationWarningCount;
    property ValidationInfoCount: Cardinal read FValidationInfoCount;
    property ValidationMessageCount: Integer read GetValidationMessageCount;
    property VendorKind: TVulkanVendorID read FVendorKind;
    property VendorName: String read GetVendorName;
    property DriverId: Integer read FDriverId;
    property DriverName: String read FDriverName;
    property DriverInfo: String read FDriverInfo;
    property IsPortabilitySubsetDevice: Boolean read FIsPortabilitySubsetDevice write FIsPortabilitySubsetDevice;
    property PortabilitySubsetCaps: TVulkanPortabilitySubsetCaps read FPortabilitySubsetCaps write FPortabilitySubsetCaps;
    property MaxPerStageDescriptorSamplers: Cardinal read FMaxPerStageDescriptorSamplers;
    property DebugObjectsNamedCount: Cardinal read FDebugObjectsNamedCount;
    property LastNamedDebugObject: String read FLastNamedDebugObject;
    property SupportsMemoryBudgetExt: Boolean read FSupportsMemoryBudgetExt;
    property SupportsDynamicRendering: Boolean read FSupportsDynamicRendering write FSupportsDynamicRendering;
    property SupportsGraphicsPipelineLibrary: Boolean read FSupportsGraphicsPipelineLibrary write FSupportsGraphicsPipelineLibrary;
    property SupportsGPLFastLinking: Boolean read FSupportsGPLFastLinking write FSupportsGPLFastLinking;
    property SupportsBindlessTextures: Boolean read FSupportsBindlessTextures write FSupportsBindlessTextures;
    property SupportsBindlessUpdateAfterBind: Boolean read FSupportsBindlessUpdateAfterBind write FSupportsBindlessUpdateAfterBind;
    property SupportsExtendedDynamicState: Boolean read FSupportsExtendedDynamicState write SetSupportsExtendedDynamicState;
    property SupportsSynchronization2: Boolean read FSupportsSynchronization2 write SetSupportsSynchronization2;
    property SupportsTimelineSemaphores: Boolean read FSupportsTimelineSemaphores write SetSupportsTimelineSemaphores;
    property SupportsHostQueryReset: Boolean read FSupportsHostQueryReset write FSupportsHostQueryReset;
    property SupportsOcclusionQueryPrecise: Boolean read FSupportsOcclusionQueryPrecise write FSupportsOcclusionQueryPrecise;
    property SupportsShaderDrawParameters: Boolean read FSupportsShaderDrawParameters write FSupportsShaderDrawParameters;
    property SupportsBufferDeviceAddress: Boolean read FSupportsBufferDeviceAddress write FSupportsBufferDeviceAddress;
    property SupportsAccelerationStructure: Boolean read FSupportsAccelerationStructure write FSupportsAccelerationStructure;
    property SupportsRayQuery: Boolean read FSupportsRayQuery write FSupportsRayQuery;
    property SupportsRayTracingPipeline: Boolean read FSupportsRayTracingPipeline write FSupportsRayTracingPipeline;
    property SupportsMeshShaders: Boolean read FSupportsMeshShaders write FSupportsMeshShaders;
    property SupportsTaskShaders: Boolean read FSupportsTaskShaders write FSupportsTaskShaders;
    property RTShaderGroupHandleSize: Cardinal read FRTShaderGroupHandleSize;
    property RTShaderGroupHandleAlignment: Cardinal read FRTShaderGroupHandleAlignment;
    property RTShaderGroupBaseAlignment: Cardinal read FRTShaderGroupBaseAlignment;
    property MaxBindlessTextures: Cardinal read FMaxBindlessTextures write FMaxBindlessTextures;
    property BindlessTextureManager: TCastleVulkanBindlessTextureManager read FBindlessTextureManager;
    property TimestampProfiler: TCastleVulkanTimestampProfiler read FTimestampProfiler;
    property TotalFramesPresented: Cardinal read FTotalFramesPresented;
    property ComputeCuller: TCastleVulkanComputeCuller read GetComputeCuller;
    property IBLGenerator: TCastleVulkanIBLGenerator read GetIBLGenerator;
    property ClusteredLightCuller: TCastleVulkanClusteredLightCuller read GetClusteredLightCuller;
    property ShadowAtlas: TCastleVulkanShadowAtlas read GetShadowAtlas;
    property HDRPostProcessor: TCastleVulkanHDRPostProcessor read GetHDRPostProcessor;
    property GTAO: TCastleVulkanGTAO read GetGTAO;
    property SSR: TCastleVulkanSSR read GetSSR;
    property VolumetricFog: TCastleVulkanVolumetricFog read GetVolumetricFog;
    property TAA: TCastleVulkanTAA read GetTAA;
    property ReflectionProbeManager: TCastleVulkanReflectionProbeManager read GetReflectionProbeManager;
    property DecalManager: TCastleVulkanDecalManager read GetDecalManager;
    property ComputeParticles: TCastleVulkanComputeParticles read GetComputeParticles;
    property WeightedBlendedOIT: TCastleVulkanWeightedBlendedOIT read GetWeightedBlendedOIT;
    property ContactShadows: TCastleVulkanContactShadows read GetContactShadows;
    property ComputeSkinner: TCastleVulkanComputeSkinner read GetComputeSkinner;
    property TerrainCDLOD: TCastleVulkanTerrainCDLOD read GetTerrainCDLOD;
    property AtmosphereRenderer: TCastleVulkanAtmosphereRenderer read GetAtmosphereRenderer;
    property OceanSimulator: TCastleVulkanOceanSimulator read GetOceanSimulator;
    property DDGIGrid: TCastleVulkanDDGIGrid read GetDDGIGrid;
    property MeshletCuller: TCastleVulkanMeshletCuller read GetMeshletCuller;
    property VirtualShadowMap: TCastleVulkanVirtualShadowMap read GetVirtualShadowMap;
    property LODSelector: TCastleVulkanLODSelector read GetLODSelector;
    property TextureStreamer: TCastleVulkanTextureStreamer read GetTextureStreamer;
    property ShadowCasterCuller: TCastleVulkanShadowCasterCuller read GetShadowCasterCuller;
    property ClusterDAG: TCastleVulkanClusterDAG read GetClusterDAG;
    property GlobalSDF: TCastleVulkanGlobalSDF read GetGlobalSDF;
    property SurfaceCache: TCastleVulkanSurfaceCache read GetSurfaceCache;
    property ReSTIR: TCastleVulkanReSTIR read GetReSTIR;
    property TSRUpscaler: TCastleVulkanTSRUpscaler read GetTSRUpscaler;
    property VRSManager: TCastleVulkanVRSManager read GetVRSManager;
    property RuntimeVirtualTexture: TCastleVulkanRuntimeVirtualTexture read GetRuntimeVirtualTexture;
    property SparseVolumeAtlas: TCastleVulkanSparseVolumeAtlas read GetSparseVolumeAtlas;
    property BreadcrumbTracker: TCastleVulkanBreadcrumbTracker read GetBreadcrumbTracker;
    property SVGFDenoiser: TCastleVulkanSVGFDenoiser read GetSVGFDenoiser;
    property ShaderBindingTable: TCastleVulkanShaderBindingTable read GetShaderBindingTable;
    property AccelerationStructureManager: TCastleVulkanAccelerationStructureManager read GetAccelerationStructureManager;
    property XPBDSimulator: TCastleVulkanXPBDSimulator read GetXPBDSimulator;
    property MultiviewStereoManager: TCastleVulkanMultiviewStereoManager read GetMultiviewStereoManager;
    property PerInstanceCustomData: TCastleVulkanPerInstanceCustomData read GetPerInstanceCustomData;
    property NeuralDenoiser: TCastleVulkanNeuralDenoiser read GetNeuralDenoiser;
    property ProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations read GetProgrammableSampleLocations;
    property StreamCompactor: TCastleVulkanStreamCompactor read GetStreamCompactor;
    property VoxelConeTracer: TCastleVulkanVoxelConeTracer read GetVoxelConeTracer;
    property MaterialBinner: TCastleVulkanMaterialBinner read GetMaterialBinner;
    property PerPixelLinkedListOIT: TCastleVulkanPerPixelLinkedListOIT read GetPerPixelLinkedListOIT;
    property HostImageCopyManager: TCastleVulkanHostImageCopyManager read GetHostImageCopyManager;
    property GaussianSplatRenderer: TCastleVulkanGaussianSplatRenderer read GetGaussianSplatRenderer;
    property DescriptorBufferManager: TCastleVulkanDescriptorBufferManager read GetDescriptorBufferManager;
    property HiZPyramidGenerator: TCastleVulkanHiZPyramidGenerator read GetHiZPyramidGenerator;
    property AutoExposureHistogram: TCastleVulkanAutoExposureHistogram read GetAutoExposureHistogram;
    property FramePacer: TCastleVulkanFramePacer read GetFramePacer;
    property IndirectComputeDispatcher: TCastleVulkanIndirectComputeDispatcher read GetIndirectComputeDispatcher;
    property BCnCompressor: TCastleVulkanBCnCompressor read GetBCnCompressor;
    property PipelineBinaryManager: TCastleVulkanPipelineBinaryManager read GetPipelineBinaryManager;
    property WorkerCommandPoolManager: TCastleVulkanWorkerCommandPoolManager read GetWorkerCommandPoolManager;
    property BindlessIndirectBatch: TCastleVulkanBindlessIndirectBatch read GetBindlessIndirectBatch;
    property VertexInputLibraryCount: Cardinal read GetVertexInputLibraryCount;
    property PreRasterizationLibraryCount: Cardinal read GetPreRasterizationLibraryCount;
    property FragmentShaderLibraryCount: Cardinal read GetFragmentShaderLibraryCount;
    property FragmentOutputLibraryCount: Cardinal read GetFragmentOutputLibraryCount;
    property TotalPipelineLibraryCount: Cardinal read GetTotalPipelineLibraryCount;
    property GPLFastLinkedPipelineCount: Cardinal read FGPLFastLinkedPipelineCount;
    property GPLLibraryCacheHits: Cardinal read FGPLLibraryCacheHits;
    property GPLLibraryCacheMisses: Cardinal read FGPLLibraryCacheMisses;
    property FallbackRenderPassCount: Cardinal read GetFallbackRenderPassCount;
    property FallbackFramebufferCount: Cardinal read GetFallbackFramebufferCount;
    property FallbackRenderPassBeginCount: Cardinal read FFallbackRenderPassBeginCount;
    property PipelineCacheHits: Cardinal read FPipelineCacheHits;
    property PipelineCacheMisses: Cardinal read FPipelineCacheMisses;
    property ComputePipelineCacheHits: Cardinal read FComputePipelineCacheHits;
    property ComputePipelineCacheMisses: Cardinal read FComputePipelineCacheMisses;
    property ComputeDispatchCount: Cardinal read FComputeDispatchCount;
    property Sync2BarrierCount: Cardinal read FSync2BarrierCount;
    property DescriptorSetAllocations: Cardinal read FDescriptorSetAllocations;
    property AllocatedMemoryBytes: Int64 read FAllocatedMemoryBytes;
    property MemoryAllocator: TCastleVulkanMemoryAllocator read FMemoryAllocator;
    property StagingUploader: TCastleVulkanStagingUploader read FStagingUploader;
    property GraphicsQueue: VkQueue read FGraphicsQueue;
    property PresentQueue: VkQueue read FPresentQueue;
    property TransferQueue: VkQueue read FTransferQueue;
    property GraphicsQueueFamily: Cardinal read FGraphicsQueueFamily;
    property PresentQueueFamily: Cardinal read FPresentQueueFamily;
    property TransferQueueFamily: Cardinal read FTransferQueueFamily;
    property HasDedicatedTransferQueue: Boolean read FHasDedicatedTransferQueue;
    property DeferResourceDestruction: Boolean read FDeferResourceDestruction write FDeferResourceDestruction;
    property PendingDeferredDeletionCount: Cardinal read GetPendingDeferredDeletionCount;
    property FrameIndex: Cardinal read FFrameIndex write FFrameIndex;
  end;

{ Selects the optimal transfer queue family index from AQueueFamilies:
  1. Prefers a dedicated DMA transfer queue family (VK_QUEUE_TRANSFER_BIT without
     VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT, e.g. AMD SDMA / NVIDIA Copy Engine).
  2. Falls back to an async compute+transfer queue family distinct from AGraphicsQueueFamily.
  3. Falls back to AGraphicsQueueFamily (AIsDedicatedTransferQueue = False). }
function SelectTransferQueueFamilyIndex(
  const AQueueFamilies: array of VkQueueFamilyProperties;
  const AGraphicsQueueFamily: Cardinal;
  out AIsDedicatedTransferQueue: Boolean): Cardinal;

{ Returns the highest power-of-two MSAA sample count (64, 32, 16, 8, 4, 2, 1)
  supported simultaneously by both color and depth framebuffer sample count masks. }
function ResolveMaxFramebufferSampleCount(
  const AColorSampleCounts, ADepthSampleCounts: VkSampleCountFlags): Cardinal;

{ Clamps ARequestedSamples down to the highest sample count bit present in ASupportedMask. }
function ClampSampleCountToMask(const ARequestedSamples: Cardinal;
  const ASupportedMask: VkSampleCountFlags): Cardinal;

{ Converts a numeric sample count (1, 2, 4, 8, 16, 32, 64) to VkSampleCountFlagBits. }
function RHIToVkSampleCountFlags(const ASampleCount: Cardinal): VkSampleCountFlags;

{ Converts TRHIResolveMode to VkResolveModeFlagBits. }
function RHIToVkResolveMode(const AResolveMode: TRHIResolveMode): Integer;

{ Converts TRHIStencilOp to VkStencilOp. }
function RHIToVkStencilOp(const AOp: TRHIStencilOp): Integer;

{ Converts TRHIStencilOpStateDesc to VkStencilOpState. }
function RHIToVkStencilOpState(const AState: TRHIStencilOpStateDesc): VkStencilOpState;

{ Converts TRHISamplerFilter to VkFilter. }
function RHIToVkFilter(const AFilter: TRHISamplerFilter): VkFilter;

{ Converts TRHISamplerFilter to VkSamplerMipmapMode. }
function RHIToVkMipmapMode(const AFilter: TRHISamplerFilter): VkSamplerMipmapMode;

{ Converts TRHISamplerAddressMode to VkSamplerAddressMode. }
function RHIToVkAddressMode(const AMode: TRHISamplerAddressMode): VkSamplerAddressMode;

{ Builds a complete VkSamplerCreateInfo from TRHISamplerDesc, clamping MaxAnisotropy to AMaxDeviceAnisotropy. }
function BuildVkSamplerCreateInfo(const ADesc: TRHISamplerDesc;
  const AMaxDeviceAnisotropy: Single = 16.0): VkSamplerCreateInfo;

{ Returns the required VkFormatFeatureFlagBits for a given TRHIPixelFormat and TRHITextureUsageFlags set. }
function GetRequiredVkFormatFeatures(const AFormat: TRHIPixelFormat;
  const AUsage: TRHITextureUsageFlags): VkFlags;

{ Returns the VkImageAspectFlags required for VkImageMemoryBarrier layout transitions
  (includes both DEPTH and STENCIL bits for combined depth-stencil formats per
  VUID-VkImageMemoryBarrier-subresourceRange-09601). }
function GetFormatTransitionAspectMask(const AFormat: TRHIPixelFormat): VkImageAspectFlags;

{ Returns the VkImageAspectFlags required for VkImageView creation
  (restricts combined depth-stencil formats to VK_IMAGE_ASPECT_DEPTH_BIT when
  tuSampled is in AUsage per VUID-VkDescriptorImageInfo-imageView-01976). }
function GetFormatViewAspectMask(const AFormat: TRHIPixelFormat;
  const AUsage: TRHITextureUsageFlags): VkImageAspectFlags;

{ Negotiates a supported TRHIPixelFormat on APhysicalDevice via vkGetPhysicalDeviceFormatProperties,
  automatically falling back across vendor differences (e.g. D24_UNorm_S8_UInt -> D32_Float_S8_UInt
  -> D32_Float -> D16_UNorm on AMD/MoltenVK, or unsupported BC/ASTC/ETC2 -> RGBA8). }
function NegotiateOptimalPixelFormat(const ARequestedFormat: TRHIPixelFormat;
  const AUsage: TRHITextureUsageFlags;
  const APhysicalDevice: VkPhysicalDevice = nil): TRHIPixelFormat;

{ Negotiates the optimal VkSurfaceFormatKHR and matching TRHIPixelFormat from AAvailableFormats,
  preferring B8G8R8A8_UNORM / R8G8B8A8_UNORM with VK_COLOR_SPACE_SRGB_NONLINEAR_KHR so 2D UI and
  standard gamma-encoded scene output match OpenGL's default window backbuffer without double-gamma. }
function SelectVulkanSurfaceFormat(const AAvailableFormats: array of VkSurfaceFormatKHR;
  out ARHIFormat: TRHIPixelFormat): VkSurfaceFormatKHR;

{ Negotiates the VkPresentModeKHR from AAvailableModes, preferring VK_PRESENT_MODE_MAILBOX_KHR
  when APreferLowLatencyNoTear = True and otherwise guaranteed tear-free VK_PRESENT_MODE_FIFO_KHR. }
function SelectVulkanPresentMode(const AAvailableModes: array of VkPresentModeKHR;
  const APreferLowLatencyNoTear: Boolean = False): VkPresentModeKHR;

{ Negotiates a supported VkCompositeAlphaFlagBitsKHR value from ASupportedCompositeAlpha,
  preferring VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR, then PRE_MULTIPLIED, POST_MULTIPLIED, and INHERIT. }
function SelectVulkanCompositeAlpha(const ASupportedCompositeAlpha: VkFlags): Integer;

{ Negotiates a valid VkSurfaceTransformFlagBitsKHR value for VkSwapchainCreateInfoKHR.preTransform
  (per VUID-VkSwapchainCreateInfoKHR-preTransform-01279), preserving ACurrentTransform when present
  in ASupportedTransforms (e.g. rotated Android 90/180/270 mobile panels without compositor penalty)
  and falling back to VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR or the first supported transform bit. }
function SelectVulkanSurfaceTransform(const ASupportedTransforms: VkFlags;
  const ACurrentTransform: Integer): Integer;

{ Classifies a Vulkan PCI / Khronos vendor ID (+ optional VkDriverId / device name) into TVulkanVendorID. }
function ClassifyVulkanVendor(const AVendorId: Cardinal;
  const ADriverId: Integer = 0; const ADeviceName: String = ''): TVulkanVendorID;

{ Returns a human-readable GPU vendor name for AVendor. }
function GetVulkanVendorName(const AVendor: TVulkanVendorID): String;

{ Scores a candidate physical device for PickPhysicalDevice selection, honoring optional
  CASTLE_VULKAN_DEVICE (substring or '#index') and CASTLE_VULKAN_VENDOR filters and preferring
  present-capable Vulkan 1.1+ DISCRETE_GPU > INTEGRATED_GPU > VIRTUAL_GPU > CPU.
  Returns -1 when excluded by ADeviceFilter or AVendorFilter. }
function ScorePhysicalDeviceForSelection(const ADeviceIndex: Cardinal;
  const ADeviceName: String; const AVendorId, ADeviceType, AApiVersion: Cardinal;
  const ASupportsSurface: Boolean;
  const ADeviceFilter: String = '';
  const AVendorFilter: String = ''): Int64;

{ Resolves VK_KHR_portability_subset device requirements (mandatory per
  VUID-VkDeviceCreateInfo-pProperties-04451 on macOS/iOS MoltenVK) and populates ACaps. }
procedure ResolvePortabilitySubsetConfig(const AHasPortabilitySubsetExt: Boolean;
  const AFeatures: VkPhysicalDevicePortabilitySubsetFeaturesKHR;
  const AProps: VkPhysicalDevicePortabilitySubsetPropertiesKHR;
  out ACaps: TVulkanPortabilitySubsetCaps;
  out ARequiredExtensions: TAnsiStringArray);

{ Adapts a TRHIGraphicsPipelineDesc to satisfy VK_KHR_portability_subset limits on MoltenVK
  (pointPolygons = False -> pmFill, constantAlphaColorBlendFactors = False -> ConstantColor,
  and minVertexInputBindingStrideAlignment power-of-two stride alignment). }
function AdaptPipelineDescForPortabilitySubset(const ADesc: TRHIGraphicsPipelineDesc;
  const APortability: TVulkanPortabilitySubsetCaps): TRHIGraphicsPipelineDesc;

{ Negotiates the highest supported VkApplicationInfo.apiVersion (1.3, 1.2, 1.1, or 1.0)
  for a given loader version reported by vkEnumerateInstanceVersion. }
function NegotiateInstanceApiVersion(const ALoaderVersion: Cardinal): Cardinal;

{ Resolves whether a Vulkan 1.1, 1.2, or 1.3+ physical device can use dynamic rendering
  (and which KHR prerequisite extensions must be enabled on VkDeviceCreateInfo) or should
  fall back to standard Vulkan 1.1 VkRenderPass + VkFramebuffer passes. }
procedure ResolveVulkan11_12DeviceConfig(const ADeviceApiVersion: Cardinal;
  const AHasDynamicRenderingExt, AHasDepthStencilResolveExt, AHasCreateRenderPass2Ext: Boolean;
  out AUseDynamicRendering: Boolean; out ARequiredExtensions: TAnsiStringArray);

{ Resolves whether a Vulkan physical device can use VK_EXT_graphics_pipeline_library
  (requiring VK_KHR_pipeline_library, VK_EXT_graphics_pipeline_library, and the
  graphicsPipelineLibrary feature) and returns the required device extensions. }
procedure ResolveGraphicsPipelineLibraryConfig(const ADeviceApiVersion: Cardinal;
  const AHasPipelineLibraryExt, AHasGraphicsPipelineLibraryExt, AHasGPLFeature: Boolean;
  out AUseGPL: Boolean; out ARequiredExtensions: TAnsiStringArray);

{ Resolves whether a Vulkan physical device supports bindless texture & sampler indexing
  via Vulkan 1.2+ core or Vulkan 1.1 + VK_EXT_descriptor_indexing (+ VK_KHR_maintenance3),
  validating shaderSampledImageArrayNonUniformIndexing, descriptorBindingPartiallyBound,
  descriptorBindingUpdateUnusedWhilePending, and runtimeDescriptorArray, and clamping
  MaxBindlessTextures to hardware descriptor limits. }
procedure ResolveDescriptorIndexingConfig(const ADeviceApiVersion: Cardinal;
  const AHasDescriptorIndexingExt, AHasMaintenance3Ext: Boolean;
  const AFeatures: VkPhysicalDeviceDescriptorIndexingFeatures;
  const AProps: VkPhysicalDeviceDescriptorIndexingProperties;
  const ARequestedMaxTextures: Cardinal;
  out AUseBindless, AUseUpdateAfterBind: Boolean;
  out AClampedMaxTextures: Cardinal;
  out ARequiredExtensions: TAnsiStringArray);

{ Resolves whether a Vulkan 1.1, 1.2, or 1.3+ physical device supports Extended Dynamic State,
  Synchronization2 (vkCmdPipelineBarrier2), and Timeline Semaphores (64-bit counters),
  and returns any extension strings required for pre-1.3 / pre-1.2 devices. }
procedure ResolveExtendedDynamicStateAndSync2Config(const ADeviceApiVersion: Cardinal;
  const AHasExtDynStateExt, AHasSync2Ext, AHasTimelineSemExt: Boolean;
  const AExtDynStateFeature, ASync2Feature, ATimelineSemFeature: Boolean;
  out AUseExtDynState, AUseSync2, AUseTimelineSem: Boolean;
  out ARequiredExtensions: TAnsiStringArray);

{ Computes a deterministic 64-bit FNV-1a hash for a graphics pipeline state descriptor.
  When AIgnoreExtendedDynamicStates = True (VK_EXT_extended_dynamic_state / Vulkan 1.3),
  CullMode, FrontFace, Topology, DepthTestEnable, DepthWriteEnable, and DepthCompareOp
  are excluded from the hash so pipelines differing only in dynamic states share a single PSO. }
function ComputePipelineKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
function ComputePipelineKeyHashEx(const ADesc: TRHIGraphicsPipelineDesc;
  const AIgnoreExtendedDynamicStates: Boolean): UInt64;

{ Computes a deterministic 64-bit FNV-1a hash for a compute pipeline state descriptor. }
function ComputeComputePipelineKeyHash(const ADesc: TRHIComputePipelineDesc): UInt64;

{ Computes deterministic 64-bit FNV-1a hashes for the 4 VK_EXT_graphics_pipeline_library subsets. }
function ComputeVertexInputLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
function ComputePreRasterizationLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
function ComputeFragmentShaderLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
function ComputeFragmentOutputLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;

{ Computes a deterministic 64-bit FNV-1a hash for a fallback VkRenderPass signature. }
function ComputeRenderPassKeyHash(const AColorFormats: array of TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat; const ASampleCount: Cardinal = 1;
  const AColorLoadOp: TRHIAttachmentLoadOp = loClear;
  const ADepthLoadOp: TRHIAttachmentLoadOp = loClear;
  const AColorStoreOp: TRHIAttachmentStoreOp = soStore;
  const ADepthStoreOp: TRHIAttachmentStoreOp = soStore;
  const AHasColorResolve: Boolean = False): UInt64;

{ Computes a deterministic 64-bit FNV-1a hash for a fallback VkFramebuffer signature. }
function ComputeFramebufferKeyHash(const ARenderPass: VkRenderPass;
  const AAttachments: array of VkImageView; const AWidth, AHeight: Cardinal): UInt64;

const
  DefaultVulkanPipelineCacheUrl        = 'castle-config:/vulkan_pipeline_cache.bin';
  DefaultBundledVulkanPipelineCacheUrl = 'castle-data:/vulkan_pipeline_cache.bin';
  PipelineCacheDiskMagic = $43474550; // 'CGEP'
  PipelineCacheDiskVersion = 1;

{ Returns True if Vulkan validation is requested explicitly or via environment variables
  CASTLE_VULKAN_VALIDATION=1 / CASTLE_VULKAN_VALIDATION_STRICT=1. }
function ShouldEnableVulkanValidationByEnv(const ARequested: Boolean): Boolean;

{ Returns True when CASTLE_VULKAN_VALIDATION_STRICT=1 is set (treating validation warnings as gate failures). }
function IsVulkanStrictValidationGateEnv: Boolean;

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

{ Converts IEEE 754 binary16 (16-bit half-float) to 32-bit Single and vice versa. }
function HalfFloatToFloat(const AHalf: Word): Single;
function FloatToHalfFloat(const AValue: Single): Word;

{$endif read_interface}

{$ifdef read_implementation}
{ ---------------------------------------------------------------------------- }
{ TCastleVulkanSwapchainSurface                                                }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanSwapchainSurface.Create(const ADevice: TVulkanRHIDevice;
  const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
  const InitialWidth, InitialHeight: Cardinal;
  const ADebugName: String);
var
  PresentSupport: VkBool32;
begin
  inherited Create;
  if ADevice = nil then
    raise ERHIError.Create('TCastleVulkanSwapchainSurface requires a non-nil TVulkanRHIDevice');
  FDevice := ADevice;
  FDebugName := ADebugName;
  FAntiAliasing := aaNone;
  FSampleCount := 1;
  FSwapchainFormat := pfBGRA8_UNorm;
  FSwapchainDepthFormat := pfD24_UNorm_S8_UInt;
  FSwapchainColorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  FSwapchainPresentMode := VK_PRESENT_MODE_FIFO_KHR;
  FSwapchainCompositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  FSwapchainPreTransform := VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  FRequestedWidth := InitialWidth;
  FRequestedHeight := InitialHeight;

  CreateSyncObjects;

  if Assigned(ACreateSurfaceCallback) then
  begin
    FSurface := ACreateSurfaceCallback(FDevice.InstanceHandle);
    FOwnsSurface := True;
  end;
  if (FDevice.Handle <> nil) and (FSurface = VK_NULL_HANDLE) then
    raise ERHIError.Create('Failed to create Vulkan control surface (VkSurfaceKHR)');

  { Query presentation support on this specific VkSurfaceKHR handle per
    VUID-vkCreateSwapchainKHR-surface-01270 before creating its VkSwapchainKHR. }
  if (FDevice.Handle <> nil) and (FSurface <> VK_NULL_HANDLE) and
     Assigned(vkGetPhysicalDeviceSurfaceSupportKHR) then
  begin
    PresentSupport := VK_FALSE;
    CheckVk(vkGetPhysicalDeviceSurfaceSupportKHR(
      FDevice.PhysicalDevice, FDevice.PresentQueueFamily, FSurface, @PresentSupport),
      'vkGetPhysicalDeviceSurfaceSupportKHR(ControlSurface)');
    if PresentSupport <> VK_TRUE then
      raise ERHIError.CreateFmt(
        'Vulkan queue family %d on physical device "%s" does not support presenting to control surface "%s"',
        [FDevice.PresentQueueFamily, FDevice.Capabilities.DeviceName, FDebugName]);
    if FDevice.GraphicsQueueFamily <> FDevice.PresentQueueFamily then
    begin
      PresentSupport := VK_FALSE;
      vkGetPhysicalDeviceSurfaceSupportKHR(
        FDevice.PhysicalDevice, FDevice.GraphicsQueueFamily, FSurface, @PresentSupport);
    end;
  end;

  if (FDevice.Handle <> nil) and (FSurface <> VK_NULL_HANDLE) then
    CreateSwapchain(InitialWidth, InitialHeight)
  else if FDevice.Handle = nil then
    SimulateForTesting(Max(Cardinal(1), InitialWidth), Max(Cardinal(1), InitialHeight), 2);
end;

constructor TCastleVulkanSwapchainSurface.Create(const ADevice: TVulkanRHIDevice;
  const ANativeDesc: TVulkanNativeSurfaceDesc;
  const InitialWidth, InitialHeight: Cardinal;
  const ADebugName: String);
var
  PresentSupport: VkBool32;
begin
  inherited Create;
  if ADevice = nil then
    raise ERHIError.Create('TCastleVulkanSwapchainSurface requires a non-nil TVulkanRHIDevice');
  FDevice := ADevice;
  FDebugName := ADebugName;
  FAntiAliasing := aaNone;
  FSampleCount := 1;
  FSwapchainFormat := pfBGRA8_UNorm;
  FSwapchainDepthFormat := pfD24_UNorm_S8_UInt;
  FSwapchainColorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  FSwapchainPresentMode := VK_PRESENT_MODE_FIFO_KHR;
  FSwapchainCompositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  FSwapchainPreTransform := VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  FRequestedWidth := InitialWidth;
  FRequestedHeight := InitialHeight;

  CreateSyncObjects;

  if FDevice.Handle <> nil then
  begin
    FSurface := CreateVulkanSurfaceFromNativeDesc(FDevice.InstanceHandle, ANativeDesc);
    FOwnsSurface := True;
    if FSurface = VK_NULL_HANDLE then
      raise ERHIError.Create('Failed to create Vulkan control surface (VkSurfaceKHR) from native descriptor');

    if Assigned(vkGetPhysicalDeviceSurfaceSupportKHR) then
    begin
      PresentSupport := VK_FALSE;
      CheckVk(vkGetPhysicalDeviceSurfaceSupportKHR(
        FDevice.PhysicalDevice, FDevice.PresentQueueFamily, FSurface, @PresentSupport),
        'vkGetPhysicalDeviceSurfaceSupportKHR(ControlSurface)');
      if PresentSupport <> VK_TRUE then
        raise ERHIError.CreateFmt(
          'Vulkan queue family %d on physical device "%s" does not support presenting to control surface "%s"',
          [FDevice.PresentQueueFamily, FDevice.Capabilities.DeviceName, FDebugName]);
      if FDevice.GraphicsQueueFamily <> FDevice.PresentQueueFamily then
      begin
        PresentSupport := VK_FALSE;
        vkGetPhysicalDeviceSurfaceSupportKHR(
          FDevice.PhysicalDevice, FDevice.GraphicsQueueFamily, FSurface, @PresentSupport);
      end;
    end;

    CreateSwapchain(InitialWidth, InitialHeight);
  end else
    SimulateForTesting(Max(Cardinal(1), InitialWidth), Max(Cardinal(1), InitialHeight), 2);
end;

constructor TCastleVulkanSwapchainSurface.CreateSimulatedForTesting(
  const ADevice: TVulkanRHIDevice;
  const AWidth, AHeight: Cardinal;
  const AImageCount: Cardinal;
  const AColorFormat, ADepthFormat: TRHIPixelFormat;
  const ADebugName: String);
begin
  inherited Create;
  if ADevice = nil then
    raise ERHIError.Create('TCastleVulkanSwapchainSurface requires a non-nil TVulkanRHIDevice');
  FDevice := ADevice;
  FDebugName := ADebugName;
  FAntiAliasing := aaNone;
  FSampleCount := 1;
  FSwapchainColorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  FSwapchainPresentMode := VK_PRESENT_MODE_FIFO_KHR;
  FSwapchainCompositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  FSwapchainPreTransform := VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  SimulateForTesting(AWidth, AHeight, AImageCount, AColorFormat, ADepthFormat);
end;

destructor TCastleVulkanSwapchainSurface.Destroy;
begin
  DestroySwapchainResources(True);
  DestroySyncObjects;
  if FOwnsSurface and (FSurface <> VK_NULL_HANDLE) and
     (FDevice <> nil) and (FDevice.InstanceHandle <> nil) and
     Assigned(vkDestroySurfaceKHR) then
  begin
    vkDestroySurfaceKHR(FDevice.InstanceHandle, FSurface, nil);
    FSurface := VK_NULL_HANDLE;
  end;
  inherited;
end;

procedure TCastleVulkanSwapchainSurface.CreateSyncObjects;
var
  I: Integer;
  SemInfo: VkSemaphoreCreateInfo;
begin
  for I := 0 to MaxFramesInFlight - 1 do
    FImageAvailableSemaphores[I] := VK_NULL_HANDLE;
  if (FDevice = nil) or (FDevice.Handle = nil) or (not Assigned(vkCreateSemaphore)) then
    Exit;

  FillChar(SemInfo, SizeOf(SemInfo), 0);
  SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
  for I := 0 to MaxFramesInFlight - 1 do
  begin
    CheckVk(vkCreateSemaphore(FDevice.Handle, @SemInfo, nil, @FImageAvailableSemaphores[I]),
      'vkCreateSemaphore(SurfaceImageAvailable)');
    if FDebugName <> '' then
      FDevice.SetDebugObjectName(VK_OBJECT_TYPE_SEMAPHORE, FImageAvailableSemaphores[I],
        Format('%s_ImageAvailable_%d', [FDebugName, I]));
  end;
end;

procedure TCastleVulkanSwapchainSurface.DestroySyncObjects;
var
  I: Integer;
begin
  for I := 0 to MaxFramesInFlight - 1 do
  begin
    if (FImageAvailableSemaphores[I] <> VK_NULL_HANDLE) and
       (FDevice <> nil) and (FDevice.Handle <> nil) and Assigned(vkDestroySemaphore) then
      vkDestroySemaphore(FDevice.Handle, FImageAvailableSemaphores[I], nil);
    FImageAvailableSemaphores[I] := VK_NULL_HANDLE;
  end;
end;

procedure TCastleVulkanSwapchainSurface.EnsureMSAATargets(
  const AWidth, AHeight: Cardinal;
  const AColorFormat, ADepthFormat: TRHIPixelFormat);
var
  EffSamples: Cardinal;
  MSAAColorDesc, MSAADepthDesc: TRHITextureDesc;
  NamePrefix: String;
begin
  EffSamples := Max(Cardinal(1), FSampleCount);
  if (FDevice <> nil) and (FDevice.Capabilities.MaxFramebufferSampleCount > 0) then
    EffSamples := Min(EffSamples, FDevice.Capabilities.MaxFramebufferSampleCount);

  if (EffSamples <= 1) or (AWidth = 0) or (AHeight = 0) or (FDevice = nil) then
  begin
    FreeAndNil(FMSAAColorTexture);
    FreeAndNil(FMSAADepthTexture);
    Exit;
  end;

  if FDebugName <> '' then
    NamePrefix := FDebugName + '_'
  else
    NamePrefix := 'ControlSurface_';

  if (FMSAAColorTexture = nil) or
     (FMSAAColorTexture.Desc.Width <> AWidth) or
     (FMSAAColorTexture.Desc.Height <> AHeight) or
     (FMSAAColorTexture.Desc.Format <> AColorFormat) or
     (FMSAAColorTexture.Desc.SampleCount <> EffSamples) then
  begin
    FreeAndNil(FMSAAColorTexture);
    if AColorFormat <> pfUndefined then
    begin
      MSAAColorDesc := TRHITextureDesc.Create2D(AWidth, AHeight, AColorFormat,
        [tuColorAttachment], 1, EffSamples);
      MSAAColorDesc.DebugName := NamePrefix + 'MSAAColor';
      FMSAAColorTexture := TVulkanRHITexture.Create(FDevice, MSAAColorDesc);
    end;
  end;

  if (FMSAADepthTexture = nil) or
     (FMSAADepthTexture.Desc.Width <> AWidth) or
     (FMSAADepthTexture.Desc.Height <> AHeight) or
     (FMSAADepthTexture.Desc.Format <> ADepthFormat) or
     (FMSAADepthTexture.Desc.SampleCount <> EffSamples) then
  begin
    FreeAndNil(FMSAADepthTexture);
    if ADepthFormat <> pfUndefined then
    begin
      MSAADepthDesc := TRHITextureDesc.Create2D(AWidth, AHeight, ADepthFormat,
        [tuDepthStencil], 1, EffSamples);
      MSAADepthDesc.DebugName := NamePrefix + 'MSAADepth';
      FMSAADepthTexture := TVulkanRHITexture.Create(FDevice, MSAADepthDesc);
    end;
  end;
end;

procedure TCastleVulkanSwapchainSurface.SetAntiAliasing(const AValue: TAntiAliasing);
begin
  FAntiAliasing := AValue;
  SetSampleCount(Max(Cardinal(1), AntiAliasingToSampleCount(AValue)));
end;

procedure TCastleVulkanSwapchainSurface.SetSampleCount(const AValue: Cardinal);
var
  MaxSamples: Cardinal;
begin
  if FDevice <> nil then
    MaxSamples := FDevice.Capabilities.MaxFramebufferSampleCount
  else
    MaxSamples := 8;
  if MaxSamples = 0 then
    MaxSamples := 8;
  FSampleCount := ClampSampleCountToMask(AValue, (MaxSamples shl 1) - 1);
  if FSampleCount <= 1 then
  begin
    FreeAndNil(FMSAAColorTexture);
    FreeAndNil(FMSAADepthTexture);
  end else
  if (FSwapchainExtent.width > 0) and (FSwapchainExtent.height > 0) then
  begin
    if FSwapchainDepthFormat <> pfUndefined then
      EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, FSwapchainDepthFormat)
    else
      EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, pfD24_UNorm_S8_UInt);
  end;
end;

procedure TCastleVulkanSwapchainSurface.CreateSwapchain(const AWidth, AHeight: Cardinal);
var
  Caps: VkSurfaceCapabilitiesKHR;
  SurfaceFormatCount, PresentModeCount, ImageCount, I: Cardinal;
  SurfaceFormats: array of VkSurfaceFormatKHR;
  PresentModes: array of VkPresentModeKHR;
  SurfFmt: VkSurfaceFormatKHR;
  CreateInfo: VkSwapchainCreateInfoKHR;
  QueueFamilyIndices: array[0..1] of Cardinal;
  ImageUsage: VkImageUsageFlags;
  ColorUsage: TRHITextureUsageFlags;
  OldSwapchain: VkSwapchainKHR;
  Images: array of VkImage;
  ViewInfo: VkImageViewCreateInfo;
  SemInfo: VkSemaphoreCreateInfo;
  ImgView: VkImageView;
  ColorDesc, DepthDesc: TRHITextureDesc;
  NamePrefix: String;
begin
  if (AWidth > 0) and (AHeight > 0) then
  begin
    FRequestedWidth := AWidth;
    FRequestedHeight := AHeight;
  end;
  if (FDevice = nil) or (FDevice.Handle = nil) or (FSurface = VK_NULL_HANDLE) then
    Exit;

  FillChar(Caps, SizeOf(Caps), 0);
  CheckVk(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(FDevice.PhysicalDevice, FSurface, @Caps),
    'vkGetPhysicalDeviceSurfaceCapabilitiesKHR(ControlSurface)');

  if ((Caps.currentExtent.width = 0) and (Caps.currentExtent.height = 0)) or
     (((AWidth = 0) or (AHeight = 0)) and (Caps.currentExtent.width = High(Cardinal))) then
  begin
    DestroySwapchainResources(True);
    FSwapchainExtent.width := 0;
    FSwapchainExtent.height := 0;
    FSwapchainMinimized := True;
    FSwapchainSuboptimal := False;
    Exit;
  end;

  OldSwapchain := FSwapchain;
  FSwapchain := VK_NULL_HANDLE;
  DestroySwapchainResources(False);
  FSwapchainMinimized := False;
  FSwapchainSuboptimal := False;
  FCurrentImageIndex := 0;

  if FDebugName <> '' then
    NamePrefix := FDebugName
  else
    NamePrefix := 'ControlSwapchain';

  try
    SurfaceFormatCount := 0;
    SurfaceFormats := nil;
    if Assigned(vkGetPhysicalDeviceSurfaceFormatsKHR) and
       (vkGetPhysicalDeviceSurfaceFormatsKHR(FDevice.PhysicalDevice, FSurface, @SurfaceFormatCount, nil) = VK_SUCCESS) and
       (SurfaceFormatCount > 0) then
    begin
      SetLength(SurfaceFormats, SurfaceFormatCount);
      vkGetPhysicalDeviceSurfaceFormatsKHR(FDevice.PhysicalDevice, FSurface, @SurfaceFormatCount, @SurfaceFormats[0]);
    end;
    SurfFmt := SelectVulkanSurfaceFormat(SurfaceFormats, FSwapchainFormat);
    FSwapchainColorSpace := SurfFmt.colorSpace;

    PresentModeCount := 0;
    PresentModes := nil;
    if Assigned(vkGetPhysicalDeviceSurfacePresentModesKHR) and
       (vkGetPhysicalDeviceSurfacePresentModesKHR(FDevice.PhysicalDevice, FSurface, @PresentModeCount, nil) = VK_SUCCESS) and
       (PresentModeCount > 0) then
    begin
      SetLength(PresentModes, PresentModeCount);
      vkGetPhysicalDeviceSurfacePresentModesKHR(FDevice.PhysicalDevice, FSurface, @PresentModeCount, @PresentModes[0]);
    end;
    FSwapchainPresentMode := SelectVulkanPresentMode(PresentModes, False);
    FSwapchainCompositeAlpha := SelectVulkanCompositeAlpha(Caps.supportedCompositeAlpha);
    FSwapchainPreTransform := SelectVulkanSurfaceTransform(Caps.supportedTransforms, Caps.currentTransform);

    FSwapchainExtent.width := Max(Cardinal(1), AWidth);
    FSwapchainExtent.height := Max(Cardinal(1), AHeight);
    if Caps.currentExtent.width <> High(Cardinal) then
      FSwapchainExtent := Caps.currentExtent
    else if (Caps.maxImageExtent.width > 0) and (Caps.maxImageExtent.height > 0) then
    begin
      FSwapchainExtent.width := EnsureRange(FSwapchainExtent.width,
        Max(Cardinal(1), Caps.minImageExtent.width), Caps.maxImageExtent.width);
      FSwapchainExtent.height := EnsureRange(FSwapchainExtent.height,
        Max(Cardinal(1), Caps.minImageExtent.height), Caps.maxImageExtent.height);
    end;

    ImageCount := Max(Cardinal(2), Caps.minImageCount);
    if (Caps.maxImageCount > 0) and (ImageCount > Caps.maxImageCount) then
      ImageCount := Caps.maxImageCount;

    ImageUsage := VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ColorUsage := [tuColorAttachment];
    if Caps.supportedUsageFlags = 0 then
    begin
      ImageUsage := ImageUsage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
      ColorUsage := ColorUsage + [tuTransferSrc, tuTransferDst];
    end else
    begin
      if (Caps.supportedUsageFlags and VK_IMAGE_USAGE_TRANSFER_SRC_BIT) <> 0 then
      begin
        ImageUsage := ImageUsage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
        Include(ColorUsage, tuTransferSrc);
      end;
      if (Caps.supportedUsageFlags and VK_IMAGE_USAGE_TRANSFER_DST_BIT) <> 0 then
      begin
        ImageUsage := ImageUsage or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        Include(ColorUsage, tuTransferDst);
      end;
    end;

    FillChar(CreateInfo, SizeOf(CreateInfo), 0);
    CreateInfo.sType := VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    CreateInfo.surface := FSurface;
    CreateInfo.minImageCount := ImageCount;
    CreateInfo.imageFormat := SurfFmt.format;
    CreateInfo.imageColorSpace := FSwapchainColorSpace;
    CreateInfo.imageExtent := FSwapchainExtent;
    CreateInfo.imageArrayLayers := 1;
    CreateInfo.imageUsage := ImageUsage;
    if FDevice.GraphicsQueueFamily <> FDevice.PresentQueueFamily then
    begin
      QueueFamilyIndices[0] := FDevice.GraphicsQueueFamily;
      QueueFamilyIndices[1] := FDevice.PresentQueueFamily;
      CreateInfo.imageSharingMode := VK_SHARING_MODE_CONCURRENT;
      CreateInfo.queueFamilyIndexCount := 2;
      CreateInfo.pQueueFamilyIndices := @QueueFamilyIndices[0];
    end else
      CreateInfo.imageSharingMode := VK_SHARING_MODE_EXCLUSIVE;
    CreateInfo.preTransform := FSwapchainPreTransform;
    CreateInfo.compositeAlpha := FSwapchainCompositeAlpha;
    CreateInfo.presentMode := FSwapchainPresentMode;
    CreateInfo.clipped := VK_TRUE;
    CreateInfo.oldSwapchain := OldSwapchain;

    CheckVk(vkCreateSwapchainKHR(FDevice.Handle, @CreateInfo, nil, @FSwapchain),
      'vkCreateSwapchainKHR(ControlSurface)');
    if FSwapchain <> VK_NULL_HANDLE then
      FDevice.SetDebugObjectName(VK_OBJECT_TYPE_SWAPCHAIN_KHR, FSwapchain, NamePrefix);
  finally
    if (OldSwapchain <> VK_NULL_HANDLE) and (FDevice.Handle <> nil) and Assigned(vkDestroySwapchainKHR) then
      vkDestroySwapchainKHR(FDevice.Handle, OldSwapchain, nil);
  end;

  CheckVk(vkGetSwapchainImagesKHR(FDevice.Handle, FSwapchain, @ImageCount, nil),
    'vkGetSwapchainImagesKHR(ControlSurface count)');
  SetLength(Images, ImageCount);
  CheckVk(vkGetSwapchainImagesKHR(FDevice.Handle, FSwapchain, @ImageCount, @Images[0]),
    'vkGetSwapchainImagesKHR(ControlSurface)');

  ColorDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    FSwapchainFormat, ColorUsage, 1);
  ColorDesc.DebugName := NamePrefix + '_Color';

  FillChar(SemInfo, SizeOf(SemInfo), 0);
  SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

  SetLength(FColorTextures, ImageCount);
  SetLength(FRenderFinishedSemaphores, ImageCount);
  SetLength(FImageInFlightFences, ImageCount);
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
    CheckVk(vkCreateImageView(FDevice.Handle, @ViewInfo, nil, @ImgView),
      'vkCreateImageView(ControlSwapchain)');
    FColorTextures[I] := TVulkanRHITexture.CreateSwapchainWrapper(FDevice, ColorDesc, Images[I], ImgView);
    FRenderFinishedSemaphores[I] := VK_NULL_HANDLE;
    FImageInFlightFences[I] := VK_NULL_HANDLE;
    if Assigned(vkCreateSemaphore) then
      CheckVk(vkCreateSemaphore(FDevice.Handle, @SemInfo, nil, @FRenderFinishedSemaphores[I]),
        'vkCreateSemaphore(ControlSwapchainRenderFinished)');
  end;

  FSwapchainDepthFormat := NegotiateOptimalPixelFormat(pfD24_UNorm_S8_UInt, [tuDepthStencil], FDevice.PhysicalDevice);
  DepthDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    FSwapchainDepthFormat, [tuDepthStencil], 1);
  DepthDesc.DebugName := NamePrefix + '_Depth';
  FDepthTexture := TVulkanRHITexture.Create(FDevice, DepthDesc);

  if FSampleCount > 1 then
    EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, FSwapchainDepthFormat);
end;

procedure TCastleVulkanSwapchainSurface.SimulateForTesting(
  const AWidth, AHeight: Cardinal;
  const AImageCount: Cardinal;
  const AColorFormat, ADepthFormat: TRHIPixelFormat);
var
  ImgCount, I: Cardinal;
  ColorDesc, DepthDesc: TRHITextureDesc;
  NamePrefix: String;
begin
  DestroySwapchainResources(True);
  FSwapchainFormat := AColorFormat;
  if (FDevice <> nil) and (FDevice.Handle <> nil) then
    FSwapchainDepthFormat := NegotiateOptimalPixelFormat(ADepthFormat, [tuDepthStencil], FDevice.PhysicalDevice)
  else
    FSwapchainDepthFormat := ADepthFormat;
  FSwapchainExtent.width := Max(Cardinal(1), AWidth);
  FSwapchainExtent.height := Max(Cardinal(1), AHeight);
  FRequestedWidth := FSwapchainExtent.width;
  FRequestedHeight := FSwapchainExtent.height;
  FSwapchainMinimized := False;
  FSwapchainSuboptimal := False;
  FCurrentImageIndex := 0;

  if FDebugName <> '' then
    NamePrefix := FDebugName + '_'
  else
    NamePrefix := 'SimControlSurface_';

  ImgCount := Max(Cardinal(1), AImageCount);
  ColorDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    FSwapchainFormat, [tuColorAttachment, tuTransferSrc, tuTransferDst], 1);
  ColorDesc.DebugName := NamePrefix + 'Color';
  SetLength(FColorTextures, ImgCount);
  SetLength(FImageInFlightFences, ImgCount);
  for I := 0 to ImgCount - 1 do
  begin
    FColorTextures[I] := TVulkanRHITexture.Create(FDevice, ColorDesc);
    FImageInFlightFences[I] := VK_NULL_HANDLE;
  end;

  if FSwapchainDepthFormat <> pfUndefined then
  begin
    DepthDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
      FSwapchainDepthFormat, [tuDepthStencil], 1);
    DepthDesc.DebugName := NamePrefix + 'Depth';
    FDepthTexture := TVulkanRHITexture.Create(FDevice, DepthDesc);
  end;

  if FSampleCount > 1 then
    EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, FSwapchainDepthFormat);
end;

procedure TCastleVulkanSwapchainSurface.DestroySwapchainResources(
  const ADestroySwapchainHandle: Boolean);
var
  I: Integer;
begin
  if FDevice <> nil then
    FDevice.ClearFallbackFramebuffers;
  FreeAndNil(FMSAAColorTexture);
  FreeAndNil(FMSAADepthTexture);
  FreeAndNil(FDepthTexture);
  for I := 0 to High(FColorTextures) do
    FreeAndNil(FColorTextures[I]);
  SetLength(FColorTextures, 0);
  SetLength(FImageInFlightFences, 0);

  for I := 0 to High(FRenderFinishedSemaphores) do
    if (FDevice <> nil) and (FDevice.Handle <> nil) and
       (FRenderFinishedSemaphores[I] <> VK_NULL_HANDLE) and Assigned(vkDestroySemaphore) then
      vkDestroySemaphore(FDevice.Handle, FRenderFinishedSemaphores[I], nil);
  SetLength(FRenderFinishedSemaphores, 0);

  if ADestroySwapchainHandle and (FSwapchain <> VK_NULL_HANDLE) then
  begin
    if (FDevice <> nil) and (FDevice.Handle <> nil) and Assigned(vkDestroySwapchainKHR) then
      vkDestroySwapchainKHR(FDevice.Handle, FSwapchain, nil);
    FSwapchain := VK_NULL_HANDLE;
  end;
end;

function TCastleVulkanSwapchainSurface.GetSwapchainImageCount: Cardinal;
begin
  Result := Cardinal(Length(FColorTextures));
end;

procedure TCastleVulkanSwapchainSurface.Resize(const NewWidth, NewHeight: Cardinal);
var
  SimCount: Cardinal;
begin
  if (NewWidth = 0) or (NewHeight = 0) then
  begin
    FSwapchainMinimized := True;
    Exit;
  end;
  FRequestedWidth := NewWidth;
  FRequestedHeight := NewHeight;
  FSwapchainMinimized := False;
  if FDevice <> nil then
    FDevice.WaitIdle;
  if (FSurface = VK_NULL_HANDLE) and (Length(FColorTextures) > 0) then
  begin
    SimCount := Cardinal(Length(FColorTextures));
    SimulateForTesting(NewWidth, NewHeight, SimCount, FSwapchainFormat, FSwapchainDepthFormat);
  end else
  if FSurface <> VK_NULL_HANDLE then
  begin
    Inc(FSwapchainRecreateCount);
    CreateSwapchain(NewWidth, NewHeight);
  end;
end;

function TCastleVulkanSwapchainSurface.GetCurrentColorTexture: TVulkanRHITexture;
begin
  if FCurrentImageIndex < Cardinal(Length(FColorTextures)) then
    Result := FColorTextures[FCurrentImageIndex]
  else
    Result := nil;
end;

function TCastleVulkanSwapchainSurface.GetDepthTexture: TVulkanRHITexture;
begin
  Result := FDepthTexture;
end;

function TCastleVulkanSwapchainSurface.BuildRenderingInfo(
  const ARenderArea: TRectangle;
  const AClearColor: TCastleColor;
  const AColorLoadOp, ADepthLoadOp: TRHIAttachmentLoadOp;
  const AClearDepth: Single): TRHIRenderingInfo;
var
  W, H: Cardinal;
  ResolveColorTex, ResolveDepthTex: TVulkanRHITexture;
  ColorFmt, DepthFmt: TRHIPixelFormat;
begin
  Result := Default(TRHIRenderingInfo);
  Result.RenderArea := ARenderArea;
  W := Max(1, ARenderArea.Width);
  H := Max(1, ARenderArea.Height);

  ResolveColorTex := GetCurrentColorTexture;
  ResolveDepthTex := GetDepthTexture;
  if ResolveColorTex <> nil then
    ColorFmt := ResolveColorTex.Desc.Format
  else
    ColorFmt := FSwapchainFormat;
  if ResolveDepthTex <> nil then
    DepthFmt := ResolveDepthTex.Desc.Format
  else if FSwapchainDepthFormat <> pfUndefined then
    DepthFmt := FSwapchainDepthFormat
  else
    DepthFmt := pfD24_UNorm_S8_UInt;

  if (FSampleCount > 1) and (ResolveColorTex <> nil) then
  begin
    EnsureMSAATargets(W, H, ColorFmt, DepthFmt);
    SetLength(Result.ColorAttachments, 1);
    Result.ColorAttachments[0].Texture := FMSAAColorTexture;
    Result.ColorAttachments[0].ResolveTexture := ResolveColorTex;
    Result.ColorAttachments[0].ResolveMode := rmAverage;
    Result.ColorAttachments[0].LoadOp := AColorLoadOp;
    Result.ColorAttachments[0].StoreOp := soDontCare;
    Result.ColorAttachments[0].ClearColor := AClearColor;

    Result.DepthAttachment.Texture := FMSAADepthTexture;
    Result.DepthAttachment.ResolveTexture := nil;
    Result.DepthAttachment.ResolveMode := rmNone;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    Result.DepthAttachment.StoreOp := soDontCare;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end else
  begin
    if ResolveColorTex <> nil then
    begin
      SetLength(Result.ColorAttachments, 1);
      Result.ColorAttachments[0].Texture := ResolveColorTex;
      Result.ColorAttachments[0].ResolveTexture := nil;
      Result.ColorAttachments[0].ResolveMode := rmNone;
      Result.ColorAttachments[0].LoadOp := AColorLoadOp;
      Result.ColorAttachments[0].StoreOp := soStore;
      Result.ColorAttachments[0].ClearColor := AClearColor;
    end;
    Result.DepthAttachment.Texture := ResolveDepthTex;
    Result.DepthAttachment.ResolveTexture := nil;
    Result.DepthAttachment.ResolveMode := rmNone;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    Result.DepthAttachment.StoreOp := soStore;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end;
  Result.HasDepthAttachment := Result.DepthAttachment.Texture <> nil;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHIDevice                                                             }
{ ---------------------------------------------------------------------------- }

function EnvFlagEnabled(const AEnvName: String): Boolean;
var
  Val: String;
begin
  Val := Trim(GetEnvironmentVariable(AEnvName));
  Result := (Val = '1') or SameText(Val, 'true') or SameText(Val, 'yes') or SameText(Val, 'on');
end;

function ShouldEnableVulkanValidationByEnv(const ARequested: Boolean): Boolean;
begin
  if SameText(Trim(GetEnvironmentVariable('CASTLE_VULKAN_VALIDATION')), '0') or
     SameText(Trim(GetEnvironmentVariable('CASTLE_VULKAN_VALIDATION')), 'false') then
    Exit(False);
  Result := ARequested or
    EnvFlagEnabled('CASTLE_VULKAN_VALIDATION') or
    EnvFlagEnabled('CASTLE_VULKAN_VALIDATION_STRICT');
end;

function IsVulkanStrictValidationGateEnv: Boolean;
begin
  Result := EnvFlagEnabled('CASTLE_VULKAN_VALIDATION_STRICT');
end;

function VulkanDebugUtilsMessengerCallback(
  messageSeverity: VkDebugUtilsMessageSeverityFlagsEXT;
  messageTypes: VkDebugUtilsMessageTypeFlagsEXT;
  const pCallbackData: PVkDebugUtilsMessengerCallbackDataEXT;
  pUserData: Pointer): VkBool32; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
var
  Dev: TVulkanRHIDevice;
  MsgIdName, MsgBody: String;
begin
  Result := VK_FALSE;
  if (pUserData = nil) or (pCallbackData = nil) then
    Exit;
  Dev := TVulkanRHIDevice(pUserData);
  if pCallbackData^.pMessageIdName <> nil then
    MsgIdName := String(AnsiString(pCallbackData^.pMessageIdName))
  else
    MsgIdName := '';
  if pCallbackData^.pMessage <> nil then
    MsgBody := String(AnsiString(pCallbackData^.pMessage))
  else
    MsgBody := '';
  Dev.RecordValidationCallbackMessage(messageSeverity, messageTypes, MsgIdName, MsgBody);
end;

constructor TVulkanRHIDevice.Create(const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
  const InitialWidth, InitialHeight: Cardinal; const EnableValidation: Boolean);
begin
  inherited Create;
  {$ifndef CASTLE_DISABLE_THREADS}
  FValidationLock := TCriticalSection.Create;
  {$endif}
  FStrictValidationGate := IsVulkanStrictValidationGateEnv;
  FBundledPipelineCacheFallbackUrl := DefaultBundledVulkanPipelineCacheUrl;
  FPipelineMap := TVulkanPipelineMap.Create([doOwnsValues]);
  FComputePipelineMap := TVulkanComputePipelineMap.Create([doOwnsValues]);
  FVertexInputLibMap := TVulkanPipelineLibraryMap.Create;
  FPreRasterLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentShaderLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentOutputLibMap := TVulkanPipelineLibraryMap.Create;
  FRenderPassMap := TVulkanRenderPassMap.Create;
  FFramebufferMap := TVulkanFramebufferMap.Create;
  FLiveDescriptorSets := TFPList.Create;
  FSupportsDynamicRendering := True;
  FAntiAliasing := aaNone;
  FSampleCount := 1;
  FSwapchainFormat := pfBGRA8_UNorm;
  FSwapchainDepthFormat := pfD24_UNorm_S8_UInt;
  FSwapchainColorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  FSwapchainPresentMode := VK_PRESENT_MODE_FIFO_KHR;
  FSwapchainCompositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  FSwapchainPreTransform := VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  FPortabilitySubsetCaps := TVulkanPortabilitySubsetCaps.DefaultFullVulkan;
  FRequestedSwapchainWidth := InitialWidth;
  FRequestedSwapchainHeight := InitialHeight;

  LoadVulkan;
  CreateInstance(EnableValidation);

  FSurface := ACreateSurfaceCallback(FInstance);
  if FSurface = VK_NULL_HANDLE then
    raise ERHIError.Create('Failed to create Vulkan window surface (VkSurfaceKHR)');

  PickPhysicalDevice;
  CreateLogicalDevice;
  FMemoryAllocator := TCastleVulkanMemoryAllocator.Create(FPhysicalDevice, FDevice, 0, FSupportsBufferDeviceAddress);
  FMemoryAllocator.SupportsMemoryBudgetExt := FSupportsMemoryBudgetExt;
  FMemoryAllocator.ForceExplicitHostFlush := FIsPortabilitySubsetDevice or (FVendorKind = vvApple);
  FStagingUploader := TCastleVulkanStagingUploader.Create(Self);
  CreateDescriptorPool;
  if FSupportsBindlessTextures and (FMaxBindlessTextures > 0) then
    FBindlessTextureManager := TCastleVulkanBindlessTextureManager.Create(
      Self, FMaxBindlessTextures, FSupportsBindlessUpdateAfterBind);
  FTimestampProfiler := TCastleVulkanTimestampProfiler.Create(Self);
  FSwapchainSurfaces := TVulkanSwapchainSurfaceList.Create(True);
  CreateFrameContexts;
  CreateSwapchain(InitialWidth, InitialHeight);
end;

constructor TVulkanRHIDevice.CreateSharedWithWSI(const EnableValidation: Boolean;
  const AProbeSurfaceCallback: TVulkanCreateSurfaceEvent);
var
  ProbeSurface: VkSurfaceKHR;
begin
  inherited Create;
  {$ifndef CASTLE_DISABLE_THREADS}
  FValidationLock := TCriticalSection.Create;
  {$endif}
  FStrictValidationGate := IsVulkanStrictValidationGateEnv;
  FBundledPipelineCacheFallbackUrl := DefaultBundledVulkanPipelineCacheUrl;
  FPipelineMap := TVulkanPipelineMap.Create([doOwnsValues]);
  FComputePipelineMap := TVulkanComputePipelineMap.Create([doOwnsValues]);
  FVertexInputLibMap := TVulkanPipelineLibraryMap.Create;
  FPreRasterLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentShaderLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentOutputLibMap := TVulkanPipelineLibraryMap.Create;
  FRenderPassMap := TVulkanRenderPassMap.Create;
  FFramebufferMap := TVulkanFramebufferMap.Create;
  FLiveDescriptorSets := TFPList.Create;
  FSwapchainSurfaces := TVulkanSwapchainSurfaceList.Create(True);
  FSupportsDynamicRendering := True;
  FRequireWSISwapchain := True;
  FAntiAliasing := aaNone;
  FSampleCount := 1;
  FSwapchainFormat := pfBGRA8_UNorm;
  FSwapchainDepthFormat := pfD24_UNorm_S8_UInt;
  FSwapchainColorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  FSwapchainPresentMode := VK_PRESENT_MODE_FIFO_KHR;
  FSwapchainCompositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  FSwapchainPreTransform := VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  FPortabilitySubsetCaps := TVulkanPortabilitySubsetCaps.DefaultFullVulkan;

  LoadVulkan;
  CreateInstance(EnableValidation, True);

  ProbeSurface := VK_NULL_HANDLE;
  if Assigned(AProbeSurfaceCallback) then
    ProbeSurface := AProbeSurfaceCallback(FInstance);
  FSurface := ProbeSurface;
  try
    PickPhysicalDevice;
    FSwapchainDepthFormat := NegotiateOptimalPixelFormat(pfD24_UNorm_S8_UInt, [tuDepthStencil], FPhysicalDevice);
    CreateLogicalDevice;
  finally
    FSurface := VK_NULL_HANDLE;
    if (ProbeSurface <> VK_NULL_HANDLE) and (FInstance <> nil) and Assigned(vkDestroySurfaceKHR) then
      vkDestroySurfaceKHR(FInstance, ProbeSurface, nil);
  end;

  FMemoryAllocator := TCastleVulkanMemoryAllocator.Create(FPhysicalDevice, FDevice, 0, FSupportsBufferDeviceAddress);
  FMemoryAllocator.SupportsMemoryBudgetExt := FSupportsMemoryBudgetExt;
  FMemoryAllocator.ForceExplicitHostFlush := FIsPortabilitySubsetDevice or (FVendorKind = vvApple);
  FStagingUploader := TCastleVulkanStagingUploader.Create(Self);
  CreateDescriptorPool;
  if FSupportsBindlessTextures and (FMaxBindlessTextures > 0) then
    FBindlessTextureManager := TCastleVulkanBindlessTextureManager.Create(
      Self, FMaxBindlessTextures, FSupportsBindlessUpdateAfterBind);
  FTimestampProfiler := TCastleVulkanTimestampProfiler.Create(Self);
  CreateFrameContexts;
end;

class function TVulkanRHIDevice.TryCreateSharedWithWSI(out ADevice: TVulkanRHIDevice;
  const EnableValidation: Boolean;
  const AProbeSurfaceCallback: TVulkanCreateSurfaceEvent): Boolean;
begin
  ADevice := nil;
  try
    ADevice := TVulkanRHIDevice.CreateSharedWithWSI(EnableValidation, AProbeSurfaceCallback);
    Result := (ADevice <> nil) and (ADevice.Handle <> nil);
    if not Result then
      FreeAndNil(ADevice);
  except
    on Exception do
    begin
      FreeAndNil(ADevice);
      Result := False;
    end;
  end;
end;

constructor TVulkanRHIDevice.CreateOffscreen(const EnableValidation: Boolean);
begin
  inherited Create;
  {$ifndef CASTLE_DISABLE_THREADS}
  FValidationLock := TCriticalSection.Create;
  {$endif}
  FStrictValidationGate := IsVulkanStrictValidationGateEnv;
  FBundledPipelineCacheFallbackUrl := DefaultBundledVulkanPipelineCacheUrl;
  FPipelineMap := TVulkanPipelineMap.Create([doOwnsValues]);
  FComputePipelineMap := TVulkanComputePipelineMap.Create([doOwnsValues]);
  FVertexInputLibMap := TVulkanPipelineLibraryMap.Create;
  FPreRasterLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentShaderLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentOutputLibMap := TVulkanPipelineLibraryMap.Create;
  FRenderPassMap := TVulkanRenderPassMap.Create;
  FFramebufferMap := TVulkanFramebufferMap.Create;
  FLiveDescriptorSets := TFPList.Create;
  FSupportsDynamicRendering := True;
  FAntiAliasing := aaNone;
  FSampleCount := 1;
  FSwapchainFormat := pfBGRA8_UNorm;
  FSwapchainDepthFormat := pfD24_UNorm_S8_UInt;
  FSwapchainColorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  FSwapchainPresentMode := VK_PRESENT_MODE_FIFO_KHR;
  FSwapchainCompositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  FSwapchainPreTransform := VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  FPortabilitySubsetCaps := TVulkanPortabilitySubsetCaps.DefaultFullVulkan;

  LoadVulkan;
  CreateInstance(EnableValidation, False);
  PickPhysicalDevice;
  FSwapchainDepthFormat := NegotiateOptimalPixelFormat(pfD24_UNorm_S8_UInt, [tuDepthStencil], FPhysicalDevice);
  CreateLogicalDevice;
  FMemoryAllocator := TCastleVulkanMemoryAllocator.Create(FPhysicalDevice, FDevice, 0, FSupportsBufferDeviceAddress);
  FMemoryAllocator.SupportsMemoryBudgetExt := FSupportsMemoryBudgetExt;
  FMemoryAllocator.ForceExplicitHostFlush := FIsPortabilitySubsetDevice or (FVendorKind = vvApple);
  FStagingUploader := TCastleVulkanStagingUploader.Create(Self);
  CreateDescriptorPool;
  if FSupportsBindlessTextures and (FMaxBindlessTextures > 0) then
    FBindlessTextureManager := TCastleVulkanBindlessTextureManager.Create(
      Self, FMaxBindlessTextures, FSupportsBindlessUpdateAfterBind);
  FTimestampProfiler := TCastleVulkanTimestampProfiler.Create(Self);
  FSwapchainSurfaces := TVulkanSwapchainSurfaceList.Create(True);
  CreateFrameContexts;
end;

class function TVulkanRHIDevice.TryCreateOffscreen(out ADevice: TVulkanRHIDevice;
  const EnableValidation: Boolean): Boolean;
begin
  ADevice := nil;
  try
    ADevice := TVulkanRHIDevice.CreateOffscreen(EnableValidation);
    Result := (ADevice <> nil) and (ADevice.Handle <> nil);
    if not Result then
      FreeAndNil(ADevice);
  except
    on Exception do
    begin
      FreeAndNil(ADevice);
      Result := False;
    end;
  end;
end;

constructor TVulkanRHIDevice.CreateHeadless(const APhysicalDevice: VkPhysicalDevice;
  const ASupportsMemoryBudgetExt: Boolean;
  const ASupportsDynamicRendering: Boolean;
  const ADeviceApiVersion: Cardinal;
  const ASupportsGraphicsPipelineLibrary: Boolean;
  const ASupportsBindlessTextures: Boolean;
  const AMaxBindlessTextures: Cardinal;
  const ASupportsExtendedDynamicState: Boolean);
var
  I: Integer;
begin
  inherited Create;
  {$ifndef CASTLE_DISABLE_THREADS}
  FValidationLock := TCriticalSection.Create;
  {$endif}
  FStrictValidationGate := IsVulkanStrictValidationGateEnv;
  FBundledPipelineCacheFallbackUrl := DefaultBundledVulkanPipelineCacheUrl;
  FPipelineMap := TVulkanPipelineMap.Create([doOwnsValues]);
  FComputePipelineMap := TVulkanComputePipelineMap.Create([doOwnsValues]);
  FVertexInputLibMap := TVulkanPipelineLibraryMap.Create;
  FPreRasterLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentShaderLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentOutputLibMap := TVulkanPipelineLibraryMap.Create;
  FRenderPassMap := TVulkanRenderPassMap.Create;
  FFramebufferMap := TVulkanFramebufferMap.Create;
  FLiveDescriptorSets := TFPList.Create;
  FAntiAliasing := aaNone;
  FSampleCount := 1;
  FSwapchainFormat := pfBGRA8_UNorm;
  FSwapchainDepthFormat := pfD24_UNorm_S8_UInt;
  FSwapchainColorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  FSwapchainPresentMode := VK_PRESENT_MODE_FIFO_KHR;
  FSwapchainCompositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  FSwapchainPreTransform := VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
  FPortabilitySubsetCaps := TVulkanPortabilitySubsetCaps.DefaultFullVulkan;
  FCapabilities.Backend := rbVulkan;
  FCapabilities.DeviceName := 'Headless Vulkan RHI Device';
  FCapabilities.MaxTextureSize := 16384;
  FCapabilities.MaxAnisotropy := 16.0;
  FCapabilities.MaxFramebufferSampleCount := 8;
  FCapabilities.SupportsComputeShaders := True;
  FCapabilities.SupportsMultiDrawIndirect := True;
  FSupportsDrawIndirectCountFeature := ADeviceApiVersion >= VK_API_VERSION_1_2;
  FSupportsShaderDrawParameters := ADeviceApiVersion >= VK_API_VERSION_1_1;
  FCapabilities.SupportsDrawIndirectCount := FSupportsDrawIndirectCountFeature;
  FCapabilities.SupportsBCCompression := True;
  FCapabilities.TimestampPeriodNanoseconds := 1.0;
  FPhysicalDevice := APhysicalDevice;
  FInstanceApiVersion := ADeviceApiVersion;
  FDeviceApiVersion := ADeviceApiVersion;
  FSupportsMemoryBudgetExt := ASupportsMemoryBudgetExt;
  FSupportsDynamicRendering := ASupportsDynamicRendering;
  FSupportsGraphicsPipelineLibrary := ASupportsGraphicsPipelineLibrary;
  FSupportsGPLFastLinking := ASupportsGraphicsPipelineLibrary;
  FSupportsBindlessTextures := ASupportsBindlessTextures;
  FSupportsBindlessUpdateAfterBind := ASupportsBindlessTextures;
  FSupportsExtendedDynamicState := ASupportsExtendedDynamicState;
  FSupportsSynchronization2 := ADeviceApiVersion >= VK_API_VERSION_1_3;
  FSupportsTimelineSemaphores := ADeviceApiVersion >= VK_API_VERSION_1_2;
  FSupportsHostQueryReset := ADeviceApiVersion >= VK_API_VERSION_1_2;
  FSupportsOcclusionQueryPrecise := True;
  FSupportsBufferDeviceAddress := ADeviceApiVersion >= VK_API_VERSION_1_2;
  FRTShaderGroupHandleSize := 32;
  FRTShaderGroupHandleAlignment := 32;
  FRTShaderGroupBaseAlignment := 64;
  FCapabilities.SupportsExtendedDynamicState := FSupportsExtendedDynamicState;
  FCapabilities.SupportsSynchronization2 := FSupportsSynchronization2;
  FCapabilities.SupportsTimelineSemaphores := FSupportsTimelineSemaphores;
  FCapabilities.SupportsBufferDeviceAddress := FSupportsBufferDeviceAddress;
  if ASupportsBindlessTextures then
    FMaxBindlessTextures := Max(Cardinal(1), AMaxBindlessTextures)
  else
    FMaxBindlessTextures := 0;
  FCapabilities.SupportsBindlessTextures := FSupportsBindlessTextures;
  FCapabilities.MaxBindlessTextures := FMaxBindlessTextures;
  FMemoryAllocator := TCastleVulkanMemoryAllocator.Create(FPhysicalDevice, FDevice, 0, FSupportsBufferDeviceAddress);
  FMemoryAllocator.SupportsMemoryBudgetExt := FSupportsMemoryBudgetExt;
  FMemoryAllocator.ForceExplicitHostFlush := FIsPortabilitySubsetDevice or (FVendorKind = vvApple);
  FStagingUploader := TCastleVulkanStagingUploader.Create(Self);
  FPersistentDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(
    FDevice, 2048, True, 8192, FSupportsBindlessUpdateAfterBind, FSupportsAccelerationStructure);
  if FSupportsBindlessTextures and (FMaxBindlessTextures > 0) then
    FBindlessTextureManager := TCastleVulkanBindlessTextureManager.Create(
      Self, FMaxBindlessTextures, FSupportsBindlessUpdateAfterBind);
  FTimestampProfiler := TCastleVulkanTimestampProfiler.Create(Self);
  FSwapchainSurfaces := TVulkanSwapchainSurfaceList.Create(True);
  for I := 0 to MaxFramesInFlight - 1 do
    FFrames[I].TransientDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(
      FDevice, 512, False, 4096, NeedsUpdateAfterBindSamplerLayouts, FSupportsAccelerationStructure);
end;

procedure TVulkanRHIDevice.ClearPipelineLibraries;

  procedure DestroyMapPipelines(const AMap: TVulkanPipelineLibraryMap);
  var
    LibHandle: VkPipeline;
  begin
    if AMap = nil then Exit;
    if (FDevice <> nil) and Assigned(vkDestroyPipeline) then
    begin
      for LibHandle in AMap.Values do
        if LibHandle <> VK_NULL_HANDLE then
          vkDestroyPipeline(FDevice, LibHandle, nil);
    end;
    AMap.Clear;
  end;

begin
  DestroyMapPipelines(FVertexInputLibMap);
  DestroyMapPipelines(FPreRasterLibMap);
  DestroyMapPipelines(FFragmentShaderLibMap);
  DestroyMapPipelines(FFragmentOutputLibMap);
end;

function TVulkanRHIDevice.GetVertexInputLibraryCount: Cardinal;
begin
  if FVertexInputLibMap <> nil then
    Result := Cardinal(FVertexInputLibMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetPreRasterizationLibraryCount: Cardinal;
begin
  if FPreRasterLibMap <> nil then
    Result := Cardinal(FPreRasterLibMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetFragmentShaderLibraryCount: Cardinal;
begin
  if FFragmentShaderLibMap <> nil then
    Result := Cardinal(FFragmentShaderLibMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetFragmentOutputLibraryCount: Cardinal;
begin
  if FFragmentOutputLibMap <> nil then
    Result := Cardinal(FFragmentOutputLibMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetTotalPipelineLibraryCount: Cardinal;
begin
  Result := GetVertexInputLibraryCount + GetPreRasterizationLibraryCount +
    GetFragmentShaderLibraryCount + GetFragmentOutputLibraryCount;
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

procedure TVulkanRHIDevice.DeferOrDestroyBuffer(const ABuffer: VkBuffer;
  var AAllocation: TVulkanMemoryAllocation; const ADeviceMemory: VkDeviceMemory;
  const AAllocatedSize: VkDeviceSize);
var
  Slot, Idx: Integer;
begin
  if FDeferResourceDestruction then
  begin
    Slot := FFrameIndex mod MaxFramesInFlight;
    Idx := Length(FDeferredDeletions[Slot]);
    SetLength(FDeferredDeletions[Slot], Idx + 1);
    FillChar(FDeferredDeletions[Slot][Idx], SizeOf(TVulkanDeferredDeletionItem), 0);
    FDeferredDeletions[Slot][Idx].IsTexture := False;
    FDeferredDeletions[Slot][Idx].Buffer := ABuffer;
    FDeferredDeletions[Slot][Idx].Allocation := AAllocation;
    FDeferredDeletions[Slot][Idx].DeviceMemory := ADeviceMemory;
    FDeferredDeletions[Slot][Idx].AllocatedSize := AAllocatedSize;
    Exit;
  end;

  if (ABuffer <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyBuffer) then
    vkDestroyBuffer(FDevice, ABuffer, nil);
  if AAllocation.IsValid and (FMemoryAllocator <> nil) then
  begin
    FMemoryAllocator.Free(AAllocation);
    Dec(FAllocatedMemoryBytes, AAllocatedSize);
  end else
  if (ADeviceMemory <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkFreeMemory) then
  begin
    vkFreeMemory(FDevice, ADeviceMemory, nil);
    Dec(FAllocatedMemoryBytes, AAllocatedSize);
  end;
end;

procedure TVulkanRHIDevice.DeferOrDestroyTexture(const AImage: VkImage;
  const AImageView: VkImageView; var AAllocation: TVulkanMemoryAllocation;
  const ADeviceMemory: VkDeviceMemory; const AAllocatedSize: VkDeviceSize);
var
  Slot, Idx: Integer;
begin
  if FDeferResourceDestruction then
  begin
    Slot := FFrameIndex mod MaxFramesInFlight;
    Idx := Length(FDeferredDeletions[Slot]);
    SetLength(FDeferredDeletions[Slot], Idx + 1);
    FillChar(FDeferredDeletions[Slot][Idx], SizeOf(TVulkanDeferredDeletionItem), 0);
    FDeferredDeletions[Slot][Idx].IsTexture := True;
    FDeferredDeletions[Slot][Idx].Image := AImage;
    FDeferredDeletions[Slot][Idx].ImageView := AImageView;
    FDeferredDeletions[Slot][Idx].Allocation := AAllocation;
    FDeferredDeletions[Slot][Idx].DeviceMemory := ADeviceMemory;
    FDeferredDeletions[Slot][Idx].AllocatedSize := AAllocatedSize;
    Exit;
  end;

  if (AImageView <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyImageView) then
    vkDestroyImageView(FDevice, AImageView, nil);
  if (AImage <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyImage) then
    vkDestroyImage(FDevice, AImage, nil);
  if AAllocation.IsValid and (FMemoryAllocator <> nil) then
  begin
    FMemoryAllocator.Free(AAllocation);
    Dec(FAllocatedMemoryBytes, AAllocatedSize);
  end else
  if (ADeviceMemory <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkFreeMemory) then
  begin
    vkFreeMemory(FDevice, ADeviceMemory, nil);
    Dec(FAllocatedMemoryBytes, AAllocatedSize);
  end;
end;

procedure TVulkanRHIDevice.DeferOrDestroyDescriptorSet(
  const AOwnerPool: VkDescriptorPool; const ASet: VkDescriptorSet);
var
  Slot, Idx: Integer;
begin
  if (AOwnerPool = VK_NULL_HANDLE) or (ASet = VK_NULL_HANDLE) then
    Exit;

  if FDeferResourceDestruction then
  begin
    Slot := FFrameIndex mod MaxFramesInFlight;
    Idx := Length(FDeferredDeletions[Slot]);
    SetLength(FDeferredDeletions[Slot], Idx + 1);
    FillChar(FDeferredDeletions[Slot][Idx], SizeOf(TVulkanDeferredDeletionItem), 0);
    FDeferredDeletions[Slot][Idx].IsDescriptorSet := True;
    FDeferredDeletions[Slot][Idx].DescriptorPool := AOwnerPool;
    FDeferredDeletions[Slot][Idx].DescriptorSet := ASet;
    Exit;
  end;

  if FPersistentDescriptorAllocator <> nil then
    FPersistentDescriptorAllocator.FreeDescriptorSet(AOwnerPool, ASet);
end;

procedure TVulkanRHIDevice.FlushDeferredDeletions(const AFrameSlot: Integer);
var
  I: Integer;
  Item: TVulkanDeferredDeletionItem;
begin
  if (AFrameSlot < 0) or (AFrameSlot >= MaxFramesInFlight) then
    Exit;
  for I := 0 to High(FDeferredDeletions[AFrameSlot]) do
  begin
    Item := FDeferredDeletions[AFrameSlot][I];
    if Item.IsDescriptorSet then
    begin
      if FPersistentDescriptorAllocator <> nil then
        FPersistentDescriptorAllocator.FreeDescriptorSet(Item.DescriptorPool, Item.DescriptorSet);
      Continue;
    end;

    if Item.IsTexture then
    begin
      if (Item.ImageView <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyImageView) then
        vkDestroyImageView(FDevice, Item.ImageView, nil);
      if (Item.Image <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyImage) then
        vkDestroyImage(FDevice, Item.Image, nil);
    end else
    begin
      if (Item.Buffer <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyBuffer) then
        vkDestroyBuffer(FDevice, Item.Buffer, nil);
    end;
    if Item.Allocation.IsValid and (FMemoryAllocator <> nil) then
    begin
      FMemoryAllocator.Free(Item.Allocation);
      Dec(FAllocatedMemoryBytes, Item.AllocatedSize);
    end else
    if (Item.DeviceMemory <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkFreeMemory) then
    begin
      vkFreeMemory(FDevice, Item.DeviceMemory, nil);
      Dec(FAllocatedMemoryBytes, Item.AllocatedSize);
    end;
  end;
  SetLength(FDeferredDeletions[AFrameSlot], 0);
end;

procedure TVulkanRHIDevice.FlushAllDeferredDeletions;
var
  Slot: Integer;
begin
  for Slot := 0 to MaxFramesInFlight - 1 do
    FlushDeferredDeletions(Slot);
end;

function TVulkanRHIDevice.FlushStagingUploads(
  const ACommandList: TVulkanRHICommandList): Cardinal;
begin
  if FStagingUploader <> nil then
    Result := FStagingUploader.FlushPendingUploads(ACommandList)
  else
    Result := 0;
end;

procedure TVulkanRHIDevice.RegisterLiveDescriptorSet(const ASet: TVulkanRHIDescriptorSet);
begin
  if (FLiveDescriptorSets <> nil) and (ASet <> nil) and
     (FLiveDescriptorSets.IndexOf(ASet) < 0) then
    FLiveDescriptorSets.Add(ASet);
end;

procedure TVulkanRHIDevice.UnregisterLiveDescriptorSet(const ASet: TVulkanRHIDescriptorSet);
begin
  if (FLiveDescriptorSets <> nil) and (ASet <> nil) then
    FLiveDescriptorSets.Remove(ASet);
end;

procedure TVulkanRHIDevice.UnbindDestroyedBufferFromDescriptorSets(const ABuffer: TVulkanRHIBuffer);
var
  I: Integer;
begin
  if (FLiveDescriptorSets = nil) or (ABuffer = nil) then
    Exit;
  for I := 0 to FLiveDescriptorSets.Count - 1 do
    TVulkanRHIDescriptorSet(FLiveDescriptorSets[I]).ClearBoundBuffer(ABuffer);
end;

procedure TVulkanRHIDevice.UnbindDestroyedTextureFromDescriptorSets(const ATexture: TVulkanRHITexture);
var
  I: Integer;
begin
  if (FLiveDescriptorSets = nil) or (ATexture = nil) then
    Exit;
  for I := 0 to FLiveDescriptorSets.Count - 1 do
    TVulkanRHIDescriptorSet(FLiveDescriptorSets[I]).ClearBoundTexture(ATexture);
end;

procedure TVulkanRHIDevice.EnqueueInFlightDescriptorSetDeletion(
  const AOwnerPool: VkDescriptorPool; const ASet: VkDescriptorSet);
var
  Slot, Idx: Integer;
begin
  if (AOwnerPool = VK_NULL_HANDLE) or (ASet = VK_NULL_HANDLE) then
    Exit;
  Slot := FFrameIndex mod MaxFramesInFlight;
  Idx := Length(FDeferredDeletions[Slot]);
  SetLength(FDeferredDeletions[Slot], Idx + 1);
  FillChar(FDeferredDeletions[Slot][Idx], SizeOf(TVulkanDeferredDeletionItem), 0);
  FDeferredDeletions[Slot][Idx].IsDescriptorSet := True;
  FDeferredDeletions[Slot][Idx].DescriptorPool := AOwnerPool;
  FDeferredDeletions[Slot][Idx].DescriptorSet := ASet;
end;

function TVulkanRHIDevice.HandleDefragmentRelocate(const AUserData: Pointer;
  const AOldAlloc, ANewAlloc: TVulkanMemoryAllocation): Boolean;
var
  Buf: TVulkanRHIBuffer;
  BufInfo: VkBufferCreateInfo;
  NewVkBuffer, OldVkBuffer: VkBuffer;
  Idx, BIdx: Integer;
  AlreadyListed: Boolean;
begin
  Result := False;
  if (AUserData = nil) or not (TObject(AUserData) is TVulkanRHIBuffer) then
    Exit;
  Buf := TVulkanRHIBuffer(AUserData);
  OldVkBuffer := Buf.Handle;
  NewVkBuffer := VK_NULL_HANDLE;

  if (FDevice <> nil) and Assigned(vkCreateBuffer) and Assigned(vkBindBufferMemory) then
  begin
    FillChar(BufInfo, SizeOf(BufInfo), 0);
    BufInfo.sType := VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    BufInfo.size := Buf.Desc.Size;
    BufInfo.sharingMode := VK_SHARING_MODE_EXCLUSIVE;
    BufInfo.usage := Buf.BuildVkUsageFlags;
    if vkCreateBuffer(FDevice, @BufInfo, nil, @NewVkBuffer) <> VK_SUCCESS then
      Exit(False);
    if vkBindBufferMemory(FDevice, NewVkBuffer, ANewAlloc.DeviceMemory, ANewAlloc.Offset) <> VK_SUCCESS then
    begin
      if Assigned(vkDestroyBuffer) then
        vkDestroyBuffer(FDevice, NewVkBuffer, nil);
      Exit(False);
    end;
  end else
    NewVkBuffer := VkBuffer(PtrUInt(Buf) xor PtrUInt(ANewAlloc.ChunkId shl 4));

  Idx := Length(FPendingRelocations);
  SetLength(FPendingRelocations, Idx + 1);
  FPendingRelocations[Idx].Buffer := Buf;
  FPendingRelocations[Idx].OldVkBuffer := OldVkBuffer;
  FPendingRelocations[Idx].NewVkBuffer := NewVkBuffer;
  FPendingRelocations[Idx].CopySize := Buf.Desc.Size;

  AlreadyListed := False;
  for BIdx := 0 to High(FRelocatedBuffers) do
    if FRelocatedBuffers[BIdx] = Buf then
    begin
      AlreadyListed := True;
      Break;
    end;
  if not AlreadyListed then
  begin
    BIdx := Length(FRelocatedBuffers);
    SetLength(FRelocatedBuffers, BIdx + 1);
    FRelocatedBuffers[BIdx] := Buf;
  end;

  Buf.RelocateToAllocation(NewVkBuffer, ANewAlloc);
  Result := True;
end;

procedure TVulkanRHIDevice.HandleDefragmentFinalizeMoves;
var
  Cmd: VkCommandBuffer;
  CopyRegion: VkBufferCopy;
  I: Integer;
begin
  if Length(FPendingRelocations) = 0 then
    Exit;

  if (FDevice <> nil) and Assigned(vkCmdCopyBuffer) then
  begin
    Cmd := BeginSingleTimeCommands;
    for I := 0 to High(FPendingRelocations) do
      if (FPendingRelocations[I].OldVkBuffer <> VK_NULL_HANDLE) and
         (FPendingRelocations[I].NewVkBuffer <> VK_NULL_HANDLE) and
         (FPendingRelocations[I].CopySize > 0) then
      begin
        FillChar(CopyRegion, SizeOf(CopyRegion), 0);
        CopyRegion.srcOffset := 0;
        CopyRegion.dstOffset := 0;
        CopyRegion.size := FPendingRelocations[I].CopySize;
        vkCmdCopyBuffer(Cmd, FPendingRelocations[I].OldVkBuffer,
          FPendingRelocations[I].NewVkBuffer, 1, @CopyRegion);
      end;
    EndSingleTimeCommands(Cmd);

    { Destroy retired VkBuffer handles BEFORE Phase C frees source sub-allocations/blocks (VUID-vkFreeMemory-memory-00677) }
    if Assigned(vkDestroyBuffer) then
      for I := 0 to High(FPendingRelocations) do
        if FPendingRelocations[I].OldVkBuffer <> VK_NULL_HANDLE then
          vkDestroyBuffer(FDevice, FPendingRelocations[I].OldVkBuffer, nil);
  end;

  SetLength(FPendingRelocations, 0);
end;

function TVulkanRHIDevice.DefragmentMemoryPools(
  const AMaxBytesToMove: UInt64;
  const AMaxAllocationsToMove: Cardinal): TVulkanDefragmentStats;
var
  I, J: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  if FMemoryAllocator = nil then
    Exit;

  if (FStagingUploader <> nil) and
     not ((ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
    FlushStagingUploads(nil);
  WaitIdle;
  FlushAllDeferredDeletions;

  SetLength(FPendingRelocations, 0);
  SetLength(FRelocatedBuffers, 0);
  try
    Result := FMemoryAllocator.DefragmentPools(
      AMaxBytesToMove,
      AMaxAllocationsToMove,
      {$ifdef FPC}@{$endif}HandleDefragmentRelocate,
      {$ifdef FPC}@{$endif}HandleDefragmentFinalizeMoves);

    if (FLiveDescriptorSets <> nil) and (Length(FRelocatedBuffers) > 0) then
      for I := 0 to High(FRelocatedBuffers) do
        for J := 0 to FLiveDescriptorSets.Count - 1 do
          TVulkanRHIDescriptorSet(FLiveDescriptorSets[J]).RefreshRelocatedBuffer(FRelocatedBuffers[I]);
  finally
    SetLength(FPendingRelocations, 0);
    SetLength(FRelocatedBuffers, 0);
  end;
end;

function TVulkanRHIDevice.GetPendingDeferredDeletionCount: Cardinal;
var
  Slot: Integer;
begin
  Result := 0;
  for Slot := 0 to MaxFramesInFlight - 1 do
    Inc(Result, Cardinal(Length(FDeferredDeletions[Slot])));
end;

function TVulkanRHIDevice.GetTransientDescriptorAllocator(
  const AFrameIndex: Cardinal): TVulkanDescriptorPoolAllocator;
begin
  Result := FFrames[AFrameIndex mod MaxFramesInFlight].TransientDescriptorAllocator;
end;

function TVulkanRHIDevice.CreateTransientDescriptorSet(
  const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet;
begin
  Inc(FDescriptorSetAllocations);
  Result := TVulkanRHIDescriptorSet.Create(Self, Layout as TVulkanRHIDescriptorSetLayout, True);
end;

function TVulkanRHIDevice.GetDescriptorPoolHandle: VkDescriptorPool;
begin
  if (FPersistentDescriptorAllocator <> nil) and
     (FPersistentDescriptorAllocator.CurrentPool <> VK_NULL_HANDLE) then
    Result := FPersistentDescriptorAllocator.CurrentPool
  else
    Result := FDescriptorPool;
end;

function TVulkanRHIDevice.GetDefaultSampler: TVulkanRHISampler;
var
  SampDesc: TRHISamplerDesc;
begin
  if FDefaultSampler = nil then
  begin
    FillChar(SampDesc, SizeOf(SampDesc), 0);
    SampDesc.MinFilter := sfLinear;
    SampDesc.MagFilter := sfLinear;
    SampDesc.MipFilter := sfLinear;
    SampDesc.AddressModeU := amRepeat;
    SampDesc.AddressModeV := amRepeat;
    SampDesc.AddressModeW := amRepeat;
    SampDesc.MaxAnisotropy := 1.0;
    SampDesc.MaxLod := 1000.0;
    FDefaultSampler := CreateSampler(SampDesc) as TVulkanRHISampler;
  end;
  Result := FDefaultSampler;
end;

function TVulkanRHIDevice.GetDefaultShadowSampler: TVulkanRHISampler;
var
  SampDesc: TRHISamplerDesc;
begin
  if FDefaultShadowSampler = nil then
  begin
    FillChar(SampDesc, SizeOf(SampDesc), 0);
    SampDesc.MinFilter := sfLinear;
    SampDesc.MagFilter := sfLinear;
    SampDesc.MipFilter := sfNearest;
    SampDesc.AddressModeU := amClampToEdge;
    SampDesc.AddressModeV := amClampToEdge;
    SampDesc.AddressModeW := amClampToEdge;
    SampDesc.MaxAnisotropy := 1.0;
    SampDesc.MaxLod := 0.0;
    SampDesc.CompareEnable := True;
    SampDesc.CompareOp := coLessOrEqual;
    FDefaultShadowSampler := CreateSampler(SampDesc) as TVulkanRHISampler;
  end;
  Result := FDefaultShadowSampler;
end;

function TVulkanRHIDevice.GetDefaultWhiteTexture: TVulkanRHITexture;
var
  TexDesc: TRHITextureDesc;
  Img: TRGBAlphaImage;
begin
  if FDefaultWhiteTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(1, 1, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 1);
    TexDesc.DebugName := 'CastleDefaultWhiteTex';
    FDefaultWhiteTexture := CreateTexture(TexDesc) as TVulkanRHITexture;
    Img := TRGBAlphaImage.Create(1, 1);
    try
      Img.PixelPtr(0, 0)^ := Vector4Byte(255, 255, 255, 255);
      FDefaultWhiteTexture.UploadImage(Img, 0, 0);
    finally
      FreeAndNil(Img);
    end;
    if (FDevice <> nil) and (FStagingUploader <> nil) and
       not ((ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
      FlushStagingUploads(nil);
  end;
  Result := FDefaultWhiteTexture;
end;

function TVulkanRHIDevice.GetDefaultBlackTexture: TVulkanRHITexture;
var
  TexDesc: TRHITextureDesc;
  Img: TRGBAlphaImage;
begin
  if FDefaultBlackTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(1, 1, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 1);
    TexDesc.DebugName := 'CastleDefaultBlackTex';
    FDefaultBlackTexture := CreateTexture(TexDesc) as TVulkanRHITexture;
    Img := TRGBAlphaImage.Create(1, 1);
    try
      Img.PixelPtr(0, 0)^ := Vector4Byte(0, 0, 0, 255);
      FDefaultBlackTexture.UploadImage(Img, 0, 0);
    finally
      FreeAndNil(Img);
    end;
    if (FDevice <> nil) and (FStagingUploader <> nil) and
       not ((ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
      FlushStagingUploads(nil);
  end;
  Result := FDefaultBlackTexture;
end;

function TVulkanRHIDevice.GetDefaultFlatNormalTexture: TVulkanRHITexture;
var
  TexDesc: TRHITextureDesc;
  Img: TRGBAlphaImage;
begin
  if FDefaultFlatNormalTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(1, 1, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 1);
    TexDesc.DebugName := 'CastleDefaultFlatNormalTex';
    FDefaultFlatNormalTexture := CreateTexture(TexDesc) as TVulkanRHITexture;
    Img := TRGBAlphaImage.Create(1, 1);
    try
      Img.PixelPtr(0, 0)^ := Vector4Byte(128, 128, 255, 255);
      FDefaultFlatNormalTexture.UploadImage(Img, 0, 0);
    finally
      FreeAndNil(Img);
    end;
    if (FDevice <> nil) and (FStagingUploader <> nil) and
       not ((ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
      FlushStagingUploads(nil);
  end;
  Result := FDefaultFlatNormalTexture;
end;

function TVulkanRHIDevice.GetDefaultShadowDepthTexture: TVulkanRHITexture;
var
  TexDesc: TRHITextureDesc;
  FloatImg: TRGBAlphaFloatImage;
begin
  if FDefaultShadowDepthTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(1, 1, pfD32_Float, [tuSampled, tuTransferDst], 1);
    TexDesc.DebugName := 'CastleDefaultShadowDepthTex';
    FDefaultShadowDepthTexture := CreateTexture(TexDesc) as TVulkanRHITexture;
    FloatImg := TRGBAlphaFloatImage.Create(1, 1);
    try
      FloatImg.PixelPtr(0, 0)^ := Vector4(1.0, 1.0, 1.0, 1.0);
      FDefaultShadowDepthTexture.UploadImage(FloatImg, 0, 0);
    finally
      FreeAndNil(FloatImg);
    end;
    if (FDevice <> nil) and (FStagingUploader <> nil) and
       not ((ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
      FlushStagingUploads(nil);
  end;
  Result := FDefaultShadowDepthTexture;
end;

function TVulkanRHIDevice.GetDefaultBrdfLutSampler: TVulkanRHISampler;
var
  SampDesc: TRHISamplerDesc;
begin
  if FDefaultBrdfLutSampler = nil then
  begin
    FillChar(SampDesc, SizeOf(SampDesc), 0);
    SampDesc.MinFilter := sfLinear;
    SampDesc.MagFilter := sfLinear;
    SampDesc.MipFilter := sfLinear;
    SampDesc.AddressModeU := amClampToEdge;
    SampDesc.AddressModeV := amClampToEdge;
    SampDesc.AddressModeW := amClampToEdge;
    SampDesc.MaxAnisotropy := 1.0;
    SampDesc.MaxLod := 1000.0;
    FDefaultBrdfLutSampler := CreateSampler(SampDesc) as TVulkanRHISampler;
  end;
  Result := FDefaultBrdfLutSampler;
end;

function TVulkanRHIDevice.GetDefaultBrdfLutTexture: TVulkanRHITexture;
const
  DefaultLutSize = 32;
var
  TexDesc: TRHITextureDesc;
  Img: TRGBAlphaImage;
  X, Y: Integer;
  NdotV, Roughness: Single;
  LutVal: TVector2;
begin
  if FDefaultBrdfLutTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      DefaultLutSize, DefaultLutSize, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 1);
    TexDesc.DebugName := 'CastleDefaultBrdfLutTex';
    FDefaultBrdfLutTexture := CreateTexture(TexDesc) as TVulkanRHITexture;
    Img := TRGBAlphaImage.Create(DefaultLutSize, DefaultLutSize);
    try
      for Y := 0 to DefaultLutSize - 1 do
      begin
        Roughness := Max((Single(Y) + 0.5) / Single(DefaultLutSize), 0.04);
        for X := 0 to DefaultLutSize - 1 do
        begin
          NdotV := (Single(X) + 0.5) / Single(DefaultLutSize);
          LutVal := TCastleVulkanIBLGenerator.IntegrateBRDFPoint(NdotV, Roughness, 32);
          Img.PixelPtr(X, Y)^ := Vector4Byte(
            Byte(Round(EnsureRange(LutVal.X, 0.0, 1.0) * 255.0)),
            Byte(Round(EnsureRange(LutVal.Y, 0.0, 1.0) * 255.0)),
            0, 255);
        end;
      end;
      FDefaultBrdfLutTexture.UploadImage(Img, 0, 0);
    finally
      FreeAndNil(Img);
    end;
    if (FDevice <> nil) and (FStagingUploader <> nil) and
       not ((ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
      FlushStagingUploads(nil);
  end;
  Result := FDefaultBrdfLutTexture;
end;

function TVulkanRHIDevice.GetDefaultWhiteCubeTexture: TVulkanRHITexture;
var
  TexDesc: TRHITextureDesc;
  Img: TRGBAlphaImage;
  FaceIdx: Cardinal;
begin
  if FDefaultWhiteCubeTexture = nil then
  begin
    TexDesc := TRHITextureDesc.CreateCube(1, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 1);
    TexDesc.DebugName := 'CastleDefaultWhiteCubeTex';
    FDefaultWhiteCubeTexture := CreateTexture(TexDesc) as TVulkanRHITexture;
    Img := TRGBAlphaImage.Create(1, 1);
    try
      Img.PixelPtr(0, 0)^ := Vector4Byte(255, 255, 255, 255);
      for FaceIdx := 0 to 5 do
        FDefaultWhiteCubeTexture.UploadImage(Img, 0, FaceIdx);
    finally
      FreeAndNil(Img);
    end;
    if (FDevice <> nil) and (FStagingUploader <> nil) and
       not ((ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
      FlushStagingUploads(nil);
  end;
  Result := FDefaultWhiteCubeTexture;
end;

function TVulkanRHIDevice.GetComputeCuller: TCastleVulkanComputeCuller;
begin
  if FComputeCuller = nil then
    FComputeCuller := TCastleVulkanComputeCuller.Create(Self);
  Result := FComputeCuller;
end;

function TVulkanRHIDevice.GetIBLGenerator: TCastleVulkanIBLGenerator;
begin
  if FIBLGenerator = nil then
    FIBLGenerator := TCastleVulkanIBLGenerator.Create(Self);
  Result := FIBLGenerator;
end;

function TVulkanRHIDevice.GetClusteredLightCuller: TCastleVulkanClusteredLightCuller;
begin
  if FClusteredLightCuller = nil then
    FClusteredLightCuller := TCastleVulkanClusteredLightCuller.Create(Self);
  Result := FClusteredLightCuller;
end;

function TVulkanRHIDevice.GetShadowAtlas: TCastleVulkanShadowAtlas;
begin
  if FShadowAtlas = nil then
    FShadowAtlas := TCastleVulkanShadowAtlas.Create(Self);
  Result := FShadowAtlas;
end;

function TVulkanRHIDevice.GetHDRPostProcessor: TCastleVulkanHDRPostProcessor;
begin
  if FHDRPostProcessor = nil then
    FHDRPostProcessor := TCastleVulkanHDRPostProcessor.Create(Self);
  Result := FHDRPostProcessor;
end;

function TVulkanRHIDevice.GetGTAO: TCastleVulkanGTAO;
begin
  if FGTAO = nil then
    FGTAO := TCastleVulkanGTAO.Create(Self);
  Result := FGTAO;
end;

function TVulkanRHIDevice.GetSSR: TCastleVulkanSSR;
begin
  if FSSR = nil then
    FSSR := TCastleVulkanSSR.Create(Self);
  Result := FSSR;
end;

function TVulkanRHIDevice.GetVolumetricFog: TCastleVulkanVolumetricFog;
begin
  if FVolumetricFog = nil then
    FVolumetricFog := TCastleVulkanVolumetricFog.Create(Self);
  Result := FVolumetricFog;
end;

function TVulkanRHIDevice.GetTAA: TCastleVulkanTAA;
begin
  if FTAA = nil then
    FTAA := TCastleVulkanTAA.Create(Self);
  Result := FTAA;
end;

function TVulkanRHIDevice.GetReflectionProbeManager: TCastleVulkanReflectionProbeManager;
begin
  if FReflectionProbeManager = nil then
    FReflectionProbeManager := TCastleVulkanReflectionProbeManager.Create(Self);
  Result := FReflectionProbeManager;
end;

function TVulkanRHIDevice.GetDecalManager: TCastleVulkanDecalManager;
begin
  if FDecalManager = nil then
    FDecalManager := TCastleVulkanDecalManager.Create(Self);
  Result := FDecalManager;
end;

function TVulkanRHIDevice.GetComputeParticles: TCastleVulkanComputeParticles;
begin
  if FComputeParticles = nil then
    FComputeParticles := TCastleVulkanComputeParticles.Create(Self);
  Result := FComputeParticles;
end;

function TVulkanRHIDevice.GetWeightedBlendedOIT: TCastleVulkanWeightedBlendedOIT;
begin
  if FWeightedBlendedOIT = nil then
    FWeightedBlendedOIT := TCastleVulkanWeightedBlendedOIT.Create(Self);
  Result := FWeightedBlendedOIT;
end;

function TVulkanRHIDevice.GetContactShadows: TCastleVulkanContactShadows;
begin
  if FContactShadows = nil then
    FContactShadows := TCastleVulkanContactShadows.Create(Self);
  Result := FContactShadows;
end;

function TVulkanRHIDevice.GetComputeSkinner: TCastleVulkanComputeSkinner;
begin
  if FComputeSkinner = nil then
    FComputeSkinner := TCastleVulkanComputeSkinner.Create(Self);
  Result := FComputeSkinner;
end;

function TVulkanRHIDevice.GetTerrainCDLOD: TCastleVulkanTerrainCDLOD;
begin
  if FTerrainCDLOD = nil then
    FTerrainCDLOD := TCastleVulkanTerrainCDLOD.Create(Self);
  Result := FTerrainCDLOD;
end;

function TVulkanRHIDevice.GetAtmosphereRenderer: TCastleVulkanAtmosphereRenderer;
begin
  if FAtmosphereRenderer = nil then
    FAtmosphereRenderer := TCastleVulkanAtmosphereRenderer.Create(Self);
  Result := FAtmosphereRenderer;
end;

function TVulkanRHIDevice.GetOceanSimulator: TCastleVulkanOceanSimulator;
begin
  if FOceanSimulator = nil then
    FOceanSimulator := TCastleVulkanOceanSimulator.Create(Self);
  Result := FOceanSimulator;
end;

function TVulkanRHIDevice.GetDDGIGrid: TCastleVulkanDDGIGrid;
begin
  if FDDGIGrid = nil then
    FDDGIGrid := TCastleVulkanDDGIGrid.Create(Self);
  Result := FDDGIGrid;
end;

function TVulkanRHIDevice.GetMeshletCuller: TCastleVulkanMeshletCuller;
begin
  if FMeshletCuller = nil then
    FMeshletCuller := TCastleVulkanMeshletCuller.Create(Self);
  Result := FMeshletCuller;
end;

function TVulkanRHIDevice.GetVirtualShadowMap: TCastleVulkanVirtualShadowMap;
begin
  if FVirtualShadowMap = nil then
    FVirtualShadowMap := TCastleVulkanVirtualShadowMap.Create(Self);
  Result := FVirtualShadowMap;
end;

function TVulkanRHIDevice.GetLODSelector: TCastleVulkanLODSelector;
begin
  if FLODSelector = nil then
    FLODSelector := TCastleVulkanLODSelector.Create(Self);
  Result := FLODSelector;
end;

function TVulkanRHIDevice.GetTextureStreamer: TCastleVulkanTextureStreamer;
begin
  if FTextureStreamer = nil then
    FTextureStreamer := TCastleVulkanTextureStreamer.Create(Self);
  Result := FTextureStreamer;
end;

function TVulkanRHIDevice.GetShadowCasterCuller: TCastleVulkanShadowCasterCuller;
begin
  if FShadowCasterCuller = nil then
    FShadowCasterCuller := TCastleVulkanShadowCasterCuller.Create(Self);
  Result := FShadowCasterCuller;
end;

function TVulkanRHIDevice.GetClusterDAG: TCastleVulkanClusterDAG;
begin
  if FClusterDAG = nil then
    FClusterDAG := TCastleVulkanClusterDAG.Create(Self);
  Result := FClusterDAG;
end;

function TVulkanRHIDevice.GetGlobalSDF: TCastleVulkanGlobalSDF;
begin
  if FGlobalSDF = nil then
    FGlobalSDF := TCastleVulkanGlobalSDF.Create(Self);
  Result := FGlobalSDF;
end;

function TVulkanRHIDevice.GetSurfaceCache: TCastleVulkanSurfaceCache;
begin
  if FSurfaceCache = nil then
    FSurfaceCache := TCastleVulkanSurfaceCache.Create(Self);
  Result := FSurfaceCache;
end;

function TVulkanRHIDevice.GetReSTIR: TCastleVulkanReSTIR;
begin
  if FReSTIR = nil then
    FReSTIR := TCastleVulkanReSTIR.Create(Self);
  Result := FReSTIR;
end;

function TVulkanRHIDevice.GetTSRUpscaler: TCastleVulkanTSRUpscaler;
begin
  if FTSRUpscaler = nil then
    FTSRUpscaler := TCastleVulkanTSRUpscaler.Create(Self);
  Result := FTSRUpscaler;
end;

function TVulkanRHIDevice.GetVRSManager: TCastleVulkanVRSManager;
begin
  if FVRSManager = nil then
    FVRSManager := TCastleVulkanVRSManager.Create(Self);
  Result := FVRSManager;
end;

function TVulkanRHIDevice.GetRuntimeVirtualTexture: TCastleVulkanRuntimeVirtualTexture;
begin
  if FRuntimeVirtualTexture = nil then
    FRuntimeVirtualTexture := TCastleVulkanRuntimeVirtualTexture.Create(Self);
  Result := FRuntimeVirtualTexture;
end;

function TVulkanRHIDevice.GetSparseVolumeAtlas: TCastleVulkanSparseVolumeAtlas;
begin
  if FSparseVolumeAtlas = nil then
    FSparseVolumeAtlas := TCastleVulkanSparseVolumeAtlas.Create(Self);
  Result := FSparseVolumeAtlas;
end;

function TVulkanRHIDevice.GetBreadcrumbTracker: TCastleVulkanBreadcrumbTracker;
begin
  if FBreadcrumbTracker = nil then
    FBreadcrumbTracker := TCastleVulkanBreadcrumbTracker.Create(Self);
  Result := FBreadcrumbTracker;
end;

function TVulkanRHIDevice.GetSVGFDenoiser: TCastleVulkanSVGFDenoiser;
begin
  if FSVGFDenoiser = nil then
    FSVGFDenoiser := TCastleVulkanSVGFDenoiser.Create(Self);
  Result := FSVGFDenoiser;
end;

function TVulkanRHIDevice.GetShaderBindingTable: TCastleVulkanShaderBindingTable;
begin
  if FShaderBindingTable = nil then
    FShaderBindingTable := TCastleVulkanShaderBindingTable.Create(Self);
  Result := FShaderBindingTable;
end;

function TVulkanRHIDevice.GetAccelerationStructureManager: TCastleVulkanAccelerationStructureManager;
begin
  if FAccelerationStructureManager = nil then
    FAccelerationStructureManager := TCastleVulkanAccelerationStructureManager.Create(Self);
  Result := FAccelerationStructureManager;
end;

function TVulkanRHIDevice.GetXPBDSimulator: TCastleVulkanXPBDSimulator;
begin
  if FXPBDSimulator = nil then
    FXPBDSimulator := TCastleVulkanXPBDSimulator.Create(Self);
  Result := FXPBDSimulator;
end;

function TVulkanRHIDevice.GetMultiviewStereoManager: TCastleVulkanMultiviewStereoManager;
begin
  if FMultiviewStereoManager = nil then
    FMultiviewStereoManager := TCastleVulkanMultiviewStereoManager.Create(Self);
  Result := FMultiviewStereoManager;
end;

function TVulkanRHIDevice.GetPerInstanceCustomData: TCastleVulkanPerInstanceCustomData;
begin
  if FPerInstanceCustomData = nil then
    FPerInstanceCustomData := TCastleVulkanPerInstanceCustomData.Create(Self);
  Result := FPerInstanceCustomData;
end;

function TVulkanRHIDevice.GetNeuralDenoiser: TCastleVulkanNeuralDenoiser;
begin
  if FNeuralDenoiser = nil then
    FNeuralDenoiser := TCastleVulkanNeuralDenoiser.Create(Self);
  Result := FNeuralDenoiser;
end;

function TVulkanRHIDevice.GetProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations;
begin
  if FProgrammableSampleLocations = nil then
    FProgrammableSampleLocations := TCastleVulkanProgrammableSampleLocations.Create(Self);
  Result := FProgrammableSampleLocations;
end;

function TVulkanRHIDevice.GetStreamCompactor: TCastleVulkanStreamCompactor;
begin
  if FStreamCompactor = nil then
    FStreamCompactor := TCastleVulkanStreamCompactor.Create(Self);
  Result := FStreamCompactor;
end;

function TVulkanRHIDevice.GetVoxelConeTracer: TCastleVulkanVoxelConeTracer;
begin
  if FVoxelConeTracer = nil then
    FVoxelConeTracer := TCastleVulkanVoxelConeTracer.Create(Self);
  Result := FVoxelConeTracer;
end;

function TVulkanRHIDevice.GetMaterialBinner: TCastleVulkanMaterialBinner;
begin
  if FMaterialBinner = nil then
    FMaterialBinner := TCastleVulkanMaterialBinner.Create(Self);
  Result := FMaterialBinner;
end;

function TVulkanRHIDevice.GetPerPixelLinkedListOIT: TCastleVulkanPerPixelLinkedListOIT;
begin
  if FPerPixelLinkedListOIT = nil then
    FPerPixelLinkedListOIT := TCastleVulkanPerPixelLinkedListOIT.Create(Self);
  Result := FPerPixelLinkedListOIT;
end;

function TVulkanRHIDevice.GetHostImageCopyManager: TCastleVulkanHostImageCopyManager;
begin
  if FHostImageCopyManager = nil then
    FHostImageCopyManager := TCastleVulkanHostImageCopyManager.Create(Self);
  Result := FHostImageCopyManager;
end;

function TVulkanRHIDevice.GetGaussianSplatRenderer: TCastleVulkanGaussianSplatRenderer;
begin
  if FGaussianSplatRenderer = nil then
    FGaussianSplatRenderer := TCastleVulkanGaussianSplatRenderer.Create(Self);
  Result := FGaussianSplatRenderer;
end;

function TVulkanRHIDevice.GetDescriptorBufferManager: TCastleVulkanDescriptorBufferManager;
begin
  if FDescriptorBufferManager = nil then
    FDescriptorBufferManager := TCastleVulkanDescriptorBufferManager.Create(Self);
  Result := FDescriptorBufferManager;
end;

function TVulkanRHIDevice.GetHiZPyramidGenerator: TCastleVulkanHiZPyramidGenerator;
begin
  if FHiZPyramidGenerator = nil then
    FHiZPyramidGenerator := TCastleVulkanHiZPyramidGenerator.Create(Self);
  Result := FHiZPyramidGenerator;
end;

function TVulkanRHIDevice.GetAutoExposureHistogram: TCastleVulkanAutoExposureHistogram;
begin
  if FAutoExposureHistogram = nil then
    FAutoExposureHistogram := TCastleVulkanAutoExposureHistogram.Create(Self);
  Result := FAutoExposureHistogram;
end;

function TVulkanRHIDevice.GetFramePacer: TCastleVulkanFramePacer;
begin
  if FFramePacer = nil then
    FFramePacer := TCastleVulkanFramePacer.Create(Self);
  Result := FFramePacer;
end;

function TVulkanRHIDevice.GetIndirectComputeDispatcher: TCastleVulkanIndirectComputeDispatcher;
begin
  if FIndirectComputeDispatcher = nil then
    FIndirectComputeDispatcher := TCastleVulkanIndirectComputeDispatcher.Create(Self);
  Result := FIndirectComputeDispatcher;
end;

function TVulkanRHIDevice.GetBCnCompressor: TCastleVulkanBCnCompressor;
begin
  if FBCnCompressor = nil then
    FBCnCompressor := TCastleVulkanBCnCompressor.Create(Self);
  Result := FBCnCompressor;
end;

function TVulkanRHIDevice.GetPipelineBinaryManager: TCastleVulkanPipelineBinaryManager;
begin
  if FPipelineBinaryManager = nil then
    FPipelineBinaryManager := TCastleVulkanPipelineBinaryManager.Create(Self);
  Result := FPipelineBinaryManager;
end;

function TVulkanRHIDevice.GetWorkerCommandPoolManager: TCastleVulkanWorkerCommandPoolManager;
begin
  if FWorkerCommandPoolManager = nil then
    FWorkerCommandPoolManager := TCastleVulkanWorkerCommandPoolManager.Create(Self);
  Result := FWorkerCommandPoolManager;
end;

function TVulkanRHIDevice.GetBindlessIndirectBatch: TCastleVulkanBindlessIndirectBatch;
begin
  if FBindlessIndirectBatch = nil then
    FBindlessIndirectBatch := TCastleVulkanBindlessIndirectBatch.Create(Self);
  Result := FBindlessIndirectBatch;
end;

function TVulkanRHIDevice.GetVendorName: String;
begin
  Result := GetVulkanVendorName(FVendorKind);
end;

destructor TVulkanRHIDevice.Destroy;
var
  I: Integer;
begin
  SetActiveCommandList(nil);
  WaitIdle;
  FreeAndNil(FBindlessIndirectBatch);
  FreeAndNil(FWorkerCommandPoolManager);
  FreeAndNil(FPipelineBinaryManager);
  FreeAndNil(FBCnCompressor);
  FreeAndNil(FIndirectComputeDispatcher);
  FreeAndNil(FFramePacer);
  FreeAndNil(FAutoExposureHistogram);
  FreeAndNil(FHiZPyramidGenerator);
  FreeAndNil(FDescriptorBufferManager);
  FreeAndNil(FGaussianSplatRenderer);
  FreeAndNil(FHostImageCopyManager);
  FreeAndNil(FPerPixelLinkedListOIT);
  FreeAndNil(FMaterialBinner);
  FreeAndNil(FVoxelConeTracer);
  FreeAndNil(FStreamCompactor);
  FreeAndNil(FProgrammableSampleLocations);
  FreeAndNil(FNeuralDenoiser);
  FreeAndNil(FPerInstanceCustomData);
  FreeAndNil(FMultiviewStereoManager);
  FreeAndNil(FXPBDSimulator);
  FreeAndNil(FAccelerationStructureManager);
  FreeAndNil(FShaderBindingTable);
  FreeAndNil(FSVGFDenoiser);
  FreeAndNil(FBreadcrumbTracker);
  FreeAndNil(FSparseVolumeAtlas);
  FreeAndNil(FRuntimeVirtualTexture);
  FreeAndNil(FVRSManager);
  FreeAndNil(FTSRUpscaler);
  FreeAndNil(FReSTIR);
  FreeAndNil(FSurfaceCache);
  FreeAndNil(FGlobalSDF);
  FreeAndNil(FClusterDAG);
  FreeAndNil(FShadowCasterCuller);
  FreeAndNil(FTextureStreamer);
  FreeAndNil(FLODSelector);
  FreeAndNil(FVirtualShadowMap);
  FreeAndNil(FMeshletCuller);
  FreeAndNil(FDDGIGrid);
  FreeAndNil(FOceanSimulator);
  FreeAndNil(FAtmosphereRenderer);
  FreeAndNil(FTerrainCDLOD);
  FreeAndNil(FComputeSkinner);
  FreeAndNil(FContactShadows);
  FreeAndNil(FWeightedBlendedOIT);
  FreeAndNil(FComputeParticles);
  FreeAndNil(FDecalManager);
  FreeAndNil(FReflectionProbeManager);
  FreeAndNil(FTAA);
  FreeAndNil(FVolumetricFog);
  FreeAndNil(FSSR);
  FreeAndNil(FGTAO);
  FreeAndNil(FHDRPostProcessor);
  FreeAndNil(FShadowAtlas);
  FreeAndNil(FClusteredLightCuller);
  FreeAndNil(FIBLGenerator);
  FreeAndNil(FComputeCuller);
  FreeAndNil(FTimestampProfiler);
  FreeAndNil(FBindlessTextureManager);
  FreeAndNil(FStagingUploader);
  FlushAllDeferredDeletions;
  FActiveSwapchainSurface := nil;
  if FSwapchainSurfaces <> nil then
  begin
    FSwapchainSurfaces.Clear;
    FreeAndNil(FSwapchainSurfaces);
  end;
  DestroySwapchain;
  FreeAndNil(FPipelineMap);
  FreeAndNil(FComputePipelineMap);
  ClearPipelineLibraries;
  FreeAndNil(FVertexInputLibMap);
  FreeAndNil(FPreRasterLibMap);
  FreeAndNil(FFragmentShaderLibMap);
  FreeAndNil(FFragmentOutputLibMap);
  ClearFallbackFramebuffers;
  ClearFallbackRenderPasses;
  FreeAndNil(FFramebufferMap);
  FreeAndNil(FRenderPassMap);
  FreeAndNil(FPrewarm3DVertexShader);
  FreeAndNil(FPrewarm3DFragmentShader);
  FreeAndNil(FPrewarm2DVertexShader);
  FreeAndNil(FPrewarm2DFragmentShader);
  FreeAndNil(FDefaultWhiteCubeTexture);
  FreeAndNil(FDefaultBrdfLutTexture);
  FreeAndNil(FDefaultShadowDepthTexture);
  FreeAndNil(FDefaultFlatNormalTexture);
  FreeAndNil(FDefaultBlackTexture);
  FreeAndNil(FDefaultWhiteTexture);
  FreeAndNil(FDefaultBrdfLutSampler);
  FreeAndNil(FDefaultShadowSampler);
  FreeAndNil(FDefaultSampler);
  FDeferResourceDestruction := False;
  ReleaseRemainingDeviceResources;
  FlushAllDeferredDeletions;
  FreeAndNil(FLiveDescriptorSets);
  SetLength(FPendingRelocations, 0);
  SetLength(FRelocatedBuffers, 0);

  for I := 0 to MaxFramesInFlight - 1 do
  begin
    FreeAndNil(FFrames[I].CommandList);
    FreeAndNil(FFrames[I].TransientDescriptorAllocator);
    if (FDevice <> nil) and (FFrames[I].ImageAvailableSemaphore <> VK_NULL_HANDLE) then
      vkDestroySemaphore(FDevice, FFrames[I].ImageAvailableSemaphore, nil);
    if (FDevice <> nil) and (FFrames[I].RenderFinishedSemaphore <> VK_NULL_HANDLE) then
      vkDestroySemaphore(FDevice, FFrames[I].RenderFinishedSemaphore, nil);
    if (FDevice <> nil) and (FFrames[I].InFlightFence <> VK_NULL_HANDLE) then
      vkDestroyFence(FDevice, FFrames[I].InFlightFence, nil);
  end;

  FreeAndNil(FPersistentDescriptorAllocator);
  if (FDevice <> nil) and (FSingleTimeCommandPool <> VK_NULL_HANDLE) and Assigned(vkDestroyCommandPool) then
  begin
    vkDestroyCommandPool(FDevice, FSingleTimeCommandPool, nil);
    FSingleTimeCommandPool := VK_NULL_HANDLE;
  end;
  if (FDevice <> nil) and (FDescriptorPool <> VK_NULL_HANDLE) then
    vkDestroyDescriptorPool(FDevice, FDescriptorPool, nil);
  if (FDevice <> nil) and (FPipelineCache <> VK_NULL_HANDLE) then
    vkDestroyPipelineCache(FDevice, FPipelineCache, nil);
  FreeAndNil(FMemoryAllocator);
  if FDevice <> nil then
    vkDestroyDevice(FDevice, nil);
  if (FInstance <> nil) and (FSurface <> VK_NULL_HANDLE) then
    vkDestroySurfaceKHR(FInstance, FSurface, nil);
  if (FInstance <> nil) and (FDebugMessenger <> VK_NULL_HANDLE) and
     Assigned(vkDestroyDebugUtilsMessengerEXT) then
  begin
    vkDestroyDebugUtilsMessengerEXT(FInstance, FDebugMessenger, nil);
    FDebugMessenger := VK_NULL_HANDLE;
  end;
  if FInstance <> nil then
  begin
    vkDestroyInstance(FInstance, nil);
    UnloadVulkanInstance(FInstance);
  end;
  FreeAndNil(FValidationLock);

  inherited;
end;

{$endif read_implementation}
