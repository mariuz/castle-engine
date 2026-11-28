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
  TCastleVulkanClusteredLightCuller = class
  private
    FDevice: TVulkanRHIDevice;
    FGridX: Cardinal;
    FGridY: Cardinal;
    FGridZ: Cardinal;
    FWorkgroupSizeX: Cardinal;
    FClusterUniforms: TCastleClusterCullingUniformBlock;
    FLights: array[0..CASTLE_MAX_CLUSTERED_LIGHTS - 1] of TCastleClusteredLight;
    FActiveLightCount: Cardinal;
    FClusterGrid: array of TCastleClusterGridEntry;
    FLightIndexList: array of Cardinal;
    FClusterUniformBuffer: TRHIBuffer;
    FLightStorageBuffer: TRHIBuffer;
    FClusterGridBuffer: TRHIBuffer;
    FLightIndexBuffer: TRHIBuffer;
    FDescriptorLayout: TRHIDescriptorSetLayout;
    FDescriptorSet: TRHIDescriptorSet;
    FComputeShader: TRHIShaderModule;
    FComputePipeline: TRHIComputePipeline;
    FActiveClusterCount: Cardinal;
    FTotalAssignedLightRefs: Cardinal;
    FTotalDispatches: Cardinal;
    procedure EnsureResourcesCreated;
    function GetTotalClusters: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const AGridX: Cardinal = CASTLE_DEFAULT_CLUSTER_X;
      const AGridY: Cardinal = CASTLE_DEFAULT_CLUSTER_Y;
      const AGridZ: Cardinal = CASTLE_DEFAULT_CLUSTER_Z);
    destructor Destroy; override;

    { Configures the 3D cluster grid resolution (default 16 x 8 x 24 = 3,072 clusters). }
    procedure SetGridDimensions(const AGridX, AGridY, AGridZ: Cardinal);

    { Configures the camera projection matrix, viewport dimensions, and near/far planes
      used for exponential Z-slice subdivision and view-space cluster AABB reconstruction. }
    procedure SetCameraProjection(const AProjectionMatrix: TMatrix4;
      const AScreenWidth, AScreenHeight: Cardinal;
      const AZNear, AZFar: Single);

    { Resets the active clustered light list for the current frame. }
    procedure ClearLights;

    { Adds a directional, point, or spot light (up to CASTLE_MAX_CLUSTERED_LIGHTS = 256). }
    function AddDirectionalLight(const AViewDirection, AColor: TVector3;
      const AIntensity: Single = 1.0): Integer;
    function AddPointLight(const AViewPosition: TVector3; const ARange: Single;
      const AColor: TVector3; const AIntensity: Single = 1.0;
      const AShadowTileIndex: Integer = -1;
      const AShadowBias: Single = 0.001): Integer;
    function AddSpotLight(const AViewPosition, AViewDirection: TVector3;
      const ARange, AInnerSpotCos, AOuterSpotCos: Single;
      const AColor: TVector3; const AIntensity: Single = 1.0;
      const AShadowTileIndex: Integer = -1;
      const AShadowBias: Single = 0.001): Integer;

    { Computes the positive view-space depth bounds [ASliceNear, ASliceFar] for exponential Z-slice ASliceZ. }
    procedure ComputeSliceDepthBounds(const ASliceZ: Cardinal;
      out ASliceNear, ASliceFar: Single);

    { Reconstructs the view-space AABB [AAABBMin, AAABBMax] of 3D cluster (ACX, ACY, ACZ). }
    procedure ComputeClusterViewAABB(const ACX, ACY, ACZ: Cardinal;
      out AAABBMin, AAABBMax: TVector3);

    { Maps screen pixel coordinates (AScreenX, AScreenY) and positive view-space depth
      to 3D cluster coordinates (ACX, ACY, ACZ) and returns the flat 1D cluster index. }
    function ComputeClusterCoordFromScreenAndDepth(
      const AScreenX, AScreenY, APositiveViewDepth: Single;
      out ACX, ACY, ACZ: Cardinal): Cardinal;

    { Uploads the active light array and cluster uniforms, evaluates exact view-space
      sphere-vs-AABB cluster culling, and dispatches the GLSL 450 compute shader.
      Returns the number of dispatched compute workgroups. }
    function DispatchLightCulling(const ACmd: TRHICommandList): Cardinal;

    { Reads back the (Offset, Count) light grid entry for cluster (ACX, ACY, ACZ). }
    function GetClusterEntry(const ACX, ACY, ACZ: Cardinal): TCastleClusterGridEntry;

    { Reads back the light index at ALocalSlot (0 .. Entry.Count - 1) for cluster (ACX, ACY, ACZ). }
    function GetClusterLightIndex(const ACX, ACY, ACZ, ALocalSlot: Cardinal): Cardinal;

    property GridX: Cardinal read FGridX;
    property GridY: Cardinal read FGridY;
    property GridZ: Cardinal read FGridZ;
    property TotalClusters: Cardinal read GetTotalClusters;
    property ActiveLightCount: Cardinal read FActiveLightCount;
    property ActiveClusterCount: Cardinal read FActiveClusterCount;
    property TotalAssignedLightRefs: Cardinal read FTotalAssignedLightRefs;
    property TotalDispatches: Cardinal read FTotalDispatches;
    property ClusterUniformBuffer: TRHIBuffer read FClusterUniformBuffer;
    property LightStorageBuffer: TRHIBuffer read FLightStorageBuffer;
    property ClusterGridBuffer: TRHIBuffer read FClusterGridBuffer;
    property LightIndexBuffer: TRHIBuffer read FLightIndexBuffer;
    property ComputePipeline: TRHIComputePipeline read FComputePipeline;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 14.2: Directional Cascaded Shadow Maps (CSM) & Positional Atlas      }
  { -------------------------------------------------------------------------- }

  TCastleVulkanShadowAtlas = class
  private
    FDevice: TVulkanRHIDevice;
    FAtlasSize: Cardinal;
    FCascadeResolution: Cardinal;
    FShadowAtlasTexture: TVulkanRHITexture;
    FShadowAtlasSampler: TRHISampler;
    FCascadeBlock: TCastleDirectionalCascadeShadowBlock;
    FPositionalTiles: array[0..CASTLE_MAX_SHADOW_ATLAS_TILES - 1] of TCastlePositionalShadowTileEntry;
    FPositionalTileRects: array[0..CASTLE_MAX_SHADOW_ATLAS_TILES - 1] of TRectangle;
    FAllocatedTileCount: Cardinal;
    FShelfCursorX: Cardinal;
    FShelfCursorY: Cardinal;
    FShelfRowHeight: Cardinal;
    FCascadeUniformBuffer: TRHIBuffer;
    FPositionalTileBuffer: TRHIBuffer;
    FTotalCascadeUpdates: Cardinal;
    FTotalShadowTilePasses: Cardinal;
    procedure EnsureAtlasResourcesCreated;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const AAtlasSize: Cardinal = 2048;
      const ACascadeResolution: Cardinal = 512);
    destructor Destroy; override;

    { Computes 4 directional shadow cascade split distances using the Practical Split Scheme
      (Nvidia PSSM / Godot 4 CSM, ALambda in [0..1], default 0.75), builds tight orthographic
      light view-projection matrices with optional texel-snapping stabilization to eliminate
      shimmering, and assigns the 4 cascade tiles in the top row of the shadow atlas. }
    procedure ComputeDirectionalCascades(
      const ACameraInverseViewProj: TMatrix4;
      const AWorldLightDirection: TVector3;
      const AZNear, AZFar: Single;
      const ALambda: Single = 0.75;
      const AStabilizeTexels: Boolean = True);

    { Returns the viewport rectangle inside the shadow atlas for directional cascade ACascadeIndex (0..3). }
    function GetCascadeViewportRect(const ACascadeIndex: Cardinal): TRectangle;

    { Resets dynamic positional shadow tile allocations for a new frame while preserving
      the reserved directional cascade region. }
    procedure ResetPositionalTiles;

    { Selects an adaptive shadow tile resolution (ABaseResolution, ABaseResolution/2,
      ABaseResolution/4, min 64) based on distance to camera and light range. }
    class function ChooseTileResolution(const ADistanceToCamera, ALightRange: Single;
      const ABaseResolution: Cardinal = 512): Cardinal; static;

    { Sub-allocates a square depth tile of ADesiredResolution inside the positional region
      of the shadow atlas, stores ALightViewProj + normalized UV scale/offset, and outputs
      ATileIndex, AViewportRect, and AUVScaleOffset. }
    function AllocatePositionalTile(const ADesiredResolution: Cardinal;
      const ALightViewProj: TMatrix4;
      out ATileIndex: Integer;
      out AViewportRect: TRectangle;
      out AUVScaleOffset: TVector4): Boolean;

    { Uploads the directional cascade UBO and positional shadow tile SSBO to the GPU. }
    procedure UploadShadowBuffers;

    { Records a depth-only shadow tile rendering pass into AViewportRect of ShadowAtlasTexture
      with slope-scaled depth bias (SetDepthBias) to prevent shadow acne. }
    procedure RecordShadowTilePass(const ACmd: TRHICommandList;
      const AViewportRect: TRectangle;
      const ADepthBiasConstant: Single = 1.25;
      const ADepthBiasSlope: Single = 1.75);

    property AtlasSize: Cardinal read FAtlasSize;
    property CascadeResolution: Cardinal read FCascadeResolution;
    property ShadowAtlasTexture: TVulkanRHITexture read FShadowAtlasTexture;
    property ShadowAtlasSampler: TRHISampler read FShadowAtlasSampler;
    property CascadeBlock: TCastleDirectionalCascadeShadowBlock read FCascadeBlock;
    property AllocatedTileCount: Cardinal read FAllocatedTileCount;
    property CascadeUniformBuffer: TRHIBuffer read FCascadeUniformBuffer;
    property PositionalTileBuffer: TRHIBuffer read FPositionalTileBuffer;
    property TotalCascadeUpdates: Cardinal read FTotalCascadeUpdates;
    property TotalShadowTilePasses: Cardinal read FTotalShadowTilePasses;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 15.2 & 15.3: HDR Scene Target, Compute Mip-Chain Bloom, Luminance    }
  { Histogram Auto-Exposure & ACES Filmic / AgX Tonemapping Composite          }

  { -------------------------------------------------------------------------- }

  TCastleVulkanHDRPostProcessor = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FBloomMipCount: Cardinal;
    FHDRSceneTexture: TVulkanRHITexture;
    FBloomMipTextures: array[0..CASTLE_BLOOM_MAX_MIP_LEVELS - 1] of TVulkanRHITexture;
    FLinearClampSampler: TRHISampler;
    FHistogramBins: array[0..CASTLE_LUMINANCE_HISTOGRAM_BINS - 1] of Cardinal;
    FHistogramBuffer: TRHIBuffer;
    FExposureStateBuffer: TRHIBuffer;
    FBlackFallbackTexture: TVulkanRHITexture;
    FBloomDescriptorLayout: TRHIDescriptorSetLayout;
    FBloomDescriptorSet: TRHIDescriptorSet;
    FBloomDownsampleSets: array[0..CASTLE_BLOOM_MAX_MIP_LEVELS - 1] of TRHIDescriptorSet;
    FBloomUpsampleSets: array[0..CASTLE_BLOOM_MAX_MIP_LEVELS - 1] of TRHIDescriptorSet;
    FHistogramDescriptorLayout: TRHIDescriptorSetLayout;
    FHistogramDescriptorSet: TRHIDescriptorSet;
    FCompositeDescriptorLayout: TRHIDescriptorSetLayout;
    FCompositeDescriptorSet: TRHIDescriptorSet;
    FModulateDescriptorLayout: TRHIDescriptorSetLayout;
    FModulateDescriptorSet: TRHIDescriptorSet;
    FHiZCopyDescriptorLayout: TRHIDescriptorSetLayout;
    FHiZCopyDescriptorSet: TRHIDescriptorSet;
    FBloomDownsampleShader: TRHIShaderModule;
    FBloomUpsampleShader: TRHIShaderModule;
    FHistogramShader: TRHIShaderModule;
    FCompositeVertShader: TRHIShaderModule;
    FCompositeFragShader: TRHIShaderModule;
    FModulateShader: TRHIShaderModule;
    FHiZCopyShader: TRHIShaderModule;
    FBloomDownsamplePipeline: TRHIComputePipeline;
    FBloomUpsamplePipeline: TRHIComputePipeline;
    FHistogramPipeline: TRHIComputePipeline;
    FModulatePipeline: TRHIComputePipeline;
    FHiZCopyPipeline: TRHIComputePipeline;
    FCompositePipeline: TRHIPipeline;
    FCompositePipelineFormat: TRHIPixelFormat;
    FAOStrength: Single;
    FSSRStrength: Single;
    FRGSceneHDRRaw: TRHIRenderGraphResourceHandle;
    FRGSceneDepth: TRHIRenderGraphResourceHandle;
    FRGHiZMip0: TRHIRenderGraphResourceHandle;
    FRGGTAORaw: TRHIRenderGraphResourceHandle;
    FRGGTAODenoised: TRHIRenderGraphResourceHandle;
    FRGSSRReflection: TRHIRenderGraphResourceHandle;
    FRGSceneHDRLit: TRHIRenderGraphResourceHandle;
    FRGBloomMip0: TRHIRenderGraphResourceHandle;
    FRGFinalLDR: TRHIRenderGraphResourceHandle;
    FNextGenForwardCallback: TRHIRenderGraphPassExecuteEvent;
    FBloomThreshold: Single;
    FBloomKnee: Single;
    FBloomIntensity: Single;
    FBloomFilterRadius: Single;
    FExposure: Single;
    FGamma: Single;
    FSaturation: Single;
    FContrast: Single;
    FTonemapOperator: TCastleTonemapOperator;
    FEnableBloom: Boolean;
    FEnableAutoExposure: Boolean;
    FAutoExposureParams: TCastleAutoExposureParams;
    FAdaptedLuminance: Single;
    FAdaptedExposure: Single;
    FTargetLuminance: Single;
    FTotalBloomDownsampleDispatches: Cardinal;
    FTotalBloomUpsampleDispatches: Cardinal;
    FTotalHistogramDispatches: Cardinal;
    FTotalCompositePasses: Cardinal;
    function GetOrCreateCompositePipelineForFormat(const AFormat: TRHIPixelFormat): TRHIPipeline;
    procedure HandleNextGenForwardPass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure HandleNextGenHiZPass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure HandleNextGenGTAOHorizonPass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure HandleNextGenGTAODenoisePass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure HandleNextGenSSRPass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure HandleNextGenModulatePass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure HandleNextGenBloomPass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure HandleNextGenHistogramPass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure HandleNextGenCompositePass(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure EnsurePipelinesCreated;
    function GetBloomMipTexture(const AMipIndex: Cardinal): TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRGBA16_Float HDR scene color target and the
      6-level pfRGBA16_Float bloom mip pyramid for (AWidth, AHeight). }
    procedure EnsureHDRTargets(const AWidth, AHeight: Cardinal);

    { Dispatches the 13-tap Jiménez Karis downsample chain (Mip 0 .. FBloomMipCount-1)
      followed by the 9-tap 3x3 tent-filter upsample chain (FBloomMipCount-1 .. Mip 0).
      Returns total compute dispatches recorded. }
    function DispatchBloomPyramid(const ACmd: TRHICommandList): Cardinal;

    { Builds the 256-bin log2 luminance histogram from ASceneLinearSamples (and dispatches
      the GPU compute shader onto ACmd), computes the weighted average scene luminance,
      and updates FAdaptedLuminance and FAdaptedExposure using exponential temporal smoothing
      over ADeltaTime seconds. Returns the new AdaptedExposure. }
    function UpdateAutoExposure(const ACmd: TRHICommandList;
      const ASceneLinearSamples: array of TVector3;
      const ADeltaTime: Single): Single;

    { Records the HDR + Bloom + Auto-Exposure + ACES/AgX Tonemapping + sRGB composite pass
      into ADstLDRTarget. }
    procedure ExecuteCompositePass(const ACmd: TRHICommandList;
      const ADstLDRTarget: TRHITexture);

    { Dispatches the bloom pyramid reading from ASrcHDRTexture (default FHDRSceneTexture)
      and optionally writing final upsampled bloom into ADstBloomMip0Override. }
    function DispatchBloomPyramidFromTexture(const ACmd: TRHICommandList;
      const ASrcHDRTexture: TRHITexture;
      const ADstBloomMip0Override: TRHITexture = nil): Cardinal;

    { Dispatches the 256-bin GPU atomic log2-luminance histogram compute shader over ASrcHDRTexture. }
    procedure DispatchLuminanceHistogramOnGPU(const ACmd: TRHICommandList;
      const ASrcHDRTexture: TRHITexture);

    { Waits for GPU idle, invalidates host cache if needed, and reads back the 256 GPU-populated
      luminance histogram bins into FHistogramBins and AOutBins. Returns total pixel count summed across bins. }
    function ReadBackGpuHistogramBins(out AOutBins: array of Cardinal): Cardinal;

    { Modulates ASrcHDR by AGTAOTex (with AAOStrength) and adds ASSRTex * ASSRStrength into ADstModulatedHDR. }
    procedure DispatchPostProcessModulate(const ACmd: TRHICommandList;
      const ASrcHDR, AGTAOTex, ASSRTex, ADstModulatedHDR: TRHITexture;
      const AAOStrength: Single = 1.0; const ASSRStrength: Single = 1.0);

    { Records the fullscreen-triangle HDR + Bloom + Auto-Exposure + Tonemap + sRGB draw call
      reading ASrcHDR and ASrcBloom into ADstLDRTarget. When AInsideRenderGraphPass = True,
      assumes BeginRendering/EndRendering is already active on ACmd. }
    procedure ExecuteCompositeFromTextures(const ACmd: TRHICommandList;
      const ASrcHDR, ASrcBloom, ADstLDRTarget: TRHITexture;
      const AInsideRenderGraphPass: Boolean = False);

    { Populates a declarative TRHIRenderGraph with the complete 4-stage HDR frame pipeline:
      1. Forward3DHDRPass (writes transient HDRColor + transient HDRDepth)
      2. BloomPyramidComputePass (reads HDRColor, writes transient BloomMip0)
      3. LuminanceHistogramComputePass (reads HDRColor, writes ExposureStateBuffer)
      4. TonemapCompositePass (reads HDRColor + BloomMip0 + ExposureStateBuffer, writes imported ASwapchainColor) }
    procedure BuildDefaultFrameRenderGraph(const AGraph: TRHIRenderGraph;
      const AWidth, AHeight: Cardinal;
      const ASwapchainColor: TRHITexture);

    { Phase 111.3: Populates and wires live GPU OnExecute callbacks for the complete 9-pass
      Next-Gen Post-Processing Render Graph (Forward HDR+Depth -> Hi-Z -> GTAO Horizon ->
      GTAO Denoise -> Hi-Z SSR -> PostProcess Modulate -> Bloom Pyramid -> Luminance Histogram ->
      Tonemap Composite) with physical VkDeviceMemory aliasing across non-overlapping transients. }
    procedure BuildNextGenPostProcessRenderGraph(const AGraph: TRHIRenderGraph;
      const AWidth, AHeight: Cardinal;
      const AFinalLDRTarget: TRHITexture;
      const ASceneForwardDrawCallback: TRHIRenderGraphPassExecuteEvent = nil;
      const AIncludeDeadDebugPass: Boolean = False);

    { Exact reference evaluators matching the GLSL 450 shaders for deterministic verification }
    class function EvaluateKarisWeight(const ALinearRGB: TVector3): Single; static;
    class function EvaluateKarisAverage4(const C0, C1, C2, C3: TVector3): TVector3; static;
    class function EvaluateSoftThreshold(const ALinearRGB: TVector3;
      const AThreshold, AKnee: Single): TVector3; static;
    class function EvaluateTonemapReinhard(const AHDR: TVector3): TVector3; static;
    class function EvaluateTonemapACESFilmic(const AHDR: TVector3): TVector3; static;
    class function EvaluateTonemapAgX(const AHDR: TVector3): TVector3; static;
    class function EvaluateLinearToSRGB(const ALinear: TVector3): TVector3; static;
    function EvaluateCompositeColor(const AHDRSceneColor, ABloomColor: TVector3): TVector3;
    function GetHistogramBinCount(const ABinIndex: Cardinal): Cardinal;

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property BloomMipCount: Cardinal read FBloomMipCount;
    property HDRSceneTexture: TVulkanRHITexture read FHDRSceneTexture;
    property BloomMipTextures[const AMipIndex: Cardinal]: TVulkanRHITexture read GetBloomMipTexture;
    property HistogramBuffer: TRHIBuffer read FHistogramBuffer;
    property ExposureStateBuffer: TRHIBuffer read FExposureStateBuffer;
    property BloomDownsamplePipeline: TRHIComputePipeline read FBloomDownsamplePipeline;
    property BloomUpsamplePipeline: TRHIComputePipeline read FBloomUpsamplePipeline;
    property HistogramPipeline: TRHIComputePipeline read FHistogramPipeline;
    property BloomThreshold: Single read FBloomThreshold write FBloomThreshold;
    property BloomKnee: Single read FBloomKnee write FBloomKnee;
    property BloomIntensity: Single read FBloomIntensity write FBloomIntensity;
    property BloomFilterRadius: Single read FBloomFilterRadius write FBloomFilterRadius;
    property Exposure: Single read FExposure write FExposure;
    property Gamma: Single read FGamma write FGamma;
    property Saturation: Single read FSaturation write FSaturation;
    property Contrast: Single read FContrast write FContrast;
    property TonemapOperator: TCastleTonemapOperator read FTonemapOperator write FTonemapOperator;
    property EnableBloom: Boolean read FEnableBloom write FEnableBloom;
    property EnableAutoExposure: Boolean read FEnableAutoExposure write FEnableAutoExposure;
    property AdaptedLuminance: Single read FAdaptedLuminance;
    property AdaptedExposure: Single read FAdaptedExposure;
    property TargetLuminance: Single read FTargetLuminance;
    property TotalBloomDownsampleDispatches: Cardinal read FTotalBloomDownsampleDispatches;
    property TotalBloomUpsampleDispatches: Cardinal read FTotalBloomUpsampleDispatches;
    property AOStrength: Single read FAOStrength write FAOStrength;
    property SSRStrength: Single read FSSRStrength write FSSRStrength;
    property CompositePipeline: TRHIPipeline read FCompositePipeline;
    property ModulatePipeline: TRHIComputePipeline read FModulatePipeline;
    property RGSceneHDRRawHandle: TRHIRenderGraphResourceHandle read FRGSceneHDRRaw;
    property RGSceneDepthHandle: TRHIRenderGraphResourceHandle read FRGSceneDepth;
    property RGHiZMip0Handle: TRHIRenderGraphResourceHandle read FRGHiZMip0;
    property RGGTAORawHandle: TRHIRenderGraphResourceHandle read FRGGTAORaw;
    property RGGTAODenoisedHandle: TRHIRenderGraphResourceHandle read FRGGTAODenoised;
    property RGSSRReflectionHandle: TRHIRenderGraphResourceHandle read FRGSSRReflection;
    property RGSceneHDRLitHandle: TRHIRenderGraphResourceHandle read FRGSceneHDRLit;
    property RGBloomMip0Handle: TRHIRenderGraphResourceHandle read FRGBloomMip0;
    property TotalHistogramDispatches: Cardinal read FTotalHistogramDispatches;
    property TotalCompositePasses: Cardinal read FTotalCompositePasses;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 16.1: Compute Ground-Truth Ambient Occlusion (GTAO) & Denoiser       }
  { -------------------------------------------------------------------------- }

  TCastleVulkanGTAO = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FHalfResolution: Boolean;
    FRawGTAOTexture: TVulkanRHITexture;
    FDenoisedGTAOTexture: TVulkanRHITexture;
    FLinearClampSampler: TRHISampler;
    FGTAODescriptorLayout: TRHIDescriptorSetLayout;
    FGTAODescriptorSet: TRHIDescriptorSet;
    FDenoiseDescriptorLayout: TRHIDescriptorSetLayout;
    FDenoiseDescriptorSet: TRHIDescriptorSet;
    FGTAOShader: TRHIShaderModule;
    FDenoiseShader: TRHIShaderModule;
    FGTAOPipeline: TRHIComputePipeline;
    FDenoisePipeline: TRHIComputePipeline;
    FEffectRadius: Single;
    FFalloffRange: Single;
    FPower: Single;
    FZNear: Single;
    FZFar: Single;
    FSliceCount: Cardinal;
    FStepsPerSlice: Cardinal;
    FTotalGTAODispatches: Cardinal;
    FTotalDenoiseDispatches: Cardinal;
    procedure EnsurePipelinesCreated;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the Raw and Denoised pfR16_Float GTAO targets. }
    procedure EnsureGTAOTargets(const AWidth, AHeight: Cardinal;
      const AHalfResolution: Boolean = False);

    { Dispatches the multi-slice GTAO horizon integral compute shader followed by the
      5x5 depth-aware cross-bilateral spatial denoiser. Returns total dispatches (2). }
    function DispatchGTAO(const ACmd: TRHICommandList;
      const ADepthTexture: TRHITexture): Cardinal;
    procedure DispatchGTAOHorizonToTarget(const ACmd: TRHICommandList;
      const ADepthTexture, ARawGTAOTarget: TRHITexture);
    procedure DispatchGTAODenoiseToTarget(const ACmd: TRHICommandList;
      const ADepthTexture, ARawGTAOTexture, ADenoisedGTAOTarget: TRHITexture);

    { Exact reference evaluators matching the GLSL 450 GTAO & bilateral filter shaders }
    class function ReconstructViewPosition(const AUV, AProjScale: TVector2;
      const ALinearZ: Single): TVector3; static;
    class function IntegrateGTAOHorizonSlice(const AH1, AH2, ANormalAngle: Single): Single; static;
    class function ComputeBilateralDepthWeight(const ACenterDepth, ASampleDepth,
      ASigmaDepth: Single): Single; static;
    function EvaluateGTAOFromHorizonCosines(const AMaxCos1, AMaxCos2,
      ANormalAngle: Single): Single;

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property HalfResolution: Boolean read FHalfResolution;
    property RawGTAOTexture: TVulkanRHITexture read FRawGTAOTexture;
    property DenoisedGTAOTexture: TVulkanRHITexture read FDenoisedGTAOTexture;
    property GTAOPipeline: TRHIComputePipeline read FGTAOPipeline;
    property DenoisePipeline: TRHIComputePipeline read FDenoisePipeline;
    property EffectRadius: Single read FEffectRadius write FEffectRadius;
    property FalloffRange: Single read FFalloffRange write FFalloffRange;
    property Power: Single read FPower write FPower;
    property ZNear: Single read FZNear write FZNear;
    property ZFar: Single read FZFar write FZFar;
    property SliceCount: Cardinal read FSliceCount write FSliceCount;
    property StepsPerSlice: Cardinal read FStepsPerSlice write FStepsPerSlice;
    property TotalGTAODispatches: Cardinal read FTotalGTAODispatches;
    property TotalDenoiseDispatches: Cardinal read FTotalDenoiseDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 16.2: Hierarchical-Z Screen-Space Reflections (Hi-Z SSR)             }
  { -------------------------------------------------------------------------- }

  TCastleVulkanSSR = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FSSRReflectionTexture: TVulkanRHITexture;
    FLinearClampSampler: TRHISampler;
    FSSRDescriptorLayout: TRHIDescriptorSetLayout;
    FSSRDescriptorSet: TRHIDescriptorSet;
    FSSRShader: TRHIShaderModule;
    FSSRPipeline: TRHIComputePipeline;
    FZNear: Single;
    FZFar: Single;
    FMaxDistance: Single;
    FThickness: Single;
    FMaxRoughness: Single;
    FEdgeFadeWidth: Single;
    FIntensity: Single;
    FMaxSteps: Cardinal;
    FHiZMipCount: Cardinal;
    FTotalSSRDispatches: Cardinal;
    procedure EnsurePipelineCreated;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRGBA16_Float SSR reflection output texture. }
    procedure EnsureSSRTarget(const AWidth, AHeight: Cardinal);

    { Dispatches the Hi-Z Screen-Space Reflections compute shader. }
    function DispatchSSR(const ACmd: TRHICommandList;
      const AHDRSceneColor, AHiZPyramid: TRHITexture): Cardinal;
    function DispatchSSRToTarget(const ACmd: TRHICommandList;
      const AHDRSceneColor, AHiZPyramid, ASSROutTarget: TRHITexture): Cardinal;

    { Exact reference evaluators matching the GLSL 450 Hi-Z SSR compute shader }
    class function EvaluateScreenEdgeFade(const AHitUV: TVector2;
      const AFadeWidth: Single): Single; static;
    class function EvaluateSSRReflectionWeight(const ARoughness, AMaxRoughness,
      ACosTheta: Single): Single; static;
    function RaymarchHiZ1D(const AHiZMip0Depths: array of Single;
      const AStartCell: Integer; const AStartDepth, ARayStepZ: Single;
      out AHitCell: Integer; out AHitSteps: Cardinal): Boolean;

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property SSRReflectionTexture: TVulkanRHITexture read FSSRReflectionTexture;
    property SSRPipeline: TRHIComputePipeline read FSSRPipeline;
    property ZNear: Single read FZNear write FZNear;
    property ZFar: Single read FZFar write FZFar;
    property MaxDistance: Single read FMaxDistance write FMaxDistance;
    property Thickness: Single read FThickness write FThickness;
    property MaxRoughness: Single read FMaxRoughness write FMaxRoughness;
    property EdgeFadeWidth: Single read FEdgeFadeWidth write FEdgeFadeWidth;
    property Intensity: Single read FIntensity write FIntensity;
    property MaxSteps: Cardinal read FMaxSteps write FMaxSteps;
    property HiZMipCount: Cardinal read FHiZMipCount write FHiZMipCount;
    property TotalSSRDispatches: Cardinal read FTotalSSRDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 16.3: 3D Froxel Volumetric Fog & Exponential Height Fog              }
  { -------------------------------------------------------------------------- }

  TCastleVulkanVolumetricFog = class
  private
    FDevice: TVulkanRHIDevice;
    FGridX: Cardinal;
    FGridY: Cardinal;
    FGridZ: Cardinal;
    FFroxelScatteringVolume: TVulkanRHITexture;
    FIntegratedFroxelLUT: TVulkanRHITexture;
    FLinearClampSampler: TRHISampler;
    FInjectDescriptorLayout: TRHIDescriptorSetLayout;
    FInjectDescriptorSet: TRHIDescriptorSet;
    FRaymarchDescriptorLayout: TRHIDescriptorSetLayout;
    FRaymarchDescriptorSet: TRHIDescriptorSet;
    FInjectShader: TRHIShaderModule;
    FRaymarchShader: TRHIShaderModule;
    FInjectPipeline: TRHIComputePipeline;
    FRaymarchPipeline: TRHIComputePipeline;
    FFogAlbedo: TVector3;
    FBaseDensity: Single;
    FSunDirection: TVector3;
    FAnisotropyG: Single;
    FSunColor: TVector3;
    FSunIntensity: Single;
    FHeightFalloff: Single;
    FBaseHeight: Single;
    FZNear: Single;
    FZFar: Single;
    FTotalInjectDispatches: Cardinal;
    FTotalRaymarchDispatches: Cardinal;
    procedure EnsurePipelinesCreated;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the 3D Froxel Scattering Volume and Integrated Froxel LUT (td3D, pfRGBA16_Float). }
    procedure EnsureFroxelVolumes(
      const AGridX: Cardinal = CASTLE_FROXEL_GRID_X;
      const AGridY: Cardinal = CASTLE_FROXEL_GRID_Y;
      const AGridZ: Cardinal = CASTLE_FROXEL_GRID_Z);

    { Dispatches the 3D Froxel Density/Scattering Injection pass followed by the
      front-to-back Beer-Lambert Raymarching Integration pass. Returns total dispatches (2). }
    function DispatchVolumetricFog(const ACmd: TRHICommandList): Cardinal;

    { Exact reference evaluators matching the GLSL 450 Volumetric Fog compute shaders }
    class function EvaluateHenyeyGreensteinPhase(const ACosTheta,
      AAnisotropyG: Single): Single; static;
    class function EvaluateHeightFogDensity(const AWorldY, ABaseDensity,
      ABaseHeight, AHeightFalloff: Single): Single; static;
    class procedure IntegrateFroxelSliceStep(const ASliceScattering: TVector3;
      const ASliceExtinction, AStepLength: Single;
      var AAccumLight: TVector3; var AAccumTransmittance: Single); static;

    property GridX: Cardinal read FGridX;
    property GridY: Cardinal read FGridY;
    property GridZ: Cardinal read FGridZ;
    property FroxelScatteringVolume: TVulkanRHITexture read FFroxelScatteringVolume;
    property IntegratedFroxelLUT: TVulkanRHITexture read FIntegratedFroxelLUT;
    property InjectPipeline: TRHIComputePipeline read FInjectPipeline;
    property RaymarchPipeline: TRHIComputePipeline read FRaymarchPipeline;
    property FogAlbedo: TVector3 read FFogAlbedo write FFogAlbedo;
    property BaseDensity: Single read FBaseDensity write FBaseDensity;
    property SunDirection: TVector3 read FSunDirection write FSunDirection;
    property AnisotropyG: Single read FAnisotropyG write FAnisotropyG;
    property SunColor: TVector3 read FSunColor write FSunColor;
    property SunIntensity: Single read FSunIntensity write FSunIntensity;
    property HeightFalloff: Single read FHeightFalloff write FHeightFalloff;
    property BaseHeight: Single read FBaseHeight write FBaseHeight;
    property ZNear: Single read FZNear write FZNear;
    property ZFar: Single read FZFar write FZFar;
    property TotalInjectDispatches: Cardinal read FTotalInjectDispatches;
    property TotalRaymarchDispatches: Cardinal read FTotalRaymarchDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 17.1: Sub-Pixel Halton Jitter, Velocity & Temporal Anti-Aliasing     }
  { -------------------------------------------------------------------------- }

  { Manages 8/16-sample Halton (2, 3) sub-pixel projection jitter, 2D screen-space
    motion vectors (pfRG16_Float), ping-pong temporal HDR history targets (pfRGBA16_Float),
    YCoCg 3x3 neighborhood variance clipping, and 5-tap Catmull-Rom bicubic TAA resolve. }
  TCastleVulkanTAA = class
  private
    FDevice: TVulkanRHIDevice;
    FLinearClampSampler: TRHISampler;
    FVelocityTexture: TVulkanRHITexture;
    FHistoryTextures: array[0..1] of TVulkanRHITexture;
    FTAADescriptorLayout: TRHIDescriptorSetLayout;
    FTAADescriptorSet: TRHIDescriptorSet;
    FTAAShader: TRHIShaderModule;
    FTAAPipeline: TRHIComputePipeline;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FCurrentHistoryIndex: Integer;
    FSampleCount: Cardinal;
    FBlendFactor: Single;
    FVarianceClipGamma: Single;
    FVelocityWeightScale: Single;
    FTotalTAADispatches: Cardinal;
    procedure EnsurePipelineCreated;
    function GetResolvedHistoryTexture: TVulkanRHITexture;
    function GetPreviousHistoryTexture: TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRG16_Float velocity texture and ping-pong pfRGBA16_Float history targets. }
    procedure EnsureTAATargets(const AWidth, AHeight: Cardinal);

    { Dispatches the compute TAA resolve pass, reading ACurrentHDRTexture, PreviousHistoryTexture,
      and VelocityTexture, and writing to ResolvedHistoryTexture. Returns 1 when dispatched. }
    function DispatchTAAResolve(const ACmd: TRHICommandList;
      const ACurrentHDRTexture: TRHITexture;
      const AFrameIndex: Cardinal = 0): Cardinal;

    { Evaluates the 1D radical inverse Halton sequence in base ABase for 1-based sample AIndex. }
    class function EvaluateHaltonSequence(const AIndex, ABase: Cardinal): Single; static;

    { Computes the sub-pixel Halton (2, 3) camera jitter offset in NDC [-1/W .. +1/W] for AFrameIndex. }
    class function ComputeHaltonJitterOffset(const AFrameIndex, ASampleCount,
      AWidth, AHeight: Cardinal): TVector2; static;

    { Converts linear RGB to YCoCg luminance-chrominance space. }
    class function RGBToYCoCg(const ARGB: TVector3): TVector3; static;

    { Converts YCoCg luminance-chrominance back to linear RGB. }
    class function YCoCgToRGB(const AYCoCg: TVector3): TVector3; static;

    { Clips history YCoCg color against the 3x3 neighborhood AABB [Mean - Gamma*StdDev, Mean + Gamma*StdDev]. }
    class function ClipHistoryYCoCg(const AHistoryYCoCg, AMeanYCoCg, AStdDevYCoCg: TVector3;
      const AGamma: Single = 1.25): TVector3; static;

    property VelocityTexture: TVulkanRHITexture read FVelocityTexture;
    property ResolvedHistoryTexture: TVulkanRHITexture read GetResolvedHistoryTexture;
    property PreviousHistoryTexture: TVulkanRHITexture read GetPreviousHistoryTexture;
    property TAAPipeline: TRHIComputePipeline read FTAAPipeline;
    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property SampleCount: Cardinal read FSampleCount write FSampleCount;
    property BlendFactor: Single read FBlendFactor write FBlendFactor;
    property VarianceClipGamma: Single read FVarianceClipGamma write FVarianceClipGamma;
    property VelocityWeightScale: Single read FVelocityWeightScale write FVelocityWeightScale;
    property TotalTAADispatches: Cardinal read FTotalTAADispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 18.2: Weighted Blended Order-Independent Transparency (McGuire 2013) }
  { -------------------------------------------------------------------------- }

  { Manages the dual MRT targets (pfRGBA16_Float accumulation + pfR16_Float revealage)
    and depth-weight/composite math for Weighted Blended Order-Independent Transparency. }
  TCastleVulkanWeightedBlendedOIT = class
  private
    FDevice: TVulkanRHIDevice;
    FOITAccumTexture: TVulkanRHITexture;
    FOITRevealageTexture: TVulkanRHITexture;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FWeightScale: Single;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure EnsureOITTargets(const AWidth, AHeight: Cardinal);

    { Evaluates the McGuire-Bavoil 2013 depth weight w(z, alpha) clamped to [1e-2 .. 3e3]. }
    class function EvaluateOITDepthWeight(const ALinearZ, AAlpha, AWeightScale: Single): Single; static;

    { Accumulates a transparent sample (PremulRGB, Alpha) at ALinearZ into AAccumRGBA and ARevealage. }
    class procedure AccumulateOITSample(const APremulColorAndAlpha: TVector4;
      const ALinearZ, AWeightScale: Single;
      var AAccumRGBA: TVector4; var ARevealage: Single); static;

    { Composites accumulated OIT buffers over AOpaqueRGB:
      mix(Accum.rgb / max(Accum.a, 1e-5), OpaqueRGB, Revealage). }
    class function EvaluateOITComposite(const AAccumRGBA: TVector4;
      const ARevealage: Single; const AOpaqueRGB: TVector3): TVector3; static;

    property OITAccumTexture: TVulkanRHITexture read FOITAccumTexture;
    property OITRevealageTexture: TVulkanRHITexture read FOITRevealageTexture;
    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property WeightScale: Single read FWeightScale write FWeightScale;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Meshlet / Sub-Mesh Cluster Cone & Frustum Culling (Phase 22.2)         }
  { -------------------------------------------------------------------------- }

  { Manages 64-vertex / 124-triangle meshlet cluster descriptors, normal-cone
    backface culling, and GPU visible meshlet compaction. }
  TCastleMeshletTriangle = packed record
    V0, V1, V2, Pad: Cardinal;
  end;

