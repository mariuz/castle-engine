{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

{ Opt-in test suite for experimental UE5/RTX research shaders & Vulkan RHI managers
  (src/base_rendering/experimental/). Isolated in Upstream PR Slice 9. }
unit TestCastleVulkanRHI_Experimental;

{$I ../../../src/common_includes/castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleTester, CastleUtils, CastleVectors, CastleColors, CastleRectangles,
  CastleBoxes, CastleFrustum, CastleTimeUtils,
  CastleApplicationProperties, CastleImages,
  CastleInternalRHI, CastleInternalVulkan, CastleInternalVulkanMemory,
  CastleInternalVulkanWSI, CastleInternalShaderCompiler, CastleInternalRHI_Vulkan,
  CastleInternalShaderRHI,
  CastleInternalShaderRHI_Experimental, CastleInternalRHI_Vulkan_Experimental,
  CastleTransform, CastleSceneCore, CastleScene, CastleViewport, CastleRenderOptions,
  CastleFilesUtils, CastleUriUtils,
  TestCastleVulkanRHI;

type
  TTestCastleVulkanRHIExperimental = class(TCastleTestCase)
  published
    procedure TestBoxProjectedParallaxReflectionProbesRHI;
    procedure TestOrientedBoxDecalProjectionRHI;
    procedure TestGPUComputeParticleSimulationAndIndirectDrawRHI;
    procedure TestScreenSpaceRaymarchedContactShadowsRHI;
    procedure TestComputeSkinningAndMorphTargetsRHI;
    procedure TestGPUDrivenTerrainCDLODRHI;
    procedure TestSubsurfaceScatteringAndFoliageTransmissionPBRRHI;
    procedure TestClearCoatAndAnisotropicPBRRHI;
    procedure TestRayleighMieAtmosphereSkyLUTComputeRHI;
    procedure TestLensFlareAndChromaticAberrationPostProcessRHI;
    procedure TestClothSheenAndIridescencePBRRHI;
    procedure TestComputeGerstnerOceanSimulationAndFoamRHI;
    procedure TestMotionBlurAndBokehDepthOfFieldPostProcessRHI;
    procedure TestDDGIOctahedralProbeGridRHI;
    procedure TestContrastAdaptiveSharpeningCASRHI;
    procedure TestVirtualShadowMapPageTableAndTilePoolRHI;
    procedure TestSeparableSubsurfaceScatteringBurleyDiffusionRHI;
    procedure TestGPUDrivenContinuousLODSelectionRHI;
    procedure TestBentNormalsAndSpecularOcclusionRHI;
    procedure TestColorGrading3DLUTAndFilmGrainVignetteRHI;
    procedure TestVolumetricCloudDualLobeHGAndBeerPowderRHI;
    procedure TestGPUTextureStreamingMipFeedbackRHI;
    procedure TestEquirectangularToCubemapPanoramaConverterRHI;
    procedure TestAnalyticAreaLightLTCSolidAngleRHI;
    procedure TestTriplanarAndHeightModulatedBlendingRHI;
    procedure TestGPUShadowCasterLightRayExtrusionCullingRHI;
    procedure TestVisibilityBufferPayloadAndBarycentricsRHI;
    procedure TestNaniteClusterDAGCutSelectionRHI;
    procedure TestSoftwareMicroPolygonComputeRasterizerRHI;
    procedure TestGlobalSDFClipmapSphereTracingRHI;
    procedure TestLumenSurfaceCacheSixAxisCardAtlasRHI;
    procedure TestScreenSpaceRadianceCacheProbesRHI;
    procedure TestReSTIRWeightedReservoirSamplingRISRHI;
    procedure TestReSTIRNeighborSimilarityAndReservoirCombineRHI;
    procedure TestVulkanReSTIRSpatioTemporalManagerRHI;
    procedure TestTSRLanczos2AndBlackmanHarrisKernelsRHI;
    procedure TestTSRDisocclusionAndThinGeometryAntiGhostingRHI;
    procedure TestVulkanTSRUpscalerHistoryManagerRHI;
    procedure TestSubstrateLayeredMaterialSlabsRHI;
    procedure TestMarschnerDualSpecularHairBSDFRHI;
    procedure TestStochasticDiscreteMicrofacetGlintsRHI;
    procedure TestVariableRateShadingTileClassifierRHI;
    procedure TestRuntimeVirtualTexturePageTableAndAtlasRHI;
    procedure TestSingleLayerWaterAbsorptionRefractionAndCausticsRHI;
    procedure TestSparseVolumeBrickAtlasAndBlackbodyEmissionRHI;
    procedure TestGPUBreadcrumbCrashTrackerDiagnosticsRHI;
    procedure TestSVGFVarianceMomentsAndTemporalVarianceRHI;
    procedure TestSVGFAttrousWaveletEdgeStoppingAndContactHardeningRHI;
    procedure TestVulkanSVGFDenoiserMultiPassDispatchRHI;
    procedure TestXPBDDistanceConstraintComplianceRHI;
    procedure TestAerodynamicWindForceAndSphereCollisionRHI;
    procedure TestVulkanXPBDSimulatorSubstepDispatchRHI;
    procedure TestMultiviewStereoPreambleAndAsymmetricEyeProjectionRHI;
    procedure TestFoveatedShadingRateAndMultiviewStereoManagerRHI;
    procedure TestHDR10Rec2020AndST2084PQEncodingRHI;
    procedure TestDualQuaternionSkinningVolumePreservationRHI;
    procedure TestDisplacedMicroMeshBarycentricsAndEdgeSnappingRHI;
    procedure TestVulkanPerInstanceCustomDataSSBORHI;
    procedure TestOpticalFlowBlockMatchingAndSubpixelOffsetRHI;
    procedure TestSpatioTemporalBlueNoiseAndR2SequenceRHI;
    procedure TestVulkanNeuralDenoiserMLPInferenceRHI;
    procedure TestSERCoherenceHintKeyPackingRHI;
    procedure TestDualSourceColoredGlassTransmissionRHI;
    procedure TestVulkanProgrammableSampleLocationsRGSSRHI;
    procedure TestDynamicRenderingLocalReadDeferredLightingRHI;
    procedure TestSubgroupWaveBallotAndExclusivePrefixSumRHI;
    procedure TestVulkanStreamCompactorPrefixSumRHI;
    procedure TestBufferDeviceAddressAlignmentAndPreambleRHI;
    procedure TestVoxelDominantAxisAndConeStepApertureRHI;
    procedure TestVulkanVoxelConeTracerMipChainAndDispatchRHI;
    procedure TestSpecularNormalVarianceAARoughnessFilteringRHI;
    procedure TestRectilinearShadowMapUVWarpingRHI;
    procedure TestMSDFMedianOfThreeAndScreenPxOpacityRHI;
    procedure TestQuadraticBezierGrassBladePositionAndTangentRHI;
    procedure TestVulkanPerPixelLinkedListOITSortAndResolveRHI;
    procedure TestPushDescriptorPreambleAndHostImageCopyByteSizeRHI;
    procedure TestSphericalGaussianProductAndIntegralRHI;
    procedure TestVulkanHostImageCopyAndPushDescriptorManagerRHI;
    procedure TestGaussianSplatConicOpacityFalloffRHI;
    procedure TestSphericalHarmonicsL1ViewDependentRadianceRHI;
    procedure TestVulkanGaussianSplatRendererFrontToBackRHI;
    procedure TestPCSSContactHardeningPenumbraWidthRHI;
    procedure TestDescriptorBufferAlignedOffsetCalculationRHI;
    procedure TestVulkanDescriptorBufferManagerAllocationAndBindRHI;
    procedure TestCarPaintMultiLayerFlakeBRDFRHI;
    procedure TestScreenSpaceCurvatureCavityShadingRHI;
    procedure TestAgXChromaGamutCompressionRHI;
    procedure TestCapsuleSoftShadowOcclusionRHI;
    procedure TestEpipolarSliceRayStepRHI;
    procedure TestCooperativeMatrixPreambleAndFP8DecodingRHI;
    procedure TestAnisotropicKuwaharaStructureTensorOrientationRHI;
    procedure TestVulkanIndirectComputeDispatcherWorkgroupsAndRecordRHI;
    procedure TestPhysicalEyeCorneaRefractionUVOffsetRHI;
    procedure TestSixPointDirectionalLightmapBasisRHI;
    procedure TestVulkanBCnCompressorEndpoint565AndDispatchRHI;
    procedure TestSecantRefinedPOMIntersectionRHI;
    procedure TestCauchyChromaticDispersionRefractiveIndexRHI;
    procedure TestVulkanPipelineBinaryManagerStoreAndLookupRHI;
    procedure TestViewportExecuteVulkanSubsystemsOrchestrationRHI;
    procedure TestViewportExecuteSceneRenderOptionsSubsystemsRHI;
    procedure TestViewportExecuteAllScenesRenderOptionsSubsystemsTreeRHI;
    procedure TestExperimentalSubsystemsIsolatedFromCoreRHIUnitsRHI;
  end;

implementation

{ TTestCastleVulkanRHIExperimental }

procedure TTestCastleVulkanRHIExperimental.TestBoxProjectedParallaxReflectionProbesRHI;
var
  VkDev: TVulkanRHIDevice;
  Probes: TCastleVulkanReflectionProbeManager;
  Gen: TCastleShaderGeneratorRHI;
  ProbeGLSL: String;
  BoxMin, BoxMax, ProbePos, SurfacePos, ReflectDir, CorrectedDir: TVector3;
  WCenter, WNearWall, WOutside: Single;
  ProbeIdx: Integer;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify struct size and GLSL 450 Box-Projected Reflection Probe functions }
    AssertEquals('TCastleReflectionProbeEntry size must be 64 bytes',
      64, SizeOf(TCastleReflectionProbeEntry));

    ProbeGLSL := Gen.GenerateBoxProjectedReflectionProbeFunctions;
    AssertTrue('Probe GLSL must include EvaluateBoxProjectedDirection',
      Pos('vec3 EvaluateBoxProjectedDirection(vec3 worldPos, vec3 worldReflectDir, vec3 probePos, vec3 boxMin, vec3 boxMax)', ProbeGLSL) > 0);
    AssertTrue('Probe GLSL must include EvaluateProbeInfluenceWeight',
      Pos('float EvaluateProbeInfluenceWeight(vec3 worldPos, vec3 boxMin, vec3 boxMax, float blendDistance)', ProbeGLSL) > 0);

    { 2. Verify Box-Projected Parallax ray-AABB intersection & trilinear influence weights }
    Probes := VkDev.ReflectionProbeManager;
    AssertTrue('ReflectionProbeManager must be lazily created by TVulkanRHIDevice', Probes <> nil);

    BoxMin := Vector3(-10.0, 0.0, -10.0);
    BoxMax := Vector3( 10.0, 6.0,  10.0);
    ProbePos := Vector3(0.0, 3.0, 0.0);

    { Surface at (5, 0, 0) reflecting straight up (0, 1, 0) hits ceiling at (5, 6, 0).
      Vector from ProbePos (0, 3, 0) to hit point (5, 6, 0) is normalize(5, 3, 0) -> X > 0, Y > 0!
      Without parallax correction, unprojected lookup would be (0, 1, 0) with X = 0. }
    SurfacePos := Vector3(5.0, 0.0, 0.0);
    ReflectDir := Vector3(0.0, 1.0, 0.0);
    CorrectedDir := Probes.EvaluateBoxProjectedDirection(SurfacePos, ReflectDir, ProbePos, BoxMin, BoxMax);
    AssertTrue('Box-projected parallax reflection must shift X lookup toward +X wall (> 0.8)',
      CorrectedDir.X > 0.8);
    AssertTrue('Box-projected parallax reflection must point upward in +Y (> 0.4)',
      CorrectedDir.Y > 0.4);

    WCenter := Probes.EvaluateProbeInfluenceWeight(Vector3(0.0, 3.0, 0.0), BoxMin, BoxMax, 2.0);
    WNearWall := Probes.EvaluateProbeInfluenceWeight(Vector3(9.0, 3.0, 0.0), BoxMin, BoxMax, 2.0);
    WOutside := Probes.EvaluateProbeInfluenceWeight(Vector3(12.0, 3.0, 0.0), BoxMin, BoxMax, 2.0);
    AssertSameValue(1.0, WCenter, 1e-4);
    AssertSameValue(0.5, WNearWall, 1e-4);
    AssertSameValue(0.0, WOutside, 1e-5);

    { 3. Verify probe registration and GPU SSBO/UBO upload }
    ProbeIdx := Probes.AddProbe(ProbePos, BoxMin, BoxMax, 15.0, 1.2, 2.0, 0, True);
    AssertEquals('First reflection probe index must be 0', 0, ProbeIdx);
    AssertEquals('ProbeCount must be 1', 1, Probes.ProbeCount);

    Probes.UploadProbes;
    AssertTrue('ProbeBuffer must be allocated after UploadProbes', Probes.ProbeBuffer <> nil);
    AssertEquals('TotalUploads must be 1', 1, Probes.TotalUploads);
  finally
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestOrientedBoxDecalProjectionRHI;
var
  VkDev: TVulkanRHIDevice;
  Decals: TCastleVulkanDecalManager;
  Gen: TCastleShaderGeneratorRHI;
  DecalGLSL: String;
  DecalIdx: Integer;
  Entry: TCastleProjectedDecalEntry;
  DecalUV: TVector2;
  LocalPos: TVector3;
  FadeAligned, FadePerpendicular: Single;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify struct size and GLSL 450 Clustered Box Decal Projection functions }
    AssertEquals('TCastleProjectedDecalEntry size must be 96 bytes',
      96, SizeOf(TCastleProjectedDecalEntry));

    DecalGLSL := Gen.GenerateClusteredDecalProjectionFunctions;
    AssertTrue('Decal GLSL must include ProjectWorldPointToDecalUV',
      Pos('bool ProjectWorldPointToDecalUV(vec3 worldPos, CastleProjectedDecalEntry decal, out vec2 decalUV, out vec3 localPos)', DecalGLSL) > 0);
    AssertTrue('Decal GLSL must include EvaluateDecalAngleAndBoxFade',
      Pos('float EvaluateDecalAngleAndBoxFade(vec3 localPos, vec3 surfaceNormal, vec3 decalForward, float angleFadeCos)', DecalGLSL) > 0);

    { 2. Verify OBB decal UV projection, outside-box rejection & normal grazing-angle fade }
    Decals := VkDev.DecalManager;
    AssertTrue('DecalManager must be lazily created by TVulkanRHIDevice', Decals <> nil);

    DecalIdx := Decals.AddBoxDecal(
      Vector3(10.0, 2.0, -5.0),
      Vector3(2.0, 2.0, 1.0),
      Vector3(0.0, 1.0, 0.0),
      Vector3(0.9, 0.2, 0.1),
      0.85, 0.4, Vector4(1.0, 1.0, 0.0, 0.0));
    AssertEquals('First decal index must be 0', 0, DecalIdx);
    AssertEquals('DecalCount must be 1', 1, Decals.DecalCount);

    Entry := Decals.GetDecal(0);
    AssertTrue('Center world point (10, 2, -5) must project inside decal box',
      Decals.ProjectWorldPointToDecalUV(Vector3(10.0, 2.0, -5.0), Entry, DecalUV, LocalPos));
    AssertSameValue(0.5, DecalUV.X, 1e-4);
    AssertSameValue(0.5, DecalUV.Y, 1e-4);

    AssertFalse('Exterior world point (20, 2, -5) must be rejected outside decal box',
      Decals.ProjectWorldPointToDecalUV(Vector3(20.0, 2.0, -5.0), Entry, DecalUV, LocalPos));

    FadeAligned := Decals.EvaluateDecalAngleAndBoxFade(
      Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0), 0.25);
    FadePerpendicular := Decals.EvaluateDecalAngleAndBoxFade(
      Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 0.25);
    AssertSameValue(1.0, FadeAligned, 1e-4);
    AssertSameValue(0.0, FadePerpendicular, 1e-4);

    { 3. Verify GPU buffer upload }
    Decals.UploadDecals;
    AssertTrue('DecalBuffer must be allocated after UploadDecals', Decals.DecalBuffer <> nil);
    AssertEquals('TotalUploads must be 1', 1, Decals.TotalUploads);
  finally
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestGPUComputeParticleSimulationAndIndirectDrawRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  Particles: TCastleVulkanComputeParticles;
  SimCS: String;
  Particle: TCastleGPUParticle;
  Alive: Boolean;
  GroupsDispatched: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify TCastleGPUParticle (48B) & TCastleParticleSimPushConstants (48B) & Compute GLSL }
    AssertEquals('TCastleGPUParticle must be 48 bytes (3 x vec4)',
      48, SizeOf(TCastleGPUParticle));
    AssertEquals('TCastleParticleSimPushConstants must be 48 bytes',
      48, SizeOf(TCastleParticleSimPushConstants));

    SimCS := Gen.GenerateParticleSimulationComputeShader(64);
    AssertTrue('Particle simulation CS must use local_size_x = 64',
      Pos('layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;', SimCS) > 0);
    AssertTrue('Particle simulation CS must atomically compact alive particles via atomicAdd',
      Pos('uint aliveSlot = atomicAdd(u_DrawCmd.instanceCount, 1u);', SimCS) > 0);

    { 2. Verify Euler integration, drag, ground plane bounce, and lifetime expiration }
    Particle.PositionAndAge := Vector4(0.0, 0.05, 0.0, 0.0);
    Particle.VelocityAndMaxLife := Vector4(1.0, -4.0, 0.0, 1.0);
    Particle.ColorAndSize := Vector4(1.0, 0.5, 0.1, 0.25);

    Alive := TCastleVulkanComputeParticles.SimulateParticleStep(
      Particle, Vector3(0.0, -9.81, 0.0), 0.1, 0.0, 0.6, 0.1);
    AssertTrue('Particle must remain alive at Age=0.1 / MaxLife=1.0', Alive);
    AssertSameValue(0.0, Particle.PositionAndAge.Y, 1e-4);
    AssertTrue('Particle Y velocity must bounce upward (> 0) after hitting GroundY=0',
      Particle.VelocityAndMaxLife.Y > 0.0);

    Alive := TCastleVulkanComputeParticles.SimulateParticleStep(
      Particle, Vector3(0.0, -9.81, 0.0), 0.1, 0.0, 0.6, 1.0);
    AssertFalse('Particle must expire when Age >= MaxLife', Alive);

    { 3. Verify GPU particle buffers and simulation dispatch }
    Particles := VkDev.ComputeParticles;
    AssertTrue('ComputeParticles must be lazily created by TVulkanRHIDevice', Particles <> nil);
    Particles.EnsureParticleBuffers(4096);
    AssertEquals('MaxParticles must be 4096', 4096, Particles.MaxParticles);
    AssertTrue('ParticleBuffer must be allocated', Particles.ParticleBuffer <> nil);
    AssertTrue('AliveIndexBuffer must be allocated', Particles.AliveIndexBuffer <> nil);
    AssertTrue('IndirectDrawBuffer must be allocated', Particles.IndirectDrawBuffer <> nil);

    CmdList.BeginRecording;
    GroupsDispatched := Particles.DispatchParticleSimulation(CmdList, 1.0 / 60.0);
    CmdList.EndRecording;

    AssertEquals('4096 particles / 64 threads = 64 workgroups', 64, GroupsDispatched);
    AssertEquals('TotalSimulationDispatches must be 1', 1, Particles.TotalSimulationDispatches);
    AssertTrue('SimulationPipeline must be compiled and cached', Particles.SimulationPipeline <> nil);
  finally
    FreeAndNil(Gen);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestScreenSpaceRaymarchedContactShadowsRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  ContactShadows: TCastleVulkanContactShadows;
  DepthTex: TRHITexture;
  ContactCS: String;
  OccludedDepths, ThickGapDepths: array[0..3] of Single;
  VisOccluded, VisGap: Single;
  HitOccluded, HitGap: Boolean;
  Groups: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  DepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(320, 180, pfD32_Float,
    [tuDepthStencil, tuSampled]));
  try
    { 1. Verify TCastleContactShadowsPushConstants (48 bytes) & Compute GLSL }
    AssertEquals('TCastleContactShadowsPushConstants must be 48 bytes',
      48, SizeOf(TCastleContactShadowsPushConstants));

    ContactCS := Gen.GenerateContactShadowsComputeShader(8, 8);
    AssertTrue('Contact shadows CS must use 8x8 workgroup',
      Pos('layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;', ContactCS) > 0);
    AssertTrue('Contact shadows CS must apply thickness window check',
      Pos('if (depthDelta > 0.001 && depthDelta < pc.u_Thickness)', ContactCS) > 0);

    { 2. Verify 1D contact shadow raymarch occlusion hit vs thickness-window rejection }
    OccludedDepths[0] := 5.0;
    OccludedDepths[1] := 4.91; { RayZ at step 2 = 5.0 - 0.03*2 = 4.94 -> DepthDelta = +0.03 within Thickness 0.05 }
    OccludedDepths[2] := 5.0;
    OccludedDepths[3] := 5.0;
    HitOccluded := TCastleVulkanContactShadows.EvaluateContactShadowRay1D(
      OccludedDepths, 5.0, -0.03, 0.05, VisOccluded);
    AssertTrue('Thin occluder within thickness window must register contact shadow hit', HitOccluded);
    AssertTrue('Contact shadow visibility must be darkened (< 1.0)', VisOccluded < 1.0);

    ThickGapDepths[0] := 5.0;
    ThickGapDepths[1] := 2.0; { Foreground object 2.94m closer than ray -> exceeds Thickness 0.05, must not cast false shadow }
    ThickGapDepths[2] := 5.0;
    ThickGapDepths[3] := 5.0;
    HitGap := TCastleVulkanContactShadows.EvaluateContactShadowRay1D(
      ThickGapDepths, 5.0, -0.03, 0.05, VisGap);
    AssertFalse('Foreground object outside thickness window must be rejected', HitGap);
    AssertSameValue(1.0, VisGap, 1e-5);

    { 3. Verify contact shadows compute dispatch }
    ContactShadows := VkDev.ContactShadows;
    AssertTrue('ContactShadows must be lazily created by TVulkanRHIDevice', ContactShadows <> nil);

    CmdList.BeginRecording;
    Groups := ContactShadows.DispatchContactShadows(CmdList, DepthTex);
    CmdList.EndRecording;

    AssertEquals('320x180 / 8x8 = 40 * 23 = 920 workgroups', 40 * 23, Groups);
    AssertEquals('TotalContactShadowDispatches must be 1', 1, ContactShadows.TotalContactShadowDispatches);
    AssertTrue('ContactShadowTexture must be allocated', ContactShadows.ContactShadowTexture <> nil);
    AssertTrue('ContactShadowPipeline must be compiled', ContactShadows.ContactShadowPipeline <> nil);
  finally
    FreeAndNil(DepthTex);
    FreeAndNil(Gen);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestComputeSkinningAndMorphTargetsRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  Skinner: TCastleVulkanComputeSkinner;
  SkinCS: String;
  SrcVert: TCastleSkinningVertex;
  Deltas: array[0..1] of TCastleMorphTargetDelta;
  Joints: array[0..1] of TMatrix4;
  SkinnedPos, SkinnedNorm: TVector3;
  Groups: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify struct sizes and Compute Skinning GLSL }
    AssertEquals('TCastleSkinningVertex must be 64 bytes',
      64, SizeOf(TCastleSkinningVertex));
    AssertEquals('TCastleMorphTargetDelta must be 32 bytes',
      32, SizeOf(TCastleMorphTargetDelta));
    AssertEquals('TCastleComputeSkinningPushConstants must be 32 bytes',
      32, SizeOf(TCastleComputeSkinningPushConstants));

    SkinCS := Gen.GenerateComputeSkinningShader(64);
    AssertTrue('Compute skinning CS must use local_size_x = 64',
      Pos('layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;', SkinCS) > 0);
    AssertTrue('Compute skinning CS must output previous positions for TAA motion vectors',
      Pos('u_PreviousPositions[vid] = vec4(u_SkinnedVertices[vid].PositionAndUVX.xyz, 1.0);', SkinCS) > 0);

    { 2. Verify morph target displacement + 2-bone linear blend skinning }
    FillChar(SrcVert, SizeOf(SrcVert), 0);
    SrcVert.PositionAndUVX := Vector4(1.0, 2.0, 0.0, 0.5);
    SrcVert.NormalAndUVY := Vector4(0.0, 1.0, 0.0, 0.5);
    SrcVert.JointIndices[0] := 0;
    SrcVert.JointIndices[1] := 1;
    SrcVert.JointWeights := Vector4(0.5, 0.5, 0.0, 0.0);

    FillChar(Deltas, SizeOf(Deltas), 0);
    Deltas[0].DeltaPosition := Vector4(2.0, 0.0, 0.0, 0.0); { weight 0.5 -> +1.0 X }
    Deltas[1].DeltaPosition := Vector4(0.0, 4.0, 0.0, 0.0); { weight 0.25 -> +1.0 Y }

    Joints[0] := TranslationMatrix(10.0, 0.0, 0.0);
    Joints[1] := TranslationMatrix(20.0, 0.0, 0.0);

    { Morphed pos = (1+1, 2+1, 0) = (2, 3, 0).
      50% Joint 0 (+10 X -> 12) + 50% Joint 1 (+20 X -> 22) = (17, 3, 0) }
    TCastleVulkanComputeSkinner.EvaluateVertexSkinningAndMorph(
      SrcVert, Deltas, Vector4(0.5, 0.25, 0.0, 0.0), Joints, SkinnedPos, SkinnedNorm);
    AssertSameValue(17.0, SkinnedPos.X, 1e-4);
    AssertSameValue(3.0, SkinnedPos.Y, 1e-4);
    AssertSameValue(0.0, SkinnedPos.Z, 1e-4);
    AssertSameValue(1.0, SkinnedNorm.Y, 1e-4);

    { 3. Verify GPU skinning buffer allocation and compute dispatch }
    Skinner := VkDev.ComputeSkinner;
    AssertTrue('ComputeSkinner must be lazily created by TVulkanRHIDevice', Skinner <> nil);
    Skinner.EnsureSkinningBuffers(2048, 4);
    AssertEquals('MaxVertices must be 2048', 2048, Skinner.MaxVertices);
    AssertTrue('SourceVertexBuffer must be allocated', Skinner.SourceVertexBuffer <> nil);
    AssertTrue('MorphDeltaBuffer must be allocated', Skinner.MorphDeltaBuffer <> nil);
    AssertTrue('JointMatrixBuffer must be allocated', Skinner.JointMatrixBuffer <> nil);
    AssertTrue('SkinnedVertexBuffer must be allocated', Skinner.SkinnedVertexBuffer <> nil);
    AssertTrue('PreviousPositionBuffer must be allocated', Skinner.PreviousPositionBuffer <> nil);

    CmdList.BeginRecording;
    Groups := Skinner.DispatchComputeSkinning(CmdList, 1000, 32, True);
    CmdList.EndRecording;

    AssertEquals('1000 vertices / 64 threads = 16 workgroups', 16, Groups);
    AssertEquals('TotalSkinningDispatches must be 1', 1, Skinner.TotalSkinningDispatches);
    AssertTrue('SkinningPipeline must be compiled', Skinner.SkinningPipeline <> nil);
  finally
    FreeAndNil(Gen);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestGPUDrivenTerrainCDLODRHI;
