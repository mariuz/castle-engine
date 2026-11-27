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
  TVulkanDescriptorPoolAllocator = class
  private
    FDevice: VkDevice;
    FAllowFreeIndividualSets: Boolean;
    FAllowUpdateAfterBind: Boolean;
    FSupportsAccelerationStructure: Boolean;
    FInitialMaxSets: Cardinal;
    FMaxSetsCap: Cardinal;
    FCurrentMaxSets: Cardinal;
    FCurrentPage: TVulkanDescriptorPoolPage;
    FHasCurrentPage: Boolean;
    FReadyPools: array of TVulkanDescriptorPoolPage;
    FFullPools: array of TVulkanDescriptorPoolPage;
    FTotalPoolCount: Cardinal;
    FTotalAllocatedSetCount: Cardinal;
    FResetCount: Cardinal;
    FNextSimulatedSetId: Cardinal;
    FForceNextAllocationError: VkResult;

    function CreateNewPoolPage(const AMaxSets: Cardinal): TVulkanDescriptorPoolPage;
    procedure AcquireNextReadyOrNewPage;
    function GetReadyPoolCount: Cardinal;
    function GetFullPoolCount: Cardinal;
    function GetCurrentPoolHandle: VkDescriptorPool;
  public
    constructor Create(const ADevice: VkDevice;
      const AInitialMaxSets: Cardinal = 1024;
      const AAllowFreeIndividualSets: Boolean = False;
      const AMaxSetsCap: Cardinal = 4096;
      const AAllowUpdateAfterBind: Boolean = False;
      const ASupportsAccelerationStructure: Boolean = False);
    destructor Destroy; override;

    { Allocates a VkDescriptorSet from the current pool page, growing the pool chain
      automatically on VK_ERROR_OUT_OF_POOL_MEMORY / VK_ERROR_FRAGMENTED_POOL. }
    function AllocateDescriptorSet(const ASetLayout: VkDescriptorSetLayout;
      out AOwnerPool: VkDescriptorPool): VkDescriptorSet;

    { Frees an individual persistent descriptor set (when AllowFreeIndividualSets = True). }
    procedure FreeDescriptorSet(const AOwnerPool: VkDescriptorPool;
      const ASet: VkDescriptorSet);

    { Resets all pool pages in O(1) per page via vkResetDescriptorPool and moves
      all full pages back into the ready list for zero-allocation frame reuse. }
    procedure ResetPools;

    property Device: VkDevice read FDevice;
    property AllowFreeIndividualSets: Boolean read FAllowFreeIndividualSets;
    property AllowUpdateAfterBind: Boolean read FAllowUpdateAfterBind write FAllowUpdateAfterBind;
    property SupportsAccelerationStructure: Boolean read FSupportsAccelerationStructure write FSupportsAccelerationStructure;
    property InitialMaxSets: Cardinal read FInitialMaxSets;
    property MaxSetsCap: Cardinal read FMaxSetsCap;
    property NextPoolMaxSets: Cardinal read FCurrentMaxSets;
    property CurrentPool: VkDescriptorPool read GetCurrentPoolHandle;
    property TotalPoolCount: Cardinal read FTotalPoolCount;
    property ReadyPoolCount: Cardinal read GetReadyPoolCount;
    property FullPoolCount: Cardinal read GetFullPoolCount;
    property TotalAllocatedSetCount: Cardinal read FTotalAllocatedSetCount;
    property ResetCount: Cardinal read FResetCount;
    property ForceNextAllocationError: VkResult read FForceNextAllocationError write FForceNextAllocationError;
  end;

  { -------------------------------------------------------------------------- }
  { Bindless Texture & Sampler Indexing Manager (VK_EXT_descriptor_indexing)   }
  { -------------------------------------------------------------------------- }

  TVulkanBindlessTextureSlot = record
    Texture: TVulkanRHITexture;
    Sampler: TVulkanRHISampler;
    InUse: Boolean;
    Dirty: Boolean;
  end;

  { Manages a global bindless combined-image-sampler array (Set 1, Binding 0)
    backed by VK_EXT_descriptor_indexing / Vulkan 1.2 core descriptor indexing
    (PARTIALLY_BOUND_BIT | UPDATE_UNUSED_WHILE_PENDING_BIT | optional UPDATE_AFTER_BIND_BIT).
    Deduplicates (Texture, Sampler) registrations, recycles freed slot indices via an
    O(1) free-list when textures or samplers are destroyed, and batches descriptor writes. }
  TCastleVulkanBindlessTextureManager = class
  private
    FDevice: TVulkanRHIDevice;
    FCapacity: Cardinal;
    FSupportsUpdateAfterBind: Boolean;
    FBindlessPool: VkDescriptorPool;
    FLayout: TVulkanRHIDescriptorSetLayout;
    FDescriptorSet: TVulkanRHIDescriptorSet;
    FMaterialSSBOBuffer: TRHIBuffer;
    FOwnsMaterialSSBOBuffer: Boolean;
    FMaterialEntries: array of TCastleBindlessMaterialEntry;
    FMaterialTableDirty: Boolean;
    FMaterialFlushCount: Cardinal;
    FSlots: array of TVulkanBindlessTextureSlot;
    FFreeSlots: array of Cardinal;
    FActiveSlotCount: Cardinal;
    FPendingWriteCount: Cardinal;
    FTotalRegistrations: Cardinal;
    FDeduplicatedHits: Cardinal;
    FRecycledSlotReuses: Cardinal;
    FTotalFlushedWrites: Cardinal;

    procedure EnsureDescriptorSetCreated;
    function GetFreeSlotCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ACapacity: Cardinal = 4096;
      const ASupportsUpdateAfterBind: Boolean = True);
    destructor Destroy; override;

    { Registers a (Texture, Sampler) pair in the global bindless descriptor array
      and returns its 0-based bindless slot index. Deduplicates existing pairs and
      reuses recycled slots from FFreeSlots before growing FSlots. }
    function RegisterTexture(const ATexture: TRHITexture;
      const ASampler: TRHISampler): Cardinal;

    { Looks up the slot index of an already-registered (Texture, Sampler) pair,
      returning True if found. }
    function TryGetTextureIndex(const ATexture: TRHITexture;
      const ASampler: TRHISampler; out AIndex: Cardinal): Boolean;

    { Unregisters a specific slot index and pushes it onto the free-list for reuse. }
    procedure UnregisterSlot(const ASlotIndex: Cardinal);

    { Unregisters all slots referencing ATexture (called automatically by TVulkanRHITexture.Destroy)
      and recycles their slot indices into the free-list. Returns number of slots freed. }
    function UnregisterTexture(const ATexture: TRHITexture): Cardinal;

    { Unregisters all slots referencing ASampler (called automatically by TVulkanRHISampler.Destroy). }
    function UnregisterSampler(const ASampler: TRHISampler): Cardinal;

    { Binds a Material SSBO (Set 1, Binding 1) containing TCastleBindlessMaterialEntry records
      alongside the bindless texture array in Set 1, Binding 0. }
    procedure SetMaterialStorageBuffer(const ASSBOBuffer: TRHIBuffer;
      const AOffset: PtrUInt = 0; const ARange: PtrUInt = 0);

    { Registers or updates a TCastleBindlessMaterialEntry in the managed Material SSBO table
      (Set 1, Binding 1). When AAlreadyRegistered is False, appends a new entry and sets
      AMaterialIndex to the allocated 0-based index and AAlreadyRegistered to True;
      otherwise updates the existing entry at AMaterialIndex in-place. }
    function RegisterOrUpdateMaterial(var AMaterialIndex: Cardinal;
      var AAlreadyRegistered: Boolean;
      const AEntry: TCastleBindlessMaterialEntry): Cardinal;

    { Returns the CPU-side TCastleBindlessMaterialEntry at AIndex (or zeroed if out of bounds). }
    function GetMaterialEntry(const AIndex: Cardinal): TCastleBindlessMaterialEntry;

    { Returns the number of registered materials in the CPU-side Material SSBO table. }
    function GetMaterialCount: Cardinal;

    { Uploads the CPU-side FMaterialEntries table into FMaterialSSBOBuffer (allocating or
      growing an owned Storage+TransferDst buffer as needed) and binds it to Set 1, Binding 1. }
    function FlushMaterialTableToSSBO: Boolean;

    { Batches all dirty slot bindings into FDescriptorSet via BindTextureAtIndex + Update,
      and flushes FMaterialEntries to FMaterialSSBOBuffer if FMaterialTableDirty is True.
      Returns the number of descriptor writes committed in this flush. }
    function FlushPendingUpdates: Cardinal;

    property Device: TVulkanRHIDevice read FDevice;
    property Capacity: Cardinal read FCapacity;
    property SupportsUpdateAfterBind: Boolean read FSupportsUpdateAfterBind;
    property BindlessPool: VkDescriptorPool read FBindlessPool;
    property Layout: TVulkanRHIDescriptorSetLayout read FLayout;
    property DescriptorSet: TVulkanRHIDescriptorSet read FDescriptorSet;
    property MaterialSSBOBuffer: TRHIBuffer read FMaterialSSBOBuffer;
    property MaterialCount: Cardinal read GetMaterialCount;
    property MaterialFlushCount: Cardinal read FMaterialFlushCount;
    property ActiveSlotCount: Cardinal read FActiveSlotCount;
    property FreeSlotCount: Cardinal read GetFreeSlotCount;
    property PendingWriteCount: Cardinal read FPendingWriteCount;
    property TotalRegistrations: Cardinal read FTotalRegistrations;
    property DeduplicatedHits: Cardinal read FDeduplicatedHits;
    property RecycledSlotReuses: Cardinal read FRecycledSlotReuses;
    property TotalFlushedWrites: Cardinal read FTotalFlushedWrites;
  end;

  { -------------------------------------------------------------------------- }
  { Asynchronous Staging Upload Ring Buffer & Dedicated DMA Transfer Queue     }
  { -------------------------------------------------------------------------- }

  TVulkanStagedBufferCopy = record
    SrcBuffer: VkBuffer;
    DstBuffer: TVulkanRHIBuffer;
    Region: VkBufferCopy;
  end;

  TVulkanStagedImageCopy = record
    SrcBuffer: VkBuffer;
    DstTexture: TVulkanRHITexture;
    Region: VkBufferImageCopy;
    MipLevel: Cardinal;
    ArrayLayer: Cardinal;
    GenerateMipmaps: Boolean;
  end;

  TVulkanStagingOverflowChunk = record
    Buffer: VkBuffer;
    Allocation: TVulkanMemoryAllocation;
  end;

  { Batches host-to-device buffer and texture uploads into per-frame persistently
    mapped staging ring buffers, eliminating synchronous per-upload vkQueueWaitIdle
    stalls. Supports both unified graphics+transfer queues and dedicated DMA
    transfer queues (VK_QUEUE_TRANSFER_BIT) with explicit queue-family ownership
    release/acquire barriers. }
  TCastleVulkanStagingUploader = class
  private
    FDevice: TVulkanRHIDevice;
    FRingCapacityPerFrame: VkDeviceSize;
    FRingBuffers: array[0 .. MaxFramesInFlight - 1] of VkBuffer;
    FRingAllocations: array[0 .. MaxFramesInFlight - 1] of TVulkanMemoryAllocation;
    FRingWriteOffsets: array[0 .. MaxFramesInFlight - 1] of VkDeviceSize;
    FOverflowChunks: array[0 .. MaxFramesInFlight - 1] of array of TVulkanStagingOverflowChunk;
    FPendingBufferCopies: array of TVulkanStagedBufferCopy;
    FPendingImageCopies: array of TVulkanStagedImageCopy;
    FGraphicsQueueFamily: Cardinal;
    FTransferQueueFamily: Cardinal;
    FUseDedicatedTransferQueue: Boolean;
    FTransferPools: array[0 .. MaxFramesInFlight - 1] of VkCommandPool;
    FTransferPoolCmdBuffers: array[0 .. MaxFramesInFlight - 1] of array of VkCommandBuffer;
    FTransferPoolUsedCounts: array[0 .. MaxFramesInFlight - 1] of Cardinal;
    FTransferBinarySemaphores: array[0 .. MaxFramesInFlight - 1] of VkSemaphore;
    FTransferTimelineSemaphore: TCastleVulkanTimelineSemaphore;
    FPendingBinaryWaitSemaphore: VkSemaphore;
    FLastSubmittedTimelineValue: UInt64;
    FPendingGraphicsWaitTimelineValue: UInt64;
    FPendingAcquireBuffers: array of TVulkanStagedBufferCopy;
    FPendingAcquireImages: array of TVulkanStagedImageCopy;
    FPendingPostTransferMipmaps: array of TVulkanRHITexture;
    FTotalAsyncSubmissions: Cardinal;
    FAsyncTransferEnabled: Boolean;
    FTotalBufferUploads: Cardinal;
    FTotalImageUploads: Cardinal;
    FTotalBatchedFlushes: Cardinal;
    FTotalStagedBytes: UInt64;
    FQueueOwnershipTransferCount: Cardinal;
    FOverflowChunkCount: Cardinal;

    function EnsureRingBufferForSlot(const AFrameSlot: Cardinal): Boolean;
    function AcquireTransferCommandBuffer(const AFrameSlot: Cardinal): VkCommandBuffer;
    function EnsureTransferBinarySemaphore(const AFrameSlot: Cardinal): VkSemaphore;
    function GetTransferTimelineSemaphore: TCastleVulkanTimelineSemaphore;
    function AllocateStagingSlice(const ASize, AAlignment: VkDeviceSize;
      out ASrcBuffer: VkBuffer; out ASrcOffset: VkDeviceSize;
      out AAllocation: TVulkanMemoryAllocation): Pointer;
    function GetPendingBufferCopyCount: Cardinal;
    function GetPendingImageCopyCount: Cardinal;
    function GetCurrentFrameWriteOffset: VkDeviceSize;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ARingCapacityPerFrame: VkDeviceSize = 8 * 1024 * 1024);
    destructor Destroy; override;

    { Configures queue families for unified vs. dedicated DMA transfer queue execution. }
    procedure ConfigureTransferQueue(const AGraphicsQueueFamily, ATransferQueueFamily: Cardinal;
      const AUseDedicatedTransferQueue: Boolean);

    { Reclaims staging ring buffer space and frees any overflow chunks for AFrameSlot
      once that frame slot's VkFence has signaled completion. }
    procedure ReclaimFrameSlot(const AFrameSlot: Cardinal);

    { Enqueues a buffer upload into the current frame's staging ring buffer without stalling. }
    procedure EnqueueBufferUpload(const ADstBuffer: TVulkanRHIBuffer;
      const AData; const ASize, ADstOffset: VkDeviceSize);

    { Enqueues a texture mip/layer upload into the current frame's staging ring buffer without stalling. }
    procedure EnqueueImageUpload(const ADstTexture: TVulkanRHITexture;
      const AData: Pointer; const ADataSize: VkDeviceSize;
      const AWidth, AHeight: Cardinal;
      const AMipLevel, AArrayLayer: Cardinal;
      const AGenerateMipmaps: Boolean = False);

    { Removes any pending copy commands targeting a buffer or texture being destroyed. }
    procedure CancelPendingUploadsForBuffer(const ABuffer: TVulkanRHIBuffer);
    procedure CancelPendingUploadsForTexture(const ATexture: TVulkanRHITexture);

    { Flushes all pending buffer-to-buffer and buffer-to-image copies + layout/queue-ownership
      barriers in a single batch into ACommandList (or a one-shot submission if ACommandList = nil).
      Returns total number of copy operations flushed. }
    function FlushPendingUploads(const ACommandList: TVulkanRHICommandList = nil): Cardinal;

    { Submits all pending buffer-to-buffer and buffer-to-image copies asynchronously onto
      FDevice.TransferQueue without stalling CPU or Graphics Queue execution, signaling
      TransferTimelineSemaphore (VkTimelineSemaphoreSubmitInfo) with the returned 64-bit
      counter value and queueing post-transfer queue-ownership acquire barriers + mipmap
      blits for the next Graphics command buffer submission. }
    function SubmitAsyncUploads: UInt64;

    { Records any pending post-transfer queue-family ownership acquire barriers and
      graphics-only mipmap blits onto ACommandList. Returns number of barriers/mipmaps applied. }
    function ApplyPendingGraphicsAcquireBarriers(
      const ACommandList: TVulkanRHICommandList): Cardinal;

    { Consumes any pending timeline/binary semaphore wait required by the next Graphics Queue
      vkQueueSubmit so GPU vertex/fragment stages wait for in-flight Transfer Queue copies. }
    function ConsumePendingGraphicsWait(out ATimelineSemaphore: VkSemaphore;
      out AWaitValue: UInt64; out ABinarySemaphore: VkSemaphore): Boolean;

    { Waits on the host for all submitted asynchronous Transfer Queue uploads to finish. }
    procedure WaitForAsyncUploads(const ATimeoutNs: UInt64 = High(UInt64));

    property RingCapacityPerFrame: VkDeviceSize read FRingCapacityPerFrame write FRingCapacityPerFrame;
    property AsyncTransferEnabled: Boolean read FAsyncTransferEnabled write FAsyncTransferEnabled;
    property TransferTimelineSemaphore: TCastleVulkanTimelineSemaphore read GetTransferTimelineSemaphore;
    property LastSubmittedTimelineValue: UInt64 read FLastSubmittedTimelineValue;
    property PendingGraphicsWaitTimelineValue: UInt64 read FPendingGraphicsWaitTimelineValue;
    property TotalAsyncSubmissions: Cardinal read FTotalAsyncSubmissions;
    property CurrentFrameWriteOffset: VkDeviceSize read GetCurrentFrameWriteOffset;
    property PendingBufferCopyCount: Cardinal read GetPendingBufferCopyCount;
    property PendingImageCopyCount: Cardinal read GetPendingImageCopyCount;
    property GraphicsQueueFamily: Cardinal read FGraphicsQueueFamily;
    property TransferQueueFamily: Cardinal read FTransferQueueFamily;
    property UseDedicatedTransferQueue: Boolean read FUseDedicatedTransferQueue;
    property TotalBufferUploads: Cardinal read FTotalBufferUploads;
    property TotalImageUploads: Cardinal read FTotalImageUploads;
    property TotalBatchedFlushes: Cardinal read FTotalBatchedFlushes;
    property TotalStagedBytes: UInt64 read FTotalStagedBytes;
    property QueueOwnershipTransferCount: Cardinal read FQueueOwnershipTransferCount;
    property OverflowChunkCount: Cardinal read FOverflowChunkCount;
  end;

  { -------------------------------------------------------------------------- }
  { Multi-Threaded Secondary Command Recording Pool (VkCommandPool per Worker) }
  { -------------------------------------------------------------------------- }

  TVulkanCommandListArray = array of TRHICommandList;

  TVulkanParallelWorkerTaskProc = procedure(const AWorkerIndex: Cardinal;
    const ACommandList: TVulkanRHICommandList) of object;

  TVulkanWorkerFrameSlot = record
    CommandPool: VkCommandPool;
    CommandLists: array of TVulkanRHICommandList;
    UsedCount: Cardinal;
  end;

  { Manages per-worker-thread, per-frame-in-flight VkCommandPool instances and a
    reusable OS worker thread pool so multiple CPU threads can record secondary
    TVulkanRHICommandList instances in parallel with zero lock contention and O(1)
    vkResetCommandPool bulk reclamation per frame slot. }
  TCastleVulkanWorkerCommandPoolManager = class
  private
    FDevice: TVulkanRHIDevice;
    FWorkerCount: Cardinal;
    FUseWorkerThreads: Boolean;
    FThreadsSpawned: Boolean;
    FWorkerSlots: array of array[0 .. MaxFramesInFlight - 1] of TVulkanWorkerFrameSlot;
    FWorkerThreads: array of TThread;
    FLastWorkerThreadIds: array of TThreadID;
    FTotalPoolResets: Cardinal;
    FTotalParallelDispatches: Cardinal;
    FTotalSecondaryListsRecorded: Cardinal;

    procedure EnsureWorkerPoolsAllocated;
    function EnsureWorkerThreadsSpawned: Boolean;
    procedure ShutdownWorkerThreads;
    procedure DestroyWorkerPools;
    procedure SetWorkerCount(const AValue: Cardinal);
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const AWorkerCount: Cardinal = 4);
    destructor Destroy; override;

    { Bulk-resets all worker VkCommandPools for AFrameSlot in O(1) once that frame's
      VkFence has signaled completion, making all secondary command lists reusable. }
    procedure ResetFrameSlot(const AFrameSlot: Cardinal);

    { Acquires a secondary TVulkanRHICommandList owned by AWorkerIndex for the current
      frame-in-flight slot, allocating from that worker's dedicated VkCommandPool. }
    function AcquireWorkerSecondaryCommandList(
      const AWorkerIndex: Cardinal): TVulkanRHICommandList;

    { Dispatches ATaskCount parallel recording tasks across up to WorkerCount threads,
      each receiving its own dedicated-pool secondary TVulkanRHICommandList, and returns
      the ordered ARecordedLists array ready for PrimaryCmd.ExecuteSecondaryCommandsInPass. }
    function ExecuteParallelRecording(const ATaskCount: Cardinal;
      const ATaskProc: TVulkanParallelWorkerTaskProc;
      out ARecordedLists: TVulkanCommandListArray): Cardinal;

    function GetWorkerCommandPool(const AWorkerIndex, AFrameSlot: Cardinal): VkCommandPool;
    function GetWorkerLastThreadId(const AWorkerIndex: Cardinal): TThreadID;

    property Device: TVulkanRHIDevice read FDevice;
    property WorkerCount: Cardinal read FWorkerCount write SetWorkerCount;
    property UseWorkerThreads: Boolean read FUseWorkerThreads write FUseWorkerThreads;
    property ThreadsSpawned: Boolean read FThreadsSpawned;
    property TotalPoolResets: Cardinal read FTotalPoolResets;
    property TotalParallelDispatches: Cardinal read FTotalParallelDispatches;
    property TotalSecondaryListsRecorded: Cardinal read FTotalSecondaryListsRecorded;
  end;

  { -------------------------------------------------------------------------- }
  { Timeline Semaphore & GPU Timestamp Profiler (Phases 6.6 & 6.7)             }
  { -------------------------------------------------------------------------- }

  { Monotonically increasing 64-bit timeline semaphore (VK_KHR_timeline_semaphore / Vulkan 1.2 Core)
    for host/device and cross-queue (async transfer / compute / graphics) synchronization. }
  TCastleVulkanTimelineSemaphore = class
  private
    FDevice: TVulkanRHIDevice;
    FHandle: VkSemaphore;
    FCounterValue: UInt64;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const AInitialValue: UInt64 = 0);
    destructor Destroy; override;

    procedure Signal(const AValue: UInt64);
    function Wait(const AValue: UInt64; const ATimeoutNs: UInt64 = High(UInt64)): Boolean;
    function GetCounterValue: UInt64;

    property Handle: VkSemaphore read FHandle;
  end;

  TVulkanTimestampPassEntry = record
    PassName: String;
    BeginQueryIndex: Cardinal;
    EndQueryIndex: Cardinal;
    CompletedGpuTimeMs: Single;
  end;

  { Per-frame non-stalling GPU pass profiler backed by MaxFramesInFlight VkQueryPool
    instances (VK_QUERY_TYPE_TIMESTAMP). Reads back N-frames-ago timestamp pairs at
    BeginFrame and converts GPU tick deltas into milliseconds via timestampPeriod. }
  TCastleVulkanTimestampProfiler = class
  private
    FDevice: TVulkanRHIDevice;
    FMaxPassesPerFrame: Cardinal;
    FPools: array[0 .. MaxFramesInFlight - 1] of TVulkanRHIQueryPool;
    FFramePasses: array[0 .. MaxFramesInFlight - 1] of array of TVulkanTimestampPassEntry;
    FCompletedPasses: array of TVulkanTimestampPassEntry;
    FLastFrameTotalGpuTimeMs: Single;
    FCurrentSlot: Cardinal;
    function GetCompletedPassCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const AMaxPassesPerFrame: Cardinal = 32);
    destructor Destroy; override;

    { Reads back completed timestamps from the frame slot about to be reused and
      resets its VkQueryPool for new pass recordings. }
    procedure BeginFrame(const ACmd: TRHICommandList; const AFrameIndex: Cardinal);

    { Records a start timestamp for APassName and returns its pass index for EndPass. }
    function BeginPass(const ACmd: TRHICommandList; const APassName: String): Integer;

    { Records an end timestamp for APassIndex. }
    procedure EndPass(const ACmd: TRHICommandList; const APassIndex: Integer);

    { Returns the most recently completed GPU execution time (in ms) for APassName, or 0.0. }
    function GetPassTimeMs(const APassName: String): Single;

    { Returns the VkQueryPool for a specific frame slot (0 .. MaxFramesInFlight - 1). }
    function GetQueryPoolForSlot(const AFrameSlot: Cardinal): TVulkanRHIQueryPool;

    property MaxPassesPerFrame: Cardinal read FMaxPassesPerFrame;
    property CompletedPassCount: Cardinal read GetCompletedPassCount;
    property LastFrameTotalGpuTimeMs: Single read FLastFrameTotalGpuTimeMs;
  end;

  { -------------------------------------------------------------------------- }
  { GPU-Driven Compute Frustum & Distance Culler (Phase 7.2)                   }
  { -------------------------------------------------------------------------- }

  { Evaluates per-instance bounding spheres against 6 camera frustum planes and an optional
    distance threshold via TRHIComputePipeline, writing or compacting
    TRHIDrawIndexedIndirectCommand entries and atomic visibility counters for DrawIndexedIndirect,
    and transitioning the indirect buffer via TransitionBuffer(rbsShaderWrite -> rbsIndirectRead). }
  TCastleVulkanComputeCuller = class
  private
    FDevice: TVulkanRHIDevice;
    FMaxInstances: Cardinal;
    FWorkgroupSizeX: Cardinal;
    FCullingUniforms: TCastleGpuCullingUniformBlock;
    FCullingUniformBuffer: TRHIBuffer;
    FInstanceInputBuffer: TRHIBuffer;
    FIndirectOutputBuffer: TRHIBuffer;
    FVisibilityOutputBuffer: TRHIBuffer;
    FDescriptorLayout: TRHIDescriptorSetLayout;
    FDescriptorSet: TRHIDescriptorSet;
    FComputeShader: TRHIShaderModule;
    FComputePipeline: TRHIComputePipeline;
    FHiZPyramidTexture: TRHITexture;
    FHiZSampler: TRHISampler;
    FHiZDescriptorLayout: TRHIDescriptorSetLayout;
    FHiZDescriptorSet: TRHIDescriptorSet;
    FHiZDownsampleShader: TRHIShaderModule;
    FHiZDownsamplePipeline: TRHIComputePipeline;
    FHiZMipLevels: Cardinal;
    FHiZWidth: Cardinal;
    FHiZHeight: Cardinal;
    FHiZMipWidths: array of Cardinal;
    FHiZMipHeights: array of Cardinal;
    FHiZMipChain: array of array of Single;
    FHiZViewProjMatrix: TMatrix4;
    FHiZCullingEnabled: Boolean;
    FHiZCulledInstanceCount: Cardinal;
    FHiZDownsampleDispatches: Cardinal;
    FUploadedInstances: array of TCastleGpuCullingInstance;
    FTotalDispatches: Cardinal;
    FLastUploadedInstanceCount: Cardinal;
    FLastVisibleInstanceCount: Cardinal;
    FLastCulledInstanceCount: Cardinal;
    procedure EnsureResourcesCreated;
    procedure EnsureHiZPipelineCreated;
    function IsInstanceVisibleOnCpu(const AInst: TCastleGpuCullingInstance;
      out AWasCulledByHiZ: Boolean): Boolean;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const AMaxInstances: Cardinal = 4096;
      const AWorkgroupSizeX: Cardinal = 64);
    destructor Destroy; override;

    { Sets the 6 camera frustum planes from a CGE TFrustum and optional max distance threshold. }
    procedure SetFrustum(const AFrustum: TFrustum; const ACameraPos: TVector3;
      const AMaxDistance: Single = 0.0);

    { Sets the 6 frustum planes (each vec4(A, B, C, D) with dot(ABC, P) + D >= 0 inside)
      and optional max distance threshold (0 = disabled). }
    procedure SetFrustumPlanes(const APlanes: array of TVector4;
      const ACameraPos: TVector3; const AMaxDistance: Single = 0.0);

    { Builds the Hierarchical Z (Hi-Z) max-depth pyramid texture (pfR32_Float full mip chain)
      from Level 0 depth data (width x height floats in [0..1], or 1.0 far depth if nil) by
      dispatching the conservative 2x2 max-depth compute reduction shader across all mip levels
      with per-mip barrier transitions. Returns the total number of mip levels generated. }
    function BuildHiZPyramid(const ACmd: TRHICommandList;
      const AWidth, AHeight: Cardinal;
      const ALevel0DepthData: PSingle = nil): Cardinal;

    { Returns the conservative max-depth value in [0..1] at (AMipLevel, AX, AY) of the Hi-Z pyramid. }
    function SampleHiZMipMaxDepth(const AMipLevel, AX, AY: Cardinal): Single;

    { Configures the view-projection matrix used for screen-space bounding-sphere Hi-Z occlusion
      testing and enables/disables Hi-Z occlusion culling in DispatchCulling. }
    procedure SetHiZProjection(const AViewProjMatrix: TMatrix4;
      const AEnableHiZCulling: Boolean = True);

    { Uploads an array of instance bounding spheres/AABBs and indirect draw parameters to the input SSBO. }
    procedure UploadInstances(const AInstances: array of TCastleGpuCullingInstance);

    { Dispatches the GPU compute culling shader for AInstanceCount instances, transitions
      IndirectOutputBuffer from rbsShaderWrite to rbsIndirectRead, and returns the number
      of workgroups dispatched. When ACompactDraws = True, only visible draws are compacted
      into [0 .. LastVisibleInstanceCount - 1]; when False, all AInstanceCount slots are written
      with instanceCount = 0 for culled instances. }
    function DispatchCulling(const ACmd: TRHICommandList;
      const AInstanceCount: Cardinal;
      const ACompactDraws: Boolean = False): Cardinal;

    { Records a GPU-driven multi-draw indirect command (vkCmdDrawIndexedIndirectCount /
      DrawIndexedIndirectCount) reading compacted commands from IndirectOutputBuffer and
      the atomic visible draw count from offset 0 of VisibilityOutputBuffer without CPU readback.
      Returns the effective draw count bounded by AMaxDrawCount (or LastUploadedInstanceCount if 0). }
    function RecordIndirectDraw(const ACmd: TRHICommandList;
      const AMaxDrawCount: Cardinal = 0): Cardinal;

    { Reads back the atomic visible instance count from VisibilityOutputBuffer. }
    function ReadBackVisibleCount: Cardinal;

    { Reads back the per-instance visibility flag (1 = visible, 0 = culled) for AIndex. }
    function ReadBackVisibilityFlag(const AIndex: Cardinal): Cardinal;

    { Reads back the generated TRHIDrawIndexedIndirectCommand at AIndex from IndirectOutputBuffer. }
    function ReadBackIndirectCommand(const AIndex: Cardinal): TRHIDrawIndexedIndirectCommand;

    property MaxInstances: Cardinal read FMaxInstances;
    property WorkgroupSizeX: Cardinal read FWorkgroupSizeX;
    property CullingUniformBuffer: TRHIBuffer read FCullingUniformBuffer;
    property InstanceInputBuffer: TRHIBuffer read FInstanceInputBuffer;
    property IndirectOutputBuffer: TRHIBuffer read FIndirectOutputBuffer;
    property VisibilityOutputBuffer: TRHIBuffer read FVisibilityOutputBuffer;
    property ComputePipeline: TRHIComputePipeline read FComputePipeline;
    property HiZPyramidTexture: TRHITexture read FHiZPyramidTexture;
    property HiZDownsamplePipeline: TRHIComputePipeline read FHiZDownsamplePipeline;
    property HiZMipLevels: Cardinal read FHiZMipLevels;
    property HiZWidth: Cardinal read FHiZWidth;
    property HiZHeight: Cardinal read FHiZHeight;
    property HiZCullingEnabled: Boolean read FHiZCullingEnabled;
    property HiZCulledInstanceCount: Cardinal read FHiZCulledInstanceCount;
    property HiZDownsampleDispatches: Cardinal read FHiZDownsampleDispatches;
    property TotalDispatches: Cardinal read FTotalDispatches;
    property LastUploadedInstanceCount: Cardinal read FLastUploadedInstanceCount;
    property LastVisibleInstanceCount: Cardinal read FLastVisibleInstanceCount;
    property LastCulledInstanceCount: Cardinal read FLastCulledInstanceCount;
  end;

  { -------------------------------------------------------------------------- }
  { Compute IBL BRDF LUT & Environment Cubemap Prefilter Generator (Phase 13.2)}
  { -------------------------------------------------------------------------- }

  { 9-band L2 Spherical Harmonics RGB coefficients for diffuse environment irradiance }
  TCastleSH9Coefficients = array[0..8] of TVector3;

  { Generates the 2D Split-Sum GGX BRDF Integration LUT via compute shader dispatch,
    prefilters environment cubemap mip chains across roughness levels [0..1], and
    projects environment cubemaps onto L2 Spherical Harmonics (9 coefficients) for
    real-time PBR Image-Based Lighting. }
  TCastleVulkanIBLGenerator = class
  private
    FDevice: TVulkanRHIDevice;
    FBrdfLutTexture: TVulkanRHITexture;
    FBrdfLutSampler: TRHISampler;
    FBrdfLutDescriptorLayout: TRHIDescriptorSetLayout;
    FBrdfLutDescriptorSet: TRHIDescriptorSet;
    FBrdfLutComputeShader: TRHIShaderModule;
    FBrdfLutComputePipeline: TRHIComputePipeline;
    FBrdfLutSize: Cardinal;
    FBrdfLutSampleCount: Cardinal;
    FBrdfLutData: array of TVector2;
    FPrefilteredEnvCubemap: TVulkanRHITexture;
    FPrefilteredEnvMipLevels: Cardinal;
    FPrefilteredEnvBaseSize: Cardinal;
    FPrefilteredEnvFaceColors: array[0..5] of array of TVector3;
    FIrradianceEnvCubemap: TVulkanRHITexture;
    FIrradianceEnvSize: Cardinal;
    FInternalSourceCubemap: TVulkanRHITexture;
    FEnvConvolveSampler: TRHISampler;
    FEnvConvolveLayout: TRHIDescriptorSetLayout;
    FPrefilterComputeShader: TRHIShaderModule;
    FPrefilterComputePipeline: TRHIComputePipeline;
    FIrradianceComputeShader: TRHIShaderModule;
    FIrradianceComputePipeline: TRHIComputePipeline;
    FPrefilterDescSets: array of TRHIDescriptorSet;
    FIrradianceDescSets: array of TRHIDescriptorSet;
    FIrradianceSH9: TCastleSH9Coefficients;
    FTotalBrdfLutDispatches: Cardinal;
    FTotalEnvPrefilterPasses: Cardinal;
    FTotalIrradianceDispatches: Cardinal;
    procedure EnsureBrdfLutPipelineCreated;
    procedure EnsureEnvConvolvePipelinesCreated;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Van der Corput base-2 radical inverse in [0..1) for Hammersley sequence. }
    class function RadicalInverseVdC(ABits: Cardinal): Single; static;

    { Evaluates the Split-Sum GGX BRDF integral (Scale, Bias) for (ANdotV, ARoughness)
      using ASampleCount Hammersley quasi-Monte Carlo importance samples. }
    class function IntegrateBRDFPoint(const ANdotV, ARoughness: Single;
      const ASampleCount: Cardinal = 32): TVector2; static;

    { Dispatches the GLSL 450 BRDF LUT compute pipeline to generate a 2D Split-Sum
      BRDF integration lookup texture of ASize x ASize texels, transitioning it to
      rsShaderRead for fragment shader binding at Set 1, Binding 6. }
    function GenerateBRDFIntegrationLUT(const ACmd: TRHICommandList;
      const ASize: Cardinal = 32;
      const ASampleCount: Cardinal = 32): TVulkanRHITexture;

    { Samples the generated 2D BRDF Integration LUT at normalized (ANdotV, ARoughness) in [0..1]. }
    function SampleBRDFLUT(const ANdotV, ARoughness: Single): TVector2;

    { Creates a mipmapped cubemap texture (tdCube, 6 faces, MipLevels = Floor(Log2(ABaseSize)) + 1)
      and prefilters each mip level across roughness [0..1] from the 6 base cubemap face colors
      (+X, -X, +Y, -Y, +Z, -Z), while also computing L2 Spherical Harmonics diffuse irradiance. }
    function PrefilterEnvironmentCubemap(const ACmd: TRHICommandList;
      const AFaceColors: array of TVector3;
      const ABaseSize: Cardinal = 16): TVulkanRHITexture;

    { Returns the prefiltered specular environment radiance for AFaceIndex (0..5) at AMipLevel. }
    function SamplePrefilteredEnvironment(const AFaceIndex, AMipLevel: Cardinal): TVector3;

    { Projects 6 cubemap face radiances (+X, -X, +Y, -Y, +Z, -Z) onto 9 L2 Spherical Harmonics
      coefficients (Y_00, Y_1-1, Y_10, Y_11, Y_2-2, Y_2-1, Y_20, Y_21, Y_22). }
    procedure ComputeDiffuseIrradianceSH(const AFaceColors: array of TVector3;
      out ASH9: TCastleSH9Coefficients);

    { Evaluates diffuse Lambertian irradiance for AWorldNormal from the precomputed L2 SH9 coefficients. }
    function EvaluateIrradianceSH(const AWorldNormal: TVector3): TVector3;

    { Convolves an arbitrary GPU cubemap texture (ASourceEnvCubemap) on the GPU into:
      1. Specular GGX importance-sampled mipmapped PrefilteredEnvCubemap (APrefilterBaseSize, all mip levels x 6 faces)
      2. Cosine-weighted Lambertian diffuse IrradianceEnvCubemap (AIrradianceSize x 6 faces)
      3. 2D Split-Sum GGX BRDF Integration LUT (if not already generated). }
    function GenerateEnvironmentIBLFromCubemap(const ACmd: TRHICommandList;
      const ASourceEnvCubemap: TRHITexture;
      const APrefilterBaseSize: Cardinal = 16;
      const AIrradianceSize: Cardinal = 8;
      const ASampleCount: Cardinal = 32): TVulkanRHITexture;

    property BrdfLutTexture: TVulkanRHITexture read FBrdfLutTexture;
    property BrdfLutSampler: TRHISampler read FBrdfLutSampler;
    property BrdfLutComputePipeline: TRHIComputePipeline read FBrdfLutComputePipeline;
    property BrdfLutSize: Cardinal read FBrdfLutSize;
    property PrefilteredEnvCubemap: TVulkanRHITexture read FPrefilteredEnvCubemap;
    property PrefilteredEnvMipLevels: Cardinal read FPrefilteredEnvMipLevels;
    property PrefilteredEnvBaseSize: Cardinal read FPrefilteredEnvBaseSize;
    property IrradianceEnvCubemap: TVulkanRHITexture read FIrradianceEnvCubemap;
    property IrradianceEnvSize: Cardinal read FIrradianceEnvSize;
    property PrefilterComputePipeline: TRHIComputePipeline read FPrefilterComputePipeline;
    property IrradianceComputePipeline: TRHIComputePipeline read FIrradianceComputePipeline;
    property IrradianceSH9: TCastleSH9Coefficients read FIrradianceSH9;
    property TotalBrdfLutDispatches: Cardinal read FTotalBrdfLutDispatches;
    property TotalEnvPrefilterPasses: Cardinal read FTotalEnvPrefilterPasses;
    property TotalIrradianceDispatches: Cardinal read FTotalIrradianceDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 14.1: 3D Clustered Forward+ Compute Light Culler (256+ Lights)       }
  { -------------------------------------------------------------------------- }

