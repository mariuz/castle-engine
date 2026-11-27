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

{$ifdef read_implementation}
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
  FOwnsCommandPool := True;
  FResetIndividualBuffer := True;
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

constructor TVulkanRHICommandList.CreateFromPool(const ADevice: TVulkanRHIDevice;
  const ACommandPool: VkCommandPool; const ALevel: TRHICommandListLevel;
  const AResetIndividualBuffer: Boolean);
var
  AllocInfo: VkCommandBufferAllocateInfo;
begin
  inherited Create(ALevel);
  FDevice := ADevice;
  FCommandPool := ACommandPool;
  FOwnsCommandPool := False;
  FResetIndividualBuffer := AResetIndividualBuffer;
  if (FDevice = nil) or (FDevice.Handle = nil) or (FCommandPool = VK_NULL_HANDLE) then
    Exit;

  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  AllocInfo.commandPool := FCommandPool;
  if ALevel = cllSecondary then
    AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_SECONDARY
  else
    AllocInfo.level := VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  AllocInfo.commandBufferCount := 1;
  CheckVk(vkAllocateCommandBuffers(FDevice.Handle, @AllocInfo, @FHandle),
    'vkAllocateCommandBuffers(WorkerPool)');
end;

destructor TVulkanRHICommandList.Destroy;
begin
  if FOwnsCommandPool and (FDevice <> nil) and (FDevice.Handle <> nil) and
     (FCommandPool <> VK_NULL_HANDLE) then
    vkDestroyCommandPool(FDevice.Handle, FCommandPool, nil);
  inherited;
end;

procedure TVulkanRHICommandList.ResetCommandTrackingState;
begin
  FActiveRenderingWidth := 0;
  FActiveRenderingHeight := 0;
  FViewportPendingReapply := False;
  FScissorPendingReapply := False;
  FCurrentPipeline := nil;
  FCurrentComputePipeline := nil;
  FBarrierCount := 0;
  FSync2BarrierCount := 0;
  FAliasingBarrierCount := 0;
  FComputeDispatchCount := 0;
  FDynamicStateChangeCount := 0;
  FIndirectDrawCallCount := 0;
  FIndirectCountDrawCallCount := 0;
  FMeshTasksDrawCallCount := 0;
  FLastEffectiveIndirectDrawCount := 0;
  FillChar(FBoundDescriptorSets, SizeOf(FBoundDescriptorSets), 0);
  FDescriptorSetBindCount := 0;
  FPipelineBindCount := 0;
  FLastPushConstantStageFlags := [];
  FLastPushConstantSize := 0;
  FPushConstantCallCount := 0;
  FClearAttachmentCallCount := 0;
  FDynamicBlendConstants := Vector4(1.0, 1.0, 1.0, 1.0);
  FBlendConstantsUpdateCount := 0;
  FSecondaryExecuteCount := 0;
  FDebugGroupPushCount := 0;
  FDebugGroupPopCount := 0;
  FDebugMarkerCount := 0;
  FLastDebugLabelName := '';
  FIsRendering := False;
  FActiveRenderingHasColor := False;
  FActiveRenderingColorFormat := pfUndefined;
  FActiveRenderingHasDepth := False;
  FActiveRenderingDepthFormat := pfUndefined;
  FActiveRenderingSampleCount := 1;
  if FDevice <> nil then
  begin
    Inc(FDevice.FCommandRecordingGeneration);
    FRecordingGeneration := FDevice.FCommandRecordingGeneration;
  end else
    Inc(FRecordingGeneration);
end;

procedure TVulkanRHICommandList.BeginRecording;
var
  BeginInfo: VkCommandBufferBeginInfo;
  InheritanceInfo: VkCommandBufferInheritanceInfo;
  InheritanceRendering: VkCommandBufferInheritanceRenderingInfo;
begin
  ResetCommandTrackingState;
  if FResetIndividualBuffer and (FHandle <> nil) and Assigned(vkResetCommandBuffer) then
    CheckVk(vkResetCommandBuffer(FHandle, 0), 'vkResetCommandBuffer');
  FillChar(BeginInfo, SizeOf(BeginInfo), 0);
  BeginInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  BeginInfo.flags := VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  if FLevel = cllSecondary then
  begin
    BeginInfo.flags := BeginInfo.flags or VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT;
    FillChar(InheritanceInfo, SizeOf(InheritanceInfo), 0);
    InheritanceInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO;
    if (FDevice <> nil) and FDevice.SupportsDynamicRendering then
    begin
      FillChar(InheritanceRendering, SizeOf(InheritanceRendering), 0);
      InheritanceRendering.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO;
      InheritanceRendering.flags := VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT;
      InheritanceRendering.rasterizationSamples := VK_SAMPLE_COUNT_1_BIT;
      InheritanceInfo.pNext := @InheritanceRendering;
    end;
    BeginInfo.pInheritanceInfo := @InheritanceInfo;
  end;
  if (FHandle <> nil) and Assigned(vkBeginCommandBuffer) then
    CheckVk(vkBeginCommandBuffer(FHandle, @BeginInfo), 'vkBeginCommandBuffer');
end;

procedure TVulkanRHICommandList.BeginSecondaryRecording(const AInheritedInfo: TRHIRenderingInfo;
  const AViewportRect: TFloatRectangle; const AScissorRect: TRectangle;
  const AMinDepth, AMaxDepth: Single);
var
  BeginInfo: VkCommandBufferBeginInfo;
  InheritanceInfo: VkCommandBufferInheritanceInfo;
  InheritanceRendering: VkCommandBufferInheritanceRenderingInfo;
  VkColorFormats: array of VkFormat;
  FallbackColorFormats: array of TRHIPixelFormat;
  ColorLoadOp, DepthLoadOp: TRHIAttachmentLoadOp;
  ColorStoreOp, DepthStoreOp: TRHIAttachmentStoreOp;
  HasColorResolve: Boolean;
  I: Integer;
