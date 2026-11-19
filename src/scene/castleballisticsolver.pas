{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Sub-stepped external and terminal ballistics solver with quadratic aerodynamic
  drag, crosswind drift, Magnus spin lift, WorldRay grazing ricochet, thin-cover
  exit penetration, moving-target intercept lead solver, and transient 3D tracer
  visualization (Phase 387). }
unit CastleBallisticSolver;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleColors, X3DNodes;

type
  { Preset ballistic profiles for rifles, mortars, and archery projectiles. }
  TBallisticPreset = (
    blpSniper762Supersonic,
    blpMortarHighArcHE,
    blpRecurveLongbowArrow
  );

  { Terminal outcome at a trajectory sample or final impact event. }
  TBallisticImpactOutcome = (
    bioInFlightOrExpired,
    bioEmbeddedStop,
    bioGrazingRicochet,
    bioThinCoverPenetrated
  );

  { Sampled state along a simulated ballistic trajectory. }
  TBallisticSamplePoint = record
    TimeSec: Single;
    WorldPos: TVector3;
    WorldVel: TVector3;
    SpeedMps: Single;
    KineticEnergyJoules: Single;
    EventKind: TBallisticImpactOutcome;
  end;

  { Complete trace report returned by TCastleBallisticLauncher.SimulateTrajectory. }
  TBallisticTraceResult = record
    SampleCount: Integer;
    Samples: array of TBallisticSamplePoint;
    ImpactCount: Integer;
    RicochetCount: Integer;
    PenetrationCount: Integer;
    FinalOutcome: TBallisticImpactOutcome;
    MaxApexY: Single;
    HorizontalRangeMeters: Single;
    LateralWindSpinDriftMeters: Single;
    TerminalSpeedMps: Single;
    FirstImpactPoint: TVector3;
    FirstImpactNormal: TVector3;
    FirstImpactItemName: String;
  end;

  { Scene transform that simulates external and terminal projectile ballistics
    against live CGE WorldRay geometry and renders a transient 3D tracer arc. }
  TCastleBallisticLauncher = class(TCastleTransform)
  private
    FPreset: TBallisticPreset;
    FMuzzleSpeedMps: Single;
    FProjectileMassKg: Single;
    FDragCoefficient: Single;
    FCrossSectionAreaM2: Single;
    FAirDensityKgM3: Single;
    FGravityMps2: Single;
    FSpinRateRps: Single;
    FMagnusLiftFactor: Single;
    FRicochetMaxGrazingDeg: Single;
    FRicochetRestitution: Single;
    FPenetrationBallisticLimitMps: Single;
    FMaxPenetrationThicknessMeters: Single;
    FMaxSimTimeSec: Single;
    FSubStepDtSec: Single;
    FWindVelocityMps: TVector3;
    FWindVelocityPersistent: TCastleVector3Persistent;
    FShowPreview: Boolean;
    FLastTrace: TBallisticTraceResult;
    FPreviewRoot: TCastleTransform;
    FPreviewScene: TCastleScene;
    procedure SetPreset(const AValue: TBallisticPreset);
    procedure SetShowPreview(const AValue: Boolean);
    function GetWindVelocityForPersistent: TVector3;
    procedure SetWindVelocityForPersistent(const AValue: TVector3);
    procedure EnsurePreviewNodes;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Apply realistic physical defaults for the chosen weapon/projectile preset. }
    procedure ApplyPreset(const APreset: TBallisticPreset);

    { Simulate a sub-stepped trajectory from ALaunchOrigin along ALaunchDirection,
      resolving quadratic drag, crosswind, Magnus spin, grazing ricochets, and
      thin-cover penetrations against AWorldRoot. }
    function SimulateTrajectory(const AWorldRoot: TCastleAbstractRootTransform;
      const ALaunchOrigin, ALaunchDirection: TVector3): TBallisticTraceResult;

    { Simulate from Self world position along local -Z forward axis and update
      the transient 3D tracer preview. }
    function SimulateFromTransform(
      const AWorldRoot: TCastleAbstractRootTransform): TBallisticTraceResult;

    { Compute launch elevation angle (degrees above horizontal) and predicted
      intercept point to hit a moving target at ATargetPos + ATargetVel * t. }
    function SolveInterceptElevationDeg(
      const ALaunchOrigin, ATargetPos, ATargetVel: TVector3;
      const AHighArc: Boolean;
      out AElevationDeg: Single;
      out AInterceptLeadPos: TVector3): Boolean;

    procedure RebuildPreview;
    procedure ClearPreview;
    function BallisticSummaryBadge: String;

    property WindVelocityMps: TVector3 read FWindVelocityMps write FWindVelocityMps;
    property LastTrace: TBallisticTraceResult read FLastTrace;
  published
    property Preset: TBallisticPreset
      read FPreset write SetPreset default blpSniper762Supersonic;
    property MuzzleSpeedMps: Single read FMuzzleSpeedMps write FMuzzleSpeedMps;
    property ProjectileMassKg: Single read FProjectileMassKg write FProjectileMassKg;
    property DragCoefficient: Single read FDragCoefficient write FDragCoefficient;
    property CrossSectionAreaM2: Single read FCrossSectionAreaM2 write FCrossSectionAreaM2;
    property AirDensityKgM3: Single read FAirDensityKgM3 write FAirDensityKgM3;
    property GravityMps2: Single read FGravityMps2 write FGravityMps2;
    property SpinRateRps: Single read FSpinRateRps write FSpinRateRps;
    property MagnusLiftFactor: Single read FMagnusLiftFactor write FMagnusLiftFactor;
    property RicochetMaxGrazingDeg: Single
      read FRicochetMaxGrazingDeg write FRicochetMaxGrazingDeg;
    property RicochetRestitution: Single
      read FRicochetRestitution write FRicochetRestitution;
    property PenetrationBallisticLimitMps: Single
      read FPenetrationBallisticLimitMps write FPenetrationBallisticLimitMps;
    property MaxPenetrationThicknessMeters: Single
      read FMaxPenetrationThicknessMeters write FMaxPenetrationThicknessMeters;
    property MaxSimTimeSec: Single read FMaxSimTimeSec write FMaxSimTimeSec;
    property SubStepDtSec: Single read FSubStepDtSec write FSubStepDtSec;
    property WindVelocityPersistent: TCastleVector3Persistent
      read FWindVelocityPersistent;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function BallisticPresetToString(const APreset: TBallisticPreset): String;
