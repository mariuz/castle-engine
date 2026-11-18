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

{ Async Asset Preloader, Hitch-Free Frame-Budgeted Warmup Queue & Pinned/LRU
  VRAM Residency Pool (Phase 365 — UE 6.0+ FStreamableManager Parity). }
unit CastleAssetPreloader;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleClassUtils;

type
  { Streamable request priority tiers (highest priority drains first). }
  TPreloadRequestPriority = (
    prpBackgroundPrefetch = 0,
    prpNormalGameplay = 1,
    prpHighCombatVfx = 2,
    prpCriticalCutscene = 3
  );

  { Asset residency lifecycle state. }
  TPreloadResidencyState = (
    prsQueuedPending,
    prsResidentLoaded,
    prsEvictedCold
  );

  { Built-in warmup queue & VRAM budget profiles. }
  TPreloadAssetPreset = (
    papCustom,
    papBossArenaSeamlessDoor,
    papOpenWorldHorizonPrefetch,
    papCutsceneZeroHitchLock
  );

  { Tracked streamable asset handle and residency entry. }
  TPreloadAssetEntry = record
    AssetUrl: String;
    Priority: TPreloadRequestPriority;
    EstimatedVramMB: Single;
    EstimatedWarmupMs: Single;
    PinnedHandle: Boolean;
    State: TPreloadResidencyState;
    LastTouchTick: Int64;
    EnqueueOrder: Int64;
  end;

  { Telemetry returned by a single frame's budgeted warmup slice. }
  TPreloadFrameStepResult = record
    AssetsWarmedThisFrame: Integer;
    FrameTimeSpentMs: Single;
    RemainingQueuedCount: Integer;
    ResidentVramMB: Single;
    EvictedCountThisFrame: Integer;
  end;

  { Hitch-free priority asset warmup queue with strict millisecond frame budget
    throttling and pinned-handle-aware LRU VRAM residency eviction. }
  TCastleAssetPreloadQueue = class(TCastleTransform)
  private
    FPreset: TPreloadAssetPreset;
    FMaxBudgetMsPerFrame: Single;
    FMaxVramBudgetMB: Single;
    FEntries: array of TPreloadAssetEntry;
    FClockTick: Int64;
    FLastFrameSpentMs: Single;
    FTotalEvictions: Integer;
    procedure SetPreset(const AValue: TPreloadAssetPreset);
    procedure SetMaxBudgetMsPerFrame(const AValue: Single);
    procedure SetMaxVramBudgetMB(const AValue: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetManifest(const APreset: TPreloadAssetPreset);
    function FindUrlIndex(const AAssetUrl: String): Integer;
    function SelectNextHighestPriorityQueuedIndex: Integer;
    function EvictOldestUnpinnedLruToFit(const ANeededMB: Single): Integer;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ClearQueue;
    function EnqueueAssetRequest(const AAssetUrl: String;
      const APriority: TPreloadRequestPriority;
      const AEstimatedVramMB, AEstimatedWarmupMs: Single;
      const APinned: Boolean = False): Integer;
    function TouchResidentAsset(const AAssetUrl: String): Boolean;
    function SetAssetPinned(const AAssetUrl: String; const APinned: Boolean): Boolean;
    function StepFrameWarmupBudget: TPreloadFrameStepResult;
    function EntryCount: Integer;
    function GetEntry(const AIndex: Integer): TPreloadAssetEntry;
    function FindEntryByUrl(const AAssetUrl: String; out OutEntry: TPreloadAssetEntry): Boolean;
    function CurrentResidentVramMB: Single;
    function QueuedPendingCount: Integer;
    function ResidentCount: Integer;
    function PinnedResidentCount: Integer;
    function PreloadSummaryBadge: String;
    property LastFrameSpentMs: Single read FLastFrameSpentMs;
    property TotalEvictions: Integer read FTotalEvictions;
  published
    property Preset: TPreloadAssetPreset read FPreset write SetPreset default papBossArenaSeamlessDoor;
    property MaxBudgetMsPerFrame: Single read FMaxBudgetMsPerFrame write SetMaxBudgetMsPerFrame {$ifdef FPC}default 2.5{$endif};
    property MaxVramBudgetMB: Single read FMaxVramBudgetMB write SetMaxVramBudgetMB {$ifdef FPC}default 256.0{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function PreloadPresetToString(const APreset: TPreloadAssetPreset): String;
function PreloadPriorityToString(const APrio: TPreloadRequestPriority): String;
function PreloadStateToString(const AState: TPreloadResidencyState): String;

implementation

uses fpjson, jsonparser, CastleComponentSerialize;

function PreloadPresetToString(const APreset: TPreloadAssetPreset): String;
begin
  case APreset of
    papCustom: Result := 'Custom Streamable Queue';
    papBossArenaSeamlessDoor: Result := 'Boss Arena Airlock Warmup (2.5 ms/frame, 256 MB)';
    papOpenWorldHorizonPrefetch: Result := 'Open-World Horizon Prefetch (1.5 ms/frame, 512 MB)';
    papCutsceneZeroHitchLock: Result := 'Cutscene Pinned Cast Lock (4.0 ms/frame, 384 MB)';
  end;
end;

function PreloadPriorityToString(const APrio: TPreloadRequestPriority): String;
begin
  case APrio of
    prpBackgroundPrefetch: Result := 'Background';
    prpNormalGameplay: Result := 'Normal';
    prpHighCombatVfx: Result := 'HighVFX';
    prpCriticalCutscene: Result := 'CRITICAL';
  end;
end;

function PreloadStateToString(const AState: TPreloadResidencyState): String;
begin
  case AState of
    prsQueuedPending: Result := 'QUEUED';
    prsResidentLoaded: Result := 'RESIDENT';
    prsEvictedCold: Result := 'EVICTED_LRU';
  end;
end;

{ TCastleAssetPreloadQueue ---------------------------------------------------- }

constructor TCastleAssetPreloadQueue.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FClockTick := 1;
  FLastFrameSpentMs := 0.0;
  FTotalEvictions := 0;
  ApplyPresetManifest(papBossArenaSeamlessDoor);
end;

procedure TCastleAssetPreloadQueue.ApplyPresetManifest(const APreset: TPreloadAssetPreset);
begin
  SetLength(FEntries, 0);
  FTotalEvictions := 0;
  FLastFrameSpentMs := 0.0;
  case APreset of
    papBossArenaSeamlessDoor, papCustom:
      begin
        FMaxBudgetMsPerFrame := 2.5;
        FMaxVramBudgetMB := 256.0;
        EnqueueAssetRequest('castle-data:/boss/malakor_mesh.gltf', prpCriticalCutscene, 64.0, 1.4, True);
        EnqueueAssetRequest('castle-data:/boss/hellfire_vfx.x3d', prpHighCombatVfx, 28.0, 0.9, True);
        EnqueueAssetRequest('castle-data:/arena/pillars_lod0.gltf', prpNormalGameplay, 42.0, 1.1, False);
        EnqueueAssetRequest('castle-data:/audio/boss_choir_stem.ogg', prpHighCombatVfx, 18.0, 0.7, False);
        EnqueueAssetRequest('castle-data:/vista/far_mountains.ktx2', prpBackgroundPrefetch, 36.0, 1.2, False);
        FPreset := APreset;
      end;
    papOpenWorldHorizonPrefetch:
      begin
        FMaxBudgetMsPerFrame := 1.5;
        FMaxVramBudgetMB := 512.0;
        EnqueueAssetRequest('castle-data:/player/mount_horse.gltf', prpCriticalCutscene, 38.0, 0.8, True);
        EnqueueAssetRequest('castle-data:/chunk/sector_n4_e2.castle-transform', prpNormalGameplay, 84.0, 1.1, False);
        EnqueueAssetRequest('castle-data:/chunk/sector_n5_e2.castle-transform', prpBackgroundPrefetch, 92.0, 1.2, False);
        EnqueueAssetRequest('castle-data:/chunk/sector_n5_e3.castle-transform', prpBackgroundPrefetch, 88.0, 1.1, False);
        FPreset := papOpenWorldHorizonPrefetch;
      end;
    papCutsceneZeroHitchLock:
      begin
        FMaxBudgetMsPerFrame := 4.0;
        FMaxVramBudgetMB := 384.0;
        EnqueueAssetRequest('castle-data:/cinematic/hero_closeup_4k.gltf', prpCriticalCutscene, 96.0, 1.8, True);
        EnqueueAssetRequest('castle-data:/cinematic/villain_throne.gltf', prpCriticalCutscene, 88.0, 1.6, True);
        EnqueueAssetRequest('castle-data:/cinematic/spark_shower.x3d', prpHighCombatVfx, 32.0, 0.9, False);
        FPreset := papCutsceneZeroHitchLock;
      end;
  end;
end;

procedure TCastleAssetPreloadQueue.SetPreset(const AValue: TPreloadAssetPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> papCustom then
    ApplyPresetManifest(AValue);
end;

procedure TCastleAssetPreloadQueue.SetMaxBudgetMsPerFrame(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.1, 50.0);
  if SameValue(FMaxBudgetMsPerFrame, V, 1e-4) then Exit;
  FMaxBudgetMsPerFrame := V;
  FPreset := papCustom;
end;

procedure TCastleAssetPreloadQueue.SetMaxVramBudgetMB(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 8.0, 16384.0);
  if SameValue(FMaxVramBudgetMB, V, 1e-3) then Exit;
  FMaxVramBudgetMB := V;
  FPreset := papCustom;
end;

procedure TCastleAssetPreloadQueue.ClearQueue;
begin
  SetLength(FEntries, 0);
  FLastFrameSpentMs := 0.0;
  FTotalEvictions := 0;
  FPreset := papCustom;
end;

function TCastleAssetPreloadQueue.FindUrlIndex(const AAssetUrl: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FEntries) do
    if SameText(FEntries[I].AssetUrl, AAssetUrl) then
      Exit(I);
  Result := -1;
end;

function TCastleAssetPreloadQueue.EnqueueAssetRequest(const AAssetUrl: String;
  const APriority: TPreloadRequestPriority;
  const AEstimatedVramMB, AEstimatedWarmupMs: Single;
  const APinned: Boolean): Integer;
var
  Idx: Integer;
begin
  Inc(FClockTick);
  Idx := FindUrlIndex(AAssetUrl);
  if Idx >= 0 then
  begin
    if Ord(APriority) > Ord(FEntries[Idx].Priority) then
      FEntries[Idx].Priority := APriority;
    FEntries[Idx].PinnedHandle := FEntries[Idx].PinnedHandle or APinned;
    FEntries[Idx].LastTouchTick := FClockTick;
    if FEntries[Idx].State = prsEvictedCold then
    begin
      FEntries[Idx].State := prsQueuedPending;
      FEntries[Idx].EnqueueOrder := FClockTick;
    end;
    FPreset := papCustom;
    Exit(Idx);
  end;

  Idx := Length(FEntries);
  SetLength(FEntries, Idx + 1);
  FEntries[Idx].AssetUrl := AAssetUrl;
  FEntries[Idx].Priority := APriority;
  FEntries[Idx].EstimatedVramMB := Max(0.1, AEstimatedVramMB);
  FEntries[Idx].EstimatedWarmupMs := Max(0.05, AEstimatedWarmupMs);
  FEntries[Idx].PinnedHandle := APinned;
  FEntries[Idx].State := prsQueuedPending;
  FEntries[Idx].LastTouchTick := FClockTick;
  FEntries[Idx].EnqueueOrder := FClockTick;
  FPreset := papCustom;
  Result := Idx;
end;

function TCastleAssetPreloadQueue.TouchResidentAsset(const AAssetUrl: String): Boolean;
var
  Idx: Integer;
begin
  Idx := FindUrlIndex(AAssetUrl);
  Result := (Idx >= 0) and (FEntries[Idx].State = prsResidentLoaded);
  if Result then
  begin
    Inc(FClockTick);
    FEntries[Idx].LastTouchTick := FClockTick;
  end;
end;

function TCastleAssetPreloadQueue.SetAssetPinned(const AAssetUrl: String;
  const APinned: Boolean): Boolean;
var
  Idx: Integer;
begin
  Idx := FindUrlIndex(AAssetUrl);
  Result := Idx >= 0;
  if Result then
    FEntries[Idx].PinnedHandle := APinned;
end;

function TCastleAssetPreloadQueue.SelectNextHighestPriorityQueuedIndex: Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FEntries) do
    if FEntries[I].State = prsQueuedPending then
    begin
      if Result < 0 then
        Result := I
      else if Ord(FEntries[I].Priority) > Ord(FEntries[Result].Priority) then
        Result := I
      else if (FEntries[I].Priority = FEntries[Result].Priority) and
              (FEntries[I].EnqueueOrder < FEntries[Result].EnqueueOrder) then
        Result := I;
    end;
end;

function TCastleAssetPreloadQueue.EvictOldestUnpinnedLruToFit(
  const ANeededMB: Single): Integer;
var
  I, OldestIdx: Integer;
begin
  Result := 0;
  while (CurrentResidentVramMB + ANeededMB > FMaxVramBudgetMB) do
  begin
    OldestIdx := -1;
    for I := 0 to High(FEntries) do
      if (FEntries[I].State = prsResidentLoaded) and (not FEntries[I].PinnedHandle) then
      begin
        if (OldestIdx < 0) or (FEntries[I].LastTouchTick < FEntries[OldestIdx].LastTouchTick) then
          OldestIdx := I;
      end;
    if OldestIdx < 0 then
      Break; { Only pinned handles remain — never evict pinned handles! }
    FEntries[OldestIdx].State := prsEvictedCold;
    Inc(Result);
    Inc(FTotalEvictions);
  end;
end;

function TCastleAssetPreloadQueue.StepFrameWarmupBudget: TPreloadFrameStepResult;
var
  NextIdx: Integer;
  CostMs: Single;
begin
  FillChar(Result, SizeOf(Result), 0);
  while True do
  begin
    NextIdx := SelectNextHighestPriorityQueuedIndex;
    if NextIdx < 0 then Break;

    CostMs := FEntries[NextIdx].EstimatedWarmupMs;
    { Enforce strict per-frame ms budget; allow at least 1 oversized item on an empty frame so nothing deadlocks }
    if (Result.AssetsWarmedThisFrame > 0) and
       (Result.FrameTimeSpentMs + CostMs > FMaxBudgetMsPerFrame + 1e-4) then
      Break;

    Result.EvictedCountThisFrame := Result.EvictedCountThisFrame +
      EvictOldestUnpinnedLruToFit(FEntries[NextIdx].EstimatedVramMB);

    Inc(FClockTick);
    FEntries[NextIdx].State := prsResidentLoaded;
    FEntries[NextIdx].LastTouchTick := FClockTick;
    Result.FrameTimeSpentMs := Result.FrameTimeSpentMs + CostMs;
    Inc(Result.AssetsWarmedThisFrame);

    if Result.FrameTimeSpentMs >= FMaxBudgetMsPerFrame - 1e-4 then
      Break;
  end;

  FLastFrameSpentMs := Result.FrameTimeSpentMs;
  Result.RemainingQueuedCount := QueuedPendingCount;
  Result.ResidentVramMB := CurrentResidentVramMB;
end;

function TCastleAssetPreloadQueue.EntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TCastleAssetPreloadQueue.GetEntry(const AIndex: Integer): TPreloadAssetEntry;
begin
  if (AIndex >= 0) and (AIndex < Length(FEntries)) then
    Result := FEntries[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleAssetPreloadQueue.FindEntryByUrl(const AAssetUrl: String;
  out OutEntry: TPreloadAssetEntry): Boolean;
var
  Idx: Integer;
begin
  Idx := FindUrlIndex(AAssetUrl);
  Result := Idx >= 0;
  if Result then
    OutEntry := FEntries[Idx]
  else
    FillChar(OutEntry, SizeOf(OutEntry), 0);
end;

function TCastleAssetPreloadQueue.CurrentResidentVramMB: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FEntries) do
    if FEntries[I].State = prsResidentLoaded then
      Result := Result + FEntries[I].EstimatedVramMB;
end;

function TCastleAssetPreloadQueue.QueuedPendingCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FEntries) do
    if FEntries[I].State = prsQueuedPending then
      Inc(Result);
end;

function TCastleAssetPreloadQueue.ResidentCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FEntries) do
    if FEntries[I].State = prsResidentLoaded then
      Inc(Result);
end;

function TCastleAssetPreloadQueue.PinnedResidentCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FEntries) do
    if (FEntries[I].State = prsResidentLoaded) and FEntries[I].PinnedHandle then
      Inc(Result);
