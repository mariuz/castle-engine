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

{ Aerodynamic Wing / Sail Foil Polar (CL, CD), Critical Stall Separation &
  Thermal Updraft Glider Behavior (Phase 369 — UE 6.0+ Flight/Sail Aero Parity). }
unit CastleAeroFoil;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleClassUtils;

type
  { Aerodynamic foil & membrane presets. }
  TAeroFoilPreset = (
    afpCustom,
    afpHangGliderHighAspectWing,
    afpWingsuitDeltaMembrane,
    afpSchoonerMainsailCanvas
  );

  { Dimensionless NACA lift/drag polar coefficients at angle of attack AlphaDeg. }
  TAeroFoilPolarSample = record
    AlphaDeg: Single;
    LiftCoeffCL: Single;
    DragCoeffCD: Single;
    LiftToDragRatio: Single;
    IsStalled: Boolean;
  end;

  { 3D world-space aerodynamic force evaluation for a moving wing/sail. }
  TAeroFoilForceState = record
    RelativeAirspeedMps: Single;
    AlphaDeg: Single;
    DynamicPressurePa: Single;
    LiftForceN: TVector3;
    DragForceN: TVector3;
    NetAeroForceN: TVector3;
    IsStalled: Boolean;
  end;

  { Finite-aspect-ratio NACA airfoil & sail behavior solving CL(alpha), induced +
    parasitic CD(alpha), post-stall flow separation, and thermal updraft soaring. }
  TCastleAeroFoilBehavior = class(TCastleBehavior)
  private
    FPreset: TAeroFoilPreset;
    FWingAreaSqM: Single;
    FAspectRatio: Single;
    FParasiticDragCD0: Single;
    FCriticalStallAngleDeg: Single;
    FZeroLiftAlphaOffsetDeg: Single;
    FAirframeMassKg: Single;
    FThermalCenterXZ: TVector2;
    FThermalRadiusMeters: Single;
    FThermalUpdraftSpeedMps: Single;
    FLastForceState: TAeroFoilForceState;
    procedure SetPreset(const AValue: TAeroFoilPreset);
    procedure SetWingAreaSqM(const AValue: Single);
    procedure SetAspectRatio(const AValue: Single);
    procedure SetParasiticDragCD0(const AValue: Single);
    procedure SetCriticalStallAngleDeg(const AValue: Single);
    procedure SetAirframeMassKg(const AValue: Single);
    procedure SetThermalRadiusMeters(const AValue: Single);
    procedure SetThermalUpdraftSpeedMps(const AValue: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParams(const APreset: TAeroFoilPreset);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetThermalCenterXZ(const ACenterXZ: TVector2);
    function EvaluatePolarAtAlphaDeg(const AAlphaDeg: Single): TAeroFoilPolarSample;
    function EvaluateThermalUpdraftAtWorld(const AWorldPos: TVector3): TVector3;
    function ComputeAeroForces(const AWorldPos, ABodyVelocityMps,
      AWingForwardWorld, AWingUpWorld, AAmbientWindMps: TVector3): TAeroFoilForceState;
    function StepGliderFlight(var WorldPos, VelocityMps: TVector3;
      const PitchDeg: Single; const AmbientWindMps: TVector3;
      const Dt: Single): TAeroFoilForceState;
    function AeroSummaryBadge: String;
    property LastForceState: TAeroFoilForceState read FLastForceState;
  published
    property Preset: TAeroFoilPreset read FPreset write SetPreset default afpHangGliderHighAspectWing;
    property WingAreaSqM: Single read FWingAreaSqM write SetWingAreaSqM {$ifdef FPC}default 14.5{$endif};
    property AspectRatio: Single read FAspectRatio write SetAspectRatio {$ifdef FPC}default 10.0{$endif};
    property ParasiticDragCD0: Single read FParasiticDragCD0 write SetParasiticDragCD0 {$ifdef FPC}default 0.022{$endif};
    property CriticalStallAngleDeg: Single read FCriticalStallAngleDeg write SetCriticalStallAngleDeg {$ifdef FPC}default 15.0{$endif};
    property AirframeMassKg: Single read FAirframeMassKg write SetAirframeMassKg {$ifdef FPC}default 95.0{$endif};
    property ThermalRadiusMeters: Single read FThermalRadiusMeters write SetThermalRadiusMeters {$ifdef FPC}default 35.0{$endif};
    property ThermalUpdraftSpeedMps: Single read FThermalUpdraftSpeedMps write SetThermalUpdraftSpeedMps {$ifdef FPC}default 4.0{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function AeroPresetToString(const APreset: TAeroFoilPreset): String;

implementation

uses fpjson, jsonparser, CastleComponentSerialize;

const
  SeaLevelAirDensity = 1.225;
  OswaldSpanEfficiency = 0.85;

function AeroPresetToString(const APreset: TAeroFoilPreset): String;
begin
  case APreset of
    afpCustom: Result := 'Custom Airfoil Polar';
    afpHangGliderHighAspectWing: Result := 'Soaring Hang-Glider Wing (AR=10.0, L/D ~ 17)';
    afpWingsuitDeltaMembrane: Result := 'Low-Aspect Wingsuit Delta Suit (AR=2.8, Stall 24 deg)';
    afpSchoonerMainsailCanvas: Result := 'Schooner Cambered Mainsail (Area=42 m^2)';
  end;
end;

{ TCastleAeroFoilBehavior ----------------------------------------------------- }

constructor TCastleAeroFoilBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FThermalCenterXZ := TVector2.Zero;
  ApplyPresetParams(afpHangGliderHighAspectWing);
end;

procedure TCastleAeroFoilBehavior.ApplyPresetParams(const APreset: TAeroFoilPreset);
begin
  FPreset := APreset;
  case APreset of
    afpHangGliderHighAspectWing, afpCustom:
      begin
        FWingAreaSqM := 14.5;
        FAspectRatio := 10.0;
        FParasiticDragCD0 := 0.022;
        FCriticalStallAngleDeg := 15.0;
        FZeroLiftAlphaOffsetDeg := 2.0;
        FAirframeMassKg := 95.0;
        FThermalRadiusMeters := 35.0;
        FThermalUpdraftSpeedMps := 4.0;
      end;
    afpWingsuitDeltaMembrane:
      begin
        FWingAreaSqM := 2.4;
        FAspectRatio := 2.8;
        FParasiticDragCD0 := 0.065;
        FCriticalStallAngleDeg := 24.0;
        FZeroLiftAlphaOffsetDeg := 1.0;
        FAirframeMassKg := 82.0;
        FThermalRadiusMeters := 35.0;
        FThermalUpdraftSpeedMps := 4.0;
      end;
    afpSchoonerMainsailCanvas:
      begin
        FWingAreaSqM := 42.0;
        FAspectRatio := 4.2;
        FParasiticDragCD0 := 0.045;
        FCriticalStallAngleDeg := 20.0;
        FZeroLiftAlphaOffsetDeg := 3.5;
        FAirframeMassKg := 650.0;
        FThermalRadiusMeters := 18.0;
        FThermalUpdraftSpeedMps := 0.0;
      end;
  end;
end;

procedure TCastleAeroFoilBehavior.SetPreset(const AValue: TAeroFoilPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> afpCustom then
    ApplyPresetParams(AValue);
end;

procedure TCastleAeroFoilBehavior.SetWingAreaSqM(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.2, 500.0);
  if SameValue(FWingAreaSqM, V, 1e-4) then Exit;
  FWingAreaSqM := V;
  FPreset := afpCustom;
end;

procedure TCastleAeroFoilBehavior.SetAspectRatio(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.8, 40.0);
  if SameValue(FAspectRatio, V, 1e-4) then Exit;
  FAspectRatio := V;
  FPreset := afpCustom;
end;

procedure TCastleAeroFoilBehavior.SetParasiticDragCD0(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.004, 0.50);
  if SameValue(FParasiticDragCD0, V, 1e-5) then Exit;
  FParasiticDragCD0 := V;
  FPreset := afpCustom;
end;

procedure TCastleAeroFoilBehavior.SetCriticalStallAngleDeg(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 6.0, 45.0);
  if SameValue(FCriticalStallAngleDeg, V, 1e-4) then Exit;
  FCriticalStallAngleDeg := V;
  FPreset := afpCustom;
end;

procedure TCastleAeroFoilBehavior.SetAirframeMassKg(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 5.0, 25000.0);
  if SameValue(FAirframeMassKg, V, 1e-3) then Exit;
  FAirframeMassKg := V;
  FPreset := afpCustom;
end;

procedure TCastleAeroFoilBehavior.SetThermalRadiusMeters(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 1.0, 250.0);
  if SameValue(FThermalRadiusMeters, V, 1e-4) then Exit;
  FThermalRadiusMeters := V;
  FPreset := afpCustom;
end;

procedure TCastleAeroFoilBehavior.SetThermalUpdraftSpeedMps(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 40.0);
  if SameValue(FThermalUpdraftSpeedMps, V, 1e-4) then Exit;
  FThermalUpdraftSpeedMps := V;
  FPreset := afpCustom;
end;

procedure TCastleAeroFoilBehavior.SetThermalCenterXZ(const ACenterXZ: TVector2);
begin
  FThermalCenterXZ := ACenterXZ;
end;

function TCastleAeroFoilBehavior.EvaluatePolarAtAlphaDeg(
  const AAlphaDeg: Single): TAeroFoilPolarSample;
var
  ClampedAlpha, LiftSlopePerRad, EffAlphaRad, PeakCL, StallBlend,
    AttachedCL, PostStallCL, InducedCD, SeparatedCD: Single;
begin
  ClampedAlpha := EnsureRange(AAlphaDeg, -85.0, 85.0);
  Result.AlphaDeg := ClampedAlpha;

  { Prandtl lifting-line finite-wing slope: a = 2*pi * AR / (AR + 2) }
  LiftSlopePerRad := (2.0 * Pi * FAspectRatio) / (FAspectRatio + 2.0);
  EffAlphaRad := DegToRad(ClampedAlpha + FZeroLiftAlphaOffsetDeg);

  if Abs(ClampedAlpha) <= FCriticalStallAngleDeg then
  begin
    Result.IsStalled := False;
    Result.LiftCoeffCL := LiftSlopePerRad * EffAlphaRad;
    InducedCD := Sqr(Result.LiftCoeffCL) / (Pi * OswaldSpanEfficiency * FAspectRatio);
    Result.DragCoeffCD := FParasiticDragCD0 + InducedCD;
  end else
  begin
    Result.IsStalled := True;
    PeakCL := LiftSlopePerRad * DegToRad(
      Sign(ClampedAlpha) * FCriticalStallAngleDeg + FZeroLiftAlphaOffsetDeg);
    { Smoothly separate into post-stall flat-plate vortex shedding over a 6-deg window }
    StallBlend := EnsureRange((Abs(ClampedAlpha) - FCriticalStallAngleDeg) / 6.0, 0.0, 1.0);
    AttachedCL := PeakCL * (1.0 - 0.55 * StallBlend);
    PostStallCL := 0.72 * Sin(2.0 * DegToRad(ClampedAlpha));
    Result.LiftCoeffCL := Lerp(StallBlend, AttachedCL, PostStallCL);

    InducedCD := Sqr(Result.LiftCoeffCL) / (Pi * OswaldSpanEfficiency * FAspectRatio);
    SeparatedCD := 1.35 * Sqr(Sin(DegToRad(ClampedAlpha)));
    Result.DragCoeffCD := FParasiticDragCD0 + InducedCD + SeparatedCD;
  end;

  Result.LiftToDragRatio := Result.LiftCoeffCL / Max(0.005, Result.DragCoeffCD);
end;

function TCastleAeroFoilBehavior.EvaluateThermalUpdraftAtWorld(
  const AWorldPos: TVector3): TVector3;
var
  DX, DZ, DistXZ, Weight: Single;
begin
  if FThermalUpdraftSpeedMps <= 0.001 then
    Exit(TVector3.Zero);
  DX := AWorldPos.X - FThermalCenterXZ.X;
  DZ := AWorldPos.Z - FThermalCenterXZ.Y;
  DistXZ := Sqrt(DX * DX + DZ * DZ);
  if DistXZ >= FThermalRadiusMeters then
    Exit(TVector3.Zero);
  Weight := Sqr(1.0 - (DistXZ / Max(0.5, FThermalRadiusMeters)));
  Result := Vector3(0.0, FThermalUpdraftSpeedMps * Weight, 0.0);
end;

function TCastleAeroFoilBehavior.ComputeAeroForces(
  const AWorldPos, ABodyVelocityMps, AWingForwardWorld, AWingUpWorld,
  AAmbientWindMps: TVector3): TAeroFoilForceState;
var
  AirVel, RelCraftVel, FwdUnit, UpUnit, RightAxis, FlowOppositeDir, LiftDir: TVector3;
  Speed, FwdComp, UpComp: Single;
  Polar: TAeroFoilPolarSample;
begin
  FillChar(Result, SizeOf(Result), 0);
  AirVel := AAmbientWindMps + EvaluateThermalUpdraftAtWorld(AWorldPos);
  { Craft velocity relative to surrounding air mass }
  RelCraftVel := ABodyVelocityMps - AirVel;
  Speed := RelCraftVel.Length;
  Result.RelativeAirspeedMps := Speed;
  if Speed < 0.05 then Exit;

  if AWingForwardWorld.LengthSqr > 1e-6 then
    FwdUnit := AWingForwardWorld.Normalize
  else
    FwdUnit := Vector3(0, 0, -1);

  if AWingUpWorld.LengthSqr > 1e-6 then
    UpUnit := AWingUpWorld.Normalize
  else
    UpUnit := Vector3(0, 1, 0);

  { Angle of attack alpha: positive when craft noses up relative to relative airflow }
  FwdComp := TVector3.DotProduct(RelCraftVel, FwdUnit);
  UpComp := TVector3.DotProduct(RelCraftVel, UpUnit);
  Result.AlphaDeg := RadToDeg(ArcTan2(-UpComp, Max(0.05, Abs(FwdComp))));

  Polar := EvaluatePolarAtAlphaDeg(Result.AlphaDeg);
  Result.IsStalled := Polar.IsStalled;
  Result.DynamicPressurePa := 0.5 * SeaLevelAirDensity * Sqr(Speed);

  FlowOppositeDir := -RelCraftVel / Speed;
  RightAxis := TVector3.CrossProduct(FwdUnit, UpUnit);
  if RightAxis.LengthSqr < 1e-6 then
    RightAxis := Vector3(1, 0, 0)
  else
    RightAxis := RightAxis.Normalize;

  { Lift acts perpendicular to relative velocity in the wing's dorsal (+UpUnit) plane }
  LiftDir := TVector3.CrossProduct(RightAxis, RelCraftVel / Speed);
  if LiftDir.LengthSqr < 1e-6 then
    LiftDir := UpUnit
  else
  begin
    LiftDir := LiftDir.Normalize;
    if TVector3.DotProduct(LiftDir, UpUnit) < 0.0 then
      LiftDir := -LiftDir;
  end;

  Result.LiftForceN := LiftDir * (Result.DynamicPressurePa * FWingAreaSqM * Polar.LiftCoeffCL);
  Result.DragForceN := FlowOppositeDir * (Result.DynamicPressurePa * FWingAreaSqM * Polar.DragCoeffCD);
  Result.NetAeroForceN := Result.LiftForceN + Result.DragForceN;
  FLastForceState := Result;
end;

function TCastleAeroFoilBehavior.StepGliderFlight(
  var WorldPos, VelocityMps: TVector3;
  const PitchDeg: Single; const AmbientWindMps: TVector3;
  const Dt: Single): TAeroFoilForceState;
var
  PitchRad: Single;
  WingFwd, WingUp, GravityForce, Accel: TVector3;
begin
  PitchRad := DegToRad(PitchDeg);
  WingFwd := Vector3(0.0, Sin(PitchRad), -Cos(PitchRad));
  WingUp := Vector3(0.0, Cos(PitchRad), Sin(PitchRad));
  Result := ComputeAeroForces(WorldPos, VelocityMps, WingFwd, WingUp, AmbientWindMps);
  if Dt <= 0.0 then Exit;

  GravityForce := Vector3(0.0, -9.81 * FAirframeMassKg, 0.0);
  Accel := (Result.NetAeroForceN + GravityForce) / Max(1.0, FAirframeMassKg);
  VelocityMps := VelocityMps + Accel * Dt;
  WorldPos := WorldPos + VelocityMps * Dt;
  if Parent <> nil then
    Parent.Translation := WorldPos;
end;

function TCastleAeroFoilBehavior.GetConfigJson: String;
var
  RootObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('area', FWingAreaSqM);
    RootObj.Add('ar', FAspectRatio);
    RootObj.Add('cd0', FParasiticDragCD0);
    RootObj.Add('stallDeg', FCriticalStallAngleDeg);
    RootObj.Add('massKg', FAirframeMassKg);
    RootObj.Add('thermalR', FThermalRadiusMeters);
    RootObj.Add('thermalUp', FThermalUpdraftSpeedMps);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleAeroFoilBehavior.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj: TJSONObject;
  PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FWingAreaSqM := EnsureRange(RootObj.Get('area', FWingAreaSqM), 0.2, 500.0);
      FAspectRatio := EnsureRange(RootObj.Get('ar', FAspectRatio), 0.8, 40.0);
      FParasiticDragCD0 := EnsureRange(RootObj.Get('cd0', FParasiticDragCD0), 0.004, 0.50);
      FCriticalStallAngleDeg := EnsureRange(RootObj.Get('stallDeg', FCriticalStallAngleDeg), 6.0, 45.0);
      FAirframeMassKg := EnsureRange(RootObj.Get('massKg', FAirframeMassKg), 5.0, 25000.0);
      FThermalRadiusMeters := EnsureRange(RootObj.Get('thermalR', FThermalRadiusMeters), 1.0, 250.0);
      FThermalUpdraftSpeedMps := EnsureRange(RootObj.Get('thermalUp', FThermalUpdraftSpeedMps), 0.0, 40.0);
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TAeroFoilPreset))) and
         (PresetOrd <= Ord(High(TAeroFoilPreset))) then
        FPreset := TAeroFoilPreset(PresetOrd);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleAeroFoilBehavior.AeroSummaryBadge: String;
begin
  Result := Format('[Aero:AR=%.1f Area=%.1fm2 %s]', [
    FAspectRatio,
    FWingAreaSqM,
    BoolToStr(FLastForceState.IsStalled, 'STALL!', 'ATTACHED')]);
end;

initialization
  RegisterSerializableComponent(TCastleAeroFoilBehavior, ['Physics & Vehicles', 'Aerodynamic Wing / Sail Foil']);
end.