{$endif read_interface}

{$ifdef read_implementation}
{ ---------------------------------------------------------------------------- }
{ TCastleVulkanGTAO                                                            }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanGTAO.Create(const ADevice: TVulkanRHIDevice);
var
  SamplerDesc: TRHISamplerDesc;
begin
  inherited Create;
  FDevice := ADevice;
  FEffectRadius := 1.5;
  FFalloffRange := 0.6;
  FPower := 1.5;
  FZNear := 0.1;
  FZFar := 500.0;
  FSliceCount := 3;
  FStepsPerSlice := 4;

  if FDevice <> nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    FLinearClampSampler := FDevice.CreateSampler(SamplerDesc);
  end;
end;

destructor TCastleVulkanGTAO.Destroy;
begin
  FGTAOPipeline := nil;
  FDenoisePipeline := nil;
  FreeAndNil(FDenoiseShader);
  FreeAndNil(FGTAOShader);
  FreeAndNil(FDenoiseDescriptorSet);
  FreeAndNil(FDenoiseDescriptorLayout);
  FreeAndNil(FGTAODescriptorSet);
  FreeAndNil(FGTAODescriptorLayout);
  FreeAndNil(FDenoisedGTAOTexture);
  FreeAndNil(FRawGTAOTexture);
  FreeAndNil(FLinearClampSampler);
  inherited;