var
  VkDev: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  Terrain: TCastleVulkanTerrainCDLOD;
  CDLODGLSL: String;
  MorphNear, MorphMid, MorphFar: Single;
  UnmorphedUV, MorphedUV: TVector2;
  NodeIdx: Integer;
  NodeEntry: TCastleTerrainCDLODNode;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify TCastleTerrainCDLODNode (32 bytes) & GLSL functions }
    AssertEquals('TCastleTerrainCDLODNode must be 32 bytes',
      32, SizeOf(TCastleTerrainCDLODNode));

    CDLODGLSL := Gen.GenerateTerrainCDLODFunctions;
    AssertTrue('Terrain CDLOD GLSL must include EvaluateCDLODMorphFactor',
      Pos('float EvaluateCDLODMorphFactor(float cameraDist, float lodNearDist, float lodFarDist, float morphStartRatio)', CDLODGLSL) > 0);
    AssertTrue('Terrain CDLOD GLSL must include MorphCDLODGridVertex',
      Pos('vec2 MorphCDLODGridVertex(vec2 gridUV, float patchResolution, float morphFactor)', CDLODGLSL) > 0);

    { 2. Verify continuous morph factor k in [0..1] and odd-grid-vertex snapping }
    { Range [0..100] with MorphStartRatio=0.70 -> morphing starts at 70m and completes at 100m }
    MorphNear := TCastleVulkanTerrainCDLOD.EvaluateCDLODMorphFactor(50.0, 0.0, 100.0, 0.70);
    MorphMid  := TCastleVulkanTerrainCDLOD.EvaluateCDLODMorphFactor(85.0, 0.0, 100.0, 0.70);
    MorphFar  := TCastleVulkanTerrainCDLOD.EvaluateCDLODMorphFactor(105.0, 0.0, 100.0, 0.70);
    AssertSameValue(0.0, MorphNear, 1e-5);
    AssertSameValue(0.5, MorphMid, 1e-4);
    AssertSameValue(1.0, MorphFar, 1e-5);

    { Odd grid vertex at UV=1/8 on an 8x8 patch must snap to even grid UV=0 when morphFactor=1 }
    UnmorphedUV := TCastleVulkanTerrainCDLOD.MorphCDLODGridVertex(Vector2(0.125, 0.25), 8.0, 0.0);
    MorphedUV   := TCastleVulkanTerrainCDLOD.MorphCDLODGridVertex(Vector2(0.125, 0.25), 8.0, 1.0);
    AssertSameValue(0.125, UnmorphedUV.X, 1e-5);
    AssertSameValue(0.0, MorphedUV.X, 1e-5);
    AssertSameValue(0.25, MorphedUV.Y, 1e-5); { 0.25 = 2/8 is already an even grid vertex }

    { 3. Verify quadtree node management & GPU buffer upload }
    Terrain := VkDev.TerrainCDLOD;
    AssertTrue('TerrainCDLOD must be lazily created by TVulkanRHIDevice', Terrain <> nil);
    NodeIdx := Terrain.AddTerrainNode(-128.0, -128.0, 64.0, 1, -10.0, 45.0);
    AssertEquals('First terrain node index must be 0', 0, NodeIdx);
    AssertEquals('NodeCount must be 1', 1, Terrain.NodeCount);

    NodeEntry := Terrain.GetTerrainNode(0);
    AssertSameValue(64.0, NodeEntry.NodeXZAndScale.Z, 1e-4);
    AssertSameValue(1.0, NodeEntry.NodeXZAndScale.W, 1e-4);

    Terrain.UploadNodes;
    AssertTrue('NodeBuffer must be allocated after UploadNodes', Terrain.NodeBuffer <> nil);
    AssertEquals('TotalNodeUploads must be 1', 1, Terrain.TotalNodeUploads);
  finally
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSubsurfaceScatteringAndFoliageTransmissionPBRRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SSSGLSL: String;
  TerminatorWrap, UnwrappedTerminator, BacklitLeaf, FrontlitLeaf, ThinLeaf, ThickLeaf: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Subsurface Scattering & Foliage Transmission GLSL functions }
    SSSGLSL := Gen.GenerateSubsurfaceAndTransmissionPBRFunctions;
    AssertTrue('SSS GLSL must include EvaluateSubsurfaceWrapDiffuse',
      Pos('vec3 EvaluateSubsurfaceWrapDiffuse(float NdotL, float wrapFactor, vec3 scatterColor)', SSSGLSL) > 0);
    AssertTrue('SSS GLSL must include EvaluateFoliageTransmission',
      Pos('vec3 EvaluateFoliageTransmission(vec3 viewDir, vec3 lightDir, vec3 surfaceNormal,', SSSGLSL) > 0);

    { 2. Verify wrap-diffuse subsurface bleeding across the NdotL = 0 shadow terminator }
    UnwrappedTerminator := TCastleShaderGeneratorRHI.EvaluateSubsurfaceWrapDiffuse(
      0.0, 0.0, Vector3(0.8, 0.1, 0.05));
    TerminatorWrap := TCastleShaderGeneratorRHI.EvaluateSubsurfaceWrapDiffuse(
      0.0, 0.5, Vector3(0.8, 0.1, 0.05));
    AssertSameValue(0.0, UnwrappedTerminator.X, 1e-5);
    AssertTrue('Wrap-diffuse at NdotL=0 with wrapFactor=0.5 must bleed warm red subsurface light',
      TerminatorWrap.X > TerminatorWrap.Z);

    { 3. Verify back-lit foliage transmission (strong when view opposes light, attenuated by thickness) }
    BacklitLeaf := TCastleShaderGeneratorRHI.EvaluateFoliageTransmission(
      Vector3(0.0, 0.0, -1.0), { ViewDir looking along -Z }
      Vector3(0.0, 0.0, 1.0),  { LightDir coming from +Z behind leaf }
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.4, 0.85, 0.2),
      0.2, 0.2, 4.0, 1.0);
    FrontlitLeaf := TCastleShaderGeneratorRHI.EvaluateFoliageTransmission(
      Vector3(0.0, 0.0, 1.0),  { ViewDir looking from same side as light }
      Vector3(0.0, 0.0, 1.0),
      Vector3(0.0, 0.0, 1.0),
      Vector3(0.4, 0.85, 0.2),
      0.2, 0.2, 4.0, 1.0);
    AssertTrue('Back-lit leaf must transmit green light (> 0)', BacklitLeaf.Y > 0.1);
    AssertSameValue(0.0, FrontlitLeaf.Y, 1e-5);

    ThinLeaf := TCastleShaderGeneratorRHI.EvaluateFoliageTransmission(
      Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0),
      Vector3(0.4, 0.85, 0.2), 0.1, 0.0, 4.0, 1.0);
    ThickLeaf := TCastleShaderGeneratorRHI.EvaluateFoliageTransmission(
      Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0),
      Vector3(0.4, 0.85, 0.2), 2.0, 0.0, 4.0, 1.0);
    AssertTrue('Thin leaf (thickness=0.1) must transmit more light than thick leaf (thickness=2.0)',
      ThinLeaf.Y > ThickLeaf.Y);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestClearCoatAndAnisotropicPBRRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  CCGLSL: String;
  CCSpecNormal, CCAttenNormal, CCSpecGrazing, CCAttenGrazing, CCSpecDisabled, CCAttenDisabled: Single;
  DAnisoAlongT, DAnisoAlongB, DIso: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Clear Coat & Anisotropic GGX GLSL generation }
    CCGLSL := Gen.GenerateClearCoatAndAnisotropicPBRFunctions;
    AssertTrue('ClearCoat GLSL must include EvaluateClearCoatBRDF',
      Pos('void EvaluateClearCoatBRDF(float cNdotH, float cNdotL, float cNdotV, float VdotH,', CCGLSL) > 0);
    AssertTrue('ClearCoat GLSL must include EvaluateAnisotropicGGX_D',
      Pos('float EvaluateAnisotropicGGX_D(float NdotH, float TdotH, float BdotH, float roughness, float anisotropy)', CCGLSL) > 0);

    { 2. Verify Clear Coat specular lobe and base-layer attenuation (1.0 - F_cc) }
    TCastleShaderGeneratorRHI.EvaluateClearCoatBRDF(
      1.0, 1.0, 1.0, 1.0, 0.0, 0.1, CCSpecDisabled, CCAttenDisabled);
    AssertSameValue(0.0, CCSpecDisabled, 1e-6);
    AssertSameValue(1.0, CCAttenDisabled, 1e-6);

    TCastleShaderGeneratorRHI.EvaluateClearCoatBRDF(
      1.0, 1.0, 1.0, 1.0, 1.0, 0.1, CCSpecNormal, CCAttenNormal);
    AssertTrue('Active glossy clear coat at NdotH=1 must produce strong specular lobe',
      CCSpecNormal > 1.0);
    { At VdotH=1 (normal incidence), IOR=1.5 has F0 = 0.04 -> base layer attenuation = 0.96 }
    AssertSameValue(0.96, CCAttenNormal, 1e-4);

    TCastleShaderGeneratorRHI.EvaluateClearCoatBRDF(
      0.8, 0.5, 0.2, 0.1, 1.0, 0.2, CCSpecGrazing, CCAttenGrazing);
    AssertTrue('Grazing VdotH=0.1 must increase Schlick Fresnel reflection and attenuate base layer (< 0.5)',
      CCAttenGrazing < 0.5);

    { 3. Verify Anisotropic GGX microfacet distribution D_aniso stretching }
    DIso := TCastleShaderGeneratorRHI.EvaluateAnisotropicGGX_D(0.9, 0.43589, 0.0, 0.3, 0.0);
    DAnisoAlongT := TCastleShaderGeneratorRHI.EvaluateAnisotropicGGX_D(0.9, 0.43589, 0.0, 0.3, 0.7);
    DAnisoAlongB := TCastleShaderGeneratorRHI.EvaluateAnisotropicGGX_D(0.9, 0.0, 0.43589, 0.3, 0.7);
    AssertTrue('Positive anisotropy stretches roughness along T (alphaT > alphaB), broadening highlight along T vs B',
      DAnisoAlongT > DAnisoAlongB);
    AssertTrue('Isotropic GGX D must be positive', DIso > 0.0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestRayleighMieAtmosphereSkyLUTComputeRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  SkyGLSL: String;
  PhaseRForward, PhaseRPerp, PhaseMForward, PhaseMBackward: Single;
  ZenithSky, HorizonSunSky: TVector3;
begin
  AssertEquals('TCastleAtmospherePushConstants must be 64 bytes',
    64, SizeOf(TCastleAtmospherePushConstants));

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify Atmosphere Sky-View LUT compute shader GLSL 450 }
    SkyGLSL := Gen.GenerateAtmosphereSkyComputeShader(8, 8);
    AssertTrue('Atmosphere compute shader must bind writeonly rgba16f u_SkyViewLUT at binding 0',
      Pos('layout(rgba16f, set = 0, binding = 0) uniform writeonly image2D u_SkyViewLUT;', SkyGLSL) > 0);
    AssertTrue('Atmosphere compute shader must include EvaluateRayleighPhase and EvaluateCornetteShanksMiePhase',
      (Pos('float EvaluateRayleighPhase(float cosTheta)', SkyGLSL) > 0) and
      (Pos('float EvaluateCornetteShanksMiePhase(float cosTheta, float g)', SkyGLSL) > 0));

    { 2. Verify Rayleigh and Cornette-Shanks Mie phase functions }
    PhaseRForward := TCastleShaderGeneratorRHI.EvaluateRayleighPhase(1.0);
    PhaseRPerp := TCastleShaderGeneratorRHI.EvaluateRayleighPhase(0.0);
    AssertSameValue(PhaseRPerp * 2.0, PhaseRForward, 1e-5);

    PhaseMForward := TCastleShaderGeneratorRHI.EvaluateCornetteShanksMiePhase(0.98, 0.8);
    PhaseMBackward := TCastleShaderGeneratorRHI.EvaluateCornetteShanksMiePhase(-0.8, 0.8);
    AssertTrue('Cornette-Shanks Mie phase (g=0.8) must strongly favor forward solar scattering',
      PhaseMForward > PhaseMBackward * 20.0);

    { 3. Verify CPU reference sky radiance (zenith blue Rayleigh sky vs bright solar aureole) }
    ZenithSky := Device.AtmosphereRenderer.EvaluateSkyRayRadiance(
      Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.2, 0.98));
    AssertTrue('Zenith clear sky must scatter more short-wavelength blue light than red light (B > R)',
      ZenithSky.Z > ZenithSky.X * 2.0);

    HorizonSunSky := Device.AtmosphereRenderer.EvaluateSkyRayRadiance(
      Vector3(0.0, 0.2, 0.98), Vector3(0.0, 0.2, 0.98));
    AssertTrue('Looking toward the sun must produce brighter Mie aureole radiance than zenith',
      HorizonSunSky.X > ZenithSky.X);

    { 4. Verify Sky-View LUT allocation & compute dispatch }
    CmdList.BeginRecording;
    Device.AtmosphereRenderer.DispatchAtmosphereSky(CmdList, nil, nil, 192, 108);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.AtmosphereRenderer.DispatchCount);
    AssertTrue('SkyViewLUTTexture must be allocated as 192x108 pfRGBA16_Float',
      (Device.AtmosphereRenderer.SkyViewLUTTexture <> nil) and
      (Device.AtmosphereRenderer.SkyViewLUTTexture.Desc.Width = 192) and
      (Device.AtmosphereRenderer.SkyViewLUTTexture.Desc.Height = 108) and
      (Device.AtmosphereRenderer.SkyViewLUTTexture.Desc.Format = pfRGBA16_Float));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestLensFlareAndChromaticAberrationPostProcessRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  FlareGLSL: String;
  RedUV, GreenUV, BlueUV, GhostUV1, GhostUV2: TVector2;
  WeightCenter, WeightEdge: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Lens Flare & Chromatic Aberration GLSL 450 functions }
    FlareGLSL := Gen.GenerateLensFlareAndChromaticAberrationFunctions;
    AssertTrue('Post-process GLSL must include EvaluateChromaticAberrationOffsets',
      Pos('void EvaluateChromaticAberrationOffsets(vec2 uv, float intensity, out vec2 outRedUV, out vec2 outGreenUV, out vec2 outBlueUV)', FlareGLSL) > 0);
    AssertTrue('Post-process GLSL must include EvaluateLensFlareGhostUV',
      Pos('void EvaluateLensFlareGhostUV(vec2 uv, int ghostIndex, float ghostSpacing, out vec2 outGhostUV, out float outRadialWeight)', FlareGLSL) > 0);

    { 2. Verify Chromatic Aberration zero dispersion at screen center and radial R/B split at corners }
    TCastleShaderGeneratorRHI.EvaluateChromaticAberrationOffsets(
      Vector2(0.5, 0.5), 0.02, RedUV, GreenUV, BlueUV);
    AssertSameValue(0.5, RedUV.X, 1e-6);
    AssertSameValue(0.5, BlueUV.X, 1e-6);

    TCastleShaderGeneratorRHI.EvaluateChromaticAberrationOffsets(
      Vector2(0.9, 0.5), 0.02, RedUV, GreenUV, BlueUV);
    AssertTrue('Red UV must shift inward and Blue UV outward at screen periphery',
      (RedUV.X < GreenUV.X) and (BlueUV.X > GreenUV.X));

    { 3. Verify Lens Flare Ghost reflection across screen center and radial window weight }
    TCastleShaderGeneratorRHI.EvaluateLensFlareGhostUV(
      Vector2(0.3, 0.5), 2, 0.5, GhostUV1, WeightCenter);
    { flareAxis = (0.5 - 0.3, 0) = (0.2, 0); step = 2 * 0.5 = 1.0 -> GhostUV1 = (0.5, 0.5) }
    AssertSameValue(0.5, GhostUV1.X, 1e-5);
    AssertSameValue(1.0, WeightCenter, 1e-5);

    TCastleShaderGeneratorRHI.EvaluateLensFlareGhostUV(
      Vector2(0.1, 0.1), 4, 0.6, GhostUV2, WeightEdge);
    AssertTrue('Ghost pushed near/past screen edge must have attenuated radial weight (< WeightCenter)',
      WeightEdge < WeightCenter);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestClothSheenAndIridescencePBRRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SheenGLSL: String;
  CharlieGrazing, CharlieNormal: Single;
  IridNormal, IridGrazing, IridZeroThickness: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Cloth Sheen & Iridescence GLSL 450 functions }
    SheenGLSL := Gen.GenerateClothSheenAndIridescencePBRFunctions;
    AssertTrue('Sheen GLSL must include EvaluateCharlieSheen_D',
      Pos('float EvaluateCharlieSheen_D(float NdotH, float sheenRoughness)', SheenGLSL) > 0);
    AssertTrue('Sheen GLSL must include EvaluateThinFilmIridescence',
      Pos('vec3 EvaluateThinFilmIridescence(float cosTheta1, float iridescenceIOR, float thicknessNanometers)', SheenGLSL) > 0);

    { 2. Verify Estevez-Kulla Charlie microfiber NDF peaks at grazing retroreflection (NdotH -> 0) }
    CharlieGrazing := TCastleShaderGeneratorRHI.EvaluateCharlieSheen_D(0.05, 0.3);
    CharlieNormal := TCastleShaderGeneratorRHI.EvaluateCharlieSheen_D(0.98, 0.3);
    AssertTrue('Charlie cloth sheen NDF must peak at grazing retroreflection (NdotH=0.05 > NdotH=0.98)',
      CharlieGrazing > CharlieNormal * 5.0);

    { 3. Verify Thin-Film Iridescence spectral interference shifts across viewing angle & thickness }
    IridZeroThickness := TCastleShaderGeneratorRHI.EvaluateThinFilmIridescence(1.0, 1.33, 0.0);
    { At 0 nm thickness, phase = pi -> 0.5 + 0.5 * cos(pi) = 0.0 destructive interference }
    AssertSameValue(0.0, IridZeroThickness.X, 1e-5);

    IridNormal := TCastleShaderGeneratorRHI.EvaluateThinFilmIridescence(1.0, 1.5, 380.0);
    IridGrazing := TCastleShaderGeneratorRHI.EvaluateThinFilmIridescence(0.2, 1.5, 380.0);
    AssertTrue('Thin-film iridescence at 380nm must shift RGB spectral reflectance between normal and grazing angles',
      Abs(IridNormal.X - IridGrazing.X) + Abs(IridNormal.Z - IridGrazing.Z) > 0.1);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestComputeGerstnerOceanSimulationAndFoamRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  OceanGLSL: String;
  Disp0, Nrm0, Disp1, Nrm1: TVector3;
  FoamCalm, FoamStorm: Single;
begin
  AssertEquals('TCastleOceanWavePushConstants must be 48 bytes',
    48, SizeOf(TCastleOceanWavePushConstants));

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify Ocean Compute Shader GLSL 450 }
    OceanGLSL := Gen.GenerateOceanDisplacementComputeShader(8, 8);
    AssertTrue('Ocean compute shader must bind writeonly rgba16f u_OceanDisplacementAndFoam at binding 0',
      Pos('layout(rgba16f, set = 0, binding = 0) uniform writeonly image2D u_OceanDisplacementAndFoam;', OceanGLSL) > 0);
    AssertTrue('Ocean compute shader must bind writeonly rgba16f u_OceanNormalAndSlope at binding 1',
      Pos('layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D u_OceanNormalAndSlope;', OceanGLSL) > 0);

    { 2. Verify CPU reference Gerstner wave propagation & Jacobian whitecap crest foam }
    Device.OceanSimulator.BaseAmplitude := 1.5;
    Device.OceanSimulator.BaseWavelength := 20.0;
    Device.OceanSimulator.Choppiness := 0.2;
    Device.OceanSimulator.EvaluateGerstnerWavePoint(Vector2(3.0, 2.0), 0.0, Disp0, Nrm0, FoamCalm);
    Device.OceanSimulator.EvaluateGerstnerWavePoint(Vector2(3.0, 2.0), 1.5, Disp1, Nrm1, FoamStorm);
    AssertTrue('Gerstner ocean wave displacement must evolve over time',
      not TVector3.Equals(Disp0, Disp1));
    AssertTrue('Analytical ocean surface normal must point upward (Y > 0)',
      (Nrm0.Y > 0.0) and (Nrm1.Y > 0.0));

    { High choppiness at wave crest (sin(phase) = 1 -> phase = pi/2) triggers Jacobian folding whitecap foam }
    Device.OceanSimulator.OctaveCount := 1;
    Device.OceanSimulator.Choppiness := 1.0;
    Device.OceanSimulator.FoamThreshold := 0.85;
    Device.OceanSimulator.EvaluateGerstnerWavePoint(Vector2(5.0, 0.0), 0.0, Disp1, Nrm1, FoamStorm);
    AssertTrue('Steep Gerstner crest (phase=pi/2 at x=wavelength/4=5.0) must generate whitecap foam (> 0)',
      FoamStorm > 0.0);

    { 3. Verify GPU ocean textures allocation & compute dispatch }
    CmdList.BeginRecording;
    Device.OceanSimulator.DispatchOceanSimulation(CmdList, nil, nil, 128);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.OceanSimulator.DispatchCount);
    AssertTrue('DisplacementAndFoamTexture and NormalAndSlopeTexture must be 128x128 pfRGBA16_Float',
      (Device.OceanSimulator.DisplacementAndFoamTexture <> nil) and
      (Device.OceanSimulator.NormalAndSlopeTexture <> nil) and
      (Device.OceanSimulator.DisplacementAndFoamTexture.Desc.Width = 128) and
      (Device.OceanSimulator.NormalAndSlopeTexture.Desc.Format = pfRGBA16_Float));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestMotionBlurAndBokehDepthOfFieldPostProcessRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  PostGLSL: String;
  CoCFocus, CoCForeground, CoCBackground: Single;
  WeightCovered, WeightOutsideVelocity, WeightOccludedBg: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Motion Blur & Bokeh DoF GLSL 450 functions }
    PostGLSL := Gen.GenerateMotionBlurAndBokehDoFFunctions;
    AssertTrue('Post GLSL must include EvaluateThinLensCoC',
      Pos('float EvaluateThinLensCoC(float linearDepth, float focusDistance, float focalLength, float apertureFStop, float maxCoCRadius)', PostGLSL) > 0);
    AssertTrue('Post GLSL must include EvaluateMotionBlurSampleWeight',
      Pos('float EvaluateMotionBlurSampleWeight(float sampleOffsetPixels, float sampleVelLenPixels,', PostGLSL) > 0);

    { 2. Verify Signed Thin-Lens Circle of Confusion (0 at focus plane, <0 foreground, >0 background) }
    CoCFocus := TCastleShaderGeneratorRHI.EvaluateThinLensCoC(10.0, 10.0, 0.05, 2.8, 16.0);
    CoCForeground := TCastleShaderGeneratorRHI.EvaluateThinLensCoC(3.0, 10.0, 0.05, 2.8, 16.0);
    CoCBackground := TCastleShaderGeneratorRHI.EvaluateThinLensCoC(50.0, 10.0, 0.05, 2.8, 16.0);
    AssertSameValue(0.0, CoCFocus, 1e-5);
    AssertTrue('Foreground object (z < focusDistance) must produce negative signed CoC',
      CoCForeground < -0.1);
    AssertTrue('Background object (z > focusDistance) must produce positive signed CoC',
      CoCBackground > 0.1);

    { 3. Verify Velocity Motion Blur sample weight & depth occlusion }
    WeightCovered := TCastleShaderGeneratorRHI.EvaluateMotionBlurSampleWeight(2.0, 8.0, 10.0, 10.0, 1.0);
    WeightOutsideVelocity := TCastleShaderGeneratorRHI.EvaluateMotionBlurSampleWeight(10.0, 4.0, 10.0, 10.0, 1.0);
    WeightOccludedBg := TCastleShaderGeneratorRHI.EvaluateMotionBlurSampleWeight(2.0, 8.0, 5.0, 20.0, 1.0);
    AssertTrue('Sample within velocity streak at matching depth must have positive weight',
      WeightCovered > 0.5);
    AssertSameValue(0.0, WeightOutsideVelocity, 1e-5);
    AssertSameValue(0.0, WeightOccludedBg, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestDDGIOctahedralProbeGridRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  DDGIGLSL: String;
  OrigDir, DecodedDir, ProbePos: TVector3;
  OctUV: TVector2;
  WeightUnoccluded, WeightOccluded: Single;
begin
  AssertEquals('TCastleDDGIGridParams must be 48 bytes',
    48, SizeOf(TCastleDDGIGridParams));

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify DDGI GLSL 450 functions }
    DDGIGLSL := Gen.GenerateDDGIProbeSamplingFunctions;
    AssertTrue('DDGI GLSL must include OctahedralEncodeDir and OctahedralDecodeUV',
      (Pos('vec2 OctahedralEncodeDir(vec3 dir)', DDGIGLSL) > 0) and
      (Pos('vec3 OctahedralDecodeUV(vec2 octUV)', DDGIGLSL) > 0));
    AssertTrue('DDGI GLSL must include EvaluateDDGIProbeWeight',
      Pos('float EvaluateDDGIProbeWeight(vec3 worldPos, vec3 surfaceNormal, vec3 probePos,', DDGIGLSL) > 0);

    { 2. Verify Octahedral encode/decode bijective roundtrip in both +Z and -Z hemispheres }
    OrigDir := Vector3(0.35, -0.62, -0.701).Normalize;
    OctUV := TCastleShaderGeneratorRHI.OctahedralEncodeDir(OrigDir);
    DecodedDir := TCastleShaderGeneratorRHI.OctahedralDecodeUV(OctUV);
    AssertSameValue(OrigDir.X, DecodedDir.X, 1e-4);
    AssertSameValue(OrigDir.Y, DecodedDir.Y, 1e-4);
    AssertSameValue(OrigDir.Z, DecodedDir.Z, 1e-4);

    { 3. Verify Chebyshev visibility probe weight suppresses occluded probes behind walls }
    WeightUnoccluded := TCastleShaderGeneratorRHI.EvaluateDDGIProbeWeight(
      Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 3.0, 0.0), 5.0, 0.25);
    WeightOccluded := TCastleShaderGeneratorRHI.EvaluateDDGIProbeWeight(
      Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 3.0, 0.0), 1.0, 0.05);
    AssertTrue('Probe occluded by wall (meanDist=1.0 < dist=3.0) must have strongly reduced Chebyshev weight',
      WeightUnoccluded > WeightOccluded * 20.0);

    { 4. Verify DDGI probe world coordinate calculation & atlas dispatch }
    ProbePos := Device.DDGIGrid.GetProbeWorldPosition(2, 1, 3);
    AssertSameValue(-16.0 + 2 * 4.0, ProbePos.X, 1e-4);
    AssertSameValue(0.0 + 1 * 4.0, ProbePos.Y, 1e-4);
    AssertSameValue(-16.0 + 3 * 4.0, ProbePos.Z, 1e-4);

    CmdList.BeginRecording;
    Device.DDGIGrid.DispatchDDGIUpdate(CmdList, nil, nil);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.DDGIGrid.UpdateCount);
    AssertTrue('DDGI Irradiance (320x80 pfRGBA16_Float) and Visibility (pfRG16_Float) atlases must be allocated',
      (Device.DDGIGrid.IrradianceAtlasTexture <> nil) and
      (Device.DDGIGrid.VisibilityAtlasTexture <> nil) and
      (Device.DDGIGrid.IrradianceAtlasTexture.Desc.Width = 320) and
      (Device.DDGIGrid.IrradianceAtlasTexture.Desc.Height = 80) and
      (Device.DDGIGrid.VisibilityAtlasTexture.Desc.Format = pfRG16_Float));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestContrastAdaptiveSharpeningCASRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  CASGLSL: String;
  Center, Neighbor, SharpenedMid, SaturatedWhite, SaturatedNeighbour, SharpenedSaturated: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify CAS GLSL 450 function }
    CASGLSL := Gen.GenerateCASSharpeningAndUpscaleFunctions;
    AssertTrue('CAS GLSL must include EvaluateCASFilter5Tap',
      Pos('vec3 EvaluateCASFilter5Tap(vec3 center, vec3 north, vec3 south, vec3 east, vec3 west, float sharpness)', CASGLSL) > 0);

    { 2. Verify moderate contrast peak is accentuated by 5-tap CAS filter }
    Center := Vector3(0.6, 0.6, 0.6);
    Neighbor := Vector3(0.4, 0.4, 0.4);
    SharpenedMid := TCastleShaderGeneratorRHI.EvaluateCASFilter5Tap(
      Center, Neighbor, Neighbor, Neighbor, Neighbor, 1.0);
    AssertTrue('CAS 5-tap filter must boost brighter center pixel relative to darker 4-neighbors',
      SharpenedMid.Y > Center.Y);

    { 3. Verify extreme contrast [0..1] suppresses negative lobe to zero (no halo/ringing clamping artifact) }
    SaturatedWhite := Vector3(1.0, 1.0, 1.0);
    SaturatedNeighbour := Vector3(0.0, 0.0, 0.0);
    SharpenedSaturated := TCastleShaderGeneratorRHI.EvaluateCASFilter5Tap(
      SaturatedWhite, SaturatedNeighbour, SaturatedNeighbour, SaturatedNeighbour, SaturatedNeighbour, 1.0);
    AssertSameValue(1.0, SharpenedSaturated.Y, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVirtualShadowMapPageTableAndTilePoolRHI;
var
  Device: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  VSMGLSL: String;
  Tile0X, Tile0Y, Tile0RepeatX, Tile0RepeatY, Tile1X, Tile1Y, OutPageX, OutPageY: Cardinal;
  AtlasUV: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  try
    { 1. Verify VSM Page Table GLSL 450 lookup functions }
    VSMGLSL := Gen.GenerateVSMPageLookupFunctions;
    AssertTrue('VSM GLSL must include DecodeVSMPageEntry and ComputeVSMPhysicalAtlasUV',
      (Pos('void DecodeVSMPageEntry(uint pageEntry, out bool outIsResident, out ivec2 outPhysicalTileCoord)', VSMGLSL) > 0) and
      (Pos('vec2 ComputeVSMPhysicalAtlasUV(vec2 virtualUV, ivec2 physicalTileCoord, float pageTableDim, float physicalTilesPerRow)', VSMGLSL) > 0));

    { 2. Verify on-demand virtual page request and physical tile allocation }
    Device.VirtualShadowMap.ResetPageTable;
    AssertTrue(Device.VirtualShadowMap.RequestAndAllocateVirtualPage(10, 20, Tile0X, Tile0Y));
    AssertTrue(Device.VirtualShadowMap.RequestAndAllocateVirtualPage(10, 20, Tile0RepeatX, Tile0RepeatY));
    AssertTrue(Device.VirtualShadowMap.RequestAndAllocateVirtualPage(15, 25, Tile1X, Tile1Y));

    AssertEquals('First allocated VSM page must receive physical tile (0, 0)', Cardinal(0), Tile0X);
    AssertEquals('First allocated VSM page must receive physical tile (0, 0)', Cardinal(0), Tile0Y);
    AssertEquals('Requesting already-resident VSM page must return same physical tile (0, 0)', Cardinal(0), Tile0RepeatX);
    AssertEquals('Second distinct VSM page must receive physical tile (1, 0)', Cardinal(1), Tile1X);
    AssertEquals('Second distinct VSM page must receive physical tile (1, 0)', Cardinal(0), Tile1Y);
    AssertEquals(Cardinal(2), Device.VirtualShadowMap.AllocatedTileCount);

    { 3. Verify virtual-to-physical atlas UV remapping for tile 1 (TileX=1, TileY=0 in 16x16 pool) }
    AssertTrue(Device.VirtualShadowMap.ComputePhysicalAtlasUV(
      Vector2(15.5 / 64.0, 25.5 / 64.0), OutPageX, OutPageY, AtlasUV));
    AssertEquals(Cardinal(15), OutPageX);
    AssertEquals(Cardinal(25), OutPageY);
    AssertSameValue((1.0 + 0.5) / 16.0, AtlasUV.X, 1e-4);
    AssertSameValue((0.0 + 0.5) / 16.0, AtlasUV.Y, 1e-4);

    { 4. Verify GPU PageTableBuffer upload and 2048x2048 pfR32_Float PhysicalTilePoolTexture creation }
    Device.VirtualShadowMap.UploadPageTable;

    AssertEquals(Cardinal(1), Device.VirtualShadowMap.TotalPageUploads);
    AssertTrue('VSM PageTableBuffer and 2048x2048 PhysicalTilePoolTexture must be allocated',
      (Device.VirtualShadowMap.PageTableBuffer <> nil) and
      (Device.VirtualShadowMap.PhysicalTilePoolTexture <> nil) and
      (Device.VirtualShadowMap.PhysicalTilePoolTexture.Desc.Width = 2048) and
      (Device.VirtualShadowMap.PhysicalTilePoolTexture.Desc.Height = 2048) and
      (Device.VirtualShadowMap.PhysicalTilePoolTexture.Desc.Format = pfR32_Float));
  finally
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSeparableSubsurfaceScatteringBurleyDiffusionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SSSSGLSL: String;
  SkinMFP, ProfileNear, ProfileFar: TVector3;
  WeightCoplanar, WeightEdgeDiscontinuity: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Separable SSSS Burley Diffusion GLSL 450 functions }
    SSSSGLSL := Gen.GenerateSeparableSSSSFunctions;
    AssertTrue('SSSS GLSL must include EvaluateBurleyDiffusionProfile and EvaluateBilateralSSSSWeight',
      (Pos('vec3 EvaluateBurleyDiffusionProfile(float radiusMM, vec3 scatterDistanceRGB)', SSSSGLSL) > 0) and
      (Pos('float EvaluateBilateralSSSSWeight(float sampleOffsetMM, float depthDiffMeters, float scatterDist, float depthFalloffScale)', SSSSGLSL) > 0));

    { 2. Verify Burley normalized diffusion profile with human skin mean-free-path (Red > Green > Blue) }
    SkinMFP := Vector3(3.67, 1.37, 0.68);
    ProfileNear := TCastleShaderGeneratorRHI.EvaluateBurleyDiffusionProfile(0.5, SkinMFP);
    ProfileFar := TCastleShaderGeneratorRHI.EvaluateBurleyDiffusionProfile(8.0, SkinMFP);

    AssertTrue('Diffusion profile must decay monotonically with radial distance r',
      (ProfileNear.X > ProfileFar.X) and (ProfileNear.Y > ProfileFar.Y) and (ProfileNear.Z > ProfileFar.Z));
    AssertTrue('In the far scattering tail (r=8.0mm), red scattering must exceed green and blue due to longer red mean free path',
      (ProfileFar.X > ProfileFar.Y) and (ProfileFar.Y > ProfileFar.Z));

    { 3. Verify bilateral depth weight prevents bleeding across depth silhouettes }
    WeightCoplanar := TCastleShaderGeneratorRHI.EvaluateBilateralSSSSWeight(1.0, 0.0005, 1.5, 100.0);
    WeightEdgeDiscontinuity := TCastleShaderGeneratorRHI.EvaluateBilateralSSSSWeight(1.0, 0.50, 1.5, 100.0);
    AssertTrue('Coplanar skin samples must retain strong bilateral weight while silhouette edges are rejected',
      (WeightCoplanar > WeightEdgeDiscontinuity * 1000.0) and (WeightEdgeDiscontinuity < 1e-5));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestGPUDrivenContinuousLODSelectionRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  LODGLSL: String;
  Thresholds: TVector4;
  Crossfade: Single;
  LOD0, LOD1, LOD2, LOD3, Culled, TotalVisible: Cardinal;
