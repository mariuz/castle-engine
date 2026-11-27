{%MainUnit castleinternalrhi.pas}
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
{ TRHIRenderGraphPass                                                          }
{ ---------------------------------------------------------------------------- }

constructor TRHIRenderGraphPass.Create(const AName: String;
  const APassIndex: Integer; const APassType: TRHIRenderGraphPassType;
  const AHasSideEffects: Boolean);
begin
  inherited Create;
  FName := AName;
  FPassIndex := APassIndex;
  FPassType := APassType;
  FHasSideEffects := AHasSideEffects;
  FIsCulled := False;
  FExecutionOrder := -1;
end;

procedure TRHIRenderGraphPass.ReadTexture(
  const AHandle: TRHIRenderGraphResourceHandle;
  const AReadState: TRHIResourceState);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FTextureReads);
  SetLength(FTextureReads, Idx + 1);
  FillChar(FTextureReads[Idx], SizeOf(TRHIRenderGraphTextureAccess), 0);
  FTextureReads[Idx].Handle := AHandle;
  FTextureReads[Idx].State := AReadState;
end;

procedure TRHIRenderGraphPass.WriteColorAttachment(
  const AHandle: TRHIRenderGraphResourceHandle;
  const ALoadOp: TRHIAttachmentLoadOp;
  const AStoreOp: TRHIAttachmentStoreOp);
begin
  WriteColorAttachment(AHandle, ALoadOp, Vector4(0.0, 0.0, 0.0, 1.0), AStoreOp);
end;

procedure TRHIRenderGraphPass.WriteColorAttachment(
  const AHandle: TRHIRenderGraphResourceHandle;
  const ALoadOp: TRHIAttachmentLoadOp;
  const AClearColor: TCastleColor;
  const AStoreOp: TRHIAttachmentStoreOp);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FTextureWrites);
  SetLength(FTextureWrites, Idx + 1);
  FillChar(FTextureWrites[Idx], SizeOf(TRHIRenderGraphTextureAccess), 0);
  FTextureWrites[Idx].Handle := AHandle;
  FTextureWrites[Idx].State := rsColorAttachment;
  FTextureWrites[Idx].LoadOp := ALoadOp;
  FTextureWrites[Idx].StoreOp := AStoreOp;
  FTextureWrites[Idx].ClearColor := AClearColor;
  FTextureWrites[Idx].IsColorAttachment := True;
end;

procedure TRHIRenderGraphPass.WriteDepthAttachment(
  const AHandle: TRHIRenderGraphResourceHandle;
  const ALoadOp: TRHIAttachmentLoadOp;
  const AClearDepth: Single;
  const AStoreOp: TRHIAttachmentStoreOp);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FTextureWrites);
  SetLength(FTextureWrites, Idx + 1);
  FillChar(FTextureWrites[Idx], SizeOf(TRHIRenderGraphTextureAccess), 0);
  FTextureWrites[Idx].Handle := AHandle;
  FTextureWrites[Idx].State := rsDepthStencilWrite;
  FTextureWrites[Idx].LoadOp := ALoadOp;
  FTextureWrites[Idx].StoreOp := AStoreOp;
  FTextureWrites[Idx].ClearDepth := AClearDepth;
  FTextureWrites[Idx].IsDepthAttachment := True;
end;

procedure TRHIRenderGraphPass.WriteStorageTexture(
  const AHandle: TRHIRenderGraphResourceHandle;
  const AWriteState: TRHIResourceState);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FTextureWrites);
  SetLength(FTextureWrites, Idx + 1);
  FillChar(FTextureWrites[Idx], SizeOf(TRHIRenderGraphTextureAccess), 0);
  FTextureWrites[Idx].Handle := AHandle;
  FTextureWrites[Idx].State := AWriteState;
  FTextureWrites[Idx].StoreOp := soStore;
end;

procedure TRHIRenderGraphPass.ReadBuffer(
  const AHandle: TRHIRenderGraphResourceHandle);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FBufferReads);
  SetLength(FBufferReads, Idx + 1);
  FBufferReads[Idx] := AHandle;
end;

procedure TRHIRenderGraphPass.WriteBuffer(
  const AHandle: TRHIRenderGraphResourceHandle);
var
  Idx: Integer;
begin
  if AHandle < 0 then Exit;
  Idx := Length(FBufferWrites);
  SetLength(FBufferWrites, Idx + 1);
  FBufferWrites[Idx] := AHandle;
end;

function TRHIRenderGraphPass.PrePassBarriersCount: Integer;
begin
  Result := Length(FPrePassBarriers);
end;

function TRHIRenderGraphPass.GetPrePassBarrier(
  const AIndex: Integer): TRHIRenderGraphTextureBarrier;
