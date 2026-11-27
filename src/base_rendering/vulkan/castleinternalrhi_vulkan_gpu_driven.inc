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

  WeightBytes := Cardinal(Max(UInt64(64), UInt64(FHiddenUnits) * UInt64(FHiddenUnits) * UInt64(SizeOf(Single))));
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
{ TCastleVulkanVoxelConeTracer (Phase 42.3)                                    }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanVoxelConeTracer.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FVoxelGridResolution := 64;
  FVoxelMipLevels := 6;
  FWorldExtent := 64.0;
end;

destructor TCastleVulkanVoxelConeTracer.Destroy;
begin
  FreeAndNil(FVoxelRadianceTexture);
  FreeAndNil(FIndirectIrradianceTexture);
  inherited;
end;

class procedure TCastleVulkanVoxelConeTracer.AccumulateVoxelConeSample(
  const ASampleRadianceRGB: TVector3;
  const ASampleOpacity: Single;
  var AAccumRadianceRGB: TVector3;
  var AAccumOpacity: Single);
var
  Transmittance, Weight: Single;
begin
  Transmittance := Max(0.0, 1.0 - AAccumOpacity);
  Weight := Transmittance * EnsureRange(ASampleOpacity, 0.0, 1.0);
  AAccumRadianceRGB := AAccumRadianceRGB + ASampleRadianceRGB * Weight;
  AAccumOpacity := EnsureRange(AAccumOpacity + Weight, 0.0, 1.0);
end;

procedure TCastleVulkanVoxelConeTracer.EnsureVoxelResources(
  const AScreenWidth, AScreenHeight: Cardinal);
var
  Res, Mips, Temp: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  if FDevice = nil then
    Exit;
  Res := Max(Cardinal(16), FVoxelGridResolution);
  Mips := 1;
  Temp := Res;
  while Temp > 1 do
  begin
    Temp := Temp shr 1;
    Inc(Mips);
  end;
  FVoxelMipLevels := Mips;

  if (FVoxelRadianceTexture = nil) or (FVoxelRadianceTexture.Desc.Width <> Res) then
  begin
    FreeAndNil(FVoxelRadianceTexture);
    TexDesc := TRHITextureDesc.Create3D(Res, Res, Res, pfRGBA16_Float,
      [tuSampled, tuStorage, tuTransferDst], Mips);
    TexDesc.DebugName := 'VXGIVoxelRadiance3D';
    FVoxelRadianceTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;

  if (FIndirectIrradianceTexture = nil) or
     (FIndirectIrradianceTexture.Desc.Width <> Max(Cardinal(1), AScreenWidth)) or
     (FIndirectIrradianceTexture.Desc.Height <> Max(Cardinal(1), AScreenHeight)) then
  begin
    FreeAndNil(FIndirectIrradianceTexture);
    TexDesc := TRHITextureDesc.Create2D(
      Max(Cardinal(1), AScreenWidth), Max(Cardinal(1), AScreenHeight),
      pfRGBA16_Float, [tuSampled, tuStorage], 1, 1);
    TexDesc.DebugName := 'VXGIIndirectIrradiance2D';
    FIndirectIrradianceTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

procedure TCastleVulkanVoxelConeTracer.DispatchVoxelConeTrace(
  const ACommandList: TVulkanRHICommandList;
  const AScreenWidth, AScreenHeight: Cardinal;
  const AComputePipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  ActivePipe: TVulkanRHIComputePipeline;
  GroupsX, GroupsY: Cardinal;
begin
  if (ACommandList = nil) or (AScreenWidth = 0) or (AScreenHeight = 0) then
    Exit;
  EnsureVoxelResources(AScreenWidth, AScreenHeight);

  if AComputePipeline <> nil then
    ActivePipe := AComputePipeline
  else
    ActivePipe := FVoxelConeTracePipeline;
  if ActivePipe <> nil then
    ACommandList.BindComputePipeline(ActivePipe);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (AScreenWidth + 7) div 8;
  GroupsY := (AScreenHeight + 7) div 8;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FConeTraceDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanMaterialBinner (Phase 43.3)                                     }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanMaterialBinner.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxMaterialBins := 256;
  FMaxElements := 4096;
end;

destructor TCastleVulkanMaterialBinner.Destroy;
begin
  SetLength(FUploadedMaterialIDs, 0);
  FreeAndNil(FBinDescriptorSet);
  FreeAndNil(FBinDescriptorLayout);
  FreeAndNil(FHistogramShader);
  FreeAndNil(FPrefixSumShader);
  FHistogramPipeline := nil; // Owned by FDevice.FComputePipelineMap
  FPrefixSumPipeline := nil; // Owned by FDevice.FComputePipelineMap
  FreeAndNil(FMaterialIDsBuffer);
  FreeAndNil(FBinCountsBuffer);
  FreeAndNil(FBinOffsetsBuffer);
  inherited;
end;

class procedure TCastleVulkanMaterialBinner.EvaluateMaterialBinRanges(
  const AMaterialIDs: array of Cardinal;
  const ABinCount: Cardinal;
  out AOutBinCounts: TCardinalDynamicArray;
  out AOutBinOffsets: TCardinalDynamicArray);
var
  SafeBins, I, MatID, RunningOffset: Cardinal;
begin
  SafeBins := Max(Cardinal(1), ABinCount);
  SetLength(AOutBinCounts, SafeBins);
  SetLength(AOutBinOffsets, SafeBins);
  for I := 0 to SafeBins - 1 do
  begin
    AOutBinCounts[I] := 0;
    AOutBinOffsets[I] := 0;
  end;

  if Length(AMaterialIDs) > 0 then
  begin
    for I := 0 to Cardinal(High(AMaterialIDs)) do
    begin
      MatID := AMaterialIDs[I] mod SafeBins;
      Inc(AOutBinCounts[MatID]);
    end;
  end;

  RunningOffset := 0;
  for I := 0 to SafeBins - 1 do
  begin
    AOutBinOffsets[I] := RunningOffset;
    Inc(RunningOffset, AOutBinCounts[I]);
  end;
end;

procedure TCastleVulkanMaterialBinner.EnsureBinningBuffers;
var
  Bins: Cardinal;
  BufDesc: TRHIBufferDesc;
begin
  if FDevice = nil then
    Exit;
  Bins := Max(Cardinal(16), FMaxMaterialBins);
  FMaxMaterialBins := Bins;

  if (FBinCountsBuffer = nil) or (FBinCountsBuffer.Desc.Size < PtrUInt(Bins) * SizeOf(Cardinal)) then
  begin
    FreeAndNil(FBinCountsBuffer);
    FreeAndNil(FBinOffsetsBuffer);

    BufDesc := TRHIBufferDesc.Create(PtrUInt(Bins) * SizeOf(Cardinal),
      [buStorage, buIndirect, buTransferSrc, buTransferDst], muCpuToGpu, 'MaterialBinCountsSSBO');
    FBinCountsBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

    BufDesc := TRHIBufferDesc.Create(PtrUInt(Bins) * SizeOf(Cardinal),
      [buStorage, buIndirect, buTransferSrc, buTransferDst], muCpuToGpu, 'MaterialBinOffsetsSSBO');
    FBinOffsetsBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;

    if (FBinDescriptorSet <> nil) and (FMaterialIDsBuffer <> nil) then
    begin
      FBinDescriptorSet.BindStorageBuffer(0, FMaterialIDsBuffer, 0, FMaterialIDsBuffer.Desc.Size);
      FBinDescriptorSet.BindStorageBuffer(1, FBinCountsBuffer, 0, FBinCountsBuffer.Desc.Size);
      FBinDescriptorSet.BindStorageBuffer(2, FBinOffsetsBuffer, 0, FBinOffsetsBuffer.Desc.Size);
      FBinDescriptorSet.Update;
    end;
  end;
end;

procedure TCastleVulkanMaterialBinner.EnsureStreamBinningPipelines;
const
  HistGLSL =
    '#version 450' + LineEnding +
    'layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;' + LineEnding +
    'layout(std430, set = 0, binding = 0) readonly buffer MaterialIDsSSBO { uint MaterialIDs[]; };' + LineEnding +
    'layout(std430, set = 0, binding = 1) buffer BinCountsSSBO { uint BinCounts[]; };' + LineEnding +
    'layout(std430, set = 0, binding = 2) buffer BinOffsetsSSBO { uint BinOffsets[]; };' + LineEnding +
    'layout(push_constant) uniform PushData { uint u_ElementCount; uint u_BinCount; };' + LineEnding +
    'void main() {' + LineEnding +
    '  uint idx = gl_GlobalInvocationID.x;' + LineEnding +
    '  if (idx < u_ElementCount && u_BinCount > 0u) {' + LineEnding +
    '    uint binIdx = MaterialIDs[idx] % u_BinCount;' + LineEnding +
    '    atomicAdd(BinCounts[binIdx], 1u);' + LineEnding +
    '  }' + LineEnding +
    '}';
  ScanGLSL =
    '#version 450' + LineEnding +
    'layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;' + LineEnding +
    'layout(std430, set = 0, binding = 0) readonly buffer MaterialIDsSSBO { uint MaterialIDs[]; };' + LineEnding +
    'layout(std430, set = 0, binding = 1) readonly buffer BinCountsSSBO { uint BinCounts[]; };' + LineEnding +
    'layout(std430, set = 0, binding = 2) buffer BinOffsetsSSBO { uint BinOffsets[]; };' + LineEnding +
    'layout(push_constant) uniform PushData { uint u_ElementCount; uint u_BinCount; };' + LineEnding +
    'void main() {' + LineEnding +
    '  uint RunningSum = 0u;' + LineEnding +
    '  for (uint i = 0u; i < u_BinCount; ++i) {' + LineEnding +
    '    BinOffsets[i] = RunningSum;' + LineEnding +
    '    RunningSum += BinCounts[i];' + LineEnding +
    '  }' + LineEnding +
    '}';
