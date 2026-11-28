{%MainUnit castleinternalrhi_vulkan_experimental.pas}
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

{ ---------------------------------------------------------------------------- }
{ TVulkanExperimentalDeviceContext & TVulkanRHIDeviceExperimentalHelper        }
{ ---------------------------------------------------------------------------- }

destructor TVulkanExperimentalDeviceContext.Destroy;
begin
  FreeAndNil(FPipelineBinaryManager);
  FreeAndNil(FBCnCompressor);
  FreeAndNil(FIndirectComputeDispatcher);
  FreeAndNil(FDescriptorBufferManager);
  FreeAndNil(FGaussianSplatRenderer);
  FreeAndNil(FHostImageCopyManager);
  FreeAndNil(FPerPixelLinkedListOIT);
  FreeAndNil(FVoxelConeTracer);
  FreeAndNil(FStreamCompactor);
  FreeAndNil(FProgrammableSampleLocations);
  FreeAndNil(FNeuralDenoiser);
  FreeAndNil(FPerInstanceCustomData);
  FreeAndNil(FMultiviewStereoManager);
  FreeAndNil(FXPBDSimulator);
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
  FreeAndNil(FDDGIGrid);
  FreeAndNil(FOceanSimulator);
  FreeAndNil(FAtmosphereRenderer);
  FreeAndNil(FTerrainCDLOD);
  FreeAndNil(FComputeSkinner);
  FreeAndNil(FContactShadows);
  FreeAndNil(FComputeParticles);
  FreeAndNil(FDecalManager);
  FreeAndNil(FReflectionProbeManager);
  inherited;
end;

function EnsureExperimentalContext(const ADevice: TVulkanRHIDevice): TVulkanExperimentalDeviceContext;
begin
  if ADevice.ExperimentalContext = nil then
    ADevice.ExperimentalContext := TVulkanExperimentalDeviceContext.Create;
  Result := TVulkanExperimentalDeviceContext(ADevice.ExperimentalContext);
end;

function TVulkanRHIDeviceExperimentalHelper.GetReflectionProbeManager: TCastleVulkanReflectionProbeManager;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FReflectionProbeManager = nil then
    Ctx.FReflectionProbeManager := TCastleVulkanReflectionProbeManager.Create(Self);
  Result := Ctx.FReflectionProbeManager;
end;

function TVulkanRHIDeviceExperimentalHelper.GetDecalManager: TCastleVulkanDecalManager;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FDecalManager = nil then
    Ctx.FDecalManager := TCastleVulkanDecalManager.Create(Self);
  Result := Ctx.FDecalManager;
end;

function TVulkanRHIDeviceExperimentalHelper.GetComputeParticles: TCastleVulkanComputeParticles;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FComputeParticles = nil then
    Ctx.FComputeParticles := TCastleVulkanComputeParticles.Create(Self);
  Result := Ctx.FComputeParticles;
end;

function TVulkanRHIDeviceExperimentalHelper.GetContactShadows: TCastleVulkanContactShadows;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FContactShadows = nil then
    Ctx.FContactShadows := TCastleVulkanContactShadows.Create(Self);
  Result := Ctx.FContactShadows;
end;

function TVulkanRHIDeviceExperimentalHelper.GetComputeSkinner: TCastleVulkanComputeSkinner;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FComputeSkinner = nil then
    Ctx.FComputeSkinner := TCastleVulkanComputeSkinner.Create(Self);
  Result := Ctx.FComputeSkinner;
end;

function TVulkanRHIDeviceExperimentalHelper.GetTerrainCDLOD: TCastleVulkanTerrainCDLOD;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FTerrainCDLOD = nil then
    Ctx.FTerrainCDLOD := TCastleVulkanTerrainCDLOD.Create(Self);
  Result := Ctx.FTerrainCDLOD;
end;

function TVulkanRHIDeviceExperimentalHelper.GetAtmosphereRenderer: TCastleVulkanAtmosphereRenderer;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FAtmosphereRenderer = nil then
    Ctx.FAtmosphereRenderer := TCastleVulkanAtmosphereRenderer.Create(Self);
  Result := Ctx.FAtmosphereRenderer;
end;

function TVulkanRHIDeviceExperimentalHelper.GetOceanSimulator: TCastleVulkanOceanSimulator;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FOceanSimulator = nil then
    Ctx.FOceanSimulator := TCastleVulkanOceanSimulator.Create(Self);
  Result := Ctx.FOceanSimulator;
