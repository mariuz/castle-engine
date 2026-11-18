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

{ MassTraffic multi-lane urban road network, NEMA conflict-free 4-way signal
  interlocks, and Intelligent Driver Model (IDM) car-following (Phase 355). }
unit CastleMassTraffic;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Urban traffic density and signal timing presets. }
  TMassTrafficPreset = (
    mtpCustom,
    mtpDowntownCrossroads24,
    mtpRushHourGridlock40,
    mtpLateNightCruisers16
  );

  { Conflict-free 6-stage NEMA 4-way signal phase cycle. }
  TTrafficSignalPhase = (
    tspNorthSouthGreen,
    tspNorthSouthYellow,
    tspAllRedClearance1,
    tspEastWestGreen,
    tspEastWestYellow,
    tspAllRedClearance2
  );

  { Individual signal aspect color. }
  TTrafficLightColor = (tlcRed, tlcYellow, tlcGreen);

  { Directed lane descriptor in the crossroads network. }
  TTrafficLaneInfo = record
    LaneIndex: Integer;
    StartLocal: TVector3;
    EndLocal: TVector3;
    LengthMeters: Single;
    StopLineMeters: Single;
    NorthSouthAxis: Boolean;
  end;

  { Per-vehicle Intelligent Driver Model (IDM) kinematic state. }
  TTrafficVehicleState = record
    VehicleId: Integer;
    LaneIndex: Integer;
    DistanceAlongLane: Single;
    SpeedMps: Single;
    AccelerationMps2: Single;
    LengthMeters: Single;
    ColorRGB: TVector3;
    WorldOrLocalPos: TVector3;
    ForwardDir: TVector3;
    StoppedAtRed: Boolean;
  end;

  { Aggregated network throughput and safety telemetry. }
  TMassTrafficStats = record
    ActiveVehicles: Integer;
    LaneCount: Integer;
    MeanSpeedMps: Single;
    StoppedQueueCount: Integer;
    RearEndOverlapCount: Integer;
    SignalConflictCount: Integer;
    TotalPhaseTransitions: Integer;
    ElapsedTimeSec: Single;
  end;

  { Multi-lane city traffic manager matching Unreal Engine 6.0+ MassTraffic
    with 8 directed lanes, conflict-free 4-way signal phases, and IDM headway braking. }
  TCastleMassTrafficManager = class(TCastleTransform)
  private
    FPreset: TMassTrafficPreset;
    FVehicleCount: Integer;
    FDesiredSpeedMps: Single;
    FSafeTimeHeadwaySec: Single;
    FMinJamGapMeters: Single;
    FMaxAccelMps2: Single;
    FComfortDecelMps2: Single;
    FGreenDurationSec: Single;
    FYellowDurationSec: Single;
    FAllRedDurationSec: Single;
    FSignalPhase: TTrafficSignalPhase;
    FPhaseTimerSec: Single;
    FShowTrafficMesh: Boolean;
    FLanes: array of TTrafficLaneInfo;
    FVehicles: array of TTrafficVehicleState;
    FStats: TMassTrafficStats;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TMassTrafficPreset);
    procedure SetVehicleCount(const AValue: Integer);
    procedure SetDesiredSpeedMps(const AValue: Single);
    procedure SetSafeTimeHeadwaySec(const AValue: Single);
    procedure SetMinJamGapMeters(const AValue: Single);
    procedure SetGreenDurationSec(const AValue: Single);
    procedure SetYellowDurationSec(const AValue: Single);
    procedure SetAllRedDurationSec(const AValue: Single);
    procedure SetShowTrafficMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParamsOnly(const APreset: TMassTrafficPreset);
    procedure BuildEightLaneCrossroads;
    function CurrentPhaseDurationSec: Single;
    procedure AdvanceSignalStateMachine(const Dt: Single);
    procedure UpdateDerivedPosesAndStats;
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
    procedure RebuildTrafficPreviewMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RebuildTrafficSimulation;
    procedure StepTraffic(const Dt: Single);
    procedure ForceSignalPhase(const APhase: TTrafficSignalPhase);
    function NorthSouthLightColor: TTrafficLightColor;
    function EastWestLightColor: TTrafficLightColor;
    function LaneLightColor(const ALaneIndex: Integer): TTrafficLightColor;
    function VehicleStateCount: Integer;
    function GetVehicleState(const AIndex: Integer): TTrafficVehicleState;
    function GetLaneInfo(const ALaneIndex: Integer): TTrafficLaneInfo;
    function TrafficSummaryBadge: String;
    property SignalPhase: TTrafficSignalPhase read FSignalPhase;
    property Stats: TMassTrafficStats read FStats;
  published
    property Preset: TMassTrafficPreset read FPreset write SetPreset default mtpDowntownCrossroads24;
    property VehicleCount: Integer read FVehicleCount write SetVehicleCount default 24;
    property DesiredSpeedMps: Single read FDesiredSpeedMps write SetDesiredSpeedMps {$ifdef FPC}default 13.5{$endif};
    property SafeTimeHeadwaySec: Single read FSafeTimeHeadwaySec write SetSafeTimeHeadwaySec {$ifdef FPC}default 1.30{$endif};
    property MinJamGapMeters: Single read FMinJamGapMeters write SetMinJamGapMeters {$ifdef FPC}default 2.20{$endif};
    property GreenDurationSec: Single read FGreenDurationSec write SetGreenDurationSec {$ifdef FPC}default 8.0{$endif};
    property YellowDurationSec: Single read FYellowDurationSec write SetYellowDurationSec {$ifdef FPC}default 2.0{$endif};
    property AllRedDurationSec: Single read FAllRedDurationSec write SetAllRedDurationSec {$ifdef FPC}default 1.0{$endif};
    property ShowTrafficMesh: Boolean read FShowTrafficMesh write SetShowTrafficMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function MassTrafficPresetToString(const APreset: TMassTrafficPreset): String;