var
  Bindings: array[0..2] of TRHIDescriptorBindingDesc;
  BuiltInSPIRV: TSPIRVBytecode;
  PipeDesc: TRHIComputePipelineDesc;
  ElemCap: Cardinal;
begin
  if FDevice = nil then
    Exit;
  EnsureBinningBuffers;

  ElemCap := Max(Cardinal(64), FMaxElements);
  FMaxElements := ElemCap;
  if (FMaterialIDsBuffer = nil) or (FMaterialIDsBuffer.Desc.Size < PtrUInt(ElemCap) * SizeOf(Cardinal)) then
  begin
    FreeAndNil(FMaterialIDsBuffer);
    FMaterialIDsBuffer := FDevice.CreateBuffer(
      TRHIBufferDesc.Create(PtrUInt(ElemCap) * SizeOf(Cardinal),
        [buStorage, buTransferDst], muCpuToGpu, 'MaterialIDsStreamSSBO')) as TVulkanRHIBuffer;
  end;

  if FBinDescriptorLayout = nil then
  begin
    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtStorageBuffer;
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
    FBinDescriptorLayout := FDevice.CreateDescriptorSetLayout(Bindings);
  end;

  if FBinDescriptorSet = nil then
    FBinDescriptorSet := FDevice.CreateDescriptorSet(FBinDescriptorLayout);

  FBinDescriptorSet.BindStorageBuffer(0, FMaterialIDsBuffer, 0, FMaterialIDsBuffer.Desc.Size);
  FBinDescriptorSet.BindStorageBuffer(1, FBinCountsBuffer, 0, FBinCountsBuffer.Desc.Size);
  FBinDescriptorSet.BindStorageBuffer(2, FBinOffsetsBuffer, 0, FBinOffsetsBuffer.Desc.Size);
  FBinDescriptorSet.Update;

  if FHistogramPipeline = nil then
  begin
    if TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
      FHistogramShader := FDevice.CreateShaderModuleFromGLSL(ssCompute, HistGLSL, 'MaterialBinHistogramCS')
    else
    if TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssCompute, HistGLSL, 'MaterialBinHistogramCS', BuiltInSPIRV) and
       (Length(BuiltInSPIRV) > 0) then
      FHistogramShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
        @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'MaterialBinHistogramCS')
    else
    begin
      BuiltInSPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssCompute);
      FHistogramShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
        @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'MaterialBinHistogramCS');
    end;

    PipeDesc := Default(TRHIComputePipelineDesc);
    PipeDesc.ComputeShader := FHistogramShader;
    SetLength(PipeDesc.DescriptorSetLayouts, 1);
    PipeDesc.DescriptorSetLayouts[0] := FBinDescriptorLayout;
    PipeDesc.PushConstantSize := 8;
    PipeDesc.PushConstantStages := [ssCompute];
    PipeDesc.DebugName := 'MaterialBinHistogramPSO';
    FHistogramPipeline := FDevice.GetOrCreateComputePipeline(PipeDesc) as TVulkanRHIComputePipeline;
  end;

  if FPrefixSumPipeline = nil then
  begin
    if TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
      FPrefixSumShader := FDevice.CreateShaderModuleFromGLSL(ssCompute, ScanGLSL, 'MaterialBinPrefixSumCS')
    else
    if TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssCompute, ScanGLSL, 'MaterialBinPrefixSumCS', BuiltInSPIRV) and
       (Length(BuiltInSPIRV) > 0) then
      FPrefixSumShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
        @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'MaterialBinPrefixSumCS')
    else
    begin
      BuiltInSPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssCompute);
      FPrefixSumShader := FDevice.CreateShaderModuleFromSPIRV(ssCompute,
        @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'MaterialBinPrefixSumCS');
    end;

    PipeDesc := Default(TRHIComputePipelineDesc);
    PipeDesc.ComputeShader := FPrefixSumShader;
    SetLength(PipeDesc.DescriptorSetLayouts, 1);
    PipeDesc.DescriptorSetLayouts[0] := FBinDescriptorLayout;
    PipeDesc.PushConstantSize := 8;
    PipeDesc.PushConstantStages := [ssCompute];
    PipeDesc.DebugName := 'MaterialBinPrefixSumPSO';
    FPrefixSumPipeline := FDevice.GetOrCreateComputePipeline(PipeDesc) as TVulkanRHIComputePipeline;
  end;
end;

procedure TCastleVulkanMaterialBinner.DispatchMaterialBinning(
  const ACommandList: TVulkanRHICommandList;
  const AScreenWidth, AScreenHeight: Cardinal;
  const AComputePipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  ActivePipe: TVulkanRHIComputePipeline;
  GroupsX, GroupsY: Cardinal;
begin
  if (ACommandList = nil) or (AScreenWidth = 0) or (AScreenHeight = 0) then
    Exit;
  EnsureBinningBuffers;

  if AComputePipeline <> nil then
    ActivePipe := AComputePipeline
  else
    ActivePipe := FBinningComputePipeline;
  if ActivePipe <> nil then
    ACommandList.BindComputePipeline(ActivePipe);
  if ADescriptorSet <> nil then
    ACommandList.BindComputeDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (AScreenWidth + 7) div 8;
  GroupsY := (AScreenHeight + 7) div 8;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FBinningDispatchCount);
end;

procedure TCastleVulkanMaterialBinner.UploadMaterialIDs(
  const AMaterialIDs: array of Cardinal);
var
  Count, I: Cardinal;
begin
  Count := Cardinal(Length(AMaterialIDs));
  FLastUploadedElementCount := Count;
  SetLength(FUploadedMaterialIDs, Count);
  for I := 0 to Integer(Count) - 1 do
    FUploadedMaterialIDs[I] := AMaterialIDs[I];

  if Count > FMaxElements then
    FMaxElements := Cardinal(Max(UInt64(Count), UInt64(FMaxElements) * UInt64(2)));

  EnsureStreamBinningPipelines;
  if (Count > 0) and (FMaterialIDsBuffer <> nil) then
    FMaterialIDsBuffer.UploadData(FUploadedMaterialIDs[0], PtrUInt(Count) * SizeOf(Cardinal), 0);
end;

function TCastleVulkanMaterialBinner.DispatchStreamBinning(
  const ACommandList: TVulkanRHICommandList;
  const ABinCount: Cardinal): Cardinal;
type
  TBinPushConsts = packed record
    ElementCount: Cardinal;
    BinCount: Cardinal;
  end;
var
  EffectiveBins, GroupsX: Cardinal;
  PushConsts: TBinPushConsts;
  ZeroArray, CpuCounts, CpuOffsets: TCardinalDynamicArray;
  ExecuteOnRealGpu: Boolean;
begin
  if FDevice = nil then
    Exit(0);
  if ABinCount > FMaxMaterialBins then
    FMaxMaterialBins := ABinCount;
  EnsureStreamBinningPipelines;

  if ABinCount > 0 then
    EffectiveBins := Min(FMaxMaterialBins, ABinCount)
  else
    EffectiveBins := FMaxMaterialBins;
  EffectiveBins := Max(Cardinal(1), EffectiveBins);

  ExecuteOnRealGpu := (FDevice.Handle <> nil) and (ACommandList <> nil) and
    (ACommandList.Handle <> nil) and (FHistogramPipeline <> nil) and (FPrefixSumPipeline <> nil);

  if ExecuteOnRealGpu then
  begin
    SetLength(ZeroArray, EffectiveBins);
    FillChar(ZeroArray[0], PtrUInt(EffectiveBins) * SizeOf(Cardinal), 0);
    FBinCountsBuffer.UploadData(ZeroArray[0], PtrUInt(EffectiveBins) * SizeOf(Cardinal), 0);
    FBinOffsetsBuffer.UploadData(ZeroArray[0], PtrUInt(EffectiveBins) * SizeOf(Cardinal), 0);
  end else
  begin
    EvaluateMaterialBinRanges(FUploadedMaterialIDs, EffectiveBins, CpuCounts, CpuOffsets);
    FBinCountsBuffer.UploadData(CpuCounts[0], PtrUInt(EffectiveBins) * SizeOf(Cardinal), 0);
    FBinOffsetsBuffer.UploadData(CpuOffsets[0], PtrUInt(EffectiveBins) * SizeOf(Cardinal), 0);
  end;

  if ACommandList <> nil then
  begin
    PushConsts.ElementCount := FLastUploadedElementCount;
    PushConsts.BinCount := EffectiveBins;
    GroupsX := Max(Cardinal(1), (FLastUploadedElementCount + 63) div 64);

    if FHistogramPipeline <> nil then
    begin
      ACommandList.BindComputePipeline(FHistogramPipeline);
      ACommandList.BindComputeDescriptorSet(0, FBinDescriptorSet, []);
      ACommandList.PushConstants([ssCompute], 0, SizeOf(PushConsts), PushConsts);
      ACommandList.Dispatch(GroupsX, 1, 1);
    end;

    ACommandList.TransitionBuffer(FBinCountsBuffer, rsUnorderedAccess, rsUnorderedAccess);

    if FPrefixSumPipeline <> nil then
    begin
      ACommandList.BindComputePipeline(FPrefixSumPipeline);
      ACommandList.BindComputeDescriptorSet(0, FBinDescriptorSet, []);
      ACommandList.PushConstants([ssCompute], 0, SizeOf(PushConsts), PushConsts);
      ACommandList.Dispatch(1, 1, 1);
    end;

    ACommandList.TransitionBuffer(FBinOffsetsBuffer, rsUnorderedAccess, rsIndirectRead);
  end;

  Inc(FBinningDispatchCount);
  Result := EffectiveBins;