begin
  ResetCommandTrackingState;
  if FResetIndividualBuffer and (FHandle <> nil) and Assigned(vkResetCommandBuffer) then
    CheckVk(vkResetCommandBuffer(FHandle, 0), 'vkResetCommandBuffer(Secondary)');

  FIsRendering := True;
  FActiveRenderingInfo := AInheritedInfo;
  FActiveRenderingInfo.ColorAttachments := Copy(AInheritedInfo.ColorAttachments);

  FActiveRenderingHasColor := (Length(AInheritedInfo.ColorAttachments) > 0) and
    (AInheritedInfo.ColorAttachments[0].Texture <> nil);
  if FActiveRenderingHasColor then
  begin
    FActiveRenderingColorFormat := AInheritedInfo.ColorAttachments[0].Texture.Desc.Format;
    FActiveRenderingSampleCount := Max(Cardinal(1),
      AInheritedInfo.ColorAttachments[0].Texture.Desc.SampleCount);
    FActiveRenderingWidth := Max(Cardinal(1),
      AInheritedInfo.ColorAttachments[0].Texture.Desc.Width shr AInheritedInfo.ColorAttachments[0].MipLevel);
    FActiveRenderingHeight := Max(Cardinal(1),
      AInheritedInfo.ColorAttachments[0].Texture.Desc.Height shr AInheritedInfo.ColorAttachments[0].MipLevel);
  end else
  begin
    FActiveRenderingColorFormat := pfUndefined;
    FActiveRenderingSampleCount := 1;
    FActiveRenderingWidth := 0;
    FActiveRenderingHeight := 0;
  end;

  FActiveRenderingHasDepth := AInheritedInfo.HasDepthAttachment and
    (AInheritedInfo.DepthAttachment.Texture <> nil);
  if FActiveRenderingHasDepth then
  begin
    FActiveRenderingDepthFormat := AInheritedInfo.DepthAttachment.Texture.Desc.Format;
    if not FActiveRenderingHasColor then
    begin
      FActiveRenderingSampleCount := Max(Cardinal(1),
        AInheritedInfo.DepthAttachment.Texture.Desc.SampleCount);
      FActiveRenderingWidth := Max(Cardinal(1),
        AInheritedInfo.DepthAttachment.Texture.Desc.Width shr AInheritedInfo.DepthAttachment.MipLevel);
      FActiveRenderingHeight := Max(Cardinal(1),
        AInheritedInfo.DepthAttachment.Texture.Desc.Height shr AInheritedInfo.DepthAttachment.MipLevel);
    end;
  end else
    FActiveRenderingDepthFormat := pfUndefined;

  if FActiveRenderingWidth = 0 then
    FActiveRenderingWidth := Cardinal(Max(1,
      Max(0, AInheritedInfo.RenderArea.Left) + Max(1, AInheritedInfo.RenderArea.Width)));
  if FActiveRenderingHeight = 0 then
    FActiveRenderingHeight := Cardinal(Max(1,
      Max(0, AInheritedInfo.RenderArea.Bottom) + Max(1, AInheritedInfo.RenderArea.Height)));

  FillChar(BeginInfo, SizeOf(BeginInfo), 0);
  BeginInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
  BeginInfo.flags := VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT or
    VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT;

  FillChar(InheritanceInfo, SizeOf(InheritanceInfo), 0);
  InheritanceInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO;

  if (FDevice <> nil) and (not FDevice.SupportsDynamicRendering) then
  begin
    SetLength(FallbackColorFormats, Length(AInheritedInfo.ColorAttachments));
    for I := 0 to High(AInheritedInfo.ColorAttachments) do
      if AInheritedInfo.ColorAttachments[I].Texture <> nil then
        FallbackColorFormats[I] := AInheritedInfo.ColorAttachments[I].Texture.Desc.Format
      else
        FallbackColorFormats[I] := pfBGRA8_UNorm;
    HasColorResolve := (FActiveRenderingSampleCount > 1) and
      (Length(AInheritedInfo.ColorAttachments) > 0) and
      (AInheritedInfo.ColorAttachments[0].ResolveTexture <> nil);
    if Length(AInheritedInfo.ColorAttachments) > 0 then
    begin
      ColorLoadOp := AInheritedInfo.ColorAttachments[0].LoadOp;
      ColorStoreOp := AInheritedInfo.ColorAttachments[0].StoreOp;
    end else
    begin
      ColorLoadOp := loLoad;
      ColorStoreOp := soStore;
    end;
    if AInheritedInfo.HasDepthAttachment then
    begin
      DepthLoadOp := AInheritedInfo.DepthAttachment.LoadOp;
      DepthStoreOp := AInheritedInfo.DepthAttachment.StoreOp;
    end else
    begin
      DepthLoadOp := loLoad;
      DepthStoreOp := soStore;
    end;
    InheritanceInfo.renderPass := FDevice.GetOrCreateFallbackRenderPass(
      FallbackColorFormats, FActiveRenderingDepthFormat, FActiveRenderingSampleCount,
      ColorLoadOp, DepthLoadOp, ColorStoreOp, DepthStoreOp, HasColorResolve);
  end else
  begin
    FillChar(InheritanceRendering, SizeOf(InheritanceRendering), 0);
    InheritanceRendering.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_RENDERING_INFO;
    InheritanceRendering.flags := VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT;
    SetLength(VkColorFormats, Length(AInheritedInfo.ColorAttachments));
    for I := 0 to High(AInheritedInfo.ColorAttachments) do
      if AInheritedInfo.ColorAttachments[I].Texture <> nil then
        VkColorFormats[I] := RHIToVkFormat(AInheritedInfo.ColorAttachments[I].Texture.Desc.Format)
      else
        VkColorFormats[I] := VK_FORMAT_UNDEFINED;
    InheritanceRendering.colorAttachmentCount := Length(VkColorFormats);
    if Length(VkColorFormats) > 0 then
      InheritanceRendering.pColorAttachmentFormats := @VkColorFormats[0];
    if FActiveRenderingHasDepth then
    begin
      InheritanceRendering.depthAttachmentFormat := RHIToVkFormat(FActiveRenderingDepthFormat);
      if FActiveRenderingDepthFormat in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
        InheritanceRendering.stencilAttachmentFormat := InheritanceRendering.depthAttachmentFormat;
    end;
    InheritanceRendering.rasterizationSamples := RHIToVkSampleCountFlags(FActiveRenderingSampleCount);
    InheritanceInfo.pNext := @InheritanceRendering;
  end;

  BeginInfo.pInheritanceInfo := @InheritanceInfo;
  if (FHandle <> nil) and Assigned(vkBeginCommandBuffer) then
    CheckVk(vkBeginCommandBuffer(FHandle, @BeginInfo), 'vkBeginCommandBuffer(Secondary)');

  SetViewport(AViewportRect, AMinDepth, AMaxDepth);
  SetScissor(AScissorRect);
end;

procedure TVulkanRHICommandList.EndRecording;
begin
  FIsRendering := False;
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

procedure TVulkanRHICommandList.EmitAliasingBarrier(const OldTexture, NewTexture: TRHITexture);
var
  MemBar2: VkMemoryBarrier2;
  DepInfo: VkDependencyInfo;
  MemBar: VkMemoryBarrier;
begin
  if NewTexture = nil then
    Exit;
  if OldTexture = nil then ;

  Inc(FAliasingBarrierCount);
  if (FDevice <> nil) and FDevice.SupportsSynchronization2 then
  begin
    FillChar(MemBar2, SizeOf(MemBar2), 0);
    MemBar2.sType := VK_STRUCTURE_TYPE_MEMORY_BARRIER_2;
    MemBar2.srcStageMask := VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    MemBar2.srcAccessMask := VK_ACCESS_2_MEMORY_WRITE_BIT or VK_ACCESS_2_MEMORY_READ_BIT;
    MemBar2.dstStageMask := VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    MemBar2.dstAccessMask := VK_ACCESS_2_MEMORY_READ_BIT or VK_ACCESS_2_MEMORY_WRITE_BIT;

    FillChar(DepInfo, SizeOf(DepInfo), 0);
    DepInfo.sType := VK_STRUCTURE_TYPE_DEPENDENCY_INFO;
    DepInfo.memoryBarrierCount := 1;
    DepInfo.pMemoryBarriers := @MemBar2;

    if (FHandle <> nil) and Assigned(vkCmdPipelineBarrier2) then
      vkCmdPipelineBarrier2(FHandle, @DepInfo);
    Inc(FBarrierCount);
    Inc(FSync2BarrierCount);
    Inc(FDevice.FSync2BarrierCount);
    Exit;
  end;

  FillChar(MemBar, SizeOf(MemBar), 0);
  MemBar.sType := VK_STRUCTURE_TYPE_MEMORY_BARRIER;
  MemBar.srcAccessMask := VK_ACCESS_MEMORY_WRITE_BIT or VK_ACCESS_MEMORY_READ_BIT;
  MemBar.dstAccessMask := VK_ACCESS_MEMORY_READ_BIT or VK_ACCESS_MEMORY_WRITE_BIT;

  if (FHandle <> nil) and Assigned(vkCmdPipelineBarrier) then
    vkCmdPipelineBarrier(FHandle,
      VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
      VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
      0, 1, @MemBar, 0, nil, 0, nil);
  Inc(FBarrierCount);
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
  if (Buffer = nil) or ((OldState = NewState) and (OldState <> rsUnorderedAccess)) then
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
begin
  if (Texture = nil) or (Texture.Desc.MipLevels <= 1) then
    Exit;

  VkTex := Texture as TVulkanRHITexture;
  Inc(VkTex.FMipmapGenerationCount);
  VkTex.FLastGeneratedMipLevels := VkTex.Desc.MipLevels;
  VkTex.FMaxUploadedMipLevel := Max(VkTex.FMaxUploadedMipLevel, VkTex.Desc.MipLevels - 1);

  if VkTex.TryUploadPortabilityCubeMipmapsFromHost then
  begin
    Texture.CurrentState := rsShaderRead;
    Exit;
  end;

  if (FHandle <> nil) and Assigned(vkCmdBlitImage) then
  begin
    if (FDevice <> nil) and (FDevice.StagingUploader <> nil) and (Level = cllPrimary) then
      FDevice.StagingUploader.FlushPendingUploads(Self);
    VkTex.RecordVkMipmapBlits(FHandle);
  end;

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
  VkRenderAreaRect: VkRect2D;
  WawImgBarrier: VkImageMemoryBarrier;
  WawVkTex: TVulkanRHITexture;
  AttCount, ResolveBaseIdx, I: Integer;