end;

procedure TCastleVulkanGTAO.EnsurePipelinesCreated;
var
  Gen: TCastleShaderGeneratorRHI;
  GTAOBindings: array[0..1] of TRHIDescriptorBindingDesc;
  DenoiseBindings: array[0..2] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FGTAOPipeline <> nil) then
    Exit;

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FGTAOShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateGTAOComputeShader(8, 8), 'GTAOHorizon_CS');
    FDenoiseShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateGTAODenoiseComputeShader(8, 8), 'GTAODenoise_CS');

    FillChar(GTAOBindings, SizeOf(GTAOBindings), 0);
    GTAOBindings[0].Binding := 0;
    GTAOBindings[0].DescriptorType := dtCombinedImageSampler;
    GTAOBindings[0].Count := 1;
    GTAOBindings[0].StageFlags := [ssCompute];

    GTAOBindings[1].Binding := 1;
    GTAOBindings[1].DescriptorType := dtStorageImage;
    GTAOBindings[1].Count := 1;
    GTAOBindings[1].StageFlags := [ssCompute];

    FGTAODescriptorLayout := FDevice.CreateDescriptorSetLayout(GTAOBindings);
    FGTAODescriptorSet := FDevice.CreateDescriptorSet(FGTAODescriptorLayout);

    FillChar(DenoiseBindings, SizeOf(DenoiseBindings), 0);
    DenoiseBindings[0] := GTAOBindings[0];
    DenoiseBindings[1].Binding := 1;
    DenoiseBindings[1].DescriptorType := dtCombinedImageSampler;
    DenoiseBindings[1].Count := 1;
    DenoiseBindings[1].StageFlags := [ssCompute];

    DenoiseBindings[2].Binding := 2;
    DenoiseBindings[2].DescriptorType := dtStorageImage;
    DenoiseBindings[2].Count := 1;
    DenoiseBindings[2].StageFlags := [ssCompute];

    FDenoiseDescriptorLayout := FDevice.CreateDescriptorSetLayout(DenoiseBindings);
    FDenoiseDescriptorSet := FDevice.CreateDescriptorSet(FDenoiseDescriptorLayout);

    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FGTAOShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FGTAODescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleGTAOPushConstants);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'GTAOHorizonComputePSO';
    FGTAOPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);

    CompDesc.ComputeShader := FDenoiseShader;
    CompDesc.DescriptorSetLayouts[0] := FDenoiseDescriptorLayout;
    CompDesc.DebugName := 'GTAODenoiseComputePSO';
    FDenoisePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TCastleVulkanGTAO.EnsureGTAOTargets(const AWidth, AHeight: Cardinal;
  const AHalfResolution: Boolean);
