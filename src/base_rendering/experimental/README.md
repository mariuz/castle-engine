# Experimental & Research Vulkan / RHI Subsystems (`src/base_rendering/experimental/`)

This directory houses **opt-in research, Unreal Engine 5-inspired, and NVIDIA RTX-inspired GPU subsystems and shader math libraries** that are **not yet wired into Castle Game Engine's default `TCastleScene` / `TCastleViewport` production rendering pipeline**.

Keeping these prototypes isolated in `src/base_rendering/experimental/` guarantees that:
1. **Zero Core Engine Coupling**: None of CGE's core rendering units (`src/base_rendering/rhi/`, `src/base_rendering/vulkan/`, `src/base_rendering/opengl/`, `src/scene/`, `src/window/`, `src/ui/`, `castle-editor`) import or link any unit from `src/base_rendering/experimental/`.
2. **Smaller Core Units & Faster Compilation**: Production applications and upstream PR reviewers of `CastleInternalShaderRHI` and `CastleInternalRHI_Vulkan` only compile and review the active GPU pipelines actually used to render X3D / glTF 2.0 scenes and 2D UI.
3. **100% Preserved Research & Test Coverage**: Every mathematical reference implementation, GLSL `#version 450` generator, and GPU buffer/texture manager scaffold remains available via Pascal `class helper` extensions and continues to be verified by `TTestCastleVulkanRHI`.

---

## Units in `src/base_rendering/experimental/`

| Unit | Include Modules | Contents |
| :--- | :--- | :--- |
| **`CastleInternalShaderRHI_Experimental`** | `castleinternalshaderrhi_experimental_types.inc`<br>`castleinternalshaderrhi_experimental_pbr_env.inc`<br>`castleinternalshaderrhi_experimental_nextgen.inc` | `TCastleShaderGeneratorRHIExperimentalHelper` (`class helper for TCastleShaderGeneratorRHI`) + `196` experimental GLSL `#version 450` shader generators, CPU reference math evaluators, and GPU `std140`/`std430` companion records. |
| **`CastleInternalRHI_Vulkan_Experimental`** | `castleinternalrhi_vulkan_experimental_types.inc`<br>`castleinternalrhi_vulkan_experimental_lighting_gi.inc`<br>`castleinternalrhi_vulkan_experimental_gpu_driven.inc` | `37` experimental `TCastleVulkan*` subsystem managers attached lazily per device via `TVulkanExperimentalDeviceContext` (`TVulkanRHIDevice.ExperimentalContext`, automatically freed in `TVulkanRHIDevice.Destroy`) and exposed via `TVulkanRHIDeviceExperimentalHelper`. |

---

## Categorized Experimental Subsystems

1. **Global Illumination & Ray Reconstruction**:
   - `TCastleVulkanGlobalSDF` & `TCastleVulkanSurfaceCache` (UE5 Lumen-style 3D Global SDF clipmap & 6-axis surface card cache)
   - `TCastleVulkanDDGIGrid` (Octahedral irradiance & Chebyshev visibility probe grid)
   - `TCastleVulkanVoxelConeTracer` (3D mipmapped Voxel Cone Tracing / VXGI)
   - `TCastleVulkanReSTIR` (UE5 MegaLights-style spatio-temporal WRS/RIS reservoir resampling)
   - `TCastleVulkanSVGFDenoiser` (Spatio-Temporal Variance-Guided À-Trous wavelet denoiser)
   - `TCastleVulkanNeuralDenoiser` (Cooperative-matrix FP8/FP16 MLP denoiser scaffold)
2. **Virtualized Geometry, Shadows & Texturing**:
   - `TCastleVulkanClusterDAG` (UE5 Nanite-style hierarchical cluster DAG cut selector + 64-bit visibility buffer & software micro-rasterizer shaders)
   - `TCastleVulkanVirtualShadowMap` (UE5 VSM $64 \times 64$ virtual page table & $16 \times 16$ physical tile pool)
   - `TCastleVulkanLODSelector` & `TCastleVulkanShadowCasterCuller` (GPU-driven screen-coverage LOD & light-ray extrusion culling)
   - `TCastleVulkanTextureStreamer` & `TCastleVulkanRuntimeVirtualTexture` (GPU mip residency feedback & RVT page table)