begin
  { Flush any pending staged buffer/image uploads outside the render pass instance
    (VUID-vkCmdCopyBuffer-renderpass / VUID-vkCmdCopyBufferToImage-renderpass) }
  if (FDevice <> nil) and (FDevice.StagingUploader <> nil) and (Level = cllPrimary) then
    FDevice.StagingUploader.FlushPendingUploads(Self);

  { On real Vulkan devices, ensure attachment images are transitioned into attachment-optimal layouts
    before beginning the render pass instance. When an attachment is ALREADY in attachment-optimal
    layout from an earlier dynamic rendering pass (e.g. suspended/resumed outer pass around RTT),
    VK_KHR_dynamic_rendering provides zero implicit synchronization between passes, so emit an
    explicit same-layout WAW/RAW VkImageMemoryBarrier to prevent TBDR / Apple Paravirtual tile races. }
  if FHandle <> nil then
  begin
    for I := 0 to High(Info.ColorAttachments) do
      if Info.ColorAttachments[I].Texture <> nil then
      begin
        if Info.ColorAttachments[I].Texture.CurrentState <> rsColorAttachment then
          TransitionTexture(Info.ColorAttachments[I].Texture, rsColorAttachment)
        else if Assigned(vkCmdPipelineBarrier) then
        begin
          WawVkTex := Info.ColorAttachments[I].Texture as TVulkanRHITexture;
          if WawVkTex.Image <> VK_NULL_HANDLE then
          begin
            FillChar(WawImgBarrier, SizeOf(WawImgBarrier), 0);
            WawImgBarrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            WawImgBarrier.srcAccessMask := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            WawImgBarrier.dstAccessMask := VK_ACCESS_COLOR_ATTACHMENT_READ_BIT or VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            WawImgBarrier.oldLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
            WawImgBarrier.newLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
            WawImgBarrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
            WawImgBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
            WawImgBarrier.image := WawVkTex.Image;
            WawImgBarrier.subresourceRange.aspectMask := WawVkTex.AspectMask;
            WawImgBarrier.subresourceRange.baseMipLevel := 0;
            WawImgBarrier.subresourceRange.levelCount := WawVkTex.Desc.MipLevels;
            WawImgBarrier.subresourceRange.baseArrayLayer := 0;
            WawImgBarrier.subresourceRange.layerCount := WawVkTex.Desc.DepthOrArrayLayers;
            vkCmdPipelineBarrier(FHandle,
              VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
              VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
              0, 0, nil, 0, nil, 1, @WawImgBarrier);
          end;
        end;
      end;
    if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
    begin
      if Info.DepthAttachment.Texture.CurrentState <> rsDepthStencilWrite then
        TransitionTexture(Info.DepthAttachment.Texture, rsDepthStencilWrite)
      else if Assigned(vkCmdPipelineBarrier) then
      begin
        WawVkTex := Info.DepthAttachment.Texture as TVulkanRHITexture;
        if WawVkTex.Image <> VK_NULL_HANDLE then
        begin
          FillChar(WawImgBarrier, SizeOf(WawImgBarrier), 0);
          WawImgBarrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
          WawImgBarrier.srcAccessMask := VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
          WawImgBarrier.dstAccessMask := VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT or VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
          WawImgBarrier.oldLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
          WawImgBarrier.newLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
          WawImgBarrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
          WawImgBarrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
          WawImgBarrier.image := WawVkTex.Image;
          WawImgBarrier.subresourceRange.aspectMask := WawVkTex.AspectMask;
          WawImgBarrier.subresourceRange.baseMipLevel := 0;
          WawImgBarrier.subresourceRange.levelCount := WawVkTex.Desc.MipLevels;
          WawImgBarrier.subresourceRange.baseArrayLayer := 0;
          WawImgBarrier.subresourceRange.layerCount := WawVkTex.Desc.DepthOrArrayLayers;
          vkCmdPipelineBarrier(FHandle,
            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            0, 0, nil, 0, nil, 1, @WawImgBarrier);
        end;
      end;
    end;
  end;

  FIsRendering := True;
  FCurrentPassHasCommands := False;
  FActiveRenderingInfo := Info;
  FActiveRenderingInfo.ColorAttachments := Copy(Info.ColorAttachments);
  if FViewportPendingReapply and
     ((FDynamicViewportRect.Left < Info.RenderArea.Left - 0.5) or
      (FDynamicViewportRect.Bottom < Info.RenderArea.Bottom - 0.5) or
      (FDynamicViewportRect.Left + FDynamicViewportRect.Width > Info.RenderArea.Left + Info.RenderArea.Width + 0.5) or
      (FDynamicViewportRect.Bottom + FDynamicViewportRect.Height > Info.RenderArea.Bottom + Info.RenderArea.Height + 0.5)) then
    FViewportPendingReapply := False;
  if FScissorPendingReapply and
     ((FDynamicScissorRect.Left < Info.RenderArea.Left) or
      (FDynamicScissorRect.Bottom < Info.RenderArea.Bottom) or
      (FDynamicScissorRect.Left + FDynamicScissorRect.Width > Info.RenderArea.Left + Info.RenderArea.Width) or
      (FDynamicScissorRect.Bottom + FDynamicScissorRect.Height > Info.RenderArea.Bottom + Info.RenderArea.Height)) then
    FScissorPendingReapply := False;
  if not FScissorPendingReapply then
    FDynamicScissorRect := Info.RenderArea;
  FActiveRenderingHasColor := (Length(Info.ColorAttachments) > 0) and (Info.ColorAttachments[0].Texture <> nil);
  if FActiveRenderingHasColor then
  begin
    FActiveRenderingColorFormat := Info.ColorAttachments[0].Texture.Desc.Format;
    FActiveRenderingSampleCount := Max(Cardinal(1), Info.ColorAttachments[0].Texture.Desc.SampleCount);
    FActiveRenderingWidth := Max(Cardinal(1),
      Info.ColorAttachments[0].Texture.Desc.Width shr Info.ColorAttachments[0].MipLevel);
    FActiveRenderingHeight := Max(Cardinal(1),
      Info.ColorAttachments[0].Texture.Desc.Height shr Info.ColorAttachments[0].MipLevel);
  end else
  begin
    FActiveRenderingColorFormat := pfUndefined;
    FActiveRenderingSampleCount := 1;
    FActiveRenderingWidth := 0;
    FActiveRenderingHeight := 0;
  end;
  FActiveRenderingHasDepth := Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil);
  if FActiveRenderingHasDepth then
  begin
    FActiveRenderingDepthFormat := Info.DepthAttachment.Texture.Desc.Format;
    if not FActiveRenderingHasColor then
    begin
      FActiveRenderingSampleCount := Max(Cardinal(1), Info.DepthAttachment.Texture.Desc.SampleCount);
      FActiveRenderingWidth := Max(Cardinal(1),
        Info.DepthAttachment.Texture.Desc.Width shr Info.DepthAttachment.MipLevel);
      FActiveRenderingHeight := Max(Cardinal(1),
        Info.DepthAttachment.Texture.Desc.Height shr Info.DepthAttachment.MipLevel);
    end;
  end else
    FActiveRenderingDepthFormat := pfUndefined;

  if FActiveRenderingWidth = 0 then
    FActiveRenderingWidth := Cardinal(Max(1, Max(0, Info.RenderArea.Left) + Max(1, Info.RenderArea.Width)));
  if FActiveRenderingHeight = 0 then
    FActiveRenderingHeight := Cardinal(Max(1, Max(0, Info.RenderArea.Bottom) + Max(1, Info.RenderArea.Height)));

  ComputeVkScissorRect(Info.RenderArea, VkRenderAreaRect);
  if VkRenderAreaRect.extent.width = 0 then
    VkRenderAreaRect.extent.width := Max(Cardinal(1), Cardinal(Max(1, Info.RenderArea.Width)));
  if VkRenderAreaRect.extent.height = 0 then
    VkRenderAreaRect.extent.height := Max(Cardinal(1), Cardinal(Max(1, Info.RenderArea.Height)));

  if (FDevice <> nil) and (Length(FDevice.FSwapchainColorTextures) = 0) then
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
        with Info.ColorAttachments[I].Texture as TVulkanRHITexture do
        begin
          FLastRenderedMipLevel := Info.ColorAttachments[I].MipLevel;
          FLastRenderedArrayLayer := Info.ColorAttachments[I].ArrayLayer;
          FRenderedLayerMask := FRenderedLayerMask or (Cardinal(1) shl Min(Cardinal(31), Info.ColorAttachments[I].ArrayLayer));
          FallbackViews[I] := GetSubresourceImageView(
            Info.ColorAttachments[I].MipLevel,
            Info.ColorAttachments[I].ArrayLayer);
        end;
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
          with Info.ColorAttachments[I].ResolveTexture as TVulkanRHITexture do
          begin
            FLastRenderedMipLevel := Info.ColorAttachments[I].MipLevel;
            FLastRenderedArrayLayer := Info.ColorAttachments[I].ArrayLayer;
            FRenderedLayerMask := FRenderedLayerMask or (Cardinal(1) shl Min(Cardinal(31), Info.ColorAttachments[I].ArrayLayer));
            FallbackViews[ResolveBaseIdx + I] := GetSubresourceImageView(
              Info.ColorAttachments[I].MipLevel,
              Info.ColorAttachments[I].ArrayLayer);
          end;
        end else
          FallbackViews[ResolveBaseIdx + I] := VK_NULL_HANDLE;
        FillChar(FallbackClears[ResolveBaseIdx + I], SizeOf(VkClearValue), 0);
      end;
    end;

    if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
    begin
      FallbackDepthFormat := Info.DepthAttachment.Texture.Desc.Format;
      with Info.DepthAttachment.Texture as TVulkanRHITexture do
      begin
        FLastRenderedMipLevel := Info.DepthAttachment.MipLevel;
        FLastRenderedArrayLayer := Info.DepthAttachment.ArrayLayer;
        FRenderedLayerMask := FRenderedLayerMask or (Cardinal(1) shl Min(Cardinal(31), Info.DepthAttachment.ArrayLayer));
        FallbackViews[ResolveBaseIdx - 1] := GetSubresourceImageView(
          Info.DepthAttachment.MipLevel,
          Info.DepthAttachment.ArrayLayer);
      end;
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
    RpBeginInfo.renderArea := VkRenderAreaRect;
    RpBeginInfo.clearValueCount := Length(FallbackClears);
    if Length(FallbackClears) > 0 then
      RpBeginInfo.pClearValues := @FallbackClears[0];

    FInFallbackRenderPass := True;
    Inc(FDevice.FFallbackRenderPassBeginCount);
    if HasColorResolve then
      Inc(FDevice.FMSAAResolvePassCount);
    if (FHandle <> nil) and Assigned(vkCmdBeginRenderPass) then
    begin
      if Info.ContentsSecondaryCommandBuffers then
        vkCmdBeginRenderPass(FHandle, @RpBeginInfo, VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS)
      else
        vkCmdBeginRenderPass(FHandle, @RpBeginInfo, VK_SUBPASS_CONTENTS_INLINE);
    end;
    if not Info.ContentsSecondaryCommandBuffers then
    begin
      if FViewportPendingReapply then
        SetViewport(FDynamicViewportRect, FDynamicMinDepth, FDynamicMaxDepth)
      else
      if FHandle <> nil then
        SetViewport(FloatRectangle(Info.RenderArea), 0.0, 1.0);
      if FScissorPendingReapply then
        SetScissor(FDynamicScissorRect)
      else
      if FHandle <> nil then
        SetScissor(FDynamicScissorRect);
    end;
    Exit;
  end;

  HasAnyResolve := False;
  SetLength(ColorAttachments, Length(Info.ColorAttachments));
  for I := 0 to High(Info.ColorAttachments) do
  begin
    FillChar(ColorAttachments[I], SizeOf(VkRenderingAttachmentInfo), 0);
    ColorAttachments[I].sType := VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
    if Info.ColorAttachments[I].Texture <> nil then
    begin
      with Info.ColorAttachments[I].Texture as TVulkanRHITexture do
      begin
        FLastRenderedMipLevel := Info.ColorAttachments[I].MipLevel;
        FLastRenderedArrayLayer := Info.ColorAttachments[I].ArrayLayer;
        FRenderedLayerMask := FRenderedLayerMask or (Cardinal(1) shl Min(Cardinal(31), Info.ColorAttachments[I].ArrayLayer));
        ColorAttachments[I].imageView := GetSubresourceImageView(
          Info.ColorAttachments[I].MipLevel,
          Info.ColorAttachments[I].ArrayLayer);
      end;
    end;
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
      with Info.ColorAttachments[I].ResolveTexture as TVulkanRHITexture do
      begin
        FLastRenderedMipLevel := Info.ColorAttachments[I].MipLevel;
        FLastRenderedArrayLayer := Info.ColorAttachments[I].ArrayLayer;
        FRenderedLayerMask := FRenderedLayerMask or (Cardinal(1) shl Min(Cardinal(31), Info.ColorAttachments[I].ArrayLayer));
        ColorAttachments[I].resolveImageView := GetSubresourceImageView(
          Info.ColorAttachments[I].MipLevel,
          Info.ColorAttachments[I].ArrayLayer);
      end;
      ColorAttachments[I].resolveImageLayout := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
      HasAnyResolve := True;
    end;
  end;

  FillChar(RenderInfo, SizeOf(RenderInfo), 0);
  RenderInfo.sType := VK_STRUCTURE_TYPE_RENDERING_INFO;
  if Info.ContentsSecondaryCommandBuffers then
    RenderInfo.flags := VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT;
  RenderInfo.renderArea := VkRenderAreaRect;
  RenderInfo.layerCount := 1;
  RenderInfo.colorAttachmentCount := Length(ColorAttachments);
  if Length(ColorAttachments) > 0 then
    RenderInfo.pColorAttachments := @ColorAttachments[0];

  if Info.HasDepthAttachment and (Info.DepthAttachment.Texture <> nil) then
  begin
    FillChar(DepthAttachment, SizeOf(DepthAttachment), 0);
    DepthAttachment.sType := VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO;
    with Info.DepthAttachment.Texture as TVulkanRHITexture do
    begin
      FLastRenderedMipLevel := Info.DepthAttachment.MipLevel;
      FLastRenderedArrayLayer := Info.DepthAttachment.ArrayLayer;
      FRenderedLayerMask := FRenderedLayerMask or (Cardinal(1) shl Min(Cardinal(31), Info.DepthAttachment.ArrayLayer));
      DepthAttachment.imageView := GetSubresourceImageView(
        Info.DepthAttachment.MipLevel,
        Info.DepthAttachment.ArrayLayer);
    end;
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
      with Info.DepthAttachment.ResolveTexture as TVulkanRHITexture do
      begin
        FLastRenderedMipLevel := Info.DepthAttachment.MipLevel;
        FLastRenderedArrayLayer := Info.DepthAttachment.ArrayLayer;
        FRenderedLayerMask := FRenderedLayerMask or (Cardinal(1) shl Min(Cardinal(31), Info.DepthAttachment.ArrayLayer));
        DepthAttachment.resolveImageView := ImageView;
      end;
      DepthAttachment.resolveImageLayout := VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
      HasAnyResolve := True;
    end;

    RenderInfo.pDepthAttachment := @DepthAttachment;
    if Info.DepthAttachment.Texture.Desc.Format in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt] then
      RenderInfo.pStencilAttachment := @DepthAttachment;
  end;

  if HasAnyResolve and (FDevice <> nil) then
    Inc(FDevice.FMSAAResolvePassCount);

  if (FHandle <> nil) and Assigned(vkCmdBeginRendering) then
    vkCmdBeginRendering(FHandle, @RenderInfo);
  if not Info.ContentsSecondaryCommandBuffers then
  begin
    if FViewportPendingReapply then
      SetViewport(FDynamicViewportRect, FDynamicMinDepth, FDynamicMaxDepth)
    else
    if FHandle <> nil then
      SetViewport(FloatRectangle(Info.RenderArea), 0.0, 1.0);
    if FScissorPendingReapply then
      SetScissor(FDynamicScissorRect)
    else
    if FHandle <> nil then
      SetScissor(FDynamicScissorRect);
  end;
