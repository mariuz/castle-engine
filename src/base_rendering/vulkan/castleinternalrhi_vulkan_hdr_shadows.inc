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
    BufDesc := Default(TRHIBufferDesc);
    BufDesc.Size := SizeOf(TCastleClusterCullingUniformBlock);
    BufDesc.Usage := [buUniform, buTransferDst];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'ClusterCullingUBO';
    FClusterUniformBuffer := FDevice.CreateBuffer(BufDesc);
  end;

  if FLightStorageBuffer = nil then
  begin
    BufDesc := Default(TRHIBufferDesc);
    BufDesc.Size := PtrUInt(CASTLE_MAX_CLUSTERED_LIGHTS) * SizeOf(TCastleClusteredLight);
    BufDesc.Usage := [buStorage, buTransferDst];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'ClusteredLightsSSBO';
    FLightStorageBuffer := FDevice.CreateBuffer(BufDesc);
  end;

  if FClusterGridBuffer = nil then
  begin
    BufDesc := Default(TRHIBufferDesc);
    BufDesc.Size := PtrUInt(Total) * SizeOf(TCastleClusterGridEntry);
    BufDesc.Usage := [buStorage, buTransferDst, buTransferSrc];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'ClusterGridSSBO';
    FClusterGridBuffer := FDevice.CreateBuffer(BufDesc);
  end;

  if FLightIndexBuffer = nil then
  begin
    BufDesc := Default(TRHIBufferDesc);
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

    CompDesc := Default(TRHIComputePipelineDesc);
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
    BufDesc := Default(TRHIBufferDesc);
    BufDesc.Size := SizeOf(TCastleDirectionalCascadeShadowBlock);
    BufDesc.Usage := [buUniform, buTransferDst];
    BufDesc.MemoryUsage := muCpuToGpu;
    BufDesc.DebugName := 'DirectionalCascadeShadowUBO';
    FCascadeUniformBuffer := FDevice.CreateBuffer(BufDesc);
  end;

  if FPositionalTileBuffer = nil then
  begin
    BufDesc := Default(TRHIBufferDesc);
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

  RenderInfo := Default(TRHIRenderingInfo);
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
  FAOStrength := 1.0;
  FSSRStrength := 1.0;

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
  { Graphics/compute pipelines are owned by FDevice.FPipelineMap / FComputePipelineMap }
  FBloomDownsamplePipeline := nil;
  FBloomUpsamplePipeline := nil;
  FHistogramPipeline := nil;
  FModulatePipeline := nil;
  FHiZCopyPipeline := nil;
  FCompositePipeline := nil;
  FreeAndNil(FHiZCopyShader);
  FreeAndNil(FModulateShader);
  FreeAndNil(FCompositeVertShader);
  FreeAndNil(FCompositeFragShader);
  FreeAndNil(FHistogramShader);
  FreeAndNil(FBloomUpsampleShader);
  FreeAndNil(FBloomDownsampleShader);
  FreeAndNil(FHiZCopyDescriptorSet);
  FreeAndNil(FHiZCopyDescriptorLayout);
  FreeAndNil(FModulateDescriptorSet);
  FreeAndNil(FModulateDescriptorLayout);
  FreeAndNil(FCompositeDescriptorSet);
  FreeAndNil(FCompositeDescriptorLayout);
  FreeAndNil(FHistogramDescriptorSet);
  FreeAndNil(FHistogramDescriptorLayout);
  for I := 0 to CASTLE_BLOOM_MAX_MIP_LEVELS - 1 do
  begin
    FreeAndNil(FBloomDownsampleSets[I]);
    FreeAndNil(FBloomUpsampleSets[I]);
  end;
  FreeAndNil(FBloomDescriptorSet);
  FreeAndNil(FBloomDescriptorLayout);
  FreeAndNil(FExposureStateBuffer);
  FreeAndNil(FHistogramBuffer);
  FreeAndNil(FLinearClampSampler);
  FreeAndNil(FBlackFallbackTexture);
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
  BlackDesc: TRHITextureDesc;
  BlackImg: TRGBAlphaImage;
  BloomBindings: array[0..1] of TRHIDescriptorBindingDesc;
  HistBindings: array[0..2] of TRHIDescriptorBindingDesc;
  CompBindings: array[0..2] of TRHIDescriptorBindingDesc;
  ModBindings: array[0..3] of TRHIDescriptorBindingDesc;
  ShaderGen: TCastleShaderGeneratorRHI;
  CompDesc: TRHIComputePipelineDesc;
  InitialExposureState: array[0..3] of Single;
  ZeroHistBins: array[0..CASTLE_LUMINANCE_HISTOGRAM_BINS - 1] of Cardinal;
  I: Integer;
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

  if FBlackFallbackTexture = nil then
  begin
    BlackDesc := TRHITextureDesc.Create2D(1, 1, pfRGBA16_Float,
      [tuSampled, tuTransferDst], 1, 1);
    BlackDesc.DebugName := 'HDRPostBlackFallback1x1';
    FBlackFallbackTexture := FDevice.CreateTexture(BlackDesc) as TVulkanRHITexture;
    BlackImg := TRGBAlphaImage.Create(1, 1);
    try
      BlackImg.Clear(Vector4Byte(0, 0, 0, 255));
      FBlackFallbackTexture.UploadImage(BlackImg);
    finally
      FreeAndNil(BlackImg);
    end;
  end;

  if FHistogramBuffer = nil then
  begin
    FillChar(ZeroHistBins[0], SizeOf(ZeroHistBins), 0);
    BufDesc := TRHIBufferDesc.Create(
      CASTLE_LUMINANCE_HISTOGRAM_BINS * SizeOf(Cardinal),
      [buStorage, buTransferSrc, buTransferDst], muCpuToGpu, 'LuminanceHistogramSSBO');
    FHistogramBuffer := FDevice.CreateBuffer(BufDesc, @ZeroHistBins[0]);
  end;

  if FExposureStateBuffer = nil then
  begin
    InitialExposureState[0] := FAdaptedLuminance;
    InitialExposureState[1] := FAdaptedExposure;
    InitialExposureState[2] := FTargetLuminance;
    InitialExposureState[3] := 0.0;
    BufDesc := TRHIBufferDesc.Create(
      4 * SizeOf(Single),
      [buStorage, buTransferSrc, buTransferDst], muCpuToGpu, 'AutoExposureStateSSBO');
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
    for I := 0 to CASTLE_BLOOM_MAX_MIP_LEVELS - 1 do
    begin
      FBloomDownsampleSets[I] := FDevice.CreateDescriptorSet(FBloomDescriptorLayout);
      FBloomUpsampleSets[I] := FDevice.CreateDescriptorSet(FBloomDescriptorLayout);
    end;
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

  if FCompositeDescriptorLayout = nil then
  begin
    FillChar(CompBindings, SizeOf(CompBindings), 0);
    CompBindings[0].Binding := 0;
    CompBindings[0].DescriptorType := dtCombinedImageSampler;
    CompBindings[0].Count := 1;
    CompBindings[0].StageFlags := [ssFragment];
    CompBindings[1].Binding := 1;
    CompBindings[1].DescriptorType := dtCombinedImageSampler;
    CompBindings[1].Count := 1;
    CompBindings[1].StageFlags := [ssFragment];
    CompBindings[2].Binding := 2;
    CompBindings[2].DescriptorType := dtStorageBuffer;
    CompBindings[2].Count := 1;
    CompBindings[2].StageFlags := [ssFragment];
    FCompositeDescriptorLayout := FDevice.CreateDescriptorSetLayout(CompBindings);
    FCompositeDescriptorSet := FDevice.CreateDescriptorSet(FCompositeDescriptorLayout);
  end;

  if FModulateDescriptorLayout = nil then
  begin
    FillChar(ModBindings, SizeOf(ModBindings), 0);
    for I := 0 to 2 do
    begin
      ModBindings[I].Binding := Cardinal(I);
      ModBindings[I].DescriptorType := dtCombinedImageSampler;
      ModBindings[I].Count := 1;
      ModBindings[I].StageFlags := [ssCompute];
    end;
    ModBindings[3].Binding := 3;
    ModBindings[3].DescriptorType := dtStorageImage;
    ModBindings[3].Count := 1;
    ModBindings[3].StageFlags := [ssCompute];
    FModulateDescriptorLayout := FDevice.CreateDescriptorSetLayout(ModBindings);
    FModulateDescriptorSet := FDevice.CreateDescriptorSet(FModulateDescriptorLayout);
  end;

  if FHiZCopyDescriptorLayout = nil then
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
    FHiZCopyDescriptorLayout := FDevice.CreateDescriptorSetLayout(BloomBindings);
    FHiZCopyDescriptorSet := FDevice.CreateDescriptorSet(FHiZCopyDescriptorLayout);
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
      FCompositeVertShader := FDevice.CreateShaderModuleFromGLSL(
        ssVertex, ShaderGen.GenerateHDRCompositeVertexShader, 'HDRCompositeVS');
      FCompositeFragShader := FDevice.CreateShaderModuleFromGLSL(
        ssFragment, ShaderGen.GenerateHDRCompositeFragmentShader, 'HDRCompositeFS');
      FModulateShader := FDevice.CreateShaderModuleFromGLSL(
        ssCompute, ShaderGen.GeneratePostProcessModulateComputeShader(8, 8), 'PostProcessModulateCS');
      FHiZCopyShader := FDevice.CreateShaderModuleFromGLSL(
        ssCompute, ShaderGen.GenerateHiZDownsampleComputeShader(8, 8), 'HiZDownsampleCS');
    finally
      FreeAndNil(ShaderGen);
    end;

    CompDesc := Default(TRHIComputePipelineDesc);
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

    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FHistogramShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FHistogramDescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleAutoExposureParams);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'LuminanceHistogramPSO';
    FHistogramPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);

    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FModulateShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FModulateDescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastlePostProcessModulatePushConstants);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'PostProcessModulatePSO';
    FModulatePipeline := FDevice.GetOrCreateComputePipeline(CompDesc);

    CompDesc := Default(TRHIComputePipelineDesc);
    CompDesc.ComputeShader := FHiZCopyShader;
    SetLength(CompDesc.DescriptorSetLayouts, 1);
    CompDesc.DescriptorSetLayouts[0] := FHiZCopyDescriptorLayout;
    CompDesc.PushConstantSize := SizeOf(TCastleHiZPushConstants);
    CompDesc.PushConstantStages := [ssCompute];
    CompDesc.DebugName := 'PostProcessHiZCopyPSO';
    FHiZCopyPipeline := FDevice.GetOrCreateComputePipeline(CompDesc);
  end;
