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

{ Upgrade extension for CastleRendererInternalShader to emit Vulkan GLSL 450
  (UBOs, Push Constants, explicit stage locations) alongside OpenGL/OpenGLES. }
unit CastleInternalShaderRHI;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, StrUtils, Generics.Collections,
  CastleVectors, CastleColors, CastleStringUtils, CastleLog,
  CastleInternalRHI;

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
    procedure SetProjectorMatrix(const Index: Integer; const Matrix: TMatrix4);
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

type
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

  { Generates RHI-compliant GLSL headers, UBO blocks, and varying layouts }
  TCastleShaderGeneratorRHI = class
  private
    FBackend: TRHIBackendType;
    function GenerateVersionAndLayoutMacros: String;
    function GenerateStandardUniformBlocks(const AStage: TRHIShaderStage): String;
    function GenerateStageIO(const AStage: TRHIShaderStage): String;
  public
    constructor Create(const ABackend: TRHIBackendType);

    { Builds the complete preamble injected before CGE's internal GLSL templates }
    function GeneratePreamble(const AStage: TRHIShaderStage): String;

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

    { Strips or comments out legacy bare uniform declarations replaced by Set 0..2 UBOs and Push Constants }
    function SanitizeVulkanShaderSource(const Source: String): String;

    { Builds GLSL 450 preamble for post-processing screen effects (TCastleScreenEffects) }
    function GenerateScreenEffectPreamble(const AStage: TRHIShaderStage; const HasDepth: Boolean): String;

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
      const HasTangents: Boolean = False): String;

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

    { Computes the 64-bit FNV-1a hash of the final GLSL source for on-disk SPIR-V caching }
    class function ComputeSourceHash(const FinalGLSL: String): UInt64; static;
  end;

implementation

const
  NL = LineEnding;

{ TCastleLightsUniformBlock }

procedure TCastleLightsUniformBlock.Clear;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

function TCastleLightsUniformBlock.AddLightInternal(const APos, AColor, ASpotDir,
  ASpotParams, AAtten, AAmbient: TVector4): Integer;
begin
  if Count >= CASTLE_MAX_LIGHTS then Exit(-1);
  Result := Count;
  Lights[Result].Position := APos;
  Lights[Result].Color := AColor;
  Lights[Result].SpotDirection := ASpotDir;
  Lights[Result].SpotParams := ASpotParams;
  Lights[Result].Attenuation := AAtten;
  Lights[Result].AmbientColor := AAmbient;
  Lights[Result].ProjectorMatrix := TMatrix4.Identity;
  Inc(Count);
end;

function TCastleLightsUniformBlock.AddDirectionalLight(const Direction, Color,
  AmbientColor: TVector3): Integer;
begin
  Result := AddLightInternal(Vector4(Direction, 0.0), Vector4(Color, 0.0),
    Vector4(0, 0, -1, -1.0), Vector4(0, 0, 0, 0), Vector4(1, 0, 0, 0), Vector4(AmbientColor, 1.0));
end;

function TCastleLightsUniformBlock.AddPointLight(const Position, Color,
  AmbientColor: TVector3; const Attenuation: TVector3; const Radius: Single): Integer;
begin
  Result := AddLightInternal(Vector4(Position, 1.0), Vector4(Color, Radius),
    Vector4(0, 0, -1, -1.0), Vector4(0, 0, 0, 0), Vector4(Attenuation, 0.0), Vector4(AmbientColor, 1.0));
end;

function TCastleLightsUniformBlock.AddSpotLight(const Position, Direction, Color,
  AmbientColor: TVector3; const Attenuation: TVector3; const Radius, SpotCosCutoff,
  SpotCutoff, BeamWidth, SpotExponent: Single): Integer;
begin
  Result := AddLightInternal(Vector4(Position, 2.0), Vector4(Color, Radius),
    Vector4(Direction, SpotCosCutoff), Vector4(SpotCutoff, BeamWidth, SpotExponent, 0.0),
    Vector4(Attenuation, 0.0), Vector4(AmbientColor, 1.0));
end;

procedure TCastleLightsUniformBlock.SetProjectorMatrix(const Index: Integer;
  const Matrix: TMatrix4);
begin
  if (Index >= 0) and (Index < Integer(Count)) then
    Lights[Index].ProjectorMatrix := Matrix;
end;

{ TCastleMaterialUniformBlock }

procedure TCastleMaterialUniformBlock.InitDefaultPBR;
begin
  BaseColor := Vector4(1.0, 1.0, 1.0, 1.0);
  SpecularColor := Vector4(0.04, 0.04, 0.04, 0.0); // a = 0.0 -> PBR Metallic-Roughness
  EmissiveColor := Vector4(0.0, 0.0, 0.0, 0.0);    // a = 0.0 -> Metallic = 0
  PBRParams := Vector4(1.0, 1.0, 1.0, 0.0);        // Roughness=1, NormalScale=1, OcclusionStrength=1, AlphaCutoff=0
end;

procedure TCastleMaterialUniformBlock.InitDefaultPhong;
begin
  BaseColor := Vector4(0.8, 0.8, 0.8, 1.0);
  SpecularColor := Vector4(0.0, 0.0, 0.0, 25.6);   // a > 0.0 -> Phong shininess (0.2 * 128)
  EmissiveColor := Vector4(0.0, 0.0, 0.0, 0.0);
  PBRParams := Vector4(0.5, 1.0, 1.0, 0.0);
end;

procedure TCastleMaterialUniformBlock.InitDefaultUnlit;
begin
  BaseColor := Vector4(1.0, 1.0, 1.0, 1.0);
  SpecularColor := Vector4(0.0, 0.0, 0.0, -1.0);   // a < 0.0 -> Unlit shading model
  EmissiveColor := Vector4(0.0, 0.0, 0.0, 0.0);
  PBRParams := Vector4(1.0, 1.0, 1.0, 0.0);
end;

{ TCastleShaderGeneratorRHI }

constructor TCastleShaderGeneratorRHI.Create(const ABackend: TRHIBackendType);
begin
  inherited Create;
  FBackend := ABackend;
end;

function TCastleShaderGeneratorRHI.GenerateVersionAndLayoutMacros: String;
begin
  case FBackend of
    rbVulkan:
      Result :=
        '#version 450' + NL +
        '#define CASTLE_VULKAN 1' + NL +
        '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140, set = SetIdx, binding = BindIdx)' + NL +
        '#define CASTLE_SSBO(SetIdx, BindIdx) layout(std430, set = SetIdx, binding = BindIdx)' + NL +
        '#define CASTLE_SAMPLER(SetIdx, BindIdx) layout(set = SetIdx, binding = BindIdx)' + NL +
        '#define CASTLE_PUSH_CONSTANT layout(push_constant)' + NL +
        '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
        '#define CASTLE_VERTEX_INDEX gl_VertexIndex' + NL +
        '#define CASTLE_INSTANCE_INDEX gl_InstanceIndex' + NL;

    rbOpenGL:
      Result :=
        '#version 330 core' + NL +
        '#extension GL_ARB_shading_language_420pack : enable' + NL +
        '#extension GL_ARB_explicit_attrib_location : enable' + NL +
        '#define CASTLE_OPENGL 1' + NL +
        { Flattens (SetIdx, BindIdx) to match GL_DESCRIPTOR_SET_SLOT_STRIDE = 4 }
        '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140, binding = (SetIdx * 4 + BindIdx))' + NL +
        '#define CASTLE_SAMPLER(SetIdx, BindIdx) layout(binding = (SetIdx * 4 + BindIdx))' + NL +
        { Maps Push Constants to reserved UBO slot 15 in OpenGL }
        '#define CASTLE_PUSH_CONSTANT layout(std140, binding = 15)' + NL +
        '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
        '#define CASTLE_VERTEX_INDEX gl_VertexID' + NL +
        '#define CASTLE_INSTANCE_INDEX gl_InstanceID' + NL;

    rbOpenGLES:
      Result :=
        '#version 300 es' + NL +
        'precision highp float;' + NL +
        'precision highp int;' + NL +
        '#define CASTLE_OPENGLES 1' + NL +
        '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140)' + NL +
        '#define CASTLE_SAMPLER(SetIdx, BindIdx)' + NL +
        '#define CASTLE_PUSH_CONSTANT layout(std140)' + NL +
        '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
        '#define CASTLE_VERTEX_INDEX gl_VertexID' + NL +
        '#define CASTLE_INSTANCE_INDEX gl_InstanceID' + NL;
  end;
end;

function TCastleShaderGeneratorRHI.GenerateStandardUniformBlocks(
  const AStage: TRHIShaderStage): String;
var
  LightAliases: String;
  I: Integer;
begin
  LightAliases := '';
  for I := 0 to CASTLE_MAX_LIGHTS - 1 do
  begin
    LightAliases := LightAliases +
      Format('#define castle_LightSource%dPosition CastleLights.u_Lights[%d].Position.xyz', [I, I]) + NL +
      Format('#define castle_LightSource%dColor CastleLights.u_Lights[%d].Color.rgb', [I, I]) + NL +
      Format('#define castle_LightSource%dRadius CastleLights.u_Lights[%d].Color.w', [I, I]) + NL +
      Format('#define castle_LightSource%dSpotDirection CastleLights.u_Lights[%d].SpotDirection.xyz', [I, I]) + NL +
      Format('#define castle_LightSource%dSpotCosCutoff CastleLights.u_Lights[%d].SpotDirection.w', [I, I]) + NL +
      Format('#define castle_LightSource%dSpotCutoff CastleLights.u_Lights[%d].SpotParams.x', [I, I]) + NL +
      Format('#define castle_LightSource%dBeamWidth CastleLights.u_Lights[%d].SpotParams.y', [I, I]) + NL +
      Format('#define castle_LightSource%dSpotExponent CastleLights.u_Lights[%d].SpotParams.z', [I, I]) + NL +
      Format('#define castle_LightSource%dAttenuation CastleLights.u_Lights[%d].Attenuation.xyz', [I, I]) + NL +
      Format('#define castle_LightSource%dAmbientColor CastleLights.u_Lights[%d].AmbientColor.rgb', [I, I]) + NL +
      Format('#define castle_projector_matrix_%d CastleLights.u_Lights[%d].ProjectorMatrix', [I, I]) + NL;
  end;

  Result :=
    '/* --- Set 0, Binding 0: Global / Per-Pass Uniforms --- */' + NL +
    'CASTLE_UBO(0, 0) uniform CastleSceneBlock {' + NL +
    '  mat4 u_ProjectionMatrix;' + NL +
    '  mat4 u_ViewMatrix;' + NL +
    '  mat4 u_ViewMatrixInverse;' + NL +
    '  vec4 u_CameraPosition;' + NL +
    '  vec4 u_FogColor;' + NL +
    '  vec4 u_FogParams;' + NL +
    '  uint u_LightCount;' + NL +
    '} CastleScene;' + NL +
    NL +
    '/* Legacy CGE uniform aliases for Set 0 */' + NL +
    '#define castle_ProjectionMatrix CastleScene.u_ProjectionMatrix' + NL +
    '#define castle_ViewMatrix CastleScene.u_ViewMatrix' + NL +
    '#define castle_ViewMatrixInverse CastleScene.u_ViewMatrixInverse' + NL +
    '#define castle_WorldEyePosition CastleScene.u_CameraPosition.xyz' + NL +
    '#define castle_SceneTime CastleScene.u_CameraPosition.w' + NL +
    NL +
    '/* --- Set 0, Binding 1: Multi-Light Uniform Block --- */' + NL +
    'struct CastleLightData {' + NL +
    '  vec4 Position;' + NL +
    '  vec4 Color;' + NL +
    '  vec4 SpotDirection;' + NL +
    '  vec4 SpotParams;' + NL +
    '  vec4 Attenuation;' + NL +
    '  vec4 AmbientColor;' + NL +
    '  mat4 ProjectorMatrix;' + NL +
    '};' + NL +
    NL +
    'CASTLE_UBO(0, 1) uniform CastleLightsBlock {' + NL +
    '  uint u_LightCount;' + NL +
    '  uint u_Pad0;' + NL +
    '  uint u_Pad1;' + NL +
    '  uint u_Pad2;' + NL +
    '  CastleLightData u_Lights[32];' + NL +
    '} CastleLights;' + NL +
    NL +
    '#define castle_LightCount CastleLights.u_LightCount' + NL +
    LightAliases + NL +
    '/* --- Set 0, Bindings 2..5: Shadow Map Samplers --- */' + NL +
    'CASTLE_SAMPLER(0, 2) uniform sampler2DShadow castle_shadow_map_0;' + NL +
    'CASTLE_SAMPLER(0, 3) uniform sampler2DShadow castle_shadow_map_1;' + NL +
    'CASTLE_SAMPLER(0, 4) uniform sampler2DShadow castle_shadow_map_2;' + NL +
    'CASTLE_SAMPLER(0, 5) uniform sampler2DShadow castle_shadow_map_3;' + NL +
    NL +
    '/* --- Set 1: Per-Material Uniforms & Samplers --- */' + NL +
    'CASTLE_UBO(1, 0) uniform CastleMaterialBlock {' + NL +
    '  vec4 u_BaseColor;' + NL +
    '  vec4 u_SpecularColor;' + NL +
    '  vec4 u_EmissiveColor;' + NL +
    '  vec4 u_PBRParams;' + NL +
    '} CastleMaterial;' + NL +
    NL +
    '/* Legacy CGE uniform aliases for Set 1 */' + NL +
    '#define castle_MaterialDiffuseAlpha CastleMaterial.u_BaseColor' + NL +
    '#define castle_MaterialBaseColor CastleMaterial.u_BaseColor' + NL +
    '#define castle_MaterialSpecular CastleMaterial.u_SpecularColor.rgb' + NL +
    '#define castle_MaterialShininess CastleMaterial.u_SpecularColor.a' + NL +
    '#define castle_MaterialEmissive CastleMaterial.u_EmissiveColor.rgb' + NL +
    '#define castle_MaterialMetallic CastleMaterial.u_EmissiveColor.a' + NL +
    '#define castle_MaterialRoughness CastleMaterial.u_PBRParams.x' + NL +
    '#define castle_MaterialNormalScale CastleMaterial.u_PBRParams.y' + NL +
    '#define castle_MaterialOcclusionStrength CastleMaterial.u_PBRParams.z' + NL +
    '#define castle_AlphaCutoff CastleMaterial.u_PBRParams.w' + NL +
    NL +
    'CASTLE_SAMPLER(1, 1) uniform sampler2D castle_base_color_texture;' + NL +
    'CASTLE_SAMPLER(1, 2) uniform sampler2D castle_normal_texture;' + NL +
    'CASTLE_SAMPLER(1, 3) uniform sampler2D castle_metallic_roughness_texture;' + NL +
    'CASTLE_SAMPLER(1, 4) uniform sampler2D castle_emissive_texture;' + NL +
    'CASTLE_SAMPLER(1, 5) uniform sampler2D castle_occlusion_texture;' + NL +
    'CASTLE_SAMPLER(1, 6) uniform sampler2D castle_brdf_lut_texture;' + NL +
    'CASTLE_SAMPLER(1, 7) uniform samplerCube castle_env_specular_texture;' + NL +
    NL +
    '/* --- Set 2: Per-Object / Skinning Uniforms --- */' + NL +
    'CASTLE_UBO(2, 0) uniform CastleSkinningBlock {' + NL +
    '  mat4 u_JointMatrices[256];' + NL +
    '  uint u_JointCount;' + NL +
    '} CastleSkinning;' + NL +
    NL +
    '#define castle_JointMatrix CastleSkinning.u_JointMatrices' + NL +
    NL +
    '/* --- Push Constants: Per-Draw Matrices --- */' + NL +
    'CASTLE_PUSH_CONSTANT uniform CastlePushConstants {' + NL +
    '  mat4 u_ModelViewMatrix;' + NL +
    '  vec4 u_NormalMatrixRow0;' + NL +
    '  vec4 u_NormalMatrixRow1;' + NL +
    '  vec4 u_NormalMatrixRow2;' + NL +
    '  vec4 u_ObjectParams;' + NL +
    '} CastleDraw;' + NL +
    NL +
    '#define castle_ModelViewMatrix CastleDraw.u_ModelViewMatrix' + NL +
    '#define castle_NormalMatrix mat3(CastleDraw.u_NormalMatrixRow0.xyz, CastleDraw.u_NormalMatrixRow1.xyz, CastleDraw.u_NormalMatrixRow2.xyz)' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateStageIO(const AStage: TRHIShaderStage): String;