function TrafficSignalPhaseToString(const APhase: TTrafficSignalPhase): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function MassTrafficPresetToString(const APreset: TMassTrafficPreset): String;
begin
  case APreset of
    mtpCustom: Result := 'Custom Traffic Network';
    mtpDowntownCrossroads24: Result := 'Downtown 8-Lane Crossroads (24 cars)';
    mtpRushHourGridlock40: Result := 'Rush-Hour Commuter Flow (40 cars)';
    mtpLateNightCruisers16: Result := 'Late-Night Arterial Cruisers (16 cars)';
  end;
end;

function TrafficSignalPhaseToString(const APhase: TTrafficSignalPhase): String;
begin
  case APhase of
    tspNorthSouthGreen: Result := 'NS=GREEN / EW=RED';
    tspNorthSouthYellow: Result := 'NS=YELLOW / EW=RED';
    tspAllRedClearance1: Result := 'ALL-RED CLEARANCE (NS->EW)';
    tspEastWestGreen: Result := 'NS=RED / EW=GREEN';
    tspEastWestYellow: Result := 'NS=RED / EW=YELLOW';
    tspAllRedClearance2: Result := 'ALL-RED CLEARANCE (EW->NS)';
  end;
end;

{$PUSH}{$Q-}{$R-}
function VehiclePaletteColor(const AId: Integer): TVector3;
begin
  case Cardinal(AId) mod 6 of
    0: Result := Vector3(0.92, 0.28, 0.24);
    1: Result := Vector3(0.24, 0.66, 0.96);
    2: Result := Vector3(0.96, 0.78, 0.20);
    3: Result := Vector3(0.30, 0.84, 0.56);
    4: Result := Vector3(0.88, 0.90, 0.94);
  else
    Result := Vector3(0.74, 0.44, 0.94);
  end;
