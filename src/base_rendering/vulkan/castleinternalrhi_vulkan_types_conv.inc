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
const
  FNV1aOffsetBasis64 = UInt64($CBF29CE484222325);
  FNV1aPrime64 = UInt64($00000100000001B3);

function HalfFloatToFloat(const AHalf: Word): Single;
var
  SignBit, ExpBits, MantBits, OutBits: Cardinal;
begin
  SignBit := Cardinal(AHalf and $8000) shl 16;
  ExpBits := (AHalf shr 10) and $1F;
  MantBits := AHalf and $03FF;

  if ExpBits = 0 then
  begin
    if MantBits = 0 then
      OutBits := SignBit
    else
    begin
      ExpBits := 1;
      while (MantBits and $0400) = 0 do
      begin
        MantBits := MantBits shl 1;
        Dec(ExpBits);
      end;
      MantBits := MantBits and $03FF;
      OutBits := SignBit or ((ExpBits + (127 - 15)) shl 23) or (MantBits shl 13);
    end;
  end else
  if ExpBits = 31 then
    OutBits := SignBit or $7F800000 or (MantBits shl 13)
  else
    OutBits := SignBit or ((ExpBits + (127 - 15)) shl 23) or (MantBits shl 13);

  Move(OutBits, Result, SizeOf(Single));
end;

function FloatToHalfFloat(const AValue: Single): Word;
var
  Bits, SignBit, Mantissa: Cardinal;
  ExpUnbiased, HalfExp: Integer;
begin
  Move(AValue, Bits, SizeOf(Cardinal));
  SignBit := (Bits shr 16) and $8000;
  ExpUnbiased := Integer((Bits shr 23) and $FF) - 127;
  Mantissa := Bits and $007FFFFF;

  if ExpUnbiased = 128 then
  begin
    { Inf or NaN }
    if Mantissa <> 0 then
      Result := Word(SignBit or $7E00)
    else
      Result := Word(SignBit or $7C00);
    Exit;
  end;

  if ExpUnbiased > 15 then
  begin
    { Clamp overflow to max finite half-float (65504.0) so HDR values never become Inf }
    Result := Word(SignBit or $7BFF);
    Exit;
  end;

  if ExpUnbiased >= -14 then
  begin
    HalfExp := ExpUnbiased + 15;
    Result := Word(SignBit or (Cardinal(HalfExp) shl 10) or ((Mantissa + $00001000) shr 13));
    if (Mantissa + $00001000) >= $00800000 then
      Result := Word(SignBit or (Cardinal(HalfExp + 1) shl 10));
    Exit;
  end;

  if ExpUnbiased >= -24 then
  begin
    Mantissa := Mantissa or $00800000;
    Result := Word(SignBit or (Mantissa shr Cardinal(-14 - ExpUnbiased + 13)));
    Exit;
  end;

  Result := Word(SignBit);
end;

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
  { CombinedImageSampler bindless arrays also count against per-stage and per-pipeline-layout
    sampler limits (VUID-VkPipelineLayoutCreateInfo-descriptorType-03022 / 03036, e.g. 96 on Metal).
    Reserve 24 slots of headroom for scene/material/effect sets when hardware limit > 32. }
  if AProps.maxPerStageDescriptorUpdateAfterBindSamplers > 0 then
  begin
    if AProps.maxPerStageDescriptorUpdateAfterBindSamplers > 32 then
      HwLimit := Min(HwLimit, AProps.maxPerStageDescriptorUpdateAfterBindSamplers - 24)
    else
      HwLimit := Min(HwLimit, AProps.maxPerStageDescriptorUpdateAfterBindSamplers);
  end;
  if AProps.maxDescriptorSetUpdateAfterBindSamplers > 0 then
  begin
    if AProps.maxDescriptorSetUpdateAfterBindSamplers > 32 then
      HwLimit := Min(HwLimit, AProps.maxDescriptorSetUpdateAfterBindSamplers - 24)
    else
      HwLimit := Min(HwLimit, AProps.maxDescriptorSetUpdateAfterBindSamplers);
  end;

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
  HashBytesFNV1a(Result, ADesc.DepthAttachmentFormat, SizeOf(ADesc.DepthAttachmentFormat));
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
  I, Count: Integer;