begin
  case AStage of
    ssVertex:
      Result :=
        '/* --- Standard Vertex Attributes (Locations 0..7) --- */' + NL +
        'CASTLE_LOCATION(0) in vec4 castle_Vertex;' + NL +
        'CASTLE_LOCATION(1) in vec3 castle_Normal;' + NL +
        'CASTLE_LOCATION(2) in vec2 castle_MultiTexCoord0;' + NL +
        'CASTLE_LOCATION(3) in vec2 castle_MultiTexCoord1;' + NL +
        'CASTLE_LOCATION(4) in vec4 castle_ColorPerVertex;' + NL +
        'CASTLE_LOCATION(5) in vec4 castle_Tangent;' + NL +
        'CASTLE_LOCATION(6) in uvec4 castle_Joints0;' + NL +
        'CASTLE_LOCATION(7) in vec4 castle_Weights0;' + NL +
        NL +
        '/* --- Vertex-to-Fragment Varyings --- */' + NL +
        'CASTLE_LOCATION(0) out vec4 castle_vertex_eye;' + NL +
        'CASTLE_LOCATION(1) out vec3 castle_normal_eye;' + NL +
        'CASTLE_LOCATION(2) out vec2 castle_tex_coord0;' + NL +
        'CASTLE_LOCATION(3) out vec2 castle_tex_coord1;' + NL +
        'CASTLE_LOCATION(4) out vec4 castle_color_per_vertex;' + NL +
        'CASTLE_LOCATION(5) out mat3 castle_tangent_to_eye_space;' + NL;

    ssFragment:
      Result :=
        '/* --- Fragment Inputs (Must match Vertex Outputs by Location) --- */' + NL +
        'CASTLE_LOCATION(0) in vec4 castle_vertex_eye;' + NL +
        'CASTLE_LOCATION(1) in vec3 castle_normal_eye;' + NL +
        'CASTLE_LOCATION(2) in vec2 castle_tex_coord0;' + NL +
        'CASTLE_LOCATION(3) in vec2 castle_tex_coord1;' + NL +
        'CASTLE_LOCATION(4) in vec4 castle_color_per_vertex;' + NL +
        'CASTLE_LOCATION(5) in mat3 castle_tangent_to_eye_space;' + NL +
        NL +
        '/* --- Fragment Color Output --- */' + NL +
        'CASTLE_LOCATION(0) out vec4 castle_FragColor;' + NL;
  else
    Result := '';
  end;
end;

function TCastleShaderGeneratorRHI.GeneratePreamble(const AStage: TRHIShaderStage): String;
begin
  Result :=
    GenerateVersionAndLayoutMacros + NL +
    GenerateStandardUniformBlocks(AStage) + NL +
    GenerateStageIO(AStage) + NL;
end;

function TCastleShaderGeneratorRHI.GenerateBindlessPreamble(const AStage: TRHIShaderStage;
  const AMaxBindlessTextures: Cardinal): String;
var
  ArrayDecl: String;
begin
  if FBackend <> rbVulkan then
    Exit(GeneratePreamble(AStage));

  if AMaxBindlessTextures > 0 then
    ArrayDecl := Format('CASTLE_SAMPLER(1, 0) uniform sampler2D castle_BindlessTextures[%d];', [AMaxBindlessTextures])
  else
    ArrayDecl := 'CASTLE_SAMPLER(1, 0) uniform sampler2D castle_BindlessTextures[];';

  Result :=
    GenerateVersionAndLayoutMacros +
    '#extension GL_EXT_nonuniform_qualifier : require' + NL +
    '#define CASTLE_BINDLESS_TEXTURES 1' + NL +
    NL +
    GenerateStandardUniformBlocks(AStage) + NL +
    '/* --- Bindless Texture Table & Multi-Material SSBO (VK_EXT_descriptor_indexing) --- */' + NL +
    ArrayDecl + NL +
    NL +
    'struct CastleBindlessMaterialEntry {' + NL +
    '  vec4 BaseColor;' + NL +
    '  vec4 SpecularColor;' + NL +
    '  vec4 EmissiveColor;' + NL +
    '  vec4 PBRParams;' + NL +
    '  uint BaseColorTexIndex;' + NL +
    '  uint NormalTexIndex;' + NL +
    '  uint MetallicRoughnessTexIndex;' + NL +
    '  uint EmissiveTexIndex;' + NL +
    '};' + NL +
    NL +
    'CASTLE_SSBO(1, 1) readonly buffer CastleBindlessMaterialsBlock {' + NL +
    '  CastleBindlessMaterialEntry u_Materials[];' + NL +
    '} CastleBindlessMaterials;' + NL +
    NL +
    '#define castle_SampleBindless2D(TexIdx, UV) texture(castle_BindlessTextures[nonuniformEXT(uint(TexIdx))], (UV))' + NL +
    '#define castle_GetMaterialEntry(MatIdx) CastleBindlessMaterials.u_Materials[uint(MatIdx)]' + NL +
    '#define castle_DrawMaterialIndex uint(CastleDraw.u_ObjectParams.x)' + NL +
    NL +
    GenerateStageIO(AStage) + NL;
end;

function IsGLSLIdentChar(const C: Char): Boolean; inline;
begin
  Result := (C in ['a'..'z', 'A'..'Z', '0'..'9', '_']);
end;

function ContainsGLSLIdentifier(const Source, Ident: String): Boolean;
var
  StartPos, MatchPos, EndIdx, IdentLen, SrcLen: Integer;
begin
  Result := False;
  IdentLen := Length(Ident);
  SrcLen := Length(Source);
  if (IdentLen = 0) or (SrcLen < IdentLen) then Exit;

  StartPos := 1;
  while StartPos <= SrcLen - IdentLen + 1 do
  begin
    MatchPos := PosEx(Ident, Source, StartPos);
    if MatchPos = 0 then Exit(False);

    EndIdx := MatchPos + IdentLen;
    if ((MatchPos = 1) or not IsGLSLIdentChar(Source[MatchPos - 1])) and
       ((EndIdx > SrcLen) or not IsGLSLIdentChar(Source[EndIdx])) then
      Exit(True);

    StartPos := MatchPos + 1;
  end;
end;

function TCastleShaderGeneratorRHI.UpgradeLegacyGLSLBuiltIns(
  const UserEffectSource: String; const EffectDebugName: String): String;
var
  UnusedWarningsCount: Cardinal;
begin
  Result := UpgradeLegacyGLSLBuiltIns(UserEffectSource, EffectDebugName, UnusedWarningsCount);
end;

function TCastleShaderGeneratorRHI.UpgradeLegacyGLSLBuiltIns(
  const UserEffectSource: String; const EffectDebugName: String;
  out AWarningsCount: Cardinal): String;
type
  TLegacyBuiltInMapping = record
    LegacySymbol: String;
    ReplacementExpr: String;
    Description: String;
  end;
const
  LegacyBuiltIns: array[0..11] of TLegacyBuiltInMapping = (
    (LegacySymbol: 'gl_ModelViewProjectionMatrix';
     ReplacementExpr: '(castle_ProjectionMatrix * castle_ModelViewMatrix)';
     Description: 'deprecated OpenGL built-in matrix uniform'),
    (LegacySymbol: 'gl_ModelViewMatrix';
     ReplacementExpr: 'castle_ModelViewMatrix';
     Description: 'deprecated OpenGL built-in matrix uniform'),
    (LegacySymbol: 'gl_ProjectionMatrix';
     ReplacementExpr: 'castle_ProjectionMatrix';
     Description: 'deprecated OpenGL built-in matrix uniform'),
    (LegacySymbol: 'gl_NormalMatrix';
     ReplacementExpr: 'castle_NormalMatrix';
     Description: 'deprecated OpenGL built-in normal matrix uniform'),
    (LegacySymbol: 'gl_Vertex';
     ReplacementExpr: 'castle_Vertex';
     Description: 'deprecated OpenGL built-in vertex attribute'),
    (LegacySymbol: 'gl_Normal';
     ReplacementExpr: 'castle_Normal';
     Description: 'deprecated OpenGL built-in normal attribute'),
    (LegacySymbol: 'gl_MultiTexCoord0';
     ReplacementExpr: 'vec4(castle_MultiTexCoord0, 0.0, 1.0)';
     Description: 'deprecated OpenGL built-in texture coordinate attribute'),
    (LegacySymbol: 'gl_MultiTexCoord1';
     ReplacementExpr: 'vec4(castle_MultiTexCoord1, 0.0, 1.0)';
     Description: 'deprecated OpenGL built-in texture coordinate attribute'),
    (LegacySymbol: 'gl_Color';
     ReplacementExpr: 'castle_ColorPerVertex';
     Description: 'deprecated OpenGL built-in vertex color attribute'),
    (LegacySymbol: 'gl_FragColor';
     ReplacementExpr: 'castle_FragColor';
     Description: 'deprecated OpenGL built-in fragment output variable'),
    (LegacySymbol: 'texture2D';
     ReplacementExpr: 'texture';
     Description: 'deprecated GLSL 1.20 texture lookup function'),
    (LegacySymbol: 'textureCube';
     ReplacementExpr: 'texture';
     Description: 'deprecated GLSL 1.20 cube texture lookup function')
  );
var
  CompatDefines, UpgradedLines: TStringBuilder;
  Lines: TStringList;
  Line, Trimmed: String;
  I: Integer;
begin
  AWarningsCount := 0;
  if FBackend <> rbVulkan then
    Exit(UserEffectSource);

  CompatDefines := TStringBuilder.Create;
  UpgradedLines := TStringBuilder.Create;
  Lines := TStringList.Create;
  try
    for I := Low(LegacyBuiltIns) to High(LegacyBuiltIns) do
    begin
      if ContainsGLSLIdentifier(UserEffectSource, LegacyBuiltIns[I].LegacySymbol) then
      begin
        Inc(AWarningsCount);
        WritelnWarning('Shader', Format(
          'Custom shader "%s" uses %s "%s" which is removed in Vulkan GLSL #version 450. ' +
          'Auto-upgrading to "%s"; please update your Effect shader to use Castle Game Engine equivalents.',
          [EffectDebugName, LegacyBuiltIns[I].Description,
           LegacyBuiltIns[I].LegacySymbol, LegacyBuiltIns[I].ReplacementExpr]));
        CompatDefines.AppendLine(Format('#ifndef %s', [LegacyBuiltIns[I].LegacySymbol]));
        CompatDefines.AppendLine(Format('#define %s %s',
          [LegacyBuiltIns[I].LegacySymbol, LegacyBuiltIns[I].ReplacementExpr]));
        CompatDefines.AppendLine('#endif');
      end;
    end;

    Lines.Text := UserEffectSource;
    for Line in Lines do
    begin
      Trimmed := Trim(Line);
      if IsPrefix('attribute ', Trimmed, False) then
      begin
        Inc(AWarningsCount);
        WritelnWarning('Shader', Format(
          'Custom shader "%s" uses deprecated GLSL qualifier "attribute" ("%s") which is removed in #version 450. ' +
          'Auto-upgrading to "in".',
          [EffectDebugName, Trimmed]));
        UpgradedLines.AppendLine('in ' + Trim(SEnding(Trimmed, Length('attribute ') + 1)));
      end else
      if IsPrefix('varying ', Trimmed, False) then
      begin
        Inc(AWarningsCount);
        WritelnWarning('Shader', Format(
          'Custom shader "%s" uses deprecated GLSL qualifier "varying" ("%s") which is removed in #version 450. ' +
          'Auto-upgrading to "in".',
          [EffectDebugName, Trimmed]));
        UpgradedLines.AppendLine('in ' + Trim(SEnding(Trimmed, Length('varying ') + 1)));
      end else
        UpgradedLines.AppendLine(Line);
    end;

    if CompatDefines.Length > 0 then
      Result :=
        '/* --- Auto-Generated #version 450 Legacy OpenGL Compatibility Aliases --- */' + NL +
        CompatDefines.ToString + NL +
        UpgradedLines.ToString
    else
      Result := UpgradedLines.ToString;
  finally
    FreeAndNil(Lines);
    FreeAndNil(UpgradedLines);
    FreeAndNil(CompatDefines);
  end;
end;

function TCastleShaderGeneratorRHI.UpgradeUserEffectUniforms(
  const UserEffectSource: String): String;
const
  PrecisionQualifiers: array[0..2] of String = ('lowp ', 'mediump ', 'highp ');
var
  Lines: TStringList;
  UBOMembers, AliasDefines, StrippedBody: TStringBuilder;
  UpgradedInput, Line, Trimmed, DeclBody, VarType, VarName, BaseName, Qual: String;
  SpacePos, SemiPos, BracketPos, CustomSamplerSlot: Integer;
begin
  if FBackend <> rbVulkan then
    Exit(UserEffectSource);

  UpgradedInput := UpgradeLegacyGLSLBuiltIns(UserEffectSource, 'Effect');

  Lines := TStringList.Create;
  UBOMembers := TStringBuilder.Create;
  AliasDefines := TStringBuilder.Create;
  StrippedBody := TStringBuilder.Create;
  try
    Lines.Text := UpgradedInput;
    CustomSamplerSlot := 2;

    for Line in Lines do
    begin
      Trimmed := Trim(Line);
      if IsPrefix('uniform ', Trimmed, False) and (Pos('{', Trimmed) = 0) then
      begin
        DeclBody := Trim(SEnding(Trimmed, Length('uniform ') + 1));
        SemiPos := Pos(';', DeclBody);
        if SemiPos > 0 then
          DeclBody := Copy(DeclBody, 1, SemiPos - 1);

        for Qual in PrecisionQualifiers do
          if IsPrefix(Qual, DeclBody, False) then
          begin
            DeclBody := Trim(SEnding(DeclBody, Length(Qual) + 1));
            Break;
          end;

        SpacePos := Pos(' ', DeclBody);
        if SpacePos > 0 then
        begin
          VarType := Trim(Copy(DeclBody, 1, SpacePos - 1));
          VarName := Trim(Copy(DeclBody, SpacePos + 1, MaxInt));

          if IsPrefix('sampler', VarType, False) then
          begin
            StrippedBody.AppendLine(Format('CASTLE_SAMPLER(2, %d) uniform %s %s;',
              [CustomSamplerSlot, VarType, VarName]));
            Inc(CustomSamplerSlot);
          end else
          begin
            BracketPos := Pos('[', VarName);
            if BracketPos > 0 then
              BaseName := Trim(Copy(VarName, 1, BracketPos - 1))
            else
              BaseName := VarName;
            UBOMembers.AppendLine(Format('  %s u_user_%s;', [VarType, VarName]));
            AliasDefines.AppendLine(Format('#define %s CastleUserEffect.u_user_%s',
              [BaseName, BaseName]));
          end;
        end;
      end else
        StrippedBody.AppendLine(Line);
    end;

    if UBOMembers.Length > 0 then
      Result :=
        '/* --- Auto-Generated Set 2 UBO for User X3D Effect Node --- */' + NL +
        'CASTLE_UBO(2, 1) uniform CastleUserEffectBlock {' + NL +
        UBOMembers.ToString +
        '} CastleUserEffect;' + NL +
        AliasDefines.ToString + NL +
        StrippedBody.ToString
    else
      Result := StrippedBody.ToString;
  finally
    FreeAndNil(StrippedBody);
    FreeAndNil(AliasDefines);
    FreeAndNil(UBOMembers);
    FreeAndNil(Lines);
  end;
end;

function TCastleShaderGeneratorRHI.FinalizeVertexShaderSource(
  const StitchedSource: String): String;
var
  LastBracePos: Integer;