begin
  if (AIndex >= 0) and (AIndex < Length(FPrePassBarriers)) then
    Result := FPrePassBarriers[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

{ ---------------------------------------------------------------------------- }
{ TRHIRenderGraph                                                              }
{ ---------------------------------------------------------------------------- }

constructor TRHIRenderGraph.Create(const ADevice: TRHIDevice);
begin
  inherited Create;
  FDevice := ADevice;
  FPasses := TRHIRenderGraphPassList.Create(True);
  Reset;
end;

destructor TRHIRenderGraph.Destroy;
begin
  ReleaseTransientPool;
  FreeAndNil(FPasses);
  inherited;
end;

procedure TRHIRenderGraph.Reset;
begin
  FPasses.Clear;
  SetLength(FCompiledPasses, 0);
  SetLength(FVirtualTextures, 0);
  SetLength(FVirtualBuffers, 0);
  SetLength(FFinalExportBarriers, 0);
  FIsCompiled := False;
  FCulledPassCount := 0;
  FEmittedBarrierCount := 0;
  FAliasingBarrierCount := 0;
  FTransientTextureCount := 0;
  FAliasedTextureSavingsCount := 0;
  FMemoryAliasedTextureCount := 0;
  FAliasedMemorySavedBytes := 0;
  FDebugScopesEmittedCount := 0;
end;

procedure TRHIRenderGraph.ReleaseTransientPool;
var
  I, J: Integer;
begin
  for I := 0 to Length(FTransientPool) - 1 do
  begin
    { Destroy aliased VkImage wrappers before freeing the carrier allocation }
    for J := 0 to Length(FTransientPool[I].AliasedVariants) - 1 do
      FreeAndNil(FTransientPool[I].AliasedVariants[J].Texture);
    SetLength(FTransientPool[I].AliasedVariants, 0);
    FreeAndNil(FTransientPool[I].Texture);
    FTransientPool[I].LastActiveTexture := nil;
  end;
  SetLength(FTransientPool, 0);
end;

class function TRHIRenderGraph.AreTextureDescsCompatibleForAliasing(
  const A, B: TRHITextureDesc): Boolean;
begin
  Result :=
    (A.Dimension = B.Dimension) and
    (A.Width = B.Width) and
    (A.Height = B.Height) and
    (A.DepthOrArrayLayers = B.DepthOrArrayLayers) and
    (A.MipLevels = B.MipLevels) and
    (A.SampleCount = B.SampleCount) and
    (A.Format = B.Format) and
    (A.Usage = B.Usage);
end;

function TRHIRenderGraph.GetPassCount: Integer;
begin
  Result := FPasses.Count;
end;

function TRHIRenderGraph.GetCompiledPassCount: Integer;
begin
  Result := Length(FCompiledPasses);
end;

function TRHIRenderGraph.GetPhysicalTransientTextureCount: Integer;
begin
  Result := Length(FTransientPool);
end;

function TRHIRenderGraph.DeclareTransientTexture(const AName: String;
  const ADesc: TRHITextureDesc): TRHIRenderGraphResourceHandle;
var
  Idx: Integer;
begin
  FIsCompiled := False;
  Idx := Length(FVirtualTextures);
  SetLength(FVirtualTextures, Idx + 1);
  FVirtualTextures[Idx] := Default(TVirtualTextureEntry);
  FVirtualTextures[Idx].Name := AName;
  FVirtualTextures[Idx].Desc := ADesc;
  FVirtualTextures[Idx].Desc.DebugName := AName;
  FVirtualTextures[Idx].IsImported := False;
  FVirtualTextures[Idx].InitialState := rsUndefined;
  FVirtualTextures[Idx].FinalState := rsUndefined;
  FVirtualTextures[Idx].PhysicalTexture := nil;
  FVirtualTextures[Idx].PoolSlotIndex := -1;
  FVirtualTextures[Idx].FirstUseOrder := High(Integer);
  FVirtualTextures[Idx].LastUseOrder := -1;
  FVirtualTextures[Idx].LastProducerPass := -1;
  Inc(FTransientTextureCount);
  Result := Idx;
end;

function TRHIRenderGraph.ImportExternalTexture(const AName: String;
  const ATexture: TRHITexture;
  const AInitialState, AFinalState: TRHIResourceState): TRHIRenderGraphResourceHandle;
var
  Idx: Integer;
begin
  FIsCompiled := False;
  Idx := Length(FVirtualTextures);
  SetLength(FVirtualTextures, Idx + 1);
  FVirtualTextures[Idx] := Default(TVirtualTextureEntry);
  FVirtualTextures[Idx].Name := AName;
  if ATexture <> nil then
    FVirtualTextures[Idx].Desc := ATexture.Desc;
  FVirtualTextures[Idx].IsImported := True;
  if (AInitialState = rsUndefined) and (ATexture <> nil) then
    FVirtualTextures[Idx].InitialState := ATexture.CurrentState
  else
    FVirtualTextures[Idx].InitialState := AInitialState;
  FVirtualTextures[Idx].FinalState := AFinalState;
  FVirtualTextures[Idx].PhysicalTexture := ATexture;
  FVirtualTextures[Idx].PoolSlotIndex := -1;
  FVirtualTextures[Idx].FirstUseOrder := High(Integer);
  FVirtualTextures[Idx].LastUseOrder := -1;
  FVirtualTextures[Idx].LastProducerPass := -1;
  Result := Idx;
end;

function TRHIRenderGraph.ImportExternalBuffer(const AName: String;
  const ABuffer: TRHIBuffer): TRHIRenderGraphResourceHandle;
var
  Idx: Integer;
begin
  FIsCompiled := False;
  Idx := Length(FVirtualBuffers);
  SetLength(FVirtualBuffers, Idx + 1);
  FVirtualBuffers[Idx].Name := AName;
  FVirtualBuffers[Idx].PhysicalBuffer := ABuffer;
  FVirtualBuffers[Idx].LastProducerPass := -1;
  Result := Idx;
end;

function TRHIRenderGraph.AddPass(const AName: String;
  const APassType: TRHIRenderGraphPassType;
  const AHasSideEffects: Boolean): TRHIRenderGraphPass;
begin
  FIsCompiled := False;
  Result := TRHIRenderGraphPass.Create(AName, FPasses.Count, APassType, AHasSideEffects);
  FPasses.Add(Result);
end;

procedure TRHIRenderGraph.Compile;
var
  NPasses, P, Q, I, J, H, H2, V, OrderIdx, NextOrd, SlotIdx, ChosenSlot, BarrierIdx: Integer;
  Edges: array of array of Boolean;
  InDegree: array of Integer;
  IsLive: array of Boolean;
  Queue: array of Integer;
  QueueHead, QueueTail: Integer;
  Pass, OtherPass: TRHIRenderGraphPass;
  LastTexWriter: array of Integer;
  LastBufWriter: array of Integer;
  TrackedTexState: array of TRHIResourceState;
  PoolTexState: array of TRHIResourceState;
  SlotActiveTex: array of TRHITexture;
  AssignedTex, AliasTex, PrevActiveTex: TRHITexture;
  ChainEnd: Integer;
  CarrierBytes, CandBytes: UInt64;
  IsDepthDesc, SlotIsDepth, DidAliasSwitch: Boolean;
  CurState, NeededState: TRHIResourceState;
  AlreadyHasBarrier: Boolean;
begin
  NPasses := FPasses.Count;
  SetLength(FCompiledPasses, 0);
  SetLength(FFinalExportBarriers, 0);
  FCulledPassCount := 0;
  FEmittedBarrierCount := 0;
  FAliasingBarrierCount := 0;
  FAliasedTextureSavingsCount := 0;
  FMemoryAliasedTextureCount := 0;
  FAliasedMemorySavedBytes := 0;

  if NPasses = 0 then
  begin
    FIsCompiled := True;
    Exit;
  end;

  { 1. Build DAG dependency edges between passes (Edges[Producer, Consumer] = True) }
  SetLength(Edges, NPasses, NPasses);
  for P := 0 to NPasses - 1 do
    for Q := 0 to NPasses - 1 do
      Edges[P][Q] := False;

  SetLength(LastTexWriter, Length(FVirtualTextures));
  for I := 0 to Length(LastTexWriter) - 1 do
    LastTexWriter[I] := -1;

  SetLength(LastBufWriter, Length(FVirtualBuffers));
  for I := 0 to Length(LastBufWriter) - 1 do
    LastBufWriter[I] := -1;

  { First pass: resolve producer -> consumer edges regardless of declaration order
    by matching any pass Q that reads resource R to any pass P that writes resource R }
  for P := 0 to NPasses - 1 do
  begin
    Pass := FPasses[P];
    for I := 0 to Length(Pass.FTextureWrites) - 1 do
    begin
      H := Pass.FTextureWrites[I].Handle;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        { Any earlier writer of the same texture must precede this writer (WAW) }
        if (LastTexWriter[H] >= 0) and (LastTexWriter[H] <> P) then
          Edges[LastTexWriter[H]][P] := True;
        LastTexWriter[H] := P;

        { Any pass Q that reads H depends on writer P (unless Q also writes H before P) }
        for Q := 0 to NPasses - 1 do
          if Q <> P then
          begin
            OtherPass := FPasses[Q];
            for J := 0 to Length(OtherPass.FTextureReads) - 1 do
              if OtherPass.FTextureReads[J].Handle = H then
              begin
                { Avoid creating a 2-cycle if Q already precedes P }
                if not Edges[Q][P] then
                  Edges[P][Q] := True;
              end;
          end;
      end;
    end;

    for I := 0 to Length(Pass.FBufferWrites) - 1 do
    begin
      H := Pass.FBufferWrites[I];
      if (H >= 0) and (H < Length(FVirtualBuffers)) then
      begin
        if (LastBufWriter[H] >= 0) and (LastBufWriter[H] <> P) then
          Edges[LastBufWriter[H]][P] := True;
        LastBufWriter[H] := P;

        for Q := 0 to NPasses - 1 do
          if Q <> P then
          begin
            OtherPass := FPasses[Q];
            for J := 0 to Length(OtherPass.FBufferReads) - 1 do
              if OtherPass.FBufferReads[J] = H then
                if not Edges[Q][P] then
                  Edges[P][Q] := True;
          end;
      end;
    end;
  end;

  { 2. Backward Liveness Analysis (Dead-Pass Culling) }
  SetLength(IsLive, NPasses);
  SetLength(Queue, NPasses);
  QueueHead := 0;
  QueueTail := 0;

  for P := 0 to NPasses - 1 do
  begin
    Pass := FPasses[P];
    IsLive[P] := Pass.FHasSideEffects;

    if not IsLive[P] then
    begin
      for I := 0 to Length(Pass.FTextureWrites) - 1 do
      begin
        H := Pass.FTextureWrites[I].Handle;
        if (H >= 0) and (H < Length(FVirtualTextures)) and FVirtualTextures[H].IsImported then
        begin
          IsLive[P] := True;
          Break;
        end;
      end;
    end;

    if not IsLive[P] then
    begin
      for I := 0 to Length(Pass.FBufferWrites) - 1 do
      begin
        H := Pass.FBufferWrites[I];
        if (H >= 0) and (H < Length(FVirtualBuffers)) then
        begin
          IsLive[P] := True;
          Break;
        end;
      end;
    end;

    if IsLive[P] then
    begin
      Queue[QueueTail] := P;
      Inc(QueueTail);
    end;
  end;

  while QueueHead < QueueTail do
  begin
    Q := Queue[QueueHead];
    Inc(QueueHead);
    for P := 0 to NPasses - 1 do
      if Edges[P][Q] and (not IsLive[P]) then
      begin
        IsLive[P] := True;
        Queue[QueueTail] := P;
        Inc(QueueTail);
      end;
  end;

  for P := 0 to NPasses - 1 do
  begin
    FPasses[P].FIsCulled := not IsLive[P];
    FPasses[P].FExecutionOrder := -1;
    SetLength(FPasses[P].FPrePassBarriers, 0);
    if not IsLive[P] then
      Inc(FCulledPassCount);
  end;

  { 3. Topological Sort (Kahn's Algorithm) over live passes }
  SetLength(InDegree, NPasses);
  for P := 0 to NPasses - 1 do
  begin
    InDegree[P] := 0;
    if IsLive[P] then
      for Q := 0 to NPasses - 1 do
        if IsLive[Q] and Edges[Q][P] then
          Inc(InDegree[P]);
  end;

  QueueHead := 0;
  QueueTail := 0;
  for P := 0 to NPasses - 1 do
    if IsLive[P] and (InDegree[P] = 0) then
    begin
      Queue[QueueTail] := P;
      Inc(QueueTail);
    end;

  OrderIdx := 0;
  SetLength(FCompiledPasses, NPasses - FCulledPassCount);
  while QueueHead < QueueTail do
  begin
    P := Queue[QueueHead];
    Inc(QueueHead);
    FPasses[P].FExecutionOrder := OrderIdx;
    FCompiledPasses[OrderIdx] := FPasses[P];
    Inc(OrderIdx);

    for Q := 0 to NPasses - 1 do
      if IsLive[Q] and Edges[P][Q] then
      begin
        Dec(InDegree[Q]);
        if InDegree[Q] = 0 then
        begin
          Queue[QueueTail] := Q;
          Inc(QueueTail);
        end;
      end;
  end;

  if OrderIdx <> (NPasses - FCulledPassCount) then
    raise ERHIError.Create('TRHIRenderGraph.Compile: Dependency cycle detected in render graph passes.');

  { 4. Compute Transient Texture Lifetimes & Perform Physical Texture Aliasing }
  for H := 0 to Length(FVirtualTextures) - 1 do
  begin
    FVirtualTextures[H].FirstUseOrder := High(Integer);
    FVirtualTextures[H].LastUseOrder := -1;
    FVirtualTextures[H].PoolSlotIndex := -1;
    if not FVirtualTextures[H].IsImported then
      FVirtualTextures[H].PhysicalTexture := nil;
  end;

  for OrderIdx := 0 to Length(FCompiledPasses) - 1 do
  begin
    Pass := FCompiledPasses[OrderIdx];
    for I := 0 to Length(Pass.FTextureReads) - 1 do
    begin
      H := Pass.FTextureReads[I].Handle;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        if OrderIdx < FVirtualTextures[H].FirstUseOrder then
          FVirtualTextures[H].FirstUseOrder := OrderIdx;
        if OrderIdx > FVirtualTextures[H].LastUseOrder then
          FVirtualTextures[H].LastUseOrder := OrderIdx;
      end;
    end;
    for I := 0 to Length(Pass.FTextureWrites) - 1 do
    begin
      H := Pass.FTextureWrites[I].Handle;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        if OrderIdx < FVirtualTextures[H].FirstUseOrder then
          FVirtualTextures[H].FirstUseOrder := OrderIdx;
        if OrderIdx > FVirtualTextures[H].LastUseOrder then
          FVirtualTextures[H].LastUseOrder := OrderIdx;
      end;
    end;
  end;

  { Reset pool slot usage for this compilation }
  for SlotIdx := 0 to Length(FTransientPool) - 1 do
    FTransientPool[SlotIdx].LastAssignedOrder := -1;

  { Assign physical textures in increasing FirstUseOrder:
    1st pass per texture: exact descriptor reuse (zero new VkImage).
    2nd pass per texture: cross-format / cross-resolution / cross-usage physical
      VkDeviceMemory aliasing via TryCreateAliasedTexture (VK_IMAGE_CREATE_ALIAS_BIT).
    3rd fallback: allocate a new carrier slot sized to the max byte footprint of
      its greedy non-overlapping interval chain so downstream transients can alias it! }
  for OrderIdx := 0 to Length(FCompiledPasses) - 1 do
    for H := 0 to Length(FVirtualTextures) - 1 do
      if (not FVirtualTextures[H].IsImported) and
         (FVirtualTextures[H].FirstUseOrder = OrderIdx) and
         (FVirtualTextures[H].LastUseOrder >= OrderIdx) and
         (FVirtualTextures[H].PhysicalTexture = nil) then
      begin
        ChosenSlot := -1;
        AssignedTex := nil;

        { 4a. Prefer exact descriptor match (either carrier texture or cached aliased variant) }
        for SlotIdx := 0 to Length(FTransientPool) - 1 do
          if FTransientPool[SlotIdx].LastAssignedOrder < FVirtualTextures[H].FirstUseOrder then
          begin
            if AreTextureDescsCompatibleForAliasing(FTransientPool[SlotIdx].Desc, FVirtualTextures[H].Desc) then
            begin
              ChosenSlot := SlotIdx;
              AssignedTex := FTransientPool[SlotIdx].Texture;
              if FTransientPool[SlotIdx].LastAssignedOrder >= 0 then
              begin
                Inc(FAliasedTextureSavingsCount);
                Inc(FAliasedMemorySavedBytes, TRHITexture.EstimateDescriptorByteSize(FVirtualTextures[H].Desc));
              end;
              Break;
            end;
            for V := 0 to Length(FTransientPool[SlotIdx].AliasedVariants) - 1 do
              if AreTextureDescsCompatibleForAliasing(
                   FTransientPool[SlotIdx].AliasedVariants[V].Desc, FVirtualTextures[H].Desc) then
              begin
                ChosenSlot := SlotIdx;
                AssignedTex := FTransientPool[SlotIdx].AliasedVariants[V].Texture;
                if FTransientPool[SlotIdx].LastAssignedOrder >= 0 then
                begin
                  Inc(FAliasedTextureSavingsCount);
                  Inc(FMemoryAliasedTextureCount);
                  Inc(FAliasedMemorySavedBytes, TRHITexture.EstimateDescriptorByteSize(FVirtualTextures[H].Desc));
                end;
                Break;
              end;
            if ChosenSlot >= 0 then
              Break;
          end;

        { 4b. Cross-format / cross-resolution / cross-usage physical GPU memory aliasing }
        if (ChosenSlot < 0) and (FDevice <> nil) then
        begin
          for SlotIdx := 0 to Length(FTransientPool) - 1 do
            if (FTransientPool[SlotIdx].LastAssignedOrder < FVirtualTextures[H].FirstUseOrder) and
               (FTransientPool[SlotIdx].Texture <> nil) then
            begin
              AliasTex := FDevice.TryCreateAliasedTexture(
                FVirtualTextures[H].Desc, FTransientPool[SlotIdx].Texture);
              if AliasTex <> nil then
              begin
                V := Length(FTransientPool[SlotIdx].AliasedVariants);
                SetLength(FTransientPool[SlotIdx].AliasedVariants, V + 1);
                FTransientPool[SlotIdx].AliasedVariants[V].Desc := FVirtualTextures[H].Desc;
                FTransientPool[SlotIdx].AliasedVariants[V].Texture := AliasTex;
                ChosenSlot := SlotIdx;
                AssignedTex := AliasTex;
                if FTransientPool[SlotIdx].LastAssignedOrder >= 0 then
                begin
                  Inc(FAliasedTextureSavingsCount);
                  Inc(FMemoryAliasedTextureCount);
                  Inc(FAliasedMemorySavedBytes, TRHITexture.EstimateDescriptorByteSize(FVirtualTextures[H].Desc));
                end;
                Break;
              end;
            end;
        end;

        { 4c. Allocate a new carrier slot sized to cover its greedy future non-overlapping chain }
        if ChosenSlot < 0 then
        begin
          CarrierBytes := TRHITexture.EstimateDescriptorByteSize(FVirtualTextures[H].Desc) + 65536;
          IsDepthDesc := tuDepthStencil in FVirtualTextures[H].Desc.Usage;
          ChainEnd := FVirtualTextures[H].LastUseOrder;
          for NextOrd := ChainEnd + 1 to Length(FCompiledPasses) - 1 do
            for H2 := 0 to Length(FVirtualTextures) - 1 do
              if (not FVirtualTextures[H2].IsImported) and
                 (FVirtualTextures[H2].PhysicalTexture = nil) and
                 (FVirtualTextures[H2].FirstUseOrder = NextOrd) and
                 (FVirtualTextures[H2].FirstUseOrder > ChainEnd) and
                 (FVirtualTextures[H2].LastUseOrder >= NextOrd) then
              begin
                SlotIsDepth := tuDepthStencil in FVirtualTextures[H2].Desc.Usage;
                if SlotIsDepth = IsDepthDesc then
                begin
                  CandBytes := TRHITexture.EstimateDescriptorByteSize(FVirtualTextures[H2].Desc) + 65536;
                  if CandBytes > CarrierBytes then
                    CarrierBytes := CandBytes;
                  ChainEnd := FVirtualTextures[H2].LastUseOrder;
                  Break;
                end;
              end;

          ChosenSlot := Length(FTransientPool);
          SetLength(FTransientPool, ChosenSlot + 1);
          FTransientPool[ChosenSlot] := Default(TTransientPoolSlot);
          FTransientPool[ChosenSlot].Desc := FVirtualTextures[H].Desc;
          FTransientPool[ChosenSlot].CarrierCapacityBytes := CarrierBytes;
          if FDevice <> nil then
            FTransientPool[ChosenSlot].Texture := FDevice.CreateTransientCarrierTexture(
              FVirtualTextures[H].Desc, CarrierBytes)
          else
            FTransientPool[ChosenSlot].Texture := nil;
          AssignedTex := FTransientPool[ChosenSlot].Texture;
        end;

        FTransientPool[ChosenSlot].LastAssignedOrder := FVirtualTextures[H].LastUseOrder;
        FVirtualTextures[H].PoolSlotIndex := ChosenSlot;
        FVirtualTextures[H].PhysicalTexture := AssignedTex;
      end;

  { 5. Hoist Pre-Pass Resource State Transitions & Physical Memory Aliasing Barriers }
  SetLength(TrackedTexState, Length(FVirtualTextures));
  for H := 0 to Length(FVirtualTextures) - 1 do
    TrackedTexState[H] := FVirtualTextures[H].InitialState;

  SetLength(PoolTexState, Length(FTransientPool));
  SetLength(SlotActiveTex, Length(FTransientPool));
  for SlotIdx := 0 to Length(FTransientPool) - 1 do
  begin
    SlotActiveTex[SlotIdx] := FTransientPool[SlotIdx].LastActiveTexture;
    if SlotActiveTex[SlotIdx] <> nil then
      PoolTexState[SlotIdx] := SlotActiveTex[SlotIdx].CurrentState
    else if FTransientPool[SlotIdx].Texture <> nil then
      PoolTexState[SlotIdx] := FTransientPool[SlotIdx].Texture.CurrentState
    else
      PoolTexState[SlotIdx] := rsUndefined;
  end;

  for OrderIdx := 0 to Length(FCompiledPasses) - 1 do
  begin
    Pass := FCompiledPasses[OrderIdx];
    SetLength(Pass.FPrePassBarriers, 0);

    { Check texture reads }
    for I := 0 to Length(Pass.FTextureReads) - 1 do
    begin
      H := Pass.FTextureReads[I].Handle;
      NeededState := Pass.FTextureReads[I].State;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        SlotIdx := FVirtualTextures[H].PoolSlotIndex;
        DidAliasSwitch := False;
        PrevActiveTex := nil;
        if (not FVirtualTextures[H].IsImported) and (SlotIdx >= 0) then
        begin
          AssignedTex := FVirtualTextures[H].PhysicalTexture;
          if (SlotActiveTex[SlotIdx] <> nil) and (SlotActiveTex[SlotIdx] <> AssignedTex) then
          begin
            DidAliasSwitch := True;
            PrevActiveTex := SlotActiveTex[SlotIdx];
            CurState := rsUndefined;
          end else
            CurState := PoolTexState[SlotIdx];
          SlotActiveTex[SlotIdx] := AssignedTex;
        end else
          CurState := TrackedTexState[H];

        if DidAliasSwitch or (CurState <> NeededState) then
        begin
          AlreadyHasBarrier := False;
          for J := 0 to Length(Pass.FPrePassBarriers) - 1 do
            if Pass.FPrePassBarriers[J].TextureHandle = H then
            begin
              AlreadyHasBarrier := True;
              Break;
            end;
          if not AlreadyHasBarrier then
          begin
            BarrierIdx := Length(Pass.FPrePassBarriers);
            SetLength(Pass.FPrePassBarriers, BarrierIdx + 1);
            FillChar(Pass.FPrePassBarriers[BarrierIdx], SizeOf(TRHIRenderGraphTextureBarrier), 0);
            Pass.FPrePassBarriers[BarrierIdx].TextureHandle := H;
            Pass.FPrePassBarriers[BarrierIdx].PreviousAliasedTexture := PrevActiveTex;
            Pass.FPrePassBarriers[BarrierIdx].IsAliasingHandoff := DidAliasSwitch;
            Pass.FPrePassBarriers[BarrierIdx].BeforeState := CurState;
            Pass.FPrePassBarriers[BarrierIdx].AfterState := NeededState;
            Inc(FEmittedBarrierCount);
            if DidAliasSwitch then
              Inc(FAliasingBarrierCount);
          end;
          TrackedTexState[H] := NeededState;
          if (not FVirtualTextures[H].IsImported) and (SlotIdx >= 0) then
            PoolTexState[SlotIdx] := NeededState;
        end;
      end;
    end;

    { Check texture writes }
    for I := 0 to Length(Pass.FTextureWrites) - 1 do
    begin
      H := Pass.FTextureWrites[I].Handle;
      NeededState := Pass.FTextureWrites[I].State;
      if (H >= 0) and (H < Length(FVirtualTextures)) then
      begin
        SlotIdx := FVirtualTextures[H].PoolSlotIndex;
        DidAliasSwitch := False;
        PrevActiveTex := nil;
        if (not FVirtualTextures[H].IsImported) and (SlotIdx >= 0) then
        begin
          AssignedTex := FVirtualTextures[H].PhysicalTexture;
          if (SlotActiveTex[SlotIdx] <> nil) and (SlotActiveTex[SlotIdx] <> AssignedTex) then
          begin
            DidAliasSwitch := True;
            PrevActiveTex := SlotActiveTex[SlotIdx];
            CurState := rsUndefined;
          end else
            CurState := PoolTexState[SlotIdx];
          SlotActiveTex[SlotIdx] := AssignedTex;
        end else
          CurState := TrackedTexState[H];

        if DidAliasSwitch or (CurState <> NeededState) then
        begin
          AlreadyHasBarrier := False;
          for J := 0 to Length(Pass.FPrePassBarriers) - 1 do
            if Pass.FPrePassBarriers[J].TextureHandle = H then
            begin
              Pass.FPrePassBarriers[J].AfterState := NeededState;
              if DidAliasSwitch then
              begin
                Pass.FPrePassBarriers[J].IsAliasingHandoff := True;
                Pass.FPrePassBarriers[J].PreviousAliasedTexture := PrevActiveTex;
                Pass.FPrePassBarriers[J].BeforeState := rsUndefined;
                Inc(FAliasingBarrierCount);
              end;
              AlreadyHasBarrier := True;
              Break;
            end;
          if not AlreadyHasBarrier then
          begin
            BarrierIdx := Length(Pass.FPrePassBarriers);
            SetLength(Pass.FPrePassBarriers, BarrierIdx + 1);
            FillChar(Pass.FPrePassBarriers[BarrierIdx], SizeOf(TRHIRenderGraphTextureBarrier), 0);
            Pass.FPrePassBarriers[BarrierIdx].TextureHandle := H;
            Pass.FPrePassBarriers[BarrierIdx].PreviousAliasedTexture := PrevActiveTex;
            Pass.FPrePassBarriers[BarrierIdx].IsAliasingHandoff := DidAliasSwitch;
            Pass.FPrePassBarriers[BarrierIdx].BeforeState := CurState;
            Pass.FPrePassBarriers[BarrierIdx].AfterState := NeededState;
            Inc(FEmittedBarrierCount);
            if DidAliasSwitch then
              Inc(FAliasingBarrierCount);
          end;
          TrackedTexState[H] := NeededState;
          if (not FVirtualTextures[H].IsImported) and (SlotIdx >= 0) then
            PoolTexState[SlotIdx] := NeededState;
        end;
      end;
    end;
  end;

  for SlotIdx := 0 to Length(FTransientPool) - 1 do
    FTransientPool[SlotIdx].LastActiveTexture := SlotActiveTex[SlotIdx];

  { Check FinalState transitions for imported textures }
  for H := 0 to Length(FVirtualTextures) - 1 do
    if FVirtualTextures[H].IsImported and
       (FVirtualTextures[H].FinalState <> rsUndefined) and
       (TrackedTexState[H] <> FVirtualTextures[H].FinalState) then
    begin
      BarrierIdx := Length(FFinalExportBarriers);
      SetLength(FFinalExportBarriers, BarrierIdx + 1);
      FFinalExportBarriers[BarrierIdx].TextureHandle := H;
      FFinalExportBarriers[BarrierIdx].BeforeState := TrackedTexState[H];
      FFinalExportBarriers[BarrierIdx].AfterState := FVirtualTextures[H].FinalState;
      Inc(FEmittedBarrierCount);
    end;

  FIsCompiled := True;
end;

procedure TRHIRenderGraph.Execute(const ACmd: TRHICommandList);
var
  OrderIdx, I, ColorCount: Integer;
  Pass: TRHIRenderGraphPass;
  PhysTex: TRHITexture;
  RenderInfo: TRHIRenderingInfo;
  TargetW, TargetH: Cardinal;
  HasAttachments: Boolean;
  ScopeColor: TCastleColor;
begin
  if not FIsCompiled then
    Compile;

  for OrderIdx := 0 to Length(FCompiledPasses) - 1 do
  begin
    Pass := FCompiledPasses[OrderIdx];

    if ACmd <> nil then
    begin
      case Pass.FPassType of
        rgptGraphics: ScopeColor := Vector4(0.22, 0.62, 0.96, 1.0);
        rgptCompute:  ScopeColor := Vector4(0.95, 0.65, 0.18, 1.0);
      else
        ScopeColor := Vector4(0.22, 0.82, 0.48, 1.0);
      end;
      ACmd.PushDebugGroup(Pass.FName, ScopeColor);
      Inc(FDebugScopesEmittedCount);
    end;
    try
      { 1. Emit hoisted pre-pass physical memory aliasing & layout transition barriers }
      if ACmd <> nil then
        for I := 0 to Length(Pass.FPrePassBarriers) - 1 do
        begin
          PhysTex := ResolvePhysicalTexture(Pass.FPrePassBarriers[I].TextureHandle);
          if PhysTex <> nil then
          begin
            if Pass.FPrePassBarriers[I].IsAliasingHandoff then
            begin
              ACmd.EmitAliasingBarrier(Pass.FPrePassBarriers[I].PreviousAliasedTexture, PhysTex);
              { Per Vulkan spec Memory Aliasing rules, activating an aliased image discards
                prior metadata and transitions from VK_IMAGE_LAYOUT_UNDEFINED }
              PhysTex.CurrentState := rsUndefined;
            end;
            ACmd.TransitionTexture(PhysTex, Pass.FPrePassBarriers[I].AfterState);
          end;
        end;

      { 2. Automatically wrap graphics passes with attachments in BeginRendering/EndRendering }
      HasAttachments := False;
      if (ACmd <> nil) and (Pass.FPassType = rgptGraphics) and (Length(Pass.FTextureWrites) > 0) then
      begin
        RenderInfo := Default(TRHIRenderingInfo);
        ColorCount := 0;
        TargetW := 0;
        TargetH := 0;

        for I := 0 to Length(Pass.FTextureWrites) - 1 do
        begin
          PhysTex := ResolvePhysicalTexture(Pass.FTextureWrites[I].Handle);
          if (PhysTex <> nil) and (TargetW = 0) then
          begin
            TargetW := PhysTex.Desc.Width;
            TargetH := PhysTex.Desc.Height;
          end;

          if Pass.FTextureWrites[I].IsColorAttachment then
          begin
            SetLength(RenderInfo.ColorAttachments, ColorCount + 1);
            FillChar(RenderInfo.ColorAttachments[ColorCount], SizeOf(TRHIRenderingAttachment), 0);
            RenderInfo.ColorAttachments[ColorCount].Texture := PhysTex;
            RenderInfo.ColorAttachments[ColorCount].LoadOp := Pass.FTextureWrites[I].LoadOp;
            RenderInfo.ColorAttachments[ColorCount].StoreOp := Pass.FTextureWrites[I].StoreOp;
            RenderInfo.ColorAttachments[ColorCount].ClearColor := Pass.FTextureWrites[I].ClearColor;
            Inc(ColorCount);
            HasAttachments := True;
          end else
          if Pass.FTextureWrites[I].IsDepthAttachment then
          begin
            RenderInfo.HasDepthAttachment := True;
            FillChar(RenderInfo.DepthAttachment, SizeOf(TRHIRenderingAttachment), 0);
            RenderInfo.DepthAttachment.Texture := PhysTex;
            RenderInfo.DepthAttachment.LoadOp := Pass.FTextureWrites[I].LoadOp;
            RenderInfo.DepthAttachment.StoreOp := Pass.FTextureWrites[I].StoreOp;
            RenderInfo.DepthAttachment.ClearDepth := Pass.FTextureWrites[I].ClearDepth;
            HasAttachments := True;
          end;
        end;

        if HasAttachments then
        begin
          if (TargetW = 0) or (TargetH = 0) then
          begin
            TargetW := 1;
            TargetH := 1;
          end;
          RenderInfo.RenderArea := Rectangle(0, 0, TargetW, TargetH);
          ACmd.BeginRendering(RenderInfo);
          ACmd.SetViewport(FloatRectangle(0, 0, TargetW, TargetH));
          ACmd.SetScissor(RenderInfo.RenderArea);
        end;
      end;

      { 3. Execute pass callback }
      if Assigned(Pass.FOnExecute) then
        Pass.FOnExecute(Self, Pass, ACmd);
      if Assigned(Pass.FOnExecuteProc) then
        Pass.FOnExecuteProc(Self, Pass, ACmd);

      if (ACmd <> nil) and HasAttachments then
        ACmd.EndRendering;
    finally
      if ACmd <> nil then
        ACmd.PopDebugGroup;
    end;
  end;

  { 4. Emit final export barriers }
  if ACmd <> nil then
    for I := 0 to Length(FFinalExportBarriers) - 1 do
    begin
      PhysTex := ResolvePhysicalTexture(FFinalExportBarriers[I].TextureHandle);
      if PhysTex <> nil then
        ACmd.TransitionTexture(PhysTex, FFinalExportBarriers[I].AfterState);
    end;

  Inc(FExecutionCount);
end;

function TRHIRenderGraph.ResolvePhysicalTexture(
  const AHandle: TRHIRenderGraphResourceHandle): TRHITexture;
begin
  if (AHandle >= 0) and (AHandle < Length(FVirtualTextures)) then
    Result := FVirtualTextures[AHandle].PhysicalTexture
  else
    Result := nil;
end;

function TRHIRenderGraph.ResolvePhysicalBuffer(
  const AHandle: TRHIRenderGraphResourceHandle): TRHIBuffer;
begin
  if (AHandle >= 0) and (AHandle < Length(FVirtualBuffers)) then
    Result := FVirtualBuffers[AHandle].PhysicalBuffer
  else
    Result := nil;
end;

function TRHIRenderGraph.GetCompiledPass(const AOrderIndex: Integer): TRHIRenderGraphPass;
begin
  if (AOrderIndex >= 0) and (AOrderIndex < Length(FCompiledPasses)) then
    Result := FCompiledPasses[AOrderIndex]
  else
    Result := nil;
end;

function EncodedImageToRHIPixelFormat(const AImage: TEncodedImage): TRHIPixelFormat;
begin
  if AImage = nil then
    Exit(pfRGBA8_UNorm);

  if (AImage is TRGBAlphaFloatImage) or
     (AImage is TRGBFloatImage) or
     (AImage is TGrayscaleFloatImage) or
     (AImage is TGrayscaleAlphaFloatImage) then
    Exit(pfRGBA32_Float);

  if AImage is TGPUCompressedImage then
  begin
    case TGPUCompressedImage(AImage).Compression of
      tcDxt1_RGB, tcDxt1_RGBA:
        Result := pfBC1_RGBA_UNorm;
      tcDxt3, tcDxt5:
        Result := pfBC3_RGBA_UNorm;
      tcETC1:
        Result := pfETC2_RGB8_UNorm;
      tcASTC_4x4_RGBA .. tcASTC_12x12_RGBA:
        Result := pfASTC_4x4_UNorm;
      tcASTC_4x4_SRGB8_ALPHA8 .. tcASTC_12x12_SRGB8_ALPHA8:
        Result := pfASTC_4x4_sRGB;
    else
      Result := pfRGBA8_UNorm;
    end;
    Exit;
  end;

  Result := pfRGBA8_UNorm;
end;

function EncodedImageToRHIGpuBytes(const AImage: TEncodedImage;
  const AFormat: TRHIPixelFormat): Int64;
var
  W, H, D: Int64;
begin
  if AImage = nil then
    Exit(0);

  if (AImage is TGPUCompressedImage) and
     (AFormat in [pfBC1_RGBA_UNorm, pfBC1_RGBA_sRGB,
                  pfBC3_RGBA_UNorm, pfBC3_RGBA_sRGB,
                  pfBC5_RG_UNorm, pfBC7_RGBA_UNorm, pfBC7_RGBA_sRGB,
                  pfASTC_4x4_UNorm, pfASTC_4x4_sRGB,
                  pfETC2_RGB8_UNorm, pfETC2_RGBA8_UNorm]) then
    Exit(Int64(TGPUCompressedImage(AImage).Size));

  W := Int64(AImage.Width);
  if W < 1 then W := 1;
  H := Int64(AImage.Height);
  if H < 1 then H := 1;
  D := Int64(AImage.Depth);
  if D < 1 then D := 1;

  case AFormat of
    pfRGBA32_Float:
      Result := W * H * D * 16;
    pfRGBA16_Float:
      Result := W * H * D * 8;
  else
    Result := W * H * D * 4;
  end;
end;

{$endif read_implementation}
