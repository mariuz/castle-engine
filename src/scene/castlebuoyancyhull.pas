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

{ Multi-pontoon Archimedes buoyancy & hull hydrostatics solver with exact
  spherical-cap submergence, traveling wave surface sampling, metacentric
  pitch/roll righting torque, damped heave/roll settling, and transient 3D
  pontoon + waterline visualization (Phase 391). }
unit CastleBuoyancyHull;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors;

type
  { Preset vessel & floating prop pontoon configurations. }
  TBuoyancyHullPreset = (
    bhpWoodenCargoRaft4Pt,
    bhpPatrolGunboat6Pt,
    bhpFloatingOilDrumSingle
  );

  { Per-pontoon spherical-cap hydrostatic sample. }
  TPontoonSample = record
    LocalOffset: TVector3;
    WorldPos: TVector3;
    RadiusMeters: Single;
    VolumeScale: Single;
    WaterSurfaceY: Single;
    SubmergedFraction01: Single;
    DisplacedVolumeM3: Single;
    BuoyantUpForceN: Single;
  end;

  { Aggregated forces, righting torque, and attitude of the floating hull. }
  THullHydrostaticState = record
    PontoonCount: Integer;
    SubmergedPontoonCount: Integer;
    MeanSubmergence01: Single;
    TotalDisplacedVolumeM3: Single;
    TotalBuoyantUpForceN: Single;
    NetVerticalForceN: Single;
    NetRightingTorqueNm: TVector3;
    RollDeg: Single;
    PitchDeg: Single;
    HeaveVelocityMps: Single;
  end;

  { Multi-pontoon floating hull computing exact spherical-cap Archimedes
    buoyancy, wave heave/roll righting torque, and damped dynamic settling. }
  TCastleBuoyancyHull = class(TCastleTransform)
  private
    FPreset: TBuoyancyHullPreset;
    FHullMassKg: Single;
    FFluidDensityKgM3: Single;
    FWaterLevelY: Single;
    FWaveAmplitudeMeters: Single;
    FWaveLengthMeters: Single;
    FWaveSpeedMps: Single;
    FLinearHeaveDamping: Single;
    FAngularRightingDamping: Single;
    FCenterOfMassOffsetY: Single;
    FGravityMps2: Single;
    FShowPreview: Boolean;
    FSimTimeSec: Single;
    FRollDeg: Single;
    FPitchDeg: Single;
    FHeaveVelMps: Single;
    FRollVelRadSec: Single;
    FPitchVelRadSec: Single;
    FPontoons: array of TPontoonSample;
    FLastState: THullHydrostaticState;
    FPreviewRoot: TCastleTransform;
    procedure SetPreset(const AValue: TBuoyancyHullPreset);
    procedure SetShowPreview(const AValue: Boolean);
    procedure SyncTransformRotationFromAttitude;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TBuoyancyHullPreset);

    { Exact spherical-cap submerged fraction h^2*(3R - h)/(4*R^3) in [0..1]. }
    class function SphericalCapSubmergedFraction(
      const ASphereCenterY, ARadius, AWaterY: Single): Single;

    { Sample traveling wave surface elevation at world (AX, AZ) and current SimTimeSec. }
    function SampleWaterSurfaceY(const AX, AZ: Single): Single;

    { Set hull pitch (bow-up deg) and roll (starboard/+X-down deg) attitude. }
    procedure SetAttitudeDeg(const APitchDeg, ARollDeg: Single);

    { Evaluate Archimedes forces and metacentric righting torque at current pose. }
    function EvaluateHydrostatics: THullHydrostaticState;

    { Step damped heave, pitch, and roll rigid-body dynamics by ADtSec. }
    function StepHydrostaticMotion(const ADtSec: Single): THullHydrostaticState;

    function PontoonCount: Integer;
    function GetPontoonSample(const AIndex: Integer): TPontoonSample;
    procedure RebuildPreview;
    procedure ClearPreview;
    function BuoyancySummaryBadge: String;

    property LastState: THullHydrostaticState read FLastState;
    property SimTimeSec: Single read FSimTimeSec write FSimTimeSec;
  published
    property Preset: TBuoyancyHullPreset
      read FPreset write SetPreset default bhpWoodenCargoRaft4Pt;
    property HullMassKg: Single read FHullMassKg write FHullMassKg;
    property FluidDensityKgM3: Single read FFluidDensityKgM3 write FFluidDensityKgM3;
    property WaterLevelY: Single read FWaterLevelY write FWaterLevelY;
    property WaveAmplitudeMeters: Single read FWaveAmplitudeMeters write FWaveAmplitudeMeters;
    property WaveLengthMeters: Single read FWaveLengthMeters write FWaveLengthMeters;
    property WaveSpeedMps: Single read FWaveSpeedMps write FWaveSpeedMps;
    property LinearHeaveDamping: Single read FLinearHeaveDamping write FLinearHeaveDamping;
    property AngularRightingDamping: Single read FAngularRightingDamping write FAngularRightingDamping;
    property CenterOfMassOffsetY: Single read FCenterOfMassOffsetY write FCenterOfMassOffsetY;
    property GravityMps2: Single read FGravityMps2 write FGravityMps2;
    property ShowPreview: Boolean read FShowPreview write SetShowPreview default True;
  end;

