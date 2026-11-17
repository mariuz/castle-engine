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

{ Secondary-motion jiggle bone spring behavior providing inertial world-space
  tip lag, under/critically-damped harmonic springs, gravity sag, exact rod
  length preservation, and spherical limit-cone clamping for ears, hair, pouches,
  tails, and antennas (Phase 344 — Unreal Engine 6.0+ AnimNode_SpringBone Parity). }
unit CastleJiggleBone;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleClassUtils, CastleUtils,
  CastleTransform;

type
  { Built-in secondary-motion spring & damping material presets. }
  TJiggleSpringPreset = (
    jspCustom,
    jspBouncyFoxEars,
    jspHeavyLeatherPouch,
    jspWhippyRadioAntenna,
    jspSoftSilkRibbon
  );

  { Inertial secondary-motion spring-damper behavior attached to any
    TCastleTransform (ear, hair tuft, pouch, cape clasp, antenna). }
  TCastleJiggleBoneBehavior = class(TCastleBehavior)
  private
    FPreset: TJiggleSpringPreset;
    FBoneLength: Single;
    FStiffness: Single;
    FDampingRatio: Single;
    FGravityFactor: Single;
    FMaxConeAngleDeg: Single;
    FParentInertiaScale: Single;
    FLocalRestAxis: TVector3;
    FLocalRestAxisPersistent: TCastleVector3Persistent;
    FDrivenTipTransformName: String;
    FAutoStepInUpdate: Boolean;

    FInitialized: Boolean;
    FPrevPivotWorld: TVector3;
    FPivotWorld: TVector3;
    FRestTipWorld: TVector3;
    FCurrentTipWorld: TVector3;
    FTipVelocityWorld: TVector3;
    FCurrentDeflectionDeg: Single;
    FPrevSignedLateralVel: Single;
    FOscillationReversals: Integer;

    procedure SetPreset(const AValue: TJiggleSpringPreset);
    procedure SetBoneLength(const AValue: Single);
    procedure SetStiffness(const AValue: Single);
    procedure SetDampingRatio(const AValue: Single);
    procedure SetGravityFactor(const AValue: Single);
    procedure SetMaxConeAngleDeg(const AValue: Single);
    procedure SetParentInertiaScale(const AValue: Single);

    function GetLocalRestAxisForPersistent: TVector3;
    procedure SetLocalRestAxisForPersistent(const AValue: TVector3);
    procedure ApplyPresetValuesOnly(const APreset: TJiggleSpringPreset);
    function ResolvePivotWorld: TVector3;
    function ResolveRestDirWorld: TVector3;
    procedure SyncDrivenTipTransform;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Snap tip immediately to its zero-velocity rest pose on Parent. }
    procedure ResetSpringToRest;

    { Apply preset parameters explicitly and reset oscillation counters. }
    procedure ApplySpringPreset(const APreset: TJiggleSpringPreset);

    { Advance inertial spring-damper & spherical limit-cone clamp by ADt seconds
      using sub-stepped semi-implicit Euler integration. }
    procedure StepSpring(const ADt: Single);

    function TipSpeedMetersPerSec: Single;
    function JiggleSummaryBadge: String;

    property LocalRestAxis: TVector3 read FLocalRestAxis write SetLocalRestAxisForPersistent;
    property PivotWorld: TVector3 read FPivotWorld;
    property RestTipWorld: TVector3 read FRestTipWorld;
    property CurrentTipWorld: TVector3 read FCurrentTipWorld;
    property TipVelocityWorld: TVector3 read FTipVelocityWorld;
    property CurrentDeflectionDeg: Single read FCurrentDeflectionDeg;
    property OscillationReversals: Integer read FOscillationReversals;
  published
    property Preset: TJiggleSpringPreset
      read FPreset write SetPreset default jspBouncyFoxEars;
    property BoneLength: Single
      read FBoneLength write SetBoneLength {$ifdef FPC}default 0.65{$endif};
    property Stiffness: Single
      read FStiffness write SetStiffness {$ifdef FPC}default 140.0{$endif};
    property DampingRatio: Single
      read FDampingRatio write SetDampingRatio {$ifdef FPC}default 0.35{$endif};
    property GravityFactor: Single
      read FGravityFactor write SetGravityFactor {$ifdef FPC}default 0.25{$endif};
    property MaxConeAngleDeg: Single
      read FMaxConeAngleDeg write SetMaxConeAngleDeg {$ifdef FPC}default 42.0{$endif};
    property ParentInertiaScale: Single
      read FParentInertiaScale write SetParentInertiaScale {$ifdef FPC}default 1.0{$endif};
    property LocalRestAxisPersistent: TCastleVector3Persistent read FLocalRestAxisPersistent;
    property DrivenTipTransformName: String read FDrivenTipTransformName write FDrivenTipTransformName;
    property AutoStepInUpdate: Boolean read FAutoStepInUpdate write FAutoStepInUpdate default True;
  end;

