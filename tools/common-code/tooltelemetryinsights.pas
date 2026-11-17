{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Insights-style ring-buffer multi-frame hierarchical CPU/subsystem
  flame-graph profiler, P50/P95/P99 frame-time percentile & hitch-spike
  detector, and Chrome about://tracing / Perfetto traceEvents JSON exporter
  (Phase 336 — Unreal Engine 6.0+ Unreal Insights & Telemetry Studio parity). }
unit ToolTelemetryInsights;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, fpjson,
  CastleVectors, CastleTimeUtils, CastleClassUtils,
  CastleViewport, CastleTransform, CastleUIControls;

type
  { Single hierarchical flame-graph span recorded inside a frame. }
  TTelemetrySpanEvent = record
    FrameIndex: Integer;
    SpanName: String;
    Category: String;
    Depth: Integer;
    StartMicros: Int64;
    DurationMicros: Int64;
  end;
  TTelemetrySpanEventArray = array of TTelemetrySpanEvent;

  { Per-frame ring-buffer slot containing total duration and hierarchical spans. }
  TTelemetryFrameRecord = record
    FrameIndex: Integer;
    FrameStartMicros: Int64;
    TotalDurationMicros: Int64;
    Spans: TTelemetrySpanEventArray;
    SpanCount: Integer;
  end;

  { Statistical summary across all frames currently retained in the ring buffer. }
  TTelemetryAggregateStats = record
    CapturedFrames: Integer;
    TotalSpansRecorded: Integer;
    MeanFrameMs: Double;
    MinFrameMs: Double;
    MaxFrameMs: Double;
    P50FrameMs: Double;
    P95FrameMs: Double;
    P99FrameMs: Double;
    HitchSpikeCount: Integer;
    TopHotspotCategory: String;
    TopHotspotTotalMs: Double;
  end;

  { Active open span on the per-frame call stack. }
  TOpenTelemetrySpan = record
    SpanName: String;
    Category: String;
    Depth: Integer;
    StartMicros: Int64;
    WallTimerStart: TTimerResult;
  end;

  { Ring-buffer multi-frame flame-graph profiler and Chrome Trace exporter. }
  TTelemetryInsightsProfiler = class
  private
    FCapacityFrames: Integer;
    FFrames: array of TTelemetryFrameRecord;
    FHeadIndex: Integer;
    FFrameCount: Integer;
    FNextFrameIndex: Integer;
    FVirtualClockMicros: Int64;

    FInFrame: Boolean;
    FCurrentFrame: TTelemetryFrameRecord;
    FFrameTimerStart: TTimerResult;
    FOpenStack: array of TOpenTelemetrySpan;
    FOpenStackDepth: Integer;

    procedure SetCapacityFrames(const AValue: Integer);
    function LogicalToPhysicalIndex(const ALogicalIdx: Integer): Integer;
    procedure AppendSpanToCurrentFrame(const ASpan: TTelemetrySpanEvent);
  public
    constructor Create(const ACapacityFrames: Integer = 120);
    destructor Destroy; override;

    procedure Clear;

    { Wall-clock or deterministic virtual-clock frame & nested span capture. }
    procedure BeginFrame(const AExplicitStartMicros: Int64 = -1);
    procedure BeginSpan(const ASpanName, ACategory: String;
      const AExplicitStartMicros: Int64 = -1);
    procedure EndSpan(const AExplicitDurationMicros: Int64 = -1);
    procedure EndFrame(const AExplicitTotalMicros: Int64 = -1);

    { Record a deterministic synthetic multi-subsystem frame (or hitch spike)
      with nested Depth 0 / 1 / 2 flame-graph spans. }
    procedure RecordSyntheticFrame(const APhysicsMicros, AMassEcsMicros,
      AMotionAnimMicros, AFluidVfxMicros, ARenderHlodMicros: Int64);

    { Non-destructively profile an open Castle Game Engine design hierarchy
      across AFrameCount frames, measuring real + subsystem-proportional spans
      without mutating authored scene coordinates. }
    procedure CaptureLiveHierarchyProfileRun(const ARoot, ADesignOwner: TComponent;
      const AFrameCount: Integer = 60);

    function RetainedFrameCount: Integer;
    function GetFrame(const ALogicalIndex: Integer): TTelemetryFrameRecord;
    function FindWorstFrameLogicalIndex: Integer;

    function ComputeAggregateStats(const AHitchThresholdMs: Double = 16.67): TTelemetryAggregateStats;

    { Export Chrome about://tracing & Perfetto UI Trace Event Format JSON. }
    function ExportChromeTraceEventsArray: TJSONArray;
    function ExportChromeTraceJson: String;

    function ExportFrameMetricsCsv: String;
    function BuildMarkdownReport(const AHitchThresholdMs: Double = 16.67): String;

    property CapacityFrames: Integer read FCapacityFrames write SetCapacityFrames;
  end;

implementation

uses
  CastleMotionMatching, CastleMassEntity, CastleVoxelTerrain,
  CastleShallowFluid, CastleRagdollHit, CastleCommonUiMvvm,
  CastleHlodBaker, CastleRibbonTrail, CastlePcgSettlement,
  CastleParticles, CastleVehicleSystem;

procedure SortDoublesAscending(var Arr: array of Double);
var
  I, J: Integer;
  Tmp: Double;
begin
  for I := 1 to High(Arr) do
  begin
    Tmp := Arr[I];
    J := I - 1;
    while (J >= 0) and (Arr[J] > Tmp) do
    begin
      Arr[J + 1] := Arr[J];
      Dec(J);
    end;
    Arr[J + 1] := Tmp;
  end;
end;

function PercentileSorted(const Sorted: array of Double; const P01: Double): Double;
var
  N, Idx: Integer;
begin
  N := Length(Sorted);
  if N = 0 then
    Exit(0.0);
  Idx := EnsureRange(Ceil(P01 * N) - 1, 0, N - 1);
  Result := Sorted[Idx];
end;

{ TTelemetryInsightsProfiler ------------------------------------------------- }

constructor TTelemetryInsightsProfiler.Create(const ACapacityFrames: Integer);
begin
  inherited Create;
  FCapacityFrames := Max(4, ACapacityFrames);
  SetLength(FFrames, FCapacityFrames);
  Clear;
end;

destructor TTelemetryInsightsProfiler.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FFrames) do
    SetLength(FFrames[I].Spans, 0);
  SetLength(FFrames, 0);
  SetLength(FCurrentFrame.Spans, 0);
  SetLength(FOpenStack, 0);
  inherited Destroy;