begin
  Result := FNV1aOffsetBasis64;
  HashUInt64FNV1a(Result, PtrUInt(ADesc.VertexShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.FragmentShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.GeometryShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.TaskShader));
  HashUInt64FNV1a(Result, PtrUInt(ADesc.MeshShader));
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

  Count := Length(ADesc.DescriptorSetLayouts);
  HashBytesFNV1a(Result, Count, SizeOf(Count));
  for I := 0 to High(ADesc.DescriptorSetLayouts) do
    HashUInt64FNV1a(Result, PtrUInt(ADesc.DescriptorSetLayouts[I]));

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

function RHIToVkFilter(const AFilter: TRHISamplerFilter): VkFilter;
begin
  case AFilter of
    sfNearest: Result := VK_FILTER_NEAREST;
    else       Result := VK_FILTER_LINEAR;
  end;
end;

function RHIToVkMipmapMode(const AFilter: TRHISamplerFilter): VkSamplerMipmapMode;
begin
  case AFilter of
    sfNearest: Result := VK_SAMPLER_MIPMAP_MODE_NEAREST;
    else       Result := VK_SAMPLER_MIPMAP_MODE_LINEAR;
  end;
end;

function RHIToVkAddressMode(const AMode: TRHISamplerAddressMode): VkSamplerAddressMode;
begin
  case AMode of
    amRepeat:         Result := VK_SAMPLER_ADDRESS_MODE_REPEAT;
    amMirroredRepeat: Result := VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT;
    amClampToEdge:    Result := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    amClampToBorder:  Result := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER;
    else              Result := VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
  end;
end;

function BuildVkSamplerCreateInfo(const ADesc: TRHISamplerDesc;
  const AMaxDeviceAnisotropy: Single): VkSamplerCreateInfo;
var
  ClampedMaxAniso: Single;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.sType := VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
  Result.magFilter := RHIToVkFilter(ADesc.MagFilter);
  Result.minFilter := RHIToVkFilter(ADesc.MinFilter);
  Result.mipmapMode := RHIToVkMipmapMode(ADesc.MipFilter);
  Result.addressModeU := RHIToVkAddressMode(ADesc.AddressModeU);
  Result.addressModeV := RHIToVkAddressMode(ADesc.AddressModeV);
  Result.addressModeW := RHIToVkAddressMode(ADesc.AddressModeW);
  Result.mipLodBias := 0.0;
  ClampedMaxAniso := Max(1.0, AMaxDeviceAnisotropy);
  if ADesc.MaxAnisotropy > 1.0 then
  begin
    Result.anisotropyEnable := VK_TRUE;
    Result.maxAnisotropy := EnsureRange(ADesc.MaxAnisotropy, 1.0, ClampedMaxAniso);
  end else
  begin
    Result.anisotropyEnable := VK_FALSE;
    Result.maxAnisotropy := 1.0;
  end;
  if ADesc.CompareEnable then
  begin
    Result.compareEnable := VK_TRUE;
    Result.compareOp := RHIToVkCompareOp(ADesc.CompareOp);
  end else
  begin
    Result.compareEnable := VK_FALSE;
    Result.compareOp := VK_COMPARE_OP_ALWAYS;
  end;
  Result.minLod := Max(0.0, ADesc.MinLod);
  Result.maxLod := Max(Result.minLod, ADesc.MaxLod);
  Result.borderColor := VK_BORDER_COLOR_INT_OPAQUE_BLACK;
  Result.unnormalizedCoordinates := VK_FALSE;
end;