{ Clamp unit vector ADir within AMaxAngleDeg of unit vector ARestAxis. }
function ClampDirectionToCone(const ADir, ARestAxis: TVector3;
  const AMaxAngleDeg: Single; out AClampedDeflectionDeg: Single): TVector3;

function JigglePresetToDisplayName(const APreset: TJiggleSpringPreset): String;

implementation

uses
  CastleComponentSerialize;

function JigglePresetToDisplayName(const APreset: TJiggleSpringPreset): String;
begin
  case APreset of
    jspCustom:             Result := 'Custom Spring';
    jspBouncyFoxEars:      Result := 'Bouncy Fox Ears';
    jspHeavyLeatherPouch:  Result := 'Heavy Leather Pouch';
    jspWhippyRadioAntenna: Result := 'Whippy Steel Antenna';
    jspSoftSilkRibbon:     Result := 'Soft Silk Hair Ribbon';
  end;
end;

function ClampDirectionToCone(const ADir, ARestAxis: TVector3;
  const AMaxAngleDeg: Single; out AClampedDeflectionDeg: Single): TVector3;
var
  SafeAxis, SafeDir, RotAxis: TVector3;
  CosAng, AngleRad, MaxRad: Single;
begin
  if ARestAxis.IsZero then
    SafeAxis := Vector3(0, 1, 0)
  else
    SafeAxis := ARestAxis.Normalize;

  if ADir.IsZero then
    SafeDir := SafeAxis
  else
    SafeDir := ADir.Normalize;

  CosAng := EnsureRange(TVector3.DotProduct(SafeDir, SafeAxis), -1.0, 1.0);
  AngleRad := ArcCos(CosAng);
  MaxRad := DegToRad(EnsureRange(AMaxAngleDeg, 0.5, 175.0));

  if AngleRad <= MaxRad then
  begin
    AClampedDeflectionDeg := RadToDeg(AngleRad);
    Exit(SafeDir);
  end;

  RotAxis := TVector3.CrossProduct(SafeAxis, SafeDir);
  if RotAxis.LengthSqr < 1e-10 then
  begin
    { Anti-parallel 180 deg singularity: pick any orthogonal axis }
    if Abs(SafeAxis.Y) < 0.9 then
      RotAxis := TVector3.CrossProduct(SafeAxis, Vector3(0, 1, 0))
    else
      RotAxis := TVector3.CrossProduct(SafeAxis, Vector3(1, 0, 0));
  end;
  Result := RotatePointAroundAxisRad(MaxRad, SafeAxis, RotAxis).Normalize;
  AClampedDeflectionDeg := EnsureRange(AMaxAngleDeg, 0.5, 175.0);
end;

{ TCastleJiggleBoneBehavior -------------------------------------------------- }