var
  TargetW, TargetH: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  if AHalfResolution then
  begin
    TargetW := Max(Cardinal(1), AWidth div 2);
    TargetH := Max(Cardinal(1), AHeight div 2);
  end else
  begin
    TargetW := Max(Cardinal(1), AWidth);
    TargetH := Max(Cardinal(1), AHeight);
  end;

  if (FRawGTAOTexture <> nil) and (FWidth = TargetW) and (FHeight = TargetH) and
     (FHalfResolution = AHalfResolution) then
    Exit;

  FWidth := TargetW;
  FHeight := TargetH;
  FHalfResolution := AHalfResolution;

  FreeAndNil(FRawGTAOTexture);
  FreeAndNil(FDenoisedGTAOTexture);

  if FDevice = nil then
    Exit;

  TexDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfR16_Float,
    [tuSampled, tuStorage, tuColorAttachment, tuTransferSrc, tuTransferDst], 1, 1);
  TexDesc.DebugName := 'GTAORawTexture';
  FRawGTAOTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc.DebugName := 'GTAODenoisedTexture';
  FDenoisedGTAOTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

procedure TCastleVulkanGTAO.DispatchGTAOHorizonToTarget(const ACmd: TRHICommandList;
  const ADepthTexture, ARawGTAOTarget: TRHITexture);
