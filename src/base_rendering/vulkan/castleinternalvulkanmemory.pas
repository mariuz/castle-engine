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

{ Vulkan GPU memory sub-allocator and per-frame ring buffer for Castle Game Engine.
  Avoids hitting maxMemoryAllocationCount limits by sub-allocating buffers and
  textures from pooled VkDeviceMemory blocks with automatic free-block coalescing. }
unit CastleInternalVulkanMemory;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Generics.Collections, SyncObjs,
  CastleLog, CastleInternalRHI, CastleInternalVulkan;

type
  TCastleVulkanMemoryBlock = class;
  TCastleVulkanMemoryAllocator = class;

  { Internal linked-list node tracking used and free sub-ranges inside a block }
  PVulkanSubAllocationNode = ^TVulkanSubAllocationNode;
  TVulkanSubAllocationNode = record
    ChunkId: Cardinal;
    Offset: VkDeviceSize;
    Size: VkDeviceSize;
    IsFree: Boolean;
    IsBufferImageGranularityTainted: Boolean;
    Prev: PVulkanSubAllocationNode;
    Next: PVulkanSubAllocationNode;
  end;

  { Represents a single sub-allocation (or dedicated allocation) of Vulkan memory. }
  TVulkanMemoryAllocation = record
    { Underlying VkDeviceMemory handle (owned by Block, or standalone if IsDedicated) }
    DeviceMemory: VkDeviceMemory;
    { Byte offset within DeviceMemory (must be passed to vkBindBufferMemory / vkBindImageMemory) }
    Offset: VkDeviceSize;
    { Usable byte size of this allocation }
    Size: VkDeviceSize;
    { Non-nil if allocated from a host-visible, persistently mapped block }
    MappedPtr: Pointer;
    { Owning pool block (nil if IsDedicated = True) }
    Block: TCastleVulkanMemoryBlock;
    { Direct pointer to the doubly-linked sub-allocation node for O(1) free & coalescing }
    Node: PVulkanSubAllocationNode;
    { Internal chunk ID for validation / fallback lookup }
    ChunkId: Cardinal;
    { True if this allocation bypassed the pool and owns its own VkDeviceMemory }
    IsDedicated: Boolean;
    { True if the underlying memory type has VK_MEMORY_PROPERTY_HOST_COHERENT_BIT }
    IsHostCoherent: Boolean;
    { True if MappedPtr was allocated on the CPU heap in headless simulation mode }
    IsSimulatedHostMemory: Boolean;
    function IsValid: Boolean;
  end;

  { Fast per-frame bump/ring allocation result for transient UBOs & dynamic vertices }
  TVulkanTransientAllocation = record
    Buffer: VkBuffer;
    Offset: VkDeviceSize;
    Size: VkDeviceSize;
    MappedPtr: Pointer;
  end;

  { Statistics for CGE Profiler / Viewport.Statistics }
  TVulkanMemoryStats = record
    TotalBlockCount: Cardinal;
    LinearBlockCount: Cardinal;
    NonLinearBlockCount: Cardinal;
    DedicatedAllocationCount: Cardinal;
    TotalVkAllocationCount: Cardinal;
    MaxMemoryAllocationCount: Cardinal;
    SubAllocationCount: Cardinal;
    TotalAllocatedBytes: UInt64;
    TotalUsedBytes: UInt64;
    DeviceMemoryUsedBytes: UInt64;
    DeviceMemoryBudgetBytes: UInt64;
    DeviceMemoryUsedMB: Cardinal;
    DeviceMemoryBudgetMB: Cardinal;
    SupportsMemoryBudgetExtension: Boolean;
  end;

  { A single large VkDeviceMemory allocation (e.g. 64 MB) subdivided into chunks. }
  TCastleVulkanMemoryBlock = class
  private
    FDevice: VkDevice;
    FMemoryTypeIndex: Cardinal;
    FIsLinearPool: Boolean;
    FIsHostCoherent: Boolean;
    FSimulatedMemory: Boolean;
    FDeviceMemory: VkDeviceMemory;
    FSize: VkDeviceSize;
    FUsedBytes: VkDeviceSize;
    FBaseMappedPtr: PByte;
    FHead: PVulkanSubAllocationNode;
    FNextChunkId: Cardinal;
    FActiveSubAllocations: Cardinal;
  public
    constructor Create(const ADevice: VkDevice; const AMemoryTypeIndex: Cardinal;
      const ABlockSize: VkDeviceSize; const AHostVisible: Boolean;
      const AIsLinearPool: Boolean = True;
      const AIsHostCoherent: Boolean = True);
    destructor Destroy; override;

    { Attempts to sub-allocate Size bytes aligned to Alignment (and respecting
      bufferImageGranularity). Returns True on success. }
    function TrySubAllocate(const ASize, AAlignment, AGranularity: VkDeviceSize;
      const AIsLinearResource: Boolean; out AAlloc: TVulkanMemoryAllocation): Boolean;

    { Frees a previously sub-allocated chunk in O(1) time and coalesces adjacent free nodes. }
    procedure FreeSubAllocation(const AAlloc: TVulkanMemoryAllocation);

    function IsEmpty: Boolean;

    property DeviceMemory: VkDeviceMemory read FDeviceMemory;
    property MemoryTypeIndex: Cardinal read FMemoryTypeIndex;
    property IsLinearPool: Boolean read FIsLinearPool;
    property IsHostCoherent: Boolean read FIsHostCoherent;
    property Size: VkDeviceSize read FSize;
    property UsedBytes: VkDeviceSize read FUsedBytes;
    property ActiveSubAllocations: Cardinal read FActiveSubAllocations;
  end;

  TCastleVulkanBlockList = {$ifdef FPC}specialize{$endif} TObjectList<TCastleVulkanMemoryBlock>;

  { Fast lock-free bump allocator for per-frame dynamic Uniform Buffers and 2D/UI vertices. }
  TCastleVulkanFrameRingBuffer = class
  private
    FAllocator: TCastleVulkanMemoryAllocator;
    FDevice: VkDevice;
    FBuffer: VkBuffer;
    FAllocation: TVulkanMemoryAllocation;
    FCapacity: VkDeviceSize;
    FCurrentOffset: VkDeviceSize;
    FMinAlignment: VkDeviceSize;
  public
    constructor Create(const AAllocator: TCastleVulkanMemoryAllocator;
      const ACapacity: VkDeviceSize; const AMinAlignment: VkDeviceSize);
    destructor Destroy; override;

    { Resets the write cursor to 0 at the start of a frame-in-flight (after fence wait). }
    procedure Reset;

    { Allocates aligned transient bytes from the ring buffer. }
    function Allocate(const ASize: VkDeviceSize; const AAlignment: VkDeviceSize = 256): TVulkanTransientAllocation;

    property Buffer: VkBuffer read FBuffer;
    property Capacity: VkDeviceSize read FCapacity;
    property UsedBytes: VkDeviceSize read FCurrentOffset;
  end;

  { Central GPU memory manager owned by TVulkanRHIDevice.
    Inspired by PasVulkan's TpvVulkanMemoryManager and AMD VMA:
    - Keeps total vkAllocateMemory count strictly below Windows WDDM's 4096 limit
      (VkPhysicalDeviceLimits.maxMemoryAllocationCount).
    - Separates Linear (VkBuffer) and Non-Linear (Optimal Tiled VkImage) block pools
      per memoryTypeIndex to avoid bufferImageGranularity page aliasing.
    - Supports Vulkan 1.1 VK_KHR_dedicated_allocation (VkMemoryDedicatedRequirements /
      VkMemoryDedicatedAllocateInfo) with automatic fallback to pooled blocks when
      approaching maxMemoryAllocationCount. }
  TCastleVulkanMemoryAllocator = class
  private
    FPhysicalDevice: VkPhysicalDevice;
    FDevice: VkDevice;
    FMemProperties: VkPhysicalDeviceMemoryProperties;
    FBufferImageGranularity: VkDeviceSize;
    FMinUniformBufferAlignment: VkDeviceSize;
    FMinStorageBufferAlignment: VkDeviceSize;
    FNonCoherentAtomSize: VkDeviceSize;
    FOptimalBufferCopyOffsetAlignment: VkDeviceSize;
    FOptimalBufferCopyRowPitchAlignment: VkDeviceSize;
    FMaxMemoryAllocationCount: Cardinal;
    FLock: TCriticalSection;

    { Separate block lists per (memoryTypeIndex, IsLinearResource) }
    FPools: array[0 .. VK_MAX_MEMORY_TYPES - 1, Boolean] of TCastleVulkanBlockList;

    { Per-frame transient ring buffers (1 per frame-in-flight) }
    FFrameRingBuffers: array[0 .. MaxFramesInFlight - 1] of TCastleVulkanFrameRingBuffer;

    FDedicatedCount: Cardinal;
    FDedicatedBytes: UInt64;
    FTotalVkAllocationCount: Cardinal;
    FSubAllocationCount: Cardinal;
    FSupportsMemoryBudgetExt: Boolean;

    function SelectMemoryType(const ATypeBits: UInt32;
      const AUsage: TRHIMemoryUsage; out AIsHostVisible, AIsHostCoherent: Boolean): Cardinal;
    function GetPreferredBlockSize(const AUsage: TRHIMemoryUsage): VkDeviceSize;
    function CanAllocateDedicated(const ARequiresDedicated: Boolean): Boolean;
    function AllocateInternal(const AMemReq: VkMemoryRequirements;
      const AUsage: TRHIMemoryUsage; const AIsLinearResource: Boolean;
      const APrefersDedicated, ARequiresDedicated: Boolean;
      const ADedicatedBuffer: VkBuffer; const ADedicatedImage: VkImage): TVulkanMemoryAllocation;
  public
    constructor Create(const APhysicalDevice: VkPhysicalDevice; const ADevice: VkDevice;
      const AMaxMemoryAllocationCount: Cardinal = 4096);
    destructor Destroy; override;

    { Sub-allocates memory matching VkMemoryRequirements and TRHIMemoryUsage. }
    function Allocate(const AMemReq: VkMemoryRequirements;
      const AUsage: TRHIMemoryUsage;
      const AIsLinearResource: Boolean = True;
      const APrefersDedicated: Boolean = False;
      const ARequiresDedicated: Boolean = False): TVulkanMemoryAllocation;

    { Queries vkGetBufferMemoryRequirements2 (with VkMemoryDedicatedRequirements)
      and sub-allocates (or dedicated-allocates) memory for ABuffer, enforcing
      at least AMinAlignment (e.g. minUniformBufferOffsetAlignment / minStorageBufferOffsetAlignment). }
    function AllocateBufferMemory(const ABuffer: VkBuffer;
      const ASize: VkDeviceSize; const AUsage: TRHIMemoryUsage;
      const AForceDedicated: Boolean = False;
      const AMinAlignment: VkDeviceSize = 0): TVulkanMemoryAllocation;

    { Queries vkGetImageMemoryRequirements2 (with VkMemoryDedicatedRequirements)
      and sub-allocates (or dedicated-allocates) memory for AImage. }
    function AllocateImageMemory(const AImage: VkImage;
      const AApproxSize: VkDeviceSize; const AUsage: TRHIMemoryUsage;
      const AIsOptimalTiling: Boolean = True;
      const AForceDedicated: Boolean = False): TVulkanMemoryAllocation;

    { Frees a sub-allocation or dedicated allocation. }
    procedure Free(var AAlloc: TVulkanMemoryAllocation);

    { Flushes CPU writes for non-coherent host-visible allocations aligned to
      VkPhysicalDeviceLimits.nonCoherentAtomSize (no-op if IsHostCoherent = True). }
    procedure FlushAllocation(const AAlloc: TVulkanMemoryAllocation;
      const AOffset: VkDeviceSize = 0; const ASize: VkDeviceSize = VK_WHOLE_SIZE);

    { Invalidates CPU cache lines for non-coherent host-visible readback allocations
      aligned to VkPhysicalDeviceLimits.nonCoherentAtomSize (no-op if IsHostCoherent = True). }
    procedure InvalidateAllocation(const AAlloc: TVulkanMemoryAllocation;
      const AOffset: VkDeviceSize = 0; const ASize: VkDeviceSize = VK_WHOLE_SIZE);

    { Returns the transient ring buffer for the given frame-in-flight index. }
    function GetFrameRingBuffer(const AFrameIndex: Cardinal): TCastleVulkanFrameRingBuffer;

    { Releases completely empty blocks back to the Vulkan driver. }
    procedure TrimEmptyBlocks;

    { Retrieves live memory budget and utilization statistics. }
    function GetStats: TVulkanMemoryStats;

    property Device: VkDevice read FDevice;
    property BufferImageGranularity: VkDeviceSize read FBufferImageGranularity write FBufferImageGranularity;
    property MinUniformBufferAlignment: VkDeviceSize read FMinUniformBufferAlignment write FMinUniformBufferAlignment;
    property MinStorageBufferAlignment: VkDeviceSize read FMinStorageBufferAlignment write FMinStorageBufferAlignment;
    property NonCoherentAtomSize: VkDeviceSize read FNonCoherentAtomSize write FNonCoherentAtomSize;
    property OptimalBufferCopyOffsetAlignment: VkDeviceSize read FOptimalBufferCopyOffsetAlignment write FOptimalBufferCopyOffsetAlignment;
    property OptimalBufferCopyRowPitchAlignment: VkDeviceSize read FOptimalBufferCopyRowPitchAlignment write FOptimalBufferCopyRowPitchAlignment;
    property MaxMemoryAllocationCount: Cardinal read FMaxMemoryAllocationCount write FMaxMemoryAllocationCount;
    property TotalVkAllocationCount: Cardinal read FTotalVkAllocationCount;
    property SubAllocationCount: Cardinal read FSubAllocationCount;
    property SupportsMemoryBudgetExt: Boolean read FSupportsMemoryBudgetExt write FSupportsMemoryBudgetExt;
  end;