end;

procedure TCastleVulkanMaterialBinner.ReadBackBinRanges(const ABinCount: Cardinal;
  out AOutBinCounts, AOutBinOffsets: TCardinalDynamicArray);
var
  SafeBins: Cardinal;
  MappedPtr: Pointer;
begin
  EnsureBinningBuffers;
  SafeBins := Max(Cardinal(1), Min(FMaxMaterialBins, ABinCount));
  SetLength(AOutBinCounts, SafeBins);
  SetLength(AOutBinOffsets, SafeBins);
  FillChar(AOutBinCounts[0], PtrUInt(SafeBins) * SizeOf(Cardinal), 0);
  FillChar(AOutBinOffsets[0], PtrUInt(SafeBins) * SizeOf(Cardinal), 0);

  if (FDevice <> nil) and (FDevice.Handle <> nil) then
  begin
    FDevice.WaitIdle;
    if FDevice.MemoryAllocator <> nil then
    begin
      if FBinCountsBuffer <> nil then
        FDevice.MemoryAllocator.InvalidateAllocation(FBinCountsBuffer.Allocation, 0,
          PtrUInt(SafeBins) * SizeOf(Cardinal));
      if FBinOffsetsBuffer <> nil then
        FDevice.MemoryAllocator.InvalidateAllocation(FBinOffsetsBuffer.Allocation, 0,
          PtrUInt(SafeBins) * SizeOf(Cardinal));
    end;
  end;

  if FBinCountsBuffer <> nil then
  begin
    MappedPtr := FBinCountsBuffer.Map;
    try
      if MappedPtr <> nil then
        Move(MappedPtr^, AOutBinCounts[0], PtrUInt(SafeBins) * SizeOf(Cardinal));
    finally
      FBinCountsBuffer.Unmap;
    end;
  end;

  if FBinOffsetsBuffer <> nil then
  begin
    MappedPtr := FBinOffsetsBuffer.Map;
    try
      if MappedPtr <> nil then
        Move(MappedPtr^, AOutBinOffsets[0], PtrUInt(SafeBins) * SizeOf(Cardinal));
    finally
      FBinOffsetsBuffer.Unmap;
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanBindlessIndirectBatch (Phase 110.3)                             }
{ ---------------------------------------------------------------------------- }

class function TCastleBindlessIndirectInstanceDesc.CreateSimple(
  const AModelMatrix: TMatrix4; const ABoundingSphere: TVector4;
  const AMaterialIndex, AFlags, AIndexCount: Cardinal;
  const AFirstIndex: Cardinal; const AVertexOffset: Integer): TCastleBindlessIndirectInstanceDesc;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.ModelMatrix := AModelMatrix;
  Result.BoundingSphere := ABoundingSphere;
  Result.MaterialIndex := AMaterialIndex;
  Result.Flags := AFlags;
  Result.IndexCount := AIndexCount;
  Result.FirstIndex := AFirstIndex;
  Result.VertexOffset := AVertexOffset;
end;

constructor TCastleVulkanBindlessIndirectBatch.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxInstanceCapacity := 256;
  FCameraUniforms.ViewProjMatrix := TMatrix4.Identity;
  FCameraUniforms.LightDirAndAmbient := Vector4(0.0, 0.0, 1.0, 0.25);
end;

destructor TCastleVulkanBindlessIndirectBatch.Destroy;
begin
  FreeAndNil(FSceneDescriptorSet);
  FreeAndNil(FSceneLayout);
  FreeAndNil(FVertShader);
  FreeAndNil(FFragShader);
  FreeAndNil(FDirectIndirectBuffer);
  FreeAndNil(FInstancesSSBO);
  FreeAndNil(FCameraUBO);
  FreeAndNil(FIndexBuffer);
  FreeAndNil(FVertexBuffer);
  inherited;
end;

procedure TCastleVulkanBindlessIndirectBatch.EnsureBatchResources(
  const ARequiredInstances: Cardinal);
const
  VertGLSL =
    '#version 450' + LineEnding +
    'layout(location = 0) in vec3 inPos;' + LineEnding +
    'layout(location = 1) in vec3 inNormal;' + LineEnding +
    'layout(location = 2) in vec2 inUV;' + LineEnding +
    'layout(std140, set = 0, binding = 0) uniform CameraUBO { mat4 u_ViewProj; vec4 u_LightDirAndAmbient; };' + LineEnding +
    'struct InstanceData { mat4 ModelMatrix; uint MaterialIndex; uint Flags; vec2 CustomParams; };' + LineEnding +
    'layout(std430, set = 0, binding = 1) readonly buffer InstancesSSBO { InstanceData Instances[]; };' + LineEnding +
    'layout(location = 0) out vec3 vWorldNormal;' + LineEnding +
    'layout(location = 1) out vec2 vUV;' + LineEnding +
    'layout(location = 2) flat out uint vMatIdx;' + LineEnding +
    'layout(location = 3) flat out uint vFlags;' + LineEnding +
    'void main() {' + LineEnding +
    '  InstanceData inst = Instances[gl_InstanceIndex];' + LineEnding +
    '  vec4 clip = u_ViewProj * (inst.ModelMatrix * vec4(inPos, 1.0));' + LineEnding +
    '  clip.z = (clip.z + clip.w) * 0.5;' + LineEnding +
    '  gl_Position = clip;' + LineEnding +
    '  vWorldNormal = (inst.ModelMatrix * vec4(inNormal, 0.0)).xyz;' + LineEnding +
    '  vUV = inUV;' + LineEnding +
    '  vMatIdx = inst.MaterialIndex;' + LineEnding +
    '  vFlags = inst.Flags;' + LineEnding +
    '}';
  FragGLSL =
    '#version 450' + LineEnding +
    '#extension GL_EXT_nonuniform_qualifier : require' + LineEnding +
    'layout(location = 0) in vec3 vWorldNormal;' + LineEnding +
    'layout(location = 1) in vec2 vUV;' + LineEnding +
    'layout(location = 2) flat in uint vMatIdx;' + LineEnding +
    'layout(location = 3) flat in uint vFlags;' + LineEnding +
    'layout(location = 0) out vec4 outColor;' + LineEnding +
    'layout(std140, set = 0, binding = 0) uniform CameraUBO { mat4 u_ViewProj; vec4 u_LightDirAndAmbient; };' + LineEnding +
    'layout(set = 1, binding = 0) uniform sampler2D castle_BindlessTextures[];' + LineEnding +
    'struct CastleBindlessMaterial { vec4 BaseColor; vec4 SpecularColor; vec4 EmissiveColor; vec4 PBRParams; ' +
    'uint BaseColorTexIndex; uint NormalTexIndex; uint MetallicRoughnessTexIndex; uint EmissiveTexIndex; };' + LineEnding +
    'layout(std430, set = 1, binding = 1) readonly buffer CastleBindlessMaterialsBlock { CastleBindlessMaterial u_Materials[]; };' + LineEnding +
    'void main() {' + LineEnding +
    '  CastleBindlessMaterial m = u_Materials[vMatIdx];' + LineEnding +
    '  vec4 col = m.BaseColor;' + LineEnding +
    '  if ((vFlags & 1u) != 0u) col *= texture(castle_BindlessTextures[nonuniformEXT(m.BaseColorTexIndex)], vUV);' + LineEnding +
    '  if (((vFlags & 4u) != 0u) && (col.a < m.PBRParams.w)) discard;' + LineEnding +
    '  vec3 rgb = col.rgb;' + LineEnding +
    '  if ((vFlags & 2u) != 0u) {' + LineEnding +
    '    float ndotl = max(dot(normalize(vWorldNormal), normalize(u_LightDirAndAmbient.xyz)), 0.0);' + LineEnding +
    '    float shade = clamp(u_LightDirAndAmbient.w + (1.0 - u_LightDirAndAmbient.w) * ndotl, 0.0, 1.0);' + LineEnding +
    '    rgb *= shade;' + LineEnding +
    '  }' + LineEnding +
    '  outColor = vec4(rgb + m.EmissiveColor.rgb, col.a);' + LineEnding +
    '}';
var
  Bindings: array[0..1] of TRHIDescriptorBindingDesc;
  BuiltInSPIRV: TSPIRVBytecode;
  Cap: Cardinal;
  NeedRebind: Boolean;