begin
  AssertEquals('TCastleLODInstanceDescriptor must be 48 bytes',
    48, SizeOf(TCastleLODInstanceDescriptor));

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify LOD Selection Compute Shader GLSL 450 }
    LODGLSL := Gen.GenerateLODSelectionComputeShader(64);
    AssertTrue('LOD compute shader must include CastleLODInstanceDescriptor and SelectDiscreteLODLevel',
      (Pos('struct CastleLODInstanceDescriptor {', LODGLSL) > 0) and
      (Pos('int SelectDiscreteLODLevel(float coverage, vec4 thresholds, float band, out float outCrossfade)', LODGLSL) > 0));

    { 2. Verify screen coverage & crossfade transition band }
    Thresholds := Vector4(0.40, 0.20, 0.08, 0.02);
    AssertEquals('Coverage 0.41 within [0.40..0.42] transition band must select LOD 0 with crossfade=0.5',
      0, TCastleShaderGeneratorRHI.SelectDiscreteLODLevel(0.41, Thresholds, Crossfade, 0.02));
    AssertSameValue(0.5, Crossfade, 1e-4);

    { 3. Register 5 instances at increasing distances (R=1.0, CotHalfFovY=1.0 => coverage = 2.0 / dist):
         dist=2.0   -> coverage=1.00  (>= 0.40 -> LOD 0)
         dist=8.0   -> coverage=0.25  (>= 0.20 -> LOD 1)
         dist=20.0  -> coverage=0.10  (>= 0.08 -> LOD 2)
         dist=50.0  -> coverage=0.04  (>= 0.02 -> LOD 3)
         dist=200.0 -> coverage=0.01  (<  0.02 -> Culled -1) }
    Device.LODSelector.ClearInstances;
    Device.LODSelector.AddInstance(Vector3(0.0, 0.0, -2.0),   1.0, Thresholds, 1);
    Device.LODSelector.AddInstance(Vector3(0.0, 0.0, -8.0),   1.0, Thresholds, 1);
    Device.LODSelector.AddInstance(Vector3(0.0, 0.0, -20.0),  1.0, Thresholds, 1);
    Device.LODSelector.AddInstance(Vector3(0.0, 0.0, -50.0),  1.0, Thresholds, 1);
    Device.LODSelector.AddInstance(Vector3(0.0, 0.0, -200.0), 1.0, Thresholds, 1);

    TotalVisible := Device.LODSelector.EvaluateInstanceLODsCPU(
      Vector3(0.0, 0.0, 0.0), 1.0, LOD0, LOD1, LOD2, LOD3, Culled);
    AssertEquals(Cardinal(4), TotalVisible);
    AssertEquals(Cardinal(1), LOD0);
    AssertEquals(Cardinal(1), LOD1);
    AssertEquals(Cardinal(1), LOD2);
    AssertEquals(Cardinal(1), LOD3);
    AssertEquals(Cardinal(1), Culled);

    { 4. Verify GPU SSBO upload and compute dispatch }
    CmdList.BeginRecording;
    Device.LODSelector.DispatchLODSelection(CmdList, Vector3(0.0, 0.0, 0.0), 1.0, nil, nil);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.LODSelector.DispatchCount);
    AssertTrue('LODSelector SSBOs must be allocated',
      (Device.LODSelector.InstanceBuffer <> nil) and
      (Device.LODSelector.SelectedLODBuffer <> nil));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestBentNormalsAndSpecularOcclusionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  BentGLSL: String;
  SOUnoccluded, SOCavityMirror: Single;
  SurfaceN, BentDir, ResultLowAO, ResultFullAO: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Bent Normals & Specular Occlusion GLSL 450 }
    BentGLSL := Gen.GenerateBentNormalsAndSpecularOcclusionFunctions;
    AssertTrue('Bent Normals GLSL must include EvaluateSpecularOcclusion and BendNormalTowardsUnoccludedDir',
      (Pos('float EvaluateSpecularOcclusion(float NdotV, float ambientOcclusion, float roughness)', BentGLSL) > 0) and
      (Pos('vec3 BendNormalTowardsUnoccludedDir(vec3 surfaceNormal, vec3 unoccludedBentDir, float ambientOcclusion)', BentGLSL) > 0));

    { 2. Verify Lagarde/Jimenez Specular Occlusion }
    SOUnoccluded := TCastleShaderGeneratorRHI.EvaluateSpecularOcclusion(0.8, 1.0, 0.1);
    SOCavityMirror := TCastleShaderGeneratorRHI.EvaluateSpecularOcclusion(0.2, 0.25, 0.1);
    AssertSameValue(1.0, SOUnoccluded, 1e-5);
    AssertTrue('Occluded grazing cavity on smooth surface must strongly attenuate specular occlusion',
      SOCavityMirror < 0.25);

    { 3. Verify Bent Normal interpolation }
    SurfaceN := Vector3(0.0, 1.0, 0.0);
    BentDir := Vector3(1.0, 1.0, 0.0).Normalize;
    ResultLowAO := TCastleShaderGeneratorRHI.BendNormalTowardsUnoccludedDir(SurfaceN, BentDir, 0.0);
    ResultFullAO := TCastleShaderGeneratorRHI.BendNormalTowardsUnoccludedDir(SurfaceN, BentDir, 1.0);
    AssertSameValue(BentDir.X, ResultLowAO.X, 1e-4);
    AssertSameValue(SurfaceN.Y, ResultFullAO.Y, 1e-4);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestColorGrading3DLUTAndFilmGrainVignetteRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  LUTGLSL: String;
  CoordBlack, CoordWhite, GrainMid, GrainWhite: TVector3;
  VigCenter, VigCorner: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify 3D Color Grading LUT, Vignette & Film Grain GLSL 450 }
    LUTGLSL := Gen.GenerateColorGradingLUTAndFilmGrainFunctions;
    AssertTrue('Color Grading GLSL must include Compute3DLUTSampleCoord, EvaluateNaturalCos4Vignette, and EvaluateFilmGrainNoise',
      (Pos('vec3 Compute3DLUTSampleCoord(vec3 colorRGB, float lutDimension)', LUTGLSL) > 0) and
      (Pos('float EvaluateNaturalCos4Vignette(vec2 uv, float intensity)', LUTGLSL) > 0) and
      (Pos('vec3 EvaluateFilmGrainNoise(vec3 color, vec2 uv, float timeSeconds, float intensity)', LUTGLSL) > 0));

    { 2. Verify half-texel-centered 3D LUT coordinate mapping for 32x32x32 LUT }
    CoordBlack := TCastleShaderGeneratorRHI.Compute3DLUTSampleCoord(Vector3(0.0, 0.0, 0.0), 32.0);
    CoordWhite := TCastleShaderGeneratorRHI.Compute3DLUTSampleCoord(Vector3(1.0, 1.0, 1.0), 32.0);
    AssertSameValue(0.5 / 32.0, CoordBlack.X, 1e-5);
    AssertSameValue(31.5 / 32.0, CoordWhite.X, 1e-5);

    { 3. Verify natural cos^4(theta) optical vignette falloff }
    VigCenter := TCastleShaderGeneratorRHI.EvaluateNaturalCos4Vignette(Vector2(0.5, 0.5), 1.0);
    VigCorner := TCastleShaderGeneratorRHI.EvaluateNaturalCos4Vignette(Vector2(0.0, 0.0), 1.0);
    AssertSameValue(1.0, VigCenter, 1e-5);
    AssertSameValue(0.444444, VigCorner, 1e-4);

    { 4. Verify luminance-preserving film grain suppresses noise at pure white (luma = 1.0 => response = 0.0) }
    GrainMid := TCastleShaderGeneratorRHI.EvaluateFilmGrainNoise(
      Vector3(0.25, 0.25, 0.25), Vector2(0.37, 0.61), 1.25, 0.1);
    GrainWhite := TCastleShaderGeneratorRHI.EvaluateFilmGrainNoise(
      Vector3(1.0, 1.0, 1.0), Vector2(0.37, 0.61), 1.25, 0.1);
    AssertTrue('Midtone pixel must receive non-zero film grain modulation',
      Abs(GrainMid.X - 0.25) > 1e-4);
    AssertSameValue(1.0, GrainWhite.X, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVolumetricCloudDualLobeHGAndBeerPowderRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  CloudGLSL: String;
  PhaseForward, PhaseSide, PhaseBack: Single;
  BeerOnly, BeerPowderEdge, BeerPowderPeak: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Volumetric Cloud GLSL 450 functions }
    CloudGLSL := Gen.GenerateVolumetricCloudFunctions;
    AssertTrue('Volumetric Cloud GLSL must include EvaluateDualLobeHGPhase and EvaluateBeerPowderTransmittance',
      (Pos('float EvaluateDualLobeHGPhase(float cosTheta, float forwardG, float backwardG, float forwardWeight)', CloudGLSL) > 0) and
      (Pos('float EvaluateBeerPowderTransmittance(float opticalDepth, float powderStrength)', CloudGLSL) > 0));

    { 2. Verify Dual-Lobe Henyey-Greenstein phase has both strong forward silver-lining and backward glory lobe }
    PhaseForward := TCastleShaderGeneratorRHI.EvaluateDualLobeHGPhase(1.0, 0.8, -0.5, 0.7);
    PhaseSide    := TCastleShaderGeneratorRHI.EvaluateDualLobeHGPhase(0.0, 0.8, -0.5, 0.7);
    PhaseBack    := TCastleShaderGeneratorRHI.EvaluateDualLobeHGPhase(-1.0, 0.8, -0.5, 0.7);
    AssertTrue('Forward silver-lining lobe must strongly exceed side-scattering and back-scattering',
      (PhaseForward > PhaseBack * 5.0) and (PhaseBack > PhaseSide * 2.0));

    { 3. Verify Schneider Beer-Powder dark-edge sugar-powder transmittance }
    BeerOnly       := TCastleShaderGeneratorRHI.EvaluateBeerPowderTransmittance(0.1, 0.0);
    BeerPowderEdge := TCastleShaderGeneratorRHI.EvaluateBeerPowderTransmittance(0.1, 1.0);
    BeerPowderPeak := TCastleShaderGeneratorRHI.EvaluateBeerPowderTransmittance(0.5, 1.0);
    AssertSameValue(Exp(-0.1), BeerOnly, 1e-5);
    AssertTrue('Beer-Powder law darkens thin cloud fringes (tau=0.1) compared to mid-density crests (tau=0.5)',
      BeerPowderPeak > BeerPowderEdge);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestGPUTextureStreamingMipFeedbackRHI;
var
  Device: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  StreamGLSL: String;
  Tex0, Tex1: Integer;
  Promoted, Evicted, TotalChanges: Cardinal;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  try
    { 1. Verify Texture Mip Feedback GLSL 450 }
    StreamGLSL := Gen.GenerateTextureMipFeedbackFunctions;
    AssertTrue('Texture Mip Feedback GLSL must include ComputeDesiredMipLevel',
      Pos('uint ComputeDesiredMipLevel(float texelFootprintMaxDeriv, uint maxMipLevel, float mipBias)', StreamGLSL) > 0);

    { 2. Verify ComputeDesiredMipLevel derivative-to-mip calculation }
    AssertEquals(Cardinal(0), TCastleShaderGeneratorRHI.ComputeDesiredMipLevel(1.0, 10));
    AssertEquals(Cardinal(2), TCastleShaderGeneratorRHI.ComputeDesiredMipLevel(4.0, 10));
    AssertEquals(Cardinal(4), TCastleShaderGeneratorRHI.ComputeDesiredMipLevel(16.0, 10));

    { 3. Verify TCastleVulkanTextureStreamer residency promotion and eviction }
    Device.TextureStreamer.ClearTextures;
    Tex0 := Device.TextureStreamer.RegisterStreamableTexture(2048, 2048, 11, 6);
    Tex1 := Device.TextureStreamer.RegisterStreamableTexture(1024, 1024, 10, 4);
    AssertEquals(0, Tex0);
    AssertEquals(1, Tex1);

    Device.TextureStreamer.ResetFrameFeedback;
    { Tex0 is sampled at multiple pixels requesting mips 4 and 1 -> atomicMin keeps mip 1 (finer than resident mip 6 -> promote!)
      Tex1 is not sampled at all ($FF) -> evict 1 mip from 4 to 5! }
    Device.TextureStreamer.RecordMipFeedback(Cardinal(Tex0), 4);
    Device.TextureStreamer.RecordMipFeedback(Cardinal(Tex0), 1);

    TotalChanges := Device.TextureStreamer.ResolveStreamingRequests(Promoted, Evicted);
    AssertEquals(Cardinal(2), TotalChanges);
    AssertEquals(Cardinal(1), Promoted);
    AssertEquals(Cardinal(1), Evicted);
    AssertEquals(Cardinal(1), Device.TextureStreamer.GetResidentMip(Cardinal(Tex0)));
    AssertEquals(Cardinal(5), Device.TextureStreamer.GetResidentMip(Cardinal(Tex1)));

    Device.TextureStreamer.UploadFeedbackBuffer;
    AssertEquals(Cardinal(1), Device.TextureStreamer.UpdateCount);
    AssertTrue('TextureStreamer FeedbackBuffer must be allocated',
      Device.TextureStreamer.FeedbackBuffer <> nil);
  finally
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestEquirectangularToCubemapPanoramaConverterRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  EquiGLSL: String;
  OrigDir, DecodedDir: TVector3;
  EqUV: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Equirectangular-to-Cubemap Compute Shader GLSL 450 }
    EquiGLSL := Gen.GenerateEquirectToCubemapComputeShader(8, 8);
    AssertTrue('Equirect-to-Cubemap GLSL must include DirectionToEquirectangularUV and CubeFaceUVToDirection',
      (Pos('vec2 DirectionToEquirectangularUV(vec3 dir)', EquiGLSL) > 0) and
      (Pos('vec3 CubeFaceUVToDirection(uint faceIdx, vec2 uv)', EquiGLSL) > 0));

    { 2. Verify bijective spherical roundtrip between 3D direction and 2:1 Equirectangular UV }
    OrigDir := Vector3(-0.48, 0.55, 0.6834).Normalize;
    EqUV := TCastleShaderGeneratorRHI.DirectionToEquirectangularUV(OrigDir);
    DecodedDir := TCastleShaderGeneratorRHI.EquirectangularUVToDirection(EqUV);
    AssertSameValue(OrigDir.X, DecodedDir.X, 1e-4);
    AssertSameValue(OrigDir.Y, DecodedDir.Y, 1e-4);
    AssertSameValue(OrigDir.Z, DecodedDir.Z, 1e-4);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestAnalyticAreaLightLTCSolidAngleRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  AreaGLSL: String;
  OmegaNear, OmegaFar, RoughNear, RoughFar: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Area Light LTC GLSL 450 functions }
    AreaGLSL := Gen.GenerateAreaLightLTCFunctions;
    AssertTrue('Area Light GLSL must include EvaluateRectAreaLightSolidAngle and EvaluateLTCFilteredRoughness',
      (Pos('float EvaluateRectAreaLightSolidAngle(vec3 surfacePos, vec3 rectCenter,', AreaGLSL) > 0) and
      (Pos('float EvaluateLTCFilteredRoughness(float baseRoughness, float distToLight, float areaExtentRadius)', AreaGLSL) > 0));

    { 2. Verify exact Lambert/Baum vector irradiance of a 2x2 square (halfWidth=1, halfHeight=1) at distance d=1 vs d=5:
         At d=1, exact contour integral of [-1..1]^2 on z=1 from origin is sqrt(2) * arccos(1/3) = 1.7408395 }
    OmegaNear := TCastleShaderGeneratorRHI.EvaluateRectAreaLightSolidAngle(
      Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 1.0, 1.0);
    OmegaFar := TCastleShaderGeneratorRHI.EvaluateRectAreaLightSolidAngle(
      Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 5.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 1.0, 1.0);
    AssertSameValue(Sqrt(2.0) * ArcCos(1.0 / 3.0), OmegaNear, 1e-4);
    AssertTrue('Area light solid angle must decay with distance', OmegaNear > OmegaFar * 10.0);

    { 3. Verify LTC filtered roughness widens more when close to large area light }
    RoughNear := TCastleShaderGeneratorRHI.EvaluateLTCFilteredRoughness(0.1, 1.0, 2.0);
    RoughFar  := TCastleShaderGeneratorRHI.EvaluateLTCFilteredRoughness(0.1, 50.0, 2.0);
    AssertTrue('Close area light must widen effective specular roughness compared to distant light',
      RoughNear > RoughFar);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestTriplanarAndHeightModulatedBlendingRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  TriGLSL: String;
  TriW: TVector3;
  HeightW: TVector4;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Triplanar & Height Blend GLSL 450 functions }
    TriGLSL := Gen.GenerateTriplanarAndHeightBlendFunctions;
    AssertTrue('Triplanar GLSL must include EvaluateTriplanarBlendWeights and EvaluateHeightModulatedBlendWeights',
      (Pos('vec3 EvaluateTriplanarBlendWeights(vec3 worldNormal, float sharpness)', TriGLSL) > 0) and
      (Pos('vec4 EvaluateHeightModulatedBlendWeights(vec4 layerWeights, vec4 layerHeights, float heightContrast)', TriGLSL) > 0));

    { 2. Verify normalized power-sharpened triplanar weights }
    TriW := TCastleShaderGeneratorRHI.EvaluateTriplanarBlendWeights(Vector3(0.8, 0.5, 0.33166).Normalize, 4.0);
    AssertSameValue(1.0, TriW.X + TriW.Y + TriW.Z, 1e-5);
    AssertTrue('Dominant X normal component must receive largest sharpened triplanar weight',
      (TriW.X > TriW.Y) and (TriW.Y > TriW.Z));

    { 3. Verify height-modulated splat weights allow high-elevation cobble layer #1 to dominate equal vertex weights }
    HeightW := TCastleShaderGeneratorRHI.EvaluateHeightModulatedBlendWeights(
      Vector4(0.5, 0.5, 0.0, 0.0), Vector4(0.1, 0.9, 0.0, 0.0), 0.2);
    AssertSameValue(1.0, HeightW.X + HeightW.Y + HeightW.Z + HeightW.W, 1e-5);
    AssertSameValue(1.0, HeightW.Y, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestGPUShadowCasterLightRayExtrusionCullingRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  CasterGLSL: String;
  ActiveCasters: Cardinal;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify Shadow Caster Extrusion Culling Compute Shader GLSL 450 }
    CasterGLSL := Gen.GenerateShadowCasterExtrusionCullingComputeShader(64);
    AssertTrue('Shadow Caster Culling GLSL must include EvaluateShadowCasterExtrudedSphereIntersectsAABB',
      Pos('bool EvaluateShadowCasterExtrudedSphereIntersectsAABB(vec3 sphereCenter, float sphereRadius,', CasterGLSL) > 0);

    { 2. Register 3 shadow casters with downward directional light ray (0, -1, 0) and receiver frustum [-10,-2,-10]..[10,2,10]:
         #0: Upwind above receiver at (0, 30, 0), radius 2 -> extrudes through receiver -> VISIBLE
         #1: Off to the side at (50, 30, 0), radius 2 -> misses receiver -> CULLED
         #2: Downwind below receiver at (0, -20, 0), radius 2 -> extrudes away from receiver -> CULLED }
    Device.ShadowCasterCuller.ClearCasters;
    Device.ShadowCasterCuller.AddCaster(Vector3(0.0, 30.0, 0.0), 2.0);
    Device.ShadowCasterCuller.AddCaster(Vector3(50.0, 30.0, 0.0), 2.0);
    Device.ShadowCasterCuller.AddCaster(Vector3(0.0, -20.0, 0.0), 2.0);

    ActiveCasters := Device.ShadowCasterCuller.EvaluateActiveShadowCastersCPU(
      Vector3(0.0, -1.0, 0.0), 100.0, Vector3(-10.0, -2.0, -10.0), Vector3(10.0, 2.0, 10.0));
    AssertEquals('Only upwind shadow caster #0 whose light-ray extrusion hits the receiver frustum must survive',
      Cardinal(1), ActiveCasters);

    { 3. Verify GPU SSBO upload and compute dispatch }
    CmdList.BeginRecording;
    Device.ShadowCasterCuller.DispatchShadowCasterCulling(
      CmdList, Vector3(0.0, -1.0, 0.0), 100.0,
      Vector3(-10.0, -2.0, -10.0), Vector3(10.0, 2.0, 10.0), nil, nil);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.ShadowCasterCuller.DispatchCount);
    AssertTrue('ShadowCasterCuller SSBOs must be allocated',
      (Device.ShadowCasterCuller.CasterBuffer <> nil) and
      (Device.ShadowCasterCuller.VisibleCasterBuffer <> nil));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVisibilityBufferPayloadAndBarycentricsRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  VisGLSL: String;
  PayloadNear, PayloadFar: QWord;
  OutDepth: Single;
  OutCluster, OutPrim: Cardinal;
  Bary: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify 64-bit Visibility Buffer & Perspective-Correct Barycentrics GLSL 450 }
    VisGLSL := Gen.GenerateVisibilityBufferFunctions;
    AssertTrue('Visibility Buffer GLSL must include PackVisibilityBufferPayload and EvaluatePerspectiveBarycentrics2D',
      (Pos('uvec2 PackVisibilityBufferPayload(float depth01, uint instanceID, uint primitiveID)', VisGLSL) > 0) and
      (Pos('vec3 EvaluatePerspectiveBarycentrics2D(vec2 pixelNDC, vec2 v0NDC, vec2 v1NDC, vec2 v2NDC, float invW0, float invW1, float invW2)', VisGLSL) > 0));

    { 2. Verify 64-bit Visibility Buffer packing/unpacking roundtrip and uint64 atomicMin depth ordering }
    PayloadNear := TCastleShaderGeneratorRHI.PackVisibilityBufferPayload(0.25, 12345, 59);
    PayloadFar  := TCastleShaderGeneratorRHI.PackVisibilityBufferPayload(0.75, 54321, 12);
    AssertTrue('Nearer NDC depth (0.25) must produce strictly smaller uint64 payload for atomicMin than farther depth (0.75)',
      PayloadNear < PayloadFar);

    TCastleShaderGeneratorRHI.UnpackVisibilityBufferPayload(PayloadNear, OutDepth, OutCluster, OutPrim);
    AssertSameValue(0.25, OutDepth, 1e-5);
    AssertEquals(Cardinal(12345), OutCluster);
    AssertEquals(Cardinal(59), OutPrim);

    { 3. Verify perspective-correct barycentric coordinates sum to 1.0 and weight perspective W }
    Bary := TCastleShaderGeneratorRHI.EvaluatePerspectiveBarycentrics2D(
      Vector2(0.25, 0.25),
      Vector2(0.0, 0.0),
      Vector2(1.0, 0.0),
      Vector2(0.0, 1.0),
      1.0, 1.0, 1.0);
    AssertSameValue(0.5, Bary.X, 1e-4);
    AssertSameValue(0.25, Bary.Y, 1e-4);
    AssertSameValue(0.25, Bary.Z, 1e-4);
    AssertSameValue(1.0, Bary.X + Bary.Y + Bary.Z, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestNaniteClusterDAGCutSelectionRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  DAGGLSL: String;
  CutCount: Cardinal;
begin
  AssertEquals('TCastleClusterDAGNode must be 48 bytes (3 x vec4)', 48, SizeOf(TCastleClusterDAGNode));

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify Cluster DAG Cut Compute Shader GLSL 450 }
    DAGGLSL := Gen.GenerateClusterDAGCutComputeShader(64);
    AssertTrue('Cluster DAG Cut GLSL must include EvaluateClusterProjectedErrorPixels and IsClusterDAGCutNode',
      (Pos('float EvaluateClusterProjectedErrorPixels(vec3 sphereCenter, vec3 cameraPos, float sphereRadius,', DAGGLSL) > 0) and
      (Pos('bool IsClusterDAGCutNode(float selfProjectedErrorPx, float parentProjectedErrorPx, float pixelErrorThreshold)', DAGGLSL) > 0));

    { 2. Register a 3-level Nanite cluster hierarchy at distance 10m (CotHalfFovY=1.0, ViewportHeight=1080, Threshold=1.0px):
         - Root (Level 0): SelfLodError = 0.05 (projected = 3.0px > 1.0px), ParentError = 1000.0 -> TOO COARSE (not selected)
         - Mid  (Level 1): SelfLodError = 0.01 (projected = 0.6px <= 1.0px), ParentError = 0.05 (3.0px > 1.0px) -> SELECTED CUT!
         - Leaf (Level 2): SelfLodError = 0.001 (projected = 0.06px <= 1.0px), ParentError = 0.01 (0.6px <= 1.0px) -> TOO FINE (parent already sufficient) }
    Device.ClusterDAG.ClearNodes;
    Device.ClusterDAG.AddClusterNode(Vector3(0.0, 0.0, -10.0), 1.0, 0.05, 1000.0, 0, 0, 64);
    Device.ClusterDAG.AddClusterNode(Vector3(0.0, 0.0, -10.0), 1.0, 0.01, 0.05, 64, 192, 64);
    Device.ClusterDAG.AddClusterNode(Vector3(0.0, 0.0, -10.0), 1.0, 0.001, 0.01, 128, 384, 64);

    CutCount := Device.ClusterDAG.EvaluateDAGCutCPU(
      Vector3(0.0, 0.0, 0.0), 1.0, 1080.0, 1.0);
    AssertEquals('Exactly 1 cluster node (Mid Level 1) must satisfy the seamless DAG cut criterion',
      Cardinal(1), CutCount);

    { 3. Verify GPU SSBO upload and compute dispatch }
    CmdList.BeginRecording;
    Device.ClusterDAG.DispatchDAGCutSelection(
      CmdList, Vector3(0.0, 0.0, 0.0), 1.0, 1080.0, 1.0, nil, nil);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.ClusterDAG.DispatchCount);
    AssertTrue('ClusterDAG SSBOs must be allocated',
      (Device.ClusterDAG.DAGNodeBuffer <> nil) and
      (Device.ClusterDAG.SelectedCutBuffer <> nil));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSoftwareMicroPolygonComputeRasterizerRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SwGLSL: String;
  MicroValid, LargeTri, BackfaceTri: Boolean;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Software Micro-Polygon Compute Rasterizer GLSL 450 }
    SwGLSL := Gen.GenerateSoftwareMicroRasterComputeShader(64);
    AssertTrue('Software Micro-Rasterizer GLSL must include EvaluateEdgeFunction2D and IsMicroTriangleCandidateForSoftwareRaster',
      (Pos('float EvaluateEdgeFunction2D(vec2 a, vec2 b, vec2 p)', SwGLSL) > 0) and
      (Pos('bool IsMicroTriangleCandidateForSoftwareRaster(vec2 v0, vec2 v1, vec2 v2, float maxBoxPixels)', SwGLSL) > 0));

    { 2. Verify small front-facing micro-triangle (< 8x8 pixels) is accepted for software compute rasterization,
         while large triangles (> 8x8 pixels) and back-facing triangles are rejected }
    MicroValid := TCastleShaderGeneratorRHI.IsMicroTriangleCandidateForSoftwareRaster(
      Vector2(100.2, 100.2), Vector2(103.8, 100.2), Vector2(100.2, 104.5), 8.0);
    LargeTri := TCastleShaderGeneratorRHI.IsMicroTriangleCandidateForSoftwareRaster(
      Vector2(100.0, 100.0), Vector2(160.0, 100.0), Vector2(100.0, 160.0), 8.0);
    BackfaceTri := TCastleShaderGeneratorRHI.IsMicroTriangleCandidateForSoftwareRaster(
      Vector2(100.2, 100.2), Vector2(100.2, 104.5), Vector2(103.8, 100.2), 8.0);

    AssertTrue('Front-facing 3.6x4.3px micro-triangle must be routed to software compute rasterizer', MicroValid);
    AssertFalse('60x60px large triangle must be routed to hardware rasterizer instead of software compute', LargeTri);
    AssertFalse('Back-facing micro-triangle must be culled', BackfaceTri);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestGlobalSDFClipmapSphereTracingRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  SDFGLSL: String;
  DistOutside, DistInside, SmoothD, SoftVis: Single;
  HitDist: Single;
  HitSteps: Cardinal;
  HitOk, MissOk: Boolean;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify Global SDF Trace GLSL 450 functions }
    SDFGLSL := Gen.GenerateGlobalSDFTraceFunctions;
    AssertTrue('Global SDF GLSL must include EvaluateSDFBoxDistance, EvaluateSDFSmoothUnion, and EvaluateSDFSoftShadowCone',
      (Pos('float EvaluateSDFBoxDistance(vec3 samplePos, vec3 boxCenter, vec3 boxHalfExtents)', SDFGLSL) > 0) and
      (Pos('float EvaluateSDFSmoothUnion(float d1, float d2, float k)', SDFGLSL) > 0) and
      (Pos('float EvaluateSDFSoftShadowCone(float currentVisibility, float sdfDistance, float rayDistance, float coneTanHalfAngle)', SDFGLSL) > 0));

    { 2. Verify exact box SDF (outside + inside), polynomial smooth union, and soft cone visibility }
    DistOutside := TCastleShaderGeneratorRHI.EvaluateSDFBoxDistance(
      Vector3(5.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(2.0, 2.0, 2.0));
    DistInside := TCastleShaderGeneratorRHI.EvaluateSDFBoxDistance(
      Vector3(0.5, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(2.0, 2.0, 2.0));
    AssertSameValue(3.0, DistOutside, 1e-5);
    AssertSameValue(-1.5, DistInside, 1e-5);

    SmoothD := TCastleShaderGeneratorRHI.EvaluateSDFSmoothUnion(0.1, 0.1, 0.4);
    AssertTrue('Smooth union at equal distances must blend strictly below min(d1, d2)', SmoothD < 0.1);

    SoftVis := TCastleShaderGeneratorRHI.EvaluateSDFSoftShadowCone(1.0, 0.25, 5.0, 0.1);
    AssertSameValue(0.5, SoftVis, 1e-5);

    { 3. Verify TCastleVulkanGlobalSDF sphere-marching and 3D clipmap volume allocation }
    Device.GlobalSDF.ClearPrimitives;
    Device.GlobalSDF.SmoothBlendRadius := 0.0;
    Device.GlobalSDF.AddBoxPrimitive(Vector3(0.0, 0.0, -10.0), Vector3(2.0, 2.0, 2.0));

    HitOk := Device.GlobalSDF.TraceSphereMarchCPU(
      Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), 50.0, HitDist, HitSteps);
    MissOk := Device.GlobalSDF.TraceSphereMarchCPU(
      Vector3(0.0, 10.0, 0.0), Vector3(0.0, 0.0, -1.0), 50.0, HitDist, HitSteps);
    AssertTrue('Ray aimed at SDF box at Z=-10 (halfExtent=2 -> front face at Z=-8) must hit', HitOk);
    AssertFalse('Ray aimed 10m above SDF box must miss', MissOk);

    CmdList.BeginRecording;
    Device.GlobalSDF.DispatchGlobalSDFBuild(CmdList, 32);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.GlobalSDF.BuildCount);
    AssertTrue('GlobalSDF ClipmapVolumeTexture (3D) must be allocated',
      (Device.GlobalSDF.ClipmapVolumeTexture <> nil) and
      (Device.GlobalSDF.ClipmapVolumeTexture.Desc.Dimension = td3D));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestLumenSurfaceCacheSixAxisCardAtlasRHI;