function BallisticOutcomeToString(const AOutcome: TBallisticImpactOutcome): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function BallisticPresetToString(const APreset: TBallisticPreset): String;
begin
  case APreset of
    blpSniper762Supersonic: Result := 'Sniper762Supersonic';
    blpMortarHighArcHE:     Result := 'MortarHighArcHE';
    blpRecurveLongbowArrow: Result := 'RecurveLongbowArrow';
  end;
end;

function BallisticOutcomeToString(const AOutcome: TBallisticImpactOutcome): String;
begin
  case AOutcome of
    bioInFlightOrExpired:   Result := 'InFlightOrExpired';
    bioEmbeddedStop:        Result := 'EmbeddedStop';
    bioGrazingRicochet:     Result := 'GrazingRicochet';
    bioThinCoverPenetrated: Result := 'ThinCoverPenetrated';
  end;
end;

function ExtractWorldSurfaceNormal(const ARayNode: TRayCollisionNode;
  const ARayDirNorm: TVector3): TVector3;
var
  HitItem: TCastleTransform;
  LocalPt, LocalMin, LocalMax, LocalCenter, HalfExt, Rel: TVector3;
  NX, NY, NZ: Single;
  InvWT: TMatrix4;
begin
  Result := -ARayDirNorm;
  HitItem := ARayNode.Item;
  if HitItem = nil then
    Exit;

  if (ARayNode.Triangle <> nil) and HitItem.HasWorldTransform then
  begin
    Result := HitItem.LocalToWorldDirection(ARayNode.Triangle^.SceneSpace.Normal);
    if Result.LengthSqr > 1e-8 then
    begin
      Result := Result.Normalize;
      if TVector3.DotProduct(Result, ARayDirNorm) > 0.0 then
        Result := -Result;
      Exit;
    end;
  end;

  { Analytic local AABB face-normal fallback for box/primitive colliders }
  if not HitItem.LocalBoundingBox.IsEmpty then
  begin
    if HitItem.HasWorldTransform then
      InvWT := HitItem.WorldInverseTransform
    else if not HitItem.Transform.TryInverse(InvWT) then
      InvWT := TMatrix4.Identity;
    LocalPt := InvWT.MultPoint(ARayNode.Point);
    LocalMin := HitItem.LocalBoundingBox.Data[0];
    LocalMax := HitItem.LocalBoundingBox.Data[1];
    LocalCenter := (LocalMin + LocalMax) * 0.5;
    HalfExt := (LocalMax - LocalMin) * 0.5;
    Rel := LocalPt - LocalCenter;
    NX := Abs(Rel.X) / Max(0.0001, HalfExt.X);
    NY := Abs(Rel.Y) / Max(0.0001, HalfExt.Y);
    NZ := Abs(Rel.Z) / Max(0.0001, HalfExt.Z);
    if (NX >= NY) and (NX >= NZ) then
      Result := Vector3(Sign(Rel.X), 0.0, 0.0)
    else if (NY >= NX) and (NY >= NZ) then
      Result := Vector3(0.0, Sign(Rel.Y), 0.0)
    else
      Result := Vector3(0.0, 0.0, Sign(Rel.Z));
    if HitItem.HasWorldTransform then
      Result := HitItem.LocalToWorldDirection(Result)
    else
      Result := HitItem.Transform.MultDirection(Result);
    if Result.LengthSqr > 1e-8 then
      Result := Result.Normalize
    else
      Result := -ARayDirNorm;
    if TVector3.DotProduct(Result, ARayDirNorm) > 0.0 then
      Result := -Result;
  end;