{$endif read_interface}

{$ifdef read_implementation}
{ ---------------------------------------------------------------------------- }
{ TVulkanDescriptorPoolAllocator                                               }
{ ---------------------------------------------------------------------------- }

constructor TVulkanDescriptorPoolAllocator.Create(const ADevice: VkDevice;
  const AInitialMaxSets: Cardinal; const AAllowFreeIndividualSets: Boolean;
  const AMaxSetsCap: Cardinal; const AAllowUpdateAfterBind: Boolean;
  const ASupportsAccelerationStructure: Boolean);
begin
  inherited Create;
  FDevice := ADevice;
  FInitialMaxSets := Max(1, AInitialMaxSets);
  FMaxSetsCap := Max(FInitialMaxSets, AMaxSetsCap);
  FCurrentMaxSets := FInitialMaxSets;
  FAllowFreeIndividualSets := AAllowFreeIndividualSets;
  FAllowUpdateAfterBind := AAllowUpdateAfterBind;
  FSupportsAccelerationStructure := ASupportsAccelerationStructure;
  FHasCurrentPage := False;
  FForceNextAllocationError := VK_SUCCESS;
end;

destructor TVulkanDescriptorPoolAllocator.Destroy;
var
  I: Integer;
begin
  if (FDevice <> nil) and Assigned(vkDestroyDescriptorPool) then
  begin
    if FHasCurrentPage and (FCurrentPage.Handle <> VK_NULL_HANDLE) then
      vkDestroyDescriptorPool(FDevice, FCurrentPage.Handle, nil);
    for I := 0 to High(FReadyPools) do
      if FReadyPools[I].Handle <> VK_NULL_HANDLE then
        vkDestroyDescriptorPool(FDevice, FReadyPools[I].Handle, nil);
    for I := 0 to High(FFullPools) do
      if FFullPools[I].Handle <> VK_NULL_HANDLE then
        vkDestroyDescriptorPool(FDevice, FFullPools[I].Handle, nil);
  end;
  FHasCurrentPage := False;
  SetLength(FReadyPools, 0);
  SetLength(FFullPools, 0);
  inherited;
end;

function TVulkanDescriptorPoolAllocator.CreateNewPoolPage(
  const AMaxSets: Cardinal): TVulkanDescriptorPoolPage;
var
  PoolSizes: array[0..7] of VkDescriptorPoolSize;
  PoolSizeCount: Cardinal;
  PoolInfo: VkDescriptorPoolCreateInfo;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Capacity := Max(1, AMaxSets);
  Result.AllocatedSets := 0;

  PoolSizes[0]._type := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  PoolSizes[0].descriptorCount := Result.Capacity * 2;
  PoolSizes[1]._type := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
  PoolSizes[1].descriptorCount := Max(1, Result.Capacity div 2);
  PoolSizes[2]._type := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  PoolSizes[2].descriptorCount := Max(1, Result.Capacity div 2);
  PoolSizes[3]._type := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
  PoolSizes[3].descriptorCount := Result.Capacity * 4;
  PoolSizes[4]._type := VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
  PoolSizes[4].descriptorCount := Result.Capacity;
  PoolSizes[5]._type := VK_DESCRIPTOR_TYPE_SAMPLER;
  PoolSizes[5].descriptorCount := Result.Capacity;
  PoolSizes[6]._type := VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
  PoolSizes[6].descriptorCount := Max(1, Result.Capacity div 4);
  PoolSizeCount := 7;
  if FSupportsAccelerationStructure then
  begin
    PoolSizes[7]._type := VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;
    PoolSizes[7].descriptorCount := Max(1, Result.Capacity div 4);
    PoolSizeCount := 8;
  end;

  FillChar(PoolInfo, SizeOf(PoolInfo), 0);
  PoolInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  if FAllowFreeIndividualSets then
    PoolInfo.flags := PoolInfo.flags or VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;
  if FAllowUpdateAfterBind then
    PoolInfo.flags := PoolInfo.flags or VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT;
  PoolInfo.maxSets := Result.Capacity;
  PoolInfo.poolSizeCount := PoolSizeCount;
  PoolInfo.pPoolSizes := @PoolSizes[0];

  if (FDevice <> nil) and Assigned(vkCreateDescriptorPool) then
    CheckVk(vkCreateDescriptorPool(FDevice, @PoolInfo, nil, @Result.Handle), 'vkCreateDescriptorPool')
  else
    Result.Handle := VkDescriptorPool(PtrUInt($50000000) + PtrUInt(FTotalPoolCount) + 1);

  Inc(FTotalPoolCount);
  FCurrentMaxSets := Cardinal(Min(UInt64(FMaxSetsCap),
    Max(UInt64(FCurrentMaxSets) + UInt64(FCurrentMaxSets div 2), UInt64(FCurrentMaxSets) + UInt64(1))));
end;

procedure TVulkanDescriptorPoolAllocator.AcquireNextReadyOrNewPage;
var
  Idx: Integer;
begin
  if FHasCurrentPage then
  begin
    Idx := Length(FFullPools);
    SetLength(FFullPools, Idx + 1);
    FFullPools[Idx] := FCurrentPage;
    FHasCurrentPage := False;
  end;

  if Length(FReadyPools) > 0 then
  begin
    Idx := High(FReadyPools);
    FCurrentPage := FReadyPools[Idx];
    SetLength(FReadyPools, Idx);
    FHasCurrentPage := True;
  end else
  begin
    FCurrentPage := CreateNewPoolPage(FCurrentMaxSets);
    FHasCurrentPage := True;
  end;
end;

function TVulkanDescriptorPoolAllocator.AllocateDescriptorSet(
  const ASetLayout: VkDescriptorSetLayout;
  out AOwnerPool: VkDescriptorPool): VkDescriptorSet;
var
  AllocInfo: VkDescriptorSetAllocateInfo;
  LocalLayout: VkDescriptorSetLayout;
  Res: VkResult;
begin
  Result := VK_NULL_HANDLE;
  if not FHasCurrentPage then
    AcquireNextReadyOrNewPage;

  LocalLayout := ASetLayout;
  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
  AllocInfo.descriptorPool := FCurrentPage.Handle;
  AllocInfo.descriptorSetCount := 1;
  AllocInfo.pSetLayouts := @LocalLayout;

  if FForceNextAllocationError <> VK_SUCCESS then
  begin
    Res := FForceNextAllocationError;
    FForceNextAllocationError := VK_SUCCESS;
  end else
  if FCurrentPage.AllocatedSets >= FCurrentPage.Capacity then
    Res := VK_ERROR_OUT_OF_POOL_MEMORY
  else
  if (FDevice <> nil) and Assigned(vkAllocateDescriptorSets) then
    Res := vkAllocateDescriptorSets(FDevice, @AllocInfo, @Result)
  else
  begin
    Inc(FNextSimulatedSetId);
    Result := VkDescriptorSet(PtrUInt($60000000) + PtrUInt(FNextSimulatedSetId));
    Res := VK_SUCCESS;
  end;

  if (Res = VK_ERROR_OUT_OF_POOL_MEMORY) or (Res = VK_ERROR_FRAGMENTED_POOL) then
  begin
    AcquireNextReadyOrNewPage;
    AllocInfo.descriptorPool := FCurrentPage.Handle;
    if (FDevice <> nil) and Assigned(vkAllocateDescriptorSets) then
      Res := vkAllocateDescriptorSets(FDevice, @AllocInfo, @Result)
    else
    begin
      Inc(FNextSimulatedSetId);
      Result := VkDescriptorSet(PtrUInt($60000000) + PtrUInt(FNextSimulatedSetId));
      Res := VK_SUCCESS;
    end;
  end;

  CheckVk(Res, 'vkAllocateDescriptorSets');
  Inc(FCurrentPage.AllocatedSets);
  Inc(FTotalAllocatedSetCount);
  AOwnerPool := FCurrentPage.Handle;
end;

procedure TVulkanDescriptorPoolAllocator.FreeDescriptorSet(
  const AOwnerPool: VkDescriptorPool; const ASet: VkDescriptorSet);
var
  LocalSet: VkDescriptorSet;
  I: Integer;
begin
  if (not FAllowFreeIndividualSets) or (AOwnerPool = VK_NULL_HANDLE) or (ASet = VK_NULL_HANDLE) then
    Exit;

  LocalSet := ASet;
  if (FDevice <> nil) and Assigned(vkFreeDescriptorSets) then
    vkFreeDescriptorSets(FDevice, AOwnerPool, 1, @LocalSet);

  if FHasCurrentPage and (FCurrentPage.Handle = AOwnerPool) then
  begin
    if FCurrentPage.AllocatedSets > 0 then
      Dec(FCurrentPage.AllocatedSets);
  end else
  begin
    for I := 0 to High(FFullPools) do
      if FFullPools[I].Handle = AOwnerPool then
      begin
        if FFullPools[I].AllocatedSets > 0 then
          Dec(FFullPools[I].AllocatedSets);
        Break;
      end;
  end;

  if FTotalAllocatedSetCount > 0 then
    Dec(FTotalAllocatedSetCount);
end;

procedure TVulkanDescriptorPoolAllocator.ResetPools;
var
  I, Idx: Integer;
begin
  for I := 0 to High(FReadyPools) do
    FReadyPools[I].AllocatedSets := 0;

  if FHasCurrentPage then
  begin
    if (FDevice <> nil) and Assigned(vkResetDescriptorPool) and
       (FCurrentPage.Handle <> VK_NULL_HANDLE) then
      CheckVk(vkResetDescriptorPool(FDevice, FCurrentPage.Handle, 0), 'vkResetDescriptorPool');
    FCurrentPage.AllocatedSets := 0;
    Idx := Length(FReadyPools);
    SetLength(FReadyPools, Idx + 1);
    FReadyPools[Idx] := FCurrentPage;
    FHasCurrentPage := False;
  end;

  for I := 0 to High(FFullPools) do
  begin
    if (FDevice <> nil) and Assigned(vkResetDescriptorPool) and
       (FFullPools[I].Handle <> VK_NULL_HANDLE) then
      CheckVk(vkResetDescriptorPool(FDevice, FFullPools[I].Handle, 0), 'vkResetDescriptorPool');
    FFullPools[I].AllocatedSets := 0;
    Idx := Length(FReadyPools);
    SetLength(FReadyPools, Idx + 1);
    FReadyPools[Idx] := FFullPools[I];
  end;
  SetLength(FFullPools, 0);

  FTotalAllocatedSetCount := 0;
  Inc(FResetCount);
end;

function TVulkanDescriptorPoolAllocator.GetReadyPoolCount: Cardinal;
begin
  Result := Cardinal(Length(FReadyPools));
end;

function TVulkanDescriptorPoolAllocator.GetFullPoolCount: Cardinal;
begin
  Result := Cardinal(Length(FFullPools));
end;

function TVulkanDescriptorPoolAllocator.GetCurrentPoolHandle: VkDescriptorPool;
begin
  if FHasCurrentPage then
    Result := FCurrentPage.Handle
  else
    Result := VK_NULL_HANDLE;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanBindlessTextureManager                                          }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanBindlessTextureManager.Create(const ADevice: TVulkanRHIDevice;
  const ACapacity: Cardinal; const ASupportsUpdateAfterBind: Boolean);
begin
  inherited Create;
  FDevice := ADevice;
  FCapacity := Max(Cardinal(1), ACapacity);
  FSupportsUpdateAfterBind := ASupportsUpdateAfterBind;
end;

destructor TCastleVulkanBindlessTextureManager.Destroy;
begin
  SetLength(FSlots, 0);
  SetLength(FFreeSlots, 0);
  SetLength(FMaterialEntries, 0);
  if FOwnsMaterialSSBOBuffer then
    FreeAndNil(FMaterialSSBOBuffer)
  else
    FMaterialSSBOBuffer := nil;
  FreeAndNil(FDescriptorSet);
  FreeAndNil(FLayout);
  if (FBindlessPool <> VK_NULL_HANDLE) and (FDevice <> nil) and
     (FDevice.Handle <> nil) and Assigned(vkDestroyDescriptorPool) then
    vkDestroyDescriptorPool(FDevice.Handle, FBindlessPool, nil);
  FBindlessPool := VK_NULL_HANDLE;
  inherited;
end;

procedure TCastleVulkanBindlessTextureManager.EnsureDescriptorSetCreated;
var
  Bindings: array[0..1] of TRHIDescriptorBindingDesc;
  PoolSizes: array[0..1] of VkDescriptorPoolSize;
  PoolInfo: VkDescriptorPoolCreateInfo;
  UseBindlessFlags, EffectiveUpdateAfterBind: Boolean;
begin
  if FDescriptorSet <> nil then
    Exit;

  UseBindlessFlags := (FDevice = nil) or FDevice.SupportsBindlessTextures;
  EffectiveUpdateAfterBind := UseBindlessFlags and FSupportsUpdateAfterBind;

  FillChar(Bindings, SizeOf(Bindings), 0);
  { Binding 0: Bindless Combined Image Sampler Array }
  Bindings[0].Binding := 0;
  Bindings[0].DescriptorType := dtCombinedImageSampler;
  Bindings[0].Count := FCapacity;
  Bindings[0].StageFlags := [ssVertex, ssFragment, ssCompute];
  if UseBindlessFlags then
  begin
    Bindings[0].BindingFlags := [dbfPartiallyBound, dbfUpdateUnusedWhilePending];
    if EffectiveUpdateAfterBind then
      Include(Bindings[0].BindingFlags, dbfUpdateAfterBind);
  end;

  { Binding 1: Multi-Material Storage Buffer (CastleBindlessMaterialsBlock) }
  Bindings[1].Binding := 1;
  Bindings[1].DescriptorType := dtStorageBuffer;
  Bindings[1].Count := 1;
  Bindings[1].StageFlags := [ssVertex, ssFragment, ssCompute];
  if UseBindlessFlags then
    Bindings[1].BindingFlags := [dbfPartiallyBound];

  FLayout := TVulkanRHIDescriptorSetLayout.Create(FDevice, Bindings);

  if FBindlessPool = VK_NULL_HANDLE then
  begin
    FillChar(PoolSizes, SizeOf(PoolSizes), 0);
    PoolSizes[0]._type := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    PoolSizes[0].descriptorCount := Max(Cardinal(16), FCapacity);
    PoolSizes[1]._type := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    PoolSizes[1].descriptorCount := 4;

    FillChar(PoolInfo, SizeOf(PoolInfo), 0);
    PoolInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    PoolInfo.flags := VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;
    if EffectiveUpdateAfterBind then
      PoolInfo.flags := PoolInfo.flags or VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT;
    PoolInfo.maxSets := 4;
    PoolInfo.poolSizeCount := Length(PoolSizes);
    PoolInfo.pPoolSizes := @PoolSizes[0];

    if (FDevice <> nil) and (FDevice.Handle <> nil) and Assigned(vkCreateDescriptorPool) then
      CheckVk(vkCreateDescriptorPool(FDevice.Handle, @PoolInfo, nil, @FBindlessPool),
        'vkCreateDescriptorPool(Bindless)')
    else
      FBindlessPool := VkDescriptorPool(PtrUInt(Self));
  end;

  FDescriptorSet := TVulkanRHIDescriptorSet.CreateFromCustomPool(FDevice, FLayout, FBindlessPool);
