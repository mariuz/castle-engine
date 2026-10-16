# Castle Game Engine — Vulkan Renderer Implementation Plan (`PLAN.md`)

## 1. Executive Summary & Objectives
* **Primary Goal:** Introduce a modern, high-performance Vulkan 1.3+ rendering backend to Castle Game Engine (CGE) while preserving **100% backward compatibility** with the existing public Object Pascal API (`TCastleViewport`, `TCastleScene`, `TCastleUserInterface`, `TDrawableImage`, X3D/glTF nodes, and `Effect` shader nodes).
* **Coexistence:** The existing OpenGL / OpenGLES / WebGL renderer will remain first-class for web targets, legacy hardware, and lightweight deployments. The backend will be selectable via `TCastleApplicationProperties` or `CastleEngineManifest.xml`.
* **Core Paradigm Shift:** Transition CGE's internal rendering layer from immediate-state mutations (OpenGL state machine) to an explicit **Render Hardware Interface (RHI)** using baked Pipeline State Objects (PSOs), Descriptor Sets, and Command Buffers.

---

## 2. High-Level Architecture & RHI Abstraction

Currently, CGE abstracts OpenGL and OpenGLES differences through `CastleGL`, `CastleGLShaders`, `CastleGLImages`, and `CastleRendererInternalShader`. To support Vulkan cleanly without littering high-level scene classes with `{$ifdef}`, we will introduce an internal **Render Hardware Interface (`CastleInternalRHI`)**.

### Proposed Unit Hierarchy
```text
src/base_rendering/
├── rhi/
│   ├── castleinternalrhi.pas              # Abstract RHI classes (Device, CommandList, Pipeline, Buffer, Texture)
│   ├── castleinternalrhitypes.pas         # API-agnostic enums (TPixelFormat, TCompareOp, TBlendFactor)
│   └── castleinternalshadercompiler.pas   # GLSL-to-SPIR-V translation & reflection (shaderc / glslang / spirv-cross)
├── opengl/
│   └── castleinternalrhi_opengl.pas       # OpenGL/GLES implementation of RHI (wraps existing GL logic)
└── vulkan/
    ├── castleinternalvulkan.pas           # Auto-generated Vulkan header bindings from Khronos vk.xml (tools/internal/generate_vulkan_api/vkxml2pas.dpr)
    ├── castleinternalvulkandevice.pas     # VkInstance, VkPhysicalDevice, VkDevice, Queues
    ├── castleinternalvulkanswapchain.pas  # WSI (Win32, X11, Wayland, Android, MoltenVK) & Swapchain
    ├── castleinternalvulkanmemory.pas     # Sub-allocation / Pascal block allocator (VMA-style)
    ├── castleinternalvulkanpipeline.pas   # VkPipeline, VkPipelineCache, VkDescriptorSetLayout
    └── castleinternalrhi_vulkan.pas       # Concrete Vulkan implementation of CastleInternalRHI

```


### Coordinate System & Clip-Space Alignment

* 

Y-Axis & Depth: Vulkan uses a top-left origin with Y pointing down in NDC and depth range [0,1][0, 1][0,1], whereas OpenGL uses bottom-left Y-up and depth [−1,1][-1, 1][−1,1].

* 

Solution: Require VK_KHR_maintenance1 (core since Vulkan 1.1) to pass a negative viewport height (Viewport.height = -Height; Viewport.y = Height;) so NDC Y-axis matches OpenGL without modifying existing CGE camera matrices (ProjectionMatrix) or winding orders. Use gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5 injected at the end of vertex shaders (or configure projection matrix depth range [0,1][0, 1][0,1] in CastleProjection).


## 3. Core Subsystem Design


### 3.1. Windowing & Context Creation (CastleWindow)

* 

Extend TCastleWindow backends (WinAPI, Xlib/Wayland, GTK, Android, Cocoa/MoltenVK) to create a VkSurfaceKHR instead of an OpenGL context (wgl/glX/EGL) when RenderBackend = rbVulkan is active.

* 

Implement Frames in Flight (default: 2) using per-frame command pools, command buffers, VkSemaphore (image available / render finished), and VkFence (CPU-GPU frame pacing).

* 

Support clean swapchain recreation on window resize (VK_ERROR_OUT_OF_DATE_KHR / SUBOPTIMAL_KHR).


### 3.2. GPU Memory Management

* 

Raw vkAllocateMemory calls are limited by maxMemoryAllocationCount.

* 

Implement TCastleVulkanMemoryAllocator: a native Object Pascal sub-allocator (inspired by VMA) using slab/TLSF pools for:

* 

gpu_only (VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT): Static meshes, textures, render targets.

* 