end;

{ TCastleBallisticLauncher --------------------------------------------------- }

constructor TCastleBallisticLauncher.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWindVelocityMps := Vector3(0.0, 0.0, 0.0);
  FWindVelocityPersistent := TCastleVector3Persistent.Create(nil);
  FWindVelocityPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetWindVelocityForPersistent;
  FWindVelocityPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetWindVelocityForPersistent;
  FWindVelocityPersistent.InternalDefaultValue := Vector3(0.0, 0.0, 0.0);
  FShowPreview := True;
  FLastTrace := Default(TBallisticTraceResult);
  ApplyPreset(blpSniper762Supersonic);
end;

destructor TCastleBallisticLauncher.Destroy;
begin
  ClearPreview;
  FreeAndNil(FWindVelocityPersistent);
  inherited Destroy;
end;

function TCastleBallisticLauncher.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'MuzzleSpeedMps', 'ProjectileMassKg', 'DragCoefficient',
       'CrossSectionAreaM2', 'AirDensityKgM3', 'GravityMps2',
       'SpinRateRps', 'MagnusLiftFactor', 'RicochetMaxGrazingDeg',
       'RicochetRestitution', 'PenetrationBallisticLimitMps',
       'MaxPenetrationThicknessMeters', 'MaxSimTimeSec', 'SubStepDtSec',
       'WindVelocityPersistent', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleBallisticLauncher.GetWindVelocityForPersistent: TVector3;
begin
  Result := FWindVelocityMps;
end;

procedure TCastleBallisticLauncher.SetWindVelocityForPersistent(
  const AValue: TVector3);
begin
  FWindVelocityMps := AValue;
end;