{ Rounds AOffset down and ASize up to multiples of ANonCoherentAtomSize within
  [0 .. ABlockSize], satisfying VUID-VkMappedMemoryRange-offset-00687 and
  VUID-VkMappedMemoryRange-size-01390 across all GPU vendors. }
procedure AlignNonCoherentMemoryRange(
  const ASubAllocOffset, ASubAllocSize, ARangeOffset, ARangeSize,
  ABlockSize, ANonCoherentAtomSize: VkDeviceSize;
  out AAlignedOffset, AAlignedSize: VkDeviceSize);

{ Aggregates GPU VRAM usage and budget across DEVICE_LOCAL memory heaps.
  When AHasBudgetExt is True, sums heapUsage and heapBudget from VK_EXT_memory_budget;
  otherwise falls back to AFallbackUsedBytes and total heap sizes from AMemProps. }
procedure AggregateDeviceLocalMemoryBudget(
  const AMemProps: VkPhysicalDeviceMemoryProperties;
  const ABudgetProps: VkPhysicalDeviceMemoryBudgetPropertiesEXT;
  const AHasBudgetExt: Boolean;
  const AFallbackUsedBytes: UInt64;
  out AUsedBytes, ABudgetBytes: UInt64;
  out AUsedMB, ABudgetMB: Cardinal);

{ Queries live GPU VRAM usage and budget from APhysicalDevice using
  vkGetPhysicalDeviceMemoryProperties2 + VK_EXT_memory_budget when available,
  or falls back to vkGetPhysicalDeviceMemoryProperties heap sizes.
  Returns True if VK_EXT_memory_budget was used for the query. }