end;

function TCastleVulkanHDRPostProcessor.GetOrCreateCompositePipelineForFormat(
  const AFormat: TRHIPixelFormat): TRHIPipeline;
var
  PipeDesc: TRHIGraphicsPipelineDesc;
  EffFormat: TRHIPixelFormat;
begin
  EnsurePipelinesCreated;
  if AFormat <> pfUndefined then
    EffFormat := AFormat
  else
    EffFormat := pfRGBA8_UNorm;

  if (FCompositePipeline <> nil) and (FCompositePipelineFormat = EffFormat) then
    Exit(FCompositePipeline);

  PipeDesc := Default(TRHIGraphicsPipelineDesc);
  PipeDesc.VertexShader := FCompositeVertShader;
  PipeDesc.FragmentShader := FCompositeFragShader;
  PipeDesc.Topology := ptTriangleList;
  PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  PipeDesc.Rasterizer.CullMode := cmNone;
  PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDisabled;
  PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
  SetLength(PipeDesc.DescriptorSetLayouts, 1);
  PipeDesc.DescriptorSetLayouts[0] := FCompositeDescriptorLayout;
  PipeDesc.PushConstantSize := SizeOf(TCastleHDRCompositePushConstants);
  PipeDesc.PushConstantStages := [ssFragment];
  SetLength(PipeDesc.ColorAttachmentFormats, 1);
  PipeDesc.ColorAttachmentFormats[0] := EffFormat;
  PipeDesc.DepthAttachmentFormat := pfUndefined;
  PipeDesc.SampleCount := 1;
  PipeDesc.DebugName := 'HDRCompositeFullscreenPSO';

  FCompositePipeline := FDevice.GetOrCreatePipeline(PipeDesc);
  FCompositePipelineFormat := EffFormat;
  Result := FCompositePipeline;
