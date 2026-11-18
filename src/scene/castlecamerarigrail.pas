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

{ Camera Rig Rail with closest-point Catmull-Rom auto-dolly, velocity look-ahead,
  deadzone aim framing, and 2-player co-op split/merge hysteresis (Phase 352). }
unit CastleCameraRigRail;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Built-in camera rail topology presets. }
  TCameraRailPreset = (
    crpCustom,
    crpSideScrollerCanyon,
    crpScurvedCorridorChase,
    crpBossArenaOrbitalRing
  );

  { Per-step evaluated camera rail tracking and co-op director telemetry. }
  TCameraRailResult = record
    RailParamU: Single;
    ClosestRailWorldPos: TVector3;
    RailTangentWorld: TVector3;
    PredictedFocusWorld: TVector3;
    DeadzoneAimWorld: TVector3;
    CameraWorldPos: TVector3;
    CameraForwardDir: TVector3;
    PlayerSeparationMeters: Single;
    ShouldSplitScreen: Boolean;
    EffectiveFieldOfViewDeg: Single;
  end;

  { Rail-mounted camera director matching Unreal Engine 6.0+ UCameraRigRail
    with closest-point auto-dolly, velocity look-ahead, deadzone framing, and
    hysteretic 2-player co-op FOV widening & split/merge gating. }
  TCastleCameraRigRail = class(TCastleTransform)
  private
    FPreset: TCameraRailPreset;
    FClosedLoop: Boolean;
    FAutoDollyEnabled: Boolean;
    FDollyDampingSpeed: Single;
    FLookAheadTimeSec: Single;
    FDeadzoneHalfWidthMeters: Single;
    FDeadzoneHalfHeightMeters: Single;
    FAimDampingSpeed: Single;
    FCameraRigHeightOffset: Single;
    FCoOpEnabled: Boolean;
    FSplitDistanceMeters: Single;
    FMergeDistanceMeters: Single;
    FBaseFovDeg: Single;
    FMaxCoOpFovDeg: Single;
    FShowDebugRailMesh: Boolean;
    FControlPoints: TVector3List;
    FPrimaryTarget: TCastleTransform;
    FSecondaryCoOpTarget: TCastleTransform;
    FCurrentU: Single;
    FCurrentAimWorld: TVector3;
    FAimInitialized: Boolean;
    FIsSplitScreenActive: Boolean;
    FLastResult: TCameraRailResult;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TCameraRailPreset);
    procedure SetClosedLoop(const AValue: Boolean);
    procedure SetDollyDampingSpeed(const AValue: Single);
    procedure SetLookAheadTimeSec(const AValue: Single);
    procedure SetDeadzoneHalfWidthMeters(const AValue: Single);
    procedure SetDeadzoneHalfHeightMeters(const AValue: Single);
    procedure SetAimDampingSpeed(const AValue: Single);
    procedure SetCameraRigHeightOffset(const AValue: Single);
    procedure SetSplitDistanceMeters(const AValue: Single);
    procedure SetMergeDistanceMeters(const AValue: Single);
    procedure SetBaseFovDeg(const AValue: Single);
    procedure SetMaxCoOpFovDeg(const AValue: Single);
    procedure SetShowDebugRailMesh(const AValue: Boolean);
    procedure SetPrimaryTarget(const AValue: TCastleTransform);
    procedure SetSecondaryCoOpTarget(const AValue: TCastleTransform);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
    function LocalPointToWorldSafe(const LocalPt: TVector3): TVector3;
    function LocalDirToWorldSafe(const LocalDir: TVector3): TVector3;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ApplyPresetKnotsOnly(const APreset: TCameraRailPreset);
    procedure ClearControlPoints;
    procedure AddControlPointLocal(const APt: TVector3);
    function ControlPointCount: Integer;
    function GetControlPointLocal(const AIndex: Integer): TVector3;
    function EvaluateRailLocal(const U: Single): TVector3;
    function EvaluateRailWorld(const U: Single): TVector3;
    function EvaluateRailTangentWorld(const U: Single): TVector3;
    function FindClosestRailParam(const TargetWorldPos: TVector3;
      out ClosestWorldPos: TVector3): Single;
    function SnapRigImmediate(const Target1WorldPos, Target2WorldPos: TVector3;
      const HasSecondPlayer: Boolean): TCameraRailResult;
    function EvaluateAndStepRig(const Target1WorldPos, Target1VelocityWorld,
      Target2WorldPos: TVector3; const HasSecondPlayer: Boolean;
      const Dt: Single): TCameraRailResult;
    function StepFromTargets(const Dt: Single): TCameraRailResult;
    procedure RebuildDebugMesh;
    function RailSummaryBadge: String;
    property PrimaryTarget: TCastleTransform read FPrimaryTarget write SetPrimaryTarget;
    property SecondaryCoOpTarget: TCastleTransform read FSecondaryCoOpTarget write SetSecondaryCoOpTarget;
    property LastResult: TCameraRailResult read FLastResult;
    property IsSplitScreenActive: Boolean read FIsSplitScreenActive;
  published
    property Preset: TCameraRailPreset read FPreset write SetPreset default crpSideScrollerCanyon;
    property ClosedLoop: Boolean read FClosedLoop write SetClosedLoop default False;
    property AutoDollyEnabled: Boolean read FAutoDollyEnabled write FAutoDollyEnabled default True;
    property DollyDampingSpeed: Single read FDollyDampingSpeed write SetDollyDampingSpeed {$ifdef FPC}default 8.0{$endif};
    property LookAheadTimeSec: Single read FLookAheadTimeSec write SetLookAheadTimeSec {$ifdef FPC}default 0.35{$endif};
    property DeadzoneHalfWidthMeters: Single read FDeadzoneHalfWidthMeters write SetDeadzoneHalfWidthMeters {$ifdef FPC}default 0.80{$endif};
    property DeadzoneHalfHeightMeters: Single read FDeadzoneHalfHeightMeters write SetDeadzoneHalfHeightMeters {$ifdef FPC}default 0.55{$endif};
    property AimDampingSpeed: Single read FAimDampingSpeed write SetAimDampingSpeed {$ifdef FPC}default 10.0{$endif};
    property CameraRigHeightOffset: Single read FCameraRigHeightOffset write SetCameraRigHeightOffset {$ifdef FPC}default 1.80{$endif};
    property CoOpEnabled: Boolean read FCoOpEnabled write FCoOpEnabled default False;
    property SplitDistanceMeters: Single read FSplitDistanceMeters write SetSplitDistanceMeters {$ifdef FPC}default 14.0{$endif};
    property MergeDistanceMeters: Single read FMergeDistanceMeters write SetMergeDistanceMeters {$ifdef FPC}default 10.5{$endif};
    property BaseFovDeg: Single read FBaseFovDeg write SetBaseFovDeg {$ifdef FPC}default 55.0{$endif};
    property MaxCoOpFovDeg: Single read FMaxCoOpFovDeg write SetMaxCoOpFovDeg {$ifdef FPC}default 74.0{$endif};
    property ShowDebugRailMesh: Boolean read FShowDebugRailMesh write SetShowDebugRailMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function CameraRailPresetToString(const APreset: TCameraRailPreset): String;

