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
function TVulkanRHIDevice.BeginFrame: TRHICommandList;
var
  Frame: TVulkanFrameContext;
  AcquireRes: VkResult;
begin
  Inc(FTotalFramesStarted);
  if FFrames[FFrameIndex].CommandList = nil then
    FFrames[FFrameIndex].CommandList := TVulkanRHICommandList.Create(Self, FGraphicsQueueFamily);
  if FFrames[FFrameIndex].TransientDescriptorAllocator = nil then
    FFrames[FFrameIndex].TransientDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(
      FDevice, 512, False, 4096, NeedsUpdateAfterBindSamplerLayouts, FSupportsAccelerationStructure);

  Frame := FFrames[FFrameIndex];

  { 1. Wait for the GPU to finish executing the previous frame occupying this slot }
  if (FDevice <> nil) and (Frame.InFlightFence <> VK_NULL_HANDLE) and Assigned(vkWaitForFences) then
    CheckVk(vkWaitForFences(FDevice, 1, @Frame.InFlightFence, VK_TRUE, High(UInt64)), 'vkWaitForFences');

  { Retire any VkBuffers/VkImages/VkDescriptorSets/TVulkanMemoryAllocations destroyed while this slot was in flight }
  FlushDeferredDeletions(FFrameIndex);
  if FMemoryAllocator <> nil then
    FMemoryAllocator.GetFrameRingBuffer(FFrameIndex).Reset;
  if FStagingUploader <> nil then
    FStagingUploader.ReclaimFrameSlot(FFrameIndex);
  if FWorkerCommandPoolManager <> nil then
    FWorkerCommandPoolManager.ResetFrameSlot(FFrameIndex);
  if Frame.TransientDescriptorAllocator <> nil then
    Frame.TransientDescriptorAllocator.ResetPools;
  FDeferResourceDestruction := True;

  if FSwapchainMinimized then
  begin
    if (FSurface <> VK_NULL_HANDLE) and (FDevice <> nil) and (FSwapchain = VK_NULL_HANDLE) then
      CreateSwapchain(Max(Cardinal(1), FRequestedSwapchainWidth), Max(Cardinal(1), FRequestedSwapchainHeight));
    if FSwapchainMinimized then
    begin
      FDeferResourceDestruction := False;
      Exit(nil);
    end;
  end;

  if Length(FSwapchainColorTextures) > 0 then
  begin
    FActiveColorTarget := nil;
    FActiveDepthTarget := nil;
  end;

  { 2. Acquire next swapchain image when bound to a native swapchain (or cycle simulated swapchain) }
  if (FDevice <> nil) and (FSwapchain <> VK_NULL_HANDLE) and Assigned(vkAcquireNextImageKHR) then
  begin
    AcquireRes := vkAcquireNextImageKHR(FDevice, FSwapchain, High(UInt64),
      Frame.ImageAvailableSemaphore, VK_NULL_HANDLE, @FCurrentSwapchainImageIndex);

    if AcquireRes = VK_ERROR_OUT_OF_DATE_KHR then
    begin
      Inc(FSwapchainRecreateCount);
      ResizeSwapchain(
        Max(Cardinal(1), Max(FRequestedSwapchainWidth, FSwapchainExtent.width)),
        Max(Cardinal(1), Max(FRequestedSwapchainHeight, FSwapchainExtent.height)));
      if FSwapchainMinimized or (FSwapchain = VK_NULL_HANDLE) then
      begin
        FDeferResourceDestruction := False;
        Exit(nil);
      end;
      { Per Vulkan spec, when vkAcquireNextImageKHR returns VK_ERROR_OUT_OF_DATE_KHR,
        ImageAvailableSemaphore was not signaled and is safe to reuse on retry. }
      AcquireRes := vkAcquireNextImageKHR(FDevice, FSwapchain, High(UInt64),
        Frame.ImageAvailableSemaphore, VK_NULL_HANDLE, @FCurrentSwapchainImageIndex);
    end;

    if AcquireRes = VK_SUBOPTIMAL_KHR then
      FSwapchainSuboptimal := True
    else if AcquireRes <> VK_SUCCESS then
    begin
      FDeferResourceDestruction := False;
      Exit(nil);
    end;
  end else
  if Length(FSwapchainColorTextures) > 0 then
    FCurrentSwapchainImageIndex := FTotalFramesPresented mod Cardinal(Length(FSwapchainColorTextures));

  if (FDevice <> nil) and (Frame.InFlightFence <> VK_NULL_HANDLE) and Assigned(vkResetFences) then
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
  TimelineSubmit: VkTimelineSemaphoreSubmitInfo;
  WaitSems: array[0..1] of VkSemaphore;
  WaitStages: array[0..1] of VkPipelineStageFlags;
  WaitValues: array[0..1] of UInt64;
  SignalValueZero: UInt64;
  WaitCount: Cardinal;
  HasAsyncWait: Boolean;
  AsyncTimelineSem, AsyncBinarySem: VkSemaphore;
  AsyncWaitValue: UInt64;
  PresentInfo: VkPresentInfoKHR;
  PresentRes: VkResult;
  CmdHandle: VkCommandBuffer;
  SignalSem: VkSemaphore;
begin
  Frame := FFrames[FFrameIndex];
  if (Frame.CommandList <> nil) and Frame.CommandList.IsRendering then
    Frame.CommandList.EndRendering;

  SetActiveCommandList(nil);
  if Frame.CommandList = nil then
    Exit;

  if FStagingUploader <> nil then
    FStagingUploader.FlushPendingUploads(Frame.CommandList);
  if FBindlessTextureManager <> nil then
    FBindlessTextureManager.FlushPendingUpdates;

  { Ensure active swapchain backbuffer is transitioned to VK_IMAGE_LAYOUT_PRESENT_SRC_KHR }
  if (FCurrentSwapchainImageIndex < Cardinal(Length(FSwapchainColorTextures))) and
     (FSwapchainColorTextures[FCurrentSwapchainImageIndex] <> nil) and
     ((FSwapchain <> VK_NULL_HANDLE) or (FDevice = nil)) then
  begin
    CaptureSwapchainReadbackShadowBeforePresent(
      Frame.CommandList, FSwapchainColorTextures[FCurrentSwapchainImageIndex]);
    Frame.CommandList.TransitionTexture(FSwapchainColorTextures[FCurrentSwapchainImageIndex], rsPresent);
  end;
  Frame.CommandList.EndRecording;

  HasAsyncWait := (FStagingUploader <> nil) and
    FStagingUploader.ConsumePendingGraphicsWait(AsyncTimelineSem, AsyncWaitValue, AsyncBinarySem);

  if (FDevice <> nil) and (FSwapchain <> VK_NULL_HANDLE) and Assigned(vkQueueSubmit) then
  begin
    WaitSems[0] := Frame.ImageAvailableSemaphore;
    WaitStages[0] := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or VK_PIPELINE_STAGE_TRANSFER_BIT;
    WaitValues[0] := 0;
    WaitCount := 1;
    SignalValueZero := 0;

    FillChar(TimelineSubmit, SizeOf(TimelineSubmit), 0);
    TimelineSubmit.sType := VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO;

    if HasAsyncWait then
    begin
      if (AsyncTimelineSem <> VK_NULL_HANDLE) and FSupportsTimelineSemaphores then
      begin
        WaitSems[1] := AsyncTimelineSem;
        WaitStages[1] :=
          VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
          VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or
          VK_PIPELINE_STAGE_TRANSFER_BIT;
        WaitValues[1] := AsyncWaitValue;
        WaitCount := 2;
        TimelineSubmit.waitSemaphoreValueCount := 2;
        TimelineSubmit.pWaitSemaphoreValues := @WaitValues[0];
        TimelineSubmit.signalSemaphoreValueCount := 1;
        TimelineSubmit.pSignalSemaphoreValues := @SignalValueZero;
      end else if AsyncBinarySem <> VK_NULL_HANDLE then
      begin
        WaitSems[1] := AsyncBinarySem;
        WaitStages[1] :=
          VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
          VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or
          VK_PIPELINE_STAGE_TRANSFER_BIT;
        WaitCount := 2;
      end;
    end;

    CmdHandle := Frame.CommandList.Handle;
    { Index RenderFinishedSemaphore by acquired swapchain image index (not frame-in-flight slot)
      per VUID-vkQueueSubmit-pSignalSemaphores-00067 when SwapchainImageCount > MaxFramesInFlight. }
    if (FCurrentSwapchainImageIndex < Cardinal(Length(FSwapchainRenderFinishedSemaphores))) and
       (FSwapchainRenderFinishedSemaphores[FCurrentSwapchainImageIndex] <> VK_NULL_HANDLE) then
      SignalSem := FSwapchainRenderFinishedSemaphores[FCurrentSwapchainImageIndex]
    else
      SignalSem := Frame.RenderFinishedSemaphore;

    FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
    SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
    if TimelineSubmit.waitSemaphoreValueCount > 0 then
      SubmitInfo.pNext := @TimelineSubmit;
    SubmitInfo.waitSemaphoreCount := WaitCount;
    SubmitInfo.pWaitSemaphores := @WaitSems[0];
    SubmitInfo.pWaitDstStageMask := @WaitStages[0];
    SubmitInfo.commandBufferCount := 1;
    SubmitInfo.pCommandBuffers := @CmdHandle;
    SubmitInfo.signalSemaphoreCount := 1;
    SubmitInfo.pSignalSemaphores := @SignalSem;

    CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, Frame.InFlightFence), 'vkQueueSubmit');

    if Assigned(vkQueuePresentKHR) then
    begin
      FillChar(PresentInfo, SizeOf(PresentInfo), 0);
      PresentInfo.sType := VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
      PresentInfo.waitSemaphoreCount := 1;
      PresentInfo.pWaitSemaphores := @SignalSem;
      PresentInfo.swapchainCount := 1;
      PresentInfo.pSwapchains := @FSwapchain;
      PresentInfo.pImageIndices := @FCurrentSwapchainImageIndex;

      PresentRes := vkQueuePresentKHR(FPresentQueue, @PresentInfo);
      if (PresentRes = VK_ERROR_OUT_OF_DATE_KHR) or (PresentRes = VK_SUBOPTIMAL_KHR) or
         FSwapchainSuboptimal then
      begin
        FSwapchainSuboptimal := False;
        Inc(FSwapchainRecreateCount);
        ResizeSwapchain(
          Max(Cardinal(1), Max(FRequestedSwapchainWidth, FSwapchainExtent.width)),
          Max(Cardinal(1), Max(FRequestedSwapchainHeight, FSwapchainExtent.height)));
      end else
        CheckVk(PresentRes, 'vkQueuePresentKHR');
    end;
  end else
  if (FDevice <> nil) and (FSwapchain = VK_NULL_HANDLE) and Assigned(vkQueueSubmit) then
  begin
    CmdHandle := Frame.CommandList.Handle;
    FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
    SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
    FillChar(TimelineSubmit, SizeOf(TimelineSubmit), 0);
    TimelineSubmit.sType := VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO;
    if HasAsyncWait then
    begin
      WaitStages[0] :=
        VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
        VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or
        VK_PIPELINE_STAGE_TRANSFER_BIT;
      if (AsyncTimelineSem <> VK_NULL_HANDLE) and FSupportsTimelineSemaphores then
      begin
        WaitSems[0] := AsyncTimelineSem;
        WaitValues[0] := AsyncWaitValue;
        TimelineSubmit.waitSemaphoreValueCount := 1;
        TimelineSubmit.pWaitSemaphoreValues := @WaitValues[0];
        SubmitInfo.pNext := @TimelineSubmit;
        SubmitInfo.waitSemaphoreCount := 1;
        SubmitInfo.pWaitSemaphores := @WaitSems[0];
        SubmitInfo.pWaitDstStageMask := @WaitStages[0];
      end else if AsyncBinarySem <> VK_NULL_HANDLE then
      begin
        WaitSems[0] := AsyncBinarySem;
        SubmitInfo.waitSemaphoreCount := 1;
        SubmitInfo.pWaitSemaphores := @WaitSems[0];
        SubmitInfo.pWaitDstStageMask := @WaitStages[0];
      end;
    end;
    SubmitInfo.commandBufferCount := 1;
    SubmitInfo.pCommandBuffers := @CmdHandle;
    CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, Frame.InFlightFence), 'vkQueueSubmit(Offscreen)');
  end;

  FFrameIndex := (FFrameIndex + 1) mod MaxFramesInFlight;
  Inc(FTotalFramesPresented);