var
  Device: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  CardGLSL: String;
  FirstSlot0, FirstSlot1: Cardinal;
  OffUV, ScaleUV, HitAtlasUV: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  try
    { 1. Verify Surface Cache Card GLSL 450 functions }
    CardGLSL := Gen.GenerateSurfaceCacheCardFunctions;
    AssertTrue('Surface Cache GLSL must include SelectDominantSurfaceCardAxis and ComputeSurfaceCacheAtlasUV',
      (Pos('uint SelectDominantSurfaceCardAxis(vec3 worldNormal)', CardGLSL) > 0) and
      (Pos('vec2 ComputeSurfaceCacheAtlasUV(vec3 localHitPos, vec3 boxHalfExtents, uint cardAxis,', CardGLSL) > 0));

    { 2. Verify dominant 6-axis card selection (+X=0, -X=1, +Y=2, -Y=3, +Z=4, -Z=5) }
    AssertEquals(Cardinal(0), TCastleShaderGeneratorRHI.SelectDominantSurfaceCardAxis(Vector3( 0.9,  0.2,  0.1)));
    AssertEquals(Cardinal(1), TCastleShaderGeneratorRHI.SelectDominantSurfaceCardAxis(Vector3(-0.9,  0.2,  0.1)));
    AssertEquals(Cardinal(2), TCastleShaderGeneratorRHI.SelectDominantSurfaceCardAxis(Vector3( 0.1,  0.95, 0.1)));
    AssertEquals(Cardinal(3), TCastleShaderGeneratorRHI.SelectDominantSurfaceCardAxis(Vector3( 0.1, -0.95, 0.1)));
    AssertEquals(Cardinal(4), TCastleShaderGeneratorRHI.SelectDominantSurfaceCardAxis(Vector3( 0.1,  0.2,  0.9)));
    AssertEquals(Cardinal(5), TCastleShaderGeneratorRHI.SelectDominantSurfaceCardAxis(Vector3( 0.1,  0.2, -0.9)));

    { 3. Verify TCastleVulkanSurfaceCache 6-axis card slot allocation and atlas UV projection }
    Device.SurfaceCache.ResetCards;
    AssertTrue(Device.SurfaceCache.AllocateSixAxisCards(FirstSlot0));
    AssertTrue(Device.SurfaceCache.AllocateSixAxisCards(FirstSlot1));
    AssertEquals(Cardinal(0), FirstSlot0);
    AssertEquals(Cardinal(6), FirstSlot1);
    AssertEquals(Cardinal(12), Device.SurfaceCache.AllocatedCardCount);

    Device.SurfaceCache.GetCardAtlasOffsetAndScale(0, OffUV, ScaleUV);
    HitAtlasUV := TCastleShaderGeneratorRHI.ComputeSurfaceCacheAtlasUV(
      Vector3(0.0, 0.0, 0.0), Vector3(2.0, 2.0, 2.0), 4, OffUV, ScaleUV);
    AssertSameValue(ScaleUV.X * 0.5, HitAtlasUV.X, 1e-5);
    AssertSameValue(ScaleUV.Y * 0.5, HitAtlasUV.Y, 1e-5);

    Device.SurfaceCache.EnsureAtlasTextures;
    AssertTrue('SurfaceCache Albedo and DirectLighting atlas textures must be allocated',
      (Device.SurfaceCache.AlbedoAtlasTexture <> nil) and
      (Device.SurfaceCache.DirectLightingAtlasTexture <> nil));
  finally
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestScreenSpaceRadianceCacheProbesRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  ProbeGLSL: String;
  WeightCoplanar, WeightStepDiscontinuity, WeightOrthogonalNormal: Single;
  SampleDir: TVector3;
  SamplePdf: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Screen-Space Radiance Cache GLSL 450 functions }
    ProbeGLSL := Gen.GenerateScreenRadianceCacheFunctions;
    AssertTrue('Screen Radiance Cache GLSL must include EvaluateScreenProbeBilateralWeight and CosineWeightedHemisphereSample',
      (Pos('float EvaluateScreenProbeBilateralWeight(vec3 pixelWorldPos, vec3 pixelNormal,', ProbeGLSL) > 0) and
      (Pos('vec3 CosineWeightedHemisphereSample(vec2 xi, out float outPdf)', ProbeGLSL) > 0));

    { 2. Verify bilateral probe weight preserves coplanar neighbors and rejects depth steps & perpendicular corners }
    WeightCoplanar := TCastleShaderGeneratorRHI.EvaluateScreenProbeBilateralWeight(
      Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
      Vector3(2.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 10.0);
    WeightStepDiscontinuity := TCastleShaderGeneratorRHI.EvaluateScreenProbeBilateralWeight(
      Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
      Vector3(1.0, 2.0, 0.0), Vector3(0.0, 1.0, 0.0), 10.0);
    WeightOrthogonalNormal := TCastleShaderGeneratorRHI.EvaluateScreenProbeBilateralWeight(
      Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
      Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), 10.0);

    AssertSameValue(1.0, WeightCoplanar, 1e-5);
    AssertTrue('2m plane height discontinuity must strongly reject probe weight', WeightStepDiscontinuity < 1e-4);
    AssertSameValue(0.0, WeightOrthogonalNormal, 1e-6);

    { 3. Verify CosineWeightedHemisphereSample produces unit direction and exact cos(theta)/pi PDF }
    SampleDir := TCastleShaderGeneratorRHI.CosineWeightedHemisphereSample(Vector2(0.25, 0.36), SamplePdf);
    AssertSameValue(1.0, SampleDir.Length, 1e-5);
    AssertSameValue(0.8, SampleDir.Z, 1e-5);
    AssertSameValue(0.8 / Pi, SamplePdf, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestReSTIRWeightedReservoirSamplingRISRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  ResGLSL: String;
  R: TCastleReSTIRReservoir;
  LumaPDF: Single;
begin
  AssertEquals('TCastleReSTIRReservoir must be 32 bytes (2 x vec4)', 32, SizeOf(TCastleReSTIRReservoir));

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify ReSTIR Reservoir GLSL 450 functions }
    ResGLSL := Gen.GenerateReSTIRReservoirFunctions;
    AssertTrue('ReSTIR GLSL must include UpdateReservoirSample and FinalizeReservoirWeight',
      (Pos('bool UpdateReservoirSample(inout CastleReSTIRReservoir r, int candidateLightID,', ResGLSL) > 0) and
      (Pos('void FinalizeReservoirWeight(inout CastleReSTIRReservoir r, uint maxHistoryM)', ResGLSL) > 0));

    { 2. Verify Rec.709 luminance target PDF p_hat(x) }
    LumaPDF := TCastleShaderGeneratorRHI.EvaluateLuminanceTargetPDF(Vector3(1.0, 1.0, 1.0));
    AssertSameValue(1.0, LumaPDF, 1e-5);

    { 3. Verify Streaming WRS/RIS over 2 candidate lights:
         - Light #10: targetPDF = 2.0, sourcePDF = 0.5 -> wi = 4.0 (first sample, accepted)
         - Light #25: targetPDF = 6.0, sourcePDF = 0.5 -> wi = 12.0 (WeightSum = 16.0, random=0.5 -> 0.5*16 = 8 < 12 -> accepted!)
         - FinalizeReservoirWeight(M=2): W = WeightSum / (TargetPDF * M) = 16.0 / (6.0 * 2.0) = 1.333333 }
    TCastleShaderGeneratorRHI.InitReSTIRReservoir(R);
    AssertEquals(-1, R.SelectedLightID);
    AssertTrue(TCastleShaderGeneratorRHI.UpdateReservoirSample(R, 10, 2.0, 0.5, 0.9));
    AssertEquals(10, R.SelectedLightID);
    AssertTrue(TCastleShaderGeneratorRHI.UpdateReservoirSample(R, 25, 6.0, 0.5, 0.5));
    AssertEquals(25, R.SelectedLightID);
    AssertEquals(Cardinal(2), R.SampleCountM);
    AssertSameValue(16.0, R.WeightSum, 1e-5);

    TCastleShaderGeneratorRHI.FinalizeReservoirWeight(R, 20);
    AssertSameValue(16.0 / 12.0, R.ContributionWeightW, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestReSTIRNeighborSimilarityAndReservoirCombineRHI;
var
  CenterR, NeighborR: TCastleReSTIRReservoir;
  SimValid, SimDepthEdge, SimNormalEdge: Boolean;
begin
  { 1. Verify depth & normal edge-stopping similarity thresholds }
  SimValid := TCastleShaderGeneratorRHI.EvaluateReSTIRNeighborSimilarity(
    10.0, Vector3(0.0, 1.0, 0.0), 10.2, Vector3(0.0, 1.0, 0.0), 0.1, 0.9);
  SimDepthEdge := TCastleShaderGeneratorRHI.EvaluateReSTIRNeighborSimilarity(
    10.0, Vector3(0.0, 1.0, 0.0), 15.0, Vector3(0.0, 1.0, 0.0), 0.1, 0.9);
  SimNormalEdge := TCastleShaderGeneratorRHI.EvaluateReSTIRNeighborSimilarity(
    10.0, Vector3(0.0, 1.0, 0.0), 10.0, Vector3(1.0, 0.0, 0.0), 0.1, 0.9);

  AssertTrue('Coplanar neighbor must pass ReSTIR similarity check', SimValid);
  AssertFalse('50% depth discontinuity must be rejected', SimDepthEdge);
  AssertFalse('90-degree normal corner must be rejected', SimNormalEdge);

  { 2. Verify CombineReservoirs with history M-capping (neighbor M=100 capped to MaxHistoryM=20) }
  TCastleShaderGeneratorRHI.InitReSTIRReservoir(CenterR);
  TCastleShaderGeneratorRHI.UpdateReservoirSample(CenterR, 5, 4.0, 1.0, 0.1);
  TCastleShaderGeneratorRHI.FinalizeReservoirWeight(CenterR, 20);

  TCastleShaderGeneratorRHI.InitReSTIRReservoir(NeighborR);
  NeighborR.SelectedLightID := 42;
  NeighborR.TargetPDF := 8.0;
  NeighborR.SampleCountM := 100; // Exceeds MaxHistoryM=20 -> must be capped to 20 during combination
  NeighborR.ContributionWeightW := 1.5;

  AssertTrue(TCastleShaderGeneratorRHI.CombineReservoirs(CenterR, NeighborR, 8.0, 20, 0.1));
  AssertEquals('Combined reservoir must select strong neighbor light #42', 42, CenterR.SelectedLightID);
  AssertEquals('Combined SampleCountM must equal 1 + capped(20) = 21', Cardinal(21), CenterR.SampleCountM);
  AssertTrue('Combined ContributionWeightW must be positive', CenterR.ContributionWeightW > 0.0);
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanReSTIRSpatioTemporalManagerRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  CSGLSL: String;
  OldCurr, OldHist: TVulkanRHIBuffer;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify ReSTIR Spatio-Temporal Compute Shader GLSL 450 }
    CSGLSL := Gen.GenerateReSTIRSpatialTemporalComputeShader(8, 8);
    AssertTrue('ReSTIR Spatio-Temporal CS must include CombineReservoirs and CastleCurrentReservoirBlock',
      (Pos('bool CombineReservoirs(inout CastleReSTIRReservoir dst,', CSGLSL) > 0) and
      (Pos('CastleCurrentReservoirBlock', CSGLSL) > 0));

    { 2. Verify TCastleVulkanReSTIR ping-pong buffer allocation, history swap, and compute dispatch }
    CmdList.BeginRecording;
    Device.ReSTIR.DispatchSpatioTemporalResampling(CmdList, 64, 64, nil, nil);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.ReSTIR.DispatchCount);
    AssertTrue('ReSTIR Current and TemporalHistory SSBOs must be allocated',
      (Device.ReSTIR.CurrentReservoirBuffer <> nil) and
      (Device.ReSTIR.TemporalHistoryReservoirBuffer <> nil));

    OldCurr := Device.ReSTIR.CurrentReservoirBuffer;
    OldHist := Device.ReSTIR.TemporalHistoryReservoirBuffer;
    Device.ReSTIR.SwapReservoirHistory;
    AssertTrue('SwapReservoirHistory must exchange Current and TemporalHistory SSBO pointers',
      (Device.ReSTIR.CurrentReservoirBuffer = OldHist) and
      (Device.ReSTIR.TemporalHistoryReservoirBuffer = OldCurr));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestTSRLanczos2AndBlackmanHarrisKernelsRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  TSRGLSL: String;
  L0, LHalf, L1, L15, L25: Single;
  BH0, BHHalf, BH1: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify TSR Upscale Compute Shader GLSL 450 }
    TSRGLSL := Gen.GenerateTSRUpscaleComputeShader(8, 8);
    AssertTrue('TSR GLSL must include EvaluateLanczos2Weight and EvaluateBlackmanHarrisWeight',
      (Pos('float EvaluateLanczos2Weight(float x)', TSRGLSL) > 0) and
      (Pos('float EvaluateBlackmanHarrisWeight(float x, float radius)', TSRGLSL) > 0));

    { 2. Verify Lanczos-2 kernel properties: L(0)=1, L(0.5)>0, L(1)=0, L(1.5)<0 (sharpening lobe), L(2.5)=0 }
    L0    := TCastleShaderGeneratorRHI.EvaluateLanczos2Weight(0.0);
    LHalf := TCastleShaderGeneratorRHI.EvaluateLanczos2Weight(0.5);
    L1    := TCastleShaderGeneratorRHI.EvaluateLanczos2Weight(1.0);
    L15   := TCastleShaderGeneratorRHI.EvaluateLanczos2Weight(1.5);
    L25   := TCastleShaderGeneratorRHI.EvaluateLanczos2Weight(2.5);

    AssertSameValue(1.0, L0, 1e-5);
    AssertTrue('Lanczos-2 main lobe at x=0.5 must be positive', LHalf > 0.5);
    AssertSameValue(0.0, L1, 1e-5);
    AssertTrue('Lanczos-2 second lobe at x=1.5 must be negative (sharpening ringed lobe)', L15 < -0.05);
    AssertSameValue(0.0, L25, 1e-6);

    { 3. Verify 4-term Blackman-Harris window: BH(0)=1, BH(0.5) in (0,1), BH(1.0)=0 }
    BH0    := TCastleShaderGeneratorRHI.EvaluateBlackmanHarrisWeight(0.0, 1.0);
    BHHalf := TCastleShaderGeneratorRHI.EvaluateBlackmanHarrisWeight(0.5, 1.0);
    BH1    := TCastleShaderGeneratorRHI.EvaluateBlackmanHarrisWeight(1.0, 1.0);

    AssertSameValue(1.0, BH0, 1e-4);
    AssertTrue('Blackman-Harris window at x=0.5 must smoothly decay between 0 and 1',
      (BHHalf > 0.05) and (BHHalf < 0.5));
    AssertSameValue(0.0, BH1, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestTSRDisocclusionAndThinGeometryAntiGhostingRHI;
var
  ConfMatched, ConfHalf, ConfDisoccluded: Single;
  BlendFlat, BlendThinWire: Single;
begin
  { 1. Verify Parallax Disocclusion Confidence }
  ConfMatched     := TCastleShaderGeneratorRHI.EvaluateTSRDisocclusionConfidence(10.0, 10.0, 0.05);
  ConfHalf        := TCastleShaderGeneratorRHI.EvaluateTSRDisocclusionConfidence(10.0, 10.25, 0.05);
  ConfDisoccluded := TCastleShaderGeneratorRHI.EvaluateTSRDisocclusionConfidence(10.0, 15.0, 0.05);

  AssertSameValue(1.0, ConfMatched, 1e-5);
  AssertSameValue(0.5, ConfHalf, 1e-4);
  AssertSameValue(0.0, ConfDisoccluded, 1e-5);

  { 2. Verify Thin-Feature Responsiveness Boost (sub-pixel wires/foliage/hair) }
  BlendFlat     := TCastleShaderGeneratorRHI.EvaluateTSRThinGeometryBlend(0.05, 0.0, 0.0);
  BlendThinWire := TCastleShaderGeneratorRHI.EvaluateTSRThinGeometryBlend(0.05, 0.5, 0.8);

  AssertSameValue(0.05, BlendFlat, 1e-5);
  AssertTrue('Sub-pixel thin wire with high depth Laplacian and luma contrast must boost current-frame blend to prevent ghosting',
    BlendThinWire > 0.7);
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanTSRUpscalerHistoryManagerRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  InW, InH: Cardinal;
  OldUpscaled, OldHistory: TVulkanRHITexture;
begin
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify 67% Quality render scale maps 1920x1080 display to 1280x720 internal render resolution }
    Device.TSRUpscaler.RenderScale := 2.0 / 3.0;
    Device.TSRUpscaler.ComputeInputResolution(1920, 1080, InW, InH);
    AssertEquals(Cardinal(1280), InW);
    AssertEquals(Cardinal(720), InH);

    { 2. Verify full-resolution Upscaled and History texture allocation, compute dispatch, and ping-pong swap }
    CmdList.BeginRecording;
    Device.TSRUpscaler.DispatchTSRUpscale(CmdList, 1920, 1080, nil, nil);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.TSRUpscaler.DispatchCount);
    AssertTrue('TSRUpscaler Upscaled and History textures must be allocated at full 1920x1080 output resolution',
      (Device.TSRUpscaler.UpscaledColorTexture <> nil) and
      (Device.TSRUpscaler.HistoryColorTexture <> nil) and
      (Device.TSRUpscaler.UpscaledColorTexture.Desc.Width = 1920) and
      (Device.TSRUpscaler.UpscaledColorTexture.Desc.Height = 1080));

    OldUpscaled := Device.TSRUpscaler.UpscaledColorTexture;
    OldHistory := Device.TSRUpscaler.HistoryColorTexture;
    Device.TSRUpscaler.SwapHistoryTargets;
    AssertTrue('SwapHistoryTargets must exchange UpscaledColorTexture and HistoryColorTexture',
      (Device.TSRUpscaler.UpscaledColorTexture = OldHistory) and
      (Device.TSRUpscaler.HistoryColorTexture = OldUpscaled));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSubstrateLayeredMaterialSlabsRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SlabGLSL: String;
  ENormal, EGrazing: Single;
  CompClear, CompTintedAmber: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Substrate Layered Material GLSL 450 functions }
    SlabGLSL := Gen.GenerateSubstrateLayeredMaterialFunctions;
    AssertTrue('Substrate GLSL must include EvaluateDirectionalSlabAlbedo and EvaluateLayeredSlabComposition',
      (Pos('float EvaluateDirectionalSlabAlbedo(float f0, float nDotV, float roughness)', SlabGLSL) > 0) and
      (Pos('vec3 EvaluateLayeredSlabComposition(vec3 topLobeRadiance, vec3 bottomLobeRadiance,', SlabGLSL) > 0));

    { 2. Verify directional slab albedo increases toward grazing angles }
    ENormal  := TCastleShaderGeneratorRHI.EvaluateDirectionalSlabAlbedo(0.04, 1.0, 0.1);
    EGrazing := TCastleShaderGeneratorRHI.EvaluateDirectionalSlabAlbedo(0.04, 0.05, 0.1);
    AssertSameValue(0.04, ENormal, 1e-5);
    AssertTrue('Grazing directional slab albedo must strongly exceed normal incidence', EGrazing > 0.6);

    { 3. Verify vertical slab composition conserves energy ((1-Eo)*(1-Ei) < 1) and applies Beer-Lambert medium tinting }
    CompClear := TCastleShaderGeneratorRHI.EvaluateLayeredSlabComposition(
      Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0), Vector3(0.0, 0.0, 0.0),
      0.04, 0.1, 1.0, 1.0, 1.0);
    CompTintedAmber := TCastleShaderGeneratorRHI.EvaluateLayeredSlabComposition(
      Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0), Vector3(0.05, 0.5, 2.0),
      0.04, 0.1, 1.0, 1.0, 1.0);

    AssertSameValue(Sqr(1.0 - 0.04), CompClear.X, 1e-5);
    AssertTrue('Amber absorbing top medium must attenuate blue far more than red',
      (CompTintedAmber.X > CompTintedAmber.Y) and (CompTintedAmber.Y > CompTintedAmber.Z));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestMarschnerDualSpecularHairBSDFRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  HairGLSL: String;
  MPeak, MOffPeak: Single;
  HairBlonde, HairDarkBrown: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Marschner Hair BSDF GLSL 450 functions }
    HairGLSL := Gen.GenerateHairMarschnerBSDF;
    AssertTrue('Marschner Hair GLSL must include EvaluateMarschnerLongitudinalM and EvaluateHairDualSpecularBSDF',
      (Pos('float EvaluateMarschnerLongitudinalM(float sinThetaI, float sinThetaO,', HairGLSL) > 0) and
      (Pos('vec3 EvaluateHairDualSpecularBSDF(vec3 hairAbsorptionSigmaA, float sinThetaI, float sinThetaO,', HairGLSL) > 0));

    { 2. Verify longitudinal Gaussian lobe M peaks when half-angle matches cuticle shift }
    MPeak    := TCastleShaderGeneratorRHI.EvaluateMarschnerLongitudinalM(Sin(0.1), Sin(0.1), 0.1, 0.1);
    MOffPeak := TCastleShaderGeneratorRHI.EvaluateMarschnerLongitudinalM(Sin(0.1), Sin(0.1), -0.3, 0.1);
    AssertTrue('Longitudinal hair lobe M must peak at cuticle shift angle', MPeak > MOffPeak * 10.0);

    { 3. Verify dual-specular R + TT + TRT scattering reflects brighter warm/blonde tones at low eumelanin absorption }
    HairBlonde := TCastleShaderGeneratorRHI.EvaluateHairDualSpecularBSDF(
      Vector3(0.06, 0.18, 0.45), 0.2, 0.2, -0.8, 0.05, 0.12);
    HairDarkBrown := TCastleShaderGeneratorRHI.EvaluateHairDualSpecularBSDF(
      Vector3(1.5, 2.2, 3.5), 0.2, 0.2, -0.8, 0.05, 0.12);

    AssertTrue('Blonde hair internal TT+TRT scattering must be significantly brighter and warmer than dark brown hair',
      (HairBlonde.X > HairDarkBrown.X * 2.0) and (HairBlonde.X > HairBlonde.Z));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestStochasticDiscreteMicrofacetGlintsRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  GlintGLSL: String;
  NDFNoFlake, NDFAlignedFlake: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Stochastic Glint GLSL 450 functions }
    GlintGLSL := Gen.GenerateStochasticGlintFunctions;
    AssertTrue('Stochastic Glint GLSL must include EvaluateStochasticGlintNDF',
      Pos('float EvaluateStochasticGlintNDF(float nDotH, float macroRoughness,', GlintGLSL) > 0);

    { 2. Verify aligned discrete micro-flake produces intense sparkle amplification over macro GGX baseline }
    NDFNoFlake      := TCastleShaderGeneratorRHI.EvaluateStochasticGlintNDF(0.95, 0.35, 0.0, 0.05, 32.0);
    NDFAlignedFlake := TCastleShaderGeneratorRHI.EvaluateStochasticGlintNDF(0.95, 0.35, 1.0, 0.05, 32.0);
    AssertTrue('Aligned discrete micro-flake must amplify specular glint NDF by > 10x',
      NDFAlignedFlake > NDFNoFlake * 10.0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVariableRateShadingTileClassifierRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  VRSGLSL: String;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify VRS Contrast Compute Shader GLSL 450 }
    VRSGLSL := Gen.GenerateVRSContrastComputeShader;
    AssertTrue('VRS Compute GLSL must include SelectOptimalShadingRateTile',
      Pos('uint SelectOptimalShadingRateTile(float lumaContrastX, float lumaContrastY,', VRSGLSL) > 0);

    { 2. Verify VRS tile rate bitmask encoding (0=1x1, 1=2x1, 4=1x2, 5=2x2, 10=4x4) }
    AssertEquals('High contrast in both X and Y must select 1x1 full rate (0)',
      0, Integer(TCastleShaderGeneratorRHI.SelectOptimalShadingRateTile(0.25, 0.25, 0.0, 0.15, 0.04)));
    AssertEquals('Low horizontal contrast + mid-high vertical contrast must select 2x1 rate (1)',
      1, Integer(TCastleShaderGeneratorRHI.SelectOptimalShadingRateTile(0.02, 0.10, 0.0, 0.15, 0.04)));
    AssertEquals('Mid-high horizontal contrast + low vertical contrast must select 1x2 rate (4)',
      4, Integer(TCastleShaderGeneratorRHI.SelectOptimalShadingRateTile(0.10, 0.02, 0.0, 0.15, 0.04)));
    AssertEquals('Moderate contrast below low threshold must select 2x2 rate (5)',
      5, Integer(TCastleShaderGeneratorRHI.SelectOptimalShadingRateTile(0.02, 0.02, 1.0, 0.15, 0.04)));
    AssertEquals('Ultra-flat luminance + high motion velocity must select 4x4 rate (10)',
      10, Integer(TCastleShaderGeneratorRHI.SelectOptimalShadingRateTile(0.005, 0.005, 10.0, 0.15, 0.04)));
  finally
    FreeAndNil(Gen);
  end;

  { 3. Verify TCastleVulkanVRSManager tile grid allocation and dispatch }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6667)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    CmdList.BeginRecording;
    Device.VRSManager.DispatchVRSImageGeneration(CmdList, 1920, 1080, nil, nil);
    CmdList.EndRecording;

    AssertEquals('1920 / 16 = 120 VRS tiles wide', 120, Integer(Device.VRSManager.TileGridWidth));
    AssertEquals('ceil(1080 / 16) = 68 VRS tiles tall', 68, Integer(Device.VRSManager.TileGridHeight));
    AssertTrue('ShadingRateImage must be allocated', Device.VRSManager.ShadingRateImage <> nil);
    AssertEquals('DispatchCount must be 1', 1, Integer(Device.VRSManager.DispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestRuntimeVirtualTexturePageTableAndAtlasRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  RVTGLSL: String;
  PhysUVCenter: TVector2;
  Device: TVulkanRHIDevice;
  TileX0, TileY0, TileX0Repeat, TileY0Repeat, TileX1, TileY1: Cardinal;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify RVT Page Table GLSL 450 functions }
    RVTGLSL := Gen.GenerateRVTLookupFunctions;
    AssertTrue('RVT GLSL must include TranslateRVTPageToPhysicalUV',
      Pos('vec2 TranslateRVTPageToPhysicalUV(vec2 inPageUV, uint physicalTileX, uint physicalTileY,', RVTGLSL) > 0);

    { 2. Verify virtual-to-physical UV translation with 4-texel border gutter }
    PhysUVCenter := TCastleShaderGeneratorRHI.TranslateRVTPageToPhysicalUV(
      Vector2(0.5, 0.5), 0, 0, 16, 4.0 / 128.0);
    { At tile (0,0) in 16x16 grid, center of tile (0.5,0.5) maps to 0.5 / 16 = 0.03125 }
    AssertSameValue(0.5 / 16.0, PhysUVCenter.X, 1e-5);
    AssertSameValue(0.5 / 16.0, PhysUVCenter.Y, 1e-5);
  finally
    FreeAndNil(Gen);
  end;

  { 3. Verify TCastleVulkanRuntimeVirtualTexture on-demand page allocation and physical material cache }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6668)) );
  try
    Device.RuntimeVirtualTexture.EnsurePhysicalAtlasTextures;
    AssertTrue('PhysicalAlbedoAtlas must be allocated', Device.RuntimeVirtualTexture.PhysicalAlbedoAtlas <> nil);
    AssertTrue('PhysicalNormalRoughnessAtlas must be allocated', Device.RuntimeVirtualTexture.PhysicalNormalRoughnessAtlas <> nil);

    AssertTrue('First RVT page request must succeed',
      Device.RuntimeVirtualTexture.RequestRVTPage(10, 20, TileX0, TileY0));
    AssertTrue('Repeated RVT page request for (10,20) must hit cache',
      Device.RuntimeVirtualTexture.RequestRVTPage(10, 20, TileX0Repeat, TileY0Repeat));
    AssertTrue('Distinct RVT page (11,20) must succeed',
      Device.RuntimeVirtualTexture.RequestRVTPage(11, 20, TileX1, TileY1));

    AssertEquals('First RVT page request must allocate physical tile (0,0)', 0, Integer(TileX0));
    AssertEquals('First RVT page request must allocate physical tile (0,0)', 0, Integer(TileY0));
    AssertEquals('Repeated RVT page request for (10,20) must return cached tile X=0', 0, Integer(TileX0Repeat));
    AssertEquals('Repeated RVT page request for (10,20) must return cached tile Y=0', 0, Integer(TileY0Repeat));
    AssertEquals('Distinct RVT page (11,20) must allocate physical tile X=1', 1, Integer(TileX1));
    AssertEquals('Distinct RVT page (11,20) must allocate physical tile Y=0', 0, Integer(TileY1));
    AssertEquals('AllocatedTileCount must be 2', 2, Integer(Device.RuntimeVirtualTexture.AllocatedTileCount));
  finally
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSingleLayerWaterAbsorptionRefractionAndCausticsRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  WaterGLSL: String;
  Transmittance: TVector3;
  RefractZeroDepth, RefractDeep: TVector2;
  CausticsZero, CausticsShallow: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Single-Layer Water GLSL 450 functions }
    WaterGLSL := Gen.GenerateSingleLayerWaterFunctions;
    AssertTrue('Single-Layer Water GLSL must include Beer-Lambert absorption, Snell refraction, and caustics',
      (Pos('vec3 EvaluateWaterBeerLambertAbsorption(vec3 absorptionCoeffRGB, float opticalDepthMeters)', WaterGLSL) > 0) and
      (Pos('vec2 ComputeWaterRefractionUVOffset(vec3 viewSpaceNormal, float waterDepthMeters,', WaterGLSL) > 0) and
      (Pos('float EvaluateWaterCausticsPattern(vec2 worldXZ, float timeSeconds, float waterDepthMeters)', WaterGLSL) > 0));

    { 2. Verify spectral Beer-Lambert absorption attenuates Red much faster than Green/Blue in natural water }
    Transmittance := TCastleShaderGeneratorRHI.EvaluateWaterBeerLambertAbsorption(
      Vector3(0.45, 0.08, 0.03), 3.0);
    AssertTrue('Deep water transmittance must preserve Blue > Green > Red',
      (Transmittance.Z > Transmittance.Y) and (Transmittance.Y > Transmittance.X));

    { 3. Verify shoreline fade suppresses refraction offset at zero depth and scales at deep water }
    RefractZeroDepth := TCastleShaderGeneratorRHI.ComputeWaterRefractionUVOffset(
      Vector3(0.5, -0.25, 0.8), 0.0, 0.75, 0.1);
    RefractDeep := TCastleShaderGeneratorRHI.ComputeWaterRefractionUVOffset(
      Vector3(0.5, -0.25, 0.8), 4.0, 0.75, 0.1);
    AssertSameValue(0.0, RefractZeroDepth.X, 1e-6);
    AssertTrue('Deep water must produce non-zero Snell screen-space refraction offset',
      Abs(RefractDeep.X) > 0.005);

    { 4. Verify underwater caustics vanish at zero depth and illuminate shallow seabed }
    CausticsZero    := TCastleShaderGeneratorRHI.EvaluateWaterCausticsPattern(Vector2(1.2, 3.4), 1.0, 0.0);
    CausticsShallow := TCastleShaderGeneratorRHI.EvaluateWaterCausticsPattern(Vector2(0.0, 0.0), 0.0, 1.5);
    AssertSameValue(0.0, CausticsZero, 1e-6);
    AssertTrue('Shallow water seabed must receive positive photon caustics', CausticsShallow > 0.01);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSparseVolumeBrickAtlasAndBlackbodyEmissionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  VolGLSL: String;
  ColdRGB, RedHotRGB, WhiteHotRGB: TVector3;
  Device: TVulkanRHIDevice;
  Brick0, Brick0Repeat, Brick1: Cardinal;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Planckian Blackbody GLSL 450 functions }
    VolGLSL := Gen.GenerateSparseVolumeBlackbodyFunctions;
    AssertTrue('Sparse Volume Blackbody GLSL must include EvaluateBlackbodyEmissionRGB',
      Pos('vec3 EvaluateBlackbodyEmissionRGB(float temperatureKelvin, float intensity)', VolGLSL) > 0);

    { 2. Verify Planckian blackbody progression from cold (<500K) -> red/orange (1200K) -> white-hot (6000K) }
    ColdRGB     := TCastleShaderGeneratorRHI.EvaluateBlackbodyEmissionRGB(300.0, 1.0);
    RedHotRGB   := TCastleShaderGeneratorRHI.EvaluateBlackbodyEmissionRGB(1200.0, 1.0);
    WhiteHotRGB := TCastleShaderGeneratorRHI.EvaluateBlackbodyEmissionRGB(6000.0, 1.0);
    AssertSameValue(0.0, ColdRGB.Length, 1e-6);
    AssertTrue('1200K fire emission must be dominated by red over blue',
      (RedHotRGB.X > 0.25) and (RedHotRGB.X > RedHotRGB.Z * 2.0));
    AssertTrue('6000K white-hot core must saturate R, G, and B channels',
      (WhiteHotRGB.X > 0.9) and (WhiteHotRGB.Y > 0.9) and (WhiteHotRGB.Z > 0.5));
  finally
    FreeAndNil(Gen);
  end;

  { 3. Verify TCastleVulkanSparseVolumeAtlas 3D brick allocation and 3D rgba16f texture pool }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6669)) );
  try
    Device.SparseVolumeAtlas.EnsureVolumeAtlasTextures;
    AssertTrue('PhysicalBrickAtlasTexture must be allocated as a 3D 64x64x64 rgba16f texture',
      (Device.SparseVolumeAtlas.PhysicalBrickAtlasTexture <> nil) and
      (Device.SparseVolumeAtlas.PhysicalBrickAtlasTexture.Desc.Dimension = td3D) and
      (Device.SparseVolumeAtlas.PhysicalBrickAtlasTexture.Desc.Width = 64));

    AssertTrue(Device.SparseVolumeAtlas.AllocateVolumeBrick(2, 3, 4, Brick0));
    AssertTrue(Device.SparseVolumeAtlas.AllocateVolumeBrick(2, 3, 4, Brick0Repeat));
    AssertTrue(Device.SparseVolumeAtlas.AllocateVolumeBrick(5, 3, 4, Brick1));

    AssertEquals('First sparse volume brick must receive index 0', 0, Integer(Brick0));
    AssertEquals('Repeated allocation of brick (2,3,4) must return index 0', 0, Integer(Brick0Repeat));
    AssertEquals('Second distinct sparse volume brick must receive index 1', 1, Integer(Brick1));
    AssertEquals('AllocatedBrickCount must be 2', 2, Integer(Device.SparseVolumeAtlas.AllocatedBrickCount));
  finally
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestGPUBreadcrumbCrashTrackerDiagnosticsRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  MarkerShadow, MarkerGI: Cardinal;
  CrashReport: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($666A)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    Device.BreadcrumbTracker.ResetBreadcrumbs;
    CmdList.BeginRecording;

    { ShadowMapPass completes normally; LumenTracePass remains active (simulating a GPU hang/TDR inside LumenTracePass) }
    MarkerShadow := Device.BreadcrumbTracker.BeginBreadcrumbScope(CmdList, 'ShadowMapPass');
    Device.BreadcrumbTracker.EndBreadcrumbScope(CmdList, MarkerShadow);

    MarkerGI := Device.BreadcrumbTracker.BeginBreadcrumbScope(CmdList, 'LumenScreenProbeTracePass');
    AssertEquals('Second breadcrumb marker ID must be 2', 2, Integer(MarkerGI));

    CmdList.EndRecording;

    AssertTrue('BreadcrumbBuffer must be allocated', Device.BreadcrumbTracker.BreadcrumbBuffer <> nil);
    AssertEquals('TotalScopesRecorded must be 2', 2, Integer(Device.BreadcrumbTracker.TotalScopesRecorded));
    AssertEquals('CompletedScopeCount must be 1', 1, Integer(Device.BreadcrumbTracker.CompletedScopeCount));
    AssertEquals('ActiveScopeCount must be 1', 1, Integer(Device.BreadcrumbTracker.ActiveScopeCount));

    CrashReport := Device.BreadcrumbTracker.FormatBreadcrumbCrashReport;
    AssertTrue('Crash report must mark ShadowMapPass as COMPLETED and LumenScreenProbeTracePass as ACTIVE_IN_FLIGHT',
      (Pos('ShadowMapPass -> COMPLETED', CrashReport) > 0) and
      (Pos('LumenScreenProbeTracePass -> ACTIVE_IN_FLIGHT (SUSPECTED GPU HANG)', CrashReport) > 0));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSVGFVarianceMomentsAndTemporalVarianceRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  MomentsGLSL: String;
  M0, M1, MBlend: TVector2;
  VarConstant, VarNoisy: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify SVGF Moments GLSL 450 functions }
    MomentsGLSL := Gen.GenerateSVGFVarianceMomentsFunctions;
    AssertTrue('SVGF Moments GLSL must include EvaluateLuminanceMoments and ComputeTemporalVariance',
      (Pos('vec2 EvaluateLuminanceMoments(vec3 radianceRGB)', MomentsGLSL) > 0) and
      (Pos('float ComputeTemporalVariance(vec2 moments)', MomentsGLSL) > 0));

    { 2. Verify constant luminance produces zero temporal variance, while fluctuating luminance produces positive variance }
    M0 := TCastleShaderGeneratorRHI.EvaluateLuminanceMoments(Vector3(1.0, 1.0, 1.0));
    M1 := TCastleShaderGeneratorRHI.EvaluateLuminanceMoments(Vector3(3.0, 3.0, 3.0));
    VarConstant := TCastleShaderGeneratorRHI.ComputeTemporalVariance(M0);
    MBlend := Vector2((M0.X + M1.X) * 0.5, (M0.Y + M1.Y) * 0.5);
    VarNoisy := TCastleShaderGeneratorRHI.ComputeTemporalVariance(MBlend);

    AssertSameValue(1.0, M0.X, 1e-5);
    AssertSameValue(1.0, M0.Y, 1e-5);
    AssertSameValue(0.0, VarConstant, 1e-6);
    AssertSameValue(1.0, VarNoisy, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSVGFAttrousWaveletEdgeStoppingAndContactHardeningRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  WaveletGLSL: String;
  WIdentical, WNormalEdge, WDepthEdge, WLumaOutlier: Single;
  BlurContact, BlurFar: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify SVGF A-Trous Wavelet & Contact Hardening GLSL 450 functions }
    WaveletGLSL := Gen.GenerateSVGFAttrousWaveletFunctions;
    AssertTrue('SVGF Wavelet GLSL must include EvaluateSVGFEdgeStoppingWeight and EvaluateHitDistanceBlurFactor',
      (Pos('float EvaluateSVGFEdgeStoppingWeight(vec3 centerNormal, vec3 sampleNormal,', WaveletGLSL) > 0) and
      (Pos('float EvaluateHitDistanceBlurFactor(float rayHitDistance, float cameraDistance, float roughness)', WaveletGLSL) > 0));

    { 2. Verify edge-stopping weights preserve normal creases, depth silhouettes, and low-variance luminance edges }
    WIdentical := TCastleShaderGeneratorRHI.EvaluateSVGFEdgeStoppingWeight(
      Vector3(0, 0, 1), Vector3(0, 0, 1), 5.0, 5.0, 0.01, 1.0, 1.0, 0.25);
    WNormalEdge := TCastleShaderGeneratorRHI.EvaluateSVGFEdgeStoppingWeight(
      Vector3(0, 0, 1), Vector3(1, 0, 0), 5.0, 5.0, 0.01, 1.0, 1.0, 0.25);
    WDepthEdge := TCastleShaderGeneratorRHI.EvaluateSVGFEdgeStoppingWeight(
      Vector3(0, 0, 1), Vector3(0, 0, 1), 5.0, 12.0, 0.01, 1.0, 1.0, 0.25);
    WLumaOutlier := TCastleShaderGeneratorRHI.EvaluateSVGFEdgeStoppingWeight(
      Vector3(0, 0, 1), Vector3(0, 0, 1), 5.0, 5.0, 0.01, 1.0, 10.0, 0.0001);

    AssertSameValue(1.0, WIdentical, 1e-5);
    AssertSameValue(0.0, WNormalEdge, 1e-6);
    AssertTrue('Depth silhouette jump must strongly attenuate A-Trous weight', WDepthEdge < 0.01);
    AssertTrue('Luminance outlier at near-zero variance must strongly attenuate A-Trous weight', WLumaOutlier < 0.01);

    { 3. Verify specular ray hit-distance contact hardening keeps contact reflections sharp }
    BlurContact := TCastleShaderGeneratorRHI.EvaluateHitDistanceBlurFactor(0.02, 5.0, 0.5);
    BlurFar     := TCastleShaderGeneratorRHI.EvaluateHitDistanceBlurFactor(20.0, 5.0, 0.5);
    AssertTrue('Contact hit distance must produce near-zero blur factor compared to distant hits',
      (BlurContact < 0.01) and (BlurFar > 0.35));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanSVGFDenoiserMultiPassDispatchRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  AssertEquals('A-Trous iteration 0 step size must be 1', 1, Integer(TCastleVulkanSVGFDenoiser.GetAttrousStepSize(0)));
  AssertEquals('A-Trous iteration 3 step size must be 8', 8, Integer(TCastleVulkanSVGFDenoiser.GetAttrousStepSize(3)));

  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($666B)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    Device.SVGFDenoiser.AttrousIterations := 4;
    CmdList.BeginRecording;
    Device.SVGFDenoiser.DispatchSVGFDenoise(CmdList, 1920, 1080, nil, nil);
    CmdList.EndRecording;

    AssertTrue('MomentsHistoryTexture must be allocated', Device.SVGFDenoiser.MomentsHistoryTexture <> nil);
    AssertTrue('FilteredPingTexture must be allocated', Device.SVGFDenoiser.FilteredPingTexture <> nil);
    AssertTrue('FilteredPongTexture must be allocated', Device.SVGFDenoiser.FilteredPongTexture <> nil);
    AssertEquals('4 A-Trous wavelet iterations must record 4 compute dispatches',
      4, Integer(Device.SVGFDenoiser.DispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestXPBDDistanceConstraintComplianceRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  XPBDGLSL: String;
  DeltaStiff, DeltaSoft: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify XPBD Cloth Compute GLSL 450 functions }
    XPBDGLSL := Gen.GenerateXPBDClothComputeShader;
    AssertTrue('XPBD Cloth GLSL must include EvaluateXPBDDistanceConstraintDelta and ResolveSphereCollisionConstraint',
      (Pos('vec3 EvaluateXPBDDistanceConstraintDelta(vec3 p1, vec3 p2, float invMass1, float invMass2,', XPBDGLSL) > 0) and
      (Pos('vec3 ResolveSphereCollisionConstraint(vec3 particlePos, vec3 sphereCenter, float sphereRadius, float margin)', XPBDGLSL) > 0));

    { 2. Verify stiff constraint (compliance = 0) moves p1 halfway toward rest length when w1 = w2 = 1 }
    DeltaStiff := TCastleShaderGeneratorRHI.EvaluateXPBDDistanceConstraintDelta(
      Vector3(0, 0, 0), Vector3(2.0, 0, 0), 1.0, 1.0, 1.0, 0.0, 0.01);
    DeltaSoft := TCastleShaderGeneratorRHI.EvaluateXPBDDistanceConstraintDelta(
      Vector3(0, 0, 0), Vector3(2.0, 0, 0), 1.0, 1.0, 1.0, 0.1, 0.01);

    { C = 2.0 - 1.0 = 1.0; DeltaP1 = -(-1.0 / 2.0) * (-1,0,0) = (+0.5, 0, 0) }
    AssertSameValue(0.5, DeltaStiff.X, 1e-5);
    AssertTrue('Compliant (soft) XPBD constraint must produce smaller single-step correction than zero-compliance stiff constraint',
      (DeltaSoft.X > 0.0) and (DeltaSoft.X < DeltaStiff.X));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestAerodynamicWindForceAndSphereCollisionRHI;
var
  WindForce: TVector3;
  PosInside, PosOutside: TVector3;
begin
  { 1. Verify aerodynamic wind force pushes surface normal facing relative wind }
  WindForce := TCastleShaderGeneratorRHI.EvaluateAerodynamicWindForce(
    Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 0, 1), 0.5, 1.2);
  AssertTrue('Aerodynamic wind force along +Z normal must be positive in Z',
    WindForce.Z > 1.0);

  { 2. Verify sphere SDF collision pushes penetrating particle to sphere surface + default 0.01 collision margin and leaves outside particle unchanged }
  PosInside := TCastleShaderGeneratorRHI.ResolveSphereCollisionConstraint(
    Vector3(0.3, 0, 0), Vector3(0, 0, 0), 1.0);
  PosOutside := TCastleShaderGeneratorRHI.ResolveSphereCollisionConstraint(
    Vector3(2.5, 0, 0), Vector3(0, 0, 0), 1.0);

  AssertSameValue(1.01, PosInside.X, 1e-5);
  AssertSameValue(2.5, PosOutside.X, 1e-5);
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanXPBDSimulatorSubstepDispatchRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($666E)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    Device.XPBDSimulator.SubstepCount := 4;
    CmdList.BeginRecording;
    Device.XPBDSimulator.DispatchXPBDSubsteps(CmdList, 1024, 2048);
    CmdList.EndRecording;

    AssertTrue('ParticlePositionBuffer must be allocated', Device.XPBDSimulator.ParticlePositionBuffer <> nil);
    AssertTrue('PreviousPositionBuffer must be allocated', Device.XPBDSimulator.PreviousPositionBuffer <> nil);
    AssertTrue('ConstraintBuffer must be allocated', Device.XPBDSimulator.ConstraintBuffer <> nil);
    AssertEquals('4 XPBD substeps must record 4 compute dispatches',
      4, Integer(Device.XPBDSimulator.TotalSubstepsDispatched));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestMultiviewStereoPreambleAndAsymmetricEyeProjectionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  StereoGLSL: String;
  SymScaleOff, AsymScaleOff: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Multiview Stereo GLSL 450 preamble }
    StereoGLSL := Gen.GenerateMultiviewStereoPreamble;
    AssertTrue('Multiview Stereo GLSL must enable GL_EXT_multiview and include ComputeAsymmetricEyeProjectionXScaleOffset',
      (Pos('#extension GL_EXT_multiview : enable', StereoGLSL) > 0) and
      (Pos('vec2 ComputeAsymmetricEyeProjectionXScaleOffset(float tanLeft, float tanRight)', StereoGLSL) > 0));

    { 2. Verify symmetric and asymmetric OpenXR eye frustum horizontal scale & offset }
    SymScaleOff  := TCastleShaderGeneratorRHI.ComputeAsymmetricEyeProjectionXScaleOffset(-1.0, 1.0);
    AsymScaleOff := TCastleShaderGeneratorRHI.ComputeAsymmetricEyeProjectionXScaleOffset(-1.2, 0.8);

    AssertSameValue(1.0, SymScaleOff.X, 1e-5);
    AssertSameValue(0.0, SymScaleOff.Y, 1e-5);
    AssertSameValue(1.0, AsymScaleOff.X, 1e-5);
    AssertSameValue(-0.2, AsymScaleOff.Y, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestFoveatedShadingRateAndMultiviewStereoManagerRHI;
var
  RateFovea, RateParafovea, RatePeriphery: Cardinal;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify gaze-tracked radial foveated VRS shading rate (1x1 fovea, 2x2 parafovea, 4x4 periphery) }
  RateFovea     := TCastleShaderGeneratorRHI.EvaluateFoveatedShadingRate(Vector2(0.5, 0.5), Vector2(0.5, 0.5));
  RateParafovea := TCastleShaderGeneratorRHI.EvaluateFoveatedShadingRate(Vector2(0.78, 0.5), Vector2(0.5, 0.5));
  RatePeriphery := TCastleShaderGeneratorRHI.EvaluateFoveatedShadingRate(Vector2(0.05, 0.05), Vector2(0.5, 0.5));

  AssertEquals('Foveal center must use 1x1 shading rate (0)', 0, Integer(RateFovea));
  AssertEquals('Parafoveal ring must use 2x2 shading rate ($5)', $5, Integer(RateParafovea));
  AssertEquals('Peripheral region must use 4x4 shading rate ($A)', $A, Integer(RatePeriphery));

  { 2. Verify TCastleVulkanMultiviewStereoManager 2-layer stereo array targets and single-pass execution }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($666F)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    CmdList.BeginRecording;
    Device.MultiviewStereoManager.BeginStereoMultiviewPass(CmdList, 2064, 2208);
    Device.MultiviewStereoManager.EndStereoMultiviewPass(CmdList);
    CmdList.EndRecording;

    AssertEquals('ViewMask must default to $3 (Left + Right eyes)', $3, Integer(Device.MultiviewStereoManager.ViewMask));
    AssertTrue('StereoColorArrayTexture must be allocated with 2 array layers',
      (Device.MultiviewStereoManager.StereoColorArrayTexture <> nil) and
      (Device.MultiviewStereoManager.StereoColorArrayTexture.Desc.DepthOrArrayLayers = 2));
    AssertTrue('StereoDepthArrayTexture must be allocated with 2 array layers',
      (Device.MultiviewStereoManager.StereoDepthArrayTexture <> nil) and
      (Device.MultiviewStereoManager.StereoDepthArrayTexture.Desc.DepthOrArrayLayers = 2));
    AssertEquals('StereoPassCount must be 1', 1, Integer(Device.MultiviewStereoManager.StereoPassCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestHDR10Rec2020AndST2084PQEncodingRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  HDR10GLSL: String;
  White2020, Red2020: TVector3;
  PQBlack, PQSDRWhite, PQPeak10k: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify HDR10 Rec.2020 & ST.2084 PQ GLSL 450 functions }
    HDR10GLSL := Gen.GenerateHDR10PQEncodingFunctions;
    AssertTrue('HDR10 GLSL must include EvaluateLinearRec709ToRec2020 and EncodeST2084PQ',
      (Pos('vec3 EvaluateLinearRec709ToRec2020(vec3 rec709)', HDR10GLSL) > 0) and
      (Pos('vec3 EncodeST2084PQ(vec3 linearNits)', HDR10GLSL) > 0));

    { 2. Verify ITU-R BT.709 -> BT.2020 gamut matrix preserves D65 neutral white and maps Rec.709 red }
    White2020 := TCastleShaderGeneratorRHI.EvaluateLinearRec709ToRec2020(Vector3(1.0, 1.0, 1.0));
    Red2020   := TCastleShaderGeneratorRHI.EvaluateLinearRec709ToRec2020(Vector3(1.0, 0.0, 0.0));
    AssertSameValue(1.0, White2020.X, 1e-4);
    AssertSameValue(1.0, White2020.Y, 1e-4);
    AssertSameValue(1.0, White2020.Z, 1e-4);
    AssertSameValue(0.627404, Red2020.X, 1e-5);
    AssertSameValue(0.069097, Red2020.Y, 1e-5);

    { 3. Verify SMPTE ST.2084 (PQ) transfer function at 0 nits, 100 nits (SDR reference white ~0.508078), and 10,000 nits (1.0) }
    PQBlack    := TCastleShaderGeneratorRHI.EncodeST2084PQ(Vector3(0.0, 0.0, 0.0));
    PQSDRWhite := TCastleShaderGeneratorRHI.EncodeST2084PQ(Vector3(100.0, 100.0, 100.0));
    PQPeak10k  := TCastleShaderGeneratorRHI.EncodeST2084PQ(Vector3(10000.0, 10000.0, 10000.0));

    AssertSameValue(0.0, PQBlack.X, 1e-6);
    AssertSameValue(0.508078, PQSDRWhite.X, 1e-4);
    AssertSameValue(1.0, PQPeak10k.X, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestDualQuaternionSkinningVolumePreservationRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  DQSGLSL: String;
  DQReal0, DQDual0, DQReal1, DQDual1, BlendedReal, BlendedDual: TVector4;
  TransformedPos: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Dual-Quaternion Skinning GLSL 450 functions }
    DQSGLSL := Gen.GenerateDualQuaternionSkinningFunctions;
    AssertTrue('DQS GLSL must include BlendDualQuaternionAntipodal and EvaluateDualQuaternionTransform',
      (Pos('void BlendDualQuaternionAntipodal(vec4 dqReal0, vec4 dqDual0, vec4 dqReal1, vec4 dqDual1,', DQSGLSL) > 0) and
      (Pos('vec3 EvaluateDualQuaternionTransform(vec4 dqReal, vec4 dqDual, vec3 pos)', DQSGLSL) > 0));

    { 2. Verify antipodality-aware blending between q = (0,0,0,1) and -q = (0,0,0,-1) does not collapse to zero }
    DQReal0 := Vector4(0, 0, 0, 1);
    DQDual0 := Vector4(0, 0, 0, 0);
    DQReal1 := Vector4(0, 0, 0, -1);
    DQDual1 := Vector4(0, 0, 0, 0);
    TCastleShaderGeneratorRHI.BlendDualQuaternionAntipodal(
      DQReal0, DQDual0, DQReal1, DQDual1, 0.5, 0.5, BlendedReal, BlendedDual);
    AssertSameValue(1.0, BlendedReal.Length, 1e-5);

    { 3. Verify 90-degree Z-axis rotation + translation preserves radial distance (zero volume collapse) }
    { 90 deg around Z: q_r = (0, 0, sin(45), cos(45)) = (0, 0, 0.70710678, 0.70710678), no translation }
    DQReal0 := Vector4(0, 0, Sqrt(0.5), Sqrt(0.5));
    TransformedPos := TCastleShaderGeneratorRHI.EvaluateDualQuaternionTransform(
      DQReal0, Vector4(0, 0, 0, 0), Vector3(2.0, 0.0, 0.0));
    AssertSameValue(0.0, TransformedPos.X, 1e-5);
    AssertSameValue(2.0, TransformedPos.Y, 1e-5);
    AssertSameValue(2.0, TransformedPos.Length, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestDisplacedMicroMeshBarycentricsAndEdgeSnappingRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  MicroGLSL: String;
  DispPos: TVector3;
  SnappedUV: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Displaced Micro-Mesh GLSL 450 functions }
    MicroGLSL := Gen.GenerateDisplacedMicroMeshFunctions;
    AssertTrue('Micro-Mesh GLSL must include EvaluateMicroMeshDisplacedPosition and SnapMicroMeshBarycentricToGrid',
      (Pos('vec3 EvaluateMicroMeshDisplacedPosition(vec3 p0, vec3 p1, vec3 p2,', MicroGLSL) > 0) and
      (Pos('vec2 SnapMicroMeshBarycentricToGrid(vec2 baryUV, uint subdivisionSegments)', MicroGLSL) > 0));

    { 2. Verify barycentric displacement along +Z normal }
    DispPos := TCastleShaderGeneratorRHI.EvaluateMicroMeshDisplacedPosition(
      Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(0, 3, 0),
      Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1),
      Vector2(1.0 / 3.0, 1.0 / 3.0), 0.5, 4.0, 0.25);
    AssertSameValue(1.0, DispPos.X, 1e-5);
    AssertSameValue(1.0, DispPos.Y, 1e-5);
    AssertSameValue(2.25, DispPos.Z, 1e-5);

    { 3. Verify crack-free barycentric snapping onto a 4-segment grid }
    SnappedUV := TCastleShaderGeneratorRHI.SnapMicroMeshBarycentricToGrid(
      Vector2(0.24, 0.51), 4);
    AssertSameValue(0.25, SnappedUV.X, 1e-5);
    AssertSameValue(0.50, SnappedUV.Y, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanPerInstanceCustomDataSSBORHI;
var
  Device: TVulkanRHIDevice;
  ReadBack0, ReadBack3: TVector4;
begin
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6670)) );
  try
    Device.PerInstanceCustomData.ClearInstanceCustomData;
    Device.PerInstanceCustomData.SetInstanceCustomData(0, Vector4(1.0, 0.5, 0.25, 0.0));
    Device.PerInstanceCustomData.SetInstanceCustomData(3, Vector4(0.2, 0.8, 1.0, 1.0));
    Device.PerInstanceCustomData.UploadCustomDataBuffer;

    ReadBack0 := Device.PerInstanceCustomData.GetInstanceCustomData(0);
    ReadBack3 := Device.PerInstanceCustomData.GetInstanceCustomData(3);

    AssertEquals('InstanceCount must grow to 4 (indices 0..3)', 4, Integer(Device.PerInstanceCustomData.InstanceCount));
    AssertSameValue(1.0, ReadBack0.X, 1e-5);
    AssertSameValue(0.8, ReadBack3.Y, 1e-5);
    AssertTrue('InstanceCustomDataBuffer must be allocated (64 bytes for 4 vec4 entries)',
      (Device.PerInstanceCustomData.InstanceCustomDataBuffer <> nil) and
      (Device.PerInstanceCustomData.InstanceCustomDataBuffer.Desc.Size = 64));
    AssertEquals('UploadCount must be 1', 1, Integer(Device.PerInstanceCustomData.UploadCount));
  finally
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestOpticalFlowBlockMatchingAndSubpixelOffsetRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  FlowGLSL: String;
  SADZero, SADDiff: Single;
  SubpixSym, SubpixShift: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Optical Flow SAD Block Matching GLSL 450 functions }
    FlowGLSL := Gen.GenerateOpticalFlowBlockMatchingShader;
    AssertTrue('Optical Flow GLSL must include EvaluateOpticalFlowPatchSAD and EstimateParabolicSubpixelOffset',
      (Pos('float EvaluateOpticalFlowPatchSAD(vec4 patchCurr, vec4 patchPrev)', FlowGLSL) > 0) and
      (Pos('vec2 EstimateParabolicSubpixelOffset(float sadLeft, float sadCenter, float sadRight,', FlowGLSL) > 0));

    { 2. Verify SAD evaluation on 2x2 luma patches }
    SADZero := TCastleShaderGeneratorRHI.EvaluateOpticalFlowPatchSAD(
      Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0.5, 0.5, 0.5, 0.5));
    SADDiff := TCastleShaderGeneratorRHI.EvaluateOpticalFlowPatchSAD(
      Vector4(0.5, 0.5, 0.5, 0.5), Vector4(0.25, 0.75, 0.25, 0.75));
    AssertSameValue(0.0, SADZero, 1e-6);
    AssertSameValue(1.0, SADDiff, 1e-5);

    { 3. Verify parabolic sub-pixel motion refinement }
    SubpixSym   := TCastleShaderGeneratorRHI.EstimateParabolicSubpixelOffset(4.0, 1.0, 4.0, 3.0, 3.0);
    SubpixShift := TCastleShaderGeneratorRHI.EstimateParabolicSubpixelOffset(5.0, 1.0, 2.0, 3.0, 3.0);
    AssertSameValue(0.0, SubpixSym.X, 1e-6);
    AssertSameValue(0.0, SubpixSym.Y, 1e-6);
    AssertTrue('Lower SAD on right neighbor must produce positive sub-pixel X shift',
      (SubpixShift.X > 0.1) and (SubpixShift.X <= 0.5));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSpatioTemporalBlueNoiseAndR2SequenceRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  BNGLSL: String;
  P0, P1: TVector2;
  J0, J1: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Spatio-Temporal Blue-Noise & R2 Sequence GLSL 450 functions }
    BNGLSL := Gen.GenerateSpatioTemporalBlueNoiseFunctions;
    AssertTrue('Blue-Noise GLSL must include EvaluateR2Sequence2D and EvaluateTemporalBlueNoiseJitter',
      (Pos('vec2 EvaluateR2Sequence2D(uint sampleIndex)', BNGLSL) > 0) and
      (Pos('float EvaluateTemporalBlueNoiseJitter(float baseBlueNoise, uint frameIndex)', BNGLSL) > 0));

    { 2. Verify Martin Roberts 2D R2 low-discrepancy sequence stays in [0..1)^2 and advances quasi-uniformly }
    P0 := TCastleShaderGeneratorRHI.EvaluateR2Sequence2D(0);
    P1 := TCastleShaderGeneratorRHI.EvaluateR2Sequence2D(1);
    AssertTrue('R2 sequence points must lie in [0..1)^2 and be well-separated',
      (P0.X >= 0.0) and (P0.X < 1.0) and (P0.Y >= 0.0) and (P0.Y < 1.0) and
      ((P1 - P0).Length > 0.2));

    { 3. Verify golden-ratio temporal blue-noise rotation }
    J0 := TCastleShaderGeneratorRHI.EvaluateTemporalBlueNoiseJitter(0.25, 0);
    J1 := TCastleShaderGeneratorRHI.EvaluateTemporalBlueNoiseJitter(0.25, 1);
    AssertSameValue(0.25, J0, 1e-5);
    AssertSameValue(0.25 + 0.61803398875, J1, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanNeuralDenoiserMLPInferenceRHI;
var
  ActPos, ActNeg: Single;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify Linear + ReLU activation }
  ActPos := TCastleVulkanNeuralDenoiser.EvaluateLinearReLU4(
    Vector4(1.0, 2.0, 0.5, 0.0), Vector4(0.5, 0.25, 1.0, 0.0), 0.25);
  ActNeg := TCastleVulkanNeuralDenoiser.EvaluateLinearReLU4(
    Vector4(1.0, 1.0, 1.0, 1.0), Vector4(-1.0, -1.0, 0.0, 0.0), 0.5);
  AssertSameValue(1.75, ActPos, 1e-5);
  AssertSameValue(0.0, ActNeg, 1e-6);

  { 2. Verify TCastleVulkanNeuralDenoiser resource allocation and compute dispatch }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6671)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    Device.NeuralDenoiser.HiddenUnits := 32;
    CmdList.BeginRecording;
    Device.NeuralDenoiser.DispatchNeuralInference(CmdList, 1920, 1080);
    CmdList.EndRecording;

    AssertTrue('MLPWeightsBuffer must be allocated', Device.NeuralDenoiser.MLPWeightsBuffer <> nil);
    AssertTrue('DenoisedOutputTexture must be allocated', Device.NeuralDenoiser.DenoisedOutputTexture <> nil);
    AssertEquals('InferenceDispatchCount must be 1', 1, Integer(Device.NeuralDenoiser.InferenceDispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSERCoherenceHintKeyPackingRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SERGLSL: String;
  KeyHitPos, KeyHitNeg, KeyMiss: Cardinal;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify SER Coherence Hint GLSL 450 functions }
    SERGLSL := Gen.GenerateSERCoherenceHintFunctions;
    AssertTrue('SER GLSL must include PackSERCoherenceHintKey',
      Pos('uint PackSERCoherenceHintKey(bool isHit, uint materialShadingModelID, vec3 rayDirection)', SERGLSL) > 0);

    { 2. Verify 8-bit coherence key packing: bit 7 = hit/miss, bits 3..6 = materialId, bits 0..2 = octant }
    KeyHitPos := TCastleShaderGeneratorRHI.PackSERCoherenceHintKey(True, 5, Vector3(1.0, 1.0, 1.0));
    KeyHitNeg := TCastleShaderGeneratorRHI.PackSERCoherenceHintKey(True, 5, Vector3(-1.0, -1.0, -1.0));
    KeyMiss   := TCastleShaderGeneratorRHI.PackSERCoherenceHintKey(False, 5, Vector3(1.0, 1.0, 1.0));

    AssertEquals('Hit in (+,+,+) octant (7) with mat 5 must pack to 128 + 40 + 7 = 175',
      175, Integer(KeyHitPos));
    AssertEquals('Hit in (-,-,-) octant (0) with mat 5 must pack to 128 + 40 + 0 = 168',
      168, Integer(KeyHitNeg));
    AssertEquals('Miss must clear bit 7 (40 + 7 = 47)',
      47, Integer(KeyMiss));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestDualSourceColoredGlassTransmissionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  GlassGLSL: String;
  Src0, Src1: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Dual-Source Colored Glass GLSL 450 functions }
    GlassGLSL := Gen.GenerateDualSourceGlassTransmissionFunctions;
    AssertTrue('Dual-Source Glass GLSL must include index = 1 output and EvaluateDualSourceGlassOutputs',
      (Pos('layout(location = 0, index = 1)', GlassGLSL) > 0) and
      (Pos('void EvaluateDualSourceGlassOutputs(', GlassGLSL) > 0));

    { 2. Verify Src0 (additive reflection) and Src1 (colored background transmittance) }
    TCastleShaderGeneratorRHI.EvaluateDualSourceGlassOutputs(
      Vector3(0.175, 0.400, 0.250), Vector3(0.2, 0.8, 0.4), 0.25, 0.5, Src0, Src1);

    AssertSameValue(0.175, Src0.X, 1e-5);
    AssertSameValue(0.400, Src0.Y, 1e-5);
    AssertSameValue(0.250, Src0.Z, 1e-5);

    { Src1.rgb = (1 - 0.25) * mix((1,1,1), (0.2, 0.8, 0.4), 0.5) = 0.75 * (0.6, 0.9, 0.7) = (0.45, 0.675, 0.525) }
    AssertSameValue(0.450, Src1.X, 1e-5);
    AssertSameValue(0.675, Src1.Y, 1e-5);
    AssertSameValue(0.525, Src1.Z, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanProgrammableSampleLocationsRGSSRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  S0, S1, S2, S3: TVector2;
begin
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6672)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    Device.ProgrammableSampleLocations.ConfigureRotatedGridPattern(4);
    S0 := Device.ProgrammableSampleLocations.GetSampleLocation(0);
    S1 := Device.ProgrammableSampleLocations.GetSampleLocation(1);
    S2 := Device.ProgrammableSampleLocations.GetSampleLocation(2);
    S3 := Device.ProgrammableSampleLocations.GetSampleLocation(3);

    AssertEquals('SampleCount must be 4', 4, Integer(Device.ProgrammableSampleLocations.SampleCount));
    AssertSameValue(0.375, S0.X, 1e-5);
    AssertSameValue(0.125, S0.Y, 1e-5);
    AssertSameValue(0.875, S1.X, 1e-5);
    AssertSameValue(0.375, S1.Y, 1e-5);
    AssertSameValue(0.125, S2.X, 1e-5);
    AssertSameValue(0.625, S2.Y, 1e-5);
    AssertSameValue(0.625, S3.X, 1e-5);
    AssertSameValue(0.875, S3.Y, 1e-5);

    CmdList.BeginRecording;
    Device.ProgrammableSampleLocations.ApplySampleLocations(CmdList);
    CmdList.EndRecording;
    AssertEquals('LocationsAppliedCount must be 1', 1, Integer(Device.ProgrammableSampleLocations.LocationsAppliedCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestDynamicRenderingLocalReadDeferredLightingRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  LocalReadGLSL: String;
  LitSpec, LitBackface: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Vulkan 1.4 Dynamic Rendering Local Read subpassInput preamble }
    LocalReadGLSL := Gen.GenerateDynamicRenderingLocalReadPreamble;
    AssertTrue('LocalRead GLSL must declare subpassInput and EvaluateTileLocalDeferredLighting',
      (Pos('layout(input_attachment_index = 0, set = 0, binding = 0) uniform subpassInput castle_TileGBufferAlbedo;', LocalReadGLSL) > 0) and
      (Pos('vec3 EvaluateTileLocalDeferredLighting(vec3 albedo, vec3 normalWS, float roughness,', LocalReadGLSL) > 0));

    { 2. Verify tile-local deferred lighting evaluation }
    LitSpec := TCastleShaderGeneratorRHI.EvaluateTileLocalDeferredLighting(
      Vector3(0.5, 0.5, 0.5), Vector3(0.0, 0.0, 1.0), 0.25,
      Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 1.0, 1.0));
    LitBackface := TCastleShaderGeneratorRHI.EvaluateTileLocalDeferredLighting(
      Vector3(0.5, 0.5, 0.5), Vector3(0.0, 0.0, 1.0), 0.25,
      Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 1.0), Vector3(1.0, 1.0, 1.0));

    AssertTrue('Front-lit tile G-Buffer pixel with aligned view/light must produce strong specular + diffuse lighting',
      LitSpec.X > 1.0);
    AssertSameValue(0.0, LitBackface.X, 1e-6);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSubgroupWaveBallotAndExclusivePrefixSumRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  WaveGLSL: String;
  BitCount: Cardinal;
  ScanOut: TVector4Cardinal;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Subgroup Wave Intrinsics GLSL 450 functions }
    WaveGLSL := Gen.GenerateSubgroupWaveIntrinsicsFunctions;
    AssertTrue('Subgroup GLSL must enable GL_KHR_shader_subgroup_ballot and GL_KHR_shader_subgroup_arithmetic',
      (Pos('#extension GL_KHR_shader_subgroup_ballot : enable', WaveGLSL) > 0) and
      (Pos('uint EvaluateSubgroupExclusivePrefixSum(uint value)', WaveGLSL) > 0));

    { 2. Verify 64-bit ballot bit count (popcount) }
    BitCount := TCastleShaderGeneratorRHI.EvaluateSubgroupBallotBitCount(UInt64($000F000F000F000F));
    AssertEquals('Ballot mask $000F000F000F000F must have 16 active lanes', 16, Integer(BitCount));

    { 3. Verify 4-lane subgroup exclusive prefix sum: (3, 1, 4, 2) -> (0, 3, 4, 8) }
    ScanOut := TCastleShaderGeneratorRHI.EvaluateSubgroupExclusivePrefixSum4(
      Vector4Cardinal(3, 1, 4, 2));
    AssertEquals('Lane 0 exclusive scan must be 0', 0, Integer(ScanOut.X));
    AssertEquals('Lane 1 exclusive scan must be 3', 3, Integer(ScanOut.Y));
    AssertEquals('Lane 2 exclusive scan must be 4', 4, Integer(ScanOut.Z));
    AssertEquals('Lane 3 exclusive scan must be 8', 8, Integer(ScanOut.W));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanStreamCompactorPrefixSumRHI;
var
  PrefixSum, Compacted: TCardinalDynamicArray;
  SurvivingCount: Cardinal;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify Blelloch exclusive prefix-sum and predicate stream compaction }
  SurvivingCount := TCastleVulkanStreamCompactor.EvaluatePrefixSumAndCompact(
    [True, False, True, True, False, True], PrefixSum, Compacted);
  AssertEquals('Surviving element count must be 4', 4, Integer(SurvivingCount));
  AssertEquals('PrefixSum[0] = 0', 0, Integer(PrefixSum[0]));
  AssertEquals('PrefixSum[2] = 1', 1, Integer(PrefixSum[2]));
  AssertEquals('PrefixSum[5] = 3', 3, Integer(PrefixSum[5]));
  AssertEquals('Compacted[0] = 0', 0, Integer(Compacted[0]));
  AssertEquals('Compacted[1] = 2', 2, Integer(Compacted[1]));
  AssertEquals('Compacted[2] = 3', 3, Integer(Compacted[2]));
  AssertEquals('Compacted[3] = 5', 5, Integer(Compacted[3]));

  { 2. Verify TCastleVulkanStreamCompactor GPU buffer allocation and compute dispatch }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6673)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    CmdList.BeginRecording;
    Device.StreamCompactor.DispatchStreamCompaction(CmdList, 1024);
    CmdList.EndRecording;

    AssertEquals('MaxElementCount must be 1024', 1024, Integer(Device.StreamCompactor.MaxElementCount));
    AssertTrue('PrefixSumBuffer and CompactedIndicesBuffer must be allocated',
      (Device.StreamCompactor.PrefixSumBuffer <> nil) and
      (Device.StreamCompactor.CompactedIndicesBuffer <> nil) and
      (Device.StreamCompactor.CompactedCountBuffer <> nil));
    AssertEquals('CompactionDispatchCount must be 1', 1, Integer(Device.StreamCompactor.CompactionDispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestBufferDeviceAddressAlignmentAndPreambleRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  BDAGLSL: String;
  Aligned16, AlignedExact: UInt64;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Buffer Device Address GLSL 450 preamble }
    BDAGLSL := Gen.GenerateBufferDeviceAddressPreamble;
    AssertTrue('BDA GLSL must require GL_EXT_buffer_reference2 and declare CastleBDAVertexBuffer',
      (Pos('#extension GL_EXT_buffer_reference2 : require', BDAGLSL) > 0) and
      (Pos('layout(buffer_reference, scalar, buffer_reference_align = 16) readonly buffer CastleBDAVertexBuffer', BDAGLSL) > 0));

    { 2. Verify 64-bit GPU device address alignment }
    Aligned16 := TCastleShaderGeneratorRHI.AlignBufferDeviceAddress(UInt64($10000003), 16);
    AlignedExact := TCastleShaderGeneratorRHI.AlignBufferDeviceAddress(UInt64($10000020), 16);
    AssertEquals('Address $10000003 aligned to 16 must be $10000010', Int64($10000010), Int64(Aligned16));
    AssertEquals('Address $10000020 aligned to 16 must remain $10000020', Int64($10000020), Int64(AlignedExact));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVoxelDominantAxisAndConeStepApertureRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  VXGIGLSL: String;
  AxisX, AxisY, AxisZ: Cardinal;
  Step0, StepFar: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Voxelization & Voxel Cone Tracing GLSL 450 functions }
    VXGIGLSL := Gen.GenerateVoxelConeTracingFunctions;
    AssertTrue('VXGI GLSL must include SelectDominantVoxelProjectionAxis and EvaluateVoxelConeStepAperture',
      (Pos('uint SelectDominantVoxelProjectionAxis(vec3 faceNormal)', VXGIGLSL) > 0) and
      (Pos('vec2 EvaluateVoxelConeStepAperture(float distanceAlongCone, float coneHalfAngleTan, float baseVoxelSize)', VXGIGLSL) > 0));

    { 2. Verify dominant-axis selection for conservative triangle voxelization }
    AxisX := TCastleShaderGeneratorRHI.SelectDominantVoxelProjectionAxis(Vector3(-0.9, 0.3, 0.2));
    AxisY := TCastleShaderGeneratorRHI.SelectDominantVoxelProjectionAxis(Vector3(0.2, 0.85, -0.4));
    AxisZ := TCastleShaderGeneratorRHI.SelectDominantVoxelProjectionAxis(Vector3(0.1, -0.2, 0.95));
    AssertEquals('Dominant X axis must be 0', 0, Integer(AxisX));
    AssertEquals('Dominant Y axis must be 1', 1, Integer(AxisY));
    AssertEquals('Dominant Z axis must be 2', 2, Integer(AxisZ));

    { 3. Verify cone diameter and 3D mip level growth along cone distance }
    Step0   := TCastleShaderGeneratorRHI.EvaluateVoxelConeStepAperture(0.0, 0.5, 0.25);
    StepFar := TCastleShaderGeneratorRHI.EvaluateVoxelConeStepAperture(1.0, 0.5, 0.25);
    AssertSameValue(0.25, Step0.X, 1e-5);
    AssertSameValue(0.0, Step0.Y, 1e-5);
    { At distance=1.0, tan=0.5 -> diameter = 2*1*0.5 = 1.0 = 4x baseVoxelSize (0.25) -> mipLevel = log2(4) = 2.0 }
    AssertSameValue(1.0, StepFar.X, 1e-5);
    AssertSameValue(2.0, StepFar.Y, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanVoxelConeTracerMipChainAndDispatchRHI;
var
  AccumRad: TVector3;
  AccumOp: Single;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify front-to-back voxel cone opacity & radiance compositing }
  AccumRad := TVector3.Zero;
  AccumOp  := 0.0;
  TCastleVulkanVoxelConeTracer.AccumulateVoxelConeSample(
    Vector3(1.0, 0.5, 0.0), 0.5, AccumRad, AccumOp);
  TCastleVulkanVoxelConeTracer.AccumulateVoxelConeSample(
    Vector3(0.0, 1.0, 0.0), 0.5, AccumRad, AccumOp);

  AssertSameValue(0.5, AccumRad.X, 1e-5);
  AssertSameValue(0.5, AccumRad.Y, 1e-5);
  AssertSameValue(0.75, AccumOp, 1e-5);

  { 2. Verify TCastleVulkanVoxelConeTracer 3D mipmapped volume allocation and compute dispatch }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6674)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    Device.VoxelConeTracer.VoxelGridResolution := 64;
    CmdList.BeginRecording;
    Device.VoxelConeTracer.DispatchVoxelConeTrace(CmdList, 1920, 1080);
    CmdList.EndRecording;

    AssertEquals('64^3 voxel grid must have 7 mip levels (64..1)', 7, Integer(Device.VoxelConeTracer.VoxelMipLevels));
    AssertTrue('VoxelRadianceTexture must be allocated as a 3D texture',
      (Device.VoxelConeTracer.VoxelRadianceTexture <> nil) and
      (Device.VoxelConeTracer.VoxelRadianceTexture.Desc.Dimension = td3D));
    AssertTrue('IndirectIrradianceTexture must be allocated',
      Device.VoxelConeTracer.IndirectIrradianceTexture <> nil);
    AssertEquals('ConeTraceDispatchCount must be 1', 1, Integer(Device.VoxelConeTracer.ConeTraceDispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSpecularNormalVarianceAARoughnessFilteringRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SpecAAGLSL: String;
  RoughFlat, RoughCurved: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Normal-Variance Specular AA GLSL 450 functions }
    SpecAAGLSL := Gen.GenerateSpecularNormalVarianceAAFunctions;
    AssertTrue('Specular AA GLSL must include EvaluateSpecularAARoughness',
      Pos('float EvaluateSpecularAARoughness(float baseRoughness, vec3 dNdU, vec3 dNdV,', SpecAAGLSL) > 0);

    { 2. Verify zero normal derivatives preserve base roughness while high normal variance increases roughness }
    RoughFlat := TCastleShaderGeneratorRHI.EvaluateSpecularAARoughness(
      0.1, TVector3.Zero, TVector3.Zero, 0.5, 0.18);
    RoughCurved := TCastleShaderGeneratorRHI.EvaluateSpecularAARoughness(
      0.1, Vector3(0.4, 0.0, 0.0), Vector3(0.0, 0.4, 0.0), 0.5, 0.18);

    AssertSameValue(0.1, RoughFlat, 1e-5);
    AssertTrue('High screen-space normal variance must increase filtered perceptual roughness (> 0.5)',
      (RoughCurved > 0.5) and (RoughCurved <= 1.0));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestRectilinearShadowMapUVWarpingRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  WarpGLSL: String;
  UVCenter, UVEdge0, UVEdge1, UVQuarter: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Rectilinear Shadow Warp GLSL 450 functions }
    WarpGLSL := Gen.GenerateRectilinearShadowWarpFunctions;
    AssertTrue('Shadow Warp GLSL must include EvaluateRectilinearShadowWarpUV',
      Pos('vec2 EvaluateRectilinearShadowWarpUV(vec2 shadowUV, float warpStrength)', WarpGLSL) > 0);

    { 2. Verify center (0.5, 0.5) and corners (0,0)/(1,1) remain fixed while interior stretches outward }
    UVCenter  := TCastleShaderGeneratorRHI.EvaluateRectilinearShadowWarpUV(Vector2(0.5, 0.5), 2.0);
    UVEdge0   := TCastleShaderGeneratorRHI.EvaluateRectilinearShadowWarpUV(Vector2(0.0, 0.0), 2.0);
    UVEdge1   := TCastleShaderGeneratorRHI.EvaluateRectilinearShadowWarpUV(Vector2(1.0, 1.0), 2.0);
    UVQuarter := TCastleShaderGeneratorRHI.EvaluateRectilinearShadowWarpUV(Vector2(0.75, 0.5), 2.0);

    AssertSameValue(0.5, UVCenter.X, 1e-6);
    AssertSameValue(0.5, UVCenter.Y, 1e-6);
    AssertSameValue(0.0, UVEdge0.X, 1e-6);
    AssertSameValue(1.0, UVEdge1.X, 1e-6);
    { p = 0.5 with w = 2.0 -> warpedP = 0.5 * 3 / (1 + 1) = 0.75 -> UV = 0.875 > 0.75 }
    AssertSameValue(0.875, UVQuarter.X, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestMSDFMedianOfThreeAndScreenPxOpacityRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  MSDFGLSL: String;
  MedianVal, OpacityInside, OpacityEdge, OpacityOutside: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify MSDF GLSL 450 functions }
    MSDFGLSL := Gen.GenerateMSDFTextFunctions;
    AssertTrue('MSDF GLSL must include EvaluateMSDFMedianOfThree',
      Pos('float EvaluateMSDFMedianOfThree(float r, float g, float b)', MSDFGLSL) > 0);
    AssertTrue('MSDF GLSL must include EvaluateMSDFScreenPxOpacity',
      Pos('float EvaluateMSDFScreenPxOpacity(vec3 msdfRGB, float screenPxRange)', MSDFGLSL) > 0);

    { 2. Verify Chlumsky median-of-three and screen-pixel AA opacity }
    MedianVal := TCastleShaderGeneratorRHI.EvaluateMSDFMedianOfThree(0.2, 0.8, 0.6);
    AssertSameValue(0.6, MedianVal, 1e-6);

    OpacityInside  := TCastleShaderGeneratorRHI.EvaluateMSDFScreenPxOpacity(Vector3(0.2, 0.8, 0.7), 4.0);
    OpacityEdge    := TCastleShaderGeneratorRHI.EvaluateMSDFScreenPxOpacity(Vector3(0.5, 0.9, 0.1), 4.0);
    OpacityOutside := TCastleShaderGeneratorRHI.EvaluateMSDFScreenPxOpacity(Vector3(0.1, 0.2, 0.9), 4.0);

    AssertTrue('Glyph interior (median > 0.5) must approach full opacity', OpacityInside > 0.95);
    AssertSameValue(0.5, OpacityEdge, 1e-6);
    AssertTrue('Glyph exterior (median < 0.5) must approach zero opacity', OpacityOutside < 0.05);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestQuadraticBezierGrassBladePositionAndTangentRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  GrassGLSL: String;
  P0, P1, P2, PosBase, TanBase, PosMid, TanMid, PosTip, TanTip: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Procedural Grass Blade GLSL 450 functions }
    GrassGLSL := Gen.GenerateProceduralGrassBladeFunctions;
    AssertTrue('Grass GLSL must include EvaluateQuadraticBezierGrassBlade',
      Pos('void EvaluateQuadraticBezierGrassBlade(vec3 p0, vec3 p1, vec3 p2, float t,', GrassGLSL) > 0);

    { 2. Verify Quadratic Bezier position and tangent at root (t=0), midpoint (t=0.5), and tip (t=1) }
    P0 := Vector3(0.0, 0.0, 0.0);
    P1 := Vector3(0.0, 1.0, 0.0);
    P2 := Vector3(1.0, 1.0, 0.0);

    TCastleShaderGeneratorRHI.EvaluateQuadraticBezierGrassBlade(P0, P1, P2, 0.0, PosBase, TanBase);
    TCastleShaderGeneratorRHI.EvaluateQuadraticBezierGrassBlade(P0, P1, P2, 0.5, PosMid, TanMid);
    TCastleShaderGeneratorRHI.EvaluateQuadraticBezierGrassBlade(P0, P1, P2, 1.0, PosTip, TanTip);

    AssertSameValue(0.0, PosBase.X, 1e-6);
    AssertSameValue(1.0, TanBase.Y, 1e-6); { Vertical tangent at root }
    AssertSameValue(0.25, PosMid.X, 1e-6);
    AssertSameValue(0.75, PosMid.Y, 1e-6);
    AssertSameValue(1.0, PosTip.X, 1e-6);
    AssertSameValue(1.0, PosTip.Y, 1e-6);
    AssertSameValue(1.0, TanTip.X, 1e-6); { Horizontal wind-bent tangent at tip }
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanPerPixelLinkedListOITSortAndResolveRHI;
var
  Nodes: array[0..1] of TPPLLFragmentNode;
  ResolvedA, ResolvedB: TVector3;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  AssertEquals('TPPLLFragmentNode must be 24 bytes', 24, SizeOf(TPPLLFragmentNode));

  { 1. Verify exact OIT back-to-front sorting yields identical result regardless of submission order }
  { Far blue layer (depth = 0.8, alpha = 0.5) and Near red layer (depth = 0.2, alpha = 0.5) }
  Nodes[0].ColorRGBA := Vector4(1.0, 0.0, 0.0, 0.5);
  Nodes[0].Depth := 0.2;
  Nodes[0].NextIndex := 1;
  Nodes[1].ColorRGBA := Vector4(0.0, 0.0, 1.0, 0.5);
  Nodes[1].Depth := 0.8;
  Nodes[1].NextIndex := $FFFFFFFF;
  ResolvedA := TCastleVulkanPerPixelLinkedListOIT.SortAndCompositeFragmentsBackToFront(
    Nodes, Vector3(0.0, 0.0, 0.0));

  { Swap submission order }
  Nodes[0].ColorRGBA := Vector4(0.0, 0.0, 1.0, 0.5);
  Nodes[0].Depth := 0.8;
  Nodes[1].ColorRGBA := Vector4(1.0, 0.0, 0.0, 0.5);
  Nodes[1].Depth := 0.2;
  ResolvedB := TCastleVulkanPerPixelLinkedListOIT.SortAndCompositeFragmentsBackToFront(
    Nodes, Vector3(0.0, 0.0, 0.0));

  AssertSameValue(ResolvedA.X, ResolvedB.X, 1e-6);
  AssertSameValue(ResolvedA.Z, ResolvedB.Z, 1e-6);
  AssertTrue('Near red layer must dominate over occluded far blue layer (R > B)',
    ResolvedA.X > ResolvedA.Z);

  { 2. Verify TCastleVulkanPerPixelLinkedListOIT resource allocation and resolve dispatch }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6676)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    CmdList.BeginRecording;
    Device.PerPixelLinkedListOIT.DispatchPPLLResolve(CmdList, 1920, 1080);
    CmdList.EndRecording;

    AssertTrue('HeadPointerTexture, FragmentNodeBuffer, and AtomicCounterBuffer must be allocated',
      (Device.PerPixelLinkedListOIT.HeadPointerTexture <> nil) and
      (Device.PerPixelLinkedListOIT.FragmentNodeBuffer <> nil) and
      (Device.PerPixelLinkedListOIT.AtomicCounterBuffer <> nil));
    AssertEquals('ResolveDispatchCount must be 1', 1, Integer(Device.PerPixelLinkedListOIT.ResolveDispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestPushDescriptorPreambleAndHostImageCopyByteSizeRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  PushGLSL: String;
  TightBytes, AlignedBytes: UInt64;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Push Descriptor GLSL 450 preamble }
    PushGLSL := Gen.GeneratePushDescriptorPreamble(2);
    AssertTrue('Push Descriptor GLSL must include CastlePushMaterialBlock at set 2, binding 0',
      Pos('layout(set = 2, binding = 0) uniform CastlePushMaterialBlock', PushGLSL) > 0);
    AssertTrue('Push Descriptor GLSL must include castle_PushBaseColorTex at set 2, binding 1',
      Pos('layout(set = 2, binding = 1) uniform sampler2D castle_PushBaseColorTex;', PushGLSL) > 0);

    { 2. Verify Host Image Copy byte size with tight (1-byte) and aligned (256-byte) row pitch }
    TightBytes := TCastleShaderGeneratorRHI.ComputeHostImageCopyByteSize(50, 10, 1, 4, 1);
    AlignedBytes := TCastleShaderGeneratorRHI.ComputeHostImageCopyByteSize(50, 10, 1, 4, 256);

    { 50 * 4 = 200 bytes/row -> tight = 200 * 10 = 2000; 256-aligned = 256 * 10 = 2560 }
    AssertEquals('Tight host image copy size must be 2000 bytes', Int64(2000), Int64(TightBytes));
    AssertEquals('256-byte row-aligned host image copy size must be 2560 bytes', Int64(2560), Int64(AlignedBytes));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSphericalGaussianProductAndIntegralRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SGGLSL: String;
  ProdAxis: TVector3;
  ProdSharpness, LogAmpScale: Single;
  IsoIntegral, SharpIntegral: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Spherical Gaussian GLSL 450 functions }
    SGGLSL := Gen.GenerateSphericalGaussianFunctions;
    AssertTrue('SG GLSL must include EvaluateSphericalGaussian',
      Pos('vec3 EvaluateSphericalGaussian(vec3 dir, vec3 axis, float sharpness, vec3 amplitude)', SGGLSL) > 0);
    AssertTrue('SG GLSL must include EvaluateSphericalGaussianIntegral',
      Pos('vec3 EvaluateSphericalGaussianIntegral(vec3 amplitude, float sharpness)', SGGLSL) > 0);

    { 2. Verify Spherical Gaussian lobe product for aligned and orthogonal lobes }
    TCastleShaderGeneratorRHI.EvaluateSphericalGaussianProduct(
      Vector3(0.0, 1.0, 0.0), 4.0,
      Vector3(0.0, 1.0, 0.0), 6.0,
      ProdAxis, ProdSharpness, LogAmpScale);
    AssertSameValue(1.0, ProdAxis.Y, 1e-6);
    AssertSameValue(10.0, ProdSharpness, 1e-5);
    AssertSameValue(0.0, LogAmpScale, 1e-5);

    { 3. Verify Spherical Gaussian integral approaches 4*pi*amplitude at sharpness->0 and decreases as sharpness grows }
    IsoIntegral := TCastleShaderGeneratorRHI.EvaluateSphericalGaussianIntegral(Vector3(1.0, 1.0, 1.0), 0.0);
    SharpIntegral := TCastleShaderGeneratorRHI.EvaluateSphericalGaussianIntegral(Vector3(1.0, 1.0, 1.0), 8.0);
    AssertSameValue(4.0 * Pi, IsoIntegral.X, 1e-4);
    AssertTrue('Sharper SG lobe must integrate to smaller total solid angle than isotropic lobe',
      (SharpIntegral.X > 0.0) and (SharpIntegral.X < IsoIntegral.X));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanHostImageCopyAndPushDescriptorManagerRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  TexDesc: TRHITextureDesc;
  Tex: TVulkanRHITexture;
  CopyOK: Boolean;