begin
  if FBackend <> rbVulkan then
    Exit(StitchedSource);

  (* Inject Vulkan clip-space depth conversion ([-1..1] -> [0..1]) before the final '}'
     of main() so CGE's OpenGL projection matrices work identically in Vulkan *)
  LastBracePos := RPos('}', StitchedSource);
  if LastBracePos > 0 then
    Result := Copy(StitchedSource, 1, LastBracePos - 1) + NL +
      '  /* Vulkan NDC depth adjustment [0..1] */' + NL +
      '  gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;' + NL +
      '}' + NL
  else
    Result := StitchedSource;
end;

function TCastleShaderGeneratorRHI.SanitizeVulkanShaderSource(
  const Source: String): String;
const
  BuiltInUniformTokens: array[0..9] of String = (
    'castle_LightSource', 'castle_projector_matrix', 'castle_ModelViewMatrix',
    'castle_ProjectionMatrix', 'castle_NormalMatrix', 'castle_JointMatrix',
    'castle_Material', 'castle_WorldEyePosition', 'castle_SceneTime', 'castle_Fog'
  );
var
  Lines: TStringList;
  ResultBuilder: TStringBuilder;
  Line, Trimmed, Token: String;
  IsBuiltIn: Boolean;
begin
  if FBackend <> rbVulkan then
    Exit(Source);

  Lines := TStringList.Create;
  ResultBuilder := TStringBuilder.Create;
  try
    Lines.Text := Source;
    for Line in Lines do
    begin
      Trimmed := Trim(Line);
      IsBuiltIn := False;
      if IsPrefix('uniform ', Trimmed, False) and (Pos('{', Trimmed) = 0) then
        for Token in BuiltInUniformTokens do
          if Pos(Token, Trimmed) > 0 then
          begin
            IsBuiltIn := True;
            Break;
          end;

      if IsBuiltIn then
        ResultBuilder.AppendLine('// [Vulkan RHI UBO]: ' + Line)
      else
        ResultBuilder.AppendLine(Line);
    end;
    Result := ResultBuilder.ToString;
  finally
    FreeAndNil(ResultBuilder);
    FreeAndNil(Lines);
  end;
end;

function TCastleShaderGeneratorRHI.GenerateScreenEffectPreamble(
  const AStage: TRHIShaderStage; const HasDepth: Boolean): String;
begin
  if FBackend <> rbVulkan then
    Exit('');

  Result :=
    '#version 450' + NL +
    '#extension GL_ARB_separate_shader_objects : enable' + NL +
    NL +
    '/* --- Screen Effect Push Constants --- */' + NL +
    'layout(push_constant) uniform CastleScreenPushConstants {' + NL +
    '  vec2 screen_size;' + NL +
    '  vec2 screen_planes;' + NL +
    '  vec4 screen_custom;' + NL +
    '} castle_Screen;' + NL +
    NL +
    '#define screen_width (castle_Screen.screen_size.x)' + NL +
    '#define screen_height (castle_Screen.screen_size.y)' + NL +
    '#define near (castle_Screen.screen_planes.x)' + NL +
    '#define far (castle_Screen.screen_planes.y)' + NL +
    NL +
    '/* --- Screen Effect Textures (Set 0) --- */' + NL +
    'layout(set = 0, binding = 0) uniform sampler2D screen;' + NL;

  if HasDepth then
    Result := Result +
      'layout(set = 0, binding = 1) uniform sampler2D screen_depth;' + NL;

  Result := Result +
    NL +
    '/* --- Compatibility Aliases --- */' + NL +
    '#define texture2D texture' + NL +
    '#define textureCube texture' + NL +
    NL;

  case AStage of
    ssVertex:
      Result := Result +
        '/* --- Vertex Shader Stage IO --- */' + NL +
        'layout(location = 0) in vec2 vertex;' + NL +
        'layout(location = 1) in vec2 tex_coord;' + NL +
        'layout(location = 0) out vec2 v_tex_coord;' + NL;
    ssFragment:
      Result := Result +
        '/* --- Fragment Shader Stage IO --- */' + NL +
        'layout(location = 0) in vec2 tex_coord;' + NL +
        'layout(location = 0) out vec4 castle_FragColor;' + NL +
        '#define gl_FragColor castle_FragColor' + NL;
  end;
end;

function TCastleShaderGeneratorRHI.GenerateComputeCullingShader(
  const AWorkgroupSizeX: Cardinal): String;
var
  EffectiveLocalSizeX: Cardinal;
begin
  if AWorkgroupSizeX = 0 then
    EffectiveLocalSizeX := 64
  else
    EffectiveLocalSizeX := AWorkgroupSizeX;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [EffectiveLocalSizeX]) + NL +
    NL +
    'layout(std140, set = 0, binding = 0) uniform CastleGpuCullingUniforms {' + NL +
    '  vec4 u_FrustumPlanes[6];' + NL +
    '  vec4 u_CameraPosition;' + NL +
    '  vec4 u_HiZParams;' + NL +
    '  uint u_InstanceCount;' + NL +
    '  uint u_EnableFrustumCulling;' + NL +
    '  uint u_EnableDistanceCulling;' + NL +
    '  uint u_CompactDrawStream;' + NL +
    '} CastleCulling;' + NL +
    NL +
    'struct CastleGpuCullingInstance {' + NL +
    '  vec4 BoundingSphere;' + NL +
    '  vec4 AABBMin;' + NL +
    '  vec4 AABBMax;' + NL +
    '  uint IndexCount;' + NL +
    '  uint FirstIndex;' + NL +
    '  int  VertexOffset;' + NL +
    '  uint FirstInstance;' + NL +
    '  uint InstanceCount;' + NL +
    '  uint MaterialIndex;' + NL +
    '  uint Padding0;' + NL +
    '  uint Padding1;' + NL +
    '};' + NL +
    NL +
    'struct CastleDrawIndexedIndirectCommand {' + NL +
    '  uint indexCount;' + NL +
    '  uint instanceCount;' + NL +
    '  uint firstIndex;' + NL +
    '  int  vertexOffset;' + NL +
    '  uint firstInstance;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) readonly buffer CastleCullingInstancesBlock {' + NL +
    '  CastleGpuCullingInstance u_Instances[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 2) writeonly buffer CastleIndirectCommandsBlock {' + NL +
    '  CastleDrawIndexedIndirectCommand u_Commands[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 3) buffer CastleVisibilityOutputBlock {' + NL +
    '  uint u_VisibleCount;' + NL +
    '  uint u_VisibilityFlags[];' + NL +
    '};' + NL +
    NL +
    'bool IsSphereInsideFrustum(vec3 center, float radius) {' + NL +
    '  for (int i = 0; i < 6; ++i) {' + NL +
    '    vec4 plane = CastleCulling.u_FrustumPlanes[i];' + NL +
    '    if (dot(plane.xyz, center) + plane.w < -radius)' + NL +
    '      return false;' + NL +
    '  }' + NL +
    '  return true;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint idx = gl_GlobalInvocationID.x;' + NL +
    '  if (idx >= CastleCulling.u_InstanceCount) return;' + NL +
    '  CastleGpuCullingInstance inst = u_Instances[idx];' + NL +
    '  bool visible = true;' + NL +
    '  if (CastleCulling.u_EnableFrustumCulling != 0u) {' + NL +
    '    visible = IsSphereInsideFrustum(inst.BoundingSphere.xyz, inst.BoundingSphere.w);' + NL +
    '  }' + NL +
    '  if (visible && (CastleCulling.u_EnableDistanceCulling != 0u) && (CastleCulling.u_CameraPosition.w > 0.0)) {' + NL +
    '    float dist = distance(inst.BoundingSphere.xyz, CastleCulling.u_CameraPosition.xyz) - inst.BoundingSphere.w;' + NL +
    '    if (dist > CastleCulling.u_CameraPosition.w)' + NL +
    '      visible = false;' + NL +
    '  }' + NL +
    '  u_VisibilityFlags[idx] = visible ? 1u : 0u;' + NL +
    '  if (CastleCulling.u_CompactDrawStream != 0u) {' + NL +
    '    if (visible) {' + NL +
    '      uint outSlot = atomicAdd(u_VisibleCount, 1u);' + NL +
    '      CastleDrawIndexedIndirectCommand cmd;' + NL +
    '      cmd.indexCount = inst.IndexCount;' + NL +
    '      cmd.instanceCount = inst.InstanceCount;' + NL +
    '      cmd.firstIndex = inst.FirstIndex;' + NL +
    '      cmd.vertexOffset = inst.VertexOffset;' + NL +
    '      cmd.firstInstance = inst.FirstInstance;' + NL +
    '      u_Commands[outSlot] = cmd;' + NL +
    '    }' + NL +
    '  } else {' + NL +
    '    if (visible) atomicAdd(u_VisibleCount, 1u);' + NL +
    '    CastleDrawIndexedIndirectCommand cmd;' + NL +
    '    cmd.indexCount = inst.IndexCount;' + NL +
    '    cmd.instanceCount = visible ? inst.InstanceCount : 0u;' + NL +
    '    cmd.firstIndex = inst.FirstIndex;' + NL +
    '    cmd.vertexOffset = inst.VertexOffset;' + NL +
    '    cmd.firstInstance = inst.FirstInstance;' + NL +
    '    u_Commands[idx] = cmd;' + NL +
    '  }' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateHiZDownsampleComputeShader(
  const AWorkgroupSizeX: Cardinal;
  const AWorkgroupSizeY: Cardinal): String;
var
  LocalSizeX, LocalSizeY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then
    LocalSizeX := 8
  else
    LocalSizeX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then
    LocalSizeY := 8
  else
    LocalSizeY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalSizeX, LocalSizeY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_SrcDepthMip;' + NL +
    'layout(set = 0, binding = 1, r32f) uniform writeonly image2D u_DstDepthMip;' + NL +
    NL +
    'layout(push_constant) uniform CastleHiZPushConstants {' + NL +
    '  uvec2 u_DstMipSize;' + NL +
    '  uvec2 u_SrcMipSize;' + NL +
    '} pc;' + NL +
    NL +
    'void main() {' + NL +
    '  uvec2 dstCoord = gl_GlobalInvocationID.xy;' + NL +
    '  if (dstCoord.x >= pc.u_DstMipSize.x || dstCoord.y >= pc.u_DstMipSize.y) return;' + NL +
    '  ivec2 srcBase = ivec2(dstCoord * 2u);' + NL +
    '  ivec2 maxSrc = ivec2(max(pc.u_SrcMipSize, uvec2(1u))) - ivec2(1);' + NL +
    '  float d00 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(0, 0), ivec2(0), maxSrc), 0).r;' + NL +
    '  float d10 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(1, 0), ivec2(0), maxSrc), 0).r;' + NL +
    '  float d01 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(0, 1), ivec2(0), maxSrc), 0).r;' + NL +
    '  float d11 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(1, 1), ivec2(0), maxSrc), 0).r;' + NL +
    '  float maxDepth = max(max(d00, d10), max(d01, d11));' + NL +
    '  if (((pc.u_SrcMipSize.x & 1u) != 0u) && (dstCoord.x + 1u == pc.u_DstMipSize.x)) {' + NL +
    '    float d20 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(2, 0), ivec2(0), maxSrc), 0).r;' + NL +
    '    float d21 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(2, 1), ivec2(0), maxSrc), 0).r;' + NL +
    '    maxDepth = max(maxDepth, max(d20, d21));' + NL +
    '  }' + NL +
    '  if (((pc.u_SrcMipSize.y & 1u) != 0u) && (dstCoord.y + 1u == pc.u_DstMipSize.y)) {' + NL +
    '    float d02 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(0, 2), ivec2(0), maxSrc), 0).r;' + NL +
    '    float d12 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(1, 2), ivec2(0), maxSrc), 0).r;' + NL +
    '    maxDepth = max(maxDepth, max(d02, d12));' + NL +
    '  }' + NL +
    '  imageStore(u_DstDepthMip, ivec2(dstCoord), vec4(maxDepth, 0.0, 0.0, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GeneratePBRFunctions: String;