end;

function TVulkanRHIDevice.BeginOffscreenFrame: TRHICommandList;
var
  Frame: TVulkanFrameContext;
begin
  Inc(FTotalFramesStarted);
  if FFrames[FFrameIndex].CommandList = nil then
    FFrames[FFrameIndex].CommandList := TVulkanRHICommandList.Create(Self, FGraphicsQueueFamily);
  if FFrames[FFrameIndex].TransientDescriptorAllocator = nil then
    FFrames[FFrameIndex].TransientDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(
      FDevice, 512, False, 4096, NeedsUpdateAfterBindSamplerLayouts, FSupportsAccelerationStructure);

  Frame := FFrames[FFrameIndex];

  if (FDevice <> nil) and (Frame.InFlightFence <> VK_NULL_HANDLE) and Assigned(vkWaitForFences) then
    CheckVk(vkWaitForFences(FDevice, 1, @Frame.InFlightFence, VK_TRUE, High(UInt64)), 'vkWaitForFences(Offscreen)');

  FlushDeferredDeletions(FFrameIndex);
  if FMemoryAllocator <> nil then
    FMemoryAllocator.GetFrameRingBuffer(FFrameIndex).Reset;
  if FStagingUploader <> nil then
    FStagingUploader.ReclaimFrameSlot(FFrameIndex);
  if FWorkerCommandPoolManager <> nil then
    FWorkerCommandPoolManager.ResetFrameSlot(FFrameIndex);
  if Frame.TransientDescriptorAllocator <> nil then
    Frame.TransientDescriptorAllocator.ResetPools;
  FDeferResourceDestruction := True;

  if (FDevice <> nil) and (Frame.InFlightFence <> VK_NULL_HANDLE) and Assigned(vkResetFences) then
    CheckVk(vkResetFences(FDevice, 1, @Frame.InFlightFence), 'vkResetFences(Offscreen)');

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

procedure TVulkanRHIDevice.EndOffscreenFrame;
var
  Frame: TVulkanFrameContext;
  SubmitInfo: VkSubmitInfo;
  TimelineSubmit: VkTimelineSemaphoreSubmitInfo;
  WaitSem: VkSemaphore;
  WaitStage: VkPipelineStageFlags;
  HasAsyncWait: Boolean;
  AsyncTimelineSem, AsyncBinarySem: VkSemaphore;
  AsyncWaitValue: UInt64;
  CmdHandle: VkCommandBuffer;
begin
  Frame := FFrames[FFrameIndex];
  if (Frame.CommandList <> nil) and Frame.CommandList.IsRendering then
    Frame.CommandList.EndRendering;

  SetActiveCommandList(nil);
  if Frame.CommandList = nil then
    Exit;

  if FStagingUploader <> nil then
    FStagingUploader.FlushPendingUploads(Frame.CommandList);
  if FBindlessTextureManager <> nil then
    FBindlessTextureManager.FlushPendingUpdates;

  Frame.CommandList.EndRecording;

  HasAsyncWait := (FStagingUploader <> nil) and
    FStagingUploader.ConsumePendingGraphicsWait(AsyncTimelineSem, AsyncWaitValue, AsyncBinarySem);

  if (FDevice <> nil) and Assigned(vkQueueSubmit) then
  begin
    CmdHandle := Frame.CommandList.Handle;
    FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
    SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
    FillChar(TimelineSubmit, SizeOf(TimelineSubmit), 0);
    TimelineSubmit.sType := VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO;
    if HasAsyncWait then
    begin
      WaitStage :=
        VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
        VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or
        VK_PIPELINE_STAGE_TRANSFER_BIT;
      if (AsyncTimelineSem <> VK_NULL_HANDLE) and FSupportsTimelineSemaphores then
      begin
        WaitSem := AsyncTimelineSem;
        TimelineSubmit.waitSemaphoreValueCount := 1;
        TimelineSubmit.pWaitSemaphoreValues := @AsyncWaitValue;
        SubmitInfo.pNext := @TimelineSubmit;
        SubmitInfo.waitSemaphoreCount := 1;
        SubmitInfo.pWaitSemaphores := @WaitSem;
        SubmitInfo.pWaitDstStageMask := @WaitStage;
      end else if AsyncBinarySem <> VK_NULL_HANDLE then
      begin
        WaitSem := AsyncBinarySem;
        SubmitInfo.waitSemaphoreCount := 1;
        SubmitInfo.pWaitSemaphores := @WaitSem;
        SubmitInfo.pWaitDstStageMask := @WaitStage;
      end;
    end;
    SubmitInfo.commandBufferCount := 1;
    SubmitInfo.pCommandBuffers := @CmdHandle;
    CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, Frame.InFlightFence), 'vkQueueSubmit(OffscreenFrame)');
  end;

  FFrameIndex := (FFrameIndex + 1) mod MaxFramesInFlight;
end;

procedure TVulkanRHIDevice.ResizeSwapchain(const NewWidth, NewHeight: Cardinal);
var
  SimCount: Cardinal;
begin
  if (FSurface = VK_NULL_HANDLE) and (Length(FSwapchainColorTextures) = 0) and
     (FActiveSwapchainSurface <> nil) then
  begin
    FActiveSwapchainSurface.Resize(NewWidth, NewHeight);
    Exit;
  end;
  if (NewWidth = 0) or (NewHeight = 0) then
  begin
    FSwapchainMinimized := True;
    Exit;
  end;
  FRequestedSwapchainWidth := NewWidth;
  FRequestedSwapchainHeight := NewHeight;
  FSwapchainMinimized := False;
  WaitIdle;
  if (FSurface = VK_NULL_HANDLE) and (Length(FSwapchainColorTextures) > 0) then
  begin
    SimCount := Cardinal(Length(FSwapchainColorTextures));
    SimulateSwapchainForTesting(NewWidth, NewHeight, SimCount, FSwapchainFormat, FSwapchainDepthFormat);
  end else
  if FSurface <> VK_NULL_HANDLE then
  begin
    { CreateSwapchain retires the existing FSwapchain via CreateInfo.oldSwapchain handoff }
    CreateSwapchain(NewWidth, NewHeight);
  end else
  begin
    DestroySwapchain;
    FSwapchainExtent.width := NewWidth;
    FSwapchainExtent.height := NewHeight;
    if FSampleCount > 1 then
    begin
      if FSwapchainDepthFormat <> pfUndefined then
        EnsureMSAATargets(NewWidth, NewHeight, FSwapchainFormat, FSwapchainDepthFormat)
      else
        EnsureMSAATargets(NewWidth, NewHeight, FSwapchainFormat, pfD24_UNorm_S8_UInt);
    end;
  end;
end;

function TVulkanRHIDevice.GetSwapchainSurfaceCount: Cardinal;
begin
  if FSwapchainSurfaces <> nil then
    Result := Cardinal(FSwapchainSurfaces.Count)
  else
    Result := 0;
end;

function TVulkanRHIDevice.GetSwapchainSurface(const AIndex: Integer): TCastleVulkanSwapchainSurface;
begin
  if (FSwapchainSurfaces <> nil) and (AIndex >= 0) and (AIndex < FSwapchainSurfaces.Count) then
    Result := FSwapchainSurfaces[AIndex]
  else
    Result := nil;
end;

function TVulkanRHIDevice.CreateSwapchainSurface(
  const ACreateSurfaceCallback: TVulkanCreateSurfaceEvent;
  const InitialWidth, InitialHeight: Cardinal;
  const ADebugName: String): TCastleVulkanSwapchainSurface;
begin
  if FSwapchainSurfaces = nil then
    FSwapchainSurfaces := TVulkanSwapchainSurfaceList.Create(True);
  Result := TCastleVulkanSwapchainSurface.Create(
    Self, ACreateSurfaceCallback, InitialWidth, InitialHeight, ADebugName);
  FSwapchainSurfaces.Add(Result);
  FActiveSwapchainSurface := Result;
end;

function TVulkanRHIDevice.CreateSwapchainSurface(
  const ANativeDesc: TVulkanNativeSurfaceDesc;
  const InitialWidth, InitialHeight: Cardinal;
  const ADebugName: String): TCastleVulkanSwapchainSurface;
begin
  if FSwapchainSurfaces = nil then
    FSwapchainSurfaces := TVulkanSwapchainSurfaceList.Create(True);
  Result := TCastleVulkanSwapchainSurface.Create(
    Self, ANativeDesc, InitialWidth, InitialHeight, ADebugName);
  FSwapchainSurfaces.Add(Result);
  FActiveSwapchainSurface := Result;
end;

function TVulkanRHIDevice.CreateSimulatedSwapchainSurface(
  const AWidth, AHeight: Cardinal;
  const AImageCount: Cardinal;
  const AColorFormat, ADepthFormat: TRHIPixelFormat;
  const ADebugName: String): TCastleVulkanSwapchainSurface;
begin
  if FSwapchainSurfaces = nil then
    FSwapchainSurfaces := TVulkanSwapchainSurfaceList.Create(True);
  Result := TCastleVulkanSwapchainSurface.CreateSimulatedForTesting(
    Self, AWidth, AHeight, AImageCount, AColorFormat, ADepthFormat, ADebugName);
  FSwapchainSurfaces.Add(Result);
  FActiveSwapchainSurface := Result;
end;

procedure TVulkanRHIDevice.DestroySwapchainSurface(var ASurface: TCastleVulkanSwapchainSurface);
begin
  if ASurface = nil then
    Exit;
  WaitIdle;
  if FActiveSwapchainSurface = ASurface then
    FActiveSwapchainSurface := nil;
  if (FSwapchainSurfaces <> nil) and (FSwapchainSurfaces.IndexOf(ASurface) >= 0) then
  begin
    { FSwapchainSurfaces owns items (OwnsObjects = True), so Remove frees ASurface }
    FSwapchainSurfaces.Remove(ASurface);
    ASurface := nil;
  end else
    FreeAndNil(ASurface);
  if (FActiveSwapchainSurface = nil) and (FSwapchainSurfaces <> nil) and
     (FSwapchainSurfaces.Count > 0) then
    FActiveSwapchainSurface := FSwapchainSurfaces[FSwapchainSurfaces.Count - 1];
end;

function TVulkanRHIDevice.BeginSurfaceFrame(
  const ASurface: TCastleVulkanSwapchainSurface): TRHICommandList;
var
  Frame: TVulkanFrameContext;
  AcquireSem: VkSemaphore;
  AcquireRes: VkResult;
  SurfIdx, ImgIdx: Integer;
  Surf: TCastleVulkanSwapchainSurface;
  PriorFence: VkFence;