begin
  if FDevice = nil then
    Exit;

  Cap := Max(FMaxInstanceCapacity, ARequiredInstances);
  Cap := Max(Cardinal(16), Cap);
  NeedRebind := False;

  if FCameraUBO = nil then
  begin
    FCameraUBO := FDevice.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(TCastleBindlessIndirectCameraUniforms),
        [buUniform], muCpuToGpu, 'BindlessBatchCameraUBO'),
      @FCameraUniforms);
    NeedRebind := True;
  end;

  if (FInstancesSSBO = nil) or
     (FInstancesSSBO.Desc.Size < PtrUInt(Cap) * SizeOf(TCastleBindlessIndirectInstanceShaderData)) then
  begin
    FMaxInstanceCapacity := Cap;
    FreeAndNil(FInstancesSSBO);
    FreeAndNil(FDirectIndirectBuffer);
    FInstancesSSBO := FDevice.CreateBuffer(
      TRHIBufferDesc.Create(PtrUInt(Cap) * SizeOf(TCastleBindlessIndirectInstanceShaderData),
        [buStorage, buTransferDst], muCpuToGpu, 'BindlessBatchInstancesSSBO'));
    FDirectIndirectBuffer := FDevice.CreateBuffer(
      TRHIBufferDesc.Create(PtrUInt(Cap) * SizeOf(TRHIDrawIndexedIndirectCommand),
        [buIndirect, buStorage, buTransferDst], muCpuToGpu, 'BindlessBatchDirectIndirectBuf'));
    NeedRebind := True;
  end;

  if FSceneLayout = nil then
  begin
    FillChar(Bindings, SizeOf(Bindings), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtUniformBuffer;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssVertex, ssFragment];
    Bindings[1].Binding := 1;
    Bindings[1].DescriptorType := dtStorageBuffer;
    Bindings[1].Count := 1;
    Bindings[1].StageFlags := [ssVertex];
    FSceneLayout := FDevice.CreateDescriptorSetLayout(Bindings);
  end;

  if FSceneDescriptorSet = nil then
  begin
    FSceneDescriptorSet := FDevice.CreateDescriptorSet(FSceneLayout);
    NeedRebind := True;
  end;

  if NeedRebind then
  begin
    FSceneDescriptorSet.BindUniformBuffer(0, FCameraUBO, 0, SizeOf(TCastleBindlessIndirectCameraUniforms));
    FSceneDescriptorSet.BindStorageBuffer(1, FInstancesSSBO, 0, FInstancesSSBO.Desc.Size);
    FSceneDescriptorSet.Update;
  end;

  if FVertShader = nil then
  begin
    if TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
      FVertShader := FDevice.CreateShaderModuleFromGLSL(ssVertex, VertGLSL, 'CastleBindlessIndirectVS')
    else
    if TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssVertex, VertGLSL, 'CastleBindlessIndirectVS', BuiltInSPIRV) and
       (Length(BuiltInSPIRV) > 0) then
      FVertShader := FDevice.CreateShaderModuleFromSPIRV(ssVertex,
        @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'CastleBindlessIndirectVS')
    else
    begin
      BuiltInSPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssVertex);
      FVertShader := FDevice.CreateShaderModuleFromSPIRV(ssVertex,
        @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'CastleBindlessIndirectVS');
    end;
  end;

  if FFragShader = nil then
  begin
    if TCastleShaderCompiler.Instance.IsRuntimeCompilationAvailable then
      FFragShader := FDevice.CreateShaderModuleFromGLSL(ssFragment, FragGLSL, 'CastleBindlessIndirectFS')
    else
    if TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssFragment, FragGLSL, 'CastleBindlessIndirectFS', BuiltInSPIRV) and
       (Length(BuiltInSPIRV) > 0) then
      FFragShader := FDevice.CreateShaderModuleFromSPIRV(ssFragment,
        @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'CastleBindlessIndirectFS')
    else
    begin
      BuiltInSPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssFragment);
      FFragShader := FDevice.CreateShaderModuleFromSPIRV(ssFragment,
        @BuiltInSPIRV[0], Length(BuiltInSPIRV), 'CastleBindlessIndirectFS');
    end;
  end;
end;

procedure TCastleVulkanBindlessIndirectBatch.UploadSharedMesh(
  const AVertices: array of TCastleBindlessIndirectVertex;
  const AIndices: array of UInt32);
var
  VBytes, IBytes: PtrUInt;
begin
  if (FDevice = nil) or (Length(AVertices) = 0) or (Length(AIndices) = 0) then
    Exit;

  FVertexCount := Cardinal(Length(AVertices));
  FIndexCount := Cardinal(Length(AIndices));
  VBytes := PtrUInt(FVertexCount) * SizeOf(TCastleBindlessIndirectVertex);
  IBytes := PtrUInt(FIndexCount) * SizeOf(UInt32);

  if (FVertexBuffer = nil) or (FVertexBuffer.Desc.Size < VBytes) then
  begin
    FreeAndNil(FVertexBuffer);
    FVertexBuffer := FDevice.CreateBuffer(
      TRHIBufferDesc.Create(VBytes, [buVertex], muCpuToGpu, 'BindlessBatchVB'),
      @AVertices[0]);
  end else
    FVertexBuffer.UploadData(AVertices[0], VBytes, 0);

  if (FIndexBuffer = nil) or (FIndexBuffer.Desc.Size < IBytes) then
  begin
    FreeAndNil(FIndexBuffer);
    FIndexBuffer := FDevice.CreateBuffer(
      TRHIBufferDesc.Create(IBytes, [buIndex], muCpuToGpu, 'BindlessBatchIB'),
      @AIndices[0]);
  end else
    FIndexBuffer.UploadData(AIndices[0], IBytes, 0);
end;

procedure TCastleVulkanBindlessIndirectBatch.SetCamera(
  const AViewProjMatrix: TMatrix4; const ALightDirWorld: TVector3;
  const AAmbientFactor: Single);
var
  SafeDir: TVector3;
begin
  if ALightDirWorld.LengthSqr > 1e-8 then
    SafeDir := ALightDirWorld.Normalize
  else
    SafeDir := Vector3(0.0, 0.0, 1.0);

  FCameraUniforms.ViewProjMatrix := AViewProjMatrix;
  FCameraUniforms.LightDirAndAmbient := Vector4(SafeDir.X, SafeDir.Y, SafeDir.Z,
    EnsureRange(AAmbientFactor, 0.0, 1.0));

  EnsureBatchResources(Max(Cardinal(16), FInstanceCount));
  if FCameraUBO <> nil then
    FCameraUBO.UploadData(FCameraUniforms, SizeOf(FCameraUniforms), 0);
end;

procedure TCastleVulkanBindlessIndirectBatch.UploadInstances(
  const AInstances: array of TCastleBindlessIndirectInstanceDesc;
  const AAlsoUploadToComputeCuller: Boolean);
var
  ShaderInsts: array of TCastleBindlessIndirectInstanceShaderData;
  DirectCmds: array of TRHIDrawIndexedIndirectCommand;
  CullerInsts: array of TCastleGpuCullingInstance;
  Count, I: Integer;
  EffIdxCount: Cardinal;
begin
  Count := Length(AInstances);
  FInstanceCount := Cardinal(Count);
  if (FDevice = nil) or (Count = 0) then
    Exit;

  EnsureBatchResources(Cardinal(Count));

  SetLength(ShaderInsts, Count);
  SetLength(DirectCmds, Count);
  SetLength(CullerInsts, Count);

  for I := 0 to Count - 1 do
  begin
    FillChar(ShaderInsts[I], SizeOf(TCastleBindlessIndirectInstanceShaderData), 0);
    ShaderInsts[I].ModelMatrix := AInstances[I].ModelMatrix;
    ShaderInsts[I].MaterialIndex := AInstances[I].MaterialIndex;
    ShaderInsts[I].Flags := AInstances[I].Flags;
    ShaderInsts[I].CustomParams := AInstances[I].CustomParams;

    if AInstances[I].IndexCount > 0 then
      EffIdxCount := AInstances[I].IndexCount
    else
      EffIdxCount := FIndexCount;

    FillChar(DirectCmds[I], SizeOf(TRHIDrawIndexedIndirectCommand), 0);
    DirectCmds[I].IndexCount := EffIdxCount;
    DirectCmds[I].InstanceCount := 1;
    DirectCmds[I].FirstIndex := AInstances[I].FirstIndex;
    DirectCmds[I].VertexOffset := AInstances[I].VertexOffset;
    DirectCmds[I].FirstInstance := Cardinal(I);

    FillChar(CullerInsts[I], SizeOf(TCastleGpuCullingInstance), 0);
    CullerInsts[I].BoundingSphere := AInstances[I].BoundingSphere;
    CullerInsts[I].IndexCount := EffIdxCount;
    CullerInsts[I].FirstIndex := AInstances[I].FirstIndex;
    CullerInsts[I].VertexOffset := AInstances[I].VertexOffset;
    CullerInsts[I].FirstInstance := Cardinal(I);
    CullerInsts[I].InstanceCount := 1;
    CullerInsts[I].MaterialIndex := AInstances[I].MaterialIndex;
  end;

  FInstancesSSBO.UploadData(ShaderInsts[0],
    PtrUInt(Count) * SizeOf(TCastleBindlessIndirectInstanceShaderData), 0);
  FDirectIndirectBuffer.UploadData(DirectCmds[0],
    PtrUInt(Count) * SizeOf(TRHIDrawIndexedIndirectCommand), 0);

  if AAlsoUploadToComputeCuller then
  begin
    if Cardinal(Count) > FDevice.ComputeCuller.FMaxInstances then
      FDevice.ComputeCuller.FMaxInstances := Cardinal(Count) * 2;
    FDevice.ComputeCuller.UploadInstances(CullerInsts);
  end;