constructor TCastleJiggleBoneBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLocalRestAxis := Vector3(0.0, 1.0, 0.0);
  FLocalRestAxisPersistent := TCastleVector3Persistent.Create(nil);
  FLocalRestAxisPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetLocalRestAxisForPersistent;
  FLocalRestAxisPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetLocalRestAxisForPersistent;
  FLocalRestAxisPersistent.InternalDefaultValue := FLocalRestAxis;

  FAutoStepInUpdate := True;
  FPreset := jspBouncyFoxEars;
  ApplyPresetValuesOnly(jspBouncyFoxEars);
  FInitialized := False;
end;

destructor TCastleJiggleBoneBehavior.Destroy;
begin
  FreeAndNil(FLocalRestAxisPersistent);
  inherited Destroy;
end;

function TCastleJiggleBoneBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'BoneLength', 'Stiffness', 'DampingRatio', 'GravityFactor',
       'MaxConeAngleDeg', 'ParentInertiaScale', 'LocalRestAxisPersistent',
       'DrivenTipTransformName', 'AutoStepInUpdate'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleJiggleBoneBehavior.ApplyPresetValuesOnly(
  const APreset: TJiggleSpringPreset);
begin
  case APreset of
    jspBouncyFoxEars:
      begin
        FBoneLength := 0.65;
        FStiffness := 140.0;
        FDampingRatio := 0.35;
        FGravityFactor := 0.25;
        FMaxConeAngleDeg := 42.0;
        FParentInertiaScale := 1.0;
        FLocalRestAxis := Vector3(0.0, 1.0, 0.0);
      end;
    jspHeavyLeatherPouch:
      begin
        FBoneLength := 0.45;
        FStiffness := 95.0;
        FDampingRatio := 0.72;
        FGravityFactor := 1.15;
        FMaxConeAngleDeg := 32.0;
        FParentInertiaScale := 0.90;
        FLocalRestAxis := Vector3(0.0, -1.0, 0.0);
      end;
    jspWhippyRadioAntenna:
      begin
        FBoneLength := 1.25;
        FStiffness := 240.0;
        FDampingRatio := 0.18;
        FGravityFactor := 0.10;
        FMaxConeAngleDeg := 55.0;
        FParentInertiaScale := 1.0;
        FLocalRestAxis := Vector3(0.0, 1.0, 0.0);
      end;
    jspSoftSilkRibbon:
      begin
        FBoneLength := 0.85;
        FStiffness := 55.0;
        FDampingRatio := 0.55;
        FGravityFactor := 0.85;
        FMaxConeAngleDeg := 68.0;
        FParentInertiaScale := 1.0;
        FLocalRestAxis := Vector3(0.0, -0.7, -0.7).Normalize;
      end;
  else ;
  end;
end;

procedure TCastleJiggleBoneBehavior.ApplySpringPreset(
  const APreset: TJiggleSpringPreset);
begin
  FPreset := APreset;
  if APreset <> jspCustom then
    ApplyPresetValuesOnly(APreset);
  ResetSpringToRest;
end;