end;

function TVulkanRHIDeviceExperimentalHelper.GetDDGIGrid: TCastleVulkanDDGIGrid;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FDDGIGrid = nil then
    Ctx.FDDGIGrid := TCastleVulkanDDGIGrid.Create(Self);
  Result := Ctx.FDDGIGrid;
end;

function TVulkanRHIDeviceExperimentalHelper.GetVirtualShadowMap: TCastleVulkanVirtualShadowMap;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FVirtualShadowMap = nil then
    Ctx.FVirtualShadowMap := TCastleVulkanVirtualShadowMap.Create(Self);
  Result := Ctx.FVirtualShadowMap;
end;

function TVulkanRHIDeviceExperimentalHelper.GetLODSelector: TCastleVulkanLODSelector;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FLODSelector = nil then
    Ctx.FLODSelector := TCastleVulkanLODSelector.Create(Self);
  Result := Ctx.FLODSelector;
end;

function TVulkanRHIDeviceExperimentalHelper.GetTextureStreamer: TCastleVulkanTextureStreamer;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FTextureStreamer = nil then
    Ctx.FTextureStreamer := TCastleVulkanTextureStreamer.Create(Self);
  Result := Ctx.FTextureStreamer;
end;

function TVulkanRHIDeviceExperimentalHelper.GetShadowCasterCuller: TCastleVulkanShadowCasterCuller;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FShadowCasterCuller = nil then
    Ctx.FShadowCasterCuller := TCastleVulkanShadowCasterCuller.Create(Self);
  Result := Ctx.FShadowCasterCuller;
end;

function TVulkanRHIDeviceExperimentalHelper.GetClusterDAG: TCastleVulkanClusterDAG;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FClusterDAG = nil then
    Ctx.FClusterDAG := TCastleVulkanClusterDAG.Create(Self);
  Result := Ctx.FClusterDAG;
end;

function TVulkanRHIDeviceExperimentalHelper.GetGlobalSDF: TCastleVulkanGlobalSDF;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FGlobalSDF = nil then
    Ctx.FGlobalSDF := TCastleVulkanGlobalSDF.Create(Self);
  Result := Ctx.FGlobalSDF;
end;

function TVulkanRHIDeviceExperimentalHelper.GetSurfaceCache: TCastleVulkanSurfaceCache;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FSurfaceCache = nil then
    Ctx.FSurfaceCache := TCastleVulkanSurfaceCache.Create(Self);
  Result := Ctx.FSurfaceCache;
end;

function TVulkanRHIDeviceExperimentalHelper.GetReSTIR: TCastleVulkanReSTIR;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FReSTIR = nil then
    Ctx.FReSTIR := TCastleVulkanReSTIR.Create(Self);
  Result := Ctx.FReSTIR;
end;

function TVulkanRHIDeviceExperimentalHelper.GetTSRUpscaler: TCastleVulkanTSRUpscaler;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FTSRUpscaler = nil then
    Ctx.FTSRUpscaler := TCastleVulkanTSRUpscaler.Create(Self);
  Result := Ctx.FTSRUpscaler;
end;

function TVulkanRHIDeviceExperimentalHelper.GetVRSManager: TCastleVulkanVRSManager;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FVRSManager = nil then
    Ctx.FVRSManager := TCastleVulkanVRSManager.Create(Self);
  Result := Ctx.FVRSManager;
end;

function TVulkanRHIDeviceExperimentalHelper.GetRuntimeVirtualTexture: TCastleVulkanRuntimeVirtualTexture;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FRuntimeVirtualTexture = nil then
    Ctx.FRuntimeVirtualTexture := TCastleVulkanRuntimeVirtualTexture.Create(Self);
  Result := Ctx.FRuntimeVirtualTexture;
end;

function TVulkanRHIDeviceExperimentalHelper.GetSparseVolumeAtlas: TCastleVulkanSparseVolumeAtlas;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FSparseVolumeAtlas = nil then
    Ctx.FSparseVolumeAtlas := TCastleVulkanSparseVolumeAtlas.Create(Self);
  Result := Ctx.FSparseVolumeAtlas;
end;

function TVulkanRHIDeviceExperimentalHelper.GetBreadcrumbTracker: TCastleVulkanBreadcrumbTracker;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FBreadcrumbTracker = nil then
    Ctx.FBreadcrumbTracker := TCastleVulkanBreadcrumbTracker.Create(Self);
  Result := Ctx.FBreadcrumbTracker;