var
  PC: TCastleGTAOPushConstants;
  TargetW, TargetH, GroupsX, GroupsY: Cardinal;
begin
  if (ACmd = nil) or (FDevice = nil) or (ARawGTAOTarget = nil) then
    Exit;
  EnsurePipelinesCreated;
  TargetW := Max(Cardinal(1), ARawGTAOTarget.Desc.Width);
  TargetH := Max(Cardinal(1), ARawGTAOTarget.Desc.Height);

  FillChar(PC, SizeOf(PC), 0);
  PC.InvResolution := Vector2(1.0 / TargetW, 1.0 / TargetH);
  PC.ProjScale := Vector2(1.0, 1.0);
  PC.ZNear := FZNear;
  PC.ZFar := FZFar;
  PC.EffectRadius := FEffectRadius;
  PC.FalloffRange := FFalloffRange;
  PC.Power := FPower;
  PC.SliceCount := Max(Cardinal(1), FSliceCount);
  PC.StepsPerSlice := Max(Cardinal(1), FStepsPerSlice);
  PC.DenoisePass := 0;

  if ADepthTexture <> nil then
  begin
    ACmd.TransitionTexture(ADepthTexture, rsShaderRead);
    FGTAODescriptorSet.BindTexture(0, ADepthTexture, FLinearClampSampler);
  end;
  ACmd.TransitionTexture(ARawGTAOTarget, rsUnorderedAccess);
  FGTAODescriptorSet.BindTexture(1, ARawGTAOTarget, FLinearClampSampler);
  FGTAODescriptorSet.Update;

  GroupsX := (TargetW + 7) div 8;
  GroupsY := (TargetH + 7) div 8;
  ACmd.BindComputePipeline(FGTAOPipeline);
  ACmd.BindComputeDescriptorSet(0, FGTAODescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch(GroupsX, GroupsY, 1);
  Inc(FTotalGTAODispatches);
end;

procedure TCastleVulkanGTAO.DispatchGTAODenoiseToTarget(const ACmd: TRHICommandList;
  const ADepthTexture, ARawGTAOTexture, ADenoisedGTAOTarget: TRHITexture);
var
  PC: TCastleGTAOPushConstants;
  TargetW, TargetH, GroupsX, GroupsY: Cardinal;
begin
  if (ACmd = nil) or (FDevice = nil) or (ARawGTAOTexture = nil) or (ADenoisedGTAOTarget = nil) then
    Exit;
  EnsurePipelinesCreated;
  TargetW := Max(Cardinal(1), ADenoisedGTAOTarget.Desc.Width);
  TargetH := Max(Cardinal(1), ADenoisedGTAOTarget.Desc.Height);

  FillChar(PC, SizeOf(PC), 0);
  PC.InvResolution := Vector2(1.0 / TargetW, 1.0 / TargetH);
  PC.ProjScale := Vector2(1.0, 1.0);
  PC.ZNear := FZNear;
  PC.ZFar := FZFar;
  PC.EffectRadius := FEffectRadius;
  PC.FalloffRange := FFalloffRange;
  PC.Power := FPower;
  PC.SliceCount := Max(Cardinal(1), FSliceCount);
  PC.StepsPerSlice := Max(Cardinal(1), FStepsPerSlice);
  PC.DenoisePass := 1;

  if ADepthTexture <> nil then
  begin
    ACmd.TransitionTexture(ADepthTexture, rsShaderRead);
    FDenoiseDescriptorSet.BindTexture(0, ADepthTexture, FLinearClampSampler);
  end;
  ACmd.TransitionTexture(ARawGTAOTexture, rsShaderRead);
  ACmd.TransitionTexture(ADenoisedGTAOTarget, rsUnorderedAccess);
  FDenoiseDescriptorSet.BindTexture(1, ARawGTAOTexture, FLinearClampSampler);
  FDenoiseDescriptorSet.BindTexture(2, ADenoisedGTAOTarget, FLinearClampSampler);
  FDenoiseDescriptorSet.Update;

  GroupsX := (TargetW + 7) div 8;
  GroupsY := (TargetH + 7) div 8;
  ACmd.BindComputePipeline(FDenoisePipeline);
  ACmd.BindComputeDescriptorSet(0, FDenoiseDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch(GroupsX, GroupsY, 1);
  Inc(FTotalDenoiseDispatches);
end;

function TCastleVulkanGTAO.DispatchGTAO(const ACmd: TRHICommandList;
  const ADepthTexture: TRHITexture): Cardinal;
begin
  Result := 0;
  if (ACmd = nil) or (FDevice = nil) then
    Exit;

  if FRawGTAOTexture = nil then
  begin
    if ADepthTexture <> nil then
      EnsureGTAOTargets(ADepthTexture.Desc.Width, ADepthTexture.Desc.Height, FHalfResolution)
    else
      EnsureGTAOTargets(1280, 720, FHalfResolution);
  end;

  DispatchGTAOHorizonToTarget(ACmd, ADepthTexture, FRawGTAOTexture);
  DispatchGTAODenoiseToTarget(ACmd, ADepthTexture, FRawGTAOTexture, FDenoisedGTAOTexture);
  ACmd.TransitionTexture(FDenoisedGTAOTexture, rsShaderRead);
  Result := 2;
end;

class function TCastleVulkanGTAO.ReconstructViewPosition(
  const AUV, AProjScale: TVector2; const ALinearZ: Single): TVector3;
var
  NDC: TVector2;
begin
  NDC := Vector2(AUV.X * 2.0 - 1.0, AUV.Y * 2.0 - 1.0);
  Result := Vector3(NDC.X * AProjScale.X * ALinearZ, NDC.Y * AProjScale.Y * ALinearZ, -ALinearZ);
end;

class function TCastleVulkanGTAO.IntegrateGTAOHorizonSlice(
  const AH1, AH2, ANormalAngle: Single): Single;
var
  SinN, CosN, I1, I2: Single;
begin
  SinN := Sin(ANormalAngle);
  CosN := Cos(ANormalAngle);
  I1 := (-Cos(2.0 * AH1 - ANormalAngle) + CosN + 2.0 * AH1 * SinN) * 0.25;
  I2 := (-Cos(2.0 * AH2 - ANormalAngle) + CosN + 2.0 * AH2 * SinN) * 0.25;
  Result := EnsureRange(I1 + I2, 0.0, 1.0);
end;

class function TCastleVulkanGTAO.ComputeBilateralDepthWeight(
  const ACenterDepth, ASampleDepth, ASigmaDepth: Single): Single;
var
  Diff: Single;
begin
  Diff := Abs(ACenterDepth - ASampleDepth) / Max(1e-5, ASigmaDepth);
  Result := Exp(-Diff * Diff);
end;

function TCastleVulkanGTAO.EvaluateGTAOFromHorizonCosines(
  const AMaxCos1, AMaxCos2, ANormalAngle: Single): Single;
var
  H1, H2, SliceVis: Single;
begin
  H1 := -ArcCos(EnsureRange(AMaxCos1, -1.0, 1.0));
  H2 :=  ArcCos(EnsureRange(AMaxCos2, -1.0, 1.0));
  SliceVis := IntegrateGTAOHorizonSlice(H1, H2, ANormalAngle);
  Result := Math.Power(EnsureRange(SliceVis, 0.0, 1.0), Max(0.01, FPower));
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanSSR                                                             }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanSSR.Create(const ADevice: TVulkanRHIDevice);
var
  SamplerDesc: TRHISamplerDesc;
begin
  inherited Create;
  FDevice := ADevice;
  FZNear := 0.1;
  FZFar := 500.0;
  FMaxDistance := 50.0;
  FThickness := 0.25;
  FMaxRoughness := 0.6;
  FEdgeFadeWidth := 0.12;
  FIntensity := 1.0;
  FMaxSteps := 48;
  FHiZMipCount := 6;

  if FDevice <> nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    FLinearClampSampler := FDevice.CreateSampler(SamplerDesc);
  end;
end;

destructor TCastleVulkanSSR.Destroy;
begin
  FSSRPipeline := nil;
  FreeAndNil(FSSRShader);
  FreeAndNil(FSSRDescriptorSet);
  FreeAndNil(FSSRDescriptorLayout);
  FreeAndNil(FSSRReflectionTexture);
  FreeAndNil(FLinearClampSampler);
  inherited;
end;

procedure TCastleVulkanSSR.EnsurePipelineCreated;
var
  Gen: TCastleShaderGeneratorRHI;
  Bindings: array[0..2] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FSSRPipeline <> nil) then
    Exit;

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FSSRShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateHiZSSRComputeShader(8, 8), 'HiZSSR_CS');

    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtCombinedImageSampler;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssCompute];

    Bindings[1].Binding := 1;
    Bindings[1].DescriptorType := dtCombinedImageSampler;
    Bindings[1].Count := 1;
    Bindings[1].StageFlags := [ssCompute];

    Bindings[2].Binding := 2;
    Bindings[2].DescriptorType := dtStorageImage;
    Bindings[2].Count := 1;
    Bindings[2].StageFlags := [ssCompute];

    FSSRDescriptorLayout := FDevice.CreateDescriptorSetLayout(Bindings);
    FSSRDescriptorSet := FDevice.CreateDescriptorSet(FSSRDescriptorLayout);

    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FSSRShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FSSRDescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleSSRPushConstants);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'HiZSSRComputePSO';
    FSSRPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TCastleVulkanSSR.EnsureSSRTarget(const AWidth, AHeight: Cardinal);