end;

function TCastleAssetPreloadQueue.GetConfigJson: String;
var
  RootObj, EObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('budgetMs', FMaxBudgetMsPerFrame);
    RootObj.Add('vramMB', FMaxVramBudgetMB);
    Arr := TJSONArray.Create;
    for I := 0 to High(FEntries) do
    begin
      EObj := TJSONObject.Create;
      EObj.Add('url', FEntries[I].AssetUrl);
      EObj.Add('prio', Ord(FEntries[I].Priority));
      EObj.Add('mb', FEntries[I].EstimatedVramMB);
      EObj.Add('ms', FEntries[I].EstimatedWarmupMs);
      EObj.Add('pin', FEntries[I].PinnedHandle);
      EObj.Add('state', Ord(FEntries[I].State));
      Arr.Add(EObj);
    end;
    RootObj.Add('entries', Arr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleAssetPreloadQueue.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, EObj: TJSONObject;
  Arr: TJSONArray;
  I, PresetOrd, PrioOrd, StateOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FMaxBudgetMsPerFrame := EnsureRange(RootObj.Get('budgetMs', FMaxBudgetMsPerFrame), 0.1, 50.0);
      FMaxVramBudgetMB := EnsureRange(RootObj.Get('vramMB', FMaxVramBudgetMB), 8.0, 16384.0);
      Arr := RootObj.Find('entries', jtArray) as TJSONArray;
      if Arr <> nil then
      begin
        SetLength(FEntries, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            EObj := TJSONObject(Arr.Items[I]);
            Inc(FClockTick);
            FEntries[I].AssetUrl := EObj.Get('url', '');
            PrioOrd := EnsureRange(EObj.Get('prio', 1), 0, Ord(High(TPreloadRequestPriority)));
            StateOrd := EnsureRange(EObj.Get('state', 0), 0, Ord(High(TPreloadResidencyState)));
            FEntries[I].Priority := TPreloadRequestPriority(PrioOrd);
            FEntries[I].EstimatedVramMB := Max(0.1, EObj.Get('mb', 16.0));
            FEntries[I].EstimatedWarmupMs := Max(0.05, EObj.Get('ms', 0.5));
            FEntries[I].PinnedHandle := EObj.Get('pin', False);
            FEntries[I].State := TPreloadResidencyState(StateOrd);
            FEntries[I].LastTouchTick := FClockTick;
            FEntries[I].EnqueueOrder := FClockTick;
          end;
      end;
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TPreloadAssetPreset))) and
         (PresetOrd <= Ord(High(TPreloadAssetPreset))) then
        FPreset := TPreloadAssetPreset(PresetOrd);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleAssetPreloadQueue.PreloadSummaryBadge: String;
begin
  Result := Format('[Preload:%d/%d VRAM=%.0f/%.0fMB %.1fms/f]', [
    ResidentCount,
    EntryCount,
    CurrentResidentVramMB,
    FMaxVramBudgetMB,
    FMaxBudgetMsPerFrame]);
end;

initialization
  RegisterSerializableComponent(TCastleAssetPreloadQueue, ['World & Streaming', 'Async Asset Preloader & VRAM Queue']);
end.