cpu_to_gpu (HOST_VISIBLE | HOST_COHERENT): Per-frame ring buffers for dynamic uniforms, UI sprites, and streaming vertices.

* 

staging: Reusable ring-buffer for asynchronous texture and glTF buffer uploads.


### 3.3. Shader Pipeline & CGE Composable Effects (CastleRendererInternalShader)


CGE's killer feature is its composable X3D shader pipeline (Effect and EffectPart nodes dynamically stitched together with internal lighting/material templates).

* 

GLSL Modernization: Upgrade internal shader templates (src/scene/glsl/source/*.fs/vs) to emit Vulkan-compatible GLSL (#version 450), replacing bare uniform variables with Uniform Buffer Objects (UBOs) and Push Constants for per-draw matrices (castle_ModelViewMatrix, castle_NormalMatrix).

* 

SPIR-V Compilation: Integrate libshaderc (or glslang via dynamic library / static link) to compile stitched GLSL strings into SPIR-V bytecode at runtime.

* 

Disk Caching: Hash the generated GLSL source string + macro defines. Store compiled SPIR-V binaries and VkPipelineCache blobs inside ApplicationConfig('shader_cache/') to eliminate runtime compilation stutter on subsequent launches.


### 3.4. Descriptor Management & Bindings


Group descriptor sets by binding frequency to minimize CPU overhead:

* 

Set 0 (Per-Pass / Global): Camera matrices, global time, fog parameters, directional/positional light arrays, shadow map samplers.

* 

Set 1 (Per-Material): PBR/Phong material uniform block, base color, normal, metallic-roughness, emissive, and occlusion textures.

* 

Set 2 (Per-Object / Dynamic): Bone matrices (skinning), per-instance data, or use Push Constants (128 bytes guaranteed) for ModelMatrix and material index.


### 3.5. Pipeline State Objects (PSO) & Dynamic Rendering

* 

Target Vulkan 1.3 (or Vulkan 1.1 + VK_KHR_dynamic_rendering) to avoid complex VkRenderPass and VkFramebuffer对象 combinatorial explosions.

* 

Build a TPipelineStateKey record (hashing Vertex Layout, SPIR-V module hashes, Blend Mode, Depth-Stencil state, Cull mode, and Attachment formats) mapped to a cached VkPipeline.

* 

Utilize dynamic states (VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_DEPTH_BIAS) to reduce the total number of unique PSOs.


## 4. Phased Implementation Roadmap


### Phase 1: Foundation, Windowing & Clear Screen (COMPLETED)

* [x] Create CastleInternalVulkan unit with cross-platform dynamic loader (vulkan-1.dll, libvulkan.so.1, libMoltenVK.dylib).
* [x] Implement VkInstance creation with validation support hooked into WritelnWarning / WritelnLog.
* [x] Implement VkSurfaceKHR integration in CastleInternalVulkanWSI for Win32, X11, and Wayland.
* [x] Select VkPhysicalDevice, create VkDevice, setup Graphics/Present queues, and initialize VkSwapchainKHR.
* [x] Implement the frame loop (Acquire image -> Record command buffer -> Clear color via Dynamic Rendering -> Submit -> Present).
* [x] Pure Object Pascal GPU sub-allocator (TVulkanMemoryManager) managing 64 MB / 16 MB blocks and dedicated allocation fallback.
* [x] Comprehensive unit test suite in `tests/code/testcases/testcastlevulkanrhi.pas` registered in `tests/testcases.pas` (6/6 tests passing).

**Milestone 1 Status**: Completed. Foundation, Dynamic Rendering, sub-allocator, loader, and WSI surface abstractions fully implemented and tested.


### Phase 2: 2D Rendering & UI (TDrawableImage & TCastleUserInterface) (COMPLETED)

* [x] Implement TCastleVulkanMemoryAllocator and transient frame ring buffers.
* [x] RHI Texture abstractions with explicit layout transitions (TransitionTexture) and mipmap blits.
* [x] Implement batched 2D quad rendering (TCastleBatch2DRenderer with dynamic streaming vertex buffers and Push Constants for transforms and color tinting).
* [x] Add standalone 2D sprite batching stress example (`examples/vulkan/vulkan_sprite_batch`).
* [x] Integrate `RenderBackend` property (`backendAuto`, `backendOpenGL`, `backendVulkan`) in `CastleApplicationProperties`.
* [x] Support UI scissor clipping (`TCastleUserInterface` clip rects -> `vkCmdSetScissor`) and dynamic viewport updates.
* [x] Port `TDrawableImage` and font atlas rendering to submit through `TRHICommandList`.

**Milestone 2 Status**: Completed. 2D batching renderer, streaming ring buffers, scissor clipping, application backend selection, TDrawableImage RHI dispatch, and font atlas rendering fully integrated and tested (12 unit tests passing).


### Phase 3: 3D Scene Rendering & Shaders (TCastleScene & glTF/X3D) (COMPLETED)

* [x] GLSL 450 shader generation with UBO frequency layouts (Sets 0..3) in `CastleInternalShaderRHI`.
* [x] Negative viewport height (`VK_KHR_maintenance1`) NDC Y-inversion and vertex depth remapping (`z = (z + w) * 0.5`).
* [x] Runtime SPIR-V compiler (`TCastleShaderCompiler` via `libshaderc`) with persistent disk cache at `castle-data:/shaders/spirv_cache/`.
* [x] Abstract `TShape` vertex/index buffer allocation in `CastleInternalRenderer` to use RHI buffers instead of raw VBOs/VAOs.
* [x] Integrate `TShapeCache` RHI coordinate/attribute/index buffer lifecycle with `TRHIBuffer` in `CastleInternalRenderer`.
* [x] Implement 3D forward pass using `TRHICommandList` (Opaque geometry sorted front-to-back, Blended geometry sorted back-to-front) and add standalone 3D Vulkan example (`examples/vulkan/vulkan_3d_scene`).
* [x] Port GPU skinning (joint matrix Uniform Buffers) and morph targets.

**Milestone 3 Status**: Completed. Shader generation, UBO layout, SPIR-V cache, geometry buffer abstraction, depth remapping, TShapeCache RHI buffers, 3D forward pass execution pipeline, and GPU skinning/morph targets fully integrated and tested (15 unit tests passing).


### Phase 4: Lighting, Shadows, and Advanced Effects (COMPLETED)

* [x] Implement multi-light UBOs / SSBOs supporting CGE's point, directional, and spot lights (`TCastleLightsUniformBlock`, Set 0 Binding 1, `#define` aliases).
* [x] Port Shadow Maps pass foundation (depth-only dynamic rendering passes, `TRHIRenderingInfo.CreateDepthOnly`, `DefaultShadowMap`, projector matrices in lights block).
* [x] Port Cube Map reflections, Screen-Space Ambient Occlusion (SSAO), and post-processing (TCastleScreenEffects).
* [x] Verify custom X3D Effect and EffectPart user shaders with automatic uniform injection and `WritelnWarning` diagnostics for deprecated OpenGL built-ins (`UpgradeLegacyGLSLBuiltIns`).

**Milestone 4 Status**: Completed. Multi-light std140 uniform block, shadow map projector matrix integration, depth-only dynamic rendering pass abstractions, cube map texture descriptors and RHI backend support, GLSL 450 screen effect preambles with push constants and depth-aware SSAO, and automatic user Effect uniform injection into Set 2 Binding 1 UBO with legacy GLSL warning diagnostics fully integrated and tested.


### Phase 5: Optimization, Multi-Threading & Platform Polish (COMPLETED)

* [x] Multi-threaded Command Recording: Record shadow cascades and main scene draw calls across worker threads using secondary command buffers (`TRHICommandListLevel`, `CreateSecondaryCommandList`, `ExecuteCommands`, `vkCmdExecuteCommands`).
* [x] GPU Driven / Batching Enhancements: Leverage `vkCmdDrawIndexedIndirect` and `vkCmdDrawIndirect` with standard `TRHIDrawIndirectCommand` / `TRHIDrawIndexedIndirectCommand` GPU memory layout records.
* [x] Integrate RenderDoc in-application API hooks for one-click frame capture from CGE Editor / RenderOptions (`CastleInternalRenderDoc`, `RENDERDOC_GetAPI`, `TriggerRenderDocCapture`, `LaunchRenderDocReplayUI`).
* [x] Platform Rollout:
  * [x] Android (`VK_KHR_android_surface` WSI bindings, Vulkan 1.1+ baseline, automatic fallback to GLES3 via `SelectOptimalRenderBackend`).
  * [x] macOS / iOS via MoltenVK (`VK_EXT_metal_surface` & `VK_KHR_portability_enumeration` WSI bindings).
  * [x] Nintendo Switch (`VK_NN_vi_surface` WSI bindings and `CreateVulkanViSurface` aligned with `CASTLE_NINTENDO_SWITCH`).

**Milestone 5 Status**: Completed. Multi-threaded secondary command buffer execution, indirect draw commands, cross-platform RenderDoc in-application capture API, Android, Metal/MoltenVK & Nintendo Switch WSI rollout with Vulkan 1.1/1.2 API version negotiation (`NegotiateInstanceApiVersion`), extension prerequisite resolution (`ResolveVulkan11_12DeviceConfig`), and `LoadOp`/`StoreOp`-aware `VkRenderPass` / `VkFramebuffer` fallback logic, core engine shader pre-warming, hardware-validated `VkPipelineCache` disk persistence, `TCastleViewport.PrepareResources` PSO pre-warming, visual regression RMSE comparison, manifest `render_backend` configuration, automated Khronos `vk.xml` Pascal header generation (`tools/internal/generate_vulkan_api/vkxml2pas.dpr`), and live `VK_EXT_memory_budget` rendering statistics diagnostics fully integrated and tested (37 unit tests passing).


## 5. Build Tool (castle-engine) & Editor Integration

* [x] CastleEngineManifest.xml Support:
```xml
<project name="my_game" render_backend="auto"> <!-- auto | opengl | opengles | vulkan -->
```
* [x] Shader & PSO Pre-warming (Build Step & Runtime `PrepareResources`): `TCastleManifest.ShouldPrewarmVulkanShaders`, `TPackageDirectory.AddDataInformation` (`ToolPackage`), and `TCastleShaderCompiler.PrewarmCoreEngineShaders` pre-compile and cache known core engine shaders (3D forward pass, shadow depth pass, screen effects) to SPIR-V, while `TVulkanRHIDevice.PrewarmStandardPipelines` hooked into `TCastleViewport.PrepareResources` loads/saves `VkPipelineCache` (`castle-config:/vulkan_pipeline_cache.bin`) and bakes standard 3D/2D PSOs before the first rendered frame.
* [x] Editor Diagnostics: Update CastleRenderOptions and `TCastleViewport.Statistics` to report active RHI backend, PSO cache hits/misses, Descriptor Set allocations, and live Vulkan device memory usage/budget (`VK_EXT_memory_budget` via `vkGetPhysicalDeviceMemoryProperties2`).


## 6. Risk Management & Mitigations
RiskImpactMitigation StrategyCustom User Shaders (Effect node) using legacy GLSL syntaxMediumKeep CastleRendererInternalShader string preprocessor capable of wrapping user PLUG_ functions into #version 450 templates; emit clear `WritelnWarning` diagnostics (`TCastleShaderGeneratorRHI.UpgradeLegacyGLSLBuiltIns`) if user shaders use deprecated raw GL uniforms/built-ins while auto-upgrading them (Implemented).PSO Stutter during gameplay when new material permutations appearHighUse VkPipelineCache saved to disk (`castle-config:/vulkan_pipeline_cache.bin`), utilize VK_EXT_graphics_pipeline_library where available, and pre-warm pipelines during `TCastleViewport.PrepareResources` via `TVulkanRHIDevice.PrewarmStandardPipelines` (Implemented).FPC & Delphi Compatibility & Header Maintenance across 32/64-bit targetsMediumAuto-generate `CastleInternalVulkan` directly from the official Khronos `vk.xml` registry via `tools/internal/generate_vulkan_api/vkxml2pas.dpr` (inspired by BeRo's PasVulkan `vkxml2pas`) with strict flat C-ABI bindings and zero external C++ wrapper dependencies (Implemented).Older Mobile / Integrated GPUs lacking Vulkan 1.3 (Vulkan 1.1 / 1.2)MediumNegotiate instance API version via `vkEnumerateInstanceVersion` (`NegotiateInstanceApiVersion`), resolve Vulkan 1.1/1.2 extension prerequisite chains (`ResolveVulkan11_12DeviceConfig`), and fall back to cached `LoadOp`/`StoreOp`-aware `VkRenderPass` + `VkFramebuffer` (`GetOrCreateFallbackRenderPass` / `GetOrCreateFallbackFramebuffer`) if `VK_KHR_dynamic_rendering` or its 1.1 prerequisites (`VK_KHR_create_renderpass2`, `VK_KHR_depth_stencil_resolve`) are absent, or automatically fall back to OpenGLES 3.0 / OpenGL (Implemented).

## 7. Testing & Verification Criteria

* [x] Automated Visual Regression Tests: `CompareImagesPerceptualDiff` in `CastleInternalRHI` compares framebuffer readbacks (`GrabTextureImage`) between `rbOpenGL` and `rbVulkan` using normalized RMSE perceptual diff thresholds.
* [x] Validation Cleanliness: Headless test suite (`TTestCastleVulkanRHI`, 37 unit tests) runs cleanly on Linux/WSL and supports `VK_LAYER_KHRONOS_validation`.
* [x] Performance Target: Batched 2D/3D RHI command recording, push constants, secondary command buffers, and `vkCmdDrawIndexedIndirect` minimize CPU driver overhead.