begin
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6677)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  Tex := nil;
  try
    TexDesc := TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 1, 1);
    Tex := Device.CreateTexture(TexDesc) as TVulkanRHITexture;

    CopyOK := Device.HostImageCopyManager.CopyHostMemoryToTexture(Tex, nil, 64 * 64 * 4, 0);
    AssertTrue('Zero-staging host image copy must succeed for valid mip 0', CopyOK);
    AssertEquals('HostImageCopyCount must be 1', 1, Integer(Device.HostImageCopyManager.HostImageCopyCount));
    AssertEquals('HostImageBytesCopied must be 16384', Int64(16384), Int64(Device.HostImageCopyManager.HostImageBytesCopied));

    CmdList.BeginRecording;
    Device.HostImageCopyManager.RecordPushDescriptorUpdate(CmdList, 1, 3);
    CmdList.EndRecording;
    AssertEquals('PushDescriptorUpdateCount must be 1', 1, Integer(Device.HostImageCopyManager.PushDescriptorUpdateCount));
  finally
    FreeAndNil(Tex);
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestGaussianSplatConicOpacityFalloffRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SplatGLSL: String;
  AlphaCenter, AlphaNear, AlphaFar: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify 3D Gaussian Splatting GLSL 450 functions }
    SplatGLSL := Gen.GenerateGaussianSplattingFunctions;
    AssertTrue('3DGS GLSL must include EvaluateGaussianSplatOpacity',
      Pos('float EvaluateGaussianSplatOpacity(vec3 cov2D, vec2 pixelOffset, float baseOpacity)', SplatGLSL) > 0);
    AssertTrue('3DGS GLSL must include EvaluateSphericalHarmonicsL1RGB',
      Pos('vec3 EvaluateSphericalHarmonicsL1RGB(vec3 sh0, vec3 sh1X, vec3 sh1Y, vec3 sh1Z, vec3 viewDir)', SplatGLSL) > 0);

    { 2. Verify 2D covariance conic Mahalanobis opacity falloff from splat center }
    AlphaCenter := TCastleShaderGeneratorRHI.EvaluateGaussianSplatOpacity(
      Vector3(2.0, 0.0, 2.0), Vector2(0.0, 0.0), 0.9);
    AlphaNear := TCastleShaderGeneratorRHI.EvaluateGaussianSplatOpacity(
      Vector3(2.0, 0.0, 2.0), Vector2(1.0, 0.0), 0.9);
    AlphaFar := TCastleShaderGeneratorRHI.EvaluateGaussianSplatOpacity(
      Vector3(2.0, 0.0, 2.0), Vector2(5.0, 0.0), 0.9);

    AssertSameValue(0.9, AlphaCenter, 1e-6);
    AssertTrue('Splat opacity must monotonically decay with pixel distance from center',
      (AlphaCenter > AlphaNear) and (AlphaNear > AlphaFar) and (AlphaFar < 0.01));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSphericalHarmonicsL1ViewDependentRadianceRHI;