end;
{$POP}

{ TCastleMassTrafficManager -------------------------------------------------- }

constructor TCastleMassTrafficManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := mtpDowntownCrossroads24;
  FVehicleCount := 24;
  FDesiredSpeedMps := 13.5;
  FSafeTimeHeadwaySec := 1.30;
  FMinJamGapMeters := 2.20;
  FMaxAccelMps2 := 2.80;
  FComfortDecelMps2 := 3.40;
  FGreenDurationSec := 8.0;
  FYellowDurationSec := 2.0;
  FAllRedDurationSec := 1.0;
  FSignalPhase := tspNorthSouthGreen;
  FPhaseTimerSec := 0.0;
  FShowTrafficMesh := True;
  ApplyPresetParamsOnly(mtpDowntownCrossroads24);
  RebuildTrafficSimulation;
end;

destructor TCastleMassTrafficManager.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleMassTrafficManager.ApplyPresetParamsOnly(const APreset: TMassTrafficPreset);
begin
  case APreset of
    mtpDowntownCrossroads24, mtpCustom:
      begin
        FVehicleCount := 24;
        FDesiredSpeedMps := 13.5;
        FSafeTimeHeadwaySec := 1.30;
        FGreenDurationSec := 8.0;
      end;
    mtpRushHourGridlock40:
      begin
        FVehicleCount := 40;
        FDesiredSpeedMps := 10.5;
        FSafeTimeHeadwaySec := 1.45;
        FGreenDurationSec := 10.0;
      end;
    mtpLateNightCruisers16:
      begin
        FVehicleCount := 16;
        FDesiredSpeedMps := 16.5;
        FSafeTimeHeadwaySec := 1.15;
        FGreenDurationSec := 6.5;
      end;
  end;
end;

