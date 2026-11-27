{%MainUnit castleinternalshaderrhi.pas}
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
const
  { Maximum bone matrices supported in Set 2 skinning UBO }
  CASTLE_MAX_BONE_MATRICES = 256;
  { Maximum lights supported in Set 0 Binding 1 lights UBO }
  CASTLE_MAX_LIGHTS = 32;

type
  { Standard CGE Vertex Attribute Locations (strictly fixed across all shaders) }
  TCastleVertexLocation = (
    vlPosition    = 0,
    vlNormal      = 1,
    vlTexCoord0   = 2,
    vlTexCoord1   = 3,
    vlColor       = 4,
    vlTangent     = 5,
    vlJoints0     = 6,
    vlWeights0    = 7
  );

  { CPU-side mirror of Set 0, Binding 0 (Per-Pass / Global Scene UBO - std140) }
  PCastleSceneUniformBlock = ^TCastleSceneUniformBlock;
  TCastleSceneUniformBlock = packed record
    ProjectionMatrix: TMatrix4;
    ViewMatrix: TMatrix4;
    ViewMatrixInverse: TMatrix4;
    CameraPosition: TVector4;       // xyz = World Eye Pos, w = Scene Time
    FogColor: TVector4;             // rgb = Fog Color, a = Fog Density
    FogParams: TVector4;            // x = Start, y = End, z = Type, w = Reserved
    LightCount: Cardinal;
    Padding0, Padding1, Padding2: Cardinal;
  end;

  { CPU-side mirror of a single light entry in CastleLightsBlock (std140) }
  PCastleLightData = ^TCastleLightData;
  TCastleLightData = packed record
    Position: TVector4;         // xyz = eye-space position/direction, w = light type (0=dir, 1=point, 2=spot)
    Color: TVector4;            // rgb = color * intensity, w = radius
    SpotDirection: TVector4;    // xyz = eye-space direction, w = spotCosCutoff
    SpotParams: TVector4;       // x = spotCutoff (rad), y = beamWidth (rad), z = spotExponent, w = reserved
    Attenuation: TVector4;      // xyz = constant, linear, quadratic factors, w = reserved
    AmbientColor: TVector4;     // rgb = ambient color * ambient intensity, w = shadow map index / enabled (1.0)
    ProjectorMatrix: TMatrix4;  // 64 bytes: eye-to-light-clip-space projector matrix for shadow mapping
  end; // 6 * 16 + 64 = 160 bytes (160 mod 16 = 0)

  { CPU-side mirror of Set 0, Binding 1 (Multi-Light UBO - std140) }
  PCastleLightsUniformBlock = ^TCastleLightsUniformBlock;
  TCastleLightsUniformBlock = packed record
  private
    function AddLightInternal(const APos, AColor, ASpotDir, ASpotParams, AAtten, AAmbient: TVector4): Integer;
  public
    Count: Cardinal;                                                // 4 bytes
    Padding0, Padding1, Padding2: Cardinal;                         // 12 bytes
    Lights: array [0 .. CASTLE_MAX_LIGHTS - 1] of TCastleLightData; // 32 * 160 = 5120 bytes
    procedure Clear;
    function AddDirectionalLight(const Direction, Color, AmbientColor: TVector3): Integer;
    function AddPointLight(const Position, Color, AmbientColor: TVector3;
      const Attenuation: TVector3; const Radius: Single): Integer;
    function AddSpotLight(const Position, Direction, Color, AmbientColor: TVector3;
      const Attenuation: TVector3; const Radius, SpotCosCutoff, SpotCutoff, BeamWidth, SpotExponent: Single): Integer;
    procedure SetProjectorMatrix(const Index: Integer; const Matrix: TMatrix4;
      const AShadowSlotIndex: Integer = 0);
  end; // Total = 5136 bytes (5136 mod 16 = 0)

  { Shading model selector for RHI forward/bindless material pipelines }
  TCastleShadingModelRHI = (
    smPBRMetallicRoughness = 0,
    smPhong                = 1,
    smUnlit                = 2
  );

  { CPU-side mirror of Set 1, Binding 0 (Per-Material UBO - std140) }
  PCastleMaterialUniformBlock = ^TCastleMaterialUniformBlock;
  TCastleMaterialUniformBlock = packed record
    BaseColor: TVector4;            // PBR BaseColor / Phong DiffuseColor + Opacity
    SpecularColor: TVector4;        // rgb = Specular/F0, a = Shininess (or < 0 for Unlit)
    EmissiveColor: TVector4;        // rgb = Emissive, a = Metallic
    PBRParams: TVector4;            // x = Roughness, y = NormalScale, z = OcclusionStrength, w = AlphaCutoff
    procedure InitDefaultPBR;
    procedure InitDefaultPhong;
    procedure InitDefaultUnlit;
  end;

  { CPU-side mirror of a Bindless Material Entry in Set 1, Binding 1 (std430 SSBO / std140 UBO).
    Stores material factors alongside 32-bit bindless texture array indices into Set 1, Binding 0
    (castle_BindlessTextures[]), enabling multi-material vkCmdDrawIndexedIndirect batches. }
  PCastleBindlessMaterialEntry = ^TCastleBindlessMaterialEntry;
  TCastleBindlessMaterialEntry = packed record
    BaseColor: TVector4;            // 16 bytes
    SpecularColor: TVector4;        // 16 bytes
    EmissiveColor: TVector4;        // 16 bytes
    PBRParams: TVector4;            // 16 bytes
    BaseColorTexIndex: Cardinal;    // 4 bytes (index into castle_BindlessTextures[])
    NormalTexIndex: Cardinal;       // 4 bytes
    MetallicRoughnessTexIndex: Cardinal; // 4 bytes
    EmissiveTexIndex: Cardinal;     // 4 bytes
  end; // Total = 80 bytes (80 mod 16 = 0)

  { CPU-side mirror of Per-Draw Push Constants (128 bytes max, guaranteed by Vulkan spec) }
  PCastlePushConstantsBlock = ^TCastlePushConstantsBlock;
  TCastlePushConstantsBlock = packed record
    ModelViewMatrix: TMatrix4;      // 64 bytes
    NormalMatrixRow0: TVector4;     // 16 bytes (std140 padded 3x3 normal matrix)
    NormalMatrixRow1: TVector4;     // 16 bytes
    NormalMatrixRow2: TVector4;     // 16 bytes
    ObjectParams: TVector4;         // 16 bytes (x = MaterialIndex, y = BoneOffset, zw = Custom)
  end; // Total = 128 bytes

  { CPU-side mirror of Set 2, Binding 0 (Per-Object Skinning UBO - std140) }
  PCastleSkinningUniformBlock = ^TCastleSkinningUniformBlock;
  TCastleSkinningUniformBlock = packed record
    JointMatrices: array [0 .. CASTLE_MAX_BONE_MATRICES - 1] of TMatrix4; // 256 * 64 = 16384 bytes
    JointCount: Cardinal;
    Padding0, Padding1, Padding2: Cardinal;
  end;

  { CPU-side mirror of CastleScreenPushConstants (32 bytes) for post-processing screen effects }
  PCastleScreenPushConstants = ^TCastleScreenPushConstants;
  TCastleScreenPushConstants = packed record
    ScreenSize: TVector2;    // x = screen_width, y = screen_height (8 bytes)
    ScreenPlanes: TVector2;  // x = near plane, y = far plane (8 bytes)
    ScreenCustom: TVector4;  // custom effect parameters (16 bytes)
  end; // Total = 32 bytes

  { CPU-side mirror of Set 0, Binding 0 for GPU Compute Frustum/Distance/Hi-Z Culling (std140) }
  PCastleGpuCullingUniformBlock = ^TCastleGpuCullingUniformBlock;
  TCastleGpuCullingUniformBlock = packed record
    FrustumPlanes: array[0..5] of TVector4; // 6 planes (A, B, C, D), 96 bytes
    CameraPosition: TVector4;               // xyz = camera world pos, w = max distance (0 = disabled), 16 bytes
    HiZParams: TVector4;                    // x = width, y = height, z = mipCount, w = enableHiZ, 16 bytes
    InstanceCount: Cardinal;                // 4 bytes
    EnableFrustumCulling: Cardinal;         // 4 bytes (1 = enabled, 0 = disabled)
    EnableDistanceCulling: Cardinal;        // 4 bytes (1 = enabled, 0 = disabled)
    CompactDrawStream: Cardinal;            // 4 bytes (1 = compact visible draws via atomicAdd, 0 = 1:1 slots)
  end; // Total = 144 bytes (144 mod 16 = 0)

  { CPU-side mirror of a single instance in Set 0, Binding 1 Input SSBO for GPU Compute Culling (std430) }
  PCastleGpuCullingInstance = ^TCastleGpuCullingInstance;
  TCastleGpuCullingInstance = packed record
    BoundingSphere: TVector4; // xyz = world-space center, w = radius (16 bytes)
    AABBMin: TVector4;        // xyz = world-space AABB min, w = reserved (16 bytes)
    AABBMax: TVector4;        // xyz = world-space AABB max, w = reserved (16 bytes)
    IndexCount: Cardinal;     // 4 bytes (for VkDrawIndexedIndirectCommand)
    FirstIndex: Cardinal;     // 4 bytes
    VertexOffset: Integer;    // 4 bytes
    FirstInstance: Cardinal;  // 4 bytes
    InstanceCount: Cardinal;  // 4 bytes (typically 1)
    MaterialIndex: Cardinal;  // 4 bytes (bindless material index)
    Padding0: Cardinal;       // 4 bytes
    Padding1: Cardinal;       // 4 bytes
  end; // Total = 80 bytes (80 mod 16 = 0)

  { Push constants for Hi-Z depth pyramid mipmap reduction compute shader (16 bytes) }
  PCastleHiZPushConstants = ^TCastleHiZPushConstants;
  TCastleHiZPushConstants = packed record
    DstMipWidth: Cardinal;
    DstMipHeight: Cardinal;
    SrcMipWidth: Cardinal;
    SrcMipHeight: Cardinal;
  end;

const
  CASTLE_MAX_CLUSTERED_LIGHTS   = 256;
  CASTLE_DEFAULT_CLUSTER_X      = 16;
  CASTLE_DEFAULT_CLUSTER_Y      = 8;
  CASTLE_DEFAULT_CLUSTER_Z      = 24;
  CASTLE_MAX_LIGHTS_PER_CLUSTER = 64;
  CASTLE_MAX_SHADOW_CASCADES    = 4;
  CASTLE_MAX_SHADOW_ATLAS_TILES = 64;

type
  { Light type in Clustered Forward+ light buffer }
  TCastleClusterLightType = (
    cltDirectional = 0,
    cltPoint       = 1,
    cltSpot        = 2
  );

  { GPU std430 clustered light entry (64 bytes, 16-byte aligned) }
  PCastleClusteredLight = ^TCastleClusteredLight;
  TCastleClusteredLight = packed record
    PositionAndRange: TVector4;    // xyz = view-space position, w = attenuation range/radius (16 bytes)
    DirectionAndSpotCos: TVector4; // xyz = view-space direction, w = outer spot cos cutoff (16 bytes)
    ColorAndIntensity: TVector4;   // rgb = linear light color, w = intensity multiplier (16 bytes)
    ShadowAndTypeParams: TVector4; // x = Ord(LightType), y = inner spot cos, z = shadow tile index (-1 if none), w = shadow bias (16 bytes)
  end; // Total = 64 bytes

  { GPU std430 per-cluster light grid entry (8 bytes) }
  PCastleClusterGridEntry = ^TCastleClusterGridEntry;
  TCastleClusterGridEntry = packed record
    Offset: Cardinal; // Start offset in flat LightIndexList SSBO
    Count: Cardinal;  // Number of lights intersecting this cluster (0..CASTLE_MAX_LIGHTS_PER_CLUSTER)
  end;

  { GPU std140 uniform block for 3D Clustered Forward+ light culling compute shader (112 bytes) }
  PCastleClusterCullingUniformBlock = ^TCastleClusterCullingUniformBlock;
  TCastleClusterCullingUniformBlock = packed record
    InverseProjectionMatrix: TMatrix4; // 64 bytes
    ScreenAndDepthParams: TVector4;    // 16 bytes (x = ScreenWidth, y = ScreenHeight, z = ZNear, w = ZFar)
    GridX: Cardinal;                   // 4 bytes
    GridY: Cardinal;                   // 4 bytes
    GridZ: Cardinal;                   // 4 bytes
    ActiveLightCount: Cardinal;        // 4 bytes
    LogDepthParams: TVector4;          // 16 bytes (x = GridZ / Ln(ZFar/ZNear), y = -GridZ*Ln(ZNear)/Ln(ZFar/ZNear), z = MaxLightsPerCluster, w = 0)
  end; // Total = 112 bytes (112 mod 16 = 0)

  { GPU std140 uniform block for 4-cascade Directional Cascaded Shadow Maps (336 bytes) }
  PCastleDirectionalCascadeShadowBlock = ^TCastleDirectionalCascadeShadowBlock;
  TCastleDirectionalCascadeShadowBlock = packed record
    CascadeViewProjMatrix: array[0..CASTLE_MAX_SHADOW_CASCADES - 1] of TMatrix4; // 256 bytes
    CascadeAtlasUVScaleOffset: array[0..CASTLE_MAX_SHADOW_CASCADES - 1] of TVector4; // 64 bytes (xy = scale, zw = offset)
    CascadeSplitDepths: TVector4; // 16 bytes (far view-space depth split d0..d3)
  end; // Total = 336 bytes (336 mod 16 = 0)

  { GPU std430 entry for positional (spot / point face) shadow atlas tile (80 bytes) }
  PCastlePositionalShadowTileEntry = ^TCastlePositionalShadowTileEntry;
  TCastlePositionalShadowTileEntry = packed record
    LightViewProjMatrix: TMatrix4; // 64 bytes
    AtlasUVScaleOffset: TVector4;  // 16 bytes (xy = UV scale, zw = UV offset in shadow atlas)
  end; // Total = 80 bytes