end;

function TCastleVulkanBindlessTextureManager.GetFreeSlotCount: Cardinal;
begin
  Result := Cardinal(Length(FFreeSlots));
end;

function TCastleVulkanBindlessTextureManager.TryGetTextureIndex(
  const ATexture: TRHITexture; const ASampler: TRHISampler;
  out AIndex: Cardinal): Boolean;
var
  I: Integer;
begin
  AIndex := 0;
  if ATexture = nil then
    Exit(False);
  for I := 0 to High(FSlots) do
    if FSlots[I].InUse and
       (FSlots[I].Texture = ATexture) and
       (FSlots[I].Sampler = ASampler) then
    begin
      AIndex := Cardinal(I);
      Exit(True);
    end;
  Result := False;
end;

function TCastleVulkanBindlessTextureManager.RegisterTexture(
  const ATexture: TRHITexture; const ASampler: TRHISampler): Cardinal;
var
  ExistingIndex: Cardinal;
  FreeIdx: Integer;
begin
  if ATexture = nil then
    Exit(0);

  EnsureDescriptorSetCreated;

  { 1. Deduplicate if already registered with the same sampler }
  if TryGetTextureIndex(ATexture, ASampler, ExistingIndex) then
  begin
    Inc(FDeduplicatedHits);
    Exit(ExistingIndex);
  end;

  { 2. Pop from free-list if available, otherwise allocate a new slot at end of FSlots }
  if Length(FFreeSlots) > 0 then
  begin
    FreeIdx := High(FFreeSlots);
    Result := FFreeSlots[FreeIdx];
    SetLength(FFreeSlots, FreeIdx);
    Inc(FRecycledSlotReuses);
  end else
  begin
    if Cardinal(Length(FSlots)) >= FCapacity then
      raise ERHIOutOfMemory.CreateFmt(
        'Bindless texture table capacity (%d slots) exceeded', [FCapacity]);
    Result := Cardinal(Length(FSlots));
    SetLength(FSlots, Result + 1);
  end;

  FSlots[Result].Texture := ATexture as TVulkanRHITexture;
  FSlots[Result].Sampler := ASampler as TVulkanRHISampler;
  FSlots[Result].InUse := True;
  FSlots[Result].Dirty := True;

  Inc(FActiveSlotCount);
  Inc(FPendingWriteCount);
  Inc(FTotalRegistrations);
end;

procedure TCastleVulkanBindlessTextureManager.UnregisterSlot(
  const ASlotIndex: Cardinal);
var
  FreeIdx: Integer;
begin
  if (ASlotIndex >= Cardinal(Length(FSlots))) or (not FSlots[ASlotIndex].InUse) then
    Exit;

  if FSlots[ASlotIndex].Dirty and (FPendingWriteCount > 0) then
    Dec(FPendingWriteCount);

  FSlots[ASlotIndex].Texture := nil;
  FSlots[ASlotIndex].Sampler := nil;
  FSlots[ASlotIndex].InUse := False;
  FSlots[ASlotIndex].Dirty := False;

  if FActiveSlotCount > 0 then
    Dec(FActiveSlotCount);

  FreeIdx := Length(FFreeSlots);
  SetLength(FFreeSlots, FreeIdx + 1);
  FFreeSlots[FreeIdx] := ASlotIndex;
end;

function TCastleVulkanBindlessTextureManager.UnregisterTexture(
  const ATexture: TRHITexture): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  if ATexture = nil then
    Exit;
  for I := 0 to High(FSlots) do
    if FSlots[I].InUse and (FSlots[I].Texture = ATexture) then
    begin
      UnregisterSlot(Cardinal(I));
      Inc(Result);
    end;
end;

function TCastleVulkanBindlessTextureManager.UnregisterSampler(
  const ASampler: TRHISampler): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  if ASampler = nil then
    Exit;
  for I := 0 to High(FSlots) do
    if FSlots[I].InUse and (FSlots[I].Sampler = ASampler) then
    begin
      UnregisterSlot(Cardinal(I));
      Inc(Result);
    end;
end;

procedure TCastleVulkanBindlessTextureManager.SetMaterialStorageBuffer(
  const ASSBOBuffer: TRHIBuffer; const AOffset, ARange: PtrUInt);
begin
  EnsureDescriptorSetCreated;
  if FOwnsMaterialSSBOBuffer and (FMaterialSSBOBuffer <> ASSBOBuffer) then
  begin
    FreeAndNil(FMaterialSSBOBuffer);
    FOwnsMaterialSSBOBuffer := False;
  end;
  FMaterialSSBOBuffer := ASSBOBuffer;
  if (FDescriptorSet <> nil) and (ASSBOBuffer <> nil) then
  begin
    FDescriptorSet.BindStorageBuffer(1, ASSBOBuffer, AOffset, ARange);
    Inc(FPendingWriteCount);
  end;
end;

function TCastleVulkanBindlessTextureManager.RegisterOrUpdateMaterial(
  var AMaterialIndex: Cardinal; var AAlreadyRegistered: Boolean;
  const AEntry: TCastleBindlessMaterialEntry): Cardinal;
begin
  EnsureDescriptorSetCreated;
  if AAlreadyRegistered and (AMaterialIndex < Cardinal(Length(FMaterialEntries))) then
  begin
    if not CompareMem(@FMaterialEntries[AMaterialIndex], @AEntry, SizeOf(TCastleBindlessMaterialEntry)) then
    begin
      FMaterialEntries[AMaterialIndex] := AEntry;
      FMaterialTableDirty := True;
      Inc(FPendingWriteCount);
    end;
    Result := AMaterialIndex;
  end else
  begin
    AMaterialIndex := Cardinal(Length(FMaterialEntries));
    SetLength(FMaterialEntries, AMaterialIndex + 1);
    FMaterialEntries[AMaterialIndex] := AEntry;
    AAlreadyRegistered := True;
    FMaterialTableDirty := True;
    Inc(FPendingWriteCount);
    Result := AMaterialIndex;
  end;
end;

function TCastleVulkanBindlessTextureManager.GetMaterialEntry(
  const AIndex: Cardinal): TCastleBindlessMaterialEntry;
