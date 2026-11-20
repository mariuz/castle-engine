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

{ Procedural traversal zipline & cableway rig solving sloped rider-loaded cable
  sag, tangential gravity acceleration, pulley rolling friction, hand-brake
  deceleration, end-of-line arrestor spring braking, and momentum-conserving
  mid-span vault launch (Phase 399). }
unit CastleZiplineRig;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset zipline & aerial cableway configurations. }
  TZiplinePreset = (
    zrpAlpineCanyonZipline,
    zrpUrbanTacticalRappelLine,
    zrpHeavyMinecartCableway
  );

  { Instantaneous kinematic & cable-load telemetry of the zipline pulley. }
  TZiplineRiderState = record
    IsRiding: Boolean;
    NormalizedProgress01: Single;
    WorldPulleyPos: TVector3;
    WorldRiderHandsPos: TVector3;
    CableTangentDir: TVector3;
    SpeedMps: Single;
    LiveRiderSagMeters: Single;
    ReachedArrestorStop: Boolean;
  end;

  { Scene transform connecting local origin (Start Tower) to EndOffsetLocal
    (Lower Landing Tower) with dynamic pulley rider traversal. }
  TCastleZiplineRig = class(TCastleTransform)
  private
    FPreset: TZiplinePreset;
    FEndOffsetLocal: TVector3;
    FEndOffsetPersistent: TCastleVector3Persistent;
    FUnloadedSagMeters: Single;
    FCableSpringStiffnessNPerM: Single;
    FPulleyRollingFriction: Single;
    FHandBrakeDecelMps2: Single;
    FAerodynamicDragFactor: Single;
    FArrestorZoneStart01: Single;
    FVaultJumpUpSpeedMps: Single;
    FRiderMassKg: Single;
    FShowPreview: Boolean;
    FLastState: TZiplineRiderState;
    FPreviewRoot: TCastleTransform;
    FPreviewCableScene: TCastleScene;
    procedure SetPreset(const AValue: TZiplinePreset);
    procedure SetShowPreview(const AValue: Boolean);
    function GetEndOffsetForPersistent: TVector3;
    procedure SetEndOffsetForPersistent(const AValue: TVector3);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TZiplinePreset);

    { Evaluate 3D cable world position and unit forward tangent at AU01 in [0..1]. }
    procedure EvaluateCablePointAt(const AU01: Single;
      const AIncludeRiderLoad: Boolean;
      out AWorldPos, ATangentNorm: TVector3);

    { Lock a rider onto the pulley at ANormalizedU01 with AInitialSpeedMps. }
    procedure AttachRiderAtProgress(const ANormalizedU01: Single = 0.02;
      const AInitialSpeedMps: Single = 1.2);

    { Integrate tangential gravity, air drag, hand-brake AHandBrake01 in [0..1],
      and end-of-line arrestor spring braking over ADtSec. }
    function StepZiplineRide(const ADtSec: Single;
      const AHandBrake01: Single = 0.0): TZiplineRiderState;

    { Detach the rider mid-ride and return tangential + upward vault velocity. }
    function DisembarkVaultLaunch(
      out ALaunchPos, ALaunchVelocity: TVector3): Boolean;

    function ChordLengthMeters: Single;
    procedure RebuildPreview;
    procedure ClearPreview;
    function ZiplineSummaryBadge: String;

    property EndOffsetLocal: TVector3 read FEndOffsetLocal write FEndOffsetLocal;
    property LastState: TZiplineRiderState read FLastState;
  published
    property Preset: TZiplinePreset
      read FPreset write SetPreset default zrpAlpineCanyonZipline;
    property EndOffsetPersistent: TCastleVector3Persistent
      read FEndOffsetPersistent;
    property UnloadedSagMeters: Single
      read FUnloadedSagMeters write FUnloadedSagMeters;
    property CableSpringStiffnessNPerM: Single
      read FCableSpringStiffnessNPerM write FCableSpringStiffnessNPerM;
    property PulleyRollingFriction: Single
      read FPulleyRollingFriction write FPulleyRollingFriction;
    property HandBrakeDecelMps2: Single
      read FHandBrakeDecelMps2 write FHandBrakeDecelMps2;
    property AerodynamicDragFactor: Single
      read FAerodynamicDragFactor write FAerodynamicDragFactor;
    property ArrestorZoneStart01: Single
      read FArrestorZoneStart01 write FArrestorZoneStart01;
    property VaultJumpUpSpeedMps: Single
      read FVaultJumpUpSpeedMps write FVaultJumpUpSpeedMps;
    property RiderMassKg: Single
      read FRiderMassKg write FRiderMassKg;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function ZiplinePresetToString(const APreset: TZiplinePreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function ZiplinePresetToString(const APreset: TZiplinePreset): String;
begin
  case APreset of
    zrpAlpineCanyonZipline:     Result := 'AlpineCanyonZipline';
    zrpUrbanTacticalRappelLine: Result := 'UrbanTacticalRappelLine';
    zrpHeavyMinecartCableway:   Result := 'HeavyMinecartCableway';
  end;
end;

{ TCastleZiplineRig ---------------------------------------------------------- }

constructor TCastleZiplineRig.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEndOffsetLocal := Vector3(0.0, -9.0, -32.0);
  FEndOffsetPersistent := TCastleVector3Persistent.Create(nil);
  FEndOffsetPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetEndOffsetForPersistent;
  FEndOffsetPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetEndOffsetForPersistent;
  FEndOffsetPersistent.InternalDefaultValue := Vector3(0.0, -9.0, -32.0);
  FShowPreview := True;
  FLastState := Default(TZiplineRiderState);
  ApplyPreset(zrpAlpineCanyonZipline);
end;

destructor TCastleZiplineRig.Destroy;
begin
  ClearPreview;
  FreeAndNil(FEndOffsetPersistent);
  inherited Destroy;
end;

function TCastleZiplineRig.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'EndOffsetPersistent', 'UnloadedSagMeters',
       'CableSpringStiffnessNPerM', 'PulleyRollingFriction',
       'HandBrakeDecelMps2', 'AerodynamicDragFactor',
       'ArrestorZoneStart01', 'VaultJumpUpSpeedMps',
       'RiderMassKg', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleZiplineRig.GetEndOffsetForPersistent: TVector3;
begin
  Result := FEndOffsetLocal;
end;

procedure TCastleZiplineRig.SetEndOffsetForPersistent(const AValue: TVector3);
begin
  FEndOffsetLocal := AValue;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleZiplineRig.SetPreset(const AValue: TZiplinePreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleZiplineRig.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleZiplineRig.ApplyPreset(const APreset: TZiplinePreset);
begin
  FPreset := APreset;
  case APreset of
    zrpAlpineCanyonZipline:
      begin
        FEndOffsetLocal := Vector3(0.0, -9.0, -32.0);
        FUnloadedSagMeters := 0.65;
        FCableSpringStiffnessNPerM := 5200.0;
        FPulleyRollingFriction := 0.022;
        FHandBrakeDecelMps2 := 15.0;
        FAerodynamicDragFactor := 0.012;
        FArrestorZoneStart01 := 0.90;
        FVaultJumpUpSpeedMps := 5.2;
        FRiderMassKg := 82.0;
      end;
    zrpUrbanTacticalRappelLine:
      begin
        FEndOffsetLocal := Vector3(0.0, -11.0, -22.0);
        FUnloadedSagMeters := 0.28;
        FCableSpringStiffnessNPerM := 9500.0;
        FPulleyRollingFriction := 0.035;
        FHandBrakeDecelMps2 := 20.0;
        FAerodynamicDragFactor := 0.015;
        FArrestorZoneStart01 := 0.88;
        FVaultJumpUpSpeedMps := 4.8;
        FRiderMassKg := 90.0;
      end;
    zrpHeavyMinecartCableway:
      begin
        FEndOffsetLocal := Vector3(0.0, -6.0, -36.0);
        FUnloadedSagMeters := 0.95;
        FCableSpringStiffnessNPerM := 16000.0;
        FPulleyRollingFriction := 0.018;
        FHandBrakeDecelMps2 := 9.5;
        FAerodynamicDragFactor := 0.008;
        FArrestorZoneStart01 := 0.92;
        FVaultJumpUpSpeedMps := 3.5;
        FRiderMassKg := 320.0;
      end;
  end;
  AttachRiderAtProgress(0.04, 1.0);
end;

function TCastleZiplineRig.ChordLengthMeters: Single;
begin
  Result := Max(1.0, FEndOffsetLocal.Length);
end;

procedure TCastleZiplineRig.EvaluateCablePointAt(const AU01: Single;
  const AIncludeRiderLoad: Boolean;
  out AWorldPos, ATangentNorm: TVector3);

  function EvalLocalPt(const U: Single): TVector3;
  var
    UC, URider, GreenK, BaseSag, LiveSag: Single;
  begin
    UC := Clamped(U, 0.0, 1.0);
    BaseSag := 4.0 * Max(0.0, FUnloadedSagMeters) * UC * (1.0 - UC);
    LiveSag := 0.0;
    if AIncludeRiderLoad and FLastState.IsRiding and (FRiderMassKg > 0.1) then
    begin
      URider := Clamped(FLastState.NormalizedProgress01, 0.01, 0.99);
      if UC <= URider then
        GreenK := UC * (1.0 - URider)
      else
        GreenK := URider * (1.0 - UC);
      LiveSag := ((FRiderMassKg * 9.81) / Max(300.0, FCableSpringStiffnessNPerM)) *
        (4.0 * GreenK);
    end;
    Result := FEndOffsetLocal * UC - Vector3(0.0, BaseSag + LiveSag, 0.0);
  end;

var
  WT: TMatrix4;
  Eps, U0, U1: Single;
  P, P0, P1, W0, W1, Diff: TVector3;
begin
  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;

  P := EvalLocalPt(AU01);
  AWorldPos := WT.MultPoint(P);

  Eps := 0.004;
  U0 := Clamped(AU01 - Eps, 0.0, 1.0);
  U1 := Clamped(AU01 + Eps, 0.0, 1.0);
  if U1 <= U0 + 1e-5 then
  begin
    U0 := 0.0;
    U1 := 0.01;
  end;
  P0 := EvalLocalPt(U0);
  P1 := EvalLocalPt(U1);
  W0 := WT.MultPoint(P0);
  W1 := WT.MultPoint(P1);
  Diff := W1 - W0;
  if Diff.LengthSqr < 1e-8 then
    ATangentNorm := Vector3(0.0, 0.0, -1.0)
  else
    ATangentNorm := Diff.Normalize;
end;

procedure TCastleZiplineRig.AttachRiderAtProgress(
  const ANormalizedU01, AInitialSpeedMps: Single);
var
  UnloadedP, LoadedP, Tang: TVector3;
begin
  FLastState := Default(TZiplineRiderState);
  FLastState.IsRiding := True;
  FLastState.NormalizedProgress01 := Clamped(ANormalizedU01, 0.0, 0.99);
  FLastState.SpeedMps := Max(0.0, AInitialSpeedMps);
  FLastState.ReachedArrestorStop := False;

  EvaluateCablePointAt(FLastState.NormalizedProgress01, False, UnloadedP, Tang);
  EvaluateCablePointAt(FLastState.NormalizedProgress01, True, LoadedP, Tang);
  FLastState.WorldPulleyPos := LoadedP;
  FLastState.WorldRiderHandsPos := LoadedP - Vector3(0.0, 0.35, 0.0);
  FLastState.CableTangentDir := Tang;
  FLastState.LiveRiderSagMeters := Max(0.0, UnloadedP.Y - LoadedP.Y);

  if FShowPreview then
    RebuildPreview;
end;

function TCastleZiplineRig.StepZiplineRide(const ADtSec: Single;
  const AHandBrake01: Single): TZiplineRiderState;
var
  SubSteps, S: Integer;
  Dt, ChordLen, Brake01, U, V, GravTan, RollFric, BrakeDecel, AirDrag: Single;
  ArrestStart, ArrestDepth, Accel: Single;
  UnloadedP, LoadedP, Tang: TVector3;
begin
  if (not FLastState.IsRiding) or (ADtSec <= 0.0) then
    Exit(FLastState);

  SubSteps := Clamped(Ceil(ADtSec / 0.015), 1, 2048);
  Dt := ADtSec / SubSteps;
  ChordLen := ChordLengthMeters;
  Brake01 := Clamped(AHandBrake01, 0.0, 1.0);
  ArrestStart := Clamped(FArrestorZoneStart01, 0.65, 0.98);

  U := FLastState.NormalizedProgress01;
  V := FLastState.SpeedMps;

  for S := 1 to SubSteps do
  begin
    { Use unloaded chord slope for macroscopic pulley propulsion so self-sag well
      does not artificially trap the pulley before the lower tower }
    EvaluateCablePointAt(U, False, UnloadedP, Tang);

    GravTan := 9.81 * (-Tang.Y);
    RollFric := FPulleyRollingFriction * 9.81 * Max(0.1, Sqrt(Max(0.0, 1.0 - Sqr(Tang.Y))));
    BrakeDecel := Brake01 * Max(0.0, FHandBrakeDecelMps2);
    AirDrag := Max(0.0, FAerodynamicDragFactor) * V * Abs(V);

    Accel := GravTan - AirDrag;
    if V > 0.02 then
      Accel := Accel - RollFric - BrakeDecel
    else if Accel < RollFric + BrakeDecel then
    begin
      Accel := 0.0;
      V := 0.0;
    end;

    { End-of-line spring-damper arrestor collar }
    if U >= ArrestStart then
    begin
      ArrestDepth := (U - ArrestStart) / Max(0.01, 0.99 - ArrestStart);
      Accel := Accel - (45.0 * ArrestDepth) - (7.5 * V);
    end;

    V := Max(0.0, V + Accel * Dt);
    U := Clamped(U + (V / ChordLen) * Dt, 0.0, 0.99);

    if (U >= ArrestStart) and ((U >= 0.985) or (V <= 0.08)) then
    begin
      V := 0.0;
      FLastState.ReachedArrestorStop := True;
      Break;
    end;
  end;

  FLastState.NormalizedProgress01 := U;
  FLastState.SpeedMps := V;
  EvaluateCablePointAt(U, False, UnloadedP, Tang);
  EvaluateCablePointAt(U, True, LoadedP, Tang);
  FLastState.WorldPulleyPos := LoadedP;
  FLastState.WorldRiderHandsPos := LoadedP - Vector3(0.0, 0.35, 0.0);
  FLastState.CableTangentDir := Tang;
  FLastState.LiveRiderSagMeters := Max(0.0, UnloadedP.Y - LoadedP.Y);

  Result := FLastState;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleZiplineRig.DisembarkVaultLaunch(
  out ALaunchPos, ALaunchVelocity: TVector3): Boolean;
begin
  if not FLastState.IsRiding then
  begin
    ALaunchPos := TVector3.Zero;
    ALaunchVelocity := TVector3.Zero;
    Exit(False);
  end;
  ALaunchPos := FLastState.WorldRiderHandsPos;
  ALaunchVelocity := (FLastState.CableTangentDir * FLastState.SpeedMps) +
    Vector3(0.0, Max(0.0, FVaultJumpUpSpeedMps), 0.0);
  FLastState.IsRiding := False;
  FLastState.SpeedMps := 0.0;
  Result := True;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleZiplineRig.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewCableScene := nil;
  end;
end;

procedure TCastleZiplineRig.RebuildPreview;
const
  CableSegs = 28;
var
  InvWT, WT: TMatrix4;
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  MatNode: TUnlitMaterialNode;
  Pts: array of TVector3;
  PulleyBox: TCastleBox;
  WPos, Tang: TVector3;
  I: Integer;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'ZiplineRigPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  FPreviewCableScene := TCastleScene.Create(FPreviewRoot);
  FPreviewCableScene.SetTransient;
  FPreviewCableScene.Pickable := False;
  FPreviewCableScene.Collides := False;
  FPreviewRoot.Add(FPreviewCableScene);

  SetLength(Pts, CableSegs + 1);
  for I := 0 to CableSegs do
  begin
    EvaluateCablePointAt(I / CableSegs, True, WPos, Tang);
    Pts[I] := InvWT.MultPoint(WPos);
  end;

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(0.92, 0.78, 0.30);
  ShapeNode.Material := MatNode;
  LineSet := TLineSetNode.Create;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([Length(Pts)]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewCableScene.Load(RootNode, True);

  if FLastState.IsRiding then
  begin
    PulleyBox := TCastleBox.Create(FPreviewRoot);
    PulleyBox.SetTransient;
    PulleyBox.Pickable := False;
    PulleyBox.Collides := False;
    PulleyBox.Size := Vector3(0.28, 0.42, 0.38);
    PulleyBox.Translation := InvWT.MultPoint(FLastState.WorldPulleyPos);
    PulleyBox.Color := Vector4(0.22, 0.88, 0.98, 1.0);
    FPreviewRoot.Add(PulleyBox);
  end;

  Add(FPreviewRoot);
end;

function TCastleZiplineRig.ZiplineSummaryBadge: String;
begin
  Result := FormatDot('[Zipline:u=%.0f%% %.1fm/s Sag=%.2fm]', [
    FLastState.NormalizedProgress01 * 100.0,
    FLastState.SpeedMps,
    FLastState.LiveRiderSagMeters]);
end;

initialization
  RegisterSerializableComponent(TCastleZiplineRig, 'Procedural Zipline & Pulley Traversal Rig');

end.