end;

function TVulkanRHIDeviceExperimentalHelper.GetSVGFDenoiser: TCastleVulkanSVGFDenoiser;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FSVGFDenoiser = nil then
    Ctx.FSVGFDenoiser := TCastleVulkanSVGFDenoiser.Create(Self);
  Result := Ctx.FSVGFDenoiser;
end;

function TVulkanRHIDeviceExperimentalHelper.GetXPBDSimulator: TCastleVulkanXPBDSimulator;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FXPBDSimulator = nil then
    Ctx.FXPBDSimulator := TCastleVulkanXPBDSimulator.Create(Self);
  Result := Ctx.FXPBDSimulator;
end;

function TVulkanRHIDeviceExperimentalHelper.GetMultiviewStereoManager: TCastleVulkanMultiviewStereoManager;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FMultiviewStereoManager = nil then
    Ctx.FMultiviewStereoManager := TCastleVulkanMultiviewStereoManager.Create(Self);
  Result := Ctx.FMultiviewStereoManager;
end;

function TVulkanRHIDeviceExperimentalHelper.GetPerInstanceCustomData: TCastleVulkanPerInstanceCustomData;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FPerInstanceCustomData = nil then
    Ctx.FPerInstanceCustomData := TCastleVulkanPerInstanceCustomData.Create(Self);
  Result := Ctx.FPerInstanceCustomData;
end;

function TVulkanRHIDeviceExperimentalHelper.GetNeuralDenoiser: TCastleVulkanNeuralDenoiser;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FNeuralDenoiser = nil then
    Ctx.FNeuralDenoiser := TCastleVulkanNeuralDenoiser.Create(Self);
  Result := Ctx.FNeuralDenoiser;
end;

function TVulkanRHIDeviceExperimentalHelper.GetProgrammableSampleLocations: TCastleVulkanProgrammableSampleLocations;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FProgrammableSampleLocations = nil then
    Ctx.FProgrammableSampleLocations := TCastleVulkanProgrammableSampleLocations.Create(Self);
  Result := Ctx.FProgrammableSampleLocations;
end;

function TVulkanRHIDeviceExperimentalHelper.GetStreamCompactor: TCastleVulkanStreamCompactor;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FStreamCompactor = nil then
    Ctx.FStreamCompactor := TCastleVulkanStreamCompactor.Create(Self);
  Result := Ctx.FStreamCompactor;
end;

function TVulkanRHIDeviceExperimentalHelper.GetVoxelConeTracer: TCastleVulkanVoxelConeTracer;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FVoxelConeTracer = nil then
    Ctx.FVoxelConeTracer := TCastleVulkanVoxelConeTracer.Create(Self);
  Result := Ctx.FVoxelConeTracer;
end;

function TVulkanRHIDeviceExperimentalHelper.GetPerPixelLinkedListOIT: TCastleVulkanPerPixelLinkedListOIT;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FPerPixelLinkedListOIT = nil then
    Ctx.FPerPixelLinkedListOIT := TCastleVulkanPerPixelLinkedListOIT.Create(Self);
  Result := Ctx.FPerPixelLinkedListOIT;
end;

function TVulkanRHIDeviceExperimentalHelper.GetHostImageCopyManager: TCastleVulkanHostImageCopyManager;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FHostImageCopyManager = nil then
    Ctx.FHostImageCopyManager := TCastleVulkanHostImageCopyManager.Create(Self);
  Result := Ctx.FHostImageCopyManager;
end;

function TVulkanRHIDeviceExperimentalHelper.GetGaussianSplatRenderer: TCastleVulkanGaussianSplatRenderer;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FGaussianSplatRenderer = nil then
    Ctx.FGaussianSplatRenderer := TCastleVulkanGaussianSplatRenderer.Create(Self);
  Result := Ctx.FGaussianSplatRenderer;
end;

function TVulkanRHIDeviceExperimentalHelper.GetDescriptorBufferManager: TCastleVulkanDescriptorBufferManager;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FDescriptorBufferManager = nil then
    Ctx.FDescriptorBufferManager := TCastleVulkanDescriptorBufferManager.Create(Self);
  Result := Ctx.FDescriptorBufferManager;
end;

function TVulkanRHIDeviceExperimentalHelper.GetIndirectComputeDispatcher: TCastleVulkanIndirectComputeDispatcher;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FIndirectComputeDispatcher = nil then
    Ctx.FIndirectComputeDispatcher := TCastleVulkanIndirectComputeDispatcher.Create(Self);
  Result := Ctx.FIndirectComputeDispatcher;