end;

function TCastleVulkanHDRPostProcessor.DispatchBloomPyramidFromTexture(
  const ACmd: TRHICommandList;
  const ASrcHDRTexture: TRHITexture;
  const ADstBloomMip0Override: TRHITexture): Cardinal;
var
  M: Integer;
  SrcTex, DstTex, RootHDR: TRHITexture;
  Mip0Target: TRHITexture;
  ActiveSet: TRHIDescriptorSet;
  PC: TCastleBloomPushConstants;
  GroupsX, GroupsY: Cardinal;
begin
  Result := 0;
  if (FWidth = 0) or (FHeight = 0) then
  begin
    if ASrcHDRTexture <> nil then
      EnsureHDRTargets(ASrcHDRTexture.Desc.Width, ASrcHDRTexture.Desc.Height)
    else
      EnsureHDRTargets(1280, 720);
  end;
  EnsurePipelinesCreated;

  if ASrcHDRTexture <> nil then
    RootHDR := ASrcHDRTexture
  else
    RootHDR := FHDRSceneTexture;

  if (FBloomMipCount = 0) or (RootHDR = nil) then
    Exit;

  if ADstBloomMip0Override <> nil then
    Mip0Target := ADstBloomMip0Override
  else
    Mip0Target := FBloomMipTextures[0];

  { 1. Progressive 13-tap Jiménez Downsample Chain (RootHDR -> Mip 0 -> Mip 1 -> ... -> Mip N-1) }
  for M := 0 to Integer(FBloomMipCount) - 1 do
  begin
    if M = 0 then
      SrcTex := RootHDR
    else if M = 1 then
      SrcTex := Mip0Target
    else
      SrcTex := FBloomMipTextures[M - 1];

    if M = 0 then
      DstTex := Mip0Target
    else
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
      ACmd.TransitionTexture(DstTex, rsUnorderedAccess);
      ActiveSet := FBloomDownsampleSets[M];
      ActiveSet.BindTexture(0, SrcTex, FLinearClampSampler);
      ActiveSet.BindTexture(1, DstTex, FLinearClampSampler);
      ActiveSet.Update;
      ACmd.BindComputePipeline(FBloomDownsamplePipeline);
      ACmd.BindComputeDescriptorSet(0, ActiveSet, []);
      ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
      ACmd.Dispatch(GroupsX, GroupsY, 1);
    end;

    Inc(FTotalBloomDownsampleDispatches);
    Inc(Result);
  end;

  { 2. Progressive 9-tap 3x3 Tent-Filter Upsample Chain (Mip N-1 -> Mip N-2 -> ... -> Mip 0 / Override) }
  if FBloomMipCount > 1 then
    for M := Integer(FBloomMipCount) - 1 downto 1 do
    begin
      SrcTex := FBloomMipTextures[M];
      if (M = 1) and (ADstBloomMip0Override <> nil) then
        DstTex := ADstBloomMip0Override
      else
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
        ACmd.TransitionTexture(DstTex, rsUnorderedAccess);
        ActiveSet := FBloomUpsampleSets[M];
        ActiveSet.BindTexture(0, SrcTex, FLinearClampSampler);
        ActiveSet.BindTexture(1, DstTex, FLinearClampSampler);
        ActiveSet.Update;
        ACmd.BindComputePipeline(FBloomUpsamplePipeline);
        ACmd.BindComputeDescriptorSet(0, ActiveSet, []);
        ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
        ACmd.Dispatch(GroupsX, GroupsY, 1);
      end;

      Inc(FTotalBloomUpsampleDispatches);
      Inc(Result);
    end;

  if (ACmd <> nil) and (Mip0Target <> nil) then
    ACmd.TransitionTexture(Mip0Target, rsShaderRead);