const
  CASTLE_BLOOM_MAX_MIP_LEVELS     = 6;
  CASTLE_LUMINANCE_HISTOGRAM_BINS = 256;

  { Phase 16.3: Default 3D camera-aligned Froxel Volumetric Fog grid dimensions }
  CASTLE_FROXEL_GRID_X = 160;
  CASTLE_FROXEL_GRID_Y = 90;
  CASTLE_FROXEL_GRID_Z = 64;

  { Phase 17.2 & 17.3: Maximum localized reflection probes and projected box decals }
  CASTLE_MAX_REFLECTION_PROBES = 16;
  CASTLE_MAX_PROJECTED_DECALS  = 64;

  { Phase 18.1: Default GPU compute particle pool capacity }
  CASTLE_DEFAULT_MAX_PARTICLES = 65536;

  { Phase 19.1 & 19.2: Default compute skinning vertex capacity and max CDLOD terrain quadtree nodes }
  CASTLE_DEFAULT_MAX_SKINNED_VERTICES = 16384;
  CASTLE_MAX_TERRAIN_CDLOD_NODES      = 256;

  { Phase 20.2: Default Sky-View LUT resolution for Rayleigh/Mie Atmospheric Scattering }
  CASTLE_DEFAULT_SKY_VIEW_LUT_WIDTH   = 192;
  CASTLE_DEFAULT_SKY_VIEW_LUT_HEIGHT  = 108;

  { Phase 21.2: Default GPU Compute Gerstner Ocean simulation texture resolution }
  CASTLE_DEFAULT_OCEAN_GRID_SIZE      = 128;

  { Phase 22.1 & 22.2: Default DDGI Octahedral Probe Grid dimensions and max GPU Meshlets }
  CASTLE_DEFAULT_DDGI_GRID_X          = 8;
  CASTLE_DEFAULT_DDGI_GRID_Y          = 4;
  CASTLE_DEFAULT_DDGI_GRID_Z          = 8;
  CASTLE_DEFAULT_DDGI_OCT_TEXELS      = 8;
  CASTLE_MAX_MESHLETS                 = 4096;

  { Phase 23.2: Virtual Shadow Map (VSM) Page Table & Physical Tile Pool dimensions }
  CASTLE_VSM_PAGE_TABLE_DIM           = 64;
  CASTLE_VSM_PHYSICAL_TILE_SIZE       = 128;
  CASTLE_VSM_PHYSICAL_TILES_PER_ROW   = 16;
  CASTLE_VSM_MAX_PHYSICAL_TILES       = 256;

  { Maximum custom user sampler uniforms per Effect / ComposedShader / ScreenEffect (Set 2, Bindings 2..9) }
  CASTLE_MAX_USER_EFFECT_SAMPLERS     = 8;

type
  { Reflected std140 member of CastleUserEffectBlock (Set 2, Binding 1) }
  TUserEffectUniformDesc = record
    Name: String;
    GLSLType: String;
    DeclSuffix: String;
    ByteOffset: PtrUInt;
    ByteSize: PtrUInt;
    ArrayCount: Cardinal;
  end;

  { Reflected custom sampler uniform at Set 2, Binding (2 + SlotIndex) }
  TUserEffectSamplerDesc = record
    Name: String;
    GLSLType: String;
    SlotIndex: Integer;
  end;

  { Reflected custom inter-stage varying assigned deterministic location }
  TUserEffectVaryingDesc = record
    Name: String;
    GLSLType: String;
    InterpQual: String;
    Location: Cardinal;
    LocationSlots: Cardinal;
  end;

  { Unified cross-stage reflection layout for an X3D Effect / ComposedShader / ScreenEffect }
  TUserEffectShaderLayout = record
    Uniforms: array of TUserEffectUniformDesc;
    Samplers: array of TUserEffectSamplerDesc;
    Varyings: array of TUserEffectVaryingDesc;
    TotalUBOSize: PtrUInt;
    function FindUniform(const AName: String; out ADesc: TUserEffectUniformDesc): Boolean;
    function FindSampler(const AName: String; out ADesc: TUserEffectSamplerDesc): Boolean;
    function FindVarying(const AName: String; out ADesc: TUserEffectVaryingDesc): Boolean;
  end;
  { HDR Tonemapping Operators (Phase 15.3) }
  TCastleTonemapOperator = (
    tmoLinear     = 0,
    tmoReinhard   = 1,
    tmoACESFilmic = 2,
    tmoAgX        = 3
  );

  { Push constants for 13-tap Karis downsample & 9-tap tent upsample bloom compute passes (32 bytes) }
  PCastleBloomPushConstants = ^TCastleBloomPushConstants;
  TCastleBloomPushConstants = packed record
    SrcTexelSize: TVector2;      // 8 bytes (1.0 / SrcWidth, 1.0 / SrcHeight)
    Threshold: Single;           // 4 bytes (Bloom brightness threshold, e.g. 1.0)
    Knee: Single;                // 4 bytes (Soft knee width, e.g. 0.5)
    FilterRadius: Single;        // 4 bytes (Tent filter radius in UV or texel units, e.g. 1.0)
    MipLevel: Cardinal;          // 4 bytes (Current bloom mip level 0..CASTLE_BLOOM_MAX_MIP_LEVELS-1)
    IsFirstDownsample: Cardinal; // 4 bytes (1 on Mip 0 -> applies Karis average + soft threshold, 0 on Mip > 0)
    DstPackedSize: Cardinal;     // 4 bytes ((DstHeight shl 16) or DstWidth)
  end; // Total = 32 bytes

  { Push constants / uniform parameters for 256-bin log-luminance histogram & eye adaptation (32 bytes) }
  PCastleAutoExposureParams = ^TCastleAutoExposureParams;
  TCastleAutoExposureParams = packed record
    MinLogLum: Single;        // 4 bytes (Minimum log2 luminance, e.g. -8.0)
    MaxLogLum: Single;        // 4 bytes (Maximum log2 luminance, e.g. +4.0)
    TimeDelta: Single;        // 4 bytes (Frame delta time in seconds)
    AdaptationSpeed: Single;  // 4 bytes (Temporal adaptation speed, e.g. 2.5)
    TargetMiddleGrey: Single; // 4 bytes (Key value / middle grey, e.g. 0.18)
    MinExposure: Single;      // 4 bytes (Clamp min exposure, e.g. 0.1)
    MaxExposure: Single;      // 4 bytes (Clamp max exposure, e.g. 10.0)
    TotalPixels: Cardinal;    // 4 bytes (Width * Height of HDR scene target)
  end; // Total = 32 bytes

  { Push constants for HDR + Bloom + Auto-Exposure + ACES/AgX Tonemapping composite pass (32 bytes) }
  PCastleHDRCompositePushConstants = ^TCastleHDRCompositePushConstants;
  TCastleHDRCompositePushConstants = packed record
    Exposure: Single;            // 4 bytes (Manual or adapted exposure multiplier)
    BloomIntensity: Single;      // 4 bytes (Bloom contribution weight, e.g. 0.08)
    Gamma: Single;               // 4 bytes (Display gamma, default 2.2)
    Saturation: Single;          // 4 bytes (Color grading saturation, default 1.0)
    Contrast: Single;            // 4 bytes (Color grading contrast, default 1.0)
    TonemapOperator: Cardinal;   // 4 bytes (Ord(TCastleTonemapOperator))
    EnableBloom: Cardinal;       // 4 bytes (1 = add bloom, 0 = bypass)
    EnableAutoExposure: Cardinal;// 4 bytes (1 = multiply by adapted exposure SSBO, 0 = manual Exposure)
  end; // Total = 32 bytes

  { Phase 16.1: Push constants for Compute Ground-Truth Ambient Occlusion (GTAO) & Bilateral Denoiser (48 bytes) }
  PCastleGTAOPushConstants = ^TCastleGTAOPushConstants;
  TCastleGTAOPushConstants = packed record
    InvResolution: TVector2;  // 8 bytes (1.0 / Width, 1.0 / Height)
    ProjScale: TVector2;      // 8 bytes (1.0 / Proj[0][0], 1.0 / Proj[1][1])
    ZNear: Single;            // 4 bytes (Camera near plane)
    ZFar: Single;             // 4 bytes (Camera far plane)
    EffectRadius: Single;     // 4 bytes (View-space AO hemisphere radius, e.g. 1.5)
    FalloffRange: Single;     // 4 bytes (Horizon thickness falloff range, e.g. 0.6)
    Power: Single;            // 4 bytes (AO contrast power exponent, e.g. 1.5)
    SliceCount: Cardinal;     // 4 bytes (Azimuthal slices per pixel, e.g. 3)
    StepsPerSlice: Cardinal;  // 4 bytes (March steps per slice side, e.g. 4)
    DenoisePass: Cardinal;    // 4 bytes (0 = GTAO horizon evaluation, 1 = 5x5 bilateral denoiser)
  end; // Total = 48 bytes

  { Phase 16.2: Push constants for Hierarchical-Z Screen-Space Reflections (Hi-Z SSR) (48 bytes) }
  PCastleSSRPushConstants = ^TCastleSSRPushConstants;
  TCastleSSRPushConstants = packed record
    InvResolution: TVector2;  // 8 bytes (1.0 / Width, 1.0 / Height)
    ZNear: Single;            // 4 bytes (Camera near plane)
    ZFar: Single;             // 4 bytes (Camera far plane)
    MaxDistance: Single;      // 4 bytes (Maximum view-space ray distance, e.g. 50.0)
    Thickness: Single;        // 4 bytes (Depth intersection thickness tolerance, e.g. 0.25)
    MaxRoughness: Single;     // 4 bytes (Roughness cutoff above which SSR fades out, e.g. 0.6)
    EdgeFadeWidth: Single;    // 4 bytes (Screen-edge vignette fade border, e.g. 0.12)
    MaxSteps: Cardinal;       // 4 bytes (Maximum Hi-Z cell march steps, e.g. 48)
    HiZMipCount: Cardinal;    // 4 bytes (Number of Hi-Z min-depth mip levels, e.g. 6)
    Intensity: Single;        // 4 bytes (Reflection intensity multiplier, e.g. 1.0)
    Reserved: Cardinal;       // 4 bytes (Padding to 16-byte alignment)
  end; // Total = 48 bytes

  { Phase 16.3: Uniform / push-constant parameters for 3D Froxel Volumetric Fog & Exponential Height Fog (64 bytes) }
  PCastleVolumetricFogParams = ^TCastleVolumetricFogParams;
  TCastleVolumetricFogParams = packed record
    FogAlbedoAndBaseDensity: TVector4; // 16 bytes (rgb = scattering albedo, w = base density rho_0)
    SunDirectionAndAnisotropy: TVector4; // 16 bytes (xyz = normalized sun dir, w = Henyey-Greenstein g in [-0.99..0.99])
    SunColorAndIntensity: TVector4;    // 16 bytes (rgb = sun color, w = sun scattering intensity)
    HeightFalloff: Single;             // 4 bytes (Exponential height falloff h)
    BaseHeight: Single;                // 4 bytes (Reference fog height y_0)
    ZNear: Single;                     // 4 bytes (Camera near plane)
    ZFar: Single;                      // 4 bytes (Camera far plane)
  end; // Total = 64 bytes

  { Phase 17.1: Push constants for Temporal Anti-Aliasing (TAA) resolve compute pass (32 bytes) }
  PCastleTAAPushConstants = ^TCastleTAAPushConstants;
  TCastleTAAPushConstants = packed record
    InvResolution: TVector2;      // 8 bytes (1.0 / Width, 1.0 / Height)
    JitterOffset: TVector2;       // 8 bytes (Current sub-pixel Halton camera jitter in UV/NDC)
    BlendFactor: Single;          // 4 bytes (Current frame weight, e.g. 0.08 -> 92% history)
    VarianceClipGamma: Single;    // 4 bytes (YCoCg 3x3 neighborhood variance clip gamma, e.g. 1.25)
    VelocityWeightScale: Single;  // 4 bytes (Disocclusion velocity boost scale, e.g. 40.0)
    FrameIndex: Cardinal;         // 4 bytes (Monotonic frame counter)
  end; // Total = 32 bytes

  { Phase 17.2: GPU std140/std430 entry for a localized Box-Projected Parallax Reflection Probe (64 bytes) }
  PCastleReflectionProbeEntry = ^TCastleReflectionProbeEntry;
  TCastleReflectionProbeEntry = packed record
    PositionAndRadius: TVector4;     // 16 bytes (xyz = world capture center, w = influence radius)
    BoxMinAndIntensity: TVector4;    // 16 bytes (xyz = world AABB min, w = intensity multiplier)
    BoxMaxAndCubemapIndex: TVector4; // 16 bytes (xyz = world AABB max, w = cubemap array / bindless index)
    BlendDistanceAndFlags: TVector4; // 16 bytes (x = inner transition falloff distance, y = box projection 1/0, z = mip count, w = priority)
  end; // Total = 64 bytes

  { Phase 17.3: GPU std140/std430 entry for an Oriented Bounding Box (OBB) Projected Decal (96 bytes) }
  PCastleProjectedDecalEntry = ^TCastleProjectedDecalEntry;
  TCastleProjectedDecalEntry = packed record
    WorldToDecalRow0: TVector4;        // 16 bytes (Row 0 of 4x3 World -> OBB unit box [-0.5..0.5]^3 transform)
    WorldToDecalRow1: TVector4;        // 16 bytes (Row 1 of 4x3 World -> OBB unit box [-0.5..0.5]^3 transform)
    WorldToDecalRow2: TVector4;        // 16 bytes (Row 2 of 4x3 World -> OBB unit box [-0.5..0.5]^3 transform)
    AlbedoTintAndOpacity: TVector4;    // 16 bytes (rgb = decal base color tint, a = opacity)
    DecalNormalAndRoughness: TVector4; // 16 bytes (xyz = world projection normal axis, w = roughness modulation)
    UVScaleOffset: TVector4;           // 16 bytes (xy = UV scale, zw = UV offset in decal atlas)
  end; // Total = 96 bytes

  { Phase 18.1: GPU std430 entry for a single simulated particle (48 bytes) }
  PCastleGPUParticle = ^TCastleGPUParticle;
  TCastleGPUParticle = packed record
    PositionAndAge: TVector4;     // 16 bytes (xyz = world position, w = current age in seconds)
    VelocityAndMaxLife: TVector4; // 16 bytes (xyz = world velocity, w = maximum lifetime in seconds)
    ColorAndSize: TVector4;       // 16 bytes (rgb = particle emissive/tint color, w = billboard radius)
  end; // Total = 48 bytes

  { Phase 18.1: Push constants for GPU Compute Particle Simulation & Alive-List Compaction (48 bytes) }
  PCastleParticleSimPushConstants = ^TCastleParticleSimPushConstants;
  TCastleParticleSimPushConstants = packed record
    GravityAndDeltaTime: TVector4; // 16 bytes (xyz = gravity vector, w = deltaTime)
    EmitterOriginAndDrag: TVector4;// 16 bytes (xyz = emitter world origin, w = linear air drag)
    GroundPlaneY: Single;          // 4 bytes (Ground collision plane Y)
    Restitution: Single;           // 4 bytes (Bounce restitution factor in [0..1])
    MaxParticles: Cardinal;        // 4 bytes (Total particle capacity)
    SpawnSeed: Cardinal;           // 4 bytes (Per-frame random hash seed)
  end; // Total = 48 bytes

  { Phase 18.3: Push constants for Screen-Space Raymarched Contact Shadows (48 bytes) }
  PCastleContactShadowsPushConstants = ^TCastleContactShadowsPushConstants;
  TCastleContactShadowsPushConstants = packed record
    InvResolution: TVector2; // 8 bytes (1.0 / Width, 1.0 / Height)
    LightDirView: TVector3;  // 12 bytes (Normalized view-space directional light vector towards light)
    RayLength: Single;       // 4 bytes (View-space contact shadow ray march length, e.g. 0.35)
    Thickness: Single;       // 4 bytes (Depth occluder thickness window, e.g. 0.05)
    ZNear: Single;           // 4 bytes (Camera near plane)
    ZFar: Single;            // 4 bytes (Camera far plane)
    StepCount: Cardinal;     // 4 bytes (Raymarch step count, e.g. 16)
    Contrast: Single;        // 4 bytes (Contact shadow contrast multiplier, e.g. 1.0)
    Reserved: Cardinal;      // 4 bytes (Padding to 16-byte alignment)
  end; // Total = 48 bytes

  { Phase 19.1: Source bind-pose vertex entry for GPU Compute Skeletal Skinning (64 bytes) }
  PCastleSkinningVertex = ^TCastleSkinningVertex;
  TCastleSkinningVertex = packed record
    PositionAndUVX: TVector4;             // 16 bytes (xyz = bind-pose position, w = u)
    NormalAndUVY: TVector4;               // 16 bytes (xyz = bind-pose normal, w = v)
    JointIndices: array[0..3] of Cardinal;// 16 bytes (4 bone matrix indices)
    JointWeights: TVector4;               // 16 bytes (4 bone blend weights)
  end; // Total = 64 bytes

  { Phase 19.1: Morph target displacement delta entry (32 bytes) }
  PCastleMorphTargetDelta = ^TCastleMorphTargetDelta;
  TCastleMorphTargetDelta = packed record
    DeltaPosition: TVector4; // 16 bytes (xyz = position displacement delta, w = 0)
    DeltaNormal: TVector4;   // 16 bytes (xyz = normal displacement delta, w = 0)
  end; // Total = 32 bytes

  { Phase 19.1: Push constants for GPU Compute Skeletal Skinning & Morph Target Blending (32 bytes) }
  PCastleComputeSkinningPushConstants = ^TCastleComputeSkinningPushConstants;
  TCastleComputeSkinningPushConstants = packed record
    MorphWeights: TVector4;       // 16 bytes (up to 4 active morph target blend weights)
    VertexCount: Cardinal;        // 4 bytes (number of vertices to skin)
    MorphTargetCount: Cardinal;   // 4 bytes (0..4 active morph targets)
    JointCount: Cardinal;         // 4 bytes (active bone matrix count)
    StorePreviousPos: Cardinal;   // 4 bytes (1 = copy previous skinned pos for TAA motion vectors)
  end; // Total = 32 bytes

  { Phase 19.2: GPU std430 entry for a Continuous Distance-Dependent LOD (CDLOD) Terrain quadtree patch (32 bytes) }
  PCastleTerrainCDLODNode = ^TCastleTerrainCDLODNode;
  TCastleTerrainCDLODNode = packed record
    NodeXZAndScale: TVector4;              // 16 bytes (x = world X origin, y = world Z origin, z = patch world size, w = LOD level)
    MorphStartEndAndHeightRange: TVector4; // 16 bytes (x = morph start dist, y = morph end dist, z = minY, w = maxY)
  end; // Total = 32 bytes

  { Phase 20.2: Push constants for Rayleigh / Mie Physical Sky & Aerial Perspective LUT compute pass (64 bytes) }
  PCastleAtmospherePushConstants = ^TCastleAtmospherePushConstants;
  TCastleAtmospherePushConstants = packed record
    SunDirectionAndIntensity: TVector4;    // 16 bytes (xyz = normalized sun dir, w = solar irradiance intensity)
    RayleighScatteringAndHeight: TVector4; // 16 bytes (rgb = Rayleigh sea-level scattering coeff, w = scale height H_R)
    MieScatteringAndHeight: TVector4;      // 16 bytes (rgb = Mie sea-level scattering coeff, w = scale height H_M)
    PlanetRadius: Single;                  // 4 bytes (Planet radius in meters, e.g. 6360000.0)
    AtmosphereRadius: Single;              // 4 bytes (Top-of-atmosphere radius in meters, e.g. 6420000.0)
    MieAnisotropyG: Single;                // 4 bytes (Cornette-Shanks Mie asymmetry g in [0..0.99], default 0.8)
    RaymarchSteps: Cardinal;               // 4 bytes (Single-scattering raymarch steps, default 16)
  end; // Total = 64 bytes

  { Phase 21.2: Push constants for GPU Compute Gerstner Wave Ocean Simulation & Foam (48 bytes) }
  PCastleOceanWavePushConstants = ^TCastleOceanWavePushConstants;
  TCastleOceanWavePushConstants = packed record
    WindDirectionAndSpeed: TVector4; // 16 bytes (xy = normalized wind dir, z = wind speed m/s, w = time seconds)
    WaveParams: TVector4;            // 16 bytes (x = base amplitude, y = base wavelength, z = choppiness Q, w = patch world size)
    GridSize: Cardinal;              // 4 bytes (Ocean texture resolution, default 128)
    OctaveCount: Cardinal;           // 4 bytes (Number of Gerstner wave octaves, default 4)
    FoamThreshold: Single;           // 4 bytes (Jacobian determinant threshold for whitecap crest foam, e.g. 0.65)
    Gravity: Single;                 // 4 bytes (Gravitational acceleration, default 9.81)
  end; // Total = 48 bytes

  { Phase 22.1: GPU std140/push-constant parameters for Dynamic Diffuse Global Illumination (DDGI) Octahedral Probe Grid (48 bytes) }
  PCastleDDGIGridParams = ^TCastleDDGIGridParams;
  TCastleDDGIGridParams = packed record
    GridOriginAndNormalBias: TVector4;  // 16 bytes (xyz = world-space probe [0,0,0] origin, w = normal bias in meters)
    GridSpacingAndViewBias: TVector4;   // 16 bytes (xyz = probe world spacing, w = view bias in meters)
    GridCountX: Cardinal;               // 4 bytes (probe count along X, default 8)
    GridCountY: Cardinal;               // 4 bytes (probe count along Y, default 4)
    GridCountZ: Cardinal;               // 4 bytes (probe count along Z, default 8)
    Hysteresis: Single;                 // 4 bytes (temporal irradiance hysteresis in [0..0.99], default 0.97)
  end; // Total = 48 bytes

  { Phase 22.2: GPU std430 descriptor for a 64-vertex / 124-triangle Meshlet cluster (48 bytes) }
  PCastleMeshletDescriptor = ^TCastleMeshletDescriptor;
  TCastleMeshletDescriptor = packed record
    BoundingSphere: TVector4;    // 16 bytes (xyz = meshlet sphere center, w = radius)
    ConeAxisAndCutoff: TVector4; // 16 bytes (xyz = normalized normal cone axis, w = sin(coneHalfAngle) backface cutoff)
    VertexOffset: Cardinal;      // 4 bytes (base vertex offset)
    VertexCount: Cardinal;       // 4 bytes (meshlet vertex count <= 64)
    TriangleOffset: Cardinal;    // 4 bytes (base primitive offset)
    TriangleCount: Cardinal;     // 4 bytes (meshlet triangle count <= 124)
  end; // Total = 48 bytes

  { Phase 24.1: GPU std430 descriptor for Continuous Instance LOD Selection (48 bytes) }
  PCastleLODInstanceDescriptor = ^TCastleLODInstanceDescriptor;
  TCastleLODInstanceDescriptor = packed record
    BoundingSphere: TVector4;      // 16 bytes (xyz = world sphere center, w = radius)
    LODScreenThresholds: TVector4; // 16 bytes (x = LOD0->1 coverage, y = LOD1->2, z = LOD2->3, w = cull coverage)
    MeshID: Cardinal;              // 4 bytes (base mesh asset ID)
    InstanceID: Cardinal;          // 4 bytes (instance index)
    TransitionBand: Single;        // 4 bytes (crossfade band width in screen coverage units, default 0.02)
    Flags: Cardinal;               // 4 bytes (reserved)
  end; // Total = 48 bytes