begin
  if ASurface = nil then
    Exit(nil);

  FActiveSwapchainSurface := ASurface;
  Inc(FTotalFramesStarted);
  if FFrames[FFrameIndex].CommandList = nil then
    FFrames[FFrameIndex].CommandList := TVulkanRHICommandList.Create(Self, FGraphicsQueueFamily);
  if FFrames[FFrameIndex].TransientDescriptorAllocator = nil then
    FFrames[FFrameIndex].TransientDescriptorAllocator := TVulkanDescriptorPoolAllocator.Create(
      FDevice, 512, False, 4096, NeedsUpdateAfterBindSamplerLayouts, FSupportsAccelerationStructure);

  Frame := FFrames[FFrameIndex];

  if (FDevice <> nil) and (Frame.InFlightFence <> VK_NULL_HANDLE) and Assigned(vkWaitForFences) then
  begin
    CheckVk(vkWaitForFences(FDevice, 1, @Frame.InFlightFence, VK_TRUE, High(UInt64)),
      'vkWaitForFences(SurfaceFrame)');
    if FSwapchainSurfaces <> nil then
      for SurfIdx := 0 to FSwapchainSurfaces.Count - 1 do
      begin
        Surf := FSwapchainSurfaces[SurfIdx];
        for ImgIdx := 0 to High(Surf.FImageInFlightFences) do
          if Surf.FImageInFlightFences[ImgIdx] = Frame.InFlightFence then
            Surf.FImageInFlightFences[ImgIdx] := VK_NULL_HANDLE;
      end;
  end;

  FlushDeferredDeletions(FFrameIndex);
  if FMemoryAllocator <> nil then
    FMemoryAllocator.GetFrameRingBuffer(FFrameIndex).Reset;
  if FStagingUploader <> nil then
    FStagingUploader.ReclaimFrameSlot(FFrameIndex);
  if FWorkerCommandPoolManager <> nil then
    FWorkerCommandPoolManager.ResetFrameSlot(FFrameIndex);
  if Frame.TransientDescriptorAllocator <> nil then
    Frame.TransientDescriptorAllocator.ResetPools;
  FDeferResourceDestruction := True;

  if ASurface.FSwapchainMinimized then
  begin
    if (ASurface.FSurface <> VK_NULL_HANDLE) and (FDevice <> nil) and (ASurface.FSwapchain = VK_NULL_HANDLE) then
      ASurface.CreateSwapchain(
        Max(Cardinal(1), ASurface.FRequestedWidth),
        Max(Cardinal(1), ASurface.FRequestedHeight));
    if ASurface.FSwapchainMinimized then
    begin
      FDeferResourceDestruction := False;
      Exit(nil);
    end;
  end;

  if Length(ASurface.FColorTextures) > 0 then
  begin
    FActiveColorTarget := nil;
    FActiveDepthTarget := nil;
  end;

  AcquireSem := ASurface.FImageAvailableSemaphores[FFrameIndex];
  if AcquireSem = VK_NULL_HANDLE then
    AcquireSem := Frame.ImageAvailableSemaphore;

  if (FDevice <> nil) and (ASurface.FSwapchain <> VK_NULL_HANDLE) and Assigned(vkAcquireNextImageKHR) then
  begin
    AcquireRes := vkAcquireNextImageKHR(FDevice, ASurface.FSwapchain, High(UInt64),
      AcquireSem, VK_NULL_HANDLE, @ASurface.FCurrentImageIndex);

    if AcquireRes = VK_ERROR_OUT_OF_DATE_KHR then
    begin
      ASurface.Resize(
        Max(Cardinal(1), Max(ASurface.FRequestedWidth, ASurface.FSwapchainExtent.width)),
        Max(Cardinal(1), Max(ASurface.FRequestedHeight, ASurface.FSwapchainExtent.height)));
      if ASurface.FSwapchainMinimized or (ASurface.FSwapchain = VK_NULL_HANDLE) then
      begin
        FDeferResourceDestruction := False;
        Exit(nil);
      end;
      AcquireRes := vkAcquireNextImageKHR(FDevice, ASurface.FSwapchain, High(UInt64),
        AcquireSem, VK_NULL_HANDLE, @ASurface.FCurrentImageIndex);
    end;

    if AcquireRes = VK_SUBOPTIMAL_KHR then
      ASurface.FSwapchainSuboptimal := True
    else if AcquireRes <> VK_SUCCESS then
    begin
      FDeferResourceDestruction := False;
      Exit(nil);
    end;

    if ASurface.FCurrentImageIndex < Cardinal(Length(ASurface.FImageInFlightFences)) then
    begin
      PriorFence := ASurface.FImageInFlightFences[ASurface.FCurrentImageIndex];
      if (PriorFence <> VK_NULL_HANDLE) and (PriorFence <> Frame.InFlightFence) and
         Assigned(vkWaitForFences) then
        CheckVk(vkWaitForFences(FDevice, 1, @PriorFence, VK_TRUE, High(UInt64)),
          'vkWaitForFences(SurfaceImageInFlight)');
      ASurface.FImageInFlightFences[ASurface.FCurrentImageIndex] := Frame.InFlightFence;
    end;
  end else
  if Length(ASurface.FColorTextures) > 0 then
    ASurface.FCurrentImageIndex := ASurface.FFramesPresentedCount mod Cardinal(Length(ASurface.FColorTextures));

  if (FDevice <> nil) and (Frame.InFlightFence <> VK_NULL_HANDLE) and Assigned(vkResetFences) then
    CheckVk(vkResetFences(FDevice, 1, @Frame.InFlightFence), 'vkResetFences(SurfaceFrame)');

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

procedure TVulkanRHIDevice.EndSurfaceFrameAndPresent(
  const ASurface: TCastleVulkanSwapchainSurface);
var
  Frame: TVulkanFrameContext;
  SubmitInfo: VkSubmitInfo;
  TimelineSubmit: VkTimelineSemaphoreSubmitInfo;
  WaitSems: array[0..1] of VkSemaphore;
  WaitStages: array[0..1] of VkPipelineStageFlags;
  WaitValues: array[0..1] of UInt64;
  SignalValueZero: UInt64;
  WaitCount: Cardinal;
  HasAsyncWait: Boolean;
  AsyncTimelineSem, AsyncBinarySem: VkSemaphore;
  AsyncWaitValue: UInt64;
  PresentInfo: VkPresentInfoKHR;
  PresentRes: VkResult;
  CmdHandle: VkCommandBuffer;
  AcquireSem, SignalSem: VkSemaphore;
  CurColorTex: TVulkanRHITexture;
begin
  if ASurface = nil then
    Exit;

  FActiveSwapchainSurface := ASurface;
  Frame := FFrames[FFrameIndex];
  if (Frame.CommandList <> nil) and Frame.CommandList.IsRendering then
    Frame.CommandList.EndRendering;

  SetActiveCommandList(nil);
  if Frame.CommandList = nil then
    Exit;

  if FStagingUploader <> nil then
    FStagingUploader.FlushPendingUploads(Frame.CommandList);
  if FBindlessTextureManager <> nil then
    FBindlessTextureManager.FlushPendingUpdates;

  CurColorTex := ASurface.GetCurrentColorTexture;
  if (CurColorTex <> nil) and ((ASurface.FSwapchain <> VK_NULL_HANDLE) or (FDevice = nil)) then
  begin
    CaptureSwapchainReadbackShadowBeforePresent(Frame.CommandList, CurColorTex);
    Frame.CommandList.TransitionTexture(CurColorTex, rsPresent);
  end;
  Frame.CommandList.EndRecording;

  HasAsyncWait := (FStagingUploader <> nil) and
    FStagingUploader.ConsumePendingGraphicsWait(AsyncTimelineSem, AsyncWaitValue, AsyncBinarySem);

  if (FDevice <> nil) and (ASurface.FSwapchain <> VK_NULL_HANDLE) and Assigned(vkQueueSubmit) then
  begin
    AcquireSem := ASurface.FImageAvailableSemaphores[FFrameIndex];
    if AcquireSem = VK_NULL_HANDLE then
      AcquireSem := Frame.ImageAvailableSemaphore;
    WaitSems[0] := AcquireSem;
    WaitStages[0] := VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT or VK_PIPELINE_STAGE_TRANSFER_BIT;
    WaitValues[0] := 0;
    WaitCount := 1;
    SignalValueZero := 0;

    FillChar(TimelineSubmit, SizeOf(TimelineSubmit), 0);
    TimelineSubmit.sType := VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO;

    if HasAsyncWait then
    begin
      if (AsyncTimelineSem <> VK_NULL_HANDLE) and FSupportsTimelineSemaphores then
      begin
        WaitSems[1] := AsyncTimelineSem;
        WaitStages[1] :=
          VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
          VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or
          VK_PIPELINE_STAGE_TRANSFER_BIT;
        WaitValues[1] := AsyncWaitValue;
        WaitCount := 2;
        TimelineSubmit.waitSemaphoreValueCount := 2;
        TimelineSubmit.pWaitSemaphoreValues := @WaitValues[0];
        TimelineSubmit.signalSemaphoreValueCount := 1;
        TimelineSubmit.pSignalSemaphoreValues := @SignalValueZero;
      end else if AsyncBinarySem <> VK_NULL_HANDLE then
      begin
        WaitSems[1] := AsyncBinarySem;
        WaitStages[1] :=
          VK_PIPELINE_STAGE_VERTEX_INPUT_BIT or
          VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
          VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or
          VK_PIPELINE_STAGE_TRANSFER_BIT;
        WaitCount := 2;
      end;
    end;

    CmdHandle := Frame.CommandList.Handle;
    if (ASurface.FCurrentImageIndex < Cardinal(Length(ASurface.FRenderFinishedSemaphores))) and
       (ASurface.FRenderFinishedSemaphores[ASurface.FCurrentImageIndex] <> VK_NULL_HANDLE) then
      SignalSem := ASurface.FRenderFinishedSemaphores[ASurface.FCurrentImageIndex]
    else
      SignalSem := Frame.RenderFinishedSemaphore;

    FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
    SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
    if TimelineSubmit.waitSemaphoreValueCount > 0 then
      SubmitInfo.pNext := @TimelineSubmit;
    SubmitInfo.waitSemaphoreCount := WaitCount;
    SubmitInfo.pWaitSemaphores := @WaitSems[0];
    SubmitInfo.pWaitDstStageMask := @WaitStages[0];
    SubmitInfo.commandBufferCount := 1;
    SubmitInfo.pCommandBuffers := @CmdHandle;
    SubmitInfo.signalSemaphoreCount := 1;
    SubmitInfo.pSignalSemaphores := @SignalSem;

    CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, Frame.InFlightFence),
      'vkQueueSubmit(SurfaceFrame)');

    if Assigned(vkQueuePresentKHR) then
    begin
      FillChar(PresentInfo, SizeOf(PresentInfo), 0);
      PresentInfo.sType := VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
      PresentInfo.waitSemaphoreCount := 1;
      PresentInfo.pWaitSemaphores := @SignalSem;
      PresentInfo.swapchainCount := 1;
      PresentInfo.pSwapchains := @ASurface.FSwapchain;
      PresentInfo.pImageIndices := @ASurface.FCurrentImageIndex;

      PresentRes := vkQueuePresentKHR(FPresentQueue, @PresentInfo);
      if (PresentRes = VK_ERROR_OUT_OF_DATE_KHR) or (PresentRes = VK_SUBOPTIMAL_KHR) or
         ASurface.FSwapchainSuboptimal then
      begin
        ASurface.FSwapchainSuboptimal := False;
        ASurface.Resize(
          Max(Cardinal(1), Max(ASurface.FRequestedWidth, ASurface.FSwapchainExtent.width)),
          Max(Cardinal(1), Max(ASurface.FRequestedHeight, ASurface.FSwapchainExtent.height)));
      end else
        CheckVk(PresentRes, 'vkQueuePresentKHR(SurfaceFrame)');
    end;
  end else
  if (FDevice <> nil) and (ASurface.FSwapchain = VK_NULL_HANDLE) and Assigned(vkQueueSubmit) then
  begin
    CmdHandle := Frame.CommandList.Handle;
    FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
    SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
    SubmitInfo.commandBufferCount := 1;
    SubmitInfo.pCommandBuffers := @CmdHandle;
    CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, Frame.InFlightFence),
      'vkQueueSubmit(SimulatedSurfaceFrame)');
  end;

  FFrameIndex := (FFrameIndex + 1) mod MaxFramesInFlight;
  Inc(ASurface.FFramesPresentedCount);
  Inc(FTotalFramesPresented);