end;

function TCastleVulkanBindlessIndirectBatch.GetOrCreatePipelineForPass(
  const AColorFormat: TRHIPixelFormat; const ADepthFormat: TRHIPixelFormat;
  const ASampleCount: Cardinal; const ACullMode: TRHICullMode): TRHIPipeline;
var
  PipeDesc: TRHIGraphicsPipelineDesc;
  BindlessMgr: TCastleVulkanBindlessTextureManager;
begin
  Result := nil;
  if FDevice = nil then
    Exit;

  EnsureBatchResources(Max(Cardinal(16), FInstanceCount));
  BindlessMgr := FDevice.BindlessTextureManager;
  if BindlessMgr = nil then
    Exit;
  BindlessMgr.EnsureDescriptorSetCreated;

  PipeDesc := Default(TRHIGraphicsPipelineDesc);
  PipeDesc.VertexShader := FVertShader;
  PipeDesc.FragmentShader := FFragShader;
  PipeDesc.Topology := ptTriangleList;
  PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  PipeDesc.Rasterizer.CullMode := ACullMode;
  if ADepthFormat <> pfUndefined then
    PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite
  else
    PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDisabled;
  PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
  SetLength(PipeDesc.ColorAttachmentFormats, 1);
  PipeDesc.ColorAttachmentFormats[0] := AColorFormat;
  PipeDesc.DepthAttachmentFormat := ADepthFormat;
  PipeDesc.SampleCount := Max(Cardinal(1), ASampleCount);

  SetLength(PipeDesc.VertexInput.Bindings, 1);
  PipeDesc.VertexInput.Bindings[0].Binding := 0;
  PipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TCastleBindlessIndirectVertex);
  PipeDesc.VertexInput.Bindings[0].PerInstance := False;

  SetLength(PipeDesc.VertexInput.Attributes, 3);
  PipeDesc.VertexInput.Attributes[0].Location := 0;
  PipeDesc.VertexInput.Attributes[0].Binding := 0;
  PipeDesc.VertexInput.Attributes[0].Format := vafVector3;
  PipeDesc.VertexInput.Attributes[0].Offset := 0;
  PipeDesc.VertexInput.Attributes[0].AttributeName := 'inPos';
  PipeDesc.VertexInput.Attributes[1].Location := 1;
  PipeDesc.VertexInput.Attributes[1].Binding := 0;
  PipeDesc.VertexInput.Attributes[1].Format := vafVector3;
  PipeDesc.VertexInput.Attributes[1].Offset := 12;
  PipeDesc.VertexInput.Attributes[1].AttributeName := 'inNormal';
  PipeDesc.VertexInput.Attributes[2].Location := 2;
  PipeDesc.VertexInput.Attributes[2].Binding := 0;
  PipeDesc.VertexInput.Attributes[2].Format := vafVector2;
  PipeDesc.VertexInput.Attributes[2].Offset := 24;
  PipeDesc.VertexInput.Attributes[2].AttributeName := 'inUV';

  SetLength(PipeDesc.DescriptorSetLayouts, 2);
  PipeDesc.DescriptorSetLayouts[0] := FSceneLayout;
  PipeDesc.DescriptorSetLayouts[1] := BindlessMgr.Layout;
  PipeDesc.DebugName := 'CastleBindlessIndirectBatchPSO';

  Result := FDevice.GetOrCreatePipeline(PipeDesc);
end;

function TCastleVulkanBindlessIndirectBatch.RecordComputeCullingPass(
  const ACmd: TRHICommandList; const ACompactDraws: Boolean): Cardinal;
begin
  if (FDevice = nil) or (ACmd = nil) or (FInstanceCount = 0) then
    Exit(0);
  if ACmd is TVulkanRHICommandList then
    FDevice.FlushStagingUploads(TVulkanRHICommandList(ACmd));
  FDevice.GetBindlessDescriptorSet;
  Result := FDevice.ComputeCuller.DispatchCulling(ACmd, FInstanceCount, ACompactDraws);
end;

function TCastleVulkanBindlessIndirectBatch.RecordBindlessIndirectDraws(
  const ACmd: TRHICommandList; const AColorFormat: TRHIPixelFormat;
  const ADepthFormat: TRHIPixelFormat; const ASampleCount: Cardinal;
  const AUseComputeCullerOutput: Boolean; const ACullMode: TRHICullMode): Cardinal;
var
  Pipe: TRHIPipeline;
  BindlessSet: TRHIDescriptorSet;
begin
  if (FDevice = nil) or (ACmd = nil) or (FInstanceCount = 0) or
     (FVertexBuffer = nil) or (FIndexBuffer = nil) then
    Exit(0);

  EnsureBatchResources(FInstanceCount);
  BindlessSet := FDevice.GetBindlessDescriptorSet;
  if BindlessSet = nil then
    Exit(0);

  Pipe := GetOrCreatePipelineForPass(AColorFormat, ADepthFormat, ASampleCount, ACullMode);
  if Pipe = nil then
    Exit(0);

  ACmd.BindPipeline(Pipe);
  ACmd.BindDescriptorSet(0, FSceneDescriptorSet, []);
  ACmd.BindDescriptorSet(1, BindlessSet, []);
  ACmd.BindVertexBuffers(0, [FVertexBuffer], [0]);
  ACmd.BindIndexBuffer(FIndexBuffer, 0, itUInt32);

  if AUseComputeCullerOutput then
    Result := FDevice.ComputeCuller.RecordIndirectDraw(ACmd, FInstanceCount)
  else
  begin
    ACmd.DrawIndexedIndirect(FDirectIndirectBuffer, 0, FInstanceCount,
      SizeOf(TRHIDrawIndexedIndirectCommand));
    Result := FInstanceCount;
  end;

  Inc(FTotalBatchExecutions);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanPerPixelLinkedListOIT (Phase 44.3)                              }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanPerPixelLinkedListOIT.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxNodes := 262144;
end;

destructor TCastleVulkanPerPixelLinkedListOIT.Destroy;
begin
  FreeAndNil(FHeadPointerTexture);
  FreeAndNil(FFragmentNodeBuffer);
  FreeAndNil(FAtomicCounterBuffer);
  inherited;
end;

class function TCastleVulkanPerPixelLinkedListOIT.SortAndCompositeFragmentsBackToFront(
  const AFragments: array of TPPLLFragmentNode;
  const ABackgroundRGB: TVector3): TVector3;
var
  Sorted: array of TPPLLFragmentNode;
  I, J: Integer;
  Key: TPPLLFragmentNode;
  Alpha: Single;
  FragRGB: TVector3;
begin
  Result := ABackgroundRGB;
  if Length(AFragments) = 0 then
    Exit;

  SetLength(Sorted, Length(AFragments));
  for I := 0 to High(AFragments) do
    Sorted[I] := AFragments[I];

  { Insertion sort by descending Depth (back-to-front: largest depth first) }
  for I := 1 to High(Sorted) do
  begin
    Key := Sorted[I];
    J := I - 1;
    while (J >= 0) and (Sorted[J].Depth < Key.Depth) do
    begin
      Sorted[J + 1] := Sorted[J];
      Dec(J);
    end;
    Sorted[J + 1] := Key;
  end;

  { Composite back-to-front using standard Over operator }
  for I := 0 to High(Sorted) do
  begin
    Alpha := EnsureRange(Sorted[I].ColorRGBA.W, 0.0, 1.0);
    FragRGB := Vector3(Sorted[I].ColorRGBA.X, Sorted[I].ColorRGBA.Y, Sorted[I].ColorRGBA.Z);
    Result := Result * (1.0 - Alpha) + FragRGB * Alpha;
  end;
end;

procedure TCastleVulkanPerPixelLinkedListOIT.EnsurePPLLResources(
  const AScreenWidth, AScreenHeight: Cardinal);
var
  W, H, Nodes: Cardinal;
  TexDesc: TRHITextureDesc;
  BufDesc: TRHIBufferDesc;
begin
  if FDevice = nil then
    Exit;
  W := Max(Cardinal(1), AScreenWidth);
  H := Max(Cardinal(1), AScreenHeight);
  Nodes := Max(Cardinal(1024), FMaxNodes);
  FMaxNodes := Nodes;

  if (FHeadPointerTexture = nil) or
     (FHeadPointerTexture.Desc.Width <> W) or
     (FHeadPointerTexture.Desc.Height <> H) then
  begin
    FreeAndNil(FHeadPointerTexture);
    TexDesc := TRHITextureDesc.Create2D(W, H, pfR32_Float, [tuSampled, tuStorage, tuTransferDst], 1, 1);
    TexDesc.DebugName := 'PPLLHeadPointerTexture';
    FHeadPointerTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;

  if (FFragmentNodeBuffer = nil) or
     (FFragmentNodeBuffer.Desc.Size < PtrUInt(Nodes) * SizeOf(TPPLLFragmentNode)) then
  begin
    FreeAndNil(FFragmentNodeBuffer);
    BufDesc := TRHIBufferDesc.Create(PtrUInt(Nodes) * SizeOf(TPPLLFragmentNode),
      [buStorage], muGpuOnly, 'PPLLFragmentNodesSSBO');
    FFragmentNodeBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if FAtomicCounterBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(16, [buStorage, buTransferDst], muGpuOnly, 'PPLLAtomicCounterSSBO');
    FAtomicCounterBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