procedure TCastleMassTrafficManager.SetPreset(const AValue: TMassTrafficPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> mtpCustom then
  begin
    ApplyPresetParamsOnly(AValue);
    RebuildTrafficSimulation;
  end;
end;

procedure TCastleMassTrafficManager.SetVehicleCount(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 4, 80);
  if FVehicleCount = V then Exit;
  FVehicleCount := V;
  FPreset := mtpCustom;
  RebuildTrafficSimulation;
end;

procedure TCastleMassTrafficManager.SetDesiredSpeedMps(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 3.0, 35.0);
  if SameValue(FDesiredSpeedMps, V, 1e-4) then Exit;
  FDesiredSpeedMps := V;
  FPreset := mtpCustom;
end;

procedure TCastleMassTrafficManager.SetSafeTimeHeadwaySec(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.4, 5.0);
  if SameValue(FSafeTimeHeadwaySec, V, 1e-4) then Exit;
  FSafeTimeHeadwaySec := V;
  FPreset := mtpCustom;
end;

procedure TCastleMassTrafficManager.SetMinJamGapMeters(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.8, 12.0);
  if SameValue(FMinJamGapMeters, V, 1e-4) then Exit;
  FMinJamGapMeters := V;
end;

procedure TCastleMassTrafficManager.SetGreenDurationSec(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 2.0, 60.0);
  if SameValue(FGreenDurationSec, V, 1e-4) then Exit;
  FGreenDurationSec := V;
end;

procedure TCastleMassTrafficManager.SetYellowDurationSec(const AValue: Single);
begin
  FYellowDurationSec := EnsureRange(AValue, 0.5, 10.0);
end;

procedure TCastleMassTrafficManager.SetAllRedDurationSec(const AValue: Single);
begin
  FAllRedDurationSec := EnsureRange(AValue, 0.2, 10.0);
end;

procedure TCastleMassTrafficManager.SetShowTrafficMesh(const AValue: Boolean);
begin
  if FShowTrafficMesh = AValue then Exit;
  FShowTrafficMesh := AValue;
  if not FShowTrafficMesh then
    ClearTransientScene
  else
    RebuildTrafficPreviewMesh;
end;

procedure TCastleMassTrafficManager.BuildEightLaneCrossroads;
const
  HalfRoad = 60.0;
  StopS = 51.0;

  procedure InitLane(const AIdx: Integer; const AStart, AEnd: TVector3; const ANS: Boolean);
  begin
    FLanes[AIdx].LaneIndex := AIdx;
    FLanes[AIdx].StartLocal := AStart;
    FLanes[AIdx].EndLocal := AEnd;
    FLanes[AIdx].LengthMeters := PointsDistance(AStart, AEnd);
    FLanes[AIdx].StopLineMeters := StopS;
    FLanes[AIdx].NorthSouthAxis := ANS;
  end;

begin
  SetLength(FLanes, 8);
  { 0..1: Northbound (+Z -> -Z), 2..3: Southbound (-Z -> +Z) }
  InitLane(0, Vector3( 1.8, 0.0,  HalfRoad), Vector3( 1.8, 0.0, -HalfRoad), True);
  InitLane(1, Vector3( 5.2, 0.0,  HalfRoad), Vector3( 5.2, 0.0, -HalfRoad), True);
  InitLane(2, Vector3(-1.8, 0.0, -HalfRoad), Vector3(-1.8, 0.0,  HalfRoad), True);
  InitLane(3, Vector3(-5.2, 0.0, -HalfRoad), Vector3(-5.2, 0.0,  HalfRoad), True);
  { 4..5: Eastbound (-X -> +X), 6..7: Westbound (+X -> -X) }
  InitLane(4, Vector3(-HalfRoad, 0.0,  1.8), Vector3( HalfRoad, 0.0,  1.8), False);
  InitLane(5, Vector3(-HalfRoad, 0.0,  5.2), Vector3( HalfRoad, 0.0,  5.2), False);
  InitLane(6, Vector3( HalfRoad, 0.0, -1.8), Vector3(-HalfRoad, 0.0, -1.8), False);
  InitLane(7, Vector3( HalfRoad, 0.0, -5.2), Vector3(-HalfRoad, 0.0, -5.2), False);
end;

procedure TCastleMassTrafficManager.RebuildTrafficSimulation;
var
  I, LIdx, SlotInLane, CarsInLane: Integer;
  Spacing: Single;
begin
  BuildEightLaneCrossroads;
  SetLength(FVehicles, FVehicleCount);
  FSignalPhase := tspNorthSouthGreen;
  FPhaseTimerSec := 0.0;
  FillChar(FStats, SizeOf(FStats), 0);

  for I := 0 to FVehicleCount - 1 do
  begin
    LIdx := I mod 8;
    SlotInLane := I div 8;
    CarsInLane := (FVehicleCount + 7 - LIdx) div 8;
    Spacing := 42.0 / Max(1, CarsInLane);

    FVehicles[I].VehicleId := I;
    FVehicles[I].LaneIndex := LIdx;
    { Spawn cleanly upstream of StopLineMeters (51m) at 4m..46m with generous headway }
    FVehicles[I].DistanceAlongLane := 4.0 + SlotInLane * Spacing;
    if LaneLightColor(LIdx) = tlcGreen then
      FVehicles[I].SpeedMps := FDesiredSpeedMps * 0.72
    else
      FVehicles[I].SpeedMps := FDesiredSpeedMps * 0.45;
    FVehicles[I].AccelerationMps2 := 0.0;
    FVehicles[I].LengthMeters := 4.2;
    FVehicles[I].ColorRGB := VehiclePaletteColor(I);
    FVehicles[I].StoppedAtRed := False;
  end;

  UpdateDerivedPosesAndStats;
end;

function TCastleMassTrafficManager.CurrentPhaseDurationSec: Single;
begin
  case FSignalPhase of
    tspNorthSouthGreen, tspEastWestGreen: Result := FGreenDurationSec;
    tspNorthSouthYellow, tspEastWestYellow: Result := FYellowDurationSec;
  else
    Result := FAllRedDurationSec;
  end;
end;

function TCastleMassTrafficManager.NorthSouthLightColor: TTrafficLightColor;
begin
  case FSignalPhase of
    tspNorthSouthGreen: Result := tlcGreen;
    tspNorthSouthYellow: Result := tlcYellow;
  else
    Result := tlcRed;
  end;
end;

function TCastleMassTrafficManager.EastWestLightColor: TTrafficLightColor;
begin
  case FSignalPhase of
    tspEastWestGreen: Result := tlcGreen;
    tspEastWestYellow: Result := tlcYellow;
  else
    Result := tlcRed;
  end;
end;

function TCastleMassTrafficManager.LaneLightColor(const ALaneIndex: Integer): TTrafficLightColor;
begin
  if (ALaneIndex >= 0) and (ALaneIndex < Length(FLanes)) and FLanes[ALaneIndex].NorthSouthAxis then
    Result := NorthSouthLightColor
  else
    Result := EastWestLightColor;
end;

procedure TCastleMassTrafficManager.ForceSignalPhase(const APhase: TTrafficSignalPhase);
begin
  FSignalPhase := APhase;
  FPhaseTimerSec := 0.0;
  UpdateDerivedPosesAndStats;
end;

procedure TCastleMassTrafficManager.AdvanceSignalStateMachine(const Dt: Single);
begin
  FPhaseTimerSec := FPhaseTimerSec + Dt;
  while FPhaseTimerSec >= CurrentPhaseDurationSec do
  begin
    FPhaseTimerSec := FPhaseTimerSec - CurrentPhaseDurationSec;
    if FSignalPhase = High(TTrafficSignalPhase) then
      FSignalPhase := Low(TTrafficSignalPhase)
    else
      FSignalPhase := Succ(FSignalPhase);
    Inc(FStats.TotalPhaseTransitions);
  end;
end;

procedure TCastleMassTrafficManager.StepTraffic(const Dt: Single);
const
  MaxSubDt = 1.0 / 30.0;
var
  RemDt, StepDt, LaneLen, StopPos, BestGap, CandCenterDiff, CandGap,
  DeltaV, SStar, FreeTerm, IntTerm, Accel, NewV, NewS, MaxAllowedS: Single;
  I, J, LIdx: Integer;
  Light: TTrafficLightColor;
  NextDist, NextSpeed, NextAccel: array of Single;
  MustStopAtLine: Boolean;
begin
  if (Dt <= 0.0) or (Length(FVehicles) = 0) then Exit;
  SetLength(NextDist, Length(FVehicles));
  SetLength(NextSpeed, Length(FVehicles));
  SetLength(NextAccel, Length(FVehicles));

  RemDt := Min(Dt, 0.25);
  while RemDt > 1e-6 do
  begin
    StepDt := Min(RemDt, MaxSubDt);
    RemDt := RemDt - StepDt;
    AdvanceSignalStateMachine(StepDt);
    FStats.ElapsedTimeSec := FStats.ElapsedTimeSec + StepDt;

    for I := 0 to High(FVehicles) do
    begin
      LIdx := FVehicles[I].LaneIndex;
      LaneLen := FLanes[LIdx].LengthMeters;
      StopPos := FLanes[LIdx].StopLineMeters - FVehicles[I].LengthMeters * 0.5;
      Light := LaneLightColor(LIdx);

      BestGap := 1e6;
      DeltaV := 0.0;

      { 1. Find closest leading vehicle on the same periodic lane }
      for J := 0 to High(FVehicles) do
        if (J <> I) and (FVehicles[J].LaneIndex = LIdx) then
        begin
          CandCenterDiff := FVehicles[J].DistanceAlongLane - FVehicles[I].DistanceAlongLane;
          if CandCenterDiff <= 0.0 then
            CandCenterDiff := CandCenterDiff + LaneLen;
          CandGap := CandCenterDiff - 0.5 * (FVehicles[I].LengthMeters + FVehicles[J].LengthMeters);
          if CandGap < BestGap then
          begin
            BestGap := CandGap;
            DeltaV := FVehicles[I].SpeedMps - FVehicles[J].SpeedMps;
          end;
        end;

      { 2. Virtual stationary stop-line obstacle when lane light is Red or Yellow }
      MustStopAtLine := (Light <> tlcGreen) and (FVehicles[I].DistanceAlongLane <= StopPos + 0.02);
      if MustStopAtLine then
      begin
        CandGap := StopPos - FVehicles[I].DistanceAlongLane;
        if CandGap < BestGap then
        begin
          BestGap := CandGap;
          DeltaV := FVehicles[I].SpeedMps;
        end;
      end;

      { 3. Intelligent Driver Model (IDM) longitudinal acceleration }
      FreeTerm := Power(FVehicles[I].SpeedMps / Max(1.0, FDesiredSpeedMps), 4.0);
      if BestGap < 80.0 then
      begin
        SStar := FMinJamGapMeters + Max(0.0,
          FVehicles[I].SpeedMps * FSafeTimeHeadwaySec +
          (FVehicles[I].SpeedMps * DeltaV) / (2.0 * Sqrt(Max(0.1, FMaxAccelMps2 * FComfortDecelMps2))));
        IntTerm := Sqr(SStar / Max(0.20, BestGap));
      end else
        IntTerm := 0.0;

      Accel := EnsureRange(FMaxAccelMps2 * (1.0 - FreeTerm - IntTerm), -9.5, FMaxAccelMps2);
      NewV := Max(0.0, FVehicles[I].SpeedMps + Accel * StepDt);
      NewS := FVehicles[I].DistanceAlongLane + NewV * StepDt;

      { Hard anti-tunneling safety envelope against stop line and leader bumper }
      MaxAllowedS := FVehicles[I].DistanceAlongLane + Max(0.0, BestGap - 0.45);
      if NewS > MaxAllowedS then
      begin
        NewS := MaxAllowedS;
        NewV := Max(0.0, (NewS - FVehicles[I].DistanceAlongLane) / StepDt);
      end;

      if NewS >= LaneLen then
        NewS := NewS - LaneLen;

      NextDist[I] := NewS;
      NextSpeed[I] := NewV;
      NextAccel[I] := Accel;
    end;

    for I := 0 to High(FVehicles) do
    begin
      FVehicles[I].DistanceAlongLane := NextDist[I];
      FVehicles[I].SpeedMps := NextSpeed[I];
      FVehicles[I].AccelerationMps2 := NextAccel[I];
    end;
  end;

  UpdateDerivedPosesAndStats;
end;

procedure TCastleMassTrafficManager.UpdateDerivedPosesAndStats;
var
  I, J, LIdx: Integer;
  U, SumSpeed, LaneLen, DiffS, MinCenterSpacing: Single;
  Dir: TVector3;
begin
  FStats.ActiveVehicles := Length(FVehicles);
  FStats.LaneCount := Length(FLanes);
  FStats.StoppedQueueCount := 0;
  FStats.RearEndOverlapCount := 0;
  if (NorthSouthLightColor = tlcGreen) and (EastWestLightColor = tlcGreen) then
    Inc(FStats.SignalConflictCount);

  SumSpeed := 0.0;
  for I := 0 to High(FVehicles) do
  begin
    LIdx := FVehicles[I].LaneIndex;
    LaneLen := Max(1.0, FLanes[LIdx].LengthMeters);
    U := EnsureRange(FVehicles[I].DistanceAlongLane / LaneLen, 0.0, 1.0);
    Dir := (FLanes[LIdx].EndLocal - FLanes[LIdx].StartLocal).Normalize;
    FVehicles[I].ForwardDir := Dir;
    FVehicles[I].WorldOrLocalPos := Lerp(U, FLanes[LIdx].StartLocal, FLanes[LIdx].EndLocal);
    FVehicles[I].StoppedAtRed := (FVehicles[I].SpeedMps < 0.35) and (LaneLightColor(LIdx) <> tlcGreen);
    if FVehicles[I].StoppedAtRed then
      Inc(FStats.StoppedQueueCount);
    SumSpeed := SumSpeed + FVehicles[I].SpeedMps;
  end;

  if Length(FVehicles) > 0 then
    FStats.MeanSpeedMps := SumSpeed / Length(FVehicles)
  else
    FStats.MeanSpeedMps := 0.0;

  { Audit pairwise same-lane bumper clearance }
  for I := 0 to High(FVehicles) do
    for J := I + 1 to High(FVehicles) do
      if FVehicles[I].LaneIndex = FVehicles[J].LaneIndex then
      begin
        LaneLen := FLanes[FVehicles[I].LaneIndex].LengthMeters;
        DiffS := Abs(FVehicles[I].DistanceAlongLane - FVehicles[J].DistanceAlongLane);
        if DiffS > LaneLen * 0.5 then
          DiffS := LaneLen - DiffS;
        MinCenterSpacing := 0.5 * (FVehicles[I].LengthMeters + FVehicles[J].LengthMeters) - 0.05;
        if DiffS < MinCenterSpacing then
          Inc(FStats.RearEndOverlapCount);
      end;

  if FShowTrafficMesh then
    RebuildTrafficPreviewMesh;
end;

function TCastleMassTrafficManager.VehicleStateCount: Integer;
begin
  Result := Length(FVehicles);
end;

function TCastleMassTrafficManager.GetVehicleState(const AIndex: Integer): TTrafficVehicleState;
begin
  if (AIndex >= 0) and (AIndex < Length(FVehicles)) then
    Result := FVehicles[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleMassTrafficManager.GetLaneInfo(const ALaneIndex: Integer): TTrafficLaneInfo;
begin
  if (ALaneIndex >= 0) and (ALaneIndex < Length(FLanes)) then
    Result := FLanes[ALaneIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleMassTrafficManager.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientMassTrafficPreview';
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;
  FTransientScene.RenderOptions.Lighting := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  FCoordNode := TCoordinateNode.Create;
  FColorNode := TColorNode.Create;
  TriSet.Coord := FCoordNode;
  TriSet.Color := FColorNode;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);
  FTransientScene.Load(Root, True);
  Add(FTransientScene);
end;

procedure TCastleMassTrafficManager.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleMassTrafficManager.RebuildTrafficPreviewMesh;
var
  Verts, Cols: TVector3List;
  I: Integer;
  Fwd, Side, Pos, HalfFwd, HalfSide, Col: TVector3;

  function LightToRGB(const ALight: TTrafficLightColor): TVector3;
  begin
    case ALight of
      tlcGreen: Result := Vector3(0.18, 0.94, 0.36);
      tlcYellow: Result := Vector3(0.98, 0.82, 0.16);
    else
      Result := Vector3(0.96, 0.22, 0.20);
    end;
  end;

  procedure EmitFlatQuad(const A, B, C, D, QCol: TVector3);
  begin
    Verts.Add(A); Verts.Add(B); Verts.Add(C);
    Cols.Add(QCol); Cols.Add(QCol); Cols.Add(QCol);
    Verts.Add(A); Verts.Add(C); Verts.Add(D);
    Cols.Add(QCol); Cols.Add(QCol); Cols.Add(QCol);
  end;

begin
  if not FShowTrafficMesh then Exit;
  EnsureTransientScene;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    { Asphalt N-S and E-W strips }
    EmitFlatQuad(Vector3(-7.2, 0.02, -60.0), Vector3(7.2, 0.02, -60.0),
                 Vector3(7.2, 0.02, 60.0), Vector3(-7.2, 0.02, 60.0),
                 Vector3(0.18, 0.20, 0.23));
    EmitFlatQuad(Vector3(-60.0, 0.03, -7.2), Vector3(60.0, 0.03, -7.2),
                 Vector3(60.0, 0.03, 7.2), Vector3(-60.0, 0.03, 7.2),
                 Vector3(0.18, 0.20, 0.23));

    { Signal light bars on stop lines }
    Col := LightToRGB(NorthSouthLightColor);
    EmitFlatQuad(Vector3(0.5, 0.12, 8.6), Vector3(6.8, 0.12, 8.6),
                 Vector3(6.8, 0.12, 9.2), Vector3(0.5, 0.12, 9.2), Col);
    EmitFlatQuad(Vector3(-6.8, 0.12, -9.2), Vector3(-0.5, 0.12, -9.2),
                 Vector3(-0.5, 0.12, -8.6), Vector3(-6.8, 0.12, -8.6), Col);

    Col := LightToRGB(EastWestLightColor);
    EmitFlatQuad(Vector3(-9.2, 0.12, 0.5), Vector3(-8.6, 0.12, 0.5),
                 Vector3(-8.6, 0.12, 6.8), Vector3(-9.2, 0.12, 6.8), Col);
    EmitFlatQuad(Vector3(8.6, 0.12, -6.8), Vector3(9.2, 0.12, -6.8),
                 Vector3(9.2, 0.12, -0.5), Vector3(8.6, 0.12, -0.5), Col);

    { Vehicle roof boxes }
    for I := 0 to High(FVehicles) do
    begin
      Fwd := FVehicles[I].ForwardDir;
      Side := TVector3.CrossProduct(Vector3(0, 1, 0), Fwd).Normalize;
      Pos := FVehicles[I].WorldOrLocalPos + Vector3(0, 0.75, 0);
      HalfFwd := Fwd * (FVehicles[I].LengthMeters * 0.5);
      HalfSide := Side * 0.95;
      EmitFlatQuad(Pos - HalfFwd - HalfSide, Pos - HalfFwd + HalfSide,
                   Pos + HalfFwd + HalfSide, Pos + HalfFwd - HalfSide,
                   FVehicles[I].ColorRGB);
    end;

    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleMassTrafficManager.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('vehicles', FVehicleCount);
    Obj.Add('speed', FDesiredSpeedMps);
    Obj.Add('headway', FSafeTimeHeadwaySec);
    Obj.Add('greenSec', FGreenDurationSec);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleMassTrafficManager.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      PresetOrd := Obj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TMassTrafficPreset))) and
         (PresetOrd <= Ord(High(TMassTrafficPreset))) then
        FPreset := TMassTrafficPreset(PresetOrd);
      FVehicleCount := EnsureRange(Obj.Get('vehicles', FVehicleCount), 4, 80);
      FDesiredSpeedMps := EnsureRange(Obj.Get('speed', FDesiredSpeedMps), 3.0, 35.0);
      FSafeTimeHeadwaySec := EnsureRange(Obj.Get('headway', FSafeTimeHeadwaySec), 0.4, 5.0);
      FGreenDurationSec := EnsureRange(Obj.Get('greenSec', FGreenDurationSec), 2.0, 60.0);
      RebuildTrafficSimulation;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleMassTrafficManager.TrafficSummaryBadge: String;
begin
  Result := Format('[Traffic:%d cars %s Overlap=%d]', [
    FStats.ActiveVehicles,
    TrafficSignalPhaseToString(FSignalPhase),
    FStats.RearEndOverlapCount]);
end;

initialization
  RegisterSerializableComponent(TCastleMassTrafficManager, ['AI & Gameplay', 'MassTraffic Road & Signal Manager']);
end.