end;

procedure TVulkanRHIDevice.WaitIdle;
begin
  if FStagingUploader <> nil then
    FStagingUploader.WaitForAsyncUploads;
  FlushStagingUploads;
  if (FDevice <> nil) and Assigned(vkDeviceWaitIdle) then
    vkDeviceWaitIdle(FDevice);
  Inc(FCompletedIdleEpoch);
  FlushAllDeferredDeletions;
  FDeferResourceDestruction := False;
end;

function TVulkanRHIDevice.CreateSecondaryCommandList: TRHICommandList;
begin
  Result := TVulkanRHICommandList.Create(Self, FGraphicsQueueFamily, cllSecondary);
end;

function TVulkanRHIDevice.GetSwapchainColorTexture: TRHITexture;
begin
  if (ActiveCommandList <> nil) and ActiveCommandList.IsRendering and
     ActiveCommandList.ActiveRenderingHasColor and
     (Length(ActiveCommandList.ActiveRenderingInfo.ColorAttachments) > 0) then
  begin
    if ActiveCommandList.ActiveRenderingInfo.ColorAttachments[0].ResolveTexture <> nil then
      Result := ActiveCommandList.ActiveRenderingInfo.ColorAttachments[0].ResolveTexture
    else
      Result := ActiveCommandList.ActiveRenderingInfo.ColorAttachments[0].Texture;
  end else
  if (FActiveSwapchainSurface <> nil) and (FActiveSwapchainSurface.GetCurrentColorTexture <> nil) then
    Result := FActiveSwapchainSurface.GetCurrentColorTexture
  else
  if FCurrentSwapchainImageIndex < Cardinal(Length(FSwapchainColorTextures)) then
    Result := FSwapchainColorTextures[FCurrentSwapchainImageIndex]
  else
    Result := FActiveColorTarget;
end;

function TVulkanRHIDevice.GetSwapchainDepthTexture: TRHITexture;
begin
  if (ActiveCommandList <> nil) and ActiveCommandList.IsRendering and
     ActiveCommandList.ActiveRenderingHasDepth and
     (ActiveCommandList.ActiveRenderingInfo.DepthAttachment.Texture <> nil) then
  begin
    if ActiveCommandList.ActiveRenderingInfo.DepthAttachment.ResolveTexture <> nil then
      Result := ActiveCommandList.ActiveRenderingInfo.DepthAttachment.ResolveTexture
    else
      Result := ActiveCommandList.ActiveRenderingInfo.DepthAttachment.Texture;
  end else
  if (FActiveSwapchainSurface <> nil) and (FActiveSwapchainSurface.GetDepthTexture <> nil) then
    Result := FActiveSwapchainSurface.GetDepthTexture
  else
  if FSwapchainDepthTexture <> nil then
    Result := FSwapchainDepthTexture
  else
    Result := FActiveDepthTarget;
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

function TVulkanRHIDevice.CreateTransientCarrierTexture(const ADesc: TRHITextureDesc;
  const AMinCarrierBytes: UInt64): TRHITexture;
begin
  Result := TVulkanRHITexture.CreateCarrier(Self, ADesc, AMinCarrierBytes);
end;

function TVulkanRHIDevice.TryCreateAliasedTexture(const ADesc: TRHITextureDesc;
  const ACarrierTexture: TRHITexture): TRHITexture;
begin
  if ACarrierTexture is TVulkanRHITexture then
    Result := TVulkanRHITexture.TryCreateAliased(Self, ADesc, TVulkanRHITexture(ACarrierTexture))
  else
    Result := nil;
end;

function TVulkanRHIDevice.CreateSampler(const ADesc: TRHISamplerDesc): TRHISampler;
begin
  Result := TVulkanRHISampler.Create(Self, ADesc);
end;

function ShouldPreferBuiltInInternalPassSPIRV(const AGLSLSource, ADebugName: String): Boolean;
const
  InternalSubsystemPassNames: array[0..25] of String = (
    'CastleBatch2D.vert',
    'CastleBatch2D.frag',
    'GpuCullingCS',
    'HiZDownsampleCS',
    'IBLBrdfLutComputeCS',
    'IBLPrefilterEnvComputeCS',
    'IBLIrradianceEnvComputeCS',
    'ClusteredLightCullingCS',
    'BloomDownsampleCS',
    'BloomUpsampleCS',
    'LuminanceHistogramCS',
    'HDRCompositeVS',
    'HDRCompositeFS',
    'PostProcessModulateCS',
    'GTAOHorizon_CS',
    'GTAODenoise_CS',
    'HiZSSR_CS',
    'VolumetricFogInject_CS',
    'VolumetricFogRaymarch_CS',
    'TAAResolve_CS',
    'ParticleSimulationCS',
    'ContactShadowsCS',
    'ComputeSkinningCS',
    'MaterialBinHistogramCS',
    'MaterialBinPrefixSumCS',
    'CastleBindlessIndirectVS'
  );
var
  PassName: String;
begin
  if (AGLSLSource <> '') and (Pos('#version', AGLSLSource) = 0) then
    Exit(True);
  if ADebugName = 'CastleBindlessIndirectFS' then
    Exit(True);
  for PassName in InternalSubsystemPassNames do
    if ADebugName = PassName then
      Exit(True);
  Result := False;
end;

function TVulkanRHIDevice.CreateShaderModuleFromGLSL(const AStage: TRHIShaderStage;
  const AGLSLSource: String; const ADebugName: String): TRHIShaderModule;
var
  SPIRV: TSPIRVBytecode;
begin
  SPIRV := nil;
  if (AGLSLSource <> '') and ShouldPreferBuiltInInternalPassSPIRV(AGLSLSource, ADebugName) then
  begin
    if not TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(
         AStage, AGLSLSource, ADebugName, SPIRV) then
      SPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(AStage);
    if Length(SPIRV) > 0 then
      Exit(CreateShaderModuleFromSPIRV(AStage, @SPIRV[0], Length(SPIRV), ADebugName));
  end;

  try
    SPIRV := TCastleShaderCompiler.Instance.GetOrCompileSPIRV(AStage, AGLSLSource, ADebugName);
  except
    on ERHIShaderCompilationError do
      if (AGLSLSource <> '') and
         not TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
        SPIRV := nil
      else
        raise;
  end;
  if Length(SPIRV) = 0 then
  begin
    if (AGLSLSource <> '') and
       not TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
    begin
      if not TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(
           AStage, AGLSLSource, ADebugName, SPIRV) then
        SPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(AStage);
      if Length(SPIRV) > 0 then
      begin
        TCastleShaderCompiler.Instance.RecordBuiltInFallbackHit;
        Exit(CreateShaderModuleFromSPIRV(AStage, @SPIRV[0], Length(SPIRV), ADebugName));
      end;
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
  EffDesc: TRHIGraphicsPipelineDesc;
  HashKey: UInt64;
  FoundPipeline: TVulkanRHIPipeline;
begin
  if FPortabilitySubsetCaps.Active then
    EffDesc := AdaptPipelineDescForPortabilitySubset(ADesc, FPortabilitySubsetCaps)
  else
    EffDesc := ADesc;
  if (FDevice <> nil) and (FPhysicalDevice <> nil) and
     (EffDesc.DepthAttachmentFormat <> pfUndefined) then
    EffDesc.DepthAttachmentFormat := NegotiateOptimalPixelFormat(
      EffDesc.DepthAttachmentFormat, [tuDepthStencil], FPhysicalDevice);
  HashKey := ComputePipelineHash(EffDesc);
  if FPipelineMap.TryGetValue(HashKey, FoundPipeline) then
  begin
    Inc(FPipelineCacheHits);
    if FSupportsExtendedDynamicState then
      FoundPipeline.UpdateDynamicStateDesc(EffDesc);
  end else
  begin
    Inc(FPipelineCacheMisses);
    FoundPipeline := TVulkanRHIPipeline.Create(Self, EffDesc);
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
  Desc3D := Default(TRHIGraphicsPipelineDesc);
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
    DescShadow := Default(TRHIGraphicsPipelineDesc);
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
  Desc2D := Default(TRHIGraphicsPipelineDesc);
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

function TVulkanRHIDevice.GrabTextureFloatImage(const SourceTexture: TRHITexture;
  const ReadArea: TRectangle): TRGBAlphaFloatImage;
var
  VkTex: TVulkanRHITexture;
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  Region: VkBufferImageCopy;
  Barrier: VkImageMemoryBarrier;
  SrcStage: VkPipelineStageFlags;
  BytesPerPixel, ByteSize, SrcIndex, DstIndex, TotalPixels: PtrUInt;
  MappedPixels: Pointer;
  RowY, ColX, SrcY, SrcW, SrcH, CopyW, CopyH: Integer;
  SrcBytePtr: PByte;
  SrcHalfPtr: PWord;
  SrcFloatPtr: PSingle;
  SrcU32Ptr: PCardinal;
  DstVecPtr: PVector4;
  DVal: Single;
  IsDepth, FlipVertical: Boolean;