implementation

uses StrUtils, fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function CameraRailPresetToString(const APreset: TCameraRailPreset): String;
begin
  case APreset of
    crpCustom: Result := 'Custom Spline Rail';
    crpSideScrollerCanyon: Result := '2.5D Canyon Side-Scroller';
    crpScurvedCorridorChase: Result := 'S-Curved Corridor Chase';
    crpBossArenaOrbitalRing: Result := 'Boss Arena Closed Orbital Ring';
  end;
end;

function CatmullRomPoint(const P0, P1, P2, P3: TVector3; const T: Single): TVector3;
var
  T2, T3: Single;
begin
  T2 := T * T;
  T3 := T2 * T;
  Result :=
    ((P1 * 2.0) +
     (P2 - P0) * T +
     (P0 * 2.0 - P1 * 5.0 + P2 * 4.0 - P3) * T2 +
     (P1 * 3.0 - P0 - P2 * 3.0 + P3) * T3) * 0.5;
end;

{ TCastleCameraRigRail ------------------------------------------------------- }

constructor TCastleCameraRigRail.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FControlPoints := TVector3List.Create;
  FPreset := crpSideScrollerCanyon;
  FClosedLoop := False;
  FAutoDollyEnabled := True;
  FDollyDampingSpeed := 8.0;
  FLookAheadTimeSec := 0.35;
  FDeadzoneHalfWidthMeters := 0.80;
  FDeadzoneHalfHeightMeters := 0.55;
  FAimDampingSpeed := 10.0;
  FCameraRigHeightOffset := 1.80;
  FCoOpEnabled := False;
  FSplitDistanceMeters := 14.0;
  FMergeDistanceMeters := 10.5;
  FBaseFovDeg := 55.0;
  FMaxCoOpFovDeg := 74.0;
  FShowDebugRailMesh := True;
  FCurrentU := 0.5;
  FAimInitialized := False;
  FIsSplitScreenActive := False;
  ApplyPresetKnotsOnly(crpSideScrollerCanyon);
  SnapRigImmediate(Vector3(0, 1, 0), Vector3(2, 1, 0), False);