begin
  if AIndex < Cardinal(Length(FMaterialEntries)) then
    Result := FMaterialEntries[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleVulkanBindlessTextureManager.GetMaterialCount: Cardinal;
begin
  Result := Cardinal(Length(FMaterialEntries));
end;

function TCastleVulkanBindlessTextureManager.FlushMaterialTableToSSBO: Boolean;
var
  RequiredBytes, AllocBytes: PtrUInt;
  BufDesc: TRHIBufferDesc;
begin
  Result := False;
  if (FDevice = nil) or (Length(FMaterialEntries) = 0) then
    Exit;

  EnsureDescriptorSetCreated;
  RequiredBytes := PtrUInt(Length(FMaterialEntries)) * SizeOf(TCastleBindlessMaterialEntry);
  if (FMaterialSSBOBuffer = nil) or (FMaterialSSBOBuffer.Desc.Size < RequiredBytes) then
  begin
    if FOwnsMaterialSSBOBuffer then
      FreeAndNil(FMaterialSSBOBuffer);
    AllocBytes := PtrUInt(Max(UInt64(64 * SizeOf(TCastleBindlessMaterialEntry)), UInt64(RequiredBytes) * UInt64(2)));
    BufDesc := Default(TRHIBufferDesc);
    BufDesc.Size := AllocBytes;
    BufDesc.Usage := [buStorage, buTransferDst];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'CastleBindlessMaterialTableSSBO';
    FMaterialSSBOBuffer := FDevice.CreateBuffer(BufDesc, nil);
    FOwnsMaterialSSBOBuffer := True;
    if (FDescriptorSet <> nil) and (FMaterialSSBOBuffer <> nil) then
      FDescriptorSet.BindStorageBuffer(1, FMaterialSSBOBuffer, 0, AllocBytes);
  end;

  if FMaterialSSBOBuffer <> nil then
  begin
    FMaterialSSBOBuffer.UploadData(FMaterialEntries[0], RequiredBytes, 0);
    FMaterialTableDirty := False;
    Inc(FMaterialFlushCount);
    Result := True;
  end;
end;

function TCastleVulkanBindlessTextureManager.FlushPendingUpdates: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  if FDescriptorSet = nil then
    Exit;

  if FMaterialTableDirty then
    FlushMaterialTableToSSBO;

  if (FPendingWriteCount = 0) and (Length(FDescriptorSet.FPendingWrites) = 0) then
    Exit;

  for I := 0 to High(FSlots) do
    if FSlots[I].InUse and FSlots[I].Dirty and (FSlots[I].Texture <> nil) then
    begin
      FDescriptorSet.BindTextureAtIndex(0, Cardinal(I), FSlots[I].Texture, FSlots[I].Sampler);
      FSlots[I].Dirty := False;
      Inc(Result);
    end;

  if (Result > 0) or (Length(FDescriptorSet.FPendingWrites) > 0) then
  begin
    Result := Cardinal(Length(FDescriptorSet.FPendingWrites));
    FDescriptorSet.Update;
    Inc(FTotalFlushedWrites, Result);
  end;
  FPendingWriteCount := 0;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanStagingUploader                                                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanStagingUploader.Create(const ADevice: TVulkanRHIDevice;
  const ARingCapacityPerFrame: VkDeviceSize);
begin
  inherited Create;
  FDevice := ADevice;
  FRingCapacityPerFrame := Max(VkDeviceSize(4096), ARingCapacityPerFrame);
  if ADevice <> nil then
    ConfigureTransferQueue(ADevice.GraphicsQueueFamily, ADevice.TransferQueueFamily,
      ADevice.HasDedicatedTransferQueue);
end;

destructor TCastleVulkanStagingUploader.Destroy;
var
  Slot: Cardinal;
begin
  WaitForAsyncUploads;
  SetLength(FPendingBufferCopies, 0);
  SetLength(FPendingImageCopies, 0);
  SetLength(FPendingAcquireBuffers, 0);
  SetLength(FPendingAcquireImages, 0);
  SetLength(FPendingPostTransferMipmaps, 0);
  FreeAndNil(FTransferTimelineSemaphore);
  for Slot := 0 to MaxFramesInFlight - 1 do
  begin
    ReclaimFrameSlot(Slot);
    if (FDevice <> nil) and (FDevice.Handle <> nil) then
    begin
      if (FTransferBinarySemaphores[Slot] <> VK_NULL_HANDLE) and Assigned(vkDestroySemaphore) then
        vkDestroySemaphore(FDevice.Handle, FTransferBinarySemaphores[Slot], nil);
      if (FTransferPools[Slot] <> VK_NULL_HANDLE) and Assigned(vkDestroyCommandPool) then
        vkDestroyCommandPool(FDevice.Handle, FTransferPools[Slot], nil);
    end;
    FTransferBinarySemaphores[Slot] := VK_NULL_HANDLE;
    FTransferPools[Slot] := VK_NULL_HANDLE;
    SetLength(FTransferPoolCmdBuffers[Slot], 0);
    FTransferPoolUsedCounts[Slot] := 0;

    if (FDevice <> nil) and (FDevice.Handle <> nil) and
       (FRingBuffers[Slot] <> VK_NULL_HANDLE) and Assigned(vkDestroyBuffer) then
      vkDestroyBuffer(FDevice.Handle, FRingBuffers[Slot], nil);
    FRingBuffers[Slot] := VK_NULL_HANDLE;
    if FRingAllocations[Slot].IsValid and (FDevice <> nil) and (FDevice.MemoryAllocator <> nil) then
    begin
      Dec(FDevice.FAllocatedMemoryBytes, FRingAllocations[Slot].Size);
      FDevice.MemoryAllocator.Free(FRingAllocations[Slot]);
    end;
    FillChar(FRingAllocations[Slot], SizeOf(TVulkanMemoryAllocation), 0);
  end;
  inherited;
end;

procedure TCastleVulkanStagingUploader.ConfigureTransferQueue(
  const AGraphicsQueueFamily, ATransferQueueFamily: Cardinal;
  const AUseDedicatedTransferQueue: Boolean);
begin
  FGraphicsQueueFamily := AGraphicsQueueFamily;
  FTransferQueueFamily := ATransferQueueFamily;
  FUseDedicatedTransferQueue := AUseDedicatedTransferQueue and
    (ATransferQueueFamily <> AGraphicsQueueFamily);
end;

function TCastleVulkanStagingUploader.EnsureRingBufferForSlot(
  const AFrameSlot: Cardinal): Boolean;
var
  Slot: Cardinal;
  BufInfo: VkBufferCreateInfo;
  Align: VkDeviceSize;
begin
  Slot := AFrameSlot mod MaxFramesInFlight;
  if FRingAllocations[Slot].IsValid then
    Exit(True);
  if (FDevice = nil) or (FDevice.MemoryAllocator = nil) then
    Exit(False);

  if (FDevice.Handle <> nil) and Assigned(vkCreateBuffer) then
  begin
    FillChar(BufInfo, SizeOf(BufInfo), 0);
    BufInfo.sType := VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    BufInfo.size := FRingCapacityPerFrame;
    BufInfo.usage := VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    BufInfo.sharingMode := VK_SHARING_MODE_EXCLUSIVE;
    CheckVk(vkCreateBuffer(FDevice.Handle, @BufInfo, nil, @FRingBuffers[Slot]),
      'vkCreateBuffer(StagingRing)');
  end else
    FRingBuffers[Slot] := VkBuffer(PtrUInt($70000000) + PtrUInt(Slot) + 1);

  Align := Max(VkDeviceSize(16), FDevice.MemoryAllocator.OptimalBufferCopyOffsetAlignment);
  FRingAllocations[Slot] := FDevice.MemoryAllocator.AllocateBufferMemory(
    FRingBuffers[Slot], FRingCapacityPerFrame, muCpuToGpu,
    (FDevice.Handle <> nil) and FDevice.IsPortabilitySubsetDevice, Align);

  if (FDevice.Handle <> nil) and Assigned(vkBindBufferMemory) then
    CheckVk(vkBindBufferMemory(FDevice.Handle, FRingBuffers[Slot],
      FRingAllocations[Slot].DeviceMemory, FRingAllocations[Slot].Offset),
      'vkBindBufferMemory(StagingRing)');

  Inc(FDevice.FAllocatedMemoryBytes, FRingAllocations[Slot].Size);
  Result := FRingAllocations[Slot].IsValid;
end;

function TCastleVulkanStagingUploader.AllocateStagingSlice(
  const ASize, AAlignment: VkDeviceSize;
  out ASrcBuffer: VkBuffer; out ASrcOffset: VkDeviceSize;
  out AAllocation: TVulkanMemoryAllocation): Pointer;
var
  Slot: Cardinal;
  EffAlign, AlignedOffset: VkDeviceSize;
  BufInfo: VkBufferCreateInfo;
  ChunkIdx: Integer;
begin
  ASrcBuffer := VK_NULL_HANDLE;
  ASrcOffset := 0;
  FillChar(AAllocation, SizeOf(AAllocation), 0);
  Result := nil;
  if (FDevice = nil) or (ASize = 0) then
    Exit;

  Slot := FDevice.FrameIndex mod MaxFramesInFlight;
  EffAlign := Max(VkDeviceSize(16), AAlignment);
  if FDevice.MemoryAllocator <> nil then
    EffAlign := Max(EffAlign, FDevice.MemoryAllocator.OptimalBufferCopyOffsetAlignment);

  if EffAlign > 1 then
    AlignedOffset := ((FRingWriteOffsets[Slot] + EffAlign - 1) div EffAlign) * EffAlign
  else
    AlignedOffset := FRingWriteOffsets[Slot];
  if (AlignedOffset + ASize <= FRingCapacityPerFrame) and EnsureRingBufferForSlot(Slot) then
  begin
    ASrcBuffer := FRingBuffers[Slot];
    ASrcOffset := AlignedOffset;
    AAllocation := FRingAllocations[Slot];
    FRingWriteOffsets[Slot] := AlignedOffset + ASize;
    if FRingAllocations[Slot].MappedPtr <> nil then
      Result := Pointer(PtrUInt(FRingAllocations[Slot].MappedPtr) + PtrUInt(AlignedOffset));
    Exit;
  end;

  { Single upload exceeds remaining space in the current frame's ring buffer:
    allocate a temporary overflow staging chunk retired on ReclaimFrameSlot(Slot) }
  if FDevice.MemoryAllocator <> nil then
  begin
    ChunkIdx := Length(FOverflowChunks[Slot]);
    SetLength(FOverflowChunks[Slot], ChunkIdx + 1);
    FillChar(FOverflowChunks[Slot][ChunkIdx], SizeOf(TVulkanStagingOverflowChunk), 0);

    if (FDevice.Handle <> nil) and Assigned(vkCreateBuffer) then
    begin
      FillChar(BufInfo, SizeOf(BufInfo), 0);
      BufInfo.sType := VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
      BufInfo.size := ASize;
      BufInfo.usage := VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
      BufInfo.sharingMode := VK_SHARING_MODE_EXCLUSIVE;
      CheckVk(vkCreateBuffer(FDevice.Handle, @BufInfo, nil, @FOverflowChunks[Slot][ChunkIdx].Buffer),
        'vkCreateBuffer(StagingOverflow)');
    end else
      FOverflowChunks[Slot][ChunkIdx].Buffer := VkBuffer(PtrUInt($71000000) + PtrUInt(FOverflowChunkCount) + 1);

    FOverflowChunks[Slot][ChunkIdx].Allocation := FDevice.MemoryAllocator.AllocateBufferMemory(
      FOverflowChunks[Slot][ChunkIdx].Buffer, ASize, muCpuToGpu,
      (FDevice.Handle <> nil) and FDevice.IsPortabilitySubsetDevice, EffAlign);

    if (FDevice.Handle <> nil) and Assigned(vkBindBufferMemory) then
      CheckVk(vkBindBufferMemory(FDevice.Handle, FOverflowChunks[Slot][ChunkIdx].Buffer,
        FOverflowChunks[Slot][ChunkIdx].Allocation.DeviceMemory,
        FOverflowChunks[Slot][ChunkIdx].Allocation.Offset),
        'vkBindBufferMemory(StagingOverflow)');

    Inc(FDevice.FAllocatedMemoryBytes, FOverflowChunks[Slot][ChunkIdx].Allocation.Size);
    Inc(FOverflowChunkCount);

    ASrcBuffer := FOverflowChunks[Slot][ChunkIdx].Buffer;
    ASrcOffset := 0;
    AAllocation := FOverflowChunks[Slot][ChunkIdx].Allocation;
    Result := AAllocation.MappedPtr;
  end;
end;

function TCastleVulkanStagingUploader.GetTransferTimelineSemaphore: TCastleVulkanTimelineSemaphore;
begin
  if FTransferTimelineSemaphore = nil then
    FTransferTimelineSemaphore := TCastleVulkanTimelineSemaphore.Create(FDevice, 0);
  Result := FTransferTimelineSemaphore;
end;

function TCastleVulkanStagingUploader.EnsureTransferBinarySemaphore(
  const AFrameSlot: Cardinal): VkSemaphore;
var
  Slot: Cardinal;
  SemInfo: VkSemaphoreCreateInfo;
begin
  Slot := AFrameSlot mod MaxFramesInFlight;
  if FTransferBinarySemaphores[Slot] = VK_NULL_HANDLE then
  begin
    if (FDevice <> nil) and (FDevice.Handle <> nil) and Assigned(vkCreateSemaphore) then
    begin
      FillChar(SemInfo, SizeOf(SemInfo), 0);
      SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
      CheckVk(vkCreateSemaphore(FDevice.Handle, @SemInfo, nil, @FTransferBinarySemaphores[Slot]),
        'vkCreateSemaphore(TransferBinary)');
    end else
      FTransferBinarySemaphores[Slot] := VkSemaphore(PtrUInt($67000001) + PtrUInt(Slot));
  end;
  Result := FTransferBinarySemaphores[Slot];
end;

function TCastleVulkanStagingUploader.AcquireTransferCommandBuffer(
  const AFrameSlot: Cardinal): VkCommandBuffer;
var
  Slot, UsedIdx: Cardinal;
  PoolInfo: VkCommandPoolCreateInfo;
  AllocInfo: VkCommandBufferAllocateInfo;
  NewCmd: VkCommandBuffer;
  EffQueueFamily: Cardinal;
begin
  Slot := AFrameSlot mod MaxFramesInFlight;
  if (FDevice = nil) or (FDevice.Handle = nil) then
  begin
    UsedIdx := FTransferPoolUsedCounts[Slot];
    Inc(FTransferPoolUsedCounts[Slot]);
    Exit(VkCommandBuffer(PtrUInt($73000000) + PtrUInt(Slot * 64 + UsedIdx + 1)));
  end;

  EffQueueFamily := FDevice.TransferQueueFamily;
  if (FTransferPools[Slot] = VK_NULL_HANDLE) and Assigned(vkCreateCommandPool) then
  begin
    FillChar(PoolInfo, SizeOf(PoolInfo), 0);
    PoolInfo.sType := VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    PoolInfo.flags := VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
    PoolInfo.queueFamilyIndex := EffQueueFamily;
    CheckVk(vkCreateCommandPool(FDevice.Handle, @PoolInfo, nil, @FTransferPools[Slot]),
      'vkCreateCommandPool(AsyncTransfer)');
  end;

  UsedIdx := FTransferPoolUsedCounts[Slot];
  if UsedIdx >= Cardinal(Length(FTransferPoolCmdBuffers[Slot])) then
  begin
    NewCmd := nil;
    FillChar(AllocInfo, SizeOf(AllocInfo), 0);
    AllocInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    AllocInfo.commandPool := FTransferPools[Slot];
    AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    AllocInfo.commandBufferCount := 1;
    CheckVk(vkAllocateCommandBuffers(FDevice.Handle, @AllocInfo, @NewCmd),
      'vkAllocateCommandBuffers(AsyncTransfer)');
    SetLength(FTransferPoolCmdBuffers[Slot], UsedIdx + 1);
    FTransferPoolCmdBuffers[Slot][UsedIdx] := NewCmd;
  end;
  Result := FTransferPoolCmdBuffers[Slot][UsedIdx];
  Inc(FTransferPoolUsedCounts[Slot]);
end;

procedure TCastleVulkanStagingUploader.ReclaimFrameSlot(const AFrameSlot: Cardinal);
var
  Slot: Cardinal;
  I: Integer;
begin
  Slot := AFrameSlot mod MaxFramesInFlight;
  if (FPendingGraphicsWaitTimelineValue > 0) and (FTransferTimelineSemaphore <> nil) then
    FTransferTimelineSemaphore.Wait(FPendingGraphicsWaitTimelineValue, High(UInt64));
  FTransferPoolUsedCounts[Slot] := 0;
  if (FDevice <> nil) and (FDevice.Handle <> nil) and
     (FTransferPools[Slot] <> VK_NULL_HANDLE) and Assigned(vkResetCommandPool) then
    CheckVk(vkResetCommandPool(FDevice.Handle, FTransferPools[Slot], 0),
      'vkResetCommandPool(AsyncTransfer)');

  { Preserve FRingWriteOffsets[Slot] and FOverflowChunks[Slot] when pre-frame uploads
    were staged into this slot prior to BeginFrame / BeginSurfaceFrame and are still
    awaiting FlushPendingUploads; otherwise subsequent in-frame staging allocations
    would overwrite offset 0 before vkQueueSubmit executes the copy commands. }
  if (Length(FPendingBufferCopies) > 0) or (Length(FPendingImageCopies) > 0) then
    Exit;

  FRingWriteOffsets[Slot] := 0;
  for I := 0 to High(FOverflowChunks[Slot]) do
  begin
    if (FDevice <> nil) and (FDevice.Handle <> nil) and
       (FOverflowChunks[Slot][I].Buffer <> VK_NULL_HANDLE) and Assigned(vkDestroyBuffer) then
      vkDestroyBuffer(FDevice.Handle, FOverflowChunks[Slot][I].Buffer, nil);
    if FOverflowChunks[Slot][I].Allocation.IsValid and
       (FDevice <> nil) and (FDevice.MemoryAllocator <> nil) then
    begin
      Dec(FDevice.FAllocatedMemoryBytes, FOverflowChunks[Slot][I].Allocation.Size);
      FDevice.MemoryAllocator.Free(FOverflowChunks[Slot][I].Allocation);
    end;
    if FOverflowChunkCount > 0 then
      Dec(FOverflowChunkCount);
  end;
  SetLength(FOverflowChunks[Slot], 0);
end;

procedure TCastleVulkanStagingUploader.EnqueueBufferUpload(
  const ADstBuffer: TVulkanRHIBuffer; const AData;
  const ASize, ADstOffset: VkDeviceSize);
var
  SrcBuf: VkBuffer;
  SrcOff: VkDeviceSize;
  SliceAlloc: TVulkanMemoryAllocation;
  SlicePtr: Pointer;
  Idx: Integer;
begin
  if (ADstBuffer = nil) or (ASize = 0) then
    Exit;

  SlicePtr := AllocateStagingSlice(ASize, 16, SrcBuf, SrcOff, SliceAlloc);
  if SlicePtr <> nil then
    Move(AData, SlicePtr^, ASize);

  if SliceAlloc.IsValid and (FDevice <> nil) and (FDevice.MemoryAllocator <> nil) then
    FDevice.MemoryAllocator.FlushAllocation(SliceAlloc, SrcOff, ASize);

  { In headless unit-test mode, mirror uploaded bytes into ADstBuffer's simulated memory }
  if ((FDevice = nil) or (FDevice.Handle = nil)) and
     (ADstBuffer.Allocation.MappedPtr <> nil) and
     (ADstOffset + ASize <= ADstBuffer.Desc.Size) then
    Move(AData, PByte(PtrUInt(ADstBuffer.Allocation.MappedPtr) + PtrUInt(ADstOffset))^, ASize);

  Idx := Length(FPendingBufferCopies);
  SetLength(FPendingBufferCopies, Idx + 1);
  FPendingBufferCopies[Idx].SrcBuffer := SrcBuf;
  FPendingBufferCopies[Idx].DstBuffer := ADstBuffer;
  FPendingBufferCopies[Idx].Region.srcOffset := SrcOff;
  FPendingBufferCopies[Idx].Region.dstOffset := ADstOffset;
  FPendingBufferCopies[Idx].Region.size := ASize;

  Inc(FTotalBufferUploads);
  Inc(FTotalStagedBytes, ASize);
end;

procedure TCastleVulkanStagingUploader.EnqueueImageUpload(
  const ADstTexture: TVulkanRHITexture; const AData: Pointer;
  const ADataSize: VkDeviceSize; const AWidth, AHeight: Cardinal;
  const AMipLevel, AArrayLayer: Cardinal; const AGenerateMipmaps: Boolean);
var
  SrcBuf: VkBuffer;
  SrcOff: VkDeviceSize;
  SliceAlloc: TVulkanMemoryAllocation;
  SlicePtr: Pointer;
  Idx: Integer;
begin
  if (ADstTexture = nil) or (ADataSize = 0) then
    Exit;

  SlicePtr := AllocateStagingSlice(ADataSize, 16, SrcBuf, SrcOff, SliceAlloc);
  if (SlicePtr <> nil) and (AData <> nil) then
    Move(AData^, SlicePtr^, ADataSize);

  if SliceAlloc.IsValid and (FDevice <> nil) and (FDevice.MemoryAllocator <> nil) then
    FDevice.MemoryAllocator.FlushAllocation(SliceAlloc, SrcOff, ADataSize);

  Idx := Length(FPendingImageCopies);
  SetLength(FPendingImageCopies, Idx + 1);
  FillChar(FPendingImageCopies[Idx], SizeOf(TVulkanStagedImageCopy), 0);
  FPendingImageCopies[Idx].SrcBuffer := SrcBuf;
  FPendingImageCopies[Idx].DstTexture := ADstTexture;
  FPendingImageCopies[Idx].MipLevel := AMipLevel;
  FPendingImageCopies[Idx].ArrayLayer := AArrayLayer;
  FPendingImageCopies[Idx].GenerateMipmaps := AGenerateMipmaps;
  FPendingImageCopies[Idx].Region.bufferOffset := SrcOff;
  FPendingImageCopies[Idx].Region.bufferRowLength := 0;
  FPendingImageCopies[Idx].Region.bufferImageHeight := 0;
  FPendingImageCopies[Idx].Region.imageSubresource.aspectMask := ADstTexture.AspectMask;
  FPendingImageCopies[Idx].Region.imageSubresource.mipLevel := AMipLevel;
  FPendingImageCopies[Idx].Region.imageSubresource.baseArrayLayer := AArrayLayer;
  FPendingImageCopies[Idx].Region.imageSubresource.layerCount := 1;
  FPendingImageCopies[Idx].Region.imageOffset.x := 0;
  FPendingImageCopies[Idx].Region.imageOffset.y := 0;
  FPendingImageCopies[Idx].Region.imageOffset.z := 0;
  FPendingImageCopies[Idx].Region.imageExtent.width := Max(1, AWidth);
  FPendingImageCopies[Idx].Region.imageExtent.height := Max(1, AHeight);
  if ADstTexture.Desc.Dimension = td3D then
    FPendingImageCopies[Idx].Region.imageExtent.depth := Max(Cardinal(1), ADstTexture.Desc.DepthOrArrayLayers)
  else
    FPendingImageCopies[Idx].Region.imageExtent.depth := 1;

  Inc(FTotalImageUploads);
  Inc(FTotalStagedBytes, ADataSize);
end;

procedure TCastleVulkanStagingUploader.CancelPendingUploadsForBuffer(
  const ABuffer: TVulkanRHIBuffer);
var
  I, WriteIdx: Integer;
begin
  if ABuffer = nil then
    Exit;
  if Length(FPendingBufferCopies) > 0 then
  begin
    WriteIdx := 0;
    for I := 0 to High(FPendingBufferCopies) do
      if FPendingBufferCopies[I].DstBuffer <> ABuffer then
      begin
        if WriteIdx <> I then
          FPendingBufferCopies[WriteIdx] := FPendingBufferCopies[I];
        Inc(WriteIdx);
      end;
    SetLength(FPendingBufferCopies, WriteIdx);
  end;
  if Length(FPendingAcquireBuffers) > 0 then
  begin
    WriteIdx := 0;
    for I := 0 to High(FPendingAcquireBuffers) do
      if FPendingAcquireBuffers[I].DstBuffer <> ABuffer then
      begin
        if WriteIdx <> I then
          FPendingAcquireBuffers[WriteIdx] := FPendingAcquireBuffers[I];
        Inc(WriteIdx);
      end;
    SetLength(FPendingAcquireBuffers, WriteIdx);
  end;
end;

procedure TCastleVulkanStagingUploader.CancelPendingUploadsForTexture(
  const ATexture: TVulkanRHITexture);
var
  I, WriteIdx: Integer;
begin
  if ATexture = nil then
    Exit;
  if Length(FPendingImageCopies) > 0 then
  begin
    WriteIdx := 0;
    for I := 0 to High(FPendingImageCopies) do
      if FPendingImageCopies[I].DstTexture <> ATexture then
      begin
        if WriteIdx <> I then
          FPendingImageCopies[WriteIdx] := FPendingImageCopies[I];
        Inc(WriteIdx);
      end;
    SetLength(FPendingImageCopies, WriteIdx);
  end;
  if Length(FPendingAcquireImages) > 0 then
  begin
    WriteIdx := 0;
    for I := 0 to High(FPendingAcquireImages) do
      if FPendingAcquireImages[I].DstTexture <> ATexture then
      begin
        if WriteIdx <> I then
          FPendingAcquireImages[WriteIdx] := FPendingAcquireImages[I];
        Inc(WriteIdx);
      end;
    SetLength(FPendingAcquireImages, WriteIdx);
  end;
  if Length(FPendingPostTransferMipmaps) > 0 then
  begin
    WriteIdx := 0;
    for I := 0 to High(FPendingPostTransferMipmaps) do
      if FPendingPostTransferMipmaps[I] <> ATexture then
      begin
        if WriteIdx <> I then
          FPendingPostTransferMipmaps[WriteIdx] := FPendingPostTransferMipmaps[I];
        Inc(WriteIdx);
      end;
    SetLength(FPendingPostTransferMipmaps, WriteIdx);
  end;
end;

function TCastleVulkanStagingUploader.ApplyPendingGraphicsAcquireBarriers(
  const ACommandList: TVulkanRHICommandList): Cardinal;
var
  AcqBufCount, AcqImgCount, MipCount, I: Integer;
  Cmd: VkCommandBuffer;
  OneShotCmd: Boolean;
  BufBarriers: array of VkBufferMemoryBarrier;
  ImgBarrier: VkImageMemoryBarrier;
  BufItem: TVulkanStagedBufferCopy;
  ImgItem: TVulkanStagedImageCopy;
  MipTex: TVulkanRHITexture;
  PendingMipList: array of TVulkanRHITexture;
begin
  AcqBufCount := Length(FPendingAcquireBuffers);
  AcqImgCount := Length(FPendingAcquireImages);
  MipCount := Length(FPendingPostTransferMipmaps);
  Result := Cardinal(AcqBufCount + AcqImgCount + MipCount);
  if Result = 0 then
    Exit;

  OneShotCmd := False;
  Cmd := nil;
  if ACommandList <> nil then
    Cmd := ACommandList.Handle
  else if (FDevice <> nil) and (FDevice.Handle <> nil) then
  begin
    WaitForAsyncUploads;
    Cmd := FDevice.BeginSingleTimeCommands;
    OneShotCmd := Cmd <> nil;
  end;

  if AcqBufCount > 0 then
  begin
    SetLength(BufBarriers, AcqBufCount);
    for I := 0 to AcqBufCount - 1 do
    begin
      BufItem := FPendingAcquireBuffers[I];
      FillChar(BufBarriers[I], SizeOf(VkBufferMemoryBarrier), 0);
      BufBarriers[I].sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
      BufBarriers[I].srcAccessMask := 0;
      BufBarriers[I].dstAccessMask :=
        VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT or
        VK_ACCESS_INDEX_READ_BIT or
        VK_ACCESS_UNIFORM_READ_BIT or
        VK_ACCESS_SHADER_READ_BIT;
      BufBarriers[I].srcQueueFamilyIndex := FTransferQueueFamily;
      BufBarriers[I].dstQueueFamilyIndex := FGraphicsQueueFamily;
      if BufItem.DstBuffer <> nil then
      begin
        BufBarriers[I].buffer := BufItem.DstBuffer.Handle;
        BufBarriers[I].offset := BufItem.Region.dstOffset;
        BufBarriers[I].size := BufItem.Region.size;
      end;
      Inc(FQueueOwnershipTransferCount);
    end;
    if (Cmd <> nil) and Assigned(vkCmdPipelineBarrier) then
      vkCmdPipelineBarrier(Cmd,
        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
        VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        0, 0, nil, Length(BufBarriers), @BufBarriers[0], 0, nil);
    if ACommandList <> nil then
      Inc(ACommandList.FBarrierCount);
    SetLength(FPendingAcquireBuffers, 0);
  end;

  if AcqImgCount > 0 then
  begin
    for I := 0 to AcqImgCount - 1 do
    begin
      ImgItem := FPendingAcquireImages[I];
      if ImgItem.DstTexture = nil then
        Continue;
      FillChar(ImgBarrier, SizeOf(ImgBarrier), 0);
      ImgBarrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
      ImgBarrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      if ImgItem.GenerateMipmaps and (ImgItem.DstTexture.Desc.MipLevels > 1) then
      begin
        ImgBarrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        ImgBarrier.dstAccessMask := VK_ACCESS_TRANSFER_READ_BIT or VK_ACCESS_TRANSFER_WRITE_BIT;
      end else
      begin
        ImgBarrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        ImgBarrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;
      end;
      ImgBarrier.srcAccessMask := 0;
      ImgBarrier.srcQueueFamilyIndex := FTransferQueueFamily;
      ImgBarrier.dstQueueFamilyIndex := FGraphicsQueueFamily;
      ImgBarrier.image := ImgItem.DstTexture.Image;
      ImgBarrier.subresourceRange.aspectMask := ImgItem.DstTexture.AspectMask;
      ImgBarrier.subresourceRange.baseMipLevel := ImgItem.MipLevel;
      ImgBarrier.subresourceRange.levelCount := 1;
      ImgBarrier.subresourceRange.baseArrayLayer := ImgItem.ArrayLayer;
      ImgBarrier.subresourceRange.layerCount := 1;
      if (Cmd <> nil) and Assigned(vkCmdPipelineBarrier) then
      begin
        if ImgItem.GenerateMipmaps and (ImgItem.DstTexture.Desc.MipLevels > 1) then
          vkCmdPipelineBarrier(Cmd,
            VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, nil, 0, nil, 1, @ImgBarrier)
        else
          vkCmdPipelineBarrier(Cmd,
            VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0, 0, nil, 0, nil, 1, @ImgBarrier);
      end;
      if not (ImgItem.GenerateMipmaps and (ImgItem.DstTexture.Desc.MipLevels > 1)) then
        ImgItem.DstTexture.CurrentState := rsShaderRead;
      Inc(FQueueOwnershipTransferCount);
      if ACommandList <> nil then
        Inc(ACommandList.FBarrierCount);
    end;
    SetLength(FPendingAcquireImages, 0);
  end;

  if MipCount > 0 then
  begin
    PendingMipList := Copy(FPendingPostTransferMipmaps);
    SetLength(FPendingPostTransferMipmaps, 0);
    for I := 0 to High(PendingMipList) do
    begin
      MipTex := PendingMipList[I];
      if (MipTex = nil) or (MipTex.Desc.MipLevels <= 1) then
        Continue;
      MipTex.CurrentState := rsTransferDst;
      if ACommandList <> nil then
        ACommandList.GenerateMipmaps(MipTex)
      else if (Cmd <> nil) and Assigned(vkCmdBlitImage) then
      begin
        Inc(MipTex.FMipmapGenerationCount);
        MipTex.FLastGeneratedMipLevels := MipTex.Desc.MipLevels;
        MipTex.FMaxUploadedMipLevel := Max(MipTex.FMaxUploadedMipLevel, MipTex.Desc.MipLevels - 1);
        MipTex.RecordVkMipmapBlits(Cmd);
        MipTex.CurrentState := rsShaderRead;
      end else
        MipTex.CurrentState := rsShaderRead;
    end;
  end;

  if OneShotCmd and (FDevice <> nil) then
    FDevice.EndSingleTimeCommands(Cmd);
end;

function TCastleVulkanStagingUploader.SubmitAsyncUploads: UInt64;
var
  BufCount, ImgCount, I, BaseIdx: Integer;
  Slot: Cardinal;
  TransferCmd: VkCommandBuffer;
  BeginInfo: VkCommandBufferBeginInfo;
  BufBarriers: array of VkBufferMemoryBarrier;
  ImgBarrier: VkImageMemoryBarrier;
  BufItem: TVulkanStagedBufferCopy;
  ImgItem: TVulkanStagedImageCopy;
  NeedOwnershipTransfer: Boolean;
  NextVal: UInt64;
  TimelineSem: TCastleVulkanTimelineSemaphore;
  SignalSemHandle: VkSemaphore;
  TimelineSubmit: VkTimelineSemaphoreSubmitInfo;
  SubmitInfo: VkSubmitInfo;
begin
  BufCount := Length(FPendingBufferCopies);
  ImgCount := Length(FPendingImageCopies);
  if BufCount + ImgCount = 0 then
    Exit(FLastSubmittedTimelineValue);

  if FDevice <> nil then
    Slot := FDevice.FrameIndex mod MaxFramesInFlight
  else
    Slot := 0;

  NeedOwnershipTransfer := FUseDedicatedTransferQueue and
    (FTransferQueueFamily <> FGraphicsQueueFamily) and
    ((FDevice = nil) or (FDevice.Handle = nil) or
     (FDevice.TransferQueueFamily <> FDevice.GraphicsQueueFamily));

  TransferCmd := AcquireTransferCommandBuffer(Slot);
  if (FDevice <> nil) and (FDevice.Handle <> nil) and
     (TransferCmd <> nil) and Assigned(vkBeginCommandBuffer) then
  begin
    FillChar(BeginInfo, SizeOf(BeginInfo), 0);
    BeginInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    BeginInfo.flags := VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    CheckVk(vkBeginCommandBuffer(TransferCmd, @BeginInfo), 'vkBeginCommandBuffer(AsyncTransfer)');
  end;

  { 1. Record buffer-to-buffer copies + release (or unified visibility) barriers }
  if BufCount > 0 then
  begin
    SetLength(BufBarriers, BufCount);
    for I := 0 to BufCount - 1 do
    begin
      BufItem := FPendingBufferCopies[I];
      if (FDevice <> nil) and (FDevice.Handle <> nil) and
         (TransferCmd <> nil) and Assigned(vkCmdCopyBuffer) and
         (BufItem.DstBuffer <> nil) then
        vkCmdCopyBuffer(TransferCmd, BufItem.SrcBuffer, BufItem.DstBuffer.Handle, 1, @BufItem.Region);

      FillChar(BufBarriers[I], SizeOf(VkBufferMemoryBarrier), 0);
      BufBarriers[I].sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
      BufBarriers[I].srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
      if NeedOwnershipTransfer then
      begin
        BufBarriers[I].dstAccessMask := 0;
        BufBarriers[I].srcQueueFamilyIndex := FTransferQueueFamily;
        BufBarriers[I].dstQueueFamilyIndex := FGraphicsQueueFamily;
        Inc(FQueueOwnershipTransferCount);
      end else
      begin
        BufBarriers[I].dstAccessMask :=
          VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT or
          VK_ACCESS_INDEX_READ_BIT or
          VK_ACCESS_UNIFORM_READ_BIT or
          VK_ACCESS_SHADER_READ_BIT;
        BufBarriers[I].srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        BufBarriers[I].dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      end;
      if BufItem.DstBuffer <> nil then
      begin
        BufBarriers[I].buffer := BufItem.DstBuffer.Handle;
        BufBarriers[I].offset := BufItem.Region.dstOffset;
        BufBarriers[I].size := BufItem.Region.size;
      end;
    end;

    if (FDevice <> nil) and (FDevice.Handle <> nil) and
       (TransferCmd <> nil) and Assigned(vkCmdPipelineBarrier) then
    begin
      if NeedOwnershipTransfer then
        vkCmdPipelineBarrier(TransferCmd,
          VK_PIPELINE_STAGE_TRANSFER_BIT,
          VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
          0, 0, nil, Length(BufBarriers), @BufBarriers[0], 0, nil)
      else
        vkCmdPipelineBarrier(TransferCmd,
          VK_PIPELINE_STAGE_TRANSFER_BIT,
          VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
          VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
          0, 0, nil, Length(BufBarriers), @BufBarriers[0], 0, nil);
    end;

    if NeedOwnershipTransfer then
    begin
      BaseIdx := Length(FPendingAcquireBuffers);
      SetLength(FPendingAcquireBuffers, BaseIdx + BufCount);
      for I := 0 to BufCount - 1 do
        FPendingAcquireBuffers[BaseIdx + I] := FPendingBufferCopies[I];
    end;
  end;

  { 2. Record buffer-to-image copies + release (or unified layout transition) barriers }
  for I := 0 to ImgCount - 1 do
  begin
    ImgItem := FPendingImageCopies[I];
    if ImgItem.DstTexture = nil then
      Continue;

    FillChar(ImgBarrier, SizeOf(ImgBarrier), 0);
    ImgBarrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    ImgBarrier.oldLayout := VK_IMAGE_LAYOUT_UNDEFINED;
    ImgBarrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    ImgBarrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    ImgBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    ImgBarrier.image := ImgItem.DstTexture.Image;
    ImgBarrier.subresourceRange.aspectMask := ImgItem.DstTexture.AspectMask;
    ImgBarrier.subresourceRange.baseMipLevel := ImgItem.MipLevel;
    ImgBarrier.subresourceRange.levelCount := 1;
    ImgBarrier.subresourceRange.baseArrayLayer := ImgItem.ArrayLayer;
    ImgBarrier.subresourceRange.layerCount := 1;
    ImgBarrier.srcAccessMask := 0;
    ImgBarrier.dstAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;

    if (FDevice <> nil) and (FDevice.Handle <> nil) and
       (TransferCmd <> nil) and Assigned(vkCmdPipelineBarrier) then
      vkCmdPipelineBarrier(TransferCmd,
        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, nil, 0, nil, 1, @ImgBarrier);

    if (FDevice <> nil) and (FDevice.Handle <> nil) and
       (TransferCmd <> nil) and Assigned(vkCmdCopyBufferToImage) then
      vkCmdCopyBufferToImage(TransferCmd, ImgItem.SrcBuffer, ImgItem.DstTexture.Image,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, @ImgItem.Region);

    if NeedOwnershipTransfer then
    begin
      ImgBarrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      if ImgItem.GenerateMipmaps and (ImgItem.DstTexture.Desc.MipLevels > 1) then
        ImgBarrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
      else
        ImgBarrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
      ImgBarrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
      ImgBarrier.dstAccessMask := 0;
      ImgBarrier.srcQueueFamilyIndex := FTransferQueueFamily;
      ImgBarrier.dstQueueFamilyIndex := FGraphicsQueueFamily;
      if (FDevice <> nil) and (FDevice.Handle <> nil) and
         (TransferCmd <> nil) and Assigned(vkCmdPipelineBarrier) then
        vkCmdPipelineBarrier(TransferCmd,
          VK_PIPELINE_STAGE_TRANSFER_BIT,
          VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
          0, 0, nil, 0, nil, 1, @ImgBarrier);
      Inc(FQueueOwnershipTransferCount);

      BaseIdx := Length(FPendingAcquireImages);
      SetLength(FPendingAcquireImages, BaseIdx + 1);
      FPendingAcquireImages[BaseIdx] := ImgItem;
      if ImgItem.GenerateMipmaps and (ImgItem.DstTexture.Desc.MipLevels > 1) then
      begin
        ImgItem.DstTexture.CurrentState := rsTransferDst;
        BaseIdx := Length(FPendingPostTransferMipmaps);
        SetLength(FPendingPostTransferMipmaps, BaseIdx + 1);
        FPendingPostTransferMipmaps[BaseIdx] := ImgItem.DstTexture;
      end else
        ImgItem.DstTexture.CurrentState := rsShaderRead;
    end else
    if ImgItem.GenerateMipmaps and (ImgItem.DstTexture.Desc.MipLevels > 1) then
    begin
      { Defer vkCmdBlitImage mipmap generation to the Graphics Queue command list }
      ImgItem.DstTexture.CurrentState := rsTransferDst;
      BaseIdx := Length(FPendingPostTransferMipmaps);
      SetLength(FPendingPostTransferMipmaps, BaseIdx + 1);
      FPendingPostTransferMipmaps[BaseIdx] := ImgItem.DstTexture;
    end else
    begin
      ImgBarrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      ImgBarrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
      ImgBarrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
      ImgBarrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;
      ImgBarrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      ImgBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      if (FDevice <> nil) and (FDevice.Handle <> nil) and
         (TransferCmd <> nil) and Assigned(vkCmdPipelineBarrier) then
        vkCmdPipelineBarrier(TransferCmd,
          VK_PIPELINE_STAGE_TRANSFER_BIT,
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
          0, 0, nil, 0, nil, 1, @ImgBarrier);
      ImgItem.DstTexture.CurrentState := rsShaderRead;
    end;
  end;

  if (FDevice <> nil) and (FDevice.Handle <> nil) and
     (TransferCmd <> nil) and Assigned(vkEndCommandBuffer) then
    CheckVk(vkEndCommandBuffer(TransferCmd), 'vkEndCommandBuffer(AsyncTransfer)');

  NextVal := FLastSubmittedTimelineValue + 1;
  TimelineSem := GetTransferTimelineSemaphore;

  if (FDevice <> nil) and (FDevice.Handle <> nil) and
     (FDevice.TransferQueue <> nil) and Assigned(vkQueueSubmit) then
  begin
    FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
    SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
    SubmitInfo.commandBufferCount := 1;
    SubmitInfo.pCommandBuffers := @TransferCmd;

    if FDevice.SupportsTimelineSemaphores then
    begin
      SignalSemHandle := TimelineSem.Handle;
      FillChar(TimelineSubmit, SizeOf(TimelineSubmit), 0);
      TimelineSubmit.sType := VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO;
      TimelineSubmit.signalSemaphoreValueCount := 1;
      TimelineSubmit.pSignalSemaphoreValues := @NextVal;
      SubmitInfo.pNext := @TimelineSubmit;
      SubmitInfo.signalSemaphoreCount := 1;
      SubmitInfo.pSignalSemaphores := @SignalSemHandle;
      FPendingBinaryWaitSemaphore := VK_NULL_HANDLE;
    end else
    begin
      SignalSemHandle := EnsureTransferBinarySemaphore(Slot);
      SubmitInfo.signalSemaphoreCount := 1;
      SubmitInfo.pSignalSemaphores := @SignalSemHandle;
      FPendingBinaryWaitSemaphore := SignalSemHandle;
    end;

    CheckVk(vkQueueSubmit(FDevice.TransferQueue, 1, @SubmitInfo, VK_NULL_HANDLE),
      'vkQueueSubmit(AsyncTransfer)');
    TimelineSem.FCounterValue := NextVal;
  end else
  begin
    TimelineSem.Signal(NextVal);
    FPendingBinaryWaitSemaphore := VK_NULL_HANDLE;
  end;

  FLastSubmittedTimelineValue := NextVal;
  FPendingGraphicsWaitTimelineValue := NextVal;
  SetLength(FPendingBufferCopies, 0);
  SetLength(FPendingImageCopies, 0);
  Inc(FTotalAsyncSubmissions);
  Inc(FTotalBatchedFlushes);
  Result := NextVal;
end;

function TCastleVulkanStagingUploader.ConsumePendingGraphicsWait(
  out ATimelineSemaphore: VkSemaphore; out AWaitValue: UInt64;
  out ABinarySemaphore: VkSemaphore): Boolean;
begin
  ATimelineSemaphore := VK_NULL_HANDLE;
  AWaitValue := 0;
  ABinarySemaphore := VK_NULL_HANDLE;
  Result := FPendingGraphicsWaitTimelineValue > 0;
  if not Result then
    Exit;

  AWaitValue := FPendingGraphicsWaitTimelineValue;
  if (FDevice <> nil) and FDevice.SupportsTimelineSemaphores and
     (FTransferTimelineSemaphore <> nil) then
    ATimelineSemaphore := FTransferTimelineSemaphore.Handle
  else
    ABinarySemaphore := FPendingBinaryWaitSemaphore;

  FPendingGraphicsWaitTimelineValue := 0;
  FPendingBinaryWaitSemaphore := VK_NULL_HANDLE;
end;

procedure TCastleVulkanStagingUploader.WaitForAsyncUploads(const ATimeoutNs: UInt64);
begin
  if (FLastSubmittedTimelineValue > 0) and (FTransferTimelineSemaphore <> nil) then
    FTransferTimelineSemaphore.Wait(FLastSubmittedTimelineValue, ATimeoutNs);
  if (FPendingBinaryWaitSemaphore <> VK_NULL_HANDLE) and
     (FDevice <> nil) and (FDevice.Handle <> nil) and
     (FDevice.TransferQueue <> nil) and Assigned(vkQueueWaitIdle) then
    vkQueueWaitIdle(FDevice.TransferQueue);
end;

function TCastleVulkanStagingUploader.FlushPendingUploads(
  const ACommandList: TVulkanRHICommandList): Cardinal;
var
  BufCount, ImgCount, I: Integer;
  DrainCount: Cardinal;
  Cmd: VkCommandBuffer;
  OneShotCmd: Boolean;
  BufBarriers: array of VkBufferMemoryBarrier;
  ImgBarrier: VkImageMemoryBarrier;
  BufItem: TVulkanStagedBufferCopy;
  ImgItem: TVulkanStagedImageCopy;
begin
  if FAsyncTransferEnabled and (ACommandList <> nil) and
     ((Length(FPendingBufferCopies) > 0) or (Length(FPendingImageCopies) > 0)) then
  begin
    Result := Cardinal(Length(FPendingBufferCopies) + Length(FPendingImageCopies));
    SubmitAsyncUploads;
    ApplyPendingGraphicsAcquireBarriers(ACommandList);
    Exit;
  end;

  DrainCount := ApplyPendingGraphicsAcquireBarriers(ACommandList);
  if ACommandList = nil then
    WaitForAsyncUploads;

  BufCount := Length(FPendingBufferCopies);
  ImgCount := Length(FPendingImageCopies);
  Result := DrainCount + Cardinal(BufCount + ImgCount);
  if BufCount + ImgCount = 0 then
    Exit;

  OneShotCmd := False;
  Cmd := nil;
  if ACommandList <> nil then
    Cmd := ACommandList.Handle
  else if (FDevice <> nil) and (FDevice.Handle <> nil) then
  begin
    Cmd := FDevice.BeginSingleTimeCommands;
    OneShotCmd := Cmd <> nil;
  end;

  { 1. Batch all pending buffer-to-buffer copies and emit a single consolidated pipeline barrier }
  if BufCount > 0 then
  begin
    SetLength(BufBarriers, BufCount);
    for I := 0 to BufCount - 1 do
    begin
      BufItem := FPendingBufferCopies[I];
      if (Cmd <> nil) and Assigned(vkCmdCopyBuffer) and (BufItem.DstBuffer <> nil) then
        vkCmdCopyBuffer(Cmd, BufItem.SrcBuffer, BufItem.DstBuffer.Handle, 1, @BufItem.Region);

      FillChar(BufBarriers[I], SizeOf(VkBufferMemoryBarrier), 0);
      BufBarriers[I].sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
      BufBarriers[I].srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
      BufBarriers[I].dstAccessMask :=
        VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT or
        VK_ACCESS_INDEX_READ_BIT or
        VK_ACCESS_UNIFORM_READ_BIT or
        VK_ACCESS_SHADER_READ_BIT;
      if FUseDedicatedTransferQueue and (FTransferQueueFamily <> FGraphicsQueueFamily) then
      begin
        BufBarriers[I].srcQueueFamilyIndex := FTransferQueueFamily;
        BufBarriers[I].dstQueueFamilyIndex := FGraphicsQueueFamily;
        Inc(FQueueOwnershipTransferCount);
      end else
      begin
        BufBarriers[I].srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        BufBarriers[I].dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      end;
      if BufItem.DstBuffer <> nil then
      begin
        BufBarriers[I].buffer := BufItem.DstBuffer.Handle;
        BufBarriers[I].offset := BufItem.Region.dstOffset;
        BufBarriers[I].size := BufItem.Region.size;
      end;
    end;

    if (Cmd <> nil) and Assigned(vkCmdPipelineBarrier) then
      vkCmdPipelineBarrier(Cmd,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
        VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        0, 0, nil, Length(BufBarriers), @BufBarriers[0], 0, nil);

    if ACommandList <> nil then
      Inc(ACommandList.FBarrierCount);
  end;

  { 2. Batch all pending buffer-to-image copies + layout transitions (+ optional mipmap blits) }
  for I := 0 to ImgCount - 1 do
  begin
    ImgItem := FPendingImageCopies[I];
    if ImgItem.DstTexture = nil then
      Continue;

    FillChar(ImgBarrier, SizeOf(ImgBarrier), 0);
    ImgBarrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    ImgBarrier.oldLayout := VK_IMAGE_LAYOUT_UNDEFINED;
    ImgBarrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    ImgBarrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    ImgBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    ImgBarrier.image := ImgItem.DstTexture.Image;
    ImgBarrier.subresourceRange.aspectMask := ImgItem.DstTexture.AspectMask;
    ImgBarrier.subresourceRange.baseMipLevel := ImgItem.MipLevel;
    ImgBarrier.subresourceRange.levelCount := 1;
    ImgBarrier.subresourceRange.baseArrayLayer := ImgItem.ArrayLayer;
    ImgBarrier.subresourceRange.layerCount := 1;
    ImgBarrier.srcAccessMask := 0;
    ImgBarrier.dstAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;

    if (Cmd <> nil) and Assigned(vkCmdPipelineBarrier) then
      vkCmdPipelineBarrier(Cmd,
        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, nil, 0, nil, 1, @ImgBarrier);

    if (Cmd <> nil) and Assigned(vkCmdCopyBufferToImage) then
      vkCmdCopyBufferToImage(Cmd, ImgItem.SrcBuffer, ImgItem.DstTexture.Image,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, @ImgItem.Region);

    if ImgItem.GenerateMipmaps and (ImgItem.DstTexture.Desc.MipLevels > 1) and
       (ACommandList <> nil) then
    begin
      ImgItem.DstTexture.CurrentState := rsTransferDst;
      ACommandList.GenerateMipmaps(ImgItem.DstTexture);
    end else
    begin
      ImgBarrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      ImgBarrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
      ImgBarrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
      ImgBarrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;
      if FUseDedicatedTransferQueue and (FTransferQueueFamily <> FGraphicsQueueFamily) then
      begin
        ImgBarrier.srcQueueFamilyIndex := FTransferQueueFamily;
        ImgBarrier.dstQueueFamilyIndex := FGraphicsQueueFamily;
        Inc(FQueueOwnershipTransferCount);
      end else
      begin
        ImgBarrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        ImgBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      end;

      if (Cmd <> nil) and Assigned(vkCmdPipelineBarrier) then
        vkCmdPipelineBarrier(Cmd,
          VK_PIPELINE_STAGE_TRANSFER_BIT,
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
          0, 0, nil, 0, nil, 1, @ImgBarrier);

      ImgItem.DstTexture.CurrentState := rsShaderRead;
      if ACommandList <> nil then
        Inc(ACommandList.FBarrierCount, 2);
    end;
  end;

  if OneShotCmd and (FDevice <> nil) then
    FDevice.EndSingleTimeCommands(Cmd);

  SetLength(FPendingBufferCopies, 0);
  SetLength(FPendingImageCopies, 0);
  Inc(FTotalBatchedFlushes);
end;

function TCastleVulkanStagingUploader.GetPendingBufferCopyCount: Cardinal;
begin
  Result := Cardinal(Length(FPendingBufferCopies));
end;

function TCastleVulkanStagingUploader.GetPendingImageCopyCount: Cardinal;
begin
  Result := Cardinal(Length(FPendingImageCopies));
end;

function TCastleVulkanStagingUploader.GetCurrentFrameWriteOffset: VkDeviceSize;
var
  Slot: Cardinal;
begin
  if FDevice <> nil then
    Slot := FDevice.FrameIndex mod MaxFramesInFlight
  else
    Slot := 0;
  Result := FRingWriteOffsets[Slot];
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanWorkerCommandPoolManager                                        }
{ ---------------------------------------------------------------------------- }

{$ifndef CASTLE_DISABLE_THREADS}
type
  TCastleVulkanRenderWorkerThread = class(TThread)
  private
    FWorkerIndex: Cardinal;
    FWakeEvent: TEvent;
    FDoneEvent: TEvent;
    FTaskProc: TVulkanParallelWorkerTaskProc;
    FTaskCmdList: TVulkanRHICommandList;
    FTaskErrorMsg: String;
    FLastOsThreadId: TThreadID;
    FShuttingDown: Boolean;
  protected
    procedure Execute; override;
  public
    constructor CreateWorker(const AWorkerIndex: Cardinal);
    destructor Destroy; override;
    procedure DispatchTask(const ATaskProc: TVulkanParallelWorkerTaskProc;
      const ACmdList: TVulkanRHICommandList);
    procedure WaitTaskDone;
    procedure SignalShutdown;
    property LastOsThreadId: TThreadID read FLastOsThreadId;
    property TaskErrorMsg: String read FTaskErrorMsg;
  end;

constructor TCastleVulkanRenderWorkerThread.CreateWorker(const AWorkerIndex: Cardinal);
begin
  FWorkerIndex := AWorkerIndex;
  FWakeEvent := TEvent.Create(nil, False, False, '');
  FDoneEvent := TEvent.Create(nil, True, True, '');
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TCastleVulkanRenderWorkerThread.Destroy;
begin
  SignalShutdown;
  inherited Destroy;
  FreeAndNil(FWakeEvent);
  FreeAndNil(FDoneEvent);
end;

procedure TCastleVulkanRenderWorkerThread.Execute;
begin
  FLastOsThreadId := GetCurrentThreadId;
  while not Terminated do
  begin
    FWakeEvent.WaitFor(INFINITE);
    if Terminated or FShuttingDown then
      Break;
    FLastOsThreadId := GetCurrentThreadId;
    FTaskErrorMsg := '';
    try
      if Assigned(FTaskProc) then
        FTaskProc(FWorkerIndex, FTaskCmdList);
    except
      on E: Exception do
        FTaskErrorMsg := E.ClassName + ': ' + E.Message;
    end;
    FTaskProc := nil;
    FTaskCmdList := nil;
    FDoneEvent.SetEvent;
  end;
end;

procedure TCastleVulkanRenderWorkerThread.DispatchTask(
  const ATaskProc: TVulkanParallelWorkerTaskProc;
  const ACmdList: TVulkanRHICommandList);
begin
  FTaskProc := ATaskProc;
  FTaskCmdList := ACmdList;
  FTaskErrorMsg := '';
  FDoneEvent.ResetEvent;
  FWakeEvent.SetEvent;
end;

procedure TCastleVulkanRenderWorkerThread.WaitTaskDone;
begin
  FDoneEvent.WaitFor(INFINITE);
end;

procedure TCastleVulkanRenderWorkerThread.SignalShutdown;
begin
  if not FShuttingDown then
  begin
    FShuttingDown := True;
    Terminate;
    if FWakeEvent <> nil then
      FWakeEvent.SetEvent;
    WaitFor;
  end;
end;
{$endif}

constructor TCastleVulkanWorkerCommandPoolManager.Create(const ADevice: TVulkanRHIDevice;
  const AWorkerCount: Cardinal);
begin
  inherited Create;
  FDevice := ADevice;
  FWorkerCount := EnsureRange(AWorkerCount, Cardinal(1), Cardinal(64));
  {$ifdef CASTLE_DISABLE_THREADS}
  FUseWorkerThreads := False;
  {$else}
  FUseWorkerThreads := True;
  {$endif}
  SetLength(FLastWorkerThreadIds, FWorkerCount);
  EnsureWorkerPoolsAllocated;
end;

destructor TCastleVulkanWorkerCommandPoolManager.Destroy;
begin
  ShutdownWorkerThreads;
  DestroyWorkerPools;
  inherited;
end;

procedure TCastleVulkanWorkerCommandPoolManager.EnsureWorkerPoolsAllocated;
var
  W, Slot: Cardinal;
  PoolInfo: VkCommandPoolCreateInfo;
begin
  if Cardinal(Length(FWorkerSlots)) = FWorkerCount then
    Exit;

  SetLength(FWorkerSlots, FWorkerCount);
  SetLength(FLastWorkerThreadIds, FWorkerCount);
  for W := 0 to FWorkerCount - 1 do
    for Slot := 0 to MaxFramesInFlight - 1 do
      if FWorkerSlots[W][Slot].CommandPool = VK_NULL_HANDLE then
      begin
        FWorkerSlots[W][Slot].UsedCount := 0;
        if (FDevice <> nil) and (FDevice.Handle <> nil) and Assigned(vkCreateCommandPool) then
        begin
          FillChar(PoolInfo, SizeOf(PoolInfo), 0);
          PoolInfo.sType := VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
          PoolInfo.flags := VK_COMMAND_POOL_CREATE_TRANSIENT_BIT;
          PoolInfo.queueFamilyIndex := FDevice.GraphicsQueueFamily;
          CheckVk(vkCreateCommandPool(FDevice.Handle, @PoolInfo, nil,
            @FWorkerSlots[W][Slot].CommandPool), 'vkCreateCommandPool(Worker)');
        end else
          FWorkerSlots[W][Slot].CommandPool :=
            VkCommandPool(PtrUInt($72000000) + PtrUInt(W * MaxFramesInFlight + Slot + 1));
      end;
end;

function TCastleVulkanWorkerCommandPoolManager.EnsureWorkerThreadsSpawned: Boolean;
{$ifndef CASTLE_DISABLE_THREADS}
var
  W: Integer;
{$endif}
begin
  {$ifdef CASTLE_DISABLE_THREADS}
  Result := False;
  {$else}
  if not FUseWorkerThreads then
    Exit(False);
  if FThreadsSpawned and (Cardinal(Length(FWorkerThreads)) = FWorkerCount) then
    Exit(True);

  ShutdownWorkerThreads;
  try
    SetLength(FWorkerThreads, FWorkerCount);
    for W := 0 to Integer(FWorkerCount) - 1 do
      FWorkerThreads[W] := TCastleVulkanRenderWorkerThread.CreateWorker(Cardinal(W));
    FThreadsSpawned := True;
    Result := True;
  except
    on E: Exception do
    begin
      WritelnWarning('Vulkan',
        'Could not spawn OS worker threads for parallel Vulkan command recording (%s); falling back to sequential worker-pool recording.',
        [E.Message]);
      ShutdownWorkerThreads;
      FUseWorkerThreads := False;
      Result := False;
    end;
  end;
  {$endif}
end;

procedure TCastleVulkanWorkerCommandPoolManager.ShutdownWorkerThreads;
{$ifndef CASTLE_DISABLE_THREADS}
var
  I: Integer;
{$endif}
begin
  {$ifndef CASTLE_DISABLE_THREADS}
  for I := 0 to High(FWorkerThreads) do
    FreeAndNil(FWorkerThreads[I]);
  SetLength(FWorkerThreads, 0);
  {$endif}
  FThreadsSpawned := False;
end;

procedure TCastleVulkanWorkerCommandPoolManager.DestroyWorkerPools;
var
  W, Slot, I: Integer;
begin
  for W := 0 to High(FWorkerSlots) do
    for Slot := 0 to MaxFramesInFlight - 1 do
    begin
      for I := 0 to High(FWorkerSlots[W][Slot].CommandLists) do
        FreeAndNil(FWorkerSlots[W][Slot].CommandLists[I]);
      SetLength(FWorkerSlots[W][Slot].CommandLists, 0);
      FWorkerSlots[W][Slot].UsedCount := 0;
      if (FDevice <> nil) and (FDevice.Handle <> nil) and
         (FWorkerSlots[W][Slot].CommandPool <> VK_NULL_HANDLE) and
         Assigned(vkDestroyCommandPool) then
        vkDestroyCommandPool(FDevice.Handle, FWorkerSlots[W][Slot].CommandPool, nil);
      FWorkerSlots[W][Slot].CommandPool := VK_NULL_HANDLE;
    end;
  SetLength(FWorkerSlots, 0);
end;

procedure TCastleVulkanWorkerCommandPoolManager.SetWorkerCount(const AValue: Cardinal);
var
  Clamped: Cardinal;
begin
  Clamped := EnsureRange(AValue, Cardinal(1), Cardinal(64));
  if Clamped = FWorkerCount then
    Exit;
  if FDevice <> nil then
    FDevice.WaitIdle;
  ShutdownWorkerThreads;
  DestroyWorkerPools;
  FWorkerCount := Clamped;
  EnsureWorkerPoolsAllocated;
end;

procedure TCastleVulkanWorkerCommandPoolManager.ResetFrameSlot(const AFrameSlot: Cardinal);
var
  Slot: Cardinal;
  W: Integer;
begin
  Slot := AFrameSlot mod MaxFramesInFlight;
  EnsureWorkerPoolsAllocated;
  for W := 0 to High(FWorkerSlots) do
  begin
    FWorkerSlots[W][Slot].UsedCount := 0;
    if (FDevice <> nil) and (FDevice.Handle <> nil) and
       (FWorkerSlots[W][Slot].CommandPool <> VK_NULL_HANDLE) and
       Assigned(vkResetCommandPool) then
      CheckVk(vkResetCommandPool(FDevice.Handle, FWorkerSlots[W][Slot].CommandPool, 0),
        'vkResetCommandPool(Worker)');
  end;
  Inc(FTotalPoolResets);
end;

function TCastleVulkanWorkerCommandPoolManager.AcquireWorkerSecondaryCommandList(
  const AWorkerIndex: Cardinal): TVulkanRHICommandList;
var
  EffWorker, Slot, UsedIdx: Cardinal;
  NewList: TVulkanRHICommandList;
begin
  EnsureWorkerPoolsAllocated;
  EffWorker := AWorkerIndex mod Max(Cardinal(1), FWorkerCount);
  if FDevice <> nil then
    Slot := FDevice.FrameIndex mod MaxFramesInFlight
  else
    Slot := 0;

  UsedIdx := FWorkerSlots[EffWorker][Slot].UsedCount;
  if UsedIdx >= Cardinal(Length(FWorkerSlots[EffWorker][Slot].CommandLists)) then
  begin
    NewList := TVulkanRHICommandList.CreateFromPool(
      FDevice, FWorkerSlots[EffWorker][Slot].CommandPool, cllSecondary, False);
    SetLength(FWorkerSlots[EffWorker][Slot].CommandLists, UsedIdx + 1);
    FWorkerSlots[EffWorker][Slot].CommandLists[UsedIdx] := NewList;
  end;
  Result := FWorkerSlots[EffWorker][Slot].CommandLists[UsedIdx];
  Inc(FWorkerSlots[EffWorker][Slot].UsedCount);
end;

function TCastleVulkanWorkerCommandPoolManager.ExecuteParallelRecording(
  const ATaskCount: Cardinal;
  const ATaskProc: TVulkanParallelWorkerTaskProc;
  out ARecordedLists: TVulkanCommandListArray): Cardinal;
var
  EffWorkers, W: Cardinal;
  WorkerCmds: array of TVulkanRHICommandList;
  {$ifndef CASTLE_DISABLE_THREADS}
  FirstErr: String;
  WorkerThread: TCastleVulkanRenderWorkerThread;
  {$endif}
begin
  SetLength(ARecordedLists, 0);
  if (ATaskCount = 0) or not Assigned(ATaskProc) then
    Exit(0);

  EnsureWorkerPoolsAllocated;
  EffWorkers := Min(ATaskCount, Max(Cardinal(1), FWorkerCount));
  SetLength(ARecordedLists, EffWorkers);
  SetLength(WorkerCmds, EffWorkers);
  for W := 0 to EffWorkers - 1 do
  begin
    WorkerCmds[W] := AcquireWorkerSecondaryCommandList(W);
    ARecordedLists[W] := WorkerCmds[W];
  end;

  Inc(FTotalParallelDispatches);
  Inc(FTotalSecondaryListsRecorded, EffWorkers);

  {$ifndef CASTLE_DISABLE_THREADS}
  if (EffWorkers >= 2) and FUseWorkerThreads and EnsureWorkerThreadsSpawned then
  begin
    FirstErr := '';
    for W := 0 to EffWorkers - 1 do
    begin
      WorkerThread := TCastleVulkanRenderWorkerThread(FWorkerThreads[W]);
      WorkerThread.DispatchTask(ATaskProc, WorkerCmds[W]);
    end;
    for W := 0 to EffWorkers - 1 do
    begin
      WorkerThread := TCastleVulkanRenderWorkerThread(FWorkerThreads[W]);
      WorkerThread.WaitTaskDone;
      FLastWorkerThreadIds[W] := WorkerThread.LastOsThreadId;
      if (FirstErr = '') and (WorkerThread.TaskErrorMsg <> '') then
        FirstErr := WorkerThread.TaskErrorMsg;
    end;
    if FirstErr <> '' then
      raise ERHIError.Create('Parallel Vulkan command recording worker error: ' + FirstErr);
    Exit(EffWorkers);
  end;
  {$endif}

  for W := 0 to EffWorkers - 1 do
  begin
    FLastWorkerThreadIds[W] := GetCurrentThreadId;
    ATaskProc(W, WorkerCmds[W]);
  end;
  Result := EffWorkers;
end;

function TCastleVulkanWorkerCommandPoolManager.GetWorkerCommandPool(
  const AWorkerIndex, AFrameSlot: Cardinal): VkCommandPool;
var
  EffWorker, Slot: Cardinal;
begin
  EnsureWorkerPoolsAllocated;
  if Length(FWorkerSlots) = 0 then
    Exit(VK_NULL_HANDLE);
  EffWorker := AWorkerIndex mod Cardinal(Length(FWorkerSlots));
  Slot := AFrameSlot mod MaxFramesInFlight;
  Result := FWorkerSlots[EffWorker][Slot].CommandPool;
end;

function TCastleVulkanWorkerCommandPoolManager.GetWorkerLastThreadId(
  const AWorkerIndex: Cardinal): TThreadID;
begin
  if AWorkerIndex < Cardinal(Length(FLastWorkerThreadIds)) then
    Result := FLastWorkerThreadIds[AWorkerIndex]
  else
    Result := TThreadID(0);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTimelineSemaphore                                               }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTimelineSemaphore.Create(const ADevice: TVulkanRHIDevice;
  const AInitialValue: UInt64);
