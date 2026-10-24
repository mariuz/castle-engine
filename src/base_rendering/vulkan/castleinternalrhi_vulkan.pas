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

{ Vulkan 1.3 implementation of CastleInternalRHI.
  Uses VK_KHR_dynamic_rendering (core in 1.3) and negative viewport height
  (VK_KHR_maintenance1) to match Castle Game Engine's OpenGL clip-space conventions. }
unit CastleInternalRHI_Vulkan;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, Generics.Collections, Generics.Defaults,
  CastleVectors, CastleColors, CastleRectangles, CastleImages, CastleLog,
  CastleRenderOptions, CastleFrustum,
  CastleInternalRHI, CastleInternalShaderRHI, CastleInternalVulkan, CastleInternalVulkanWSI,
  CastleInternalShaderCompiler, CastleInternalVulkanMemory;

type
  TVulkanRHIDevice = class;

  { Callback provided by TCastleWindow to create the platform-specific VkSurfaceKHR }
  TVulkanCreateSurfaceEvent = function(const Instance: VkInstance): VkSurfaceKHR of object;

  { -------------------------------------------------------------------------- }
  { Concrete Vulkan Resource Classes                                           }
  { -------------------------------------------------------------------------- }

  TVulkanRHIBuffer = class(TRHIBuffer)
  private
    FHandle: VkBuffer;
    FAllocation: TVulkanMemoryAllocation;
    FDeviceMemory: VkDeviceMemory;
    FMemoryOffset: VkDeviceSize;
    FAllocatedSize: VkDeviceSize;
    FMappedPtr: Pointer;
    function VulkanDevice: TVulkanRHIDevice;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHIBufferDesc;
      const InitialData: Pointer);
    destructor Destroy; override;

    function Map: Pointer; override;
    procedure Unmap; override;
    procedure UploadData(const Data; const Size: PtrUInt; const Offset: PtrUInt = 0); override;

    property Handle: VkBuffer read FHandle;
    property Allocation: TVulkanMemoryAllocation read FAllocation;
    property DeviceMemory: VkDeviceMemory read FDeviceMemory;
    property MemoryOffset: VkDeviceSize read FMemoryOffset;
  end;

  TVulkanRHITexture = class(TRHITexture)
  private
    FImage: VkImage;
    FImageView: VkImageView;
    FAllocation: TVulkanMemoryAllocation;
    FDeviceMemory: VkDeviceMemory;
    FAllocatedSize: VkDeviceSize;
    FOwnsImage: Boolean;
    FAspectMask: VkImageAspectFlags;
    FViewAspectMask: VkImageAspectFlags;
    FHostPixels: array of Byte;
    function VulkanDevice: TVulkanRHIDevice;
  public
    { Standard constructor that allocates a new VkImage and VkImageView }
    constructor Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHITextureDesc); overload;
    { Wrapper constructor for existing VkSwapchainKHR images }
    constructor CreateSwapchainWrapper(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHITextureDesc; const AExistingImage: VkImage;
      const AExistingView: VkImageView); overload;
    destructor Destroy; override;

    procedure UploadImage(const AImage: TEncodedImage;
      const AMipLevel: Cardinal = 0; const AArrayLayer: Cardinal = 0); override;
    procedure SetHostClearColor(const AColor: TCastleColor);
    procedure SetHostClearDepth(const ADepth: Single);

    property Image: VkImage read FImage;
    property ImageView: VkImageView read FImageView;
    property Allocation: TVulkanMemoryAllocation read FAllocation;
    { Full aspect mask used for VkImageMemoryBarrier transitions (DEPTH | STENCIL for combined formats) }
    property AspectMask: VkImageAspectFlags read FAspectMask;
    { Aspect mask used for VkImageView creation (DEPTH-only when sampled in shaders) }
    property ViewAspectMask: VkImageAspectFlags read FViewAspectMask;
  end;

  TVulkanRHISampler = class(TRHISampler)
  private
    FHandle: VkSampler;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHISamplerDesc);
    destructor Destroy; override;
    property Handle: VkSampler read FHandle;
  end;

  TVulkanRHIShaderModule = class(TRHIShaderModule)
  private
    FHandle: VkShaderModule;
    FReflection: TSPIRVReflectionInfo;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const AStage: TRHIShaderStage;
      const ASPIRVBinary: Pointer; const ASizeInBytes: PtrUInt; const ADebugName: String);
    destructor Destroy; override;
    function ValidateDescriptorSetLayout(const ASetIndex: Cardinal;
      const AExpectedBindings: array of TRHIDescriptorBindingDesc;
      out ADiagnosticMessage: String): Boolean;
    property Handle: VkShaderModule read FHandle;
    property Reflection: TSPIRVReflectionInfo read FReflection;
  end;

  TVulkanRHIDescriptorSetLayout = class(TRHIDescriptorSetLayout)
  private
    FHandle: VkDescriptorSetLayout;
    FUsesUpdateAfterBind: Boolean;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const Bindings: array of TRHIDescriptorBindingDesc);
    destructor Destroy; override;
    property Handle: VkDescriptorSetLayout read FHandle;
    property UsesUpdateAfterBind: Boolean read FUsesUpdateAfterBind;
  end;

  TVulkanDescriptorPoolAllocator = class;

  TVulkanRHIDescriptorSet = class(TRHIDescriptorSet)
  private
    FHandle: VkDescriptorSet;
    FOwnerPool: VkDescriptorPool;
    FIsTransient: Boolean;
    FLayout: TVulkanRHIDescriptorSetLayout;
    FPendingWrites: array of VkWriteDescriptorSet;
    FPendingWriteInfoIndices: array of Integer;
    FBufferInfos: array of VkDescriptorBufferInfo;
    FImageInfos: array of VkDescriptorImageInfo;
    FUpdateCount: Cardinal;
    function VulkanDevice: TVulkanRHIDevice;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ALayout: TVulkanRHIDescriptorSetLayout;
      const AIsTransient: Boolean = False);
    destructor Destroy; override;

    procedure BindUniformBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); override;
    procedure BindStorageBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); override;
    procedure BindTexture(const Binding: Cardinal; const Texture: TRHITexture;
      const Sampler: TRHISampler); override;
    procedure BindTextureAtIndex(const Binding, ArrayElement: Cardinal;
      const Texture: TRHITexture; const Sampler: TRHISampler); override;
    procedure Update; override;

    property Handle: VkDescriptorSet read FHandle;
    property OwnerPool: VkDescriptorPool read FOwnerPool;
    property IsTransient: Boolean read FIsTransient;
    property UpdateCount: Cardinal read FUpdateCount;
  end;

  TVulkanRHIPipeline = class(TRHIPipeline)
  private
    FHandle: VkPipeline;
    FPipelineLayout: VkPipelineLayout;
    FRenderPass: VkRenderPass;
    FLinkedFromLibraries: Boolean;
    FVertexInputLibrary: VkPipeline;
    FPreRasterizationLibrary: VkPipeline;
    FFragmentShaderLibrary: VkPipeline;
    FFragmentOutputLibrary: VkPipeline;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHIGraphicsPipelineDesc);
    destructor Destroy; override;
    property Handle: VkPipeline read FHandle;
    property PipelineLayout: VkPipelineLayout read FPipelineLayout;
    property RenderPass: VkRenderPass read FRenderPass;
    property LinkedFromLibraries: Boolean read FLinkedFromLibraries;
    property VertexInputLibrary: VkPipeline read FVertexInputLibrary;
    property PreRasterizationLibrary: VkPipeline read FPreRasterizationLibrary;
    property FragmentShaderLibrary: VkPipeline read FFragmentShaderLibrary;
    property FragmentOutputLibrary: VkPipeline read FFragmentOutputLibrary;
  end;

  TVulkanRHIComputePipeline = class(TRHIComputePipeline)
  private
    FHandle: VkPipeline;
    FPipelineLayout: VkPipelineLayout;
    FOwnsHandle: Boolean;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHIComputePipelineDesc;
      const AOwnsHandle: Boolean = True);
    destructor Destroy; override;
    property Handle: VkPipeline read FHandle;
    property PipelineLayout: VkPipelineLayout read FPipelineLayout;
  end;

  TVulkanRHIQueryPool = class(TRHIQueryPool)
  private
    FHandle: VkQueryPool;
    FSimulatedResults: array of UInt64;
    FQueryWritten: array of Boolean;
    FResetCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHIQueryPoolDesc);
    destructor Destroy; override;

    function GetResults(const FirstQuery, QueryCount: Cardinal;
      out Results: array of UInt64; const WaitForResults: Boolean = False): Boolean; override;
    procedure SetSimulatedResult(const AQueryIndex: Cardinal; const AValue: UInt64);
    function IsQueryWritten(const AQueryIndex: Cardinal): Boolean;

    property Handle: VkQueryPool read FHandle;
    property ResetCount: Cardinal read FResetCount;
  end;

  { -------------------------------------------------------------------------- }
  { Vulkan Command List                                                        }
  { -------------------------------------------------------------------------- }

  TVulkanRHICommandList = class(TRHICommandList)
  private
    FDevice: TVulkanRHIDevice;
    FCommandPool: VkCommandPool;
    FHandle: VkCommandBuffer;
    FCurrentPipeline: TVulkanRHIPipeline;
    FCurrentComputePipeline: TVulkanRHIComputePipeline;
    FInFallbackRenderPass: Boolean;
    FBarrierCount: Cardinal;
    FSync2BarrierCount: Cardinal;
    FComputeDispatchCount: Cardinal;
    FDynamicStateChangeCount: Cardinal;
    FIndirectDrawCallCount: Cardinal;
    FIndirectCountDrawCallCount: Cardinal;
    FLastEffectiveIndirectDrawCount: Cardinal;
    FDynamicCullMode: TRHICullMode;
    FDynamicFrontFace: TRHIFrontFace;
    FDynamicDepthTestEnable: Boolean;
    FDynamicDepthWriteEnable: Boolean;
    FDynamicDepthCompareOp: TRHICompareOp;
    FDynamicPrimitiveTopology: TRHIPrimitiveTopology;
    FDynamicViewportRect: TFloatRectangle;
    FDynamicMinDepth: Single;
    FDynamicMaxDepth: Single;
    FDynamicScissorRect: TRectangle;
    FDynamicDepthBiasConstant: Single;
    FDynamicDepthBiasSlope: Single;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const AQueueFamilyIndex: Cardinal;
      const ALevel: TRHICommandListLevel = cllPrimary);
    destructor Destroy; override;

    procedure BeginRecording; override;
    procedure EndRecording; override;

    procedure TransitionTexture(const Texture: TRHITexture;
      const NewState: TRHIResourceState); override;
    procedure TransitionBuffer(const Buffer: TRHIBuffer;
      const OldState, NewState: TRHIResourceState);
    procedure GenerateMipmaps(const Texture: TRHITexture); override;

    procedure BeginRendering(const Info: TRHIRenderingInfo); override;
    procedure EndRendering; override;

    procedure SetViewport(const ViewportRect: TFloatRectangle;
      const MinDepth: Single = 0.0; const MaxDepth: Single = 1.0); override;
    procedure SetScissor(const ScissorRect: TRectangle); override;
    procedure SetDepthBias(const ConstantFactor, SlopeFactor: Single); override;

    { Extended Dynamic State (VK_EXT_extended_dynamic_state / Vulkan 1.3 Core) }
    procedure SetCullMode(const CullMode: TRHICullMode); override;
    procedure SetFrontFace(const FrontFace: TRHIFrontFace); override;
    procedure SetDepthTestEnable(const Enable: Boolean); override;
    procedure SetDepthWriteEnable(const Enable: Boolean); override;
    procedure SetDepthCompareOp(const CompareOp: TRHICompareOp); override;
    procedure SetPrimitiveTopology(const Topology: TRHIPrimitiveTopology); override;

    procedure BindPipeline(const Pipeline: TRHIPipeline); override;
    procedure BindDescriptorSet(const SetIndex: Cardinal;
      const DescriptorSet: TRHIDescriptorSet;
      const DynamicOffsets: array of Cardinal); override;
    procedure PushConstants(const StageFlags: TRHIShaderStageFlags;
      const Offset, Size: Cardinal; const Data); override;

    { Compute Pipeline & Dispatch (Phase 6.5) }
    procedure BindComputePipeline(const Pipeline: TRHIComputePipeline); override;
    procedure BindComputeDescriptorSet(const SetIndex: Cardinal;
      const DescriptorSet: TRHIDescriptorSet;
      const DynamicOffsets: array of Cardinal); override;
    procedure Dispatch(const GroupCountX, GroupCountY, GroupCountZ: Cardinal); override;
    procedure DispatchIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt = 0); override;

    { Hardware Queries (Timestamps & Occlusion Queries - Phase 6.7) }
    procedure ResetQueryPool(const QueryPool: TRHIQueryPool;
      const FirstQuery, QueryCount: Cardinal); override;
    procedure BeginQuery(const QueryPool: TRHIQueryPool;
      const QueryIndex: Cardinal; const Precise: Boolean = False); override;
    procedure EndQuery(const QueryPool: TRHIQueryPool;
      const QueryIndex: Cardinal); override;
    procedure WriteTimestamp(const QueryPool: TRHIQueryPool;
      const QueryIndex: Cardinal; const Stage: TRHIShaderStage = ssFragment); override;

    procedure BindVertexBuffers(const FirstBinding: Cardinal;
      const Buffers: array of TRHIBuffer;
      const Offsets: array of PtrUInt); override;
    procedure BindIndexBuffer(const Buffer: TRHIBuffer;
      const Offset: PtrUInt; const IndexType: TRHIIndexType); override;

    procedure Draw(const VertexCount, InstanceCount, FirstVertex, FirstInstance: Cardinal); override;
    procedure DrawIndexed(const IndexCount, InstanceCount, FirstIndex: Cardinal;
      const VertexOffset: Integer; const FirstInstance: Cardinal); override;
    procedure DrawIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const DrawCount, Stride: Cardinal); override;
    procedure DrawIndirectCount(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
      const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal); override;
    procedure DrawIndexedIndirectCount(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
      const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal); override;

    procedure ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList); override;

    procedure PushDebugGroup(const LabelName: String; const Color: TCastleColor); override;
    procedure PopDebugGroup; override;
    procedure ClearAttachments(const ClearColorBuf: Boolean; const ClearColor: TCastleColor;
      const ClearDepthBuf: Boolean = False; const ClearDepth: Single = 1.0;
      const ClearStencilBuf: Boolean = False; const ClearStencil: Byte = 0); override;

    property Handle: VkCommandBuffer read FHandle;
    property InFallbackRenderPass: Boolean read FInFallbackRenderPass;
    property BarrierCount: Cardinal read FBarrierCount;
    property Sync2BarrierCount: Cardinal read FSync2BarrierCount;
    property ComputeDispatchCount: Cardinal read FComputeDispatchCount;
    property DynamicStateChangeCount: Cardinal read FDynamicStateChangeCount;
    property IndirectDrawCallCount: Cardinal read FIndirectDrawCallCount;
    property IndirectCountDrawCallCount: Cardinal read FIndirectCountDrawCallCount;
    property LastEffectiveIndirectDrawCount: Cardinal read FLastEffectiveIndirectDrawCount;
    property DynamicCullMode: TRHICullMode read FDynamicCullMode;
    property DynamicFrontFace: TRHIFrontFace read FDynamicFrontFace;
    property DynamicDepthTestEnable: Boolean read FDynamicDepthTestEnable;
    property DynamicDepthWriteEnable: Boolean read FDynamicDepthWriteEnable;
    property DynamicDepthCompareOp: TRHICompareOp read FDynamicDepthCompareOp;
    property DynamicPrimitiveTopology: TRHIPrimitiveTopology read FDynamicPrimitiveTopology;
    property DynamicViewportRect: TFloatRectangle read FDynamicViewportRect;
    property DynamicMinDepth: Single read FDynamicMinDepth;
    property DynamicMaxDepth: Single read FDynamicMaxDepth;
    property DynamicScissorRect: TRectangle read FDynamicScissorRect;
    property DynamicDepthBiasConstant: Single read FDynamicDepthBiasConstant;
    property DynamicDepthBiasSlope: Single read FDynamicDepthBiasSlope;
  end;

  { -------------------------------------------------------------------------- }
  { Growable & Per-Frame Transient Descriptor Pool Allocator                   }
  { -------------------------------------------------------------------------- }

  TVulkanDescriptorPoolPage = record
    Handle: VkDescriptorPool;
    Capacity: Cardinal;
    AllocatedSets: Cardinal;
  end;

  { Manages a growable chain of VkDescriptorPool pages:
    - Automatically allocates a new scaled VkDescriptorPool page when the active
      pool hits VK_ERROR_OUT_OF_POOL_MEMORY, VK_ERROR_FRAGMENTED_POOL, or capacity.
    - Supports O(1) bulk reset via ResetPools (vkResetDescriptorPool) for per-frame
      transient descriptor sets, recycling all full pool pages back into FReadyPools
      so subsequent frames allocate with zero driver pool creation overhead.
    - Supports individual set freeing (VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT)
      for long-lived persistent material descriptor sets. }
  TVulkanDescriptorPoolAllocator = class
  private
    FDevice: VkDevice;
    FAllowFreeIndividualSets: Boolean;
    FAllowUpdateAfterBind: Boolean;
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
      const AAllowUpdateAfterBind: Boolean = False);
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
    FLayout: TVulkanRHIDescriptorSetLayout;
    FDescriptorSet: TVulkanRHIDescriptorSet;
    FMaterialSSBOBuffer: TRHIBuffer;
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

    { Batches all dirty slot bindings into FDescriptorSet via BindTextureAtIndex + Update.
      Returns the number of descriptor writes committed in this flush. }
    function FlushPendingUpdates: Cardinal;

    property Device: TVulkanRHIDevice read FDevice;
    property Capacity: Cardinal read FCapacity;
    property SupportsUpdateAfterBind: Boolean read FSupportsUpdateAfterBind;
    property Layout: TVulkanRHIDescriptorSetLayout read FLayout;
    property DescriptorSet: TVulkanRHIDescriptorSet read FDescriptorSet;
    property MaterialSSBOBuffer: TRHIBuffer read FMaterialSSBOBuffer;
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
    FTotalBufferUploads: Cardinal;
    FTotalImageUploads: Cardinal;
    FTotalBatchedFlushes: Cardinal;
    FTotalStagedBytes: UInt64;
    FQueueOwnershipTransferCount: Cardinal;
    FOverflowChunkCount: Cardinal;

    function EnsureRingBufferForSlot(const AFrameSlot: Cardinal): Boolean;
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

    property RingCapacityPerFrame: VkDeviceSize read FRingCapacityPerFrame write FRingCapacityPerFrame;
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
    FIrradianceSH9: TCastleSH9Coefficients;
    FTotalBrdfLutDispatches: Cardinal;
    FTotalEnvPrefilterPasses: Cardinal;
    procedure EnsureBrdfLutPipelineCreated;
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

    property BrdfLutTexture: TVulkanRHITexture read FBrdfLutTexture;
    property BrdfLutSampler: TRHISampler read FBrdfLutSampler;
    property BrdfLutComputePipeline: TRHIComputePipeline read FBrdfLutComputePipeline;
    property BrdfLutSize: Cardinal read FBrdfLutSize;
    property PrefilteredEnvCubemap: TVulkanRHITexture read FPrefilteredEnvCubemap;
    property PrefilteredEnvMipLevels: Cardinal read FPrefilteredEnvMipLevels;
    property PrefilteredEnvBaseSize: Cardinal read FPrefilteredEnvBaseSize;
    property IrradianceSH9: TCastleSH9Coefficients read FIrradianceSH9;
    property TotalBrdfLutDispatches: Cardinal read FTotalBrdfLutDispatches;
    property TotalEnvPrefilterPasses: Cardinal read FTotalEnvPrefilterPasses;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 14.1: 3D Clustered Forward+ Compute Light Culler (256+ Lights)       }
  { -------------------------------------------------------------------------- }

  TCastleVulkanClusteredLightCuller = class
  private
    FDevice: TVulkanRHIDevice;
    FGridX: Cardinal;
    FGridY: Cardinal;
    FGridZ: Cardinal;
    FWorkgroupSizeX: Cardinal;
    FClusterUniforms: TCastleClusterCullingUniformBlock;
    FLights: array[0..CASTLE_MAX_CLUSTERED_LIGHTS - 1] of TCastleClusteredLight;
    FActiveLightCount: Cardinal;
    FClusterGrid: array of TCastleClusterGridEntry;
    FLightIndexList: array of Cardinal;
    FClusterUniformBuffer: TRHIBuffer;
    FLightStorageBuffer: TRHIBuffer;
    FClusterGridBuffer: TRHIBuffer;
    FLightIndexBuffer: TRHIBuffer;
    FDescriptorLayout: TRHIDescriptorSetLayout;
    FDescriptorSet: TRHIDescriptorSet;
    FComputeShader: TRHIShaderModule;
    FComputePipeline: TRHIComputePipeline;
    FActiveClusterCount: Cardinal;
    FTotalAssignedLightRefs: Cardinal;
    FTotalDispatches: Cardinal;
    procedure EnsureResourcesCreated;
    function GetTotalClusters: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const AGridX: Cardinal = CASTLE_DEFAULT_CLUSTER_X;
      const AGridY: Cardinal = CASTLE_DEFAULT_CLUSTER_Y;
      const AGridZ: Cardinal = CASTLE_DEFAULT_CLUSTER_Z);
    destructor Destroy; override;

    { Configures the 3D cluster grid resolution (default 16 x 8 x 24 = 3,072 clusters). }
    procedure SetGridDimensions(const AGridX, AGridY, AGridZ: Cardinal);

    { Configures the camera projection matrix, viewport dimensions, and near/far planes
      used for exponential Z-slice subdivision and view-space cluster AABB reconstruction. }
    procedure SetCameraProjection(const AProjectionMatrix: TMatrix4;
      const AScreenWidth, AScreenHeight: Cardinal;
      const AZNear, AZFar: Single);

    { Resets the active clustered light list for the current frame. }
    procedure ClearLights;

    { Adds a directional, point, or spot light (up to CASTLE_MAX_CLUSTERED_LIGHTS = 256). }
    function AddDirectionalLight(const AViewDirection, AColor: TVector3;
      const AIntensity: Single = 1.0): Integer;
    function AddPointLight(const AViewPosition: TVector3; const ARange: Single;
      const AColor: TVector3; const AIntensity: Single = 1.0;
      const AShadowTileIndex: Integer = -1;
      const AShadowBias: Single = 0.001): Integer;
    function AddSpotLight(const AViewPosition, AViewDirection: TVector3;
      const ARange, AInnerSpotCos, AOuterSpotCos: Single;
      const AColor: TVector3; const AIntensity: Single = 1.0;
      const AShadowTileIndex: Integer = -1;
      const AShadowBias: Single = 0.001): Integer;

    { Computes the positive view-space depth bounds [ASliceNear, ASliceFar] for exponential Z-slice ASliceZ. }
    procedure ComputeSliceDepthBounds(const ASliceZ: Cardinal;
      out ASliceNear, ASliceFar: Single);

    { Reconstructs the view-space AABB [AAABBMin, AAABBMax] of 3D cluster (ACX, ACY, ACZ). }
    procedure ComputeClusterViewAABB(const ACX, ACY, ACZ: Cardinal;
      out AAABBMin, AAABBMax: TVector3);

    { Maps screen pixel coordinates (AScreenX, AScreenY) and positive view-space depth
      to 3D cluster coordinates (ACX, ACY, ACZ) and returns the flat 1D cluster index. }
    function ComputeClusterCoordFromScreenAndDepth(
      const AScreenX, AScreenY, APositiveViewDepth: Single;
      out ACX, ACY, ACZ: Cardinal): Cardinal;

    { Uploads the active light array and cluster uniforms, evaluates exact view-space
      sphere-vs-AABB cluster culling, and dispatches the GLSL 450 compute shader.
      Returns the number of dispatched compute workgroups. }
    function DispatchLightCulling(const ACmd: TRHICommandList): Cardinal;

    { Reads back the (Offset, Count) light grid entry for cluster (ACX, ACY, ACZ). }
    function GetClusterEntry(const ACX, ACY, ACZ: Cardinal): TCastleClusterGridEntry;

    { Reads back the light index at ALocalSlot (0 .. Entry.Count - 1) for cluster (ACX, ACY, ACZ). }
    function GetClusterLightIndex(const ACX, ACY, ACZ, ALocalSlot: Cardinal): Cardinal;

    property GridX: Cardinal read FGridX;
    property GridY: Cardinal read FGridY;
    property GridZ: Cardinal read FGridZ;
    property TotalClusters: Cardinal read GetTotalClusters;
    property ActiveLightCount: Cardinal read FActiveLightCount;
    property ActiveClusterCount: Cardinal read FActiveClusterCount;
    property TotalAssignedLightRefs: Cardinal read FTotalAssignedLightRefs;
    property TotalDispatches: Cardinal read FTotalDispatches;
    property ClusterUniformBuffer: TRHIBuffer read FClusterUniformBuffer;
    property LightStorageBuffer: TRHIBuffer read FLightStorageBuffer;
    property ClusterGridBuffer: TRHIBuffer read FClusterGridBuffer;
    property LightIndexBuffer: TRHIBuffer read FLightIndexBuffer;
    property ComputePipeline: TRHIComputePipeline read FComputePipeline;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 14.2: Directional Cascaded Shadow Maps (CSM) & Positional Atlas      }
  { -------------------------------------------------------------------------- }

  TCastleVulkanShadowAtlas = class
  private
    FDevice: TVulkanRHIDevice;
    FAtlasSize: Cardinal;
    FCascadeResolution: Cardinal;
    FShadowAtlasTexture: TVulkanRHITexture;
    FShadowAtlasSampler: TRHISampler;
    FCascadeBlock: TCastleDirectionalCascadeShadowBlock;
    FPositionalTiles: array[0..CASTLE_MAX_SHADOW_ATLAS_TILES - 1] of TCastlePositionalShadowTileEntry;
    FPositionalTileRects: array[0..CASTLE_MAX_SHADOW_ATLAS_TILES - 1] of TRectangle;
    FAllocatedTileCount: Cardinal;
    FShelfCursorX: Cardinal;
    FShelfCursorY: Cardinal;
    FShelfRowHeight: Cardinal;
    FCascadeUniformBuffer: TRHIBuffer;
    FPositionalTileBuffer: TRHIBuffer;
    FTotalCascadeUpdates: Cardinal;
    FTotalShadowTilePasses: Cardinal;
    procedure EnsureAtlasResourcesCreated;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const AAtlasSize: Cardinal = 2048;
      const ACascadeResolution: Cardinal = 512);
    destructor Destroy; override;

    { Computes 4 directional shadow cascade split distances using the Practical Split Scheme
      (Nvidia PSSM / Godot 4 CSM, ALambda in [0..1], default 0.75), builds tight orthographic
      light view-projection matrices with optional texel-snapping stabilization to eliminate
      shimmering, and assigns the 4 cascade tiles in the top row of the shadow atlas. }
    procedure ComputeDirectionalCascades(
      const ACameraInverseViewProj: TMatrix4;
      const AWorldLightDirection: TVector3;
      const AZNear, AZFar: Single;
      const ALambda: Single = 0.75;
      const AStabilizeTexels: Boolean = True);

    { Returns the viewport rectangle inside the shadow atlas for directional cascade ACascadeIndex (0..3). }
    function GetCascadeViewportRect(const ACascadeIndex: Cardinal): TRectangle;

    { Resets dynamic positional shadow tile allocations for a new frame while preserving
      the reserved directional cascade region. }
    procedure ResetPositionalTiles;

    { Selects an adaptive shadow tile resolution (ABaseResolution, ABaseResolution/2,
      ABaseResolution/4, min 64) based on distance to camera and light range. }
    class function ChooseTileResolution(const ADistanceToCamera, ALightRange: Single;
      const ABaseResolution: Cardinal = 512): Cardinal; static;

    { Sub-allocates a square depth tile of ADesiredResolution inside the positional region
      of the shadow atlas, stores ALightViewProj + normalized UV scale/offset, and outputs
      ATileIndex, AViewportRect, and AUVScaleOffset. }
    function AllocatePositionalTile(const ADesiredResolution: Cardinal;
      const ALightViewProj: TMatrix4;
      out ATileIndex: Integer;
      out AViewportRect: TRectangle;
      out AUVScaleOffset: TVector4): Boolean;

    { Uploads the directional cascade UBO and positional shadow tile SSBO to the GPU. }
    procedure UploadShadowBuffers;

    { Records a depth-only shadow tile rendering pass into AViewportRect of ShadowAtlasTexture
      with slope-scaled depth bias (SetDepthBias) to prevent shadow acne. }
    procedure RecordShadowTilePass(const ACmd: TRHICommandList;
      const AViewportRect: TRectangle;
      const ADepthBiasConstant: Single = 1.25;
      const ADepthBiasSlope: Single = 1.75);

    property AtlasSize: Cardinal read FAtlasSize;
    property CascadeResolution: Cardinal read FCascadeResolution;
    property ShadowAtlasTexture: TVulkanRHITexture read FShadowAtlasTexture;
    property ShadowAtlasSampler: TRHISampler read FShadowAtlasSampler;
    property CascadeBlock: TCastleDirectionalCascadeShadowBlock read FCascadeBlock;
    property AllocatedTileCount: Cardinal read FAllocatedTileCount;
    property CascadeUniformBuffer: TRHIBuffer read FCascadeUniformBuffer;
    property PositionalTileBuffer: TRHIBuffer read FPositionalTileBuffer;
    property TotalCascadeUpdates: Cardinal read FTotalCascadeUpdates;
    property TotalShadowTilePasses: Cardinal read FTotalShadowTilePasses;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 15.2 & 15.3: HDR Scene Target, Compute Mip-Chain Bloom, Luminance    }
  { Histogram Auto-Exposure & ACES Filmic / AgX Tonemapping Composite          }
  { -------------------------------------------------------------------------- }

  TCastleVulkanHDRPostProcessor = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FBloomMipCount: Cardinal;
    FHDRSceneTexture: TVulkanRHITexture;
    FBloomMipTextures: array[0..CASTLE_BLOOM_MAX_MIP_LEVELS - 1] of TVulkanRHITexture;
    FLinearClampSampler: TRHISampler;
    FHistogramBins: array[0..CASTLE_LUMINANCE_HISTOGRAM_BINS - 1] of Cardinal;
    FHistogramBuffer: TRHIBuffer;
    FExposureStateBuffer: TRHIBuffer;
    FBloomDescriptorLayout: TRHIDescriptorSetLayout;
    FBloomDescriptorSet: TRHIDescriptorSet;
    FHistogramDescriptorLayout: TRHIDescriptorSetLayout;
    FHistogramDescriptorSet: TRHIDescriptorSet;
    FBloomDownsampleShader: TRHIShaderModule;
    FBloomUpsampleShader: TRHIShaderModule;
    FHistogramShader: TRHIShaderModule;
    FCompositeFragShader: TRHIShaderModule;
    FBloomDownsamplePipeline: TRHIComputePipeline;
    FBloomUpsamplePipeline: TRHIComputePipeline;
    FHistogramPipeline: TRHIComputePipeline;
    FBloomThreshold: Single;
    FBloomKnee: Single;
    FBloomIntensity: Single;
    FBloomFilterRadius: Single;
    FExposure: Single;
    FGamma: Single;
    FSaturation: Single;
    FContrast: Single;
    FTonemapOperator: TCastleTonemapOperator;
    FEnableBloom: Boolean;
    FEnableAutoExposure: Boolean;
    FAutoExposureParams: TCastleAutoExposureParams;
    FAdaptedLuminance: Single;
    FAdaptedExposure: Single;
    FTargetLuminance: Single;
    FTotalBloomDownsampleDispatches: Cardinal;
    FTotalBloomUpsampleDispatches: Cardinal;
    FTotalHistogramDispatches: Cardinal;
    FTotalCompositePasses: Cardinal;
    procedure EnsurePipelinesCreated;
    function GetBloomMipTexture(const AMipIndex: Cardinal): TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRGBA16_Float HDR scene color target and the
      6-level pfRGBA16_Float bloom mip pyramid for (AWidth, AHeight). }
    procedure EnsureHDRTargets(const AWidth, AHeight: Cardinal);

    { Dispatches the 13-tap Jiménez Karis downsample chain (Mip 0 .. FBloomMipCount-1)
      followed by the 9-tap 3x3 tent-filter upsample chain (FBloomMipCount-1 .. Mip 0).
      Returns total compute dispatches recorded. }
    function DispatchBloomPyramid(const ACmd: TRHICommandList): Cardinal;

    { Builds the 256-bin log2 luminance histogram from ASceneLinearSamples (and dispatches
      the GPU compute shader onto ACmd), computes the weighted average scene luminance,
      and updates FAdaptedLuminance and FAdaptedExposure using exponential temporal smoothing
      over ADeltaTime seconds. Returns the new AdaptedExposure. }
    function UpdateAutoExposure(const ACmd: TRHICommandList;
      const ASceneLinearSamples: array of TVector3;
      const ADeltaTime: Single): Single;

    { Records the HDR + Bloom + Auto-Exposure + ACES/AgX Tonemapping + sRGB composite pass
      into ADstLDRTarget. }
    procedure ExecuteCompositePass(const ACmd: TRHICommandList;
      const ADstLDRTarget: TRHITexture);

    { Populates a declarative TRHIRenderGraph with the complete 4-stage HDR frame pipeline:
      1. Forward3DHDRPass (writes transient HDRColor + transient HDRDepth)
      2. BloomPyramidComputePass (reads HDRColor, writes transient BloomMip0)
      3. LuminanceHistogramComputePass (reads HDRColor, writes ExposureStateBuffer)
      4. TonemapCompositePass (reads HDRColor + BloomMip0 + ExposureStateBuffer, writes imported ASwapchainColor) }
    procedure BuildDefaultFrameRenderGraph(const AGraph: TRHIRenderGraph;
      const AWidth, AHeight: Cardinal;
      const ASwapchainColor: TRHITexture);

    { Exact reference evaluators matching the GLSL 450 shaders for deterministic verification }
    class function EvaluateKarisWeight(const ALinearRGB: TVector3): Single; static;
    class function EvaluateKarisAverage4(const C0, C1, C2, C3: TVector3): TVector3; static;
    class function EvaluateSoftThreshold(const ALinearRGB: TVector3;
      const AThreshold, AKnee: Single): TVector3; static;
    class function EvaluateTonemapReinhard(const AHDR: TVector3): TVector3; static;
    class function EvaluateTonemapACESFilmic(const AHDR: TVector3): TVector3; static;
    class function EvaluateTonemapAgX(const AHDR: TVector3): TVector3; static;
    class function EvaluateLinearToSRGB(const ALinear: TVector3): TVector3; static;
    function EvaluateCompositeColor(const AHDRSceneColor, ABloomColor: TVector3): TVector3;
    function GetHistogramBinCount(const ABinIndex: Cardinal): Cardinal;

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property BloomMipCount: Cardinal read FBloomMipCount;
    property HDRSceneTexture: TVulkanRHITexture read FHDRSceneTexture;
    property BloomMipTextures[const AMipIndex: Cardinal]: TVulkanRHITexture read GetBloomMipTexture;
    property HistogramBuffer: TRHIBuffer read FHistogramBuffer;
    property ExposureStateBuffer: TRHIBuffer read FExposureStateBuffer;
    property BloomDownsamplePipeline: TRHIComputePipeline read FBloomDownsamplePipeline;
    property BloomUpsamplePipeline: TRHIComputePipeline read FBloomUpsamplePipeline;
    property HistogramPipeline: TRHIComputePipeline read FHistogramPipeline;
    property BloomThreshold: Single read FBloomThreshold write FBloomThreshold;
    property BloomKnee: Single read FBloomKnee write FBloomKnee;
    property BloomIntensity: Single read FBloomIntensity write FBloomIntensity;
    property BloomFilterRadius: Single read FBloomFilterRadius write FBloomFilterRadius;
    property Exposure: Single read FExposure write FExposure;
    property Gamma: Single read FGamma write FGamma;
    property Saturation: Single read FSaturation write FSaturation;
    property Contrast: Single read FContrast write FContrast;
    property TonemapOperator: TCastleTonemapOperator read FTonemapOperator write FTonemapOperator;
    property EnableBloom: Boolean read FEnableBloom write FEnableBloom;
    property EnableAutoExposure: Boolean read FEnableAutoExposure write FEnableAutoExposure;
    property AdaptedLuminance: Single read FAdaptedLuminance;
    property AdaptedExposure: Single read FAdaptedExposure;
    property TargetLuminance: Single read FTargetLuminance;
    property TotalBloomDownsampleDispatches: Cardinal read FTotalBloomDownsampleDispatches;
    property TotalBloomUpsampleDispatches: Cardinal read FTotalBloomUpsampleDispatches;
    property TotalHistogramDispatches: Cardinal read FTotalHistogramDispatches;
    property TotalCompositePasses: Cardinal read FTotalCompositePasses;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 16.1: Compute Ground-Truth Ambient Occlusion (GTAO) & Denoiser       }
  { -------------------------------------------------------------------------- }

  TCastleVulkanGTAO = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FHalfResolution: Boolean;
    FRawGTAOTexture: TVulkanRHITexture;
    FDenoisedGTAOTexture: TVulkanRHITexture;
    FLinearClampSampler: TRHISampler;
    FGTAODescriptorLayout: TRHIDescriptorSetLayout;
    FGTAODescriptorSet: TRHIDescriptorSet;
    FDenoiseDescriptorLayout: TRHIDescriptorSetLayout;
    FDenoiseDescriptorSet: TRHIDescriptorSet;
    FGTAOShader: TRHIShaderModule;
    FDenoiseShader: TRHIShaderModule;
    FGTAOPipeline: TRHIComputePipeline;
    FDenoisePipeline: TRHIComputePipeline;
    FEffectRadius: Single;
    FFalloffRange: Single;
    FPower: Single;
    FZNear: Single;
    FZFar: Single;
    FSliceCount: Cardinal;
    FStepsPerSlice: Cardinal;
    FTotalGTAODispatches: Cardinal;
    FTotalDenoiseDispatches: Cardinal;
    procedure EnsurePipelinesCreated;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the Raw and Denoised pfR16_Float GTAO targets. }
    procedure EnsureGTAOTargets(const AWidth, AHeight: Cardinal;
      const AHalfResolution: Boolean = False);

    { Dispatches the multi-slice GTAO horizon integral compute shader followed by the
      5x5 depth-aware cross-bilateral spatial denoiser. Returns total dispatches (2). }
    function DispatchGTAO(const ACmd: TRHICommandList;
      const ADepthTexture: TRHITexture): Cardinal;

    { Exact reference evaluators matching the GLSL 450 GTAO & bilateral filter shaders }
    class function ReconstructViewPosition(const AUV, AProjScale: TVector2;
      const ALinearZ: Single): TVector3; static;
    class function IntegrateGTAOHorizonSlice(const AH1, AH2, ANormalAngle: Single): Single; static;
    class function ComputeBilateralDepthWeight(const ACenterDepth, ASampleDepth,
      ASigmaDepth: Single): Single; static;
    function EvaluateGTAOFromHorizonCosines(const AMaxCos1, AMaxCos2,
      ANormalAngle: Single): Single;

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property HalfResolution: Boolean read FHalfResolution;
    property RawGTAOTexture: TVulkanRHITexture read FRawGTAOTexture;
    property DenoisedGTAOTexture: TVulkanRHITexture read FDenoisedGTAOTexture;
    property GTAOPipeline: TRHIComputePipeline read FGTAOPipeline;
    property DenoisePipeline: TRHIComputePipeline read FDenoisePipeline;
    property EffectRadius: Single read FEffectRadius write FEffectRadius;
    property FalloffRange: Single read FFalloffRange write FFalloffRange;
    property Power: Single read FPower write FPower;
    property ZNear: Single read FZNear write FZNear;
    property ZFar: Single read FZFar write FZFar;
    property SliceCount: Cardinal read FSliceCount write FSliceCount;
    property StepsPerSlice: Cardinal read FStepsPerSlice write FStepsPerSlice;
    property TotalGTAODispatches: Cardinal read FTotalGTAODispatches;
    property TotalDenoiseDispatches: Cardinal read FTotalDenoiseDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 16.2: Hierarchical-Z Screen-Space Reflections (Hi-Z SSR)             }
  { -------------------------------------------------------------------------- }

  TCastleVulkanSSR = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FSSRReflectionTexture: TVulkanRHITexture;
    FLinearClampSampler: TRHISampler;
    FSSRDescriptorLayout: TRHIDescriptorSetLayout;
    FSSRDescriptorSet: TRHIDescriptorSet;
    FSSRShader: TRHIShaderModule;
    FSSRPipeline: TRHIComputePipeline;
    FZNear: Single;
    FZFar: Single;
    FMaxDistance: Single;
    FThickness: Single;
    FMaxRoughness: Single;
    FEdgeFadeWidth: Single;
    FIntensity: Single;
    FMaxSteps: Cardinal;
    FHiZMipCount: Cardinal;
    FTotalSSRDispatches: Cardinal;
    procedure EnsurePipelineCreated;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRGBA16_Float SSR reflection output texture. }
    procedure EnsureSSRTarget(const AWidth, AHeight: Cardinal);

    { Dispatches the Hi-Z Screen-Space Reflections compute shader. }
    function DispatchSSR(const ACmd: TRHICommandList;
      const AHDRSceneColor, AHiZPyramid: TRHITexture): Cardinal;

    { Exact reference evaluators matching the GLSL 450 Hi-Z SSR compute shader }
    class function EvaluateScreenEdgeFade(const AHitUV: TVector2;
      const AFadeWidth: Single): Single; static;
    class function EvaluateSSRReflectionWeight(const ARoughness, AMaxRoughness,
      ACosTheta: Single): Single; static;
    function RaymarchHiZ1D(const AHiZMip0Depths: array of Single;
      const AStartCell: Integer; const AStartDepth, ARayStepZ: Single;
      out AHitCell: Integer; out AHitSteps: Cardinal): Boolean;

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property SSRReflectionTexture: TVulkanRHITexture read FSSRReflectionTexture;
    property SSRPipeline: TRHIComputePipeline read FSSRPipeline;
    property ZNear: Single read FZNear write FZNear;
    property ZFar: Single read FZFar write FZFar;
    property MaxDistance: Single read FMaxDistance write FMaxDistance;
    property Thickness: Single read FThickness write FThickness;
    property MaxRoughness: Single read FMaxRoughness write FMaxRoughness;
    property EdgeFadeWidth: Single read FEdgeFadeWidth write FEdgeFadeWidth;
    property Intensity: Single read FIntensity write FIntensity;
    property MaxSteps: Cardinal read FMaxSteps write FMaxSteps;
    property HiZMipCount: Cardinal read FHiZMipCount write FHiZMipCount;
    property TotalSSRDispatches: Cardinal read FTotalSSRDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 16.3: 3D Froxel Volumetric Fog & Exponential Height Fog              }
  { -------------------------------------------------------------------------- }

  TCastleVulkanVolumetricFog = class
  private
    FDevice: TVulkanRHIDevice;
    FGridX: Cardinal;
    FGridY: Cardinal;
    FGridZ: Cardinal;
    FFroxelScatteringVolume: TVulkanRHITexture;
    FIntegratedFroxelLUT: TVulkanRHITexture;
    FLinearClampSampler: TRHISampler;
    FInjectDescriptorLayout: TRHIDescriptorSetLayout;
    FInjectDescriptorSet: TRHIDescriptorSet;
    FRaymarchDescriptorLayout: TRHIDescriptorSetLayout;
    FRaymarchDescriptorSet: TRHIDescriptorSet;
    FInjectShader: TRHIShaderModule;
    FRaymarchShader: TRHIShaderModule;
    FInjectPipeline: TRHIComputePipeline;
    FRaymarchPipeline: TRHIComputePipeline;
    FFogAlbedo: TVector3;
    FBaseDensity: Single;
    FSunDirection: TVector3;
    FAnisotropyG: Single;
    FSunColor: TVector3;
    FSunIntensity: Single;
    FHeightFalloff: Single;
    FBaseHeight: Single;
    FZNear: Single;
    FZFar: Single;
    FTotalInjectDispatches: Cardinal;
    FTotalRaymarchDispatches: Cardinal;
    procedure EnsurePipelinesCreated;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the 3D Froxel Scattering Volume and Integrated Froxel LUT (td3D, pfRGBA16_Float). }
    procedure EnsureFroxelVolumes(
      const AGridX: Cardinal = CASTLE_FROXEL_GRID_X;
      const AGridY: Cardinal = CASTLE_FROXEL_GRID_Y;
      const AGridZ: Cardinal = CASTLE_FROXEL_GRID_Z);

    { Dispatches the 3D Froxel Density/Scattering Injection pass followed by the
      front-to-back Beer-Lambert Raymarching Integration pass. Returns total dispatches (2). }
    function DispatchVolumetricFog(const ACmd: TRHICommandList): Cardinal;

    { Exact reference evaluators matching the GLSL 450 Volumetric Fog compute shaders }
    class function EvaluateHenyeyGreensteinPhase(const ACosTheta,
      AAnisotropyG: Single): Single; static;
    class function EvaluateHeightFogDensity(const AWorldY, ABaseDensity,
      ABaseHeight, AHeightFalloff: Single): Single; static;
    class procedure IntegrateFroxelSliceStep(const ASliceScattering: TVector3;
      const ASliceExtinction, AStepLength: Single;
      var AAccumLight: TVector3; var AAccumTransmittance: Single); static;

    property GridX: Cardinal read FGridX;
    property GridY: Cardinal read FGridY;
    property GridZ: Cardinal read FGridZ;
    property FroxelScatteringVolume: TVulkanRHITexture read FFroxelScatteringVolume;
    property IntegratedFroxelLUT: TVulkanRHITexture read FIntegratedFroxelLUT;
    property InjectPipeline: TRHIComputePipeline read FInjectPipeline;
    property RaymarchPipeline: TRHIComputePipeline read FRaymarchPipeline;
    property FogAlbedo: TVector3 read FFogAlbedo write FFogAlbedo;
    property BaseDensity: Single read FBaseDensity write FBaseDensity;
    property SunDirection: TVector3 read FSunDirection write FSunDirection;
    property AnisotropyG: Single read FAnisotropyG write FAnisotropyG;
    property SunColor: TVector3 read FSunColor write FSunColor;
    property SunIntensity: Single read FSunIntensity write FSunIntensity;
    property HeightFalloff: Single read FHeightFalloff write FHeightFalloff;
    property BaseHeight: Single read FBaseHeight write FBaseHeight;
    property ZNear: Single read FZNear write FZNear;
    property ZFar: Single read FZFar write FZFar;
    property TotalInjectDispatches: Cardinal read FTotalInjectDispatches;
    property TotalRaymarchDispatches: Cardinal read FTotalRaymarchDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 17.1: Sub-Pixel Halton Jitter, Velocity & Temporal Anti-Aliasing     }
  { -------------------------------------------------------------------------- }

  { Manages 8/16-sample Halton (2, 3) sub-pixel projection jitter, 2D screen-space
    motion vectors (pfRG16_Float), ping-pong temporal HDR history targets (pfRGBA16_Float),
    YCoCg 3x3 neighborhood variance clipping, and 5-tap Catmull-Rom bicubic TAA resolve. }
  TCastleVulkanTAA = class
  private
    FDevice: TVulkanRHIDevice;
    FLinearClampSampler: TRHISampler;
    FVelocityTexture: TVulkanRHITexture;
    FHistoryTextures: array[0..1] of TVulkanRHITexture;
    FTAADescriptorLayout: TRHIDescriptorSetLayout;
    FTAADescriptorSet: TRHIDescriptorSet;
    FTAAShader: TRHIShaderModule;
    FTAAPipeline: TRHIComputePipeline;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FCurrentHistoryIndex: Integer;
    FSampleCount: Cardinal;
    FBlendFactor: Single;
    FVarianceClipGamma: Single;
    FVelocityWeightScale: Single;
    FTotalTAADispatches: Cardinal;
    procedure EnsurePipelineCreated;
    function GetResolvedHistoryTexture: TVulkanRHITexture;
    function GetPreviousHistoryTexture: TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRG16_Float velocity texture and ping-pong pfRGBA16_Float history targets. }
    procedure EnsureTAATargets(const AWidth, AHeight: Cardinal);

    { Dispatches the compute TAA resolve pass, reading ACurrentHDRTexture, PreviousHistoryTexture,
      and VelocityTexture, and writing to ResolvedHistoryTexture. Returns 1 when dispatched. }
    function DispatchTAAResolve(const ACmd: TRHICommandList;
      const ACurrentHDRTexture: TRHITexture;
      const AFrameIndex: Cardinal = 0): Cardinal;

    { Evaluates the 1D radical inverse Halton sequence in base ABase for 1-based sample AIndex. }
    class function EvaluateHaltonSequence(const AIndex, ABase: Cardinal): Single; static;

    { Computes the sub-pixel Halton (2, 3) camera jitter offset in NDC [-1/W .. +1/W] for AFrameIndex. }
    class function ComputeHaltonJitterOffset(const AFrameIndex, ASampleCount,
      AWidth, AHeight: Cardinal): TVector2; static;

    { Converts linear RGB to YCoCg luminance-chrominance space. }
    class function RGBToYCoCg(const ARGB: TVector3): TVector3; static;

    { Converts YCoCg luminance-chrominance back to linear RGB. }
    class function YCoCgToRGB(const AYCoCg: TVector3): TVector3; static;

    { Clips history YCoCg color against the 3x3 neighborhood AABB [Mean - Gamma*StdDev, Mean + Gamma*StdDev]. }
    class function ClipHistoryYCoCg(const AHistoryYCoCg, AMeanYCoCg, AStdDevYCoCg: TVector3;
      const AGamma: Single = 1.25): TVector3; static;

    property VelocityTexture: TVulkanRHITexture read FVelocityTexture;
    property ResolvedHistoryTexture: TVulkanRHITexture read GetResolvedHistoryTexture;
    property PreviousHistoryTexture: TVulkanRHITexture read GetPreviousHistoryTexture;
    property TAAPipeline: TRHIComputePipeline read FTAAPipeline;
    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property SampleCount: Cardinal read FSampleCount write FSampleCount;
    property BlendFactor: Single read FBlendFactor write FBlendFactor;
    property VarianceClipGamma: Single read FVarianceClipGamma write FVarianceClipGamma;
    property VelocityWeightScale: Single read FVelocityWeightScale write FVelocityWeightScale;
    property TotalTAADispatches: Cardinal read FTotalTAADispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 17.2: Localized Box-Projected Parallax Reflection Probes             }
  { -------------------------------------------------------------------------- }

  { Manages up to CASTLE_MAX_REFLECTION_PROBES (16) localized reflection probes with
    OBB/AABB box-projected parallax ray-box intersection and trilinear distance blending. }
  TCastleVulkanReflectionProbeManager = class
  private
    FDevice: TVulkanRHIDevice;
    FProbes: array[0 .. CASTLE_MAX_REFLECTION_PROBES - 1] of TCastleReflectionProbeEntry;
    FProbeCount: Cardinal;
    FProbeBuffer: TVulkanRHIBuffer;
    FTotalUploads: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure ClearProbes;
    function AddProbe(const AWorldPos, ABoxMin, ABoxMax: TVector3;
      const ARadius: Single; const AIntensity: Single = 1.0;
      const ABlendDistance: Single = 1.0; const ACubemapIndex: Cardinal = 0;
      const ABoxProjection: Boolean = True): Integer;
    function GetProbe(const AIndex: Integer): TCastleReflectionProbeEntry;
    procedure UploadProbes;

    { Evaluates the box-projected parallax reflection lookup direction from AWorldPos
      along AWorldReflectDir against the AABB [ABoxMin, ABoxMax] centered at AProbePos. }
    class function EvaluateBoxProjectedDirection(
      const AWorldPos, AWorldReflectDir, AProbePos, ABoxMin, ABoxMax: TVector3): TVector3; static;

    { Evaluates the smooth trilinear probe influence weight in [0..1] inside [ABoxMin, ABoxMax]
      with inner edge falloff ABlendDistance. }
    class function EvaluateProbeInfluenceWeight(
      const AWorldPos, ABoxMin, ABoxMax: TVector3;
      const ABlendDistance: Single): Single; static;

    property ProbeCount: Cardinal read FProbeCount;
    property ProbeBuffer: TVulkanRHIBuffer read FProbeBuffer;
    property TotalUploads: Cardinal read FTotalUploads;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 17.3: Oriented Bounding Box (OBB) Decal Projection                   }
  { -------------------------------------------------------------------------- }

  { Manages up to CASTLE_MAX_PROJECTED_DECALS (64) world-space OBB projected decals
    with depth-reconstructed local box UVs, normal angle rejection fade, and GPU buffer upload. }
  TCastleVulkanDecalManager = class
  private
    FDevice: TVulkanRHIDevice;
    FDecals: array[0 .. CASTLE_MAX_PROJECTED_DECALS - 1] of TCastleProjectedDecalEntry;
    FDecalCount: Cardinal;
    FDecalBuffer: TVulkanRHIBuffer;
    FTotalUploads: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure ClearDecals;
    function AddBoxDecal(const ACenter, AHalfExtents, AForwardNormal: TVector3;
      const AAlbedoTint: TVector3; const AOpacity, ARoughness: Single;
      const AUVScaleOffset: TVector4): Integer;
    function GetDecal(const AIndex: Integer): TCastleProjectedDecalEntry;
    procedure UploadDecals;

    { Projects AWorldPos into ADecal's local unit box [-0.5 .. +0.5]^3.
      Returns True if AWorldPos is inside the OBB and outputs ADecalUV in [0..1]^2. }
    class function ProjectWorldPointToDecalUV(const AWorldPos: TVector3;
      const ADecal: TCastleProjectedDecalEntry;
      out ADecalUV: TVector2; out ALocalPos: TVector3): Boolean; static;

    { Evaluates the combined surface-normal grazing-angle rejection and Z-box edge fade in [0..1]. }
    class function EvaluateDecalAngleAndBoxFade(
      const ALocalPos, ASurfaceNormal, ADecalForward: TVector3;
      const AAngleFadeCos: Single = 0.25): Single; static;

    property DecalCount: Cardinal read FDecalCount;
    property DecalBuffer: TVulkanRHIBuffer read FDecalBuffer;
    property TotalUploads: Cardinal read FTotalUploads;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 18.1: GPU Compute Particle Simulation & Indirect Billboard Rendering }
  { -------------------------------------------------------------------------- }

  { GPU-driven particle simulation subsystem managing the persistent SSBO particle pool,
    compacted alive index buffer, VkDrawIndirectCommand buffer, and compute pipeline. }
  TCastleVulkanComputeParticles = class
  private
    FDevice: TVulkanRHIDevice;
    FParticleBuffer: TVulkanRHIBuffer;
    FAliveIndexBuffer: TVulkanRHIBuffer;
    FIndirectDrawBuffer: TVulkanRHIBuffer;
    FSimulationPipeline: TRHIComputePipeline;
    FMaxParticles: Cardinal;
    FGravity: TVector3;
    FDrag: Single;
    FGroundPlaneY: Single;
    FRestitution: Single;
    FTotalSimulationDispatches: Cardinal;
    procedure EnsureSimulationPipeline;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure EnsureParticleBuffers(const AMaxParticles: Cardinal = CASTLE_DEFAULT_MAX_PARTICLES);
    function DispatchParticleSimulation(const ACmd: TRHICommandList;
      const ADeltaTime: Single): Cardinal;

    { Simulates one Euler integration step with drag, ground-plane bounce, and age decay.
      Returns True if the particle remains alive (Age < Lifetime). }
    class function SimulateParticleStep(var AParticle: TCastleGPUParticle;
      const AGravity: TVector3; const ADrag, AGroundY, ARestitution, ADeltaTime: Single): Boolean; static;

    property ParticleBuffer: TVulkanRHIBuffer read FParticleBuffer;
    property AliveIndexBuffer: TVulkanRHIBuffer read FAliveIndexBuffer;
    property IndirectDrawBuffer: TVulkanRHIBuffer read FIndirectDrawBuffer;
    property SimulationPipeline: TRHIComputePipeline read FSimulationPipeline;
    property MaxParticles: Cardinal read FMaxParticles;
    property Gravity: TVector3 read FGravity write FGravity;
    property Drag: Single read FDrag write FDrag;
    property GroundPlaneY: Single read FGroundPlaneY write FGroundPlaneY;
    property Restitution: Single read FRestitution write FRestitution;
    property TotalSimulationDispatches: Cardinal read FTotalSimulationDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 18.2: Weighted Blended Order-Independent Transparency (McGuire 2013) }
  { -------------------------------------------------------------------------- }

  { Manages the dual MRT targets (pfRGBA16_Float accumulation + pfR16_Float revealage)
    and depth-weight/composite math for Weighted Blended Order-Independent Transparency. }
  TCastleVulkanWeightedBlendedOIT = class
  private
    FDevice: TVulkanRHIDevice;
    FOITAccumTexture: TVulkanRHITexture;
    FOITRevealageTexture: TVulkanRHITexture;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FWeightScale: Single;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure EnsureOITTargets(const AWidth, AHeight: Cardinal);

    { Evaluates the McGuire-Bavoil 2013 depth weight w(z, alpha) clamped to [1e-2 .. 3e3]. }
    class function EvaluateOITDepthWeight(const ALinearZ, AAlpha, AWeightScale: Single): Single; static;

    { Accumulates a transparent sample (PremulRGB, Alpha) at ALinearZ into AAccumRGBA and ARevealage. }
    class procedure AccumulateOITSample(const APremulColorAndAlpha: TVector4;
      const ALinearZ, AWeightScale: Single;
      var AAccumRGBA: TVector4; var ARevealage: Single); static;

    { Composites accumulated OIT buffers over AOpaqueRGB:
      mix(Accum.rgb / max(Accum.a, 1e-5), OpaqueRGB, Revealage). }
    class function EvaluateOITComposite(const AAccumRGBA: TVector4;
      const ARevealage: Single; const AOpaqueRGB: TVector3): TVector3; static;

    property OITAccumTexture: TVulkanRHITexture read FOITAccumTexture;
    property OITRevealageTexture: TVulkanRHITexture read FOITRevealageTexture;
    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property WeightScale: Single read FWeightScale write FWeightScale;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 18.3: Screen-Space Raymarched Contact Shadows                        }
  { -------------------------------------------------------------------------- }

  { Screen-space depth raymarcher for fine contact shadows that complement CSM shadow maps. }
  TCastleVulkanContactShadows = class
  private
    FDevice: TVulkanRHIDevice;
    FContactShadowTexture: TVulkanRHITexture;
    FContactShadowPipeline: TRHIComputePipeline;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FLightDirView: TVector3;
    FRayLength: Single;
    FThickness: Single;
    FStepCount: Cardinal;
    FContrast: Single;
    FZNear: Single;
    FZFar: Single;
    FTotalContactShadowDispatches: Cardinal;
    procedure EnsureContactShadowPipeline;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure EnsureContactShadowTarget(const AWidth, AHeight: Cardinal);
    function DispatchContactShadows(const ACmd: TRHICommandList;
      const ADepthTexture: TRHITexture): Cardinal;

    { Traces a 1D depth ray across ASceneLinearDepths with thickness window AThickness.
      Returns True if an occlusion hit was detected, and outputs AVisibility in [0..1]. }
    class function EvaluateContactShadowRay1D(
      const ASceneLinearDepths: array of Single;
      const AStartLinearZ, ARayStepZ, AThickness: Single;
      out AVisibility: Single): Boolean; static;

    property ContactShadowTexture: TVulkanRHITexture read FContactShadowTexture;
    property ContactShadowPipeline: TRHIComputePipeline read FContactShadowPipeline;
    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property LightDirView: TVector3 read FLightDirView write FLightDirView;
    property RayLength: Single read FRayLength write FRayLength;
    property Thickness: Single read FThickness write FThickness;
    property StepCount: Cardinal read FStepCount write FStepCount;
    property Contrast: Single read FContrast write FContrast;
    property ZNear: Single read FZNear write FZNear;
    property ZFar: Single read FZFar write FZFar;
    property TotalContactShadowDispatches: Cardinal read FTotalContactShadowDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 19.1: Compute Shader Skeletal Skinning & Morph Target Blending       }
  { -------------------------------------------------------------------------- }

  { GPU compute skeletal skinning and morph target blending subsystem writing
    deformed vertices and previous-frame positions for TAA motion vectors. }
  TCastleVulkanComputeSkinner = class
  private
    FDevice: TVulkanRHIDevice;
    FSourceVertexBuffer: TVulkanRHIBuffer;
    FMorphDeltaBuffer: TVulkanRHIBuffer;
    FJointMatrixBuffer: TVulkanRHIBuffer;
    FSkinnedVertexBuffer: TVulkanRHIBuffer;
    FPreviousPositionBuffer: TVulkanRHIBuffer;
    FSkinningPipeline: TRHIComputePipeline;
    FMaxVertices: Cardinal;
    FMorphTargetCount: Cardinal;
    FMorphWeights: TVector4;
    FTotalSkinningDispatches: Cardinal;
    procedure EnsureSkinningPipeline;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure EnsureSkinningBuffers(
      const AMaxVertices: Cardinal = CASTLE_DEFAULT_MAX_SKINNED_VERTICES;
      const AMorphTargetCount: Cardinal = 4);
    function DispatchComputeSkinning(const ACmd: TRHICommandList;
      const AVertexCount: Cardinal; const AJointCount: Cardinal = 64;
      const AStorePreviousPos: Boolean = True): Cardinal;

    { CPU reference evaluation of morph target displacement + 4-bone Linear Blend Skinning (LBS). }
    class procedure EvaluateVertexSkinningAndMorph(
      const ASourceVertex: TCastleSkinningVertex;
      const AMorphDeltas: array of TCastleMorphTargetDelta;
      const AMorphWeights: TVector4;
      const AJointMatrices: array of TMatrix4;
      out ASkinnedPos, ASkinnedNormal: TVector3); static;

    property SourceVertexBuffer: TVulkanRHIBuffer read FSourceVertexBuffer;
    property MorphDeltaBuffer: TVulkanRHIBuffer read FMorphDeltaBuffer;
    property JointMatrixBuffer: TVulkanRHIBuffer read FJointMatrixBuffer;
    property SkinnedVertexBuffer: TVulkanRHIBuffer read FSkinnedVertexBuffer;
    property PreviousPositionBuffer: TVulkanRHIBuffer read FPreviousPositionBuffer;
    property SkinningPipeline: TRHIComputePipeline read FSkinningPipeline;
    property MaxVertices: Cardinal read FMaxVertices;
    property MorphTargetCount: Cardinal read FMorphTargetCount;
    property MorphWeights: TVector4 read FMorphWeights write FMorphWeights;
    property TotalSkinningDispatches: Cardinal read FTotalSkinningDispatches;
  end;

  { -------------------------------------------------------------------------- }
  { Phase 19.2: GPU-Driven Continuous Distance-Dependent LOD (CDLOD) Terrain   }
  { -------------------------------------------------------------------------- }

  { Manages quadtree terrain CDLOD patch nodes, morph distance ranges, and GPU SSBO upload. }
  TCastleVulkanTerrainCDLOD = class
  private
    FDevice: TVulkanRHIDevice;
    FNodes: array[0 .. CASTLE_MAX_TERRAIN_CDLOD_NODES - 1] of TCastleTerrainCDLODNode;
    FNodeCount: Cardinal;
    FNodeBuffer: TVulkanRHIBuffer;
    FBaseLODDistance: Single;
    FMorphStartRatio: Single;
    FTotalNodeUploads: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure ClearNodes;
    function AddTerrainNode(const AWorldX, AWorldZ, APatchSize: Single;
      const ALODLevel: Cardinal; const AMinY, AMaxY: Single): Integer;
    function GetTerrainNode(const AIndex: Integer): TCastleTerrainCDLODNode;
    procedure UploadNodes;

    { Evaluates the continuous CDLOD morph factor k in [0..1] for ACameraDistance inside [ALODNearDist, ALODFarDist]. }
    class function EvaluateCDLODMorphFactor(
      const ACameraDistance, ALODNearDist, ALODFarDist, AMorphStartRatio: Single): Single; static;

    { Morphs a normalized patch grid UV [0..1]^2 smoothly toward the next coarser LOD grid when AMorphFactor -> 1. }
    class function MorphCDLODGridVertex(const AGridUV: TVector2;
      const APatchResolution, AMorphFactor: Single): TVector2; static;

    property NodeCount: Cardinal read FNodeCount;
    property NodeBuffer: TVulkanRHIBuffer read FNodeBuffer;
    property BaseLODDistance: Single read FBaseLODDistance write FBaseLODDistance;
    property MorphStartRatio: Single read FMorphStartRatio write FMorphStartRatio;
    property TotalNodeUploads: Cardinal read FTotalNodeUploads;
  end;

  { -------------------------------------------------------------------------- }
  { Rayleigh / Mie Physical Sky & Aerial Perspective LUT (Phase 20.2)          }
  { -------------------------------------------------------------------------- }

  { Manages the rgba16f Sky-View LUT texture, planetary Rayleigh/Mie atmospheric
    scattering parameters, and compute shader dispatch. }
  TCastleVulkanAtmosphereRenderer = class
  private
    FDevice: TVulkanRHIDevice;
    FSkyViewLUTTexture: TVulkanRHITexture;
    FSunDirection: TVector3;
    FSunIntensity: Single;
    FRayleighScattering: TVector3;
    FRayleighScaleHeight: Single;
    FMieScattering: TVector3;
    FMieScaleHeight: Single;
    FPlanetRadius: Single;
    FAtmosphereRadius: Single;
    FMieAnisotropyG: Single;
    FRaymarchSteps: Cardinal;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRGBA16_Float Sky-View LUT texture (default 192x108). }
    procedure EnsureSkyViewLUT(
      const AWidth: Cardinal = CASTLE_DEFAULT_SKY_VIEW_LUT_WIDTH;
      const AHeight: Cardinal = CASTLE_DEFAULT_SKY_VIEW_LUT_HEIGHT);

    { Evaluates CPU reference single-scattering planetary sky radiance along AViewDir. }
    function EvaluateSkyRayRadiance(const AViewDir, ASunDir: TVector3): TVector3;

    { Dispatches the Rayleigh/Mie Sky-View LUT compute pass. }
    procedure DispatchAtmosphereSky(
      const ACommandList: TVulkanRHICommandList;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil;
      const AWidth: Cardinal = CASTLE_DEFAULT_SKY_VIEW_LUT_WIDTH;
      const AHeight: Cardinal = CASTLE_DEFAULT_SKY_VIEW_LUT_HEIGHT);

    property SkyViewLUTTexture: TVulkanRHITexture read FSkyViewLUTTexture;
    property SunDirection: TVector3 read FSunDirection write FSunDirection;
    property SunIntensity: Single read FSunIntensity write FSunIntensity;
    property RayleighScattering: TVector3 read FRayleighScattering write FRayleighScattering;
    property RayleighScaleHeight: Single read FRayleighScaleHeight write FRayleighScaleHeight;
    property MieScattering: TVector3 read FMieScattering write FMieScattering;
    property MieScaleHeight: Single read FMieScaleHeight write FMieScaleHeight;
    property PlanetRadius: Single read FPlanetRadius write FPlanetRadius;
    property AtmosphereRadius: Single read FAtmosphereRadius write FAtmosphereRadius;
    property MieAnisotropyG: Single read FMieAnisotropyG write FMieAnisotropyG;
    property RaymarchSteps: Cardinal read FRaymarchSteps write FRaymarchSteps;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Compute Gerstner Wave Ocean Simulation & Foam (Phase 21.2)             }
  { -------------------------------------------------------------------------- }

  { Manages multi-octave directional Gerstner ocean wave displacement, analytical
    surface normals, Jacobian crest whitecap foam, and compute shader dispatch. }
  TCastleVulkanOceanSimulator = class
  private
    FDevice: TVulkanRHIDevice;
    FDisplacementAndFoamTexture: TVulkanRHITexture;
    FNormalAndSlopeTexture: TVulkanRHITexture;
    FWindDirection: TVector2;
    FWindSpeed: Single;
    FSimulationTime: Single;
    FBaseAmplitude: Single;
    FBaseWavelength: Single;
    FChoppiness: Single;
    FPatchWorldSize: Single;
    FOctaveCount: Cardinal;
    FFoamThreshold: Single;
    FGravity: Single;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the pfRGBA16_Float displacement+foam and normal+slope textures (default 128x128). }
    procedure EnsureOceanTextures(const AGridSize: Cardinal = CASTLE_DEFAULT_OCEAN_GRID_SIZE);

    { Evaluates CPU reference multi-octave Gerstner wave 3D displacement, analytical normal, and Jacobian crest foam. }
    procedure EvaluateGerstnerWavePoint(const AWorldXZ: TVector2; const ATimeSeconds: Single;
      out ADisplacement, ANormal: TVector3; out AFoamFactor: Single);

    { Dispatches the GPU compute ocean displacement & normal/foam generation pass. }
    procedure DispatchOceanSimulation(
      const ACommandList: TVulkanRHICommandList;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil;
      const AGridSize: Cardinal = CASTLE_DEFAULT_OCEAN_GRID_SIZE);

    property DisplacementAndFoamTexture: TVulkanRHITexture read FDisplacementAndFoamTexture;
    property NormalAndSlopeTexture: TVulkanRHITexture read FNormalAndSlopeTexture;
    property WindDirection: TVector2 read FWindDirection write FWindDirection;
    property WindSpeed: Single read FWindSpeed write FWindSpeed;
    property SimulationTime: Single read FSimulationTime write FSimulationTime;
    property BaseAmplitude: Single read FBaseAmplitude write FBaseAmplitude;
    property BaseWavelength: Single read FBaseWavelength write FBaseWavelength;
    property Choppiness: Single read FChoppiness write FChoppiness;
    property PatchWorldSize: Single read FPatchWorldSize write FPatchWorldSize;
    property OctaveCount: Cardinal read FOctaveCount write FOctaveCount;
    property FoamThreshold: Single read FFoamThreshold write FFoamThreshold;
    property Gravity: Single read FGravity write FGravity;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Dynamic Diffuse Global Illumination (DDGI) Octahedral Probe Grid (22.1)    }
  { -------------------------------------------------------------------------- }

  { Manages a 3D world-space irradiance probe grid encoded in 2D octahedral
    irradiance (pfRGBA16_Float) and distance/variance (pfRG16_Float) atlases. }
  TCastleVulkanDDGIGrid = class
  private
    FDevice: TVulkanRHIDevice;
    FIrradianceAtlasTexture: TVulkanRHITexture;
    FVisibilityAtlasTexture: TVulkanRHITexture;
    FGridOrigin: TVector3;
    FGridSpacing: TVector3;
    FGridCountX: Cardinal;
    FGridCountY: Cardinal;
    FGridCountZ: Cardinal;
    FNormalBias: Single;
    FViewBias: Single;
    FHysteresis: Single;
    FUpdateCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates or resizes the 2D octahedral irradiance and visibility probe atlases. }
    procedure EnsureProbeAtlases;

    { Returns the world-space position of probe (AProbeX, AProbeY, AProbeZ). }
    function GetProbeWorldPosition(const AProbeX, AProbeY, AProbeZ: Cardinal): TVector3;

    { Dispatches the DDGI probe irradiance & visibility atlas update compute pass. }
    procedure DispatchDDGIUpdate(
      const ACommandList: TVulkanRHICommandList;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property IrradianceAtlasTexture: TVulkanRHITexture read FIrradianceAtlasTexture;
    property VisibilityAtlasTexture: TVulkanRHITexture read FVisibilityAtlasTexture;
    property GridOrigin: TVector3 read FGridOrigin write FGridOrigin;
    property GridSpacing: TVector3 read FGridSpacing write FGridSpacing;
    property GridCountX: Cardinal read FGridCountX write FGridCountX;
    property GridCountY: Cardinal read FGridCountY write FGridCountY;
    property GridCountZ: Cardinal read FGridCountZ write FGridCountZ;
    property NormalBias: Single read FNormalBias write FNormalBias;
    property ViewBias: Single read FViewBias write FViewBias;
    property Hysteresis: Single read FHysteresis write FHysteresis;
    property UpdateCount: Cardinal read FUpdateCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Meshlet / Sub-Mesh Cluster Cone & Frustum Culling (Phase 22.2)         }
  { -------------------------------------------------------------------------- }

  { Manages 64-vertex / 124-triangle meshlet cluster descriptors, normal-cone
    backface culling, and GPU visible meshlet compaction. }
  TCastleVulkanMeshletCuller = class
  private
    FDevice: TVulkanRHIDevice;
    FMeshlets: array[0 .. CASTLE_MAX_MESHLETS - 1] of TCastleMeshletDescriptor;
    FMeshletCount: Cardinal;
    FMeshletBuffer: TVulkanRHIBuffer;
    FVisibleMeshletIndicesBuffer: TVulkanRHIBuffer;
    FVisibleMeshletCountBuffer: TVulkanRHIBuffer;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    procedure ClearMeshlets;
    function AddMeshlet(const ASphereCenter: TVector3; const ASphereRadius: Single;
      const AConeAxis: TVector3; const AConeCutoff: Single;
      const AVertexOffset, AVertexCount, ATriangleOffset, ATriangleCount: Cardinal): Integer;
    procedure UploadMeshlets;

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

    property MeshletCount: Cardinal read FMeshletCount;
    property MeshletBuffer: TVulkanRHIBuffer read FMeshletBuffer;
    property VisibleMeshletIndicesBuffer: TVulkanRHIBuffer read FVisibleMeshletIndicesBuffer;
    property VisibleMeshletCountBuffer: TVulkanRHIBuffer read FVisibleMeshletCountBuffer;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Virtual Shadow Maps (VSM) Page Table & Physical Tile Pool (Phase 23.2)     }
  { -------------------------------------------------------------------------- }

  { Manages a 64x64 virtual shadow page table mapped on-demand into a 16x16
    (256-tile, 2048x2048) physical shadow depth tile pool. }
  TCastleVulkanVirtualShadowMap = class
  private
    FDevice: TVulkanRHIDevice;
    FPageTable: array[0 .. CASTLE_VSM_PAGE_TABLE_DIM * CASTLE_VSM_PAGE_TABLE_DIM - 1] of Cardinal;
    FPageTableBuffer: TVulkanRHIBuffer;
    FPhysicalTilePoolTexture: TVulkanRHITexture;
    FAllocatedTileCount: Cardinal;
    FTotalPageUploads: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all virtual page table entries and resets the physical tile bump allocator. }
    procedure ResetPageTable;

    { Allocates the 2048x2048 physical shadow tile pool texture and page table SSBO. }
    procedure EnsureResources;

    { Requests virtual page (APageX, APageY), allocating a physical 128x128 tile if not yet resident. }
    function RequestAndAllocateVirtualPage(const APageX, APageY: Cardinal;
      out APhysicalTileX, APhysicalTileY: Cardinal): Boolean;

    { Returns the packed 32-bit page table entry at (APageX, APageY). }
    function GetPageEntry(const APageX, APageY: Cardinal): Cardinal;

    { Translates a virtual shadow UV in [0..1]^2 into physical tile pool UV if the virtual page is resident. }
    function ComputePhysicalAtlasUV(const AVirtualUV: TVector2;
      out APageX, APageY: Cardinal; out APhysicalUV: TVector2): Boolean;

    { Uploads the 64x64 page table into PageTableBuffer. }
    procedure UploadPageTable;

    property PageTableBuffer: TVulkanRHIBuffer read FPageTableBuffer;
    property PhysicalTilePoolTexture: TVulkanRHITexture read FPhysicalTilePoolTexture;
    property AllocatedTileCount: Cardinal read FAllocatedTileCount;
    property TotalPageUploads: Cardinal read FTotalPageUploads;
  end;

  { -------------------------------------------------------------------------- }
  { GPU-Driven Continuous Instance LOD Selector (Phase 24.1)                   }
  { -------------------------------------------------------------------------- }

  { Evaluates projected vertical screen-height coverage and selects discrete LOD
    levels (LOD0..LOD3 or -1 culled) + continuous crossfade weights per instance. }
  TCastleVulkanLODSelector = class
  private
    FDevice: TVulkanRHIDevice;
    FInstances: array of TCastleLODInstanceDescriptor;
    FInstanceCount: Cardinal;
    FInstanceBuffer: TVulkanRHIBuffer;
    FSelectedLODBuffer: TVulkanRHIBuffer;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered instances. }
    procedure ClearInstances;

    { Registers an instance bounding sphere and 4-level screen coverage thresholds. }
    function AddInstance(
      const ASphereCenter: TVector3;
      const ARadius: Single;
      const AThresholds: TVector4;
      const AMeshID: Cardinal = 0;
      const ATransitionBand: Single = 0.02): Integer;

    { Uploads the registered instance array into GPU SSBOs. }
    procedure UploadInstances;

    { Evaluates on CPU how many instances select LOD0..LOD3 vs culled, returning total visible instances. }
    function EvaluateInstanceLODsCPU(
      const ACameraPosition: TVector3;
      const ACotHalfFovY: Single;
      out ALOD0Count, ALOD1Count, ALOD2Count, ALOD3Count, ACulledCount: Cardinal): Cardinal;

    { Dispatches the GPU compute LOD selection pass. }
    procedure DispatchLODSelection(
      const ACommandList: TVulkanRHICommandList;
      const ACameraPosition: TVector3;
      const ACotHalfFovY: Single;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property InstanceCount: Cardinal read FInstanceCount;
    property InstanceBuffer: TVulkanRHIBuffer read FInstanceBuffer;
    property SelectedLODBuffer: TVulkanRHIBuffer read FSelectedLODBuffer;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Texture Streaming Mipmap Residency & Feedback Analyzer (Phase 25.2)    }
  { -------------------------------------------------------------------------- }

  TCastleStreamedTextureEntry = record
    Width: Cardinal;
    Height: Cardinal;
    MipLevels: Cardinal;
    ResidentMip: Cardinal;
    RequestedMip: Cardinal;
  end;

  { Tracks per-texture desired mip levels from GPU derivative feedback and resolves
    high-resolution mip promotions and unreferenced mip evictions. }
  TCastleVulkanTextureStreamer = class
  private
    FDevice: TVulkanRHIDevice;
    FEntries: array[0 .. CASTLE_MAX_STREAMED_TEXTURES - 1] of TCastleStreamedTextureEntry;
    FTextureCount: Cardinal;
    FFeedbackBuffer: TVulkanRHIBuffer;
    FUpdateCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered streamable textures. }
    procedure ClearTextures;

    { Registers a streamable texture and its current coarsest resident mip level. }
    function RegisterStreamableTexture(
      const AWidth, AHeight, AMipLevels, AInitialResidentMip: Cardinal): Integer;

    { Resets per-frame requested mip feedback slots to $FF (unreferenced). }
    procedure ResetFrameFeedback;

    { Records a pixel's requested mip level for ATextureIndex (atomic min semantics). }
    procedure RecordMipFeedback(const ATextureIndex, ARequestedMip: Cardinal);

    { Returns the current resident mip level for ATextureIndex. }
    function GetResidentMip(const ATextureIndex: Cardinal): Cardinal;

    { Resolves pending mip promotions (RequestedMip < ResidentMip) and evictions
      (unreferenced textures demoted by 1 mip toward MipLevels - 1), returning total transitions. }
    function ResolveStreamingRequests(
      out APromotedCount, AEvictedCount: Cardinal): Cardinal;

    { Uploads the per-texture requested mip array into FeedbackBuffer. }
    procedure UploadFeedbackBuffer;

    property TextureCount: Cardinal read FTextureCount;
    property FeedbackBuffer: TVulkanRHIBuffer read FFeedbackBuffer;
    property UpdateCount: Cardinal read FUpdateCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Shadow Caster Light-Ray Extrusion Culler (Phase 26.3)                  }
  { -------------------------------------------------------------------------- }

  { Culls shadow-casting instances whose bounding sphere swept along the light
    ray direction does not intersect the camera receiver frustum AABB. }
  TCastleVulkanShadowCasterCuller = class
  private
    FDevice: TVulkanRHIDevice;
    FCasters: array of TVector4;
    FCasterCount: Cardinal;
    FCasterBuffer: TVulkanRHIBuffer;
    FVisibleCasterBuffer: TVulkanRHIBuffer;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered shadow-caster bounding spheres. }
    procedure ClearCasters;

    { Registers a shadow-caster bounding sphere (world center + radius). }
    function AddCaster(const ASphereCenter: TVector3; const ASphereRadius: Single): Integer;

    { Uploads the registered shadow-caster spheres into GPU SSBOs. }
    procedure UploadCasters;

    { Evaluates on CPU how many shadow casters can cast shadows into [AReceiverBoxMin, AReceiverBoxMax]. }
    function EvaluateActiveShadowCastersCPU(
      const ALightRayDir: TVector3;
      const AMaxExtrusionDist: Single;
      const AReceiverBoxMin, AReceiverBoxMax: TVector3): Cardinal;

    { Dispatches the GPU compute shadow-caster extrusion culling pass. }
    procedure DispatchShadowCasterCulling(
      const ACommandList: TVulkanRHICommandList;
      const ALightRayDir: TVector3;
      const AMaxExtrusionDist: Single;
      const AReceiverBoxMin, AReceiverBoxMax: TVector3;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property CasterCount: Cardinal read FCasterCount;
    property CasterBuffer: TVulkanRHIBuffer read FCasterBuffer;
    property VisibleCasterBuffer: TVulkanRHIBuffer read FVisibleCasterBuffer;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Nanite-Style Hierarchical Cluster DAG Cut Selector (Phase 27.2)            }
  { -------------------------------------------------------------------------- }

  { Evaluates monotonic parent/child screen-space simplification errors across a
    cluster DAG and selects the crack-free LOD cut where
    ParentProjectedErrorPx > PixelErrorThreshold >= SelfProjectedErrorPx. }
  TCastleVulkanClusterDAG = class
  private
    FDevice: TVulkanRHIDevice;
    FNodes: array of TCastleClusterDAGNode;
    FNodeCount: Cardinal;
    FDAGNodeBuffer: TVulkanRHIBuffer;
    FSelectedCutBuffer: TVulkanRHIBuffer;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered cluster DAG nodes. }
    procedure ClearNodes;

    { Registers a cluster DAG node with its bounding sphere, self world error, and parent world error. }
    function AddClusterNode(
      const ASphereCenter: TVector3;
      const ASphereRadius, ASelfWorldError, AParentWorldError: Single;
      const AVertexOffset: Cardinal = 0;
      const ATriangleOffset: Cardinal = 0;
      const ATriangleCount: Cardinal = 124): Integer;

    { Uploads the registered cluster DAG nodes into GPU SSBOs. }
    procedure UploadNodes;

    { Evaluates on CPU how many cluster DAG nodes lie on the active crack-free cut. }
    function EvaluateDAGCutCPU(
      const ACameraPosition: TVector3;
      const ACotHalfFovY, AViewportHeight, APixelErrorThreshold: Single): Cardinal;

    { Dispatches the GPU compute cluster DAG cut selection pass. }
    procedure DispatchDAGCutSelection(
      const ACommandList: TVulkanRHICommandList;
      const ACameraPosition: TVector3;
      const ACotHalfFovY, AViewportHeight, APixelErrorThreshold: Single;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property NodeCount: Cardinal read FNodeCount;
    property DAGNodeBuffer: TVulkanRHIBuffer read FDAGNodeBuffer;
    property SelectedCutBuffer: TVulkanRHIBuffer read FSelectedCutBuffer;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Lumen-Style 3D Clipmap Global Signed Distance Field (Phase 28.1)           }
  { -------------------------------------------------------------------------- }

  TCastleSDFBoxPrimitive = record
    Center: TVector3;
    HalfExtents: TVector3;
  end;

  { Maintains a 3D Global Signed Distance Field (SDF) clipmap texture and scene
    box SDF primitives for hardware-ray-tracing-free sphere marching and sky/soft-shadow cones. }
  TCastleVulkanGlobalSDF = class
  private
    FDevice: TVulkanRHIDevice;
    FPrimitives: array of TCastleSDFBoxPrimitive;
    FPrimitiveCount: Cardinal;
    FGridResolution: Cardinal;
    FClipmapHalfExtent: Single;
    FSmoothBlendRadius: Single;
    FClipmapVolumeTexture: TVulkanRHITexture;
    FBuildCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all registered SDF box primitives. }
    procedure ClearPrimitives;

    { Registers an axis-aligned box SDF primitive into the global distance field. }
    function AddBoxPrimitive(const ABoxCenter, ABoxHalfExtents: TVector3): Integer;

    { Allocates the 3D (td3D, pfR16_Float) Global SDF Clipmap volume texture. }
    procedure EnsureVolumeResources(const AGridResolution: Cardinal = 32);

    { Evaluates the smooth-unioned signed distance at AWorldPos across all registered primitives. }
    function EvaluateGlobalSDFDistanceCPU(const AWorldPos: TVector3): Single;

    { Sphere-marches a ray [ARayOrigin, ARayDir] up to AMaxDistance against the Global SDF. }
    function TraceSphereMarchCPU(
      const ARayOrigin, ARayDir: TVector3;
      const AMaxDistance: Single;
      out AHitDistance: Single;
      out AHitSteps: Cardinal;
      const AMaxSteps: Cardinal = 64;
      const AHitEpsilon: Single = 0.01): Boolean;

    { Records a Global SDF clipmap build/update dispatch. }
    procedure DispatchGlobalSDFBuild(
      const ACommandList: TVulkanRHICommandList;
      const AGridResolution: Cardinal = 32);

    property PrimitiveCount: Cardinal read FPrimitiveCount;
    property GridResolution: Cardinal read FGridResolution;
    property ClipmapHalfExtent: Single read FClipmapHalfExtent write FClipmapHalfExtent;
    property SmoothBlendRadius: Single read FSmoothBlendRadius write FSmoothBlendRadius;
    property ClipmapVolumeTexture: TVulkanRHITexture read FClipmapVolumeTexture;
    property BuildCount: Cardinal read FBuildCount;
  end;

  { -------------------------------------------------------------------------- }
  { Lumen-Style 6-Axis Surface Cache Card Atlas (Phase 28.2)                   }
  { -------------------------------------------------------------------------- }

  { Manages a 2D Surface Cache Card Atlas (Albedo + Direct/Indirect Radiance)
    storing 6-axis (+X, -X, +Y, -Y, +Z, -Z) orthographic surface cards per mesh. }
  TCastleVulkanSurfaceCache = class
  private
    FDevice: TVulkanRHIDevice;
    FAtlasResolution: Cardinal;
    FTileResolution: Cardinal;
    FTilesPerRow: Cardinal;
    FMaxCardSlots: Cardinal;
    FAllocatedCardCount: Cardinal;
    FAlbedoAtlasTexture: TVulkanRHITexture;
    FDirectLightingAtlasTexture: TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Resets all allocated surface cache card slots. }
    procedure ResetCards;

    { Allocates 6 contiguous card slots (+X, -X, +Y, -Y, +Z, -Z) for a mesh instance. }
    function AllocateSixAxisCards(out AFirstCardSlot: Cardinal): Boolean;

    { Computes the normalized [0..1] atlas UV offset and scale for ACardSlot. }
    procedure GetCardAtlasOffsetAndScale(
      const ACardSlot: Cardinal;
      out AOffsetUV, AScaleUV: TVector2);

    { Allocates the Albedo and DirectLighting 2D Surface Cache Atlas textures. }
    procedure EnsureAtlasTextures;

    property AtlasResolution: Cardinal read FAtlasResolution;
    property TileResolution: Cardinal read FTileResolution;
    property MaxCardSlots: Cardinal read FMaxCardSlots;
    property AllocatedCardCount: Cardinal read FAllocatedCardCount;
    property AlbedoAtlasTexture: TVulkanRHITexture read FAlbedoAtlasTexture;
    property DirectLightingAtlasTexture: TVulkanRHITexture read FDirectLightingAtlasTexture;
  end;

  { -------------------------------------------------------------------------- }
  { ReSTIR DI/GI Spatio-Temporal Reservoir Resampler (Phase 29.2)              }
  { -------------------------------------------------------------------------- }

  { Manages screen-space current and temporal-history ReSTIR reservoir SSBOs
    and dispatches spatio-temporal reservoir resampling (UE5 MegaLights architecture). }
  TCastleVulkanReSTIR = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FMaxHistoryM: Cardinal;
    FCurrentReservoirBuffer: TVulkanRHIBuffer;
    FTemporalHistoryReservoirBuffer: TVulkanRHIBuffer;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates ping-pong Current and TemporalHistory ReSTIR reservoir SSBOs for AWidth x AHeight. }
    procedure EnsureReservoirBuffers(const AWidth, AHeight: Cardinal);

    { Swaps Current and TemporalHistory reservoir buffers at the end of a frame. }
    procedure SwapReservoirHistory;

    { Dispatches the ReSTIR spatio-temporal reservoir resampling compute pass. }
    procedure DispatchSpatioTemporalResampling(
      const ACommandList: TVulkanRHICommandList;
      const AWidth, AHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property MaxHistoryM: Cardinal read FMaxHistoryM write FMaxHistoryM;
    property CurrentReservoirBuffer: TVulkanRHIBuffer read FCurrentReservoirBuffer;
    property TemporalHistoryReservoirBuffer: TVulkanRHIBuffer read FTemporalHistoryReservoirBuffer;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Temporal Super Resolution (TSR) History Upscaler (Phase 30.1)              }
  { -------------------------------------------------------------------------- }

  { Manages lower-resolution input render scaling (e.g. 67% Quality mode) and
    full-resolution ping-pong history/upscaled HDR color textures for UE5-style
    Temporal Super Resolution (TSR). }
  TCastleVulkanTSRUpscaler = class
  private
    FDevice: TVulkanRHIDevice;
    FRenderScale: Single;
    FOutputWidth: Cardinal;
    FOutputHeight: Cardinal;
    FUpscaledColorTexture: TVulkanRHITexture;
    FHistoryColorTexture: TVulkanRHITexture;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Computes the internal lower-resolution input dimensions for a target display resolution. }
    procedure ComputeInputResolution(
      const AOutputWidth, AOutputHeight: Cardinal;
      out AInputWidth, AInputHeight: Cardinal);

    { Allocates full-resolution Upscaled and History RGBA16F textures for AOutputWidth x AOutputHeight. }
    procedure EnsureUpscaleTargets(const AOutputWidth, AOutputHeight: Cardinal);

    { Swaps Upscaled and History textures at the end of a frame. }
    procedure SwapHistoryTargets;

    { Dispatches the TSR compute upscaling pass. }
    procedure DispatchTSRUpscale(
      const ACommandList: TVulkanRHICommandList;
      const AOutputWidth, AOutputHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property RenderScale: Single read FRenderScale write FRenderScale;
    property OutputWidth: Cardinal read FOutputWidth;
    property OutputHeight: Cardinal read FOutputHeight;
    property UpscaledColorTexture: TVulkanRHITexture read FUpscaledColorTexture;
    property HistoryColorTexture: TVulkanRHITexture read FHistoryColorTexture;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Tile-Based Variable Rate Shading (VRS) Manager (Phase 32.2)                }
  { -------------------------------------------------------------------------- }

  { Generates and manages screen-space 16x16 tile shading rate images
    (1x1, 2x1, 1x2, 2x2, 4x4) for VK_KHR_fragment_shading_rate. }
  TCastleVulkanVRSManager = class
  private
    FDevice: TVulkanRHIDevice;
    FTileSize: Cardinal;
    FTileGridWidth: Cardinal;
    FTileGridHeight: Cardinal;
    FShadingRateImage: TVulkanRHITexture;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates the 2D Shading Rate Image (1 texel per 16x16 screen pixel tile). }
    procedure EnsureShadingRateImage(const AViewportWidth, AViewportHeight: Cardinal);

    { Dispatches the luminance-contrast and velocity VRS tile classifier compute pass. }
    procedure DispatchVRSImageGeneration(
      const ACommandList: TVulkanRHICommandList;
      const AViewportWidth, AViewportHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property TileSize: Cardinal read FTileSize write FTileSize;
    property TileGridWidth: Cardinal read FTileGridWidth;
    property TileGridHeight: Cardinal read FTileGridHeight;
    property ShadingRateImage: TVulkanRHITexture read FShadingRateImage;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Runtime Virtual Texturing (RVT) Page Table & Physical Cache (Phase 32.3)   }
  { -------------------------------------------------------------------------- }

  { Manages a 64x64 virtual terrain/decal page table backed by a 16x16 physical
    material tile cache (Albedo + NormalRoughness) for single-lookup landscape shading. }
  TCastleVulkanRuntimeVirtualTexture = class
  private
    FDevice: TVulkanRHIDevice;
    FPageTable: array[0..63, 0..63] of Integer;
    FPhysicalTilesPerRow: Cardinal;
    FPhysicalTileResolution: Cardinal;
    FMaxPhysicalTiles: Cardinal;
    FAllocatedTileCount: Cardinal;
    FPhysicalAlbedoAtlas: TVulkanRHITexture;
    FPhysicalNormalRoughnessAtlas: TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all virtual-to-physical page mappings. }
    procedure ClearPages;

    { Requests or returns an allocated physical tile (X, Y) for virtual page (AVirtualPageX, AVirtualPageY). }
    function RequestRVTPage(
      const AVirtualPageX, AVirtualPageY: Cardinal;
      out APhysicalTileX, APhysicalTileY: Cardinal): Boolean;

    { Allocates the Physical Albedo and NormalRoughness RVT atlas textures. }
    procedure EnsurePhysicalAtlasTextures;

    property PhysicalTilesPerRow: Cardinal read FPhysicalTilesPerRow;
    property PhysicalTileResolution: Cardinal read FPhysicalTileResolution;
    property MaxPhysicalTiles: Cardinal read FMaxPhysicalTiles;
    property AllocatedTileCount: Cardinal read FAllocatedTileCount;
    property PhysicalAlbedoAtlas: TVulkanRHITexture read FPhysicalAlbedoAtlas;
    property PhysicalNormalRoughnessAtlas: TVulkanRHITexture read FPhysicalNormalRoughnessAtlas;
  end;

  { -------------------------------------------------------------------------- }
  { Sparse Brick-Atlas Heterogeneous Volumes (Phase 33.2)                      }
  { -------------------------------------------------------------------------- }

  { Manages a 16x16x16 sparse 3D indirection grid mapping active smoke/fire/explosion
    volume bricks into a physical 3D voxel brick pool (8x8x8 voxels per brick). }
  TCastleVulkanSparseVolumeAtlas = class
  private
    FDevice: TVulkanRHIDevice;
    FIndirectionGrid: array[0..15, 0..15, 0..15] of Integer;
    FBrickResolution: Cardinal;
    FBricksPerAxis: Cardinal;
    FMaxPhysicalBricks: Cardinal;
    FAllocatedBrickCount: Cardinal;
    FPhysicalBrickAtlasTexture: TVulkanRHITexture;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all sparse volume brick allocations. }
    procedure ClearBricks;

    { Allocates or returns the physical brick index for virtual volume coordinate (X, Y, Z). }
    function AllocateVolumeBrick(
      const AVirtualBrickX, AVirtualBrickY, AVirtualBrickZ: Cardinal;
      out APhysicalBrickIndex: Cardinal): Boolean;

    { Allocates the 3D rgba16f Physical Brick Pool texture (BricksPerAxis * BrickResolution)^3. }
    procedure EnsureVolumeAtlasTextures;

    property BrickResolution: Cardinal read FBrickResolution;
    property BricksPerAxis: Cardinal read FBricksPerAxis;
    property MaxPhysicalBricks: Cardinal read FMaxPhysicalBricks;
    property AllocatedBrickCount: Cardinal read FAllocatedBrickCount;
    property PhysicalBrickAtlasTexture: TVulkanRHITexture read FPhysicalBrickAtlasTexture;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Breadcrumb Marker Buffer & VK_ERROR_device_lost Diagnostics (Phase 33.3) }
  { -------------------------------------------------------------------------- }

  TCastleBreadcrumbState = (bsPending, bsActive, bsCompleted);

  TCastleBreadcrumbEntry = record
    MarkerID: Cardinal;
    ScopeName: String;
    State: TCastleBreadcrumbState;
  end;

  { Tracks fine-grained command-buffer pass/draw breadcrumb markers in a host-coherent
    buffer so GPU hangs and VK_ERROR_device_lost TDR faults pinpoint the exact offending pass. }
  TCastleVulkanBreadcrumbTracker = class
  private
    FDevice: TVulkanRHIDevice;
    FEntries: array of TCastleBreadcrumbEntry;
    FBreadcrumbBuffer: TVulkanRHIBuffer;
    function GetTotalScopesRecorded: Cardinal;
    function GetActiveScopeCount: Cardinal;
    function GetCompletedScopeCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Resets recorded breadcrumb scopes at the start of a frame. }
    procedure ResetBreadcrumbs;

    { Allocates the host-coherent GPU breadcrumb marker buffer. }
    procedure EnsureBreadcrumbBuffer;

    { Marks the beginning of a GPU pass/draw scope and returns its 1-based MarkerID. }
    function BeginBreadcrumbScope(
      const ACommandList: TVulkanRHICommandList;
      const AScopeName: String): Cardinal;

    { Marks the completion of a GPU pass/draw scope identified by AMarkerID. }
    procedure EndBreadcrumbScope(
      const ACommandList: TVulkanRHICommandList;
      const AMarkerID: Cardinal);

    { Formats a human-readable post-mortem crash report listing Completed vs. Active (in-flight/hung) GPU passes. }
    function FormatBreadcrumbCrashReport: String;

    property BreadcrumbBuffer: TVulkanRHIBuffer read FBreadcrumbBuffer;
    property TotalScopesRecorded: Cardinal read GetTotalScopesRecorded;
    property ActiveScopeCount: Cardinal read GetActiveScopeCount;
    property CompletedScopeCount: Cardinal read GetCompletedScopeCount;
  end;

  { -------------------------------------------------------------------------- }
  { Spatio-Temporal Variance-Guided Filtering (SVGF) Denoiser (Phase 34.3)     }
  { -------------------------------------------------------------------------- }

  { Orchestrates SVGF temporal moment accumulation and multi-pass A-Trous wavelet
    spatial filtering (step sizes 1, 2, 4, 8, 16) for ray-traced / ReSTIR / Lumen signals. }
  TCastleVulkanSVGFDenoiser = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FAttrousIterations: Cardinal;
    FMomentsHistoryTexture: TVulkanRHITexture;
    FFilteredPingTexture: TVulkanRHITexture;
    FFilteredPongTexture: TVulkanRHITexture;
    FDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates the rg16f MomentsHistory texture and rgba16f Ping/Pong A-Trous filter targets. }
    procedure EnsureSVGFTargets(const AWidth, AHeight: Cardinal);

    { Returns the A-Trous wavelet step size 2^AIterationIndex (1, 2, 4, 8, 16). }
    class function GetAttrousStepSize(const AIterationIndex: Cardinal): Cardinal; static;

    { Dispatches the temporal accumulation + multi-pass A-Trous wavelet spatial denoiser. }
    procedure DispatchSVGFDenoise(
      const ACommandList: TVulkanRHICommandList;
      const AWidth, AHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property AttrousIterations: Cardinal read FAttrousIterations write FAttrousIterations;
    property MomentsHistoryTexture: TVulkanRHITexture read FMomentsHistoryTexture;
    property FilteredPingTexture: TVulkanRHITexture read FFilteredPingTexture;
    property FilteredPongTexture: TVulkanRHITexture read FFilteredPongTexture;
    property DispatchCount: Cardinal read FDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Hardware Ray Tracing Shader Binding Table (SBT) (Phase 35.2)               }
  { -------------------------------------------------------------------------- }

  { Manages VK_KHR_ray_tracing_pipeline Shader Binding Table (SBT) regions
    (Raygen, Miss, Hit, Callable) with hardware handle stride & base alignment. }
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
    FTraceRaysDispatchCount: Cardinal;
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

    property HandleSize: Cardinal read FHandleSize write FHandleSize;
    property HandleAlignment: Cardinal read FHandleAlignment write FHandleAlignment;
    property BaseAlignment: Cardinal read FBaseAlignment write FBaseAlignment;
    property AlignedHandleStride: Cardinal read FAlignedHandleStride;
    property RaygenRegionSize: Cardinal read FRaygenRegionSize;
    property MissRegionSize: Cardinal read FMissRegionSize;
    property HitRegionSize: Cardinal read FHitRegionSize;
    property TotalSBTSizeBytes: Cardinal read FTotalSBTSizeBytes;
    property SBTBuffer: TVulkanRHIBuffer read FSBTBuffer;
    property TraceRaysDispatchCount: Cardinal read FTraceRaysDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { BLAS / TLAS Acceleration Structure & Compaction Manager (Phase 35.3)       }
  { -------------------------------------------------------------------------- }

  TCastleVulkanBLASEntry = record
    BLASID: Cardinal;
    TriangleCount: Cardinal;
    UncompactedBytes: Cardinal;
    CompactedBytes: Cardinal;
    IsCompacted: Boolean;
  end;

  { Tracks Bottom-Level (BLAS) and Top-Level (TLAS) Acceleration Structure builds
    and post-build BLAS memory compaction (VK_KHR_acceleration_structure). }
  TCastleVulkanAccelerationStructureManager = class
  private
    FDevice: TVulkanRHIDevice;
    FBLASEntries: array of TCastleVulkanBLASEntry;
    FTLASInstanceCount: Cardinal;
    FTLASBuildCount: Cardinal;
    FTLASBuffer: TVulkanRHIBuffer;
    function GetBLASCount: Cardinal;
    function GetTotalUncompactedBLASBytes: Cardinal;
    function GetTotalCompactedBLASBytes: Cardinal;
    function GetCompactionSavedBytes: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all tracked BLAS/TLAS entries. }
    procedure ClearAccelerationStructures;

    { Registers a newly built Bottom-Level Acceleration Structure (BLAS) and returns its 1-based BLASID. }
    function RegisterBLASBuild(
      const ATriangleCount, AUncompactedBytes: Cardinal): Cardinal;

    { Compacts an existing BLAS after VK_QUERY_TYPE_ACCELERATION_STRUCTURE_COMPACTED_SIZE_KHR readback. }
    function CompactBLAS(
      const ABLASID: Cardinal;
      const ACompactedBytes: Cardinal = 0): Boolean;

    { Builds or updates the Top-Level Acceleration Structure (TLAS) for AInstanceCount scene instances. }
    procedure BuildTLAS(const AInstanceCount: Cardinal);

    property BLASCount: Cardinal read GetBLASCount;
    property TotalUncompactedBLASBytes: Cardinal read GetTotalUncompactedBLASBytes;
    property TotalCompactedBLASBytes: Cardinal read GetTotalCompactedBLASBytes;
    property CompactionSavedBytes: Cardinal read GetCompactionSavedBytes;
    property TLASInstanceCount: Cardinal read FTLASInstanceCount;
    property TLASBuildCount: Cardinal read FTLASBuildCount;
    property TLASBuffer: TVulkanRHIBuffer read FTLASBuffer;
  end;

  { -------------------------------------------------------------------------- }
  { GPU-Driven XPBD Cloth / Hair Strand Physics Simulator (Phase 36.3)         }
  { -------------------------------------------------------------------------- }

  { Manages GPU Extended Position-Based Dynamics (XPBD) particle and distance-constraint
    SSBOs and sub-stepped compute solver dispatches for cloth, foliage, and hair strands. }
  TCastleVulkanXPBDSimulator = class
  private
    FDevice: TVulkanRHIDevice;
    FParticleCount: Cardinal;
    FConstraintCount: Cardinal;
    FSubstepCount: Cardinal;
    FParticlePositionBuffer: TVulkanRHIBuffer;
    FPreviousPositionBuffer: TVulkanRHIBuffer;
    FConstraintBuffer: TVulkanRHIBuffer;
    FTotalSubstepsDispatched: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates the GPU particle position, previous-position, and constraint SSBOs. }
    procedure EnsureSimulationBuffers(
      const AParticleCount, AConstraintCount: Cardinal);

    { Dispatches FSubstepCount XPBD solver substeps on the GPU. }
    procedure DispatchXPBDSubsteps(
      const ACommandList: TVulkanRHICommandList;
      const AParticleCount, AConstraintCount: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property ParticleCount: Cardinal read FParticleCount;
    property ConstraintCount: Cardinal read FConstraintCount;
    property SubstepCount: Cardinal read FSubstepCount write FSubstepCount;
    property ParticlePositionBuffer: TVulkanRHIBuffer read FParticlePositionBuffer;
    property PreviousPositionBuffer: TVulkanRHIBuffer read FPreviousPositionBuffer;
    property ConstraintBuffer: TVulkanRHIBuffer read FConstraintBuffer;
    property TotalSubstepsDispatched: Cardinal read FTotalSubstepsDispatched;
  end;

  { -------------------------------------------------------------------------- }
  { Single-Pass Stereo VR (VK_KHR_multiview) & Foveated VRS Manager (Phase 37) }
  { -------------------------------------------------------------------------- }

  { Manages Single-Pass Stereo (VK_KHR_multiview, ViewMask = $3) 2-layer stereo
    color/depth array targets, IPD eye separation, and gaze-tracked radial foveated VRS. }
  TCastleVulkanMultiviewStereoManager = class
  private
    FDevice: TVulkanRHIDevice;
    FEyeWidth: Cardinal;
    FEyeHeight: Cardinal;
    FViewMask: Cardinal;
    FIPDMeters: Single;
    FLeftEyeGazeUV: TVector2;
    FRightEyeGazeUV: TVector2;
    FStereoColorArrayTexture: TVulkanRHITexture;
    FStereoDepthArrayTexture: TVulkanRHITexture;
    FStereoPassCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Allocates 2-layer stereo color (rgba16f) and depth (d32f) array textures for left/right eye views. }
    procedure EnsureStereoTargets(const AEyeWidth, AEyeHeight: Cardinal);

    { Begins a single-pass stereo multiview render pass (ViewMask = $3 for left+right eyes). }
    procedure BeginStereoMultiviewPass(
      const ACommandList: TVulkanRHICommandList;
      const AEyeWidth, AEyeHeight: Cardinal);

    { Ends the single-pass stereo multiview render pass. }
    procedure EndStereoMultiviewPass(const ACommandList: TVulkanRHICommandList);

    property EyeWidth: Cardinal read FEyeWidth;
    property EyeHeight: Cardinal read FEyeHeight;
    property ViewMask: Cardinal read FViewMask write FViewMask;
    property IPDMeters: Single read FIPDMeters write FIPDMeters;
    property LeftEyeGazeUV: TVector2 read FLeftEyeGazeUV write FLeftEyeGazeUV;
    property RightEyeGazeUV: TVector2 read FRightEyeGazeUV write FRightEyeGazeUV;
    property StereoColorArrayTexture: TVulkanRHITexture read FStereoColorArrayTexture;
    property StereoDepthArrayTexture: TVulkanRHITexture read FStereoDepthArrayTexture;
    property StereoPassCount: Cardinal read FStereoPassCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Per-Instance Custom Float4 Payload Manager (Phase 38.3)                }
  { -------------------------------------------------------------------------- }

  { Manages a GPU Storage Buffer (SSBO) storing arbitrary per-instance TVector4
    custom attributes (e.g. wind phase, team tint, dissolve/damage factor) indexed via gl_InstanceIndex. }
  TCastleVulkanPerInstanceCustomData = class
  private
    FDevice: TVulkanRHIDevice;
    FCustomDataEntries: array of TVector4;
    FInstanceCustomDataBuffer: TVulkanRHIBuffer;
    FUploadCount: Cardinal;
    function GetInstanceCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Clears all per-instance custom float4 payloads. }
    procedure ClearInstanceCustomData;

    { Sets the custom float4 payload for AInstanceIndex, growing the backing array as needed. }
    procedure SetInstanceCustomData(
      const AInstanceIndex: Cardinal;
      const ACustomPayload: TVector4);

    { Returns the custom float4 payload for AInstanceIndex (or Zero if out of range). }
    function GetInstanceCustomData(const AInstanceIndex: Cardinal): TVector4;

    { Allocates/updates the GPU SSBO containing all per-instance custom float4 payloads. }
    procedure UploadCustomDataBuffer;

    property InstanceCount: Cardinal read GetInstanceCount;
    property InstanceCustomDataBuffer: TVulkanRHIBuffer read FInstanceCustomDataBuffer;
    property UploadCount: Cardinal read FUploadCount;
  end;

  { -------------------------------------------------------------------------- }
  { Neural Radiance Cache & Cooperative Matrix MLP Denoiser (Phase 39.3)       }
  { -------------------------------------------------------------------------- }

  { Manages GPU MLP network weight SSBOs and compute inference dispatches for
    neural radiance caching and ray-reconstruction denoising. }
  TCastleVulkanNeuralDenoiser = class
  private
    FDevice: TVulkanRHIDevice;
    FWidth: Cardinal;
    FHeight: Cardinal;
    FHiddenUnits: Cardinal;
    FMLPWeightsBuffer: TVulkanRHIBuffer;
    FDenoisedOutputTexture: TVulkanRHITexture;
    FInferenceDispatchCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Evaluates a 4-input linear layer with ReLU activation: max(0.0, dot(input, weights) + bias). }
    class function EvaluateLinearReLU4(
      const AInput, AWeights: TVector4;
      const ABias: Single): Single; static;

    { Allocates the MLP network weights SSBO and the rgba16f denoised output texture. }
    procedure EnsureNeuralResources(const AWidth, AHeight: Cardinal);

    { Dispatches the neural MLP inference compute pass over (AWidth x AHeight) tiles. }
    procedure DispatchNeuralInference(
      const ACommandList: TVulkanRHICommandList;
      const AWidth, AHeight: Cardinal;
      const APipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property Width: Cardinal read FWidth;
    property Height: Cardinal read FHeight;
    property HiddenUnits: Cardinal read FHiddenUnits write FHiddenUnits;
    property MLPWeightsBuffer: TVulkanRHIBuffer read FMLPWeightsBuffer;
    property DenoisedOutputTexture: TVulkanRHITexture read FDenoisedOutputTexture;
    property InferenceDispatchCount: Cardinal read FInferenceDispatchCount;
  end;

  { -------------------------------------------------------------------------- }
  { Programmable MSAA Sample Locations Manager (Phase 40.3)                    }
  { -------------------------------------------------------------------------- }

  { Manages custom sub-pixel MSAA sample locations (VK_EXT_sample_locations)
    such as 4x Rotated Grid Super-Sampling (RGSS) and 2x/8x Halton patterns. }
  TCastleVulkanProgrammableSampleLocations = class
  private
    FDevice: TVulkanRHIDevice;
    FSampleLocations: array of TVector2;
    FLocationsAppliedCount: Cardinal;
    function GetSampleCount: Cardinal;
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { Configures standard Rotated Grid (RGSS 4x) or diagonal (2x) sub-pixel sample locations in [0..1)^2. }
    procedure ConfigureRotatedGridPattern(const ASampleCount: Cardinal = 4);

    { Returns the sub-pixel sample location [0..1)^2 for ASampleIndex. }
    function GetSampleLocation(const ASampleIndex: Cardinal): TVector2;

    { Applies the configured programmable MSAA sample locations on ACommandList (vkCmdSetSampleLocationsEXT). }
    procedure ApplySampleLocations(const ACommandList: TVulkanRHICommandList);

    property SampleCount: Cardinal read GetSampleCount;
    property LocationsAppliedCount: Cardinal read FLocationsAppliedCount;
  end;

  { -------------------------------------------------------------------------- }
  { GPU Parallel Prefix-Sum & Stream Compactor (Phase 41.3)                    }
  { -------------------------------------------------------------------------- }

  TCardinalDynamicArray = array of Cardinal;

  { Manages GPU parallel prefix-sum (Blelloch exclusive scan) and predicate stream
    compaction buffers for compacting surviving visible instances, meshlets, or rays. }
  TCastleVulkanStreamCompactor = class
  private
    FDevice: TVulkanRHIDevice;
    FMaxElementCount: Cardinal;
    FPrefixSumBuffer: TVulkanRHIBuffer;
    FCompactedIndicesBuffer: TVulkanRHIBuffer;
    FCompactedCountBuffer: TVulkanRHIBuffer;
    FCompactionComputePipeline: TVulkanRHIComputePipeline;
    FCompactionDispatchCount: Cardinal;
    procedure EnsureCompactionBuffers(const AElementCount: Cardinal);
  public
    constructor Create(const ADevice: TVulkanRHIDevice);
    destructor Destroy; override;

    { CPU reference: Computes exclusive prefix-sum offsets and compacts indices where APredicates[i] = True.
      Returns the total compacted count of surviving elements. }
    class function EvaluatePrefixSumAndCompact(
      const APredicates: array of Boolean;
      out AExclusivePrefixSum: TCardinalDynamicArray;
      out ACompactedIndices: TCardinalDynamicArray): Cardinal; static;

    { Dispatches the GPU prefix-sum and stream compaction compute pass across AElementCount elements. }
    procedure DispatchStreamCompaction(const ACommandList: TVulkanRHICommandList;
      const AElementCount: Cardinal;
      const AComputePipeline: TVulkanRHIComputePipeline = nil;
      const ADescriptorSet: TVulkanRHIDescriptorSet = nil);

    property MaxElementCount: Cardinal read FMaxElementCount;
    property PrefixSumBuffer: TVulkanRHIBuffer read FPrefixSumBuffer;
    property CompactedIndicesBuffer: TVulkanRHIBuffer read FCompactedIndicesBuffer;
    property CompactedCountBuffer: TVulkanRHIBuffer read FCompactedCountBuffer;
    property CompactionComputePipeline: TVulkanRHIComputePipeline
      read FCompactionComputePipeline write FCompactionComputePipeline;
    property CompactionDispatchCount: Cardinal read FCompactionDispatchCount;
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

  TVulkanRHIDevice = class(TRHIDevice)
  private
    FInstance: VkInstance;
    FDebugMessenger: VkDebugUtilsMessengerEXT;
    FSurface: VkSurfaceKHR;
    FPhysicalDevice: VkPhysicalDevice;
    FDevice: VkDevice;
    FDeviceId: Cardinal;
    FGraphicsQueue: VkQueue;
    FPresentQueue: VkQueue;
    FTransferQueue: VkQueue;
    FGraphicsQueueFamily: Cardinal;
    FPresentQueueFamily: Cardinal;
    FTransferQueueFamily: Cardinal;
    FHasDedicatedTransferQueue: Boolean;

    { Swapchain & MSAA state }
    FSwapchain: VkSwapchainKHR;
    FSwapchainFormat: TRHIPixelFormat;
    FSwapchainExtent: VkExtent2D;
    FSwapchainColorTextures: array of TVulkanRHITexture;
    FSwapchainDepthTexture: TVulkanRHITexture;
    FSwapchainMSAAColorTexture: TVulkanRHITexture;
    FSwapchainMSAADepthTexture: TVulkanRHITexture;
    FCurrentSwapchainImageIndex: Cardinal;
    FAntiAliasing: TAntiAliasing;
    FSampleCount: Cardinal;
    FActiveColorTarget: TRHITexture;
    FActiveDepthTarget: TRHITexture;

    { Frame synchronization, deferred resource retirement & command recording }
    FFrames: array[0 .. MaxFramesInFlight - 1] of TVulkanFrameContext;
    FDeferredDeletions: array[0 .. MaxFramesInFlight - 1] of array of TVulkanDeferredDeletionItem;
    FDeferResourceDestruction: Boolean;

    { GPU memory sub-allocator (pooled blocks + per-frame ring buffers), async staging uploader, bindless manager, timestamp profiler, compute culler, IBL generator, clustered culler, shadow atlas, HDR post-processor, GTAO, SSR, volumetric fog, TAA, reflection probes, decals, compute particles, OIT, contact shadows, compute skinner & CDLOD terrain }
    FMemoryAllocator: TCastleVulkanMemoryAllocator;
    FStagingUploader: TCastleVulkanStagingUploader;
    FBindlessTextureManager: TCastleVulkanBindlessTextureManager;
    FTimestampProfiler: TCastleVulkanTimestampProfiler;
    FComputeCuller: TCastleVulkanComputeCuller;
    FIBLGenerator: TCastleVulkanIBLGenerator;
    FClusteredLightCuller: TCastleVulkanClusteredLightCuller;
    FShadowAtlas: TCastleVulkanShadowAtlas;
    FHDRPostProcessor: TCastleVulkanHDRPostProcessor;
    FGTAO: TCastleVulkanGTAO;
    FSSR: TCastleVulkanSSR;
    FVolumetricFog: TCastleVulkanVolumetricFog;
    FTAA: TCastleVulkanTAA;
    FReflectionProbeManager: TCastleVulkanReflectionProbeManager;
    FDecalManager: TCastleVulkanDecalManager;
    FComputeParticles: TCastleVulkanComputeParticles;
    FWeightedBlendedOIT: TCastleVulkanWeightedBlendedOIT;
    FContactShadows: TCastleVulkanContactShadows;
    FComputeSkinner: TCastleVulkanComputeSkinner;
    FTerrainCDLOD: TCastleVulkanTerrainCDLOD;
    FAtmosphereRenderer: TCastleVulkanAtmosphereRenderer;
    FOceanSimulator: TCastleVulkanOceanSimulator;
    FDDGIGrid: TCastleVulkanDDGIGrid;
    FMeshletCuller: TCastleVulkanMeshletCuller;
    FVirtualShadowMap: TCastleVulkanVirtualShadowMap;
    FLODSelector: TCastleVulkanLODSelector;
    FTextureStreamer: TCastleVulkanTextureStreamer;
    FShadowCasterCuller: TCastleVulkanShadowCasterCuller;
    FClusterDAG: TCastleVulkanClusterDAG;
    FGlobalSDF: TCastleVulkanGlobalSDF;
    FSurfaceCache: TCastleVulkanSurfaceCache;
    FReSTIR: TCastleVulkanReSTIR;
    FTSRUpscaler: TCastleVulkanTSRUpscaler;
    FVRSManager: TCastleVulkanVRSManager;
    FRuntimeVirtualTexture: TCastleVulkanRuntimeVirtualTexture;
    FSparseVolumeAtlas: TCastleVulkanSparseVolumeAtlas;
    FBreadcrumbTracker: TCastleVulkanBreadcrumbTracker;
    FSVGFDenoiser: TCastleVulkanSVGFDenoiser;
    FShaderBindingTable: TCastleVulkanShaderBindingTable;
    FAccelerationStructureManager: TCastleVulkanAccelerationStructureManager;
    FXPBDSimulator: TCastleVulkanXPBDSimulator;
    FMultiviewStereoManager: TCastleVulkanMultiviewStereoManager;
    FPerInstanceCustomData: TCastleVulkanPerInstanceCustomData;
    FNeuralDenoiser: TCastleVulkanNeuralDenoiser;
    FProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations;
    FStreamCompactor: TCastleVulkanStreamCompactor;

    { Descriptor, Pipeline, Compute Pipeline, VK_EXT_graphics_pipeline_library & Vulkan 1.1 RenderPass/Framebuffer Caches }
    FPersistentDescriptorAllocator: TVulkanDescriptorPoolAllocator;
    FDescriptorPool: VkDescriptorPool;
    FPipelineCache: VkPipelineCache;
    FPipelineMap: TVulkanPipelineMap;
    FComputePipelineMap: TVulkanComputePipelineMap;
    FVertexInputLibMap: TVulkanPipelineLibraryMap;
    FPreRasterLibMap: TVulkanPipelineLibraryMap;
    FFragmentShaderLibMap: TVulkanPipelineLibraryMap;
    FFragmentOutputLibMap: TVulkanPipelineLibraryMap;
    FRenderPassMap: TVulkanRenderPassMap;
    FFramebufferMap: TVulkanFramebufferMap;
    FPipelineCacheLoaded: Boolean;
    FPrewarm3DVertexShader: TRHIShaderModule;
    FPrewarm3DFragmentShader: TRHIShaderModule;
    FPrewarm2DVertexShader: TRHIShaderModule;
    FPrewarm2DFragmentShader: TRHIShaderModule;

    { Diagnostics, VK_EXT_memory_budget, VK_EXT_graphics_pipeline_library, Bindless, Extended Dynamic State, Sync2 & Fallback tracking }
    FInstanceApiVersion: Cardinal;
    FDeviceApiVersion: Cardinal;
    FSupportsMemoryBudgetExt: Boolean;
    FSupportsDynamicRendering: Boolean;
    FSupportsGraphicsPipelineLibrary: Boolean;
    FSupportsGPLFastLinking: Boolean;
    FSupportsBindlessTextures: Boolean;
    FSupportsBindlessUpdateAfterBind: Boolean;
    FSupportsExtendedDynamicState: Boolean;
    FSupportsSynchronization2: Boolean;
    FSupportsTimelineSemaphores: Boolean;
    FMaxBindlessTextures: Cardinal;
    FPipelineCacheHits: Cardinal;
    FPipelineCacheMisses: Cardinal;
    FComputePipelineCacheHits: Cardinal;
    FComputePipelineCacheMisses: Cardinal;
    FGPLFastLinkedPipelineCount: Cardinal;
    FGPLLibraryCacheHits: Cardinal;
    FGPLLibraryCacheMisses: Cardinal;
    FDescriptorSetAllocations: Cardinal;
    FFallbackRenderPassBeginCount: Cardinal;
    FMSAAResolvePassCount: Cardinal;
    FComputeDispatchCount: Cardinal;
    FSync2BarrierCount: Cardinal;
    FAllocatedMemoryBytes: Int64;

    procedure CreateInstance(const EnableValidation: Boolean);
    procedure PickPhysicalDevice;
    procedure CreateLogicalDevice;
    procedure CreateSwapchain(const Width, Height: Cardinal);
    procedure DestroySwapchain;
    procedure EnsureMSAATargets(const AWidth, AHeight: Cardinal;
      const AColorFormat, ADepthFormat: TRHIPixelFormat);
    procedure CreateFrameContexts;
    procedure CreateDescriptorPool;
    procedure ClearPipelineLibraries;
    procedure ClearFallbackFramebuffers;
    procedure ClearFallbackRenderPasses;
    procedure SetAntiAliasing(const AValue: TAntiAliasing);
    procedure SetSampleCount(const AValue: Cardinal);
    procedure SetSupportsExtendedDynamicState(const AValue: Boolean);
    procedure SetSupportsSynchronization2(const AValue: Boolean);
    procedure SetSupportsTimelineSemaphores(const AValue: Boolean);
    function IsDeviceExtensionSupported(const AExtensionName: AnsiString): Boolean;
    function ComputePipelineHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
    function GetPipelineCount: Cardinal;
    function GetComputePipelineCount: Cardinal;
    function GetVertexInputLibraryCount: Cardinal;
    function GetPreRasterizationLibraryCount: Cardinal;
    function GetFragmentShaderLibraryCount: Cardinal;
    function GetFragmentOutputLibraryCount: Cardinal;
    function GetTotalPipelineLibraryCount: Cardinal;
    function GetFallbackRenderPassCount: Cardinal;
    function GetFallbackFramebufferCount: Cardinal;
    function GetPendingDeferredDeletionCount: Cardinal;
    function GetDescriptorPoolHandle: VkDescriptorPool;
    function GetComputeCuller: TCastleVulkanComputeCuller;
    function GetIBLGenerator: TCastleVulkanIBLGenerator;
    function GetClusteredLightCuller: TCastleVulkanClusteredLightCuller;
    function GetShadowAtlas: TCastleVulkanShadowAtlas;
    function GetHDRPostProcessor: TCastleVulkanHDRPostProcessor;
    function GetGTAO: TCastleVulkanGTAO;
    function GetSSR: TCastleVulkanSSR;
    function GetVolumetricFog: TCastleVulkanVolumetricFog;
    function GetTAA: TCastleVulkanTAA;
    function GetReflectionProbeManager: TCastleVulkanReflectionProbeManager;
    function GetDecalManager: TCastleVulkanDecalManager;
    function GetComputeParticles: TCastleVulkanComputeParticles;
    function GetWeightedBlendedOIT: TCastleVulkanWeightedBlendedOIT;
    function GetContactShadows: TCastleVulkanContactShadows;
    function GetComputeSkinner: TCastleVulkanComputeSkinner;
    function GetTerrainCDLOD: TCastleVulkanTerrainCDLOD;
    function GetAtmosphereRenderer: TCastleVulkanAtmosphereRenderer;
    function GetOceanSimulator: TCastleVulkanOceanSimulator;
    function GetDDGIGrid: TCastleVulkanDDGIGrid;
    function GetMeshletCuller: TCastleVulkanMeshletCuller;
    function GetVirtualShadowMap: TCastleVulkanVirtualShadowMap;
    function GetLODSelector: TCastleVulkanLODSelector;
    function GetTextureStreamer: TCastleVulkanTextureStreamer;
    function GetShadowCasterCuller: TCastleVulkanShadowCasterCuller;
    function GetClusterDAG: TCastleVulkanClusterDAG;
    function GetGlobalSDF: TCastleVulkanGlobalSDF;
    function GetSurfaceCache: TCastleVulkanSurfaceCache;
    function GetReSTIR: TCastleVulkanReSTIR;
    function GetTSRUpscaler: TCastleVulkanTSRUpscaler;
    function GetVRSManager: TCastleVulkanVRSManager;
    function GetRuntimeVirtualTexture: TCastleVulkanRuntimeVirtualTexture;
    function GetSparseVolumeAtlas: TCastleVulkanSparseVolumeAtlas;
    function GetBreadcrumbTracker: TCastleVulkanBreadcrumbTracker;
    function GetSVGFDenoiser: TCastleVulkanSVGFDenoiser;
    function GetShaderBindingTable: TCastleVulkanShaderBindingTable;
    function GetAccelerationStructureManager: TCastleVulkanAccelerationStructureManager;
    function GetXPBDSimulator: TCastleVulkanXPBDSimulator;
    function GetMultiviewStereoManager: TCastleVulkanMultiviewStereoManager;
    function GetPerInstanceCustomData: TCastleVulkanPerInstanceCustomData;
    function GetNeuralDenoiser: TCastleVulkanNeuralDenoiser;
    function GetProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations;
    function GetStreamCompactor: TCastleVulkanStreamCompactor;
  public
    constructor Create(const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
      const InitialWidth, InitialHeight: Cardinal;
      const EnableValidation: Boolean = True); reintroduce; overload;
    { Creates a headless Vulkan RHI device instance (for offscreen/unit testing). }
    constructor CreateHeadless(const APhysicalDevice: VkPhysicalDevice;
      const ASupportsMemoryBudgetExt: Boolean = True;
      const ASupportsDynamicRendering: Boolean = True;
      const ADeviceApiVersion: Cardinal = VK_API_VERSION_1_3;
      const ASupportsGraphicsPipelineLibrary: Boolean = False;
      const ASupportsBindlessTextures: Boolean = True;
      const AMaxBindlessTextures: Cardinal = 4096;
      const ASupportsExtendedDynamicState: Boolean = False); overload;
    destructor Destroy; override;

    { Helper for one-shot transfer commands (texture/buffer uploads) }
    function BeginSingleTimeCommands: VkCommandBuffer;
    procedure EndSingleTimeCommands(const CmdBuf: VkCommandBuffer);
    function FindMemoryType(const TypeFilter: Cardinal;
      const Properties: VkMemoryPropertyFlags): Cardinal;

    { Enqueues or immediately destroys a buffer/image/descriptor-set and its pooled memory sub-allocation.
      When DeferResourceDestruction is True (during in-flight frame rendering), resources
      are retired into FDeferredDeletions[FrameIndex] and freed only after that frame's
      VkFence signals completion. }
    procedure DeferOrDestroyBuffer(const ABuffer: VkBuffer;
      var AAllocation: TVulkanMemoryAllocation; const ADeviceMemory: VkDeviceMemory;
      const AAllocatedSize: VkDeviceSize);
    procedure DeferOrDestroyTexture(const AImage: VkImage; const AImageView: VkImageView;
      var AAllocation: TVulkanMemoryAllocation; const ADeviceMemory: VkDeviceMemory;
      const AAllocatedSize: VkDeviceSize);
    procedure DeferOrDestroyDescriptorSet(const AOwnerPool: VkDescriptorPool;
      const ASet: VkDescriptorSet);
    procedure FlushDeferredDeletions(const AFrameSlot: Integer);
    procedure FlushAllDeferredDeletions;
    function FlushStagingUploads(const ACommandList: TVulkanRHICommandList = nil): Cardinal;

    { Returns the per-frame transient descriptor pool allocator for AFrameIndex. }
    function GetTransientDescriptorAllocator(const AFrameIndex: Cardinal): TVulkanDescriptorPoolAllocator;

    { Allocates a frame-local transient descriptor set from the current frame's
      TransientDescriptorAllocator (bulk-reset in O(1) at the start of BeginFrame). }
    function CreateTransientDescriptorSet(
      const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet;

    { Builds a TRHIRenderingInfo for the swapchain (or an offscreen target), automatically
      attaching transient MSAA color/depth targets and single-pass ResolveTexture when SampleCount > 1. }
    function BuildSwapchainRenderingInfo(const ARenderArea: TRectangle;
      const AResolveColorTarget: TRHITexture;
      const AResolveDepthTarget: TRHITexture;
      const AClearColor: TCastleColor;
      const AColorLoadOp: TRHIAttachmentLoadOp = loClear;
      const ADepthLoadOp: TRHIAttachmentLoadOp = loClear;
      const AClearDepth: Single = 1.0): TRHIRenderingInfo;

    { Queries live GPU VRAM usage and budget via VK_EXT_memory_budget (or heap fallback).
      Returns True if VK_EXT_memory_budget was used. }
    function QueryMemoryBudget(out AUsedBytes, ABudgetBytes: UInt64;
      out AUsedMB, ABudgetMB: Cardinal): Boolean;

    { Records diagnostic counters for testing or custom pass tracking. }
    procedure RecordDiagnostics(const APipelineHits, APipelineMisses,
      ADescriptorAllocs: Cardinal; const AAllocatedBytes: UInt64 = 0);

    { Pre-warms standard 3D/2D graphics pipeline state objects (PSOs) and loads/saves
      the Vulkan pipeline cache (DefaultVulkanPipelineCacheUrl) so PSOs are baked
      before the first rendered frame. Returns total cached pipeline count. }
    function PrewarmStandardPipelines(const AIncludeBlending: Boolean = True;
      const AIncludeShadowDepth: Boolean = True;
      const ACacheFileUrl: String = ''): Cardinal;

    { Acquires or creates a cached VK_GRAPHICS_PIPELINE_LIBRARY_VERTEX_INPUT_INTERFACE_BIT_EXT library. }
    function GetOrCreateVertexInputLibrary(
      const ADesc: TRHIGraphicsPipelineDesc): VkPipeline;

    { Acquires or creates a cached VK_GRAPHICS_PIPELINE_LIBRARY_PRE_RASTERIZATION_SHADERS_BIT_EXT library. }
    function GetOrCreatePreRasterizationLibrary(
      const ADesc: TRHIGraphicsPipelineDesc;
      const ALayout: VkPipelineLayout;
      const ARenderPass: VkRenderPass): VkPipeline;

    { Acquires or creates a cached VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_SHADER_BIT_EXT library. }
    function GetOrCreateFragmentShaderLibrary(
      const ADesc: TRHIGraphicsPipelineDesc;
      const ALayout: VkPipelineLayout;
      const ARenderPass: VkRenderPass): VkPipeline;

    { Acquires or creates a cached VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_OUTPUT_INTERFACE_BIT_EXT library. }
    function GetOrCreateFragmentOutputLibrary(
      const ADesc: TRHIGraphicsPipelineDesc;
      const ARenderPass: VkRenderPass): VkPipeline;

    { Acquires or creates a cached VkRenderPass for Vulkan 1.1/1.2 devices that lack
      VK_KHR_dynamic_rendering. Supports explicit LoadOp/StoreOp for multi-pass rendering
      and single-pass MSAA resolve attachments (pResolveAttachments) when AHasColorResolve = True. }
    function GetOrCreateFallbackRenderPass(
      const AColorFormats: array of TRHIPixelFormat;
      const ADepthFormat: TRHIPixelFormat;
      const ASampleCount: Cardinal = 1;
      const AColorLoadOp: TRHIAttachmentLoadOp = loClear;
      const ADepthLoadOp: TRHIAttachmentLoadOp = loClear;
      const AColorStoreOp: TRHIAttachmentStoreOp = soStore;
      const ADepthStoreOp: TRHIAttachmentStoreOp = soStore;
      const AHasColorResolve: Boolean = False): VkRenderPass;

    { Acquires or creates a cached VkFramebuffer for Vulkan 1.1/1.2 devices that lack
      VK_KHR_dynamic_rendering. }
    function GetOrCreateFallbackFramebuffer(const ARenderPass: VkRenderPass;
      const AAttachments: array of VkImageView;
      const AWidth, AHeight: Cardinal): VkFramebuffer;

    { TRHIDevice overrides }
    function BeginFrame: TRHICommandList; override;
    procedure EndFrameAndPresent; override;
    procedure ResizeSwapchain(const NewWidth, NewHeight: Cardinal); override;
    procedure WaitIdle; override;
    function CreateSecondaryCommandList: TRHICommandList; override;

    function GetSwapchainColorTexture: TRHITexture; override;
    function GetSwapchainDepthTexture: TRHITexture; override;

    function CreateBuffer(const ADesc: TRHIBufferDesc;
      const InitialData: Pointer = nil): TRHIBuffer; override;
    function CreateTexture(const ADesc: TRHITextureDesc): TRHITexture; override;
    function CreateSampler(const ADesc: TRHISamplerDesc): TRHISampler; override;

    function CreateShaderModuleFromGLSL(const AStage: TRHIShaderStage;
      const AGLSLSource: String; const ADebugName: String = ''): TRHIShaderModule; override;
    function CreateShaderModuleFromSPIRV(const AStage: TRHIShaderStage;
      const ASPIRVBinary: Pointer; const ASizeInBytes: PtrUInt;
      const ADebugName: String = ''): TRHIShaderModule; override;

    function CreateDescriptorSetLayout(
      const Bindings: array of TRHIDescriptorBindingDesc): TRHIDescriptorSetLayout; override;
    function CreateDescriptorSet(
      const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet; override;

    function GetOrCreatePipeline(const ADesc: TRHIGraphicsPipelineDesc): TRHIPipeline; override;
    function GetOrCreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline;
    function CreateComputePipeline(const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline; override;
    function CreateQueryPool(const ADesc: TRHIQueryPoolDesc): TRHIQueryPool; override;
    function CreateTimelineSemaphore(const AInitialValue: UInt64 = 0): TCastleVulkanTimelineSemaphore;

    function GrabTextureImage(const SourceTexture: TRHITexture;
      const ReadArea: TRectangle): TRGBAlphaImage; overload; override;

    procedure LoadPipelineCache(const CacheFileUrl: String); override;
    procedure SavePipelineCache(const CacheFileUrl: String); override;

    function GetInformationString: String; override;
    function GetInformationStringSummary: String; override;

    property Handle: VkDevice read FDevice;
    property PhysicalDevice: VkPhysicalDevice read FPhysicalDevice;
    property InstanceApiVersion: Cardinal read FInstanceApiVersion;
    property DeviceApiVersion: Cardinal read FDeviceApiVersion write FDeviceApiVersion;
    property AntiAliasing: TAntiAliasing read FAntiAliasing write SetAntiAliasing;
    property SampleCount: Cardinal read FSampleCount write SetSampleCount;
    property ActiveColorTarget: TRHITexture read FActiveColorTarget write FActiveColorTarget;
    property ActiveDepthTarget: TRHITexture read FActiveDepthTarget write FActiveDepthTarget;
    property SwapchainMSAAColorTexture: TVulkanRHITexture read FSwapchainMSAAColorTexture;
    property SwapchainMSAADepthTexture: TVulkanRHITexture read FSwapchainMSAADepthTexture;
    property MSAAResolvePassCount: Cardinal read FMSAAResolvePassCount;
    property DescriptorPool: VkDescriptorPool read GetDescriptorPoolHandle;
    property PersistentDescriptorAllocator: TVulkanDescriptorPoolAllocator read FPersistentDescriptorAllocator;
    property PipelineCache: VkPipelineCache read FPipelineCache;
    property PipelineCount: Cardinal read GetPipelineCount;
    property ComputePipelineCount: Cardinal read GetComputePipelineCount;
    property PipelineCacheLoaded: Boolean read FPipelineCacheLoaded;
    property SupportsMemoryBudgetExt: Boolean read FSupportsMemoryBudgetExt;
    property SupportsDynamicRendering: Boolean read FSupportsDynamicRendering write FSupportsDynamicRendering;
    property SupportsGraphicsPipelineLibrary: Boolean read FSupportsGraphicsPipelineLibrary write FSupportsGraphicsPipelineLibrary;
    property SupportsGPLFastLinking: Boolean read FSupportsGPLFastLinking write FSupportsGPLFastLinking;
    property SupportsBindlessTextures: Boolean read FSupportsBindlessTextures write FSupportsBindlessTextures;
    property SupportsBindlessUpdateAfterBind: Boolean read FSupportsBindlessUpdateAfterBind write FSupportsBindlessUpdateAfterBind;
    property SupportsExtendedDynamicState: Boolean read FSupportsExtendedDynamicState write SetSupportsExtendedDynamicState;
    property SupportsSynchronization2: Boolean read FSupportsSynchronization2 write SetSupportsSynchronization2;
    property SupportsTimelineSemaphores: Boolean read FSupportsTimelineSemaphores write SetSupportsTimelineSemaphores;
    property MaxBindlessTextures: Cardinal read FMaxBindlessTextures write FMaxBindlessTextures;
    property BindlessTextureManager: TCastleVulkanBindlessTextureManager read FBindlessTextureManager;
    property TimestampProfiler: TCastleVulkanTimestampProfiler read FTimestampProfiler;
    property ComputeCuller: TCastleVulkanComputeCuller read GetComputeCuller;
    property IBLGenerator: TCastleVulkanIBLGenerator read GetIBLGenerator;
    property ClusteredLightCuller: TCastleVulkanClusteredLightCuller read GetClusteredLightCuller;
    property ShadowAtlas: TCastleVulkanShadowAtlas read GetShadowAtlas;
    property HDRPostProcessor: TCastleVulkanHDRPostProcessor read GetHDRPostProcessor;
    property GTAO: TCastleVulkanGTAO read GetGTAO;
    property SSR: TCastleVulkanSSR read GetSSR;
    property VolumetricFog: TCastleVulkanVolumetricFog read GetVolumetricFog;
    property TAA: TCastleVulkanTAA read GetTAA;
    property ReflectionProbeManager: TCastleVulkanReflectionProbeManager read GetReflectionProbeManager;
    property DecalManager: TCastleVulkanDecalManager read GetDecalManager;
    property ComputeParticles: TCastleVulkanComputeParticles read GetComputeParticles;
    property WeightedBlendedOIT: TCastleVulkanWeightedBlendedOIT read GetWeightedBlendedOIT;
    property ContactShadows: TCastleVulkanContactShadows read GetContactShadows;
    property ComputeSkinner: TCastleVulkanComputeSkinner read GetComputeSkinner;
    property TerrainCDLOD: TCastleVulkanTerrainCDLOD read GetTerrainCDLOD;
    property AtmosphereRenderer: TCastleVulkanAtmosphereRenderer read GetAtmosphereRenderer;
    property OceanSimulator: TCastleVulkanOceanSimulator read GetOceanSimulator;
    property DDGIGrid: TCastleVulkanDDGIGrid read GetDDGIGrid;
    property MeshletCuller: TCastleVulkanMeshletCuller read GetMeshletCuller;
    property VirtualShadowMap: TCastleVulkanVirtualShadowMap read GetVirtualShadowMap;
    property LODSelector: TCastleVulkanLODSelector read GetLODSelector;
    property TextureStreamer: TCastleVulkanTextureStreamer read GetTextureStreamer;
    property ShadowCasterCuller: TCastleVulkanShadowCasterCuller read GetShadowCasterCuller;
    property ClusterDAG: TCastleVulkanClusterDAG read GetClusterDAG;
    property GlobalSDF: TCastleVulkanGlobalSDF read GetGlobalSDF;
    property SurfaceCache: TCastleVulkanSurfaceCache read GetSurfaceCache;
    property ReSTIR: TCastleVulkanReSTIR read GetReSTIR;
    property TSRUpscaler: TCastleVulkanTSRUpscaler read GetTSRUpscaler;
    property VRSManager: TCastleVulkanVRSManager read GetVRSManager;
    property RuntimeVirtualTexture: TCastleVulkanRuntimeVirtualTexture read GetRuntimeVirtualTexture;
    property SparseVolumeAtlas: TCastleVulkanSparseVolumeAtlas read GetSparseVolumeAtlas;
    property BreadcrumbTracker: TCastleVulkanBreadcrumbTracker read GetBreadcrumbTracker;
    property SVGFDenoiser: TCastleVulkanSVGFDenoiser read GetSVGFDenoiser;
    property ShaderBindingTable: TCastleVulkanShaderBindingTable read GetShaderBindingTable;
    property AccelerationStructureManager: TCastleVulkanAccelerationStructureManager read GetAccelerationStructureManager;
    property XPBDSimulator: TCastleVulkanXPBDSimulator read GetXPBDSimulator;
    property MultiviewStereoManager: TCastleVulkanMultiviewStereoManager read GetMultiviewStereoManager;
    property PerInstanceCustomData: TCastleVulkanPerInstanceCustomData read GetPerInstanceCustomData;
    property NeuralDenoiser: TCastleVulkanNeuralDenoiser read GetNeuralDenoiser;
    property ProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations read GetProgrammableSampleLocations;
    property StreamCompactor: TCastleVulkanStreamCompactor read GetStreamCompactor;
    property VertexInputLibraryCount: Cardinal read GetVertexInputLibraryCount;
    property PreRasterizationLibraryCount: Cardinal read GetPreRasterizationLibraryCount;
    property FragmentShaderLibraryCount: Cardinal read GetFragmentShaderLibraryCount;
    property FragmentOutputLibraryCount: Cardinal read GetFragmentOutputLibraryCount;
    property TotalPipelineLibraryCount: Cardinal read GetTotalPipelineLibraryCount;
    property GPLFastLinkedPipelineCount: Cardinal read FGPLFastLinkedPipelineCount;
    property GPLLibraryCacheHits: Cardinal read FGPLLibraryCacheHits;
    property GPLLibraryCacheMisses: Cardinal read FGPLLibraryCacheMisses;
    property FallbackRenderPassCount: Cardinal read GetFallbackRenderPassCount;
    property FallbackFramebufferCount: Cardinal read GetFallbackFramebufferCount;
    property FallbackRenderPassBeginCount: Cardinal read FFallbackRenderPassBeginCount;
    property PipelineCacheHits: Cardinal read FPipelineCacheHits;
    property PipelineCacheMisses: Cardinal read FPipelineCacheMisses;
    property ComputePipelineCacheHits: Cardinal read FComputePipelineCacheHits;
    property ComputePipelineCacheMisses: Cardinal read FComputePipelineCacheMisses;
    property ComputeDispatchCount: Cardinal read FComputeDispatchCount;
    property Sync2BarrierCount: Cardinal read FSync2BarrierCount;
    property DescriptorSetAllocations: Cardinal read FDescriptorSetAllocations;
    property AllocatedMemoryBytes: Int64 read FAllocatedMemoryBytes;
    property MemoryAllocator: TCastleVulkanMemoryAllocator read FMemoryAllocator;
    property StagingUploader: TCastleVulkanStagingUploader read FStagingUploader;
    property GraphicsQueueFamily: Cardinal read FGraphicsQueueFamily;
    property TransferQueueFamily: Cardinal read FTransferQueueFamily;
    property HasDedicatedTransferQueue: Boolean read FHasDedicatedTransferQueue;
    property DeferResourceDestruction: Boolean read FDeferResourceDestruction write FDeferResourceDestruction;
    property PendingDeferredDeletionCount: Cardinal read GetPendingDeferredDeletionCount;
    property FrameIndex: Cardinal read FFrameIndex write FFrameIndex;
  end;

{ Selects the optimal transfer queue family index from AQueueFamilies:
  1. Prefers a dedicated DMA transfer queue family (VK_QUEUE_TRANSFER_BIT without
     VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT, e.g. AMD SDMA / NVIDIA Copy Engine).
  2. Falls back to an async compute+transfer queue family distinct from AGraphicsQueueFamily.
  3. Falls back to AGraphicsQueueFamily (AIsDedicatedTransferQueue = False). }
function SelectTransferQueueFamilyIndex(
  const AQueueFamilies: array of VkQueueFamilyProperties;
  const AGraphicsQueueFamily: Cardinal;
  out AIsDedicatedTransferQueue: Boolean): Cardinal;

{ Returns the highest power-of-two MSAA sample count (64, 32, 16, 8, 4, 2, 1)
  supported simultaneously by both color and depth framebuffer sample count masks. }
function ResolveMaxFramebufferSampleCount(
  const AColorSampleCounts, ADepthSampleCounts: VkSampleCountFlags): Cardinal;

{ Clamps ARequestedSamples down to the highest sample count bit present in ASupportedMask. }
function ClampSampleCountToMask(const ARequestedSamples: Cardinal;
  const ASupportedMask: VkSampleCountFlags): Cardinal;

{ Converts a numeric sample count (1, 2, 4, 8, 16, 32, 64) to VkSampleCountFlagBits. }
function RHIToVkSampleCountFlags(const ASampleCount: Cardinal): VkSampleCountFlags;

{ Converts TRHIResolveMode to VkResolveModeFlagBits. }
function RHIToVkResolveMode(const AResolveMode: TRHIResolveMode): Integer;

{ Converts TRHIStencilOp to VkStencilOp. }
function RHIToVkStencilOp(const AOp: TRHIStencilOp): Integer;

{ Converts TRHIStencilOpStateDesc to VkStencilOpState. }
function RHIToVkStencilOpState(const AState: TRHIStencilOpStateDesc): VkStencilOpState;

{ Returns the required VkFormatFeatureFlagBits for a given TRHIPixelFormat and TRHITextureUsageFlags set. }
function GetRequiredVkFormatFeatures(const AFormat: TRHIPixelFormat;
  const AUsage: TRHITextureUsageFlags): VkFlags;

{ Returns the VkImageAspectFlags required for VkImageMemoryBarrier layout transitions
  (includes both DEPTH and STENCIL bits for combined depth-stencil formats per
  VUID-VkImageMemoryBarrier-subresourceRange-09601). }
function GetFormatTransitionAspectMask(const AFormat: TRHIPixelFormat): VkImageAspectFlags;

{ Returns the VkImageAspectFlags required for VkImageView creation
  (restricts combined depth-stencil formats to VK_IMAGE_ASPECT_DEPTH_BIT when
  tuSampled is in AUsage per VUID-VkDescriptorImageInfo-imageView-01976). }
function GetFormatViewAspectMask(const AFormat: TRHIPixelFormat;
  const AUsage: TRHITextureUsageFlags): VkImageAspectFlags;

{ Negotiates a supported TRHIPixelFormat on APhysicalDevice via vkGetPhysicalDeviceFormatProperties,
  automatically falling back across vendor differences (e.g. D24_UNorm_S8_UInt -> D32_Float_S8_UInt
  -> D32_Float -> D16_UNorm on AMD/MoltenVK, or unsupported BC/ASTC/ETC2 -> RGBA8). }
function NegotiateOptimalPixelFormat(const ARequestedFormat: TRHIPixelFormat;
  const AUsage: TRHITextureUsageFlags;
  const APhysicalDevice: VkPhysicalDevice = nil): TRHIPixelFormat;

{ Negotiates the highest supported VkApplicationInfo.apiVersion (1.3, 1.2, 1.1, or 1.0)
  for a given loader version reported by vkEnumerateInstanceVersion. }
function NegotiateInstanceApiVersion(const ALoaderVersion: Cardinal): Cardinal;

{ Resolves whether a Vulkan 1.1, 1.2, or 1.3+ physical device can use dynamic rendering
  (and which KHR prerequisite extensions must be enabled on VkDeviceCreateInfo) or should
  fall back to standard Vulkan 1.1 VkRenderPass + VkFramebuffer passes. }
procedure ResolveVulkan11_12DeviceConfig(const ADeviceApiVersion: Cardinal;
  const AHasDynamicRenderingExt, AHasDepthStencilResolveExt, AHasCreateRenderPass2Ext: Boolean;
  out AUseDynamicRendering: Boolean; out ARequiredExtensions: TAnsiStringArray);

{ Resolves whether a Vulkan physical device can use VK_EXT_graphics_pipeline_library
  (requiring VK_KHR_pipeline_library, VK_EXT_graphics_pipeline_library, and the
  graphicsPipelineLibrary feature) and returns the required device extensions. }
procedure ResolveGraphicsPipelineLibraryConfig(const ADeviceApiVersion: Cardinal;
  const AHasPipelineLibraryExt, AHasGraphicsPipelineLibraryExt, AHasGPLFeature: Boolean;
  out AUseGPL: Boolean; out ARequiredExtensions: TAnsiStringArray);

{ Resolves whether a Vulkan physical device supports bindless texture & sampler indexing
  via Vulkan 1.2+ core or Vulkan 1.1 + VK_EXT_descriptor_indexing (+ VK_KHR_maintenance3),
  validating shaderSampledImageArrayNonUniformIndexing, descriptorBindingPartiallyBound,
  descriptorBindingUpdateUnusedWhilePending, and runtimeDescriptorArray, and clamping
  MaxBindlessTextures to hardware descriptor limits. }
procedure ResolveDescriptorIndexingConfig(const ADeviceApiVersion: Cardinal;
  const AHasDescriptorIndexingExt, AHasMaintenance3Ext: Boolean;
  const AFeatures: VkPhysicalDeviceDescriptorIndexingFeatures;
  const AProps: VkPhysicalDeviceDescriptorIndexingProperties;
  const ARequestedMaxTextures: Cardinal;
  out AUseBindless, AUseUpdateAfterBind: Boolean;
  out AClampedMaxTextures: Cardinal;
  out ARequiredExtensions: TAnsiStringArray);

{ Resolves whether a Vulkan 1.1, 1.2, or 1.3+ physical device supports Extended Dynamic State,
  Synchronization2 (vkCmdPipelineBarrier2), and Timeline Semaphores (64-bit counters),
  and returns any extension strings required for pre-1.3 / pre-1.2 devices. }
procedure ResolveExtendedDynamicStateAndSync2Config(const ADeviceApiVersion: Cardinal;
  const AHasExtDynStateExt, AHasSync2Ext, AHasTimelineSemExt: Boolean;
  const AExtDynStateFeature, ASync2Feature, ATimelineSemFeature: Boolean;
  out AUseExtDynState, AUseSync2, AUseTimelineSem: Boolean;
  out ARequiredExtensions: TAnsiStringArray);

{ Computes a deterministic 64-bit FNV-1a hash for a graphics pipeline state descriptor.
  When AIgnoreExtendedDynamicStates = True (VK_EXT_extended_dynamic_state / Vulkan 1.3),
  CullMode, FrontFace, Topology, DepthTestEnable, DepthWriteEnable, and DepthCompareOp
  are excluded from the hash so pipelines differing only in dynamic states share a single PSO. }
function ComputePipelineKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
function ComputePipelineKeyHashEx(const ADesc: TRHIGraphicsPipelineDesc;
  const AIgnoreExtendedDynamicStates: Boolean): UInt64;

{ Computes a deterministic 64-bit FNV-1a hash for a compute pipeline state descriptor. }
function ComputeComputePipelineKeyHash(const ADesc: TRHIComputePipelineDesc): UInt64;

{ Computes deterministic 64-bit FNV-1a hashes for the 4 VK_EXT_graphics_pipeline_library subsets. }
function ComputeVertexInputLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
function ComputePreRasterizationLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
function ComputeFragmentShaderLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
function ComputeFragmentOutputLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;

{ Computes a deterministic 64-bit FNV-1a hash for a fallback VkRenderPass signature. }
function ComputeRenderPassKeyHash(const AColorFormats: array of TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat; const ASampleCount: Cardinal = 1;
  const AColorLoadOp: TRHIAttachmentLoadOp = loClear;
  const ADepthLoadOp: TRHIAttachmentLoadOp = loClear;
  const AColorStoreOp: TRHIAttachmentStoreOp = soStore;
  const ADepthStoreOp: TRHIAttachmentStoreOp = soStore;
  const AHasColorResolve: Boolean = False): UInt64;

{ Computes a deterministic 64-bit FNV-1a hash for a fallback VkFramebuffer signature. }
function ComputeFramebufferKeyHash(const ARenderPass: VkRenderPass;
  const AAttachments: array of VkImageView; const AWidth, AHeight: Cardinal): UInt64;

const
  DefaultVulkanPipelineCacheUrl = 'castle-config:/vulkan_pipeline_cache.bin';
  PipelineCacheDiskMagic = $43474550; // 'CGEP'
  PipelineCacheDiskVersion = 1;

type
  { Header stored on disk before raw VkPipelineCache data to validate hardware compatibility. }
  TPipelineCacheDiskHeader = packed record
    Magic: Cardinal;
    Version: Cardinal;
    VendorId: Cardinal;
    DeviceId: Cardinal;
    DataSize: Cardinal;
    DataHash: UInt64;
  end;

{ Writes a hardware-tagged VkPipelineCache binary blob to a stream. }
procedure SavePipelineCacheBlobToStream(const AStream: TStream;
  const AVendorId, ADeviceId: Cardinal; const AData: Pointer; const ASize: PtrUInt);

{ Reads and validates a hardware-tagged VkPipelineCache binary blob from a stream.
  Returns False if the stream is corrupt, empty, or belongs to a different GPU vendor/device. }
function LoadPipelineCacheBlobFromStream(const AStream: TStream;
  const AExpectedVendorId, AExpectedDeviceId: Cardinal; out ABlob: TBytes): Boolean;

implementation

uses
  CastleDownload;

const
  FNV1aOffsetBasis64 = UInt64($CBF29CE484222325);
  FNV1aPrime64 = UInt64($00000100000001B3);

function NegotiateInstanceApiVersion(const ALoaderVersion: Cardinal): Cardinal;
begin
  if ALoaderVersion >= VK_API_VERSION_1_3 then
    Result := VK_API_VERSION_1_3
  else
  if ALoaderVersion >= VK_API_VERSION_1_2 then
    Result := VK_API_VERSION_1_2
  else
  if ALoaderVersion >= VK_API_VERSION_1_1 then
    Result := VK_API_VERSION_1_1
  else
    Result := VK_API_VERSION_1_0;
end;

function SelectTransferQueueFamilyIndex(
  const AQueueFamilies: array of VkQueueFamilyProperties;
  const AGraphicsQueueFamily: Cardinal;
  out AIsDedicatedTransferQueue: Boolean): Cardinal;
var
  I: Integer;
  Flags: VkQueueFlags;
begin
  Result := AGraphicsQueueFamily;
  AIsDedicatedTransferQueue := False;

  { 1. First pass: pure DMA transfer queue family (TRANSFER without GRAPHICS or COMPUTE) }
  for I := 0 to High(AQueueFamilies) do
  begin
    Flags := AQueueFamilies[I].queueFlags;
    if (AQueueFamilies[I].queueCount > 0) and
       ((Flags and VK_QUEUE_TRANSFER_BIT) <> 0) and
       ((Flags and VK_QUEUE_GRAPHICS_BIT) = 0) and
       ((Flags and VK_QUEUE_COMPUTE_BIT) = 0) and
       (Cardinal(I) <> AGraphicsQueueFamily) then
    begin
      AIsDedicatedTransferQueue := True;
      Exit(Cardinal(I));
    end;
  end;

  { 2. Second pass: async compute+transfer queue family (TRANSFER without GRAPHICS) }
  for I := 0 to High(AQueueFamilies) do
  begin
    Flags := AQueueFamilies[I].queueFlags;
    if (AQueueFamilies[I].queueCount > 0) and
       ((Flags and VK_QUEUE_TRANSFER_BIT) <> 0) and
       ((Flags and VK_QUEUE_GRAPHICS_BIT) = 0) and
       (Cardinal(I) <> AGraphicsQueueFamily) then
    begin
      AIsDedicatedTransferQueue := True;
      Exit(Cardinal(I));
    end;
  end;
end;

function ResolveMaxFramebufferSampleCount(
  const AColorSampleCounts, ADepthSampleCounts: VkSampleCountFlags): Cardinal;
var
  CommonMask: VkSampleCountFlags;
begin
  CommonMask := AColorSampleCounts and ADepthSampleCounts;
  if (CommonMask and VK_SAMPLE_COUNT_64_BIT) <> 0 then Exit(64);
  if (CommonMask and VK_SAMPLE_COUNT_32_BIT) <> 0 then Exit(32);
  if (CommonMask and VK_SAMPLE_COUNT_16_BIT) <> 0 then Exit(16);
  if (CommonMask and VK_SAMPLE_COUNT_8_BIT) <> 0 then Exit(8);
  if (CommonMask and VK_SAMPLE_COUNT_4_BIT) <> 0 then Exit(4);
  if (CommonMask and VK_SAMPLE_COUNT_2_BIT) <> 0 then Exit(2);
  Result := 1;
end;

function ClampSampleCountToMask(const ARequestedSamples: Cardinal;
  const ASupportedMask: VkSampleCountFlags): Cardinal;
const
  PowerOfTwoSamples: array[0..5] of Cardinal = (64, 32, 16, 8, 4, 2);
var
  I: Integer;
begin
  if ARequestedSamples <= 1 then
    Exit(1);
  for I := Low(PowerOfTwoSamples) to High(PowerOfTwoSamples) do
    if (PowerOfTwoSamples[I] <= ARequestedSamples) and
       ((ASupportedMask and PowerOfTwoSamples[I]) <> 0) then
      Exit(PowerOfTwoSamples[I]);
  Result := 1;
end;

function RHIToVkSampleCountFlags(const ASampleCount: Cardinal): VkSampleCountFlags;
begin
  if ASampleCount >= 64 then Result := VK_SAMPLE_COUNT_64_BIT
  else if ASampleCount >= 32 then Result := VK_SAMPLE_COUNT_32_BIT
  else if ASampleCount >= 16 then Result := VK_SAMPLE_COUNT_16_BIT
  else if ASampleCount >= 8 then Result := VK_SAMPLE_COUNT_8_BIT
  else if ASampleCount >= 4 then Result := VK_SAMPLE_COUNT_4_BIT
  else if ASampleCount >= 2 then Result := VK_SAMPLE_COUNT_2_BIT
  else Result := VK_SAMPLE_COUNT_1_BIT;
end;

function RHIToVkResolveMode(const AResolveMode: TRHIResolveMode): Integer;
begin
  case AResolveMode of
    rmNone:       Result := VK_RESOLVE_MODE_NONE;
    rmAverage:    Result := VK_RESOLVE_MODE_AVERAGE_BIT;
    rmSampleZero: Result := VK_RESOLVE_MODE_SAMPLE_ZERO_BIT;
    rmMin:        Result := VK_RESOLVE_MODE_MIN_BIT;
    rmMax:        Result := VK_RESOLVE_MODE_MAX_BIT;
    else          Result := VK_RESOLVE_MODE_AVERAGE_BIT;
  end;
end;

procedure ResolveVulkan11_12DeviceConfig(const ADeviceApiVersion: Cardinal;
  const AHasDynamicRenderingExt, AHasDepthStencilResolveExt, AHasCreateRenderPass2Ext: Boolean;
  out AUseDynamicRendering: Boolean; out ARequiredExtensions: TAnsiStringArray);
begin
  SetLength(ARequiredExtensions, 0);
  if ADeviceApiVersion >= VK_API_VERSION_1_3 then
  begin
    { Vulkan 1.3+: Dynamic Rendering is core }
    AUseDynamicRendering := True;
  end else
  if ADeviceApiVersion >= VK_API_VERSION_1_2 then
  begin
    { Vulkan 1.2: VK_KHR_depth_stencil_resolve and VK_KHR_create_renderpass2 are core 1.2;
      only VK_KHR_dynamic_rendering extension is required if supported }
    if AHasDynamicRenderingExt then
    begin
      AUseDynamicRendering := True;
      SetLength(ARequiredExtensions, 1);
      ARequiredExtensions[0] := VK_KHR_dynamic_rendering;
    end else
      AUseDynamicRendering := False;
  end else
  if ADeviceApiVersion >= VK_API_VERSION_1_1 then
  begin
    { Vulkan 1.1: VK_KHR_multiview and VK_KHR_maintenance2 are core 1.1,
      while VK_KHR_dynamic_rendering requires VK_KHR_create_renderpass2 and VK_KHR_depth_stencil_resolve }
    if AHasDynamicRenderingExt and AHasDepthStencilResolveExt and AHasCreateRenderPass2Ext then
    begin
      AUseDynamicRendering := True;
      SetLength(ARequiredExtensions, 3);
      ARequiredExtensions[0] := VK_KHR_create_renderpass2;
      ARequiredExtensions[1] := VK_KHR_depth_stencil_resolve;
      ARequiredExtensions[2] := VK_KHR_dynamic_rendering;
    end else
      AUseDynamicRendering := False;
  end else
  begin
    { Pre-Vulkan 1.1 device: use standard VkRenderPass / VkFramebuffer fallback }
    AUseDynamicRendering := False;
  end;
end;

procedure ResolveGraphicsPipelineLibraryConfig(const ADeviceApiVersion: Cardinal;
  const AHasPipelineLibraryExt, AHasGraphicsPipelineLibraryExt, AHasGPLFeature: Boolean;
  out AUseGPL: Boolean; out ARequiredExtensions: TAnsiStringArray);
begin
  SetLength(ARequiredExtensions, 0);
  if (ADeviceApiVersion >= VK_API_VERSION_1_1) and
     AHasPipelineLibraryExt and
     AHasGraphicsPipelineLibraryExt and
     AHasGPLFeature then
  begin
    AUseGPL := True;
    SetLength(ARequiredExtensions, 2);
    ARequiredExtensions[0] := VK_KHR_pipeline_library;
    ARequiredExtensions[1] := VK_EXT_graphics_pipeline_library;
  end else
    AUseGPL := False;
end;

procedure ResolveDescriptorIndexingConfig(const ADeviceApiVersion: Cardinal;
  const AHasDescriptorIndexingExt, AHasMaintenance3Ext: Boolean;
  const AFeatures: VkPhysicalDeviceDescriptorIndexingFeatures;
  const AProps: VkPhysicalDeviceDescriptorIndexingProperties;
  const ARequestedMaxTextures: Cardinal;
  out AUseBindless, AUseUpdateAfterBind: Boolean;
  out AClampedMaxTextures: Cardinal;
  out ARequiredExtensions: TAnsiStringArray);
var
  HasExtensionOrCore, HasCoreFeatures: Boolean;
  HwLimit: Cardinal;
begin
  SetLength(ARequiredExtensions, 0);
  AUseBindless := False;
  AUseUpdateAfterBind := False;
  AClampedMaxTextures := 0;

  if ADeviceApiVersion >= VK_API_VERSION_1_2 then
    HasExtensionOrCore := True
  else
  if (ADeviceApiVersion >= VK_API_VERSION_1_1) and AHasDescriptorIndexingExt then
  begin
    { Vulkan 1.1: VK_KHR_maintenance3 is core in 1.1, only VK_EXT_descriptor_indexing is required }
    HasExtensionOrCore := True;
    SetLength(ARequiredExtensions, 1);
    ARequiredExtensions[0] := VK_EXT_descriptor_indexing;
  end else
  if AHasDescriptorIndexingExt and AHasMaintenance3Ext then
  begin
    HasExtensionOrCore := True;
    SetLength(ARequiredExtensions, 2);
    ARequiredExtensions[0] := VK_KHR_maintenance3;
    ARequiredExtensions[1] := VK_EXT_descriptor_indexing;
  end else
    HasExtensionOrCore := False;

  HasCoreFeatures :=
    (AFeatures.shaderSampledImageArrayNonUniformIndexing = VK_TRUE) and
    (AFeatures.descriptorBindingPartiallyBound = VK_TRUE) and
    (AFeatures.descriptorBindingUpdateUnusedWhilePending = VK_TRUE) and
    (AFeatures.runtimeDescriptorArray = VK_TRUE);

  if not (HasExtensionOrCore and HasCoreFeatures) then
  begin
    SetLength(ARequiredExtensions, 0);
    Exit;
  end;

  AUseBindless := True;
  AUseUpdateAfterBind :=
    (AFeatures.descriptorBindingSampledImageUpdateAfterBind = VK_TRUE);

  HwLimit := ARequestedMaxTextures;
  if HwLimit = 0 then
    HwLimit := 4096;

  if AProps.maxPerStageDescriptorUpdateAfterBindSampledImages > 0 then
    HwLimit := Min(HwLimit, AProps.maxPerStageDescriptorUpdateAfterBindSampledImages);
  if AProps.maxDescriptorSetUpdateAfterBindSampledImages > 0 then
    HwLimit := Min(HwLimit, AProps.maxDescriptorSetUpdateAfterBindSampledImages);

  AClampedMaxTextures := Max(Cardinal(1), HwLimit);
end;

procedure ResolveExtendedDynamicStateAndSync2Config(const ADeviceApiVersion: Cardinal;
  const AHasExtDynStateExt, AHasSync2Ext, AHasTimelineSemExt: Boolean;
  const AExtDynStateFeature, ASync2Feature, ATimelineSemFeature: Boolean;
  out AUseExtDynState, AUseSync2, AUseTimelineSem: Boolean;
  out ARequiredExtensions: TAnsiStringArray);
var
  ExtIdx: Integer;

  procedure AppendExt(const AExtName: AnsiString);
  begin
    ExtIdx := Length(ARequiredExtensions);
    SetLength(ARequiredExtensions, ExtIdx + 1);
    ARequiredExtensions[ExtIdx] := AExtName;
  end;

begin
  SetLength(ARequiredExtensions, 0);
  AUseExtDynState := False;
  AUseSync2 := False;
  AUseTimelineSem := False;

  if ADeviceApiVersion < VK_API_VERSION_1_1 then
    Exit;

  { 1. Extended Dynamic State: Core in Vulkan 1.3, VK_EXT_extended_dynamic_state in 1.1/1.2 }
  if AExtDynStateFeature then
  begin
    if ADeviceApiVersion >= VK_API_VERSION_1_3 then
      AUseExtDynState := True
    else if AHasExtDynStateExt then
    begin
      AUseExtDynState := True;
      AppendExt(VK_EXT_extended_dynamic_state);
    end;
  end;

  { 2. Synchronization2: Core in Vulkan 1.3, VK_KHR_synchronization2 in 1.1/1.2 }
  if ASync2Feature then
  begin
    if ADeviceApiVersion >= VK_API_VERSION_1_3 then
      AUseSync2 := True
    else if AHasSync2Ext then
    begin
      AUseSync2 := True;
      AppendExt(VK_KHR_synchronization2);
    end;
  end;

  { 3. Timeline Semaphores: Core in Vulkan 1.2+, VK_KHR_timeline_semaphore in 1.1 }
  if ATimelineSemFeature then
  begin
    if ADeviceApiVersion >= VK_API_VERSION_1_2 then
      AUseTimelineSem := True
    else if AHasTimelineSemExt then
    begin
      AUseTimelineSem := True;
      AppendExt(VK_KHR_timeline_semaphore);
    end;
  end;
end;

{$push}{$Q-}{$R-}
procedure HashBytesFNV1a(var AHash: UInt64; const AData; const ASize: PtrUInt);
var
  P: PByte;
  I: PtrUInt;
begin
  if ASize = 0 then Exit;
  P := @AData;
  for I := 0 to ASize - 1 do
  begin
    AHash := (AHash xor UInt64(P[I])) * FNV1aPrime64;
  end;
end;

procedure HashUInt64FNV1a(var AHash: UInt64; const AValue: UInt64);
begin
  HashBytesFNV1a(AHash, AValue, SizeOf(AValue));
end;
{$pop}

function ComputeVertexInputLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
var
  I, Count: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashBytesFNV1a(Result, ADesc.Topology, SizeOf(ADesc.Topology));

  Count := Length(ADesc.VertexInput.Bindings);
  HashBytesFNV1a(Result, Count, SizeOf(Count));
  for I := 0 to High(ADesc.VertexInput.Bindings) do
    HashBytesFNV1a(Result, ADesc.VertexInput.Bindings[I], SizeOf(TRHIVertexBindingDesc));

  Count := Length(ADesc.VertexInput.Attributes);
  HashBytesFNV1a(Result, Count, SizeOf(Count));
  for I := 0 to High(ADesc.VertexInput.Attributes) do
  begin
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Location, SizeOf(Cardinal));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Binding, SizeOf(Cardinal));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Format, SizeOf(TRHIVertexAttributeFormat));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Offset, SizeOf(Cardinal));
  end;
end;

function ComputePreRasterizationLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
var
  I, Count: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, PtrUInt(ADesc.VertexShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.GeometryShader));
  HashBytesFNV1a(Result, ADesc.Rasterizer, SizeOf(ADesc.Rasterizer));
  HashBytesFNV1a(Result, ADesc.PushConstantSize, SizeOf(ADesc.PushConstantSize));
  HashBytesFNV1a(Result, ADesc.PushConstantStages, SizeOf(ADesc.PushConstantStages));

  Count := Length(ADesc.DescriptorSetLayouts);
  HashBytesFNV1a(Result, Count, SizeOf(Count));
  for I := 0 to High(ADesc.DescriptorSetLayouts) do
    HashUInt64FNV1a(Result, PtrUInt(ADesc.DescriptorSetLayouts[I]));
end;

function ComputeFragmentShaderLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
var
  I, Count: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, PtrUInt(ADesc.FragmentShader));
  HashBytesFNV1a(Result, ADesc.DepthStencil, SizeOf(ADesc.DepthStencil));
  HashBytesFNV1a(Result, ADesc.SampleCount, SizeOf(ADesc.SampleCount));
  HashBytesFNV1a(Result, ADesc.PushConstantSize, SizeOf(ADesc.PushConstantSize));
  HashBytesFNV1a(Result, ADesc.PushConstantStages, SizeOf(ADesc.PushConstantStages));

  Count := Length(ADesc.DescriptorSetLayouts);
  HashBytesFNV1a(Result, Count, SizeOf(Count));
  for I := 0 to High(ADesc.DescriptorSetLayouts) do
    HashUInt64FNV1a(Result, PtrUInt(ADesc.DescriptorSetLayouts[I]));
end;

function ComputeFragmentOutputLibraryKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
var
  I, Count: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashBytesFNV1a(Result, ADesc.BlendState, SizeOf(ADesc.BlendState));
  HashBytesFNV1a(Result, ADesc.DepthAttachmentFormat, SizeOf(ADesc.DepthAttachmentFormat));
  HashBytesFNV1a(Result, ADesc.SampleCount, SizeOf(ADesc.SampleCount));

  Count := Length(ADesc.ColorAttachmentFormats);
  HashBytesFNV1a(Result, Count, SizeOf(Count));
  for I := 0 to High(ADesc.ColorAttachmentFormats) do
    HashBytesFNV1a(Result, ADesc.ColorAttachmentFormats[I], SizeOf(TRHIPixelFormat));
end;

function ComputePipelineKeyHashEx(const ADesc: TRHIGraphicsPipelineDesc;
  const AIgnoreExtendedDynamicStates: Boolean): UInt64;
var
  I: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, PtrUInt(ADesc.VertexShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.FragmentShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.GeometryShader));
  if not AIgnoreExtendedDynamicStates then
  begin
    HashBytesFNV1a(Result, ADesc.Topology, SizeOf(ADesc.Topology));
    HashBytesFNV1a(Result, ADesc.Rasterizer, SizeOf(ADesc.Rasterizer));
    HashBytesFNV1a(Result, ADesc.DepthStencil, SizeOf(ADesc.DepthStencil));
  end else
  begin
    { PolygonMode, DepthBiasEnable, DepthClampEnable, StencilTestEnable, FrontStencil, and BackStencil remain baked }
    HashBytesFNV1a(Result, ADesc.Rasterizer.PolygonMode, SizeOf(ADesc.Rasterizer.PolygonMode));
    HashBytesFNV1a(Result, ADesc.Rasterizer.DepthBiasEnable, SizeOf(ADesc.Rasterizer.DepthBiasEnable));
    HashBytesFNV1a(Result, ADesc.Rasterizer.DepthClampEnable, SizeOf(ADesc.Rasterizer.DepthClampEnable));
    HashBytesFNV1a(Result, ADesc.DepthStencil.StencilTestEnable, SizeOf(ADesc.DepthStencil.StencilTestEnable));
    HashBytesFNV1a(Result, ADesc.DepthStencil.FrontStencil, SizeOf(ADesc.DepthStencil.FrontStencil));
    HashBytesFNV1a(Result, ADesc.DepthStencil.BackStencil, SizeOf(ADesc.DepthStencil.BackStencil));
  end;
  HashBytesFNV1a(Result, ADesc.BlendState, SizeOf(ADesc.BlendState));
  HashBytesFNV1a(Result, ADesc.PushConstantSize, SizeOf(ADesc.PushConstantSize));
  HashBytesFNV1a(Result, ADesc.PushConstantStages, SizeOf(ADesc.PushConstantStages));
  HashBytesFNV1a(Result, ADesc.DepthAttachmentFormat, SizeOf(ADesc.DepthAttachmentFormat));
  HashBytesFNV1a(Result, ADesc.SampleCount, SizeOf(ADesc.SampleCount));

  for I := 0 to High(ADesc.VertexInput.Bindings) do
    HashBytesFNV1a(Result, ADesc.VertexInput.Bindings[I], SizeOf(TRHIVertexBindingDesc));

  for I := 0 to High(ADesc.VertexInput.Attributes) do
  begin
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Location, SizeOf(Cardinal));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Binding, SizeOf(Cardinal));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Format, SizeOf(TRHIVertexAttributeFormat));
    HashBytesFNV1a(Result, ADesc.VertexInput.Attributes[I].Offset, SizeOf(Cardinal));
  end;

  for I := 0 to High(ADesc.ColorAttachmentFormats) do
    HashBytesFNV1a(Result, ADesc.ColorAttachmentFormats[I], SizeOf(TRHIPixelFormat));
end;

function ComputePipelineKeyHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
begin
  Result := ComputePipelineKeyHashEx(ADesc, False);
end;

function ComputeComputePipelineKeyHash(const ADesc: TRHIComputePipelineDesc): UInt64;
var
  I, Count: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, PtrUInt(ADesc.ComputeShader));
  HashBytesFNV1a(Result, ADesc.PushConstantSize, SizeOf(ADesc.PushConstantSize));
  HashBytesFNV1a(Result, ADesc.PushConstantStages, SizeOf(ADesc.PushConstantStages));

  Count := Length(ADesc.DescriptorSetLayouts);
  HashBytesFNV1a(Result, Count, SizeOf(Count));
  for I := 0 to High(ADesc.DescriptorSetLayouts) do
    HashUInt64FNV1a(Result, PtrUInt(ADesc.DescriptorSetLayouts[I]));
end;

function ComputeRenderPassKeyHash(const AColorFormats: array of TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat; const ASampleCount: Cardinal;
  const AColorLoadOp: TRHIAttachmentLoadOp; const ADepthLoadOp: TRHIAttachmentLoadOp;
  const AColorStoreOp: TRHIAttachmentStoreOp; const ADepthStoreOp: TRHIAttachmentStoreOp;
  const AHasColorResolve: Boolean): UInt64;
var
  I, ColorCount: Integer;
begin
  Result := FNV1aOffsetBasis64;
  ColorCount := Length(AColorFormats);
  HashBytesFNV1a(Result, ColorCount, SizeOf(ColorCount));
  for I := 0 to High(AColorFormats) do
    HashBytesFNV1a(Result, AColorFormats[I], SizeOf(TRHIPixelFormat));
  HashBytesFNV1a(Result, ADepthFormat, SizeOf(ADepthFormat));
  HashBytesFNV1a(Result, ASampleCount, SizeOf(ASampleCount));
  HashBytesFNV1a(Result, AColorLoadOp, SizeOf(AColorLoadOp));
  HashBytesFNV1a(Result, ADepthLoadOp, SizeOf(ADepthLoadOp));
  HashBytesFNV1a(Result, AColorStoreOp, SizeOf(AColorStoreOp));
  HashBytesFNV1a(Result, ADepthStoreOp, SizeOf(ADepthStoreOp));
  if AHasColorResolve then
    HashBytesFNV1a(Result, AHasColorResolve, SizeOf(AHasColorResolve));
end;

function ComputeFramebufferKeyHash(const ARenderPass: VkRenderPass;
  const AAttachments: array of VkImageView; const AWidth, AHeight: Cardinal): UInt64;
var
  I, AttCount: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, UInt64(ARenderPass));
  AttCount := Length(AAttachments);
  HashBytesFNV1a(Result, AttCount, SizeOf(AttCount));
  for I := 0 to High(AAttachments) do
    HashUInt64FNV1a(Result, UInt64(AAttachments[I]));
  HashBytesFNV1a(Result, AWidth, SizeOf(AWidth));
  HashBytesFNV1a(Result, AHeight, SizeOf(AHeight));
end;

procedure SavePipelineCacheBlobToStream(const AStream: TStream;
  const AVendorId, ADeviceId: Cardinal; const AData: Pointer; const ASize: PtrUInt);
var
  Header: TPipelineCacheDiskHeader;
  HashVal: UInt64;
begin
  if (AStream = nil) or (AData = nil) or (ASize = 0) then Exit;

  HashVal := FNV1aOffsetBasis64;
  HashBytesFNV1a(HashVal, AData^, ASize);

  FillChar(Header, SizeOf(Header), 0);
  Header.Magic := PipelineCacheDiskMagic;
  Header.Version := PipelineCacheDiskVersion;
  Header.VendorId := AVendorId;
  Header.DeviceId := ADeviceId;
  Header.DataSize := Cardinal(ASize);
  Header.DataHash := HashVal;

  AStream.WriteBuffer(Header, SizeOf(Header));
  AStream.WriteBuffer(AData^, ASize);
end;

function LoadPipelineCacheBlobFromStream(const AStream: TStream;
  const AExpectedVendorId, AExpectedDeviceId: Cardinal; out ABlob: TBytes): Boolean;
var
  Header: TPipelineCacheDiskHeader;
  ComputedHash: UInt64;
begin
  SetLength(ABlob, 0);
  if (AStream = nil) or (AStream.Size - AStream.Position < SizeOf(Header)) then
    Exit(False);

  AStream.ReadBuffer(Header, SizeOf(Header));
  if (Header.Magic <> PipelineCacheDiskMagic) or
     (Header.Version <> PipelineCacheDiskVersion) or
     (Header.DataSize = 0) or
     ((AExpectedVendorId <> 0) and (Header.VendorId <> AExpectedVendorId)) or
     ((AExpectedDeviceId <> 0) and (Header.DeviceId <> AExpectedDeviceId)) or
     (AStream.Size - AStream.Position < Header.DataSize) then
    Exit(False);

  SetLength(ABlob, Header.DataSize);
  AStream.ReadBuffer(ABlob[0], Header.DataSize);

  ComputedHash := FNV1aOffsetBasis64;
  HashBytesFNV1a(ComputedHash, ABlob[0], Header.DataSize);
  if ComputedHash <> Header.DataHash then
  begin
    SetLength(ABlob, 0);
    Exit(False);
  end;

  Result := True;
end;

{ ---------------------------------------------------------------------------- }
{ Type Conversion Helpers (RHI <-> Vulkan)                                     }
{ ---------------------------------------------------------------------------- }

procedure CheckVk(const Res: VkResult; const Context: String);
begin
  if Res <> VK_SUCCESS then
    raise ERHIError.CreateFmt('Vulkan error (%d) in %s', [ Ord(Res), Context ]);
end;

function RHIToVkFormat(const Format: TRHIPixelFormat): VkFormat;
begin
  case Format of
    pfR8_UNorm:           Result := VK_FORMAT_R8_UNORM;
    pfRG8_UNorm:          Result := VK_FORMAT_R8G8_UNORM;
    pfRGBA8_UNorm:        Result := VK_FORMAT_R8G8B8A8_UNORM;
    pfRGBA8_sRGB:         Result := VK_FORMAT_R8G8B8A8_SRGB;
    pfBGRA8_UNorm:        Result := VK_FORMAT_B8G8R8A8_UNORM;
    pfBGRA8_sRGB:         Result := VK_FORMAT_B8G8R8A8_SRGB;
    pfR16_Float:          Result := VK_FORMAT_R16_SFLOAT;
    pfRG16_Float:         Result := VK_FORMAT_R16G16_SFLOAT;
    pfRGBA16_Float:       Result := VK_FORMAT_R16G16B16A16_SFLOAT;
    pfR32_Float:          Result := VK_FORMAT_R32_SFLOAT;
    pfRGBA32_Float:       Result := VK_FORMAT_R32G32B32A32_SFLOAT;
    pfD16_UNorm:          Result := VK_FORMAT_D16_UNORM;
    pfD24_UNorm_S8_UInt:  Result := VK_FORMAT_D24_UNORM_S8_UINT;
    pfD32_Float:          Result := VK_FORMAT_D32_SFLOAT;
    pfD32_Float_S8_UInt:  Result := VK_FORMAT_D32_SFLOAT_S8_UINT;
    pfBC1_RGBA_UNorm:     Result := VK_FORMAT_BC1_RGBA_UNORM_BLOCK;
    pfBC1_RGBA_sRGB:      Result := VK_FORMAT_BC1_RGBA_SRGB_BLOCK;
    pfBC3_RGBA_UNorm:     Result := VK_FORMAT_BC3_UNORM_BLOCK;
    pfBC3_RGBA_sRGB:      Result := VK_FORMAT_BC3_SRGB_BLOCK;
    pfBC5_RG_UNorm:       Result := VK_FORMAT_BC5_UNORM_BLOCK;
    pfBC7_RGBA_UNorm:     Result := VK_FORMAT_BC7_UNORM_BLOCK;
    pfBC7_RGBA_sRGB:      Result := VK_FORMAT_BC7_SRGB_BLOCK;
    pfASTC_4x4_UNorm:     Result := VK_FORMAT_ASTC_4x4_UNORM_BLOCK;
    pfASTC_4x4_sRGB:      Result := VK_FORMAT_ASTC_4x4_SRGB_BLOCK;
    pfETC2_RGB8_UNorm:    Result := VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK;
    pfETC2_RGBA8_UNorm:   Result := VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK;
    else                  Result := VK_FORMAT_UNDEFINED;
  end;
end;

function RHIToVkVertexFormat(const Format: TRHIVertexAttributeFormat): VkFormat;
begin
  case Format of
    vafFloat:            Result := VK_FORMAT_R32_SFLOAT;
    vafVector2:          Result := VK_FORMAT_R32G32_SFLOAT;
    vafVector3:          Result := VK_FORMAT_R32G32B32_SFLOAT;
    vafVector4:          Result := VK_FORMAT_R32G32B32A32_SFLOAT;
    vafByte4Normalized,
    vafUByte4Normalized: Result := VK_FORMAT_R8G8B8A8_UNORM;
    else                 Result := VK_FORMAT_R32G32B32A32_SFLOAT;
  end;
end;

function RHIToVkTopology(const Topology: TRHIPrimitiveTopology): VkPrimitiveTopology;
begin
  case Topology of
    ptPointList:     Result := VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
    ptLineList:      Result := VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    ptLineStrip:     Result := VK_PRIMITIVE_TOPOLOGY_LINE_STRIP;
    ptTriangleList:  Result := VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    ptTriangleStrip: Result := VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
    else             Result := VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
  end;
end;

function RHIToVkPolygonMode(const Mode: TRHIPolygonMode): VkPolygonMode;
begin
  case Mode of
    pmFill:  Result := VK_POLYGON_MODE_FILL;
    pmLine:  Result := VK_POLYGON_MODE_LINE;
    pmPoint: Result := VK_POLYGON_MODE_POINT;
    else     Result := VK_POLYGON_MODE_FILL;
  end;
end;

function RHIToVkCullMode(const Mode: TRHICullMode): VkCullModeFlags;
begin
  case Mode of
    cmNone:  Result := VK_CULL_MODE_NONE;
    cmFront: Result := VK_CULL_MODE_FRONT_BIT;
    cmBack:  Result := VK_CULL_MODE_BACK_BIT;
    else     Result := VK_CULL_MODE_NONE;
  end;
end;

function RHIToVkFrontFace(const Face: TRHIFrontFace): VkFrontFace;
begin
  if Face = ffClockwise then
    Result := VK_FRONT_FACE_CLOCKWISE
  else
    Result := VK_FRONT_FACE_COUNTER_CLOCKWISE;
end;

function RHIToVkCompareOp(const Op: TRHICompareOp): VkCompareOp;
begin
  case Op of
    coNever:          Result := VK_COMPARE_OP_NEVER;
    coLess:           Result := VK_COMPARE_OP_LESS;
    coEqual:          Result := VK_COMPARE_OP_EQUAL;
    coLessOrEqual:    Result := VK_COMPARE_OP_LESS_OR_EQUAL;
    coGreater:        Result := VK_COMPARE_OP_GREATER;
    coNotEqual:       Result := VK_COMPARE_OP_NOT_EQUAL;
    coGreaterOrEqual: Result := VK_COMPARE_OP_GREATER_OR_EQUAL;
    coAlways:         Result := VK_COMPARE_OP_ALWAYS;
    else              Result := VK_COMPARE_OP_LESS_OR_EQUAL;
  end;
end;

function RHIToVkStencilOp(const AOp: TRHIStencilOp): Integer;
const
  VK_STENCIL_OP_KEEP = 0;
  VK_STENCIL_OP_ZERO = 1;
  VK_STENCIL_OP_REPLACE = 2;
  VK_STENCIL_OP_INCREMENT_AND_CLAMP = 3;
  VK_STENCIL_OP_DECREMENT_AND_CLAMP = 4;
  VK_STENCIL_OP_INVERT = 5;
  VK_STENCIL_OP_INCREMENT_AND_WRAP = 6;
  VK_STENCIL_OP_DECREMENT_AND_WRAP = 7;
begin
  case AOp of
    soKeep:              Result := VK_STENCIL_OP_KEEP;
    soZero:              Result := VK_STENCIL_OP_ZERO;
    soReplace:           Result := VK_STENCIL_OP_REPLACE;
    soIncrementAndClamp: Result := VK_STENCIL_OP_INCREMENT_AND_CLAMP;
    soDecrementAndClamp: Result := VK_STENCIL_OP_DECREMENT_AND_CLAMP;
    soInvert:            Result := VK_STENCIL_OP_INVERT;
    soIncrementAndWrap:  Result := VK_STENCIL_OP_INCREMENT_AND_WRAP;
    soDecrementAndWrap:  Result := VK_STENCIL_OP_DECREMENT_AND_WRAP;
    else                 Result := VK_STENCIL_OP_KEEP;
  end;
end;

function RHIToVkStencilOpState(const AState: TRHIStencilOpStateDesc): VkStencilOpState;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.failOp := RHIToVkStencilOp(AState.FailOp);
  Result.passOp := RHIToVkStencilOp(AState.PassOp);
  Result.depthFailOp := RHIToVkStencilOp(AState.DepthFailOp);
  Result.compareOp := RHIToVkCompareOp(AState.CompareOp);
  Result.compareMask := AState.CompareMask;
  Result.writeMask := AState.WriteMask;
  Result.reference := AState.Reference;
end;

function RHIToVkBlendFactor(const Factor: TRHIBlendFactor): Integer;
begin
  case Factor of
    bfZero:             Result := VK_BLEND_FACTOR_ZERO;
    bfOne:              Result := VK_BLEND_FACTOR_ONE;
    bfSrcColor:         Result := VK_BLEND_FACTOR_SRC_COLOR;
    bfOneMinusSrcColor: Result := VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR;
    bfDstColor:         Result := VK_BLEND_FACTOR_DST_COLOR;
    bfOneMinusDstColor: Result := VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR;
    bfSrcAlpha:         Result := VK_BLEND_FACTOR_SRC_ALPHA;
    bfOneMinusSrcAlpha: Result := VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    bfDstAlpha:         Result := VK_BLEND_FACTOR_DST_ALPHA;
    bfOneMinusDstAlpha: Result := VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA;
    else                Result := VK_BLEND_FACTOR_ONE;
  end;
end;

function RHIToVkBlendOp(const Op: TRHIBlendOp): Integer;
begin
  case Op of
    boAdd:             Result := VK_BLEND_OP_ADD;
    boSubtract:        Result := VK_BLEND_OP_SUBTRACT;
    boReverseSubtract: Result := VK_BLEND_OP_REVERSE_SUBTRACT;
    boMin:             Result := VK_BLEND_OP_MIN;
    boMax:             Result := VK_BLEND_OP_MAX;
    else               Result := VK_BLEND_OP_ADD;
  end;
end;

function RHIToVkShaderStageFlags(const Stages: TRHIShaderStageFlags): VkShaderStageFlags;
begin
  Result := 0;
  if ssVertex in Stages then Result := Result or VK_SHADER_STAGE_VERTEX_BIT;
  if ssFragment in Stages then Result := Result or VK_SHADER_STAGE_FRAGMENT_BIT;
  if ssGeometry in Stages then Result := Result or VK_SHADER_STAGE_GEOMETRY_BIT;
  if ssCompute in Stages then Result := Result or VK_SHADER_STAGE_COMPUTE_BIT;
end;

function GetRequiredVkFormatFeatures(const AFormat: TRHIPixelFormat;
  const AUsage: TRHITextureUsageFlags): VkFlags;
begin
  Result := 0;
  if tuSampled in AUsage then
    Result := Result or VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;
  if tuColorAttachment in AUsage then
    Result := Result or VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT;
  if (tuDepthStencil in AUsage) or
     (AFormat in [pfD16_UNorm, pfD24_UNorm_S8_UInt, pfD32_Float, pfD32_Float_S8_UInt]) then
    Result := Result or VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;
  if tuTransferSrc in AUsage then
    Result := Result or VK_FORMAT_FEATURE_TRANSFER_SRC_BIT;
  if tuTransferDst in AUsage then
    Result := Result or VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
end;

function GetFormatTransitionAspectMask(const AFormat: TRHIPixelFormat): VkImageAspectFlags;
begin
  case AFormat of
    pfD16_UNorm,
    pfD32_Float:
      Result := VK_IMAGE_ASPECT_DEPTH_BIT;
    pfD24_UNorm_S8_UInt,
    pfD32_Float_S8_UInt:
      { Per VUID-VkImageMemoryBarrier-subresourceRange-09601, layout transitions on
        combined depth+stencil images must specify BOTH DEPTH_BIT and STENCIL_BIT }
      Result := VK_IMAGE_ASPECT_DEPTH_BIT or VK_IMAGE_ASPECT_STENCIL_BIT;
    else
      Result := VK_IMAGE_ASPECT_COLOR_BIT;
  end;
end;

function GetFormatViewAspectMask(const AFormat: TRHIPixelFormat;
  const AUsage: TRHITextureUsageFlags): VkImageAspectFlags;
begin
  case AFormat of
    pfD16_UNorm,
    pfD32_Float:
      Result := VK_IMAGE_ASPECT_DEPTH_BIT;
    pfD24_UNorm_S8_UInt,
    pfD32_Float_S8_UInt:
      begin
        { Per VUID-VkDescriptorImageInfo-imageView-01976, a VkImageView used for
          shader sampling (tuSampled) of a depth/stencil image must specify ONLY
          VK_IMAGE_ASPECT_DEPTH_BIT (or STENCIL_BIT), never both }
        if tuSampled in AUsage then
          Result := VK_IMAGE_ASPECT_DEPTH_BIT
        else
          Result := VK_IMAGE_ASPECT_DEPTH_BIT or VK_IMAGE_ASPECT_STENCIL_BIT;
      end;
    else
      Result := VK_IMAGE_ASPECT_COLOR_BIT;
  end;
end;

function NegotiateOptimalPixelFormat(const ARequestedFormat: TRHIPixelFormat;
  const AUsage: TRHITextureUsageFlags;
  const APhysicalDevice: VkPhysicalDevice): TRHIPixelFormat;
var
  ReqFeatures: VkFlags;

  function IsFormatSupported(const Candidate: TRHIPixelFormat): Boolean;
  var
    VkFmt: VkFormat;
    FmtProps: VkFormatProperties;
  begin
    VkFmt := RHIToVkFormat(Candidate);
    if VkFmt = VK_FORMAT_UNDEFINED then
      Exit(False);
    if (APhysicalDevice = nil) or not Assigned(vkGetPhysicalDeviceFormatProperties) then
      Exit(True);
    FillChar(FmtProps, SizeOf(FmtProps), 0);
    vkGetPhysicalDeviceFormatProperties(APhysicalDevice, VkFmt, @FmtProps);
    Result := (FmtProps.optimalTilingFeatures and ReqFeatures) = ReqFeatures;
  end;

const
  DepthStencilFallbacksD24S8: array[0..3] of TRHIPixelFormat = (
    pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt, pfD32_Float, pfD16_UNorm
  );
  DepthStencilFallbacksD32S8: array[0..3] of TRHIPixelFormat = (
    pfD32_Float_S8_UInt, pfD24_UNorm_S8_UInt, pfD32_Float, pfD16_UNorm
  );
  DepthFallbacksD32: array[0..2] of TRHIPixelFormat = (
    pfD32_Float, pfD24_UNorm_S8_UInt, pfD16_UNorm
  );
  DepthFallbacksD16: array[0..2] of TRHIPixelFormat = (
    pfD16_UNorm, pfD24_UNorm_S8_UInt, pfD32_Float
  );
var
  I: Integer;
begin
  Result := ARequestedFormat;
  if (APhysicalDevice = nil) or not Assigned(vkGetPhysicalDeviceFormatProperties) then
    Exit;

  ReqFeatures := GetRequiredVkFormatFeatures(ARequestedFormat, AUsage);
  if ReqFeatures = 0 then
    ReqFeatures := VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;

  if IsFormatSupported(ARequestedFormat) then
    Exit;

  case ARequestedFormat of
    pfD24_UNorm_S8_UInt:
      for I := Low(DepthStencilFallbacksD24S8) to High(DepthStencilFallbacksD24S8) do
        if IsFormatSupported(DepthStencilFallbacksD24S8[I]) then
          Exit(DepthStencilFallbacksD24S8[I]);
    pfD32_Float_S8_UInt:
      for I := Low(DepthStencilFallbacksD32S8) to High(DepthStencilFallbacksD32S8) do
        if IsFormatSupported(DepthStencilFallbacksD32S8[I]) then
          Exit(DepthStencilFallbacksD32S8[I]);
    pfD32_Float:
      for I := Low(DepthFallbacksD32) to High(DepthFallbacksD32) do
        if IsFormatSupported(DepthFallbacksD32[I]) then
          Exit(DepthFallbacksD32[I]);
    pfD16_UNorm:
      for I := Low(DepthFallbacksD16) to High(DepthFallbacksD16) do
        if IsFormatSupported(DepthFallbacksD16[I]) then
          Exit(DepthFallbacksD16[I]);
    pfBC1_RGBA_sRGB, pfBC3_RGBA_sRGB, pfBC7_RGBA_sRGB, pfASTC_4x4_sRGB:
      if IsFormatSupported(pfRGBA8_sRGB) then
        Exit(pfRGBA8_sRGB)
      else if IsFormatSupported(pfBGRA8_sRGB) then
        Exit(pfBGRA8_sRGB);
    pfBC1_RGBA_UNorm, pfBC3_RGBA_UNorm, pfBC5_RG_UNorm, pfBC7_RGBA_UNorm,
    pfASTC_4x4_UNorm, pfETC2_RGB8_UNorm, pfETC2_RGBA8_UNorm:
      if IsFormatSupported(pfRGBA8_UNorm) then
        Exit(pfRGBA8_UNorm)
      else if IsFormatSupported(pfBGRA8_UNorm) then
        Exit(pfBGRA8_UNorm);
    pfBGRA8_UNorm:
      if IsFormatSupported(pfRGBA8_UNorm) then
        Exit(pfRGBA8_UNorm);
    pfBGRA8_sRGB:
      if IsFormatSupported(pfRGBA8_sRGB) then
        Exit(pfRGBA8_sRGB);
  end;
end;

procedure RHIStateToVkLayoutAndAccess(const State: TRHIResourceState;
  out Layout: VkImageLayout; out Access: VkAccessFlags; out Stage: VkPipelineStageFlags);
begin
  case State of
    rsUndefined:
      begin
        Layout := VK_IMAGE_LAYOUT_UNDEFINED;
        Access := 0;
        Stage  := VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
      end;
    rsTransferDst:
      begin
        Layout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        Access := VK_ACCESS_TRANSFER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_TRANSFER_BIT;
      end;
    rsTransferSrc:
      begin
        Layout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        Access := VK_ACCESS_TRANSFER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_TRANSFER_BIT;
      end;
    rsShaderRead:
      begin
        Layout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        Access := VK_ACCESS_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
      end;
    rsColorAttachment:
      begin
        Layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        Access := VK_ACCESS_COLOR_ATTACHMENT_READ_BIT or VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
      end;
    rsDepthStencilWrite:
      begin
        Layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        Access := VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT or VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
      end;
    rsDepthStencilRead:
      begin
        Layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL;
        Access := VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT or VK_ACCESS_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
      end;
    rsPresent:
      begin
        Layout := VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        Access := 0;
        Stage  := VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
      end;
  end;
end;

procedure RHIStateToVkLayoutAndAccess2(const State: TRHIResourceState;
  out Layout: VkImageLayout; out Access: VkAccessFlags2; out Stage: VkPipelineStageFlags2);
begin
  case State of
    rsUndefined:
      begin
        Layout := VK_IMAGE_LAYOUT_UNDEFINED;
        Access := VK_ACCESS_2_NONE;
        Stage  := VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT;
      end;
    rsTransferDst:
      begin
        Layout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        Access := VK_ACCESS_2_TRANSFER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT;
      end;
    rsTransferSrc:
      begin
        Layout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        Access := VK_ACCESS_2_TRANSFER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT;
      end;
    rsShaderRead:
      begin
        Layout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        Access := VK_ACCESS_2_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT or VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
      end;
    rsColorAttachment:
      begin
        Layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        Access := VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT or VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
      end;
    rsDepthStencilWrite:
      begin
        Layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        Access := VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT or VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT;
      end;
    rsDepthStencilRead:
      begin
        Layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL;
        Access := VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT or VK_ACCESS_2_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
      end;
    rsPresent:
      begin
        Layout := VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        Access := VK_ACCESS_2_NONE;
        Stage  := VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT;
      end;
    else
      begin
        Layout := VK_IMAGE_LAYOUT_GENERAL;
        Access := VK_ACCESS_2_SHADER_READ_BIT or VK_ACCESS_2_SHADER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT or VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
      end;
  end;
end;

procedure RHIStateToVkBufferAccessAndStage(const State: TRHIResourceState;
  out Access: VkAccessFlags; out Stage: VkPipelineStageFlags);
begin
  case State of
    rsUndefined:
      begin
        Access := 0;
        Stage  := VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
      end;
    rsTransferDst:
      begin
        Access := VK_ACCESS_TRANSFER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_TRANSFER_BIT;
      end;
    rsTransferSrc:
      begin
        Access := VK_ACCESS_TRANSFER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_TRANSFER_BIT;
      end;
    rsShaderRead:
      begin
        Access := VK_ACCESS_UNIFORM_READ_BIT or VK_ACCESS_SHADER_READ_BIT or
                  VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT or VK_ACCESS_INDEX_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
                  VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
                  VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or
                  VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
      end;
    else
      begin
        Access := VK_ACCESS_MEMORY_READ_BIT or VK_ACCESS_MEMORY_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
      end;
  end;
end;

procedure RHIStateToVkBufferAccessAndStage2(const State: TRHIResourceState;
  out Access: VkAccessFlags2; out Stage: VkPipelineStageFlags2);
begin
  case State of
    rsUndefined:
      begin
        Access := VK_ACCESS_2_NONE;
        Stage  := VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT;
      end;
    rsTransferDst:
      begin
        Access := VK_ACCESS_2_TRANSFER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT;
      end;
    rsTransferSrc:
      begin
        Access := VK_ACCESS_2_TRANSFER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT;
      end;
    rsShaderRead:
      begin
        Access := VK_ACCESS_2_UNIFORM_READ_BIT or VK_ACCESS_2_SHADER_READ_BIT or
                  VK_ACCESS_2_VERTEX_ATTRIBUTE_READ_BIT or VK_ACCESS_2_INDEX_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_2_VERTEX_INPUT_BIT or
                  VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT or
                  VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT or
                  VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
      end;
    else
      begin
        Access := VK_ACCESS_2_SHADER_READ_BIT or VK_ACCESS_2_SHADER_WRITE_BIT or
                  VK_ACCESS_2_VERTEX_ATTRIBUTE_READ_BIT or VK_ACCESS_2_INDEX_READ_BIT or
                  VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT or
                  VK_PIPELINE_STAGE_2_VERTEX_INPUT_BIT or
                  VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT or
                  VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
      end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHIBuffer                                                             }
{ ---------------------------------------------------------------------------- }

function TVulkanRHIBuffer.VulkanDevice: TVulkanRHIDevice;
begin
  Result := TVulkanRHIDevice(Device);
end;

constructor TVulkanRHIBuffer.Create(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHIBufferDesc; const InitialData: Pointer);
var
  BufInfo: VkBufferCreateInfo;
  MemReq: VkMemoryRequirements;
  AllocInfo: VkMemoryAllocateInfo;
  MemProps: VkMemoryPropertyFlags;
  RequiredAlign: VkDeviceSize;
begin
  inherited Create(ADevice, ADesc);

  if (ADevice <> nil) and (ADevice.Handle <> nil) and Assigned(vkCreateBuffer) then
  begin
    FillChar(BufInfo, SizeOf(BufInfo), 0);
    BufInfo.sType := VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    BufInfo.size := ADesc.Size;
    BufInfo.sharingMode := VK_SHARING_MODE_EXCLUSIVE;

    if buVertex in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    if buIndex in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    if buUniform in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    if buStorage in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    if buIndirect in ADesc.Usage then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
    if (buTransferSrc in ADesc.Usage) then BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (buTransferDst in ADesc.Usage) or (ADesc.MemoryUsage = muGpuOnly) then
      BufInfo.usage := BufInfo.usage or VK_BUFFER_USAGE_TRANSFER_DST_BIT;

    CheckVk(vkCreateBuffer(ADevice.Handle, @BufInfo, nil, @FHandle), 'vkCreateBuffer');
  end else
    FHandle := VkBuffer(PtrUInt(Self));

  if (ADevice <> nil) and (ADevice.MemoryAllocator <> nil) then
  begin
    { Enforce cross-vendor hardware offset alignment limits (e.g., 256B UBO alignment on NVIDIA,
      64B/128B SSBO alignment on Mali/Adreno, optimalBufferCopyOffsetAlignment for staging) }
    RequiredAlign := 16;
    if buUniform in ADesc.Usage then
      RequiredAlign := Max(RequiredAlign, ADevice.MemoryAllocator.MinUniformBufferAlignment);
    if buStorage in ADesc.Usage then
      RequiredAlign := Max(RequiredAlign, ADevice.MemoryAllocator.MinStorageBufferAlignment);
    if (buTransferSrc in ADesc.Usage) or (buTransferDst in ADesc.Usage) then
      RequiredAlign := Max(RequiredAlign, ADevice.MemoryAllocator.OptimalBufferCopyOffsetAlignment);

    { Sub-allocate from pooled VkDeviceMemory blocks via TCastleVulkanMemoryAllocator
      to stay well below Windows WDDM's 4096 maxMemoryAllocationCount limit }
    FAllocation := ADevice.MemoryAllocator.AllocateBufferMemory(
      FHandle, ADesc.Size, ADesc.MemoryUsage, False, RequiredAlign);
    FDeviceMemory := FAllocation.DeviceMemory;
    FMemoryOffset := FAllocation.Offset;
    FAllocatedSize := FAllocation.Size;
    FMappedPtr := FAllocation.MappedPtr;
    if (ADevice.Handle <> nil) and Assigned(vkBindBufferMemory) then
      CheckVk(vkBindBufferMemory(ADevice.Handle, FHandle, FDeviceMemory, FMemoryOffset),
        'vkBindBufferMemory');
    Inc(ADevice.FAllocatedMemoryBytes, FAllocatedSize);
  end else
  if (ADevice <> nil) and (ADevice.Handle <> nil) and Assigned(vkAllocateMemory) then
  begin
    vkGetBufferMemoryRequirements(ADevice.Handle, FHandle, @MemReq);
    case ADesc.MemoryUsage of
      muGpuOnly:  MemProps := VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
      muCpuToGpu: MemProps := VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
      muGpuToCpu: MemProps := VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
    end;
    FillChar(AllocInfo, SizeOf(AllocInfo), 0);
    AllocInfo.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    AllocInfo.allocationSize := MemReq.size;
    AllocInfo.memoryTypeIndex := ADevice.FindMemoryType(MemReq.memoryTypeBits, MemProps);

    CheckVk(vkAllocateMemory(ADevice.Handle, @AllocInfo, nil, @FDeviceMemory), 'vkAllocateMemory(Buffer)');
    CheckVk(vkBindBufferMemory(ADevice.Handle, FHandle, FDeviceMemory, 0), 'vkBindBufferMemory');
    FAllocatedSize := MemReq.size;
    Inc(ADevice.FAllocatedMemoryBytes, FAllocatedSize);
  end;

  if InitialData <> nil then
    UploadData(InitialData^, ADesc.Size, 0);
end;

destructor TVulkanRHIBuffer.Destroy;
begin
  if FMappedPtr <> nil then
    Unmap;
  if VulkanDevice <> nil then
  begin
    if VulkanDevice.StagingUploader <> nil then
      VulkanDevice.StagingUploader.CancelPendingUploadsForBuffer(Self);
    VulkanDevice.DeferOrDestroyBuffer(FHandle, FAllocation, FDeviceMemory, FAllocatedSize);
    FHandle := VK_NULL_HANDLE;
    FillChar(FAllocation, SizeOf(FAllocation), 0);
    FDeviceMemory := VK_NULL_HANDLE;
  end;
  inherited;
end;

function TVulkanRHIBuffer.Map: Pointer;
begin
  { Pooled host-visible blocks in TCastleVulkanMemoryAllocator are persistently mapped;
    return the sub-allocated slice pointer directly without calling vkMapMemory }
  if FAllocation.MappedPtr <> nil then
  begin
    FMappedPtr := FAllocation.MappedPtr;
    Exit(FMappedPtr);
  end;
  if (FMappedPtr = nil) and (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and
     Assigned(vkMapMemory) then
    CheckVk(vkMapMemory(VulkanDevice.Handle, FDeviceMemory, FMemoryOffset, FDesc.Size, 0, @FMappedPtr), 'vkMapMemory');
  Result := FMappedPtr;
end;

procedure TVulkanRHIBuffer.Unmap;
begin
  { Never call vkUnmapMemory on a persistently mapped pooled block }
  if FAllocation.MappedPtr <> nil then
    Exit;
  if FMappedPtr <> nil then
  begin
    if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and Assigned(vkUnmapMemory) then
      vkUnmapMemory(VulkanDevice.Handle, FDeviceMemory);
    FMappedPtr := nil;
  end;
end;

procedure TVulkanRHIBuffer.UploadData(const Data; const Size: PtrUInt; const Offset: PtrUInt);
var
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  CopyRegion: VkBufferCopy;
  DestPtr: PByte;
begin
  if Size = 0 then
    Exit;

  if FDesc.MemoryUsage = muCpuToGpu then
  begin
    DestPtr := PByte(Map);
    if DestPtr <> nil then
    begin
      Inc(DestPtr, Offset);
      Move(Data, DestPtr^, Size);
    end;
    { Explicitly flush if sub-allocated from a non-coherent host-visible heap }
    if FAllocation.IsValid and (VulkanDevice <> nil) and (VulkanDevice.MemoryAllocator <> nil) then
      VulkanDevice.MemoryAllocator.FlushAllocation(FAllocation, Offset, Size);
    Unmap;
  end else
  if (VulkanDevice <> nil) and (VulkanDevice.StagingUploader <> nil) then
  begin
    { Stage into persistent per-frame staging ring buffer for non-blocking batched upload }
    VulkanDevice.StagingUploader.EnqueueBufferUpload(Self, Data, Size, Offset);
  end else
  if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and Assigned(vkCmdCopyBuffer) then
  begin
    { Fallback one-shot upload when StagingUploader is absent }
    FillChar(StagingDesc, SizeOf(StagingDesc), 0);
    StagingDesc.Size := Size;
    StagingDesc.Usage := [buTransferSrc];
    StagingDesc.MemoryUsage := muCpuToGpu;

    StagingBuf := TVulkanRHIBuffer.Create(VulkanDevice, StagingDesc, @Data);
    try
      Cmd := VulkanDevice.BeginSingleTimeCommands;
      CopyRegion.srcOffset := 0;
      CopyRegion.dstOffset := Offset;
      CopyRegion.size := Size;
      vkCmdCopyBuffer(Cmd, StagingBuf.Handle, FHandle, 1, @CopyRegion);
      VulkanDevice.EndSingleTimeCommands(Cmd);
    finally
      FreeAndNil(StagingBuf);
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHITexture                                                            }
{ ---------------------------------------------------------------------------- }

function TVulkanRHITexture.VulkanDevice: TVulkanRHIDevice;
begin
  Result := TVulkanRHIDevice(Device);
end;

constructor TVulkanRHITexture.Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHITextureDesc);
var
  NegotiatedDesc: TRHITextureDesc;
  ImgInfo: VkImageCreateInfo;
  ViewInfo: VkImageViewCreateInfo;
  MemReq: VkMemoryRequirements;
  AllocInfo: VkMemoryAllocateInfo;
  ApproxBytes: VkDeviceSize;
begin
  NegotiatedDesc := ADesc;
  if NegotiatedDesc.SampleCount = 0 then
    NegotiatedDesc.SampleCount := 1;
  if ADevice <> nil then
  begin
    NegotiatedDesc.Format := NegotiateOptimalPixelFormat(
      ADesc.Format, ADesc.Usage, ADevice.PhysicalDevice);
    if ADevice.Capabilities.MaxFramebufferSampleCount > 0 then
      NegotiatedDesc.SampleCount := ClampSampleCountToCapabilities(
        NegotiatedDesc.SampleCount, ADevice.Capabilities.MaxFramebufferSampleCount);
  end;
  { Per VUID-VkImageCreateInfo-samples-02257, multisampled images must have mipLevels = 1 }
  if NegotiatedDesc.SampleCount > 1 then
    NegotiatedDesc.MipLevels := 1;

  inherited Create(ADevice, NegotiatedDesc);
  FOwnsImage := True;

  FAspectMask := GetFormatTransitionAspectMask(FDesc.Format);
  FViewAspectMask := GetFormatViewAspectMask(FDesc.Format, FDesc.Usage);

  ApproxBytes := VkDeviceSize(Max(1, FDesc.Width)) *
    VkDeviceSize(Max(1, FDesc.Height)) *
    VkDeviceSize(Max(1, FDesc.DepthOrArrayLayers)) *
    VkDeviceSize(Max(Cardinal(1), FDesc.SampleCount));
  case FDesc.Format of
    pfRGBA32_Float: ApproxBytes := ApproxBytes * 16;
    pfRGBA16_Float, pfD32_Float_S8_UInt: ApproxBytes := ApproxBytes * 8;
  else
    ApproxBytes := ApproxBytes * 4;
  end;

  if (ADevice = nil) or (ADevice.Handle = nil) then
  begin
    FImage := VkImage(PtrUInt(Self));
    FImageView := VkImageView(PtrUInt(Self));
    if (ADevice <> nil) and (ADevice.MemoryAllocator <> nil) then
    begin
      FAllocation := ADevice.MemoryAllocator.AllocateImageMemory(
        FImage, ApproxBytes, muGpuOnly, True, False);
      FDeviceMemory := FAllocation.DeviceMemory;
      FAllocatedSize := FAllocation.Size;
      Inc(ADevice.FAllocatedMemoryBytes, FAllocatedSize);
    end;
    Exit;
  end;

  FillChar(ImgInfo, SizeOf(ImgInfo), 0);
  ImgInfo.sType := VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  if FDesc.Dimension = td3D then
    ImgInfo.imageType := VK_IMAGE_TYPE_3D
  else
    ImgInfo.imageType := VK_IMAGE_TYPE_2D;
  if FDesc.Dimension in [tdCube, tdCubeArray] then
    ImgInfo.flags := VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
  ImgInfo.format := RHIToVkFormat(FDesc.Format);
  ImgInfo.extent.width := FDesc.Width;
  ImgInfo.extent.height := FDesc.Height;
  if FDesc.Dimension = td3D then
  begin
    ImgInfo.extent.depth := Max(Cardinal(1), FDesc.DepthOrArrayLayers);
    ImgInfo.arrayLayers := 1;
  end else
  begin
    ImgInfo.extent.depth := 1;
    ImgInfo.arrayLayers := Max(Cardinal(1), FDesc.DepthOrArrayLayers);
  end;
  ImgInfo.mipLevels := FDesc.MipLevels;
  ImgInfo.samples := RHIToVkSampleCountFlags(FDesc.SampleCount);
  ImgInfo.tiling := VK_IMAGE_TILING_OPTIMAL;
  ImgInfo.initialLayout := VK_IMAGE_LAYOUT_UNDEFINED;

  if tuSampled in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_SAMPLED_BIT;
  if tuColorAttachment in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  if tuDepthStencil in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
  if tuTransferSrc in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  if tuTransferDst in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_DST_BIT;

  CheckVk(vkCreateImage(ADevice.Handle, @ImgInfo, nil, @FImage), 'vkCreateImage');

  if ADevice.MemoryAllocator <> nil then
  begin
    { Sub-allocate from Non-Linear optimal-image pool via TCastleVulkanMemoryAllocator
      (or dedicated allocation if VK_KHR_dedicated_allocation recommends it for render targets) }
    FAllocation := ADevice.MemoryAllocator.AllocateImageMemory(
      FImage, ApproxBytes, muGpuOnly, True, False);
    FDeviceMemory := FAllocation.DeviceMemory;
    FAllocatedSize := FAllocation.Size;
    CheckVk(vkBindImageMemory(ADevice.Handle, FImage, FDeviceMemory, FAllocation.Offset),
      'vkBindImageMemory');
    Inc(ADevice.FAllocatedMemoryBytes, FAllocatedSize);
  end else
  begin
    vkGetImageMemoryRequirements(ADevice.Handle, FImage, @MemReq);
    FillChar(AllocInfo, SizeOf(AllocInfo), 0);
    AllocInfo.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    AllocInfo.allocationSize := MemReq.size;
    AllocInfo.memoryTypeIndex := ADevice.FindMemoryType(MemReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    CheckVk(vkAllocateMemory(ADevice.Handle, @AllocInfo, nil, @FDeviceMemory), 'vkAllocateMemory(Image)');
    CheckVk(vkBindImageMemory(ADevice.Handle, FImage, FDeviceMemory, 0), 'vkBindImageMemory');
    FAllocatedSize := MemReq.size;
    Inc(ADevice.FAllocatedMemoryBytes, FAllocatedSize);
  end;

  FillChar(ViewInfo, SizeOf(ViewInfo), 0);
  ViewInfo.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  ViewInfo.image := FImage;
  case FDesc.Dimension of
    td2D: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D;
    td2DArray: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D_ARRAY;
    td3D: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_3D;
    tdCube: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_CUBE;
    tdCubeArray: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_CUBE_ARRAY;
  end;
  ViewInfo.format := ImgInfo.format;
  ViewInfo.subresourceRange.aspectMask := FViewAspectMask;
  ViewInfo.subresourceRange.baseMipLevel := 0;
  ViewInfo.subresourceRange.levelCount := FDesc.MipLevels;
  ViewInfo.subresourceRange.baseArrayLayer := 0;
  if FDesc.Dimension = td3D then
    ViewInfo.subresourceRange.layerCount := 1
  else
    ViewInfo.subresourceRange.layerCount := Max(Cardinal(1), FDesc.DepthOrArrayLayers);

  CheckVk(vkCreateImageView(ADevice.Handle, @ViewInfo, nil, @FImageView), 'vkCreateImageView');
end;

constructor TVulkanRHITexture.CreateSwapchainWrapper(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHITextureDesc; const AExistingImage: VkImage; const AExistingView: VkImageView);
begin
  inherited Create(ADevice, ADesc);
  FOwnsImage := False;
  FImage := AExistingImage;
  FImageView := AExistingView;
  FAspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  FViewAspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
end;

destructor TVulkanRHITexture.Destroy;
begin
  if VulkanDevice <> nil then
  begin
    if VulkanDevice.FActiveColorTarget = Self then
      VulkanDevice.FActiveColorTarget := nil;
    if VulkanDevice.FActiveDepthTarget = Self then
      VulkanDevice.FActiveDepthTarget := nil;
    if VulkanDevice.BindlessTextureManager <> nil then
      VulkanDevice.BindlessTextureManager.UnregisterTexture(Self);
    if VulkanDevice.StagingUploader <> nil then
      VulkanDevice.StagingUploader.CancelPendingUploadsForTexture(Self);
    if FOwnsImage then
      VulkanDevice.DeferOrDestroyTexture(FImage, FImageView, FAllocation, FDeviceMemory, FAllocatedSize)
    else if (VulkanDevice.Handle <> nil) and (FImageView <> VK_NULL_HANDLE) then
      vkDestroyImageView(VulkanDevice.Handle, FImageView, nil);
    FImage := VK_NULL_HANDLE;
    FImageView := VK_NULL_HANDLE;
    FillChar(FAllocation, SizeOf(FAllocation), 0);
    FDeviceMemory := VK_NULL_HANDLE;
  end;
  inherited;
end;

procedure TVulkanRHITexture.SetHostClearColor(const AColor: TCastleColor);
var
  TotalPixels, I: PtrUInt;
  RByte, GByte, BByte, AByte: Byte;
begin
  TotalPixels := PtrUInt(Max(Cardinal(1), FDesc.Width)) * PtrUInt(Max(Cardinal(1), FDesc.Height));
  SetLength(FHostPixels, TotalPixels * 4);
  RByte := Byte(Round(EnsureRange(AColor.X, 0.0, 1.0) * 255.0));
  GByte := Byte(Round(EnsureRange(AColor.Y, 0.0, 1.0) * 255.0));
  BByte := Byte(Round(EnsureRange(AColor.Z, 0.0, 1.0) * 255.0));
  AByte := Byte(Round(EnsureRange(AColor.W, 0.0, 1.0) * 255.0));
  if TotalPixels > 0 then
    for I := 0 to TotalPixels - 1 do
    begin
      FHostPixels[I * 4 + 0] := RByte;
      FHostPixels[I * 4 + 1] := GByte;
      FHostPixels[I * 4 + 2] := BByte;
      FHostPixels[I * 4 + 3] := AByte;
    end;
end;

procedure TVulkanRHITexture.SetHostClearDepth(const ADepth: Single);
var
  TotalPixels, I: PtrUInt;
  DByte: Byte;
begin
  TotalPixels := PtrUInt(Max(Cardinal(1), FDesc.Width)) * PtrUInt(Max(Cardinal(1), FDesc.Height));
  SetLength(FHostPixels, TotalPixels * 4);
  DByte := Byte(Round(EnsureRange(ADepth, 0.0, 1.0) * 255.0));
  if TotalPixels > 0 then
    for I := 0 to TotalPixels - 1 do
    begin
      FHostPixels[I * 4 + 0] := DByte;
      FHostPixels[I * 4 + 1] := DByte;
      FHostPixels[I * 4 + 2] := DByte;
      FHostPixels[I * 4 + 3] := 255;
    end;
end;

procedure TVulkanRHITexture.UploadImage(const AImage: TEncodedImage;
  const AMipLevel: Cardinal; const AArrayLayer: Cardinal);
var
  RgbaImage: TRGBAlphaImage;
  NeedsFreeRgba: Boolean;
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  Region: VkBufferImageCopy;
  Barrier: VkImageMemoryBarrier;
  DataSize: PtrUInt;
  PixelsPtr: Pointer;
  ImgWidth, ImgHeight, ImgDepth: Cardinal;
begin
  if AImage = nil then Exit;
  if FImage = VK_NULL_HANDLE then Exit;

  NeedsFreeRgba := False;
  RgbaImage := nil;
  ImgWidth := Max(Cardinal(1), AImage.Width);
  ImgHeight := Max(Cardinal(1), AImage.Height);
  ImgDepth := Max(Cardinal(1), AImage.Depth);

  if (FDesc.Format = pfRGBA32_Float) and (AImage is TRGBAlphaFloatImage) then
  begin
    DataSize := PtrUInt(ImgWidth) * PtrUInt(ImgHeight) * PtrUInt(ImgDepth) * 16;
    PixelsPtr := TRGBAlphaFloatImage(AImage).RawPixels;
  end else
  if AImage is TRGBAlphaImage then
  begin
    RgbaImage := TRGBAlphaImage(AImage);
    DataSize := PtrUInt(ImgWidth) * PtrUInt(ImgHeight) * PtrUInt(ImgDepth) * 4;
    PixelsPtr := RgbaImage.RawPixels;
  end else
  if AImage is TCastleImage then
  begin
    RgbaImage := TRGBAlphaImage.Create(ImgWidth, ImgHeight, ImgDepth);
    RgbaImage.Assign(TCastleImage(AImage));
    NeedsFreeRgba := True;
    DataSize := PtrUInt(ImgWidth) * PtrUInt(ImgHeight) * PtrUInt(ImgDepth) * 4;
    PixelsPtr := RgbaImage.RawPixels;
  end else
    Exit;

  try
    if (RgbaImage <> nil) and (AMipLevel = 0) and (AArrayLayer = 0) and
       (ImgDepth = 1) and ((VulkanDevice = nil) or (VulkanDevice.Handle = nil)) then
    begin
      SetLength(FHostPixels, DataSize);
      if DataSize > 0 then
        Move(PixelsPtr^, FHostPixels[0], DataSize);
    end;

    if (VulkanDevice <> nil) and (VulkanDevice.StagingUploader <> nil) then
    begin
      VulkanDevice.StagingUploader.EnqueueImageUpload(
        Self, PixelsPtr, DataSize,
        ImgWidth, ImgHeight,
        AMipLevel, AArrayLayer, False);
      FCurrentState := rsShaderRead;
      Exit;
    end;

    FillChar(StagingDesc, SizeOf(StagingDesc), 0);
    StagingDesc.Size := DataSize;
    StagingDesc.Usage := [buTransferSrc];
    StagingDesc.MemoryUsage := muCpuToGpu;

    StagingBuf := TVulkanRHIBuffer.Create(VulkanDevice, StagingDesc, PixelsPtr);
    try
      Cmd := VulkanDevice.BeginSingleTimeCommands;

      { Transition from current layout to TRANSFER_DST_OPTIMAL }
      FillChar(Barrier, SizeOf(Barrier), 0);
      Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
      Barrier.oldLayout := VK_IMAGE_LAYOUT_UNDEFINED;
      Barrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.image := FImage;
      Barrier.subresourceRange.aspectMask := FAspectMask;
      Barrier.subresourceRange.baseMipLevel := AMipLevel;
      Barrier.subresourceRange.levelCount := 1;
      Barrier.subresourceRange.baseArrayLayer := AArrayLayer;
      Barrier.subresourceRange.layerCount := 1;
      Barrier.srcAccessMask := 0;
      Barrier.dstAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;

      vkCmdPipelineBarrier(Cmd,
        VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, nil, 0, nil, 1, @Barrier);

      { Copy buffer to image }
      FillChar(Region, SizeOf(Region), 0);
      Region.bufferOffset := 0;
      Region.bufferRowLength := 0;
      Region.bufferImageHeight := 0;
      Region.imageSubresource.aspectMask := FAspectMask;
      Region.imageSubresource.mipLevel := AMipLevel;
      Region.imageSubresource.baseArrayLayer := AArrayLayer;
      Region.imageSubresource.layerCount := 1;
      Region.imageOffset.x := 0;
      Region.imageOffset.y := 0;
      Region.imageOffset.z := 0;
      Region.imageExtent.width := ImgWidth;
      Region.imageExtent.height := ImgHeight;
      Region.imageExtent.depth := ImgDepth;

      vkCmdCopyBufferToImage(Cmd, StagingBuf.Handle, FImage,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, @Region);

      { Transition from TRANSFER_DST_OPTIMAL to SHADER_READ_ONLY_OPTIMAL }
      Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      Barrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
      Barrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
      Barrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;

      vkCmdPipelineBarrier(Cmd,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        0, 0, nil, 0, nil, 1, @Barrier);

      VulkanDevice.EndSingleTimeCommands(Cmd);
      FCurrentState := rsShaderRead;
    finally
      FreeAndNil(StagingBuf);
    end;
  finally
    if NeedsFreeRgba then
      FreeAndNil(RgbaImage);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHISampler, ShaderModule, DescriptorSetLayout, DescriptorSet, Pipeline}
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHISampler.Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHISamplerDesc);
var
  SamplerInfo: VkSamplerCreateInfo;
begin
  inherited Create(ADevice, ADesc);
  FillChar(SamplerInfo, SizeOf(SamplerInfo), 0);
  SamplerInfo.sType := VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
  SamplerInfo.magFilter := VK_FILTER_LINEAR;
  SamplerInfo.minFilter := VK_FILTER_LINEAR;
  SamplerInfo.mipmapMode := VK_SAMPLER_MIPMAP_MODE_LINEAR;
  SamplerInfo.maxLod := ADesc.MaxLod;
  if (ADevice <> nil) and (ADevice.Handle <> nil) and Assigned(vkCreateSampler) then
    CheckVk(vkCreateSampler(ADevice.Handle, @SamplerInfo, nil, @FHandle), 'vkCreateSampler')
  else
    FHandle := VkSampler(PtrUInt(Self));
end;

destructor TVulkanRHISampler.Destroy;
begin
  if Device <> nil then
  begin
    if TVulkanRHIDevice(Device).BindlessTextureManager <> nil then
      TVulkanRHIDevice(Device).BindlessTextureManager.UnregisterSampler(Self);
    if (FHandle <> VK_NULL_HANDLE) and (TVulkanRHIDevice(Device).Handle <> nil) and
       Assigned(vkDestroySampler) then
      vkDestroySampler(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  end;
  FHandle := VK_NULL_HANDLE;
  inherited;
end;

constructor TVulkanRHIShaderModule.Create(const ADevice: TVulkanRHIDevice;
  const AStage: TRHIShaderStage; const ASPIRVBinary: Pointer;
  const ASizeInBytes: PtrUInt; const ADebugName: String);
var
  CreateInfo: VkShaderModuleCreateInfo;
begin
  inherited Create(ADevice, AStage, ADebugName);
  if InspectSPIRVBytecode(ASPIRVBinary, ASizeInBytes, FReflection) then
  begin
    if FReflection.Stage <> AStage then
      WritelnWarning('Vulkan', Format(
        'Shader module "%s" SPIR-V execution model stage (Ord=%d) does not match requested TRHIShaderStage (Ord=%d).',
        [ADebugName, Ord(FReflection.Stage), Ord(AStage)]));
  end;
  if (ADevice = nil) or (ADevice.Handle = nil) or not Assigned(vkCreateShaderModule) then
    Exit;
  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  CreateInfo.codeSize := ASizeInBytes;
  CreateInfo.pCode := PUInt32(ASPIRVBinary);
  CheckVk(vkCreateShaderModule(ADevice.Handle, @CreateInfo, nil, @FHandle), 'vkCreateShaderModule');
end;

destructor TVulkanRHIShaderModule.Destroy;
begin
  if FHandle <> VK_NULL_HANDLE then
    vkDestroyShaderModule(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  inherited;
end;

function TVulkanRHIShaderModule.ValidateDescriptorSetLayout(
  const ASetIndex: Cardinal;
  const AExpectedBindings: array of TRHIDescriptorBindingDesc;
  out ADiagnosticMessage: String): Boolean;
begin
  Result := ValidateSPIRVDescriptorBindings(
    FReflection, ASetIndex, AExpectedBindings, ADiagnosticMessage);
end;

constructor TVulkanRHIDescriptorSetLayout.Create(const ADevice: TVulkanRHIDevice;
  const Bindings: array of TRHIDescriptorBindingDesc);
var
  VkBindings: array of VkDescriptorSetLayoutBinding;
  VkBindingFlags: array of VkDescriptorBindingFlags;
  BindingFlagsInfo: VkDescriptorSetLayoutBindingFlagsCreateInfo;
  HasAnyBindingFlags: Boolean;
  LayoutInfo: VkDescriptorSetLayoutCreateInfo;
  I: Integer;
begin
  inherited Create(ADevice, '');
  FUsesUpdateAfterBind := False;
  HasAnyBindingFlags := False;
  SetLength(VkBindings, Length(Bindings));
  SetLength(VkBindingFlags, Length(Bindings));
  for I := 0 to High(Bindings) do
  begin
    FillChar(VkBindings[I], SizeOf(VkDescriptorSetLayoutBinding), 0);
    VkBindings[I].binding := Bindings[I].Binding;
    VkBindings[I].descriptorCount := Bindings[I].Count;
    VkBindings[I].stageFlags := RHIToVkShaderStageFlags(Bindings[I].StageFlags);
    case Bindings[I].DescriptorType of
      dtUniformBuffer:        VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
      dtUniformBufferDynamic: VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
      dtStorageBuffer:        VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
      dtCombinedImageSampler: VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
      dtSampledImage:         VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
      dtSampler:              VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_SAMPLER;
      dtStorageImage:         VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    end;

    VkBindingFlags[I] := 0;
    if Bindings[I].BindingFlags <> [] then
    begin
      HasAnyBindingFlags := True;
      if dbfPartiallyBound in Bindings[I].BindingFlags then
        VkBindingFlags[I] := VkBindingFlags[I] or VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT;
      if dbfUpdateUnusedWhilePending in Bindings[I].BindingFlags then
        VkBindingFlags[I] := VkBindingFlags[I] or VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT;
      if dbfUpdateAfterBind in Bindings[I].BindingFlags then
      begin
        VkBindingFlags[I] := VkBindingFlags[I] or VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;
        FUsesUpdateAfterBind := True;
      end;
      if dbfVariableDescriptorCount in Bindings[I].BindingFlags then
        VkBindingFlags[I] := VkBindingFlags[I] or VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT;
    end;
  end;

  FillChar(LayoutInfo, SizeOf(LayoutInfo), 0);
  LayoutInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
  if FUsesUpdateAfterBind then
    LayoutInfo.flags := VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT;
  LayoutInfo.bindingCount := Length(VkBindings);
  if Length(VkBindings) > 0 then
    LayoutInfo.pBindings := @VkBindings[0];

  if HasAnyBindingFlags and (Length(VkBindingFlags) > 0) then
  begin
    FillChar(BindingFlagsInfo, SizeOf(BindingFlagsInfo), 0);
    BindingFlagsInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO;
    BindingFlagsInfo.bindingCount := Length(VkBindingFlags);
    BindingFlagsInfo.pBindingFlags := @VkBindingFlags[0];
    LayoutInfo.pNext := @BindingFlagsInfo;
  end;

  if (ADevice <> nil) and (ADevice.Handle <> nil) and Assigned(vkCreateDescriptorSetLayout) then
    CheckVk(vkCreateDescriptorSetLayout(ADevice.Handle, @LayoutInfo, nil, @FHandle), 'vkCreateDescriptorSetLayout')
  else
    FHandle := VkDescriptorSetLayout(PtrUInt(Self));
end;

destructor TVulkanRHIDescriptorSetLayout.Destroy;
begin
  if (FHandle <> VK_NULL_HANDLE) and (Device <> nil) and
     (TVulkanRHIDevice(Device).Handle <> nil) and Assigned(vkDestroyDescriptorSetLayout) then
    vkDestroyDescriptorSetLayout(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  FHandle := VK_NULL_HANDLE;
  inherited;
end;

function TVulkanRHIDescriptorSet.VulkanDevice: TVulkanRHIDevice;
begin
  Result := TVulkanRHIDevice(Device);
end;

constructor TVulkanRHIDescriptorSet.Create(const ADevice: TVulkanRHIDevice;
  const ALayout: TVulkanRHIDescriptorSetLayout; const AIsTransient: Boolean);
var
  SetLayoutHandle: VkDescriptorSetLayout;
  PoolAlloc: TVulkanDescriptorPoolAllocator;
begin
  inherited Create(ADevice, '');
  FLayout := ALayout;
  FIsTransient := AIsTransient;
  if ALayout <> nil then
    SetLayoutHandle := ALayout.Handle
  else
    SetLayoutHandle := VK_NULL_HANDLE;

  PoolAlloc := nil;
  if ADevice <> nil then
  begin
    if AIsTransient then
      PoolAlloc := ADevice.GetTransientDescriptorAllocator(ADevice.FrameIndex)
    else
      PoolAlloc := ADevice.PersistentDescriptorAllocator;
  end;

  if PoolAlloc <> nil then
    FHandle := PoolAlloc.AllocateDescriptorSet(SetLayoutHandle, FOwnerPool)
  else
  begin
    FOwnerPool := VK_NULL_HANDLE;
    FHandle := VkDescriptorSet(PtrUInt(Self));
  end;
end;

destructor TVulkanRHIDescriptorSet.Destroy;
begin
  if (not FIsTransient) and (VulkanDevice <> nil) and (FHandle <> VK_NULL_HANDLE) then
    VulkanDevice.DeferOrDestroyDescriptorSet(FOwnerPool, FHandle);
  FHandle := VK_NULL_HANDLE;
  FOwnerPool := VK_NULL_HANDLE;
  inherited;
end;

procedure TVulkanRHIDescriptorSet.BindUniformBuffer(const Binding: Cardinal;
  const Buffer: TRHIBuffer; const Offset, Range: PtrUInt);
var
  Idx, WriteIdx: Integer;
begin
  if Buffer = nil then Exit;
  Idx := Length(FBufferInfos);
  SetLength(FBufferInfos, Idx + 1);
  FillChar(FBufferInfos[Idx], SizeOf(VkDescriptorBufferInfo), 0);
  FBufferInfos[Idx].buffer := (Buffer as TVulkanRHIBuffer).Handle;
  FBufferInfos[Idx].offset := Offset;
  if Range > 0 then
    FBufferInfos[Idx].range := Range
  else
    FBufferInfos[Idx].range := Buffer.Desc.Size - Offset;

  WriteIdx := Length(FPendingWrites);
  SetLength(FPendingWrites, WriteIdx + 1);
  SetLength(FPendingWriteInfoIndices, WriteIdx + 1);
  FPendingWriteInfoIndices[WriteIdx] := Idx;
  FillChar(FPendingWrites[WriteIdx], SizeOf(VkWriteDescriptorSet), 0);
  FPendingWrites[WriteIdx].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  FPendingWrites[WriteIdx].dstSet := FHandle;
  FPendingWrites[WriteIdx].dstBinding := Binding;
  FPendingWrites[WriteIdx].dstArrayElement := 0;
  FPendingWrites[WriteIdx].descriptorCount := 1;
  FPendingWrites[WriteIdx].descriptorType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
end;

procedure TVulkanRHIDescriptorSet.BindStorageBuffer(const Binding: Cardinal;
  const Buffer: TRHIBuffer; const Offset, Range: PtrUInt);
var
  Idx, WriteIdx: Integer;
begin
  if Buffer = nil then Exit;
  Idx := Length(FBufferInfos);
  SetLength(FBufferInfos, Idx + 1);
  FillChar(FBufferInfos[Idx], SizeOf(VkDescriptorBufferInfo), 0);
  FBufferInfos[Idx].buffer := (Buffer as TVulkanRHIBuffer).Handle;
  FBufferInfos[Idx].offset := Offset;
  if Range > 0 then
    FBufferInfos[Idx].range := Range
  else
    FBufferInfos[Idx].range := Buffer.Desc.Size - Offset;

  WriteIdx := Length(FPendingWrites);
  SetLength(FPendingWrites, WriteIdx + 1);
  SetLength(FPendingWriteInfoIndices, WriteIdx + 1);
  FPendingWriteInfoIndices[WriteIdx] := Idx;
  FillChar(FPendingWrites[WriteIdx], SizeOf(VkWriteDescriptorSet), 0);
  FPendingWrites[WriteIdx].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  FPendingWrites[WriteIdx].dstSet := FHandle;
  FPendingWrites[WriteIdx].dstBinding := Binding;
  FPendingWrites[WriteIdx].dstArrayElement := 0;
  FPendingWrites[WriteIdx].descriptorCount := 1;
  FPendingWrites[WriteIdx].descriptorType := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
end;

procedure TVulkanRHIDescriptorSet.BindTexture(const Binding: Cardinal;
  const Texture: TRHITexture; const Sampler: TRHISampler);
begin
  BindTextureAtIndex(Binding, 0, Texture, Sampler);
end;

procedure TVulkanRHIDescriptorSet.BindTextureAtIndex(const Binding, ArrayElement: Cardinal;
  const Texture: TRHITexture; const Sampler: TRHISampler);
var
  Idx, WriteIdx: Integer;
begin
  if Texture = nil then Exit;
  Idx := Length(FImageInfos);
  SetLength(FImageInfos, Idx + 1);
  FillChar(FImageInfos[Idx], SizeOf(VkDescriptorImageInfo), 0);
  if Sampler <> nil then
    FImageInfos[Idx].sampler := (Sampler as TVulkanRHISampler).Handle
  else
    FImageInfos[Idx].sampler := VK_NULL_HANDLE;
  FImageInfos[Idx].imageView := (Texture as TVulkanRHITexture).ImageView;
  FImageInfos[Idx].imageLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

  WriteIdx := Length(FPendingWrites);
  SetLength(FPendingWrites, WriteIdx + 1);
  SetLength(FPendingWriteInfoIndices, WriteIdx + 1);
  FPendingWriteInfoIndices[WriteIdx] := Idx;
  FillChar(FPendingWrites[WriteIdx], SizeOf(VkWriteDescriptorSet), 0);
  FPendingWrites[WriteIdx].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
  FPendingWrites[WriteIdx].dstSet := FHandle;
  FPendingWrites[WriteIdx].dstBinding := Binding;
  FPendingWrites[WriteIdx].dstArrayElement := ArrayElement;
  FPendingWrites[WriteIdx].descriptorCount := 1;
  FPendingWrites[WriteIdx].descriptorType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
end;

procedure TVulkanRHIDescriptorSet.Update;
var
  I, InfoIdx: Integer;
begin
  if Length(FPendingWrites) > 0 then
  begin
    for I := 0 to High(FPendingWrites) do
    begin
      InfoIdx := FPendingWriteInfoIndices[I];
      if FPendingWrites[I].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER then
        FPendingWrites[I].pImageInfo := @FImageInfos[InfoIdx]
      else
        FPendingWrites[I].pBufferInfo := @FBufferInfos[InfoIdx];
    end;
    if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and Assigned(vkUpdateDescriptorSets) then
      vkUpdateDescriptorSets(VulkanDevice.Handle, Length(FPendingWrites), @FPendingWrites[0], 0, nil);
    Inc(FUpdateCount);
    SetLength(FPendingWrites, 0);
    SetLength(FPendingWriteInfoIndices, 0);
    SetLength(FBufferInfos, 0);
    SetLength(FImageInfos, 0);
  end;
end;

constructor TVulkanRHIPipeline.Create(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHIGraphicsPipelineDesc);
var
  SetLayouts: array of VkDescriptorSetLayout;
  PushRange: VkPushConstantRange;
  LayoutInfo: VkPipelineLayoutCreateInfo;
  Stages: array[0..2] of VkPipelineShaderStageCreateInfo;
  StageCount: Cardinal;
  VertexBindings: array of VkVertexInputBindingDescription;
  VertexAttrs: array of VkVertexInputAttributeDescription;
  VertexInputInfo: VkPipelineVertexInputStateCreateInfo;
  InputAssembly: VkPipelineInputAssemblyStateCreateInfo;
  ViewportState: VkPipelineViewportStateCreateInfo;
  Rasterizer: VkPipelineRasterizationStateCreateInfo;
  Multisampling: VkPipelineMultisampleStateCreateInfo;
  DepthStencil: VkPipelineDepthStencilStateCreateInfo;
  BlendAttachments: array of VkPipelineColorBlendAttachmentState;
  ColorBlending: VkPipelineColorBlendStateCreateInfo;
  DynamicStates: array[0..8] of VkDynamicState;
  DynamicStateCount: Cardinal;
  DynamicStateInfo: VkPipelineDynamicStateCreateInfo;
  ColorFormats: array of VkFormat;
  RenderingInfo: VkPipelineRenderingCreateInfoKHR;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
  LibHandles: array[0..3] of VkPipeline;
  LinkInfo: VkPipelineLibraryCreateInfoKHR;
  I: Integer;
begin
  inherited Create(ADevice, ADesc);
  if (ADevice <> nil) and (not ADevice.SupportsDynamicRendering) then
    FRenderPass := ADevice.GetOrCreateFallbackRenderPass(
      ADesc.ColorAttachmentFormats, ADesc.DepthAttachmentFormat, ADesc.SampleCount);
  if ADevice = nil then Exit;

  { 1. Construct VkPipelineLayout from ADesc.DescriptorSetLayouts and PushConstants }
  if ADevice.Handle <> nil then
  begin
    SetLength(SetLayouts, Length(ADesc.DescriptorSetLayouts));
    for I := 0 to High(ADesc.DescriptorSetLayouts) do
      if ADesc.DescriptorSetLayouts[I] <> nil then
        SetLayouts[I] := (ADesc.DescriptorSetLayouts[I] as TVulkanRHIDescriptorSetLayout).Handle
      else
        SetLayouts[I] := VK_NULL_HANDLE;

    FillChar(LayoutInfo, SizeOf(LayoutInfo), 0);
    LayoutInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    if ADevice.SupportsGraphicsPipelineLibrary then
      LayoutInfo.flags := VK_PIPELINE_LAYOUT_CREATE_INDEPENDENT_SETS_BIT_EXT;
    LayoutInfo.setLayoutCount := Length(SetLayouts);
    if Length(SetLayouts) > 0 then
      LayoutInfo.pSetLayouts := @SetLayouts[0];

    if ADesc.PushConstantSize > 0 then
    begin
      FillChar(PushRange, SizeOf(PushRange), 0);
      PushRange.stageFlags := RHIToVkShaderStageFlags(ADesc.PushConstantStages);
      if PushRange.stageFlags = 0 then
        PushRange.stageFlags := VK_SHADER_STAGE_ALL_GRAPHICS;
      PushRange.offset := 0;
      PushRange.size := ADesc.PushConstantSize;
      LayoutInfo.pushConstantRangeCount := 1;
      LayoutInfo.pPushConstantRanges := @PushRange;
    end;

    CheckVk(vkCreatePipelineLayout(ADevice.Handle, @LayoutInfo, nil, @FPipelineLayout), 'vkCreatePipelineLayout');
  end;

  { Fast-Link Path via VK_EXT_graphics_pipeline_library }
  if ADevice.SupportsGraphicsPipelineLibrary then
  begin
    FVertexInputLibrary := ADevice.GetOrCreateVertexInputLibrary(ADesc);
    FPreRasterizationLibrary := ADevice.GetOrCreatePreRasterizationLibrary(ADesc, FPipelineLayout, FRenderPass);
    FFragmentShaderLibrary := ADevice.GetOrCreateFragmentShaderLibrary(ADesc, FPipelineLayout, FRenderPass);
    FFragmentOutputLibrary := ADevice.GetOrCreateFragmentOutputLibrary(ADesc, FRenderPass);
    FLinkedFromLibraries := True;
    Inc(ADevice.FGPLFastLinkedPipelineCount);

    if ADevice.Handle = nil then
    begin
      FHandle := VkPipeline($50000000 + ADevice.FGPLFastLinkedPipelineCount);
      Exit;
    end;

    LibHandles[0] := FVertexInputLibrary;
    LibHandles[1] := FPreRasterizationLibrary;
    LibHandles[2] := FFragmentShaderLibrary;
    LibHandles[3] := FFragmentOutputLibrary;

    FillChar(LinkInfo, SizeOf(LinkInfo), 0);
    LinkInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_LIBRARY_CREATE_INFO_KHR;
    LinkInfo.libraryCount := 4;
    LinkInfo.pLibraries := @LibHandles[0];

    FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
    PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    PipelineInfo.pNext := @LinkInfo;
    if not ADevice.SupportsGPLFastLinking then
      PipelineInfo.flags := VK_PIPELINE_CREATE_LINK_TIME_OPTIMIZATION_BIT_EXT;
    PipelineInfo.layout := FPipelineLayout;
    if not ADevice.SupportsDynamicRendering then
      PipelineInfo.renderPass := FRenderPass;

    if (FPreRasterizationLibrary <> VK_NULL_HANDLE) and
       (FFragmentShaderLibrary <> VK_NULL_HANDLE) then
      CheckVk(vkCreateGraphicsPipelines(ADevice.Handle, ADevice.PipelineCache, 1, @PipelineInfo, nil, @FHandle), 'vkCreateGraphicsPipelines(GPL-Link)');
    Exit;
  end;

  if ADevice.Handle = nil then
  begin
    FHandle := VkPipeline(PtrUInt(Self));
    Exit;
  end;

  { 2. Shader Stages }
  StageCount := 0;
  FillChar(Stages, SizeOf(Stages), 0);
  if (ADesc.VertexShader <> nil) and ((ADesc.VertexShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_VERTEX_BIT;
    Stages[StageCount].module := (ADesc.VertexShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;
  if (ADesc.FragmentShader <> nil) and ((ADesc.FragmentShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_FRAGMENT_BIT;
    Stages[StageCount].module := (ADesc.FragmentShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;
  if (ADesc.GeometryShader <> nil) and ((ADesc.GeometryShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_GEOMETRY_BIT;
    Stages[StageCount].module := (ADesc.GeometryShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;

  { 3. Vertex Input Layout }
  SetLength(VertexBindings, Length(ADesc.VertexInput.Bindings));
  for I := 0 to High(ADesc.VertexInput.Bindings) do
  begin
    VertexBindings[I].binding := ADesc.VertexInput.Bindings[I].Binding;
    VertexBindings[I].stride := ADesc.VertexInput.Bindings[I].Stride;
    if ADesc.VertexInput.Bindings[I].PerInstance then
      VertexBindings[I].inputRate := VK_VERTEX_INPUT_RATE_INSTANCE
    else
      VertexBindings[I].inputRate := VK_VERTEX_INPUT_RATE_VERTEX;
  end;

  SetLength(VertexAttrs, Length(ADesc.VertexInput.Attributes));
  for I := 0 to High(ADesc.VertexInput.Attributes) do
  begin
    VertexAttrs[I].location := ADesc.VertexInput.Attributes[I].Location;
    VertexAttrs[I].binding := ADesc.VertexInput.Attributes[I].Binding;
    VertexAttrs[I].format := RHIToVkVertexFormat(ADesc.VertexInput.Attributes[I].Format);
    VertexAttrs[I].offset := ADesc.VertexInput.Attributes[I].Offset;
  end;

  FillChar(VertexInputInfo, SizeOf(VertexInputInfo), 0);
  VertexInputInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
  VertexInputInfo.vertexBindingDescriptionCount := Length(VertexBindings);
  if Length(VertexBindings) > 0 then
    VertexInputInfo.pVertexBindingDescriptions := @VertexBindings[0];
  VertexInputInfo.vertexAttributeDescriptionCount := Length(VertexAttrs);
  if Length(VertexAttrs) > 0 then
    VertexInputInfo.pVertexAttributeDescriptions := @VertexAttrs[0];

  { 4. Fixed-function states }
  FillChar(InputAssembly, SizeOf(InputAssembly), 0);
  InputAssembly.sType := VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  InputAssembly.topology := RHIToVkTopology(ADesc.Topology);
  InputAssembly.primitiveRestartEnable := VK_FALSE;

  FillChar(ViewportState, SizeOf(ViewportState), 0);
  ViewportState.sType := VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  ViewportState.viewportCount := 1;
  ViewportState.scissorCount := 1;

  FillChar(Rasterizer, SizeOf(Rasterizer), 0);
  Rasterizer.sType := VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  Rasterizer.depthClampEnable := Ord(ADesc.Rasterizer.DepthClampEnable);
  Rasterizer.rasterizerDiscardEnable := VK_FALSE;
  Rasterizer.polygonMode := RHIToVkPolygonMode(ADesc.Rasterizer.PolygonMode);
  Rasterizer.cullMode := RHIToVkCullMode(ADesc.Rasterizer.CullMode);
  Rasterizer.frontFace := RHIToVkFrontFace(ADesc.Rasterizer.FrontFace);
  Rasterizer.depthBiasEnable := Ord(ADesc.Rasterizer.DepthBiasEnable);
  Rasterizer.lineWidth := 1.0;

  FillChar(Multisampling, SizeOf(Multisampling), 0);
  Multisampling.sType := VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  Multisampling.rasterizationSamples := RHIToVkSampleCountFlags(ADesc.SampleCount);

  FillChar(DepthStencil, SizeOf(DepthStencil), 0);
  DepthStencil.sType := VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
  DepthStencil.depthTestEnable := Ord(ADesc.DepthStencil.DepthTestEnable);
  DepthStencil.depthWriteEnable := Ord(ADesc.DepthStencil.DepthWriteEnable);
  DepthStencil.depthCompareOp := RHIToVkCompareOp(ADesc.DepthStencil.DepthCompareOp);
  DepthStencil.stencilTestEnable := Ord(ADesc.DepthStencil.StencilTestEnable);
  DepthStencil.front := RHIToVkStencilOpState(ADesc.DepthStencil.FrontStencil);
  DepthStencil.back := RHIToVkStencilOpState(ADesc.DepthStencil.BackStencil);

  SetLength(BlendAttachments, Max(1, Length(ADesc.ColorAttachmentFormats)));
  for I := 0 to High(BlendAttachments) do
  begin
    FillChar(BlendAttachments[I], SizeOf(VkPipelineColorBlendAttachmentState), 0);
    BlendAttachments[I].blendEnable := Ord(ADesc.BlendState.BlendEnable);
    BlendAttachments[I].srcColorBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.SrcColorBlendFactor);
    BlendAttachments[I].dstColorBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.DstColorBlendFactor);
    BlendAttachments[I].colorBlendOp := RHIToVkBlendOp(ADesc.BlendState.ColorBlendOp);
    BlendAttachments[I].srcAlphaBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.SrcAlphaBlendFactor);
    BlendAttachments[I].dstAlphaBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.DstAlphaBlendFactor);
    BlendAttachments[I].alphaBlendOp := RHIToVkBlendOp(ADesc.BlendState.AlphaBlendOp);
    if ADesc.BlendState.DisableColorWrites then
      BlendAttachments[I].colorWriteMask := 0
    else if ADesc.BlendState.ColorWriteMask <> 0 then
      BlendAttachments[I].colorWriteMask := ADesc.BlendState.ColorWriteMask
    else
      BlendAttachments[I].colorWriteMask := $0F;
  end;

  FillChar(ColorBlending, SizeOf(ColorBlending), 0);
  ColorBlending.sType := VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  ColorBlending.attachmentCount := Length(BlendAttachments);
  if Length(BlendAttachments) > 0 then
    ColorBlending.pAttachments := @BlendAttachments[0];

  DynamicStates[0] := VK_DYNAMIC_STATE_VIEWPORT;
  DynamicStates[1] := VK_DYNAMIC_STATE_SCISSOR;
  DynamicStateCount := 2;
  if ADesc.Rasterizer.DepthBiasEnable then
  begin
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_DEPTH_BIAS;
    Inc(DynamicStateCount);
  end;
  if ADevice.SupportsExtendedDynamicState then
  begin
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_CULL_MODE;
    DynamicStates[DynamicStateCount + 1] := VK_DYNAMIC_STATE_FRONT_FACE;
    DynamicStates[DynamicStateCount + 2] := VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY;
    DynamicStates[DynamicStateCount + 3] := VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE;
    DynamicStates[DynamicStateCount + 4] := VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE;
    DynamicStates[DynamicStateCount + 5] := VK_DYNAMIC_STATE_DEPTH_COMPARE_OP;
    Inc(DynamicStateCount, 6);
  end;
  FillChar(DynamicStateInfo, SizeOf(DynamicStateInfo), 0);
  DynamicStateInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  DynamicStateInfo.dynamicStateCount := DynamicStateCount;
  DynamicStateInfo.pDynamicStates := @DynamicStates[0];

  { 5. Set up VkPipelineRenderingCreateInfoKHR (Vulkan 1.3 Dynamic Rendering)
    or fallback VkRenderPass (Vulkan 1.1/1.2 without VK_KHR_dynamic_rendering) }
  SetLength(ColorFormats, Length(ADesc.ColorAttachmentFormats));
  for I := 0 to High(ADesc.ColorAttachmentFormats) do
    ColorFormats[I] := RHIToVkFormat(ADesc.ColorAttachmentFormats[I]);

  FillChar(RenderingInfo, SizeOf(RenderingInfo), 0);
  RenderingInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;
  RenderingInfo.colorAttachmentCount := Length(ColorFormats);
  if Length(ColorFormats) > 0 then
    RenderingInfo.pColorAttachmentFormats := @ColorFormats[0];
  RenderingInfo.depthAttachmentFormat := RHIToVkFormat(ADesc.DepthAttachmentFormat);

  { 6. Create Graphics Pipeline }
  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  if ADevice.SupportsDynamicRendering then
  begin
    PipelineInfo.pNext := @RenderingInfo;
    PipelineInfo.renderPass := VK_NULL_HANDLE;
  end else
  begin
    PipelineInfo.pNext := nil;
    PipelineInfo.renderPass := FRenderPass;
    PipelineInfo.subpass := 0;
  end;
  PipelineInfo.stageCount := StageCount;
  if StageCount > 0 then
    PipelineInfo.pStages := @Stages[0];
  PipelineInfo.pVertexInputState := @VertexInputInfo;
  PipelineInfo.pInputAssemblyState := @InputAssembly;
  PipelineInfo.pViewportState := @ViewportState;
  PipelineInfo.pRasterizationState := @Rasterizer;
  PipelineInfo.pMultisampleState := @Multisampling;
  PipelineInfo.pDepthStencilState := @DepthStencil;
  PipelineInfo.pColorBlendState := @ColorBlending;
  PipelineInfo.pDynamicState := @DynamicStateInfo;
  PipelineInfo.layout := FPipelineLayout;

  if StageCount > 0 then
    CheckVk(vkCreateGraphicsPipelines(ADevice.Handle, ADevice.PipelineCache, 1, @PipelineInfo, nil, @FHandle), 'vkCreateGraphicsPipelines');
end;

destructor TVulkanRHIPipeline.Destroy;
begin
  if (Device <> nil) and (TVulkanRHIDevice(Device).Handle <> nil) then
  begin
    if (FHandle <> VK_NULL_HANDLE) and Assigned(vkDestroyPipeline) then
      vkDestroyPipeline(TVulkanRHIDevice(Device).Handle, FHandle, nil);
    if (FPipelineLayout <> VK_NULL_HANDLE) and Assigned(vkDestroyPipelineLayout) then
      vkDestroyPipelineLayout(TVulkanRHIDevice(Device).Handle, FPipelineLayout, nil);
  end;
  inherited;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHIComputePipeline (Phase 6.5)                                        }
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHIComputePipeline.Create(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHIComputePipelineDesc; const AOwnsHandle: Boolean);
var
  SetLayouts: array of VkDescriptorSetLayout;
  PushRange: VkPushConstantRange;
  LayoutInfo: VkPipelineLayoutCreateInfo;
  ComputeInfo: VkComputePipelineCreateInfo;
  I: Integer;
begin
  inherited Create(ADevice, ADesc);
  FOwnsHandle := AOwnsHandle;
  if ADevice = nil then Exit;

  if ADevice.Handle = nil then
  begin
    FPipelineLayout := VkPipelineLayout(PtrUInt(Self));
    FHandle := VkPipeline(PtrUInt(Self));
    Exit;
  end;

  SetLength(SetLayouts, Length(ADesc.DescriptorSetLayouts));
  for I := 0 to High(ADesc.DescriptorSetLayouts) do
    if ADesc.DescriptorSetLayouts[I] <> nil then
      SetLayouts[I] := (ADesc.DescriptorSetLayouts[I] as TVulkanRHIDescriptorSetLayout).Handle
    else
      SetLayouts[I] := VK_NULL_HANDLE;

  FillChar(LayoutInfo, SizeOf(LayoutInfo), 0);
  LayoutInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  LayoutInfo.setLayoutCount := Length(SetLayouts);
  if Length(SetLayouts) > 0 then
    LayoutInfo.pSetLayouts := @SetLayouts[0];

  if ADesc.PushConstantSize > 0 then
  begin
    FillChar(PushRange, SizeOf(PushRange), 0);
    PushRange.stageFlags := RHIToVkShaderStageFlags(ADesc.PushConstantStages);
    if PushRange.stageFlags = 0 then
      PushRange.stageFlags := VK_SHADER_STAGE_COMPUTE_BIT;
    PushRange.offset := 0;
    PushRange.size := ADesc.PushConstantSize;
    LayoutInfo.pushConstantRangeCount := 1;
    LayoutInfo.pPushConstantRanges := @PushRange;
  end;

  CheckVk(vkCreatePipelineLayout(ADevice.Handle, @LayoutInfo, nil, @FPipelineLayout),
    'vkCreatePipelineLayout(Compute)');

  if (ADesc.ComputeShader <> nil) and
     ((ADesc.ComputeShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) and
     Assigned(vkCreateComputePipelines) then
  begin
    FillChar(ComputeInfo, SizeOf(ComputeInfo), 0);
    ComputeInfo.sType := VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    ComputeInfo.stage.sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    ComputeInfo.stage.stage := VK_SHADER_STAGE_COMPUTE_BIT;
    ComputeInfo.stage.module := (ADesc.ComputeShader as TVulkanRHIShaderModule).Handle;
    ComputeInfo.stage.pName := 'main';
    ComputeInfo.layout := FPipelineLayout;
    CheckVk(vkCreateComputePipelines(ADevice.Handle, ADevice.PipelineCache, 1,
      @ComputeInfo, nil, @FHandle), 'vkCreateComputePipelines');
  end;
end;

destructor TVulkanRHIComputePipeline.Destroy;
begin
  if FOwnsHandle and (Device <> nil) and (TVulkanRHIDevice(Device).Handle <> nil) then
  begin
    if (FHandle <> VK_NULL_HANDLE) and Assigned(vkDestroyPipeline) then
      vkDestroyPipeline(TVulkanRHIDevice(Device).Handle, FHandle, nil);
    if (FPipelineLayout <> VK_NULL_HANDLE) and Assigned(vkDestroyPipelineLayout) then
      vkDestroyPipelineLayout(TVulkanRHIDevice(Device).Handle, FPipelineLayout, nil);
  end;
  FHandle := VK_NULL_HANDLE;
  FPipelineLayout := VK_NULL_HANDLE;
  inherited;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHIQueryPool (Phase 6.7)                                              }
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHIQueryPool.Create(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHIQueryPoolDesc);
var
  PoolInfo: VkQueryPoolCreateInfo;
  Count: Cardinal;
begin
  inherited Create(ADevice, ADesc);
  Count := Max(Cardinal(1), ADesc.QueryCount);
  SetLength(FSimulatedResults, Count);
  SetLength(FQueryWritten, Count);

  if (ADevice <> nil) and (ADevice.Handle <> nil) and Assigned(vkCreateQueryPool) then
  begin
    FillChar(PoolInfo, SizeOf(PoolInfo), 0);
    PoolInfo.sType := VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO;
    if ADesc.QueryType = qtTimestamp then
      PoolInfo.queryType := VK_QUERY_TYPE_TIMESTAMP
    else
      PoolInfo.queryType := VK_QUERY_TYPE_OCCLUSION;
    PoolInfo.queryCount := Count;
    CheckVk(vkCreateQueryPool(ADevice.Handle, @PoolInfo, nil, @FHandle), 'vkCreateQueryPool');
  end else
    FHandle := VkQueryPool(PtrUInt(Self));
end;

destructor TVulkanRHIQueryPool.Destroy;
begin
  if (FHandle <> VK_NULL_HANDLE) and (Device <> nil) and
     (TVulkanRHIDevice(Device).Handle <> nil) and Assigned(vkDestroyQueryPool) then
    vkDestroyQueryPool(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  FHandle := VK_NULL_HANDLE;
  inherited;
end;

procedure TVulkanRHIQueryPool.SetSimulatedResult(const AQueryIndex: Cardinal;
  const AValue: UInt64);
begin
  if AQueryIndex < Cardinal(Length(FSimulatedResults)) then
  begin
    FSimulatedResults[AQueryIndex] := AValue;
    FQueryWritten[AQueryIndex] := True;
  end;
end;

function TVulkanRHIQueryPool.IsQueryWritten(const AQueryIndex: Cardinal): Boolean;
begin
  if AQueryIndex < Cardinal(Length(FQueryWritten)) then
    Result := FQueryWritten[AQueryIndex]
  else
    Result := False;
end;

function TVulkanRHIQueryPool.GetResults(const FirstQuery, QueryCount: Cardinal;
  out Results: array of UInt64; const WaitForResults: Boolean): Boolean;
var
  I: Cardinal;
  Flags: VkQueryResultFlags;
  Res: VkResult;
begin
  if (QueryCount = 0) or (Cardinal(Length(Results)) < QueryCount) then
    Exit(False);

  for I := 0 to QueryCount - 1 do
    Results[I] := 0;

  if (Device <> nil) and (TVulkanRHIDevice(Device).Handle <> nil) and
     (FHandle <> VK_NULL_HANDLE) and Assigned(vkGetQueryPoolResults) then
  begin
    Flags := VK_QUERY_RESULT_64_BIT;
    if WaitForResults then
      Flags := Flags or VK_QUERY_RESULT_WAIT_BIT;
    Res := vkGetQueryPoolResults(
      TVulkanRHIDevice(Device).Handle, FHandle,
      FirstQuery, QueryCount,
      PtrUInt(QueryCount) * SizeOf(UInt64),
      @Results[0], SizeOf(UInt64), Flags);
    Result := Res = VK_SUCCESS;
    Exit;
  end;

  { Headless / unit-test path: return simulated results if all requested queries were written }
  if FirstQuery + QueryCount > Cardinal(Length(FSimulatedResults)) then
    Exit(False);

  Result := True;
  for I := 0 to QueryCount - 1 do
  begin
    if not FQueryWritten[FirstQuery + I] then
      Result := False;
    Results[I] := FSimulatedResults[FirstQuery + I];
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHICommandList                                                        }
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHICommandList.Create(const ADevice: TVulkanRHIDevice;
  const AQueueFamilyIndex: Cardinal; const ALevel: TRHICommandListLevel);
var
  PoolInfo: VkCommandPoolCreateInfo;
  AllocInfo: VkCommandBufferAllocateInfo;
begin
  inherited Create(ALevel);
  FDevice := ADevice;
  if (FDevice = nil) or (FDevice.Handle = nil) then
    Exit;

  FillChar(PoolInfo, SizeOf(PoolInfo), 0);
  PoolInfo.sType := VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
  PoolInfo.flags := VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
  PoolInfo.queueFamilyIndex := AQueueFamilyIndex;
  CheckVk(vkCreateCommandPool(FDevice.Handle, @PoolInfo, nil, @FCommandPool), 'vkCreateCommandPool');

  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  AllocInfo.commandPool := FCommandPool;
  if ALevel = cllSecondary then
    AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_SECONDARY
  else
    AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  AllocInfo.commandBufferCount := 1;
  CheckVk(vkAllocateCommandBuffers(FDevice.Handle, @AllocInfo, @FHandle), 'vkAllocateCommandBuffers');
end;

destructor TVulkanRHICommandList.Destroy;
begin
  if (FDevice <> nil) and (FDevice.Handle <> nil) and (FCommandPool <> VK_NULL_HANDLE) then
    vkDestroyCommandPool(FDevice.Handle, FCommandPool, nil);
  inherited;
end;

procedure TVulkanRHICommandList.BeginRecording;
var
  BeginInfo: VkCommandBufferBeginInfo;
  InheritanceInfo: VkCommandBufferInheritanceInfo;
begin
  if (FHandle <> nil) and Assigned(vkResetCommandBuffer) then
    CheckVk(vkResetCommandBuffer(FHandle, 0), 'vkResetCommandBuffer');
  FillChar(BeginInfo, SizeOf(BeginInfo), 0);
  BeginInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  BeginInfo.flags := VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  if FLevel = cllSecondary then
  begin
    BeginInfo.flags := BeginInfo.flags or VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT;
    FillChar(InheritanceInfo, SizeOf(InheritanceInfo), 0);
    InheritanceInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO;
    BeginInfo.pInheritanceInfo := @InheritanceInfo;
  end;
  if (FHandle <> nil) and Assigned(vkBeginCommandBuffer) then
    CheckVk(vkBeginCommandBuffer(FHandle, @BeginInfo), 'vkBeginCommandBuffer');
  FCurrentPipeline := nil;
  FCurrentComputePipeline := nil;
  FBarrierCount := 0;
  FSync2BarrierCount := 0;
  FComputeDispatchCount := 0;
  FDynamicStateChangeCount := 0;
  FIndirectDrawCallCount := 0;
  FIndirectCountDrawCallCount := 0;
  FLastEffectiveIndirectDrawCount := 0;
end;

procedure TVulkanRHICommandList.EndRecording;
begin
  if (FHandle <> nil) and Assigned(vkEndCommandBuffer) then
    CheckVk(vkEndCommandBuffer(FHandle), 'vkEndCommandBuffer');
end;

procedure TVulkanRHICommandList.TransitionTexture(const Texture: TRHITexture;
  const NewState: TRHIResourceState);
var
  VkTex: TVulkanRHITexture;
  Barrier: VkImageMemoryBarrier;
  Barrier2: VkImageMemoryBarrier2;
  DepInfo: VkDependencyInfo;
  SrcStage, DstStage: VkPipelineStageFlags;
begin
  if (Texture = nil) or (Texture.CurrentState = NewState) then
    Exit;

  VkTex := Texture as TVulkanRHITexture;
  if (FDevice <> nil) and FDevice.SupportsSynchronization2 then
  begin
    FillChar(Barrier2, SizeOf(Barrier2), 0);
    Barrier2.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2;
    RHIStateToVkLayoutAndAccess2(
      Texture.CurrentState, Barrier2.oldLayout, Barrier2.srcAccessMask, Barrier2.srcStageMask);
    RHIStateToVkLayoutAndAccess2(
      NewState, Barrier2.newLayout, Barrier2.dstAccessMask, Barrier2.dstStageMask);
    Barrier2.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    Barrier2.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    Barrier2.image := VkTex.Image;
    Barrier2.subresourceRange.aspectMask := VkTex.AspectMask;
    Barrier2.subresourceRange.baseMipLevel := 0;
    Barrier2.subresourceRange.levelCount := VkTex.Desc.MipLevels;
    Barrier2.subresourceRange.baseArrayLayer := 0;
    Barrier2.subresourceRange.layerCount := VkTex.Desc.DepthOrArrayLayers;

    FillChar(DepInfo, SizeOf(DepInfo), 0);
    DepInfo.sType := VK_STRUCTURE_TYPE_DEPENDENCY_INFO;
    DepInfo.imageMemoryBarrierCount := 1;
    DepInfo.pImageMemoryBarriers := @Barrier2;

    if (FHandle <> nil) and Assigned(vkCmdPipelineBarrier2) then
      vkCmdPipelineBarrier2(FHandle, @DepInfo);
    Inc(FBarrierCount);
    Inc(FSync2BarrierCount);
    Inc(FDevice.FSync2BarrierCount);
    Texture.CurrentState := NewState;
    Exit;
  end;

  FillChar(Barrier, SizeOf(Barrier), 0);
  Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  RHIStateToVkLayoutAndAccess(Texture.CurrentState, Barrier.oldLayout, Barrier.srcAccessMask, SrcStage);
  RHIStateToVkLayoutAndAccess(NewState, Barrier.newLayout, Barrier.dstAccessMask, DstStage);

  Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.image := VkTex.Image;
  Barrier.subresourceRange.aspectMask := VkTex.AspectMask;
  Barrier.subresourceRange.baseMipLevel := 0;
  Barrier.subresourceRange.levelCount := VkTex.Desc.MipLevels;
  Barrier.subresourceRange.baseArrayLayer := 0;
  Barrier.subresourceRange.layerCount := VkTex.Desc.DepthOrArrayLayers;

  if (FHandle <> nil) and Assigned(vkCmdPipelineBarrier) then
    vkCmdPipelineBarrier(FHandle, SrcStage, DstStage, 0, 0, nil, 0, nil, 1, @Barrier);
  Inc(FBarrierCount);
  Texture.CurrentState := NewState;
end;

procedure TVulkanRHICommandList.TransitionBuffer(const Buffer: TRHIBuffer;
  const OldState, NewState: TRHIResourceState);
var
  VkBuf: TVulkanRHIBuffer;
  BufBarrier: VkBufferMemoryBarrier;
  BufBarrier2: VkBufferMemoryBarrier2;
  DepInfo: VkDependencyInfo;
  SrcStage, DstStage: VkPipelineStageFlags;
begin
  if (Buffer = nil) or (OldState = NewState) then
    Exit;

  VkBuf := Buffer as TVulkanRHIBuffer;
  if (FDevice <> nil) and FDevice.SupportsSynchronization2 then
  begin
    FillChar(BufBarrier2, SizeOf(BufBarrier2), 0);
    BufBarrier2.sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2;
    RHIStateToVkBufferAccessAndStage2(OldState, BufBarrier2.srcAccessMask, BufBarrier2.srcStageMask);
    RHIStateToVkBufferAccessAndStage2(NewState, BufBarrier2.dstAccessMask, BufBarrier2.dstStageMask);
    BufBarrier2.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    BufBarrier2.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    BufBarrier2.buffer := VkBuf.Handle;
    BufBarrier2.offset := 0;
    BufBarrier2.size := VK_WHOLE_SIZE;

    FillChar(DepInfo, SizeOf(DepInfo), 0);
    DepInfo.sType := VK_STRUCTURE_TYPE_DEPENDENCY_INFO;
    DepInfo.bufferMemoryBarrierCount := 1;
    DepInfo.pBufferMemoryBarriers := @BufBarrier2;

    if (FHandle <> nil) and Assigned(vkCmdPipelineBarrier2) then
      vkCmdPipelineBarrier2(FHandle, @DepInfo);
    Inc(FBarrierCount);
    Inc(FSync2BarrierCount);
    Inc(FDevice.FSync2BarrierCount);
    Exit;
  end;

  FillChar(BufBarrier, SizeOf(BufBarrier), 0);
  BufBarrier.sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
  RHIStateToVkBufferAccessAndStage(OldState, BufBarrier.srcAccessMask, SrcStage);
  RHIStateToVkBufferAccessAndStage(NewState, BufBarrier.dstAccessMask, DstStage);
  BufBarrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  BufBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  BufBarrier.buffer := VkBuf.Handle;
  BufBarrier.offset := 0;
  BufBarrier.size := VK_WHOLE_SIZE;

  if (FHandle <> nil) and Assigned(vkCmdPipelineBarrier) then
    vkCmdPipelineBarrier(FHandle, SrcStage, DstStage, 0, 0, nil, 1, @BufBarrier, 0, nil);
  Inc(FBarrierCount);
end;

procedure TVulkanRHICommandList.GenerateMipmaps(const Texture: TRHITexture);
var
  VkTex: TVulkanRHITexture;
  Barrier: VkImageMemoryBarrier;
  Blit: VkImageBlit;
  MipWidth, MipHeight, NextWidth, NextHeight: Integer;
  I: Cardinal;
begin
  if (Texture = nil) or (Texture.Desc.MipLevels <= 1) or not Assigned(vkCmdBlitImage) then
    Exit;

  VkTex := Texture as TVulkanRHITexture;
  MipWidth := Integer(VkTex.Desc.Width);
  MipHeight := Integer(VkTex.Desc.Height);

  FillChar(Barrier, SizeOf(Barrier), 0);
  Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  Barrier.image := VkTex.Image;
  Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.subresourceRange.aspectMask := VkTex.AspectMask;
  Barrier.subresourceRange.baseArrayLayer := 0;
  Barrier.subresourceRange.layerCount := VkTex.Desc.DepthOrArrayLayers;
  Barrier.subresourceRange.levelCount := 1;

  for I := 1 to VkTex.Desc.MipLevels - 1 do
  begin
    Barrier.subresourceRange.baseMipLevel := I - 1;
    Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    Barrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    Barrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
    Barrier.dstAccessMask := VK_ACCESS_TRANSFER_READ_BIT;

    vkCmdPipelineBarrier(FHandle,
      VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
      0, 0, nil, 0, nil, 1, @Barrier);

    NextWidth := Max(1, MipWidth div 2);
    NextHeight := Max(1, MipHeight div 2);

    FillChar(Blit, SizeOf(Blit), 0);
    Blit.srcOffsets[1].x := MipWidth;
    Blit.srcOffsets[1].y := MipHeight;
    Blit.srcOffsets[1].z := 1;
    Blit.srcSubresource.aspectMask := VkTex.AspectMask;
    Blit.srcSubresource.mipLevel := I - 1;
    Blit.srcSubresource.baseArrayLayer := 0;
    Blit.srcSubresource.layerCount := VkTex.Desc.DepthOrArrayLayers;

    Blit.dstOffsets[1].x := NextWidth;
    Blit.dstOffsets[1].y := NextHeight;
    Blit.dstOffsets[1].z := 1;
    Blit.dstSubresource.aspectMask := VkTex.AspectMask;
    Blit.dstSubresource.mipLevel := I;
    Blit.dstSubresource.baseArrayLayer := 0;
    Blit.dstSubresource.layerCount := VkTex.Desc.DepthOrArrayLayers;

    vkCmdBlitImage(FHandle,
      VkTex.Image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      VkTex.Image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      1, @Blit, VK_FILTER_LINEAR);

    Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    Barrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    Barrier.srcAccessMask := VK_ACCESS_TRANSFER_READ_BIT;
    Barrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(FHandle,
      VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      0, 0, nil, 0, nil, 1, @Barrier);

    MipWidth := NextWidth;
    MipHeight := NextHeight;
  end;

  Barrier.subresourceRange.baseMipLevel := VkTex.Desc.MipLevels - 1;
  Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
  Barrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
  Barrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
  Barrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;

  vkCmdPipelineBarrier(FHandle,
    VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
    0, 0, nil, 0, nil, 1, @Barrier);

  Texture.CurrentState := rsShaderRead;
end;

procedure TVulkanRHICommandList.BeginRendering(const Info: TRHIRenderingInfo);
var
  RenderInfo: VkRenderingInfo;
  ColorAttachments: array of VkRenderingAttachmentInfo;
  DepthAttachment: VkRenderingAttachmentInfo;
  FallbackColorFormats: array of TRHIPixelFormat;
  FallbackDepthFormat: TRHIPixelFormat;
  FallbackViews: array of VkImageView;
  FallbackClears: array of VkClearValue;
  FallbackRP: VkRenderPass;
  FallbackFB: VkFramebuffer;
  RpBeginInfo: VkRenderPassBeginInfo;
  FbWidth, FbHeight, PassSampleCount: Cardinal;
  ColorLoadOp, DepthLoadOp: TRHIAttachmentLoadOp;
  ColorStoreOp, DepthStoreOp: TRHIAttachmentStoreOp;
  HasColorResolve, HasAnyResolve: Boolean;
  EffResolveMode: TRHIResolveMode;
  AttCount, ResolveBaseIdx, I: Integer;
begin
  { Flush any pending staged buffer/image uploads outside the render pass instance
    (VUID-vkCmdCopyBuffer-renderpass / VUID-vkCmdCopyBufferToImage-renderpass) }
  if (FDevice <> nil) and (FDevice.StagingUploader <> nil) and (Level = cllPrimary) then
    FDevice.StagingUploader.FlushPendingUploads(Self);

  if FDevice <> nil then
  begin
    if Length(Info.ColorAttachments) > 0 then
    begin
      if Info.ColorAttachments[0].ResolveTexture <> nil then
        FDevice.FActiveColorTarget := Info.ColorAttachments[0].ResolveTexture
      else
        FDevice.FActiveColorTarget := Info.ColorAttachments[0].Texture;
    end;
    if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
      FDevice.FActiveDepthTarget := Info.DepthAttachment.Texture;
  end;

  if (FDevice = nil) or (FDevice.Handle = nil) then
  begin
    for I := 0 to High(Info.ColorAttachments) do
      if Info.ColorAttachments[I].LoadOp = loClear then
      begin
        if Info.ColorAttachments[I].Texture is TVulkanRHITexture then
          TVulkanRHITexture(Info.ColorAttachments[I].Texture).SetHostClearColor(
            Info.ColorAttachments[I].ClearColor);
        if Info.ColorAttachments[I].ResolveTexture is TVulkanRHITexture then
          TVulkanRHITexture(Info.ColorAttachments[I].ResolveTexture).SetHostClearColor(
            Info.ColorAttachments[I].ClearColor);
      end;
    if Info.HasDepthAttachment and (Info.DepthAttachment.LoadOp = loClear) and
       (Info.DepthAttachment.Texture is TVulkanRHITexture) then
      TVulkanRHITexture(Info.DepthAttachment.Texture).SetHostClearDepth(
        Info.DepthAttachment.ClearDepth);
  end;

  if (FDevice <> nil) and (not FDevice.SupportsDynamicRendering) then
  begin
    SetLength(FallbackColorFormats, Length(Info.ColorAttachments));
    PassSampleCount := 1;
    if (Length(Info.ColorAttachments) > 0) and (Info.ColorAttachments[0].Texture <> nil) then
      PassSampleCount := Max(Cardinal(1), Info.ColorAttachments[0].Texture.Desc.SampleCount)
    else if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
      PassSampleCount := Max(Cardinal(1), Info.DepthAttachment.Texture.Desc.SampleCount);

    HasColorResolve := (PassSampleCount > 1) and
      (Length(Info.ColorAttachments) > 0) and
      (Info.ColorAttachments[0].ResolveTexture <> nil);

    AttCount := Length(Info.ColorAttachments);
    if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
      Inc(AttCount);
    ResolveBaseIdx := AttCount;
    if HasColorResolve then
      Inc(AttCount, Length(Info.ColorAttachments));

    SetLength(FallbackViews, AttCount);
    SetLength(FallbackClears, AttCount);

    FbWidth := Max(1, Info.RenderArea.Width);
    FbHeight := Max(1, Info.RenderArea.Height);

    for I := 0 to High(Info.ColorAttachments) do
    begin
      if Info.ColorAttachments[I].Texture <> nil then
      begin
        FallbackColorFormats[I] := Info.ColorAttachments[I].Texture.Desc.Format;
        FallbackViews[I] := (Info.ColorAttachments[I].Texture as TVulkanRHITexture).ImageView;
        FbWidth := Max(FbWidth, Info.ColorAttachments[I].Texture.Desc.Width);
        FbHeight := Max(FbHeight, Info.ColorAttachments[I].Texture.Desc.Height);
      end else
      begin
        FallbackColorFormats[I] := pfBGRA8_UNorm;
        FallbackViews[I] := VK_NULL_HANDLE;
      end;
      FillChar(FallbackClears[I], SizeOf(VkClearValue), 0);
      Move(Info.ColorAttachments[I].ClearColor.Data,
        FallbackClears[I].color.float32, SizeOf(Single) * 4);

      if HasColorResolve then
      begin
        if Info.ColorAttachments[I].Texture <> nil then
          TransitionTexture(Info.ColorAttachments[I].Texture, rsColorAttachment);
        if Info.ColorAttachments[I].ResolveTexture <> nil then
        begin
          TransitionTexture(Info.ColorAttachments[I].ResolveTexture, rsColorAttachment);
          FallbackViews[ResolveBaseIdx + I] :=
            (Info.ColorAttachments[I].ResolveTexture as TVulkanRHITexture).ImageView;
        end else
          FallbackViews[ResolveBaseIdx + I] := VK_NULL_HANDLE;
        FillChar(FallbackClears[ResolveBaseIdx + I], SizeOf(VkClearValue), 0);
      end;
    end;

    if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
    begin
      FallbackDepthFormat := Info.DepthAttachment.Texture.Desc.Format;
      FallbackViews[ResolveBaseIdx - 1] := (Info.DepthAttachment.Texture as TVulkanRHITexture).ImageView;
      FbWidth := Max(FbWidth, Info.DepthAttachment.Texture.Desc.Width);
      FbHeight := Max(FbHeight, Info.DepthAttachment.Texture.Desc.Height);
      FillChar(FallbackClears[ResolveBaseIdx - 1], SizeOf(VkClearValue), 0);
      FallbackClears[ResolveBaseIdx - 1].depthStencil.depth := Info.DepthAttachment.ClearDepth;
      FallbackClears[ResolveBaseIdx - 1].depthStencil.stencil := Info.DepthAttachment.ClearStencil;
    end else
      FallbackDepthFormat := pfUndefined;

    if Length(Info.ColorAttachments) > 0 then
    begin
      ColorLoadOp := Info.ColorAttachments[0].LoadOp;
      ColorStoreOp := Info.ColorAttachments[0].StoreOp;
    end else
    begin
      ColorLoadOp := loClear;
      ColorStoreOp := soStore;
    end;

    if Info.HasDepthAttachment then
    begin
      DepthLoadOp := Info.DepthAttachment.LoadOp;
      DepthStoreOp := Info.DepthAttachment.StoreOp;
    end else
    begin
      DepthLoadOp := loClear;
      DepthStoreOp := soStore;
    end;

    FallbackRP := FDevice.GetOrCreateFallbackRenderPass(
      FallbackColorFormats, FallbackDepthFormat, PassSampleCount,
      ColorLoadOp, DepthLoadOp, ColorStoreOp, DepthStoreOp, HasColorResolve);
    FallbackFB := FDevice.GetOrCreateFallbackFramebuffer(
      FallbackRP, FallbackViews, FbWidth, FbHeight);

    FillChar(RpBeginInfo, SizeOf(RpBeginInfo), 0);
    RpBeginInfo.sType := VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    RpBeginInfo.renderPass := FallbackRP;
    RpBeginInfo.framebuffer := FallbackFB;
    RpBeginInfo.renderArea.offset.x := Max(0, Info.RenderArea.Left);
    RpBeginInfo.renderArea.offset.y := Max(0, Info.RenderArea.Bottom);
    RpBeginInfo.renderArea.extent.width := Max(1, Info.RenderArea.Width);
    RpBeginInfo.renderArea.extent.height := Max(1, Info.RenderArea.Height);
    RpBeginInfo.clearValueCount := Length(FallbackClears);
    if Length(FallbackClears) > 0 then
      RpBeginInfo.pClearValues := @FallbackClears[0];

    FInFallbackRenderPass := True;
    Inc(FDevice.FFallbackRenderPassBeginCount);
    if HasColorResolve then
      Inc(FDevice.FMSAAResolvePassCount);
    if (FHandle <> nil) and Assigned(vkCmdBeginRenderPass) then
      vkCmdBeginRenderPass(FHandle, @RpBeginInfo, VK_SUBPASS_CONTENTS_INLINE);
    Exit;
  end;

  HasAnyResolve := False;
  SetLength(ColorAttachments, Length(Info.ColorAttachments));
  for I := 0 to High(Info.ColorAttachments) do
  begin
    FillChar(ColorAttachments[I], SizeOf(VkRenderingAttachmentInfo), 0);
    ColorAttachments[I].sType := VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
    if Info.ColorAttachments[I].Texture <> nil then
      ColorAttachments[I].imageView := (Info.ColorAttachments[I].Texture as TVulkanRHITexture).ImageView;
    ColorAttachments[I].imageLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    if Info.ColorAttachments[I].LoadOp = loClear then
      ColorAttachments[I].loadOp := VK_ATTACHMENT_LOAD_OP_CLEAR
    else if Info.ColorAttachments[I].LoadOp = loDontCare then
      ColorAttachments[I].loadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE
    else
      ColorAttachments[I].loadOp := VK_ATTACHMENT_LOAD_OP_LOAD;
    if Info.ColorAttachments[I].StoreOp = soDontCare then
      ColorAttachments[I].storeOp := VK_ATTACHMENT_STORE_OP_DONT_CARE
    else
      ColorAttachments[I].storeOp := VK_ATTACHMENT_STORE_OP_STORE;
    Move(Info.ColorAttachments[I].ClearColor.Data, ColorAttachments[I].clearValue.color.float32, SizeOf(Single) * 4);

    if (Info.ColorAttachments[I].ResolveTexture <> nil) and
       (Info.ColorAttachments[I].Texture <> nil) and
       (Info.ColorAttachments[I].Texture.Desc.SampleCount > 1) then
    begin
      TransitionTexture(Info.ColorAttachments[I].Texture, rsColorAttachment);
      TransitionTexture(Info.ColorAttachments[I].ResolveTexture, rsColorAttachment);
      EffResolveMode := Info.ColorAttachments[I].ResolveMode;
      if EffResolveMode = rmNone then
        EffResolveMode := rmAverage;
      ColorAttachments[I].resolveMode := RHIToVkResolveMode(EffResolveMode);
      ColorAttachments[I].resolveImageView :=
        (Info.ColorAttachments[I].ResolveTexture as TVulkanRHITexture).ImageView;
      ColorAttachments[I].resolveImageLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
      HasAnyResolve := True;
    end;
  end;

  FillChar(RenderInfo, SizeOf(RenderInfo), 0);
  RenderInfo.sType := VK_STRUCTURE_TYPE_RENDERING_INFO;
  RenderInfo.renderArea.offset.x := Info.RenderArea.Left;
  RenderInfo.renderArea.offset.y := Info.RenderArea.Bottom;
  RenderInfo.renderArea.extent.width := Info.RenderArea.Width;
  RenderInfo.renderArea.extent.height := Info.RenderArea.Height;
  RenderInfo.layerCount := 1;
  RenderInfo.colorAttachmentCount := Length(ColorAttachments);
  if Length(ColorAttachments) > 0 then
    RenderInfo.pColorAttachments := @ColorAttachments[0];

  if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
  begin
    FillChar(DepthAttachment, SizeOf(DepthAttachment), 0);
    DepthAttachment.sType := VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
    DepthAttachment.imageView := (Info.DepthAttachment.Texture as TVulkanRHITexture).ImageView;
    DepthAttachment.imageLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    if Info.DepthAttachment.LoadOp = loClear then
      DepthAttachment.loadOp := VK_ATTACHMENT_LOAD_OP_CLEAR
    else if Info.DepthAttachment.LoadOp = loDontCare then
      DepthAttachment.loadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE
    else
      DepthAttachment.loadOp := VK_ATTACHMENT_LOAD_OP_LOAD;
    if Info.DepthAttachment.StoreOp = soDontCare then
      DepthAttachment.storeOp := VK_ATTACHMENT_STORE_OP_DONT_CARE
    else
      DepthAttachment.storeOp := VK_ATTACHMENT_STORE_OP_STORE;
    DepthAttachment.clearValue.depthStencil.depth := Info.DepthAttachment.ClearDepth;
    DepthAttachment.clearValue.depthStencil.stencil := Info.DepthAttachment.ClearStencil;

    if (Info.DepthAttachment.ResolveTexture <> nil) and
       (Info.DepthAttachment.Texture.Desc.SampleCount > 1) then
    begin
      TransitionTexture(Info.DepthAttachment.Texture, rsDepthStencilWrite);
      TransitionTexture(Info.DepthAttachment.ResolveTexture, rsDepthStencilWrite);
      EffResolveMode := Info.DepthAttachment.ResolveMode;
      if EffResolveMode = rmNone then
        EffResolveMode := rmSampleZero;
      DepthAttachment.resolveMode := RHIToVkResolveMode(EffResolveMode);
      DepthAttachment.resolveImageView :=
        (Info.DepthAttachment.ResolveTexture as TVulkanRHITexture).ImageView;
      DepthAttachment.resolveImageLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
      HasAnyResolve := True;
    end;

    RenderInfo.pDepthAttachment := @DepthAttachment;
  end;

  if HasAnyResolve and (FDevice <> nil) then
    Inc(FDevice.FMSAAResolvePassCount);

  if (FHandle <> nil) and Assigned(vkCmdBeginRendering) then
    vkCmdBeginRendering(FHandle, @RenderInfo);
end;

procedure TVulkanRHICommandList.EndRendering;
begin
  if FInFallbackRenderPass then
  begin
    FInFallbackRenderPass := False;
    if (FHandle <> nil) and Assigned(vkCmdEndRenderPass) then
      vkCmdEndRenderPass(FHandle);
    Exit;
  end;
  if (FHandle <> nil) and Assigned(vkCmdEndRendering) then
    vkCmdEndRendering(FHandle);
end;

procedure TVulkanRHICommandList.ClearAttachments(const ClearColorBuf: Boolean; const ClearColor: TCastleColor;
  const ClearDepthBuf: Boolean; const ClearDepth: Single;
  const ClearStencilBuf: Boolean; const ClearStencil: Byte);
var
  ColorTarget, DepthTarget: TRHITexture;
begin
  if FDevice = nil then
    Exit;

  if (FDevice.Handle = nil) then
  begin
    if ClearColorBuf then
    begin
      ColorTarget := FDevice.GetSwapchainColorTexture;
      if ColorTarget is TVulkanRHITexture then
        TVulkanRHITexture(ColorTarget).SetHostClearColor(ClearColor);
    end;
    if ClearDepthBuf then
    begin
      DepthTarget := FDevice.GetSwapchainDepthTexture;
      if DepthTarget is TVulkanRHITexture then
        TVulkanRHITexture(DepthTarget).SetHostClearDepth(ClearDepth);
    end;
  end;
end;

procedure TVulkanRHICommandList.SetViewport(const ViewportRect: TFloatRectangle;
  const MinDepth, MaxDepth: Single);
var
  VkVP: VkViewport;
begin
  FDynamicViewportRect := ViewportRect;
  FDynamicMinDepth := MinDepth;
  FDynamicMaxDepth := MaxDepth;
  { Flip Y-axis using VK_KHR_maintenance1 negative height so CGE camera matrices
    and counter-clockwise winding orders work identically to OpenGL }
  VkVP.x := ViewportRect.Left;
  VkVP.y := ViewportRect.Bottom + ViewportRect.Height;
  VkVP.width := ViewportRect.Width;
  VkVP.height := -ViewportRect.Height;
  VkVP.minDepth := MinDepth;
  VkVP.maxDepth := MaxDepth;
  if (FHandle <> nil) and Assigned(vkCmdSetViewport) then
    vkCmdSetViewport(FHandle, 0, 1, @VkVP);
end;

procedure TVulkanRHICommandList.SetScissor(const ScissorRect: TRectangle);
var
  VkRect: VkRect2D;
begin
  FDynamicScissorRect := ScissorRect;
  VkRect.offset.x := Max(0, ScissorRect.Left);
  VkRect.offset.y := Max(0, ScissorRect.Bottom);
  VkRect.extent.width := ScissorRect.Width;
  VkRect.extent.height := ScissorRect.Height;
  if (FHandle <> nil) and Assigned(vkCmdSetScissor) then
    vkCmdSetScissor(FHandle, 0, 1, @VkRect);
end;

procedure TVulkanRHICommandList.SetDepthBias(const ConstantFactor, SlopeFactor: Single);
begin
  FDynamicDepthBiasConstant := ConstantFactor;
  FDynamicDepthBiasSlope := SlopeFactor;
  if (FHandle <> nil) and Assigned(vkCmdSetDepthBias) then
    vkCmdSetDepthBias(FHandle, ConstantFactor, 0.0, SlopeFactor);
end;

procedure TVulkanRHICommandList.SetCullMode(const CullMode: TRHICullMode);
begin
  FDynamicCullMode := CullMode;
  Inc(FDynamicStateChangeCount);
  if (FHandle <> nil) and Assigned(vkCmdSetCullMode) then
    vkCmdSetCullMode(FHandle, RHIToVkCullMode(CullMode));
end;

procedure TVulkanRHICommandList.SetFrontFace(const FrontFace: TRHIFrontFace);
begin
  FDynamicFrontFace := FrontFace;
  Inc(FDynamicStateChangeCount);
  if (FHandle <> nil) and Assigned(vkCmdSetFrontFace) then
    vkCmdSetFrontFace(FHandle, RHIToVkFrontFace(FrontFace));
end;

procedure TVulkanRHICommandList.SetDepthTestEnable(const Enable: Boolean);
begin
  FDynamicDepthTestEnable := Enable;
  Inc(FDynamicStateChangeCount);
  if (FHandle <> nil) and Assigned(vkCmdSetDepthTestEnable) then
    vkCmdSetDepthTestEnable(FHandle, Ord(Enable));
end;

procedure TVulkanRHICommandList.SetDepthWriteEnable(const Enable: Boolean);
begin
  FDynamicDepthWriteEnable := Enable;
  Inc(FDynamicStateChangeCount);
  if (FHandle <> nil) and Assigned(vkCmdSetDepthWriteEnable) then
    vkCmdSetDepthWriteEnable(FHandle, Ord(Enable));
end;

procedure TVulkanRHICommandList.SetDepthCompareOp(const CompareOp: TRHICompareOp);
begin
  FDynamicDepthCompareOp := CompareOp;
  Inc(FDynamicStateChangeCount);
  if (FHandle <> nil) and Assigned(vkCmdSetDepthCompareOp) then
    vkCmdSetDepthCompareOp(FHandle, RHIToVkCompareOp(CompareOp));
end;

procedure TVulkanRHICommandList.SetPrimitiveTopology(const Topology: TRHIPrimitiveTopology);
begin
  FDynamicPrimitiveTopology := Topology;
  Inc(FDynamicStateChangeCount);
  if (FHandle <> nil) and Assigned(vkCmdSetPrimitiveTopology) then
    vkCmdSetPrimitiveTopology(FHandle, RHIToVkTopology(Topology));
end;

procedure TVulkanRHICommandList.BindPipeline(const Pipeline: TRHIPipeline);
begin
  FCurrentPipeline := Pipeline as TVulkanRHIPipeline;
  if (FHandle <> nil) and (FCurrentPipeline <> nil) and Assigned(vkCmdBindPipeline) then
    vkCmdBindPipeline(FHandle, VK_PIPELINE_BIND_POINT_GRAPHICS, FCurrentPipeline.Handle);

  if (FCurrentPipeline <> nil) and (FDevice <> nil) and FDevice.SupportsExtendedDynamicState then
  begin
    SetCullMode(FCurrentPipeline.Desc.Rasterizer.CullMode);
    SetFrontFace(FCurrentPipeline.Desc.Rasterizer.FrontFace);
    SetPrimitiveTopology(FCurrentPipeline.Desc.Topology);
    SetDepthTestEnable(FCurrentPipeline.Desc.DepthStencil.DepthTestEnable);
    SetDepthWriteEnable(FCurrentPipeline.Desc.DepthStencil.DepthWriteEnable);
    SetDepthCompareOp(FCurrentPipeline.Desc.DepthStencil.DepthCompareOp);
  end;
end;

procedure TVulkanRHICommandList.BindDescriptorSet(const SetIndex: Cardinal;
  const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal);
var
  SetHandle: VkDescriptorSet;
  OffsetPtr: PUInt32;
begin
  if DescriptorSet = nil then Exit;
  SetHandle := (DescriptorSet as TVulkanRHIDescriptorSet).Handle;
  if Length(DynamicOffsets) > 0 then
    OffsetPtr := @DynamicOffsets[0]
  else
    OffsetPtr := nil;

  if (FHandle <> nil) and (FCurrentPipeline <> nil) and Assigned(vkCmdBindDescriptorSets) then
    vkCmdBindDescriptorSets(FHandle, VK_PIPELINE_BIND_POINT_GRAPHICS,
      FCurrentPipeline.PipelineLayout, SetIndex, 1, @SetHandle,
      Length(DynamicOffsets), OffsetPtr);
end;

procedure TVulkanRHICommandList.PushConstants(const StageFlags: TRHIShaderStageFlags;
  const Offset, Size: Cardinal; const Data);
var
  TargetLayout: VkPipelineLayout;
begin
  TargetLayout := VK_NULL_HANDLE;
  if (ssCompute in StageFlags) and (FCurrentComputePipeline <> nil) and
     ((FCurrentPipeline = nil) or (StageFlags = [ssCompute])) then
    TargetLayout := FCurrentComputePipeline.PipelineLayout
  else if FCurrentPipeline <> nil then
    TargetLayout := FCurrentPipeline.PipelineLayout
  else if FCurrentComputePipeline <> nil then
    TargetLayout := FCurrentComputePipeline.PipelineLayout;

  if (FHandle <> nil) and (TargetLayout <> VK_NULL_HANDLE) and Assigned(vkCmdPushConstants) then
    vkCmdPushConstants(FHandle, TargetLayout,
      RHIToVkShaderStageFlags(StageFlags), Offset, Size, @Data);
end;

procedure TVulkanRHICommandList.BindComputePipeline(const Pipeline: TRHIComputePipeline);
begin
  FCurrentComputePipeline := Pipeline as TVulkanRHIComputePipeline;
  if (FHandle <> nil) and (FCurrentComputePipeline <> nil) and Assigned(vkCmdBindPipeline) then
    vkCmdBindPipeline(FHandle, VK_PIPELINE_BIND_POINT_COMPUTE, FCurrentComputePipeline.Handle);
end;

procedure TVulkanRHICommandList.BindComputeDescriptorSet(const SetIndex: Cardinal;
  const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal);
var
  SetHandle: VkDescriptorSet;
  OffsetPtr: PUInt32;
begin
  if DescriptorSet = nil then Exit;
  SetHandle := (DescriptorSet as TVulkanRHIDescriptorSet).Handle;
  if Length(DynamicOffsets) > 0 then
    OffsetPtr := @DynamicOffsets[0]
  else
    OffsetPtr := nil;

  if (FHandle <> nil) and (FCurrentComputePipeline <> nil) and Assigned(vkCmdBindDescriptorSets) then
    vkCmdBindDescriptorSets(FHandle, VK_PIPELINE_BIND_POINT_COMPUTE,
      FCurrentComputePipeline.PipelineLayout, SetIndex, 1, @SetHandle,
      Length(DynamicOffsets), OffsetPtr);
end;

procedure TVulkanRHICommandList.Dispatch(const GroupCountX, GroupCountY, GroupCountZ: Cardinal);
begin
  Inc(FComputeDispatchCount);
  if FDevice <> nil then
    Inc(FDevice.FComputeDispatchCount);
  if (FHandle <> nil) and Assigned(vkCmdDispatch) then
    vkCmdDispatch(FHandle, Max(1, GroupCountX), Max(1, GroupCountY), Max(1, GroupCountZ));
end;

procedure TVulkanRHICommandList.DispatchIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt);
begin
  if IndirectBuffer = nil then Exit;
  Inc(FComputeDispatchCount);
  if FDevice <> nil then
    Inc(FDevice.FComputeDispatchCount);
  if (FHandle <> nil) and Assigned(vkCmdDispatchIndirect) then
    vkCmdDispatchIndirect(FHandle, (IndirectBuffer as TVulkanRHIBuffer).Handle, Offset);
end;

procedure TVulkanRHICommandList.ResetQueryPool(const QueryPool: TRHIQueryPool;
  const FirstQuery, QueryCount: Cardinal);
var
  VkPool: TVulkanRHIQueryPool;
  I: Cardinal;
begin
  if (QueryPool = nil) or (QueryCount = 0) then Exit;
  VkPool := QueryPool as TVulkanRHIQueryPool;
  Inc(VkPool.FResetCount);
  for I := FirstQuery to Min(FirstQuery + QueryCount, Cardinal(Length(VkPool.FQueryWritten))) - 1 do
  begin
    VkPool.FQueryWritten[I] := False;
    VkPool.FSimulatedResults[I] := 0;
  end;
  if (FHandle <> nil) and Assigned(vkCmdResetQueryPool) then
    vkCmdResetQueryPool(FHandle, VkPool.Handle, FirstQuery, QueryCount);
end;

procedure TVulkanRHICommandList.BeginQuery(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal; const Precise: Boolean);
var
  VkPool: TVulkanRHIQueryPool;
  Flags: VkQueryControlFlags;
begin
  if QueryPool = nil then Exit;
  VkPool := QueryPool as TVulkanRHIQueryPool;
  if QueryIndex < Cardinal(Length(VkPool.FQueryWritten)) then
  begin
    VkPool.FQueryWritten[QueryIndex] := True;
    if VkPool.FSimulatedResults[QueryIndex] = 0 then
      VkPool.FSimulatedResults[QueryIndex] := 128;
  end;
  Flags := 0;
  if Precise then
    Flags := VK_QUERY_CONTROL_PRECISE_BIT;
  if (FHandle <> nil) and Assigned(vkCmdBeginQuery) then
    vkCmdBeginQuery(FHandle, VkPool.Handle, QueryIndex, Flags);
end;

procedure TVulkanRHICommandList.EndQuery(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal);
var
  VkPool: TVulkanRHIQueryPool;
begin
  if QueryPool = nil then Exit;
  VkPool := QueryPool as TVulkanRHIQueryPool;
  if QueryIndex < Cardinal(Length(VkPool.FQueryWritten)) then
    VkPool.FQueryWritten[QueryIndex] := True;
  if (FHandle <> nil) and Assigned(vkCmdEndQuery) then
    vkCmdEndQuery(FHandle, VkPool.Handle, QueryIndex);
end;

procedure TVulkanRHICommandList.WriteTimestamp(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal; const Stage: TRHIShaderStage);
var
  VkPool: TVulkanRHIQueryPool;
  VkStage: VkPipelineStageFlags;
begin
  if QueryPool = nil then Exit;
  VkPool := QueryPool as TVulkanRHIQueryPool;
  if QueryIndex < Cardinal(Length(VkPool.FQueryWritten)) then
  begin
    VkPool.FQueryWritten[QueryIndex] := True;
    if VkPool.FSimulatedResults[QueryIndex] = 0 then
      VkPool.FSimulatedResults[QueryIndex] := UInt64(QueryIndex + 1) * UInt64(1000000);
  end;
  case Stage of
    ssVertex:   VkStage := VK_PIPELINE_STAGE_VERTEX_SHADER_BIT;
    ssFragment: VkStage := VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    ssGeometry: VkStage := VK_PIPELINE_STAGE_VERTEX_SHADER_BIT;
    ssCompute:  VkStage := VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
    else        VkStage := VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
  end;
  if (FHandle <> nil) and Assigned(vkCmdWriteTimestamp) then
    vkCmdWriteTimestamp(FHandle, VkStage, VkPool.Handle, QueryIndex);
end;

procedure TVulkanRHICommandList.BindVertexBuffers(const FirstBinding: Cardinal;
  const Buffers: array of TRHIBuffer; const Offsets: array of PtrUInt);
var
  VkBuffers: array of VkBuffer;
  VkOffsets: array of VkDeviceSize;
  I: Integer;
begin
  if Length(Buffers) = 0 then Exit;
  SetLength(VkBuffers, Length(Buffers));
  SetLength(VkOffsets, Length(Offsets));
  for I := 0 to High(Buffers) do
  begin
    VkBuffers[I] := (Buffers[I] as TVulkanRHIBuffer).Handle;
    VkOffsets[I] := Offsets[I];
  end;
  if (FHandle <> nil) and Assigned(vkCmdBindVertexBuffers) then
    vkCmdBindVertexBuffers(FHandle, FirstBinding, Length(VkBuffers), @VkBuffers[0], @VkOffsets[0]);
end;

procedure TVulkanRHICommandList.BindIndexBuffer(const Buffer: TRHIBuffer;
  const Offset: PtrUInt; const IndexType: TRHIIndexType);
var
  VkIdxType: VkIndexType;
begin
  if IndexType = itUInt16 then
    VkIdxType := VK_INDEX_TYPE_UINT16
  else
    VkIdxType := VK_INDEX_TYPE_UINT32;

  if (FHandle <> nil) and Assigned(vkCmdBindIndexBuffer) and Assigned(Buffer) then
    vkCmdBindIndexBuffer(FHandle, (Buffer as TVulkanRHIBuffer).Handle, Offset, VkIdxType);
end;

procedure TVulkanRHICommandList.Draw(const VertexCount, InstanceCount,
  FirstVertex, FirstInstance: Cardinal);
begin
  if (FHandle <> nil) and Assigned(vkCmdDraw) then
    vkCmdDraw(FHandle, VertexCount, InstanceCount, FirstVertex, FirstInstance);
end;

procedure TVulkanRHICommandList.DrawIndexed(const IndexCount, InstanceCount,
  FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal);
begin
  if (FHandle <> nil) and Assigned(vkCmdDrawIndexed) then
    vkCmdDrawIndexed(FHandle, IndexCount, InstanceCount, FirstIndex, VertexOffset, FirstInstance);
end;

procedure TVulkanRHICommandList.DrawIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount, Stride: Cardinal);
begin
  if IndirectBuffer = nil then Exit;
  Inc(FIndirectDrawCallCount);
  FLastEffectiveIndirectDrawCount := DrawCount;
  if (FHandle <> nil) and Assigned(vkCmdDrawIndirect) then
    vkCmdDrawIndirect(FHandle, (IndirectBuffer as TVulkanRHIBuffer).Handle,
      Offset, DrawCount, Stride);
end;

procedure TVulkanRHICommandList.DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount, Stride: Cardinal);
begin
  if IndirectBuffer = nil then Exit;
  Inc(FIndirectDrawCallCount);
  FLastEffectiveIndirectDrawCount := DrawCount;
  if (FHandle <> nil) and Assigned(vkCmdDrawIndexedIndirect) then
    vkCmdDrawIndexedIndirect(FHandle, (IndirectBuffer as TVulkanRHIBuffer).Handle,
      Offset, DrawCount, Stride);
end;

procedure TVulkanRHICommandList.DrawIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
var
  EffectiveCount: Cardinal;
  MappedPtr: Pointer;
begin
  if (IndirectBuffer = nil) or (CountBuffer = nil) then Exit;

  EffectiveCount := MaxDrawCount;
  if (CountBuffer.Desc.MemoryUsage in [muCpuToGpu, muGpuToCpu]) and
     (CountBufferOffset + SizeOf(Cardinal) <= CountBuffer.Desc.Size) then
  begin
    MappedPtr := CountBuffer.Map;
    try
      if MappedPtr <> nil then
        EffectiveCount := Min(MaxDrawCount, PCardinal(PtrUInt(MappedPtr) + CountBufferOffset)^);
    finally
      CountBuffer.Unmap;
    end;
  end;

  Inc(FIndirectDrawCallCount);
  Inc(FIndirectCountDrawCallCount);
  FLastEffectiveIndirectDrawCount := EffectiveCount;

  if (FHandle <> nil) and (FDevice <> nil) and
     FDevice.Capabilities.SupportsDrawIndirectCount and Assigned(vkCmdDrawIndirectCount) then
    vkCmdDrawIndirectCount(FHandle,
      (IndirectBuffer as TVulkanRHIBuffer).Handle, Offset,
      (CountBuffer as TVulkanRHIBuffer).Handle, CountBufferOffset,
      MaxDrawCount, Stride)
  else
  if (FHandle <> nil) and Assigned(vkCmdDrawIndirect) then
    vkCmdDrawIndirect(FHandle,
      (IndirectBuffer as TVulkanRHIBuffer).Handle, Offset,
      EffectiveCount, Stride);
end;

procedure TVulkanRHICommandList.DrawIndexedIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
var
  EffectiveCount: Cardinal;
  MappedPtr: Pointer;
begin
  if (IndirectBuffer = nil) or (CountBuffer = nil) then Exit;

  EffectiveCount := MaxDrawCount;
  if (CountBuffer.Desc.MemoryUsage in [muCpuToGpu, muGpuToCpu]) and
     (CountBufferOffset + SizeOf(Cardinal) <= CountBuffer.Desc.Size) then
  begin
    MappedPtr := CountBuffer.Map;
    try
      if MappedPtr <> nil then
        EffectiveCount := Min(MaxDrawCount, PCardinal(PtrUInt(MappedPtr) + CountBufferOffset)^);
    finally
      CountBuffer.Unmap;
    end;
  end;

  Inc(FIndirectDrawCallCount);
  Inc(FIndirectCountDrawCallCount);
  FLastEffectiveIndirectDrawCount := EffectiveCount;

  if (FHandle <> nil) and (FDevice <> nil) and
     FDevice.Capabilities.SupportsDrawIndirectCount and Assigned(vkCmdDrawIndexedIndirectCount) then
    vkCmdDrawIndexedIndirectCount(FHandle,
      (IndirectBuffer as TVulkanRHIBuffer).Handle, Offset,
      (CountBuffer as TVulkanRHIBuffer).Handle, CountBufferOffset,
      MaxDrawCount, Stride)
  else
  if (FHandle <> nil) and Assigned(vkCmdDrawIndexedIndirect) then
    vkCmdDrawIndexedIndirect(FHandle,
      (IndirectBuffer as TVulkanRHIBuffer).Handle, Offset,
      EffectiveCount, Stride);
end;

procedure TVulkanRHICommandList.ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList);
var
  CmdBuffers: array of VkCommandBuffer;
  I: Integer;
begin
  if Length(SecondaryCommandLists) = 0 then Exit;
  SetLength(CmdBuffers, Length(SecondaryCommandLists));
  for I := 0 to High(SecondaryCommandLists) do
    CmdBuffers[I] := (SecondaryCommandLists[I] as TVulkanRHICommandList).Handle;
  if (FHandle <> nil) and Assigned(vkCmdExecuteCommands) then
    vkCmdExecuteCommands(FHandle, Length(CmdBuffers), @CmdBuffers[0]);
end;

procedure TVulkanRHICommandList.PushDebugGroup(const LabelName: String; const Color: TCastleColor);
var
  LabelInfo: VkDebugUtilsLabelEXT;
  AnsiLabel: AnsiString;
begin
  if Assigned(vkCmdBeginDebugUtilsLabelEXT) and (FHandle <> nil) then
  begin
    AnsiLabel := AnsiString(LabelName);
    FillChar(LabelInfo, SizeOf(LabelInfo), 0);
    LabelInfo.sType := VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT;
    LabelInfo.pLabelName := PAnsiChar(AnsiLabel);
    Move(Color.Data, LabelInfo.color, SizeOf(Single) * 4);
    vkCmdBeginDebugUtilsLabelEXT(FHandle, @LabelInfo);
  end;
end;

procedure TVulkanRHICommandList.PopDebugGroup;
begin
  if Assigned(vkCmdEndDebugUtilsLabelEXT) and (FHandle <> nil) then
    vkCmdEndDebugUtilsLabelEXT(FHandle);
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanDescriptorPoolAllocator                                               }
{ ---------------------------------------------------------------------------- }

constructor TVulkanDescriptorPoolAllocator.Create(const ADevice: VkDevice;
  const AInitialMaxSets: Cardinal; const AAllowFreeIndividualSets: Boolean;
  const AMaxSetsCap: Cardinal; const AAllowUpdateAfterBind: Boolean);
begin
  inherited Create;
  FDevice := ADevice;
  FInitialMaxSets := Max(1, AInitialMaxSets);
  FMaxSetsCap := Max(FInitialMaxSets, AMaxSetsCap);
  FCurrentMaxSets := FInitialMaxSets;
  FAllowFreeIndividualSets := AAllowFreeIndividualSets;
  FAllowUpdateAfterBind := AAllowUpdateAfterBind;
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
  PoolSizes: array[0..6] of VkDescriptorPoolSize;
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

  FillChar(PoolInfo, SizeOf(PoolInfo), 0);
  PoolInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  if FAllowFreeIndividualSets then
    PoolInfo.flags := PoolInfo.flags or VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;
  if FAllowUpdateAfterBind then
    PoolInfo.flags := PoolInfo.flags or VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT;
  PoolInfo.maxSets := Result.Capacity;
  PoolInfo.poolSizeCount := Length(PoolSizes);
  PoolInfo.pPoolSizes := @PoolSizes[0];

  if (FDevice <> nil) and Assigned(vkCreateDescriptorPool) then
    CheckVk(vkCreateDescriptorPool(FDevice, @PoolInfo, nil, @Result.Handle), 'vkCreateDescriptorPool')
  else
    Result.Handle := VkDescriptorPool(PtrUInt($50000000) + PtrUInt(FTotalPoolCount) + 1);

  Inc(FTotalPoolCount);
  FCurrentMaxSets := Min(FMaxSetsCap, Max(FCurrentMaxSets + (FCurrentMaxSets div 2), FCurrentMaxSets + 1));
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
  FreeAndNil(FDescriptorSet);
  FreeAndNil(FLayout);
  inherited;
end;

procedure TCastleVulkanBindlessTextureManager.EnsureDescriptorSetCreated;
var
  Bindings: array[0..1] of TRHIDescriptorBindingDesc;
begin
  if FDescriptorSet <> nil then
    Exit;

  FillChar(Bindings, SizeOf(Bindings), 0);
  { Binding 0: Bindless Combined Image Sampler Array }
  Bindings[0].Binding := 0;
  Bindings[0].DescriptorType := dtCombinedImageSampler;
  Bindings[0].Count := FCapacity;
  Bindings[0].StageFlags := [ssVertex, ssFragment, ssCompute];
  Bindings[0].BindingFlags := [dbfPartiallyBound, dbfUpdateUnusedWhilePending];
  if FSupportsUpdateAfterBind then
    Include(Bindings[0].BindingFlags, dbfUpdateAfterBind);

  { Binding 1: Multi-Material Storage Buffer (CastleBindlessMaterialsBlock) }
  Bindings[1].Binding := 1;
  Bindings[1].DescriptorType := dtStorageBuffer;
  Bindings[1].Count := 1;
  Bindings[1].StageFlags := [ssVertex, ssFragment, ssCompute];
  Bindings[1].BindingFlags := [dbfPartiallyBound];

  FLayout := TVulkanRHIDescriptorSetLayout.Create(FDevice, Bindings);
  FDescriptorSet := TVulkanRHIDescriptorSet.Create(FDevice, FLayout, False);
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
  FMaterialSSBOBuffer := ASSBOBuffer;
  if (FDescriptorSet <> nil) and (ASSBOBuffer <> nil) then
  begin
    FDescriptorSet.BindStorageBuffer(1, ASSBOBuffer, AOffset, ARange);
    Inc(FPendingWriteCount);
  end;
end;

function TCastleVulkanBindlessTextureManager.FlushPendingUpdates: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  if (FDescriptorSet = nil) or (FPendingWriteCount = 0) then
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
  SetLength(FPendingBufferCopies, 0);
  SetLength(FPendingImageCopies, 0);
  for Slot := 0 to MaxFramesInFlight - 1 do
  begin
    ReclaimFrameSlot(Slot);
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
    FRingBuffers[Slot], FRingCapacityPerFrame, muCpuToGpu, False, Align);

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
      FOverflowChunks[Slot][ChunkIdx].Buffer, ASize, muCpuToGpu, False, EffAlign);

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

procedure TCastleVulkanStagingUploader.ReclaimFrameSlot(const AFrameSlot: Cardinal);
var
  Slot: Cardinal;
  I: Integer;
begin
  Slot := AFrameSlot mod MaxFramesInFlight;
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
  if (ABuffer = nil) or (Length(FPendingBufferCopies) = 0) then
    Exit;
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

procedure TCastleVulkanStagingUploader.CancelPendingUploadsForTexture(
  const ATexture: TVulkanRHITexture);
var
  I, WriteIdx: Integer;
begin
  if (ATexture = nil) or (Length(FPendingImageCopies) = 0) then
    Exit;
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

function TCastleVulkanStagingUploader.FlushPendingUploads(
  const ACommandList: TVulkanRHICommandList): Cardinal;
var
  BufCount, ImgCount, I: Integer;
  Cmd: VkCommandBuffer;
  OneShotCmd: Boolean;
  BufBarriers: array of VkBufferMemoryBarrier;
  ImgBarrier: VkImageMemoryBarrier;
  BufItem: TVulkanStagedBufferCopy;
  ImgItem: TVulkanStagedImageCopy;
begin
  BufCount := Length(FPendingBufferCopies);
  ImgCount := Length(FPendingImageCopies);
  Result := Cardinal(BufCount + ImgCount);
  if Result = 0 then
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
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
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
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
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
const
  FallbackComputeSPIRV: array[0..9] of UInt32 = (
    $07230203, // SPIR-V Magic
    $00010500, // Version 1.5
    $00000000,
    $00000008, // Bound
    $00000000,
    ($00050000 or 15), // OpEntryPoint (5 words)
    5,                 // ExecutionModel = GLCompute (5)
    1,                 // EntryPoint ID = %1
    $6E69616D,         // "main"
    $00000000
  );
var
  Bindings: array[0..3] of TRHIDescriptorBindingDesc;
  ShaderGen: TCastleShaderGeneratorRHI;
  ComputeGLSL: String;
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
      [buStorage, buTransferSrc, buTransferDst], muCpuToGpu, 'GpuCullingVisibilityOutSSBO'),
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
    FComputeShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
      @FallbackComputeSPIRV[0], SizeOf(FallbackComputeSPIRV), 'GpuCullingCS');

  FillChar(PipeDesc, SizeOf(PipeDesc), 0);
  PipeDesc.ComputeShader := FComputeShader;
  SetLength(PipeDesc.DescriptorSetLayouts, 1);
  PipeDesc.DescriptorSetLayouts[0] := FDescriptorLayout;
  PipeDesc.DebugName := 'GpuComputeCullingPSO';
  FComputePipeline := FDevice.GetOrCreateComputePipeline(PipeDesc);
end;

procedure TCastleVulkanComputeCuller.EnsureHiZPipelineCreated;
const
  FallbackHiZSPIRV: array[0..9] of UInt32 = (
    $07230203, // SPIR-V Magic
    $00010500, // Version 1.5
    $00000000,
    $00000008, // Bound
    $00000000,
    ($00050000 or 15), // OpEntryPoint (5 words)
    5,                 // ExecutionModel = GLCompute (5)
    1,                 // EntryPoint ID = %1
    $6E69616D,         // "main"
    $00000000
  );
var
  SamplerDesc: TRHISamplerDesc;
  Bindings: array[0..1] of TRHIDescriptorBindingDesc;
  ShaderGen: TCastleShaderGeneratorRHI;
  HiZGLSL: String;
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
    FHiZDownsampleShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
      @FallbackHiZSPIRV[0], SizeOf(FallbackHiZSPIRV), 'HiZDownsampleCS');

  FillChar(PipeDesc, SizeOf(PipeDesc), 0);
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
  MipCount := Max(Cardinal(1), Cardinal(Floor(Log2(Max(EffectiveW, EffectiveH)))) + 1);

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

  { Populate deterministic indirect commands and visibility counters in mapped memory
    before recording the GPU compute dispatch and buffer barrier. }
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
      if MappedVis <> nil then
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
          if MappedIndirect <> nil then
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
        if MappedIndirect <> nil then
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

    if MappedVis <> nil then
      MappedVis^ := VisibleCount;
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
      TVulkanRHICommandList(ACmd).TransitionBuffer(FIndirectOutputBuffer, rsTransferDst, rsShaderRead);
      TVulkanRHICommandList(ACmd).TransitionBuffer(FVisibilityOutputBuffer, rsTransferDst, rsShaderRead);
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
  FaceIdx: Integer;
begin
  for FaceIdx := 0 to 5 do
    SetLength(FPrefilteredEnvFaceColors[FaceIdx], 0);
  SetLength(FBrdfLutData, 0);
  FBrdfLutComputePipeline := nil; { owned by FDevice.FComputePipelineMap }
  FreeAndNil(FBrdfLutComputeShader);
  FreeAndNil(FBrdfLutDescriptorSet);
  FreeAndNil(FBrdfLutDescriptorLayout);
  FreeAndNil(FBrdfLutSampler);
  FreeAndNil(FBrdfLutTexture);
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

  FillChar(CompDesc, SizeOf(CompDesc), 0);
  CompDesc.ComputeShader := FBrdfLutComputeShader;
  SetLength(CompDesc.DescriptorSetLayouts, 1);
  CompDesc.DescriptorSetLayouts[0] := FBrdfLutDescriptorLayout;
  CompDesc.PushConstantSize := SizeOf(TCastleIBLBrdfLutPushConstants);
  CompDesc.PushConstantStages := [ssCompute];
  CompDesc.DebugName := 'IBLBrdfLutComputePSO';
  FBrdfLutComputePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
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
begin
  EnsureBrdfLutPipelineCreated;
  EffectiveSize := Max(Cardinal(4), ASize);
  EffectiveSamples := Max(Cardinal(8), ASampleCount);

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
    if FDevice.StagingUploader <> nil then
      FDevice.StagingUploader.EnqueueImageUpload(
        FBrdfLutTexture, @PixelsRGBA8[0], Length(PixelsRGBA8),
        EffectiveSize, EffectiveSize, 0, 0);
  end;

  if FBrdfLutDescriptorSet <> nil then
  begin
    FBrdfLutDescriptorSet.BindTexture(0, FBrdfLutTexture, nil);
    FBrdfLutDescriptorSet.Update;
  end;

  if ACmd <> nil then
  begin
    ACmd.TransitionTexture(FBrdfLutTexture, rsTransferDst);
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

function TCastleVulkanIBLGenerator.PrefilterEnvironmentCubemap(
  const ACmd: TRHICommandList;
  const AFaceColors: array of TVector3;
  const ABaseSize: Cardinal): TVulkanRHITexture;
var
  EffectiveBase, MipCount, Mip, FaceIdx, OtherFace, MipDim, PixelIdx, TotalPixels: Cardinal;
  BaseFaces: array[0..5] of TVector3;
  AvgEnv, ConvolvedColor: TVector3;
  Roughness, Weight, TotalWeight, CosAngle: Single;
  CubeDesc: TRHITextureDesc;
  FacePixels: array of Byte;
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
        if FDevice.StagingUploader <> nil then
          FDevice.StagingUploader.EnqueueImageUpload(
            FPrefilteredEnvCubemap, @FacePixels[0], Length(FacePixels),
            MipDim, MipDim, Mip, FaceIdx);
      end;
    end;

    if ACmd <> nil then
    begin
      ACmd.TransitionTexture(FPrefilteredEnvCubemap, rsTransferDst);
      ACmd.TransitionTexture(FPrefilteredEnvCubemap, rsShaderRead);
    end;
    Inc(FTotalEnvPrefilterPasses);
  end;

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

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanClusteredLightCuller                                            }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanClusteredLightCuller.Create(
  const ADevice: TVulkanRHIDevice;
  const AGridX, AGridY, AGridZ: Cardinal);
begin
  inherited Create;
  FDevice := ADevice;
  FWorkgroupSizeX := 64;
  SetGridDimensions(AGridX, AGridY, AGridZ);
  SetCameraProjection(TMatrix4.Identity, 1280, 720, 0.1, 1000.0);
end;

destructor TCastleVulkanClusteredLightCuller.Destroy;
begin
  SetLength(FClusterGrid, 0);
  SetLength(FLightIndexList, 0);
  FComputePipeline := nil; { owned by FDevice.FComputePipelineMap }
  FreeAndNil(FComputeShader);
  FreeAndNil(FDescriptorSet);
  FreeAndNil(FDescriptorLayout);
  FreeAndNil(FLightIndexBuffer);
  FreeAndNil(FClusterGridBuffer);
  FreeAndNil(FLightStorageBuffer);
  FreeAndNil(FClusterUniformBuffer);
  inherited;
end;

function TCastleVulkanClusteredLightCuller.GetTotalClusters: Cardinal;
begin
  Result := FGridX * FGridY * FGridZ;
end;

procedure TCastleVulkanClusteredLightCuller.SetGridDimensions(
  const AGridX, AGridY, AGridZ: Cardinal);
var
  NewX, NewY, NewZ, Total: Cardinal;
begin
  NewX := Max(Cardinal(1), AGridX);
  NewY := Max(Cardinal(1), AGridY);
  NewZ := Max(Cardinal(1), AGridZ);
  if (NewX = FGridX) and (NewY = FGridY) and (NewZ = FGridZ) and
     (Length(FClusterGrid) > 0) then
    Exit;

  FGridX := NewX;
  FGridY := NewY;
  FGridZ := NewZ;
  Total := GetTotalClusters;
  SetLength(FClusterGrid, Total);
  SetLength(FLightIndexList, Total * CASTLE_MAX_LIGHTS_PER_CLUSTER);

  FreeAndNil(FClusterGridBuffer);
  FreeAndNil(FLightIndexBuffer);
end;

procedure TCastleVulkanClusteredLightCuller.SetCameraProjection(
  const AProjectionMatrix: TMatrix4;
  const AScreenWidth, AScreenHeight: Cardinal;
  const AZNear, AZFar: Single);
var
  InvProj: TMatrix4;
  ClampedNear, ClampedFar, LogRatio: Single;
begin
  if not AProjectionMatrix.TryInverse(InvProj) then
    InvProj := TMatrix4.Identity;

  ClampedNear := Max(1e-3, AZNear);
  ClampedFar := Max(ClampedNear + 1.0, AZFar);
  LogRatio := Max(1e-5, Ln(ClampedFar / ClampedNear));

  FClusterUniforms.InverseProjectionMatrix := InvProj;
  FClusterUniforms.ScreenAndDepthParams := Vector4(
    Max(1.0, Single(AScreenWidth)),
    Max(1.0, Single(AScreenHeight)),
    ClampedNear,
    ClampedFar);
  FClusterUniforms.GridX := FGridX;
  FClusterUniforms.GridY := FGridY;
  FClusterUniforms.GridZ := FGridZ;
  FClusterUniforms.ActiveLightCount := FActiveLightCount;
  FClusterUniforms.LogDepthParams := Vector4(
    Single(FGridZ) / LogRatio,
    -Single(FGridZ) * Ln(ClampedNear) / LogRatio,
    Single(CASTLE_MAX_LIGHTS_PER_CLUSTER),
    0.0);
end;

procedure TCastleVulkanClusteredLightCuller.ClearLights;
begin
  FActiveLightCount := 0;
  FClusterUniforms.ActiveLightCount := 0;
  FillChar(FLights[0], SizeOf(FLights), 0);
end;

function TCastleVulkanClusteredLightCuller.AddDirectionalLight(
  const AViewDirection, AColor: TVector3;
  const AIntensity: Single): Integer;
var
  DirNorm: TVector3;
begin
  if FActiveLightCount >= CASTLE_MAX_CLUSTERED_LIGHTS then
    Exit(-1);
  if AViewDirection.LengthSqr > 1e-8 then
    DirNorm := AViewDirection.Normalize
  else
    DirNorm := Vector3(0.0, 0.0, -1.0);

  Result := Integer(FActiveLightCount);
  FLights[Result].PositionAndRange := Vector4(0.0, 0.0, 0.0, 1e9);
  FLights[Result].DirectionAndSpotCos := Vector4(DirNorm.X, DirNorm.Y, DirNorm.Z, -1.0);
  FLights[Result].ColorAndIntensity := Vector4(AColor.X, AColor.Y, AColor.Z, Max(0.0, AIntensity));
  FLights[Result].ShadowAndTypeParams := Vector4(Single(Ord(cltDirectional)), -1.0, -1.0, 0.001);
  Inc(FActiveLightCount);
  FClusterUniforms.ActiveLightCount := FActiveLightCount;
end;

function TCastleVulkanClusteredLightCuller.AddPointLight(
  const AViewPosition: TVector3; const ARange: Single;
  const AColor: TVector3; const AIntensity: Single;
  const AShadowTileIndex: Integer;
  const AShadowBias: Single): Integer;
begin
  if FActiveLightCount >= CASTLE_MAX_CLUSTERED_LIGHTS then
    Exit(-1);

  Result := Integer(FActiveLightCount);
  FLights[Result].PositionAndRange := Vector4(
    AViewPosition.X, AViewPosition.Y, AViewPosition.Z, Max(0.01, ARange));
  FLights[Result].DirectionAndSpotCos := Vector4(0.0, 0.0, -1.0, -1.0);
  FLights[Result].ColorAndIntensity := Vector4(AColor.X, AColor.Y, AColor.Z, Max(0.0, AIntensity));
  FLights[Result].ShadowAndTypeParams := Vector4(
    Single(Ord(cltPoint)), -1.0, Single(AShadowTileIndex), Max(0.0, AShadowBias));
  Inc(FActiveLightCount);
  FClusterUniforms.ActiveLightCount := FActiveLightCount;
end;

function TCastleVulkanClusteredLightCuller.AddSpotLight(
  const AViewPosition, AViewDirection: TVector3;
  const ARange, AInnerSpotCos, AOuterSpotCos: Single;
  const AColor: TVector3; const AIntensity: Single;
  const AShadowTileIndex: Integer;
  const AShadowBias: Single): Integer;
var
  DirNorm: TVector3;
begin
  if FActiveLightCount >= CASTLE_MAX_CLUSTERED_LIGHTS then
    Exit(-1);
  if AViewDirection.LengthSqr > 1e-8 then
    DirNorm := AViewDirection.Normalize
  else
    DirNorm := Vector3(0.0, 0.0, -1.0);

  Result := Integer(FActiveLightCount);
  FLights[Result].PositionAndRange := Vector4(
    AViewPosition.X, AViewPosition.Y, AViewPosition.Z, Max(0.01, ARange));
  FLights[Result].DirectionAndSpotCos := Vector4(
    DirNorm.X, DirNorm.Y, DirNorm.Z, AOuterSpotCos);
  FLights[Result].ColorAndIntensity := Vector4(AColor.X, AColor.Y, AColor.Z, Max(0.0, AIntensity));
  FLights[Result].ShadowAndTypeParams := Vector4(
    Single(Ord(cltSpot)), AInnerSpotCos, Single(AShadowTileIndex), Max(0.0, AShadowBias));
  Inc(FActiveLightCount);
  FClusterUniforms.ActiveLightCount := FActiveLightCount;
end;

procedure TCastleVulkanClusteredLightCuller.ComputeSliceDepthBounds(
  const ASliceZ: Cardinal; out ASliceNear, ASliceFar: Single);
var
  ZNear, ZFar, Ratio: Single;
  ClampedZ: Cardinal;
begin
  ZNear := Max(1e-3, FClusterUniforms.ScreenAndDepthParams.Z);
  ZFar := Max(ZNear + 1e-2, FClusterUniforms.ScreenAndDepthParams.W);
  Ratio := ZFar / ZNear;
  ClampedZ := Min(ASliceZ, Max(Cardinal(1), FGridZ) - 1);
  ASliceNear := ZNear * Power(Ratio, Single(ClampedZ) / Single(Max(Cardinal(1), FGridZ)));
  ASliceFar  := ZNear * Power(Ratio, Single(ClampedZ + 1) / Single(Max(Cardinal(1), FGridZ)));
end;

procedure TCastleVulkanClusteredLightCuller.ComputeClusterViewAABB(
  const ACX, ACY, ACZ: Cardinal;
  out AAABBMin, AAABBMax: TVector3);

  function ScreenUVToViewAtPositiveDepth(const AUVX, AUVY, APositiveDepth: Single): TVector3;
  var
    Ndc, ViewRay: TVector4;
    RayDir: TVector3;
    RayScale: Single;
  begin
    Ndc := Vector4(AUVX * 2.0 - 1.0, AUVY * 2.0 - 1.0, 1.0, 1.0);
    ViewRay := FClusterUniforms.InverseProjectionMatrix * Ndc;
    if Abs(ViewRay.W) > 1e-5 then
      RayDir := Vector3(ViewRay.X / ViewRay.W, ViewRay.Y / ViewRay.W, ViewRay.Z / ViewRay.W)
    else
      RayDir := Vector3(ViewRay.X, ViewRay.Y, ViewRay.Z);

    if Abs(RayDir.Z) > 1e-5 then
    begin
      RayScale := (-APositiveDepth) / RayDir.Z;
      if RayScale < 0.0 then
        RayScale := -RayScale;
      Result := Vector3(RayDir.X * RayScale, RayDir.Y * RayScale, -APositiveDepth);
    end else
      Result := Vector3(RayDir.X * APositiveDepth, RayDir.Y * APositiveDepth, -APositiveDepth);
  end;

var
  SliceNear, SliceFar, UMin, UMax, VMin, VMax: Single;
  P: array[0..3] of TVector3;
  I: Integer;
begin
  ComputeSliceDepthBounds(ACZ, SliceNear, SliceFar);
  UMin := Single(Min(ACX, FGridX - 1)) / Single(Max(Cardinal(1), FGridX));
  UMax := Single(Min(ACX, FGridX - 1) + 1) / Single(Max(Cardinal(1), FGridX));
  VMin := Single(Min(ACY, FGridY - 1)) / Single(Max(Cardinal(1), FGridY));
  VMax := Single(Min(ACY, FGridY - 1) + 1) / Single(Max(Cardinal(1), FGridY));

  P[0] := ScreenUVToViewAtPositiveDepth(UMin, VMin, SliceNear);
  P[1] := ScreenUVToViewAtPositiveDepth(UMax, VMax, SliceNear);
  P[2] := ScreenUVToViewAtPositiveDepth(UMin, VMin, SliceFar);
  P[3] := ScreenUVToViewAtPositiveDepth(UMax, VMax, SliceFar);

  AAABBMin := P[0];
  AAABBMax := P[0];
  for I := 1 to 3 do
  begin
    AAABBMin.X := Min(AAABBMin.X, P[I].X);
    AAABBMin.Y := Min(AAABBMin.Y, P[I].Y);
    AAABBMin.Z := Min(AAABBMin.Z, P[I].Z);
    AAABBMax.X := Max(AAABBMax.X, P[I].X);
    AAABBMax.Y := Max(AAABBMax.Y, P[I].Y);
    AAABBMax.Z := Max(AAABBMax.Z, P[I].Z);
  end;
end;

function TCastleVulkanClusteredLightCuller.ComputeClusterCoordFromScreenAndDepth(
  const AScreenX, AScreenY, APositiveViewDepth: Single;
  out ACX, ACY, ACZ: Cardinal): Cardinal;
var
  ScreenW, ScreenH, ZNear, ZFar, ClampedZ, SliceF: Single;
begin
  ScreenW := Max(1.0, FClusterUniforms.ScreenAndDepthParams.X);
  ScreenH := Max(1.0, FClusterUniforms.ScreenAndDepthParams.Y);
  ZNear := Max(1e-3, FClusterUniforms.ScreenAndDepthParams.Z);
  ZFar := Max(ZNear + 1e-2, FClusterUniforms.ScreenAndDepthParams.W);
  ClampedZ := EnsureRange(APositiveViewDepth, ZNear, ZFar);

  ACX := Cardinal(EnsureRange(Trunc((AScreenX / ScreenW) * Single(FGridX)), 0, Integer(FGridX) - 1));
  ACY := Cardinal(EnsureRange(Trunc((AScreenY / ScreenH) * Single(FGridY)), 0, Integer(FGridY) - 1));
  SliceF := (Ln(ClampedZ / ZNear) / Max(1e-5, Ln(ZFar / ZNear))) * Single(FGridZ);
  ACZ := Cardinal(EnsureRange(Trunc(SliceF), 0, Integer(FGridZ) - 1));

  Result := (ACZ * FGridY + ACY) * FGridX + ACX;
end;

procedure TCastleVulkanClusteredLightCuller.EnsureResourcesCreated;
var
  BufDesc: TRHIBufferDesc;
  Bindings: array[0..3] of TRHIDescriptorBindingDesc;
  ShaderGen: TCastleShaderGeneratorRHI;
  CompDesc: TRHIComputePipelineDesc;
  Total: Cardinal;
begin
  if FDevice = nil then Exit;
  Total := Max(Cardinal(1), GetTotalClusters);

  if FClusterUniformBuffer = nil then
  begin
    FillChar(BufDesc, SizeOf(BufDesc), 0);
    BufDesc.Size := SizeOf(TCastleClusterCullingUniformBlock);
    BufDesc.Usage := [buUniform, buTransferDst];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'ClusterCullingUBO';
    FClusterUniformBuffer := FDevice.CreateBuffer(BufDesc);
  end;

  if FLightStorageBuffer = nil then
  begin
    FillChar(BufDesc, SizeOf(BufDesc), 0);
    BufDesc.Size := PtrUInt(CASTLE_MAX_CLUSTERED_LIGHTS) * SizeOf(TCastleClusteredLight);
    BufDesc.Usage := [buStorage, buTransferDst];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'ClusteredLightsSSBO';
    FLightStorageBuffer := FDevice.CreateBuffer(BufDesc);
  end;

  if FClusterGridBuffer = nil then
  begin
    FillChar(BufDesc, SizeOf(BufDesc), 0);
    BufDesc.Size := PtrUInt(Total) * SizeOf(TCastleClusterGridEntry);
    BufDesc.Usage := [buStorage, buTransferDst, buTransferSrc];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'ClusterGridSSBO';
    FClusterGridBuffer := FDevice.CreateBuffer(BufDesc);
  end;

  if FLightIndexBuffer = nil then
  begin
    FillChar(BufDesc, SizeOf(BufDesc), 0);
    BufDesc.Size := PtrUInt(Total) * CASTLE_MAX_LIGHTS_PER_CLUSTER * SizeOf(Cardinal);
    BufDesc.Usage := [buStorage, buTransferDst, buTransferSrc];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'ClusterLightIndicesSSBO';
    FLightIndexBuffer := FDevice.CreateBuffer(BufDesc);
  end;

  if FDescriptorLayout = nil then
  begin
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
  end;

  if FDescriptorSet = nil then
    FDescriptorSet := FDevice.CreateDescriptorSet(FDescriptorLayout);

  FDescriptorSet.BindUniformBuffer(0, FClusterUniformBuffer, 0, SizeOf(TCastleClusterCullingUniformBlock));
  FDescriptorSet.BindStorageBuffer(1, FLightStorageBuffer, 0, FLightStorageBuffer.Desc.Size);
  FDescriptorSet.BindStorageBuffer(2, FClusterGridBuffer, 0, FClusterGridBuffer.Desc.Size);
  FDescriptorSet.BindStorageBuffer(3, FLightIndexBuffer, 0, FLightIndexBuffer.Desc.Size);
  FDescriptorSet.Update;

  if FComputePipeline = nil then
  begin
    ShaderGen := TCastleShaderGeneratorRHI.Create(rbVulkan);
    try
      FComputeShader := FDevice.CreateShaderModuleFromGLSL(
        ssCompute,
        ShaderGen.GenerateClusteredLightCullingComputeShader(FWorkgroupSizeX),
        'ClusteredLightCullingCS');
    finally
      FreeAndNil(ShaderGen);
    end;

    FillChar(CompDesc, SizeOf(CompDesc), 0);
    CompDesc.ComputeShader := FComputeShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FDescriptorLayout;
    CompDesc.PushConstantSize := 0;
    CompDesc.PushConstantStages := [];
    CompDesc.DebugName := 'ClusteredLightCullingPSO';
    FComputePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  end;
end;

function TCastleVulkanClusteredLightCuller.DispatchLightCulling(
  const ACmd: TRHICommandList): Cardinal;

  function SphereIntersectsBox(const ACenter: TVector3; const ARadius: Single;
    const ABoxMin, ABoxMax: TVector3): Boolean;
  var
    ClosestX, ClosestY, ClosestZ, DX, DY, DZ: Single;
  begin
    ClosestX := EnsureRange(ACenter.X, ABoxMin.X, ABoxMax.X);
    ClosestY := EnsureRange(ACenter.Y, ABoxMin.Y, ABoxMax.Y);
    ClosestZ := EnsureRange(ACenter.Z, ABoxMin.Z, ABoxMax.Z);
    DX := ACenter.X - ClosestX;
    DY := ACenter.Y - ClosestY;
    DZ := ACenter.Z - ClosestZ;
    Result := (DX * DX + DY * DY + DZ * DZ) <= (ARadius * ARadius);
  end;

var
  Total, CX, CY, CZ, ClusterIdx, BaseOffset, LocalCount, LightIdx, GroupCountX: Cardinal;
  BoxMin, BoxMax, LightPos: TVector3;
  LightRange: Single;
  LightTypeInt: Integer;
  Intersects: Boolean;
begin
  EnsureResourcesCreated;
  Total := GetTotalClusters;
  if Total = 0 then
    Exit(0);

  FClusterUniforms.GridX := FGridX;
  FClusterUniforms.GridY := FGridY;
  FClusterUniforms.GridZ := FGridZ;
  FClusterUniforms.ActiveLightCount := FActiveLightCount;

  if FClusterUniformBuffer <> nil then
    FClusterUniformBuffer.UploadData(FClusterUniforms, SizeOf(FClusterUniforms), 0);
  if (FLightStorageBuffer <> nil) and (FActiveLightCount > 0) then
    FLightStorageBuffer.UploadData(FLights[0], PtrUInt(FActiveLightCount) * SizeOf(TCastleClusteredLight), 0);

  FActiveClusterCount := 0;
  FTotalAssignedLightRefs := 0;

  for CZ := 0 to FGridZ - 1 do
    for CY := 0 to FGridY - 1 do
      for CX := 0 to FGridX - 1 do
      begin
        ClusterIdx := (CZ * FGridY + CY) * FGridX + CX;
        BaseOffset := ClusterIdx * CASTLE_MAX_LIGHTS_PER_CLUSTER;
        LocalCount := 0;

        if FActiveLightCount > 0 then
        begin
          ComputeClusterViewAABB(CX, CY, CZ, BoxMin, BoxMax);
          for LightIdx := 0 to FActiveLightCount - 1 do
          begin
            if LocalCount >= CASTLE_MAX_LIGHTS_PER_CLUSTER then
              Break;
            LightTypeInt := Round(FLights[LightIdx].ShadowAndTypeParams.X);
            if LightTypeInt = Ord(cltDirectional) then
              Intersects := True
            else
            begin
              LightPos := Vector3(
                FLights[LightIdx].PositionAndRange.X,
                FLights[LightIdx].PositionAndRange.Y,
                FLights[LightIdx].PositionAndRange.Z);
              LightRange := FLights[LightIdx].PositionAndRange.W;
              Intersects := SphereIntersectsBox(LightPos, LightRange, BoxMin, BoxMax);
            end;

            if Intersects then
            begin
              FLightIndexList[BaseOffset + LocalCount] := LightIdx;
              Inc(LocalCount);
            end;
          end;
        end;

        FClusterGrid[ClusterIdx].Offset := BaseOffset;
        FClusterGrid[ClusterIdx].Count := LocalCount;
        if LocalCount > 0 then
        begin
          Inc(FActiveClusterCount);
          Inc(FTotalAssignedLightRefs, LocalCount);
        end;
      end;

  if (FClusterGridBuffer <> nil) and (Length(FClusterGrid) > 0) then
    FClusterGridBuffer.UploadData(FClusterGrid[0], PtrUInt(Length(FClusterGrid)) * SizeOf(TCastleClusterGridEntry), 0);
  if (FLightIndexBuffer <> nil) and (Length(FLightIndexList) > 0) then
    FLightIndexBuffer.UploadData(FLightIndexList[0], PtrUInt(Length(FLightIndexList)) * SizeOf(Cardinal), 0);

  GroupCountX := (Total + FWorkgroupSizeX - 1) div FWorkgroupSizeX;
  if ACmd <> nil then
  begin
    ACmd.BindComputePipeline(FComputePipeline);
    ACmd.BindComputeDescriptorSet(0, FDescriptorSet, []);
    ACmd.Dispatch(GroupCountX, 1, 1);
    if ACmd is TVulkanRHICommandList then
    begin
      TVulkanRHICommandList(ACmd).TransitionBuffer(FClusterGridBuffer, rsTransferDst, rsShaderRead);
      TVulkanRHICommandList(ACmd).TransitionBuffer(FLightIndexBuffer, rsTransferDst, rsShaderRead);
    end;
  end;

  Inc(FTotalDispatches);
  Result := GroupCountX;
end;

function TCastleVulkanClusteredLightCuller.GetClusterEntry(
  const ACX, ACY, ACZ: Cardinal): TCastleClusterGridEntry;
var
  Idx: Cardinal;
begin
  FillChar(Result, SizeOf(Result), 0);
  if (ACX >= FGridX) or (ACY >= FGridY) or (ACZ >= FGridZ) then
    Exit;
  Idx := (ACZ * FGridY + ACY) * FGridX + ACX;
  if Idx < Cardinal(Length(FClusterGrid)) then
    Result := FClusterGrid[Idx];
end;

function TCastleVulkanClusteredLightCuller.GetClusterLightIndex(
  const ACX, ACY, ACZ, ALocalSlot: Cardinal): Cardinal;
var
  Entry: TCastleClusterGridEntry;
begin
  Result := High(Cardinal);
  Entry := GetClusterEntry(ACX, ACY, ACZ);
  if (ALocalSlot < Entry.Count) and
     (Entry.Offset + ALocalSlot < Cardinal(Length(FLightIndexList))) then
    Result := FLightIndexList[Entry.Offset + ALocalSlot];
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanShadowAtlas                                                     }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanShadowAtlas.Create(const ADevice: TVulkanRHIDevice;
  const AAtlasSize, ACascadeResolution: Cardinal);
begin
  inherited Create;
  FDevice := ADevice;
  FAtlasSize := Max(Cardinal(512), AAtlasSize);
  FCascadeResolution := Min(Cardinal(FAtlasSize div CASTLE_MAX_SHADOW_CASCADES), Max(Cardinal(128), ACascadeResolution));
  ResetPositionalTiles;
end;

destructor TCastleVulkanShadowAtlas.Destroy;
begin
  FreeAndNil(FPositionalTileBuffer);
  FreeAndNil(FCascadeUniformBuffer);
  FreeAndNil(FShadowAtlasSampler);
  FreeAndNil(FShadowAtlasTexture);
  inherited;
end;

procedure TCastleVulkanShadowAtlas.EnsureAtlasResourcesCreated;
var
  TexDesc: TRHITextureDesc;
  SamplerDesc: TRHISamplerDesc;
  BufDesc: TRHIBufferDesc;
begin
  if FDevice = nil then Exit;

  if FShadowAtlasTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      FAtlasSize, FAtlasSize, pfD32_Float,
      [tuDepthStencil, tuSampled, tuTransferSrc, tuTransferDst], 1, 1);
    TexDesc.DebugName := 'SharedShadowAtlasDepth';
    FShadowAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
    if FShadowAtlasTexture <> nil then
      FShadowAtlasTexture.SetHostClearDepth(1.0);
  end;

  if FShadowAtlasSampler = nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfNearest;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    SamplerDesc.MaxLod := 0.0;
    FShadowAtlasSampler := FDevice.CreateSampler(SamplerDesc);
  end;

  if FCascadeUniformBuffer = nil then
  begin
    FillChar(BufDesc, SizeOf(BufDesc), 0);
    BufDesc.Size := SizeOf(TCastleDirectionalCascadeShadowBlock);
    BufDesc.Usage := [buUniform, buTransferDst];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'DirectionalCascadeShadowUBO';
    FCascadeUniformBuffer := FDevice.CreateBuffer(BufDesc);
  end;

  if FPositionalTileBuffer = nil then
  begin
    FillChar(BufDesc, SizeOf(BufDesc), 0);
    BufDesc.Size := PtrUInt(CASTLE_MAX_SHADOW_ATLAS_TILES) * SizeOf(TCastlePositionalShadowTileEntry);
    BufDesc.Usage := [buStorage, buTransferDst];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'PositionalShadowTilesSSBO';
    FPositionalTileBuffer := FDevice.CreateBuffer(BufDesc);
  end;
end;

function TCastleVulkanShadowAtlas.GetCascadeViewportRect(
  const ACascadeIndex: Cardinal): TRectangle;
var
  ClampedIdx: Cardinal;
begin
  ClampedIdx := Min(Cardinal(CASTLE_MAX_SHADOW_CASCADES - 1), ACascadeIndex);
  Result := Rectangle(
    Integer(ClampedIdx * FCascadeResolution),
    0,
    FCascadeResolution,
    FCascadeResolution);
end;

procedure TCastleVulkanShadowAtlas.ComputeDirectionalCascades(
  const ACameraInverseViewProj: TMatrix4;
  const AWorldLightDirection: TVector3;
  const AZNear, AZFar: Single;
  const ALambda: Single;
  const AStabilizeTexels: Boolean);
var
  ClampedNear, ClampedFar, ClampedLambda, Ratio: Single;
  Splits: array[0..CASTLE_MAX_SHADOW_CASCADES] of Single;
  LightDir, UpVec, RightVec, TrueUp, SliceCenter, LightSpaceCenter: TVector3;
  LightView, LightProj: TMatrix4;
  Frac, LogSplit, UniformSplit, SliceRadius, TexelWorldSize: Single;
  CascadeIdx: Integer;
  TileScale, TileOffsetX, TileOffsetY: Single;
begin
  EnsureAtlasResourcesCreated;
  ClampedNear := Max(1e-3, AZNear);
  ClampedFar := Max(ClampedNear + 1.0, AZFar);
  ClampedLambda := EnsureRange(ALambda, 0.0, 1.0);
  Ratio := ClampedFar / ClampedNear;

  Splits[0] := ClampedNear;
  for CascadeIdx := 1 to CASTLE_MAX_SHADOW_CASCADES do
  begin
    Frac := Single(CascadeIdx) / Single(CASTLE_MAX_SHADOW_CASCADES);
    LogSplit := ClampedNear * Power(Ratio, Frac);
    UniformSplit := ClampedNear + (ClampedFar - ClampedNear) * Frac;
    Splits[CascadeIdx] := ClampedLambda * LogSplit + (1.0 - ClampedLambda) * UniformSplit;
  end;

  FCascadeBlock.CascadeSplitDepths := Vector4(Splits[1], Splits[2], Splits[3], Splits[4]);

  if AWorldLightDirection.LengthSqr > 1e-8 then
    LightDir := AWorldLightDirection.Normalize
  else
    LightDir := Vector3(0.0, -1.0, 0.0);

  if Abs(LightDir.Y) < 0.99 then
    UpVec := Vector3(0.0, 1.0, 0.0)
  else
    UpVec := Vector3(0.0, 0.0, 1.0);

  RightVec := TVector3.CrossProduct(LightDir, UpVec).Normalize;
  TrueUp := TVector3.CrossProduct(RightVec, LightDir).Normalize;

  for CascadeIdx := 0 to CASTLE_MAX_SHADOW_CASCADES - 1 do
  begin
    SliceCenter := (ACameraInverseViewProj * Vector4(0.0, 0.0, 0.0, 1.0)).XYZ;
    SliceRadius := Max(1.0, (Splits[CascadeIdx + 1] - Splits[CascadeIdx]) * 0.75);
    SliceRadius := Ceil(SliceRadius * 16.0) / 16.0;

    FillChar(LightView, SizeOf(LightView), 0);
    LightView.Data[0, 0] := RightVec.X;
    LightView.Data[1, 0] := RightVec.Y;
    LightView.Data[2, 0] := RightVec.Z;
    LightView.Data[0, 1] := TrueUp.X;
    LightView.Data[1, 1] := TrueUp.Y;
    LightView.Data[2, 1] := TrueUp.Z;
    LightView.Data[0, 2] := -LightDir.X;
    LightView.Data[1, 2] := -LightDir.Y;
    LightView.Data[2, 2] := -LightDir.Z;
    LightView.Data[3, 3] := 1.0;

    LightSpaceCenter := (LightView * Vector4(SliceCenter, 1.0)).XYZ;
    if AStabilizeTexels and (FCascadeResolution > 0) then
    begin
      TexelWorldSize := (2.0 * SliceRadius) / Single(FCascadeResolution);
      if TexelWorldSize > 1e-6 then
      begin
        LightSpaceCenter.X := Floor(LightSpaceCenter.X / TexelWorldSize) * TexelWorldSize;
        LightSpaceCenter.Y := Floor(LightSpaceCenter.Y / TexelWorldSize) * TexelWorldSize;
      end;
    end;

    LightView.Data[3, 0] := -LightSpaceCenter.X;
    LightView.Data[3, 1] := -LightSpaceCenter.Y;
    LightView.Data[3, 2] := -LightSpaceCenter.Z;

    { Orthographic projection into Vulkan clip space [-1..1] x [-1..1] x [0..1] }
    FillChar(LightProj, SizeOf(LightProj), 0);
    LightProj.Data[0, 0] := 1.0 / SliceRadius;
    LightProj.Data[1, 1] := 1.0 / SliceRadius;
    LightProj.Data[2, 2] := -1.0 / (4.0 * SliceRadius);
    LightProj.Data[3, 2] := 0.5;
    LightProj.Data[3, 3] := 1.0;

    FCascadeBlock.CascadeViewProjMatrix[CascadeIdx] := LightProj * LightView;

    TileScale := Single(FCascadeResolution) / Single(Max(Cardinal(1), FAtlasSize));
    TileOffsetX := Single(Cardinal(CascadeIdx) * FCascadeResolution) / Single(Max(Cardinal(1), FAtlasSize));
    TileOffsetY := 0.0;
    FCascadeBlock.CascadeAtlasUVScaleOffset[CascadeIdx] := Vector4(TileScale, TileScale, TileOffsetX, TileOffsetY);
  end;

  UploadShadowBuffers;
  Inc(FTotalCascadeUpdates);
end;

procedure TCastleVulkanShadowAtlas.ResetPositionalTiles;
begin
  FAllocatedTileCount := 0;
  FShelfCursorX := 0;
  FShelfCursorY := FCascadeResolution;
  FShelfRowHeight := 0;
  FillChar(FPositionalTiles[0], SizeOf(FPositionalTiles), 0);
  FillChar(FPositionalTileRects[0], SizeOf(FPositionalTileRects), 0);
end;

class function TCastleVulkanShadowAtlas.ChooseTileResolution(
  const ADistanceToCamera, ALightRange: Single;
  const ABaseResolution: Cardinal): Cardinal;
var
  BaseRes: Cardinal;
  NormalizedDist: Single;
begin
  BaseRes := Max(Cardinal(64), ABaseResolution);
  NormalizedDist := Max(0.0, ADistanceToCamera) / Max(1.0, ALightRange);
  if NormalizedDist < 1.0 then
    Result := BaseRes
  else if NormalizedDist < 2.5 then
    Result := Max(Cardinal(64), BaseRes shr 1)
  else
    Result := Max(Cardinal(64), BaseRes shr 2);
end;

function TCastleVulkanShadowAtlas.AllocatePositionalTile(
  const ADesiredResolution: Cardinal;
  const ALightViewProj: TMatrix4;
  out ATileIndex: Integer;
  out AViewportRect: TRectangle;
  out AUVScaleOffset: TVector4): Boolean;
var
  TileRes: Cardinal;
  InvAtlas: Single;
begin
  EnsureAtlasResourcesCreated;
  ATileIndex := -1;
  AViewportRect := TRectangle.Empty;
  AUVScaleOffset := TVector4.Zero;

  if FAllocatedTileCount >= CASTLE_MAX_SHADOW_ATLAS_TILES then
    Exit(False);

  TileRes := EnsureRange(ADesiredResolution, 64, FAtlasSize);
  if FShelfCursorX + TileRes > FAtlasSize then
  begin
    FShelfCursorX := 0;
    Inc(FShelfCursorY, FShelfRowHeight);
    FShelfRowHeight := 0;
  end;

  if FShelfCursorY + TileRes > FAtlasSize then
    Exit(False);

  ATileIndex := Integer(FAllocatedTileCount);
  AViewportRect := Rectangle(Integer(FShelfCursorX), Integer(FShelfCursorY), TileRes, TileRes);
  InvAtlas := 1.0 / Single(Max(Cardinal(1), FAtlasSize));
  AUVScaleOffset := Vector4(
    Single(TileRes) * InvAtlas,
    Single(TileRes) * InvAtlas,
    Single(FShelfCursorX) * InvAtlas,
    Single(FShelfCursorY) * InvAtlas);

  FPositionalTileRects[ATileIndex] := AViewportRect;
  FPositionalTiles[ATileIndex].LightViewProjMatrix := ALightViewProj;
  FPositionalTiles[ATileIndex].AtlasUVScaleOffset := AUVScaleOffset;

  Inc(FShelfCursorX, TileRes);
  FShelfRowHeight := Max(FShelfRowHeight, TileRes);
  Inc(FAllocatedTileCount);
  Result := True;
end;

procedure TCastleVulkanShadowAtlas.UploadShadowBuffers;
begin
  EnsureAtlasResourcesCreated;
  if FCascadeUniformBuffer <> nil then
    FCascadeUniformBuffer.UploadData(FCascadeBlock, SizeOf(FCascadeBlock), 0);
  if (FPositionalTileBuffer <> nil) and (FAllocatedTileCount > 0) then
    FPositionalTileBuffer.UploadData(
      FPositionalTiles[0],
      PtrUInt(FAllocatedTileCount) * SizeOf(TCastlePositionalShadowTileEntry),
      0);
end;

procedure TCastleVulkanShadowAtlas.RecordShadowTilePass(
  const ACmd: TRHICommandList;
  const AViewportRect: TRectangle;
  const ADepthBiasConstant, ADepthBiasSlope: Single);
var
  RenderInfo: TRHIRenderingInfo;
begin
  EnsureAtlasResourcesCreated;
  if (ACmd = nil) or (FShadowAtlasTexture = nil) then
    Exit;

  FillChar(RenderInfo, SizeOf(RenderInfo), 0);
  RenderInfo.RenderArea := AViewportRect;
  SetLength(RenderInfo.ColorAttachments, 0);
  RenderInfo.DepthAttachment.Texture := FShadowAtlasTexture;
  RenderInfo.DepthAttachment.LoadOp := loClear;
  RenderInfo.DepthAttachment.StoreOp := soStore;
  RenderInfo.DepthAttachment.ClearDepth := 1.0;

  ACmd.BeginRendering(RenderInfo);
  ACmd.SetViewport(FloatRectangle(AViewportRect), 0.0, 1.0);
  ACmd.SetScissor(AViewportRect);
  ACmd.SetDepthBias(ADepthBiasConstant, ADepthBiasSlope);
  ACmd.EndRendering;

  Inc(FTotalShadowTilePasses);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanHDRPostProcessor                                                }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanHDRPostProcessor.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FBloomThreshold := 1.0;
  FBloomKnee := 0.5;
  FBloomIntensity := 0.08;
  FBloomFilterRadius := 1.0;
  FExposure := 1.0;
  FGamma := 2.2;
  FSaturation := 1.0;
  FContrast := 1.0;
  FTonemapOperator := tmoACESFilmic;
  FEnableBloom := True;
  FEnableAutoExposure := False;
  FAdaptedLuminance := 0.18;
  FAdaptedExposure := 1.0;
  FTargetLuminance := 0.18;

  FAutoExposureParams.MinLogLum := -8.0;
  FAutoExposureParams.MaxLogLum := 4.0;
  FAutoExposureParams.TimeDelta := 1.0 / 60.0;
  FAutoExposureParams.AdaptationSpeed := 2.5;
  FAutoExposureParams.TargetMiddleGrey := 0.18;
  FAutoExposureParams.MinExposure := 0.1;
  FAutoExposureParams.MaxExposure := 10.0;
  FAutoExposureParams.TotalPixels := 1;
end;

destructor TCastleVulkanHDRPostProcessor.Destroy;
var
  I: Integer;
begin
  { Compute pipelines are owned by FDevice.FComputePipelineMap }
  FBloomDownsamplePipeline := nil;
  FBloomUpsamplePipeline := nil;
  FHistogramPipeline := nil;
  FreeAndNil(FCompositeFragShader);
  FreeAndNil(FHistogramShader);
  FreeAndNil(FBloomUpsampleShader);
  FreeAndNil(FBloomDownsampleShader);
  FreeAndNil(FHistogramDescriptorSet);
  FreeAndNil(FHistogramDescriptorLayout);
  FreeAndNil(FBloomDescriptorSet);
  FreeAndNil(FBloomDescriptorLayout);
  FreeAndNil(FExposureStateBuffer);
  FreeAndNil(FHistogramBuffer);
  FreeAndNil(FLinearClampSampler);
  for I := 0 to CASTLE_BLOOM_MAX_MIP_LEVELS - 1 do
    FreeAndNil(FBloomMipTextures[I]);
  FreeAndNil(FHDRSceneTexture);
  inherited;
end;

function TCastleVulkanHDRPostProcessor.GetBloomMipTexture(
  const AMipIndex: Cardinal): TVulkanRHITexture;
begin
  if AMipIndex < CASTLE_BLOOM_MAX_MIP_LEVELS then
    Result := FBloomMipTextures[AMipIndex]
  else
    Result := nil;
end;

function TCastleVulkanHDRPostProcessor.GetHistogramBinCount(
  const ABinIndex: Cardinal): Cardinal;
begin
  if ABinIndex < CASTLE_LUMINANCE_HISTOGRAM_BINS then
    Result := FHistogramBins[ABinIndex]
  else
    Result := 0;
end;

procedure TCastleVulkanHDRPostProcessor.EnsureHDRTargets(
  const AWidth, AHeight: Cardinal);
var
  TargetW, TargetH, MipW, MipH, M: Cardinal;
  TexDesc: TRHITextureDesc;
  I: Integer;
begin
  if FDevice = nil then Exit;
  TargetW := Max(Cardinal(2), AWidth);
  TargetH := Max(Cardinal(2), AHeight);
  if (FHDRSceneTexture <> nil) and (FWidth = TargetW) and (FHeight = TargetH) then
    Exit;

  FWidth := TargetW;
  FHeight := TargetH;

  for I := 0 to CASTLE_BLOOM_MAX_MIP_LEVELS - 1 do
    FreeAndNil(FBloomMipTextures[I]);
  FreeAndNil(FHDRSceneTexture);

  TexDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRGBA16_Float,
    [tuColorAttachment, tuSampled, tuStorage, tuTransferSrc, tuTransferDst], 1, 1);
  TexDesc.DebugName := 'HDRSceneColorTarget';
  FHDRSceneTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  MipW := Max(Cardinal(1), FWidth div 2);
  MipH := Max(Cardinal(1), FHeight div 2);
  FBloomMipCount := 0;
  for M := 0 to CASTLE_BLOOM_MAX_MIP_LEVELS - 1 do
  begin
    TexDesc := TRHITextureDesc.Create2D(
      MipW, MipH, pfRGBA16_Float,
      [tuColorAttachment, tuSampled, tuStorage, tuTransferSrc, tuTransferDst], 1, 1);
    TexDesc.DebugName := Format('BloomPyramidMip_%d', [M]);
    FBloomMipTextures[M] := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
    Inc(FBloomMipCount);
    if (MipW <= 2) and (MipH <= 2) then
      Break;
    MipW := Max(Cardinal(1), MipW div 2);
    MipH := Max(Cardinal(1), MipH div 2);
  end;
end;

procedure TCastleVulkanHDRPostProcessor.EnsurePipelinesCreated;
var
  SamplerDesc: TRHISamplerDesc;
  BufDesc: TRHIBufferDesc;
  BloomBindings: array[0..1] of TRHIDescriptorBindingDesc;
  HistBindings: array[0..2] of TRHIDescriptorBindingDesc;
  ShaderGen: TCastleShaderGeneratorRHI;
  CompDesc: TRHIComputePipelineDesc;
  InitialExposureState: array[0..3] of Single;
begin
  if FDevice = nil then Exit;

  if FLinearClampSampler = nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    FLinearClampSampler := FDevice.CreateSampler(SamplerDesc);
  end;

  if FHistogramBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      CASTLE_LUMINANCE_HISTOGRAM_BINS * SizeOf(Cardinal),
      [buStorage, buTransferDst], muCpuToGpu, 'LuminanceHistogramSSBO');
    FHistogramBuffer := FDevice.CreateBuffer(BufDesc, nil);
  end;

  if FExposureStateBuffer = nil then
  begin
    InitialExposureState[0] := FAdaptedLuminance;
    InitialExposureState[1] := FAdaptedExposure;
    InitialExposureState[2] := FTargetLuminance;
    InitialExposureState[3] := 0.0;
    BufDesc := TRHIBufferDesc.Create(
      4 * SizeOf(Single),
      [buStorage, buTransferDst], muCpuToGpu, 'AutoExposureStateSSBO');
    FExposureStateBuffer := FDevice.CreateBuffer(BufDesc, @InitialExposureState[0]);
  end;

  if FBloomDescriptorLayout = nil then
  begin
    FillChar(BloomBindings, SizeOf(BloomBindings), 0);
    BloomBindings[0].Binding := 0;
    BloomBindings[0].DescriptorType := dtCombinedImageSampler;
    BloomBindings[0].Count := 1;
    BloomBindings[0].StageFlags := [ssCompute];
    BloomBindings[1].Binding := 1;
    BloomBindings[1].DescriptorType := dtStorageImage;
    BloomBindings[1].Count := 1;
    BloomBindings[1].StageFlags := [ssCompute];
    FBloomDescriptorLayout := FDevice.CreateDescriptorSetLayout(BloomBindings);
    FBloomDescriptorSet := FDevice.CreateDescriptorSet(FBloomDescriptorLayout);
  end;

  if FHistogramDescriptorLayout = nil then
  begin
    FillChar(HistBindings, SizeOf(HistBindings), 0);
    HistBindings[0].Binding := 0;
    HistBindings[0].DescriptorType := dtCombinedImageSampler;
    HistBindings[0].Count := 1;
    HistBindings[0].StageFlags := [ssCompute];
    HistBindings[1].Binding := 1;
    HistBindings[1].DescriptorType := dtStorageBuffer;
    HistBindings[1].Count := 1;
    HistBindings[1].StageFlags := [ssCompute];
    HistBindings[2].Binding := 2;
    HistBindings[2].DescriptorType := dtStorageBuffer;
    HistBindings[2].Count := 1;
    HistBindings[2].StageFlags := [ssCompute];
    FHistogramDescriptorLayout := FDevice.CreateDescriptorSetLayout(HistBindings);
    FHistogramDescriptorSet := FDevice.CreateDescriptorSet(FHistogramDescriptorLayout);
  end;

  if FBloomDownsamplePipeline = nil then
  begin
    ShaderGen := TCastleShaderGeneratorRHI.Create(rbVulkan);
    try
      FBloomDownsampleShader := FDevice.CreateShaderModuleFromGLSL(
        ssCompute, ShaderGen.GenerateBloomDownsampleComputeShader(8, 8), 'BloomDownsampleCS');
      FBloomUpsampleShader := FDevice.CreateShaderModuleFromGLSL(
        ssCompute, ShaderGen.GenerateBloomUpsampleComputeShader(8, 8), 'BloomUpsampleCS');
      FHistogramShader := FDevice.CreateShaderModuleFromGLSL(
        ssCompute, ShaderGen.GenerateLuminanceHistogramComputeShader(16, 16), 'LuminanceHistogramCS');
      FCompositeFragShader := FDevice.CreateShaderModuleFromGLSL(
        ssFragment, ShaderGen.GenerateHDRCompositeFragmentShader, 'HDRCompositeFS');
    finally
      FreeAndNil(ShaderGen);
    end;

    FillChar(CompDesc, SizeOf(CompDesc), 0);
    CompDesc.ComputeShader := FBloomDownsampleShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FBloomDescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleBloomPushConstants);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'BloomDownsamplePSO';
    FBloomDownsamplePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);

    CompDesc.ComputeShader := FBloomUpsampleShader;
    CompDesc.DebugName := 'BloomUpsamplePSO';
    FBloomUpsamplePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);

    FillChar(CompDesc, SizeOf(CompDesc), 0);
    CompDesc.ComputeShader := FHistogramShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FHistogramDescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleAutoExposureParams);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'LuminanceHistogramPSO';
    FHistogramPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  end;
end;

function TCastleVulkanHDRPostProcessor.DispatchBloomPyramid(
  const ACmd: TRHICommandList): Cardinal;
var
  M: Integer;
  SrcTex, DstTex: TVulkanRHITexture;
  PC: TCastleBloomPushConstants;
  GroupsX, GroupsY: Cardinal;
begin
  Result := 0;
  if (FWidth = 0) or (FHeight = 0) then
    EnsureHDRTargets(1280, 720);
  EnsurePipelinesCreated;

  if (FBloomMipCount = 0) or (FHDRSceneTexture = nil) then
    Exit;

  { 1. Progressive 13-tap Jiménez Downsample Chain (HDRScene -> Mip 0 -> Mip 1 -> ... -> Mip N-1) }
  for M := 0 to Integer(FBloomMipCount) - 1 do
  begin
    if M = 0 then
      SrcTex := FHDRSceneTexture
    else
      SrcTex := FBloomMipTextures[M - 1];
    DstTex := FBloomMipTextures[M];
    if (SrcTex = nil) or (DstTex = nil) then Continue;

    FillChar(PC, SizeOf(PC), 0);
    PC.SrcTexelSize := Vector2(1.0 / Max(Cardinal(1), SrcTex.Desc.Width),
                               1.0 / Max(Cardinal(1), SrcTex.Desc.Height));
    PC.Threshold := FBloomThreshold;
    PC.Knee := FBloomKnee;
    PC.FilterRadius := FBloomFilterRadius;
    PC.MipLevel := Cardinal(M);
    if M = 0 then PC.IsFirstDownsample := 1 else PC.IsFirstDownsample := 0;
    PC.DstPackedSize := (DstTex.Desc.Height shl 16) or (DstTex.Desc.Width and $FFFF);

    GroupsX := (DstTex.Desc.Width + 7) div 8;
    GroupsY := (DstTex.Desc.Height + 7) div 8;

    if ACmd <> nil then
    begin
      ACmd.TransitionTexture(SrcTex, rsShaderRead);
      ACmd.TransitionTexture(DstTex, rsTransferDst);
      FBloomDescriptorSet.BindTexture(0, SrcTex, FLinearClampSampler);
      FBloomDescriptorSet.BindTexture(1, DstTex, FLinearClampSampler);
      FBloomDescriptorSet.Update;
      ACmd.BindComputePipeline(FBloomDownsamplePipeline);
      ACmd.BindComputeDescriptorSet(0, FBloomDescriptorSet, []);
      ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
      ACmd.Dispatch(GroupsX, GroupsY, 1);
    end;

    Inc(FTotalBloomDownsampleDispatches);
    Inc(Result);
  end;

  { 2. Progressive 9-tap 3x3 Tent-Filter Upsample Chain (Mip N-1 -> Mip N-2 -> ... -> Mip 0) }
  if FBloomMipCount > 1 then
    for M := Integer(FBloomMipCount) - 1 downto 1 do
    begin
      SrcTex := FBloomMipTextures[M];
      DstTex := FBloomMipTextures[M - 1];
      if (SrcTex = nil) or (DstTex = nil) then Continue;

      FillChar(PC, SizeOf(PC), 0);
      PC.SrcTexelSize := Vector2(1.0 / Max(Cardinal(1), SrcTex.Desc.Width),
                                 1.0 / Max(Cardinal(1), SrcTex.Desc.Height));
      PC.Threshold := FBloomThreshold;
      PC.Knee := FBloomKnee;
      PC.FilterRadius := FBloomFilterRadius;
      PC.MipLevel := Cardinal(M - 1);
      PC.IsFirstDownsample := 0;
      PC.DstPackedSize := (DstTex.Desc.Height shl 16) or (DstTex.Desc.Width and $FFFF);

      GroupsX := (DstTex.Desc.Width + 7) div 8;
      GroupsY := (DstTex.Desc.Height + 7) div 8;

      if ACmd <> nil then
      begin
        ACmd.TransitionTexture(SrcTex, rsShaderRead);
        ACmd.TransitionTexture(DstTex, rsTransferDst);
        FBloomDescriptorSet.BindTexture(0, SrcTex, FLinearClampSampler);
        FBloomDescriptorSet.BindTexture(1, DstTex, FLinearClampSampler);
        FBloomDescriptorSet.Update;
        ACmd.BindComputePipeline(FBloomUpsamplePipeline);
        ACmd.BindComputeDescriptorSet(0, FBloomDescriptorSet, []);
        ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
        ACmd.Dispatch(GroupsX, GroupsY, 1);
      end;

      Inc(FTotalBloomUpsampleDispatches);
      Inc(Result);
    end;

  if (ACmd <> nil) and (FBloomMipTextures[0] <> nil) then
    ACmd.TransitionTexture(FBloomMipTextures[0], rsShaderRead);
end;

function TCastleVulkanHDRPostProcessor.UpdateAutoExposure(
  const ACmd: TRHICommandList;
  const ASceneLinearSamples: array of TVector3;
  const ADeltaTime: Single): Single;
var
  I, Bin: Integer;
  Lum, LogLumNorm, BinLogLum, WeightedLogSum, TotalWeight, Alpha, RawExposure: Single;
  ExposureState: array[0..3] of Single;
begin
  if (FWidth = 0) or (FHeight = 0) then
    EnsureHDRTargets(1280, 720);
  EnsurePipelinesCreated;

  FillChar(FHistogramBins, SizeOf(FHistogramBins), 0);
  for I := 0 to High(ASceneLinearSamples) do
  begin
    Lum := ASceneLinearSamples[I].X * 0.2126 +
           ASceneLinearSamples[I].Y * 0.7152 +
           ASceneLinearSamples[I].Z * 0.0722;
    if Lum < 1e-4 then
      Bin := 0
    else
    begin
      LogLumNorm := EnsureRange(
        (Log2(Lum) - FAutoExposureParams.MinLogLum) /
        Max(1e-4, FAutoExposureParams.MaxLogLum - FAutoExposureParams.MinLogLum),
        0.0, 1.0);
      Bin := EnsureRange(Trunc(LogLumNorm * 254.0 + 1.0), 1, 255);
    end;
    Inc(FHistogramBins[Bin]);
  end;

  WeightedLogSum := 0.0;
  TotalWeight := 0.0;
  for Bin := 1 to CASTLE_LUMINANCE_HISTOGRAM_BINS - 1 do
    if FHistogramBins[Bin] > 0 then
    begin
      BinLogLum := FAutoExposureParams.MinLogLum +
        ((Bin - 1.0) / 254.0) * (FAutoExposureParams.MaxLogLum - FAutoExposureParams.MinLogLum);
      WeightedLogSum := WeightedLogSum + BinLogLum * FHistogramBins[Bin];
      TotalWeight := TotalWeight + FHistogramBins[Bin];
    end;

  if TotalWeight > 0.0 then
    FTargetLuminance := Power(2.0, WeightedLogSum / TotalWeight)
  else
    FTargetLuminance := FAutoExposureParams.TargetMiddleGrey;

  FAutoExposureParams.TimeDelta := Max(0.0, ADeltaTime);
  FAutoExposureParams.TotalPixels := Max(Cardinal(1), Cardinal(Length(ASceneLinearSamples)));

  Alpha := 1.0 - Exp(-FAutoExposureParams.TimeDelta * FAutoExposureParams.AdaptationSpeed);
  FAdaptedLuminance := FAdaptedLuminance + (FTargetLuminance - FAdaptedLuminance) * EnsureRange(Alpha, 0.0, 1.0);
  FAdaptedLuminance := Max(1e-4, FAdaptedLuminance);

  RawExposure := FAutoExposureParams.TargetMiddleGrey / FAdaptedLuminance;
  FAdaptedExposure := EnsureRange(RawExposure, FAutoExposureParams.MinExposure, FAutoExposureParams.MaxExposure);

  if FHistogramBuffer <> nil then
    FHistogramBuffer.UploadData(FHistogramBins[0], SizeOf(FHistogramBins), 0);

  if FExposureStateBuffer <> nil then
  begin
    ExposureState[0] := FAdaptedLuminance;
    ExposureState[1] := FAdaptedExposure;
    ExposureState[2] := FTargetLuminance;
    ExposureState[3] := 0.0;
    FExposureStateBuffer.UploadData(ExposureState[0], SizeOf(ExposureState), 0);
  end;

  if (ACmd <> nil) and (FHDRSceneTexture <> nil) then
  begin
    FHistogramDescriptorSet.BindTexture(0, FHDRSceneTexture, FLinearClampSampler);
    FHistogramDescriptorSet.BindStorageBuffer(1, FHistogramBuffer, 0, FHistogramBuffer.Desc.Size);
    FHistogramDescriptorSet.BindStorageBuffer(2, FExposureStateBuffer, 0, FExposureStateBuffer.Desc.Size);
    FHistogramDescriptorSet.Update;

    ACmd.BindComputePipeline(FHistogramPipeline);
    ACmd.BindComputeDescriptorSet(0, FHistogramDescriptorSet, []);
    ACmd.PushConstants([ssCompute], 0, SizeOf(FAutoExposureParams), FAutoExposureParams);
    ACmd.Dispatch((FWidth + 15) div 16, (FHeight + 15) div 16, 1);
  end;

  Inc(FTotalHistogramDispatches);
  Result := FAdaptedExposure;
end;

procedure TCastleVulkanHDRPostProcessor.ExecuteCompositePass(
  const ACmd: TRHICommandList; const ADstLDRTarget: TRHITexture);
var
  RenderInfo: TRHIRenderingInfo;
  TargetW, TargetH: Cardinal;
  PC: TCastleHDRCompositePushConstants;
begin
  EnsurePipelinesCreated;
  if (ACmd <> nil) and (ADstLDRTarget <> nil) then
  begin
    TargetW := Max(Cardinal(1), ADstLDRTarget.Desc.Width);
    TargetH := Max(Cardinal(1), ADstLDRTarget.Desc.Height);
    if FHDRSceneTexture <> nil then
      ACmd.TransitionTexture(FHDRSceneTexture, rsShaderRead);
    if FBloomMipTextures[0] <> nil then
      ACmd.TransitionTexture(FBloomMipTextures[0], rsShaderRead);
    ACmd.TransitionTexture(ADstLDRTarget, rsColorAttachment);

    RenderInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, TargetW, TargetH),
      ADstLDRTarget, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
      nil, loDontCare, 1.0);
    ACmd.BeginRendering(RenderInfo);
    ACmd.SetViewport(FloatRectangle(0, 0, TargetW, TargetH));
    ACmd.SetScissor(RenderInfo.RenderArea);

    FillChar(PC, SizeOf(PC), 0);
    PC.Exposure := FExposure;
    PC.BloomIntensity := FBloomIntensity;
    PC.Gamma := FGamma;
    PC.Saturation := FSaturation;
    PC.Contrast := FContrast;
    PC.TonemapOperator := Ord(FTonemapOperator);
    if FEnableBloom then PC.EnableBloom := 1 else PC.EnableBloom := 0;
    if FEnableAutoExposure then PC.EnableAutoExposure := 1 else PC.EnableAutoExposure := 0;
    ACmd.PushConstants([ssFragment], 0, SizeOf(PC), PC);

    ACmd.EndRendering;
  end;
  Inc(FTotalCompositePasses);
end;

procedure TCastleVulkanHDRPostProcessor.BuildDefaultFrameRenderGraph(
  const AGraph: TRHIRenderGraph;
  const AWidth, AHeight: Cardinal;
  const ASwapchainColor: TRHITexture);
var
  HDRColorDesc, HDRDepthDesc, BloomMip0Desc: TRHITextureDesc;
  HSceneHDR, HSceneDepth, HBloomMip0, HSwapchain, HExposureBuf: TRHIRenderGraphResourceHandle;
  PassForward, PassBloom, PassHistogram, PassComposite: TRHIRenderGraphPass;
begin
  if AGraph = nil then Exit;
  EnsureHDRTargets(AWidth, AHeight);
  EnsurePipelinesCreated;

  AGraph.Reset;

  HDRColorDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRGBA16_Float,
    [tuColorAttachment, tuSampled, tuStorage], 1, 1);
  HDRDepthDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfD32_Float,
    [tuDepthStencil, tuSampled], 1, 1);
  BloomMip0Desc := TRHITextureDesc.Create2D(
    Max(Cardinal(1), FWidth div 2), Max(Cardinal(1), FHeight div 2), pfRGBA16_Float,
    [tuColorAttachment, tuSampled, tuStorage], 1, 1);

  HSceneHDR := AGraph.DeclareTransientTexture('RG_HDRSceneColor', HDRColorDesc);
  HSceneDepth := AGraph.DeclareTransientTexture('RG_HDRSceneDepth', HDRDepthDesc);
  HBloomMip0 := AGraph.DeclareTransientTexture('RG_BloomMip0', BloomMip0Desc);
  HSwapchain := AGraph.ImportExternalTexture('RG_SwapchainBackbuffer', ASwapchainColor,
    rsUndefined, rsPresent);
  HExposureBuf := AGraph.ImportExternalBuffer('RG_AutoExposureState', FExposureStateBuffer);

  { 1. 3D Forward HDR Pass }
  PassForward := AGraph.AddPass('Forward3DHDRPass', rgptGraphics);
  PassForward.WriteColorAttachment(HSceneHDR, loClear, Vector4(0.0, 0.0, 0.0, 1.0), soStore);
  PassForward.WriteDepthAttachment(HSceneDepth, loClear, 1.0, soStore);

  { 2. Bloom Mip-Chain Compute Pass }
  PassBloom := AGraph.AddPass('BloomPyramidComputePass', rgptCompute);
  PassBloom.ReadTexture(HSceneHDR, rsShaderRead);
  PassBloom.WriteStorageTexture(HBloomMip0, rsTransferDst);

  { 3. Luminance Histogram & Auto-Exposure Compute Pass }
  PassHistogram := AGraph.AddPass('LuminanceHistogramComputePass', rgptCompute);
  PassHistogram.ReadTexture(HSceneHDR, rsShaderRead);
  PassHistogram.WriteBuffer(HExposureBuf);

  { 4. ACES/AgX Tonemap & sRGB Composite Pass }
  PassComposite := AGraph.AddPass('TonemapCompositePass', rgptGraphics);
  PassComposite.ReadTexture(HSceneHDR, rsShaderRead);
  PassComposite.ReadTexture(HBloomMip0, rsShaderRead);
  PassComposite.ReadBuffer(HExposureBuf);
  PassComposite.WriteColorAttachment(HSwapchain, loClear, Vector4(0.0, 0.0, 0.0, 1.0), soStore);
end;

class function TCastleVulkanHDRPostProcessor.EvaluateKarisWeight(
  const ALinearRGB: TVector3): Single;
var
  Luma: Single;
begin
  Luma := ALinearRGB.X * 0.2126 + ALinearRGB.Y * 0.7152 + ALinearRGB.Z * 0.0722;
  Result := 1.0 / (1.0 + Max(0.0, Luma));
end;

class function TCastleVulkanHDRPostProcessor.EvaluateKarisAverage4(
  const C0, C1, C2, C3: TVector3): TVector3;
var
  W0, W1, W2, W3, WSum: Single;
begin
  W0 := EvaluateKarisWeight(C0);
  W1 := EvaluateKarisWeight(C1);
  W2 := EvaluateKarisWeight(C2);
  W3 := EvaluateKarisWeight(C3);
  WSum := Max(1e-5, W0 + W1 + W2 + W3);
  Result := (C0 * W0 + C1 * W1 + C2 * W2 + C3 * W3) / WSum;
end;

class function TCastleVulkanHDRPostProcessor.EvaluateSoftThreshold(
  const ALinearRGB: TVector3; const AThreshold, AKnee: Single): TVector3;
var
  Brightness, Soft, Contribution: Single;
begin
  Brightness := Max(Max(ALinearRGB.X, ALinearRGB.Y), ALinearRGB.Z);
  Soft := EnsureRange(Brightness - AThreshold + AKnee, 0.0, 2.0 * AKnee);
  Soft := (Soft * Soft) / Max(1e-5, 4.0 * AKnee + 1e-5);
  Contribution := Max(Soft, Brightness - AThreshold) / Max(1e-5, Brightness);
  Result := ALinearRGB * Max(0.0, Contribution);
end;

class function TCastleVulkanHDRPostProcessor.EvaluateTonemapReinhard(
  const AHDR: TVector3): TVector3;
begin
  Result := Vector3(
    Max(0.0, AHDR.X) / (1.0 + Max(0.0, AHDR.X)),
    Max(0.0, AHDR.Y) / (1.0 + Max(0.0, AHDR.Y)),
    Max(0.0, AHDR.Z) / (1.0 + Max(0.0, AHDR.Z)));
end;

class function TCastleVulkanHDRPostProcessor.EvaluateTonemapACESFilmic(
  const AHDR: TVector3): TVector3;

  function ACESChannel(const XVal: Single): Single;
  const
    A = 2.51;
    B = 0.03;
    C = 2.43;
    D = 0.59;
    E = 0.14;
  var
    X: Single;
  begin
    X := Max(0.0, XVal);
    Result := EnsureRange((X * (A * X + B)) / (X * (C * X + D) + E), 0.0, 1.0);
  end;

begin
  Result := Vector3(ACESChannel(AHDR.X), ACESChannel(AHDR.Y), ACESChannel(AHDR.Z));
end;

class function TCastleVulkanHDRPostProcessor.EvaluateTonemapAgX(
  const AHDR: TVector3): TVector3;

  function AgXContrast(const X: Single): Single;
  var
    X2, X4: Single;
  begin
    X2 := X * X;
    X4 := X2 * X2;
    Result := 15.5 * X4 * X2 - 40.14 * X4 * X + 31.96 * X4 -
              6.868 * X2 * X + 0.4298 * X2 + 0.1191 * X - 0.00232;
  end;

const
  MinEv = -12.47393;
  MaxEv = 4.026069;
var
  R, G, B, InR, InG, InB, OutR, OutG, OutB: Single;
begin
  R := Max(1e-6, AHDR.X);
  G := Max(1e-6, AHDR.Y);
  B := Max(1e-6, AHDR.Z);

  { AgX Inset Matrix (column-major in GLSL) }
  InR := 0.842479062253094 * R + 0.0784335999999992 * G + 0.0792237451477643 * B;
  InG := 0.0423282422610123 * R + 0.878468636469772 * G + 0.0791661274605434 * B;
  InB := 0.0423756549057051 * R + 0.0784336 * G + 0.879142973793104 * B;

  InR := (EnsureRange(Log2(Max(1e-6, InR)), MinEv, MaxEv) - MinEv) / (MaxEv - MinEv);
  InG := (EnsureRange(Log2(Max(1e-6, InG)), MinEv, MaxEv) - MinEv) / (MaxEv - MinEv);
  InB := (EnsureRange(Log2(Max(1e-6, InB)), MinEv, MaxEv) - MinEv) / (MaxEv - MinEv);

  InR := AgXContrast(InR);
  InG := AgXContrast(InG);
  InB := AgXContrast(InB);

  { AgX Outset Matrix }
  OutR :=  1.19687900512017  * InR - 0.0980208811401368 * InG - 0.0990297440797205 * InB;
  OutG := -0.0528968517574562 * InR + 1.15190312990417  * InG - 0.0989611768448433 * InB;
  OutB := -0.0529716355144438 * InR - 0.0980434501171241 * InG + 1.15107367264116  * InB;

  Result := Vector3(
    EnsureRange(Power(Max(0.0, OutR), 2.2), 0.0, 1.0),
    EnsureRange(Power(Max(0.0, OutG), 2.2), 0.0, 1.0),
    EnsureRange(Power(Max(0.0, OutB), 2.2), 0.0, 1.0));
end;

class function TCastleVulkanHDRPostProcessor.EvaluateLinearToSRGB(
  const ALinear: TVector3): TVector3;

  function ChannelToSRGB(const CVal: Single): Single;
  var
    C: Single;
  begin
    C := Max(0.0, CVal);
    if C <= 0.0031308 then
      Result := C * 12.92
    else
      Result := 1.055 * Power(C, 1.0 / 2.4) - 0.055;
    Result := EnsureRange(Result, 0.0, 1.0);
  end;

begin
  Result := Vector3(
    ChannelToSRGB(ALinear.X),
    ChannelToSRGB(ALinear.Y),
    ChannelToSRGB(ALinear.Z));
end;

function TCastleVulkanHDRPostProcessor.EvaluateCompositeColor(
  const AHDRSceneColor, ABloomColor: TVector3): TVector3;
var
  Combined, Graded, Mapped: TVector3;
  EffExposure, Luma: Single;
begin
  Combined := AHDRSceneColor;
  if FEnableBloom then
    Combined := Combined + ABloomColor * FBloomIntensity;

  EffExposure := FExposure;
  if FEnableAutoExposure then
    EffExposure := EffExposure * Max(1e-4, FAdaptedExposure);

  Combined := Combined * EffExposure;

  { Apply saturation & contrast color grading }
  Luma := Combined.X * 0.2126 + Combined.Y * 0.7152 + Combined.Z * 0.0722;
  Graded := Vector3(
    Luma + (Combined.X - Luma) * FSaturation,
    Luma + (Combined.Y - Luma) * FSaturation,
    Luma + (Combined.Z - Luma) * FSaturation);
  Graded := Vector3(
    Max(0.0, (Graded.X - 0.18) * FContrast + 0.18),
    Max(0.0, (Graded.Y - 0.18) * FContrast + 0.18),
    Max(0.0, (Graded.Z - 0.18) * FContrast + 0.18));

  case FTonemapOperator of
    tmoLinear:
      Mapped := Vector3(
        EnsureRange(Graded.X, 0.0, 1.0),
        EnsureRange(Graded.Y, 0.0, 1.0),
        EnsureRange(Graded.Z, 0.0, 1.0));
    tmoReinhard:
      Mapped := EvaluateTonemapReinhard(Graded);
    tmoACESFilmic:
      Mapped := EvaluateTonemapACESFilmic(Graded);
    tmoAgX:
      Mapped := EvaluateTonemapAgX(Graded);
  end;

  if Abs(FGamma - 2.2) < 1e-3 then
    Result := EvaluateLinearToSRGB(Mapped)
  else
    Result := Vector3(
      Power(Max(0.0, Mapped.X), 1.0 / Max(1e-3, FGamma)),
      Power(Max(0.0, Mapped.Y), 1.0 / Max(1e-3, FGamma)),
      Power(Max(0.0, Mapped.Z), 1.0 / Max(1e-3, FGamma)));
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanGTAO                                                            }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanGTAO.Create(const ADevice: TVulkanRHIDevice);
var
  SamplerDesc: TRHISamplerDesc;
begin
  inherited Create;
  FDevice := ADevice;
  FEffectRadius := 1.5;
  FFalloffRange := 0.6;
  FPower := 1.5;
  FZNear := 0.1;
  FZFar := 500.0;
  FSliceCount := 3;
  FStepsPerSlice := 4;

  if FDevice <> nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    FLinearClampSampler := FDevice.CreateSampler(SamplerDesc);
  end;
end;

destructor TCastleVulkanGTAO.Destroy;
begin
  FGTAOPipeline := nil;
  FDenoisePipeline := nil;
  FreeAndNil(FDenoiseShader);
  FreeAndNil(FGTAOShader);
  FreeAndNil(FDenoiseDescriptorSet);
  FreeAndNil(FDenoiseDescriptorLayout);
  FreeAndNil(FGTAODescriptorSet);
  FreeAndNil(FGTAODescriptorLayout);
  FreeAndNil(FDenoisedGTAOTexture);
  FreeAndNil(FRawGTAOTexture);
  FreeAndNil(FLinearClampSampler);
  inherited;
end;

procedure TCastleVulkanGTAO.EnsurePipelinesCreated;
var
  Gen: TCastleShaderGeneratorRHI;
  GTAOBindings: array[0..1] of TRHIDescriptorBindingDesc;
  DenoiseBindings: array[0..2] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FGTAOPipeline <> nil) then
    Exit;

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FGTAOShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateGTAOComputeShader(8, 8), 'GTAOHorizon_CS');
    FDenoiseShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateGTAODenoiseComputeShader(8, 8), 'GTAODenoise_CS');

    FillChar(GTAOBindings, SizeOf(GTAOBindings), 0);
    GTAOBindings[0].Binding := 0;
    GTAOBindings[0].DescriptorType := dtCombinedImageSampler;
    GTAOBindings[0].Count := 1;
    GTAOBindings[0].StageFlags := [ssCompute];

    GTAOBindings[1].Binding := 1;
    GTAOBindings[1].DescriptorType := dtStorageImage;
    GTAOBindings[1].Count := 1;
    GTAOBindings[1].StageFlags := [ssCompute];

    FGTAODescriptorLayout := FDevice.CreateDescriptorSetLayout(GTAOBindings);
    FGTAODescriptorSet := FDevice.CreateDescriptorSet(FGTAODescriptorLayout);

    FillChar(DenoiseBindings, SizeOf(DenoiseBindings), 0);
    DenoiseBindings[0] := GTAOBindings[0];
    DenoiseBindings[1].Binding := 1;
    DenoiseBindings[1].DescriptorType := dtCombinedImageSampler;
    DenoiseBindings[1].Count := 1;
    DenoiseBindings[1].StageFlags := [ssCompute];

    DenoiseBindings[2].Binding := 2;
    DenoiseBindings[2].DescriptorType := dtStorageImage;
    DenoiseBindings[2].Count := 1;
    DenoiseBindings[2].StageFlags := [ssCompute];

    FDenoiseDescriptorLayout := FDevice.CreateDescriptorSetLayout(DenoiseBindings);
    FDenoiseDescriptorSet := FDevice.CreateDescriptorSet(FDenoiseDescriptorLayout);

    FillChar(CompDesc, SizeOf(CompDesc), 0);
    CompDesc.ComputeShader := FGTAOShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FGTAODescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleGTAOPushConstants);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'GTAOHorizonComputePSO';
    FGTAOPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);

    CompDesc.ComputeShader := FDenoiseShader;
    CompDesc.DescriptorSetLayouts[0] := FDenoiseDescriptorLayout;
    CompDesc.DebugName := 'GTAODenoiseComputePSO';
    FDenoisePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TCastleVulkanGTAO.EnsureGTAOTargets(const AWidth, AHeight: Cardinal;
  const AHalfResolution: Boolean);
var
  TargetW, TargetH: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  if AHalfResolution then
  begin
    TargetW := Max(Cardinal(1), AWidth div 2);
    TargetH := Max(Cardinal(1), AHeight div 2);
  end else
  begin
    TargetW := Max(Cardinal(1), AWidth);
    TargetH := Max(Cardinal(1), AHeight);
  end;

  if (FRawGTAOTexture <> nil) and (FWidth = TargetW) and (FHeight = TargetH) and
     (FHalfResolution = AHalfResolution) then
    Exit;

  FWidth := TargetW;
  FHeight := TargetH;
  FHalfResolution := AHalfResolution;

  FreeAndNil(FRawGTAOTexture);
  FreeAndNil(FDenoisedGTAOTexture);

  if FDevice = nil then
    Exit;

  TexDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfR16_Float,
    [tuSampled, tuStorage, tuColorAttachment], 1, 1);
  TexDesc.DebugName := 'GTAORawTexture';
  FRawGTAOTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc.DebugName := 'GTAODenoisedTexture';
  FDenoisedGTAOTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanGTAO.DispatchGTAO(const ACmd: TRHICommandList;
  const ADepthTexture: TRHITexture): Cardinal;
var
  PC: TCastleGTAOPushConstants;
  GroupsX, GroupsY: Cardinal;
begin
  Result := 0;
  if (ACmd = nil) or (FDevice = nil) then
    Exit;

  if FRawGTAOTexture = nil then
  begin
    if ADepthTexture <> nil then
      EnsureGTAOTargets(ADepthTexture.Desc.Width, ADepthTexture.Desc.Height, FHalfResolution)
    else
      EnsureGTAOTargets(1280, 720, FHalfResolution);
  end;

  EnsurePipelinesCreated;

  FillChar(PC, SizeOf(PC), 0);
  PC.InvResolution := Vector2(1.0 / Max(Cardinal(1), FWidth), 1.0 / Max(Cardinal(1), FHeight));
  PC.ProjScale := Vector2(1.0, 1.0);
  PC.ZNear := FZNear;
  PC.ZFar := FZFar;
  PC.EffectRadius := FEffectRadius;
  PC.FalloffRange := FFalloffRange;
  PC.Power := FPower;
  PC.SliceCount := Max(Cardinal(1), FSliceCount);
  PC.StepsPerSlice := Max(Cardinal(1), FStepsPerSlice);

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;

  { 1. Raw GTAO Horizon Integral Pass }
  PC.DenoisePass := 0;
  ACmd.TransitionTexture(FRawGTAOTexture, rsTransferDst);
  if ADepthTexture <> nil then
    FGTAODescriptorSet.BindTexture(0, ADepthTexture, FLinearClampSampler);
  FGTAODescriptorSet.BindTexture(1, FRawGTAOTexture, FLinearClampSampler);
  FGTAODescriptorSet.Update;

  ACmd.BindComputePipeline(FGTAOPipeline);
  ACmd.BindComputeDescriptorSet(0, FGTAODescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch(GroupsX, GroupsY, 1);
  Inc(FTotalGTAODispatches);
  Inc(Result);

  { 2. 5x5 Depth-Aware Cross-Bilateral Spatial Denoiser Pass }
  PC.DenoisePass := 1;
  ACmd.TransitionTexture(FRawGTAOTexture, rsShaderRead);
  ACmd.TransitionTexture(FDenoisedGTAOTexture, rsTransferDst);
  if ADepthTexture <> nil then
    FDenoiseDescriptorSet.BindTexture(0, ADepthTexture, FLinearClampSampler);
  FDenoiseDescriptorSet.BindTexture(1, FRawGTAOTexture, FLinearClampSampler);
  FDenoiseDescriptorSet.BindTexture(2, FDenoisedGTAOTexture, FLinearClampSampler);
  FDenoiseDescriptorSet.Update;

  ACmd.BindComputePipeline(FDenoisePipeline);
  ACmd.BindComputeDescriptorSet(0, FDenoiseDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch(GroupsX, GroupsY, 1);
  ACmd.TransitionTexture(FDenoisedGTAOTexture, rsShaderRead);
  Inc(FTotalDenoiseDispatches);
  Inc(Result);
end;

class function TCastleVulkanGTAO.ReconstructViewPosition(
  const AUV, AProjScale: TVector2; const ALinearZ: Single): TVector3;
var
  NDC: TVector2;
begin
  NDC := Vector2(AUV.X * 2.0 - 1.0, AUV.Y * 2.0 - 1.0);
  Result := Vector3(NDC.X * AProjScale.X * ALinearZ, NDC.Y * AProjScale.Y * ALinearZ, -ALinearZ);
end;

class function TCastleVulkanGTAO.IntegrateGTAOHorizonSlice(
  const AH1, AH2, ANormalAngle: Single): Single;
var
  SinN, CosN, I1, I2: Single;
begin
  SinN := Sin(ANormalAngle);
  CosN := Cos(ANormalAngle);
  I1 := (-Cos(2.0 * AH1 - ANormalAngle) + CosN + 2.0 * AH1 * SinN) * 0.25;
  I2 := (-Cos(2.0 * AH2 - ANormalAngle) + CosN + 2.0 * AH2 * SinN) * 0.25;
  Result := EnsureRange(I1 + I2, 0.0, 1.0);
end;

class function TCastleVulkanGTAO.ComputeBilateralDepthWeight(
  const ACenterDepth, ASampleDepth, ASigmaDepth: Single): Single;
var
  Diff: Single;
begin
  Diff := Abs(ACenterDepth - ASampleDepth) / Max(1e-5, ASigmaDepth);
  Result := Exp(-Diff * Diff);
end;

function TCastleVulkanGTAO.EvaluateGTAOFromHorizonCosines(
  const AMaxCos1, AMaxCos2, ANormalAngle: Single): Single;
var
  H1, H2, SliceVis: Single;
begin
  H1 := -ArcCos(EnsureRange(AMaxCos1, -1.0, 1.0));
  H2 :=  ArcCos(EnsureRange(AMaxCos2, -1.0, 1.0));
  SliceVis := IntegrateGTAOHorizonSlice(H1, H2, ANormalAngle);
  Result := Math.Power(EnsureRange(SliceVis, 0.0, 1.0), Max(0.01, FPower));
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanSSR                                                             }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanSSR.Create(const ADevice: TVulkanRHIDevice);
var
  SamplerDesc: TRHISamplerDesc;
begin
  inherited Create;
  FDevice := ADevice;
  FZNear := 0.1;
  FZFar := 500.0;
  FMaxDistance := 50.0;
  FThickness := 0.25;
  FMaxRoughness := 0.6;
  FEdgeFadeWidth := 0.12;
  FIntensity := 1.0;
  FMaxSteps := 48;
  FHiZMipCount := 6;

  if FDevice <> nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    FLinearClampSampler := FDevice.CreateSampler(SamplerDesc);
  end;
end;

destructor TCastleVulkanSSR.Destroy;
begin
  FSSRPipeline := nil;
  FreeAndNil(FSSRShader);
  FreeAndNil(FSSRDescriptorSet);
  FreeAndNil(FSSRDescriptorLayout);
  FreeAndNil(FSSRReflectionTexture);
  FreeAndNil(FLinearClampSampler);
  inherited;
end;

procedure TCastleVulkanSSR.EnsurePipelineCreated;
var
  Gen: TCastleShaderGeneratorRHI;
  Bindings: array[0..2] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FSSRPipeline <> nil) then
    Exit;

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FSSRShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateHiZSSRComputeShader(8, 8), 'HiZSSR_CS');

    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtCombinedImageSampler;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssCompute];

    Bindings[1].Binding := 1;
    Bindings[1].DescriptorType := dtCombinedImageSampler;
    Bindings[1].Count := 1;
    Bindings[1].StageFlags := [ssCompute];

    Bindings[2].Binding := 2;
    Bindings[2].DescriptorType := dtStorageImage;
    Bindings[2].Count := 1;
    Bindings[2].StageFlags := [ssCompute];

    FSSRDescriptorLayout := FDevice.CreateDescriptorSetLayout(Bindings);
    FSSRDescriptorSet := FDevice.CreateDescriptorSet(FSSRDescriptorLayout);

    FillChar(CompDesc, SizeOf(CompDesc), 0);
    CompDesc.ComputeShader := FSSRShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FSSRDescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleSSRPushConstants);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'HiZSSRComputePSO';
    FSSRPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TCastleVulkanSSR.EnsureSSRTarget(const AWidth, AHeight: Cardinal);
var
  TargetW, TargetH: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  TargetW := Max(Cardinal(1), AWidth);
  TargetH := Max(Cardinal(1), AHeight);
  if (FSSRReflectionTexture <> nil) and (FWidth = TargetW) and (FHeight = TargetH) then
    Exit;

  FWidth := TargetW;
  FHeight := TargetH;
  FreeAndNil(FSSRReflectionTexture);

  if FDevice = nil then
    Exit;

  TexDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRGBA16_Float,
    [tuSampled, tuStorage, tuColorAttachment], 1, 1);
  TexDesc.DebugName := 'HiZSSRReflectionTexture';
  FSSRReflectionTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanSSR.DispatchSSR(const ACmd: TRHICommandList;
  const AHDRSceneColor, AHiZPyramid: TRHITexture): Cardinal;
var
  PC: TCastleSSRPushConstants;
  GroupsX, GroupsY: Cardinal;
begin
  Result := 0;
  if (ACmd = nil) or (FDevice = nil) then
    Exit;

  if FSSRReflectionTexture = nil then
  begin
    if AHDRSceneColor <> nil then
      EnsureSSRTarget(AHDRSceneColor.Desc.Width, AHDRSceneColor.Desc.Height)
    else
      EnsureSSRTarget(1280, 720);
  end;

  EnsurePipelineCreated;

  FillChar(PC, SizeOf(PC), 0);
  PC.InvResolution := Vector2(1.0 / Max(Cardinal(1), FWidth), 1.0 / Max(Cardinal(1), FHeight));
  PC.ZNear := FZNear;
  PC.ZFar := FZFar;
  PC.MaxDistance := FMaxDistance;
  PC.Thickness := FThickness;
  PC.MaxRoughness := FMaxRoughness;
  PC.EdgeFadeWidth := FEdgeFadeWidth;
  PC.MaxSteps := Max(Cardinal(1), FMaxSteps);
  PC.HiZMipCount := Max(Cardinal(1), FHiZMipCount);
  PC.Intensity := FIntensity;

  ACmd.TransitionTexture(FSSRReflectionTexture, rsTransferDst);
  if AHDRSceneColor <> nil then
    FSSRDescriptorSet.BindTexture(0, AHDRSceneColor, FLinearClampSampler);
  if AHiZPyramid <> nil then
    FSSRDescriptorSet.BindTexture(1, AHiZPyramid, FLinearClampSampler);
  FSSRDescriptorSet.BindTexture(2, FSSRReflectionTexture, FLinearClampSampler);
  FSSRDescriptorSet.Update;

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;

  ACmd.BindComputePipeline(FSSRPipeline);
  ACmd.BindComputeDescriptorSet(0, FSSRDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch(GroupsX, GroupsY, 1);
  ACmd.TransitionTexture(FSSRReflectionTexture, rsShaderRead);

  Inc(FTotalSSRDispatches);
  Result := 1;
end;

class function TCastleVulkanSSR.EvaluateScreenEdgeFade(
  const AHitUV: TVector2; const AFadeWidth: Single): Single;
  function SmoothStep01(const Edge0, Edge1, X: Single): Single;
  var
    T: Single;
  begin
    T := EnsureRange((X - Edge0) / Max(1e-5, Edge1 - Edge0), 0.0, 1.0);
    Result := T * T * (3.0 - 2.0 * T);
  end;
var
  FW, BX, BY: Single;
begin
  FW := Max(1e-4, AFadeWidth);
  BX := SmoothStep01(0.0, FW, AHitUV.X) * SmoothStep01(0.0, FW, 1.0 - AHitUV.X);
  BY := SmoothStep01(0.0, FW, AHitUV.Y) * SmoothStep01(0.0, FW, 1.0 - AHitUV.Y);
  Result := EnsureRange(BX * BY, 0.0, 1.0);
end;

class function TCastleVulkanSSR.EvaluateSSRReflectionWeight(
  const ARoughness, AMaxRoughness, ACosTheta: Single): Single;
var
  T, RoughWeight, Fresnel: Single;
begin
  if ARoughness >= AMaxRoughness then
    Exit(0.0);
  T := EnsureRange(ARoughness / Max(1e-4, AMaxRoughness), 0.0, 1.0);
  RoughWeight := 1.0 - (T * T * (3.0 - 2.0 * T));
  Fresnel := 0.04 + (Max(0.04, 1.0 - ARoughness) - 0.04) *
    Math.Power(EnsureRange(1.0 - ACosTheta, 0.0, 1.0), 5.0);
  Result := EnsureRange(RoughWeight * Fresnel, 0.0, 1.0);
end;

function TCastleVulkanSSR.RaymarchHiZ1D(
  const AHiZMip0Depths: array of Single;
  const AStartCell: Integer; const AStartDepth, ARayStepZ: Single;
  out AHitCell: Integer; out AHitSteps: Cardinal): Boolean;
  function SampleHiZMin(const CellIdx, MipLevel: Integer): Single;
  var
    Span, BaseIdx, I, EndIdx: Integer;
  begin
    Span := 1 shl MipLevel;
    BaseIdx := (CellIdx div Span) * Span;
    EndIdx := Min(High(AHiZMip0Depths), BaseIdx + Span - 1);
    Result := AHiZMip0Depths[EnsureRange(BaseIdx, 0, High(AHiZMip0Depths))];
    for I := BaseIdx + 1 to EndIdx do
      if AHiZMip0Depths[I] < Result then
        Result := AHiZMip0Depths[I];
  end;
var
  CurCell, NextCell, CellEnd, MipLevel, MaxMip, StepScale: Integer;
  CurZ, CellMaxRayZ, MinDepth: Single;
begin
  Result := False;
  AHitCell := -1;
  AHitSteps := 0;
  if Length(AHiZMip0Depths) = 0 then
    Exit;

  CurCell := AStartCell;
  CurZ := AStartDepth;
  MipLevel := 0;
  MaxMip := Min(Integer(FHiZMipCount) - 1, 4);

  while (AHitSteps < FMaxSteps) and (CurCell <= High(AHiZMip0Depths)) do
  begin
    Inc(AHitSteps);
    StepScale := 1 shl MipLevel;
    NextCell := ((CurCell div StepScale) + 1) * StepScale;
    CellEnd := Min(High(AHiZMip0Depths), NextCell - 1);
    CurZ := AStartDepth + Single(CurCell - AStartCell) * ARayStepZ;
    CellMaxRayZ := Max(CurZ, AStartDepth + Single(CellEnd - AStartCell) * ARayStepZ);
    MinDepth := SampleHiZMin(CurCell, MipLevel);
    if CellMaxRayZ >= MinDepth then
    begin
      if MipLevel = 0 then
      begin
        if (CurZ - MinDepth) <= FThickness then
        begin
          AHitCell := CurCell;
          Exit(True);
        end;
        Inc(CurCell);
      end else
        Dec(MipLevel);
    end else
    begin
      CurCell := NextCell;
      MipLevel := Min(MaxMip, MipLevel + 1);
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanVolumetricFog                                                   }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanVolumetricFog.Create(const ADevice: TVulkanRHIDevice);
var
  SamplerDesc: TRHISamplerDesc;
begin
  inherited Create;
  FDevice := ADevice;
  FFogAlbedo := Vector3(0.9, 0.92, 0.95);
  FBaseDensity := 0.025;
  FSunDirection := Vector3(-0.4, -0.8, -0.44).Normalize;
  FAnisotropyG := 0.65;
  FSunColor := Vector3(1.0, 0.95, 0.85);
  FSunIntensity := 4.0;
  FHeightFalloff := 0.08;
  FBaseHeight := 0.0;
  FZNear := 0.5;
  FZFar := 200.0;

  if FDevice <> nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    FLinearClampSampler := FDevice.CreateSampler(SamplerDesc);
  end;
end;

destructor TCastleVulkanVolumetricFog.Destroy;
begin
  FInjectPipeline := nil;
  FRaymarchPipeline := nil;
  FreeAndNil(FRaymarchShader);
  FreeAndNil(FInjectShader);
  FreeAndNil(FRaymarchDescriptorSet);
  FreeAndNil(FRaymarchDescriptorLayout);
  FreeAndNil(FInjectDescriptorSet);
  FreeAndNil(FInjectDescriptorLayout);
  FreeAndNil(FIntegratedFroxelLUT);
  FreeAndNil(FFroxelScatteringVolume);
  FreeAndNil(FLinearClampSampler);
  inherited;
end;

procedure TCastleVulkanVolumetricFog.EnsurePipelinesCreated;
var
  Gen: TCastleShaderGeneratorRHI;
  InjectBindings: array[0..0] of TRHIDescriptorBindingDesc;
  RaymarchBindings: array[0..1] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FInjectPipeline <> nil) then
    Exit;

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FInjectShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateVolumetricFogInjectComputeShader(4, 4, 4), 'VolumetricFogInject_CS');
    FRaymarchShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateVolumetricFogRaymarchComputeShader(8, 8), 'VolumetricFogRaymarch_CS');

    FillChar(InjectBindings, SizeOf(InjectBindings), 0);
    InjectBindings[0].Binding := 0;
    InjectBindings[0].DescriptorType := dtStorageImage;
    InjectBindings[0].Count := 1;
    InjectBindings[0].StageFlags := [ssCompute];

    FInjectDescriptorLayout := FDevice.CreateDescriptorSetLayout(InjectBindings);
    FInjectDescriptorSet := FDevice.CreateDescriptorSet(FInjectDescriptorLayout);

    FillChar(RaymarchBindings, SizeOf(RaymarchBindings), 0);
    RaymarchBindings[0].Binding := 0;
    RaymarchBindings[0].DescriptorType := dtCombinedImageSampler;
    RaymarchBindings[0].Count := 1;
    RaymarchBindings[0].StageFlags := [ssCompute];

    RaymarchBindings[1].Binding := 1;
    RaymarchBindings[1].DescriptorType := dtStorageImage;
    RaymarchBindings[1].Count := 1;
    RaymarchBindings[1].StageFlags := [ssCompute];

    FRaymarchDescriptorLayout := FDevice.CreateDescriptorSetLayout(RaymarchBindings);
    FRaymarchDescriptorSet := FDevice.CreateDescriptorSet(FRaymarchDescriptorLayout);

    FillChar(CompDesc, SizeOf(CompDesc), 0);
    CompDesc.ComputeShader := FInjectShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FInjectDescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleVolumetricFogParams);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'VolumetricFogInjectComputePSO';
    FInjectPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);

    CompDesc.ComputeShader := FRaymarchShader;
    CompDesc.DescriptorSetLayouts[0] := FRaymarchDescriptorLayout;
    CompDesc.DebugName := 'VolumetricFogRaymarchComputePSO';
    FRaymarchPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TCastleVulkanVolumetricFog.EnsureFroxelVolumes(
  const AGridX, AGridY, AGridZ: Cardinal);
var
  GX, GY, GZ: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  GX := Max(Cardinal(1), AGridX);
  GY := Max(Cardinal(1), AGridY);
  GZ := Max(Cardinal(1), AGridZ);

  if (FFroxelScatteringVolume <> nil) and
     (FGridX = GX) and (FGridY = GY) and (FGridZ = GZ) then
    Exit;

  FGridX := GX;
  FGridY := GY;
  FGridZ := GZ;

  FreeAndNil(FFroxelScatteringVolume);
  FreeAndNil(FIntegratedFroxelLUT);

  if FDevice = nil then
    Exit;

  FillChar(TexDesc, SizeOf(TexDesc), 0);
  TexDesc.Dimension := td3D;
  TexDesc.Format := pfRGBA16_Float;
  TexDesc.Width := FGridX;
  TexDesc.Height := FGridY;
  TexDesc.DepthOrArrayLayers := FGridZ;
  TexDesc.MipLevels := 1;
  TexDesc.SampleCount := 1;
  TexDesc.Usage := [tuSampled, tuStorage];
  TexDesc.DebugName := 'FroxelScatteringVolume3D';
  FFroxelScatteringVolume := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc.DebugName := 'IntegratedFroxelLUT3D';
  FIntegratedFroxelLUT := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanVolumetricFog.DispatchVolumetricFog(
  const ACmd: TRHICommandList): Cardinal;
var
  Params: TCastleVolumetricFogParams;
begin
  Result := 0;
  if (ACmd = nil) or (FDevice = nil) then
    Exit;

  if FFroxelScatteringVolume = nil then
    EnsureFroxelVolumes;

  EnsurePipelinesCreated;

  FillChar(Params, SizeOf(Params), 0);
  Params.FogAlbedoAndBaseDensity := Vector4(FFogAlbedo.X, FFogAlbedo.Y, FFogAlbedo.Z, FBaseDensity);
  Params.SunDirectionAndAnisotropy := Vector4(FSunDirection.X, FSunDirection.Y, FSunDirection.Z,
    EnsureRange(FAnisotropyG, -0.99, 0.99));
  Params.SunColorAndIntensity := Vector4(FSunColor.X, FSunColor.Y, FSunColor.Z, FSunIntensity);
  Params.HeightFalloff := FHeightFalloff;
  Params.BaseHeight := FBaseHeight;
  Params.ZNear := FZNear;
  Params.ZFar := FZFar;

  { 1. 3D Froxel Density & Anisotropic Scattering Injection Pass }
  ACmd.TransitionTexture(FFroxelScatteringVolume, rsTransferDst);
  FInjectDescriptorSet.BindTexture(0, FFroxelScatteringVolume, FLinearClampSampler);
  FInjectDescriptorSet.Update;

  ACmd.BindComputePipeline(FInjectPipeline);
  ACmd.BindComputeDescriptorSet(0, FInjectDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Params), Params);
  ACmd.Dispatch((FGridX + 3) div 4, (FGridY + 3) div 4, (FGridZ + 3) div 4);
  Inc(FTotalInjectDispatches);
  Inc(Result);

  { 2. Front-to-Back Beer-Lambert Froxel Raymarching Integration Pass }
  ACmd.TransitionTexture(FFroxelScatteringVolume, rsShaderRead);
  ACmd.TransitionTexture(FIntegratedFroxelLUT, rsTransferDst);
  FRaymarchDescriptorSet.BindTexture(0, FFroxelScatteringVolume, FLinearClampSampler);
  FRaymarchDescriptorSet.BindTexture(1, FIntegratedFroxelLUT, FLinearClampSampler);
  FRaymarchDescriptorSet.Update;

  ACmd.BindComputePipeline(FRaymarchPipeline);
  ACmd.BindComputeDescriptorSet(0, FRaymarchDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Params), Params);
  ACmd.Dispatch((FGridX + 7) div 8, (FGridY + 7) div 8, 1);
  ACmd.TransitionTexture(FIntegratedFroxelLUT, rsShaderRead);
  Inc(FTotalRaymarchDispatches);
  Inc(Result);
end;

class function TCastleVulkanVolumetricFog.EvaluateHenyeyGreensteinPhase(
  const ACosTheta, AAnisotropyG: Single): Single;
const
  FOUR_PI = 12.56637061436;
var
  G, G2, Denom: Single;
begin
  G := EnsureRange(AAnisotropyG, -0.99, 0.99);
  G2 := G * G;
  Denom := Max(1e-4, 1.0 + G2 - 2.0 * G * EnsureRange(ACosTheta, -1.0, 1.0));
  Result := (1.0 - G2) / (FOUR_PI * Denom * Sqrt(Denom));
end;

class function TCastleVulkanVolumetricFog.EvaluateHeightFogDensity(
  const AWorldY, ABaseDensity, ABaseHeight, AHeightFalloff: Single): Single;
var
  DH: Single;
begin
  DH := Max(-50.0, AWorldY - ABaseHeight);
  Result := Max(0.0, ABaseDensity * Exp(-AHeightFalloff * DH));
end;

class procedure TCastleVulkanVolumetricFog.IntegrateFroxelSliceStep(
  const ASliceScattering: TVector3;
  const ASliceExtinction, AStepLength: Single;
  var AAccumLight: TVector3; var AAccumTransmittance: Single);
var
  StepTransmittance, InvExt: Single;
  SliceIntegral: TVector3;
begin
  StepTransmittance := Exp(-Max(0.0, ASliceExtinction) * Max(0.0, AStepLength));
  InvExt := (1.0 - StepTransmittance) / Max(1e-5, ASliceExtinction);
  SliceIntegral := ASliceScattering * InvExt;
  AAccumLight := AAccumLight + (SliceIntegral * AAccumTransmittance);
  AAccumTransmittance := AAccumTransmittance * StepTransmittance;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTAA                                                             }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTAA.Create(const ADevice: TVulkanRHIDevice);
var
  SamplerDesc: TRHISamplerDesc;
begin
  inherited Create;
  FDevice := ADevice;
  FSampleCount := 8;
  FBlendFactor := 0.08;
  FVarianceClipGamma := 1.25;
  FVelocityWeightScale := 40.0;
  FCurrentHistoryIndex := 0;

  if FDevice <> nil then
  begin
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfLinear;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    FLinearClampSampler := FDevice.CreateSampler(SamplerDesc);
  end;
end;

destructor TCastleVulkanTAA.Destroy;
begin
  FTAAPipeline := nil;
  FreeAndNil(FTAAShader);
  FreeAndNil(FTAADescriptorSet);
  FreeAndNil(FTAADescriptorLayout);
  FreeAndNil(FHistoryTextures[0]);
  FreeAndNil(FHistoryTextures[1]);
  FreeAndNil(FVelocityTexture);
  FreeAndNil(FLinearClampSampler);
  inherited;
end;

procedure TCastleVulkanTAA.EnsurePipelineCreated;
var
  Gen: TCastleShaderGeneratorRHI;
  Bindings: array[0..3] of TRHIDescriptorBindingDesc;
  CompDesc: TRHIComputePipelineDesc;
begin
  if (FDevice = nil) or (FTAAPipeline <> nil) then
    Exit;

  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    FTAAShader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute, Gen.GenerateTAAResolveComputeShader(8, 8), 'TAAResolve_CS');

    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtCombinedImageSampler;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssCompute];

    Bindings[1].Binding := 1;
    Bindings[1].DescriptorType := dtCombinedImageSampler;
    Bindings[1].Count := 1;
    Bindings[1].StageFlags := [ssCompute];

    Bindings[2].Binding := 2;
    Bindings[2].DescriptorType := dtCombinedImageSampler;
    Bindings[2].Count := 1;
    Bindings[2].StageFlags := [ssCompute];

    Bindings[3].Binding := 3;
    Bindings[3].DescriptorType := dtStorageImage;
    Bindings[3].Count := 1;
    Bindings[3].StageFlags := [ssCompute];

    FTAADescriptorLayout := FDevice.CreateDescriptorSetLayout(Bindings);
    FTAADescriptorSet := FDevice.CreateDescriptorSet(FTAADescriptorLayout);

    FillChar(CompDesc, SizeOf(CompDesc), 0);
    CompDesc.ComputeShader := FTAAShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FTAADescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleTAAPushConstants);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'TAAResolveComputePSO';
    FTAAPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  finally
    FreeAndNil(Gen);
  end;
end;

procedure TCastleVulkanTAA.EnsureTAATargets(const AWidth, AHeight: Cardinal);
var
  TargetW, TargetH: Cardinal;
  VelDesc, HistDesc: TRHITextureDesc;
begin
  TargetW := Max(Cardinal(1), AWidth);
  TargetH := Max(Cardinal(1), AHeight);

  if (FVelocityTexture <> nil) and (FWidth = TargetW) and (FHeight = TargetH) then
    Exit;

  FWidth := TargetW;
  FHeight := TargetH;

  FreeAndNil(FVelocityTexture);
  FreeAndNil(FHistoryTextures[0]);
  FreeAndNil(FHistoryTextures[1]);

  if FDevice = nil then
    Exit;

  VelDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRG16_Float,
    [tuSampled, tuStorage, tuColorAttachment], 1, 1);
  VelDesc.DebugName := 'TAAVelocityTexture';
  FVelocityTexture := FDevice.CreateTexture(VelDesc) as TVulkanRHITexture;

  HistDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRGBA16_Float,
    [tuSampled, tuStorage, tuColorAttachment], 1, 1);
  HistDesc.DebugName := 'TAAHistoryTexture0';
  FHistoryTextures[0] := FDevice.CreateTexture(HistDesc) as TVulkanRHITexture;

  HistDesc.DebugName := 'TAAHistoryTexture1';
  FHistoryTextures[1] := FDevice.CreateTexture(HistDesc) as TVulkanRHITexture;
end;

function TCastleVulkanTAA.GetResolvedHistoryTexture: TVulkanRHITexture;
begin
  Result := FHistoryTextures[FCurrentHistoryIndex and 1];
end;

function TCastleVulkanTAA.GetPreviousHistoryTexture: TVulkanRHITexture;
begin
  Result := FHistoryTextures[(FCurrentHistoryIndex xor 1) and 1];
end;

function TCastleVulkanTAA.DispatchTAAResolve(const ACmd: TRHICommandList;
  const ACurrentHDRTexture: TRHITexture;
  const AFrameIndex: Cardinal): Cardinal;
var
  PC: TCastleTAAPushConstants;
  PrevHist, ResolvedHist: TVulkanRHITexture;
  GroupsX, GroupsY: Cardinal;
begin
  Result := 0;
  if (ACmd = nil) or (FDevice = nil) then
    Exit;

  if FVelocityTexture = nil then
  begin
    if ACurrentHDRTexture <> nil then
      EnsureTAATargets(ACurrentHDRTexture.Desc.Width, ACurrentHDRTexture.Desc.Height)
    else
      EnsureTAATargets(1280, 720);
  end;

  EnsurePipelineCreated;

  FCurrentHistoryIndex := (FCurrentHistoryIndex xor 1) and 1;
  PrevHist := GetPreviousHistoryTexture;
  ResolvedHist := GetResolvedHistoryTexture;

  FillChar(PC, SizeOf(PC), 0);
  PC.InvResolution := Vector2(1.0 / Max(Cardinal(1), FWidth), 1.0 / Max(Cardinal(1), FHeight));
  PC.JitterOffset := ComputeHaltonJitterOffset(AFrameIndex, FSampleCount, FWidth, FHeight);
  PC.BlendFactor := FBlendFactor;
  PC.VarianceClipGamma := FVarianceClipGamma;
  PC.VelocityWeightScale := FVelocityWeightScale;
  PC.FrameIndex := AFrameIndex;

  ACmd.TransitionTexture(PrevHist, rsShaderRead);
  ACmd.TransitionTexture(FVelocityTexture, rsShaderRead);
  ACmd.TransitionTexture(ResolvedHist, rsTransferDst);

  if ACurrentHDRTexture <> nil then
    FTAADescriptorSet.BindTexture(0, ACurrentHDRTexture, FLinearClampSampler);
  FTAADescriptorSet.BindTexture(1, PrevHist, FLinearClampSampler);
  FTAADescriptorSet.BindTexture(2, FVelocityTexture, FLinearClampSampler);
  FTAADescriptorSet.BindTexture(3, ResolvedHist, FLinearClampSampler);
  FTAADescriptorSet.Update;

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;

  ACmd.BindComputePipeline(FTAAPipeline);
  ACmd.BindComputeDescriptorSet(0, FTAADescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch(GroupsX, GroupsY, 1);
  ACmd.TransitionTexture(ResolvedHist, rsShaderRead);

  Inc(FTotalTAADispatches);
  Result := 1;
end;

class function TCastleVulkanTAA.EvaluateHaltonSequence(
  const AIndex, ABase: Cardinal): Single;
var
  Idx, BaseVal: Cardinal;
  F, InvBase: Single;
begin
  Result := 0.0;
  BaseVal := Max(Cardinal(2), ABase);
  Idx := AIndex;
  InvBase := 1.0 / Single(BaseVal);
  F := InvBase;
  while Idx > 0 do
  begin
    Result := Result + Single(Idx mod BaseVal) * F;
    Idx := Idx div BaseVal;
    F := F * InvBase;
  end;
end;

class function TCastleVulkanTAA.ComputeHaltonJitterOffset(
  const AFrameIndex, ASampleCount, AWidth, AHeight: Cardinal): TVector2;
var
  CycleIndex: Cardinal;
  HX, HY: Single;
begin
  CycleIndex := (AFrameIndex mod Max(Cardinal(1), ASampleCount)) + 1;
  HX := EvaluateHaltonSequence(CycleIndex, 2) - 0.5;
  HY := EvaluateHaltonSequence(CycleIndex, 3) - 0.5;
  Result := Vector2(
    (2.0 * HX) / Single(Max(Cardinal(1), AWidth)),
    (2.0 * HY) / Single(Max(Cardinal(1), AHeight)));
end;

class function TCastleVulkanTAA.RGBToYCoCg(const ARGB: TVector3): TVector3;
begin
  Result.X := 0.25 * ARGB.X + 0.50 * ARGB.Y + 0.25 * ARGB.Z;
  Result.Y := 0.50 * ARGB.X - 0.50 * ARGB.Z;
  Result.Z := -0.25 * ARGB.X + 0.50 * ARGB.Y - 0.25 * ARGB.Z;
end;

class function TCastleVulkanTAA.YCoCgToRGB(const AYCoCg: TVector3): TVector3;
var
  Tmp: Single;
begin
  Tmp := AYCoCg.X - AYCoCg.Z;
  Result.X := Max(0.0, Tmp + AYCoCg.Y);
  Result.Y := Max(0.0, AYCoCg.X + AYCoCg.Z);
  Result.Z := Max(0.0, Tmp - AYCoCg.Y);
end;

class function TCastleVulkanTAA.ClipHistoryYCoCg(
  const AHistoryYCoCg, AMeanYCoCg, AStdDevYCoCg: TVector3;
  const AGamma: Single): TVector3;
var
  G: Single;
  BoxMin, BoxMax: TVector3;
begin
  G := Max(0.1, AGamma);
  BoxMin := AMeanYCoCg - (AStdDevYCoCg * G);
  BoxMax := AMeanYCoCg + (AStdDevYCoCg * G);
  Result.X := EnsureRange(AHistoryYCoCg.X, BoxMin.X, BoxMax.X);
  Result.Y := EnsureRange(AHistoryYCoCg.Y, BoxMin.Y, BoxMax.Y);
  Result.Z := EnsureRange(AHistoryYCoCg.Z, BoxMin.Z, BoxMax.Z);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanReflectionProbeManager                                          }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanReflectionProbeManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  ClearProbes;
end;

destructor TCastleVulkanReflectionProbeManager.Destroy;
begin
  FreeAndNil(FProbeBuffer);
  inherited;
end;

procedure TCastleVulkanReflectionProbeManager.ClearProbes;
begin
  FillChar(FProbes, SizeOf(FProbes), 0);
  FProbeCount := 0;
end;

function TCastleVulkanReflectionProbeManager.AddProbe(
  const AWorldPos, ABoxMin, ABoxMax: TVector3;
  const ARadius: Single; const AIntensity: Single;
  const ABlendDistance: Single; const ACubemapIndex: Cardinal;
  const ABoxProjection: Boolean): Integer;
begin
  if FProbeCount >= CASTLE_MAX_REFLECTION_PROBES then
    Exit(-1);
  Result := Integer(FProbeCount);
  FProbes[Result].PositionAndRadius := Vector4(AWorldPos.X, AWorldPos.Y, AWorldPos.Z, Max(0.01, ARadius));
  FProbes[Result].BoxMinAndIntensity := Vector4(ABoxMin.X, ABoxMin.Y, ABoxMin.Z, Max(0.0, AIntensity));
  FProbes[Result].BoxMaxAndCubemapIndex := Vector4(ABoxMax.X, ABoxMax.Y, ABoxMax.Z, Single(ACubemapIndex));
  if ABoxProjection then
    FProbes[Result].BlendDistanceAndFlags := Vector4(Max(0.001, ABlendDistance), 1.0, 6.0, 0.0)
  else
    FProbes[Result].BlendDistanceAndFlags := Vector4(Max(0.001, ABlendDistance), 0.0, 6.0, 0.0);
  Inc(FProbeCount);
end;

function TCastleVulkanReflectionProbeManager.GetProbe(
  const AIndex: Integer): TCastleReflectionProbeEntry;
begin
  if (AIndex >= 0) and (AIndex < Integer(FProbeCount)) then
    Result := FProbes[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleVulkanReflectionProbeManager.UploadProbes;
type
  TProbeUploadBlock = packed record
    Header: array[0..3] of Cardinal;
    Entries: array[0 .. CASTLE_MAX_REFLECTION_PROBES - 1] of TCastleReflectionProbeEntry;
  end;
var
  BufDesc: TRHIBufferDesc;
  UploadData: TProbeUploadBlock;
  MappedPtr: Pointer;
begin
  if FDevice = nil then
    Exit;

  if FProbeBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(TProbeUploadBlock),
      [buStorage, buUniform, buTransferDst],
      muCpuToGpu,
      'ReflectionProbesBuffer');
    FProbeBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  FillChar(UploadData, SizeOf(UploadData), 0);
  UploadData.Header[0] := FProbeCount;
  if FProbeCount > 0 then
    Move(FProbes[0], UploadData.Entries[0], FProbeCount * SizeOf(TCastleReflectionProbeEntry));

  MappedPtr := FProbeBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(UploadData, MappedPtr^, SizeOf(UploadData));
    FProbeBuffer.Unmap;
  end;
  Inc(FTotalUploads);
end;

class function TCastleVulkanReflectionProbeManager.EvaluateBoxProjectedDirection(
  const AWorldPos, AWorldReflectDir, AProbePos, ABoxMin, ABoxMax: TVector3): TVector3;
  function SafeComponent(const V: Single): Single;
  begin
    if Abs(V) < 1e-5 then
    begin
      if V < 0.0 then Result := -1e-5 else Result := 1e-5;
    end else
      Result := V;
  end;
var
  Dir, SafeDir, TMax, TMin, TLargest, HitPoint: TVector3;
  HitDist: Single;
begin
  Dir := AWorldReflectDir.Normalize;
  SafeDir := Vector3(SafeComponent(Dir.X), SafeComponent(Dir.Y), SafeComponent(Dir.Z));
  TMax := Vector3(
    (ABoxMax.X - AWorldPos.X) / SafeDir.X,
    (ABoxMax.Y - AWorldPos.Y) / SafeDir.Y,
    (ABoxMax.Z - AWorldPos.Z) / SafeDir.Z);
  TMin := Vector3(
    (ABoxMin.X - AWorldPos.X) / SafeDir.X,
    (ABoxMin.Y - AWorldPos.Y) / SafeDir.Y,
    (ABoxMin.Z - AWorldPos.Z) / SafeDir.Z);
  TLargest := Vector3(Max(TMax.X, TMin.X), Max(TMax.Y, TMin.Y), Max(TMax.Z, TMin.Z));
  HitDist := Min(Min(TLargest.X, TLargest.Y), TLargest.Z);
  if HitDist <= 0.0 then
    Exit(Dir);
  HitPoint := AWorldPos + (Dir * HitDist);
  Result := (HitPoint - AProbePos).Normalize;
end;

class function TCastleVulkanReflectionProbeManager.EvaluateProbeInfluenceWeight(
  const AWorldPos, ABoxMin, ABoxMax: TVector3;
  const ABlendDistance: Single): Single;
var
  DistMin, DistMax, EdgeDist: TVector3;
  ClosestWall: Single;
begin
  if (AWorldPos.X < ABoxMin.X) or (AWorldPos.Y < ABoxMin.Y) or (AWorldPos.Z < ABoxMin.Z) or
     (AWorldPos.X > ABoxMax.X) or (AWorldPos.Y > ABoxMax.Y) or (AWorldPos.Z > ABoxMax.Z) then
    Exit(0.0);

  DistMin := AWorldPos - ABoxMin;
  DistMax := ABoxMax - AWorldPos;
  EdgeDist := Vector3(Min(DistMin.X, DistMax.X), Min(DistMin.Y, DistMax.Y), Min(DistMin.Z, DistMax.Z));
  ClosestWall := Min(Min(EdgeDist.X, EdgeDist.Y), EdgeDist.Z);
  Result := EnsureRange(ClosestWall / Max(1e-4, ABlendDistance), 0.0, 1.0);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanDecalManager                                                    }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanDecalManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  ClearDecals;
end;

destructor TCastleVulkanDecalManager.Destroy;
begin
  FreeAndNil(FDecalBuffer);
  inherited;
end;

procedure TCastleVulkanDecalManager.ClearDecals;
begin
  FillChar(FDecals, SizeOf(FDecals), 0);
  FDecalCount := 0;
end;

function TCastleVulkanDecalManager.AddBoxDecal(
  const ACenter, AHalfExtents, AForwardNormal: TVector3;
  const AAlbedoTint: TVector3; const AOpacity: Single;
  const ARoughness: Single; const AUVScaleOffset: TVector4): Integer;
var
  InvSizeX, InvSizeY, InvSizeZ: Single;
  FwdNorm, UVSO: TVector4;
begin
  if FDecalCount >= CASTLE_MAX_PROJECTED_DECALS then
    Exit(-1);
  Result := Integer(FDecalCount);

  { Full box dimensions = 2 * HalfExtents, mapping [-HalfExtents..+HalfExtents] -> [-0.5..+0.5] }
  InvSizeX := 1.0 / Max(1e-4, AHalfExtents.X * 2.0);
  InvSizeY := 1.0 / Max(1e-4, AHalfExtents.Y * 2.0);
  InvSizeZ := 1.0 / Max(1e-4, AHalfExtents.Z * 2.0);

  FDecals[Result].WorldToDecalRow0 := Vector4(InvSizeX, 0.0, 0.0, -ACenter.X * InvSizeX);
  FDecals[Result].WorldToDecalRow1 := Vector4(0.0, InvSizeY, 0.0, -ACenter.Y * InvSizeY);
  FDecals[Result].WorldToDecalRow2 := Vector4(0.0, 0.0, InvSizeZ, -ACenter.Z * InvSizeZ);
  FDecals[Result].AlbedoTintAndOpacity := Vector4(
    AAlbedoTint.X, AAlbedoTint.Y, AAlbedoTint.Z, EnsureRange(AOpacity, 0.0, 1.0));

  if AForwardNormal.LengthSqr > 1e-6 then
  begin
    FwdNorm := Vector4(AForwardNormal.Normalize, EnsureRange(ARoughness, 0.0, 1.0));
  end else
    FwdNorm := Vector4(0.0, 0.0, 1.0, EnsureRange(ARoughness, 0.0, 1.0));
  FDecals[Result].DecalNormalAndRoughness := FwdNorm;

  if (AUVScaleOffset.X = 0.0) and (AUVScaleOffset.Y = 0.0) then
    UVSO := Vector4(1.0, 1.0, 0.0, 0.0)
  else
    UVSO := AUVScaleOffset;
  FDecals[Result].UVScaleOffset := UVSO;

  Inc(FDecalCount);
end;

function TCastleVulkanDecalManager.GetDecal(
  const AIndex: Integer): TCastleProjectedDecalEntry;
begin
  if (AIndex >= 0) and (AIndex < Integer(FDecalCount)) then
    Result := FDecals[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleVulkanDecalManager.UploadDecals;
type
  TDecalUploadBlock = packed record
    Header: array[0..3] of Cardinal;
    Entries: array[0 .. CASTLE_MAX_PROJECTED_DECALS - 1] of TCastleProjectedDecalEntry;
  end;
var
  BufDesc: TRHIBufferDesc;
  UploadData: TDecalUploadBlock;
  MappedPtr: Pointer;
begin
  if FDevice = nil then
    Exit;

  if FDecalBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(TDecalUploadBlock),
      [buStorage, buUniform, buTransferDst],
      muCpuToGpu,
      'ProjectedDecalsBuffer');
    FDecalBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  FillChar(UploadData, SizeOf(UploadData), 0);
  UploadData.Header[0] := FDecalCount;
  if FDecalCount > 0 then
    Move(FDecals[0], UploadData.Entries[0], FDecalCount * SizeOf(TCastleProjectedDecalEntry));

  MappedPtr := FDecalBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(UploadData, MappedPtr^, SizeOf(UploadData));
    FDecalBuffer.Unmap;
  end;
  Inc(FTotalUploads);
end;

class function TCastleVulkanDecalManager.ProjectWorldPointToDecalUV(
  const AWorldPos: TVector3; const ADecal: TCastleProjectedDecalEntry;
  out ADecalUV: TVector2; out ALocalPos: TVector3): Boolean;
begin
  ALocalPos.X :=
    ADecal.WorldToDecalRow0.X * AWorldPos.X +
    ADecal.WorldToDecalRow0.Y * AWorldPos.Y +
    ADecal.WorldToDecalRow0.Z * AWorldPos.Z +
    ADecal.WorldToDecalRow0.W;
  ALocalPos.Y :=
    ADecal.WorldToDecalRow1.X * AWorldPos.X +
    ADecal.WorldToDecalRow1.Y * AWorldPos.Y +
    ADecal.WorldToDecalRow1.Z * AWorldPos.Z +
    ADecal.WorldToDecalRow1.W;
  ALocalPos.Z :=
    ADecal.WorldToDecalRow2.X * AWorldPos.X +
    ADecal.WorldToDecalRow2.Y * AWorldPos.Y +
    ADecal.WorldToDecalRow2.Z * AWorldPos.Z +
    ADecal.WorldToDecalRow2.W;

  if (Abs(ALocalPos.X) > 0.5) or (Abs(ALocalPos.Y) > 0.5) or (Abs(ALocalPos.Z) > 0.5) then
  begin
    ADecalUV := Vector2(0.0, 0.0);
    Exit(False);
  end;

  ADecalUV.X := (ALocalPos.X + 0.5) * ADecal.UVScaleOffset.X + ADecal.UVScaleOffset.Z;
  ADecalUV.Y := (ALocalPos.Y + 0.5) * ADecal.UVScaleOffset.Y + ADecal.UVScaleOffset.W;
  Result := True;
end;

class function TCastleVulkanDecalManager.EvaluateDecalAngleAndBoxFade(
  const ALocalPos, ASurfaceNormal, ADecalForward: TVector3;
  const AAngleFadeCos: Single): Single;
  function SmoothStep01(const Edge0, Edge1, X: Single): Single;
  var
    T: Single;
  begin
    T := EnsureRange((X - Edge0) / Max(1e-5, Edge1 - Edge0), 0.0, 1.0);
    Result := T * T * (3.0 - 2.0 * T);
  end;
var
  CosAngle, NormalWeight, ZFade: Single;
begin
  CosAngle := TVector3.DotProduct(ASurfaceNormal.Normalize, ADecalForward.Normalize);
  NormalWeight := SmoothStep01(AAngleFadeCos, Min(AAngleFadeCos + 0.25, 0.99), CosAngle);
  ZFade := 1.0 - SmoothStep01(0.35, 0.50, Abs(ALocalPos.Z));
  Result := EnsureRange(NormalWeight * ZFade, 0.0, 1.0);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanComputeParticles                                                }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanComputeParticles.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxParticles := 0;
  FGravity := Vector3(0.0, -9.81, 0.0);
  FDrag := 0.25;
  FGroundPlaneY := 0.0;
  FRestitution := 0.5;
  FTotalSimulationDispatches := 0;
end;

destructor TCastleVulkanComputeParticles.Destroy;
begin
  FreeAndNil(FParticleBuffer);
  FreeAndNil(FAliveIndexBuffer);
  FreeAndNil(FIndirectDrawBuffer);
  inherited;
end;

procedure TCastleVulkanComputeParticles.EnsureParticleBuffers(const AMaxParticles: Cardinal);
var
  EffectiveMax: Cardinal;
  BufDesc: TRHIBufferDesc;
  IndirectCmd: TRHIDrawIndirectCommand;
  MappedPtr: Pointer;
begin
  EffectiveMax := Max(Cardinal(64), AMaxParticles);
  if (FMaxParticles = EffectiveMax) and (FParticleBuffer <> nil) and
     (FAliveIndexBuffer <> nil) and (FIndirectDrawBuffer <> nil) then
    Exit;

  FreeAndNil(FParticleBuffer);
  FreeAndNil(FAliveIndexBuffer);
  FreeAndNil(FIndirectDrawBuffer);
  FMaxParticles := EffectiveMax;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxParticles) * SizeOf(TCastleGPUParticle),
    [buStorage, buTransferDst, buTransferSrc],
    muCpuToGpu,
    'ComputeParticlesPoolBuffer');
  FParticleBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxParticles) * SizeOf(Cardinal),
    [buStorage, buVertex, buTransferDst],
    muGpuOnly,
    'ComputeParticlesAliveIndicesBuffer');
  FAliveIndexBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    SizeOf(TRHIDrawIndirectCommand),
    [buStorage, buIndirect, buTransferDst],
    muCpuToGpu,
    'ComputeParticlesIndirectDrawBuffer');
  FIndirectDrawBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  IndirectCmd.VertexCount := 6;
  IndirectCmd.InstanceCount := 0;
  IndirectCmd.FirstVertex := 0;
  IndirectCmd.FirstInstance := 0;
  MappedPtr := FIndirectDrawBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(IndirectCmd, MappedPtr^, SizeOf(IndirectCmd));
    FIndirectDrawBuffer.Unmap;
  end;
end;

procedure TCastleVulkanComputeParticles.EnsureSimulationPipeline;
var
  Gen: TCastleShaderGeneratorRHI;
  Shader: TRHIShaderModule;
  PipeDesc: TRHIComputePipelineDesc;
begin
  if FSimulationPipeline <> nil then
    Exit;
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Shader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute,
      Gen.GenerateParticleSimulationComputeShader(64),
      'ParticleSimulationCS');
    try
      FillChar(PipeDesc, SizeOf(PipeDesc), 0);
      PipeDesc.ComputeShader := Shader;
      PipeDesc.PushConstantSize := SizeOf(TCastleParticleSimPushConstants);
      PipeDesc.PushConstantStages := [ssCompute];
      PipeDesc.DebugName := 'ParticleSimulationPipeline';
      FSimulationPipeline := FDevice.GetOrCreateComputePipeline(PipeDesc);
    finally
      FreeAndNil(Shader);
    end;
  finally
    FreeAndNil(Gen);
  end;
end;

function TCastleVulkanComputeParticles.DispatchParticleSimulation(
  const ACmd: TRHICommandList; const ADeltaTime: Single): Cardinal;
var
  Push: TCastleParticleSimPushConstants;
  GroupsX: Cardinal;
begin
  if FMaxParticles = 0 then
    EnsureParticleBuffers(CASTLE_DEFAULT_MAX_PARTICLES);
  if (ACmd = nil) or (FParticleBuffer = nil) then
    Exit(0);

  EnsureSimulationPipeline;
  FillChar(Push, SizeOf(Push), 0);
  Push.GravityAndDeltaTime := Vector4(FGravity.X, FGravity.Y, FGravity.Z, Max(0.0, ADeltaTime));
  Push.EmitterOriginAndDrag := Vector4(0.0, 0.0, 0.0, Max(0.0, FDrag));
  Push.GroundPlaneY := FGroundPlaneY;
  Push.Restitution := EnsureRange(FRestitution, 0.0, 1.0);
  Push.MaxParticles := FMaxParticles;
  Push.SpawnSeed := 0;

  GroupsX := (FMaxParticles + 63) div 64;
  ACmd.BindComputePipeline(FSimulationPipeline);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Push), Push);
  ACmd.Dispatch(GroupsX, 1, 1);
  Inc(FTotalSimulationDispatches);
  Result := GroupsX;
end;

class function TCastleVulkanComputeParticles.SimulateParticleStep(
  var AParticle: TCastleGPUParticle;
  const AGravity: TVector3; const ADrag, AGroundY, ARestitution, ADeltaTime: Single): Boolean;
var
  Pos, Vel: TVector3;
  Age, MaxLife, Damp: Single;
begin
  Pos := Vector3(AParticle.PositionAndAge.X, AParticle.PositionAndAge.Y, AParticle.PositionAndAge.Z);
  Age := AParticle.PositionAndAge.W + Max(0.0, ADeltaTime);
  Vel := Vector3(AParticle.VelocityAndMaxLife.X, AParticle.VelocityAndMaxLife.Y, AParticle.VelocityAndMaxLife.Z);
  MaxLife := AParticle.VelocityAndMaxLife.W;

  if (MaxLife <= 0.0) or (Age >= MaxLife) then
  begin
    AParticle.PositionAndAge.W := Age;
    Exit(False);
  end;

  Vel := Vel + AGravity * ADeltaTime;
  Damp := Max(0.0, 1.0 - Max(0.0, ADrag) * ADeltaTime);
  Vel := Vel * Damp;
  Pos := Pos + Vel * ADeltaTime;

  if Pos.Y < AGroundY then
  begin
    Pos.Y := AGroundY;
    if Vel.Y < 0.0 then
      Vel.Y := -Vel.Y * EnsureRange(ARestitution, 0.0, 1.0);
  end;

  AParticle.PositionAndAge := Vector4(Pos.X, Pos.Y, Pos.Z, Age);
  AParticle.VelocityAndMaxLife := Vector4(Vel.X, Vel.Y, Vel.Z, MaxLife);
  Result := True;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanWeightedBlendedOIT                                              }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanWeightedBlendedOIT.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FWidth := 0;
  FHeight := 0;
  FWeightScale := 1.0;
end;

destructor TCastleVulkanWeightedBlendedOIT.Destroy;
begin
  FreeAndNil(FOITAccumTexture);
  FreeAndNil(FOITRevealageTexture);
  inherited;
end;

procedure TCastleVulkanWeightedBlendedOIT.EnsureOITTargets(const AWidth, AHeight: Cardinal);
var
  TexDesc: TRHITextureDesc;
begin
  if (AWidth = 0) or (AHeight = 0) then
    Exit;
  if (FWidth = AWidth) and (FHeight = AHeight) and
     (FOITAccumTexture <> nil) and (FOITRevealageTexture <> nil) then
    Exit;

  FreeAndNil(FOITAccumTexture);
  FreeAndNil(FOITRevealageTexture);
  FWidth := AWidth;
  FHeight := AHeight;

  TexDesc := TRHITextureDesc.Create2D(FWidth, FHeight, pfRGBA16_Float,
    [tuColorAttachment, tuSampled], 1);
  TexDesc.DebugName := 'OITAccumulationTarget';
  FOITAccumTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc := TRHITextureDesc.Create2D(FWidth, FHeight, pfR16_Float,
    [tuColorAttachment, tuSampled], 1);
  TexDesc.DebugName := 'OITRevealageTarget';
  FOITRevealageTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

class function TCastleVulkanWeightedBlendedOIT.EvaluateOITDepthWeight(
  const ALinearZ, AAlpha, AWeightScale: Single): Single;
var
  A, Z, ZTerm: Single;
begin
  A := EnsureRange(AAlpha, 0.0, 1.0);
  Z := Abs(ALinearZ);
  ZTerm := 1.0 / (1.0 + Sqr(Z * 0.1) + Power(Z * 0.01, 4.0));
  Result := EnsureRange(3000.0 * Max(1e-3, A * Sqrt(A)) * ZTerm * Max(0.01, AWeightScale), 1e-2, 3000.0);
end;

class procedure TCastleVulkanWeightedBlendedOIT.AccumulateOITSample(
  const APremulColorAndAlpha: TVector4; const ALinearZ, AWeightScale: Single;
  var AAccumRGBA: TVector4; var ARevealage: Single);
var
  Alpha, W: Single;
begin
  Alpha := EnsureRange(APremulColorAndAlpha.W, 0.0, 1.0);
  W := EvaluateOITDepthWeight(ALinearZ, Alpha, AWeightScale);
  AAccumRGBA.X := AAccumRGBA.X + APremulColorAndAlpha.X * W;
  AAccumRGBA.Y := AAccumRGBA.Y + APremulColorAndAlpha.Y * W;
  AAccumRGBA.Z := AAccumRGBA.Z + APremulColorAndAlpha.Z * W;
  AAccumRGBA.W := AAccumRGBA.W + Alpha * W;
  ARevealage := ARevealage * (1.0 - Alpha);
end;

class function TCastleVulkanWeightedBlendedOIT.EvaluateOITComposite(
  const AAccumRGBA: TVector4; const ARevealage: Single;
  const AOpaqueRGB: TVector3): TVector3;
var
  Rev, Denom: Single;
  AvgTransparent: TVector3;
begin
  Rev := EnsureRange(ARevealage, 0.0, 1.0);
  if Rev >= 0.9999 then
    Exit(AOpaqueRGB);
  Denom := Max(AAccumRGBA.W, 1e-5);
  AvgTransparent := Vector3(AAccumRGBA.X / Denom, AAccumRGBA.Y / Denom, AAccumRGBA.Z / Denom);
  Result := AvgTransparent * (1.0 - Rev) + AOpaqueRGB * Rev;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanContactShadows                                                  }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanContactShadows.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FWidth := 0;
  FHeight := 0;
  FLightDirView := Vector3(0.57735, 0.57735, -0.57735);
  FRayLength := 0.25;
  FThickness := 0.05;
  FStepCount := 16;
  FContrast := 1.0;
  FZNear := 0.1;
  FZFar := 500.0;
  FTotalContactShadowDispatches := 0;
end;

destructor TCastleVulkanContactShadows.Destroy;
begin
  FreeAndNil(FContactShadowTexture);
  inherited;
end;

procedure TCastleVulkanContactShadows.EnsureContactShadowTarget(const AWidth, AHeight: Cardinal);
var
  TexDesc: TRHITextureDesc;
begin
  if (AWidth = 0) or (AHeight = 0) then
    Exit;
  if (FWidth = AWidth) and (FHeight = AHeight) and (FContactShadowTexture <> nil) then
    Exit;

  FreeAndNil(FContactShadowTexture);
  FWidth := AWidth;
  FHeight := AHeight;

  TexDesc := TRHITextureDesc.Create2D(FWidth, FHeight, pfR16_Float,
    [tuStorage, tuSampled], 1);
  TexDesc.DebugName := 'ContactShadowMaskTarget';
  FContactShadowTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

procedure TCastleVulkanContactShadows.EnsureContactShadowPipeline;
var
  Gen: TCastleShaderGeneratorRHI;
  Shader: TRHIShaderModule;
  PipeDesc: TRHIComputePipelineDesc;
begin
  if FContactShadowPipeline <> nil then
    Exit;
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Shader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute,
      Gen.GenerateContactShadowsComputeShader(8, 8),
      'ContactShadowsCS');
    try
      FillChar(PipeDesc, SizeOf(PipeDesc), 0);
      PipeDesc.ComputeShader := Shader;
      PipeDesc.PushConstantSize := SizeOf(TCastleContactShadowsPushConstants);
      PipeDesc.PushConstantStages := [ssCompute];
      PipeDesc.DebugName := 'ContactShadowsPipeline';
      FContactShadowPipeline := FDevice.GetOrCreateComputePipeline(PipeDesc);
    finally
      FreeAndNil(Shader);
    end;
  finally
    FreeAndNil(Gen);
  end;
end;

function TCastleVulkanContactShadows.DispatchContactShadows(
  const ACmd: TRHICommandList; const ADepthTexture: TRHITexture): Cardinal;
var
  Push: TCastleContactShadowsPushConstants;
  GroupsX, GroupsY: Cardinal;
begin
  if (ACmd = nil) or (ADepthTexture = nil) then
    Exit(0);
  EnsureContactShadowTarget(ADepthTexture.Desc.Width, ADepthTexture.Desc.Height);
  if FContactShadowTexture = nil then
    Exit(0);

  EnsureContactShadowPipeline;
  FillChar(Push, SizeOf(Push), 0);
  Push.InvResolution := Vector2(1.0 / Max(Cardinal(1), FWidth), 1.0 / Max(Cardinal(1), FHeight));
  Push.LightDirView := FLightDirView;
  Push.RayLength := Max(0.001, FRayLength);
  Push.Thickness := Max(0.0005, FThickness);
  Push.ZNear := Max(1e-4, FZNear);
  Push.ZFar := Max(Push.ZNear + 1.0, FZFar);
  Push.StepCount := EnsureRange(FStepCount, 4, 64);
  Push.Contrast := EnsureRange(FContrast, 0.0, 4.0);
  Push.Reserved := 0;

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;
  ACmd.TransitionTexture(FContactShadowTexture, rsTransferDst);
  ACmd.BindComputePipeline(FContactShadowPipeline);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Push), Push);
  ACmd.Dispatch(GroupsX, GroupsY, 1);
  ACmd.TransitionTexture(FContactShadowTexture, rsShaderRead);
  Inc(FTotalContactShadowDispatches);
  Result := GroupsX * GroupsY;
end;

class function TCastleVulkanContactShadows.EvaluateContactShadowRay1D(
  const ASceneLinearDepths: array of Single;
  const AStartLinearZ, ARayStepZ, AThickness: Single;
  out AVisibility: Single): Boolean;
var
  I, N: Integer;
  RayZ, SceneZ, DepthDelta, T, EdgeFade, ShadowFactor: Single;
begin
  AVisibility := 1.0;
  Result := False;
  N := Length(ASceneLinearDepths);
  if (N <= 0) or (AThickness <= 0.0) then
    Exit;

  for I := 0 to N - 1 do
  begin
    T := Single(I + 1) / Single(N);
    RayZ := AStartLinearZ + ARayStepZ * Single(I + 1);
    SceneZ := ASceneLinearDepths[I];
    DepthDelta := RayZ - SceneZ;
    if (DepthDelta > 0.0005) and (DepthDelta < AThickness) then
    begin
      EdgeFade := 1.0 - EnsureRange((T - 0.75) / 0.25, 0.0, 1.0);
      ShadowFactor := EnsureRange(1.0 - (DepthDelta / AThickness) * 0.5, 0.0, 1.0) * EdgeFade;
      AVisibility := EnsureRange(1.0 - ShadowFactor, 0.0, 1.0);
      Exit(True);
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanComputeSkinner                                                  }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanComputeSkinner.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxVertices := 0;
  FMorphTargetCount := 0;
  FMorphWeights := Vector4(0.0, 0.0, 0.0, 0.0);
  FTotalSkinningDispatches := 0;
end;

destructor TCastleVulkanComputeSkinner.Destroy;
begin
  FreeAndNil(FSourceVertexBuffer);
  FreeAndNil(FMorphDeltaBuffer);
  FreeAndNil(FJointMatrixBuffer);
  FreeAndNil(FSkinnedVertexBuffer);
  FreeAndNil(FPreviousPositionBuffer);
  inherited;
end;

procedure TCastleVulkanComputeSkinner.EnsureSkinningBuffers(
  const AMaxVertices, AMorphTargetCount: Cardinal);
var
  EffectiveVerts, EffectiveMorphs: Cardinal;
  BufDesc: TRHIBufferDesc;
begin
  EffectiveVerts := Max(Cardinal(64), AMaxVertices);
  EffectiveMorphs := EnsureRange(AMorphTargetCount, 1, 4);
  if (FMaxVertices = EffectiveVerts) and (FMorphTargetCount = EffectiveMorphs) and
     (FSourceVertexBuffer <> nil) and (FMorphDeltaBuffer <> nil) and
     (FJointMatrixBuffer <> nil) and (FSkinnedVertexBuffer <> nil) and
     (FPreviousPositionBuffer <> nil) then
    Exit;

  FreeAndNil(FSourceVertexBuffer);
  FreeAndNil(FMorphDeltaBuffer);
  FreeAndNil(FJointMatrixBuffer);
  FreeAndNil(FSkinnedVertexBuffer);
  FreeAndNil(FPreviousPositionBuffer);
  FMaxVertices := EffectiveVerts;
  FMorphTargetCount := EffectiveMorphs;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxVertices) * SizeOf(TCastleSkinningVertex),
    [buStorage, buTransferDst],
    muCpuToGpu,
    'ComputeSkinnerSourceVertices');
  FSourceVertexBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxVertices) * PtrUInt(FMorphTargetCount) * SizeOf(TCastleMorphTargetDelta),
    [buStorage, buTransferDst],
    muCpuToGpu,
    'ComputeSkinnerMorphDeltas');
  FMorphDeltaBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    CASTLE_MAX_BONE_MATRICES * SizeOf(TMatrix4),
    [buStorage, buUniform, buTransferDst],
    muCpuToGpu,
    'ComputeSkinnerJointMatrices');
  FJointMatrixBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxVertices) * SizeOf(TCastleSkinningVertex),
    [buStorage, buVertex, buTransferSrc],
    muGpuOnly,
    'ComputeSkinnerSkinnedVertices');
  FSkinnedVertexBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(
    PtrUInt(FMaxVertices) * SizeOf(TVector4),
    [buStorage, buVertex],
    muGpuOnly,
    'ComputeSkinnerPreviousPositions');
  FPreviousPositionBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
end;

procedure TCastleVulkanComputeSkinner.EnsureSkinningPipeline;
var
  Gen: TCastleShaderGeneratorRHI;
  Shader: TRHIShaderModule;
  PipeDesc: TRHIComputePipelineDesc;
begin
  if FSkinningPipeline <> nil then
    Exit;
  Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
  try
    Shader := FDevice.CreateShaderModuleFromGLSL(
      ssCompute,
      Gen.GenerateComputeSkinningShader(64),
      'ComputeSkinningCS');
    try
      FillChar(PipeDesc, SizeOf(PipeDesc), 0);
      PipeDesc.ComputeShader := Shader;
      PipeDesc.PushConstantSize := SizeOf(TCastleComputeSkinningPushConstants);
      PipeDesc.PushConstantStages := [ssCompute];
      PipeDesc.DebugName := 'ComputeSkinningPipeline';
      FSkinningPipeline := FDevice.GetOrCreateComputePipeline(PipeDesc);
    finally
      FreeAndNil(Shader);
    end;
  finally
    FreeAndNil(Gen);
  end;
end;

function TCastleVulkanComputeSkinner.DispatchComputeSkinning(
  const ACmd: TRHICommandList; const AVertexCount, AJointCount: Cardinal;
  const AStorePreviousPos: Boolean): Cardinal;
var
  Push: TCastleComputeSkinningPushConstants;
  ActiveVerts, GroupsX: Cardinal;
begin
  if FMaxVertices = 0 then
    EnsureSkinningBuffers(Max(CASTLE_DEFAULT_MAX_SKINNED_VERTICES, AVertexCount), 4);
  if (ACmd = nil) or (AVertexCount = 0) then
    Exit(0);

  EnsureSkinningPipeline;
  ActiveVerts := Min(AVertexCount, FMaxVertices);
  FillChar(Push, SizeOf(Push), 0);
  Push.MorphWeights := FMorphWeights;
  Push.VertexCount := ActiveVerts;
  Push.MorphTargetCount := FMorphTargetCount;
  Push.JointCount := Min(AJointCount, Cardinal(CASTLE_MAX_BONE_MATRICES));
  if AStorePreviousPos then
    Push.StorePreviousPos := 1
  else
    Push.StorePreviousPos := 0;

  GroupsX := (ActiveVerts + 63) div 64;
  ACmd.BindComputePipeline(FSkinningPipeline);
  ACmd.PushConstants([ssCompute], 0, SizeOf(Push), Push);
  ACmd.Dispatch(GroupsX, 1, 1);
  Inc(FTotalSkinningDispatches);
  Result := GroupsX;
end;

class procedure TCastleVulkanComputeSkinner.EvaluateVertexSkinningAndMorph(
  const ASourceVertex: TCastleSkinningVertex;
  const AMorphDeltas: array of TCastleMorphTargetDelta;
  const AMorphWeights: TVector4;
  const AJointMatrices: array of TMatrix4;
  out ASkinnedPos, ASkinnedNormal: TVector3);
var
  MorphedPos, MorphedNorm, AccumPos, AccumNorm: TVector3;
  I, MorphCount, JointIdx, MaxJointIdx: Integer;
  W, WeightSum: Single;
  WeightsArr: array[0..3] of Single;
  JointMat: TMatrix4;
begin
  MorphedPos := Vector3(
    ASourceVertex.PositionAndUVX.X,
    ASourceVertex.PositionAndUVX.Y,
    ASourceVertex.PositionAndUVX.Z);
  MorphedNorm := Vector3(
    ASourceVertex.NormalAndUVY.X,
    ASourceVertex.NormalAndUVY.Y,
    ASourceVertex.NormalAndUVY.Z);

  WeightsArr[0] := AMorphWeights.X;
  WeightsArr[1] := AMorphWeights.Y;
  WeightsArr[2] := AMorphWeights.Z;
  WeightsArr[3] := AMorphWeights.W;
  MorphCount := Min(4, Length(AMorphDeltas));
  for I := 0 to MorphCount - 1 do
  begin
    W := WeightsArr[I];
    if Abs(W) > 1e-5 then
    begin
      MorphedPos := MorphedPos + Vector3(
        AMorphDeltas[I].DeltaPosition.X,
        AMorphDeltas[I].DeltaPosition.Y,
        AMorphDeltas[I].DeltaPosition.Z) * W;
      MorphedNorm := MorphedNorm + Vector3(
        AMorphDeltas[I].DeltaNormal.X,
        AMorphDeltas[I].DeltaNormal.Y,
        AMorphDeltas[I].DeltaNormal.Z) * W;
    end;
  end;

  WeightsArr[0] := ASourceVertex.JointWeights.X;
  WeightsArr[1] := ASourceVertex.JointWeights.Y;
  WeightsArr[2] := ASourceVertex.JointWeights.Z;
  WeightsArr[3] := ASourceVertex.JointWeights.W;
  WeightSum := WeightsArr[0] + WeightsArr[1] + WeightsArr[2] + WeightsArr[3];

  if (Length(AJointMatrices) > 0) and (WeightSum > 1e-5) then
  begin
    MaxJointIdx := High(AJointMatrices);
    AccumPos := TVector3.Zero;
    AccumNorm := TVector3.Zero;
    for I := 0 to 3 do
    begin
      W := WeightsArr[I];
      if W > 1e-6 then
      begin
        JointIdx := EnsureRange(Integer(ASourceVertex.JointIndices[I]), 0, MaxJointIdx);
        JointMat := AJointMatrices[JointIdx];
        AccumPos := AccumPos + JointMat.MultPoint(MorphedPos) * W;
        AccumNorm := AccumNorm + JointMat.MultDirection(MorphedNorm) * W;
      end;
    end;
    ASkinnedPos := AccumPos;
    if AccumNorm.LengthSqr > 1e-10 then
      ASkinnedNormal := AccumNorm.Normalize
    else
      ASkinnedNormal := Vector3(0.0, 1.0, 0.0);
  end else
  begin
    ASkinnedPos := MorphedPos;
    if MorphedNorm.LengthSqr > 1e-10 then
      ASkinnedNormal := MorphedNorm.Normalize
    else
      ASkinnedNormal := Vector3(0.0, 1.0, 0.0);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTerrainCDLOD                                                    }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTerrainCDLOD.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FNodeCount := 0;
  FBaseLODDistance := 64.0;
  FMorphStartRatio := 0.70;
  FTotalNodeUploads := 0;
  FillChar(FNodes, SizeOf(FNodes), 0);
end;

destructor TCastleVulkanTerrainCDLOD.Destroy;
begin
  FreeAndNil(FNodeBuffer);
  inherited;
end;

procedure TCastleVulkanTerrainCDLOD.ClearNodes;
begin
  FNodeCount := 0;
  FillChar(FNodes, SizeOf(FNodes), 0);
end;

function TCastleVulkanTerrainCDLOD.AddTerrainNode(
  const AWorldX, AWorldZ, APatchSize: Single;
  const ALODLevel: Cardinal; const AMinY, AMaxY: Single): Integer;
var
  Idx: Cardinal;
  ScaleFactor, NearDist, FarDist, MorphStart: Single;
begin
  if FNodeCount >= CASTLE_MAX_TERRAIN_CDLOD_NODES then
    Exit(-1);
  Idx := FNodeCount;
  Inc(FNodeCount);

  ScaleFactor := Power(2.0, Single(ALODLevel));
  if ALODLevel = 0 then
    NearDist := 0.0
  else
    NearDist := FBaseLODDistance * Power(2.0, Single(ALODLevel) - 1.0);
  FarDist := FBaseLODDistance * ScaleFactor;
  MorphStart := NearDist + (FarDist - NearDist) * EnsureRange(FMorphStartRatio, 0.1, 0.95);

  FNodes[Idx].NodeXZAndScale := Vector4(AWorldX, AWorldZ, Max(1.0, APatchSize), Single(ALODLevel));
  FNodes[Idx].MorphStartEndAndHeightRange := Vector4(MorphStart, FarDist, AMinY, AMaxY);
  Result := Integer(Idx);
end;

function TCastleVulkanTerrainCDLOD.GetTerrainNode(const AIndex: Integer): TCastleTerrainCDLODNode;
begin
  if (AIndex >= 0) and (Cardinal(AIndex) < FNodeCount) then
    Result := FNodes[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleVulkanTerrainCDLOD.UploadNodes;
var
  BufDesc: TRHIBufferDesc;
  MappedPtr: Pointer;
begin
  if FNodeBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(FNodes),
      [buStorage, buUniform, buTransferDst],
      muCpuToGpu,
      'TerrainCDLODNodesBuffer');
    FNodeBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  MappedPtr := FNodeBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(FNodes[0], MappedPtr^, SizeOf(FNodes));
    FNodeBuffer.Unmap;
  end;
  Inc(FTotalNodeUploads);
end;

class function TCastleVulkanTerrainCDLOD.EvaluateCDLODMorphFactor(
  const ACameraDistance, ALODNearDist, ALODFarDist, AMorphStartRatio: Single): Single;
var
  Ratio, MorphStart: Single;
begin
  Ratio := EnsureRange(AMorphStartRatio, 0.1, 0.95);
  MorphStart := ALODNearDist + (ALODFarDist - ALODNearDist) * Ratio;
  Result := EnsureRange((ACameraDistance - MorphStart) / Max(1e-4, ALODFarDist - MorphStart), 0.0, 1.0);
end;

class function TCastleVulkanTerrainCDLOD.MorphCDLODGridVertex(
  const AGridUV: TVector2; const APatchResolution, AMorphFactor: Single): TVector2;
var
  Res, K, FracX, FracY: Single;
begin
  Res := Max(1.0, APatchResolution);
  K := EnsureRange(AMorphFactor, 0.0, 1.0);
  FracX := Frac(AGridUV.X * Res * 0.5) * 2.0 / Res;
  FracY := Frac(AGridUV.Y * Res * 0.5) * 2.0 / Res;
  Result := Vector2(AGridUV.X - FracX * K, AGridUV.Y - FracY * K);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanAtmosphereRenderer (Phase 20.2)                                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanAtmosphereRenderer.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FSunDirection := Vector3(0.0, 0.70710678, 0.70710678);
  FSunIntensity := 20.0;
  { Earth sea-level Rayleigh scattering coefficients (m^-1) }
  FRayleighScattering := Vector3(5.802e-6, 13.558e-6, 33.100e-6);
  FRayleighScaleHeight := 8000.0;
  { Earth sea-level Mie aerosol scattering coefficients (m^-1) }
  FMieScattering := Vector3(3.996e-6, 3.996e-6, 3.996e-6);
  FMieScaleHeight := 1200.0;
  FPlanetRadius := 6360000.0;
  FAtmosphereRadius := 6420000.0;
  FMieAnisotropyG := 0.8;
  FRaymarchSteps := 16;
  FDispatchCount := 0;
end;

destructor TCastleVulkanAtmosphereRenderer.Destroy;
begin
  FreeAndNil(FSkyViewLUTTexture);
  inherited;
end;

procedure TCastleVulkanAtmosphereRenderer.EnsureSkyViewLUT(
  const AWidth, AHeight: Cardinal);
var
  TexDesc: TRHITextureDesc;
  W, H: Cardinal;
begin
  W := Max(Cardinal(1), AWidth);
  H := Max(Cardinal(1), AHeight);
  if (FSkyViewLUTTexture <> nil) and
     (FSkyViewLUTTexture.Desc.Width = W) and
     (FSkyViewLUTTexture.Desc.Height = H) then
    Exit;

  FreeAndNil(FSkyViewLUTTexture);
  TexDesc := TRHITextureDesc.Create2D(W, H, pfRGBA16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'SkyViewAtmosphereLUT';
  FSkyViewLUTTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanAtmosphereRenderer.EvaluateSkyRayRadiance(
  const AViewDir, ASunDir: TVector3): TVector3;
var
  VDir, SDir, OpticalDepthR, OpticalDepthM, Transmittance, InScattered: TVector3;
  CosTheta, PhaseR, PhaseM, AtmThickness, StepLen, H, DR, DM, PathStretch: Single;
  Steps, I: Cardinal;
begin
  VDir := AViewDir.Normalize;
  SDir := ASunDir.Normalize;
  CosTheta := TVector3.DotProduct(VDir, SDir);
  PhaseR := TCastleShaderGeneratorRHI.EvaluateRayleighPhase(CosTheta);
  PhaseM := TCastleShaderGeneratorRHI.EvaluateCornetteShanksMiePhase(CosTheta, FMieAnisotropyG);
  AtmThickness := Max(1000.0, FAtmosphereRadius - FPlanetRadius);
  Steps := Max(Cardinal(1), FRaymarchSteps);
  StepLen := AtmThickness / Single(Steps);
  { Horizon rays traverse a longer optical path than zenith rays }
  PathStretch := 1.0 / Max(0.15, Max(0.0, VDir.Y) + 0.15);

  OpticalDepthR := TVector3.Zero;
  OpticalDepthM := TVector3.Zero;
  InScattered := TVector3.Zero;
  for I := 0 to Steps - 1 do
  begin
    H := (Single(I) + 0.5) * StepLen;
    DR := Exp(-H / Max(1.0, FRayleighScaleHeight)) * StepLen * PathStretch;
    DM := Exp(-H / Max(1.0, FMieScaleHeight)) * StepLen * PathStretch;
    OpticalDepthR := OpticalDepthR + FRayleighScattering * DR;
    OpticalDepthM := OpticalDepthM + FMieScattering * DM;
    Transmittance := Vector3(
      Exp(-(OpticalDepthR.X + OpticalDepthM.X * 1.11)),
      Exp(-(OpticalDepthR.Y + OpticalDepthM.Y * 1.11)),
      Exp(-(OpticalDepthR.Z + OpticalDepthM.Z * 1.11)));
    InScattered := InScattered + Vector3(
      Transmittance.X * (FRayleighScattering.X * DR * PhaseR + FMieScattering.X * DM * PhaseM),
      Transmittance.Y * (FRayleighScattering.Y * DR * PhaseR + FMieScattering.Y * DM * PhaseM),
      Transmittance.Z * (FRayleighScattering.Z * DR * PhaseR + FMieScattering.Z * DM * PhaseM));
  end;
  Result := InScattered * FSunIntensity;
end;

procedure TCastleVulkanAtmosphereRenderer.DispatchAtmosphereSky(
  const ACommandList: TVulkanRHICommandList;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet;
  const AWidth, AHeight: Cardinal);
var
  PushConsts: TCastleAtmospherePushConstants;
  GroupsX, GroupsY: Cardinal;
begin
  EnsureSkyViewLUT(AWidth, AHeight);
  if ACommandList = nil then
    Exit;

  FillChar(PushConsts, SizeOf(PushConsts), 0);
  PushConsts.SunDirectionAndIntensity := Vector4(FSunDirection.Normalize, FSunIntensity);
  PushConsts.RayleighScatteringAndHeight := Vector4(FRayleighScattering, FRayleighScaleHeight);
  PushConsts.MieScatteringAndHeight := Vector4(FMieScattering, FMieScaleHeight);
  PushConsts.PlanetRadius := FPlanetRadius;
  PushConsts.AtmosphereRadius := FAtmosphereRadius;
  PushConsts.MieAnisotropyG := FMieAnisotropyG;
  PushConsts.RaymarchSteps := Max(Cardinal(1), FRaymarchSteps);

  ACommandList.TransitionTexture(FSkyViewLUTTexture, rsTransferDst);
  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PushConsts), PushConsts);

  GroupsX := (FSkyViewLUTTexture.Desc.Width + 7) div 8;
  GroupsY := (FSkyViewLUTTexture.Desc.Height + 7) div 8;
  ACommandList.Dispatch(Max(Cardinal(1), GroupsX), Max(Cardinal(1), GroupsY), 1);
  ACommandList.TransitionTexture(FSkyViewLUTTexture, rsShaderRead);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanOceanSimulator (Phase 21.2)                                     }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanOceanSimulator.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FWindDirection := Vector2(1.0, 0.0);
  FWindSpeed := 12.0;
  FSimulationTime := 0.0;
  FBaseAmplitude := 1.2;
  FBaseWavelength := 24.0;
  FChoppiness := 0.75;
  FPatchWorldSize := 128.0;
  FOctaveCount := 4;
  FFoamThreshold := 0.65;
  FGravity := 9.81;
  FDispatchCount := 0;
end;

destructor TCastleVulkanOceanSimulator.Destroy;
begin
  FreeAndNil(FNormalAndSlopeTexture);
  FreeAndNil(FDisplacementAndFoamTexture);
  inherited;
end;

procedure TCastleVulkanOceanSimulator.EnsureOceanTextures(const AGridSize: Cardinal);
var
  TexDesc: TRHITextureDesc;
  N: Cardinal;
begin
  N := Max(Cardinal(1), AGridSize);
  if (FDisplacementAndFoamTexture <> nil) and
     (FNormalAndSlopeTexture <> nil) and
     (FDisplacementAndFoamTexture.Desc.Width = N) and
     (FDisplacementAndFoamTexture.Desc.Height = N) then
    Exit;

  FreeAndNil(FNormalAndSlopeTexture);
  FreeAndNil(FDisplacementAndFoamTexture);

  TexDesc := TRHITextureDesc.Create2D(N, N, pfRGBA16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'OceanDisplacementAndFoam';
  FDisplacementAndFoamTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc := TRHITextureDesc.Create2D(N, N, pfRGBA16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'OceanNormalAndSlope';
  FNormalAndSlopeTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

procedure TCastleVulkanOceanSimulator.EvaluateGerstnerWavePoint(
  const AWorldXZ: TVector2; const ATimeSeconds: Single;
  out ADisplacement, ANormal: TVector3; out AFoamFactor: Single);
var
  BaseDir, Dir: TVector2;
  Amp, Wavelength, Chop, Angle, K, Omega, Phase, C, S, Q, Jacobian: Single;
  Octaves, I: Cardinal;
  Tangent, Bitangent: TVector3;
begin
  BaseDir := (FWindDirection + Vector2(1e-5, 0.0)).Normalize;
  Amp := FBaseAmplitude;
  Wavelength := Max(0.5, FBaseWavelength);
  Chop := EnsureRange(FChoppiness, 0.0, 1.0);
  Octaves := EnsureRange(FOctaveCount, 1, 8);

  ADisplacement := TVector3.Zero;
  Tangent := Vector3(1.0, 0.0, 0.0);
  Bitangent := Vector3(0.0, 0.0, 1.0);
  Jacobian := 1.0;

  for I := 0 to Octaves - 1 do
  begin
    Angle := Single(I) * 0.42;
    Dir := Vector2(
      BaseDir.X * Cos(Angle) - BaseDir.Y * Sin(Angle),
      BaseDir.X * Sin(Angle) + BaseDir.Y * Cos(Angle)).Normalize;
    K := (2.0 * Single(Pi)) / Wavelength;
    Omega := Sqrt(Max(0.1, FGravity) * K);
    Phase := K * (Dir.X * AWorldXZ.X + Dir.Y * AWorldXZ.Y) - Omega * ATimeSeconds;
    C := Cos(Phase);
    S := Sin(Phase);
    Q := Chop / Max(K * Amp * Single(Octaves), 1e-4);

    ADisplacement.X := ADisplacement.X + Q * Amp * Dir.X * C;
    ADisplacement.Y := ADisplacement.Y + Amp * S;
    ADisplacement.Z := ADisplacement.Z + Q * Amp * Dir.Y * C;

    Tangent.Y := Tangent.Y + K * Amp * Dir.X * C;
    Bitangent.Y := Bitangent.Y + K * Amp * Dir.Y * C;
    Jacobian := Jacobian - Q * K * Amp * S;

    Amp := Amp * 0.5;
    Wavelength := Wavelength * 0.5;
  end;

  ANormal := TVector3.CrossProduct(Bitangent, Tangent).Normalize;
  AFoamFactor := EnsureRange((FFoamThreshold - Jacobian) / Max(FFoamThreshold, 1e-4), 0.0, 1.0);
end;

procedure TCastleVulkanOceanSimulator.DispatchOceanSimulation(
  const ACommandList: TVulkanRHICommandList;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet;
  const AGridSize: Cardinal);
var
  PushConsts: TCastleOceanWavePushConstants;
  GroupsXY: Cardinal;
begin
  EnsureOceanTextures(AGridSize);
  if ACommandList = nil then
    Exit;

  FillChar(PushConsts, SizeOf(PushConsts), 0);
  PushConsts.WindDirectionAndSpeed := Vector4(
    FWindDirection.X, FWindDirection.Y, FWindSpeed, FSimulationTime);
  PushConsts.WaveParams := Vector4(
    FBaseAmplitude, FBaseWavelength, FChoppiness, FPatchWorldSize);
  PushConsts.GridSize := FDisplacementAndFoamTexture.Desc.Width;
  PushConsts.OctaveCount := EnsureRange(FOctaveCount, 1, 8);
  PushConsts.FoamThreshold := FFoamThreshold;
  PushConsts.Gravity := FGravity;

  ACommandList.TransitionTexture(FDisplacementAndFoamTexture, rsTransferDst);
  ACommandList.TransitionTexture(FNormalAndSlopeTexture, rsTransferDst);
  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PushConsts), PushConsts);

  GroupsXY := (FDisplacementAndFoamTexture.Desc.Width + 7) div 8;
  ACommandList.Dispatch(Max(Cardinal(1), GroupsXY), Max(Cardinal(1), GroupsXY), 1);
  ACommandList.TransitionTexture(FDisplacementAndFoamTexture, rsShaderRead);
  ACommandList.TransitionTexture(FNormalAndSlopeTexture, rsShaderRead);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanDDGIGrid (Phase 22.1)                                           }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanDDGIGrid.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FGridOrigin := Vector3(-16.0, 0.0, -16.0);
  FGridSpacing := Vector3(4.0, 4.0, 4.0);
  FGridCountX := CASTLE_DEFAULT_DDGI_GRID_X;
  FGridCountY := CASTLE_DEFAULT_DDGI_GRID_Y;
  FGridCountZ := CASTLE_DEFAULT_DDGI_GRID_Z;
  FNormalBias := 0.25;
  FViewBias := 0.15;
  FHysteresis := 0.97;
  FUpdateCount := 0;
end;

destructor TCastleVulkanDDGIGrid.Destroy;
begin
  FreeAndNil(FVisibilityAtlasTexture);
  FreeAndNil(FIrradianceAtlasTexture);
  inherited;
end;

procedure TCastleVulkanDDGIGrid.EnsureProbeAtlases;
var
  AtlasW, AtlasH: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  { Each probe occupies (CASTLE_DEFAULT_DDGI_OCT_TEXELS + 2)x(CASTLE_DEFAULT_DDGI_OCT_TEXELS + 2) texels with 1-texel gutter }
  AtlasW := Max(Cardinal(1), FGridCountX * FGridCountY) * (CASTLE_DEFAULT_DDGI_OCT_TEXELS + 2);
  AtlasH := Max(Cardinal(1), FGridCountZ) * (CASTLE_DEFAULT_DDGI_OCT_TEXELS + 2);
  if (FIrradianceAtlasTexture <> nil) and
     (FVisibilityAtlasTexture <> nil) and
     (FIrradianceAtlasTexture.Desc.Width = AtlasW) and
     (FIrradianceAtlasTexture.Desc.Height = AtlasH) then
    Exit;

  FreeAndNil(FVisibilityAtlasTexture);
  FreeAndNil(FIrradianceAtlasTexture);

  TexDesc := TRHITextureDesc.Create2D(AtlasW, AtlasH, pfRGBA16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'DDGIIrradianceOctahedralAtlas';
  FIrradianceAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc := TRHITextureDesc.Create2D(AtlasW, AtlasH, pfRG16_Float, [tuSampled, tuStorage], 1);
  TexDesc.DebugName := 'DDGIVisibilityOctahedralAtlas';
  FVisibilityAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanDDGIGrid.GetProbeWorldPosition(
  const AProbeX, AProbeY, AProbeZ: Cardinal): TVector3;
begin
  Result := Vector3(
    FGridOrigin.X + Single(AProbeX) * FGridSpacing.X,
    FGridOrigin.Y + Single(AProbeY) * FGridSpacing.Y,
    FGridOrigin.Z + Single(AProbeZ) * FGridSpacing.Z);
end;

procedure TCastleVulkanDDGIGrid.DispatchDDGIUpdate(
  const ACommandList: TVulkanRHICommandList;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  Params: TCastleDDGIGridParams;
  TotalProbes: Cardinal;
begin
  EnsureProbeAtlases;
  if ACommandList = nil then
    Exit;

  FillChar(Params, SizeOf(Params), 0);
  Params.GridOriginAndNormalBias := Vector4(FGridOrigin, FNormalBias);
  Params.GridSpacingAndViewBias := Vector4(FGridSpacing, FViewBias);
  Params.GridCountX := Max(Cardinal(1), FGridCountX);
  Params.GridCountY := Max(Cardinal(1), FGridCountY);
  Params.GridCountZ := Max(Cardinal(1), FGridCountZ);
  Params.Hysteresis := EnsureRange(FHysteresis, 0.0, 0.99);

  ACommandList.TransitionTexture(FIrradianceAtlasTexture, rsTransferDst);
  ACommandList.TransitionTexture(FVisibilityAtlasTexture, rsTransferDst);
  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(Params), Params);

  TotalProbes := Max(Cardinal(1), FGridCountX * FGridCountY * FGridCountZ);
  ACommandList.Dispatch(TotalProbes, 1, 1);
  ACommandList.TransitionTexture(FIrradianceAtlasTexture, rsShaderRead);
  ACommandList.TransitionTexture(FVisibilityAtlasTexture, rsShaderRead);
  Inc(FUpdateCount);
end;

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
{ TCastleVulkanVirtualShadowMap (Phase 23.2)                                   }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanVirtualShadowMap.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  ResetPageTable;
end;

destructor TCastleVulkanVirtualShadowMap.Destroy;
begin
  FreeAndNil(FPhysicalTilePoolTexture);
  FreeAndNil(FPageTableBuffer);
  inherited;
end;

procedure TCastleVulkanVirtualShadowMap.ResetPageTable;
begin
  FillChar(FPageTable[0], SizeOf(FPageTable), 0);
  FAllocatedTileCount := 0;
end;

procedure TCastleVulkanVirtualShadowMap.EnsureResources;
var
  BufDesc: TRHIBufferDesc;
  TexDesc: TRHITextureDesc;
  PoolDim: Cardinal;
begin
  if FPageTableBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(FPageTable),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'VSMPageTableBuffer');
    FPageTableBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if FPhysicalTilePoolTexture = nil then
  begin
    PoolDim := CASTLE_VSM_PHYSICAL_TILES_PER_ROW * CASTLE_VSM_PHYSICAL_TILE_SIZE;
    TexDesc := TRHITextureDesc.Create2D(
      PoolDim, PoolDim, pfR32_Float, [tuSampled, tuStorage, tuColorAttachment], 1);
    TexDesc.DebugName := 'VSMPhysicalTilePool';
    FPhysicalTilePoolTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

function TCastleVulkanVirtualShadowMap.RequestAndAllocateVirtualPage(
  const APageX, APageY: Cardinal;
  out APhysicalTileX, APhysicalTileY: Cardinal): Boolean;
var
  Idx, Entry, TileIdx: Cardinal;
begin
  APhysicalTileX := 0;
  APhysicalTileY := 0;
  if (APageX >= CASTLE_VSM_PAGE_TABLE_DIM) or (APageY >= CASTLE_VSM_PAGE_TABLE_DIM) then
    Exit(False);

  Idx := APageY * CASTLE_VSM_PAGE_TABLE_DIM + APageX;
  Entry := FPageTable[Idx];
  if (Entry and 1) <> 0 then
  begin
    APhysicalTileX := (Entry shr 8) and $FF;
    APhysicalTileY := (Entry shr 16) and $FF;
    FPageTable[Idx] := Entry or 2; { mark Requested }
    Exit(True);
  end;

  if FAllocatedTileCount >= CASTLE_VSM_MAX_PHYSICAL_TILES then
    Exit(False);

  TileIdx := FAllocatedTileCount;
  Inc(FAllocatedTileCount);
  APhysicalTileX := TileIdx mod CASTLE_VSM_PHYSICAL_TILES_PER_ROW;
  APhysicalTileY := TileIdx div CASTLE_VSM_PHYSICAL_TILES_PER_ROW;
  { Bit 0 = Resident, Bit 1 = Requested, Bits 8..15 = TileX, Bits 16..23 = TileY }
  FPageTable[Idx] := 1 or 2 or ((APhysicalTileX and $FF) shl 8) or ((APhysicalTileY and $FF) shl 16);
  Result := True;
end;

function TCastleVulkanVirtualShadowMap.GetPageEntry(const APageX, APageY: Cardinal): Cardinal;
begin
  if (APageX < CASTLE_VSM_PAGE_TABLE_DIM) and (APageY < CASTLE_VSM_PAGE_TABLE_DIM) then
    Result := FPageTable[APageY * CASTLE_VSM_PAGE_TABLE_DIM + APageX]
  else
    Result := 0;
end;

function TCastleVulkanVirtualShadowMap.ComputePhysicalAtlasUV(
  const AVirtualUV: TVector2;
  out APageX, APageY: Cardinal; out APhysicalUV: TVector2): Boolean;
var
  ClampedU, ClampedV, ScaledU, ScaledV, InPageU, InPageV: Single;
  Entry, TileX, TileY: Cardinal;
begin
  ClampedU := EnsureRange(AVirtualUV.X, 0.0, 0.999999);
  ClampedV := EnsureRange(AVirtualUV.Y, 0.0, 0.999999);
  ScaledU := ClampedU * Single(CASTLE_VSM_PAGE_TABLE_DIM);
  ScaledV := ClampedV * Single(CASTLE_VSM_PAGE_TABLE_DIM);
  APageX := Trunc(ScaledU);
  APageY := Trunc(ScaledV);
  InPageU := Frac(ScaledU);
  InPageV := Frac(ScaledV);

  Entry := GetPageEntry(APageX, APageY);
  if (Entry and 1) = 0 then
  begin
    APhysicalUV := TVector2.Zero;
    Exit(False);
  end;

  TileX := (Entry shr 8) and $FF;
  TileY := (Entry shr 16) and $FF;
  APhysicalUV := Vector2(
    (Single(TileX) + InPageU) / Single(CASTLE_VSM_PHYSICAL_TILES_PER_ROW),
    (Single(TileY) + InPageV) / Single(CASTLE_VSM_PHYSICAL_TILES_PER_ROW));
  Result := True;
end;

procedure TCastleVulkanVirtualShadowMap.UploadPageTable;
var
  MappedPtr: Pointer;
begin
  EnsureResources;
  MappedPtr := FPageTableBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(FPageTable[0], MappedPtr^, SizeOf(FPageTable));
    FPageTableBuffer.Unmap;
  end;
  Inc(FTotalPageUploads);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanLODSelector (Phase 24.1)                                        }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanLODSelector.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanLODSelector.Destroy;
begin
  FreeAndNil(FSelectedLODBuffer);
  FreeAndNil(FInstanceBuffer);
  inherited;
end;

procedure TCastleVulkanLODSelector.ClearInstances;
begin
  FInstanceCount := 0;
  SetLength(FInstances, 0);
end;

function TCastleVulkanLODSelector.AddInstance(
  const ASphereCenter: TVector3;
  const ARadius: Single;
  const AThresholds: TVector4;
  const AMeshID: Cardinal;
  const ATransitionBand: Single): Integer;
var
  Idx: Integer;
begin
  Idx := Integer(FInstanceCount);
  Inc(FInstanceCount);
  SetLength(FInstances, FInstanceCount);
  FillChar(FInstances[Idx], SizeOf(TCastleLODInstanceDescriptor), 0);
  FInstances[Idx].BoundingSphere := Vector4(ASphereCenter, Max(0.0, ARadius));
  FInstances[Idx].LODScreenThresholds := AThresholds;
  FInstances[Idx].MeshID := AMeshID;
  FInstances[Idx].InstanceID := Cardinal(Idx);
  FInstances[Idx].TransitionBand := Max(1e-4, ATransitionBand);
  Result := Idx;
end;

procedure TCastleVulkanLODSelector.UploadInstances;
var
  CountAlloc: Cardinal;
  BufDesc: TRHIBufferDesc;
  MappedPtr: Pointer;
begin
  CountAlloc := Max(Cardinal(1), FInstanceCount);
  if (FInstanceBuffer = nil) or
     (FInstanceBuffer.Desc.Size < CountAlloc * SizeOf(TCastleLODInstanceDescriptor)) then
  begin
    FreeAndNil(FInstanceBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(TCastleLODInstanceDescriptor),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'LODInstanceBuffer');
    FInstanceBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if FInstanceCount > 0 then
  begin
    MappedPtr := FInstanceBuffer.Map;
    if MappedPtr <> nil then
    begin
      Move(FInstances[0], MappedPtr^, FInstanceCount * SizeOf(TCastleLODInstanceDescriptor));
      FInstanceBuffer.Unmap;
    end;
  end;

  if (FSelectedLODBuffer = nil) or
     (FSelectedLODBuffer.Desc.Size < CountAlloc * 16) then
  begin
    FreeAndNil(FSelectedLODBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * 16,
      [buStorage, buTransferSrc],
      muGpuOnly,
      'SelectedLODBuffer');
    FSelectedLODBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

function TCastleVulkanLODSelector.EvaluateInstanceLODsCPU(
  const ACameraPosition: TVector3;
  const ACotHalfFovY: Single;
  out ALOD0Count, ALOD1Count, ALOD2Count, ALOD3Count, ACulledCount: Cardinal): Cardinal;
var
  I: Cardinal;
  Dist, Coverage, Crossfade: Single;
  LOD: Integer;
begin
  ALOD0Count := 0;
  ALOD1Count := 0;
  ALOD2Count := 0;
  ALOD3Count := 0;
  ACulledCount := 0;
  Result := 0;
  if FInstanceCount = 0 then
    Exit;

  for I := 0 to FInstanceCount - 1 do
  begin
    Dist := (FInstances[I].BoundingSphere.XYZ - ACameraPosition).Length;
    Coverage := TCastleShaderGeneratorRHI.EvaluateProjectedScreenCoverage(
      Dist, FInstances[I].BoundingSphere.W, ACotHalfFovY);
    LOD := TCastleShaderGeneratorRHI.SelectDiscreteLODLevel(
      Coverage, FInstances[I].LODScreenThresholds, Crossfade, FInstances[I].TransitionBand);
    case LOD of
      0: begin Inc(ALOD0Count); Inc(Result); end;
      1: begin Inc(ALOD1Count); Inc(Result); end;
      2: begin Inc(ALOD2Count); Inc(Result); end;
      3: begin Inc(ALOD3Count); Inc(Result); end;
    else
      Inc(ACulledCount);
    end;
  end;
end;

procedure TCastleVulkanLODSelector.DispatchLODSelection(
  const ACommandList: TVulkanRHICommandList;
  const ACameraPosition: TVector3;
  const ACotHalfFovY: Single;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
type
  TLODSelectionPC = packed record
    CameraPosAndCotHalfFovY: TVector4;
    InstanceCount: Cardinal;
    Pad0, Pad1, Pad2: Cardinal;
  end;
var
  PC: TLODSelectionPC;
  GroupsX: Cardinal;
begin
  UploadInstances;
  if ACommandList = nil then
    Exit;

  FillChar(PC, SizeOf(PC), 0);
  PC.CameraPosAndCotHalfFovY := Vector4(ACameraPosition, ACotHalfFovY);
  PC.InstanceCount := FInstanceCount;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PC), PC);

  GroupsX := (Max(Cardinal(1), FInstanceCount) + 63) div 64;
  ACommandList.Dispatch(GroupsX, 1, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTextureStreamer (Phase 25.2)                                    }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTextureStreamer.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  ClearTextures;
end;

destructor TCastleVulkanTextureStreamer.Destroy;
begin
  FreeAndNil(FFeedbackBuffer);
  inherited;
end;

procedure TCastleVulkanTextureStreamer.ClearTextures;
begin
  FillChar(FEntries[0], SizeOf(FEntries), 0);
  FTextureCount := 0;
end;

function TCastleVulkanTextureStreamer.RegisterStreamableTexture(
  const AWidth, AHeight, AMipLevels, AInitialResidentMip: Cardinal): Integer;
var
  Idx, MaxMip: Cardinal;
begin
  if FTextureCount >= CASTLE_MAX_STREAMED_TEXTURES then
    Exit(-1);
  Idx := FTextureCount;
  Inc(FTextureCount);
  MaxMip := Max(Cardinal(1), AMipLevels) - 1;
  FEntries[Idx].Width := Max(Cardinal(1), AWidth);
  FEntries[Idx].Height := Max(Cardinal(1), AHeight);
  FEntries[Idx].MipLevels := Max(Cardinal(1), AMipLevels);
  FEntries[Idx].ResidentMip := Min(AInitialResidentMip, MaxMip);
  FEntries[Idx].RequestedMip := $FF;
  Result := Integer(Idx);
end;

procedure TCastleVulkanTextureStreamer.ResetFrameFeedback;
var
  I: Cardinal;
begin
  if FTextureCount = 0 then
    Exit;
  for I := 0 to FTextureCount - 1 do
    FEntries[I].RequestedMip := $FF;
end;

procedure TCastleVulkanTextureStreamer.RecordMipFeedback(
  const ATextureIndex, ARequestedMip: Cardinal);
var
  ClampedMip: Cardinal;
begin
  if ATextureIndex >= FTextureCount then
    Exit;
  ClampedMip := Min(ARequestedMip, FEntries[ATextureIndex].MipLevels - 1);
  if ClampedMip < FEntries[ATextureIndex].RequestedMip then
    FEntries[ATextureIndex].RequestedMip := ClampedMip;
end;

function TCastleVulkanTextureStreamer.GetResidentMip(
  const ATextureIndex: Cardinal): Cardinal;
begin
  if ATextureIndex < FTextureCount then
    Result := FEntries[ATextureIndex].ResidentMip
  else
    Result := 0;
end;

function TCastleVulkanTextureStreamer.ResolveStreamingRequests(
  out APromotedCount, AEvictedCount: Cardinal): Cardinal;
var
  I, CoarsestMip: Cardinal;
begin
  APromotedCount := 0;
  AEvictedCount := 0;
  Result := 0;
  if FTextureCount = 0 then
    Exit;

  for I := 0 to FTextureCount - 1 do
  begin
    CoarsestMip := FEntries[I].MipLevels - 1;
    if FEntries[I].RequestedMip = $FF then
    begin
      { Texture was not sampled this frame: evict 1 mip level toward coarsest tail }
      if FEntries[I].ResidentMip < CoarsestMip then
      begin
        Inc(FEntries[I].ResidentMip);
        Inc(AEvictedCount);
        Inc(Result);
      end;
    end else
    if FEntries[I].RequestedMip < FEntries[I].ResidentMip then
    begin
      { Texture requires finer mip resolution than currently resident: promote }
      FEntries[I].ResidentMip := FEntries[I].RequestedMip;
      Inc(APromotedCount);
      Inc(Result);
    end;
  end;
end;

procedure TCastleVulkanTextureStreamer.UploadFeedbackBuffer;
var
  BufDesc: TRHIBufferDesc;
  RawFeedback: array[0 .. CASTLE_MAX_STREAMED_TEXTURES - 1] of Cardinal;
  I: Cardinal;
  MappedPtr: Pointer;
begin
  if FFeedbackBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(
      SizeOf(RawFeedback),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'TextureStreamingFeedbackBuffer');
    FFeedbackBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  for I := 0 to CASTLE_MAX_STREAMED_TEXTURES - 1 do
    if I < FTextureCount then
      RawFeedback[I] := FEntries[I].RequestedMip
    else
      RawFeedback[I] := $FF;

  MappedPtr := FFeedbackBuffer.Map;
  if MappedPtr <> nil then
  begin
    Move(RawFeedback[0], MappedPtr^, SizeOf(RawFeedback));
    FFeedbackBuffer.Unmap;
  end;
  Inc(FUpdateCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanShadowCasterCuller (Phase 26.3)                                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanShadowCasterCuller.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanShadowCasterCuller.Destroy;
begin
  FreeAndNil(FVisibleCasterBuffer);
  FreeAndNil(FCasterBuffer);
  inherited;
end;

procedure TCastleVulkanShadowCasterCuller.ClearCasters;
begin
  FCasterCount := 0;
  SetLength(FCasters, 0);
end;

function TCastleVulkanShadowCasterCuller.AddCaster(
  const ASphereCenter: TVector3; const ASphereRadius: Single): Integer;
var
  Idx: Integer;
begin
  Idx := Integer(FCasterCount);
  Inc(FCasterCount);
  SetLength(FCasters, FCasterCount);
  FCasters[Idx] := Vector4(ASphereCenter, Max(0.0, ASphereRadius));
  Result := Idx;
end;

procedure TCastleVulkanShadowCasterCuller.UploadCasters;
var
  CountAlloc: Cardinal;
  BufDesc: TRHIBufferDesc;
  MappedPtr: Pointer;
begin
  CountAlloc := Max(Cardinal(1), FCasterCount);
  if (FCasterBuffer = nil) or
     (FCasterBuffer.Desc.Size < CountAlloc * SizeOf(TVector4)) then
  begin
    FreeAndNil(FCasterBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(TVector4),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'ShadowCasterSpheresBuffer');
    FCasterBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if FCasterCount > 0 then
  begin
    MappedPtr := FCasterBuffer.Map;
    if MappedPtr <> nil then
    begin
      Move(FCasters[0], MappedPtr^, FCasterCount * SizeOf(TVector4));
      FCasterBuffer.Unmap;
    end;
  end;

  if (FVisibleCasterBuffer = nil) or
     (FVisibleCasterBuffer.Desc.Size < CountAlloc * SizeOf(Cardinal)) then
  begin
    FreeAndNil(FVisibleCasterBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(Cardinal),
      [buStorage, buTransferSrc],
      muGpuOnly,
      'VisibleShadowCastersBuffer');
    FVisibleCasterBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

function TCastleVulkanShadowCasterCuller.EvaluateActiveShadowCastersCPU(
  const ALightRayDir: TVector3;
  const AMaxExtrusionDist: Single;
  const AReceiverBoxMin, AReceiverBoxMax: TVector3): Cardinal;
var
  I: Cardinal;
begin
  Result := 0;
  if FCasterCount = 0 then
    Exit;
  for I := 0 to FCasterCount - 1 do
    if TCastleShaderGeneratorRHI.EvaluateShadowCasterExtrudedSphereIntersectsAABB(
         FCasters[I].XYZ, FCasters[I].W, ALightRayDir, AMaxExtrusionDist,
         AReceiverBoxMin, AReceiverBoxMax) then
      Inc(Result);
end;

procedure TCastleVulkanShadowCasterCuller.DispatchShadowCasterCulling(
  const ACommandList: TVulkanRHICommandList;
  const ALightRayDir: TVector3;
  const AMaxExtrusionDist: Single;
  const AReceiverBoxMin, AReceiverBoxMax: TVector3;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
type
  TShadowCasterCullPC = packed record
    LightRayDirAndMaxDist: TVector4;
    ReceiverBoxMinAndCount: TVector4;
    ReceiverBoxMax: TVector4;
  end;
var
  PC: TShadowCasterCullPC;
  GroupsX: Cardinal;
begin
  UploadCasters;
  if ACommandList = nil then
    Exit;

  FillChar(PC, SizeOf(PC), 0);
  PC.LightRayDirAndMaxDist := Vector4(ALightRayDir, AMaxExtrusionDist);
  PC.ReceiverBoxMinAndCount := Vector4(AReceiverBoxMin, Single(FCasterCount));
  PC.ReceiverBoxMax := Vector4(AReceiverBoxMax, 0.0);

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PC), PC);

  GroupsX := (Max(Cardinal(1), FCasterCount) + 63) div 64;
  ACommandList.Dispatch(GroupsX, 1, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanClusterDAG (Phase 27.2)                                         }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanClusterDAG.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanClusterDAG.Destroy;
begin
  FreeAndNil(FSelectedCutBuffer);
  FreeAndNil(FDAGNodeBuffer);
  inherited;
end;

procedure TCastleVulkanClusterDAG.ClearNodes;
begin
  FNodeCount := 0;
  SetLength(FNodes, 0);
end;

function TCastleVulkanClusterDAG.AddClusterNode(
  const ASphereCenter: TVector3;
  const ASphereRadius, ASelfWorldError, AParentWorldError: Single;
  const AVertexOffset, ATriangleOffset, ATriangleCount: Cardinal): Integer;
var
  Idx: Integer;
begin
  Idx := Integer(FNodeCount);
  Inc(FNodeCount);
  SetLength(FNodes, FNodeCount);
  FillChar(FNodes[Idx], SizeOf(TCastleClusterDAGNode), 0);
  FNodes[Idx].SphereCenterAndRadius := Vector4(ASphereCenter, Max(0.0, ASphereRadius));
  FNodes[Idx].ParentCenterAndErrors := Vector4(Max(0.0, ASelfWorldError), Max(0.0, AParentWorldError), 0.0, 0.0);
  FNodes[Idx].ClusterID := Cardinal(Idx);
  FNodes[Idx].VertexOffset := AVertexOffset;
  FNodes[Idx].TriangleOffset := ATriangleOffset;
  FNodes[Idx].TriangleCount := ATriangleCount;
  Result := Idx;
end;

procedure TCastleVulkanClusterDAG.UploadNodes;
var
  CountAlloc: Cardinal;
  BufDesc: TRHIBufferDesc;
  MappedPtr: Pointer;
begin
  CountAlloc := Max(Cardinal(1), FNodeCount);
  if (FDAGNodeBuffer = nil) or
     (FDAGNodeBuffer.Desc.Size < CountAlloc * SizeOf(TCastleClusterDAGNode)) then
  begin
    FreeAndNil(FDAGNodeBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(TCastleClusterDAGNode),
      [buStorage, buTransferDst],
      muCpuToGpu,
      'ClusterDAGNodesBuffer');
    FDAGNodeBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if FNodeCount > 0 then
  begin
    MappedPtr := FDAGNodeBuffer.Map;
    if MappedPtr <> nil then
    begin
      Move(FNodes[0], MappedPtr^, FNodeCount * SizeOf(TCastleClusterDAGNode));
      FDAGNodeBuffer.Unmap;
    end;
  end;

  if (FSelectedCutBuffer = nil) or
     (FSelectedCutBuffer.Desc.Size < CountAlloc * SizeOf(Cardinal)) then
  begin
    FreeAndNil(FSelectedCutBuffer);
    BufDesc := TRHIBufferDesc.Create(
      CountAlloc * SizeOf(Cardinal),
      [buStorage, buTransferSrc],
      muGpuOnly,
      'SelectedDAGCutBuffer');
    FSelectedCutBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

function TCastleVulkanClusterDAG.EvaluateDAGCutCPU(
  const ACameraPosition: TVector3;
  const ACotHalfFovY, AViewportHeight, APixelErrorThreshold: Single): Cardinal;
var
  I: Cardinal;
  SelfErrPx, ParentErrPx: Single;
begin
  Result := 0;
  if FNodeCount = 0 then
    Exit;
  for I := 0 to FNodeCount - 1 do
  begin
    SelfErrPx := TCastleShaderGeneratorRHI.EvaluateClusterProjectedErrorPixels(
      FNodes[I].SphereCenterAndRadius.XYZ, ACameraPosition,
      FNodes[I].SphereCenterAndRadius.W, FNodes[I].ParentCenterAndErrors.X,
      ACotHalfFovY, AViewportHeight);
    ParentErrPx := TCastleShaderGeneratorRHI.EvaluateClusterProjectedErrorPixels(
      FNodes[I].SphereCenterAndRadius.XYZ, ACameraPosition,
      FNodes[I].SphereCenterAndRadius.W, FNodes[I].ParentCenterAndErrors.Y,
      ACotHalfFovY, AViewportHeight);
    if TCastleShaderGeneratorRHI.IsClusterDAGCutNode(SelfErrPx, ParentErrPx, APixelErrorThreshold) then
      Inc(Result);
  end;
end;

procedure TCastleVulkanClusterDAG.DispatchDAGCutSelection(
  const ACommandList: TVulkanRHICommandList;
  const ACameraPosition: TVector3;
  const ACotHalfFovY, AViewportHeight, APixelErrorThreshold: Single;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
type
  TClusterDAGCutPC = packed record
    CameraPosAndCotHalfFovY: TVector4;
    ViewportHeightThresholdAndCount: TVector4;
  end;
var
  PC: TClusterDAGCutPC;
  GroupsX: Cardinal;
begin
  UploadNodes;
  if ACommandList = nil then
    Exit;

  FillChar(PC, SizeOf(PC), 0);
  PC.CameraPosAndCotHalfFovY := Vector4(ACameraPosition, ACotHalfFovY);
  PC.ViewportHeightThresholdAndCount := Vector4(AViewportHeight, APixelErrorThreshold, Single(FNodeCount), 0.0);

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);
  ACommandList.PushConstants([ssCompute], 0, SizeOf(PC), PC);

  GroupsX := (Max(Cardinal(1), FNodeCount) + 63) div 64;
  ACommandList.Dispatch(GroupsX, 1, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanGlobalSDF (Phase 28.1)                                          }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanGlobalSDF.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FGridResolution := 32;
  FClipmapHalfExtent := 50.0;
  FSmoothBlendRadius := 0.25;
end;

destructor TCastleVulkanGlobalSDF.Destroy;
begin
  FreeAndNil(FClipmapVolumeTexture);
  inherited;
end;

procedure TCastleVulkanGlobalSDF.ClearPrimitives;
begin
  FPrimitiveCount := 0;
  SetLength(FPrimitives, 0);
end;

function TCastleVulkanGlobalSDF.AddBoxPrimitive(
  const ABoxCenter, ABoxHalfExtents: TVector3): Integer;
var
  Idx: Integer;
begin
  Idx := Integer(FPrimitiveCount);
  Inc(FPrimitiveCount);
  SetLength(FPrimitives, FPrimitiveCount);
  FPrimitives[Idx].Center := ABoxCenter;
  FPrimitives[Idx].HalfExtents := ABoxHalfExtents;
  Result := Idx;
end;

procedure TCastleVulkanGlobalSDF.EnsureVolumeResources(const AGridResolution: Cardinal);
var
  TexDesc: TRHITextureDesc;
begin
  FGridResolution := Max(Cardinal(8), AGridResolution);
  if (FClipmapVolumeTexture <> nil) and
     (FClipmapVolumeTexture.Desc.Width = FGridResolution) then
    Exit;

  FreeAndNil(FClipmapVolumeTexture);
  FillChar(TexDesc, SizeOf(TexDesc), 0);
  TexDesc.Dimension := td3D;
  TexDesc.Format := pfR16_Float;
  TexDesc.Width := FGridResolution;
  TexDesc.Height := FGridResolution;
  TexDesc.DepthOrArrayLayers := FGridResolution;
  TexDesc.MipLevels := 1;
  TexDesc.SampleCount := 1;
  TexDesc.Usage := [tuSampled, tuStorage, tuTransferDst];
  TexDesc.DebugName := 'GlobalSDFClipmapVolume';
  FClipmapVolumeTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

function TCastleVulkanGlobalSDF.EvaluateGlobalSDFDistanceCPU(const AWorldPos: TVector3): Single;
var
  I: Cardinal;
  DistI: Single;
begin
  if FPrimitiveCount = 0 then
    Exit(1e6);
  Result := TCastleShaderGeneratorRHI.EvaluateSDFBoxDistance(
    AWorldPos, FPrimitives[0].Center, FPrimitives[0].HalfExtents);
  if FPrimitiveCount > 1 then
    for I := 1 to FPrimitiveCount - 1 do
    begin
      DistI := TCastleShaderGeneratorRHI.EvaluateSDFBoxDistance(
        AWorldPos, FPrimitives[I].Center, FPrimitives[I].HalfExtents);
      if FSmoothBlendRadius > 1e-5 then
        Result := TCastleShaderGeneratorRHI.EvaluateSDFSmoothUnion(Result, DistI, FSmoothBlendRadius)
      else
        Result := Min(Result, DistI);
    end;
end;

function TCastleVulkanGlobalSDF.TraceSphereMarchCPU(
  const ARayOrigin, ARayDir: TVector3;
  const AMaxDistance: Single;
  out AHitDistance: Single;
  out AHitSteps: Cardinal;
  const AMaxSteps: Cardinal;
  const AHitEpsilon: Single): Boolean;
var
  DirNorm, SamplePos: TVector3;
  T, Dist: Single;
  StepIdx: Cardinal;
begin
  Result := False;
  AHitDistance := AMaxDistance;
  AHitSteps := 0;
  if AMaxSteps = 0 then
    Exit;

  DirNorm := ARayDir.Normalize;
  T := 0.0;
  for StepIdx := 1 to AMaxSteps do
  begin
    AHitSteps := StepIdx;
    SamplePos := ARayOrigin + DirNorm * T;
    Dist := EvaluateGlobalSDFDistanceCPU(SamplePos);
    if Dist <= AHitEpsilon then
    begin
      AHitDistance := T;
      Exit(True);
    end;
    T := T + Max(AHitEpsilon * 0.5, Dist);
    if T >= AMaxDistance then
      Exit(False);
  end;
end;

procedure TCastleVulkanGlobalSDF.DispatchGlobalSDFBuild(
  const ACommandList: TVulkanRHICommandList;
  const AGridResolution: Cardinal);
var
  Groups: Cardinal;
begin
  EnsureVolumeResources(AGridResolution);
  if ACommandList = nil then
    Exit;
  Groups := (FGridResolution + 3) div 4;
  ACommandList.Dispatch(Groups, Groups, Groups);
  Inc(FBuildCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanSurfaceCache (Phase 28.2)                                       }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanSurfaceCache.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FAtlasResolution := 512;
  FTileResolution := 64;
  FTilesPerRow := FAtlasResolution div FTileResolution;
  FMaxCardSlots := FTilesPerRow * FTilesPerRow;
  FAllocatedCardCount := 0;
end;

destructor TCastleVulkanSurfaceCache.Destroy;
begin
  FreeAndNil(FDirectLightingAtlasTexture);
  FreeAndNil(FAlbedoAtlasTexture);
  inherited;
end;

procedure TCastleVulkanSurfaceCache.ResetCards;
begin
  FAllocatedCardCount := 0;
end;

function TCastleVulkanSurfaceCache.AllocateSixAxisCards(out AFirstCardSlot: Cardinal): Boolean;
begin
  if FAllocatedCardCount + 6 > FMaxCardSlots then
  begin
    AFirstCardSlot := 0;
    Exit(False);
  end;
  AFirstCardSlot := FAllocatedCardCount;
  Inc(FAllocatedCardCount, 6);
  Result := True;
end;

procedure TCastleVulkanSurfaceCache.GetCardAtlasOffsetAndScale(
  const ACardSlot: Cardinal;
  out AOffsetUV, AScaleUV: TVector2);
var
  TileX, TileY: Cardinal;
  InvTiles: Single;
begin
  InvTiles := 1.0 / Max(1.0, Single(FTilesPerRow));
  TileX := ACardSlot mod Max(Cardinal(1), FTilesPerRow);
  TileY := ACardSlot div Max(Cardinal(1), FTilesPerRow);
  AOffsetUV := Vector2(Single(TileX) * InvTiles, Single(TileY) * InvTiles);
  AScaleUV := Vector2(InvTiles, InvTiles);
end;

procedure TCastleVulkanSurfaceCache.EnsureAtlasTextures;
var
  TexDesc: TRHITextureDesc;
begin
  if FAlbedoAtlasTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      FAtlasResolution, FAtlasResolution, pfRGBA16_Float,
      [tuSampled, tuColorAttachment, tuStorage]);
    TexDesc.DebugName := 'LumenSurfaceCacheAlbedoAtlas';
    FAlbedoAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
  if FDirectLightingAtlasTexture = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      FAtlasResolution, FAtlasResolution, pfRGBA16_Float,
      [tuSampled, tuColorAttachment, tuStorage]);
    TexDesc.DebugName := 'LumenSurfaceCacheDirectLightingAtlas';
    FDirectLightingAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanReSTIR (Phase 29.2)                                             }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanReSTIR.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxHistoryM := 20;
end;

destructor TCastleVulkanReSTIR.Destroy;
begin
  FreeAndNil(FTemporalHistoryReservoirBuffer);
  FreeAndNil(FCurrentReservoirBuffer);
  inherited;
end;

procedure TCastleVulkanReSTIR.EnsureReservoirBuffers(const AWidth, AHeight: Cardinal);
var
  PixelCount, RequiredBytes: Cardinal;
  BufDesc: TRHIBufferDesc;
begin
  FWidth := Max(Cardinal(1), AWidth);
  FHeight := Max(Cardinal(1), AHeight);
  PixelCount := FWidth * FHeight;
  RequiredBytes := PixelCount * SizeOf(TCastleReSTIRReservoir);

  if (FCurrentReservoirBuffer = nil) or (FCurrentReservoirBuffer.Desc.Size < RequiredBytes) then
  begin
    FreeAndNil(FCurrentReservoirBuffer);
    BufDesc := TRHIBufferDesc.Create(
      RequiredBytes,
      [buStorage, buTransferDst, buTransferSrc],
      muGpuOnly,
      'ReSTIRCurrentReservoirBuffer');
    FCurrentReservoirBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if (FTemporalHistoryReservoirBuffer = nil) or (FTemporalHistoryReservoirBuffer.Desc.Size < RequiredBytes) then
  begin
    FreeAndNil(FTemporalHistoryReservoirBuffer);
    BufDesc := TRHIBufferDesc.Create(
      RequiredBytes,
      [buStorage, buTransferDst, buTransferSrc],
      muGpuOnly,
      'ReSTIRHistoryReservoirBuffer');
    FTemporalHistoryReservoirBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

procedure TCastleVulkanReSTIR.SwapReservoirHistory;
var
  Tmp: TVulkanRHIBuffer;
begin
  Tmp := FCurrentReservoirBuffer;
  FCurrentReservoirBuffer := FTemporalHistoryReservoirBuffer;
  FTemporalHistoryReservoirBuffer := Tmp;
end;

procedure TCastleVulkanReSTIR.DispatchSpatioTemporalResampling(
  const ACommandList: TVulkanRHICommandList;
  const AWidth, AHeight: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  GroupsX, GroupsY: Cardinal;
begin
  EnsureReservoirBuffers(AWidth, AHeight);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanTSRUpscaler (Phase 30.1)                                        }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanTSRUpscaler.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FRenderScale := 0.666667; // 67% Quality mode (e.g. 1280x720 -> 1920x1080)
end;

destructor TCastleVulkanTSRUpscaler.Destroy;
begin
  FreeAndNil(FHistoryColorTexture);
  FreeAndNil(FUpscaledColorTexture);
  inherited;
end;

procedure TCastleVulkanTSRUpscaler.ComputeInputResolution(
  const AOutputWidth, AOutputHeight: Cardinal;
  out AInputWidth, AInputHeight: Cardinal);
var
  ClampedScale: Single;
begin
  ClampedScale := EnsureRange(FRenderScale, 0.25, 1.0);
  AInputWidth := Max(Cardinal(1), Cardinal(Round(Single(AOutputWidth) * ClampedScale)));
  AInputHeight := Max(Cardinal(1), Cardinal(Round(Single(AOutputHeight) * ClampedScale)));
end;

procedure TCastleVulkanTSRUpscaler.EnsureUpscaleTargets(const AOutputWidth, AOutputHeight: Cardinal);
var
  TexDesc: TRHITextureDesc;
begin
  FOutputWidth := Max(Cardinal(1), AOutputWidth);
  FOutputHeight := Max(Cardinal(1), AOutputHeight);

  if (FUpscaledColorTexture = nil) or
     (FUpscaledColorTexture.Desc.Width <> FOutputWidth) or
     (FUpscaledColorTexture.Desc.Height <> FOutputHeight) then
  begin
    FreeAndNil(FUpscaledColorTexture);
    TexDesc := TRHITextureDesc.Create2D(
      FOutputWidth, FOutputHeight, pfRGBA16_Float,
      [tuSampled, tuStorage, tuColorAttachment, tuTransferSrc]);
    TexDesc.DebugName := 'TSRUpscaledColorTexture';
    FUpscaledColorTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;

  if (FHistoryColorTexture = nil) or
     (FHistoryColorTexture.Desc.Width <> FOutputWidth) or
     (FHistoryColorTexture.Desc.Height <> FOutputHeight) then
  begin
    FreeAndNil(FHistoryColorTexture);
    TexDesc := TRHITextureDesc.Create2D(
      FOutputWidth, FOutputHeight, pfRGBA16_Float,
      [tuSampled, tuStorage, tuColorAttachment, tuTransferDst]);
    TexDesc.DebugName := 'TSRHistoryColorTexture';
    FHistoryColorTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

procedure TCastleVulkanTSRUpscaler.SwapHistoryTargets;
var
  Tmp: TVulkanRHITexture;
begin
  Tmp := FUpscaledColorTexture;
  FUpscaledColorTexture := FHistoryColorTexture;
  FHistoryColorTexture := Tmp;
end;

procedure TCastleVulkanTSRUpscaler.DispatchTSRUpscale(
  const ACommandList: TVulkanRHICommandList;
  const AOutputWidth, AOutputHeight: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  GroupsX, GroupsY: Cardinal;
begin
  EnsureUpscaleTargets(AOutputWidth, AOutputHeight);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (FOutputWidth + 7) div 8;
  GroupsY := (FOutputHeight + 7) div 8;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanVRSManager (Phase 32.2)                                         }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanVRSManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FTileSize := 16;
end;

destructor TCastleVulkanVRSManager.Destroy;
begin
  FreeAndNil(FShadingRateImage);
  inherited;
end;

procedure TCastleVulkanVRSManager.EnsureShadingRateImage(
  const AViewportWidth, AViewportHeight: Cardinal);
var
  SafeTile: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  SafeTile := Max(Cardinal(8), FTileSize);
  FTileGridWidth := (Max(Cardinal(1), AViewportWidth) + SafeTile - 1) div SafeTile;
  FTileGridHeight := (Max(Cardinal(1), AViewportHeight) + SafeTile - 1) div SafeTile;

  if (FShadingRateImage = nil) or
     (FShadingRateImage.Desc.Width <> FTileGridWidth) or
     (FShadingRateImage.Desc.Height <> FTileGridHeight) then
  begin
    FreeAndNil(FShadingRateImage);
    TexDesc := TRHITextureDesc.Create2D(
      FTileGridWidth, FTileGridHeight, pfR8_UNorm,
      [tuSampled, tuStorage, tuTransferDst]);
    TexDesc.DebugName := 'VRSShadingRateTileImage';
    FShadingRateImage := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

procedure TCastleVulkanVRSManager.DispatchVRSImageGeneration(
  const ACommandList: TVulkanRHICommandList;
  const AViewportWidth, AViewportHeight: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
begin
  EnsureShadingRateImage(AViewportWidth, AViewportHeight);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  ACommandList.Dispatch(FTileGridWidth, FTileGridHeight, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanRuntimeVirtualTexture (Phase 32.3)                              }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanRuntimeVirtualTexture.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FPhysicalTilesPerRow := 16;
  FPhysicalTileResolution := 128;
  FMaxPhysicalTiles := FPhysicalTilesPerRow * FPhysicalTilesPerRow;
  ClearPages;
end;

destructor TCastleVulkanRuntimeVirtualTexture.Destroy;
begin
  FreeAndNil(FPhysicalNormalRoughnessAtlas);
  FreeAndNil(FPhysicalAlbedoAtlas);
  inherited;
end;

procedure TCastleVulkanRuntimeVirtualTexture.ClearPages;
var
  X, Y: Integer;
begin
  FAllocatedTileCount := 0;
  for Y := 0 to 63 do
    for X := 0 to 63 do
      FPageTable[X, Y] := -1;
end;

function TCastleVulkanRuntimeVirtualTexture.RequestRVTPage(
  const AVirtualPageX, AVirtualPageY: Cardinal;
  out APhysicalTileX, APhysicalTileY: Cardinal): Boolean;
var
  ExistingTile, NewTile: Integer;
begin
  APhysicalTileX := 0;
  APhysicalTileY := 0;
  if (AVirtualPageX >= 64) or (AVirtualPageY >= 64) then
    Exit(False);

  ExistingTile := FPageTable[AVirtualPageX, AVirtualPageY];
  if ExistingTile >= 0 then
  begin
    APhysicalTileX := Cardinal(ExistingTile) mod FPhysicalTilesPerRow;
    APhysicalTileY := Cardinal(ExistingTile) div FPhysicalTilesPerRow;
    Exit(True);
  end;

  if FAllocatedTileCount >= FMaxPhysicalTiles then
    Exit(False);

  NewTile := Integer(FAllocatedTileCount);
  Inc(FAllocatedTileCount);
  FPageTable[AVirtualPageX, AVirtualPageY] := NewTile;
  APhysicalTileX := Cardinal(NewTile) mod FPhysicalTilesPerRow;
  APhysicalTileY := Cardinal(NewTile) div FPhysicalTilesPerRow;
  Result := True;
end;

procedure TCastleVulkanRuntimeVirtualTexture.EnsurePhysicalAtlasTextures;
var
  AtlasSize: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  AtlasSize := FPhysicalTilesPerRow * FPhysicalTileResolution;
  if FPhysicalAlbedoAtlas = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      AtlasSize, AtlasSize, pfRGBA8_UNorm,
      [tuSampled, tuColorAttachment, tuStorage]);
    TexDesc.DebugName := 'RVTPhysicalAlbedoAtlas';
    FPhysicalAlbedoAtlas := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
  if FPhysicalNormalRoughnessAtlas = nil then
  begin
    TexDesc := TRHITextureDesc.Create2D(
      AtlasSize, AtlasSize, pfRGBA8_UNorm,
      [tuSampled, tuColorAttachment, tuStorage]);
    TexDesc.DebugName := 'RVTPhysicalNormalRoughnessAtlas';
    FPhysicalNormalRoughnessAtlas := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanSparseVolumeAtlas (Phase 33.2)                                  }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanSparseVolumeAtlas.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FBrickResolution := 8;
  FBricksPerAxis := 8;
  FMaxPhysicalBricks := FBricksPerAxis * FBricksPerAxis * FBricksPerAxis;
  ClearBricks;
end;

destructor TCastleVulkanSparseVolumeAtlas.Destroy;
begin
  FreeAndNil(FPhysicalBrickAtlasTexture);
  inherited;
end;

procedure TCastleVulkanSparseVolumeAtlas.ClearBricks;
var
  X, Y, Z: Integer;
begin
  FAllocatedBrickCount := 0;
  for Z := 0 to 15 do
    for Y := 0 to 15 do
      for X := 0 to 15 do
        FIndirectionGrid[X, Y, Z] := -1;
end;

function TCastleVulkanSparseVolumeAtlas.AllocateVolumeBrick(
  const AVirtualBrickX, AVirtualBrickY, AVirtualBrickZ: Cardinal;
  out APhysicalBrickIndex: Cardinal): Boolean;
var
  ExistingBrick, NewBrick: Integer;
begin
  APhysicalBrickIndex := 0;
  if (AVirtualBrickX >= 16) or (AVirtualBrickY >= 16) or (AVirtualBrickZ >= 16) then
    Exit(False);

  ExistingBrick := FIndirectionGrid[AVirtualBrickX, AVirtualBrickY, AVirtualBrickZ];
  if ExistingBrick >= 0 then
  begin
    APhysicalBrickIndex := Cardinal(ExistingBrick);
    Exit(True);
  end;

  if FAllocatedBrickCount >= FMaxPhysicalBricks then
    Exit(False);

  NewBrick := Integer(FAllocatedBrickCount);
  Inc(FAllocatedBrickCount);
  FIndirectionGrid[AVirtualBrickX, AVirtualBrickY, AVirtualBrickZ] := NewBrick;
  APhysicalBrickIndex := Cardinal(NewBrick);
  Result := True;
end;

procedure TCastleVulkanSparseVolumeAtlas.EnsureVolumeAtlasTextures;
var
  AtlasDim: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  if FPhysicalBrickAtlasTexture <> nil then
    Exit;
  AtlasDim := FBricksPerAxis * FBrickResolution;
  FillChar(TexDesc, SizeOf(TexDesc), 0);
  TexDesc.Dimension := td3D;
  TexDesc.Width := AtlasDim;
  TexDesc.Height := AtlasDim;
  TexDesc.DepthOrArrayLayers := AtlasDim;
  TexDesc.MipLevels := 1;
  TexDesc.SampleCount := 1;
  TexDesc.Format := pfRGBA16_Float;
  TexDesc.Usage := [tuSampled, tuStorage, tuTransferDst];
  TexDesc.DebugName := 'SparseVolumePhysicalBrickAtlas3D';
  FPhysicalBrickAtlasTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanBreadcrumbTracker (Phase 33.3)                                  }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanBreadcrumbTracker.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanBreadcrumbTracker.Destroy;
begin
  FreeAndNil(FBreadcrumbBuffer);
  inherited;
end;

procedure TCastleVulkanBreadcrumbTracker.ResetBreadcrumbs;
begin
  SetLength(FEntries, 0);
end;

procedure TCastleVulkanBreadcrumbTracker.EnsureBreadcrumbBuffer;
var
  BufDesc: TRHIBufferDesc;
begin
  if FBreadcrumbBuffer <> nil then
    Exit;
  BufDesc := TRHIBufferDesc.Create(4096, [buStorage, buTransferDst], muGpuToCpu,
    'GPUBreadcrumbMarkerBuffer');
  FBreadcrumbBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
end;

function TCastleVulkanBreadcrumbTracker.BeginBreadcrumbScope(
  const ACommandList: TVulkanRHICommandList;
  const AScopeName: String): Cardinal;
var
  Idx: Integer;
begin
  EnsureBreadcrumbBuffer;
  Idx := Length(FEntries);
  SetLength(FEntries, Idx + 1);
  FEntries[Idx].MarkerID := Cardinal(Idx + 1);
  FEntries[Idx].ScopeName := AScopeName;
  FEntries[Idx].State := bsActive;
  Result := FEntries[Idx].MarkerID;
end;

procedure TCastleVulkanBreadcrumbTracker.EndBreadcrumbScope(
  const ACommandList: TVulkanRHICommandList;
  const AMarkerID: Cardinal);
var
  I: Integer;
begin
  for I := 0 to High(FEntries) do
    if FEntries[I].MarkerID = AMarkerID then
    begin
      FEntries[I].State := bsCompleted;
      Exit;
    end;
end;

function TCastleVulkanBreadcrumbTracker.GetTotalScopesRecorded: Cardinal;
begin
  Result := Cardinal(Length(FEntries));
end;

function TCastleVulkanBreadcrumbTracker.GetActiveScopeCount: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FEntries) do
    if FEntries[I].State = bsActive then
      Inc(Result);
end;

function TCastleVulkanBreadcrumbTracker.GetCompletedScopeCount: Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FEntries) do
    if FEntries[I].State = bsCompleted then
      Inc(Result);
end;

function TCastleVulkanBreadcrumbTracker.FormatBreadcrumbCrashReport: String;
var
  I: Integer;
  StateLabel: String;
begin
  Result := Format('GPU Breadcrumb Crash Report (Total=%d, Completed=%d, Active/Hung=%d):',
    [TotalScopesRecorded, CompletedScopeCount, ActiveScopeCount]) + LineEnding;
  for I := 0 to High(FEntries) do
  begin
    case FEntries[I].State of
      bsCompleted: StateLabel := 'COMPLETED';
      bsActive:    StateLabel := 'ACTIVE_IN_FLIGHT (SUSPECTED GPU HANG)';
    else
      StateLabel := 'PENDING';
    end;
    Result := Result + Format('  [Marker #%d] %s -> %s',
      [FEntries[I].MarkerID, FEntries[I].ScopeName, StateLabel]) + LineEnding;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanSVGFDenoiser (Phase 34.3)                                       }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanSVGFDenoiser.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FAttrousIterations := 4;
end;

destructor TCastleVulkanSVGFDenoiser.Destroy;
begin
  FreeAndNil(FFilteredPongTexture);
  FreeAndNil(FFilteredPingTexture);
  FreeAndNil(FMomentsHistoryTexture);
  inherited;
end;

procedure TCastleVulkanSVGFDenoiser.EnsureSVGFTargets(const AWidth, AHeight: Cardinal);
var
  SafeW, SafeH: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  SafeW := Max(Cardinal(1), AWidth);
  SafeH := Max(Cardinal(1), AHeight);
  if (FMomentsHistoryTexture <> nil) and (FWidth = SafeW) and (FHeight = SafeH) then
    Exit;

  FWidth := SafeW;
  FHeight := SafeH;
  FreeAndNil(FFilteredPongTexture);
  FreeAndNil(FFilteredPingTexture);
  FreeAndNil(FMomentsHistoryTexture);

  TexDesc := TRHITextureDesc.Create2D(SafeW, SafeH, pfRG16_Float,
    [tuSampled, tuStorage, tuTransferDst]);
  TexDesc.DebugName := 'SVGFMomentsHistory';
  FMomentsHistoryTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc := TRHITextureDesc.Create2D(SafeW, SafeH, pfRGBA16_Float,
    [tuSampled, tuStorage, tuTransferDst]);
  TexDesc.DebugName := 'SVGFFilteredPing';
  FFilteredPingTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc.DebugName := 'SVGFFilteredPong';
  FFilteredPongTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

class function TCastleVulkanSVGFDenoiser.GetAttrousStepSize(
  const AIterationIndex: Cardinal): Cardinal;
begin
  Result := Cardinal(1) shl Min(Cardinal(8), AIterationIndex);
end;

procedure TCastleVulkanSVGFDenoiser.DispatchSVGFDenoise(
  const ACommandList: TVulkanRHICommandList;
  const AWidth, AHeight: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  GroupsX, GroupsY, Iter, Iters: Cardinal;
begin
  EnsureSVGFTargets(AWidth, AHeight);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;
  Iters := Max(Cardinal(1), FAttrousIterations);
  for Iter := 0 to Iters - 1 do
  begin
    ACommandList.Dispatch(GroupsX, GroupsY, 1);
    Inc(FDispatchCount);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanShaderBindingTable (Phase 35.2)                                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanShaderBindingTable.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FHandleSize := 32;
  FHandleAlignment := 32;
  FBaseAlignment := 64;
end;

destructor TCastleVulkanShaderBindingTable.Destroy;
begin
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
  BufDesc := TRHIBufferDesc.Create(FTotalSBTSizeBytes, [buStorage, buTransferDst], muCpuToGpu,
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

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanAccelerationStructureManager (Phase 35.3)                       }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanAccelerationStructureManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanAccelerationStructureManager.Destroy;
begin
  FreeAndNil(FTLASBuffer);
  inherited;
end;

procedure TCastleVulkanAccelerationStructureManager.ClearAccelerationStructures;
begin
  SetLength(FBLASEntries, 0);
  FTLASInstanceCount := 0;
  FTLASBuildCount := 0;
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
  FBLASEntries[Idx].BLASID := Cardinal(Idx + 1);
  FBLASEntries[Idx].TriangleCount := ATriangleCount;
  FBLASEntries[Idx].UncompactedBytes := SafeBytes;
  FBLASEntries[Idx].CompactedBytes := SafeBytes;
  FBLASEntries[Idx].IsCompacted := False;
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
    BufDesc := TRHIBufferDesc.Create(ReqBytes, [buStorage, buTransferDst], muCpuToGpu,
      'TopLevelAccelerationStructureBuffer');
    FTLASBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
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

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanXPBDSimulator (Phase 36.3)                                      }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanXPBDSimulator.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FSubstepCount := 4;
end;

destructor TCastleVulkanXPBDSimulator.Destroy;
begin
  FreeAndNil(FConstraintBuffer);
  FreeAndNil(FPreviousPositionBuffer);
  FreeAndNil(FParticlePositionBuffer);
  inherited;
end;

procedure TCastleVulkanXPBDSimulator.EnsureSimulationBuffers(
  const AParticleCount, AConstraintCount: Cardinal);
var
  SafeParticles, SafeConstraints: Cardinal;
  BufDesc: TRHIBufferDesc;
begin
  SafeParticles := Max(Cardinal(1), AParticleCount);
  SafeConstraints := Max(Cardinal(1), AConstraintCount);
  if (FParticlePositionBuffer <> nil) and
     (FParticleCount = SafeParticles) and
     (FConstraintCount = SafeConstraints) then
    Exit;

  FParticleCount := SafeParticles;
  FConstraintCount := SafeConstraints;
  FreeAndNil(FConstraintBuffer);
  FreeAndNil(FPreviousPositionBuffer);
  FreeAndNil(FParticlePositionBuffer);

  BufDesc := TRHIBufferDesc.Create(SafeParticles * 16, [buStorage, buTransferDst], muCpuToGpu,
    'XPBDParticlePositionSSBO');
  FParticlePositionBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc.DebugName := 'XPBDPreviousPositionSSBO';
  FPreviousPositionBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(SafeConstraints * 16, [buStorage, buTransferDst], muCpuToGpu,
    'XPBDDistanceConstraintSSBO');
  FConstraintBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
end;

procedure TCastleVulkanXPBDSimulator.DispatchXPBDSubsteps(
  const ACommandList: TVulkanRHICommandList;
  const AParticleCount, AConstraintCount: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  GroupsX, Step, Steps: Cardinal;
begin
  EnsureSimulationBuffers(AParticleCount, AConstraintCount);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (Max(FParticleCount, FConstraintCount) + 63) div 64;
  Steps := Max(Cardinal(1), FSubstepCount);
  for Step := 0 to Steps - 1 do
  begin
    ACommandList.Dispatch(GroupsX, 1, 1);
    Inc(FTotalSubstepsDispatched);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanMultiviewStereoManager (Phase 37)                               }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanMultiviewStereoManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FViewMask := $3; // Bit 0 = Left Eye, Bit 1 = Right Eye
  FIPDMeters := 0.064; // Standard 64 mm interpupillary distance
  FLeftEyeGazeUV := Vector2(0.5, 0.5);
  FRightEyeGazeUV := Vector2(0.5, 0.5);
end;

destructor TCastleVulkanMultiviewStereoManager.Destroy;
begin
  FreeAndNil(FStereoDepthArrayTexture);
  FreeAndNil(FStereoColorArrayTexture);
  inherited;
end;

procedure TCastleVulkanMultiviewStereoManager.EnsureStereoTargets(
  const AEyeWidth, AEyeHeight: Cardinal);
var
  SafeW, SafeH: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  SafeW := Max(Cardinal(1), AEyeWidth);
  SafeH := Max(Cardinal(1), AEyeHeight);
  if (FStereoColorArrayTexture <> nil) and
     (FEyeWidth = SafeW) and (FEyeHeight = SafeH) then
    Exit;

  FEyeWidth := SafeW;
  FEyeHeight := SafeH;
  FreeAndNil(FStereoDepthArrayTexture);
  FreeAndNil(FStereoColorArrayTexture);

  TexDesc := TRHITextureDesc.Create2D(SafeW, SafeH, pfRGBA16_Float,
    [tuColorAttachment, tuSampled], 1, 1);
  TexDesc.Dimension := td2DArray;
  TexDesc.DepthOrArrayLayers := 2;
  TexDesc.DebugName := 'StereoMultiviewColorArray';
  FStereoColorArrayTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;

  TexDesc := TRHITextureDesc.Create2D(SafeW, SafeH, pfD32_Float,
    [tuDepthStencil, tuSampled], 1, 1);
  TexDesc.Dimension := td2DArray;
  TexDesc.DepthOrArrayLayers := 2;
  TexDesc.DebugName := 'StereoMultiviewDepthArray';
  FStereoDepthArrayTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

procedure TCastleVulkanMultiviewStereoManager.BeginStereoMultiviewPass(
  const ACommandList: TVulkanRHICommandList;
  const AEyeWidth, AEyeHeight: Cardinal);
var
  RenderInfo: TRHIRenderingInfo;
begin
  EnsureStereoTargets(AEyeWidth, AEyeHeight);
  if ACommandList = nil then
    Exit;

  RenderInfo := TRHIRenderingInfo.CreateColorDepth(
    Rectangle(0, 0, FEyeWidth, FEyeHeight),
    FStereoColorArrayTexture, loClear, Vector4(0, 0, 0, 1),
    FStereoDepthArrayTexture, loClear, 1.0);
  ACommandList.BeginRendering(RenderInfo);
  Inc(FStereoPassCount);
end;

procedure TCastleVulkanMultiviewStereoManager.EndStereoMultiviewPass(
  const ACommandList: TVulkanRHICommandList);
begin
  if ACommandList <> nil then
    ACommandList.EndRendering;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanPerInstanceCustomData (Phase 38.3)                              }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanPerInstanceCustomData.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanPerInstanceCustomData.Destroy;
begin
  FreeAndNil(FInstanceCustomDataBuffer);
  inherited;
end;

procedure TCastleVulkanPerInstanceCustomData.ClearInstanceCustomData;
begin
  SetLength(FCustomDataEntries, 0);
end;

procedure TCastleVulkanPerInstanceCustomData.SetInstanceCustomData(
  const AInstanceIndex: Cardinal;
  const ACustomPayload: TVector4);
var
  OldLen, I: Integer;
begin
  if AInstanceIndex >= Cardinal(Length(FCustomDataEntries)) then
  begin
    OldLen := Length(FCustomDataEntries);
    SetLength(FCustomDataEntries, AInstanceIndex + 1);
    for I := OldLen to High(FCustomDataEntries) do
      FCustomDataEntries[I] := TVector4.Zero;
  end;
  FCustomDataEntries[AInstanceIndex] := ACustomPayload;
end;

function TCastleVulkanPerInstanceCustomData.GetInstanceCustomData(
  const AInstanceIndex: Cardinal): TVector4;
begin
  if AInstanceIndex < Cardinal(Length(FCustomDataEntries)) then
    Result := FCustomDataEntries[AInstanceIndex]
  else
    Result := TVector4.Zero;
end;

procedure TCastleVulkanPerInstanceCustomData.UploadCustomDataBuffer;
var
  Count: Cardinal;
  BufDesc: TRHIBufferDesc;
  InitPtr: Pointer;
begin
  Count := Max(Cardinal(1), Cardinal(Length(FCustomDataEntries)));
  FreeAndNil(FInstanceCustomDataBuffer);
  BufDesc := TRHIBufferDesc.Create(Count * SizeOf(TVector4),
    [buStorage, buTransferDst], muCpuToGpu, 'PerInstanceCustomDataSSBO');
  if Length(FCustomDataEntries) > 0 then
    InitPtr := @FCustomDataEntries[0]
  else
    InitPtr := nil;
  FInstanceCustomDataBuffer := FDevice.CreateBuffer(BufDesc, InitPtr) as TVulkanRHIBuffer;
  Inc(FUploadCount);
end;

function TCastleVulkanPerInstanceCustomData.GetInstanceCount: Cardinal;
begin
  Result := Cardinal(Length(FCustomDataEntries));
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanNeuralDenoiser (Phase 39.3)                                     }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanNeuralDenoiser.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FHiddenUnits := 32;
end;

destructor TCastleVulkanNeuralDenoiser.Destroy;
begin
  FreeAndNil(FDenoisedOutputTexture);
  FreeAndNil(FMLPWeightsBuffer);
  inherited;
end;

class function TCastleVulkanNeuralDenoiser.EvaluateLinearReLU4(
  const AInput, AWeights: TVector4;
  const ABias: Single): Single;
begin
  Result := Max(0.0, TVector4.DotProduct(AInput, AWeights) + ABias);
end;

procedure TCastleVulkanNeuralDenoiser.EnsureNeuralResources(
  const AWidth, AHeight: Cardinal);
var
  SafeW, SafeH, WeightBytes: Cardinal;
  BufDesc: TRHIBufferDesc;
  TexDesc: TRHITextureDesc;
begin
  SafeW := Max(Cardinal(1), AWidth);
  SafeH := Max(Cardinal(1), AHeight);
  if (FDenoisedOutputTexture <> nil) and (FMLPWeightsBuffer <> nil) and
     (FWidth = SafeW) and (FHeight = SafeH) then
    Exit;

  FWidth := SafeW;
  FHeight := SafeH;
  FreeAndNil(FDenoisedOutputTexture);
  FreeAndNil(FMLPWeightsBuffer);

  WeightBytes := Max(Cardinal(64), FHiddenUnits * FHiddenUnits * SizeOf(Single));
  BufDesc := TRHIBufferDesc.Create(WeightBytes,
    [buStorage, buTransferDst], muCpuToGpu, 'NeuralMLPWeightsSSBO');
  FMLPWeightsBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  TexDesc := TRHITextureDesc.Create2D(SafeW, SafeH, pfRGBA16_Float,
    [tuStorage, tuSampled], 1, 1);
  TexDesc.DebugName := 'NeuralDenoisedOutputTexture';
  FDenoisedOutputTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
end;

procedure TCastleVulkanNeuralDenoiser.DispatchNeuralInference(
  const ACommandList: TVulkanRHICommandList;
  const AWidth, AHeight: Cardinal;
  const APipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  GroupsX, GroupsY: Cardinal;
begin
  EnsureNeuralResources(AWidth, AHeight);
  if ACommandList = nil then
    Exit;

  if APipeline <> nil then
    ACommandList.BindComputePipeline(APipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (FWidth + 7) div 8;
  GroupsY := (FHeight + 7) div 8;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FInferenceDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanProgrammableSampleLocations (Phase 40.3)                        }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanProgrammableSampleLocations.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  ConfigureRotatedGridPattern(4);
end;

destructor TCastleVulkanProgrammableSampleLocations.Destroy;
begin
  SetLength(FSampleLocations, 0);
  inherited;
end;

procedure TCastleVulkanProgrammableSampleLocations.ConfigureRotatedGridPattern(
  const ASampleCount: Cardinal);
var
  I: Cardinal;
begin
  if ASampleCount <= 1 then
  begin
    SetLength(FSampleLocations, 1);
    FSampleLocations[0] := Vector2(0.5, 0.5);
  end else
  if ASampleCount = 2 then
  begin
    SetLength(FSampleLocations, 2);
    FSampleLocations[0] := Vector2(0.25, 0.25);
    FSampleLocations[1] := Vector2(0.75, 0.75);
  end else
  if ASampleCount = 4 then
  begin
    { Standard 4x Rotated Grid Super-Sampling (RGSS / N-Rooks) }
    SetLength(FSampleLocations, 4);
    FSampleLocations[0] := Vector2(0.375, 0.125);
    FSampleLocations[1] := Vector2(0.875, 0.375);
    FSampleLocations[2] := Vector2(0.125, 0.625);
    FSampleLocations[3] := Vector2(0.625, 0.875);
  end else
  begin
    SetLength(FSampleLocations, ASampleCount);
    for I := 0 to ASampleCount - 1 do
      FSampleLocations[I] := TCastleShaderGeneratorRHI.EvaluateR2Sequence2D(I);
  end;
end;

function TCastleVulkanProgrammableSampleLocations.GetSampleLocation(
  const ASampleIndex: Cardinal): TVector2;
begin
  if ASampleIndex < Cardinal(Length(FSampleLocations)) then
    Result := FSampleLocations[ASampleIndex]
  else
    Result := Vector2(0.5, 0.5);
end;

procedure TCastleVulkanProgrammableSampleLocations.ApplySampleLocations(
  const ACommandList: TVulkanRHICommandList);
begin
  if ACommandList = nil then
    Exit;
  Inc(FLocationsAppliedCount);
end;

function TCastleVulkanProgrammableSampleLocations.GetSampleCount: Cardinal;
begin
  Result := Cardinal(Length(FSampleLocations));
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanStreamCompactor (Phase 41.3)                                    }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanStreamCompactor.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
end;

destructor TCastleVulkanStreamCompactor.Destroy;
begin
  FreeAndNil(FPrefixSumBuffer);
  FreeAndNil(FCompactedIndicesBuffer);
  FreeAndNil(FCompactedCountBuffer);
  inherited;
end;

class function TCastleVulkanStreamCompactor.EvaluatePrefixSumAndCompact(
  const APredicates: array of Boolean;
  out AExclusivePrefixSum: TCardinalDynamicArray;
  out ACompactedIndices: TCardinalDynamicArray): Cardinal;
var
  I, RunningSum: Cardinal;
begin
  SetLength(AExclusivePrefixSum, Length(APredicates));
  RunningSum := 0;
  if Length(APredicates) > 0 then
  begin
    for I := 0 to Cardinal(High(APredicates)) do
    begin
      AExclusivePrefixSum[I] := RunningSum;
      if APredicates[I] then
        Inc(RunningSum);
    end;
  end;

  SetLength(ACompactedIndices, RunningSum);
  if Length(APredicates) > 0 then
  begin
    for I := 0 to Cardinal(High(APredicates)) do
      if APredicates[I] then
        ACompactedIndices[AExclusivePrefixSum[I]] := I;
  end;
  Result := RunningSum;
end;

procedure TCastleVulkanStreamCompactor.EnsureCompactionBuffers(
  const AElementCount: Cardinal);
var
  Cap: Cardinal;
  BufDesc: TRHIBufferDesc;
begin
  if FDevice = nil then
    Exit;
  Cap := Max(Cardinal(64), AElementCount);
  if (FPrefixSumBuffer <> nil) and (FMaxElementCount >= Cap) then
    Exit;

  FreeAndNil(FPrefixSumBuffer);
  FreeAndNil(FCompactedIndicesBuffer);
  FreeAndNil(FCompactedCountBuffer);

  FMaxElementCount := Cap;

  BufDesc := TRHIBufferDesc.Create(PtrUInt(Cap) * SizeOf(Cardinal),
    [buStorage], muGpuOnly, 'StreamCompactorPrefixSumSSBO');
  FPrefixSumBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(PtrUInt(Cap) * SizeOf(Cardinal),
    [buStorage], muGpuOnly, 'StreamCompactorIndicesSSBO');
  FCompactedIndicesBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

  BufDesc := TRHIBufferDesc.Create(SizeOf(Cardinal) * 4,
    [buStorage, buIndirect], muGpuOnly, 'StreamCompactorCountSSBO');
  FCompactedCountBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
end;

procedure TCastleVulkanStreamCompactor.DispatchStreamCompaction(
  const ACommandList: TVulkanRHICommandList;
  const AElementCount: Cardinal;
  const AComputePipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  ActivePipe: TVulkanRHIComputePipeline;
  Workgroups: Cardinal;
begin
  if (ACommandList = nil) or (AElementCount = 0) then
    Exit;
  EnsureCompactionBuffers(AElementCount);

  if AComputePipeline <> nil then
    ActivePipe := AComputePipeline
  else
    ActivePipe := FCompactionComputePipeline;
  if ActivePipe <> nil then
    ACommandList.BindComputePipeline(ActivePipe);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  Workgroups := (AElementCount + 255) div 256;
  ACommandList.Dispatch(Workgroups, 1, 1);
  Inc(FCompactionDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHIDevice                                                             }
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHIDevice.Create(const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
  const InitialWidth, InitialHeight: Cardinal; const EnableValidation: Boolean);
begin
  inherited Create;
  FPipelineMap := TVulkanPipelineMap.Create([doOwnsValues]);
  FComputePipelineMap := TVulkanComputePipelineMap.Create([doOwnsValues]);
  FVertexInputLibMap := TVulkanPipelineLibraryMap.Create;
  FPreRasterLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentShaderLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentOutputLibMap := TVulkanPipelineLibraryMap.Create;
  FRenderPassMap := TVulkanRenderPassMap.Create;
  FFramebufferMap := TVulkanFramebufferMap.Create;
  FSupportsDynamicRendering := True;
  FAntiAliasing := aaNone;
  FSampleCount := 1;

  LoadVulkan;
  CreateInstance(EnableValidation);

  FSurface := ACreateSurfaceCallback(FInstance);
  if FSurface = VK_NULL_HANDLE then
    raise ERHIError.Create('Failed to create Vulkan window surface (VkSurfaceKHR)');

  PickPhysicalDevice;
  CreateLogicalDevice;
  FMemoryAllocator := TCastleVulkanMemoryAllocator.Create(FPhysicalDevice, FDevice);
  FMemoryAllocator.SupportsMemoryBudgetExt := FSupportsMemoryBudgetExt;
  FStagingUploader := TCastleVulkanStagingUploader.Create(Self);
  CreateDescriptorPool;
  if FSupportsBindlessTextures and (FMaxBindlessTextures > 0) then
    FBindlessTextureManager := TCastleVulkanBindlessTextureManager.Create(
      Self, FMaxBindlessTextures, FSupportsBindlessUpdateAfterBind);
  FTimestampProfiler := TCastleVulkanTimestampProfiler.Create(Self);
  CreateFrameContexts;
  CreateSwapchain(InitialWidth, InitialHeight);
end;

constructor TVulkanRHIDevice.CreateHeadless(const APhysicalDevice: VkPhysicalDevice;
  const ASupportsMemoryBudgetExt: Boolean;
  const ASupportsDynamicRendering: Boolean;
  const ADeviceApiVersion: Cardinal;
  const ASupportsGraphicsPipelineLibrary: Boolean;
  const ASupportsBindlessTextures: Boolean;
  const AMaxBindlessTextures: Cardinal;
  const ASupportsExtendedDynamicState: Boolean);
var
  I: Integer;
begin
  inherited Create;
  FPipelineMap := TVulkanPipelineMap.Create([doOwnsValues]);
  FComputePipelineMap := TVulkanComputePipelineMap.Create([doOwnsValues]);
  FVertexInputLibMap := TVulkanPipelineLibraryMap.Create;
  FPreRasterLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentShaderLibMap := TVulkanPipelineLibraryMap.Create;
  FFragmentOutputLibMap := TVulkanPipelineLibraryMap.Create;
  FRenderPassMap := TVulkanRenderPassMap.Create;
  FFramebufferMap := TVulkanFramebufferMap.Create;
  FAntiAliasing := aaNone;
  FSampleCount := 1;
  FCapabilities.Backend := rbVulkan;
  FCapabilities.DeviceName := 'Headless Vulkan RHI Device';
  FCapabilities.MaxTextureSize := 16384;
  FCapabilities.MaxAnisotropy := 16.0;
  FCapabilities.MaxFramebufferSampleCount := 8;
  FCapabilities.SupportsComputeShaders := True;
  FCapabilities.SupportsMultiDrawIndirect := True;
  FCapabilities.SupportsDrawIndirectCount := ADeviceApiVersion >= VK_API_VERSION_1_2;
  FCapabilities.TimestampPeriodNanoseconds := 1.0;
  FPhysicalDevice := APhysicalDevice;
  FInstanceApiVersion := ADeviceApiVersion;
  FDeviceApiVersion := ADeviceApiVersion;
  FSupportsMemoryBudgetExt := ASupportsMemoryBudgetExt;
  FSupportsDynamicRendering := ASupportsDynamicRendering;
  FSupportsGraphicsPipelineLibrary := ASupportsGraphicsPipelineLibrary;
  FSupportsGPLFastLinking := ASupportsGraphicsPipelineLibrary;
  FSupportsBindlessTextures := ASupportsBindlessTextures;
  FSupportsBindlessUpdateAfterBind := ASupportsBindlessTextures;
  FSupportsExtendedDynamicState := ASupportsExtendedDynamicState;
  FSupportsSynchronization2 := ADeviceApiVersion >= VK_API_VERSION_1_3;
  FSupportsTimelineSemaphores := ADeviceApiVersion >= VK_API_VERSION_1_2;
  FCapabilities.SupportsExtendedDynamicState := FSupportsExtendedDynamicState;
  FCapabilities.SupportsSynchronization2 := FSupportsSynchronization2;
  FCapabilities.SupportsTimelineSemaphores := FSupportsTimelineSemaphores;
  if ASupportsBindlessTextures then
    FMaxBindlessTextures := Max(Cardinal(1), AMaxBindlessTextures)
  else
    FMaxBindlessTextures := 0;
  FCapabilities.SupportsBindlessTextures := FSupportsBindlessTextures;
  FCapabilities.MaxBindlessTextures := FMaxBindlessTextures;
  FMemoryAllocator := TCastleVulkanMemoryAllocator.Create(FPhysicalDevice, FDevice);
  FMemoryAllocator.SupportsMemoryBudgetExt := FSupportsMemoryBudgetExt;
  FStagingUploader := TCastleVulkanStagingUploader.Create(Self);
  FPersistentDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(
    FDevice, 2048, True, 8192, FSupportsBindlessUpdateAfterBind);
  if FSupportsBindlessTextures and (FMaxBindlessTextures > 0) then
    FBindlessTextureManager := TCastleVulkanBindlessTextureManager.Create(
      Self, FMaxBindlessTextures, FSupportsBindlessUpdateAfterBind);
  FTimestampProfiler := TCastleVulkanTimestampProfiler.Create(Self);
  for I := 0 to MaxFramesInFlight - 1 do
    FFrames[I].TransientDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(FDevice, 512, False, 4096);
end;

procedure TVulkanRHIDevice.ClearPipelineLibraries;

  procedure DestroyMapPipelines(const AMap: TVulkanPipelineLibraryMap);
  var
    LibHandle: VkPipeline;
  begin
    if AMap = nil then Exit;
    if (FDevice <> nil) and Assigned(vkDestroyPipeline) then
    begin
      for LibHandle in AMap.Values do
        if LibHandle <> VK_NULL_HANDLE then
          vkDestroyPipeline(FDevice, LibHandle, nil);
    end;
    AMap.Clear;
  end;

begin
  DestroyMapPipelines(FVertexInputLibMap);
  DestroyMapPipelines(FPreRasterLibMap);
  DestroyMapPipelines(FFragmentShaderLibMap);
  DestroyMapPipelines(FFragmentOutputLibMap);
end;

function TVulkanRHIDevice.GetVertexInputLibraryCount: Cardinal;
begin
  if FVertexInputLibMap <> nil then
    Result := Cardinal(FVertexInputLibMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetPreRasterizationLibraryCount: Cardinal;
begin
  if FPreRasterLibMap <> nil then
    Result := Cardinal(FPreRasterLibMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetFragmentShaderLibraryCount: Cardinal;
begin
  if FFragmentShaderLibMap <> nil then
    Result := Cardinal(FFragmentShaderLibMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetFragmentOutputLibraryCount: Cardinal;
begin
  if FFragmentOutputLibMap <> nil then
    Result := Cardinal(FFragmentOutputLibMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetTotalPipelineLibraryCount: Cardinal;
begin
  Result := GetVertexInputLibraryCount + GetPreRasterizationLibraryCount +
    GetFragmentShaderLibraryCount + GetFragmentOutputLibraryCount;
end;

procedure TVulkanRHIDevice.ClearFallbackFramebuffers;
var
  FbHandle: VkFramebuffer;
begin
  if FFramebufferMap = nil then Exit;
  if (FDevice <> nil) and Assigned(vkDestroyFramebuffer) then
  begin
    for FbHandle in FFramebufferMap.Values do
      if FbHandle <> VK_NULL_HANDLE then
        vkDestroyFramebuffer(FDevice, FbHandle, nil);
  end;
  FFramebufferMap.Clear;
end;

procedure TVulkanRHIDevice.ClearFallbackRenderPasses;
var
  RpHandle: VkRenderPass;
begin
  if FRenderPassMap = nil then Exit;
  if (FDevice <> nil) and Assigned(vkDestroyRenderPass) then
  begin
    for RpHandle in FRenderPassMap.Values do
      if RpHandle <> VK_NULL_HANDLE then
        vkDestroyRenderPass(FDevice, RpHandle, nil);
  end;
  FRenderPassMap.Clear;
end;

function TVulkanRHIDevice.GetFallbackRenderPassCount: Cardinal;
begin
  if FRenderPassMap <> nil then
    Result := Cardinal(FRenderPassMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetFallbackFramebufferCount: Cardinal;
begin
  if FFramebufferMap <> nil then
    Result := Cardinal(FFramebufferMap.Count)
  else
    Result := 0;
end;

procedure TVulkanRHIDevice.DeferOrDestroyBuffer(const ABuffer: VkBuffer;
  var AAllocation: TVulkanMemoryAllocation; const ADeviceMemory: VkDeviceMemory;
  const AAllocatedSize: VkDeviceSize);
var
  Slot, Idx: Integer;
begin
  if FDeferResourceDestruction then
  begin
    Slot := FFrameIndex mod MaxFramesInFlight;
    Idx := Length(FDeferredDeletions[Slot]);
    SetLength(FDeferredDeletions[Slot], Idx + 1);
    FillChar(FDeferredDeletions[Slot][Idx], SizeOf(TVulkanDeferredDeletionItem), 0);
    FDeferredDeletions[Slot][Idx].IsTexture := False;
    FDeferredDeletions[Slot][Idx].Buffer := ABuffer;
    FDeferredDeletions[Slot][Idx].Allocation := AAllocation;
    FDeferredDeletions[Slot][Idx].DeviceMemory := ADeviceMemory;
    FDeferredDeletions[Slot][Idx].AllocatedSize := AAllocatedSize;
    Exit;
  end;

  if (ABuffer <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyBuffer) then
    vkDestroyBuffer(FDevice, ABuffer, nil);
  if AAllocation.IsValid and (FMemoryAllocator <> nil) then
  begin
    FMemoryAllocator.Free(AAllocation);
    Dec(FAllocatedMemoryBytes, AAllocatedSize);
  end else
  if (ADeviceMemory <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkFreeMemory) then
  begin
    vkFreeMemory(FDevice, ADeviceMemory, nil);
    Dec(FAllocatedMemoryBytes, AAllocatedSize);
  end;
end;

procedure TVulkanRHIDevice.DeferOrDestroyTexture(const AImage: VkImage;
  const AImageView: VkImageView; var AAllocation: TVulkanMemoryAllocation;
  const ADeviceMemory: VkDeviceMemory; const AAllocatedSize: VkDeviceSize);
var
  Slot, Idx: Integer;
begin
  if FDeferResourceDestruction then
  begin
    Slot := FFrameIndex mod MaxFramesInFlight;
    Idx := Length(FDeferredDeletions[Slot]);
    SetLength(FDeferredDeletions[Slot], Idx + 1);
    FillChar(FDeferredDeletions[Slot][Idx], SizeOf(TVulkanDeferredDeletionItem), 0);
    FDeferredDeletions[Slot][Idx].IsTexture := True;
    FDeferredDeletions[Slot][Idx].Image := AImage;
    FDeferredDeletions[Slot][Idx].ImageView := AImageView;
    FDeferredDeletions[Slot][Idx].Allocation := AAllocation;
    FDeferredDeletions[Slot][Idx].DeviceMemory := ADeviceMemory;
    FDeferredDeletions[Slot][Idx].AllocatedSize := AAllocatedSize;
    Exit;
  end;

  if (AImageView <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyImageView) then
    vkDestroyImageView(FDevice, AImageView, nil);
  if (AImage <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyImage) then
    vkDestroyImage(FDevice, AImage, nil);
  if AAllocation.IsValid and (FMemoryAllocator <> nil) then
  begin
    FMemoryAllocator.Free(AAllocation);
    Dec(FAllocatedMemoryBytes, AAllocatedSize);
  end else
  if (ADeviceMemory <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkFreeMemory) then
  begin
    vkFreeMemory(FDevice, ADeviceMemory, nil);
    Dec(FAllocatedMemoryBytes, AAllocatedSize);
  end;
end;

procedure TVulkanRHIDevice.DeferOrDestroyDescriptorSet(
  const AOwnerPool: VkDescriptorPool; const ASet: VkDescriptorSet);
var
  Slot, Idx: Integer;
begin
  if (AOwnerPool = VK_NULL_HANDLE) or (ASet = VK_NULL_HANDLE) then
    Exit;

  if FDeferResourceDestruction then
  begin
    Slot := FFrameIndex mod MaxFramesInFlight;
    Idx := Length(FDeferredDeletions[Slot]);
    SetLength(FDeferredDeletions[Slot], Idx + 1);
    FillChar(FDeferredDeletions[Slot][Idx], SizeOf(TVulkanDeferredDeletionItem), 0);
    FDeferredDeletions[Slot][Idx].IsDescriptorSet := True;
    FDeferredDeletions[Slot][Idx].DescriptorPool := AOwnerPool;
    FDeferredDeletions[Slot][Idx].DescriptorSet := ASet;
    Exit;
  end;

  if FPersistentDescriptorAllocator <> nil then
    FPersistentDescriptorAllocator.FreeDescriptorSet(AOwnerPool, ASet);
end;

procedure TVulkanRHIDevice.FlushDeferredDeletions(const AFrameSlot: Integer);
var
  I: Integer;
  Item: TVulkanDeferredDeletionItem;
begin
  if (AFrameSlot < 0) or (AFrameSlot >= MaxFramesInFlight) then
    Exit;
  for I := 0 to High(FDeferredDeletions[AFrameSlot]) do
  begin
    Item := FDeferredDeletions[AFrameSlot][I];
    if Item.IsDescriptorSet then
    begin
      if FPersistentDescriptorAllocator <> nil then
        FPersistentDescriptorAllocator.FreeDescriptorSet(Item.DescriptorPool, Item.DescriptorSet);
      Continue;
    end;

    if Item.IsTexture then
    begin
      if (Item.ImageView <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyImageView) then
        vkDestroyImageView(FDevice, Item.ImageView, nil);
      if (Item.Image <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyImage) then
        vkDestroyImage(FDevice, Item.Image, nil);
    end else
    begin
      if (Item.Buffer <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyBuffer) then
        vkDestroyBuffer(FDevice, Item.Buffer, nil);
    end;
    if Item.Allocation.IsValid and (FMemoryAllocator <> nil) then
    begin
      FMemoryAllocator.Free(Item.Allocation);
      Dec(FAllocatedMemoryBytes, Item.AllocatedSize);
    end else
    if (Item.DeviceMemory <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkFreeMemory) then
    begin
      vkFreeMemory(FDevice, Item.DeviceMemory, nil);
      Dec(FAllocatedMemoryBytes, Item.AllocatedSize);
    end;
  end;
  SetLength(FDeferredDeletions[AFrameSlot], 0);
end;

procedure TVulkanRHIDevice.FlushAllDeferredDeletions;
var
  Slot: Integer;
begin
  for Slot := 0 to MaxFramesInFlight - 1 do
    FlushDeferredDeletions(Slot);
end;

function TVulkanRHIDevice.FlushStagingUploads(
  const ACommandList: TVulkanRHICommandList): Cardinal;
begin
  if FStagingUploader <> nil then
    Result := FStagingUploader.FlushPendingUploads(ACommandList)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetPendingDeferredDeletionCount: Cardinal;
var
  Slot: Integer;
begin
  Result := 0;
  for Slot := 0 to MaxFramesInFlight - 1 do
    Inc(Result, Cardinal(Length(FDeferredDeletions[Slot])));
end;

function TVulkanRHIDevice.GetTransientDescriptorAllocator(
  const AFrameIndex: Cardinal): TVulkanDescriptorPoolAllocator;
begin
  Result := FFrames[AFrameIndex mod MaxFramesInFlight].TransientDescriptorAllocator;
end;

function TVulkanRHIDevice.CreateTransientDescriptorSet(
  const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet;
begin
  Inc(FDescriptorSetAllocations);
  Result := TVulkanRHIDescriptorSet.Create(Self, Layout as TVulkanRHIDescriptorSetLayout, True);
end;

function TVulkanRHIDevice.GetDescriptorPoolHandle: VkDescriptorPool;
begin
  if (FPersistentDescriptorAllocator <> nil) and
     (FPersistentDescriptorAllocator.CurrentPool <> VK_NULL_HANDLE) then
    Result := FPersistentDescriptorAllocator.CurrentPool
  else
    Result := FDescriptorPool;
end;

function TVulkanRHIDevice.GetComputeCuller: TCastleVulkanComputeCuller;
begin
  if FComputeCuller = nil then
    FComputeCuller := TCastleVulkanComputeCuller.Create(Self);
  Result := FComputeCuller;
end;

function TVulkanRHIDevice.GetIBLGenerator: TCastleVulkanIBLGenerator;
begin
  if FIBLGenerator = nil then
    FIBLGenerator := TCastleVulkanIBLGenerator.Create(Self);
  Result := FIBLGenerator;
end;

function TVulkanRHIDevice.GetClusteredLightCuller: TCastleVulkanClusteredLightCuller;
begin
  if FClusteredLightCuller = nil then
    FClusteredLightCuller := TCastleVulkanClusteredLightCuller.Create(Self);
  Result := FClusteredLightCuller;
end;

function TVulkanRHIDevice.GetShadowAtlas: TCastleVulkanShadowAtlas;
begin
  if FShadowAtlas = nil then
    FShadowAtlas := TCastleVulkanShadowAtlas.Create(Self);
  Result := FShadowAtlas;
end;

function TVulkanRHIDevice.GetHDRPostProcessor: TCastleVulkanHDRPostProcessor;
begin
  if FHDRPostProcessor = nil then
    FHDRPostProcessor := TCastleVulkanHDRPostProcessor.Create(Self);
  Result := FHDRPostProcessor;
end;

function TVulkanRHIDevice.GetGTAO: TCastleVulkanGTAO;
begin
  if FGTAO = nil then
    FGTAO := TCastleVulkanGTAO.Create(Self);
  Result := FGTAO;
end;

function TVulkanRHIDevice.GetSSR: TCastleVulkanSSR;
begin
  if FSSR = nil then
    FSSR := TCastleVulkanSSR.Create(Self);
  Result := FSSR;
end;

function TVulkanRHIDevice.GetVolumetricFog: TCastleVulkanVolumetricFog;
begin
  if FVolumetricFog = nil then
    FVolumetricFog := TCastleVulkanVolumetricFog.Create(Self);
  Result := FVolumetricFog;
end;

function TVulkanRHIDevice.GetTAA: TCastleVulkanTAA;
begin
  if FTAA = nil then
    FTAA := TCastleVulkanTAA.Create(Self);
  Result := FTAA;
end;

function TVulkanRHIDevice.GetReflectionProbeManager: TCastleVulkanReflectionProbeManager;
begin
  if FReflectionProbeManager = nil then
    FReflectionProbeManager := TCastleVulkanReflectionProbeManager.Create(Self);
  Result := FReflectionProbeManager;
end;

function TVulkanRHIDevice.GetDecalManager: TCastleVulkanDecalManager;
begin
  if FDecalManager = nil then
    FDecalManager := TCastleVulkanDecalManager.Create(Self);
  Result := FDecalManager;
end;

function TVulkanRHIDevice.GetComputeParticles: TCastleVulkanComputeParticles;
begin
  if FComputeParticles = nil then
    FComputeParticles := TCastleVulkanComputeParticles.Create(Self);
  Result := FComputeParticles;
end;

function TVulkanRHIDevice.GetWeightedBlendedOIT: TCastleVulkanWeightedBlendedOIT;
begin
  if FWeightedBlendedOIT = nil then
    FWeightedBlendedOIT := TCastleVulkanWeightedBlendedOIT.Create(Self);
  Result := FWeightedBlendedOIT;
end;

function TVulkanRHIDevice.GetContactShadows: TCastleVulkanContactShadows;
begin
  if FContactShadows = nil then
    FContactShadows := TCastleVulkanContactShadows.Create(Self);
  Result := FContactShadows;
end;

function TVulkanRHIDevice.GetComputeSkinner: TCastleVulkanComputeSkinner;
begin
  if FComputeSkinner = nil then
    FComputeSkinner := TCastleVulkanComputeSkinner.Create(Self);
  Result := FComputeSkinner;
end;

function TVulkanRHIDevice.GetTerrainCDLOD: TCastleVulkanTerrainCDLOD;
begin
  if FTerrainCDLOD = nil then
    FTerrainCDLOD := TCastleVulkanTerrainCDLOD.Create(Self);
  Result := FTerrainCDLOD;
end;

function TVulkanRHIDevice.GetAtmosphereRenderer: TCastleVulkanAtmosphereRenderer;
begin
  if FAtmosphereRenderer = nil then
    FAtmosphereRenderer := TCastleVulkanAtmosphereRenderer.Create(Self);
  Result := FAtmosphereRenderer;
end;

function TVulkanRHIDevice.GetOceanSimulator: TCastleVulkanOceanSimulator;
begin
  if FOceanSimulator = nil then
    FOceanSimulator := TCastleVulkanOceanSimulator.Create(Self);
  Result := FOceanSimulator;
end;

function TVulkanRHIDevice.GetDDGIGrid: TCastleVulkanDDGIGrid;
begin
  if FDDGIGrid = nil then
    FDDGIGrid := TCastleVulkanDDGIGrid.Create(Self);
  Result := FDDGIGrid;
end;

function TVulkanRHIDevice.GetMeshletCuller: TCastleVulkanMeshletCuller;
begin
  if FMeshletCuller = nil then
    FMeshletCuller := TCastleVulkanMeshletCuller.Create(Self);
  Result := FMeshletCuller;
end;

function TVulkanRHIDevice.GetVirtualShadowMap: TCastleVulkanVirtualShadowMap;
begin
  if FVirtualShadowMap = nil then
    FVirtualShadowMap := TCastleVulkanVirtualShadowMap.Create(Self);
  Result := FVirtualShadowMap;
end;

function TVulkanRHIDevice.GetLODSelector: TCastleVulkanLODSelector;
begin
  if FLODSelector = nil then
    FLODSelector := TCastleVulkanLODSelector.Create(Self);
  Result := FLODSelector;
end;

function TVulkanRHIDevice.GetTextureStreamer: TCastleVulkanTextureStreamer;
begin
  if FTextureStreamer = nil then
    FTextureStreamer := TCastleVulkanTextureStreamer.Create(Self);
  Result := FTextureStreamer;
end;

function TVulkanRHIDevice.GetShadowCasterCuller: TCastleVulkanShadowCasterCuller;
begin
  if FShadowCasterCuller = nil then
    FShadowCasterCuller := TCastleVulkanShadowCasterCuller.Create(Self);
  Result := FShadowCasterCuller;
end;

function TVulkanRHIDevice.GetClusterDAG: TCastleVulkanClusterDAG;
begin
  if FClusterDAG = nil then
    FClusterDAG := TCastleVulkanClusterDAG.Create(Self);
  Result := FClusterDAG;
end;

function TVulkanRHIDevice.GetGlobalSDF: TCastleVulkanGlobalSDF;
begin
  if FGlobalSDF = nil then
    FGlobalSDF := TCastleVulkanGlobalSDF.Create(Self);
  Result := FGlobalSDF;
end;

function TVulkanRHIDevice.GetSurfaceCache: TCastleVulkanSurfaceCache;
begin
  if FSurfaceCache = nil then
    FSurfaceCache := TCastleVulkanSurfaceCache.Create(Self);
  Result := FSurfaceCache;
end;

function TVulkanRHIDevice.GetReSTIR: TCastleVulkanReSTIR;
begin
  if FReSTIR = nil then
    FReSTIR := TCastleVulkanReSTIR.Create(Self);
  Result := FReSTIR;
end;

function TVulkanRHIDevice.GetTSRUpscaler: TCastleVulkanTSRUpscaler;
begin
  if FTSRUpscaler = nil then
    FTSRUpscaler := TCastleVulkanTSRUpscaler.Create(Self);
  Result := FTSRUpscaler;
end;

function TVulkanRHIDevice.GetVRSManager: TCastleVulkanVRSManager;
begin
  if FVRSManager = nil then
    FVRSManager := TCastleVulkanVRSManager.Create(Self);
  Result := FVRSManager;
end;

function TVulkanRHIDevice.GetRuntimeVirtualTexture: TCastleVulkanRuntimeVirtualTexture;
begin
  if FRuntimeVirtualTexture = nil then
    FRuntimeVirtualTexture := TCastleVulkanRuntimeVirtualTexture.Create(Self);
  Result := FRuntimeVirtualTexture;
end;

function TVulkanRHIDevice.GetSparseVolumeAtlas: TCastleVulkanSparseVolumeAtlas;
begin
  if FSparseVolumeAtlas = nil then
    FSparseVolumeAtlas := TCastleVulkanSparseVolumeAtlas.Create(Self);
  Result := FSparseVolumeAtlas;
end;

function TVulkanRHIDevice.GetBreadcrumbTracker: TCastleVulkanBreadcrumbTracker;
begin
  if FBreadcrumbTracker = nil then
    FBreadcrumbTracker := TCastleVulkanBreadcrumbTracker.Create(Self);
  Result := FBreadcrumbTracker;
end;

function TVulkanRHIDevice.GetSVGFDenoiser: TCastleVulkanSVGFDenoiser;
begin
  if FSVGFDenoiser = nil then
    FSVGFDenoiser := TCastleVulkanSVGFDenoiser.Create(Self);
  Result := FSVGFDenoiser;
end;

function TVulkanRHIDevice.GetShaderBindingTable: TCastleVulkanShaderBindingTable;
begin
  if FShaderBindingTable = nil then
    FShaderBindingTable := TCastleVulkanShaderBindingTable.Create(Self);
  Result := FShaderBindingTable;
end;

function TVulkanRHIDevice.GetAccelerationStructureManager: TCastleVulkanAccelerationStructureManager;
begin
  if FAccelerationStructureManager = nil then
    FAccelerationStructureManager := TCastleVulkanAccelerationStructureManager.Create(Self);
  Result := FAccelerationStructureManager;
end;

function TVulkanRHIDevice.GetXPBDSimulator: TCastleVulkanXPBDSimulator;
begin
  if FXPBDSimulator = nil then
    FXPBDSimulator := TCastleVulkanXPBDSimulator.Create(Self);
  Result := FXPBDSimulator;
end;

function TVulkanRHIDevice.GetMultiviewStereoManager: TCastleVulkanMultiviewStereoManager;
begin
  if FMultiviewStereoManager = nil then
    FMultiviewStereoManager := TCastleVulkanMultiviewStereoManager.Create(Self);
  Result := FMultiviewStereoManager;
end;

function TVulkanRHIDevice.GetPerInstanceCustomData: TCastleVulkanPerInstanceCustomData;
begin
  if FPerInstanceCustomData = nil then
    FPerInstanceCustomData := TCastleVulkanPerInstanceCustomData.Create(Self);
  Result := FPerInstanceCustomData;
end;

function TVulkanRHIDevice.GetNeuralDenoiser: TCastleVulkanNeuralDenoiser;
begin
  if FNeuralDenoiser = nil then
    FNeuralDenoiser := TCastleVulkanNeuralDenoiser.Create(Self);
  Result := FNeuralDenoiser;
end;

function TVulkanRHIDevice.GetProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations;
begin
  if FProgrammableSampleLocations = nil then
    FProgrammableSampleLocations := TCastleVulkanProgrammableSampleLocations.Create(Self);
  Result := FProgrammableSampleLocations;
end;

function TVulkanRHIDevice.GetStreamCompactor: TCastleVulkanStreamCompactor;
begin
  if FStreamCompactor = nil then
    FStreamCompactor := TCastleVulkanStreamCompactor.Create(Self);
  Result := FStreamCompactor;
end;

destructor TVulkanRHIDevice.Destroy;
var
  I: Integer;
begin
  SetActiveCommandList(nil);
  WaitIdle;
  FreeAndNil(FStreamCompactor);
  FreeAndNil(FProgrammableSampleLocations);
  FreeAndNil(FNeuralDenoiser);
  FreeAndNil(FPerInstanceCustomData);
  FreeAndNil(FMultiviewStereoManager);
  FreeAndNil(FXPBDSimulator);
  FreeAndNil(FAccelerationStructureManager);
  FreeAndNil(FShaderBindingTable);
  FreeAndNil(FSVGFDenoiser);
  FreeAndNil(FBreadcrumbTracker);
  FreeAndNil(FSparseVolumeAtlas);
  FreeAndNil(FRuntimeVirtualTexture);
  FreeAndNil(FVRSManager);
  FreeAndNil(FTSRUpscaler);
  FreeAndNil(FReSTIR);
  FreeAndNil(FSurfaceCache);
  FreeAndNil(FGlobalSDF);
  FreeAndNil(FClusterDAG);
  FreeAndNil(FShadowCasterCuller);
  FreeAndNil(FTextureStreamer);
  FreeAndNil(FLODSelector);
  FreeAndNil(FVirtualShadowMap);
  FreeAndNil(FMeshletCuller);
  FreeAndNil(FDDGIGrid);
  FreeAndNil(FOceanSimulator);
  FreeAndNil(FAtmosphereRenderer);
  FreeAndNil(FTerrainCDLOD);
  FreeAndNil(FComputeSkinner);
  FreeAndNil(FContactShadows);
  FreeAndNil(FWeightedBlendedOIT);
  FreeAndNil(FComputeParticles);
  FreeAndNil(FDecalManager);
  FreeAndNil(FReflectionProbeManager);
  FreeAndNil(FTAA);
  FreeAndNil(FVolumetricFog);
  FreeAndNil(FSSR);
  FreeAndNil(FGTAO);
  FreeAndNil(FHDRPostProcessor);
  FreeAndNil(FShadowAtlas);
  FreeAndNil(FClusteredLightCuller);
  FreeAndNil(FIBLGenerator);
  FreeAndNil(FComputeCuller);
  FreeAndNil(FTimestampProfiler);
  FreeAndNil(FBindlessTextureManager);
  FreeAndNil(FStagingUploader);
  FlushAllDeferredDeletions;
  DestroySwapchain;
  FreeAndNil(FPipelineMap);
  FreeAndNil(FComputePipelineMap);
  ClearPipelineLibraries;
  FreeAndNil(FVertexInputLibMap);
  FreeAndNil(FPreRasterLibMap);
  FreeAndNil(FFragmentShaderLibMap);
  FreeAndNil(FFragmentOutputLibMap);
  ClearFallbackFramebuffers;
  ClearFallbackRenderPasses;
  FreeAndNil(FFramebufferMap);
  FreeAndNil(FRenderPassMap);
  FreeAndNil(FPrewarm3DVertexShader);
  FreeAndNil(FPrewarm3DFragmentShader);
  FreeAndNil(FPrewarm2DVertexShader);
  FreeAndNil(FPrewarm2DFragmentShader);

  for I := 0 to MaxFramesInFlight - 1 do
  begin
    FreeAndNil(FFrames[I].CommandList);
    FreeAndNil(FFrames[I].TransientDescriptorAllocator);
    if (FDevice <> nil) and (FFrames[I].ImageAvailableSemaphore <> VK_NULL_HANDLE) then
      vkDestroySemaphore(FDevice, FFrames[I].ImageAvailableSemaphore, nil);
    if (FDevice <> nil) and (FFrames[I].RenderFinishedSemaphore <> VK_NULL_HANDLE) then
      vkDestroySemaphore(FDevice, FFrames[I].RenderFinishedSemaphore, nil);
    if (FDevice <> nil) and (FFrames[I].InFlightFence <> VK_NULL_HANDLE) then
      vkDestroyFence(FDevice, FFrames[I].InFlightFence, nil);
  end;

  FreeAndNil(FPersistentDescriptorAllocator);
  if (FDevice <> nil) and (FDescriptorPool <> VK_NULL_HANDLE) then
    vkDestroyDescriptorPool(FDevice, FDescriptorPool, nil);
  if (FDevice <> nil) and (FPipelineCache <> VK_NULL_HANDLE) then
    vkDestroyPipelineCache(FDevice, FPipelineCache, nil);
  FreeAndNil(FMemoryAllocator);
  if FDevice <> nil then
    vkDestroyDevice(FDevice, nil);
  if (FInstance <> nil) and (FSurface <> VK_NULL_HANDLE) then
    vkDestroySurfaceKHR(FInstance, FSurface, nil);
  if FInstance <> nil then
    vkDestroyInstance(FInstance, nil);

  inherited;
end;

procedure TVulkanRHIDevice.CreateInstance(const EnableValidation: Boolean);
const
  FallbackVersions: array[0..3] of Cardinal = (
    VK_API_VERSION_1_3,
    VK_API_VERSION_1_2,
    VK_API_VERSION_1_1,
    VK_API_VERSION_1_0
  );
var
  AppInfo: VkApplicationInfo;
  CreateInfo: VkInstanceCreateInfo;
  ExtNames: TAnsiStringArray;
  ExtPtrs: array of PAnsiChar;
  LayerName: PAnsiChar;
  LoaderVer: Cardinal;
  I: Integer;
  Res: VkResult;
begin
  LoaderVer := VK_API_VERSION_1_3;
  if Assigned(vkEnumerateInstanceVersion) then
  begin
    if vkEnumerateInstanceVersion(@LoaderVer) <> VK_SUCCESS then
      LoaderVer := VK_API_VERSION_1_0;
  end else
    LoaderVer := VK_API_VERSION_1_0;

  FInstanceApiVersion := NegotiateInstanceApiVersion(LoaderVer);

  FillChar(AppInfo, SizeOf(AppInfo), 0);
  AppInfo.sType := VK_STRUCTURE_TYPE_APPLICATION_INFO;
  AppInfo.pApplicationName := 'Castle Game Engine Application';
  AppInfo.applicationVersion := VK_API_VERSION_1_0;
  AppInfo.pEngineName := 'Castle Game Engine';
  AppInfo.engineVersion := FInstanceApiVersion;
  AppInfo.apiVersion := FInstanceApiVersion;

  ExtNames := GetRequiredVulkanInstanceExtensions;
  SetLength(ExtPtrs, Length(ExtNames));
  for I := 0 to High(ExtNames) do
    ExtPtrs[I] := PAnsiChar(ExtNames[I]);

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  CreateInfo.pApplicationInfo := @AppInfo;
  CreateInfo.enabledExtensionCount := Length(ExtPtrs);
  if Length(ExtPtrs) > 0 then
    CreateInfo.ppEnabledExtensionNames := @ExtPtrs[0];

  LayerName := VK_LAYER_KHRONOS_validation;
  if EnableValidation then
  begin
    CreateInfo.enabledLayerCount := 1;
    CreateInfo.ppEnabledLayerNames := @LayerName;
  end;

  Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
  if (Res = VK_ERROR_LAYER_NOT_PRESENT) and EnableValidation then
  begin
    CreateInfo.enabledLayerCount := 0;
    CreateInfo.ppEnabledLayerNames := nil;
    Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
  end;

  { Step down apiVersion if older Vulkan 1.1/1.2 loader rejects higher version }
  if Res = VK_ERROR_INCOMPATIBLE_DRIVER then
  begin
    for I := Low(FallbackVersions) to High(FallbackVersions) do
      if FallbackVersions[I] < AppInfo.apiVersion then
      begin
        AppInfo.apiVersion := FallbackVersions[I];
        FInstanceApiVersion := AppInfo.apiVersion;
        Res := vkCreateInstance(@CreateInfo, nil, @FInstance);
        if Res = VK_SUCCESS then
          Break;
      end;
  end;

  CheckVk(Res, 'vkCreateInstance');
  LoadVulkanInstance(FInstance);
end;

procedure TVulkanRHIDevice.PickPhysicalDevice;
var
  DeviceCount, I: Cardinal;
  Devices: array of VkPhysicalDevice;
  Props, ChosenProps: VkPhysicalDeviceProperties;
  Features: VkPhysicalDeviceFeatures;
  Features2: VkPhysicalDeviceFeatures2;
  GplFeatures: VkPhysicalDeviceGraphicsPipelineLibraryFeaturesEXT;
  DescIdxFeatures: VkPhysicalDeviceDescriptorIndexingFeatures;
  ExtDynFeatures: VkPhysicalDeviceExtendedDynamicStateFeaturesEXT;
  Sync2Features: VkPhysicalDeviceSynchronization2Features;
  TimelineFeatures: VkPhysicalDeviceTimelineSemaphoreFeatures;
  Props2: VkPhysicalDeviceProperties2;
  GplProps: VkPhysicalDeviceGraphicsPipelineLibraryPropertiesEXT;
  DescIdxProps: VkPhysicalDeviceDescriptorIndexingProperties;
  HasGplFeature, HasExtDynFeature, HasSync2Feature, HasTimelineFeature: Boolean;
  ReqDynRenderExts, ReqGplExts, ReqBindlessExts, ReqExtDynSync2Exts: TAnsiStringArray;
begin
  DeviceCount := 0;
  CheckVk(vkEnumeratePhysicalDevices(FInstance, @DeviceCount, nil), 'vkEnumeratePhysicalDevices(count)');
  if DeviceCount = 0 then
    raise ERHIError.Create('No Vulkan physical devices found');

  SetLength(Devices, DeviceCount);
  CheckVk(vkEnumeratePhysicalDevices(FInstance, @DeviceCount, @Devices[0]), 'vkEnumeratePhysicalDevices');

  { Prefer discrete GPU meeting Vulkan 1.1+ baseline, otherwise any Vulkan 1.1+ GPU }
  FPhysicalDevice := Devices[0];
  for I := 0 to DeviceCount - 1 do
  begin
    vkGetPhysicalDeviceProperties(Devices[I], @Props);
    if (Props.deviceType = VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) and
       (Props.apiVersion >= VK_API_VERSION_1_1) then
    begin
      FPhysicalDevice := Devices[I];
      Break;
    end;
    if Props.apiVersion >= VK_API_VERSION_1_1 then
      FPhysicalDevice := Devices[I];
  end;

  vkGetPhysicalDeviceProperties(FPhysicalDevice, @ChosenProps);
  vkGetPhysicalDeviceFeatures(FPhysicalDevice, @Features);

  FDeviceId := ChosenProps.deviceID;
  FDeviceApiVersion := ChosenProps.apiVersion;

  ResolveVulkan11_12DeviceConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_dynamic_rendering),
    IsDeviceExtensionSupported(VK_KHR_depth_stencil_resolve),
    IsDeviceExtensionSupported(VK_KHR_create_renderpass2),
    FSupportsDynamicRendering,
    ReqDynRenderExts);

  HasGplFeature := False;
  FSupportsGPLFastLinking := False;
  if IsDeviceExtensionSupported(VK_KHR_pipeline_library) and
     IsDeviceExtensionSupported(VK_EXT_graphics_pipeline_library) and
     Assigned(vkGetPhysicalDeviceFeatures2) then
  begin
    FillChar(GplFeatures, SizeOf(GplFeatures), 0);
    GplFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT;
    FillChar(Features2, SizeOf(Features2), 0);
    Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    Features2.pNext := @GplFeatures;
    vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
    HasGplFeature := GplFeatures.graphicsPipelineLibrary = VK_TRUE;

    if HasGplFeature and Assigned(vkGetPhysicalDeviceProperties2) then
    begin
      FillChar(GplProps, SizeOf(GplProps), 0);
      GplProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_PROPERTIES_EXT;
      FillChar(Props2, SizeOf(Props2), 0);
      Props2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
      Props2.pNext := @GplProps;
      vkGetPhysicalDeviceProperties2(FPhysicalDevice, @Props2);
      FSupportsGPLFastLinking := GplProps.graphicsPipelineLibraryFastLinking = VK_TRUE;
    end;
  end;

  ResolveGraphicsPipelineLibraryConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_pipeline_library),
    IsDeviceExtensionSupported(VK_EXT_graphics_pipeline_library),
    HasGplFeature,
    FSupportsGraphicsPipelineLibrary,
    ReqGplExts);

  FillChar(DescIdxFeatures, SizeOf(DescIdxFeatures), 0);
  DescIdxFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES;
  FillChar(DescIdxProps, SizeOf(DescIdxProps), 0);
  DescIdxProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES;

  if ((FDeviceApiVersion >= VK_API_VERSION_1_2) or IsDeviceExtensionSupported(VK_EXT_descriptor_indexing)) and
     Assigned(vkGetPhysicalDeviceFeatures2) then
  begin
    FillChar(Features2, SizeOf(Features2), 0);
    Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    Features2.pNext := @DescIdxFeatures;
    vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);

    if Assigned(vkGetPhysicalDeviceProperties2) then
    begin
      FillChar(Props2, SizeOf(Props2), 0);
      Props2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
      Props2.pNext := @DescIdxProps;
      vkGetPhysicalDeviceProperties2(FPhysicalDevice, @Props2);
    end;
  end;

  ResolveDescriptorIndexingConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_EXT_descriptor_indexing),
    IsDeviceExtensionSupported(VK_KHR_maintenance3),
    DescIdxFeatures,
    DescIdxProps,
    4096,
    FSupportsBindlessTextures,
    FSupportsBindlessUpdateAfterBind,
    FMaxBindlessTextures,
    ReqBindlessExts);

  HasExtDynFeature := False;
  HasSync2Feature := False;
  HasTimelineFeature := False;
  if Assigned(vkGetPhysicalDeviceFeatures2) then
  begin
    if (FDeviceApiVersion >= VK_API_VERSION_1_3) or IsDeviceExtensionSupported(VK_EXT_extended_dynamic_state) then
    begin
      FillChar(ExtDynFeatures, SizeOf(ExtDynFeatures), 0);
      ExtDynFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @ExtDynFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      HasExtDynFeature := ExtDynFeatures.extendedDynamicState = VK_TRUE;
    end;
    if (FDeviceApiVersion >= VK_API_VERSION_1_3) or IsDeviceExtensionSupported(VK_KHR_synchronization2) then
    begin
      FillChar(Sync2Features, SizeOf(Sync2Features), 0);
      Sync2Features.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @Sync2Features;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      HasSync2Feature := Sync2Features.synchronization2 = VK_TRUE;
    end;
    if (FDeviceApiVersion >= VK_API_VERSION_1_2) or IsDeviceExtensionSupported(VK_KHR_timeline_semaphore) then
    begin
      FillChar(TimelineFeatures, SizeOf(TimelineFeatures), 0);
      TimelineFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES;
      FillChar(Features2, SizeOf(Features2), 0);
      Features2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      Features2.pNext := @TimelineFeatures;
      vkGetPhysicalDeviceFeatures2(FPhysicalDevice, @Features2);
      HasTimelineFeature := TimelineFeatures.timelineSemaphore = VK_TRUE;
    end;
  end;

  ResolveExtendedDynamicStateAndSync2Config(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_EXT_extended_dynamic_state),
    IsDeviceExtensionSupported(VK_KHR_synchronization2),
    IsDeviceExtensionSupported(VK_KHR_timeline_semaphore),
    HasExtDynFeature,
    HasSync2Feature,
    HasTimelineFeature,
    FSupportsExtendedDynamicState,
    FSupportsSynchronization2,
    FSupportsTimelineSemaphores,
    ReqExtDynSync2Exts);

  WritelnLog('Vulkan', Format('Selected GPU "%s" (Vulkan %d.%d.%d, DynamicRendering=%s, GPL=%s, Bindless=%s[max=%d], ExtDynState=%s, Sync2=%s, TimelineSem=%s)', [
    String(PAnsiChar(@ChosenProps.deviceName[0])),
    VK_VERSION_MAJOR(FDeviceApiVersion),
    VK_VERSION_MINOR(FDeviceApiVersion),
    VK_VERSION_PATCH(FDeviceApiVersion),
    BoolToStr(FSupportsDynamicRendering, True),
    BoolToStr(FSupportsGraphicsPipelineLibrary, True),
    BoolToStr(FSupportsBindlessTextures, True),
    FMaxBindlessTextures,
    BoolToStr(FSupportsExtendedDynamicState, True),
    BoolToStr(FSupportsSynchronization2, True),
    BoolToStr(FSupportsTimelineSemaphores, True)
  ]));

  FCapabilities.Backend := rbVulkan;
  FCapabilities.DeviceName := String(PAnsiChar(@ChosenProps.deviceName[0]));
  FCapabilities.VendorId := ChosenProps.vendorID;
  FCapabilities.MaxTextureSize := ChosenProps.limits.maxImageDimension2D;
  FCapabilities.MaxAnisotropy := ChosenProps.limits.maxSamplerAnisotropy;
  FCapabilities.MaxUniformBufferRange := ChosenProps.limits.maxUniformBufferRange;
  FCapabilities.MinUniformBufferOffsetAlignment := Cardinal(ChosenProps.limits.minUniformBufferOffsetAlignment);
  FCapabilities.MaxPushConstantsSize := ChosenProps.limits.maxPushConstantsSize;
  FCapabilities.MaxFramebufferSampleCount := ResolveMaxFramebufferSampleCount(
    ChosenProps.limits.framebufferColorSampleCounts,
    ChosenProps.limits.framebufferDepthSampleCounts);
  FCapabilities.TimestampPeriodNanoseconds := ChosenProps.limits.timestampPeriod;
  FCapabilities.SupportsBCCompression := Features.textureCompressionBC = VK_TRUE;
  FCapabilities.SupportsASTCCompression := Features.textureCompressionASTC_LDR = VK_TRUE;
  FCapabilities.SupportsETC2Compression := Features.textureCompressionETC2 = VK_TRUE;
  FCapabilities.SupportsComputeShaders := True;
  FCapabilities.SupportsMultiDrawIndirect := Features.multiDrawIndirect = VK_TRUE;
  FCapabilities.SupportsDrawIndirectCount :=
    (FDeviceApiVersion >= VK_API_VERSION_1_2) or
    IsDeviceExtensionSupported(VK_KHR_draw_indirect_count);
  FCapabilities.SupportsBindlessTextures := FSupportsBindlessTextures;
  FCapabilities.MaxBindlessTextures := FMaxBindlessTextures;
  FCapabilities.SupportsExtendedDynamicState := FSupportsExtendedDynamicState;
  FCapabilities.SupportsSynchronization2 := FSupportsSynchronization2;
  FCapabilities.SupportsTimelineSemaphores := FSupportsTimelineSemaphores;
end;

function TVulkanRHIDevice.IsDeviceExtensionSupported(const AExtensionName: AnsiString): Boolean;
var
  ExtCount, I: Cardinal;
  Exts: array of VkExtensionProperties;
  ExtStr: AnsiString;
begin
  Result := False;
  if (FPhysicalDevice = nil) or not Assigned(vkEnumerateDeviceExtensionProperties) then
    Exit;
  ExtCount := 0;
  if vkEnumerateDeviceExtensionProperties(FPhysicalDevice, nil, @ExtCount, nil) <> VK_SUCCESS then
    Exit;
  if ExtCount = 0 then
    Exit;
  SetLength(Exts, ExtCount);
  if vkEnumerateDeviceExtensionProperties(FPhysicalDevice, nil, @ExtCount, @Exts[0]) <> VK_SUCCESS then
    Exit;
  for I := 0 to ExtCount - 1 do
  begin
    ExtStr := PAnsiChar(@Exts[I].extensionName[0]);
    if ExtStr = AExtensionName then
      Exit(True);
  end;
end;

procedure TVulkanRHIDevice.CreateLogicalDevice;
var
  QueueCount, QueueInfoCount, I, ExtCount: Cardinal;
  QueueProps: array of VkQueueFamilyProperties;
  PresentSupport: VkBool32;
  QueueInfos: array[0..2] of VkDeviceQueueCreateInfo;
  QueuePriority: Single;
  DynRenderFeatures: VkPhysicalDeviceDynamicRenderingFeatures;
  GplFeatures: VkPhysicalDeviceGraphicsPipelineLibraryFeaturesEXT;
  DescIdxFeatures: VkPhysicalDeviceDescriptorIndexingFeatures;
  DescIdxProps: VkPhysicalDeviceDescriptorIndexingProperties;
  ExtDynFeatures: VkPhysicalDeviceExtendedDynamicStateFeaturesEXT;
  Sync2Features: VkPhysicalDeviceSynchronization2Features;
  TimelineFeatures: VkPhysicalDeviceTimelineSemaphoreFeatures;
  ReqDynRenderExts, ReqGplExts, ReqBindlessExts, ReqExtDynSync2Exts: TAnsiStringArray;
  DeviceExts: array[0..23] of PAnsiChar;
  CreateInfo: VkDeviceCreateInfo;
  CacheInfo: VkPipelineCacheCreateInfo;
  NextChainHead: Pointer;
begin
  QueueCount := 0;
  vkGetPhysicalDeviceQueueFamilyProperties(FPhysicalDevice, @QueueCount, nil);
  SetLength(QueueProps, QueueCount);
  vkGetPhysicalDeviceQueueFamilyProperties(FPhysicalDevice, @QueueCount, @QueueProps[0]);

  FGraphicsQueueFamily := 0;
  FPresentQueueFamily := 0;
  for I := 0 to QueueCount - 1 do
  begin
    if (QueueProps[I].queueFlags and VK_QUEUE_GRAPHICS_BIT) <> 0 then
      FGraphicsQueueFamily := I;
    if (FSurface <> VK_NULL_HANDLE) and Assigned(vkGetPhysicalDeviceSurfaceSupportKHR) then
    begin
      PresentSupport := VK_FALSE;
      if vkGetPhysicalDeviceSurfaceSupportKHR(FPhysicalDevice, I, FSurface, @PresentSupport) = VK_SUCCESS then
        if PresentSupport = VK_TRUE then
          FPresentQueueFamily := I;
    end else
      FPresentQueueFamily := FGraphicsQueueFamily;
  end;
  FTransferQueueFamily := SelectTransferQueueFamilyIndex(QueueProps, FGraphicsQueueFamily, FHasDedicatedTransferQueue);

  QueuePriority := 1.0;
  FillChar(QueueInfos, SizeOf(QueueInfos), 0);
  QueueInfos[0].sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
  QueueInfos[0].queueFamilyIndex := FGraphicsQueueFamily;
  QueueInfos[0].queueCount := 1;
  QueueInfos[0].pQueuePriorities := @QueuePriority;
  QueueInfoCount := 1;

  FillChar(DynRenderFeatures, SizeOf(DynRenderFeatures), 0);
  DynRenderFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR;
  DynRenderFeatures.dynamicRendering := VK_TRUE;

  FillChar(GplFeatures, SizeOf(GplFeatures), 0);
  GplFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT;
  GplFeatures.graphicsPipelineLibrary := VK_TRUE;

  FillChar(DescIdxFeatures, SizeOf(DescIdxFeatures), 0);
  DescIdxFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES;
  if FSupportsBindlessTextures then
  begin
    DescIdxFeatures.shaderSampledImageArrayNonUniformIndexing := VK_TRUE;
    DescIdxFeatures.descriptorBindingPartiallyBound := VK_TRUE;
    DescIdxFeatures.descriptorBindingUpdateUnusedWhilePending := VK_TRUE;
    DescIdxFeatures.runtimeDescriptorArray := VK_TRUE;
    if FSupportsBindlessUpdateAfterBind then
      DescIdxFeatures.descriptorBindingSampledImageUpdateAfterBind := VK_TRUE;
  end;
  FillChar(DescIdxProps, SizeOf(DescIdxProps), 0);
  DescIdxProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES;

  FillChar(ExtDynFeatures, SizeOf(ExtDynFeatures), 0);
  ExtDynFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT;
  ExtDynFeatures.extendedDynamicState := VK_TRUE;

  FillChar(Sync2Features, SizeOf(Sync2Features), 0);
  Sync2Features.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES;
  Sync2Features.synchronization2 := VK_TRUE;

  FillChar(TimelineFeatures, SizeOf(TimelineFeatures), 0);
  TimelineFeatures.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES;
  TimelineFeatures.timelineSemaphore := VK_TRUE;

  DeviceExts[0] := VK_KHR_swapchain;
  ExtCount := 1;
  FSupportsMemoryBudgetExt := IsDeviceExtensionSupported(VK_EXT_memory_budget);
  if FSupportsMemoryBudgetExt then
  begin
    if (FDeviceApiVersion < VK_API_VERSION_1_1) and
       IsDeviceExtensionSupported(VK_KHR_get_physical_device_properties2) then
    begin
      DeviceExts[ExtCount] := VK_KHR_get_physical_device_properties2;
      Inc(ExtCount);
    end;
    DeviceExts[ExtCount] := VK_EXT_memory_budget;
    Inc(ExtCount);
  end;

  ResolveVulkan11_12DeviceConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_dynamic_rendering),
    IsDeviceExtensionSupported(VK_KHR_depth_stencil_resolve),
    IsDeviceExtensionSupported(VK_KHR_create_renderpass2),
    FSupportsDynamicRendering,
    ReqDynRenderExts);

  for I := 0 to High(ReqDynRenderExts) do
  begin
    DeviceExts[ExtCount] := PAnsiChar(ReqDynRenderExts[I]);
    Inc(ExtCount);
  end;

  ResolveGraphicsPipelineLibraryConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_KHR_pipeline_library),
    IsDeviceExtensionSupported(VK_EXT_graphics_pipeline_library),
    FSupportsGraphicsPipelineLibrary,
    FSupportsGraphicsPipelineLibrary,
    ReqGplExts);

  for I := 0 to High(ReqGplExts) do
  begin
    DeviceExts[ExtCount] := PAnsiChar(ReqGplExts[I]);
    Inc(ExtCount);
  end;

  ResolveDescriptorIndexingConfig(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_EXT_descriptor_indexing),
    IsDeviceExtensionSupported(VK_KHR_maintenance3),
    DescIdxFeatures,
    DescIdxProps,
    FMaxBindlessTextures,
    FSupportsBindlessTextures,
    FSupportsBindlessUpdateAfterBind,
    FMaxBindlessTextures,
    ReqBindlessExts);

  for I := 0 to High(ReqBindlessExts) do
  begin
    DeviceExts[ExtCount] := PAnsiChar(ReqBindlessExts[I]);
    Inc(ExtCount);
  end;

  ResolveExtendedDynamicStateAndSync2Config(
    FDeviceApiVersion,
    IsDeviceExtensionSupported(VK_EXT_extended_dynamic_state),
    IsDeviceExtensionSupported(VK_KHR_synchronization2),
    IsDeviceExtensionSupported(VK_KHR_timeline_semaphore),
    FSupportsExtendedDynamicState,
    FSupportsSynchronization2,
    FSupportsTimelineSemaphores,
    FSupportsExtendedDynamicState,
    FSupportsSynchronization2,
    FSupportsTimelineSemaphores,
    ReqExtDynSync2Exts);

  for I := 0 to High(ReqExtDynSync2Exts) do
  begin
    DeviceExts[ExtCount] := PAnsiChar(ReqExtDynSync2Exts[I]);
    Inc(ExtCount);
  end;

  NextChainHead := nil;
  if FSupportsTimelineSemaphores then
  begin
    TimelineFeatures.pNext := NextChainHead;
    NextChainHead := @TimelineFeatures;
  end;
  if FSupportsSynchronization2 then
  begin
    Sync2Features.pNext := NextChainHead;
    NextChainHead := @Sync2Features;
  end;
  if FSupportsExtendedDynamicState then
  begin
    ExtDynFeatures.pNext := NextChainHead;
    NextChainHead := @ExtDynFeatures;
  end;
  if FSupportsBindlessTextures then
  begin
    DescIdxFeatures.pNext := NextChainHead;
    NextChainHead := @DescIdxFeatures;
  end;
  if FSupportsGraphicsPipelineLibrary then
  begin
    GplFeatures.pNext := NextChainHead;
    NextChainHead := @GplFeatures;
  end;
  if FSupportsDynamicRendering then
  begin
    DynRenderFeatures.pNext := NextChainHead;
    NextChainHead := @DynRenderFeatures;
  end else
  begin
    WritelnLog('Vulkan', Format('Device (Vulkan %d.%d) does not support VK_KHR_dynamic_rendering; using Vulkan 1.1/1.2 VkRenderPass / VkFramebuffer fallback.', [
      VK_VERSION_MAJOR(FDeviceApiVersion),
      VK_VERSION_MINOR(FDeviceApiVersion)
    ]));
  end;

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
  CreateInfo.pNext := NextChainHead;
  if FPresentQueueFamily <> FGraphicsQueueFamily then
  begin
    QueueInfos[QueueInfoCount].sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    QueueInfos[QueueInfoCount].queueFamilyIndex := FPresentQueueFamily;
    QueueInfos[QueueInfoCount].queueCount := 1;
    QueueInfos[QueueInfoCount].pQueuePriorities := @QueuePriority;
    Inc(QueueInfoCount);
  end;
  if (FTransferQueueFamily <> FGraphicsQueueFamily) and
     (FTransferQueueFamily <> FPresentQueueFamily) then
  begin
    QueueInfos[QueueInfoCount].sType := VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    QueueInfos[QueueInfoCount].queueFamilyIndex := FTransferQueueFamily;
    QueueInfos[QueueInfoCount].queueCount := 1;
    QueueInfos[QueueInfoCount].pQueuePriorities := @QueuePriority;
    Inc(QueueInfoCount);
  end;
  CreateInfo.queueCreateInfoCount := QueueInfoCount;
  CreateInfo.pQueueCreateInfos := @QueueInfos[0];
  CreateInfo.enabledExtensionCount := ExtCount;
  CreateInfo.ppEnabledExtensionNames := @DeviceExts[0];

  CheckVk(vkCreateDevice(FPhysicalDevice, @CreateInfo, nil, @FDevice), 'vkCreateDevice');
  LoadVulkanDevice(FDevice);

  vkGetDeviceQueue(FDevice, FGraphicsQueueFamily, 0, @FGraphicsQueue);
  vkGetDeviceQueue(FDevice, FPresentQueueFamily, 0, @FPresentQueue);
  vkGetDeviceQueue(FDevice, FTransferQueueFamily, 0, @FTransferQueue);

  if Assigned(vkCreatePipelineCache) then
  begin
    FillChar(CacheInfo, SizeOf(CacheInfo), 0);
    CacheInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;
    CheckVk(vkCreatePipelineCache(FDevice, @CacheInfo, nil, @FPipelineCache), 'vkCreatePipelineCache');
  end;
end;

function TVulkanRHIDevice.GetOrCreateVertexInputLibrary(
  const ADesc: TRHIGraphicsPipelineDesc): VkPipeline;
var
  KeyHash: UInt64;
  VertexBindings: array of VkVertexInputBindingDescription;
  VertexAttrs: array of VkVertexInputAttributeDescription;
  VertexInputInfo: VkPipelineVertexInputStateCreateInfo;
  InputAssembly: VkPipelineInputAssemblyStateCreateInfo;
  GplInfo: VkGraphicsPipelineLibraryCreateInfoEXT;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
  I: Integer;
begin
  KeyHash := ComputeVertexInputLibraryKeyHash(ADesc);
  if (FVertexInputLibMap <> nil) and FVertexInputLibMap.TryGetValue(KeyHash, Result) then
  begin
    Inc(FGPLLibraryCacheHits);
    Exit;
  end;
  Inc(FGPLLibraryCacheMisses);

  SetLength(VertexBindings, Length(ADesc.VertexInput.Bindings));
  for I := 0 to High(ADesc.VertexInput.Bindings) do
  begin
    VertexBindings[I].binding := ADesc.VertexInput.Bindings[I].Binding;
    VertexBindings[I].stride := ADesc.VertexInput.Bindings[I].Stride;
    if ADesc.VertexInput.Bindings[I].PerInstance then
      VertexBindings[I].inputRate := VK_VERTEX_INPUT_RATE_INSTANCE
    else
      VertexBindings[I].inputRate := VK_VERTEX_INPUT_RATE_VERTEX;
  end;

  SetLength(VertexAttrs, Length(ADesc.VertexInput.Attributes));
  for I := 0 to High(ADesc.VertexInput.Attributes) do
  begin
    VertexAttrs[I].location := ADesc.VertexInput.Attributes[I].Location;
    VertexAttrs[I].binding := ADesc.VertexInput.Attributes[I].Binding;
    VertexAttrs[I].format := RHIToVkVertexFormat(ADesc.VertexInput.Attributes[I].Format);
    VertexAttrs[I].offset := ADesc.VertexInput.Attributes[I].Offset;
  end;

  FillChar(VertexInputInfo, SizeOf(VertexInputInfo), 0);
  VertexInputInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
  VertexInputInfo.vertexBindingDescriptionCount := Length(VertexBindings);
  if Length(VertexBindings) > 0 then
    VertexInputInfo.pVertexBindingDescriptions := @VertexBindings[0];
  VertexInputInfo.vertexAttributeDescriptionCount := Length(VertexAttrs);
  if Length(VertexAttrs) > 0 then
    VertexInputInfo.pVertexAttributeDescriptions := @VertexAttrs[0];

  FillChar(InputAssembly, SizeOf(InputAssembly), 0);
  InputAssembly.sType := VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
  InputAssembly.topology := RHIToVkTopology(ADesc.Topology);
  InputAssembly.primitiveRestartEnable := VK_FALSE;

  FillChar(GplInfo, SizeOf(GplInfo), 0);
  GplInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT;
  GplInfo.flags := VK_GRAPHICS_PIPELINE_LIBRARY_VERTEX_INPUT_INTERFACE_BIT_EXT;

  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PipelineInfo.pNext := @GplInfo;
  PipelineInfo.flags := VK_PIPELINE_CREATE_LIBRARY_BIT_KHR or
    VK_PIPELINE_CREATE_RETAIN_LINK_TIME_OPTIMIZATION_INFO_BIT_EXT;
  PipelineInfo.pVertexInputState := @VertexInputInfo;
  PipelineInfo.pInputAssemblyState := @InputAssembly;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateGraphicsPipelines) then
    CheckVk(vkCreateGraphicsPipelines(FDevice, FPipelineCache, 1, @PipelineInfo, nil, @Result),
      'vkCreateGraphicsPipelines(VertexInputLibrary)')
  else
  if FVertexInputLibMap <> nil then
    Result := VkPipeline($10000000 + Cardinal(FVertexInputLibMap.Count) + 1);

  if FVertexInputLibMap <> nil then
    FVertexInputLibMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreatePreRasterizationLibrary(
  const ADesc: TRHIGraphicsPipelineDesc;
  const ALayout: VkPipelineLayout;
  const ARenderPass: VkRenderPass): VkPipeline;
var
  KeyHash: UInt64;
  Stages: array[0..1] of VkPipelineShaderStageCreateInfo;
  StageCount: Cardinal;
  ViewportState: VkPipelineViewportStateCreateInfo;
  Rasterizer: VkPipelineRasterizationStateCreateInfo;
  DynamicStates: array[0..2] of VkDynamicState;
  DynamicStateInfo: VkPipelineDynamicStateCreateInfo;
  RenderingInfo: VkPipelineRenderingCreateInfoKHR;
  GplInfo: VkGraphicsPipelineLibraryCreateInfoEXT;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
begin
  KeyHash := ComputePreRasterizationLibraryKeyHash(ADesc);
  if (FPreRasterLibMap <> nil) and FPreRasterLibMap.TryGetValue(KeyHash, Result) then
  begin
    Inc(FGPLLibraryCacheHits);
    Exit;
  end;
  Inc(FGPLLibraryCacheMisses);

  StageCount := 0;
  FillChar(Stages, SizeOf(Stages), 0);
  if (ADesc.VertexShader <> nil) and ((ADesc.VertexShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_VERTEX_BIT;
    Stages[StageCount].module := (ADesc.VertexShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;
  if (ADesc.GeometryShader <> nil) and ((ADesc.GeometryShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stages[StageCount].stage := VK_SHADER_STAGE_GEOMETRY_BIT;
    Stages[StageCount].module := (ADesc.GeometryShader as TVulkanRHIShaderModule).Handle;
    Stages[StageCount].pName := 'main';
    Inc(StageCount);
  end;

  FillChar(ViewportState, SizeOf(ViewportState), 0);
  ViewportState.sType := VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  ViewportState.viewportCount := 1;
  ViewportState.scissorCount := 1;

  FillChar(Rasterizer, SizeOf(Rasterizer), 0);
  Rasterizer.sType := VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  Rasterizer.depthClampEnable := Ord(ADesc.Rasterizer.DepthClampEnable);
  Rasterizer.rasterizerDiscardEnable := VK_FALSE;
  Rasterizer.polygonMode := RHIToVkPolygonMode(ADesc.Rasterizer.PolygonMode);
  Rasterizer.cullMode := RHIToVkCullMode(ADesc.Rasterizer.CullMode);
  Rasterizer.frontFace := RHIToVkFrontFace(ADesc.Rasterizer.FrontFace);
  Rasterizer.depthBiasEnable := Ord(ADesc.Rasterizer.DepthBiasEnable);
  Rasterizer.lineWidth := 1.0;

  DynamicStates[0] := VK_DYNAMIC_STATE_VIEWPORT;
  DynamicStates[1] := VK_DYNAMIC_STATE_SCISSOR;
  DynamicStates[2] := VK_DYNAMIC_STATE_DEPTH_BIAS;
  FillChar(DynamicStateInfo, SizeOf(DynamicStateInfo), 0);
  DynamicStateInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  if ADesc.Rasterizer.DepthBiasEnable then
    DynamicStateInfo.dynamicStateCount := 3
  else
    DynamicStateInfo.dynamicStateCount := 2;
  DynamicStateInfo.pDynamicStates := @DynamicStates[0];

  FillChar(RenderingInfo, SizeOf(RenderingInfo), 0);
  RenderingInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;

  FillChar(GplInfo, SizeOf(GplInfo), 0);
  GplInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT;
  GplInfo.flags := VK_GRAPHICS_PIPELINE_LIBRARY_PRE_RASTERIZATION_SHADERS_BIT_EXT;
  if FSupportsDynamicRendering then
    GplInfo.pNext := @RenderingInfo;

  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PipelineInfo.pNext := @GplInfo;
  PipelineInfo.flags := VK_PIPELINE_CREATE_LIBRARY_BIT_KHR or
    VK_PIPELINE_CREATE_RETAIN_LINK_TIME_OPTIMIZATION_INFO_BIT_EXT;
  PipelineInfo.stageCount := StageCount;
  if StageCount > 0 then
    PipelineInfo.pStages := @Stages[0];
  PipelineInfo.pViewportState := @ViewportState;
  PipelineInfo.pRasterizationState := @Rasterizer;
  PipelineInfo.pDynamicState := @DynamicStateInfo;
  PipelineInfo.layout := ALayout;
  if not FSupportsDynamicRendering then
    PipelineInfo.renderPass := ARenderPass;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateGraphicsPipelines) and (StageCount > 0) then
    CheckVk(vkCreateGraphicsPipelines(FDevice, FPipelineCache, 1, @PipelineInfo, nil, @Result),
      'vkCreateGraphicsPipelines(PreRasterizationLibrary)')
  else
  if (FDevice = nil) and (FPreRasterLibMap <> nil) then
    Result := VkPipeline($20000000 + Cardinal(FPreRasterLibMap.Count) + 1);

  if FPreRasterLibMap <> nil then
    FPreRasterLibMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreateFragmentShaderLibrary(
  const ADesc: TRHIGraphicsPipelineDesc;
  const ALayout: VkPipelineLayout;
  const ARenderPass: VkRenderPass): VkPipeline;
var
  KeyHash: UInt64;
  Stage: VkPipelineShaderStageCreateInfo;
  StageCount: Cardinal;
  DepthStencil: VkPipelineDepthStencilStateCreateInfo;
  Multisampling: VkPipelineMultisampleStateCreateInfo;
  RenderingInfo: VkPipelineRenderingCreateInfoKHR;
  GplInfo: VkGraphicsPipelineLibraryCreateInfoEXT;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
begin
  KeyHash := ComputeFragmentShaderLibraryKeyHash(ADesc);
  if (FFragmentShaderLibMap <> nil) and FFragmentShaderLibMap.TryGetValue(KeyHash, Result) then
  begin
    Inc(FGPLLibraryCacheHits);
    Exit;
  end;
  Inc(FGPLLibraryCacheMisses);

  StageCount := 0;
  FillChar(Stage, SizeOf(Stage), 0);
  if (ADesc.FragmentShader <> nil) and ((ADesc.FragmentShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
  begin
    Stage.sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    Stage.stage := VK_SHADER_STAGE_FRAGMENT_BIT;
    Stage.module := (ADesc.FragmentShader as TVulkanRHIShaderModule).Handle;
    Stage.pName := 'main';
    StageCount := 1;
  end;

  FillChar(DepthStencil, SizeOf(DepthStencil), 0);
  DepthStencil.sType := VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
  DepthStencil.depthTestEnable := Ord(ADesc.DepthStencil.DepthTestEnable);
  DepthStencil.depthWriteEnable := Ord(ADesc.DepthStencil.DepthWriteEnable);
  DepthStencil.depthCompareOp := RHIToVkCompareOp(ADesc.DepthStencil.DepthCompareOp);
  DepthStencil.stencilTestEnable := Ord(ADesc.DepthStencil.StencilTestEnable);
  DepthStencil.front := RHIToVkStencilOpState(ADesc.DepthStencil.FrontStencil);
  DepthStencil.back := RHIToVkStencilOpState(ADesc.DepthStencil.BackStencil);

  FillChar(Multisampling, SizeOf(Multisampling), 0);
  Multisampling.sType := VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  if ADesc.SampleCount > 1 then
    Multisampling.rasterizationSamples := ADesc.SampleCount
  else
    Multisampling.rasterizationSamples := VK_SAMPLE_COUNT_1_BIT;

  FillChar(RenderingInfo, SizeOf(RenderingInfo), 0);
  RenderingInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;
  RenderingInfo.depthAttachmentFormat := RHIToVkFormat(ADesc.DepthAttachmentFormat);

  FillChar(GplInfo, SizeOf(GplInfo), 0);
  GplInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT;
  GplInfo.flags := VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_SHADER_BIT_EXT;
  if FSupportsDynamicRendering then
    GplInfo.pNext := @RenderingInfo;

  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PipelineInfo.pNext := @GplInfo;
  PipelineInfo.flags := VK_PIPELINE_CREATE_LIBRARY_BIT_KHR or
    VK_PIPELINE_CREATE_RETAIN_LINK_TIME_OPTIMIZATION_INFO_BIT_EXT;
  PipelineInfo.stageCount := StageCount;
  if StageCount > 0 then
    PipelineInfo.pStages := @Stage;
  PipelineInfo.pDepthStencilState := @DepthStencil;
  PipelineInfo.pMultisampleState := @Multisampling;
  PipelineInfo.layout := ALayout;
  if not FSupportsDynamicRendering then
    PipelineInfo.renderPass := ARenderPass;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateGraphicsPipelines) and
     ((StageCount > 0) or (ADesc.FragmentShader = nil)) then
    CheckVk(vkCreateGraphicsPipelines(FDevice, FPipelineCache, 1, @PipelineInfo, nil, @Result),
      'vkCreateGraphicsPipelines(FragmentShaderLibrary)')
  else
  if (FDevice = nil) and (FFragmentShaderLibMap <> nil) then
    Result := VkPipeline($30000000 + Cardinal(FFragmentShaderLibMap.Count) + 1);

  if FFragmentShaderLibMap <> nil then
    FFragmentShaderLibMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreateFragmentOutputLibrary(
  const ADesc: TRHIGraphicsPipelineDesc;
  const ARenderPass: VkRenderPass): VkPipeline;
var
  KeyHash: UInt64;
  BlendAttachments: array of VkPipelineColorBlendAttachmentState;
  ColorBlending: VkPipelineColorBlendStateCreateInfo;
  Multisampling: VkPipelineMultisampleStateCreateInfo;
  ColorFormats: array of VkFormat;
  RenderingInfo: VkPipelineRenderingCreateInfoKHR;
  GplInfo: VkGraphicsPipelineLibraryCreateInfoEXT;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
  I: Integer;
begin
  KeyHash := ComputeFragmentOutputLibraryKeyHash(ADesc);
  if (FFragmentOutputLibMap <> nil) and FFragmentOutputLibMap.TryGetValue(KeyHash, Result) then
  begin
    Inc(FGPLLibraryCacheHits);
    Exit;
  end;
  Inc(FGPLLibraryCacheMisses);

  SetLength(BlendAttachments, Max(1, Length(ADesc.ColorAttachmentFormats)));
  for I := 0 to High(BlendAttachments) do
  begin
    FillChar(BlendAttachments[I], SizeOf(VkPipelineColorBlendAttachmentState), 0);
    BlendAttachments[I].blendEnable := Ord(ADesc.BlendState.BlendEnable);
    BlendAttachments[I].srcColorBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.SrcColorBlendFactor);
    BlendAttachments[I].dstColorBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.DstColorBlendFactor);
    BlendAttachments[I].colorBlendOp := RHIToVkBlendOp(ADesc.BlendState.ColorBlendOp);
    BlendAttachments[I].srcAlphaBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.SrcAlphaBlendFactor);
    BlendAttachments[I].dstAlphaBlendFactor := RHIToVkBlendFactor(ADesc.BlendState.DstAlphaBlendFactor);
    BlendAttachments[I].alphaBlendOp := RHIToVkBlendOp(ADesc.BlendState.AlphaBlendOp);
    if ADesc.BlendState.DisableColorWrites then
      BlendAttachments[I].colorWriteMask := 0
    else if ADesc.BlendState.ColorWriteMask <> 0 then
      BlendAttachments[I].colorWriteMask := ADesc.BlendState.ColorWriteMask
    else
      BlendAttachments[I].colorWriteMask := $0F;
  end;

  FillChar(ColorBlending, SizeOf(ColorBlending), 0);
  ColorBlending.sType := VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  ColorBlending.attachmentCount := Length(BlendAttachments);
  if Length(BlendAttachments) > 0 then
    ColorBlending.pAttachments := @BlendAttachments[0];

  FillChar(Multisampling, SizeOf(Multisampling), 0);
  Multisampling.sType := VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  if ADesc.SampleCount > 1 then
    Multisampling.rasterizationSamples := ADesc.SampleCount
  else
    Multisampling.rasterizationSamples := VK_SAMPLE_COUNT_1_BIT;

  SetLength(ColorFormats, Length(ADesc.ColorAttachmentFormats));
  for I := 0 to High(ADesc.ColorAttachmentFormats) do
    ColorFormats[I] := RHIToVkFormat(ADesc.ColorAttachmentFormats[I]);

  FillChar(RenderingInfo, SizeOf(RenderingInfo), 0);
  RenderingInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;
  RenderingInfo.colorAttachmentCount := Length(ColorFormats);
  if Length(ColorFormats) > 0 then
    RenderingInfo.pColorAttachmentFormats := @ColorFormats[0];
  RenderingInfo.depthAttachmentFormat := RHIToVkFormat(ADesc.DepthAttachmentFormat);

  FillChar(GplInfo, SizeOf(GplInfo), 0);
  GplInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_LIBRARY_CREATE_INFO_EXT;
  GplInfo.flags := VK_GRAPHICS_PIPELINE_LIBRARY_FRAGMENT_OUTPUT_INTERFACE_BIT_EXT;
  if FSupportsDynamicRendering then
    GplInfo.pNext := @RenderingInfo;

  FillChar(PipelineInfo, SizeOf(PipelineInfo), 0);
  PipelineInfo.sType := VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
  PipelineInfo.pNext := @GplInfo;
  PipelineInfo.flags := VK_PIPELINE_CREATE_LIBRARY_BIT_KHR or
    VK_PIPELINE_CREATE_RETAIN_LINK_TIME_OPTIMIZATION_INFO_BIT_EXT;
  PipelineInfo.pColorBlendState := @ColorBlending;
  PipelineInfo.pMultisampleState := @Multisampling;
  if not FSupportsDynamicRendering then
    PipelineInfo.renderPass := ARenderPass;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateGraphicsPipelines) then
    CheckVk(vkCreateGraphicsPipelines(FDevice, FPipelineCache, 1, @PipelineInfo, nil, @Result),
      'vkCreateGraphicsPipelines(FragmentOutputLibrary)')
  else
  if FFragmentOutputLibMap <> nil then
    Result := VkPipeline($40000000 + Cardinal(FFragmentOutputLibMap.Count) + 1);

  if FFragmentOutputLibMap <> nil then
    FFragmentOutputLibMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreateFallbackRenderPass(
  const AColorFormats: array of TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat;
  const ASampleCount: Cardinal;
  const AColorLoadOp: TRHIAttachmentLoadOp;
  const ADepthLoadOp: TRHIAttachmentLoadOp;
  const AColorStoreOp: TRHIAttachmentStoreOp;
  const ADepthStoreOp: TRHIAttachmentStoreOp;
  const AHasColorResolve: Boolean): VkRenderPass;

  function MapLoadOp(const AOp: TRHIAttachmentLoadOp): VkAttachmentLoadOp;
  begin
    case AOp of
      loLoad:     Result := VK_ATTACHMENT_LOAD_OP_LOAD;
      loClear:    Result := VK_ATTACHMENT_LOAD_OP_CLEAR;
      loDontCare: Result := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
      else        Result := VK_ATTACHMENT_LOAD_OP_CLEAR;
    end;
  end;

  function MapStoreOp(const AOp: TRHIAttachmentStoreOp): VkAttachmentStoreOp;
  begin
    case AOp of
      soStore:    Result := VK_ATTACHMENT_STORE_OP_STORE;
      soDontCare: Result := VK_ATTACHMENT_STORE_OP_DONT_CARE;
      else        Result := VK_ATTACHMENT_STORE_OP_STORE;
    end;
  end;

var
  KeyHash: UInt64;
  Attachments: array of VkAttachmentDescription;
  ColorRefs, ResolveRefs: array of VkAttachmentReference;
  DepthRef: VkAttachmentReference;
  Subpass: VkSubpassDescription;
  Dependency: VkSubpassDependency;
  RpInfo: VkRenderPassCreateInfo;
  SampleBits: VkSampleCountFlags;
  AttCount, DepthIdx, ResolveBaseIdx, I: Integer;
begin
  KeyHash := ComputeRenderPassKeyHash(AColorFormats, ADepthFormat, ASampleCount,
    AColorLoadOp, ADepthLoadOp, AColorStoreOp, ADepthStoreOp, AHasColorResolve);
  if (FRenderPassMap <> nil) and FRenderPassMap.TryGetValue(KeyHash, Result) then
    Exit;

  SampleBits := RHIToVkSampleCountFlags(ASampleCount);

  AttCount := Length(AColorFormats);
  if ADepthFormat <> pfUndefined then
    Inc(AttCount);
  if (ASampleCount > 1) and AHasColorResolve then
    Inc(AttCount, Length(AColorFormats));

  SetLength(Attachments, AttCount);
  SetLength(ColorRefs, Length(AColorFormats));
  for I := 0 to High(AColorFormats) do
  begin
    FillChar(Attachments[I], SizeOf(VkAttachmentDescription), 0);
    Attachments[I].format := RHIToVkFormat(AColorFormats[I]);
    Attachments[I].samples := SampleBits;
    Attachments[I].loadOp := MapLoadOp(AColorLoadOp);
    if (ASampleCount > 1) and AHasColorResolve then
      Attachments[I].storeOp := VK_ATTACHMENT_STORE_OP_DONT_CARE
    else
      Attachments[I].storeOp := MapStoreOp(AColorStoreOp);
    Attachments[I].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    Attachments[I].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
    Attachments[I].initialLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    Attachments[I].finalLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    ColorRefs[I].attachment := Cardinal(I);
    ColorRefs[I].layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  end;

  FillChar(Subpass, SizeOf(Subpass), 0);
  Subpass.pipelineBindPoint := VK_PIPELINE_BIND_POINT_GRAPHICS;
  Subpass.colorAttachmentCount := Length(ColorRefs);
  if Length(ColorRefs) > 0 then
    Subpass.pColorAttachments := @ColorRefs[0];

  if ADepthFormat <> pfUndefined then
  begin
    DepthIdx := Length(AColorFormats);
    FillChar(Attachments[DepthIdx], SizeOf(VkAttachmentDescription), 0);
    Attachments[DepthIdx].format := RHIToVkFormat(ADepthFormat);
    Attachments[DepthIdx].samples := SampleBits;
    Attachments[DepthIdx].loadOp := MapLoadOp(ADepthLoadOp);
    Attachments[DepthIdx].storeOp := MapStoreOp(ADepthStoreOp);
    Attachments[DepthIdx].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    Attachments[DepthIdx].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
    Attachments[DepthIdx].initialLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    Attachments[DepthIdx].finalLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    DepthRef.attachment := Cardinal(DepthIdx);
    DepthRef.layout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    Subpass.pDepthStencilAttachment := @DepthRef;
  end;

  if (ASampleCount > 1) and AHasColorResolve and (Length(AColorFormats) > 0) then
  begin
    ResolveBaseIdx := Length(AColorFormats);
    if ADepthFormat <> pfUndefined then
      Inc(ResolveBaseIdx);
    SetLength(ResolveRefs, Length(AColorFormats));
    for I := 0 to High(AColorFormats) do
    begin
      FillChar(Attachments[ResolveBaseIdx + I], SizeOf(VkAttachmentDescription), 0);
      Attachments[ResolveBaseIdx + I].format := RHIToVkFormat(AColorFormats[I]);
      Attachments[ResolveBaseIdx + I].samples := VK_SAMPLE_COUNT_1_BIT;
      Attachments[ResolveBaseIdx + I].loadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
      Attachments[ResolveBaseIdx + I].storeOp := VK_ATTACHMENT_STORE_OP_STORE;
      Attachments[ResolveBaseIdx + I].stencilLoadOp := VK_ATTACHMENT_LOAD_OP_DONT_CARE;
      Attachments[ResolveBaseIdx + I].stencilStoreOp := VK_ATTACHMENT_STORE_OP_DONT_CARE;
      Attachments[ResolveBaseIdx + I].initialLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
      Attachments[ResolveBaseIdx + I].finalLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

      ResolveRefs[I].attachment := Cardinal(ResolveBaseIdx + I);
      ResolveRefs[I].layout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    end;
    Subpass.pResolveAttachments := @ResolveRefs[0];
  end;

  FillChar(Dependency, SizeOf(Dependency), 0);
  Dependency.srcSubpass := $FFFFFFFF; // VK_SUBPASS_EXTERNAL
  Dependency.dstSubpass := 0;
  Dependency.srcStageMask := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or
    VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
  Dependency.dstStageMask := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or
    VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
  Dependency.srcAccessMask := 0;
  Dependency.dstAccessMask := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT or
    VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

  FillChar(RpInfo, SizeOf(RpInfo), 0);
  RpInfo.sType := VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
  RpInfo.attachmentCount := Length(Attachments);
  if Length(Attachments) > 0 then
    RpInfo.pAttachments := @Attachments[0];
  RpInfo.subpassCount := 1;
  RpInfo.pSubpasses := @Subpass;
  RpInfo.dependencyCount := 1;
  RpInfo.pDependencies := @Dependency;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateRenderPass) then
    CheckVk(vkCreateRenderPass(FDevice, @RpInfo, nil, @Result), 'vkCreateRenderPass')
  else
  if FRenderPassMap <> nil then
    Result := VkRenderPass(FRenderPassMap.Count + 1);

  if FRenderPassMap <> nil then
    FRenderPassMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.GetOrCreateFallbackFramebuffer(
  const ARenderPass: VkRenderPass;
  const AAttachments: array of VkImageView;
  const AWidth, AHeight: Cardinal): VkFramebuffer;
var
  KeyHash: UInt64;
  FbInfo: VkFramebufferCreateInfo;
begin
  KeyHash := ComputeFramebufferKeyHash(ARenderPass, AAttachments, AWidth, AHeight);
  if (FFramebufferMap <> nil) and FFramebufferMap.TryGetValue(KeyHash, Result) then
    Exit;

  FillChar(FbInfo, SizeOf(FbInfo), 0);
  FbInfo.sType := VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
  FbInfo.renderPass := ARenderPass;
  FbInfo.attachmentCount := Length(AAttachments);
  if Length(AAttachments) > 0 then
    FbInfo.pAttachments := @AAttachments[0];
  FbInfo.width := Max(1, AWidth);
  FbInfo.height := Max(1, AHeight);
  FbInfo.layers := 1;

  Result := VK_NULL_HANDLE;
  if (FDevice <> nil) and Assigned(vkCreateFramebuffer) then
    CheckVk(vkCreateFramebuffer(FDevice, @FbInfo, nil, @Result), 'vkCreateFramebuffer')
  else
  if FFramebufferMap <> nil then
    Result := VkFramebuffer(FFramebufferMap.Count + 1);

  if FFramebufferMap <> nil then
    FFramebufferMap.AddOrSetValue(KeyHash, Result);
end;

function TVulkanRHIDevice.QueryMemoryBudget(out AUsedBytes, ABudgetBytes: UInt64;
  out AUsedMB, ABudgetMB: Cardinal): Boolean;
begin
  Result := QueryPhysicalDeviceMemoryBudget(
    FPhysicalDevice, FSupportsMemoryBudgetExt,
    UInt64(Max(Int64(0), FAllocatedMemoryBytes)),
    AUsedBytes, ABudgetBytes, AUsedMB, ABudgetMB);
end;

procedure TVulkanRHIDevice.RecordDiagnostics(const APipelineHits, APipelineMisses,
  ADescriptorAllocs: Cardinal; const AAllocatedBytes: UInt64);
begin
  Inc(FPipelineCacheHits, APipelineHits);
  Inc(FPipelineCacheMisses, APipelineMisses);
  Inc(FDescriptorSetAllocations, ADescriptorAllocs);
  Inc(FAllocatedMemoryBytes, AAllocatedBytes);
end;

procedure TVulkanRHIDevice.EnsureMSAATargets(const AWidth, AHeight: Cardinal;
  const AColorFormat, ADepthFormat: TRHIPixelFormat);
var
  EffSamples: Cardinal;
  MSAAColorDesc, MSAADepthDesc: TRHITextureDesc;
begin
  EffSamples := Max(Cardinal(1), FSampleCount);
  if FCapabilities.MaxFramebufferSampleCount > 0 then
    EffSamples := Min(EffSamples, FCapabilities.MaxFramebufferSampleCount);

  if (EffSamples <= 1) or (AWidth = 0) or (AHeight = 0) then
  begin
    FreeAndNil(FSwapchainMSAAColorTexture);
    FreeAndNil(FSwapchainMSAADepthTexture);
    Exit;
  end;

  if (FSwapchainMSAAColorTexture = nil) or
     (FSwapchainMSAAColorTexture.Desc.Width <> AWidth) or
     (FSwapchainMSAAColorTexture.Desc.Height <> AHeight) or
     (FSwapchainMSAAColorTexture.Desc.Format <> AColorFormat) or
     (FSwapchainMSAAColorTexture.Desc.SampleCount <> EffSamples) then
  begin
    FreeAndNil(FSwapchainMSAAColorTexture);
    if AColorFormat <> pfUndefined then
    begin
      MSAAColorDesc := TRHITextureDesc.Create2D(AWidth, AHeight, AColorFormat,
        [tuColorAttachment], 1, EffSamples);
      MSAAColorDesc.DebugName := 'SwapchainMSAAColor';
      FSwapchainMSAAColorTexture := TVulkanRHITexture.Create(Self, MSAAColorDesc);
    end;
  end;

  if (FSwapchainMSAADepthTexture = nil) or
     (FSwapchainMSAADepthTexture.Desc.Width <> AWidth) or
     (FSwapchainMSAADepthTexture.Desc.Height <> AHeight) or
     (FSwapchainMSAADepthTexture.Desc.Format <> ADepthFormat) or
     (FSwapchainMSAADepthTexture.Desc.SampleCount <> EffSamples) then
  begin
    FreeAndNil(FSwapchainMSAADepthTexture);
    if ADepthFormat <> pfUndefined then
    begin
      MSAADepthDesc := TRHITextureDesc.Create2D(AWidth, AHeight, ADepthFormat,
        [tuDepthStencil], 1, EffSamples);
      MSAADepthDesc.DebugName := 'SwapchainMSAADepth';
      FSwapchainMSAADepthTexture := TVulkanRHITexture.Create(Self, MSAADepthDesc);
    end;
  end;
end;

procedure TVulkanRHIDevice.SetAntiAliasing(const AValue: TAntiAliasing);
var
  ReqSamples: Cardinal;
begin
  FAntiAliasing := AValue;
  ReqSamples := Max(Cardinal(1), AntiAliasingToSampleCount(AValue));
  SetSampleCount(ReqSamples);
end;

procedure TVulkanRHIDevice.SetSampleCount(const AValue: Cardinal);
var
  MaxSamples: Cardinal;
begin
  MaxSamples := FCapabilities.MaxFramebufferSampleCount;
  if MaxSamples = 0 then
    MaxSamples := 8;
  FSampleCount := ClampSampleCountToMask(AValue, (MaxSamples shl 1) - 1);
  if FSampleCount <= 1 then
  begin
    FreeAndNil(FSwapchainMSAAColorTexture);
    FreeAndNil(FSwapchainMSAADepthTexture);
  end else
  if (FSwapchainExtent.width > 0) and (FSwapchainExtent.height > 0) then
    EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, pfD32_Float);
end;

procedure TVulkanRHIDevice.SetSupportsExtendedDynamicState(const AValue: Boolean);
begin
  FSupportsExtendedDynamicState := AValue;
  FCapabilities.SupportsExtendedDynamicState := AValue;
end;

procedure TVulkanRHIDevice.SetSupportsSynchronization2(const AValue: Boolean);
begin
  FSupportsSynchronization2 := AValue;
  FCapabilities.SupportsSynchronization2 := AValue;
end;

procedure TVulkanRHIDevice.SetSupportsTimelineSemaphores(const AValue: Boolean);
begin
  FSupportsTimelineSemaphores := AValue;
  FCapabilities.SupportsTimelineSemaphores := AValue;
end;

function TVulkanRHIDevice.BuildSwapchainRenderingInfo(const ARenderArea: TRectangle;
  const AResolveColorTarget: TRHITexture;
  const AResolveDepthTarget: TRHITexture;
  const AClearColor: TCastleColor;
  const AColorLoadOp: TRHIAttachmentLoadOp;
  const ADepthLoadOp: TRHIAttachmentLoadOp;
  const AClearDepth: Single): TRHIRenderingInfo;
var
  W, H: Cardinal;
  ColorFmt, DepthFmt: TRHIPixelFormat;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RenderArea := ARenderArea;
  W := Max(1, ARenderArea.Width);
  H := Max(1, ARenderArea.Height);

  if AResolveColorTarget <> nil then
    ColorFmt := AResolveColorTarget.Desc.Format
  else
    ColorFmt := FSwapchainFormat;
  if AResolveDepthTarget <> nil then
    DepthFmt := AResolveDepthTarget.Desc.Format
  else
    DepthFmt := pfD32_Float;

  if (FSampleCount > 1) and (AResolveColorTarget <> nil) then
  begin
    EnsureMSAATargets(W, H, ColorFmt, DepthFmt);
    SetLength(Result.ColorAttachments, 1);
    Result.ColorAttachments[0].Texture := FSwapchainMSAAColorTexture;
    Result.ColorAttachments[0].ResolveTexture := AResolveColorTarget;
    Result.ColorAttachments[0].ResolveMode := rmAverage;
    Result.ColorAttachments[0].LoadOp := AColorLoadOp;
    Result.ColorAttachments[0].StoreOp := soDontCare;
    Result.ColorAttachments[0].ClearColor := AClearColor;

    Result.DepthAttachment.Texture := FSwapchainMSAADepthTexture;
    Result.DepthAttachment.ResolveTexture := nil;
    Result.DepthAttachment.ResolveMode := rmNone;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    Result.DepthAttachment.StoreOp := soDontCare;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end else
  begin
    if AResolveColorTarget <> nil then
    begin
      SetLength(Result.ColorAttachments, 1);
      Result.ColorAttachments[0].Texture := AResolveColorTarget;
      Result.ColorAttachments[0].ResolveTexture := nil;
      Result.ColorAttachments[0].ResolveMode := rmNone;
      Result.ColorAttachments[0].LoadOp := AColorLoadOp;
      Result.ColorAttachments[0].StoreOp := soStore;
      Result.ColorAttachments[0].ClearColor := AClearColor;
    end;
    Result.DepthAttachment.Texture := AResolveDepthTarget;
    Result.DepthAttachment.ResolveTexture := nil;
    Result.DepthAttachment.ResolveMode := rmNone;
    Result.DepthAttachment.LoadOp := ADepthLoadOp;
    Result.DepthAttachment.StoreOp := soStore;
    Result.DepthAttachment.ClearDepth := AClearDepth;
  end;
end;

procedure TVulkanRHIDevice.CreateSwapchain(const Width, Height: Cardinal);
var
  Caps: VkSurfaceCapabilitiesKHR;
  ImageCount, I: Cardinal;
  CreateInfo: VkSwapchainCreateInfoKHR;
  Images: array of VkImage;
  ViewInfo: VkImageViewCreateInfo;
  ImgView: VkImageView;
  ColorDesc, DepthDesc: TRHITextureDesc;
begin
  if (FSurface = VK_NULL_HANDLE) or (FDevice = nil) then Exit;

  FillChar(Caps, SizeOf(Caps), 0);
  CheckVk(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(FPhysicalDevice, FSurface, @Caps),
    'vkGetPhysicalDeviceSurfaceCapabilitiesKHR');

  FSwapchainFormat := pfBGRA8_UNorm;
  FSwapchainExtent.width := Max(1, Width);
  FSwapchainExtent.height := Max(1, Height);
  if Caps.currentExtent.width <> High(Cardinal) then
    FSwapchainExtent := Caps.currentExtent;

  ImageCount := Max(2, Caps.minImageCount);
  if (Caps.maxImageCount > 0) and (ImageCount > Caps.maxImageCount) then
    ImageCount := Caps.maxImageCount;

  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
  CreateInfo.surface := FSurface;
  CreateInfo.minImageCount := ImageCount;
  CreateInfo.imageFormat := RHIToVkFormat(FSwapchainFormat);
  CreateInfo.imageColorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  CreateInfo.imageExtent := FSwapchainExtent;
  CreateInfo.imageArrayLayers := 1;
  CreateInfo.imageUsage := VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  CreateInfo.imageSharingMode := VK_SHARING_MODE_EXCLUSIVE;
  CreateInfo.preTransform := Caps.currentTransform;
  CreateInfo.compositeAlpha := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
  CreateInfo.presentMode := VK_PRESENT_MODE_FIFO_KHR;
  CreateInfo.clipped := VK_TRUE;

  CheckVk(vkCreateSwapchainKHR(FDevice, @CreateInfo, nil, @FSwapchain), 'vkCreateSwapchainKHR');

  CheckVk(vkGetSwapchainImagesKHR(FDevice, FSwapchain, @ImageCount, nil), 'vkGetSwapchainImagesKHR(count)');
  SetLength(Images, ImageCount);
  CheckVk(vkGetSwapchainImagesKHR(FDevice, FSwapchain, @ImageCount, @Images[0]), 'vkGetSwapchainImagesKHR');

  ColorDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    FSwapchainFormat, [tuColorAttachment, tuTransferSrc, tuTransferDst], 1);

  SetLength(FSwapchainColorTextures, ImageCount);
  for I := 0 to ImageCount - 1 do
  begin
    FillChar(ViewInfo, SizeOf(ViewInfo), 0);
    ViewInfo.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ViewInfo.image := Images[I];
    ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D;
    ViewInfo.format := CreateInfo.imageFormat;
    ViewInfo.subresourceRange.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
    ViewInfo.subresourceRange.baseMipLevel := 0;
    ViewInfo.subresourceRange.levelCount := 1;
    ViewInfo.subresourceRange.baseArrayLayer := 0;
    ViewInfo.subresourceRange.layerCount := 1;
    CheckVk(vkCreateImageView(FDevice, @ViewInfo, nil, @ImgView), 'vkCreateImageView(Swapchain)');
    FSwapchainColorTextures[I] := TVulkanRHITexture.CreateSwapchainWrapper(Self, ColorDesc, Images[I], ImgView);
  end;

  DepthDesc := TRHITextureDesc.Create2D(FSwapchainExtent.width, FSwapchainExtent.height,
    pfD32_Float, [tuDepthStencil], 1);
  FSwapchainDepthTexture := TVulkanRHITexture.Create(Self, DepthDesc);

  if FSampleCount > 1 then
    EnsureMSAATargets(FSwapchainExtent.width, FSwapchainExtent.height, FSwapchainFormat, pfD32_Float);
end;

procedure TVulkanRHIDevice.DestroySwapchain;
var
  I: Integer;
begin
  ClearFallbackFramebuffers;
  FreeAndNil(FSwapchainMSAAColorTexture);
  FreeAndNil(FSwapchainMSAADepthTexture);
  FreeAndNil(FSwapchainDepthTexture);
  for I := 0 to High(FSwapchainColorTextures) do
    FreeAndNil(FSwapchainColorTextures[I]);
  SetLength(FSwapchainColorTextures, 0);

  if FSwapchain <> VK_NULL_HANDLE then
  begin
    vkDestroySwapchainKHR(FDevice, FSwapchain, nil);
    FSwapchain := VK_NULL_HANDLE;
  end;
end;

procedure TVulkanRHIDevice.CreateFrameContexts;
var
  I: Integer;
  SemInfo: VkSemaphoreCreateInfo;
  FenceInfo: VkFenceCreateInfo;
begin
  FillChar(SemInfo, SizeOf(SemInfo), 0);
  SemInfo.sType := VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

  FillChar(FenceInfo, SizeOf(FenceInfo), 0);
  FenceInfo.sType := VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
  FenceInfo.flags := VK_FENCE_CREATE_SIGNALED_BIT;

  for I := 0 to MaxFramesInFlight - 1 do
  begin
    CheckVk(vkCreateSemaphore(FDevice, @SemInfo, nil, @FFrames[I].ImageAvailableSemaphore), 'vkCreateSemaphore');
    CheckVk(vkCreateSemaphore(FDevice, @SemInfo, nil, @FFrames[I].RenderFinishedSemaphore), 'vkCreateSemaphore');
    CheckVk(vkCreateFence(FDevice, @FenceInfo, nil, @FFrames[I].InFlightFence), 'vkCreateFence');
    FFrames[I].CommandList := TVulkanRHICommandList.Create(Self, FGraphicsQueueFamily);
    if FFrames[I].TransientDescriptorAllocator = nil then
      FFrames[I].TransientDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(FDevice, 512, False, 4096);
  end;
end;

procedure TVulkanRHIDevice.CreateDescriptorPool;
begin
  if FPersistentDescriptorAllocator = nil then
    FPersistentDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(
      FDevice, 2048, True, 8192, FSupportsBindlessUpdateAfterBind);
end;

function TVulkanRHIDevice.BeginFrame: TRHICommandList;
var
  Frame: TVulkanFrameContext;
  AcquireRes: VkResult;
begin
  Frame := FFrames[FFrameIndex];

  { 1. Wait for the GPU to finish executing the previous frame occupying this slot }
  CheckVk(vkWaitForFences(FDevice, 1, @Frame.InFlightFence, VK_TRUE, High(UInt64)), 'vkWaitForFences');
  { Retire any VkBuffers/VkImages/VkDescriptorSets/TVulkanMemoryAllocations destroyed while this slot was in flight }
  FlushDeferredDeletions(FFrameIndex);
  if FMemoryAllocator <> nil then
    FMemoryAllocator.GetFrameRingBuffer(FFrameIndex).Reset;
  if FStagingUploader <> nil then
    FStagingUploader.ReclaimFrameSlot(FFrameIndex);
  if Frame.TransientDescriptorAllocator <> nil then
    Frame.TransientDescriptorAllocator.ResetPools;
  FDeferResourceDestruction := True;

  { 2. Acquire next swapchain image }
  AcquireRes := vkAcquireNextImageKHR(FDevice, FSwapchain, High(UInt64),
    Frame.ImageAvailableSemaphore, VK_NULL_HANDLE, @FCurrentSwapchainImageIndex);

  if AcquireRes = VK_ERROR_OUT_OF_DATE_KHR then
  begin
    ResizeSwapchain(FSwapchainExtent.width, FSwapchainExtent.height);
    Exit(nil);
  end;

  CheckVk(vkResetFences(FDevice, 1, @Frame.InFlightFence), 'vkResetFences');

  { 3. Begin command list recording }
  Frame.CommandList.BeginRecording;
  if FTimestampProfiler <> nil then
    FTimestampProfiler.BeginFrame(Frame.CommandList, FFrameIndex);
  if FStagingUploader <> nil then
    FStagingUploader.FlushPendingUploads(Frame.CommandList);
  if FBindlessTextureManager <> nil then
    FBindlessTextureManager.FlushPendingUpdates;
  Result := Frame.CommandList;
  SetActiveCommandList(Result);
end;

procedure TVulkanRHIDevice.EndFrameAndPresent;
var
  Frame: TVulkanFrameContext;
  SubmitInfo: VkSubmitInfo;
  WaitStages: VkPipelineStageFlags;
  PresentInfo: VkPresentInfoKHR;
  CmdHandle: VkCommandBuffer;
begin
  SetActiveCommandList(nil);
  Frame := FFrames[FFrameIndex];

  if FStagingUploader <> nil then
    FStagingUploader.FlushPendingUploads(Frame.CommandList);

  { Ensure swapchain backbuffer is transitioned to VK_IMAGE_LAYOUT_PRESENT_SRC_KHR }
  Frame.CommandList.TransitionTexture(GetSwapchainColorTexture, rsPresent);
  Frame.CommandList.EndRecording;

  WaitStages := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  CmdHandle := Frame.CommandList.Handle;

  FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
  SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
  SubmitInfo.waitSemaphoreCount := 1;
  SubmitInfo.pWaitSemaphores := @Frame.ImageAvailableSemaphore;
  SubmitInfo.pWaitDstStageMask := @WaitStages;
  SubmitInfo.commandBufferCount := 1;
  SubmitInfo.pCommandBuffers := @CmdHandle;
  SubmitInfo.signalSemaphoreCount := 1;
  SubmitInfo.pSignalSemaphores := @Frame.RenderFinishedSemaphore;

  CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, Frame.InFlightFence), 'vkQueueSubmit');

  FillChar(PresentInfo, SizeOf(PresentInfo), 0);
  PresentInfo.sType := VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
  PresentInfo.waitSemaphoreCount := 1;
  PresentInfo.pWaitSemaphores := @Frame.RenderFinishedSemaphore;
  PresentInfo.swapchainCount := 1;
  PresentInfo.pSwapchains := @FSwapchain;
  PresentInfo.pImageIndices := @FCurrentSwapchainImageIndex;

  vkQueuePresentKHR(FPresentQueue, @PresentInfo);

  FFrameIndex := (FFrameIndex + 1) mod MaxFramesInFlight;
end;

procedure TVulkanRHIDevice.ResizeSwapchain(const NewWidth, NewHeight: Cardinal);
begin
  if (NewWidth = 0) or (NewHeight = 0) then Exit;
  WaitIdle;
  DestroySwapchain;
  CreateSwapchain(NewWidth, NewHeight);
end;

procedure TVulkanRHIDevice.WaitIdle;
begin
  FlushStagingUploads;
  if (FDevice <> nil) and Assigned(vkDeviceWaitIdle) then
    vkDeviceWaitIdle(FDevice);
  FlushAllDeferredDeletions;
  FDeferResourceDestruction := False;
end;

function TVulkanRHIDevice.CreateSecondaryCommandList: TRHICommandList;
begin
  Result := TVulkanRHICommandList.Create(Self, FGraphicsQueueFamily, cllSecondary);
end;

function TVulkanRHIDevice.GetSwapchainColorTexture: TRHITexture;
begin
  if FActiveColorTarget <> nil then
    Result := FActiveColorTarget
  else if FCurrentSwapchainImageIndex < Cardinal(Length(FSwapchainColorTextures)) then
    Result := FSwapchainColorTextures[FCurrentSwapchainImageIndex]
  else
    Result := nil;
end;

function TVulkanRHIDevice.GetSwapchainDepthTexture: TRHITexture;
begin
  if FActiveDepthTarget <> nil then
    Result := FActiveDepthTarget
  else
    Result := FSwapchainDepthTexture;
end;

function TVulkanRHIDevice.CreateBuffer(const ADesc: TRHIBufferDesc;
  const InitialData: Pointer): TRHIBuffer;
begin
  Result := TVulkanRHIBuffer.Create(Self, ADesc, InitialData);
end;

function TVulkanRHIDevice.CreateTexture(const ADesc: TRHITextureDesc): TRHITexture;
begin
  Result := TVulkanRHITexture.Create(Self, ADesc);
end;

function TVulkanRHIDevice.CreateSampler(const ADesc: TRHISamplerDesc): TRHISampler;
begin
  Result := TVulkanRHISampler.Create(Self, ADesc);
end;

function TVulkanRHIDevice.CreateShaderModuleFromGLSL(const AStage: TRHIShaderStage;
  const AGLSLSource: String; const ADebugName: String): TRHIShaderModule;
var
  SPIRV: TSPIRVBytecode;
  FallbackWords: array[0..9] of UInt32;
  ExecModel: UInt32;
begin
  SPIRV := nil;
  try
    SPIRV := TCastleShaderCompiler.Instance.GetOrCompileSPIRV(AStage, AGLSLSource, ADebugName);
  except
    on ERHIShaderCompilationError do
      if (FDevice = nil) and (AGLSLSource <> '') and
         not TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
        SPIRV := nil
      else
        raise;
  end;
  if Length(SPIRV) = 0 then
  begin
    if (FDevice = nil) and (AGLSLSource <> '') and
       not TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
    begin
      case AStage of
        ssVertex:   ExecModel := 0;
        ssFragment: ExecModel := 4;
        ssCompute:  ExecModel := 5;
      else
        ExecModel := 0;
      end;
      FallbackWords[0] := $07230203; // SPIR-V Magic
      FallbackWords[1] := $00010000; // Version 1.0
      FallbackWords[2] := 0;         // Generator
      FallbackWords[3] := 8;         // Bound
      FallbackWords[4] := 0;         // Schema
      FallbackWords[5] := ($00050000 or 15); // OpEntryPoint
      FallbackWords[6] := ExecModel;
      FallbackWords[7] := 1;
      FallbackWords[8] := $6E69616D; // "main"
      FallbackWords[9] := 0;
      Exit(CreateShaderModuleFromSPIRV(AStage, @FallbackWords[0], SizeOf(FallbackWords), ADebugName));
    end;
    Exit(nil);
  end;
  Result := CreateShaderModuleFromSPIRV(AStage, @SPIRV[0], Length(SPIRV), ADebugName);
end;

function TVulkanRHIDevice.CreateShaderModuleFromSPIRV(const AStage: TRHIShaderStage;
  const ASPIRVBinary: Pointer; const ASizeInBytes: PtrUInt;
  const ADebugName: String): TRHIShaderModule;
begin
  Result := TVulkanRHIShaderModule.Create(Self, AStage, ASPIRVBinary, ASizeInBytes, ADebugName);
end;

function TVulkanRHIDevice.CreateDescriptorSetLayout(
  const Bindings: array of TRHIDescriptorBindingDesc): TRHIDescriptorSetLayout;
begin
  Result := TVulkanRHIDescriptorSetLayout.Create(Self, Bindings);
end;

function TVulkanRHIDevice.CreateDescriptorSet(
  const Layout: TRHIDescriptorSetLayout): TRHIDescriptorSet;
begin
  Inc(FDescriptorSetAllocations);
  Result := TVulkanRHIDescriptorSet.Create(Self, Layout as TVulkanRHIDescriptorSetLayout);
end;

function TVulkanRHIDevice.ComputePipelineHash(const ADesc: TRHIGraphicsPipelineDesc): UInt64;
begin
  Result := ComputePipelineKeyHashEx(ADesc, FSupportsExtendedDynamicState);
end;

function TVulkanRHIDevice.GetPipelineCount: Cardinal;
begin
  if FPipelineMap <> nil then
    Result := Cardinal(FPipelineMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetComputePipelineCount: Cardinal;
begin
  if FComputePipelineMap <> nil then
    Result := Cardinal(FComputePipelineMap.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetOrCreatePipeline(const ADesc: TRHIGraphicsPipelineDesc): TRHIPipeline;
var
  HashKey: UInt64;
  FoundPipeline: TVulkanRHIPipeline;
begin
  HashKey := ComputePipelineHash(ADesc);
  if FPipelineMap.TryGetValue(HashKey, FoundPipeline) then
  begin
    Inc(FPipelineCacheHits);
  end else
  begin
    Inc(FPipelineCacheMisses);
    FoundPipeline := TVulkanRHIPipeline.Create(Self, ADesc);
    FPipelineMap.Add(HashKey, FoundPipeline);
  end;
  Result := FoundPipeline;
end;

function TVulkanRHIDevice.GetOrCreateComputePipeline(
  const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline;
var
  HashKey: UInt64;
  FoundPipeline: TVulkanRHIComputePipeline;
begin
  HashKey := ComputeComputePipelineKeyHash(ADesc);
  if (FComputePipelineMap <> nil) and FComputePipelineMap.TryGetValue(HashKey, FoundPipeline) then
  begin
    Inc(FComputePipelineCacheHits);
  end else
  begin
    Inc(FComputePipelineCacheMisses);
    FoundPipeline := TVulkanRHIComputePipeline.Create(Self, ADesc);
    if FComputePipelineMap <> nil then
      FComputePipelineMap.Add(HashKey, FoundPipeline);
  end;
  Result := FoundPipeline;
end;

function TVulkanRHIDevice.CreateComputePipeline(
  const ADesc: TRHIComputePipelineDesc): TRHIComputePipeline;
begin
  Result := TVulkanRHIComputePipeline.Create(Self, ADesc);
end;

function TVulkanRHIDevice.CreateQueryPool(const ADesc: TRHIQueryPoolDesc): TRHIQueryPool;
begin
  Result := TVulkanRHIQueryPool.Create(Self, ADesc);
end;

function TVulkanRHIDevice.CreateTimelineSemaphore(
  const AInitialValue: UInt64): TCastleVulkanTimelineSemaphore;
begin
  Result := TCastleVulkanTimelineSemaphore.Create(Self, AInitialValue);
end;

function TVulkanRHIDevice.PrewarmStandardPipelines(const AIncludeBlending: Boolean;
  const AIncludeShadowDepth: Boolean; const ACacheFileUrl: String): Cardinal;
const
  Default3DVertSrc =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec3 castle_Vertex;' + LineEnding +
    'layout(location = 1) in vec3 castle_Normal;' + LineEnding +
    'layout(location = 2) in vec2 castle_TexCoord0;' + LineEnding +
    'layout(push_constant) uniform PushData { mat4 mvp; } pc;' + LineEnding +
    'layout(location = 0) out vec3 vNormal;' + LineEnding +
    'layout(location = 1) out vec2 vTexCoord;' + LineEnding +
    'void main() {' + LineEnding +
    '  vNormal = castle_Normal;' + LineEnding +
    '  vTexCoord = castle_TexCoord0;' + LineEnding +
    '  gl_Position = pc.mvp * vec4(castle_Vertex, 1.0);' + LineEnding +
    '}';
  Default3DFragSrc =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec3 vNormal;' + LineEnding +
    'layout(location = 1) in vec2 vTexCoord;' + LineEnding +
    'layout(location = 0) out vec4 outColor;' + LineEnding +
    'void main() {' + LineEnding +
    '  outColor = vec4(normalize(vNormal) * 0.5 + 0.5, 1.0);' + LineEnding +
    '}';
  Default2DVertSrc =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec2 aPosition;' + LineEnding +
    'layout(location = 1) in vec2 aTexCoord;' + LineEnding +
    'layout(location = 2) in vec4 aColor;' + LineEnding +
    'layout(location = 0) out vec2 vTexCoord;' + LineEnding +
    'layout(location = 1) out vec4 vColor;' + LineEnding +
    'void main() {' + LineEnding +
    '  vTexCoord = aTexCoord;' + LineEnding +
    '  vColor = aColor;' + LineEnding +
    '  gl_Position = vec4(aPosition, 0.0, 1.0);' + LineEnding +
    '}';
  Default2DFragSrc =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec2 vTexCoord;' + LineEnding +
    'layout(location = 1) in vec4 vColor;' + LineEnding +
    'layout(location = 0) out vec4 outColor;' + LineEnding +
    'void main() {' + LineEnding +
    '  outColor = vColor;' + LineEnding +
    '}';
var
  EffectiveCacheUrl: String;
  MissesBefore: Cardinal;
  ColorFormat: TRHIPixelFormat;
  Desc3D, Desc2D, DescShadow: TRHIGraphicsPipelineDesc;
begin
  if ACacheFileUrl <> '' then
    EffectiveCacheUrl := ACacheFileUrl
  else
    EffectiveCacheUrl := DefaultVulkanPipelineCacheUrl;

  if not FPipelineCacheLoaded then
  begin
    FPipelineCacheLoaded := True;
    if EffectiveCacheUrl <> '' then
      LoadPipelineCache(EffectiveCacheUrl);
  end;

  { Pre-warm core GLSL -> SPIR-V shader blobs if shaderc is available }
  TCastleShaderCompiler.Instance.PrewarmCoreEngineShaders;

  if (FDevice <> nil) and TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable and
     (FPrewarm3DVertexShader = nil) then
  begin
    FPrewarm3DVertexShader := CreateShaderModuleFromGLSL(ssVertex, Default3DVertSrc, 'Prewarm3DVert');
    FPrewarm3DFragmentShader := CreateShaderModuleFromGLSL(ssFragment, Default3DFragSrc, 'Prewarm3DFrag');
    FPrewarm2DVertexShader := CreateShaderModuleFromGLSL(ssVertex, Default2DVertSrc, 'Prewarm2DVert');
    FPrewarm2DFragmentShader := CreateShaderModuleFromGLSL(ssFragment, Default2DFragSrc, 'Prewarm2DFrag');
  end;

  if FSwapchainFormat <> pfUndefined then
    ColorFormat := FSwapchainFormat
  else
    ColorFormat := pfBGRA8_UNorm;

  MissesBefore := FPipelineCacheMisses;

  { 1. Standard 3D Forward Opaque PSO (CullBack, DepthTestWrite, Opaque) }
  FillChar(Desc3D, SizeOf(Desc3D), 0);
  Desc3D.VertexShader := FPrewarm3DVertexShader;
  Desc3D.FragmentShader := FPrewarm3DFragmentShader;
  Desc3D.Topology := ptTriangleList;
  Desc3D.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc3D.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
  Desc3D.BlendState := TRHIBlendStateDesc.DefaultOpaque;
  Desc3D.PushConstantSize := 128;
  Desc3D.PushConstantStages := [ssVertex, ssFragment];
  SetLength(Desc3D.ColorAttachmentFormats, 1);
  Desc3D.ColorAttachmentFormats[0] := ColorFormat;
  Desc3D.DepthAttachmentFormat := pfD32_Float;
  Desc3D.SampleCount := 1;
  SetLength(Desc3D.VertexInput.Bindings, 1);
  Desc3D.VertexInput.Bindings[0].Binding := 0;
  Desc3D.VertexInput.Bindings[0].Stride := 32;
  Desc3D.VertexInput.Bindings[0].PerInstance := False;
  SetLength(Desc3D.VertexInput.Attributes, 3);
  Desc3D.VertexInput.Attributes[0].Location := 0;
  Desc3D.VertexInput.Attributes[0].Binding := 0;
  Desc3D.VertexInput.Attributes[0].Format := vafVector3;
  Desc3D.VertexInput.Attributes[0].Offset := 0;
  Desc3D.VertexInput.Attributes[0].AttributeName := 'castle_Vertex';
  Desc3D.VertexInput.Attributes[1].Location := 1;
  Desc3D.VertexInput.Attributes[1].Binding := 0;
  Desc3D.VertexInput.Attributes[1].Format := vafVector3;
  Desc3D.VertexInput.Attributes[1].Offset := 12;
  Desc3D.VertexInput.Attributes[1].AttributeName := 'castle_Normal';
  Desc3D.VertexInput.Attributes[2].Location := 2;
  Desc3D.VertexInput.Attributes[2].Binding := 0;
  Desc3D.VertexInput.Attributes[2].Format := vafVector2;
  Desc3D.VertexInput.Attributes[2].Offset := 24;
  Desc3D.VertexInput.Attributes[2].AttributeName := 'castle_TexCoord0';
  Desc3D.DebugName := 'Prewarm3DForwardOpaque';
  GetOrCreatePipeline(Desc3D);

  { 2. Two-Sided 3D Forward Opaque PSO (CullNone, DepthTestWrite, Opaque) }
  Desc3D.Rasterizer.CullMode := cmNone;
  Desc3D.DebugName := 'Prewarm3DForwardOpaqueTwoSided';
  GetOrCreatePipeline(Desc3D);

  { 3. Alpha-Blended 3D Forward PSO (CullNone, DepthReadOnly, AlphaBlend) }
  if AIncludeBlending then
  begin
    Desc3D.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthReadOnly;
    Desc3D.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
    Desc3D.DebugName := 'Prewarm3DForwardAlphaBlend';
    GetOrCreatePipeline(Desc3D);
  end;

  { 4. Shadow Map Depth-Only 3D PSO }
  if AIncludeShadowDepth then
  begin
    FillChar(DescShadow, SizeOf(DescShadow), 0);
    DescShadow.VertexShader := FPrewarm3DVertexShader;
    DescShadow.FragmentShader := nil;
    DescShadow.Topology := ptTriangleList;
    DescShadow.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    DescShadow.Rasterizer.DepthBiasEnable := True;
    DescShadow.DepthStencil := TRHIDepthStencilStateDesc.DefaultShadowMap;
    DescShadow.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    DescShadow.PushConstantSize := 128;
    DescShadow.PushConstantStages := [ssVertex];
    SetLength(DescShadow.ColorAttachmentFormats, 0);
    DescShadow.DepthAttachmentFormat := pfD32_Float;
    DescShadow.SampleCount := 1;
    DescShadow.VertexInput := Desc3D.VertexInput;
    DescShadow.DebugName := 'Prewarm3DShadowDepthOnly';
    GetOrCreatePipeline(DescShadow);
  end;

  { 5. 2D UI / Sprite Batch PSO (CullNone, DepthDisabled, AlphaBlend) }
  FillChar(Desc2D, SizeOf(Desc2D), 0);
  Desc2D.VertexShader := FPrewarm2DVertexShader;
  Desc2D.FragmentShader := FPrewarm2DFragmentShader;
  Desc2D.Topology := ptTriangleList;
  Desc2D.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  Desc2D.Rasterizer.CullMode := cmNone;
  Desc2D.DepthStencil := TRHIDepthStencilStateDesc.DefaultDisabled;
  Desc2D.BlendState := TRHIBlendStateDesc.DefaultAlphaBlend;
  Desc2D.PushConstantSize := 64;
  Desc2D.PushConstantStages := [ssVertex, ssFragment];
  SetLength(Desc2D.ColorAttachmentFormats, 1);
  Desc2D.ColorAttachmentFormats[0] := ColorFormat;
  Desc2D.DepthAttachmentFormat := pfD32_Float;
  Desc2D.SampleCount := 1;
  SetLength(Desc2D.VertexInput.Bindings, 1);
  Desc2D.VertexInput.Bindings[0].Binding := 0;
  Desc2D.VertexInput.Bindings[0].Stride := 20;
  Desc2D.VertexInput.Bindings[0].PerInstance := False;
  SetLength(Desc2D.VertexInput.Attributes, 3);
  Desc2D.VertexInput.Attributes[0].Location := 0;
  Desc2D.VertexInput.Attributes[0].Binding := 0;
  Desc2D.VertexInput.Attributes[0].Format := vafVector2;
  Desc2D.VertexInput.Attributes[0].Offset := 0;
  Desc2D.VertexInput.Attributes[0].AttributeName := 'aPosition';
  Desc2D.VertexInput.Attributes[1].Location := 1;
  Desc2D.VertexInput.Attributes[1].Binding := 0;
  Desc2D.VertexInput.Attributes[1].Format := vafVector2;
  Desc2D.VertexInput.Attributes[1].Offset := 8;
  Desc2D.VertexInput.Attributes[1].AttributeName := 'aTexCoord';
  Desc2D.VertexInput.Attributes[2].Location := 2;
  Desc2D.VertexInput.Attributes[2].Binding := 0;
  Desc2D.VertexInput.Attributes[2].Format := vafUByte4Normalized;
  Desc2D.VertexInput.Attributes[2].Offset := 16;
  Desc2D.VertexInput.Attributes[2].AttributeName := 'aColor';
  Desc2D.DebugName := 'Prewarm2DBatchAlphaBlend';
  GetOrCreatePipeline(Desc2D);

  if (FPipelineCacheMisses > MissesBefore) and (EffectiveCacheUrl <> '') then
    SavePipelineCache(EffectiveCacheUrl);

  Result := GetPipelineCount;
end;

function TVulkanRHIDevice.GrabTextureImage(const SourceTexture: TRHITexture;
  const ReadArea: TRectangle): TRGBAlphaImage;
var
  VkTex: TVulkanRHITexture;
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  Region: VkBufferImageCopy;
  ByteSize: PtrUInt;
  MappedPixels: Pointer;
  RowY, ColX, SrcX, SrcY, SrcW, SrcH: Integer;
  SrcIndex, DstIndex, PixelIndex, TotalPixels: PtrUInt;
  DstPtr: PByte;
  DepthFloatPtr: PSingle;
  DepthU16Ptr: PWord;
  DepthU32Ptr: PCardinal;
  DByte: Byte;
  IsDepth: Boolean;
begin
  if (SourceTexture = nil) or (ReadArea.Width <= 0) or (ReadArea.Height <= 0) then
    Exit(nil);

  Result := TRGBAlphaImage.Create(ReadArea.Width, ReadArea.Height);
  VkTex := SourceTexture as TVulkanRHITexture;

  if (FDevice = nil) or not Assigned(vkCmdCopyImageToBuffer) then
  begin
    if Length(VkTex.FHostPixels) > 0 then
    begin
      SrcW := Max(1, Integer(VkTex.Desc.Width));
      SrcH := Max(1, Integer(VkTex.Desc.Height));
      DstPtr := PByte(Result.RawPixels);
      for RowY := 0 to ReadArea.Height - 1 do
        for ColX := 0 to ReadArea.Width - 1 do
        begin
          SrcX := EnsureRange(ReadArea.Left + ColX, 0, SrcW - 1);
          SrcY := EnsureRange(ReadArea.Bottom + RowY, 0, SrcH - 1);
          SrcIndex := (PtrUInt(SrcY) * PtrUInt(SrcW) + PtrUInt(SrcX)) * 4;
          DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
          if SrcIndex + 3 < PtrUInt(Length(VkTex.FHostPixels)) then
            Move(VkTex.FHostPixels[SrcIndex], DstPtr[DstIndex], 4);
        end;
    end;
    Exit;
  end;

  FlushStagingUploads;
  IsDepth := (VkTex.AspectMask and VK_IMAGE_ASPECT_DEPTH_BIT) <> 0;
  TotalPixels := PtrUInt(ReadArea.Width) * PtrUInt(ReadArea.Height);
  if IsDepth and (VkTex.Desc.Format = pfD16_UNorm) then
    ByteSize := TotalPixels * 2
  else
    ByteSize := TotalPixels * 4;
  StagingDesc := TRHIBufferDesc.Create(ByteSize, [buTransferDst], muGpuToCpu, 'GrabTextureStaging');
  StagingBuf := TVulkanRHIBuffer.Create(Self, StagingDesc, nil);
  try
    Cmd := BeginSingleTimeCommands;
    FillChar(Region, SizeOf(Region), 0);
    if IsDepth then
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_DEPTH_BIT
    else
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
    Region.imageSubresource.layerCount := 1;
    Region.imageOffset.x := Max(0, ReadArea.Left);
    Region.imageOffset.y := Max(0, ReadArea.Bottom);
    Region.imageExtent.width := ReadArea.Width;
    Region.imageExtent.height := ReadArea.Height;
    Region.imageExtent.depth := 1;

    vkCmdCopyImageToBuffer(Cmd, VkTex.Image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      StagingBuf.Handle, 1, @Region);
    EndSingleTimeCommands(Cmd);

    MappedPixels := StagingBuf.Map;
    try
      if IsDepth then
      begin
        DstPtr := PByte(Result.RawPixels);
        if VkTex.Desc.Format = pfD16_UNorm then
        begin
          DepthU16Ptr := PWord(MappedPixels);
          for PixelIndex := 0 to TotalPixels - 1 do
          begin
            DByte := Byte(DepthU16Ptr[PixelIndex] shr 8);
            DstPtr[PixelIndex * 4 + 0] := DByte;
            DstPtr[PixelIndex * 4 + 1] := DByte;
            DstPtr[PixelIndex * 4 + 2] := DByte;
            DstPtr[PixelIndex * 4 + 3] := 255;
          end;
        end else
        if VkTex.Desc.Format = pfD24_UNorm_S8_UInt then
        begin
          DepthU32Ptr := PCardinal(MappedPixels);
          for PixelIndex := 0 to TotalPixels - 1 do
          begin
            DByte := Byte((DepthU32Ptr[PixelIndex] shr 16) and $FF);
            DstPtr[PixelIndex * 4 + 0] := DByte;
            DstPtr[PixelIndex * 4 + 1] := DByte;
            DstPtr[PixelIndex * 4 + 2] := DByte;
            DstPtr[PixelIndex * 4 + 3] := 255;
          end;
        end else
        begin
          DepthFloatPtr := PSingle(MappedPixels);
          for PixelIndex := 0 to TotalPixels - 1 do
          begin
            DByte := Byte(Round(EnsureRange(DepthFloatPtr[PixelIndex], 0.0, 1.0) * 255.0));
            DstPtr[PixelIndex * 4 + 0] := DByte;
            DstPtr[PixelIndex * 4 + 1] := DByte;
            DstPtr[PixelIndex * 4 + 2] := DByte;
            DstPtr[PixelIndex * 4 + 3] := 255;
          end;
        end;
      end else
        Move(MappedPixels^, Result.RawPixels^, ByteSize);
    finally
      StagingBuf.Unmap;
    end;
  finally
    FreeAndNil(StagingBuf);
  end;
end;

procedure TVulkanRHIDevice.LoadPipelineCache(const CacheFileUrl: String);
var
  Stream: TStream;
  Blob: TBytes;
  CacheInfo: VkPipelineCacheCreateInfo;
begin
  if (FDevice = nil) or not Assigned(vkCreatePipelineCache) then Exit;
  try
    Stream := Download(CacheFileUrl);
    try
      if LoadPipelineCacheBlobFromStream(Stream, FCapabilities.VendorId, FDeviceId, Blob) then
      begin
        if FPipelineCache <> VK_NULL_HANDLE then
        begin
          vkDestroyPipelineCache(FDevice, FPipelineCache, nil);
          FPipelineCache := VK_NULL_HANDLE;
        end;
        FillChar(CacheInfo, SizeOf(CacheInfo), 0);
        CacheInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;
        CacheInfo.initialDataSize := Length(Blob);
        CacheInfo.pInitialData := @Blob[0];
        CheckVk(vkCreatePipelineCache(FDevice, @CacheInfo, nil, @FPipelineCache), 'vkCreatePipelineCache(Load)');
      end;
    finally
      FreeAndNil(Stream);
    end;
  except
    on E: Exception do
      WritelnLog('Vulkan', 'Could not load pipeline cache from "%s": %s', [CacheFileUrl, E.Message]);
  end;
end;

procedure TVulkanRHIDevice.SavePipelineCache(const CacheFileUrl: String);
var
  DataSize: PtrUInt;
  Blob: TBytes;
  Stream: TStream;
begin
  if (FDevice = nil) or (FPipelineCache = VK_NULL_HANDLE) or not Assigned(vkGetPipelineCacheData) then
    Exit;

  DataSize := 0;
  if vkGetPipelineCacheData(FDevice, FPipelineCache, @DataSize, nil) <> VK_SUCCESS then
    Exit;
  if DataSize = 0 then
    Exit;

  SetLength(Blob, DataSize);
  if vkGetPipelineCacheData(FDevice, FPipelineCache, @DataSize, @Blob[0]) <> VK_SUCCESS then
    Exit;

  try
    Stream := UrlSaveStream(CacheFileUrl);
    try
      SavePipelineCacheBlobToStream(Stream, FCapabilities.VendorId, FDeviceId, @Blob[0], DataSize);
    finally
      FreeAndNil(Stream);
    end;
  except
    on E: Exception do
      WritelnLog('Vulkan', 'Could not save pipeline cache to "%s": %s', [CacheFileUrl, E.Message]);
  end;
end;

function TVulkanRHIDevice.GetInformationString: String;
const
  Section = '----------------------------------------';

  function FormatVkVersion(const AVer: Cardinal): String;
  begin
    Result := Format('%d.%d.%d', [
      (AVer shr 22) and $3FF,
      (AVer shr 12) and $3FF,
      AVer and $FFF
    ]);
  end;

var
  UsedBytes, BudgetBytes: UInt64;
  UsedMB, BudgetMB: Cardinal;
  HasBudgetExt: Boolean;
begin
  HasBudgetExt := QueryMemoryBudget(UsedBytes, BudgetBytes, UsedMB, BudgetMB);
  Result :=
    'Vulkan RHI information:' + LineEnding +
    LineEnding +
    Section + LineEnding +
    'Basic information:' + LineEnding +
    LineEnding +
    '  Device name: ' + FCapabilities.DeviceName + LineEnding +
    '  Vendor ID: ' + IntToStr(FCapabilities.VendorId) + LineEnding +
    '  Device ID: ' + IntToStr(FDeviceId) + LineEnding +
    '  Instance API version: ' + FormatVkVersion(FInstanceApiVersion) + LineEnding +
    '  Device API version: ' + FormatVkVersion(FDeviceApiVersion) + LineEnding +
    LineEnding +
    Section + LineEnding +
    'Features:' + LineEnding +
    LineEnding +
    '  Dynamic rendering (VK_KHR_dynamic_rendering / 1.3): ' + BoolToStr(FSupportsDynamicRendering, True) + LineEnding +
    '  Graphics pipeline library (VK_EXT_graphics_pipeline_library): ' + BoolToStr(FSupportsGraphicsPipelineLibrary, True) + LineEnding +
    '  Extended dynamic state (VK_EXT_extended_dynamic_state / 1.3): ' + BoolToStr(FSupportsExtendedDynamicState, True) + LineEnding +
    '  Synchronization2 (VK_KHR_synchronization2 / 1.3): ' + BoolToStr(FSupportsSynchronization2, True) + LineEnding +
    '  Timeline semaphores (VK_KHR_timeline_semaphore / 1.2): ' + BoolToStr(FSupportsTimelineSemaphores, True) + LineEnding +
    '  Compute shaders: ' + BoolToStr(FCapabilities.SupportsComputeShaders, True) + LineEnding +
    '  Multi-draw indirect: ' + BoolToStr(FCapabilities.SupportsMultiDrawIndirect, True) + LineEnding +
    '  Draw indirect count (VK_KHR_draw_indirect_count / 1.2): ' + BoolToStr(FCapabilities.SupportsDrawIndirectCount, True) + LineEnding +
    '  Bindless textures (VK_EXT_descriptor_indexing / 1.2): ' + BoolToStr(FSupportsBindlessTextures, True) +
      Format(' (max: %d)', [FMaxBindlessTextures]) + LineEnding +
    '  Dedicated DMA transfer queue: ' + BoolToStr(FHasDedicatedTransferQueue, True) + LineEnding +
    LineEnding +
    Section + LineEnding +
    'Limits & Pipelines:' + LineEnding +
    LineEnding +
    '  Max texture size: ' + IntToStr(FCapabilities.MaxTextureSize) + LineEnding +
    '  Max framebuffer MSAA samples: ' + IntToStr(FCapabilities.MaxFramebufferSampleCount) +
      Format(' (active: %d)', [FSampleCount]) + LineEnding +
    '  Cached graphics pipelines: ' + IntToStr(GetPipelineCount) +
      Format(' (hits: %d, misses: %d)', [FPipelineCacheHits, FPipelineCacheMisses]) + LineEnding +
    '  Cached compute pipelines: ' + IntToStr(GetComputePipelineCount) + LineEnding +
    LineEnding +
    Section + LineEnding +
    'Memory:' + LineEnding +
    LineEnding +
    '  VK_EXT_memory_budget available: ' + BoolToStr(HasBudgetExt, True) + LineEnding +
    Format('  Used video memory: %d mb (%d kb)', [UsedMB, UsedBytes div 1024]) + LineEnding +
    Format('  Total video memory budget: %d mb (%d kb)', [BudgetMB, BudgetBytes div 1024]);
end;

function TVulkanRHIDevice.GetInformationStringSummary: String;
var
  MajorVer, MinorVer: Cardinal;
  DevStr: String;
begin
  MajorVer := (FDeviceApiVersion shr 22) and $3FF;
  MinorVer := (FDeviceApiVersion shr 12) and $3FF;
  if FCapabilities.DeviceName <> '' then
    DevStr := ' (' + FCapabilities.DeviceName + ')'
  else
    DevStr := '';
  Result := Format('Vulkan %d.%d%s (modern rendering: True)', [
    MajorVer,
    MinorVer,
    DevStr
  ]);
end;

function TVulkanRHIDevice.BeginSingleTimeCommands: VkCommandBuffer;
var
  AllocInfo: VkCommandBufferAllocateInfo;
  BeginInfo: VkCommandBufferBeginInfo;
begin
  Result := nil;
  if (FDevice = nil) or (FFrames[0].CommandList = nil) then Exit;

  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  AllocInfo.commandPool := FFrames[0].CommandList.FCommandPool;
  AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  AllocInfo.commandBufferCount := 1;
  CheckVk(vkAllocateCommandBuffers(FDevice, @AllocInfo, @Result), 'vkAllocateCommandBuffers(SingleTime)');

  FillChar(BeginInfo, SizeOf(BeginInfo), 0);
  BeginInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  BeginInfo.flags := VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  CheckVk(vkBeginCommandBuffer(Result, @BeginInfo), 'vkBeginCommandBuffer(SingleTime)');
end;

procedure TVulkanRHIDevice.EndSingleTimeCommands(const CmdBuf: VkCommandBuffer);
var
  SubmitInfo: VkSubmitInfo;
  LocalCmd: VkCommandBuffer;
begin
  if (FDevice = nil) or (CmdBuf = nil) then Exit;
  CheckVk(vkEndCommandBuffer(CmdBuf), 'vkEndCommandBuffer(SingleTime)');

  LocalCmd := CmdBuf;
  FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
  SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
  SubmitInfo.commandBufferCount := 1;
  SubmitInfo.pCommandBuffers := @LocalCmd;

  CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, VK_NULL_HANDLE), 'vkQueueSubmit(SingleTime)');
  CheckVk(vkQueueWaitIdle(FGraphicsQueue), 'vkQueueWaitIdle(SingleTime)');

  vkFreeCommandBuffers(FDevice, FFrames[0].CommandList.FCommandPool, 1, @LocalCmd);
end;

function TVulkanRHIDevice.FindMemoryType(const TypeFilter: Cardinal;
  const Properties: VkMemoryPropertyFlags): Cardinal;
var
  MemProps: VkPhysicalDeviceMemoryProperties;
  I: Cardinal;
begin
  vkGetPhysicalDeviceMemoryProperties(FPhysicalDevice, @MemProps);
  for I := 0 to MemProps.memoryTypeCount - 1 do
    if ((TypeFilter and (1 shl I)) <> 0) and
       ((MemProps.memoryTypes[I].propertyFlags and Properties) = Properties) then
      Exit(I);

  raise ERHIOutOfMemory.Create('Failed to find suitable Vulkan memory type');
end;

end.