function QueryPhysicalDeviceMemoryBudget(
  const APhysicalDevice: VkPhysicalDevice;
  const ASupportsMemoryBudgetExt: Boolean;
  const AFallbackUsedBytes: UInt64;
  out AUsedBytes, ABudgetBytes: UInt64;
  out AUsedMB, ABudgetMB: Cardinal): Boolean;

implementation

const
  { Default pool block sizes }
  GPU_ONLY_BLOCK_SIZE     = 64 * 1024 * 1024; // 64 MB per block for static VRAM
  HOST_VISIBLE_BLOCK_SIZE = 16 * 1024 * 1024; // 16 MB per block for CPU-visible RAM
  MIN_FALLBACK_BLOCK_SIZE =  4 * 1024 * 1024; // 4 MB minimum fallback block size
  FRAME_RING_BUFFER_SIZE  =  4 * 1024 * 1024; // 4 MB per frame-in-flight ring buffer
  { Windows WDDM kernel limit is 4096 total VkDeviceMemory allocations;
    keep a 64-allocation safety margin for swapchain/driver internal allocations }
  WINDOWS_DEFAULT_MAX_MEMORY_ALLOCATIONS = 4096;
  ALLOCATION_LIMIT_SAFETY_MARGIN         = 64;

var
  GNextSimulatedDeviceMemoryHandle: UInt64 = $50000000;

function AlignUp(const Value, Alignment: VkDeviceSize): VkDeviceSize; inline;
begin
  if Alignment <= 1 then
    Result := Value
  else
    Result := (Value + (Alignment - 1)) and not (Alignment - 1);
end;

{ ---------------------------------------------------------------------------- }
{ TVulkanMemoryAllocation                                                      }
{ ---------------------------------------------------------------------------- }

function TVulkanMemoryAllocation.IsValid: Boolean;
begin
  Result := DeviceMemory <> VK_NULL_HANDLE;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanMemoryBlock                                                     }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanMemoryBlock.Create(const ADevice: VkDevice;
  const AMemoryTypeIndex: Cardinal; const ABlockSize: VkDeviceSize;
  const AHostVisible: Boolean; const AIsLinearPool: Boolean;
  const AIsHostCoherent: Boolean);
var
  AllocInfo: VkMemoryAllocateInfo;
  Res: VkResult;
begin
  inherited Create;
  FDevice := ADevice;
  FMemoryTypeIndex := AMemoryTypeIndex;
  FIsLinearPool := AIsLinearPool;
  FIsHostCoherent := AIsHostCoherent;
  FSize := ABlockSize;
  FUsedBytes := 0;
  FNextChunkId := 1;
  FActiveSubAllocations := 0;

  if (FDevice <> nil) and Assigned(vkAllocateMemory) then
  begin
    FSimulatedMemory := False;
    FillChar(AllocInfo, SizeOf(AllocInfo), 0);
    AllocInfo.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    AllocInfo.allocationSize := ABlockSize;
    AllocInfo.memoryTypeIndex := AMemoryTypeIndex;

    Res := vkAllocateMemory(FDevice, @AllocInfo, nil, @FDeviceMemory);
    if Res <> VK_SUCCESS then
      raise ERHIOutOfMemory.CreateFmt(
        'Vulkan out of device memory allocating %d MB block (VkResult: %d)',
        [ABlockSize div (1024 * 1024), Ord(Res)]);

    { Persistently map host-visible blocks once for the entire lifetime of the block }
    if AHostVisible and Assigned(vkMapMemory) then
    begin
      Res := vkMapMemory(FDevice, FDeviceMemory, 0, ABlockSize, 0, @FBaseMappedPtr);
      if Res <> VK_SUCCESS then
      begin
        if Assigned(vkFreeMemory) then
          vkFreeMemory(FDevice, FDeviceMemory, nil);
        raise ERHIOutOfMemory.CreateFmt('vkMapMemory failed for block (VkResult: %d)', [Ord(Res)]);
      end;
    end;
  end else
  begin
    { Headless / unit-test simulation mode }
    FSimulatedMemory := True;
    Inc(GNextSimulatedDeviceMemoryHandle);
    FDeviceMemory := VkDeviceMemory(GNextSimulatedDeviceMemoryHandle);
    if AHostVisible then
      GetMem(FBaseMappedPtr, PtrUInt(ABlockSize));
  end;

  { Initialize linked list with a single free node spanning the entire block }
  New(FHead);
  FHead^.ChunkId := 0;
  FHead^.Offset := 0;
  FHead^.Size := ABlockSize;
  FHead^.IsFree := True;
  FHead^.IsBufferImageGranularityTainted := False;
  FHead^.Prev := nil;
  FHead^.Next := nil;
end;

destructor TCastleVulkanMemoryBlock.Destroy;
var
  Curr, NextNode: PVulkanSubAllocationNode;
begin
  Curr := FHead;
  while Curr <> nil do
  begin
    NextNode := Curr^.Next;
    Dispose(Curr);
    Curr := NextNode;
  end;

  if FSimulatedMemory then
  begin
    if FBaseMappedPtr <> nil then
      FreeMem(FBaseMappedPtr);
  end else
  begin
    if (FBaseMappedPtr <> nil) and (FDevice <> nil) and Assigned(vkUnmapMemory) then
      vkUnmapMemory(FDevice, FDeviceMemory);
    if (FDeviceMemory <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkFreeMemory) then
      vkFreeMemory(FDevice, FDeviceMemory, nil);
  end;

  inherited;
end;

function TCastleVulkanMemoryBlock.IsEmpty: Boolean;
begin
  Result := (FHead <> nil) and FHead^.IsFree and (FHead^.Next = nil);
end;

function TCastleVulkanMemoryBlock.TrySubAllocate(
  const ASize, AAlignment, AGranularity: VkDeviceSize;
  const AIsLinearResource: Boolean; out AAlloc: TVulkanMemoryAllocation): Boolean;
var
  Curr, SplitStartNode, SplitEndNode: PVulkanSubAllocationNode;
  AlignedOffset, PaddingFront, PaddingBack, EffectiveAlignment: VkDeviceSize;
begin
  Result := False;
  if FSize - FUsedBytes < ASize then Exit;

  { Enforce bufferImageGranularity when linear buffers and optimal tiled images share a block }
  EffectiveAlignment := AAlignment;
  if EffectiveAlignment = 0 then
    EffectiveAlignment := 1;
  if (not AIsLinearResource) and (AGranularity > EffectiveAlignment) then
    EffectiveAlignment := AGranularity;

  Curr := FHead;
  while Curr <> nil do
  begin
    if Curr^.IsFree and (Curr^.Size >= ASize) then
    begin
      AlignedOffset := AlignUp(Curr^.Offset, EffectiveAlignment);

      { Also align up to granularity if the previous neighbor had a different linearity }
      if (Curr^.Prev <> nil) and (AGranularity > 1) and
         (Curr^.Prev^.IsBufferImageGranularityTainted <> (not AIsLinearResource)) then
        AlignedOffset := AlignUp(AlignedOffset, AGranularity);

      PaddingFront := AlignedOffset - Curr^.Offset;

      if Curr^.Size >= PaddingFront + ASize then
      begin
        PaddingBack := Curr^.Size - (PaddingFront + ASize);

        { 1. If there is alignment padding at the front, split off a small free node before Curr }
        if PaddingFront > 0 then
        begin
          New(SplitStartNode);
          SplitStartNode^.ChunkId := 0;
          SplitStartNode^.Offset := Curr^.Offset;
          SplitStartNode^.Size := PaddingFront;
          SplitStartNode^.IsFree := True;
          SplitStartNode^.IsBufferImageGranularityTainted := False;
          SplitStartNode^.Prev := Curr^.Prev;
          SplitStartNode^.Next := Curr;

          if Curr^.Prev <> nil then
            Curr^.Prev^.Next := SplitStartNode
          else
            FHead := SplitStartNode;

          Curr^.Prev := SplitStartNode;
          Curr^.Offset := AlignedOffset;
          Curr^.Size := Curr^.Size - PaddingFront;
        end;

        { 2. If there is remaining space at the back, split off a trailing free node }
        if PaddingBack > 0 then
        begin
          New(SplitEndNode);
          SplitEndNode^.ChunkId := 0;
          SplitEndNode^.Offset := AlignedOffset + ASize;
          SplitEndNode^.Size := PaddingBack;
          SplitEndNode^.IsFree := True;
          SplitEndNode^.IsBufferImageGranularityTainted := False;
          SplitEndNode^.Prev := Curr;
          SplitEndNode^.Next := Curr^.Next;

          if Curr^.Next <> nil then
            Curr^.Next^.Prev := SplitEndNode;
          Curr^.Next := SplitEndNode;
          Curr^.Size := ASize;
        end;

        { 3. Mark Curr as allocated }
        Curr^.IsFree := False;
        Curr^.IsBufferImageGranularityTainted := not AIsLinearResource;
        Curr^.ChunkId := FNextChunkId;
        Inc(FNextChunkId);

        Inc(FUsedBytes, ASize);
        Inc(FActiveSubAllocations);

        FillChar(AAlloc, SizeOf(AAlloc), 0);
        AAlloc.DeviceMemory := FDeviceMemory;
        AAlloc.Offset := Curr^.Offset;
        AAlloc.Size := Curr^.Size;
        AAlloc.Block := Self;
        AAlloc.Node := Curr;
        AAlloc.ChunkId := Curr^.ChunkId;
        AAlloc.IsDedicated := False;
        AAlloc.IsHostCoherent := FIsHostCoherent;
        if FBaseMappedPtr <> nil then
          AAlloc.MappedPtr := FBaseMappedPtr + Curr^.Offset;

        Exit(True);
      end;
    end;
    Curr := Curr^.Next;
  end;