begin
  if (SourceTexture = nil) or (ReadArea.Width <= 0) or (ReadArea.Height <= 0) then
    Exit(nil);

  Result := TRGBAlphaFloatImage.Create(ReadArea.Width, ReadArea.Height);
  VkTex := SourceTexture as TVulkanRHITexture;
  if (FDevice = nil) or not Assigned(vkCmdCopyImageToBuffer) then
    Exit;

  if Assigned(vkDeviceWaitIdle) then
  begin
    vkDeviceWaitIdle(FDevice);
    Inc(FCompletedIdleEpoch);
  end;
  FlushStagingUploads;

  IsDepth := (VkTex.AspectMask and VK_IMAGE_ASPECT_DEPTH_BIT) <> 0;
  FlipVertical := VkTex.RenderedLayerMask <> 0;
  SrcW := Max(1, Integer(VkTex.Desc.Width));
  SrcH := Max(1, Integer(VkTex.Desc.Height));
  CopyW := EnsureRange(ReadArea.Width, 1, Max(1, SrcW - Max(0, ReadArea.Left)));
  CopyH := EnsureRange(ReadArea.Height, 1, Max(1, SrcH - Max(0, ReadArea.Bottom)));
  TotalPixels := PtrUInt(CopyW) * PtrUInt(CopyH);

  if IsDepth then
  begin
    if VkTex.Desc.Format = pfD16_UNorm then
      BytesPerPixel := 2
    else
      BytesPerPixel := 4;
  end else
  begin
    case VkTex.Desc.Format of
      pfRGBA32_Float: BytesPerPixel := 16;
      pfRGBA16_Float: BytesPerPixel := 8;
      pfRG16_Float, pfR32_Float: BytesPerPixel := 4;
      pfR16_Float, pfRG8_UNorm: BytesPerPixel := 2;
      pfR8_UNorm: BytesPerPixel := 1;
    else
      BytesPerPixel := 4;
    end;
  end;

  ByteSize := TotalPixels * BytesPerPixel;
  StagingDesc := TRHIBufferDesc.Create(ByteSize, [buTransferDst], muGpuToCpu, 'GrabTextureFloatStaging');
  StagingBuf := TVulkanRHIBuffer.Create(Self, StagingDesc, nil);
  try
    Cmd := BeginSingleTimeCommands;
    if (VkTex.CurrentState <> rsTransferSrc) and Assigned(vkCmdPipelineBarrier) then
    begin
      FillChar(Barrier, SizeOf(Barrier), 0);
      Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
      RHIStateToVkLayoutAndAccess(VkTex.CurrentState, Barrier.oldLayout, Barrier.srcAccessMask, SrcStage);
      Barrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
      Barrier.dstAccessMask := VK_ACCESS_TRANSFER_READ_BIT;
      Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.image := VkTex.Image;
      Barrier.subresourceRange.aspectMask := VkTex.AspectMask;
      Barrier.subresourceRange.baseMipLevel := 0;
      Barrier.subresourceRange.levelCount := Max(Cardinal(1), VkTex.Desc.MipLevels);
      Barrier.subresourceRange.baseArrayLayer := 0;
      Barrier.subresourceRange.layerCount := Max(Cardinal(1), VkTex.Desc.DepthOrArrayLayers);
      vkCmdPipelineBarrier(Cmd, SrcStage, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nil, 0, nil, 1, @Barrier);
      VkTex.CurrentState := rsTransferSrc;
    end;

    FillChar(Region, SizeOf(Region), 0);
    if IsDepth then
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_DEPTH_BIT
    else
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
    Region.imageSubresource.layerCount := 1;
    Region.imageOffset.x := EnsureRange(ReadArea.Left, 0, SrcW - CopyW);
    if FlipVertical then
      Region.imageOffset.y := EnsureRange(SrcH - (Max(0, ReadArea.Bottom) + CopyH), 0, SrcH - CopyH)
    else
      Region.imageOffset.y := EnsureRange(ReadArea.Bottom, 0, SrcH - CopyH);
    Region.imageExtent.width := Cardinal(CopyW);
    Region.imageExtent.height := Cardinal(CopyH);
    Region.imageExtent.depth := 1;

    vkCmdCopyImageToBuffer(Cmd, VkTex.Image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      StagingBuf.Handle, 1, @Region);
    EndSingleTimeCommands(Cmd);

    if StagingBuf.Allocation.IsValid and (FMemoryAllocator <> nil) then
      FMemoryAllocator.InvalidateAllocation(StagingBuf.Allocation, 0, ByteSize);

    MappedPixels := StagingBuf.Map;
    try
      DstVecPtr := PVector4(Result.RawPixels);
      SrcBytePtr := PByte(MappedPixels);
      SrcHalfPtr := PWord(MappedPixels);
      SrcFloatPtr := PSingle(MappedPixels);
      SrcU32Ptr := PCardinal(MappedPixels);

      for RowY := 0 to CopyH - 1 do
      begin
        if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
        for ColX := 0 to CopyW - 1 do
        begin
          SrcIndex := PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX);
          DstIndex := PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX);
          if IsDepth then
          begin
            if VkTex.Desc.Format = pfD16_UNorm then
              DVal := SrcHalfPtr[SrcIndex] / 65535.0
            else if VkTex.Desc.Format = pfD24_UNorm_S8_UInt then
              DVal := (SrcU32Ptr[SrcIndex] and $FFFFFF) / 16777215.0
            else
              DVal := SrcFloatPtr[SrcIndex];
            DstVecPtr[DstIndex] := Vector4(DVal, DVal, DVal, 1.0);
          end else
          begin
            case VkTex.Desc.Format of
              pfRGBA32_Float:
                DstVecPtr[DstIndex] := Vector4(
                  SrcFloatPtr[SrcIndex * 4 + 0],
                  SrcFloatPtr[SrcIndex * 4 + 1],
                  SrcFloatPtr[SrcIndex * 4 + 2],
                  SrcFloatPtr[SrcIndex * 4 + 3]);
              pfRGBA16_Float:
                DstVecPtr[DstIndex] := Vector4(
                  HalfFloatToFloat(SrcHalfPtr[SrcIndex * 4 + 0]),
                  HalfFloatToFloat(SrcHalfPtr[SrcIndex * 4 + 1]),
                  HalfFloatToFloat(SrcHalfPtr[SrcIndex * 4 + 2]),
                  HalfFloatToFloat(SrcHalfPtr[SrcIndex * 4 + 3]));
              pfRG16_Float:
                DstVecPtr[DstIndex] := Vector4(
                  HalfFloatToFloat(SrcHalfPtr[SrcIndex * 2 + 0]),
                  HalfFloatToFloat(SrcHalfPtr[SrcIndex * 2 + 1]),
                  0.0, 1.0);
              pfR32_Float:
                begin
                  DVal := SrcFloatPtr[SrcIndex];
                  DstVecPtr[DstIndex] := Vector4(DVal, DVal, DVal, 1.0);
                end;
              pfR16_Float:
                begin
                  DVal := HalfFloatToFloat(SrcHalfPtr[SrcIndex]);
                  DstVecPtr[DstIndex] := Vector4(DVal, DVal, DVal, 1.0);
                end;
              pfRG8_UNorm:
                DstVecPtr[DstIndex] := Vector4(
                  SrcBytePtr[SrcIndex * 2 + 0] / 255.0,
                  SrcBytePtr[SrcIndex * 2 + 1] / 255.0,
                  0.0, 1.0);
              pfR8_UNorm:
                begin
                  DVal := SrcBytePtr[SrcIndex] / 255.0;
                  DstVecPtr[DstIndex] := Vector4(DVal, DVal, DVal, 1.0);
                end;
              pfBGRA8_UNorm, pfBGRA8_sRGB:
                DstVecPtr[DstIndex] := Vector4(
                  SrcBytePtr[SrcIndex * 4 + 2] / 255.0,
                  SrcBytePtr[SrcIndex * 4 + 1] / 255.0,
                  SrcBytePtr[SrcIndex * 4 + 0] / 255.0,
                  SrcBytePtr[SrcIndex * 4 + 3] / 255.0);
            else
              DstVecPtr[DstIndex] := Vector4(
                SrcBytePtr[SrcIndex * 4 + 0] / 255.0,
                SrcBytePtr[SrcIndex * 4 + 1] / 255.0,
                SrcBytePtr[SrcIndex * 4 + 2] / 255.0,
                SrcBytePtr[SrcIndex * 4 + 3] / 255.0);
            end;
          end;
        end;
      end;
    finally
      StagingBuf.Unmap;
    end;
  finally
    FreeAndNil(StagingBuf);
  end;
end;

function TVulkanRHIDevice.GrabTextureImage(const SourceTexture: TRHITexture;
  const ReadArea: TRectangle): TRGBAlphaImage;
var
  VkTex: TVulkanRHITexture;
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  Region: VkBufferImageCopy;
  Barrier: VkImageMemoryBarrier;
  SrcStage: VkPipelineStageFlags;
  BytesPerPixel, ByteSize, RowBytes: PtrUInt;
  MappedPixels: Pointer;
  RowY, ColX, SrcX, SrcY, SrcW, SrcH, CopyW, CopyH: Integer;
  SrcIndex, DstIndex, TotalPixels: PtrUInt;
  SrcBytePtr, DstPtr: PByte;
  DepthFloatPtr: PSingle;
  DepthU16Ptr: PWord;
  DepthU32Ptr: PCardinal;
  DByte: Byte;
  IsDepth, FlipVertical: Boolean;

  function Float01ToByte(const AVal: Single): Byte; inline;
  begin
    Result := Byte(Round(EnsureRange(AVal, 0.0, 1.0) * 255.0));
  end;