var
  TypeInfo: VkSemaphoreTypeCreateInfo;
  SemInfo: VkSemaphoreCreateInfo;
begin
  inherited Create;
  FDevice := ADevice;
  FCounterValue := AInitialValue;

  if (FDevice <> nil) and (FDevice.Handle <> nil) and Assigned(vkCreateSemaphore) and
     FDevice.SupportsTimelineSemaphores then
  begin
    FillChar(TypeInfo, SizeOf(TypeInfo), 0);
    TypeInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO;
    TypeInfo.semaphoreType := VK_SEMAPHORE_TYPE_TIMELINE;
    TypeInfo.initialValue := AInitialValue;

    FillChar(SemInfo, SizeOf(SemInfo), 0);
    SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    SemInfo.pNext := @TypeInfo;
    CheckVk(vkCreateSemaphore(FDevice.Handle, @SemInfo, nil, @FHandle), 'vkCreateSemaphore(Timeline)');
  end else
    FHandle := VkSemaphore(PtrUInt($66000001));
end;

destructor TCastleVulkanTimelineSemaphore.Destroy;
begin
  if (FDevice <> nil) and (FDevice.Handle <> nil) and (FHandle <> VK_NULL_HANDLE) and
     Assigned(vkDestroySemaphore) and FDevice.SupportsTimelineSemaphores then
    vkDestroySemaphore(FDevice.Handle, FHandle, nil);
  FHandle := VK_NULL_HANDLE;
  inherited;
end;

procedure TCastleVulkanTimelineSemaphore.Signal(const AValue: UInt64);
var
  SigInfo: VkSemaphoreSignalInfo;
begin
  if AValue > FCounterValue then
    FCounterValue := AValue;

  if (FDevice <> nil) and (FDevice.Handle <> nil) and (FHandle <> VK_NULL_HANDLE) and
     FDevice.SupportsTimelineSemaphores and Assigned(vkSignalSemaphore) then
  begin
    FillChar(SigInfo, SizeOf(SigInfo), 0);
    SigInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO;
    SigInfo.semaphore := FHandle;
    SigInfo.value := AValue;
    CheckVk(vkSignalSemaphore(FDevice.Handle, @SigInfo), 'vkSignalSemaphore');
  end;
end;

function TCastleVulkanTimelineSemaphore.Wait(const AValue: UInt64;
  const ATimeoutNs: UInt64): Boolean;
var
  WaitInfo: VkSemaphoreWaitInfo;
  Res: VkResult;
begin
  if (FDevice <> nil) and (FDevice.Handle <> nil) and (FHandle <> VK_NULL_HANDLE) and
     FDevice.SupportsTimelineSemaphores and Assigned(vkWaitSemaphores) then
  begin
    FillChar(WaitInfo, SizeOf(WaitInfo), 0);
    WaitInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO;
    WaitInfo.semaphoreCount := 1;
    WaitInfo.pSemaphores := @FHandle;
    WaitInfo.pValues := @AValue;
    Res := vkWaitSemaphores(FDevice.Handle, @WaitInfo, ATimeoutNs);
    Result := Res = VK_SUCCESS;
  end else
    Result := FCounterValue >= AValue;
end;

function TCastleVulkanTimelineSemaphore.GetCounterValue: UInt64;
begin
  Result := FCounterValue;
  if (FDevice <> nil) and (FDevice.Handle <> nil) and (FHandle <> VK_NULL_HANDLE) and
     FDevice.SupportsTimelineSemaphores and Assigned(vkGetSemaphoreCounterValue) then
    vkGetSemaphoreCounterValue(FDevice.Handle, FHandle, @Result);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTimestampProfiler                                               }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTimestampProfiler.Create(const ADevice: TVulkanRHIDevice;
  const AMaxPassesPerFrame: Cardinal);
var
  Slot: Cardinal;
  PoolDesc: TRHIQueryPoolDesc;
begin
  inherited Create;
  FDevice := ADevice;
  FMaxPassesPerFrame := Max(Cardinal(1), AMaxPassesPerFrame);
  PoolDesc := TRHIQueryPoolDesc.Create(qtTimestamp, FMaxPassesPerFrame * 2, 'FrameTimestampPool');
  for Slot := 0 to MaxFramesInFlight - 1 do
    FPools[Slot] := TVulkanRHIQueryPool.Create(ADevice, PoolDesc);
end;

destructor TCastleVulkanTimestampProfiler.Destroy;
var
  Slot: Cardinal;
begin
  for Slot := 0 to MaxFramesInFlight - 1 do
  begin
    SetLength(FFramePasses[Slot], 0);
    FreeAndNil(FPools[Slot]);
  end;
  SetLength(FCompletedPasses, 0);
  inherited;
end;

procedure TCastleVulkanTimestampProfiler.BeginFrame(const ACmd: TRHICommandList;
  const AFrameIndex: Cardinal);
var
  Slot: Cardinal;
  PassCount, I: Integer;
  QueryCount: Cardinal;
  Ticks: array of UInt64;
  PeriodNs: Single;
  DeltaTicks: UInt64;
begin
  Slot := AFrameIndex mod MaxFramesInFlight;
  FCurrentSlot := Slot;
  PassCount := Length(FFramePasses[Slot]);
  if (PassCount > 0) and (FPools[Slot] <> nil) then
  begin
    QueryCount := Cardinal(PassCount) * 2;
    SetLength(Ticks, QueryCount);
    if FPools[Slot].GetResults(0, QueryCount, Ticks, False) then
    begin
      if (FDevice <> nil) and (FDevice.Capabilities.TimestampPeriodNanoseconds > 0) then
        PeriodNs := FDevice.Capabilities.TimestampPeriodNanoseconds
      else
        PeriodNs := 1.0;

      FLastFrameTotalGpuTimeMs := 0.0;
      SetLength(FCompletedPasses, PassCount);
      for I := 0 to PassCount - 1 do
      begin
        FCompletedPasses[I] := FFramePasses[Slot][I];
        if Ticks[FCompletedPasses[I].EndQueryIndex] >= Ticks[FCompletedPasses[I].BeginQueryIndex] then
          DeltaTicks := Ticks[FCompletedPasses[I].EndQueryIndex] - Ticks[FCompletedPasses[I].BeginQueryIndex]
        else
          DeltaTicks := 0;
        { Convert nanoseconds (DeltaTicks * PeriodNs) -> milliseconds (/ 1,000,000) }
        FCompletedPasses[I].CompletedGpuTimeMs := (Double(DeltaTicks) * Double(PeriodNs)) / 1000000.0;
        FLastFrameTotalGpuTimeMs := FLastFrameTotalGpuTimeMs + FCompletedPasses[I].CompletedGpuTimeMs;
      end;
    end;
  end;

  SetLength(FFramePasses[Slot], 0);
  if (ACmd <> nil) and (FPools[Slot] <> nil) then
    ACmd.ResetQueryPool(FPools[Slot], 0, FMaxPassesPerFrame * 2)
  else if (FPools[Slot] <> nil) and (Length(FPools[Slot].FQueryWritten) > 0) then
    FillChar(FPools[Slot].FQueryWritten[0], Length(FPools[Slot].FQueryWritten) * SizeOf(Boolean), 0);
end;

function TCastleVulkanTimestampProfiler.BeginPass(const ACmd: TRHICommandList;
  const APassName: String): Integer;
var
  Slot: Cardinal;
  PassIdx: Integer;
begin
  Slot := FCurrentSlot mod MaxFramesInFlight;
  PassIdx := Length(FFramePasses[Slot]);
  if Cardinal(PassIdx) >= FMaxPassesPerFrame then
    Exit(-1);

  SetLength(FFramePasses[Slot], PassIdx + 1);
  FFramePasses[Slot][PassIdx].PassName := APassName;
  FFramePasses[Slot][PassIdx].BeginQueryIndex := Cardinal(PassIdx * 2);
  FFramePasses[Slot][PassIdx].EndQueryIndex := Cardinal(PassIdx * 2 + 1);
  FFramePasses[Slot][PassIdx].CompletedGpuTimeMs := 0.0;

  if (ACmd <> nil) and (FPools[Slot] <> nil) then
    ACmd.WriteTimestamp(FPools[Slot], FFramePasses[Slot][PassIdx].BeginQueryIndex, ssVertex);
  Result := PassIdx;
end;

procedure TCastleVulkanTimestampProfiler.EndPass(const ACmd: TRHICommandList;
  const APassIndex: Integer);
var
  Slot: Cardinal;
begin
  Slot := FCurrentSlot mod MaxFramesInFlight;
  if (APassIndex < 0) or (APassIndex >= Length(FFramePasses[Slot])) then
    Exit;
  if (ACmd <> nil) and (FPools[Slot] <> nil) then
    ACmd.WriteTimestamp(FPools[Slot], FFramePasses[Slot][APassIndex].EndQueryIndex, ssFragment);
end;

function TCastleVulkanTimestampProfiler.GetPassTimeMs(const APassName: String): Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FCompletedPasses) do
    if FCompletedPasses[I].PassName = APassName then
      Exit(FCompletedPasses[I].CompletedGpuTimeMs);
end;

function TCastleVulkanTimestampProfiler.GetQueryPoolForSlot(
  const AFrameSlot: Cardinal): TVulkanRHIQueryPool;