begin
  Result :=
    '/* --- glTF 2.0 / X3D PhysicalMaterial Cook-Torrance Microfacet GGX BRDF --- */' + NL +
    'const float CASTLE_PI = 3.14159265358979323846;' + NL +
    NL +
    'float DistributionGGX(float NdotH, float roughness) {' + NL +
    '  float alpha = max(roughness * roughness, 0.002025);' + NL +
    '  float alpha2 = alpha * alpha;' + NL +
    '  float denom = (NdotH * NdotH) * (alpha2 - 1.0) + 1.0;' + NL +
    '  return alpha2 / max(CASTLE_PI * denom * denom, 1e-7);' + NL +
    '}' + NL +
    NL +
    'float GeometrySmithGGXCorrelated(float NdotV, float NdotL, float roughness) {' + NL +
    '  float alpha = max(roughness * roughness, 0.002025);' + NL +
    '  float alpha2 = alpha * alpha;' + NL +
    '  float ggxV = NdotL * sqrt(max(NdotV * NdotV * (1.0 - alpha2) + alpha2, 1e-7));' + NL +
    '  float ggxL = NdotV * sqrt(max(NdotL * NdotL * (1.0 - alpha2) + alpha2, 1e-7));' + NL +
    '  return 0.5 / max(ggxV + ggxL, 1e-5);' + NL +
    '}' + NL +
    NL +
    'vec3 FresnelSchlick(float cosTheta, vec3 F0) {' + NL +
    '  float clamped = clamp(1.0 - cosTheta, 0.0, 1.0);' + NL +
    '  float c2 = clamped * clamped;' + NL +
    '  return F0 + (1.0 - F0) * (c2 * c2 * clamped);' + NL +
    '}' + NL +
    NL +
    'vec3 FresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness) {' + NL +
    '  float clamped = clamp(1.0 - cosTheta, 0.0, 1.0);' + NL +
    '  float c2 = clamped * clamped;' + NL +
    '  return F0 + (max(vec3(1.0 - roughness), F0) - F0) * (c2 * c2 * clamped);' + NL +
    '}' + NL +
    NL +
    '/* Screen-space derivative cotangent-frame TBN normal mapping (Christian Schuler) */' + NL +
    'vec3 PerturbNormalCotangent(vec3 N, vec3 V, vec2 texCoord, vec3 tangentNormal, float normalScale) {' + NL +
    '  vec3 dp1 = dFdx(-V);' + NL +
    '  vec3 dp2 = dFdy(-V);' + NL +
    '  vec2 duv1 = dFdx(texCoord);' + NL +
    '  vec2 duv2 = dFdy(texCoord);' + NL +
    '  vec3 dp2perp = cross(dp2, N);' + NL +
    '  vec3 dp1perp = cross(N, dp1);' + NL +
    '  vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;' + NL +
    '  vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;' + NL +
    '  float invmax = inversesqrt(max(dot(T, T), dot(B, B)) + 1e-7);' + NL +
    '  mat3 TBN = mat3(T * invmax, B * invmax, N);' + NL +
    '  vec3 scaledNormal = normalize(tangentNormal * vec3(normalScale, normalScale, 1.0));' + NL +
    '  return normalize(TBN * scaledNormal);' + NL +
    '}' + NL +
    NL +
    'vec3 PerturbNormalTBN(mat3 TBN, vec3 tangentNormal, float normalScale) {' + NL +
    '  vec3 scaledNormal = normalize(tangentNormal * vec3(normalScale, normalScale, 1.0));' + NL +
    '  return normalize(TBN * scaledNormal);' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateDirectCookTorranceGGX(vec3 N, vec3 V, vec3 L, vec3 lightRadiance,' + NL +
    '  vec3 albedo, float metallic, float roughness) {' + NL +
    '  vec3 H = normalize(V + L);' + NL +
    '  float NdotL = max(dot(N, L), 0.0);' + NL +
    '  float NdotV = max(dot(N, V), 1e-4);' + NL +
    '  float NdotH = max(dot(N, H), 0.0);' + NL +
    '  float HdotV = max(dot(H, V), 0.0);' + NL +
    '  if (NdotL <= 0.0) return vec3(0.0);' + NL +
    '  vec3 F0 = mix(vec3(0.04), albedo, metallic);' + NL +
    '  float D = DistributionGGX(NdotH, roughness);' + NL +
    '  float Vis = GeometrySmithGGXCorrelated(NdotV, NdotL, roughness);' + NL +
    '  vec3 F = FresnelSchlick(HdotV, F0);' + NL +
    '  vec3 specular = (D * Vis) * F;' + NL +
    '  vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);' + NL +
    '  vec3 diffuse = kD * albedo / CASTLE_PI;' + NL +
    '  return (diffuse + specular) * lightRadiance * NdotL;' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateIBLCookTorranceGGX(vec3 N, vec3 V, vec3 albedo, float metallic,' + NL +
    '  float roughness, float ao, vec3 diffuseIrradiance, vec3 prefilteredEnvColor, vec2 brdfLut) {' + NL +
    '  float NdotV = max(dot(N, V), 1e-4);' + NL +
    '  vec3 F0 = mix(vec3(0.04), albedo, metallic);' + NL +
    '  vec3 F = FresnelSchlickRoughness(NdotV, F0, roughness);' + NL +
    '  vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);' + NL +
    '  vec3 diffuse = diffuseIrradiance * albedo * kD;' + NL +
    '  vec3 specular = prefilteredEnvColor * (F * brdfLut.x + brdfLut.y);' + NL +
    '  return (diffuse + specular) * ao;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateDefault3DVertexShader(
  const HasSkinning: Boolean; const HasTangents: Boolean): String;
var
  Body: String;
begin
  Body :=
    GeneratePreamble(ssVertex) +
    'void main() {' + NL +
    '  vec4 localPos = castle_Vertex;' + NL +
    '  vec3 localNormal = castle_Normal;' + NL +
    '  vec3 localTangent = castle_Tangent.xyz;' + NL;

  if HasSkinning then
    Body := Body +
      '  if (CastleSkinning.u_JointCount > 0u) {' + NL +
      '    mat4 skinMat =' + NL +
      '      castle_Weights0.x * CastleSkinning.u_JointMatrices[castle_Joints0.x] +' + NL +
      '      castle_Weights0.y * CastleSkinning.u_JointMatrices[castle_Joints0.y] +' + NL +
      '      castle_Weights0.z * CastleSkinning.u_JointMatrices[castle_Joints0.z] +' + NL +
      '      castle_Weights0.w * CastleSkinning.u_JointMatrices[castle_Joints0.w];' + NL +
      '    localPos = skinMat * localPos;' + NL +
      '    localNormal = mat3(skinMat) * localNormal;' + NL +
      '    localTangent = mat3(skinMat) * localTangent;' + NL +
      '  }' + NL;

  Body := Body +
    '  castle_vertex_eye = castle_ModelViewMatrix * localPos;' + NL +
    '  castle_normal_eye = normalize(castle_NormalMatrix * localNormal);' + NL +
    '  castle_tex_coord0 = castle_MultiTexCoord0;' + NL +
    '  castle_tex_coord1 = castle_MultiTexCoord1;' + NL +
    '  castle_color_per_vertex = castle_ColorPerVertex;' + NL;

  if HasTangents then
    Body := Body +
      '  vec3 T = normalize(castle_NormalMatrix * localTangent);' + NL +
      '  vec3 N = castle_normal_eye;' + NL +
      '  T = normalize(T - dot(T, N) * N);' + NL +
      '  vec3 B = cross(N, T) * castle_Tangent.w;' + NL +
      '  castle_tangent_to_eye_space = mat3(T, B, N);' + NL
  else
    Body := Body +
      '  castle_tangent_to_eye_space = mat3(1.0);' + NL;

  Body := Body +
    '  gl_Position = castle_ProjectionMatrix * castle_vertex_eye;' + NL +
    '}' + NL;

  Result := FinalizeVertexShaderSource(Body);
end;

function TCastleShaderGeneratorRHI.GenerateClusteredForwardAndShadowFunctions: String;
begin
  Result :=
    '/* Set 0 / Set 1 Clustered Forward+ & Shadow Atlas Bindings */' + NL +
    'struct CastleClusteredLightData {' + NL +
    '  vec4 PositionAndRange;' + NL +
    '  vec4 DirectionAndSpotCos;' + NL +
    '  vec4 ColorAndIntensity;' + NL +
    '  vec4 ShadowAndTypeParams;' + NL +
    '};' + NL +
    NL +
    'struct CastleClusterGridEntryData {' + NL +
    '  uint Offset;' + NL +
    '  uint Count;' + NL +
    '};' + NL +
    NL +
    'struct CastlePositionalShadowTileData {' + NL +
    '  mat4 LightViewProjMatrix;' + NL +
    '  vec4 AtlasUVScaleOffset;' + NL +
    '};' + NL +
    NL +
    'layout(std140, set = 0, binding = 2) uniform CastleClusterCullingBlock {' + NL +
    '  mat4 u_InvProjectionMatrix;' + NL +
    '  vec4 u_ScreenAndDepthParams;' + NL +
    '  uvec4 u_ClusterGridDim;' + NL +
    '  vec4 u_LogDepthParams;' + NL +
    '} CastleClusterUniforms;' + NL +
    NL +
    'layout(std430, set = 0, binding = 3) readonly buffer CastleClusteredLightsBuffer {' + NL +
    '  CastleClusteredLightData u_ClusteredLights[];' + NL +
    '} CastleClusteredLightsSSBO;' + NL +
    NL +
    'layout(std430, set = 0, binding = 4) readonly buffer CastleClusterGridBuffer {' + NL +
    '  CastleClusterGridEntryData u_ClusterGrid[];' + NL +
    '} CastleClusterGridSSBO;' + NL +
    NL +
    'layout(std430, set = 0, binding = 5) readonly buffer CastleClusterLightIndexBuffer {' + NL +
    '  uint u_ClusterLightIndices[];' + NL +
    '} CastleClusterLightIndexSSBO;' + NL +
    NL +
    'layout(std140, set = 0, binding = 6) uniform CastleCascadeShadowBlock {' + NL +
    '  mat4 u_CascadeViewProjMatrix[4];' + NL +
    '  vec4 u_CascadeAtlasUVScaleOffset[4];' + NL +
    '  vec4 u_CascadeSplitDepths;' + NL +
    '} CastleCascadeShadows;' + NL +
    NL +
    'layout(std430, set = 0, binding = 7) readonly buffer CastlePositionalShadowTilesBuffer {' + NL +
    '  CastlePositionalShadowTileData u_ShadowTiles[];' + NL +
    '} CastlePositionalShadowTilesSSBO;' + NL +
    NL +
    'layout(set = 1, binding = 8) uniform sampler2D castle_shadow_atlas_texture;' + NL +
    NL +
    'uvec3 ComputeClusterIndex3D(vec2 fragCoord, float positiveViewDepth) {' + NL +
    '  vec2 screenSize = max(CastleClusterUniforms.u_ScreenAndDepthParams.xy, vec2(1.0));' + NL +
    '  float zNear = max(CastleClusterUniforms.u_ScreenAndDepthParams.z, 1e-3);' + NL +
    '  float zFar = max(CastleClusterUniforms.u_ScreenAndDepthParams.w, zNear + 1e-2);' + NL +
    '  float clampedZ = clamp(positiveViewDepth, zNear, zFar);' + NL +
    '  uint cx = min(uint((fragCoord.x / screenSize.x) * float(CastleClusterUniforms.u_ClusterGridDim.x)), CastleClusterUniforms.u_ClusterGridDim.x - 1u);' + NL +
    '  uint cy = min(uint((fragCoord.y / screenSize.y) * float(CastleClusterUniforms.u_ClusterGridDim.y)), CastleClusterUniforms.u_ClusterGridDim.y - 1u);' + NL +
    '  float sliceF = log(clampedZ / zNear) / max(log(zFar / zNear), 1e-5) * float(CastleClusterUniforms.u_ClusterGridDim.z);' + NL +
    '  uint cz = min(uint(max(sliceF, 0.0)), CastleClusterUniforms.u_ClusterGridDim.z - 1u);' + NL +
    '  return uvec3(cx, cy, cz);' + NL +
    '}' + NL +
    NL +
    'uint FlattenClusterIndex(uvec3 clusterCoord) {' + NL +
    '  return (clusterCoord.z * CastleClusterUniforms.u_ClusterGridDim.y + clusterCoord.y) * CastleClusterUniforms.u_ClusterGridDim.x + clusterCoord.x;' + NL +
    '}' + NL +
    NL +
    'float SampleShadowAtlasPCF3x3(vec2 atlasUV, float compareDepth, vec2 texelSize) {' + NL +
    '  float shadow = 0.0;' + NL +
    '  for (int y = -1; y <= 1; ++y) {' + NL +
    '    for (int x = -1; x <= 1; ++x) {' + NL +
    '      vec2 sampleUV = atlasUV + vec2(float(x), float(y)) * texelSize;' + NL +
    '      float closestDepth = texture(castle_shadow_atlas_texture, sampleUV).r;' + NL +
    '      shadow += (compareDepth <= closestDepth) ? 1.0 : 0.0;' + NL +
    '    }' + NL +
    '  }' + NL +
    '  return shadow * (1.0 / 9.0);' + NL +
    '}' + NL +
    NL +
    'float EvaluateDirectionalCascadeShadow(vec3 worldPos, float positiveViewDepth, float NdotL) {' + NL +
    '  int cascadeIdx = 3;' + NL +
    '  if (positiveViewDepth < CastleCascadeShadows.u_CascadeSplitDepths.x) cascadeIdx = 0;' + NL +
    '  else if (positiveViewDepth < CastleCascadeShadows.u_CascadeSplitDepths.y) cascadeIdx = 1;' + NL +
    '  else if (positiveViewDepth < CastleCascadeShadows.u_CascadeSplitDepths.z) cascadeIdx = 2;' + NL +
    '  vec4 lightClip = CastleCascadeShadows.u_CascadeViewProjMatrix[cascadeIdx] * vec4(worldPos, 1.0);' + NL +
    '  vec3 lightNDC = lightClip.xyz / max(lightClip.w, 1e-5);' + NL +
    '  vec2 uv01 = lightNDC.xy * 0.5 + 0.5;' + NL +
    '  if (uv01.x < 0.0 || uv01.x > 1.0 || uv01.y < 0.0 || uv01.y > 1.0 || lightNDC.z < 0.0 || lightNDC.z > 1.0) return 1.0;' + NL +
    '  vec4 scaleOffset = CastleCascadeShadows.u_CascadeAtlasUVScaleOffset[cascadeIdx];' + NL +
    '  vec2 atlasUV = uv01 * scaleOffset.xy + scaleOffset.zw;' + NL +
    '  float slopeBias = max(0.0025 * (1.0 - max(NdotL, 0.0)), 0.0005);' + NL +
    '  vec2 texelSize = vec2(1.0) / max(vec2(textureSize(castle_shadow_atlas_texture, 0)), vec2(1.0));' + NL +
    '  return SampleShadowAtlasPCF3x3(atlasUV, lightNDC.z - slopeBias, texelSize);' + NL +
    '}' + NL +
    NL +
    'float EvaluatePositionalAtlasShadow(vec3 worldPos, int shadowTileIdx, float bias) {' + NL +
    '  if (shadowTileIdx < 0) return 1.0;' + NL +
    '  CastlePositionalShadowTileData tile = CastlePositionalShadowTilesSSBO.u_ShadowTiles[shadowTileIdx];' + NL +
    '  vec4 lightClip = tile.LightViewProjMatrix * vec4(worldPos, 1.0);' + NL +
    '  if (lightClip.w <= 1e-5) return 1.0;' + NL +
    '  vec3 lightNDC = lightClip.xyz / lightClip.w;' + NL +
    '  vec2 uv01 = lightNDC.xy * 0.5 + 0.5;' + NL +
    '  if (uv01.x < 0.0 || uv01.x > 1.0 || uv01.y < 0.0 || uv01.y > 1.0 || lightNDC.z < 0.0 || lightNDC.z > 1.0) return 1.0;' + NL +
    '  vec2 atlasUV = uv01 * tile.AtlasUVScaleOffset.xy + tile.AtlasUVScaleOffset.zw;' + NL +
    '  vec2 texelSize = vec2(1.0) / max(vec2(textureSize(castle_shadow_atlas_texture, 0)), vec2(1.0));' + NL +
    '  return SampleShadowAtlasPCF3x3(atlasUV, lightNDC.z - max(bias, 0.0005), texelSize);' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateClusteredForwardLights(vec2 fragCoord, vec3 eyePos, vec3 worldPos, vec3 N, vec3 V, vec3 baseColor, float metallic, float roughness, bool useShadows) {' + NL +
    '  float positiveViewDepth = max(-eyePos.z, 1e-3);' + NL +
    '  uvec3 clusterCoord = ComputeClusterIndex3D(fragCoord, positiveViewDepth);' + NL +
    '  uint clusterIdx = FlattenClusterIndex(clusterCoord);' + NL +
    '  CastleClusterGridEntryData entry = CastleClusterGridSSBO.u_ClusterGrid[clusterIdx];' + NL +
    '  vec3 totalRadiance = vec3(0.0);' + NL +
    '  uint count = min(entry.Count, 64u);' + NL +
    '  for (uint i = 0u; i < count; ++i) {' + NL +
    '    uint lightIdx = CastleClusterLightIndexSSBO.u_ClusterLightIndices[entry.Offset + i];' + NL +
    '    CastleClusteredLightData cl = CastleClusteredLightsSSBO.u_ClusteredLights[lightIdx];' + NL +
    '    int lightType = int(cl.ShadowAndTypeParams.x + 0.5);' + NL +
    '    vec3 L;' + NL +
    '    float attenuation = 1.0;' + NL +
    '    if (lightType == 0) {' + NL +
    '      L = normalize(-cl.DirectionAndSpotCos.xyz);' + NL +
    '    } else {' + NL +
    '      vec3 toLight = cl.PositionAndRange.xyz - eyePos;' + NL +
    '      float dist = length(toLight);' + NL +
    '      float range = max(cl.PositionAndRange.w, 1e-4);' + NL +
    '      if (dist >= range) continue;' + NL +
    '      L = toLight / max(dist, 1e-5);' + NL +
    '      float distRatio = dist / range;' + NL +
    '      float windowFactor = max(1.0 - pow(distRatio, 4.0), 0.0);' + NL +
    '      attenuation = (windowFactor * windowFactor) / (dist * dist + 1.0);' + NL +
    '      if (lightType == 2) {' + NL +
    '        float cosDir = dot(-L, normalize(cl.DirectionAndSpotCos.xyz));' + NL +
    '        float outerCos = cl.DirectionAndSpotCos.w;' + NL +
    '        float innerCos = max(cl.ShadowAndTypeParams.y, outerCos + 1e-4);' + NL +
    '        float spotFactor = clamp((cosDir - outerCos) / (innerCos - outerCos), 0.0, 1.0);' + NL +
    '        attenuation *= spotFactor * spotFactor;' + NL +
    '      }' + NL +
    '    }' + NL +
    '    if (attenuation <= 0.0) continue;' + NL +
    '    float shadowVis = 1.0;' + NL +
    '    if (useShadows) {' + NL +
    '      if (lightType == 0) {' + NL +
    '        shadowVis = EvaluateDirectionalCascadeShadow(worldPos, positiveViewDepth, max(dot(N, L), 0.0));' + NL +
    '      } else {' + NL +
    '        int tileIdx = int(floor(cl.ShadowAndTypeParams.z + 0.5));' + NL +
    '        shadowVis = EvaluatePositionalAtlasShadow(worldPos, tileIdx, cl.ShadowAndTypeParams.w);' + NL +
    '      }' + NL +
    '    }' + NL +
    '    vec3 radiance = cl.ColorAndIntensity.rgb * (cl.ColorAndIntensity.w * attenuation * shadowVis);' + NL +
    '    totalRadiance += EvaluateDirectCookTorranceGGX(N, V, L, radiance, baseColor, metallic, roughness);' + NL +
    '  }' + NL +
    '  return totalRadiance;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateDefault3DFragmentShader(
  const HasBaseColorTex: Boolean;
  const HasNormalTex: Boolean;
  const HasMetallicRoughnessTex: Boolean;
  const HasEmissiveTex: Boolean;
  const HasOcclusionTex: Boolean;
  const HasIBL: Boolean;
  const UseAlphaTest: Boolean;
  const HasClusteredForward: Boolean;
  const HasCascadedShadows: Boolean): String;
begin
  Result :=
    GeneratePreamble(ssFragment) +
    GeneratePBRFunctions + NL;

  if HasClusteredForward or HasCascadedShadows then
    Result := Result + GenerateClusteredForwardAndShadowFunctions + NL;

  Result := Result +
    'void main() {' + NL +
    '  vec4 baseColor = castle_MaterialBaseColor;' + NL;

  if HasBaseColorTex then
    Result := Result +
      '  baseColor *= texture(castle_base_color_texture, castle_tex_coord0);' + NL;

  if UseAlphaTest then
    Result := Result +
      '  if (baseColor.a < castle_AlphaCutoff) discard;' + NL;

  Result := Result +
    '  /* Unlit Material Early Out (SpecularColor.a < 0.0) */' + NL +
    '  if (castle_MaterialShininess < 0.0) {' + NL +
    '    vec3 unlitColor = baseColor.rgb + castle_MaterialEmissive;' + NL;
  if HasEmissiveTex then
    Result := Result +
      '    unlitColor += texture(castle_emissive_texture, castle_tex_coord0).rgb;' + NL;
  Result := Result +
    '    castle_FragColor = vec4(unlitColor, baseColor.a);' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  float metallic = clamp(castle_MaterialMetallic, 0.0, 1.0);' + NL +
    '  float roughness = clamp(castle_MaterialRoughness, 0.04, 1.0);' + NL;

  if HasMetallicRoughnessTex then
    Result := Result +
      '  vec4 mrSample = texture(castle_metallic_roughness_texture, castle_tex_coord0);' + NL +
      '  roughness = clamp(roughness * mrSample.g, 0.04, 1.0);' + NL +
      '  metallic = clamp(metallic * mrSample.b, 0.0, 1.0);' + NL;

  Result := Result +
    '  float ao = 1.0;' + NL;
  if HasOcclusionTex then
    Result := Result +
      '  float occSample = texture(castle_occlusion_texture, castle_tex_coord0).r;' + NL +
      '  ao = mix(1.0, occSample, clamp(castle_MaterialOcclusionStrength, 0.0, 1.0));' + NL;

  Result := Result +
    '  vec3 N = normalize(castle_normal_eye);' + NL +
    '  vec3 V = normalize(-castle_vertex_eye.xyz);' + NL;

  if HasNormalTex then
    Result := Result +
      '  vec3 tangentNormal = texture(castle_normal_texture, castle_tex_coord0).xyz * 2.0 - 1.0;' + NL +
      '  N = PerturbNormalCotangent(N, -castle_vertex_eye.xyz, castle_tex_coord0, tangentNormal, castle_MaterialNormalScale);' + NL;

  Result := Result +
    '  vec3 Lo = vec3(0.0);' + NL;

  if HasClusteredForward then
  begin
    Result := Result +
      '  vec3 worldPos = (castle_ViewMatrixInverse * castle_vertex_eye).xyz;' + NL +
      Format('  Lo += EvaluateClusteredForwardLights(gl_FragCoord.xy, castle_vertex_eye.xyz, worldPos, N, V, baseColor.rgb, metallic, roughness, %s);',
        [IfThen(HasCascadedShadows, 'true', 'false')]) + NL;
  end else
  begin
    Result := Result +
      '  uint lightCount = min(castle_LightCount, 32u);' + NL +
      '  for (uint i = 0u; i < lightCount; ++i) {' + NL +
      '    CastleLightData light = CastleLights.u_Lights[i];' + NL +
      '    vec3 L;' + NL +
      '    float attenuation = 1.0;' + NL +
      '    if (light.Position.w == 0.0) {' + NL +
      '      L = normalize(light.Position.xyz);' + NL +
      '    } else {' + NL +
      '      vec3 toLight = light.Position.xyz - castle_vertex_eye.xyz;' + NL +
      '      float dist = length(toLight);' + NL +
      '      L = toLight / max(dist, 1e-5);' + NL +
      '      float attenDenom = light.Attenuation.x + light.Attenuation.y * dist + light.Attenuation.z * dist * dist;' + NL +
      '      if (attenDenom > 0.0) attenuation = 1.0 / attenDenom;' + NL +
      '      if (light.Color.w > 0.0 && dist > light.Color.w) attenuation = 0.0;' + NL +
      '      if (light.Position.w > 1.5 && light.SpotDirection.w >= 0.0) {' + NL +
      '        float cosDir = dot(-L, normalize(light.SpotDirection.xyz));' + NL +
      '        if (cosDir < light.SpotDirection.w) attenuation = 0.0;' + NL +
      '      }' + NL +
      '    }' + NL +
      '    float shadowVis = 1.0;' + NL;
    if HasCascadedShadows then
      Result := Result +
        '    if (light.Position.w == 0.0) {' + NL +
        '      vec3 worldPos = (castle_ViewMatrixInverse * castle_vertex_eye).xyz;' + NL +
        '      shadowVis = EvaluateDirectionalCascadeShadow(worldPos, max(-castle_vertex_eye.z, 1e-3), max(dot(N, L), 0.0));' + NL +
        '    }' + NL;
    Result := Result +
      '    vec3 radiance = light.Color.rgb * (attenuation * shadowVis);' + NL +
      '    Lo += EvaluateDirectCookTorranceGGX(N, V, L, radiance, baseColor.rgb, metallic, roughness);' + NL +
      '    Lo += light.AmbientColor.rgb * baseColor.rgb * ao;' + NL +
      '  }' + NL;
  end;

  if HasIBL then
    Result := Result +
      '  float NdotV = max(dot(N, V), 1e-4);' + NL +
      '  vec3 R = reflect(-V, N);' + NL +
      '  vec3 worldR = mat3(castle_ViewMatrixInverse) * R;' + NL +
      '  vec3 prefilteredEnv = textureLod(castle_env_specular_texture, worldR, roughness * 4.0).rgb;' + NL +
      '  vec2 brdfLut = texture(castle_brdf_lut_texture, vec2(NdotV, roughness)).rg;' + NL +
      '  vec3 diffuseIrradiance = textureLod(castle_env_specular_texture, mat3(castle_ViewMatrixInverse) * N, 4.0).rgb;' + NL +
      '  Lo += EvaluateIBLCookTorranceGGX(N, V, baseColor.rgb, metallic, roughness, ao, diffuseIrradiance, prefilteredEnv, brdfLut);' + NL;

  Result := Result +
    '  vec3 emissive = castle_MaterialEmissive;' + NL;
  if HasEmissiveTex then
    Result := Result +
      '  emissive += texture(castle_emissive_texture, castle_tex_coord0).rgb;' + NL;

  Result := Result +
    '  castle_FragColor = vec4(Lo + emissive, baseColor.a);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateIBLBrdfLutComputeShader(
  const AWorkgroupSizeX: Cardinal;
  const AWorkgroupSizeY: Cardinal): String;