function RHIToVkBlendFactor(const Factor: TRHIBlendFactor): Integer;
begin
  case Factor of
    bfZero:                  Result := VK_BLEND_FACTOR_ZERO;
    bfOne:                   Result := VK_BLEND_FACTOR_ONE;
    bfSrcColor:              Result := VK_BLEND_FACTOR_SRC_COLOR;
    bfOneMinusSrcColor:      Result := VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR;
    bfDstColor:              Result := VK_BLEND_FACTOR_DST_COLOR;
    bfOneMinusDstColor:      Result := VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR;
    bfSrcAlpha:              Result := VK_BLEND_FACTOR_SRC_ALPHA;
    bfOneMinusSrcAlpha:      Result := VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    bfDstAlpha:              Result := VK_BLEND_FACTOR_DST_ALPHA;
    bfOneMinusDstAlpha:      Result := VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA;
    bfConstantColor:         Result := VK_BLEND_FACTOR_CONSTANT_COLOR;
    bfOneMinusConstantColor: Result := VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR;
    bfConstantAlpha:         Result := VK_BLEND_FACTOR_CONSTANT_ALPHA;
    bfOneMinusConstantAlpha: Result := VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA;
    bfSrcAlphaSaturate:      Result := VK_BLEND_FACTOR_SRC_ALPHA_SATURATE;
    else                     Result := VK_BLEND_FACTOR_ONE;
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
  if ssTask in Stages then Result := Result or VK_SHADER_STAGE_TASK_BIT_EXT;
  if ssMesh in Stages then Result := Result or VK_SHADER_STAGE_MESH_BIT_EXT;
  if ssRayGen in Stages then Result := Result or VK_SHADER_STAGE_RAYGEN_BIT_KHR;
  if ssAnyHit in Stages then Result := Result or VK_SHADER_STAGE_ANY_HIT_BIT_KHR;
  if ssClosestHit in Stages then Result := Result or VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR;
  if ssMiss in Stages then Result := Result or VK_SHADER_STAGE_MISS_BIT_KHR;
  if ssIntersection in Stages then Result := Result or VK_SHADER_STAGE_INTERSECTION_BIT_KHR;
  if ssCallable in Stages then Result := Result or VK_SHADER_STAGE_CALLABLE_BIT_KHR;
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

function SelectVulkanSurfaceFormat(const AAvailableFormats: array of VkSurfaceFormatKHR;
  out ARHIFormat: TRHIPixelFormat): VkSurfaceFormatKHR;

  function TryMatch(const AVkFmt: VkFormat; const AColorSpace: VkColorSpaceKHR;
    const AMappedFmt: TRHIPixelFormat): Boolean;
  var
    J: Integer;
  begin
    for J := Low(AAvailableFormats) to High(AAvailableFormats) do
      if (AAvailableFormats[J].format = AVkFmt) and
         (AAvailableFormats[J].colorSpace = AColorSpace) then
      begin
        Result := True;
        SelectVulkanSurfaceFormat := AAvailableFormats[J];
        ARHIFormat := AMappedFmt;
        Exit;
      end;
    Result := False;
  end;

begin
  Result.format := VK_FORMAT_B8G8R8A8_UNORM;
  Result.colorSpace := VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
  ARHIFormat := pfBGRA8_UNorm;

  if Length(AAvailableFormats) = 0 then
    Exit;
  if (Length(AAvailableFormats) = 1) and (AAvailableFormats[0].format = VK_FORMAT_UNDEFINED) then
    Exit;

  if TryMatch(VK_FORMAT_B8G8R8A8_UNORM, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR, pfBGRA8_UNorm) then Exit;
  if TryMatch(VK_FORMAT_R8G8B8A8_UNORM, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR, pfRGBA8_UNorm) then Exit;
  if TryMatch(VK_FORMAT_B8G8R8A8_SRGB,  VK_COLOR_SPACE_SRGB_NONLINEAR_KHR, pfBGRA8_sRGB) then Exit;
  if TryMatch(VK_FORMAT_R8G8B8A8_SRGB,  VK_COLOR_SPACE_SRGB_NONLINEAR_KHR, pfRGBA8_sRGB) then Exit;

  Result := AAvailableFormats[0];
  case Result.format of
    VK_FORMAT_R8G8B8A8_UNORM: ARHIFormat := pfRGBA8_UNorm;
    VK_FORMAT_B8G8R8A8_SRGB:  ARHIFormat := pfBGRA8_sRGB;
    VK_FORMAT_R8G8B8A8_SRGB:  ARHIFormat := pfRGBA8_sRGB;
    else                      ARHIFormat := pfBGRA8_UNorm;
  end;
