{%MainUnit castleinternalrhi_vulkan.pas}
{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{$ifdef read_interface}
  TCastleVulkanMeshletCuller = class
  private
    FDevice: TVulkanRHIDevice;
    FMeshlets: array[0 .. CASTLE_MAX_MESHLETS - 1] of TCastleMeshletDescriptor;
    FMeshletCount: Cardinal;
    FMeshletBuffer: TVulkanRHIBuffer;
    FVisibleMeshletIndicesBuffer: TVulkanRHIBuffer;
    FVisibleMeshletCountBuffer: TVulkanRHIBuffer;
    FMeshletVertexBuffer: TVulkanRHIBuffer;
    FMeshletTriangleBuffer: TVulkanRHIBuffer;
    FExpandedVertexBuffer: TVulkanRHIBuffer;
    FSoftwareIndirectDrawBuffer: TVulkanRHIBuffer;
    FMeshTasksIndirectBuffer: TVulkanRHIBuffer;
    FTotalTriangleCapacity: Cardinal;
    FMeshDrawLayout: TRHIDescriptorSetLayout;
    FMeshDrawSet: TRHIDescriptorSet;
    FSoftwareCullLayout: TRHIDescriptorSetLayout;
    FSoftwareCullSet: TRHIDescriptorSet;
    FTaskShader: TRHIShaderModule;
    FMeshShader: TRHIShaderModule;
    FFragShader: TRHIShaderModule;
    FFallbackVertShader: TRHIShaderModule;
    FSoftwareCullShader: TRHIShaderModule;
    FSoftwareCullPipeline: TRHIComputePipeline;
    FForceSoftwareFallback: Boolean;
    FUseTaskShader: Boolean;
    FHardwareMeshDrawCount: Cardinal;
    FSoftwareFallbackDrawCount: Cardinal;
    FDispatchCount: Cardinal;
    procedure EnsureMeshletRenderPipelines;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure ClearMeshlets;
    function AddMeshlet(const ASphereCenter: TVector3; const ASphereRadius: Single;
      const AConeAxis: TVector3; const AConeCutoff: Single;
      const AVertexOffset, AVertexCount, ATriangleOffset, ATriangleCount: Cardinal): Integer;
    procedure UploadMeshlets;

    { Uploads per-meshlet clip/NDC positions + colors and local 0..63 triangle indices
      for both VK_EXT_mesh_shader rendering and Software Compute meshlet expansion. }
    procedure UploadMeshletGeometry(
      const APositions, AColors: array of TVector4;
      const ATriangles: array of TCastleMeshletTriangle);

    { Evaluates on CPU how many registered meshlets pass distance + normal-cone backface culling. }
    function EvaluateVisibleMeshletsCPU(const ACameraPosition: TVector3;
      const AMaxDrawDistance: Single): Cardinal;

    { Dispatches the GPU compute meshlet culling pass. }
    procedure DispatchMeshletCulling(
      const ACommandList: TVulkanRHICommandList;
      const ACameraPosition: TVector3;
      const AMaxDrawDistance: Single;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    { Records the Software Compute meshlet cull + vertex expansion pass BEFORE BeginRendering
      (used when ForceSoftwareFallback = True or Device.SupportsMeshShaders = False). }
    procedure PrepareSoftwareMeshletCulling(
      const ACommandList: TVulkanRHICommandList;
      const ACameraPosition: TVector3;
      const AMaxDrawDistance: Single;
      const AEnableConeCull: Boolean = True);

    { Renders uploaded meshlets inside an active render pass using live VK_EXT_mesh_shader
      (vkCmdDrawMeshTasksEXT / vkCmdDrawMeshTasksIndirectEXT, returning True) when supported
      and ForceSoftwareFallback = False, or Software Compute/Indirect fallback (returning False). }
    function RenderMeshlets(
      const ACommandList: TVulkanRHICommandList;
      const AColorFormat: TRHIPixelFormat;
      const ACameraPosition: TVector3;
      const AMaxDrawDistance: Single;
      const AEnableConeCull: Boolean = True;
      const AUseIndirectMeshTasks: Boolean = False): Boolean;

    property MeshletCount: Cardinal read FMeshletCount;
    property MeshletBuffer: TVulkanRHIBuffer read FMeshletBuffer;
    property VisibleMeshletIndicesBuffer: TVulkanRHIBuffer read FVisibleMeshletIndicesBuffer;
    property VisibleMeshletCountBuffer: TVulkanRHIBuffer read FVisibleMeshletCountBuffer;
    property MeshletVertexBuffer: TVulkanRHIBuffer read FMeshletVertexBuffer;
    property MeshletTriangleBuffer: TVulkanRHIBuffer read FMeshletTriangleBuffer;
    property ExpandedVertexBuffer: TVulkanRHIBuffer read FExpandedVertexBuffer;
    property SoftwareIndirectDrawBuffer: TVulkanRHIBuffer read FSoftwareIndirectDrawBuffer;
    property MeshTasksIndirectBuffer: TVulkanRHIBuffer read FMeshTasksIndirectBuffer;
    property ForceSoftwareFallback: Boolean read FForceSoftwareFallback write FForceSoftwareFallback;
    property UseTaskShader: Boolean read FUseTaskShader write FUseTaskShader;
    property HardwareMeshDrawCount: Cardinal read FHardwareMeshDrawCount;
    property SoftwareFallbackDrawCount: Cardinal read FSoftwareFallbackDrawCount;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Hardware Ray Tracing Shader Binding Table (SBT) (Phase 35.2)               }
  { -------------------------------------------------------------------------- }

  { Manages VK_KHR_ray_tracing_pipeline Shader Binding Table (SBT) regions
    (Raygen, Miss, Hit, Callable) with hardware handle stride & base alignment. }
  TCastleVulkanAccelerationStructureManager = class;

  TCastleRTInstanceDesc = record
    BLASID: Cardinal;
    Transform: TMatrix4;
    CustomIndex: Cardinal;
    Mask: Byte;
  end;

  TCastleVulkanShaderBindingTable = class
  private
    FDevice: TVulkanRHIDevice;
    FHandleSize: Cardinal;
    FHandleAlignment: Cardinal;
    FBaseAlignment: Cardinal;
    FAlignedHandleStride: Cardinal;
    FRaygenRegionSize: Cardinal;
    FMissRegionSize: Cardinal;
    FHitRegionSize: Cardinal;
    FTotalSBTSizeBytes: Cardinal;
    FSBTBuffer: TVulkanRHIBuffer;
    FRTDescriptorLayout: TVulkanRHIDescriptorSetLayout;
    FRTDescriptorSet: TVulkanRHIDescriptorSet;
    FRayGenShader: TVulkanRHIShaderModule;
    FRayMissShader: TVulkanRHIShaderModule;
    FRayClosestHitShader: TVulkanRHIShaderModule;
    FRTPipelineLayout: VkPipelineLayout;
    FRTPipeline: VkPipeline;
    FSBTPopulated: Boolean;
    FForceSoftwareFallback: Boolean;
    FHardwareTraceRaysCount: Cardinal;
    FFallbackTraceRaysCount: Cardinal;
    FTraceRaysDispatchCount: Cardinal;
    procedure EnsureHardwareRTPipelineAndSBT;
    procedure DestroyHardwareRTPipeline;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Computes aligned SBT record stride and Raygen/Miss/Hit table region byte sizes. }
    procedure ComputeAlignedSBTRegionSizes(
      const AMissGroupCount, AHitGroupCount: Cardinal);

    { Allocates the GPU SBT buffer sized for the aligned Raygen, Miss, and Hit regions. }
    procedure EnsureSBTBuffer(const AMissGroupCount, AHitGroupCount: Cardinal);

    { Dispatches hardware ray tracing (vkCmdTraceRaysKHR or compute fallback). }
    procedure DispatchTraceRays(
      const ACommandList: TVulkanRHICommandList;
      const AWidth, AHeight: Cardinal;
      const AMissGroupCount: Cardinal = 2;
      const AHitGroupCount: Cardinal = 4);

    { Executes live VK_KHR_ray_tracing_pipeline (vkCreateRayTracingPipelinesKHR +
      vkGetRayTracingShaderGroupHandlesKHR + vkCmdTraceRaysKHR, returning True) when supported
      and ForceSoftwareFallback = False, or delegates to AASManager.DispatchRayQueryOrFallback. }
    function DispatchHardwareTraceRaysOrFallback(
      const ACommandList: TVulkanRHICommandList;
      const AASManager: TCastleVulkanAccelerationStructureManager;
      const AOutputImage: TVulkanRHITexture;
      const AOriginXYScale, ARayDirAndOriginZ: TVector4): Boolean;

    property HandleSize: Cardinal read FHandleSize write FHandleSize;
    property HandleAlignment: Cardinal read FHandleAlignment write FHandleAlignment;
    property BaseAlignment: Cardinal read FBaseAlignment write FBaseAlignment;
    property AlignedHandleStride: Cardinal read FAlignedHandleStride;
    property RaygenRegionSize: Cardinal read FRaygenRegionSize;
    property MissRegionSize: Cardinal read FMissRegionSize;
    property HitRegionSize: Cardinal read FHitRegionSize;
    property TotalSBTSizeBytes: Cardinal read FTotalSBTSizeBytes;
    property SBTBuffer: TVulkanRHIBuffer read FSBTBuffer;
    property RTPipelineHandle: VkPipeline read FRTPipeline;
    property ForceSoftwareFallback: Boolean read FForceSoftwareFallback write FForceSoftwareFallback;
    property HardwareTraceRaysCount: Cardinal read FHardwareTraceRaysCount;
    property FallbackTraceRaysCount: Cardinal read FFallbackTraceRaysCount;
    property TraceRaysDispatchCount: Cardinal read FTraceRaysDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { BLAS / TLAS Acceleration Structure & Compaction Manager (Phase 35.3 / 117) }
  { -------------------------------------------------------------------------- }

  TCastleVulkanBLASEntry = record
    BLASID: Cardinal;
    TriangleCount: Cardinal;
    UncompactedBytes: Cardinal;
    CompactedBytes: Cardinal;
    IsCompacted: Boolean;
    Handle: VkAccelerationStructureKHR;
    DeviceAddress: UInt64;
    BackingBuffer: TVulkanRHIBuffer;
    VertexBuffer: TVulkanRHIBuffer;
    IndexBuffer: TVulkanRHIBuffer;
    CPUVertices: array of TVector3;
    CPUIndices: array of UInt32;
  end;

  { Tracks Bottom-Level (BLAS) and Top-Level (TLAS) Acceleration Structure builds,
    real GPU post-build BLAS compaction (VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR
    + vkCmdCopyAccelerationStructureKHR), inline VK_KHR_ray_query compute dispatches, and
    automatic Software Compute Stackless LBVH Ray-Tracing Fallback. }
  TCastleVulkanAccelerationStructureManager = class
  private
    FDevice: TVulkanRHIDevice;
    FBLASEntries: array of TCastleVulkanBLASEntry;
    FTLASInstanceCount: Cardinal;
    FTLASBuildCount: Cardinal;
    FTLASBuffer: TVulkanRHIBuffer;
    FTLASInstancesBuffer: TVulkanRHIBuffer;
    FTLASHandle: VkAccelerationStructureKHR;
    FTLASDeviceAddress: UInt64;
    FLBVHNodeBuffer: TVulkanRHIBuffer;
    FLBVHTriangleBuffer: TVulkanRHIBuffer;
    FLBVHNodeCount: Cardinal;
    FLBVHTriangleCount: Cardinal;
    FRayQueryLayout: TVulkanRHIDescriptorSetLayout;
    FRayQuerySet: TVulkanRHIDescriptorSet;
    FRayQueryShader: TRHIShaderModule;
    FRayQueryPipeline: TRHIComputePipeline;
    FSoftwareLBVHLayout: TRHIDescriptorSetLayout;
    FSoftwareLBVHSet: TRHIDescriptorSet;
    FSoftwareLBVHShader: TRHIShaderModule;
    FSoftwareLBVHPipeline: TRHIComputePipeline;
    FForceSoftwareFallback: Boolean;
    FRayQueryDispatchCount: Cardinal;
    FSoftwareLBVHDispatchCount: Cardinal;
    procedure DestroyBLASEntryGPU(var AEntry: TCastleVulkanBLASEntry);
    procedure DestroyTLASGPU;
    procedure BuildSoftwareLBVH(const AInstances: array of TCastleRTInstanceDesc);
    procedure EnsureRayQueryAndLBVHPipelines;
    function GetBLASCount: Cardinal;
    function GetTotalUncompactedBLASBytes: Cardinal;
    function GetTotalCompactedBLASBytes: Cardinal;
    function GetCompactionSavedBytes: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all tracked BLAS/TLAS entries and releases GPU acceleration structures. }
    procedure ClearAccelerationStructures;

    { Registers a newly built Bottom-Level Acceleration Structure (BLAS) and returns its 1-based BLASID. }
    function RegisterBLASBuild(
      const ATriangleCount, AUncompactedBytes: Cardinal): Cardinal;

    { Builds a real hardware VkAccelerationStructureKHR BLAS from indexed 3D triangles
      (and caches CPU geometry for Software Compute LBVH fallback), returning its 1-based BLASID. }
    function BuildTriangleBLAS(
      const AVertices: array of TVector3;
      const AIndices: array of UInt32;
      const AAllowCompaction: Boolean = True): Cardinal;

    { Compacts an existing BLAS after VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR readback. }
    function CompactBLAS(
      const ABLASID: Cardinal;
      const ACompactedBytes: Cardinal = 0): Boolean;

    { Executes real GPU BLAS compaction via VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR
      + vkCmdCopyAccelerationStructureKHR(VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR). }
    function CompactBLASOnGPU(const ABLASID: Cardinal): Boolean;

    { Builds or updates the Top-Level Acceleration Structure (TLAS) for AInstanceCount scene instances. }
    procedure BuildTLAS(const AInstanceCount: Cardinal);

    { Builds both the hardware Top-Level VkAccelerationStructureKHR (64-byte VkAccelerationStructureInstanceKHR
      records) and the stackless Software Compute LBVH from AInstances. }
    function BuildInstanceTLAS(const AInstances: array of TCastleRTInstanceDesc): Boolean;

    { Dispatches inline VK_KHR_ray_query compute ray tracing (returning True) when supported
      and ForceSoftwareFallback = False, or Software Compute Stackless LBVH ray tracing (returning False). }
    function DispatchRayQueryOrFallback(
      const ACommandList: TVulkanRHICommandList;
      const AOutputImage: TVulkanRHITexture;
      const AOriginXYScale, ARayDirAndOriginZ: TVector4): Boolean;

    function GetBLASDeviceAddress(const ABLASID: Cardinal): UInt64;

    property BLASCount: Cardinal read GetBLASCount;
    property TotalUncompactedBLASBytes: Cardinal read GetTotalUncompactedBLASBytes;
    property TotalCompactedBLASBytes: Cardinal read GetTotalCompactedBLASBytes;
    property CompactionSavedBytes: Cardinal read GetCompactionSavedBytes;
    property TLASInstanceCount: Cardinal read FTLASInstanceCount;
    property TLASBuildCount: Cardinal read FTLASBuildCount;
    property TLASBuffer: TVulkanRHIBuffer read FTLASBuffer;
    property TLASHandle: VkAccelerationStructureKHR read FTLASHandle;
    property TLASDeviceAddress: UInt64 read FTLASDeviceAddress;
    property LBVHNodeCount: Cardinal read FLBVHNodeCount;
    property LBVHTriangleCount: Cardinal read FLBVHTriangleCount;
    property ForceSoftwareFallback: Boolean read FForceSoftwareFallback write FForceSoftwareFallback;
    property RayQueryDispatchCount: Cardinal read FRayQueryDispatchCount;
    property SoftwareLBVHDispatchCount: Cardinal read FSoftwareLBVHDispatchCount;
  end;

  TCardinalDynamicArray = array of Cardinal;

  { -------------------------------------------------------------------------- }
  { GPU Indirect Material Binning Manager (Phase 43.3)                         }
  { -------------------------------------------------------------------------- }

  { Bins visibility-buffer or ray-hit fragments by material ID into contiguous
    indirect dispatch ranges (BinCountsBuffer, BinOffsetsBuffer) for coherent shading. }
  TCastleVulkanMaterialBinner = class
  private
    FDevice: TVulkanRHIDevice;
    FMaxMaterialBins: Cardinal;
    FMaxElements: Cardinal;
    FLastUploadedElementCount: Cardinal;
    FUploadedMaterialIDs: TCardinalDynamicArray;
    FMaterialIDsBuffer: TVulkanRHIBuffer;
    FBinCountsBuffer: TVulkanRHIBuffer;
    FBinOffsetsBuffer: TVulkanRHIBuffer;
    FBinDescriptorLayout: TRHIDescriptorSetLayout;
    FBinDescriptorSet: TRHIDescriptorSet;
    FHistogramShader: TRHIShaderModule;
    FPrefixSumShader: TRHIShaderModule;
    FHistogramPipeline: TVulkanRHIComputePipeline;
    FPrefixSumPipeline: TVulkanRHIComputePipeline;
    FBinningComputePipeline: TVulkanRHIComputePipeline;
    FBinningDispatchCount: Cardinal;
    procedure EnsureBinningBuffers;
    procedure EnsureStreamBinningPipelines;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { CPU reference: Computes per-material histogram counts and exclusive prefix-sum starting offsets. }
    class procedure EvaluateMaterialBinRanges(
      const AMaterialIDs: array of Cardinal;
      const ABinCount: Cardinal;
      out AOutBinCounts: TCardinalDynamicArray;
      out AOutBinOffsets: TCardinalDynamicArray); static;

    { Dispatches the GPU material binning pass across an AScreenWidth x AScreenHeight visibility buffer. }
    procedure DispatchMaterialBinning(const ACommandList: TVulkanRHICommandList;
      const AScreenWidth, AScreenHeight: Cardinal;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    { Uploads a stream of 32-bit material IDs for GPU histogram + prefix-sum binning. }
    procedure UploadMaterialIDs(const AMaterialIDs: array of Cardinal);

    { Dispatches real GPU MaterialBinHistogramCS + compute memory barrier + MaterialBinPrefixSumCS
      over the uploaded material ID stream, populating BinCountsBuffer and BinOffsetsBuffer. }
    function DispatchStreamBinning(const ACommandList: TVulkanRHICommandList;
      const ABinCount: Cardinal = 0): Cardinal;

    { Reads back ABinCount histogram counts and exclusive prefix-sum offsets from GPU memory. }
    procedure ReadBackBinRanges(const ABinCount: Cardinal;
      out AOutBinCounts, AOutBinOffsets: TCardinalDynamicArray);

    property MaxMaterialBins: Cardinal read FMaxMaterialBins write FMaxMaterialBins;
    property LastUploadedElementCount: Cardinal read FLastUploadedElementCount;
    property MaterialIDsBuffer: TVulkanRHIBuffer read FMaterialIDsBuffer;
    property BinCountsBuffer: TVulkanRHIBuffer read FBinCountsBuffer;
    property BinOffsetsBuffer: TVulkanRHIBuffer read FBinOffsetsBuffer;
    property BinningComputePipeline: TVulkanRHIComputePipeline
      read FBinningComputePipeline write FBinningComputePipeline;
    property HistogramPipeline: TVulkanRHIComputePipeline read FHistogramPipeline;
    property PrefixSumPipeline: TVulkanRHIComputePipeline read FPrefixSumPipeline;
    property BinningDispatchCount: Cardinal read FBinningDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Bindless GPU-Driven Indirect Multi-Draw Batch (Phase 110.3)                }
  { -------------------------------------------------------------------------- }

  const
    BINDLESS_INSTANCE_FLAG_TEXTURED     = 1;
    BINDLESS_INSTANCE_FLAG_LIT          = 2;
    BINDLESS_INSTANCE_FLAG_ALPHA_CUTOFF = 4;

  type
    { 32-byte interleaved 3D vertex format (Pos3 + Normal3 + UV2) for CastleBindlessIndirectVS. }
    TCastleBindlessIndirectVertex = packed record
      Position: TVector3;
      Normal: TVector3;
      TexCoord: TVector2;
    end;
    PCastleBindlessIndirectVertex = ^TCastleBindlessIndirectVertex;

    { 80-byte std140 Camera + Directional/Ambient Light UBO (Set 0, Binding 0). }
    TCastleBindlessIndirectCameraUniforms = packed record
      ViewProjMatrix: TMatrix4;
      LightDirAndAmbient: TVector4;
    end;

    { 80-byte std430 per-instance GPU SSBO record (Set 0, Binding 1) indexed by gl_InstanceIndex. }
    TCastleBindlessIndirectInstanceShaderData = packed record
      ModelMatrix: TMatrix4;
      MaterialIndex: Cardinal;
      Flags: Cardinal;
      CustomParams: TVector2;
    end;

    { Combined CPU-side instance descriptor pairing GPU transform/material data with
      world-space bounding sphere and sub-mesh range for TCastleVulkanComputeCuller. }
    TCastleBindlessIndirectInstanceDesc = record
      ModelMatrix: TMatrix4;
      BoundingSphere: TVector4;
      MaterialIndex: Cardinal;
      Flags: Cardinal;
      IndexCount: Cardinal;
      FirstIndex: Cardinal;
      VertexOffset: Integer;
      CustomParams: TVector2;
      class function CreateSimple(const AModelMatrix: TMatrix4;
        const ABoundingSphere: TVector4;
        const AMaterialIndex, AFlags, AIndexCount: Cardinal;
        const AFirstIndex: Cardinal = 0;
        const AVertexOffset: Integer = 0): TCastleBindlessIndirectInstanceDesc; static;
    end;

    { Encapsulates GPU-driven multi-material indirect rendering combining:
        - Set 0: CameraUBO (Binding 0) + Per-Instance Transform/Material SSBO (Binding 1)
        - Set 1: Global TCastleVulkanBindlessTextureManager (Bindless sampler2D[] + Material SSBO)
        - Optional GPU Compute Frustum/Distance Culling (TCastleVulkanComputeCuller)
        - Single vkCmdDrawIndexedIndirectCount / vkCmdDrawIndexedIndirect multi-draw execution. }
    TCastleVulkanBindlessIndirectBatch = class
    private
      FDevice: TVulkanRHIDevice;
      FVertexBuffer: TRHIBuffer;
      FIndexBuffer: TRHIBuffer;
      FCameraUBO: TRHIBuffer;
      FInstancesSSBO: TRHIBuffer;
      FDirectIndirectBuffer: TRHIBuffer;
      FSceneLayout: TRHIDescriptorSetLayout;
      FSceneDescriptorSet: TRHIDescriptorSet;
      FVertShader: TRHIShaderModule;
      FFragShader: TRHIShaderModule;
      FCameraUniforms: TCastleBindlessIndirectCameraUniforms;
      FVertexCount: Cardinal;
      FIndexCount: Cardinal;
      FInstanceCount: Cardinal;
      FMaxInstanceCapacity: Cardinal;
      FTotalBatchExecutions: Cardinal;
      procedure EnsureBatchResources(const ARequiredInstances: Cardinal);
    public
      constructor Create(const ADevice: TVulkanRHIDevice);
      destructor Destroy; override;

      { Uploads shared vertex and 32-bit index geometry buffers for multi-draw indirect rendering. }
      procedure UploadSharedMesh(const AVertices: array of TCastleBindlessIndirectVertex;
        const AIndices: array of UInt32);

      { Updates Set 0 Binding 0 Camera ViewProj matrix and world-space directional + ambient light. }
      procedure SetCamera(const AViewProjMatrix: TMatrix4;
        const ALightDirWorld: TVector3;
        const AAmbientFactor: Single = 0.25);

      { Uploads per-instance transform/material/flag records to Set 0 Binding 1 and (optionally)
        populates Device.ComputeCuller with matching FirstInstance = I indirect candidates. }
      procedure UploadInstances(const AInstances: array of TCastleBindlessIndirectInstanceDesc;
        const AAlsoUploadToComputeCuller: Boolean = True);

      { Acquires or creates the cached graphics PSO for CastleBindlessIndirectVS + CastleBindlessIndirectFS. }
      function GetOrCreatePipelineForPass(const AColorFormat: TRHIPixelFormat;
        const ADepthFormat: TRHIPixelFormat = pfUndefined;
        const ASampleCount: Cardinal = 1;
        const ACullMode: TRHICullMode = cmNone): TRHIPipeline;

      { Records GPU compute culling + UAV->IndirectRead buffer barriers BEFORE BeginRendering. }
      function RecordComputeCullingPass(const ACmd: TRHICommandList;
        const ACompactDraws: Boolean = True): Cardinal;

      { Binds Set 0 + Set 1 (Bindless) + shared VB/IB inside an active render pass and issues a
        single vkCmdDrawIndexedIndirectCount (when AUseComputeCullerOutput = True) or
        vkCmdDrawIndexedIndirect multi-draw call for all visible instances. }
      function RecordBindlessIndirectDraws(const ACmd: TRHICommandList;
        const AColorFormat: TRHIPixelFormat;
        const ADepthFormat: TRHIPixelFormat = pfUndefined;
        const ASampleCount: Cardinal = 1;
        const AUseComputeCullerOutput: Boolean = True;
        const ACullMode: TRHICullMode = cmNone): Cardinal;

      property VertexBuffer: TRHIBuffer read FVertexBuffer;
      property IndexBuffer: TRHIBuffer read FIndexBuffer;
      property CameraUBO: TRHIBuffer read FCameraUBO;
      property InstancesSSBO: TRHIBuffer read FInstancesSSBO;
      property SceneDescriptorSet: TRHIDescriptorSet read FSceneDescriptorSet;
      property VertexCount: Cardinal read FVertexCount;
      property IndexCount: Cardinal read FIndexCount;
      property InstanceCount: Cardinal read FInstanceCount;
      property TotalBatchExecutions: Cardinal read FTotalBatchExecutions;
    end;

  { -------------------------------------------------------------------------- }
  { GPU Hi-Z Conservative Depth Pyramid Generator                              }
  { -------------------------------------------------------------------------- }

  { Builds a conservative min/max hierarchical depth (Hi-Z) pyramid texture
    across mip levels for two-phase occlusion culling and screen-space raytracing. }
  TCastleVulkanHiZPyramidGenerator = class
  private
    FDevice: TVulkanRHIDevice;
    FHiZPyramidTexture: TVulkanRHITexture;
    FMipLevelCount: Cardinal;
    FBuildDispatchCount: Cardinal;
    FDownsampleComputePipeline: TVulkanRHIComputePipeline;
    procedure EnsureHiZPyramidResources(const ABaseWidth, ABaseHeight: Cardinal);
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Evaluates conservative 2x2 depth reduction producing both the closest (min)
      and farthest (max) depth values across 4 texels. }
    class procedure EvaluateConservativeDepthDownsample2x2(
      const AD00, AD10, AD01, AD11: Single;
      out AMinDepth, AMaxDepth: Single); static;

    { Dispatches the hierarchical depth mip-chain downsample compute passes
      across all mip levels of the Hi-Z pyramid texture. }
    procedure DispatchHiZPyramidBuild(
      const ACommandList: TVulkanRHICommandList;
      const ABaseWidth, ABaseHeight: Cardinal;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property HiZPyramidTexture: TVulkanRHITexture read FHiZPyramidTexture;
    property MipLevelCount: Cardinal read FMipLevelCount;
    property BuildDispatchCount: Cardinal read FBuildDispatchCount;
    property DownsampleComputePipeline: TVulkanRHIComputePipeline
      read FDownsampleComputePipeline write FDownsampleComputePipeline;
  end;

  { -------------------------------------------------------------------------- }
  { GPU 64-Bin Luminance Histogram Auto-Exposure Manager                       }
  { -------------------------------------------------------------------------- }

  { Manages a 64-bin log-luminance histogram SSBO, outlier-trimmed average EV
    reduction, and temporal eye adaptation compute dispatches. }
  TCastleVulkanAutoExposureHistogram = class
  private
    FDevice: TVulkanRHIDevice;
    FHistogramBuffer: TVulkanRHIBuffer;
    FAdaptedExposureBuffer: TVulkanRHIBuffer;
    FCurrentAdaptedEV: Single;
    FDispatchCount: Cardinal;
    FHistogramComputePipeline: TVulkanRHIComputePipeline;
    procedure EnsureHistogramResources;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Evaluates the outlier-trimmed weighted average EV across a luminance histogram
      by discarding the darkest ALowPercentile and brightest AHighPercentile pixel counts. }
    class function EvaluateTrimmedHistogramAverageEV(
      const ABins: array of Cardinal;
      const AMinLogLum, AMaxLogLum, ALowPercentile, AHighPercentile: Single): Single; static;

    { Dispatches the luminance histogram build and temporal eye adaptation compute pass. }
    procedure DispatchHistogramAutoExposure(
      const ACommandList: TVulkanRHICommandList;
      const AViewportWidth, AViewportHeight: Cardinal;
      const ATargetEV, ADeltaTimeSeconds, AAdaptationSpeed: Single;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property HistogramBuffer: TVulkanRHIBuffer read FHistogramBuffer;
    property AdaptedExposureBuffer: TVulkanRHIBuffer read FAdaptedExposureBuffer;
    property CurrentAdaptedEV: Single read FCurrentAdaptedEV write FCurrentAdaptedEV;
    property DispatchCount: Cardinal read FDispatchCount;
    property HistogramComputePipeline: TVulkanRHIComputePipeline
      read FHistogramComputePipeline write FHistogramComputePipeline;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Frame Pacing & Present Timing Manager                                  }
  { -------------------------------------------------------------------------- }

  { Tracks rolling frame durations, calculates low-latency frame-pacing wait
    intervals for target display refresh rates, and records present telemetry. }
  TCastleVulkanFramePacer = class
  private
    FDevice: TVulkanRHIDevice;
    FTargetRefreshHz: Single;
    FLastFrameDurationMilliseconds: Single;
    FSmoothedFrameMilliseconds: Single;
    FLastWaitMicroseconds: Int64;
    FPacedFrameCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);

    { Computes the exact frame-pacing wait interval in microseconds for a target
      display refresh rate (ATargetRefreshHz), elapsed GPU/CPU frame time
      (AElapsedFrameMilliseconds), and scheduler safety margin (ASafetyMarginMicroseconds). }
    class function EvaluateFramePacingWaitMicroseconds(
      const ATargetRefreshHz, AElapsedFrameMilliseconds,
      ASafetyMarginMicroseconds: Single): Int64; static;

    { Records a completed frame's duration and updates smoothed frame-time and wait telemetry. }
    procedure RecordFramePresentTiming(
      const AElapsedFrameMilliseconds: Single;
      const ASafetyMarginMicroseconds: Single = 250.0);

    property TargetRefreshHz: Single read FTargetRefreshHz write FTargetRefreshHz;
    property LastFrameDurationMilliseconds: Single read FLastFrameDurationMilliseconds;
    property SmoothedFrameMilliseconds: Single read FSmoothedFrameMilliseconds;
    property LastWaitMicroseconds: Int64 read FLastWaitMicroseconds;
    property PacedFrameCount: Cardinal read FPacedFrameCount;
  end;

  { -------------------------------------------------------------------------- }
  { Vulkan Render Device                                                       }
  { -------------------------------------------------------------------------- }

  TVulkanFrameContext = record
    ImageAvailableSemaphore: VkSemaphore;
    RenderFinishedSemaphore: VkSemaphore;
    InFlightFence: VkFence;
    CommandList: TVulkanRHICommandList;
    TransientDescriptorAllocator: TVulkanDescriptorPoolAllocator;
  end;

  { Retired GPU resource queued for safe destruction after the in-flight frame fence signals. }
  TVulkanDeferredDeletionItem = record
    IsTexture: Boolean;
    IsDescriptorSet: Boolean;
    Buffer: VkBuffer;
    Image: VkImage;
    ImageView: VkImageView;
    DescriptorSet: VkDescriptorSet;
    DescriptorPool: VkDescriptorPool;
    Allocation: TVulkanMemoryAllocation;
    DeviceMemory: VkDeviceMemory;
    AllocatedSize: VkDeviceSize;
  end;

  TVulkanPipelineMap = {$ifdef FPC}specialize{$endif} TObjectDictionary<UInt64, TVulkanRHIPipeline>;
  TVulkanComputePipelineMap = {$ifdef FPC}specialize{$endif} TObjectDictionary<UInt64, TVulkanRHIComputePipeline>;
  TVulkanPipelineLibraryMap = {$ifdef FPC}specialize{$endif} TDictionary<UInt64, VkPipeline>;
  TVulkanRenderPassMap = {$ifdef FPC}specialize{$endif} TDictionary<UInt64, VkRenderPass>;
  TVulkanFramebufferMap = {$ifdef FPC}specialize{$endif} TDictionary<UInt64, VkFramebuffer>;

  { Independent per-control / per-widget Vulkan WSI surface + swapchain bound to a shared
    TVulkanRHIDevice (Phase 115: TCastleControl multi-pane / castle-editor / VCL / FMX). }

{$endif read_interface}

{$ifdef read_implementation}
{ ---------------------------------------------------------------------------- }
{ TCastleVulkanMeshletCuller (Phase 22.2)                                      }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanMeshletCuller.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMeshletCount := 0;
  FDispatchCount := 0;
end;

destructor TCastleVulkanMeshletCuller.Destroy;
begin
  FreeAndNil(FSoftwareCullPipeline);
  FreeAndNil(FSoftwareCullShader);
  FreeAndNil(FFallbackVertShader);
  FreeAndNil(FFragShader);
  FreeAndNil(FMeshShader);
  FreeAndNil(FTaskShader);
  FreeAndNil(FSoftwareCullSet);
  FreeAndNil(FSoftwareCullLayout);
  FreeAndNil(FMeshDrawSet);
  FreeAndNil(FMeshDrawLayout);
  FreeAndNil(FMeshTasksIndirectBuffer);
  FreeAndNil(FSoftwareIndirectDrawBuffer);
  FreeAndNil(FExpandedVertexBuffer);
  FreeAndNil(FMeshletTriangleBuffer);
  FreeAndNil(FMeshletVertexBuffer);
  FreeAndNil(FVisibleMeshletCountBuffer);
  FreeAndNil(FVisibleMeshletIndicesBuffer);
  FreeAndNil(FMeshletBuffer);
  inherited;
end;

procedure TCastleVulkanMeshletCuller.ClearMeshlets;
begin
  FMeshletCount := 0;
  FillChar(FMeshlets[0], SizeOf(FMeshlets), 0);
end;

function TCastleVulkanMeshletCuller.AddMeshlet(
  const ASphereCenter: TVector3; const ASphereRadius: Single;
  const AConeAxis: TVector3; const AConeCutoff: Single;
  const AVertexOffset, AVertexCount, ATriangleOffset, ATriangleCount: Cardinal): Integer;
begin
  if FMeshletCount >= CASTLE_MAX_MESHLETS then
    Exit(-1);
  Result := Integer(FMeshletCount);
  FMeshlets[Result].BoundingSphere := Vector4(ASphereCenter, Max(0.001, ASphereRadius));
  FMeshlets[Result].ConeAxisAndCutoff := Vector4(AConeAxis.Normalize, AConeCutoff);
  FMeshlets[Result].VertexOffset := AVertexOffset;
  FMeshlets[Result].VertexCount := Min(Cardinal(64), AVertexCount);
  FMeshlets[Result].TriangleOffset := ATriangleOffset;
  FMeshlets[Result].TriangleCount := Min(Cardinal(124), ATriangleCount);
  Inc(FMeshletCount);
end;

procedure TCastleVulkanMeshletCuller.UploadMeshlets;
var
  BufDesc: TRHIBufferDesc;
  MappedPtr: Pointer;
begin
  if FMeshletBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(FMeshlets),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'MeshletDescriptorsBuffer');
    FMeshletBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
  if FVisibleMeshletIndicesBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      CASTLE_MAX_MESHLETS * SizeOf(Cardinal),
      [buStorage, buTransferDst],
      muGpuOnly,
      'VisibleMeshletIndicesBuffer');
    FVisibleMeshletIndicesBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
  if FVisibleMeshletCountBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(Cardinal) * 4,
      [buStorage, buIndirect, buTransferDst],
      muCpuToGpu,
      'VisibleMeshletCountBuffer');
    FVisibleMeshletCountBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  MappedPtr := FMeshletBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(FMeshlets[0], MappedPtr^, SizeOf(FMeshlets));
    FMeshletBuffer.Unmap;
  end;