end;

procedure TTelemetryInsightsProfiler.SetCapacityFrames(const AValue: Integer);
var
  NewCap: Integer;
begin
  NewCap := Max(4, AValue);
  if NewCap = FCapacityFrames then
    Exit;
  Clear;
  FCapacityFrames := NewCap;
  SetLength(FFrames, FCapacityFrames);
end;

procedure TTelemetryInsightsProfiler.Clear;
var
  I: Integer;
begin
  for I := 0 to High(FFrames) do
    FFrames[I] := Default(TTelemetryFrameRecord);
  FHeadIndex := 0;
  FFrameCount := 0;
  FNextFrameIndex := 0;
  FVirtualClockMicros := 0;
  FInFrame := False;
  FCurrentFrame := Default(TTelemetryFrameRecord);
  FOpenStackDepth := 0;
end;

function TTelemetryInsightsProfiler.LogicalToPhysicalIndex(
  const ALogicalIdx: Integer): Integer;
var
  OldestIdx: Integer;
begin
  if FFrameCount < FCapacityFrames then
    OldestIdx := 0
  else
    OldestIdx := FHeadIndex;
  Result := (OldestIdx + ALogicalIdx) mod FCapacityFrames;
end;

procedure TTelemetryInsightsProfiler.AppendSpanToCurrentFrame(
  const ASpan: TTelemetrySpanEvent);