begin
  Result := FPools[AFrameSlot mod MaxFramesInFlight];
end;

function TCastleVulkanTimestampProfiler.GetCompletedPassCount: Cardinal;
begin
  Result := Cardinal(Length(FCompletedPasses));
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanComputeCuller                                                   }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanComputeCuller.Create(const ADevice: TVulkanRHIDevice;
  const AMaxInstances, AWorkgroupSizeX: Cardinal);
var
  I: Integer;
begin
  inherited Create;
  FDevice := ADevice;
  FMaxInstances := Max(Cardinal(1), AMaxInstances);
  if AWorkgroupSizeX = 0 then
    FWorkgroupSizeX := 64
  else
    FWorkgroupSizeX := AWorkgroupSizeX;

  FillChar(FCullingUniforms, SizeOf(FCullingUniforms), 0);
  { Default frustum planes: all-pass half-spaces (normal = 0,0,0, D = 1.0 >= 0) }
  for I := 0 to 5 do
    FCullingUniforms.FrustumPlanes[I] := Vector4(0, 0, 0, 1.0);
  FCullingUniforms.EnableFrustumCulling := 1;
  FCullingUniforms.EnableDistanceCulling := 0;
  FHiZViewProjMatrix := TMatrix4.Identity;
  FHiZCullingEnabled := False;
end;

destructor TCastleVulkanComputeCuller.Destroy;
begin
  SetLength(FUploadedInstances, 0);
  SetLength(FHiZMipWidths, 0);
  SetLength(FHiZMipHeights, 0);
  SetLength(FHiZMipChain, 0);
  FreeAndNil(FHiZDescriptorSet);
  FreeAndNil(FHiZDescriptorLayout);
  FreeAndNil(FHiZDownsampleShader);
  FreeAndNil(FHiZSampler);
  FreeAndNil(FHiZPyramidTexture);
  FHiZDownsamplePipeline := nil; // Owned by FDevice.FComputePipelineMap
  FreeAndNil(FDescriptorSet);
  FreeAndNil(FDescriptorLayout);
  FreeAndNil(FComputeShader);
  FreeAndNil(FCullingUniformBuffer);
  FreeAndNil(FInstanceInputBuffer);
  FreeAndNil(FIndirectOutputBuffer);
  FreeAndNil(FVisibilityOutputBuffer);
  FComputePipeline := nil; // Owned by FDevice.FComputePipelineMap
  inherited;
end;

procedure TCastleVulkanComputeCuller.EnsureResourcesCreated;
var
  Bindings: array[0..3] of TRHIDescriptorBindingDesc;
  ShaderGen: TCastleShaderGeneratorRHI;
  ComputeGLSL: String;
  BuiltInSPIRV: TSPIRVBytecode;
  PipeDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FComputePipeline <> nil) then
    Exit;

  FCullingUniformBuffer := FDevice.CreateBuffer(
    TRHIBufferDesc.Create(SizeOf(TCastleGpuCullingUniformBlock),
      [buUniform], muCpuToGpu, 'GpuCullingUniformsUBO'),
    @FCullingUniforms);

  FInstanceInputBuffer := FDevice.CreateBuffer(
    TRHIBufferDesc.Create(PtrUInt(FMaxInstances) * SizeOf(TCastleGpuCullingInstance),
      [buStorage, buTransferDst], muCpuToGpu, 'GpuCullingInstancesSSBO'),
    nil);

  FIndirectOutputBuffer := FDevice.CreateBuffer(
    TRHIBufferDesc.Create(PtrUInt(FMaxInstances) * SizeOf(TRHIDrawIndexedIndirectCommand),
      [buStorage, buIndirect, buTransferSrc, buTransferDst], muCpuToGpu, 'GpuCullingIndirectOutSSBO'),
    nil);

  FVisibilityOutputBuffer := FDevice.CreateBuffer(
    TRHIBufferDesc.Create(PtrUInt(FMaxInstances + 1) * SizeOf(Cardinal),
      [buStorage, buIndirect, buTransferSrc, buTransferDst], muCpuToGpu, 'GpuCullingVisibilityOutSSBO'),
    nil);

  FillChar(Bindings, SizeOf(Bindings), 0);
  Bindings[0].Binding := 0;
  Bindings[0].DescriptorType := dtUniformBuffer;
  Bindings[0].Count := 1;
  Bindings[0].StageFlags := [ssCompute];

  Bindings[1].Binding := 1;
  Bindings[1].DescriptorType := dtStorageBuffer;
  Bindings[1].Count := 1;
  Bindings[1].StageFlags := [ssCompute];

  Bindings[2].Binding := 2;
  Bindings[2].DescriptorType := dtStorageBuffer;
  Bindings[2].Count := 1;
  Bindings[2].StageFlags := [ssCompute];

  Bindings[3].Binding := 3;
  Bindings[3].DescriptorType := dtStorageBuffer;
  Bindings[3].Count := 1;
  Bindings[3].StageFlags := [ssCompute];

  FDescriptorLayout := FDevice.CreateDescriptorSetLayout(Bindings);
  FDescriptorSet := FDevice.CreateDescriptorSet(FDescriptorLayout);
  FDescriptorSet.BindUniformBuffer(0, FCullingUniformBuffer, 0, SizeOf(TCastleGpuCullingUniformBlock));
  FDescriptorSet.BindStorageBuffer(1, FInstanceInputBuffer, 0,
    PtrUInt(FMaxInstances) * SizeOf(TCastleGpuCullingInstance));
  FDescriptorSet.BindStorageBuffer(2, FIndirectOutputBuffer, 0,
    PtrUInt(FMaxInstances) * SizeOf(TRHIDrawIndexedIndirectCommand));
  FDescriptorSet.BindStorageBuffer(3, FVisibilityOutputBuffer, 0,
    PtrUInt(FMaxInstances + 1) * SizeOf(Cardinal));
  FDescriptorSet.Update;

  ShaderGen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    ComputeGLSL := ShaderGen.GenerateComputeCullingShader(FWorkgroupSizeX);
  finally
    FreeAndNil(ShaderGen);
  end;

  if TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
    FComputeShader := FDevice.CreateShaderModuleFromGLSL(ssCompute, ComputeGLSL, 'GpuCullingCS')
  else
  if TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssCompute, ComputeGLSL, 'GpuCullingCS', BuiltInSPIRV) and
     (Length(BuiltInSPIRV) > 0) then
    FComputeShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
      @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'GpuCullingCS')
  else
  begin
    BuiltInSPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssCompute);
    FComputeShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
      @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'GpuCullingCS');
  end;

  PipeDesc := Default(TRHIComputePipelineDesc);
  PipeDesc.ComputeShader := FComputeShader;
  SetLength(PipeDesc.DescriptorSetLayouts, 1);
  PipeDesc.DescriptorSetLayouts[0] := FDescriptorLayout;
  PipeDesc.DebugName := 'GpuComputeCullingPSO';
  FComputePipeline := FDevice.GetOrCreateComputePipeline(PipeDesc);
end;

procedure TCastleVulkanComputeCuller.EnsureHiZPipelineCreated;
var
  SamplerDesc: TRHISamplerDesc;
  Bindings: array[0..1] of TRHIDescriptorBindingDesc;
  ShaderGen: TCastleShaderGeneratorRHI;
  HiZGLSL: String;
  BuiltInSPIRV: TSPIRVBytecode;
  PipeDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FHiZDownsamplePipeline <> nil) then
    Exit;

  FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
  SamplerDesc.MinFilter := sfNearest;
  SamplerDesc.MagFilter := sfNearest;
  SamplerDesc.MipFilter := sfNearest;
  SamplerDesc.AddressModeU := amClampToEdge;
  SamplerDesc.AddressModeV := amClampToEdge;
  SamplerDesc.AddressModeW := amClampToEdge;
  SamplerDesc.MaxAnisotropy := 1.0;
  SamplerDesc.MaxLod := 1000.0;
  FHiZSampler := FDevice.CreateSampler(SamplerDesc);

  FillChar(Bindings, SizeOf(Bindings), 0);
  Bindings[0].Binding := 0;
  Bindings[0].DescriptorType := dtCombinedImageSampler;
  Bindings[0].Count := 1;
  Bindings[0].StageFlags := [ssCompute];

  Bindings[1].Binding := 1;
  Bindings[1].DescriptorType := dtStorageImage;
  Bindings[1].Count := 1;
  Bindings[1].StageFlags := [ssCompute];

  FHiZDescriptorLayout := FDevice.CreateDescriptorSetLayout(Bindings);
  FHiZDescriptorSet := FDevice.CreateDescriptorSet(FHiZDescriptorLayout);

  ShaderGen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    HiZGLSL := ShaderGen.GenerateHiZDownsampleComputeShader(8, 8);
  finally
    FreeAndNil(ShaderGen);
  end;

  if TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
    FHiZDownsampleShader := FDevice.CreateShaderModuleFromGLSL(ssCompute, HiZGLSL, 'HiZDownsampleCS')
  else
  if TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssCompute, HiZGLSL, 'HiZDownsampleCS', BuiltInSPIRV) and
     (Length(BuiltInSPIRV) > 0) then
    FHiZDownsampleShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
      @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'HiZDownsampleCS')
  else
  begin
    BuiltInSPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssCompute);
    FHiZDownsampleShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
      @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'HiZDownsampleCS');
  end;

  PipeDesc := Default(TRHIComputePipelineDesc);
  PipeDesc.ComputeShader := FHiZDownsampleShader;
  SetLength(PipeDesc.DescriptorSetLayouts, 1);
  PipeDesc.DescriptorSetLayouts[0] := FHiZDescriptorLayout;
  PipeDesc.PushConstantSize := SizeOf(TCastleHiZPushConstants);
  PipeDesc.PushConstantStages := [ssCompute];
  PipeDesc.DebugName := 'HiZDownsampleComputePSO';
  FHiZDownsamplePipeline := FDevice.GetOrCreateComputePipeline(PipeDesc);
end;

function TCastleVulkanComputeCuller.BuildHiZPyramid(const ACmd: TRHICommandList;
  const AWidth, AHeight: Cardinal;
  const ALevel0DepthData: PSingle): Cardinal;
var
  EffectiveW, EffectiveH, MipCount, M, SrcW, SrcH, DstW, DstH, DX, DY, I: Cardinal;
  TexDesc: TRHITextureDesc;
  PushConsts: TCastleHiZPushConstants;

  function FetchSrcDepth(const AMip: Cardinal; const AX, AY, AMaxW, AMaxH: Integer): Single;
  var
    ClampedX, ClampedY: Cardinal;
  begin
    ClampedX := Cardinal(EnsureRange(AX, 0, Max(0, AMaxW - 1)));
    ClampedY := Cardinal(EnsureRange(AY, 0, Max(0, AMaxH - 1)));
    Result := FHiZMipChain[AMip][ClampedY * Cardinal(AMaxW) + ClampedX];
  end;

var
  SrcX, SrcY: Integer;
  D00, D10, D01, D11, D20, D21, D02, D12, MaxD: Single;
begin
  EnsureHiZPipelineCreated;
  EffectiveW := Max(Cardinal(1), AWidth);
  EffectiveH := Max(Cardinal(1), AHeight);
  MipCount := 1;
  SrcW := Max(EffectiveW, EffectiveH);
  while SrcW > 1 do
  begin
    SrcW := SrcW shr 1;
    Inc(MipCount);
  end;

  if (FHiZPyramidTexture = nil) or
     (FHiZWidth <> EffectiveW) or
     (FHiZHeight <> EffectiveH) or
     (FHiZMipLevels <> MipCount) then
  begin
    FreeAndNil(FHiZPyramidTexture);
    FHiZWidth := EffectiveW;
    FHiZHeight := EffectiveH;
    FHiZMipLevels := MipCount;

    TexDesc := TRHITextureDesc.Create2D(EffectiveW, EffectiveH, pfR32_Float,
      [tuSampled, tuStorage, tuTransferSrc, tuTransferDst], MipCount, 1);
    TexDesc.DebugName := 'HiZDepthPyramid';
    FHiZPyramidTexture := FDevice.CreateTexture(TexDesc);

    if (FHiZDescriptorSet <> nil) and (FHiZSampler <> nil) then
    begin
      FHiZDescriptorSet.BindTexture(0, FHiZPyramidTexture, FHiZSampler);
      FHiZDescriptorSet.BindTexture(1, FHiZPyramidTexture, nil);
      FHiZDescriptorSet.Update;
    end;
  end;

  SetLength(FHiZMipWidths, MipCount);
  SetLength(FHiZMipHeights, MipCount);
  SetLength(FHiZMipChain, MipCount);

  FHiZMipWidths[0] := EffectiveW;
  FHiZMipHeights[0] := EffectiveH;
  SetLength(FHiZMipChain[0], PtrUInt(EffectiveW) * PtrUInt(EffectiveH));
  if ALevel0DepthData <> nil then
    Move(ALevel0DepthData^, FHiZMipChain[0][0], PtrUInt(EffectiveW) * PtrUInt(EffectiveH) * SizeOf(Single))
  else
  begin
    for I := 0 to PtrUInt(EffectiveW) * PtrUInt(EffectiveH) - 1 do
      FHiZMipChain[0][I] := 1.0;
  end;

  if (ACmd <> nil) and (FHiZPyramidTexture <> nil) then
    ACmd.TransitionTexture(FHiZPyramidTexture, rsTransferDst);

  if MipCount > 1 then
  begin
    for M := 1 to MipCount - 1 do
    begin
      SrcW := FHiZMipWidths[M - 1];
      SrcH := FHiZMipHeights[M - 1];
      DstW := Max(Cardinal(1), SrcW shr 1);
      DstH := Max(Cardinal(1), SrcH shr 1);
      FHiZMipWidths[M] := DstW;
      FHiZMipHeights[M] := DstH;
      SetLength(FHiZMipChain[M], PtrUInt(DstW) * PtrUInt(DstH));

      for DY := 0 to DstH - 1 do
        for DX := 0 to DstW - 1 do
        begin
          SrcX := Integer(DX * 2);
          SrcY := Integer(DY * 2);
          D00 := FetchSrcDepth(M - 1, SrcX + 0, SrcY + 0, Integer(SrcW), Integer(SrcH));
          D10 := FetchSrcDepth(M - 1, SrcX + 1, SrcY + 0, Integer(SrcW), Integer(SrcH));
          D01 := FetchSrcDepth(M - 1, SrcX + 0, SrcY + 1, Integer(SrcW), Integer(SrcH));
          D11 := FetchSrcDepth(M - 1, SrcX + 1, SrcY + 1, Integer(SrcW), Integer(SrcH));
          MaxD := Max(Max(D00, D10), Max(D01, D11));
          if ((SrcW and 1) <> 0) and (DX + 1 = DstW) then
          begin
            D20 := FetchSrcDepth(M - 1, SrcX + 2, SrcY + 0, Integer(SrcW), Integer(SrcH));
            D21 := FetchSrcDepth(M - 1, SrcX + 2, SrcY + 1, Integer(SrcW), Integer(SrcH));
            MaxD := Max(MaxD, Max(D20, D21));
          end;
          if ((SrcH and 1) <> 0) and (DY + 1 = DstH) then
          begin
            D02 := FetchSrcDepth(M - 1, SrcX + 0, SrcY + 2, Integer(SrcW), Integer(SrcH));
            D12 := FetchSrcDepth(M - 1, SrcX + 1, SrcY + 2, Integer(SrcW), Integer(SrcH));
            MaxD := Max(MaxD, Max(D02, D12));
          end;
          FHiZMipChain[M][DY * DstW + DX] := MaxD;
        end;

      if (ACmd <> nil) and (FHiZDownsamplePipeline <> nil) then
      begin
        PushConsts.DstMipWidth := DstW;
        PushConsts.DstMipHeight := DstH;
        PushConsts.SrcMipWidth := SrcW;
        PushConsts.SrcMipHeight := SrcH;
        ACmd.BindComputePipeline(FHiZDownsamplePipeline);
        ACmd.BindComputeDescriptorSet(0, FHiZDescriptorSet, []);
        ACmd.PushConstants([ssCompute], 0, SizeOf(PushConsts), PushConsts);
        ACmd.Dispatch((DstW + 7) div 8, (DstH + 7) div 8, 1);
        if FHiZPyramidTexture <> nil then
          ACmd.TransitionTexture(FHiZPyramidTexture, rsTransferDst);
        Inc(FHiZDownsampleDispatches);
      end;
    end;
  end;

  if (ACmd <> nil) and (FHiZPyramidTexture <> nil) then
    ACmd.TransitionTexture(FHiZPyramidTexture, rsShaderRead);

  FCullingUniforms.HiZParams.X := EffectiveW;
  FCullingUniforms.HiZParams.Y := EffectiveH;
  FCullingUniforms.HiZParams.Z := MipCount;
  Result := MipCount;
end;

function TCastleVulkanComputeCuller.SampleHiZMipMaxDepth(
  const AMipLevel, AX, AY: Cardinal): Single;
var
  ClampedMip, MipW, MipH, ClampedX, ClampedY: Cardinal;
begin
  if (FHiZMipLevels = 0) or (Length(FHiZMipChain) = 0) then
    Exit(1.0);
  ClampedMip := Min(AMipLevel, FHiZMipLevels - 1);
  MipW := FHiZMipWidths[ClampedMip];
  MipH := FHiZMipHeights[ClampedMip];
  if (MipW = 0) or (MipH = 0) then
    Exit(1.0);
  ClampedX := Min(AX, MipW - 1);
  ClampedY := Min(AY, MipH - 1);
  Result := FHiZMipChain[ClampedMip][ClampedY * MipW + ClampedX];
end;

procedure TCastleVulkanComputeCuller.SetHiZProjection(
  const AViewProjMatrix: TMatrix4; const AEnableHiZCulling: Boolean);
begin
  FHiZViewProjMatrix := AViewProjMatrix;
  FHiZCullingEnabled := AEnableHiZCulling;
  if AEnableHiZCulling then
    FCullingUniforms.HiZParams.W := 1.0
  else
    FCullingUniforms.HiZParams.W := 0.0;
end;

procedure TCastleVulkanComputeCuller.SetFrustum(const AFrustum: TFrustum;
  const ACameraPos: TVector3; const AMaxDistance: Single);
var
  Planes: array[0..5] of TVector4;
  FP: TFrustumPlane;
begin
  for FP := Low(TFrustumPlane) to High(TFrustumPlane) do
    Planes[Ord(FP)] := AFrustum.Planes[FP];
  if AFrustum.FarInfinity then
    Planes[Ord(fpFar)] := Vector4(0, 0, 0, 1.0);
  SetFrustumPlanes(Planes, ACameraPos, AMaxDistance);
end;

procedure TCastleVulkanComputeCuller.SetFrustumPlanes(
  const APlanes: array of TVector4; const ACameraPos: TVector3;
  const AMaxDistance: Single);
var
  I, Count: Integer;
begin
  Count := Min(6, Length(APlanes));
  for I := 0 to Count - 1 do
    FCullingUniforms.FrustumPlanes[I] := APlanes[I];
  for I := Count to 5 do
    FCullingUniforms.FrustumPlanes[I] := Vector4(0, 0, 0, 1.0);

  FCullingUniforms.CameraPosition := Vector4(ACameraPos.X, ACameraPos.Y, ACameraPos.Z, Max(0.0, AMaxDistance));
  FCullingUniforms.EnableFrustumCulling := 1;
  if AMaxDistance > 0.0 then
    FCullingUniforms.EnableDistanceCulling := 1
  else
    FCullingUniforms.EnableDistanceCulling := 0;
end;

procedure TCastleVulkanComputeCuller.UploadInstances(
  const AInstances: array of TCastleGpuCullingInstance);
var
  UploadCount: Cardinal;
  I: Integer;
begin
  EnsureResourcesCreated;
  UploadCount := Min(FMaxInstances, Cardinal(Length(AInstances)));
  FLastUploadedInstanceCount := UploadCount;
  SetLength(FUploadedInstances, UploadCount);
  for I := 0 to Integer(UploadCount) - 1 do
    FUploadedInstances[I] := AInstances[I];

  if (UploadCount > 0) and (FInstanceInputBuffer <> nil) then
    FInstanceInputBuffer.UploadData(FUploadedInstances[0],
      PtrUInt(UploadCount) * SizeOf(TCastleGpuCullingInstance), 0);
end;

function TCastleVulkanComputeCuller.IsInstanceVisibleOnCpu(
  const AInst: TCastleGpuCullingInstance;
  out AWasCulledByHiZ: Boolean): Boolean;
var
  I: Integer;
  Plane, CornerClip: TVector4;
  Center, CamPos, BoxMin, BoxMax: TVector3;
  Radius, SignedDist, DistToCam: Single;
  UMin, UMax, VMin, VMax, ZNear01, InvW, U, V, ZNdc, Z01: Single;
  FootprintTexels, OccluderMaxDepth, D00, D10, D01, D11: Single;
  MipLevel, MipW, MipH, X0, X1, Y0, Y1: Cardinal;
  AllCornersInFront: Boolean;
begin
  Result := True;
  AWasCulledByHiZ := False;
  Center := Vector3(AInst.BoundingSphere.X, AInst.BoundingSphere.Y, AInst.BoundingSphere.Z);
  Radius := Max(0.0, AInst.BoundingSphere.W);

  if FCullingUniforms.EnableFrustumCulling <> 0 then
  begin
    for I := 0 to 5 do
    begin
      Plane := FCullingUniforms.FrustumPlanes[I];
      SignedDist := Plane.X * Center.X + Plane.Y * Center.Y + Plane.Z * Center.Z + Plane.W;
      if SignedDist < -Radius then
        Exit(False);
    end;
  end;

  if (FCullingUniforms.EnableDistanceCulling <> 0) and (FCullingUniforms.CameraPosition.W > 0.0) then
  begin
    CamPos := Vector3(FCullingUniforms.CameraPosition.X,
      FCullingUniforms.CameraPosition.Y, FCullingUniforms.CameraPosition.Z);
    DistToCam := PointsDistance(Center, CamPos) - Radius;
    if DistToCam > FCullingUniforms.CameraPosition.W then
      Exit(False);
  end;

  if FHiZCullingEnabled and (FHiZMipLevels > 0) and (FHiZWidth > 0) and (FHiZHeight > 0) then
  begin
    if (AInst.AABBMax.X > AInst.AABBMin.X) or
       (AInst.AABBMax.Y > AInst.AABBMin.Y) or
       (AInst.AABBMax.Z > AInst.AABBMin.Z) then
    begin
      BoxMin := Vector3(AInst.AABBMin.X, AInst.AABBMin.Y, AInst.AABBMin.Z);
      BoxMax := Vector3(AInst.AABBMax.X, AInst.AABBMax.Y, AInst.AABBMax.Z);
    end else
    begin
      BoxMin := Vector3(Center.X - Radius, Center.Y - Radius, Center.Z - Radius);
      BoxMax := Vector3(Center.X + Radius, Center.Y + Radius, Center.Z + Radius);
    end;

    UMin := 1.0;
    UMax := 0.0;
    VMin := 1.0;
    VMax := 0.0;
    ZNear01 := 1.0;
    AllCornersInFront := True;

    for I := 0 to 7 do
    begin
      CornerClip := FHiZViewProjMatrix * Vector4(
        IfThen((I and 1) <> 0, BoxMax.X, BoxMin.X),
        IfThen((I and 2) <> 0, BoxMax.Y, BoxMin.Y),
        IfThen((I and 4) <> 0, BoxMax.Z, BoxMin.Z),
        1.0);
      if CornerClip.W <= 0.0001 then
      begin
        AllCornersInFront := False;
        Break;
      end;
      InvW := 1.0 / CornerClip.W;
      U := (CornerClip.X * InvW) * 0.5 + 0.5;
      V := (CornerClip.Y * InvW) * 0.5 + 0.5;
      ZNdc := CornerClip.Z * InvW;
      Z01 := EnsureRange(ZNdc * 0.5 + 0.5, 0.0, 1.0);
      UMin := Min(UMin, U);
      UMax := Max(UMax, U);
      VMin := Min(VMin, V);
      VMax := Max(VMax, V);
      ZNear01 := Min(ZNear01, Z01);
    end;

    if AllCornersInFront and (UMax >= 0.0) and (UMin <= 1.0) and (VMax >= 0.0) and (VMin <= 1.0) then
    begin
      UMin := EnsureRange(UMin, 0.0, 1.0);
      UMax := EnsureRange(UMax, 0.0, 1.0);
      VMin := EnsureRange(VMin, 0.0, 1.0);
      VMax := EnsureRange(VMax, 0.0, 1.0);

      FootprintTexels := Max((UMax - UMin) * FHiZWidth, (VMax - VMin) * FHiZHeight);
      if FootprintTexels <= 2.0 then
        MipLevel := 0
      else
        MipLevel := Cardinal(EnsureRange(Ceil(Log2(FootprintTexels * 0.5)), 0, Integer(FHiZMipLevels) - 1));

      MipW := FHiZMipWidths[MipLevel];
      MipH := FHiZMipHeights[MipLevel];
      X0 := Cardinal(EnsureRange(Trunc(UMin * MipW), 0, Integer(MipW) - 1));
      X1 := Cardinal(EnsureRange(Trunc(UMax * MipW), 0, Integer(MipW) - 1));
      Y0 := Cardinal(EnsureRange(Trunc(VMin * MipH), 0, Integer(MipH) - 1));
      Y1 := Cardinal(EnsureRange(Trunc(VMax * MipH), 0, Integer(MipH) - 1));

      D00 := SampleHiZMipMaxDepth(MipLevel, X0, Y0);
      D10 := SampleHiZMipMaxDepth(MipLevel, X1, Y0);
      D01 := SampleHiZMipMaxDepth(MipLevel, X0, Y1);
      D11 := SampleHiZMipMaxDepth(MipLevel, X1, Y1);
      OccluderMaxDepth := Max(Max(D00, D10), Max(D01, D11));

      if ZNear01 > OccluderMaxDepth then
      begin
        AWasCulledByHiZ := True;
        Exit(False);
      end;
    end;
  end;
end;

function TCastleVulkanComputeCuller.DispatchCulling(const ACmd: TRHICommandList;
  const AInstanceCount: Cardinal; const ACompactDraws: Boolean): Cardinal;
var
  EffectiveCount, GroupCountX, VisibleCount, HiZCulledCount, OutSlot, I: Cardinal;
  Inst: TCastleGpuCullingInstance;
  Visible, WasHiZCulled: Boolean;
  CmdEntry: TRHIDrawIndexedIndirectCommand;
  MappedIndirect: PRHIDrawIndexedIndirectCommand;
  MappedVis: PCardinal;
  ExecuteOnRealGpu: Boolean;