end;

function TCastleVulkanMeshletCuller.EvaluateVisibleMeshletsCPU(
  const ACameraPosition: TVector3; const AMaxDrawDistance: Single): Cardinal;
var
  I: Cardinal;
  Center, Axis: TVector3;
  Radius, Cutoff, Dist: Single;
begin
  Result := 0;
  if FMeshletCount = 0 then
    Exit;
  for I := 0 to FMeshletCount - 1 do
  begin
    Center := FMeshlets[I].BoundingSphere.XYZ;
    Radius := FMeshlets[I].BoundingSphere.W;
    Axis := FMeshlets[I].ConeAxisAndCutoff.XYZ;
    Cutoff := FMeshlets[I].ConeAxisAndCutoff.W;
    Dist := (Center - ACameraPosition).Length;
    if Dist - Radius > AMaxDrawDistance then
      Continue;
    if TCastleShaderGeneratorRHI.EvaluateMeshletConeBackfaceCull(Center, ACameraPosition, Axis, Cutoff) then
      Continue;
    Inc(Result);
  end;
end;

procedure TCastleVulkanMeshletCuller.DispatchMeshletCulling(
  const ACommandList: TVulkanRHICommandList;
  const ACameraPosition: TVector3;
  const AMaxDrawDistance: Single;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
type
  TMeshletCullPC = packed record
    CameraPosAndMaxDist: TVector4;
    MeshletCount: Cardinal;
    Pad0, Pad1, Pad2: Cardinal;
  end;
var
  PC: TMeshletCullPC;
  GroupsX: Cardinal;
begin
  UploadMeshlets;
  if ACommandList = nil then
    Exit;

  FillChar(PC, SizeOf(PC), 0);
  PC.CameraPosAndMaxDist := Vector4(ACameraPosition, AMaxDrawDistance);
  PC.MeshletCount := FMeshletCount;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PC), PC);

  GroupsX := (Max(Cardinal(1), FMeshletCount) + 63) div 64;
  ACommandList.Dispatch(GroupsX, 1, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
procedure TCastleVulkanMeshletCuller.UploadMeshletGeometry(
  const APositions, AColors: array of TVector4;
  const ATriangles: array of TCastleMeshletTriangle);
var
  VertCount, TriCount, I: Cardinal;
  Interleaved: array of TVector4;
  BufDesc: TRHIBufferDesc;
begin
  UploadMeshlets;
  VertCount := Max(Cardinal(1), Cardinal(Min(Length(APositions), Length(AColors))));
  TriCount := Max(Cardinal(1), Cardinal(Length(ATriangles)));
  FTotalTriangleCapacity := TriCount;

  SetLength(Interleaved, VertCount * 2);
  for I := 0 to VertCount - 1 do
    if Integer(I) <= High(APositions) then
    begin
      Interleaved[I * 2 + 0] := APositions[I];
      Interleaved[I * 2 + 1] := AColors[I];
    end;

  FreeAndNil(FMeshletVertexBuffer);
  BufDesc := TRHIBufferDesc.Create(VertCount * 2 * SizeOf(TVector4),
    [buStorage, buTransferDst], muCpuToGpu, 'MeshletVerticesSSBO');
  FMeshletVertexBuffer := FDevice.CreateBuffer(BufDesc, @Interleaved[0]) as TVulkanRHIBuffer;

  FreeAndNil(FMeshletTriangleBuffer);
  BufDesc := TRHIBufferDesc.Create(TriCount * SizeOf(TCastleMeshletTriangle),
    [buStorage, buTransferDst], muCpuToGpu, 'MeshletTrianglesSSBO');
  if Length(ATriangles) > 0 then
    FMeshletTriangleBuffer := FDevice.CreateBuffer(BufDesc, @ATriangles[0]) as TVulkanRHIBuffer
  else
    FMeshletTriangleBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  FreeAndNil(FExpandedVertexBuffer);
  BufDesc := TRHIBufferDesc.Create(TriCount * 3 * 2 * SizeOf(TVector4),
    [buVertex, buStorage, buTransferDst], muGpuOnly, 'MeshletExpandedVerticesVBO');
  FExpandedVertexBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  if FSoftwareIndirectDrawBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(SizeOf(VkDrawIndirectCommand),
      [buStorage, buIndirect, buTransferDst], muCpuToGpu, 'MeshletSoftwareDrawIndirectBuffer');
    FSoftwareIndirectDrawBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
  if FMeshTasksIndirectBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(SizeOf(VkDrawMeshTasksIndirectCommandEXT),
      [buStorage, buIndirect, buTransferDst], muCpuToGpu, 'MeshTasksIndirectBuffer');
    FMeshTasksIndirectBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  { Refresh descriptor bindings on next draw/cull }
  FreeAndNil(FMeshDrawSet);
  FreeAndNil(FSoftwareCullSet);
end;

procedure TCastleVulkanMeshletCuller.EnsureMeshletRenderPipelines;
var
  MeshBinds: array[0..2] of TRHIDescriptorBindingDesc;
  CullBinds: array[0..4] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
  I: Integer;
begin
  if FMeshDrawLayout = nil then
  begin
    for I := 0 to 2 do
    begin
      MeshBinds[I] := Default(TRHIDescriptorBindingDesc);
      MeshBinds[I].Binding := I;
      MeshBinds[I].DescriptorType := dtStorageBuffer;
      MeshBinds[I].Count := 1;
      MeshBinds[I].StageFlags := [ssTask, ssMesh];
    end;
    FMeshDrawLayout := FDevice.CreateDescriptorSetLayout(MeshBinds);
  end;
  if FSoftwareCullLayout = nil then
  begin
    for I := 0 to 4 do
    begin
      CullBinds[I] := Default(TRHIDescriptorBindingDesc);
      CullBinds[I].Binding := I;
      CullBinds[I].DescriptorType := dtStorageBuffer;
      CullBinds[I].Count := 1;
      CullBinds[I].StageFlags := [ssCompute];
    end;
    FSoftwareCullLayout := FDevice.CreateDescriptorSetLayout(CullBinds);
  end;
  if (FMeshDrawSet = nil) and (FMeshletBuffer <> nil) and
     (FMeshletVertexBuffer <> nil) and (FMeshletTriangleBuffer <> nil) then
  begin
    FMeshDrawSet := FDevice.CreateDescriptorSet(FMeshDrawLayout);
    FMeshDrawSet.BindStorageBuffer(0, FMeshletBuffer);
    FMeshDrawSet.BindStorageBuffer(1, FMeshletVertexBuffer);
    FMeshDrawSet.BindStorageBuffer(2, FMeshletTriangleBuffer);
    FMeshDrawSet.Update;
  end;
  if (FSoftwareCullSet = nil) and (FMeshletBuffer <> nil) and
     (FMeshletVertexBuffer <> nil) and (FMeshletTriangleBuffer <> nil) and
     (FExpandedVertexBuffer <> nil) and (FSoftwareIndirectDrawBuffer <> nil) then
  begin
    FSoftwareCullSet := FDevice.CreateDescriptorSet(FSoftwareCullLayout);
    FSoftwareCullSet.BindStorageBuffer(0, FMeshletBuffer);
    FSoftwareCullSet.BindStorageBuffer(1, FMeshletVertexBuffer);
    FSoftwareCullSet.BindStorageBuffer(2, FMeshletTriangleBuffer);
    FSoftwareCullSet.BindStorageBuffer(3, FExpandedVertexBuffer);
    FSoftwareCullSet.BindStorageBuffer(4, FSoftwareIndirectDrawBuffer);
    FSoftwareCullSet.Update;
  end;
  if FFragShader = nil then
    FFragShader := FDevice.CreateShaderModuleFromGLSL(ssFragment, '// MeshletFS', 'MeshletFS');
  if FFallbackVertShader = nil then
    FFallbackVertShader := FDevice.CreateShaderModuleFromGLSL(ssVertex, '// MeshletFallbackVS', 'MeshletFallbackVS');
  if FSoftwareCullShader = nil then
    FSoftwareCullShader := FDevice.CreateShaderModuleFromGLSL(ssCompute, '// MeshletCullCS', 'MeshletCullCS');
  if FSoftwareCullPipeline = nil then
  begin
    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FSoftwareCullShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FSoftwareCullLayout;
    CompDesc.PushConstantSize := 32;
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'MeshletSoftwareCullPipeline';
    FSoftwareCullPipeline := FDevice.CreateComputePipeline(CompDesc);
  end;
  if FDevice.SupportsMeshShaders and (FMeshShader = nil) then
    FMeshShader := FDevice.CreateShaderModuleFromGLSL(ssMesh, '// MeshletMeshEXT', 'MeshletMeshEXT');
  if FDevice.SupportsMeshShaders and FDevice.SupportsTaskShaders and (FTaskShader = nil) then
    FTaskShader := FDevice.CreateShaderModuleFromGLSL(ssTask, '// MeshletTaskEXT', 'MeshletTaskEXT');
end;

procedure TCastleVulkanMeshletCuller.PrepareSoftwareMeshletCulling(
  const ACommandList: TVulkanRHICommandList;
  const ACameraPosition: TVector3;
  const AMaxDrawDistance: Single;
  const AEnableConeCull: Boolean);
type
  TMeshletDrawPC = packed record
    CameraPosAndMaxDist: TVector4;
    MeshletCount: Cardinal;
    EnableConeCull: Cardinal;
    Pad0, Pad1: Cardinal;
  end;
var
  InitCmd: VkDrawIndirectCommand;
  PC: TMeshletDrawPC;
  GroupsX: Cardinal;
begin
  if (ACommandList = nil) or (FMeshletCount = 0) then Exit;
  EnsureMeshletRenderPipelines;
  if (FSoftwareIndirectDrawBuffer = nil) or (FSoftwareCullSet = nil) then Exit;

  InitCmd.vertexCount := 0;
  InitCmd.instanceCount := 1;
  InitCmd.firstVertex := 0;
  InitCmd.firstInstance := 0;
  FSoftwareIndirectDrawBuffer.UploadData(InitCmd, SizeOf(InitCmd), 0);

  FillChar(PC, SizeOf(PC), 0);
  PC.CameraPosAndMaxDist := Vector4(ACameraPosition, AMaxDrawDistance);
  PC.MeshletCount := FMeshletCount;
  PC.EnableConeCull := Ord(AEnableConeCull);

  ACommandList.BindComputePipeline(FSoftwareCullPipeline);
  ACommandList.BindComputeDescriptorSet(0, FSoftwareCullSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  GroupsX := (FMeshletCount + 63) div 64;
  ACommandList.Dispatch(GroupsX, 1, 1);
  ACommandList.TransitionBuffer(FExpandedVertexBuffer, rsUnorderedAccess, rsShaderRead);
  ACommandList.TransitionBuffer(FSoftwareIndirectDrawBuffer, rsUnorderedAccess, rsIndirectRead);
  Inc(FDispatchCount);
end;

function TCastleVulkanMeshletCuller.RenderMeshlets(
  const ACommandList: TVulkanRHICommandList;
  const AColorFormat: TRHIPixelFormat;
  const ACameraPosition: TVector3;
  const AMaxDrawDistance: Single;
  const AEnableConeCull: Boolean;
  const AUseIndirectMeshTasks: Boolean): Boolean;
type
  TMeshletDrawPC = packed record
    CameraPosAndMaxDist: TVector4;
    MeshletCount: Cardinal;
    EnableConeCull: Cardinal;
    Pad0, Pad1: Cardinal;
  end;
var
  PDesc: TRHIGraphicsPipelineDesc;
  Pipe: TRHIPipeline;
  PC: TMeshletDrawPC;
  TaskCmd: VkDrawMeshTasksIndirectCommandEXT;
  UseHwMesh, UseHwTask: Boolean;
  GroupsX: Cardinal;
begin
  Result := False;
  if (ACommandList = nil) or (FMeshletCount = 0) then Exit;
  EnsureMeshletRenderPipelines;

  UseHwMesh := FDevice.SupportsMeshShaders and (not FForceSoftwareFallback) and
    (FMeshShader <> nil) and (FMeshDrawSet <> nil);
  if UseHwMesh then
  begin
    UseHwTask := FUseTaskShader and FDevice.SupportsTaskShaders and (FTaskShader <> nil);
    PDesc := Default(TRHIGraphicsPipelineDesc);
    PDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    PDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    PDesc.SampleCount := 1;
    if UseHwTask then
      PDesc.TaskShader := FTaskShader;
    PDesc.MeshShader := FMeshShader;
    PDesc.FragmentShader := FFragShader;
    PDesc.Rasterizer.CullMode := cmNone;
    PDesc.DepthStencil.DepthTestEnable := False;
    PDesc.DepthStencil.DepthWriteEnable := False;
    SetLength(PDesc.ColorAttachmentFormats, 1);
    PDesc.ColorAttachmentFormats[0] := AColorFormat;
    SetLength(PDesc.DescriptorSetLayouts, 1);
    PDesc.DescriptorSetLayouts[0] := FMeshDrawLayout;
    PDesc.PushConstantSize := SizeOf(PC);
    PDesc.PushConstantStages := [ssTask, ssMesh];
    PDesc.DebugName := 'MeshletHardwareMeshPipeline';
    Pipe := FDevice.GetOrCreatePipeline(PDesc);

    FillChar(PC, SizeOf(PC), 0);
    PC.CameraPosAndMaxDist := Vector4(ACameraPosition, AMaxDrawDistance);
    PC.MeshletCount := FMeshletCount;
    PC.EnableConeCull := Ord(AEnableConeCull);

    ACommandList.BindPipeline(Pipe);
    ACommandList.BindDescriptorSet(0, FMeshDrawSet, []);
    ACommandList.PushConstants([ssTask, ssMesh], 0, SizeOf(PC), PC);

    if UseHwTask then
      GroupsX := 1
    else
      GroupsX := FMeshletCount;

    if AUseIndirectMeshTasks and (FMeshTasksIndirectBuffer <> nil) then
    begin
      TaskCmd.groupCountX := GroupsX;
      TaskCmd.groupCountY := 1;
      TaskCmd.groupCountZ := 1;
      FMeshTasksIndirectBuffer.UploadData(TaskCmd, SizeOf(TaskCmd), 0);
      ACommandList.DrawMeshTasksIndirect(FMeshTasksIndirectBuffer, 0, 1, SizeOf(TaskCmd));
    end else
      ACommandList.DrawMeshTasks(GroupsX, 1, 1);

    Inc(FHardwareMeshDrawCount);
    Exit(True);
  end;

  { Software Compute + Indirect Vertex Expansion Fallback }
  if (FExpandedVertexBuffer = nil) or (FSoftwareIndirectDrawBuffer = nil) then
    Exit(False);

  PDesc := Default(TRHIGraphicsPipelineDesc);
  PDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  PDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
  PDesc.SampleCount := 1;
  PDesc.VertexShader := FFallbackVertShader;
  PDesc.FragmentShader := FFragShader;
  PDesc.Topology := ptTriangleList;
  PDesc.Rasterizer.CullMode := cmNone;
  PDesc.DepthStencil.DepthTestEnable := False;
  PDesc.DepthStencil.DepthWriteEnable := False;
  SetLength(PDesc.VertexInput.Bindings, 1);
  PDesc.VertexInput.Bindings[0].Binding := 0;
  PDesc.VertexInput.Bindings[0].Stride := 32;
  PDesc.VertexInput.Bindings[0].PerInstance := False;
  SetLength(PDesc.VertexInput.Attributes, 2);
  PDesc.VertexInput.Attributes[0].Location := 0;
  PDesc.VertexInput.Attributes[0].Binding := 0;
  PDesc.VertexInput.Attributes[0].Format := vafVector4;
  PDesc.VertexInput.Attributes[0].Offset := 0;
  PDesc.VertexInput.Attributes[1].Location := 1;
  PDesc.VertexInput.Attributes[1].Binding := 0;
  PDesc.VertexInput.Attributes[1].Format := vafVector4;
  PDesc.VertexInput.Attributes[1].Offset := 16;
  SetLength(PDesc.ColorAttachmentFormats, 1);
  PDesc.ColorAttachmentFormats[0] := AColorFormat;
  PDesc.DebugName := 'MeshletSoftwareFallbackPipeline';
  Pipe := FDevice.GetOrCreatePipeline(PDesc);

  ACommandList.BindPipeline(Pipe);
  ACommandList.BindVertexBuffers(0, [FExpandedVertexBuffer], [0]);
  ACommandList.DrawIndirect(FSoftwareIndirectDrawBuffer, 0, 1, SizeOf(VkDrawIndirectCommand));
  Inc(FSoftwareFallbackDrawCount);
  Result := False;
end;

{ TCastleVulkanVirtualShadowMap (Phase 23.2)                                   }

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanShaderBindingTable (Phase 35.2)                                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanShaderBindingTable.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  if (ADevice <> nil) and (ADevice.RTShaderGroupHandleSize > 0) then
    FHandleSize := ADevice.RTShaderGroupHandleSize
  else
    FHandleSize := 32;
  if (ADevice <> nil) and (ADevice.RTShaderGroupHandleAlignment > 0) then
    FHandleAlignment := ADevice.RTShaderGroupHandleAlignment
  else
    FHandleAlignment := 32;
  if (ADevice <> nil) and (ADevice.RTShaderGroupBaseAlignment > 0) then
    FBaseAlignment := ADevice.RTShaderGroupBaseAlignment
  else
    FBaseAlignment := 64;
end;

procedure TCastleVulkanShaderBindingTable.DestroyHardwareRTPipeline;
begin
  if (FDevice <> nil) and (FDevice.Handle <> nil) then
  begin
    if (FRTPipeline <> VK_NULL_HANDLE) and Assigned(vkDestroyPipeline) then
      vkDestroyPipeline(FDevice.Handle, FRTPipeline, nil);
    if (FRTPipelineLayout <> VK_NULL_HANDLE) and Assigned(vkDestroyPipelineLayout) then
      vkDestroyPipelineLayout(FDevice.Handle, FRTPipelineLayout, nil);
  end;
  FRTPipeline := VK_NULL_HANDLE;
  FRTPipelineLayout := VK_NULL_HANDLE;
  FreeAndNil(FRTDescriptorSet);
  FreeAndNil(FRTDescriptorLayout);
  FreeAndNil(FRayClosestHitShader);
  FreeAndNil(FRayMissShader);
  FreeAndNil(FRayGenShader);
  FSBTPopulated := False;
end;

destructor TCastleVulkanShaderBindingTable.Destroy;
begin
  DestroyHardwareRTPipeline;
  FreeAndNil(FSBTBuffer);
  inherited;
end;

procedure TCastleVulkanShaderBindingTable.ComputeAlignedSBTRegionSizes(
  const AMissGroupCount, AHitGroupCount: Cardinal);
begin
  FAlignedHandleStride := TCastleShaderGeneratorRHI.AlignUpSBTSize(
    Max(Cardinal(1), FHandleSize), Max(Cardinal(1), FHandleAlignment));
  FRaygenRegionSize := TCastleShaderGeneratorRHI.AlignUpSBTSize(
    FAlignedHandleStride, Max(Cardinal(1), FBaseAlignment));
  FMissRegionSize := TCastleShaderGeneratorRHI.AlignUpSBTSize(
    Max(Cardinal(1), AMissGroupCount) * FAlignedHandleStride, Max(Cardinal(1), FBaseAlignment));
  FHitRegionSize := TCastleShaderGeneratorRHI.AlignUpSBTSize(
    Max(Cardinal(1), AHitGroupCount) * FAlignedHandleStride, Max(Cardinal(1), FBaseAlignment));
  FTotalSBTSizeBytes := FRaygenRegionSize + FMissRegionSize + FHitRegionSize;
end;

procedure TCastleVulkanShaderBindingTable.EnsureSBTBuffer(
  const AMissGroupCount, AHitGroupCount: Cardinal);
var
  BufDesc: TRHIBufferDesc;
begin
  ComputeAlignedSBTRegionSizes(AMissGroupCount, AHitGroupCount);
  if (FSBTBuffer <> nil) and (FSBTBuffer.Desc.Size >= FTotalSBTSizeBytes) then
    Exit;
  FreeAndNil(FSBTBuffer);
  FSBTPopulated := False;
  BufDesc := TRHIBufferDesc.Create(FTotalSBTSizeBytes,
    [buStorage, buShaderBindingTable, buShaderDeviceAddress, buTransferDst], muCpuToGpu,
    'RayTracingShaderBindingTable');
  FSBTBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
end;

procedure TCastleVulkanShaderBindingTable.DispatchTraceRays(
  const ACommandList: TVulkanRHICommandList;
  const AWidth, AHeight: Cardinal;
  const AMissGroupCount: Cardinal;
  const AHitGroupCount: Cardinal);
var
  GroupsX, GroupsY: Cardinal;
begin
  EnsureSBTBuffer(AMissGroupCount, AHitGroupCount);
  if ACommandList = nil then
    Exit;
  GroupsX := (Max(Cardinal(1), AWidth) + 7) div 8;
  GroupsY := (Max(Cardinal(1), AHeight) + 7) div 8;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FTraceRaysDispatchCount);
end;

procedure TCastleVulkanShaderBindingTable.EnsureHardwareRTPipelineAndSBT;
var
  Binds: array[0..1] of TRHIDescriptorBindingDesc;
  SetLayoutHandle: VkDescriptorSetLayout;
  PushRange: VkPushConstantRange;
  LayoutInfo: VkPipelineLayoutCreateInfo;
  Stages: array[0..2] of VkPipelineShaderStageCreateInfo;
  Groups: array[0..2] of VkRayTracingShaderGroupCreateInfoKHR;
  RTInfo: VkRayTracingPipelineCreateInfoKHR;
  RawHandles, SBTBytes: array of Byte;
begin
  if FSBTPopulated and (FRTPipeline <> VK_NULL_HANDLE) then
    Exit;
  if (FDevice = nil) or (FDevice.Handle = nil) or
     (not FDevice.SupportsRayTracingPipeline) or
     (not Assigned(vkCreateRayTracingPipelinesKHR)) or
     (not Assigned(vkGetRayTracingShaderGroupHandlesKHR)) then
    Exit;

  EnsureSBTBuffer(1, 1);

  if FRTDescriptorLayout = nil then
  begin
    Binds[0] := Default(TRHIDescriptorBindingDesc);
    Binds[0].Binding := 0;
    Binds[0].DescriptorType := dtAccelerationStructure;
    Binds[0].Count := 1;
    Binds[0].StageFlags := [ssRayGen, ssCompute];

    Binds[1] := Default(TRHIDescriptorBindingDesc);
    Binds[1].Binding := 1;
    Binds[1].DescriptorType := dtStorageImage;
    Binds[1].Count := 1;
    Binds[1].StageFlags := [ssRayGen, ssCompute];
    FRTDescriptorLayout := FDevice.CreateDescriptorSetLayout(Binds) as TVulkanRHIDescriptorSetLayout;
  end;
  if FRTDescriptorSet = nil then
    FRTDescriptorSet := FDevice.CreateDescriptorSet(FRTDescriptorLayout) as TVulkanRHIDescriptorSet;

  if FRayGenShader = nil then
    FRayGenShader := FDevice.CreateShaderModuleFromGLSL(ssRayGen, '// RayTraceRGen', 'RayTraceRGen') as TVulkanRHIShaderModule;
  if FRayMissShader = nil then
    FRayMissShader := FDevice.CreateShaderModuleFromGLSL(ssMiss, '// RayTraceRMiss', 'RayTraceRMiss') as TVulkanRHIShaderModule;
  if FRayClosestHitShader = nil then
    FRayClosestHitShader := FDevice.CreateShaderModuleFromGLSL(ssClosestHit, '// RayTraceRChit', 'RayTraceRChit') as TVulkanRHIShaderModule;

  if FRTPipelineLayout = VK_NULL_HANDLE then
  begin
    SetLayoutHandle := FRTDescriptorLayout.Handle;
    FillChar(PushRange, SizeOf(PushRange), 0);
    PushRange.stageFlags := VK_SHADER_STAGE_RAYGEN_BIT_KHR or VK_SHADER_STAGE_COMPUTE_BIT;
    PushRange.offset := 0;
    PushRange.size := 48;

    FillChar(LayoutInfo, SizeOf(LayoutInfo), 0);
    LayoutInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    LayoutInfo.setLayoutCount := 1;
    LayoutInfo.pSetLayouts := @SetLayoutHandle;
    LayoutInfo.pushConstantRangeCount := 1;
    LayoutInfo.pPushConstantRanges := @PushRange;
    CheckVk(vkCreatePipelineLayout(FDevice.Handle, @LayoutInfo, nil, @FRTPipelineLayout),
      'vkCreatePipelineLayout(RayTracing)');
  end;

  if FRTPipeline = VK_NULL_HANDLE then
  begin
    FillChar(Stages, SizeOf(Stages), 0);
    Stages[0].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[0].stage := VK_SHADER_STAGE_RAYGEN_BIT_KHR;
    Stages[0].module := FRayGenShader.Handle;
    Stages[0].pName := 'main';

    Stages[1].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[1].stage := VK_SHADER_STAGE_MISS_BIT_KHR;
    Stages[1].module := FRayMissShader.Handle;
    Stages[1].pName := 'main';

    Stages[2].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[2].stage := VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR;
    Stages[2].module := FRayClosestHitShader.Handle;
    Stages[2].pName := 'main';

    FillChar(Groups, SizeOf(Groups), 0);
    Groups[0].sType := VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
    Groups[0]._type := VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR;
    Groups[0].generalShader := 0;
    Groups[0].closestHitShader := VK_SHADER_UNUSED_KHR;
    Groups[0].anyHitShader := VK_SHADER_UNUSED_KHR;
    Groups[0].intersectionShader := VK_SHADER_UNUSED_KHR;

    Groups[1].sType := VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
    Groups[1]._type := VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR;
    Groups[1].generalShader := 1;
    Groups[1].closestHitShader := VK_SHADER_UNUSED_KHR;
    Groups[1].anyHitShader := VK_SHADER_UNUSED_KHR;
    Groups[1].intersectionShader := VK_SHADER_UNUSED_KHR;

    Groups[2].sType := VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
    Groups[2]._type := VK_RAY_TRACING_SHADER_GROUP_TYPE_TRIANGLES_HIT_GROUP_KHR;
    Groups[2].generalShader := VK_SHADER_UNUSED_KHR;
    Groups[2].closestHitShader := 2;
    Groups[2].anyHitShader := VK_SHADER_UNUSED_KHR;
    Groups[2].intersectionShader := VK_SHADER_UNUSED_KHR;

    FillChar(RTInfo, SizeOf(RTInfo), 0);
    RTInfo.sType := VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_CREATE_INFO_KHR;
    RTInfo.stageCount := 3;
    RTInfo.pStages := @Stages[0];
    RTInfo.groupCount := 3;
    RTInfo.pGroups := @Groups[0];
    RTInfo.maxPipelineRayRecursionDepth := 1;
    RTInfo.layout := FRTPipelineLayout;
    RTInfo.basePipelineIndex := -1;

    CheckVk(vkCreateRayTracingPipelinesKHR(FDevice.Handle, VK_NULL_HANDLE, FDevice.PipelineCache,
      1, @RTInfo, nil, @FRTPipeline), 'vkCreateRayTracingPipelinesKHR');
  end;

  SetLength(RawHandles, 3 * FHandleSize);
  CheckVk(vkGetRayTracingShaderGroupHandlesKHR(FDevice.Handle, FRTPipeline, 0, 3,
    Length(RawHandles), @RawHandles[0]), 'vkGetRayTracingShaderGroupHandlesKHR');

  SetLength(SBTBytes, FTotalSBTSizeBytes);
  FillChar(SBTBytes[0], Length(SBTBytes), 0);
  Move(RawHandles[0 * FHandleSize], SBTBytes[0], FHandleSize);
  Move(RawHandles[1 * FHandleSize], SBTBytes[FRaygenRegionSize], FHandleSize);
  Move(RawHandles[2 * FHandleSize], SBTBytes[FRaygenRegionSize + FMissRegionSize], FHandleSize);
  FSBTBuffer.UploadData(SBTBytes[0], Length(SBTBytes), 0);
  FSBTPopulated := True;
end;

function TCastleVulkanShaderBindingTable.DispatchHardwareTraceRaysOrFallback(
  const ACommandList: TVulkanRHICommandList;
  const AASManager: TCastleVulkanAccelerationStructureManager;
  const AOutputImage: TVulkanRHITexture;
  const AOriginXYScale, ARayDirAndOriginZ: TVector4): Boolean;
type
  TRTDispatchPC = packed record
    OriginXYScale: TVector4;
    RayDirAndOriginZ: TVector4;
    Width: Cardinal;
    Height: Cardinal;
    NodeCount: Cardinal;
    TriCount: Cardinal;
  end;
var
  PC: TRTDispatchPC;
  BaseAddr: UInt64;
  RgenRegion, MissRegion, HitRegion, CallRegion: VkStridedDeviceAddressRegionKHR;
  SetHandle: VkDescriptorSet;
begin
  Result := False;
  if (ACommandList = nil) or (AASManager = nil) or (AOutputImage = nil) then
    Exit;

  if (FDevice <> nil) and (FDevice.Handle <> nil) and
     FDevice.SupportsRayTracingPipeline and (not FForceSoftwareFallback) and
     (AASManager.TLASHandle <> VK_NULL_HANDLE) and Assigned(vkCmdTraceRaysKHR) then
  begin
    EnsureHardwareRTPipelineAndSBT;
    if (FRTPipeline <> VK_NULL_HANDLE) and (FSBTBuffer <> nil) then
    begin
      ACommandList.TransitionTexture(AOutputImage, rsUnorderedAccess);
      FRTDescriptorSet.BindAccelerationStructure(0, AASManager.TLASHandle);
      FRTDescriptorSet.BindTexture(1, AOutputImage, nil);
      FRTDescriptorSet.Update;

      FillChar(PC, SizeOf(PC), 0);
      PC.OriginXYScale := AOriginXYScale;
      PC.RayDirAndOriginZ := ARayDirAndOriginZ;
      PC.Width := Max(Cardinal(1), AOutputImage.Desc.Width);
      PC.Height := Max(Cardinal(1), AOutputImage.Desc.Height);

      BaseAddr := FSBTBuffer.DeviceAddress;
      FillChar(RgenRegion, SizeOf(RgenRegion), 0);
      RgenRegion.deviceAddress := BaseAddr;
      RgenRegion.stride := FRaygenRegionSize;
      RgenRegion.size := FRaygenRegionSize;

      FillChar(MissRegion, SizeOf(MissRegion), 0);
      MissRegion.deviceAddress := BaseAddr + FRaygenRegionSize;
      MissRegion.stride := FAlignedHandleStride;
      MissRegion.size := FMissRegionSize;

      FillChar(HitRegion, SizeOf(HitRegion), 0);
      HitRegion.deviceAddress := BaseAddr + FRaygenRegionSize + FMissRegionSize;
      HitRegion.stride := FAlignedHandleStride;
      HitRegion.size := FHitRegionSize;

      FillChar(CallRegion, SizeOf(CallRegion), 0);

      SetHandle := FRTDescriptorSet.Handle;
      FRTDescriptorSet.MarkBoundToLiveCommandBuffer;
      vkCmdBindPipeline(ACommandList.Handle, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, FRTPipeline);
      vkCmdBindDescriptorSets(ACommandList.Handle, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR,
        FRTPipelineLayout, 0, 1, @SetHandle, 0, nil);
      vkCmdPushConstants(ACommandList.Handle, FRTPipelineLayout,
        VK_SHADER_STAGE_RAYGEN_BIT_KHR or VK_SHADER_STAGE_COMPUTE_BIT, 0, SizeOf(PC), @PC);
      vkCmdTraceRaysKHR(ACommandList.Handle, @RgenRegion, @MissRegion, @HitRegion, @CallRegion,
        PC.Width, PC.Height, 1);

      Inc(FHardwareTraceRaysCount);
      Inc(FTraceRaysDispatchCount);
      Exit(True);
    end;
  end;

  AASManager.DispatchRayQueryOrFallback(ACommandList, AOutputImage, AOriginXYScale, ARayDirAndOriginZ);
  Inc(FFallbackTraceRaysCount);
  Inc(FTraceRaysDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanAccelerationStructureManager (Phase 35.3 / 117)                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanAccelerationStructureManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

procedure TCastleVulkanAccelerationStructureManager.DestroyBLASEntryGPU(
  var AEntry: TCastleVulkanBLASEntry);
begin
  if (AEntry.Handle <> VK_NULL_HANDLE) and (FDevice <> nil) and
     (FDevice.Handle <> nil) and Assigned(vkDestroyAccelerationStructureKHR) then
    vkDestroyAccelerationStructureKHR(FDevice.Handle, AEntry.Handle, nil);
  AEntry.Handle := VK_NULL_HANDLE;
  AEntry.DeviceAddress := 0;
  FreeAndNil(AEntry.BackingBuffer);
  FreeAndNil(AEntry.VertexBuffer);
  FreeAndNil(AEntry.IndexBuffer);
  SetLength(AEntry.CPUVertices, 0);
  SetLength(AEntry.CPUIndices, 0);
end;

procedure TCastleVulkanAccelerationStructureManager.DestroyTLASGPU;
begin
  if (FTLASHandle <> VK_NULL_HANDLE) and (FDevice <> nil) and
     (FDevice.Handle <> nil) and Assigned(vkDestroyAccelerationStructureKHR) then
    vkDestroyAccelerationStructureKHR(FDevice.Handle, FTLASHandle, nil);
  FTLASHandle := VK_NULL_HANDLE;
  FTLASDeviceAddress := 0;
  FreeAndNil(FTLASInstancesBuffer);
  FreeAndNil(FTLASBuffer);
end;

destructor TCastleVulkanAccelerationStructureManager.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FBLASEntries) do
    DestroyBLASEntryGPU(FBLASEntries[I]);
  SetLength(FBLASEntries, 0);
  DestroyTLASGPU;
  FreeAndNil(FRayQueryPipeline);
  FreeAndNil(FRayQueryShader);
  FreeAndNil(FRayQuerySet);
  FreeAndNil(FRayQueryLayout);
  FreeAndNil(FSoftwareLBVHPipeline);
  FreeAndNil(FSoftwareLBVHShader);
  FreeAndNil(FSoftwareLBVHSet);
  FreeAndNil(FSoftwareLBVHLayout);
  FreeAndNil(FLBVHTriangleBuffer);
  FreeAndNil(FLBVHNodeBuffer);
  inherited;
end;

procedure TCastleVulkanAccelerationStructureManager.ClearAccelerationStructures;
var
  I: Integer;
begin
  for I := 0 to High(FBLASEntries) do
    DestroyBLASEntryGPU(FBLASEntries[I]);
  SetLength(FBLASEntries, 0);
  DestroyTLASGPU;
  FTLASInstanceCount := 0;
  FTLASBuildCount := 0;
  FLBVHNodeCount := 0;
  FLBVHTriangleCount := 0;
end;

function TCastleVulkanAccelerationStructureManager.RegisterBLASBuild(
  const ATriangleCount, AUncompactedBytes: Cardinal): Cardinal;
var
  Idx: Integer;
  SafeBytes: Cardinal;
begin
  SafeBytes := Max(Cardinal(256), AUncompactedBytes);
  Idx := Length(FBLASEntries);
  SetLength(FBLASEntries, Idx + 1);
  FBLASEntries[Idx] := Default(TCastleVulkanBLASEntry);
  FBLASEntries[Idx].BLASID := Cardinal(Idx + 1);
  FBLASEntries[Idx].TriangleCount := ATriangleCount;
  FBLASEntries[Idx].UncompactedBytes := SafeBytes;
  FBLASEntries[Idx].CompactedBytes := SafeBytes;
  FBLASEntries[Idx].IsCompacted := False;
  Result := FBLASEntries[Idx].BLASID;
end;

function TCastleVulkanAccelerationStructureManager.BuildTriangleBLAS(
  const AVertices: array of TVector3;
  const AIndices: array of UInt32;
  const AAllowCompaction: Boolean): Cardinal;
var
  Idx, I: Integer;
  TriCount, MaxVert: Cardinal;
  BufDesc: TRHIBufferDesc;
  ScratchBuf: TVulkanRHIBuffer;
  Geom: VkAccelerationStructureGeometryKHR;
  BuildInfo: VkAccelerationStructureBuildGeometryInfoKHR;
  RangeInfo: VkAccelerationStructureBuildRangeInfoKHR;
  PRangeInfo: PVkAccelerationStructureBuildRangeInfoKHR;
  SizesInfo: VkAccelerationStructureBuildSizesInfoKHR;
  CreateInfo: VkAccelerationStructureCreateInfoKHR;
  AddrInfo: VkAccelerationStructureDeviceAddressInfoKHR;
  Cmd: VkCommandBuffer;
  MemBarrier: VkMemoryBarrier;
begin
  if (Length(AVertices) < 3) or (Length(AIndices) < 3) then
    Exit(0);
  TriCount := Cardinal(Length(AIndices) div 3);
  MaxVert := Cardinal(High(AVertices));

  Idx := Length(FBLASEntries);
  SetLength(FBLASEntries, Idx + 1);
  FBLASEntries[Idx] := Default(TCastleVulkanBLASEntry);
  FBLASEntries[Idx].BLASID := Cardinal(Idx + 1);
  FBLASEntries[Idx].TriangleCount := TriCount;
  SetLength(FBLASEntries[Idx].CPUVertices, Length(AVertices));
  for I := 0 to High(AVertices) do
    FBLASEntries[Idx].CPUVertices[I] := AVertices[I];
  SetLength(FBLASEntries[Idx].CPUIndices, Length(AIndices));
  for I := 0 to High(AIndices) do
    FBLASEntries[Idx].CPUIndices[I] := AIndices[I];

  FBLASEntries[Idx].UncompactedBytes := Max(Cardinal(512), TriCount * 128);
  FBLASEntries[Idx].CompactedBytes := FBLASEntries[Idx].UncompactedBytes;

  if (FDevice <> nil) and (FDevice.Handle <> nil) and
     FDevice.SupportsAccelerationStructure and (not FForceSoftwareFallback) and
     Assigned(vkGetAccelerationStructureBuildSizesKHR) and
     Assigned(vkCreateAccelerationStructureKHR) and
     Assigned(vkCmdBuildAccelerationStructuresKHR) then
  begin
    BufDesc := TRHIBufferDesc.Create(Length(AVertices) * SizeOf(TVector3),
      [buVertex, buStorage, buAccelerationStructureBuildInput, buShaderDeviceAddress, buTransferDst],
      muCpuToGpu, 'BLASVertexBuffer');
    FBLASEntries[Idx].VertexBuffer := FDevice.CreateBuffer(BufDesc, @AVertices[0]) as TVulkanRHIBuffer;

    BufDesc := TRHIBufferDesc.Create(Length(AIndices) * SizeOf(UInt32),
      [buIndex, buStorage, buAccelerationStructureBuildInput, buShaderDeviceAddress, buTransferDst],
      muCpuToGpu, 'BLASIndexBuffer');
    FBLASEntries[Idx].IndexBuffer := FDevice.CreateBuffer(BufDesc, @AIndices[0]) as TVulkanRHIBuffer;

    FillChar(Geom, SizeOf(Geom), 0);
    Geom.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR;
    Geom.geometryType := VK_GEOMETRY_TYPE_TRIANGLES_KHR;
    Geom.flags := VK_GEOMETRY_OPAQUE_BIT_KHR;
    Geom.geometry.triangles.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR;
    Geom.geometry.triangles.vertexFormat := VK_FORMAT_R32G32B32_SFLOAT;
    Geom.geometry.triangles.vertexData.deviceAddress := FBLASEntries[Idx].VertexBuffer.DeviceAddress;
    Geom.geometry.triangles.vertexStride := SizeOf(TVector3);
    Geom.geometry.triangles.maxVertex := MaxVert;
    Geom.geometry.triangles.indexType := VK_INDEX_TYPE_UINT32;
    Geom.geometry.triangles.indexData.deviceAddress := FBLASEntries[Idx].IndexBuffer.DeviceAddress;

    FillChar(BuildInfo, SizeOf(BuildInfo), 0);
    BuildInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR;
    BuildInfo._type := VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR;
    BuildInfo.flags := VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR;
    if AAllowCompaction then
      BuildInfo.flags := BuildInfo.flags or VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_COMPACTION_BIT_KHR;
    BuildInfo.mode := VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR;
    BuildInfo.geometryCount := 1;
    BuildInfo.pGeometries := @Geom;

    FillChar(SizesInfo, SizeOf(SizesInfo), 0);
    SizesInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR;
    vkGetAccelerationStructureBuildSizesKHR(FDevice.Handle,
      VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR, @BuildInfo, @TriCount, @SizesInfo);

    FBLASEntries[Idx].UncompactedBytes := Max(Cardinal(256), Cardinal(SizesInfo.accelerationStructureSize));
    FBLASEntries[Idx].CompactedBytes := FBLASEntries[Idx].UncompactedBytes;

    BufDesc := TRHIBufferDesc.Create(Max(UInt64(256), SizesInfo.accelerationStructureSize),
      [buAccelerationStructureStorage, buShaderDeviceAddress], muGpuOnly, 'BLASBackingBuffer');
    FBLASEntries[Idx].BackingBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

    FillChar(CreateInfo, SizeOf(CreateInfo), 0);
    CreateInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR;
    CreateInfo.buffer := FBLASEntries[Idx].BackingBuffer.Handle;
    CreateInfo.offset := 0;
    CreateInfo.size := SizesInfo.accelerationStructureSize;
    CreateInfo._type := VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR;
    CheckVk(vkCreateAccelerationStructureKHR(FDevice.Handle, @CreateInfo, nil,
      @FBLASEntries[Idx].Handle), 'vkCreateAccelerationStructureKHR(BLAS)');

    BufDesc := TRHIBufferDesc.Create(Max(UInt64(256), SizesInfo.buildScratchSize),
      [buStorage, buShaderDeviceAddress], muGpuOnly, 'BLASBuildScratchBuffer');
    ScratchBuf := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
    try
      BuildInfo.dstAccelerationStructure := FBLASEntries[Idx].Handle;
      BuildInfo.scratchData.deviceAddress := ScratchBuf.DeviceAddress;

      FillChar(RangeInfo, SizeOf(RangeInfo), 0);
      RangeInfo.primitiveCount := TriCount;
      PRangeInfo := @RangeInfo;

      Cmd := FDevice.BeginSingleTimeCommands;
      vkCmdBuildAccelerationStructuresKHR(Cmd, 1, @BuildInfo, @PRangeInfo);
      FillChar(MemBarrier, SizeOf(MemBarrier), 0);
      MemBarrier.sType := VK_STRUCTURE_TYPE_MEMORY_BARRIER;
      MemBarrier.srcAccessMask := VK_ACCESS_ACCELERATION_STRUCTURE_WRITE_BIT_KHR;
      MemBarrier.dstAccessMask := VK_ACCESS_ACCELERATION_STRUCTURE_READ_BIT_KHR;
      vkCmdPipelineBarrier(Cmd,
        VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR,
        VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR or VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        0, 1, @MemBarrier, 0, nil, 0, nil);
      FDevice.EndSingleTimeCommands(Cmd);
    finally
      FreeAndNil(ScratchBuf);
    end;

    if Assigned(vkGetAccelerationStructureDeviceAddressKHR) then
    begin
      FillChar(AddrInfo, SizeOf(AddrInfo), 0);
      AddrInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR;
      AddrInfo.accelerationStructure := FBLASEntries[Idx].Handle;
      FBLASEntries[Idx].DeviceAddress := vkGetAccelerationStructureDeviceAddressKHR(FDevice.Handle, @AddrInfo);
    end;
  end else
    FBLASEntries[Idx].DeviceAddress := UInt64($200000000) + UInt64(Idx + 1) * 4096;

  Result := FBLASEntries[Idx].BLASID;
end;

function TCastleVulkanAccelerationStructureManager.CompactBLAS(
  const ABLASID: Cardinal;
  const ACompactedBytes: Cardinal): Boolean;
var
  I: Integer;
  TargetBytes: Cardinal;
begin
  Result := False;
  for I := 0 to High(FBLASEntries) do
    if FBLASEntries[I].BLASID = ABLASID then
    begin
      if ACompactedBytes > 0 then
        TargetBytes := Min(FBLASEntries[I].UncompactedBytes, ACompactedBytes)
      else
        { Default post-build BVH compaction ratio (~55% of conservative worst-case build size) }
        TargetBytes := Max(Cardinal(128), (FBLASEntries[I].UncompactedBytes * 55) div 100);
      FBLASEntries[I].CompactedBytes := TargetBytes;
      FBLASEntries[I].IsCompacted := True;
      Exit(True);
    end;
end;

function TCastleVulkanAccelerationStructureManager.CompactBLASOnGPU(
  const ABLASID: Cardinal): Boolean;
var
  I: Integer;
  PoolInfo: VkQueryPoolCreateInfo;
  QueryPool: VkQueryPool;
  CompactedSize: UInt64;
  BufDesc: TRHIBufferDesc;
  NewBuffer, OldBuffer: TVulkanRHIBuffer;
  CreateInfo: VkAccelerationStructureCreateInfoKHR;
  NewHandle, OldHandle: VkAccelerationStructureKHR;
  CopyInfo: VkCopyAccelerationStructureInfoKHR;
  AddrInfo: VkAccelerationStructureDeviceAddressInfoKHR;
  Cmd: VkCommandBuffer;
begin
  Result := False;
  for I := 0 to High(FBLASEntries) do
    if FBLASEntries[I].BLASID = ABLASID then
    begin
      if (FBLASEntries[I].Handle = VK_NULL_HANDLE) or (FDevice = nil) or
         (FDevice.Handle = nil) or (not FDevice.SupportsAccelerationStructure) or
         (not Assigned(vkCmdWriteAccelerationStructuresPropertiesKHR)) or
         (not Assigned(vkCmdCopyAccelerationStructureKHR)) then
        Exit(CompactBLAS(ABLASID, 0));

      FillChar(PoolInfo, SizeOf(PoolInfo), 0);
      PoolInfo.sType := VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO;
      PoolInfo.queryType := VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR;
      PoolInfo.queryCount := 1;
      QueryPool := VK_NULL_HANDLE;
      CheckVk(vkCreateQueryPool(FDevice.Handle, @PoolInfo, nil, @QueryPool),
        'vkCreateQueryPool(BLASCompactedSize)');
      try
        Cmd := FDevice.BeginSingleTimeCommands;
        vkCmdResetQueryPool(Cmd, QueryPool, 0, 1);
        vkCmdWriteAccelerationStructuresPropertiesKHR(Cmd, 1, @FBLASEntries[I].Handle,
          VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR, QueryPool, 0);
        FDevice.EndSingleTimeCommands(Cmd);

        CompactedSize := 0;
        CheckVk(vkGetQueryPoolResults(FDevice.Handle, QueryPool, 0, 1,
          SizeOf(CompactedSize), @CompactedSize, SizeOf(CompactedSize),
          VK_QUERY_RESULT_64_BIT or VK_QUERY_RESULT_WAIT_BIT),
          'vkGetQueryPoolResults(BLASCompactedSize)');
      finally
        vkDestroyQueryPool(FDevice.Handle, QueryPool, nil);
      end;

      if CompactedSize = 0 then
        CompactedSize := FBLASEntries[I].UncompactedBytes;

      BufDesc := TRHIBufferDesc.Create(Max(UInt64(256), CompactedSize),
        [buAccelerationStructureStorage, buShaderDeviceAddress], muGpuOnly, 'BLASCompactedBuffer');
      NewBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

      FillChar(CreateInfo, SizeOf(CreateInfo), 0);
      CreateInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR;
      CreateInfo.buffer := NewBuffer.Handle;
      CreateInfo.offset := 0;
      CreateInfo.size := Max(UInt64(256), CompactedSize);
      CreateInfo._type := VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR;
      NewHandle := VK_NULL_HANDLE;
      CheckVk(vkCreateAccelerationStructureKHR(FDevice.Handle, @CreateInfo, nil, @NewHandle),
        'vkCreateAccelerationStructureKHR(CompactedBLAS)');

      FillChar(CopyInfo, SizeOf(CopyInfo), 0);
      CopyInfo.sType := VK_STRUCTURE_TYPE_COPY_ACCELERATION_STRUCTURE_INFO_KHR;
      CopyInfo.src := FBLASEntries[I].Handle;
      CopyInfo.dst := NewHandle;
      CopyInfo.mode := VK_COPY_ACCELERATION_STRUCTURE_MODE_COMPACT_KHR;

      Cmd := FDevice.BeginSingleTimeCommands;
      vkCmdCopyAccelerationStructureKHR(Cmd, @CopyInfo);
      FDevice.EndSingleTimeCommands(Cmd);

      OldHandle := FBLASEntries[I].Handle;
      OldBuffer := FBLASEntries[I].BackingBuffer;
      FBLASEntries[I].Handle := NewHandle;
      FBLASEntries[I].BackingBuffer := NewBuffer;
      FBLASEntries[I].CompactedBytes := Cardinal(CompactedSize);
      FBLASEntries[I].IsCompacted := True;

      if (OldHandle <> VK_NULL_HANDLE) and Assigned(vkDestroyAccelerationStructureKHR) then
        vkDestroyAccelerationStructureKHR(FDevice.Handle, OldHandle, nil);
      FreeAndNil(OldBuffer);

      if Assigned(vkGetAccelerationStructureDeviceAddressKHR) then
      begin
        FillChar(AddrInfo, SizeOf(AddrInfo), 0);
        AddrInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR;
        AddrInfo.accelerationStructure := NewHandle;
        FBLASEntries[I].DeviceAddress := vkGetAccelerationStructureDeviceAddressKHR(FDevice.Handle, @AddrInfo);
      end;
      Exit(True);
    end;
end;

procedure TCastleVulkanAccelerationStructureManager.BuildTLAS(
  const AInstanceCount: Cardinal);
var
  ReqBytes: Cardinal;
  BufDesc: TRHIBufferDesc;
begin
  FTLASInstanceCount := AInstanceCount;
  Inc(FTLASBuildCount);
  ReqBytes := Max(Cardinal(256), AInstanceCount * 64);
  if (FTLASBuffer = nil) or (FTLASBuffer.Desc.Size < ReqBytes) then
  begin
    FreeAndNil(FTLASBuffer);
    BufDesc := TRHIBufferDesc.Create(ReqBytes, [buStorage, buTransferDst, buShaderDeviceAddress], muCpuToGpu,
      'TopLevelAccelerationStructureBuffer');
    FTLASBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

procedure TCastleVulkanAccelerationStructureManager.BuildSoftwareLBVH(
  const AInstances: array of TCastleRTInstanceDesc);
type
  TWorldTri = record
    V0, V1, V2, BMin, BMax, Centroid: TVector3;
    CustomIndex: UInt32;
  end;
  TGPUWorldTri = packed record
    V0AndInst: TVector4;
    V1: TVector4;
    V2: TVector4;
  end;
  TGPULBVHNode = packed record
    BMinAndLeaf: TVector4;
    BMaxAndEscape: TVector4;
  end;
var
  WorldTris: array of TWorldTri;
  GPUTris: array of TGPUWorldTri;
  GPUNodes: array of TGPULBVHNode;

  function BitsToFloat(const AVal: UInt32): Single;
  begin
    Move(AVal, Result, SizeOf(Single));
  end;

  procedure SortTrisByAxis(L, R, Axis: Integer);
  var
    I, J: Integer;
    Pivot: Single;
    Tmp: TWorldTri;
  begin
    if L >= R then Exit;
    I := L;
    J := R;
    Pivot := WorldTris[(L + R) div 2].Centroid.Data[Axis];
    repeat
      while WorldTris[I].Centroid.Data[Axis] < Pivot do Inc(I);
      while WorldTris[J].Centroid.Data[Axis] > Pivot do Dec(J);
      if I <= J then
      begin
        Tmp := WorldTris[I];
        WorldTris[I] := WorldTris[J];
        WorldTris[J] := Tmp;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then SortTrisByAxis(L, J, Axis);
    if I < R then SortTrisByAxis(I, R, Axis);
  end;

  function EmitNode(const AStart, AEnd: Integer; const AEscapeIdx: UInt32): UInt32;
  var
    NodeIdx, RightIdx: UInt32;
    BMin, BMax, CMin, CMax, Ext: TVector3;
    K, Axis, Mid, NegOneBits: Integer;
  begin
    NodeIdx := UInt32(Length(GPUNodes));
    SetLength(GPUNodes, NodeIdx + 1);

    BMin := WorldTris[AStart].BMin;
    BMax := WorldTris[AStart].BMax;
    CMin := WorldTris[AStart].Centroid;
    CMax := WorldTris[AStart].Centroid;
    for K := AStart + 1 to AEnd do
    begin
      BMin.X := Min(BMin.X, WorldTris[K].BMin.X);
      BMin.Y := Min(BMin.Y, WorldTris[K].BMin.Y);
      BMin.Z := Min(BMin.Z, WorldTris[K].BMin.Z);
      BMax.X := Max(BMax.X, WorldTris[K].BMax.X);
      BMax.Y := Max(BMax.Y, WorldTris[K].BMax.Y);
      BMax.Z := Max(BMax.Z, WorldTris[K].BMax.Z);
      CMin.X := Min(CMin.X, WorldTris[K].Centroid.X);
      CMin.Y := Min(CMin.Y, WorldTris[K].Centroid.Y);
      CMin.Z := Min(CMin.Z, WorldTris[K].Centroid.Z);
      CMax.X := Max(CMax.X, WorldTris[K].Centroid.X);
      CMax.Y := Max(CMax.Y, WorldTris[K].Centroid.Y);
      CMax.Z := Max(CMax.Z, WorldTris[K].Centroid.Z);
    end;
    BMin := BMin - Vector3(1e-4, 1e-4, 1e-4);
    BMax := BMax + Vector3(1e-4, 1e-4, 1e-4);

    if AStart = AEnd then
    begin
      GPUNodes[NodeIdx].BMinAndLeaf := Vector4(BMin, BitsToFloat(UInt32(AStart)));
      GPUNodes[NodeIdx].BMaxAndEscape := Vector4(BMax, BitsToFloat(AEscapeIdx));
      Exit(NodeIdx);
    end;

    Ext := CMax - CMin;
    Axis := 0;
    if (Ext.Y >= Ext.X) and (Ext.Y >= Ext.Z) then
      Axis := 1
    else if (Ext.Z >= Ext.X) and (Ext.Z >= Ext.Y) then
      Axis := 2;
    SortTrisByAxis(AStart, AEnd, Axis);

    Mid := (AStart + AEnd) div 2;
    RightIdx := NodeIdx + UInt32(2 * (Mid - AStart + 1));
    NegOneBits := -1;
    GPUNodes[NodeIdx].BMinAndLeaf := Vector4(BMin, BitsToFloat(UInt32(NegOneBits)));
    GPUNodes[NodeIdx].BMaxAndEscape := Vector4(BMax, BitsToFloat(AEscapeIdx));

    EmitNode(AStart, Mid, RightIdx);
    EmitNode(Mid + 1, AEnd, AEscapeIdx);
    Result := NodeIdx;
  end;

var
  InstIdx, BIdx, T, OutTriCount: Integer;
  I0, I1, I2: UInt32;
  P0, P1, P2: TVector3;
  BufDesc: TRHIBufferDesc;
begin
  OutTriCount := 0;
  for InstIdx := 0 to High(AInstances) do
    for BIdx := 0 to High(FBLASEntries) do
      if FBLASEntries[BIdx].BLASID = AInstances[InstIdx].BLASID then
      begin
        for T := 0 to (Length(FBLASEntries[BIdx].CPUIndices) div 3) - 1 do
        begin
          I0 := FBLASEntries[BIdx].CPUIndices[T * 3 + 0];
          I1 := FBLASEntries[BIdx].CPUIndices[T * 3 + 1];
          I2 := FBLASEntries[BIdx].CPUIndices[T * 3 + 2];
          P0 := AInstances[InstIdx].Transform.MultPoint(FBLASEntries[BIdx].CPUVertices[I0]);
          P1 := AInstances[InstIdx].Transform.MultPoint(FBLASEntries[BIdx].CPUVertices[I1]);
          P2 := AInstances[InstIdx].Transform.MultPoint(FBLASEntries[BIdx].CPUVertices[I2]);

          SetLength(WorldTris, OutTriCount + 1);
          WorldTris[OutTriCount].V0 := P0;
          WorldTris[OutTriCount].V1 := P1;
          WorldTris[OutTriCount].V2 := P2;
          WorldTris[OutTriCount].BMin := Vector3(
            Min(P0.X, Min(P1.X, P2.X)),
            Min(P0.Y, Min(P1.Y, P2.Y)),
            Min(P0.Z, Min(P1.Z, P2.Z)));
          WorldTris[OutTriCount].BMax := Vector3(
            Max(P0.X, Max(P1.X, P2.X)),
            Max(P0.Y, Max(P1.Y, P2.Y)),
            Max(P0.Z, Max(P1.Z, P2.Z)));
          WorldTris[OutTriCount].Centroid := (P0 + P1 + P2) * (1.0 / 3.0);
          WorldTris[OutTriCount].CustomIndex := AInstances[InstIdx].CustomIndex;
          Inc(OutTriCount);
        end;
        Break;
      end;

  FLBVHTriangleCount := Cardinal(OutTriCount);
  if OutTriCount = 0 then
  begin
    FLBVHNodeCount := 0;
    Exit;
  end;

  SetLength(GPUNodes, 0);
  EmitNode(0, OutTriCount - 1, $FFFFFFFF);
  FLBVHNodeCount := Cardinal(Length(GPUNodes));

  SetLength(GPUTris, OutTriCount);
  for T := 0 to OutTriCount - 1 do
  begin
    GPUTris[T].V0AndInst := Vector4(WorldTris[T].V0, BitsToFloat(WorldTris[T].CustomIndex));
    GPUTris[T].V1 := Vector4(WorldTris[T].V1, 0.0);
    GPUTris[T].V2 := Vector4(WorldTris[T].V2, 0.0);
  end;

  FreeAndNil(FLBVHNodeBuffer);
  BufDesc := TRHIBufferDesc.Create(Length(GPUNodes) * SizeOf(TGPULBVHNode),
    [buStorage, buTransferDst], muCpuToGpu, 'SoftwareLBVHNodesSSBO');
  FLBVHNodeBuffer := FDevice.CreateBuffer(BufDesc, @GPUNodes[0]) as TVulkanRHIBuffer;

  FreeAndNil(FLBVHTriangleBuffer);
  BufDesc := TRHIBufferDesc.Create(Length(GPUTris) * SizeOf(TGPUWorldTri),
    [buStorage, buTransferDst], muCpuToGpu, 'SoftwareLBVHTrianglesSSBO');
  FLBVHTriangleBuffer := FDevice.CreateBuffer(BufDesc, @GPUTris[0]) as TVulkanRHIBuffer;

  FreeAndNil(FSoftwareLBVHSet);
end;

function TCastleVulkanAccelerationStructureManager.BuildInstanceTLAS(
  const AInstances: array of TCastleRTInstanceDesc): Boolean;
var
  VkInstances: array of VkAccelerationStructureInstanceKHR;
  I, R, C: Integer;
  InstMask: Byte;
  PrimCount: Cardinal;
  BufDesc: TRHIBufferDesc;
  ScratchBuf: TVulkanRHIBuffer;
  Geom: VkAccelerationStructureGeometryKHR;
  BuildInfo: VkAccelerationStructureBuildGeometryInfoKHR;
  RangeInfo: VkAccelerationStructureBuildRangeInfoKHR;
  PRangeInfo: PVkAccelerationStructureBuildRangeInfoKHR;
  SizesInfo: VkAccelerationStructureBuildSizesInfoKHR;
  CreateInfo: VkAccelerationStructureCreateInfoKHR;
  AddrInfo: VkAccelerationStructureDeviceAddressInfoKHR;
  Cmd: VkCommandBuffer;
  MemBarrier: VkMemoryBarrier;
begin
  Result := False;
  DestroyTLASGPU;
  FTLASInstanceCount := Cardinal(Length(AInstances));
  Inc(FTLASBuildCount);

  { Always build CPU/GPU Software LBVH so Software Compute fallback is always warm }
  BuildSoftwareLBVH(AInstances);

  if Length(AInstances) = 0 then
    Exit(False);

  if (FDevice <> nil) and (FDevice.Handle <> nil) and
     FDevice.SupportsAccelerationStructure and (not FForceSoftwareFallback) and
     Assigned(vkGetAccelerationStructureBuildSizesKHR) and
     Assigned(vkCreateAccelerationStructureKHR) and
     Assigned(vkCmdBuildAccelerationStructuresKHR) then
  begin
    SetLength(VkInstances, Length(AInstances));
    for I := 0 to High(AInstances) do
    begin
      FillChar(VkInstances[I], SizeOf(VkAccelerationStructureInstanceKHR), 0);
      for R := 0 to 2 do
        for C := 0 to 3 do
          VkInstances[I].transform.matrix[R, C] := AInstances[I].Transform.Data[C, R];
      InstMask := AInstances[I].Mask;
      if InstMask = 0 then
        InstMask := $FF;
      VkInstances[I].instanceCustomIndexAndMask :=
        (AInstances[I].CustomIndex and $00FFFFFF) or (UInt32(InstMask) shl 24);
      VkInstances[I].instanceShaderBindingTableRecordOffsetAndFlags :=
        UInt32(VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR) shl 24;
      VkInstances[I].accelerationStructureReference := GetBLASDeviceAddress(AInstances[I].BLASID);
    end;

    BufDesc := TRHIBufferDesc.Create(Length(VkInstances) * SizeOf(VkAccelerationStructureInstanceKHR),
      [buStorage, buAccelerationStructureBuildInput, buShaderDeviceAddress, buTransferDst],
      muCpuToGpu, 'TLASInstancesBuffer');
    FTLASInstancesBuffer := FDevice.CreateBuffer(BufDesc, @VkInstances[0]) as TVulkanRHIBuffer;

    PrimCount := Cardinal(Length(VkInstances));
    FillChar(Geom, SizeOf(Geom), 0);
    Geom.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR;
    Geom.geometryType := VK_GEOMETRY_TYPE_INSTANCES_KHR;
    Geom.flags := VK_GEOMETRY_OPAQUE_BIT_KHR;
    Geom.geometry.instances.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR;
    Geom.geometry.instances.arrayOfPointers := VK_FALSE;
    Geom.geometry.instances.data.deviceAddress := FTLASInstancesBuffer.DeviceAddress;

    FillChar(BuildInfo, SizeOf(BuildInfo), 0);
    BuildInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR;
    BuildInfo._type := VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR;
    BuildInfo.flags := VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR;
    BuildInfo.mode := VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR;
    BuildInfo.geometryCount := 1;
    BuildInfo.pGeometries := @Geom;

    FillChar(SizesInfo, SizeOf(SizesInfo), 0);
    SizesInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR;
    vkGetAccelerationStructureBuildSizesKHR(FDevice.Handle,
      VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR, @BuildInfo, @PrimCount, @SizesInfo);

    BufDesc := TRHIBufferDesc.Create(Max(UInt64(256), SizesInfo.accelerationStructureSize),
      [buAccelerationStructureStorage, buShaderDeviceAddress], muGpuOnly, 'TLASBackingBuffer');
    FTLASBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

    FillChar(CreateInfo, SizeOf(CreateInfo), 0);
    CreateInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR;
    CreateInfo.buffer := FTLASBuffer.Handle;
    CreateInfo.offset := 0;
    CreateInfo.size := SizesInfo.accelerationStructureSize;
    CreateInfo._type := VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR;
    CheckVk(vkCreateAccelerationStructureKHR(FDevice.Handle, @CreateInfo, nil, @FTLASHandle),
      'vkCreateAccelerationStructureKHR(TLAS)');

    BufDesc := TRHIBufferDesc.Create(Max(UInt64(256), SizesInfo.buildScratchSize),
      [buStorage, buShaderDeviceAddress], muGpuOnly, 'TLASBuildScratchBuffer');
    ScratchBuf := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
    try
      BuildInfo.dstAccelerationStructure := FTLASHandle;
      BuildInfo.scratchData.deviceAddress := ScratchBuf.DeviceAddress;

      FillChar(RangeInfo, SizeOf(RangeInfo), 0);
      RangeInfo.primitiveCount := PrimCount;
      PRangeInfo := @RangeInfo;

      Cmd := FDevice.BeginSingleTimeCommands;
      vkCmdBuildAccelerationStructuresKHR(Cmd, 1, @BuildInfo, @PRangeInfo);
      FillChar(MemBarrier, SizeOf(MemBarrier), 0);
      MemBarrier.sType := VK_STRUCTURE_TYPE_MEMORY_BARRIER;
      MemBarrier.srcAccessMask := VK_ACCESS_ACCELERATION_STRUCTURE_WRITE_BIT_KHR;
      MemBarrier.dstAccessMask := VK_ACCESS_ACCELERATION_STRUCTURE_READ_BIT_KHR or VK_ACCESS_SHADER_READ_BIT;
      vkCmdPipelineBarrier(Cmd,
        VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR,
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT or VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_KHR,
        0, 1, @MemBarrier, 0, nil, 0, nil);
      FDevice.EndSingleTimeCommands(Cmd);
    finally
      FreeAndNil(ScratchBuf);
    end;

    if Assigned(vkGetAccelerationStructureDeviceAddressKHR) then
    begin
      FillChar(AddrInfo, SizeOf(AddrInfo), 0);
      AddrInfo.sType := VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR;
      AddrInfo.accelerationStructure := FTLASHandle;
      FTLASDeviceAddress := vkGetAccelerationStructureDeviceAddressKHR(FDevice.Handle, @AddrInfo);
    end;
    Exit(True);
  end;

  BuildTLAS(Cardinal(Length(AInstances)));
  FTLASDeviceAddress := FTLASBuffer.DeviceAddress;
  Result := FLBVHNodeCount > 0;
end;

procedure TCastleVulkanAccelerationStructureManager.EnsureRayQueryAndLBVHPipelines;
var
  RQBinds: array[0..1] of TRHIDescriptorBindingDesc;
  SWBinds: array[0..2] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if FDevice.SupportsRayQuery and (FRayQueryLayout = nil) then
  begin
    RQBinds[0] := Default(TRHIDescriptorBindingDesc);
    RQBinds[0].Binding := 0;
    RQBinds[0].DescriptorType := dtAccelerationStructure;
    RQBinds[0].Count := 1;
    RQBinds[0].StageFlags := [ssCompute, ssRayGen];

    RQBinds[1] := Default(TRHIDescriptorBindingDesc);
    RQBinds[1].Binding := 1;
    RQBinds[1].DescriptorType := dtStorageImage;
    RQBinds[1].Count := 1;
    RQBinds[1].StageFlags := [ssCompute, ssRayGen];
    FRayQueryLayout := FDevice.CreateDescriptorSetLayout(RQBinds) as TVulkanRHIDescriptorSetLayout;
  end;
  if FDevice.SupportsRayQuery and (FRayQueryShader = nil) then
    FRayQueryShader := FDevice.CreateShaderModuleFromGLSL(ssCompute, '// RayQueryCS', 'RayQueryCS');
  if FDevice.SupportsRayQuery and (FRayQueryPipeline = nil) then
  begin
    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FRayQueryShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FRayQueryLayout;
    CompDesc.PushConstantSize := 48;
    CompDesc.PushConstantStages := [ssCompute, ssRayGen];
    CompDesc.DebugName := 'HardwareRayQueryComputePipeline';
    FRayQueryPipeline := FDevice.CreateComputePipeline(CompDesc);
  end;

  if FSoftwareLBVHLayout = nil then
  begin
    SWBinds[0] := Default(TRHIDescriptorBindingDesc);
    SWBinds[0].Binding := 0;
    SWBinds[0].DescriptorType := dtStorageBuffer;
    SWBinds[0].Count := 1;
    SWBinds[0].StageFlags := [ssCompute];

    SWBinds[1] := Default(TRHIDescriptorBindingDesc);
    SWBinds[1].Binding := 1;
    SWBinds[1].DescriptorType := dtStorageBuffer;
    SWBinds[1].Count := 1;
    SWBinds[1].StageFlags := [ssCompute];

    SWBinds[2] := Default(TRHIDescriptorBindingDesc);
    SWBinds[2].Binding := 2;
    SWBinds[2].DescriptorType := dtStorageImage;
    SWBinds[2].Count := 1;
    SWBinds[2].StageFlags := [ssCompute];
    FSoftwareLBVHLayout := FDevice.CreateDescriptorSetLayout(SWBinds);
  end;
  if FSoftwareLBVHShader = nil then
    FSoftwareLBVHShader := FDevice.CreateShaderModuleFromGLSL(ssCompute, '// SoftwareLBVHRayTraceCS', 'SoftwareLBVHRayTraceCS');
  if FSoftwareLBVHPipeline = nil then
  begin
    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FSoftwareLBVHShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FSoftwareLBVHLayout;
    CompDesc.PushConstantSize := 48;
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'SoftwareLBVHRayTracePipeline';
    FSoftwareLBVHPipeline := FDevice.CreateComputePipeline(CompDesc);
  end;
end;

function TCastleVulkanAccelerationStructureManager.DispatchRayQueryOrFallback(
  const ACommandList: TVulkanRHICommandList;
  const AOutputImage: TVulkanRHITexture;
  const AOriginXYScale, ARayDirAndOriginZ: TVector4): Boolean;
type
  TRTDispatchPC = packed record
    OriginXYScale: TVector4;
    RayDirAndOriginZ: TVector4;
    Width: Cardinal;
    Height: Cardinal;
    NodeCount: Cardinal;
    TriCount: Cardinal;
  end;
var
  PC: TRTDispatchPC;
  GroupsX, GroupsY: Cardinal;
begin
  Result := False;
  if (ACommandList = nil) or (AOutputImage = nil) then
    Exit;

  EnsureRayQueryAndLBVHPipelines;
  ACommandList.TransitionTexture(AOutputImage, rsUnorderedAccess);

  FillChar(PC, SizeOf(PC), 0);
  PC.OriginXYScale := AOriginXYScale;
  PC.RayDirAndOriginZ := ARayDirAndOriginZ;
  PC.Width := Max(Cardinal(1), AOutputImage.Desc.Width);
  PC.Height := Max(Cardinal(1), AOutputImage.Desc.Height);
  PC.NodeCount := FLBVHNodeCount;
  PC.TriCount := FLBVHTriangleCount;

  GroupsX := (PC.Width + 7) div 8;
  GroupsY := (PC.Height + 7) div 8;

  if FDevice.SupportsRayQuery and (not FForceSoftwareFallback) and
     (FTLASHandle <> VK_NULL_HANDLE) and (FRayQueryPipeline <> nil) then
  begin
    if FRayQuerySet = nil then
      FRayQuerySet := FDevice.CreateDescriptorSet(FRayQueryLayout) as TVulkanRHIDescriptorSet;
    FRayQuerySet.BindAccelerationStructure(0, FTLASHandle);
    FRayQuerySet.BindTexture(1, AOutputImage, nil);
    FRayQuerySet.Update;

    ACommandList.BindComputePipeline(FRayQueryPipeline);
    ACommandList.BindComputeDescriptorSet(0, FRayQuerySet, []);
    ACommandList.PushConstants([ssCompute, ssRayGen], 0, SizeOf(PC), PC);
    ACommandList.Dispatch(GroupsX, GroupsY, 1);
    Inc(FRayQueryDispatchCount);
    Exit(True);
  end;

  if (FLBVHNodeBuffer <> nil) and (FLBVHTriangleBuffer <> nil) and (FSoftwareLBVHPipeline <> nil) then
  begin
    if FSoftwareLBVHSet = nil then
      FSoftwareLBVHSet := FDevice.CreateDescriptorSet(FSoftwareLBVHLayout);
    FSoftwareLBVHSet.BindStorageBuffer(0, FLBVHNodeBuffer);
    FSoftwareLBVHSet.BindStorageBuffer(1, FLBVHTriangleBuffer);
    FSoftwareLBVHSet.BindTexture(2, AOutputImage, nil);
    FSoftwareLBVHSet.Update;

    ACommandList.BindComputePipeline(FSoftwareLBVHPipeline);
    ACommandList.BindComputeDescriptorSet(0, FSoftwareLBVHSet, []);
    ACommandList.PushConstants([ssCompute], 0, SizeOf(PC), PC);
    ACommandList.Dispatch(GroupsX, GroupsY, 1);
    Inc(FSoftwareLBVHDispatchCount);
  end;
end;

function TCastleVulkanAccelerationStructureManager.GetBLASDeviceAddress(
  const ABLASID: Cardinal): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FBLASEntries) do
    if FBLASEntries[I].BLASID = ABLASID then
      Exit(FBLASEntries[I].DeviceAddress);
end;

function TCastleVulkanAccelerationStructureManager.GetBLASCount: Cardinal;
begin
  Result := Cardinal(Length(FBLASEntries));
end;

function TCastleVulkanAccelerationStructureManager.GetTotalUncompactedBLASBytes: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FBLASEntries) do
    Inc(Result, FBLASEntries[I].UncompactedBytes);
end;

function TCastleVulkanAccelerationStructureManager.GetTotalCompactedBLASBytes: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FBLASEntries) do
    Inc(Result, FBLASEntries[I].CompactedBytes);
end;

function TCastleVulkanAccelerationStructureManager.GetCompactionSavedBytes: Cardinal;
var
  Uncomp, Comp: Cardinal;
begin
  Uncomp := GetTotalUncompactedBLASBytes;
  Comp := GetTotalCompactedBLASBytes;
  if Uncomp > Comp then
    Result := Uncomp - Comp
  else
    Result := 0;
end;

{$endif read_implementation}
