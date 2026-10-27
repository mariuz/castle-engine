# Agent Handover & Engineering Guide (`castle-engine` Vulkan Renderer)

This document provides essential architecture context, build/test instructions, hardware compatibility rules, and roadmap status for AI coding agents working on the Castle Game Engine Vulkan RHI renderer.

---

## 1. Repository & Git Workflow Rules

- **Primary Engine Repository**: `e:\Work\castle-engine` (WSL path: `/mnt/e/Work/castle-engine`)
- **Companion Quake 1 Demo Workspace**: `e:\Work\castle-quake1` (WSL path: `/mnt/e/Work/castle-quake1`)
- **Active Branch**: `vulkan-renderer`
- **Git Remote Rule**:
  - `origin` points to `https://github.com/mariuz/castle-engine.git`
  - `upstream` points to `https://github.com/castle-engine/castle-engine.git`
  - **ALWAYS push ONLY to `origin vulkan-renderer`** (`git push origin vulkan-renderer`). Never push to `upstream`.
- **Clean Working Tree Policy**:
  - Before finishing a task or creating a git commit, always remove temporary FPC build outputs (`*.o`, `*.ppu`, `*.rsj`, `tests/castle_tester_standalone`, `tools/internal/generate_vulkan_api/vkxml2pas`):
    ```bash
    wsl bash -c "rm -f tests/castle_tester_standalone tools/internal/generate_vulkan_api/vkxml2pas && find . -name '*.o' -o -name '*.ppu' -o -name '*.rsj' | xargs rm -f"
    ```

---

## 2. Architecture & Key Source Files