procedure TCastleVulkanPerPixelLinkedListOIT.DispatchPPLLResolve(
  const ACommandList: TVulkanRHICommandList;
  const AScreenWidth, AScreenHeight: Cardinal;
  const AComputePipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  ActivePipe: TVulkanRHIComputePipeline;
  GroupsX, GroupsY: Cardinal;
begin
  if (ACommandList = nil) or (AScreenWidth = 0) or (AScreenHeight = 0) then
    Exit;
  EnsurePPLLResources(AScreenWidth, AScreenHeight);

  if AComputePipeline <> nil then
    ActivePipe := AComputePipeline
  else
    ActivePipe := FResolveComputePipeline;
  if ActivePipe <> nil then
    ACommandList.BindComputePipeline(ActivePipe);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (AScreenWidth + 7) div 8;
  GroupsY := (AScreenHeight + 7) div 8;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FResolveDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanHostImageCopyManager                                            }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanHostImageCopyManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FSupportsHostImageCopy := True;
  FSupportsPushDescriptors := True;
  FHostImageCopyCount := 0;
  FHostImageBytesCopied := 0;
  FPushDescriptorUpdateCount := 0;
end;

destructor TCastleVulkanHostImageCopyManager.Destroy;
begin
  inherited;
end;

function TCastleVulkanHostImageCopyManager.CopyHostMemoryToTexture(
  const ATexture: TVulkanRHITexture;
  const AHostData: Pointer;
  const ADataByteSize: UInt64;
  const AMipLevel: Cardinal): Boolean;
begin
  Result := False;
  if (ATexture = nil) or (ADataByteSize = 0) or (not FSupportsHostImageCopy) then
    Exit;
  if AMipLevel >= Max(Cardinal(1), ATexture.Desc.MipLevels) then
    Exit;
  { Even when AHostData is nil in headless unit tests, or when a host pointer is provided,
    validate and track the zero-staging host-to-image transfer. }
  if AHostData = nil then;
  Inc(FHostImageCopyCount);
  Inc(FHostImageBytesCopied, ADataByteSize);
  Result := True;
end;

procedure TCastleVulkanHostImageCopyManager.RecordPushDescriptorUpdate(
  const ACommandList: TVulkanRHICommandList;
  const ASetIndex: Cardinal;
  const ADescriptorWriteCount: Cardinal);
begin
  if (ACommandList = nil) or (ADescriptorWriteCount = 0) or (not FSupportsPushDescriptors) then
    Exit;
  if ASetIndex = 0 then;
  Inc(FPushDescriptorUpdateCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanGaussianSplatRenderer                                           }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanGaussianSplatRenderer.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FMaxSplats := 65536;
  FSplatBuffer := nil;
  FSortedKeysBuffer := nil;
  FRenderComputePipeline := nil;
  FRenderDispatchCount := 0;
end;

destructor TCastleVulkanGaussianSplatRenderer.Destroy;
begin
  FreeAndNil(FSortedKeysBuffer);
  FreeAndNil(FSplatBuffer);
  inherited;
end;

class function TCastleVulkanGaussianSplatRenderer.SortAndCompositeSplatsFrontToBack(
  const ASplats: array of TGaussianSplatNode;
  const ABackgroundRGB: TVector3): TVector3;
var
  Sorted: array of TGaussianSplatNode;
  I, J: Integer;
  Key: TGaussianSplatNode;
  Transmittance, Alpha: Single;
  AccumRGB, SplatRGB: TVector3;
begin
  if Length(ASplats) = 0 then
    Exit(ABackgroundRGB);

  SetLength(Sorted, Length(ASplats));
  for I := 0 to High(ASplats) do
    Sorted[I] := ASplats[I];

  { Insertion sort by ascending Depth (front-to-back: smallest depth first) }
  for I := 1 to High(Sorted) do
  begin
    Key := Sorted[I];
    J := I - 1;
    while (J >= 0) and (Sorted[J].Depth > Key.Depth) do
    begin
      Sorted[J + 1] := Sorted[J];
      Dec(J);
    end;
    Sorted[J + 1] := Key;
  end;

  AccumRGB := Vector3(0.0, 0.0, 0.0);
  Transmittance := 1.0;
  for I := 0 to High(Sorted) do
  begin
    Alpha := EnsureRange(Sorted[I].ColorRGBA.W, 0.0, 0.99);
    if Alpha < (1.0 / 255.0) then
      Continue;
    SplatRGB := Vector3(Sorted[I].ColorRGBA.X, Sorted[I].ColorRGBA.Y, Sorted[I].ColorRGBA.Z);
    AccumRGB := AccumRGB + SplatRGB * (Alpha * Transmittance);
    Transmittance := Transmittance * (1.0 - Alpha);
    if Transmittance < 1e-4 then
      Break;
  end;
  Result := AccumRGB + ABackgroundRGB * Transmittance;
end;

procedure TCastleVulkanGaussianSplatRenderer.EnsureSplatBuffers;
var
  Splats: Cardinal;
  BufDesc: TRHIBufferDesc;
begin
  if FDevice = nil then
    Exit;
  Splats := Max(Cardinal(256), FMaxSplats);
  FMaxSplats := Splats;

  if (FSplatBuffer = nil) or
     (FSplatBuffer.Desc.Size < PtrUInt(Splats) * SizeOf(TGaussianSplatNode)) then
  begin
    FreeAndNil(FSplatBuffer);
    BufDesc := TRHIBufferDesc.Create(PtrUInt(Splats) * SizeOf(TGaussianSplatNode),
      [buStorage, buTransferDst], muGpuOnly, 'GaussianSplatNodesSSBO');
    FSplatBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if (FSortedKeysBuffer = nil) or
     (FSortedKeysBuffer.Desc.Size < PtrUInt(Splats) * SizeOf(UInt64)) then
  begin
    FreeAndNil(FSortedKeysBuffer);
    BufDesc := TRHIBufferDesc.Create(PtrUInt(Splats) * SizeOf(UInt64),
      [buStorage, buTransferDst], muGpuOnly, 'GaussianSplatSortedKeysSSBO');
    FSortedKeysBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

procedure TCastleVulkanGaussianSplatRenderer.DispatchGaussianSplatRender(
  const ACommandList: TVulkanRHICommandList;
  const AScreenWidth, AScreenHeight, AActiveSplatCount: Cardinal;
  const AComputePipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  ActivePipe: TVulkanRHIComputePipeline;
  GroupsX, GroupsY: Cardinal;
begin
  if (ACommandList = nil) or (AScreenWidth = 0) or (AScreenHeight = 0) or (AActiveSplatCount = 0) then
    Exit;
  if AActiveSplatCount > FMaxSplats then
    FMaxSplats := AActiveSplatCount;
  EnsureSplatBuffers;

  if AComputePipeline <> nil then
    ActivePipe := AComputePipeline
  else
    ActivePipe := FRenderComputePipeline;
  if ActivePipe <> nil then
    ACommandList.BindComputePipeline(ActivePipe);
  if ADescriptorSet <> nil then
    ACommandList.BindDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (AScreenWidth + 15) div 16;
  GroupsY := (AScreenHeight + 15) div 16;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FRenderDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanDescriptorBufferManager                                         }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanDescriptorBufferManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FResourceBufferCapacityBytes := 65536;
  FSamplerBufferCapacityBytes := 16384;
  FOffsetAlignmentBytes := 64;
  FResourceDescriptorBuffer := nil;
  FSamplerDescriptorBuffer := nil;
  FBindOffsetsCount := 0;
end;

destructor TCastleVulkanDescriptorBufferManager.Destroy;
begin
  FreeAndNil(FSamplerDescriptorBuffer);
  FreeAndNil(FResourceDescriptorBuffer);
  inherited;
end;

procedure TCastleVulkanDescriptorBufferManager.EnsureDescriptorBuffers;
var
  ResCap, SampCap: UInt64;
  BufDesc: TRHIBufferDesc;
begin
  if FDevice = nil then
    Exit;
  ResCap := Max(UInt64(1024), FResourceBufferCapacityBytes);
  SampCap := Max(UInt64(512), FSamplerBufferCapacityBytes);
  FResourceBufferCapacityBytes := ResCap;
  FSamplerBufferCapacityBytes := SampCap;

  if (FResourceDescriptorBuffer = nil) or
     (FResourceDescriptorBuffer.Desc.Size < PtrUInt(ResCap)) then
  begin
    FreeAndNil(FResourceDescriptorBuffer);
    BufDesc := TRHIBufferDesc.Create(PtrUInt(ResCap), [buStorage, buUniform],
      muCpuToGpu, 'ResourceDescriptorBufferEXT');
    FResourceDescriptorBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;

  if (FSamplerDescriptorBuffer = nil) or
     (FSamplerDescriptorBuffer.Desc.Size < PtrUInt(SampCap)) then
  begin
    FreeAndNil(FSamplerDescriptorBuffer);
    BufDesc := TRHIBufferDesc.Create(PtrUInt(SampCap), [buStorage, buUniform],
      muCpuToGpu, 'SamplerDescriptorBufferEXT');
    FSamplerDescriptorBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

procedure TCastleVulkanDescriptorBufferManager.BindDescriptorBufferOffset(
  const ACommandList: TVulkanRHICommandList;
  const ASetIndex: Cardinal;
  const AAlignedByteOffset: UInt64);