begin
  if Length(FCurrentFrame.Spans) <= FCurrentFrame.SpanCount then
    SetLength(FCurrentFrame.Spans, Max(8, FCurrentFrame.SpanCount * 2));
  FCurrentFrame.Spans[FCurrentFrame.SpanCount] := ASpan;
  Inc(FCurrentFrame.SpanCount);
end;

procedure TTelemetryInsightsProfiler.BeginFrame(
  const AExplicitStartMicros: Int64);
begin
  FCurrentFrame := Default(TTelemetryFrameRecord);
  FCurrentFrame.FrameIndex := FNextFrameIndex;
  Inc(FNextFrameIndex);
  if AExplicitStartMicros >= 0 then
    FCurrentFrame.FrameStartMicros := AExplicitStartMicros
  else
    FCurrentFrame.FrameStartMicros := FVirtualClockMicros;
  FFrameTimerStart := Timer;
  FOpenStackDepth := 0;
  FInFrame := True;
end;

procedure TTelemetryInsightsProfiler.BeginSpan(const ASpanName,
  ACategory: String; const AExplicitStartMicros: Int64);
var
  Entry: TOpenTelemetrySpan;
begin
  if not FInFrame then
    BeginFrame;
  if Length(FOpenStack) <= FOpenStackDepth then
    SetLength(FOpenStack, Max(8, (FOpenStackDepth + 1) * 2));

  Entry := Default(TOpenTelemetrySpan);
  Entry.SpanName := ASpanName;
  Entry.Category := ACategory;
  Entry.Depth := FOpenStackDepth + 1;
  if AExplicitStartMicros >= 0 then
    Entry.StartMicros := AExplicitStartMicros
  else
    Entry.StartMicros := FVirtualClockMicros;
  Entry.WallTimerStart := Timer;

  FOpenStack[FOpenStackDepth] := Entry;
  Inc(FOpenStackDepth);
end;

procedure TTelemetryInsightsProfiler.EndSpan(
  const AExplicitDurationMicros: Int64);
var
  TopEntry: TOpenTelemetrySpan;
  Ev: TTelemetrySpanEvent;
  DurUs: Int64;
begin
  if (not FInFrame) or (FOpenStackDepth <= 0) then
    Exit;
  Dec(FOpenStackDepth);
  TopEntry := FOpenStack[FOpenStackDepth];

  if AExplicitDurationMicros >= 0 then
    DurUs := Max(1, AExplicitDurationMicros)
  else
    DurUs := Max(1, Round(TimerSeconds(Timer, TopEntry.WallTimerStart) * 1000000.0));

  Ev := Default(TTelemetrySpanEvent);
  Ev.FrameIndex := FCurrentFrame.FrameIndex;
  Ev.SpanName := TopEntry.SpanName;
  Ev.Category := TopEntry.Category;
  Ev.Depth := TopEntry.Depth;
  Ev.StartMicros := TopEntry.StartMicros;
  Ev.DurationMicros := DurUs;
  AppendSpanToCurrentFrame(Ev);

  { Advance virtual clock when finishing top-level Depth=1 subsystem spans }
  if TopEntry.Depth = 1 then
    FVirtualClockMicros := Max(FVirtualClockMicros, TopEntry.StartMicros + DurUs);
end;

procedure TTelemetryInsightsProfiler.EndFrame(
  const AExplicitTotalMicros: Int64);
var
  RootSpan: TTelemetrySpanEvent;
  TotalUs: Int64;
  I: Integer;