end;

function SelectVulkanPresentMode(const AAvailableModes: array of VkPresentModeKHR;
  const APreferLowLatencyNoTear: Boolean): VkPresentModeKHR;
var
  I: Integer;
begin
  Result := VK_PRESENT_MODE_FIFO_KHR;
  if Length(AAvailableModes) = 0 then
    Exit;

  if APreferLowLatencyNoTear then
    for I := Low(AAvailableModes) to High(AAvailableModes) do
      if AAvailableModes[I] = VK_PRESENT_MODE_MAILBOX_KHR then
        Exit(VK_PRESENT_MODE_MAILBOX_KHR);

  for I := Low(AAvailableModes) to High(AAvailableModes) do
    if AAvailableModes[I] = VK_PRESENT_MODE_FIFO_KHR then
      Exit(VK_PRESENT_MODE_FIFO_KHR);

  Result := AAvailableModes[0];
end;

function SelectVulkanCompositeAlpha(const ASupportedCompositeAlpha: VkFlags): Integer;
begin
  if (ASupportedCompositeAlpha = 0) or
     ((ASupportedCompositeAlpha and VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR) <> 0) then
    Result := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
  else if (ASupportedCompositeAlpha and VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR) <> 0 then
    Result := VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR
  else if (ASupportedCompositeAlpha and VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR) <> 0 then
    Result := VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR
  else if (ASupportedCompositeAlpha and VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR) <> 0 then
    Result := VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR
  else
    Result := VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
end;

class function TVulkanPortabilitySubsetCaps.DefaultFullVulkan: TVulkanPortabilitySubsetCaps;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Active := False;
  Result.ConstantAlphaColorBlendFactors := True;
  Result.Events := True;
  Result.ImageViewFormatReinterpretation := True;
  Result.ImageViewFormatSwizzle := True;
  Result.ImageView2DOn3DImage := True;
  Result.MultisampleArrayImage := True;
  Result.MutableComparisonSamplers := True;
  Result.PointPolygons := True;
  Result.SamplerMipLodBias := True;
  Result.SeparateStencilMaskRef := True;
  Result.TriangleFans := True;
  Result.VertexAttributeAccessBeyondStride := True;
  Result.MinVertexInputBindingStrideAlignment := 1;
end;

class function TVulkanPortabilitySubsetCaps.DefaultMoltenVK: TVulkanPortabilitySubsetCaps;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Active := True;
  Result.ConstantAlphaColorBlendFactors := False;
  Result.Events := True;
  Result.ImageViewFormatReinterpretation := True;
  Result.ImageViewFormatSwizzle := True;
  Result.ImageView2DOn3DImage := False;
  Result.MultisampleArrayImage := True;
  Result.MutableComparisonSamplers := False;
  Result.PointPolygons := False;
  Result.SamplerMipLodBias := False;
  Result.SeparateStencilMaskRef := True;
  Result.TriangleFans := False;
  Result.VertexAttributeAccessBeyondStride := True;
  Result.MinVertexInputBindingStrideAlignment := 4;
end;

function SelectVulkanSurfaceTransform(const ASupportedTransforms: VkFlags;
  const ACurrentTransform: Integer): Integer;
var
  BitIdx: Integer;
  CandidateBit: VkFlags;
begin
  if (ACurrentTransform > 0) and
     ((Cardinal(ACurrentTransform) and (Cardinal(ACurrentTransform) - 1)) = 0) and
     ((ASupportedTransforms = 0) or ((ASupportedTransforms and Cardinal(ACurrentTransform)) <> 0)) then
    Exit(ACurrentTransform);

  if (ASupportedTransforms = 0) or
     ((ASupportedTransforms and VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR) <> 0) then
    Exit(VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR);

  for BitIdx := 0 to 30 do
  begin
    CandidateBit := VkFlags(1) shl BitIdx;
    if (ASupportedTransforms and CandidateBit) <> 0 then
      Exit(Integer(CandidateBit));
  end;

  Result := VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
