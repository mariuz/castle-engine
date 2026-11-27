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
    FDeviceAddress: UInt64;
    function VulkanDevice: TVulkanRHIDevice;
    function BuildVkUsageFlags: VkBufferUsageFlags;
    procedure RelocateToAllocation(const ANewHandle: VkBuffer;
      const ANewAlloc: TVulkanMemoryAllocation);
  protected
    procedure ReleaseDeviceResources; override;
    function GetDeviceAddress: UInt64; override;
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

  TVulkanSubresourceViewEntry = record
    MipLevel: Cardinal;
    ArrayLayer: Cardinal;
    View: VkImageView;
  end;

  TVulkanRHITexture = class(TRHITexture)
  private
    FImage: VkImage;
    FImageView: VkImageView;
    FSubresourceViews: array of TVulkanSubresourceViewEntry;
    FAllocation: TVulkanMemoryAllocation;
    FDeviceMemory: VkDeviceMemory;
    FMemoryOffset: VkDeviceSize;
    FAllocatedSize: VkDeviceSize;
    FOwnsImage: Boolean;
    FOwnsAllocation: Boolean;
    FAspectMask: VkImageAspectFlags;
    FViewAspectMask: VkImageAspectFlags;
    FHostPixels: array of Byte;
    FTotalSubresourceUploads: Cardinal;
    FMaxUploadedMipLevel: Cardinal;
    FMaxUploadedArrayLayer: Cardinal;
    FMipmapGenerationCount: Cardinal;
    FLastGeneratedMipLevels: Cardinal;
    FLastRenderedMipLevel: Cardinal;
    FLastRenderedArrayLayer: Cardinal;
    FRenderedLayerMask: Cardinal;
    FPresentReadbackShadow: TVulkanRHITexture;
    FPresentReadbackStaging: TVulkanRHIBuffer;
    FMip0FacePixels: array[0..5] of array of Byte;
    function VulkanDevice: TVulkanRHIDevice;
    function GetSubresourceViewCount: Cardinal;
    procedure RecordVkMipmapBlits(const ACmd: VkCommandBuffer);
    function TryUploadPortabilityCubeMipmapsFromHost: Boolean;
  protected
    procedure ReleaseDeviceResources; override;
    function GetRenderedLayerMask: Cardinal; override;
  public
    { Standard constructor that allocates a new VkImage and VkImageView }
    constructor Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHITextureDesc); overload;
    { Carrier constructor (VK_IMAGE_CREATE_ALIAS_BIT) backed by at least AMinCarrierBytes for RenderGraph aliasing }
    constructor CreateCarrier(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHITextureDesc; const AMinCarrierBytes: UInt64); overload;
    { Wrapper constructor for existing VkSwapchainKHR images }
    constructor CreateSwapchainWrapper(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHITextureDesc; const AExistingImage: VkImage;
      const AExistingView: VkImageView); overload;
    { Attempts to create an aliased VkImage + VkImageView bound to ACarrier's physical VkDeviceMemory }
    class function TryCreateAliased(const ADevice: TVulkanRHIDevice;
      const ADesc: TRHITextureDesc; const ACarrier: TVulkanRHITexture): TVulkanRHITexture;
    destructor Destroy; override;

    procedure UploadImage(const AImage: TEncodedImage;
      const AMipLevel: Cardinal = 0; const AArrayLayer: Cardinal = 0); override;
    procedure GenerateMipmaps; override;
    function GetSubresourceImageView(const AMipLevel, AArrayLayer: Cardinal): VkImageView;
    procedure SetHostClearColor(const AColor: TCastleColor);
    procedure SetHostClearColorRect(const AColor: TCastleColor; const ARect: TRectangle);
    procedure SetHostClearDepth(const ADepth: Single);

    property Image: VkImage read FImage;
    property ImageView: VkImageView read FImageView;
    property Allocation: TVulkanMemoryAllocation read FAllocation;
    property DeviceMemory: VkDeviceMemory read FDeviceMemory;
    property MemoryOffset: VkDeviceSize read FMemoryOffset;
    property AllocatedSize: VkDeviceSize read FAllocatedSize;
    property OwnsAllocation: Boolean read FOwnsAllocation;
    { Full aspect mask used for VkImageMemoryBarrier transitions (DEPTH | STENCIL for combined formats) }
    property AspectMask: VkImageAspectFlags read FAspectMask;
    { Aspect mask used for VkImageView creation (DEPTH-only when sampled in shaders) }
    property ViewAspectMask: VkImageAspectFlags read FViewAspectMask;
    property TotalSubresourceUploads: Cardinal read FTotalSubresourceUploads;
    property MaxUploadedMipLevel: Cardinal read FMaxUploadedMipLevel;
    property MaxUploadedArrayLayer: Cardinal read FMaxUploadedArrayLayer;
    property MipmapGenerationCount: Cardinal read FMipmapGenerationCount;
    property LastGeneratedMipLevels: Cardinal read FLastGeneratedMipLevels;
    property SubresourceViewCount: Cardinal read GetSubresourceViewCount;
    property LastRenderedMipLevel: Cardinal read FLastRenderedMipLevel;
    property LastRenderedArrayLayer: Cardinal read FLastRenderedArrayLayer;
    property RenderedLayerMask: Cardinal read FRenderedLayerMask;
  end;

  TVulkanRHISampler = class(TRHISampler)
  private
    FHandle: VkSampler;
    FCreateInfo: VkSamplerCreateInfo;
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHISamplerDesc);
    destructor Destroy; override;
    property Handle: VkSampler read FHandle;
    property CreateInfo: VkSamplerCreateInfo read FCreateInfo;
  end;

  TVulkanRHIShaderModule = class(TRHIShaderModule)
  private
    FHandle: VkShaderModule;
    FReflection: TSPIRVReflectionInfo;
  protected
    procedure ReleaseDeviceResources; override;
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
    FAllBindingsUpdateAfterBind: Boolean;
    FBindings: array of TRHIDescriptorBindingDesc;
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const Bindings: array of TRHIDescriptorBindingDesc);
    destructor Destroy; override;
    function TryGetBindingType(const ABinding: Cardinal;
      out ADescriptorType: TRHIDescriptorType): Boolean;
    property Handle: VkDescriptorSetLayout read FHandle;
    property UsesUpdateAfterBind: Boolean read FUsesUpdateAfterBind;
    property AllBindingsUpdateAfterBind: Boolean read FAllBindingsUpdateAfterBind;
  end;

  TVulkanDescriptorPoolAllocator = class;

  TVulkanBoundBufferEntry = record
    Binding: Cardinal;
    IsStorage: Boolean;
    Buffer: TVulkanRHIBuffer;
    Offset: PtrUInt;
    Range: PtrUInt;
  end;

  TVulkanCommittedDescriptorEntry = record
    Binding: Cardinal;
    ArrayElement: Cardinal;
    DescriptorType: VkDescriptorType;
    BufferObj: TVulkanRHIBuffer;
    BufferHandle: VkBuffer;
    BufferOffset: VkDeviceSize;
    BufferRange: VkDeviceSize;
    TextureObj: TVulkanRHITexture;
    ImageView: VkImageView;
    Sampler: VkSampler;
    ImageLayout: VkImageLayout;
    AccelStructHandle: VkAccelerationStructureKHR;
  end;

  TVulkanRHIDescriptorSet = class(TRHIDescriptorSet)
  private
    FHandle: VkDescriptorSet;
    FOwnerPool: VkDescriptorPool;
    FIsTransient: Boolean;
    FUsesCustomPool: Boolean;
    FBoundIdleEpoch: UInt64;
    FLayout: TVulkanRHIDescriptorSetLayout;
    FPendingWrites: array of VkWriteDescriptorSet;
    FPendingWriteInfoIndices: array of Integer;
    FBufferInfos: array of VkDescriptorBufferInfo;
    FImageInfos: array of VkDescriptorImageInfo;
    FAccelStructHandles: array of VkAccelerationStructureKHR;
    FAccelStructWrites: array of VkWriteDescriptorSetAccelerationStructureKHR;
    FBoundBuffers: array of TVulkanBoundBufferEntry;
    FCommittedEntries: array of TVulkanCommittedDescriptorEntry;
    FUpdateCount: Cardinal;
    FLastBoundTexture: TRHITexture;
    FLastBoundSampler: TRHISampler;
    function VulkanDevice: TVulkanRHIDevice;
    procedure RecordBoundBuffer(const ABinding: Cardinal; const AIsStorage: Boolean;
      const ABuffer: TVulkanRHIBuffer; const AOffset, ARange: PtrUInt);
    procedure RecordCommittedBuffer(const ABinding: Cardinal;
      const ADescType: VkDescriptorType; const ABuffer: TVulkanRHIBuffer;
      const AOffset, ARange: VkDeviceSize);
    procedure RecordCommittedImage(const ABinding, AArrayElement: Cardinal;
      const ADescType: VkDescriptorType; const ATexture: TVulkanRHITexture;
      const AImageView: VkImageView; const ASampler: VkSampler;
      const AImageLayout: VkImageLayout);
    procedure RecordCommittedAccelStruct(const ABinding: Cardinal;
      const AAccelStruct: VkAccelerationStructureKHR);
    procedure ClearBoundBuffer(const ABuffer: TVulkanRHIBuffer);
    procedure ClearBoundTexture(const ATexture: TVulkanRHITexture);
    procedure RefreshRelocatedBuffer(const ABuffer: TVulkanRHIBuffer);
    procedure MarkBoundToLiveCommandBuffer;
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const ALayout: TVulkanRHIDescriptorSetLayout;
      const AIsTransient: Boolean = False);
    constructor CreateFromCustomPool(const ADevice: TVulkanRHIDevice;
      const ALayout: TVulkanRHIDescriptorSetLayout;
      const ACustomPool: VkDescriptorPool);
    destructor Destroy; override;

    procedure BindUniformBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); override;
    procedure BindStorageBuffer(const Binding: Cardinal; const Buffer: TRHIBuffer;
      const Offset: PtrUInt = 0; const Range: PtrUInt = 0); override;
    procedure BindTexture(const Binding: Cardinal; const Texture: TRHITexture;
      const Sampler: TRHISampler); override;
    procedure BindTextureAtIndex(const Binding, ArrayElement: Cardinal;
      const Texture: TRHITexture; const Sampler: TRHISampler); override;
    procedure BindTextureSubresource(const Binding: Cardinal;
      const Texture: TRHITexture; const MipLevel, ArrayLayer: Cardinal;
      const Sampler: TRHISampler = nil); override;
    procedure BindAccelerationStructure(const Binding: Cardinal;
      const AAccelerationStructure: VkAccelerationStructureKHR);
    procedure Update; override;

    property Handle: VkDescriptorSet read FHandle;
    property OwnerPool: VkDescriptorPool read FOwnerPool;
    property IsTransient: Boolean read FIsTransient;
    property UpdateCount: Cardinal read FUpdateCount;
    property LastBoundTexture: TRHITexture read FLastBoundTexture;
    property LastBoundSampler: TRHISampler read FLastBoundSampler;
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
  protected
    procedure ReleaseDeviceResources; override;
  public
    constructor Create(const ADevice: TVulkanRHIDevice;
      const AInputDesc: TRHIGraphicsPipelineDesc);
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
  protected
    procedure ReleaseDeviceResources; override;
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
    FQueryResetReady: array of Boolean;
    FQueryRecordedGeneration: array of UInt64;
    FQueryActiveInCmd: array of Boolean;
    FResetCount: Cardinal;
    FHostResetCount: Cardinal;
  protected
    procedure ReleaseDeviceResources; override;
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
    property HostResetCount: Cardinal read FHostResetCount;
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
    FAliasingBarrierCount: Cardinal;
    FComputeDispatchCount: Cardinal;
    FDynamicStateChangeCount: Cardinal;
    FIndirectDrawCallCount: Cardinal;
    FIndirectCountDrawCallCount: Cardinal;
    FMeshTasksDrawCallCount: Cardinal;
    FLastEffectiveIndirectDrawCount: Cardinal;
    FClearAttachmentCallCount: Cardinal;
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
    FDynamicLineWidth: Single;
    FLineWidthUpdateCount: Cardinal;
    FDynamicBlendConstants: TVector4;
    FBlendConstantsUpdateCount: Cardinal;
    FBoundDescriptorSets: array[0..3] of TRHIDescriptorSet;
    FDescriptorSetBindCount: Cardinal;
    FPipelineBindCount: Cardinal;
    FLastPushConstantStageFlags: TRHIShaderStageFlags;
    FLastPushConstantSize: Cardinal;
    FPushConstantCallCount: Cardinal;
    FActiveRenderingWidth: Cardinal;
    FActiveRenderingHeight: Cardinal;
    FLastVkViewportY: Single;
    FLastVkScissorOffsetY: Integer;
    FViewportPendingReapply: Boolean;
    FScissorPendingReapply: Boolean;
    FOwnsCommandPool: Boolean;
    FResetIndividualBuffer: Boolean;
    FSecondaryExecuteCount: Cardinal;
    FDebugGroupPushCount: Cardinal;
    FDebugGroupPopCount: Cardinal;
    FDebugMarkerCount: Cardinal;
    FLastDebugLabelName: String;
    FRecordingGeneration: UInt64;
    procedure ResetCommandTrackingState;
    function GetBoundDescriptorSet(const ASetIndex: Cardinal): TRHIDescriptorSet;
    procedure ComputeVkScissorRect(const ARect: TRectangle; out AVkRect: VkRect2D);
  public
    constructor Create(const ADevice: TVulkanRHIDevice; const AQueueFamilyIndex: Cardinal;
      const ALevel: TRHICommandListLevel = cllPrimary); overload;
    constructor CreateFromPool(const ADevice: TVulkanRHIDevice;
      const ACommandPool: VkCommandPool;
      const ALevel: TRHICommandListLevel = cllSecondary;
      const AResetIndividualBuffer: Boolean = False); overload;
    destructor Destroy; override;

    procedure BeginRecording; override;
    procedure BeginSecondaryRecording(const AInheritedInfo: TRHIRenderingInfo;
      const AViewportRect: TFloatRectangle; const AScissorRect: TRectangle;
      const AMinDepth: Single = 0.0; const AMaxDepth: Single = 1.0); overload; override;
    procedure EndRecording; override;

    procedure TransitionTexture(const Texture: TRHITexture;
      const NewState: TRHIResourceState); override;
    procedure EmitAliasingBarrier(const OldTexture, NewTexture: TRHITexture); override;
    procedure TransitionBuffer(const Buffer: TRHIBuffer;
      const OldState, NewState: TRHIResourceState);
    procedure GenerateMipmaps(const Texture: TRHITexture); override;

    procedure BeginRendering(const Info: TRHIRenderingInfo); override;
    procedure EndRendering; override;

    procedure SetViewport(const ViewportRect: TFloatRectangle;
      const MinDepth: Single = 0.0; const MaxDepth: Single = 1.0); override;
    procedure SetScissor(const ScissorRect: TRectangle); override;
    procedure SetDepthBias(const ConstantFactor, SlopeFactor: Single); override;
    procedure SetLineWidth(const LineWidth: Single); override;
    procedure SetBlendConstants(const ABlendConstants: TVector4); override;

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
    procedure DrawMeshTasks(const GroupCountX: Cardinal;
      const GroupCountY: Cardinal = 1; const GroupCountZ: Cardinal = 1); override;
    procedure DrawMeshTasksIndirect(const IndirectBuffer: TRHIBuffer;
      const Offset: PtrUInt; const DrawCount: Cardinal = 1;
      const Stride: Cardinal = 12); override;

    procedure ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList); override;
    procedure ExecuteSecondaryCommandsInPass(
      const SecondaryCommandLists: array of TRHICommandList); override;

    procedure PushDebugGroup(const LabelName: String; const Color: TCastleColor); override;
    procedure PopDebugGroup; override;
    procedure InsertDebugMarker(const LabelName: String; const Color: TCastleColor); override;
    procedure ClearAttachments(const ClearColorBuf: Boolean; const ClearColor: TCastleColor;
      const ClearDepthBuf: Boolean = False; const ClearDepth: Single = 1.0;
      const ClearStencilBuf: Boolean = False; const ClearStencil: Byte = 0); override;

    property Handle: VkCommandBuffer read FHandle;
    property CommandPool: VkCommandPool read FCommandPool;
    property SecondaryExecuteCount: Cardinal read FSecondaryExecuteCount;
    property DebugGroupPushCount: Cardinal read FDebugGroupPushCount;
    property DebugGroupPopCount: Cardinal read FDebugGroupPopCount;
    property DebugMarkerCount: Cardinal read FDebugMarkerCount;
    property LastDebugLabelName: String read FLastDebugLabelName;
    property InFallbackRenderPass: Boolean read FInFallbackRenderPass;
    property BarrierCount: Cardinal read FBarrierCount;
    property Sync2BarrierCount: Cardinal read FSync2BarrierCount;
    property AliasingBarrierCount: Cardinal read FAliasingBarrierCount;
    property ComputeDispatchCount: Cardinal read FComputeDispatchCount;
    property DynamicStateChangeCount: Cardinal read FDynamicStateChangeCount;
    property IndirectDrawCallCount: Cardinal read FIndirectDrawCallCount;
    property IndirectCountDrawCallCount: Cardinal read FIndirectCountDrawCallCount;
    property MeshTasksDrawCallCount: Cardinal read FMeshTasksDrawCallCount;
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
    property DynamicLineWidth: Single read FDynamicLineWidth;
    property LineWidthUpdateCount: Cardinal read FLineWidthUpdateCount;
    property DynamicBlendConstants: TVector4 read FDynamicBlendConstants;
    property BlendConstantsUpdateCount: Cardinal read FBlendConstantsUpdateCount;
    property BoundDescriptorSets[const ASetIndex: Cardinal]: TRHIDescriptorSet read GetBoundDescriptorSet;
    property DescriptorSetBindCount: Cardinal read FDescriptorSetBindCount;
    property BoundPipeline: TVulkanRHIPipeline read FCurrentPipeline;
    property PipelineBindCount: Cardinal read FPipelineBindCount;
    property LastPushConstantStageFlags: TRHIShaderStageFlags read FLastPushConstantStageFlags;
    property LastPushConstantSize: Cardinal read FLastPushConstantSize;
    property PushConstantCallCount: Cardinal read FPushConstantCallCount;
    property ClearAttachmentCallCount: Cardinal read FClearAttachmentCallCount;
    property ActiveRenderingWidth: Cardinal read FActiveRenderingWidth;
    property ActiveRenderingHeight: Cardinal read FActiveRenderingHeight;
    property LastVkViewportY: Single read FLastVkViewportY;
    property LastVkScissorOffsetY: Integer read FLastVkScissorOffsetY;
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
{$endif read_interface}