end;

procedure TVulkanRHICommandList.EndRendering;
begin
  FIsRendering := False;
  FCurrentPassHasCommands := False;
  FViewportPendingReapply := False;
  FScissorPendingReapply := False;
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

procedure TVulkanRHICommandList.ComputeVkScissorRect(const ARect: TRectangle;
  out AVkRect: VkRect2D);
var
  LeftX, RightX, TopY, BotY: Integer;
begin
  FillChar(AVkRect, SizeOf(AVkRect), 0);
  if FIsRendering and (FActiveRenderingHeight > 0) then
  begin
    LeftX := Max(0, ARect.Left);
    if FActiveRenderingWidth > 0 then
      RightX := Min(Integer(FActiveRenderingWidth), ARect.Left + Max(0, ARect.Width))
    else
      RightX := LeftX + Max(0, ARect.Width);
    TopY := Max(0, Integer(FActiveRenderingHeight) - (ARect.Bottom + Max(0, ARect.Height)));
    BotY := Min(Integer(FActiveRenderingHeight), Integer(FActiveRenderingHeight) - ARect.Bottom);
    AVkRect.offset.x := LeftX;
    AVkRect.offset.y := TopY;
    AVkRect.extent.width := Cardinal(Max(0, RightX - LeftX));
    AVkRect.extent.height := Cardinal(Max(0, BotY - TopY));
  end else
  begin
    AVkRect.offset.x := Max(0, ARect.Left);
    AVkRect.offset.y := Max(0, ARect.Bottom);
    AVkRect.extent.width := Cardinal(Max(0, ARect.Width));
    AVkRect.extent.height := Cardinal(Max(0, ARect.Height));
  end;