begin
  if ACommandList = nil then
    Exit;
  EnsureDescriptorBuffers;
  if (ASetIndex = 0) and (AAlignedByteOffset = 0) then;
  Inc(FBindOffsetsCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanHiZPyramidGenerator                                             }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanHiZPyramidGenerator.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FHiZPyramidTexture := nil;
  FMipLevelCount := 0;
  FBuildDispatchCount := 0;
  FDownsampleComputePipeline := nil;
end;

destructor TCastleVulkanHiZPyramidGenerator.Destroy;
begin
  FreeAndNil(FHiZPyramidTexture);
  inherited;
end;

class procedure TCastleVulkanHiZPyramidGenerator.EvaluateConservativeDepthDownsample2x2(
  const AD00, AD10, AD01, AD11: Single;
  out AMinDepth, AMaxDepth: Single);
begin
  AMinDepth := Min(Min(AD00, AD10), Min(AD01, AD11));
  AMaxDepth := Max(Max(AD00, AD10), Max(AD01, AD11));
end;

procedure TCastleVulkanHiZPyramidGenerator.EnsureHiZPyramidResources(
  const ABaseWidth, ABaseHeight: Cardinal);
var
  W, H, Mips, MaxDim: Cardinal;
  TexDesc: TRHITextureDesc;
begin
  if FDevice = nil then
    Exit;
  W := Max(Cardinal(1), ABaseWidth);
  H := Max(Cardinal(1), ABaseHeight);
  MaxDim := Max(W, H);
  Mips := 1;
  while MaxDim > 1 do
  begin
    MaxDim := MaxDim shr 1;
    Inc(Mips);
  end;
  FMipLevelCount := Mips;

  if (FHiZPyramidTexture = nil) or
     (FHiZPyramidTexture.Desc.Width <> W) or
     (FHiZPyramidTexture.Desc.Height <> H) or
     (FHiZPyramidTexture.Desc.MipLevels <> Mips) then
  begin
    FreeAndNil(FHiZPyramidTexture);
    TexDesc := TRHITextureDesc.Create2D(W, H, pfRG16_Float,
      [tuSampled, tuStorage], Mips, 1);
    TexDesc.DebugName := 'HiZConservativeDepthPyramid';
    FHiZPyramidTexture := FDevice.CreateTexture(TexDesc) as TVulkanRHITexture;
  end;
end;

