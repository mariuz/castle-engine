{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

{ Test CastleInternalRHI and production Vulkan / OpenGL RHI backend subsystems. }
unit TestCastleVulkanRHI;

{$I ../../../src/common_includes/castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)} X, Xlib, {$endif}
  CastleTester, CastleUtils, CastleVectors, CastleColors, CastleRectangles,
  CastleBoxes, CastleFrustum, CastleTimeUtils,
  CastleApplicationProperties, CastleImages, CastleGLImages, CastleFonts,
  CastleTextureFont_Default3d_Sans,
  CastleInternalRHI, CastleInternalVulkan, CastleInternalVulkanMemory,
  CastleInternalVulkanWSI, CastleInternalShaderCompiler, CastleInternalRHI_Vulkan,
  CastleInternalRHI_OpenGL,
  CastleInternalShaderRHI, CastleInternalBatch2DRHI, CastleInternalRenderer,
  CastleRendererInternalShader, CastleRendererInternalLights, CastleRendererInternalTextureEnv, X3DNodes, X3DFields, X3DCameraUtils,
  CastleInternalGeometryArrays, CastleSceneInternalShape, CastleInternalOcclusionCulling,
  CastleTransform, CastleSceneCore, CastleScene, CastleProjection, CastleViewport, CastleScreenEffects, CastleRenderOptions, CastleWindow,
  CastleUIControls, CastleControls, CastleInternalInspector,
  CastleVideos, CastleInternalBackgroundRenderer, CastleInternalGLShadowVolumes,
  CastleInternalScreenEffects,
  CastleGLShaders, CastleGLUtils, CastleGLVersion, CastleRenderPrimitives, CastleShapes, CastleRenderContext,
  CastleShapeInternalShadowVolumes, CastleShapeInternalRenderShadowVolumes,
  CastleInternalBatchShapes, CastleInternalShapesRenderer,
  CastleTransformManipulate, CastleDebugTransform, CastleInternalPhysicsVisualization,
  CastleInternalCompositeImage, CastleFilesUtils, CastleUriUtils,
  CastleInternalGLCubeMaps, CastleInternalSphericalHarmonics,
  CastleTerrain, CastleComponentSerialize, CastleParameters, CastleFlashEffect,
  CastleBehaviors, CastleLivingBehaviors, CastleCameras, CastleSoundEngine,
  CastleInternalDirectoryInformation, ToolManifest, CastleInternalRenderDoc;