3. **Temporal Upscaling, Stereo VR & Variable Rate Shading**:
   - `TCastleVulkanTSRUpscaler` (UE5 TSR-style Lanczos-2 / Blackman-Harris history upscaler)
   - `TCastleVulkanVRSManager` & `TCastleVulkanMultiviewStereoManager` (`VK_KHR_fragment_shading_rate` & `VK_KHR_multiview` foveated stereo)
   - `TCastleVulkanProgrammableSampleLocations` (`VK_EXT_sample_locations` sub-pixel MSAA patterns)
4. **Environment, Simulation, Particles & Novel Representations**:
   - `TCastleVulkanAtmosphereRenderer` (Rayleigh/Mie sky-view LUT), `TCastleVulkanOceanSimulator` (Gerstner wave spectrum), `TCastleVulkanTerrainCDLOD`, `TCastleVulkanSparseVolumeAtlas` (Planckian blackbody heterogeneous volumes)
   - `TCastleVulkanReflectionProbeManager`, `TCastleVulkanDecalManager`, `TCastleVulkanContactShadows`, `TCastleVulkanPerPixelLinkedListOIT`
   - `TCastleVulkanComputeParticles`, `TCastleVulkanComputeSkinner`, `TCastleVulkanXPBDSimulator` (Chaos-style XPBD cloth/hair)
   - `TCastleVulkanGaussianSplatRenderer` (3D Gaussian Splatting EWA conic covariance & tile radix sorter)
5. **Low-Level Driver Extensions & Advanced Shading Lobes**:
   - `TCastleVulkanDescriptorBufferManager` (`VK_EXT_descriptor_buffer`), `TCastleVulkanHostImageCopyManager` (`VK_EXT_host_image_copy`), `TCastleVulkanPipelineBinaryManager` (`VK_KHR_pipeline_binary`), `TCastleVulkanBreadcrumbTracker`, `TCastleVulkanBCnCompressor`, `TCastleVulkanStreamCompactor`, `TCastleVulkanIndirectComputeDispatcher`, `TCastleVulkanPerInstanceCustomData`
   - Advanced BSDF & post-processing GLSL/CPU libraries: Substrate layered slabs, Marschner hair/fur, clear coat, anisotropic GGX, Charlie cloth sheen, thin-film iridescence, Burley SSSSS, car-paint flakes, physical eye refraction, POM, LTC area lights, PCSS, DQS, displaced micro-meshes, SER coherence hints, optical flow, Kuwahara, MSDF, HDR10 PQ, and AgX chroma gamut compression.

---

## Opting In & Graduation Policy

To experiment with these APIs in a custom demo or test, add the units to your `uses` clause:

```pascal
uses
  CastleInternalRHI_Vulkan,
  CastleInternalShaderRHI,
  CastleInternalShaderRHI_Experimental,
  CastleInternalRHI_Vulkan_Experimental;
```

When `CastleInternalRHI_Vulkan_Experimental` is linked into an executable, its `initialization` section automatically registers `ExecuteVulkanExperimentalViewportSubsystems` and `ExecuteVulkanExperimentalSceneSubsystems` with `TVulkanRHIDevice`, activating the experimental `TCastleViewport` / `TCastleRenderOptions` modes (`giLumenSDFAndSurfaceCache`, `giDDGIProbes`, `giVoxelConeTracing`, `giReSTIRGI`, `taaTSRUpscaler`, `vrsContrastAdaptive`, `vrsFoveatedStereo`, `smsVirtualShadowMaps`, `tmPerPixelLinkedListOIT`).

**Graduation Criteria to Core RHI**: A subsystem should only move from `src/base_rendering/experimental/` back into `src/base_rendering/rhi/` + `src/base_rendering/vulkan/` once it has:
1. Compiled SPIR-V shaders (`.spv` or runtime-compiled GLSL `#version 450`) executing real GPU passes (`vkCmdDispatch` / `vkCmdDraw*`),
2. End-to-end scene-graph integration in `TCastleScene` / `TCastleViewport`, and
3. Pixel-verified visual parity / regression tests on live Vulkan hardware (`Mesa Lavapipe` + discrete GPU) with zero `VK_LAYER_KHRONOS_validation` errors.