{$ifdef read_implementation}
{ ---------------------------------------------------------------------------- }
{ TVulkanRHIBuffer                                                             }
{ ---------------------------------------------------------------------------- }

function TVulkanRHIBuffer.VulkanDevice: TVulkanRHIDevice;
begin
  Result := TVulkanRHIDevice(Device);
end;

function TVulkanRHIBuffer.BuildVkUsageFlags: VkBufferUsageFlags;
var
  ADevice: TVulkanRHIDevice;
begin
  Result := 0;
  ADevice := VulkanDevice;
  if buVertex in FDesc.Usage then Result := Result or VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
  if buIndex in FDesc.Usage then Result := Result or VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
  if buUniform in FDesc.Usage then Result := Result or VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
  if buStorage in FDesc.Usage then Result := Result or VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
  if buIndirect in FDesc.Usage then Result := Result or VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
  if buTransferSrc in FDesc.Usage then Result := Result or VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
  if (buTransferDst in FDesc.Usage) or (FDesc.MemoryUsage = muGpuOnly) then
    Result := Result or VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  if not (buAccelerationStructureStorage in FDesc.Usage) then
    Result := Result or VK_BUFFER_USAGE_TRANSFER_SRC_BIT or VK_BUFFER_USAGE_TRANSFER_DST_BIT;
  if (ADevice <> nil) and ADevice.SupportsBufferDeviceAddress and
     ((buShaderDeviceAddress in FDesc.Usage) or
      (buAccelerationStructureBuildInput in FDesc.Usage) or
      (buAccelerationStructureStorage in FDesc.Usage) or
      (buShaderBindingTable in FDesc.Usage)) then
    Result := Result or VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
  if (ADevice <> nil) and ADevice.SupportsAccelerationStructure and
     (buAccelerationStructureBuildInput in FDesc.Usage) then
    Result := Result or VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR;
  if (ADevice <> nil) and ADevice.SupportsAccelerationStructure and
     (buAccelerationStructureStorage in FDesc.Usage) then
    Result := Result or VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR;
  if (ADevice <> nil) and ADevice.SupportsRayTracingPipeline and
     (buShaderBindingTable in FDesc.Usage) then
    Result := Result or VK_BUFFER_USAGE_SHADER_BINDING_TABLE_BIT_KHR;
end;

procedure TVulkanRHIBuffer.RelocateToAllocation(const ANewHandle: VkBuffer;
  const ANewAlloc: TVulkanMemoryAllocation);
begin
  FHandle := ANewHandle;
  FAllocation := ANewAlloc;
  FDeviceMemory := ANewAlloc.DeviceMemory;
  FMemoryOffset := ANewAlloc.Offset;
  FAllocatedSize := ANewAlloc.Size;
  FMappedPtr := ANewAlloc.MappedPtr;
  FDeviceAddress := 0;
  if (VulkanDevice <> nil) and (FDesc.DebugName <> '') and (FHandle <> VK_NULL_HANDLE) then
    VulkanDevice.SetDebugObjectName(VK_OBJECT_TYPE_BUFFER, FHandle, FDesc.DebugName);
end;

constructor TVulkanRHIBuffer.Create(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHIBufferDesc; const InitialData: Pointer);
var
  BufInfo: VkBufferCreateInfo;
  MemReq: VkMemoryRequirements;
  AllocInfo: VkMemoryAllocateInfo;
  MemProps: VkMemoryPropertyFlags;
  RequiredAlign: VkDeviceSize;
  MovableOwner: Pointer;
  ForceDedicatedBuf: Boolean;
begin
  inherited Create(ADevice, ADesc);

  if (ADevice <> nil) and (ADevice.Handle <> nil) and Assigned(vkCreateBuffer) then
  begin
    FillChar(BufInfo, SizeOf(BufInfo), 0);
    BufInfo.sType := VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    { Pad underlying VkBuffer / MTLBuffer size to at least 16-byte alignment on real GPUs
      (e.g. 12-byte 6-index UInt16 quad IBOs on Apple Paravirtual / Metal) while keeping FDesc.Size exact. }
    BufInfo.size := Max(VkDeviceSize(16), (VkDeviceSize(ADesc.Size) + 15) and not VkDeviceSize(15));
    BufInfo.sharingMode := VK_SHARING_MODE_EXCLUSIVE;
    BufInfo.usage := BuildVkUsageFlags;

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
    if buAccelerationStructureStorage in ADesc.Usage then
      RequiredAlign := Max(RequiredAlign, VkDeviceSize(256));
    if buShaderBindingTable in ADesc.Usage then
      RequiredAlign := Max(RequiredAlign, VkDeviceSize(64));

    if buAccelerationStructureStorage in ADesc.Usage then
      MovableOwner := nil
    else
      MovableOwner := Self;

    { Sub-allocate from pooled VkDeviceMemory blocks via TCastleVulkanMemoryAllocator
      to stay well below Windows WDDM's 4096 maxMemoryAllocationCount limit.
      On live Portability Subset / MoltenVK devices (where maxMemoryAllocationCount is unlimited
      and Apple Paravirtual MTLHeap / shared-block sub-allocation at non-zero offsets can truncate),
      use 1:1 dedicated MTLBuffer allocations at offset 0 unless small defragmentation test blocks are configured. }
    ForceDedicatedBuf := (ADevice.Handle <> nil) and ADevice.IsPortabilitySubsetDevice and
      (ADevice.MemoryAllocator.PreferredGpuOnlyBlockSize >= 16 * 1024 * 1024);
    FAllocation := ADevice.MemoryAllocator.AllocateBufferMemory(
      FHandle, ADesc.Size, ADesc.MemoryUsage, ForceDedicatedBuf, RequiredAlign, MovableOwner);
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

  if (ADevice <> nil) and (ADesc.DebugName <> '') and (FHandle <> VK_NULL_HANDLE) then
    ADevice.SetDebugObjectName(VK_OBJECT_TYPE_BUFFER, FHandle, ADesc.DebugName);

  if InitialData <> nil then
    UploadData(InitialData^, ADesc.Size, 0);
end;

procedure TVulkanRHIBuffer.ReleaseDeviceResources;
begin
  if FMappedPtr <> nil then
    Unmap;
  if VulkanDevice <> nil then
  begin
    VulkanDevice.UnbindDestroyedBufferFromDescriptorSets(Self);
    if VulkanDevice.StagingUploader <> nil then
      VulkanDevice.StagingUploader.CancelPendingUploadsForBuffer(Self);
    if (FHandle <> VK_NULL_HANDLE) or (FDeviceMemory <> VK_NULL_HANDLE) or (FAllocatedSize > 0) then
      VulkanDevice.DeferOrDestroyBuffer(FHandle, FAllocation, FDeviceMemory, FAllocatedSize);
  end;
  FHandle := VK_NULL_HANDLE;
  FillChar(FAllocation, SizeOf(FAllocation), 0);
  FDeviceMemory := VK_NULL_HANDLE;
  FAllocatedSize := 0;
end;

function TVulkanRHIBuffer.GetDeviceAddress: UInt64;
var
  AddrInfo: VkBufferDeviceAddressInfo;
begin
  if FDeviceAddress <> 0 then
    Exit(FDeviceAddress);
  if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and
     VulkanDevice.SupportsBufferDeviceAddress and (FHandle <> VK_NULL_HANDLE) and
     ((BuildVkUsageFlags and VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT) <> 0) and
     Assigned(vkGetBufferDeviceAddress) then
  begin
    FillChar(AddrInfo, SizeOf(AddrInfo), 0);
    AddrInfo.sType := VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO;
    AddrInfo.buffer := FHandle;
    FDeviceAddress := vkGetBufferDeviceAddress(VulkanDevice.Handle, @AddrInfo);
    Exit(FDeviceAddress);
  end;
  if (buShaderDeviceAddress in FDesc.Usage) or
     (buAccelerationStructureBuildInput in FDesc.Usage) or
     (buAccelerationStructureStorage in FDesc.Usage) or
     (buShaderBindingTable in FDesc.Usage) then
    FDeviceAddress := UInt64($100000000) + ((UInt64(PtrUInt(Self)) shl 8) and UInt64($0000FFFFFFFFF000));
  Result := FDeviceAddress;
end;