end;

procedure TVulkanRHICommandList.ClearAttachments(const ClearColorBuf: Boolean; const ClearColor: TCastleColor;
  const ClearDepthBuf: Boolean; const ClearDepth: Single;
  const ClearStencilBuf: Boolean; const ClearStencil: Byte);
var
  ColorTarget, DepthTarget: TRHITexture;
  ClearAtts: array[0..8] of VkClearAttachment;
  ClearRect: VkClearRect;
  ClearAttCount: Cardinal;
  DepthStencilAspect: VkImageAspectFlags;
  I: Integer;
begin
  if FDevice = nil then
    Exit;

  if FIsRendering then
  begin
    FCurrentPassHasCommands := True;
    Inc(FClearAttachmentCallCount);
    if (FHandle <> nil) and Assigned(vkCmdClearAttachments) then
    begin
      ClearAttCount := 0;
      FillChar(ClearAtts, SizeOf(ClearAtts), 0);
      if ClearColorBuf then
      begin
        for I := 0 to Min(7, High(FActiveRenderingInfo.ColorAttachments)) do
          if FActiveRenderingInfo.ColorAttachments[I].Texture <> nil then
          begin
            ClearAtts[ClearAttCount].aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
            ClearAtts[ClearAttCount].colorAttachment := Cardinal(I);
            Move(ClearColor.Data, ClearAtts[ClearAttCount].clearValue.color.float32, SizeOf(Single) * 4);
            Inc(ClearAttCount);
          end;
      end;
      if (ClearDepthBuf or ClearStencilBuf) and FActiveRenderingHasDepth then
      begin
        DepthStencilAspect := 0;
        if ClearDepthBuf then
          DepthStencilAspect := DepthStencilAspect or VK_IMAGE_ASPECT_DEPTH_BIT;
        if ClearStencilBuf and
           (FActiveRenderingDepthFormat in [pfD24_UNorm_S8_UInt, pfD32_Float_S8_UInt]) then
          DepthStencilAspect := DepthStencilAspect or VK_IMAGE_ASPECT_STENCIL_BIT;
        if DepthStencilAspect <> 0 then
        begin
          ClearAtts[ClearAttCount].aspectMask := DepthStencilAspect;
          ClearAtts[ClearAttCount].clearValue.depthStencil.depth := ClearDepth;
          ClearAtts[ClearAttCount].clearValue.depthStencil.stencil := ClearStencil;
          Inc(ClearAttCount);
        end;
      end;
      if ClearAttCount > 0 then
      begin
        FillChar(ClearRect, SizeOf(ClearRect), 0);
        ComputeVkScissorRect(FDynamicScissorRect, ClearRect.rect);
        ClearRect.baseArrayLayer := 0;
        ClearRect.layerCount := 1;
        if (ClearRect.rect.extent.width > 0) and (ClearRect.rect.extent.height > 0) then
          vkCmdClearAttachments(FHandle, ClearAttCount, @ClearAtts[0], 1, @ClearRect);
      end;
    end;
  end;

  if (FDevice.Handle = nil) then
  begin
    if FIsRendering then
    begin
      if ClearColorBuf then
      begin
        for I := 0 to High(FActiveRenderingInfo.ColorAttachments) do
        begin
          FActiveRenderingInfo.ColorAttachments[I].ClearColor := ClearColor;
          ColorTarget := FActiveRenderingInfo.ColorAttachments[I].Texture;
          if ColorTarget is TVulkanRHITexture then
            TVulkanRHITexture(ColorTarget).SetHostClearColorRect(ClearColor, FDynamicScissorRect);
          ColorTarget := FActiveRenderingInfo.ColorAttachments[I].ResolveTexture;
          if ColorTarget is TVulkanRHITexture then
            TVulkanRHITexture(ColorTarget).SetHostClearColorRect(ClearColor, FDynamicScissorRect);
        end;
      end;
      if ClearDepthBuf and FActiveRenderingInfo.HasDepthAttachment then
      begin
        FActiveRenderingInfo.DepthAttachment.ClearDepth := ClearDepth;
        DepthTarget := FActiveRenderingInfo.DepthAttachment.Texture;
        if DepthTarget is TVulkanRHITexture then
          TVulkanRHITexture(DepthTarget).SetHostClearDepth(ClearDepth);
        DepthTarget := FActiveRenderingInfo.DepthAttachment.ResolveTexture;
        if DepthTarget is TVulkanRHITexture then
          TVulkanRHITexture(DepthTarget).SetHostClearDepth(ClearDepth);
      end;
    end else
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
end;

procedure TVulkanRHICommandList.SetViewport(const ViewportRect: TFloatRectangle;
  const MinDepth, MaxDepth: Single);
var
  VkVP: VkViewport;