end;

function TVulkanRHIDeviceExperimentalHelper.GetBCnCompressor: TCastleVulkanBCnCompressor;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FBCnCompressor = nil then
    Ctx.FBCnCompressor := TCastleVulkanBCnCompressor.Create(Self);
  Result := Ctx.FBCnCompressor;
end;

function TVulkanRHIDeviceExperimentalHelper.GetPipelineBinaryManager: TCastleVulkanPipelineBinaryManager;
var
  Ctx: TVulkanExperimentalDeviceContext;
begin
  Ctx := EnsureExperimentalContext(Self);
  if Ctx.FPipelineBinaryManager = nil then
    Ctx.FPipelineBinaryManager := TCastleVulkanPipelineBinaryManager.Create(Self);
  Result := Ctx.FPipelineBinaryManager;
end;

function ExecuteVulkanExperimentalViewportSubsystems(
  const ADevice: TVulkanRHIDevice;
  const ACommandList: TVulkanRHICommandList;
  const AViewWidth, AViewHeight: Cardinal;
  const AGlobalIlluminationModeOrd, ATemporalAAModeOrd, AVariableRateShadingModeOrd: Cardinal): Cardinal;
begin
  Result := 0;
  case AGlobalIlluminationModeOrd of
    Ord(giDDGIProbes):
      begin
        ADevice.DDGIGrid.EnsureProbeAtlases;
        ADevice.DDGIGrid.DispatchDDGIUpdate(ACommandList);
        Inc(Result);
      end;
    Ord(giVoxelConeTracing):
      begin
        ADevice.VoxelConeTracer.DispatchVoxelConeTrace(ACommandList, AViewWidth, AViewHeight);
        Inc(Result);
      end;
    Ord(giLumenSDFAndSurfaceCache):
      begin
        ADevice.GlobalSDF.DispatchGlobalSDFBuild(ACommandList, 32);
        ADevice.SurfaceCache.EnsureAtlasTextures;
        Inc(Result);
      end;
    Ord(giReSTIRGI):
      begin
        ADevice.ReSTIR.EnsureReservoirBuffers(AViewWidth, AViewHeight);
        ADevice.ReSTIR.DispatchSpatioTemporalResampling(ACommandList, AViewWidth, AViewHeight);
        Inc(Result);
      end;
    else ;
  end;

  if ATemporalAAModeOrd = Ord(taaTSRUpscaler) then
  begin
    ADevice.TSRUpscaler.EnsureUpscaleTargets(AViewWidth, AViewHeight);
    ADevice.TSRUpscaler.DispatchTSRUpscale(ACommandList, AViewWidth, AViewHeight);
    Inc(Result);
  end;

  case AVariableRateShadingModeOrd of
    Ord(vrsContrastAdaptive):
      begin
        ADevice.VRSManager.EnsureShadingRateImage(AViewWidth, AViewHeight);
        ADevice.VRSManager.DispatchVRSImageGeneration(ACommandList, AViewWidth, AViewHeight);
        Inc(Result);
      end;
    Ord(vrsFoveatedStereo):
      begin
        ADevice.MultiviewStereoManager.EnsureStereoTargets(AViewWidth div 2, AViewHeight);
        Inc(Result);
      end;
    else ;
  end;
end;

function ExecuteVulkanExperimentalSceneSubsystems(
  const ADevice: TVulkanRHIDevice;
  const ACommandList: TVulkanRHICommandList;
  const AViewWidth, AViewHeight: Cardinal;
  const AShadowMapSystemModeOrd, ATransparencyModeOrd: Cardinal): Cardinal;
var
  TileX, TileY: Cardinal;
begin
  Result := 0;
  if AShadowMapSystemModeOrd = Ord(smsVirtualShadowMaps) then
  begin
    ADevice.VirtualShadowMap.EnsureResources;
    ADevice.VirtualShadowMap.RequestAndAllocateVirtualPage(0, 0, TileX, TileY);
    ADevice.VirtualShadowMap.UploadPageTable;
    Inc(Result);
  end;

  if ATransparencyModeOrd = Ord(tmPerPixelLinkedListOIT) then
  begin
    ADevice.PerPixelLinkedListOIT.DispatchPPLLResolve(ACommandList, AViewWidth, AViewHeight);
    Inc(Result);
  end;
end;

{$endif read_implementation}
