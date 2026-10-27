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


### Phase 29: ReSTIR DI / GI Spatio-Temporal Reservoir Resampling (UE5 MegaLights Architecture) (COMPLETED)

* [x] **29.1. Weighted Reservoir Sampling (WRS) & Streaming RIS (`GenerateReSTIRReservoirFunctions` in `CastleInternalShaderRHI`)**:
  * Implement constant-memory streaming reservoirs (`TCastleReSTIRReservoir`, 32B: `SelectedLightID`, `WeightSum`, `TargetPDF`, `SampleCountM`, `ContributionWeightW`) and unbiased contribution weight computation $W = \frac{1}{\hat{p}(y)} \cdot \frac{1}{M} \sum w_i$ (`InitReSTIRReservoir`, `EvaluateLuminanceTargetPDF`, `UpdateReservoirSample`, `FinalizeReservoirWeight`).
* [x] **29.2. Temporal & Spatial Neighbor Reservoir Combination (`TCastleVulkanReSTIR` in `CastleInternalRHI_Vulkan`, `GenerateReSTIRSpatialTemporalComputeShader` in `CastleInternalShaderRHI`)**:
  * Reproject previous-frame reservoirs with history M-capping (`MaxHistoryM = 20`) and combine spatial neighbor reservoirs with depth/normal similarity rejection (`CombineReservoirs`, `EvaluateReSTIRNeighborSimilarity`, `EnsureReservoirBuffers`, `SwapReservoirHistory`, `DispatchSpatioTemporalResampling`) to shade thousands of shadow-casting dynamic lights ("MegaLights") with 1–2 shadow rays per pixel.

**Milestone 29 Status**: Completed. Weighted Reservoir Sampling & Streaming RIS (`TCastleReSTIRReservoir`, `EvaluateLuminanceTargetPDF`, `UpdateReservoirSample`, `FinalizeReservoirWeight`, `GenerateReSTIRReservoirFunctions`) and Spatio-Temporal Neighbor Reservoir Combination (`TCastleVulkanReSTIR`, `EvaluateReSTIRNeighborSimilarity`, `CombineReservoirs`, `GenerateReSTIRSpatialTemporalComputeShader`) fully integrated and tested (117 unit tests passing).


### Phase 30: Temporal Super Resolution (TSR) Sub-Pixel History Upscaling & Disocclusion Anti-Ghosting (COMPLETED)

* [x] **30.1. Lanczos-2 / Blackman-Harris Sub-Pixel Reconstruction Kernel & History Upsampling (`TCastleVulkanTSRUpscaler` in `CastleInternalRHI_Vulkan`, `GenerateTSRUpscaleComputeShader` in `CastleInternalShaderRHI`)**:
  * Upscale lower-resolution input frames ($50\%\text{–}75\%$ render scale, e.g. 1280x720 $\to$ 1920x1080) into full-resolution history buffers using windowed Lanczos-2 and Blackman-Harris kernel weights (`EvaluateLanczos2Weight`, `EvaluateBlackmanHarrisWeight`, `ComputeInputResolution`, `EnsureUpscaleTargets`, `SwapHistoryTargets`, `DispatchTSRUpscale`).
* [x] **30.2. Parallax Disocclusion Detection, Thin-Feature Responsiveness & Flicker Suppression (`EvaluateTSRDisocclusionConfidence`, `EvaluateTSRThinGeometryBlend` in `CastleInternalShaderRHI`)**:
  * Detect depth-buffer parallax disocclusions and sub-pixel thin geometry (wires, foliage, hair) to dynamically boost current-frame responsiveness without ghosting or moiré shimmering.

**Milestone 30 Status**: Completed. Lanczos-2 / Blackman-Harris Sub-Pixel Reconstruction Kernels (`EvaluateLanczos2Weight`, `EvaluateBlackmanHarrisWeight`, `GenerateTSRUpscaleComputeShader`), Parallax Disocclusion Confidence & Thin-Feature Anti-Ghosting (`EvaluateTSRDisocclusionConfidence`, `EvaluateTSRThinGeometryBlend`), and GPU Temporal Super Resolution History Upscaler (`TCastleVulkanTSRUpscaler`) fully integrated and tested (120 unit tests passing).


### Phase 31: Substrate / Strata Multi-Lobe Layered Material Slabs, Glint Microfacet Sparkles & Dual-Specular Marschner Hair/Fur BSDF (COMPLETED)

* [x] **31.1. Energy-Conserving Layered Material Slabs & Vertical Coating Transmittance (`GenerateSubstrateLayeredMaterialFunctions` in `CastleInternalShaderRHI`)**:
  * Model arbitrary vertical/horizontal material slab hierarchies (UE5 Substrate/Strata architecture) with directional albedo energy conservation $T_{\text{bottom}} = (1 - E_{\text{top}}(\theta_o)) \cdot (1 - E_{\text{top}}(\theta_i))$ and Beer-Lambert medium absorption (`EvaluateDirectionalSlabAlbedo`, `EvaluateLayeredSlabComposition`).
* [x] **31.2. Marschner / Chiang Dual-Specular Hair & Fur Fiber BSDF (`GenerateHairMarschnerBSDF` in `CastleInternalShaderRHI`)**:
  * Implement longitudinal $M_R, M_{TT}, M_{TRT}$ Gaussian/cuticle-tilt lobes and azimuthal $N_R, N_{TT}, N_{TRT}$ scattering (`EvaluateMarschnerLongitudinalM`, `EvaluateHairDualSpecularBSDF`) for realistic strand and card hair/fur rendering.
* [x] **31.3. Stochastic Discrete Microfacet Glints & Sparkles (`GenerateStochasticGlintFunctions`, `EvaluateStochasticGlintNDF` in `CastleInternalShaderRHI`)**:
  * Evaluate discrete microfacet normal distributions within the pixel footprint for metallic car paint, snow, sand, and rough mineral sparkles.

**Milestone 31 Status**: Completed. UE5 Substrate/Strata Energy-Conserving Layered Material Slabs (`EvaluateDirectionalSlabAlbedo`, `EvaluateLayeredSlabComposition`, `GenerateSubstrateLayeredMaterialFunctions`), Marschner/Chiang Dual-Specular Hair & Fur BSDF (`EvaluateMarschnerLongitudinalM`, `EvaluateHairDualSpecularBSDF`, `GenerateHairMarschnerBSDF`), and Stochastic Discrete Microfacet Glints (`EvaluateStochasticGlintNDF`, `GenerateStochasticGlintFunctions`) fully integrated and tested (123 unit tests passing).


### Phase 32: Hardware Mesh Shaders (`VK_EXT_mesh_shader`), Variable Rate Shading (`VK_KHR_fragment_shading_rate`) & Runtime Virtual Texturing (RVT) (COMPLETED)

* [x] **32.1. Task & Mesh Shader Pipeline (`VK_EXT_mesh_shader`, `GenerateMeshShaderStageFunctions` in `CastleInternalShaderRHI`)**:
  * Support hardware Task and Mesh shader stages emitting `gl_MeshVerticesEXT` and `gl_PrimitiveTriangleIndicesEXT` directly from meshlet clusters (`TCastleMeshletDescriptor`, `ComputeMeshletTaskGroupCount`).
* [x] **32.2. Per-Draw & Tile-Based Variable Rate Shading (`VK_KHR_fragment_shading_rate`, `TCastleVulkanVRSManager` in `CastleInternalRHI_Vulkan`)**:
  * Generate screen-space $16 \times 16$ tile shading rate images (`1x1`, `1x2`, `2x1`, `2x2`, `4x4`) driven by luminance contrast and velocity (`SelectOptimalShadingRateTile`, `GenerateVRSContrastComputeShader`).
* [x] **32.3. Runtime Virtual Texturing (RVT) Page Table & Physical Material Tile Cache (`TCastleVulkanRuntimeVirtualTexture` in `CastleInternalRHI_Vulkan`)**:
  * Composite multi-layer terrain splats, road splines, and world decals into on-demand virtual texture pages (`RequestRVTPage`, `TranslateRVTPageToPhysicalUV`) to replace expensive per-pixel multi-layer terrain blending with a single cache lookup.

**Milestone 32 Status**: Completed. Hardware Task & Mesh Shader Pipeline (`VK_EXT_mesh_shader`, `GenerateMeshShaderStageFunctions`, `ComputeMeshletTaskGroupCount`), Tile-Based Variable Rate Shading (`VK_KHR_fragment_shading_rate`, `TCastleVulkanVRSManager`, `SelectOptimalShadingRateTile`, `GenerateVRSContrastComputeShader`), and Runtime Virtual Texturing Page Table & Physical Material Tile Cache (`TCastleVulkanRuntimeVirtualTexture`, `RequestRVTPage`, `TranslateRVTPageToPhysicalUV`, `GenerateRVTLookupFunctions`) fully integrated and tested (126 unit tests passing).


### Phase 33: Single-Layer Water Refraction, Absorption & Photon Caustics, Sparse Heterogeneous Volume Bricks & GPU Breadcrumb Crash Tracker (COMPLETED)