begin
  FDynamicViewportRect := ViewportRect;
  FDynamicMinDepth := MinDepth;
  FDynamicMaxDepth := MaxDepth;
  { Flip Y-axis using VK_KHR_maintenance1 negative height so CGE camera matrices,
    counter-clockwise winding orders, and bottom-up sub-viewport rectangles (Bottom = 0
    at attachment bottom) map cleanly to Vulkan's top-down framebuffer space. }
  VkVP.x := ViewportRect.Left;
  if FIsRendering and (FActiveRenderingHeight > 0) then
  begin
    VkVP.y := Single(FActiveRenderingHeight) - ViewportRect.Bottom;
    FViewportPendingReapply := False;
  end else
  begin
    VkVP.y := ViewportRect.Bottom + ViewportRect.Height;
    FViewportPendingReapply := True;
  end;
  FLastVkViewportY := VkVP.y;
  VkVP.width := Max(1.0, ViewportRect.Width);
  VkVP.height := -Max(1.0, ViewportRect.Height);
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
  ComputeVkScissorRect(ScissorRect, VkRect);
  FLastVkScissorOffsetY := VkRect.offset.y;
  FScissorPendingReapply := not FIsRendering;
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

procedure TVulkanRHICommandList.SetLineWidth(const LineWidth: Single);
begin
  FDynamicLineWidth := Max(1.0, LineWidth);
  Inc(FLineWidthUpdateCount);
end;

procedure TVulkanRHICommandList.SetBlendConstants(const ABlendConstants: TVector4);
begin
  FDynamicBlendConstants := ABlendConstants;
  Inc(FBlendConstantsUpdateCount);
  Inc(FDynamicStateChangeCount);
  if (FHandle <> nil) and Assigned(vkCmdSetBlendConstants) then
    vkCmdSetBlendConstants(FHandle, @ABlendConstants.Data[0]);
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
  if FCurrentPipeline <> nil then
    Inc(FPipelineBindCount);
  if (FHandle <> nil) and (FCurrentPipeline <> nil) and Assigned(vkCmdBindPipeline) then
    vkCmdBindPipeline(FHandle, VK_PIPELINE_BIND_POINT_GRAPHICS, FCurrentPipeline.Handle);

  if (FCurrentPipeline <> nil) and (FDevice <> nil) and FDevice.SupportsExtendedDynamicState then
  begin
    SetCullMode(FCurrentPipeline.Desc.Rasterizer.CullMode);
    SetFrontFace(FCurrentPipeline.Desc.Rasterizer.FrontFace);
    if FCurrentPipeline.Desc.MeshShader = nil then
      SetPrimitiveTopology(FCurrentPipeline.Desc.Topology);
    if FIsRendering and (not FActiveRenderingHasDepth) then
    begin
      SetDepthTestEnable(False);
      SetDepthWriteEnable(False);
    end else
    begin
      SetDepthTestEnable(FCurrentPipeline.Desc.DepthStencil.DepthTestEnable);
      SetDepthWriteEnable(FCurrentPipeline.Desc.DepthStencil.DepthWriteEnable);
    end;
    SetDepthCompareOp(FCurrentPipeline.Desc.DepthStencil.DepthCompareOp);
  end;
end;

function TVulkanRHICommandList.GetBoundDescriptorSet(const ASetIndex: Cardinal): TRHIDescriptorSet;
begin
  if ASetIndex <= High(FBoundDescriptorSets) then
    Result := FBoundDescriptorSets[ASetIndex]
  else
    Result := nil;
end;

procedure TVulkanRHICommandList.BindDescriptorSet(const SetIndex: Cardinal;
  const DescriptorSet: TRHIDescriptorSet; const DynamicOffsets: array of Cardinal);
var
  SetHandle: VkDescriptorSet;
  OffsetPtr: PUInt32;
begin
  if DescriptorSet = nil then Exit;
  if SetIndex <= High(FBoundDescriptorSets) then
    FBoundDescriptorSets[SetIndex] := DescriptorSet;
  Inc(FDescriptorSetBindCount);
  SetHandle := (DescriptorSet as TVulkanRHIDescriptorSet).Handle;
  if Length(DynamicOffsets) > 0 then
    OffsetPtr := @DynamicOffsets[0]
  else
    OffsetPtr := nil;

  if (FHandle <> nil) and (FCurrentPipeline <> nil) and Assigned(vkCmdBindDescriptorSets) then
  begin
    (DescriptorSet as TVulkanRHIDescriptorSet).MarkBoundToLiveCommandBuffer;
    vkCmdBindDescriptorSets(FHandle, VK_PIPELINE_BIND_POINT_GRAPHICS,
      FCurrentPipeline.PipelineLayout, SetIndex, 1, @SetHandle,
      Length(DynamicOffsets), OffsetPtr);
  end;
end;

procedure TVulkanRHICommandList.PushConstants(const StageFlags: TRHIShaderStageFlags;
  const Offset, Size: Cardinal; const Data);
var
  TargetLayout: VkPipelineLayout;
begin
  FLastPushConstantStageFlags := StageFlags;
  FLastPushConstantSize := Size;
  Inc(FPushConstantCallCount);
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
  begin
    (DescriptorSet as TVulkanRHIDescriptorSet).MarkBoundToLiveCommandBuffer;
    vkCmdBindDescriptorSets(FHandle, VK_PIPELINE_BIND_POINT_COMPUTE,
      FCurrentComputePipeline.PipelineLayout, SetIndex, 1, @SetHandle,
      Length(DynamicOffsets), OffsetPtr);
  end;
end;

procedure TVulkanRHICommandList.Dispatch(const GroupCountX, GroupCountY, GroupCountZ: Cardinal);
begin
  if (FHandle <> nil) and (not FIsRendering) and (Level = cllPrimary) and
     (FDevice <> nil) and (FDevice.StagingUploader <> nil) and
     ((FDevice.StagingUploader.PendingBufferCopyCount > 0) or
      (FDevice.StagingUploader.PendingImageCopyCount > 0)) then
    FDevice.StagingUploader.FlushPendingUploads(Self);

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
  EndExclusive, I: Cardinal;
  DidHostReset: Boolean;
begin
  if (QueryPool = nil) or (QueryCount = 0) then Exit;
  VkPool := QueryPool as TVulkanRHIQueryPool;
  Inc(VkPool.FResetCount);
  EndExclusive := Min(FirstQuery + QueryCount, Cardinal(Length(VkPool.FQueryWritten)));
  { VUID-vkCmdResetQueryPool-renderpass: vkCmdResetQueryPool is illegal inside an active
    render pass instance. When called mid-pass (e.g. TShape.OcclusionQueryId lazy init
    inside TCastleViewport), use VK_EXT_host_query_reset / Vulkan 1.2 vkResetQueryPool.
    Never host-reset a query that was already recorded in the current VkCommandBuffer
    (e.g. multi-pass or shared shapes), because host resets occur before vkQueueSubmit
    and cannot reset a query between two vkCmdBeginQuery calls in the same command buffer. }
  if FIsRendering then
  begin
    if (FDevice <> nil) and FDevice.SupportsHostQueryReset then
    begin
      DidHostReset := False;
      for I := FirstQuery to EndExclusive - 1 do
      begin
        if (FRecordingGeneration <> 0) and
           (VkPool.FQueryRecordedGeneration[I] = FRecordingGeneration) then
          Continue;
        VkPool.FQueryWritten[I] := False;
        VkPool.FSimulatedResults[I] := 0;
        VkPool.FQueryActiveInCmd[I] := False;
        if (FDevice.Handle <> nil) and (VkPool.Handle <> VK_NULL_HANDLE) and Assigned(vkResetQueryPool) then
        begin
          vkResetQueryPool(FDevice.Handle, VkPool.Handle, I, 1);
          VkPool.FQueryResetReady[I] := True;
          DidHostReset := True;
        end else if (FDevice.Handle = nil) then
        begin
          VkPool.FQueryResetReady[I] := True;
          DidHostReset := True;
        end;
      end;
      if DidHostReset then
        Inc(VkPool.FHostResetCount);
    end else
    begin
      for I := FirstQuery to EndExclusive - 1 do
      begin
        VkPool.FQueryWritten[I] := False;
        VkPool.FSimulatedResults[I] := 0;
      end;
    end;
    Exit;
  end;
  for I := FirstQuery to EndExclusive - 1 do
  begin
    VkPool.FQueryWritten[I] := False;
    VkPool.FSimulatedResults[I] := 0;
    VkPool.FQueryResetReady[I] := True;
    VkPool.FQueryRecordedGeneration[I] := 0;
    VkPool.FQueryActiveInCmd[I] := False;
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
  if QueryIndex >= Cardinal(Length(VkPool.FQueryWritten)) then
    Exit;
  if (FHandle <> nil) and Assigned(vkCmdBeginQuery) then
  begin
    if (not VkPool.FQueryResetReady[QueryIndex]) or
       ((FRecordingGeneration <> 0) and
        (VkPool.FQueryRecordedGeneration[QueryIndex] = FRecordingGeneration)) then
      Exit;
    VkPool.FQueryResetReady[QueryIndex] := False;
    VkPool.FQueryRecordedGeneration[QueryIndex] := FRecordingGeneration;
    VkPool.FQueryActiveInCmd[QueryIndex] := True;
    VkPool.FQueryWritten[QueryIndex] := True;
    if VkPool.FSimulatedResults[QueryIndex] = 0 then
      VkPool.FSimulatedResults[QueryIndex] := 128;
    Flags := 0;
    { Per VUID-vkCmdBeginQuery-queryType-00800, VK_QUERY_CONTROL_PRECISE_BIT is only valid
      for VK_QUERY_TYPE_OCCLUSION when occlusionQueryPrecise is enabled on the device. }
    if Precise and (VkPool.Desc.QueryType = qtOcclusion) and
       ((FDevice = nil) or FDevice.SupportsOcclusionQueryPrecise) then
      Flags := VK_QUERY_CONTROL_PRECISE_BIT;
    vkCmdBeginQuery(FHandle, VkPool.Handle, QueryIndex, Flags);
    Exit;
  end;
  VkPool.FQueryWritten[QueryIndex] := True;
  if VkPool.FSimulatedResults[QueryIndex] = 0 then
    VkPool.FSimulatedResults[QueryIndex] := 128;
  VkPool.FQueryActiveInCmd[QueryIndex] := True;
end;

procedure TVulkanRHICommandList.EndQuery(const QueryPool: TRHIQueryPool;
  const QueryIndex: Cardinal);
var
  VkPool: TVulkanRHIQueryPool;
begin
  if QueryPool = nil then Exit;
  VkPool := QueryPool as TVulkanRHIQueryPool;
  if QueryIndex >= Cardinal(Length(VkPool.FQueryWritten)) then
    Exit;
  if (FHandle <> nil) and Assigned(vkCmdEndQuery) then
  begin
    if not VkPool.FQueryActiveInCmd[QueryIndex] then
      Exit;
    VkPool.FQueryActiveInCmd[QueryIndex] := False;
    VkPool.FQueryWritten[QueryIndex] := True;
    vkCmdEndQuery(FHandle, VkPool.Handle, QueryIndex);
    Exit;
  end;
  VkPool.FQueryActiveInCmd[QueryIndex] := False;
  VkPool.FQueryWritten[QueryIndex] := True;
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
    VkPool.FQueryResetReady[QueryIndex] := False;
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
  FCurrentPassHasCommands := True;
  if (FHandle <> nil) and Assigned(vkCmdDraw) then
    vkCmdDraw(FHandle, VertexCount, InstanceCount, FirstVertex, FirstInstance);
end;

procedure TVulkanRHICommandList.DrawIndexed(const IndexCount, InstanceCount,
  FirstIndex: Cardinal; const VertexOffset: Integer; const FirstInstance: Cardinal);
begin
  FCurrentPassHasCommands := True;
  if (FHandle <> nil) and Assigned(vkCmdDrawIndexed) then
    vkCmdDrawIndexed(FHandle, IndexCount, InstanceCount, FirstIndex, VertexOffset, FirstInstance);
end;

procedure TVulkanRHICommandList.DrawIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount, Stride: Cardinal);
var
  EffectiveStride, I: Cardinal;
  VkBuf: VkBuffer;