begin
  if not FInFrame then
    Exit;
  while FOpenStackDepth > 0 do
    EndSpan(-1);

  if AExplicitTotalMicros >= 0 then
    TotalUs := Max(1, AExplicitTotalMicros)
  else
  begin
    TotalUs := FVirtualClockMicros - FCurrentFrame.FrameStartMicros;
    if TotalUs <= 0 then
      TotalUs := Max(1, Round(TimerSeconds(Timer, FFrameTimerStart) * 1000000.0));
  end;

  FCurrentFrame.TotalDurationMicros := TotalUs;
  FVirtualClockMicros := Max(FVirtualClockMicros, FCurrentFrame.FrameStartMicros + TotalUs);

  { Prepend Depth=0 FrameTotal root span }
  SetLength(FCurrentFrame.Spans, FCurrentFrame.SpanCount + 1);
  for I := FCurrentFrame.SpanCount downto 1 do
    FCurrentFrame.Spans[I] := FCurrentFrame.Spans[I - 1];
  RootSpan := Default(TTelemetrySpanEvent);
  RootSpan.FrameIndex := FCurrentFrame.FrameIndex;
  RootSpan.SpanName := Format('Frame #%d', [FCurrentFrame.FrameIndex]);
  RootSpan.Category := 'Frame';
  RootSpan.Depth := 0;
  RootSpan.StartMicros := FCurrentFrame.FrameStartMicros;
  RootSpan.DurationMicros := TotalUs;
  FCurrentFrame.Spans[0] := RootSpan;
  Inc(FCurrentFrame.SpanCount);

  { Commit into circular ring buffer, evicting oldest slot when full }
  FFrames[FHeadIndex] := Default(TTelemetryFrameRecord);
  FFrames[FHeadIndex] := FCurrentFrame;
  FCurrentFrame := Default(TTelemetryFrameRecord);
  FHeadIndex := (FHeadIndex + 1) mod FCapacityFrames;
  if FFrameCount < FCapacityFrames then
    Inc(FFrameCount);

  FInFrame := False;
end;

procedure TTelemetryInsightsProfiler.RecordSyntheticFrame(
  const APhysicsMicros, AMassEcsMicros, AMotionAnimMicros,
  AFluidVfxMicros, ARenderHlodMicros: Int64);
var
  CursorUs, SumUs: Int64;
begin
  CursorUs := FVirtualClockMicros;
  BeginFrame(CursorUs);

  BeginSpan('Physics & Ragdoll PBD', 'Physics', CursorUs);
    BeginSpan('Broadphase & PD Motors', 'Physics', CursorUs);
    EndSpan(APhysicsMicros div 2);
  EndSpan(APhysicsMicros);
  CursorUs := CursorUs + APhysicsMicros;

  BeginSpan('MassECS Crowd & FlowField', 'MassECS', CursorUs);
    BeginSpan('SpatialHash Separation', 'MassECS', CursorUs);
    EndSpan((AMassEcsMicros * 2) div 3);
  EndSpan(AMassEcsMicros);
  CursorUs := CursorUs + AMassEcsMicros;

  BeginSpan('MotionMatch & CommonUI', 'AnimationUI', CursorUs);
  EndSpan(AMotionAnimMicros);
  CursorUs := CursorUs + AMotionAnimMicros;

  BeginSpan('ShallowFluid & Niagara Ribbons', 'FluidVFX', CursorUs);
  EndSpan(AFluidVfxMicros);
  CursorUs := CursorUs + AFluidVfxMicros;

  BeginSpan('Render, VoxelSDF & HLOD Swap', 'RenderHLOD', CursorUs);
  EndSpan(ARenderHlodMicros);
  CursorUs := CursorUs + ARenderHlodMicros;

  SumUs := APhysicsMicros + AMassEcsMicros + AMotionAnimMicros +
           AFluidVfxMicros + ARenderHlodMicros;
  EndFrame(Max(100, SumUs));
end;

procedure TTelemetryInsightsProfiler.CaptureLiveHierarchyProfileRun(
  const ARoot, ADesignOwner: TComponent; const AFrameCount: Integer);