begin
  EnsureResourcesCreated;
  EffectiveCount := Min(FMaxInstances, Min(AInstanceCount, FLastUploadedInstanceCount));
  if EffectiveCount = 0 then
  begin
    FLastVisibleInstanceCount := 0;
    FLastCulledInstanceCount := 0;
    FHiZCulledInstanceCount := 0;
    Exit(0);
  end;

  FCullingUniforms.InstanceCount := EffectiveCount;
  if ACompactDraws then
    FCullingUniforms.CompactDrawStream := 1
  else
    FCullingUniforms.CompactDrawStream := 0;

  if FCullingUniformBuffer <> nil then
    FCullingUniformBuffer.UploadData(FCullingUniforms, SizeOf(FCullingUniforms), 0);

  { On real Vulkan GPUs (when CPU-emulated Hi-Z test is not active), zero both output
    buffers on host so GpuCullingCS populates VisibilityOut[0..N] (via OpAtomicIAdd)
    and IndirectOut[0..N-1] exclusively on the GPU. In headless mode (FDevice.Handle = nil)
    or when CPU Hi-Z culling is active, populate mapped buffers deterministically on CPU. }
  ExecuteOnRealGpu := (FDevice <> nil) and (FDevice.Handle <> nil) and
    (ACmd is TVulkanRHICommandList) and (TVulkanRHICommandList(ACmd).Handle <> nil) and
    (FComputePipeline <> nil) and (not FHiZCullingEnabled);

  VisibleCount := 0;
  HiZCulledCount := 0;
  MappedIndirect := nil;
  MappedVis := nil;
  if FIndirectOutputBuffer <> nil then
    MappedIndirect := PRHIDrawIndexedIndirectCommand(FIndirectOutputBuffer.Map);
  if FVisibilityOutputBuffer <> nil then
    MappedVis := PCardinal(FVisibilityOutputBuffer.Map);
  try
    if MappedIndirect <> nil then
      FillChar(MappedIndirect^, PtrUInt(EffectiveCount) * SizeOf(TRHIDrawIndexedIndirectCommand), 0);
    if MappedVis <> nil then
      FillChar(MappedVis^, PtrUInt(EffectiveCount + 1) * SizeOf(Cardinal), 0);

    for I := 0 to EffectiveCount - 1 do
    begin
      Inst := FUploadedInstances[I];
      Visible := IsInstanceVisibleOnCpu(Inst, WasHiZCulled);
      if WasHiZCulled then
        Inc(HiZCulledCount);
      if (not ExecuteOnRealGpu) and (MappedVis <> nil) then
      begin
        if Visible then
          PCardinal(PtrUInt(MappedVis) + PtrUInt(I + 1) * SizeOf(Cardinal))^ := 1
        else
          PCardinal(PtrUInt(MappedVis) + PtrUInt(I + 1) * SizeOf(Cardinal))^ := 0;
      end;

      if ACompactDraws then
      begin
        if Visible then
        begin
          OutSlot := VisibleCount;
          Inc(VisibleCount);
          if (not ExecuteOnRealGpu) and (MappedIndirect <> nil) then
          begin
            CmdEntry.IndexCount := Inst.IndexCount;
            CmdEntry.InstanceCount := Inst.InstanceCount;
            CmdEntry.FirstIndex := Inst.FirstIndex;
            CmdEntry.VertexOffset := Inst.VertexOffset;
            CmdEntry.FirstInstance := Inst.FirstInstance;
            PRHIDrawIndexedIndirectCommand(
              PtrUInt(MappedIndirect) + PtrUInt(OutSlot) * SizeOf(TRHIDrawIndexedIndirectCommand))^ := CmdEntry;
          end;
        end;
      end else
      begin
        if Visible then
          Inc(VisibleCount);
        if (not ExecuteOnRealGpu) and (MappedIndirect <> nil) then
        begin
          CmdEntry.IndexCount := Inst.IndexCount;
          if Visible then
            CmdEntry.InstanceCount := Inst.InstanceCount
          else
            CmdEntry.InstanceCount := 0;
          CmdEntry.FirstIndex := Inst.FirstIndex;
          CmdEntry.VertexOffset := Inst.VertexOffset;
          CmdEntry.FirstInstance := Inst.FirstInstance;
          PRHIDrawIndexedIndirectCommand(
            PtrUInt(MappedIndirect) + PtrUInt(I) * SizeOf(TRHIDrawIndexedIndirectCommand))^ := CmdEntry;
        end;
      end;
    end;

    if (not ExecuteOnRealGpu) and (MappedVis <> nil) then
      MappedVis^ := VisibleCount;

    if (FDevice <> nil) and (FDevice.MemoryAllocator <> nil) then
    begin
      if (FIndirectOutputBuffer is TVulkanRHIBuffer) and
         TVulkanRHIBuffer(FIndirectOutputBuffer).Allocation.IsValid then
        FDevice.MemoryAllocator.FlushAllocation(
          TVulkanRHIBuffer(FIndirectOutputBuffer).Allocation, 0,
          PtrUInt(EffectiveCount) * SizeOf(TRHIDrawIndexedIndirectCommand));
      if (FVisibilityOutputBuffer is TVulkanRHIBuffer) and
         TVulkanRHIBuffer(FVisibilityOutputBuffer).Allocation.IsValid then
        FDevice.MemoryAllocator.FlushAllocation(
          TVulkanRHIBuffer(FVisibilityOutputBuffer).Allocation, 0,
          PtrUInt(EffectiveCount + 1) * SizeOf(Cardinal));
    end;
  finally
    if FVisibilityOutputBuffer <> nil then
      FVisibilityOutputBuffer.Unmap;
    if FIndirectOutputBuffer <> nil then
      FIndirectOutputBuffer.Unmap;
  end;

  FLastVisibleInstanceCount := VisibleCount;
  FLastCulledInstanceCount := EffectiveCount - VisibleCount;
  FHiZCulledInstanceCount := HiZCulledCount;

  GroupCountX := (EffectiveCount + FWorkgroupSizeX - 1) div FWorkgroupSizeX;
  if ACmd <> nil then
  begin
    ACmd.BindComputePipeline(FComputePipeline);
    ACmd.BindComputeDescriptorSet(0, FDescriptorSet, []);
    ACmd.Dispatch(GroupCountX, 1, 1);
    if ACmd is TVulkanRHICommandList then
    begin
      TVulkanRHICommandList(ACmd).TransitionBuffer(FIndirectOutputBuffer, rsUnorderedAccess, rsIndirectRead);
      TVulkanRHICommandList(ACmd).TransitionBuffer(FVisibilityOutputBuffer, rsUnorderedAccess, rsIndirectRead);
    end;
  end;

  Inc(FTotalDispatches);
  Result := GroupCountX;
end;

function TCastleVulkanComputeCuller.RecordIndirectDraw(const ACmd: TRHICommandList;
  const AMaxDrawCount: Cardinal): Cardinal;
var
  MaxDraws: Cardinal;
begin
  EnsureResourcesCreated;
  if AMaxDrawCount > 0 then
    MaxDraws := Min(FMaxInstances, AMaxDrawCount)
  else
    MaxDraws := Min(FMaxInstances, FLastUploadedInstanceCount);

  if (ACmd = nil) or (MaxDraws = 0) or
     (FIndirectOutputBuffer = nil) or (FVisibilityOutputBuffer = nil) then
    Exit(0);

  ACmd.DrawIndexedIndirectCount(
    FIndirectOutputBuffer, 0,
    FVisibilityOutputBuffer, 0,
    MaxDraws, SizeOf(TRHIDrawIndexedIndirectCommand));

  if (FDevice <> nil) and (FDevice.Handle <> nil) and
     (ACmd is TVulkanRHICommandList) and (TVulkanRHICommandList(ACmd).Handle <> nil) and
     (not FHiZCullingEnabled) then
  begin
    Result := Min(MaxDraws, FLastVisibleInstanceCount);
    TVulkanRHICommandList(ACmd).FLastEffectiveIndirectDrawCount := Result;
  end else
  if ACmd is TVulkanRHICommandList then
    Result := TVulkanRHICommandList(ACmd).LastEffectiveIndirectDrawCount
  else
    Result := Min(MaxDraws, FLastVisibleInstanceCount);
end;

function TCastleVulkanComputeCuller.ReadBackVisibleCount: Cardinal;
var
  MappedVis: PCardinal;
begin
  Result := FLastVisibleInstanceCount;
  if FVisibilityOutputBuffer <> nil then
  begin
    if (FDevice <> nil) and (FDevice.Handle <> nil) then
    begin
      FDevice.WaitIdle;
      if (FDevice.MemoryAllocator <> nil) and (FVisibilityOutputBuffer is TVulkanRHIBuffer) then
        FDevice.MemoryAllocator.InvalidateAllocation(
          TVulkanRHIBuffer(FVisibilityOutputBuffer).Allocation, 0, SizeOf(Cardinal));
    end;
    MappedVis := PCardinal(FVisibilityOutputBuffer.Map);
    try
      if MappedVis <> nil then
        Result := MappedVis^;
    finally
      FVisibilityOutputBuffer.Unmap;
    end;
  end;
end;

function TCastleVulkanComputeCuller.ReadBackVisibilityFlag(const AIndex: Cardinal): Cardinal;
var
  MappedVis: PCardinal;
begin
  Result := 0;
  if (FVisibilityOutputBuffer <> nil) and (AIndex < FMaxInstances) then
  begin
    if (FDevice <> nil) and (FDevice.Handle <> nil) then
    begin
      FDevice.WaitIdle;
      if (FDevice.MemoryAllocator <> nil) and (FVisibilityOutputBuffer is TVulkanRHIBuffer) then
        FDevice.MemoryAllocator.InvalidateAllocation(
          TVulkanRHIBuffer(FVisibilityOutputBuffer).Allocation, 0,
          PtrUInt(AIndex + 2) * SizeOf(Cardinal));
    end;
    MappedVis := PCardinal(FVisibilityOutputBuffer.Map);
    try
      if MappedVis <> nil then
        Result := PCardinal(PtrUInt(MappedVis) + PtrUInt(AIndex + 1) * SizeOf(Cardinal))^;
    finally
      FVisibilityOutputBuffer.Unmap;
    end;
  end;
end;

function TCastleVulkanComputeCuller.ReadBackIndirectCommand(
  const AIndex: Cardinal): TRHIDrawIndexedIndirectCommand;
var
  MappedIndirect: PRHIDrawIndexedIndirectCommand;
begin
  FillChar(Result, SizeOf(Result), 0);
  if (FIndirectOutputBuffer <> nil) and (AIndex < FMaxInstances) then
  begin
    if (FDevice <> nil) and (FDevice.Handle <> nil) then
    begin
      FDevice.WaitIdle;
      if (FDevice.MemoryAllocator <> nil) and (FIndirectOutputBuffer is TVulkanRHIBuffer) then
        FDevice.MemoryAllocator.InvalidateAllocation(
          TVulkanRHIBuffer(FIndirectOutputBuffer).Allocation, 0,
          PtrUInt(AIndex + 1) * SizeOf(TRHIDrawIndexedIndirectCommand));
    end;
    MappedIndirect := PRHIDrawIndexedIndirectCommand(FIndirectOutputBuffer.Map);
    try
      if MappedIndirect <> nil then
        Result := PRHIDrawIndexedIndirectCommand(
          PtrUInt(MappedIndirect) + PtrUInt(AIndex) * SizeOf(TRHIDrawIndexedIndirectCommand))^;
    finally
      FIndirectOutputBuffer.Unmap;
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanIBLGenerator                                                    }
{ ---------------------------------------------------------------------------- }

type
  TCastleIBLBrdfLutPushConstants = packed record
    LutWidth: Cardinal;
    LutHeight: Cardinal;
    SampleCount: Cardinal;
    Reserved: Cardinal;
  end;

  TCastleIBLCubemapPassPushConstants = packed record
    MipSize: Cardinal;
    SampleCount: Cardinal;
    Roughness: Single;
    FaceIndex: Cardinal;
  end;

const
  CubemapFaceDirections: array[0..5] of TVector3 = (
    (X:  1.0; Y:  0.0; Z:  0.0), // +X
    (X: -1.0; Y:  0.0; Z:  0.0), // -X
    (X:  0.0; Y:  1.0; Z:  0.0), // +Y
    (X:  0.0; Y: -1.0; Z:  0.0), // -Y
    (X:  0.0; Y:  0.0; Z:  1.0), // +Z
    (X:  0.0; Y:  0.0; Z: -1.0)  // -Z
  );

constructor TCastleVulkanIBLGenerator.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanIBLGenerator.Destroy;
var
  FaceIdx, I: Integer;
begin
  for FaceIdx := 0 to 5 do
    SetLength(FPrefilteredEnvFaceColors[FaceIdx], 0);
  SetLength(FBrdfLutData, 0);
  for I := 0 to High(FPrefilterDescSets) do
    FreeAndNil(FPrefilterDescSets[I]);
  SetLength(FPrefilterDescSets, 0);
  for I := 0 to High(FIrradianceDescSets) do
    FreeAndNil(FIrradianceDescSets[I]);
  SetLength(FIrradianceDescSets, 0);
  FBrdfLutComputePipeline := nil; { owned by FDevice.FComputePipelineMap }
  FPrefilterComputePipeline := nil;
  FIrradianceComputePipeline := nil;
  FreeAndNil(FPrefilterComputeShader);
  FreeAndNil(FIrradianceComputeShader);
  FreeAndNil(FEnvConvolveLayout);
  FreeAndNil(FEnvConvolveSampler);
  FreeAndNil(FBrdfLutComputeShader);
  FreeAndNil(FBrdfLutDescriptorSet);
  FreeAndNil(FBrdfLutDescriptorLayout);
  FreeAndNil(FBrdfLutSampler);
  FreeAndNil(FBrdfLutTexture);
  FreeAndNil(FInternalSourceCubemap);
  FreeAndNil(FIrradianceEnvCubemap);
  FreeAndNil(FPrefilteredEnvCubemap);
  inherited;
end;

class function TCastleVulkanIBLGenerator.RadicalInverseVdC(ABits: Cardinal): Single;
begin
  ABits := (ABits shl 16) or (ABits shr 16);
  ABits := ((ABits and $55555555) shl 1) or ((ABits and $AAAAAAAA) shr 1);
  ABits := ((ABits and $33333333) shl 2) or ((ABits and $CCCCCCCC) shr 2);
  ABits := ((ABits and $0F0F0F0F) shl 4) or ((ABits and $F0F0F0F0) shr 4);
  ABits := ((ABits and $00FF00FF) shl 8) or ((ABits and $FF00FF00) shr 8);
  Result := Single(ABits) * 2.3283064365386963e-10; // / 0x100000000
end;

class function TCastleVulkanIBLGenerator.IntegrateBRDFPoint(
  const ANdotV, ARoughness: Single;
  const ASampleCount: Cardinal): TVector2;
var
  ClampedNdotV, ClampedRoughness, Alpha, Alpha2, K: Single;
  Vx, Vz, XiX, XiY, Phi, CosTheta, SinTheta, Hx, Hz: Single;
  VdotH, Lz, NdotL, NdotH, Gv, Gl, G, GVis, OneMinusVdotH, Fc, A, B: Single;
  EffectiveSamples, I: Cardinal;
begin
  ClampedNdotV := EnsureRange(ANdotV, 1e-4, 1.0);
  ClampedRoughness := EnsureRange(ARoughness, 0.04, 1.0);
  EffectiveSamples := Max(Cardinal(8), ASampleCount);

  Alpha := ClampedRoughness * ClampedRoughness;
  Alpha2 := Alpha * Alpha;
  K := (ClampedRoughness * ClampedRoughness) * 0.5;

  Vx := Sqrt(Max(1.0 - ClampedNdotV * ClampedNdotV, 0.0));
  Vz := ClampedNdotV;
  A := 0.0;
  B := 0.0;

  for I := 0 to EffectiveSamples - 1 do
  begin
    XiX := Single(I) / Single(EffectiveSamples);
    XiY := RadicalInverseVdC(I);

    Phi := 2.0 * Pi * XiX;
    CosTheta := Sqrt((1.0 - XiY) / Max(1.0 + (Alpha2 - 1.0) * XiY, 1e-6));
    SinTheta := Sqrt(Max(1.0 - CosTheta * CosTheta, 0.0));

    Hx := Cos(Phi) * SinTheta;
    Hz := CosTheta;

    VdotH := Max(Vx * Hx + Vz * Hz, 0.0);
    Lz := 2.0 * VdotH * Hz - Vz;
    NdotL := Max(Lz, 0.0);
    NdotH := Max(Hz, 0.0);

    if NdotL > 0.0 then
    begin
      Gv := ClampedNdotV / Max(ClampedNdotV * (1.0 - K) + K, 1e-5);
      Gl := NdotL / Max(NdotL * (1.0 - K) + K, 1e-5);
      G := Gv * Gl;
      GVis := (G * VdotH) / Max(NdotH * ClampedNdotV, 1e-5);
      OneMinusVdotH := EnsureRange(1.0 - VdotH, 0.0, 1.0);
      Fc := OneMinusVdotH * OneMinusVdotH * OneMinusVdotH * OneMinusVdotH * OneMinusVdotH;
      A := A + (1.0 - Fc) * GVis;
      B := B + Fc * GVis;
    end;
  end;

  Result := Vector2(
    EnsureRange(A / Single(EffectiveSamples), 0.0, 1.0),
    EnsureRange(B / Single(EffectiveSamples), 0.0, 1.0)
  );
end;

procedure TCastleVulkanIBLGenerator.EnsureBrdfLutPipelineCreated;
var
  ShaderGen: TCastleShaderGeneratorRHI;
  Bindings: array[0..0] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
  SamplerDesc: TRHISamplerDesc;
begin
  if (FDevice = nil) or (FBrdfLutComputePipeline <> nil) then
    Exit;

  FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
  SamplerDesc.MinFilter := sfLinear;
  SamplerDesc.MagFilter := sfLinear;
  SamplerDesc.MipFilter := sfLinear;
  SamplerDesc.AddressModeU := amClampToEdge;
  SamplerDesc.AddressModeV := amClampToEdge;
  SamplerDesc.AddressModeW := amClampToEdge;
  SamplerDesc.MaxAnisotropy := 1.0;
  SamplerDesc.MaxLod := 1000.0;
  FBrdfLutSampler := FDevice.CreateSampler(SamplerDesc);

  FillChar(Bindings, SizeOf(Bindings), 0);
  Bindings[0].Binding := 0;
  Bindings[0].DescriptorType := dtStorageImage;
  Bindings[0].Count := 1;
  Bindings[0].StageFlags := [ssCompute];
  FBrdfLutDescriptorLayout := FDevice.CreateDescriptorSetLayout(Bindings);
  FBrdfLutDescriptorSet := FDevice.CreateDescriptorSet(FBrdfLutDescriptorLayout);

  ShaderGen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FBrdfLutComputeShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute,
      ShaderGen.GenerateIBLBrdfLutComputeShader(8, 8),
      'IBLBrdfLutComputeCS');
  finally
    FreeAndNil(ShaderGen);
  end;

  CompDesc := Default(TRHIComputePipelineDesc);
  CompDesc.ComputeShader := FBrdfLutComputeShader;
  SetLength(CompDesc.DescriptorSetLayouts, 1);
  CompDesc.DescriptorSetLayouts[0] := FBrdfLutDescriptorLayout;
  CompDesc.PushConstantSize := SizeOf(TCastleIBLBrdfLutPushConstants);
  CompDesc.PushConstantStages := [ssCompute];
  CompDesc.DebugName := 'IBLBrdfLutComputePSO';
  FBrdfLutComputePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
end;

procedure TCastleVulkanIBLGenerator.EnsureEnvConvolvePipelinesCreated;
const
  PrefilterComputeGLSL =
    '/* IBLPrefilterEnvCompute */' + LineEnding +
    '#version 450' + LineEnding +
    'layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;' + LineEnding +
    'layout(set = 0, binding = 0) uniform samplerCube u_SrcEnvCubemap;' + LineEnding +
    'layout(set = 0, binding = 1, rgba8) uniform writeonly image2D u_DstCubemapFace;' + LineEnding +
    'layout(push_constant) uniform CubemapConvolvePC {' + LineEnding +
    '  uint MipSize;' + LineEnding +
    '  uint SampleCount;' + LineEnding +
    '  float Roughness;' + LineEnding +
    '  uint FaceIndex;' + LineEnding +
    '} pc;' + LineEnding +
    'float RadicalInverse_VdC(uint bits) {' + LineEnding +
    '  bits = (bits << 16u) | (bits >> 16u);' + LineEnding +
    '  bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);' + LineEnding +
    '  bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);' + LineEnding +
    '  bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);' + LineEnding +
    '  bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);' + LineEnding +
    '  return float(bits) * 2.3283064365386963e-10;' + LineEnding +
    '}' + LineEnding +
    'vec3 CubemapFaceDir(uint faceIdx, float u, float v) {' + LineEnding +
    '  if (faceIdx == 0u) return normalize(vec3( 1.0, -v, -u));' + LineEnding +
    '  if (faceIdx == 1u) return normalize(vec3(-1.0, -v,  u));' + LineEnding +
    '  if (faceIdx == 2u) return normalize(vec3( u,  1.0,  v));' + LineEnding +
    '  if (faceIdx == 3u) return normalize(vec3( u, -1.0, -v));' + LineEnding +
    '  if (faceIdx == 4u) return normalize(vec3( u, -v,  1.0));' + LineEnding +
    '  return normalize(vec3(-u, -v, -1.0));' + LineEnding +
    '}' + LineEnding +
    'void main() {' + LineEnding +
    '  uvec2 gid = gl_GlobalInvocationID.xy;' + LineEnding +
    '  if (gid.x >= pc.MipSize || gid.y >= pc.MipSize) return;' + LineEnding +
    '  float u = ((float(gid.x) + 0.5) / float(pc.MipSize)) * 2.0 - 1.0;' + LineEnding +
    '  float v = ((float(gid.y) + 0.5) / float(pc.MipSize)) * 2.0 - 1.0;' + LineEnding +
    '  vec3 N = CubemapFaceDir(pc.FaceIndex, u, v);' + LineEnding +
    '  vec3 V = N;' + LineEnding +
    '  vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);' + LineEnding +
    '  vec3 T = normalize(cross(up, N));' + LineEnding +
    '  vec3 B = cross(N, T);' + LineEnding +
    '  uint samples = max(pc.SampleCount, 8u);' + LineEnding +
    '  float a = clamp(pc.Roughness, 0.0, 1.0);' + LineEnding +
    '  float a2 = a * a * a * a;' + LineEnding +
    '  vec3 prefiltered = vec3(0.0);' + LineEnding +
    '  float totalWeight = 0.0;' + LineEnding +
    '  for (uint i = 0u; i < samples; ++i) {' + LineEnding +
    '    float xiX = float(i) / float(samples);' + LineEnding +
    '    float xiY = RadicalInverse_VdC(i);' + LineEnding +
    '    float phi = 6.28318530718 * xiX;' + LineEnding +
    '    float cosTheta = sqrt((1.0 - xiY) / max(1.0 + (a2 - 1.0) * xiY, 1e-6));' + LineEnding +
    '    float sinTheta = sqrt(max(1.0 - cosTheta * cosTheta, 0.0));' + LineEnding +
    '    vec3 H = normalize(T * (cos(phi) * sinTheta) + B * (sin(phi) * sinTheta) + N * cosTheta);' + LineEnding +
    '    vec3 L = normalize(2.0 * dot(V, H) * H - V);' + LineEnding +
    '    float NdotL = max(dot(N, L), 0.0);' + LineEnding +
    '    if (NdotL > 0.0) {' + LineEnding +
    '      prefiltered += textureLod(u_SrcEnvCubemap, L, 0.0).rgb * NdotL;' + LineEnding +
    '      totalWeight += NdotL;' + LineEnding +
    '    }' + LineEnding +
    '  }' + LineEnding +
    '  prefiltered = prefiltered / max(totalWeight, 1e-5);' + LineEnding +
    '  imageStore(u_DstCubemapFace, ivec2(gid), vec4(clamp(prefiltered, 0.0, 1.0), 1.0));' + LineEnding +
    '}';
  IrradianceComputeGLSL =
    '/* IBLIrradianceEnvCompute */' + LineEnding +
    '#version 450' + LineEnding +
    'layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;' + LineEnding +
    'layout(set = 0, binding = 0) uniform samplerCube u_SrcEnvCubemap;' + LineEnding +
    'layout(set = 0, binding = 1, rgba8) uniform writeonly image2D u_DstCubemapFace;' + LineEnding +
    'layout(push_constant) uniform CubemapConvolvePC {' + LineEnding +
    '  uint MipSize;' + LineEnding +
    '  uint SampleCount;' + LineEnding +
    '  float Roughness;' + LineEnding +
    '  uint FaceIndex;' + LineEnding +
    '} pc;' + LineEnding +
    'float RadicalInverse_VdC(uint bits) {' + LineEnding +
    '  bits = (bits << 16u) | (bits >> 16u);' + LineEnding +
    '  bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);' + LineEnding +
    '  bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);' + LineEnding +
    '  bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);' + LineEnding +
    '  bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);' + LineEnding +
    '  return float(bits) * 2.3283064365386963e-10;' + LineEnding +
    '}' + LineEnding +
    'vec3 CubemapFaceDir(uint faceIdx, float u, float v) {' + LineEnding +
    '  if (faceIdx == 0u) return normalize(vec3( 1.0, -v, -u));' + LineEnding +
    '  if (faceIdx == 1u) return normalize(vec3(-1.0, -v,  u));' + LineEnding +
    '  if (faceIdx == 2u) return normalize(vec3( u,  1.0,  v));' + LineEnding +
    '  if (faceIdx == 3u) return normalize(vec3( u, -1.0, -v));' + LineEnding +
    '  if (faceIdx == 4u) return normalize(vec3( u, -v,  1.0));' + LineEnding +
    '  return normalize(vec3(-u, -v, -1.0));' + LineEnding +
    '}' + LineEnding +
    'void main() {' + LineEnding +
    '  uvec2 gid = gl_GlobalInvocationID.xy;' + LineEnding +
    '  if (gid.x >= pc.MipSize || gid.y >= pc.MipSize) return;' + LineEnding +
    '  float u = ((float(gid.x) + 0.5) / float(pc.MipSize)) * 2.0 - 1.0;' + LineEnding +
    '  float v = ((float(gid.y) + 0.5) / float(pc.MipSize)) * 2.0 - 1.0;' + LineEnding +
    '  vec3 N = CubemapFaceDir(pc.FaceIndex, u, v);' + LineEnding +
    '  vec3 up = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);' + LineEnding +
    '  vec3 T = normalize(cross(up, N));' + LineEnding +
    '  vec3 B = cross(N, T);' + LineEnding +
    '  uint samples = max(pc.SampleCount, 8u);' + LineEnding +
    '  vec3 irradiance = vec3(0.0);' + LineEnding +
    '  for (uint i = 0u; i < samples; ++i) {' + LineEnding +
    '    float xiX = float(i) / float(samples);' + LineEnding +
    '    float xiY = RadicalInverse_VdC(i);' + LineEnding +
    '    float phi = 6.28318530718 * xiX;' + LineEnding +
    '    float sinTheta = sqrt(max(xiY, 0.0));' + LineEnding +
    '    float cosTheta = sqrt(max(1.0 - xiY, 0.0));' + LineEnding +
    '    vec3 L = normalize(T * (cos(phi) * sinTheta) + B * (sin(phi) * sinTheta) + N * cosTheta);' + LineEnding +
    '    irradiance += textureLod(u_SrcEnvCubemap, L, 0.0).rgb;' + LineEnding +
    '  }' + LineEnding +
    '  irradiance = irradiance / float(samples);' + LineEnding +
    '  imageStore(u_DstCubemapFace, ivec2(gid), vec4(clamp(irradiance, 0.0, 1.0), 1.0));' + LineEnding +
    '}';
