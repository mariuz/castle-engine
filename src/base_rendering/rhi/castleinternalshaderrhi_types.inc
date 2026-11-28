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

  { Phase 22.2: Maximum GPU Meshlets per culler batch }
  CASTLE_MAX_MESHLETS                 = 4096;

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
    function GenerateVersionAndLayoutMacrosForStage(const AStage: TRHIShaderStage): String;
    function GenerateStandardUniformBlocks(const AStage: TRHIShaderStage): String;
    function GenerateStageIO(const AStage: TRHIShaderStage): String;
  public
    constructor Create(const ABackend: TRHIBackendType);
    function GenerateVersionAndLayoutMacros: String;

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

    { Phase 18.2: Generates GLSL 450 functions for McGuire & Bavoil Weighted Blended
      Order-Independent Transparency (EvaluateOITDepthWeight, AccumulateWeightedBlendedOIT,
      EvaluateOITComposite). }
    function GenerateWeightedBlendedOITFunctions: String;

    { Phase 18.2: Generates a complete GLSL 450 fragment shader for compositing Weighted Blended
      OIT accumulation (pfRGBA16_Float) and revealage (pfR16_Float) targets over the opaque HDR scene. }
    function GenerateWeightedBlendedOITCompositeFragmentShader: String;

    { Phase 22.2: Generates a GLSL 450 compute shader for GPU Meshlet / Sub-Mesh Cluster
      Bounding-Sphere & Normal-Cone Backface Culling. }
    function GenerateMeshletCullingComputeShader(
      const AWorkgroupSizeX: Cardinal = 64): String;

    { Phase 22.2 CPU reference: Returns True if the meshlet normal cone is 100% backfacing to ACameraPosition. }
    class function EvaluateMeshletConeBackfaceCull(
      const AMeshletCenter, ACameraPosition, AConeAxis: TVector3;
      const AConeCutoff: Single): Boolean; static;

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