var
  ColorFront, ColorBack: TVector3;
begin
  { Verify L1 Spherical Harmonics view-dependent specular lobe along +Z vs -Z }
  ColorFront := TCastleShaderGeneratorRHI.EvaluateSphericalHarmonicsL1RGB(
    Vector3(0.0, 0.0, 0.0),
    Vector3(0.0, 0.0, 0.0),
    Vector3(0.0, 0.0, 0.0),
    Vector3(1.0, 0.5, 0.0),
    Vector3(0.0, 0.0, 1.0));
  ColorBack := TCastleShaderGeneratorRHI.EvaluateSphericalHarmonicsL1RGB(
    Vector3(0.0, 0.0, 0.0),
    Vector3(0.0, 0.0, 0.0),
    Vector3(0.0, 0.0, 0.0),
    Vector3(1.0, 0.5, 0.0),
    Vector3(0.0, 0.0, -1.0));

  AssertTrue('Positive SH1Z coefficient must brighten +Z view direction relative to -Z',
    (ColorFront.X > 0.9) and (ColorBack.X < 0.1));
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanGaussianSplatRendererFrontToBackRHI;
var
  Splats: array[0..1] of TGaussianSplatNode;
  ResolvedA, ResolvedB: TVector3;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  AssertEquals('TGaussianSplatNode must be 24 bytes', 24, SizeOf(TGaussianSplatNode));

  { 1. Verify front-to-back Beer-Lambert transmittance compositing }
  Splats[0].ColorRGBA := Vector4(0.0, 1.0, 0.0, 0.8); { Near green splat at depth 1.5 }
  Splats[0].Depth := 1.5;
  Splats[0].SplatID := 0;
  Splats[1].ColorRGBA := Vector4(1.0, 0.0, 0.0, 0.8); { Far red splat at depth 5.0 }
  Splats[1].Depth := 5.0;
  Splats[1].SplatID := 1;
  ResolvedA := TCastleVulkanGaussianSplatRenderer.SortAndCompositeSplatsFrontToBack(
    Splats, Vector3(0.0, 0.0, 0.0));

  { Swap input order }
  Splats[0].ColorRGBA := Vector4(1.0, 0.0, 0.0, 0.8);
  Splats[0].Depth := 5.0;
  Splats[1].ColorRGBA := Vector4(0.0, 1.0, 0.0, 0.8);
  Splats[1].Depth := 1.5;
  ResolvedB := TCastleVulkanGaussianSplatRenderer.SortAndCompositeSplatsFrontToBack(
    Splats, Vector3(0.0, 0.0, 0.0));

  AssertSameValue(ResolvedA.X, ResolvedB.X, 1e-6);
  AssertSameValue(ResolvedA.Y, ResolvedB.Y, 1e-6);
  AssertTrue('Near green splat (alpha=0.8) must dominate over occluded far red splat (G > R)',
    ResolvedA.Y > ResolvedA.X * 4.0);

  { 2. Verify TCastleVulkanGaussianSplatRenderer buffer allocation and tile compute dispatch }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6678)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    CmdList.BeginRecording;
    Device.GaussianSplatRenderer.DispatchGaussianSplatRender(CmdList, 1920, 1080, 10000);
    CmdList.EndRecording;

    AssertTrue('SplatBuffer and SortedKeysBuffer must be allocated',
      (Device.GaussianSplatRenderer.SplatBuffer <> nil) and
      (Device.GaussianSplatRenderer.SortedKeysBuffer <> nil));
    AssertEquals('RenderDispatchCount must be 1', 1, Integer(Device.GaussianSplatRenderer.RenderDispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestPCSSContactHardeningPenumbraWidthRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  PCSSGLSL: String;
  PenumbraContact, PenumbraNear, PenumbraFar: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify PCSS GLSL 450 functions }
    PCSSGLSL := Gen.GeneratePCSSSoftShadowFunctions;
    AssertTrue('PCSS GLSL must include EvaluatePCSSPenumbraWidth',
      Pos('float EvaluatePCSSPenumbraWidth(float receiverDepth, float avgBlockerDepth, float lightSize)', PCSSGLSL) > 0);

    { 2. Verify contact-hardening penumbra width: zero at contact, grows with receiver-blocker separation }
    PenumbraContact := TCastleShaderGeneratorRHI.EvaluatePCSSPenumbraWidth(0.5, 0.5, 0.04);
    PenumbraNear    := TCastleShaderGeneratorRHI.EvaluatePCSSPenumbraWidth(0.6, 0.5, 0.04);
    PenumbraFar     := TCastleShaderGeneratorRHI.EvaluatePCSSPenumbraWidth(0.9, 0.5, 0.04);

    AssertSameValue(0.0, PenumbraContact, 1e-6);
    { (0.6 - 0.5) * 0.04 / 0.5 = 0.008; (0.9 - 0.5) * 0.04 / 0.5 = 0.032 }
    AssertSameValue(0.008, PenumbraNear, 1e-6);
    AssertSameValue(0.032, PenumbraFar, 1e-6);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestDescriptorBufferAlignedOffsetCalculationRHI;
var
  Offset0, Offset1, Offset3: UInt64;
begin
  { Verify VK_EXT_descriptor_buffer 64-byte aligned stride for 100-byte descriptor set -> stride = 128 }
  Offset0 := TCastleShaderGeneratorRHI.ComputeDescriptorBufferAlignedOffset(0, 100, 64);
  Offset1 := TCastleShaderGeneratorRHI.ComputeDescriptorBufferAlignedOffset(1, 100, 64);
  Offset3 := TCastleShaderGeneratorRHI.ComputeDescriptorBufferAlignedOffset(3, 100, 64);

  AssertEquals('Set 0 offset must be 0', Int64(0), Int64(Offset0));
  AssertEquals('Set 1 offset must be 128', Int64(128), Int64(Offset1));
  AssertEquals('Set 3 offset must be 384', Int64(384), Int64(Offset3));
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanDescriptorBufferManagerAllocationAndBindRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6679)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    CmdList.BeginRecording;
    Device.DescriptorBufferManager.BindDescriptorBufferOffset(CmdList, 0, 0);
    Device.DescriptorBufferManager.BindDescriptorBufferOffset(CmdList, 1, 128);
    CmdList.EndRecording;

    AssertTrue('ResourceDescriptorBuffer and SamplerDescriptorBuffer must be allocated',
      (Device.DescriptorBufferManager.ResourceDescriptorBuffer <> nil) and
      (Device.DescriptorBufferManager.SamplerDescriptorBuffer <> nil));
    AssertEquals('BindOffsetsCount must be 2', 2, Integer(Device.DescriptorBufferManager.BindOffsetsCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestCarPaintMultiLayerFlakeBRDFRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  CarPaintGLSL: String;
  FlakeOff, FlakeAligned: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Car-Paint GLSL 450 functions }
    CarPaintGLSL := Gen.GenerateCarPaintFlakeFunctions;
    AssertTrue('Car-Paint GLSL must include EvaluateCarPaintMultiLayerBRDF',
      Pos('vec3 EvaluateCarPaintMultiLayerBRDF(', CarPaintGLSL) > 0);

    { 2. Verify metallic flake glint lobe increases radiance when AFlakeNdotH = 1.0 vs 0.0 }
    FlakeOff := TCastleShaderGeneratorRHI.EvaluateCarPaintMultiLayerBRDF(
      Vector3(0.1, 0.0, 0.8),
      Vector3(0.0, 0.2, 0.5),
      Vector3(0.9, 0.9, 1.0),
      0.8, 0.5, 0.0, 64.0);
    FlakeAligned := TCastleShaderGeneratorRHI.EvaluateCarPaintMultiLayerBRDF(
      Vector3(0.1, 0.0, 0.8),
      Vector3(0.0, 0.2, 0.5),
      Vector3(0.9, 0.9, 1.0),
      0.8, 0.5, 1.0, 64.0);

    AssertTrue('Aligned metallic flake normal must boost car-paint specular radiance',
      FlakeAligned.Z > FlakeOff.Z + 0.5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestScreenSpaceCurvatureCavityShadingRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  CurvatureGLSL: String;
  ConvexEdge, ConcaveCavity: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Screen-Space Curvature GLSL 450 functions }
    CurvatureGLSL := Gen.GenerateScreenSpaceCurvatureFunctions;
    AssertTrue('Curvature GLSL must include EvaluateScreenSpaceCurvatureCavity',
      Pos('float EvaluateScreenSpaceCurvatureCavity(', CurvatureGLSL) > 0);

    { 2. Verify positive normal divergence produces convex edge highlight (> 1.0)
         and negative normal divergence produces concave cavity darkening (< 1.0) }
    ConvexEdge := TCastleShaderGeneratorRHI.EvaluateScreenSpaceCurvatureCavity(
      Vector3(0.3, 0.0, 0.0), Vector3(0.0, 0.3, 0.0), 1.0);
    ConcaveCavity := TCastleShaderGeneratorRHI.EvaluateScreenSpaceCurvatureCavity(
      Vector3(-0.3, 0.0, 0.0), Vector3(0.0, -0.3, 0.0), 1.0);

    AssertSameValue(1.6, ConvexEdge, 1e-6);
    AssertSameValue(0.4, ConcaveCavity, 1e-6);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestAgXChromaGamutCompressionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  AgXGLSL: String;
  InputColor, CompressedColor: TVector3;
  InputLuma, CompressedLuma: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify AgX Gamut Compression GLSL 450 functions }
    AgXGLSL := Gen.GenerateAgXGamutCompressionFunctions;
    AssertTrue('AgX GLSL must include EvaluateChromaGamutCompression',
      Pos('vec3 EvaluateChromaGamutCompression(vec3 linearRGB, float compressionStrength)', AgXGLSL) > 0);

    { 2. Verify intense saturated red (10, 0, 0) compresses toward achromatic luminance while preserving Rec.709 luma }
    InputColor := Vector3(10.0, 0.0, 0.0);
    CompressedColor := TCastleShaderGeneratorRHI.EvaluateChromaGamutCompression(InputColor, 0.8);
    InputLuma := InputColor.X * 0.2126 + InputColor.Y * 0.7152 + InputColor.Z * 0.0722;
    CompressedLuma := CompressedColor.X * 0.2126 + CompressedColor.Y * 0.7152 + CompressedColor.Z * 0.0722;

    AssertSameValue(InputLuma, CompressedLuma, 1e-4);
    AssertTrue('Chroma compression must lift G/B channels and reduce peak R saturation in bright highlights',
      (CompressedColor.X < InputColor.X) and (CompressedColor.Y > 1.0) and (CompressedColor.Z > 1.0));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestCapsuleSoftShadowOcclusionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  CapGLSL: String;
  VisBlocked, VisGrazing, VisClear: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Analytical Capsule Occlusion GLSL 450 functions }
    CapGLSL := Gen.GenerateCapsuleOcclusionFunctions;
    AssertTrue('Capsule GLSL must include EvaluateCapsuleSoftShadowOcclusion',
      Pos('float EvaluateCapsuleSoftShadowOcclusion(', CapGLSL) > 0);

    { 2. Verify ray passing directly through capsule axis is occluded (0.0),
         grazing ray is partially occluded (~0.5), and far offset ray is unoccluded (1.0) }
    VisBlocked := TCastleShaderGeneratorRHI.EvaluateCapsuleSoftShadowOcclusion(
      Vector3(0.0, 0.0, 0.0),
      Vector3(0.0, 0.0, 1.0),
      Vector3(0.0, -1.0, 5.0),
      Vector3(0.0,  1.0, 5.0),
      0.5, 0.05);
    VisGrazing := TCastleShaderGeneratorRHI.EvaluateCapsuleSoftShadowOcclusion(
      Vector3(0.5, 0.0, 0.0),
      Vector3(0.0, 0.0, 1.0),
      Vector3(0.0, -1.0, 5.0),
      Vector3(0.0,  1.0, 5.0),
      0.5, 0.05);
    VisClear := TCastleShaderGeneratorRHI.EvaluateCapsuleSoftShadowOcclusion(
      Vector3(2.0, 0.0, 0.0),
      Vector3(0.0, 0.0, 1.0),
      Vector3(0.0, -1.0, 5.0),
      Vector3(0.0,  1.0, 5.0),
      0.5, 0.05);

    AssertSameValue(0.0, VisBlocked, 1e-5);
    AssertSameValue(0.5, VisGrazing, 1e-5);
    AssertSameValue(1.0, VisClear, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestEpipolarSliceRayStepRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  EpiGLSL: String;
  Step0, StepHalf, Step1: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Epipolar Light Shaft GLSL 450 functions }
    EpiGLSL := Gen.GenerateEpipolarLightShaftFunctions;
    AssertTrue('Epipolar GLSL must include EvaluateEpipolarSliceRayStep',
      Pos('vec2 EvaluateEpipolarSliceRayStep(vec2 lightScreenUV, vec2 sliceEndpointUV, float sliceFraction)', EpiGLSL) > 0);

    { 2. Verify linear radial interpolation from light screen UV (0.2, 0.8) to border UV (1.0, 0.0) }
    Step0    := TCastleShaderGeneratorRHI.EvaluateEpipolarSliceRayStep(Vector2(0.2, 0.8), Vector2(1.0, 0.0), 0.0);
    StepHalf := TCastleShaderGeneratorRHI.EvaluateEpipolarSliceRayStep(Vector2(0.2, 0.8), Vector2(1.0, 0.0), 0.5);
    Step1    := TCastleShaderGeneratorRHI.EvaluateEpipolarSliceRayStep(Vector2(0.2, 0.8), Vector2(1.0, 0.0), 1.0);

    AssertSameValue(0.2, Step0.X, 1e-6);
    AssertSameValue(0.8, Step0.Y, 1e-6);
    AssertSameValue(0.6, StepHalf.X, 1e-6);
    AssertSameValue(0.4, StepHalf.Y, 1e-6);
    AssertSameValue(1.0, Step1.X, 1e-6);
    AssertSameValue(0.0, Step1.Y, 1e-6);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestCooperativeMatrixPreambleAndFP8DecodingRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  CoopGLSL: String;
  ValZero, ValOne, ValNegTwoPointFive: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Cooperative Matrix GLSL 450 preamble }
    CoopGLSL := Gen.GenerateCooperativeMatrixPreamble;
    AssertTrue('Cooperative Matrix preamble must enable GL_KHR_cooperative_matrix',
      Pos('#extension GL_KHR_cooperative_matrix : enable', CoopGLSL) > 0);
    AssertTrue('Cooperative Matrix preamble must include EvaluateQuantizedFP8ToFloat',
      Pos('float EvaluateQuantizedFP8ToFloat(uint fp8Byte)', CoopGLSL) > 0);

    { 2. Verify E4M3 FP8 decoding (bias = 7):
         - 0x00 -> 0.0
         - sign=0, exp=7 (0111), mant=0 (000) -> 0x38 -> +1.0
         - sign=1, exp=8 (1000), mant=2 (010 -> 1 + 2/8 = 1.25) -> 0xC2 -> -1.25 * 2^1 = -2.5 }
    ValZero := TCastleShaderGeneratorRHI.EvaluateQuantizedFP8ToFloat($00);
    ValOne := TCastleShaderGeneratorRHI.EvaluateQuantizedFP8ToFloat($38);
    ValNegTwoPointFive := TCastleShaderGeneratorRHI.EvaluateQuantizedFP8ToFloat($C2);

    AssertSameValue(0.0, ValZero, 1e-6);
    AssertSameValue(1.0, ValOne, 1e-6);
    AssertSameValue(-2.5, ValNegTwoPointFive, 1e-6);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestAnisotropicKuwaharaStructureTensorOrientationRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  KuwaharaGLSL: String;
  AngleHorizontal, AngleDiagonal, AnisoHorizontal, AnisoIsotropic: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Anisotropic Kuwahara Structure-Tensor GLSL 450 functions }
    KuwaharaGLSL := Gen.GenerateAnisotropicKuwaharaFunctions;
    AssertTrue('Kuwahara GLSL must include EvaluateStructureTensorEigenOrientation',
      Pos('vec2 EvaluateStructureTensorEigenOrientation(float jxx, float jyy, float jxy)', KuwaharaGLSL) > 0);

    { 2. Pure X gradient (Jxx=4, Jyy=0, Jxy=0) -> angle = 0, anisotropy = 1.0;
         Isotropic gradient (Jxx=2, Jyy=2, Jxy=0) -> anisotropy = 0.0;
         Diagonal gradient (Jxx=1, Jyy=1, Jxy=1) -> angle = Pi/4 }
    AngleHorizontal := TCastleShaderGeneratorRHI.EvaluateStructureTensorEigenOrientation(
      4.0, 0.0, 0.0, AnisoHorizontal);
    TCastleShaderGeneratorRHI.EvaluateStructureTensorEigenOrientation(
      2.0, 2.0, 0.0, AnisoIsotropic);
    AngleDiagonal := TCastleShaderGeneratorRHI.EvaluateStructureTensorEigenOrientation(
      1.0, 1.0, 1.0, AnisoHorizontal);

    AssertSameValue(0.0, AngleHorizontal, 1e-6);
    AssertSameValue(1.0, AnisoHorizontal, 1e-6);
    AssertSameValue(0.0, AnisoIsotropic, 1e-6);
    AssertSameValue(Pi * 0.25, AngleDiagonal, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanIndirectComputeDispatcherWorkgroupsAndRecordRHI;
var
  WgZero, WgPartial: TVector3Cardinal;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify 1D workgroup count calculation ceil(N / 64) }
  WgZero := TCastleVulkanIndirectComputeDispatcher.ComputeWorkgroupCountsFromItemCount(0, 64);
  WgPartial := TCastleVulkanIndirectComputeDispatcher.ComputeWorkgroupCountsFromItemCount(130, 64);
  AssertEquals('0 active items must produce 0 X workgroups', 0, Integer(WgZero.X));
  AssertEquals('130 active items with workgroup size 64 must produce 3 X workgroups', 3, Integer(WgPartial.X));
  AssertEquals('Y workgroup count must be 1', 1, Integer(WgPartial.Y));
  AssertEquals('Z workgroup count must be 1', 1, Integer(WgPartial.Z));

  { 2. Verify TCastleVulkanIndirectComputeDispatcher buffer creation & DispatchIndirect recording }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($667D)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    CmdList.BeginRecording;
    Device.IndirectComputeDispatcher.RecordIndirectComputeDispatch(CmdList, 2);
    CmdList.EndRecording;

    AssertTrue('IndirectArgumentBuffer must be allocated',
      Device.IndirectComputeDispatcher.IndirectArgumentBuffer <> nil);
    AssertEquals('DispatchedCommandCount must be 1',
      1, Integer(Device.IndirectComputeDispatcher.DispatchedCommandCount));
    AssertEquals('CommandList ComputeDispatchCount must be 1',
      1, Integer(CmdList.ComputeDispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestPhysicalEyeCorneaRefractionUVOffsetRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  EyeGLSL: String;
  OffsetPerp, OffsetOblique: TVector2;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Physical Eye Refraction GLSL 450 functions }
    EyeGLSL := Gen.GeneratePhysicalEyeRefractionFunctions;
    AssertTrue('Eye refraction GLSL must include EvaluateEyeIrisRefractionUVOffset',
      Pos('vec2 EvaluateEyeIrisRefractionUVOffset(', EyeGLSL) > 0);

    { 2. Perpendicular view (0,0,1) along cornea normal (0,0,1) -> zero UV parallax offset;
         Oblique view (0.5, 0.0, 0.866) -> non-zero X parallax offset scaled by anterior chamber depth }
    OffsetPerp := TCastleShaderGeneratorRHI.EvaluateEyeIrisRefractionUVOffset(
      Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0), 1.376, 0.12);
    OffsetOblique := TCastleShaderGeneratorRHI.EvaluateEyeIrisRefractionUVOffset(
      Vector3(0.5, 0.0, 0.8660254), Vector3(0.0, 0.0, 1.0), 1.376, 0.12);

    AssertSameValue(0.0, OffsetPerp.X, 1e-6);
    AssertSameValue(0.0, OffsetPerp.Y, 1e-6);
    AssertTrue('Oblique view must produce negative X refracted iris offset', OffsetOblique.X < -0.02);
    AssertSameValue(0.0, OffsetOblique.Y, 1e-6);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSixPointDirectionalLightmapBasisRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  SixPtGLSL: String;
  ValPosX, ValNegY, ValDiag: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Six-Point Lightmap GLSL 450 functions }
    SixPtGLSL := Gen.GenerateSixPointLightmapFunctions;
    AssertTrue('Six-point lightmap GLSL must include EvaluateSixPointDirectionalBasis',
      Pos('float EvaluateSixPointDirectionalBasis(', SixPtGLSL) > 0);

    { 2. Map values: (+X=1.0, -X=0.2, +Y=0.8), (-Y=0.1, +Z=0.6, -Z=0.0) }
    ValPosX := TCastleShaderGeneratorRHI.EvaluateSixPointDirectionalBasis(
      Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.2, 0.8), Vector3(0.1, 0.6, 0.0));
    ValNegY := TCastleShaderGeneratorRHI.EvaluateSixPointDirectionalBasis(
      Vector3(0.0, -1.0, 0.0), Vector3(1.0, 0.2, 0.8), Vector3(0.1, 0.6, 0.0));
    ValDiag := TCastleShaderGeneratorRHI.EvaluateSixPointDirectionalBasis(
      Vector3(1.0, 1.0, 0.0), Vector3(1.0, 0.2, 0.8), Vector3(0.1, 0.6, 0.0));

    AssertSameValue(1.0, ValPosX, 1e-6);
    AssertSameValue(0.1, ValNegY, 1e-6);
    AssertSameValue(0.9, ValDiag, 1e-6); { 0.5 * 1.0 + 0.5 * 0.8 = 0.9 }
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanBCnCompressorEndpoint565AndDispatchRHI;
var
  White565, Red565, Green565, Blue565: Word;
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify RGB565 BC1 endpoint quantization }
  White565 := TCastleVulkanBCnCompressor.EvaluateBC1EndpointQuantization565(Vector3(1.0, 1.0, 1.0));
  Red565   := TCastleVulkanBCnCompressor.EvaluateBC1EndpointQuantization565(Vector3(1.0, 0.0, 0.0));
  Green565 := TCastleVulkanBCnCompressor.EvaluateBC1EndpointQuantization565(Vector3(0.0, 1.0, 0.0));
  Blue565  := TCastleVulkanBCnCompressor.EvaluateBC1EndpointQuantization565(Vector3(0.0, 0.0, 1.0));

  AssertEquals('White RGB(1,1,1) must quantize to $FFFF', $FFFF, Integer(White565));
  AssertEquals('Pure Red RGB(1,0,0) must quantize to $F800', $F800, Integer(Red565));
  AssertEquals('Pure Green RGB(0,1,0) must quantize to $07E0', $07E0, Integer(Green565));
  AssertEquals('Pure Blue RGB(0,0,1) must quantize to $001F', $001F, Integer(Blue565));

  { 2. Verify TCastleVulkanBCnCompressor 4x4 block count and compute dispatch }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($667E)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    CmdList.BeginRecording;
    Device.BCnCompressor.DispatchBCnBlockCompression(CmdList, 256, 256, 8); { 64x64 = 4096 blocks * 8B = 32768B }
    CmdList.EndRecording;

    AssertTrue('CompressedOutputBuffer must be allocated',
      Device.BCnCompressor.CompressedOutputBuffer <> nil);
    AssertEquals('256x256 texture must produce 4096 4x4 BC1 blocks',
      4096, Integer(Device.BCnCompressor.CompressedBlockCount));
    AssertEquals('CompressedOutputBuffer size must be 32768 bytes',
      Int64(32768), Int64(Device.BCnCompressor.CompressedOutputBuffer.Desc.Size));
    AssertEquals('BCnCompressor DispatchCount must be 1',
      1, Integer(Device.BCnCompressor.DispatchCount));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestSecantRefinedPOMIntersectionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  POMGLSL: String;
  HitMid, HitQuarter: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Secant-Refined POM GLSL 450 functions }
    POMGLSL := Gen.GenerateParallaxOcclusionMappingFunctions;
    AssertTrue('POM GLSL must include EvaluateSecantRefinedPOMIntersection',
      Pos('float EvaluateSecantRefinedPOMIntersection(', POMGLSL) > 0);

    { 2. Verify exact secant root between layer [0.2, 0.4] and height [0.35, 0.25]:
         beforeDepth = 0.35 - 0.20 = +0.15, afterDepth = 0.25 - 0.40 = -0.15 -> midpoint 0.30 }
    HitMid := TCastleShaderGeneratorRHI.EvaluateSecantRefinedPOMIntersection(0.20, 0.40, 0.35, 0.25);
    { beforeDepth = 0.25 - 0.20 = +0.05, afterDepth = 0.25 - 0.40 = -0.15 -> quarter step 0.25 }
    HitQuarter := TCastleShaderGeneratorRHI.EvaluateSecantRefinedPOMIntersection(0.20, 0.40, 0.25, 0.25);

    AssertSameValue(0.30, HitMid, 1e-6);
    AssertSameValue(0.25, HitQuarter, 1e-6);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestCauchyChromaticDispersionRefractiveIndexRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  DispGLSL: String;
  IorRGB: TVector3;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Cauchy Chromatic Dispersion GLSL 450 functions }
    DispGLSL := Gen.GenerateChromaticDispersionFlareFunctions;
    AssertTrue('Chromatic dispersion GLSL must include EvaluateCauchyRefractiveIndexRGB',
      Pos('vec3 EvaluateCauchyRefractiveIndexRGB(float coeffA, float coeffBMicronsSq)', DispGLSL) > 0);

    { 2. Verify normal dispersion order: n(Blue 0.45um) > n(Green 0.55um) > n(Red 0.65um) for B > 0 }
    IorRGB := TCastleShaderGeneratorRHI.EvaluateCauchyRefractiveIndexRGB(1.50, 0.0045);
    AssertTrue('Blue IOR must exceed Green IOR under Cauchy dispersion', IorRGB.Z > IorRGB.Y);
    AssertTrue('Green IOR must exceed Red IOR under Cauchy dispersion', IorRGB.Y > IorRGB.X);
    AssertSameValue(1.50 + 0.0045 / (0.65 * 0.65), IorRGB.X, 1e-5);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestVulkanPipelineBinaryManagerStoreAndLookupRHI;