var
  LocalSizeX, LocalSizeY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then
    LocalSizeX := 8
  else
    LocalSizeX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then
    LocalSizeY := 8
  else
    LocalSizeY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalSizeX, LocalSizeY]) + NL +
    NL +
    'layout(set = 0, binding = 0, rgba16f) uniform writeonly image2D u_BrdfLutImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleIBLBrdfLutPushConstants {' + NL +
    '  uvec2 u_LutSize;' + NL +
    '  uint  u_SampleCount;' + NL +
    '  uint  u_Reserved;' + NL +
    '} pc;' + NL +
    NL +
    'const float CASTLE_PI = 3.14159265358979323846;' + NL +
    NL +
    'float RadicalInverse_VdC(uint bits) {' + NL +
    '  bits = (bits << 16u) | (bits >> 16u);' + NL +
    '  bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);' + NL +
    '  bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);' + NL +
    '  bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);' + NL +
    '  bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);' + NL +
    '  return float(bits) * 2.3283064365386963e-10;' + NL +
    '}' + NL +
    NL +
    'vec2 Hammersley(uint i, uint N) {' + NL +
    '  return vec2(float(i) / float(max(N, 1u)), RadicalInverse_VdC(i));' + NL +
    '}' + NL +
    NL +
    'vec3 ImportanceSampleGGX(vec2 Xi, vec3 N, float roughness) {' + NL +
    '  float a = roughness * roughness;' + NL +
    '  float phi = 2.0 * CASTLE_PI * Xi.x;' + NL +
    '  float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));' + NL +
    '  float sinTheta = sqrt(max(1.0 - cosTheta * cosTheta, 0.0));' + NL +
    '  vec3 H = vec3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);' + NL +
    '  vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);' + NL +
    '  vec3 tangent = normalize(cross(up, N));' + NL +
    '  vec3 bitangent = cross(N, tangent);' + NL +
    '  return normalize(tangent * H.x + bitangent * H.y + N * H.z);' + NL +
    '}' + NL +
    NL +
    'float GeometrySchlickGGX_IBL(float NdotV, float roughness) {' + NL +
    '  float a = roughness;' + NL +
    '  float k = (a * a) * 0.5;' + NL +
    '  return NdotV / max(NdotV * (1.0 - k) + k, 1e-5);' + NL +
    '}' + NL +
    NL +
    'float GeometrySmith_IBL(float NdotV, float NdotL, float roughness) {' + NL +
    '  return GeometrySchlickGGX_IBL(NdotV, roughness) * GeometrySchlickGGX_IBL(NdotL, roughness);' + NL +
    '}' + NL +
    NL +
    'vec2 IntegrateBRDF(float NdotV, float roughness, uint sampleCount) {' + NL +
    '  vec3 V = vec3(sqrt(max(1.0 - NdotV * NdotV, 0.0)), 0.0, NdotV);' + NL +
    '  float A = 0.0;' + NL +
    '  float B = 0.0;' + NL +
    '  vec3 N = vec3(0.0, 0.0, 1.0);' + NL +
    '  for (uint i = 0u; i < sampleCount; ++i) {' + NL +
    '    vec2 Xi = Hammersley(i, sampleCount);' + NL +
    '    vec3 H = ImportanceSampleGGX(Xi, N, roughness);' + NL +
    '    vec3 L = normalize(2.0 * dot(V, H) * H - V);' + NL +
    '    float NdotL = max(L.z, 0.0);' + NL +
    '    float NdotH = max(H.z, 0.0);' + NL +
    '    float VdotH = max(dot(V, H), 0.0);' + NL +
    '    if (NdotL > 0.0) {' + NL +
    '      float G = GeometrySmith_IBL(NdotV, NdotL, roughness);' + NL +
    '      float G_Vis = (G * VdotH) / max(NdotH * NdotV, 1e-5);' + NL +
    '      float Fc = pow(1.0 - VdotH, 5.0);' + NL +
    '      A += (1.0 - Fc) * G_Vis;' + NL +
    '      B += Fc * G_Vis;' + NL +
    '    }' + NL +
    '  }' + NL +
    '  return vec2(A, B) / float(max(sampleCount, 1u));' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uvec2 coord = gl_GlobalInvocationID.xy;' + NL +
    '  if (coord.x >= pc.u_LutSize.x || coord.y >= pc.u_LutSize.y) return;' + NL +
    '  float NdotV = (float(coord.x) + 0.5) / float(max(pc.u_LutSize.x, 1u));' + NL +
    '  float roughness = max((float(coord.y) + 0.5) / float(max(pc.u_LutSize.y, 1u)), 0.04);' + NL +
    '  vec2 res = IntegrateBRDF(NdotV, roughness, max(pc.u_SampleCount, 16u));' + NL +
    '  imageStore(u_BrdfLutImage, ivec2(coord), vec4(res.x, res.y, 0.0, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateClusteredLightCullingComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
var
  LocalSizeX: Cardinal;
