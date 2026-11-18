{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless helper for Async Asset Preloader & VRAM Residency Studio (Phase 365). }
unit ToolPreloadStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleAssetPreloader;

type
  TPreloadStudioHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindPreloaderInHierarchy(const Root: TComponent): TCastleAssetPreloadQueue;
    class function SpawnBossAirlockPreloadDemo(const Root, DesignOwner: TComponent;
      out Queue: TCastleAssetPreloadQueue): Boolean;
    class function GeneratePreloadReport(const Queue: TCastleAssetPreloadQueue): String;
  end;

implementation

class function TPreloadStudioHelper.FindViewport(const Root: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleViewport then Exit(TCastleViewport(Root));
  for I := 0 to Root.ComponentCount - 1 do
  begin
    Result := FindViewport(Root.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TPreloadStudioHelper.FindPreloaderInHierarchy(const Root: TComponent): TCastleAssetPreloadQueue;

  function WalkTransform(const T: TCastleTransform): TCastleAssetPreloadQueue;
  var
    I: Integer;
  begin
    if T is TCastleAssetPreloadQueue then
      Exit(TCastleAssetPreloadQueue(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := WalkTransform(T[I]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

var
  Vp: TCastleViewport;
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleAssetPreloadQueue then Exit(TCastleAssetPreloadQueue(Root));
  if Root is TCastleTransform then
  begin
    Result := WalkTransform(TCastleTransform(Root));
    if Result <> nil then Exit;
  end;
  Vp := FindViewport(Root);
  if (Vp <> nil) and (Vp.Items <> nil) then
  begin
    Result := WalkTransform(Vp.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to Root.ComponentCount - 1 do
    if Root.Components[I] is TCastleAssetPreloadQueue then
      Exit(TCastleAssetPreloadQueue(Root.Components[I]));
end;

class function TPreloadStudioHelper.SpawnBossAirlockPreloadDemo(
  const Root, DesignOwner: TComponent;
  out Queue: TCastleAssetPreloadQueue): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  GateBox: TCastleBox;
begin
  Result := False;
  Queue := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('BossAirlockGateTrigger') = nil then
  begin
    GateBox := TCastleBox.Create(OwnerComp);
    GateBox.Name := 'BossAirlockGateTrigger';
    GateBox.Size := Vector3(4.2, 3.6, 0.6);
    GateBox.Translation := Vector3(0.0, 1.8, -5.0);
    GateBox.Color := Vector4(0.85, 0.62, 0.18, 1.0);
    Vp.Items.Add(GateBox);
  end;

  Queue := FindPreloaderInHierarchy(Root);
  if Queue = nil then
  begin
    Queue := TCastleAssetPreloadQueue.Create(OwnerComp);
    Queue.Name := 'AssetPreloadQueue1';
    Queue.Preset := papBossArenaSeamlessDoor;
    Vp.Items.Add(Queue);
  end;
  Result := True;
end;

class function TPreloadStudioHelper.GeneratePreloadReport(
  const Queue: TCastleAssetPreloadQueue): String;
var
  I: Integer;
  E: TPreloadAssetEntry;
begin
  if Queue = nil then
    Exit('# Async Asset Preloader & VRAM Residency Report' + LineEnding + LineEnding +
         '_No `TCastleAssetPreloadQueue` found in design._');

  Result :=
    '# Async Asset Preloader & Frame-Budgeted VRAM Residency Report (Phase 365)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [Queue.Name, PreloadPresetToString(Queue.Preset)]) + LineEnding +
    Format('| **Frame Warmup Budget** | **`%.2f ms/frame`** (Last slice: `%.2f ms`) |', [
      Queue.MaxBudgetMsPerFrame, Queue.LastFrameSpentMs]) + LineEnding +
    Format('| **VRAM Residency Pool** | **`%.1f / %.1f MB`** (`%d` resident, `%d` pinned, `%d` queued, `%d` evictions) |', [
      Queue.CurrentResidentVramMB, Queue.MaxVramBudgetMB,
      Queue.ResidentCount, Queue.PinnedResidentCount,
      Queue.QueuedPendingCount, Queue.TotalEvictions]) + LineEnding + LineEnding +
    '## Streamable Handle Manifest' + LineEnding +
    '| Asset URL | Priority | VRAM | Warmup | Pinned | State |' + LineEnding +
    '| :--- | :--- | :--- | :--- | :--- | :--- |' + LineEnding;

  for I := 0 to Queue.EntryCount - 1 do
  begin
    E := Queue.GetEntry(I);
    Result := Result + Format('| `%s` | `%s` | `%.1f MB` | `%.2f ms` | `%s` | **`%s`** |', [
      E.AssetUrl,
      PreloadPriorityToString(E.Priority),
      E.EstimatedVramMB,
      E.EstimatedWarmupMs,
      BoolToStr(E.PinnedHandle, 'PINNED', 'LRU'),
      PreloadStateToString(E.State)]) + LineEnding;
  end;
end;

end.
