# `spv2pas` — Binary SPIR-V (`*.spv`) to Generated Pascal Include Converter

Packs the pre-compiled binary SPIR-V modules in `src/base_rendering/vulkan/spirv/*.spv` into `src/base_rendering/vulkan/generated-pascal/castleinternalvulkanspirv_blobs.inc` (following the same pattern as `src/scene/glsl/generated-pascal/*.inc`), keeping handwritten Pascal units free of hardcoded SPIR-V hex arrays.

## Usage

Run from the repository root:

```bash
fpc -Mobjfpc -Sh tools/internal/generate_vulkan_spirv/spv2pas.dpr
./tools/internal/generate_vulkan_spirv/spv2pas \
  src/base_rendering/vulkan/spirv \
  src/base_rendering/vulkan/generated-pascal/castleinternalvulkanspirv_blobs.inc
```

At runtime, `TCastleShaderCompiler` can also load `.spv` binaries directly from an external directory when `CASTLE_VULKAN_SPIRV_DIR=/path/to/spirv` is set.