{ Resolves a repository-relative file path across local, CI, and app-bundle CWDs. }
function ResolveRepoExampleFile(const ARelPath: String): String;

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
    procedure TestWeightedBlendedOrderIndependentTransparencyRHI;
    procedure TestGPUMeshletConeAndSphereCullingRHI;
    procedure TestInlineRayQueryAndBVHIntersectionRHI;
    procedure TestHardwareMeshShaderStageAndTaskGroupsRHI;
    procedure TestRayTracingPipelineStagesAndBarycentricNormalRHI;
    procedure TestVulkanShaderBindingTableAlignmentAndDispatchRHI;
    procedure TestVulkanAccelerationStructureCompactionAndTLASRHI;
    procedure TestVulkanMaterialBinnerHistogramAndOffsetsRHI;
    procedure TestVulkanHiZPyramidGeneratorDownsampleAndDispatchRHI;
    procedure TestCameraEV100AndExposureMultiplierRHI;
    procedure TestVulkanAutoExposureHistogramTrimmedEVAndDispatchRHI;
    procedure TestVulkanFramePacerWaitMicrosecondsAndTelemetryRHI;
    procedure TestRenderOptionsNextGenPropertiesAndHashingRHI;
    procedure TestViewportCameraEV100AndNextGenPropertiesRHI;
    procedure TestVulkanWSINativeSurfaceDescAndExtensionsRHI;
    procedure TestCreateVulkanSurfaceAcrossAllOSBackendsRHI;
    procedure TestCastleWindowVulkanSurfaceCreationAndLifecycleRHI;
    procedure TestBatch2DRendererMultiBatchCoalescingAndFlushCounterRHI;
    procedure TestAllThreeVulkanExampleManifestsAndPipelineCacheGuardRHI;
    procedure TestBuildShapeRHIPushConstantsObjectParamsPackingRHI;
    procedure TestViewportNextGenToneMappingHDRTargetPreparationRHI;
    procedure TestShaderObjectParamsMacrosAndUnpackingRHI;
    procedure TestVulkanBeginEndFrameHeadlessAndWindowLifecycleRHI;
    procedure TestDefault3DShadersConsumeCastleObjectParamsRHI;
    procedure TestCastleContainerAndUIControlsHeadlessVulkanRenderRHI;
    procedure TestProjectionHelpersNilSafeRenderContextRHI;
    procedure TestCastleScenePrepareResourcesHeadlessVulkanRHI;
    procedure TestCastleViewport3DSceneHeadlessVulkanRenderRHI;
    procedure TestCastleViewportWireframeAndShadowVolumesHeadlessVulkanRHI;
    procedure TestRendererSceneUniformBlockUploadRHI;
    procedure TestShapeCacheMaterialUniformBlockAndBindlessIndexRHI;
    procedure TestVulkan3DSceneExampleSourceVerificationRHI;
    procedure TestBindlessManagerMaterialTableAndAutoSSBOFlushRHI;
    procedure TestShapeAutoBindlessTextureAndMaterialRegistrationRHI;
    procedure TestViewportMultiShapeBindlessMaterialIndicesRHI;
    procedure TestRendererSceneAndLightsDescriptorSetRHI;
    procedure TestShapeCacheMaterialAndSkinningDescriptorSetsRHI;
    procedure TestViewportRenderBindsSet0Set1DescriptorSetsRHI;
    procedure TestRendererBuildShapePipelineDescAndCachingRHI;
    procedure TestViewportRenderBindsGraphicsPipelineAndWireframePSORHI;
    procedure TestViewportOpaqueAndBlendedPipelineStatesRHI;
    procedure TestShapeCacheEnsureRHIShadersPermutationMaskRHI;
    procedure TestUploadRHIMaterialAutoSpecializesShapeShadersRHI;
    procedure TestShadowMapDepthOnlyPipelineSpecializationRHI;
    procedure TestEnsureBatch2DRendererAndStandaloneDrawableImageDrawRHI;
    procedure TestCastleImageControlAndButtonHeadlessVulkanRenderRHI;
    procedure TestDrawableImageBlendModesAndRotationBatch2DRHI;
    procedure TestDrawPrimitive2DFanAndLineLoopExpansionAndShadersRHI;
    procedure TestRenderUnlitMeshShadersPushConstantsAndDepthStateRHI;
    procedure TestViewportMainSceneScreenEffectRHIPipelineAndRenderRHI;
    procedure TestViewport3DSkyboxAndImageBackgroundRotationOnlyViewMatrixRHI;
    procedure TestViewportStencilShadowVolumesEndToEndMultiPassAndMeshPSORHI;
    procedure TestSceneUpdateGeneratedTexturesRenderedTextureAndShadowMapRHI;
    procedure TestViewportOcclusionCullingEndToEndAndBoxUnlitMeshPSORHI;
    procedure TestViewportDynamicBatchingMergesShapesAndUploadsRHIBuffersRHI;
    procedure TestShapeExtractRHIMaterialTexturesAllResourceTypesAndOnDemandPrepareRHI;
    procedure TestViewportSkinNodeGPUSkinningEndToEndAndJointUploadRHI;
    procedure TestCastleMask2DAnd3DStencilMaskingEndToEndRHI;
    procedure TestTextureSizingHelpersNilSafeInPureRHIModeRHI;
    procedure TestCastleTextAndPrimitivesHeadlessVulkanRenderRHI;
    procedure TestPointSetLineSetForceUnlitAndPerVertexColorSpecializationRHI;
    procedure TestSolidWireframeSilhouettePolygonOffsetAndFogShaderRHI;
    procedure TestTextureResourceRHISamplerFilterWrapAndAnisotropyRHI;
    procedure TestShapeMaterialDescriptorSetBindsRHISamplersRHI;
    procedure TestTextureTransformAndImageTransformRepeatShiftSpecializationRHI;
    procedure TestClipPlaneNodeSlicingAndDiscardSpecializationRHI;
    procedure TestEnvironmentLightIBLCubemapAndBrdfLutSpecializationRHI;
    procedure TestShadowMapReceiverProjectorMatrixAndSceneDescriptorBindingRHI;
    procedure TestTextureCoordinateGeneratorAndBounds2DSpecializationRHI;
    procedure TestEffectNodePlugFunctionsAndPointPropertiesSpecializationRHI;
    procedure TestViewportUpdateGeneratedTexturesOffscreenSceneRenderRHI;
    procedure TestComposedShaderNodeFullCustomShaderAndLegacyUpgradeRHI;
    procedure TestPhongMaterialOcclusionSpecularPureEmissiveAndCommonSurfaceShaderRHI;
    procedure TestTwoSidedGeometryFrontFacingNormalFlipAndNegativeScaleWindingRHI;
    procedure TestEffectAndComposedShaderCustomUniformUBOAndTextureBindingRHI;
    procedure TestEffectShaderLibrariesEyeWorldSpaceAndCameraMatrixAliasesRHI;
    procedure TestLinePropertiesNodeAndRenderContextDynamicLineWidthRHI;
    procedure TestTangentSpaceNormalMappingAndParallaxBumpMappingSpecializationRHI;
    procedure TestFogCoordinateVolumetricFogAndCustomShaderVertexAttributesRHI;
    procedure TestColorSpaceLinearGammaCorrectionAndFilmicToneMappingSpecializationRHI;
    procedure TestBlendModeNodeRenderOptionsBlendFactorsAndDepthFuncPipelineRHI;
    procedure TestColorNodeReplaceModeAndRenderOptionsLightingDisabledUnlitRHI;
    procedure TestProjectedTextureCoordinateAndMirrorPlaneTexGenSpecializationRHI;
    procedure TestShadowSamplingModesPCFAndVSMSpecializationRHI;
    procedure TestMultiClipPlanesExtractionAndSpecializationRHI;
    procedure TestSecondaryUVChannelAndMaterialTextureMappingSpecializationRHI;
    procedure TestMultiShadowMapLightsSlotRoutingAndSceneDescriptorSetRHI;
    procedure TestRenderOptionsColorChannelsWriteMaskPipelineRHI;
    procedure TestVarianceShadowMapCasterPassMomentShaderAndPipelineRHI;
    procedure TestMultiTextureCombineModesAndTextured3DTextSpecializationRHI;
    procedure TestMultiTextureTransformSecondaryUVSpecializationRHI;
    procedure TestGeneratedShadowMapVSMAndCubeMapDepthAttachmentRHI;
    procedure TestCubeMapAnd3DTextureBaseColorAndBounds3DSpecializationRHI;
    procedure TestTextureNodeShaderTextureAndLightNodeEffectsSpecializationRHI;
    procedure TestMultiTextureEnvScaleDot3ComplementAndAlphaReplicateRHI;
    procedure TestSteepParallaxSelfShadowingSpecializationRHI;
    procedure TestExtendedEffectNodePlugsVertexMaterialLightingFogAndEndRHI;
    procedure TestTextureCoordinate3D4DAndTextureTransform3DSpecializationRHI;
    procedure TestSpotLightBeamWidthExponentAndPlugLightScaleRHI;
    procedure TestPhongSpecularShininessAmbientTexturesAndPlugsRHI;
    procedure TestEnvironmentLightDualCubemapIntensityAndLinearEmissiveDecodeRHI;
    procedure TestSeparateSpecularShininessTexturesAndCommonSurfaceAlphaTextureRHI;
    procedure TestMultiTextureThreeAndFourStageCombinePipelineRHI;
    procedure TestLightsRendererMaxLightsPerShapeAndGlobalSceneDeduplicationRHI;
    procedure TestMultiEffectChainedPlugDeduplicationAndInvocationRHI;
    procedure TestAdditionalShaderPlugsLightAmbientSteepShadowTextureApplyAddLightRHI;
    procedure TestUserEffectDoublePrecisionAndMultiValueArrayUniformPackingRHI;
    procedure TestScreenEffectFloatLibraryFunctionsAndCustomVertexShaderRHI;
    procedure TestScreenEffectCustomUniformUBOAndTextureBindingRHI;
    procedure TestViewpointMirrorPlaneUniformsAndTexGenSpecializationRHI;
    procedure TestGeometryShaderComposedAndEffectNodePlugsAndPipelineRHI;
    procedure TestImageTextureAndMovieTextureFlipVerticallyInMemoryUploadRHI;
    procedure TestCommonSurfaceShaderMultiDiffuseAlphaAndNormalMapHeightGateRHI;
    procedure TestVulkanSamplerCreateInfoTranslationAndTexturePropertiesMipmapControlRHI;
    procedure TestCompositeCubeMapAnd3DTextureMipmapChainUploadRHI;
    procedure TestPhongSpecularAndAmbientTextureLinearColorSpaceDecodeRHI;
    procedure TestAutomaticTextureMipmapGeneration2DCubeAnd3DRHI;
    procedure TestSubresourceImageViewAndGeneratedCubeMapPerFaceLayerRenderRHI;
    procedure TestVRML1MaterialTextureTransformAndTwoSidedMaterialExtractionRHI;
    procedure TestRenderedAndGeneratedCubeMapInitialImageAndMovieTextureMipmapsRHI;
    procedure TestActiveRenderingAttachmentFormatsAndSampleCountPipelineRHI;
    procedure TestMeshRendererGeometryShaderPushConstantsAndAnimatedMovieTextureFrameRHI;
    procedure TestDrawableImageRenderToImageAndDrawFromRHI;
    procedure TestDrawableImageRepeatWrapSamplersAndBatch2DOffscreenFormatsRHI;
    procedure TestDrawPrimitive2DLineWidthPointSizeAndActiveRenderingFormatsRHI;
    procedure TestDrawableImageClipLineAlphaTestAndCustomBlendFactorsRHI;
    procedure TestSaveScreenActiveOffscreenAttachmentAndBatchFlushRHI;
    procedure TestGLVideo3DAndGLVideo2DAndTexture2DClampToEdgeRHI;
    procedure TestGLSLProgramAndDrawableImageCustomShaderAndUniformsRHI;
    procedure TestCastleFontDistanceFieldBitmapFontAndGrayscaleTreatAsAlphaRHI;
    procedure TestTextureMemoryProfilerRHIAndImageGLFormatNilSafeRHI;
    procedure TestGLSLScreenEffectAndViewportSSAOSSRPostProcessingRHI;
    procedure TestCastleMaskAndInternalClearColorsByDrawStencilRHI;
    procedure TestRenderToTextureRenderBeginFollowsAndInternalControlRectIgnoreRHI;
    procedure TestRenderControlToImageAndOffscreenClearAttachmentsRHI;
    procedure TestGLTextureScaleDownscalingAndComposedCubeMapResizeRHI;
    procedure TestSkinNodeGpuTextureJointResourceAndAutoUploadRHI;
    procedure TestFloatAndGPUCompressedTextureUploadRHI;
    procedure TestRenderedGeneratedCubeAndShadowMapMemoryProfilerRHI;
    procedure TestSHVectorGLCaptureOffscreenRHI;
    procedure TestRendererCacheTextureSharingAndRefCountRHI;
    procedure TestSceneFreeResourcesAndMovieTexturePostUnloadPlaybackRHI;
    procedure TestSceneAndViewportPrepareResourcesPipelinePrebakeRHI;
    procedure TestViewportSubRectScreenEffectsAndOuterPassRHI;
    procedure TestX3DGLSLProgramSetupUniformsTextureFieldsRHI;
    procedure TestCastleInspectorAndGLInformationStringRHI;
    procedure TestGLSLScreenEffectAndViewportSSAOSSRUniformsRHI;
    procedure TestViewportChildSceneScreenEffectsAndDynamicToggleRHI;
    procedure TestViewportPrepareShadowVolumesAnd2DUIControlsRHI;
    procedure TestWireframeEffectsAndDualSlotShaderCacheRHI;
    procedure TestPointSizeScalingAndLinePropertiesStippleRHI;
    procedure TestTransformManipulateDebugGizmosAndColliderWireframeRHI;
    procedure TestConstantBlendFactorsAndBlendConstantsDynamicStateRHI;
    procedure TestInputOnlyShaderEventsAndLiveRouteUniformsRHI;
    procedure TestLitPointSetLineSetWithNormalsAndDynamicUnlitEmissiveRHI;
    procedure TestViewportShadowVolumesMultiPassSet0SlotsAndRealLavapipeStencilRHI;
    procedure TestViewportOcclusionCullingInPassHostQueryResetRHI;
    procedure TestGPUCompressedImageDecompressDXT1DXT3DXT5AndFlipVerticalRHI;
    procedure TestRealLavapipeSubViewportScissorClearAndBottomUpGrabTextureRHI;
    procedure TestCastleWindowVulkanSwapchainPassSurfaceNegotiationAndStencilDepthRHI;
    procedure TestContainerSaveScreenAndSaveScreenRgbaOutOfFrameRealLavapipeRHI;
    procedure TestBuiltInSPIRVCoreShadersAndRealLavapipeDrawPrimitive2DRHI;
    procedure TestRealLavapipeBatch2DDrawableImageFontAlphaClipAndMultiPassRHI;
    procedure TestRealLavapipeRenderUnlitMeshDepthAndOcclusionCullingRHI;
    procedure TestRealLavapipe3DViewportUnlitAndLitMeshSceneRHI;
    procedure TestRealLavapipe3DViewportTexturedMeshAndAlphaCutoffRHI;
    procedure TestRealLavapipeViewportScreenEffectPostProcessingRHI;
    procedure TestVulkanSwapchainCompositeAlphaAndWSIExtensionDiscoveryRHI;
    procedure TestRealVulkanHeadlessSurfaceLiveSwapchainPresentAndResizeRHI;
    procedure TestRealCastleWindowPureVulkanOpenRenderResizeSaveScreenRHI;
    procedure TestRealLavapipeSecondaryCommandBuffersAndWorkerCommandPoolParallelDrawRHI;
    procedure TestRealLavapipeViewportParallelCommandRecording3DSceneParityRHI;
    procedure TestRealLavapipeAsyncTransferQueueTimelineSemaphoreUploadAndRenderRHI;
    procedure TestRealLavapipeBindlessTextureAndMaterialSSBOMultiDrawRHI;
    procedure TestRealLavapipeComputeCullerAndDrawIndexedIndirectCountRHI;
    procedure TestRealLavapipeMaterialBinnerAndBindlessGpuDrivenPipelineRHI;
    procedure TestRealLavapipeRenderGraphPhysicalMemoryAliasingAndDeadPassCullingRHI;
    procedure TestRealLavapipeHDRBloomLuminanceHistogramAndTonemapPerceptualDiffRHI;
    procedure TestRealLavapipeFullRenderGraphGTAOSSRAndPostProcessPipelineRHI;
    procedure TestVulkanValidationLayerDebugMessengerAndZeroErrorGateRHI;
    procedure TestRealOpenGLVsVulkanSideBySideVisualRegressionSuiteRHI;
    procedure TestShaderAndPipelineCachePackageBundlingAndDataSeedRHI;
    procedure TestVulkanDebugUtilsObjectNamingLabelsAndRenderGraphScopesRHI;
    procedure TestRealLavapipe3DPBRShadowMapsAndGpuSkeletalSkinningRHI;
    procedure TestRealOpenGLVsVulkanPBRMetallicRoughnessVisualParityRHI;
    procedure TestRealLavapipeIBLComputeBrdfLutPrefilterAndIrradianceCubemapRHI;
    procedure TestRealLavapipeSkyboxBackgroundCubemap3DTextureAndMultiTextureRHI;
    procedure TestRealLavapipeEnvironmentLightSplitSumIBL3DViewportRHI;
    procedure TestSharedDeviceMultiControlSwapchainSurfacesHeadlessAndSimulatedRHI;
    procedure TestRealVulkanMultiControlHeadlessSurfacesSharedDevice3DAnd2DRHI;
    procedure TestRealX11MultiChildWidgetSurfacesSharedVulkanDevicePresentAndResizeRHI;
    procedure TestOpenGLRHIShaderTranslationHeadlessComputeIndirectAndQueryPoolRHI;
    procedure TestRealOpenGLRHIComputeSSBOStorageImageIndirectMultiDrawAndQueriesRHI;
    procedure TestUnifiedRenderGraphOpenGLVsVulkanComputeAndGraphicsBackendParityRHI;
    procedure TestBufferDeviceAddressAccelerationStructureSBTAndMeshShaderHeadlessRHI;
    procedure TestRealLavapipeHardwareBLASCompactionTLASRayQueryTraceRaysAndSoftwareLBVHParityRHI;
    procedure TestRealLavapipeMeshShaderDrawMeshTasksIndirectAndSoftwareMeshletFallbackParityRHI;
    procedure TestMemoryPoolDefragmentationHeadlessAndRealGpuBufferRelocationRHI;
    procedure TestMultiWindowSharedVulkanDeviceSwapchainsResizeAndTeardownRHI;
    procedure TestRuntimeRenderBackendHotSwitchOpenGLToVulkanToOpenGLVisualParityRHI;
    procedure TestRenderBackendCLIAndEnvOverrideAndCrossStageEffectLayoutRHI;
    procedure TestRuntimeShadercAndGlslangCustomEffectAndTerrainVisualParityRHI;
    procedure TestFlagshipDemosExploreCastlePlatformerAndTerrainEndToEndVulkanRHI;
    procedure TestHardwareVendorProfilesNvidiaAmdIntelAlignmentAndQueueQuirksRHI;
    procedure TestMoltenVKPortabilitySubsetNegotiationAndPipelineAdaptationRHI;
    procedure TestAndroidWSISurfacePreTransformCompositeAlphaAndApkCacheBundlingRHI;
    procedure TestLiveHardwareVendorWSIAndOffscreenValidationMatrixRHI;
    procedure TestAutoExitFramesAndCaptureScreenshotCLIFlagsRHI;
    procedure TestPerLightShaderEffectsUniformScopingAndVisualParityRHI;
    procedure TestBroaderExampleCatalogVulkanSmokeAndOpenGLVisualParitySweepRHI;
    procedure TestUpstreamPRSliceManifestAndDocumentationCompletenessRHI;
    procedure TestExtractedSPIRVBinariesExternalOverrideAndModularUnitsRHI;
    procedure TestModularTestSuiteAndUpstreamSlice9ExperimentalIsolationRHI;
  private
    FPhase111ForwardSubPassCounter: Integer;
    FCapturedWarnings: TStringList;
    FRenderedShapeCount: Cardinal;
    FRenderFromViewpointCalls: Cardinal;
    FShadowVolumeOnePassCalls: Cardinal;
    FShadowVolumeCasterCalls: Cardinal;
    FRenderGraphPassExecCount: Cardinal;
    FSHCaptureRenderCalls: Cardinal;
    FParallelTestPassInfo: TRHIRenderingInfo;
    FParallelTestPipeline: TRHIPipeline;
    FParallelTestQuadVBOs: array[0..3] of TRHIBuffer;
    FParallelTestHeadlessMode: Boolean;
    procedure Phase111ForwardSceneCallback(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure Phase111AliasPass0Callback(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure Phase111AliasPass5Callback(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure CaptureWarning(const Category, S: String);
    procedure DummyRenderShapeCallback(const Shape: TCollectedShape;
      const Params: TRenderParams; const PassParams: TRenderOnePassParams);
    procedure DummyRenderFromViewpointCallback(const RenderCamera: TRenderingCamera);
    procedure DummyShadowVolumeOnePassCallback(const Params: TRenderParams;
      const PassParams: TRenderOnePassParams);
    procedure DummyShadowVolumeCasterCallback(const Params: TRenderParams);
    procedure DummyRenderGraphPassCallback(const AGraph: TRHIRenderGraph;
      const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
    procedure DummySHCaptureRenderCallback(const RenderParams: TRenderParams);
    procedure ParallelQuadWorkerCallback(const AWorkerIndex: Cardinal;
      const ACommandList: TVulkanRHICommandList);
    function CreateHeadlessSurfaceForTest(const AInstance: VkInstance): VkSurfaceKHR;
    procedure CollectSingleTextureNodeCallback(Node: TX3DNode);
  private
    FCollectedSingleTexNodes: TX3DNodeList;
  end;


implementation

function ResolveRepoExampleFile(const ARelPath: String): String;
var
  EnvDir, CurDir, Candidate: String;
  Step: Integer;
begin
  if FileExists(ARelPath) then
    Exit(ExpandFileName(ARelPath));
  if FileExists('../' + ARelPath) then
    Exit(ExpandFileName('../' + ARelPath));

  EnvDir := GetEnvironmentVariable('CASTLE_ENGINE_PATH');
  if EnvDir <> '' then
  begin
    Candidate := InclPathDelim(EnvDir) + ARelPath;
    if FileExists(Candidate) then
      Exit(ExpandFileName(Candidate));
  end;

  CurDir := InclPathDelim(ExtractFilePath(ExpandFileName(ParamStr(0))));
  for Step := 1 to 10 do
  begin
    Candidate := CurDir + ARelPath;
    if FileExists(Candidate) then
      Exit(ExpandFileName(Candidate));
    CurDir := CurDir + '../';
  end;

  Result := ARelPath;
end;

{ TTestCastleVulkanRHI }

{$define read_implementation}
{$I testcastlevulkanrhi_part1_core_2d.inc}
{$I testcastlevulkanrhi_part2_pbr_post_wsi.inc}
{$I testcastlevulkanrhi_part3_scene_x3d_a.inc}
{$I testcastlevulkanrhi_part4_scene_x3d_b.inc}
{$I testcastlevulkanrhi_part5_scene_x3d_c.inc}
{$I testcastlevulkanrhi_part6_live_gpu_a.inc}
{$I testcastlevulkanrhi_part7_live_gpu_b.inc}
{$I testcastlevulkanrhi_part8_vendors_slices.inc}
{$undef read_implementation}

initialization
  RegisterTest(TTestCastleVulkanRHI);
end.