end;

function ClassifyVulkanVendor(const AVendorId: Cardinal;
  const ADriverId: Integer; const ADeviceName: String): TVulkanVendorID;
var
  LowerName: String;
begin
  case AVendorId of
    $10DE: Exit(vvNVIDIA);
    $1002, $1022: Exit(vvAMD);
    $8086, $8087: Exit(vvIntel);
    $106B: Exit(vvApple);
    $13B5: Exit(vvARM);
    $5143: Exit(vvQualcomm);
    $1010: Exit(vvImgTec);
    $14E4: Exit(vvBroadcom);
    $144D: Exit(vvSamsung);
    $1414: Exit(vvMicrosoft);
    $10005: Exit(vvMesa);
  end;

  case ADriverId of
    VK_DRIVER_ID_NVIDIA_PROPRIETARY,
    VK_DRIVER_ID_MESA_NVK:
      Exit(vvNVIDIA);
    VK_DRIVER_ID_AMD_PROPRIETARY,
    VK_DRIVER_ID_AMD_OPEN_SOURCE,
    VK_DRIVER_ID_MESA_RADV:
      Exit(vvAMD);
    VK_DRIVER_ID_INTEL_PROPRIETARY_WINDOWS,
    VK_DRIVER_ID_INTEL_OPEN_SOURCE_MESA:
      Exit(vvIntel);
    VK_DRIVER_ID_MOLTENVK,
    VK_DRIVER_ID_MESA_AGXV:
      Exit(vvApple);
    VK_DRIVER_ID_ARM_PROPRIETARY,
    VK_DRIVER_ID_MESA_PANVK:
      Exit(vvARM);
    VK_DRIVER_ID_QUALCOMM_PROPRIETARY,
    VK_DRIVER_ID_MESA_TURNIP:
      Exit(vvQualcomm);
    VK_DRIVER_ID_IMAGINATION_PROPRIETARY:
      Exit(vvImgTec);
    VK_DRIVER_ID_MESA_V3DV:
      Exit(vvBroadcom);
    VK_DRIVER_ID_SAMSUNG_PROPRIETARY:
      Exit(vvSamsung);
    VK_DRIVER_ID_MESA_LLVMPIPE,
    VK_DRIVER_ID_GOOGLE_SWIFTSHADER:
      Exit(vvMesa);
  end;

  LowerName := LowerCase(ADeviceName);
  if (Pos('llvmpipe', LowerName) > 0) or (Pos('lavapipe', LowerName) > 0) or
     (Pos('swiftshader', LowerName) > 0) then
    Result := vvMesa
  else if (Pos('geforce', LowerName) > 0) or (Pos('nvidia', LowerName) > 0) or
          (Pos('quadro', LowerName) > 0) then
    Result := vvNVIDIA
  else if (Pos('radeon', LowerName) > 0) or (Pos('radv', LowerName) > 0) then
    Result := vvAMD
  else if (Pos('intel', LowerName) > 0) or (Pos('arc', LowerName) > 0) then
    Result := vvIntel
  else if (Pos('apple', LowerName) > 0) or (Pos('moltenvk', LowerName) > 0) then
    Result := vvApple
  else if (Pos('mali', LowerName) > 0) or (Pos('immortalis', LowerName) > 0) then
    Result := vvARM
  else if (Pos('adreno', LowerName) > 0) or (Pos('turnip', LowerName) > 0) then
    Result := vvQualcomm
  else if (Pos('powervr', LowerName) > 0) then
    Result := vvImgTec
  else
    Result := vvUnknown;
end;

function GetVulkanVendorName(const AVendor: TVulkanVendorID): String;
begin
  case AVendor of
    vvNVIDIA:    Result := 'NVIDIA';
    vvAMD:       Result := 'AMD';
    vvIntel:     Result := 'Intel';
    vvApple:     Result := 'Apple';
    vvARM:       Result := 'ARM Mali';
    vvQualcomm:  Result := 'Qualcomm Adreno';
    vvImgTec:    Result := 'Imagination PowerVR';
    vvBroadcom:  Result := 'Broadcom VideoCore';
    vvSamsung:   Result := 'Samsung Xclipse';
    vvMesa:      Result := 'Mesa Software';
    vvMicrosoft: Result := 'Microsoft';
    else         Result := 'Unknown';
  end;