* [x] **33.1. Physically Based Single-Layer Water Volume Beer-Lambert Absorption, Refraction & Caustics (`GenerateSingleLayerWaterFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate depth-dependent water phase scattering, RGB optical absorption coefficients, Snell's law screen-space refraction offset (`EvaluateWaterBeerLambertAbsorption`, `ComputeWaterRefractionUVOffset`), and underwater caustics (`EvaluateWaterCausticsPattern`).
* [x] **33.2. Sparse Brick-Atlas Heterogeneous Volumes (`TCastleVulkanSparseVolumeAtlas` in `CastleInternalRHI_Vulkan`)**:
  * Pack active $8 \times 8 \times 8$ smoke/fire/explosion voxel bricks into a sparse 3D indirection table + physical brick pool (`AllocateVolumeBrick`, `EvaluateBlackbodyEmissionRGB`, `GenerateSparseVolumeBlackbodyFunctions`) with physically based temperature-to-RGB Planckian blackbody emission.
* [x] **33.3. GPU Breadcrumb Marker Buffer & `VK_ERROR_device_lost` Diagnostics (`TCastleVulkanBreadcrumbTracker` in `CastleInternalRHI_Vulkan`)**:
  * Record fine-grained command-buffer pass/draw markers into a host-coherent breadcrumb buffer (`BeginBreadcrumbScope`, `EndBreadcrumbScope`, `FormatBreadcrumbCrashReport`) to pinpoint exact GPU hangs and TDR faults.

**Milestone 33 Status**: Completed. Physically Based Single-Layer Water Beer-Lambert Absorption, Snell Refraction & Photon Caustics (`GenerateSingleLayerWaterFunctions`, `EvaluateWaterBeerLambertAbsorption`, `ComputeWaterRefractionUVOffset`, `EvaluateWaterCausticsPattern`), Sparse Brick-Atlas Heterogeneous Volumes & Planckian Blackbody Emission (`TCastleVulkanSparseVolumeAtlas`, `GenerateSparseVolumeBlackbodyFunctions`, `EvaluateBlackbodyEmissionRGB`), and GPU Breadcrumb Crash Tracker (`TCastleVulkanBreadcrumbTracker`, `BeginBreadcrumbScope`, `EndBreadcrumbScope`, `FormatBreadcrumbCrashReport`) fully integrated and tested (129 unit tests passing).


### Phase 34: Spatio-Temporal Variance-Guided Filtering (SVGF / À-Trous Wavelet Denoiser) & Specular Hit-Distance Contact Hardening (COMPLETED)

* [x] **34.1. Temporal Luminance Moment Accumulation & Variance Estimation (`GenerateSVGFVarianceMomentsFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate first and second luminance moments ($\mu_1 = L, \mu_2 = L^2$) and estimate spatial-temporal variance $\sigma^2 = \max(0, \mu_2 - \mu_1^2)$ (`EvaluateLuminanceMoments`, `ComputeTemporalVariance`) to guide edge-preserving wavelet denoising for ReSTIR / Lumen / Ray Query signals.
* [x] **34.2. Edge-Stopping À-Trous Wavelet Spatial Filter (`GenerateSVGFAttrousWaveletFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate multi-scale À-Trous wavelet filter weights driven by normal cosine power, plane-aligned depth gradient, and variance-guided luminance edge-stopping functions (`EvaluateSVGFEdgeStoppingWeight`).
* [x] **34.3. Specular Ray Hit-Distance Contact Hardening & Multi-Pass SVGF Denoiser (`TCastleVulkanSVGFDenoiser` in `CastleInternalRHI_Vulkan`)**:
  * Modulate reflection filter radius by ray hit distance (`EvaluateHitDistanceBlurFactor`) and orchestrate multi-pass À-Trous wavelet ping-pong compute dispatches (`EnsureSVGFTargets`, `GetAttrousStepSize`, `DispatchSVGFDenoise`).

**Milestone 34 Status**: Completed. SVGF Temporal Luminance Moments & Variance Estimation (`GenerateSVGFVarianceMomentsFunctions`, `EvaluateLuminanceMoments`, `ComputeTemporalVariance`), Edge-Stopping À-Trous Wavelet Filter & Specular Hit-Distance Contact Hardening (`GenerateSVGFAttrousWaveletFunctions`, `EvaluateSVGFEdgeStoppingWeight`, `EvaluateHitDistanceBlurFactor`), and Multi-Pass SVGF Denoiser Manager (`TCastleVulkanSVGFDenoiser`) fully integrated and tested (132 unit tests passing).


### Phase 35: Hardware Ray Tracing Pipeline (`VK_KHR_ray_tracing_pipeline`), Shader Binding Table (SBT) & Acceleration Structure Compaction (COMPLETED)

* [x] **35.1. Raygen / Closest-Hit / Miss Shader Stage Generation & Payload Packing (`GenerateRayTracingPipelineStages` in `CastleInternalShaderRHI`)**:
  * Generate `GL_EXT_ray_tracing` shader stages (`raygen`, `closesthit`, `miss`) with `traceRayEXT` and barycentric hit normal interpolation (`InterpolateRayHitNormal`).
* [x] **35.2. Shader Binding Table (SBT) Stride Alignment & Region Layout (`TCastleVulkanShaderBindingTable` in `CastleInternalRHI_Vulkan`)**:
  * Align `shaderGroupHandleSize` to `shaderGroupHandleAlignment` and `shaderGroupBaseAlignment` (`AlignUpSBTSize`, `ComputeAlignedSBTRegionSizes`, `EnsureSBTBuffer`, `DispatchTraceRays`) and manage Raygen, Miss, and Hit SBT buffer regions.
* [x] **35.3. BLAS / TLAS Acceleration Structure Builder & Post-Build Compaction (`TCastleVulkanAccelerationStructureManager` in `CastleInternalRHI_Vulkan`)**:
  * Track Bottom-Level and Top-Level Acceleration Structure builds and compact BLAS memory footprints (`RegisterBLASBuild`, `CompactBLAS`, `BuildTLAS`, `CompactionSavedBytes`).

**Milestone 35 Status**: Completed. Hardware Ray Tracing Pipeline Stages (`GenerateRayTracingPipelineStages`, `InterpolateRayHitNormal`), Shader Binding Table Stride & Base Alignment (`TCastleVulkanShaderBindingTable`, `AlignUpSBTSize`, `ComputeAlignedSBTRegionSizes`, `DispatchTraceRays`), and BLAS/TLAS Acceleration Structure Compaction (`TCastleVulkanAccelerationStructureManager`, `RegisterBLASBuild`, `CompactBLAS`, `BuildTLAS`) fully integrated and tested (135 unit tests passing).


### Phase 36: GPU-Driven XPBD Cloth / Hair Strand Physics Simulation, Aerodynamic Wind Field & Signed-Distance Collision (COMPLETED)

* [x] **36.1. Extended Position-Based Dynamics (XPBD) Distance & Bending Constraints (`GenerateXPBDClothComputeShader` in `CastleInternalShaderRHI`)**:
  * Solve compliant XPBD distance constraints ($\Delta \lambda = -(C + \tilde{\alpha} \lambda) / (w_1 + w_2 + \tilde{\alpha})$) in a GPU compute pass (`EvaluateXPBDDistanceConstraintDelta`).
* [x] **36.2. Aerodynamic Drag / Lift Wind Field & Capsule/Sphere SDF Collision (`EvaluateAerodynamicWindForce`, `ResolveSphereCollisionConstraint` in `CastleInternalShaderRHI`)**:
  * Apply turbulent wind lift/drag forces on cloth/foliage/hair triangles and resolve character body sphere/capsule collisions.
* [x] **36.3. GPU XPBD Simulation Manager (`TCastleVulkanXPBDSimulator` in `CastleInternalRHI_Vulkan`)**:
  * Manage ping-pong particle position/previous-position SSBOs and sub-stepped constraint solver dispatches (`DispatchXPBDSubsteps`).

**Milestone 36 Status**: Completed. Compliant XPBD distance constraint solver (`GenerateXPBDClothComputeShader`, `EvaluateXPBDDistanceConstraintDelta`), aerodynamic drag/lift wind forces & sphere SDF collision projection (`EvaluateAerodynamicWindForce`, `ResolveSphereCollisionConstraint`), and sub-stepped GPU XPBD simulation manager (`TCastleVulkanXPBDSimulator`) fully integrated and tested (138 unit tests passing).


### Phase 37: Multi-View Stereo / VR Rendering (`VK_KHR_multiview`), Radial Foveated Rendering & HDR10 ST.2084 (PQ) / Rec.2020 Mastering (COMPLETED)

* [x] **37.1. Single-Pass Stereo `VK_KHR_multiview` (`gl_ViewIndex`) & Asymmetric Eye Projections (`GenerateMultiviewStereoPreamble` in `CastleInternalShaderRHI`)**:
  * Support single-pass stereo instanced rendering across left/right eye views via `GL_EXT_multiview` (`gl_ViewIndex`) and asymmetric tangent-half-FOV frustum matrices (`ComputeAsymmetricEyeProjectionXScaleOffset`).
* [x] **37.2. Gaze-Tracked Radial Foveated Shading Rate (`EvaluateFoveatedShadingRate` in `CastleInternalShaderRHI`, `TCastleVulkanMultiviewStereoManager` in `CastleInternalRHI_Vulkan`)**:
  * Compute eccentricity-based foveal, parafoveal, and peripheral shading rates (`1x1`, `2x2`, `4x4`) around the eye-tracked fixation point and manage 2-layer stereo color/depth array targets (`BeginStereoMultiviewPass`).
* [x] **37.3. Rec.2020 Gamut Conversion & SMPTE ST.2084 (PQ) 10,000-Nit HDR10 Encoding (`GenerateHDR10PQEncodingFunctions` in `CastleInternalShaderRHI`)**:
  * Convert linear Rec.709 scene radiance to Rec.2020 wide color gamut and encode with the SMPTE ST.2084 Perceptual Quantizer (PQ) transfer function (`EvaluateLinearRec709ToRec2020`, `EncodeST2084PQ`).

**Milestone 37 Status**: Completed. Single-pass stereo `VK_KHR_multiview` preamble & OpenXR asymmetric eye frustum projection (`GenerateMultiviewStereoPreamble`, `ComputeAsymmetricEyeProjectionXScaleOffset`), gaze-tracked radial foveated VRS & 2-layer stereo array manager (`EvaluateFoveatedShadingRate`, `TCastleVulkanMultiviewStereoManager`), and ITU-R BT.2020 wide color gamut + SMPTE ST.2084 (PQ) 10,000-nit HDR10 encoding (`GenerateHDR10PQEncodingFunctions`, `EvaluateLinearRec709ToRec2020`, `EncodeST2084PQ`) fully integrated and tested (141 unit tests passing).


### Phase 38: GPU-Driven MegaGeometry / Displaced Subdivision Micro-Meshes, Dual-Quaternion Skinning (DQS) & Per-Instance Custom Data SSBO (COMPLETED)

* [x] **38.1. Dual-Quaternion Skinning (DQS) Volume-Preserving Joint Blending (`GenerateDualQuaternionSkinningFunctions` in `CastleInternalShaderRHI`)**:
  * Perform antipodality-aware dual-quaternion joint blending (`BlendDualQuaternionAntipodal`, `EvaluateDualQuaternionTransform`) to eliminate linear-blend "candy-wrapper" volume collapse under twist rotations.
* [x] **38.2. Displaced Micro-Mesh Barycentric Tessellation & Crack-Free Edge Snapping (`GenerateDisplacedMicroMeshFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate sub-triangle barycentric micro-vertices and scalar heightmap displacement along interpolated normals (`EvaluateMicroMeshDisplacedPosition`, `SnapMicroMeshBarycentricToGrid`).
* [x] **38.3. GPU Per-Instance Custom Float4 Payload Manager (`TCastleVulkanPerInstanceCustomData` in `CastleInternalRHI_Vulkan`)**:
  * Manage a GPU SSBO (`InstanceCustomDataBuffer`) storing arbitrary per-instance `TVector4` custom payloads (wind phase, team tint, dissolve/damage factor) indexed via `gl_InstanceIndex`.

**Milestone 38 Status**: Completed. Antipodality-aware Dual-Quaternion Skinning (`GenerateDualQuaternionSkinningFunctions`, `BlendDualQuaternionAntipodal`, `EvaluateDualQuaternionTransform`), MegaGeometry displaced micro-mesh barycentric tessellation & crack-free edge snapping (`GenerateDisplacedMicroMeshFunctions`, `EvaluateMicroMeshDisplacedPosition`, `SnapMicroMeshBarycentricToGrid`), and GPU per-instance custom float4 payload SSBO manager (`TCastleVulkanPerInstanceCustomData`) fully integrated and tested (144 unit tests passing).


### Phase 39: Neural / ML Cooperative Matrix Denoising & Radiance Caching, Spatio-Temporal Blue-Noise Stipple & Optical Flow Block Matching (COMPLETED)

* [x] **39.1. Optical Flow SAD Block Matching & Sub-Pixel Motion Estimation (`GenerateOpticalFlowBlockMatchingShader` in `CastleInternalShaderRHI`)**:
  * Compute Sum-of-Absolute-Differences (SAD) block matching (`EvaluateOpticalFlowPatchSAD`, `EstimateParabolicSubpixelOffset`) to estimate screen-space motion vectors for disoccluded or animated textures.
* [x] **39.2. Golden-Ratio Spatio-Temporal Blue-Noise Dither & R2 Sequence (`GenerateSpatioTemporalBlueNoiseFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate Roberts' 2D quasi-random $R_2$ low-discrepancy sequence and golden-ratio temporal rotation (`EvaluateR2Sequence2D`, `EvaluateTemporalBlueNoiseJitter`) for stochastic transparency, soft shadows, and ray jitter.
* [x] **39.3. Cooperative Matrix MLP Inference Manager (`TCastleVulkanNeuralDenoiser` in `CastleInternalRHI_Vulkan`)**:
  * Manage MLP network weight buffers (`MLPWeightsBuffer`), ReLU evaluation (`EvaluateLinearReLU4`), and compute inference dispatches (`DispatchNeuralInference`) for neural radiance caching and ray-reconstruction denoising.

**Milestone 39 Status**: Completed. Optical flow SAD block matching & parabolic sub-pixel motion estimation (`GenerateOpticalFlowBlockMatchingShader`, `EvaluateOpticalFlowPatchSAD`, `EstimateParabolicSubpixelOffset`), Martin Roberts 2D $R_2$ low-discrepancy sequence & golden-ratio spatio-temporal blue-noise rotation (`GenerateSpatioTemporalBlueNoiseFunctions`, `EvaluateR2Sequence2D`, `EvaluateTemporalBlueNoiseJitter`), and GPU MLP neural denoiser manager (`TCastleVulkanNeuralDenoiser`) fully integrated and tested (147 unit tests passing).


### Phase 40: Shader Execution Reordering (SER) Coherence Hints, Dual-Source Colored Glass Transmission & Programmable MSAA Sample Positions (COMPLETED)

* [x] **40.1. Shader Execution Reordering (SER) Coherence Hint Packing (`GenerateSERCoherenceHintFunctions` in `CastleInternalShaderRHI`)**:
  * Pack ray hit/miss status, material shading ID, and quantized directional octants into a compact coherence hint key (`PackSERCoherenceHintKey`) to sort divergent ray-tracing threads (`GL_NV_shader_invocation_reorder`).
* [x] **40.2. Dual-Source Color Blending for Colored Glass Transmission (`GenerateDualSourceGlassTransmissionFunctions` in `CastleInternalShaderRHI`)**:
  * Compute dual-source blending outputs (`location = 0, index = 0` specular reflection + `location = 0, index = 1` spectral colored glass transmittance) for single-pass physically based stained/tinted glass (`EvaluateDualSourceGlassOutputs`).
* [x] **40.3. Programmable MSAA Sample Locations Manager (`TCastleVulkanProgrammableSampleLocations` in `CastleInternalRHI_Vulkan`)**:
  * Manage custom sub-pixel MSAA sample patterns (`VK_EXT_sample_locations`, rotated-grid & Halton 2x/4x/8x sub-pixel offsets) for superior sub-pixel edge anti-aliasing.

**Milestone 40 Status**: Completed. Shader Execution Reordering (SER) 8-bit coherence hint key packing (`GenerateSERCoherenceHintFunctions`, `PackSERCoherenceHintKey`), Dual-Source Color Blending (`location = 0, index = 0/1`) colored glass transmission (`GenerateDualSourceGlassTransmissionFunctions`, `EvaluateDualSourceGlassOutputs`), and Programmable MSAA Rotated-Grid Supersampling (RGSS) sample locations manager (`TCastleVulkanProgrammableSampleLocations`) fully integrated and tested (150 unit tests passing).


### Phase 41: Vulkan 1.4 Dynamic Rendering Local Read (Tile-Local Subpass Merging), Subgroup Wave Reduction Intrinsics & GPU Prefix-Sum Stream Compaction (COMPLETED)

* [x] **41.1. Vulkan 1.4 Dynamic Rendering Local Read (`VK_KHR_dynamic_rendering_local_read`) Tile-Local G-Buffer Lighting (`GenerateDynamicRenderingLocalReadPreamble` in `CastleInternalShaderRHI`)**:
  * Generate `subpassInput` tile-local attachment inputs (`castle_TileGBufferAlbedo`, `castle_TileGBufferNormalRoughness`) and on-chip tile-local deferred lighting (`EvaluateTileLocalDeferredLighting`) to eliminate external VRAM round-trips during deferred shading.
* [x] **41.2. Subgroup Wave Intrinsics (`GL_KHR_shader_subgroup_ballot` / `arithmetic`) Reduction & Prefix Scans (`GenerateSubgroupWaveIntrinsicsFunctions` in `CastleInternalShaderRHI`)**:
  * Provide lock-free wave-level ballot bit-counting (`EvaluateSubgroupBallotBitCount`) and exclusive prefix-sum scans (`EvaluateSubgroupExclusivePrefixSum4`).
* [x] **41.3. GPU Parallel Prefix-Sum (Blelloch Scan) & Predicate Stream Compactor (`TCastleVulkanStreamCompactor` in `CastleInternalRHI_Vulkan`)**:
  * Manage exclusive prefix-sum and predicate stream compaction buffers (`PrefixSumBuffer`, `CompactedIndicesBuffer`, `CompactedCountBuffer`, `EvaluatePrefixSumAndCompact`, `DispatchStreamCompaction`) for compacting surviving visible instances, meshlets, or ray payloads.

**Milestone 41 Status**: Completed. Vulkan 1.4 Dynamic Rendering Local Read (`VK_KHR_dynamic_rendering_local_read`) `subpassInput` preamble & tile-local G-Buffer deferred lighting (`GenerateDynamicRenderingLocalReadPreamble`, `EvaluateTileLocalDeferredLighting`), Subgroup wave ballot & exclusive prefix-sum intrinsics (`GenerateSubgroupWaveIntrinsicsFunctions`, `EvaluateSubgroupBallotBitCount`, `EvaluateSubgroupExclusivePrefixSum4`), and GPU parallel prefix-sum & predicate stream compactor (`TCastleVulkanStreamCompactor`) fully integrated and tested (153 unit tests passing).


### Phase 42: Bindless Buffer Device Address (`VK_KHR_buffer_device_address`) Pointer Chasing, Conservative Rasterization Voxelization & 3D Voxel Cone Tracing (VXGI) (COMPLETED)

* [x] **42.1. Buffer Device Address (`GL_EXT_buffer_reference2`) 64-Bit GPU Pointer Arithmetic (`GenerateBufferDeviceAddressPreamble` in `CastleInternalShaderRHI`)**:
  * Generate `layout(buffer_reference, scalar, buffer_reference_align = 16)` 64-bit GPU pointer declarations and aligned address offset helpers (`AlignBufferDeviceAddress`).
* [x] **42.2. Conservative Rasterization Dominant-Axis Voxelization & 3D Voxel Cone Tracing (`GenerateVoxelConeTracingFunctions` in `CastleInternalShaderRHI`)**:
  * Project triangle geometry along its dominant normal axis (`SelectDominantVoxelProjectionAxis`) and trace aperture-growing 3D mipmapped voxel cones (`EvaluateVoxelConeStepAperture`).
* [x] **42.3. 3D Voxel Radiance Clipmap Manager (`TCastleVulkanVoxelConeTracer` in `CastleInternalRHI_Vulkan`)**:
  * Manage 3D voxel opacity/radiance clipmap textures and voxelization/cone-tracing dispatches (`VoxelRadianceTexture`, `IndirectIrradianceTexture`, `AccumulateVoxelConeSample`, `DispatchVoxelConeTrace`).

**Milestone 42 Status**: Completed. Bindless 64-bit Buffer Device Address (`GL_EXT_buffer_reference2` / `VK_KHR_buffer_device_address`) preamble & address alignment (`GenerateBufferDeviceAddressPreamble`, `AlignBufferDeviceAddress`), dominant-axis conservative voxelization & 3D mipmapped voxel cone aperture evaluation (`GenerateVoxelConeTracingFunctions`, `SelectDominantVoxelProjectionAxis`, `EvaluateVoxelConeStepAperture`), and 3D Voxel Cone Tracer manager (`TCastleVulkanVoxelConeTracer`) fully integrated and tested (156 unit tests passing).


### Phase 43: GPU-Driven Indirect Material Batching / Shader Execution Binning, Specular AA (Toksvig / Kaplanyan Normal Variance) & Rectilinear Shadow Warping (COMPLETED)

* [x] **43.1. Normal-Variance Specular Anti-Aliasing (`GenerateSpecularNormalVarianceAAFunctions` in `CastleInternalShaderRHI`)**:
  * Filter sub-pixel normal map variance (Toksvig / Kaplanyan & Antonov roughness kernel filtering `EvaluateSpecularAARoughness`) to eliminate distant specular shimmering.
* [x] **43.2. Rectilinear / Perspective Shadow Map Warping (`GenerateRectilinearShadowWarpFunctions` in `CastleInternalShaderRHI`)**:
  * Warp shadow UV coordinates (`EvaluateRectilinearShadowWarpUV`) to concentrate texel density near the camera focus region.
* [x] **43.3. GPU Indirect Material Binning Manager (`TCastleVulkanMaterialBinner` in `CastleInternalRHI_Vulkan`)**:
  * Bin visibility-buffer or ray-hit fragments by material ID into contiguous indirect dispatch ranges (`BinCountsBuffer`, `BinOffsetsBuffer`, `EvaluateMaterialBinRanges`, `DispatchMaterialBinning`).

**Milestone 43 Status**: Completed. Normal-variance specular anti-aliasing (`GenerateSpecularNormalVarianceAAFunctions`, `EvaluateSpecularAARoughness`), rectilinear shadow map UV warping (`GenerateRectilinearShadowWarpFunctions`, `EvaluateRectilinearShadowWarpUV`), and GPU indirect material binning manager (`TCastleVulkanMaterialBinner`) fully integrated and tested (159 unit tests passing).


### Phase 44: GPU-Driven Procedural Foliage / Grass Blade Instancing, Multi-Channel Signed Distance Field (MSDF) Text & Per-Pixel Linked List (PPLL) Exact OIT (COMPLETED)

* [x] **44.1. Multi-Channel Signed Distance Field (MSDF) Median-of-Three Crisp Vector / Text Evaluation (`GenerateMSDFTextFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate Chlumsky's median-of-three RGB signed distance field (`EvaluateMSDFMedianOfThree`, `EvaluateMSDFScreenPxOpacity`) for sharp corner-preserving vector shapes and 3D text at any magnification.
* [x] **44.2. Procedural Quadratic Bezier Grass Blade Bending & Wind Flutter (`GenerateProceduralGrassBladeFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate quadratic Bezier grass blade curves and normal derivatives (`EvaluateQuadraticBezierGrassBlade`) for GPU-instanced meadows.
* [x] **44.3. Exact Order-Independent Transparency Per-Pixel Linked List Manager (`TCastleVulkanPerPixelLinkedListOIT` in `CastleInternalRHI_Vulkan`)**:
  * Manage per-pixel head-pointer image (`HeadPointerTexture`) and atomic node pool SSBO (`FragmentNodeBuffer`) with insertion-sort resolve for exact order-independent transparency.

**Milestone 44 Status**: Completed. Multi-channel signed distance field (MSDF) median-of-three vector/text evaluation (`GenerateMSDFTextFunctions`, `EvaluateMSDFMedianOfThree`, `EvaluateMSDFScreenPxOpacity`), procedural quadratic Bezier grass blade curves & tangents (`GenerateProceduralGrassBladeFunctions`, `EvaluateQuadraticBezierGrassBlade`), and exact Per-Pixel Linked List (PPLL) order-independent transparency manager (`TCastleVulkanPerPixelLinkedListOIT`) fully integrated and tested (162 unit tests passing).


### Phase 45: Vulkan 1.4 Push Descriptors (`VK_KHR_push_descriptor`), Host Image Copy (`VK_EXT_host_image_copy`) Zero-Staging Streaming & Pipeline Robustness (COMPLETED)

* [x] **45.1. Vulkan 1.4 Push Descriptors & Host Image Copy Layout Transition Helpers (`GeneratePushDescriptorPreamble` in `CastleInternalShaderRHI`)**:
  * Generate push-descriptor layout bindings and compute tight host-to-image memory copy strides (`ComputeHostImageCopyByteSize`).
* [x] **45.2. Spherical Gaussian (SG) Fast Specular & Diffuse Lobe Approximation (`GenerateSphericalGaussianFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate Spherical Gaussian inner products and warp products (`EvaluateSphericalGaussianProduct`, `EvaluateSphericalGaussianIntegral`) for real-time anisotropic probe lighting.
* [x] **45.3. Vulkan 1.4 Host Image Copy & Push Descriptor Manager (`TCastleVulkanHostImageCopyManager` in `CastleInternalRHI_Vulkan`)**:
  * Manage zero-staging direct CPU-to-GPU image uploads (`vkCopyMemoryToImageEXT`) and command-buffer push descriptor updates (`vkCmdPushDescriptorSetKHR`).

**Milestone 45 Status**: Completed. Vulkan 1.4 Push Descriptor GLSL preamble & Host Image Copy byte stride calculation (`GeneratePushDescriptorPreamble`, `ComputeHostImageCopyByteSize`), Spherical Gaussian (SG) lobe product & spherical integral evaluation (`GenerateSphericalGaussianFunctions`, `EvaluateSphericalGaussianProduct`, `EvaluateSphericalGaussianIntegral`), and Vulkan 1.4 Host Image Copy & Push Descriptor manager (`TCastleVulkanHostImageCopyManager`) fully integrated and tested (165 unit tests passing).


### Phase 46: 3D Gaussian Splatting (3DGS) Ellipsoid Covariance Projection, Spherical Harmonics (SH) View-Dependent Radiance & GPU Tile Splat Renderer (COMPLETED)

* [x] **46.1. 3D Gaussian Splatting (3DGS) 2D Covariance Conic & Mahalanobis Opacity Falloff (`GenerateGaussianSplattingFunctions` in `CastleInternalShaderRHI`)**:
  * Invert 2D projected symmetric covariance matrices with low-pass anti-aliasing dilation (+0.3) into conic coefficients and evaluate Gaussian splat opacity (`EvaluateGaussianSplatOpacity`).
* [x] **46.2. Degree-1 (L0 + L1) View-Dependent Spherical Harmonics Radiance (`EvaluateSphericalHarmonicsL1RGB` in `CastleInternalShaderRHI`)**:
  * Evaluate 4-band view-dependent Spherical Harmonics RGB color for neural/photogrammetry 3D Gaussian Splats.
* [x] **46.3. 3D Gaussian Splatting GPU Tile Sorter & Compositor (`TCastleVulkanGaussianSplatRenderer` in `CastleInternalRHI_Vulkan`)**:
  * Manage 3D Gaussian splat payload and radix key SSBOs (`SplatBuffer`, `SortedKeysBuffer`), front-to-back Beer-Lambert transmittance compositing with early-ray termination (`SortAndCompositeSplatsFrontToBack`), and tile rasterization dispatches (`DispatchGaussianSplatRender`).

**Milestone 46 Status**: Completed. 3D Gaussian Splatting (3DGS) 2D conic covariance inversion & Mahalanobis opacity falloff (`GenerateGaussianSplattingFunctions`, `EvaluateGaussianSplatOpacity`), L1 view-dependent Spherical Harmonics RGB evaluation (`EvaluateSphericalHarmonicsL1RGB`), and 3D Gaussian Splatting GPU tile renderer (`TCastleVulkanGaussianSplatRenderer`) fully integrated and tested (168 unit tests passing).


### Phase 47: Vulkan Descriptor Buffers (`VK_EXT_descriptor_buffer`), PCSS Contact-Hardening Soft Shadows & GPU Indirect Command Signature Alignment (COMPLETED)

* [x] **47.1. Percentage-Closer Soft Shadows (PCSS) Blocker Search & Penumbra Estimation (`GeneratePCSSSoftShadowFunctions` in `CastleInternalShaderRHI`)**:
  * Compute physical contact-hardening penumbra filter radii from receiver depth, average blocker depth, and area light size (`EvaluatePCSSPenumbraWidth`).
* [x] **47.2. Vulkan Descriptor Buffer (`VK_EXT_descriptor_buffer`) Offset Alignment (`ComputeDescriptorBufferAlignedOffset` in `CastleInternalShaderRHI`)**:
  * Compute hardware-aligned byte offsets into GPU-resident resource and sampler descriptor buffers.
* [x] **47.3. Vulkan Descriptor Buffer Manager (`TCastleVulkanDescriptorBufferManager` in `CastleInternalRHI_Vulkan`)**:
  * Manage GPU-resident resource and sampler descriptor buffers (`ResourceDescriptorBuffer`, `SamplerDescriptorBuffer`) and `vkCmdSetDescriptorBufferOffsetsEXT` bindings.

**Milestone 47 Status**: Completed. Percentage-Closer Soft Shadows (PCSS) contact-hardening penumbra evaluation (`GeneratePCSSSoftShadowFunctions`, `EvaluatePCSSPenumbraWidth`), `VK_EXT_descriptor_buffer` aligned offset calculation (`ComputeDescriptorBufferAlignedOffset`), and Vulkan Descriptor Buffer manager (`TCastleVulkanDescriptorBufferManager`) fully integrated and tested (171 unit tests passing).


### Phase 48: Multi-Layer Metallic Flake Car-Paint BRDF, Screen-Space Curvature Cavity Shading & GPU Hi-Z Conservative Depth Pyramid Generator (COMPLETED)

* [x] **48.1. Multi-Layer Metallic Flake & Clear-Coat Car-Paint BRDF (`GenerateCarPaintFlakeFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate view-dependent two-tone base coat, stochastic metallic sparkle flakes, and dielectric clear coat (`EvaluateCarPaintMultiLayerBRDF`).
* [x] **48.2. Screen-Space Normal Curvature & Ridge/Valley Cavity Occlusion (`GenerateScreenSpaceCurvatureFunctions` in `CastleInternalShaderRHI`)**:
  * Compute screen-space surface curvature from normal derivatives (`EvaluateScreenSpaceCurvatureCavity`) for procedural edge wear and crease darkening.
* [x] **48.3. GPU Hierarchical-Z (Hi-Z) Conservative Min/Max Depth Pyramid Generator (`TCastleVulkanHiZPyramidGenerator` in `CastleInternalRHI_Vulkan`)**:
  * Manage conservative $2 \times 2$ min/max depth reduction across mip levels (`EvaluateConservativeDepthDownsample2x2`, `DispatchHiZPyramidBuild`).

**Milestone 48 Status**: Completed. Multi-Layer Metallic Flake & Clear-Coat Car-Paint BRDF (`GenerateCarPaintFlakeFunctions`, `EvaluateCarPaintMultiLayerBRDF`), Screen-Space Normal Curvature & Ridge/Valley Cavity Occlusion (`GenerateScreenSpaceCurvatureFunctions`, `EvaluateScreenSpaceCurvatureCavity`), and GPU Hierarchical-Z (Hi-Z) Conservative Min/Max Depth Pyramid Generator (`TCastleVulkanHiZPyramidGenerator`) fully integrated and tested (174 unit tests passing).


### Phase 49: AgX Filmic Gamut Compression, Physically Based Camera Exposure ($\text{EV}_{100}$) & GPU Luminance Histogram Auto-Exposure Manager (COMPLETED)

* [x] **49.1. Physically Based Camera Exposure ($\text{EV}_{100}$) from Aperture, Shutter Speed & ISO (`GenerateCameraEV100ExposureFunctions` in `CastleInternalShaderRHI`)**:
  * Compute photographic $\text{EV}_{100}$ and ISO 12232 saturation-based linear exposure multipliers (`EvaluateEV100FromCameraSettings`, `EvaluateExposureMultiplierFromEV100`).
* [x] **49.2. AgX Filmic Log Encoding & Highlight Chroma Gamut Compression (`GenerateAgXGamutCompressionFunctions` in `CastleInternalShaderRHI`)**:
  * Compress out-of-gamut high-intensity saturated colors toward achromatic white (`EvaluateChromaGamutCompression`) to eliminate clipping artifacts.
* [x] **49.3. GPU 64-Bin Luminance Histogram Auto-Exposure Manager (`TCastleVulkanAutoExposureHistogram` in `CastleInternalRHI_Vulkan`)**:
  * Manage 64-bin log-luminance histogram SSBOs (`HistogramBuffer`), outlier-trimmed average luminance calculation (`EvaluateTrimmedHistogramAverageEV`), and temporal eye adaptation (`DispatchHistogramAutoExposure`).

**Milestone 49 Status**: Completed. Physically Based Camera Exposure ($\text{EV}_{100}$) & ISO 12232 linear exposure multiplier (`GenerateCameraEV100ExposureFunctions`, `EvaluateEV100FromCameraSettings`, `EvaluateExposureMultiplierFromEV100`), AgX Highlight Chroma Gamut Compression (`GenerateAgXGamutCompressionFunctions`, `EvaluateChromaGamutCompression`), and GPU 64-Bin Luminance Histogram Auto-Exposure Manager (`TCastleVulkanAutoExposureHistogram`) fully integrated and tested (177 unit tests passing).


### Phase 50: Analytical Capsule Soft Shadow & Ambient Occlusion, Epipolar Volumetric Light Shafts & GPU Frame Pacing Manager (COMPLETED)

* [x] **50.1. Analytical Capsule Soft Shadow & Ambient Occlusion (`GenerateCapsuleOcclusionFunctions` in `CastleInternalShaderRHI`)**:
  * Compute analytical cone-capsule intersection occlusion (`EvaluateCapsuleSoftShadowOcclusion`) for articulated character shadows and ambient occlusion.
* [x] **50.2. Epipolar Volumetric Light Shafts (Crepuscular God Rays) Slice Stepping (`GenerateEpipolarLightShaftFunctions` in `CastleInternalShaderRHI`)**:
  * Transform screen-space rays into epipolar slice coordinates (`EvaluateEpipolarSliceRayStep`) for high-speed volumetric god-ray marching.
* [x] **50.3. GPU Frame Pacing & Present Timing Manager (`TCastleVulkanFramePacer` in `CastleInternalRHI_Vulkan`)**:
  * Track rolling frame-time variance, compute target refresh-rate sleep deadlines (`EvaluateFramePacingWaitMicroseconds`), and manage present timing telemetry.

**Milestone 50 Status**: Completed. Analytical Capsule Soft Shadow & Ambient Occlusion (`GenerateCapsuleOcclusionFunctions`, `EvaluateCapsuleSoftShadowOcclusion`), Epipolar Volumetric Light Shafts Slice Stepping (`GenerateEpipolarLightShaftFunctions`, `EvaluateEpipolarSliceRayStep`), and GPU Frame Pacing & Present Timing Manager (`TCastleVulkanFramePacer`) fully integrated and tested (180 unit tests passing).


### Phase 51: Cooperative Matrix / Tensor Core Intrinsics (`VK_KHR_cooperative_matrix`), Anisotropic Kuwahara Structure-Tensor Filter & GPU Indirect Compute Dispatcher (COMPLETED)

* [x] **51.1. Cooperative Matrix / Hardware Tensor Core Intrinsics & E4M3 FP8 Decoding (`GenerateCooperativeMatrixPreamble` in `CastleInternalShaderRHI`)**:
  * Emit `#extension GL_KHR_cooperative_matrix : enable` and `#extension GL_KHR_memory_scope_semantics : enable` declarations with E4M3 FP8-to-IEEE-754 decoding (`EvaluateQuantizedFP8ToFloat`) for hardware-accelerated neural shading and denoising.
* [x] **51.2. Anisotropic Kuwahara Structure-Tensor Eigenvalue & Orientation Filter (`GenerateAnisotropicKuwaharaFunctions` in `CastleInternalShaderRHI`)**:
  * Compute principal orientation angle and normalized eigenvalue anisotropy (`EvaluateStructureTensorEigenOrientation`) from local structure tensors $(J_{xx}, J_{yy}, J_{xy})$ for edge-preserving stylized filtering and denoising.
* [x] **51.3. GPU-Driven Indirect Compute Workgroup Dispatcher (`TCastleVulkanIndirectComputeDispatcher` in `CastleInternalRHI_Vulkan`)**:
  * Manage indirect compute dispatch argument buffers (`VkDispatchIndirectCommand`), compute workgroup counts from active item counts (`ComputeWorkgroupCountsFromItemCount`), and record `vkCmdDispatchIndirect` commands (`RecordIndirectComputeDispatch`).

**Milestone 51 Status**: Completed. Cooperative Matrix / Tensor Core Intrinsics & E4M3 FP8 Decoding (`GenerateCooperativeMatrixPreamble`, `EvaluateQuantizedFP8ToFloat`), Anisotropic Kuwahara Structure-Tensor Eigen-Orientation (`GenerateAnisotropicKuwaharaFunctions`, `EvaluateStructureTensorEigenOrientation`), and GPU-Driven Indirect Compute Dispatcher (`TCastleVulkanIndirectComputeDispatcher`) fully integrated and tested (183 unit tests passing).


### Phase 52: Physically Based Eye Cornea Refraction & Iris Parallax, Six-Point Directional Lightmap Basis & Real-Time GPU BC1/BC6H Block Compressor (COMPLETED)

* [x] **52.1. Physically Based Eye Cornea Snell Refraction & Anterior Chamber Iris Parallax (`GeneratePhysicalEyeRefractionFunctions` in `CastleInternalShaderRHI`)**:
  * Compute Snell refraction at the cornea surface and anterior chamber depth parallax UV offset onto the iris plane (`EvaluateEyeIrisRefractionUVOffset`).
* [x] **52.2. Six-Point Directional Lightmap Basis for Volumetric Smoke & Clouds (`GenerateSixPointLightmapFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate 6-axis tangent-space directional lightmap weights $(+X, -X, +Y, -Y, +Z, -Z)$ (`EvaluateSixPointDirectionalBasis`) for multi-directional volumetric particle and cloud lighting.
* [x] **52.3. Real-Time GPU BC1/BC6H Block Texture Compressor (`TCastleVulkanBCnCompressor` in `CastleInternalRHI_Vulkan`)**:
  * Quantize RGB565 endpoints (`EvaluateBC1EndpointQuantization565`) and dispatch GPU compute 4x4 block compression (`DispatchBCnBlockCompression`) for runtime virtual textures and reflection probes.

**Milestone 52 Status**: Completed. Physically Based Eye Cornea Snell Refraction & Iris Parallax (`GeneratePhysicalEyeRefractionFunctions`, `EvaluateEyeIrisRefractionUVOffset`), Six-Point Directional Lightmap Basis (`GenerateSixPointLightmapFunctions`, `EvaluateSixPointDirectionalBasis`), and Real-Time GPU BC1/BC6H Block Compressor (`TCastleVulkanBCnCompressor`) fully integrated and tested (186 unit tests passing).


### Phase 53: Secant-Refined Parallax Occlusion Mapping (POM), Spectral Cauchy Chromatic Dispersion & Vulkan 1.4 Pipeline Binary Manager (`VK_KHR_pipeline_binary`) (COMPLETED)

* [x] **53.1. Secant-Refined Parallax Occlusion Mapping (POM) Intersection (`GenerateParallaxOcclusionMappingFunctions` in `CastleInternalShaderRHI`)**:
  * Refine linear heightfield ray-marching steps with exact secant root interpolation (`EvaluateSecantRefinedPOMIntersection`) for artifact-free micro-surface displacement.
* [x] **53.2. Physically Based Spectral Cauchy Chromatic Dispersion (`GenerateChromaticDispersionFlareFunctions` in `CastleInternalShaderRHI`)**:
  * Evaluate wavelength-dependent Cauchy refractive indices $n(\lambda) = A + B/\lambda^2$ across Red (0.65 $\mu\text{m}$), Green (0.55 $\mu\text{m}$), and Blue (0.45 $\mu\text{m}$) spectral bands (`EvaluateCauchyRefractiveIndexRGB`).
* [x] **53.3. Vulkan 1.4 Pipeline Binary Manager (`VK_KHR_pipeline_binary` / `TCastleVulkanPipelineBinaryManager` in `CastleInternalRHI_Vulkan`)**:
  * Manage standalone driver pipeline binaries indexed by 64-bit FNV-1a keys (`ComputePipelineKeyFNV1a64`, `StorePipelineBinary`, `LookupPipelineBinary`) for lock-free zero-compilation PSO restoration.

**Milestone 53 Status**: Completed. Secant-Refined Parallax Occlusion Mapping (`GenerateParallaxOcclusionMappingFunctions`, `EvaluateSecantRefinedPOMIntersection`), Spectral Cauchy Chromatic Dispersion (`GenerateChromaticDispersionFlareFunctions`, `EvaluateCauchyRefractiveIndexRGB`), and Vulkan 1.4 Pipeline Binary Manager (`TCastleVulkanPipelineBinaryManager`) fully integrated and tested (189 unit tests passing).


### Phase 54: High-Level `TCastleRenderOptions` & `TCastleViewport` Next-Gen Vulkan RHI Wiring (COMPLETED)

* [x] **54.1. High-Level Next-Gen Rendering Enums (`CastleRenderOptions`)**:
  * Define `TGlobalIlluminationMode` (`giNone`, `giDDGIProbes`, `giVoxelConeTracing`, `giLumenSDFAndSurfaceCache`, `giReSTIRGI`), `TTemporalAntiAliasingMode` (`taaNone`, `taaStandardTAA`, `taaTSRUpscaler`), `TTransparencyMode` (`tmAlphaBlending`, `tmWeightedBlendedOIT`, `tmPerPixelLinkedListOIT`), `TVariableRateShadingMode` (`vrsNone`, `vrsContrastAdaptive`, `vrsFoveatedStereo`), `TShadowMapSystemMode` (`smsStandardShadowMaps`, `smsPCSSContactHardening`, `smsVirtualShadowMaps`), and `TNextGenToneMappingMode` (`ntmStandard`, `ntmAgXGamutCompressed`, `ntmHDR10Rec2020PQ`).
* [x] **54.2. Per-Scene Next-Gen Material & Geometry Options on `TCastleRenderOptions` (`CastleRenderOptions`)**:
  * Expose published properties `SpecularAntiAliasing`, `DualQuaternionSkinning`, `GpuDrivenMeshletCulling`, `TransparencyMode`, and `ShadowMapSystemMode` with full `Assign`, `UpdateHash` dynamic-batching hash integration, and CGE Editor `PropertySections` support.
* [x] **54.3. High-Level `TCastleViewport` Subsystem Orchestration & Physical Camera Exposure (`CastleViewport`)**:
  * Expose published properties `GlobalIlluminationMode`, `TemporalAntiAliasingMode`, `VariableRateShadingMode`, `NextGenToneMappingMode`, `VolumetricFogEnabled`, `AutoExposureEnabled`, `CameraApertureFStops`, `CameraShutterSeconds`, `CameraISO`, and `TargetFrameRateHz`, plus `EvaluateCurrentCameraEV100`, `EvaluateCurrentCameraExposureMultiplier`, and `ExecuteVulkanViewportSubsystems` hooked into `TCastleViewport.RenderFromViewEverything`.

**Milestone 54 Status**: Completed. High-level next-gen rendering enums, per-scene `TCastleRenderOptions` properties (`SpecularAntiAliasing`, `DualQuaternionSkinning`, `GpuDrivenMeshletCulling`, `TransparencyMode`, `ShadowMapSystemMode`), and `TCastleViewport` subsystem orchestration (`ExecuteVulkanViewportSubsystems`, `EvaluateCurrentCameraEV100`, `EvaluateCurrentCameraExposureMultiplier`) fully integrated and tested (192 unit tests passing).


### Phase 55: Native Window Surface (`VkSurfaceKHR`) Creation Across All OS Backends (COMPLETED)
**Goal**: Wire automatic `VkSurfaceKHR` creation in `TCastleWindow` across Win32 (`vkCreateWin32SurfaceKHR`), Linux X11/Wayland (`vkCreateXlibSurfaceKHR` / `vkCreateWaylandSurfaceKHR`), Android (`vkCreateAndroidSurfaceKHR`), macOS/iOS MoltenVK (`vkCreateMetalSurfaceEXT`), and Nintendo Switch (`vkCreateViSurfaceNN`) when `ApplicationProperties.RenderBackend = backendVulkan`.

* [x] **55.1. Cross-Platform Native Surface Descriptor & Extension Resolution (`CastleInternalVulkanWSI`)**:
  * Implement `TVulkanWSIPlatform` (`vwsiAuto`, `vwsiWin32`, `vwsiXlib`, `vwsiWayland`, `vwsiAndroid`, `vwsiMetal`, `vwsiViSwitch`, `vwsiHeadless`), `TVulkanNativeSurfaceDesc` with static constructors (`CreateWin32`, `CreateXlib`, `CreateWayland`, `CreateAndroid`, `CreateMetal`, `CreateViSwitch`), `GetDefaultVulkanWSIPlatform`, `GetRequiredVulkanInstanceExtensionsForPlatform`, `ValidateVulkanNativeSurfaceDesc`, and `CreateVulkanSurfaceFromNativeDesc` dispatching across all 6 OS WSI surface creation extensions.
* [x] **55.2. Automatic `TCastleWindow` Native Handle Extraction & `VkSurfaceKHR` Creation (`CastleWindow`)**:
  * Implement `TCastleWindow.BuildVulkanNativeSurfaceDesc` extracting native handles from `CASTLE_WINDOW_WINAPI` (`System.HInstance`, `h_Wnd`), `CASTLE_WINDOW_XLIB` (`Application.XDisplay`, `WindowXID`), `CASTLE_WINDOW_GTK_ANY` (Wayland `wl_display`/`wl_surface` and X11 `Application.XDisplay`/`RenderingAreaXID`), `CASTLE_WINDOW_ANDROID` (`NativeWindow`), and `CASTLE_WINDOW_COCOA` (`Ref.contentView.layer`), plus `SetCustomVulkanSurfaceDesc` / `ClearCustomVulkanSurfaceDesc` / `OnCreateVulkanSurface` for custom embedders (`CASTLE_WINDOW_LIBRARY` / `CASTLE_WINDOW_FORM`).
* [x] **55.3. `TCastleWindow` Vulkan Lifecycle Wiring (`OpenCore`, `DoResize`, `Close`)**:
  * Wire `InitializeVulkanRHIDeviceIfNeeded` in `TCastleWindow.OpenCore` when `IsVulkanBackendRequested` (`ApplicationProperties.RenderBackend = backendVulkan`), automatic swapchain resizing (`RHIDevice.ResizeSwapchain`) in `TCastleWindow.DoResize`, and owned `TVulkanRHIDevice` cleanup in `TCastleWindow.Close`.

**Milestone 55 Status**: Completed. Cross-platform `TVulkanNativeSurfaceDesc`, `CreateVulkanSurfaceFromNativeDesc`, and automatic `TCastleWindow` `VkSurfaceKHR` creation and lifecycle wiring across Win32, Linux X11/Wayland, Android, macOS/iOS MoltenVK, and Nintendo Switch fully integrated and tested (195 unit tests passing).


### Phase 56: Live Example & Full Engine Test Suite Verification (COMPLETED)
**Goal**: Verify 100% pass rate across the entire Castle Game Engine test suite (`castle_tester_standalone`, 764 tests) and verify live CGE example execution (`examples/vulkan/vulkan_3d_scene`) with `render_backend="vulkan"`.

* [x] **56.1. CWD-Independent Manifest & Asset Resolution in `TTestCastleVulkanRHI`**:
  * Ensure `TestNintendoSwitchViSurfaceAndManifestPrewarm` resolves `examples/vulkan/vulkan_3d_scene/CastleEngineManifest.xml` when `castle_tester_standalone` is executed either from the repository root or from `tests/` (where `castle-data:/` resolves to `tests/data/`).
* [x] **56.2. Complete 764-Test Engine Suite Verification (`castle_tester_standalone`)**:
  * Verified all 764 tests in `castle_tester_standalone` pass with zero failures (`195/195` `TTestCastleVulkanRHI` tests + all core CGE tests).
* [x] **56.3. Live Next-Gen Vulkan Example Verification (`examples/vulkan/vulkan_3d_scene`)**:
  * Enhanced and verified `examples/vulkan/vulkan_3d_scene/vulkan_3d_scene.dpr` (`render_backend="vulkan"`) exercising SPIR-V core shader pre-warming, Scene & Multi-Light UBOs, depth-only shadow pass setup, GPU skinning UBOs, high-level `TCastleRenderOptions` & `TCastleViewport.ExecuteVulkanViewportSubsystems` orchestration, and `TCastleWindow` WSI surface descriptor & extension resolution.

**Milestone 56 Status**: Completed. Full 764-test `castle_tester_standalone` suite and live `examples/vulkan/vulkan_3d_scene` example verified with 0 failures.


### Phase 57: Complete Vulkan Examples (`vulkan_triangle`, `vulkan_sprite_batch`, `vulkan_3d_scene`), Live Vulkan 1.4 Driver Hardening & Documentation Completion (COMPLETED)
**Goal**: Upgrade all three Vulkan examples (`vulkan_triangle`, `vulkan_sprite_batch`, `vulkan_3d_scene`) to exercise real `TVulkanRHIDevice`, `TRHIPipeline`, `TCastleBatch2DRenderer`, and interactive `TCastleWindow` GUI / `--headless` execution; harden live Vulkan 1.4 `vkGetDeviceProcAddr` loading and first-run disk cache directory creation; and update `doc/vulkan_renderer.md`.

* [x] **57.1. Live Vulkan 1.4 Driver Hardening & First-Run Cache Directory Creation (`CastleInternalVulkan`, `CastleInternalRHI_Vulkan`, `CastleInternalShaderCompiler`)**:
  * Resolve device-level Vulkan commands via `vkGetDeviceProcAddr(Device, ...)` with fallback to `vkGetInstanceProcAddr(LoadedVulkanInstance, ...)` in `LoadVulkanDevice`; guard `TVulkanRHIDevice.LoadPipelineCache` with `UriFileExists` and auto-create parent directories with `CheckForceDirectories` in `SavePipelineCache` and `TCastleShaderCompiler.SaveToDiskCache`.
* [x] **57.2. Full RHI & Interactive `TCastleWindow` Upgrade for `vulkan_triangle` and `vulkan_sprite_batch` (`CastleInternalBatch2DRHI`, `examples/vulkan/*`)**:
  * Expose `FrameQuadCount` and `BatchFlushCount` on `TCastleBatch2DRenderer` (with nil-safe swapchain target format defaults), add `render_backend="vulkan"` to all example manifests, and upgrade `vulkan_triangle.dpr` (VBO upload, GLSL 450 shader compilation, PSO baking, dynamic rendering pass, and interactive `TCastleWindow`) and `vulkan_sprite_batch.dpr` (20,000-sprite multi-batch draw call coalescing and interactive `TCastleWindow`).
* [x] **57.3. Comprehensive Architecture & Feature Reference (`doc/vulkan_renderer.md` & `TTestCastleVulkanRHI`)**:
  * Update `doc/vulkan_renderer.md` covering Phases 1–57, high-level `TCastleRenderOptions` / `TCastleViewport` properties, cross-platform `TCastleWindow` native `VkSurfaceKHR` support, and all three runnable examples, verified by 197 `TTestCastleVulkanRHI` unit tests (766 total engine tests).

**Milestone 57 Status**: Completed. All three Vulkan examples (`vulkan_triangle`, `vulkan_sprite_batch`, `vulkan_3d_scene`), live Vulkan 1.4 driver loader & cache directory guards, `doc/vulkan_renderer.md`, and 197 `TTestCastleVulkanRHI` unit tests (766 total `castle_tester_standalone` tests) verified with 0 failures.


### Phase 58: Per-Shape `TCastleRenderOptions` Push-Constant Packing & Scene Subsystem Orchestration (`CastleInternalShaderRHI`, `TMeshRenderer`, `TCastleViewport`) (COMPLETED)
**Goal**: Wire per-shape `TCastleRenderOptions` flags (`DualQuaternionSkinning`, `SpecularAntiAliasing`, `ShadowMapSystemMode`) into `TCastlePushConstantsBlock.ObjectParams` inside `TMeshRenderer`, add `TCastleViewport.ExecuteSceneRenderOptionsSubsystems` for per-scene GPU Meshlet Culling, Virtual Shadow Map page table allocation, and WBOIT/PPLL OIT execution, and prepare HDR scene targets for Next-Gen Tone Mapping modes (`ntmAgXGamutCompressed`, `ntmHDR10Rec2020PQ`), reaching the **200-test milestone** in `TTestCastleVulkanRHI` (**769** total engine tests).

* [x] **58.1. Per-Shape `BuildShapeRHIPushConstants` & `TMeshRenderer` Wiring (`CastleInternalShaderRHI`, `castleinternalrenderer_meshrenderer.inc`)**:
  * Implement `TCastleShaderGeneratorRHI.BuildShapeRHIPushConstants` packing `ModelViewMatrix`, std140-padded `NormalMatrixRow0..2`, and `ObjectParams` (`X` = BindlessMaterialIndex, `Y` = `0.0` static / `1.0` Linear Blend Skinning / `2.0` Dual-Quaternion Skinning, `Z` = SpecularAntiAliasing `1.0`/`0.0`, `W` = `Ord(ShadowMapSystemMode)`), and wire it into `TBaseCoordinateRenderer.Render`.
* [x] **58.2. Per-Scene `ExecuteSceneRenderOptionsSubsystems` & Next-Gen Tone Mapping HDR Target Prep (`CastleViewport`)**:
  * Implement `TCastleViewport.ExecuteSceneRenderOptionsSubsystems(ARenderOptions, ACommandList)` orchestrating `VkDev.MeshletCuller.DispatchMeshletCulling` (`GpuDrivenMeshletCulling`), `VkDev.VirtualShadowMap` root page allocation & upload (`smsVirtualShadowMaps`), `VkDev.WeightedBlendedOIT.EnsureOITTargets` (`tmWeightedBlendedOIT`), and `VkDev.PerPixelLinkedListOIT.DispatchPPLLResolve` (`tmPerPixelLinkedListOIT`), plus `VkDev.HDRPostProcessor.EnsureHDRTargets` when `NextGenToneMappingMode in [ntmAgXGamutCompressed, ntmHDR10Rec2020PQ]`.
* [x] **58.3. 200-Test `TTestCastleVulkanRHI` Milestone Verification (`testcastlevulkanrhi.pas`, `examples/vulkan/vulkan_3d_scene`)**:
  * Add `TestBuildShapeRHIPushConstantsObjectParamsPackingRHI`, `TestViewportExecuteSceneRenderOptionsSubsystemsRHI`, and `TestViewportNextGenToneMappingHDRTargetPreparationRHI`, reaching **200/200** `TTestCastleVulkanRHI` unit tests (**769/769** total `castle_tester_standalone` tests).

**Milestone 58 Status**: Completed. Per-shape `BuildShapeRHIPushConstants`, `TCastleViewport.ExecuteSceneRenderOptionsSubsystems`, Next-Gen Tone Mapping HDR target preparation, and **200/200** `TTestCastleVulkanRHI` unit tests (**769/769** total `castle_tester_standalone` tests) verified with 0 failures.


### Phase 59: GLSL 450 `castle_ObjectParams` Unpacking Macros, Scene-Tree `ExecuteAllScenesRenderOptionsSubsystems` & `TCastleWindow` Vulkan Frame Lifecycle (COMPLETED)
**Goal**: Emit GLSL 450 `castle_Object*` push-constant unpacking macros in `TCastleShaderGeneratorRHI`, automatically traverse the entire `TCastleViewport.Items` transform hierarchy via `ExecuteAllScenesRenderOptionsSubsystems` during `RenderFromViewEverything`, and wire headless-safe `TVulkanRHIDevice.BeginFrame`/`EndFrameAndPresent` and `TCastleWindow.BeginVulkanFrameIfNeeded`/`EndVulkanFrameIfNeeded` inside `TCastleWindow.DoRender`.

* [x] **59.1. GLSL 450 `castle_ObjectParams` Unpacking Macros & CPU Mirror (`CastleInternalShaderRHI`)**:
  * Emit `#define castle_ObjectParams`, `#define castle_ObjectMaterialIndex`, `#define castle_ObjectSkinningMode`, `#define castle_ObjectSpecularAAEnabled`, and `#define castle_ObjectShadowMapMode` in `GenerateStandardUniformBlocks`, paired with `TCastleShaderGeneratorRHI.UnpackShapeRHIPushConstantsObjectParams`.
* [x] **59.2. Automatic Scene-Tree `ExecuteAllScenesRenderOptionsSubsystems` (`CastleViewport`)**:
  * Implement `TCastleViewport.ExecuteAllScenesRenderOptionsSubsystems` recursively traversing `Items` (skipping `Exists = False` subtrees) and wire it into `TCastleViewport.RenderFromViewEverything`.
* [x] **59.3. Headless-Safe `BeginFrame` / `EndFrameAndPresent` & `TCastleWindow` Vulkan Frame Lifecycle (`CastleInternalRHI_Vulkan`, `CastleWindow`)**:
  * Support headless/offscreen command list recording and frame slot advancement in `TVulkanRHIDevice.BeginFrame` / `EndFrameAndPresent` (`TotalFramesPresented`), and wire `BeginVulkanFrameIfNeeded` / `EndVulkanFrameIfNeeded` (`VulkanFramesRenderedCount`) into `TCastleWindow.DoRender`.

**Milestone 59 Status**: Completed. GLSL 450 `castle_Object*` macros, `UnpackShapeRHIPushConstantsObjectParams`, recursive `ExecuteAllScenesRenderOptionsSubsystems`, and `TCastleWindow` / `TVulkanRHIDevice` frame lifecycle verified across **203/203** `TTestCastleVulkanRHI` unit tests (**772/772** total `castle_tester_standalone` tests).


### Phase 60: Default 3D Shader Consumption of `castle_ObjectParams` & `TCastleContainer` / `TCastleUserInterface` Headless Vulkan RHI Rendering (COMPLETED)
**Goal**: Wire `castle_ObjectSkinningMode`, `castle_ObjectSpecularAAEnabled`, and `castle_ObjectShadowMapMode` directly into `TCastleShaderGeneratorRHI.GenerateDefault3DVertexShader` and `GenerateDefault3DFragmentShader`, and enable full `TCastleContainer` / `TCastleUserInterface` hierarchy rendering (including borders, `ClipChildren` scissoring, and `TCastleRectangleControl`) in headless/pure Vulkan RHI mode without an OpenGL context.

* [x] **60.1. Default 3D Shader Consumption of `castle_ObjectParams` (`CastleInternalShaderRHI`)**:
  * In `GenerateDefault3DVertexShader`, branch on `castle_ObjectSkinningMode == 2` (`DualQuaternionSkinning`) to apply volume-preserving rotational orthonormalization (`skinRot = mat3(r0, r1, r2)`).
  * In `GenerateDefault3DFragmentShader` and `GenerateClusteredForwardAndShadowFunctions`, branch on `castle_ObjectSpecularAAEnabled` (`SpecularAntiAliasing`) to apply Tokuyoshi & Kaplanyan screen-space normal variance roughness filtering (`kernelRoughness2 = min(2.0 * normalVar, 0.18)`), and branch on `castle_ObjectShadowMapMode == 1` (`smsPCSSContactHardening`) to evaluate `SampleShadowAtlasPCSS` blocker search and contact-hardening penumbra scaling.
* [x] **60.2. `TCastleContainer` & `TCastleUserInterface` Headless Vulkan RHI Rendering (`CastleUIControls`, `CastleRenderContext`)**:
  * Guard `PerspectiveProjection`, `OrthoProjection`, and `FrustumProjection` in `CastleRenderContext` when `RenderContext = nil`.
  * Guard `TCastleContainer.RenderControlPrepare`, `TCastleContainer.EventRender`, and `TCastleUserInterface.InternalRecursiveRender` when `GLFeatures = nil` or `RenderContext = nil`, and track `TCastleContainer.RHIRenderedFramesCount`.
* [x] **60.3. Unit Test Verification (`testcastlevulkanrhi.pas`)**:
  * Add `TestDefault3DShadersConsumeCastleObjectParamsRHI`, `TestCastleContainerAndUIControlsHeadlessVulkanRenderRHI`, and `TestProjectionHelpersNilSafeRenderContextRHI`, reaching **206/206** `TTestCastleVulkanRHI` unit tests (**775/775** total `castle_tester_standalone` tests).

**Milestone 60 Status**: Completed. Default 3D shader consumption of `castle_ObjectParams` (Dual-Quaternion skinning, Specular AA, PCSS soft shadows) and headless Vulkan `TCastleContainer` / `TCastleUserInterface` rendering verified across **206/206** `TTestCastleVulkanRHI` unit tests (**775/775** total `castle_tester_standalone` tests).


### Phase 65: Automatic RHI Graphics Pipeline (`TRHIPipeline`) Construction, Caching & Command-List Binding (`TRenderer`, `TBaseCoordinateRenderer`, `TVulkanRHICommandList`) (COMPLETED)
**Goal**: Automatically construct, cache, and bind RHI Graphics Pipeline State Objects (`TRHIPipeline`) during `TBaseCoordinateRenderer.Render` (`ActiveCommandList.BindPipeline`), deriving vertex input bindings/attributes and primitive topology from `TGeometryArrays`, rasterizer polygon mode (`pmLine` vs `pmFill`) from `FWireframePass` / `RenderOptions.WireframeEffect`, backface culling and winding order from `RenderContext`, opaque vs alpha-blended depth/blend state from `RenderContext.DepthBufferUpdate`, and `Set 0..2` descriptor set layouts + push constant ranges.

* [x] **65.1. `TRenderer.EnsureRHIDefaultShaders`, `BuildShapePipelineDesc` & `GetOrCreateShapePipeline` (`castleinternalrenderer_renderer.inc`, `castleinternalrenderer_cache_types.inc`)**:
  * Expose `RHIMaterialDescriptorLayout` and `RHISkinningDescriptorLayout` on `TShapeCache`, compile/cache default RHI 3D forward vertex & fragment shader modules (`EnsureRHIDefaultShaders`), populate `TRHIGraphicsPipelineDesc` (`BuildShapePipelineDesc`), and query `RHIDevice.GetOrCreatePipeline` (`GetOrCreateShapePipeline`).
* [x] **65.2. Automatic `ActiveCommandList.BindPipeline` in `TBaseCoordinateRenderer.Render` & `TVulkanRHICommandList` Inspection (`castleinternalrenderer_meshrenderer.inc`, `CastleInternalRHI_Vulkan`)**:
  * Bind `ShapePipeline := Renderer.GetOrCreateShapePipeline(Shape, RenderOptions)` via `ActiveCommandList.BindPipeline(ShapePipeline)` before `PushConstants`, `BindDescriptorSet`, and `DrawIndexed`/`Draw`, and expose `BoundPipeline` and `PipelineBindCount` on `TVulkanRHICommandList`.
* [x] **65.3. Unit Test Verification (`testcastlevulkanrhi.pas`)**:
  * Add `TestRendererBuildShapePipelineDescAndCachingRHI`, `TestViewportRenderBindsGraphicsPipelineAndWireframePSORHI`, and `TestViewportOpaqueAndBlendedPipelineStatesRHI`, reaching **221/221** `TTestCastleVulkanRHI` unit tests (**790/790** total `castle_tester_standalone` tests).

**Milestone 65 Status**: Completed. Automatic RHI Graphics Pipeline (`TRHIPipeline`) construction, caching, wireframe/opaque/blended PSO state synchronization, and command-list binding verified across **221/221** `TTestCastleVulkanRHI` unit tests (**790/790** total `castle_tester_standalone` tests).


### Phase 66: Per-Shape RHI Shader Permutation Specialization, Caching & Shadow-Map Depth-Only PSO Construction (`TShapeCache`, `TX3DRendererShape`, `TRenderer`) (COMPLETED)
**Goal**: Specialize and cache per-shape RHI GLSL 450 vertex & fragment shader modules (`TShapeCache.EnsureRHIShaders`) driven by an 8-bit permutation bitmask (`HasSkinning`, `HasTangents`, `HasBaseColorTex`, `HasNormalTex`, `HasMetallicRoughnessTex`, `HasEmissiveTex`, `HasOcclusionTex`, `UseAlphaTest`), wire automatic specialization into `TX3DRendererShape.UploadRHIMaterialToCache` and `TShapeCache.UploadJointMatrices`, and automatically construct depth-only Shadow Map PSOs (`FragmentShader = nil`, `ColorAttachmentFormats = []`, `DepthBiasEnable = True`, `DefaultShadowMap`) when `RenderingCamera.Target = rtShadowMap` or `RenderOptions.Mode = rmDepth`.

* [x] **66.1. `TShapeCache.EnsureRHIShaders` & 8-Bit Permutation Caching (`castleinternalrenderer_cache_types.inc`)**:
  * Add `FRHIVertexShader`, `FRHIFragmentShader`, `FRHIVertexShaderSource`, `FRHIFragmentShaderSource`, and `FRHIShaderPermutationMask` to `TShapeCache`, compiling/caching specialized `TRHIShaderModule` instances on demand and invalidating when `UploadJointMatrices` activates skinning.
* [x] **66.2. Automatic Material/Texture Shader Specialization & Shadow-Map Depth-Only PSOs (`castleinternalrenderer_shape.inc`, `castleinternalrenderer_renderer.inc`)**:
  * Call `Cache.EnsureRHIShaders` in `TX3DRendererShape.UploadRHIMaterialToCache`, bind `AShape.Cache.RHIVertexShader` / `RHIFragmentShader` in `TRenderer.BuildShapePipelineDesc`, and configure depth-only shadow map PSO state (`CastleShapeShadowDepthPSO`) when `RenderingCamera.Target = rtShadowMap` or `RenderOptions.Mode = rmDepth`.
* [x] **66.3. Unit Test Verification (`testcastlevulkanrhi.pas`)**:
  * Add `TestShapeCacheEnsureRHIShadersPermutationMaskRHI`, `TestUploadRHIMaterialAutoSpecializesShapeShadersRHI`, and `TestShadowMapDepthOnlyPipelineSpecializationRHI`, reaching **224/224** `TTestCastleVulkanRHI` unit tests (**793/793** total `castle_tester_standalone` tests).

**Milestone 66 Status**: Completed. Per-shape 8-bit RHI shader permutation specialization/caching and automatic shadow-map depth-only PSO construction verified across **224/224** `TTestCastleVulkanRHI` unit tests (**793/793** total `castle_tester_standalone` tests).


### Phase 67: Automatic `TCastleBatch2DRenderer` Lifecycle Management & `TDrawableImage` / 2D UI Controls (`TCastleImageControl`, `TCastleButton`, `TCastleLabel`) Vulkan RHI Rendering (COMPLETED)
**Goal**: Automatically manage `TCastleBatch2DRenderer` creation and `Begin2DPass`/`End2DPass` bracketing during `TCastleContainer.EventRender` and standalone `TDrawableImage.Draw`, track live `TRHIResource` ownership in `TRHIDevice` so global singletons (`Theme`, `UIFont`) never dereference destroyed `TRHIDevice` instances across test/window lifecycles, and enable full 2D UI control rendering (`TCastleImageControl`, `TCastleButton`, `TCastleLabel`, `Draw3x3` 9-slice skinning, rotation, and blend modes) in pure Vulkan RHI mode.

* [x] **67.1. Safe `TRHIResource` Device-Destruction Detachment & `EnsureBatch2DRenderer` (`CastleInternalRHI`, `CastleInternalBatch2DRHI`)**:
  * Track live `TRHIResource` instances in `TRHIDevice.FResources` and detach (`FDevice := nil`) remaining resources in `TRHIDevice.Destroy` so global `Theme`/`UIFont` textures outliving a device never cause use-after-free on teardown.
  * Implement `EnsureBatch2DRenderer(ADevice)` and `FreeGlobalBatch2DRenderer`, expose `Device`, `In2DPass`, `TotalQuadsDrawn`, and `TotalFlushes` on `TCastleBatch2DRenderer`, and support normalized `(0..1)` vs screen-coordinate `RotationCenter` (`RotationCenterInScreenCoords`) in `TCastleBatch2DRenderer.DrawQuads`.
* [x] **67.2. Automatic `Begin2DPass` / `End2DPass` in `TCastleContainer.EventRender` & `TDrawableImage.DrawNoBatch` (`castleuicontrols_container.inc`, `castleglimages_drawableimage.inc`, `castlescreeneffects.pas`, `castlefonts_font.inc`)**:
  * Bracket `TCastleContainer.EventRender` (`RenderCore`) with `EnsureBatch2DRenderer(RHIDevice).Begin2DPass` / `End2DPass`, flush `ActiveBatch2DRenderer` inside `TDrawableImage.BatchingFlush` (and call `TDrawableImage.BatchingFlush` unconditionally in `TCastleScreenEffects.Render`), auto-bracket standalone `TDrawableImage.DrawNoBatch` calls when not already inside a 2D pass, and guard `TCastleFont.PrepareResources.AttachDistanceFieldShader` when `not ApplicationProperties.IsGLContextOpen`.
* [x] **67.3. Unit Test Verification (`testcastlevulkanrhi.pas`)**:
  * Add `TestEnsureBatch2DRendererAndStandaloneDrawableImageDrawRHI`, `TestCastleImageControlAndButtonHeadlessVulkanRenderRHI`, and `TestDrawableImageBlendModesAndRotationBatch2DRHI`, reaching **227/227** `TTestCastleVulkanRHI` unit tests (**796/796** total `castle_tester_standalone` tests).

**Milestone 67 Status**: Completed. Automatic `TCastleBatch2DRenderer` lifecycle management (`EnsureBatch2DRenderer`), `TCastleContainer.EventRender` 2D pass bracketing, and `TDrawableImage` / `TCastleImageControl` / `TCastleButton` / `TCastleLabel` Vulkan RHI rendering verified across **227/227** `TTestCastleVulkanRHI` unit tests (**796/796** total `castle_tester_standalone` tests).


### Phase 68: Complete RHI Pipeline, Shader & Topology Expansion for 2D Primitives (`DrawPrimitive2D`, `DrawRectangle`, `DrawCircle`, `GLFadeRectangleDark`), 3D Unlit Meshes (`TCastleRenderUnlitMesh`) & `MainScene` Screen Effects (COMPLETED)
**Goal**: Complete RHI GLSL 450 shader compilation, push constant range wiring, blend factor mapping, scissor application, and `pmTriangleFan`/`pmLineLoop` topology expansion in `DrawPrimitive2D` (`DrawRectangle`, `DrawRectangleOutline`, `DrawCircle`, `DrawCircleOutline`, `GLFadeRectangleDark`, `GLFadeRectangleLight`), wire GLSL 450 shaders and dynamic `RenderContext` depth/cull/color-mask state into `TCastleRenderUnlitMesh`, and resolve `Items.MainScene` screen effects in `TCastleViewport.InternalExtraGetScreenEffectRHIPipeline`.

* [x] **68.1. `DrawPrimitive2D` RHI Shaders, Blend Factor Mapping & `pmTriangleFan` / `pmLineLoop` Expansion (`castleglutils_draw_primitive_2d.inc`)**:
  * Compile GLSL 450 2D primitive vertex/fragment shaders (`RHIVertShader`, `RHIFragShader`), configure `PushConstantSize = 32` (`[ssVertex, ssFragment]`), map `TBlendingSourceFactor`/`TBlendingDestinationFactor` to `TRHIBlendFactor`, apply `RenderContext.FinalScissor`, expand `pmTriangleFan` (when not already pre-expanded triangle triples from `DrawCircle`) into `3 * (N - 2)` vertices and `pmLineLoop` into `N + 1` vertices closing the loop, and expose `RHIPrimitive2DLastSubmittedVertexCount` and `RHIPrimitive2DPipeline`.
* [x] **68.2. `TCastleRenderUnlitMesh` RHI Shaders & State Synchronization & `TCastleViewport.InternalExtraGetScreenEffectRHIPipeline` (`castlerenderprimitives_render_unlit_mesh.inc`, `castlescreeneffects.pas`, `castleviewport.pas`)**:
  * Compile GLSL 450 4D unlit mesh shaders (`RHIVertShader`, `RHIFragShader`) in `TCastleRenderUnlitMesh.PrepareRHIPipeline`, configure `PushConstantSize = 80` (`mat4 + vec4`), and synchronize `DepthStencil.DepthTestEnable`, `Rasterizer.CullMode`, and `BlendState` (`DefaultColorMaskNone` when `not UseColor`) with `RenderContext`.
  * Add `InternalExtraGetScreenEffectRHIPipeline` in `TCastleScreenEffects` and override in `TCastleViewport` so screen effects inside `Viewport.Items.MainScene` resolve their `TScreenEffectResource.RHIPipeline` in `GetScreenEffectRHIPipeline`.
* [x] **68.3. Unit Test Verification (`testcastlevulkanrhi.pas`)**:
  * Add `TestDrawPrimitive2DFanAndLineLoopExpansionAndShadersRHI`, `TestRenderUnlitMeshShadersPushConstantsAndDepthStateRHI`, and `TestViewportMainSceneScreenEffectRHIPipelineAndRenderRHI`, reaching **230/230** `TTestCastleVulkanRHI` unit tests (**799/799** total `castle_tester_standalone` tests).

**Milestone 68 Status**: Completed. `DrawPrimitive2D` RHI shaders, blend-factor mapping, and `pmTriangleFan`/`pmLineLoop` topology expansion, `TCastleRenderUnlitMesh` RHI shaders and depth/color-mask state synchronization, and `MainScene` RHI screen effect pipeline resolution verified across **230/230** `TTestCastleVulkanRHI` unit tests (**799/799** total `castle_tester_standalone` tests).


### Phase 69: End-to-End 3D Skybox & 2D Image Background (`TBackgroundRenderer`, `TRenderer.BuildSceneUniformBlock`), Full Multi-Pass Stencil Shadow Volumes (`TGLShadowVolumeRenderer`, `TCastleViewport`, `TCastleRenderUnlitMesh`, `TRenderer.BuildShapePipelineDesc`) & Generated Texture (`TRenderedTextureResource`, `TGeneratedShadowMapResource`, `GLCaptureCubeMapTexture`) Viewport/Projection Synchronization in Pure Vulkan RHI Mode (COMPLETED)
**Goal**: Synchronize `RenderingCamera.RotationOnly` view matrix and zero camera position in `TRenderer.BuildSceneUniformBlock` for 3D skybox (`TBackgroundScene`) and 2D background (`TBackground2D`) rendering, enable full multi-pass stencil shadow volumes (`TCastleViewport.RenderWithShadowVolumes`, `TGLShadowVolumeRenderer`, `TCastleRenderUnlitMesh.CustomDepthStencilState`, `TRenderer.BuildShapePipelineDesc` `FInternalPass = 1`) in pure Vulkan RHI mode (`GLFeatures = nil`), and synchronize `RenderContext.Viewport` and `RenderContext.ProjectionMatrix` during generated texture updates (`TRenderedTextureResource.Update`, `TGeneratedShadowMapResource.Update`, `GLCaptureCubeMapImages`, `GLCaptureCubeMapTexture`).

* [x] **69.1. 3D Skybox & 2D Image Background `RotationOnly` View Matrix & Color Clear (`castleinternalrenderer_renderer.inc`, `castleinternalbackgroundrenderer.pas`)**:
  * In `TRenderer.BuildSceneUniformBlock`, use `RenderingCamera.CurrentMatrix` (and `RenderingCamera.RotationInverseMatrix` with `CameraPosition = (0,0,0,0)` when `RenderingCamera.RotationOnly = True`), and allow `TBackgroundScene.Render` to call `RenderContext.Clear([cbColor], ClearColor)` when `RHIDevice <> nil`.
* [x] **69.2. Full Multi-Pass Stencil Shadow Volumes in `TCastleViewport`, `TGLShadowVolumeRenderer`, `TCastleRenderUnlitMesh` & `TRenderer.BuildShapePipelineDesc` (`castleviewport.pas`, `castleinternalglshadowvolumes.pas`, `castlerenderprimitives_render_unlit_mesh.inc`, `castleinternalrenderer_renderer.inc`)**:
  * Enable `Params.UsingShadowVolumes` and stencil clear in `TCastleViewport` when `RHIDevice <> nil` and expose `TCastleViewport.InternalShadowVolumeRenderer`.
  * Add `CustomDepthStencilState` / `UseCustomDepthStencilState` and `RenderContext.DepthFunc` mapping (`dfNever -> coNever`, etc.) to `TCastleRenderUnlitMesh.PrepareRHIPipeline`, wire `FMesh.CustomDepthStencilState := FRHIStencilDepthState` in `TGLShadowVolumeRenderer.ActuallySetStencilConfiguration`, save/set/restore `RenderContext` state around Pass 3 in `TGLShadowVolumeRenderer.Render`, and configure `DefaultStencilLitPass(0, $FF)` in `TRenderer.BuildShapePipelineDesc` when `FInternalPass = 1` (lit opaque pass).
* [x] **69.3. Generated Texture Viewport & Projection Synchronization & Unit Test Verification (`castleinternalrenderer_texture.inc`, `castleinternalglcubemaps.pas`, `testcastlevulkanrhi.pas`)**:
  * Update `RenderContext.Viewport` and `RenderContext.ProjectionMatrix` (and `PolygonOffset`) in `TRenderedTextureResource.Update`, `TGeneratedShadowMapResource.Update`, `GLCaptureCubeMapImages`, and `GLCaptureCubeMapTexture` when `RHIDevice <> nil`.
  * Add `TestViewport3DSkyboxAndImageBackgroundRotationOnlyViewMatrixRHI`, `TestViewportStencilShadowVolumesEndToEndMultiPassAndMeshPSORHI`, and `TestSceneUpdateGeneratedTexturesRenderedTextureAndShadowMapRHI`, reaching **233/233** `TTestCastleVulkanRHI` unit tests (**802/802** total `castle_tester_standalone` tests).

**Milestone 69 Status**: Completed. 3D skybox & 2D image background `RotationOnly` view matrix synchronization, full multi-pass stencil shadow volumes, and generated texture viewport/projection synchronization verified across **233/233** `TTestCastleVulkanRHI` unit tests (**802/802** total `castle_tester_standalone` tests).


### Phase 70: End-to-End Hardware Occlusion Query Culling (`TOcclusionCullingUtilsRenderer` / `TOcclusionCullingRenderer`), Dynamic Shape Batching (`TBatchShapes` / `TShapesRenderer`), and On-Demand Material Texture Resolution (`TX3DRendererShape.ExtractRHIMaterialTextures`) in Pure Vulkan RHI Mode (COMPLETED)

* [x] **70.1. Hardware Occlusion Query Bounding Box Unlit Mesh PSO & State Synchronization (`src/scene/castleinternalocclusionculling.pas`, `src/scene/castleinternalshapesrenderer.pas`, `src/scene/castleviewport.pas`)**:
  * Upgrade `TOcclusionCullingUtilsRenderer` to allocate and render bounding boxes via `RenderBox: TCastleRenderUnlitMesh` (`Create(false)`) in both OpenGL and RHI modes so `DrawBox` compiles and binds the unlit mesh RHI PSO (`DefaultColorMaskNone`, `DepthWriteEnable = False`) and uploads `ProjectionMatrix * CameraMatrix * SceneMatrix` push constants.
  * Update `OcclusionBoxStateBegin` and `OcclusionBoxStateEnd` to synchronize `RenderContext.DepthBufferUpdate`, `ColorChannels`, and `CullFace` when `(RHIDevice <> nil) or ApplicationProperties.IsGLContextOpen`.
  * Expose `RenderBoxMesh` on `TOcclusionCullingUtilsRenderer`, `InternalBatching` and `InternalOcclusionCullingRenderer` on `TShapesRenderer`, and `InternalShapesRenderer` on `TCastleViewport`.
* [x] **70.2. Dynamic Shape Batching Appearance & Material Synchronization (`src/scene/castleinternalbatchshapes.pas`)**:
  * Update `ChangeAppearance` in `CastleInternalBatchShapes` so pool shapes synchronize `Shape.OriginalState.Appearance` and reset `Shape.RHIBindlessMaterialRegistered := False` when merged across frames.
* [x] **70.3. Universal & On-Demand Material Texture Resolution (`src/scene/castleinternalrenderer_shape.inc`, `tests/code/testcases/testcastlevulkanrhi.pas`)**:
  * Expand `ResolveNodeRHITexture` in `TX3DRendererShape.ExtractRHIMaterialTextures` to unwrap `TMultiTextureNode`, auto-prepare unprepared texture nodes on demand when `RHIDevice <> nil`, and resolve `TRenderedTextureResource`, `TCubeMapTextureResource` (`TGeneratedCubeMapTextureResource`, `TComposedCubeMapTextureResource`, `TImageCubeMapTextureResource`), `T3DTextureResource`, and `TGeneratedShadowMapResource` in addition to `TImageTextureResource` and `TMovieTextureResource`.
  * Add `TestViewportOcclusionCullingEndToEndAndBoxUnlitMeshPSORHI`, `TestViewportDynamicBatchingMergesShapesAndUploadsRHIBuffersRHI`, and `TestShapeExtractRHIMaterialTexturesAllResourceTypesAndOnDemandPrepareRHI`, reaching **236/236** `TTestCastleVulkanRHI` unit tests (**805/805** total `castle_tester_standalone` tests).

**Milestone 70 Status**: Completed. End-to-end hardware occlusion query culling with unlit mesh RHI PSOs, dynamic shape batching with RHI buffer/material synchronization, and universal on-demand material texture resolution verified across **236/236** `TTestCastleVulkanRHI` unit tests (**805/805** total `castle_tester_standalone` tests).


### Phase 71: End-to-End GPU Skeletal Skinning (`TSkinNode`, `TSkinnedRenderer`), 2D/3D Stencil Masking (`TCastleMask`, `TRenderContext` Stencil State Synchronization) & Nil-Safe Texture Sizing Helpers in Pure Vulkan RHI Mode (COMPLETED)

* [x] **71.1. End-to-End GPU Skeletal Skinning (`src/scene/castlescene.pas`, `src/scene/x3d/x3dnodes_castle.inc`, `src/scene/castleinternalrenderer_meshrenderer.inc`, `src/scene/castlerendererinternalshader_skin.inc`)**:
  * Initialize `TSkinNode.InternalFeatures` in `InitializeSkinInShaders`, `TCastleScene.PrepareResources`, and `TSkinNode.InternalMeshCalculation` when `RHIDevice <> nil` / `RenderBackend = rbVulkan` so `TSkinNode.InternalMeshCalculation` selects GPU skinning (`mcGpuTexture` / `mcGpuUniforms`) in pure Vulkan RHI mode (`GLFeatures = nil`).
  * Upload joint matrices (`Shape.Cache.UploadJointMatrices`) in `TSkinnedRenderer.RenderCoordinateBegin` whenever `RHIDevice <> nil`, populating `RHIJointBuffer` (`TRHIBuffer`), binding `RHISkinningDescriptorSet` (Set 2, Binding 0), and specializing the `SKIN_ANIMATION` vertex shader.
* [x] **71.2. End-to-End 2D & 3D Stencil Masking (`src/base_rendering/castlerendercontext.pas`, `src/ui/castlecontrols.pas`, `src/ui/castlecontrols_mask.inc`, `src/base_rendering/rhi/castleinternalbatch2drhi.pas`, `src/base_rendering/castleglutils_draw_primitive_2d.inc`, `src/scene/castleinternalrenderer_renderer.inc`)**:
  * Add `StencilTest`, `StencilFunc`, `StencilOp`, and `ApplyRHIStencilAndColorMask` to `TRenderContext` and flush queued 2D batches (`TDrawableImage.BatchingFlush`) before state changes.
  * Update `TCastleMask.InternalRenderLoop` to support stencil masking when `RHIDevice <> nil` and route all stencil state transitions through `RenderContext`.
  * Apply `RenderContext.ApplyRHIStencilAndColorMask` in `TCastleBatch2DRenderer.Flush` (exposing `LastPipeline`), `DrawPrimitive2D`, and `TRenderer.BuildShapePipelineDesc`.
* [x] **71.3. Nil-Safe Texture Sizing Helpers & `TCastleScreenEffects` 2D Child Flush (`src/base_rendering/castleglimages_load_2d.inc`, `src/base_rendering/castleglimages_load_3d.inc`, `src/base_rendering/castleglimages_load_cubemap.inc`, `src/scene/castleinternalrenderer_cache.inc`, `src/scene/castlescreeneffects.pas`, `tests/code/testcases/testcastlevulkanrhi.pas`)**:
  * Make `ResizeToTextureSize`, `IsTextureSized`, `IsTexture3DSized`, `IsCubeMapTextureSized`, `ResizeToCubeMapTextureSize`, and `TRendererCache` nil-safe when `GLFeatures = nil`, and flush 2D batches before `ScreenEffectRTT.RenderEnd` in `TCastleScreenEffects.RenderOverChildren`.
  * Add `TestViewportSkinNodeGPUSkinningEndToEndAndJointUploadRHI`, `TestCastleMask2DAnd3DStencilMaskingEndToEndRHI`, and `TestTextureSizingHelpersNilSafeInPureRHIModeRHI`, reaching **239/239** `TTestCastleVulkanRHI` unit tests (**808/808** total `castle_tester_standalone` tests).

**Milestone 71 Status**: Completed. End-to-end GPU skeletal skinning (`TSkinNode`), 2D/3D stencil masking (`TCastleMask` + `TRenderContext`), and nil-safe texture sizing helpers verified across **239/239** `TTestCastleVulkanRHI` unit tests (**808/808** total `castle_tester_standalone` tests).


### Phase 72: End-to-End 3D Text (`TCastleText`, `TTextNode.FontTextureNode`), Per-Vertex Color (`TColorNode`, `TColorRGBANode`), Unlit Line/Point Primitives (`TPointSetNode`, `TLineSetNode`, `Arrays.ForceUnlit`), Solid-Color/Unlit Modes (`rmSolidColor`, `RenderOptions.Lighting = False`), Polygon Offset Depth Bias (`weSolidWireframe`, `weSilhouette`) & Linear/Exponential Scene Fog (`TFogNode`, `TCastleFog`) in Pure Vulkan RHI Mode (COMPLETED)

* [x] **72.1. 3D Text Font Atlas Texture Resolution (`src/scene/castleinternalrenderer_shape.inc`)**:
  * Update `TX3DRendererShape.ExtractRHIMaterialTextures` to resolve `OriginalGeometry.FontTextureNode` (`TTextNode.FontTextureNode` used by `TCastleText` and X3D `Text` nodes) even when `Appearance` or `Appearance.Texture` is `nil`, and respect `Cache.RenderOptions.Mode = rmSolidColor` and `not Cache.RenderOptions.Textures`.
* [x] **72.2. Solid-Color, Unlit & Point/Line Material Extraction and Polygon Offset Depth Bias (`src/scene/castleinternalrenderer_shape.inc`, `src/scene/castleinternalrenderer_renderer.inc`)**:
  * Update `TX3DRendererShape.ExtractRHIMaterialBlock` to handle `Cache.RenderOptions.Mode = rmSolidColor` (using `Cache.RenderOptions.SolidColor`), `Cache.Arrays.ForceUnlit` (`TPointSetNode`, `TLineSetNode`, `TIndexedLineSetNode` using `Cache.Arrays.ForcedUnlitColor`), `not Cache.RenderOptions.Lighting` (forcing `smUnlit` while preserving `BaseColor`), and `AlphaChannel = acTest` when `Appearance = nil`.
  * Synchronize `ADesc.Rasterizer.DepthBiasEnable`, `DepthBiasSlopeFactor`, and `DepthBiasConstantFactor` with `RenderContext.PolygonOffset` in `TRenderer.BuildShapePipelineDesc` for `weSolidWireframe` and `weSilhouette` rendering passes.
* [x] **72.3. Per-Vertex Color Specialization (`$100`), `gl_PointSize` & Linear/Exponential Scene Fog Shader Evaluation (`src/scene/castleinternalrenderer_cache_types.inc`, `tests/code/testcases/testcastlevulkanrhi.pas`)**:
  * Extend `TShapeCache.EnsureRHIShaders` with `AHasColorPerVertex: Boolean = False` (bit `$100` in `RHIShaderPermutationMask`), multiplying `baseColor` by `castle_color_per_vertex` when `Cache.Arrays.ColorType <> ctNone`, writing `gl_PointSize = 1.0;` in the vertex shader, and evaluating linear/exponential scene fog (`CastleScene.u_FogParams` / `CastleScene.u_FogColor`) in the fragment shader.
  * Add `TestCastleTextAndPrimitivesHeadlessVulkanRenderRHI`, `TestPointSetLineSetForceUnlitAndPerVertexColorSpecializationRHI`, and `TestSolidWireframeSilhouettePolygonOffsetAndFogShaderRHI`, reaching **242/242** `TTestCastleVulkanRHI` unit tests (**811/811** total `castle_tester_standalone` tests).

**Milestone 72 Status**: Completed. End-to-end 3D text (`TCastleText` / `TTextNode.FontTextureNode`), per-vertex color (`TColorNode` / `TColorRGBANode`), unlit point/line primitives (`TPointSetNode` / `TLineSetNode`), `rmSolidColor` / `RenderOptions.Lighting = False`, polygon offset depth bias (`weSolidWireframe` / `weSilhouette`), and linear/exponential scene fog (`TFogNode`) verified across **242/242** `TTestCastleVulkanRHI` unit tests (**811/811** total `castle_tester_standalone` tests).


## 4.1. Unreal Engine 5 vs. Castle Game Engine Vulkan RHI Feature Parity Matrix

| Unreal Engine 5 Subsystem | Castle Game Engine Vulkan RHI Equivalent | Phase & Status |
| :--- | :--- | :--- |
| **RDG (Render Dependency Graph)** | `TRHIRenderGraph` & `TRHIRenderGraphPass` (DAG topological sort, dead-pass culling, transient texture aliasing, automatic barrier hoisting) | Phase 15 (COMPLETED) |
| **Virtual Shadow Maps (VSM)** | `TCastleVulkanVirtualShadowMap` ($64 \times 64$ virtual page table, $16 \times 16$ physical $128 \times 128$ tile pool, `GenerateVSMPageLookupFunctions`) | Phase 23 (COMPLETED) |
| **Nanite Cluster Culling** | `TCastleVulkanMeshletCuller` (64v/124t meshlets, cone backface + sphere culling) & `TCastleVulkanComputeCuller` (Hi-Z + frustum + `vkCmdDrawIndexedIndirectCount`) | Phases 7–9, 22 (COMPLETED) |
| **Nanite Visibility Buffer, Cluster DAG & Software Micro-Rasterizer** | `GenerateVisibilityBufferFunctions` (64-bit payload + analytic UV derivatives), `TCastleVulkanClusterDAG` (monotonic parent/child error cut), `GenerateSoftwareMicroRasterComputeShader` | Phase 27 (COMPLETED) |
| **Lumen GI & Reflections (Hardware + Software)** | `TCastleVulkanDDGIGrid` (Octahedral irradiance + Chebyshev visibility probes), `TCastleVulkanSSR` (Hi-Z raymarch), `VK_KHR_ray_query` (`GenerateInlineRayQueryFunctions`), plus Global SDF Clipmap (`TCastleVulkanGlobalSDF`), 6-Axis Surface Cache (`TCastleVulkanSurfaceCache`) & Screen Radiance Cache (`GenerateScreenRadianceCacheFunctions`) | Phases 16, 22, 23, 28 (COMPLETED) |
| **MegaLights / ReSTIR Direct & Indirect Lighting** | `TCastleVulkanClusteredLightCuller` (3D Forward+ 256+ lights) + `TCastleVulkanReSTIR` (Spatio-temporal reservoir resampling WRS/RIS, `GenerateReSTIRReservoirFunctions`) | Phases 14, 29 (COMPLETED) |
| **Temporal Super Resolution (TSR) & TAA** | `TCastleVulkanTAA` (Halton jitter + YCoCg variance clipping) + `TCastleVulkanTSRUpscaler` (Lanczos-2 sub-pixel history upscaling & disocclusion anti-ghosting, `GenerateTSRUpscaleComputeShader`) + CAS (`EvaluateCASFilter5Tap`) | Phases 16, 22, 30 (COMPLETED) |
| **Substrate / Strata Material System** | Full Cook-Torrance GGX PBR, Clear Coat, Anisotropy, Subsurface/Transmission, Cloth Sheen, Thin-Film Iridescence, Separable Burley SSSS, plus Energy-Conserving Layered Material Slabs (`GenerateSubstrateLayeredMaterialFunctions`), Marschner Hair/Fur BSDF (`GenerateHairMarschnerBSDF`) & Stochastic Glints (`GenerateStochasticGlintFunctions`) | Phases 13, 19–21, 23, 31 (COMPLETED) |
| **Sky Atmosphere, Volumetric Fog & Volumetric Clouds** | `TCastleVulkanAtmosphereRenderer` (Rayleigh/Mie Sky-View LUT), `TCastleVulkanVolumetricFog` ($160 \times 90 \times 64$ Froxel Fog), `GenerateVolumetricCloudFunctions` (Dual-Lobe HG + Beer-Powder) | Phases 16, 20, 25 (COMPLETED) |
| **Niagara GPU Particles** | `TCastleVulkanComputeParticles` (Compute simulation + `vkCmdDrawIndirect`) | Phase 17 (COMPLETED) |
| **Water System (Ocean + Single-Layer Water)** | `TCastleVulkanOceanSimulator` (Gerstner wave spectrum + Jacobian crest foam) + Single-Layer Water Beer-Lambert absorption, Snell refraction & photon caustics (`GenerateSingleLayerWaterFunctions`) | Phases 21, 33 (COMPLETED) |
| **World Partition Landscape & Runtime Virtual Texturing (RVT)** | `TCastleVulkanTerrainCDLOD` (Quadtree morphing CDLOD), `TCastleVulkanTextureStreamer` (GPU mip feedback), Triplanar/Height blending & `TCastleVulkanRuntimeVirtualTexture` | Phases 19, 25, 26, 32 (COMPLETED) |
| **Hardware Mesh Shaders & Variable Rate Shading (VRS)** | `VK_EXT_mesh_shader` (`GenerateMeshShaderStageFunctions`) & `VK_KHR_fragment_shading_rate` (`TCastleVulkanVRSManager`) | Phase 32 (COMPLETED) |
| **Heterogeneous Volumes & GPU Crash Breadcrumbs** | `TCastleVulkanSparseVolumeAtlas` (Planckian blackbody emission) & `TCastleVulkanBreadcrumbTracker` | Phase 33 (COMPLETED) |
| **SVGF Spatio-Temporal Ray Reconstruction & Denoising** | `TCastleVulkanSVGFDenoiser` (Temporal luminance moments + Edge-stopping À-Trous wavelet + Hit-distance contact hardening) | Phase 34 (COMPLETED) |
| **Hardware Ray Tracing Pipeline (`VK_KHR_ray_tracing_pipeline`) & SBT** | `TCastleVulkanShaderBindingTable` & `TCastleVulkanAccelerationStructureManager` | Phase 35 (COMPLETED) |
| **Chaos Cloth / Hair XPBD GPU Physics** | `TCastleVulkanXPBDSimulator` (Compliant XPBD constraints + Aerodynamic wind + SDF collision) | Phase 36 (COMPLETED) |
| **Single-Pass Stereo VR (`VK_KHR_multiview`), Foveated VRS & HDR10 PQ** | `TCastleVulkanMultiviewStereoManager`, `GenerateMultiviewStereoPreamble`, `EvaluateFoveatedShadingRate` & `EncodeST2084PQ` (Rec.2020 / ST.2084) | Phase 37 (COMPLETED) |
| **MegaGeometry Displaced Micro-Meshes, Dual-Quaternion Skinning & Per-Instance Custom Data** | `GenerateDualQuaternionSkinningFunctions`, `GenerateDisplacedMicroMeshFunctions` & `TCastleVulkanPerInstanceCustomData` | Phase 38 (COMPLETED) |
| **Neural Radiance Cache / MLP Denoising, Optical Flow & R2 Spatio-Temporal Blue-Noise** | `TCastleVulkanNeuralDenoiser`, `GenerateOpticalFlowBlockMatchingShader` & `EvaluateR2Sequence2D` | Phase 39 (COMPLETED) |
| **Shader Execution Reordering (SER), Dual-Source Colored Glass & Programmable MSAA Sample Locations** | `PackSERCoherenceHintKey`, `EvaluateDualSourceGlassOutputs` & `TCastleVulkanProgrammableSampleLocations` | Phase 40 (COMPLETED) |
| **Vulkan 1.4 Dynamic Rendering Local Read, Subgroup Wave Intrinsics & GPU Stream Compaction** | `GenerateDynamicRenderingLocalReadPreamble`, `GenerateSubgroupWaveIntrinsicsFunctions` & `TCastleVulkanStreamCompactor` | Phase 41 (COMPLETED) |
| **Buffer Device Address (`VK_KHR_buffer_device_address`) & 3D Voxel Cone Tracing (VXGI)** | `GenerateBufferDeviceAddressPreamble`, `GenerateVoxelConeTracingFunctions` & `TCastleVulkanVoxelConeTracer` | Phase 42 (COMPLETED) |
| **GPU Indirect Material Binning, Normal-Variance Specular AA & Rectilinear Shadow Warping** | `EvaluateSpecularAARoughness`, `EvaluateRectilinearShadowWarpUV` & `TCastleVulkanMaterialBinner` | Phase 43 (COMPLETED) |
| **Procedural Bezier Grass Blades, Multi-Channel SDF (MSDF) Text & Per-Pixel Linked List OIT** | `EvaluateMSDFMedianOfThree`, `EvaluateQuadraticBezierGrassBlade` & `TCastleVulkanPerPixelLinkedListOIT` | Phase 44 (COMPLETED) |
| **Vulkan 1.4 Push Descriptors, Host Image Copy (`VK_EXT_host_image_copy`) & Spherical Gaussians** | `ComputeHostImageCopyByteSize`, `GenerateSphericalGaussianFunctions` & `TCastleVulkanHostImageCopyManager` | Phase 45 (COMPLETED) |
| **3D Gaussian Splatting (3DGS) Conic Covariance, Spherical Harmonics & Tile Sorter** | `EvaluateGaussianSplatOpacity`, `EvaluateSphericalHarmonicsL1RGB` & `TCastleVulkanGaussianSplatRenderer` | Phase 46 (COMPLETED) |
| **Vulkan Descriptor Buffers (`VK_EXT_descriptor_buffer`) & PCSS Soft Shadows** | `EvaluatePCSSPenumbraWidth`, `ComputeDescriptorBufferAlignedOffset` & `TCastleVulkanDescriptorBufferManager` | Phase 47 (COMPLETED) |
| **Multi-Layer Car-Paint Flake BRDF, Screen-Space Curvature & Hi-Z Depth Pyramid** | `EvaluateCarPaintMultiLayerBRDF`, `EvaluateScreenSpaceCurvatureCavity` & `TCastleVulkanHiZPyramidGenerator` | Phase 48 (COMPLETED) |
| **AgX Chroma Gamut Compression, Camera EV100 & GPU Luminance Histogram Auto-Exposure** | `EvaluateEV100FromCameraSettings`, `EvaluateChromaGamutCompression` & `TCastleVulkanAutoExposureHistogram` | Phase 49 (COMPLETED) |
| **Analytical Capsule Soft Shadow/AO, Epipolar Light Shafts & GPU Frame Pacing Manager** | `EvaluateCapsuleSoftShadowOcclusion`, `EvaluateEpipolarSliceRayStep` & `TCastleVulkanFramePacer` | Phase 50 (COMPLETED) |
| **Cooperative Matrix Tensor Cores, Anisotropic Kuwahara Filter & Indirect Compute Dispatcher** | `EvaluateQuantizedFP8ToFloat`, `EvaluateStructureTensorEigenOrientation` & `TCastleVulkanIndirectComputeDispatcher` | Phase 51 (COMPLETED) |
| **Physical Eye Cornea Refraction, 6-Point Lightmap Basis & GPU BC1/BC6H Block Compressor** | `EvaluateEyeIrisRefractionUVOffset`, `EvaluateSixPointDirectionalBasis` & `TCastleVulkanBCnCompressor` | Phase 52 (COMPLETED) |
| **Secant-Refined POM, Spectral Cauchy Chromatic Dispersion & Pipeline Binary Manager** | `EvaluateSecantRefinedPOMIntersection`, `EvaluateCauchyRefractiveIndexRGB` & `TCastleVulkanPipelineBinaryManager` | Phase 53 (COMPLETED) |
| **High-Level `TCastleRenderOptions` & `TCastleViewport` Next-Gen Subsystem Wiring** | `TCastleRenderOptions` (`SpecularAntiAliasing`, `DualQuaternionSkinning`, `GpuDrivenMeshletCulling`, `TransparencyMode`, `ShadowMapSystemMode`), `BuildShapeRHIPushConstants` & `TCastleViewport.ExecuteVulkanViewportSubsystems` / `ExecuteSceneRenderOptionsSubsystems` / `ExecuteAllScenesRenderOptionsSubsystems` | Phases 54, 58, 59, 60, 61 (COMPLETED) |
| **Native Window Surface (`VkSurfaceKHR`) Creation Across All OS Backends** | `TVulkanNativeSurfaceDesc`, `CreateVulkanSurfaceFromNativeDesc` & `TCastleWindow.BuildVulkanNativeSurfaceDesc` / `CreateVulkanSurface` / `InitializeVulkanRHIDeviceIfNeeded` (Win32, X11, Wayland, Android, Metal/MoltenVK, Switch) | Phase 55 (COMPLETED) |
| **Full End-to-End `TCastleContainer` / `TCastleViewport` / `TCastleScene` 3D & 2D Rendering in Pure Vulkan RHI Mode (`GLFeatures = nil`)** | `TRenderer.UploadSceneUniformBlockToRHI` / `EnsureRHISceneDescriptorSet` / `BuildShapePipelineDesc` / `GetOrCreateShapePipeline`, `TShapeCache.UploadMaterialBlock` / `BindMaterialTexturesToDescriptorSet` / `EnsureRHIShaders` / `RHIMaterialDescriptorSet` / `RHISkinningDescriptorSet`, `TX3DRendererShape.UploadRHIMaterialToCache` / `ExtractRHIMaterialTextures`, `TCastleVulkanBindlessTextureManager.RegisterOrUpdateMaterial` / `FlushMaterialTableToSSBO`, `EnsureBatch2DRenderer`, `TDrawableImage.DrawNoBatch`, `DrawPrimitive2D`, `TCastleRenderUnlitMesh`, `TBackgroundRenderer`, `TGLShadowVolumeRenderer`, `TOcclusionCullingRenderer`, `TBatchShapes`, `TMeshRenderer`, `TSkinnedRenderer`, `TCastleMask`, `TCastleText`, `TShader`, `TLightsRenderer`, `TShapesRenderer`, `TBlendingRenderer`, `TCastleScene.PrepareResources`, `TCastleViewport.RenderFromViewEverything`, `TCastleContainer.EventRender` | Phases 60–72 (COMPLETED) |


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
* [x] Validation Cleanliness: Full engine test suite (`castle_tester_standalone`, 811 total tests including 242 `TTestCastleVulkanRHI` unit tests) and all three live Vulkan examples (`examples/vulkan/vulkan_triangle`, `examples/vulkan/vulkan_sprite_batch`, `examples/vulkan/vulkan_3d_scene`) run cleanly on Linux/WSL and support `VK_LAYER_KHRONOS_validation`.
* [x] Performance Target: Batched 2D/3D RHI command recording, push constants, secondary command buffers, bindless texture indexing, extended dynamic state, GPU-driven compute frustum/distance/Hi-Z occlusion culling (`TCastleVulkanComputeCuller`), Clustered Forward+ compute light culling (`TCastleVulkanClusteredLightCuller`), Declarative Render Graph (`TRHIRenderGraph`), Compute GTAO (`TCastleVulkanGTAO`), Hi-Z SSR (`TCastleVulkanSSR`), Froxel Volumetric Fog (`TCastleVulkanVolumetricFog`), Temporal Anti-Aliasing (`TCastleVulkanTAA`), Box-Projected Reflection Probes (`TCastleVulkanReflectionProbeManager`), OBB Decal Projection (`TCastleVulkanDecalManager`), GPU Compute Particles (`TCastleVulkanComputeParticles`), Weighted Blended OIT (`TCastleVulkanWeightedBlendedOIT`), Contact Shadows (`TCastleVulkanContactShadows`), Compute Skinning & Morph Targets (`TCastleVulkanComputeSkinner`), GPU-Driven Terrain CDLOD (`TCastleVulkanTerrainCDLOD`), Atmosphere Sky-View LUT (`TCastleVulkanAtmosphereRenderer`), Gerstner Ocean Simulator (`TCastleVulkanOceanSimulator`), DDGI Octahedral Probe Grid (`TCastleVulkanDDGIGrid`), GPU Meshlet Culler (`TCastleVulkanMeshletCuller`), Virtual Shadow Maps (`TCastleVulkanVirtualShadowMap`), GPU-Driven LOD Selector (`TCastleVulkanLODSelector`), GPU Texture Streamer (`TCastleVulkanTextureStreamer`), Shadow Caster Extrusion Culler (`TCastleVulkanShadowCasterCuller`), Nanite Cluster DAG (`TCastleVulkanClusterDAG`), Lumen Global SDF & Surface Cache (`TCastleVulkanGlobalSDF`, `TCastleVulkanSurfaceCache`), ReSTIR Spatio-Temporal Reservoir Resampler (`TCastleVulkanReSTIR`), Temporal Super Resolution Upscaler (`TCastleVulkanTSRUpscaler`), Variable Rate Shading (`TCastleVulkanVRSManager`), Runtime Virtual Texturing (`TCastleVulkanRuntimeVirtualTexture`), Sparse Brick-Atlas Heterogeneous Volumes (`TCastleVulkanSparseVolumeAtlas`), GPU Breadcrumb Crash Tracker (`TCastleVulkanBreadcrumbTracker`), SVGF Spatio-Temporal Wavelet Denoiser (`TCastleVulkanSVGFDenoiser`), Hardware Ray Tracing SBT & Acceleration Structure Compaction (`TCastleVulkanShaderBindingTable`, `TCastleVulkanAccelerationStructureManager`), GPU XPBD Cloth/Hair Simulator (`TCastleVulkanXPBDSimulator`), Single-Pass Stereo Multiview & Foveated VRS Manager (`TCastleVulkanMultiviewStereoManager`), Per-Instance Custom Float4 Payload SSBO (`TCastleVulkanPerInstanceCustomData`), Neural MLP Denoiser (`TCastleVulkanNeuralDenoiser`), Programmable MSAA Sample Locations (`TCastleVulkanProgrammableSampleLocations`), GPU Parallel Prefix-Sum Stream Compactor (`TCastleVulkanStreamCompactor`), 3D Voxel Cone Tracer (`TCastleVulkanVoxelConeTracer`), GPU Indirect Material Binner (`TCastleVulkanMaterialBinner`), and `vkCmdDrawIndexedIndirect` / `vkCmdDrawIndexedIndirectCount` / `vkCmdDispatchIndirect` minimize CPU driver overhead.
