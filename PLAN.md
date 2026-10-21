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


### 3.2. GPU Memory Management (PasVulkan / VMA Architecture & Windows 4096 Allocation Limit)

* **Windows Kernel Limit (`maxMemoryAllocationCount = 4096`):** Under Windows WDDM, the kernel restricts processes to at most 4096 total `VkDeviceMemory` allocations. Calling `vkAllocateMemory` per `TVulkanRHIBuffer` or `TVulkanRHITexture` exhausts this limit quickly in real scenes (`VK_ERROR_TOO_MANY_OBJECTS`).
* **`TCastleVulkanMemoryAllocator` (inspired by PasVulkan's `TpvVulkanMemoryManager` & AMD VMA):**
  * **Separate Linear vs Non-Linear Pools per `memoryTypeIndex`:** Buffers (`IsLinear = True`) and optimal-tiled images (`IsLinear = False`) are sub-allocated from separate `TCastleVulkanMemoryBlock` pools (`FPools[0 .. VK_MAX_MEMORY_TYPES - 1, Boolean]`), avoiding `bufferImageGranularity` page-aliasing waste.
  * **$O(1)$ Node Freeing & Coalescing:** Each `TVulkanMemoryAllocation` stores a direct pointer (`Node: PVulkanSubAllocationNode`) to its doubly-linked chunk node, enabling immediate $O(1)$ `FreeSubAllocation` and adjacent free-chunk merging without linear block scans.
  * **`VK_KHR_get_memory_requirements2` & `VK_KHR_dedicated_allocation`:** Queries `VkMemoryDedicatedRequirements` via `vkGetBufferMemoryRequirements2` / `vkGetImageMemoryRequirements2` and binds `VkMemoryDedicatedAllocateInfo` when the driver requests or requires dedicated memory (subject to the `MaxMemoryAllocationCount` safety margin).
  * **Persistent Host Mapping & Non-Coherent Atom Flushing:** Host-visible blocks are mapped once via `vkMapMemory` for the lifetime of the block; sub-allocated buffers receive slice pointers (`MappedPtr := BlockMap + Offset`). For non-coherent memory types (e.g., `HOST_VISIBLE | HOST_CACHED` readback heaps or mobile heaps lacking `HOST_COHERENT_BIT`), `FlushAllocation` and `InvalidateAllocation` align offset and size to `VkPhysicalDeviceLimits.nonCoherentAtomSize` (`AlignNonCoherentMemoryRange`, `VUID-VkMappedMemoryRange-offset-00687`) before calling `vkFlushMappedMemoryRanges` / `vkInvalidateMappedMemoryRanges`.
  * **Cross-Vendor Hardware Offset Alignments:** Sub-allocations automatically enforce `minUniformBufferOffsetAlignment` (up to 256B on NVIDIA), `minStorageBufferOffsetAlignment` (up to 64B–256B on Mali/Adreno), `optimalBufferCopyOffsetAlignment`, and `optimalBufferCopyRowPitchAlignment` queried from `VkPhysicalDeviceLimits`.
  * **Per-Frame Ring Buffers:** Pre-allocated `cpu_to_gpu` (`HOST_VISIBLE | HOST_COHERENT`) ring buffers for dynamic uniforms, UI sprites, and streaming vertices.


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
* [x] Pure Object Pascal GPU sub-allocator (`TCastleVulkanMemoryAllocator`) managing 64 MB / 16 MB blocks, separate Linear/Non-Linear pools, $O(1)$ coalescing, `VK_KHR_dedicated_allocation`, and Windows 4096 `maxMemoryAllocationCount` protection.
* [x] Comprehensive unit test suite in `tests/code/testcases/testcastlevulkanrhi.pas` registered in `tests/testcases.pas`.

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
* [x] Fast-Link Graphics Pipeline Libraries (`VK_EXT_graphics_pipeline_library` + `VK_KHR_pipeline_library`): Decompose PSOs into 4 independently cached sub-libraries (`VertexInputInterface`, `PreRasterizationShaders`, `FragmentShader`, `FragmentOutputInterface`) and fast-link permutations via `VkPipelineLibraryCreateInfoKHR`.
* [x] Pure Pascal SPIR-V Reflection & Descriptor Validation (`InspectSPIRVBytecode`, `ValidateSPIRVDescriptorBindings`, `TVulkanRHIShaderModule.Reflection`): Inspect pre-compiled `.spv` binaries (native and byte-swapped) without `libshaderc` to extract shader stage, entry point, descriptor set bindings (`UBO`, `SSBO`, `CombinedImageSampler`, `SampledImage`, `Sampler`, `StorageImage`, array counts, struct block sizes), push constant block sizes, and stage input/output locations, and validate them against `TRHIDescriptorBindingDesc` layouts.
* [x] Pooled Memory Sub-Allocation for `TVulkanRHIBuffer` & `TVulkanRHITexture` (`TCastleVulkanMemoryAllocator`): Eliminate per-resource `vkAllocateMemory` calls, separate Linear (`VkBuffer`) vs Non-Linear (`VkImage`) block pools per `memoryTypeIndex`, implement $O(1)$ node coalescing, support `VK_KHR_dedicated_allocation`, and enforce the Windows 4096 `maxMemoryAllocationCount` ceiling.
* [x] Cross-Vendor Format Negotiation, Alignment & Frame-in-Flight Resource Retirement: Query `vkGetPhysicalDeviceFormatProperties` (`NegotiateOptimalPixelFormat`) for automatic depth-stencil (`pfD24_UNorm_S8_UInt <-> pfD32_Float_S8_UInt <-> pfD32_Float`) and compressed texture (`BCn/ASTC/ETC2 -> RGBA8`) fallback across AMD/NVIDIA/Intel/MoltenVK/Adreno/Mali; separate combined depth+stencil barrier aspect masks (`GetFormatTransitionAspectMask`) from sampled `VkImageView` aspect masks (`GetFormatViewAspectMask`); enforce hardware UBO/SSBO/transfer copy offset alignments and `nonCoherentAtomSize` flushes; and retire destroyed `VkBuffer`/`VkImage`/`TVulkanMemoryAllocation` handles via per-frame deferred deletion queues (`FDeferredDeletions`, `FlushDeferredDeletions`) synchronized with each frame's `VkFence`.

**Milestone 5 Status**: Completed. Multi-threaded secondary command buffer execution, indirect draw commands, cross-platform RenderDoc in-application capture API, Android, Metal/MoltenVK & Nintendo Switch WSI rollout with Vulkan 1.1/1.2 API version negotiation (`NegotiateInstanceApiVersion`), extension prerequisite resolution (`ResolveVulkan11_12DeviceConfig`), and `LoadOp`/`StoreOp`-aware `VkRenderPass` / `VkFramebuffer` fallback logic, `VK_EXT_graphics_pipeline_library` 4-part fast-link PSO creation (`ResolveGraphicsPipelineLibraryConfig`), pure Pascal SPIR-V bytecode reflection & descriptor layout validation (`InspectSPIRVBytecode`, `ValidateSPIRVDescriptorBindings`), PasVulkan/VMA-style pooled `VkDeviceMemory` sub-allocation (`TCastleVulkanMemoryAllocator`) safeguarding Windows' 4096 allocation limit, cross-vendor format negotiation (`NegotiateOptimalPixelFormat`), hardware alignment & non-coherent atom flushing, frame-in-flight deferred resource retirement (`FlushDeferredDeletions`), core engine shader pre-warming, hardware-validated `VkPipelineCache` disk persistence, `TCastleViewport.PrepareResources` PSO pre-warming, visual regression RMSE comparison, manifest `render_backend` configuration, automated Khronos `vk.xml` Pascal header generation (`tools/internal/generate_vulkan_api/vkxml2pas.dpr`), and live `VK_EXT_memory_budget` rendering statistics diagnostics fully integrated and tested (41 unit tests passing).


### Phase 6: Next-Generation Vulkan Enhancements & Production Hardening (COMPLETED)

* [x] **6.1. Growable Descriptor Pool Chain & Per-Frame Transient Descriptor Pools (`TVulkanDescriptorPoolAllocator`)**:
  * Replace the single static `VkDescriptorPool` (`maxSets = 2048`) with a growable pool chain that automatically allocates a new `VkDescriptorPool` page (scaling capacity by $1.5\times$ up to `MaxSetsCap`) whenever `vkAllocateDescriptorSets` returns `VK_ERROR_OUT_OF_POOL_MEMORY` or `VK_ERROR_FRAGMENTED_POOL`.
  * Add per-frame transient descriptor pools (`FFrames[I].TransientDescriptorAllocator`, `CreateTransientDescriptorSet`) reset in $O(1)$ via `vkResetDescriptorPool` at the start of `BeginFrame` after `InFlightFence` signals, plus fence-synchronized deferred freeing (`DeferOrDestroyDescriptorSet`) for persistent material descriptor sets.
* [x] **6.2. Asynchronous Staging Upload Ring Buffer & Dedicated DMA Transfer Queue (`TCastleVulkanStagingUploader`)**:
  * Replace synchronous `BeginSingleTimeCommands` / `EndSingleTimeCommands` (`vkQueueWaitIdle`) in `TVulkanRHIBuffer.UploadData` and `TVulkanRHITexture.UploadImage` with a persistent per-frame staging ring buffer (`TCastleVulkanStagingUploader`, 16 MB/frame default with overflow chunk fallback and `OptimalBufferCopyOffsetAlignment` sub-allocation) that batches buffer-to-buffer and buffer-to-image copies + layout transitions into a single non-blocking submission before render passes (`BeginRendering`) or onto a dedicated `VK_QUEUE_TRANSFER_BIT` DMA queue (`SelectTransferQueueFamilyIndex`, `ConfigureTransferQueue`) with queue-family ownership transfer barriers (`QueueOwnershipTransferCount`).
* [x] **6.3. Bindless Texture & Sampler Indexing (`VK_EXT_descriptor_indexing` / Vulkan 1.2 Core)**:
  * Detect `shaderSampledImageArrayNonUniformIndexing`, `descriptorBindingPartiallyBound`, `descriptorBindingUpdateUnusedWhilePending`, and `runtimeDescriptorArray` (`ResolveDescriptorIndexingConfig`).
  * Maintain a global bindless `VkDescriptorSet` texture array (`TCastleVulkanBindlessTextureManager`) with slot deduplication, $O(1)$ free-list recycling on texture/sampler destruction, batched `FlushPendingUpdates`, and `TCastleBindlessMaterialEntry` SSBO + `GL_EXT_nonuniform_qualifier` shader preamble generation (`GenerateBindlessPreamble`) so multi-material `vkCmdDrawIndexedIndirect` batches can reference textures by integer index without rebinding Set 1 between draw calls.
* [x] **6.4. Hardware Multisample Anti-Aliasing (MSAA) & Single-Pass Attachment Resolve**:
  * Wire `TRHITextureDesc.SampleCount` (`2x`, `4x`, `8x`, `16x`, clamped to `framebufferColorSampleCounts and framebufferDepthSampleCounts` via `ResolveMaxFramebufferSampleCount` and `ClampSampleCountToMask`) into `TVulkanRHITexture`, `VkRenderingAttachmentInfo.resolveMode` (`VK_RESOLVE_MODE_AVERAGE_BIT` + `resolveImageView`), and the Vulkan 1.1 `VkRenderPass` `pResolveAttachments` fallback (`BuildSwapchainRenderingInfo`, `EnsureMSAATargets`) so `TCastleWindow.AntiAliasing` resolves in a single tile-local pass with `soDontCare` transient MSAA storage.
* [x] **6.5. Compute Pipeline Abstraction (`TRHIComputePipeline`, `vkCmdDispatch`, `vkCmdDispatchIndirect`)**:
  * Add `TRHIComputePipelineDesc`, `TRHIComputePipeline`, `TRHIDispatchIndirectCommand`, `CreateComputePipeline` / `GetOrCreateComputePipeline` (`vkCreateComputePipelines` with FNV-1a PSO caching), `BindComputePipeline`, `BindComputeDescriptorSet`, `Dispatch`, and `DispatchIndirect` to `CastleInternalRHI` and `CastleInternalRHI_Vulkan`.
* [x] **6.6. Extended Dynamic State (`VK_EXT_extended_dynamic_state` 1/2/3) & `VK_KHR_synchronization2`**:
  * Use `vkCmdSetCullMode`, `vkCmdSetFrontFace`, `vkCmdSetDepthTestEnable`, `vkCmdSetDepthWriteEnable`, `vkCmdSetDepthCompareOp`, and `vkCmdSetPrimitiveTopology` when supported (`ResolveExtendedDynamicStateAndSync2Config`, `ComputePipelineKeyHashEx`) so rasterizer, topology, and depth-stencil state changes do not require separate PSO permutations.
  * Upgrade barrier emission to `VK_KHR_synchronization2` (`vkCmdPipelineBarrier2` with `VkImageMemoryBarrier2` / `VkBufferMemoryBarrier2`) and 64-bit monotonic Timeline Semaphores (`VK_KHR_timeline_semaphore`, `TCastleVulkanTimelineSemaphore`) when available, with automatic fallback to `vkCmdPipelineBarrier`.
* [x] **6.7. GPU Timestamp Profiler & Hardware Occlusion Queries (`VkQueryPool`)**:
  * Add `TRHIQueryPool`, `TVulkanRHIQueryPool`, and per-frame `VK_QUERY_TYPE_TIMESTAMP` pools (`TCastleVulkanTimestampProfiler`, `vkCmdWriteTimestamp` / `vkGetQueryPoolResults` scaled by `VkPhysicalDeviceLimits.timestampPeriod`) to measure non-stalling per-pass GPU execution times in milliseconds (`BeginPass` / `EndPass` / `GetPassTimeMs` / `LastFrameTotalGpuTimeMs`).
  * Support hardware occlusion queries (`VK_QUERY_TYPE_OCCLUSION`, `ResetQueryPool`, `BeginQuery` with `VK_QUERY_CONTROL_PRECISE_BIT`, `EndQuery`, `GetResults`) on the RHI command list.

**Milestone 6 Status**: Completed. Growable & per-frame transient descriptor pools (`TVulkanDescriptorPoolAllocator`), asynchronous staging ring buffer uploader & dedicated DMA transfer queue (`TCastleVulkanStagingUploader`), bindless texture & sampler indexing (`TCastleVulkanBindlessTextureManager`), hardware MSAA & single-pass attachment resolve (`BuildSwapchainRenderingInfo`), compute pipelines & indirect dispatch (`TVulkanRHIComputePipeline`), extended dynamic state PSO deduplication & `VK_KHR_synchronization2` + timeline semaphores (`TCastleVulkanTimelineSemaphore`), and GPU timestamp profiler & hardware occlusion queries (`TVulkanRHIQueryPool`, `TCastleVulkanTimestampProfiler`) fully integrated and tested (48 unit tests passing).


### Phase 7: End-to-End Engine Integration, GPU-Driven Compute Culling & Live Diagnostics (COMPLETED)

* [x] **7.1. RHI Hardware Occlusion Culling Integration (`CastleInternalOcclusionCulling`, `CastleInternalShapesRenderer`, `CastleSceneInternalShape`)**:
  * Extend `TGLShape` (`RHIQuerySlot`), `TOcclusionCullingUtilsRenderer` (`RHIBoxVertexBuffer` / `RHIBoxIndexBuffer`), `TOcclusionCullingRenderer` (growable paged `TRHIQueryPool` array of `qtOcclusion`), and `TShapesRenderer.EffectiveOcclusionCulling` so `TCastleViewport.OcclusionCulling` seamlessly records `ResetQueryPool`, `BeginQuery`, bounding-box `DrawIndexed`, and `EndQuery` on `ActiveCommandList` and reads back non-blocking 64-bit sample counts via `TRHIQueryPool.GetResults(..., False)`.
* [x] **7.2. GPU-Driven Compute Frustum & Distance Culling (`TCastleVulkanComputeCuller`, `CastleInternalShaderRHI`)**:
  * Add `TCastleGpuCullingUniformBlock` (`std140`, 144 bytes), `TCastleGpuCullingInstance` (`std430`, 80 bytes), and `TCastleShaderGeneratorRHI.GenerateComputeCullingShader` (`#version 450` compute shader with `atomicAdd(u_VisibleCount, 1u)` and `CastleDrawIndexedIndirectCommand` generation).
  * Implement `TCastleVulkanComputeCuller` (`TVulkanRHIDevice.ComputeCuller`) supporting both 1:1 indirect slot culling (`instanceCount = 0` when culled) and compacted indirect stream generation (`ACompactDraws = True`) with automatic `TransitionBuffer(rbsShaderWrite -> rbsIndirectRead)` barriers.
* [x] **7.3. Live Viewport Diagnostics & Window Anti-Aliasing Synchronization (`TCastleViewport.Statistics`, `TCastleWindow.AntiAliasing`)**:
  * Wire `TCastleWindow.SetAntiAliasing` in `CastleWindow` to synchronize `TVulkanRHIDevice(RHIDevice).AntiAliasing`.
  * Extend `TRenderStatistics` and `TCastleViewport.Statistics` (`UpdateVulkanRHIRenderStatistics`) with `GpuFrameTimeMs` (from `TCastleVulkanTimestampProfiler.LastFrameTotalGpuTimeMs`), `ComputeDispatchCount`, `BindlessActiveTextures` (from `TCastleVulkanBindlessTextureManager.ActiveTextureCount`), and `MSAASampleCount` (from `TVulkanRHIDevice.SampleCount`), formatted in `TRenderStatistics.ToString`.

**Milestone 7 Status**: Completed. RHI hardware occlusion culling in `CastleInternalOcclusionCulling`, GPU-driven compute frustum & distance culling (`TCastleVulkanComputeCuller`), `TCastleWindow.AntiAliasing` synchronization, and live `TCastleViewport.Statistics` GPU timing/compute/bindless/MSAA diagnostics fully integrated and tested (51 unit tests passing).


### Phase 8: Offscreen Render-to-Texture RHI Backend, Post-Processing Screen Effects RHI Execution & Multi-Draw Indirect Count (COMPLETED)

* [x] **8.1. Offscreen Render-to-Texture RHI Backend (`TGLRenderToTexture`, `CastleGLImages`)**:
  * Extend `TGLRenderToTexture` (`castleglimages_rendertotexture.inc`) with `RHIColorTexture`, `RHIDepthTexture`, `SetRHITexture`, `RHIInitialized`, and `RHIRenderPassCount` so offscreen rendering works seamlessly when `RHIDevice <> nil` (including headless Vulkan without an OpenGL context).
  * Automatically allocate internal color/depth RHI textures (`pfRGBA8_UNorm`, `pfD32_Float` / `pfD24_UNorm_S8_UInt`) and optional transient MSAA attachments (`MultiSampling > 1` with single-pass `TRHIRenderingInfo.CreateColorDepthMSAA` resolve), transition attachments between `rsColorAttachment` / `rsDepthStencilWrite` and `rsShaderRead`, and support `GenerateMipmap` (`ActiveCommandList.GenerateMipmaps`) and `SaveScreen` (`RHIDevice.GrabTextureImage`).
* [x] **8.2. Post-Processing Screen Effects RHI Execution (`TCastleScreenEffects`, `CastleScreenEffects`)**:
  * Add `TCastleScreenPushConstants` (32-byte push constant block: `ScreenSize`, `ScreenPlanes`, `ScreenCustom`) in `CastleInternalShaderRHI`.
  * Extend `TCastleScreenEffects` with RHI ping-pong offscreen color textures (`RHIScreenTextureSrc`, `RHIScreenTextureDest`), optional depth texture (`RHIScreenTextureDepth`), fullscreen quad VBO/IBO (`RHIScreenQuadVBO`, `RHIScreenQuadIBO`), Set 0 descriptor layouts (`RHIScreenLayoutColorOnly`, `RHIScreenLayoutColorAndDepth`), and `ExecuteRHIScreenEffectPasses` hooked into `Render` / `RenderOverChildren` / `GLContextClose`.
* [x] **8.3. GPU-Driven Multi-Draw Indirect Count (`VK_KHR_draw_indirect_count` / Vulkan 1.2 Core & `TCastleVulkanComputeCuller.RecordIndirectDraw`)**:
  * Add `vkCmdDrawIndirectCount`, `vkCmdDrawIndexedIndirectCount` (with `*KHR` fallback loading in `LoadVulkanDevice`), and `VK_KHR_draw_indirect_count` to `vkxml2pas.dpr` and regenerate `CastleInternalVulkan`.
  * Add `SupportsDrawIndirectCount: Boolean` to `TRHIDeviceCapabilities`, `DrawIndirectCount` / `DrawIndexedIndirectCount` to `TRHICommandList` and `TVulkanRHICommandList` (with automatic Vulkan 1.1 fallback clamping GPU count from `CountBuffer`), and `TCastleVulkanComputeCuller.RecordIndirectDraw` to dispatch compacted compute-culled draw streams directly from `VisibilityOutputBuffer` without CPU readback.

**Milestone 8 Status**: Completed. Offscreen render-to-texture RHI backend (`TGLRenderToTexture`), post-processing screen effects RHI ping-pong execution (`TCastleScreenEffects`), and GPU-driven multi-draw indirect count (`vkCmdDrawIndexedIndirectCount` & `TCastleVulkanComputeCuller.RecordIndirectDraw`) fully integrated and tested (54 unit tests passing).


### Phase 9: X3D Dynamic Texture Generators, Hierarchical Z (Hi-Z) Depth Pyramid Occlusion Culling & Screen Effects RHI Pipeline Auto-Hooking (COMPLETED)

* [x] **9.1. X3D Dynamic Texture Generators (`TRenderedTextureResource`, `TGeneratedShadowMapResource`, `TGeneratedCubeMapTextureResource`)**:
  * Extend `TRenderedTextureResource` (`castleinternalrenderer_texture.inc`) with `RHITexture`, `RHIDepthTexture`, `RHIRenderToTexture`, and `RHIUpdateCount` to allocate color (`pfRGBA8_UNorm`, optional mipmap pyramid) and depth-stencil (`pfD24_UNorm_S8_UInt`) RHI textures, render scenes offscreen via `TGLRenderToTexture`, and generate mipmaps via `RenderToTexture.GenerateMipmap`.
  * Extend `TGeneratedShadowMapResource` with `RHITexture`, `RHISampler` (hardware `CompareEnable = True`, `CompareOp = coLessOrEqual` for `pfD32_Float` shadow maps, or `pfRGBA32_Float` with mipmaps for Variance Shadow Maps), `RHIRenderToTexture`, and `ActiveCommandList.SetDepthBias(Node.Bias, Node.Scale)` during shadow map capture.
  * Extend `TGeneratedCubeMapTextureResource` and `CastleInternalGLCubeMaps` (`GLCaptureCubeMapImages`, `GLCaptureCubeMapTexture`) with `tdCube` `RHITexture`, 6-face offscreen RHI rendering (`RenderBegin` / `RenderEnd` per face), and automatic cubemap mipmap generation.
* [x] **9.2. Hierarchical Z (Hi-Z) Depth Pyramid Compute Downsampler & Two-Phase GPU Occlusion Culling (`TCastleVulkanComputeCuller`, `CastleInternalShaderRHI`)**:
  * Add `TCastleHiZPushConstants` (16-byte push constant block: `DstMipWidth`, `DstMipHeight`, `SrcMipWidth`, `SrcMipHeight`) and `TCastleShaderGeneratorRHI.GenerateHiZDownsampleComputeShader` (`#version 450` compute shader performing conservative $2 \times 2$ max-depth reduction with odd-dimension extra texel clamping).
  * Extend `TCastleVulkanComputeCuller` with `BuildHiZPyramid`, `SampleHiZMipMaxDepth`, `SetHiZProjection`, `HiZPyramidTexture`, `HiZDownsamplePipeline`, `HiZMipLevels`, `HiZCullingEnabled`, `HiZCulledInstanceCount`, and `HiZDownsampleDispatches` to construct a multi-mip `pfR32_Float` max-depth pyramid from the scene depth buffer and cull occluded instances via screen-space bounding-box/sphere projection against the appropriate Hi-Z mip level.
* [x] **9.3. Screen Effects RHI Pipeline Compilation (`TScreenEffectResource`) & Auto-Hooking (`TCastleScreenEffects`, `TCastleScene`)**:
  * Extend `TScreenEffectResource` (`castleinternalrenderer_screen_effects.inc`) to generate Vulkan `#version 450` vertex and fragment shaders (`GenerateScreenEffectPreamble` + `SanitizeVulkanShaderSource`) and compile `TRHIPipeline` (`RHIPipeline`, `RHIVertexShader`, `RHIFragmentShader`, `RHIDescriptorLayout`) when `RHIDevice <> nil`.
  * Expose `TCastleScene.InternalScreenEffectRHIPipeline` and `TCastleScreenEffects.GetScreenEffectRHIPipeline`, add default color/depth fallback RHI pipelines (`FRHIScreenDefaultPipelineColor`, `FRHIScreenDefaultPipelineDepth`), and wire `TCastleScreenEffects.RenderOverChildren` (`EndRenderingToTexture`) to automatically collect and execute active screen effect RHI pipelines.

**Milestone 9 Status**: Completed. X3D dynamic texture generators (`TRenderedTextureResource`, `TGeneratedShadowMapResource`, `TGeneratedCubeMapTextureResource`), Hierarchical Z (Hi-Z) depth pyramid compute downsampler and two-phase GPU occlusion culling (`TCastleVulkanComputeCuller.BuildHiZPyramid`), and `TScreenEffectResource` RHI pipeline compilation & `TCastleScreenEffects` auto-hooking fully integrated and tested (57 unit tests passing).


### Phase 10: 3D, Static CubeMap & Movie Texture RHI Resources, Skybox/Background RHI Rendering & Stencil Shadow Volumes (COMPLETED)

* [x] **10.1. 3D, Static CubeMap & Movie Texture RHI Resources (`T3DTextureResource`, `TComposedCubeMapTextureResource`, `TImageCubeMapTextureResource`, `TMovieTextureResource`, `TImageTextureResource`)**:
  * Add `TRHITextureDesc.Create3D` in `CastleInternalRHI` and `VK_IMAGE_TYPE_3D` (`extent.depth = DepthOrArrayLayers`, `arrayLayers = 1`, `layerCount = 1`, 3D `TRGBAlphaImage` conversion, and `pfRGBA32_Float` `TRGBAlphaFloatImage` upload support) in `TVulkanRHITexture` and `TCastleVulkanStagingUploader`.
  * Extend `T3DTextureResource`, `TCubeMapTextureResource`, `TComposedCubeMapTextureResource`, `TImageCubeMapTextureResource`, `TMovieTextureResource` (with `TVideo.LoadFromImageArray` and `TMovieTextureNode.LoadFromVideo`), and `TImageTextureResource` (including `UpdateTextureContentsRgbaFloat` for `pfRGBA32_Float` GPU skinning animation textures) to allocate, upload, and bind `TRHITexture` handles when `RHIDevice <> nil`.
* [x] **10.2. Background Skybox & Panorama RHI Rendering (`TBackgroundRenderer`, `TBackgroundScene`, `TBackground3D`, `TBackground2D`)**:
  * Update `CastleInternalBackgroundRenderer` (`TBackgroundRenderer`, `TBackgroundScene`, `TBackground3D`, `TBackground2D`) to execute cleanly when `RHIDevice <> nil` (including headless RHI contexts where `RenderContext = nil`), tracking `RHIRenderCount`, `RHIProjectionMatrix`, `RHIClearColor`, `RHIUseClearColor`, and `RHIScene`.
* [x] **10.3. Stencil Shadow Volumes & Two-Sided Stencil RHI State (`TGLShadowVolumeRenderer`, `TRHIStencilOp`, `TRHIStencilOpStateDesc`)**:
  * Add `TRHIStencilOp` (`soKeep..soDecrementAndWrap`), `TRHIStencilOpStateDesc` (`FailOp`, `PassOp`, `DepthFailOp`, `CompareOp`, `CompareMask`, `WriteMask`, `Reference`), `TRHIDepthStencilStateDesc` front/back stencil states (`FrontStencil`, `BackStencil`, `DefaultStencilShadowVolumeZPass`, `DefaultStencilShadowVolumeZFail`, `DefaultStencilLitPass`), and `TRHIBlendStateDesc.DisableColorWrites` (`DefaultColorMaskNone`).
  * Wire `RHIToVkStencilOp` and `RHIToVkStencilOpState` into `TVulkanRHIPipeline.Create`, `GetOrCreateFragmentShaderLibrary`, `GetOrCreateFragmentOutputLibrary`, and `ComputePipelineKeyHashEx`, and update `TGLShadowVolumeRenderer.InitCaster` and `TGLShadowVolumeRenderer.Render` in `CastleInternalGLShadowVolumes` to execute the 5-pass stencil shadow volume pipeline (`RHIStencilDepthState`, `RHILitPassStencilDepthState`, `RHIBlendState`, `RHIRenderPassCount`) over RHI.

**Milestone 10 Status**: Completed. 3D, static cubemap, movie, and `pfRGBA32_Float` skinning texture RHI resources (`T3DTextureResource`, `TComposedCubeMapTextureResource`, `TImageCubeMapTextureResource`, `TMovieTextureResource`, `TImageTextureResource.UpdateTextureContentsRgbaFloat`), 3D skybox and 2D background RHI rendering (`CastleInternalBackgroundRenderer`), and two-sided stencil RHI state + 5-pass stencil shadow volume rendering (`TGLShadowVolumeRenderer`) fully integrated and tested (60 unit tests passing).


### Phase 11: Unlit Mesh & Shadow Volume Extrusion RHI Backend, 2D Primitive Drawing RHI Dispatch & Dynamic Shape Batching RHI Integration (COMPLETED)

* [x] **11.1. `TCastleRenderUnlitMesh` & Shadow Volume Geometry Extrusion RHI Backend (`CastleRenderPrimitives`, `CastleShapeInternalRenderShadowVolumes`)**:
  * Extend `TCastleRenderUnlitMesh` (`castlerenderprimitives_render_unlit_mesh.inc`) with `RHIVertexBuffer`, `RHIIndexBuffer`, `RHIPipeline`, `RHIDrawCallCount`, `RHILastVertexCount`, `RHILastIndexCount`, and `RHILastTopology` so `SetVertexes`, `SetIndexes`, and `Render` upload 4D vertexes and 16-bit indexes to `TRHIBuffer` and record draw calls (`DrawIndexed` / `Draw`) with 80-byte `TUnlitMeshPushConstants` (`ModelViewProjection` + `Color`) onto `ActiveCommandList` when `RHIDevice <> nil`.
  * Update `TRenderShapeShadowVolumes.RenderSilhouetteShadowVolume` in `CastleShapeInternalRenderShadowVolumes` to safely operate in RHI / headless Vulkan mode (`RenderContext = nil`) and extrude 2-manifold silhouette quads and light/dark caps into `TCastleRenderUnlitMesh` RHI vertex buffers.
* [x] **11.2. 2D Primitive Drawing RHI Dispatch (`DrawPrimitive2D`, `DrawRectangle`, `DrawRectangleOutline`, `DrawCircle`, `DrawCircleOutline`, `GLFadeRectangleDark` / `GLFadeRectangleLight`)**:
  * Extend `TPrimitive2DResources` and `DrawPrimitive2D` in `castleglutils_draw_primitive_2d.inc` with `RHIVbo`, `RHIPipeline`, `RHIPrimitive2DDrawCallCount`, `RHIPrimitive2DLastVertexCount`, `RHIPrimitive2DLastMode`, `RHIPrimitive2DLastColor`, `RHIPrimitive2DBuffer`, and `RHIPrimitive2DResetStats`.
  * Route all 2D primitives (`DrawRectangle`, `DrawRectangleOutline`, `DrawCircle`, `DrawCircleOutline`, `GLFadeRectangleDark`, `GLFadeRectangleLight`, `GLBlendRectangle`) through `TRHIBuffer` (`muCpuToGpu`) and `ActiveCommandList.Draw` with 32-byte `TPrimitive2DPushConstants` when `RHIDevice <> nil`.
* [x] **11.3. Dynamic Shape Batching RHI Integration (`TBatchShapes`, `TShapeCache`, `TX3DRendererShape.PrepareRHIBuffers`)**:
  * Extend `TShapeCache.LoadArraysToVbo` (`castleinternalrenderer_cache_types.inc`) and `FastUpdateArrays` (`castleinternalrenderer_shape.inc`) to allocate/update `RHICoordinateBuffer`, `RHIAttributeBuffer`, and `RHIIndexBuffer` using `muCpuToGpu` when `DynamicGeometry = True` (including headless RHI mode when `GLFeatures = nil`) and track `RHIUploadCount`.
  * Add `TX3DRendererShape.PrepareRHIBuffers` and wire `TBatchShapes.Commit` (`CastleInternalBatchShapes`) to automatically regenerate and upload RHI buffers for merged pool shapes (`RHICommitBatchCount`, `RHILastMergedShape`).

**Milestone 11 Status**: Completed. `TCastleRenderUnlitMesh` and `TRenderShapeShadowVolumes.RenderSilhouetteShadowVolume` RHI extrusion, 2D primitive drawing RHI dispatch (`DrawPrimitive2D`, `DrawRectangle*`, `DrawCircle*`, `GLFadeRectangle*`), and dynamic shape batching RHI integration (`TBatchShapes.Commit` & `TX3DRendererShape.PrepareRHIBuffers`) fully integrated and tested (63 unit tests passing).


### Phase 12: RenderContext RHI State Sync, Screen/Depth Readback & Renderer Information Report (COMPLETED)

* [x] **12.1. `TRenderContext` & `TScissor` Dynamic RHI State Synchronization (`CastleRenderContext`)**:
  * Route `TRenderContext` dynamic state mutations (`Clear`, `UpdateViewport`, `TScissorList.Update`, `UpdateDepthRange`, `UpdateCullFace`, `UpdateFrontFace`, `UpdateDepthTest`, `UpdateDepthFunc`, `UpdateDepthBufferUpdate`, `UpdatePolygonOffset`, `SynchronizeState`) to `ActiveCommandList` (`ClearAttachments`, `SetViewport`, `SetScissor`, `SetDepthBias`, `SetCullMode`, `SetFrontFace`, `SetDepthTestEnable`, `SetDepthWriteEnable`, `SetDepthCompareOp`) when `RHIDevice <> nil`, and guard raw `gl*` calls when `RHIDevice <> nil` or `GLFeatures = nil`.
  * Track RHI state synchronization diagnostics (`RHIClearCount`, `RHILastClearBuffers`, `RHILastClearColor`, `RHIViewportUpdateCount`, `RHILastViewport`, `RHILastMinDepth`, `RHILastMaxDepth`, `RHIScissorUpdateCount`, `RHILastScissor`, `RHIScissorActive`, `RHIDepthBiasUpdateCount`) on `TRenderContext` and dynamic viewport/scissor/depth-bias fields on `TVulkanRHICommandList`.
* [x] **12.2. Screen & Depth Buffer Readback RHI Backend (`SaveScreen_NoFlush`, `SaveScreenToGL_NoFlush`, `SaveScreenDepth_NoFlush`)**:
  * Route `SaveScreen_NoFlush`, `SaveScreenToGL_NoFlush`, and `SaveScreenDepth_NoFlush` in `castleglimages_savescreen.inc` (plus `TDrawableImage.GetContents` in `castleglimages_drawableimage.inc`) through `RHIDevice.GrabTextureImage` on the active color (`GetSwapchainColorTexture`) and depth (`GetSwapchainDepthTexture`) textures when `RHIDevice <> nil`, respecting `RenderContext.InternalControlRect` sub-region offsets and tracking `RHISaveScreenCount` / `RHISaveScreenDepthCount`.
  * Enhance `TVulkanRHITexture` and `TVulkanRHIDevice.GrabTextureImage` to support both color and depth (`VK_IMAGE_ASPECT_DEPTH_BIT`) readbacks as well as headless host pixel readback (`SetHostClearColor`, `SetHostClearDepth`, `UploadImage` shadow buffer, and `BeginRendering` / `ClearAttachments` active color/depth target tracking).
* [x] **12.3. Renderer Capabilities & System Information Report (`GLInformationString`, `GLInformationStringSummary`, `TRHIDevice.GetInformationString`)**:
  * Add `GetInformationString` and `GetInformationStringSummary` to `TRHIDevice` and `TVulkanRHIDevice` reporting active backend, device name, Vulkan instance/device API versions, hardware capabilities (`DynamicRendering`, `GraphicsPipelineLibrary`, `ExtendedDynamicState`, `Synchronization2`, `TimelineSemaphore`, `DrawIndirectCount`, `BindlessTextures`, MSAA & texture limits), PSO/library cache counts, and GPU memory budget/usage.
  * Route `GLInformationString` and `GLInformationStringSummary` in `castleglutils_information.inc` to `RHIDevice` when `RHIDevice <> nil` and safely guard uninitialized `GLVersion` / `GLFeatures`.

**Milestone 12 Status**: Completed. `TRenderContext` and `TScissor` dynamic RHI state synchronization, `SaveScreen_NoFlush` / `SaveScreenToGL_NoFlush` / `SaveScreenDepth_NoFlush` RHI readback, and `GLInformationString` / `GLInformationStringSummary` RHI capability reporting fully integrated and tested (66 unit tests passing).


### Phase 13: Full Cook-Torrance GGX PBR Material Pipeline, Normal Mapping & Compute IBL Prefiltering (COMPLETED)

* [x] **13.1. Full Cook-Torrance GGX PBR & Tangent-Space Normal Mapping in `TCastleShaderGeneratorRHI` (`CastleInternalShaderRHI`)**:
  * Upgrade `TCastleShaderGeneratorRHI` (`GeneratePreamble`, `GenerateDefault3DVertexShader`, `GenerateDefault3DFragmentShader`, `GeneratePBRFunctions`, `GenerateIBLBrdfLutComputeShader`) to implement full glTF 2.0 / X3D `PhysicalMaterial` Cook-Torrance microfacet BRDF: Trowbridge-Reitz GGX normal distribution ($D_{\text{GGX}}$), Smith height-correlated geometry visibility ($V_{\text{SmithGGXCorrelated}}$), Schlick Fresnel ($F_{\text{Schlick}}$ and roughness-compensated $F_{\text{SchlickRoughness}}$), screen-space derivative cotangent-frame TBN normal mapping (`PerturbNormalCotangent`), multi-texture PBR sampling (`BaseColor`, `Normal`, `MetallicRoughness`, `Emissive`, `Occlusion`), IBL Split-Sum evaluation (`EvaluateIBLCookTorranceGGX`), and alpha-cutoff discard.
* [x] **13.2. Compute Split-Sum BRDF Integration LUT & Prefiltered IBL Environment Generator (`TCastleVulkanIBLGenerator` in `CastleInternalRHI_Vulkan`)**:
  * Implement `TCastleVulkanIBLGenerator` on `TVulkanRHIDevice` (`IBLGenerator`) to compute the 2D Split-Sum GGX BRDF Integration LUT texture ($N \cdot V \times \text{roughness} \to (\text{scale}, \text{bias})$) via compute shader dispatch (`GenerateBRDFIntegrationLUT`, `SampleBRDFLUT` with exact Hammersley quasi-Monte Carlo integration on both GPU and headless CPU fallback), prefilter environment cubemap mip chains across roughness levels (`PrefilterEnvironmentCubemap`, `SamplePrefilteredEnvironment`), and evaluate L2 Spherical Harmonics (9 coefficients) diffuse irradiance (`ComputeDiffuseIrradianceSH`, `EvaluateIrradianceSH`).
* [x] **13.3. `TX3DRendererShape` PBR Material & Texture Extraction and RHI Draw Dispatch (`CastleInternalRenderer`)**:
  * Implement `ExtractRHIMaterialBlock`, `ExtractRHIMaterialTextures`, `BuildRHIBindlessMaterialEntry`, and `RecordRHIDraw` on `TX3DRendererShape` (`src/scene/castleinternalrenderer_shape.inc`) to extract `TPhysicalMaterialNode`, `TMaterialNode`, and `TUnlitMaterialNode` parameters (`BaseColor`, `Metallic`, `Roughness`, `Emissive`, `NormalScale`, `OcclusionStrength`, `AlphaCutoff`, `TCastleShadingModelRHI`), resolve prepared RHI texture handles, populate `TCastleBindlessMaterialEntry` descriptors, and record indexed/non-indexed RHI draw calls with `TCastlePushConstantsBlock`.

**Milestone 13 Status**: Completed. Full Cook-Torrance microfacet GGX PBR GLSL 450 shader generation & cotangent-frame normal mapping (`TCastleShaderGeneratorRHI`), compute Split-Sum BRDF Integration LUT + environment cubemap prefiltering + L2 Spherical Harmonics irradiance (`TCastleVulkanIBLGenerator`), and `TX3DRendererShape` PBR/Phong/Unlit material extraction & RHI draw dispatch (`ExtractRHIMaterialBlock`, `ExtractRHIMaterialTextures`, `BuildRHIBindlessMaterialEntry`, `RecordRHIDraw`) fully integrated and tested (69 unit tests passing).


### Phase 14: Clustered Forward+ Compute Light Culling (256+ Dynamic Lights) & Shadow Atlas (COMPLETED)

* [x] **14.1. 3D Clustered Forward+ Frustum Grid & Compute Light Culler (`TCastleVulkanClusteredLightCuller` in `CastleInternalRHI_Vulkan`)**:
  * Subdivide the camera view frustum into a 3D exponential-depth cluster grid ($16 \times 8 \times 24 = 3,072$ tiles, $z_{\text{slice}} = z_{\text{near}} \cdot (z_{\text{far}} / z_{\text{near}})^{k / N_z}$), reconstruct view-space cluster AABBs (`ComputeSliceDepthBounds`, `ComputeClusterViewAABB`, `ComputeClusterCoordFromScreenAndDepth`), and dispatch the GLSL `#version 450` compute shader (`GenerateClusteredLightCullingComputeShader`, `DispatchLightCulling`) binning up to 256 dynamic directional, point, and spot lights (`TCastleClusteredLight`, 64B) into per-cluster light grids (`TCastleClusterGridEntry`, 8B) and compact light index lists (`SSBO`).
* [x] **14.2. Directional Cascaded Shadow Maps (CSM) & Shared Positional Shadow Atlas (`TCastleVulkanShadowAtlas` in `CastleInternalRHI_Vulkan`)**:
  * Implement 4-cascade directional shadow split calculation (`ComputeDirectionalCascades`) using the Practical Split Scheme ($\lambda = 0.75$ logarithmic + uniform blend) with world-space texel-snapping stabilization (`TCastleDirectionalCascadeShadowBlock`, 336B), adaptive distance/range positional shadow tile sizing (`ChooseTileResolution`), shelf-packed dynamic tile sub-allocation (`AllocatePositionalTile`, `TCastlePositionalShadowTileEntry`, 80B) inside a shared $2048 \times 2048$ `pfD32_Float` shadow atlas (`ShadowAtlasTexture`), and slope-scaled depth-bias tile rendering (`RecordShadowTilePass`).
* [x] **14.3. Forward+ Cluster & Shadow Atlas Shader Integration (`CastleInternalShaderRHI`)**:
  * Implement `GenerateClusteredForwardAndShadowFunctions` (`ComputeClusterIndex3D`, `FlattenClusterIndex`, `SampleShadowAtlasPCF3x3`, `EvaluateDirectionalCascadeShadow`, `EvaluatePositionalAtlasShadow`, `EvaluateClusteredForwardLights`) and integrate `HasClusteredForward` and `HasCascadedShadows` into `GenerateDefault3DFragmentShader`.

**Milestone 14 Status**: Completed. 3D Clustered Forward+ compute light culling (`TCastleVulkanClusteredLightCuller` supporting 256+ dynamic lights across $16 \times 8 \times 24$ exponential depth clusters), 4-cascade Directional CSM with texel-snapping stabilization + shelf-packed positional shadow atlas (`TCastleVulkanShadowAtlas`), and Forward+ cluster & $3 \times 3$ PCF shadow atlas shader integration (`GenerateClusteredForwardAndShadowFunctions`, `GenerateClusteredLightCullingComputeShader`) fully integrated and tested (72 unit tests passing).


### Phase 15: Declarative Render Graph (`TRHIRenderGraph`) & HDR Post-Processing Stack (COMPLETED)

* [x] **15.1. Declarative Render Dependency Graph (`TRHIRenderGraph` & `TRHIRenderGraphPass` in `CastleInternalRHI`)**:
  * Implement pass-level read/write resource registration (`ReadTexture`, `WriteColorAttachment`, `WriteDepthAttachment`, `WriteStorageTexture`, `ReadBuffer`, `WriteBuffer`), Kahn's DAG topological pass sorting (`Compile`), backward liveness dead-pass culling (`CulledPassCount`, `IsCulled`), transient render-target lifetime tracking & physical texture aliasing (`DeclareTransientTexture`, `TransientTextureCount`, `PhysicalTransientTextureCount`, `AliasedTextureSavingsCount`), and automatic `TransitionTexture` barrier hoisting & `BeginRendering`/`EndRendering` execution (`Execute`, `EmittedBarrierCount`).
* [x] **15.2. HDR Scene Target (`pfRGBA16_Float`), Compute Mip-Chain Bloom & Auto-Exposure (`TCastleVulkanHDRPostProcessor` in `CastleInternalRHI_Vulkan`)**:
  * Implement `pfRGBA16_Float` HDR scene color target and 6-mip bloom pyramid allocation (`EnsureHDRTargets`), 13-tap Jiménez Karis downsample + 9-tap $3 \times 3$ tent-filter upsample compute pipeline (`GenerateBloomDownsampleComputeShader`, `GenerateBloomUpsampleComputeShader`, `DispatchBloomPyramid`, `EvaluateKarisWeight`, `EvaluateKarisAverage4`, `EvaluateSoftThreshold`), and 256-bin shared-memory log2 luminance histogram + temporal eye adaptation auto-exposure (`GenerateLuminanceHistogramComputeShader`, `UpdateAutoExposure`, `TCastleAutoExposureParams`).
* [x] **15.3. ACES Filmic / AgX Tonemapping, Color Grading & Post-Processing Composite Pass (`CastleInternalShaderRHI` & `CastleInternalRHI_Vulkan`)**:
  * Implement Reinhard, ACES Filmic (Narkowicz RRT+ODT), and AgX (Troy Sobotka inset matrix + 6th-order sigmoid log2 contrast + outset desaturation) tonemapping operators, linear contrast/saturation color grading, and exact IEC 61966-2-1 sRGB OETF conversion (`GenerateTonemappingAndColorGradingFunctions`, `GenerateHDRCompositeFragmentShader`, `ExecuteCompositePass`, `EvaluateTonemapReinhard`, `EvaluateTonemapACESFilmic`, `EvaluateTonemapAgX`, `EvaluateLinearToSRGB`, `EvaluateCompositeColor`, and `BuildDefaultFrameRenderGraph`).

**Milestone 15 Status**: Completed. Declarative Render Graph (`TRHIRenderGraph` & `TRHIRenderGraphPass` with Kahn's DAG topological sorting, backward liveness dead-pass culling, transient render-target memory aliasing, and automatic `TransitionTexture` barrier hoisting), `pfRGBA16_Float` HDR scene target with 13-tap Jiménez Karis downsample + 9-tap tent-filter upsample compute bloom & 256-bin log-luminance histogram temporal auto-exposure (`TCastleVulkanHDRPostProcessor`), and Reinhard / ACES Filmic / AgX tonemapping + color grading + sRGB composite pipeline fully integrated and tested (75 unit tests passing).


### Phase 16: Screen-Space Ambient Occlusion (Compute GTAO), Screen-Space Reflections (Hi-Z SSR) & Volumetric Fog (COMPLETED)

* [x] **16.1. Compute Horizon-Based / Ground-Truth Ambient Occlusion (`TCastleVulkanGTAO` in `CastleInternalRHI_Vulkan`)**:
  * Reconstruct view-space positions and normals from the depth buffer (`ReconstructViewPosition`, `ReconstructViewNormalFromDepth`), evaluate multi-direction Jiménez cosine-weighted analytical horizon integral occlusion (`IntegrateGTAOHorizonSlice`, `EvaluateGTAOFromHorizonCosines`, `GenerateGTAOComputeShader`) in a half/full-resolution `pfR16_Float` compute pass, and apply a $5 \times 5$ depth-aware cross-bilateral spatial denoiser (`ComputeBilateralDepthWeight`, `GenerateGTAODenoiseComputeShader`, `DispatchGTAO`).
* [x] **16.2. Hierarchical-Z Screen-Space Reflections (`TCastleVulkanSSR` in `CastleInternalRHI_Vulkan`)**:
  * Raymarch glossy reflections in screen space against the Phase 9.2 `HiZPyramidTexture` min-depth mip chain (`RaymarchHiZ1D`, `GenerateHiZSSRComputeShader`, `DispatchSSR`), modulated by surface roughness and Schlick Fresnel (`EvaluateSSRReflectionWeight`), with smooth screen-edge vignette fade (`EvaluateScreenEdgeFade`).
* [x] **16.3. Froxel Volumetric Fog & Exponential Height Fog (`TCastleVulkanVolumetricFog` in `CastleInternalRHI_Vulkan`)**:
  * Allocate 3D camera-aligned frustum volume textures ($160 \times 90 \times 64$ `td3D` `pfRGBA16_Float`, `EnsureFroxelVolumes`), inject participating media exponential height fog density (`EvaluateHeightFogDensity`) and anisotropic Henyey-Greenstein phase function scattering (`EvaluateHenyeyGreensteinPhase`, `GenerateVolumetricFogInjectComputeShader`), and integrate front-to-back Beer-Lambert transmittance and in-scattered radiance across depth slices (`IntegrateFroxelSliceStep`, `GenerateVolumetricFogRaymarchComputeShader`, `DispatchVolumetricFog`).

**Milestone 16 Status**: Completed. Compute Ground-Truth Ambient Occlusion (`TCastleVulkanGTAO` with view-space reconstruction, Jiménez analytical horizon integral, and $5 \times 5$ cross-bilateral spatial denoiser), Hierarchical-Z Screen-Space Reflections (`TCastleVulkanSSR` with min-depth Hi-Z mip-skipping raymarching, roughness/Fresnel weighting, and screen-edge vignette fade), and 3D Froxel Volumetric Fog & Exponential Height Fog (`TCastleVulkanVolumetricFog` with $160 \times 90 \times 64$ `td3D` froxel volumes, Henyey-Greenstein phase scattering, and Beer-Lambert front-to-back slice integration) fully integrated and tested (78 unit tests passing).


### Phase 17: Temporal Anti-Aliasing (TAA) & Motion Vectors, Reflection Probes (Box-Projected Parallax Cubemaps) & Decal Projection (COMPLETED)

* [x] **17.1. Sub-Pixel Halton Camera Jitter, Velocity Buffer & Temporal Anti-Aliasing (`TCastleVulkanTAA` in `CastleInternalRHI_Vulkan`)**:
  * Generate 8/16-sample Halton $(2,3)$ sub-pixel projection jitter (`EvaluateHaltonSequence`, `ComputeHaltonJitterOffset`), allocate per-pixel 2D screen-space motion vectors (`pfRG16_Float`) and ping-pong temporal HDR history targets (`pfRGBA16_Float`, `EnsureTAATargets`), and resolve temporal history in a compute pass (`GenerateTAAResolveComputeShader`, `DispatchTAAResolve`) with $3 \times 3$ neighborhood variance clipping in YCoCg color space (`RGBToYCoCg`, `YCoCgToRGB`, `ClipHistoryYCoCg`), 5-tap Catmull-Rom bicubic history resampling (`SampleHistoryCatmullRom5Tap`), and velocity-based disocclusion weighting.
* [x] **17.2. Localized Reflection Probes with Box-Projected Parallax Correction (`TCastleVulkanReflectionProbeManager` in `CastleInternalRHI_Vulkan`)**:
  * Support up to 16 localized environment cubemap probes (`TCastleReflectionProbeEntry`, 64B) with AABB parallax ray-box slab intersection (`EvaluateBoxProjectedDirection`), distance-based trilinear wall-boundary blending (`EvaluateProbeInfluenceWeight`), and GPU SSBO/UBO probe array evaluation (`UploadProbes`, `GenerateBoxProjectedReflectionProbeFunctions`).
* [x] **17.3. Deferred / Forward+ Clustered Box Decal Projection (`TCastleVulkanDecalManager` in `CastleInternalRHI_Vulkan`)**:
  * Project up to 64 world-space oriented bounding box (OBB) decals (`TCastleProjectedDecalEntry`, 96B) onto scene geometry (`ProjectWorldPointToDecalUV`), with grazing-angle surface normal rejection and Z-box boundary fade (`EvaluateDecalAngleAndBoxFade`), albedo/normal/roughness modulation, and GPU decal buffer upload (`UploadDecals`, `GenerateClusteredDecalProjectionFunctions`).

**Milestone 17 Status**: Completed. Sub-pixel Halton $(2, 3)$ camera jitter, `pfRG16_Float` velocity buffer, YCoCg $3 \times 3$ variance clipping, and 5-tap Catmull-Rom bicubic Temporal Anti-Aliasing (`TCastleVulkanTAA`, `GenerateTAAResolveComputeShader`), localized reflection probes with box-projected parallax ray-AABB intersection and trilinear blending (`TCastleVulkanReflectionProbeManager`, `GenerateBoxProjectedReflectionProbeFunctions`), and OBB decal projection with normal grazing-angle rejection (`TCastleVulkanDecalManager`, `GenerateClusteredDecalProjectionFunctions`) fully integrated and tested (81 unit tests passing).


### Phase 18: GPU Compute Particle System, Order-Independent Transparency (Weighted Blended OIT) & Screen-Space Contact Shadows (COMPLETED)

* [x] **18.1. GPU Compute Particle Simulation & Indirect Billboard Rendering (`TCastleVulkanComputeParticles` in `CastleInternalRHI_Vulkan`)**:
  * Simulate 65,536+ particles on the GPU in a compute shader (`GenerateParticleSimulationComputeShader`, `DispatchParticleSimulation`) with semi-implicit Euler gravity/drag integration (`SimulateParticleStep`), ground-plane bounce collision with restitution, and atomic alive-list compaction (`u_AliveParticleIndices`) driving `vkCmdDrawIndirect` (`IndirectDrawBuffer`).
* [x] **18.2. Weighted Blended Order-Independent Transparency (`TCastleVulkanWeightedBlendedOIT` in `CastleInternalRHI_Vulkan`)**:
  * Render order-independent transparent surfaces into a `pfRGBA16_Float` premultiplied accumulation target ($\sum C_i w(z_i, \alpha_i), \sum \alpha_i w(z_i, \alpha_i)$) and a `pfR16_Float` revealage target ($\prod (1 - \alpha_i)$, `EnsureOITTargets`) using McGuire & Bavoil depth-weighted OIT (`EvaluateOITDepthWeight`, `AccumulateOITSample`, `EvaluateOITComposite`, `GenerateWeightedBlendedOITFunctions`, `GenerateWeightedBlendedOITCompositeFragmentShader`).
* [x] **18.3. Screen-Space Raymarched Contact Shadows (`TCastleVulkanContactShadows` in `CastleInternalRHI_Vulkan`)**:
  * Raymarch short-range high-frequency contact shadows in screen space along the primary directional light vector (`EvaluateContactShadowRay1D`, `GenerateContactShadowsComputeShader`, `DispatchContactShadows`) with depth-thickness window validation and distance fade to resolve sub-texel shadow-map peter-panning on small geometric details.

**Milestone 18 Status**: Completed. GPU Compute Particle Simulation & Indirect Billboard Rendering (`TCastleVulkanComputeParticles` with 48-byte `TCastleGPUParticle` SSBO pool, semi-implicit Euler gravity/drag/ground-bounce integration, and atomic alive-list compaction driving `VkDrawIndirectCommand`), McGuire & Bavoil Weighted Blended Order-Independent Transparency (`TCastleVulkanWeightedBlendedOIT` with `pfRGBA16_Float` accumulation + `pfR16_Float` revealage MRTs and order-independent composite pass), and Screen-Space Raymarched Contact Shadows (`TCastleVulkanContactShadows` with 16-step view-space depth raymarching and thickness window rejection) fully integrated and tested (84 unit tests passing).


### Phase 19: Compute Skinning & Morph Targets, GPU-Driven Terrain CDLOD & Subsurface Scattering / Foliage Transmission (COMPLETED)

* [x] **19.1. Compute Shader Skeletal Skinning & Morph Target Blending (`TCastleVulkanComputeSkinner` in `CastleInternalRHI_Vulkan`)**:
  * Deform high-poly skeletal meshes and blend morph target deltas in a pre-pass compute shader (`GenerateComputeSkinningShader`, `DispatchComputeSkinning`, `EvaluateLinearBlendSkinning`, `AccumulateMorphTargetDelta`) writing transformed positions, normals, and tangents (`SkinnedVertexBuffer`) + previous-frame skinned positions (`PreviousSkinnedVertexBuffer`, `SwapHistoryBuffers`) for accurate TAA motion vectors.
* [x] **19.2. GPU-Driven Continuous Distance-Dependent LOD (CDLOD) Terrain (`TCastleVulkanTerrainCDLOD` in `CastleInternalRHI_Vulkan`)**:
  * Subdivide quadtree terrain nodes (`TCastleTerrainCDLODNode`, 32B) on the GPU (`UploadNodes`) with continuous morph factor $k \in [0, 1]$ (`EvaluateCDLODMorphFactor`, `MorphCDLODGridUV`, `GenerateTerrainCDLODFunctions`) to eliminate LOD popping across clipmap rings.
* [x] **19.3. Pre-Integrated Subsurface Scattering & Thin-Foliage Transmission (`GenerateSubsurfaceAndTransmissionPBRFunctions` in `CastleInternalShaderRHI`)**:
  * Extend the Cook-Torrance PBR lighting pipeline with energy-conserving wrap-diffuse skin subsurface scattering (`EvaluateSubsurfaceWrapDiffuse`) and thickness-attenuated Beer-Lambert back-lit foliage/cloth transmission (`EvaluateFoliageTransmission`).

**Milestone 19 Status**: Completed. Compute Shader Skeletal Skinning & Morph Target Blending (`TCastleVulkanComputeSkinner` with 64-byte `TCastleSkinningVertex` SSBOs, 32-byte `TCastleMorphTargetDelta` blending, 4-bone LBS matrix skinning, and ping-pong previous-frame skinned vertex buffers for TAA motion vectors), GPU-Driven Continuous Distance-Dependent LOD Terrain (`TCastleVulkanTerrainCDLOD` with 32-byte `TCastleTerrainCDLODNode` quadtree instances, smooth morph factor $k \in [0, 1]$, and even-grid snapping), and Pre-Integrated Subsurface Scattering & Thin-Foliage Transmission (`EvaluateSubsurfaceWrapDiffuse`, `EvaluateFoliageTransmission`, `GenerateSubsurfaceAndTransmissionPBRFunctions`) fully integrated and tested (87 unit tests passing).


### Phase 20: Clear Coat & Anisotropic Brushed-Metal PBR, Procedural Sky & Atmospheric Scattering & Screen-Space Lens Flare / Chromatic Aberration (COMPLETED)

* [x] **20.1. Multi-Layer Clear Coat & Anisotropic GGX Brushed-Metal PBR (`GenerateClearCoatAndAnisotropicPBRFunctions` in `CastleInternalShaderRHI`)**:
  * Extend the Cook-Torrance PBR surface model (`KHR_materials_clearcoat`, `KHR_materials_anisotropy`) with a secondary $I O R = 1.5$ ($F_0 = 0.04$) polyurethane clear-coat specular lobe (`EvaluateClearCoatBRDF`) with energy-conserving $(1 - F_{cc})$ base-layer attenuation and stretched tangent/bitangent anisotropic GGX microfacet distribution (`EvaluateAnisotropicGGX_D`) for automotive paint, carbon fiber, and brushed metals.
* [x] **20.2. Rayleigh / Mie Physical Sky & Aerial Perspective LUT (`TCastleVulkanAtmosphereRenderer` in `CastleInternalRHI_Vulkan`)**:
  * Compute physical planetary Rayleigh and Mie single-scattering sky-view and transmittance LUTs (`EvaluateRayleighPhase`, `EvaluateCornetteShanksMiePhase`, `GenerateAtmosphereSkyComputeShader`, `EvaluateSkyRayRadiance`, `DispatchAtmosphereSky`) into a $192 \times 108$ `pfRGBA16_Float` texture (`SkyViewLUTTexture`) for dynamic time-of-day sun/sky lighting and distant aerial perspective.
* [x] **20.3. Post-Process Screen-Space Ghosting Lens Flare & Radial Chromatic Aberration (`GenerateLensFlareAndChromaticAberrationFunctions` in `CastleInternalShaderRHI`)**:
  * Synthesize multi-ghost thresholded HDR lens flares with screen-center reflection and $w^4$ radial window falloff (`EvaluateLensFlareGhostUV`) and spectral radial chromatic aberration (`EvaluateChromaticAberrationOffsets`) in the HDR post-processing pipeline.

**Milestone 20 Status**: Completed. Multi-Layer Clear Coat & Anisotropic GGX Brushed-Metal PBR (`EvaluateClearCoatBRDF`, `EvaluateAnisotropicGGX_D`, `GenerateClearCoatAndAnisotropicPBRFunctions`), Rayleigh / Mie Physical Sky & Aerial Perspective LUT (`TCastleVulkanAtmosphereRenderer` with 64-byte `TCastleAtmospherePushConstants`, $192 \times 108$ `pfRGBA16_Float` `SkyViewLUTTexture`, Rayleigh + Cornette-Shanks Mie single-scattering integration, and `DispatchAtmosphereSky`), and Screen-Space Ghosting Lens Flare & Radial Chromatic Aberration (`EvaluateChromaticAberrationOffsets`, `EvaluateLensFlareGhostUV`, `GenerateLensFlareAndChromaticAberrationFunctions`) fully integrated and tested (90 unit tests passing).


### Phase 21: Cloth Sheen & Iridescence Thin-Film PBR, Compute FFT / Gerstner Ocean Water Simulation & Screen-Space Motion Blur / Bokeh Depth of Field (COMPLETED)

* [x] **21.1. Velvet/Cloth Estevez-Kulla Sheen & Thin-Film Iridescence PBR (`GenerateClothSheenAndIridescencePBRFunctions` in `CastleInternalShaderRHI`)**:
  * Extend the PBR surface model (`KHR_materials_sheen`, `KHR_materials_iridescence`) with Estevez-Kulla inverted-Gaussian microfiber cloth sheen (`EvaluateCharlieSheen_D`) and Airy thin-film optical path difference spectral interference (`EvaluateThinFilmIridescence`) for velvet, satin, soap bubbles, and anodized metals.
* [x] **21.2. GPU Compute Gerstner Wave Ocean Simulation & Foam (`TCastleVulkanOceanSimulator` in `CastleInternalRHI_Vulkan`)**:
  * Simulate multi-octave directional Gerstner trochoidal ocean waves in a compute shader (`GenerateOceanDisplacementComputeShader`, `EvaluateGerstnerWavePoint`, `DispatchOceanSimulation`) outputting 3D displacement, analytical surface normal/slope, and Jacobian crest whitecap foam into `pfRGBA16_Float` displacement/normal maps (`DisplacementAndFoamTexture`, `NormalAndSlopeTexture`).
* [x] **21.3. Per-Pixel Velocity Motion Blur & Circle-of-Confusion Bokeh Depth of Field (`GenerateMotionBlurAndBokehDoFFunctions` in `CastleInternalShaderRHI`)**:
  * Compute thin-lens signed Circle of Confusion (`EvaluateThinLensCoC`) and velocity-line directional motion blur reconstruction (`EvaluateMotionBlurSampleWeight`) for cinematic camera post-processing.

**Milestone 21 Status**: Completed. Velvet/Cloth Estevez-Kulla Charlie Sheen & Thin-Film Iridescence PBR (`EvaluateCharlieSheen_D`, `EvaluateThinFilmIridescence`, `GenerateClothSheenAndIridescencePBRFunctions`), GPU Compute Gerstner Wave Ocean Simulation & Foam (`TCastleVulkanOceanSimulator` with 48-byte `TCastleOceanWavePushConstants`, $128 \times 128$ `pfRGBA16_Float` `DisplacementAndFoamTexture` + `NormalAndSlopeTexture`, analytical normals, and Jacobian whitecap crest foam), and Per-Pixel Velocity Motion Blur & Thin-Lens Bokeh Depth of Field (`EvaluateThinLensCoC`, `EvaluateMotionBlurSampleWeight`, `GenerateMotionBlurAndBokehDoFFunctions`) fully integrated and tested (93 unit tests passing).


### Phase 22: Diffuse Global Illumination Irradiance Probes (DDGI Octahedral Atlas), GPU Meshlet / Cluster Culling & CAS Spatial Upscaling + Sharpening (COMPLETED)

* [x] **22.1. Dynamic Diffuse Global Illumination (DDGI) Octahedral Probe Grid (`TCastleVulkanDDGIGrid` in `CastleInternalRHI_Vulkan`)**:
  * Maintain a 3D world-space irradiance probe volume (`TCastleDDGIGridParams`, 48B) encoded via $8 \times 8$ octahedral mapping with 1-texel border gutters (`OctahedralEncodeDir`, `OctahedralDecodeUV`, `EvaluateDDGIProbeWeight`, `GenerateDDGIProbeSamplingFunctions`, `DispatchDDGIUpdate`) into `pfRGBA16_Float` irradiance (`IrradianceAtlasTexture`) and `pfRG16_Float` Chebyshev visibility (`VisibilityAtlasTexture`) atlases.
* [x] **22.2. GPU Meshlet / Sub-Mesh Cluster Cone & Frustum Culling (`TCastleVulkanMeshletCuller` in `CastleInternalRHI_Vulkan`)**:
  * Partition high-poly meshes into 64-vertex / 124-triangle meshlet clusters (`TCastleMeshletDescriptor`, 48B) and cull backfacing normal cones (`EvaluateMeshletConeBackfaceCull`) and bounding spheres in a compute pass (`GenerateMeshletCullingComputeShader`, `EvaluateVisibleMeshletsCPU`, `DispatchMeshletCulling`).
* [x] **22.3. Contrast-Adaptive Sharpening (RCAS/CAS) & Edge-Adaptive Spatial Upscaling (`GenerateCASSharpeningAndUpscaleFunctions` in `CastleInternalShaderRHI`)**:
  * Implement AMD FidelityFX 5-tap Contrast-Adaptive Sharpening (`EvaluateCASFilter5Tap`) for halo-free high-DPI display presentation.

**Milestone 22 Status**: Completed. Dynamic Diffuse Global Illumination Octahedral Probe Grid (`TCastleVulkanDDGIGrid` with 48-byte `TCastleDDGIGridParams`, bijective octahedral encoding/decoding, Chebyshev variance shadow probe weighting, and `pfRGBA16_Float` / `pfRG16_Float` probe atlases), GPU Meshlet / Sub-Mesh Cluster Cone & Sphere Culling (`TCastleVulkanMeshletCuller` with 48-byte `TCastleMeshletDescriptor`, normal-cone backface cutoff rejection, and atomic visible meshlet compaction), and 5-tap Contrast-Adaptive Sharpening (`EvaluateCASFilter5Tap`, `GenerateCASSharpeningAndUpscaleFunctions`) fully integrated and tested (96 unit tests passing).


### Phase 23: Ray-Traced / Hardware Ray Query Shadows & Reflections (`VK_KHR_ray_query`), Virtual Shadow Maps (VSM Clipmap Pages) & Screen-Space Subsurface Scattering Diffusion (COMPLETED)

* [x] **23.1. Hardware Ray Query (`VK_KHR_ray_query` / `VK_KHR_acceleration_structure`) Inline Shadow & Reflection Traversal (`GenerateInlineRayQueryFunctions` in `CastleInternalShaderRHI`)**:
  * Support inline `rayQueryEXT` BVH ray-box/ray-triangle traversal and CPU/GPU ray-AABB & Möller-Trumbore ray-triangle intersection (`EvaluateRayTriangleIntersection`, `EvaluateRayAABBIntersection`) for hybrid ray-traced hard/soft shadows and glossy reflections.
* [x] **23.2. Virtual Shadow Maps (VSM) Page Table & Physical Tile Pool (`TCastleVulkanVirtualShadowMap` in `CastleInternalRHI_Vulkan`)**:
  * Manage a virtual shadow page table ($64 \times 64$ virtual pages mapped to a $16 \times 16$ pool of $128 \times 128$ physical texel tiles in a $2048 \times 2048$ `pfD32_Float` atlas) with on-demand page allocation (`RequestAndAllocateVirtualPage`, `ComputePhysicalAtlasUV`, `UploadPageTable`, `GenerateVSMPageLookupFunctions`).
* [x] **23.3. Separable Screen-Space Subsurface Scattering (SSSSS) Burley Diffusion Kernel (`GenerateSeparableSSSSFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate bilateral depth-aware separable screen-space subsurface scattering diffusion weights (`EvaluateBurleyDiffusionProfile`, `EvaluateBilateralSSSSWeight`, `EvaluateSeparableSSSSBlur7Tap`) for close-up skin rendering.

**Milestone 23 Status**: Completed. Hardware Ray Query (`GL_EXT_ray_query` inline shadow/reflection traversal plus CPU/GPU slab ray-AABB `EvaluateRayAABBIntersection` and Möller-Trumbore ray-triangle `EvaluateRayTriangleIntersection`), Virtual Shadow Maps (`TCastleVulkanVirtualShadowMap` with $64 \times 64$ virtual page table SSBO, $2048 \times 2048$ `pfD32_Float` physical tile pool, and `GenerateVSMPageLookupFunctions`), and Separable Screen-Space Subsurface Scattering (`EvaluateBurleyDiffusionProfile`, `EvaluateBilateralSSSSWeight`, `GenerateSeparableSSSSFunctions`) fully integrated and tested (99 unit tests passing).


### Phase 24: GPU-Driven Instance & Mesh LOD Selection, Screen-Space Bent Normals & Specular Occlusion, and Color Grading 3D LUT + Film Grain / Vignette Post-Processing (COMPLETED)

* [x] **24.1. GPU-Driven Continuous Instance LOD Selection & Screen-Height Metric (`TCastleVulkanLODSelector` in `CastleInternalRHI_Vulkan`)**:
  * Compute screen-space projected bounding sphere height / solid angle (`EvaluateProjectedScreenCoverage`, `SelectDiscreteLODLevel`) and dithered cross-fade transition factor across 4 discrete LOD levels (`LOD0..LOD3`) in a compute shader (`GenerateLODSelectionComputeShader`, `EvaluateInstanceLODsCPU`, `DispatchLODSelection`).
* [x] **24.2. Screen-Space Bent Normals & Jimenez Specular Occlusion (`GenerateBentNormalsAndSpecularOcclusionFunctions` in `CastleInternalShaderRHI`)**:
  * Reconstruct unoccluded horizon direction bent normals and evaluate Lagarde/Jimenez cone-intersection specular ambient occlusion (`EvaluateSpecularOcclusion`, `BendNormalTowardsUnoccludedDir`) to prevent specular light leaking in cavities and grazing angles.
* [x] **24.3. Trilinear 3D Color Grading LUT (`td3D`), Film Grain & Natural Vignette (`GenerateColorGradingLUTAndFilmGrainFunctions` in `CastleInternalShaderRHI`)**:
  * Implement half-texel-corrected 3D LUT color grading coordinate mapping (`Compute3DLUTSampleCoord`), natural $\cos^4(\theta)$ optical lens vignette (`EvaluateNaturalCos4Vignette`), and luminance-preserving spatio-temporal film grain (`EvaluateFilmGrainNoise`).

**Milestone 24 Status**: Completed. GPU-Driven Continuous Instance LOD Selection (`TCastleVulkanLODSelector` with 48-byte `TCastleLODInstanceDescriptor`, projected vertical screen-height coverage metric `EvaluateProjectedScreenCoverage`, 4-level discrete LOD selection + crossfade transition band `SelectDiscreteLODLevel`, and `GenerateLODSelectionComputeShader`), Screen-Space Bent Normals & Lagarde/Jimenez Specular Occlusion (`EvaluateSpecularOcclusion`, `BendNormalTowardsUnoccludedDir`, `GenerateBentNormalsAndSpecularOcclusionFunctions`), and Trilinear 3D Color Grading LUT + Natural $\cos^4(\theta)$ Vignette + Luminance-Preserving Film Grain (`Compute3DLUTSampleCoord`, `EvaluateNaturalCos4Vignette`, `EvaluateFilmGrainNoise`, `GenerateColorGradingLUTAndFilmGrainFunctions`) fully integrated and tested (102 unit tests passing).


### Phase 25: Volumetric Cloud Raymarching (Henyey-Greenstein Dual-Lobe Phase & Beer-Powder Law), GPU Texture Streaming Residency Feedback & Equirectangular-to-Cubemap Compute Panorama Converter (COMPLETED)

* [x] **25.1. Horizon-Aligned Volumetric Cloud Layer Raymarcher (`GenerateVolumetricCloudFunctions` in `CastleInternalShaderRHI`)**:
  * Implement dual-lobe Henyey-Greenstein forward/backward scattering phase (`EvaluateDualLobeHGPhase`) and Schneider's Beer-Powder multiple-scattering dark-edge sugar-powder approximation (`EvaluateBeerPowderTransmittance`).
* [x] **25.2. GPU Texture Streaming Mipmap Residency & Feedback Analyzer (`TCastleVulkanTextureStreamer` in `CastleInternalRHI_Vulkan`)**:
  * Track per-texture minimum requested mip levels from GPU UV derivative feedback (`ComputeDesiredMipLevel`, `GenerateTextureMipFeedbackFunctions`, `RegisterStreamableTexture`, `RecordMipFeedback`, `ResolveStreamingRequests`, `UploadFeedbackBuffer`).
* [x] **25.3. Equirectangular HDR Panorama to Cubemap Compute Converter (`GenerateEquirectToCubemapComputeShader` in `CastleInternalShaderRHI`)**:
  * Convert $2:1$ equirectangular `.hdr`/`.exr` panoramas into 6-face `tdCube` environment textures (`DirectionToEquirectangularUV`, `EquirectangularUVToDirection`, `CubeFaceUVToDirection`) in a single compute pass.

**Milestone 25 Status**: Completed. Volumetric Cloud Raymarching (`EvaluateDualLobeHGPhase`, `EvaluateBeerPowderTransmittance`, `GenerateVolumetricCloudFunctions`), GPU Texture Streaming Mipmap Residency & Feedback Analyzer (`TCastleVulkanTextureStreamer` with `ComputeDesiredMipLevel`, `RecordMipFeedback`, `ResolveStreamingRequests`, and `FeedbackBuffer`), and Equirectangular-to-Cubemap Compute Panorama Converter (`DirectionToEquirectangularUV`, `EquirectangularUVToDirection`, `GenerateEquirectToCubemapComputeShader`) fully integrated and tested (105 unit tests passing).


### Phase 26: Analytic Area Light LTC Shading, Seamless World-Space Triplanar & Height-Blended Texturing, and GPU Shadow Caster Light-Ray Extrusion Culling (COMPLETED)

* [x] **26.1. Analytic Polygonal / Rectangular Area Lights via Linearly Transformed Cosines (`GenerateAreaLightLTCFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate analytical rectangular area light solid angle & horizon-clipped irradiance (`EvaluateRectAreaLightSolidAngle`, `EvaluateLTCFilteredRoughness`) for physically based area lights.
* [x] **26.2. Seamless World-Space Triplanar & Height-Blended Texture Mapping (`GenerateTriplanarAndHeightBlendFunctions` in `CastleInternalShaderRHI`)**:
  * Compute power-sharpened triplanar projection weights (`EvaluateTriplanarBlendWeights`) and height-modulated multi-layer splat blending (`EvaluateHeightModulatedBlendWeights`) for steep cliffs, caves, and procedural geometry without UV seams.
* [x] **26.3. GPU Shadow Caster Frustum + Light-Ray Extrusion Culling (`TCastleVulkanShadowCasterCuller` in `CastleInternalRHI_Vulkan`)**:
  * Cull shadow-casting instances whose extruded light-direction bounding volume does not intersect the camera view frustum (`EvaluateShadowCasterExtrudedSphereIntersectsAABB`, `GenerateShadowCasterExtrusionCullingComputeShader`, `EvaluateActiveShadowCastersCPU`, `DispatchShadowCasterCulling`).

**Milestone 26 Status**: Completed. Analytic Rectangular Area Light Solid-Angle & LTC Roughness (`EvaluateRectAreaLightSolidAngle`, `EvaluateLTCFilteredRoughness`, `GenerateAreaLightLTCFunctions`), Seamless World-Space Triplanar & Height-Modulated Multi-Layer Splat Blending (`EvaluateTriplanarBlendWeights`, `EvaluateHeightModulatedBlendWeights`, `GenerateTriplanarAndHeightBlendFunctions`), and GPU Shadow Caster Light-Ray Extrusion Culling (`TCastleVulkanShadowCasterCuller`, `EvaluateShadowCasterExtrudedSphereIntersectsAABB`, `GenerateShadowCasterExtrusionCullingComputeShader`) fully integrated and tested (108 unit tests passing).


### Phase 27: Nanite-Style Visibility Buffer, Hierarchical Cluster DAG & Software Micro-Polygon Compute Rasterizer (COMPLETED)

* [x] **27.1. 64-Bit Visibility Buffer (`Depth32 | InstanceID20 | PrimitiveID12`) & Analytic Partial-Derivative Barycentric Reconstruction (`GenerateVisibilityBufferFunctions` in `CastleInternalShaderRHI`)**:
  * Pack visible instance/cluster/triangle IDs into a compact visibility payload (`PackVisibilityBufferPayload`, `UnpackVisibilityBufferPayload`) and reconstruct perspective-correct barycentric coordinates $(\lambda_0, \lambda_1, \lambda_2)$ and analytical screen-space UV gradients ($\partial \text{uv}/\partial x$, $\partial \text{uv}/\partial y$, `EvaluatePerspectiveBarycentrics2D`) in a deferred material shading pass without $2 \times 2$ quad overshading.
* [x] **27.2. Hierarchical Cluster DAG Cut Selection & Monotonic Parent-Child Screen-Space Error (`TCastleVulkanClusterDAG` in `CastleInternalRHI_Vulkan`)**:
  * Evaluate Nanite-style monotonic cluster group error bounds (`EvaluateClusterProjectedErrorPixels`, `IsClusterDAGCutNode`, `GenerateClusterDAGCutComputeShader`, `EvaluateDAGCutCPU`, `DispatchDAGCutSelection`) where a cluster is rendered iff `ParentProjectedError > PixelErrorThreshold >= SelfProjectedError`, guaranteeing crack-free seamless LOD transitions across adjacent meshlets without index stitching.
* [x] **27.3. Sub-Pixel Software Compute Micro-Triangle Rasterizer (`GenerateSoftwareMicroRasterComputeShader` in `CastleInternalShaderRHI`)**:
  * Rasterize sub-pixel / micro-polygon clusters ($< 8 \times 8$ pixels) directly in a compute shader via 2D edge-function bounding boxes (`EvaluateEdgeFunction2D`, `IsMicroTriangleCandidateForSoftwareRaster`) and `atomicMin` 64-bit depth+payload writes, bypassing fixed-function hardware rasterizer quad-occupancy bottlenecks.

**Milestone 27 Status**: Completed. 64-Bit Visibility Buffer & Perspective-Correct Barycentrics (`PackVisibilityBufferPayload`, `UnpackVisibilityBufferPayload`, `EvaluatePerspectiveBarycentrics2D`, `GenerateVisibilityBufferFunctions`), Hierarchical Cluster DAG Cut Selection (`TCastleVulkanClusterDAG`, `EvaluateClusterProjectedErrorPixels`, `IsClusterDAGCutNode`, `GenerateClusterDAGCutComputeShader`), and Sub-Pixel Software Compute Micro-Triangle Rasterizer (`EvaluateEdgeFunction2D`, `IsMicroTriangleCandidateForSoftwareRaster`, `GenerateSoftwareMicroRasterComputeShader`) fully integrated and tested (111 unit tests passing).


### Phase 28: Lumen-Style Signed Distance Field (SDF) Global Illumination, Surface Cache Cards & Screen-Space Radiance Cache (COMPLETED)

* [x] **28.1. Mesh SDF & 3D Clipmap Global Signed Distance Field Sphere Tracing (`TCastleVulkanGlobalSDF` in `CastleInternalRHI_Vulkan`, `GenerateGlobalSDFTraceFunctions` in `CastleInternalShaderRHI`)**:
  * Maintain a multi-cascade 3D `td3D` Global SDF clipmap (`EvaluateSDFBoxDistance`, `EvaluateSDFSmoothUnion`, `TraceSphereMarchCPU`, `EvaluateSDFSoftShadowCone`, `DispatchGlobalSDFBuild`) for fast hardware-ray-tracing-free software ray queries, sky occlusion, and off-screen GI.
* [x] **28.2. Lumen-Style 6-Axis Surface Cache Card Atlas (`TCastleVulkanSurfaceCache` in `CastleInternalRHI_Vulkan`, `GenerateSurfaceCacheCardFunctions` in `CastleInternalShaderRHI`)**:
  * Project mesh surface direct lighting, albedo, and normals into an axis-aligned card atlas (`SelectDominantSurfaceCardAxis`, `ComputeSurfaceCacheAtlasUV`, `AllocateSixAxisCards`, `GetCardAtlasOffsetAndScale`) so SDF sphere hits can evaluate multi-bounce indirect radiance at any world hit point.
* [x] **28.3. Screen-Space Radiance Cache Probe Interpolation & Importance Sampling (`GenerateScreenRadianceCacheFunctions` in `CastleInternalShaderRHI`)**:
  * Place sparse screen-space radiance probes (`EvaluateScreenProbeBilateralWeight`, `CosineWeightedHemisphereSample`) to decouple full-resolution shading from expensive GI raymarching.

**Milestone 28 Status**: Completed. 3D Clipmap Global Signed Distance Field Sphere Tracing (`TCastleVulkanGlobalSDF`, `EvaluateSDFBoxDistance`, `EvaluateSDFSmoothUnion`, `EvaluateSDFSoftShadowCone`, `GenerateGlobalSDFTraceFunctions`), Lumen-Style 6-Axis Surface Cache Card Atlas (`TCastleVulkanSurfaceCache`, `SelectDominantSurfaceCardAxis`, `ComputeSurfaceCacheAtlasUV`, `GenerateSurfaceCacheCardFunctions`), and Screen-Space Radiance Cache Probe Interpolation & Importance Sampling (`EvaluateScreenProbeBilateralWeight`, `CosineWeightedHemisphereSample`, `GenerateScreenRadianceCacheFunctions`) fully integrated and tested (114 unit tests passing).


### Phase 29: ReSTIR DI / GI Spatio-Temporal Reservoir Resampling (UE5 MegaLights Architecture) (PLANNED)

* [ ] **29.1. Weighted Reservoir Sampling (WRS) & Streaming RIS (`GenerateReSTIRReservoirFunctions` in `CastleInternalShaderRHI`)**:
  * Implement constant-memory streaming reservoirs (`TCastleReSTIRReservoir`, 32B: `SelectedLightID`, `WeightSum`, `TargetPDF`, `SampleCountM`, `ContributionWeightW`) and unbiased contribution weight computation $W = \frac{1}{\hat{p}(y)} \cdot \frac{1}{M} \sum w_i$ (`EvaluateLuminanceTargetPDF`, `UpdateReservoirSample`, `FinalizeReservoirWeight`).
* [ ] **29.2. Temporal & Spatial Neighbor Reservoir Combination (`TCastleVulkanReSTIR` in `CastleInternalRHI_Vulkan`)**:
  * Reproject previous-frame reservoirs with history M-capping (`MaxHistoryM = 20`) and combine spatial neighbor reservoirs with depth/normal similarity rejection (`CombineReservoirs`, `EvaluateReSTIRNeighborSimilarity`) to shade thousands of shadow-casting dynamic lights ("MegaLights") with 1–2 shadow rays per pixel.


### Phase 30: Temporal Super Resolution (TSR) Sub-Pixel History Upscaling & Disocclusion Anti-Ghosting (PLANNED)

* [ ] **30.1. Lanczos-2 / Blackman-Harris Sub-Pixel Reconstruction Kernel & History Upsampling (`TCastleVulkanTSRUpscaler` in `CastleInternalRHI_Vulkan`, `GenerateTSRUpscaleComputeShader` in `CastleInternalShaderRHI`)**:
  * Upscale lower-resolution input frames ($50\%\text{–}75\%$ render scale, e.g. 1080p $\to$ 4K) into full-resolution history buffers using windowed Lanczos-2 and Blackman-Harris kernel weights (`EvaluateLanczos2Weight`, `EvaluateBlackmanHarrisWeight`).
* [ ] **30.2. Parallax Disocclusion Detection, Thin-Feature Responsiveness & Flicker Suppression (`EvaluateTSRDisocclusionConfidence`, `EvaluateTSRThinGeometryBlend` in `CastleInternalShaderRHI`)**:
  * Detect depth-buffer parallax disocclusions and sub-pixel thin geometry (wires, foliage, hair) to dynamically boost current-frame responsiveness without ghosting or moiré shimmering.


### Phase 31: Substrate / Strata Multi-Lobe Layered Material Slabs, Glint Microfacet Sparkles & Dual-Specular Marschner Hair/Fur BSDF (PLANNED)

* [ ] **31.1. Energy-Conserving Layered Material Slabs & Vertical Coating Transmittance (`GenerateSubstrateLayeredMaterialFunctions` in `CastleInternalShaderRHI`)**:
  * Model arbitrary vertical/horizontal material slab hierarchies (UE5 Substrate/Strata architecture) with directional albedo energy conservation $T_{\text{bottom}} = (1 - E_{\text{top}}(\theta_o)) \cdot (1 - E_{\text{top}}(\theta_i))$ and Beer-Lambert medium absorption (`EvaluateLayeredSlabComposition`).
* [ ] **31.2. Marschner / Chiang Dual-Specular Hair & Fur Fiber BSDF (`GenerateHairMarschnerBSDF` in `CastleInternalShaderRHI`)**:
  * Implement longitudinal $M_R, M_{TT}, M_{TRT}$ Gaussian/cuticle-tilt lobes and azimuthal $N_R, N_{TT}, N_{TRT}$ scattering (`EvaluateMarschnerLongitudinalM`, `EvaluateHairAzimuthalTRT`) for realistic strand and card hair/fur rendering.
* [ ] **31.3. Stochastic Discrete Microfacet Glints & Sparkles (`EvaluateStochasticGlintNDF` in `CastleInternalShaderRHI`)**:
  * Evaluate discrete microfacet normal distributions within the pixel footprint for metallic car paint, snow, sand, and rough mineral sparkles.


### Phase 32: Hardware Mesh Shaders (`VK_EXT_mesh_shader`), Variable Rate Shading (`VK_KHR_fragment_shading_rate`) & Runtime Virtual Texturing (RVT) (PLANNED)

* [ ] **32.1. Task & Mesh Shader Pipeline (`VK_EXT_mesh_shader`, `GenerateMeshShaderStageFunctions` in `CastleInternalShaderRHI`)**:
  * Support hardware Task and Mesh shader stages emitting `gl_MeshVerticesEXT` and `gl_PrimitiveTriangleIndicesEXT` directly from meshlet clusters (`TCastleMeshletDescriptor`, `ComputeMeshletTaskGroupCount`).
* [ ] **32.2. Per-Draw & Tile-Based Variable Rate Shading (`VK_KHR_fragment_shading_rate`, `TCastleVulkanVRSManager` in `CastleInternalRHI_Vulkan`)**:
  * Generate screen-space $16 \times 16$ tile shading rate images (`1x1`, `1x2`, `2x1`, `2x2`, `4x4`) driven by luminance contrast and velocity (`SelectOptimalShadingRateTile`, `GenerateVRSContrastComputeShader`).
* [ ] **32.3. Runtime Virtual Texturing (RVT) Page Table & Physical Material Tile Cache (`TCastleVulkanRuntimeVirtualTexture` in `CastleInternalRHI_Vulkan`)**:
  * Composite multi-layer terrain splats, road splines, and world decals into on-demand virtual texture pages (`RequestRVTPage`, `TranslateRVTPageToPhysicalUV`) to replace expensive per-pixel multi-layer terrain blending with a single cache lookup.


### Phase 33: Single-Layer Water Refraction, Absorption & Photon Caustics, Sparse Heterogeneous Volume Bricks & GPU Breadcrumb Crash Tracker (PLANNED)

* [ ] **33.1. Physically Based Single-Layer Water Volume Beer-Lambert Absorption, Refraction & Caustics (`GenerateSingleLayerWaterFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate depth-dependent water phase scattering, RGB optical absorption coefficients, Snell's law screen-space refraction offset (`EvaluateWaterBeerLambertAbsorption`, `ComputeWaterRefractionUVOffset`), and underwater caustics (`EvaluateWaterCausticsPattern`).
* [ ] **33.2. Sparse Brick-Atlas Heterogeneous Volumes (`TCastleVulkanSparseVolumeAtlas` in `CastleInternalRHI_Vulkan`)**:
  * Pack active $8 \times 8 \times 8$ smoke/fire/explosion voxel bricks into a sparse 3D indirection table + physical brick pool (`AllocateVolumeBrick`, `EvaluateBlackbodyEmissionRGB`) with physically based temperature-to-RGB Planckian blackbody emission.
* [ ] **33.3. GPU Breadcrumb Marker Buffer & `VK_ERROR_device_lost` Diagnostics (`TCastleVulkanBreadcrumbTracker` in `CastleInternalRHI_Vulkan`)**:
  * Record fine-grained command-buffer pass/draw markers into a host-coherent breadcrumb buffer (`BeginBreadcrumbScope`, `EndBreadcrumbScope`, `FormatBreadcrumbCrashReport`) to pinpoint exact GPU hangs and TDR faults.


## 4.1. Unreal Engine 5 vs. Castle Game Engine Vulkan RHI Feature Parity Matrix

| Unreal Engine 5 Subsystem | Castle Game Engine Vulkan RHI Equivalent | Phase & Status |
| :--- | :--- | :--- |
| **RDG (Render Dependency Graph)** | `TRHIRenderGraph` & `TRHIRenderGraphPass` (DAG topological sort, dead-pass culling, transient texture aliasing, automatic barrier hoisting) | Phase 15 (COMPLETED) |
| **Virtual Shadow Maps (VSM)** | `TCastleVulkanVirtualShadowMap` ($64 \times 64$ virtual page table, $16 \times 16$ physical $128 \times 128$ tile pool, `GenerateVSMPageLookupFunctions`) | Phase 23 (COMPLETED) |
| **Nanite Cluster Culling** | `TCastleVulkanMeshletCuller` (64v/124t meshlets, cone backface + sphere culling) & `TCastleVulkanComputeCuller` (Hi-Z + frustum + `vkCmdDrawIndexedIndirectCount`) | Phases 7–9, 22 (COMPLETED) |
| **Nanite Visibility Buffer, Cluster DAG & Software Micro-Rasterizer** | `GenerateVisibilityBufferFunctions` (64-bit payload + analytic UV derivatives), `TCastleVulkanClusterDAG` (monotonic parent/child error cut), `GenerateSoftwareMicroRasterComputeShader` | Phase 27 (COMPLETED) |
| **Lumen GI & Reflections (Hardware + Software)** | `TCastleVulkanDDGIGrid` (Octahedral irradiance + Chebyshev visibility probes), `TCastleVulkanSSR` (Hi-Z raymarch), `VK_KHR_ray_query` (`GenerateInlineRayQueryFunctions`), plus Global SDF Clipmap (`TCastleVulkanGlobalSDF`), 6-Axis Surface Cache (`TCastleVulkanSurfaceCache`) & Screen Radiance Cache (`GenerateScreenRadianceCacheFunctions`) | Phases 16, 22, 23, 28 (COMPLETED) |
| **MegaLights / ReSTIR Direct & Indirect Lighting** | `TCastleVulkanClusteredLightCuller` (3D Forward+ 256+ lights) + `TCastleVulkanReSTIR` (Spatio-temporal reservoir resampling WRS/RIS) | Phase 14 (COMPLETED) & Phase 29 (PLANNED) |
| **Temporal Super Resolution (TSR) & TAA** | `TCastleVulkanTAA` (Halton jitter + YCoCg variance clipping) + `TCastleVulkanTSRUpscaler` (Lanczos-2 sub-pixel history upscaling & disocclusion anti-ghosting) + CAS (`EvaluateCASFilter5Tap`) | Phases 16, 22 (COMPLETED) & Phase 30 (PLANNED) |
| **Substrate / Strata Material System** | Full Cook-Torrance GGX PBR, Clear Coat, Anisotropy, Subsurface/Transmission, Cloth Sheen, Thin-Film Iridescence, Separable Burley SSSS, plus Energy-Conserving Layered Material Slabs, Marschner Hair/Fur BSDF & Stochastic Glints | Phases 13, 19–21, 23 (COMPLETED) & Phase 31 (PLANNED) |
| **Sky Atmosphere, Volumetric Fog & Volumetric Clouds** | `TCastleVulkanAtmosphereRenderer` (Rayleigh/Mie Sky-View LUT), `TCastleVulkanVolumetricFog` ($160 \times 90 \times 64$ Froxel Fog), `GenerateVolumetricCloudFunctions` (Dual-Lobe HG + Beer-Powder) | Phases 16, 20, 25 (COMPLETED) |
| **Niagara GPU Particles** | `TCastleVulkanComputeParticles` (Compute simulation + `vkCmdDrawIndirect`) | Phase 17 (COMPLETED) |
| **Water System (Ocean + Single-Layer Water)** | `TCastleVulkanOceanSimulator` (Gerstner wave spectrum + Jacobian crest foam) + Single-Layer Water Beer-Lambert absorption, Snell refraction & photon caustics | Phase 21 (COMPLETED) & Phase 33 (PLANNED) |
| **World Partition Landscape & Runtime Virtual Texturing (RVT)** | `TCastleVulkanTerrainCDLOD` (Quadtree morphing CDLOD), `TCastleVulkanTextureStreamer` (GPU mip feedback), Triplanar/Height blending & `TCastleVulkanRuntimeVirtualTexture` | Phases 19, 25 (COMPLETED) & Phases 26, 32 (PLANNED) |
| **Hardware Mesh Shaders & Variable Rate Shading (VRS)** | `VK_EXT_mesh_shader` (`GenerateMeshShaderStageFunctions`) & `VK_KHR_fragment_shading_rate` (`TCastleVulkanVRSManager`) | Phase 32 (PLANNED) |
| **Heterogeneous Volumes & GPU Crash Breadcrumbs** | `TCastleVulkanSparseVolumeAtlas` (Planckian blackbody emission) & `TCastleVulkanBreadcrumbTracker` | Phase 33 (PLANNED) |


## 5. Build Tool (castle-engine) & Editor Integration

* [x] CastleEngineManifest.xml Support:
```xml
<project name="my_game" render_backend="auto"> <!-- auto | opengl | opengles | vulkan -->
```
* [x] Shader & PSO Pre-warming (Build Step & Runtime `PrepareResources`): `TCastleManifest.ShouldPrewarmVulkanShaders`, `TPackageDirectory.AddDataInformation` (`ToolPackage`), and `TCastleShaderCompiler.PrewarmCoreEngineShaders` pre-compile and cache known core engine shaders (3D forward pass, shadow depth pass, screen effects) to SPIR-V, while `TVulkanRHIDevice.PrewarmStandardPipelines` hooked into `TCastleViewport.PrepareResources` loads/saves `VkPipelineCache` (`castle-config:/vulkan_pipeline_cache.bin`) and bakes standard 3D/2D PSOs (and `VK_EXT_graphics_pipeline_library` sub-libraries) before the first rendered frame.
* [x] Editor Diagnostics: Update CastleRenderOptions and `TCastleViewport.Statistics` to report active RHI backend, MSAA sample count, PSO cache hits/misses, Descriptor Set allocations, active bindless textures, compute dispatches, GPU frame time (ms), and live Vulkan device memory usage/budget (`VK_EXT_memory_budget` via `vkGetPhysicalDeviceMemoryProperties2`).


## 6. Risk Management & Mitigations

| Risk | Impact | Mitigation Strategy |
| :--- | :--- | :--- |
| Custom User Shaders (`Effect` node) using legacy GLSL syntax | Medium | Keep `CastleRendererInternalShader` string preprocessor capable of wrapping user `PLUG_` functions into `#version 450` templates; emit clear `WritelnWarning` diagnostics (`TCastleShaderGeneratorRHI.UpgradeLegacyGLSLBuiltIns`) if user shaders use deprecated raw GL uniforms/built-ins while auto-upgrading them, and reflect/validate pre-compiled `.spv` binaries via pure Pascal `InspectSPIRVBytecode` & `ValidateSPIRVDescriptorBindings` without requiring `libshaderc` (Implemented). |
| PSO Stutter during gameplay when new material permutations appear | High | Use `VkPipelineCache` saved to disk (`castle-config:/vulkan_pipeline_cache.bin`), utilize `VK_EXT_graphics_pipeline_library` (`GetOrCreateVertexInputLibrary`, `GetOrCreatePreRasterizationLibrary`, `GetOrCreateFragmentShaderLibrary`, `GetOrCreateFragmentOutputLibrary` + `VkPipelineLibraryCreateInfoKHR` fast-linking) and `VK_EXT_extended_dynamic_state` where available, and pre-warm pipelines during `TCastleViewport.PrepareResources` via `TVulkanRHIDevice.PrewarmStandardPipelines` (Implemented). |
| Windows 4096 `maxMemoryAllocationCount` Kernel Limit | High | Route all `TVulkanRHIBuffer` and `TVulkanRHITexture` allocations through `TCastleVulkanMemoryAllocator` (inspired by PasVulkan's `TpvVulkanMemoryManager` and AMD VMA) with separate Linear/Non-Linear pools per `memoryTypeIndex`, $O(1)$ doubly-linked node coalescing, persistent host mapping, `VK_KHR_dedicated_allocation`, and a 4096 `MaxMemoryAllocationCount` safety guard (Implemented). |
| Cross-Vendor Driver Differences (Format Support, Alignment Limits & In-Flight Resource Destruction) | High | Query `vkGetPhysicalDeviceFormatProperties` via `NegotiateOptimalPixelFormat` to fall back across vendor-supported depth/stencil and compressed formats; separate combined depth+stencil barrier vs sampled view aspect masks (`GetFormatTransitionAspectMask` vs `GetFormatViewAspectMask`); enforce `minUniformBufferOffsetAlignment`, `minStorageBufferOffsetAlignment`, `optimalBufferCopyOffsetAlignment`, and `nonCoherentAtomSize` (`FlushAllocation` / `InvalidateAllocation`); and retire destroyed buffers/textures via per-frame deferred deletion queues (`FlushDeferredDeletions`) synchronized with each frame's `VkFence` (Implemented). |
| FPC & Delphi Compatibility & Header Maintenance across 32/64-bit targets | Medium | Auto-generate `CastleInternalVulkan` directly from the official Khronos `vk.xml` registry via `tools/internal/generate_vulkan_api/vkxml2pas.dpr` (inspired by BeRo's PasVulkan `vkxml2pas`) with strict flat C-ABI bindings and zero external C++ wrapper dependencies (Implemented). |
| Older Mobile / Integrated GPUs lacking Vulkan 1.3 (Vulkan 1.1 / 1.2) | Medium | Negotiate instance API version via `vkEnumerateInstanceVersion` (`NegotiateInstanceApiVersion`), resolve Vulkan 1.1/1.2 extension prerequisite chains (`ResolveVulkan11_12DeviceConfig`), and fall back to cached `LoadOp`/`StoreOp`-aware `VkRenderPass` + `VkFramebuffer` (`GetOrCreateFallbackRenderPass` / `GetOrCreateFallbackFramebuffer`) if `VK_KHR_dynamic_rendering` or its 1.1 prerequisites (`VK_KHR_create_renderpass2`, `VK_KHR_depth_stencil_resolve`) are absent, or automatically fall back to OpenGLES 3.0 / OpenGL (Implemented). |

## 7. Testing & Verification Criteria

* [x] Automated Visual Regression Tests: `CompareImagesPerceptualDiff` in `CastleInternalRHI` compares framebuffer readbacks (`GrabTextureImage`) between `rbOpenGL` and `rbVulkan` using normalized RMSE perceptual diff thresholds.
* [x] Validation Cleanliness: Headless test suite (`TTestCastleVulkanRHI`, 114 unit tests) runs cleanly on Linux/WSL and supports `VK_LAYER_KHRONOS_validation`.
* [x] Performance Target: Batched 2D/3D RHI command recording, push constants, secondary command buffers, bindless texture indexing, extended dynamic state, GPU-driven compute frustum/distance/Hi-Z occlusion culling (`TCastleVulkanComputeCuller`), Clustered Forward+ compute light culling (`TCastleVulkanClusteredLightCuller`), Declarative Render Graph (`TRHIRenderGraph`), Compute GTAO (`TCastleVulkanGTAO`), Hi-Z SSR (`TCastleVulkanSSR`), Froxel Volumetric Fog (`TCastleVulkanVolumetricFog`), Temporal Anti-Aliasing (`TCastleVulkanTAA`), Box-Projected Reflection Probes (`TCastleVulkanReflectionProbeManager`), OBB Decal Projection (`TCastleVulkanDecalManager`), GPU Compute Particles (`TCastleVulkanComputeParticles`), Weighted Blended OIT (`TCastleVulkanWeightedBlendedOIT`), Contact Shadows (`TCastleVulkanContactShadows`), Compute Skinning & Morph Targets (`TCastleVulkanComputeSkinner`), GPU-Driven Terrain CDLOD (`TCastleVulkanTerrainCDLOD`), Atmosphere Sky-View LUT (`TCastleVulkanAtmosphereRenderer`), Gerstner Ocean Simulator (`TCastleVulkanOceanSimulator`), DDGI Octahedral Probe Grid (`TCastleVulkanDDGIGrid`), GPU Meshlet Culler (`TCastleVulkanMeshletCuller`), Virtual Shadow Maps (`TCastleVulkanVirtualShadowMap`), GPU-Driven LOD Selector (`TCastleVulkanLODSelector`), GPU Texture Streamer (`TCastleVulkanTextureStreamer`), Shadow Caster Extrusion Culler (`TCastleVulkanShadowCasterCuller`), Nanite Cluster DAG (`TCastleVulkanClusterDAG`), Lumen Global SDF & Surface Cache (`TCastleVulkanGlobalSDF`, `TCastleVulkanSurfaceCache`), and `vkCmdDrawIndexedIndirect` / `vkCmdDrawIndexedIndirectCount` / `vkCmdDispatchIndirect` minimize CPU driver overhead.