procedure TCastleJiggleBoneBehavior.SetPreset(const AValue: TJiggleSpringPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  { Never overwrite custom property floats when jspCustom is deserialized }
  if AValue <> jspCustom then
    ApplyPresetValuesOnly(AValue);
end;

procedure TCastleJiggleBoneBehavior.SetBoneLength(const AValue: Single);
begin
  FBoneLength := Max(0.05, AValue);
  FPreset := jspCustom;
end;

procedure TCastleJiggleBoneBehavior.SetStiffness(const AValue: Single);
begin
  FStiffness := EnsureRange(AValue, 1.0, 4000.0);
  FPreset := jspCustom;
end;

procedure TCastleJiggleBoneBehavior.SetDampingRatio(const AValue: Single);
begin
  FDampingRatio := EnsureRange(AValue, 0.02, 4.0);
  FPreset := jspCustom;
end;

procedure TCastleJiggleBoneBehavior.SetGravityFactor(const AValue: Single);
begin
  FGravityFactor := EnsureRange(AValue, -4.0, 4.0);
  FPreset := jspCustom;
end;

procedure TCastleJiggleBoneBehavior.SetMaxConeAngleDeg(const AValue: Single);
begin
  FMaxConeAngleDeg := EnsureRange(AValue, 1.0, 175.0);
  FPreset := jspCustom;
end;

procedure TCastleJiggleBoneBehavior.SetParentInertiaScale(const AValue: Single);
begin
  FParentInertiaScale := EnsureRange(AValue, 0.0, 2.0);
  FPreset := jspCustom;
end;

function TCastleJiggleBoneBehavior.GetLocalRestAxisForPersistent: TVector3;
begin
  Result := FLocalRestAxis;
end;

procedure TCastleJiggleBoneBehavior.SetLocalRestAxisForPersistent(
  const AValue: TVector3);
begin
  if AValue.IsZero then
    FLocalRestAxis := Vector3(0.0, 1.0, 0.0)
  else
    FLocalRestAxis := AValue.Normalize;
end;

function TCastleJiggleBoneBehavior.ResolvePivotWorld: TVector3;
begin
  if (Parent <> nil) and Parent.HasParent then
    Result := Parent.WorldTranslation
  else if Parent <> nil then
    Result := Parent.Translation
  else
    Result := TVector3.Zero;
end;

function TCastleJiggleBoneBehavior.ResolveRestDirWorld: TVector3;
var
  SafeLocal: TVector3;
begin
  if FLocalRestAxis.IsZero then
    SafeLocal := Vector3(0.0, 1.0, 0.0)
  else
    SafeLocal := FLocalRestAxis.Normalize;

  if (Parent <> nil) and Parent.HasParent then
    Result := Parent.LocalToWorldDirection(SafeLocal)
  else if Parent <> nil then
    Result := Parent.Transform.MultDirection(SafeLocal)
  else
    Result := SafeLocal;

  if Result.IsZero then
    Result := Vector3(0.0, 1.0, 0.0)
  else
    Result := Result.Normalize;
end;

procedure TCastleJiggleBoneBehavior.ResetSpringToRest;
var
  RestDir: TVector3;
begin
  FPivotWorld := ResolvePivotWorld;
  FPrevPivotWorld := FPivotWorld;
  RestDir := ResolveRestDirWorld;
  FRestTipWorld := FPivotWorld + RestDir * FBoneLength;
  FCurrentTipWorld := FRestTipWorld;
  FTipVelocityWorld := TVector3.Zero;
  FCurrentDeflectionDeg := 0.0;
  FPrevSignedLateralVel := 0.0;
  FOscillationReversals := 0;
  FInitialized := True;
  SyncDrivenTipTransform;
end;

procedure TCastleJiggleBoneBehavior.SyncDrivenTipTransform;
var
  I: Integer;
  TargetT: TCastleTransform;
begin
  if (Parent = nil) or (FDrivenTipTransformName = '') then Exit;
  TargetT := nil;
  for I := 0 to Parent.Count - 1 do
    if SameText(Parent[I].Name, FDrivenTipTransformName) then
    begin
      TargetT := Parent[I];
      Break;
    end;
  if TargetT = nil then Exit;

  if Parent.HasParent then
    TargetT.Translation := Parent.WorldToLocal(FCurrentTipWorld)
  else
    TargetT.Translation := FCurrentTipWorld - Parent.Translation;
end;

procedure TCastleJiggleBoneBehavior.StepSpring(const ADt: Single);
const
  MaxSubStep = 1.0 / 120.0;
var
  TotalDt, SubDt, DampingCoeff, PreAngleDeg, LatVel: Single;
  Steps, S: Integer;
  NewPivot, PivotDelta, RestDir, Accel, RawDir, ClampedDir, OutwardNormal: TVector3;
  OutwardSpeed: Single;
begin
  if not FInitialized then
    ResetSpringToRest;

  TotalDt := EnsureRange(ADt, 0.0, 0.25);
  if TotalDt <= 0.0 then
    Exit;

  NewPivot := ResolvePivotWorld;
  PivotDelta := NewPivot - FPrevPivotWorld;
  FPrevPivotWorld := NewPivot;
  FPivotWorld := NewPivot;

  { Carry tip partially with parent when ParentInertiaScale < 1.0;
    at 1.0 the tip stays in world space and whips naturally }
  FCurrentTipWorld := FCurrentTipWorld + PivotDelta * (1.0 - FParentInertiaScale);

  RestDir := ResolveRestDirWorld;
  FRestTipWorld := FPivotWorld + RestDir * FBoneLength;

  Steps := Max(1, Ceil(TotalDt / MaxSubStep));
  SubDt := TotalDt / Single(Steps);
  DampingCoeff := 2.0 * FDampingRatio * Sqrt(FStiffness);

  for S := 1 to Steps do
  begin
    Accel := (FRestTipWorld - FCurrentTipWorld) * FStiffness
           - FTipVelocityWorld * DampingCoeff
           + Vector3(0.0, -9.81 * FGravityFactor, 0.0);

    FTipVelocityWorld := FTipVelocityWorld + Accel * SubDt;
    FCurrentTipWorld := FCurrentTipWorld + FTipVelocityWorld * SubDt;

    { Enforce spherical cone limit & inextensible BoneLength }
    RawDir := FCurrentTipWorld - FPivotWorld;
    if RawDir.LengthSqr < 1e-10 then
      RawDir := RestDir
    else
      RawDir := RawDir.Normalize;

    PreAngleDeg := RadToDeg(ArcCos(EnsureRange(TVector3.DotProduct(RawDir, RestDir), -1.0, 1.0)));
    ClampedDir := ClampDirectionToCone(RawDir, RestDir, FMaxConeAngleDeg, FCurrentDeflectionDeg);
    FCurrentTipWorld := FPivotWorld + ClampedDir * FBoneLength;

    { Remove rod-stretch velocity along ClampedDir }
    FTipVelocityWorld := FTipVelocityWorld
      - ClampedDir * TVector3.DotProduct(FTipVelocityWorld, ClampedDir);

    { If clamped against cone wall, strip outward cone-normal velocity }
    if PreAngleDeg > FMaxConeAngleDeg then
    begin
      OutwardNormal := (ClampedDir - RestDir * TVector3.DotProduct(ClampedDir, RestDir));
      if not OutwardNormal.IsZero then
      begin
        OutwardNormal := OutwardNormal.Normalize;
        OutwardSpeed := TVector3.DotProduct(FTipVelocityWorld, OutwardNormal);
        if OutwardSpeed > 0.0 then
          FTipVelocityWorld := FTipVelocityWorld - OutwardNormal * OutwardSpeed;
      end;
    end;

    { Count tangential velocity sign reversals for oscillation telemetry }
    LatVel := FTipVelocityWorld.X + FTipVelocityWorld.Z;
    if Abs(LatVel) > 0.02 then
    begin
      if (FPrevSignedLateralVel * LatVel) < 0.0 then
        Inc(FOscillationReversals);
      FPrevSignedLateralVel := LatVel;
    end;
  end;

  SyncDrivenTipTransform;
end;

procedure TCastleJiggleBoneBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if FAutoStepInUpdate then
    StepSpring(Min(SecondsPassed, 0.1));
end;

function TCastleJiggleBoneBehavior.TipSpeedMetersPerSec: Single;
begin
  Result := FTipVelocityWorld.Length;
end;

function TCastleJiggleBoneBehavior.JiggleSummaryBadge: String;
begin
  Result := Format('[Jiggle:k=%.0f z=%.2f Cone=%.0f/%.0fdeg]', [
    FStiffness, FDampingRatio, FCurrentDeflectionDeg, FMaxConeAngleDeg
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleJiggleBoneBehavior,
    ['Animation & Rigging', 'Secondary-Motion Jiggle Bone Spring (TCastleJiggleBoneBehavior)']);

end.