var
  TargetW, TargetH: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  TargetW := Max(Cardinal(1), AWidth);
  TargetH := Max(Cardinal(1), AHeight);
  if (FSSRReflectionTexture <> nil) and (FWidth = TargetW) and (FHeight = TargetH) then
    Exit;

  FWidth := TargetW;
  FHeight := TargetH;
  FreeAndNil(FSSRReflectionTexture);

  if FDevice = nil then
    Exit;

  TexDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRGBA16_Float,
    [tuSampled, tuStorage, tuColorAttachment, tuTransferSrc, tuTransferDst], 1, 1);
  TexDesc.DebugName := 'HiZSSRReflectionTexture';
  FSSRReflectionTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanSSR.DispatchSSRToTarget(const ACmd: TRHICommandList;
  const AHDRSceneColor, AHiZPyramid, ASSROutTarget: TRHITexture): Cardinal;
var
  PC: TCastleSSRPushConstants;
  TargetW, TargetH, GroupsX, GroupsY: Cardinal;
begin
  Result := 0;
  if (ACmd = nil) or (FDevice = nil) or (ASSROutTarget = nil) then
    Exit;

  EnsurePipelineCreated;
  TargetW := Max(Cardinal(1), ASSROutTarget.Desc.Width);
  TargetH := Max(Cardinal(1), ASSROutTarget.Desc.Height);

  FillChar(PC, SizeOf(PC), 0);
  PC.InvResolution := Vector2(1.0 / TargetW, 1.0 / TargetH);
  PC.ZNear := FZNear;
  PC.ZFar := FZFar;
  PC.MaxDistance := FMaxDistance;
  PC.Thickness := FThickness;
  PC.MaxRoughness := FMaxRoughness;
  PC.EdgeFadeWidth := FEdgeFadeWidth;
  PC.MaxSteps := Max(Cardinal(1), FMaxSteps);
  PC.HiZMipCount := Max(Cardinal(1), FHiZMipCount);
  PC.Intensity := FIntensity;

  if AHDRSceneColor <> nil then
  begin
    ACmd.TransitionTexture(AHDRSceneColor, rsShaderRead);
    FSSRDescriptorSet.BindTexture(0, AHDRSceneColor, FLinearClampSampler);
  end;
  if AHiZPyramid <> nil then
  begin
    ACmd.TransitionTexture(AHiZPyramid, rsShaderRead);
    FSSRDescriptorSet.BindTexture(1, AHiZPyramid, FLinearClampSampler);
  end;
  ACmd.TransitionTexture(ASSROutTarget, rsUnorderedAccess);
  FSSRDescriptorSet.BindTexture(2, ASSROutTarget, FLinearClampSampler);
  FSSRDescriptorSet.Update;

  GroupsX := (TargetW + 7) div 8;
  GroupsY := (TargetH + 7) div 8;

  ACmd.BindComputePipeline(FSSRPipeline);
  ACmd.BindComputeDescriptorSet(0, FSSRDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch(GroupsX, GroupsY, 1);

  Inc(FTotalSSRDispatches);
  Result := 1;
end;

function TCastleVulkanSSR.DispatchSSR(const ACmd: TRHICommandList;
  const AHDRSceneColor, AHiZPyramid: TRHITexture): Cardinal;
begin
  Result := 0;
  if (ACmd = nil) or (FDevice = nil) then
    Exit;

  if FSSRReflectionTexture = nil then
  begin
    if AHDRSceneColor <> nil then
      EnsureSSRTarget(AHDRSceneColor.Desc.Width, AHDRSceneColor.Desc.Height)
    else
      EnsureSSRTarget(1280, 720);
  end;

  Result := DispatchSSRToTarget(ACmd, AHDRSceneColor, AHiZPyramid, FSSRReflectionTexture);
  if Result > 0 then
    ACmd.TransitionTexture(FSSRReflectionTexture, rsShaderRead);
end;

class function TCastleVulkanSSR.EvaluateScreenEdgeFade(
  const AHitUV: TVector2; const AFadeWidth: Single): Single;
  function SmoothStep01(const Edge0, Edge1, X: Single): Single;
  var
    T: Single;
  begin
    T := EnsureRange((X - Edge0) / Max(1e-5, Edge1 - Edge0), 0.0, 1.0);
    Result := T * T * (3.0 - 2.0 * T);
  end;
var
  FW, BX, BY: Single;
begin
  FW := Max(1e-4, AFadeWidth);
  BX := SmoothStep01(0.0, FW, AHitUV.X) * SmoothStep01(0.0, FW, 1.0 - AHitUV.X);
  BY := SmoothStep01(0.0, FW, AHitUV.Y) * SmoothStep01(0.0, FW, 1.0 - AHitUV.Y);
  Result := EnsureRange(BX * BY, 0.0, 1.0);
end;

class function TCastleVulkanSSR.EvaluateSSRReflectionWeight(
  const ARoughness, AMaxRoughness, ACosTheta: Single): Single;
var
  T, RoughWeight, Fresnel: Single;
begin
  if ARoughness >= AMaxRoughness then
    Exit(0.0);
  T := EnsureRange(ARoughness / Max(1e-4, AMaxRoughness), 0.0, 1.0);
  RoughWeight := 1.0 - (T * T * (3.0 - 2.0 * T));
  Fresnel := 0.04 + (Max(0.04, 1.0 - ARoughness) - 0.04) *
    Math.Power(EnsureRange(1.0 - ACosTheta, 0.0, 1.0), 5.0);
  Result := EnsureRange(RoughWeight * Fresnel, 0.0, 1.0);
end;

function TCastleVulkanSSR.RaymarchHiZ1D(
  const AHiZMip0Depths: array of Single;
  const AStartCell: Integer; const AStartDepth, ARayStepZ: Single;
  out AHitCell: Integer; out AHitSteps: Cardinal): Boolean;
  function SampleHiZMin(const CellIdx, MipLevel: Integer): Single;
  var
    Span, BaseIdx, I, EndIdx: Integer;
  begin
    Span := 1 shl MipLevel;
    BaseIdx := (CellIdx div Span) * Span;
    EndIdx := Min(High(AHiZMip0Depths), BaseIdx + Span - 1);
    Result := AHiZMip0Depths[EnsureRange(BaseIdx, 0, High(AHiZMip0Depths))];
    for I := BaseIdx + 1 to EndIdx do
      if AHiZMip0Depths[I] < Result then
        Result := AHiZMip0Depths[I];
  end;
var
  CurCell, NextCell, CellEnd, MipLevel, MaxMip, StepScale: Integer;
  CurZ, CellMaxRayZ, MinDepth: Single;
begin
  Result := False;
  AHitCell := -1;
  AHitSteps := 0;
  if Length(AHiZMip0Depths) = 0 then
    Exit;

  CurCell := AStartCell;
  CurZ := AStartDepth;
  MipLevel := 0;
  MaxMip := Min(Integer(FHiZMipCount) - 1, 4);

  while (AHitSteps < FMaxSteps) and (CurCell <= High(AHiZMip0Depths)) do
  begin
    Inc(AHitSteps);
    StepScale := 1 shl MipLevel;
    NextCell := ((CurCell div StepScale) + 1) * StepScale;
    CellEnd := Min(High(AHiZMip0Depths), NextCell - 1);
    CurZ := AStartDepth + Single(CurCell - AStartCell) * ARayStepZ;
    CellMaxRayZ := Max(CurZ, AStartDepth + Single(CellEnd - AStartCell) * ARayStepZ);
    MinDepth := SampleHiZMin(CurCell, MipLevel);
    if CellMaxRayZ >= MinDepth then
    begin
      if MipLevel = 0 then
      begin
        if (CurZ - MinDepth) <= FThickness then
        begin
          AHitCell := CurCell;
          Exit(True);
        end;
        Inc(CurCell);
      end else
        Dec(MipLevel);
    end else
    begin
      CurCell := NextCell;
      MipLevel := Min(MaxMip, MipLevel + 1);
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanVolumetricFog                                                   }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanVolumetricFog.Create(const ADevice: TVulkanRHIDevice);
var
  SamplerDesc: TRHISamplerDesc;
begin
  inherited Create;
  FDevice := ADevice;
  FFogAlbedo := Vector3(0.9, 0.92, 0.95);
  FBaseDensity := 0.025;
  FSunDirection := Vector3(-0.4, -0.8, -0.44).Normalize;
  FAnisotropyG := 0.65;
  FSunColor := Vector3(1.0, 0.95, 0.85);
  FSunIntensity := 4.0;
  FHeightFalloff := 0.08;
  FBaseHeight := 0.0;
  FZNear := 0.5;
  FZFar := 200.0;

  if FDevice <> nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    FLinearClampSampler := FDevice.CreateSampler(SamplerDesc);
  end;
end;

destructor TCastleVulkanVolumetricFog.Destroy;
begin
  FInjectPipeline := nil;
  FRaymarchPipeline := nil;
  FreeAndNil(FRaymarchShader);
  FreeAndNil(FInjectShader);
  FreeAndNil(FRaymarchDescriptorSet);
  FreeAndNil(FRaymarchDescriptorLayout);
  FreeAndNil(FInjectDescriptorSet);
  FreeAndNil(FInjectDescriptorLayout);
  FreeAndNil(FIntegratedFroxelLUT);
  FreeAndNil(FFroxelScatteringVolume);
  FreeAndNil(FLinearClampSampler);
  inherited;