procedure TCastleBallisticLauncher.SetPreset(const AValue: TBallisticPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleBallisticLauncher.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleBallisticLauncher.ApplyPreset(const APreset: TBallisticPreset);
begin
  FPreset := APreset;
  FAirDensityKgM3 := 1.225;
  FGravityMps2 := 9.81;
  case APreset of
    blpSniper762Supersonic:
      begin
        FMuzzleSpeedMps := 820.0;
        FProjectileMassKg := 0.010;
        FDragCoefficient := 0.295;
        FCrossSectionAreaM2 := 0.000048;
        FSpinRateRps := 2400.0;
        FMagnusLiftFactor := 0.000002;
        FRicochetMaxGrazingDeg := 22.0;
        FRicochetRestitution := 0.68;
        FPenetrationBallisticLimitMps := 260.0;
        FMaxPenetrationThicknessMeters := 0.45;
        FMaxSimTimeSec := 2.5;
        FSubStepDtSec := 0.002;
      end;
    blpMortarHighArcHE:
      begin
        FMuzzleSpeedMps := 68.0;
        FProjectileMassKg := 4.20;
        FDragCoefficient := 0.42;
        FCrossSectionAreaM2 := 0.0052;
        FSpinRateRps := 18.0;
        FMagnusLiftFactor := 0.000010;
        FRicochetMaxGrazingDeg := 8.0;
        FRicochetRestitution := 0.30;
        FPenetrationBallisticLimitMps := 950.0;
        FMaxPenetrationThicknessMeters := 0.15;
        FMaxSimTimeSec := 10.0;
        FSubStepDtSec := 0.015;
      end;
    blpRecurveLongbowArrow:
      begin
        FMuzzleSpeedMps := 62.0;
        FProjectileMassKg := 0.028;
        FDragCoefficient := 0.85;
        FCrossSectionAreaM2 := 0.00012;
        FSpinRateRps := 35.0;
        FMagnusLiftFactor := 0.000012;
        FRicochetMaxGrazingDeg := 14.0;
        FRicochetRestitution := 0.42;
        FPenetrationBallisticLimitMps := 140.0;
        FMaxPenetrationThicknessMeters := 0.08;
        FMaxSimTimeSec := 5.0;
        FSubStepDtSec := 0.010;
      end;
  end;
end;

function TCastleBallisticLauncher.SimulateTrajectory(
  const AWorldRoot: TCastleAbstractRootTransform;
  const ALaunchOrigin, ALaunchDirection: TVector3): TBallisticTraceResult;
var
  LaunchDir, HorizForward, HorizRight, SpinAxis: TVector3;
  CurPos, CurVel, NextPos, RelAirVel, Accel, DragAcc, MagnusAcc: TVector3;
  SegVec, SegDir, HitPt, HitNorm,VnVec, VtVec, ProbeBackOrigin, ExitPt: TVector3;
  Dt, SimT, MaxT, MassSafe, SpeedNow, RelSpeed, SegLen: Single;
  SinGraze, GrazingDeg, ResidualSq, ExitSpeed, CoverThick: Single;
  MaxSteps, StepIdx, StrideRecord, K: Integer;
  BackHit: TRayCollision;
  HitItem, FoundItem: TCastleTransform;
  FoundDist: Single;
  FoundNode: TRayCollisionNode;
  DidPenetrate: Boolean;

  procedure AppendSample(const T: Single; const P, V: TVector3;
    const Ev: TBallisticImpactOutcome);
  var
    Idx: Integer;
    Spd: Single;
  begin
    Idx := Result.SampleCount;
    Inc(Result.SampleCount);
    if Idx >= Length(Result.Samples) then
      SetLength(Result.Samples, Max(64, Length(Result.Samples) * 2));
    Spd := V.Length;
    Result.Samples[Idx].TimeSec := T;
    Result.Samples[Idx].WorldPos := P;
    Result.Samples[Idx].WorldVel := V;
    Result.Samples[Idx].SpeedMps := Spd;
    Result.Samples[Idx].KineticEnergyJoules := 0.5 * MassSafe * Spd * Spd;
    Result.Samples[Idx].EventKind := Ev;
    if P.Y > Result.MaxApexY then
      Result.MaxApexY := P.Y;
  end;

  function FindFirstSolidHit(const AOrig, ADir: TVector3; const AMaxLen: Single;
    out ANode: TRayCollisionNode; out ADist: Single): Boolean;
  var
    RH: TRayCollision;
    J: Integer;
    Candidate: TCastleTransform;
    D: Single;
  begin
    Result := False;
    ADist := AMaxLen + 1.0;
    ANode := Default(TRayCollisionNode);
    if AWorldRoot = nil then Exit;
    RH := AWorldRoot.WorldRay(AOrig, ADir);
    try
      if RH = nil then Exit;
      for J := 0 to RH.Count - 1 do
      begin
        Candidate := RH[J].Item;
        if (Candidate = nil) or (Candidate = AWorldRoot) or (Candidate = Self) then
          Continue;
        if csTransient in Candidate.ComponentStyle then
          Continue;
        D := PointsDistance(AOrig, RH[J].Point);
        if (D >= 1e-4) and (D <= AMaxLen + 1e-4) and (D < ADist) then
        begin
          ADist := D;
          ANode := RH[J];
          Result := True;
        end;
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

begin
  Result := Default(TBallisticTraceResult);
  Result.FinalOutcome := bioInFlightOrExpired;
  Result.MaxApexY := ALaunchOrigin.Y;

  if ALaunchDirection.LengthSqr < 1e-8 then
    LaunchDir := Vector3(0.0, 0.0, -1.0)
  else
    LaunchDir := ALaunchDirection.Normalize;

  HorizForward := Vector3(LaunchDir.X, 0.0, LaunchDir.Z);
  if HorizForward.LengthSqr < 1e-6 then
    HorizForward := Vector3(0.0, 0.0, -1.0)
  else
    HorizForward := HorizForward.Normalize;
  HorizRight := TVector3.CrossProduct(HorizForward, Vector3(0.0, 1.0, 0.0));
  if HorizRight.LengthSqr < 1e-6 then
    HorizRight := Vector3(1.0, 0.0, 0.0)
  else
    HorizRight := HorizRight.Normalize;

  MassSafe := Max(0.0005, FProjectileMassKg);
  Dt := Clamped(FSubStepDtSec, 0.0005, 0.05);
  MaxT := Clamped(FMaxSimTimeSec, Dt, 30.0);
  MaxSteps := Min(6000, Max(1, Round(MaxT / Dt)));
  StrideRecord := Max(1, MaxSteps div 96);

  CurPos := ALaunchOrigin;
  CurVel := LaunchDir * Max(0.1, FMuzzleSpeedMps);
  SimT := 0.0;
  SetLength(Result.Samples, 128);
  AppendSample(0.0, CurPos, CurVel, bioInFlightOrExpired);

  BackHit := nil;
  for StepIdx := 1 to MaxSteps do
  begin
    SpeedNow := CurVel.Length;
    if SpeedNow < 0.25 then
    begin
      Result.FinalOutcome := bioEmbeddedStop;
      Break;
    end;

    { Relative velocity with respect to ambient wind }
    RelAirVel := CurVel - FWindVelocityMps;
    RelSpeed := RelAirVel.Length;
    if (RelSpeed > 1e-4) and (FAirDensityKgM3 > 0.0) and (FDragCoefficient > 0.0) then
      DragAcc := -RelAirVel * (0.5 * FAirDensityKgM3 * FDragCoefficient *
        Max(1e-7, FCrossSectionAreaM2) * RelSpeed / MassSafe)
    else
      DragAcc := TVector3.Zero;

    { Spin-induced Magnus acceleration (spin axis along vertical/right gyroscope) }
    if (Abs(FSpinRateRps) > 1e-3) and (Abs(FMagnusLiftFactor) > 1e-9) and
       (RelSpeed > 1e-3) then
    begin
      SpinAxis := Vector3(0.0, 1.0, 0.0);
      MagnusAcc := TVector3.CrossProduct(SpinAxis * FSpinRateRps, RelAirVel) *
        FMagnusLiftFactor;
    end else
      MagnusAcc := TVector3.Zero;

    Accel := Vector3(0.0, -FGravityMps2, 0.0) + DragAcc + MagnusAcc;
    { Velocity-Verlet midpoint integration }
    NextPos := CurPos + CurVel * Dt + Accel * (0.5 * Dt * Dt);
    CurVel := CurVel + Accel * Dt;
    SimT := SimT + Dt;

    { Segment WorldRay terminal ballistics test }
    SegVec := NextPos - CurPos;
    SegLen := SegVec.Length;
    if (AWorldRoot <> nil) and (SegLen > 1e-5) then
    begin
      SegDir := SegVec / SegLen;
      if FindFirstSolidHit(CurPos, SegDir, SegLen, FoundNode, FoundDist) then
      begin
        HitItem := FoundNode.Item;
        HitPt := FoundNode.Point;
        HitNorm := ExtractWorldSurfaceNormal(FoundNode, SegDir);
        Inc(Result.ImpactCount);
        if Result.ImpactCount = 1 then
        begin
          Result.FirstImpactPoint := HitPt;
          Result.FirstImpactNormal := HitNorm;
          if HitItem <> nil then
            Result.FirstImpactItemName := HitItem.Name;
        end;

        SpeedNow := CurVel.Length;
        SinGraze := Clamped(Abs(TVector3.DotProduct(SegDir, HitNorm)), 0.0, 1.0);
        GrazingDeg := RadToDeg(ArcSin(SinGraze));

        { 1. Grazing Ricochet check }
        if (GrazingDeg <= FRicochetMaxGrazingDeg) and (Result.RicochetCount < 4) then
        begin
          VnVec := HitNorm * TVector3.DotProduct(CurVel, HitNorm);
          VtVec := CurVel - VnVec;
          CurVel := VtVec * Clamped(0.92, 0.1, 1.0) -
            VnVec * Clamped(FRicochetRestitution, 0.05, 0.98);
          CurPos := HitPt + HitNorm * 0.015;
          Inc(Result.RicochetCount);
          Result.FinalOutcome := bioGrazingRicochet;
          AppendSample(SimT, CurPos, CurVel, bioGrazingRicochet);
          Continue;
        end;

        { 2. Thin-Cover Penetration check via reverse raycast from far side }
        DidPenetrate := False;
        if (SpeedNow > FPenetrationBallisticLimitMps) and
           (FMaxPenetrationThicknessMeters > 0.01) and
           (Result.PenetrationCount < 4) and (HitItem <> nil) then
        begin
          ProbeBackOrigin := HitPt + SegDir * (FMaxPenetrationThicknessMeters + 0.05);
          BackHit := AWorldRoot.WorldRay(ProbeBackOrigin, -SegDir);
          try
            if BackHit <> nil then
              for K := 0 to BackHit.Count - 1 do
              begin
                FoundItem := BackHit[K].Item;
                if FoundItem = HitItem then
                begin
                  ExitPt := BackHit[K].Point;
                  CoverThick := PointsDistance(HitPt, ExitPt);
                  if (CoverThick >= 0.005) and
                     (CoverThick <= FMaxPenetrationThicknessMeters + 0.02) then
                  begin
                    ResidualSq := Sqr(SpeedNow) -
                      Sqr(FPenetrationBallisticLimitMps) *
                      Clamped(CoverThick / Max(0.05, FMaxPenetrationThicknessMeters), 0.25, 1.5);
                    if ResidualSq > 4.0 then
                    begin
                      ExitSpeed := Sqrt(ResidualSq);
                      CurPos := ExitPt + SegDir * 0.02;
                      CurVel := SegDir * ExitSpeed;
                      Inc(Result.PenetrationCount);
                      Result.FinalOutcome := bioThinCoverPenetrated;
                      AppendSample(SimT, CurPos, CurVel, bioThinCoverPenetrated);
                      DidPenetrate := True;
                    end;
                  end;
                  Break;
                end;
              end;
          finally
            FreeAndNil(BackHit);
          end;
        end;

        if DidPenetrate then
          Continue;

        { 3. Projectile embeds and stops }
        CurPos := HitPt;
        Result.FinalOutcome := bioEmbeddedStop;
        AppendSample(SimT, CurPos, CurVel, bioEmbeddedStop);
        Break;
      end;
    end;

    CurPos := NextPos;
    if (StepIdx mod StrideRecord = 0) or (StepIdx = MaxSteps) then
      AppendSample(SimT, CurPos, CurVel, bioInFlightOrExpired);
  end;

  SetLength(Result.Samples, Result.SampleCount);
  Result.TerminalSpeedMps := CurVel.Length;
  Result.HorizontalRangeMeters := Hypot(
    CurPos.X - ALaunchOrigin.X, CurPos.Z - ALaunchOrigin.Z);
  Result.LateralWindSpinDriftMeters := TVector3.DotProduct(
    CurPos - ALaunchOrigin, HorizRight);
  FLastTrace := Result;
end;

function TCastleBallisticLauncher.SimulateFromTransform(
  const AWorldRoot: TCastleAbstractRootTransform): TBallisticTraceResult;
var
  WT: TMatrix4;
  Orig, Fwd: TVector3;
begin
  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;
  Orig := WT.MultPoint(TVector3.Zero);
  Fwd := WT.MultDirection(Vector3(0.0, 0.0, -1.0));
  if Fwd.LengthSqr < 1e-8 then
    Fwd := Vector3(0.0, 0.0, -1.0)
  else
    Fwd := Fwd.Normalize;
  Result := SimulateTrajectory(AWorldRoot, Orig, Fwd);
  if FShowPreview then
    RebuildPreview;
end;

function TCastleBallisticLauncher.SolveInterceptElevationDeg(
  const ALaunchOrigin, ATargetPos, ATargetVel: TVector3;
  const AHighArc: Boolean;
  out AElevationDeg: Single;
  out AInterceptLeadPos: TVector3): Boolean;
var
  Iter: Integer;
  FlightT, V0, G, DX, DY, DZ, HorizDist, Disc, TanTheta: Single;
  LeadPos: TVector3;
begin
  Result := False;
  AElevationDeg := 0.0;
  AInterceptLeadPos := ATargetPos;
  V0 := Max(1.0, FMuzzleSpeedMps);
  G := Max(0.01, FGravityMps2);

  FlightT := PointsDistance(ALaunchOrigin, ATargetPos) / V0;
  for Iter := 0 to 7 do
  begin
    LeadPos := ATargetPos + ATargetVel * FlightT;
    DX := LeadPos.X - ALaunchOrigin.X;
    DY := LeadPos.Y - ALaunchOrigin.Y;
    DZ := LeadPos.Z - ALaunchOrigin.Z;
    HorizDist := Hypot(DX, DZ);
    if HorizDist < 1e-4 then
    begin
      AElevationDeg := IfThen(DY >= 0.0, 89.0, -89.0);
      AInterceptLeadPos := LeadPos;
      Exit(True);
    end;
    { Vacuum ballistic parabola discriminant: v^4 - g*(g*x^2 + 2*y*v^2) }
    Disc := Sqr(Sqr(V0)) - G * (G * Sqr(HorizDist) + 2.0 * DY * Sqr(V0));
    if Disc < 0.0 then
      Exit(False);
    if AHighArc then
      TanTheta := (Sqr(V0) + Sqrt(Disc)) / (G * HorizDist)
    else
      TanTheta := (Sqr(V0) - Sqrt(Disc)) / (G * HorizDist);
    AElevationDeg := RadToDeg(ArcTan(TanTheta));
    FlightT := HorizDist / Max(0.25, V0 * Cos(DegToRad(AElevationDeg)));
    AInterceptLeadPos := LeadPos;
    Result := True;
  end;
end;

procedure TCastleBallisticLauncher.EnsurePreviewNodes;
begin
  if FPreviewRoot <> nil then Exit;
  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'BallisticTracerPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewScene := TCastleScene.Create(FPreviewRoot);
  FPreviewScene.SetTransient;
  FPreviewScene.Name := 'BallisticTracerPreviewScene';
  FPreviewScene.Pickable := False;
  FPreviewScene.Collides := False;
  FPreviewRoot.Add(FPreviewScene);
end;

procedure TCastleBallisticLauncher.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewScene := nil;
  end;
end;

procedure TCastleBallisticLauncher.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  MatNode: TUnlitMaterialNode;
  Pts: array of TVector3;
  InvWT, WT: TMatrix4;
  I: Integer;
begin
  if (csDestroying in ComponentState) or (not FShowPreview) then Exit;
  if FLastTrace.SampleCount < 2 then
  begin
    ClearPreview;
    Exit;
  end;

  EnsurePreviewNodes;
  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then
      InvWT := TMatrix4.Identity;
  end;

  SetLength(Pts, FLastTrace.SampleCount);
  for I := 0 to FLastTrace.SampleCount - 1 do
    Pts[I] := InvWT.MultPoint(FLastTrace.Samples[I].WorldPos);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  case FPreset of
    blpSniper762Supersonic: MatNode.EmissiveColor := Vector3(1.0, 0.78, 0.18);
    blpMortarHighArcHE:     MatNode.EmissiveColor := Vector3(1.0, 0.36, 0.14);
    blpRecurveLongbowArrow: MatNode.EmissiveColor := Vector3(0.28, 0.92, 0.56);
  end;
  ShapeNode.Material := MatNode;

  LineSet := TLineSetNode.Create;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([Length(Pts)]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewScene.Load(RootNode, True);
end;

function TCastleBallisticLauncher.BallisticSummaryBadge: String;
begin
  Result := FormatDot('[Ballistics:%.0fm/s Ric=%d Pen=%d]', [
    FMuzzleSpeedMps, FLastTrace.RicochetCount, FLastTrace.PenetrationCount]);
end;

initialization
  RegisterSerializableComponent(TCastleBallisticLauncher, 'Ballistic Trajectory Launcher');

end.