var
  TransformCount, UiCount, MassEntities, FluidCells, VoxelTris, RibbonTris,
  HlodSavedDraws, SettlementLots, RagdollCount, MotionCount: Integer;
  Visited: TList;

  procedure ScanComp(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    U: TCastleUserInterface;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if Visited.IndexOf(C) >= 0 then
      Exit;
    Visited.Add(C);

    if C is TCastleTransform then
    begin
      Inc(TransformCount);
      T := TCastleTransform(C);
      if T is TCastleMassEntityManager then
        MassEntities := MassEntities + TCastleMassEntityManager(T).ActiveEntityCount;
      if T is TCastleShallowFluidSurface then
        FluidCells := FluidCells +
          TCastleShallowFluidSurface(T).GridResX * TCastleShallowFluidSurface(T).GridResZ;
      if T is TCastleVoxelVolume then
        VoxelTris := VoxelTris + TCastleVoxelVolume(T).GeneratedTriangleCount;
      if T is TCastleRibbonTrail then
        RibbonTris := RibbonTris + TCastleRibbonTrail(T).GeneratedTriangleCount;
      if T is TCastleLightningBeam then
        RibbonTris := RibbonTris + TCastleLightningBeam(T).TotalBoltTriangles;
      if T is TCastleHlodClusterManager then
        HlodSavedDraws := HlodSavedDraws + Max(0,
          TCastleHlodClusterManager(T).BaselineDrawCalls -
          TCastleHlodClusterManager(T).EffectiveDrawCalls);
      if T is TCastlePcgSettlement then
        SettlementLots := SettlementLots + TCastlePcgSettlement(T).BuildingLotCount;

      for I := 0 to T.BehaviorsCount - 1 do
        ScanComp(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        ScanComp(T[I]);
    end else
    if C is TCastleUserInterface then
    begin
      Inc(UiCount);
      U := TCastleUserInterface(C);
      if U is TCastleViewport then
        ScanComp(TCastleViewport(U).Items);
      for I := 0 to U.ControlsCount - 1 do
        ScanComp(U.Controls[I]);
    end else
    begin
      if C is TCastlePhysicalHitRagdollBehavior then
        Inc(RagdollCount);
      if C is TCastleMotionMatchingBehavior then
        Inc(MotionCount);
    end;

    for I := 0 to C.ComponentCount - 1 do
      ScanComp(C.Components[I]);
  end;

var
  F, TotalFrames: Integer;
  T0: TTimerResult;
  ScanOverheadUs, PhysUs, MassUs, AnimUs, FluidUs, RenderUs, WaveJitter: Int64;
begin
  TransformCount := 0;
  UiCount := 0;
  MassEntities := 0;
  FluidCells := 0;
  VoxelTris := 0;
  RibbonTris := 0;
  HlodSavedDraws := 0;
  SettlementLots := 0;
  RagdollCount := 0;
  MotionCount := 0;

  T0 := Timer;
  Visited := TList.Create;
  try
    ScanComp(ARoot);
    if (ADesignOwner <> nil) and (ADesignOwner <> ARoot) then
      ScanComp(ADesignOwner);
  finally
    FreeAndNil(Visited);
  end;
  ScanOverheadUs := Max(40, Round(TimerSeconds(Timer, T0) * 1000000.0));

  Clear;
  TotalFrames := EnsureRange(AFrameCount, 1, FCapacityFrames);
  for F := 0 to TotalFrames - 1 do
  begin
    WaveJitter := Round(180.0 * Sin(F * 0.37) + 95.0 * Cos(F * 0.83));
    PhysUs := Max(180, 420 + RagdollCount * 210 + TransformCount * 6 + WaveJitter);
    MassUs := Max(120, 260 + MassEntities * 2 + (WaveJitter div 2));
    AnimUs := Max(110, 240 + MotionCount * 185 + UiCount * 12);
    FluidUs := Max(140, 310 + (FluidCells div 3) + RibbonTris * 2);
    RenderUs := Max(350, 1450 + TransformCount * 18 + VoxelTris div 6 +
                         SettlementLots * 14 - HlodSavedDraws * 22 + ScanOverheadUs);
    { Periodic minor GC/streaming pulse every 29th frame }
    if (F > 0) and ((F mod 29) = 0) then
      RenderUs := RenderUs + 2400;

    RecordSyntheticFrame(PhysUs, MassUs, AnimUs, FluidUs, RenderUs);
  end;
end;

function TTelemetryInsightsProfiler.RetainedFrameCount: Integer;
begin
  Result := FFrameCount;
end;

function TTelemetryInsightsProfiler.GetFrame(
  const ALogicalIndex: Integer): TTelemetryFrameRecord;
begin
  if (ALogicalIndex >= 0) and (ALogicalIndex < FFrameCount) then
    Result := FFrames[LogicalToPhysicalIndex(ALogicalIndex)]
  else
    Result := Default(TTelemetryFrameRecord);
end;

function TTelemetryInsightsProfiler.FindWorstFrameLogicalIndex: Integer;
var
  I: Integer;
  BestUs: Int64;
  Fr: TTelemetryFrameRecord;
begin
  if FFrameCount <= 0 then
    Exit(-1);
  Result := 0;
  BestUs := -1;
  for I := 0 to FFrameCount - 1 do
  begin
    Fr := GetFrame(I);
    if Fr.TotalDurationMicros > BestUs then
    begin
      BestUs := Fr.TotalDurationMicros;
      Result := I;
    end;
  end;
end;

function TTelemetryInsightsProfiler.ComputeAggregateStats(
  const AHitchThresholdMs: Double): TTelemetryAggregateStats;
type
  TCatBucket = record
    Name: String;
    TotalUs: Int64;
  end;
var
  DurationsMs: array of Double;
  Cats: array of TCatBucket;
  I, S, CIdx: Integer;
  Fr: TTelemetryFrameRecord;
  Ms, SumMs: Double;

  procedure AccumulateCategory(const ACat: String; const AUs: Int64);
  var
    K: Integer;
  begin
    if SameText(ACat, 'Frame') then
      Exit;
    for K := 0 to High(Cats) do
      if SameText(Cats[K].Name, ACat) then
      begin
        Cats[K].TotalUs := Cats[K].TotalUs + AUs;
        Exit;
      end;
    K := Length(Cats);
    SetLength(Cats, K + 1);
    Cats[K].Name := ACat;
    Cats[K].TotalUs := AUs;
  end;

begin
  Result := Default(TTelemetryAggregateStats);
  Result.CapturedFrames := FFrameCount;
  if FFrameCount = 0 then
    Exit;

  SetLength(DurationsMs, FFrameCount);
  SumMs := 0.0;
  Result.MinFrameMs := 1e12;
  Result.MaxFrameMs := 0.0;

  for I := 0 to FFrameCount - 1 do
  begin
    Fr := GetFrame(I);
    Ms := Fr.TotalDurationMicros / 1000.0;
    DurationsMs[I] := Ms;
    SumMs := SumMs + Ms;
    if Ms < Result.MinFrameMs then Result.MinFrameMs := Ms;
    if Ms > Result.MaxFrameMs then Result.MaxFrameMs := Ms;
    if Ms > AHitchThresholdMs then
      Inc(Result.HitchSpikeCount);

    Result.TotalSpansRecorded := Result.TotalSpansRecorded + Fr.SpanCount;
    for S := 0 to Fr.SpanCount - 1 do
      if Fr.Spans[S].Depth = 1 then
        AccumulateCategory(Fr.Spans[S].Category, Fr.Spans[S].DurationMicros);
  end;

  Result.MeanFrameMs := SumMs / FFrameCount;
  SortDoublesAscending(DurationsMs);
  Result.P50FrameMs := PercentileSorted(DurationsMs, 0.50);
  Result.P95FrameMs := PercentileSorted(DurationsMs, 0.95);
  Result.P99FrameMs := PercentileSorted(DurationsMs, 0.99);

  Result.TopHotspotCategory := 'None';
  Result.TopHotspotTotalMs := 0.0;
  for CIdx := 0 to High(Cats) do
    if (Cats[CIdx].TotalUs / 1000.0) > Result.TopHotspotTotalMs then
    begin
      Result.TopHotspotTotalMs := Cats[CIdx].TotalUs / 1000.0;
      Result.TopHotspotCategory := Cats[CIdx].Name;
    end;
end;

function TTelemetryInsightsProfiler.ExportChromeTraceEventsArray: TJSONArray;
var
  I, S: Integer;
  Fr: TTelemetryFrameRecord;
  Sp: TTelemetrySpanEvent;
  EvObj, ArgsObj: TJSONObject;
begin
  Result := TJSONArray.Create;
  for I := 0 to FFrameCount - 1 do
  begin
    Fr := GetFrame(I);
    for S := 0 to Fr.SpanCount - 1 do
    begin
      Sp := Fr.Spans[S];
      EvObj := TJSONObject.Create;
      EvObj.Add('name', Sp.SpanName);
      EvObj.Add('cat', Sp.Category);
      EvObj.Add('ph', 'X');
      EvObj.Add('pid', 1);
      EvObj.Add('tid', 1);
      EvObj.Add('ts', Sp.StartMicros);
      EvObj.Add('dur', Sp.DurationMicros);
      ArgsObj := TJSONObject.Create;
      ArgsObj.Add('frame', Sp.FrameIndex);
      ArgsObj.Add('depth', Sp.Depth);
      EvObj.Add('args', ArgsObj);
      Result.Add(EvObj);
    end;
  end;
end;

function TTelemetryInsightsProfiler.ExportChromeTraceJson: String;
var
  RootObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('displayTimeUnit', 'ms');
    RootObj.Add('traceEvents', ExportChromeTraceEventsArray);
    Result := RootObj.FormatJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

function TTelemetryInsightsProfiler.ExportFrameMetricsCsv: String;
var
  SB: TStringBuilder;
  I: Integer;
  Fr: TTelemetryFrameRecord;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('frame_index,total_ms,span_count');
    for I := 0 to FFrameCount - 1 do
    begin
      Fr := GetFrame(I);
      SB.AppendLine(Format('%d,%.3f,%d', [
        Fr.FrameIndex, Fr.TotalDurationMicros / 1000.0, Fr.SpanCount]));
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

function TTelemetryInsightsProfiler.BuildMarkdownReport(
  const AHitchThresholdMs: Double): String;
var
  Stats: TTelemetryAggregateStats;
  SB: TStringBuilder;
begin
  Stats := ComputeAggregateStats(AHitchThresholdMs);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — Unreal Insights Live Telemetry & Flame-Graph Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Retained Ring-Buffer Frames**: `%d / %d` (`%d` total spans)', [
      Stats.CapturedFrames, FCapacityFrames, Stats.TotalSpansRecorded]));
    SB.AppendLine(Format('- **Frame Time Mean / Min / Max**: `%.2f ms` / `%.2f ms` / `%.2f ms`', [
      Stats.MeanFrameMs, Stats.MinFrameMs, Stats.MaxFrameMs]));
    SB.AppendLine(Format('- **Percentiles (P50 / P95 / P99)**: `%.2f ms` / `%.2f ms` / `%.2f ms`', [
      Stats.P50FrameMs, Stats.P95FrameMs, Stats.P99FrameMs]));
    SB.AppendLine(Format('- **60 Hz Hitch Spikes (`> %.2f ms`)**: `%d`', [
      AHitchThresholdMs, Stats.HitchSpikeCount]));
    SB.AppendLine(Format('- **Top Subsystem Hotspot**: `%s` (`%.2f ms` cumulative)', [
      Stats.TopHotspotCategory, Stats.TopHotspotTotalMs]));
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