end;

function TCastleVulkanHDRPostProcessor.DispatchBloomPyramid(
  const ACmd: TRHICommandList): Cardinal;
begin
  Result := DispatchBloomPyramidFromTexture(ACmd, FHDRSceneTexture, nil);
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

procedure TCastleVulkanHDRPostProcessor.DispatchLuminanceHistogramOnGPU(
  const ACmd: TRHICommandList; const ASrcHDRTexture: TRHITexture);
var
  ZeroBins: array[0..CASTLE_LUMINANCE_HISTOGRAM_BINS - 1] of Cardinal;
  SrcTex: TRHITexture;
begin
  EnsurePipelinesCreated;
  if ASrcHDRTexture <> nil then
    SrcTex := ASrcHDRTexture
  else
    SrcTex := FHDRSceneTexture;
  if (ACmd = nil) or (SrcTex = nil) or (FHistogramBuffer = nil) then
    Exit;

  FillChar(ZeroBins[0], SizeOf(ZeroBins), 0);
  FHistogramBuffer.UploadData(ZeroBins[0], SizeOf(ZeroBins), 0);
  FAutoExposureParams.TotalPixels := Max(Cardinal(1), SrcTex.Desc.Width * SrcTex.Desc.Height);

  ACmd.TransitionTexture(SrcTex, rsShaderRead);
  FHistogramDescriptorSet.BindTexture(0, SrcTex, FLinearClampSampler);
  FHistogramDescriptorSet.BindStorageBuffer(1, FHistogramBuffer, 0, FHistogramBuffer.Desc.Size);
  FHistogramDescriptorSet.BindStorageBuffer(2, FExposureStateBuffer, 0, FExposureStateBuffer.Desc.Size);
  FHistogramDescriptorSet.Update;

  ACmd.BindComputePipeline(FHistogramPipeline);
  ACmd.BindComputeDescriptorSet(0, FHistogramDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(FAutoExposureParams), FAutoExposureParams);
  ACmd.Dispatch((SrcTex.Desc.Width + 15) div 16, (SrcTex.Desc.Height + 15) div 16, 1);
  if ACmd is TVulkanRHICommandList then
    TVulkanRHICommandList(ACmd).TransitionBuffer(FHistogramBuffer, rsUnorderedAccess, rsShaderRead);
  Inc(FTotalHistogramDispatches);
end;

function TCastleVulkanHDRPostProcessor.ReadBackGpuHistogramBins(
  out AOutBins: array of Cardinal): Cardinal;
var
  VkBuf: TVulkanRHIBuffer;
  Mapped: PCardinal;
  I, CopyCount: Integer;
begin
  Result := 0;
  if (FDevice = nil) or (FHistogramBuffer = nil) then
    Exit;
  FDevice.WaitIdle;
  VkBuf := FHistogramBuffer as TVulkanRHIBuffer;
  if VkBuf.Allocation.IsValid and (FDevice.MemoryAllocator <> nil) then
    FDevice.MemoryAllocator.InvalidateAllocation(VkBuf.Allocation, 0, VkBuf.Desc.Size);
  Mapped := PCardinal(VkBuf.Map);
  if Mapped <> nil then
  try
    Move(Mapped^, FHistogramBins[0], SizeOf(FHistogramBins));
    CopyCount := Min(Length(AOutBins), Integer(CASTLE_LUMINANCE_HISTOGRAM_BINS));
    for I := 0 to CopyCount - 1 do
      AOutBins[I] := FHistogramBins[I];
    for I := 0 to CASTLE_LUMINANCE_HISTOGRAM_BINS - 1 do
      Inc(Result, FHistogramBins[I]);
  finally
    VkBuf.Unmap;
  end;
end;

procedure TCastleVulkanHDRPostProcessor.DispatchPostProcessModulate(
  const ACmd: TRHICommandList;
  const ASrcHDR, AGTAOTex, ASSRTex, ADstModulatedHDR: TRHITexture;
  const AAOStrength, ASSRStrength: Single);
var
  PC: TCastlePostProcessModulatePushConstants;
  SafeAO, SafeSSR: TRHITexture;