end;

procedure TCastleVulkanMemoryBlock.FreeSubAllocation(const AAlloc: TVulkanMemoryAllocation);
var
  Curr, Neighbor: PVulkanSubAllocationNode;
begin
  { Fast O(1) path via direct node pointer }
  if (AAlloc.Node <> nil) and (not AAlloc.Node^.IsFree) and
     (AAlloc.Node^.ChunkId = AAlloc.ChunkId) and (AAlloc.Node^.Offset = AAlloc.Offset) then
    Curr := AAlloc.Node
  else
  begin
    { Fallback linear scan if Node was not populated }
    Curr := FHead;
    while Curr <> nil do
    begin
      if (not Curr^.IsFree) and (Curr^.ChunkId = AAlloc.ChunkId) and (Curr^.Offset = AAlloc.Offset) then
        Break;
      Curr := Curr^.Next;
    end;
  end;

  if Curr <> nil then
  begin
    Curr^.IsFree := True;
    Curr^.ChunkId := 0;
    Dec(FUsedBytes, Curr^.Size);
    if FActiveSubAllocations > 0 then
      Dec(FActiveSubAllocations);

    { Coalesce with next node if free }
    Neighbor := Curr^.Next;
    if (Neighbor <> nil) and Neighbor^.IsFree then
    begin
      Curr^.Size := Curr^.Size + Neighbor^.Size;
      Curr^.Next := Neighbor^.Next;
      if Curr^.Next <> nil then
        Curr^.Next^.Prev := Curr;
      Dispose(Neighbor);
    end;

    { Coalesce with previous node if free }
    Neighbor := Curr^.Prev;
    if (Neighbor <> nil) and Neighbor^.IsFree then
    begin
      Neighbor^.Size := Neighbor^.Size + Curr^.Size;
      Neighbor^.Next := Curr^.Next;
      if Neighbor^.Next <> nil then
        Neighbor^.Next^.Prev := Neighbor;
      Dispose(Curr);
    end;

    Exit;
  end;

  WritelnWarning('VulkanMemory', 'Attempted to free unknown sub-allocation chunk %d at offset %d',
    [AAlloc.ChunkId, AAlloc.Offset]);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanFrameRingBuffer                                                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanFrameRingBuffer.Create(
  const AAllocator: TCastleVulkanMemoryAllocator;
  const ACapacity, AMinAlignment: VkDeviceSize);
var
  BufInfo: VkBufferCreateInfo;
  MemReq: VkMemoryRequirements;
begin
  inherited Create;
  FAllocator := AAllocator;
  FDevice := AAllocator.Device;
  FCapacity := ACapacity;
  FMinAlignment := AMinAlignment;
  FCurrentOffset := 0;

  if (FDevice <> nil) and Assigned(vkCreateBuffer) then
  begin
    FillChar(BufInfo, SizeOf(BufInfo), 0);
    BufInfo.sType := VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    BufInfo.size := ACapacity;
    BufInfo.usage :=
      VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT or
      VK_BUFFER_USAGE_VERTEX_BUFFER_BIT or
      VK_BUFFER_USAGE_INDEX_BUFFER_BIT or
      VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    BufInfo.sharingMode := VK_SHARING_MODE_EXCLUSIVE;

    if vkCreateBuffer(FDevice, @BufInfo, nil, @FBuffer) <> VK_SUCCESS then
      raise ERHIOutOfMemory.Create('Failed to create Vulkan per-frame ring buffer');

    vkGetBufferMemoryRequirements(FDevice, FBuffer, @MemReq);
    FAllocation := FAllocator.Allocate(MemReq, muCpuToGpu, True);
    vkBindBufferMemory(FDevice, FBuffer, FAllocation.DeviceMemory, FAllocation.Offset);
  end else
  begin
    { Headless / simulated ring buffer }
    FBuffer := VkBuffer(PtrUInt(Self));
    FillChar(MemReq, SizeOf(MemReq), 0);
    MemReq.size := ACapacity;
    MemReq.alignment := 256;
    MemReq.memoryTypeBits := $FFFFFFFF;
    FAllocation := FAllocator.Allocate(MemReq, muCpuToGpu, True);
  end;
end;

destructor TCastleVulkanFrameRingBuffer.Destroy;
begin
  if (FBuffer <> VK_NULL_HANDLE) and (FDevice <> nil) and Assigned(vkDestroyBuffer) then
    vkDestroyBuffer(FDevice, FBuffer, nil);
  if FAllocation.IsValid then
    FAllocator.Free(FAllocation);
  inherited;
end;

procedure TCastleVulkanFrameRingBuffer.Reset;
begin
  FCurrentOffset := 0;
end;

function TCastleVulkanFrameRingBuffer.Allocate(
  const ASize, AAlignment: VkDeviceSize): TVulkanTransientAllocation;
var
  EffAlign, AlignedOffset: VkDeviceSize;
begin
  EffAlign := AAlignment;
  if FMinAlignment > EffAlign then
    EffAlign := FMinAlignment;

  AlignedOffset := AlignUp(FCurrentOffset, EffAlign);
  if AlignedOffset + ASize > FCapacity then
    raise ERHIOutOfMemory.CreateFmt(
      'Vulkan per-frame ring buffer exhausted (%d / %d bytes requested). Increase FRAME_RING_BUFFER_SIZE.',
      [AlignedOffset + ASize, FCapacity]);

  Result.Buffer := FBuffer;
  Result.Offset := AlignedOffset;
  Result.Size := ASize;
  if FAllocation.MappedPtr <> nil then
    Result.MappedPtr := PByte(FAllocation.MappedPtr) + AlignedOffset
  else
    Result.MappedPtr := nil;

  FCurrentOffset := AlignedOffset + ASize;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanMemoryAllocator                                                 }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanMemoryAllocator.Create(
  const APhysicalDevice: VkPhysicalDevice; const ADevice: VkDevice;
  const AMaxMemoryAllocationCount: Cardinal);
var
  DevProps: VkPhysicalDeviceProperties;
  I: Integer;
  IsLinear: Boolean;