end;

procedure TCastleVulkanVolumetricFog.EnsurePipelinesCreated;
var
  Gen: TCastleShaderGeneratorRHI;
  InjectBindings: array[0..0] of TRHIDescriptorBindingDesc;
  RaymarchBindings: array[0..1] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FInjectPipeline <> nil) then
    Exit;

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FInjectShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateVolumetricFogInjectComputeShader(4, 4, 4), 'VolumetricFogInject_CS');
    FRaymarchShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateVolumetricFogRaymarchComputeShader(8, 8), 'VolumetricFogRaymarch_CS');

    FillChar(InjectBindings, SizeOf(InjectBindings), 0);
    InjectBindings[0].Binding := 0;
    InjectBindings[0].DescriptorType := dtStorageImage;
    InjectBindings[0].Count := 1;
    InjectBindings[0].StageFlags := [ssCompute];

    FInjectDescriptorLayout := FDevice.CreateDescriptorSetLayout(InjectBindings);
    FInjectDescriptorSet := FDevice.CreateDescriptorSet(FInjectDescriptorLayout);

    FillChar(RaymarchBindings, SizeOf(RaymarchBindings), 0);
    RaymarchBindings[0].Binding := 0;
    RaymarchBindings[0].DescriptorType := dtCombinedImageSampler;
    RaymarchBindings[0].Count := 1;
    RaymarchBindings[0].StageFlags := [ssCompute];

    RaymarchBindings[1].Binding := 1;
    RaymarchBindings[1].DescriptorType := dtStorageImage;
    RaymarchBindings[1].Count := 1;
    RaymarchBindings[1].StageFlags := [ssCompute];

    FRaymarchDescriptorLayout := FDevice.CreateDescriptorSetLayout(RaymarchBindings);
    FRaymarchDescriptorSet := FDevice.CreateDescriptorSet(FRaymarchDescriptorLayout);

    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FInjectShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FInjectDescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleVolumetricFogParams);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'VolumetricFogInjectComputePSO';
    FInjectPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);

    CompDesc.ComputeShader := FRaymarchShader;
    CompDesc.DescriptorSetLayouts[0] := FRaymarchDescriptorLayout;
    CompDesc.DebugName := 'VolumetricFogRaymarchComputePSO';
    FRaymarchPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TCastleVulkanVolumetricFog.EnsureFroxelVolumes(
  const AGridX, AGridY, AGridZ: Cardinal);
var
  GX, GY, GZ: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  GX := Max(Cardinal(1), AGridX);
  GY := Max(Cardinal(1), AGridY);
  GZ := Max(Cardinal(1), AGridZ);

  if (FFroxelScatteringVolume <> nil) and
     (FGridX = GX) and (FGridY = GY) and (FGridZ = GZ) then
    Exit;

  FGridX := GX;
  FGridY := GY;
  FGridZ := GZ;

  FreeAndNil(FFroxelScatteringVolume);
  FreeAndNil(FIntegratedFroxelLUT);

  if FDevice = nil then
    Exit;

  TexDesc := Default(TRHITextureDesc);
  TexDesc.Dimension := td3D;
  TexDesc.Format := pfRGBA16_Float;
  TexDesc.Width := FGridX;
  TexDesc.Height := FGridY;
  TexDesc.DepthOrArrayLayers := FGridZ;
  TexDesc.MipLevels := 1;
  TexDesc.SampleCount := 1;
  TexDesc.Usage := [tuSampled, tuStorage];
  TexDesc.DebugName := 'FroxelScatteringVolume3D';
  FFroxelScatteringVolume := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc.DebugName := 'IntegratedFroxelLUT3D';
  FIntegratedFroxelLUT := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanVolumetricFog.DispatchVolumetricFog(
  const ACmd: TRHICommandList): Cardinal;
var
  Params: TCastleVolumetricFogParams;
begin
  Result := 0;
  if (ACmd = nil) or (FDevice = nil) then
    Exit;

  if FFroxelScatteringVolume = nil then
    EnsureFroxelVolumes;

  EnsurePipelinesCreated;

  FillChar(Params, SizeOf(Params), 0);
  Params.FogAlbedoAndBaseDensity := Vector4(FFogAlbedo.X, FFogAlbedo.Y, FFogAlbedo.Z, FBaseDensity);
  Params.SunDirectionAndAnisotropy := Vector4(FSunDirection.X, FSunDirection.Y, FSunDirection.Z,
    EnsureRange(FAnisotropyG, -0.99, 0.99));
  Params.SunColorAndIntensity := Vector4(FSunColor.X, FSunColor.Y, FSunColor.Z, FSunIntensity);
  Params.HeightFalloff := FHeightFalloff;
  Params.BaseHeight := FBaseHeight;
  Params.ZNear := FZNear;
  Params.ZFar := FZFar;

  { 1. 3D Froxel Density & Anisotropic Scattering Injection Pass }
  ACmd.TransitionTexture(FFroxelScatteringVolume, rsTransferDst);
  FInjectDescriptorSet.BindTexture(0, FFroxelScatteringVolume, FLinearClampSampler);
  FInjectDescriptorSet.Update;

  ACmd.BindComputePipeline(FInjectPipeline);
  ACmd.BindComputeDescriptorSet(0, FInjectDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Params), Params);
  ACmd.Dispatch((FGridX + 3) div 4, (FGridY + 3) div 4, (FGridZ + 3) div 4);
  Inc(FTotalInjectDispatches);
  Inc(Result);

  { 2. Front-to-Back Beer-Lambert Froxel Raymarching Integration Pass }
  ACmd.TransitionTexture(FFroxelScatteringVolume, rsShaderRead);
  ACmd.TransitionTexture(FIntegratedFroxelLUT, rsTransferDst);
  FRaymarchDescriptorSet.BindTexture(0, FFroxelScatteringVolume, FLinearClampSampler);
  FRaymarchDescriptorSet.BindTexture(1, FIntegratedFroxelLUT, FLinearClampSampler);
  FRaymarchDescriptorSet.Update;

  ACmd.BindComputePipeline(FRaymarchPipeline);
  ACmd.BindComputeDescriptorSet(0, FRaymarchDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Params), Params);
  ACmd.Dispatch((FGridX + 7) div 8, (FGridY + 7) div 8, 1);
  ACmd.TransitionTexture(FIntegratedFroxelLUT, rsShaderRead);
  Inc(FTotalRaymarchDispatches);
  Inc(Result);
end;

class function TCastleVulkanVolumetricFog.EvaluateHenyeyGreensteinPhase(
  const ACosTheta, AAnisotropyG: Single): Single;
const
  FOUR_PI = 12.56637061436;
var
  G, G2, Denom: Single;
begin
  G := EnsureRange(AAnisotropyG, -0.99, 0.99);
  G2 := G * G;
  Denom := Max(1e-4, 1.0 + G2 - 2.0 * G * EnsureRange(ACosTheta, -1.0, 1.0));
  Result := (1.0 - G2) / (FOUR_PI * Denom * Sqrt(Denom));
end;

class function TCastleVulkanVolumetricFog.EvaluateHeightFogDensity(
  const AWorldY, ABaseDensity, ABaseHeight, AHeightFalloff: Single): Single;
var
  DH: Single;
begin
  DH := Max(-50.0, AWorldY - ABaseHeight);
  Result := Max(0.0, ABaseDensity * Exp(-AHeightFalloff * DH));
end;

class procedure TCastleVulkanVolumetricFog.IntegrateFroxelSliceStep(
  const ASliceScattering: TVector3;
  const ASliceExtinction, AStepLength: Single;
  var AAccumLight: TVector3; var AAccumTransmittance: Single);
var
  StepTransmittance, InvExt: Single;
  SliceIntegral: TVector3;
begin
  StepTransmittance := Exp(-Max(0.0, ASliceExtinction) * Max(0.0, AStepLength));
  InvExt := (1.0 - StepTransmittance) / Max(1e-5, ASliceExtinction);
  SliceIntegral := ASliceScattering * InvExt;
  AAccumLight := AAccumLight + (SliceIntegral * AAccumTransmittance);
  AAccumTransmittance := AAccumTransmittance * StepTransmittance;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTAA                                                             }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTAA.Create(const ADevice: TVulkanRHIDevice);
var
  SamplerDesc: TRHISamplerDesc;
begin
  inherited Create;
  FDevice := ADevice;
  FSampleCount := 8;
  FBlendFactor := 0.08;
  FVarianceClipGamma := 1.25;
  FVelocityWeightScale := 40.0;
  FCurrentHistoryIndex := 0;

  if FDevice <> nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    FLinearClampSampler := FDevice.CreateSampler(SamplerDesc);
  end;
end;

destructor TCastleVulkanTAA.Destroy;
begin
  FTAAPipeline := nil;
  FreeAndNil(FTAAShader);
  FreeAndNil(FTAADescriptorSet);
  FreeAndNil(FTAADescriptorLayout);
  FreeAndNil(FHistoryTextures[0]);
  FreeAndNil(FHistoryTextures[1]);
  FreeAndNil(FVelocityTexture);
  FreeAndNil(FLinearClampSampler);
  inherited;
end;

procedure TCastleVulkanTAA.EnsurePipelineCreated;
var
  Gen: TCastleShaderGeneratorRHI;
  Bindings: array[0..3] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FTAAPipeline <> nil) then
    Exit;

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FTAAShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateTAAResolveComputeShader(8, 8), 'TAAResolve_CS');

    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtCombinedImageSampler;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssCompute];

    Bindings[1].Binding := 1;
    Bindings[1].DescriptorType := dtCombinedImageSampler;
    Bindings[1].Count := 1;
    Bindings[1].StageFlags := [ssCompute];

    Bindings[2].Binding := 2;
    Bindings[2].DescriptorType := dtCombinedImageSampler;
    Bindings[2].Count := 1;
    Bindings[2].StageFlags := [ssCompute];

    Bindings[3].Binding := 3;
    Bindings[3].DescriptorType := dtStorageImage;
    Bindings[3].Count := 1;
    Bindings[3].StageFlags := [ssCompute];

    FTAADescriptorLayout := FDevice.CreateDescriptorSetLayout(Bindings);
    FTAADescriptorSet := FDevice.CreateDescriptorSet(FTAADescriptorLayout);

    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FTAAShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FTAADescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleTAAPushConstants);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'TAAResolveComputePSO';
    FTAAPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TCastleVulkanTAA.EnsureTAATargets(const AWidth, AHeight: Cardinal);
var
  TargetW, TargetH: Cardinal;
  VelDesc, HistDesc: TRHITextureDesc;