destructor TVulkanRHIBuffer.Destroy;
begin
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
  BufBarrier: VkBufferMemoryBarrier;
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
  if (VulkanDevice <> nil) and (VulkanDevice.StagingUploader <> nil) and
     not ((VulkanDevice.Handle <> nil) and (ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
  begin
    { Stage into persistent per-frame staging ring buffer for non-blocking batched upload }
    VulkanDevice.StagingUploader.EnqueueBufferUpload(Self, Data, Size, Offset);
  end else
  if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and Assigned(vkCmdCopyBuffer) then
  begin
    { Immediate one-shot upload when StagingUploader is absent or when uploading mid-render-pass on a real GPU }
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
      if Assigned(vkCmdPipelineBarrier) then
      begin
        FillChar(BufBarrier, SizeOf(BufBarrier), 0);
        BufBarrier.sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        BufBarrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
        BufBarrier.dstAccessMask :=
          VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT or
          VK_ACCESS_INDEX_READ_BIT or
          VK_ACCESS_UNIFORM_READ_BIT or
          VK_ACCESS_SHADER_READ_BIT;
        BufBarrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        BufBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        BufBarrier.buffer := FHandle;
        BufBarrier.offset := Offset;
        BufBarrier.size := Size;
        vkCmdPipelineBarrier(Cmd,
          VK_PIPELINE_STAGE_TRANSFER_BIT,
          VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
          VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
          0, 0, nil, 1, @BufBarrier, 0, nil);
      end;
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
  FmtProps: VkFormatProperties;
  ApproxBytes: VkDeviceSize;
begin
  NegotiatedDesc := ADesc;
  if NegotiatedDesc.SampleCount = 0 then
    NegotiatedDesc.SampleCount := 1;
  if ADevice <> nil then
  begin
    if (ADevice.Handle <> nil) or (not IsVulkanInstanceLoaded) then
      NegotiatedDesc.Format := NegotiateOptimalPixelFormat(
        ADesc.Format, ADesc.Usage, ADevice.PhysicalDevice)
    else
      NegotiatedDesc.Format := NegotiateOptimalPixelFormat(
        ADesc.Format, ADesc.Usage, nil);
    if ADevice.Capabilities.MaxFramebufferSampleCount > 0 then
      NegotiatedDesc.SampleCount := ClampSampleCountToCapabilities(
        NegotiatedDesc.SampleCount, ADevice.Capabilities.MaxFramebufferSampleCount);
  end;
  { Per VUID-VkImageCreateInfo-samples-02257, multisampled images must have mipLevels = 1 }
  if NegotiatedDesc.SampleCount > 1 then
    NegotiatedDesc.MipLevels := 1;

  inherited Create(ADevice, NegotiatedDesc);
  FOwnsImage := True;
  FOwnsAllocation := True;

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
      FMemoryOffset := FAllocation.Offset;
      FAllocatedSize := FAllocation.Size;
      Inc(ADevice.FAllocatedMemoryBytes, FAllocatedSize);
    end;
    if (ADevice <> nil) and (FDesc.DebugName <> '') then
    begin
      ADevice.SetDebugObjectName(VK_OBJECT_TYPE_IMAGE, FImage, FDesc.DebugName);
      ADevice.SetDebugObjectName(VK_OBJECT_TYPE_IMAGE_VIEW, FImageView, FDesc.DebugName + '.View');
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
  if tuStorage in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_STORAGE_BIT;
  if tuColorAttachment in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  if tuDepthStencil in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
  if tuTransferSrc in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  if tuTransferDst in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  { On Metal / MoltenVK (Portability Subset), scaled vkCmdBlitImage mipmap generation renders
    via an internal MTLRenderCommandEncoder when MTLBlitCommandEncoder cannot filter-scale;
    include COLOR_ATTACHMENT_BIT when supported by the optimal-tiling format so MTLTextureUsageRenderTarget is set. }
  if ADevice.IsPortabilitySubsetDevice and (FDesc.MipLevels > 1) and
     (tuTransferSrc in FDesc.Usage) and (tuTransferDst in FDesc.Usage) and
     ((ImgInfo.usage and VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) = 0) and
     (ADevice.PhysicalDevice <> nil) and Assigned(vkGetPhysicalDeviceFormatProperties) then
  begin
    FillChar(FmtProps, SizeOf(FmtProps), 0);
    vkGetPhysicalDeviceFormatProperties(ADevice.PhysicalDevice, ImgInfo.format, @FmtProps);
    if (FmtProps.optimalTilingFeatures and VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT) <> 0 then
      ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  end;

  CheckVk(vkCreateImage(ADevice.Handle, @ImgInfo, nil, @FImage), 'vkCreateImage');

  if ADevice.MemoryAllocator <> nil then
  begin
    { Sub-allocate from Non-Linear optimal-image pool via TCastleVulkanMemoryAllocator
      (or dedicated allocation if VK_KHR_dedicated_allocation recommends it for render targets) }
    FAllocation := ADevice.MemoryAllocator.AllocateImageMemory(
      FImage, ApproxBytes, muGpuOnly, True, False);
    FDeviceMemory := FAllocation.DeviceMemory;
    FMemoryOffset := FAllocation.Offset;
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
  if FDesc.DebugName <> '' then
  begin
    ADevice.SetDebugObjectName(VK_OBJECT_TYPE_IMAGE, FImage, FDesc.DebugName);
    ADevice.SetDebugObjectName(VK_OBJECT_TYPE_IMAGE_VIEW, FImageView, FDesc.DebugName + '.View');
  end;
end;

constructor TVulkanRHITexture.CreateCarrier(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHITextureDesc; const AMinCarrierBytes: UInt64);
var
  NegotiatedDesc: TRHITextureDesc;
  ImgInfo: VkImageCreateInfo;
  ViewInfo: VkImageViewCreateInfo;
  FmtProps: VkFormatProperties;
  CarrierBytes: VkDeviceSize;
begin
  NegotiatedDesc := ADesc;
  if NegotiatedDesc.SampleCount = 0 then
    NegotiatedDesc.SampleCount := 1;
  if ADevice <> nil then
  begin
    if (ADevice.Handle <> nil) or (not IsVulkanInstanceLoaded) then
      NegotiatedDesc.Format := NegotiateOptimalPixelFormat(
        ADesc.Format, ADesc.Usage, ADevice.PhysicalDevice)
    else
      NegotiatedDesc.Format := NegotiateOptimalPixelFormat(
        ADesc.Format, ADesc.Usage, nil);
    if ADevice.Capabilities.MaxFramebufferSampleCount > 0 then
      NegotiatedDesc.SampleCount := ClampSampleCountToCapabilities(
        NegotiatedDesc.SampleCount, ADevice.Capabilities.MaxFramebufferSampleCount);
  end;
  if NegotiatedDesc.SampleCount > 1 then
    NegotiatedDesc.MipLevels := 1;

  inherited Create(ADevice, NegotiatedDesc);
  FOwnsImage := True;
  FOwnsAllocation := True;
  FAspectMask := GetFormatTransitionAspectMask(FDesc.Format);
  FViewAspectMask := GetFormatViewAspectMask(FDesc.Format, FDesc.Usage);

  CarrierBytes := Max(VkDeviceSize(TRHITexture.EstimateDescriptorByteSize(FDesc)),
    VkDeviceSize(AMinCarrierBytes));

  if (ADevice = nil) or (ADevice.Handle = nil) then
  begin
    FImage := VkImage(PtrUInt(Self));
    FImageView := VkImageView(PtrUInt(Self));
    if (ADevice <> nil) and (ADevice.MemoryAllocator <> nil) then
    begin
      FAllocation := ADevice.MemoryAllocator.AllocateTransientCarrierImageMemory(
        FImage, CarrierBytes, 65536);
      FDeviceMemory := FAllocation.DeviceMemory;
      FMemoryOffset := FAllocation.Offset;
      FAllocatedSize := FAllocation.Size;
      Inc(ADevice.FAllocatedMemoryBytes, FAllocatedSize);
    end;
    Exit;
  end;

  FillChar(ImgInfo, SizeOf(ImgInfo), 0);
  ImgInfo.sType := VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  ImgInfo.flags := VK_IMAGE_CREATE_ALIAS_BIT;
  if FDesc.Dimension = td3D then
    ImgInfo.imageType := VK_IMAGE_TYPE_3D
  else
    ImgInfo.imageType := VK_IMAGE_TYPE_2D;
  if FDesc.Dimension in [tdCube, tdCubeArray] then
    ImgInfo.flags := ImgInfo.flags or VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
  ImgInfo.format := RHIToVkFormat(FDesc.Format);
  ImgInfo.extent.width := Max(Cardinal(1), FDesc.Width);
  ImgInfo.extent.height := Max(Cardinal(1), FDesc.Height);
  if FDesc.Dimension = td3D then
  begin
    ImgInfo.extent.depth := Max(Cardinal(1), FDesc.DepthOrArrayLayers);
    ImgInfo.arrayLayers := 1;
  end else
  begin
    ImgInfo.extent.depth := 1;
    ImgInfo.arrayLayers := Max(Cardinal(1), FDesc.DepthOrArrayLayers);
  end;
  ImgInfo.mipLevels := Max(Cardinal(1), FDesc.MipLevels);
  ImgInfo.samples := RHIToVkSampleCountFlags(FDesc.SampleCount);
  ImgInfo.tiling := VK_IMAGE_TILING_OPTIMAL;
  ImgInfo.initialLayout := VK_IMAGE_LAYOUT_UNDEFINED;

  if tuSampled in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_SAMPLED_BIT;
  if tuStorage in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_STORAGE_BIT;
  if tuColorAttachment in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  if tuDepthStencil in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
  if tuTransferSrc in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  if tuTransferDst in FDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_DST_BIT;
  { On Metal / MoltenVK (Portability Subset), scaled vkCmdBlitImage mipmap generation renders
    via an internal MTLRenderCommandEncoder when MTLBlitCommandEncoder cannot filter-scale;
    include COLOR_ATTACHMENT_BIT when supported by the optimal-tiling format so MTLTextureUsageRenderTarget is set. }
  if ADevice.IsPortabilitySubsetDevice and (FDesc.MipLevels > 1) and
     (tuTransferSrc in FDesc.Usage) and (tuTransferDst in FDesc.Usage) and
     ((ImgInfo.usage and VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) = 0) and
     (ADevice.PhysicalDevice <> nil) and Assigned(vkGetPhysicalDeviceFormatProperties) then
  begin
    FillChar(FmtProps, SizeOf(FmtProps), 0);
    vkGetPhysicalDeviceFormatProperties(ADevice.PhysicalDevice, ImgInfo.format, @FmtProps);
    if (FmtProps.optimalTilingFeatures and VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT) <> 0 then
      ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  end;

  CheckVk(vkCreateImage(ADevice.Handle, @ImgInfo, nil, @FImage), 'vkCreateImage(Carrier)');

  if ADevice.MemoryAllocator <> nil then
  begin
    FAllocation := ADevice.MemoryAllocator.AllocateTransientCarrierImageMemory(
      FImage, CarrierBytes, 65536);
    FDeviceMemory := FAllocation.DeviceMemory;
    FMemoryOffset := FAllocation.Offset;
    FAllocatedSize := FAllocation.Size;
    CheckVk(vkBindImageMemory(ADevice.Handle, FImage, FDeviceMemory, FMemoryOffset),
      'vkBindImageMemory(Carrier)');
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
  ViewInfo.subresourceRange.levelCount := Max(Cardinal(1), FDesc.MipLevels);
  ViewInfo.subresourceRange.baseArrayLayer := 0;
  if FDesc.Dimension = td3D then
    ViewInfo.subresourceRange.layerCount := 1
  else
    ViewInfo.subresourceRange.layerCount := Max(Cardinal(1), FDesc.DepthOrArrayLayers);

  CheckVk(vkCreateImageView(ADevice.Handle, @ViewInfo, nil, @FImageView), 'vkCreateImageView(Carrier)');
  if FDesc.DebugName <> '' then
  begin
    ADevice.SetDebugObjectName(VK_OBJECT_TYPE_IMAGE, FImage, FDesc.DebugName + '.Carrier');
    ADevice.SetDebugObjectName(VK_OBJECT_TYPE_IMAGE_VIEW, FImageView, FDesc.DebugName + '.CarrierView');
  end;
end;

class function TVulkanRHITexture.TryCreateAliased(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHITextureDesc; const ACarrier: TVulkanRHITexture): TVulkanRHITexture;

  function AlignOffsetUp(const AVal, AAlign: VkDeviceSize): VkDeviceSize;
  begin
    if AAlign <= 1 then
      Result := AVal
    else
      Result := ((AVal + AAlign - 1) div AAlign) * AAlign;
  end;

var
  NegotiatedDesc: TRHITextureDesc;
  ImgInfo: VkImageCreateInfo;
  ViewInfo: VkImageViewCreateInfo;
  Info2: VkImageMemoryRequirementsInfo2;
  Req2: VkMemoryRequirements2;
  DedReq: VkMemoryDedicatedRequirements;
  MemReq: VkMemoryRequirements;
  TempImg: VkImage;
  TempView: VkImageView;
  AlignedOffset, CarrierEnd: VkDeviceSize;
  EstBytes: UInt64;
begin
  Result := nil;
  if (ADevice = nil) or (ACarrier = nil) or (ACarrier.AllocatedSize = 0) then
    Exit;

  NegotiatedDesc := ADesc;
  if NegotiatedDesc.SampleCount = 0 then
    NegotiatedDesc.SampleCount := 1;
  if (ADevice.Handle <> nil) or (not IsVulkanInstanceLoaded) then
    NegotiatedDesc.Format := NegotiateOptimalPixelFormat(
      ADesc.Format, ADesc.Usage, ADevice.PhysicalDevice)
  else
    NegotiatedDesc.Format := NegotiateOptimalPixelFormat(
      ADesc.Format, ADesc.Usage, nil);
  if ADevice.Capabilities.MaxFramebufferSampleCount > 0 then
    NegotiatedDesc.SampleCount := ClampSampleCountToCapabilities(
      NegotiatedDesc.SampleCount, ADevice.Capabilities.MaxFramebufferSampleCount);
  if NegotiatedDesc.SampleCount > 1 then
    NegotiatedDesc.MipLevels := 1;

  { Headless simulation mode: verify byte capacity & depth/color compatibility }
  if ADevice.Handle = nil then
  begin
    if (tuDepthStencil in NegotiatedDesc.Usage) <> (tuDepthStencil in ACarrier.Desc.Usage) then
      Exit(nil);
    EstBytes := TRHITexture.EstimateDescriptorByteSize(NegotiatedDesc);
    if EstBytes > UInt64(ACarrier.AllocatedSize) then
      Exit(nil);

    Result := TVulkanRHITexture.CreateSwapchainWrapper(ADevice, NegotiatedDesc, VK_NULL_HANDLE, VK_NULL_HANDLE);
    Result.FOwnsImage := True;
    Result.FOwnsAllocation := False;
    Result.FIsMemoryAliased := True;
    Result.FAliasedCarrierTexture := ACarrier;
    Result.FAspectMask := GetFormatTransitionAspectMask(NegotiatedDesc.Format);
    Result.FViewAspectMask := GetFormatViewAspectMask(NegotiatedDesc.Format, NegotiatedDesc.Usage);
    Result.FImage := VkImage(PtrUInt(Result));
    Result.FImageView := VkImageView(PtrUInt(Result));
    Result.FDeviceMemory := ACarrier.DeviceMemory;
    Result.FMemoryOffset := ACarrier.MemoryOffset;
    Result.FAllocatedSize := VkDeviceSize(EstBytes);
    Exit;
  end;

  { Real Vulkan GPU path: carrier cannot be aliased if it is a dedicated single-image allocation }
  if (ACarrier.DeviceMemory = VK_NULL_HANDLE) or
     (ACarrier.Allocation.IsValid and ACarrier.Allocation.IsDedicated) then
    Exit(nil);

  FillChar(ImgInfo, SizeOf(ImgInfo), 0);
  ImgInfo.sType := VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
  ImgInfo.flags := VK_IMAGE_CREATE_ALIAS_BIT;
  if NegotiatedDesc.Dimension = td3D then
    ImgInfo.imageType := VK_IMAGE_TYPE_3D
  else
    ImgInfo.imageType := VK_IMAGE_TYPE_2D;
  if NegotiatedDesc.Dimension in [tdCube, tdCubeArray] then
    ImgInfo.flags := ImgInfo.flags or VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
  ImgInfo.format := RHIToVkFormat(NegotiatedDesc.Format);
  ImgInfo.extent.width := Max(Cardinal(1), NegotiatedDesc.Width);
  ImgInfo.extent.height := Max(Cardinal(1), NegotiatedDesc.Height);
  if NegotiatedDesc.Dimension = td3D then
  begin
    ImgInfo.extent.depth := Max(Cardinal(1), NegotiatedDesc.DepthOrArrayLayers);
    ImgInfo.arrayLayers := 1;
  end else
  begin
    ImgInfo.extent.depth := 1;
    ImgInfo.arrayLayers := Max(Cardinal(1), NegotiatedDesc.DepthOrArrayLayers);
  end;
  ImgInfo.mipLevels := Max(Cardinal(1), NegotiatedDesc.MipLevels);
  ImgInfo.samples := RHIToVkSampleCountFlags(NegotiatedDesc.SampleCount);
  ImgInfo.tiling := VK_IMAGE_TILING_OPTIMAL;
  ImgInfo.initialLayout := VK_IMAGE_LAYOUT_UNDEFINED;

  if tuSampled in NegotiatedDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_SAMPLED_BIT;
  if tuStorage in NegotiatedDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_STORAGE_BIT;
  if tuColorAttachment in NegotiatedDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
  if tuDepthStencil in NegotiatedDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
  if tuTransferSrc in NegotiatedDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  if tuTransferDst in NegotiatedDesc.Usage then ImgInfo.usage := ImgInfo.usage or VK_IMAGE_USAGE_TRANSFER_DST_BIT;

  TempImg := VK_NULL_HANDLE;
  if vkCreateImage(ADevice.Handle, @ImgInfo, nil, @TempImg) <> VK_SUCCESS then
    Exit(nil);

  FillChar(MemReq, SizeOf(MemReq), 0);
  if Assigned(vkGetImageMemoryRequirements2) then
  begin
    FillChar(Info2, SizeOf(Info2), 0);
    Info2.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2;
    Info2.image := TempImg;
    FillChar(DedReq, SizeOf(DedReq), 0);
    DedReq.sType := VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS;
    FillChar(Req2, SizeOf(Req2), 0);
    Req2.sType := VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
    Req2.pNext := @DedReq;
    vkGetImageMemoryRequirements2(ADevice.Handle, @Info2, @Req2);
    MemReq := Req2.memoryRequirements;
    if DedReq.requiresDedicatedAllocation <> VK_FALSE then
    begin
      vkDestroyImage(ADevice.Handle, TempImg, nil);
      Exit(nil);
    end;
  end else
    vkGetImageMemoryRequirements(ADevice.Handle, TempImg, @MemReq);

  { Verify memoryTypeBits compatibility and aligned byte range inside ACarrier }
  if ACarrier.Allocation.IsValid and
     ((MemReq.memoryTypeBits and (UInt32(1) shl ACarrier.Allocation.MemoryTypeIndex)) = 0) then
  begin
    vkDestroyImage(ADevice.Handle, TempImg, nil);
    Exit(nil);
  end;

  AlignedOffset := AlignOffsetUp(ACarrier.MemoryOffset, MemReq.alignment);
  CarrierEnd := ACarrier.MemoryOffset + ACarrier.AllocatedSize;
  if AlignedOffset + MemReq.size > CarrierEnd then
  begin
    vkDestroyImage(ADevice.Handle, TempImg, nil);
    Exit(nil);
  end;

  if vkBindImageMemory(ADevice.Handle, TempImg, ACarrier.DeviceMemory, AlignedOffset) <> VK_SUCCESS then
  begin
    vkDestroyImage(ADevice.Handle, TempImg, nil);
    Exit(nil);
  end;

  FillChar(ViewInfo, SizeOf(ViewInfo), 0);
  ViewInfo.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
  ViewInfo.image := TempImg;
  case NegotiatedDesc.Dimension of
    td2D: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D;
    td2DArray: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D_ARRAY;
    td3D: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_3D;
    tdCube: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_CUBE;
    tdCubeArray: ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_CUBE_ARRAY;
  end;
  ViewInfo.format := ImgInfo.format;
  ViewInfo.subresourceRange.aspectMask := GetFormatViewAspectMask(NegotiatedDesc.Format, NegotiatedDesc.Usage);
  ViewInfo.subresourceRange.baseMipLevel := 0;
  ViewInfo.subresourceRange.levelCount := Max(Cardinal(1), NegotiatedDesc.MipLevels);
  ViewInfo.subresourceRange.baseArrayLayer := 0;
  if NegotiatedDesc.Dimension = td3D then
    ViewInfo.subresourceRange.layerCount := 1
  else
    ViewInfo.subresourceRange.layerCount := Max(Cardinal(1), NegotiatedDesc.DepthOrArrayLayers);

  TempView := VK_NULL_HANDLE;
  if vkCreateImageView(ADevice.Handle, @ViewInfo, nil, @TempView) <> VK_SUCCESS then
  begin
    vkDestroyImage(ADevice.Handle, TempImg, nil);
    Exit(nil);
  end;

  Result := TVulkanRHITexture.CreateSwapchainWrapper(ADevice, NegotiatedDesc, TempImg, TempView);
  Result.FOwnsImage := True;
  Result.FOwnsAllocation := False;
  Result.FIsMemoryAliased := True;
  Result.FAliasedCarrierTexture := ACarrier;
  Result.FAspectMask := GetFormatTransitionAspectMask(NegotiatedDesc.Format);
  Result.FViewAspectMask := ViewInfo.subresourceRange.aspectMask;
  Result.FDeviceMemory := ACarrier.DeviceMemory;
  Result.FMemoryOffset := AlignedOffset;
  Result.FAllocatedSize := MemReq.size;
  if NegotiatedDesc.DebugName <> '' then
  begin
    ADevice.SetDebugObjectName(VK_OBJECT_TYPE_IMAGE, TempImg, NegotiatedDesc.DebugName + '.Aliased');
    ADevice.SetDebugObjectName(VK_OBJECT_TYPE_IMAGE_VIEW, TempView, NegotiatedDesc.DebugName + '.AliasedView');
  end;
end;

constructor TVulkanRHITexture.CreateSwapchainWrapper(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHITextureDesc; const AExistingImage: VkImage; const AExistingView: VkImageView);
begin
  inherited Create(ADevice, ADesc);
  FOwnsImage := False;
  FOwnsAllocation := False;
  FImage := AExistingImage;
  FImageView := AExistingView;
  FAspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
  FViewAspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
end;

procedure TVulkanRHITexture.ReleaseDeviceResources;
var
  I: Integer;
  SubDummyAlloc: TVulkanMemoryAllocation;
begin
  if VulkanDevice <> nil then
  begin
    VulkanDevice.UnbindDestroyedTextureFromDescriptorSets(Self);
    if VulkanDevice.FActiveColorTarget = Self then
      VulkanDevice.FActiveColorTarget := nil;
    if VulkanDevice.FActiveDepthTarget = Self then
      VulkanDevice.FActiveDepthTarget := nil;
    if VulkanDevice.BindlessTextureManager <> nil then
      VulkanDevice.BindlessTextureManager.UnregisterTexture(Self);
    if VulkanDevice.StagingUploader <> nil then
      VulkanDevice.StagingUploader.CancelPendingUploadsForTexture(Self);
    FillChar(SubDummyAlloc, SizeOf(SubDummyAlloc), 0);
    for I := 0 to High(FSubresourceViews) do
      if (FSubresourceViews[I].View <> VK_NULL_HANDLE) and
         (FSubresourceViews[I].View <> FImageView) then
        VulkanDevice.DeferOrDestroyTexture(
          VK_NULL_HANDLE, FSubresourceViews[I].View, SubDummyAlloc, VK_NULL_HANDLE, 0);
    SetLength(FSubresourceViews, 0);
    if FOwnsImage then
    begin
      if (FImage <> VK_NULL_HANDLE) or (FImageView <> VK_NULL_HANDLE) or
         (FDeviceMemory <> VK_NULL_HANDLE) then
      begin
        if FOwnsAllocation then
          VulkanDevice.DeferOrDestroyTexture(FImage, FImageView, FAllocation, FDeviceMemory, FAllocatedSize)
        else
          VulkanDevice.DeferOrDestroyTexture(FImage, FImageView, SubDummyAlloc, VK_NULL_HANDLE, 0);
      end;
    end else if (VulkanDevice.Handle <> nil) and (FImageView <> VK_NULL_HANDLE) then
      vkDestroyImageView(VulkanDevice.Handle, FImageView, nil);
  end;
  SetLength(FSubresourceViews, 0);
  FImage := VK_NULL_HANDLE;
  FImageView := VK_NULL_HANDLE;
  FillChar(FAllocation, SizeOf(FAllocation), 0);
  FDeviceMemory := VK_NULL_HANDLE;
  FAllocatedSize := 0;
end;

destructor TVulkanRHITexture.Destroy;
var
  FaceIdx: Integer;
begin
  FreeAndNil(FPresentReadbackShadow);
  FreeAndNil(FPresentReadbackStaging);
  for FaceIdx := 0 to 5 do
    SetLength(FMip0FacePixels[FaceIdx], 0);
  SetLength(FHostPixels, 0);
  inherited;
end;

function TVulkanRHITexture.GetSubresourceViewCount: Cardinal;
begin
  Result := Cardinal(Length(FSubresourceViews));
end;

function TVulkanRHITexture.GetRenderedLayerMask: Cardinal;
begin
  Result := FRenderedLayerMask;
end;

function TVulkanRHITexture.GetSubresourceImageView(
  const AMipLevel, AArrayLayer: Cardinal): VkImageView;
var
  I, NewIdx: Integer;
  ViewInfo: VkImageViewCreateInfo;
  ClampedMip, ClampedLayer: Cardinal;
begin
  ClampedMip := Min(AMipLevel, Max(Cardinal(1), FDesc.MipLevels) - 1);
  if FDesc.Dimension = td3D then
    ClampedLayer := 0
  else
    ClampedLayer := Min(AArrayLayer, Max(Cardinal(1), FDesc.DepthOrArrayLayers) - 1);

  if (FDesc.Dimension = td2D) and (FDesc.MipLevels <= 1) and
     (FDesc.DepthOrArrayLayers <= 1) and (ClampedMip = 0) and (ClampedLayer = 0) and
     (FViewAspectMask = FAspectMask) then
    Exit(FImageView);

  for I := 0 to High(FSubresourceViews) do
    if (FSubresourceViews[I].MipLevel = ClampedMip) and
       (FSubresourceViews[I].ArrayLayer = ClampedLayer) then
      Exit(FSubresourceViews[I].View);

  NewIdx := Length(FSubresourceViews);
  SetLength(FSubresourceViews, NewIdx + 1);
  FSubresourceViews[NewIdx].MipLevel := ClampedMip;
  FSubresourceViews[NewIdx].ArrayLayer := ClampedLayer;

  if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and Assigned(vkCreateImageView) then
  begin
    FillChar(ViewInfo, SizeOf(ViewInfo), 0);
    ViewInfo.sType := VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ViewInfo.image := FImage;
    ViewInfo.viewType := VK_IMAGE_VIEW_TYPE_2D;
    ViewInfo.format := RHIToVkFormat(FDesc.Format);
    ViewInfo.subresourceRange.aspectMask := FAspectMask;
    ViewInfo.subresourceRange.baseMipLevel := ClampedMip;
    ViewInfo.subresourceRange.levelCount := 1;
    ViewInfo.subresourceRange.baseArrayLayer := ClampedLayer;
    ViewInfo.subresourceRange.layerCount := 1;
    CheckVk(vkCreateImageView(VulkanDevice.Handle, @ViewInfo, nil,
      @FSubresourceViews[NewIdx].View), 'vkCreateImageView(Subresource)');
  end else
    FSubresourceViews[NewIdx].View := VkImageView(
      PtrUInt(Self) xor ((PtrUInt(ClampedMip + 1) shl 16) or PtrUInt(ClampedLayer + 1)));

  Result := FSubresourceViews[NewIdx].View;
end;

procedure TVulkanRHITexture.RecordVkMipmapBlits(const ACmd: VkCommandBuffer);
var
  Barrier: VkImageMemoryBarrier;
  Blits: array of VkImageBlit;
  MipWidth, MipHeight, MipDepth, NextWidth, NextHeight, NextDepth: Integer;
  LayerCount, LayerIdx, I: Cardinal;
begin
  if (ACmd = nil) or (FDesc.MipLevels <= 1) or
     not Assigned(vkCmdBlitImage) or not Assigned(vkCmdPipelineBarrier) then
    Exit;

  MipWidth := Max(1, Integer(FDesc.Width));
  MipHeight := Max(1, Integer(FDesc.Height));
  if FDesc.Dimension = td3D then
  begin
    MipDepth := Max(1, Integer(FDesc.DepthOrArrayLayers));
    LayerCount := 1;
  end else
  begin
    MipDepth := 1;
    LayerCount := Max(Cardinal(1), FDesc.DepthOrArrayLayers);
  end;

  FillChar(Barrier, SizeOf(Barrier), 0);
  Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
  Barrier.image := FImage;
  Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.subresourceRange.aspectMask := FAspectMask;
  Barrier.subresourceRange.baseArrayLayer := 0;
  Barrier.subresourceRange.layerCount := LayerCount;
  Barrier.subresourceRange.levelCount := 1;

  for I := 1 to FDesc.MipLevels - 1 do
  begin
    { Transition source mip level I - 1 to TRANSFER_SRC_OPTIMAL }
    Barrier.subresourceRange.baseMipLevel := I - 1;
    if (I = 1) and (FCurrentState = rsShaderRead) then
    begin
      Barrier.oldLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
      Barrier.srcAccessMask := VK_ACCESS_SHADER_READ_BIT;
    end else
    begin
      Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      Barrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
    end;
    Barrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    Barrier.dstAccessMask := VK_ACCESS_TRANSFER_READ_BIT;

    vkCmdPipelineBarrier(ACmd,
      VK_PIPELINE_STAGE_TRANSFER_BIT or VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      VK_PIPELINE_STAGE_TRANSFER_BIT,
      0, 0, nil, 0, nil, 1, @Barrier);

    { Transition destination mip level I from UNDEFINED to TRANSFER_DST_OPTIMAL }
    Barrier.subresourceRange.baseMipLevel := I;
    Barrier.oldLayout := VK_IMAGE_LAYOUT_UNDEFINED;
    Barrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    Barrier.srcAccessMask := 0;
    Barrier.dstAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;

    vkCmdPipelineBarrier(ACmd,
      VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_TRANSFER_BIT,
      0, 0, nil, 0, nil, 1, @Barrier);

    NextWidth := Max(1, MipWidth div 2);
    NextHeight := Max(1, MipHeight div 2);
    NextDepth := Max(1, MipDepth div 2);

    SetLength(Blits, LayerCount);
    for LayerIdx := 0 to LayerCount - 1 do
    begin
      FillChar(Blits[LayerIdx], SizeOf(VkImageBlit), 0);
      Blits[LayerIdx].srcOffsets[1].x := MipWidth;
      Blits[LayerIdx].srcOffsets[1].y := MipHeight;
      Blits[LayerIdx].srcOffsets[1].z := MipDepth;
      Blits[LayerIdx].srcSubresource.aspectMask := FAspectMask;
      Blits[LayerIdx].srcSubresource.mipLevel := I - 1;
      Blits[LayerIdx].srcSubresource.baseArrayLayer := LayerIdx;
      Blits[LayerIdx].srcSubresource.layerCount := 1;

      Blits[LayerIdx].dstOffsets[1].x := NextWidth;
      Blits[LayerIdx].dstOffsets[1].y := NextHeight;
      Blits[LayerIdx].dstOffsets[1].z := NextDepth;
      Blits[LayerIdx].dstSubresource.aspectMask := FAspectMask;
      Blits[LayerIdx].dstSubresource.mipLevel := I;
      Blits[LayerIdx].dstSubresource.baseArrayLayer := LayerIdx;
      Blits[LayerIdx].dstSubresource.layerCount := 1;
    end;

    vkCmdBlitImage(ACmd,
      FImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      FImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      LayerCount, @Blits[0], VK_FILTER_LINEAR);

    { Transition source mip level I - 1 to SHADER_READ_ONLY_OPTIMAL }
    Barrier.subresourceRange.baseMipLevel := I - 1;
    Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    Barrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    Barrier.srcAccessMask := VK_ACCESS_TRANSFER_READ_BIT;
    Barrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(ACmd,
      VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
      0, 0, nil, 0, nil, 1, @Barrier);

    MipWidth := NextWidth;
    MipHeight := NextHeight;
    MipDepth := NextDepth;
  end;

  { Transition final mip level Desc.MipLevels - 1 to SHADER_READ_ONLY_OPTIMAL }
  Barrier.subresourceRange.baseMipLevel := FDesc.MipLevels - 1;
  Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
  Barrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
  Barrier.srcAccessMask := VK_ACCESS_TRANSFER_WRITE_BIT;
  Barrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;

  vkCmdPipelineBarrier(ACmd,
    VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
    0, 0, nil, 0, nil, 1, @Barrier);
end;

function TVulkanRHITexture.TryUploadPortabilityCubeMipmapsFromHost: Boolean;
var
  FaceIdx, MipIdx: Cardinal;
  SrcW, SrcH, DstW, DstH, DX, DY, SX0, SX1, SY0, SY1, C: Integer;
  PrevPixels, NextPixels: array of Byte;
  MipImg: TRGBAlphaImage;
  SavedUploads: Cardinal;
  P00, P10, P01, P11, DstOff: PtrUInt;
begin
  Result := False;
  if (VulkanDevice = nil) or (VulkanDevice.Handle = nil) or
     (not VulkanDevice.IsPortabilitySubsetDevice) or
     (FDesc.Dimension <> tdCube) or (FDesc.MipLevels <= 1) or
     not (FDesc.Format in [pfRGBA8_UNorm, pfRGBA8_sRGB, pfBGRA8_UNorm, pfBGRA8_sRGB]) then
    Exit;

  SrcW := Max(1, Integer(FDesc.Width));
  SrcH := Max(1, Integer(FDesc.Height));
  for FaceIdx := 0 to 5 do
    if Length(FMip0FacePixels[FaceIdx]) <> SrcW * SrcH * 4 then
      Exit;

  if not ((ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
    VulkanDevice.FlushStagingUploads(nil);

  SavedUploads := FTotalSubresourceUploads;
  try
    for FaceIdx := 0 to 5 do
    begin
      SrcW := Max(1, Integer(FDesc.Width));
      SrcH := Max(1, Integer(FDesc.Height));
      SetLength(PrevPixels, SrcW * SrcH * 4);
      Move(FMip0FacePixels[FaceIdx][0], PrevPixels[0], Length(PrevPixels));

      for MipIdx := 1 to FDesc.MipLevels - 1 do
      begin
        DstW := Max(1, SrcW div 2);
        DstH := Max(1, SrcH div 2);
        SetLength(NextPixels, DstW * DstH * 4);
        for DY := 0 to DstH - 1 do
        begin
          SY0 := Min(SrcH - 1, DY * 2);
          SY1 := Min(SrcH - 1, DY * 2 + 1);
          for DX := 0 to DstW - 1 do
          begin
            SX0 := Min(SrcW - 1, DX * 2);
            SX1 := Min(SrcW - 1, DX * 2 + 1);
            P00 := (PtrUInt(SY0) * PtrUInt(SrcW) + PtrUInt(SX0)) * 4;
            P10 := (PtrUInt(SY0) * PtrUInt(SrcW) + PtrUInt(SX1)) * 4;
            P01 := (PtrUInt(SY1) * PtrUInt(SrcW) + PtrUInt(SX0)) * 4;
            P11 := (PtrUInt(SY1) * PtrUInt(SrcW) + PtrUInt(SX1)) * 4;
            DstOff := (PtrUInt(DY) * PtrUInt(DstW) + PtrUInt(DX)) * 4;
            for C := 0 to 3 do
              NextPixels[DstOff + PtrUInt(C)] := Byte(
                (Cardinal(PrevPixels[P00 + PtrUInt(C)]) +
                 Cardinal(PrevPixels[P10 + PtrUInt(C)]) +
                 Cardinal(PrevPixels[P01 + PtrUInt(C)]) +
                 Cardinal(PrevPixels[P11 + PtrUInt(C)]) + 2) shr 2);
          end;
        end;

        MipImg := TRGBAlphaImage.Create(DstW, DstH);
        try
          Move(NextPixels[0], MipImg.RawPixels^, DstW * DstH * 4);
          UploadImage(MipImg, MipIdx, FaceIdx);
        finally
          FreeAndNil(MipImg);
        end;

        PrevPixels := Copy(NextPixels);
        SrcW := DstW;
        SrcH := DstH;
      end;
    end;

    if not ((ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
      VulkanDevice.FlushStagingUploads(nil);
  finally
    FTotalSubresourceUploads := SavedUploads;
  end;

  Result := True;
end;

procedure TVulkanRHITexture.GenerateMipmaps;
var
  Cmd: VkCommandBuffer;
begin
  if FDesc.MipLevels <= 1 then
    Exit;

  if TryUploadPortabilityCubeMipmapsFromHost then
  begin
    Inc(FMipmapGenerationCount);
    FLastGeneratedMipLevels := FDesc.MipLevels;
    FMaxUploadedMipLevel := Max(FMaxUploadedMipLevel, FDesc.MipLevels - 1);
    FCurrentState := rsShaderRead;
    Exit;
  end;

  if (ActiveCommandList <> nil) and
     not ((VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and ActiveCommandList.IsRendering) then
  begin
    ActiveCommandList.GenerateMipmaps(Self);
    Exit;
  end;

  Inc(FMipmapGenerationCount);
  FLastGeneratedMipLevels := FDesc.MipLevels;
  FMaxUploadedMipLevel := Max(FMaxUploadedMipLevel, FDesc.MipLevels - 1);

  if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and Assigned(vkCmdBlitImage) then
  begin
    VulkanDevice.FlushStagingUploads(nil);
    Cmd := VulkanDevice.BeginSingleTimeCommands;
    RecordVkMipmapBlits(Cmd);
    VulkanDevice.EndSingleTimeCommands(Cmd);
  end;

  FCurrentState := rsShaderRead;
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

procedure TVulkanRHITexture.SetHostClearColorRect(const AColor: TCastleColor;
  const ARect: TRectangle);
var
  TexW, TexH, X0, Y0, X1, Y1, X, Y: Integer;
  TotalPixels, Idx: PtrUInt;
  RByte, GByte, BByte, AByte: Byte;
begin
  TexW := Max(1, Integer(FDesc.Width));
  TexH := Max(1, Integer(FDesc.Height));
  TotalPixels := PtrUInt(TexW) * PtrUInt(TexH);
  if PtrUInt(Length(FHostPixels)) < TotalPixels * 4 then
    SetLength(FHostPixels, TotalPixels * 4);

  X0 := Max(0, ARect.Left);
  Y0 := Max(0, ARect.Bottom);
  X1 := Min(TexW, ARect.Left + Max(0, ARect.Width));
  Y1 := Min(TexH, ARect.Bottom + Max(0, ARect.Height));
  if (X0 >= X1) or (Y0 >= Y1) then
    Exit;

  RByte := Byte(Round(EnsureRange(AColor.X, 0.0, 1.0) * 255.0));
  GByte := Byte(Round(EnsureRange(AColor.Y, 0.0, 1.0) * 255.0));
  BByte := Byte(Round(EnsureRange(AColor.Z, 0.0, 1.0) * 255.0));
  AByte := Byte(Round(EnsureRange(AColor.W, 0.0, 1.0) * 255.0));
  for Y := Y0 to Y1 - 1 do
    for X := X0 to X1 - 1 do
    begin
      Idx := (PtrUInt(Y) * PtrUInt(TexW) + PtrUInt(X)) * 4;
      FHostPixels[Idx + 0] := RByte;
      FHostPixels[Idx + 1] := GByte;
      FHostPixels[Idx + 2] := BByte;
      FHostPixels[Idx + 3] := AByte;
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
  FloatImage: TRGBAlphaFloatImage;
  DecompressedImg: TCastleImage;
  NeedsFreeRgba, NeedsFreeFloat: Boolean;
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  Region: VkBufferImageCopy;
  Barrier: VkImageMemoryBarrier;
  DataSize, CopyBytes, TotalTexels, PIdx: PtrUInt;
  PixelsPtr: Pointer;
  ImgWidth, ImgHeight, ImgDepth: Cardinal;
  EncodedFormatBytes: array of Byte;
  SrcFloat4: PVector4;
  DstHalfPtr: PWord;
  DstFloatPtr: PSingle;
begin
  if AImage = nil then Exit;
  if FImage = VK_NULL_HANDLE then Exit;

  NeedsFreeRgba := False;
  NeedsFreeFloat := False;
  RgbaImage := nil;
  FloatImage := nil;
  ImgWidth := Max(Cardinal(1), AImage.Width);
  ImgHeight := Max(Cardinal(1), AImage.Height);
  ImgDepth := Max(Cardinal(1), AImage.Depth);

  TotalTexels := PtrUInt(ImgWidth) * PtrUInt(ImgHeight) * PtrUInt(ImgDepth);
  if FDesc.Format = pfRGBA32_Float then
  begin
    if AImage is TRGBAlphaFloatImage then
    begin
      FloatImage := TRGBAlphaFloatImage(AImage);
      DataSize := TotalTexels * 16;
      PixelsPtr := FloatImage.RawPixels;
    end else
    if AImage is TCastleImage then
    begin
      FloatImage := TRGBAlphaFloatImage.Create(ImgWidth, ImgHeight, ImgDepth);
      FloatImage.Assign(TCastleImage(AImage));
      NeedsFreeFloat := True;
      DataSize := TotalTexels * 16;
      PixelsPtr := FloatImage.RawPixels;
    end else
      Exit;
  end else
  if FDesc.Format in [pfRGBA16_Float, pfRG16_Float, pfR16_Float, pfR32_Float, pfD32_Float] then
  begin
    if AImage is TRGBAlphaFloatImage then
      FloatImage := TRGBAlphaFloatImage(AImage)
    else if AImage is TCastleImage then
    begin
      FloatImage := TRGBAlphaFloatImage.Create(ImgWidth, ImgHeight, ImgDepth);
      FloatImage.Assign(TCastleImage(AImage));
      NeedsFreeFloat := True;
    end else
      Exit;

    SrcFloat4 := PVector4(FloatImage.RawPixels);
    case FDesc.Format of
      pfRGBA16_Float:
        begin
          DataSize := TotalTexels * 8;
          SetLength(EncodedFormatBytes, DataSize);
          DstHalfPtr := PWord(@EncodedFormatBytes[0]);
          for PIdx := 0 to TotalTexels - 1 do
          begin
            DstHalfPtr[PIdx * 4 + 0] := FloatToHalfFloat(SrcFloat4[PIdx].X);
            DstHalfPtr[PIdx * 4 + 1] := FloatToHalfFloat(SrcFloat4[PIdx].Y);
            DstHalfPtr[PIdx * 4 + 2] := FloatToHalfFloat(SrcFloat4[PIdx].Z);
            DstHalfPtr[PIdx * 4 + 3] := FloatToHalfFloat(SrcFloat4[PIdx].W);
          end;
        end;
      pfRG16_Float:
        begin
          DataSize := TotalTexels * 4;
          SetLength(EncodedFormatBytes, DataSize);
          DstHalfPtr := PWord(@EncodedFormatBytes[0]);
          for PIdx := 0 to TotalTexels - 1 do
          begin
            DstHalfPtr[PIdx * 2 + 0] := FloatToHalfFloat(SrcFloat4[PIdx].X);
            DstHalfPtr[PIdx * 2 + 1] := FloatToHalfFloat(SrcFloat4[PIdx].Y);
          end;
        end;
      pfR16_Float:
        begin
          DataSize := TotalTexels * 2;
          SetLength(EncodedFormatBytes, DataSize);
          DstHalfPtr := PWord(@EncodedFormatBytes[0]);
          for PIdx := 0 to TotalTexels - 1 do
            DstHalfPtr[PIdx] := FloatToHalfFloat(SrcFloat4[PIdx].X);
        end;
    else { pfR32_Float, pfD32_Float }
      begin
        DataSize := TotalTexels * 4;
        SetLength(EncodedFormatBytes, DataSize);
        DstFloatPtr := PSingle(@EncodedFormatBytes[0]);
        for PIdx := 0 to TotalTexels - 1 do
          DstFloatPtr[PIdx] := SrcFloat4[PIdx].X;
      end;
    end;
    PixelsPtr := @EncodedFormatBytes[0];
  end else
  if AImage is TGPUCompressedImage then
  begin
    if FDesc.Format in [pfBC1_RGBA_UNorm, pfBC1_RGBA_sRGB,
                        pfBC3_RGBA_UNorm, pfBC3_RGBA_sRGB,
                        pfBC5_RG_UNorm, pfBC7_RGBA_UNorm, pfBC7_RGBA_sRGB,
                        pfASTC_4x4_UNorm, pfASTC_4x4_sRGB,
                        pfETC2_RGB8_UNorm, pfETC2_RGBA8_UNorm] then
    begin
      DataSize := TGPUCompressedImage(AImage).Size;
      PixelsPtr := TGPUCompressedImage(AImage).RawPixels;
    end else
    begin
      RgbaImage := TRGBAlphaImage.Create(ImgWidth, ImgHeight, ImgDepth);
      NeedsFreeRgba := True;
      DataSize := PtrUInt(ImgWidth) * PtrUInt(ImgHeight) * PtrUInt(ImgDepth) * 4;
      FillChar(RgbaImage.RawPixels^, DataSize, 0);
      if Assigned(DecompressTexture) then
      begin
        try
          DecompressedImg := TGPUCompressedImage(AImage).Decompress;
          try
            RgbaImage.Assign(DecompressedImg);
          finally
            FreeAndNil(DecompressedImg);
          end;
        except
          on ECannotDecompressTexture do ;
        end;
      end else
      if (TGPUCompressedImage(AImage).RawPixels <> nil) and (TGPUCompressedImage(AImage).Size > 0) then
      begin
        CopyBytes := Min(DataSize, PtrUInt(TGPUCompressedImage(AImage).Size));
        Move(TGPUCompressedImage(AImage).RawPixels^, RgbaImage.RawPixels^, CopyBytes);
      end;
      PixelsPtr := RgbaImage.RawPixels;
    end;
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
    Inc(FTotalSubresourceUploads);
    if (AMipLevel = 0) and (AArrayLayer = 0) then
      FRenderedLayerMask := 0;
    if AMipLevel > FMaxUploadedMipLevel then
      FMaxUploadedMipLevel := AMipLevel;
    if AArrayLayer > FMaxUploadedArrayLayer then
      FMaxUploadedArrayLayer := AArrayLayer;

    if (PixelsPtr <> nil) and (AMipLevel = 0) and (AArrayLayer = 0) and
       ((VulkanDevice = nil) or (VulkanDevice.Handle = nil)) then
    begin
      SetLength(FHostPixels, DataSize);
      if DataSize > 0 then
        Move(PixelsPtr^, FHostPixels[0], DataSize);
    end;

    if (PixelsPtr <> nil) and (AMipLevel = 0) and (AArrayLayer < 6) and
       (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and
       VulkanDevice.IsPortabilitySubsetDevice and
       (FDesc.Dimension = tdCube) and (FDesc.MipLevels > 1) and
       (DataSize = PtrUInt(Max(Cardinal(1), FDesc.Width)) * PtrUInt(Max(Cardinal(1), FDesc.Height)) * 4) then
    begin
      SetLength(FMip0FacePixels[AArrayLayer], DataSize);
      if DataSize > 0 then
        Move(PixelsPtr^, FMip0FacePixels[AArrayLayer][0], DataSize);
    end;

    if (VulkanDevice <> nil) and (VulkanDevice.StagingUploader <> nil) and
       not ((VulkanDevice.Handle <> nil) and (ImgDepth > 1)) and
       not ((VulkanDevice.Handle <> nil) and (ActiveCommandList <> nil) and ActiveCommandList.IsRendering) then
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
    if NeedsFreeFloat then
      FreeAndNil(FloatImage);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHISampler, ShaderModule, DescriptorSetLayout, DescriptorSet, Pipeline}
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHISampler.Create(const ADevice: TVulkanRHIDevice; const ADesc: TRHISamplerDesc);
var
  MaxDevAniso: Single;
begin
  inherited Create(ADevice, ADesc);
  if (ADevice <> nil) and (ADevice.Capabilities.MaxAnisotropy > 0.0) then
    MaxDevAniso := ADevice.Capabilities.MaxAnisotropy
  else
    MaxDevAniso := 16.0;
  FCreateInfo := BuildVkSamplerCreateInfo(ADesc, MaxDevAniso);
  if (ADevice <> nil) and (ADevice.Handle <> nil) and Assigned(vkCreateSampler) then
    CheckVk(vkCreateSampler(ADevice.Handle, @FCreateInfo, nil, @FHandle), 'vkCreateSampler')
  else
    FHandle := VkSampler(PtrUInt(Self));
end;

procedure TVulkanRHISampler.ReleaseDeviceResources;
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
end;

destructor TVulkanRHISampler.Destroy;
begin
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
  if (ADevice = nil) or (ADevice.Handle = nil) or
     (not Assigned(vkCreateShaderModule)) or (ASizeInBytes <= 10 * SizeOf(UInt32)) then
    Exit;
  FillChar(CreateInfo, SizeOf(CreateInfo), 0);
  CreateInfo.sType := VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
  CreateInfo.codeSize := ASizeInBytes;
  CreateInfo.pCode := PUInt32(ASPIRVBinary);
  CheckVk(vkCreateShaderModule(ADevice.Handle, @CreateInfo, nil, @FHandle), 'vkCreateShaderModule');
  if (ADebugName <> '') and (FHandle <> VK_NULL_HANDLE) then
    ADevice.SetDebugObjectName(VK_OBJECT_TYPE_SHADER_MODULE, FHandle, ADebugName);
end;

procedure TVulkanRHIShaderModule.ReleaseDeviceResources;
begin
  if (FHandle <> VK_NULL_HANDLE) and (Device <> nil) and
     (TVulkanRHIDevice(Device).Handle <> nil) and Assigned(vkDestroyShaderModule) then
    vkDestroyShaderModule(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  FHandle := VK_NULL_HANDLE;
end;

destructor TVulkanRHIShaderModule.Destroy;
begin
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
  HasAnyBindingFlags, HasSamplerBinding, HasDynamicBuffer, AutoPromoteSamplersToUAB: Boolean;
  LayoutInfo: VkDescriptorSetLayoutCreateInfo;
  I: Integer;
begin
  inherited Create(ADevice, '');
  FUsesUpdateAfterBind := False;
  FAllBindingsUpdateAfterBind := Length(Bindings) > 0;
  HasAnyBindingFlags := False;
  HasSamplerBinding := False;
  HasDynamicBuffer := False;
  for I := 0 to High(Bindings) do
  begin
    if Bindings[I].DescriptorType in [dtCombinedImageSampler, dtSampler] then
      HasSamplerBinding := True;
    if Bindings[I].DescriptorType = dtUniformBufferDynamic then
      HasDynamicBuffer := True;
  end;
  { On Metal / Portability devices where non-UAB discrete sampler registers are capped at 16
    (VUID-VkPipelineLayoutCreateInfo-descriptorType-03016) while Metal Argument Buffers
    (UpdateAfterBind) support 96+ samplers per stage, promote sampler bindings in non-dynamic-UBO
    layouts to VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT. }
  AutoPromoteSamplersToUAB := (ADevice <> nil) and
    ADevice.NeedsUpdateAfterBindSamplerLayouts and
    HasSamplerBinding and (not HasDynamicBuffer);

  SetLength(FBindings, Length(Bindings));
  SetLength(VkBindings, Length(Bindings));
  SetLength(VkBindingFlags, Length(Bindings));
  for I := 0 to High(Bindings) do
  begin
    FBindings[I] := Bindings[I];
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
      dtSampler:               VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_SAMPLER;
      dtStorageImage:          VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
      dtAccelerationStructure: VkBindings[I].descriptorType := VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;
    end;

    if AutoPromoteSamplersToUAB and
       (Bindings[I].DescriptorType in [dtCombinedImageSampler, dtSampler]) then
      Include(FBindings[I].BindingFlags, dbfUpdateAfterBind);

    VkBindingFlags[I] := 0;
    if FBindings[I].BindingFlags <> [] then
    begin
      HasAnyBindingFlags := True;
      if dbfPartiallyBound in FBindings[I].BindingFlags then
        VkBindingFlags[I] := VkBindingFlags[I] or VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT;
      if dbfUpdateUnusedWhilePending in FBindings[I].BindingFlags then
        VkBindingFlags[I] := VkBindingFlags[I] or VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT;
      if dbfUpdateAfterBind in FBindings[I].BindingFlags then
      begin
        VkBindingFlags[I] := VkBindingFlags[I] or VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;
        FUsesUpdateAfterBind := True;
      end else
        FAllBindingsUpdateAfterBind := False;
      if dbfVariableDescriptorCount in FBindings[I].BindingFlags then
        VkBindingFlags[I] := VkBindingFlags[I] or VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT;
    end else
      FAllBindingsUpdateAfterBind := False;
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

procedure TVulkanRHIDescriptorSetLayout.ReleaseDeviceResources;
begin
  if (FHandle <> VK_NULL_HANDLE) and (Device <> nil) and
     (TVulkanRHIDevice(Device).Handle <> nil) and Assigned(vkDestroyDescriptorSetLayout) then
    vkDestroyDescriptorSetLayout(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  FHandle := VK_NULL_HANDLE;
end;

destructor TVulkanRHIDescriptorSetLayout.Destroy;
begin
  SetLength(FBindings, 0);
  inherited;
end;

function TVulkanRHIDescriptorSetLayout.TryGetBindingType(const ABinding: Cardinal;
  out ADescriptorType: TRHIDescriptorType): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FBindings) do
    if FBindings[I].Binding = ABinding then
    begin
      ADescriptorType := FBindings[I].DescriptorType;
      Exit(True);
    end;
  ADescriptorType := dtCombinedImageSampler;
  Result := False;
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

  FUsesCustomPool := False;
  if PoolAlloc <> nil then
    FHandle := PoolAlloc.AllocateDescriptorSet(SetLayoutHandle, FOwnerPool)
  else
  begin
    FOwnerPool := VK_NULL_HANDLE;
    FHandle := VkDescriptorSet(PtrUInt(Self));
  end;
  if (ADevice <> nil) and (not AIsTransient) then
    ADevice.RegisterLiveDescriptorSet(Self);
end;

constructor TVulkanRHIDescriptorSet.CreateFromCustomPool(
  const ADevice: TVulkanRHIDevice; const ALayout: TVulkanRHIDescriptorSetLayout;
  const ACustomPool: VkDescriptorPool);
var
  AllocInfo: VkDescriptorSetAllocateInfo;
  LocalLayout: VkDescriptorSetLayout;
begin
  inherited Create(ADevice, '');
  FLayout := ALayout;
  FIsTransient := False;
  FUsesCustomPool := True;
  FOwnerPool := ACustomPool;
  if ALayout <> nil then
    LocalLayout := ALayout.Handle
  else
    LocalLayout := VK_NULL_HANDLE;

  if (ADevice <> nil) and (ADevice.Handle <> nil) and
     (ACustomPool <> VK_NULL_HANDLE) and Assigned(vkAllocateDescriptorSets) then
  begin
    FillChar(AllocInfo, SizeOf(AllocInfo), 0);
    AllocInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    AllocInfo.descriptorPool := ACustomPool;
    AllocInfo.descriptorSetCount := 1;
    AllocInfo.pSetLayouts := @LocalLayout;
    CheckVk(vkAllocateDescriptorSets(ADevice.Handle, @AllocInfo, @FHandle),
      'vkAllocateDescriptorSets(CustomPool)');
  end else
    FHandle := VkDescriptorSet(PtrUInt(Self));
  if ADevice <> nil then
    ADevice.RegisterLiveDescriptorSet(Self);
end;

procedure TVulkanRHIDescriptorSet.ReleaseDeviceResources;
var
  LocalSet: VkDescriptorSet;
begin
  if VulkanDevice <> nil then
    VulkanDevice.UnregisterLiveDescriptorSet(Self);
  SetLength(FBoundBuffers, 0);
  SetLength(FCommittedEntries, 0);
  if FUsesCustomPool then
  begin
    if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and
       (not VulkanDevice.DeferResourceDestruction) and
       ((FBoundIdleEpoch = 0) or (FBoundIdleEpoch <> VulkanDevice.FCompletedIdleEpoch)) and
       (FOwnerPool <> VK_NULL_HANDLE) and (FHandle <> VK_NULL_HANDLE) and
       Assigned(vkFreeDescriptorSets) then
    begin
      LocalSet := FHandle;
      vkFreeDescriptorSets(VulkanDevice.Handle, FOwnerPool, 1, @LocalSet);
    end;
  end else
  if (not FIsTransient) and (VulkanDevice <> nil) and (FHandle <> VK_NULL_HANDLE) then
  begin
    if (FBoundIdleEpoch <> 0) and (FBoundIdleEpoch = VulkanDevice.FCompletedIdleEpoch) then
      VulkanDevice.EnqueueInFlightDescriptorSetDeletion(FOwnerPool, FHandle)
    else
      VulkanDevice.DeferOrDestroyDescriptorSet(FOwnerPool, FHandle);
  end;
  FHandle := VK_NULL_HANDLE;
  FOwnerPool := VK_NULL_HANDLE;
  FBoundIdleEpoch := 0;
end;

destructor TVulkanRHIDescriptorSet.Destroy;
begin
  SetLength(FPendingWrites, 0);
  SetLength(FPendingWriteInfoIndices, 0);
  SetLength(FBufferInfos, 0);
  SetLength(FImageInfos, 0);
  SetLength(FAccelStructHandles, 0);
  SetLength(FAccelStructWrites, 0);
  SetLength(FBoundBuffers, 0);
  SetLength(FCommittedEntries, 0);
  inherited;
end;

procedure TVulkanRHIDescriptorSet.RecordBoundBuffer(const ABinding: Cardinal;
  const AIsStorage: Boolean; const ABuffer: TVulkanRHIBuffer;
  const AOffset, ARange: PtrUInt);
var
  I, NewIdx: Integer;
begin
  if FIsTransient then
    Exit;
  for I := 0 to High(FBoundBuffers) do
    if FBoundBuffers[I].Binding = ABinding then
    begin
      FBoundBuffers[I].IsStorage := AIsStorage;
      FBoundBuffers[I].Buffer := ABuffer;
      FBoundBuffers[I].Offset := AOffset;
      FBoundBuffers[I].Range := ARange;
      Exit;
    end;
  NewIdx := Length(FBoundBuffers);
  SetLength(FBoundBuffers, NewIdx + 1);
  FBoundBuffers[NewIdx].Binding := ABinding;
  FBoundBuffers[NewIdx].IsStorage := AIsStorage;
  FBoundBuffers[NewIdx].Buffer := ABuffer;
  FBoundBuffers[NewIdx].Offset := AOffset;
  FBoundBuffers[NewIdx].Range := ARange;
end;

procedure TVulkanRHIDescriptorSet.RecordCommittedBuffer(const ABinding: Cardinal;
  const ADescType: VkDescriptorType; const ABuffer: TVulkanRHIBuffer;
  const AOffset, ARange: VkDeviceSize);
var
  I, NewIdx: Integer;
begin
  for I := 0 to High(FCommittedEntries) do
    if (FCommittedEntries[I].Binding = ABinding) and
       (FCommittedEntries[I].ArrayElement = 0) then
    begin
      FillChar(FCommittedEntries[I], SizeOf(TVulkanCommittedDescriptorEntry), 0);
      FCommittedEntries[I].Binding := ABinding;
      FCommittedEntries[I].DescriptorType := ADescType;
      FCommittedEntries[I].BufferObj := ABuffer;
      FCommittedEntries[I].BufferHandle := ABuffer.Handle;
      FCommittedEntries[I].BufferOffset := AOffset;
      FCommittedEntries[I].BufferRange := ARange;
      Exit;
    end;
  NewIdx := Length(FCommittedEntries);
  SetLength(FCommittedEntries, NewIdx + 1);
  FillChar(FCommittedEntries[NewIdx], SizeOf(TVulkanCommittedDescriptorEntry), 0);
  FCommittedEntries[NewIdx].Binding := ABinding;
  FCommittedEntries[NewIdx].DescriptorType := ADescType;
  FCommittedEntries[NewIdx].BufferObj := ABuffer;
  FCommittedEntries[NewIdx].BufferHandle := ABuffer.Handle;
  FCommittedEntries[NewIdx].BufferOffset := AOffset;
  FCommittedEntries[NewIdx].BufferRange := ARange;
end;

procedure TVulkanRHIDescriptorSet.RecordCommittedImage(
  const ABinding, AArrayElement: Cardinal; const ADescType: VkDescriptorType;
  const ATexture: TVulkanRHITexture; const AImageView: VkImageView;
  const ASampler: VkSampler; const AImageLayout: VkImageLayout);
var
  I, NewIdx: Integer;
begin
  for I := 0 to High(FCommittedEntries) do
    if (FCommittedEntries[I].Binding = ABinding) and
       (FCommittedEntries[I].ArrayElement = AArrayElement) then
    begin
      FillChar(FCommittedEntries[I], SizeOf(TVulkanCommittedDescriptorEntry), 0);
      FCommittedEntries[I].Binding := ABinding;
      FCommittedEntries[I].ArrayElement := AArrayElement;
      FCommittedEntries[I].DescriptorType := ADescType;
      FCommittedEntries[I].TextureObj := ATexture;
      FCommittedEntries[I].ImageView := AImageView;
      FCommittedEntries[I].Sampler := ASampler;
      FCommittedEntries[I].ImageLayout := AImageLayout;
      Exit;
    end;
  NewIdx := Length(FCommittedEntries);
  SetLength(FCommittedEntries, NewIdx + 1);
  FillChar(FCommittedEntries[NewIdx], SizeOf(TVulkanCommittedDescriptorEntry), 0);
  FCommittedEntries[NewIdx].Binding := ABinding;
  FCommittedEntries[NewIdx].ArrayElement := AArrayElement;
  FCommittedEntries[NewIdx].DescriptorType := ADescType;
  FCommittedEntries[NewIdx].TextureObj := ATexture;
  FCommittedEntries[NewIdx].ImageView := AImageView;
  FCommittedEntries[NewIdx].Sampler := ASampler;
  FCommittedEntries[NewIdx].ImageLayout := AImageLayout;
end;

procedure TVulkanRHIDescriptorSet.RecordCommittedAccelStruct(const ABinding: Cardinal;
  const AAccelStruct: VkAccelerationStructureKHR);
var
  I, NewIdx: Integer;
begin
  for I := 0 to High(FCommittedEntries) do
    if (FCommittedEntries[I].Binding = ABinding) and
       (FCommittedEntries[I].ArrayElement = 0) then
    begin
      FillChar(FCommittedEntries[I], SizeOf(TVulkanCommittedDescriptorEntry), 0);
      FCommittedEntries[I].Binding := ABinding;
      FCommittedEntries[I].DescriptorType := VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;
      FCommittedEntries[I].AccelStructHandle := AAccelStruct;
      Exit;
    end;
  NewIdx := Length(FCommittedEntries);
  SetLength(FCommittedEntries, NewIdx + 1);
  FillChar(FCommittedEntries[NewIdx], SizeOf(TVulkanCommittedDescriptorEntry), 0);
  FCommittedEntries[NewIdx].Binding := ABinding;
  FCommittedEntries[NewIdx].DescriptorType := VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;
  FCommittedEntries[NewIdx].AccelStructHandle := AAccelStruct;
end;

procedure TVulkanRHIDescriptorSet.ClearBoundBuffer(const ABuffer: TVulkanRHIBuffer);
var
  I, WriteIdx: Integer;
begin
  for I := 0 to High(FBoundBuffers) do
    if FBoundBuffers[I].Buffer = ABuffer then
      FBoundBuffers[I].Buffer := nil;
  WriteIdx := 0;
  for I := 0 to High(FCommittedEntries) do
    if FCommittedEntries[I].BufferObj <> ABuffer then
    begin
      if WriteIdx <> I then
        FCommittedEntries[WriteIdx] := FCommittedEntries[I];
      Inc(WriteIdx);
    end;
  if WriteIdx <> Length(FCommittedEntries) then
    SetLength(FCommittedEntries, WriteIdx);
end;

procedure TVulkanRHIDescriptorSet.ClearBoundTexture(const ATexture: TVulkanRHITexture);
var
  I, WriteIdx: Integer;
begin
  if FLastBoundTexture = ATexture then
    FLastBoundTexture := nil;
  WriteIdx := 0;
  for I := 0 to High(FCommittedEntries) do
    if FCommittedEntries[I].TextureObj <> ATexture then
    begin
      if WriteIdx <> I then
        FCommittedEntries[WriteIdx] := FCommittedEntries[I];
      Inc(WriteIdx);
    end;
  if WriteIdx <> Length(FCommittedEntries) then
    SetLength(FCommittedEntries, WriteIdx);
end;

procedure TVulkanRHIDescriptorSet.MarkBoundToLiveCommandBuffer;
begin
  if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) then
  begin
    if VulkanDevice.FCompletedIdleEpoch = 0 then
      VulkanDevice.FCompletedIdleEpoch := 1;
    FBoundIdleEpoch := VulkanDevice.FCompletedIdleEpoch;
  end;
end;

procedure TVulkanRHIDescriptorSet.RefreshRelocatedBuffer(const ABuffer: TVulkanRHIBuffer);
var
  I: Integer;
  AnyRebound: Boolean;
begin
  if (ABuffer = nil) or (FHandle = VK_NULL_HANDLE) then
    Exit;
  AnyRebound := False;
  for I := 0 to High(FBoundBuffers) do
    if FBoundBuffers[I].Buffer = ABuffer then
    begin
      if FBoundBuffers[I].IsStorage then
        BindStorageBuffer(FBoundBuffers[I].Binding, ABuffer, FBoundBuffers[I].Offset, FBoundBuffers[I].Range)
      else
        BindUniformBuffer(FBoundBuffers[I].Binding, ABuffer, FBoundBuffers[I].Offset, FBoundBuffers[I].Range);
      AnyRebound := True;
    end;
  if AnyRebound then
    Update;
end;

procedure TVulkanRHIDescriptorSet.BindUniformBuffer(const Binding: Cardinal;
  const Buffer: TRHIBuffer; const Offset, Range: PtrUInt);
var
  Idx, WriteIdx: Integer;
  DeclType: TRHIDescriptorType;
  VkDescType: VkDescriptorType;
  EffRange: VkDeviceSize;
begin
  if Buffer = nil then Exit;
  RecordBoundBuffer(Binding, False, Buffer as TVulkanRHIBuffer, Offset, Range);
  VkDescType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
  if (FLayout <> nil) and FLayout.TryGetBindingType(Binding, DeclType) and
     (DeclType = dtUniformBufferDynamic) then
    VkDescType := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC;
  if Range > 0 then
    EffRange := Range
  else
    EffRange := Buffer.Desc.Size - Offset;
  RecordCommittedBuffer(Binding, VkDescType, Buffer as TVulkanRHIBuffer, Offset, EffRange);

  Idx := Length(FBufferInfos);
  SetLength(FBufferInfos, Idx + 1);
  FillChar(FBufferInfos[Idx], SizeOf(VkDescriptorBufferInfo), 0);
  FBufferInfos[Idx].buffer := (Buffer as TVulkanRHIBuffer).Handle;
  FBufferInfos[Idx].offset := Offset;
  FBufferInfos[Idx].range := EffRange;

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
  FPendingWrites[WriteIdx].descriptorType := VkDescType;
end;

procedure TVulkanRHIDescriptorSet.BindStorageBuffer(const Binding: Cardinal;
  const Buffer: TRHIBuffer; const Offset, Range: PtrUInt);
var
  Idx, WriteIdx: Integer;
  EffRange: VkDeviceSize;
begin
  if Buffer = nil then Exit;
  RecordBoundBuffer(Binding, True, Buffer as TVulkanRHIBuffer, Offset, Range);
  if Range > 0 then
    EffRange := Range
  else
    EffRange := Buffer.Desc.Size - Offset;
  RecordCommittedBuffer(Binding, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
    Buffer as TVulkanRHIBuffer, Offset, EffRange);

  Idx := Length(FBufferInfos);
  SetLength(FBufferInfos, Idx + 1);
  FillChar(FBufferInfos[Idx], SizeOf(VkDescriptorBufferInfo), 0);
  FBufferInfos[Idx].buffer := (Buffer as TVulkanRHIBuffer).Handle;
  FBufferInfos[Idx].offset := Offset;
  FBufferInfos[Idx].range := EffRange;

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
  DeclType: TRHIDescriptorType;
  VkDescType: VkDescriptorType;
begin
  if Texture = nil then Exit;
  FLastBoundTexture := Texture;
  FLastBoundSampler := Sampler;

  DeclType := dtCombinedImageSampler;
  if FLayout <> nil then
    FLayout.TryGetBindingType(Binding, DeclType);

  Idx := Length(FImageInfos);
  SetLength(FImageInfos, Idx + 1);
  FillChar(FImageInfos[Idx], SizeOf(VkDescriptorImageInfo), 0);
  FImageInfos[Idx].imageView := (Texture as TVulkanRHITexture).ImageView;

  case DeclType of
    dtStorageImage:
      begin
        FImageInfos[Idx].sampler := VK_NULL_HANDLE;
        FImageInfos[Idx].imageLayout := VK_IMAGE_LAYOUT_GENERAL;
        VkDescType := VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
      end;
    dtSampledImage:
      begin
        FImageInfos[Idx].sampler := VK_NULL_HANDLE;
        FImageInfos[Idx].imageLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        VkDescType := VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
      end;
    else
      begin
        if Sampler <> nil then
          FImageInfos[Idx].sampler := (Sampler as TVulkanRHISampler).Handle
        else
        if VulkanDevice <> nil then
          FImageInfos[Idx].sampler := VulkanDevice.GetDefaultSampler.Handle
        else
          FImageInfos[Idx].sampler := VK_NULL_HANDLE;
        FImageInfos[Idx].imageLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        VkDescType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
      end;
  end;
  RecordCommittedImage(Binding, ArrayElement, VkDescType,
    Texture as TVulkanRHITexture, FImageInfos[Idx].imageView,
    FImageInfos[Idx].sampler, FImageInfos[Idx].imageLayout);

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
  FPendingWrites[WriteIdx].descriptorType := VkDescType;
end;

procedure TVulkanRHIDescriptorSet.BindTextureSubresource(const Binding: Cardinal;
  const Texture: TRHITexture; const MipLevel, ArrayLayer: Cardinal;
  const Sampler: TRHISampler);
var
  Idx, WriteIdx: Integer;
  DeclType: TRHIDescriptorType;
  VkDescType: VkDescriptorType;
  VkTex: TVulkanRHITexture;
begin
  if Texture = nil then Exit;
  VkTex := Texture as TVulkanRHITexture;
  FLastBoundTexture := Texture;
  FLastBoundSampler := Sampler;

  DeclType := dtCombinedImageSampler;
  if FLayout <> nil then
    FLayout.TryGetBindingType(Binding, DeclType);

  Idx := Length(FImageInfos);
  SetLength(FImageInfos, Idx + 1);
  FillChar(FImageInfos[Idx], SizeOf(VkDescriptorImageInfo), 0);
  FImageInfos[Idx].imageView := VkTex.GetSubresourceImageView(MipLevel, ArrayLayer);

  case DeclType of
    dtStorageImage:
      begin
        FImageInfos[Idx].sampler := VK_NULL_HANDLE;
        FImageInfos[Idx].imageLayout := VK_IMAGE_LAYOUT_GENERAL;
        VkDescType := VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
      end;
    dtSampledImage:
      begin
        FImageInfos[Idx].sampler := VK_NULL_HANDLE;
        FImageInfos[Idx].imageLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        VkDescType := VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
      end;
    else
      begin
        if Sampler <> nil then
          FImageInfos[Idx].sampler := (Sampler as TVulkanRHISampler).Handle
        else if VulkanDevice <> nil then
          FImageInfos[Idx].sampler := VulkanDevice.GetDefaultSampler.Handle
        else
          FImageInfos[Idx].sampler := VK_NULL_HANDLE;
        FImageInfos[Idx].imageLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        VkDescType := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
      end;
  end;
  RecordCommittedImage(Binding, 0, VkDescType, VkTex,
    FImageInfos[Idx].imageView, FImageInfos[Idx].sampler,
    FImageInfos[Idx].imageLayout);

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
  FPendingWrites[WriteIdx].descriptorType := VkDescType;
end;

procedure TVulkanRHIDescriptorSet.BindAccelerationStructure(const Binding: Cardinal;
  const AAccelerationStructure: VkAccelerationStructureKHR);
var
  Idx, WriteIdx: Integer;
begin
  if AAccelerationStructure = VK_NULL_HANDLE then Exit;
  RecordCommittedAccelStruct(Binding, AAccelerationStructure);
  Idx := Length(FAccelStructHandles);
  SetLength(FAccelStructHandles, Idx + 1);
  SetLength(FAccelStructWrites, Idx + 1);
  FAccelStructHandles[Idx] := AAccelerationStructure;
  FillChar(FAccelStructWrites[Idx], SizeOf(VkWriteDescriptorSetAccelerationStructureKHR), 0);
  FAccelStructWrites[Idx].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR;
  FAccelStructWrites[Idx].accelerationStructureCount := 1;

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
  FPendingWrites[WriteIdx].descriptorType := VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;
end;

procedure TVulkanRHIDescriptorSet.Update;
var
  I, InfoIdx, EntryCount: Integer;
  PoolAlloc: TVulkanDescriptorPoolAllocator;
  SetLayoutHandle: VkDescriptorSetLayout;
  CowWrites: array of VkWriteDescriptorSet;
  CowBufferInfos: array of VkDescriptorBufferInfo;
  CowImageInfos: array of VkDescriptorImageInfo;
  CowAccelHandles: array of VkAccelerationStructureKHR;
  CowAccelWrites: array of VkWriteDescriptorSetAccelerationStructureKHR;
begin
  if Length(FPendingWrites) > 0 then
  begin
    { Copy-On-Write rotation (VUID-vkUpdateDescriptorSets-None-03047):
      If FHandle has already been bound to a recording or in-flight VkCommandBuffer
      since the last GPU idle point, allocate a fresh VkDescriptorSet and retire the
      previous handle into FDeferredDeletions so pending command buffers remain untouched. }
    if (VulkanDevice <> nil) and (VulkanDevice.Handle <> nil) and
       (not FUsesCustomPool) and
       ((FLayout = nil) or (not FLayout.AllBindingsUpdateAfterBind)) and
       (FBoundIdleEpoch <> 0) and
       (FBoundIdleEpoch = VulkanDevice.FCompletedIdleEpoch) then
    begin
      if FLayout <> nil then
        SetLayoutHandle := FLayout.Handle
      else
        SetLayoutHandle := VK_NULL_HANDLE;
      if FIsTransient then
        PoolAlloc := VulkanDevice.GetTransientDescriptorAllocator(VulkanDevice.FrameIndex)
      else
        PoolAlloc := VulkanDevice.PersistentDescriptorAllocator;

      if PoolAlloc <> nil then
      begin
        if (not FIsTransient) and (FHandle <> VK_NULL_HANDLE) then
          VulkanDevice.EnqueueInFlightDescriptorSetDeletion(FOwnerPool, FHandle);
        FHandle := PoolAlloc.AllocateDescriptorSet(SetLayoutHandle, FOwnerPool);
        FBoundIdleEpoch := 0;

        EntryCount := Length(FCommittedEntries);
        if (EntryCount > 0) and Assigned(vkUpdateDescriptorSets) then
        begin
          SetLength(CowWrites, EntryCount);
          SetLength(CowBufferInfos, EntryCount);
          SetLength(CowImageInfos, EntryCount);
          SetLength(CowAccelHandles, EntryCount);
          SetLength(CowAccelWrites, EntryCount);
          for I := 0 to EntryCount - 1 do
          begin
            FillChar(CowWrites[I], SizeOf(VkWriteDescriptorSet), 0);
            CowWrites[I].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            CowWrites[I].dstSet := FHandle;
            CowWrites[I].dstBinding := FCommittedEntries[I].Binding;
            CowWrites[I].dstArrayElement := FCommittedEntries[I].ArrayElement;
            CowWrites[I].descriptorCount := 1;
            CowWrites[I].descriptorType := FCommittedEntries[I].DescriptorType;
            if FCommittedEntries[I].DescriptorType = VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR then
            begin
              CowAccelHandles[I] := FCommittedEntries[I].AccelStructHandle;
              FillChar(CowAccelWrites[I], SizeOf(VkWriteDescriptorSetAccelerationStructureKHR), 0);
              CowAccelWrites[I].sType := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR;
              CowAccelWrites[I].accelerationStructureCount := 1;
              CowAccelWrites[I].pAccelerationStructures := @CowAccelHandles[I];
              CowWrites[I].pNext := @CowAccelWrites[I];
            end else
            if (FCommittedEntries[I].DescriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) or
               (FCommittedEntries[I].DescriptorType = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE) or
               (FCommittedEntries[I].DescriptorType = VK_DESCRIPTOR_TYPE_SAMPLER) or
               (FCommittedEntries[I].DescriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) then
            begin
              FillChar(CowImageInfos[I], SizeOf(VkDescriptorImageInfo), 0);
              CowImageInfos[I].imageView := FCommittedEntries[I].ImageView;
              CowImageInfos[I].sampler := FCommittedEntries[I].Sampler;
              CowImageInfos[I].imageLayout := FCommittedEntries[I].ImageLayout;
              CowWrites[I].pImageInfo := @CowImageInfos[I];
            end else
            begin
              FillChar(CowBufferInfos[I], SizeOf(VkDescriptorBufferInfo), 0);
              CowBufferInfos[I].buffer := FCommittedEntries[I].BufferHandle;
              CowBufferInfos[I].offset := FCommittedEntries[I].BufferOffset;
              CowBufferInfos[I].range := FCommittedEntries[I].BufferRange;
              CowWrites[I].pBufferInfo := @CowBufferInfos[I];
            end;
          end;
          vkUpdateDescriptorSets(VulkanDevice.Handle, EntryCount, @CowWrites[0], 0, nil);
        end;

        Inc(FUpdateCount);
        SetLength(FPendingWrites, 0);
        SetLength(FPendingWriteInfoIndices, 0);
        SetLength(FBufferInfos, 0);
        SetLength(FImageInfos, 0);
        SetLength(FAccelStructHandles, 0);
        SetLength(FAccelStructWrites, 0);
        Exit;
      end;
    end;

    for I := 0 to High(FPendingWrites) do
    begin
      FPendingWrites[I].dstSet := FHandle;
      InfoIdx := FPendingWriteInfoIndices[I];
      if FPendingWrites[I].descriptorType = VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR then
      begin
        FAccelStructWrites[InfoIdx].pAccelerationStructures := @FAccelStructHandles[InfoIdx];
        FPendingWrites[I].pNext := @FAccelStructWrites[InfoIdx];
      end else
      if (FPendingWrites[I].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) or
         (FPendingWrites[I].descriptorType = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE) or
         (FPendingWrites[I].descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER) or
         (FPendingWrites[I].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE) then
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
    SetLength(FAccelStructHandles, 0);
    SetLength(FAccelStructWrites, 0);
  end;
end;

constructor TVulkanRHIPipeline.Create(const ADevice: TVulkanRHIDevice;
  const AInputDesc: TRHIGraphicsPipelineDesc);
var
  ADesc: TRHIGraphicsPipelineDesc;
  SetLayouts: array of VkDescriptorSetLayout;
  PushRange: VkPushConstantRange;
  LayoutInfo: VkPipelineLayoutCreateInfo;
  Stages: array[0..3] of VkPipelineShaderStageCreateInfo;
  IsMeshPipeline: Boolean;
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
  DynamicStates: array[0..9] of VkDynamicState;
  DynamicStateCount: Cardinal;
  DynamicStateInfo: VkPipelineDynamicStateCreateInfo;
  ColorFormats: array of VkFormat;
  RenderingInfo: VkPipelineRenderingCreateInfoKHR;
  PipelineInfo: VkGraphicsPipelineCreateInfo;
  LibHandles: array[0..3] of VkPipeline;
  LinkInfo: VkPipelineLibraryCreateInfoKHR;
  EmptySetLayoutInfo: VkDescriptorSetLayoutCreateInfo;
  TempEmptySetLayout: VkDescriptorSetLayout;
  I: Integer;
begin
  if (ADevice <> nil) and ADevice.PortabilitySubsetCaps.Active then
    ADesc := AdaptPipelineDescForPortabilitySubset(AInputDesc, ADevice.PortabilitySubsetCaps)
  else
    ADesc := AInputDesc;
  if (ADevice <> nil) and (ADevice.Handle <> nil) and
     (ADevice.PhysicalDevice <> nil) and (ADesc.DepthAttachmentFormat <> pfUndefined) then
    ADesc.DepthAttachmentFormat := NegotiateOptimalPixelFormat(
      ADesc.DepthAttachmentFormat, [tuDepthStencil], ADevice.PhysicalDevice);
  inherited Create(ADevice, ADesc);
  if (ADevice <> nil) and (not ADevice.SupportsDynamicRendering) then
    FRenderPass := ADevice.GetOrCreateFallbackRenderPass(
      ADesc.ColorAttachmentFormats, ADesc.DepthAttachmentFormat, ADesc.SampleCount);
  if ADevice = nil then Exit;

  { 1. Construct VkPipelineLayout from ADesc.DescriptorSetLayouts and PushConstants }
  if ADevice.Handle <> nil then
  begin
    TempEmptySetLayout := VK_NULL_HANDLE;
    try
      SetLength(SetLayouts, Length(ADesc.DescriptorSetLayouts));
      for I := 0 to High(ADesc.DescriptorSetLayouts) do
        if ADesc.DescriptorSetLayouts[I] <> nil then
          SetLayouts[I] := (ADesc.DescriptorSetLayouts[I] as TVulkanRHIDescriptorSetLayout).Handle
        else
        begin
          if TempEmptySetLayout = VK_NULL_HANDLE then
          begin
            FillChar(EmptySetLayoutInfo, SizeOf(EmptySetLayoutInfo), 0);
            EmptySetLayoutInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
            CheckVk(vkCreateDescriptorSetLayout(ADevice.Handle, @EmptySetLayoutInfo, nil, @TempEmptySetLayout),
              'vkCreateDescriptorSetLayout(EmptyPlaceholder)');
          end;
          SetLayouts[I] := TempEmptySetLayout;
        end;

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
    finally
      if TempEmptySetLayout <> VK_NULL_HANDLE then
        vkDestroyDescriptorSetLayout(ADevice.Handle, TempEmptySetLayout, nil);
    end;
  end;

  IsMeshPipeline := ADesc.MeshShader <> nil;

  { Fast-Link Path via VK_EXT_graphics_pipeline_library (vertex-pipeline only) }
  if ADevice.SupportsGraphicsPipelineLibrary and (not IsMeshPipeline) then
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
    begin
      CheckVk(vkCreateGraphicsPipelines(ADevice.Handle, ADevice.PipelineCache, 1, @PipelineInfo, nil, @FHandle), 'vkCreateGraphicsPipelines(GPL-Link)');
      if FHandle <> VK_NULL_HANDLE then
      begin
        if (ADesc.VertexShader <> nil) and (ADesc.VertexShader.DebugName <> '') then
          ADevice.SetDebugObjectName(VK_OBJECT_TYPE_PIPELINE, FHandle, ADesc.VertexShader.DebugName + '_GPLPipeline')
        else
          ADevice.SetDebugObjectName(VK_OBJECT_TYPE_PIPELINE, FHandle, 'CastleGraphicsPipelineGPL');
      end;
    end;
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
  if IsMeshPipeline then
  begin
    if (ADesc.TaskShader <> nil) and ((ADesc.TaskShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE) then
    begin
      Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
      Stages[StageCount].stage := VK_SHADER_STAGE_TASK_BIT_EXT;
      Stages[StageCount].module := (ADesc.TaskShader as TVulkanRHIShaderModule).Handle;
      Stages[StageCount].pName := 'main';
      Inc(StageCount);
    end;
    if (ADesc.MeshShader as TVulkanRHIShaderModule).Handle <> VK_NULL_HANDLE then
    begin
      Stages[StageCount].sType := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
      Stages[StageCount].stage := VK_SHADER_STAGE_MESH_BIT_EXT;
      Stages[StageCount].module := (ADesc.MeshShader as TVulkanRHIShaderModule).Handle;
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
  end else
  begin
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
  if ADesc.DepthAttachmentFormat <> pfUndefined then
  begin
    DepthStencil.depthTestEnable := Ord(ADesc.DepthStencil.DepthTestEnable);
    DepthStencil.depthWriteEnable := Ord(ADesc.DepthStencil.DepthWriteEnable);
    DepthStencil.depthCompareOp := RHIToVkCompareOp(ADesc.DepthStencil.DepthCompareOp);
    if ADesc.DepthAttachmentFormat in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
      DepthStencil.stencilTestEnable := Ord(ADesc.DepthStencil.StencilTestEnable);
  end;
  DepthStencil.front := RHIToVkStencilOpState(ADesc.DepthStencil.FrontStencil);
  DepthStencil.back := RHIToVkStencilOpState(ADesc.DepthStencil.BackStencil);

  SetLength(BlendAttachments, Length(ADesc.ColorAttachmentFormats));
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
  ColorBlending.blendConstants[0] := 1.0;
  ColorBlending.blendConstants[1] := 1.0;
  ColorBlending.blendConstants[2] := 1.0;
  ColorBlending.blendConstants[3] := 1.0;

  DynamicStates[0] := VK_DYNAMIC_STATE_VIEWPORT;
  DynamicStates[1] := VK_DYNAMIC_STATE_SCISSOR;
  DynamicStateCount := 2;
  if ADesc.Rasterizer.DepthBiasEnable then
  begin
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_DEPTH_BIAS;
    Inc(DynamicStateCount);
  end;
  if ADesc.BlendState.BlendEnable then
  begin
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_BLEND_CONSTANTS;
    Inc(DynamicStateCount);
  end;
  if ADevice.SupportsExtendedDynamicState then
  begin
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_CULL_MODE; Inc(DynamicStateCount);
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_FRONT_FACE; Inc(DynamicStateCount);
    if not IsMeshPipeline then
    begin
      DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY;
      Inc(DynamicStateCount);
    end;
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE; Inc(DynamicStateCount);
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE; Inc(DynamicStateCount);
    DynamicStates[DynamicStateCount] := VK_DYNAMIC_STATE_DEPTH_COMPARE_OP; Inc(DynamicStateCount);
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
  if ADesc.DepthAttachmentFormat in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
    RenderingInfo.stencilAttachmentFormat := RenderingInfo.depthAttachmentFormat;

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
  if IsMeshPipeline then
  begin
    PipelineInfo.pVertexInputState := nil;
    PipelineInfo.pInputAssemblyState := nil;
  end else
  begin
    PipelineInfo.pVertexInputState := @VertexInputInfo;
    PipelineInfo.pInputAssemblyState := @InputAssembly;
  end;
  PipelineInfo.pViewportState := @ViewportState;
  PipelineInfo.pRasterizationState := @Rasterizer;
  PipelineInfo.pMultisampleState := @Multisampling;
  PipelineInfo.pDepthStencilState := @DepthStencil;
  PipelineInfo.pColorBlendState := @ColorBlending;
  PipelineInfo.pDynamicState := @DynamicStateInfo;
  PipelineInfo.layout := FPipelineLayout;

  if StageCount > 0 then
    CheckVk(vkCreateGraphicsPipelines(ADevice.Handle, ADevice.PipelineCache, 1, @PipelineInfo, nil, @FHandle), 'vkCreateGraphicsPipelines');
  if ADesc.DebugName <> '' then
  begin
    if FHandle <> VK_NULL_HANDLE then
      ADevice.SetDebugObjectName(VK_OBJECT_TYPE_PIPELINE, FHandle, ADesc.DebugName);
    if FPipelineLayout <> VK_NULL_HANDLE then
      ADevice.SetDebugObjectName(VK_OBJECT_TYPE_PIPELINE_LAYOUT, FPipelineLayout, ADesc.DebugName + '.Layout');
  end;
end;

procedure TVulkanRHIPipeline.ReleaseDeviceResources;
begin
  if (Device <> nil) and (TVulkanRHIDevice(Device).Handle <> nil) then
  begin
    if (FHandle <> VK_NULL_HANDLE) and Assigned(vkDestroyPipeline) then
      vkDestroyPipeline(TVulkanRHIDevice(Device).Handle, FHandle, nil);
    if (FPipelineLayout <> VK_NULL_HANDLE) and Assigned(vkDestroyPipelineLayout) then
      vkDestroyPipelineLayout(TVulkanRHIDevice(Device).Handle, FPipelineLayout, nil);
  end;
  FHandle := VK_NULL_HANDLE;
  FPipelineLayout := VK_NULL_HANDLE;
end;

destructor TVulkanRHIPipeline.Destroy;
begin
  inherited;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHIComputePipeline (Phase 6.5)                                        }
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHIComputePipeline.Create(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHIComputePipelineDesc; const AOwnsHandle: Boolean);
var
  SetLayouts: array of VkDescriptorSetLayout;
  TempEmptySetLayout: VkDescriptorSetLayout;
  EmptySetLayoutInfo: VkDescriptorSetLayoutCreateInfo;
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

  TempEmptySetLayout := VK_NULL_HANDLE;
  try
    SetLength(SetLayouts, Length(ADesc.DescriptorSetLayouts));
    for I := 0 to High(ADesc.DescriptorSetLayouts) do
      if ADesc.DescriptorSetLayouts[I] <> nil then
        SetLayouts[I] := (ADesc.DescriptorSetLayouts[I] as TVulkanRHIDescriptorSetLayout).Handle
      else
      begin
        if TempEmptySetLayout = VK_NULL_HANDLE then
        begin
          FillChar(EmptySetLayoutInfo, SizeOf(EmptySetLayoutInfo), 0);
          EmptySetLayoutInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
          CheckVk(vkCreateDescriptorSetLayout(ADevice.Handle, @EmptySetLayoutInfo, nil, @TempEmptySetLayout),
            'vkCreateDescriptorSetLayout(EmptyComputePlaceholder)');
        end;
        SetLayouts[I] := TempEmptySetLayout;
      end;

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
  finally
    if TempEmptySetLayout <> VK_NULL_HANDLE then
      vkDestroyDescriptorSetLayout(ADevice.Handle, TempEmptySetLayout, nil);
  end;

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
  if ADesc.DebugName <> '' then
  begin
    if FHandle <> VK_NULL_HANDLE then
      ADevice.SetDebugObjectName(VK_OBJECT_TYPE_PIPELINE, FHandle, ADesc.DebugName);
    if FPipelineLayout <> VK_NULL_HANDLE then
      ADevice.SetDebugObjectName(VK_OBJECT_TYPE_PIPELINE_LAYOUT, FPipelineLayout, ADesc.DebugName + '.Layout');
  end;
end;

procedure TVulkanRHIComputePipeline.ReleaseDeviceResources;
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
end;

destructor TVulkanRHIComputePipeline.Destroy;
begin
  inherited;
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanRHIQueryPool (Phase 6.7)                                              }
{ ---------------------------------------------------------------------------- }

constructor TVulkanRHIQueryPool.Create(const ADevice: TVulkanRHIDevice;
  const ADesc: TRHIQueryPoolDesc);
var
  PoolInfo: VkQueryPoolCreateInfo;
  Count, I: Cardinal;
begin
  inherited Create(ADevice, ADesc);
  Count := Max(Cardinal(1), ADesc.QueryCount);
  SetLength(FSimulatedResults, Count);
  SetLength(FQueryWritten, Count);
  SetLength(FQueryResetReady, Count);
  SetLength(FQueryRecordedGeneration, Count);
  SetLength(FQueryActiveInCmd, Count);

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
    if FHandle <> VK_NULL_HANDLE then
    begin
      if ADesc.QueryType = qtTimestamp then
        ADevice.SetDebugObjectName(VK_OBJECT_TYPE_QUERY_POOL, FHandle, 'CastleTimestampQueryPool')
      else
        ADevice.SetDebugObjectName(VK_OBJECT_TYPE_QUERY_POOL, FHandle, 'CastleOcclusionQueryPool');
    end;
    if ADevice.SupportsHostQueryReset and Assigned(vkResetQueryPool) then
    begin
      vkResetQueryPool(ADevice.Handle, FHandle, 0, Count);
      for I := 0 to Count - 1 do
        FQueryResetReady[I] := True;
      Inc(FHostResetCount);
    end;
  end else
  begin
    FHandle := VkQueryPool(PtrUInt(Self));
    for I := 0 to Count - 1 do
      FQueryResetReady[I] := True;
  end;
end;

procedure TVulkanRHIQueryPool.ReleaseDeviceResources;
begin
  if (FHandle <> VK_NULL_HANDLE) and (Device <> nil) and
     (TVulkanRHIDevice(Device).Handle <> nil) and Assigned(vkDestroyQueryPool) then
    vkDestroyQueryPool(TVulkanRHIDevice(Device).Handle, FHandle, nil);
  FHandle := VK_NULL_HANDLE;
end;

destructor TVulkanRHIQueryPool.Destroy;
begin
  SetLength(FSimulatedResults, 0);
  SetLength(FQueryWritten, 0);
  SetLength(FQueryResetReady, 0);
  SetLength(FQueryRecordedGeneration, 0);
  SetLength(FQueryActiveInCmd, 0);
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

{$endif read_implementation}