begin
  inherited Create;
  FPhysicalDevice := APhysicalDevice;
  FDevice := ADevice;
  FLock := TCriticalSection.Create;
  FMaxMemoryAllocationCount := AMaxMemoryAllocationCount;
  if FMaxMemoryAllocationCount = 0 then
    FMaxMemoryAllocationCount := WINDOWS_DEFAULT_MAX_MEMORY_ALLOCATIONS;

  if (FPhysicalDevice <> nil) and Assigned(vkGetPhysicalDeviceMemoryProperties) and
     Assigned(vkGetPhysicalDeviceProperties) then
  begin
    vkGetPhysicalDeviceMemoryProperties(FPhysicalDevice, @FMemProperties);
    vkGetPhysicalDeviceProperties(FPhysicalDevice, @DevProps);

    FBufferImageGranularity := DevProps.limits.bufferImageGranularity;
    FMinUniformBufferAlignment := DevProps.limits.minUniformBufferOffsetAlignment;
    FMinStorageBufferAlignment := DevProps.limits.minStorageBufferOffsetAlignment;
    FNonCoherentAtomSize := DevProps.limits.nonCoherentAtomSize;
    FOptimalBufferCopyOffsetAlignment := DevProps.limits.optimalBufferCopyOffsetAlignment;
    FOptimalBufferCopyRowPitchAlignment := DevProps.limits.optimalBufferCopyRowPitchAlignment;
    if DevProps.limits.maxMemoryAllocationCount > 0 then
      FMaxMemoryAllocationCount := DevProps.limits.maxMemoryAllocationCount;
  end else
  begin
    { Synthetic memory properties for headless / unit test mode }
    FillChar(FMemProperties, SizeOf(FMemProperties), 0);
    FMemProperties.memoryHeapCount := 2;
    FMemProperties.memoryHeaps[0].size := UInt64(4096) * 1024 * 1024;
    FMemProperties.memoryHeaps[0].flags := VK_MEMORY_HEAP_DEVICE_LOCAL_BIT;
    FMemProperties.memoryHeaps[1].size := UInt64(8192) * 1024 * 1024;
    FMemProperties.memoryHeaps[1].flags := 0;

    FMemProperties.memoryTypeCount := 3;
    { Type 0: DEVICE_LOCAL (VRAM) }
    FMemProperties.memoryTypes[0].heapIndex := 0;
    FMemProperties.memoryTypes[0].propertyFlags := VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    { Type 1: HOST_VISIBLE | HOST_COHERENT (Upload / Ring) }
    FMemProperties.memoryTypes[1].heapIndex := 1;
    FMemProperties.memoryTypes[1].propertyFlags :=
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    { Type 2: HOST_VISIBLE | HOST_CACHED (Readback, non-coherent) }
    FMemProperties.memoryTypes[2].heapIndex := 1;
    FMemProperties.memoryTypes[2].propertyFlags :=
      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_CACHED_BIT;

    FBufferImageGranularity := 1024;
    FMinUniformBufferAlignment := 256;
    FMinStorageBufferAlignment := 256;
    FNonCoherentAtomSize := 64;
    FOptimalBufferCopyOffsetAlignment := 16;
    FOptimalBufferCopyRowPitchAlignment := 64;
  end;

  if FMinUniformBufferAlignment = 0 then FMinUniformBufferAlignment := 256;
  if FMinStorageBufferAlignment = 0 then FMinStorageBufferAlignment := 256;
  if FNonCoherentAtomSize = 0 then FNonCoherentAtomSize := 64;
  if FOptimalBufferCopyOffsetAlignment = 0 then FOptimalBufferCopyOffsetAlignment := 16;
  if FOptimalBufferCopyRowPitchAlignment = 0 then FOptimalBufferCopyRowPitchAlignment := 64;

  for I := 0 to VK_MAX_MEMORY_TYPES - 1 do
    for IsLinear := Low(Boolean) to High(Boolean) do
      FPools[I, IsLinear] := TCastleVulkanBlockList.Create(True);

  for I := 0 to MaxFramesInFlight - 1 do
    FFrameRingBuffers[I] := TCastleVulkanFrameRingBuffer.Create(
      Self, FRAME_RING_BUFFER_SIZE, FMinUniformBufferAlignment);
end;

destructor TCastleVulkanMemoryAllocator.Destroy;
var
  I: Integer;
  IsLinear: Boolean;
begin
  for I := 0 to MaxFramesInFlight - 1 do
    FreeAndNil(FFrameRingBuffers[I]);

  for I := 0 to VK_MAX_MEMORY_TYPES - 1 do
    for IsLinear := Low(Boolean) to High(Boolean) do
      FreeAndNil(FPools[I, IsLinear]);

  FreeAndNil(FLock);
  inherited;
end;

function TCastleVulkanMemoryAllocator.SelectMemoryType(const ATypeBits: UInt32;
  const AUsage: TRHIMemoryUsage; out AIsHostVisible, AIsHostCoherent: Boolean): Cardinal;

  function TryFindWithFlags(const Required, Preferred: VkMemoryPropertyFlags;
    out FoundIdx: Cardinal): Boolean;
  var
    I: Cardinal;
    Flags: VkMemoryPropertyFlags;
    BestScore, Score: Integer;
  begin
    Result := False;
    BestScore := -1;
    FoundIdx := 0;

    for I := 0 to FMemProperties.memoryTypeCount - 1 do
      if (ATypeBits and (UInt32(1) shl I)) <> 0 then
      begin
        Flags := FMemProperties.memoryTypes[I].propertyFlags;
        if (Flags and Required) = Required then
        begin
          Score := 0;
          if (Flags and Preferred) = Preferred then
            Score := 10;
          if Score > BestScore then
          begin
            BestScore := Score;
            FoundIdx := I;
            Result := True;
          end;
        end;
      end;
  end;

var
  RequiredFlags, PreferredFlags, SelectedFlags: VkMemoryPropertyFlags;
begin
  case AUsage of
    muGpuOnly:
      begin
        RequiredFlags := VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
        PreferredFlags := VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
        AIsHostVisible := False;
      end;
    muCpuToGpu:
      begin
        RequiredFlags := VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        { Prefer Resizable BAR / ReBAR (DEVICE_LOCAL + HOST_VISIBLE) when available }
        PreferredFlags := RequiredFlags or VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
        AIsHostVisible := True;
      end;
    muGpuToCpu:
      begin
        RequiredFlags := VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
        PreferredFlags := VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
        AIsHostVisible := True;
      end;
  end;

  if not TryFindWithFlags(RequiredFlags, PreferredFlags, Result) then
    if not TryFindWithFlags(0, 0, Result) then
      raise ERHIOutOfMemory.Create('Could not find compatible Vulkan memory type');

  SelectedFlags := FMemProperties.memoryTypes[Result].propertyFlags;
  AIsHostVisible := (SelectedFlags and VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) <> 0;
  AIsHostCoherent := (SelectedFlags and VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) <> 0;
end;

function TCastleVulkanMemoryAllocator.GetPreferredBlockSize(
  const AUsage: TRHIMemoryUsage): VkDeviceSize;
begin
  if AUsage = muGpuOnly then
    Result := GPU_ONLY_BLOCK_SIZE
  else
    Result := HOST_VISIBLE_BLOCK_SIZE;
end;

function TCastleVulkanMemoryAllocator.CanAllocateDedicated(
  const ARequiresDedicated: Boolean): Boolean;