begin
  TargetW := Max(Cardinal(1), AWidth);
  TargetH := Max(Cardinal(1), AHeight);

  if (FVelocityTexture <> nil) and (FWidth = TargetW) and (FHeight = TargetH) then
    Exit;

  FWidth := TargetW;
  FHeight := TargetH;

  FreeAndNil(FVelocityTexture);
  FreeAndNil(FHistoryTextures[0]);
  FreeAndNil(FHistoryTextures[1]);

  if FDevice = nil then
    Exit;

  VelDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRG16_Float,
    [tuSampled, tuStorage, tuColorAttachment], 1, 1);
  VelDesc.DebugName := 'TAAVelocityTexture';
  FVelocityTexture := FDevice.CreateTexture(VelDesc) as TVulkanRHITexture;

  HistDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRGBA16_Float,
    [tuSampled, tuStorage, tuColorAttachment], 1, 1);
  HistDesc.DebugName := 'TAAHistoryTexture0';
  FHistoryTextures[0] := FDevice.CreateTexture(HistDesc) as TVulkanRHITexture;

  HistDesc.DebugName := 'TAAHistoryTexture1';
  FHistoryTextures[1] := FDevice.CreateTexture(HistDesc) as TVulkanRHITexture;
end;

function TCastleVulkanTAA.GetResolvedHistoryTexture: TVulkanRHITexture;
begin
  Result := FHistoryTextures[FCurrentHistoryIndex and 1];
end;

function TCastleVulkanTAA.GetPreviousHistoryTexture: TVulkanRHITexture;
begin
  Result := FHistoryTextures[(FCurrentHistoryIndex xor 1) and 1];
end;

function TCastleVulkanTAA.DispatchTAAResolve(const ACmd: TRHICommandList;
  const ACurrentHDRTexture: TRHITexture;
  const AFrameIndex: Cardinal): Cardinal;
var
  PC: TCastleTAAPushConstants;
  PrevHist, ResolvedHist: TVulkanRHITexture;
  GroupsX, GroupsY: Cardinal;
begin
  Result := 0;
  if (ACmd = nil) or (FDevice = nil) then
    Exit;

  if FVelocityTexture = nil then
  begin
    if ACurrentHDRTexture <> nil then
      EnsureTAATargets(ACurrentHDRTexture.Desc.Width, ACurrentHDRTexture.Desc.Height)
    else
      EnsureTAATargets(1280, 720);
  end;

  EnsurePipelineCreated;

  FCurrentHistoryIndex := (FCurrentHistoryIndex xor 1) and 1;
  PrevHist := GetPreviousHistoryTexture;
  ResolvedHist := GetResolvedHistoryTexture;

  FillChar(PC, SizeOf(PC), 0);
  PC.InvResolution := Vector2(1.0 / Max(Cardinal(1), FWidth), 1.0 / Max(Cardinal(1), FHeight));
  PC.JitterOffset := ComputeHaltonJitterOffset(AFrameIndex, FSampleCount, FWidth, FHeight);
  PC.BlendFactor := FBlendFactor;
  PC.VarianceClipGamma := FVarianceClipGamma;
  PC.VelocityWeightScale := FVelocityWeightScale;
  PC.FrameIndex := AFrameIndex;

  ACmd.TransitionTexture(PrevHist, rsShaderRead);
  ACmd.TransitionTexture(FVelocityTexture, rsShaderRead);
  ACmd.TransitionTexture(ResolvedHist, rsTransferDst);

  if ACurrentHDRTexture <> nil then
    FTAADescriptorSet.BindTexture(0, ACurrentHDRTexture, FLinearClampSampler);
  FTAADescriptorSet.BindTexture(1, PrevHist, FLinearClampSampler);
  FTAADescriptorSet.BindTexture(2, FVelocityTexture, FLinearClampSampler);
  FTAADescriptorSet.BindTexture(3, ResolvedHist, FLinearClampSampler);
  FTAADescriptorSet.Update;

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;

  ACmd.BindComputePipeline(FTAAPipeline);
  ACmd.BindComputeDescriptorSet(0, FTAADescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch(GroupsX, GroupsY, 1);
  ACmd.TransitionTexture(ResolvedHist, rsShaderRead);

  Inc(FTotalTAADispatches);
  Result := 1;
end;

class function TCastleVulkanTAA.EvaluateHaltonSequence(
  const AIndex, ABase: Cardinal): Single;
var
  Idx, BaseVal: Cardinal;
  F, InvBase: Single;
begin
  Result := 0.0;
  BaseVal := Max(Cardinal(2), ABase);
  Idx := AIndex;
  InvBase := 1.0 / Single(BaseVal);
  F := InvBase;
  while Idx > 0 do
  begin
    Result := Result + Single(Idx mod BaseVal) * F;
    Idx := Idx div BaseVal;
    F := F * InvBase;
  end;
end;

class function TCastleVulkanTAA.ComputeHaltonJitterOffset(
  const AFrameIndex, ASampleCount, AWidth, AHeight: Cardinal): TVector2;
var
  CycleIndex: Cardinal;
  HX, HY: Single;
begin
  CycleIndex := (AFrameIndex mod Max(Cardinal(1), ASampleCount)) + 1;
  HX := EvaluateHaltonSequence(CycleIndex, 2) - 0.5;
  HY := EvaluateHaltonSequence(CycleIndex, 3) - 0.5;
  Result := Vector2(
    (2.0 * HX) / Single(Max(Cardinal(1), AWidth)),
    (2.0 * HY) / Single(Max(Cardinal(1), AHeight)));
end;

class function TCastleVulkanTAA.RGBToYCoCg(const ARGB: TVector3): TVector3;
begin
  Result.X := 0.25 * ARGB.X + 0.50 * ARGB.Y + 0.25 * ARGB.Z;
  Result.Y := 0.50 * ARGB.X - 0.50 * ARGB.Z;
  Result.Z := -0.25 * ARGB.X + 0.50 * ARGB.Y - 0.25 * ARGB.Z;
end;

class function TCastleVulkanTAA.YCoCgToRGB(const AYCoCg: TVector3): TVector3;
var
  Tmp: Single;
begin
  Tmp := AYCoCg.X - AYCoCg.Z;
  Result.X := Max(0.0, Tmp + AYCoCg.Y);
  Result.Y := Max(0.0, AYCoCg.X + AYCoCg.Z);
  Result.Z := Max(0.0, Tmp - AYCoCg.Y);
end;

class function TCastleVulkanTAA.ClipHistoryYCoCg(
  const AHistoryYCoCg, AMeanYCoCg, AStdDevYCoCg: TVector3;
  const AGamma: Single): TVector3;
var
  G: Single;
  BoxMin, BoxMax: TVector3;
begin
  G := Max(0.1, AGamma);
  BoxMin := AMeanYCoCg - (AStdDevYCoCg * G);
  BoxMax := AMeanYCoCg + (AStdDevYCoCg * G);
  Result.X := EnsureRange(AHistoryYCoCg.X, BoxMin.X, BoxMax.X);
  Result.Y := EnsureRange(AHistoryYCoCg.Y, BoxMin.Y, BoxMax.Y);
  Result.Z := EnsureRange(AHistoryYCoCg.Z, BoxMin.Z, BoxMax.Z);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanWeightedBlendedOIT                                              }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanWeightedBlendedOIT.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FWidth := 0;
  FHeight := 0;
  FWeightScale := 1.0;
end;

destructor TCastleVulkanWeightedBlendedOIT.Destroy;
begin
  FreeAndNil(FOITAccumTexture);
  FreeAndNil(FOITRevealageTexture);
  inherited;
end;

procedure TCastleVulkanWeightedBlendedOIT.EnsureOITTargets(const AWidth, AHeight: Cardinal);
var
  TexDesc: TRHITextureDesc;
begin
  if (AWidth = 0) or (AHeight = 0) then
    Exit;
  if (FWidth = AWidth) and (FHeight = AHeight) and
     (FOITAccumTexture <> nil) and (FOITRevealageTexture <> nil) then
    Exit;

  FreeAndNil(FOITAccumTexture);
  FreeAndNil(FOITRevealageTexture);
  FWidth := AWidth;
  FHeight := AHeight;

  TexDesc := TRHITextureDesc.Create2D(FWidth, FHeight, pfRGBA16_Float,
    [tuColorAttachment, tuSampled], 1);
  TexDesc.DebugName := 'OITAccumulationTarget';
  FOITAccumTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc := TRHITextureDesc.Create2D(FWidth, FHeight, pfR16_Float,
    [tuColorAttachment, tuSampled], 1);
  TexDesc.DebugName := 'OITRevealageTarget';
  FOITRevealageTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

class function TCastleVulkanWeightedBlendedOIT.EvaluateOITDepthWeight(
  const ALinearZ, AAlpha, AWeightScale: Single): Single;
var
  A, Z, ZTerm: Single;
begin
  A := EnsureRange(AAlpha, 0.0, 1.0);
  Z := Abs(ALinearZ);
  ZTerm := 1.0 / (1.0 + Sqr(Z * 0.1) + Power(Z * 0.01, 4.0));
  Result := EnsureRange(3000.0 * Max(1e-3, A * Sqrt(A)) * ZTerm * Max(0.01, AWeightScale), 1e-2, 3000.0);
end;

class procedure TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(
  const APremulColorAndAlpha: TVector4; const ALinearZ, AWeightScale: Single;
  var AAccumRGBA: TVector4; var ARevealage: Single);
var
  Alpha, W: Single;
begin
  Alpha := EnsureRange(APremulColorAndAlpha.W, 0.0, 1.0);
  W := EvaluateOITDepthWeight(ALinearZ, Alpha, AWeightScale);
  AAccumRGBA.X := AAccumRGBA.X + APremulColorAndAlpha.X * W;
  AAccumRGBA.Y := AAccumRGBA.Y + APremulColorAndAlpha.Y * W;
  AAccumRGBA.Z := AAccumRGBA.Z + APremulColorAndAlpha.Z * W;
  AAccumRGBA.W := AAccumRGBA.W + Alpha * W;
  ARevealage := ARevealage * (1.0 - Alpha);
end;

class function TCastleVulkanWeightedBlendedOIT.EvaluateOITComposite(
  const AAccumRGBA: TVector4; const ARevealage: Single;
  const AOpaqueRGB: TVector3): TVector3;
var
  Rev, Denom: Single;
  AvgTransparent: TVector3;
begin
  Rev := EnsureRange(ARevealage, 0.0, 1.0);
  if Rev >= 0.9999 then
    Exit(AOpaqueRGB);
  Denom := Max(AAccumRGBA.W, 1e-5);
  AvgTransparent := Vector3(AAccumRGBA.X / Denom, AAccumRGBA.Y / Denom, AAccumRGBA.Z / Denom);
  Result := AvgTransparent * (1.0 - Rev) + AOpaqueRGB * Rev;
end;

{$endif read_implementation}