end;

function ScorePhysicalDeviceForSelection(const ADeviceIndex: Cardinal;
  const ADeviceName: String; const AVendorId, ADeviceType, AApiVersion: Cardinal;
  const ASupportsSurface: Boolean;
  const ADeviceFilter: String;
  const AVendorFilter: String): Int64;
var
  TrimmedDev, TrimmedVendor, IdxToken: String;
  ParsedIdx: Integer;
  VendorKind: TVulkanVendorID;
  VendorMatched: Boolean;
begin
  TrimmedDev := LowerCase(Trim(ADeviceFilter));
  if TrimmedDev <> '' then
  begin
    IdxToken := TrimmedDev;
    if (IdxToken <> '') and (IdxToken[1] = '#') then
      Delete(IdxToken, 1, 1);
    ParsedIdx := StrToIntDef(IdxToken, -1);
    if ParsedIdx >= 0 then
    begin
      if Cardinal(ParsedIdx) <> ADeviceIndex then
        Exit(-1);
    end else
    if Pos(TrimmedDev, LowerCase(ADeviceName)) = 0 then
      Exit(-1);
  end;

  TrimmedVendor := LowerCase(Trim(AVendorFilter));
  if TrimmedVendor <> '' then
  begin
    VendorKind := ClassifyVulkanVendor(AVendorId, 0, ADeviceName);
    if (TrimmedVendor = 'nvidia') or (TrimmedVendor = 'nv') then
      VendorMatched := VendorKind = vvNVIDIA
    else if (TrimmedVendor = 'amd') or (TrimmedVendor = 'radv') or (TrimmedVendor = 'radeon') then
      VendorMatched := VendorKind = vvAMD
    else if (TrimmedVendor = 'intel') or (TrimmedVendor = 'anv') then
      VendorMatched := VendorKind = vvIntel
    else if (TrimmedVendor = 'apple') or (TrimmedVendor = 'metal') or (TrimmedVendor = 'moltenvk') then
      VendorMatched := VendorKind = vvApple
    else if (TrimmedVendor = 'arm') or (TrimmedVendor = 'mali') then
      VendorMatched := VendorKind = vvARM
    else if (TrimmedVendor = 'qualcomm') or (TrimmedVendor = 'adreno') or (TrimmedVendor = 'turnip') then
      VendorMatched := VendorKind = vvQualcomm
    else if (TrimmedVendor = 'imgtec') or (TrimmedVendor = 'powervr') then
      VendorMatched := VendorKind = vvImgTec
    else if (TrimmedVendor = 'broadcom') or (TrimmedVendor = 'v3dv') then
      VendorMatched := VendorKind = vvBroadcom
    else if (TrimmedVendor = 'samsung') or (TrimmedVendor = 'xclipse') then
      VendorMatched := VendorKind = vvSamsung
    else if (TrimmedVendor = 'mesa') or (TrimmedVendor = 'lavapipe') or
            (TrimmedVendor = 'llvmpipe') or (TrimmedVendor = 'cpu') or (TrimmedVendor = 'software') then
      VendorMatched := (VendorKind = vvMesa) or (ADeviceType = VK_PHYSICAL_DEVICE_TYPE_CPU)
    else if (TrimmedVendor = 'microsoft') or (TrimmedVendor = 'dozen') then
      VendorMatched := VendorKind = vvMicrosoft
    else
      VendorMatched := Pos(TrimmedVendor, LowerCase(GetVulkanVendorName(VendorKind))) > 0;

    if not VendorMatched then
      Exit(-1);
  end;

  Result := 0;
  if ASupportsSurface then
    Inc(Result, 100000);
  if AApiVersion >= VK_API_VERSION_1_1 then
    Inc(Result, 50000);

  case ADeviceType of
    VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:   Inc(Result, 4000);
    VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU: Inc(Result, 3000);
    VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:    Inc(Result, 2000);
    VK_PHYSICAL_DEVICE_TYPE_OTHER:          Inc(Result, 1000);
    VK_PHYSICAL_DEVICE_TYPE_CPU:            Inc(Result, 500);
  end;

  if AApiVersion >= VK_API_VERSION_1_3 then
    Inc(Result, 100)
  else if AApiVersion >= VK_API_VERSION_1_2 then
    Inc(Result, 50);