begin
  if ARequiresDedicated then
    Exit(FTotalVkAllocationCount < FMaxMemoryAllocationCount);
  { Preserve a safety margin below Windows' 4096 maxMemoryAllocationCount limit }
  Result := (FTotalVkAllocationCount + ALLOCATION_LIMIT_SAFETY_MARGIN) < FMaxMemoryAllocationCount;
end;

function TCastleVulkanMemoryAllocator.AllocateInternal(
  const AMemReq: VkMemoryRequirements; const AUsage: TRHIMemoryUsage;
  const AIsLinearResource: Boolean;
  const APrefersDedicated, ARequiresDedicated: Boolean;
  const ADedicatedBuffer: VkBuffer; const ADedicatedImage: VkImage): TVulkanMemoryAllocation;
var
  MemTypeIdx: Cardinal;
  IsHostVisible, IsHostCoherent, WantDedicated: Boolean;
  PrefBlockSize, NewBlockSize: VkDeviceSize;
  Pool: TCastleVulkanBlockList;
  Block, NewBlock: TCastleVulkanMemoryBlock;
  AllocInfo: VkMemoryAllocateInfo;
  DedicatedAllocInfo: VkMemoryDedicatedAllocateInfo;
  I: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  MemTypeIdx := SelectMemoryType(AMemReq.memoryTypeBits, AUsage, IsHostVisible, IsHostCoherent);
  PrefBlockSize := GetPreferredBlockSize(AUsage);

  FLock.Acquire;
  try
    WantDedicated := ARequiresDedicated or APrefersDedicated or
      (AMemReq.size >= (PrefBlockSize div 2));

    { 1. Dedicated Allocation Path (guarded by maxMemoryAllocationCount limit) }
    if WantDedicated and CanAllocateDedicated(ARequiresDedicated) then
    begin
      if (FDevice <> nil) and Assigned(vkAllocateMemory) then
      begin
        FillChar(AllocInfo, SizeOf(AllocInfo), 0);
        AllocInfo.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        AllocInfo.allocationSize := AMemReq.size;
        AllocInfo.memoryTypeIndex := MemTypeIdx;

        if (ADedicatedBuffer <> VK_NULL_HANDLE) or (ADedicatedImage <> VK_NULL_HANDLE) then
        begin
          FillChar(DedicatedAllocInfo, SizeOf(DedicatedAllocInfo), 0);
          DedicatedAllocInfo.sType := VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO;
          DedicatedAllocInfo.buffer := ADedicatedBuffer;
          DedicatedAllocInfo.image := ADedicatedImage;
          AllocInfo.pNext := @DedicatedAllocInfo;
        end;

        if vkAllocateMemory(FDevice, @AllocInfo, nil, @Result.DeviceMemory) <> VK_SUCCESS then
          raise ERHIOutOfMemory.CreateFmt('Failed dedicated Vulkan allocation of %d bytes', [AMemReq.size]);

        if IsHostVisible and Assigned(vkMapMemory) then
          vkMapMemory(FDevice, Result.DeviceMemory, 0, AMemReq.size, 0, @Result.MappedPtr);
      end else
      begin
        Inc(GNextSimulatedDeviceMemoryHandle);
        Result.DeviceMemory := VkDeviceMemory(GNextSimulatedDeviceMemoryHandle);
        if IsHostVisible then
        begin
          GetMem(Result.MappedPtr, PtrUInt(AMemReq.size));
          Result.IsSimulatedHostMemory := True;
        end;
      end;

      Result.Offset := 0;
      Result.Size := AMemReq.size;
      Result.IsDedicated := True;
      Result.IsHostCoherent := IsHostCoherent;

      Inc(FDedicatedCount);
      Inc(FDedicatedBytes, AMemReq.size);
      Inc(FTotalVkAllocationCount);
      Exit;
    end;

    { 2. Pooled Sub-Allocation Path: Separate Linear vs Non-Linear pools per memoryTypeIndex }
    Pool := FPools[MemTypeIdx, AIsLinearResource];
    for I := 0 to Pool.Count - 1 do
    begin
      Block := Pool[I];
      if Block.TrySubAllocate(AMemReq.size, AMemReq.alignment,
           1 { Granularity=1 since Linear and NonLinear are in separate blocks },
           AIsLinearResource, Result) then
      begin
        Inc(FSubAllocationCount);
        Exit;
      end;
    end;

    { 3. Allocate a new pooled block (scaling up if AMemReq.size > PrefBlockSize when near 4096 limit) }
    if FTotalVkAllocationCount >= FMaxMemoryAllocationCount then
      raise ERHIOutOfMemory.CreateFmt(
        'Vulkan maxMemoryAllocationCount limit (%d) reached; cannot allocate new memory block.',
        [FMaxMemoryAllocationCount]);

    NewBlockSize := PrefBlockSize;
    if AMemReq.size > NewBlockSize then
      NewBlockSize := AlignUp(AMemReq.size, 4 * 1024 * 1024);

    NewBlock := nil;
    while NewBlock = nil do
    begin
      try
        NewBlock := TCastleVulkanMemoryBlock.Create(
          FDevice, MemTypeIdx, NewBlockSize, IsHostVisible, AIsLinearResource, IsHostCoherent);
      except
        on E: ERHIOutOfMemory do
        begin
          { Fallback to halved block size if VRAM is fragmented }
          NewBlockSize := NewBlockSize div 2;
          if (NewBlockSize < AMemReq.size) or (NewBlockSize < MIN_FALLBACK_BLOCK_SIZE) then
            raise;
        end;
      end;
    end;

    Pool.Add(NewBlock);
    Inc(FTotalVkAllocationCount);

    if not NewBlock.TrySubAllocate(AMemReq.size, AMemReq.alignment,
         1, AIsLinearResource, Result) then
      raise ERHIOutOfMemory.Create('Sub-allocation failed on freshly created memory block');
    Inc(FSubAllocationCount);
  finally
    FLock.Release;
  end;
end;

function TCastleVulkanMemoryAllocator.Allocate(
  const AMemReq: VkMemoryRequirements; const AUsage: TRHIMemoryUsage;
  const AIsLinearResource: Boolean;
  const APrefersDedicated, ARequiresDedicated: Boolean): TVulkanMemoryAllocation;
begin
  Result := AllocateInternal(AMemReq, AUsage, AIsLinearResource,
    APrefersDedicated, ARequiresDedicated, VK_NULL_HANDLE, VK_NULL_HANDLE);
end;

function TCastleVulkanMemoryAllocator.AllocateBufferMemory(const ABuffer: VkBuffer;
  const ASize: VkDeviceSize; const AUsage: TRHIMemoryUsage;
  const AForceDedicated: Boolean; const AMinAlignment: VkDeviceSize): TVulkanMemoryAllocation;
var
  Info2: VkBufferMemoryRequirementsInfo2;
  Req2: VkMemoryRequirements2;
  DedReq: VkMemoryDedicatedRequirements;
  MemReq: VkMemoryRequirements;
  PrefersDed, RequiresDed: Boolean;
begin
  PrefersDed := AForceDedicated;
  RequiresDed := AForceDedicated;

  if (FDevice <> nil) and (ABuffer <> VK_NULL_HANDLE) and
     Assigned(vkGetBufferMemoryRequirements2) then
  begin
    FillChar(Info2, SizeOf(Info2), 0);
    Info2.sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2;
    Info2.buffer := ABuffer;

    FillChar(DedReq, SizeOf(DedReq), 0);
    DedReq.sType := VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS;

    FillChar(Req2, SizeOf(Req2), 0);
    Req2.sType := VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
    Req2.pNext := @DedReq;

    vkGetBufferMemoryRequirements2(FDevice, @Info2, @Req2);
    MemReq := Req2.memoryRequirements;
    PrefersDed := PrefersDed or (DedReq.prefersDedicatedAllocation <> VK_FALSE);
    RequiresDed := RequiresDed or (DedReq.requiresDedicatedAllocation <> VK_FALSE);
  end else
  if (FDevice <> nil) and (ABuffer <> VK_NULL_HANDLE) and
     Assigned(vkGetBufferMemoryRequirements) then
  begin
    FillChar(MemReq, SizeOf(MemReq), 0);
    vkGetBufferMemoryRequirements(FDevice, ABuffer, @MemReq);
  end else
  begin
    FillChar(MemReq, SizeOf(MemReq), 0);
    if ASize > 0 then
      MemReq.size := ASize
    else
      MemReq.size := 256;
    MemReq.alignment := 256;
    MemReq.memoryTypeBits := $FFFFFFFF;
  end;

  { Enforce hardware offset alignment (e.g. minUniformBufferOffsetAlignment,
    minStorageBufferOffsetAlignment, optimalBufferCopyOffsetAlignment) }
  if AMinAlignment > MemReq.alignment then
    MemReq.alignment := AMinAlignment;
  if (AUsage = muGpuToCpu) and (FNonCoherentAtomSize > MemReq.alignment) then
    MemReq.alignment := FNonCoherentAtomSize;

  Result := AllocateInternal(MemReq, AUsage, True { Linear },
    PrefersDed, RequiresDed, ABuffer, VK_NULL_HANDLE);
end;

function TCastleVulkanMemoryAllocator.AllocateImageMemory(const AImage: VkImage;
  const AApproxSize: VkDeviceSize; const AUsage: TRHIMemoryUsage;
  const AIsOptimalTiling: Boolean; const AForceDedicated: Boolean): TVulkanMemoryAllocation;
var
  Info2: VkImageMemoryRequirementsInfo2;
  Req2: VkMemoryRequirements2;
  DedReq: VkMemoryDedicatedRequirements;
  MemReq: VkMemoryRequirements;
  PrefersDed, RequiresDed: Boolean;
begin
  PrefersDed := AForceDedicated;
  RequiresDed := AForceDedicated;

  if (FDevice <> nil) and (AImage <> VK_NULL_HANDLE) and
     Assigned(vkGetImageMemoryRequirements2) then
  begin
    FillChar(Info2, SizeOf(Info2), 0);
    Info2.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2;
    Info2.image := AImage;

    FillChar(DedReq, SizeOf(DedReq), 0);
    DedReq.sType := VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS;

    FillChar(Req2, SizeOf(Req2), 0);
    Req2.sType := VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2;
    Req2.pNext := @DedReq;

    vkGetImageMemoryRequirements2(FDevice, @Info2, @Req2);
    MemReq := Req2.memoryRequirements;
    PrefersDed := PrefersDed or (DedReq.prefersDedicatedAllocation <> VK_FALSE);
    RequiresDed := RequiresDed or (DedReq.requiresDedicatedAllocation <> VK_FALSE);
  end else
  if (FDevice <> nil) and (AImage <> VK_NULL_HANDLE) and
     Assigned(vkGetImageMemoryRequirements) then
  begin
    FillChar(MemReq, SizeOf(MemReq), 0);
    vkGetImageMemoryRequirements(FDevice, AImage, @MemReq);
  end else
  begin
    FillChar(MemReq, SizeOf(MemReq), 0);
    if AApproxSize > 0 then
      MemReq.size := AApproxSize
    else
      MemReq.size := 4096;
    MemReq.alignment := 1024;
    MemReq.memoryTypeBits := $FFFFFFFF;
  end;

  Result := AllocateInternal(MemReq, AUsage, not AIsOptimalTiling,
    PrefersDed, RequiresDed, VK_NULL_HANDLE, AImage);
end;

procedure TCastleVulkanMemoryAllocator.Free(var AAlloc: TVulkanMemoryAllocation);
begin
  if not AAlloc.IsValid then Exit;

  FLock.Acquire;
  try
    if AAlloc.IsDedicated then
    begin
      if AAlloc.IsSimulatedHostMemory then
      begin
        if AAlloc.MappedPtr <> nil then
          FreeMem(AAlloc.MappedPtr);
      end else
      if FDevice <> nil then
      begin
        if (AAlloc.MappedPtr <> nil) and Assigned(vkUnmapMemory) then
          vkUnmapMemory(FDevice, AAlloc.DeviceMemory);
        if Assigned(vkFreeMemory) then
          vkFreeMemory(FDevice, AAlloc.DeviceMemory, nil);
      end;
      if FDedicatedCount > 0 then
        Dec(FDedicatedCount);
      Dec(FDedicatedBytes, AAlloc.Size);
      if FTotalVkAllocationCount > 0 then
        Dec(FTotalVkAllocationCount);
    end else
    if AAlloc.Block <> nil then
    begin
      AAlloc.Block.FreeSubAllocation(AAlloc);
      if FSubAllocationCount > 0 then
        Dec(FSubAllocationCount);
    end;

    FillChar(AAlloc, SizeOf(AAlloc), 0);
  finally
    FLock.Release;
  end;
end;

procedure AlignNonCoherentMemoryRange(
  const ASubAllocOffset, ASubAllocSize, ARangeOffset, ARangeSize,
  ABlockSize, ANonCoherentAtomSize: VkDeviceSize;
  out AAlignedOffset, AAlignedSize: VkDeviceSize);
var
  Atom, RawStart, RawEnd, AlignedEnd, EffectiveSize: VkDeviceSize;
begin
  Atom := ANonCoherentAtomSize;
  if Atom <= 1 then
  begin
    AAlignedOffset := ASubAllocOffset + ARangeOffset;
    if (ARangeSize = VK_WHOLE_SIZE) or (ARangeOffset + ARangeSize > ASubAllocSize) then
      AAlignedSize := ASubAllocSize - ARangeOffset
    else
      AAlignedSize := ARangeSize;
    Exit;
  end;

  RawStart := ASubAllocOffset + ARangeOffset;
  if (ARangeSize = VK_WHOLE_SIZE) or (ARangeOffset + ARangeSize > ASubAllocSize) then
    EffectiveSize := ASubAllocSize - ARangeOffset
  else
    EffectiveSize := ARangeSize;
  RawEnd := RawStart + EffectiveSize;

  { VUID-VkMappedMemoryRange-offset-00687: offset must be a multiple of nonCoherentAtomSize }
  AAlignedOffset := (RawStart div Atom) * Atom;

  { VUID-VkMappedMemoryRange-size-01390: size must either be a multiple of
    nonCoherentAtomSize, or offset + size must equal the underlying VkDeviceMemory size }
  AlignedEnd := ((RawEnd + Atom - 1) div Atom) * Atom;
  if (ABlockSize > 0) and (AlignedEnd > ABlockSize) then
    AlignedEnd := ABlockSize;

  AAlignedSize := AlignedEnd - AAlignedOffset;
end;

procedure TCastleVulkanMemoryAllocator.FlushAllocation(
  const AAlloc: TVulkanMemoryAllocation; const AOffset, ASize: VkDeviceSize);
var
  Range: VkMappedMemoryRange;
  BlockSize, AlignedOffset, AlignedSize: VkDeviceSize;
begin
  if (not AAlloc.IsValid) or AAlloc.IsHostCoherent then Exit;
  if (FDevice = nil) or (not Assigned(vkFlushMappedMemoryRanges)) then Exit;

  if AAlloc.Block <> nil then
    BlockSize := AAlloc.Block.Size
  else
    BlockSize := AAlloc.Size;

  AlignNonCoherentMemoryRange(AAlloc.Offset, AAlloc.Size, AOffset, ASize,
    BlockSize, FNonCoherentAtomSize, AlignedOffset, AlignedSize);

  FillChar(Range, SizeOf(Range), 0);
  Range.sType := VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
  Range.memory := AAlloc.DeviceMemory;
  Range.offset := AlignedOffset;
  Range.size := AlignedSize;
  vkFlushMappedMemoryRanges(FDevice, 1, @Range);
end;

procedure TCastleVulkanMemoryAllocator.InvalidateAllocation(
  const AAlloc: TVulkanMemoryAllocation; const AOffset, ASize: VkDeviceSize);
var
  Range: VkMappedMemoryRange;
  BlockSize, AlignedOffset, AlignedSize: VkDeviceSize;
begin
  if (not AAlloc.IsValid) or AAlloc.IsHostCoherent then Exit;
  if (FDevice = nil) or (not Assigned(vkInvalidateMappedMemoryRanges)) then Exit;

  if AAlloc.Block <> nil then
    BlockSize := AAlloc.Block.Size
  else
    BlockSize := AAlloc.Size;

  AlignNonCoherentMemoryRange(AAlloc.Offset, AAlloc.Size, AOffset, ASize,
    BlockSize, FNonCoherentAtomSize, AlignedOffset, AlignedSize);

  FillChar(Range, SizeOf(Range), 0);
  Range.sType := VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
  Range.memory := AAlloc.DeviceMemory;
  Range.offset := AlignedOffset;
  Range.size := AlignedSize;
  vkInvalidateMappedMemoryRanges(FDevice, 1, @Range);
end;

function TCastleVulkanMemoryAllocator.GetFrameRingBuffer(
  const AFrameIndex: Cardinal): TCastleVulkanFrameRingBuffer;
begin
  Result := FFrameRingBuffers[AFrameIndex mod MaxFramesInFlight];
end;

procedure TCastleVulkanMemoryAllocator.TrimEmptyBlocks;
var
  I, J: Integer;
  IsLinear: Boolean;
  Pool: TCastleVulkanBlockList;
begin
  FLock.Acquire;
  try
    for I := 0 to VK_MAX_MEMORY_TYPES - 1 do
      for IsLinear := Low(Boolean) to High(Boolean) do
      begin
        Pool := FPools[I, IsLinear];
        { Keep at least 1 block per active pool to avoid thrashing vkAllocateMemory }
        for J := Pool.Count - 1 downto 1 do
          if Pool[J].IsEmpty then
          begin
            Pool.Delete(J);
            if FTotalVkAllocationCount > 0 then
              Dec(FTotalVkAllocationCount);
          end;
      end;
  finally
    FLock.Release;
  end;
end;

procedure AggregateDeviceLocalMemoryBudget(
  const AMemProps: VkPhysicalDeviceMemoryProperties;
  const ABudgetProps: VkPhysicalDeviceMemoryBudgetPropertiesEXT;
  const AHasBudgetExt: Boolean;
  const AFallbackUsedBytes: UInt64;
  out AUsedBytes, ABudgetBytes: UInt64;
  out AUsedMB, ABudgetMB: Cardinal);
const
  BytesPerMB = UInt64(1024 * 1024);
var
  HeapCount, I: Cardinal;
  FoundDeviceLocal: Boolean;
begin
  AUsedBytes := 0;
  ABudgetBytes := 0;
  AUsedMB := 0;
  ABudgetMB := 0;

  HeapCount := AMemProps.memoryHeapCount;
  if HeapCount > VK_MAX_MEMORY_HEAPS then
    HeapCount := VK_MAX_MEMORY_HEAPS;

  FoundDeviceLocal := False;
  if HeapCount > 0 then
  begin
    for I := 0 to HeapCount - 1 do
      if (AMemProps.memoryHeaps[I].flags and VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) <> 0 then
      begin
        FoundDeviceLocal := True;
        if AHasBudgetExt and (ABudgetProps.heapBudget[I] > 0) then
        begin
          Inc(ABudgetBytes, ABudgetProps.heapBudget[I]);
          Inc(AUsedBytes, ABudgetProps.heapUsage[I]);
        end else
          Inc(ABudgetBytes, AMemProps.memoryHeaps[I].size);
      end;

    { Fallback if no heap explicitly set VK_MEMORY_HEAP_DEVICE_LOCAL_BIT }
    if not FoundDeviceLocal then
      for I := 0 to HeapCount - 1 do
      begin
        if AHasBudgetExt and (ABudgetProps.heapBudget[I] > 0) then
        begin
          Inc(ABudgetBytes, ABudgetProps.heapBudget[I]);
          Inc(AUsedBytes, ABudgetProps.heapUsage[I]);
        end else
          Inc(ABudgetBytes, AMemProps.memoryHeaps[I].size);
      end;
  end;

  if (not AHasBudgetExt) or ((AUsedBytes = 0) and (AFallbackUsedBytes > 0)) then
    AUsedBytes := AFallbackUsedBytes;

  AUsedMB := Cardinal(AUsedBytes div BytesPerMB);
  if (AUsedBytes > 0) and (AUsedMB = 0) then
    AUsedMB := 1;
  ABudgetMB := Cardinal(ABudgetBytes div BytesPerMB);
end;

function QueryPhysicalDeviceMemoryBudget(
  const APhysicalDevice: VkPhysicalDevice;
  const ASupportsMemoryBudgetExt: Boolean;
  const AFallbackUsedBytes: UInt64;
  out AUsedBytes, ABudgetBytes: UInt64;
  out AUsedMB, ABudgetMB: Cardinal): Boolean;
var
  MemProps2: VkPhysicalDeviceMemoryProperties2;
  BudgetProps: VkPhysicalDeviceMemoryBudgetPropertiesEXT;
  MemProps: VkPhysicalDeviceMemoryProperties;
begin
  Result := False;
  FillChar(BudgetProps, SizeOf(BudgetProps), 0);

  if (APhysicalDevice <> nil) and ASupportsMemoryBudgetExt and
     Assigned(vkGetPhysicalDeviceMemoryProperties2) then
  begin
    FillChar(MemProps2, SizeOf(MemProps2), 0);
    BudgetProps.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT;
    MemProps2.sType := VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2;
    MemProps2.pNext := @BudgetProps;
    vkGetPhysicalDeviceMemoryProperties2(APhysicalDevice, @MemProps2);

    AggregateDeviceLocalMemoryBudget(MemProps2.memoryProperties, BudgetProps,
      True, AFallbackUsedBytes, AUsedBytes, ABudgetBytes, AUsedMB, ABudgetMB);
    Exit(True);
  end;

  FillChar(MemProps, SizeOf(MemProps), 0);
  if (APhysicalDevice <> nil) and Assigned(vkGetPhysicalDeviceMemoryProperties) then
    vkGetPhysicalDeviceMemoryProperties(APhysicalDevice, @MemProps);

  AggregateDeviceLocalMemoryBudget(MemProps, BudgetProps,
    False, AFallbackUsedBytes, AUsedBytes, ABudgetBytes, AUsedMB, ABudgetMB);
end;

function TCastleVulkanMemoryAllocator.GetStats: TVulkanMemoryStats;
var
  I, J: Integer;
  IsLinear: Boolean;
  Pool: TCastleVulkanBlockList;
begin
  FillChar(Result, SizeOf(Result), 0);
  FLock.Acquire;
  try
    Result.DedicatedAllocationCount := FDedicatedCount;
    Result.TotalVkAllocationCount := FTotalVkAllocationCount;
    Result.MaxMemoryAllocationCount := FMaxMemoryAllocationCount;
    Result.SubAllocationCount := FSubAllocationCount;
    Result.TotalAllocatedBytes := FDedicatedBytes;
    Result.TotalUsedBytes := FDedicatedBytes;

    for I := 0 to VK_MAX_MEMORY_TYPES - 1 do
      for IsLinear := Low(Boolean) to High(Boolean) do
      begin
        Pool := FPools[I, IsLinear];
        Inc(Result.TotalBlockCount, Pool.Count);
        if IsLinear then
          Inc(Result.LinearBlockCount, Pool.Count)
        else
          Inc(Result.NonLinearBlockCount, Pool.Count);

        for J := 0 to Pool.Count - 1 do
        begin
          Inc(Result.TotalAllocatedBytes, Pool[J].Size);
          Inc(Result.TotalUsedBytes, Pool[J].UsedBytes);
        end;
      end;

    Result.SupportsMemoryBudgetExtension := QueryPhysicalDeviceMemoryBudget(
      FPhysicalDevice, FSupportsMemoryBudgetExt, Result.TotalUsedBytes,
      Result.DeviceMemoryUsedBytes, Result.DeviceMemoryBudgetBytes,
      Result.DeviceMemoryUsedMB, Result.DeviceMemoryBudgetMB);
  finally
    FLock.Release;
  end;
end;

end.