begin
  if IndirectBuffer = nil then Exit;
  FCurrentPassHasCommands := True;
  Inc(FIndirectDrawCallCount);
  FLastEffectiveIndirectDrawCount := DrawCount;
  if (FHandle <> nil) and Assigned(vkCmdDrawIndirect) and (DrawCount > 0) then
  begin
    VkBuf := (IndirectBuffer as TVulkanRHIBuffer).Handle;
    EffectiveStride := Stride;
    if EffectiveStride = 0 then
      EffectiveStride := SizeOf(TRHIDrawIndirectCommand);
    if (FDevice = nil) or FDevice.Capabilities.SupportsMultiDrawIndirect or (DrawCount = 1) then
      vkCmdDrawIndirect(FHandle, VkBuf, Offset, DrawCount, EffectiveStride)
    else
      { Per VUID-vkCmdDrawIndirect-drawCount-02718, emit single-draw calls when multiDrawIndirect is unsupported }
      for I := 0 to DrawCount - 1 do
        vkCmdDrawIndirect(FHandle, VkBuf,
          Offset + PtrUInt(I) * PtrUInt(EffectiveStride), 1, EffectiveStride);
  end;
end;

procedure TVulkanRHICommandList.DrawIndexedIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount, Stride: Cardinal);
var
  EffectiveStride, I: Cardinal;
  VkBuf: VkBuffer;
begin
  if IndirectBuffer = nil then Exit;
  FCurrentPassHasCommands := True;
  Inc(FIndirectDrawCallCount);
  FLastEffectiveIndirectDrawCount := DrawCount;
  if (FHandle <> nil) and Assigned(vkCmdDrawIndexedIndirect) and (DrawCount > 0) then
  begin
    VkBuf := (IndirectBuffer as TVulkanRHIBuffer).Handle;
    EffectiveStride := Stride;
    if EffectiveStride = 0 then
      EffectiveStride := SizeOf(TRHIDrawIndexedIndirectCommand);
    if (FDevice = nil) or FDevice.Capabilities.SupportsMultiDrawIndirect or (DrawCount = 1) then
      vkCmdDrawIndexedIndirect(FHandle, VkBuf, Offset, DrawCount, EffectiveStride)
    else
      { Per VUID-vkCmdDrawIndexedIndirect-drawCount-02718, emit single-draw calls when multiDrawIndirect is unsupported }
      for I := 0 to DrawCount - 1 do
        vkCmdDrawIndexedIndirect(FHandle, VkBuf,
          Offset + PtrUInt(I) * PtrUInt(EffectiveStride), 1, EffectiveStride);
  end;
end;

procedure TVulkanRHICommandList.DrawIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
var
  EffectiveCount, CpuCount, EffectiveStride, I: Cardinal;
  MappedPtr: Pointer;
  VkBuf: VkBuffer;
begin
  if (IndirectBuffer = nil) or (CountBuffer = nil) then Exit;
  FCurrentPassHasCommands := True;

  EffectiveCount := MaxDrawCount;
  if (CountBuffer.Desc.MemoryUsage in [muCpuToGpu, muGpuToCpu]) and
     (CountBufferOffset + SizeOf(Cardinal) <= CountBuffer.Desc.Size) then
  begin
    MappedPtr := CountBuffer.Map;
    try
      if MappedPtr <> nil then
      begin
        CpuCount := PCardinal(PtrUInt(MappedPtr) + CountBufferOffset)^;
        { In headless mode CountBuffer is CPU-populated; on a real GPU without VK_KHR_draw_indirect_count
          (e.g. Metal / MoltenVK), a zero host value indicates a GPU compute pass will populate
          IndirectBuffer before draw execution with unused trailing slots zeroed. }
        if (FHandle = nil) or (CpuCount > 0) then
          EffectiveCount := Min(MaxDrawCount, CpuCount);
      end;
    finally
      CountBuffer.Unmap;
    end;
  end;

  Inc(FIndirectDrawCallCount);
  Inc(FIndirectCountDrawCallCount);
  FLastEffectiveIndirectDrawCount := EffectiveCount;

  EffectiveStride := Stride;
  if EffectiveStride = 0 then
    EffectiveStride := SizeOf(TRHIDrawIndirectCommand);

  if (FHandle <> nil) and (FDevice <> nil) and
     FDevice.Capabilities.SupportsDrawIndirectCount and Assigned(vkCmdDrawIndirectCount) then
    vkCmdDrawIndirectCount(FHandle,
      (IndirectBuffer as TVulkanRHIBuffer).Handle, Offset,
      (CountBuffer as TVulkanRHIBuffer).Handle, CountBufferOffset,
      MaxDrawCount, EffectiveStride)
  else
  if (FHandle <> nil) and Assigned(vkCmdDrawIndirect) and (EffectiveCount > 0) then
  begin
    VkBuf := (IndirectBuffer as TVulkanRHIBuffer).Handle;
    if (FDevice = nil) or FDevice.Capabilities.SupportsMultiDrawIndirect or (EffectiveCount = 1) then
      vkCmdDrawIndirect(FHandle, VkBuf, Offset, EffectiveCount, EffectiveStride)
    else
      for I := 0 to EffectiveCount - 1 do
        vkCmdDrawIndirect(FHandle, VkBuf,
          Offset + PtrUInt(I) * PtrUInt(EffectiveStride), 1, EffectiveStride);
  end;
end;

procedure TVulkanRHICommandList.DrawIndexedIndirectCount(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const CountBuffer: TRHIBuffer;
  const CountBufferOffset: PtrUInt; const MaxDrawCount, Stride: Cardinal);
var
  EffectiveCount, CpuCount, EffectiveStride, I: Cardinal;
  MappedPtr: Pointer;
  VkBuf: VkBuffer;
begin
  if (IndirectBuffer = nil) or (CountBuffer = nil) then Exit;
  FCurrentPassHasCommands := True;

  EffectiveCount := MaxDrawCount;
  if (CountBuffer.Desc.MemoryUsage in [muCpuToGpu, muGpuToCpu]) and
     (CountBufferOffset + SizeOf(Cardinal) <= CountBuffer.Desc.Size) then
  begin
    MappedPtr := CountBuffer.Map;
    try
      if MappedPtr <> nil then
      begin
        CpuCount := PCardinal(PtrUInt(MappedPtr) + CountBufferOffset)^;
        if (FHandle = nil) or (CpuCount > 0) then
          EffectiveCount := Min(MaxDrawCount, CpuCount);
      end;
    finally
      CountBuffer.Unmap;
    end;
  end;

  Inc(FIndirectDrawCallCount);
  Inc(FIndirectCountDrawCallCount);
  FLastEffectiveIndirectDrawCount := EffectiveCount;

  EffectiveStride := Stride;
  if EffectiveStride = 0 then
    EffectiveStride := SizeOf(TRHIDrawIndexedIndirectCommand);

  if (FHandle <> nil) and (FDevice <> nil) and
     FDevice.Capabilities.SupportsDrawIndirectCount and Assigned(vkCmdDrawIndexedIndirectCount) then
    vkCmdDrawIndexedIndirectCount(FHandle,
      (IndirectBuffer as TVulkanRHIBuffer).Handle, Offset,
      (CountBuffer as TVulkanRHIBuffer).Handle, CountBufferOffset,
      MaxDrawCount, EffectiveStride)
  else
  if (FHandle <> nil) and Assigned(vkCmdDrawIndexedIndirect) and (EffectiveCount > 0) then
  begin
    VkBuf := (IndirectBuffer as TVulkanRHIBuffer).Handle;
    if (FDevice = nil) or FDevice.Capabilities.SupportsMultiDrawIndirect or (EffectiveCount = 1) then
      vkCmdDrawIndexedIndirect(FHandle, VkBuf, Offset, EffectiveCount, EffectiveStride)
    else
      for I := 0 to EffectiveCount - 1 do
        vkCmdDrawIndexedIndirect(FHandle, VkBuf,
          Offset + PtrUInt(I) * PtrUInt(EffectiveStride), 1, EffectiveStride);
  end;
