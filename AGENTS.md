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