end;

procedure ResolvePortabilitySubsetConfig(const AHasPortabilitySubsetExt: Boolean;
  const AFeatures: VkPhysicalDevicePortabilitySubsetFeaturesKHR;
  const AProps: VkPhysicalDevicePortabilitySubsetPropertiesKHR;
  out ACaps: TVulkanPortabilitySubsetCaps;
  out ARequiredExtensions: TAnsiStringArray);
begin
  SetLength(ARequiredExtensions, 0);
  if not AHasPortabilitySubsetExt then
  begin
    ACaps := TVulkanPortabilitySubsetCaps.DefaultFullVulkan;
    Exit;
  end;

  { Per VUID-VkDeviceCreateInfo-pProperties-04451, if VK_KHR_portability_subset is advertised
    in vkEnumerateDeviceExtensionProperties, it MUST be included in ppEnabledExtensionNames. }
  SetLength(ARequiredExtensions, 1);
  ARequiredExtensions[0] := VK_KHR_portability_subset;

  FillChar(ACaps, SizeOf(ACaps), 0);
  ACaps.Active := True;
  ACaps.ConstantAlphaColorBlendFactors := AFeatures.constantAlphaColorBlendFactors = VK_TRUE;
  ACaps.Events := AFeatures.events = VK_TRUE;
  ACaps.ImageViewFormatReinterpretation := AFeatures.imageViewFormatReinterpretation = VK_TRUE;
  ACaps.ImageViewFormatSwizzle := AFeatures.imageViewFormatSwizzle = VK_TRUE;
  ACaps.ImageView2DOn3DImage := AFeatures.imageView2DOn3DImage = VK_TRUE;
  ACaps.MultisampleArrayImage := AFeatures.multisampleArrayImage = VK_TRUE;
  ACaps.MutableComparisonSamplers := AFeatures.mutableComparisonSamplers = VK_TRUE;
  ACaps.PointPolygons := AFeatures.pointPolygons = VK_TRUE;
  ACaps.SamplerMipLodBias := AFeatures.samplerMipLodBias = VK_TRUE;
  ACaps.SeparateStencilMaskRef := AFeatures.separateStencilMaskRef = VK_TRUE;
  ACaps.TriangleFans := AFeatures.triangleFans = VK_TRUE;
  ACaps.VertexAttributeAccessBeyondStride := AFeatures.vertexAttributeAccessBeyondStride = VK_TRUE;
  ACaps.MinVertexInputBindingStrideAlignment := Max(Cardinal(1), AProps.minVertexInputBindingStrideAlignment);
end;

function AdaptPipelineDescForPortabilitySubset(const ADesc: TRHIGraphicsPipelineDesc;
  const APortability: TVulkanPortabilitySubsetCaps): TRHIGraphicsPipelineDesc;

  function AdaptColorBlendFactor(const AFactor: TRHIBlendFactor): TRHIBlendFactor;
  begin
    case AFactor of
      bfConstantAlpha:         Result := bfConstantColor;
      bfOneMinusConstantAlpha: Result := bfOneMinusConstantColor;
      else                     Result := AFactor;
    end;
  end;

var
  I: Integer;
  AlignMask, AlignedStride: Cardinal;
  NeedsBindingCopy: Boolean;