end;

destructor TCastleCameraRigRail.Destroy;
begin
  PrimaryTarget := nil;
  SecondaryCoOpTarget := nil;
  ClearTransientScene;
  FreeAndNil(FControlPoints);
  inherited Destroy;
end;

procedure TCastleCameraRigRail.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FPrimaryTarget then
      FPrimaryTarget := nil;
    if AComponent = FSecondaryCoOpTarget then
      FSecondaryCoOpTarget := nil;
  end;
end;

procedure TCastleCameraRigRail.SetPrimaryTarget(const AValue: TCastleTransform);
begin
  if FPrimaryTarget = AValue then Exit;
  if FPrimaryTarget <> nil then
    FPrimaryTarget.RemoveFreeNotification(Self);
  FPrimaryTarget := AValue;
  if FPrimaryTarget <> nil then
    FPrimaryTarget.FreeNotification(Self);
end;

procedure TCastleCameraRigRail.SetSecondaryCoOpTarget(const AValue: TCastleTransform);
begin
  if FSecondaryCoOpTarget = AValue then Exit;
  if FSecondaryCoOpTarget <> nil then
    FSecondaryCoOpTarget.RemoveFreeNotification(Self);
  FSecondaryCoOpTarget := AValue;
  if FSecondaryCoOpTarget <> nil then
    FSecondaryCoOpTarget.FreeNotification(Self);
end;

procedure TCastleCameraRigRail.ApplyPresetKnotsOnly(const APreset: TCameraRailPreset);
var
  I: Integer;
  Ang: Single;
begin
  FControlPoints.Clear;
  case APreset of
    crpSideScrollerCanyon, crpCustom:
      begin
        FClosedLoop := False;
        FControlPoints.Add(Vector3(-16.0, 2.2, 9.5));
        FControlPoints.Add(Vector3(-8.0, 2.6, 10.2));
        FControlPoints.Add(Vector3(0.0, 2.4, 9.5));
        FControlPoints.Add(Vector3(8.0, 2.8, 10.2));
        FControlPoints.Add(Vector3(16.0, 2.2, 9.5));
      end;
    crpScurvedCorridorChase:
      begin
        FClosedLoop := False;
        FControlPoints.Add(Vector3(-14.0, 2.5, 12.0));
        FControlPoints.Add(Vector3(-6.0, 3.0, 4.0));
        FControlPoints.Add(Vector3(2.0, 2.4, -3.5));
        FControlPoints.Add(Vector3(10.0, 3.2, -10.0));
        FControlPoints.Add(Vector3(16.0, 2.6, -16.0));
      end;
    crpBossArenaOrbitalRing:
      begin
        FClosedLoop := True;
        for I := 0 to 7 do
        begin
          Ang := (2.0 * Pi * I) / 8.0;
          FControlPoints.Add(Vector3(Cos(Ang) * 14.0, 3.2 + 0.4 * Sin(Ang * 2.0), Sin(Ang) * 14.0));
        end;
      end;
  end;
  RebuildDebugMesh;
end;