begin
  if AWorkgroupSizeX = 0 then
    LocalSizeX := 64
  else
    LocalSizeX := AWorkgroupSizeX;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [LocalSizeX]) + NL +
    NL +
    'struct CastleClusteredLightData {' + NL +
    '  vec4 PositionAndRange;' + NL +
    '  vec4 DirectionAndSpotCos;' + NL +
    '  vec4 ColorAndIntensity;' + NL +
    '  vec4 ShadowAndTypeParams;' + NL +
    '};' + NL +
    NL +
    'struct CastleClusterGridEntryData {' + NL +
    '  uint Offset;' + NL +
    '  uint Count;' + NL +
    '};' + NL +
    NL +
    'layout(std140, set = 0, binding = 0) uniform CastleClusterCullingBlock {' + NL +
    '  mat4 u_InvProjectionMatrix;' + NL +
    '  vec4 u_ScreenAndDepthParams;' + NL +
    '  uvec4 u_ClusterGridDim;' + NL +
    '  vec4 u_LogDepthParams;' + NL +
    '} u_ClusterInfo;' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) readonly buffer CastleClusteredLightsBuffer {' + NL +
    '  CastleClusteredLightData u_Lights[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 2) writeonly buffer CastleClusterGridBuffer {' + NL +
    '  CastleClusterGridEntryData u_ClusterGrid[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 3) writeonly buffer CastleClusterLightIndexBuffer {' + NL +
    '  uint u_ClusterLightIndices[];' + NL +
    '};' + NL +
    NL +
    'vec3 ScreenUVToViewAtZ(vec2 uv, float viewZ) {' + NL +
    '  vec4 ndc = vec4(uv * 2.0 - 1.0, 1.0, 1.0);' + NL +
    '  vec4 viewRay = u_ClusterInfo.u_InvProjectionMatrix * ndc;' + NL +
    '  viewRay.xyz /= max(abs(viewRay.w), 1e-5);' + NL +
    '  float rayScale = viewZ / min(viewRay.z, -1e-5);' + NL +
    '  return viewRay.xyz * rayScale;' + NL +
    '}' + NL +
    NL +
    'bool SphereIntersectsAABB(vec3 center, float radius, vec3 aabbMin, vec3 aabbMax) {' + NL +
    '  vec3 closest = clamp(center, aabbMin, aabbMax);' + NL +
    '  vec3 diff = center - closest;' + NL +
    '  return dot(diff, diff) <= (radius * radius);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint clusterIdx = gl_GlobalInvocationID.x;' + NL +
    '  uint gridX = max(u_ClusterInfo.u_ClusterGridDim.x, 1u);' + NL +
    '  uint gridY = max(u_ClusterInfo.u_ClusterGridDim.y, 1u);' + NL +
    '  uint gridZ = max(u_ClusterInfo.u_ClusterGridDim.z, 1u);' + NL +
    '  uint totalClusters = gridX * gridY * gridZ;' + NL +
    '  if (clusterIdx >= totalClusters) return;' + NL +
    NL +
    '  uint cx = clusterIdx % gridX;' + NL +
    '  uint cy = (clusterIdx / gridX) % gridY;' + NL +
    '  uint cz = clusterIdx / (gridX * gridY);' + NL +
    NL +
    '  float zNear = max(u_ClusterInfo.u_ScreenAndDepthParams.z, 1e-3);' + NL +
    '  float zFar = max(u_ClusterInfo.u_ScreenAndDepthParams.w, zNear + 1e-2);' + NL +
    '  float sliceNear = -zNear * pow(zFar / zNear, float(cz) / float(gridZ));' + NL +
    '  float sliceFar  = -zNear * pow(zFar / zNear, float(cz + 1u) / float(gridZ));' + NL +
    NL +
    '  vec2 uvMin = vec2(float(cx) / float(gridX), float(cy) / float(gridY));' + NL +
    '  vec2 uvMax = vec2(float(cx + 1u) / float(gridX), float(cy + 1u) / float(gridY));' + NL +
    '  vec3 p0 = ScreenUVToViewAtZ(uvMin, sliceNear);' + NL +
    '  vec3 p1 = ScreenUVToViewAtZ(uvMax, sliceNear);' + NL +
    '  vec3 p2 = ScreenUVToViewAtZ(uvMin, sliceFar);' + NL +
    '  vec3 p3 = ScreenUVToViewAtZ(uvMax, sliceFar);' + NL +
    '  vec3 aabbMin = min(min(p0, p1), min(p2, p3));' + NL +
    '  vec3 aabbMax = max(max(p0, p1), max(p2, p3));' + NL +
    NL +
    '  uint maxPerCluster = max(uint(u_ClusterInfo.u_LogDepthParams.z), 64u);' + NL +
    '  uint baseOffset = clusterIdx * maxPerCluster;' + NL +
    '  uint visibleCount = 0u;' + NL +
    '  uint lightCount = min(u_ClusterInfo.u_ClusterGridDim.w, 256u);' + NL +
    NL +
    '  for (uint i = 0u; i < lightCount; ++i) {' + NL +
    '    if (visibleCount >= maxPerCluster) break;' + NL +
    '    CastleClusteredLightData light = u_Lights[i];' + NL +
    '    int lightType = int(light.ShadowAndTypeParams.x + 0.5);' + NL +
    '    bool intersects = (lightType == 0) || SphereIntersectsAABB(light.PositionAndRange.xyz, light.PositionAndRange.w, aabbMin, aabbMax);' + NL +
    '    if (intersects) {' + NL +
    '      u_ClusterLightIndices[baseOffset + visibleCount] = i;' + NL +
    '      visibleCount++;' + NL +
    '    }' + NL +
    '  }' + NL +
    NL +
    '  CastleClusterGridEntryData entry;' + NL +
    '  entry.Offset = baseOffset;' + NL +
    '  entry.Count = visibleCount;' + NL +
    '  u_ClusterGrid[clusterIdx] = entry;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateBloomDownsampleComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_SrcTexture;' + NL +
    'layout(set = 0, binding = 1, rgba16f) uniform writeonly image2D u_DstImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleBloomPushConstants {' + NL +
    '  vec2  u_SrcTexelSize;' + NL +
    '  float u_Threshold;' + NL +
    '  float u_Knee;' + NL +
    '  float u_FilterRadius;' + NL +
    '  uint  u_MipLevel;' + NL +
    '  uint  u_IsFirstDownsample;' + NL +
    '  uint  u_DstPackedSize;' + NL +
    '} pc;' + NL +
    NL +
    'float LuminanceRec709(vec3 c) {' + NL +
    '  return dot(c, vec3(0.2126, 0.7152, 0.0722));' + NL +
    '}' + NL +
    NL +
    'float KarisWeight(vec3 c) {' + NL +
    '  return 1.0 / (1.0 + LuminanceRec709(c));' + NL +
    '}' + NL +
    NL +
    'vec3 ApplySoftThreshold(vec3 c, float threshold, float knee) {' + NL +
    '  float brightness = max(max(c.r, c.g), c.b);' + NL +
    '  float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);' + NL +
    '  soft = (soft * soft) / max(4.0 * knee + 1e-5, 1e-5);' + NL +
    '  float contribution = max(soft, brightness - threshold) / max(brightness, 1e-5);' + NL +
    '  return c * max(contribution, 0.0);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uvec2 dstSize = uvec2(pc.u_DstPackedSize & 0xFFFFu, pc.u_DstPackedSize >> 16u);' + NL +
    '  uvec2 coord = gl_GlobalInvocationID.xy;' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(coord) + vec2(0.5)) / vec2(max(dstSize, uvec2(1u)));' + NL +
    '  vec2 d = pc.u_SrcTexelSize;' + NL +
    NL +
    '  /* 13-tap Jiménez Dual-Filtering Downsample Kernel:' + NL +
    '     a - b - c' + NL +
    '     - j - k -' + NL +
    '     d - e - f' + NL +
    '     - l - m -' + NL +
    '     g - h - i */' + NL +
    '  vec3 a = texture(u_SrcTexture, uv + vec2(-2.0, -2.0) * d).rgb;' + NL +
    '  vec3 b = texture(u_SrcTexture, uv + vec2( 0.0, -2.0) * d).rgb;' + NL +
    '  vec3 c = texture(u_SrcTexture, uv + vec2( 2.0, -2.0) * d).rgb;' + NL +
    '  vec3 d0 = texture(u_SrcTexture, uv + vec2(-2.0,  0.0) * d).rgb;' + NL +
    '  vec3 e = texture(u_SrcTexture, uv).rgb;' + NL +
    '  vec3 f = texture(u_SrcTexture, uv + vec2( 2.0,  0.0) * d).rgb;' + NL +
    '  vec3 g = texture(u_SrcTexture, uv + vec2(-2.0,  2.0) * d).rgb;' + NL +
    '  vec3 h = texture(u_SrcTexture, uv + vec2( 0.0,  2.0) * d).rgb;' + NL +
    '  vec3 i = texture(u_SrcTexture, uv + vec2( 2.0,  2.0) * d).rgb;' + NL +
    '  vec3 j = texture(u_SrcTexture, uv + vec2(-1.0, -1.0) * d).rgb;' + NL +
    '  vec3 k = texture(u_SrcTexture, uv + vec2( 1.0, -1.0) * d).rgb;' + NL +
    '  vec3 l = texture(u_SrcTexture, uv + vec2(-1.0,  1.0) * d).rgb;' + NL +
    '  vec3 m = texture(u_SrcTexture, uv + vec2( 1.0,  1.0) * d).rgb;' + NL +
    NL +
    '  vec3 downsample;' + NL +
    '  if (pc.u_IsFirstDownsample != 0u) {' + NL +
    '    vec3 g0 = (a + b + d0 + e) * 0.25;' + NL +
    '    vec3 g1 = (b + c + e + f) * 0.25;' + NL +
    '    vec3 g2 = (d0 + e + g + h) * 0.25;' + NL +
    '    vec3 g3 = (e + f + h + i) * 0.25;' + NL +
    '    vec3 g4 = (j + k + l + m) * 0.25;' + NL +
    '    float w0 = KarisWeight(g0);' + NL +
    '    float w1 = KarisWeight(g1);' + NL +
    '    float w2 = KarisWeight(g2);' + NL +
    '    float w3 = KarisWeight(g3);' + NL +
    '    float w4 = KarisWeight(g4);' + NL +
    '    downsample = (g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3) * 0.125 / max(0.25 * (w0 + w1 + w2 + w3), 1e-5)' + NL +
    '               + (g4 * 0.5);' + NL +
    '    downsample = ApplySoftThreshold(downsample, pc.u_Threshold, pc.u_Knee);' + NL +
    '  } else {' + NL +
    '    downsample  = e * 0.125;' + NL +
    '    downsample += (a + c + g + i) * 0.03125;' + NL +
    '    downsample += (b + d0 + f + h) * 0.0625;' + NL +
    '    downsample += (j + k + l + m) * 0.125;' + NL +
    '  }' + NL +
    NL +
    '  imageStore(u_DstImage, ivec2(coord), vec4(max(downsample, vec3(0.0)), 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateBloomUpsampleComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_SrcLowMipTexture;' + NL +
    'layout(set = 0, binding = 1, rgba16f) uniform image2D u_DstHighMipImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleBloomPushConstants {' + NL +
    '  vec2  u_SrcTexelSize;' + NL +
    '  float u_Threshold;' + NL +
    '  float u_Knee;' + NL +
    '  float u_FilterRadius;' + NL +
    '  uint  u_MipLevel;' + NL +
    '  uint  u_IsFirstDownsample;' + NL +
    '  uint  u_DstPackedSize;' + NL +
    '} pc;' + NL +
    NL +
    'void main() {' + NL +
    '  uvec2 dstSize = uvec2(pc.u_DstPackedSize & 0xFFFFu, pc.u_DstPackedSize >> 16u);' + NL +
    '  uvec2 coord = gl_GlobalInvocationID.xy;' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(coord) + vec2(0.5)) / vec2(max(dstSize, uvec2(1u)));' + NL +
    '  vec2 d = pc.u_SrcTexelSize * max(pc.u_FilterRadius, 1e-4);' + NL +
    NL +
    '  /* 9-tap 3x3 Tent Filter Upsample Kernel ([1, 2, 1; 2, 4, 2; 1, 2, 1] / 16) */' + NL +
    '  vec3 a = texture(u_SrcLowMipTexture, uv + vec2(-d.x, -d.y)).rgb;' + NL +
    '  vec3 b = texture(u_SrcLowMipTexture, uv + vec2( 0.0, -d.y)).rgb;' + NL +
    '  vec3 c = texture(u_SrcLowMipTexture, uv + vec2( d.x, -d.y)).rgb;' + NL +
    '  vec3 d0 = texture(u_SrcLowMipTexture, uv + vec2(-d.x,  0.0)).rgb;' + NL +
    '  vec3 e = texture(u_SrcLowMipTexture, uv).rgb;' + NL +
    '  vec3 f = texture(u_SrcLowMipTexture, uv + vec2( d.x,  0.0)).rgb;' + NL +
    '  vec3 g = texture(u_SrcLowMipTexture, uv + vec2(-d.x,  d.y)).rgb;' + NL +
    '  vec3 h = texture(u_SrcLowMipTexture, uv + vec2( 0.0,  d.y)).rgb;' + NL +
    '  vec3 i = texture(u_SrcLowMipTexture, uv + vec2( d.x,  d.y)).rgb;' + NL +
    NL +
    '  vec3 upsample = (e * 4.0 + (b + d0 + f + h) * 2.0 + (a + c + g + i)) * (1.0 / 16.0);' + NL +
    '  vec3 prevMip = imageLoad(u_DstHighMipImage, ivec2(coord)).rgb;' + NL +
    '  imageStore(u_DstHighMipImage, ivec2(coord), vec4(prevMip + upsample, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateLuminanceHistogramComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 16 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 16 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_HDRSceneTexture;' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) buffer CastleLuminanceHistogramBuffer {' + NL +
    '  uint u_HistogramBins[256];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 2) buffer CastleAutoExposureStateBuffer {' + NL +
    '  float u_AdaptedLuminance;' + NL +
    '  float u_AdaptedExposure;' + NL +
    '  float u_TargetLuminance;' + NL +
    '  float u_Reserved;' + NL +
    '};' + NL +
    NL +
    'layout(push_constant) uniform CastleAutoExposurePushConstants {' + NL +
    '  float u_MinLogLum;' + NL +
    '  float u_MaxLogLum;' + NL +
    '  float u_TimeDelta;' + NL +
    '  float u_AdaptationSpeed;' + NL +
    '  float u_TargetMiddleGrey;' + NL +
    '  float u_MinExposure;' + NL +
    '  float u_MaxExposure;' + NL +
    '  uint  u_TotalPixels;' + NL +
    '} pc;' + NL +
    NL +
    'shared uint s_LocalHistogram[256];' + NL +
    NL +
    'uint ColorToHistogramBin(vec3 hdrColor) {' + NL +
    '  float lum = dot(hdrColor, vec3(0.2126, 0.7152, 0.0722));' + NL +
    '  if (lum < 1e-4) return 0u;' + NL +
    '  float logLum = clamp((log2(lum) - pc.u_MinLogLum) / max(pc.u_MaxLogLum - pc.u_MinLogLum, 1e-4), 0.0, 1.0);' + NL +
    '  return uint(logLum * 254.0 + 1.0);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint localIdx = gl_LocalInvocationIndex;' + NL +
    '  if (localIdx < 256u) s_LocalHistogram[localIdx] = 0u;' + NL +
    '  barrier();' + NL +
    NL +
    '  ivec2 texSize = textureSize(u_HDRSceneTexture, 0);' + NL +
    '  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (coord.x < texSize.x && coord.y < texSize.y) {' + NL +
    '    vec3 hdrColor = texelFetch(u_HDRSceneTexture, coord, 0).rgb;' + NL +
    '    uint bin = ColorToHistogramBin(hdrColor);' + NL +
    '    atomicAdd(s_LocalHistogram[bin], 1u);' + NL +
    '  }' + NL +
    '  barrier();' + NL +
    NL +
    '  if (localIdx < 256u && s_LocalHistogram[localIdx] > 0u) {' + NL +
    '    atomicAdd(u_HistogramBins[localIdx], s_LocalHistogram[localIdx]);' + NL +
    '  }' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateTonemappingAndColorGradingFunctions: String;
begin
  Result :=
    '/* Phase 15.3: HDR Tonemapping (Reinhard, ACES Filmic, AgX) & Color Grading */' + NL +
    'vec3 TonemapReinhard(vec3 hdr) {' + NL +
    '  return hdr / (hdr + vec3(1.0));' + NL +
    '}' + NL +
    NL +
    'vec3 TonemapACESFilmic(vec3 x) {' + NL +
    '  const float a = 2.51;' + NL +
    '  const float b = 0.03;' + NL +
    '  const float c = 2.43;' + NL +
    '  const float d = 0.59;' + NL +
    '  const float e = 0.14;' + NL +
    '  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'vec3 AgXDefaultContrastApprox(vec3 x) {' + NL +
    '  vec3 x2 = x * x;' + NL +
    '  vec3 x4 = x2 * x2;' + NL +
    '  return + 15.5     * x4 * x2' + NL +
    '         - 40.14    * x4 * x' + NL +
    '         + 31.96    * x4' + NL +
    '         - 6.868    * x2 * x' + NL +
    '         + 0.4298   * x2' + NL +
    '         + 0.1191   * x' + NL +
    '         - 0.00232;' + NL +
    '}' + NL +
    NL +
    'vec3 TonemapAgX(vec3 hdr) {' + NL +
    '  const mat3 agxInsetMatrix = mat3(' + NL +
    '    0.842479062253094,  0.0423282422610123, 0.0423756549057051,' + NL +
    '    0.0784335999999992, 0.878468636469772,  0.0784336,' + NL +
    '    0.0792237451477643, 0.0791661274605434, 0.879142973793104);' + NL +
    '  const mat3 agxOutsetMatrix = mat3(' + NL +
    '     1.19687900512017,   -0.0528968517574562, -0.0529716355144438,' + NL +
    '    -0.0980208811401368,  1.15190312990417,   -0.0980434501171241,' + NL +
    '    -0.0990297440797205, -0.0989611768448433,  1.15107367264116);' + NL +
    '  const float minEv = -12.47393;' + NL +
    '  const float maxEv = 4.026069;' + NL +
    '  vec3 val = agxInsetMatrix * max(hdr, vec3(1e-6));' + NL +
    '  val = clamp(log2(val), minEv, maxEv);' + NL +
    '  val = (val - minEv) / (maxEv - minEv);' + NL +
    '  val = AgXDefaultContrastApprox(val);' + NL +
    '  val = agxOutsetMatrix * val;' + NL +
    '  return clamp(pow(max(val, vec3(0.0)), vec3(2.2)), 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'vec3 ApplyColorGrading(vec3 color, float saturation, float contrast) {' + NL +
    '  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));' + NL +
    '  vec3 satColor = mix(vec3(luma), color, saturation);' + NL +
    '  return max((satColor - vec3(0.18)) * contrast + vec3(0.18), vec3(0.0));' + NL +
    '}' + NL +
    NL +
    'vec3 LinearToSRGB(vec3 linearColor) {' + NL +
    '  vec3 c = max(linearColor, vec3(0.0));' + NL +
    '  vec3 lo = c * 12.92;' + NL +
    '  vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;' + NL +
    '  return mix(lo, hi, step(vec3(0.0031308), c));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateHDRCompositeFragmentShader: String;
begin
  Result :=
    '#version 450' + NL +
    'layout(location = 0) in vec2 v_TexCoord;' + NL +
    'layout(location = 0) out vec4 out_FragColor;' + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_HDRSceneTexture;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_BloomTexture;' + NL +
    'layout(std430, set = 0, binding = 2) readonly buffer CastleAutoExposureStateBuffer {' + NL +
    '  float u_AdaptedLuminance;' + NL +
    '  float u_AdaptedExposure;' + NL +
    '  float u_TargetLuminance;' + NL +
    '  float u_Reserved;' + NL +
    '};' + NL +
    NL +
    'layout(push_constant) uniform CastleHDRCompositePushConstants {' + NL +
    '  float u_Exposure;' + NL +
    '  float u_BloomIntensity;' + NL +
    '  float u_Gamma;' + NL +
    '  float u_Saturation;' + NL +
    '  float u_Contrast;' + NL +
    '  uint  u_TonemapOperator;' + NL +
    '  uint  u_EnableBloom;' + NL +
    '  uint  u_EnableAutoExposure;' + NL +
    '} pc;' + NL +
    NL +
    GenerateTonemappingAndColorGradingFunctions + NL +
    'void main() {' + NL +
    '  vec3 hdrColor = texture(u_HDRSceneTexture, v_TexCoord).rgb;' + NL +
    '  if (pc.u_EnableBloom != 0u) {' + NL +
    '    vec3 bloomColor = texture(u_BloomTexture, v_TexCoord).rgb;' + NL +
    '    hdrColor += bloomColor * pc.u_BloomIntensity;' + NL +
    '  }' + NL +
    NL +
    '  float exposure = pc.u_Exposure;' + NL +
    '  if (pc.u_EnableAutoExposure != 0u) {' + NL +
    '    exposure *= max(u_AdaptedExposure, 1e-4);' + NL +
    '  }' + NL +
    '  vec3 exposed = ApplyColorGrading(hdrColor * exposure, pc.u_Saturation, pc.u_Contrast);' + NL +
    NL +
    '  vec3 mapped;' + NL +
    '  if (pc.u_TonemapOperator == 1u) mapped = TonemapReinhard(exposed);' + NL +
    '  else if (pc.u_TonemapOperator == 2u) mapped = TonemapACESFilmic(exposed);' + NL +
    '  else if (pc.u_TonemapOperator == 3u) mapped = TonemapAgX(exposed);' + NL +
    '  else mapped = clamp(exposed, 0.0, 1.0);' + NL +
    NL +
    '  vec3 srgb = (abs(pc.u_Gamma - 2.2) < 1e-3) ? LinearToSRGB(mapped) : pow(max(mapped, vec3(0.0)), vec3(1.0 / max(pc.u_Gamma, 1e-3)));' + NL +
    '  out_FragColor = vec4(srgb, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateGTAOComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_DepthTexture;' + NL +
    'layout(set = 0, binding = 1, r16f) uniform writeonly image2D u_RawGTAOImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleGTAOPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  vec2  u_ProjScale;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '  float u_EffectRadius;' + NL +
    '  float u_FalloffRange;' + NL +
    '  float u_Power;' + NL +
    '  uint  u_SliceCount;' + NL +
    '  uint  u_StepsPerSlice;' + NL +
    '  uint  u_DenoisePass;' + NL +
    '} pc;' + NL +
    NL +
    'const float PI = 3.14159265359;' + NL +
    'const float HALF_PI = 1.57079632679;' + NL +
    NL +
    'float LinearizeDepth(float ndcDepth) {' + NL +
    '  float zNear = max(pc.u_ZNear, 1e-3);' + NL +
    '  float zFar = max(pc.u_ZFar, zNear + 1.0);' + NL +
    '  return (zNear * zFar) / max(zFar - ndcDepth * (zFar - zNear), 1e-5);' + NL +
    '}' + NL +
    NL +
    'vec3 ReconstructViewPosition(vec2 uv, float linearZ) {' + NL +
    '  vec2 ndc = uv * 2.0 - 1.0;' + NL +
    '  return vec3(ndc * pc.u_ProjScale * linearZ, -linearZ);' + NL +
    '}' + NL +
    NL +
    'vec3 ReconstructViewNormalFromDepth(vec2 uv, vec3 centerPos) {' + NL +
    '  vec2 dx = vec2(pc.u_InvResolution.x, 0.0);' + NL +
    '  vec2 dy = vec2(0.0, pc.u_InvResolution.y);' + NL +
    '  vec3 pRight = ReconstructViewPosition(uv + dx, LinearizeDepth(textureLod(u_DepthTexture, uv + dx, 0.0).r)) - centerPos;' + NL +
    '  vec3 pLeft  = centerPos - ReconstructViewPosition(uv - dx, LinearizeDepth(textureLod(u_DepthTexture, uv - dx, 0.0).r));' + NL +
    '  vec3 pUp    = ReconstructViewPosition(uv + dy, LinearizeDepth(textureLod(u_DepthTexture, uv + dy, 0.0).r)) - centerPos;' + NL +
    '  vec3 pDown  = centerPos - ReconstructViewPosition(uv - dy, LinearizeDepth(textureLod(u_DepthTexture, uv - dy, 0.0).r));' + NL +
    '  vec3 dX = (abs(pRight.z) < abs(pLeft.z)) ? pRight : pLeft;' + NL +
    '  vec3 dY = (abs(pUp.z) < abs(pDown.z)) ? pUp : pDown;' + NL +
    '  return normalize(cross(dX, dY));' + NL +
    '}' + NL +
    NL +
    'float InterleavedGradientNoise(vec2 pixelCoord) {' + NL +
    '  return fract(52.9829189 * fract(dot(pixelCoord, vec2(0.06711056, 0.00583715))));' + NL +
    '}' + NL +
    NL +
    'float IntegrateGTAOHorizonSlice(float h1, float h2, float nAngle) {' + NL +
    '  float sinN = sin(nAngle);' + NL +
    '  float cosN = cos(nAngle);' + NL +
    '  float i1 = (-cos(2.0 * h1 - nAngle) + cosN + 2.0 * h1 * sinN) * 0.25;' + NL +
    '  float i2 = (-cos(2.0 * h2 - nAngle) + cosN + 2.0 * h2 * sinN) * 0.25;' + NL +
    '  return clamp(i1 + i2, 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 dstSize = imageSize(u_RawGTAOImage);' + NL +
    '  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(coord) + 0.5) * pc.u_InvResolution;' + NL +
    '  float rawDepth = textureLod(u_DepthTexture, uv, 0.0).r;' + NL +
    '  if (rawDepth >= 0.9999) {' + NL +
    '    imageStore(u_RawGTAOImage, coord, vec4(1.0, 0.0, 0.0, 1.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  float linearZ = LinearizeDepth(rawDepth);' + NL +
    '  vec3 viewPos = ReconstructViewPosition(uv, linearZ);' + NL +
    '  vec3 viewNormal = ReconstructViewNormalFromDepth(uv, viewPos);' + NL +
    '  vec3 viewDir = normalize(-viewPos);' + NL +
    NL +
    '  uint sliceCount = max(pc.u_SliceCount, 1u);' + NL +
    '  uint stepsPerSlice = max(pc.u_StepsPerSlice, 1u);' + NL +
    '  float noiseAngle = InterleavedGradientNoise(vec2(coord)) * PI;' + NL +
    '  float visibilitySum = 0.0;' + NL +
    NL +
    '  for (uint s = 0u; s < sliceCount; ++s) {' + NL +
    '    float phi = (float(s) / float(sliceCount)) * PI + noiseAngle;' + NL +
    '    vec2 omega = vec2(cos(phi), sin(phi));' + NL +
    '    vec2 maxCos = vec2(-1.0);' + NL +
    '    for (uint stepIdx = 1u; stepIdx <= stepsPerSlice; ++stepIdx) {' + NL +
    '      float stepFrac = float(stepIdx) / float(stepsPerSlice);' + NL +
    '      vec2 uvOffset = omega * stepFrac * (pc.u_EffectRadius / max(linearZ, 0.5)) * pc.u_InvResolution * 16.0;' + NL +
    '      vec3 sPos1 = ReconstructViewPosition(uv + uvOffset, LinearizeDepth(textureLod(u_DepthTexture, uv + uvOffset, 0.0).r)) - viewPos;' + NL +
    '      vec3 sPos2 = ReconstructViewPosition(uv - uvOffset, LinearizeDepth(textureLod(u_DepthTexture, uv - uvOffset, 0.0).r)) - viewPos;' + NL +
    '      float dist1 = length(sPos1);' + NL +
    '      float dist2 = length(sPos2);' + NL +
    '      float falloff1 = clamp(1.0 - dist1 / max(pc.u_EffectRadius * (1.0 + pc.u_FalloffRange), 1e-4), 0.0, 1.0);' + NL +
    '      float falloff2 = clamp(1.0 - dist2 / max(pc.u_EffectRadius * (1.0 + pc.u_FalloffRange), 1e-4), 0.0, 1.0);' + NL +
    '      maxCos.x = max(maxCos.x, mix(-1.0, dot(sPos1 / max(dist1, 1e-5), viewDir), falloff1));' + NL +
    '      maxCos.y = max(maxCos.y, mix(-1.0, dot(sPos2 / max(dist2, 1e-5), viewDir), falloff2));' + NL +
    '    }' + NL +
    '    float h1 = -acos(clamp(maxCos.x, -1.0, 1.0));' + NL +
    '    float h2 =  acos(clamp(maxCos.y, -1.0, 1.0));' + NL +
    '    float nAngle = acos(clamp(dot(viewNormal, viewDir), -1.0, 1.0)) - HALF_PI;' + NL +
    '    visibilitySum += IntegrateGTAOHorizonSlice(h1, h2, nAngle);' + NL +
    '  }' + NL +
    NL +
    '  float ao = pow(clamp(visibilitySum / float(sliceCount), 0.0, 1.0), max(pc.u_Power, 0.01));' + NL +
    '  imageStore(u_RawGTAOImage, coord, vec4(ao, 0.0, 0.0, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateGTAODenoiseComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_DepthTexture;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_RawGTAOTexture;' + NL +
    'layout(set = 0, binding = 2, r16f) uniform writeonly image2D u_DenoisedGTAOImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleGTAOPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  vec2  u_ProjScale;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '  float u_EffectRadius;' + NL +
    '  float u_FalloffRange;' + NL +
    '  float u_Power;' + NL +
    '  uint  u_SliceCount;' + NL +
    '  uint  u_StepsPerSlice;' + NL +
    '  uint  u_DenoisePass;' + NL +
    '} pc;' + NL +
    NL +
    'float ComputeBilateralDepthWeight(float centerDepth, float sampleDepth, float sigmaDepth) {' + NL +
    '  float diff = abs(centerDepth - sampleDepth) / max(sigmaDepth, 1e-5);' + NL +
    '  return exp(-diff * diff);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 dstSize = imageSize(u_DenoisedGTAOImage);' + NL +
    '  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 centerUV = (vec2(coord) + 0.5) * pc.u_InvResolution;' + NL +
    '  float centerDepth = textureLod(u_DepthTexture, centerUV, 0.0).r;' + NL +
    '  float aoSum = 0.0;' + NL +
    '  float weightSum = 0.0;' + NL +
    NL +
    '  for (int dy = -2; dy <= 2; ++dy) {' + NL +
    '    for (int dx = -2; dx <= 2; ++dx) {' + NL +
    '      vec2 sampleUV = centerUV + vec2(float(dx), float(dy)) * pc.u_InvResolution;' + NL +
    '      float sampleDepth = textureLod(u_DepthTexture, sampleUV, 0.0).r;' + NL +
    '      float sampleAO = textureLod(u_RawGTAOTexture, sampleUV, 0.0).r;' + NL +
    '      float spatialWeight = exp(-float(dx * dx + dy * dy) / 4.5);' + NL +
    '      float depthWeight = ComputeBilateralDepthWeight(centerDepth, sampleDepth, 0.015);' + NL +
    '      float w = spatialWeight * depthWeight;' + NL +
    '      aoSum += sampleAO * w;' + NL +
    '      weightSum += w;' + NL +
    '    }' + NL +
    '  }' + NL +
    NL +
    '  float denoisedAO = aoSum / max(weightSum, 1e-5);' + NL +
    '  imageStore(u_DenoisedGTAOImage, coord, vec4(denoisedAO, 0.0, 0.0, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateHiZSSRComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_HDRSceneColor;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_HiZPyramidTexture;' + NL +
    'layout(set = 0, binding = 2, rgba16f) uniform writeonly image2D u_SSRReflectionImage;' + NL +
    NL +
    'layout(push_constant) uniform CastleSSRPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '  float u_MaxDistance;' + NL +
    '  float u_Thickness;' + NL +
    '  float u_MaxRoughness;' + NL +
    '  float u_EdgeFadeWidth;' + NL +
    '  uint  u_MaxSteps;' + NL +
    '  uint  u_HiZMipCount;' + NL +
    '  float u_Intensity;' + NL +
    '  uint  u_Reserved;' + NL +
    '} pc;' + NL +
    NL +
    'float EvaluateScreenEdgeFade(vec2 hitUV, float fadeWidth) {' + NL +
    '  vec2 border = smoothstep(vec2(0.0), vec2(max(fadeWidth, 1e-4)), hitUV) *' + NL +
    '                smoothstep(vec2(0.0), vec2(max(fadeWidth, 1e-4)), vec2(1.0) - hitUV);' + NL +
    '  return clamp(border.x * border.y, 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'float EvaluateSSRReflectionWeight(float roughness, float maxRoughness, float cosTheta) {' + NL +
    '  if (roughness >= maxRoughness) return 0.0;' + NL +
    '  float roughWeight = 1.0 - smoothstep(0.0, max(maxRoughness, 1e-4), roughness);' + NL +
    '  float fresnel = mix(0.04, max(1.0 - roughness, 0.04), pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0));' + NL +
    '  return clamp(roughWeight * fresnel, 0.0, 1.0);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 dstSize = imageSize(u_SSRReflectionImage);' + NL +
    '  ivec2 coord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (coord.x >= dstSize.x || coord.y >= dstSize.y) return;' + NL +
    NL +
    '  vec2 startUV = (vec2(coord) + 0.5) * pc.u_InvResolution;' + NL +
    '  float startDepth = textureLod(u_HiZPyramidTexture, startUV, 0.0).r;' + NL +
    '  if (startDepth >= 0.9999) {' + NL +
    '    imageStore(u_SSRReflectionImage, coord, vec4(0.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  vec2 rayDirUV = normalize(startUV - vec2(0.5, 0.5) + vec2(1e-4)) * pc.u_InvResolution * 2.0;' + NL +
    '  float rayStepZ = -0.002;' + NL +
    '  vec2 curUV = startUV;' + NL +
    '  float curZ = startDepth;' + NL +
    '  int mipLevel = 0;' + NL +
    '  int maxMip = int(max(pc.u_HiZMipCount, 1u)) - 1;' + NL +
    '  bool hit = false;' + NL +
    NL +
    '  for (uint stepIdx = 0u; stepIdx < pc.u_MaxSteps; ++stepIdx) {' + NL +
    '    float stepScale = float(1 << mipLevel);' + NL +
    '    curUV += rayDirUV * stepScale;' + NL +
    '    curZ  += rayStepZ * stepScale;' + NL +
    '    if (curUV.x < 0.0 || curUV.x > 1.0 || curUV.y < 0.0 || curUV.y > 1.0) break;' + NL +
    '    float hiZMinDepth = textureLod(u_HiZPyramidTexture, curUV, float(mipLevel)).r;' + NL +
    '    if (curZ >= hiZMinDepth) {' + NL +
    '      if (mipLevel == 0) {' + NL +
    '        if (curZ - hiZMinDepth <= pc.u_Thickness) { hit = true; break; }' + NL +
    '      } else {' + NL +
    '        mipLevel = max(0, mipLevel - 1);' + NL +
    '      }' + NL +
    '    } else {' + NL +
    '      mipLevel = min(maxMip, mipLevel + 1);' + NL +
    '    }' + NL +
    '  }' + NL +
    NL +
    '  if (!hit) {' + NL +
    '    imageStore(u_SSRReflectionImage, coord, vec4(0.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  float edgeFade = EvaluateScreenEdgeFade(curUV, pc.u_EdgeFadeWidth);' + NL +
    '  float reflWeight = EvaluateSSRReflectionWeight(0.15, pc.u_MaxRoughness, 0.5) * edgeFade * pc.u_Intensity;' + NL +
    '  vec3 hitColor = textureLod(u_HDRSceneColor, curUV, 0.0).rgb;' + NL +
    '  imageStore(u_SSRReflectionImage, coord, vec4(hitColor * reflWeight, reflWeight));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateVolumetricFogInjectComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY, AWorkgroupSizeZ: Cardinal): String;
var
  LocalX, LocalY, LocalZ: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 4 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 4 else LocalY := AWorkgroupSizeY;
  if AWorkgroupSizeZ = 0 then LocalZ := 4 else LocalZ := AWorkgroupSizeZ;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = %d) in;', [LocalX, LocalY, LocalZ]) + NL +
    NL +
    'layout(set = 0, binding = 0, rgba16f) uniform writeonly image3D u_FroxelScatteringVolume;' + NL +
    NL +
    'layout(push_constant) uniform CastleVolumetricFogParams {' + NL +
    '  vec4  u_FogAlbedoAndBaseDensity;' + NL +
    '  vec4  u_SunDirectionAndAnisotropy;' + NL +
    '  vec4  u_SunColorAndIntensity;' + NL +
    '  float u_HeightFalloff;' + NL +
    '  float u_BaseHeight;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '} pc;' + NL +
    NL +
    'const float FOUR_PI = 12.56637061436;' + NL +
    NL +
    'float EvaluateHenyeyGreensteinPhase(float cosTheta, float g) {' + NL +
    '  float g2 = g * g;' + NL +
    '  float denom = max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4);' + NL +
    '  return (1.0 - g2) / (FOUR_PI * denom * sqrt(denom));' + NL +
    '}' + NL +
    NL +
    'float EvaluateHeightFogDensity(float worldY, float baseDensity, float baseHeight, float heightFalloff) {' + NL +
    '  float dh = max(worldY - baseHeight, -50.0);' + NL +
    '  return max(0.0, baseDensity * exp(-heightFalloff * dh));' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec3 gridSize = imageSize(u_FroxelScatteringVolume);' + NL +
    '  ivec3 froxelCoord = ivec3(gl_GlobalInvocationID.xyz);' + NL +
    '  if (froxelCoord.x >= gridSize.x || froxelCoord.y >= gridSize.y || froxelCoord.z >= gridSize.z) return;' + NL +
    NL +
    '  vec3 uvw = (vec3(froxelCoord) + 0.5) / vec3(gridSize);' + NL +
    '  float zNear = max(pc.u_ZNear, 0.05);' + NL +
    '  float zFar  = max(pc.u_ZFar, zNear + 1.0);' + NL +
    '  float sliceDepth = zNear * pow(zFar / zNear, uvw.z);' + NL +
    '  float worldY = (uvw.y - 0.5) * sliceDepth;' + NL +
    NL +
    '  float extinction = EvaluateHeightFogDensity(worldY, pc.u_FogAlbedoAndBaseDensity.w, pc.u_BaseHeight, pc.u_HeightFalloff);' + NL +
    '  vec3 viewRayDir = normalize(vec3((uvw.xy * 2.0 - 1.0), -1.0));' + NL +
    '  float cosTheta = dot(viewRayDir, normalize(pc.u_SunDirectionAndAnisotropy.xyz));' + NL +
    '  float phase = EvaluateHenyeyGreensteinPhase(cosTheta, clamp(pc.u_SunDirectionAndAnisotropy.w, -0.99, 0.99));' + NL +
    NL +
    '  vec3 scatteringAlbedo = pc.u_FogAlbedoAndBaseDensity.rgb;' + NL +
    '  vec3 sunLight = pc.u_SunColorAndIntensity.rgb * pc.u_SunColorAndIntensity.w;' + NL +
    '  vec3 inScattered = scatteringAlbedo * extinction * (vec3(0.15) + sunLight * phase);' + NL +
    '  imageStore(u_FroxelScatteringVolume, froxelCoord, vec4(inScattered, extinction));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateVolumetricFogRaymarchComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler3D u_FroxelScatteringVolume;' + NL +
    'layout(set = 0, binding = 1, rgba16f) uniform writeonly image3D u_IntegratedFroxelLUT;' + NL +
    NL +
    'layout(push_constant) uniform CastleVolumetricFogParams {' + NL +
    '  vec4  u_FogAlbedoAndBaseDensity;' + NL +
    '  vec4  u_SunDirectionAndAnisotropy;' + NL +
    '  vec4  u_SunColorAndIntensity;' + NL +
    '  float u_HeightFalloff;' + NL +
    '  float u_BaseHeight;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '} pc;' + NL +
    NL +
    'void IntegrateFroxelSliceStep(vec3 sliceScattering, float sliceExtinction, float stepLength,' + NL +
    '  inout vec3 accumLight, inout float accumTransmittance) {' + NL +
    '  float stepTransmittance = exp(-max(sliceExtinction, 0.0) * max(stepLength, 0.0));' + NL +
    '  vec3 sliceIntegral = sliceScattering * (1.0 - stepTransmittance) / max(sliceExtinction, 1e-5);' + NL +
    '  accumLight += accumTransmittance * sliceIntegral;' + NL +
    '  accumTransmittance *= stepTransmittance;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec3 gridSize = imageSize(u_IntegratedFroxelLUT);' + NL +
    '  ivec2 xy = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  if (xy.x >= gridSize.x || xy.y >= gridSize.y) return;' + NL +
    NL +
    '  float zNear = max(pc.u_ZNear, 0.05);' + NL +
    '  float zFar  = max(pc.u_ZFar, zNear + 1.0);' + NL +
    '  vec3 accumLight = vec3(0.0);' + NL +
    '  float accumTransmittance = 1.0;' + NL +
    '  float prevDepth = zNear;' + NL +
    NL +
    '  for (int z = 0; z < gridSize.z; ++z) {' + NL +
    '    float nextDepth = zNear * pow(zFar / zNear, float(z + 1) / float(gridSize.z));' + NL +
    '    float stepLength = max(nextDepth - prevDepth, 1e-3);' + NL +
    '    prevDepth = nextDepth;' + NL +
    '    vec4 sampleVal = texelFetch(u_FroxelScatteringVolume, ivec3(xy, z), 0);' + NL +
    '    IntegrateFroxelSliceStep(sampleVal.rgb, sampleVal.a, stepLength, accumLight, accumTransmittance);' + NL +
    '    imageStore(u_IntegratedFroxelLUT, ivec3(xy, z), vec4(accumLight, accumTransmittance));' + NL +
    '  }' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateTAAResolveComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_CurrentHDRTexture;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_HistoryHDRTexture;' + NL +
    'layout(set = 0, binding = 2) uniform sampler2D u_VelocityTexture;' + NL +
    'layout(set = 0, binding = 3, rgba16f) uniform writeonly image2D u_ResolvedHDRTexture;' + NL +
    NL +
    'layout(push_constant) uniform CastleTAAPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  vec2  u_JitterOffset;' + NL +
    '  float u_BlendFactor;' + NL +
    '  float u_VarianceClipGamma;' + NL +
    '  float u_VelocityWeightScale;' + NL +
    '  uint  u_FrameIndex;' + NL +
    '} pc;' + NL +
    NL +
    'vec3 RGBToYCoCg(vec3 rgb) {' + NL +
    '  float Y  = dot(rgb, vec3(0.25, 0.50, 0.25));' + NL +
    '  float Co = dot(rgb, vec3(0.50, 0.00, -0.50));' + NL +
    '  float Cg = dot(rgb, vec3(-0.25, 0.50, -0.25));' + NL +
    '  return vec3(Y, Co, Cg);' + NL +
    '}' + NL +
    NL +
    'vec3 YCoCgToRGB(vec3 ycocg) {' + NL +
    '  float tmp = ycocg.x - ycocg.z;' + NL +
    '  float r   = tmp + ycocg.y;' + NL +
    '  float g   = ycocg.x + ycocg.z;' + NL +
    '  float b   = tmp - ycocg.y;' + NL +
    '  return max(vec3(r, g, b), vec3(0.0));' + NL +
    '}' + NL +
    NL +
    'vec3 ClipHistoryYCoCg(vec3 historyYCoCg, vec3 meanYCoCg, vec3 stdDevYCoCg, float gamma) {' + NL +
    '  vec3 boxMin = meanYCoCg - stdDevYCoCg * max(gamma, 0.1);' + NL +
    '  vec3 boxMax = meanYCoCg + stdDevYCoCg * max(gamma, 0.1);' + NL +
    '  return clamp(historyYCoCg, boxMin, boxMax);' + NL +
    '}' + NL +
    NL +
    'vec3 SampleHistoryCatmullRom5Tap(sampler2D tex, vec2 uv, vec2 invRes) {' + NL +
    '  vec2 samplePos = uv / max(invRes, vec2(1e-6));' + NL +
    '  vec2 texPos1 = floor(samplePos - 0.5) + 0.5;' + NL +
    '  vec2 f = samplePos - texPos1;' + NL +
    '  vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));' + NL +
    '  vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);' + NL +
    '  vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));' + NL +
    '  vec2 w3 = f * f * (-0.5 + 0.5 * f);' + NL +
    '  vec2 w12 = w1 + w2;' + NL +
    '  vec2 offset12 = w2 / max(w12, vec2(1e-5));' + NL +
    '  vec2 texPos0 = (texPos1 - 1.0) * invRes;' + NL +
    '  vec2 texPos3 = (texPos1 + 2.0) * invRes;' + NL +
    '  vec2 texPos12 = (texPos1 + offset12) * invRes;' + NL +
    '  vec3 result = vec3(0.0);' + NL +
    '  result += textureLod(tex, vec2(texPos12.x, texPos0.y), 0.0).rgb * (w12.x * w0.y);' + NL +
    '  result += textureLod(tex, vec2(texPos0.x,  texPos12.y), 0.0).rgb * (w0.x  * w12.y);' + NL +
    '  result += textureLod(tex, vec2(texPos12.x, texPos12.y), 0.0).rgb * (w12.x * w12.y);' + NL +
    '  result += textureLod(tex, vec2(texPos3.x,  texPos12.y), 0.0).rgb * (w3.x  * w12.y);' + NL +
    '  result += textureLod(tex, vec2(texPos12.x, texPos3.y), 0.0).rgb * (w12.x * w3.y);' + NL +
    '  float totalWeight = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;' + NL +
    '  return max(result / max(totalWeight, 1e-5), vec3(0.0));' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 pixelCoord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  ivec2 outSize = imageSize(u_ResolvedHDRTexture);' + NL +
    '  if (pixelCoord.x >= outSize.x || pixelCoord.y >= outSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(pixelCoord) + 0.5) * pc.u_InvResolution;' + NL +
    '  vec2 velocity = textureLod(u_VelocityTexture, uv, 0.0).rg;' + NL +
    '  vec2 historyUV = uv - velocity;' + NL +
    NL +
    '  vec3 m1 = vec3(0.0);' + NL +
    '  vec3 m2 = vec3(0.0);' + NL +
    '  vec3 centerYCoCg = vec3(0.0);' + NL +
    '  for (int dy = -1; dy <= 1; ++dy) {' + NL +
    '    for (int dx = -1; dx <= 1; ++dx) {' + NL +
    '      vec2 sampleUV = clamp(uv + vec2(float(dx), float(dy)) * pc.u_InvResolution, vec2(0.0), vec2(1.0));' + NL +
    '      vec3 sampleYCoCg = RGBToYCoCg(textureLod(u_CurrentHDRTexture, sampleUV, 0.0).rgb);' + NL +
    '      if (dx == 0 && dy == 0) centerYCoCg = sampleYCoCg;' + NL +
    '      m1 += sampleYCoCg;' + NL +
    '      m2 += sampleYCoCg * sampleYCoCg;' + NL +
    '    }' + NL +
    '  }' + NL +
    '  vec3 meanYCoCg = m1 / 9.0;' + NL +
    '  vec3 stdDevYCoCg = sqrt(max(m2 / 9.0 - meanYCoCg * meanYCoCg, vec3(0.0)));' + NL +
    NL +
    '  if (any(lessThan(historyUV, vec2(0.0))) || any(greaterThan(historyUV, vec2(1.0)))) {' + NL +
    '    imageStore(u_ResolvedHDRTexture, pixelCoord, vec4(YCoCgToRGB(centerYCoCg), 1.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  vec3 historyRGB = SampleHistoryCatmullRom5Tap(u_HistoryHDRTexture, historyUV, pc.u_InvResolution);' + NL +
    '  vec3 clippedHistoryYCoCg = ClipHistoryYCoCg(RGBToYCoCg(historyRGB), meanYCoCg, stdDevYCoCg, pc.u_VarianceClipGamma);' + NL +
    '  float velMag = length(velocity / max(pc.u_InvResolution, vec2(1e-6)));' + NL +
    '  float blendWeight = clamp(pc.u_BlendFactor + velMag * pc.u_VelocityWeightScale * 0.001, 0.04, 0.50);' + NL +
    '  vec3 resolvedRGB = YCoCgToRGB(mix(clippedHistoryYCoCg, centerYCoCg, blendWeight));' + NL +
    '  imageStore(u_ResolvedHDRTexture, pixelCoord, vec4(resolvedRGB, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateBoxProjectedReflectionProbeFunctions: String;
begin
  Result :=
    '// --- Localized Reflection Probes with Box-Projected Parallax Correction (Phase 17.2) ---' + NL +
    'struct CastleReflectionProbeEntry {' + NL +
    '  vec4 PositionAndRadius;' + NL +
    '  vec4 BoxMinAndIntensity;' + NL +
    '  vec4 BoxMaxAndCubemapIndex;' + NL +
    '  vec4 BlendDistanceAndFlags;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 8) readonly buffer CastleReflectionProbesBuffer {' + NL +
    '  uvec4 u_ProbeHeader;' + NL +
    '  CastleReflectionProbeEntry u_Probes[];' + NL +
    '} CastleReflectionProbes;' + NL +
    NL +
    'vec3 EvaluateBoxProjectedDirection(vec3 worldPos, vec3 worldReflectDir, vec3 probePos, vec3 boxMin, vec3 boxMax) {' + NL +
    '  vec3 safeDir = sign(worldReflectDir) * max(abs(worldReflectDir), vec3(1e-5));' + NL +
    '  vec3 tMax = (boxMax - worldPos) / safeDir;' + NL +
    '  vec3 tMin = (boxMin - worldPos) / safeDir;' + NL +
    '  vec3 tLargest = max(tMax, tMin);' + NL +
    '  float hitDist = min(min(tLargest.x, tLargest.y), tLargest.z);' + NL +
    '  if (hitDist <= 0.0) return normalize(worldReflectDir);' + NL +
    '  vec3 hitPoint = worldPos + worldReflectDir * hitDist;' + NL +
    '  return normalize(hitPoint - probePos);' + NL +
    '}' + NL +
    NL +
    'float EvaluateProbeInfluenceWeight(vec3 worldPos, vec3 boxMin, vec3 boxMax, float blendDistance) {' + NL +
    '  if (any(lessThan(worldPos, boxMin)) || any(greaterThan(worldPos, boxMax))) return 0.0;' + NL +
    '  vec3 distToMin = worldPos - boxMin;' + NL +
    '  vec3 distToMax = boxMax - worldPos;' + NL +
    '  vec3 minEdgeDist = min(distToMin, distToMax);' + NL +
    '  float closestWall = min(min(minEdgeDist.x, minEdgeDist.y), minEdgeDist.z);' + NL +
    '  return clamp(closestWall / max(blendDistance, 1e-4), 0.0, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateClusteredDecalProjectionFunctions: String;
begin
  Result :=
    '// --- Oriented Bounding Box (OBB) Decal Projection Functions (Phase 17.3) ---' + NL +
    'struct CastleProjectedDecalEntry {' + NL +
    '  vec4 WorldToDecalRow0;' + NL +
    '  vec4 WorldToDecalRow1;' + NL +
    '  vec4 WorldToDecalRow2;' + NL +
    '  vec4 AlbedoTintAndOpacity;' + NL +
    '  vec4 DecalNormalAndRoughness;' + NL +
    '  vec4 UVScaleOffset;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 9) readonly buffer CastleProjectedDecalsBuffer {' + NL +
    '  uvec4 u_DecalHeader;' + NL +
    '  CastleProjectedDecalEntry u_Decals[];' + NL +
    '} CastleProjectedDecals;' + NL +
    NL +
    'bool ProjectWorldPointToDecalUV(vec3 worldPos, CastleProjectedDecalEntry decal, out vec2 decalUV, out vec3 localPos) {' + NL +
    '  vec4 wp = vec4(worldPos, 1.0);' + NL +
    '  localPos = vec3(dot(decal.WorldToDecalRow0, wp), dot(decal.WorldToDecalRow1, wp), dot(decal.WorldToDecalRow2, wp));' + NL +
    '  if (any(greaterThan(abs(localPos), vec3(0.5)))) {' + NL +
    '    decalUV = vec2(0.0);' + NL +
    '    return false;' + NL +
    '  }' + NL +
    '  decalUV = (localPos.xy + 0.5) * decal.UVScaleOffset.xy + decal.UVScaleOffset.zw;' + NL +
    '  return true;' + NL +
    '}' + NL +
    NL +
    'float EvaluateDecalAngleAndBoxFade(vec3 localPos, vec3 surfaceNormal, vec3 decalForward, float angleFadeCos) {' + NL +
    '  float cosAngle = dot(normalize(surfaceNormal), normalize(decalForward));' + NL +
    '  float normalWeight = smoothstep(angleFadeCos, min(angleFadeCos + 0.25, 0.99), cosAngle);' + NL +
    '  float zFade = 1.0 - smoothstep(0.35, 0.50, abs(localPos.z));' + NL +
    '  return clamp(normalWeight * zFade, 0.0, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateParticleSimulationComputeShader(
  const AWorkgroupSizeX: Cardinal): String;