end;

procedure TVulkanRHICommandList.DrawMeshTasks(const GroupCountX: Cardinal;
  const GroupCountY: Cardinal; const GroupCountZ: Cardinal);
begin
  if (GroupCountX = 0) or (GroupCountY = 0) or (GroupCountZ = 0) then Exit;
  FCurrentPassHasCommands := True;
  Inc(FMeshTasksDrawCallCount);
  if (FHandle <> nil) and (FDevice <> nil) and
     FDevice.SupportsMeshShaders and Assigned(vkCmdDrawMeshTasksEXT) then
    vkCmdDrawMeshTasksEXT(FHandle, GroupCountX, GroupCountY, GroupCountZ);
end;

procedure TVulkanRHICommandList.DrawMeshTasksIndirect(const IndirectBuffer: TRHIBuffer;
  const Offset: PtrUInt; const DrawCount: Cardinal; const Stride: Cardinal);
begin
  if (IndirectBuffer = nil) or (DrawCount = 0) then Exit;
  FCurrentPassHasCommands := True;
  Inc(FMeshTasksDrawCallCount);
  Inc(FIndirectDrawCallCount);
  FLastEffectiveIndirectDrawCount := DrawCount;
  if (FHandle <> nil) and (FDevice <> nil) and
     FDevice.SupportsMeshShaders and Assigned(vkCmdDrawMeshTasksIndirectEXT) then
    vkCmdDrawMeshTasksIndirectEXT(FHandle, (IndirectBuffer as TVulkanRHIBuffer).Handle,
      Offset, DrawCount, Stride);
end;

procedure TVulkanRHICommandList.ExecuteCommands(const SecondaryCommandLists: array of TRHICommandList);
var
  CmdBuffers: array of VkCommandBuffer;
  OutCount, I: Integer;
begin
  if Length(SecondaryCommandLists) = 0 then Exit;
  SetLength(CmdBuffers, Length(SecondaryCommandLists));
  OutCount := 0;
  for I := 0 to High(SecondaryCommandLists) do
    if SecondaryCommandLists[I] <> nil then
    begin
      CmdBuffers[OutCount] := (SecondaryCommandLists[I] as TVulkanRHICommandList).Handle;
      Inc(OutCount);
    end;
  if OutCount = 0 then Exit;
  Inc(FSecondaryExecuteCount, Cardinal(OutCount));
  if (FHandle <> nil) and Assigned(vkCmdExecuteCommands) then
    vkCmdExecuteCommands(FHandle, Cardinal(OutCount), @CmdBuffers[0]);
end;

procedure TVulkanRHICommandList.ExecuteSecondaryCommandsInPass(
  const SecondaryCommandLists: array of TRHICommandList);
type
  TVkAttachmentMemBarrier = record
    sType: VkStructureType;
    pNext: Pointer;
    srcAccessMask: VkAccessFlags;
    dstAccessMask: VkAccessFlags;
  end;

  procedure EmitAttachmentContinuationBarrier;
  var
    MemBarrier: TVkAttachmentMemBarrier;
    Stages: VkPipelineStageFlags;
  begin
    Inc(FBarrierCount);
    if (FHandle <> nil) and Assigned(vkCmdPipelineBarrier) then
    begin
      FillChar(MemBarrier, SizeOf(MemBarrier), 0);
      MemBarrier.sType := VK_STRUCTURE_TYPE_MEMORY_BARRIER;
      MemBarrier.srcAccessMask := VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT or
        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
      MemBarrier.dstAccessMask := VK_ACCESS_COLOR_ATTACHMENT_READ_BIT or
        VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT or
        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT or
        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
      Stages := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or
        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or
        VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
      vkCmdPipelineBarrier(FHandle, Stages, Stages, 0, 1, @MemBarrier, 0, nil, 0, nil);
    end;
  end;

var
  SavedInfo, SecInfo, ResumeInfo: TRHIRenderingInfo;
  SavedVp: TFloatRectangle;
  SavedMinD, SavedMaxD: Single;
  SavedScissor: TRectangle;
  I: Integer;
begin
  if Length(SecondaryCommandLists) = 0 then
    Exit;
  FCurrentPassHasCommands := True;

  if FIsRendering and (not FActiveRenderingInfo.ContentsSecondaryCommandBuffers) then
  begin
    SavedInfo := FActiveRenderingInfo;
    SavedInfo.ColorAttachments := Copy(FActiveRenderingInfo.ColorAttachments);
    SavedVp := FDynamicViewportRect;
    SavedMinD := FDynamicMinDepth;
    SavedMaxD := FDynamicMaxDepth;
    SavedScissor := FDynamicScissorRect;

    EndRendering;
    EmitAttachmentContinuationBarrier;

    SecInfo := SavedInfo;
    SecInfo.ColorAttachments := Copy(SavedInfo.ColorAttachments);
    for I := 0 to High(SecInfo.ColorAttachments) do
    begin
      SecInfo.ColorAttachments[I].LoadOp := loLoad;
      SecInfo.ColorAttachments[I].StoreOp := soStore;
      SecInfo.ColorAttachments[I].ResolveTexture := nil;
      SecInfo.ColorAttachments[I].ResolveMode := rmNone;
    end;
    if SecInfo.HasDepthAttachment then
    begin
      SecInfo.DepthAttachment.LoadOp := loLoad;
      SecInfo.DepthAttachment.StoreOp := soStore;
      SecInfo.DepthAttachment.ResolveTexture := nil;
      SecInfo.DepthAttachment.ResolveMode := rmNone;
    end;
    SecInfo.ContentsSecondaryCommandBuffers := True;

    BeginRendering(SecInfo);
    ExecuteCommands(SecondaryCommandLists);
    EndRendering;
    EmitAttachmentContinuationBarrier;

    ResumeInfo := SavedInfo;
    ResumeInfo.ColorAttachments := Copy(SavedInfo.ColorAttachments);
    for I := 0 to High(ResumeInfo.ColorAttachments) do
      ResumeInfo.ColorAttachments[I].LoadOp := loLoad;
    if ResumeInfo.HasDepthAttachment then
      ResumeInfo.DepthAttachment.LoadOp := loLoad;
    ResumeInfo.ContentsSecondaryCommandBuffers := False;

    BeginRendering(ResumeInfo);
    SetViewport(SavedVp, SavedMinD, SavedMaxD);
    SetScissor(SavedScissor);
  end else
    ExecuteCommands(SecondaryCommandLists);
end;

procedure TVulkanRHICommandList.PushDebugGroup(const LabelName: String; const Color: TCastleColor);
var
  LabelInfo: VkDebugUtilsLabelEXT;
  AnsiLabel: AnsiString;
begin
  Inc(FDebugGroupPushCount);
  FLastDebugLabelName := LabelName;
  if (FDevice <> nil) and FDevice.DebugUtilsActive and
     Assigned(vkCmdBeginDebugUtilsLabelEXT) and (FHandle <> nil) then
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
  Inc(FDebugGroupPopCount);
  if (FDevice <> nil) and FDevice.DebugUtilsActive and
     Assigned(vkCmdEndDebugUtilsLabelEXT) and (FHandle <> nil) then
    vkCmdEndDebugUtilsLabelEXT(FHandle);
end;

procedure TVulkanRHICommandList.InsertDebugMarker(const LabelName: String; const Color: TCastleColor);
var
  LabelInfo: VkDebugUtilsLabelEXT;
  AnsiLabel: AnsiString;
begin
  Inc(FDebugMarkerCount);
  FLastDebugLabelName := LabelName;
  if (FDevice <> nil) and FDevice.DebugUtilsActive and
     Assigned(vkCmdInsertDebugUtilsLabelEXT) and (FHandle <> nil) then
  begin
    AnsiLabel := AnsiString(LabelName);
    FillChar(LabelInfo, SizeOf(LabelInfo), 0);
    LabelInfo.sType := VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT;
    LabelInfo.pLabelName := PAnsiChar(AnsiLabel);
    Move(Color.Data, LabelInfo.color, SizeOf(Single) * 4);
    vkCmdInsertDebugUtilsLabelEXT(FHandle, @LabelInfo);
  end;
end;

{$endif read_implementation}
