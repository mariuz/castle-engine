{%MainUnit castleinternalshaderrhi_experimental.pas}
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

  { Phase 23.2: Virtual Shadow Map (VSM) Page Table & Physical Tile Pool dimensions }
  CASTLE_VSM_PAGE_TABLE_DIM           = 64;
  CASTLE_VSM_PHYSICAL_TILE_SIZE       = 128;
  CASTLE_VSM_PHYSICAL_TILES_PER_ROW   = 16;
  CASTLE_VSM_MAX_PHYSICAL_TILES       = 256;

type
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

  { Class helper exposing experimental & research shader generation and CPU
    reference math methods on TCastleShaderGeneratorRHI when opted in. }
  TCastleShaderGeneratorRHIExperimentalHelper = class helper for TCastleShaderGeneratorRHI
  public

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

    { Phase 22.3: Generates GLSL 450 functions for AMD FidelityFX Contrast-Adaptive Sharpening
      (EvaluateCASFilter5Tap) and Edge-Adaptive Spatial Upscaling. }
    function GenerateCASSharpeningAndUpscaleFunctions: String;

    { Phase 22.3 CPU reference: Evaluates 5-tap Contrast-Adaptive Sharpening (CAS) without halo ringing. }
    class function EvaluateCASFilter5Tap(
      const ACenter, ANorth, ASouth, AEast, AWest: TVector3;
      const ASharpness: Single): TVector3; static;

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
  end;

{$endif read_interface}