var
  LocalX: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 64 else LocalX := AWorkgroupSizeX;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [LocalX]) + NL +
    NL +
    'struct CastleGPUParticle {' + NL +
    '  vec4 PositionAndAge;' + NL +
    '  vec4 VelocityAndMaxLife;' + NL +
    '  vec4 ColorAndSize;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 0) buffer CastleParticlePoolBuffer {' + NL +
    '  CastleGPUParticle u_Particles[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) writeonly buffer CastleAliveParticleIndexBuffer {' + NL +
    '  uint u_AliveParticleIndices[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 2) buffer CastleParticleIndirectDrawBuffer {' + NL +
    '  uint vertexCount;' + NL +
    '  uint instanceCount;' + NL +
    '  uint firstVertex;' + NL +
    '  uint firstInstance;' + NL +
    '} u_DrawCmd;' + NL +
    NL +
    'layout(push_constant) uniform CastleParticleSimPushConstants {' + NL +
    '  vec4  u_GravityAndDeltaTime;' + NL +
    '  vec4  u_EmitterOriginAndDrag;' + NL +
    '  float u_GroundPlaneY;' + NL +
    '  float u_Restitution;' + NL +
    '  uint  u_MaxParticles;' + NL +
    '  uint  u_SpawnSeed;' + NL +
    '} pc;' + NL +
    NL +
    'bool SimulateParticleStep(inout CastleGPUParticle p, vec3 gravity, float drag, float groundY, float restitution, float dt) {' + NL +
    '  float age = p.PositionAndAge.w + dt;' + NL +
    '  float maxLife = p.VelocityAndMaxLife.w;' + NL +
    '  if (maxLife <= 0.0 || age >= maxLife) {' + NL +
    '    p.PositionAndAge.w = age;' + NL +
    '    return false;' + NL +
    '  }' + NL +
    '  vec3 vel = (p.VelocityAndMaxLife.xyz + gravity * dt) * max(1.0 - drag * dt, 0.0);' + NL +
    '  vec3 pos = p.PositionAndAge.xyz + vel * dt;' + NL +
    '  if (pos.y < groundY && vel.y < 0.0) {' + NL +
    '    pos.y = groundY;' + NL +
    '    vel.y = -vel.y * clamp(restitution, 0.0, 1.0);' + NL +
    '  }' + NL +
    '  p.PositionAndAge = vec4(pos, age);' + NL +
    '  p.VelocityAndMaxLife.xyz = vel;' + NL +
    '  return true;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint idx = gl_GlobalInvocationID.x;' + NL +
    '  if (idx == 0u) {' + NL +
    '    u_DrawCmd.vertexCount = 6u;' + NL +
    '    u_DrawCmd.firstVertex = 0u;' + NL +
    '    u_DrawCmd.firstInstance = 0u;' + NL +
    '  }' + NL +
    '  if (idx >= pc.u_MaxParticles) return;' + NL +
    '  CastleGPUParticle p = u_Particles[idx];' + NL +
    '  if (SimulateParticleStep(p, pc.u_GravityAndDeltaTime.xyz, pc.u_EmitterOriginAndDrag.w,' + NL +
    '      pc.u_GroundPlaneY, pc.u_Restitution, pc.u_GravityAndDeltaTime.w)) {' + NL +
    '    uint aliveSlot = atomicAdd(u_DrawCmd.instanceCount, 1u);' + NL +
    '    u_AliveParticleIndices[aliveSlot] = idx;' + NL +
    '  }' + NL +
    '  u_Particles[idx] = p;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateWeightedBlendedOITFunctions: String;
begin
  Result :=
    '// --- McGuire & Bavoil Weighted Blended Order-Independent Transparency (Phase 18.2) ---' + NL +
    'float EvaluateOITDepthWeight(float linearZ, float alpha, float weightScale) {' + NL +
    '  float normZ = clamp(linearZ / max(weightScale, 1.0), 0.0, 0.99);' + NL +
    '  float oneMinusZ = 1.0 - normZ;' + NL +
    '  float depthFactor = max(1e-2, 3000.0 * oneMinusZ * oneMinusZ * oneMinusZ);' + NL +
    '  return clamp(max(alpha, 1e-3) * depthFactor, 1e-2, 3000.0);' + NL +
    '}' + NL +
    NL +
    'void AccumulateWeightedBlendedOIT(vec4 premulColorAndAlpha, float linearZ, float weightScale,' + NL +
    '  out vec4 outAccum, out float outRevealage) {' + NL +
    '  float a = clamp(premulColorAndAlpha.a, 0.0, 1.0);' + NL +
    '  float w = EvaluateOITDepthWeight(linearZ, a, weightScale);' + NL +
    '  outAccum = vec4(premulColorAndAlpha.rgb * w, a * w);' + NL +
    '  outRevealage = a;' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateOITComposite(vec4 accumRGBA, float revealage, vec3 opaqueRGB) {' + NL +
    '  float transmittance = clamp(revealage, 0.0, 1.0);' + NL +
    '  if (transmittance >= 0.9999) return opaqueRGB;' + NL +
    '  vec3 avgTransparentColor = accumRGBA.rgb / max(accumRGBA.a, 1e-5);' + NL +
    '  return avgTransparentColor * (1.0 - transmittance) + opaqueRGB * transmittance;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateWeightedBlendedOITCompositeFragmentShader: String;
begin
  Result :=
    '#version 450' + NL +
    'layout(location = 0) in vec2 v_TexCoord;' + NL +
    'layout(location = 0) out vec4 out_FragColor;' + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_OpaqueHDRTexture;' + NL +
    'layout(set = 0, binding = 1) uniform sampler2D u_OITAccumTexture;' + NL +
    'layout(set = 0, binding = 2) uniform sampler2D u_OITRevealageTexture;' + NL +
    NL +
    GenerateWeightedBlendedOITFunctions + NL +
    'void main() {' + NL +
    '  vec3 opaqueRGB = texture(u_OpaqueHDRTexture, v_TexCoord).rgb;' + NL +
    '  vec4 accumRGBA = texture(u_OITAccumTexture, v_TexCoord);' + NL +
    '  float revealage = texture(u_OITRevealageTexture, v_TexCoord).r;' + NL +
    '  vec3 composited = EvaluateOITComposite(accumRGBA, revealage, opaqueRGB);' + NL +
    '  out_FragColor = vec4(composited, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateContactShadowsComputeShader(
  const AWorkgroupSizeX, AWorkgroupSizeY: Cardinal): String;
var
  LocalX, LocalY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then LocalX := 8 else LocalX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then LocalY := 8 else LocalY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalX, LocalY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_DepthTexture;' + NL +
    'layout(set = 0, binding = 1, r16f) uniform writeonly image2D u_ContactShadowMask;' + NL +
    NL +
    'layout(push_constant) uniform CastleContactShadowsPushConstants {' + NL +
    '  vec2  u_InvResolution;' + NL +
    '  vec3  u_LightDirView;' + NL +
    '  float u_RayLength;' + NL +
    '  float u_Thickness;' + NL +
    '  float u_ZNear;' + NL +
    '  float u_ZFar;' + NL +
    '  uint  u_StepCount;' + NL +
    '  float u_Contrast;' + NL +
    '  uint  u_Reserved;' + NL +
    '} pc;' + NL +
    NL +
    'float LinearizeContactDepth(float d, float zNear, float zFar) {' + NL +
    '  return (zNear * zFar) / max(zFar - d * (zFar - zNear), 1e-5);' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  ivec2 pixelCoord = ivec2(gl_GlobalInvocationID.xy);' + NL +
    '  ivec2 outSize = imageSize(u_ContactShadowMask);' + NL +
    '  if (pixelCoord.x >= outSize.x || pixelCoord.y >= outSize.y) return;' + NL +
    NL +
    '  vec2 uv = (vec2(pixelCoord) + 0.5) * pc.u_InvResolution;' + NL +
    '  float centerRawDepth = textureLod(u_DepthTexture, uv, 0.0).r;' + NL +
    '  if (centerRawDepth >= 0.9999) {' + NL +
    '    imageStore(u_ContactShadowMask, pixelCoord, vec4(1.0));' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  float startLinearZ = LinearizeContactDepth(centerRawDepth, pc.u_ZNear, pc.u_ZFar);' + NL +
    '  uint steps = max(pc.u_StepCount, 4u);' + NL +
    '  vec2 uvStep = (pc.u_LightDirView.xy * pc.u_RayLength * 0.25) / float(steps);' + NL +
    '  float zStep = (-pc.u_LightDirView.z * pc.u_RayLength) / float(steps);' + NL +
    '  float shadowOcclusion = 0.0;' + NL +
    NL +
    '  for (uint i = 1u; i <= steps; ++i) {' + NL +
    '    float t = float(i) / float(steps);' + NL +
    '    vec2 sampleUV = uv + uvStep * float(i);' + NL +
    '    if (any(lessThan(sampleUV, vec2(0.0))) || any(greaterThan(sampleUV, vec2(1.0)))) break;' + NL +
    '    float rayLinearZ = startLinearZ + zStep * float(i);' + NL +
    '    float sceneLinearZ = LinearizeContactDepth(textureLod(u_DepthTexture, sampleUV, 0.0).r, pc.u_ZNear, pc.u_ZFar);' + NL +
    '    float depthDelta = rayLinearZ - sceneLinearZ;' + NL +
    '    if (depthDelta > 0.001 && depthDelta < pc.u_Thickness) {' + NL +
    '      shadowOcclusion = max(shadowOcclusion, (1.0 - t * t) * clamp(pc.u_Contrast, 0.0, 1.0));' + NL +
    '      break;' + NL +
    '    }' + NL +
    '  }' + NL +
    '  imageStore(u_ContactShadowMask, pixelCoord, vec4(clamp(1.0 - shadowOcclusion, 0.0, 1.0)));' + NL +
    '}' + NL;
end;

class function TCastleShaderGeneratorRHI.ComputeSourceHash(const FinalGLSL: String): UInt64;
const
  FNV_OFFSET_BASIS: UInt64 = QWord($CBF29CE484222325);
  FNV_PRIME: UInt64 = $100000001B3;
var
  I: Integer;
begin
  {$Q-}{$R-}
  Result := FNV_OFFSET_BASIS;
  for I := 1 to Length(FinalGLSL) do
  begin
    Result := Result xor Ord(FinalGLSL[I]);
    Result := Result * FNV_PRIME;
  end;
  {$Q+}{$R+}
end;

end.