procedure TCastleCameraRigRail.SetPreset(const AValue: TCameraRailPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> crpCustom then
    ApplyPresetKnotsOnly(AValue);
end;

procedure TCastleCameraRigRail.SetClosedLoop(const AValue: Boolean);
begin
  if FClosedLoop = AValue then Exit;
  FClosedLoop := AValue;
  FPreset := crpCustom;
  RebuildDebugMesh;
end;

procedure TCastleCameraRigRail.SetDollyDampingSpeed(const AValue: Single);
begin
  FDollyDampingSpeed := Max(0.1, AValue);
end;

procedure TCastleCameraRigRail.SetLookAheadTimeSec(const AValue: Single);
begin
  FLookAheadTimeSec := EnsureRange(AValue, 0.0, 3.0);
end;

procedure TCastleCameraRigRail.SetDeadzoneHalfWidthMeters(const AValue: Single);
begin
  FDeadzoneHalfWidthMeters := Max(0.0, AValue);
end;

procedure TCastleCameraRigRail.SetDeadzoneHalfHeightMeters(const AValue: Single);
begin
  FDeadzoneHalfHeightMeters := Max(0.0, AValue);
end;

procedure TCastleCameraRigRail.SetAimDampingSpeed(const AValue: Single);
begin
  FAimDampingSpeed := Max(0.1, AValue);
end;

procedure TCastleCameraRigRail.SetCameraRigHeightOffset(const AValue: Single);
begin
  FCameraRigHeightOffset := EnsureRange(AValue, -10.0, 20.0);
  RebuildDebugMesh;
end;

procedure TCastleCameraRigRail.SetSplitDistanceMeters(const AValue: Single);
begin
  FSplitDistanceMeters := Max(1.0, AValue);
  if FMergeDistanceMeters > FSplitDistanceMeters then
    FMergeDistanceMeters := FSplitDistanceMeters * 0.75;
end;

procedure TCastleCameraRigRail.SetMergeDistanceMeters(const AValue: Single);
begin
  FMergeDistanceMeters := EnsureRange(AValue, 0.5, FSplitDistanceMeters);
end;

procedure TCastleCameraRigRail.SetBaseFovDeg(const AValue: Single);
begin
  FBaseFovDeg := EnsureRange(AValue, 20.0, 120.0);
end;

procedure TCastleCameraRigRail.SetMaxCoOpFovDeg(const AValue: Single);
begin
  FMaxCoOpFovDeg := EnsureRange(AValue, FBaseFovDeg, 130.0);
end;

procedure TCastleCameraRigRail.SetShowDebugRailMesh(const AValue: Boolean);
begin
  if FShowDebugRailMesh = AValue then Exit;
  FShowDebugRailMesh := AValue;
  if not FShowDebugRailMesh then
    ClearTransientScene
  else
    RebuildDebugMesh;
end;

procedure TCastleCameraRigRail.ClearControlPoints;
begin
  FControlPoints.Clear;
  FPreset := crpCustom;
  RebuildDebugMesh;
end;

procedure TCastleCameraRigRail.AddControlPointLocal(const APt: TVector3);
begin
  FControlPoints.Add(APt);
  FPreset := crpCustom;
  RebuildDebugMesh;
end;

function TCastleCameraRigRail.ControlPointCount: Integer;
begin
  Result := FControlPoints.Count;
end;

function TCastleCameraRigRail.GetControlPointLocal(const AIndex: Integer): TVector3;
begin
  if (AIndex >= 0) and (AIndex < FControlPoints.Count) then
    Result := FControlPoints[AIndex]
  else
    Result := TVector3.Zero;
end;

function TCastleCameraRigRail.LocalPointToWorldSafe(const LocalPt: TVector3): TVector3;
begin
  if Parent <> nil then
    Result := LocalToWorld(LocalPt)
  else
    Result := Translation + LocalPt;
end;

function TCastleCameraRigRail.LocalDirToWorldSafe(const LocalDir: TVector3): TVector3;
begin
  if Parent <> nil then
    Result := LocalToWorldDirection(LocalDir)
  else
    Result := LocalDir;
end;

function TCastleCameraRigRail.EvaluateRailLocal(const U: Single): TVector3;
var
  N, SegCount, SegIdx, I0, I1, I2, I3: Integer;
  ClampedU, Scaled, LocalT: Single;
begin
  N := FControlPoints.Count;
  if N = 0 then
    Exit(TVector3.Zero);
  if N = 1 then
    Exit(FControlPoints[0]);

  if FClosedLoop then
  begin
    ClampedU := Frac(U);
    if ClampedU < 0.0 then
      ClampedU := ClampedU + 1.0;
    SegCount := N;
    Scaled := ClampedU * SegCount;
    SegIdx := Floor(Scaled);
    if SegIdx >= SegCount then
      SegIdx := 0;
    LocalT := Scaled - SegIdx;
    I0 := (SegIdx - 1 + N) mod N;
    I1 := SegIdx mod N;
    I2 := (SegIdx + 1) mod N;
    I3 := (SegIdx + 2) mod N;
  end else
  begin
    ClampedU := EnsureRange(U, 0.0, 1.0);
    SegCount := N - 1;
    Scaled := ClampedU * SegCount;
    SegIdx := Min(SegCount - 1, Floor(Scaled));
    LocalT := Scaled - SegIdx;
    I0 := Max(0, SegIdx - 1);
    I1 := SegIdx;
    I2 := Min(N - 1, SegIdx + 1);
    I3 := Min(N - 1, SegIdx + 2);
  end;

  Result := CatmullRomPoint(FControlPoints[I0], FControlPoints[I1],
    FControlPoints[I2], FControlPoints[I3], LocalT);
end;

function TCastleCameraRigRail.EvaluateRailWorld(const U: Single): TVector3;
begin
  Result := LocalPointToWorldSafe(EvaluateRailLocal(U));
end;

function TCastleCameraRigRail.EvaluateRailTangentWorld(const U: Single): TVector3;
const
  Eps = 0.002;
var
  PMinus, PPlus, RawTan: TVector3;
begin
  if FClosedLoop then
  begin
    PMinus := EvaluateRailLocal(U - Eps);
    PPlus := EvaluateRailLocal(U + Eps);
  end else
  begin
    PMinus := EvaluateRailLocal(Max(0.0, U - Eps));
    PPlus := EvaluateRailLocal(Min(1.0, U + Eps));
  end;
  RawTan := LocalDirToWorldSafe(PPlus - PMinus);
  if RawTan.LengthSqr > 1e-8 then
    Result := RawTan.Normalize
  else
    Result := Vector3(1, 0, 0);
end;

function TCastleCameraRigRail.FindClosestRailParam(const TargetWorldPos: TVector3;
  out ClosestWorldPos: TVector3): Single;
const
  CoarseSamples = 64;
  RefineSteps = 14;
var
  I, Step: Integer;
  BestU, CandU, BestDistSqr, CandDistSqr, LeftU, RightU, Mid1, Mid2, D1, D2, Span: Single;
  Pt: TVector3;
begin
  BestU := 0.0;
  ClosestWorldPos := EvaluateRailWorld(0.0);
  BestDistSqr := PointsDistanceSqr(ClosestWorldPos, TargetWorldPos);

  for I := 1 to CoarseSamples do
  begin
    if FClosedLoop and (I = CoarseSamples) then
      Continue;
    CandU := I / CoarseSamples;
    Pt := EvaluateRailWorld(CandU);
    CandDistSqr := PointsDistanceSqr(Pt, TargetWorldPos);
    if CandDistSqr < BestDistSqr then
    begin
      BestDistSqr := CandDistSqr;
      BestU := CandU;
      ClosestWorldPos := Pt;
    end;
  end;

  Span := 1.0 / CoarseSamples;
  LeftU := BestU - Span;
  RightU := BestU + Span;
  if not FClosedLoop then
  begin
    LeftU := Max(0.0, LeftU);
    RightU := Min(1.0, RightU);
  end;

  for Step := 1 to RefineSteps do
  begin
    Mid1 := LeftU + (RightU - LeftU) / 3.0;
    Mid2 := RightU - (RightU - LeftU) / 3.0;
    D1 := PointsDistanceSqr(EvaluateRailWorld(Mid1), TargetWorldPos);
    D2 := PointsDistanceSqr(EvaluateRailWorld(Mid2), TargetWorldPos);
    if D1 < D2 then
      RightU := Mid2
    else
      LeftU := Mid1;
  end;

  BestU := (LeftU + RightU) * 0.5;
  if FClosedLoop then
  begin
    BestU := Frac(BestU);
    if BestU < 0.0 then
      BestU := BestU + 1.0;
  end else
    BestU := EnsureRange(BestU, 0.0, 1.0);

  ClosestWorldPos := EvaluateRailWorld(BestU);
  Result := BestU;
end;

function TCastleCameraRigRail.SnapRigImmediate(const Target1WorldPos, Target2WorldPos: TVector3;
  const HasSecondPlayer: Boolean): TCameraRailResult;
var
  FocusWorld, ClosestWorld: TVector3;
begin
  if FCoOpEnabled and HasSecondPlayer then
  begin
    FLastResult.PlayerSeparationMeters := PointsDistance(Target1WorldPos, Target2WorldPos);
    FIsSplitScreenActive := FLastResult.PlayerSeparationMeters > FSplitDistanceMeters;
    if FIsSplitScreenActive then
      FocusWorld := Target1WorldPos
    else
      FocusWorld := (Target1WorldPos + Target2WorldPos) * 0.5;
  end else
  begin
    FLastResult.PlayerSeparationMeters := 0.0;
    FIsSplitScreenActive := False;
    FocusWorld := Target1WorldPos;
  end;

  FCurrentU := FindClosestRailParam(FocusWorld, ClosestWorld);
  FCurrentAimWorld := FocusWorld;
  FAimInitialized := True;
  Result := EvaluateAndStepRig(Target1WorldPos, TVector3.Zero, Target2WorldPos, HasSecondPlayer, 0.0);
end;

function TCastleCameraRigRail.EvaluateAndStepRig(const Target1WorldPos, Target1VelocityWorld,
  Target2WorldPos: TVector3; const HasSecondPlayer: Boolean;
  const Dt: Single): TCameraRailResult;
var
  BaseFocus, PredictedFocus, ClosestPt, CamPos, ToTarget, RightAxis, UpAxis,
  DesiredAim, AimDelta: TVector3;
  TargetU, DeltaU, AlphaDolly, AlphaAim, OffRight, OffUp, ClampRight, ClampUp,
  CoOpRatio: Single;
begin
  if FCoOpEnabled and HasSecondPlayer then
  begin
    Result.PlayerSeparationMeters := PointsDistance(Target1WorldPos, Target2WorldPos);
    if FIsSplitScreenActive then
    begin
      if Result.PlayerSeparationMeters < FMergeDistanceMeters then
        FIsSplitScreenActive := False;
    end else
    begin
      if Result.PlayerSeparationMeters > FSplitDistanceMeters then
        FIsSplitScreenActive := True;
    end;
    Result.ShouldSplitScreen := FIsSplitScreenActive;

    if FIsSplitScreenActive then
    begin
      BaseFocus := Target1WorldPos;
      Result.EffectiveFieldOfViewDeg := FBaseFovDeg;
    end else
    begin
      BaseFocus := (Target1WorldPos + Target2WorldPos) * 0.5;
      CoOpRatio := EnsureRange(Result.PlayerSeparationMeters / Max(0.01, FSplitDistanceMeters), 0.0, 1.0);
      Result.EffectiveFieldOfViewDeg := Lerp(CoOpRatio, FBaseFovDeg, FMaxCoOpFovDeg);
    end;
  end else
  begin
    Result.PlayerSeparationMeters := 0.0;
    FIsSplitScreenActive := False;
    Result.ShouldSplitScreen := False;
    BaseFocus := Target1WorldPos;
    Result.EffectiveFieldOfViewDeg := FBaseFovDeg;
  end;

  PredictedFocus := BaseFocus + Target1VelocityWorld * FLookAheadTimeSec;
  Result.PredictedFocusWorld := PredictedFocus;

  if FAutoDollyEnabled then
  begin
    TargetU := FindClosestRailParam(PredictedFocus, ClosestPt);
    if Dt <= 0.0 then
      FCurrentU := TargetU
    else
    begin
      AlphaDolly := 1.0 - Exp(-FDollyDampingSpeed * Dt);
      if FClosedLoop then
      begin
        DeltaU := TargetU - FCurrentU;
        if DeltaU > 0.5 then DeltaU := DeltaU - 1.0
        else if DeltaU < -0.5 then DeltaU := DeltaU + 1.0;
        FCurrentU := Frac(FCurrentU + DeltaU * AlphaDolly);
        if FCurrentU < 0.0 then
          FCurrentU := FCurrentU + 1.0;
      end else
        FCurrentU := Lerp(AlphaDolly, FCurrentU, TargetU);
    end;
  end;

  Result.RailParamU := FCurrentU;
  Result.ClosestRailWorldPos := EvaluateRailWorld(FCurrentU);
  Result.RailTangentWorld := EvaluateRailTangentWorld(FCurrentU);
  CamPos := Result.ClosestRailWorldPos + Vector3(0, FCameraRigHeightOffset, 0);
  Result.CameraWorldPos := CamPos;

  if not FAimInitialized then
  begin
    FCurrentAimWorld := PredictedFocus;
    FAimInitialized := True;
  end;

  ToTarget := FCurrentAimWorld - CamPos;
  if ToTarget.LengthSqr < 1e-6 then
    ToTarget := Vector3(0, 0, -1)
  else
    ToTarget := ToTarget.Normalize;

  RightAxis := TVector3.CrossProduct(ToTarget, Vector3(0, 1, 0));
  if RightAxis.LengthSqr < 1e-6 then
    RightAxis := Vector3(1, 0, 0)
  else
    RightAxis := RightAxis.Normalize;
  UpAxis := TVector3.CrossProduct(RightAxis, ToTarget).Normalize;

  AimDelta := PredictedFocus - FCurrentAimWorld;
  OffRight := TVector3.DotProduct(AimDelta, RightAxis);
  OffUp := TVector3.DotProduct(AimDelta, UpAxis);

  if Abs(OffRight) <= FDeadzoneHalfWidthMeters then
    ClampRight := 0.0
  else if OffRight > 0.0 then
    ClampRight := OffRight - FDeadzoneHalfWidthMeters
  else
    ClampRight := OffRight + FDeadzoneHalfWidthMeters;

  if Abs(OffUp) <= FDeadzoneHalfHeightMeters then
    ClampUp := 0.0
  else if OffUp > 0.0 then
    ClampUp := OffUp - FDeadzoneHalfHeightMeters
  else
    ClampUp := OffUp + FDeadzoneHalfHeightMeters;

  DesiredAim := FCurrentAimWorld + RightAxis * ClampRight + UpAxis * ClampUp +
    ToTarget * TVector3.DotProduct(AimDelta, ToTarget);

  if (Abs(ClampRight) < 1e-6) and (Abs(ClampUp) < 1e-6) then
  begin
    { Inside deadzone: hold exact aim point so micro-movements cause zero rotation jitter }
  end else if Dt <= 0.0 then
    FCurrentAimWorld := DesiredAim
  else
  begin
    AlphaAim := 1.0 - Exp(-FAimDampingSpeed * Dt);
    FCurrentAimWorld := Lerp(AlphaAim, FCurrentAimWorld, DesiredAim);
  end;

  Result.DeadzoneAimWorld := FCurrentAimWorld;
  if (FCurrentAimWorld - CamPos).LengthSqr > 1e-6 then
    Result.CameraForwardDir := (FCurrentAimWorld - CamPos).Normalize
  else
    Result.CameraForwardDir := Vector3(0, 0, -1);

  FLastResult := Result;
  if FShowDebugRailMesh then
    RebuildDebugMesh;
end;

function TCastleCameraRigRail.StepFromTargets(const Dt: Single): TCameraRailResult;
var
  P1, P2: TVector3;
  HasP2: Boolean;
begin
  if FPrimaryTarget <> nil then
    P1 := FPrimaryTarget.WorldTranslation
  else
    P1 := TVector3.Zero;

  HasP2 := FSecondaryCoOpTarget <> nil;
  if HasP2 then
    P2 := FSecondaryCoOpTarget.WorldTranslation
  else
    P2 := P1;

  Result := EvaluateAndStepRig(P1, TVector3.Zero, P2, HasP2, Dt);
end;

procedure TCastleCameraRigRail.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientCameraRailPreview';
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;
  FTransientScene.CastShadows := False;
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

procedure TCastleCameraRigRail.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleCameraRigRail.RebuildDebugMesh;
const
  RailSegments = 36;
  HalfRibbonWidth = 0.14;
var
  Verts, Cols: TVector3List;
  I: Integer;
  U0, U1: Single;
  P0, P1, SideVec, CarriageLocal, Apex, B1, B2, B3: TVector3;
  RailCol, CarriageCol: TVector3;
begin
  if not FShowDebugRailMesh then Exit;
  if FControlPoints.Count < 2 then Exit;
  EnsureTransientScene;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    RailCol := Vector3(0.20, 0.85, 0.98);
    SideVec := Vector3(0, HalfRibbonWidth, 0);
    for I := 0 to RailSegments - 1 do
    begin
      U0 := I / RailSegments;
      U1 := (I + 1) / RailSegments;
      P0 := EvaluateRailLocal(U0);
      P1 := EvaluateRailLocal(U1);
      Verts.Add(P0 - SideVec); Verts.Add(P0 + SideVec); Verts.Add(P1 + SideVec);
      Cols.Add(RailCol); Cols.Add(RailCol); Cols.Add(RailCol);
      Verts.Add(P0 - SideVec); Verts.Add(P1 + SideVec); Verts.Add(P1 - SideVec);
      Cols.Add(RailCol); Cols.Add(RailCol); Cols.Add(RailCol);
    end;

    CarriageLocal := EvaluateRailLocal(FCurrentU) + Vector3(0, FCameraRigHeightOffset, 0);
    if FIsSplitScreenActive then
      CarriageCol := Vector3(1.0, 0.42, 0.25)
    else
      CarriageCol := Vector3(1.0, 0.84, 0.20);
    Apex := CarriageLocal + Vector3(0, 0.35, 0);
    B1 := CarriageLocal + Vector3(-0.28, -0.20, 0.25);
    B2 := CarriageLocal + Vector3(0.28, -0.20, 0.25);
    B3 := CarriageLocal + Vector3(0.0, -0.20, -0.32);

    Verts.Add(Apex); Verts.Add(B1); Verts.Add(B2);
    Cols.Add(CarriageCol); Cols.Add(CarriageCol); Cols.Add(CarriageCol);
    Verts.Add(Apex); Verts.Add(B2); Verts.Add(B3);
    Cols.Add(CarriageCol); Cols.Add(CarriageCol); Cols.Add(CarriageCol);
    Verts.Add(Apex); Verts.Add(B3); Verts.Add(B1);
    Cols.Add(CarriageCol); Cols.Add(CarriageCol); Cols.Add(CarriageCol);

    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleCameraRigRail.GetConfigJson: String;
var
  RootObj, PtObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  Pt: TVector3;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('closedLoop', FClosedLoop);
    Arr := TJSONArray.Create;
    for I := 0 to FControlPoints.Count - 1 do
    begin
      Pt := FControlPoints[I];
      PtObj := TJSONObject.Create;
      PtObj.Add('x', Pt.X);
      PtObj.Add('y', Pt.Y);
      PtObj.Add('z', Pt.Z);
      Arr.Add(PtObj);
    end;
    RootObj.Add('knots', Arr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleCameraRigRail.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, PtObj: TJSONObject;
  Arr: TJSONArray;
  I, PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TCameraRailPreset))) and
         (PresetOrd <= Ord(High(TCameraRailPreset))) then
        FPreset := TCameraRailPreset(PresetOrd);
      FClosedLoop := RootObj.Get('closedLoop', FClosedLoop);
      Arr := RootObj.Find('knots', jtArray) as TJSONArray;
      if (Arr <> nil) and (Arr.Count > 0) then
      begin
        FControlPoints.Clear;
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            PtObj := TJSONObject(Arr.Items[I]);
            FControlPoints.Add(Vector3(
              PtObj.Get('x', 0.0),
              PtObj.Get('y', 0.0),
              PtObj.Get('z', 0.0)));
          end;
      end;
      RebuildDebugMesh;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleCameraRigRail.RailSummaryBadge: String;
begin
  Result := Format('[CamRail:u=%.2f FOV=%.0fd %s]', [
    FLastResult.RailParamU,
    FLastResult.EffectiveFieldOfViewDeg,
    IfThen(FLastResult.ShouldSplitScreen, 'SPLIT-2P', 'SINGLE')]);
end;

initialization
  RegisterSerializableComponent(TCastleCameraRigRail, ['Camera', 'Camera Rig Rail (Auto-Dolly & Co-Op)']);
end.