begin
  if (SourceTexture = nil) or (ReadArea.Width <= 0) or (ReadArea.Height <= 0) then
    Exit(nil);

  Result := TRGBAlphaImage.Create(ReadArea.Width, ReadArea.Height);
  VkTex := SourceTexture as TVulkanRHITexture;
  if (not VkTex.FOwnsImage) and (VkTex.FPresentReadbackShadow <> nil) then
    VkTex := VkTex.FPresentReadbackShadow;

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

  if Assigned(vkDeviceWaitIdle) then
  begin
    vkDeviceWaitIdle(FDevice);
    Inc(FCompletedIdleEpoch);
  end;
  FlushStagingUploads;
  IsDepth := (VkTex.AspectMask and VK_IMAGE_ASPECT_DEPTH_BIT) <> 0;
  FlipVertical := VkTex.RenderedLayerMask <> 0;
  SrcW := Max(1, Integer(VkTex.Desc.Width));
  SrcH := Max(1, Integer(VkTex.Desc.Height));
  CopyW := EnsureRange(ReadArea.Width, 1, Max(1, SrcW - Max(0, ReadArea.Left)));
  CopyH := EnsureRange(ReadArea.Height, 1, Max(1, SrcH - Max(0, ReadArea.Bottom)));
  TotalPixels := PtrUInt(CopyW) * PtrUInt(CopyH);
  if IsDepth then
  begin
    if VkTex.Desc.Format = pfD16_UNorm then
      BytesPerPixel := 2
    else
      BytesPerPixel := 4;
  end else
  begin
    case VkTex.Desc.Format of
      pfRGBA32_Float: BytesPerPixel := 16;
      pfRGBA16_Float: BytesPerPixel := 8;
      pfRG16_Float, pfR32_Float: BytesPerPixel := 4;
      pfR16_Float, pfRG8_UNorm: BytesPerPixel := 2;
      pfR8_UNorm: BytesPerPixel := 1;
    else
      BytesPerPixel := 4;
    end;
  end;
  ByteSize := TotalPixels * BytesPerPixel;
  StagingDesc := TRHIBufferDesc.Create(ByteSize, [buTransferDst], muGpuToCpu, 'GrabTextureStaging');
  StagingBuf := TVulkanRHIBuffer.Create(Self, StagingDesc, nil);
  try
    Cmd := BeginSingleTimeCommands;
    if (VkTex.CurrentState <> rsTransferSrc) and Assigned(vkCmdPipelineBarrier) then
    begin
      FillChar(Barrier, SizeOf(Barrier), 0);
      Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
      RHIStateToVkLayoutAndAccess(VkTex.CurrentState, Barrier.oldLayout, Barrier.srcAccessMask, SrcStage);
      Barrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
      Barrier.dstAccessMask := VK_ACCESS_TRANSFER_READ_BIT;
      Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.image := VkTex.Image;
      Barrier.subresourceRange.aspectMask := VkTex.AspectMask;
      Barrier.subresourceRange.baseMipLevel := 0;
      Barrier.subresourceRange.levelCount := Max(Cardinal(1), VkTex.Desc.MipLevels);
      Barrier.subresourceRange.baseArrayLayer := 0;
      Barrier.subresourceRange.layerCount := Max(Cardinal(1), VkTex.Desc.DepthOrArrayLayers);
      vkCmdPipelineBarrier(Cmd, SrcStage, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nil, 0, nil, 1, @Barrier);
      VkTex.CurrentState := rsTransferSrc;
    end;
    FillChar(Region, SizeOf(Region), 0);
    if IsDepth then
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_DEPTH_BIT
    else
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
    Region.imageSubresource.layerCount := 1;
    Region.imageOffset.x := EnsureRange(ReadArea.Left, 0, SrcW - CopyW);
    if FlipVertical then
      Region.imageOffset.y := EnsureRange(SrcH - (Max(0, ReadArea.Bottom) + CopyH), 0, SrcH - CopyH)
    else
      Region.imageOffset.y := EnsureRange(ReadArea.Bottom, 0, SrcH - CopyH);
    Region.imageExtent.width := Cardinal(CopyW);
    Region.imageExtent.height := Cardinal(CopyH);
    Region.imageExtent.depth := 1;

    vkCmdCopyImageToBuffer(Cmd, VkTex.Image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      StagingBuf.Handle, 1, @Region);
    EndSingleTimeCommands(Cmd);

    if StagingBuf.Allocation.IsValid and (FMemoryAllocator <> nil) then
      FMemoryAllocator.InvalidateAllocation(StagingBuf.Allocation, 0, ByteSize);

    MappedPixels := StagingBuf.Map;
    try
      DstPtr := PByte(Result.RawPixels);
      if IsDepth then
      begin
        if VkTex.Desc.Format = pfD16_UNorm then
        begin
          DepthU16Ptr := PWord(MappedPixels);
          for RowY := 0 to CopyH - 1 do
          begin
            if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
            for ColX := 0 to CopyW - 1 do
            begin
              SrcIndex := PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX);
              DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
              DByte := Byte(DepthU16Ptr[SrcIndex] shr 8);
              DstPtr[DstIndex + 0] := DByte;
              DstPtr[DstIndex + 1] := DByte;
              DstPtr[DstIndex + 2] := DByte;
              DstPtr[DstIndex + 3] := 255;
            end;
          end;
        end else
        if VkTex.Desc.Format = pfD24_UNorm_S8_UInt then
        begin
          DepthU32Ptr := PCardinal(MappedPixels);
          for RowY := 0 to CopyH - 1 do
          begin
            if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
            for ColX := 0 to CopyW - 1 do
            begin
              SrcIndex := PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX);
              DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
              DByte := Byte((DepthU32Ptr[SrcIndex] shr 16) and $FF);
              DstPtr[DstIndex + 0] := DByte;
              DstPtr[DstIndex + 1] := DByte;
              DstPtr[DstIndex + 2] := DByte;
              DstPtr[DstIndex + 3] := 255;
            end;
          end;
        end else
        begin
          DepthFloatPtr := PSingle(MappedPixels);
          for RowY := 0 to CopyH - 1 do
          begin
            if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
            for ColX := 0 to CopyW - 1 do
            begin
              SrcIndex := PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX);
              DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
              DByte := Float01ToByte(DepthFloatPtr[SrcIndex]);
              DstPtr[DstIndex + 0] := DByte;
              DstPtr[DstIndex + 1] := DByte;
              DstPtr[DstIndex + 2] := DByte;
              DstPtr[DstIndex + 3] := 255;
            end;
          end;
        end;
      end else
      if VkTex.Desc.Format = pfRGBA32_Float then
      begin
        DepthFloatPtr := PSingle(MappedPixels);
        for RowY := 0 to CopyH - 1 do
        begin
          if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
          for ColX := 0 to CopyW - 1 do
          begin
            SrcIndex := (PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX)) * 4;
            DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
            DstPtr[DstIndex + 0] := Float01ToByte(DepthFloatPtr[SrcIndex + 0]);
            DstPtr[DstIndex + 1] := Float01ToByte(DepthFloatPtr[SrcIndex + 1]);
            DstPtr[DstIndex + 2] := Float01ToByte(DepthFloatPtr[SrcIndex + 2]);
            DstPtr[DstIndex + 3] := Float01ToByte(DepthFloatPtr[SrcIndex + 3]);
          end;
        end;
      end else
      if VkTex.Desc.Format = pfRGBA16_Float then
      begin
        DepthU16Ptr := PWord(MappedPixels);
        for RowY := 0 to CopyH - 1 do
        begin
          if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
          for ColX := 0 to CopyW - 1 do
          begin
            SrcIndex := (PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX)) * 4;
            DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
            DstPtr[DstIndex + 0] := Float01ToByte(HalfFloatToFloat(DepthU16Ptr[SrcIndex + 0]));
            DstPtr[DstIndex + 1] := Float01ToByte(HalfFloatToFloat(DepthU16Ptr[SrcIndex + 1]));
            DstPtr[DstIndex + 2] := Float01ToByte(HalfFloatToFloat(DepthU16Ptr[SrcIndex + 2]));
            DstPtr[DstIndex + 3] := Float01ToByte(HalfFloatToFloat(DepthU16Ptr[SrcIndex + 3]));
          end;
        end;
      end else
      if VkTex.Desc.Format = pfRG16_Float then
      begin
        DepthU16Ptr := PWord(MappedPixels);
        for RowY := 0 to CopyH - 1 do
        begin
          if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
          for ColX := 0 to CopyW - 1 do
          begin
            SrcIndex := (PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX)) * 2;
            DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
            DstPtr[DstIndex + 0] := Float01ToByte(HalfFloatToFloat(DepthU16Ptr[SrcIndex + 0]));
            DstPtr[DstIndex + 1] := Float01ToByte(HalfFloatToFloat(DepthU16Ptr[SrcIndex + 1]));
            DstPtr[DstIndex + 2] := 0;
            DstPtr[DstIndex + 3] := 255;
          end;
        end;
      end else
      if VkTex.Desc.Format = pfR32_Float then
      begin
        DepthFloatPtr := PSingle(MappedPixels);
        for RowY := 0 to CopyH - 1 do
        begin
          if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
          for ColX := 0 to CopyW - 1 do
          begin
            SrcIndex := PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX);
            DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
            DByte := Float01ToByte(DepthFloatPtr[SrcIndex]);
            DstPtr[DstIndex + 0] := DByte;
            DstPtr[DstIndex + 1] := DByte;
            DstPtr[DstIndex + 2] := DByte;
            DstPtr[DstIndex + 3] := 255;
          end;
        end;
      end else
      if VkTex.Desc.Format = pfR16_Float then
      begin
        DepthU16Ptr := PWord(MappedPixels);
        for RowY := 0 to CopyH - 1 do
        begin
          if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
          for ColX := 0 to CopyW - 1 do
          begin
            SrcIndex := PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX);
            DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
            DByte := Float01ToByte(HalfFloatToFloat(DepthU16Ptr[SrcIndex]));
            DstPtr[DstIndex + 0] := DByte;
            DstPtr[DstIndex + 1] := DByte;
            DstPtr[DstIndex + 2] := DByte;
            DstPtr[DstIndex + 3] := 255;
          end;
        end;
      end else
      if VkTex.Desc.Format = pfRG8_UNorm then
      begin
        SrcBytePtr := PByte(MappedPixels);
        for RowY := 0 to CopyH - 1 do
        begin
          if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
          for ColX := 0 to CopyW - 1 do
          begin
            SrcIndex := (PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX)) * 2;
            DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
            DstPtr[DstIndex + 0] := SrcBytePtr[SrcIndex + 0];
            DstPtr[DstIndex + 1] := SrcBytePtr[SrcIndex + 1];
            DstPtr[DstIndex + 2] := 0;
            DstPtr[DstIndex + 3] := 255;
          end;
        end;
      end else
      if VkTex.Desc.Format = pfR8_UNorm then
      begin
        SrcBytePtr := PByte(MappedPixels);
        for RowY := 0 to CopyH - 1 do
        begin
          if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
          for ColX := 0 to CopyW - 1 do
          begin
            SrcIndex := PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX);
            DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
            DByte := SrcBytePtr[SrcIndex];
            DstPtr[DstIndex + 0] := DByte;
            DstPtr[DstIndex + 1] := DByte;
            DstPtr[DstIndex + 2] := DByte;
            DstPtr[DstIndex + 3] := 255;
          end;
        end;
      end else
      if VkTex.Desc.Format in [pfBGRA8_UNorm, pfBGRA8_sRGB] then
      begin
        SrcBytePtr := PByte(MappedPixels);
        for RowY := 0 to CopyH - 1 do
        begin
          if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
          for ColX := 0 to CopyW - 1 do
          begin
            SrcIndex := (PtrUInt(SrcY) * PtrUInt(CopyW) + PtrUInt(ColX)) * 4;
            DstIndex := (PtrUInt(RowY) * PtrUInt(ReadArea.Width) + PtrUInt(ColX)) * 4;
            DstPtr[DstIndex + 0] := SrcBytePtr[SrcIndex + 2];
            DstPtr[DstIndex + 1] := SrcBytePtr[SrcIndex + 1];
            DstPtr[DstIndex + 2] := SrcBytePtr[SrcIndex + 0];
            DstPtr[DstIndex + 3] := SrcBytePtr[SrcIndex + 3];
          end;
        end;
      end else
      if (not FlipVertical) and (CopyW = ReadArea.Width) and (CopyH = ReadArea.Height) then
        Move(MappedPixels^, Result.RawPixels^, ByteSize)
      else
      begin
        SrcBytePtr := PByte(MappedPixels);
        RowBytes := PtrUInt(CopyW) * 4;
        for RowY := 0 to CopyH - 1 do
        begin
          if FlipVertical then SrcY := (CopyH - 1) - RowY else SrcY := RowY;
          Move(SrcBytePtr[PtrUInt(SrcY) * RowBytes],
            DstPtr[PtrUInt(RowY) * PtrUInt(ReadArea.Width) * 4], RowBytes);
        end;
      end;
    finally
      StagingBuf.Unmap;
    end;
  finally
    FreeAndNil(StagingBuf);
  end;
end;

function TVulkanRHIDevice.GrabTextureSubresourceImage(
  const SourceTexture: TRHITexture;
  const AMipLevel, AArrayLayer: Cardinal): TRGBAlphaImage;
var
  VkTex: TVulkanRHITexture;
  ClampedMip, ClampedLayer: Cardinal;
  MipW, MipH, RowY, ColX: Integer;
  BytesPerPixel, ByteSize, TotalPixels, SrcIndex, DstIndex: PtrUInt;
  StagingDesc: TRHIBufferDesc;
  StagingBuf: TVulkanRHIBuffer;
  Cmd: VkCommandBuffer;
  Region: VkBufferImageCopy;
  Barrier: VkImageMemoryBarrier;
  SrcStage: VkPipelineStageFlags;
  MappedPixels: Pointer;
  SrcBytePtr, DstPtr: PByte;
  SrcHalfPtr: PWord;
  SrcFloatPtr: PSingle;
  PrevState: TRHIResourceState;

  function Float01ToByte(const AVal: Single): Byte; inline;
  begin
    Result := Byte(Round(EnsureRange(AVal, 0.0, 1.0) * 255.0));
  end;