function BuoyancyPresetToString(const APreset: TBuoyancyHullPreset): String;

implementation

uses
  CastleComponentSerialize, CastleQuaternions, CastleUtils;

function BuoyancyPresetToString(const APreset: TBuoyancyHullPreset): String;
begin
  case APreset of
    bhpWoodenCargoRaft4Pt:    Result := 'WoodenCargoRaft4Pt';
    bhpPatrolGunboat6Pt:      Result := 'PatrolGunboat6Pt';
    bhpFloatingOilDrumSingle: Result := 'FloatingOilDrumSingle';
  end;
end;

{ TCastleBuoyancyHull -------------------------------------------------------- }

constructor TCastleBuoyancyHull.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFluidDensityKgM3 := 1025.0;
  FWaterLevelY := 0.0;
  FGravityMps2 := 9.81;
  FShowPreview := True;
  FSimTimeSec := 0.0;
  FRollDeg := 0.0;
  FPitchDeg := 0.0;
  FHeaveVelMps := 0.0;
  FRollVelRadSec := 0.0;
  FPitchVelRadSec := 0.0;
  ApplyPreset(bhpWoodenCargoRaft4Pt);
end;

destructor TCastleBuoyancyHull.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleBuoyancyHull.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'HullMassKg', 'FluidDensityKgM3', 'WaterLevelY',
       'WaveAmplitudeMeters', 'WaveLengthMeters', 'WaveSpeedMps',
       'LinearHeaveDamping', 'AngularRightingDamping',
       'CenterOfMassOffsetY', 'GravityMps2', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleBuoyancyHull.SetPreset(const AValue: TBuoyancyHullPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleBuoyancyHull.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleBuoyancyHull.ApplyPreset(const APreset: TBuoyancyHullPreset);

  procedure AddPt(const AIdx: Integer; const AOff: TVector3;
    const ARad, AVolScale: Single);
  begin
    FPontoons[AIdx] := Default(TPontoonSample);
    FPontoons[AIdx].LocalOffset := AOff;
    FPontoons[AIdx].RadiusMeters := ARad;
    FPontoons[AIdx].VolumeScale := AVolScale;
  end;

begin
  FPreset := APreset;
  FFluidDensityKgM3 := 1025.0;
  FGravityMps2 := 9.81;
  FHeaveVelMps := 0.0;
  FRollVelRadSec := 0.0;
  FPitchVelRadSec := 0.0;

  case APreset of
    bhpWoodenCargoRaft4Pt:
      begin
        FHullMassKg := 680.0;
        FWaveAmplitudeMeters := 0.22;
        FWaveLengthMeters := 12.0;
        FWaveSpeedMps := 2.4;
        FLinearHeaveDamping := 4.2;
        FAngularRightingDamping := 3.5;
        FCenterOfMassOffsetY := -0.10;
        SetLength(FPontoons, 4);
        AddPt(0, Vector3(-1.4, 0.0, -1.8), 0.48, 1.0);
        AddPt(1, Vector3( 1.4, 0.0, -1.8), 0.48, 1.0);
        AddPt(2, Vector3(-1.4, 0.0,  1.8), 0.48, 1.0);
        AddPt(3, Vector3( 1.4, 0.0,  1.8), 0.48, 1.0);
      end;
    bhpPatrolGunboat6Pt:
      begin
        FHullMassKg := 2200.0;
        FWaveAmplitudeMeters := 0.45;
        FWaveLengthMeters := 18.0;
        FWaveSpeedMps := 3.6;
        FLinearHeaveDamping := 3.8;
        FAngularRightingDamping := 4.0;
        FCenterOfMassOffsetY := -0.25;
        SetLength(FPontoons, 6);
        AddPt(0, Vector3(-1.5, 0.0, -3.5), 0.56, 1.0);
        AddPt(1, Vector3( 1.5, 0.0, -3.5), 0.56, 1.0);
        AddPt(2, Vector3(-1.7, 0.0,  0.0), 0.62, 1.1);
        AddPt(3, Vector3( 1.7, 0.0,  0.0), 0.62, 1.1);
        AddPt(4, Vector3(-1.4, 0.0,  3.5), 0.56, 1.0);
        AddPt(5, Vector3( 1.4, 0.0,  3.5), 0.56, 1.0);
      end;
    bhpFloatingOilDrumSingle:
      begin
        FHullMassKg := 85.0;
        FWaveAmplitudeMeters := 0.18;
        FWaveLengthMeters := 9.0;
        FWaveSpeedMps := 2.0;
        FLinearHeaveDamping := 5.0;
        FAngularRightingDamping := 4.5;
        FCenterOfMassOffsetY := -0.08;
        SetLength(FPontoons, 1);
        AddPt(0, Vector3(0.0, 0.0, 0.0), 0.36, 1.0);
      end;
  end;
  EvaluateHydrostatics;
  RebuildPreview;
end;

class function TCastleBuoyancyHull.SphericalCapSubmergedFraction(
  const ASphereCenterY, ARadius, AWaterY: Single): Single;
var
  R, H: Single;
begin
  R := Max(0.001, ARadius);
  H := Clamped(AWaterY - (ASphereCenterY - R), 0.0, 2.0 * R);
  Result := (H * H * (3.0 * R - H)) / (4.0 * R * R * R);
end;

function TCastleBuoyancyHull.SampleWaterSurfaceY(const AX, AZ: Single): Single;
var
  WaveK, Phase: Single;
begin
  Result := FWaterLevelY;
  if (Abs(FWaveAmplitudeMeters) > 1e-5) and (FWaveLengthMeters > 0.2) then
  begin
    WaveK := (2.0 * Pi) / FWaveLengthMeters;
    Phase := WaveK * (0.8 * AX + 0.6 * AZ - FWaveSpeedMps * FSimTimeSec);
    Result := Result + FWaveAmplitudeMeters * Sin(Phase);
  end;
end;

procedure TCastleBuoyancyHull.SyncTransformRotationFromAttitude;
var
  QPitch, QRoll, QTotal: TQuaternion;
begin
  { Positive PitchDeg raises bow (-Z upward -> +Pitch around +X);
    Positive RollDeg heels starboard (+X downward -> -Roll around +Z) }
  QPitch := QuatFromAxisAngle(Vector4(1.0, 0.0, 0.0, DegToRad(FPitchDeg)));
  QRoll := QuatFromAxisAngle(Vector4(0.0, 0.0, 1.0, -DegToRad(FRollDeg)));
  QTotal := QPitch * QRoll;
  Rotation := QTotal.ToAxisAngle;
end;

procedure TCastleBuoyancyHull.SetAttitudeDeg(const APitchDeg, ARollDeg: Single);
begin
  FPitchDeg := Clamped(APitchDeg, -75.0, 75.0);
  FRollDeg := Clamped(ARollDeg, -75.0, 75.0);
  SyncTransformRotationFromAttitude;
  EvaluateHydrostatics;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleBuoyancyHull.EvaluateHydrostatics: THullHydrostaticState;
var
  WT: TMatrix4;
  ComWorld, LeverArm, UpForceVec: TVector3;
  I: Integer;
  R, FullSphereVol, SubFrac, DispVol, UpN, SumSub: Single;
begin
  Result := Default(THullHydrostaticState);
  SyncTransformRotationFromAttitude;
  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;

  ComWorld := WT.MultPoint(Vector3(0.0, FCenterOfMassOffsetY, 0.0));
  Result.PontoonCount := Length(FPontoons);
  Result.RollDeg := FRollDeg;
  Result.PitchDeg := FPitchDeg;
  Result.HeaveVelocityMps := FHeaveVelMps;
  SumSub := 0.0;

  for I := 0 to High(FPontoons) do
  begin
    FPontoons[I].WorldPos := WT.MultPoint(FPontoons[I].LocalOffset);
    FPontoons[I].WaterSurfaceY := SampleWaterSurfaceY(
      FPontoons[I].WorldPos.X, FPontoons[I].WorldPos.Z);
    R := Max(0.02, FPontoons[I].RadiusMeters);
    SubFrac := SphericalCapSubmergedFraction(
      FPontoons[I].WorldPos.Y, R, FPontoons[I].WaterSurfaceY);
    FullSphereVol := (4.0 / 3.0) * Pi * R * R * R * Max(0.05, FPontoons[I].VolumeScale);
    DispVol := FullSphereVol * SubFrac;
    UpN := Max(0.0, FFluidDensityKgM3) * DispVol * Max(0.0, FGravityMps2);

    FPontoons[I].SubmergedFraction01 := SubFrac;
    FPontoons[I].DisplacedVolumeM3 := DispVol;
    FPontoons[I].BuoyantUpForceN := UpN;

    if SubFrac > 0.001 then
      Inc(Result.SubmergedPontoonCount);
    SumSub := SumSub + SubFrac;
    Result.TotalDisplacedVolumeM3 := Result.TotalDisplacedVolumeM3 + DispVol;
    Result.TotalBuoyantUpForceN := Result.TotalBuoyantUpForceN + UpN;

    UpForceVec := Vector3(0.0, UpN, 0.0);
    LeverArm := FPontoons[I].WorldPos - ComWorld;
    Result.NetRightingTorqueNm := Result.NetRightingTorqueNm +
      TVector3.CrossProduct(LeverArm, UpForceVec);
  end;

  if Result.PontoonCount > 0 then
    Result.MeanSubmergence01 := SumSub / Result.PontoonCount;
  Result.NetVerticalForceN := Result.TotalBuoyantUpForceN -
    Max(1.0, FHullMassKg) * Max(0.0, FGravityMps2);
  FLastState := Result;
end;

function TCastleBuoyancyHull.StepHydrostaticMotion(
  const ADtSec: Single): THullHydrostaticState;
var
  SubSteps, S: Integer;
  Dt, MassSafe, InertiaApprox, AccelY, RollAcc, PitchAcc, SubDamp: Single;
  St: THullHydrostaticState;
  PosNow: TVector3;
begin
  if ADtSec <= 0.0 then
    Exit(EvaluateHydrostatics);

  SubSteps := Clamped(Ceil(ADtSec / 0.02), 1, 64);
  Dt := ADtSec / SubSteps;
  MassSafe := Max(1.0, FHullMassKg);
  InertiaApprox := MassSafe * 1.8;

  for S := 1 to SubSteps do
  begin
    FSimTimeSec := FSimTimeSec + Dt;
    St := EvaluateHydrostatics;
    SubDamp := 0.35 + 0.65 * St.MeanSubmergence01;

    AccelY := (St.NetVerticalForceN / MassSafe) -
      FLinearHeaveDamping * SubDamp * FHeaveVelMps;
    FHeaveVelMps := Clamped(FHeaveVelMps + AccelY * Dt, -20.0, 20.0);
    PosNow := Translation;
    PosNow.Y := PosNow.Y + FHeaveVelMps * Dt;
    Translation := PosNow;

    { NetRightingTorqueNm.Z > 0 opposes positive starboard RollDeg -> reduces FRollDeg }
    RollAcc := (-St.NetRightingTorqueNm.Z / InertiaApprox) -
      FAngularRightingDamping * SubDamp * FRollVelRadSec;
    PitchAcc := (St.NetRightingTorqueNm.X / InertiaApprox) -
      FAngularRightingDamping * SubDamp * FPitchVelRadSec;

    FRollVelRadSec := Clamped(FRollVelRadSec + RollAcc * Dt, -6.0, 6.0);
    FPitchVelRadSec := Clamped(FPitchVelRadSec + PitchAcc * Dt, -6.0, 6.0);
    FRollDeg := Clamped(FRollDeg + RadToDeg(FRollVelRadSec * Dt), -75.0, 75.0);
    FPitchDeg := Clamped(FPitchDeg + RadToDeg(FPitchVelRadSec * Dt), -75.0, 75.0);
  end;

  Result := EvaluateHydrostatics;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleBuoyancyHull.PontoonCount: Integer;
begin
  Result := Length(FPontoons);
end;

function TCastleBuoyancyHull.GetPontoonSample(
  const AIndex: Integer): TPontoonSample;
begin
  if (AIndex >= 0) and (AIndex < Length(FPontoons)) then
    Result := FPontoons[AIndex]
  else
    Result := Default(TPontoonSample);
end;

procedure TCastleBuoyancyHull.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
  end;
end;

procedure TCastleBuoyancyHull.RebuildPreview;
var
  DeckBox, PtBox: TCastleBox;
  I: Integer;
  D: Single;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'BuoyancyHullPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  DeckBox := TCastleBox.Create(FPreviewRoot);
  DeckBox.SetTransient;
  DeckBox.Pickable := False;
  DeckBox.Collides := False;
  case FPreset of
    bhpWoodenCargoRaft4Pt:
      begin
        DeckBox.Size := Vector3(3.2, 0.22, 4.2);
        DeckBox.Color := Vector4(0.56, 0.39, 0.22, 1.0);
      end;
    bhpPatrolGunboat6Pt:
      begin
        DeckBox.Size := Vector3(3.6, 0.45, 7.6);
        DeckBox.Color := Vector4(0.32, 0.40, 0.46, 1.0);
      end;
    bhpFloatingOilDrumSingle:
      begin
        DeckBox.Size := Vector3(0.62, 0.88, 0.62);
        DeckBox.Color := Vector4(0.82, 0.30, 0.16, 1.0);
      end;
  end;
  DeckBox.Translation := Vector3(0.0, 0.18, 0.0);
  FPreviewRoot.Add(DeckBox);

  for I := 0 to High(FPontoons) do
  begin
    PtBox := TCastleBox.Create(FPreviewRoot);
    PtBox.SetTransient;
    PtBox.Pickable := False;
    PtBox.Collides := False;
    D := FPontoons[I].RadiusMeters * 1.65;
    PtBox.Size := Vector3(D, D, D);
    PtBox.Translation := FPontoons[I].LocalOffset;
    if FPontoons[I].SubmergedFraction01 > 0.05 then
      PtBox.Color := Vector4(0.18, 0.82, 0.96, 1.0)
    else
      PtBox.Color := Vector4(0.95, 0.78, 0.24, 1.0);
    FPreviewRoot.Add(PtBox);
  end;

  Add(FPreviewRoot);
end;

function TCastleBuoyancyHull.BuoyancySummaryBadge: String;
begin
  Result := FormatDot('[Buoyancy:%d/%d pts Sub=%.0f%% Roll=%.1fdeg]', [
    FLastState.SubmergedPontoonCount, FLastState.PontoonCount,
    FLastState.MeanSubmergence01 * 100.0, FLastState.RollDeg]);
end;

initialization
  RegisterSerializableComponent(TCastleBuoyancyHull, 'Multi-Pontoon Buoyancy Hull');

end.