begin
  Result := ADesc;
  if not APortability.Active then
    Exit;

  { VUID-VkPipelineRasterizationStateCreateInfo-pointPolygons-04458:
    Metal / MoltenVK lacks polygonMode = VK_POLYGON_MODE_POINT when pointPolygons = VK_FALSE }
  if (not APortability.PointPolygons) and (Result.Rasterizer.PolygonMode = pmPoint) then
    Result.Rasterizer.PolygonMode := pmFill;

  { VUID-VkPipelineColorBlendAttachmentState-constantAlphaColorBlendFactors-04454/04455:
    Metal / MoltenVK forbids CONSTANT_ALPHA / ONE_MINUS_CONSTANT_ALPHA on RGB color blend factors }
  if not APortability.ConstantAlphaColorBlendFactors then
  begin
    Result.BlendState.SrcColorBlendFactor := AdaptColorBlendFactor(Result.BlendState.SrcColorBlendFactor);
    Result.BlendState.DstColorBlendFactor := AdaptColorBlendFactor(Result.BlendState.DstColorBlendFactor);
  end;

  { VUID-VkVertexInputBindingDescription-stride-04456:
    stride must be a multiple of minVertexInputBindingStrideAlignment (typically 4 on Metal) }
  if (APortability.MinVertexInputBindingStrideAlignment > 1) and
     (Length(ADesc.VertexInput.Bindings) > 0) then
  begin
    NeedsBindingCopy := False;
    for I := 0 to High(ADesc.VertexInput.Bindings) do
      if (ADesc.VertexInput.Bindings[I].Stride > 0) and
         ((ADesc.VertexInput.Bindings[I].Stride mod APortability.MinVertexInputBindingStrideAlignment) <> 0) then
      begin
        NeedsBindingCopy := True;
        Break;
      end;

    if NeedsBindingCopy then
    begin
      Result.VertexInput.Bindings := Copy(ADesc.VertexInput.Bindings, 0, Length(ADesc.VertexInput.Bindings));
      AlignMask := APortability.MinVertexInputBindingStrideAlignment;
      for I := 0 to High(Result.VertexInput.Bindings) do
        if (Result.VertexInput.Bindings[I].Stride > 0) and
           ((Result.VertexInput.Bindings[I].Stride mod AlignMask) <> 0) then
        begin
          AlignedStride := ((Result.VertexInput.Bindings[I].Stride + AlignMask - 1) div AlignMask) * AlignMask;
          Result.VertexInput.Bindings[I].Stride := AlignedStride;
        end;
    end;
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
        Stage  := VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
                  VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT or
                  VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
      end;
    rsUnorderedAccess:
      begin
        Layout := VK_IMAGE_LAYOUT_GENERAL;
        Access := VK_ACCESS_SHADER_READ_BIT or VK_ACCESS_SHADER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT or VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
      end;
    rsIndirectRead:
      begin
        Layout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        Access := VK_ACCESS_INDIRECT_COMMAND_READ_BIT or VK_ACCESS_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT or VK_PIPELINE_STAGE_VERTEX_SHADER_BIT;
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
        Stage  := VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT or
                  VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT or
                  VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
      end;
    rsUnorderedAccess:
      begin
        Layout := VK_IMAGE_LAYOUT_GENERAL;
        Access := VK_ACCESS_2_SHADER_READ_BIT or VK_ACCESS_2_SHADER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT or VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
      end;
    rsIndirectRead:
      begin
        Layout := VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        Access := VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT or VK_ACCESS_2_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT or VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT;
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
    rsUnorderedAccess:
      begin
        Access := VK_ACCESS_SHADER_READ_BIT or VK_ACCESS_SHADER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
      end;
    rsIndirectRead:
      begin
        Access := VK_ACCESS_INDIRECT_COMMAND_READ_BIT or VK_ACCESS_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT or
                  VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or
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
    rsUnorderedAccess:
      begin
        Access := VK_ACCESS_2_SHADER_READ_BIT or VK_ACCESS_2_SHADER_WRITE_BIT;
        Stage  := VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
      end;
    rsIndirectRead:
      begin
        Access := VK_ACCESS_2_INDIRECT_COMMAND_READ_BIT or VK_ACCESS_2_SHADER_READ_BIT;
        Stage  := VK_PIPELINE_STAGE_2_DRAW_INDIRECT_BIT or
                  VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT or
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

{$endif read_implementation}
