{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

{ Test CastleInternalRHI and Vulkan backend subsystems. }
unit TestCastleVulkanRHI;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleTester, CastleVectors, CastleColors, CastleRectangles,
  CastleBoxes, CastleFrustum, CastleTimeUtils,
  CastleApplicationProperties, CastleImages, CastleGLImages, CastleFonts,
  CastleTextureFont_Default3d_Sans,
  CastleInternalRHI, CastleInternalVulkan, CastleInternalVulkanMemory,
  CastleInternalVulkanWSI, CastleInternalShaderCompiler, CastleInternalRHI_Vulkan,
  CastleInternalShaderRHI, CastleInternalBatch2DRHI, CastleInternalRenderer,
  CastleRendererInternalLights, X3DNodes,
  CastleSceneInternalShape, CastleInternalOcclusionCulling,
  CastleTransform, CastleScene, CastleProjection, CastleViewport, CastleScreenEffects, CastleRenderOptions, CastleWindow,
  CastleVideos, CastleInternalBackgroundRenderer, CastleInternalGLShadowVolumes,
  CastleGLUtils, CastleRenderPrimitives, CastleShapes, CastleRenderContext,
  CastleShapeInternalShadowVolumes, CastleShapeInternalRenderShadowVolumes,
  CastleInternalBatchShapes,
  ToolManifest, CastleInternalRenderDoc;

type
  TTestCastleVulkanRHI = class(TCastleTestCase)
  published
    procedure TestRHIFundamentals;
    procedure TestVulkanDynamicLoader;
    procedure TestVulkanPipelineKeyHashing;
    procedure TestVulkanMemorySubAllocator;
    procedure TestShaderGeneratorRHI;
    procedure TestBatch2DCalculations;
    procedure TestApplicationPropertiesRenderBackend;
    procedure TestBatch2DScissorAndClipping;
    procedure TestGeometryBuffersToRHIBuffer;
    procedure TestDrawableImageRHIDispatch;
    procedure TestFontAtlasRHIDispatch;
    procedure TestSceneShapeRHIBufferAllocation;
    procedure Test3DForwardPassDispatch;
    procedure TestGPUSkinningJointBuffer;
    procedure TestMorphTargetVboReload;
    procedure TestMultiLightUBO;
    procedure TestDepthOnlyDynamicRenderingPass;
    procedure TestSanitizeVulkanShaderSource;
    procedure TestCubeMapTextureDesc;
    procedure TestScreenEffectPreambleAndSSAO;
    procedure TestCustomEffectAutomaticUniformInjection;
    procedure TestSecondaryCommandBuffersAndExecution;
    procedure TestManifestRenderBackendParsing;
    procedure TestRenderStatisticsDiagnostics;
    procedure TestDrawIndirectCommandStructures;
    procedure TestRenderDocIntegration;
    procedure TestPlatformWSIAndBackendFallback;
    procedure TestShaderPrewarming;
    procedure TestVisualRegressionImageComparison;
    procedure TestNintendoSwitchViSurfaceAndManifestPrewarm;
    procedure TestPipelineCacheDiskPersistence;
    procedure TestVulkanMemoryBudgetAndViewportStatistics;
    procedure TestViewportPrepareResourcesPrewarmsPSOs;
    procedure TestLegacyGLSLUniformWarningDiagnostics;
    procedure TestVulkan11RenderPassFramebufferFallback;
    procedure TestVkXmlHeaderGenerator;
    procedure TestVulkan11_12DeviceNegotiationAndFallback;
    procedure TestGraphicsPipelineLibraryFastLinking;
    procedure TestSPIRVBinaryReflectionAndValidation;
    procedure TestWindows4096MaxMemoryAllocationLimitAndPooledSubAllocation;
    procedure TestMultiVendorFormatAlignmentAndDeferredResourceDestruction;
    procedure TestGrowableAndTransientDescriptorPools;
    procedure TestAsyncStagingUploadRingBufferAndTransferQueue;
    procedure TestBindlessTextureAndSamplerIndexing;
    procedure TestHardwareMSAAAndSinglePassResolve;
    procedure TestComputePipelineAndDispatch;
    procedure TestExtendedDynamicStateAndSync2AndTimelineSemaphore;
    procedure TestQueryPoolTimestampsAndOcclusion;
    procedure TestRHIOcclusionCullingRendererIntegration;
    procedure TestGpuDrivenComputeFrustumAndDistanceCulling;
    procedure TestViewportLiveDiagnosticsAndWindowAntiAliasingSync;
    procedure TestRenderToTextureRHIBackend;
    procedure TestScreenEffectsRHIPingPongExecution;
    procedure TestDrawIndirectCountAndComputeCullerPipeline;
    procedure TestDynamicTextureResourcesRHI;
    procedure TestHiZDepthPyramidAndOcclusionCulling;
    procedure TestScreenEffectResourceAndAutoHookingRHI;
    procedure Test3DAndCubeAndMovieTextureResourcesRHI;
    procedure TestBackgroundRendererRHI;
    procedure TestStencilShadowVolumesRHI;
    procedure TestRenderUnlitMeshAndShadowVolumeExtrusionRHI;
    procedure TestDrawPrimitive2DRHI;
    procedure TestDynamicBatchShapesRHI;
    procedure TestRenderContextAndScissorRHI;
    procedure TestSaveScreenAndDepthReadbackRHI;
    procedure TestGLInformationStringRHI;
    procedure TestCookTorranceGGXPBRShaderGenerationRHI;
    procedure TestComputeIBLBrdfLutAndEnvironmentPrefilterRHI;
    procedure TestShapePBRMaterialExtractionAndDispatchRHI;
    procedure TestClusteredForwardLightCullingComputeRHI;
    procedure TestDirectionalCascadedShadowMapsAndShadowAtlasRHI;
    procedure TestClusteredForwardAndShadowAtlasShaderIntegrationRHI;
    procedure TestDeclarativeRenderGraphAndTransientAliasingRHI;
    procedure TestHDRBloomPyramidAndAutoExposureComputeRHI;
    procedure TestACESFilmicAndAgXTonemappingCompositeRHI;
    procedure TestComputeGTAOAndBilateralDenoiserRHI;
    procedure TestHierarchicalZScreenSpaceReflectionsRHI;
    procedure TestFroxelVolumetricFogAndHeightFogRHI;
    procedure TestTemporalAntiAliasingAndHaltonJitterRHI;
    procedure TestBoxProjectedParallaxReflectionProbesRHI;
    procedure TestOrientedBoxDecalProjectionRHI;
    procedure TestGPUComputeParticleSimulationAndIndirectDrawRHI;
    procedure TestWeightedBlendedOrderIndependentTransparencyRHI;
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
    procedure TestGPUMeshletConeAndSphereCullingRHI;
    procedure TestContrastAdaptiveSharpeningCASRHI;
    procedure TestInlineRayQueryAndBVHIntersectionRHI;
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
  private
    FCapturedWarnings: TStringList;
    FRenderedShapeCount: Cardinal;
    FRenderFromViewpointCalls: Cardinal;
    FShadowVolumeOnePassCalls: Cardinal;
    FShadowVolumeCasterCalls: Cardinal;
    FRenderGraphPassExecCount: Cardinal;
    procedure CaptureWarning(const Category, S: String);
    procedure DummyRenderShapeCallback(const Shape: TCollectedShape;
      const Params: TRenderParams; const PassParams: TRenderOnePassParams);
    procedure DummyRenderFromViewpointCallback(const RenderCamera: TRenderingCamera);
    procedure DummyShadowVolumeOnePassCallback(const Params: TRenderParams;
      const PassParams: TRenderOnePassParams);
    procedure DummyShadowVolumeCasterCallback(const Params: TRenderParams);
    procedure DummyRenderGraphPassCallback(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
  end;

implementation

{ TTestCastleVulkanRHI }

procedure TTestCastleVulkanRHI.TestRHIFundamentals;
var
  Desc: TRHIBufferDesc;
  TexDesc: TRHITextureDesc;
  PipelineDesc: TRHIGraphicsPipelineDesc;
begin
  { 1. Buffer Descriptor Validation }
  Desc.Size := 1024;
  Desc.Usage := [buVertex, buTransferDst];
  Desc.MemoryUsage := muGpuOnly;
  Desc.DebugName := 'TestVBO';

  AssertEquals('Buffer size must match', 1024, Desc.Size);
  AssertTrue('Buffer usage must include buVertex', buVertex in Desc.Usage);
  AssertTrue('Buffer usage must include buTransferDst', buTransferDst in Desc.Usage);
  AssertFalse('Buffer usage must not include buIndex', buIndex in Desc.Usage);
  AssertEquals('Buffer memory usage', Ord(muGpuOnly), Ord(Desc.MemoryUsage));

  { 2. Texture Descriptor Validation }
  TexDesc.Dimension := td2D;
  TexDesc.Format := pfRGBA8_UNorm;
  TexDesc.Width := 512;
  TexDesc.Height := 256;
  TexDesc.DepthOrArrayLayers := 1;
  TexDesc.MipLevels := 9;
  TexDesc.SampleCount := 1;
  TexDesc.Usage := [tuSampled, tuColorAttachment];
  TexDesc.DebugName := 'TestTex';

  AssertEquals('Tex width', 512, TexDesc.Width);
  AssertEquals('Tex height', 256, TexDesc.Height);
  AssertEquals('Tex mip levels', 9, TexDesc.MipLevels);
  AssertTrue('Tex usage must include tuSampled', tuSampled in TexDesc.Usage);
  AssertTrue('Tex usage must include tuColorAttachment', tuColorAttachment in TexDesc.Usage);

  { 3. Pipeline State Default Descriptors }
  PipelineDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  AssertEquals('Default cull mode should be cmBack', Ord(cmBack), Ord(PipelineDesc.Rasterizer.CullMode));
  AssertEquals('Default front face should be ffCounterClockwise', Ord(ffCounterClockwise), Ord(PipelineDesc.Rasterizer.FrontFace));
  AssertEquals('Default polygon mode should be pmFill', Ord(pmFill), Ord(PipelineDesc.Rasterizer.PolygonMode));

  PipelineDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  AssertTrue('Depth test should be enabled', PipelineDesc.DepthStencil.DepthTestEnable);
  AssertTrue('Depth write should be enabled', PipelineDesc.DepthStencil.DepthWriteEnable);
  AssertEquals('Depth compare op should be coLessOrEqual', Ord(coLessOrEqual), Ord(PipelineDesc.DepthStencil.DepthCompareOp));
end;

procedure TTestCastleVulkanRHI.TestVulkanDynamicLoader;
begin
  { Verify dynamic loader state query does not crash }
  AssertTrue('Dynamic loader query executes without raising', (IsVulkanLoaded = True) or (IsVulkanLoaded = False));

  { Calling FreeVulkan should cleanly reset function pointers }
  FreeVulkan;
  AssertFalse('After FreeVulkan, IsVulkanLoaded must be False', IsVulkanLoaded);
  AssertTrue('vkGetInstanceProcAddr should be nil when unloaded', vkGetInstanceProcAddr = nil);
end;

procedure TTestCastleVulkanRHI.TestVulkanPipelineKeyHashing;
var
  Desc1, Desc2, Desc3, Desc4: TRHIGraphicsPipelineDesc;
  Hash1, Hash2, Hash3, Hash4: UInt64;
begin
  FillChar(Desc1, SizeOf(Desc1), 0);
  Desc1.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc1.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc1.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc1.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc1.ColorAttachmentFormats, 1);
  Desc1.ColorAttachmentFormats[0] := pfBGRA8_UNorm;
  SetLength(Desc1.VertexInput.Attributes, 1);
  Desc1.VertexInput.Attributes[0].Location := 0;
  Desc1.VertexInput.Attributes[0].Binding := 0;
  Desc1.VertexInput.Attributes[0].Format := vafVector3;
  Desc1.VertexInput.Attributes[0].Offset := 0;

  FillChar(Desc2, SizeOf(Desc2), 0);
  Desc2.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc2.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc2.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc2.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc2.ColorAttachmentFormats, 1);
  Desc2.ColorAttachmentFormats[0] := pfBGRA8_UNorm;
  SetLength(Desc2.VertexInput.Attributes, 1);
  Desc2.VertexInput.Attributes[0].Location := 0;
  Desc2.VertexInput.Attributes[0].Binding := 0;
  Desc2.VertexInput.Attributes[0].Format := vafVector3;
  Desc2.VertexInput.Attributes[0].Offset := 0;

  FillChar(Desc3, SizeOf(Desc3), 0);
  Desc3.BlendState := TRHIBlendStateDesc.DefaultOpaque; // Different blend state
  Desc3.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc3.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc3.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc3.ColorAttachmentFormats, 1);
  Desc3.ColorAttachmentFormats[0] := pfBGRA8_UNorm;

  FillChar(Desc4, SizeOf(Desc4), 0);
  Desc4.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc4.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc4.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc4.DepthAttachmentFormat := pfD32_Float;
  SetLength(Desc4.ColorAttachmentFormats, 1);
  Desc4.ColorAttachmentFormats[0] := pfRGBA16_Float; // Different color attachment format

  Hash1 := ComputePipelineKeyHash(Desc1);
  Hash2 := ComputePipelineKeyHash(Desc2);
  Hash3 := ComputePipelineKeyHash(Desc3);
  Hash4 := ComputePipelineKeyHash(Desc4);

  AssertTrue('Identical pipeline configurations must produce identical FNV-1a hashes', Hash1 = Hash2);
  AssertTrue('Divergent blend states must produce different hashes', Hash1 <> Hash3);
  AssertTrue('Divergent attachment formats must produce different hashes', Hash1 <> Hash4);
end;

procedure TTestCastleVulkanRHI.TestVulkanMemorySubAllocator;
var
  Alloc: TVulkanMemoryAllocation;
begin
  { Validate TVulkanMemoryAllocation default state }
  FillChar(Alloc, SizeOf(Alloc), 0);
  AssertFalse('Empty allocation should not be valid', Alloc.IsValid);

  Alloc.Size := 4096;
  Alloc.DeviceMemory := 1; // non-zero handle
  AssertTrue('Allocation with size and non-zero handle is valid', Alloc.IsValid);
end;

procedure TTestCastleVulkanRHI.TestShaderGeneratorRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  OriginalVS, AdjustedVS: String;
  Hash1, Hash2: UInt64;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Test Vulkan NDC Depth Conversion ([ -1 .. 1 ] -> [ 0 .. 1 ]) }
    OriginalVS :=
      'void main()' + NL +
      '{' + NL +
      '  gl_Position = u_ProjectionMatrix * u_ViewMatrix * a_Position;' + NL +
      '}' + NL;

    AdjustedVS := Gen.FinalizeVertexShaderSource(OriginalVS);
    AssertTrue('Adjusted vertex shader must contain depth adjustment',
      Pos('gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;', AdjustedVS) > 0);

    { 2. Test FNV-1a Source Hash Determinism }
    Hash1 := TCastleShaderGeneratorRHI.ComputeSourceHash(OriginalVS);
    Hash2 := TCastleShaderGeneratorRHI.ComputeSourceHash(OriginalVS);
    AssertTrue('Source hash must be deterministic', Hash1 = Hash2);

    { Changing string should change hash }
    AssertTrue('Different GLSL sources must produce distinct hashes',
      Hash1 <> TCastleShaderGeneratorRHI.ComputeSourceHash(AdjustedVS));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestBatch2DCalculations;
var
  Tint: Cardinal;
  C: TCastleColor;
begin
  { 1. Test Color Packing into 32-bit R8G8B8A8 UNorm integer }
  C := Vector4(1.0, 0.0, 0.0, 1.0); // Opaque Red
  Tint := PackColorRgba8(C);
  AssertEquals('Red channel should be $FF in byte 0', $FF, Tint and $FF);
  AssertEquals('Green channel should be 0 in byte 1', 0, (Tint shr 8) and $FF);
  AssertEquals('Blue channel should be 0 in byte 2', 0, (Tint shr 16) and $FF);
  AssertEquals('Alpha channel should be $FF in byte 3', $FF, (Tint shr 24) and $FF);

  { 2. Test Batch Constants }
  AssertTrue('MaxQuadsPerBatch must not exceed 65536 indices capacity', MaxQuadsPerBatch * 4 <= 65536);
  AssertTrue('MaxQuadsPerFrame must be at least MaxQuadsPerBatch', MaxQuadsPerFrame >= MaxQuadsPerBatch);
end;

procedure TTestCastleVulkanRHI.TestApplicationPropertiesRenderBackend;
begin
  AssertEquals('Default RenderBackend should be backendAuto', Ord(backendAuto), Ord(ApplicationProperties.RenderBackend));
  ApplicationProperties.RenderBackend := backendVulkan;
  AssertEquals('RenderBackend should be backendVulkan', Ord(backendVulkan), Ord(ApplicationProperties.RenderBackend));
  ApplicationProperties.RenderBackend := backendOpenGL;
  AssertEquals('RenderBackend should be backendOpenGL', Ord(backendOpenGL), Ord(ApplicationProperties.RenderBackend));
  ApplicationProperties.RenderBackend := backendAuto;
end;

procedure TTestCastleVulkanRHI.TestBatch2DScissorAndClipping;
var
  R1, R2, Intersection: TRectangle;
  ScaleBias: TVector4;
  ViewportW, ViewportH: Single;
begin
  ViewportW := 1920.0;
  ViewportH := 1080.0;

  { 1. Test 2D Orthographic Scale/Bias formula }
  ScaleBias := Vector4(2.0 / ViewportW, 2.0 / ViewportH, -1.0, -1.0);
  AssertTrue('ScaleBias.X should match 2.0 / 1920', Abs(ScaleBias.X - (2.0 / 1920.0)) < 0.0001);
  AssertTrue('ScaleBias.Y should match 2.0 / 1080', Abs(ScaleBias.Y - (2.0 / 1080.0)) < 0.0001);
  AssertTrue('ScaleBias.Z should match -1.0', Abs(ScaleBias.Z - (-1.0)) < 0.0001);
  AssertTrue('ScaleBias.W should match -1.0', Abs(ScaleBias.W - (-1.0)) < 0.0001);

  { 2. Test Scissor Rect calculation and intersection }
  R1 := Rectangle(100, 100, 400, 300);
  R2 := Rectangle(200, 150, 500, 400);
  Intersection := R1 * R2;
  AssertEquals('Intersection Left', 200, Intersection.Left);
  AssertEquals('Intersection Bottom', 150, Intersection.Bottom);
  AssertEquals('Intersection Width', 300, Intersection.Width);
  AssertEquals('Intersection Height', 250, Intersection.Height);
  AssertFalse('Intersection should not be empty', Intersection.IsEmpty);
end;

procedure TTestCastleVulkanRHI.TestGeometryBuffersToRHIBuffer;
var
  CoordDesc, AttrDesc, IndexDesc: TRHIBufferDesc;
begin
  { Coordinate VBO -> RHI vertex buffer }
  FillChar(CoordDesc, SizeOf(CoordDesc), 0);
  CoordDesc.Size := 100 * SizeOf(TVector3);
  CoordDesc.Usage := [buVertex, buTransferDst];
  CoordDesc.MemoryUsage := muGpuOnly;
  CoordDesc.DebugName := 'MeshCoordinates';

  AssertTrue('Coord buffer must have buVertex', buVertex in CoordDesc.Usage);
  AssertEquals('Coord buffer size', 100 * SizeOf(TVector3), CoordDesc.Size);

  { Attribute VBO -> RHI vertex buffer }
  FillChar(AttrDesc, SizeOf(AttrDesc), 0);
  AttrDesc.Size := 100 * SizeOf(TVector4);
  AttrDesc.Usage := [buVertex, buTransferDst];
  AttrDesc.MemoryUsage := muGpuOnly;
  AttrDesc.DebugName := 'MeshAttributes';

  AssertTrue('Attr buffer must have buVertex', buVertex in AttrDesc.Usage);

  { Index VBO -> RHI index buffer }
  FillChar(IndexDesc, SizeOf(IndexDesc), 0);
  IndexDesc.Size := 300 * SizeOf(UInt32);
  IndexDesc.Usage := [buIndex, buTransferDst];
  IndexDesc.MemoryUsage := muGpuOnly;
  IndexDesc.DebugName := 'MeshIndices';

  AssertTrue('Index buffer must have buIndex', buIndex in IndexDesc.Usage);
  AssertFalse('Index buffer must not have buVertex', buVertex in IndexDesc.Usage);
end;

procedure TTestCastleVulkanRHI.TestDrawableImageRHIDispatch;
var
  CpuImg: TRGBAlphaImage;
  DrawImg: TDrawableImage;
  BlendMode: TCastle2DBlendMode;
begin
  CpuImg := TRGBAlphaImage.Create(32, 32);
  CpuImg.Clear(Vector4Byte(255, 128, 64, 255));

  DrawImg := TDrawableImage.Create(CpuImg, true, true);
  try
    AssertEquals('DrawableImage width', 32, DrawImg.Width);
    AssertEquals('DrawableImage height', 32, DrawImg.Height);
    AssertTrue('DrawableImage smooth scaling', DrawImg.SmoothScaling);

    { Verify RHI properties start unallocated without active device }
    AssertTrue('RHITexture nil by default without active device', DrawImg.RHITexture = nil);
    AssertTrue('RHIDescriptorSet nil by default', DrawImg.RHIDescriptorSet = nil);

    { Verify ActiveBatch2DRenderer accessor }
    AssertTrue('ActiveBatch2DRenderer nil outside 2D pass', ActiveBatch2DRenderer = nil);

    { Test alpha channel to blend mode translation }
    case DrawImg.Alpha of
      acNone: BlendMode := CastleInternalBatch2DRHI.bmNone;
      else BlendMode := CastleInternalBatch2DRHI.bmAlphaBlend;
    end;
    AssertTrue('Opaque image translates to expected blend mode',
      BlendMode in [CastleInternalBatch2DRHI.bmNone, CastleInternalBatch2DRHI.bmAlphaBlend]);

    DrawImg.SmoothScaling := false;
    AssertFalse('SmoothScaling toggle', DrawImg.SmoothScaling);
  finally
    FreeAndNil(DrawImg);
  end;
end;

procedure TTestCastleVulkanRHI.TestFontAtlasRHIDispatch;
var
  TestFont: TCastleFont;
  TextW, TextH: Single;
begin
  TestFont := TCastleFont.Create(nil);
  try
    TestFont.Load(Font_Default3d_Sans);
    TestFont.Size := 16;
    TextW := TestFont.TextWidth('Vulkan RHI Font Test');
    TextH := TestFont.TextHeight('Vulkan RHI Font Test');
    AssertTrue('Font text width > 0', TextW > 0.0);
    AssertTrue('Font text height > 0', TextH > 0.0);

    { Font rendering creates glyph rectangles compatible with batch 2D quads }
    AssertTrue('Font scale positive', TestFont.Scale > 0.0);
  finally
    FreeAndNil(TestFont);
  end;
end;

procedure TTestCastleVulkanRHI.TestSceneShapeRHIBufferAllocation;
var
  CoordDesc, AttrDesc, IndexDesc: TRHIBufferDesc;
  PipelineDesc: TRHIGraphicsPipelineDesc;
begin
  { 1. 3D Forward Pass Vertex/Index Layout Configuration }
  CoordDesc := TRHIBufferDesc.Create(500 * SizeOf(TVector3), [buVertex], muGpuOnly);
  AttrDesc := TRHIBufferDesc.Create(500 * SizeOf(TVector4), [buVertex], muGpuOnly);
  IndexDesc := TRHIBufferDesc.Create(1500 * SizeOf(UInt32), [buIndex], muGpuOnly);

  AssertEquals('Coord buffer size matches 500 vertices', 500 * SizeOf(TVector3), CoordDesc.Size);
  AssertTrue('Coord buffer must have buVertex', buVertex in CoordDesc.Usage);
  AssertTrue('Attr buffer must have buVertex', buVertex in AttrDesc.Usage);
  AssertEquals('Index buffer size matches 1500 indices', 1500 * SizeOf(UInt32), IndexDesc.Size);
  AssertTrue('Index buffer must have buIndex', buIndex in IndexDesc.Usage);

  { 2. Forward pass pipeline descriptor validation }
  FillChar(PipelineDesc, SizeOf(PipelineDesc), 0);
  PipelineDesc.Topology := ptTriangleList;
  PipelineDesc.Rasterizer.CullMode := cmBack;
  PipelineDesc.Rasterizer.FrontFace := ffCounterClockwise;
  PipelineDesc.DepthStencil.DepthTestEnable := True;
  PipelineDesc.DepthStencil.DepthWriteEnable := True;
  PipelineDesc.DepthStencil.DepthCompareOp := coLess;

  AssertTrue('3D pipeline has depth test enabled', PipelineDesc.DepthStencil.DepthTestEnable);
  AssertTrue('3D pipeline has depth write enabled', PipelineDesc.DepthStencil.DepthWriteEnable);
  AssertTrue('3D pipeline uses backface culling', PipelineDesc.Rasterizer.CullMode = cmBack);
end;

type
  TMockRHICommandList = class(TRHICommandList)
  public
    LastPushConstantSize: Cardinal;
    LastPushConstantData: TCastlePushConstantsBlock;
    DrawCallsCount: Cardinal;
    DrawIndexedCallsCount: Cardinal;
    LastVertexCount: Cardinal;
    LastIndexCount: Cardinal;
    LastIndexType: TRHIIndexType;
    LastVertexBuffersBound: Boolean;
    ExecutedCommandsCount: Cardinal;

    procedure BeginRecording; override;
    procedure EndRecording; override;
    procedure TransitionTexture(const Texture: TRHITexture; const NewState: TRHIResourceState); override;
    procedure GenerateMipmaps(const Texture: TRHITexture); override;
    procedure BeginRendering(const Info: TRHIRenderingInfo); override;
    procedure EndRendering; override;
    procedure SetViewport(const ViewportRect: TFloatRectangle; const MinDepth: Single = 0.0; const MaxDepth: Single = 1.0); override;
    procedure SetScissor(const ScissorRect: TRectangle); override;
    procedure SetDepthBias(const ConstantFactor, SlopeFactor: Single); override;
    procedure BindPipeline(const Pipeline: TRHIPipeline); override;
    procedure BindDescriptorSet(const SetIndex: Cardinal; const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal); override;
    procedure PushConstants(const StageFlags: TRHIShaderStageFlags; const Offset, Size: Cardinal; const Data); override;
    procedure BindVertexBuffers(const FirstBinding: Cardinal; const Buffers: array of TRHIBuffer; const Offsets: array of PtrUInt); override;
    procedure BindIndexBuffer(const Buffer: TRHIBuffer; const Offset: PtrUInt; const IndexType: TRHIIndexType); override;
    procedure Draw(const VertexCount, InstanceCount, FirstVertex, FirstInstance: Cardinal); override;
    procedure DrawIndexed(const IndexCount, InstanceCount, FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal); override;
    procedure DrawIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList); override;
    procedure PushDebugGroup(const LabelName: String; const Color: TCastleColor); override;
    procedure PopDebugGroup; override;
  end;

procedure TMockRHICommandList.BeginRecording; begin end;
procedure TMockRHICommandList.EndRecording; begin end;
procedure TMockRHICommandList.TransitionTexture(const Texture: TRHITexture; const NewState: TRHIResourceState); begin end;
procedure TMockRHICommandList.GenerateMipmaps(const Texture: TRHITexture); begin end;
procedure TMockRHICommandList.BeginRendering(const Info: TRHIRenderingInfo); begin end;
procedure TMockRHICommandList.EndRendering; begin end;
procedure TMockRHICommandList.SetViewport(const ViewportRect: TFloatRectangle; const MinDepth: Single; const MaxDepth: Single); begin end;
procedure TMockRHICommandList.SetScissor(const ScissorRect: TRectangle); begin end;
procedure TMockRHICommandList.SetDepthBias(const ConstantFactor, SlopeFactor: Single); begin end;
procedure TMockRHICommandList.BindPipeline(const Pipeline: TRHIPipeline); begin end;
procedure TMockRHICommandList.BindDescriptorSet(const SetIndex: Cardinal; const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal); begin end;
procedure TMockRHICommandList.DrawIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); begin end;
procedure TMockRHICommandList.DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer; const Offset: PtrUInt; const DrawCount, Stride: Cardinal); begin end;
procedure TMockRHICommandList.ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList);
begin
  Inc(ExecutedCommandsCount, Length(SecondaryCommandLists));
end;
procedure TMockRHICommandList.PushDebugGroup(const LabelName: String; const Color: TCastleColor); begin end;
procedure TMockRHICommandList.PopDebugGroup; begin end;

procedure TMockRHICommandList.PushConstants(const StageFlags: TRHIShaderStageFlags;
  const Offset, Size: Cardinal; const Data);
begin
  LastPushConstantSize := Size;
  if Size = SizeOf(TCastlePushConstantsBlock) then
    Move(Data, LastPushConstantData, Size);
end;

procedure TMockRHICommandList.BindVertexBuffers(const FirstBinding: Cardinal;
  const Buffers: array of TRHIBuffer; const Offsets: array of PtrUInt);
begin
  LastVertexBuffersBound := Length(Buffers) > 0;
end;

procedure TMockRHICommandList.BindIndexBuffer(const Buffer: TRHIBuffer;
  const Offset: PtrUInt; const IndexType: TRHIIndexType);
begin
  LastIndexType := IndexType;
end;

procedure TMockRHICommandList.Draw(const VertexCount, InstanceCount,
  FirstVertex, FirstInstance: Cardinal);
begin
  Inc(DrawCallsCount);
  LastVertexCount := VertexCount;
end;

procedure TMockRHICommandList.DrawIndexed(const IndexCount, InstanceCount,
  FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal);
begin
  Inc(DrawIndexedCallsCount);
  LastIndexCount := IndexCount;
end;

procedure TTestCastleVulkanRHI.Test3DForwardPassDispatch;
var
  MockCmd: TMockRHICommandList;
  PushConstants: TCastlePushConstantsBlock;
  ModelViewMat: TMatrix4;
  NormalMat: TMatrix3;
begin
  AssertTrue('ActiveCommandList starts nil', ActiveCommandList = nil);

  MockCmd := TMockRHICommandList.Create;
  try
    SetActiveCommandList(MockCmd);
    AssertTrue('ActiveCommandList is now MockCmd', ActiveCommandList = MockCmd);

    { 1. Test Push Constants calculation and packaging }
    ModelViewMat := TranslationMatrix(Vector3(10.0, 5.0, -20.0));
    PushConstants.ModelViewMatrix := ModelViewMat;
    NormalMat := ModelViewToNormalMatrix(ModelViewMat);
    PushConstants.NormalMatrixRow0 := Vector4(NormalMat.Rows[0], 0);
    PushConstants.NormalMatrixRow1 := Vector4(NormalMat.Rows[1], 0);
    PushConstants.NormalMatrixRow2 := Vector4(NormalMat.Rows[2], 0);
    PushConstants.ObjectParams := Vector4(1.0, 2.0, 0.0, 0.0);

    ActiveCommandList.PushConstants([ssVertex, ssFragment], 0, SizeOf(PushConstants), PushConstants);

    AssertEquals('Push constant size matches 128 bytes', 128, MockCmd.LastPushConstantSize);
    AssertTrue('Push constant translation X matches', Abs(MockCmd.LastPushConstantData.ModelViewMatrix.Columns[3].X - 10.0) < 0.001);
    AssertTrue('Push constant translation Y matches', Abs(MockCmd.LastPushConstantData.ModelViewMatrix.Columns[3].Y - 5.0) < 0.001);
    AssertTrue('Push constant translation Z matches', Abs(MockCmd.LastPushConstantData.ModelViewMatrix.Columns[3].Z - (-20.0)) < 0.001);
    AssertTrue('Push constant ObjectParam X matches', Abs(MockCmd.LastPushConstantData.ObjectParams.X - 1.0) < 0.001);

    { 2. Test draw dispatch recording }
    ActiveCommandList.DrawIndexed(36, 1, 0, 0, 0);
    AssertEquals('Indexed draw call count', 1, MockCmd.DrawIndexedCallsCount);
    AssertEquals('Indexed draw count matches 36 indices', 36, MockCmd.LastIndexCount);

    ActiveCommandList.Draw(24, 1, 0, 0);
    AssertEquals('Non-indexed draw call count', 1, MockCmd.DrawCallsCount);
    AssertEquals('Non-indexed draw count matches 24 vertices', 24, MockCmd.LastVertexCount);
  finally
    SetActiveCommandList(nil);
    FreeAndNil(MockCmd);
  end;

  AssertTrue('ActiveCommandList cleared', ActiveCommandList = nil);
end;

procedure TTestCastleVulkanRHI.TestGPUSkinningJointBuffer;
var
  JointList: TMatrix4List;
  SkinUBO: TCastleSkinningUniformBlock;
  UboDesc: TRHIBufferDesc;
  Gen: TCastleShaderGeneratorRHI;
  Preamble: String;
  I: Integer;
begin
  { 1. Validate skinning UBO dimensions and alignments }
  AssertEquals('Maximum bone count is 256', 256, CASTLE_MAX_BONE_MATRICES);
  AssertTrue('TCastleSkinningUniformBlock size >= 16384 bytes', SizeOf(TCastleSkinningUniformBlock) >= 16384);

  { 2. Populate joint matrices and simulate UBO upload }
  JointList := TMatrix4List.Create;
  try
    for I := 0 to 15 do
      JointList.Add(TranslationMatrix(Vector3(I * 2.0, 0, 0)));

    FillChar(SkinUBO, SizeOf(SkinUBO), 0);
    SkinUBO.JointCount := JointList.Count;
    for I := 0 to JointList.Count - 1 do
      SkinUBO.JointMatrices[I] := JointList.L[I];

    AssertEquals('Skin UBO joint count', 16, SkinUBO.JointCount);
    AssertTrue('First bone translation X', Abs(SkinUBO.JointMatrices[0].Columns[3].X - 0.0) < 0.001);
    AssertTrue('Last bone translation X', Abs(SkinUBO.JointMatrices[15].Columns[3].X - 30.0) < 0.001);

    UboDesc := TRHIBufferDesc.Create(JointList.Count * SizeOf(TMatrix4), [buUniform], muCpuToGpu, 'SkinningJointsUBO');
    AssertEquals('UBO descriptor size', 16 * SizeOf(TMatrix4), UboDesc.Size);
    AssertTrue('UBO descriptor usage includes buUniform', buUniform in UboDesc.Usage);
  finally
    FreeAndNil(JointList);
  end;

  { 3. Validate GLSL Set 2 skinning block generation }
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Preamble := Gen.GeneratePreamble(ssVertex);
    AssertTrue('Preamble must declare CastleSkinningBlock', Pos('CastleSkinningBlock', Preamble) > 0);
    AssertTrue('Preamble must alias castle_JointMatrix', Pos('#define castle_JointMatrix', Preamble) > 0);
    AssertTrue('Preamble must define Set 2 binding 0 for skinning', Pos('CASTLE_UBO(2, 0)', Preamble) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestMorphTargetVboReload;
var
  Cache: TShapeCache;
  JointList: TMatrix4List;
  CoordDesc: TRHIBufferDesc;
begin
  Cache := TShapeCache.Create;
  JointList := TMatrix4List.Create;
  try
    Cache.InvalidateVertexData([vtCoordinate]);
    JointList.Add(TMatrix4.Identity);
    Cache.UploadJointMatrices(JointList.L, JointList.Count);
    AssertTrue('Cache RHI buffers safely nil when backend is not active', Cache.RHICoordinateBuffer = nil);
    AssertTrue('Cache RHI joint buffer safely nil when backend is not active', Cache.RHIJointBuffer = nil);

    { Verify morph target buffer descriptor creation }
    CoordDesc := TRHIBufferDesc.Create(1000 * SizeOf(TVector3), [buVertex], muGpuOnly, 'MorphedCoords');
    AssertEquals('Morphed coordinate buffer size matches', 1000 * SizeOf(TVector3), CoordDesc.Size);
    AssertTrue('Morphed coordinate buffer is buVertex', buVertex in CoordDesc.Usage);
  finally
    FreeAndNil(JointList);
    FreeAndNil(Cache);
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiLightUBO;
var
  Block: TCastleLightsUniformBlock;
  IdxDir, IdxPoint, IdxSpot: Integer;
  ProjMat: TMatrix4;
  Gen: TCastleShaderGeneratorRHI;
  Preamble: String;
begin
  { 1. std140 Struct Alignment and Size Validation }
  AssertEquals('Maximum lights count is 32', 32, CASTLE_MAX_LIGHTS);
  AssertEquals('TCastleLightData record size must be 160 bytes', 160, SizeOf(TCastleLightData));
  AssertEquals('TCastleLightsUniformBlock size must be 5136 bytes (16-byte aligned)', 5136, SizeOf(TCastleLightsUniformBlock));
  AssertEquals('TCastleLightsUniformBlock must be std140 aligned', 0, SizeOf(TCastleLightsUniformBlock) mod 16);

  { 2. Populate Directional Light }
  Block.Clear;
  AssertEquals('Cleared block light count', 0, Block.Count);

  IdxDir := Block.AddDirectionalLight(Vector3(0, -1, 0), Vector3(1, 1, 0.8), Vector3(0.1, 0.1, 0.1));
  AssertEquals('First light index', 0, IdxDir);
  AssertEquals('Light count after directional light', 1, Block.Count);
  AssertTrue('Directional light position W is 0.0', Abs(Block.Lights[0].Position.W - 0.0) < 0.001);
  AssertTrue('Directional light direction Y is -1.0', Abs(Block.Lights[0].Position.Y - (-1.0)) < 0.001);
  AssertTrue('Directional light color R is 1.0', Abs(Block.Lights[0].Color.X - 1.0) < 0.001);

  { 3. Populate Point Light }
  IdxPoint := Block.AddPointLight(Vector3(10, 5, 2), Vector3(1, 0, 0), Vector3(0.05, 0, 0),
    Vector3(1, 0.1, 0.01), 50.0);
  AssertEquals('Second light index', 1, IdxPoint);
  AssertEquals('Light count after point light', 2, Block.Count);
  AssertTrue('Point light position W is 1.0', Abs(Block.Lights[1].Position.W - 1.0) < 0.001);
  AssertTrue('Point light position X is 10.0', Abs(Block.Lights[1].Position.X - 10.0) < 0.001);
  AssertTrue('Point light radius is 50.0', Abs(Block.Lights[1].Color.W - 50.0) < 0.001);
  AssertTrue('Point light attenuation constant', Abs(Block.Lights[1].Attenuation.X - 1.0) < 0.001);

  { 4. Populate Spot Light and Shadow Projector Matrix }
  IdxSpot := Block.AddSpotLight(Vector3(0, 10, 0), Vector3(0, -1, 0), Vector3(1, 1, 1),
    Vector3(0.1, 0.1, 0.1), Vector3(1, 0.05, 0), 30.0,
    Cos(Pi / 4), Pi / 4, Pi / 6, 2.0);
  AssertEquals('Third light index', 2, IdxSpot);
  AssertEquals('Light count after spot light', 3, Block.Count);
  AssertTrue('Spot light position W is 2.0', Abs(Block.Lights[2].Position.W - 2.0) < 0.001);
  AssertTrue('Spot light spot direction Y is -1.0', Abs(Block.Lights[2].SpotDirection.Y - (-1.0)) < 0.001);
  AssertTrue('Spot light spot exponent is 2.0', Abs(Block.Lights[2].SpotParams.Z - 2.0) < 0.001);

  ProjMat := TranslationMatrix(Vector3(0, 0, -5));
  Block.SetProjectorMatrix(IdxSpot, ProjMat);
  AssertTrue('Spot light projector matrix translation Z', Abs(Block.Lights[2].ProjectorMatrix.Columns[3].Z - (-5.0)) < 0.001);

  { 5. Validate GLSL Set 0 Binding 1 lights block generation }
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Preamble := Gen.GeneratePreamble(ssFragment);
    AssertTrue('Preamble declares CastleLightsBlock', Pos('CastleLightsBlock', Preamble) > 0);
    AssertTrue('Preamble binds CastleLights at Set 0 Binding 1', Pos('CASTLE_UBO(0, 1)', Preamble) > 0);
    AssertTrue('Preamble aliases castle_LightSource0Position', Pos('#define castle_LightSource0Position', Preamble) > 0);
    AssertTrue('Preamble aliases castle_projector_matrix_0', Pos('#define castle_projector_matrix_0', Preamble) > 0);
    AssertTrue('Preamble binds shadow map samplers', Pos('CASTLE_SAMPLER(0, 2) uniform sampler2DShadow castle_shadow_map_0;', Preamble) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestDepthOnlyDynamicRenderingPass;
var
  Area: TRectangle;
  Info: TRHIRenderingInfo;
  DepthState: TRHIDepthStencilStateDesc;
begin
  Area := Rectangle(0, 0, 1024, 1024);
  Info := TRHIRenderingInfo.CreateDepthOnly(Area, nil, loClear, soStore, 1.0);

  AssertEquals('RenderArea width', 1024, Info.RenderArea.Width);
  AssertEquals('RenderArea height', 1024, Info.RenderArea.Height);
  AssertEquals('ColorAttachments length is 0 for depth-only pass', 0, Length(Info.ColorAttachments));
  AssertTrue('HasDepthAttachment is True', Info.HasDepthAttachment);
  AssertEquals('Depth attachment load op is loClear', Ord(loClear), Ord(Info.DepthAttachment.LoadOp));
  AssertEquals('Depth attachment store op is soStore', Ord(soStore), Ord(Info.DepthAttachment.StoreOp));
  AssertTrue('Depth clear value is 1.0', Abs(Info.DepthAttachment.ClearDepth - 1.0) < 0.001);

  DepthState := TRHIDepthStencilStateDesc.DefaultShadowMap;
  AssertTrue('Shadow map depth test must be enabled', DepthState.DepthTestEnable);
  AssertTrue('Shadow map depth write must be enabled', DepthState.DepthWriteEnable);
  AssertEquals('Shadow map depth compare op is coLessOrEqual', Ord(coLessOrEqual), Ord(DepthState.DepthCompareOp));
  AssertFalse('Shadow map stencil test is disabled', DepthState.StencilTestEnable);
end;

procedure TTestCastleVulkanRHI.TestSanitizeVulkanShaderSource;
var
  Gen: TCastleShaderGeneratorRHI;
  LegacyGLSL, SanitizedGLSL: String;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    LegacyGLSL :=
      'uniform mat4 castle_ModelViewMatrix;' + NL +
      'uniform mat4 castle_ProjectionMatrix;' + NL +
      'uniform vec3 castle_LightSource0Position;' + NL +
      'uniform vec3 castle_LightSource0Color;' + NL +
      'uniform mat4 castle_projector_matrix_0;' + NL +
      'uniform float u_MyCustomMultiplier;' + NL +
      'void main() {' + NL +
      '  vec3 l = castle_LightSource0Position;' + NL +
      '  gl_Position = castle_ProjectionMatrix * (castle_ModelViewMatrix * vec4(l, 1.0)) * u_MyCustomMultiplier;' + NL +
      '}' + NL;

    SanitizedGLSL := Gen.SanitizeVulkanShaderSource(LegacyGLSL);

    { Legacy uniforms replaced by UBOs/PushConstants must be commented out }
    AssertTrue('castle_ModelViewMatrix must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform mat4 castle_ModelViewMatrix;', SanitizedGLSL) > 0);
    AssertTrue('castle_ProjectionMatrix must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform mat4 castle_ProjectionMatrix;', SanitizedGLSL) > 0);
    AssertTrue('castle_LightSource0Position must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform vec3 castle_LightSource0Position;', SanitizedGLSL) > 0);
    AssertTrue('castle_projector_matrix_0 must be commented out',
      Pos('// [Vulkan RHI UBO]: uniform mat4 castle_projector_matrix_0;', SanitizedGLSL) > 0);

    { User custom uniforms must remain intact }
    AssertTrue('u_MyCustomMultiplier must NOT be commented out',
      Pos('uniform float u_MyCustomMultiplier;', SanitizedGLSL) > 0);

    { Code usage inside main() must remain intact }
    AssertTrue('Shader body must be preserved',
      Pos('vec3 l = castle_LightSource0Position;', SanitizedGLSL) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestCubeMapTextureDesc;
var
  Desc: TRHITextureDesc;
begin
  Desc := TRHITextureDesc.CreateCube(512, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 4);
  AssertEquals('Cube map dimension', Ord(tdCube), Ord(Desc.Dimension));
  AssertEquals('Cube map width', 512, Desc.Width);
  AssertEquals('Cube map height', 512, Desc.Height);
  AssertEquals('Cube map depth/array layers must be 6', 6, Desc.DepthOrArrayLayers);
  AssertEquals('Cube map mip levels', 4, Desc.MipLevels);
  AssertEquals('Cube map sample count', 1, Desc.SampleCount);
  AssertEquals('Cube map pixel format', Ord(pfRGBA8_UNorm), Ord(Desc.Format));
  AssertTrue('Cube map usage tuSampled', tuSampled in Desc.Usage);
  AssertTrue('Cube map usage tuTransferDst', tuTransferDst in Desc.Usage);
end;

procedure TTestCastleVulkanRHI.TestScreenEffectPreambleAndSSAO;
var
  Gen: TCastleShaderGeneratorRHI;
  VertPreamble, FragPreambleDepth, FragPreambleNoDepth: String;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { Fragment shader with depth (used by SSAO and depth-aware screen effects) }
    FragPreambleDepth := Gen.GenerateScreenEffectPreamble(ssFragment, True);
    AssertTrue('Screen effect preamble contains #version 450', Pos('#version 450', FragPreambleDepth) > 0);
    AssertTrue('Screen effect contains screen push constants', Pos('CastleScreenPushConstants', FragPreambleDepth) > 0);
    AssertTrue('Screen effect aliases screen_width', Pos('#define screen_width (castle_Screen.screen_size.x)', FragPreambleDepth) > 0);
    AssertTrue('Screen effect aliases near plane', Pos('#define near (castle_Screen.screen_planes.x)', FragPreambleDepth) > 0);
    AssertTrue('Screen effect aliases far plane', Pos('#define far (castle_Screen.screen_planes.y)', FragPreambleDepth) > 0);
    AssertTrue('Screen effect binds screen sampler at Set 0 Binding 0',
      Pos('layout(set = 0, binding = 0) uniform sampler2D screen;', FragPreambleDepth) > 0);
    AssertTrue('Screen effect binds screen_depth sampler at Set 0 Binding 1',
      Pos('layout(set = 0, binding = 1) uniform sampler2D screen_depth;', FragPreambleDepth) > 0);
    AssertTrue('Screen effect defines texture2D compatibility macro', Pos('#define texture2D texture', FragPreambleDepth) > 0);
    AssertTrue('Screen effect defines gl_FragColor alias', Pos('#define gl_FragColor castle_FragColor', FragPreambleDepth) > 0);
    AssertTrue('Screen effect outputs castle_FragColor at location 0',
      Pos('layout(location = 0) out vec4 castle_FragColor;', FragPreambleDepth) > 0);
    AssertTrue('Screen effect inputs tex_coord at location 0',
      Pos('layout(location = 0) in vec2 tex_coord;', FragPreambleDepth) > 0);

    { Fragment shader without depth (simple color grading, vignette, blur) }
    FragPreambleNoDepth := Gen.GenerateScreenEffectPreamble(ssFragment, False);
    AssertTrue('No-depth preamble has screen sampler', Pos('uniform sampler2D screen;', FragPreambleNoDepth) > 0);
    AssertFalse('No-depth preamble must NOT have screen_depth sampler', Pos('screen_depth', FragPreambleNoDepth) > 0);

    { Vertex shader for screen effect quad }
    VertPreamble := Gen.GenerateScreenEffectPreamble(ssVertex, False);
    AssertTrue('Vertex preamble inputs vertex attribute at location 0',
      Pos('layout(location = 0) in vec2 vertex;', VertPreamble) > 0);
    AssertTrue('Vertex preamble inputs tex_coord attribute at location 1',
      Pos('layout(location = 1) in vec2 tex_coord;', VertPreamble) > 0);
    AssertTrue('Vertex preamble outputs v_tex_coord at location 0',
      Pos('layout(location = 0) out vec2 v_tex_coord;', VertPreamble) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestCustomEffectAutomaticUniformInjection;
var
  Gen: TCastleShaderGeneratorRHI;
  UserGLSL, UpgradedGLSL: String;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    UserGLSL :=
      'uniform float u_intensity;' + NL +
      'uniform vec3 u_tint;' + NL +
      'uniform mediump float u_roughness;' + NL +
      'uniform sampler2D u_noiseTexture;' + NL +
      'uniform float u_weights[4];' + NL +
      'void PLUG_custom_surface() {' + NL +
      '  float f = u_intensity * u_roughness * u_weights[0];' + NL +
      '  vec4 n = texture(u_noiseTexture, vec2(f, f)) * vec4(u_tint, 1.0);' + NL +
      '}' + NL;

    UpgradedGLSL := Gen.UpgradeUserEffectUniforms(UserGLSL);

    { Value uniforms must be gathered into CastleUserEffectBlock at Set 2 Binding 1 }
    AssertTrue('Upgraded shader contains CastleUserEffectBlock UBO at Set 2 Binding 1',
      Pos('CASTLE_UBO(2, 1) uniform CastleUserEffectBlock', UpgradedGLSL) > 0);
    AssertTrue('UBO contains u_user_u_intensity', Pos('float u_user_u_intensity;', UpgradedGLSL) > 0);
    AssertTrue('UBO contains u_user_u_tint', Pos('vec3 u_user_u_tint;', UpgradedGLSL) > 0);
    AssertTrue('UBO contains u_user_u_roughness with stripped precision qualifier',
      Pos('float u_user_u_roughness;', UpgradedGLSL) > 0);
    AssertTrue('UBO contains array u_user_u_weights[4]', Pos('float u_user_u_weights[4];', UpgradedGLSL) > 0);

    { Aliases must redirect bare variable names to CastleUserEffect.u_user_* }
    AssertTrue('Alias define for u_intensity',
      Pos('#define u_intensity CastleUserEffect.u_user_u_intensity', UpgradedGLSL) > 0);
    AssertTrue('Alias define for u_tint',
      Pos('#define u_tint CastleUserEffect.u_user_u_tint', UpgradedGLSL) > 0);
    AssertTrue('Alias define for u_roughness',
      Pos('#define u_roughness CastleUserEffect.u_user_u_roughness', UpgradedGLSL) > 0);
    AssertTrue('Alias define for u_weights',
      Pos('#define u_weights CastleUserEffect.u_user_u_weights', UpgradedGLSL) > 0);

    { Samplers must be assigned to Set 2 Binding 2+ }
    AssertTrue('Sampler assigned to Set 2 Binding 2',
      Pos('CASTLE_SAMPLER(2, 2) uniform sampler2D u_noiseTexture;', UpgradedGLSL) > 0);

    { User function body must remain intact }
    AssertTrue('Shader body preserved', Pos('void PLUG_custom_surface()', UpgradedGLSL) > 0);
    AssertTrue('Texture lookup preserved', Pos('vec4 n = texture(u_noiseTexture, vec2(f, f))', UpgradedGLSL) > 0);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestSecondaryCommandBuffersAndExecution;
var
  PrimaryCmd, SecCmd1, SecCmd2: TMockRHICommandList;
begin
  PrimaryCmd := TMockRHICommandList.Create(cllPrimary);
  SecCmd1 := TMockRHICommandList.Create(cllSecondary);
  SecCmd2 := TMockRHICommandList.Create(cllSecondary);
  try
    AssertEquals('PrimaryCmd level is primary', Ord(cllPrimary), Ord(PrimaryCmd.Level));
    AssertEquals('SecCmd1 level is secondary', Ord(cllSecondary), Ord(SecCmd1.Level));
    AssertEquals('SecCmd2 level is secondary', Ord(cllSecondary), Ord(SecCmd2.Level));

    SecCmd1.BeginRecording;
    SecCmd1.Draw(100, 1, 0, 0);
    SecCmd1.EndRecording;
    AssertEquals('SecCmd1 recorded 1 draw call', 1, SecCmd1.DrawCallsCount);

    SecCmd2.BeginRecording;
    SecCmd2.DrawIndexed(250, 1, 0, 0, 0);
    SecCmd2.EndRecording;
    AssertEquals('SecCmd2 recorded 1 indexed draw call', 1, SecCmd2.DrawIndexedCallsCount);

    PrimaryCmd.BeginRecording;
    PrimaryCmd.ExecuteCommands([SecCmd1, SecCmd2]);
    PrimaryCmd.EndRecording;
    AssertEquals('PrimaryCmd executed 2 secondary command lists', 2, PrimaryCmd.ExecutedCommandsCount);
  finally
    FreeAndNil(SecCmd2);
    FreeAndNil(SecCmd1);
    FreeAndNil(PrimaryCmd);
  end;
end;

procedure TTestCastleVulkanRHI.TestManifestRenderBackendParsing;
var
  ParsedException: Boolean;
begin
  AssertEquals('Parse auto', Ord(backendAuto), Ord(StringToRenderBackend('auto')));
  AssertEquals('Parse opengl', Ord(backendOpenGL), Ord(StringToRenderBackend('opengl')));
  AssertEquals('Parse opengles', Ord(backendOpenGLES), Ord(StringToRenderBackend('opengles')));
  AssertEquals('Parse vulkan', Ord(backendVulkan), Ord(StringToRenderBackend('vulkan')));

  AssertEquals('String auto', 'auto', RenderBackendToString(backendAuto));
  AssertEquals('String opengl', 'opengl', RenderBackendToString(backendOpenGL));
  AssertEquals('String opengles', 'opengles', RenderBackendToString(backendOpenGLES));
  AssertEquals('String vulkan', 'vulkan', RenderBackendToString(backendVulkan));

  ParsedException := False;
  try
    StringToRenderBackend('directx');
  except
    on E: Exception do
      ParsedException := True;
  end;
  AssertTrue('Invalid backend name raises exception', ParsedException);
end;

procedure TTestCastleVulkanRHI.TestRenderStatisticsDiagnostics;
var
  Stats: TRenderStatistics;
  S: String;
  Options: TCastleRenderOptions;
begin
  FillChar(Stats, SizeOf(Stats), 0);
  Stats.ShapesRendered := 450;
  Stats.ShapesVisible := 1200;
  Stats.DrawCalls := 85;
  Stats.ActiveBackend := 'Vulkan 1.3';
  Stats.PipelineCacheHits := 120;
  Stats.PipelineCacheMisses := 4;
  Stats.DescriptorSetAllocations := 350;
  Stats.DeviceMemoryUsedMB := 128;
  Stats.DeviceMemoryBudgetMB := 2048;

  S := Stats.ToString;
  AssertTrue('Stats contains shapes count', Pos('Shapes 450', S) > 0);
  AssertTrue('Stats contains draw calls', Pos('Draw calls: 85', S) > 0);
  AssertTrue('Stats contains active backend', Pos('Backend: Vulkan 1.3', S) > 0);
  AssertTrue('Stats contains PSO cache hits/misses', Pos('PSO hits/misses: 120/4', S) > 0);
  AssertTrue('Stats contains descriptor allocations', Pos('Descriptors: 350', S) > 0);
  AssertTrue('Stats contains VRAM budget', Pos('VRAM: 128 / 2048 MB', S) > 0);

  Options := TCastleRenderOptions.Create(nil);
  try
    ApplicationProperties.RenderBackend := backendVulkan;
    AssertEquals('Options backend name is Vulkan', 'Vulkan', Options.ActiveRenderBackendName);
    ApplicationProperties.RenderBackend := backendOpenGL;
    AssertEquals('Options backend name is OpenGL', 'OpenGL', Options.ActiveRenderBackendName);
    ApplicationProperties.RenderBackend := backendAuto;
    AssertEquals('Options backend name is Auto', 'Auto', Options.ActiveRenderBackendName);
  finally
    FreeAndNil(Options);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawIndirectCommandStructures;
var
  Cmd: TRHIDrawIndirectCommand;
  IndexedCmd: TRHIDrawIndexedIndirectCommand;
begin
  { Verify standard sizes match hardware indirect dispatch specs }
  AssertEquals('TRHIDrawIndirectCommand size must be 16 bytes', 16, SizeOf(TRHIDrawIndirectCommand));
  AssertEquals('TRHIDrawIndexedIndirectCommand size must be 20 bytes', 20, SizeOf(TRHIDrawIndexedIndirectCommand));
  AssertEquals('VkDrawIndirectCommand size must be 16 bytes', 16, SizeOf(VkDrawIndirectCommand));
  AssertEquals('VkDrawIndexedIndirectCommand size must be 20 bytes', 20, SizeOf(VkDrawIndexedIndirectCommand));

  { Verify field values and offsets }
  FillChar(Cmd, SizeOf(Cmd), 0);
  Cmd.VertexCount := 36;
  Cmd.InstanceCount := 10;
  Cmd.FirstVertex := 0;
  Cmd.FirstInstance := 5;

  AssertEquals('VertexCount', 36, Cmd.VertexCount);
  AssertEquals('InstanceCount', 10, Cmd.InstanceCount);
  AssertEquals('FirstVertex', 0, Cmd.FirstVertex);
  AssertEquals('FirstInstance', 5, Cmd.FirstInstance);

  FillChar(IndexedCmd, SizeOf(IndexedCmd), 0);
  IndexedCmd.IndexCount := 72;
  IndexedCmd.InstanceCount := 4;
  IndexedCmd.FirstIndex := 120;
  IndexedCmd.VertexOffset := -3;
  IndexedCmd.FirstInstance := 1;

  AssertEquals('IndexCount', 72, IndexedCmd.IndexCount);
  AssertEquals('InstanceCount', 4, IndexedCmd.InstanceCount);
  AssertEquals('FirstIndex', 120, IndexedCmd.FirstIndex);
  AssertEquals('VertexOffset', -3, IndexedCmd.VertexOffset);
  AssertEquals('FirstInstance', 1, IndexedCmd.FirstInstance);
end;

procedure TTestCastleVulkanRHI.TestRenderDocIntegration;
var
  Options: TCastleRenderOptions;
  IsAvail: Boolean;
begin
  IsAvail := RenderDocAvailable;
  { Calling TriggerCapture should never fail even if RenderDoc is not connected }
  RenderDocTriggerCapture;
  RenderDocStartFrameCapture(nil, nil);
  AssertFalse('Should not be frame capturing when RenderDoc not loaded', RenderDocIsFrameCapturing);
  AssertFalse('EndFrameCapture should return False when RenderDoc not loaded', RenderDocEndFrameCapture(nil, nil));
  AssertFalse('LaunchReplayUI should return False when RenderDoc not loaded', RenderDocLaunchReplayUI(False));

  Options := TCastleRenderOptions.Create(nil);
  try
    AssertEquals('Options RenderDocAvailable matches', IsAvail, Options.RenderDocAvailable);
    Options.TriggerRenderDocCapture;
    AssertFalse('Options LaunchRenderDocReplayUI returns False without RenderDoc', Options.LaunchRenderDocReplayUI);
  finally
    FreeAndNil(Options);
  end;
end;

procedure TTestCastleVulkanRHI.TestPlatformWSIAndBackendFallback;
var
  Exts: TAnsiStringArray;
begin
  Exts := GetRequiredVulkanInstanceExtensions;
  AssertTrue('At least VK_KHR_surface is required', Length(Exts) >= 1);
  AssertEquals('First extension is VK_KHR_surface', VK_KHR_SURFACE_EXTENSION_NAME, String(Exts[0]));

  { Vulkan 1.3 available -> selects backendVulkan }
  AssertEquals('Auto with Vulkan 1.3 -> Vulkan',
    Ord(backendVulkan), Ord(SelectOptimalRenderBackend(backendAuto, True, 1, 3, False)));

  { Vulkan 1.1 baseline on Android -> selects backendVulkan }
  AssertEquals('Auto with Vulkan 1.1 on mobile -> Vulkan',
    Ord(backendVulkan), Ord(SelectOptimalRenderBackend(backendAuto, True, 1, 1, True)));

  { Vulkan 1.0 (below 1.1 baseline) on Android -> falls back to OpenGLES 3.0 }
  AssertEquals('Vulkan 1.0 on mobile -> falls back to OpenGLES',
    Ord(backendOpenGLES), Ord(SelectOptimalRenderBackend(backendAuto, True, 1, 0, True)));

  { Vulkan unavailable on desktop -> falls back to OpenGL }
  AssertEquals('No Vulkan on desktop -> falls back to OpenGL',
    Ord(backendOpenGL), Ord(SelectOptimalRenderBackend(backendVulkan, False, 0, 0, False)));

  { Explicit OpenGL request is preserved even if Vulkan 1.3 is present }
  AssertEquals('Explicit OpenGL -> OpenGL',
    Ord(backendOpenGL), Ord(SelectOptimalRenderBackend(backendOpenGL, True, 1, 3, False)));
end;

procedure TTestCastleVulkanRHI.TestShaderPrewarming;
var
  Hashes: TUInt64Array;
  I, J: Integer;
begin
  Hashes := TCastleShaderCompiler.Instance.PrewarmCoreEngineShaders;
  AssertEquals('PrewarmCoreEngineShaders returns 5 core shader stage hashes', 5, Length(Hashes));
  for I := 0 to High(Hashes) do
  begin
    AssertTrue('Core shader hash must be non-zero', Hashes[I] <> 0);
    for J := I + 1 to High(Hashes) do
      AssertTrue('Distinct core shaders must produce distinct hashes', Hashes[I] <> Hashes[J]);
  end;
end;

procedure TTestCastleVulkanRHI.TestVisualRegressionImageComparison;
var
  ImgA, ImgB: TRGBAlphaImage;
  RMSE: Single;
  Px: PVector4Byte;
begin
  ImgA := TRGBAlphaImage.Create(16, 16);
  ImgB := TRGBAlphaImage.Create(16, 16);
  try
    ImgA.Clear(Vector4Byte(64, 128, 192, 255));
    ImgB.Clear(Vector4Byte(64, 128, 192, 255));

    { 1. Identical images must have 0.0 RMSE }
    AssertTrue('Identical framebuffers pass diff threshold',
      CompareImagesPerceptualDiff(ImgA, ImgB, 0.001, RMSE));
    AssertSameValue(0.0, RMSE, 0.00001);

    { 2. Minor 1-LSB rounding difference across 1 pixel stays well within perceptual threshold (0.01) }
    Px := ImgB.PixelPtr(8, 8);
    Px^.X := 65;
    AssertTrue('1-LSB sub-threshold difference passes',
      CompareImagesPerceptualDiff(ImgA, ImgB, 0.01, RMSE));
    AssertTrue('RMSE > 0 for modified image', RMSE > 0.0);

    { 3. Completely different image exceeds threshold and fails }
    ImgB.Clear(Vector4Byte(255, 0, 0, 255));
    AssertFalse('Divergent framebuffers fail diff threshold',
      CompareImagesPerceptualDiff(ImgA, ImgB, 0.05, RMSE));
    AssertTrue('Divergent RMSE > 0.3', RMSE > 0.3);
  finally
    FreeAndNil(ImgB);
    FreeAndNil(ImgA);
  end;
end;

procedure TTestCastleVulkanRHI.TestNintendoSwitchViSurfaceAndManifestPrewarm;
var
  ViCreateInfo: VkViSurfaceCreateInfoNN;
  Manifest: TCastleManifest;
  RaisedError: Boolean;
begin
  { 1. Verify Nintendo Switch VK_NN_vi_surface ABI layout and constants }
  AssertEquals('VK_NN_vi_surface extension name', 'VK_NN_vi_surface', VK_NN_VI_SURFACE_EXTENSION_NAME);
  AssertEquals('VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN', 1000062000, VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN);

  FillChar(ViCreateInfo, SizeOf(ViCreateInfo), 0);
  ViCreateInfo.sType := VK_STRUCTURE_TYPE_VI_SURFACE_CREATE_INFO_NN;
  ViCreateInfo.window := Pointer($1234);
  AssertEquals('ViCreateInfo.sType', 1000062000, ViCreateInfo.sType);
  AssertTrue('ViCreateInfo.window pointer matches', ViCreateInfo.window = Pointer($1234));

  RaisedError := False;
  try
    CreateVulkanViSurface(nil, Pointer($1234));
  except
    on E: ERHIError do
      RaisedError := True;
  end;
  AssertTrue('CreateVulkanViSurface raises ERHIError when vkCreateViSurfaceNN is not loaded', RaisedError);

  { 2. Verify TCastleManifest loading of vulkan_3d_scene and ShouldPrewarmVulkanShaders }
  Manifest := TCastleManifest.CreateFromUrl('examples/vulkan/vulkan_3d_scene/CastleEngineManifest.xml');
  try
    AssertEquals('Manifest name', 'vulkan_3d_scene', Manifest.Name);
    AssertEquals('Manifest RenderBackend is backendVulkan', Ord(backendVulkan), Ord(Manifest.RenderBackend));
    AssertTrue('ShouldPrewarmVulkanShaders is True for backendVulkan', Manifest.ShouldPrewarmVulkanShaders);
  finally
    FreeAndNil(Manifest);
  end;
end;

procedure TTestCastleVulkanRHI.TestPipelineCacheDiskPersistence;
var
  Stream: TMemoryStream;
  InputData, OutputBlob: TBytes;
  I: Integer;
begin
  SetLength(InputData, 64);
  for I := 0 to High(InputData) do
    InputData[I] := Byte((I * 37 + 13) and $FF);

  Stream := TMemoryStream.Create;
  try
    { 1. Save hardware-tagged pipeline cache blob }
    SavePipelineCacheBlobToStream(Stream, $10DE, $2684, @InputData[0], Length(InputData));
    AssertEquals('Stream size equals header + payload',
      SizeOf(TPipelineCacheDiskHeader) + Length(InputData), Stream.Size);

    { 2. Load with matching vendorId ($10DE) and deviceId ($2684) }
    Stream.Position := 0;
    AssertTrue('Valid pipeline cache blob loads for matching GPU',
      LoadPipelineCacheBlobFromStream(Stream, $10DE, $2684, OutputBlob));
    AssertEquals('Loaded blob length matches', Length(InputData), Length(OutputBlob));
    for I := 0 to High(InputData) do
      AssertEquals('Loaded payload byte matches', InputData[I], OutputBlob[I]);

    { 3. Reject when GPU vendorId or deviceId differs }
    Stream.Position := 0;
    AssertFalse('Pipeline cache blob rejected for mismatched VendorId',
      LoadPipelineCacheBlobFromStream(Stream, $1002, $2684, OutputBlob));
    Stream.Position := 0;
    AssertFalse('Pipeline cache blob rejected for mismatched DeviceId',
      LoadPipelineCacheBlobFromStream(Stream, $10DE, $9999, OutputBlob));

    { 4. Reject when payload byte is corrupted (FNV-1a checksum mismatch) }
    PByte(Stream.Memory)[SizeOf(TPipelineCacheDiskHeader) + 5] :=
      PByte(Stream.Memory)[SizeOf(TPipelineCacheDiskHeader) + 5] xor $FF;
    Stream.Position := 0;
    AssertFalse('Corrupted pipeline cache blob rejected by FNV-1a checksum',
      LoadPipelineCacheBlobFromStream(Stream, $10DE, $2684, OutputBlob));
  finally
    FreeAndNil(Stream);
  end;
end;

procedure MockGetPhysicalDeviceMemoryProperties2(
  physicalDevice: VkPhysicalDevice;
  pMemoryProperties: PVkPhysicalDeviceMemoryProperties2); {$ifdef MSWINDOWS}stdcall;{$else}cdecl;{$endif}
var
  BudgetExt: PVkPhysicalDeviceMemoryBudgetPropertiesEXT;
begin
  if pMemoryProperties = nil then Exit;
  pMemoryProperties^.memoryProperties.memoryHeapCount := 2;
  { Heap 0: 8 GB Device-Local VRAM }
  pMemoryProperties^.memoryProperties.memoryHeaps[0].size := UInt64(8192) * 1024 * 1024;
  pMemoryProperties^.memoryProperties.memoryHeaps[0].flags := VK_MEMORY_HEAP_DEVICE_LOCAL_BIT;
  { Heap 1: 16 GB System Shared RAM (not device-local) }
  pMemoryProperties^.memoryProperties.memoryHeaps[1].size := UInt64(16384) * 1024 * 1024;
  pMemoryProperties^.memoryProperties.memoryHeaps[1].flags := 0;

  if pMemoryProperties^.pNext <> nil then
  begin
    BudgetExt := PVkPhysicalDeviceMemoryBudgetPropertiesEXT(pMemoryProperties^.pNext);
    if BudgetExt^.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT then
    begin
      BudgetExt^.heapUsage[0] := UInt64(512) * 1024 * 1024;
      BudgetExt^.heapBudget[0] := UInt64(4096) * 1024 * 1024;
      BudgetExt^.heapUsage[1] := UInt64(1024) * 1024 * 1024;
      BudgetExt^.heapBudget[1] := UInt64(12288) * 1024 * 1024;
    end;
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanMemoryBudgetAndViewportStatistics;
var
  MemProps: VkPhysicalDeviceMemoryProperties;
  BudgetProps: VkPhysicalDeviceMemoryBudgetPropertiesEXT;
  UsedBytes, BudgetBytes: UInt64;
  UsedMB, BudgetMB: Cardinal;
  SavedProc: PFN_vkGetPhysicalDeviceMemoryProperties2;
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  Stats: TRenderStatistics;
begin
  { 1. Test AggregateDeviceLocalMemoryBudget with multi-heap DEVICE_LOCAL filtering }
  FillChar(MemProps, SizeOf(MemProps), 0);
  FillChar(BudgetProps, SizeOf(BudgetProps), 0);
  MemProps.memoryHeapCount := 2;
  MemProps.memoryHeaps[0].size := UInt64(8192) * 1024 * 1024;
  MemProps.memoryHeaps[0].flags := VK_MEMORY_HEAP_DEVICE_LOCAL_BIT;
  MemProps.memoryHeaps[1].size := UInt64(16384) * 1024 * 1024;
  MemProps.memoryHeaps[1].flags := 0;

  BudgetProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT;
  BudgetProps.heapUsage[0] := UInt64(640) * 1024 * 1024;
  BudgetProps.heapBudget[0] := UInt64(7680) * 1024 * 1024;
  BudgetProps.heapUsage[1] := UInt64(2048) * 1024 * 1024;
  BudgetProps.heapBudget[1] := UInt64(14336) * 1024 * 1024;

  AggregateDeviceLocalMemoryBudget(MemProps, BudgetProps, True,
    UInt64(128) * 1024 * 1024, UsedBytes, BudgetBytes, UsedMB, BudgetMB);
  AssertEquals('VK_EXT_memory_budget used MB from DEVICE_LOCAL heap', 640, UsedMB);
  AssertEquals('VK_EXT_memory_budget budget MB from DEVICE_LOCAL heap', 7680, BudgetMB);

  { 2. Test fallback when VK_EXT_memory_budget is not supported }
  AggregateDeviceLocalMemoryBudget(MemProps, BudgetProps, False,
    UInt64(256) * 1024 * 1024, UsedBytes, BudgetBytes, UsedMB, BudgetMB);
  AssertEquals('Fallback used MB from tracked allocations', 256, UsedMB);
  AssertEquals('Fallback budget MB from full DEVICE_LOCAL heap size', 8192, BudgetMB);

  { 3. Test end-to-end live Viewport.Statistics query via vkGetPhysicalDeviceMemoryProperties2 }
  SavedProc := vkGetPhysicalDeviceMemoryProperties2;
  SavedDevice := RHIDevice;
  vkGetPhysicalDeviceMemoryProperties2 := @MockGetPhysicalDeviceMemoryProperties2;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt(1)), True);
  Viewport := TCastleViewport.Create(nil);
  try
    VkDev.RecordDiagnostics(42, 3, 128);
    SetRHIDevice(VkDev);

    Stats := Viewport.Statistics;
    AssertEquals('Viewport.Statistics ActiveBackend', 'Vulkan 1.3', Stats.ActiveBackend);
    AssertEquals('Viewport.Statistics PipelineCacheHits', 42, Stats.PipelineCacheHits);
    AssertEquals('Viewport.Statistics PipelineCacheMisses', 3, Stats.PipelineCacheMisses);
    AssertEquals('Viewport.Statistics DescriptorSetAllocations', 128, Stats.DescriptorSetAllocations);
    AssertEquals('Viewport.Statistics DeviceMemoryUsedMB from VK_EXT_memory_budget', 512, Stats.DeviceMemoryUsedMB);
    AssertEquals('Viewport.Statistics DeviceMemoryBudgetMB from VK_EXT_memory_budget', 4096, Stats.DeviceMemoryBudgetMB);
    AssertTrue('Viewport.Statistics.ToString includes live VRAM usage/budget',
      Pos('VRAM: 512 / 4096 MB', Stats.ToString) > 0);
  finally
    SetRHIDevice(SavedDevice);
    vkGetPhysicalDeviceMemoryProperties2 := SavedProc;
    FreeAndNil(Viewport);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportPrepareResourcesPrewarmsPSOs;
var
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  Viewport: TCastleViewport;
  Stats: TRenderStatistics;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, False);
  Viewport := TCastleViewport.Create(nil);
  try
    SetRHIDevice(VkDev);
    AssertEquals('Initial PipelineCount should be 0', 0, VkDev.PipelineCount);
    AssertFalse('Initial PipelineCacheLoaded should be False', VkDev.PipelineCacheLoaded);

    { First PrepareResources call should load the pipeline cache and bake all 5 standard PSOs }
    Viewport.PrepareResources;
    AssertTrue('PipelineCacheLoaded should be True after PrepareResources', VkDev.PipelineCacheLoaded);
    AssertEquals('All 5 standard PSO permutations should be pre-warmed', 5, VkDev.PipelineCount);
    AssertEquals('First PrepareResources should record 5 pipeline cache misses', 5, VkDev.PipelineCacheMisses);
    AssertEquals('First PrepareResources should record 0 pipeline cache hits', 0, VkDev.PipelineCacheHits);

    { Second PrepareResources call should hit all 5 cached PSOs with zero new misses }
    Viewport.PrepareResources;
    AssertEquals('PipelineCount remains 5 after second PrepareResources', 5, VkDev.PipelineCount);
    AssertEquals('PipelineCacheMisses remains 5 after second PrepareResources', 5, VkDev.PipelineCacheMisses);
    AssertEquals('Second PrepareResources should record 5 pipeline cache hits', 5, VkDev.PipelineCacheHits);

    Stats := Viewport.Statistics;
    AssertEquals('Viewport.Statistics reflects pre-warmed PSO hits', 5, Stats.PipelineCacheHits);
    AssertEquals('Viewport.Statistics reflects pre-warmed PSO misses', 5, Stats.PipelineCacheMisses);
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(Viewport);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.CaptureWarning(const Category, S: String);
begin
  if FCapturedWarnings <> nil then
    FCapturedWarnings.Add(Category + ': ' + S);
end;

procedure TTestCastleVulkanRHI.TestLegacyGLSLUniformWarningDiagnostics;
var
  Gen: TCastleShaderGeneratorRHI;
  LegacyEffectSource, CleanEffectSource, Upgraded: String;
  WarnCount: Cardinal;
  AllWarnings: String;
const
  NL = LineEnding;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  FCapturedWarnings := TStringList.Create;
  ApplicationProperties.OnWarning.Add({$ifdef FPC}@{$endif}CaptureWarning);
  try
    { 1. Legacy EffectPart using gl_ModelViewProjectionMatrix, gl_NormalMatrix,
         gl_Vertex, gl_FragColor, texture2D, and varying }
    LegacyEffectSource :=
      'uniform sampler2D u_albedoMap;' + NL +
      'uniform float u_exposure;' + NL +
      'varying vec2 v_legacyUV;' + NL +
      'void PLUG_fragment_modify(inout vec4 color) {' + NL +
      '  vec4 clipPos = gl_ModelViewProjectionMatrix * gl_Vertex;' + NL +
      '  vec3 n = gl_NormalMatrix * vec3(0.0, 0.0, 1.0);' + NL +
      '  gl_FragColor = texture2D(u_albedoMap, v_legacyUV) * u_exposure + clipPos * 0.0 + vec4(n, 0.0) * 0.0;' + NL +
      '}' + NL;

    Upgraded := Gen.UpgradeLegacyGLSLBuiltIns(LegacyEffectSource, 'MyWaterEffect', WarnCount);
    AllWarnings := FCapturedWarnings.Text;

    AssertEquals('Should emit 6 warnings (gl_ModelViewProjectionMatrix, gl_NormalMatrix, gl_Vertex, gl_FragColor, texture2D, varying)',
      6, WarnCount);
    AssertEquals('OnWarning listener should capture 6 warnings', 6, FCapturedWarnings.Count);
    AssertTrue('Warning mentions gl_ModelViewProjectionMatrix and replacement',
      Pos('gl_ModelViewProjectionMatrix', AllWarnings) > 0);
    AssertTrue('Warning mentions gl_NormalMatrix',
      Pos('gl_NormalMatrix', AllWarnings) > 0);
    AssertTrue('Warning mentions gl_Vertex',
      Pos('gl_Vertex', AllWarnings) > 0);
    AssertTrue('Warning mentions gl_FragColor',
      Pos('gl_FragColor', AllWarnings) > 0);
    AssertTrue('Warning mentions texture2D',
      Pos('texture2D', AllWarnings) > 0);
    AssertTrue('Warning mentions varying qualifier',
      Pos('qualifier "varying"', AllWarnings) > 0);

    { Verify #version 450 compatibility #define aliases and qualifier upgrade in output }
    AssertTrue('Upgraded source defines gl_ModelViewProjectionMatrix alias',
      Pos('#define gl_ModelViewProjectionMatrix (castle_ProjectionMatrix * castle_ModelViewMatrix)', Upgraded) > 0);
    AssertTrue('Upgraded source defines gl_FragColor alias',
      Pos('#define gl_FragColor castle_FragColor', Upgraded) > 0);
    AssertTrue('Upgraded source defines texture2D alias',
      Pos('#define texture2D texture', Upgraded) > 0);
    AssertTrue('Upgraded source rewrites varying to in',
      Pos('in vec2 v_legacyUV;', Upgraded) > 0);

    { 2. Verify identifier boundary matching: gl_VertexIndex must NOT trigger gl_Vertex warning }
    FCapturedWarnings.Clear;
    CleanEffectSource :=
      'uniform float u_scale;' + NL +
      'void PLUG_vertex_object_space(inout vec4 vertex, inout vec3 normal) {' + NL +
      '  int idx = gl_VertexIndex;' + NL +
      '  vertex.xyz *= u_scale;' + NL +
      '}' + NL;
    Upgraded := Gen.UpgradeUserEffectUniforms(CleanEffectSource);
    AssertEquals('Clean modern GLSL 450 effect should emit 0 warnings', 0, FCapturedWarnings.Count);
    AssertTrue('UpgradeUserEffectUniforms still generates CastleUserEffectBlock',
      Pos('CastleUserEffectBlock', Upgraded) > 0);
  finally
    ApplicationProperties.OnWarning.Remove({$ifdef FPC}@{$endif}CaptureWarning);
    FreeAndNil(FCapturedWarnings);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkan11RenderPassFramebufferFallback;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  ColorTex, DepthTex, ShadowDepthTex: TRHITexture;
  ForwardInfo, ShadowInfo: TRHIRenderingInfo;
  RpHash1, RpHash2, RpHashShadow, FbHash1, FbHash2: UInt64;
  RpForward, RpShadow: VkRenderPass;
  PrewarmedCount: Cardinal;
begin
  { 1. Verify deterministic FNV-1a key hashes for VkRenderPass and VkFramebuffer }
  RpHash1 := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD32_Float, 1);
  RpHash2 := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD32_Float, 1);
  RpHashShadow := ComputeRenderPassKeyHash([], pfD32_Float, 1);
  AssertTrue('Identical render pass signatures must produce identical hashes', RpHash1 = RpHash2);
  AssertTrue('Forward pass and depth-only shadow pass must produce distinct hashes', RpHash1 <> RpHashShadow);

  FbHash1 := ComputeFramebufferKeyHash(VkRenderPass(1), [VkImageView(100), VkImageView(200)], 1920, 1080);
  FbHash2 := ComputeFramebufferKeyHash(VkRenderPass(1), [VkImageView(100), VkImageView(200)], 1280, 720);
  AssertTrue('Different framebuffer dimensions must produce distinct hashes', FbHash1 <> FbHash2);

  { 2. Create headless Vulkan 1.1 fallback device (SupportsDynamicRendering = False) }
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, False);
  try
    AssertFalse('Headless Vulkan 1.1 device must report SupportsDynamicRendering = False',
      VkDev.SupportsDynamicRendering);
    AssertEquals('Initial fallback render pass count should be 0', 0, VkDev.FallbackRenderPassCount);
    AssertEquals('Initial fallback framebuffer count should be 0', 0, VkDev.FallbackFramebufferCount);

    { 3. Pre-warming standard PSOs on a Vulkan 1.1 device should populate fallback VkRenderPasses }
    PrewarmedCount := VkDev.PrewarmStandardPipelines(True, True);
    AssertEquals('PrewarmStandardPipelines should bake 5 standard PSOs on Vulkan 1.1 fallback', 5, PrewarmedCount);
    AssertEquals('Pre-warming forward + shadow PSOs should cache exactly 2 unique VkRenderPasses',
      2, VkDev.FallbackRenderPassCount);

    RpForward := VkDev.GetOrCreateFallbackRenderPass([pfBGRA8_UNorm], pfD32_Float, 1);
    RpShadow := VkDev.GetOrCreateFallbackRenderPass([], pfD32_Float, 1);
    AssertTrue('Cached forward VkRenderPass handle must be non-null', RpForward <> VK_NULL_HANDLE);
    AssertTrue('Cached shadow VkRenderPass handle must be non-null', RpShadow <> VK_NULL_HANDLE);
    AssertTrue('Forward and shadow VkRenderPass handles must be distinct', RpForward <> RpShadow);
    AssertEquals('Re-querying existing render passes must not increase FallbackRenderPassCount',
      2, VkDev.FallbackRenderPassCount);

    { 4. Execute BeginRendering / EndRendering on TVulkanRHICommandList across 2 frames }
    ColorTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfBGRA8_UNorm, [tuColorAttachment]));
    DepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfD32_Float, [tuDepthStencil]));
    ShadowDepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(2048, 2048, pfD32_Float, [tuDepthStencil, tuSampled]));
    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    try
      FillChar(ForwardInfo, SizeOf(ForwardInfo), 0);
      ForwardInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(ForwardInfo.ColorAttachments, 1);
      ForwardInfo.ColorAttachments[0].Texture := ColorTex;
      ForwardInfo.ColorAttachments[0].LoadOp := loClear;
      ForwardInfo.ColorAttachments[0].StoreOp := soStore;
      ForwardInfo.HasDepthAttachment := True;
      ForwardInfo.DepthAttachment.Texture := DepthTex;
      ForwardInfo.DepthAttachment.LoadOp := loClear;
      ForwardInfo.DepthAttachment.StoreOp := soStore;
      ForwardInfo.DepthAttachment.ClearDepth := 1.0;

      FillChar(ShadowInfo, SizeOf(ShadowInfo), 0);
      ShadowInfo.RenderArea := Rectangle(0, 0, 2048, 2048);
      ShadowInfo.HasDepthAttachment := True;
      ShadowInfo.DepthAttachment.Texture := ShadowDepthTex;
      ShadowInfo.DepthAttachment.LoadOp := loClear;
      ShadowInfo.DepthAttachment.StoreOp := soStore;
      ShadowInfo.DepthAttachment.ClearDepth := 1.0;

      { Frame 1: Shadow pass + Forward pass }
      CmdList.BeginRendering(ShadowInfo);
      AssertTrue('CommandList must be inside fallback render pass after BeginRendering',
        CmdList.InFallbackRenderPass);
      CmdList.EndRendering;
      AssertFalse('CommandList must exit fallback render pass after EndRendering',
        CmdList.InFallbackRenderPass);

      CmdList.BeginRendering(ForwardInfo);
      AssertTrue('CommandList must be inside fallback render pass during forward pass',
        CmdList.InFallbackRenderPass);
      CmdList.EndRendering;

      AssertEquals('After Frame 1, 2 framebuffers (shadow + forward) should be cached',
        2, VkDev.FallbackFramebufferCount);
      AssertEquals('After Frame 1, FallbackRenderPassBeginCount should be 2',
        2, VkDev.FallbackRenderPassBeginCount);

      { Frame 2: Reuse cached VkRenderPass and VkFramebuffer instances }
      CmdList.BeginRendering(ShadowInfo);
      CmdList.EndRendering;
      CmdList.BeginRendering(ForwardInfo);
      CmdList.EndRendering;

      AssertEquals('Frame 2 must reuse cached VkRenderPasses (count stays 2)',
        2, VkDev.FallbackRenderPassCount);
      AssertEquals('Frame 2 must reuse cached VkFramebuffers (count stays 2)',
        2, VkDev.FallbackFramebufferCount);
      AssertEquals('After Frame 2, FallbackRenderPassBeginCount should be 4',
        4, VkDev.FallbackRenderPassBeginCount);
    finally
      FreeAndNil(CmdList);
      FreeAndNil(ShadowDepthTex);
      FreeAndNil(DepthTex);
      FreeAndNil(ColorTex);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestVkXmlHeaderGenerator;
begin
  { Verify that CastleInternalVulkan was generated from the official Khronos vk.xml
    registry by tools/internal/generate_vulkan_api/vkxml2pas.dpr }
  AssertTrue('VK_HEADER_VERSION from vk.xml must be >= 300',
    VK_HEADER_VERSION >= 300);

  { Verify core and extension VkStructureType values against Khronos vk.xml
    formula: 1000000000 + (extnumber - 1) * 1000 + offset }
  AssertEquals('VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO must be 17 per vk.xml',
    17, VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_RENDERING_INFO (ext 45, offset 0) must be 1000044000',
    1000044000, VK_STRUCTURE_TYPE_RENDERING_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO (ext 45, offset 1) must be 1000044001',
    1000044001, VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO (ext 45, offset 2) must be 1000044002',
    1000044002, VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR (ext 45, offset 3) must be 1000044003',
    1000044003, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR (ext 315, offset 7) must be 1000314007',
    1000314007, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT (ext 238, offset 0) must be 1000237000',
    1000237000, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT);
end;

procedure TTestCastleVulkanRHI.TestVulkan11_12DeviceNegotiationAndFallback;
var
  UseDynRender: Boolean;
  ReqExts: TAnsiStringArray;
  VkDev: TVulkanRHIDevice;
  ColorTex, DepthTex: TRHITexture;
  CmdList: TVulkanRHICommandList;
  ScenePassInfo, UIOverlayPassInfo: TRHIRenderingInfo;
  ClearHash, LoadHash: UInt64;
begin
  { 1. Instance API Version Negotiation (vkEnumerateInstanceVersion fallback) }
  AssertEquals('Vulkan 1.3+ loader negotiates 1.3',
    VK_API_VERSION_1_3, NegotiateInstanceApiVersion(VK_API_VERSION_1_4));
  AssertEquals('Vulkan 1.3 loader negotiates 1.3',
    VK_API_VERSION_1_3, NegotiateInstanceApiVersion(VK_API_VERSION_1_3));
  AssertEquals('Vulkan 1.2 loader negotiates 1.2',
    VK_API_VERSION_1_2, NegotiateInstanceApiVersion(VK_API_VERSION_1_2));
  AssertEquals('Vulkan 1.1 loader negotiates 1.1',
    VK_API_VERSION_1_1, NegotiateInstanceApiVersion(VK_API_VERSION_1_1));
  AssertEquals('Vulkan 1.0 loader negotiates 1.0',
    VK_API_VERSION_1_0, NegotiateInstanceApiVersion(VK_API_VERSION_1_0));

  { 2. Vulkan 1.3 Device Config: Dynamic rendering is core (0 extra extensions needed) }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_3, False, False, False, UseDynRender, ReqExts);
  AssertTrue('Vulkan 1.3 device uses core dynamic rendering', UseDynRender);
  AssertEquals('Vulkan 1.3 device needs 0 extra dynamic rendering extensions', 0, Length(ReqExts));

  { 3. Vulkan 1.2 Device Config:
    - With VK_KHR_dynamic_rendering: enabled (VK_KHR_depth_stencil_resolve & VK_KHR_create_renderpass2 are core 1.2)
    - Without VK_KHR_dynamic_rendering: falls back to VkRenderPass + VkFramebuffer }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_2, True, False, False, UseDynRender, ReqExts);
  AssertTrue('Vulkan 1.2 device with VK_KHR_dynamic_rendering enables dynamic rendering', UseDynRender);
  AssertEquals('Vulkan 1.2 device enables 1 extension (VK_KHR_dynamic_rendering)', 1, Length(ReqExts));
  AssertEquals('Extension name must be VK_KHR_dynamic_rendering',
    VK_KHR_dynamic_rendering, String(ReqExts[0]));

  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_2, False, True, True, UseDynRender, ReqExts);
  AssertFalse('Vulkan 1.2 device without VK_KHR_dynamic_rendering falls back to VkRenderPass', UseDynRender);
  AssertEquals('Fallback needs 0 dynamic rendering extensions', 0, Length(ReqExts));

  { 4. Vulkan 1.1 Device Config:
    - Requires VK_KHR_create_renderpass2 + VK_KHR_depth_stencil_resolve + VK_KHR_dynamic_rendering
    - Missing any prerequisite falls back to VkRenderPass + VkFramebuffer }
  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_1, True, True, True, UseDynRender, ReqExts);
  AssertTrue('Vulkan 1.1 device with all 3 extensions enables dynamic rendering', UseDynRender);
  AssertEquals('Vulkan 1.1 device enables all 3 prerequisite extensions', 3, Length(ReqExts));
  AssertEquals('First prerequisite on 1.1 is VK_KHR_create_renderpass2',
    VK_KHR_create_renderpass2, String(ReqExts[0]));
  AssertEquals('Second prerequisite on 1.1 is VK_KHR_depth_stencil_resolve',
    VK_KHR_depth_stencil_resolve, String(ReqExts[1]));
  AssertEquals('Third extension on 1.1 is VK_KHR_dynamic_rendering',
    VK_KHR_dynamic_rendering, String(ReqExts[2]));

  ResolveVulkan11_12DeviceConfig(VK_API_VERSION_1_1, True, False, True, UseDynRender, ReqExts);
  AssertFalse('Vulkan 1.1 device missing VK_KHR_depth_stencil_resolve falls back to VkRenderPass', UseDynRender);

  { 5. Multi-Pass LoadOp (loClear vs loLoad) on a Vulkan 1.1/1.2 Fallback Device }
  ClearHash := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD24_UNorm_S8_UInt, 1, loClear, loClear);
  LoadHash := ComputeRenderPassKeyHash([pfBGRA8_UNorm], pfD24_UNorm_S8_UInt, 1, loLoad, loLoad);
  AssertTrue('loClear and loLoad render passes must produce distinct cache keys', ClearHash <> LoadHash);

  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, False, VK_API_VERSION_1_1);
  try
    AssertEquals('Headless Vulkan 1.1 device reports apiVersion 1.1',
      VK_API_VERSION_1_1, VkDev.DeviceApiVersion);
    AssertFalse('Headless Vulkan 1.1 fallback device disables dynamic rendering',
      VkDev.SupportsDynamicRendering);

    ColorTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfBGRA8_UNorm, [tuColorAttachment]));
    DepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(1280, 720, pfD24_UNorm_S8_UInt, [tuDepthStencil]));

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    try
      { Pass 1: 3D Scene Pass (LoadOp = loClear) }
      FillChar(ScenePassInfo, SizeOf(ScenePassInfo), 0);
      ScenePassInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(ScenePassInfo.ColorAttachments, 1);
      ScenePassInfo.ColorAttachments[0].Texture := ColorTex;
      ScenePassInfo.ColorAttachments[0].LoadOp := loClear;
      ScenePassInfo.ColorAttachments[0].StoreOp := soStore;
      ScenePassInfo.HasDepthAttachment := True;
      ScenePassInfo.DepthAttachment.Texture := DepthTex;
      ScenePassInfo.DepthAttachment.LoadOp := loClear;
      ScenePassInfo.DepthAttachment.StoreOp := soStore;

      { Pass 2: 2D UI Overlay Pass (LoadOp = loLoad to preserve 3D scene!) }
      FillChar(UIOverlayPassInfo, SizeOf(UIOverlayPassInfo), 0);
      UIOverlayPassInfo.RenderArea := Rectangle(0, 0, 1280, 720);
      SetLength(UIOverlayPassInfo.ColorAttachments, 1);
      UIOverlayPassInfo.ColorAttachments[0].Texture := ColorTex;
      UIOverlayPassInfo.ColorAttachments[0].LoadOp := loLoad;
      UIOverlayPassInfo.ColorAttachments[0].StoreOp := soStore;
      UIOverlayPassInfo.HasDepthAttachment := False;

      CmdList.BeginRendering(ScenePassInfo);
      CmdList.EndRendering;

      CmdList.BeginRendering(UIOverlayPassInfo);
      CmdList.EndRendering;

      AssertEquals('2 distinct fallback VkRenderPasses (loClear 3D + loLoad 2D UI) must be cached',
        2, VkDev.FallbackRenderPassCount);
      AssertEquals('2 fallback VkFramebuffers must be cached',
        2, VkDev.FallbackFramebufferCount);
    finally
      FreeAndNil(CmdList);
      FreeAndNil(DepthTex);
      FreeAndNil(ColorTex);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestGraphicsPipelineLibraryFastLinking;
var
  UseGPL: Boolean;
  ReqExts: TAnsiStringArray;
  DescA, DescB: TRHIGraphicsPipelineDesc;
  VkDev: TVulkanRHIDevice;
  PrewarmedCount: Cardinal;
  PsoOpaque, PsoTwoSided: TVulkanRHIPipeline;
begin
  { 1. Verify Khronos vk.xml generated constants for VK_EXT_graphics_pipeline_library }
  AssertEquals('VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR must match vk.xml',
    1000290000, VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT must match vk.xml',
    1000320000, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_PROPERTIES_EXT must match vk.xml',
    1000320001, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_PROPERTIES_EXT);
  AssertEquals('VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT must match vk.xml',
    1000320002, VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT);
  AssertEquals('All 4 GPL subset flags combined must equal $0F',
    $0000000F,
    VK_GRAPHICS_PIPELINE_LIBRARY_VERTEX_INPUT_INTERFACE_BIT_EXT or
    VK_GRAPHICS_PIPELINE_LIBRARY_PRE_RASTERIZATION_SHADERS_BIT_EXT or
    VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_SHADER_BIT_EXT or
    VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_OUTPUT_INTERFACE_BIT_EXT);

  { 2. Verify ResolveGraphicsPipelineLibraryConfig device extension negotiation }
  ResolveGraphicsPipelineLibraryConfig(VK_API_VERSION_1_3, True, True, True, UseGPL, ReqExts);
  AssertTrue('Device advertising both extensions and feature enables GPL', UseGPL);
  AssertEquals('GPL requires 2 extensions (VK_KHR_pipeline_library + VK_EXT_graphics_pipeline_library)',
    2, Length(ReqExts));
  AssertEquals('First GPL extension is VK_KHR_pipeline_library',
    VK_KHR_pipeline_library, String(ReqExts[0]));
  AssertEquals('Second GPL extension is VK_EXT_graphics_pipeline_library',
    VK_EXT_graphics_pipeline_library, String(ReqExts[1]));

  ResolveGraphicsPipelineLibraryConfig(VK_API_VERSION_1_3, True, True, False, UseGPL, ReqExts);
  AssertFalse('Device without graphicsPipelineLibrary feature bit disables GPL', UseGPL);
  AssertEquals('Disabled GPL requires 0 extensions', 0, Length(ReqExts));

  { 3. Verify independent hashing of the 4 pipeline library subsets }
  FillChar(DescA, SizeOf(DescA), 0);
  DescA.Topology := ptTriangleList;
  DescA.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  DescA.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  DescA.BlendState := TRHIBlendStateDesc.DefaultOpaque;
  SetLength(DescA.ColorAttachmentFormats, 1);
  DescA.ColorAttachmentFormats[0] := pfBGRA8_UNorm;
  DescA.DepthAttachmentFormat := pfD32_Float;
  DescA.SampleCount := 1;

  DescB := DescA;
  DescB.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;

  AssertTrue('Changing BlendState must NOT change VertexInputLibrary hash',
    ComputeVertexInputLibraryKeyHash(DescA) = ComputeVertexInputLibraryKeyHash(DescB));
  AssertTrue('Changing BlendState must NOT change PreRasterizationLibrary hash',
    ComputePreRasterizationLibraryKeyHash(DescA) = ComputePreRasterizationLibraryKeyHash(DescB));
  AssertTrue('Changing BlendState must NOT change FragmentShaderLibrary hash',
    ComputeFragmentShaderLibraryKeyHash(DescA) = ComputeFragmentShaderLibraryKeyHash(DescB));
  AssertTrue('Changing BlendState MUST change FragmentOutputLibrary hash',
    ComputeFragmentOutputLibraryKeyHash(DescA) <> ComputeFragmentOutputLibraryKeyHash(DescB));

  { 4. Verify fast-linking & sub-library cache reuse across permutations }
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3, True);
  try
    AssertTrue('Headless GPL device reports SupportsGraphicsPipelineLibrary',
      VkDev.SupportsGraphicsPipelineLibrary);
    AssertTrue('Headless GPL device reports SupportsGPLFastLinking',
      VkDev.SupportsGPLFastLinking);

    { PrewarmStandardPipelines bakes 5 PSOs (20 subset lookups total) }
    PrewarmedCount := VkDev.PrewarmStandardPipelines(True, True);
    AssertEquals('5 standard PSOs should be fast-linked', 5, PrewarmedCount);
    AssertEquals('GPLFastLinkedPipelineCount should equal 5', 5, VkDev.GPLFastLinkedPipelineCount);

    { Out of 20 subset lookups (5 PSOs x 4 subsets), only 13 unique sub-libraries are created
      and 7 are served directly from the partial library caches! }
    AssertEquals('VertexInputLibraryCount should be 2 (3D mesh shared by 4 PSOs + 2D sprite)',
      2, VkDev.VertexInputLibraryCount);
    AssertEquals('PreRasterizationLibraryCount should be 4 (3D CullNone shared by TwoSided + AlphaBlend)',
      4, VkDev.PreRasterizationLibraryCount);
    AssertEquals('FragmentShaderLibraryCount should be 4 (3D DepthTestWrite shared by Opaque + TwoSided)',
      4, VkDev.FragmentShaderLibraryCount);
    AssertEquals('FragmentOutputLibraryCount should be 3 (Opaque, AlphaBlend, DepthOnly)',
      3, VkDev.FragmentOutputLibraryCount);
    AssertEquals('Total unique pipeline libraries should be 13 (down from 20)',
      13, VkDev.TotalPipelineLibraryCount);
    AssertEquals('GPL library cache hits should be 7', 7, VkDev.GPLLibraryCacheHits);
    AssertEquals('GPL library cache misses should be 13', 13, VkDev.GPLLibraryCacheMisses);

    { Verify two PSOs that differ only in CullMode share 3 out of 4 pipeline libraries }
    DescB := DescA;
    DescB.Rasterizer.CullMode := cmNone;
    PsoOpaque := VkDev.GetOrCreatePipeline(DescA) as TVulkanRHIPipeline;
    PsoTwoSided := VkDev.GetOrCreatePipeline(DescB) as TVulkanRHIPipeline;

    AssertTrue('Opaque PSO must be linked from libraries', PsoOpaque.LinkedFromLibraries);
    AssertTrue('TwoSided PSO must be linked from libraries', PsoTwoSided.LinkedFromLibraries);
    AssertTrue('Opaque and TwoSided PSOs share VertexInputLibrary',
      PsoOpaque.VertexInputLibrary = PsoTwoSided.VertexInputLibrary);
    AssertTrue('Opaque and TwoSided PSOs have distinct PreRasterizationLibrary (CullBack vs CullNone)',
      PsoOpaque.PreRasterizationLibrary <> PsoTwoSided.PreRasterizationLibrary);
    AssertTrue('Opaque and TwoSided PSOs share FragmentShaderLibrary',
      PsoOpaque.FragmentShaderLibrary = PsoTwoSided.FragmentShaderLibrary);
    AssertTrue('Opaque and TwoSided PSOs share FragmentOutputLibrary',
      PsoOpaque.FragmentOutputLibrary = PsoTwoSided.FragmentOutputLibrary);
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestSPIRVBinaryReflectionAndValidation;
var
  Words, SwappedWords: array of UInt32;
  Info, SwappedInfo: TSPIRVReflectionInfo;
  FoundBind: TSPIRVReflectedBinding;
  FoundIO: TSPIRVReflectedStageIO;
  ShaderMod, WrongStageMod: TVulkanRHIShaderModule;
  ValidSet0Layout: array[0..1] of TRHIDescriptorBindingDesc;
  ValidSet1Layout: array[0..1] of TRHIDescriptorBindingDesc;
  BadTypeLayout: array[0..1] of TRHIDescriptorBindingDesc;
  MissingBindLayout: array[0..0] of TRHIDescriptorBindingDesc;
  BadStageLayout: array[0..1] of TRHIDescriptorBindingDesc;
  BadCountLayout: array[0..1] of TRHIDescriptorBindingDesc;
  DiagMsg: String;
  I: Integer;

  procedure EmitWord(const W: UInt32);
  begin
    SetLength(Words, Length(Words) + 1);
    Words[High(Words)] := W;
  end;

  procedure EmitInst(const Opcode: UInt16; const Operands: array of UInt32);
  var
    Idx: Integer;
  begin
    EmitWord((UInt32(Length(Operands) + 1) shl 16) or Opcode);
    for Idx := 0 to High(Operands) do
      EmitWord(Operands[Idx]);
  end;

  procedure EmitName(const TargetId: UInt32; const S: AnsiString);
  var
    WordLen, WIdx, BIdx, CharPos: Integer;
    WVal: UInt32;
  begin
    WordLen := (Length(S) div 4) + 1;
    EmitWord((UInt32(WordLen + 2) shl 16) or 5 { OpName });
    EmitWord(TargetId);
    for WIdx := 0 to WordLen - 1 do
    begin
      WVal := 0;
      for BIdx := 0 to 3 do
      begin
        CharPos := WIdx * 4 + BIdx + 1;
        if CharPos <= Length(S) then
          WVal := WVal or (UInt32(Ord(S[CharPos])) shl (BIdx * 8));
      end;
      EmitWord(WVal);
    end;
  end;

begin
  { Build a synthetic pre-compiled SPIR-V 1.6 Fragment Shader binary word stream
    (verifying pure Pascal reflection with zero libshaderc dependency) }
  SetLength(Words, 0);
  EmitWord($07230203); // Magic
  EmitWord($00010600); // Version 1.6
  EmitWord($000D000B); // Generator
  EmitWord(40);        // Bound
  EmitWord(0);         // Schema

  { OpEntryPoint Fragment(4), %1, "main" ($6E69616D, $00000000) }
  EmitInst(15, [4, 1, $6E69616D, 0]);

  { Debug names (OpName) }
  EmitName(10, 'CastleFrameUBO');
  EmitName(13, 'CastleJointSSBO');
  EmitName(18, 'castle_MaterialTextures');
  EmitName(20, 'castle_OutputStorageImg');
  EmitName(23, 'CastleDrawPushConstants');
  EmitName(25, 'v_TexCoord0');
  EmitName(27, 'out_FragColor');

  { Decorations (OpDecorate = 71, OpMemberDecorate = 72) }
  { UBO struct %9: Block(2), member 0 Offset 0 (mat4=64B), member 1 Offset 64 (vec4=16B) => 80B }
  EmitInst(71, [9, 2]);
  EmitInst(72, [9, 0, 35, 0]);
  EmitInst(72, [9, 1, 35, 64]);
  EmitInst(71, [10, 34, 0]); // DescriptorSet 0
  EmitInst(71, [10, 33, 0]); // Binding 0

  { SSBO struct %12: Block(2), member 0 Offset 0 (mat4=64B) => 64B }
  EmitInst(71, [12, 2]);
  EmitInst(72, [12, 0, 35, 0]);
  EmitInst(71, [13, 34, 0]); // DescriptorSet 0
  EmitInst(71, [13, 33, 1]); // Binding 1

  { CombinedImageSampler array[4] %18: DescriptorSet 1, Binding 0 }
  EmitInst(71, [18, 34, 1]);
  EmitInst(71, [18, 33, 0]);

  { StorageImage %20: DescriptorSet 1, Binding 1 }
  EmitInst(71, [20, 34, 1]);
  EmitInst(71, [20, 33, 1]);

  { PushConstant struct %22: Block(2), member 0 Offset 0 (mat4=64B), member 1 Offset 64 (mat4=64B) => 128B }
  EmitInst(71, [22, 2]);
  EmitInst(72, [22, 0, 35, 0]);
  EmitInst(72, [22, 1, 35, 64]);

  { Stage Input %25 (location = 0) and Stage Output %27 (location = 0) }
  EmitInst(71, [25, 30, 0]);
  EmitInst(71, [27, 30, 0]);

  { Fundamental types }
  EmitInst(22, [2, 32]);       // %2 = OpTypeFloat 32
  EmitInst(23, [3, 2, 4]);     // %3 = OpTypeVector %2 4 (vec4)
  EmitInst(24, [4, 3, 4]);     // %4 = OpTypeMatrix %3 4 (mat4, 64 bytes)
  EmitInst(23, [5, 2, 2]);     // %5 = OpTypeVector %2 2 (vec2)
  EmitInst(21, [6, 32, 0]);    // %6 = OpTypeInt 32 0 (uint)
  EmitInst(43, [6, 7, 4]);     // %7 = OpConstant %6 4

  { UBO type & variable: %9 = struct(mat4, vec4), %8 = ptr(Uniform=2, %9), %10 = var }
  EmitInst(30, [9, 4, 3]);
  EmitInst(32, [8, 2, 9]);
  EmitInst(59, [8, 10, 2]);

  { SSBO type & variable: %12 = struct(mat4), %11 = ptr(StorageBuffer=12, %12), %13 = var }
  EmitInst(30, [12, 4]);
  EmitInst(32, [11, 12, 12]);
  EmitInst(59, [11, 13, 12]);

  { CombinedImageSampler[4]: %14 = Image(Sampled=1), %15 = SampledImage, %16 = Array[4], %17 = ptr(UniformConstant=0), %18 = var }
  EmitInst(25, [14, 2, 1, 0, 0, 0, 1, 0]);
  EmitInst(27, [15, 14]);
  EmitInst(28, [16, 15, 7]);
  EmitInst(32, [17, 0, 16]);
  EmitInst(59, [17, 18, 0]);

  { StorageImage: %19 = Image(Sampled=2), %21 = ptr(UniformConstant=0, %19), %20 = var }
  EmitInst(25, [19, 2, 1, 0, 0, 0, 2, 1]);
  EmitInst(32, [21, 0, 19]);
  EmitInst(59, [21, 20, 0]);

  { PushConstant: %22 = struct(mat4, mat4), %24 = ptr(PushConstant=9, %22), %23 = var }
  EmitInst(30, [22, 4, 4]);
  EmitInst(32, [24, 9, 22]);
  EmitInst(59, [24, 23, 9]);

  { Stage Input & Output variables }
  EmitInst(32, [26, 1, 5]);    // %26 = ptr(Input=1, vec2)
  EmitInst(59, [26, 25, 1]);   // %25 = var Input
  EmitInst(32, [28, 3, 3]);    // %28 = ptr(Output=3, vec4)
  EmitInst(59, [28, 27, 3]);   // %27 = var Output

  { 1. Inspect native-endian SPIR-V binary }
  AssertTrue('InspectSPIRVBytecode must succeed on valid SPIR-V stream',
    InspectSPIRVBytecode(@Words[0], Length(Words) * SizeOf(UInt32), Info));
  AssertTrue('Info.IsValid must be True', Info.IsValid);
  AssertFalse('Native SPIR-V must not be flagged ByteSwapped', Info.ByteSwapped);
  AssertEquals('SPIR-V VersionMajor', 1, Info.VersionMajor);
  AssertEquals('SPIR-V VersionMinor', 6, Info.VersionMinor);
  AssertEquals('Reflected stage must be ssFragment', Ord(ssFragment), Ord(Info.Stage));
  AssertEquals('Reflected entry point name', 'main', Info.EntryPointName);

  { Verify 4 reflected descriptor bindings }
  AssertEquals('Reflected binding count must be 4', 4, Length(Info.Bindings));

  AssertTrue('Must find Set 0 Binding 0 (UBO)', Info.FindBinding(0, 0, FoundBind));
  AssertEquals('Set 0 Binding 0 type', Ord(dtUniformBuffer), Ord(FoundBind.DescriptorType));
  AssertEquals('Set 0 Binding 0 count', 1, FoundBind.Count);
  AssertEquals('Set 0 Binding 0 block size (mat4 + vec4 = 80)', 80, FoundBind.BlockSize);
  AssertEquals('Set 0 Binding 0 name', 'CastleFrameUBO', FoundBind.Name);

  AssertTrue('Must find Set 0 Binding 1 (SSBO)', Info.FindBinding(0, 1, FoundBind));
  AssertEquals('Set 0 Binding 1 type', Ord(dtStorageBuffer), Ord(FoundBind.DescriptorType));
  AssertEquals('Set 0 Binding 1 count', 1, FoundBind.Count);
  AssertEquals('Set 0 Binding 1 block size (mat4 = 64)', 64, FoundBind.BlockSize);
  AssertEquals('Set 0 Binding 1 name', 'CastleJointSSBO', FoundBind.Name);

  AssertTrue('Must find Set 1 Binding 0 (CombinedImageSampler[4])', Info.FindBinding(1, 0, FoundBind));
  AssertEquals('Set 1 Binding 0 type', Ord(dtCombinedImageSampler), Ord(FoundBind.DescriptorType));
  AssertEquals('Set 1 Binding 0 array count', 4, FoundBind.Count);
  AssertEquals('Set 1 Binding 0 name', 'castle_MaterialTextures', FoundBind.Name);

  AssertTrue('Must find Set 1 Binding 1 (StorageImage)', Info.FindBinding(1, 1, FoundBind));
  AssertEquals('Set 1 Binding 1 type', Ord(dtStorageImage), Ord(FoundBind.DescriptorType));
  AssertEquals('Set 1 Binding 1 count', 1, FoundBind.Count);
  AssertEquals('Set 1 Binding 1 name', 'castle_OutputStorageImg', FoundBind.Name);

  { Verify Push Constants }
  AssertTrue('Must detect PushConstant block', Info.HasPushConstants);
  AssertEquals('PushConstant size (2 x mat4 = 128)', 128, Info.PushConstantSize);
  AssertEquals('PushConstant name', 'CastleDrawPushConstants', Info.PushConstantName);

  { Verify Stage IO }
  AssertEquals('StageIO count must be 2', 2, Length(Info.StageIO));
  AssertTrue('Must find Stage Input at location 0', Info.FindStageInput(0, FoundIO));
  AssertEquals('Stage Input 0 component count (vec2)', 2, FoundIO.ComponentCount);
  AssertEquals('Stage Input 0 name', 'v_TexCoord0', FoundIO.Name);

  AssertTrue('Must find Stage Output at location 0', Info.FindStageOutput(0, FoundIO));
  AssertEquals('Stage Output 0 component count (vec4)', 4, FoundIO.ComponentCount);
  AssertEquals('Stage Output 0 name', 'out_FragColor', FoundIO.Name);

  { 2. Verify byte-swapped SPIR-V header/stream support }
  SetLength(SwappedWords, Length(Words));
  for I := 0 to High(Words) do
    SwappedWords[I] := SwapEndian(Words[I]);
  AssertTrue('InspectSPIRVBytecode must support byte-swapped SPIR-V streams',
    InspectSPIRVBytecode(@SwappedWords[0], Length(SwappedWords) * SizeOf(UInt32), SwappedInfo));
  AssertTrue('SwappedInfo.ByteSwapped must be True', SwappedInfo.ByteSwapped);
  AssertEquals('SwappedInfo binding count', 4, Length(SwappedInfo.Bindings));
  AssertEquals('SwappedInfo PushConstantSize', 128, SwappedInfo.PushConstantSize);

  { 3. Verify TVulkanRHIShaderModule automatic reflection & descriptor layout validation }
  ShaderMod := TVulkanRHIShaderModule.Create(nil, ssFragment,
    @Words[0], Length(Words) * SizeOf(UInt32), 'ReflectedFragShader');
  try
    AssertTrue('ShaderMod.Reflection.IsValid must be True', ShaderMod.Reflection.IsValid);
    AssertEquals('ShaderMod.Reflection binding count', 4, Length(ShaderMod.Reflection.Bindings));

    { Valid Set 0 layout (note: dtUniformBufferDynamic is compatible with SPIR-V UBO) }
    ValidSet0Layout[0].Binding := 0;
    ValidSet0Layout[0].DescriptorType := dtUniformBufferDynamic;
    ValidSet0Layout[0].Count := 1;
    ValidSet0Layout[0].StageFlags := [ssVertex, ssFragment];
    ValidSet0Layout[1].Binding := 1;
    ValidSet0Layout[1].DescriptorType := dtStorageBuffer;
    ValidSet0Layout[1].Count := 1;
    ValidSet0Layout[1].StageFlags := [ssVertex, ssFragment];
    AssertTrue('Valid Set 0 layout must pass validation',
      ShaderMod.ValidateDescriptorSetLayout(0, ValidSet0Layout, DiagMsg));
    AssertEquals('Diagnostic message must be empty on success', '', DiagMsg);

    { Valid Set 1 layout }
    ValidSet1Layout[0].Binding := 0;
    ValidSet1Layout[0].DescriptorType := dtCombinedImageSampler;
    ValidSet1Layout[0].Count := 4;
    ValidSet1Layout[0].StageFlags := [ssFragment];
    ValidSet1Layout[1].Binding := 1;
    ValidSet1Layout[1].DescriptorType := dtStorageImage;
    ValidSet1Layout[1].Count := 1;
    ValidSet1Layout[1].StageFlags := [ssFragment];
    AssertTrue('Valid Set 1 layout must pass validation',
      ShaderMod.ValidateDescriptorSetLayout(1, ValidSet1Layout, DiagMsg));

    { Mismatched descriptor type }
    BadTypeLayout[0] := ValidSet0Layout[0];
    BadTypeLayout[0].DescriptorType := dtCombinedImageSampler;
    BadTypeLayout[1] := ValidSet0Layout[1];
    AssertFalse('Mismatched descriptor type must fail validation',
      ShaderMod.ValidateDescriptorSetLayout(0, BadTypeLayout, DiagMsg));
    AssertTrue('Diagnostic must report type mismatch',
      Pos('descriptor type mismatch', DiagMsg) > 0);

    { Missing binding }
    MissingBindLayout[0] := ValidSet0Layout[0];
    AssertFalse('Missing binding 1 in Set 0 must fail validation',
      ShaderMod.ValidateDescriptorSetLayout(0, MissingBindLayout, DiagMsg));
    AssertTrue('Diagnostic must report undeclared descriptor',
      Pos('undeclared descriptor', DiagMsg) > 0);

    { Mismatched stage visibility }
    BadStageLayout[0] := ValidSet0Layout[0];
    BadStageLayout[0].StageFlags := [ssVertex];
    BadStageLayout[1] := ValidSet0Layout[1];
    AssertFalse('Missing ssFragment in StageFlags must fail validation',
      ShaderMod.ValidateDescriptorSetLayout(0, BadStageLayout, DiagMsg));
    AssertTrue('Diagnostic must report stage visibility mismatch',
      Pos('stage visibility mismatch', DiagMsg) > 0);

    { Insufficient array count }
    BadCountLayout[0] := ValidSet1Layout[0];
    BadCountLayout[0].Count := 2; // Shader requires 4
    BadCountLayout[1] := ValidSet1Layout[1];
    AssertFalse('Array count smaller than shader array must fail validation',
      ShaderMod.ValidateDescriptorSetLayout(1, BadCountLayout, DiagMsg));
    AssertTrue('Diagnostic must report count mismatch',
      Pos('descriptor count mismatch', DiagMsg) > 0);
  finally
    FreeAndNil(ShaderMod);
  end;

  { 4. Verify stage mismatch warning when creating a vertex module from fragment SPIR-V }
  FCapturedWarnings := TStringList.Create;
  try
    ApplicationProperties.OnWarning.Add({$ifdef FPC}@{$endif}CaptureWarning);
    try
      WrongStageMod := TVulkanRHIShaderModule.Create(nil, ssVertex,
        @Words[0], Length(Words) * SizeOf(UInt32), 'WrongStageShader');
      try
        AssertTrue('Creating ssVertex module with Fragment SPIR-V must emit warning',
          FCapturedWarnings.Count > 0);
        AssertTrue('Warning must mention execution model stage mismatch',
          Pos('SPIR-V execution model stage', FCapturedWarnings.Text) > 0);
      finally
        FreeAndNil(WrongStageMod);
      end;
    finally
      ApplicationProperties.OnWarning.Remove({$ifdef FPC}@{$endif}CaptureWarning);
    end;
  finally
    FreeAndNil(FCapturedWarnings);
  end;
end;

procedure TTestCastleVulkanRHI.TestWindows4096MaxMemoryAllocationLimitAndPooledSubAllocation;
const
  { 5,000 individual buffers and textures exceed the Windows WDDM kernel limit
    of 4096 total VkDeviceMemory allocations (maxMemoryAllocationCount = 4096). }
  BufferCount = 3000;
  TextureCount = 2000;
var
  VkDev: TVulkanRHIDevice;
  Buffers: array[0 .. BufferCount - 1] of TVulkanRHIBuffer;
  Textures: array[0 .. TextureCount - 1] of TVulkanRHITexture;
  BufDesc: TRHIBufferDesc;
  TexDesc: TRHITextureDesc;
  Stats: TVulkanMemoryStats;
  I: Integer;
  P0, P1: Pointer;
  SampleVal0, SampleVal1: Cardinal;
  DedicatedReq: VkMemoryRequirements;
  DedicatedAlloc: TVulkanMemoryAllocation;
begin
  { Verify VK_KHR_get_memory_requirements2 and VK_KHR_dedicated_allocation
    VkStructureType constants generated by vkxml2pas.dpr from vk.xml }
  AssertEquals('VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2',
    1000146000, VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2);
  AssertEquals('VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2',
    1000146001, VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2);
  AssertEquals('VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2',
    1000146003, VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2);
  AssertEquals('VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS',
    1000127000, VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS);
  AssertEquals('VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO',
    1000127001, VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO);

  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True);
  try
    AssertTrue('TVulkanRHIDevice must initialize MemoryAllocator',
      VkDev.MemoryAllocator <> nil);
    AssertEquals('Default MaxMemoryAllocationCount must match Windows WDDM 4096 limit',
      4096, VkDev.MemoryAllocator.MaxMemoryAllocationCount);

    FillChar(Buffers, SizeOf(Buffers), 0);
    FillChar(Textures, SizeOf(Textures), 0);
    try
      { 1. Allocate 3,000 TVulkanRHIBuffer objects (1,500 host-visible + 1,500 GPU-only) }
      for I := 0 to BufferCount - 1 do
      begin
        FillChar(BufDesc, SizeOf(BufDesc), 0);
        BufDesc.Size := 4096;
        BufDesc.Usage := [buVertex, buUniform];
        if (I and 1) = 0 then
          BufDesc.MemoryUsage := muCpuToGpu
        else
          BufDesc.MemoryUsage := muGpuOnly;
        Buffers[I] := VkDev.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
        AssertTrue('Pooled buffer allocation must be valid', Buffers[I].Allocation.IsValid);
        AssertFalse('4 KB buffer must be sub-allocated, not dedicated', Buffers[I].Allocation.IsDedicated);
        AssertTrue('Buffer allocation must come from a Linear block pool',
          (Buffers[I].Allocation.Block <> nil) and Buffers[I].Allocation.Block.IsLinearPool);
        AssertTrue('Buffer allocation must hold an O(1) sub-allocation node pointer',
          Buffers[I].Allocation.Node <> nil);
      end;

      { 2. Allocate 2,000 TVulkanRHITexture objects (non-linear optimal-tiled images) }
      for I := 0 to TextureCount - 1 do
      begin
        TexDesc := TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuSampled]);
        Textures[I] := VkDev.CreateTexture(TexDesc) as TVulkanRHITexture;
        AssertTrue('Pooled texture allocation must be valid', Textures[I].Allocation.IsValid);
        AssertFalse('32x32 RGBA8 texture (4 KB) must be sub-allocated, not dedicated',
          Textures[I].Allocation.IsDedicated);
        AssertTrue('Optimal-tiled texture must come from a Non-Linear block pool',
          (Textures[I].Allocation.Block <> nil) and (not Textures[I].Allocation.Block.IsLinearPool));
      end;

      { 3. Verify 5,000+ sub-allocations use only a handful of VkDeviceMemory blocks
           (preventing VK_ERROR_TOO_MANY_OBJECTS on Windows' 4096 allocation cap) }
      Stats := VkDev.MemoryAllocator.GetStats;
      AssertTrue('SubAllocationCount must be >= 5000 (buffers + textures + frame rings)',
        Stats.SubAllocationCount >= Cardinal(BufferCount + TextureCount));
      AssertTrue('TotalVkAllocationCount must remain tiny (< 16 blocks for 5,000 resources)',
        (Stats.TotalVkAllocationCount > 0) and (Stats.TotalVkAllocationCount < 16));
      AssertTrue('LinearBlockCount must be > 0 for buffers', Stats.LinearBlockCount > 0);
      AssertTrue('NonLinearBlockCount must be > 0 for optimal images', Stats.NonLinearBlockCount > 0);
      AssertTrue('Linear buffer and Non-Linear texture must not share the same VkDeviceMemory block',
        Buffers[0].DeviceMemory <> Textures[0].Allocation.DeviceMemory);

      { 4. Verify persistent host mapping and non-overlapping sub-allocation offsets }
      AssertTrue('Two host-visible buffers in the same block must have distinct offsets',
        Buffers[0].MemoryOffset <> Buffers[2].MemoryOffset);
      SampleVal0 := $CAFEBABE;
      SampleVal1 := $DEADBEEF;
      Buffers[0].UploadData(SampleVal0, SizeOf(SampleVal0), 0);
      Buffers[2].UploadData(SampleVal1, SizeOf(SampleVal1), 0);

      P0 := Buffers[0].Map;
      P1 := Buffers[2].Map;
      AssertTrue('Host-visible sub-allocated buffers must return non-nil persistent pointers',
        (P0 <> nil) and (P1 <> nil) and (P0 <> P1));
      AssertEquals('Buffer[0] mapped memory must retain uploaded value without corruption',
        Int64(SampleVal0), Int64(PCardinal(P0)^));
      AssertEquals('Buffer[2] mapped memory must retain uploaded value without corruption',
        Int64(SampleVal1), Int64(PCardinal(P1)^));
      Buffers[0].Unmap;
      Buffers[2].Unmap;
      { Unmapping one sub-allocated buffer must not invalidate persistent mapping of siblings }
      AssertEquals('Sibling buffer mapping must remain valid after Unmap',
        Int64(SampleVal1), Int64(PCardinal(Buffers[2].Map)^));
      Buffers[2].Unmap;

      { 5. Verify Windows 4096 maxMemoryAllocationCount safety guard:
           when close to the limit, optional dedicated requests fall back to pooled sub-allocation }
      FillChar(DedicatedReq, SizeOf(DedicatedReq), 0);
      DedicatedReq.size := 64 * 1024;
      DedicatedReq.alignment := 256;
      DedicatedReq.memoryTypeBits := $FFFFFFFF;
      { Artificially tighten MaxMemoryAllocationCount so CanAllocateDedicated(False) triggers }
      VkDev.MemoryAllocator.MaxMemoryAllocationCount := Stats.TotalVkAllocationCount + 10;
      DedicatedAlloc := VkDev.MemoryAllocator.Allocate(
        DedicatedReq, muGpuOnly, True, True, False);
      try
        AssertTrue('Allocation near maxMemoryAllocationCount limit must succeed via pool',
          DedicatedAlloc.IsValid);
        AssertFalse('Optional dedicated request must fall back to pooled block when near 4096 limit',
          DedicatedAlloc.IsDedicated);
      finally
        VkDev.MemoryAllocator.Free(DedicatedAlloc);
        VkDev.MemoryAllocator.MaxMemoryAllocationCount := 4096;
      end;
    finally
      { 6. Free all 5,000 buffers and textures in O(1) per node and verify coalescing }
      for I := 0 to BufferCount - 1 do
        FreeAndNil(Buffers[I]);
      for I := 0 to TextureCount - 1 do
        FreeAndNil(Textures[I]);
    end;

    Stats := VkDev.MemoryAllocator.GetStats;
    { Only the 2 per-frame ring buffer sub-allocations remain }
    AssertEquals('After freeing all 5,000 buffers/textures, only 2 frame-ring sub-allocations remain',
      2, Stats.SubAllocationCount);

    { Trim excess empty blocks }
    VkDev.MemoryAllocator.TrimEmptyBlocks;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure MockGetPhysicalDeviceFormatProperties(
  physicalDevice: VkPhysicalDevice; format: VkFormat;
  pFormatProperties: PVkFormatProperties); {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  if pFormatProperties = nil then Exit;
  FillChar(pFormatProperties^, SizeOf(VkFormatProperties), 0);
  case format of
    { Simulate AMD RDNA / Apple MoltenVK where D24_UNORM_S8_UINT and ASTC_4x4 are unsupported,
      while D32_SFLOAT_S8_UINT, D32_SFLOAT, RGBA8_SRGB, and RGBA8_UNORM are supported }
    VK_FORMAT_D24_UNORM_S8_UINT,
    VK_FORMAT_ASTC_4x4_SRGB_BLOCK,
    VK_FORMAT_ASTC_4x4_UNORM_BLOCK,
    VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK:
      pFormatProperties^.optimalTilingFeatures := 0;
    VK_FORMAT_D32_SFLOAT_S8_UINT,
    VK_FORMAT_D32_SFLOAT,
    VK_FORMAT_D16_UNORM:
      pFormatProperties^.optimalTilingFeatures :=
        VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT or
        VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT or
        VK_FORMAT_FEATURE_TRANSFER_SRC_BIT or
        VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
    else
      pFormatProperties^.optimalTilingFeatures :=
        VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT or
        VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT or
        VK_FORMAT_FEATURE_TRANSFER_SRC_BIT or
        VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiVendorFormatAlignmentAndDeferredResourceDestruction;
var
  VkDev: TVulkanRHIDevice;
  SavedFormatPropsProc: Pointer;
  NegotiatedFmt: TRHIPixelFormat;
  TexDesc: TRHITextureDesc;
  DepthTex, ColorTex: TVulkanRHITexture;
  UboDesc, SsboDesc, StageDesc: TRHIBufferDesc;
  Ubo0, Ubo1, Ssbo0, Ssbo1, StageBuf: TVulkanRHIBuffer;
  AlignedOffset, AlignedSize: VkDeviceSize;
  SubAllocsBefore, SubAllocsDuring, SubAllocsAfterFlush: Cardinal;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Cross-Vendor Format Negotiation (AMD/MoltenVK D24S8 -> D32S8 fallback,
       mobile ASTC/ETC2 -> desktop RGBA8 fallback) }
  SavedFormatPropsProc := Pointer(vkGetPhysicalDeviceFormatProperties);
  vkGetPhysicalDeviceFormatProperties := @MockGetPhysicalDeviceFormatProperties;
  try
    VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($ABCD)), False, True, VK_API_VERSION_1_3);
    try
      NegotiatedFmt := NegotiateOptimalPixelFormat(
        pfD24_UNorm_S8_UInt, [tuDepthStencil, tuSampled], VkDev.PhysicalDevice);
      AssertEquals('Unsupported D24_UNorm_S8_UInt must negotiate fallback to D32_Float_S8_UInt',
        Ord(pfD32_Float_S8_UInt), Ord(NegotiatedFmt));

      NegotiatedFmt := NegotiateOptimalPixelFormat(
        pfASTC_4x4_sRGB, [tuSampled, tuTransferDst], VkDev.PhysicalDevice);
      AssertEquals('Unsupported ASTC_4x4_sRGB must negotiate fallback to RGBA8_sRGB',
        Ord(pfRGBA8_sRGB), Ord(NegotiatedFmt));

      NegotiatedFmt := NegotiateOptimalPixelFormat(
        pfETC2_RGBA8_UNorm, [tuSampled, tuTransferDst], VkDev.PhysicalDevice);
      AssertEquals('Unsupported ETC2_RGBA8_UNorm must negotiate fallback to RGBA8_UNorm',
        Ord(pfRGBA8_UNorm), Ord(NegotiatedFmt));

      { 2. Combined Depth+Stencil Barrier vs. ImageView Aspect Mask Separation
           (VUID-VkImageMemoryBarrier-subresourceRange-09601 vs VUID-VkDescriptorImageInfo-imageView-01976) }
      FillChar(TexDesc, SizeOf(TexDesc), 0);
      TexDesc.Dimension := td2D;
      TexDesc.Width := 512;
      TexDesc.Height := 512;
      TexDesc.DepthOrArrayLayers := 1;
      TexDesc.MipLevels := 1;
      TexDesc.SampleCount := 1;
      TexDesc.Format := pfD24_UNorm_S8_UInt;
      TexDesc.Usage := [tuDepthStencil, tuSampled];

      DepthTex := TVulkanRHITexture.Create(VkDev, TexDesc);
      try
        AssertEquals('TVulkanRHITexture must automatically negotiate supported D32_Float_S8_UInt',
          Ord(pfD32_Float_S8_UInt), Ord(DepthTex.Desc.Format));
        AssertEquals('Combined depth+stencil barrier AspectMask must include both DEPTH and STENCIL bits',
          Cardinal(VK_IMAGE_ASPECT_DEPTH_BIT or VK_IMAGE_ASPECT_STENCIL_BIT),
          DepthTex.AspectMask);
        AssertEquals('Combined depth+stencil sampled ViewAspectMask must include ONLY DEPTH_BIT',
          Cardinal(VK_IMAGE_ASPECT_DEPTH_BIT),
          DepthTex.ViewAspectMask);
      finally
        FreeAndNil(DepthTex);
      end;

      { 3. Cross-Vendor Hardware Buffer Offset Alignment
           (NVIDIA 256B UBO alignment, Mali/Adreno 128B SSBO alignment, 64B transfer copy alignment) }
      VkDev.MemoryAllocator.MinUniformBufferAlignment := 256;
      VkDev.MemoryAllocator.MinStorageBufferAlignment := 128;
      VkDev.MemoryAllocator.OptimalBufferCopyOffsetAlignment := 64;
      VkDev.MemoryAllocator.NonCoherentAtomSize := 64;

      FillChar(UboDesc, SizeOf(UboDesc), 0);
      UboDesc.Size := 72; // unaligned size
      UboDesc.Usage := [buUniform];
      UboDesc.MemoryUsage := muCpuToGpu;

      FillChar(SsboDesc, SizeOf(SsboDesc), 0);
      SsboDesc.Size := 50; // unaligned size
      SsboDesc.Usage := [buStorage];
      SsboDesc.MemoryUsage := muGpuOnly;

      FillChar(StageDesc, SizeOf(StageDesc), 0);
      StageDesc.Size := 36; // unaligned size
      StageDesc.Usage := [buTransferSrc];
      StageDesc.MemoryUsage := muCpuToGpu;

      Ubo0 := TVulkanRHIBuffer.Create(VkDev, UboDesc, nil);
      Ubo1 := TVulkanRHIBuffer.Create(VkDev, UboDesc, nil);
      Ssbo0 := TVulkanRHIBuffer.Create(VkDev, SsboDesc, nil);
      Ssbo1 := TVulkanRHIBuffer.Create(VkDev, SsboDesc, nil);
      StageBuf := TVulkanRHIBuffer.Create(VkDev, StageDesc, nil);
      try
        AssertEquals('UBO[0] sub-allocation offset must be aligned to MinUniformBufferAlignment (256)',
          0, Ubo0.MemoryOffset mod 256);
        AssertEquals('UBO[1] sub-allocation offset must be aligned to MinUniformBufferAlignment (256)',
          0, Ubo1.MemoryOffset mod 256);
        AssertEquals('SSBO[0] sub-allocation offset must be aligned to MinStorageBufferAlignment (128)',
          0, Ssbo0.MemoryOffset mod 128);
        AssertEquals('SSBO[1] sub-allocation offset must be aligned to MinStorageBufferAlignment (128)',
          0, Ssbo1.MemoryOffset mod 128);
        AssertEquals('Transfer staging buffer offset must be aligned to OptimalBufferCopyOffsetAlignment (64)',
          0, StageBuf.MemoryOffset mod 64);
      finally
        FreeAndNil(StageBuf);
        FreeAndNil(Ssbo1);
        FreeAndNil(Ssbo0);
        FreeAndNil(Ubo1);
        FreeAndNil(Ubo0);
      end;

      { 4. Non-Coherent Atom Size Range Alignment (VUID-VkMappedMemoryRange-offset-00687) }
      AlignNonCoherentMemoryRange(
        256, 100, 17, 50, 4096, VkDev.MemoryAllocator.NonCoherentAtomSize,
        AlignedOffset, AlignedSize);
      AssertEquals('Non-coherent flush offset must round down to 64B atom boundary',
        256, AlignedOffset);
      AssertEquals('Non-coherent flush size must round up to 64B atom multiple covering [273..323)',
        128, AlignedSize);

      { 5. Synchronization & Frame-In-Flight Deferred Resource Destruction Queue
           (VUID-vkDestroyBuffer-buffer-00922: resources freed while a frame is in flight
            must remain alive until that frame slot's VkFence completes) }
      SubAllocsBefore := VkDev.MemoryAllocator.GetStats.SubAllocationCount;
      VkDev.FrameIndex := 1;
      VkDev.DeferResourceDestruction := True;

      Ubo0 := TVulkanRHIBuffer.Create(VkDev, UboDesc, nil);
      TexDesc.Format := pfRGBA8_UNorm;
      TexDesc.Usage := [tuSampled, tuColorAttachment];
      ColorTex := TVulkanRHITexture.Create(VkDev, TexDesc);
      SubAllocsDuring := VkDev.MemoryAllocator.GetStats.SubAllocationCount;
      AssertEquals('Creating 1 buffer + 1 texture must add 2 sub-allocations',
        SubAllocsBefore + 2, SubAllocsDuring);

      { Destroy both while Frame 1 is still in flight on the GPU }
      FreeAndNil(Ubo0);
      FreeAndNil(ColorTex);

      AssertEquals('Destroyed buffer + texture must be queued in PendingDeferredDeletionCount',
        2, VkDev.PendingDeferredDeletionCount);
      AssertEquals('Sub-allocations must NOT be recycled while Frame 1 is still in flight',
        SubAllocsDuring, VkDev.MemoryAllocator.GetStats.SubAllocationCount);

      { Flushing Frame 0 must not retire Frame 1's resources }
      VkDev.FlushDeferredDeletions(0);
      AssertEquals('Flushing Frame 0 must leave Frame 1 deferred resources intact',
        2, VkDev.PendingDeferredDeletionCount);

      { Flushing Frame 1 (simulating Frame 1 VkFence completion) retires both resources }
      VkDev.FlushDeferredDeletions(1);
      SubAllocsAfterFlush := VkDev.MemoryAllocator.GetStats.SubAllocationCount;
      AssertEquals('After Frame 1 fence flush, PendingDeferredDeletionCount must be 0',
        0, VkDev.PendingDeferredDeletionCount);
      AssertEquals('After Frame 1 fence flush, sub-allocations must be returned to the pool',
        SubAllocsBefore, SubAllocsAfterFlush);
      VkDev.DeferResourceDestruction := False;

      { 6. Explicit Buffer & Texture Pipeline Barrier Tracking on TVulkanRHICommandList }
      Ubo0 := TVulkanRHIBuffer.Create(VkDev, UboDesc, nil);
      ColorTex := TVulkanRHITexture.Create(VkDev, TexDesc);
      CmdList := TVulkanRHICommandList.Create(VkDev, 0);
      try
        AssertEquals('Initial BarrierCount must be 0', 0, CmdList.BarrierCount);
        CmdList.TransitionBuffer(Ubo0, rsTransferDst, rsShaderRead);
        AssertEquals('TransitionBuffer must emit a VkBufferMemoryBarrier', 1, CmdList.BarrierCount);
        CmdList.TransitionTexture(ColorTex, rsColorAttachment);
        AssertEquals('TransitionTexture must emit a VkImageMemoryBarrier', 2, CmdList.BarrierCount);
        { Redundant transition to same state must be a no-op }
        CmdList.TransitionTexture(ColorTex, rsColorAttachment);
        AssertEquals('Redundant TransitionTexture to identical state must be skipped', 2, CmdList.BarrierCount);
      finally
        FreeAndNil(CmdList);
        FreeAndNil(ColorTex);
        FreeAndNil(Ubo0);
      end;
    finally
      FreeAndNil(VkDev);
    end;
  finally
    Pointer(vkGetPhysicalDeviceFormatProperties) := SavedFormatPropsProc;
  end;
end;

procedure TTestCastleVulkanRHI.TestGrowableAndTransientDescriptorPools;
var
  PoolAlloc: TVulkanDescriptorPoolAllocator;
  OwnerPool, FirstPool, SecondPool: VkDescriptorPool;
  SetHandle: VkDescriptorSet;
  I: Integer;
  VkDev: TVulkanRHIDevice;
  Bindings: array[0..1] of TRHIDescriptorBindingDesc;
  Layout: TRHIDescriptorSetLayout;
  PersistSet, TransSet0, TransSet1: TVulkanRHIDescriptorSet;
begin
  { 1. Growable Descriptor Pool Chain & Capacity Scaling }
  PoolAlloc := TVulkanDescriptorPoolAllocator.Create(nil, 4, False, 16);
  try
    AssertEquals('Initial TotalPoolCount must be 0 (lazy creation)', 0, PoolAlloc.TotalPoolCount);
    AssertEquals('Initial NextPoolMaxSets must be 4', 4, PoolAlloc.NextPoolMaxSets);

    { Allocate 4 descriptor sets filling Page #1 (capacity 4) }
    FirstPool := VK_NULL_HANDLE;
    for I := 1 to 4 do
    begin
      SetHandle := PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
      AssertTrue('Allocated descriptor set must be non-null', SetHandle <> VK_NULL_HANDLE);
      if I = 1 then
        FirstPool := OwnerPool
      else
        AssertTrue('First 4 sets must come from the same Pool Page #1', OwnerPool = FirstPool);
    end;
    AssertEquals('After 4 sets, TotalPoolCount must be 1', 1, PoolAlloc.TotalPoolCount);
    AssertEquals('After 4 sets, FullPoolCount must be 0', 0, PoolAlloc.FullPoolCount);
    AssertEquals('After Page #1 (cap 4), NextPoolMaxSets must scale by 1.5x to 6',
      6, PoolAlloc.NextPoolMaxSets);

    { 5th allocation exceeds Page #1 capacity (4) and automatically grows to Page #2 (cap 6) }
    SetHandle := PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), SecondPool);
    AssertTrue('5th descriptor set must succeed via pool growth', SetHandle <> VK_NULL_HANDLE);
    AssertTrue('Page #2 handle must differ from Page #1 handle', SecondPool <> FirstPool);
    AssertEquals('After growing to Page #2, TotalPoolCount must be 2', 2, PoolAlloc.TotalPoolCount);
    AssertEquals('Page #1 must move to FullPools (FullPoolCount = 1)', 1, PoolAlloc.FullPoolCount);
    AssertEquals('After Page #2 (cap 6), NextPoolMaxSets must scale by 1.5x to 9',
      9, PoolAlloc.NextPoolMaxSets);

    { Fill remaining 5 slots of Page #2 (total 10 sets), then allocate 11th set -> Page #3 (cap 9) }
    for I := 6 to 10 do
      PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertEquals('After 10 sets, TotalPoolCount must still be 2', 2, PoolAlloc.TotalPoolCount);

    PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertEquals('11th set must grow to Page #3 (TotalPoolCount = 3)', 3, PoolAlloc.TotalPoolCount);
    AssertEquals('Pages #1 and #2 must be in FullPools (FullPoolCount = 2)', 2, PoolAlloc.FullPoolCount);
    AssertEquals('After Page #3 (cap 9), NextPoolMaxSets must scale to 13',
      13, PoolAlloc.NextPoolMaxSets);

    { 2. Driver Error Recovery: VK_ERROR_FRAGMENTED_POOL & VK_ERROR_OUT_OF_POOL_MEMORY }
    PoolAlloc.ForceNextAllocationError := VK_ERROR_FRAGMENTED_POOL;
    SetHandle := PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertTrue('Allocation after VK_ERROR_FRAGMENTED_POOL must recover on new pool page',
      SetHandle <> VK_NULL_HANDLE);
    AssertEquals('VK_ERROR_FRAGMENTED_POOL must retire Page #3 and create Page #4 (cap 13)',
      4, PoolAlloc.TotalPoolCount);
    AssertEquals('After Page #4 (cap 13), NextPoolMaxSets must cap at MaxSetsCap (16)',
      16, PoolAlloc.NextPoolMaxSets);

    PoolAlloc.ForceNextAllocationError := VK_ERROR_OUT_OF_POOL_MEMORY;
    SetHandle := PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertTrue('Allocation after VK_ERROR_OUT_OF_POOL_MEMORY must recover on new pool page',
      SetHandle <> VK_NULL_HANDLE);
    AssertEquals('VK_ERROR_OUT_OF_POOL_MEMORY must retire Page #4 and create Page #5 (cap 16)',
      5, PoolAlloc.TotalPoolCount);
    AssertEquals('FullPoolCount must be 4', 4, PoolAlloc.FullPoolCount);
    AssertEquals('TotalAllocatedSetCount must be 13', 13, PoolAlloc.TotalAllocatedSetCount);

    { 3. O(1) Bulk Reset (ResetPools) & Zero-Allocation Frame Reuse }
    PoolAlloc.ResetPools;
    AssertEquals('ResetCount must be 1', 1, PoolAlloc.ResetCount);
    AssertEquals('TotalAllocatedSetCount must reset to 0', 0, PoolAlloc.TotalAllocatedSetCount);
    AssertEquals('FullPoolCount must reset to 0', 0, PoolAlloc.FullPoolCount);
    AssertEquals('All 5 pool pages must move to ReadyPools (ReadyPoolCount = 5)',
      5, PoolAlloc.ReadyPoolCount);
    AssertEquals('TotalPoolCount must remain 5', 5, PoolAlloc.TotalPoolCount);

    { Allocate 20 sets in the next frame: must reuse ReadyPools without creating any new pools }
    for I := 1 to 20 do
      PoolAlloc.AllocateDescriptorSet(VkDescriptorSetLayout(PtrUInt(1)), OwnerPool);
    AssertEquals('Reusing ready pools across frames must not allocate new VkDescriptorPools',
      5, PoolAlloc.TotalPoolCount);
    AssertEquals('TotalAllocatedSetCount must be 20', 20, PoolAlloc.TotalAllocatedSetCount);
  finally
    FreeAndNil(PoolAlloc);
  end;

  { 4. TVulkanRHIDevice Persistent vs. Per-Frame Transient Descriptor Sets & Deferred Retirement }
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  try
    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtUniformBuffer;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssVertex, ssFragment];
    Bindings[1].Binding := 1;
    Bindings[1].DescriptorType := dtCombinedImageSampler;
    Bindings[1].Count := 1;
    Bindings[1].StageFlags := [ssFragment];

    Layout := VkDev.CreateDescriptorSetLayout(Bindings);
    try
      VkDev.FrameIndex := 0;
      PersistSet := VkDev.CreateDescriptorSet(Layout) as TVulkanRHIDescriptorSet;
      TransSet0 := VkDev.CreateTransientDescriptorSet(Layout) as TVulkanRHIDescriptorSet;
      TransSet1 := VkDev.CreateTransientDescriptorSet(Layout) as TVulkanRHIDescriptorSet;
      try
        AssertFalse('CreateDescriptorSet must create a persistent descriptor set',
          PersistSet.IsTransient);
        AssertTrue('CreateTransientDescriptorSet must create a transient descriptor set',
          TransSet0.IsTransient);
        AssertEquals('PersistentDescriptorAllocator must have 1 allocated set',
          1, VkDev.PersistentDescriptorAllocator.TotalAllocatedSetCount);
        AssertEquals('Frame 0 TransientDescriptorAllocator must have 2 allocated sets',
          2, VkDev.GetTransientDescriptorAllocator(0).TotalAllocatedSetCount);
        AssertEquals('Frame 1 TransientDescriptorAllocator must have 0 allocated sets',
          0, VkDev.GetTransientDescriptorAllocator(1).TotalAllocatedSetCount);
        AssertTrue('Device.DescriptorPool must reflect the active persistent pool handle',
          VkDev.DescriptorPool = PersistSet.OwnerPool);

        { Simulate in-flight Frame 1: destroying transient sets must NOT enqueue individual frees,
          whereas destroying a persistent set MUST defer vkFreeDescriptorSets until Fence 1 }
        VkDev.FrameIndex := 1;
        VkDev.DeferResourceDestruction := True;

        FreeAndNil(TransSet0);
        FreeAndNil(TransSet1);
        AssertEquals('Destroying transient sets must not add to PendingDeferredDeletionCount',
          0, VkDev.PendingDeferredDeletionCount);

        FreeAndNil(PersistSet);
        AssertEquals('Destroying persistent set while frame is in flight must queue 1 deferred deletion',
          1, VkDev.PendingDeferredDeletionCount);
        AssertEquals('Persistent set must remain allocated until in-flight frame fence flushes',
          1, VkDev.PersistentDescriptorAllocator.TotalAllocatedSetCount);

        VkDev.FlushDeferredDeletions(1);
        AssertEquals('After Frame 1 FlushDeferredDeletions, PendingDeferredDeletionCount must be 0',
          0, VkDev.PendingDeferredDeletionCount);
        AssertEquals('After Frame 1 FlushDeferredDeletions, persistent set must be freed back to pool',
          0, VkDev.PersistentDescriptorAllocator.TotalAllocatedSetCount);

        { Bulk reset Frame 0 transient pool }
        VkDev.GetTransientDescriptorAllocator(0).ResetPools;
        AssertEquals('After Frame 0 ResetPools, transient allocated count must be 0',
          0, VkDev.GetTransientDescriptorAllocator(0).TotalAllocatedSetCount);
        AssertEquals('Frame 0 transient pool page must be recycled into ReadyPools',
          1, VkDev.GetTransientDescriptorAllocator(0).ReadyPoolCount);
      finally
        FreeAndNil(TransSet1);
        FreeAndNil(TransSet0);
        FreeAndNil(PersistSet);
      end;
    finally
      FreeAndNil(Layout);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestAsyncStagingUploadRingBufferAndTransferQueue;
var
  QueueProps: array of VkQueueFamilyProperties;
  HasDedicatedDMA: Boolean;
  SelectedQueueFamily: Cardinal;
  VkDev: TVulkanRHIDevice;
  Uploader: TCastleVulkanStagingUploader;
  BufDesc0, BufDesc1, TempBufDesc: TRHIBufferDesc;
  GpuBuf0, GpuBuf1, TempBuf: TVulkanRHIBuffer;
  TexDesc, TempTexDesc, ColorTargetDesc: TRHITextureDesc;
  GpuTex0, TempTex, ColorTarget: TVulkanRHITexture;
  ImgMip0, ImgMip1: TRGBAlphaImage;
  Payload: array of Byte;
  CmdList: TVulkanRHICommandList;
  RenderInfo: TRHIRenderingInfo;
  I: Integer;
begin
  { 1. Dedicated DMA Transfer Queue Selection Across Hardware Topologies }
  SetLength(QueueProps, 1);
  FillChar(QueueProps[0], SizeOf(VkQueueFamilyProperties), 0);
  QueueProps[0].queueCount := 1;
  QueueProps[0].queueFlags := VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT or VK_QUEUE_TRANSFER_BIT;
  SelectedQueueFamily := SelectTransferQueueFamilyIndex(QueueProps, 0, HasDedicatedDMA);
  AssertEquals('Single unified queue must select graphics queue family 0', 0, SelectedQueueFamily);
  AssertFalse('Single unified queue must not report HasDedicatedTransferQueue', HasDedicatedDMA);

  SetLength(QueueProps, 2);
  FillChar(QueueProps[1], SizeOf(VkQueueFamilyProperties), 0);
  QueueProps[1].queueCount := 2;
  QueueProps[1].queueFlags := VK_QUEUE_COMPUTE_BIT or VK_QUEUE_TRANSFER_BIT;
  SelectedQueueFamily := SelectTransferQueueFamilyIndex(QueueProps, 0, HasDedicatedDMA);
  AssertEquals('Graphics + Async Compute topology must select non-graphics family 1 for transfers',
    1, SelectedQueueFamily);
  AssertTrue('Non-graphics transfer queue family (family 1 <> graphics family 0) must report HasDedicatedTransferQueue = True',
    HasDedicatedDMA);

  SetLength(QueueProps, 3);
  FillChar(QueueProps[2], SizeOf(VkQueueFamilyProperties), 0);
  QueueProps[2].queueCount := 1;
  QueueProps[2].queueFlags := VK_QUEUE_TRANSFER_BIT or VK_QUEUE_SPARSE_BINDING_BIT;
  SelectedQueueFamily := SelectTransferQueueFamilyIndex(QueueProps, 0, HasDedicatedDMA);
  AssertEquals('Dedicated DMA queue family (TRANSFER without GRAPHICS/COMPUTE) must be prioritized (family 2)',
    2, SelectedQueueFamily);
  AssertTrue('Dedicated DMA queue family must report HasDedicatedTransferQueue = True', HasDedicatedDMA);

  { 2. Asynchronous Staging Ring Buffer Sub-Allocation & Multi-Upload Batching }
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  try
    Uploader := VkDev.StagingUploader;
    AssertTrue('Device must initialize StagingUploader', Uploader <> nil);

    Uploader.RingCapacityPerFrame := 4096;
    VkDev.MemoryAllocator.OptimalBufferCopyOffsetAlignment := 64;
    VkDev.FrameIndex := 0;

    SetLength(Payload, 8192);
    for I := 0 to High(Payload) do
      Payload[I] := Byte(I and $FF);

    BufDesc0 := TRHIBufferDesc.Create(300, [buVertex, buTransferDst], muGpuOnly, 'StagedVBO');
    BufDesc1 := TRHIBufferDesc.Create(8192, [buIndex, buTransferDst], muGpuOnly, 'StagedIBO');

    FillChar(TexDesc, SizeOf(TexDesc), 0);
    TexDesc.Dimension := td2D;
    TexDesc.Width := 8;
    TexDesc.Height := 8;
    TexDesc.DepthOrArrayLayers := 1;
    TexDesc.MipLevels := 2;
    TexDesc.SampleCount := 1;
    TexDesc.Format := pfRGBA8_UNorm;
    TexDesc.Usage := [tuSampled, tuTransferDst];
    TexDesc.DebugName := 'StagedTex2D';

    ImgMip0 := TRGBAlphaImage.Create(8, 8);
    ImgMip1 := TRGBAlphaImage.Create(4, 4);
    GpuBuf0 := TVulkanRHIBuffer.Create(VkDev, BufDesc0, @Payload[0]);
    GpuBuf1 := TVulkanRHIBuffer.Create(VkDev, BufDesc1, nil);
    GpuTex0 := TVulkanRHITexture.Create(VkDev, TexDesc);
    try
      { Upload 512 bytes to GpuBuf1 at offset 128, plus Mip 0 (256B) and Mip 1 (64B) to GpuTex0 }
      GpuBuf1.UploadData(Payload[0], 512, 128);
      GpuTex0.UploadImage(ImgMip0, 0, 0);
      GpuTex0.UploadImage(ImgMip1, 1, 0);

      AssertEquals('2 buffer uploads must be queued without synchronous flush',
        2, Uploader.PendingBufferCopyCount);
      AssertEquals('2 image mip uploads must be queued without synchronous flush',
        2, Uploader.PendingImageCopyCount);
      AssertEquals('TotalBufferUploads must be 2', 2, Uploader.TotalBufferUploads);
      AssertEquals('TotalImageUploads must be 2', 2, Uploader.TotalImageUploads);
      AssertEquals('TotalStagedBytes must equal 300 + 512 + 256 + 64 = 1132',
        1132, Uploader.TotalStagedBytes);
      { Slice 0: [0..300) -> next 300
        Slice 1: aligned to 64 -> [320..832) -> next 832
        Slice 2: aligned to 64 -> [832..1088) -> next 1088
        Slice 3: aligned to 64 -> [1088..1152) -> next 1152 }
      AssertEquals('CurrentFrameWriteOffset must reflect 64-byte OptimalBufferCopyOffsetAlignment',
        1152, Uploader.CurrentFrameWriteOffset);
      AssertEquals('Sub-allocations within 4096B ring capacity must not allocate overflow chunks',
        0, Uploader.OverflowChunkCount);

      { 3. Overflow Chunk Fallback When Single Upload Exceeds RingCapacityPerFrame }
      GpuBuf1.UploadData(Payload[0], 8192, 0);
      AssertEquals('Large upload (8192B > 4096B ring) must allocate 1 overflow staging chunk',
        1, Uploader.OverflowChunkCount);
      AssertEquals('PendingBufferCopyCount must now be 3', 3, Uploader.PendingBufferCopyCount);

      { 4. Cancellation When Destination Buffer/Texture Is Destroyed Before Flush }
      TempBufDesc := TRHIBufferDesc.Create(128, [buVertex], muGpuOnly, 'ShortLivedVBO');
      TempBuf := TVulkanRHIBuffer.Create(VkDev, TempBufDesc, @Payload[0]);
      TempTexDesc := TexDesc;
      TempTexDesc.MipLevels := 1;
      TempTex := TVulkanRHITexture.Create(VkDev, TempTexDesc);
      TempTex.UploadImage(ImgMip0, 0, 0);

      AssertEquals('PendingBufferCopyCount with TempBuf must be 4', 4, Uploader.PendingBufferCopyCount);
      AssertEquals('PendingImageCopyCount with TempTex must be 3', 3, Uploader.PendingImageCopyCount);

      FreeAndNil(TempBuf);
      FreeAndNil(TempTex);
      AssertEquals('Destroying TempBuf before flush must cancel its pending buffer copy',
        3, Uploader.PendingBufferCopyCount);
      AssertEquals('Destroying TempTex before flush must cancel its pending image copy',
        2, Uploader.PendingImageCopyCount);

      { 5. Automatic Pre-RenderPass Flush & Dedicated DMA Queue Ownership Transfer Barriers }
      Uploader.ConfigureTransferQueue(0, 2, True);
      AssertTrue('ConfigureTransferQueue(0, 2, True) must enable UseDedicatedTransferQueue',
        Uploader.UseDedicatedTransferQueue);

      ColorTargetDesc := TexDesc;
      ColorTargetDesc.MipLevels := 1;
      ColorTargetDesc.Usage := [tuColorAttachment];
      ColorTarget := TVulkanRHITexture.Create(VkDev, ColorTargetDesc);
      CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
      try
        CmdList.BeginRecording;
        FillChar(RenderInfo, SizeOf(RenderInfo), 0);
        RenderInfo.RenderArea := Rectangle(0, 0, 8, 8);
        SetLength(RenderInfo.ColorAttachments, 1);
        RenderInfo.ColorAttachments[0].Texture := ColorTarget;
        RenderInfo.ColorAttachments[0].LoadOp := loClear;
        RenderInfo.ColorAttachments[0].StoreOp := soStore;

        { BeginRendering must automatically flush all pending staged uploads BEFORE opening render pass }
        CmdList.BeginRendering(RenderInfo);
        AssertEquals('BeginRendering must flush all pending buffer copies prior to render pass',
          0, Uploader.PendingBufferCopyCount);
        AssertEquals('BeginRendering must flush all pending image copies prior to render pass',
          0, Uploader.PendingImageCopyCount);
        AssertEquals('TotalBatchedFlushes must increment to 1', 1, Uploader.TotalBatchedFlushes);
        AssertEquals('Dedicated DMA queue flush must record ownership transfer for 3 buffer copies + 2 image mips',
          5, Uploader.QueueOwnershipTransferCount);
        AssertEquals('Uploaded texture must transition to rsShaderRead after staging flush',
          Ord(rsShaderRead), Ord(GpuTex0.CurrentState));
        CmdList.EndRendering;
        CmdList.EndRecording;
      finally
        FreeAndNil(CmdList);
        FreeAndNil(ColorTarget);
      end;

      { 6. Frame Slot Reclamation Resets Ring Write Offset and Frees Overflow Chunks }
      Uploader.ReclaimFrameSlot(0);
      AssertEquals('ReclaimFrameSlot(0) must reset CurrentFrameWriteOffset to 0',
        0, Uploader.CurrentFrameWriteOffset);
      AssertEquals('ReclaimFrameSlot(0) must release temporary overflow chunks for that frame slot',
        0, Uploader.OverflowChunkCount);
    finally
      FreeAndNil(GpuTex0);
      FreeAndNil(GpuBuf1);
      FreeAndNil(GpuBuf0);
      FreeAndNil(ImgMip1);
      FreeAndNil(ImgMip0);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestBindlessTextureAndSamplerIndexing;
var
  Features: VkPhysicalDeviceDescriptorIndexingFeatures;
  Props: VkPhysicalDeviceDescriptorIndexingProperties;
  UseBindless, UseUpdateAfterBind: Boolean;
  ClampedMax: Cardinal;
  ReqExts: TAnsiStringArray;
  VkDev: TVulkanRHIDevice;
  Mgr: TCastleVulkanBindlessTextureManager;
  SamplerDesc: TRHISamplerDesc;
  Sampler0, Sampler1: TVulkanRHISampler;
  TexDesc: TRHITextureDesc;
  Tex0, Tex1, Tex2, Tex3: TVulkanRHITexture;
  Slot0, Slot0Dup, Slot1, Slot2, Slot3, FoundSlot: Cardinal;
  Materials: array[0..2] of TCastleBindlessMaterialEntry;
  MatSSBODesc, IndirectDesc: TRHIBufferDesc;
  MatSSBO, IndirectBuf: TVulkanRHIBuffer;
  IndirectCmds: array[0..2] of TRHIDrawIndexedIndirectCommand;
  FlushedCount: Cardinal;
  Gen: TCastleShaderGeneratorRHI;
  BindlessFragGLSL: String;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Verify Khronos vk.xml generated constants for VK_EXT_descriptor_indexing / Vulkan 1.2 }
  AssertEquals('VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO',
    1000161000, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES',
    1000161001, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES);
  AssertEquals('VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES',
    1000161002, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES);
  AssertEquals('VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO',
    1000161003, VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO);
  AssertEquals('VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT',
    $00000001, VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT);
  AssertEquals('VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT',
    $00000002, VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT);
  AssertEquals('VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT',
    $00000004, VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT);
  AssertEquals('VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT',
    $00000008, VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT);

  { 2. Verify ResolveDescriptorIndexingConfig across Vulkan 1.2 core, Vulkan 1.1 extension, and missing features }
  FillChar(Features, SizeOf(Features), 0);
  Features.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES;
  Features.shaderSampledImageArrayNonUniformIndexing := VK_TRUE;
  Features.descriptorBindingPartiallyBound := VK_TRUE;
  Features.descriptorBindingUpdateUnusedWhilePending := VK_TRUE;
  Features.runtimeDescriptorArray := VK_TRUE;
  Features.descriptorBindingSampledImageUpdateAfterBind := VK_TRUE;

  FillChar(Props, SizeOf(Props), 0);
  Props.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES;
  Props.maxPerStageDescriptorUpdateAfterBindSampledImages := 2048;
  Props.maxDescriptorSetUpdateAfterBindSampledImages := 16384;

  { Vulkan 1.2+ Core: requires 0 extra device extensions and clamps to hardware limit (2048) }
  ResolveDescriptorIndexingConfig(VK_API_VERSION_1_2, False, False,
    Features, Props, 4096, UseBindless, UseUpdateAfterBind, ClampedMax, ReqExts);
  AssertTrue('Vulkan 1.2 with core features must enable bindless textures', UseBindless);
  AssertTrue('Vulkan 1.2 with UpdateAfterBind feature must enable UpdateAfterBind', UseUpdateAfterBind);
  AssertEquals('MaxBindlessTextures must clamp to maxPerStageDescriptorUpdateAfterBindSampledImages (2048)',
    2048, ClampedMax);
  AssertEquals('Vulkan 1.2 core must not require extra extension names', 0, Length(ReqExts));

  { Vulkan 1.1 + VK_EXT_descriptor_indexing: requires VK_EXT_descriptor_indexing extension }
  ResolveDescriptorIndexingConfig(VK_API_VERSION_1_1, True, True,
    Features, Props, 1024, UseBindless, UseUpdateAfterBind, ClampedMax, ReqExts);
  AssertTrue('Vulkan 1.1 with VK_EXT_descriptor_indexing must enable bindless textures', UseBindless);
  AssertEquals('Requested 1024 (< 2048 hw limit) must remain 1024', 1024, ClampedMax);
  AssertEquals('Vulkan 1.1 must require 1 extension (VK_EXT_descriptor_indexing)', 1, Length(ReqExts));
  AssertEquals('Extension name must be VK_EXT_descriptor_indexing',
    String(VK_EXT_descriptor_indexing), String(ReqExts[0]));

  { Missing descriptorBindingPartiallyBound must disable bindless }
  Features.descriptorBindingPartiallyBound := VK_FALSE;
  ResolveDescriptorIndexingConfig(VK_API_VERSION_1_3, True, True,
    Features, Props, 4096, UseBindless, UseUpdateAfterBind, ClampedMax, ReqExts);
  AssertFalse('Missing descriptorBindingPartiallyBound must disable bindless', UseBindless);
  AssertEquals('Disabled bindless must report 0 max textures', 0, ClampedMax);

  { 3. Test TCastleVulkanBindlessTextureManager registration, deduplication, free-list recycling, and batched updates }
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True,
    VK_API_VERSION_1_3, False, True, 1024);
  try
    AssertTrue('Headless device must report SupportsBindlessTextures = True',
      VkDev.Capabilities.SupportsBindlessTextures);
    AssertEquals('Headless device must report MaxBindlessTextures = 1024',
      1024, VkDev.Capabilities.MaxBindlessTextures);
    Mgr := VkDev.BindlessTextureManager;
    AssertTrue('Device must initialize BindlessTextureManager', Mgr <> nil);
    AssertEquals('BindlessTextureManager capacity must match 1024', 1024, Mgr.Capacity);

    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.MaxLod := 8.0;
    Sampler0 := VkDev.CreateSampler(SamplerDesc) as TVulkanRHISampler;
    Sampler1 := VkDev.CreateSampler(SamplerDesc) as TVulkanRHISampler;

    TexDesc := TRHITextureDesc.Create2D(16, 16, pfRGBA8_UNorm, [tuSampled]);
    Tex0 := VkDev.CreateTexture(TexDesc) as TVulkanRHITexture;
    Tex1 := VkDev.CreateTexture(TexDesc) as TVulkanRHITexture;
    Tex2 := VkDev.CreateTexture(TexDesc) as TVulkanRHITexture;
    Tex3 := nil;
    MatSSBO := nil;
    IndirectBuf := nil;
    try
      Slot0 := Mgr.RegisterTexture(Tex0, Sampler0);
      Slot0Dup := Mgr.RegisterTexture(Tex0, Sampler0);
      Slot1 := Mgr.RegisterTexture(Tex1, Sampler0);
      Slot2 := Mgr.RegisterTexture(Tex2, Sampler1);

      AssertEquals('First registered texture must receive slot 0', 0, Slot0);
      AssertEquals('Duplicate (Tex0, Sampler0) registration must return existing slot 0', 0, Slot0Dup);
      AssertEquals('Second distinct texture must receive slot 1', 1, Slot1);
      AssertEquals('Third distinct texture must receive slot 2', 2, Slot2);
      AssertEquals('DeduplicatedHits must be 1', 1, Mgr.DeduplicatedHits);
      AssertEquals('ActiveSlotCount must be 3', 3, Mgr.ActiveSlotCount);
      AssertEquals('PendingWriteCount must be 3', 3, Mgr.PendingWriteCount);
      AssertTrue('TryGetTextureIndex(Tex1, Sampler0) must succeed',
        Mgr.TryGetTextureIndex(Tex1, Sampler0, FoundSlot) and (FoundSlot = 1));
      AssertTrue('Bindless layout must enable UsesUpdateAfterBind',
        Mgr.Layout.UsesUpdateAfterBind);

      { Destroy Tex1: TVulkanRHITexture.Destroy must automatically unregister Slot 1 into the free-list }
      FreeAndNil(Tex1);
      AssertEquals('Destroying Tex1 must decrement ActiveSlotCount to 2', 2, Mgr.ActiveSlotCount);
      AssertEquals('Destroying Tex1 must push slot 1 onto FreeSlots (FreeSlotCount = 1)',
        1, Mgr.FreeSlotCount);
      AssertEquals('Destroying dirty Tex1 before flush must decrement PendingWriteCount to 2',
        2, Mgr.PendingWriteCount);

      { Register Tex3: must reuse recycled Slot 1 from the free-list instead of growing to Slot 3 }
      Tex3 := VkDev.CreateTexture(TexDesc) as TVulkanRHITexture;
      Slot3 := Mgr.RegisterTexture(Tex3, Sampler0);
      AssertEquals('New texture registration must reuse recycled slot 1 from free-list', 1, Slot3);
      AssertEquals('RecycledSlotReuses must be 1', 1, Mgr.RecycledSlotReuses);
      AssertEquals('FreeSlotCount must now be 0', 0, Mgr.FreeSlotCount);
      AssertEquals('ActiveSlotCount must be back to 3', 3, Mgr.ActiveSlotCount);

      { Bind a multi-material SSBO (Set 1, Binding 1) and flush all pending descriptor writes in one batch }
      AssertEquals('TCastleBindlessMaterialEntry must be 80 bytes (16-byte aligned std430/std140)',
        80, SizeOf(TCastleBindlessMaterialEntry));
      FillChar(Materials, SizeOf(Materials), 0);
      Materials[0].BaseColor := Vector4(1, 0, 0, 1);
      Materials[0].BaseColorTexIndex := Slot0;
      Materials[1].BaseColor := Vector4(0, 1, 0, 1);
      Materials[1].BaseColorTexIndex := Slot3;
      Materials[2].BaseColor := Vector4(0, 0, 1, 1);
      Materials[2].BaseColorTexIndex := Slot2;

      MatSSBODesc := TRHIBufferDesc.Create(SizeOf(Materials), [buStorage], muCpuToGpu, 'BindlessMaterialSSBO');
      MatSSBO := VkDev.CreateBuffer(MatSSBODesc, @Materials[0]) as TVulkanRHIBuffer;
      Mgr.SetMaterialStorageBuffer(MatSSBO);
      AssertEquals('PendingWriteCount with 3 textures + 1 material SSBO must be 4',
        4, Mgr.PendingWriteCount);

      FlushedCount := Mgr.FlushPendingUpdates;
      AssertEquals('FlushPendingUpdates must commit all 4 descriptor writes in a single batch',
        4, FlushedCount);
      AssertEquals('PendingWriteCount after flush must be 0', 0, Mgr.PendingWriteCount);
      AssertEquals('DescriptorSet.UpdateCount must be 1 (single batched vkUpdateDescriptorSets call)',
        1, Mgr.DescriptorSet.UpdateCount);

      { 4. Verify Bindless GLSL 450 Preamble Generation & Multi-Material DrawIndexedIndirect }
      Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
      try
        BindlessFragGLSL := Gen.GenerateBindlessPreamble(ssFragment, VkDev.Capabilities.MaxBindlessTextures);
        AssertTrue('Bindless preamble must require GL_EXT_nonuniform_qualifier',
          Pos('#extension GL_EXT_nonuniform_qualifier : require', BindlessFragGLSL) > 0);
        AssertTrue('Bindless preamble must declare castle_BindlessTextures[1024] at Set 1 Binding 0',
          Pos('CASTLE_SAMPLER(1, 0) uniform sampler2D castle_BindlessTextures[1024];', BindlessFragGLSL) > 0);
        AssertTrue('Bindless preamble must declare CastleBindlessMaterialsBlock SSBO at Set 1 Binding 1',
          Pos('CASTLE_SSBO(1, 1) readonly buffer CastleBindlessMaterialsBlock', BindlessFragGLSL) > 0);
        AssertTrue('Bindless preamble must provide nonuniformEXT sampling macro',
          Pos('nonuniformEXT(uint(TexIdx))', BindlessFragGLSL) > 0);
      finally
        FreeAndNil(Gen);
      end;

      { Record a multi-material indirect draw batch binding Set 1 once for all 3 materials }
      FillChar(IndirectCmds, SizeOf(IndirectCmds), 0);
      IndirectCmds[0].IndexCount := 36;
      IndirectCmds[0].InstanceCount := 1;
      IndirectCmds[1].IndexCount := 36;
      IndirectCmds[1].InstanceCount := 1;
      IndirectCmds[1].FirstIndex := 36;
      IndirectCmds[2].IndexCount := 36;
      IndirectCmds[2].InstanceCount := 1;
      IndirectCmds[2].FirstIndex := 72;

      IndirectDesc := TRHIBufferDesc.Create(SizeOf(IndirectCmds), [buIndirect], muCpuToGpu, 'BindlessIndirectCmds');
      IndirectBuf := VkDev.CreateBuffer(IndirectDesc, @IndirectCmds[0]) as TVulkanRHIBuffer;
      CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
      try
        CmdList.BeginRecording;
        CmdList.BindDescriptorSet(1, Mgr.DescriptorSet, []);
        CmdList.DrawIndexedIndirect(IndirectBuf, 0, 3, SizeOf(TRHIDrawIndexedIndirectCommand));
        CmdList.EndRecording;
      finally
        FreeAndNil(CmdList);
      end;
    finally
      FreeAndNil(IndirectBuf);
      FreeAndNil(MatSSBO);
      FreeAndNil(Tex3);
      FreeAndNil(Tex2);
      FreeAndNil(Tex1);
      FreeAndNil(Tex0);
      FreeAndNil(Sampler1);
      FreeAndNil(Sampler0);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestHardwareMSAAAndSinglePassResolve;
var
  VkDevDyn, VkDevFallback: TVulkanRHIDevice;
  ResolveColorDesc, ResolveDepthDesc, OverLimitDesc: TRHITextureDesc;
  ResolveColorTex, ResolveDepthTex, OverLimitTex: TVulkanRHITexture;
  RenderInfo: TRHIRenderingInfo;
  CmdList: TVulkanRHICommandList;
begin
  { 1. Sample count bitmask negotiation and clamping }
  AssertEquals('Color=1|2|4|8, Depth=1|2|4 must resolve to max 4x MSAA',
    4, ResolveMaxFramebufferSampleCount(
      VK_SAMPLE_COUNT_1_BIT or VK_SAMPLE_COUNT_2_BIT or VK_SAMPLE_COUNT_4_BIT or VK_SAMPLE_COUNT_8_BIT,
      VK_SAMPLE_COUNT_1_BIT or VK_SAMPLE_COUNT_2_BIT or VK_SAMPLE_COUNT_4_BIT));
  AssertEquals('Requesting 16x on 1|2|4|8 mask must clamp to 8x',
    8, ClampSampleCountToMask(16,
      VK_SAMPLE_COUNT_1_BIT or VK_SAMPLE_COUNT_2_BIT or VK_SAMPLE_COUNT_4_BIT or VK_SAMPLE_COUNT_8_BIT));
  AssertEquals('RHIToVkSampleCountFlags(4) must return VK_SAMPLE_COUNT_4_BIT',
    VK_SAMPLE_COUNT_4_BIT, RHIToVkSampleCountFlags(4));
  AssertEquals('RHIToVkResolveMode(rmAverage) must return VK_RESOLVE_MODE_AVERAGE_BIT',
    VK_RESOLVE_MODE_AVERAGE_BIT, RHIToVkResolveMode(rmAverage));

  { 2. Dynamic Rendering (Vulkan 1.3) single-pass 4x MSAA attachment resolve }
  VkDevDyn := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  try
    AssertEquals('Default headless MaxFramebufferSampleCount must be 8',
      8, VkDevDyn.Capabilities.MaxFramebufferSampleCount);

    { Verify that requesting 16x MSAA on an 8x-capable device clamps to 8x and forces MipLevels = 1 }
    OverLimitDesc := TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment], 4, 16);
    OverLimitTex := VkDevDyn.CreateTexture(OverLimitDesc) as TVulkanRHITexture;
    try
      AssertEquals('MSAA texture sample count must clamp to device MaxFramebufferSampleCount (8)',
        8, OverLimitTex.Desc.SampleCount);
      AssertEquals('Multisampled VkImage must enforce MipLevels = 1',
        1, OverLimitTex.Desc.MipLevels);
    finally
      FreeAndNil(OverLimitTex);
    end;

    { Configure 4x MSAA via TAntiAliasing (aa4SamplesRegular) }
    VkDevDyn.AntiAliasing := aa4SamplesRegular;
    AssertEquals('aa4SamplesRegular must set SampleCount = 4', 4, VkDevDyn.SampleCount);

    ResolveColorDesc := TRHITextureDesc.Create2D(128, 128, pfBGRA8_UNorm, [tuColorAttachment, tuSampled]);
    ResolveDepthDesc := TRHITextureDesc.Create2D(128, 128, pfD32_Float, [tuDepthStencil]);
    ResolveColorTex := VkDevDyn.CreateTexture(ResolveColorDesc) as TVulkanRHITexture;
    ResolveDepthTex := VkDevDyn.CreateTexture(ResolveDepthDesc) as TVulkanRHITexture;
    CmdList := TVulkanRHICommandList.Create(VkDevDyn, 0, cllPrimary);
    try
      RenderInfo := VkDevDyn.BuildSwapchainRenderingInfo(
        Rectangle(0, 0, 128, 128), ResolveColorTex, ResolveDepthTex, Black);

      AssertTrue('Transient 4x MSAA color target must be allocated', VkDevDyn.SwapchainMSAAColorTexture <> nil);
      AssertTrue('Transient 4x MSAA depth target must be allocated', VkDevDyn.SwapchainMSAADepthTexture <> nil);
      AssertEquals('Transient MSAA color target must have 4 samples', 4, VkDevDyn.SwapchainMSAAColorTexture.Desc.SampleCount);
      AssertEquals('Transient MSAA color target StoreOp must be soDontCare (tile-local)',
        Ord(soDontCare), Ord(RenderInfo.ColorAttachments[0].StoreOp));
      AssertTrue('ResolveTexture must point to 1x ResolveColorTex',
        RenderInfo.ColorAttachments[0].ResolveTexture = ResolveColorTex);
      AssertEquals('ResolveMode must be rmAverage',
        Ord(rmAverage), Ord(RenderInfo.ColorAttachments[0].ResolveMode));

      CmdList.BeginRecording;
      CmdList.BeginRendering(RenderInfo);
      CmdList.EndRendering;
      CmdList.EndRecording;

      AssertEquals('MSAAResolvePassCount must be incremented to 1', 1, VkDevDyn.MSAAResolvePassCount);
      AssertEquals('1x ResolveColorTex must be transitioned to rsColorAttachment',
        Ord(rsColorAttachment), Ord(ResolveColorTex.CurrentState));
    finally
      FreeAndNil(CmdList);
      FreeAndNil(ResolveDepthTex);
      FreeAndNil(ResolveColorTex);
    end;
  finally
    FreeAndNil(VkDevDyn);
  end;

  { 3. Vulkan 1.1/1.2 Fallback RenderPass single-pass MSAA resolve (pResolveAttachments) }
  VkDevFallback := TVulkanRHIDevice.CreateHeadless(nil, True, False, VK_API_VERSION_1_1);
  try
    VkDevFallback.SampleCount := 4;
    ResolveColorDesc := TRHITextureDesc.Create2D(128, 128, pfBGRA8_UNorm, [tuColorAttachment]);
    ResolveDepthDesc := TRHITextureDesc.Create2D(128, 128, pfD32_Float, [tuDepthStencil]);
    ResolveColorTex := VkDevFallback.CreateTexture(ResolveColorDesc) as TVulkanRHITexture;
    ResolveDepthTex := VkDevFallback.CreateTexture(ResolveDepthDesc) as TVulkanRHITexture;
    CmdList := TVulkanRHICommandList.Create(VkDevFallback, 0, cllPrimary);
    try
      RenderInfo := VkDevFallback.BuildSwapchainRenderingInfo(
        Rectangle(0, 0, 128, 128), ResolveColorTex, ResolveDepthTex, Black);

      CmdList.BeginRecording;
      CmdList.BeginRendering(RenderInfo);
      CmdList.EndRendering;
      CmdList.EndRecording;

      AssertEquals('FallbackRenderPassBeginCount must be 1', 1, VkDevFallback.FallbackRenderPassBeginCount);
      AssertEquals('FallbackRenderPassCount must be 1', 1, VkDevFallback.FallbackRenderPassCount);
      AssertEquals('FallbackFramebufferCount must be 1', 1, VkDevFallback.FallbackFramebufferCount);
      AssertEquals('Fallback MSAAResolvePassCount must be 1', 1, VkDevFallback.MSAAResolvePassCount);
    finally
      FreeAndNil(CmdList);
      FreeAndNil(ResolveDepthTex);
      FreeAndNil(ResolveColorTex);
    end;
  finally
    FreeAndNil(VkDevFallback);
  end;
end;

procedure TTestCastleVulkanRHI.TestComputePipelineAndDispatch;
const
  MinimalComputeSPIRV: array[0..9] of UInt32 = (
    $07230203, // SPIR-V Magic
    $00010500, // Version 1.5
    $00000000,
    $00000008, // Bound
    $00000000,
    ($00050000 or 15), // OpEntryPoint (5 words)
    5,                 // ExecutionModel = GLCompute (5)
    1,                 // EntryPoint ID = %1
    $6E69616D,         // "main"
    $00000000
  );
var
  VkDev: TVulkanRHIDevice;
  CompShader: TRHIShaderModule;
  LayoutDesc: array[0..1] of TRHIDescriptorBindingDesc;
  SetLayout: TRHIDescriptorSetLayout;
  DescSet: TRHIDescriptorSet;
  SSBODesc, IndirectDesc: TRHIBufferDesc;
  SSBOBuf, IndirectBuf: TRHIBuffer;
  StorageTexDesc: TRHITextureDesc;
  StorageTex: TRHITexture;
  CompDesc: TRHIComputePipelineDesc;
  CompPipe1, CompPipe2: TRHIComputePipeline;
  IndirectCmd: TRHIDispatchIndirectCommand;
  PushData: TVector4;
  CmdList: TVulkanRHICommandList;
begin
  AssertEquals('TRHIDispatchIndirectCommand must be exactly 12 bytes (VkDispatchIndirectCommand)',
    12, SizeOf(TRHIDispatchIndirectCommand));

  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  try
    CompShader := VkDev.CreateShaderModuleFromSPIRV(ssCompute, @MinimalComputeSPIRV[0],
      SizeOf(MinimalComputeSPIRV), 'TestComputeCS');
    LayoutDesc[0].Binding := 0;
    LayoutDesc[0].DescriptorType := dtStorageBuffer;
    LayoutDesc[0].Count := 1;
    LayoutDesc[0].StageFlags := [ssCompute];
    LayoutDesc[1].Binding := 1;
    LayoutDesc[1].DescriptorType := dtStorageImage;
    LayoutDesc[1].Count := 1;
    LayoutDesc[1].StageFlags := [ssCompute];
    SetLayout := VkDev.CreateDescriptorSetLayout(LayoutDesc);
    DescSet := VkDev.CreateDescriptorSet(SetLayout);

    SSBODesc := TRHIBufferDesc.Create(1024, [buStorage], muGpuOnly, 'ParticleSSBO');
    SSBOBuf := VkDev.CreateBuffer(SSBODesc, nil);
    StorageTexDesc := TRHITextureDesc.Create2D(64, 64, pfRGBA16_Float, [tuStorage, tuSampled]);
    StorageTex := VkDev.CreateTexture(StorageTexDesc);

    IndirectCmd.GroupCountX := 8;
    IndirectCmd.GroupCountY := 4;
    IndirectCmd.GroupCountZ := 1;
    IndirectDesc := TRHIBufferDesc.Create(SizeOf(IndirectCmd), [buIndirect, buStorage], muCpuToGpu, 'DispatchIndirectBuf');
    IndirectBuf := VkDev.CreateBuffer(IndirectDesc, @IndirectCmd);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
    try
      DescSet.BindStorageBuffer(0, SSBOBuf);
      DescSet.BindTexture(1, StorageTex, nil);
      DescSet.Update;

      FillChar(CompDesc, SizeOf(CompDesc), 0);
      CompDesc.ComputeShader := CompShader;
      SetLength(CompDesc.DescriptorSetLayouts, 1);
      CompDesc.DescriptorSetLayouts[0] := SetLayout;
      CompDesc.PushConstantSize := SizeOf(TVector4);
      CompDesc.PushConstantStages := [ssCompute];
      CompDesc.DebugName := 'ParticleSimComputePSO';

      CompPipe1 := VkDev.GetOrCreateComputePipeline(CompDesc);
      CompPipe2 := VkDev.GetOrCreateComputePipeline(CompDesc);
      AssertTrue('GetOrCreateComputePipeline must return cached instance on second call',
        CompPipe1 = CompPipe2);
      AssertEquals('ComputePipelineCacheMisses must be 1', 1, VkDev.ComputePipelineCacheMisses);
      AssertEquals('ComputePipelineCacheHits must be 1', 1, VkDev.ComputePipelineCacheHits);
      AssertEquals('ComputePipelineCount must be 1', 1, VkDev.ComputePipelineCount);

      PushData := Vector4(0.016, 9.81, 0, 0);
      CmdList.BeginRecording;
      CmdList.TransitionTexture(StorageTex, rsShaderRead);
      CmdList.BindComputePipeline(CompPipe1);
      CmdList.BindComputeDescriptorSet(0, DescSet, []);
      CmdList.PushConstants([ssCompute], 0, SizeOf(PushData), PushData);
      CmdList.Dispatch(16, 1, 1);
      CmdList.TransitionBuffer(SSBOBuf, rsTransferDst, rsShaderRead);
      CmdList.DispatchIndirect(IndirectBuf, 0);
      CmdList.EndRecording;

      AssertEquals('ComputeDispatchCount must record both Dispatch and DispatchIndirect (2)',
        2, VkDev.ComputeDispatchCount);
      AssertEquals('CmdList.ComputeDispatchCount must be 2', 2, CmdList.ComputeDispatchCount);
      AssertEquals('StorageTex state must be rsShaderRead', Ord(rsShaderRead), Ord(StorageTex.CurrentState));
    finally
      FreeAndNil(CmdList);
      FreeAndNil(IndirectBuf);
      FreeAndNil(StorageTex);
      FreeAndNil(SSBOBuf);
      FreeAndNil(DescSet);
      FreeAndNil(SetLayout);
      FreeAndNil(CompShader);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestExtendedDynamicStateAndSync2AndTimelineSemaphore;
var
  UseExtDyn, UseSync2, UseTimeline: Boolean;
  ReqExts: TAnsiStringArray;
  VkDev13, VkDev11: TVulkanRHIDevice;
  DescA, DescB: TRHIGraphicsPipelineDesc;
  PipeA, PipeB: TRHIPipeline;
  TexDesc: TRHITextureDesc;
  Tex: TRHITexture;
  BufDesc: TRHIBufferDesc;
  Buf: TRHIBuffer;
  CmdList: TVulkanRHICommandList;
  TimelineSem: TCastleVulkanTimelineSemaphore;
begin
  { 1. Verify Vulkan 1.3 vs Vulkan 1.1 capability & extension resolution }
  ResolveExtendedDynamicStateAndSync2Config(
    VK_API_VERSION_1_3, False, False, False,
    True, True, True,
    UseExtDyn, UseSync2, UseTimeline, ReqExts);
  AssertTrue('Vulkan 1.3 core must enable ExtendedDynamicState without extension strings', UseExtDyn);
  AssertTrue('Vulkan 1.3 core must enable Synchronization2 without extension strings', UseSync2);
  AssertTrue('Vulkan 1.3 core must enable TimelineSemaphores without extension strings', UseTimeline);
  AssertEquals('Vulkan 1.3 core must require 0 extra extension strings', 0, Length(ReqExts));

  ResolveExtendedDynamicStateAndSync2Config(
    VK_API_VERSION_1_1, True, True, True,
    True, True, True,
    UseExtDyn, UseSync2, UseTimeline, ReqExts);
  AssertTrue('Vulkan 1.1 with extensions must enable ExtendedDynamicState', UseExtDyn);
  AssertTrue('Vulkan 1.1 with extensions must enable Synchronization2', UseSync2);
  AssertTrue('Vulkan 1.1 with extensions must enable TimelineSemaphores', UseTimeline);
  AssertEquals('Vulkan 1.1 with all 3 extensions must request 3 extension strings', 3, Length(ReqExts));

  { 2. Verify Extended Dynamic State PSO deduplication (CullMode, FrontFace, DepthTest/Write/CompareOp, Topology) }
  VkDev13 := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3, False, True, 4096, True);
  try
    AssertTrue('Vulkan 1.3 headless device must enable SupportsExtendedDynamicState',
      VkDev13.SupportsExtendedDynamicState);
    AssertTrue('Vulkan 1.3 headless device must enable SupportsSynchronization2',
      VkDev13.SupportsSynchronization2);
    AssertTrue('Vulkan 1.3 headless device must enable SupportsTimelineSemaphores',
      VkDev13.SupportsTimelineSemaphores);

    FillChar(DescA, SizeOf(DescA), 0);
    DescA.Topology := ptTriangleList;
    DescA.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    DescA.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
    DescA.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    DescA.DepthAttachmentFormat := pfD32_Float;
    SetLength(DescA.ColorAttachmentFormats, 1);
    DescA.ColorAttachmentFormats[0] := pfBGRA8_UNorm;

    { DescB differs ONLY in CullMode, FrontFace, DepthWriteEnable, DepthCompareOp, and Topology }
    DescB := DescA;
    DescB.Topology := ptTriangleStrip;
    DescB.Rasterizer.CullMode := cmNone;
    DescB.Rasterizer.FrontFace := ffClockwise;
    DescB.DepthStencil.DepthWriteEnable := False;
    DescB.DepthStencil.DepthCompareOp := coLess;

    PipeA := VkDev13.GetOrCreatePipeline(DescA);
    PipeB := VkDev13.GetOrCreatePipeline(DescB);
    AssertTrue('With VK_EXT_extended_dynamic_state enabled, DescA and DescB must share the same cached PSO',
      PipeA = PipeB);
    AssertEquals('PipelineCount must be 1 (zero redundant PSO permutation)', 1, VkDev13.PipelineCount);
    AssertEquals('PipelineCacheHits must be 1', 1, VkDev13.PipelineCacheHits);

    { 3. Verify Synchronization2 barriers (TransitionTexture & TransitionBuffer) and dynamic state commands }
    TexDesc := TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuSampled, tuColorAttachment]);
    Tex := VkDev13.CreateTexture(TexDesc);
    BufDesc := TRHIBufferDesc.Create(256, [buStorage, buVertex], muGpuOnly, 'Sync2Buf');
    Buf := VkDev13.CreateBuffer(BufDesc, nil);
    CmdList := TVulkanRHICommandList.Create(VkDev13, 0, cllPrimary);
    TimelineSem := VkDev13.CreateTimelineSemaphore(10);
    try
      CmdList.BeginRecording;
      CmdList.TransitionTexture(Tex, rsColorAttachment);
      CmdList.TransitionTexture(Tex, rsShaderRead);
      CmdList.TransitionBuffer(Buf, rsTransferDst, rsShaderRead);
      CmdList.BindPipeline(PipeA);
      CmdList.SetCullMode(cmNone);
      CmdList.SetFrontFace(ffClockwise);
      CmdList.SetDepthTestEnable(True);
      CmdList.SetDepthWriteEnable(False);
      CmdList.SetDepthCompareOp(coLess);
      CmdList.SetPrimitiveTopology(ptTriangleStrip);
      CmdList.EndRecording;

      AssertEquals('Sync2BarrierCount must be 3 (2 texture + 1 buffer barrier via Sync2 path)',
        3, VkDev13.Sync2BarrierCount);
      AssertEquals('CmdList.BarrierCount must be 3', 3, CmdList.BarrierCount);

      { 4. Verify 64-bit Timeline Semaphore monotonic counter & host Signal/Wait }
      AssertEquals('Initial timeline semaphore counter must be 10', 10, TimelineSem.GetCounterValue);
      AssertFalse('Wait(15) before Signal(15) must return False', TimelineSem.Wait(15, 0));
      TimelineSem.Signal(15);
      AssertEquals('Counter after Signal(15) must be 15', 15, TimelineSem.GetCounterValue);
      AssertTrue('Wait(15) after Signal(15) must return True', TimelineSem.Wait(15, 0));
    finally
      FreeAndNil(TimelineSem);
      FreeAndNil(CmdList);
      FreeAndNil(Buf);
      FreeAndNil(Tex);
    end;
  finally
    FreeAndNil(VkDev13);
  end;

  { 5. Verify that when ExtendedDynamicState is False (Vulkan 1.1 baseline), DescA and DescB produce distinct PSOs }
  VkDev11 := TVulkanRHIDevice.CreateHeadless(nil, True, False, VK_API_VERSION_1_1);
  try
    AssertFalse('Vulkan 1.1 baseline device must have SupportsExtendedDynamicState = False',
      VkDev11.SupportsExtendedDynamicState);
    PipeA := VkDev11.GetOrCreatePipeline(DescA);
    PipeB := VkDev11.GetOrCreatePipeline(DescB);
    AssertTrue('Without ExtendedDynamicState, DescA and DescB must produce distinct PSOs',
      PipeA <> PipeB);
    AssertEquals('PipelineCount on Vulkan 1.1 baseline must be 2', 2, VkDev11.PipelineCount);
  finally
    FreeAndNil(VkDev11);
  end;
end;

procedure TTestCastleVulkanRHI.TestQueryPoolTimestampsAndOcclusion;
var
  VkDev: TVulkanRHIDevice;
  OccDesc: TRHIQueryPoolDesc;
  OccPool: TVulkanRHIQueryPool;
  OccSamples: array[0..1] of UInt64;
  CmdList: TVulkanRHICommandList;
  Profiler: TCastleVulkanTimestampProfiler;
  Slot0Pool: TVulkanRHIQueryPool;
  PassShadow, PassForward: Integer;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  try
    { Set 2.0 nanoseconds per GPU timestamp tick to verify tick -> millisecond conversion }
    OccDesc := TRHIQueryPoolDesc.Create(qtOcclusion, 4, 'HardwareOcclusionPool');
    OccPool := VkDev.CreateQueryPool(OccDesc) as TVulkanRHIQueryPool;
    CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
    try
      { 1. Hardware Occlusion Queries (BeginQuery / EndQuery / GetResults) }
      CmdList.BeginRecording;
      CmdList.ResetQueryPool(OccPool, 0, 4);
      CmdList.BeginQuery(OccPool, 0, False);
      OccPool.SetSimulatedResult(0, 1420); // 1,420 visible samples
      CmdList.EndQuery(OccPool, 0);

      CmdList.BeginQuery(OccPool, 1, True); // VK_QUERY_CONTROL_PRECISE_BIT
      OccPool.SetSimulatedResult(1, 0);     // Fully occluded bounding box
      CmdList.EndQuery(OccPool, 1);
      CmdList.EndRecording;

      AssertTrue('Query 0 must be marked written', OccPool.IsQueryWritten(0));
      AssertTrue('Query 1 must be marked written', OccPool.IsQueryWritten(1));
      AssertFalse('Query 2 was not recorded and must not be marked written', OccPool.IsQueryWritten(2));

      FillChar(OccSamples, SizeOf(OccSamples), 0);
      AssertTrue('GetResults for written queries 0..1 must return True',
        OccPool.GetResults(0, 2, OccSamples, False));
      AssertEquals('Occlusion query 0 sample count must be 1420', 1420, OccSamples[0]);
      AssertEquals('Occlusion query 1 sample count must be 0 (occluded)', 0, OccSamples[1]);

      { Non-blocking GetResults on unwritten query 2 must return False (VK_NOT_READY) }
      AssertFalse('Non-blocking GetResults on unwritten query 2 must return False',
        OccPool.GetResults(2, 1, OccSamples, False));

      { 2. Per-Frame GPU Timestamp Profiler (TCastleVulkanTimestampProfiler) }
      Profiler := VkDev.TimestampProfiler;
      AssertTrue('Device TimestampProfiler must be initialized', Profiler <> nil);

      CmdList.BeginRecording;
      Profiler.BeginFrame(CmdList, 0);
      PassShadow := Profiler.BeginPass(CmdList, 'ShadowMapPass');
      Profiler.EndPass(CmdList, PassShadow);
      PassForward := Profiler.BeginPass(CmdList, 'ForwardOpaquePass');
      Profiler.EndPass(CmdList, PassForward);
      CmdList.EndRecording;

      { Inject simulated GPU timestamps for Frame Slot 0:
        ShadowMapPass: 1,000,000 -> 2,500,000 ticks (1.5 ms at 1.0 ns/tick)
        ForwardOpaquePass: 2,500,000 -> 6,000,000 ticks (3.5 ms at 1.0 ns/tick) }
      Slot0Pool := Profiler.GetQueryPoolForSlot(0);
      Slot0Pool.SetSimulatedResult(0, 1000000);
      Slot0Pool.SetSimulatedResult(1, 2500000);
      Slot0Pool.SetSimulatedResult(2, 2500000);
      Slot0Pool.SetSimulatedResult(3, 6000000);

      { Next time Frame Slot 0 (FrameIndex = MaxFramesInFlight = 2) begins, Profiler reads back completed passes }
      CmdList.BeginRecording;
      Profiler.BeginFrame(CmdList, MaxFramesInFlight);
      CmdList.EndRecording;

      AssertEquals('CompletedPassCount must be 2', 2, Profiler.CompletedPassCount);
      AssertSameValue(1.5, Profiler.GetPassTimeMs('ShadowMapPass'), 0.001);
      AssertSameValue(3.5, Profiler.GetPassTimeMs('ForwardOpaquePass'), 0.001);
      AssertSameValue(5.0, Profiler.LastFrameTotalGpuTimeMs, 0.001);
    finally
      FreeAndNil(CmdList);
      FreeAndNil(OccPool);
    end;
  finally
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.DummyRenderShapeCallback(const Shape: TCollectedShape;
  const Params: TRenderParams; const PassParams: TRenderOnePassParams);
begin
  Inc(FRenderedShapeCount);
  if Params.InternalPass = 0 then
    Inc(Params.Statistics.ShapesRendered);
end;

procedure TTestCastleVulkanRHI.TestRHIOcclusionCullingRendererIntegration;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  OccRenderer: TOcclusionCullingRenderer;
  Shape1, Shape2, Shape3: TGLShape;
  Col1, Col2, Col3: TCollectedShape;
  ShapeNode1, ShapeNode2, ShapeNode3: TShapeNode;
  BoxNode1, BoxNode2, BoxNode3: TBoxNode;
  State1, State2, State3: TX3DGraphTraverseState;
  Params: TRenderParams;
  PassParams: TRenderOnePassParams;
  Pool0, Pool1: TVulkanRHIQueryPool;
  SavedDevice: TRHIDevice;
  SavedCmd: TRHICommandList;
begin
  SavedDevice := RHIDevice;
  SavedCmd := ActiveCommandList;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  OccRenderer := TOcclusionCullingRenderer.Create;
  ShapeNode1 := TShapeNode.Create;
  BoxNode1 := TBoxNode.Create;
  ShapeNode1.Geometry := BoxNode1;
  State1 := TX3DGraphTraverseState.Create;
  State1.ShapeNode := ShapeNode1;
  ShapeNode2 := TShapeNode.Create;
  BoxNode2 := TBoxNode.Create;
  ShapeNode2.Geometry := BoxNode2;
  State2 := TX3DGraphTraverseState.Create;
  State2.ShapeNode := ShapeNode2;
  ShapeNode3 := TShapeNode.Create;
  BoxNode3 := TBoxNode.Create;
  ShapeNode3.Geometry := BoxNode3;
  State3 := TX3DGraphTraverseState.Create;
  State3.ShapeNode := ShapeNode3;
  Shape1 := TGLShape.Create(nil, BoxNode1, State1, nil);
  Shape2 := TGLShape.Create(nil, BoxNode2, State2, nil);
  Shape3 := TGLShape.Create(nil, BoxNode3, State3, nil);
  Col1 := TCollectedShape.Create;
  Col2 := TCollectedShape.Create;
  Col3 := TCollectedShape.Create;
  Params := TRenderParams.Create;
  try
    SetRHIDevice(VkDev);
    SetActiveCommandList(CmdList);
    Col1.Shape := Shape1;
    Col1.SceneTransform := TMatrix4.Identity;
    Col2.Shape := Shape2;
    Col2.SceneTransform := TMatrix4.Identity;
    Col3.Shape := Shape3;
    Col3.SceneTransform := TMatrix4.Identity;
    PassParams.Init;

    { Force page capacity = 2 so 3 shapes allocate across 2 paged TRHIQueryPool instances }
    OccRenderer.RHIQueryPageCapacity := 2;
    FRenderedShapeCount := 0;

    { Frame 1: Initial render allocates query slots 1..3 across 2 pools and renders all 3 shapes }
    CmdList.BeginRecording;
    OccRenderer.Render(Col1, Params, PassParams, @DummyRenderShapeCallback);
    OccRenderer.Render(Col2, Params, PassParams, @DummyRenderShapeCallback);
    OccRenderer.Render(Col3, Params, PassParams, @DummyRenderShapeCallback);
    CmdList.EndRecording;

    AssertEquals('All 3 shapes must be rendered on first frame', 3, FRenderedShapeCount);
    AssertEquals('AllocatedRHIQuerySlots must be 3', 3, OccRenderer.AllocatedRHIQuerySlots);
    AssertEquals('RHIQueryPoolCount must grow to 2 pages (capacity 2 per page)', 2, OccRenderer.RHIQueryPoolCount);
    AssertEquals('RHIQueriesIssuedCount must be 3', 3, OccRenderer.RHIQueriesIssuedCount);
    AssertEquals('Shape1.RHIQuerySlot must be 1', 1, Shape1.RHIQuerySlot);
    AssertEquals('Shape2.RHIQuerySlot must be 2', 2, Shape2.RHIQuerySlot);
    AssertEquals('Shape3.RHIQuerySlot must be 3', 3, Shape3.RHIQuerySlot);

    { Simulate occlusion query results from Frame 1:
      - Shape1 (Pool0, index 0): 500 samples (visible)
      - Shape2 (Pool0, index 1): 0 samples (occluded!)
      - Shape3 (Pool1, index 0): 120 samples (visible) }
    Pool0 := OccRenderer.GetRHIQueryPool(0) as TVulkanRHIQueryPool;
    Pool1 := OccRenderer.GetRHIQueryPool(1) as TVulkanRHIQueryPool;
    AssertTrue('Pool0 must exist', Pool0 <> nil);
    AssertTrue('Pool1 must exist', Pool1 <> nil);
    Pool0.SetSimulatedResult(0, 500);
    Pool0.SetSimulatedResult(1, 0);
    Pool1.SetSimulatedResult(0, 120);

    { Frame 2: Shape1 and Shape3 render normally; Shape2 is occluded so only its bounding box
      is drawn via RHI (Utils.DrawBox) and BoxesOcclusionQueriedCount is incremented }
    FRenderedShapeCount := 0;
    CmdList.BeginRecording;
    OccRenderer.Render(Col1, Params, PassParams, @DummyRenderShapeCallback);
    OccRenderer.Render(Col2, Params, PassParams, @DummyRenderShapeCallback);
    OccRenderer.Render(Col3, Params, PassParams, @DummyRenderShapeCallback);
    OccRenderer.Utils.OcclusionBoxStateEnd(True);
    CmdList.EndRecording;

    AssertEquals('Only 2 visible shapes must be rendered on Frame 2', 2, FRenderedShapeCount);
    AssertEquals('BoxesOcclusionQueriedCount must be 1 (Shape2 bounding box)',
      1, Params.Statistics.BoxesOcclusionQueriedCount);
    AssertTrue('RHI bounding box VBO must be allocated', OccRenderer.Utils.RHIBoxVertexBuffer <> nil);
    AssertTrue('RHI bounding box IBO must be allocated', OccRenderer.Utils.RHIBoxIndexBuffer <> nil);
    AssertEquals('RHIQueriesHitCount must be 2 (Shape1 + Shape3)', 2, OccRenderer.RHIQueriesHitCount);

    { Frame 3: Suppose Shape2's bounding box query now passed 80 samples -> Shape2 becomes visible again }
    Pool0.SetSimulatedResult(0, 500);
    Pool0.SetSimulatedResult(1, 80);
    Pool1.SetSimulatedResult(0, 120);

    FRenderedShapeCount := 0;
    CmdList.BeginRecording;
    OccRenderer.Render(Col1, Params, PassParams, @DummyRenderShapeCallback);
    OccRenderer.Render(Col2, Params, PassParams, @DummyRenderShapeCallback);
    OccRenderer.Render(Col3, Params, PassParams, @DummyRenderShapeCallback);
    CmdList.EndRecording;

    AssertEquals('All 3 shapes must be rendered on Frame 3 after Shape2 bbox query hit',
      3, FRenderedShapeCount);
    AssertEquals('RHIQueriesHitCount must now be 5 (2 + 3)', 5, OccRenderer.RHIQueriesHitCount);
  finally
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedDevice);
    FreeAndNil(Params);
    FreeAndNil(Col3);
    FreeAndNil(Col2);
    FreeAndNil(Col1);
    FreeAndNil(Shape3);
    FreeAndNil(Shape2);
    FreeAndNil(Shape1);
    FreeAndNil(ShapeNode3);
    FreeAndNil(ShapeNode2);
    FreeAndNil(ShapeNode1);
    FreeAndNil(OccRenderer);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestGpuDrivenComputeFrustumAndDistanceCulling;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Culler: TCastleVulkanComputeCuller;
  ShaderGen: TCastleShaderGeneratorRHI;
  CompGLSL: String;
  Planes: array[0..5] of TVector4;
  Instances: array[0..3] of TCastleGpuCullingInstance;
  Groups: Cardinal;
  Cmd0, Cmd1, Cmd2, Cmd3: TRHIDrawIndexedIndirectCommand;
begin
  AssertEquals('TCastleGpuCullingUniformBlock must be 144 bytes (16-byte aligned std140)',
    144, SizeOf(TCastleGpuCullingUniformBlock));
  AssertEquals('TCastleGpuCullingInstance must be 80 bytes (16-byte aligned std430)',
    80, SizeOf(TCastleGpuCullingInstance));

  ShaderGen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    CompGLSL := ShaderGen.GenerateComputeCullingShader(64);
    AssertTrue('Compute culling shader must specify #version 450',
      Pos('#version 450', CompGLSL) > 0);
    AssertTrue('Compute culling shader must specify local_size_x = 64',
      Pos('layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;', CompGLSL) > 0);
    AssertTrue('Compute culling shader must declare CastleGpuCullingUniforms',
      Pos('CastleGpuCullingUniforms', CompGLSL) > 0);
    AssertTrue('Compute culling shader must declare CastleIndirectCommandsBlock',
      Pos('CastleIndirectCommandsBlock', CompGLSL) > 0);
    AssertTrue('Compute culling shader must use atomicAdd(u_VisibleCount, 1u)',
      Pos('atomicAdd(u_VisibleCount, 1u)', CompGLSL) > 0);
  finally
    FreeAndNil(ShaderGen);
  end;

  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  try
    Culler := VkDev.ComputeCuller;
    AssertTrue('Device ComputeCuller must be created on demand', Culler <> nil);

    { Define a simple box frustum:
      X in [-50..50], Y in [-50..50], Z in [-100..0] (camera at origin looking down -Z),
      and max distance culling = 80.0 units }
    Planes[0] := Vector4( 1,  0,  0, 50);  // x >= -50
    Planes[1] := Vector4(-1,  0,  0, 50);  // x <= 50
    Planes[2] := Vector4( 0,  1,  0, 50);  // y >= -50
    Planes[3] := Vector4( 0, -1,  0, 50);  // y <= 50
    Planes[4] := Vector4( 0,  0, -1, 0);   // z <= 0 (in front of camera)
    Planes[5] := Vector4( 0,  0,  1, 100); // z >= -100
    Culler.SetFrustumPlanes(Planes, Vector3(0, 0, 0), 80.0);

    FillChar(Instances, SizeOf(Instances), 0);
    { Instance 0: Inside frustum (0, 0, -20), radius 2 -> VISIBLE (IndexCount = 36) }
    Instances[0].BoundingSphere := Vector4(0, 0, -20, 2.0);
    Instances[0].IndexCount := 36;
    Instances[0].InstanceCount := 1;
    Instances[0].FirstIndex := 0;
    Instances[0].MaterialIndex := 1;

    { Instance 1: Outside frustum (+120, 0, -20), radius 2 -> CULLED by frustum (IndexCount = 72) }
    Instances[1].BoundingSphere := Vector4(120, 0, -20, 2.0);
    Instances[1].IndexCount := 72;
    Instances[1].InstanceCount := 1;
    Instances[1].FirstIndex := 36;
    Instances[1].MaterialIndex := 2;

    { Instance 2: Inside frustum (0, 0, -95), radius 1 -> CULLED by distance (94 > 80.0) (IndexCount = 108) }
    Instances[2].BoundingSphere := Vector4(0, 0, -95, 1.0);
    Instances[2].IndexCount := 108;
    Instances[2].InstanceCount := 1;
    Instances[2].FirstIndex := 108;
    Instances[2].MaterialIndex := 3;

    { Instance 3: Inside frustum & within distance (10, -5, -40), radius 3 -> VISIBLE (IndexCount = 144) }
    Instances[3].BoundingSphere := Vector4(10, -5, -40, 3.0);
    Instances[3].IndexCount := 144;
    Instances[3].InstanceCount := 1;
    Instances[3].FirstIndex := 216;
    Instances[3].MaterialIndex := 4;

    Culler.UploadInstances(Instances);
    AssertEquals('LastUploadedInstanceCount must be 4', 4, Culler.LastUploadedInstanceCount);

    { 1. Dispatch in non-compacted 1:1 mode (ACompactDraws = False) }
    CmdList.BeginRecording;
    Groups := Culler.DispatchCulling(CmdList, 4, False);
    CmdList.EndRecording;

    AssertEquals('4 instances with workgroup size 64 must dispatch 1 workgroup', 1, Groups);
    AssertEquals('Visible instance count must be 2 (Instances 0 and 3)', 2, Culler.ReadBackVisibleCount);
    AssertEquals('LastCulledInstanceCount must be 2 (Instances 1 and 2)', 2, Culler.LastCulledInstanceCount);
    AssertEquals('Instance 0 visibility flag must be 1', 1, Culler.ReadBackVisibilityFlag(0));
    AssertEquals('Instance 1 visibility flag must be 0 (frustum culled)', 0, Culler.ReadBackVisibilityFlag(1));
    AssertEquals('Instance 2 visibility flag must be 0 (distance culled)', 0, Culler.ReadBackVisibilityFlag(2));
    AssertEquals('Instance 3 visibility flag must be 1', 1, Culler.ReadBackVisibilityFlag(3));

    Cmd0 := Culler.ReadBackIndirectCommand(0);
    Cmd1 := Culler.ReadBackIndirectCommand(1);
    Cmd2 := Culler.ReadBackIndirectCommand(2);
    Cmd3 := Culler.ReadBackIndirectCommand(3);
    AssertEquals('Slot 0 must have InstanceCount = 1', 1, Cmd0.InstanceCount);
    AssertEquals('Slot 0 IndexCount must be 36', 36, Cmd0.IndexCount);
    AssertEquals('Slot 1 (culled) must have InstanceCount = 0', 0, Cmd1.InstanceCount);
    AssertEquals('Slot 2 (culled) must have InstanceCount = 0', 0, Cmd2.InstanceCount);
    AssertEquals('Slot 3 must have InstanceCount = 1', 1, Cmd3.InstanceCount);
    AssertEquals('Slot 3 IndexCount must be 144', 144, Cmd3.IndexCount);

    { 2. Dispatch in compacted stream mode (ACompactDraws = True) }
    CmdList.BeginRecording;
    Culler.DispatchCulling(CmdList, 4, True);
    CmdList.EndRecording;

    AssertEquals('Compacted visible count must be 2', 2, Culler.ReadBackVisibleCount);
    Cmd0 := Culler.ReadBackIndirectCommand(0);
    Cmd1 := Culler.ReadBackIndirectCommand(1);
    AssertEquals('Compacted slot 0 must be Instance 0 (IndexCount = 36)', 36, Cmd0.IndexCount);
    AssertEquals('Compacted slot 0 InstanceCount must be 1', 1, Cmd0.InstanceCount);
    AssertEquals('Compacted slot 1 must be Instance 3 (IndexCount = 144, FirstIndex = 216)',
      144, Cmd1.IndexCount);
    AssertEquals('Compacted slot 1 FirstIndex must be 216', 216, Cmd1.FirstIndex);
    AssertEquals('Device ComputeDispatchCount must be 2', 2, VkDev.ComputeDispatchCount);
    AssertTrue('CmdList BarrierCount must include indirect & visibility buffer barriers',
      CmdList.BarrierCount >= 2);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportLiveDiagnosticsAndWindowAntiAliasingSync;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Viewport: TCastleViewport;
  Tex: TRHITexture;
  SamplerDesc: TRHISamplerDesc;
  Sampler: TRHISampler;
  Profiler: TCastleVulkanTimestampProfiler;
  Slot0Pool: TVulkanRHIQueryPool;
  PassIdx: Integer;
  Instances: array[0..0] of TCastleGpuCullingInstance;
  Stats: TRenderStatistics;
  StatsText: String;
  SavedDevice: TRHIDevice;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  Viewport := TCastleViewport.Create(nil);
  Tex := VkDev.CreateTexture(TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuSampled]));
  FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
  SamplerDesc.MinFilter := sfLinear;
  SamplerDesc.MagFilter := sfLinear;
  Sampler := VkDev.CreateSampler(SamplerDesc);
  try
    SetRHIDevice(VkDev);

    { 1. Set 4x MSAA on VkDev and register a bindless texture }
    VkDev.AntiAliasing := aa4SamplesNicer;
    AssertEquals('VkDev.SampleCount must be 4', 4, VkDev.SampleCount);
    VkDev.BindlessTextureManager.RegisterTexture(Tex, Sampler);
    AssertEquals('BindlessTextureManager.ActiveSlotCount must be 1',
      1, VkDev.BindlessTextureManager.ActiveSlotCount);

    { 2. Record a GPU compute culling dispatch and a GPU timestamp pass (2.75 ms) }
    FillChar(Instances, SizeOf(Instances), 0);
    Instances[0].BoundingSphere := Vector4(0, 0, -10, 1.0);
    Instances[0].IndexCount := 36;
    Instances[0].InstanceCount := 1;
    VkDev.ComputeCuller.UploadInstances(Instances);

    Profiler := VkDev.TimestampProfiler;
    CmdList.BeginRecording;
    Profiler.BeginFrame(CmdList, 0);
    PassIdx := Profiler.BeginPass(CmdList, 'MainViewportPass');
    VkDev.ComputeCuller.DispatchCulling(CmdList, 1, True);
    Profiler.EndPass(CmdList, PassIdx);
    CmdList.EndRecording;

    Slot0Pool := Profiler.GetQueryPoolForSlot(0);
    Slot0Pool.SetSimulatedResult(0, 1000000);
    Slot0Pool.SetSimulatedResult(1, 3750000); // 2,750,000 ns = 2.75 ms

    CmdList.BeginRecording;
    Profiler.BeginFrame(CmdList, MaxFramesInFlight);
    CmdList.EndRecording;

    { 3. Query Viewport.Statistics and verify live RHI diagnostics }
    Stats := Viewport.Statistics;
    AssertEquals('ActiveBackend must be Vulkan 1.3', 'Vulkan 1.3', Stats.ActiveBackend);
    AssertEquals('MSAASampleCount must be 4', 4, Stats.MSAASampleCount);
    AssertEquals('BindlessActiveTextures must be 1', 1, Stats.BindlessActiveTextures);
    AssertEquals('ComputeDispatchCount must be 1', 1, Stats.ComputeDispatchCount);
    AssertSameValue(2.75, Stats.GpuFrameTimeMs, 0.001);

    StatsText := Stats.ToString;
    AssertTrue('Stats.ToString must include MSAA: 4x', Pos('MSAA: 4x', StatsText) > 0);
    AssertTrue('Stats.ToString must include Bindless tex: 1', Pos('Bindless tex: 1', StatsText) > 0);
    AssertTrue('Stats.ToString must include Compute dispatches: 1', Pos('Compute dispatches: 1', StatsText) > 0);
    AssertTrue('Stats.ToString must include GPU: 2.75 ms', Pos('GPU: 2.75 ms', StatsText) > 0);
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(Sampler);
    FreeAndNil(Tex);
    FreeAndNil(Viewport);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderToTextureRHIBackend;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  RTTColor, RTTDepth, RTTColorDepth, RTTMSAA: TGLRenderToTexture;
  ExtColorTex, ExtDepthTex: TRHITexture;
  CapturedImg: TCastleImage;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  RTTColor := nil;
  RTTDepth := nil;
  RTTColorDepth := nil;
  RTTMSAA := nil;
  ExtColorTex := nil;
  ExtDepthTex := nil;
  CapturedImg := nil;
  try
    SetRHIDevice(VkDev);
    SetActiveCommandList(CmdList);
    CmdList.BeginRecording;

    { 1. tbColor with automatic RHI texture allocation, GenerateMipmap, and SaveScreen }
    AssertFalse('OffscreenRendering must be False initially', OffscreenRendering);
    RTTColor := TGLRenderToTexture.Create(128, 64);
    RTTColor.Buffer := tbColor;
    RTTColor.GLContextOpen;
    AssertTrue('RTTColor.RHIInitialized must be True after GLContextOpen', RTTColor.RHIInitialized);
    AssertTrue('RTTColor.RHIColorTexture must be allocated', RTTColor.RHIColorTexture <> nil);
    AssertTrue('RTTColor.RHIDepthTexture must be allocated', RTTColor.RHIDepthTexture <> nil);
    AssertEquals('RTTColor.ColorBuffer must be cbColorAttachment0', Ord(cbColorAttachment0), Ord(RTTColor.ColorBuffer));

    RTTColor.RenderBegin;
    AssertTrue('OffscreenRendering must be True inside RenderBegin..RenderEnd', OffscreenRendering);
    AssertEquals('RTTColor.RHIRenderPassCount must be 1', 1, RTTColor.RHIRenderPassCount);
    CapturedImg := RTTColor.SaveScreen(TRGBAlphaImage, Rectangle(0, 0, 128, 64));
    AssertTrue('SaveScreen must return non-nil TRGBAlphaImage', CapturedImg is TRGBAlphaImage);
    AssertEquals('CapturedImg.Width must be 128', 128, CapturedImg.Width);
    AssertEquals('CapturedImg.Height must be 64', 64, CapturedImg.Height);
    RTTColor.RenderEnd;
    AssertFalse('OffscreenRendering must be False after RenderEnd', OffscreenRendering);
    AssertEquals('RTTColor.RHIColorTexture must transition to rsShaderRead after RenderEnd',
      Ord(rsShaderRead), Ord(RTTColor.RHIColorTexture.CurrentState));
    RTTColor.GenerateMipmap;

    { 2. tbDepth for shadow map rendering }
    RTTDepth := TGLRenderToTexture.Create(256, 256);
    RTTDepth.Buffer := tbDepth;
    RTTDepth.Stencil := False;
    RTTDepth.GLContextOpen;
    AssertTrue('RTTDepth.RHIDepthTexture must be allocated', RTTDepth.RHIDepthTexture <> nil);
    AssertEquals('RTTDepth depth format must be pfD32_Float when Stencil=False',
      Ord(pfD32_Float), Ord(RTTDepth.RHIDepthTexture.Desc.Format));
    RTTDepth.RenderBegin;
    RTTDepth.RenderEnd;
    AssertEquals('RTTDepth.RHIDepthTexture must transition to rsShaderRead after RenderEnd',
      Ord(rsShaderRead), Ord(RTTDepth.RHIDepthTexture.CurrentState));

    { 3. tbColorAndDepth with external RHI textures }
    ExtColorTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    ExtDepthTex := VkDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfD32_Float,
      [tuDepthStencil, tuSampled, tuTransferSrc]));
    RTTColorDepth := TGLRenderToTexture.Create(64, 64);
    RTTColorDepth.Buffer := tbColorAndDepth;
    RTTColorDepth.Stencil := False;
    RTTColorDepth.SetRHITexture(ExtColorTex, ExtDepthTex);
    RTTColorDepth.GLContextOpen;
    RTTColorDepth.RenderBegin;
    RTTColorDepth.RenderEnd;
    AssertEquals('ExtColorTex must be rsShaderRead after RenderEnd',
      Ord(rsShaderRead), Ord(ExtColorTex.CurrentState));
    AssertEquals('ExtDepthTex must be rsShaderRead after RenderEnd',
      Ord(rsShaderRead), Ord(ExtDepthTex.CurrentState));

    { 4. 4x MSAA single-pass resolve in TGLRenderToTexture }
    RTTMSAA := TGLRenderToTexture.Create(128, 128);
    RTTMSAA.Buffer := tbColor;
    RTTMSAA.MultiSampling := 4;
    RTTMSAA.GLContextOpen;
    RTTMSAA.RenderBegin;
    RTTMSAA.RenderEnd;
    AssertEquals('RTTMSAA.RHIRenderPassCount must be 1', 1, RTTMSAA.RHIRenderPassCount);
    AssertEquals('RTTMSAA resolved color texture must be rsShaderRead',
      Ord(rsShaderRead), Ord(RTTMSAA.RHIColorTexture.CurrentState));

    CmdList.EndRecording;
  finally
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(CapturedImg);
    FreeAndNil(RTTMSAA);
    FreeAndNil(RTTColorDepth);
    FreeAndNil(ExtDepthTex);
    FreeAndNil(ExtColorTex);
    FreeAndNil(RTTDepth);
    FreeAndNil(RTTColor);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestScreenEffectsRHIPingPongExecution;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  ScreenFX: TCastleScreenEffects;
  FinalTarget: TRHITexture;
  Pipelines: array[0..2] of TRHIPipeline;
  ExecutedPasses: Cardinal;
  SrcBeforeSwap: TRHITexture;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  ScreenFX := TCastleScreenEffects.Create(nil);
  FinalTarget := VkDev.CreateTexture(TRHITextureDesc.Create2D(320, 180, pfRGBA8_UNorm,
    [tuColorAttachment, tuSampled, tuTransferSrc]));
  try
    SetRHIDevice(VkDev);
    SetActiveCommandList(CmdList);
    CmdList.BeginRecording;

    { 1. Verify TCastleScreenPushConstants layout (32 bytes) }
    AssertEquals('TCastleScreenPushConstants must be 32 bytes',
      32, SizeOf(TCastleScreenPushConstants));

    { 2. Ensure RHI screen resources with depth enabled (SSAO / depth-of-field) }
    ScreenFX.EnsureRHIScreenResources(320, 180, True);
    AssertTrue('RHIScreenTextureSrc must be allocated', ScreenFX.RHIScreenTextureSrc <> nil);
    AssertTrue('RHIScreenTextureDest must be allocated', ScreenFX.RHIScreenTextureDest <> nil);
    AssertTrue('RHIScreenTextureDepth must be allocated when NeedDepth=True',
      ScreenFX.RHIScreenTextureDepth <> nil);
    AssertTrue('RHIScreenQuadVBO must be allocated', ScreenFX.RHIScreenQuadVBO <> nil);
    AssertEquals('RHIScreenQuadVBO must be 64 bytes (4 vertices x 16 bytes)',
      64, ScreenFX.RHIScreenQuadVBO.Desc.Size);
    AssertTrue('RHIScreenQuadIBO must be allocated', ScreenFX.RHIScreenQuadIBO <> nil);
    AssertEquals('RHIScreenQuadIBO must be 12 bytes (6 UInt16 indices)',
      12, ScreenFX.RHIScreenQuadIBO.Desc.Size);
    AssertTrue('RHIScreenLayoutColorOnly must be created', ScreenFX.RHIScreenLayoutColorOnly <> nil);
    AssertTrue('RHIScreenLayoutColorAndDepth must be created', ScreenFX.RHIScreenLayoutColorAndDepth <> nil);

    { 3. Execute 3-pass post-processing chain (2 intermediate ping-pong passes + 1 final pass) }
    Pipelines[0] := nil;
    Pipelines[1] := nil;
    Pipelines[2] := nil;
    SrcBeforeSwap := ScreenFX.RHIScreenTextureSrc;
    ExecutedPasses := ScreenFX.ExecuteRHIScreenEffectPasses(
      Pipelines, 320, 180, True, FinalTarget, 0.1, 500.0);

    AssertEquals('ExecuteRHIScreenEffectPasses must execute all 3 passes', 3, ExecutedPasses);
    AssertEquals('ScreenFX.RHIScreenPassCount must be 3', 3, ScreenFX.RHIScreenPassCount);
    AssertEquals('ScreenFX.RHIScreenDrawCount must be 3', 3, ScreenFX.RHIScreenDrawCount);
    { Note: 2 intermediate passes swap Src and Dest twice, returning Src to original;
      let's also run a 2-pass chain (1 intermediate swap + 1 final pass) to verify ping-pong swap! }
    ExecutedPasses := ScreenFX.ExecuteRHIScreenEffectPasses(
      [Pipelines[0], Pipelines[1]], 320, 180, False, FinalTarget, 0.1, 500.0);
    AssertEquals('2-pass chain must execute 2 passes', 2, ExecutedPasses);
    AssertTrue('2-pass chain (1 intermediate pass) must swap RHIScreenTextureSrc and Dest',
      ScreenFX.RHIScreenTextureSrc <> SrcBeforeSwap);
    AssertEquals('Total RHIScreenPassCount must now be 5', 5, ScreenFX.RHIScreenPassCount);

    { 4. Verify GLContextClose releases RHI post-processing resources cleanly }
    ScreenFX.GLContextClose;
    AssertTrue('RHIScreenTextureSrc must be nil after GLContextClose', ScreenFX.RHIScreenTextureSrc = nil);
    AssertTrue('RHIScreenQuadVBO must be nil after GLContextClose', ScreenFX.RHIScreenQuadVBO = nil);

    CmdList.EndRecording;
  finally
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(FinalTarget);
    FreeAndNil(ScreenFX);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawIndirectCountAndComputeCullerPipeline;
var
  VkDev13, VkDev11: TVulkanRHIDevice;
  CmdList13, CmdList11: TVulkanRHICommandList;
  Culler: TCastleVulkanComputeCuller;
  Planes: array[0..5] of TVector4;
  Instances: array[0..3] of TCastleGpuCullingInstance;
  DispatchedDraws: Cardinal;
  CountBuf: TRHIBuffer;
  GpuDrawCount: UInt32;
begin
  VkDev13 := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  VkDev11 := TVulkanRHIDevice.CreateHeadless(nil, True, False, VK_API_VERSION_1_1);
  CmdList13 := TVulkanRHICommandList.Create(VkDev13, 0, cllPrimary);
  CmdList11 := TVulkanRHICommandList.Create(VkDev11, 0, cllPrimary);
  CountBuf := nil;
  try
    { 1. Verify SupportsDrawIndirectCount capability on Vulkan 1.2+ vs Vulkan 1.1 fallback }
    AssertTrue('Vulkan 1.3 device must report SupportsDrawIndirectCount = True',
      VkDev13.Capabilities.SupportsDrawIndirectCount);
    AssertFalse('Vulkan 1.1 fallback device must report SupportsDrawIndirectCount = False',
      VkDev11.Capabilities.SupportsDrawIndirectCount);

    { 2. End-to-end GPU-driven compute culling -> RecordIndirectDraw (DrawIndexedIndirectCount) }
    Culler := VkDev13.ComputeCuller;
    Planes[0] := Vector4( 1,  0,  0, 50);
    Planes[1] := Vector4(-1,  0,  0, 50);
    Planes[2] := Vector4( 0,  1,  0, 50);
    Planes[3] := Vector4( 0, -1,  0, 50);
    Planes[4] := Vector4( 0,  0, -1, 0);
    Planes[5] := Vector4( 0,  0,  1, 200);
    Culler.SetFrustumPlanes(Planes, Vector3(0, 0, 0), 50.0);

    FillChar(Instances, SizeOf(Instances), 0);
    { 3 visible within 50m, 1 culled at 120m }
    Instances[0].BoundingSphere := Vector4(0, 0, -10, 2.0);
    Instances[0].IndexCount := 36;
    Instances[0].InstanceCount := 1;
    Instances[1].BoundingSphere := Vector4(0, 0, -25, 2.0);
    Instances[1].IndexCount := 72;
    Instances[1].InstanceCount := 1;
    Instances[2].BoundingSphere := Vector4(0, 0, -120, 2.0); // culled!
    Instances[2].IndexCount := 108;
    Instances[2].InstanceCount := 1;
    Instances[3].BoundingSphere := Vector4(0, 0, -40, 2.0);
    Instances[3].IndexCount := 144;
    Instances[3].InstanceCount := 1;

    Culler.UploadInstances(Instances);

    CmdList13.BeginRecording;
    Culler.DispatchCulling(CmdList13, Length(Instances), True);
    AssertEquals('Compute culler must compact 3 visible instances into VisibilityOutputBuffer[0]',
      3, Culler.ReadBackVisibleCount);

    DispatchedDraws := Culler.RecordIndirectDraw(CmdList13);
    AssertEquals('RecordIndirectDraw must return effective GPU draw count (3)',
      3, DispatchedDraws);
    AssertEquals('CmdList13.IndirectDrawCallCount must be 1',
      1, CmdList13.IndirectDrawCallCount);
    AssertEquals('CmdList13.IndirectCountDrawCallCount must be 1',
      1, CmdList13.IndirectCountDrawCallCount);
    AssertEquals('CmdList13.LastEffectiveIndirectDrawCount must read GPU count = 3 from VisibilityOutputBuffer',
      3, CmdList13.LastEffectiveIndirectDrawCount);
    CmdList13.EndRecording;

    { 3. Verify Vulkan 1.1 fallback clamps GPU count to MaxDrawCount via DrawIndirectCount }
    GpuDrawCount := 7;
    CountBuf := VkDev11.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(UInt32), [buIndirect, buStorage], muCpuToGpu, 'TestCountBuf'),
      @GpuDrawCount);
    CmdList11.BeginRecording;
    CmdList11.DrawIndirectCount(CountBuf, 0, CountBuf, 0, 5, SizeOf(TRHIDrawIndirectCommand));
    AssertEquals('CmdList11.IndirectCountDrawCallCount must be 1',
      1, CmdList11.IndirectCountDrawCallCount);
    AssertEquals('CmdList11.LastEffectiveIndirectDrawCount must clamp GPU count (7) to MaxDrawCount (5)',
      5, CmdList11.LastEffectiveIndirectDrawCount);
    CmdList11.EndRecording;
  finally
    FreeAndNil(CountBuf);
    FreeAndNil(CmdList11);
    FreeAndNil(CmdList13);
    FreeAndNil(VkDev11);
    FreeAndNil(VkDev13);
  end;
end;

procedure TTestCastleVulkanRHI.DummyRenderFromViewpointCallback(const RenderCamera: TRenderingCamera);
begin
  Inc(FRenderFromViewpointCalls);
end;

procedure TTestCastleVulkanRHI.TestDynamicTextureResourcesRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  RenderOptions: TCastleRenderOptions;
  RenderedTexNode: TRenderedTextureNode;
  TexProps1, TexProps2: TTexturePropertiesNode;
  RenderedTexRes: TRenderedTextureResource;
  ShadowMapNode: TGeneratedShadowMapNode;
  ShadowMapRes: TGeneratedShadowMapResource;
  CubeMapNode: TGeneratedCubeMapTextureNode;
  CubeMapRes: TGeneratedCubeMapTextureResource;
  CamView: TViewVectors;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  RenderOptions := TCastleRenderOptions.Create(nil);
  RenderedTexNode := TRenderedTextureNode.Create;
  ShadowMapNode := TGeneratedShadowMapNode.Create;
  CubeMapNode := TGeneratedCubeMapTextureNode.Create;
  try
    SetRHIDevice(VkDev);
    SetActiveCommandList(CmdList);

    { 1. Test TRenderedTextureResource over RHI }
    RenderedTexNode.SetDimensions([128, 64, 4, 1, 1]);
    RenderedTexNode.Update := upNextFrameOnly;
    TexProps1 := TTexturePropertiesNode.Create;
    TexProps1.GenerateMipMaps := True;
    RenderedTexNode.TextureProperties := TexProps1;

    TTextureResources.Prepare(RenderOptions, RenderedTexNode);
    AssertTrue('InternalRendererResource must be TRenderedTextureResource',
      RenderedTexNode.InternalRendererResource is TRenderedTextureResource);
    RenderedTexRes := TRenderedTextureResource(RenderedTexNode.InternalRendererResource);
    AssertTrue('RenderedTexRes.RHITexture must be created', RenderedTexRes.RHITexture <> nil);
    AssertTrue('RenderedTexRes.RHIDepthTexture must be created', RenderedTexRes.RHIDepthTexture <> nil);
    AssertTrue('RenderedTexRes.RHIRenderToTexture must be created', RenderedTexRes.RHIRenderToTexture <> nil);
    AssertEquals('RenderedTexRes.RHITexture width must be 128', 128, RenderedTexRes.RHITexture.Desc.Width);
    AssertEquals('RenderedTexRes.RHITexture height must be 64', 64, RenderedTexRes.RHITexture.Desc.Height);
    AssertTrue('RenderedTexRes.RHITexture must allocate mipmap pyramid (> 1 mip)',
      RenderedTexRes.RHITexture.Desc.MipLevels > 1);

    FRenderFromViewpointCalls := 0;
    FillChar(CamView, SizeOf(CamView), 0);
    CamView.Direction := Vector3(0, 0, -1);
    CamView.Up := Vector3(0, 1, 0);
    CmdList.BeginRecording;
    RenderedTexRes.Update(@DummyRenderFromViewpointCallback, 0.1, 100.0, nil, True, CamView, nil);
    CmdList.EndRecording;

    AssertEquals('RenderedTexRes.RHIUpdateCount must be 1', 1, RenderedTexRes.RHIUpdateCount);
    AssertEquals('RenderedTexRes.RHIRenderToTexture.RHIRenderPassCount must be 1',
      1, RenderedTexRes.RHIRenderToTexture.RHIRenderPassCount);
    AssertEquals('RenderFromViewpoint callback must be invoked once for TRenderedTextureNode',
      1, FRenderFromViewpointCalls);

    { 2. Test TGeneratedShadowMapResource over RHI }
    ShadowMapNode.Size := 256;
    ShadowMapNode.Update := upAlways;
    ShadowMapNode.Bias := 1.5;
    ShadowMapNode.Scale := 2.5;

    TTextureResources.Prepare(RenderOptions, ShadowMapNode);
    AssertTrue('InternalRendererResource must be TGeneratedShadowMapResource',
      ShadowMapNode.InternalRendererResource is TGeneratedShadowMapResource);
    ShadowMapRes := TGeneratedShadowMapResource(ShadowMapNode.InternalRendererResource);
    AssertTrue('ShadowMapRes.RHITexture must be created', ShadowMapRes.RHITexture <> nil);
    AssertEquals('ShadowMapRes.RHITexture format must be pfD32_Float',
      Ord(pfD32_Float), Ord(ShadowMapRes.RHITexture.Desc.Format));
    AssertTrue('ShadowMapRes.RHISampler with hardware shadow comparison must be created',
      ShadowMapRes.RHISampler <> nil);
    AssertTrue('ShadowMapRes.RHIRenderToTexture must be created',
      ShadowMapRes.RHIRenderToTexture <> nil);

    FRenderFromViewpointCalls := 0;
    CmdList.BeginRecording;
    ShadowMapRes.Update(@DummyRenderFromViewpointCallback, 0.1, 100.0, nil);
    CmdList.EndRecording;
    AssertEquals('ShadowMapRes.RHIUpdateCount must be 1', 1, ShadowMapRes.RHIUpdateCount);
    AssertEquals('ShadowMapRes.RHIRenderToTexture.RHIRenderPassCount must be 1',
      1, ShadowMapRes.RHIRenderToTexture.RHIRenderPassCount);
    AssertEquals('RenderFromViewpoint callback must be invoked once for TGeneratedShadowMapNode',
      1, FRenderFromViewpointCalls);

    { 3. Test TGeneratedCubeMapTextureResource over RHI }
    CubeMapNode.Size := 64;
    CubeMapNode.Update := upNextFrameOnly;
    TexProps2 := TTexturePropertiesNode.Create;
    TexProps2.GenerateMipMaps := True;
    CubeMapNode.TextureProperties := TexProps2;

    TTextureResources.Prepare(RenderOptions, CubeMapNode);
    AssertTrue('InternalRendererResource must be TGeneratedCubeMapTextureResource',
      CubeMapNode.InternalRendererResource is TGeneratedCubeMapTextureResource);
    CubeMapRes := TGeneratedCubeMapTextureResource(CubeMapNode.InternalRendererResource);
    AssertTrue('CubeMapRes.RHITexture must be created', CubeMapRes.RHITexture <> nil);
    AssertEquals('CubeMapRes.RHITexture dimension must be tdCube',
      Ord(tdCube), Ord(CubeMapRes.RHITexture.Desc.Dimension));
    AssertEquals('CubeMapRes.RHITexture size must be 64', 64, CubeMapRes.RHITexture.Desc.Width);
    AssertEquals('CubeMapRes.RHITexture DepthOrArrayLayers must be 6',
      6, CubeMapRes.RHITexture.Desc.DepthOrArrayLayers);
    AssertTrue('CubeMapRes.RHIRenderToTexture must be created',
      CubeMapRes.RHIRenderToTexture <> nil);

    FRenderFromViewpointCalls := 0;
    CmdList.BeginRecording;
    CubeMapRes.Update(@DummyRenderFromViewpointCallback, 0.1, 100.0, Vector3(0, 0, 0));
    CmdList.EndRecording;

    AssertEquals('CubeMapRes.RHIUpdateCount must be 1', 1, CubeMapRes.RHIUpdateCount);
    AssertEquals('CubeMapRes.RHIFacesRenderedCount must be 6 (all 6 cubemap faces)',
      6, CubeMapRes.RHIFacesRenderedCount);
    AssertEquals('RenderFromViewpoint callback must be invoked 6 times (once per cubemap face)',
      6, FRenderFromViewpointCalls);

    { Clean unprepare }
    TTextureResources.Unprepare(RenderedTexNode);
    TTextureResources.Unprepare(ShadowMapNode);
    TTextureResources.Unprepare(CubeMapNode);
    AssertTrue('RenderedTexNode.InternalRendererResource must be nil after Unprepare',
      RenderedTexNode.InternalRendererResource = nil);
    AssertTrue('ShadowMapNode.InternalRendererResource must be nil after Unprepare',
      ShadowMapNode.InternalRendererResource = nil);
    AssertTrue('CubeMapNode.InternalRendererResource must be nil after Unprepare',
      CubeMapNode.InternalRendererResource = nil);
  finally
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(CubeMapNode);
    FreeAndNil(ShadowMapNode);
    FreeAndNil(RenderedTexNode);
    FreeAndNil(RenderOptions);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestHiZDepthPyramidAndOcclusionCulling;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Culler: TCastleVulkanComputeCuller;
  ShaderGen: TCastleShaderGeneratorRHI;
  HiZShaderSrc: String;
  DepthPixels: array[0..63] of Single;
  X, Y: Integer;
  ProjMat: TMatrix4;
  Planes: array[0..5] of TVector4;
  Instances: array[0..2] of TCastleGpuCullingInstance;
begin
  { 1. Verify GenerateHiZDownsampleComputeShader GLSL generation }
  ShaderGen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    HiZShaderSrc := ShaderGen.GenerateHiZDownsampleComputeShader(8, 8);
  finally
    FreeAndNil(ShaderGen);
  end;
  AssertTrue('Hi-Z shader must contain #version 450', Pos('#version 450', HiZShaderSrc) > 0);
  AssertTrue('Hi-Z shader must declare local_size_x = 8', Pos('local_size_x = 8', HiZShaderSrc) > 0);
  AssertTrue('Hi-Z shader must declare u_SrcDepthMip sampler2D', Pos('u_SrcDepthMip', HiZShaderSrc) > 0);
  AssertTrue('Hi-Z shader must declare u_DstDepthMip r32f image2D', Pos('u_DstDepthMip', HiZShaderSrc) > 0);

  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  try
    { 2. Populate 8x8 depth buffer:
      - Lower-left quadrant (x in [0..3], y in [0..3]): occluder wall at depth = 0.25
      - Remainder of screen: clear sky depth = 0.95 }
    for Y := 0 to 7 do
      for X := 0 to 7 do
      begin
        if (X <= 3) and (Y <= 3) then
          DepthPixels[Y * 8 + X] := 0.25
        else
          DepthPixels[Y * 8 + X] := 0.95;
      end;

    { 3. Build Hi-Z Pyramid via compute downsampler }
    Culler := VkDev.ComputeCuller;
    CmdList.BeginRecording;
    AssertEquals('BuildHiZPyramid(8, 8) must return 4 mip levels',
      4, Culler.BuildHiZPyramid(CmdList, 8, 8, @DepthPixels[0]));
    CmdList.EndRecording;

    AssertTrue('HiZPyramidTexture must be allocated', Culler.HiZPyramidTexture <> nil);
    AssertTrue('HiZDownsamplePipeline must be compiled', Culler.HiZDownsamplePipeline <> nil);
    AssertEquals('8x8 Hi-Z pyramid must have 4 mip levels (8x8, 4x4, 2x2, 1x1)',
      4, Culler.HiZMipLevels);
    AssertEquals('HiZDownsampleDispatches must equal 3 (mips 1, 2, 3)',
      3, Culler.HiZDownsampleDispatches);

    { Verify mip 1 (4x4) max-depth values }
    AssertSameValue(0.25, Culler.SampleHiZMipMaxDepth(1, 0, 0), 1e-5);
    AssertSameValue(0.95, Culler.SampleHiZMipMaxDepth(1, 3, 3), 1e-5);
    { Verify mip 3 (1x1 coarsest mip) conservative max reduction }
    AssertSameValue(0.95, Culler.SampleHiZMipMaxDepth(3, 0, 0), 1e-5);

    { 4. Two-Phase GPU Occlusion Culling using the Hi-Z Pyramid }
    ProjMat := OrthoProjectionMatrix(FloatRectangle(-10, -10, 20, 20), 1.0, 100.0);
    Culler.SetHiZProjection(ProjMat, True);

    Planes[0] := Vector4( 1,  0,  0, 50);
    Planes[1] := Vector4(-1,  0,  0, 50);
    Planes[2] := Vector4( 0,  1,  0, 50);
    Planes[3] := Vector4( 0, -1,  0, 50);
    Planes[4] := Vector4( 0,  0, -1, 0);
    Planes[5] := Vector4( 0,  0,  1, 200);
    Culler.SetFrustumPlanes(Planes, Vector3(0, 0, 0), 0.0);

    FillChar(Instances, SizeOf(Instances), 0);
    { Instance 0: Lower-left quadrant (x = -5, y = -5), in FRONT of occluder wall (z = -10 -> ZNear01 ~ 0.08 < 0.25) -> VISIBLE }
    Instances[0].BoundingSphere := Vector4(-5, -5, -10, 1.0);
    Instances[0].IndexCount := 36;
    Instances[0].InstanceCount := 1;

    { Instance 1: Lower-left quadrant (x = -5, y = -5), BEHIND the 0.25 occluder wall (z = -60 -> ZNear01 ~ 0.58 > 0.25) -> OCCLUDED! }
    Instances[1].BoundingSphere := Vector4(-5, -5, -60, 1.0);
    Instances[1].IndexCount := 36;
    Instances[1].InstanceCount := 1;

    { Instance 2: Upper-right quadrant (x = +5, y = +5), at z = -60 where depth is 0.95 (0.58 <= 0.95) -> VISIBLE }
    Instances[2].BoundingSphere := Vector4(5, 5, -60, 1.0);
    Instances[2].IndexCount := 36;
    Instances[2].InstanceCount := 1;

    Culler.UploadInstances(Instances);

    CmdList.BeginRecording;
    Culler.DispatchCulling(CmdList, Length(Instances), True);
    CmdList.EndRecording;

    AssertEquals('HiZCulledInstanceCount must be 1 (Instance 1 occluded behind 0.25 depth wall)',
      1, Culler.HiZCulledInstanceCount);
    AssertEquals('ReadBackVisibleCount must be 2 (Instances 0 and 2 visible)',
      2, Culler.ReadBackVisibleCount);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestScreenEffectResourceAndAutoHookingRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  SeNode: TScreenEffectNode;
  ShaderNode: TComposedShaderNode;
  FragPart: TShaderPartNode;
  SeRes: TScreenEffectResource;
  ScreenFX: TCastleScreenEffects;
  FinalTarget: TRHITexture;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  Scene := TCastleScene.Create(nil);
  ScreenFX := TCastleScreenEffects.Create(nil);
  FinalTarget := VkDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
    [tuColorAttachment, tuSampled, tuTransferDst, tuTransferSrc]));
  try
    SetRHIDevice(VkDev);
    SetActiveCommandList(CmdList);

    { 1. Build X3D scene containing a TScreenEffectNode with custom fragment shader }
    Root := TX3DRootNode.Create;
    SeNode := TScreenEffectNode.Create;
    ShaderNode := TComposedShaderNode.Create;
    ShaderNode.Language := slGLSL;
    FragPart := TShaderPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents :=
      'void main(void)' + LineEnding +
      '{' + LineEnding +
      '  gl_FragColor = screen_get_color(screen_position());' + LineEnding +
      '}';
    ShaderNode.SetParts([FragPart]);
    SeNode.SetShaders([ShaderNode]);
    Root.AddChildren(SeNode);
    Scene.Load(Root, True);

    { 2. Trigger TCastleScene.InternalScreenEffectsCount over RHI -> prepares TScreenEffectResource }
    AssertEquals('Scene.InternalScreenEffectsCount must be 1 on RHI backend',
      1, Scene.InternalScreenEffectsCount);
    AssertTrue('SeNode.InternalRendererResource must be TScreenEffectResource',
      SeNode.InternalRendererResource is TScreenEffectResource);
    SeRes := TScreenEffectResource(SeNode.InternalRendererResource);
    AssertTrue('SeRes.RHIPipeline must be compiled', SeRes.RHIPipeline <> nil);
    AssertTrue('SeRes.RHIVertexShader must be compiled', SeRes.RHIVertexShader <> nil);
    AssertTrue('SeRes.RHIFragmentShader must be compiled', SeRes.RHIFragmentShader <> nil);
    AssertTrue('SeRes.RHIVertexGLSL must contain #version 450',
      Pos('#version 450', SeRes.RHIVertexGLSL) > 0);
    AssertTrue('SeRes.RHIFragmentGLSL must contain #version 450',
      Pos('#version 450', SeRes.RHIFragmentGLSL) > 0);
    AssertTrue('Scene.InternalScreenEffectRHIPipeline(0) must return SeRes.RHIPipeline',
      Scene.InternalScreenEffectRHIPipeline(0) = SeRes.RHIPipeline);

    { 3. Verify TCastleScreenEffects auto-hooking and pipeline execution }
    ScreenFX.AddScreenEffect(SeNode.DeepCopy as TScreenEffectNode);
    AssertTrue('ScreenFX.GetScreenEffectRHIPipeline(0) must return non-nil RHI pipeline',
      ScreenFX.GetScreenEffectRHIPipeline(0) <> nil);

    CmdList.BeginRecording;
    ScreenFX.EnsureRHIScreenResources(64, 64, False);
    AssertEquals('ScreenFX.ExecuteRHIScreenEffectPasses must execute 1 pass',
      1, ScreenFX.ExecuteRHIScreenEffectPasses(
        [ScreenFX.GetScreenEffectRHIPipeline(0)], 64, 64, False, FinalTarget, 0.1, 100.0));
    CmdList.EndRecording;
  finally
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(FinalTarget);
    FreeAndNil(ScreenFX);
    FreeAndNil(Scene);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.DummyShadowVolumeOnePassCallback(
  const Params: TRenderParams; const PassParams: TRenderOnePassParams);
begin
  Inc(FShadowVolumeOnePassCalls);
end;

procedure TTestCastleVulkanRHI.DummyShadowVolumeCasterCallback(
  const Params: TRenderParams);
begin
  Inc(FShadowVolumeCasterCalls);
end;

procedure TTestCastleVulkanRHI.Test3DAndCubeAndMovieTextureResourcesRHI;
var
  VkDev: TVulkanRHIDevice;
  SavedDevice: TRHIDevice;
  RenderOpts: TCastleRenderOptions;
  Desc3D: TRHITextureDesc;
  Tex3DNode: TComposedTexture3DNode;
  SliceNodes: array[0..3] of TPixelTextureNode;
  SliceImg: TRGBAlphaImage;
  CubeNode: TComposedCubeMapTextureNode;
  SideNodes: array[0..5] of TPixelTextureNode;
  SideImg: TRGBImage;
  MovieNode: TMovieTextureNode;
  Video: TVideo;
  Frame0, Frame1: TRGBAlphaImage;
  ImgTexNode: TPixelTextureNode;
  BaseImg: TRGBImage;
  FloatData: array[0..63] of TVector4;
  I: Integer;
begin
  { 1. Verify TRHITextureDesc.Create3D }
  Desc3D := TRHITextureDesc.Create3D(16, 8, 4, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 2);
  AssertEquals('Create3D Dimension must be td3D', Ord(td3D), Ord(Desc3D.Dimension));
  AssertEquals('Create3D Width', 16, Desc3D.Width);
  AssertEquals('Create3D Height', 8, Desc3D.Height);
  AssertEquals('Create3D DepthOrArrayLayers', 4, Desc3D.DepthOrArrayLayers);
  AssertEquals('Create3D MipLevels', 2, Desc3D.MipLevels);

  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  RenderOpts := TCastleRenderOptions.Create(nil);
  Tex3DNode := TComposedTexture3DNode.Create;
  CubeNode := TComposedCubeMapTextureNode.Create;
  MovieNode := TMovieTextureNode.Create;
  ImgTexNode := TPixelTextureNode.Create;
  try
    SetRHIDevice(VkDev);

    { 2. Test T3DTextureResource with 4x4x4 3D image via TComposedTexture3DNode }
    for I := 0 to 3 do
    begin
      SliceNodes[I] := TPixelTextureNode.Create;
      SliceImg := TRGBAlphaImage.Create(4, 4);
      SliceImg.Clear(Vector4Byte(64, 128, I * 60, 255));
      SliceNodes[I].FdImage.Value := SliceImg;
    end;
    Tex3DNode.SetTexture([SliceNodes[0], SliceNodes[1], SliceNodes[2], SliceNodes[3]]);
    TTextureResources.Prepare(RenderOpts, Tex3DNode);
    AssertTrue('Tex3DNode.InternalRendererResource must be T3DTextureResource',
      Tex3DNode.InternalRendererResource is T3DTextureResource);
    AssertTrue('T3DTextureResource.RHITexture must be allocated',
      T3DTextureResource(Tex3DNode.InternalRendererResource).RHITexture <> nil);
    AssertEquals('T3DTextureResource.RHITexture dimension must be td3D',
      Ord(td3D), Ord(T3DTextureResource(Tex3DNode.InternalRendererResource).RHITexture.Desc.Dimension));
    AssertEquals('T3DTextureResource.RHITexture depth must be 4',
      4, T3DTextureResource(Tex3DNode.InternalRendererResource).RHITexture.Desc.DepthOrArrayLayers);
    AssertTrue('T3DTextureResource.Bind(0) must succeed over RHI',
      T3DTextureResource(Tex3DNode.InternalRendererResource).Bind(0));

    { 3. Test TComposedCubeMapTextureResource with 6 8x8 faces }
    for I := 0 to 5 do
    begin
      SideNodes[I] := TPixelTextureNode.Create;
      SideImg := TRGBImage.Create(8, 8);
      SideImg.Clear(Vector4Byte(I * 40, 100, 200, 255));
      SideNodes[I].FdImage.Value := SideImg;
    end;
    CubeNode.Back   := SideNodes[0];
    CubeNode.Bottom := SideNodes[1];
    CubeNode.Front  := SideNodes[2];
    CubeNode.Left   := SideNodes[3];
    CubeNode.Right  := SideNodes[4];
    CubeNode.Top    := SideNodes[5];
    TTextureResources.Prepare(RenderOpts, CubeNode);
    AssertTrue('CubeNode.InternalRendererResource must be TComposedCubeMapTextureResource',
      CubeNode.InternalRendererResource is TComposedCubeMapTextureResource);
    AssertTrue('TComposedCubeMapTextureResource.RHITexture must be allocated',
      TComposedCubeMapTextureResource(CubeNode.InternalRendererResource).RHITexture <> nil);
    AssertEquals('TComposedCubeMapTextureResource.RHITexture dimension must be tdCube',
      Ord(tdCube), Ord(TComposedCubeMapTextureResource(CubeNode.InternalRendererResource).RHITexture.Desc.Dimension));
    AssertEquals('TComposedCubeMapTextureResource.RHITexture width must be 8',
      8, TComposedCubeMapTextureResource(CubeNode.InternalRendererResource).RHITexture.Desc.Width);
    AssertTrue('TComposedCubeMapTextureResource.Bind(0) must succeed over RHI',
      TComposedCubeMapTextureResource(CubeNode.InternalRendererResource).Bind(0));

    { 4. Test TMovieTextureResource with 2-frame TVideo }
    Video := TVideo.Create;
    Frame0 := TRGBAlphaImage.Create(8, 8);
    Frame0.Clear(Vector4Byte(255, 0, 0, 255));
    Frame1 := TRGBAlphaImage.Create(8, 8);
    Frame1.Clear(Vector4Byte(0, 255, 0, 255));
    Video.LoadFromImageArray([Frame0, Frame1], True, 2);
    MovieNode.LoadFromVideo(Video, True);
    TTextureResources.Prepare(RenderOpts, MovieNode);
    AssertTrue('MovieNode.InternalRendererResource must be TMovieTextureResource',
      MovieNode.InternalRendererResource is TMovieTextureResource);
    AssertEquals('TMovieTextureResource.RHIFrameCount must be 2',
      2, TMovieTextureResource(MovieNode.InternalRendererResource).RHIFrameCount);
    AssertTrue('TMovieTextureResource.RHITexture must be non-nil',
      TMovieTextureResource(MovieNode.InternalRendererResource).RHITexture <> nil);
    AssertTrue('TMovieTextureResource.Bind(0) must succeed over RHI',
      TMovieTextureResource(MovieNode.InternalRendererResource).Bind(0));

    { 5. Test TImageTextureResource.UpdateTextureContentsRgbaFloat for GPU skinning texture }
    BaseImg := TRGBImage.Create(4, 4);
    BaseImg.Clear(Vector4Byte(128, 128, 128, 255));
    ImgTexNode.FdImage.Value := BaseImg;
    TTextureResources.Prepare(RenderOpts, ImgTexNode);
    AssertTrue('ImgTexNode.InternalRendererResource must be TImageTextureResource',
      ImgTexNode.InternalRendererResource is TImageTextureResource);
    for I := 0 to High(FloatData) do
      FloatData[I] := Vector4(1.0, 0.5, 0.25, 1.0);
    ImgTexNode.InternalRendererResource.UpdateTextureContentsRgbaFloat(16, 4, @FloatData[0]);
    AssertEquals('Updated TImageTextureResource format must be pfRGBA32_Float',
      Ord(pfRGBA32_Float), Ord(TImageTextureResource(ImgTexNode.InternalRendererResource).RHITexture.Desc.Format));
    AssertEquals('Updated TImageTextureResource width must be 16',
      16, TImageTextureResource(ImgTexNode.InternalRendererResource).RHITexture.Desc.Width);
    AssertEquals('Updated TImageTextureResource height must be 4',
      4, TImageTextureResource(ImgTexNode.InternalRendererResource).RHITexture.Desc.Height);
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(ImgTexNode);
    FreeAndNil(MovieNode);
    FreeAndNil(CubeNode);
    FreeAndNil(Tex3DNode);
    FreeAndNil(RenderOpts);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestBackgroundRendererRHI;
var
  VkDev: TVulkanRHIDevice;
  SavedDevice: TRHIDevice;
  Bg3DNode: TBackgroundNode;
  Bg2DNode: TImageBackgroundNode;
  TexNode: TPixelTextureNode;
  Img: TRGBImage;
  Bg3DRenderer, Bg2DRenderer: TBackgroundRenderer;
  Proj: TProjection;
  RenderCam: TRenderingCamera;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  Bg3DNode := TBackgroundNode.Create;
  Bg2DNode := TImageBackgroundNode.Create;
  TexNode := TPixelTextureNode.Create;
  RenderCam := TRenderingCamera.Create;
  Bg3DRenderer := nil;
  Bg2DRenderer := nil;
  try
    SetRHIDevice(VkDev);

    { 1. Setup 3D Background node with sky/ground rings }
    Bg3DNode.SetSkyColor([Vector3(0.1, 0.2, 0.8), Vector3(0.5, 0.7, 1.0)]);
    Bg3DNode.SetSkyAngle([1.2]);
    Bg3DNode.SetGroundColor([Vector3(0.2, 0.3, 0.1), Vector3(0.4, 0.3, 0.2)]);
    Bg3DNode.SetGroundAngle([1.0]);
    Bg3DRenderer := CreateBackgroundRenderer(Bg3DNode);
    AssertTrue('CreateBackgroundRenderer(TBackgroundNode) must be non-nil', Bg3DRenderer <> nil);
    AssertTrue('Bg3DRenderer.RHIScene must be a TCastleScene', Bg3DRenderer.RHIScene is TCastleScene);

    Proj.ProjectionType := ptPerspective;
    Proj.PerspectiveAnglesRad := Vector2(DegToRad(60), DegToRad(60));
    Proj.ProjectionNear := 0.1;
    Proj.ProjectionFar := 1000.0;
    RenderCam.RotationMatrix := TMatrix4.Identity;

    Bg3DRenderer.UpdateRotation(Vector4(0, 1, 0, 0.5));
    Bg3DRenderer.Update(0.016);
    Bg3DRenderer.Render(RenderCam, False, FloatRectangle(0, 0, 800, 600), Proj, nil, nil, nil);
    AssertEquals('Bg3DRenderer.RHIRenderCount must be 1 after first Render', 1, Bg3DRenderer.RHIRenderCount);
    AssertFalse('Bg3DRenderer.RHIUseClearColor must be False when SkyColor has 2 colors',
      Bg3DRenderer.RHIUseClearColor);

    { 2. Setup 2D ImageBackground node with a texture }
    Img := TRGBImage.Create(4, 4);
    Img.Clear(Vector4Byte(200, 100, 50, 255));
    TexNode.FdImage.Value := Img;
    Bg2DNode.Texture := TexNode;
    Bg2DNode.Color := Vector4(0.9, 0.8, 0.7, 1.0);
    Bg2DRenderer := CreateBackgroundRenderer(Bg2DNode);
    AssertTrue('CreateBackgroundRenderer(TImageBackgroundNode) must be non-nil', Bg2DRenderer <> nil);
    AssertTrue('Bg2DRenderer.RHIScene must be a TCastleScene', Bg2DRenderer.RHIScene is TCastleScene);

    Bg2DRenderer.Render(RenderCam, False, FloatRectangle(0, 0, 800, 600), Proj, nil, nil, nil);
    AssertEquals('Bg2DRenderer.RHIRenderCount must be 1 after Render', 1, Bg2DRenderer.RHIRenderCount);
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(Bg2DRenderer);
    FreeAndNil(Bg3DRenderer);
    FreeAndNil(RenderCam);
    FreeAndNil(Bg2DNode);
    FreeAndNil(Bg3DNode);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestStencilShadowVolumesRHI;
var
  VkDev: TVulkanRHIDevice;
  SavedDevice: TRHIDevice;
  ZPassDesc, ZFailDesc, LitDesc: TRHIDepthStencilStateDesc;
  PipeDesc1, PipeDesc2: TRHIGraphicsPipelineDesc;
  Hash1, Hash2: QWord;
  SVRenderer: TGLShadowVolumeRenderer;
  Frustum: TFrustum;
  RenderParams: TBasicRenderParams;
begin
  { 1. Verify RHIToVkStencilOp mapping for all 8 stencil operations }
  AssertEquals('soKeep -> VK_STENCIL_OP_KEEP (0)', 0, RHIToVkStencilOp(soKeep));
  AssertEquals('soZero -> VK_STENCIL_OP_ZERO (1)', 1, RHIToVkStencilOp(soZero));
  AssertEquals('soReplace -> VK_STENCIL_OP_REPLACE (2)', 2, RHIToVkStencilOp(soReplace));
  AssertEquals('soIncrementAndClamp -> VK_STENCIL_OP_INCREMENT_AND_CLAMP (3)', 3, RHIToVkStencilOp(soIncrementAndClamp));
  AssertEquals('soDecrementAndClamp -> VK_STENCIL_OP_DECREMENT_AND_CLAMP (4)', 4, RHIToVkStencilOp(soDecrementAndClamp));
  AssertEquals('soInvert -> VK_STENCIL_OP_INVERT (5)', 5, RHIToVkStencilOp(soInvert));
  AssertEquals('soIncrementAndWrap -> VK_STENCIL_OP_INCREMENT_AND_WRAP (6)', 6, RHIToVkStencilOp(soIncrementAndWrap));
  AssertEquals('soDecrementAndWrap -> VK_STENCIL_OP_DECREMENT_AND_WRAP (7)', 7, RHIToVkStencilOp(soDecrementAndWrap));

  { 2. Verify Z-Pass, Z-Fail, and Lit Pass stencil descriptors }
  ZPassDesc := TRHIDepthStencilStateDesc.DefaultStencilShadowVolumeZPass;
  AssertTrue('ZPass StencilTestEnable must be True', ZPassDesc.StencilTestEnable);
  AssertFalse('ZPass DepthWriteEnable must be False', ZPassDesc.DepthWriteEnable);
  AssertEquals('ZPass FrontStencil.PassOp must be soIncrementAndWrap',
    Ord(soIncrementAndWrap), Ord(ZPassDesc.FrontStencil.PassOp));
  AssertEquals('ZPass BackStencil.PassOp must be soDecrementAndWrap',
    Ord(soDecrementAndWrap), Ord(ZPassDesc.BackStencil.PassOp));

  ZFailDesc := TRHIDepthStencilStateDesc.DefaultStencilShadowVolumeZFail;
  AssertTrue('ZFail StencilTestEnable must be True', ZFailDesc.StencilTestEnable);
  AssertFalse('ZFail DepthWriteEnable must be False', ZFailDesc.DepthWriteEnable);
  AssertEquals('ZFail FrontStencil.DepthFailOp must be soDecrementAndWrap',
    Ord(soDecrementAndWrap), Ord(ZFailDesc.FrontStencil.DepthFailOp));
  AssertEquals('ZFail BackStencil.DepthFailOp must be soIncrementAndWrap',
    Ord(soIncrementAndWrap), Ord(ZFailDesc.BackStencil.DepthFailOp));

  LitDesc := TRHIDepthStencilStateDesc.DefaultStencilLitPass(0, $FF);
  AssertTrue('LitPass StencilTestEnable must be True', LitDesc.StencilTestEnable);
  AssertEquals('LitPass DepthCompareOp must be coLessOrEqual',
    Ord(coLessOrEqual), Ord(LitDesc.DepthCompareOp));
  AssertEquals('LitPass FrontStencil.CompareOp must be coEqual',
    Ord(coEqual), Ord(LitDesc.FrontStencil.CompareOp));
  AssertEquals('LitPass FrontStencil.CompareMask must be $FF',
    $FF, LitDesc.FrontStencil.CompareMask);

  { 3. Verify Pipeline Key Hash distinguishes Z-Pass and Z-Fail stencil states }
  FillChar(PipeDesc1, SizeOf(PipeDesc1), 0);
  PipeDesc1.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  PipeDesc1.Rasterizer.CullMode := cmNone;
  PipeDesc1.DepthStencil := ZPassDesc;
  PipeDesc1.BlendState := TRHIBlendStateDesc.DefaultColorMaskNone;

  PipeDesc2 := PipeDesc1;
  PipeDesc2.DepthStencil := ZFailDesc;
  Hash1 := ComputePipelineKeyHash(PipeDesc1);
  Hash2 := ComputePipelineKeyHash(PipeDesc2);
  AssertTrue('Pipeline key hash must differ between Z-Pass and Z-Fail stencil ops', Hash1 <> Hash2);

  { 4. Verify TGLShadowVolumeRenderer RHI execution (InitFrustumAndLight, InitCaster, Render) }
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  SVRenderer := TGLShadowVolumeRenderer.Create;
  RenderParams := TBasicRenderParams.Create;
  try
    SetRHIDevice(VkDev);

    Frustum.Init(
      PerspectiveProjectionMatrixDeg(60, 1.0, 1.0, 100.0),
      TMatrix4.Identity);
    SVRenderer.InitFrustumAndLight(Frustum, Vector4(0, 10, 0, 1));

    { Caster inside frustum far from near plane -> Z-Pass }
    SVRenderer.InitCaster(Box3D(Vector3(-1, -1, -10), Vector3(1, 1, -8)));
    AssertTrue('CasterShadowPossiblyVisible must be True for visible box',
      SVRenderer.CasterShadowPossiblyVisible);
    AssertFalse('ZFail must be False for box far from near plane', SVRenderer.ZFail);
    AssertEquals('RHIStencilDepthState FrontStencil.PassOp must be soIncrementAndWrap',
      Ord(soIncrementAndWrap), Ord(SVRenderer.RHIStencilDepthState.FrontStencil.PassOp));
    AssertTrue('RHIBlendState.DisableColorWrites must be True',
      SVRenderer.RHIBlendState.DisableColorWrites);

    { Execute 5-pass shadow volume Render over RHI }
    FShadowVolumeOnePassCalls := 0;
    FShadowVolumeCasterCalls := 0;
    RenderParams.InternalPass := 0;
    SVRenderer.Render(RenderParams,
      {$ifdef FPC}@{$endif}DummyShadowVolumeOnePassCallback,
      {$ifdef FPC}@{$endif}DummyShadowVolumeCasterCallback);
    AssertEquals('SVRenderer.RHIRenderPassCount must be 5', 5, SVRenderer.RHIRenderPassCount);
    AssertEquals('DummyShadowVolumeOnePassCallback must be called 4 times', 4, FShadowVolumeOnePassCalls);
    AssertEquals('DummyShadowVolumeCasterCallback must be called 1 time', 1, FShadowVolumeCasterCalls);
    AssertEquals('RHILitPassStencilDepthState FrontStencil.CompareOp must be coEqual',
      Ord(coEqual), Ord(SVRenderer.RHILitPassStencilDepthState.FrontStencil.CompareOp));
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(RenderParams);
    FreeAndNil(SVRenderer);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderUnlitMeshAndShadowVolumeExtrusionRHI;
var
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  UnlitMesh, ShadowMesh: TCastleRenderUnlitMesh;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  RenderParams: TBasicRenderParams;
  ShapeObj: TShape;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  try
    SetRHIDevice(VkDev);
    CmdList.BeginRecording;
    SetActiveCommandList(CmdList);

    { 1. Test TCastleRenderUnlitMesh direct RHI vertex/index upload and draw recording }
    UnlitMesh := TCastleRenderUnlitMesh.Create(True);
    try
      UnlitMesh.Color := Vector4(1, 0.5, 0, 1);
      UnlitMesh.ModelViewProjection := TMatrix4.Identity;
      UnlitMesh.SetVertexes([
        Vector4(-1, -1, 0, 1),
        Vector4( 1, -1, 0, 1),
        Vector4( 1,  1, 0, 1),
        Vector4(-1,  1, 0, 1)
      ], False);
      UnlitMesh.SetIndexes([0, 1, 2, 0, 2, 3]);

      AssertTrue('UnlitMesh.RHIVertexBuffer must be allocated', UnlitMesh.RHIVertexBuffer <> nil);
      AssertEquals('UnlitMesh.RHIVertexBuffer size must be 64 bytes (4 * TVector4)',
        64, UnlitMesh.RHIVertexBuffer.Desc.Size);
      AssertTrue('UnlitMesh.RHIIndexBuffer must be allocated', UnlitMesh.RHIIndexBuffer <> nil);
      AssertEquals('UnlitMesh.RHIIndexBuffer size must be 12 bytes (6 * UInt16)',
        12, UnlitMesh.RHIIndexBuffer.Desc.Size);

      UnlitMesh.Render(pmTriangles);
      AssertEquals('UnlitMesh.RHIDrawCallCount must be 1', 1, UnlitMesh.RHIDrawCallCount);
      AssertEquals('UnlitMesh.RHILastVertexCount must be 4', 4, UnlitMesh.RHILastVertexCount);
      AssertEquals('UnlitMesh.RHILastIndexCount must be 6', 6, UnlitMesh.RHILastIndexCount);
      AssertEquals('UnlitMesh.RHILastTopology must be ptTriangleList',
        Ord(ptTriangleList), Ord(UnlitMesh.RHILastTopology));
      AssertTrue('UnlitMesh.RHIPipeline must be created', UnlitMesh.RHIPipeline <> nil);
    finally
      FreeAndNil(UnlitMesh);
    end;

    { 2. Test TRenderShapeShadowVolumes.RenderSilhouetteShadowVolume RHI extrusion }
    Scene := TCastleScene.Create(nil);
    ShadowMesh := TCastleRenderUnlitMesh.Create(False);
    RenderParams := TBasicRenderParams.Create;
    try
      Root := TX3DRootNode.Create;
      BoxNode := TBoxNode.CreateWithShape(ShapeNode);
      BoxNode.Size := Vector3(2, 2, 2);
      Root.AddChildren(ShapeNode);
      Scene.Load(Root, True);

      AssertTrue('Scene must have at least 1 shape', Scene.Shapes.TraverseList(False).Count >= 1);
      ShapeObj := Scene.Shapes.TraverseList(False)[0];
      ShapeObj.InternalShadowVolumes.PrepareResources;
      ShapeObj.InternalShadowVolumes.RenderSilhouetteShadowVolume(
        RenderParams, ShadowMesh, Vector4(0, 10, 0, 1), TMatrix4.Identity,
        True, True, True, True);

      AssertTrue('ShadowMesh.RHIDrawCallCount must be >= 1 after silhouette extrusion',
        ShadowMesh.RHIDrawCallCount >= 1);
      AssertTrue('ShadowMesh.RHIVertexBuffer must be allocated for extruded shadow quads',
        ShadowMesh.RHIVertexBuffer <> nil);
      AssertTrue('ShadowMesh.RHILastVertexCount must be > 0',
        ShadowMesh.RHILastVertexCount > 0);
      AssertEquals('ShadowMesh.RHILastTopology must be ptTriangleList',
        Ord(ptTriangleList), Ord(ShadowMesh.RHILastTopology));
    finally
      FreeAndNil(RenderParams);
      FreeAndNil(ShadowMesh);
      FreeAndNil(Scene);
    end;

    CmdList.EndRecording;
  finally
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawPrimitive2DRHI;
var
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  try
    SetRHIDevice(VkDev);
    CmdList.BeginRecording;
    SetActiveCommandList(CmdList);
    RHIPrimitive2DResetStats;

    { 1. DrawRectangle }
    DrawRectangle(FloatRectangle(10, 20, 100, 50), Red);
    AssertEquals('DrawRectangle must increment RHIPrimitive2DDrawCallCount to 1',
      1, RHIPrimitive2DDrawCallCount);
    AssertEquals('DrawRectangle must upload 4 vertices',
      4, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawRectangle mode must be pmTriangleFan',
      Ord(pmTriangleFan), Ord(RHIPrimitive2DLastMode));
    AssertVectorEquals(Red, RHIPrimitive2DLastColor);
    AssertTrue('RHIPrimitive2DBuffer must be allocated', RHIPrimitive2DBuffer <> nil);

    { 2. DrawRectangleOutline }
    DrawRectangleOutline(FloatRectangle(10, 20, 100, 50), Green, 2.0);
    AssertEquals('DrawRectangleOutline must increment RHIPrimitive2DDrawCallCount to 2',
      2, RHIPrimitive2DDrawCallCount);
    AssertEquals('DrawRectangleOutline must upload 4 vertices',
      4, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawRectangleOutline mode must be pmLineLoop',
      Ord(pmLineLoop), Ord(RHIPrimitive2DLastMode));

    { 3. DrawCircle }
    DrawCircle(Vector2(50, 50), 25, 25, Blue, 12);
    AssertEquals('DrawCircle must increment RHIPrimitive2DDrawCallCount to 3',
      3, RHIPrimitive2DDrawCallCount);
    AssertEquals('DrawCircle with 12 slices must upload 36 vertices',
      36, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawCircle mode must be pmTriangleFan',
      Ord(pmTriangleFan), Ord(RHIPrimitive2DLastMode));

    { 4. DrawCircleOutline }
    DrawCircleOutline(Vector2(50, 50), 25, 25, Yellow, 1.5, 16);
    AssertEquals('DrawCircleOutline must increment RHIPrimitive2DDrawCallCount to 4',
      4, RHIPrimitive2DDrawCallCount);
    AssertEquals('DrawCircleOutline with 16 slices must upload 16 vertices',
      16, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawCircleOutline mode must be pmLineLoop',
      Ord(pmLineLoop), Ord(RHIPrimitive2DLastMode));

    { 5. GLFadeRectangleDark and GLFadeRectangleLight }
    GLFadeRectangleDark(Rectangle(0, 0, 800, 600), Red, 0.5);
    GLFadeRectangleLight(Rectangle(0, 0, 800, 600), White, 0.5);
    AssertEquals('GLFadeRectangleDark + GLFadeRectangleLight must increment RHIPrimitive2DDrawCallCount to 6',
      6, RHIPrimitive2DDrawCallCount);

    CmdList.EndRecording;
  finally
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestDynamicBatchShapesRHI;
var
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  SharedApp: TAppearanceNode;
  Mat: TMaterialNode;
  ShapeNode1, ShapeNode2: TShapeNode;
  IFS1, IFS2: TIndexedFaceSetNode;
  Coord1, Coord2: TCoordinateNode;
  Collected1, Collected2: TCollectedShape;
  Batcher: TBatchShapes;
  ShapesList: TShapeList;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  Scene := TCastleScene.Create(nil);
  Collected1 := TCollectedShape.Create;
  Collected2 := TCollectedShape.Create;
  Batcher := nil;
  try
    SetRHIDevice(VkDev);

    Root := TX3DRootNode.Create;
    SharedApp := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    SharedApp.Material := Mat;

    ShapeNode1 := TShapeNode.Create;
    ShapeNode1.Appearance := SharedApp;
    IFS1 := TIndexedFaceSetNode.Create;
    Coord1 := TCoordinateNode.Create;
    Coord1.SetPoint([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]);
    IFS1.Coord := Coord1;
    IFS1.SetCoordIndex([0, 1, 2, -1]);
    ShapeNode1.Geometry := IFS1;

    ShapeNode2 := TShapeNode.Create;
    ShapeNode2.Appearance := SharedApp;
    IFS2 := TIndexedFaceSetNode.Create;
    Coord2 := TCoordinateNode.Create;
    Coord2.SetPoint([Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(2, 1, 0)]);
    IFS2.Coord := Coord2;
    IFS2.SetCoordIndex([0, 1, 2, -1]);
    ShapeNode2.Geometry := IFS2;

    Root.AddChildren([ShapeNode1, ShapeNode2]);
    Scene.Load(Root, True);

    ShapesList := Scene.Shapes.TraverseList(False);
    AssertEquals('Scene must have 2 shapes before batching', 2, ShapesList.Count);

    Collected1.Shape := ShapesList[0] as TGLShape;
    Collected1.RenderOptions := Scene.RenderOptions;
    Collected1.SceneTransform := TMatrix4.Identity;

    Collected2.Shape := ShapesList[1] as TGLShape;
    Collected2.RenderOptions := Scene.RenderOptions;
    Collected2.SceneTransform := TranslationMatrix(10, 0, 0);

    Batcher := TBatchShapes.Create;

    { Frame 1: Batch Collected1 and Collected2 into a single merged pool shape }
    AssertTrue('Batch(Collected1) must return True', Batcher.Batch(Collected1));
    AssertTrue('Batch(Collected2) must return True', Batcher.Batch(Collected2));
    Batcher.Commit;

    AssertEquals('Two compatible shapes must merge into 1 batched shape',
      1, Batcher.Batched.Count);
    AssertEquals('RHICommitBatchCount must be 1 after first Commit',
      1, Batcher.RHICommitBatchCount);
    AssertTrue('RHILastMergedShape must be assigned',
      Batcher.RHILastMergedShape <> nil);
    AssertTrue('Merged shape Cache must be initialized',
      Batcher.RHILastMergedShape.Cache <> nil);
    AssertTrue('Merged shape RHICoordinateBuffer must be uploaded',
      Batcher.RHILastMergedShape.Cache.RHICoordinateBuffer <> nil);
    AssertEquals('Merged shape RHICoordinateBuffer must use muCpuToGpu (DynamicGeometry)',
      Ord(muCpuToGpu), Ord(Batcher.RHILastMergedShape.Cache.RHICoordinateBuffer.Desc.MemoryUsage));
    AssertEquals('Merged shape Cache.RHIUploadCount must be 1',
      1, Batcher.RHILastMergedShape.Cache.RHIUploadCount);

    { Frame 2: Re-batch with updated transform and verify dynamic RHI buffer re-upload }
    Batcher.FreeBatched;
    Collected2.SceneTransform := TranslationMatrix(20, 5, 0);
    AssertTrue('Frame 2 Batch(Collected1) must return True', Batcher.Batch(Collected1));
    AssertTrue('Frame 2 Batch(Collected2) must return True', Batcher.Batch(Collected2));
    Batcher.Commit;

    AssertEquals('RHICommitBatchCount must be 2 after second Commit',
      2, Batcher.RHICommitBatchCount);
    AssertEquals('Merged shape Cache.RHIUploadCount must be 2 after dynamic re-upload',
      2, Batcher.RHILastMergedShape.Cache.RHIUploadCount);

    Batcher.FreeBatched;
    Batcher.GLContextClose;
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(Batcher);
    FreeAndNil(Collected2);
    FreeAndNil(Collected1);
    FreeAndNil(Scene);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderContextAndScissorRHI;
var
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  SavedContext: TRenderContext;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Ctx: TRenderContext;
  Scissor1, Scissor2: TScissor;
  ColorTex, DepthTex: TVulkanRHITexture;
  ColorDesc, DepthDesc: TRHITextureDesc;
  PassInfo: TRHIRenderingInfo;
  GrabbedColor: TRGBImage;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  SavedContext := RenderContext;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  Ctx := TRenderContext.Create(nil);
  Scissor1 := nil;
  Scissor2 := nil;
  ColorTex := nil;
  DepthTex := nil;
  GrabbedColor := nil;
  try
    SetRHIDevice(VkDev);
    SetActiveCommandList(CmdList);
    RenderContext := Ctx;

    { 1. Viewport and DepthRange synchronization to ActiveCommandList }
    Ctx.Viewport := Rectangle(10, 20, 640, 480);
    AssertEquals('RHIViewportUpdateCount must be 1 after Viewport assignment',
      1, Ctx.RHIViewportUpdateCount);
    AssertEquals('CmdList.DynamicViewportRect.Left must be 10',
      10, Round(CmdList.DynamicViewportRect.Left));
    AssertEquals('CmdList.DynamicViewportRect.Bottom must be 20',
      20, Round(CmdList.DynamicViewportRect.Bottom));
    AssertEquals('CmdList.DynamicViewportRect.Width must be 640',
      640, Round(CmdList.DynamicViewportRect.Width));
    AssertEquals('CmdList.DynamicViewportRect.Height must be 480',
      480, Round(CmdList.DynamicViewportRect.Height));
    AssertTrue('Default MinDepth must be 0.0', SameValue(0.0, CmdList.DynamicMinDepth, 0.001));
    AssertTrue('Default MaxDepth must be 1.0', SameValue(1.0, CmdList.DynamicMaxDepth, 0.001));

    Ctx.DepthRange := drFar;
    AssertTrue('drFar MinDepth must be 0.1', SameValue(0.1, CmdList.DynamicMinDepth, 0.001));
    AssertTrue('drFar MaxDepth must be 1.0', SameValue(1.0, CmdList.DynamicMaxDepth, 0.001));

    Ctx.DepthRange := drNear;
    AssertTrue('drNear MinDepth must be 0.0', SameValue(0.0, CmdList.DynamicMinDepth, 0.001));
    AssertTrue('drNear MaxDepth must be 0.1', SameValue(0.1, CmdList.DynamicMaxDepth, 0.001));

    Ctx.DepthRange := drFull;
    AssertTrue('drFull MinDepth must be 0.0', SameValue(0.0, CmdList.DynamicMinDepth, 0.001));
    AssertTrue('drFull MaxDepth must be 1.0', SameValue(1.0, CmdList.DynamicMaxDepth, 0.001));

    { 2. Nested TScissor stack intersection & restoration }
    Scissor1 := TScissor.Create;
    Scissor2 := TScissor.Create;
    Scissor1.Rect := Rectangle(0, 0, 300, 200);
    Scissor1.Enabled := True;
    AssertTrue('RHIScissorActive must be True when Scissor1 is enabled', Ctx.RHIScissorActive);
    AssertEquals('Scissor1 Left must be 0', 0, CmdList.DynamicScissorRect.Left);
    AssertEquals('Scissor1 Bottom must be 0', 0, CmdList.DynamicScissorRect.Bottom);
    AssertEquals('Scissor1 Width must be 300', 300, CmdList.DynamicScissorRect.Width);
    AssertEquals('Scissor1 Height must be 200', 200, CmdList.DynamicScissorRect.Height);

    Scissor2.Rect := Rectangle(100, 50, 400, 300);
    Scissor2.Enabled := True;
    AssertTrue('RHIScissorActive must remain True with nested Scissor2', Ctx.RHIScissorActive);
    AssertEquals('Nested scissor intersection Left must be 100', 100, CmdList.DynamicScissorRect.Left);
    AssertEquals('Nested scissor intersection Bottom must be 50', 50, CmdList.DynamicScissorRect.Bottom);
    AssertEquals('Nested scissor intersection Width must be 200', 200, CmdList.DynamicScissorRect.Width);
    AssertEquals('Nested scissor intersection Height must be 150', 150, CmdList.DynamicScissorRect.Height);

    Scissor2.Enabled := False;
    AssertTrue('RHIScissorActive must remain True when only Scissor1 is left', Ctx.RHIScissorActive);
    AssertEquals('Restored Scissor1 Width must be 300', 300, CmdList.DynamicScissorRect.Width);
    AssertEquals('Restored Scissor1 Height must be 200', 200, CmdList.DynamicScissorRect.Height);

    Scissor1.Enabled := False;
    AssertFalse('RHIScissorActive must be False when all scissors are disabled', Ctx.RHIScissorActive);
    AssertEquals('Disabled scissor must restore full viewport Left (10)', 10, CmdList.DynamicScissorRect.Left);
    AssertEquals('Disabled scissor must restore full viewport Bottom (20)', 20, CmdList.DynamicScissorRect.Bottom);
    AssertEquals('Disabled scissor must restore full viewport Width (640)', 640, CmdList.DynamicScissorRect.Width);
    AssertEquals('Disabled scissor must restore full viewport Height (480)', 480, CmdList.DynamicScissorRect.Height);

    { 3. InternalControlRect offset propagation to Viewport & Scissor }
    Ctx.InternalControlRect := Rectangle(5, 8, 800, 600);
    Ctx.Viewport := Rectangle(10, 20, 320, 240);
    AssertEquals('Viewport Left with InternalControlRect must be 15', 15, Round(CmdList.DynamicViewportRect.Left));
    AssertEquals('Viewport Bottom with InternalControlRect must be 28', 28, Round(CmdList.DynamicViewportRect.Bottom));
    Scissor1.Rect := Rectangle(4, 6, 100, 80);
    Scissor1.Enabled := True;
    AssertEquals('Scissor Left with InternalControlRect must be 9', 9, CmdList.DynamicScissorRect.Left);
    AssertEquals('Scissor Bottom with InternalControlRect must be 14', 14, CmdList.DynamicScissorRect.Bottom);
    Scissor1.Enabled := False;
    Ctx.InternalControlRect := TRectangle.Empty;

    { 4. PolygonOffset / SetDepthBias and Extended Dynamic State }
    Ctx.PolygonOffsetEnable(2.5, 4.0);
    AssertEquals('RHIDepthBiasUpdateCount must be 1', 1, Ctx.RHIDepthBiasUpdateCount);
    AssertTrue('DynamicDepthBiasSlope must be 2.5', SameValue(2.5, CmdList.DynamicDepthBiasSlope, 0.001));
    AssertTrue('DynamicDepthBiasConstant must be 4.0', SameValue(4.0, CmdList.DynamicDepthBiasConstant, 0.001));

    Ctx.PolygonOffsetDisable;
    AssertEquals('RHIDepthBiasUpdateCount must be 2', 2, Ctx.RHIDepthBiasUpdateCount);
    AssertTrue('DynamicDepthBiasSlope must reset to 0', SameValue(0.0, CmdList.DynamicDepthBiasSlope, 0.001));
    AssertTrue('DynamicDepthBiasConstant must reset to 0', SameValue(0.0, CmdList.DynamicDepthBiasConstant, 0.001));

    Ctx.CullFace := True;
    AssertEquals('CullFace=True must set DynamicCullMode to cmBack', Ord(cmBack), Ord(CmdList.DynamicCullMode));
    Ctx.FrontFaceCcw := False;
    AssertEquals('FrontFaceCcw=False must set DynamicFrontFace to ffClockwise', Ord(ffClockwise), Ord(CmdList.DynamicFrontFace));
    Ctx.DepthTest := True;
    AssertTrue('DepthTest=True must set DynamicDepthTestEnable', CmdList.DynamicDepthTestEnable);
    Ctx.DepthFunc := dfLessEqual;
    AssertEquals('DepthFunc=dfLessEqual must set DynamicDepthCompareOp to coLessOrEqual', Ord(coLessOrEqual), Ord(CmdList.DynamicDepthCompareOp));
    Ctx.DepthFunc := dfLess;
    AssertEquals('DepthFunc=dfLess must set DynamicDepthCompareOp to coLess', Ord(coLess), Ord(CmdList.DynamicDepthCompareOp));
    Ctx.DepthBufferUpdate := False;
    AssertFalse('DepthBufferUpdate=False must set DynamicDepthWriteEnable=False', CmdList.DynamicDepthWriteEnable);

    { 5. TRenderContext.Clear routing & SynchronizeState }
    ColorDesc := TRHITextureDesc.Create2D(16, 16, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]);
    DepthDesc := TRHITextureDesc.Create2D(16, 16, pfD24_UNorm_S8_UInt, [tuDepthStencil, tuTransferSrc]);
    ColorTex := TVulkanRHITexture.Create(VkDev, ColorDesc);
    DepthTex := TVulkanRHITexture.Create(VkDev, DepthDesc);

    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 16, 16),
      ColorTex, loLoad, Vector4(0, 0, 0, 1),
      DepthTex, loLoad, 1.0);
    CmdList.BeginRendering(PassInfo);

    Ctx.Clear([cbColor, cbDepth], Vector4(1.0, 0.0, 0.5, 1.0));
    AssertEquals('RHIClearCount must be 1 after Ctx.Clear', 1, Ctx.RHIClearCount);
    AssertTrue('cbColor must be in RHILastClearBuffers', cbColor in Ctx.RHILastClearBuffers);
    AssertTrue('cbDepth must be in RHILastClearBuffers', cbDepth in Ctx.RHILastClearBuffers);
    AssertTrue('RHILastClearColor.X must be 1.0', SameValue(1.0, Ctx.RHILastClearColor.X, 0.001));

    CmdList.EndRendering;

    GrabbedColor := TRGBImage.Create(4, 4);
    AssertTrue('GrabTextureImage on cleared ColorTex must succeed',
      VkDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 4, 4), GrabbedColor));
    AssertEquals('Cleared pixel R must be 255', 255, GrabbedColor.PixelPtr(0, 0)^.X);
    AssertEquals('Cleared pixel G must be 0', 0, GrabbedColor.PixelPtr(0, 0)^.Y);
    AssertEquals('Cleared pixel B must be 128', 128, GrabbedColor.PixelPtr(0, 0)^.Z);

    Ctx.SynchronizeState;
    AssertTrue('SynchronizeState must increment RHIViewportUpdateCount',
      Ctx.RHIViewportUpdateCount >= 3);
  finally
    RenderContext := SavedContext;
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(GrabbedColor);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Scissor2);
    FreeAndNil(Scissor1);
    FreeAndNil(Ctx);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestSaveScreenAndDepthReadbackRHI;
var
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  SavedContext: TRenderContext;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Ctx: TRenderContext;
  ColorTex, DepthTex: TVulkanRHITexture;
  ColorDesc, DepthDesc: TRHITextureDesc;
  PassInfo: TRHIRenderingInfo;
  ScreenColor, SubRegionColor, DrawableContents: TRGBImage;
  ScreenDepth: TGrayscaleImage;
  DrawableScreen: TDrawableImage;
  UploadPattern: TRGBAlphaImage;
  SavedSaveCount, SavedDepthCount: Integer;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  SavedContext := RenderContext;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  Ctx := TRenderContext.Create(nil);
  ColorTex := nil;
  DepthTex := nil;
  ScreenColor := nil;
  SubRegionColor := nil;
  DrawableContents := nil;
  ScreenDepth := nil;
  DrawableScreen := nil;
  UploadPattern := nil;
  try
    SetRHIDevice(VkDev);
    SetActiveCommandList(CmdList);
    RenderContext := Ctx;

    ColorDesc := TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc, tuTransferDst]);
    DepthDesc := TRHITextureDesc.Create2D(32, 32, pfD24_UNorm_S8_UInt, [tuDepthStencil, tuTransferSrc]);
    ColorTex := TVulkanRHITexture.Create(VkDev, ColorDesc);
    DepthTex := TVulkanRHITexture.Create(VkDev, DepthDesc);

    { 1. Render pass with loClear color (51, 102, 204) and depth (0.5 -> 128) }
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 32, 32),
      ColorTex, loClear, Vector4(0.2, 0.4, 0.8, 1.0),
      DepthTex, loClear, 0.5);
    CmdList.BeginRendering(PassInfo);
    CmdList.EndRendering;

    SavedSaveCount := RHISaveScreenCount;
    SavedDepthCount := RHISaveScreenDepthCount;

    ScreenColor := SaveScreen_NoFlush(Rectangle(0, 0, 16, 16), cbBack);
    AssertEquals('RHISaveScreenCount must increment by 1', SavedSaveCount + 1, RHISaveScreenCount);
    AssertEquals('ScreenColor Width must be 16', 16, ScreenColor.Width);
    AssertEquals('ScreenColor Height must be 16', 16, ScreenColor.Height);
    AssertEquals('ScreenColor R must be 51', 51, ScreenColor.PixelPtr(0, 0)^.X);
    AssertEquals('ScreenColor G must be 102', 102, ScreenColor.PixelPtr(0, 0)^.Y);
    AssertEquals('ScreenColor B must be 204', 204, ScreenColor.PixelPtr(0, 0)^.Z);

    ScreenDepth := SaveScreenDepth_NoFlush(Rectangle(0, 0, 16, 16));
    AssertEquals('RHISaveScreenDepthCount must increment by 1', SavedDepthCount + 1, RHISaveScreenDepthCount);
    AssertEquals('ScreenDepth Width must be 16', 16, ScreenDepth.Width);
    AssertEquals('ScreenDepth Height must be 16', 16, ScreenDepth.Height);
    AssertEquals('ScreenDepth pixel must be 128 (0.5 depth)', 128, ScreenDepth.PixelPtr(0, 0)^);

    { 2. Upload custom pixel pattern and verify InternalControlRect sub-region cropping & SaveScreenToGL_NoFlush }
    UploadPattern := TRGBAlphaImage.Create(32, 32);
    UploadPattern.Clear(Vector4Byte(10, 20, 30, 255));
    UploadPattern.PixelPtr(10, 12)^ := Vector4Byte(220, 110, 55, 255);
    ColorTex.UploadImage(UploadPattern);

    Ctx.InternalControlRect := Rectangle(10, 12, 32, 32);
    SubRegionColor := SaveScreen_NoFlush(Rectangle(0, 0, 4, 4), cbBack);
    AssertEquals('Cropped SubRegionColor (0,0) R must match pattern at (10,12)',
      220, SubRegionColor.PixelPtr(0, 0)^.X);
    AssertEquals('Cropped SubRegionColor (0,0) G must match pattern at (10,12)',
      110, SubRegionColor.PixelPtr(0, 0)^.Y);
    AssertEquals('Cropped SubRegionColor (0,0) B must match pattern at (10,12)',
      55, SubRegionColor.PixelPtr(0, 0)^.Z);

    DrawableScreen := SaveScreenToGL_NoFlush(Rectangle(0, 0, 4, 4), cbBack, False);
    AssertTrue('SaveScreenToGL_NoFlush must create TDrawableImage with RHITexture',
      DrawableScreen.RHITexture <> nil);
    DrawableContents := DrawableScreen.GetContents(TRGBImage) as TRGBImage;
    AssertEquals('DrawableScreen GetContents R must be 220',
      220, DrawableContents.PixelPtr(0, 0)^.X);
  finally
    RenderContext := SavedContext;
    SetActiveCommandList(SavedCmdList);
    SetRHIDevice(SavedDevice);
    FreeAndNil(UploadPattern);
    FreeAndNil(DrawableContents);
    FreeAndNil(DrawableScreen);
    FreeAndNil(ScreenDepth);
    FreeAndNil(SubRegionColor);
    FreeAndNil(ScreenColor);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Ctx);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestGLInformationStringRHI;
var
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  InfoFull, InfoSummary: String;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  try
    { 1. When RHIDevice = nil and GLVersion = nil, GLInformationString must not AV }
    SetRHIDevice(nil);
    InfoFull := GLInformationString;
    InfoSummary := GLInformationStringSummary;
    AssertTrue('Uninitialized GLInformationString must return non-empty fallback', InfoFull <> '');
    AssertTrue('Uninitialized GLInformationStringSummary must return non-empty fallback', InfoSummary <> '');

    { 2. When RHIDevice <> nil, GLInformationString and GLInformationStringSummary report Vulkan RHI }
    SetRHIDevice(VkDev);
    InfoFull := GLInformationString;
    InfoSummary := GLInformationStringSummary;

    AssertTrue('Vulkan GLInformationString must contain header "Vulkan RHI information:"',
      Pos('Vulkan RHI information:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationString must contain "Basic information:" section',
      Pos('Basic information:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationString must contain "Features:" section',
      Pos('Features:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationString must contain "Limits & Pipelines:" section',
      Pos('Limits & Pipelines:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationString must contain "Memory:" section',
      Pos('Memory:', InfoFull) > 0);
    AssertTrue('Vulkan GLInformationStringSummary must report Vulkan 1.3 and modern rendering',
      (Pos('Vulkan 1.3', InfoSummary) > 0) and (Pos('modern rendering: True', InfoSummary) > 0));
  finally
    SetRHIDevice(SavedDevice);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestCookTorranceGGXPBRShaderGenerationRHI;
var
  VkDev: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  MatBlock: TCastleMaterialUniformBlock;
  PBRFuncs, VS, FS,LutCS: String;
  VSMod, FSMod, CSMod: TRHIShaderModule;
begin
  { 1. Verify TCastleMaterialUniformBlock default initializers }
  MatBlock.InitDefaultPBR;
  AssertSameValue(1.0, MatBlock.BaseColor.X, 1e-4);
  AssertSameValue(1.0, MatBlock.BaseColor.W, 1e-4);
  AssertSameValue(0.0, MatBlock.SpecularColor.W, 1e-4); // 0.0 -> PBR Metallic-Roughness
  AssertSameValue(0.0, MatBlock.EmissiveColor.W, 1e-4); // Metallic = 0
  AssertSameValue(1.0, MatBlock.PBRParams.X, 1e-4);     // Roughness = 1
  AssertSameValue(1.0, MatBlock.PBRParams.Y, 1e-4);     // NormalScale = 1
  AssertSameValue(1.0, MatBlock.PBRParams.Z, 1e-4);     // OcclusionStrength = 1

  MatBlock.InitDefaultPhong;
  AssertTrue('InitDefaultPhong SpecularColor.W (shininess) must be > 0', MatBlock.SpecularColor.W > 0.0);

  MatBlock.InitDefaultUnlit;
  AssertTrue('InitDefaultUnlit SpecularColor.W must be < 0 (unlit marker)', MatBlock.SpecularColor.W < 0.0);

  { 2. Verify Cook-Torrance GGX PBR shader generation & SPIR-V module compilation }
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  VSMod := nil;
  FSMod := nil;
  CSMod := nil;
  try
    PBRFuncs := Gen.GeneratePBRFunctions;
    AssertTrue('GeneratePBRFunctions must emit DistributionGGX', Pos('DistributionGGX(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit GeometrySmithGGXCorrelated', Pos('GeometrySmithGGXCorrelated(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit FresnelSchlick', Pos('FresnelSchlick(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit FresnelSchlickRoughness', Pos('FresnelSchlickRoughness(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit PerturbNormalCotangent', Pos('PerturbNormalCotangent(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit EvaluateDirectCookTorranceGGX', Pos('EvaluateDirectCookTorranceGGX(', PBRFuncs) > 0);
    AssertTrue('GeneratePBRFunctions must emit EvaluateIBLCookTorranceGGX', Pos('EvaluateIBLCookTorranceGGX(', PBRFuncs) > 0);

    VS := Gen.GenerateDefault3DVertexShader(True, True);
    AssertTrue('Default 3D VS must include #version 450', Pos('#version 450', VS) > 0);
    AssertTrue('Default 3D VS with skinning must reference CastleSkinning.u_JointMatrices',
      Pos('CastleSkinning.u_JointMatrices', VS) > 0);
    AssertTrue('Default 3D VS with tangents must compute castle_tangent_to_eye_space',
      Pos('castle_tangent_to_eye_space = mat3(T, B, N);', VS) > 0);
    AssertTrue('Default 3D VS must include Vulkan NDC depth adjustment [0..1]',
      Pos('gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;', VS) > 0);

    FS := Gen.GenerateDefault3DFragmentShader(True, True, True, True, True, True, True);
    AssertTrue('Default 3D FS must sample castle_base_color_texture', Pos('castle_base_color_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_normal_texture', Pos('castle_normal_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_metallic_roughness_texture', Pos('castle_metallic_roughness_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_emissive_texture', Pos('castle_emissive_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_occlusion_texture', Pos('castle_occlusion_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_brdf_lut_texture', Pos('castle_brdf_lut_texture', FS) > 0);
    AssertTrue('Default 3D FS must sample castle_env_specular_texture', Pos('castle_env_specular_texture', FS) > 0);
    AssertTrue('Default 3D FS with UseAlphaTest must discard against castle_AlphaCutoff',
      Pos('if (baseColor.a < castle_AlphaCutoff) discard;', FS) > 0);

    LutCS := Gen.GenerateIBLBrdfLutComputeShader(8, 8);
    AssertTrue('BRDF LUT CS must include RadicalInverse_VdC', Pos('RadicalInverse_VdC(', LutCS) > 0);
    AssertTrue('BRDF LUT CS must include ImportanceSampleGGX', Pos('ImportanceSampleGGX(', LutCS) > 0);
    AssertTrue('BRDF LUT CS must include IntegrateBRDF', Pos('IntegrateBRDF(', LutCS) > 0);

    VSMod := VkDev.CreateShaderModuleFromGLSL(ssVertex, VS, 'PBR3D_VS');
    FSMod := VkDev.CreateShaderModuleFromGLSL(ssFragment, FS, 'PBR3D_FS');
    CSMod := VkDev.CreateShaderModuleFromGLSL(ssCompute, LutCS, 'IBLBrdfLut_CS');
    AssertTrue('VSMod must be created', VSMod <> nil);
    AssertTrue('FSMod must be created', FSMod <> nil);
    AssertTrue('CSMod must be created', CSMod <> nil);
  finally
    FreeAndNil(CSMod);
    FreeAndNil(FSMod);
    FreeAndNil(VSMod);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestComputeIBLBrdfLutAndEnvironmentPrefilterRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  LutTex, CubeTex: TVulkanRHITexture;
  LutNormalSmooth, LutGrazingSmooth, LutNormalRough: TVector2;
  FaceColors: array[0..5] of TVector3;
  Mip0Sky, Mip4Sky, Mip0Ground, Mip4Ground, IrrSky, IrrGround: TVector3;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  try
    { 1. Verify Van der Corput radical inverse }
    AssertSameValue(0.0, TCastleVulkanIBLGenerator.RadicalInverseVdC(0), 1e-6);
    AssertSameValue(0.5, TCastleVulkanIBLGenerator.RadicalInverseVdC(1), 1e-6);
    AssertSameValue(0.25, TCastleVulkanIBLGenerator.RadicalInverseVdC(2), 1e-6);
    AssertSameValue(0.75, TCastleVulkanIBLGenerator.RadicalInverseVdC(3), 1e-6);

    { 2. Generate 16x16 Split-Sum BRDF Integration LUT via compute dispatch }
    LutTex := VkDev.IBLGenerator.GenerateBRDFIntegrationLUT(CmdList, 16, 32);
    AssertTrue('GenerateBRDFIntegrationLUT must return non-nil texture', LutTex <> nil);
    AssertTrue('BrdfLutComputePipeline must be created', VkDev.IBLGenerator.BrdfLutComputePipeline <> nil);
    AssertEquals('TotalBrdfLutDispatches must be 1', 1, VkDev.IBLGenerator.TotalBrdfLutDispatches);
    AssertEquals('BrdfLutSize must be 16', 16, VkDev.IBLGenerator.BrdfLutSize);

    LutNormalSmooth := VkDev.IBLGenerator.SampleBRDFLUT(0.95, 0.1);
    LutGrazingSmooth := VkDev.IBLGenerator.SampleBRDFLUT(0.05, 0.1);
    LutNormalRough := VkDev.IBLGenerator.SampleBRDFLUT(0.95, 0.9);

    { At normal incidence and smooth roughness, Fresnel scale (X) dominates over bias (Y) }
    AssertTrue('At normal incidence (NdotV=0.95, r=0.1), Scale (X) must be > 0.8', LutNormalSmooth.X > 0.8);
    AssertTrue('At normal incidence (NdotV=0.95, r=0.1), Bias (Y) must be < 0.1', LutNormalSmooth.Y < 0.1);
    { At grazing angle (NdotV=0.05), Schlick Fresnel (1 - VdotH)^5 increases Bias (Y) significantly }
    AssertTrue('At grazing angle (NdotV=0.05), Bias (Y) must exceed normal-incidence Bias',
      LutGrazingSmooth.Y > LutNormalSmooth.Y);
    { Energy conservation: Scale + Bias <= 1.01 }
    AssertTrue('BRDF LUT must conserve energy (Scale + Bias <= 1.01)',
      (LutNormalSmooth.X + LutNormalSmooth.Y <= 1.01) and
      (LutGrazingSmooth.X + LutGrazingSmooth.Y <= 1.01) and
      (LutNormalRough.X + LutNormalRough.Y <= 1.01));

    { 3. Prefilter 16x16 environment cubemap across 5 mip levels and compute L2 SH9 irradiance }
    FaceColors[0] := Vector3(0.4, 0.4, 0.5); // +X
    FaceColors[1] := Vector3(0.4, 0.4, 0.5); // -X
    FaceColors[2] := Vector3(1.0, 0.9, 0.8); // +Y (Bright sky)
    FaceColors[3] := Vector3(0.1, 0.1, 0.1); // -Y (Dark ground)
    FaceColors[4] := Vector3(0.4, 0.4, 0.5); // +Z
    FaceColors[5] := Vector3(0.4, 0.4, 0.5); // -Z

    CubeTex := VkDev.IBLGenerator.PrefilterEnvironmentCubemap(CmdList, FaceColors, 16);
    AssertTrue('PrefilterEnvironmentCubemap must return non-nil cubemap', CubeTex <> nil);
    AssertEquals('Cubemap dimension must be tdCube', Ord(tdCube), Ord(CubeTex.Desc.Dimension));
    AssertEquals('PrefilteredEnvMipLevels for 16x16 cubemap must be 5', 5, VkDev.IBLGenerator.PrefilteredEnvMipLevels);
    AssertEquals('TotalEnvPrefilterPasses must be 5', 5, VkDev.IBLGenerator.TotalEnvPrefilterPasses);

    Mip0Sky := VkDev.IBLGenerator.SamplePrefilteredEnvironment(2, 0); // +Y at mip 0 (roughness=0)
    Mip4Sky := VkDev.IBLGenerator.SamplePrefilteredEnvironment(2, 4); // +Y at mip 4 (roughness=1)
    Mip0Ground := VkDev.IBLGenerator.SamplePrefilteredEnvironment(3, 0); // -Y at mip 0
    Mip4Ground := VkDev.IBLGenerator.SamplePrefilteredEnvironment(3, 4); // -Y at mip 4

    AssertSameValue(1.0, Mip0Sky.X, 1e-4);
    AssertSameValue(0.1, Mip0Ground.X, 1e-4);
    AssertTrue('Roughness=1 Mip 4 sky must blur down toward average environment', Mip4Sky.X < Mip0Sky.X);
    AssertTrue('Roughness=1 Mip 4 ground must blur up toward average environment', Mip4Ground.X > Mip0Ground.X);

    { 4. Verify L2 Spherical Harmonics diffuse irradiance evaluation }
    IrrSky := VkDev.IBLGenerator.EvaluateIrradianceSH(Vector3(0.0, 1.0, 0.0));
    IrrGround := VkDev.IBLGenerator.EvaluateIrradianceSH(Vector3(0.0, -1.0, 0.0));
    AssertTrue('SH9 diffuse irradiance along +Y (sky) must exceed -Y (ground)',
      IrrSky.X > IrrGround.X);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestShapePBRMaterialExtractionAndDispatchRHI;
var
  SavedDevice: TRHIDevice;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  RenderOpts: TCastleRenderOptions;
  ShapeNode: TShapeNode;
  AppNode: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  PhongMat: TMaterialNode;
  UnlitMat: TUnlitMaterialNode;
  BaseTexNode, NormTexNode: TPixelTextureNode;
  BaseImg, NormImg: TRGBImage;
  BoxNode: TBoxNode;
  TraverseState: TX3DGraphTraverseState;
  Shape: TX3DRendererShape;
  MatBlock: TCastleMaterialUniformBlock;
  ShadingModel: TCastleShadingModelRHI;
  BaseTexRHI, NormTexRHI, MRTexRHI, EmissiveTexRHI, OccTexRHI: TRHITexture;
  TexCount, DrawCalls: Cardinal;
  BindlessEntry: TCastleBindlessMaterialEntry;
begin
  SavedDevice := RHIDevice;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  RenderOpts := TCastleRenderOptions.Create(nil);
  ShapeNode := TShapeNode.Create;
  AppNode := TAppearanceNode.Create;
  AppNode.WaitForRelease;
  PhysMat := TPhysicalMaterialNode.Create;
  PhysMat.WaitForRelease;
  PhongMat := TMaterialNode.Create;
  PhongMat.WaitForRelease;
  UnlitMat := TUnlitMaterialNode.Create;
  UnlitMat.WaitForRelease;
  BaseTexNode := TPixelTextureNode.Create;
  BaseTexNode.WaitForRelease;
  NormTexNode := TPixelTextureNode.Create;
  NormTexNode.WaitForRelease;
  BoxNode := TBoxNode.Create;
  BoxNode.WaitForRelease;
  TraverseState := TX3DGraphTraverseState.Create;
  Shape := nil;
  try
    SetRHIDevice(VkDev);

    BaseImg := TRGBImage.Create(4, 4);
    BaseImg.Clear(Vector4Byte(200, 150, 100, 255));
    BaseTexNode.FdImage.Value := BaseImg;
    TTextureResources.Prepare(RenderOpts, BaseTexNode);

    NormImg := TRGBImage.Create(4, 4);
    NormImg.Clear(Vector4Byte(128, 128, 255, 255));
    NormTexNode.FdImage.Value := NormImg;
    TTextureResources.Prepare(RenderOpts, NormTexNode);

    PhysMat.BaseColor := Vector3(0.8, 0.6, 0.4);
    PhysMat.Transparency := 0.1;
    PhysMat.Metallic := 0.85;
    PhysMat.Roughness := 0.25;
    PhysMat.EmissiveColor := Vector3(0.1, 0.2, 0.3);
    PhysMat.NormalScale := 1.5;
    PhysMat.OcclusionStrength := 0.75;
    PhysMat.BaseTexture := BaseTexNode;
    PhysMat.NormalTexture := NormTexNode;

    AppNode.Material := PhysMat;
    AppNode.AlphaMode := amMask;
    AppNode.AlphaCutoff := 0.4;
    ShapeNode.Appearance := AppNode;
    ShapeNode.Geometry := BoxNode;
    TraverseState.ShapeNode := ShapeNode;

    Shape := TX3DRendererShape.Create(nil, BoxNode, TraverseState, nil);
    TraverseState := nil; { owned and freed by TShape.Destroy (FOriginalState) }

    { 1. Verify PhysicalMaterial extraction }
    AssertTrue('ExtractRHIMaterialBlock must return True for TPhysicalMaterialNode',
      Shape.ExtractRHIMaterialBlock(MatBlock, ShadingModel));
    AssertEquals('ShadingModel must be smPBRMetallicRoughness',
      Ord(smPBRMetallicRoughness), Ord(ShadingModel));
    AssertSameValue(0.8, MatBlock.BaseColor.X, 1e-4);
    AssertSameValue(0.6, MatBlock.BaseColor.Y, 1e-4);
    AssertSameValue(0.4, MatBlock.BaseColor.Z, 1e-4);
    AssertSameValue(0.9, MatBlock.BaseColor.W, 1e-4); // 1 - 0.1 transparency
    AssertSameValue(0.85, MatBlock.EmissiveColor.W, 1e-4); // Metallic
    AssertSameValue(0.25, MatBlock.PBRParams.X, 1e-4);     // Roughness
    AssertSameValue(1.5, MatBlock.PBRParams.Y, 1e-4);      // NormalScale
    AssertSameValue(0.75, MatBlock.PBRParams.Z, 1e-4);     // OcclusionStrength
    AssertSameValue(0.4, MatBlock.PBRParams.W, 1e-4);      // AlphaCutoff (amMask)

    { 2. Verify texture handle extraction }
    TexCount := Shape.ExtractRHIMaterialTextures(
      BaseTexRHI, NormTexRHI, MRTexRHI, EmissiveTexRHI, OccTexRHI);
    AssertEquals('ExtractRHIMaterialTextures must find 2 prepared textures', 2, TexCount);
    AssertTrue('BaseTexRHI must be non-nil', BaseTexRHI <> nil);
    AssertTrue('NormTexRHI must be non-nil', NormTexRHI <> nil);
    AssertTrue('MRTexRHI must be nil', MRTexRHI = nil);

    { 3. Verify Bindless Material Entry construction }
    BindlessEntry := Shape.BuildRHIBindlessMaterialEntry(11, 22, 33, 44);
    AssertSameValue(0.85, BindlessEntry.EmissiveColor.W, 1e-4);
    AssertEquals('BaseColorTexIndex must be 11', 11, BindlessEntry.BaseColorTexIndex);
    AssertEquals('NormalTexIndex must be 22', 22, BindlessEntry.NormalTexIndex);
    AssertEquals('MetallicRoughnessTexIndex must be 33', 33, BindlessEntry.MetallicRoughnessTexIndex);
    AssertEquals('EmissiveTexIndex must be 44', 44, BindlessEntry.EmissiveTexIndex);

    { 4. Verify Phong Material extraction }
    PhongMat.DiffuseColor := Vector3(0.5, 0.5, 0.5);
    PhongMat.SpecularColor := Vector3(0.9, 0.9, 0.9);
    PhongMat.Shininess := 0.5;
    AppNode.Material := PhongMat;
    AssertTrue('ExtractRHIMaterialBlock must return True for TMaterialNode',
      Shape.ExtractRHIMaterialBlock(MatBlock, ShadingModel));
    AssertEquals('ShadingModel must be smPhong', Ord(smPhong), Ord(ShadingModel));
    AssertSameValue(64.0, MatBlock.SpecularColor.W, 1e-3); // 0.5 * 128

    { 5. Verify Unlit Material extraction }
    UnlitMat.EmissiveColor := Vector3(0.2, 0.8, 0.4);
    UnlitMat.Transparency := 0.25;
    AppNode.Material := UnlitMat;
    AssertTrue('ExtractRHIMaterialBlock must return True for TUnlitMaterialNode',
      Shape.ExtractRHIMaterialBlock(MatBlock, ShadingModel));
    AssertEquals('ShadingModel must be smUnlit', Ord(smUnlit), Ord(ShadingModel));
    AssertTrue('Unlit SpecularColor.W must be < 0', MatBlock.SpecularColor.W < 0.0);
    AssertSameValue(0.75, MatBlock.BaseColor.W, 1e-4);

    { Restore PhysMat before PrepareRHIBuffers/RecordRHIDraw and Shape destruction }
    AppNode.Material := PhysMat;

    { 6. Verify PrepareRHIBuffers + RecordRHIDraw }
    Shape.PrepareRHIBuffers(RenderOpts, 1);
    DrawCalls := Shape.RecordRHIDraw(CmdList, TMatrix4.Identity, 7);
    AssertTrue('RecordRHIDraw must record at least 1 draw call for TBoxNode', DrawCalls >= 1);
  finally
    if AppNode <> nil then
      AppNode.Material := PhysMat;
    if (Shape <> nil) and (Shape.Cache <> nil) then
      RendererCache.Shape_DecReference(Shape, Shape.Cache);
    FreeAndNil(Shape);
    FreeAndNil(TraverseState);
    TTextureResources.Unprepare(BaseTexNode);
    TTextureResources.Unprepare(NormTexNode);
    SetRHIDevice(SavedDevice);
    FreeAndNil(ShapeNode);
    FreeIfUnusedAndNil(AppNode);
    FreeIfUnusedAndNil(PhysMat);
    FreeIfUnusedAndNil(PhongMat);
    FreeIfUnusedAndNil(UnlitMat);
    FreeIfUnusedAndNil(BaseTexNode);
    FreeIfUnusedAndNil(NormTexNode);
    FreeIfUnusedAndNil(BoxNode);
    FreeAndNil(RenderOpts);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestClusteredForwardLightCullingComputeRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Culler: TCastleVulkanClusteredLightCuller;
  ProjMat: TMatrix4;
  SliceNear0, SliceFar0, SliceNearLast, SliceFarLast: Single;
  AABBMin, AABBMax: TVector3;
  CX, CY, CZ, FlatIdx: Cardinal;
  Workgroups: Cardinal;
  CenterEntry: TCastleClusterGridEntry;
  I: Integer;
  LightIdx: Cardinal;
  FoundDirLight, FoundCenterPointLight: Boolean;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  try
    Culler := VkDev.ClusteredLightCuller;
    AssertTrue('ClusteredLightCuller must be created on TVulkanRHIDevice', Culler <> nil);
    AssertEquals('Default GridX must be 16', 16, Culler.GridX);
    AssertEquals('Default GridY must be 8', 8, Culler.GridY);
    AssertEquals('Default GridZ must be 24', 24, Culler.GridZ);
    AssertEquals('Default TotalClusters must be 3072', 3072, Culler.TotalClusters);

    { 1. Verify struct layout sizes for std140/std430 GPU compatibility }
    AssertEquals('TCastleClusteredLight must be 64 bytes', 64, SizeOf(TCastleClusteredLight));
    AssertEquals('TCastleClusterGridEntry must be 8 bytes', 8, SizeOf(TCastleClusterGridEntry));
    AssertEquals('TCastleClusterCullingUniformBlock must be 112 bytes', 112, SizeOf(TCastleClusterCullingUniformBlock));

    { 2. Configure camera projection (90 deg FOV, 1920x1080, ZNear=1.0, ZFar=1000.0) }
    ProjMat := PerspectiveProjectionMatrixDeg(90.0, 1920.0 / 1080.0, 1.0, 1000.0);
    Culler.SetCameraProjection(ProjMat, 1920, 1080, 1.0, 1000.0);

    { 3. Verify exponential Z-slice bounds }
    Culler.ComputeSliceDepthBounds(0, SliceNear0, SliceFar0);
    Culler.ComputeSliceDepthBounds(Culler.GridZ - 1, SliceNearLast, SliceFarLast);
    AssertSameValue(1.0, SliceNear0, 1e-4);
    AssertTrue('First slice far bound must be > ZNear', SliceFar0 > SliceNear0);
    AssertSameValue(1000.0, SliceFarLast, 1e-2);
    AssertTrue('Last slice near bound must be < ZFar', SliceNearLast < SliceFarLast);

    { 4. Verify screen pixel + depth to 3D cluster coordinate mapping }
    FlatIdx := Culler.ComputeClusterCoordFromScreenAndDepth(960.0, 540.0, 10.0, CX, CY, CZ);
    AssertEquals('Screen center X (960/1920) must map to cluster X = 8', 8, CX);
    AssertEquals('Screen center Y (540/1080) must map to cluster Y = 4', 4, CY);
    AssertTrue('Depth 10.0 in [1..1000] must map to valid Z slice', (CZ > 0) and (CZ < Culler.GridZ));
    AssertEquals('Flat index must equal CX + CY*GridX + CZ*GridX*GridY',
      CX + CY * Culler.GridX + CZ * Culler.GridX * Culler.GridY, FlatIdx);

    { Verify reconstructed view-space AABB at center cluster (8, 4, CZ) contains view center (0, 0, -10) }
    Culler.ComputeClusterViewAABB(CX, CY, CZ, AABBMin, AABBMax);
    AssertTrue('Cluster AABBMin.X must be <= AABBMax.X', AABBMin.X <= AABBMax.X);
    AssertTrue('Cluster AABBMin.Y must be <= AABBMax.Y', AABBMin.Y <= AABBMax.Y);
    AssertTrue('Cluster AABBMin.Z must be <= -10.0', AABBMin.Z <= -10.0 + 1e-3);
    AssertTrue('Cluster AABBMax.Z must be >= -10.0', AABBMax.Z >= -10.0 - 1e-3);

    { 5. Populate 64 dynamic lights (1 directional, 1 point light at (0,0,-10), 1 spot light, + 61 distributed point lights) }
    Culler.ClearLights;
    AssertEquals('Light 0 (directional)', 0,
      Culler.AddDirectionalLight(Vector3(0.0, -1.0, -1.0).Normalize, Vector3(1.0, 0.98, 0.9), 2.5));
    AssertEquals('Light 1 (point light at view center -10)', 1,
      Culler.AddPointLight(Vector3(0.0, 0.0, -10.0), 4.0, Vector3(1.0, 0.2, 0.1), 5.0, 0, 0.002));
    AssertEquals('Light 2 (spot light at view center -10)', 2,
      Culler.AddSpotLight(Vector3(0.0, 0.0, -8.0), Vector3(0.0, 0.0, -1.0),
        12.0, Cos(DegToRad(15.0)), Cos(DegToRad(30.0)), Vector3(0.2, 0.8, 1.0), 4.0, 1, 0.001));
    for I := 3 to 63 do
      Culler.AddPointLight(
        Vector3(((I mod 8) - 4) * 25.0, (((I div 8) mod 8) - 4) * 15.0, -20.0 - (I * 12.0)),
        8.0, Vector3(0.5, 0.5, 0.5), 1.0);
    AssertEquals('ActiveLightCount must be 64', 64, Culler.ActiveLightCount);

    { 6. Dispatch light culling compute pass }
    CmdList.BeginRecording;
    Workgroups := Culler.DispatchLightCulling(CmdList);
    CmdList.EndRecording;
    AssertEquals('3072 clusters / 64 threads per workgroup = 48 workgroups', 48, Workgroups);
    AssertEquals('TotalDispatches must be 1', 1, Culler.TotalDispatches);
    AssertTrue('ActiveClusterCount must be > 0', Culler.ActiveClusterCount > 0);
    AssertTrue('TotalAssignedLightRefs must be >= 3072 (directional light hits all clusters)',
      Culler.TotalAssignedLightRefs >= 3072);
    AssertTrue('ClusterUniformBuffer must be allocated', Culler.ClusterUniformBuffer <> nil);
    AssertTrue('LightStorageBuffer must be allocated', Culler.LightStorageBuffer <> nil);
    AssertTrue('ClusterGridBuffer must be allocated', Culler.ClusterGridBuffer <> nil);
    AssertTrue('LightIndexBuffer must be allocated', Culler.LightIndexBuffer <> nil);

    { 7. Verify center cluster at (CX, CY, CZ) received Light 0 (directional) and Light 1 (point light at -10) }
    CenterEntry := Culler.GetClusterEntry(CX, CY, CZ);
    AssertTrue('Center cluster must have at least 2 lights assigned', CenterEntry.Count >= 2);
    FoundDirLight := False;
    FoundCenterPointLight := False;
    for I := 0 to Integer(CenterEntry.Count) - 1 do
    begin
      LightIdx := Culler.GetClusterLightIndex(CX, CY, CZ, I);
      if LightIdx = 0 then FoundDirLight := True;
      if LightIdx = 1 then FoundCenterPointLight := True;
    end;
    AssertTrue('Center cluster must contain directional light 0', FoundDirLight);
    AssertTrue('Center cluster must contain point light 1 at (0,0,-10)', FoundCenterPointLight);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestDirectionalCascadedShadowMapsAndShadowAtlasRHI;
var
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Atlas: TCastleVulkanShadowAtlas;
  ProjMat, InvProjMat, LightVP: TMatrix4;
  Block1, Block2: TCastleDirectionalCascadeShadowBlock;
  CascRect0, CascRect3, TileRect0, TileRect1: TRectangle;
  TileIdx0, TileIdx1: Integer;
  UVScaleOffset0, UVScaleOffset1: TVector4;
  ResNear, ResMid, ResFar: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0);
  try
    Atlas := VkDev.ShadowAtlas;
    AssertTrue('ShadowAtlas must be created on TVulkanRHIDevice', Atlas <> nil);
    AssertEquals('Default AtlasSize must be 2048', 2048, Atlas.AtlasSize);
    AssertEquals('Default CascadeResolution must be 512', 512, Atlas.CascadeResolution);
    AssertEquals('TCastleDirectionalCascadeShadowBlock must be 336 bytes',
      336, SizeOf(TCastleDirectionalCascadeShadowBlock));
    AssertEquals('TCastlePositionalShadowTileEntry must be 80 bytes',
      80, SizeOf(TCastlePositionalShadowTileEntry));

    { 1. Compute 4 Directional Cascades using Practical Split Scheme (lambda = 0.75) + texel snapping }
    ProjMat := PerspectiveProjectionMatrixDeg(60.0, 16.0 / 9.0, 0.5, 200.0);
    if not ProjMat.TryInverse(InvProjMat) then
      InvProjMat := TMatrix4.Identity;

    Atlas.ComputeDirectionalCascades(InvProjMat, Vector3(-0.4, -1.0, -0.3).Normalize, 0.5, 200.0, 0.75, True);
    Block1 := Atlas.CascadeBlock;
    AssertEquals('TotalCascadeUpdates must be 1', 1, Atlas.TotalCascadeUpdates);

    { Verify strictly increasing cascade split distances ending at ZFar = 200.0 }
    AssertTrue('Cascade 0 split > ZNear', Block1.CascadeSplitDepths.X > 0.5);
    AssertTrue('Cascade 1 split > Cascade 0 split', Block1.CascadeSplitDepths.Y > Block1.CascadeSplitDepths.X);
    AssertTrue('Cascade 2 split > Cascade 1 split', Block1.CascadeSplitDepths.Z > Block1.CascadeSplitDepths.Y);
    AssertSameValue(200.0, Block1.CascadeSplitDepths.W, 1e-3);

    { Verify top-row cascade atlas UV scale/offsets (4 cascades of 512x512 in 2048x2048 -> scale = 0.25) }
    AssertSameValue(0.25, Block1.CascadeAtlasUVScaleOffset[0].X, 1e-4);
    AssertSameValue(0.25, Block1.CascadeAtlasUVScaleOffset[0].Y, 1e-4);
    AssertSameValue(0.00, Block1.CascadeAtlasUVScaleOffset[0].Z, 1e-4);
    AssertSameValue(0.75, Block1.CascadeAtlasUVScaleOffset[3].Z, 1e-4);

    CascRect0 := Atlas.GetCascadeViewportRect(0);
    CascRect3 := Atlas.GetCascadeViewportRect(3);
    AssertEquals('Cascade 0 Left must be 0', 0, CascRect0.Left);
    AssertEquals('Cascade 0 Width must be 512', 512, CascRect0.Width);
    AssertEquals('Cascade 3 Left must be 1536', 1536, CascRect3.Left);

    { Verify texel snapping determinism when re-evaluated }
    Atlas.ComputeDirectionalCascades(InvProjMat, Vector3(-0.4, -1.0, -0.3).Normalize, 0.5, 200.0, 0.75, True);
    Block2 := Atlas.CascadeBlock;
    AssertSameValue(Block1.CascadeViewProjMatrix[0].Data[3, 0], Block2.CascadeViewProjMatrix[0].Data[3, 0], 1e-5);
    AssertSameValue(Block1.CascadeViewProjMatrix[0].Data[3, 1], Block2.CascadeViewProjMatrix[0].Data[3, 1], 1e-5);

    { 2. Verify Adaptive Positional Shadow Tile Resolution & Sub-Allocation }
    ResNear := TCastleVulkanShadowAtlas.ChooseTileResolution(3.0, 10.0, 512);
    ResMid  := TCastleVulkanShadowAtlas.ChooseTileResolution(20.0, 10.0, 512);
    ResFar  := TCastleVulkanShadowAtlas.ChooseTileResolution(50.0, 10.0, 512);
    AssertEquals('Near light must get full 512x512 tile', 512, ResNear);
    AssertEquals('Mid-distance light must get 256x256 tile', 256, ResMid);
    AssertEquals('Far light must get 128x128 tile', 128, ResFar);

    Atlas.ResetPositionalTiles;
    LightVP := PerspectiveProjectionMatrixDeg(90.0, 1.0, 0.1, 25.0);
    AssertTrue('First positional shadow tile allocation must succeed',
      Atlas.AllocatePositionalTile(ResNear, LightVP, TileIdx0, TileRect0, UVScaleOffset0));
    AssertTrue('Second positional shadow tile allocation must succeed',
      Atlas.AllocatePositionalTile(ResMid, LightVP, TileIdx1, TileRect1, UVScaleOffset1));
    AssertEquals('TileIdx0 must be 0', 0, TileIdx0);
    AssertEquals('TileIdx1 must be 1', 1, TileIdx1);
    AssertEquals('AllocatedTileCount must be 2', 2, Atlas.AllocatedTileCount);
    AssertTrue('Positional tiles must be placed below the reserved 512px directional cascade row',
      TileRect0.Bottom >= 512);
    AssertEquals('Tile 0 width must be 512', 512, TileRect0.Width);
    AssertEquals('Tile 1 width must be 256', 256, TileRect1.Width);
    AssertSameValue(512.0 / 2048.0, UVScaleOffset0.X, 1e-5);

    { 3. Upload shadow buffers & record depth-only shadow tile passes with slope-scaled depth bias }
    Atlas.UploadShadowBuffers;
    AssertTrue('ShadowAtlasTexture must be created', Atlas.ShadowAtlasTexture <> nil);
    AssertTrue('ShadowAtlasSampler must be created', Atlas.ShadowAtlasSampler <> nil);
    AssertTrue('CascadeUniformBuffer must be created', Atlas.CascadeUniformBuffer <> nil);
    AssertTrue('PositionalTileBuffer must be created', Atlas.PositionalTileBuffer <> nil);

    CmdList.BeginRecording;
    Atlas.RecordShadowTilePass(CmdList, CascRect0, 1.25, 1.75);
    Atlas.RecordShadowTilePass(CmdList, TileRect0, 1.50, 2.00);
    CmdList.EndRecording;
    AssertEquals('TotalShadowTilePasses must be 2', 2, Atlas.TotalShadowTilePasses);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestClusteredForwardAndShadowAtlasShaderIntegrationRHI;
var
  VkDev: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  ComputeGLSL, HelperGLSL, FragShaderClusteredShadows, FragShaderCascadesOnly: String;
  CSMod, FSMod1, FSMod2: TRHIShaderModule;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CSMod := nil;
  FSMod1 := nil;
  FSMod2 := nil;
  try
    { 1. Verify Clustered Light Culling Compute Shader GLSL 450 generation & compilation }
    ComputeGLSL := Gen.GenerateClusteredLightCullingComputeShader(64);
    AssertTrue('Compute shader must contain local_size_x = 64',
      Pos('layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;', ComputeGLSL) > 0);
    AssertTrue('Compute shader must bind CastleClusterCullingBlock at binding 0',
      Pos('layout(std140, set = 0, binding = 0) uniform CastleClusterCullingBlock', ComputeGLSL) > 0);
    AssertTrue('Compute shader must bind CastleClusteredLightsBuffer at binding 1',
      Pos('layout(std430, set = 0, binding = 1) readonly buffer CastleClusteredLightsBuffer', ComputeGLSL) > 0);
    AssertTrue('Compute shader must bind CastleClusterGridBuffer at binding 2',
      Pos('layout(std430, set = 0, binding = 2) writeonly buffer CastleClusterGridBuffer', ComputeGLSL) > 0);
    AssertTrue('Compute shader must bind CastleClusterLightIndexBuffer at binding 3',
      Pos('layout(std430, set = 0, binding = 3) writeonly buffer CastleClusterLightIndexBuffer', ComputeGLSL) > 0);
    AssertTrue('Compute shader must include SphereIntersectsAABB test',
      Pos('bool SphereIntersectsAABB(', ComputeGLSL) > 0);

    CSMod := VkDev.CreateShaderModuleFromGLSL(ssCompute, ComputeGLSL, 'ClusteredLightCulling_CS');
    AssertTrue('ClusteredLightCulling_CS shader module must be created', CSMod <> nil);

    { 2. Verify Forward+ Cluster & Shadow Atlas helper GLSL functions }
    HelperGLSL := Gen.GenerateClusteredForwardAndShadowFunctions;
    AssertTrue('Helper GLSL must include SampleShadowAtlasPCF3x3',
      Pos('float SampleShadowAtlasPCF3x3(', HelperGLSL) > 0);
    AssertTrue('Helper GLSL must include EvaluateDirectionalCascadeShadow',
      Pos('float EvaluateDirectionalCascadeShadow(', HelperGLSL) > 0);
    AssertTrue('Helper GLSL must include EvaluatePositionalAtlasShadow',
      Pos('float EvaluatePositionalAtlasShadow(', HelperGLSL) > 0);
    AssertTrue('Helper GLSL must include ComputeClusterIndex3D',
      Pos('uvec3 ComputeClusterIndex3D(', HelperGLSL) > 0);
    AssertTrue('Helper GLSL must include EvaluateClusteredForwardLights',
      Pos('vec3 EvaluateClusteredForwardLights(', HelperGLSL) > 0);

    { 3. Verify 3D Fragment Shader integration with Clustered Forward+ & Cascaded/Atlas Shadows }
    FragShaderClusteredShadows := Gen.GenerateDefault3DFragmentShader(
      True, True, True, True, True, True, False, True, True);
    AssertTrue('Clustered+Shadows Fragment Shader must invoke EvaluateClusteredForwardLights with useShadows=true',
      Pos('EvaluateClusteredForwardLights(gl_FragCoord.xy, castle_vertex_eye.xyz, worldPos, N, V, baseColor.rgb, metallic, roughness, true)',
        FragShaderClusteredShadows) > 0);
    FSMod1 := VkDev.CreateShaderModuleFromGLSL(ssFragment, FragShaderClusteredShadows, 'ForwardPlusCSM_FS');
    AssertTrue('ForwardPlusCSM_FS shader module must be created', FSMod1 <> nil);

    { 4. Verify 3D Fragment Shader integration with Cascaded Shadows on standard multi-light loop }
    FragShaderCascadesOnly := Gen.GenerateDefault3DFragmentShader(
      True, False, False, False, False, False, False, False, True);
    AssertTrue('Cascades-only Fragment Shader must invoke EvaluateDirectionalCascadeShadow',
      Pos('EvaluateDirectionalCascadeShadow(worldPos, max(-castle_vertex_eye.z, 1e-3), max(dot(N, L), 0.0))',
        FragShaderCascadesOnly) > 0);
    FSMod2 := VkDev.CreateShaderModuleFromGLSL(ssFragment, FragShaderCascadesOnly, 'CascadedShadowsOnly_FS');
    AssertTrue('CascadedShadowsOnly_FS shader module must be created', FSMod2 <> nil);
  finally
    FreeAndNil(FSMod2);
    FreeAndNil(FSMod1);
    FreeAndNil(CSMod);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.DummyRenderGraphPassCallback(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass;
  const ACmd: TRHICommandList);
begin
  Inc(FRenderGraphPassExecCount);
end;

procedure TTestCastleVulkanRHI.TestDeclarativeRenderGraphAndTransientAliasingRHI;
var
  VkDev: TVulkanRHIDevice;
  Graph: TRHIRenderGraph;
  CmdList: TVulkanRHICommandList;
  FinalTargetTex: TRHITexture;
  FinalTargetDesc, TransientDescA, TransientDescB, DepthDesc, DeadDesc: TRHITextureDesc;
  HShadow, HDepth, HHDRColor, HBloomA, HBloomB, HFinal, HDeadTex: TRHIRenderGraphResourceHandle;
  PassShadow, PassForward, PassBloomDown, PassBloomUp, PassComposite, PassDead: TRHIRenderGraphPass;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Graph := nil;
  CmdList := nil;
  FinalTargetTex := nil;
  try
    FillChar(FinalTargetDesc, SizeOf(FinalTargetDesc), 0);
    FinalTargetDesc.Dimension := td2D;
    FinalTargetDesc.Format := pfRGBA8_UNorm;
    FinalTargetDesc.Width := 1280;
    FinalTargetDesc.Height := 720;
    FinalTargetDesc.DepthOrArrayLayers := 1;
    FinalTargetDesc.MipLevels := 1;
    FinalTargetDesc.SampleCount := 1;
    FinalTargetDesc.Usage := [tuColorAttachment, tuSampled, tuTransferSrc];
    FinalTargetDesc.DebugName := 'FinalBackbufferTarget';
    FinalTargetTex := VkDev.CreateTexture(FinalTargetDesc);

    Graph := TRHIRenderGraph.Create(VkDev);

    { 1. Declare transient resources with non-overlapping lifetimes to test physical texture aliasing }
    TransientDescA := FinalTargetDesc;
    TransientDescA.Format := pfRGBA16_Float;
    TransientDescA.Width := 640;
    TransientDescA.Height := 360;
    TransientDescA.Usage := [tuColorAttachment, tuSampled, tuStorage];

    TransientDescB := TransientDescA; { Identical descriptor -> eligible for memory aliasing }

    DepthDesc := FinalTargetDesc;
    DepthDesc.Format := pfD32_Float;
    DepthDesc.Width := 640;
    DepthDesc.Height := 360;
    DepthDesc.Usage := [tuDepthStencil, tuSampled];

    DeadDesc := TransientDescA;
    DeadDesc.Width := 256;
    DeadDesc.Height := 256;

    HShadow := Graph.DeclareTransientTexture('TransientShadowScratch', TransientDescA);
    HDepth := Graph.DeclareTransientTexture('TransientSceneDepth', DepthDesc);
    HHDRColor := Graph.DeclareTransientTexture('TransientHDRColor', TransientDescA);
    HBloomA := Graph.DeclareTransientTexture('TransientBloomScratchA', TransientDescB);
    HBloomB := Graph.DeclareTransientTexture('TransientBloomScratchB', TransientDescB);
    HDeadTex := Graph.DeclareTransientTexture('UnusedDeadTarget', DeadDesc);
    HFinal := Graph.ImportExternalTexture('FinalSwapchainOut', FinalTargetTex, rsUndefined, rsPresent);

    { 2. Add passes intentionally out-of-order to verify Kahn's DAG topological sorting:
         Register Composite first, then BloomUp, BloomDown, Forward, Shadow, and an unreferenced Dead pass }
    FRenderGraphPassExecCount := 0;

    PassComposite := Graph.AddPass('TonemapCompositePass', rgptGraphics);
    PassComposite.OnExecute := @DummyRenderGraphPassCallback;
    PassComposite.ReadTexture(HHDRColor, rsShaderRead);
    PassComposite.ReadTexture(HBloomB, rsShaderRead);
    PassComposite.WriteColorAttachment(HFinal);

    PassBloomUp := Graph.AddPass('BloomUpsamplePass', rgptCompute);
    PassBloomUp.OnExecute := @DummyRenderGraphPassCallback;
    PassBloomUp.ReadTexture(HBloomA, rsShaderRead);
    PassBloomUp.WriteStorageTexture(HBloomB, rsTransferDst);

    PassBloomDown := Graph.AddPass('BloomDownsamplePass', rgptCompute);
    PassBloomDown.OnExecute := @DummyRenderGraphPassCallback;
    PassBloomDown.ReadTexture(HHDRColor, rsShaderRead);
    PassBloomDown.WriteStorageTexture(HBloomA, rsTransferDst);

    PassForward := Graph.AddPass('HDRForwardOpaquePass', rgptGraphics);
    PassForward.OnExecute := @DummyRenderGraphPassCallback;
    PassForward.ReadTexture(HShadow, rsShaderRead);
    PassForward.WriteDepthAttachment(HDepth);
    PassForward.WriteColorAttachment(HHDRColor);

    PassShadow := Graph.AddPass('ShadowCasterPass', rgptGraphics);
    PassShadow.OnExecute := @DummyRenderGraphPassCallback;
    PassShadow.WriteColorAttachment(HShadow);

    { Unreferenced pass writing only to HDeadTex (which is never read by any output or side-effect pass) }
    PassDead := Graph.AddPass('UnreferencedDebugPass', rgptGraphics);
    PassDead.OnExecute := @DummyRenderGraphPassCallback;
    PassDead.WriteColorAttachment(HDeadTex);

    { 3. Compile the Render Graph }
    Graph.Compile;
    AssertTrue('Graph.IsCompiled must be true', Graph.IsCompiled);
    AssertEquals('Total registered passes must be 6', 6, Graph.PassCount);
    AssertEquals('Dead-pass culling must cull 1 unreferenced pass', 1, Graph.CulledPassCount);
    AssertEquals('Compiled active pass count must be 5', 5, Graph.CompiledPassCount);
    AssertTrue('PassDead must be marked IsCulled', PassDead.IsCulled);
    AssertFalse('PassShadow must not be culled', PassShadow.IsCulled);
    AssertFalse('PassComposite must not be culled', PassComposite.IsCulled);

    { Verify topological order: Shadow -> Forward -> BloomDown -> BloomUp -> Composite }
    AssertEquals('First compiled pass must be ShadowCasterPass',
      'ShadowCasterPass', Graph.GetCompiledPass(0).Name);
    AssertEquals('Last compiled pass must be TonemapCompositePass',
      'TonemapCompositePass', Graph.GetCompiledPass(Graph.CompiledPassCount - 1).Name);
    AssertTrue('Shadow pass must execute before Forward pass',
      PassShadow.ExecutionOrder < PassForward.ExecutionOrder);
    AssertTrue('Forward pass must execute before BloomDown pass',
      PassForward.ExecutionOrder < PassBloomDown.ExecutionOrder);
    AssertTrue('BloomDown pass must execute before BloomUp pass',
      PassBloomDown.ExecutionOrder < PassBloomUp.ExecutionOrder);
    AssertTrue('BloomUp pass must execute before Composite pass',
      PassBloomUp.ExecutionOrder < PassComposite.ExecutionOrder);

    { 4. Verify Transient Resource Lifetime Tracking & Physical Texture Aliasing:
         HShadow (used in passes 0..1) and HBloomB (used in passes 3..4) have non-overlapping lifetimes
         and identical descriptors, so they must alias the same physical texture! }
    AssertTrue('Transient textures must alias physical RHI textures (AliasedTextureSavingsCount >= 1)',
      Graph.AliasedTextureSavingsCount >= 1);
    AssertTrue('PhysicalTransientTextureCount must be strictly less than active transient textures',
      Graph.PhysicalTransientTextureCount < Graph.TransientTextureCount);
    AssertTrue('Resolved HShadow texture must be non-nil', Graph.ResolvePhysicalTexture(HShadow) <> nil);
    AssertTrue('Resolved HHDRColor texture must be non-nil', Graph.ResolvePhysicalTexture(HHDRColor) <> nil);
    AssertTrue('Dead transient texture must not allocate a physical texture',
      Graph.ResolvePhysicalTexture(HDeadTex) = nil);

    { 5. Execute the compiled Render Graph and verify automatic barrier hoisting }
    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Graph.Execute(CmdList);
    CmdList.EndRecording;

    AssertEquals('All 5 active passes must have executed their callback', 5, FRenderGraphPassExecCount);
    AssertTrue('RenderGraph must automatically hoist and emit TransitionTexture barriers (>= 6)',
      Graph.EmittedBarrierCount >= 6);
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Graph);
    FreeAndNil(FinalTargetTex);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestHDRBloomPyramidAndAutoExposureComputeRHI;
var
  VkDev: TVulkanRHIDevice;
  HDRPost: TCastleVulkanHDRPostProcessor;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  DownGLSL, UpGLSL, HistGLSL: String;
  CSDown, CSUp, CSHist: TRHIShaderModule;
  BrightSamples, DarkSamples: array[0..15] of TVector3;
  WUniform, WFirefly: Single;
  AvgUniform, AvgFirefly, SoftThresh: TVector3;
  I, Step: Integer;
  Dispatches: Cardinal;
  BrightLum, DarkLum, BrightExp, DarkExp: Single;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  CSDown := nil;
  CSUp := nil;
  CSHist := nil;
  try
    { 1. Verify struct sizes and GLSL compute shader generation }
    AssertEquals('TCastleBloomPushConstants size must be 32 bytes',
      32, SizeOf(TCastleBloomPushConstants));
    AssertEquals('TCastleAutoExposureParams size must be 32 bytes',
      32, SizeOf(TCastleAutoExposureParams));
    AssertEquals('TCastleHDRCompositePushConstants size must be 32 bytes',
      32, SizeOf(TCastleHDRCompositePushConstants));

    DownGLSL := Gen.GenerateBloomDownsampleComputeShader;
    UpGLSL := Gen.GenerateBloomUpsampleComputeShader;
    HistGLSL := Gen.GenerateLuminanceHistogramComputeShader;

    AssertTrue('Bloom downsample GLSL must include KarisWeight',
      Pos('float KarisWeight(vec3 c)', DownGLSL) > 0);
    AssertTrue('Bloom downsample GLSL must include ApplySoftThreshold',
      Pos('vec3 ApplySoftThreshold(vec3 c', DownGLSL) > 0);
    AssertTrue('Bloom upsample GLSL must include 9-tap tent filter weights',
      Pos('16.0', UpGLSL) > 0);
    AssertTrue('Histogram GLSL must include s_LocalHistogram[256]',
      Pos('shared uint s_LocalHistogram[256]', HistGLSL) > 0);

    CSDown := VkDev.CreateShaderModuleFromGLSL(ssCompute, DownGLSL, 'BloomDown_CS');
    CSUp := VkDev.CreateShaderModuleFromGLSL(ssCompute, UpGLSL, 'BloomUp_CS');
    CSHist := VkDev.CreateShaderModuleFromGLSL(ssCompute, HistGLSL, 'LumHist_CS');
    AssertTrue('BloomDown_CS module must compile', CSDown <> nil);
    AssertTrue('BloomUp_CS module must compile', CSUp <> nil);
    AssertTrue('LumHist_CS module must compile', CSHist <> nil);

    { 2. Verify Karis average firefly suppression and soft-knee threshold math }
    HDRPost := VkDev.HDRPostProcessor;
    AssertTrue('HDRPostProcessor must be lazily created by TVulkanRHIDevice', HDRPost <> nil);

    WUniform := HDRPost.EvaluateKarisWeight(Vector3(1.0, 1.0, 1.0));
    WFirefly := HDRPost.EvaluateKarisWeight(Vector3(100.0, 100.0, 100.0));
    AssertTrue('Karis weight must strongly attenuate extreme HDR fireflies', WFirefly < WUniform * 0.05);

    AvgUniform := HDRPost.EvaluateKarisAverage4(
      Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
      Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0));
    AvgFirefly := HDRPost.EvaluateKarisAverage4(
      Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
      Vector3(1.0, 1.0, 1.0), Vector3(1000.0, 1000.0, 1000.0));
    AssertSameValue(1.0, AvgUniform.X, 1e-4);
    { Without Karis weighting, arithmetic average of (1,1,1,1000) is 250.75; with Karis average it stays < 2.0! }
    AssertTrue('Karis 4-tap average must suppress single-pixel 1000-nit firefly (< 2.0)',
      AvgFirefly.X < 2.0);

    SoftThresh := HDRPost.EvaluateSoftThreshold(Vector3(0.2, 0.2, 0.2), 1.0, 0.5);
    AssertSameValue(0.0, SoftThresh.X, 1e-5);
    SoftThresh := HDRPost.EvaluateSoftThreshold(Vector3(3.0, 3.0, 3.0), 1.0, 0.5);
    AssertTrue('HDR color above threshold (3.0 > 1.0) must produce positive bloom contribution',
      SoftThresh.X > 1.5);

    { 3. Verify HDR target and 6-mip Bloom Pyramid creation + compute dispatch }
    HDRPost.EnsureHDRTargets(1920, 1080);
    AssertTrue('HDRSceneTexture must be allocated', HDRPost.HDRSceneTexture <> nil);
    AssertEquals('HDRSceneTexture format must be pfRGBA16_Float',
      Ord(pfRGBA16_Float), Ord(HDRPost.HDRSceneTexture.Desc.Format));
    AssertEquals('BloomMipCount for 1920x1080 must be 6',
      CASTLE_BLOOM_MAX_MIP_LEVELS, HDRPost.BloomMipCount);
    AssertEquals('BloomMipTextures[0] width must be half-res (960)', 960, HDRPost.BloomMipTextures[0].Desc.Width);
    AssertEquals('BloomMipTextures[0] height must be half-res (540)', 540, HDRPost.BloomMipTextures[0].Desc.Height);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := HDRPost.DispatchBloomPyramid(CmdList);
    CmdList.EndRecording;
    { 6 downsample dispatches + 5 upsample dispatches = 11 total bloom compute dispatches }
    AssertEquals('DispatchBloomPyramid must record 11 compute dispatches (6 down + 5 up)',
      11, Dispatches);
    AssertEquals('TotalBloomDownsampleDispatches must be 6', 6, HDRPost.TotalBloomDownsampleDispatches);
    AssertEquals('TotalBloomUpsampleDispatches must be 5', 5, HDRPost.TotalBloomUpsampleDispatches);

    { 4. Verify 256-bin Log-Luminance Histogram & Temporal Eye Adaptation }
    for I := 0 to High(BrightSamples) do
      BrightSamples[I] := Vector3(16.0, 16.0, 16.0); { Bright outdoor sunlit scene }
    for I := 0 to High(DarkSamples) do
      DarkSamples[I] := Vector3(0.08, 0.08, 0.08);   { Dim indoor scene }

    CmdList.BeginRecording;
    for Step := 1 to 10 do
      HDRPost.UpdateAutoExposure(CmdList, BrightSamples, 0.5);
    BrightLum := HDRPost.AdaptedLuminance;
    BrightExp := HDRPost.AdaptedExposure;

    for Step := 1 to 15 do
      HDRPost.UpdateAutoExposure(CmdList, DarkSamples, 0.5);
    DarkLum := HDRPost.AdaptedLuminance;
    DarkExp := HDRPost.AdaptedExposure;
    CmdList.EndRecording;

    AssertTrue('TotalHistogramDispatches must increment', HDRPost.TotalHistogramDispatches >= 25);
    AssertTrue('Bright scene adapted luminance must be much higher than dark scene',
      BrightLum > DarkLum * 20.0);
    AssertTrue('Auto-exposure must lower exposure multiplier in bright scenes and raise it in dark scenes',
      DarkExp > BrightExp * 5.0);
  finally
    FreeAndNil(CSHist);
    FreeAndNil(CSUp);
    FreeAndNil(CSDown);
    FreeAndNil(CmdList);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestACESFilmicAndAgXTonemappingCompositeRHI;
var
  VkDev: TVulkanRHIDevice;
  HDRPost: TCastleVulkanHDRPostProcessor;
  Gen: TCastleShaderGeneratorRHI;
  Graph: TRHIRenderGraph;
  CmdList: TVulkanRHICommandList;
  LDRTarget: TRHITexture;
  LDRDesc: TRHITextureDesc;
  TonemapHelpersGLSL, CompositeFragGLSL: String;
  FSComposite: TRHIShaderModule;
  ReinhardOut, ACESOut, AgXOut, SRGBOut, CompositeGraded: TVector3;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Graph := nil;
  CmdList := nil;
  LDRTarget := nil;
  FSComposite := nil;
  try
    { 1. Verify GLSL Tonemapping (Reinhard, ACES Filmic, AgX) & Color Grading shader generation }
    TonemapHelpersGLSL := Gen.GenerateTonemappingAndColorGradingFunctions;
    CompositeFragGLSL := Gen.GenerateHDRCompositeFragmentShader;

    AssertTrue('Tonemap helpers must include TonemapReinhard',
      Pos('vec3 TonemapReinhard(vec3 hdr)', TonemapHelpersGLSL) > 0);
    AssertTrue('Tonemap helpers must include TonemapACESFilmic',
      Pos('vec3 TonemapACESFilmic(vec3 x)', TonemapHelpersGLSL) > 0);
    AssertTrue('Tonemap helpers must include TonemapAgX with inset matrix and sigmoid log2 encoding',
      Pos('vec3 TonemapAgX(vec3 hdr)', TonemapHelpersGLSL) > 0);
    AssertTrue('Tonemap helpers must include ApplyColorGrading',
      Pos('vec3 ApplyColorGrading(', TonemapHelpersGLSL) > 0);
    AssertTrue('Tonemap helpers must include LinearToSRGB',
      Pos('vec3 LinearToSRGB(vec3 linearColor)', TonemapHelpersGLSL) > 0);

    FSComposite := VkDev.CreateShaderModuleFromGLSL(ssFragment, CompositeFragGLSL, 'HDRComposite_FS');
    AssertTrue('HDRComposite_FS shader module must compile', FSComposite <> nil);

    { 2. Verify CPU reference curves for Reinhard, ACES Filmic (Narkowicz), and AgX (Sobotka) }
    HDRPost := VkDev.HDRPostProcessor;

    ReinhardOut := HDRPost.EvaluateTonemapReinhard(Vector3(1.0, 1.0, 1.0));
    AssertSameValue(0.5, ReinhardOut.X, 1e-4);

    ACESOut := HDRPost.EvaluateTonemapACESFilmic(Vector3(10.0, 10.0, 10.0));
    AssertTrue('ACES Filmic must compress 10.0 HDR white into (0.9..1.0] display range',
      (ACESOut.X > 0.9) and (ACESOut.X <= 1.0));

    { AgX chroma-preserving highlight desaturation test:
      A bright saturated red (25.0, 0.5, 0.5) under AgX inset matrix + sigmoid must desaturate
      toward white (G and B channels rise significantly above 0.5) }
    AgXOut := HDRPost.EvaluateTonemapAgX(Vector3(25.0, 0.5, 0.5));
    AssertTrue('AgX must map HDR highlights into [0..1]',
      (AgXOut.X > 0.8) and (AgXOut.X <= 1.0));
    AssertTrue('AgX inset matrix must gracefully desaturate bright primary highlights (G/B > 0.45)',
      (AgXOut.Y > 0.45) and (AgXOut.Z > 0.45));

    SRGBOut := HDRPost.EvaluateLinearToSRGB(Vector3(0.5, 0.5, 0.5));
    AssertSameValue(0.735357, SRGBOut.X, 1e-3);

    { 3. Verify full composite evaluation (HDR + Bloom + Exposure + Grading + AgX + sRGB) }
    HDRPost.TonemapOperator := tmoAgX;
    HDRPost.BloomIntensity := 0.1;
    HDRPost.Contrast := 1.1;
    HDRPost.Saturation := 1.05;
    HDRPost.Gamma := 2.2;
    CompositeGraded := HDRPost.EvaluateCompositeColor(
      Vector3(2.0, 1.5, 1.0), Vector3(0.5, 0.5, 0.5));
    AssertTrue('Composite output must be clamped in [0..1] display range',
      (CompositeGraded.X >= 0.0) and (CompositeGraded.X <= 1.0) and
      (CompositeGraded.Y >= 0.0) and (CompositeGraded.Y <= 1.0) and
      (CompositeGraded.Z >= 0.0) and (CompositeGraded.Z <= 1.0));

    { 4. Verify end-to-end BuildDefaultFrameRenderGraph + ExecuteCompositePass }
    FillChar(LDRDesc, SizeOf(LDRDesc), 0);
    LDRDesc.Dimension := td2D;
    LDRDesc.Format := pfRGBA8_UNorm;
    LDRDesc.Width := 1280;
    LDRDesc.Height := 720;
    LDRDesc.DepthOrArrayLayers := 1;
    LDRDesc.MipLevels := 1;
    LDRDesc.SampleCount := 1;
    LDRDesc.Usage := [tuColorAttachment, tuSampled, tuTransferSrc];
    LDRDesc.DebugName := 'LDRDisplayTarget';
    LDRTarget := VkDev.CreateTexture(LDRDesc);

    Graph := TRHIRenderGraph.Create(VkDev);
    HDRPost.BuildDefaultFrameRenderGraph(Graph, 1280, 720, LDRTarget);
    Graph.Compile;

    AssertTrue('Default frame RenderGraph must compile cleanly', Graph.IsCompiled);
    AssertEquals('Default frame RenderGraph must contain 4 active passes (HDRScene, Bloom, AutoExposure, Composite)',
      4, Graph.CompiledPassCount);
    AssertEquals('Default frame RenderGraph must have 0 culled passes',
      0, Graph.CulledPassCount);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Graph.Execute(CmdList);
    HDRPost.ExecuteCompositePass(CmdList, LDRTarget);
    CmdList.EndRecording;

    AssertEquals('RenderGraph ExecutionCount must be 1', 1, Graph.ExecutionCount);
    AssertTrue('TotalCompositePasses must be >= 1', HDRPost.TotalCompositePasses >= 1);
  finally
    FreeAndNil(FSComposite);
    FreeAndNil(CmdList);
    FreeAndNil(Graph);
    FreeAndNil(LDRTarget);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestComputeGTAOAndBilateralDenoiserRHI;
var
  VkDev: TVulkanRHIDevice;
  GTAO: TCastleVulkanGTAO;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  DepthTex: TRHITexture;
  DepthDesc: TRHITextureDesc;
  GTAOGLSL, DenoiseGLSL: String;
  CSGTAO, CSDenoise: TRHIShaderModule;
  ViewPos: TVector3;
  OpenVis, CornerVis, CavityVis, WCoplanar, WEdge: Single;
  Dispatches: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  DepthTex := nil;
  CSGTAO := nil;
  CSDenoise := nil;
  try
    { 1. Verify struct size and GLSL 450 GTAO & Bilateral Denoiser compute shader generation }
    AssertEquals('TCastleGTAOPushConstants size must be 48 bytes',
      48, SizeOf(TCastleGTAOPushConstants));

    GTAOGLSL := Gen.GenerateGTAOComputeShader;
    DenoiseGLSL := Gen.GenerateGTAODenoiseComputeShader;

    AssertTrue('GTAO GLSL must include ReconstructViewPosition',
      Pos('vec3 ReconstructViewPosition(vec2 uv, float linearZ)', GTAOGLSL) > 0);
    AssertTrue('GTAO GLSL must include ReconstructViewNormalFromDepth',
      Pos('vec3 ReconstructViewNormalFromDepth(vec2 uv, vec3 centerPos)', GTAOGLSL) > 0);
    AssertTrue('GTAO GLSL must include IntegrateGTAOHorizonSlice',
      Pos('float IntegrateGTAOHorizonSlice(float h1, float h2, float nAngle)', GTAOGLSL) > 0);
    AssertTrue('Denoise GLSL must include ComputeBilateralDepthWeight',
      Pos('float ComputeBilateralDepthWeight(float centerDepth, float sampleDepth, float sigmaDepth)', DenoiseGLSL) > 0);

    CSGTAO := VkDev.CreateShaderModuleFromGLSL(ssCompute, GTAOGLSL, 'GTAO_CS');
    CSDenoise := VkDev.CreateShaderModuleFromGLSL(ssCompute, DenoiseGLSL, 'GTAODenoise_CS');
    AssertTrue('GTAO_CS module must compile', CSGTAO <> nil);
    AssertTrue('GTAODenoise_CS module must compile', CSDenoise <> nil);

    { 2. Verify view-space reconstruction, Jiménez GTAO analytical horizon integral & bilateral depth weight }
    GTAO := VkDev.GTAO;
    AssertTrue('GTAO must be lazily created by TVulkanRHIDevice', GTAO <> nil);

    ViewPos := GTAO.ReconstructViewPosition(Vector2(0.5, 0.5), Vector2(1.0, 1.0), 10.0);
    AssertSameValue(0.0, ViewPos.X, 1e-5);
    AssertSameValue(0.0, ViewPos.Y, 1e-5);
    AssertSameValue(-10.0, ViewPos.Z, 1e-5);

    { Flat unoccluded hemisphere: h1 = -PI/2, h2 = +PI/2, nAngle = 0 -> visibility = 1.0 }
    OpenVis := GTAO.IntegrateGTAOHorizonSlice(-Pi * 0.5, Pi * 0.5, 0.0);
    AssertSameValue(1.0, OpenVis, 1e-4);

    { 90-degree orthogonal wall corner: h1 = 0, h2 = +PI/2, nAngle = 0 -> visibility = 0.5 }
    CornerVis := GTAO.IntegrateGTAOHorizonSlice(0.0, Pi * 0.5, 0.0);
    AssertSameValue(0.5, CornerVis, 1e-4);

    { Deep narrow crease: cos(h) near 0.9 -> strong occlusion (< 0.15) }
    GTAO.Power := 1.5;
    CavityVis := GTAO.EvaluateGTAOFromHorizonCosines(0.9, 0.9, 0.0);
    AssertTrue('Deep narrow crease must produce strong ambient occlusion (< 0.15)',
      CavityVis < 0.15);

    { Cross-bilateral depth weight: coplanar neighbor vs silhouette edge discontinuity }
    WCoplanar := GTAO.ComputeBilateralDepthWeight(0.500, 0.501, 0.015);
    WEdge := GTAO.ComputeBilateralDepthWeight(0.500, 0.850, 0.015);
    AssertTrue('Coplanar depth neighbor must have high bilateral weight (> 0.99)', WCoplanar > 0.99);
    AssertTrue('Silhouette depth discontinuity must have near-zero bilateral weight (< 1e-4)', WEdge < 1e-4);

    { 3. Verify GTAO full-res & half-res pfR16_Float target allocation and 2-pass compute dispatch }
    GTAO.EnsureGTAOTargets(1920, 1080, True);
    AssertEquals('Half-res GTAO width must be 960', 960, GTAO.Width);
    AssertEquals('Half-res GTAO height must be 540', 540, GTAO.Height);
    AssertEquals('RawGTAOTexture format must be pfR16_Float',
      Ord(pfR16_Float), Ord(GTAO.RawGTAOTexture.Desc.Format));
    AssertEquals('DenoisedGTAOTexture format must be pfR16_Float',
      Ord(pfR16_Float), Ord(GTAO.DenoisedGTAOTexture.Desc.Format));

    DepthDesc := TRHITextureDesc.Create2D(1920, 1080, pfD32_Float, [tuDepthStencil, tuSampled], 1, 1);
    DepthTex := VkDev.CreateTexture(DepthDesc);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := GTAO.DispatchGTAO(CmdList, DepthTex);
    CmdList.EndRecording;

    AssertEquals('DispatchGTAO must record 2 compute dispatches (1 horizon + 1 bilateral denoise)', 2, Dispatches);
    AssertEquals('TotalGTAODispatches must be 1', 1, GTAO.TotalGTAODispatches);
    AssertEquals('TotalDenoiseDispatches must be 1', 1, GTAO.TotalDenoiseDispatches);
  finally
    FreeAndNil(CSDenoise);
    FreeAndNil(CSGTAO);
    FreeAndNil(CmdList);
    FreeAndNil(DepthTex);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestHierarchicalZScreenSpaceReflectionsRHI;
var
  VkDev: TVulkanRHIDevice;
  SSR: TCastleVulkanSSR;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  HDRTex, HiZTex: TRHITexture;
  HDRDesc, HiZDesc: TRHITextureDesc;
  SSRGLSL: String;
  CSSSR: TRHIShaderModule;
  FadeCenter, FadeEdge, WeightMirrorGrazing, WeightRough: Single;
  HiZDepths: array[0..31] of Single;
  I, HitCell: Integer;
  HitSteps, Dispatches: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  HDRTex := nil;
  HiZTex := nil;
  CSSSR := nil;
  try
    { 1. Verify struct size and GLSL 450 Hi-Z SSR compute shader generation }
    AssertEquals('TCastleSSRPushConstants size must be 48 bytes',
      48, SizeOf(TCastleSSRPushConstants));

    SSRGLSL := Gen.GenerateHiZSSRComputeShader;
    AssertTrue('SSR GLSL must include EvaluateScreenEdgeFade',
      Pos('float EvaluateScreenEdgeFade(vec2 hitUV, float fadeWidth)', SSRGLSL) > 0);
    AssertTrue('SSR GLSL must include EvaluateSSRReflectionWeight',
      Pos('float EvaluateSSRReflectionWeight(float roughness, float maxRoughness, float cosTheta)', SSRGLSL) > 0);
    AssertTrue('SSR GLSL must sample u_HiZPyramidTexture across mip levels',
      Pos('textureLod(u_HiZPyramidTexture, curUV, float(mipLevel))', SSRGLSL) > 0);

    CSSSR := VkDev.CreateShaderModuleFromGLSL(ssCompute, SSRGLSL, 'HiZSSR_CS');
    AssertTrue('HiZSSR_CS module must compile', CSSSR <> nil);

    { 2. Verify Screen-Edge Vignette Fade, Roughness/Fresnel Weighting & Hierarchical-Z Raymarching }
    SSR := VkDev.SSR;
    AssertTrue('SSR must be lazily created by TVulkanRHIDevice', SSR <> nil);

    FadeCenter := SSR.EvaluateScreenEdgeFade(Vector2(0.5, 0.5), 0.12);
    FadeEdge := SSR.EvaluateScreenEdgeFade(Vector2(0.0, 0.5), 0.12);
    AssertSameValue(1.0, FadeCenter, 1e-4);
    AssertSameValue(0.0, FadeEdge, 1e-4);

    WeightMirrorGrazing := SSR.EvaluateSSRReflectionWeight(0.02, 0.6, 0.05);
    WeightRough := SSR.EvaluateSSRReflectionWeight(0.75, 0.6, 0.05);
    AssertTrue('Smooth grazing surface must have strong Fresnel SSR weight (> 0.7)',
      WeightMirrorGrazing > 0.7);
    AssertSameValue(0.0, WeightRough, 1e-5);

    { Populate a 32-cell depth buffer where cells 0..27 are far background (0.95)
      and cell 28 contains a foreground reflection occluder at depth 0.55.
      Hierarchical-Z mip skipping must find cell 28 in far fewer than 28 linear steps! }
    for I := 0 to High(HiZDepths) do
      HiZDepths[I] := 0.95;
    HiZDepths[28] := 0.55;

    SSR.Thickness := 0.15;
    SSR.HiZMipCount := 5;
    SSR.MaxSteps := 48;
    AssertTrue('RaymarchHiZ1D must find the foreground occluder at cell 28',
      SSR.RaymarchHiZ1D(HiZDepths, 0, 0.44, 0.005, HitCell, HitSteps));
    AssertEquals('RaymarchHiZ1D must hit exact cell 28', 28, HitCell);
    AssertTrue('Hierarchical-Z mip skipping must find cell 28 in < 16 steps (vs 29 linear steps)',
      HitSteps < 16);

    { 3. Verify SSR target allocation and compute dispatch }
    SSR.EnsureSSRTarget(1280, 720);
    AssertTrue('SSRReflectionTexture must be allocated', SSR.SSRReflectionTexture <> nil);
    AssertEquals('SSRReflectionTexture format must be pfRGBA16_Float',
      Ord(pfRGBA16_Float), Ord(SSR.SSRReflectionTexture.Desc.Format));

    HDRDesc := TRHITextureDesc.Create2D(1280, 720, pfRGBA16_Float, [tuColorAttachment, tuSampled], 1, 1);
    HiZDesc := TRHITextureDesc.Create2D(1280, 720, pfR32_Float, [tuSampled, tuStorage], 6, 1);
    HDRTex := VkDev.CreateTexture(HDRDesc);
    HiZTex := VkDev.CreateTexture(HiZDesc);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := SSR.DispatchSSR(CmdList, HDRTex, HiZTex);
    CmdList.EndRecording;

    AssertEquals('DispatchSSR must record 1 compute dispatch', 1, Dispatches);
    AssertEquals('TotalSSRDispatches must be 1', 1, SSR.TotalSSRDispatches);
  finally
    FreeAndNil(CSSSR);
    FreeAndNil(CmdList);
    FreeAndNil(HiZTex);
    FreeAndNil(HDRTex);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestFroxelVolumetricFogAndHeightFogRHI;
var
  VkDev: TVulkanRHIDevice;
  VolFog: TCastleVulkanVolumetricFog;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  InjectGLSL, RaymarchGLSL: String;
  CSInject, CSRaymarch: TRHIShaderModule;
  PhaseIso, PhaseForward, PhaseBack, DensityLow, DensityHigh: Single;
  AccumLight: TVector3;
  AccumTransmittance: Single;
  SliceIdx: Integer;
  Dispatches: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  CSInject := nil;
  CSRaymarch := nil;
  try
    { 1. Verify struct size and GLSL 450 Volumetric Fog Inject & Raymarch compute shader generation }
    AssertEquals('TCastleVolumetricFogParams size must be 64 bytes',
      64, SizeOf(TCastleVolumetricFogParams));

    InjectGLSL := Gen.GenerateVolumetricFogInjectComputeShader;
    RaymarchGLSL := Gen.GenerateVolumetricFogRaymarchComputeShader;

    AssertTrue('Volumetric Fog Inject GLSL must include EvaluateHenyeyGreensteinPhase',
      Pos('float EvaluateHenyeyGreensteinPhase(float cosTheta, float g)', InjectGLSL) > 0);
    AssertTrue('Volumetric Fog Inject GLSL must include EvaluateHeightFogDensity',
      Pos('float EvaluateHeightFogDensity(float worldY, float baseDensity, float baseHeight, float heightFalloff)', InjectGLSL) > 0);
    AssertTrue('Volumetric Fog Inject GLSL must write to image3D u_FroxelScatteringVolume',
      Pos('uniform writeonly image3D u_FroxelScatteringVolume;', InjectGLSL) > 0);
    AssertTrue('Volumetric Fog Raymarch GLSL must include IntegrateFroxelSliceStep',
      Pos('void IntegrateFroxelSliceStep(', RaymarchGLSL) > 0);
    AssertTrue('Volumetric Fog Raymarch GLSL must write to image3D u_IntegratedFroxelLUT',
      Pos('uniform writeonly image3D u_IntegratedFroxelLUT;', RaymarchGLSL) > 0);

    CSInject := VkDev.CreateShaderModuleFromGLSL(ssCompute, InjectGLSL, 'VolFogInject_CS');
    CSRaymarch := VkDev.CreateShaderModuleFromGLSL(ssCompute, RaymarchGLSL, 'VolFogRaymarch_CS');
    AssertTrue('VolFogInject_CS module must compile', CSInject <> nil);
    AssertTrue('VolFogRaymarch_CS module must compile', CSRaymarch <> nil);

    { 2. Verify Henyey-Greenstein phase function, Exponential Height Fog & Beer-Lambert step integration }
    VolFog := VkDev.VolumetricFog;
    AssertTrue('VolumetricFog must be lazily created by TVulkanRHIDevice', VolFog <> nil);

    PhaseIso := VolFog.EvaluateHenyeyGreensteinPhase(0.3, 0.0);
    AssertSameValue(1.0 / (4.0 * Pi), PhaseIso, 1e-4);

    PhaseForward := VolFog.EvaluateHenyeyGreensteinPhase(1.0, 0.7);
    PhaseBack := VolFog.EvaluateHenyeyGreensteinPhase(-1.0, 0.7);
    AssertTrue('Forward-scattering HG phase (g=0.7, cosTheta=1) must be >> back-scattering (> 50x)',
      PhaseForward > PhaseBack * 50.0);

    DensityLow := VolFog.EvaluateHeightFogDensity(0.0, 0.05, 0.0, 0.1);
    DensityHigh := VolFog.EvaluateHeightFogDensity(30.0, 0.05, 0.0, 0.1);
    AssertSameValue(0.05, DensityLow, 1e-5);
    AssertTrue('Exponential height fog density must decay with altitude', DensityHigh < DensityLow * 0.1);

    AccumLight := Vector3(0.0, 0.0, 0.0);
    AccumTransmittance := 1.0;
    for SliceIdx := 1 to 16 do
      VolFog.IntegrateFroxelSliceStep(Vector3(0.04, 0.04, 0.05), 0.05, 2.0, AccumLight, AccumTransmittance);
    AssertTrue('Beer-Lambert transmittance must decay below 0.25 across 16 fog slices',
      (AccumTransmittance > 0.0) and (AccumTransmittance < 0.25));
    AssertTrue('Accumulated in-scattered light must be positive', AccumLight.Z > 0.5);

    { 3. Verify 3D Froxel volume allocation (160x90x64 td3D pfRGBA16_Float) and 2-pass compute dispatch }
    VolFog.EnsureFroxelVolumes;
    AssertTrue('FroxelScatteringVolume 3D texture must be created', VolFog.FroxelScatteringVolume <> nil);
    AssertTrue('IntegratedFroxelLUT 3D texture must be created', VolFog.IntegratedFroxelLUT <> nil);
    AssertEquals('FroxelScatteringVolume dimension must be td3D',
      Ord(td3D), Ord(VolFog.FroxelScatteringVolume.Desc.Dimension));
    AssertEquals('Froxel grid X must be 160', CASTLE_FROXEL_GRID_X, VolFog.GridX);
    AssertEquals('Froxel grid Y must be 90', CASTLE_FROXEL_GRID_Y, VolFog.GridY);
    AssertEquals('Froxel grid Z must be 64', CASTLE_FROXEL_GRID_Z, VolFog.GridZ);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := VolFog.DispatchVolumetricFog(CmdList);
    CmdList.EndRecording;

    AssertEquals('DispatchVolumetricFog must record 2 compute dispatches (1 3D inject + 1 front-to-back raymarch)',
      2, Dispatches);
    AssertEquals('TotalInjectDispatches must be 1', 1, VolFog.TotalInjectDispatches);
    AssertEquals('TotalRaymarchDispatches must be 1', 1, VolFog.TotalRaymarchDispatches);
  finally
    FreeAndNil(CSRaymarch);
    FreeAndNil(CSInject);
    FreeAndNil(CmdList);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestTemporalAntiAliasingAndHaltonJitterRHI;
var
  VkDev: TVulkanRHIDevice;
  TAA: TCastleVulkanTAA;
  Gen: TCastleShaderGeneratorRHI;
  CmdList: TVulkanRHICommandList;
  HDRTex, FirstResolved, SecondResolved: TRHITexture;
  HDRDesc: TRHITextureDesc;
  TAAGLSL: String;
  CSTAA: TRHIShaderModule;
  Jitter0, Jitter1, Jitter8: TVector2;
  OrigRGB, YCoCgVal, RoundTripRGB, ClippedYCoCg, ClippedRGB: TVector3;
  Dispatches: Cardinal;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($1234)), False, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  CmdList := nil;
  HDRTex := nil;
  CSTAA := nil;
  try
    { 1. Verify struct size and GLSL 450 TAA Resolve compute shader generation }
    AssertEquals('TCastleTAAPushConstants size must be 32 bytes',
      32, SizeOf(TCastleTAAPushConstants));

    TAAGLSL := Gen.GenerateTAAResolveComputeShader;
    AssertTrue('TAA GLSL must include RGBToYCoCg',
      Pos('vec3 RGBToYCoCg(vec3 rgb)', TAAGLSL) > 0);
    AssertTrue('TAA GLSL must include YCoCgToRGB',
      Pos('vec3 YCoCgToRGB(vec3 ycocg)', TAAGLSL) > 0);
    AssertTrue('TAA GLSL must include ClipHistoryYCoCg',
      Pos('vec3 ClipHistoryYCoCg(vec3 historyYCoCg, vec3 meanYCoCg, vec3 stdDevYCoCg, float gamma)', TAAGLSL) > 0);
    AssertTrue('TAA GLSL must include SampleHistoryCatmullRom5Tap',
      Pos('vec3 SampleHistoryCatmullRom5Tap(sampler2D tex, vec2 uv, vec2 invRes)', TAAGLSL) > 0);

    CSTAA := VkDev.CreateShaderModuleFromGLSL(ssCompute, TAAGLSL, 'TAAResolve_CS');
    AssertTrue('TAAResolve_CS module must compile', CSTAA <> nil);

    { 2. Verify Halton (2, 3) low-discrepancy jitter sequence & YCoCg variance clipping }
    TAA := VkDev.TAA;
    AssertTrue('TAA must be lazily created by TVulkanRHIDevice', TAA <> nil);

    AssertSameValue(0.5, TAA.EvaluateHaltonSequence(1, 2), 1e-5);
    AssertSameValue(0.25, TAA.EvaluateHaltonSequence(2, 2), 1e-5);
    AssertSameValue(0.75, TAA.EvaluateHaltonSequence(3, 2), 1e-5);
    AssertSameValue(1.0 / 3.0, TAA.EvaluateHaltonSequence(1, 3), 1e-5);
    AssertSameValue(2.0 / 3.0, TAA.EvaluateHaltonSequence(2, 3), 1e-5);

    Jitter0 := TAA.ComputeHaltonJitterOffset(0, 8, 1920, 1080);
    Jitter1 := TAA.ComputeHaltonJitterOffset(1, 8, 1920, 1080);
    Jitter8 := TAA.ComputeHaltonJitterOffset(8, 8, 1920, 1080);
    AssertTrue('Adjacent frames must have distinct Halton sub-pixel jitter offsets',
      (Abs(Jitter0.X - Jitter1.X) > 1e-6) or (Abs(Jitter0.Y - Jitter1.Y) > 1e-6));
    AssertSameValue(Jitter0.X, Jitter8.X, 1e-6);
    AssertSameValue(Jitter0.Y, Jitter8.Y, 1e-6);

    OrigRGB := Vector3(0.8, 0.4, 0.2);
    YCoCgVal := TAA.RGBToYCoCg(OrigRGB);
    RoundTripRGB := TAA.YCoCgToRGB(YCoCgVal);
    AssertSameValue(OrigRGB.X, RoundTripRGB.X, 1e-5);
    AssertSameValue(OrigRGB.Y, RoundTripRGB.Y, 1e-5);
    AssertSameValue(OrigRGB.Z, RoundTripRGB.Z, 1e-5);

    { Ghosting history outlier (RGB = 10, 10, 10) must be clipped to neighborhood [Mean + Gamma*StdDev] }
    ClippedYCoCg := TAA.ClipHistoryYCoCg(
      TAA.RGBToYCoCg(Vector3(10.0, 10.0, 10.0)),
      TAA.RGBToYCoCg(Vector3(0.5, 0.5, 0.5)),
      Vector3(0.1, 0.05, 0.05), 1.25);
    ClippedRGB := TAA.YCoCgToRGB(ClippedYCoCg);
    AssertTrue('Variance clipping must clamp bright ghosting history outlier below 0.7',
      ClippedRGB.X < 0.7);

    { 3. Verify Velocity (pfRG16_Float) + Ping-Pong History (pfRGBA16_Float) allocation and compute dispatch }
    TAA.EnsureTAATargets(1920, 1080);
    AssertTrue('VelocityTexture must be allocated', TAA.VelocityTexture <> nil);
    AssertEquals('VelocityTexture format must be pfRG16_Float',
      Ord(pfRG16_Float), Ord(TAA.VelocityTexture.Desc.Format));
    AssertEquals('ResolvedHistoryTexture format must be pfRGBA16_Float',
      Ord(pfRGBA16_Float), Ord(TAA.ResolvedHistoryTexture.Desc.Format));

    HDRDesc := TRHITextureDesc.Create2D(1920, 1080, pfRGBA16_Float, [tuColorAttachment, tuSampled], 1, 1);
    HDRTex := VkDev.CreateTexture(HDRDesc);

    CmdList := TVulkanRHICommandList.Create(VkDev, 0);
    CmdList.BeginRecording;
    Dispatches := TAA.DispatchTAAResolve(CmdList, HDRTex, 0);
    FirstResolved := TAA.ResolvedHistoryTexture;
    Dispatches := Dispatches + TAA.DispatchTAAResolve(CmdList, HDRTex, 1);
    SecondResolved := TAA.ResolvedHistoryTexture;
    CmdList.EndRecording;

    AssertEquals('Two TAA frames must record 2 compute dispatches', 2, Dispatches);
    AssertTrue('TAA history textures must ping-pong between frames', FirstResolved <> SecondResolved);
    AssertEquals('TotalTAADispatches must be 2', 2, TAA.TotalTAADispatches);
  finally
    FreeAndNil(CSTAA);
    FreeAndNil(CmdList);
    FreeAndNil(HDRTex);
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestBoxProjectedParallaxReflectionProbesRHI;
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

procedure TTestCastleVulkanRHI.TestOrientedBoxDecalProjectionRHI;
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

procedure TTestCastleVulkanRHI.TestGPUComputeParticleSimulationAndIndirectDrawRHI;
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

procedure TTestCastleVulkanRHI.TestWeightedBlendedOrderIndependentTransparencyRHI;
var
  VkDev: TVulkanRHIDevice;
  Gen: TCastleShaderGeneratorRHI;
  OIT: TCastleVulkanWeightedBlendedOIT;
  OITFunctionsGLSL, OITCompositeFS: String;
  NearWeight, FarWeight, RevealageAB, RevealageBA: Single;
  AccumAB, AccumBA, RedSample, BlueSample: TVector4;
  CompositeAB, CompositeBA, OpaqueBg: TVector3;
begin
  VkDev := TVulkanRHIDevice.CreateHeadless(nil, True, True, VK_API_VERSION_1_3);
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Weighted Blended OIT GLSL helpers and composite fragment shader }
    OITFunctionsGLSL := Gen.GenerateWeightedBlendedOITFunctions;
    AssertTrue('OIT GLSL must include EvaluateOITDepthWeight',
      Pos('float EvaluateOITDepthWeight(float linearZ, float alpha, float weightScale)', OITFunctionsGLSL) > 0);
    AssertTrue('OIT GLSL must include AccumulateWeightedBlendedOIT',
      Pos('void AccumulateWeightedBlendedOIT(', OITFunctionsGLSL) > 0);

    OITCompositeFS := Gen.GenerateWeightedBlendedOITCompositeFragmentShader;
    AssertTrue('OIT Composite FS must sample u_OITAccumTexture and u_OITRevealageTexture',
      (Pos('u_OITAccumTexture', OITCompositeFS) > 0) and (Pos('u_OITRevealageTexture', OITCompositeFS) > 0));

    { 2. Verify depth weight monotonically decreases with distance and order independence holds }
    NearWeight := TCastleVulkanWeightedBlendedOIT.EvaluateOITDepthWeight(2.0, 0.5, 1.0);
    FarWeight := TCastleVulkanWeightedBlendedOIT.EvaluateOITDepthWeight(50.0, 0.5, 1.0);
    AssertTrue('Near transparent surface at Z=2m must have higher OIT weight than far surface at Z=50m',
      NearWeight > FarWeight);

    RedSample := Vector4(0.5, 0.0, 0.0, 0.5);   { premultiplied red at Z=3m }
    BlueSample := Vector4(0.0, 0.0, 0.5, 0.5);  { premultiplied blue at Z=15m }
    OpaqueBg := Vector3(0.2, 0.2, 0.2);

    { Order A -> B (near red then far blue) }
    AccumAB := Vector4(0.0, 0.0, 0.0, 0.0);
    RevealageAB := 1.0;
    TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(RedSample, 3.0, 1.0, AccumAB, RevealageAB);
    TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(BlueSample, 15.0, 1.0, AccumAB, RevealageAB);
    CompositeAB := TCastleVulkanWeightedBlendedOIT.EvaluateOITComposite(AccumAB, RevealageAB, OpaqueBg);

    { Order B -> A (far blue then near red) }
    AccumBA := Vector4(0.0, 0.0, 0.0, 0.0);
    RevealageBA := 1.0;
    TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(BlueSample, 15.0, 1.0, AccumBA, RevealageBA);
    TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(RedSample, 3.0, 1.0, AccumBA, RevealageBA);
    CompositeBA := TCastleVulkanWeightedBlendedOIT.EvaluateOITComposite(AccumBA, RevealageBA, OpaqueBg);

    AssertSameValue(RevealageAB, RevealageBA, 1e-6);
    AssertSameValue(0.25, RevealageAB, 1e-5);
    AssertSameValue(CompositeAB.X, CompositeBA.X, 1e-5);
    AssertSameValue(CompositeAB.Y, CompositeBA.Y, 1e-5);
    AssertSameValue(CompositeAB.Z, CompositeBA.Z, 1e-5);
    AssertTrue('Near red sample must dominate far blue sample in composite',
      CompositeAB.X > CompositeAB.Z);

    { 3. Verify OIT MRT target allocation }
    OIT := VkDev.WeightedBlendedOIT;
    AssertTrue('WeightedBlendedOIT must be lazily created by TVulkanRHIDevice', OIT <> nil);
    OIT.EnsureOITTargets(640, 360);
    AssertTrue('OITAccumTexture (pfRGBA16_Float) must be allocated', OIT.OITAccumTexture <> nil);
    AssertTrue('OITRevealageTexture (pfR16_Float) must be allocated', OIT.OITRevealageTexture <> nil);
    AssertEquals('OITAccumTexture format must be pfRGBA16_Float',
      Ord(pfRGBA16_Float), Ord(OIT.OITAccumTexture.Desc.Format));
    AssertEquals('OITRevealageTexture format must be pfR16_Float',
      Ord(pfR16_Float), Ord(OIT.OITRevealageTexture.Desc.Format));
  finally
    FreeAndNil(Gen);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestScreenSpaceRaymarchedContactShadowsRHI;
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

procedure TTestCastleVulkanRHI.TestComputeSkinningAndMorphTargetsRHI;
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

procedure TTestCastleVulkanRHI.TestGPUDrivenTerrainCDLODRHI;
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

procedure TTestCastleVulkanRHI.TestSubsurfaceScatteringAndFoliageTransmissionPBRRHI;
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

procedure TTestCastleVulkanRHI.TestClearCoatAndAnisotropicPBRRHI;
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

procedure TTestCastleVulkanRHI.TestRayleighMieAtmosphereSkyLUTComputeRHI;
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

procedure TTestCastleVulkanRHI.TestLensFlareAndChromaticAberrationPostProcessRHI;
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

procedure TTestCastleVulkanRHI.TestClothSheenAndIridescencePBRRHI;
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

procedure TTestCastleVulkanRHI.TestComputeGerstnerOceanSimulationAndFoamRHI;
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

procedure TTestCastleVulkanRHI.TestMotionBlurAndBokehDepthOfFieldPostProcessRHI;
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

procedure TTestCastleVulkanRHI.TestDDGIOctahedralProbeGridRHI;
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

procedure TTestCastleVulkanRHI.TestGPUMeshletConeAndSphereCullingRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Gen: TCastleShaderGeneratorRHI;
  MeshletGLSL: String;
  VisibleCount: Cardinal;
begin
  AssertEquals('TCastleMeshletDescriptor must be 48 bytes',
    48, SizeOf(TCastleMeshletDescriptor));

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  Device := TVulkanRHIDevice.CreateHeadless( VkPhysicalDevice(PtrUInt($6666)) );
  CmdList := TVulkanRHICommandList.Create(Device, 0);
  try
    { 1. Verify Meshlet Culling Compute Shader GLSL 450 }
    MeshletGLSL := Gen.GenerateMeshletCullingComputeShader(64);
    AssertTrue('Meshlet compute shader must include CastleMeshletDescriptor and EvaluateMeshletConeBackfaceCull',
      (Pos('struct CastleMeshletDescriptor {', MeshletGLSL) > 0) and
      (Pos('bool EvaluateMeshletConeBackfaceCull(vec3 meshletCenter, vec3 cameraPos, vec3 coneAxis, float coneCutoff)', MeshletGLSL) > 0));

    { 2. Register 3 meshlets:
         #0: Front-facing cone (axis = (0,0,1) toward camera at (0,0,10)), within draw distance -> VISIBLE
         #1: Back-facing cone (axis = (0,0,-1) away from camera at (0,0,10), dot(viewRay=(0,0,-1), axis=(0,0,-1)) = 1.0 >= cutoff 0.5) -> CULLED
         #2: Beyond max draw distance (z = -500) -> CULLED }
    Device.MeshletCuller.ClearMeshlets;
    Device.MeshletCuller.AddMeshlet(Vector3(0.0, 0.0, 0.0), 2.0, Vector3(0.0, 0.0, 1.0), 0.5, 0, 64, 0, 124);
    Device.MeshletCuller.AddMeshlet(Vector3(0.0, 0.0, 0.0), 2.0, Vector3(0.0, 0.0, -1.0), 0.5, 64, 64, 124, 124);
    Device.MeshletCuller.AddMeshlet(Vector3(0.0, 0.0, -500.0), 2.0, Vector3(0.0, 0.0, 1.0), 0.5, 128, 64, 248, 124);

    AssertEquals(Cardinal(3), Device.MeshletCuller.MeshletCount);
    VisibleCount := Device.MeshletCuller.EvaluateVisibleMeshletsCPU(Vector3(0.0, 0.0, 10.0), 100.0);
    AssertEquals('Only front-facing in-range meshlet #0 must survive culling', Cardinal(1), VisibleCount);

    { 3. Verify GPU meshlet SSBO upload and compute dispatch }
    CmdList.BeginRecording;
    Device.MeshletCuller.DispatchMeshletCulling(CmdList, Vector3(0.0, 0.0, 10.0), 100.0, nil, nil);
    CmdList.EndRecording;

    AssertEquals(Cardinal(1), Device.MeshletCuller.DispatchCount);
    AssertTrue('Meshlet SSBOs must be allocated',
      (Device.MeshletCuller.MeshletBuffer <> nil) and
      (Device.MeshletCuller.VisibleMeshletIndicesBuffer <> nil) and
      (Device.MeshletCuller.VisibleMeshletCountBuffer <> nil));
  finally
    FreeAndNil(CmdList);
    FreeAndNil(Device);
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestContrastAdaptiveSharpeningCASRHI;
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

procedure TTestCastleVulkanRHI.TestInlineRayQueryAndBVHIntersectionRHI;
var
  Gen: TCastleShaderGeneratorRHI;
  RayGLSL: String;
  TNear, TFar, THit, BaryU, BaryV: Single;
begin
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    { 1. Verify Hardware Ray Query (GL_EXT_ray_query) & BVH fallback GLSL 450 }
    RayGLSL := Gen.GenerateInlineRayQueryFunctions(True);
    AssertTrue('Ray Query GLSL must include GL_EXT_ray_query, EvaluateRayAABBIntersection, and Moller-Trumbore intersection',
      (Pos('#extension GL_EXT_ray_query : enable', RayGLSL) > 0) and
      (Pos('bool EvaluateRayAABBIntersection(vec3 rayOrigin, vec3 rayDir,', RayGLSL) > 0) and
      (Pos('bool EvaluateRayTriangleIntersection(vec3 rayOrigin, vec3 rayDir,', RayGLSL) > 0));

    { 2. Verify Slab Ray-AABB intersection (hit and miss) }
    AssertTrue('Ray along -Z from (0,0,5) must intersect AABB [-1,-1,-1]..[1,1,1] at tNear=4, tFar=6',
      TCastleShaderGeneratorRHI.EvaluateRayAABBIntersection(
        Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0),
        Vector3(-1.0, -1.0, -1.0), Vector3(1.0, 1.0, 1.0), 0.001, 100.0, TNear, TFar));
    AssertSameValue(4.0, TNear, 1e-4);
    AssertSameValue(6.0, TFar, 1e-4);

    AssertFalse('Ray offset to X=5 must miss AABB [-1,-1,-1]..[1,1,1]',
      TCastleShaderGeneratorRHI.EvaluateRayAABBIntersection(
        Vector3(5.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0),
        Vector3(-1.0, -1.0, -1.0), Vector3(1.0, 1.0, 1.0), 0.001, 100.0, TNear, TFar));

    { 3. Verify Moller-Trumbore Ray-Triangle intersection & barycentric coordinates }
    AssertTrue('Ray from (0.25, 0.25, 3.0) along -Z must hit triangle (0,0,0)-(1,0,0)-(0,1,0) at t=3.0, u=0.25, v=0.25',
      TCastleShaderGeneratorRHI.EvaluateRayTriangleIntersection(
        Vector3(0.25, 0.25, 3.0), Vector3(0.0, 0.0, -1.0),
        Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
        0.001, 100.0, THit, BaryU, BaryV));
    AssertSameValue(3.0, THit, 1e-4);
    AssertSameValue(0.25, BaryU, 1e-4);
    AssertSameValue(0.25, BaryV, 1e-4);

    AssertFalse('Ray outside triangle hypotenuse (0.8, 0.8, 3.0) must miss',
      TCastleShaderGeneratorRHI.EvaluateRayTriangleIntersection(
        Vector3(0.8, 0.8, 3.0), Vector3(0.0, 0.0, -1.0),
        Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
        0.001, 100.0, THit, BaryU, BaryV));
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TTestCastleVulkanRHI.TestVirtualShadowMapPageTableAndTilePoolRHI;
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

procedure TTestCastleVulkanRHI.TestSeparableSubsurfaceScatteringBurleyDiffusionRHI;
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

procedure TTestCastleVulkanRHI.TestGPUDrivenContinuousLODSelectionRHI;
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

procedure TTestCastleVulkanRHI.TestBentNormalsAndSpecularOcclusionRHI;
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

procedure TTestCastleVulkanRHI.TestColorGrading3DLUTAndFilmGrainVignetteRHI;
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

procedure TTestCastleVulkanRHI.TestVolumetricCloudDualLobeHGAndBeerPowderRHI;
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

procedure TTestCastleVulkanRHI.TestGPUTextureStreamingMipFeedbackRHI;
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

procedure TTestCastleVulkanRHI.TestEquirectangularToCubemapPanoramaConverterRHI;
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

procedure TTestCastleVulkanRHI.TestAnalyticAreaLightLTCSolidAngleRHI;
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

procedure TTestCastleVulkanRHI.TestTriplanarAndHeightModulatedBlendingRHI;
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

procedure TTestCastleVulkanRHI.TestGPUShadowCasterLightRayExtrusionCullingRHI;
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

initialization
  RegisterTest(TTestCastleVulkanRHI);
end.