begin
  EnsurePipelinesCreated;
  if (ACmd = nil) or (ASrcHDR = nil) or (ADstModulatedHDR = nil) then
    Exit;

  if AGTAOTex <> nil then SafeAO := AGTAOTex else SafeAO := FBlackFallbackTexture;
  if ASSRTex <> nil then SafeSSR := ASSRTex else SafeSSR := FBlackFallbackTexture;

  ACmd.TransitionTexture(ASrcHDR, rsShaderRead);
  if SafeAO <> nil then ACmd.TransitionTexture(SafeAO, rsShaderRead);
  if SafeSSR <> nil then ACmd.TransitionTexture(SafeSSR, rsShaderRead);
  ACmd.TransitionTexture(ADstModulatedHDR, rsUnorderedAccess);

  FModulateDescriptorSet.BindTexture(0, ASrcHDR, FLinearClampSampler);
  FModulateDescriptorSet.BindTexture(1, SafeAO, FLinearClampSampler);
  FModulateDescriptorSet.BindTexture(2, SafeSSR, FLinearClampSampler);
  FModulateDescriptorSet.BindTexture(3, ADstModulatedHDR, FLinearClampSampler);
  FModulateDescriptorSet.Update;

  FillChar(PC, SizeOf(PC), 0);
  if AGTAOTex <> nil then PC.AOStrength := AAOStrength else PC.AOStrength := 0.0;
  if ASSRTex <> nil then PC.SSRStrength := ASSRStrength else PC.SSRStrength := 0.0;
  PC.DstWidth := Max(Cardinal(1), ADstModulatedHDR.Desc.Width);
  PC.DstHeight := Max(Cardinal(1), ADstModulatedHDR.Desc.Height);

  ACmd.BindComputePipeline(FModulatePipeline);
  ACmd.BindComputeDescriptorSet(0, FModulateDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch((PC.DstWidth + 7) div 8, (PC.DstHeight + 7) div 8, 1);
end;

procedure TCastleVulkanHDRPostProcessor.ExecuteCompositeFromTextures(
  const ACmd: TRHICommandList;
  const ASrcHDR, ASrcBloom, ADstLDRTarget: TRHITexture;
  const AInsideRenderGraphPass: Boolean);
var
  RenderInfo: TRHIRenderingInfo;
  TargetW, TargetH: Cardinal;
  PC: TCastleHDRCompositePushConstants;
  SafeHDR, SafeBloom: TRHITexture;
  CompPipe: TRHIPipeline;
begin
  EnsurePipelinesCreated;
  if (ACmd <> nil) and (ADstLDRTarget <> nil) then
  begin
    TargetW := Max(Cardinal(1), ADstLDRTarget.Desc.Width);
    TargetH := Max(Cardinal(1), ADstLDRTarget.Desc.Height);
    if ASrcHDR <> nil then SafeHDR := ASrcHDR
    else if FHDRSceneTexture <> nil then SafeHDR := FHDRSceneTexture
    else SafeHDR := FBlackFallbackTexture;

    if ASrcBloom <> nil then SafeBloom := ASrcBloom
    else if FBloomMipTextures[0] <> nil then SafeBloom := FBloomMipTextures[0]
    else SafeBloom := FBlackFallbackTexture;

    CompPipe := GetOrCreateCompositePipelineForFormat(ADstLDRTarget.Desc.Format);
    FCompositeDescriptorSet.BindTexture(0, SafeHDR, FLinearClampSampler);
    FCompositeDescriptorSet.BindTexture(1, SafeBloom, FLinearClampSampler);
    FCompositeDescriptorSet.BindStorageBuffer(2, FExposureStateBuffer, 0, FExposureStateBuffer.Desc.Size);
    FCompositeDescriptorSet.Update;

    if not AInsideRenderGraphPass then
    begin
      if SafeHDR <> nil then
        ACmd.TransitionTexture(SafeHDR, rsShaderRead);
      if SafeBloom <> nil then
        ACmd.TransitionTexture(SafeBloom, rsShaderRead);
      ACmd.TransitionTexture(ADstLDRTarget, rsColorAttachment);

      RenderInfo := TRHIRenderingInfo.CreateColorDepth(
        Rectangle(0, 0, TargetW, TargetH),
        ADstLDRTarget, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
        nil, loDontCare, 1.0);
      ACmd.BeginRendering(RenderInfo);
      ACmd.SetViewport(FloatRectangle(0, 0, TargetW, TargetH));
      ACmd.SetScissor(RenderInfo.RenderArea);
    end;

    FillChar(PC, SizeOf(PC), 0);
    PC.Exposure := FExposure;
    PC.BloomIntensity := FBloomIntensity;
    PC.Gamma := FGamma;
    PC.Saturation := FSaturation;
    PC.Contrast := FContrast;
    PC.TonemapOperator := Ord(FTonemapOperator);
    if FEnableBloom and (SafeBloom <> FBlackFallbackTexture) then
      PC.EnableBloom := 1
    else
      PC.EnableBloom := 0;
    if FEnableAutoExposure then PC.EnableAutoExposure := 1 else PC.EnableAutoExposure := 0;

    if CompPipe <> nil then
      ACmd.BindPipeline(CompPipe);
    ACmd.BindDescriptorSet(0, FCompositeDescriptorSet, []);
    ACmd.PushConstants([ssFragment], 0, SizeOf(PC), PC);
    ACmd.Draw(3, 1, 0, 0);

    if not AInsideRenderGraphPass then
      ACmd.EndRendering;
  end;
  Inc(FTotalCompositePasses);
end;

procedure TCastleVulkanHDRPostProcessor.ExecuteCompositePass(
  const ACmd: TRHICommandList; const ADstLDRTarget: TRHITexture);
begin
  ExecuteCompositeFromTextures(ACmd, FHDRSceneTexture, FBloomMipTextures[0], ADstLDRTarget, False);
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
  PassBloom.WriteStorageTexture(HBloomMip0, rsUnorderedAccess);

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

procedure TCastleVulkanHDRPostProcessor.HandleNextGenForwardPass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
begin
  if Assigned(FNextGenForwardCallback) then
    FNextGenForwardCallback(AGraph, APass, ACmd);
end;

procedure TCastleVulkanHDRPostProcessor.HandleNextGenHiZPass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
var
  DepthTex, HiZTex: TRHITexture;
  PC: TCastleHiZPushConstants;
begin
  if APass = nil then ;
  DepthTex := AGraph.ResolvePhysicalTexture(FRGSceneDepth);
  HiZTex := AGraph.ResolvePhysicalTexture(FRGHiZMip0);
  if (ACmd = nil) or (DepthTex = nil) or (HiZTex = nil) or (FHiZCopyPipeline = nil) then
    Exit;

  FHiZCopyDescriptorSet.BindTexture(0, DepthTex, FLinearClampSampler);
  FHiZCopyDescriptorSet.BindTexture(1, HiZTex, FLinearClampSampler);
  FHiZCopyDescriptorSet.Update;

  FillChar(PC, SizeOf(PC), 0);
  PC.DstMipWidth := Max(Cardinal(1), HiZTex.Desc.Width);
  PC.DstMipHeight := Max(Cardinal(1), HiZTex.Desc.Height);
  PC.SrcMipWidth := Max(Cardinal(1), DepthTex.Desc.Width);
  PC.SrcMipHeight := Max(Cardinal(1), DepthTex.Desc.Height);

  ACmd.BindComputePipeline(FHiZCopyPipeline);
  ACmd.BindComputeDescriptorSet(0, FHiZCopyDescriptorSet, []);
  ACmd.PushConstants([ssCompute], 0, SizeOf(PC), PC);
  ACmd.Dispatch((PC.DstMipWidth + 7) div 8, (PC.DstMipHeight + 7) div 8, 1);
end;

procedure TCastleVulkanHDRPostProcessor.HandleNextGenGTAOHorizonPass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
var
  DepthTex, RawAOTex: TRHITexture;
begin
  if APass = nil then ;
  DepthTex := AGraph.ResolvePhysicalTexture(FRGSceneDepth);
  RawAOTex := AGraph.ResolvePhysicalTexture(FRGGTAORaw);
  if (FDevice <> nil) and (ACmd <> nil) and (DepthTex <> nil) and (RawAOTex <> nil) then
    FDevice.GTAO.DispatchGTAOHorizonToTarget(ACmd, DepthTex, RawAOTex);
end;

procedure TCastleVulkanHDRPostProcessor.HandleNextGenGTAODenoisePass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
var
  DepthTex, RawAOTex, DenoisedAOTex: TRHITexture;
begin
  if APass = nil then ;
  DepthTex := AGraph.ResolvePhysicalTexture(FRGSceneDepth);
  RawAOTex := AGraph.ResolvePhysicalTexture(FRGGTAORaw);
  DenoisedAOTex := AGraph.ResolvePhysicalTexture(FRGGTAODenoised);
  if (FDevice <> nil) and (ACmd <> nil) and (DepthTex <> nil) and
     (RawAOTex <> nil) and (DenoisedAOTex <> nil) then
    FDevice.GTAO.DispatchGTAODenoiseToTarget(ACmd, DepthTex, RawAOTex, DenoisedAOTex);
end;

procedure TCastleVulkanHDRPostProcessor.HandleNextGenSSRPass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
var
  HDRRawTex, HiZTex, SSRTex: TRHITexture;
begin
  if APass = nil then ;
  HDRRawTex := AGraph.ResolvePhysicalTexture(FRGSceneHDRRaw);
  HiZTex := AGraph.ResolvePhysicalTexture(FRGHiZMip0);
  SSRTex := AGraph.ResolvePhysicalTexture(FRGSSRReflection);
  if (FDevice <> nil) and (ACmd <> nil) and (HDRRawTex <> nil) and
     (HiZTex <> nil) and (SSRTex <> nil) then
    FDevice.SSR.DispatchSSRToTarget(ACmd, HDRRawTex, HiZTex, SSRTex);
end;

procedure TCastleVulkanHDRPostProcessor.HandleNextGenModulatePass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
var
  HDRRawTex, DenoisedAOTex, SSRTex, HDRLitTex: TRHITexture;
begin
  if APass = nil then ;
  HDRRawTex := AGraph.ResolvePhysicalTexture(FRGSceneHDRRaw);
  DenoisedAOTex := AGraph.ResolvePhysicalTexture(FRGGTAODenoised);
  SSRTex := AGraph.ResolvePhysicalTexture(FRGSSRReflection);
  HDRLitTex := AGraph.ResolvePhysicalTexture(FRGSceneHDRLit);
  DispatchPostProcessModulate(ACmd, HDRRawTex, DenoisedAOTex, SSRTex, HDRLitTex,
    FAOStrength, FSSRStrength);
end;

procedure TCastleVulkanHDRPostProcessor.HandleNextGenBloomPass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
var
  HDRLitTex, BloomMip0Tex: TRHITexture;
begin
  if APass = nil then ;
  HDRLitTex := AGraph.ResolvePhysicalTexture(FRGSceneHDRLit);
  BloomMip0Tex := AGraph.ResolvePhysicalTexture(FRGBloomMip0);
  DispatchBloomPyramidFromTexture(ACmd, HDRLitTex, BloomMip0Tex);
end;

procedure TCastleVulkanHDRPostProcessor.HandleNextGenHistogramPass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
var
  HDRLitTex: TRHITexture;
begin
  if APass = nil then ;
  HDRLitTex := AGraph.ResolvePhysicalTexture(FRGSceneHDRLit);
  DispatchLuminanceHistogramOnGPU(ACmd, HDRLitTex);
end;

procedure TCastleVulkanHDRPostProcessor.HandleNextGenCompositePass(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
var
  HDRLitTex, BloomMip0Tex, FinalLDRTex: TRHITexture;
begin
  if APass = nil then ;
  HDRLitTex := AGraph.ResolvePhysicalTexture(FRGSceneHDRLit);
  BloomMip0Tex := AGraph.ResolvePhysicalTexture(FRGBloomMip0);
  FinalLDRTex := AGraph.ResolvePhysicalTexture(FRGFinalLDR);
  ExecuteCompositeFromTextures(ACmd, HDRLitTex, BloomMip0Tex, FinalLDRTex, True);
end;

procedure TCastleVulkanHDRPostProcessor.BuildNextGenPostProcessRenderGraph(
  const AGraph: TRHIRenderGraph;
  const AWidth, AHeight: Cardinal;
  const AFinalLDRTarget: TRHITexture;
  const ASceneForwardDrawCallback: TRHIRenderGraphPassExecuteEvent;
  const AIncludeDeadDebugPass: Boolean);
var
  HDRColorDesc, HDRLitDesc, HDRDepthDesc, HiZMip0Desc, GTAODesc, SSRDesc, BloomMip0Desc, DeadDesc: TRHITextureDesc;
  HExposureBuf, HDeadScratch: TRHIRenderGraphResourceHandle;
  FinalExportState: TRHIResourceState;
  PassForward, PassHiZ, PassGTAOHorizon, PassGTAODenoise, PassSSR,
    PassModulate, PassBloom, PassHistogram, PassComposite, PassDead: TRHIRenderGraphPass;
begin
  if AGraph = nil then Exit;
  EnsureHDRTargets(AWidth, AHeight);
  EnsurePipelinesCreated;
  if AFinalLDRTarget = nil then ;
  FNextGenForwardCallback := ASceneForwardDrawCallback;

  { Pre-create composite PSO outside active render pass }
  if AFinalLDRTarget <> nil then
    GetOrCreateCompositePipelineForFormat(AFinalLDRTarget.Desc.Format)
  else
    GetOrCreateCompositePipelineForFormat(pfRGBA8_UNorm);

  AGraph.Reset;

  HDRColorDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRGBA16_Float,
    [tuColorAttachment, tuSampled, tuStorage, tuTransferSrc, tuTransferDst], 1, 1);
  HDRLitDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRGBA16_Float,
    [tuSampled, tuStorage, tuTransferSrc], 1, 1);
  HDRDepthDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfD32_Float,
    [tuDepthStencil, tuSampled, tuTransferSrc, tuTransferDst], 1, 1);
  HiZMip0Desc := TRHITextureDesc.Create2D(
    Max(Cardinal(1), FWidth div 2), Max(Cardinal(1), FHeight div 2), pfR32_Float,
    [tuSampled, tuStorage], 1, 1);
  GTAODesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfR16_Float,
    [tuSampled, tuStorage, tuTransferSrc], 1, 1);
  SSRDesc := TRHITextureDesc.Create2D(
    FWidth, FHeight, pfRGBA16_Float,
    [tuSampled, tuStorage, tuTransferSrc], 1, 1);
  BloomMip0Desc := TRHITextureDesc.Create2D(
    Max(Cardinal(1), FWidth div 2), Max(Cardinal(1), FHeight div 2), pfRGBA16_Float,
    [tuSampled, tuStorage, tuTransferSrc], 1, 1);

  FRGSceneHDRRaw := AGraph.DeclareTransientTexture('RG_SceneHDRRaw', HDRColorDesc);
  FRGSceneDepth := AGraph.DeclareTransientTexture('RG_SceneDepth', HDRDepthDesc);
  FRGHiZMip0 := AGraph.DeclareTransientTexture('RG_HiZDepthMip0', HiZMip0Desc);
  FRGGTAORaw := AGraph.DeclareTransientTexture('RG_GTAORaw', GTAODesc);
  FRGGTAODenoised := AGraph.DeclareTransientTexture('RG_GTAODenoised', GTAODesc);
  FRGSSRReflection := AGraph.DeclareTransientTexture('RG_SSRReflection', SSRDesc);
  FRGSceneHDRLit := AGraph.DeclareTransientTexture('RG_SceneHDRLit', HDRLitDesc);
  FRGBloomMip0 := AGraph.DeclareTransientTexture('RG_BloomMip0', BloomMip0Desc);

  if (AFinalLDRTarget <> nil) and (tuTransferSrc in AFinalLDRTarget.Desc.Usage) then
    FinalExportState := rsShaderRead
  else
    FinalExportState := rsPresent;
  FRGFinalLDR := AGraph.ImportExternalTexture('RG_FinalLDRTarget', AFinalLDRTarget,
    rsUndefined, FinalExportState);
  HExposureBuf := AGraph.ImportExternalBuffer('RG_AutoExposureState', FExposureStateBuffer);

  { 1. Forward 3D HDR + Depth Pass }
  PassForward := AGraph.AddPass('Forward3DHDRPass', rgptGraphics);
  PassForward.WriteColorAttachment(FRGSceneHDRRaw, loClear, Vector4(0.0, 0.0, 0.0, 1.0), soStore);
  PassForward.WriteDepthAttachment(FRGSceneDepth, loClear, 1.0, soStore);
  PassForward.OnExecute := {$ifdef FPC}@{$endif}HandleNextGenForwardPass;

  { 2. Hi-Z Conservative Half-Res Depth Pyramid Mip0 Pass }
  PassHiZ := AGraph.AddPass('HiZDepthCopyComputePass', rgptCompute);
  PassHiZ.ReadTexture(FRGSceneDepth, rsShaderRead);
  PassHiZ.WriteStorageTexture(FRGHiZMip0, rsUnorderedAccess);
  PassHiZ.OnExecute := {$ifdef FPC}@{$endif}HandleNextGenHiZPass;

  { 3. GTAO Horizon Integral Compute Pass }
  PassGTAOHorizon := AGraph.AddPass('GTAOHorizonComputePass', rgptCompute);
  PassGTAOHorizon.ReadTexture(FRGSceneDepth, rsShaderRead);
  PassGTAOHorizon.WriteStorageTexture(FRGGTAORaw, rsUnorderedAccess);
  PassGTAOHorizon.OnExecute := {$ifdef FPC}@{$endif}HandleNextGenGTAOHorizonPass;

  { 4. GTAO Cross-Bilateral Spatial Denoiser Pass (ends lifetime of FRGGTAORaw & FRGSceneDepth!) }
  PassGTAODenoise := AGraph.AddPass('GTAODenoiseComputePass', rgptCompute);
  PassGTAODenoise.ReadTexture(FRGSceneDepth, rsShaderRead);
  PassGTAODenoise.ReadTexture(FRGGTAORaw, rsShaderRead);
  PassGTAODenoise.WriteStorageTexture(FRGGTAODenoised, rsUnorderedAccess);
  PassGTAODenoise.OnExecute := {$ifdef FPC}@{$endif}HandleNextGenGTAODenoisePass;

  { 5. Hi-Z Screen-Space Reflections Compute Pass (starts AFTER FRGGTAORaw dies -> aliases VkDeviceMemory!) }
  PassSSR := AGraph.AddPass('HiZSSRComputePass', rgptCompute);
  PassSSR.ReadTexture(FRGSceneHDRRaw, rsShaderRead);
  PassSSR.ReadTexture(FRGHiZMip0, rsShaderRead);
  PassSSR.WriteStorageTexture(FRGSSRReflection, rsUnorderedAccess);
  PassSSR.OnExecute := {$ifdef FPC}@{$endif}HandleNextGenSSRPass;

  { 6. Post-Process HDR Lighting Modulation Pass (ends lifetime of FRGSceneHDRRaw, FRGGTAODenoised, FRGSSRReflection!) }
  PassModulate := AGraph.AddPass('PostProcessModulateComputePass', rgptCompute);
  PassModulate.ReadTexture(FRGSceneHDRRaw, rsShaderRead);
  PassModulate.ReadTexture(FRGGTAODenoised, rsShaderRead);
  PassModulate.ReadTexture(FRGSSRReflection, rsShaderRead);
  PassModulate.WriteStorageTexture(FRGSceneHDRLit, rsUnorderedAccess);
  PassModulate.OnExecute := {$ifdef FPC}@{$endif}HandleNextGenModulatePass;

  { 7. Jiménez 13-Tap Karis Downsample + 9-Tap Tent Upsample Bloom Pyramid Pass (aliases dead HDR/GTAO/SSR VRAM!) }
  PassBloom := AGraph.AddPass('BloomPyramidComputePass', rgptCompute);
  PassBloom.ReadTexture(FRGSceneHDRLit, rsShaderRead);
  PassBloom.WriteStorageTexture(FRGBloomMip0, rsUnorderedAccess);
  PassBloom.OnExecute := {$ifdef FPC}@{$endif}HandleNextGenBloomPass;

  { 8. 256-Bin Atomic Luminance Histogram Compute Pass }
  PassHistogram := AGraph.AddPass('LuminanceHistogramComputePass', rgptCompute);
  PassHistogram.ReadTexture(FRGSceneHDRLit, rsShaderRead);
  PassHistogram.WriteBuffer(HExposureBuf);
  PassHistogram.OnExecute := {$ifdef FPC}@{$endif}HandleNextGenHistogramPass;

  { 9. ACES Filmic / AgX Tonemapping + Bloom + Color Grading + sRGB Fullscreen Composite Pass }
  PassComposite := AGraph.AddPass('TonemapCompositePass', rgptGraphics);
  PassComposite.ReadTexture(FRGSceneHDRLit, rsShaderRead);
  PassComposite.ReadTexture(FRGBloomMip0, rsShaderRead);
  PassComposite.ReadBuffer(HExposureBuf);
  PassComposite.WriteColorAttachment(FRGFinalLDR, loClear, Vector4(0.0, 0.0, 0.0, 1.0), soStore);
  PassComposite.OnExecute := {$ifdef FPC}@{$endif}HandleNextGenCompositePass;

  if AIncludeDeadDebugPass then
  begin
    DeadDesc := TRHITextureDesc.Create2D(256, 256, pfRGBA16_Float,
      [tuColorAttachment, tuSampled], 1, 1);
    HDeadScratch := AGraph.DeclareTransientTexture('RG_UnusedDebugScratch', DeadDesc);
    PassDead := AGraph.AddPass('UnusedDebugInspectionPass', rgptGraphics);
    PassDead.WriteColorAttachment(HDeadScratch, loClear, Vector4(1.0, 0.0, 1.0, 1.0), soStore);
  end;
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

{$endif read_implementation}