begin
  if SourceTexture = nil then
    Exit(nil);

  VkTex := SourceTexture as TVulkanRHITexture;
  ClampedMip := Min(AMipLevel, Max(Cardinal(1), VkTex.Desc.MipLevels) - 1);
  if VkTex.Desc.Dimension = td3D then
    ClampedLayer := 0
  else
    ClampedLayer := Min(AArrayLayer, Max(Cardinal(1), VkTex.Desc.DepthOrArrayLayers) - 1);

  MipW := Max(1, Integer(VkTex.Desc.Width shr ClampedMip));
  MipH := Max(1, Integer(VkTex.Desc.Height shr ClampedMip));
  Result := TRGBAlphaImage.Create(MipW, MipH);

  if (FDevice = nil) or not Assigned(vkCmdCopyImageToBuffer) then
  begin
    if Length(VkTex.FHostPixels) >= 4 then
    begin
      DstPtr := PByte(Result.RawPixels);
      for RowY := 0 to MipH - 1 do
        for ColX := 0 to MipW - 1 do
        begin
          DstIndex := (PtrUInt(RowY) * PtrUInt(MipW) + PtrUInt(ColX)) * 4;
          SrcIndex := DstIndex mod PtrUInt(Length(VkTex.FHostPixels) and (not PtrInt(3)));
          Move(VkTex.FHostPixels[SrcIndex], DstPtr[DstIndex], 4);
        end;
    end;
    Exit;
  end;

  if Assigned(vkDeviceWaitIdle) then
  begin
    vkDeviceWaitIdle(FDevice);
    Inc(FCompletedIdleEpoch);
  end;
  FlushStagingUploads;

  TotalPixels := PtrUInt(MipW) * PtrUInt(MipH);
  case VkTex.Desc.Format of
    pfRGBA32_Float: BytesPerPixel := 16;
    pfRGBA16_Float: BytesPerPixel := 8;
    pfRG16_Float, pfR32_Float: BytesPerPixel := 4;
    pfR16_Float, pfRG8_UNorm: BytesPerPixel := 2;
    pfR8_UNorm: BytesPerPixel := 1;
  else
    BytesPerPixel := 4;
  end;
  ByteSize := TotalPixels * BytesPerPixel;

  StagingDesc := TRHIBufferDesc.Create(ByteSize, [buTransferDst], muGpuToCpu, 'GrabSubresourceStaging');
  StagingBuf := TVulkanRHIBuffer.Create(Self, StagingDesc, nil);
  try
    PrevState := VkTex.CurrentState;
    Cmd := BeginSingleTimeCommands;
    if (PrevState <> rsTransferSrc) and Assigned(vkCmdPipelineBarrier) then
    begin
      FillChar(Barrier, SizeOf(Barrier), 0);
      Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
      RHIStateToVkLayoutAndAccess(PrevState, Barrier.oldLayout, Barrier.srcAccessMask, SrcStage);
      Barrier.newLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
      Barrier.dstAccessMask := VK_ACCESS_TRANSFER_READ_BIT;
      Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.image := VkTex.Image;
      Barrier.subresourceRange.aspectMask := VkTex.AspectMask;
      Barrier.subresourceRange.baseMipLevel := 0;
      Barrier.subresourceRange.levelCount := Max(Cardinal(1), VkTex.Desc.MipLevels);
      Barrier.subresourceRange.baseArrayLayer := 0;
      Barrier.subresourceRange.layerCount := Max(Cardinal(1), VkTex.Desc.DepthOrArrayLayers);
      vkCmdPipelineBarrier(Cmd, SrcStage, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nil, 0, nil, 1, @Barrier);
      VkTex.CurrentState := rsTransferSrc;
    end;

    FillChar(Region, SizeOf(Region), 0);
    if (VkTex.AspectMask and VK_IMAGE_ASPECT_DEPTH_BIT) <> 0 then
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_DEPTH_BIT
    else
      Region.imageSubresource.aspectMask := VK_IMAGE_ASPECT_COLOR_BIT;
    Region.imageSubresource.mipLevel := ClampedMip;
    Region.imageSubresource.baseArrayLayer := ClampedLayer;
    Region.imageSubresource.layerCount := 1;
    Region.imageExtent.width := Cardinal(MipW);
    Region.imageExtent.height := Cardinal(MipH);
    Region.imageExtent.depth := 1;

    vkCmdCopyImageToBuffer(Cmd, VkTex.Image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
      StagingBuf.Handle, 1, @Region);

    if (PrevState = rsShaderRead) and Assigned(vkCmdPipelineBarrier) then
    begin
      FillChar(Barrier, SizeOf(Barrier), 0);
      Barrier.sType := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
      Barrier.oldLayout := VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
      Barrier.newLayout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
      Barrier.srcAccessMask := VK_ACCESS_TRANSFER_READ_BIT;
      Barrier.dstAccessMask := VK_ACCESS_SHADER_READ_BIT;
      Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
      Barrier.image := VkTex.Image;
      Barrier.subresourceRange.aspectMask := VkTex.AspectMask;
      Barrier.subresourceRange.baseMipLevel := 0;
      Barrier.subresourceRange.levelCount := Max(Cardinal(1), VkTex.Desc.MipLevels);
      Barrier.subresourceRange.baseArrayLayer := 0;
      Barrier.subresourceRange.layerCount := Max(Cardinal(1), VkTex.Desc.DepthOrArrayLayers);
      vkCmdPipelineBarrier(Cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        0, 0, nil, 0, nil, 1, @Barrier);
      VkTex.CurrentState := rsShaderRead;
    end;

    EndSingleTimeCommands(Cmd);

    if StagingBuf.Allocation.IsValid and (FMemoryAllocator <> nil) then
      FMemoryAllocator.InvalidateAllocation(StagingBuf.Allocation, 0, ByteSize);

    MappedPixels := StagingBuf.Map;
    try
      DstPtr := PByte(Result.RawPixels);
      if VkTex.Desc.Format = pfRGBA32_Float then
      begin
        SrcFloatPtr := PSingle(MappedPixels);
        for DstIndex := 0 to TotalPixels - 1 do
        begin
          DstPtr[DstIndex * 4 + 0] := Float01ToByte(SrcFloatPtr[DstIndex * 4 + 0]);
          DstPtr[DstIndex * 4 + 1] := Float01ToByte(SrcFloatPtr[DstIndex * 4 + 1]);
          DstPtr[DstIndex * 4 + 2] := Float01ToByte(SrcFloatPtr[DstIndex * 4 + 2]);
          DstPtr[DstIndex * 4 + 3] := Float01ToByte(SrcFloatPtr[DstIndex * 4 + 3]);
        end;
      end else
      if VkTex.Desc.Format = pfRGBA16_Float then
      begin
        SrcHalfPtr := PWord(MappedPixels);
        for DstIndex := 0 to TotalPixels - 1 do
        begin
          DstPtr[DstIndex * 4 + 0] := Float01ToByte(HalfFloatToFloat(SrcHalfPtr[DstIndex * 4 + 0]));
          DstPtr[DstIndex * 4 + 1] := Float01ToByte(HalfFloatToFloat(SrcHalfPtr[DstIndex * 4 + 1]));
          DstPtr[DstIndex * 4 + 2] := Float01ToByte(HalfFloatToFloat(SrcHalfPtr[DstIndex * 4 + 2]));
          DstPtr[DstIndex * 4 + 3] := Float01ToByte(HalfFloatToFloat(SrcHalfPtr[DstIndex * 4 + 3]));
        end;
      end else
      if VkTex.Desc.Format in [pfBGRA8_UNorm, pfBGRA8_sRGB] then
      begin
        SrcBytePtr := PByte(MappedPixels);
        for DstIndex := 0 to TotalPixels - 1 do
        begin
          DstPtr[DstIndex * 4 + 0] := SrcBytePtr[DstIndex * 4 + 2];
          DstPtr[DstIndex * 4 + 1] := SrcBytePtr[DstIndex * 4 + 1];
          DstPtr[DstIndex * 4 + 2] := SrcBytePtr[DstIndex * 4 + 0];
          DstPtr[DstIndex * 4 + 3] := SrcBytePtr[DstIndex * 4 + 3];
        end;
      end else
        Move(MappedPixels^, Result.RawPixels^, TotalPixels * 4);
    finally
      StagingBuf.Unmap;
    end;
  finally
    FreeAndNil(StagingBuf);
  end;
end;

procedure TVulkanRHIDevice.LoadPipelineCache(const CacheFileUrl: String);

  function TryLoadCacheFromUrl(const AUrl: String): Boolean;
  var
    Stream: TStream;
    Blob: TBytes;
    CacheInfo: VkPipelineCacheCreateInfo;
  begin
    Result := False;
    if (AUrl = '') or (not UriFileExists(AUrl)) then Exit;
    try
      Stream := Download(AUrl);
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
          Result := True;
        end;
      finally
        FreeAndNil(Stream);
      end;
    except
      on E: Exception do
        WritelnLog('Vulkan', 'Could not load pipeline cache from "%s": %s', [AUrl, E.Message]);
    end;
  end;

begin
  FPipelineCacheSeededFromBundle := False;
  if (FDevice = nil) or not Assigned(vkCreatePipelineCache) then Exit;

  { 1. Prefer user-writable persistent cache (e.g. castle-config:/vulkan_pipeline_cache.bin) }
  if (CacheFileUrl <> '') and TryLoadCacheFromUrl(CacheFileUrl) then
    Exit;

  { 2. First-boot fallback: try packaged asset seed cache (e.g. castle-data:/vulkan_pipeline_cache.bin) }
  if (FBundledPipelineCacheFallbackUrl <> '') and
     (FBundledPipelineCacheFallbackUrl <> CacheFileUrl) and
     TryLoadCacheFromUrl(FBundledPipelineCacheFallbackUrl) then
    FPipelineCacheSeededFromBundle := True;
end;

procedure TVulkanRHIDevice.SavePipelineCache(const CacheFileUrl: String);
var
  DataSize: PtrUInt;
  Blob: TBytes;
  Stream: TStream;
  LocalFileName, LocalDir: String;
begin
  if (FDevice = nil) or (FPipelineCache = VK_NULL_HANDLE) or not Assigned(vkGetPipelineCacheData) then
    Exit;
  if CacheFileUrl = '' then
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
    LocalFileName := UriToFilenameSafe(CacheFileUrl);
    if LocalFileName <> '' then
    begin
      LocalDir := ExtractFilePath(LocalFileName);
      if LocalDir <> '' then
        CheckForceDirectories(LocalDir);
    end;
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
  DriverLine: String;
begin
  HasBudgetExt := QueryMemoryBudget(UsedBytes, BudgetBytes, UsedMB, BudgetMB);
  if FDriverName <> '' then
  begin
    DriverLine := '  Driver: ' + FDriverName;
    if FDriverInfo <> '' then
      DriverLine := DriverLine + ' (' + FDriverInfo + ')';
    DriverLine := DriverLine + LineEnding;
  end else
    DriverLine := '';
  Result :=
    'Vulkan RHI information:' + LineEnding +
    LineEnding +
    Section + LineEnding +
    'Basic information:' + LineEnding +
    LineEnding +
    '  Device name: ' + FCapabilities.DeviceName + LineEnding +
    '  Vendor: ' + GetVendorName + ' (ID: 0x' + IntToHex(FCapabilities.VendorId, 4) + ')' + LineEnding +
    '  Device ID: ' + IntToStr(FDeviceId) + LineEnding +
    DriverLine +
    '  Instance API version: ' + FormatVkVersion(FInstanceApiVersion) + LineEnding +
    '  Device API version: ' + FormatVkVersion(FDeviceApiVersion) + LineEnding +
    LineEnding +
    Section + LineEnding +
    'Features:' + LineEnding +
    LineEnding +
    '  Portability subset (VK_KHR_portability_subset / MoltenVK): ' + BoolToStr(FIsPortabilitySubsetDevice, True) + LineEnding +
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
    '  Validation layer (VK_LAYER_KHRONOS_validation): ' + BoolToStr(FValidationLayerActive, True) +
      Format(' (debug messenger: %s, errors: %d, warnings: %d)',
        [BoolToStr(FDebugMessenger <> VK_NULL_HANDLE, True), FValidationErrorCount, FValidationWarningCount]) + LineEnding +
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

function TVulkanRHIDevice.RegisterBindlessTexture(const ATexture: TRHITexture;
  const ASampler: TRHISampler): Cardinal;
begin
  if (FBindlessTextureManager <> nil) and (ATexture <> nil) then
    Result := FBindlessTextureManager.RegisterTexture(ATexture, ASampler)
  else
    Result := 0;
end;

function TVulkanRHIDevice.RegisterOrUpdateBindlessMaterial(
  var AMaterialIndex: Cardinal; var AAlreadyRegistered: Boolean;
  const AEntryData; const AEntrySizeInBytes: Cardinal): Cardinal;
var
  Entry: TCastleBindlessMaterialEntry;
begin
  if (FBindlessTextureManager <> nil) and
     (AEntrySizeInBytes = SizeOf(TCastleBindlessMaterialEntry)) then
  begin
    Move(AEntryData, Entry, SizeOf(TCastleBindlessMaterialEntry));
    Result := FBindlessTextureManager.RegisterOrUpdateMaterial(
      AMaterialIndex, AAlreadyRegistered, Entry);
  end else
    Result := AMaterialIndex;
end;

function TVulkanRHIDevice.GetBindlessDescriptorSet: TRHIDescriptorSet;
begin
  if FBindlessTextureManager <> nil then
  begin
    FBindlessTextureManager.EnsureDescriptorSetCreated;
    FBindlessTextureManager.FlushPendingUpdates;
    Result := FBindlessTextureManager.DescriptorSet;
  end else
    Result := nil;
end;

function TVulkanRHIDevice.BeginSingleTimeCommands: VkCommandBuffer;
var
  PoolInfo: VkCommandPoolCreateInfo;
  AllocInfo: VkCommandBufferAllocateInfo;
  BeginInfo: VkCommandBufferBeginInfo;