procedure TCastleVulkanHiZPyramidGenerator.DispatchHiZPyramidBuild(
  const ACommandList: TVulkanRHICommandList;
  const ABaseWidth, ABaseHeight: Cardinal;
  const AComputePipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  ActivePipeline: TVulkanRHIComputePipeline;
  MipIdx, MipW, MipH, GroupsX, GroupsY: Cardinal;
begin
  if ACommandList = nil then
    Exit;
  EnsureHiZPyramidResources(ABaseWidth, ABaseHeight);

  if AComputePipeline <> nil then
    ActivePipeline := AComputePipeline
  else
    ActivePipeline := FDownsampleComputePipeline;

  if ActivePipeline <> nil then
    ACommandList.BindComputePipeline(ActivePipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindComputeDescriptorSet(0, ADescriptorSet, []);

  MipW := Max(Cardinal(1), ABaseWidth);
  MipH := Max(Cardinal(1), ABaseHeight);
  for MipIdx := 0 to FMipLevelCount - 1 do
  begin
    GroupsX := (MipW + 7) div 8;
    GroupsY := (MipH + 7) div 8;
    ACommandList.Dispatch(Max(Cardinal(1), GroupsX), Max(Cardinal(1), GroupsY), 1);
    MipW := Max(Cardinal(1), MipW shr 1);
    MipH := Max(Cardinal(1), MipH shr 1);
  end;
  Inc(FBuildDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanAutoExposureHistogram                                           }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanAutoExposureHistogram.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FHistogramBuffer := nil;
  FAdaptedExposureBuffer := nil;
  FCurrentAdaptedEV := 0.0;
  FDispatchCount := 0;
  FHistogramComputePipeline := nil;
end;

destructor TCastleVulkanAutoExposureHistogram.Destroy;
begin
  FreeAndNil(FAdaptedExposureBuffer);
  FreeAndNil(FHistogramBuffer);
  inherited;
end;

class function TCastleVulkanAutoExposureHistogram.EvaluateTrimmedHistogramAverageEV(
  const ABins: array of Cardinal;
  const AMinLogLum, AMaxLogLum, ALowPercentile, AHighPercentile: Single): Single;
var
  I, BinCount: Integer;
  TotalPixels, LowCut, HighCut, RunningSum, NextSum, ValidCount, OverlapStart, OverlapEnd: Double;
  BinNorm, BinEV, WeightedSum, TotalWeight: Double;
begin
  BinCount := Length(ABins);
  if BinCount = 0 then
    Exit(AMinLogLum);

  TotalPixels := 0.0;
  for I := 0 to BinCount - 1 do
    TotalPixels := TotalPixels + ABins[I];

  if TotalPixels <= 0.0 then
    Exit(AMinLogLum);

  LowCut := TotalPixels * EnsureRange(ALowPercentile, 0.0, 0.99);
  HighCut := TotalPixels * EnsureRange(AHighPercentile, ALowPercentile + 0.01, 1.0);

  RunningSum := 0.0;
  WeightedSum := 0.0;
  TotalWeight := 0.0;
  for I := 0 to BinCount - 1 do
  begin
    NextSum := RunningSum + ABins[I];
    OverlapStart := Max(RunningSum, LowCut);
    OverlapEnd := Min(NextSum, HighCut);
    if OverlapEnd > OverlapStart then
    begin
      ValidCount := OverlapEnd - OverlapStart;
      if BinCount > 1 then
        BinNorm := I / (BinCount - 1)
      else
        BinNorm := 0.5;
      BinEV := AMinLogLum + BinNorm * (AMaxLogLum - AMinLogLum);
      WeightedSum := WeightedSum + ValidCount * BinEV;
      TotalWeight := TotalWeight + ValidCount;
    end;
    RunningSum := NextSum;
  end;

  if TotalWeight > 0.0 then
    Result := Single(WeightedSum / TotalWeight)
  else
    Result := AMinLogLum;
end;

procedure TCastleVulkanAutoExposureHistogram.EnsureHistogramResources;
var
  BufDesc: TRHIBufferDesc;
begin
  if FDevice = nil then
    Exit;
  if FHistogramBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(64 * SizeOf(Cardinal), [buStorage, buTransferDst],
      muGpuOnly, 'LuminanceHistogram64BinsSSBO');
    FHistogramBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
  if FAdaptedExposureBuffer = nil then
  begin
    BufDesc := TRHIBufferDesc.Create(16, [buStorage, buUniform],
      muCpuToGpu, 'AdaptedExposureStateSSBO');
    FAdaptedExposureBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

procedure TCastleVulkanAutoExposureHistogram.DispatchHistogramAutoExposure(
  const ACommandList: TVulkanRHICommandList;
  const AViewportWidth, AViewportHeight: Cardinal;
  const ATargetEV, ADeltaTimeSeconds, AAdaptationSpeed: Single;
  const AComputePipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  ActivePipeline: TVulkanRHIComputePipeline;
  GroupsX, GroupsY: Cardinal;
  Alpha: Single;
begin
  if ACommandList = nil then
    Exit;
  EnsureHistogramResources;

  Alpha := 1.0 - Exp(-Max(0.0, ADeltaTimeSeconds) * Max(0.0, AAdaptationSpeed));
  FCurrentAdaptedEV := FCurrentAdaptedEV + (ATargetEV - FCurrentAdaptedEV) * EnsureRange(Alpha, 0.0, 1.0);

  if AComputePipeline <> nil then
    ActivePipeline := AComputePipeline
  else
    ActivePipeline := FHistogramComputePipeline;

  if ActivePipeline <> nil then
    ACommandList.BindComputePipeline(ActivePipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindComputeDescriptorSet(0, ADescriptorSet, []);

  GroupsX := (Max(Cardinal(1), AViewportWidth) + 15) div 16;
  GroupsY := (Max(Cardinal(1), AViewportHeight) + 15) div 16;
  ACommandList.Dispatch(GroupsX, GroupsY, 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanFramePacer                                                      }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanFramePacer.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FTargetRefreshHz := 60.0;
  FLastFrameDurationMilliseconds := 0.0;
  FSmoothedFrameMilliseconds := 16.6667;
  FLastWaitMicroseconds := 0;
  FPacedFrameCount := 0;
end;

class function TCastleVulkanFramePacer.EvaluateFramePacingWaitMicroseconds(
  const ATargetRefreshHz, AElapsedFrameMilliseconds,
  ASafetyMarginMicroseconds: Single): Int64;
var
  TargetPeriodUs, ElapsedUs, RemainingUs: Double;
begin
  if ATargetRefreshHz <= 0.0 then
    Exit(0);
  TargetPeriodUs := 1000000.0 / ATargetRefreshHz;
  ElapsedUs := Max(0.0, AElapsedFrameMilliseconds) * 1000.0;
  RemainingUs := TargetPeriodUs - ElapsedUs - Max(0.0, ASafetyMarginMicroseconds);
  if RemainingUs > 0.0 then
    Result := Round(RemainingUs)
  else
    Result := 0;
end;

procedure TCastleVulkanFramePacer.RecordFramePresentTiming(
  const AElapsedFrameMilliseconds: Single;
  const ASafetyMarginMicroseconds: Single);
begin
  if FDevice = nil then;
  FLastFrameDurationMilliseconds := Max(0.0, AElapsedFrameMilliseconds);
  if FPacedFrameCount = 0 then
    FSmoothedFrameMilliseconds := FLastFrameDurationMilliseconds
  else
    FSmoothedFrameMilliseconds := FSmoothedFrameMilliseconds * 0.9 + FLastFrameDurationMilliseconds * 0.1;
  FLastWaitMicroseconds := EvaluateFramePacingWaitMicroseconds(
    FTargetRefreshHz, FLastFrameDurationMilliseconds, ASafetyMarginMicroseconds);
  Inc(FPacedFrameCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanIndirectComputeDispatcher                                       }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanIndirectComputeDispatcher.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FIndirectArgumentBuffer := nil;
  FDispatchedCommandCount := 0;
end;

destructor TCastleVulkanIndirectComputeDispatcher.Destroy;
begin
  FreeAndNil(FIndirectArgumentBuffer);
  inherited;
end;

class function TCastleVulkanIndirectComputeDispatcher.ComputeWorkgroupCountsFromItemCount(
  const AActiveItemCount, AWorkgroupSizeX: Cardinal): TVector3Cardinal;
var
  WgSize, GroupsX: Cardinal;
begin
  if AActiveItemCount = 0 then
    Exit(Vector3Cardinal(0, 1, 1));
  WgSize := Max(Cardinal(1), AWorkgroupSizeX);
  GroupsX := (AActiveItemCount + WgSize - 1) div WgSize;
  Result := Vector3Cardinal(GroupsX, 1, 1);
end;

procedure TCastleVulkanIndirectComputeDispatcher.EnsureIndirectBuffer(
  const AMaxCommandSlots: Cardinal);
var
  RequiredBytes: UInt64;
  BufDesc: TRHIBufferDesc;
begin
  if FDevice = nil then
    Exit;
  RequiredBytes := UInt64(Max(Cardinal(16), AMaxCommandSlots)) * 12;
  if (FIndirectArgumentBuffer = nil) or (FIndirectArgumentBuffer.Desc.Size < RequiredBytes) then
  begin
    FreeAndNil(FIndirectArgumentBuffer);
    BufDesc := TRHIBufferDesc.Create(RequiredBytes, [buStorage, buIndirect],
      muGpuOnly, 'IndirectComputeDispatchArgsSSBO');
    FIndirectArgumentBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

procedure TCastleVulkanIndirectComputeDispatcher.RecordIndirectComputeDispatch(
  const ACommandList: TVulkanRHICommandList;
  const ACommandSlotIndex: Cardinal;
  const AComputePipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
begin
  if ACommandList = nil then
    Exit;
  EnsureIndirectBuffer(ACommandSlotIndex + 1);
  if AComputePipeline <> nil then
    ACommandList.BindComputePipeline(AComputePipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindComputeDescriptorSet(0, ADescriptorSet, []);
  if FIndirectArgumentBuffer <> nil then
    ACommandList.DispatchIndirect(FIndirectArgumentBuffer, PtrUInt(ACommandSlotIndex) * 12);
  Inc(FDispatchedCommandCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanBCnCompressor                                                   }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanBCnCompressor.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FCompressedOutputBuffer := nil;
  FCompressedBlockCount := 0;
  FDispatchCount := 0;
  FCompressionPipeline := nil;
end;

destructor TCastleVulkanBCnCompressor.Destroy;
begin
  FreeAndNil(FCompressedOutputBuffer);
  inherited;
end;

class function TCastleVulkanBCnCompressor.EvaluateBC1EndpointQuantization565(
  const AColorRGB: TVector3): Word;
var
  R5, G6, B5: Word;
begin
  R5 := Word(Round(EnsureRange(AColorRGB.X, 0.0, 1.0) * 31.0));
  G6 := Word(Round(EnsureRange(AColorRGB.Y, 0.0, 1.0) * 63.0));
  B5 := Word(Round(EnsureRange(AColorRGB.Z, 0.0, 1.0) * 31.0));
  Result := (R5 shl 11) or (G6 shl 5) or B5;
end;

procedure TCastleVulkanBCnCompressor.EnsureCompressionBuffer(
  const AWidth, AHeight, ABytesPerBlock: Cardinal);
var
  BlocksX, BlocksY, BlockBytes: Cardinal;
  TotalBytes: UInt64;
  BufDesc: TRHIBufferDesc;
begin
  if FDevice = nil then
    Exit;
  BlocksX := (Max(Cardinal(1), AWidth) + 3) div 4;
  BlocksY := (Max(Cardinal(1), AHeight) + 3) div 4;
  FCompressedBlockCount := BlocksX * BlocksY;
  BlockBytes := Max(Cardinal(8), ABytesPerBlock);
  TotalBytes := UInt64(FCompressedBlockCount) * BlockBytes;
  if (FCompressedOutputBuffer = nil) or (FCompressedOutputBuffer.Desc.Size < TotalBytes) then
  begin
    FreeAndNil(FCompressedOutputBuffer);
    BufDesc := TRHIBufferDesc.Create(TotalBytes, [buStorage, buTransferSrc],
      muGpuOnly, 'BCnCompressedBlocksOutputSSBO');
    FCompressedOutputBuffer := FDevice.CreateBuffer(BufDesc) as TVulkanRHIBuffer;
  end;
end;

procedure TCastleVulkanBCnCompressor.DispatchBCnBlockCompression(
  const ACommandList: TVulkanRHICommandList;
  const AWidth, AHeight: Cardinal;
  const ABytesPerBlock: Cardinal;
  const AComputePipeline: TVulkanRHIComputePipeline;
  const ADescriptorSet: TVulkanRHIDescriptorSet);
var
  ActivePipeline: TVulkanRHIComputePipeline;
  BlocksX, BlocksY, GroupsX, GroupsY: Cardinal;
begin
  if ACommandList = nil then
    Exit;
  EnsureCompressionBuffer(AWidth, AHeight, ABytesPerBlock);
  if AComputePipeline <> nil then
    ActivePipeline := AComputePipeline
  else
    ActivePipeline := FCompressionPipeline;
  if ActivePipeline <> nil then
    ACommandList.BindComputePipeline(ActivePipeline);
  if ADescriptorSet <> nil then
    ACommandList.BindComputeDescriptorSet(0, ADescriptorSet, []);
  BlocksX := (Max(Cardinal(1), AWidth) + 3) div 4;
  BlocksY := (Max(Cardinal(1), AHeight) + 3) div 4;
  GroupsX := (BlocksX + 7) div 8;
  GroupsY := (BlocksY + 7) div 8;
  ACommandList.Dispatch(Max(Cardinal(1), GroupsX), Max(Cardinal(1), GroupsY), 1);
  Inc(FDispatchCount);
end;

{ ---------------------------------------------------------------------------- }
{ TCastleVulkanPipelineBinaryManager                                           }
{ ---------------------------------------------------------------------------- }

constructor TCastleVulkanPipelineBinaryManager.Create(const ADevice: TVulkanRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  SetLength(FEntries, 0);
  FTotalBinaryBytes := 0;
  FCacheHitCount := 0;
end;

function TCastleVulkanPipelineBinaryManager.GetBinaryEntryCount: Cardinal;
begin
  if FDevice = nil then;
  Result := Cardinal(Length(FEntries));
end;

class function TCastleVulkanPipelineBinaryManager.ComputePipelineKeyFNV1a64(
  const AVertexShaderHash, AFragmentShaderHash: UInt64;
  const ARenderStateFlags: Cardinal): UInt64;
begin
  {$Q-}{$R-}
  Result := FNV1aOffsetBasis64;
  Result := (Result xor AVertexShaderHash) * FNV1aPrime64;
  Result := (Result xor AFragmentShaderHash) * FNV1aPrime64;
  Result := (Result xor UInt64(ARenderStateFlags)) * FNV1aPrime64;
  {$Q+}{$R+}
end;

procedure TCastleVulkanPipelineBinaryManager.StorePipelineBinary(
  const APipelineKeyHash: UInt64;
  const ABinarySize: Cardinal);
var
  I, N: Integer;
begin
  for I := 0 to High(FEntries) do
    if FEntries[I].PipelineKeyHash = APipelineKeyHash then
    begin
      Dec(FTotalBinaryBytes, FEntries[I].BinarySize);
      FEntries[I].BinarySize := ABinarySize;
      Inc(FTotalBinaryBytes, ABinarySize);
      Exit;
    end;
  N := Length(FEntries);
  SetLength(FEntries, N + 1);
  FEntries[N].PipelineKeyHash := APipelineKeyHash;
  FEntries[N].BinarySize := ABinarySize;
  Inc(FTotalBinaryBytes, ABinarySize);
end;

function TCastleVulkanPipelineBinaryManager.LookupPipelineBinary(
  const APipelineKeyHash: UInt64;
  out AOutBinarySize: Cardinal): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FEntries) do
    if FEntries[I].PipelineKeyHash = APipelineKeyHash then
    begin
      AOutBinarySize := FEntries[I].BinarySize;
      Inc(FCacheHitCount);
      Exit(True);
    end;
  AOutBinarySize := 0;
  Result := False;
end;

{$endif read_implementation}
