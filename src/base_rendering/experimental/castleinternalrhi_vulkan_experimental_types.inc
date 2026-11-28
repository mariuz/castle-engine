{%MainUnit castleinternalrhi_vulkan_experimental.pas}
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
  { -------------------------------------------------------------------------- }
  { Phase 17.2: Localized Box-Projected Parallax Reflection Probes             }
  { -------------------------------------------------------------------------- }

  { Manages up to CASTLE_MAX_REFLECTION_PROBES (16) localized reflection probes with
    OBB/AABB box-projected parallax ray-box intersection and trilinear distance blending. }
  TCastleVulkanReflectionProbeManager = class
  private
    FDevice: TVulkanRHIDevice;
    FProbes: array[0 .. CASTLE_MAX_REFLECTION_PROBES - 1] of TCastleReflectionProbeEntry;
    FProbeCount: Cardinal;
    FProbeBuffer: TVulkanRHIBuffer;
    FTotalUploads: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure ClearProbes;
    function AddProbe(const AWorldPos, ABoxMin, ABoxMax: TVector3;
      const ARadius: Single; const AIntensity: Single = 1.0;
      const ABlendDistance: Single = 1.0; const ACubemapIndex: Cardinal = 0;
      const ABoxProjection: Boolean = True): Integer;
    function GetProbe(const AIndex: Integer): TCastleReflectionProbeEntry;
    procedure UploadProbes;

    { Evaluates the box-projected parallax reflection lookup direction from AWorldPos
      along AWorldReflectDir against the AABB [ABoxMin, ABoxMax] centered at AProbePos. }
    class function EvaluateBoxProjectedDirection(
      const AWorldPos, AWorldReflectDir, AProbePos, ABoxMin, ABoxMax: TVector3): TVector3; static;

    { Evaluates the smooth trilinear probe influence weight in [0..1] inside [ABoxMin, ABoxMax]
      with inner edge falloff ABlendDistance. }
    class function EvaluateProbeInfluenceWeight(
      const AWorldPos, ABoxMin, ABoxMax: TVector3;
      const ABlendDistance: Single): Single; static;

    property ProbeCount: Cardinal read FProbeCount;
    property ProbeBuffer: TVulkanRHIBuffer read FProbeBuffer;
    property TotalUploads: Cardinal read FTotalUploads;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 17.3: Oriented Bounding Box (OBB) Decal Projection                   }
  { -------------------------------------------------------------------------- }

  { Manages up to CASTLE_MAX_PROJECTED_DECALS (64) world-space OBB projected decals
    with depth-reconstructed local box UVs, normal angle rejection fade, and GPU buffer upload. }
  TCastleVulkanDecalManager = class
  private
    FDevice: TVulkanRHIDevice;
    FDecals: array[0 .. CASTLE_MAX_PROJECTED_DECALS - 1] of TCastleProjectedDecalEntry;
    FDecalCount: Cardinal;
    FDecalBuffer: TVulkanRHIBuffer;
    FTotalUploads: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure ClearDecals;
    function AddBoxDecal(const ACenter, AHalfExtents, AForwardNormal: TVector3;
      const AAlbedoTint: TVector3; const AOpacity, ARoughness: Single;
      const AUVScaleOffset: TVector4): Integer;
    function GetDecal(const AIndex: Integer): TCastleProjectedDecalEntry;
    procedure UploadDecals;

    { Projects AWorldPos into ADecal's local unit box [-0.5 .. +0.5]^3.
      Returns True if AWorldPos is inside the OBB and outputs ADecalUV in [0..1]^2. }
    class function ProjectWorldPointToDecalUV(const AWorldPos: TVector3;
      const ADecal: TCastleProjectedDecalEntry;
      out ADecalUV: TVector2; out ALocalPos: TVector3): Boolean; static;

    { Evaluates the combined surface-normal grazing-angle rejection and Z-box edge fade in [0..1]. }
    class function EvaluateDecalAngleAndBoxFade(
      const ALocalPos, ASurfaceNormal, ADecalForward: TVector3;
      const AAngleFadeCos: Single = 0.25): Single; static;

    property DecalCount: Cardinal read FDecalCount;
    property DecalBuffer: TVulkanRHIBuffer read FDecalBuffer;
    property TotalUploads: Cardinal read FTotalUploads;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 18.1: GPU Compute Particle Simulation & Indirect Billboard Rendering }
  { -------------------------------------------------------------------------- }

  { GPU-driven particle simulation subsystem managing the persistent SSBO particle pool,
    compacted alive index buffer, VkDrawIndirectCommand buffer, and compute pipeline. }
  TCastleVulkanComputeParticles = class
  private
    FDevice: TVulkanRHIDevice;
    FParticleBuffer: TVulkanRHIBuffer;
    FAliveIndexBuffer: TVulkanRHIBuffer;
    FIndirectDrawBuffer: TVulkanRHIBuffer;
    FSimulationPipeline: TRHIComputePipeline;
    FMaxParticles: Cardinal;
    FGravity: TVector3;
    FDrag: Single;
    FGroundPlaneY: Single;
    FRestitution: Single;
    FTotalSimulationDispatches: Cardinal;
    procedure EnsureSimulationPipeline;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure EnsureParticleBuffers(const AMaxParticles: Cardinal = CASTLE_DEFAULT_MAX_PARTICLES);
    function DispatchParticleSimulation(const ACmd: TRHICommandList;
      const ADeltaTime: Single): Cardinal;

    { Simulates one Euler integration step with drag, ground-plane bounce, and age decay.
      Returns True if the particle remains alive (Age < Lifetime). }
    class function SimulateParticleStep(var AParticle: TCastleGPUParticle;
      const AGravity: TVector3; const ADrag, AGroundY, ARestitution, ADeltaTime: Single): Boolean; static;

    property ParticleBuffer: TVulkanRHIBuffer read FParticleBuffer;
    property AliveIndexBuffer: TVulkanRHIBuffer read FAliveIndexBuffer;
    property IndirectDrawBuffer: TVulkanRHIBuffer read FIndirectDrawBuffer;
    property SimulationPipeline: TRHIComputePipeline read FSimulationPipeline;
    property MaxParticles: Cardinal read FMaxParticles;
    property Gravity: TVector3 read FGravity write FGravity;
    property Drag: Single read FDrag write FDrag;
    property GroundPlaneY: Single read FGroundPlaneY write FGroundPlaneY;
    property Restitution: Single read FRestitution write FRestitution;
    property TotalSimulationDispatches: Cardinal read FTotalSimulationDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 18.3: Screen-Space Raymarched Contact Shadows                        }
  { -------------------------------------------------------------------------- }

  { Screen-space depth raymarcher for fine contact shadows that complement CSM shadow maps. }
  TCastleVulkanContactShadows = class
  private
    FDevice: TVulkanRHIDevice;
    FContactShadowTexture: TVulkanRHITexture;
    FContactShadowPipeline: TRHIComputePipeline;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FLightDirView: TVector3;
    FRayLength: Single;
    FThickness: Single;
    FStepCount: Cardinal;
    FContrast: Single;
    FZNear: Single;
    FZFar: Single;
    FTotalContactShadowDispatches: Cardinal;
    procedure EnsureContactShadowPipeline;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure EnsureContactShadowTarget(const AWidth, AHeight: Cardinal);
    function DispatchContactShadows(const ACmd: TRHICommandList;
      const ADepthTexture: TRHITexture): Cardinal;

    { Traces a 1D depth ray across ASceneLinearDepths with thickness window AThickness.
      Returns True if an occlusion hit was detected, and outputs AVisibility in [0..1]. }
    class function EvaluateContactShadowRay1D(
      const ASceneLinearDepths: array of Single;
      const AStartLinearZ, ARayStepZ, AThickness: Single;
      out AVisibility: Single): Boolean; static;

    property ContactShadowTexture: TVulkanRHITexture read FContactShadowTexture;
    property ContactShadowPipeline: TRHIComputePipeline read FContactShadowPipeline;
    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property LightDirView: TVector3 read FLightDirView write FLightDirView;
    property RayLength: Single read FRayLength write FRayLength;
    property Thickness: Single read FThickness write FThickness;
    property StepCount: Cardinal read FStepCount write FStepCount;
    property Contrast: Single read FContrast write FContrast;
    property ZNear: Single read FZNear write FZNear;
    property ZFar: Single read FZFar write FZFar;
    property TotalContactShadowDispatches: Cardinal read FTotalContactShadowDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 19.1: Compute Shader Skeletal Skinning & Morph Target Blending       }
  { -------------------------------------------------------------------------- }

  { GPU compute skeletal skinning and morph target blending subsystem writing
    deformed vertices and previous-frame positions for TAA motion vectors. }
  TCastleVulkanComputeSkinner = class
  private
    FDevice: TVulkanRHIDevice;
    FSourceVertexBuffer: TVulkanRHIBuffer;
    FMorphDeltaBuffer: TVulkanRHIBuffer;
    FJointMatrixBuffer: TVulkanRHIBuffer;
    FSkinnedVertexBuffer: TVulkanRHIBuffer;
    FPreviousPositionBuffer: TVulkanRHIBuffer;
    FSkinningPipeline: TRHIComputePipeline;
    FMaxVertices: Cardinal;
    FMorphTargetCount: Cardinal;
    FMorphWeights: TVector4;
    FTotalSkinningDispatches: Cardinal;
    procedure EnsureSkinningPipeline;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure EnsureSkinningBuffers(
      const AMaxVertices: Cardinal = CASTLE_DEFAULT_MAX_SKINNED_VERTICES;
      const AMorphTargetCount: Cardinal = 4);
    function DispatchComputeSkinning(const ACmd: TRHICommandList;
      const AVertexCount: Cardinal; const AJointCount: Cardinal = 64;
      const AStorePreviousPos: Boolean = True): Cardinal;

    { CPU reference evaluation of morph target displacement + 4-bone Linear Blend Skinning (LBS). }
    class procedure EvaluateVertexSkinningAndMorph(
      const ASourceVertex: TCastleSkinningVertex;
      const AMorphDeltas: array of TCastleMorphTargetDelta;
      const AMorphWeights: TVector4;
      const AJointMatrices: array of TMatrix4;
      out ASkinnedPos, ASkinnedNormal: TVector3); static;

    property SourceVertexBuffer: TVulkanRHIBuffer read FSourceVertexBuffer;
    property MorphDeltaBuffer: TVulkanRHIBuffer read FMorphDeltaBuffer;
    property JointMatrixBuffer: TVulkanRHIBuffer read FJointMatrixBuffer;
    property SkinnedVertexBuffer: TVulkanRHIBuffer read FSkinnedVertexBuffer;
    property PreviousPositionBuffer: TVulkanRHIBuffer read FPreviousPositionBuffer;
    property SkinningPipeline: TRHIComputePipeline read FSkinningPipeline;
    property MaxVertices: Cardinal read FMaxVertices;
    property MorphTargetCount: Cardinal read FMorphTargetCount;
    property MorphWeights: TVector4 read FMorphWeights write FMorphWeights;
    property TotalSkinningDispatches: Cardinal read FTotalSkinningDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 19.2: GPU-Driven Continuous Distance-Dependent LOD (CDLOD) Terrain   }
  { -------------------------------------------------------------------------- }

  { Manages quadtree terrain CDLOD patch nodes, morph distance ranges, and GPU SSBO upload. }
  TCastleVulkanTerrainCDLOD = class
  private
    FDevice: TVulkanRHIDevice;
    FNodes: array[0 .. CASTLE_MAX_TERRAIN_CDLOD_NODES - 1] of TCastleTerrainCDLODNode;
    FNodeCount: Cardinal;
    FNodeBuffer: TVulkanRHIBuffer;
    FBaseLODDistance: Single;
    FMorphStartRatio: Single;
    FTotalNodeUploads: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure ClearNodes;
    function AddTerrainNode(const AWorldX, AWorldZ, APatchSize: Single;
      const ALODLevel: Cardinal; const AMinY, AMaxY: Single): Integer;
    function GetTerrainNode(const AIndex: Integer): TCastleTerrainCDLODNode;
    procedure UploadNodes;

    { Evaluates the continuous CDLOD morph factor k in [0..1] for ACameraDistance inside [ALODNearDist, ALODFarDist]. }
    class function EvaluateCDLODMorphFactor(
      const ACameraDistance, ALODNearDist, ALODFarDist, AMorphStartRatio: Single): Single; static;

    { Morphs a normalized patch grid UV [0..1]^2 smoothly toward the next coarser LOD grid when AMorphFactor -> 1. }
    class function MorphCDLODGridVertex(const AGridUV: TVector2;
      const APatchResolution, AMorphFactor: Single): TVector2; static;

    property NodeCount: Cardinal read FNodeCount;
    property NodeBuffer: TVulkanRHIBuffer read FNodeBuffer;
    property BaseLODDistance: Single read FBaseLODDistance write FBaseLODDistance;
    property MorphStartRatio: Single read FMorphStartRatio write FMorphStartRatio;
    property TotalNodeUploads: Cardinal read FTotalNodeUploads;
  end;

  { -------------------------------------------------------------------------- }
  { Rayleigh / Mie Physical Sky & Aerial Perspective LUT (Phase 20.2)          }
  { -------------------------------------------------------------------------- }

  { Manages the rgba16f Sky-View LUT texture, planetary Rayleigh/Mie atmospheric
    scattering parameters, and compute shader dispatch. }
  TCastleVulkanAtmosphereRenderer = class
  private
    FDevice: TVulkanRHIDevice;
    FSkyViewLUTTexture: TVulkanRHITexture;
    FSunDirection: TVector3;
    FSunIntensity: Single;
    FRayleighScattering: TVector3;
    FRayleighScaleHeight: Single;
    FMieScattering: TVector3;
    FMieScaleHeight: Single;
    FPlanetRadius: Single;
    FAtmosphereRadius: Single;
    FMieAnisotropyG: Single;
    FRaymarchSteps: Cardinal;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRGBA16_Float Sky-View LUT texture (default 192x108). }
    procedure EnsureSkyViewLUT(
      const AWidth: Cardinal = CASTLE_DEFAULT_SKY_VIEW_LUT_WIDTH;
      const AHeight: Cardinal = CASTLE_DEFAULT_SKY_VIEW_LUT_HEIGHT);

    { Evaluates CPU reference single-scattering planetary sky radiance along AViewDir. }
    function EvaluateSkyRayRadiance(const AViewDir, ASunDir: TVector3): TVector3;

    { Dispatches the Rayleigh/Mie Sky-View LUT compute pass. }
    procedure DispatchAtmosphereSky(
      const ACommandList: TVulkanRHICommandList;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil;
      const AWidth: Cardinal = CASTLE_DEFAULT_SKY_VIEW_LUT_WIDTH;
      const AHeight: Cardinal = CASTLE_DEFAULT_SKY_VIEW_LUT_HEIGHT);

    property SkyViewLUTTexture: TVulkanRHITexture read FSkyViewLUTTexture;
    property SunDirection: TVector3 read FSunDirection write FSunDirection;
    property SunIntensity: Single read FSunIntensity write FSunIntensity;
    property RayleighScattering: TVector3 read FRayleighScattering write FRayleighScattering;
    property RayleighScaleHeight: Single read FRayleighScaleHeight write FRayleighScaleHeight;
    property MieScattering: TVector3 read FMieScattering write FMieScattering;
    property MieScaleHeight: Single read FMieScaleHeight write FMieScaleHeight;
    property PlanetRadius: Single read FPlanetRadius write FPlanetRadius;
    property AtmosphereRadius: Single read FAtmosphereRadius write FAtmosphereRadius;
    property MieAnisotropyG: Single read FMieAnisotropyG write FMieAnisotropyG;
    property RaymarchSteps: Cardinal read FRaymarchSteps write FRaymarchSteps;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Compute Gerstner Wave Ocean Simulation & Foam (Phase 21.2)             }
  { -------------------------------------------------------------------------- }

  { Manages multi-octave directional Gerstner ocean wave displacement, analytical
    surface normals, Jacobian crest whitecap foam, and compute shader dispatch. }
  TCastleVulkanOceanSimulator = class
  private
    FDevice: TVulkanRHIDevice;
    FDisplacementAndFoamTexture: TVulkanRHITexture;
    FNormalAndSlopeTexture: TVulkanRHITexture;
    FWindDirection: TVector2;
    FWindSpeed: Single;
    FSimulationTime: Single;
    FBaseAmplitude: Single;
    FBaseWavelength: Single;
    FChoppiness: Single;
    FPatchWorldSize: Single;
    FOctaveCount: Cardinal;
    FFoamThreshold: Single;
    FGravity: Single;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRGBA16_Float displacement+foam and normal+slope textures (default 128x128). }
    procedure EnsureOceanTextures(const AGridSize: Cardinal = CASTLE_DEFAULT_OCEAN_GRID_SIZE);

    { Evaluates CPU reference multi-octave Gerstner wave 3D displacement, analytical normal, and Jacobian crest foam. }
    procedure EvaluateGerstnerWavePoint(const AWorldXZ: TVector2; const ATimeSeconds: Single;
      out ADisplacement, ANormal: TVector3; out AFoamFactor: Single);

    { Dispatches the GPU compute ocean displacement & normal/foam generation pass. }
    procedure DispatchOceanSimulation(
      const ACommandList: TVulkanRHICommandList;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil;
      const AGridSize: Cardinal = CASTLE_DEFAULT_OCEAN_GRID_SIZE);

    property DisplacementAndFoamTexture: TVulkanRHITexture read FDisplacementAndFoamTexture;
    property NormalAndSlopeTexture: TVulkanRHITexture read FNormalAndSlopeTexture;
    property WindDirection: TVector2 read FWindDirection write FWindDirection;
    property WindSpeed: Single read FWindSpeed write FWindSpeed;
    property SimulationTime: Single read FSimulationTime write FSimulationTime;
    property BaseAmplitude: Single read FBaseAmplitude write FBaseAmplitude;
    property BaseWavelength: Single read FBaseWavelength write FBaseWavelength;
    property Choppiness: Single read FChoppiness write FChoppiness;
    property PatchWorldSize: Single read FPatchWorldSize write FPatchWorldSize;
    property OctaveCount: Cardinal read FOctaveCount write FOctaveCount;
    property FoamThreshold: Single read FFoamThreshold write FFoamThreshold;
    property Gravity: Single read FGravity write FGravity;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Dynamic Diffuse Global Illumination (DDGI) Octahedral Probe Grid (22.1)    }
  { -------------------------------------------------------------------------- }

  { Manages a 3D world-space irradiance probe grid encoded in 2D octahedral
    irradiance (pfRGBA16_Float) and distance/variance (pfRG16_Float) atlases. }
  TCastleVulkanDDGIGrid = class
  private
    FDevice: TVulkanRHIDevice;
    FIrradianceAtlasTexture: TVulkanRHITexture;
    FVisibilityAtlasTexture: TVulkanRHITexture;
    FGridOrigin: TVector3;
    FGridSpacing: TVector3;
    FGridCountX: Cardinal;
    FGridCountY: Cardinal;
    FGridCountZ: Cardinal;
    FNormalBias: Single;
    FViewBias: Single;
    FHysteresis: Single;
    FUpdateCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the 2D octahedral irradiance and visibility probe atlases. }
    procedure EnsureProbeAtlases;

    { Returns the world-space position of probe (AProbeX, AProbeY, AProbeZ). }
    function GetProbeWorldPosition(const AProbeX, AProbeY, AProbeZ: Cardinal): TVector3;

    { Dispatches the DDGI probe irradiance & visibility atlas update compute pass. }
    procedure DispatchDDGIUpdate(
      const ACommandList: TVulkanRHICommandList;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property IrradianceAtlasTexture: TVulkanRHITexture read FIrradianceAtlasTexture;
    property VisibilityAtlasTexture: TVulkanRHITexture read FVisibilityAtlasTexture;
    property GridOrigin: TVector3 read FGridOrigin write FGridOrigin;
    property GridSpacing: TVector3 read FGridSpacing write FGridSpacing;
    property GridCountX: Cardinal read FGridCountX write FGridCountX;
    property GridCountY: Cardinal read FGridCountY write FGridCountY;
    property GridCountZ: Cardinal read FGridCountZ write FGridCountZ;
    property NormalBias: Single read FNormalBias write FNormalBias;
    property ViewBias: Single read FViewBias write FViewBias;
    property Hysteresis: Single read FHysteresis write FHysteresis;
    property UpdateCount: Cardinal read FUpdateCount;
  end;

  { -------------------------------------------------------------------------- }
  { Virtual Shadow Maps (VSM) Page Table & Physical Tile Pool (Phase 23.2)     }
  { -------------------------------------------------------------------------- }

  { Manages a 64x64 virtual shadow page table mapped on-demand into a 16x16
    (256-tile, 2048x2048) physical shadow depth tile pool. }
  TCastleVulkanVirtualShadowMap = class
  private
    FDevice: TVulkanRHIDevice;
    FPageTable: array[0 .. CASTLE_VSM_PAGE_TABLE_DIM * CASTLE_VSM_PAGE_TABLE_DIM - 1] of Cardinal;
    FPageTableBuffer: TVulkanRHIBuffer;
    FPhysicalTilePoolTexture: TVulkanRHITexture;
    FAllocatedTileCount: Cardinal;
    FTotalPageUploads: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all virtual page table entries and resets the physical tile bump allocator. }
    procedure ResetPageTable;

    { Allocates the 2048x2048 physical shadow tile pool texture and page table SSBO. }
    procedure EnsureResources;

    { Requests virtual page (APageX, APageY), allocating a physical 128x128 tile if not yet resident. }
    function RequestAndAllocateVirtualPage(const APageX, APageY: Cardinal;
      out APhysicalTileX, APhysicalTileY: Cardinal): Boolean;

    { Returns the packed 32-bit page table entry at (APageX, APageY). }
    function GetPageEntry(const APageX, APageY: Cardinal): Cardinal;

    { Translates a virtual shadow UV in [0..1]^2 into physical tile pool UV if the virtual page is resident. }
    function ComputePhysicalAtlasUV(const AVirtualUV: TVector2;
      out APageX, APageY: Cardinal; out APhysicalUV: TVector2): Boolean;

    { Uploads the 64x64 page table into PageTableBuffer. }
    procedure UploadPageTable;

    property PageTableBuffer: TVulkanRHIBuffer read FPageTableBuffer;
    property PhysicalTilePoolTexture: TVulkanRHITexture read FPhysicalTilePoolTexture;
    property AllocatedTileCount: Cardinal read FAllocatedTileCount;
    property TotalPageUploads: Cardinal read FTotalPageUploads;
  end;

  { -------------------------------------------------------------------------- }
  { GPU-Driven Continuous Instance LOD Selector (Phase 24.1)                   }
  { -------------------------------------------------------------------------- }

  { Evaluates projected vertical screen-height coverage and selects discrete LOD
    levels (LOD0..LOD3 or -1 culled) + continuous crossfade weights per instance. }
  TCastleVulkanLODSelector = class
  private
    FDevice: TVulkanRHIDevice;
    FInstances: array of TCastleLODInstanceDescriptor;
    FInstanceCount: Cardinal;
    FInstanceBuffer: TVulkanRHIBuffer;
    FSelectedLODBuffer: TVulkanRHIBuffer;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered instances. }
    procedure ClearInstances;

    { Registers an instance bounding sphere and 4-level screen coverage thresholds. }
    function AddInstance(
      const ASphereCenter: TVector3;
      const ARadius: Single;
      const AThresholds: TVector4;
      const AMeshID: Cardinal = 0;
      const ATransitionBand: Single = 0.02): Integer;

    { Uploads the registered instance array into GPU SSBOs. }
    procedure UploadInstances;

    { Evaluates on CPU how many instances select LOD0..LOD3 vs culled, returning total visible instances. }
    function EvaluateInstanceLODsCPU(
      const ACameraPosition: TVector3;
      const ACotHalfFovY: Single;
      out ALOD0Count, ALOD1Count, ALOD2Count, ALOD3Count, ACulledCount: Cardinal): Cardinal;

    { Dispatches the GPU compute LOD selection pass. }
    procedure DispatchLODSelection(
      const ACommandList: TVulkanRHICommandList;
      const ACameraPosition: TVector3;
      const ACotHalfFovY: Single;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property InstanceCount: Cardinal read FInstanceCount;
    property InstanceBuffer: TVulkanRHIBuffer read FInstanceBuffer;
    property SelectedLODBuffer: TVulkanRHIBuffer read FSelectedLODBuffer;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Texture Streaming Mipmap Residency & Feedback Analyzer (Phase 25.2)    }
  { -------------------------------------------------------------------------- }

  TCastleStreamedTextureEntry = record
    Width: Cardinal;
    Height: Cardinal;
    MipLevels: Cardinal;
    ResidentMip: Cardinal;
    RequestedMip: Cardinal;
  end;

  { Tracks per-texture desired mip levels from GPU derivative feedback and resolves
    high-resolution mip promotions and unreferenced mip evictions. }
  TCastleVulkanTextureStreamer = class
  private
    FDevice: TVulkanRHIDevice;
    FEntries: array[0 .. CASTLE_MAX_STREAMED_TEXTURES - 1] of TCastleStreamedTextureEntry;
    FTextureCount: Cardinal;
    FFeedbackBuffer: TVulkanRHIBuffer;
    FUpdateCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered streamable textures. }
    procedure ClearTextures;

    { Registers a streamable texture and its current coarsest resident mip level. }
    function RegisterStreamableTexture(
      const AWidth, AHeight, AMipLevels, AInitialResidentMip: Cardinal): Integer;

    { Resets per-frame requested mip feedback slots to $FF (unreferenced). }
    procedure ResetFrameFeedback;

    { Records a pixel's requested mip level for ATextureIndex (atomic min semantics). }
    procedure RecordMipFeedback(const ATextureIndex, ARequestedMip: Cardinal);

    { Returns the current resident mip level for ATextureIndex. }
    function GetResidentMip(const ATextureIndex: Cardinal): Cardinal;

    { Resolves pending mip promotions (RequestedMip < ResidentMip) and evictions
      (unreferenced textures demoted by 1 mip toward MipLevels - 1), returning total transitions. }
    function ResolveStreamingRequests(
      out APromotedCount, AEvictedCount: Cardinal): Cardinal;

    { Uploads the per-texture requested mip array into FeedbackBuffer. }
    procedure UploadFeedbackBuffer;

    property TextureCount: Cardinal read FTextureCount;
    property FeedbackBuffer: TVulkanRHIBuffer read FFeedbackBuffer;
    property UpdateCount: Cardinal read FUpdateCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Shadow Caster Light-Ray Extrusion Culler (Phase 26.3)                  }
  { -------------------------------------------------------------------------- }

  { Culls shadow-casting instances whose bounding sphere swept along the light
    ray direction does not intersect the camera receiver frustum AABB. }
  TCastleVulkanShadowCasterCuller = class
  private
    FDevice: TVulkanRHIDevice;
    FCasters: array of TVector4;
    FCasterCount: Cardinal;
    FCasterBuffer: TVulkanRHIBuffer;
    FVisibleCasterBuffer: TVulkanRHIBuffer;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered shadow-caster bounding spheres. }
    procedure ClearCasters;

    { Registers a shadow-caster bounding sphere (world center + radius). }
    function AddCaster(const ASphereCenter: TVector3; const ASphereRadius: Single): Integer;

    { Uploads the registered shadow-caster spheres into GPU SSBOs. }
    procedure UploadCasters;

    { Evaluates on CPU how many shadow casters can cast shadows into [AReceiverBoxMin, AReceiverBoxMax]. }
    function EvaluateActiveShadowCastersCPU(
      const ALightRayDir: TVector3;
      const AMaxExtrusionDist: Single;
      const AReceiverBoxMin, AReceiverBoxMax: TVector3): Cardinal;

    { Dispatches the GPU compute shadow-caster extrusion culling pass. }
    procedure DispatchShadowCasterCulling(
      const ACommandList: TVulkanRHICommandList;
      const ALightRayDir: TVector3;
      const AMaxExtrusionDist: Single;
      const AReceiverBoxMin, AReceiverBoxMax: TVector3;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property CasterCount: Cardinal read FCasterCount;
    property CasterBuffer: TVulkanRHIBuffer read FCasterBuffer;
    property VisibleCasterBuffer: TVulkanRHIBuffer read FVisibleCasterBuffer;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Nanite-Style Hierarchical Cluster DAG Cut Selector (Phase 27.2)            }
  { -------------------------------------------------------------------------- }

  { Evaluates monotonic parent/child screen-space simplification errors across a
    cluster DAG and selects the crack-free LOD cut where
    ParentProjectedErrorPx > PixelErrorThreshold >= SelfProjectedErrorPx. }
  TCastleVulkanClusterDAG = class
  private
    FDevice: TVulkanRHIDevice;
    FNodes: array of TCastleClusterDAGNode;
    FNodeCount: Cardinal;
    FDAGNodeBuffer: TVulkanRHIBuffer;
    FSelectedCutBuffer: TVulkanRHIBuffer;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered cluster DAG nodes. }
    procedure ClearNodes;

    { Registers a cluster DAG node with its bounding sphere, self world error, and parent world error. }
    function AddClusterNode(
      const ASphereCenter: TVector3;
      const ASphereRadius, ASelfWorldError, AParentWorldError: Single;
      const AVertexOffset: Cardinal = 0;
      const ATriangleOffset: Cardinal = 0;
      const ATriangleCount: Cardinal = 124): Integer;

    { Uploads the registered cluster DAG nodes into GPU SSBOs. }
    procedure UploadNodes;

    { Evaluates on CPU how many cluster DAG nodes lie on the active crack-free cut. }
    function EvaluateDAGCutCPU(
      const ACameraPosition: TVector3;
      const ACotHalfFovY, AViewportHeight, APixelErrorThreshold: Single): Cardinal;

    { Dispatches the GPU compute cluster DAG cut selection pass. }
    procedure DispatchDAGCutSelection(
      const ACommandList: TVulkanRHICommandList;
      const ACameraPosition: TVector3;
      const ACotHalfFovY, AViewportHeight, APixelErrorThreshold: Single;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property NodeCount: Cardinal read FNodeCount;
    property DAGNodeBuffer: TVulkanRHIBuffer read FDAGNodeBuffer;
    property SelectedCutBuffer: TVulkanRHIBuffer read FSelectedCutBuffer;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Lumen-Style 3D Clipmap Global Signed Distance Field (Phase 28.1)           }
  { -------------------------------------------------------------------------- }

  TCastleSDFBoxPrimitive = record
    Center: TVector3;
    HalfExtents: TVector3;
  end;

  { Maintains a 3D Global Signed Distance Field (SDF) clipmap texture and scene
    box SDF primitives for hardware-ray-tracing-free sphere marching and sky/soft-shadow cones. }
  TCastleVulkanGlobalSDF = class
  private
    FDevice: TVulkanRHIDevice;
    FPrimitives: array of TCastleSDFBoxPrimitive;
    FPrimitiveCount: Cardinal;
    FGridResolution: Cardinal;
    FClipmapHalfExtent: Single;
    FSmoothBlendRadius: Single;
    FClipmapVolumeTexture: TVulkanRHITexture;
    FBuildCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered SDF box primitives. }
    procedure ClearPrimitives;

    { Registers an axis-aligned box SDF primitive into the global distance field. }
    function AddBoxPrimitive(const ABoxCenter, ABoxHalfExtents: TVector3): Integer;

    { Allocates the 3D (td3D, pfR16_Float) Global SDF Clipmap volume texture. }
    procedure EnsureVolumeResources(const AGridResolution: Cardinal = 32);

    { Evaluates the smooth-unioned signed distance at AWorldPos across all registered primitives. }
    function EvaluateGlobalSDFDistanceCPU(const AWorldPos: TVector3): Single;

    { Sphere-marches a ray [ARayOrigin, ARayDir] up to AMaxDistance against the Global SDF. }
    function TraceSphereMarchCPU(
      const ARayOrigin, ARayDir: TVector3;
      const AMaxDistance: Single;
      out AHitDistance: Single;
      out AHitSteps: Cardinal;
      const AMaxSteps: Cardinal = 64;
      const AHitEpsilon: Single = 0.01): Boolean;

    { Records a Global SDF clipmap build/update dispatch. }
    procedure DispatchGlobalSDFBuild(
      const ACommandList: TVulkanRHICommandList;
      const AGridResolution: Cardinal = 32);

    property PrimitiveCount: Cardinal read FPrimitiveCount;
    property GridResolution: Cardinal read FGridResolution;
    property ClipmapHalfExtent: Single read FClipmapHalfExtent write FClipmapHalfExtent;
    property SmoothBlendRadius: Single read FSmoothBlendRadius write FSmoothBlendRadius;
    property ClipmapVolumeTexture: TVulkanRHITexture read FClipmapVolumeTexture;
    property BuildCount: Cardinal read FBuildCount;
  end;

  { -------------------------------------------------------------------------- }
  { Lumen-Style 6-Axis Surface Cache Card Atlas (Phase 28.2)                   }
  { -------------------------------------------------------------------------- }

  { Manages a 2D Surface Cache Card Atlas (Albedo + Direct/Indirect Radiance)
    storing 6-axis (+X, -X, +Y, -Y, +Z, -Z) orthographic surface cards per mesh. }
  TCastleVulkanSurfaceCache = class
  private
    FDevice: TVulkanRHIDevice;
    FAtlasResolution: Cardinal;
    FTileResolution: Cardinal;
    FTilesPerRow: Cardinal;
    FMaxCardSlots: Cardinal;
    FAllocatedCardCount: Cardinal;
    FAlbedoAtlasTexture: TVulkanRHITexture;
    FDirectLightingAtlasTexture: TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Resets all allocated surface cache card slots. }
    procedure ResetCards;

    { Allocates 6 contiguous card slots (+X, -X, +Y, -Y, +Z, -Z) for a mesh instance. }
    function AllocateSixAxisCards(out AFirstCardSlot: Cardinal): Boolean;

    { Computes the normalized [0..1] atlas UV offset and scale for ACardSlot. }
    procedure GetCardAtlasOffsetAndScale(
      const ACardSlot: Cardinal;
      out AOffsetUV, AScaleUV: TVector2);

    { Allocates the Albedo and DirectLighting 2D Surface Cache Atlas textures. }
    procedure EnsureAtlasTextures;

    property AtlasResolution: Cardinal read FAtlasResolution;
    property TileResolution: Cardinal read FTileResolution;
    property MaxCardSlots: Cardinal read FMaxCardSlots;
    property AllocatedCardCount: Cardinal read FAllocatedCardCount;
    property AlbedoAtlasTexture: TVulkanRHITexture read FAlbedoAtlasTexture;
    property DirectLightingAtlasTexture: TVulkanRHITexture read FDirectLightingAtlasTexture;
  end;

  { -------------------------------------------------------------------------- }
  { ReSTIR DI/GI Spatio-Temporal Reservoir Resampler (Phase 29.2)              }
  { -------------------------------------------------------------------------- }

  { Manages screen-space current and temporal-history ReSTIR reservoir SSBOs
    and dispatches spatio-temporal reservoir resampling (UE5 MegaLights architecture). }
  TCastleVulkanReSTIR = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FMaxHistoryM: Cardinal;
    FCurrentReservoirBuffer: TVulkanRHIBuffer;
    FTemporalHistoryReservoirBuffer: TVulkanRHIBuffer;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates ping-pong Current and TemporalHistory ReSTIR reservoir SSBOs for AWidth x AHeight. }
    procedure EnsureReservoirBuffers(const AWidth, AHeight: Cardinal);

    { Swaps Current and TemporalHistory reservoir buffers at the end of a frame. }
    procedure SwapReservoirHistory;

    { Dispatches the ReSTIR spatio-temporal reservoir resampling compute pass. }
    procedure DispatchSpatioTemporalResampling(
      const ACommandList: TVulkanRHICommandList;
      const AWidth, AHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property MaxHistoryM: Cardinal read FMaxHistoryM write FMaxHistoryM;
    property CurrentReservoirBuffer: TVulkanRHIBuffer read FCurrentReservoirBuffer;
    property TemporalHistoryReservoirBuffer: TVulkanRHIBuffer read FTemporalHistoryReservoirBuffer;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Temporal Super Resolution (TSR) History Upscaler (Phase 30.1)              }
  { -------------------------------------------------------------------------- }

  { Manages lower-resolution input render scaling (e.g. 67% Quality mode) and
    full-resolution ping-pong history/upscaled HDR color textures for UE5-style
    Temporal Super Resolution (TSR). }
  TCastleVulkanTSRUpscaler = class
  private
    FDevice: TVulkanRHIDevice;
    FRenderScale: Single;
    FOutputWidth: Cardinal;
    FOutputHeight: Cardinal;
    FUpscaledColorTexture: TVulkanRHITexture;
    FHistoryColorTexture: TVulkanRHITexture;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Computes the internal lower-resolution input dimensions for a target display resolution. }
    procedure ComputeInputResolution(
      const AOutputWidth, AOutputHeight: Cardinal;
      out AInputWidth, AInputHeight: Cardinal);

    { Allocates full-resolution Upscaled and History RGBA16F textures for AOutputWidth x AOutputHeight. }
    procedure EnsureUpscaleTargets(const AOutputWidth, AOutputHeight: Cardinal);

    { Swaps Upscaled and History textures at the end of a frame. }
    procedure SwapHistoryTargets;

    { Dispatches the TSR compute upscaling pass. }
    procedure DispatchTSRUpscale(
      const ACommandList: TVulkanRHICommandList;
      const AOutputWidth, AOutputHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property RenderScale: Single read FRenderScale write FRenderScale;
    property OutputWidth: Cardinal read FOutputWidth;
    property OutputHeight: Cardinal read FOutputHeight;
    property UpscaledColorTexture: TVulkanRHITexture read FUpscaledColorTexture;
    property HistoryColorTexture: TVulkanRHITexture read FHistoryColorTexture;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Tile-Based Variable Rate Shading (VRS) Manager (Phase 32.2)                }
  { -------------------------------------------------------------------------- }

  { Generates and manages screen-space 16x16 tile shading rate images
    (1x1, 2x1, 1x2, 2x2, 4x4) for VK_KHR_fragment_shading_rate. }
  TCastleVulkanVRSManager = class
  private
    FDevice: TVulkanRHIDevice;
    FTileSize: Cardinal;
    FTileGridWidth: Cardinal;
    FTileGridHeight: Cardinal;
    FShadingRateImage: TVulkanRHITexture;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates the 2D Shading Rate Image (1 texel per 16x16 screen pixel tile). }
    procedure EnsureShadingRateImage(const AViewportWidth, AViewportHeight: Cardinal);

    { Dispatches the luminance-contrast and velocity VRS tile classifier compute pass. }
    procedure DispatchVRSImageGeneration(
      const ACommandList: TVulkanRHICommandList;
      const AViewportWidth, AViewportHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property TileSize: Cardinal read FTileSize write FTileSize;
    property TileGridWidth: Cardinal read FTileGridWidth;
    property TileGridHeight: Cardinal read FTileGridHeight;
    property ShadingRateImage: TVulkanRHITexture read FShadingRateImage;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Runtime Virtual Texturing (RVT) Page Table & Physical Cache (Phase 32.3)   }
  { -------------------------------------------------------------------------- }

  { Manages a 64x64 virtual terrain/decal page table backed by a 16x16 physical
    material tile cache (Albedo + NormalRoughness) for single-lookup landscape shading. }
  TCastleVulkanRuntimeVirtualTexture = class
  private
    FDevice: TVulkanRHIDevice;
    FPageTable: array[0..63, 0..63] of Integer;
    FPhysicalTilesPerRow: Cardinal;
    FPhysicalTileResolution: Cardinal;
    FMaxPhysicalTiles: Cardinal;
    FAllocatedTileCount: Cardinal;
    FPhysicalAlbedoAtlas: TVulkanRHITexture;
    FPhysicalNormalRoughnessAtlas: TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all virtual-to-physical page mappings. }
    procedure ClearPages;

    { Requests or returns an allocated physical tile (X, Y) for virtual page (AVirtualPageX, AVirtualPageY). }
    function RequestRVTPage(
      const AVirtualPageX, AVirtualPageY: Cardinal;
      out APhysicalTileX, APhysicalTileY: Cardinal): Boolean;

    { Allocates the Physical Albedo and NormalRoughness RVT atlas textures. }
    procedure EnsurePhysicalAtlasTextures;

    property PhysicalTilesPerRow: Cardinal read FPhysicalTilesPerRow;
    property PhysicalTileResolution: Cardinal read FPhysicalTileResolution;
    property MaxPhysicalTiles: Cardinal read FMaxPhysicalTiles;
    property AllocatedTileCount: Cardinal read FAllocatedTileCount;
    property PhysicalAlbedoAtlas: TVulkanRHITexture read FPhysicalAlbedoAtlas;
    property PhysicalNormalRoughnessAtlas: TVulkanRHITexture read FPhysicalNormalRoughnessAtlas;
  end;

  { -------------------------------------------------------------------------- }
  { Sparse Brick-Atlas Heterogeneous Volumes (Phase 33.2)                      }
  { -------------------------------------------------------------------------- }

  { Manages a 16x16x16 sparse 3D indirection grid mapping active smoke/fire/explosion
    volume bricks into a physical 3D voxel brick pool (8x8x8 voxels per brick). }
  TCastleVulkanSparseVolumeAtlas = class
  private
    FDevice: TVulkanRHIDevice;
    FIndirectionGrid: array[0..15, 0..15, 0..15] of Integer;
    FBrickResolution: Cardinal;
    FBricksPerAxis: Cardinal;
    FMaxPhysicalBricks: Cardinal;
    FAllocatedBrickCount: Cardinal;
    FPhysicalBrickAtlasTexture: TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all sparse volume brick allocations. }
    procedure ClearBricks;

    { Allocates or returns the physical brick index for virtual volume coordinate (X, Y, Z). }
    function AllocateVolumeBrick(
      const AVirtualBrickX, AVirtualBrickY, AVirtualBrickZ: Cardinal;
      out APhysicalBrickIndex: Cardinal): Boolean;

    { Allocates the 3D rgba16f Physical Brick Pool texture (BricksPerAxis * BrickResolution)^3. }
    procedure EnsureVolumeAtlasTextures;

    property BrickResolution: Cardinal read FBrickResolution;
    property BricksPerAxis: Cardinal read FBricksPerAxis;
    property MaxPhysicalBricks: Cardinal read FMaxPhysicalBricks;
    property AllocatedBrickCount: Cardinal read FAllocatedBrickCount;
    property PhysicalBrickAtlasTexture: TVulkanRHITexture read FPhysicalBrickAtlasTexture;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Breadcrumb Marker Buffer & VK_ERROR_device_lost Diagnostics (Phase 33.3) }
  { -------------------------------------------------------------------------- }

  TCastleBreadcrumbState = (bsPending, bsActive, bsCompleted);

  TCastleBreadcrumbEntry = record
    MarkerID: Cardinal;
    ScopeName: String;
    State: TCastleBreadcrumbState;
  end;

  { Tracks fine-grained command-buffer pass/draw breadcrumb markers in a host-coherent
    buffer so GPU hangs and VK_ERROR_device_lost TDR faults pinpoint the exact offending pass. }
  TCastleVulkanBreadcrumbTracker = class
  private
    FDevice: TVulkanRHIDevice;
    FEntries: array of TCastleBreadcrumbEntry;
    FBreadcrumbBuffer: TVulkanRHIBuffer;
    function GetTotalScopesRecorded: Cardinal;
    function GetActiveScopeCount: Cardinal;
    function GetCompletedScopeCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Resets recorded breadcrumb scopes at the start of a frame. }
    procedure ResetBreadcrumbs;

    { Allocates the host-coherent GPU breadcrumb marker buffer. }
    procedure EnsureBreadcrumbBuffer;

    { Marks the beginning of a GPU pass/draw scope and returns its 1-based MarkerID. }
    function BeginBreadcrumbScope(
      const ACommandList: TVulkanRHICommandList;
      const AScopeName: String): Cardinal;

    { Marks the completion of a GPU pass/draw scope identified by AMarkerID. }
    procedure EndBreadcrumbScope(
      const ACommandList: TVulkanRHICommandList;
      const AMarkerID: Cardinal);

    { Formats a human-readable post-mortem crash report listing Completed vs. Active (in-flight/hung) GPU passes. }
    function FormatBreadcrumbCrashReport: String;

    property BreadcrumbBuffer: TVulkanRHIBuffer read FBreadcrumbBuffer;
    property TotalScopesRecorded: Cardinal read GetTotalScopesRecorded;
    property ActiveScopeCount: Cardinal read GetActiveScopeCount;
    property CompletedScopeCount: Cardinal read GetCompletedScopeCount;
  end;

  { -------------------------------------------------------------------------- }
  { Spatio-Temporal Variance-Guided Filtering (SVGF) Denoiser (Phase 34.3)     }
  { -------------------------------------------------------------------------- }

  { Orchestrates SVGF temporal moment accumulation and multi-pass A-Trous wavelet
    spatial filtering (step sizes 1, 2, 4, 8, 16) for ray-traced / ReSTIR / Lumen signals. }
  TCastleVulkanSVGFDenoiser = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FAttrousIterations: Cardinal;
    FMomentsHistoryTexture: TVulkanRHITexture;
    FFilteredPingTexture: TVulkanRHITexture;
    FFilteredPongTexture: TVulkanRHITexture;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates the rg16f MomentsHistory texture and rgba16f Ping/Pong A-Trous filter targets. }
    procedure EnsureSVGFTargets(const AWidth, AHeight: Cardinal);

    { Returns the A-Trous wavelet step size 2^AIterationIndex (1, 2, 4, 8, 16). }
    class function GetAttrousStepSize(const AIterationIndex: Cardinal): Cardinal; static;

    { Dispatches the temporal accumulation + multi-pass A-Trous wavelet spatial denoiser. }
    procedure DispatchSVGFDenoise(
      const ACommandList: TVulkanRHICommandList;
      const AWidth, AHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property AttrousIterations: Cardinal read FAttrousIterations write FAttrousIterations;
    property MomentsHistoryTexture: TVulkanRHITexture read FMomentsHistoryTexture;
    property FilteredPingTexture: TVulkanRHITexture read FFilteredPingTexture;
    property FilteredPongTexture: TVulkanRHITexture read FFilteredPongTexture;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU-Driven XPBD Cloth / Hair Strand Physics Simulator (Phase 36.3)         }
  { -------------------------------------------------------------------------- }

  { Manages GPU Extended Position-Based Dynamics (XPBD) particle and distance-constraint
    SSBOs and sub-stepped compute solver dispatches for cloth, foliage, and hair strands. }
  TCastleVulkanXPBDSimulator = class
  private
    FDevice: TVulkanRHIDevice;
    FParticleCount: Cardinal;
    FConstraintCount: Cardinal;
    FSubstepCount: Cardinal;
    FParticlePositionBuffer: TVulkanRHIBuffer;
    FPreviousPositionBuffer: TVulkanRHIBuffer;
    FConstraintBuffer: TVulkanRHIBuffer;
    FTotalSubstepsDispatched: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates the GPU particle position, previous-position, and constraint SSBOs. }
    procedure EnsureSimulationBuffers(
      const AParticleCount, AConstraintCount: Cardinal);

    { Dispatches FSubstepCount XPBD solver substeps on the GPU. }
    procedure DispatchXPBDSubsteps(
      const ACommandList: TVulkanRHICommandList;
      const AParticleCount, AConstraintCount: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property ParticleCount: Cardinal read FParticleCount;
    property ConstraintCount: Cardinal read FConstraintCount;
    property SubstepCount: Cardinal read FSubstepCount write FSubstepCount;
    property ParticlePositionBuffer: TVulkanRHIBuffer read FParticlePositionBuffer;
    property PreviousPositionBuffer: TVulkanRHIBuffer read FPreviousPositionBuffer;
    property ConstraintBuffer: TVulkanRHIBuffer read FConstraintBuffer;
    property TotalSubstepsDispatched: Cardinal read FTotalSubstepsDispatched;
  end;

  { -------------------------------------------------------------------------- }
  { Single-Pass Stereo VR (VK_KHR_multiview) & Foveated VRS Manager (Phase 37) }
  { -------------------------------------------------------------------------- }

  { Manages Single-Pass Stereo (VK_KHR_multiview, ViewMask = $3) 2-layer stereo
    color/depth array targets, IPD eye separation, and gaze-tracked radial foveated VRS. }
  TCastleVulkanMultiviewStereoManager = class
  private
    FDevice: TVulkanRHIDevice;
    FEyeWidth: Cardinal;
    FEyeHeight: Cardinal;
    FViewMask: Cardinal;
    FIPDMeters: Single;
    FLeftEyeGazeUV: TVector2;
    FRightEyeGazeUV: TVector2;
    FStereoColorArrayTexture: TVulkanRHITexture;
    FStereoDepthArrayTexture: TVulkanRHITexture;
    FStereoPassCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates 2-layer stereo color (rgba16f) and depth (d32f) array textures for left/right eye views. }
    procedure EnsureStereoTargets(const AEyeWidth, AEyeHeight: Cardinal);

    { Begins a single-pass stereo multiview render pass (ViewMask = $3 for left+right eyes). }
    procedure BeginStereoMultiviewPass(
      const ACommandList: TVulkanRHICommandList;
      const AEyeWidth, AEyeHeight: Cardinal);

    { Ends the single-pass stereo multiview render pass. }
    procedure EndStereoMultiviewPass(const ACommandList: TVulkanRHICommandList);

    property EyeWidth: Cardinal read FEyeWidth;
    property EyeHeight: Cardinal read FEyeHeight;
    property ViewMask: Cardinal read FViewMask write FViewMask;
    property IPDMeters: Single read FIPDMeters write FIPDMeters;
    property LeftEyeGazeUV: TVector2 read FLeftEyeGazeUV write FLeftEyeGazeUV;
    property RightEyeGazeUV: TVector2 read FRightEyeGazeUV write FRightEyeGazeUV;
    property StereoColorArrayTexture: TVulkanRHITexture read FStereoColorArrayTexture;
    property StereoDepthArrayTexture: TVulkanRHITexture read FStereoDepthArrayTexture;
    property StereoPassCount: Cardinal read FStereoPassCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Per-Instance Custom Float4 Payload Manager (Phase 38.3)                }
  { -------------------------------------------------------------------------- }

  { Manages a GPU Storage Buffer (SSBO) storing arbitrary per-instance TVector4
    custom attributes (e.g. wind phase, team tint, dissolve/damage factor) indexed via gl_InstanceIndex. }
  TCastleVulkanPerInstanceCustomData = class
  private
    FDevice: TVulkanRHIDevice;
    FCustomDataEntries: array of TVector4;
    FInstanceCustomDataBuffer: TVulkanRHIBuffer;
    FUploadCount: Cardinal;
    function GetInstanceCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all per-instance custom float4 payloads. }
    procedure ClearInstanceCustomData;

    { Sets the custom float4 payload for AInstanceIndex, growing the backing array as needed. }
    procedure SetInstanceCustomData(
      const AInstanceIndex: Cardinal;
      const ACustomPayload: TVector4);

    { Returns the custom float4 payload for AInstanceIndex (or Zero if out of range). }
    function GetInstanceCustomData(const AInstanceIndex: Cardinal): TVector4;

    { Allocates/updates the GPU SSBO containing all per-instance custom float4 payloads. }
    procedure UploadCustomDataBuffer;

    property InstanceCount: Cardinal read GetInstanceCount;
    property InstanceCustomDataBuffer: TVulkanRHIBuffer read FInstanceCustomDataBuffer;
    property UploadCount: Cardinal read FUploadCount;
  end;

  { -------------------------------------------------------------------------- }
  { Neural Radiance Cache & Cooperative Matrix MLP Denoiser (Phase 39.3)       }
  { -------------------------------------------------------------------------- }

  { Manages GPU MLP network weight SSBOs and compute inference dispatches for
    neural radiance caching and ray-reconstruction denoising. }
  TCastleVulkanNeuralDenoiser = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FHiddenUnits: Cardinal;
    FMLPWeightsBuffer: TVulkanRHIBuffer;
    FDenoisedOutputTexture: TVulkanRHITexture;
    FInferenceDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Evaluates a 4-input linear layer with ReLU activation: max(0.0, dot(input, weights) + bias). }
    class function EvaluateLinearReLU4(
      const AInput, AWeights: TVector4;
      const ABias: Single): Single; static;

    { Allocates the MLP network weights SSBO and the rgba16f denoised output texture. }
    procedure EnsureNeuralResources(const AWidth, AHeight: Cardinal);

    { Dispatches the neural MLP inference compute pass over (AWidth x AHeight) tiles. }
    procedure DispatchNeuralInference(
      const ACommandList: TVulkanRHICommandList;
      const AWidth, AHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property HiddenUnits: Cardinal read FHiddenUnits write FHiddenUnits;
    property MLPWeightsBuffer: TVulkanRHIBuffer read FMLPWeightsBuffer;
    property DenoisedOutputTexture: TVulkanRHITexture read FDenoisedOutputTexture;
    property InferenceDispatchCount: Cardinal read FInferenceDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Programmable MSAA Sample Locations Manager (Phase 40.3)                    }
  { -------------------------------------------------------------------------- }

  { Manages custom sub-pixel MSAA sample locations (VK_EXT_sample_locations)
    such as 4x Rotated Grid Super-Sampling (RGSS) and 2x/8x Halton patterns. }
  TCastleVulkanProgrammableSampleLocations = class
  private
    FDevice: TVulkanRHIDevice;
    FSampleLocations: array of TVector2;
    FLocationsAppliedCount: Cardinal;
    function GetSampleCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Configures standard Rotated Grid (RGSS 4x) or diagonal (2x) sub-pixel sample locations in [0..1)^2. }
    procedure ConfigureRotatedGridPattern(const ASampleCount: Cardinal = 4);

    { Returns the sub-pixel sample location [0..1)^2 for ASampleIndex. }
    function GetSampleLocation(const ASampleIndex: Cardinal): TVector2;

    { Applies the configured programmable MSAA sample locations on ACommandList (vkCmdSetSampleLocationsEXT). }
    procedure ApplySampleLocations(const ACommandList: TVulkanRHICommandList);

    property SampleCount: Cardinal read GetSampleCount;
    property LocationsAppliedCount: Cardinal read FLocationsAppliedCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Parallel Prefix-Sum & Stream Compactor (Phase 41.3)                    }
  { -------------------------------------------------------------------------- }

  { Manages GPU parallel prefix-sum (Blelloch exclusive scan) and predicate stream
    compaction buffers for compacting surviving visible instances, meshlets, or rays. }
  TCastleVulkanStreamCompactor = class
  private
    FDevice: TVulkanRHIDevice;
    FMaxElementCount: Cardinal;
    FPrefixSumBuffer: TVulkanRHIBuffer;
    FCompactedIndicesBuffer: TVulkanRHIBuffer;
    FCompactedCountBuffer: TVulkanRHIBuffer;
    FCompactionComputePipeline: TVulkanRHIComputePipeline;
    FCompactionDispatchCount: Cardinal;
    procedure EnsureCompactionBuffers(const AElementCount: Cardinal);
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { CPU reference: Computes exclusive prefix-sum offsets and compacts indices where APredicates[i] = True.
      Returns the total compacted count of surviving elements. }
    class function EvaluatePrefixSumAndCompact(
      const APredicates: array of Boolean;
      out AExclusivePrefixSum: TCardinalDynamicArray;
      out ACompactedIndices: TCardinalDynamicArray): Cardinal; static;

    { Dispatches the GPU prefix-sum and stream compaction compute pass across AElementCount elements. }
    procedure DispatchStreamCompaction(const ACommandList: TVulkanRHICommandList;
      const AElementCount: Cardinal;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property MaxElementCount: Cardinal read FMaxElementCount;
    property PrefixSumBuffer: TVulkanRHIBuffer read FPrefixSumBuffer;
    property CompactedIndicesBuffer: TVulkanRHIBuffer read FCompactedIndicesBuffer;
    property CompactedCountBuffer: TVulkanRHIBuffer read FCompactedCountBuffer;
    property CompactionComputePipeline: TVulkanRHIComputePipeline
      read FCompactionComputePipeline write FCompactionComputePipeline;
    property CompactionDispatchCount: Cardinal read FCompactionDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { 3D Voxel Radiance Clipmap & Voxel Cone Tracer (Phase 42.3)                 }
  { -------------------------------------------------------------------------- }

  { Manages 3D mipmapped voxel radiance/opacity clipmap textures and compute
    dispatches for Voxel Cone Tracing (VXGI) diffuse & specular global illumination. }
  TCastleVulkanVoxelConeTracer = class
  private
    FDevice: TVulkanRHIDevice;
    FVoxelGridResolution: Cardinal;
    FVoxelMipLevels: Cardinal;
    FWorldExtent: Single;
    FVoxelRadianceTexture: TVulkanRHITexture;
    FIndirectIrradianceTexture: TVulkanRHITexture;
    FVoxelConeTracePipeline: TVulkanRHIComputePipeline;
    FConeTraceDispatchCount: Cardinal;
    procedure EnsureVoxelResources(const AScreenWidth, AScreenHeight: Cardinal);
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Evaluates front-to-back alpha-composited radiance accumulation for a single voxel cone step. }
    class procedure AccumulateVoxelConeSample(
      const ASampleRadianceRGB: TVector3;
      const ASampleOpacity: Single;
      var AAccumRadianceRGB: TVector3;
      var AAccumOpacity: Single); static;

    { Dispatches the 3D Voxel Cone Tracing global illumination pass for an AScreenWidth x AScreenHeight viewport. }
    procedure DispatchVoxelConeTrace(const ACommandList: TVulkanRHICommandList;
      const AScreenWidth, AScreenHeight: Cardinal;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property VoxelGridResolution: Cardinal read FVoxelGridResolution write FVoxelGridResolution;
    property VoxelMipLevels: Cardinal read FVoxelMipLevels;
    property WorldExtent: Single read FWorldExtent write FWorldExtent;
    property VoxelRadianceTexture: TVulkanRHITexture read FVoxelRadianceTexture;
    property IndirectIrradianceTexture: TVulkanRHITexture read FIndirectIrradianceTexture;
    property VoxelConeTracePipeline: TVulkanRHIComputePipeline
      read FVoxelConeTracePipeline write FVoxelConeTracePipeline;
    property ConeTraceDispatchCount: Cardinal read FConeTraceDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Per-Pixel Linked List (PPLL) Exact OIT Manager (Phase 44.3)                }
  { -------------------------------------------------------------------------- }

  TPPLLFragmentNode = record
    ColorRGBA: TVector4; { Straight-alpha RGBA }
    Depth: Single;       { View/NDC depth [0..1] }
    NextIndex: Cardinal;
  end;

  { Manages per-pixel head-pointer texture (pfR32_UInt) and atomic fragment node
    pool SSBO for exact Order-Independent Transparency (PPLL OIT) with depth sorting. }
  TCastleVulkanPerPixelLinkedListOIT = class
  private
    FDevice: TVulkanRHIDevice;
    FMaxNodes: Cardinal;
    FHeadPointerTexture: TVulkanRHITexture;
    FFragmentNodeBuffer: TVulkanRHIBuffer;
    FAtomicCounterBuffer: TVulkanRHIBuffer;
    FResolveComputePipeline: TVulkanRHIComputePipeline;
    FResolveDispatchCount: Cardinal;
    procedure EnsurePPLLResources(const AScreenWidth, AScreenHeight: Cardinal);
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { CPU reference: Sorts an array of PPLL fragment nodes back-to-front by Depth (descending)
      and composites them using standard over blending onto ABackgroundRGB. }
    class function SortAndCompositeFragmentsBackToFront(
      const AFragments: array of TPPLLFragmentNode;
      const ABackgroundRGB: TVector3): TVector3; static;

    { Dispatches the PPLL OIT sorting and compositing resolve pass across AScreenWidth x AScreenHeight. }
    procedure DispatchPPLLResolve(const ACommandList: TVulkanRHICommandList;
      const AScreenWidth, AScreenHeight: Cardinal;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property MaxNodes: Cardinal read FMaxNodes write FMaxNodes;
    property HeadPointerTexture: TVulkanRHITexture read FHeadPointerTexture;
    property FragmentNodeBuffer: TVulkanRHIBuffer read FFragmentNodeBuffer;
    property AtomicCounterBuffer: TVulkanRHIBuffer read FAtomicCounterBuffer;
    property ResolveComputePipeline: TVulkanRHIComputePipeline
      read FResolveComputePipeline write FResolveComputePipeline;
    property ResolveDispatchCount: Cardinal read FResolveDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Vulkan 1.4 Host Image Copy & Push Descriptor Manager (Phase 45.3)          }
  { -------------------------------------------------------------------------- }

  { Manages Vulkan 1.4 Host Image Copy (`VK_EXT_host_image_copy`) zero-staging
    CPU-to-GPU image transfers and Push Descriptor (`VK_KHR_push_descriptor`)
    command-buffer updates without descriptor pool allocations. }
  TCastleVulkanHostImageCopyManager = class
  private
    FDevice: TVulkanRHIDevice;
    FSupportsHostImageCopy: Boolean;
    FSupportsPushDescriptors: Boolean;
    FHostImageCopyCount: Cardinal;
    FHostImageBytesCopied: UInt64;
    FPushDescriptorUpdateCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Performs a zero-staging host-to-image copy into ATexture (or records/validates
      the transfer size in headless/emulated mode). Returns True on success. }
    function CopyHostMemoryToTexture(
      const ATexture: TVulkanRHITexture;
      const AHostData: Pointer;
      const ADataByteSize: UInt64;
      const AMipLevel: Cardinal = 0): Boolean;

    { Records a command-buffer push descriptor update (`vkCmdPushDescriptorSetKHR`)
      for ASetIndex without allocating a VkDescriptorSet from a pool. }
    procedure RecordPushDescriptorUpdate(
      const ACommandList: TVulkanRHICommandList;
      const ASetIndex: Cardinal;
      const ADescriptorWriteCount: Cardinal);

    property SupportsHostImageCopy: Boolean
      read FSupportsHostImageCopy write FSupportsHostImageCopy;
    property SupportsPushDescriptors: Boolean
      read FSupportsPushDescriptors write FSupportsPushDescriptors;
    property HostImageCopyCount: Cardinal read FHostImageCopyCount;
    property HostImageBytesCopied: UInt64 read FHostImageBytesCopied;
    property PushDescriptorUpdateCount: Cardinal read FPushDescriptorUpdateCount;
  end;

  { -------------------------------------------------------------------------- }
  { 3D Gaussian Splatting (3DGS) GPU Renderer (Phase 46.3)                     }
  { -------------------------------------------------------------------------- }

  TGaussianSplatNode = record
    ColorRGBA: TVector4; { RGB radiance + splat opacity }
    Depth: Single;       { View-space depth }
    SplatID: Cardinal;
  end;

  { Manages 3D Gaussian Splatting (3DGS) SSBOs, front-to-back transmittance
    alpha compositing with early-ray termination, and tile rasterization dispatches. }
  TCastleVulkanGaussianSplatRenderer = class
  private
    FDevice: TVulkanRHIDevice;
    FMaxSplats: Cardinal;
    FSplatBuffer: TVulkanRHIBuffer;
    FSortedKeysBuffer: TVulkanRHIBuffer;
    FRenderComputePipeline: TVulkanRHIComputePipeline;
    FRenderDispatchCount: Cardinal;
    procedure EnsureSplatBuffers;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { CPU reference: Sorts 3D Gaussian splats front-to-back (ascending Depth) and composites
      them with Beer-Lambert transmittance T_i = prod_(j<i)(1 - alpha_j) and early termination. }
    class function SortAndCompositeSplatsFrontToBack(
      const ASplats: array of TGaussianSplatNode;
      const ABackgroundRGB: TVector3): TVector3; static;

    { Dispatches the 3D Gaussian Splatting tile sort & rasterization pass across AScreenWidth x AScreenHeight. }
    procedure DispatchGaussianSplatRender(
      const ACommandList: TVulkanRHICommandList;
      const AScreenWidth, AScreenHeight, AActiveSplatCount: Cardinal;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property MaxSplats: Cardinal read FMaxSplats write FMaxSplats;
    property SplatBuffer: TVulkanRHIBuffer read FSplatBuffer;
    property SortedKeysBuffer: TVulkanRHIBuffer read FSortedKeysBuffer;
    property RenderComputePipeline: TVulkanRHIComputePipeline
      read FRenderComputePipeline write FRenderComputePipeline;
    property RenderDispatchCount: Cardinal read FRenderDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Vulkan Descriptor Buffer Manager (`VK_EXT_descriptor_buffer`, Phase 47.3)  }
  { -------------------------------------------------------------------------- }

  { Manages GPU-resident resource and sampler descriptor buffers (`VK_EXT_descriptor_buffer`)
    and `vkCmdSetDescriptorBufferOffsetsEXT` bindings to replace legacy VkDescriptorPool allocations. }
  TCastleVulkanDescriptorBufferManager = class
  private
    FDevice: TVulkanRHIDevice;
    FResourceBufferCapacityBytes: UInt64;
    FSamplerBufferCapacityBytes: UInt64;
    FOffsetAlignmentBytes: UInt64;
    FResourceDescriptorBuffer: TVulkanRHIBuffer;
    FSamplerDescriptorBuffer: TVulkanRHIBuffer;
    FBindOffsetsCount: Cardinal;
    procedure EnsureDescriptorBuffers;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Binds the resource and sampler descriptor buffers and sets the aligned byte offset
      for ASetIndex on ACommandList. }
    procedure BindDescriptorBufferOffset(
      const ACommandList: TVulkanRHICommandList;
      const ASetIndex: Cardinal;
      const AAlignedByteOffset: UInt64);

    property ResourceBufferCapacityBytes: UInt64
      read FResourceBufferCapacityBytes write FResourceBufferCapacityBytes;
    property SamplerBufferCapacityBytes: UInt64
      read FSamplerBufferCapacityBytes write FSamplerBufferCapacityBytes;
    property OffsetAlignmentBytes: UInt64
      read FOffsetAlignmentBytes write FOffsetAlignmentBytes;
    property ResourceDescriptorBuffer: TVulkanRHIBuffer read FResourceDescriptorBuffer;
    property SamplerDescriptorBuffer: TVulkanRHIBuffer read FSamplerDescriptorBuffer;
    property BindOffsetsCount: Cardinal read FBindOffsetsCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU-Driven Indirect Compute Workgroup Dispatcher                           }
  { -------------------------------------------------------------------------- }

  { Manages indirect compute dispatch argument buffers (VkDispatchIndirectCommand:
    GroupCountX, GroupCountY, GroupCountZ) and records vkCmdDispatchIndirect calls. }
  TCastleVulkanIndirectComputeDispatcher = class
  private
    FDevice: TVulkanRHIDevice;
    FIndirectArgumentBuffer: TVulkanRHIBuffer;
    FDispatchedCommandCount: Cardinal;
    procedure EnsureIndirectBuffer(const AMaxCommandSlots: Cardinal);
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Computes the 1D workgroup dispatch count ceil(AActiveItemCount / AWorkgroupSizeX)
      for a GPU-written VkDispatchIndirectCommand structure. }
    class function ComputeWorkgroupCountsFromItemCount(
      const AActiveItemCount, AWorkgroupSizeX: Cardinal): TVector3Cardinal; static;

    { Ensures the indirect dispatch argument buffer is allocated and records a
      DispatchIndirect command at ACommandSlotIndex * 12 bytes. }
    procedure RecordIndirectComputeDispatch(
      const ACommandList: TVulkanRHICommandList;
      const ACommandSlotIndex: Cardinal = 0;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property IndirectArgumentBuffer: TVulkanRHIBuffer read FIndirectArgumentBuffer;
    property DispatchedCommandCount: Cardinal read FDispatchedCommandCount;
  end;

  { -------------------------------------------------------------------------- }
  { Real-Time GPU BC1/BC6H Block Texture Compressor                            }
  { -------------------------------------------------------------------------- }

  { Compresses 4x4 texel blocks into BC1 (8 bytes/block) or BC6H (16 bytes/block)
    compressed GPU storage buffers for runtime virtual textures and reflection probes. }
  TCastleVulkanBCnCompressor = class
  private
    FDevice: TVulkanRHIDevice;
    FCompressedOutputBuffer: TVulkanRHIBuffer;
    FCompressedBlockCount: Cardinal;
    FDispatchCount: Cardinal;
    FCompressionPipeline: TVulkanRHIComputePipeline;
    procedure EnsureCompressionBuffer(const AWidth, AHeight, ABytesPerBlock: Cardinal);
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Quantizes a linear/sRGB RGB color in [0..1]^3 into a 16-bit RGB565 BC1 endpoint word. }
    class function EvaluateBC1EndpointQuantization565(
      const AColorRGB: TVector3): Word; static;

    { Allocates the output block buffer for (AWidth x AHeight) 4x4 blocks and
      dispatches the GPU BCn block compression compute shader. }
    procedure DispatchBCnBlockCompression(
      const ACommandList: TVulkanRHICommandList;
      const AWidth, AHeight: Cardinal;
      const ABytesPerBlock: Cardinal = 8;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property CompressedOutputBuffer: TVulkanRHIBuffer read FCompressedOutputBuffer;
    property CompressedBlockCount: Cardinal read FCompressedBlockCount;
    property DispatchCount: Cardinal read FDispatchCount;
    property CompressionPipeline: TVulkanRHIComputePipeline
      read FCompressionPipeline write FCompressionPipeline;
  end;

  { -------------------------------------------------------------------------- }
  { Vulkan 1.4 Pipeline Binary Manager (VK_KHR_pipeline_binary)                }
  { -------------------------------------------------------------------------- }

  TVulkanPipelineBinaryEntry = record
    PipelineKeyHash: UInt64;
    BinarySize: Cardinal;
  end;

  { Manages standalone driver pipeline binaries (VK_KHR_pipeline_binary) indexed by
    64-bit FNV-1a pipeline keys for lock-free zero-compilation PSO restoration. }
  TCastleVulkanPipelineBinaryManager = class
  private
    FDevice: TVulkanRHIDevice;
    FEntries: array of TVulkanPipelineBinaryEntry;
    FTotalBinaryBytes: UInt64;
    FCacheHitCount: Cardinal;
    function GetBinaryEntryCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);

    { Computes a 64-bit FNV-1a pipeline binary key from shader hashes and state flags. }
    class function ComputePipelineKeyFNV1a64(
      const AVertexShaderHash, AFragmentShaderHash: UInt64;
      const ARenderStateFlags: Cardinal): UInt64; static;

    { Stores or updates a captured pipeline binary record of ABinarySize bytes. }
    procedure StorePipelineBinary(
      const APipelineKeyHash: UInt64;
      const ABinarySize: Cardinal);

    { Looks up a previously captured pipeline binary by key and increments CacheHitCount on hit. }
    function LookupPipelineBinary(
      const APipelineKeyHash: UInt64;
      out AOutBinarySize: Cardinal): Boolean;

    property BinaryEntryCount: Cardinal read GetBinaryEntryCount;
    property TotalBinaryBytes: UInt64 read FTotalBinaryBytes;
    property CacheHitCount: Cardinal read FCacheHitCount;
  end;

  { Per-device container owning lazily instantiated experimental Vulkan managers.
    Automatically freed by TVulkanRHIDevice.Destroy via FExperimentalContext. }
  TVulkanExperimentalDeviceContext = class
  private
    FReflectionProbeManager: TCastleVulkanReflectionProbeManager;
    FDecalManager: TCastleVulkanDecalManager;
    FComputeParticles: TCastleVulkanComputeParticles;
    FContactShadows: TCastleVulkanContactShadows;
    FComputeSkinner: TCastleVulkanComputeSkinner;
    FTerrainCDLOD: TCastleVulkanTerrainCDLOD;
    FAtmosphereRenderer: TCastleVulkanAtmosphereRenderer;
    FOceanSimulator: TCastleVulkanOceanSimulator;
    FDDGIGrid: TCastleVulkanDDGIGrid;
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
    FXPBDSimulator: TCastleVulkanXPBDSimulator;
    FMultiviewStereoManager: TCastleVulkanMultiviewStereoManager;
    FPerInstanceCustomData: TCastleVulkanPerInstanceCustomData;
    FNeuralDenoiser: TCastleVulkanNeuralDenoiser;
    FProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations;
    FStreamCompactor: TCastleVulkanStreamCompactor;
    FVoxelConeTracer: TCastleVulkanVoxelConeTracer;
    FPerPixelLinkedListOIT: TCastleVulkanPerPixelLinkedListOIT;
    FHostImageCopyManager: TCastleVulkanHostImageCopyManager;
    FGaussianSplatRenderer: TCastleVulkanGaussianSplatRenderer;
    FDescriptorBufferManager: TCastleVulkanDescriptorBufferManager;
    FIndirectComputeDispatcher: TCastleVulkanIndirectComputeDispatcher;
    FBCnCompressor: TCastleVulkanBCnCompressor;
    FPipelineBinaryManager: TCastleVulkanPipelineBinaryManager;
  public
    destructor Destroy; override;
  end;

  { Class helper exposing experimental Vulkan managers on TVulkanRHIDevice when opted in. }
  TVulkanRHIDeviceExperimentalHelper = class helper for TVulkanRHIDevice
  private
    function GetReflectionProbeManager: TCastleVulkanReflectionProbeManager;
    function GetDecalManager: TCastleVulkanDecalManager;
    function GetComputeParticles: TCastleVulkanComputeParticles;
    function GetContactShadows: TCastleVulkanContactShadows;
    function GetComputeSkinner: TCastleVulkanComputeSkinner;
    function GetTerrainCDLOD: TCastleVulkanTerrainCDLOD;
    function GetAtmosphereRenderer: TCastleVulkanAtmosphereRenderer;
    function GetOceanSimulator: TCastleVulkanOceanSimulator;
    function GetDDGIGrid: TCastleVulkanDDGIGrid;
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
    function GetXPBDSimulator: TCastleVulkanXPBDSimulator;
    function GetMultiviewStereoManager: TCastleVulkanMultiviewStereoManager;
    function GetPerInstanceCustomData: TCastleVulkanPerInstanceCustomData;
    function GetNeuralDenoiser: TCastleVulkanNeuralDenoiser;
    function GetProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations;
    function GetStreamCompactor: TCastleVulkanStreamCompactor;
    function GetVoxelConeTracer: TCastleVulkanVoxelConeTracer;
    function GetPerPixelLinkedListOIT: TCastleVulkanPerPixelLinkedListOIT;
    function GetHostImageCopyManager: TCastleVulkanHostImageCopyManager;
    function GetGaussianSplatRenderer: TCastleVulkanGaussianSplatRenderer;
    function GetDescriptorBufferManager: TCastleVulkanDescriptorBufferManager;
    function GetIndirectComputeDispatcher: TCastleVulkanIndirectComputeDispatcher;
    function GetBCnCompressor: TCastleVulkanBCnCompressor;
    function GetPipelineBinaryManager: TCastleVulkanPipelineBinaryManager;
  public
    property ReflectionProbeManager: TCastleVulkanReflectionProbeManager read GetReflectionProbeManager;
    property DecalManager: TCastleVulkanDecalManager read GetDecalManager;
    property ComputeParticles: TCastleVulkanComputeParticles read GetComputeParticles;
    property ContactShadows: TCastleVulkanContactShadows read GetContactShadows;
    property ComputeSkinner: TCastleVulkanComputeSkinner read GetComputeSkinner;
    property TerrainCDLOD: TCastleVulkanTerrainCDLOD read GetTerrainCDLOD;
    property AtmosphereRenderer: TCastleVulkanAtmosphereRenderer read GetAtmosphereRenderer;
    property OceanSimulator: TCastleVulkanOceanSimulator read GetOceanSimulator;
    property DDGIGrid: TCastleVulkanDDGIGrid read GetDDGIGrid;
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
    property XPBDSimulator: TCastleVulkanXPBDSimulator read GetXPBDSimulator;
    property MultiviewStereoManager: TCastleVulkanMultiviewStereoManager read GetMultiviewStereoManager;
    property PerInstanceCustomData: TCastleVulkanPerInstanceCustomData read GetPerInstanceCustomData;
    property NeuralDenoiser: TCastleVulkanNeuralDenoiser read GetNeuralDenoiser;
    property ProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations read GetProgrammableSampleLocations;
    property StreamCompactor: TCastleVulkanStreamCompactor read GetStreamCompactor;
    property VoxelConeTracer: TCastleVulkanVoxelConeTracer read GetVoxelConeTracer;
    property PerPixelLinkedListOIT: TCastleVulkanPerPixelLinkedListOIT read GetPerPixelLinkedListOIT;
    property HostImageCopyManager: TCastleVulkanHostImageCopyManager read GetHostImageCopyManager;
    property GaussianSplatRenderer: TCastleVulkanGaussianSplatRenderer read GetGaussianSplatRenderer;
    property DescriptorBufferManager: TCastleVulkanDescriptorBufferManager read GetDescriptorBufferManager;
    property IndirectComputeDispatcher: TCastleVulkanIndirectComputeDispatcher read GetIndirectComputeDispatcher;
    property BCnCompressor: TCastleVulkanBCnCompressor read GetBCnCompressor;
    property PipelineBinaryManager: TCastleVulkanPipelineBinaryManager read GetPipelineBinaryManager;
  end;

{$endif read_interface}