const
  CASTLE_MAX_STREAMED_TEXTURES = 512;

type
  { Phase 27.2: GPU std430 descriptor for a Nanite-style Hierarchical Cluster DAG Node (48 bytes) }
  PCastleClusterDAGNode = ^TCastleClusterDAGNode;
  TCastleClusterDAGNode = packed record
    SphereCenterAndRadius: TVector4;       // 16 bytes (xyz = world sphere center, w = radius)
    ParentCenterAndErrors: TVector4;       // 16 bytes (x = self world error, y = parent world error, z = parent dist offset, w = reserved)
    ClusterID: Cardinal;                   // 4 bytes (cluster index)
    VertexOffset: Cardinal;                // 4 bytes (base vertex offset)
    TriangleOffset: Cardinal;              // 4 bytes (base primitive offset)
    TriangleCount: Cardinal;               // 4 bytes (triangle count <= 124)
  end; // Total = 48 bytes

  { Phase 29.1: GPU std430 streaming reservoir for ReSTIR DI / GI (UE5 MegaLights, 32 bytes) }
  PCastleReSTIRReservoir = ^TCastleReSTIRReservoir;
  TCastleReSTIRReservoir = packed record
    SelectedLightID: Integer;     // 4 bytes (selected candidate light index, -1 if empty)
    WeightSum: Single;            // 4 bytes (running sum of resampling weights sum(w_i))
    TargetPDF: Single;            // 4 bytes (unshadowed target PDF p_hat(y) of SelectedLightID)
    SampleCountM: Cardinal;       // 4 bytes (number of candidates M seen by this reservoir)
    ContributionWeightW: Single;  // 4 bytes (unbiased RIS weight W = WeightSum / (TargetPDF * M))
    Reserved0: Cardinal;          // 4 bytes (std430 16/32-byte alignment padding)
    Reserved1: Cardinal;          // 4 bytes
    Reserved2: Cardinal;          // 4 bytes
  end; // Total = 32 bytes

  { Phase 111: Push constants for GTAO + Hi-Z SSR HDR lighting modulation compute pass (16 bytes) }
  PCastlePostProcessModulatePushConstants = ^TCastlePostProcessModulatePushConstants;
  TCastlePostProcessModulatePushConstants = packed record
    AOStrength: Single;   // 4 bytes (0 = no AO attenuation, 1 = full GTAO visibility)
    SSRStrength: Single;  // 4 bytes (additive screen-space reflection multiplier)
    DstWidth: Cardinal;   // 4 bytes (output HDR texture width in pixels)
    DstHeight: Cardinal;  // 4 bytes (output HDR texture height in pixels)
  end; // Total = 16 bytes

  { Generates RHI-compliant GLSL headers, UBO blocks, and varying layouts }
  TCastleShaderGeneratorRHI = class
  private
    FBackend: TRHIBackendType;
    function GenerateVersionAndLayoutMacros: String;
    function GenerateVersionAndLayoutMacrosForStage(const AStage: TRHIShaderStage): String;
    function GenerateStandardUniformBlocks(const AStage: TRHIShaderStage): String;
    function GenerateStageIO(const AStage: TRHIShaderStage): String;
  public
    constructor Create(const ABackend: TRHIBackendType);

    { Builds the complete preamble injected before CGE's internal GLSL templates }
    function GeneratePreamble(const AStage: TRHIShaderStage): String;

    { Builds a clean cross-backend compute shader preamble (#version 450 on Vulkan,
      #version 430 core on OpenGL, #version 310 es on OpenGLES) with unified
      CASTLE_UBO, CASTLE_SSBO, CASTLE_SAMPLER, CASTLE_IMAGE, and CASTLE_PUSH_CONSTANT
      macros plus layout(local_size_x, local_size_y, local_size_z) in; }
    function GenerateComputePreamble(const ALocalSizeX: Cardinal = 1;
      const ALocalSizeY: Cardinal = 1;
      const ALocalSizeZ: Cardinal = 1): String;

    { Builds a bindless texture/material GLSL 450 preamble using GL_EXT_nonuniform_qualifier,
      Set 1 Binding 0 unbounded/sized sampler2D array (castle_BindlessTextures[]), and
      Set 1 Binding 1 Material SSBO (CastleBindlessMaterials[]) indexed by push-constant
      or per-draw MaterialIndex for multi-material indirect rendering. }
    function GenerateBindlessPreamble(const AStage: TRHIShaderStage;
      const AMaxBindlessTextures: Cardinal = 4096): String;

    { Transforms legacy user X3D EffectPart uniform declarations into a std140 UBO
      at Set 2, Binding 1 and emits WritelnWarning diagnostics for deprecated raw
      OpenGL built-in uniforms/variables while auto-upgrading them to #version 450 }
    function UpgradeUserEffectUniforms(const UserEffectSource: String): String;

    { Extracts a unified cross-stage std140 UBO, sampler-slot, and varying-location
      layout across Vertex, Geometry, and Fragment Effect / ComposedShader parts so
      interface declarations can be packed by uniform name (independent of X3D vs GLSL
      declaration order) and custom varyings receive matching CASTLE_LOCATION indices. }
    function ExtractUserEffectLayout(
      const AVertSource, AFragSource: String;
      const AGeomSource: String = '';
      const AFirstVaryingLocation: Cardinal = 10): TUserEffectShaderLayout;

    { Upgrades a single stage's Effect / ComposedShader / ScreenEffect GLSL source
      against a unified cross-stage TUserEffectShaderLayout. }
    function UpgradeUserEffectStageSource(
      const AStage: TRHIShaderStage;
      const AStageSource: String;
      const ALayout: TUserEffectShaderLayout;
      const AFirstSamplerBinding: Cardinal = 2;
      const ASetIndex: Cardinal = 2): String;

    { Scans user Effect / EffectPart GLSL code for deprecated OpenGL built-in
      uniforms, attributes, outputs, and texture functions (e.g. gl_ModelViewProjectionMatrix,
      gl_ModelViewMatrix, gl_ProjectionMatrix, gl_NormalMatrix, gl_Vertex, gl_Normal,
      gl_MultiTexCoord0, gl_Color, gl_FragColor, texture2D, textureCube, attribute, varying),
      emits clear WritelnWarning diagnostics, and injects #version 450 compatibility aliases. }
    function UpgradeLegacyGLSLBuiltIns(const UserEffectSource: String;
      const EffectDebugName: String = 'Effect'): String; overload;
    function UpgradeLegacyGLSLBuiltIns(const UserEffectSource: String;
      const EffectDebugName: String; out AWarningsCount: Cardinal): String; overload;

    { Appends Vulkan clip-space depth adjustment (Z from [-1..1] to [0..1])
      at the end of the vertex shader main() }
    function FinalizeVertexShaderSource(const StitchedSource: String): String;

    { Appends CGE geometry shader helper implementations (geometryVertexSet,
      geometryVertexZero, geometryVertexAdd with optional PLUG_geometry_vertex_* calls)
      after the user's geometry shader code and ensures input/output layout qualifiers exist }
    function FinalizeGeometryShaderSource(
      const StitchedSource: String;
      const PlugSetCalls: String = '';
      const PlugZeroCalls: String = '';
      const PlugAddCalls: String = ''): String;

    { Strips or comments out legacy bare uniform declarations replaced by Set 0..2 UBOs and Push Constants }
    function SanitizeVulkanShaderSource(const Source: String): String;

    { Builds GLSL 450 preamble for post-processing screen effects (TCastleScreenEffects) }
    function GenerateScreenEffectPreamble(const AStage: TRHIShaderStage;
      const HasDepth: Boolean;
      const AIncludeVertexResources: Boolean = False): String;

    { Builds GLSL 450 preamble for custom 2D fragment shaders (TDrawableImage.CustomShader)
      paired with TCastleBatch2DRenderer (64-byte push constants + location 0/1 stage IO). }
    function GenerateBatch2DFragmentPreamble: String;

    { Generates a complete GLSL 450 compute shader for GPU-driven frustum & distance culling
      that populates VkDrawIndexedIndirectCommand entries and atomic visibility counters. }
    function GenerateComputeCullingShader(const AWorkgroupSizeX: Cardinal = 64): String;

    { Generates a complete GLSL 450 compute shader for Hierarchical Z (Hi-Z) depth pyramid
      mipmap reduction (conservative 2x2 max-depth reduction with odd-dimension edge handling). }
    function GenerateHiZDownsampleComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Generates glTF 2.0 / X3D PhysicalMaterial Cook-Torrance microfacet GGX BRDF functions:
      DistributionGGX, GeometrySmithGGXCorrelated, FresnelSchlick, FresnelSchlickRoughness,
      PerturbNormalCotangent (screen-space derivative TBN), PerturbNormalTBN,
      EvaluateDirectCookTorranceGGX, and EvaluateIBLCookTorranceGGX. }
    function GeneratePBRFunctions: String;

    { Generates GLSL 450 SSBO/UBO bindings and evaluation functions for 3D Clustered Forward+
      (256+ dynamic lights) and 4-cascade Directional CSM + Positional Shadow Atlas 3x3 PCF:
      ComputeClusterIndex3D, FlattenClusterIndex, SampleShadowAtlasPCF3x3,
      EvaluateDirectionalCascadeShadow, EvaluatePositionalAtlasShadow, and
      EvaluateClusteredForwardLights. }
    function GenerateClusteredForwardAndShadowFunctions: String;

    { Generates a complete GLSL 450 3D vertex shader supporting optional GPU linear-blend
      skinning (Set 2 CastleSkinningBlock) and tangent-space basis (castle_tangent_to_eye_space). }
    function GenerateDefault3DVertexShader(
      const HasSkinning: Boolean = False;
      const HasTangents: Boolean = False): String; overload;

    { Generates a complete GLSL 450 3D vertex shader declaring only the vertex attributes
      and Set 2 CastleSkinningBlock actually present on the shape, preventing Vulkan
      VUID-VkGraphicsPipelineCreateInfo-Input-07904 on unprovided attributes while
      aliasing absent attributes to safe defaults. }
    function GenerateDefault3DVertexShader(
      const HasSkinning, HasTangents, HasTexCoord1, HasColorPerVertex: Boolean): String; overload;

    { Generates the 3D vertex shader preamble with conditional vertex input attributes
      and conditional Set 2 CastleSkinningBlock. }
    function GeneratePreambleFor3DVertex(
      const AHasSkinning, AHasTangents, AHasTexCoord1, AHasColorPerVertex: Boolean): String;

    { Generates standard Set 0..1 (and optional Set 2 CastleSkinningBlock) uniform blocks. }
    function GenerateStandardUniformBlocksForStage(
      const AStage: TRHIShaderStage;
      const AIncludeSkinningUBO: Boolean): String;

    { Generates a complete GLSL 450 3D fragment shader supporting Cook-Torrance GGX PBR,
      Phong, and Unlit shading models, multi-texture sampling (BaseColor, Normal,
      MetallicRoughness, Emissive, Occlusion), normal mapping, alpha-cutoff discard,
      multi-light evaluation, Split-Sum IBL ambient lighting, optional Clustered Forward+
      (256+ lights), and optional 4-cascade CSM + Shadow Atlas PCF. }
    function GenerateDefault3DFragmentShader(
      const HasBaseColorTex: Boolean = False;
      const HasNormalTex: Boolean = False;
      const HasMetallicRoughnessTex: Boolean = False;
      const HasEmissiveTex: Boolean = False;
      const HasOcclusionTex: Boolean = False;
      const HasIBL: Boolean = False;
      const UseAlphaTest: Boolean = False;
      const HasClusteredForward: Boolean = False;
      const HasCascadedShadows: Boolean = False): String;

    { Generates a complete GLSL 450 compute shader that precomputes the 2D Split-Sum GGX
      BRDF Integration LUT (NdotV x Roughness -> Scale, Bias) using Van der Corput
      Hammersley quasi-Monte Carlo importance sampling. }
    function GenerateIBLBrdfLutComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Generates a complete GLSL 450 compute shader that subdivides the view frustum into
      a 3D exponential-depth cluster grid (e.g. 16x8x24) and bins up to 256 dynamic point,
      spot, and directional lights into per-cluster light index lists. }
    function GenerateClusteredLightCullingComputeShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 15.2: Generates a GLSL 450 compute shader for 13-tap Jiménez dual-filtering
      bloom downsample with Karis average firefly suppression and soft-knee thresholding on Mip 0. }
    function GenerateBloomDownsampleComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 15.2: Generates a GLSL 450 compute shader for 9-tap 3x3 tent-filter bloom upsample. }
    function GenerateBloomUpsampleComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 15.2: Generates a GLSL 450 compute shader that builds a 256-bin log2 luminance
      histogram and updates temporal eye-adapted exposure. }
    function GenerateLuminanceHistogramComputeShader(
      const AWorkgroupSizeX: Cardinal = 16;
      const AWorkgroupSizeY: Cardinal = 16): String;

    { Phase 15.3: Generates GLSL 450 functions for Reinhard, ACES Filmic (Narkowicz RRT+ODT),
      and AgX (Sobotka inset + log2 sigmoid + outset) tonemapping, saturation/contrast grading,
      and IEC 61966-2-1 Linear-to-sRGB transfer. }
    function GenerateTonemappingAndColorGradingFunctions: String;

    { Phase 15.3: Generates a complete GLSL 450 fragment shader for the HDR Post-Processing
      Composite pass (combining HDR scene color, mip-chain bloom, adapted exposure, color grading,
      ACES/AgX tonemapping, and sRGB output). }
    function GenerateHDRCompositeFragmentShader: String;

    { Phase 16.1: Generates a GLSL 450 compute shader for Ground-Truth Ambient Occlusion (GTAO),
      reconstructing view-space positions and normals from depth and integrating multi-slice
      horizon angles with cosine-weighted analytical visibility. }
    function GenerateGTAOComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 16.1: Generates a GLSL 450 compute shader for 5x5 depth- and normal-aware
      cross-bilateral spatial denoising of the GTAO visibility buffer. }
    function GenerateGTAODenoiseComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 16.2: Generates a GLSL 450 compute shader for Hierarchical-Z Screen-Space Reflections
      (Hi-Z SSR), raymarching reflection rays against the min-depth Hi-Z mip pyramid with
      roughness attenuation, Schlick Fresnel weighting, and screen-edge vignette fade. }
    function GenerateHiZSSRComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 16.3: Generates a GLSL 450 3D compute shader that injects exponential height fog
      density, Henyey-Greenstein anisotropic sun scattering, and extinction into the
      3D camera-aligned froxel volume texture. }
    function GenerateVolumetricFogInjectComputeShader(
      const AWorkgroupSizeX: Cardinal = 4;
      const AWorkgroupSizeY: Cardinal = 4;
      const AWorkgroupSizeZ: Cardinal = 4): String;

    { Phase 16.3: Generates a GLSL 450 compute shader that raymarches front-to-back along
      each (x, y) froxel column using Beer-Lambert analytical step integration. }
    function GenerateVolumetricFogRaymarchComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 17.1: Generates a GLSL 450 compute shader for Temporal Anti-Aliasing (TAA) resolve
      with 3x3 neighborhood YCoCg variance clipping, 5-tap Catmull-Rom bicubic history resampling,
      and velocity-based disocclusion weighting. }
    function GenerateTAAResolveComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 17.2: Generates GLSL 450 functions and UBO/SSBO bindings for localized Reflection Probes
      with Box-Projected Parallax ray-AABB intersection (EvaluateBoxProjectedDirection) and
      distance-based trilinear probe blending (EvaluateProbeInfluenceWeight). }
    function GenerateBoxProjectedReflectionProbeFunctions: String;

    { Phase 17.3: Generates GLSL 450 functions and UBO/SSBO bindings for Oriented Bounding Box (OBB)
      Decal Projection (ProjectWorldPointToDecalUV, EvaluateDecalAngleAndBoxFade). }
    function GenerateClusteredDecalProjectionFunctions: String;

    { Phase 18.1: Generates a GLSL 450 compute shader for GPU particle simulation (semi-implicit
      Euler gravity/drag integration, ground-plane bounce collision, and atomic alive-list
      compaction populating VkDrawIndirectCommand). }
    function GenerateParticleSimulationComputeShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 18.2: Generates GLSL 450 functions for McGuire & Bavoil Weighted Blended
      Order-Independent Transparency (EvaluateOITDepthWeight, AccumulateWeightedBlendedOIT,
      EvaluateOITComposite). }
    function GenerateWeightedBlendedOITFunctions: String;

    { Phase 18.2: Generates a complete GLSL 450 fragment shader for compositing Weighted Blended
      OIT accumulation (pfRGBA16_Float) and revealage (pfR16_Float) targets over the opaque HDR scene. }
    function GenerateWeightedBlendedOITCompositeFragmentShader: String;

    { Phase 18.3: Generates a GLSL 450 compute shader for Screen-Space Raymarched Contact Shadows
      along the primary directional light vector with depth-thickness validation and edge fade. }
    function GenerateContactShadowsComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 19.1: Generates a GLSL 450 compute shader for Skeletal Linear-Blend Skinning (LBS)
      combined with up to 4 Morph Target displacements and previous-frame vertex position output. }
    function GenerateComputeSkinningShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 19.2: Generates GLSL 450 vertex shader functions for Continuous Distance-Dependent
      LOD (CDLOD) terrain quadtree morphing (EvaluateCDLODMorphFactor, MorphCDLODGridVertex). }
    function GenerateTerrainCDLODFunctions: String;

    { Phase 19.3: Generates GLSL 450 PBR functions for Pre-Integrated Wrap-Diffuse Subsurface
      Scattering (EvaluateSubsurfaceWrapDiffuse) and Thin-Foliage Back-Lit Transmission
      (EvaluateFoliageTransmission). }
    function GenerateSubsurfaceAndTransmissionPBRFunctions: String;

    { Phase 19.3 CPU reference: Evaluates wrap-diffuse subsurface scattering with energy normalization. }
    class function EvaluateSubsurfaceWrapDiffuse(
      const ANdotL, AWrapFactor: Single;
      const AScatterColor: TVector3): TVector3; static;

    { Phase 19.3 CPU reference: Evaluates back-lit foliage/cloth translucent transmission. }
    class function EvaluateFoliageTransmission(
      const AViewDir, ALightDir, ASurfaceNormal, ATransmissionTint: TVector3;
      const AThickness, ADistortion, APower, AScale: Single): TVector3; static;

    { Phase 20.1: Generates GLSL 450 PBR functions for Multi-Layer Clear Coat
      (EvaluateClearCoatBRDF) and Stretched Tangent/Bitangent Anisotropic GGX
      Microfacet Distribution (EvaluateAnisotropicGGX_D). }
    function GenerateClearCoatAndAnisotropicPBRFunctions: String;

    { Phase 20.1 CPU reference: Evaluates secondary IOR=1.5 (F0=0.04) Clear Coat specular lobe
      and energy-conserving base-layer attenuation (1.0 - F_cc). }
    class procedure EvaluateClearCoatBRDF(
      const ACNdotH, ACNdotL, ACNdotV, AVdotH, AClearCoatFactor, AClearCoatRoughness: Single;
      out AClearCoatSpecular, ABaseLayerAttenuation: Single); static;

    { Phase 20.1 CPU reference: Evaluates anisotropic Trowbridge-Reitz GGX normal distribution D_aniso. }
    class function EvaluateAnisotropicGGX_D(
      const ANdotH, ATdotH, ABdotH, ARoughness, AAnisotropy: Single): Single; static;

    { Phase 20.2: Generates a GLSL 450 compute shader for baking the Rayleigh / Mie
      single-scattering physical sky-view LUT (rgba16f). }
    function GenerateAtmosphereSkyComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 20.2 CPU reference: Evaluates Rayleigh molecular phase function Phi_R(cosTheta). }
    class function EvaluateRayleighPhase(const ACosTheta: Single): Single; static;

    { Phase 20.2 CPU reference: Evaluates Cornette-Shanks aerosol Mie phase function Phi_M(cosTheta, g). }
    class function EvaluateCornetteShanksMiePhase(const ACosTheta, AG: Single): Single; static;

    { Phase 20.3: Generates GLSL 450 post-processing functions for Screen-Space Multi-Ghost
      Lens Flare and Radial Spectral Chromatic Aberration. }
    function GenerateLensFlareAndChromaticAberrationFunctions: String;

    { Phase 20.3 CPU reference: Computes R, G, B radial dispersion UV coordinates for chromatic aberration. }
    class procedure EvaluateChromaticAberrationOffsets(
      const AUV: TVector2; const AIntensity: Single;
      out ARedUV, AGreenUV, ABlueUV: TVector2); static;

    { Phase 20.3 CPU reference: Computes reflected ghost sample UV and radial window weight for lens flare ghosting. }
    class procedure EvaluateLensFlareGhostUV(
      const AUV: TVector2; const AGhostIndex: Integer; const AGhostSpacing: Single;
      out AGhostUV: TVector2; out ARadialWeight: Single); static;

    { Phase 21.1: Generates GLSL 450 PBR functions for Velvet/Cloth Estevez-Kulla Charlie
      Sheen (EvaluateCharlieSheen_D) and Thin-Film Spectral Iridescence (EvaluateThinFilmIridescence). }
    function GenerateClothSheenAndIridescencePBRFunctions: String;

    { Phase 21.1 CPU reference: Evaluates Estevez & Kulla (2017) "Charlie" microfiber sheen NDF. }
    class function EvaluateCharlieSheen_D(const ANdotH, ASheenRoughness: Single): Single; static;

    { Phase 21.1 CPU reference: Evaluates Airy thin-film optical path difference spectral interference. }
    class function EvaluateThinFilmIridescence(
      const ACosTheta1, AIridescenceIOR, AThicknessNanometers: Single): TVector3; static;

    { Phase 21.2: Generates a GLSL 450 compute shader for Multi-Octave Trochoidal Gerstner
      Ocean Wave Displacement, Analytical Normals & Jacobian Whitecap Foam. }
    function GenerateOceanDisplacementComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 21.3: Generates GLSL 450 post-processing functions for Thin-Lens Bokeh Depth of Field
      Circle of Confusion (EvaluateThinLensCoC) and Per-Pixel Velocity Motion Blur
      (EvaluateMotionBlurSampleWeight). }
    function GenerateMotionBlurAndBokehDoFFunctions: String;

    { Phase 21.3 CPU reference: Evaluates signed thin-lens Circle of Confusion (CoC) in pixels. }
    class function EvaluateThinLensCoC(
      const ALinearDepth, AFocusDistance, AFocalLength, AApertureFStop, AMaxCoCRadius: Single): Single; static;

    { Phase 21.3 CPU reference: Evaluates McGuire velocity-line motion blur sample weight with depth ordering. }
    class function EvaluateMotionBlurSampleWeight(
      const ASampleOffsetPixels, ASampleVelocityLengthPixels, ACenterDepth, ASampleDepth, ADepthSoftness: Single): Single; static;

    { Phase 22.1: Generates GLSL 450 functions for Dynamic Diffuse Global Illumination (DDGI)
      Octahedral Probe Encoding/Decoding and Chebyshev Visibility Trilinear Probe Weighting. }
    function GenerateDDGIProbeSamplingFunctions: String;

    { Phase 22.1 CPU reference: Encodes a normalized 3D direction into [-1, 1]^2 octahedral coordinates. }
    class function OctahedralEncodeDir(const ADir: TVector3): TVector2; static;

    { Phase 22.1 CPU reference: Decodes [-1, 1]^2 octahedral coordinates back to a normalized 3D direction. }
    class function OctahedralDecodeUV(const AOctUV: TVector2): TVector3; static;

    { Phase 22.1 CPU reference: Evaluates DDGI probe weight with wrap cosine and Chebyshev variance visibility. }
    class function EvaluateDDGIProbeWeight(
      const AWorldPos, ASurfaceNormal, AProbePos: TVector3;
      const AProbeMeanDist, AProbeVariance: Single): Single; static;

    { Phase 22.2: Generates a GLSL 450 compute shader for GPU Meshlet / Sub-Mesh Cluster
      Bounding-Sphere & Normal-Cone Backface Culling. }
    function GenerateMeshletCullingComputeShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 22.2 CPU reference: Returns True if the meshlet normal cone is 100% backfacing to ACameraPosition. }
    class function EvaluateMeshletConeBackfaceCull(
      const AMeshletCenter, ACameraPosition, AConeAxis: TVector3;
      const AConeCutoff: Single): Boolean; static;

    { Phase 22.3: Generates GLSL 450 functions for AMD FidelityFX Contrast-Adaptive Sharpening
      (EvaluateCASFilter5Tap) and Edge-Adaptive Spatial Upscaling. }
    function GenerateCASSharpeningAndUpscaleFunctions: String;

    { Phase 22.3 CPU reference: Evaluates 5-tap Contrast-Adaptive Sharpening (CAS) without halo ringing. }
    class function EvaluateCASFilter5Tap(
      const ACenter, ANorth, ASouth, AEast, AWest: TVector3;
      const ASharpness: Single): TVector3; static;

    { Phase 23.1: Generates GLSL 450 functions for Hardware Inline Ray Query (VK_KHR_ray_query)
      and Software BVH Ray-AABB / Möller-Trumbore Ray-Triangle Intersection. }
    function GenerateInlineRayQueryFunctions(
      const AUseHardwareRayQueryExt: Boolean = True): String;

    { Phase 23.1 CPU reference: Evaluates slab Ray-AABB intersection within [ATMin, ATMax]. }
    class function EvaluateRayAABBIntersection(
      const ARayOrigin, ARayDir, ABoxMin, ABoxMax: TVector3;
      const ATMin, ATMax: Single;
      out AHitTNear, AHitTFar: Single): Boolean; static;

    { Phase 23.1 CPU reference: Evaluates Möller-Trumbore Ray-Triangle intersection within [ATMin, ATMax]. }
    class function EvaluateRayTriangleIntersection(
      const ARayOrigin, ARayDir, AV0, AV1, AV2: TVector3;
      const ATMin, ATMax: Single;
      out AHitT, ABaryU, ABaryV: Single): Boolean; static;

    { Phase 23.2: Generates GLSL 450 functions for Virtual Shadow Map (VSM) Page Table
      decoding and Virtual-to-Physical Tile Pool UV translation. }
    function GenerateVSMPageLookupFunctions: String;

    { Phase 23.3: Generates GLSL 450 functions for Separable Screen-Space Subsurface
      Scattering (SSSSS) Christensen-Burley Diffusion Profile and Bilateral Depth Weighting. }
    function GenerateSeparableSSSSFunctions: String;

    { Phase 23.3 CPU reference: Evaluates Christensen-Burley normalized diffusion profile R(r, d). }
    class function EvaluateBurleyDiffusionProfile(
      const ARadiusMillimeters: Single;
      const AScatterDistanceRGB: TVector3): TVector3; static;

    { Phase 23.3 CPU reference: Evaluates depth-aware bilateral SSSSS weight. }
    class function EvaluateBilateralSSSSWeight(
      const ASampleOffsetMillimeters, ADepthDiffMeters, AScatterDist, ADepthFalloffScale: Single): Single; static;

    { Phase 24.1: Generates a GLSL 450 compute shader for GPU-Driven Continuous Instance
      LOD Selection using projected vertical screen-height coverage and dither crossfade. }
    function GenerateLODSelectionComputeShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 24.1 CPU reference: Evaluates normalized vertical screen-height coverage
      in [0..1] for a bounding sphere of ARadius at distance ADistance. }
    class function EvaluateProjectedScreenCoverage(
      const ADistance, ARadius, ACotHalfFovY: Single): Single; static;

    { Phase 24.1 CPU reference: Selects discrete LOD level (0..3, or -1 if culled)
      and computes continuous crossfade transition weight in [0..1]. }
    class function SelectDiscreteLODLevel(
      const AScreenCoverage: Single;
      const AThresholds: TVector4;
      out ACrossfadeWeight: Single;
      const ATransitionBand: Single = 0.02): Integer; static;

    { Phase 24.2: Generates GLSL 450 functions for Screen-Space Bent Normals and
      Lagarde/Jimenez Cone-Intersection Specular Occlusion. }
    function GenerateBentNormalsAndSpecularOcclusionFunctions: String;

    { Phase 24.2 CPU reference: Evaluates Lagarde/Jimenez Specular Occlusion from NdotV, AO, and Roughness. }
    class function EvaluateSpecularOcclusion(
      const ANdotV, AAmbientOcclusion, ARoughness: Single): Single; static;

    { Phase 24.2 CPU reference: Bends surface shading normal toward unoccluded bent horizon normal based on AO. }
    class function BendNormalTowardsUnoccludedDir(
      const ASurfaceNormal, AUnoccludedBentDir: TVector3;
      const AAmbientOcclusion: Single): TVector3; static;

    { Phase 24.3: Generates GLSL 450 functions for Trilinear 3D Color Grading LUT (sampler3D)
      half-texel coordinate mapping, Natural cos^4(theta) Vignette, and Luminance-Preserving Film Grain. }
    function GenerateColorGradingLUTAndFilmGrainFunctions: String;

    { Phase 24.3 CPU reference: Maps [0..1]^3 RGB color to half-texel-centered 3D LUT UVW coordinates. }
    class function Compute3DLUTSampleCoord(
      const AColorRGB: TVector3;
      const ALutDimension: Single = 32.0): TVector3; static;

    { Phase 24.3 CPU reference: Evaluates natural optical cos^4(theta) lens vignette falloff. }
    class function EvaluateNaturalCos4Vignette(
      const AUV: TVector2;
      const AIntensity: Single): Single; static;

    { Phase 24.3 CPU reference: Applies luminance-preserving spatio-temporal film grain. }
    class function EvaluateFilmGrainNoise(
      const AColor: TVector3;
      const AUV: TVector2;
      const ATimeSeconds, AIntensity: Single): TVector3; static;

    { Phase 25.1: Generates GLSL 450 functions for Horizon-Aligned Volumetric Cloud
      Raymarching (Dual-Lobe Henyey-Greenstein Phase & Schneider Beer-Powder Law). }
    function GenerateVolumetricCloudFunctions: String;

    { Phase 25.1 CPU reference: Evaluates Dual-Lobe Henyey-Greenstein scattering phase function. }
    class function EvaluateDualLobeHGPhase(
      const ACosTheta, AForwardG, ABackwardG, AForwardWeight: Single): Single; static;

    { Phase 25.1 CPU reference: Evaluates Schneider's Beer-Powder cloud transmittance & dark-edge effect. }
    class function EvaluateBeerPowderTransmittance(
      const AOpticalDepth, APowderStrength: Single): Single; static;

    { Phase 25.2: Generates GLSL 450 functions for GPU Texture Streaming Mipmap
      Residency Feedback (atomicMin desired mip recording from screen-space UV derivatives). }
    function GenerateTextureMipFeedbackFunctions: String;

    { Phase 25.2 CPU reference: Computes desired mipmap level from max texel footprint derivative. }
    class function ComputeDesiredMipLevel(
      const ATexelFootprintMaxDerivative: Single;
      const AMaxMipLevel: Cardinal;
      const AMipBias: Single = 0.0): Cardinal; static;

    { Phase 25.3: Generates a GLSL 450 compute shader that converts a 2:1 Equirectangular
      HDR panorama texture into a 6-face Cubemap (tdCube) texture. }
    function GenerateEquirectToCubemapComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 25.3 CPU reference: Maps a normalized 3D direction vector to 2:1 equirectangular UV in [0..1]^2. }
    class function DirectionToEquirectangularUV(const ADir: TVector3): TVector2; static;

    { Phase 25.3 CPU reference: Inverse-maps 2:1 equirectangular UV in [0..1]^2 to a normalized 3D direction. }
    class function EquirectangularUVToDirection(const AUV: TVector2): TVector3; static;

    { Phase 26.1: Generates GLSL 450 functions for Analytic Rectangular Area Lights
      via Linearly Transformed Cosines (LTC) & Baum/Lambert Solid-Angle Integration. }
    function GenerateAreaLightLTCFunctions: String;

    { Phase 26.1 CPU reference: Evaluates subtended solid angle in [0..2*Pi] of a 3D rectangular area light. }
    class function EvaluateRectAreaLightSolidAngle(
      const ASurfacePos, ARectCenter, ARectRight, ARectUp: TVector3;
      const AHalfWidth, AHalfHeight: Single): Single; static;

    { Phase 26.1 CPU reference: Evaluates solid-angle-widened effective roughness for area lights. }
    class function EvaluateLTCFilteredRoughness(
      const ABaseRoughness, ADistanceToAreaLight, AAreaExtentRadius: Single): Single; static;

    { Phase 26.2: Generates GLSL 450 functions for Seamless World-Space Triplanar
      Projection and Height-Modulated Multi-Layer Splat Blending. }
    function GenerateTriplanarAndHeightBlendFunctions: String;

    { Phase 26.2 CPU reference: Evaluates power-sharpened normalized triplanar blend weights (w.x + w.y + w.z = 1). }
    class function EvaluateTriplanarBlendWeights(
      const AWorldNormal: TVector3;
      const ASharpness: Single = 4.0): TVector3; static;

    { Phase 26.2 CPU reference: Evaluates height-map-modulated 4-layer splat blend weights. }
    class function EvaluateHeightModulatedBlendWeights(
      const ALayerWeights, ALayerHeights: TVector4;
      const AHeightContrast: Single = 0.2): TVector4; static;

    { Phase 26.3: Generates a GLSL 450 compute shader for GPU Shadow Caster Light-Ray
      Extrusion Culling against the receiver camera frustum AABB. }
    function GenerateShadowCasterExtrusionCullingComputeShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 26.3 CPU reference: Tests whether a shadow-caster sphere extruded along
      ALightRayDir for [0..AMaxExtrusionDist] intersects [AReceiverBoxMin, AReceiverBoxMax]. }
    class function EvaluateShadowCasterExtrudedSphereIntersectsAABB(
      const ASphereCenter: TVector3;
      const ASphereRadius: Single;
      const ALightRayDir: TVector3;
      const AMaxExtrusionDist: Single;
      const AReceiverBoxMin, AReceiverBoxMax: TVector3): Boolean; static;

    { Phase 27.1: Generates GLSL 450 functions for a 64-Bit Visibility Buffer
      (Depth32 | InstanceID20 | PrimitiveID12) and Analytic Perspective-Correct Barycentrics. }
    function GenerateVisibilityBufferFunctions: String;

    { Phase 27.1 CPU reference: Packs Depth01 (32b), InstanceID (20b), and PrimitiveID (12b) into 64-bit payload. }
    class function PackVisibilityBufferPayload(
      const ADepth01: Single;
      const AInstanceID, APrimitiveID: Cardinal): QWord; static;

    { Phase 27.1 CPU reference: Unpacks Depth01, InstanceID, and PrimitiveID from 64-bit visibility payload. }
    class procedure UnpackVisibilityBufferPayload(
      const APayload: QWord;
      out AOutDepth01: Single;
      out AOutInstanceID, AOutPrimitiveID: Cardinal); static;

    { Phase 27.1 CPU reference: Evaluates perspective-correct 2D barycentric weights (lambda0 + lambda1 + lambda2 = 1). }
    class function EvaluatePerspectiveBarycentrics2D(
      const APixelNDC, AV0NDC, AV1NDC, AV2NDC: TVector2;
      const AInvW0, AInvW1, AInvW2: Single): TVector3; static;

    { Phase 27.2: Generates a GLSL 450 compute shader for Nanite-style Hierarchical
      Cluster DAG Cut Selection (ParentProjectedError > Threshold >= SelfProjectedError). }
    function GenerateClusterDAGCutComputeShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 27.2 CPU reference: Evaluates projected screen-space geometric error in pixels. }
    class function EvaluateClusterProjectedErrorPixels(
      const ASphereCenter, ACameraPos: TVector3;
      const ASphereRadius, AWorldError, ACotHalfFovY, AViewportHeight: Single): Single; static;

    { Phase 27.2 CPU reference: Returns True iff this cluster node lies on the active crack-free DAG cut. }
    class function IsClusterDAGCutNode(
      const ASelfProjectedErrorPx, AParentProjectedErrorPx, APixelErrorThreshold: Single): Boolean; static;

    { Phase 27.3: Generates a GLSL 450 compute shader for Sub-Pixel Software Compute
      Micro-Polygon Rasterization using 2D edge functions and 64-bit atomic visibility writes. }
    function GenerateSoftwareMicroRasterComputeShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 27.3 CPU reference: Evaluates 2D signed edge determinant (B.x-A.x)*(P.y-A.y) - (B.y-A.y)*(P.x-A.x). }
    class function EvaluateEdgeFunction2D(
      const AA, AB, AP: TVector2): Single; static;

    { Phase 27.3 CPU reference: Returns True when a front-facing triangle's 2D screen AABB fits within AMaxBoxPixels. }
    class function IsMicroTriangleCandidateForSoftwareRaster(
      const AV0Screen, AV1Screen, AV2Screen: TVector2;
      const AMaxBoxPixels: Single = 16.0): Boolean; static;

    { Phase 28.1: Generates GLSL 450 functions for Lumen-style Global Signed Distance Field (SDF)
      box evaluation, polynomial smooth union, 3D clipmap UVW mapping, and soft cone tracing. }
    function GenerateGlobalSDFTraceFunctions: String;

    { Phase 28.1 CPU reference: Exact signed distance from ASamplePos to an axis-aligned box. }
    class function EvaluateSDFBoxDistance(
      const ASamplePos, ABoxCenter, ABoxHalfExtents: TVector3): Single; static;

    { Phase 28.1 CPU reference: Polynomial smooth minimum (smin) of two SDF distances. }
    class function EvaluateSDFSmoothUnion(
      const AD1, AD2, AK: Single): Single; static;

    { Phase 28.1 CPU reference: Updates soft cone-traced visibility / sky occlusion along an SDF ray. }
    class function EvaluateSDFSoftShadowCone(
      const ACurrentVisibility, ASDFDistance, ARayDistance, AConeTanHalfAngle: Single): Single; static;

    { Phase 28.2: Generates GLSL 450 functions for Lumen-style 6-Axis Surface Cache Card
      dominant axis selection and 2D card atlas UV projection. }
    function GenerateSurfaceCacheCardFunctions: String;

    { Phase 28.2 CPU reference: Selects dominant card axis 0..5 (+X, -X, +Y, -Y, +Z, -Z) for AWorldNormal. }
    class function SelectDominantSurfaceCardAxis(
      const AWorldNormal: TVector3): Cardinal; static;

    { Phase 28.2 CPU reference: Projects local hit point onto card axis tangent plane and maps to atlas UV. }
    class function ComputeSurfaceCacheAtlasUV(
      const ALocalHitPos, ABoxHalfExtents: TVector3;
      const ACardAxis: Cardinal;
      const ACardAtlasOffsetUV, ACardAtlasScaleUV: TVector2): TVector2; static;

    { Phase 28.3: Generates GLSL 450 functions for Screen-Space Radiance Cache bilateral
      probe interpolation and cosine-weighted hemisphere importance sampling. }
    function GenerateScreenRadianceCacheFunctions: String;

    { Phase 28.3 CPU reference: Plane-distance and normal-aware bilateral weight for screen probe interpolation. }
    class function EvaluateScreenProbeBilateralWeight(
      const APixelWorldPos, APixelNormal, AProbeWorldPos, AProbeNormal: TVector3;
      const APlaneDistSensitivity: Single = 10.0): Single; static;

    { Phase 28.3 CPU reference: Cosine-weighted hemisphere sample (Z-up tangent space) with PDF = cos(theta)/pi. }
    class function CosineWeightedHemisphereSample(
      const AXi: TVector2;
      out AOutPdf: Single): TVector3; static;

    { Phase 29.1: Generates GLSL 450 functions and structs for ReSTIR Weighted Reservoir
      Sampling (WRS), Streaming Resampled Importance Sampling (RIS), and Temporal/Spatial
      Reservoir Combination (UE5 MegaLights architecture). }
    function GenerateReSTIRReservoirFunctions: String;

    { Phase 29.2: Generates a GLSL 450 compute shader for ReSTIR Spatio-Temporal Reservoir
      Resampling across temporal history and spatial neighbors with depth/normal edge rejection. }
    function GenerateReSTIRSpatialTemporalComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 29.1 CPU reference: Initializes an empty ReSTIR reservoir (SelectedLightID = -1). }
    class procedure InitReSTIRReservoir(out AReservoir: TCastleReSTIRReservoir); static;

    { Phase 29.1 CPU reference: Evaluates Rec.709 luminance target PDF p_hat(x) for unshadowed light contribution. }
    class function EvaluateLuminanceTargetPDF(
      const AUnshadowedContribution: TVector3): Single; static;

    { Phase 29.1 CPU reference: Streams a single candidate light sample into AReservoir using WRS/RIS. }
    class function UpdateReservoirSample(
      var AReservoir: TCastleReSTIRReservoir;
      const ACandidateLightID: Integer;
      const ATargetPDF, ASourcePDF, ARandom01: Single): Boolean; static;

    { Phase 29.1 CPU reference: Caps SampleCountM to AMaxHistoryM and computes unbiased ContributionWeightW. }
    class procedure FinalizeReservoirWeight(
      var AReservoir: TCastleReSTIRReservoir;
      const AMaxHistoryM: Cardinal = 20); static;

    { Phase 29.2 CPU reference: Returns True when a temporal/spatial neighbor passes depth & normal similarity thresholds. }
    class function EvaluateReSTIRNeighborSimilarity(
      const ACenterDepth: Single;
      const ACenterNormal: TVector3;
      const ANeighborDepth: Single;
      const ANeighborNormal: TVector3;
      const AMaxRelativeDepthDiff: Single = 0.1;
      const AMinNormalCos: Single = 0.9): Boolean; static;

    { Phase 29.2 CPU reference: Combines ANeighbor reservoir into ADst with M-capping and target PDF re-evaluation. }
    class function CombineReservoirs(
      var ADst: TCastleReSTIRReservoir;
      const ANeighbor: TCastleReSTIRReservoir;
      const ANeighborTargetPDFAtCenter: Single;
      const AMaxHistoryM: Cardinal;
      const ARandom01: Single): Boolean; static;

    { Phase 30.1: Generates a GLSL 450 compute shader for Temporal Super Resolution (TSR)
      sub-pixel history upscaling using Lanczos-2 / Blackman-Harris reconstruction kernels,
      parallax disocclusion confidence, and thin-feature anti-ghosting. }
    function GenerateTSRUpscaleComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Phase 30.1 CPU reference: Evaluates windowed Lanczos-2 sinc kernel L(x) = sinc(x)*sinc(x/2) for |x| < 2. }
    class function EvaluateLanczos2Weight(const AX: Single): Single; static;

    { Phase 30.1 CPU reference: Evaluates 4-term Blackman-Harris window for |x| < ARadius. }
    class function EvaluateBlackmanHarrisWeight(
      const AX: Single;
      const ARadius: Single = 1.0): Single; static;

    { Phase 30.2 CPU reference: Evaluates temporal history confidence [0..1] from relative depth mismatch. }
    class function EvaluateTSRDisocclusionConfidence(
      const ACurrentLinearDepth, AReprojectedLinearDepth: Single;
      const AMaxRelativeDepthError: Single = 0.05): Single; static;

    { Phase 30.2 CPU reference: Boosts current-frame responsiveness [0..1] on thin sub-pixel geometry (wires/foliage/hair). }
    class function EvaluateTSRThinGeometryBlend(
      const ABaseCurrentFrameBlend, ADepthCrossLaplacian, ALumaContrast: Single): Single; static;

    { Phase 31.1: Generates GLSL 450 functions for UE5 Substrate/Strata Energy-Conserving
      Layered Material Slabs (directional slab albedo & Beer-Lambert medium transmittance). }
    function GenerateSubstrateLayeredMaterialFunctions: String;

    { Phase 31.1 CPU reference: Evaluates directional slab reflectance albedo E(mu, roughness) in [0..1]. }
    class function EvaluateDirectionalSlabAlbedo(
      const AF0, ANdotV, ARoughness: Single): Single; static;

    { Phase 31.1 CPU reference: Energy-conserving vertical composition of a top coating/medium slab over a bottom substrate slab. }
    class function EvaluateLayeredSlabComposition(
      const ATopLobeRadiance, ABottomLobeRadiance, AExtinctionSigmaT: TVector3;
      const ATopF0, ATopRoughness, ANdotV, ANdotL, ASlabThickness: Single): TVector3; static;

    { Phase 31.2: Generates GLSL 450 functions for Marschner / Chiang Dual-Specular
      Hair & Fur Fiber BSDF (longitudinal R, TT, TRT cuticle-tilted lobes and Beer-Lambert absorption). }
    function GenerateHairMarschnerBSDF: String;

    { Phase 31.2 CPU reference: Normalized longitudinal Gaussian lobe M(theta_h - shift) for hair fibers. }
    class function EvaluateMarschnerLongitudinalM(
      const ASinThetaI, ASinThetaO, ACuticleShiftRad, ALongitudinalRoughnessBeta: Single): Single; static;

    { Phase 31.2 CPU reference: Evaluates combined Marschner R + TT + TRT hair fiber scattering RGB. }
    class function EvaluateHairDualSpecularBSDF(
      const AHairAbsorptionSigmaA: TVector3;
      const ASinThetaI, ASinThetaO, ACosPhiD, ACuticleTiltRad, APrimaryRoughnessBeta: Single): TVector3; static;

    { Phase 31.3: Generates GLSL 450 functions for Stochastic Discrete Microfacet Glints & Sparkles. }
    function GenerateStochasticGlintFunctions: String;

    { Phase 31.3 CPU reference: Evaluates discrete microfacet glint NDF amplification for metallic paint/snow/minerals. }
    class function EvaluateStochasticGlintNDF(
      const ANdotH, AMacroRoughness, AFlakeAlignment01, AGlintDensity, AGlintSharpness: Single): Single; static;

    { Phase 32.1: Generates a GLSL 450 Mesh Shader stage (GL_EXT_mesh_shader) emitting
      meshlet vertices and primitive triangle indices via SetMeshOutputsEXT. }
    function GenerateMeshShaderStageFunctions(
      const AMaxVertices: Cardinal = 64;
      const AMaxPrimitives: Cardinal = 124;
      const AWorkgroupSizeX: Cardinal = 32): String;

    { Phase 32.1 CPU reference: Computes task shader workgroup count for ATotalMeshletCount. }
    class function ComputeMeshletTaskGroupCount(
      const ATotalMeshletCount: Cardinal;
      const AMeshletsPerTaskGroup: Cardinal = 32): Cardinal; static;

    { Phase 32.2: Generates a GLSL 450 compute shader for VK_KHR_fragment_shading_rate
      tile-based Variable Rate Shading (1x1, 2x1, 1x2, 2x2, 4x4) driven by luma contrast & motion. }
    function GenerateVRSContrastComputeShader(
      const ATileSize: Cardinal = 16): String;

    { Phase 32.2 CPU reference: Selects optimal shading rate code (0=1x1, 1=2x1, 4=1x2, 5=2x2, 10=4x4). }
    class function SelectOptimalShadingRateTile(
      const ALumaContrastX, ALumaContrastY, AVelocityPixels: Single;
      const AHighContrastThreshold: Single = 0.20;
      const ALowContrastThreshold: Single = 0.04): Cardinal; static;

    { Phase 32.3: Generates GLSL 450 functions for Runtime Virtual Texturing (RVT)
      virtual-to-physical page translation with bilinear border padding. }
    function GenerateRVTLookupFunctions: String;

    { Phase 32.3 CPU reference: Translates in-page UV [0..1]^2 and physical tile (X,Y) into physical RVT atlas UV. }
    class function TranslateRVTPageToPhysicalUV(
      const AInPageUV: TVector2;
      const APhysicalTileX, APhysicalTileY, APhysicalTilesPerRow: Cardinal;
      const ABorderTexelFraction: Single = 0.03125): TVector2; static;

    { Phase 33.1: Generates GLSL 450 functions for Physically Based Single-Layer Water
      (Beer-Lambert RGB optical absorption, Snell screen-space refraction offset, and photon caustics). }
    function GenerateSingleLayerWaterFunctions: String;

    { Phase 33.1 CPU reference: Evaluates Beer-Lambert spectral water transmittance exp(-sigma_a * depth). }
    class function EvaluateWaterBeerLambertAbsorption(
      const AAbsorptionCoeffRGB: TVector3;
      const AOpticalDepthMeters: Single): TVector3; static;

    { Phase 33.1 CPU reference: Computes depth-faded Snell screen-space refraction UV offset. }
    class function ComputeWaterRefractionUVOffset(
      const AViewSpaceNormal: TVector3;
      const AWaterDepthMeters, AIORRatio, ARefractionStrength: Single): TVector2; static;

    { Phase 33.1 CPU reference: Evaluates animated dual-wave interference underwater photon caustics. }
    class function EvaluateWaterCausticsPattern(
      const AWorldXZ: TVector2;
      const ATimeSeconds, AWaterDepthMeters: Single): Single; static;

    { Phase 33.2: Generates GLSL 450 functions for Sparse Heterogeneous Volume Brick Atlas
      lookup and physically based Planckian Blackbody temperature-to-RGB emission. }
    function GenerateSparseVolumeBlackbodyFunctions: String;

    { Phase 33.2 CPU reference: Converts temperature in Kelvin (e.g. 1000K..10000K) to Planckian blackbody RGB radiance. }
    class function EvaluateBlackbodyEmissionRGB(
      const ATemperatureKelvin: Single;
      const AIntensity: Single = 1.0): TVector3; static;

    { Phase 34.1: Generates GLSL 450 functions for Spatio-Temporal Variance-Guided Filtering (SVGF)
      temporal luminance moment accumulation (E[L], E[L^2]) and variance estimation. }
    function GenerateSVGFVarianceMomentsFunctions: String;

    { Phase 34.1 CPU reference: Evaluates first and second luminance moments (L, L^2) from linear RGB radiance. }
    class function EvaluateLuminanceMoments(const ARadianceRGB: TVector3): TVector2; static;

    { Phase 34.1 CPU reference: Computes temporal variance max(0, M2 - M1^2) from exponentially blended moments. }
    class function ComputeTemporalVariance(const AMoments: TVector2): Single; static;

    { Phase 34.2: Generates GLSL 450 functions for SVGF Edge-Stopping A-Trous Wavelet
      Spatial Filtering (normal, depth-gradient, and variance-guided luminance weights)
      and Specular Ray Hit-Distance Contact Hardening. }
    function GenerateSVGFAttrousWaveletFunctions: String;

    { Phase 34.2 CPU reference: Evaluates combined SVGF edge-stopping weight w_z * w_n * w_l in [0..1]. }
    class function EvaluateSVGFEdgeStoppingWeight(
      const ACenterNormal, ASampleNormal: TVector3;
      const ACenterDepth, ASampleDepth, ADepthGradientDotOffset: Single;
      const ACenterLuma, ASampleLuma, AVariance: Single;
      const APhiDepth: Single = 1.0;
      const APhiNormal: Single = 128.0;
      const APhiLuma: Single = 4.0): Single; static;

    { Phase 34.3 CPU reference: Evaluates contact-hardening reflection kernel factor [0..1] from ray hit distance and roughness. }
    class function EvaluateHitDistanceBlurFactor(
      const ARayHitDistance, ACameraDistance, ARoughness: Single): Single; static;

    { Phase 35.1: Generates GLSL 460 Hardware Ray Tracing Pipeline stages (GL_EXT_ray_tracing:
      raygen, closesthit, miss) invoking traceRayEXT and barycentric hit interpolation. }
    function GenerateRayTracingPipelineStages: String;

    { Phase 35.1 CPU reference: Interpolates a normalized triangle vertex normal using ray-hit barycentrics (bary.xy). }
    class function InterpolateRayHitNormal(
      const AN0, AN1, AN2: TVector3;
      const AHitBarycentricsUV: TVector2): TVector3; static;

    { Phase 35.2 CPU reference: Aligns AValue upward to the next multiple of APowerOfTwoAlignment. }
    class function AlignUpSBTSize(
      const AValue, AAlignment: Cardinal): Cardinal; static;

    { Phase 36.1: Generates a GLSL 450 compute shader for Extended Position-Based Dynamics (XPBD)
      Cloth & Hair Strand Simulation (compliant distance constraints, aerodynamic wind, and SDF collision). }
    function GenerateXPBDClothComputeShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 36.1 CPU reference: Evaluates compliant XPBD distance constraint position correction delta for P1. }
    class function EvaluateXPBDDistanceConstraintDelta(
      const AP1, AP2: TVector3;
      const AInvMass1, AInvMass2, ARestLength, AComplianceAlpha, ASubstepDt: Single): TVector3; static;

    { Phase 36.2 CPU reference: Evaluates aerodynamic normal wind force on a cloth/foliage triangle element. }
    class function EvaluateAerodynamicWindForce(
      const AWindVelocity, AElementVelocity, AElementNormal: TVector3;
      const AElementArea, ADragCoeff: Single;
      const AAirDensity: Single = 1.225): TVector3; static;

    { Phase 36.2 CPU reference: Projects a cloth/hair particle out of a colliding bounding sphere with margin. }
    class function ResolveSphereCollisionConstraint(
      const AParticlePos, ASphereCenter: TVector3;
      const ASphereRadius: Single;
      const ACollisionMargin: Single = 0.01): TVector3; static;

    { Phase 37.1 & 37.2: Generates GLSL 450 Multi-View Stereo VR preamble (GL_EXT_multiview / gl_ViewIndex),
      asymmetric OpenXR eye frustum projection helper, and gaze-tracked radial foveated VRS shading rate. }
    function GenerateMultiviewStereoPreamble: String;

    { Phase 37.1 CPU reference: Computes OpenXR asymmetric eye frustum horizontal projection (XScale, XOffset) from tangent half-angles. }
    class function ComputeAsymmetricEyeProjectionXScaleOffset(
      const ATanLeft, ATanRight: Single): TVector2; static;

    { Phase 37.2 CPU reference: Evaluates gaze-tracked radial foveated shading rate code
      (0 = 1x1 fovea, $5 = 2x2 parafovea, $A = 4x4 periphery) around AGazeCenterUV. }
    class function EvaluateFoveatedShadingRate(
      const AUV, AGazeCenterUV: TVector2;
      const AInnerFoveaRadius: Single = 0.18;
      const AMiddleParafoveaRadius: Single = 0.42): Cardinal; static;

    { Phase 37.3: Generates GLSL 450 HDR10 Rec.2020 Wide Color Gamut conversion and SMPTE ST.2084 (PQ)
      10,000-nit perceptual quantizer transfer functions. }
    function GenerateHDR10PQEncodingFunctions: String;

    { Phase 37.3 CPU reference: Converts linear Rec.709 / sRGB radiance to linear Rec.2020 wide color gamut. }
    class function EvaluateLinearRec709ToRec2020(
      const ALinearRec709: TVector3): TVector3; static;

    { Phase 37.3 CPU reference: Encodes linear luminance in nits [0..10000] with the SMPTE ST.2084 (PQ) transfer function [0..1]. }
    class function EncodeST2084PQ(
      const ALinearNits: TVector3): TVector3; static;

    { Phase 38.1: Generates GLSL 450 Dual-Quaternion Skinning (DQS) functions for volume-preserving joint blending. }
    function GenerateDualQuaternionSkinningFunctions: String;

    { Phase 38.1 CPU reference: Blends two dual quaternions with antipodality sign correction and normalizes the result. }
    class procedure BlendDualQuaternionAntipodal(
      const ADQReal0, ADQDual0, ADQReal1, ADQDual1: TVector4;
      const AW0, AW1: Single;
      out AOutReal, AOutDual: TVector4); static;

    { Phase 38.1 CPU reference: Transforms a 3D vertex position by a normalized dual quaternion (q_real, q_dual). }
    class function EvaluateDualQuaternionTransform(
      const ADQReal, ADQDual: TVector4;
      const APosition: TVector3): TVector3; static;

    { Phase 38.2: Generates GLSL 450 MegaGeometry Displaced Micro-Mesh barycentric tessellation and edge-snapping functions. }
    function GenerateDisplacedMicroMeshFunctions: String;

    { Phase 38.2 CPU reference: Evaluates a micro-mesh vertex position displaced along the barycentrically interpolated normal. }
    class function EvaluateMicroMeshDisplacedPosition(
      const AP0, AP1, AP2, AN0, AN1, AN2: TVector3;
      const ABaryUV: TVector2;
      const AHeightSample, ADisplacementScale: Single;
      const ADisplacementBias: Single = 0.0): TVector3; static;

    { Phase 38.2 CPU reference: Snaps barycentric (u, v) coordinates onto a uniform subdivision grid for crack-free edges. }
    class function SnapMicroMeshBarycentricToGrid(
      const ABaryUV: TVector2;
      const ASubdivisionSegments: Cardinal): TVector2; static;

    { Phase 39.1: Generates GLSL 450 Optical Flow SAD Block Matching & parabolic sub-pixel motion estimation functions. }
    function GenerateOpticalFlowBlockMatchingShader: String;

    { Phase 39.1 CPU reference: Computes Sum of Absolute Differences (SAD) between two 2x2 luma patches. }
    class function EvaluateOpticalFlowPatchSAD(
      const APatchCurr, APatchPrev: TVector4): Single; static;

    { Phase 39.1 CPU reference: Estimates parabolic sub-pixel motion offset [-0.5..0.5]^2 from 5-point SAD neighbors. }
    class function EstimateParabolicSubpixelOffset(
      const ASADLeft, ASADCenter, ASADRight, ASADDown, ASADUp: Single): TVector2; static;

    { Phase 39.2: Generates GLSL 450 Martin Roberts R2 low-discrepancy sequence and golden-ratio spatio-temporal blue-noise functions. }
    function GenerateSpatioTemporalBlueNoiseFunctions: String;

    { Phase 39.2 CPU reference: Evaluates the 2D quasi-random R2 sequence in [0..1)^2 for ASampleIndex. }
    class function EvaluateR2Sequence2D(
      const ASampleIndex: Cardinal): TVector2; static;

    { Phase 39.2 CPU reference: Rotates a spatial blue-noise value [0..1) temporally using the golden ratio conjugate. }
    class function EvaluateTemporalBlueNoiseJitter(
      const ABaseBlueNoise: Single;
      const AFrameIndex: Cardinal): Single; static;

    { Phase 40.1: Generates GLSL 460 Shader Execution Reordering (SER, GL_NV_shader_invocation_reorder)
      coherence hint packing functions to sort divergent ray-tracing threads by hit state, material, and direction octant. }
    function GenerateSERCoherenceHintFunctions: String;

    { Phase 40.1 CPU reference: Packs an 8-bit SER coherence hint key [0..255] from (IsHit, MaterialID[0..15], DirectionOctant[0..7]). }
    class function PackSERCoherenceHintKey(
      const AIsHit: Boolean;
      const AMaterialShadingModelID: Cardinal;
      const ARayDirection: TVector3): Cardinal; static;

    { Phase 40.2: Generates GLSL 450 Dual-Source Color Blending functions (location = 0, index = 0/1)
      for single-pass physically based colored/stained glass reflection and spectral transmission. }
    function GenerateDualSourceGlassTransmissionFunctions: String;

    { Phase 40.2 CPU reference: Evaluates dual-source glass outputs (Src0 additive specular, Src1 multiplicative colored transmittance). }
    class procedure EvaluateDualSourceGlassOutputs(
      const ASpecularLightingRGB, AGlassTintRGB: TVector3;
      const AFresnelF, AGlassOpacity: Single;
      out AOutSpecularAdd, AOutTransmittanceMul: TVector3); static;

    { Phase 41.1: Generates Vulkan 1.4 Dynamic Rendering Local Read (VK_KHR_dynamic_rendering_local_read)
      subpassInput preamble and tile-local G-Buffer deferred lighting evaluation functions. }
    function GenerateDynamicRenderingLocalReadPreamble: String;

    { Phase 41.1 CPU reference: Evaluates tile-local G-Buffer deferred lighting (diffuse + roughness-driven specular)
      without external VRAM bandwidth round-trips. }
    class function EvaluateTileLocalDeferredLighting(
      const AAlbedo, ANormalWS: TVector3;
      const ARoughness: Single;
      const ALightDirWS, AViewDirWS, ALightColor: TVector3): TVector3; static;

    { Phase 41.2: Generates GLSL 450 Subgroup Wave Intrinsics (GL_KHR_shader_subgroup_ballot / arithmetic)
      for lock-free wave-level ballot bit-counting and exclusive prefix-sum reductions. }
    function GenerateSubgroupWaveIntrinsicsFunctions: String;

    { Phase 41.2 CPU reference: Counts active threads (popcount) in a 64-bit subgroup ballot mask. }
    class function EvaluateSubgroupBallotBitCount(const ABallotMask: UInt64): Cardinal; static;

    { Phase 41.2 CPU reference: Computes the exclusive prefix sum (0, v0, v0+v1, v0+v1+v2) across 4 subgroup lanes. }
    class function EvaluateSubgroupExclusivePrefixSum4(
      const AValues: TVector4Cardinal): TVector4Cardinal; static;

    { Phase 42.1: Generates GLSL 450 Buffer Device Address (GL_EXT_buffer_reference2 / VK_KHR_buffer_device_address)
      64-bit GPU pointer definitions for bindless vertex/index/material buffer dereferencing. }
    function GenerateBufferDeviceAddressPreamble: String;

    { Phase 42.1 CPU reference: Aligns a 64-bit GPU VkDeviceAddress upward to AAlignment (buffer_reference_align). }
    class function AlignBufferDeviceAddress(
      const AAddress: UInt64;
      const AAlignment: Cardinal = 16): UInt64; static;

    { Phase 42.2: Generates GLSL 450 Conservative Dominant-Axis Voxelization and 3D Mipmapped Voxel Cone Tracing (VXGI) functions. }
    function GenerateVoxelConeTracingFunctions: String;

    { Phase 42.2 CPU reference: Selects the dominant projection axis (0=X, 1=Y, 2=Z) that maximizes projected triangle area. }
    class function SelectDominantVoxelProjectionAxis(
      const AFaceNormal: TVector3): Cardinal; static;

    { Phase 42.2 CPU reference: Evaluates voxel cone diameter (X) and 3D texture mip level (Y) at ADistanceAlongCone. }
    class function EvaluateVoxelConeStepAperture(
      const ADistanceAlongCone, AConeHalfAngleTan, ABaseVoxelSize: Single): TVector2; static;

    { Phase 43.1: Generates GLSL 450 Normal-Variance Specular Anti-Aliasing (Kaplanyan & Antonov / Toksvig)
      functions to filter sub-pixel normal derivatives into GGX roughness and eliminate distant specular aliasing. }
    function GenerateSpecularNormalVarianceAAFunctions: String;

    { Phase 43.1 CPU reference: Evaluates filtered GGX perceptual roughness in [0..1] from base roughness and screen-space normal derivatives dNdU, dNdV. }
    class function EvaluateSpecularAARoughness(
      const ABaseRoughness: Single;
      const ADNdU, ADNdV: TVector3;
      const AVarianceStrength: Single = 0.5;
      const AMaxVarianceThreshold: Single = 0.18): Single; static;

    { Phase 43.2: Generates GLSL 450 Rectilinear Shadow Map Warping functions to concentrate shadow map
      texel density near the camera focus region while keeping [0..1]^2 boundaries invariant. }
    function GenerateRectilinearShadowWarpFunctions: String;

    { Phase 43.2 CPU reference: Warps normalized shadow map UV [0..1]^2 using rectilinear warp strength AWarpStrength >= 0. }
    class function EvaluateRectilinearShadowWarpUV(
      const AShadowUV: TVector2;
      const AWarpStrength: Single): TVector2; static;

    { Phase 44.1: Generates GLSL 450 Multi-Channel Signed Distance Field (MSDF, Chlumsky median-of-three)
      evaluation functions for sharp corner-preserving vector shapes and 3D text at arbitrary magnification. }
    function GenerateMSDFTextFunctions: String;

    { Phase 44.1 CPU reference: Evaluates the median of three MSDF RGB channels. }
    class function EvaluateMSDFMedianOfThree(
      const AR, AG, AB: Single): Single; static;

    { Phase 44.1 CPU reference: Evaluates anti-aliased screen-space glyph opacity in [0..1] from MSDF RGB and screen pixel range. }
    class function EvaluateMSDFScreenPxOpacity(
      const AMSDFSampleRGB: TVector3;
      const AScreenPxRange: Single): Single; static;

    { Phase 44.2: Generates GLSL 450 Procedural Quadratic Bezier Grass Blade position and tangent evaluation
      functions for GPU-instanced foliage and meadows. }
    function GenerateProceduralGrassBladeFunctions: String;

    { Phase 44.2 CPU reference: Evaluates quadratic Bezier grass blade position B(t) and normalized tangent B'(t) for t in [0..1]. }
    class procedure EvaluateQuadraticBezierGrassBlade(
      const AP0, AP1, AP2: TVector3;
      const AT: Single;
      out AOutPosition, AOutTangent: TVector3); static;

    { Phase 45.1: Generates Vulkan 1.4 Push Descriptor (`VK_KHR_push_descriptor`) GLSL 450 set layout preamble
      for zero-allocation command-buffer descriptor updates. }
    function GeneratePushDescriptorPreamble(const ASetIndex: Cardinal = 1): String;

    { Phase 45.1 CPU reference: Computes the byte size required for a Vulkan 1.4 Host Image Copy (`VK_EXT_host_image_copy`)
      subresource transfer with aligned row pitch. }
    class function ComputeHostImageCopyByteSize(
      const AWidth, AHeight, ADepth, ABytesPerTexel: Cardinal;
      const ARowAlignmentBytes: Cardinal = 1): UInt64; static;

    { Phase 45.2: Generates GLSL 450 Spherical Gaussian (SG) lobe evaluation, inner product, and spherical integral
      functions for real-time anisotropic specular and diffuse probe lighting. }
    function GenerateSphericalGaussianFunctions: String;

    { Phase 45.2 CPU reference: Evaluates the exact product of two normalized Spherical Gaussian lobes. }
    class procedure EvaluateSphericalGaussianProduct(
      const AAxis1: TVector3; const ASharpness1: Single;
      const AAxis2: TVector3; const ASharpness2: Single;
      out AProductAxis: TVector3;
      out AProductSharpness, ALogAmplitudeScale: Single); static;

    { Phase 45.2 CPU reference: Evaluates the exact integral of a Spherical Gaussian lobe over the unit sphere S^2. }
    class function EvaluateSphericalGaussianIntegral(
      const AAmplitude: TVector3;
      const ASharpness: Single): TVector3; static;

    { Phase 46.1: Generates GLSL 450 3D Gaussian Splatting (3DGS) EWA 2D covariance conic projection
      and Mahalanobis opacity falloff evaluation functions. }
    function GenerateGaussianSplattingFunctions: String;

    { Phase 46.1 CPU reference: Invert a 2D symmetric covariance matrix (CovXX, CovXY, CovYY) with low-pass dilation
      into conic coefficients (ConicX, ConicY, ConicZ) and evaluate Gaussian splat opacity at PixelOffset. }
    class function EvaluateGaussianSplatOpacity(
      const ACov2D: TVector3;
      const APixelOffset: TVector2;
      const ABaseOpacity: Single): Single; static;

    { Phase 46.2 CPU reference: Evaluates degree-1 (L0 + L1) view-dependent Spherical Harmonics RGB color
      clamped to non-negative radiance for 3D Gaussian Splats. }
    class function EvaluateSphericalHarmonicsL1RGB(
      const ASH0, ASH1X, ASH1Y, ASH1Z: TVector3;
      const AViewDir: TVector3): TVector3; static;

    { Phase 47.1: Generates GLSL 450 Percentage-Closer Soft Shadows (PCSS) blocker search
      and contact-hardening penumbra width evaluation functions. }
    function GeneratePCSSSoftShadowFunctions: String;

    { Phase 47.1 CPU reference: Evaluates PCSS contact-hardening penumbra filter width
      (d_receiver - d_blocker) * lightWorldSize / d_blocker. }
    class function EvaluatePCSSPenumbraWidth(
      const AReceiverDepth, AAvgBlockerDepth, ALightSize: Single): Single; static;

    { Phase 47.2 CPU reference: Computes hardware-aligned byte offset into a Vulkan Descriptor Buffer (`VK_EXT_descriptor_buffer`). }
    class function ComputeDescriptorBufferAlignedOffset(
      const ASetIndex: Cardinal;
      const ASetByteSize: UInt64;
      const AOffsetAlignment: UInt64 = 64): UInt64; static;

    { Phase 48.1: Generates GLSL 450 Multi-Layer Metallic Flake & Clear-Coat Car-Paint BRDF functions. }
    function GenerateCarPaintFlakeFunctions: String;

    { Phase 48.1 CPU reference: Evaluates multi-layer automotive car-paint radiance combining
      view-dependent two-tone base coat, metallic flake sparkle lobe, and dielectric clear coat Fresnel. }
    class function EvaluateCarPaintMultiLayerBRDF(
      const ABaseColorNormal, ABaseColorGrazing, AFlakeColor: TVector3;
      const ANdotV, ANdotH, AFlakeNdotH, AFlakeExponent: Single): TVector3; static;

    { Phase 48.2: Generates GLSL 450 Screen-Space Normal Curvature & Ridge/Valley Cavity Shading functions. }
    function GenerateScreenSpaceCurvatureFunctions: String;

    { Phase 48.2 CPU reference: Evaluates screen-space ridge/valley cavity multiplier in [0..2]
      from horizontal and vertical view-normal derivatives. }
    class function EvaluateScreenSpaceCurvatureCavity(
      const ADNormalDx, ADNormalDy: TVector3;
      const ACurvatureScale: Single): Single; static;

    { Phase 49.1: Generates GLSL 450 Physically Based Camera Exposure (EV100) functions. }
    function GenerateCameraEV100ExposureFunctions: String;

    { Phase 49.1 CPU reference: Computes photographic EV100 from aperture f-stops (N),
      shutter time in seconds (t), and sensor ISO sensitivity (S):
      EV100 = log2((N^2 / t) * (100.0 / S)). }
    class function EvaluateEV100FromCameraSettings(
      const AApertureFStops, AShutterSeconds, AISO: Single): Single; static;

    { Phase 49.1 CPU reference: Computes ISO 12232 saturation-based linear exposure
      multiplier from EV100: 1.0 / (1.2 * 2^EV100). }
    class function EvaluateExposureMultiplierFromEV100(
      const AEV100: Single): Single; static;

    { Phase 49.2: Generates GLSL 450 AgX Filmic Log Encoding & Highlight Chroma Gamut Compression functions. }
    function GenerateAgXGamutCompressionFunctions: String;

    { Phase 49.2 CPU reference: Compresses out-of-gamut high-intensity saturated RGB colors
      toward their Rec.709 luminance achromatic axis to prevent hard channel clipping. }
    class function EvaluateChromaGamutCompression(
      const ALinearRGB: TVector3;
      const ACompressionStrength: Single): TVector3; static;

    { Phase 50.1: Generates GLSL 450 Analytical Capsule Soft Shadow & Ambient Occlusion functions. }
    function GenerateCapsuleOcclusionFunctions: String;

    { Phase 50.1 CPU reference: Evaluates analytical soft shadow visibility in [0..1]
      (1 = unoccluded, 0 = fully occluded) for a ray from AShadingPos along ALightDir
      against a capsule segment [ACapsuleA, ACapsuleB] with ACapsuleRadius and AConeTang. }
    class function EvaluateCapsuleSoftShadowOcclusion(
      const AShadingPos, ALightDir, ACapsuleA, ACapsuleB: TVector3;
      const ACapsuleRadius, AConeTang: Single): Single; static;

    { Phase 50.2: Generates GLSL 450 Epipolar Volumetric Light Shafts (Crepuscular God Rays) functions. }
    function GenerateEpipolarLightShaftFunctions: String;

    { Phase 50.2 CPU reference: Evaluates the 2D screen-space sample UV along an epipolar
      slice ray from ALightScreenUV to ASliceEndpointUV at normalized step ASliceFraction in [0..1]. }
    class function EvaluateEpipolarSliceRayStep(
      const ALightScreenUV, ASliceEndpointUV: TVector2;
      const ASliceFraction: Single): TVector2; static;

    { Phase 51.1: Generates GLSL 450 Cooperative Matrix / Tensor Core preamble (`GL_KHR_cooperative_matrix`). }
    function GenerateCooperativeMatrixPreamble: String;

    { Phase 51.1 CPU reference: Decodes an 8-bit E4M3 floating-point byte (1 sign bit,
      4 exponent bits with bias 7, 3 mantissa bits) into a 32-bit IEEE 754 Single. }
    class function EvaluateQuantizedFP8ToFloat(
      const AFP8Byte: Byte): Single; static;

    { Phase 51.2: Generates GLSL 450 Anisotropic Kuwahara Structure-Tensor functions. }
    function GenerateAnisotropicKuwaharaFunctions: String;

    { Phase 51.2 CPU reference: Computes the principal orientation angle in radians
      [-Pi/2..Pi/2] and normalized eigenvalue anisotropy in [0..1] from structure
      tensor components (AJxx, AJyy, AJxy). }
    class function EvaluateStructureTensorEigenOrientation(
      const AJxx, AJyy, AJxy: Single;
      out AAnisotropy: Single): Single; static;

    { Phase 52.1: Generates GLSL 450 Physically Based Eye Cornea Snell Refraction & Iris Parallax functions. }
    function GeneratePhysicalEyeRefractionFunctions: String;

    { Phase 52.1 CPU reference: Evaluates the 2D iris UV parallax offset caused by
      Snell refraction at the cornea surface (ACorneaIOR) across AAnteriorChamberDepth. }
    class function EvaluateEyeIrisRefractionUVOffset(
      const AViewDirTS, ACorneaNormalTS: TVector3;
      const ACorneaIOR, AAnteriorChamberDepth: Single): TVector2; static;

    { Phase 52.2: Generates GLSL 450 Six-Point Directional Lightmap Basis functions for volumetric smoke/clouds. }
    function GenerateSixPointLightmapFunctions: String;

    { Phase 52.2 CPU reference: Evaluates 6-axis directional lightmap irradiance
      (+X, -X, +Y in AMapPosXNegXPosY; -Y, +Z, -Z in AMapNegYPosZNegZ) for ALightDirTS. }
    class function EvaluateSixPointDirectionalBasis(
      const ALightDirTS, AMapPosXNegXPosY, AMapNegYPosZNegZ: TVector3): Single; static;

    { Phase 53.1: Generates GLSL 450 Secant-Refined Parallax Occlusion Mapping (POM) functions. }
    function GenerateParallaxOcclusionMappingFunctions: String;

    { Phase 53.1 CPU reference: Computes the secant-interpolated ray-heightfield
      intersection depth between two POM step layers. }
    class function EvaluateSecantRefinedPOMIntersection(
      const APrevLayerDepth, ACurrLayerDepth, APrevHeight, ACurrHeight: Single): Single; static;

    { Phase 53.2: Generates GLSL 450 Spectral Cauchy Chromatic Dispersion & Lens Flare functions. }
    function GenerateChromaticDispersionFlareFunctions: String;

    { Phase 53.2 CPU reference: Evaluates wavelength-dependent Cauchy refractive indices
      n(lambda) = A + B / lambda^2 for Red (0.65 um), Green (0.55 um), and Blue (0.45 um). }
    class function EvaluateCauchyRefractiveIndexRGB(
      const ACoeffA, ACoeffBMicronsSq: Single): TVector3; static;

    { Phase 58.1: Builds the 128-byte per-draw TCastlePushConstantsBlock for a shape,
      packing ModelViewMatrix, std140-padded 3x3 NormalMatrix rows, and ObjectParams:
      - ObjectParams.X: Bindless material index (ABindlessMaterialIndex)
      - ObjectParams.Y: Skinning mode (0.0 = static mesh, 1.0 = Linear Blend Skinning, 2.0 = Dual-Quaternion Skinning)
      - ObjectParams.Z: Specular Anti-Aliasing flag (1.0 = enabled, 0.0 = disabled)
      - ObjectParams.W: ShadowMapSystemMode ordinal (0 = PCF, 1 = PCSS, 2 = VSM) }
    class function BuildShapeRHIPushConstants(
      const AShapeModelView: TMatrix4;
      const ANormalMatrix: TMatrix3;
      const AHasSkinJoints, ADualQuaternionSkinning, ASpecularAntiAliasing: Boolean;
      const AShadowMapSystemModeOrd: Cardinal = 0;
      const ABindlessMaterialIndex: Cardinal = 0): TCastlePushConstantsBlock; static;

    { Phase 59.1: Unpacks ObjectParams from a TCastlePushConstantsBlock into
      ABindlessMaterialIndex, ASkinningMode (0 = static, 1 = LBS, 2 = Dual-Quaternion),
      ASpecularAntiAliasing, and AShadowMapSystemModeOrd (0 = PCF, 1 = PCSS, 2 = VSM),
      mirroring the GLSL 450 castle_Object* macros. }
    class procedure UnpackShapeRHIPushConstantsObjectParams(
      const APushConstants: TCastlePushConstantsBlock;
      out ABindlessMaterialIndex, ASkinningMode: Cardinal;
      out ASpecularAntiAliasing: Boolean;
      out AShadowMapSystemModeOrd: Cardinal); static;

    { Phase 111: Generates a procedural fullscreen-triangle GLSL 450 vertex shader
      for HDR Tonemapping & Bloom Composite (compatible with CGE negative-height VkViewport). }
    function GenerateHDRCompositeVertexShader: String;

    { Phase 111: Generates a GLSL 450 compute shader that modulates scene HDR radiance
      by denoised GTAO ambient occlusion and adds Hi-Z SSR reflections. }
    function GeneratePostProcessModulateComputeShader(
      const AWorkgroupSizeX: Cardinal = 8;
      const AWorkgroupSizeY: Cardinal = 8): String;

    { Computes the 64-bit FNV-1a hash of the final GLSL source for on-disk SPIR-V caching }
    class function ComputeSourceHash(const FinalGLSL: String): UInt64; static;
  end;

{$endif read_interface}