var
  SamplerDesc: TRHISamplerDesc;
  Bindings: array[0..1] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FPrefilterComputePipeline <> nil) then
    Exit;

  FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
  SamplerDesc.MinFilter := sfLinear;
  SamplerDesc.MagFilter := sfLinear;
  SamplerDesc.MipFilter := sfLinear;
  SamplerDesc.AddressModeU := amClampToEdge;
  SamplerDesc.AddressModeV := amClampToEdge;
  SamplerDesc.AddressModeW := amClampToEdge;
  SamplerDesc.MaxAnisotropy := 1.0;
  SamplerDesc.MaxLod := 1000.0;
  FEnvConvolveSampler := FDevice.CreateSampler(SamplerDesc);

  FillChar(Bindings, SizeOf(Bindings), 0);
  Bindings[0].Binding := 0;
  Bindings[0].DescriptorType := dtCombinedImageSampler;
  Bindings[0].Count := 1;
  Bindings[0].StageFlags := [ssCompute];
  Bindings[1].Binding := 1;
  Bindings[1].DescriptorType := dtStorageImage;
  Bindings[1].Count := 1;
  Bindings[1].StageFlags := [ssCompute];
  FEnvConvolveLayout := FDevice.CreateDescriptorSetLayout(Bindings);

  FPrefilterComputeShader := FDevice.CreateShaderModuleFromGLSL(
    ssCompute, PrefilterComputeGLSL, 'IBLPrefilterEnvComputeCS');
  FIrradianceComputeShader := FDevice.CreateShaderModuleFromGLSL(
    ssCompute, IrradianceComputeGLSL, 'IBLIrradianceEnvComputeCS');

  CompDesc := Default(TRHIComputePipelineDesc);
  CompDesc.ComputeShader := FPrefilterComputeShader;
  SetLength(CompDesc.DescriptorSetLayouts, 1);
  CompDesc.DescriptorSetLayouts[0] := FEnvConvolveLayout;
  CompDesc.PushConstantSize := SizeOf(TCastleIBLCubemapPassPushConstants);
  CompDesc.PushConstantStages := [ssCompute];
  CompDesc.DebugName := 'IBLPrefilterEnvComputePSO';
  FPrefilterComputePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);

  CompDesc.ComputeShader := FIrradianceComputeShader;
  CompDesc.DebugName := 'IBLIrradianceEnvComputePSO';
  FIrradianceComputePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
end;

function TCastleVulkanIBLGenerator.GenerateBRDFIntegrationLUT(
  const ACmd: TRHICommandList;
  const ASize: Cardinal;
  const ASampleCount: Cardinal): TVulkanRHITexture;
var
  EffectiveSize, EffectiveSamples, X, Y, Idx, GroupX, GroupY: Cardinal;
  TexDesc: TRHITextureDesc;
  PC: TCastleIBLBrdfLutPushConstants;
  NdotV, Roughness: Single;
  LutVal: TVector2;
  PixelsRGBA8: array of Byte;
  RecreatedTex: Boolean;
begin
  EnsureBrdfLutPipelineCreated;
  EffectiveSize := Max(Cardinal(4), ASize);
  EffectiveSamples := Max(Cardinal(8), ASampleCount);
  RecreatedTex := False;

  if (FBrdfLutTexture = nil) or (FBrdfLutSize <> EffectiveSize) then
  begin
    FreeAndNil(FBrdfLutTexture);
    FBrdfLutSize := EffectiveSize;
    TexDesc := TRHITextureDesc.Create2D(
      EffectiveSize, EffectiveSize,
      pfRGBA8_UNorm,
      [tuSampled, tuStorage, tuTransferDst, tuTransferSrc],
      1, 1);
    TexDesc.DebugName := 'IBLBrdfIntegrationLUT';
    FBrdfLutTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
    RecreatedTex := True;
  end;
  FBrdfLutSampleCount := EffectiveSamples;

  SetLength(FBrdfLutData, EffectiveSize * EffectiveSize);
  SetLength(PixelsRGBA8, EffectiveSize * EffectiveSize * 4);
  for Y := 0 to EffectiveSize - 1 do
  begin
    Roughness := Max((Single(Y) + 0.5) / Single(EffectiveSize), 0.04);
    for X := 0 to EffectiveSize - 1 do
    begin
      NdotV := (Single(X) + 0.5) / Single(EffectiveSize);
      LutVal := IntegrateBRDFPoint(NdotV, Roughness, EffectiveSamples);
      Idx := Y * EffectiveSize + X;
      FBrdfLutData[Idx] := LutVal;
      PixelsRGBA8[Idx * 4 + 0] := Byte(Round(EnsureRange(LutVal.X, 0.0, 1.0) * 255.0));
      PixelsRGBA8[Idx * 4 + 1] := Byte(Round(EnsureRange(LutVal.Y, 0.0, 1.0) * 255.0));
      PixelsRGBA8[Idx * 4 + 2] := 0;
      PixelsRGBA8[Idx * 4 + 3] := 255;
    end;
  end;

  if (FBrdfLutTexture <> nil) and (Length(PixelsRGBA8) > 0) then
  begin
    SetLength(FBrdfLutTexture.FHostPixels, Length(PixelsRGBA8));
    Move(PixelsRGBA8[0], FBrdfLutTexture.FHostPixels[0], Length(PixelsRGBA8));
    if ((FDevice.Handle = nil) or (ACmd = nil)) and (FDevice.StagingUploader <> nil) then
      FDevice.StagingUploader.EnqueueImageUpload(
        FBrdfLutTexture, @PixelsRGBA8[0], Length(PixelsRGBA8),
        EffectiveSize, EffectiveSize, 0, 0);
  end;

  if RecreatedTex or (FBrdfLutDescriptorSet = nil) then
  begin
    FreeAndNil(FBrdfLutDescriptorSet);
    FBrdfLutDescriptorSet := FDevice.CreateDescriptorSet(FBrdfLutDescriptorLayout);
    FBrdfLutDescriptorSet.BindTexture(0, FBrdfLutTexture, nil);
    FBrdfLutDescriptorSet.Update;
  end;

  if ACmd <> nil then
  begin
    if (FDevice <> nil) and (FDevice.Handle <> nil) and (not ACmd.IsRendering) and
       (FDevice.StagingUploader <> nil) and
       ((FDevice.StagingUploader.PendingBufferCopyCount > 0) or
        (FDevice.StagingUploader.PendingImageCopyCount > 0)) then
      FDevice.FlushStagingUploads(ACmd as TVulkanRHICommandList);
    ACmd.TransitionTexture(FBrdfLutTexture, rsUnorderedAccess);
    ACmd.BindComputePipeline(FBrdfLutComputePipeline);
    ACmd.BindComputeDescriptorSet(0, FBrdfLutDescriptorSet, []);
    PC.LutWidth := EffectiveSize;
    PC.LutHeight := EffectiveSize;
    PC.SampleCount := EffectiveSamples;
    PC.Reserved := 0;
    ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
    GroupX := (EffectiveSize + 7) div 8;
    GroupY := (EffectiveSize + 7) div 8;
    ACmd.Dispatch(GroupX, GroupY, 1);
    ACmd.TransitionTexture(FBrdfLutTexture, rsShaderRead);
  end;

  Inc(FTotalBrdfLutDispatches);
  Result := FBrdfLutTexture;
end;

function TCastleVulkanIBLGenerator.SampleBRDFLUT(const ANdotV, ARoughness: Single): TVector2;
var
  X, Y: Cardinal;
begin
  if (FBrdfLutSize = 0) or (Length(FBrdfLutData) = 0) then
    Exit(IntegrateBRDFPoint(ANdotV, ARoughness, 32));

  X := Cardinal(EnsureRange(Trunc(EnsureRange(ANdotV, 0.0, 0.9999) * FBrdfLutSize), 0, Integer(FBrdfLutSize) - 1));
  Y := Cardinal(EnsureRange(Trunc(EnsureRange(ARoughness, 0.0, 0.9999) * FBrdfLutSize), 0, Integer(FBrdfLutSize) - 1));
  Result := FBrdfLutData[Y * FBrdfLutSize + X];
end;

procedure TCastleVulkanIBLGenerator.ComputeDiffuseIrradianceSH(
  const AFaceColors: array of TVector3;
  out ASH9: TCastleSH9Coefficients);
const
  { Solid-angle weight of each cubemap face (4*Pi / 6) normalized by 1/Pi for Lambertian convolution }
  FaceWeight = 4.0 / 6.0;
  Y00 = 0.28209479177387814; // 0.5 * sqrt(1/pi)
  Y1  = 0.4886025119029199;  // 0.5 * sqrt(3/pi)
  Y20 = 0.31539156525252005; // 0.25 * sqrt(5/pi)
  Y21 = 1.0925484305920792;  // 0.5 * sqrt(15/pi)
  Y22 = 0.5462742152960396;  // 0.25 * sqrt(15/pi)
var
  FaceIdx: Integer;
  FaceColor, Dir: TVector3;
begin
  FillChar(ASH9, SizeOf(ASH9), 0);
  for FaceIdx := 0 to 5 do
  begin
    if FaceIdx <= High(AFaceColors) then
      FaceColor := AFaceColors[FaceIdx]
    else if Length(AFaceColors) > 0 then
      FaceColor := AFaceColors[High(AFaceColors)]
    else
      FaceColor := Vector3(0.0, 0.0, 0.0);

    Dir := CubemapFaceDirections[FaceIdx];
    ASH9[0] := ASH9[0] + FaceColor * (FaceWeight * Y00);
    ASH9[1] := ASH9[1] + FaceColor * (FaceWeight * Y1 * Dir.Y);
    ASH9[2] := ASH9[2] + FaceColor * (FaceWeight * Y1 * Dir.Z);
    ASH9[3] := ASH9[3] + FaceColor * (FaceWeight * Y1 * Dir.X);
    ASH9[4] := ASH9[4] + FaceColor * (FaceWeight * Y21 * Dir.X * Dir.Y);
    ASH9[5] := ASH9[5] + FaceColor * (FaceWeight * Y21 * Dir.Y * Dir.Z);
    ASH9[6] := ASH9[6] + FaceColor * (FaceWeight * Y20 * (3.0 * Dir.Z * Dir.Z - 1.0));
    ASH9[7] := ASH9[7] + FaceColor * (FaceWeight * Y21 * Dir.X * Dir.Z);
    ASH9[8] := ASH9[8] + FaceColor * (FaceWeight * Y22 * (Dir.X * Dir.X - Dir.Y * Dir.Y));
  end;
end;

function TCastleVulkanIBLGenerator.EvaluateIrradianceSH(const AWorldNormal: TVector3): TVector3;
const
  { Ramamoorthi & Hanrahan (2001) Lambertian cosine lobe convolution constants A_l * Y_lm }
  C0  = 0.8862269254527580;  // pi * Y00
  C1  = 1.0233267079464885;  // (2*pi/3) * Y1
  C20 = 0.2477079561003757;  // (pi/4) * Y20
  C21 = 0.8580855308097834;  // (pi/4) * Y21
  C22 = 0.4290427654048917;  // (pi/4) * Y22
var
  N: TVector3;
begin
  if AWorldNormal.LengthSqr > 1e-8 then
    N := AWorldNormal.Normalize
  else
    N := Vector3(0.0, 1.0, 0.0);

  Result :=
    FIrradianceSH9[0] * C0 +
    FIrradianceSH9[1] * (C1 * N.Y) +
    FIrradianceSH9[2] * (C1 * N.Z) +
    FIrradianceSH9[3] * (C1 * N.X) +
    FIrradianceSH9[4] * (C21 * N.X * N.Y) +
    FIrradianceSH9[5] * (C21 * N.Y * N.Z) +
    FIrradianceSH9[6] * (C20 * (3.0 * N.Z * N.Z - 1.0)) +
    FIrradianceSH9[7] * (C21 * N.X * N.Z) +
    FIrradianceSH9[8] * (C22 * (N.X * N.X - N.Y * N.Y));
  Result.X := Max(0.0, Result.X);
  Result.Y := Max(0.0, Result.Y);
  Result.Z := Max(0.0, Result.Z);
end;

function TCastleVulkanIBLGenerator.GenerateEnvironmentIBLFromCubemap(
  const ACmd: TRHICommandList;
  const ASourceEnvCubemap: TRHITexture;
  const APrefilterBaseSize, AIrradianceSize, ASampleCount: Cardinal): TVulkanRHITexture;
var
  EffectiveBase, EffectiveIrrSize, EffectiveSamples, MipCount, MipDim: Cardinal;
  Mip, FaceIdx, SetIdx, GroupCount: Cardinal;
  I: Integer;
  CubeDesc: TRHITextureDesc;
  PC: TCastleIBLCubemapPassPushConstants;
  Roughness: Single;
  SrcVkTex: TVulkanRHITexture;
begin
  if (FDevice = nil) or (ASourceEnvCubemap = nil) then
    Exit(FPrefilteredEnvCubemap);

  EnsureBrdfLutPipelineCreated;
  EnsureEnvConvolvePipelinesCreated;

  EffectiveSamples := Max(Cardinal(8), ASampleCount);
  if FBrdfLutTexture = nil then
    GenerateBRDFIntegrationLUT(ACmd, 32, EffectiveSamples);

  EffectiveBase := Max(Cardinal(4), APrefilterBaseSize);
  MipCount := 1;
  MipDim := EffectiveBase;
  while MipDim > 1 do
  begin
    MipDim := MipDim shr 1;
    Inc(MipCount);
  end;
  EffectiveIrrSize := Max(Cardinal(4), AIrradianceSize);

  if (FPrefilteredEnvCubemap = nil) or
     (FPrefilteredEnvBaseSize <> EffectiveBase) or
     (FPrefilteredEnvMipLevels <> MipCount) then
  begin
    FreeAndNil(FPrefilteredEnvCubemap);
    FPrefilteredEnvBaseSize := EffectiveBase;
    FPrefilteredEnvMipLevels := MipCount;
    CubeDesc := TRHITextureDesc.CreateCube(
      EffectiveBase,
      pfRGBA8_UNorm,
      [tuSampled, tuStorage, tuTransferDst, tuTransferSrc],
      MipCount);
    CubeDesc.DebugName := 'PrefilteredEnvCubemap';
    FPrefilteredEnvCubemap := FDevice.CreateTexture(CubeDesc) as TVulkanRHITexture;
  end;

  if (FIrradianceEnvCubemap = nil) or (FIrradianceEnvSize <> EffectiveIrrSize) then
  begin
    FreeAndNil(FIrradianceEnvCubemap);
    FIrradianceEnvSize := EffectiveIrrSize;
    CubeDesc := TRHITextureDesc.CreateCube(
      EffectiveIrrSize,
      pfRGBA8_UNorm,
      [tuSampled, tuStorage, tuTransferDst, tuTransferSrc],
      1);
    CubeDesc.DebugName := 'IrradianceEnvCubemap';
    FIrradianceEnvCubemap := FDevice.CreateTexture(CubeDesc) as TVulkanRHITexture;
  end;

  for I := 0 to High(FPrefilterDescSets) do
    FreeAndNil(FPrefilterDescSets[I]);
  SetLength(FPrefilterDescSets, MipCount * 6);
  for Mip := 0 to MipCount - 1 do
    for FaceIdx := 0 to 5 do
    begin
      SetIdx := Mip * 6 + FaceIdx;
      FPrefilterDescSets[SetIdx] := FDevice.CreateDescriptorSet(FEnvConvolveLayout);
      FPrefilterDescSets[SetIdx].BindTexture(0, ASourceEnvCubemap, FEnvConvolveSampler);
      FPrefilterDescSets[SetIdx].BindTextureSubresource(1, FPrefilteredEnvCubemap, Mip, FaceIdx, nil);
      FPrefilterDescSets[SetIdx].Update;
    end;

  for I := 0 to High(FIrradianceDescSets) do
    FreeAndNil(FIrradianceDescSets[I]);
  SetLength(FIrradianceDescSets, 6);
  for FaceIdx := 0 to 5 do
  begin
    FIrradianceDescSets[FaceIdx] := FDevice.CreateDescriptorSet(FEnvConvolveLayout);
    FIrradianceDescSets[FaceIdx].BindTexture(0, ASourceEnvCubemap, FEnvConvolveSampler);
    FIrradianceDescSets[FaceIdx].BindTextureSubresource(1, FIrradianceEnvCubemap, 0, FaceIdx, nil);
    FIrradianceDescSets[FaceIdx].Update;
  end;

  if ACmd <> nil then
  begin
    if (FDevice.Handle <> nil) and (not ACmd.IsRendering) and
       (FDevice.StagingUploader <> nil) and
       ((FDevice.StagingUploader.PendingBufferCopyCount > 0) or
        (FDevice.StagingUploader.PendingImageCopyCount > 0)) then
      FDevice.FlushStagingUploads(ACmd as TVulkanRHICommandList);

    SrcVkTex := ASourceEnvCubemap as TVulkanRHITexture;
    if (SrcVkTex.Desc.MipLevels > 1) and
       (SrcVkTex.MaxUploadedMipLevel + 1 < SrcVkTex.Desc.MipLevels) then
      SrcVkTex.GenerateMipmaps;
    if SrcVkTex.CurrentState <> rsShaderRead then
      ACmd.TransitionTexture(ASourceEnvCubemap, rsShaderRead);

    { 1. Specular GGX importance-sampled prefiltered environment mip chain }
    ACmd.TransitionTexture(FPrefilteredEnvCubemap, rsUnorderedAccess);
    ACmd.BindComputePipeline(FPrefilterComputePipeline);
    for Mip := 0 to MipCount - 1 do
    begin
      if MipCount > 1 then
        Roughness := Single(Mip) / Single(MipCount - 1)
      else
        Roughness := 0.0;
      MipDim := Max(Cardinal(1), EffectiveBase shr Mip);
      GroupCount := (MipDim + 7) div 8;
      for FaceIdx := 0 to 5 do
      begin
        SetIdx := Mip * 6 + FaceIdx;
        ACmd.BindComputeDescriptorSet(0, FPrefilterDescSets[SetIdx], []);
        PC.MipSize := MipDim;
        PC.SampleCount := EffectiveSamples;
        PC.Roughness := Roughness;
        PC.FaceIndex := FaceIdx;
        ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
        ACmd.Dispatch(GroupCount, GroupCount, 1);
      end;
      Inc(FTotalEnvPrefilterPasses);
    end;
    ACmd.TransitionTexture(FPrefilteredEnvCubemap, rsShaderRead);

    { 2. Cosine-weighted Lambertian diffuse irradiance cubemap }
    ACmd.TransitionTexture(FIrradianceEnvCubemap, rsUnorderedAccess);
    ACmd.BindComputePipeline(FIrradianceComputePipeline);
    GroupCount := (EffectiveIrrSize + 7) div 8;
    for FaceIdx := 0 to 5 do
    begin
      ACmd.BindComputeDescriptorSet(0, FIrradianceDescSets[FaceIdx], []);
      PC.MipSize := EffectiveIrrSize;
      PC.SampleCount := EffectiveSamples;
      PC.Roughness := 1.0;
      PC.FaceIndex := FaceIdx;
      ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
      ACmd.Dispatch(GroupCount, GroupCount, 1);
      Inc(FTotalIrradianceDispatches);
    end;
    ACmd.TransitionTexture(FIrradianceEnvCubemap, rsShaderRead);
  end else
  begin
    Inc(FTotalEnvPrefilterPasses, MipCount);
    Inc(FTotalIrradianceDispatches, 6);
  end;

  Result := FPrefilteredEnvCubemap;
end;

function TCastleVulkanIBLGenerator.PrefilterEnvironmentCubemap(
  const ACmd: TRHICommandList;
  const AFaceColors: array of TVector3;
  const ABaseSize: Cardinal): TVulkanRHITexture;
var
  EffectiveBase, MipCount, Mip, FaceIdx, OtherFace, MipDim, PixelIdx, TotalPixels: Cardinal;
  BaseFaces: array[0..5] of TVector3;
  AvgEnv, ConvolvedColor: TVector3;
  Roughness, Weight, TotalWeight, CosAngle: Single;
  CubeDesc, SrcCubeDesc: TRHITextureDesc;
  FacePixels: array of Byte;
  SrcFaceImg: TRGBAlphaImage;
  FaceRgba: TVector4Byte;
  PX, PY: Integer;
begin
  EffectiveBase := Max(Cardinal(4), ABaseSize);
  MipCount := 1;
  MipDim := EffectiveBase;
  while MipDim > 1 do
  begin
    MipDim := MipDim shr 1;
    Inc(MipCount);
  end;

  if (FPrefilteredEnvCubemap = nil) or
     (FPrefilteredEnvBaseSize <> EffectiveBase) or
     (FPrefilteredEnvMipLevels <> MipCount) then
  begin
    FreeAndNil(FPrefilteredEnvCubemap);
    FPrefilteredEnvBaseSize := EffectiveBase;
    FPrefilteredEnvMipLevels := MipCount;
    CubeDesc := TRHITextureDesc.CreateCube(
      EffectiveBase,
      pfRGBA8_UNorm,
      [tuSampled, tuStorage, tuTransferDst, tuTransferSrc],
      MipCount);
    CubeDesc.DebugName := 'PrefilteredEnvCubemap';
    FPrefilteredEnvCubemap := FDevice.CreateTexture(CubeDesc) as TVulkanRHITexture;
  end;

  AvgEnv := Vector3(0.0, 0.0, 0.0);
  for FaceIdx := 0 to 5 do
  begin
    if Integer(FaceIdx) <= High(AFaceColors) then
      BaseFaces[FaceIdx] := AFaceColors[FaceIdx]
    else if Length(AFaceColors) > 0 then
      BaseFaces[FaceIdx] := AFaceColors[High(AFaceColors)]
    else
      BaseFaces[FaceIdx] := Vector3(0.2, 0.2, 0.2);
    AvgEnv := AvgEnv + BaseFaces[FaceIdx] * (1.0 / 6.0);
    SetLength(FPrefilteredEnvFaceColors[FaceIdx], MipCount);
  end;

  ComputeDiffuseIrradianceSH(BaseFaces, FIrradianceSH9);

  for Mip := 0 to MipCount - 1 do
  begin
    if MipCount > 1 then
      Roughness := Single(Mip) / Single(MipCount - 1)
    else
      Roughness := 0.0;

    MipDim := Max(Cardinal(1), EffectiveBase shr Mip);
    TotalPixels := MipDim * MipDim;
    SetLength(FacePixels, TotalPixels * 4);

    for FaceIdx := 0 to 5 do
    begin
      if Roughness <= 1e-4 then
        ConvolvedColor := BaseFaces[FaceIdx]
      else
      begin
        ConvolvedColor := Vector3(0.0, 0.0, 0.0);
        TotalWeight := 0.0;
        for OtherFace := 0 to 5 do
        begin
          CosAngle := TVector3.DotProduct(CubemapFaceDirections[FaceIdx], CubemapFaceDirections[OtherFace]);
          { Smooth GGX lobe weighting between sharp reflection at roughness=0 and hemisphere/isotropic at roughness=1 }
          if OtherFace = FaceIdx then
            Weight := 1.0
          else if CosAngle >= 0.0 then
            Weight := Roughness * Roughness * 0.5
          else
            Weight := Roughness * Roughness * Roughness * 0.15;
          ConvolvedColor := ConvolvedColor + BaseFaces[OtherFace] * Weight;
          TotalWeight := TotalWeight + Weight;
        end;
        if TotalWeight > 1e-5 then
          ConvolvedColor := ConvolvedColor * (1.0 / TotalWeight);
        ConvolvedColor := Lerp(Roughness * Roughness, ConvolvedColor, AvgEnv);
      end;

      FPrefilteredEnvFaceColors[FaceIdx][Mip] := ConvolvedColor;
      for PixelIdx := 0 to TotalPixels - 1 do
      begin
        FacePixels[PixelIdx * 4 + 0] := Byte(Round(EnsureRange(ConvolvedColor.X, 0.0, 1.0) * 255.0));
        FacePixels[PixelIdx * 4 + 1] := Byte(Round(EnsureRange(ConvolvedColor.Y, 0.0, 1.0) * 255.0));
        FacePixels[PixelIdx * 4 + 2] := Byte(Round(EnsureRange(ConvolvedColor.Z, 0.0, 1.0) * 255.0));
        FacePixels[PixelIdx * 4 + 3] := 255;
      end;

      if (FPrefilteredEnvCubemap <> nil) and (Length(FacePixels) > 0) then
      begin
        if (Mip = 0) and (FaceIdx = 0) then
        begin
          SetLength(FPrefilteredEnvCubemap.FHostPixels, Length(FacePixels));
          Move(FacePixels[0], FPrefilteredEnvCubemap.FHostPixels[0], Length(FacePixels));
        end;
        if ((FDevice.Handle = nil) or (ACmd = nil)) and (FDevice.StagingUploader <> nil) then
          FDevice.StagingUploader.EnqueueImageUpload(
            FPrefilteredEnvCubemap, @FacePixels[0], Length(FacePixels),
            MipDim, MipDim, Mip, FaceIdx);
      end;
    end;

    if (ACmd <> nil) and ((FDevice = nil) or (FDevice.Handle = nil)) then
    begin
      ACmd.TransitionTexture(FPrefilteredEnvCubemap, rsTransferDst);
      ACmd.TransitionTexture(FPrefilteredEnvCubemap, rsShaderRead);
    end;
    if (FDevice = nil) or (FDevice.Handle = nil) or (ACmd = nil) then
      Inc(FTotalEnvPrefilterPasses);
  end;

  if (FDevice <> nil) and (FDevice.Handle <> nil) and (ACmd <> nil) then
  begin
    if FInternalSourceCubemap = nil then
    begin
      SrcCubeDesc := TRHITextureDesc.CreateCube(4, pfRGBA8_UNorm, [tuSampled, tuTransferDst], 1);
      SrcCubeDesc.DebugName := 'IBLInternalSourceCube';
      FInternalSourceCubemap := FDevice.CreateTexture(SrcCubeDesc) as TVulkanRHITexture;
    end;
    SrcFaceImg := TRGBAlphaImage.Create(4, 4);
    try
      for FaceIdx := 0 to 5 do
      begin
        FaceRgba := Vector4Byte(
          Byte(Round(EnsureRange(BaseFaces[FaceIdx].X, 0.0, 1.0) * 255.0)),
          Byte(Round(EnsureRange(BaseFaces[FaceIdx].Y, 0.0, 1.0) * 255.0)),
          Byte(Round(EnsureRange(BaseFaces[FaceIdx].Z, 0.0, 1.0) * 255.0)),
          255);
        for PY := 0 to 3 do
          for PX := 0 to 3 do
            SrcFaceImg.PixelPtr(PX, PY)^ := FaceRgba;
        FInternalSourceCubemap.UploadImage(SrcFaceImg, 0, FaceIdx);
      end;
    finally
      FreeAndNil(SrcFaceImg);
    end;
    Result := GenerateEnvironmentIBLFromCubemap(ACmd, FInternalSourceCubemap, EffectiveBase, 8, 32);
  end else
    Result := FPrefilteredEnvCubemap;
end;

function TCastleVulkanIBLGenerator.SamplePrefilteredEnvironment(
  const AFaceIndex, AMipLevel: Cardinal): TVector3;
var
  ClampedFace, ClampedMip: Cardinal;
begin
  Result := Vector3(0.0, 0.0, 0.0);
  if FPrefilteredEnvMipLevels = 0 then Exit;
  ClampedFace := Min(Cardinal(5), AFaceIndex);
  ClampedMip := Min(FPrefilteredEnvMipLevels - 1, AMipLevel);
  if ClampedMip < Cardinal(Length(FPrefilteredEnvFaceColors[ClampedFace])) then
    Result := FPrefilteredEnvFaceColors[ClampedFace][ClampedMip];
end;

{$endif read_implementation}