var
  Key1, Key2: UInt64;
  FoundSize: Cardinal;
  Device: TVulkanRHIDevice;
begin
  { 1. Verify deterministic 64-bit FNV-1a pipeline binary key calculation }
  Key1 := TCastleVulkanPipelineBinaryManager.ComputePipelineKeyFNV1a64($1111, $2222, $03);
  Key2 := TCastleVulkanPipelineBinaryManager.ComputePipelineKeyFNV1a64($1111, $2222, $07);
  AssertTrue('Distinct render state flags must produce distinct pipeline binary keys', Key1 <> Key2);

  { 2. Verify TCastleVulkanPipelineBinaryManager store, update, and lookup telemetry }
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($667F)) );
  try
    Device.PipelineBinaryManager.StorePipelineBinary(Key1, 4096);
    Device.PipelineBinaryManager.StorePipelineBinary(Key2, 8192);
    AssertEquals('BinaryEntryCount must be 2', 2, Integer(Device.PipelineBinaryManager.BinaryEntryCount));
    AssertEquals('TotalBinaryBytes must be 12288', Int64(12288), Int64(Device.PipelineBinaryManager.TotalBinaryBytes));

    AssertTrue('LookupPipelineBinary for Key1 must hit',
      Device.PipelineBinaryManager.LookupPipelineBinary(Key1, FoundSize));
    AssertEquals('FoundSize for Key1 must be 4096', 4096, Integer(FoundSize));
    AssertEquals('CacheHitCount must be 1', 1, Integer(Device.PipelineBinaryManager.CacheHitCount));
  finally
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestViewportExecuteVulkanSubsystemsOrchestrationRHI;
var
  SavedRHI: TRHIDevice;
  Device: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  ExecutedPasses: Cardinal;
begin
  SavedRHI := RHIDevice;
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6680)) );
  Viewport := TCastleViewport.Create(nil);
  try
    SetRHIDevice(Device);
    Viewport.Width := 320;
    Viewport.Height := 180;
    Viewport.ScreenSpaceAmbientOcclusion := True;
    Viewport.ScreenSpaceReflections := True;
    Viewport.VolumetricFogEnabled := True;
    Viewport.GlobalIlluminationMode := giLumenSDFAndSurfaceCache;
    Viewport.TemporalAntiAliasingMode := taaTSRUpscaler;
    Viewport.VariableRateShadingMode := vrsContrastAdaptive;
    Viewport.AutoExposureEnabled := True;
    Viewport.TargetFrameRateHz := 120.0;

    ExecutedPasses := Viewport.ExecuteVulkanViewportSubsystems(nil, 0.005);
    AssertEquals('All 8 enabled Vulkan viewport subsystems must execute', 8, Integer(ExecutedPasses));
    AssertTrue('Hi-Z pyramid must be built', Device.HiZPyramidGenerator.BuildDispatchCount >= 1);
    AssertTrue('GlobalSDF must be built', Device.GlobalSDF.BuildCount >= 1);
    AssertTrue('SurfaceCache AlbedoAtlasTexture must be allocated',
      Device.SurfaceCache.AlbedoAtlasTexture <> nil);
    AssertEquals('TSRUpscaler DispatchCount must be 1', 1, Integer(Device.TSRUpscaler.DispatchCount));
    AssertEquals('VRSManager DispatchCount must be 1', 1, Integer(Device.VRSManager.DispatchCount));
    AssertEquals('AutoExposureHistogram DispatchCount must be 1',
      1, Integer(Device.AutoExposureHistogram.DispatchCount));
    AssertEquals('FramePacer PacedFrameCount must be 1',
      1, Integer(Device.FramePacer.PacedFrameCount));
  finally
    SetRHIDevice(SavedRHI);
    FreeAndNil(Viewport);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestViewportExecuteSceneRenderOptionsSubsystemsRHI;
var
  Device: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  SavedRHI: TRHIDevice;
  ExecutedCount: Cardinal;
begin
  SavedRHI := RHIDevice;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7201)));
  Viewport := TCastleViewport.Create(nil);
  Scene := TCastleScene.Create(nil);
  try
    SetRHIDevice(Device);
    Viewport.Width := 640;
    Viewport.Height := 360;
    Viewport.Items.Add(Scene);

    { 1. Default RenderOptions (all next-gen scene subsystems off) -> 0 passes }
    ExecutedCount := Viewport.ExecuteSceneRenderOptionsSubsystems(Scene.RenderOptions);
    AssertEquals('Default RenderOptions must execute 0 scene subsystems', 0, Integer(ExecutedCount));

    { 2. Enable Meshlet Culling + VSM + WBOIT -> 3 passes }
    Scene.RenderOptions.GpuDrivenMeshletCulling := True;
    Scene.RenderOptions.ShadowMapSystemMode := smsVirtualShadowMaps;
    Scene.RenderOptions.TransparencyMode := tmWeightedBlendedOIT;
    ExecutedCount := Viewport.ExecuteSceneRenderOptionsSubsystems(Scene.RenderOptions);
    AssertEquals('Meshlet + VSM + WBOIT must execute 3 scene subsystems', 3, Integer(ExecutedCount));
    AssertEquals('MeshletCuller DispatchCount must be 1', 1, Integer(Device.MeshletCuller.DispatchCount));
    AssertTrue('VirtualShadowMap AllocatedTileCount must be >= 1', Device.VirtualShadowMap.AllocatedTileCount >= 1);
    AssertTrue('VirtualShadowMap TotalPageUploads must be >= 1', Device.VirtualShadowMap.TotalPageUploads >= 1);
    AssertTrue('WeightedBlendedOIT OITAccumTexture must be allocated',
      Device.WeightedBlendedOIT.OITAccumTexture <> nil);

    { 3. Switch TransparencyMode to PPLL OIT -> dispatches PPLL resolve }
    Scene.RenderOptions.TransparencyMode := tmPerPixelLinkedListOIT;
    ExecutedCount := Viewport.ExecuteSceneRenderOptionsSubsystems(Scene.RenderOptions);
    AssertEquals('Meshlet + VSM + PPLL OIT must execute 3 scene subsystems', 3, Integer(ExecutedCount));
    AssertEquals('PerPixelLinkedListOIT ResolveDispatchCount must be 1',
      1, Integer(Device.PerPixelLinkedListOIT.ResolveDispatchCount));
  finally
    SetRHIDevice(SavedRHI);
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestViewportExecuteAllScenesRenderOptionsSubsystemsTreeRHI;
var
  Device: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  Group: TCastleTransform;
  SceneA, SceneB, HiddenScene: TCastleScene;
  SavedRHI: TRHIDevice;
  TotalPasses: Cardinal;
begin
  SavedRHI := RHIDevice;
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7301)));
  Viewport := TCastleViewport.Create(nil);
  Group := TCastleTransform.Create(Viewport);
  SceneA := TCastleScene.Create(Viewport);
  SceneB := TCastleScene.Create(Viewport);
  HiddenScene := TCastleScene.Create(Viewport);
  try
    SetRHIDevice(Device);
    Viewport.Width := 800;
    Viewport.Height := 600;

    SceneA.RenderOptions.GpuDrivenMeshletCulling := True;
    SceneA.RenderOptions.TransparencyMode := tmWeightedBlendedOIT;

    SceneB.RenderOptions.ShadowMapSystemMode := smsVirtualShadowMaps;
    SceneB.RenderOptions.TransparencyMode := tmPerPixelLinkedListOIT;

    HiddenScene.Exists := False;
    HiddenScene.RenderOptions.GpuDrivenMeshletCulling := True;
    HiddenScene.RenderOptions.ShadowMapSystemMode := smsVirtualShadowMaps;

    Viewport.Items.Add(SceneA);
    Group.Add(SceneB);
    Group.Add(HiddenScene);
    Viewport.Items.Add(Group);

    TotalPasses := Viewport.ExecuteAllScenesRenderOptionsSubsystems(nil);
    AssertEquals('SceneA (2) + SceneB (2) must execute 4 subsystem passes (HiddenScene skipped)',
      4, Integer(TotalPasses));
    AssertEquals('MeshletCuller DispatchCount must be 1', 1, Integer(Device.MeshletCuller.DispatchCount));
    AssertTrue('WeightedBlendedOIT OITAccumTexture must be allocated',
      Device.WeightedBlendedOIT.OITAccumTexture <> nil);
    AssertTrue('VirtualShadowMap AllocatedTileCount must be >= 1',
      Device.VirtualShadowMap.AllocatedTileCount >= 1);
    AssertEquals('PerPixelLinkedListOIT ResolveDispatchCount must be 1',
      1, Integer(Device.PerPixelLinkedListOIT.ResolveDispatchCount));
  finally
    SetRHIDevice(SavedRHI);
    FreeAndNil(Viewport);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHIExperimental.TestExperimentalSubsystemsIsolatedFromCoreRHIUnitsRHI;

  function ReadRawFileText(const AFileName: String): String;
  var
    Stream: TFileStream;
  begin
    Result := '';
    Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size > 0 then
      begin
        SetLength(Result, Stream.Size);
        Stream.ReadBuffer(Result[1], Stream.Size);
      end;
    finally
      FreeAndNil(Stream);
    end;
  end;

  procedure AssertCoreDirectoryFreeOfExperimentalRefs(
    const ARepoRootDir, ARelDir: String; const AForbiddenTokens: array of String);
  var
    FullDir, FileText, LowerExt: String;
    SR: TSearchRec;
    K: Integer;
  begin
    FullDir := ARepoRootDir + StringReplace(ARelDir, '/', PathDelim, [rfReplaceAll]);
    AssertTrue('Core source directory must exist: ' + FullDir, DirectoryExists(FullDir));
    if FindFirst(InclPathDelim(FullDir) + '*', faAnyFile and (not faDirectory), SR) = 0 then
    begin
      try
        repeat
          if (SR.Name = '.') or (SR.Name = '..') then Continue;
          LowerExt := LowerCase(ExtractFileExt(SR.Name));
          if (LowerExt <> '.pas') and (LowerExt <> '.inc') then Continue;
          FileText := ReadRawFileText(InclPathDelim(FullDir) + SR.Name);
          for K := Low(AForbiddenTokens) to High(AForbiddenTokens) do
            AssertEquals(Format('Core engine file %s/%s must NOT reference experimental symbol %s',
              [ARelDir, SR.Name, AForbiddenTokens[K]]),
              0, Pos(AForbiddenTokens[K], FileText));
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
    end;
  end;

const
  ExpectedExpFiles: array[0..8] of String = (
    'src/base_rendering/experimental/README.md',
    'src/base_rendering/experimental/castleinternalshaderrhi_experimental.pas',
    'src/base_rendering/experimental/castleinternalshaderrhi_experimental_types.inc',
    'src/base_rendering/experimental/castleinternalshaderrhi_experimental_pbr_env.inc',
    'src/base_rendering/experimental/castleinternalshaderrhi_experimental_nextgen.inc',
    'src/base_rendering/experimental/castleinternalrhi_vulkan_experimental.pas',
    'src/base_rendering/experimental/castleinternalrhi_vulkan_experimental_types.inc',
    'src/base_rendering/experimental/castleinternalrhi_vulkan_experimental_lighting_gi.inc',
    'src/base_rendering/experimental/castleinternalrhi_vulkan_experimental_gpu_driven.inc'
  );
  ForbiddenExperimentalTokens: array[0..9] of String = (
    'CastleInternalShaderRHI_Experimental',
    'CastleInternalRHI_Vulkan_Experimental',
    'castleinternalshaderrhi_experimental',
    'castleinternalrhi_vulkan_experimental',
    'TCastleVulkanGlobalSDF',
    'TCastleVulkanClusterDAG',
    'TCastleVulkanReSTIR',
    'TCastleVulkanNeuralDenoiser',
    'TCastleVulkanGaussianSplatRenderer',
    'TCastleVulkanXPBDSimulator'
  );
var
  I: Integer;
  RepoRootDir, ExpFilePath, DeletedCoreNextGenPath, SDFGLSL: String;
  ShaderGen: TCastleShaderGeneratorRHI;
  Dev: TVulkanRHIDevice;
  Cmd: TVulkanRHICommandList;
  ExecCount: Cardinal;
begin
  RepoRootDir := ExpandFileName(InclPathDelim(ExtractFilePath(
    ResolveRepoExampleFile('tools/internal/vulkan_upstream_slices/slice_manifest.tsv'))) + '../../..');
  RepoRootDir := InclPathDelim(RepoRootDir);

  { 1. Verify opt-in experimental directory files exist and deleted core nextgen.inc is gone }
  for I := Low(ExpectedExpFiles) to High(ExpectedExpFiles) do
  begin
    ExpFilePath := ResolveRepoExampleFile(ExpectedExpFiles[I]);
    AssertTrue('Experimental file must exist: ' + ExpectedExpFiles[I], FileExists(ExpFilePath));
  end;
  DeletedCoreNextGenPath := ExtractFilePath(
    ResolveRepoExampleFile('src/base_rendering/rhi/castleinternalshaderrhi.pas')) +
    'castleinternalshaderrhi_nextgen.inc';
  AssertFalse('castleinternalshaderrhi_nextgen.inc must be removed from core src/base_rendering/rhi/',
    FileExists(DeletedCoreNextGenPath));

  { 2. Verify zero core engine directories reference experimental units or speculative classes }
  AssertCoreDirectoryFreeOfExperimentalRefs(RepoRootDir, 'src/base_rendering/rhi', ForbiddenExperimentalTokens);
  AssertCoreDirectoryFreeOfExperimentalRefs(RepoRootDir, 'src/base_rendering/vulkan', ForbiddenExperimentalTokens);
  AssertCoreDirectoryFreeOfExperimentalRefs(RepoRootDir, 'src/base_rendering/opengl', ForbiddenExperimentalTokens);
  AssertCoreDirectoryFreeOfExperimentalRefs(RepoRootDir, 'src/scene', ForbiddenExperimentalTokens);
  AssertCoreDirectoryFreeOfExperimentalRefs(RepoRootDir, 'src/window', ForbiddenExperimentalTokens);
  AssertCoreDirectoryFreeOfExperimentalRefs(RepoRootDir, 'src/ui', ForbiddenExperimentalTokens);

  { 3. Verify lazy per-device ExperimentalContext lifecycle, class helpers & callback hooks }
  ShaderGen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    SDFGLSL := ShaderGen.GenerateGlobalSDFTraceFunctions;
    AssertTrue('Experimental shader class helper must emit Global SDF trace GLSL',
      Pos('EvaluateSDFBoxDistance', SDFGLSL) > 0);
  finally
    FreeAndNil(ShaderGen);
  end;

  Dev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($77E0)));
  Cmd := TVulkanRHICommandList.Create(Dev, Dev.GraphicsQueueFamily);
  try
    AssertTrue('Fresh TVulkanRHIDevice must have nil ExperimentalContext until an experimental subsystem is accessed',
      Dev.ExperimentalContext = nil);

    AssertTrue('Dev.GlobalSDF class helper must lazily allocate ExperimentalContext',
      Dev.GlobalSDF <> nil);
    AssertTrue('ExperimentalContext must be non-nil after accessing Dev.GlobalSDF',
      Dev.ExperimentalContext <> nil);
    AssertTrue('Dev.NeuralDenoiser must be accessible via experimental class helper',
      Dev.NeuralDenoiser <> nil);
    AssertTrue('Dev.GaussianSplatRenderer must be accessible via experimental class helper',
      Dev.GaussianSplatRenderer <> nil);

    Cmd.BeginRecording;
    ExecCount := Dev.ExecuteExperimentalViewportSubsystems(Cmd, 320, 240,
      Ord(giLumenSDFAndSurfaceCache), Ord(taaTSRUpscaler), Ord(vrsContrastAdaptive)) +
      Dev.ExecuteExperimentalSceneSubsystems(Cmd, 320, 240,
      Ord(smsVirtualShadowMaps), Ord(tmPerPixelLinkedListOIT));
    Cmd.EndRecording;
    AssertEquals('Experimental viewport + scene callback hooks must execute all 5 requested experimental subsystems',
      5, ExecCount);
  finally
    FreeAndNil(Cmd);
    FreeAndNil(Dev);
  end;
end;

initialization
  RegisterTest(TTestCastleVulkanRHIExperimental);
end.