All roadmap milestones and design decisions are tracked in [`PLAN.md`](file:///e:/Work/castle-engine/PLAN.md).

| File | Responsibility |
| :--- | :--- |
| [`PLAN.md`](file:///e:/Work/castle-engine/PLAN.md) | Master architectural specification and Phase 1–6 checklist. Keep this updated as items are completed. |
| [`tools/internal/generate_vulkan_api/vkxml2pas.dpr`](file:///e:/Work/castle-engine/tools/internal/generate_vulkan_api/vkxml2pas.dpr) | Pure Pascal Khronos `vk.xml` registry parser and header generator (inspired by BeRo's PasVulkan `vkxml2pas`). |
| [`src/base_rendering/vulkan/castleinternalvulkan.pas`](file:///e:/Work/castle-engine/src/base_rendering/vulkan/castleinternalvulkan.pas) | **Auto-generated** flat C-ABI Pascal bindings for Vulkan 1.0–1.4 + extensions. **Do not edit manually**—always add needed enums/structs/commands to `vkxml2pas.dpr` and regenerate. |
| [`src/base_rendering/vulkan/castleinternalvulkanmemory.pas`](file:///e:/Work/castle-engine/src/base_rendering/vulkan/castleinternalvulkanmemory.pas) | `TCastleVulkanMemoryAllocator`: Pooled `VkDeviceMemory` sub-allocator (inspired by PasVulkan's `TpvVulkanMemoryManager` & AMD VMA). Enforces Windows WDDM's 4096 `maxMemoryAllocationCount` ceiling, separates Linear (`VkBuffer`) vs. Non-Linear (`VkImage`) pools per `memoryTypeIndex` (`bufferImageGranularity`), performs $O(1)$ free-block coalescing, supports `VK_KHR_dedicated_allocation`, aligns non-coherent flushes (`nonCoherentAtomSize`), and provides per-frame transient ring buffers (`TCastleVulkanFrameRingBuffer`). |
| [`src/base_rendering/vulkan/castleinternalvulkanwsi.pas`](file:///e:/Work/castle-engine/src/base_rendering/vulkan/castleinternalvulkanwsi.pas) | Cross-platform Window System Integration (Win32, Xlib, Wayland, Android, macOS/iOS Metal/MoltenVK, Nintendo Switch `VK_NN_vi_surface`) and `SelectOptimalRenderBackend`. |
| [`src/base_rendering/vulkan/castleinternalshadercompiler.pas`](file:///e:/Work/castle-engine/src/base_rendering/vulkan/castleinternalshadercompiler.pas) | Runtime GLSL `#version 450` to SPIR-V compilation via `libshaderc`, SHA-based `.spv` disk caching, core shader pre-warming, and pure Pascal SPIR-V binary reflection & descriptor validation (`InspectSPIRVBytecode`, `ValidateSPIRVDescriptorBindings`). |
| [`src/base_rendering/rhi/castleinternalrhi.pas`](file:///e:/Work/castle-engine/src/base_rendering/rhi/castleinternalrhi.pas) | Backend-agnostic Render Hardware Interface (`TRHIDevice`, `TRHICommandList`, `TRHIBuffer`, `TRHITexture`, `TRHISampler`, `TRHIShaderModule`, `TRHIDescriptorSetLayout`, `TRHIDescriptorSet`, `TRHIPipeline`, `TRHIComputePipeline`, `TRHIQueryPool`, `TRHIRenderGraphPass`, `TRHIRenderGraph`, `CompareImagesPerceptualDiff`). |
| [`src/base_rendering/vulkan/castleinternalrhi_vulkan.pas`](file:///e:/Work/castle-engine/src/base_rendering/vulkan/castleinternalrhi_vulkan.pas) | Full Vulkan RHI implementation: `TVulkanRHIDevice`, `TVulkanRHICommandList`, `TVulkanDescriptorPoolAllocator` (growable + per-frame transient descriptor pools), `TCastleVulkanStagingUploader` (async staging upload ring buffer + dedicated DMA transfer queue), `TCastleVulkanBindlessTextureManager` (bindless texture & sampler indexing), hardware MSAA & single-pass attachment resolve, `TVulkanRHIComputePipeline` (`vkCmdDispatch` / `vkCmdDispatchIndirect`), `VK_EXT_extended_dynamic_state` & `VK_KHR_synchronization2` + `TCastleVulkanTimelineSemaphore`, `TVulkanRHIQueryPool` & `TCastleVulkanTimestampProfiler`, `TCastleVulkanComputeCuller` (GPU frustum/distance/Hi-Z occlusion culling), `TCastleVulkanIBLGenerator` (Split-Sum BRDF LUT + cubemap prefiltering + L2 SH irradiance), `TCastleVulkanClusteredLightCuller` (3D Clustered Forward+ 256-light compute culling), `TCastleVulkanShadowAtlas` (4-cascade CSM + positional shadow atlas), `TCastleVulkanHDRPostProcessor` (`pfRGBA16_Float` HDR target, 13-tap Karis downsample + 9-tap tent upsample bloom, 256-bin log-luminance histogram auto-exposure, Reinhard/ACES/AgX tonemapping), `TCastleVulkanGTAO` (compute GTAO + $5 \times 5$ cross-bilateral denoiser), `TCastleVulkanSSR` (Hi-Z mip-skipping screen-space reflections), `TCastleVulkanVolumetricFog` ($160 \times 90 \times 64$ 3D froxel volumetric & height fog), `TCastleVulkanTAA` (Halton $(2,3)$ camera jitter, `pfRG16_Float` velocity, YCoCg variance clipping & 5-tap Catmull-Rom TAA), `TCastleVulkanReflectionProbeManager` (box-projected parallax cubemap probes), `TCastleVulkanDecalManager` (OBB projected decals), `TCastleVulkanComputeParticles` (GPU compute particle simulation & indirect billboard draw), `TCastleVulkanWeightedBlendedOIT` (McGuire & Bavoil Weighted Blended OIT), `TCastleVulkanContactShadows` (screen-space raymarched contact shadows), `VK_KHR_dynamic_rendering` with Vulkan 1.1/1.2 `VkRenderPass`/`VkFramebuffer` fallback, `VK_EXT_graphics_pipeline_library` 4-part fast-link PSO caching, cross-vendor format negotiation (`NegotiateOptimalPixelFormat`), and fence-synchronized deferred resource deletion (`FlushDeferredDeletions`). |
| [`src/base_rendering/rhi/castlerendercontext_rhi.pas`](file:///e:/Work/castle-engine/src/base_rendering/rhi/castlerendercontext_rhi.pas) | Bridges CGE's `TRenderContext`, `TCastleViewport`, `TDrawableImage`, and `TCastleScene` rendering to `TRHIDevice`. |
| [`src/base_rendering/rhi/castleinternalshaderrhi.pas`](file:///e:/Work/castle-engine/src/base_rendering/rhi/castleinternalshaderrhi.pas) | Generates Vulkan GLSL `#version 450` shaders (`Set 0` frame/light/skinning UBOs, `Set 1` material textures & bindless texture array preamble `GenerateBindlessPreamble`, `Set 2` custom `Effect` uniforms, Push Constants, Cook-Torrance GGX PBR, Clustered Forward+ & CSM/Atlas PCF shadows, 13-tap Karis bloom downsample/upsample, 256-bin luminance histogram, Reinhard/ACES Filmic/AgX tonemapping, Compute GTAO + bilateral denoiser, Hi-Z SSR, 3D Froxel Volumetric Fog, Compute TAA Resolve, Box-Projected Reflection Probes, OBB Decal Projection, GPU Compute Particle Simulation, Weighted Blended OIT, and Screen-Space Contact Shadows) and auto-upgrades legacy OpenGL built-ins (`UpgradeLegacyGLSLBuiltIns`). |
| [`tests/code/testcases/testcastlevulkanrhi.pas`](file:///e:/Work/castle-engine/tests/code/testcases/testcastlevulkanrhi.pas) | `TTestCastleVulkanRHI`: 84 unit tests covering all Vulkan RHI subsystems in both headless simulation and hardware modes. |

---

## 3. Compiling & Running Unit Tests (WSL)

### 3.1 Running the Vulkan RHI Test Suite (`TTestCastleVulkanRHI`)
In WSL, GTK3 development headers are not installed, so `castle_tester_standalone` must be compiled with `-dCASTLE_WINDOW_XLIB` and linked against `/tmp/xlibs` (where unversioned `libXmu.so` and `libXxf86vm.so` symlinks are created):

```bash
wsl bash -c "mkdir -p /tmp/xlibs && ln -sf /usr/lib/x86_64-linux-gnu/libXmu.so.6 /tmp/xlibs/libXmu.so && ln -sf /usr/lib/x86_64-linux-gnu/libXxf86vm.so.1 /tmp/xlibs/libXxf86vm.so && fpc -Mobjfpc -Sh -Ci -Co -Cr -gl -dCASTLE_WINDOW_XLIB -Fl/tmp/xlibs @castle-fpc.cfg -Futools/common-code -Fitools/common-code -Futests/common-code -Fitests/common-code -Futests/code/tester-castle -Futests/code/testcases -Fitests/code/testcases tests/castle_tester_standalone.dpr && ./tests/castle_tester_standalone --console --filter=TTestCastleVulkanRHI*"
```

### 3.2 Regenerating `castleinternalvulkan.pas` from Khronos `vk.xml`
Whenever new Vulkan constants, enums, bitmasks, structs, or function pointers are needed:
1. Add their names to the `OrderedEnums*`, `OrderedStructs*`, or `OrderedCommands*` arrays in `tools/internal/generate_vulkan_api/vkxml2pas.dpr`.
2. Compile and run `vkxml2pas` in WSL (it reads `/usr/share/vulkan/registry/vk.xml` by default and writes `src/base_rendering/vulkan/castleinternalvulkan.pas`):
   ```bash
   wsl bash -c "fpc -Mobjfpc -Sh tools/internal/generate_vulkan_api/vkxml2pas.dpr && ./tools/internal/generate_vulkan_api/vkxml2pas && rm -f tools/internal/generate_vulkan_api/vkxml2pas tools/internal/generate_vulkan_api/*.o tools/internal/generate_vulkan_api/*.ppu"
   ```

---

## 4. Important Engineering & Testing Pitfalls to Keep in Mind

1. **Headless Unit-Test Mode (`TVulkanRHIDevice.CreateHeadless`)**:
   - In unit tests, `TVulkanRHIDevice.CreateHeadless` runs with `FDevice = nil` (simulated device) so tests can execute deterministically on CI/headless runners without a physical Vulkan ICD, or with a mock `PhysicalDevice` handle.
   - Always guard raw `vkCmd*` / `vkCreate*` / `vkDestroy*` calls with `if (FDevice <> nil) and Assigned(vk...)` or `if (FHandle <> nil) and Assigned(vkCmd...)`, and provide deterministic synthetic handles/counters for headless verification.
2. **FPC Range Checking (`-Cr`) in `AssertEquals`**:
   - Tests compile with `-Ci -Co -Cr -gl`. In FPC, `AssertEquals(Msg, Expected, Actual)` has overloads for `Integer` and `Int64`, but **not** unsigned `Cardinal` (`UInt32`).
   - Passing a `Cardinal` value `>= $80000000` (such as `VK_QUEUE_FAMILY_IGNORED = $FFFFFFFF`) directly to `AssertEquals` will trigger `ERangeError` at runtime if it resolves to the `Integer` overload. Always cast such values to `Int64(...)` in `AssertEquals`.
3. ** Vulkan Hardware & Driver Constraints (BeRo / PasVulkan Best Practices)**:
   - Never call `vkAllocateMemory` directly for individual buffers or images; always route through `FDevice.MemoryAllocator` (`TCastleVulkanMemoryAllocator`) to respect Windows' 4096 allocation limit.
   - Never destroy GPU resources (`VkBuffer`, `VkImage`, `VkImageView`, `VkDescriptorSet`, `TVulkanMemoryAllocation`) immediately while frames are in flight (`FDeferResourceDestruction = True`); always route through `DeferOrDestroy*` so they are retired after the frame slot's `InFlightFence` signals.
   - Never record `vkCmdCopyBuffer` or `vkCmdCopyBufferToImage` inside an active render pass instance (`VUID-vkCmdCopyBuffer-renderpass`).

---

## 5. Current Status & Roadmap in `PLAN.md`

- **Phases 1–67**: **COMPLETED** (100%).
- **Phase 68 (Complete RHI Pipeline, Shader & Topology Expansion for 2D Primitives, 3D Unlit Meshes & `MainScene` Screen Effects)**: **COMPLETED** (100%, 799/799 total engine tests and 230/230 `TTestCastleVulkanRHI` tests passing):
  - [x] **68.1. `DrawPrimitive2D` RHI Shaders, Blend Factor Mapping & `pmTriangleFan` / `pmLineLoop` Expansion (`castleglutils_draw_primitive_2d.inc`)** — Completed & tested (`TestDrawPrimitive2DFanAndLineLoopExpansionAndShadersRHI`).
  - [x] **68.2. `TCastleRenderUnlitMesh` RHI Shaders & State Synchronization (`castlerenderprimitives_render_unlit_mesh.inc`)** — Completed & tested (`TestRenderUnlitMeshShadersPushConstantsAndDepthStateRHI`).
  - [x] **68.3. `TCastleViewport.InternalExtraGetScreenEffectRHIPipeline` for `MainScene` Screen Effects (`castlescreeneffects.pas`, `castleviewport.pas`)** — Completed & tested (`TestViewportMainSceneScreenEffectRHIPipelineAndRenderRHI`).
- **Phase 69 (End-to-End 3D Skybox & 2D Image Background, Full Multi-Pass Stencil Shadow Volumes & Generated Texture Viewport/Projection Synchronization in Pure Vulkan RHI Mode)**: **COMPLETED** (100%, 802/802 total engine tests and 233/233 `TTestCastleVulkanRHI` tests passing):
  - [x] **69.1. 3D Skybox & 2D Image Background `RotationOnly` View Matrix & Color Clear (`castleinternalrenderer_renderer.inc`, `castleinternalbackgroundrenderer.pas`)** — Completed & tested (`TestViewport3DSkyboxAndImageBackgroundRotationOnlyViewMatrixRHI`).
  - [x] **69.2. Full Multi-Pass Stencil Shadow Volumes in `TCastleViewport`, `TGLShadowVolumeRenderer`, `TCastleRenderUnlitMesh` & `TRenderer.BuildShapePipelineDesc`** — Completed & tested (`TestViewportStencilShadowVolumesEndToEndMultiPassAndMeshPSORHI`).
  - [x] **69.3. Generated Texture Viewport & Projection Synchronization (`TRenderedTextureResource`, `TGeneratedShadowMapResource`, `GLCaptureCubeMapTexture`)** — Completed & tested (`TestSceneUpdateGeneratedTexturesRenderedTextureAndShadowMapRHI`).
- **Phase 70 (End-to-End Hardware Occlusion Query Culling, Dynamic Shape Batching & On-Demand Material Texture Resolution in Pure Vulkan RHI Mode)**: **COMPLETED** (100%, 805/805 total engine tests and 236/236 `TTestCastleVulkanRHI` tests passing):
  - [x] **70.1. Hardware Occlusion Query Bounding Box Unlit Mesh PSO & State Synchronization (`castleinternalocclusionculling.pas`, `castleinternalshapesrenderer.pas`, `castleviewport.pas`)** — Completed & tested (`TestViewportOcclusionCullingEndToEndAndBoxUnlitMeshPSORHI`).
  - [x] **70.2. Dynamic Shape Batching Appearance & Material Synchronization (`castleinternalbatchshapes.pas`)** — Completed & tested (`TestViewportDynamicBatchingMergesShapesAndUploadsRHIBuffersRHI`).
  - [x] **70.3. Universal & On-Demand Material Texture Resolution (`castleinternalrenderer_shape.inc`)** — Completed & tested (`TestShapeExtractRHIMaterialTexturesAllResourceTypesAndOnDemandPrepareRHI`).
- **Phase 71 (End-to-End GPU Skeletal Skinning, 2D/3D Stencil Masking & Nil-Safe Texture Sizing Helpers in Pure Vulkan RHI Mode)**: **COMPLETED** (100%, 808/808 total engine tests and 239/239 `TTestCastleVulkanRHI` tests passing):
  - [x] **71.1. End-to-End GPU Skeletal Skinning (`TSkinNode`, `TSkinnedRenderer`)** — Completed & tested (`TestViewportSkinNodeGPUSkinningEndToEndAndJointUploadRHI`).
  - [x] **71.2. End-to-End 2D & 3D Stencil Masking (`TCastleMask`, `TRenderContext.ApplyRHIStencilAndColorMask`, `TCastleBatch2DRenderer.Flush`, `DrawPrimitive2D`, `TRenderer.BuildShapePipelineDesc`)** — Completed & tested (`TestCastleMask2DAnd3DStencilMaskingEndToEndRHI`).
  - [x] **71.3. Nil-Safe Texture Sizing Helpers (`ResizeToTextureSize`, `IsTextureSized`, `IsTexture3DSized`, `IsCubeMapTextureSized`, `ResizeToCubeMapTextureSize`)** — Completed & tested (`TestTextureSizingHelpersNilSafeInPureRHIModeRHI`).
- **Phase 72 (End-to-End 3D Text, Per-Vertex Color, Unlit Point/Line Primitives, Solid-Color/Unlit Modes, Polygon Offset Depth Bias & Linear/Exponential Scene Fog in Pure Vulkan RHI Mode)**: **COMPLETED** (100%, 811/811 total engine tests and 242/242 `TTestCastleVulkanRHI` tests passing):
  - [x] **72.1. 3D Text Font Atlas Texture Resolution (`TCastleText`, `TTextNode.FontTextureNode`)** — Completed & tested (`TestCastleTextAndPrimitivesHeadlessVulkanRenderRHI`).
  - [x] **72.2. Solid-Color, Unlit & Point/Line Material Extraction (`rmSolidColor`, `Arrays.ForceUnlit`, `RenderOptions.Lighting = False`) & Polygon Offset Depth Bias (`weSolidWireframe`, `weSilhouette`)** — Completed & tested (`TestPointSetLineSetForceUnlitAndPerVertexColorSpecializationRHI`, `TestSolidWireframeSilhouettePolygonOffsetAndFogShaderRHI`).
  - [x] **72.3. Per-Vertex Color Specialization (`$100`), `gl_PointSize` & Linear/Exponential Scene Fog Shader Evaluation (`TFogNode`)** — Completed & tested (`TestPointSetLineSetForceUnlitAndPerVertexColorSpecializationRHI`, `TestSolidWireframeSilhouettePolygonOffsetAndFogShaderRHI`).
- **Phase 73 (Universal `TTexturePropertiesNode` / `TCastleRenderOptions` `TRHISampler` State, Material Descriptor Set Sampler Binding & `TTextureTransformNode` UV Transform Specialization in Pure Vulkan RHI Mode)**: **COMPLETED** (100%, 814/814 total engine tests and 245/245 `TTestCastleVulkanRHI` tests passing):
  - [x] **73.1. Universal `TRHISampler` Creation & Exposure Across All `TTextureResource` Classes (`TTextureResource.CreateRHISampler`)** — Completed & tested (`TestTextureResourceRHISamplerFilterWrapAndAnisotropyRHI`).
  - [x] **73.2. Material Descriptor Set Sampler Resolution & Binding (`TX3DRendererShape.ExtractRHIMaterialTextures`, `TShapeCache.BindMaterialTexturesToDescriptorSet`)** — Completed & tested (`TestShapeMaterialDescriptorSetBindsRHISamplersRHI`).
  - [x] **73.3. X3D `TTextureTransformNode` / `TMultiTextureTransformNode` UV Transform Specialization (`$200`)** — Completed & tested (`TestTextureTransformAndImageTransformRepeatShiftSpecializationRHI`).
- **Phase 74 (X3D `TClipPlaneNode` Slicing & Discard Specialization, `TEnvironmentLightNode` Split-Sum IBL & Receiver Shadow Map Sampling in Pure Vulkan RHI Mode)**: **COMPLETED** (100%, 817/817 total engine tests and 248/248 `TTestCastleVulkanRHI` tests passing):
  - [x] **74.1. X3D `TClipPlaneNode` (`State.ClipPlanes`) Slicing & Fragment Discard Specialization (`$400`)** — Completed & tested (`TestClipPlaneNodeSlicingAndDiscardSpecializationRHI`).
  - [x] **74.2. X3D `TEnvironmentLightNode` / `TCastleEnvironmentLight` Split-Sum IBL (`$800`, Set 1 Bindings 6 & 7)** — Completed & tested (`TestEnvironmentLightIBLCubemapAndBrdfLutSpecializationRHI`).
  - [x] **74.3. X3D Receiver Shadow Map Sampling (`$1000`, Set 0 Bindings 2..5 & `ProjectorMatrix`)** — Completed & tested (`TestShadowMapReceiverProjectorMatrixAndSceneDescriptorBindingRHI`).
- **Phase 75 (Procedural Texture Coordinate Generation, Custom X3D Shader Effects & `TPointPropertiesNode`, and End-to-End Offscreen Scene Rendering into Generated Textures in Pure Vulkan RHI Mode)**: **COMPLETED** (100%, 820/820 total engine tests and 251/251 `TTestCastleVulkanRHI` tests passing):
  - [x] **75.1. Procedural Texture Coordinate Generation (`TTextureCoordinateGeneratorNode` & Implicit `tgBounds2d`/`tgBounds3d` Specialization `$2000`)** — Completed & tested (`TestTextureCoordinateGeneratorAndBounds2DSpecializationRHI`).
  - [x] **75.2. Custom X3D Shader Effects (`TEffectNode` / `TEffectPartNode` `PLUG_*` & `TPointPropertiesNode` `gl_PointSize` Specialization `$4000`)** — Completed & tested (`TestEffectNodePlugFunctionsAndPointPropertiesSpecializationRHI`).
  - [x] **75.3. End-to-End Offscreen Scene Rendering into Generated Textures (`TCastleViewport.Update` -> `TCastleScene.UpdateGeneratedTextures`)** — Completed & tested (`TestViewportUpdateGeneratedTexturesOffscreenSceneRenderRHI`).
- **Phase 76 (X3D `TComposedShaderNode` Custom Shader Specialization & Legacy GLSL Auto-Upgrade, `TMaterialNode` Surface Textures / `PureEmissive` & `TCommonSurfaceShaderNode`, and Two-Sided Geometry `gl_FrontFacing` Normal Flip & `RobustNegativeScale` Winding Flip in Pure Vulkan RHI Mode)**: **COMPLETED** (100%, 823/823 total engine tests and 254/254 `TTestCastleVulkanRHI` tests passing):
  - [x] **76.1. X3D `TComposedShaderNode` (`TShaderPartNode`) Full Custom Shader Specialization (`$8000`) & Legacy GLSL Auto-Upgrade** — Completed & tested (`TestComposedShaderNodeFullCustomShaderAndLegacyUpgradeRHI`).
  - [x] **76.2. X3D `TMaterialNode` Surface Textures (`OcclusionTexture`, `SpecularTexture`), `PureEmissive` Unlit Optimization & `TCommonSurfaceShaderNode` Material/Texture Extraction** — Completed & tested (`TestPhongMaterialOcclusionSpecularPureEmissiveAndCommonSurfaceShaderRHI`).
  - [x] **76.3. Two-Sided Geometry (`Solid = False`) Back-Face Normal Flip (`gl_FrontFacing`) & `RobustNegativeScale` Winding Flip** — Completed & tested (`TestTwoSidedGeometryFrontFacingNormalFlipAndNegativeScaleWindingRHI`).
- **Phase 77 (X3D `TEffectNode` & `TComposedShaderNode` Custom Uniform Buffer & Texture Sampler Binding, `castle-shader:/EyeWorldSpace.glsl` & Camera Matrix Aliases, and Dynamic `TLinePropertiesNode` Line Width Synchronization in Pure Vulkan RHI Mode)**: **COMPLETED** (100%, 826/826 total engine tests and 257/257 `TTestCastleVulkanRHI` tests passing):
  - [x] **77.1. X3D `TEffectNode` & `TComposedShaderNode` Custom Uniform Buffer (`CastleUserEffectBlock` UBO) & Custom Texture Sampler (`Set 2, Bindings 2..5`) Extraction, std140 Packing & Descriptor Set Binding** — Completed & tested (`TestEffectAndComposedShaderCustomUniformUBOAndTextureBindingRHI`).
  - [x] **77.2. X3D `TEffectNode.FdShaderLibraries` (`'castle-shader:/EyeWorldSpace.glsl'`) Support & Built-in Camera Matrix Aliases (`castle_Camera*Matrix`)** — Completed & tested (`TestEffectShaderLibrariesEyeWorldSpaceAndCameraMatrixAliasesRHI`).
  - [x] **77.3. X3D `TLinePropertiesNode` (`Appearance.LineProperties`) & `TRenderContext.LineWidth` Dynamic RHI Line Width Synchronization** — Completed & tested (`TestLinePropertiesNodeAndRenderContextDynamicLineWidthRHI`).