begin
  Result := nil;
  if FDevice = nil then Exit;

  if (FSingleTimeCommandPool = VK_NULL_HANDLE) and Assigned(vkCreateCommandPool) then
  begin
    FillChar(PoolInfo, SizeOf(PoolInfo), 0);
    PoolInfo.sType := VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    PoolInfo.flags := VK_COMMAND_POOL_CREATE_TRANSIENT_BIT or VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    PoolInfo.queueFamilyIndex := FGraphicsQueueFamily;
    CheckVk(vkCreateCommandPool(FDevice, @PoolInfo, nil, @FSingleTimeCommandPool),
      'vkCreateCommandPool(SingleTime)');
  end;
  if FSingleTimeCommandPool = VK_NULL_HANDLE then Exit;

  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
  AllocInfo.commandPool := FSingleTimeCommandPool;
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
  if (FDevice = nil) or (CmdBuf = nil) or (FSingleTimeCommandPool = VK_NULL_HANDLE) then Exit;
  CheckVk(vkEndCommandBuffer(CmdBuf), 'vkEndCommandBuffer(SingleTime)');

  LocalCmd := CmdBuf;
  FillChar(SubmitInfo, SizeOf(SubmitInfo), 0);
  SubmitInfo.sType := VK_STRUCTURE_TYPE_SUBMIT_INFO;
  SubmitInfo.commandBufferCount := 1;
  SubmitInfo.pCommandBuffers := @LocalCmd;

  CheckVk(vkQueueSubmit(FGraphicsQueue, 1, @SubmitInfo, VK_NULL_HANDLE), 'vkQueueSubmit(SingleTime)');
  CheckVk(vkQueueWaitIdle(FGraphicsQueue), 'vkQueueWaitIdle(SingleTime)');

  vkFreeCommandBuffers(FDevice, FSingleTimeCommandPool, 1, @LocalCmd);
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

function TVulkanRHIDevice.GetValidationMessageCount: Integer;
begin
  {$ifndef CASTLE_DISABLE_THREADS}
  if FValidationLock <> nil then
    TCriticalSection(FValidationLock).Acquire;
  try
  {$endif}
    Result := Length(FValidationMessages);
  {$ifndef CASTLE_DISABLE_THREADS}
  finally
    if FValidationLock <> nil then
      TCriticalSection(FValidationLock).Release;
  end;
  {$endif}
end;

procedure TVulkanRHIDevice.RecordValidationCallbackMessage(
  const ASeverity, AMessageTypes: VkFlags;
  const AMessageIdName, AMessage: String);
const
  MaxCapturedValidationMessages = 256;
var
  SeverityTag, TypeTag, FormattedEntry: String;
  Idx: Integer;
begin
  if (ASeverity and VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) <> 0 then
    SeverityTag := 'ERROR'
  else if (ASeverity and VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) <> 0 then
    SeverityTag := 'WARNING'
  else if (ASeverity and VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) <> 0 then
    SeverityTag := 'INFO'
  else
    SeverityTag := 'VERBOSE';

  if (AMessageTypes and VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT) <> 0 then
    TypeTag := 'VALIDATION'
  else if (AMessageTypes and VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT) <> 0 then
    TypeTag := 'PERFORMANCE'
  else
    TypeTag := 'GENERAL';

  if AMessageIdName <> '' then
    FormattedEntry := Format('[%s/%s] (%s) %s', [SeverityTag, TypeTag, AMessageIdName, AMessage])
  else
    FormattedEntry := Format('[%s/%s] %s', [SeverityTag, TypeTag, AMessage]);

  {$ifndef CASTLE_DISABLE_THREADS}
  if FValidationLock <> nil then
    TCriticalSection(FValidationLock).Acquire;
  try
  {$endif}
    if (ASeverity and VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) <> 0 then
      Inc(FValidationErrorCount)
    else if (ASeverity and VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) <> 0 then
      Inc(FValidationWarningCount)
    else
      Inc(FValidationInfoCount);

    if Length(FValidationMessages) < MaxCapturedValidationMessages then
    begin
      Idx := Length(FValidationMessages);
      SetLength(FValidationMessages, Idx + 1);
      FValidationMessages[Idx] := FormattedEntry;
    end;
  {$ifndef CASTLE_DISABLE_THREADS}
  finally
    if FValidationLock <> nil then
      TCriticalSection(FValidationLock).Release;
  end;
  {$endif}

  if (ASeverity and (VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT or
                     VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT)) <> 0 then
    WritelnWarning('Vulkan/Validation', '%s', [FormattedEntry])
  else
    WritelnLog('Vulkan/Validation', '%s', [FormattedEntry]);
end;

function TVulkanRHIDevice.SubmitDebugUtilsMessage(
  const ASeverity, AMessageTypes: VkFlags;
  const AMessageIdName, AMessage: String): Boolean;
var
  AnsiId, AnsiMsg: AnsiString;
  CbData: VkDebugUtilsMessengerCallbackDataEXT;
begin
  if (FInstance <> nil) and FDebugUtilsActive and
     (FDebugMessenger <> VK_NULL_HANDLE) and Assigned(vkSubmitDebugUtilsMessageEXT) then
  begin
    AnsiId := AnsiString(AMessageIdName);
    AnsiMsg := AnsiString(AMessage);
    FillChar(CbData, SizeOf(CbData), 0);
    CbData.sType := VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CALLBACK_DATA_EXT;
    if AnsiId <> '' then
      CbData.pMessageIdName := PAnsiChar(AnsiId);
    CbData.pMessage := PAnsiChar(AnsiMsg);
    vkSubmitDebugUtilsMessageEXT(FInstance, ASeverity, AMessageTypes, @CbData);
    Exit(True);
  end;

  RecordValidationCallbackMessage(ASeverity, AMessageTypes, AMessageIdName, AMessage);
  Result := False;
end;

procedure TVulkanRHIDevice.ResetValidationCounters;
begin
  {$ifndef CASTLE_DISABLE_THREADS}
  if FValidationLock <> nil then
    TCriticalSection(FValidationLock).Acquire;
  try
  {$endif}
    FValidationErrorCount := 0;
    FValidationWarningCount := 0;
    FValidationInfoCount := 0;
    SetLength(FValidationMessages, 0);
  {$ifndef CASTLE_DISABLE_THREADS}
  finally
    if FValidationLock <> nil then
      TCriticalSection(FValidationLock).Release;
  end;
  {$endif}
end;

function TVulkanRHIDevice.GetValidationMessage(const AIndex: Integer): String;
begin
  Result := '';
  {$ifndef CASTLE_DISABLE_THREADS}
  if FValidationLock <> nil then
    TCriticalSection(FValidationLock).Acquire;
  try
  {$endif}
    if (AIndex >= 0) and (AIndex < Length(FValidationMessages)) then
      Result := FValidationMessages[AIndex];
  {$ifndef CASTLE_DISABLE_THREADS}
  finally
    if FValidationLock <> nil then
      TCriticalSection(FValidationLock).Release;
  end;
  {$endif}
end;

function TVulkanRHIDevice.GetValidationMessagesReport: String;
var
  I: Integer;
begin
  {$ifndef CASTLE_DISABLE_THREADS}
  if FValidationLock <> nil then
    TCriticalSection(FValidationLock).Acquire;
  try
  {$endif}
    Result := Format(
      'Vulkan Validation Report (layerActive=%s, messengerActive=%s, errors=%d, warnings=%d):',
      [BoolToStr(FValidationLayerActive, True),
       BoolToStr(FDebugMessenger <> VK_NULL_HANDLE, True),
       FValidationErrorCount,
       FValidationWarningCount]);
    for I := 0 to High(FValidationMessages) do
      Result := Result + LineEnding + '  ' + FValidationMessages[I];
  {$ifndef CASTLE_DISABLE_THREADS}
  finally
    if FValidationLock <> nil then
      TCriticalSection(FValidationLock).Release;
  end;
  {$endif}
end;

procedure TVulkanRHIDevice.AssertZeroValidationErrors(const AContext: String);
var
  CtxPrefix: String;
begin
  if (FValidationErrorCount = 0) and
     ((not FStrictValidationGate) or (FValidationWarningCount = 0)) then
    Exit;

  if AContext <> '' then
    CtxPrefix := '[' + AContext + '] '
  else
    CtxPrefix := '';

  raise ERHIError.CreateFmt(
    '%sVulkan validation gate failed (%d errors, %d warnings; strict=%s). %s',
    [CtxPrefix, FValidationErrorCount, FValidationWarningCount,
     BoolToStr(FStrictValidationGate, True), GetValidationMessagesReport]);
end;

function TVulkanRHIDevice.SetDebugObjectName(const AObjectType: VkObjectType;
  const AObjectHandle: UInt64; const AObjectName: String): Boolean;
var
  NameInfo: VkDebugUtilsObjectNameInfoEXT;
  AnsiName: AnsiString;
begin
  Result := False;
  if (AObjectHandle = 0) or (AObjectName = '') then
    Exit;

  Inc(FDebugObjectsNamedCount);
  FLastNamedDebugObject := AObjectName;

  if FDebugUtilsActive and (FDevice <> nil) and Assigned(vkSetDebugUtilsObjectNameEXT) then
  begin
    AnsiName := AnsiString(AObjectName);
    FillChar(NameInfo, SizeOf(NameInfo), 0);
    NameInfo.sType := VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;
    NameInfo.objectType := AObjectType;
    NameInfo.objectHandle := AObjectHandle;
    NameInfo.pObjectName := PAnsiChar(AnsiName);
    Result := vkSetDebugUtilsObjectNameEXT(FDevice, @NameInfo) = VK_SUCCESS;
  end else
  if FDevice = nil then
    Result := True;
end;

procedure TVulkanRHIDevice.BeginQueueDebugLabel(const ALabelName: String;
  const AColor: TCastleColor);
var
  LabelInfo: VkDebugUtilsLabelEXT;
  AnsiLabel: AnsiString;
begin
  if FDebugUtilsActive and (FGraphicsQueue <> nil) and Assigned(vkQueueBeginDebugUtilsLabelEXT) then
  begin
    AnsiLabel := AnsiString(ALabelName);
    FillChar(LabelInfo, SizeOf(LabelInfo), 0);
    LabelInfo.sType := VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT;
    LabelInfo.pLabelName := PAnsiChar(AnsiLabel);
    Move(AColor.Data, LabelInfo.color, SizeOf(Single) * 4);
    vkQueueBeginDebugUtilsLabelEXT(FGraphicsQueue, @LabelInfo);
  end;
end;

procedure TVulkanRHIDevice.EndQueueDebugLabel;
begin
  if FDebugUtilsActive and (FGraphicsQueue <> nil) and Assigned(vkQueueEndDebugUtilsLabelEXT) then
    vkQueueEndDebugUtilsLabelEXT(FGraphicsQueue);
end;

procedure TVulkanRHIDevice.InsertQueueDebugLabel(const ALabelName: String;
  const AColor: TCastleColor);
var
  LabelInfo: VkDebugUtilsLabelEXT;
  AnsiLabel: AnsiString;
begin
  if FDebugUtilsActive and (FGraphicsQueue <> nil) and Assigned(vkQueueInsertDebugUtilsLabelEXT) then
  begin
    AnsiLabel := AnsiString(ALabelName);
    FillChar(LabelInfo, SizeOf(LabelInfo), 0);
    LabelInfo.sType := VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT;
    LabelInfo.pLabelName := PAnsiChar(AnsiLabel);
    Move(AColor.Data, LabelInfo.color, SizeOf(Single) * 4);
    vkQueueInsertDebugUtilsLabelEXT(FGraphicsQueue, @LabelInfo);
  end;
end;

{$endif read_implementation}
