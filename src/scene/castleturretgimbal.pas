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

{ Dual-axis gimbal turret controller with finite angular yaw/elevation servo
  slew rates, shortest-arc 360-deg wraparound vs. casemate sector clamping,
  WorldRay friendly-superstructure fire inhibit, critically-damped barrel
  recoil, and thermal overheat steam-vent lockout (Phase 413). }
unit CastleTurretGimbal;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset turret servo, arc & thermal profiles. }
  TTurretGimbalPreset = (
    tgpHeavyBattleshipMainBattery,
    tgpRapidCiwsAntiAirPhalanx,
    tgpSponsonCasemateLimitedArc
  );

  { Instantaneous gimbal angles, target error, recoil & thermal state. }
  TTurretGimbalState = record
    CurrentYawDeg: Single;
    CurrentPitchDeg: Single;
    AngularAimErrorDeg: Single;
    OnTargetReady: Boolean;
    FriendlyHullBlocked: Boolean;
    IsOverheatedVenting: Boolean;
    BarrelHeat01: Single;
    RecoilOffsetMeters: Single;
    ShotsFiredCount: Integer;
  end;

  { Dual-axis gimbal turret servo, recoil & thermal lockout component. }
  TCastleTurretGimbal = class(TCastleTransform)
  private
    FPreset: TTurretGimbalPreset;
    FFull360Traverse: Boolean;
    FMinYawDeg: Single;
    FMaxYawDeg: Single;
    FMinPitchDeg: Single;
    FMaxPitchDeg: Single;
    FYawSlewDegPerSec: Single;
    FPitchSlewDegPerSec: Single;
    FHeatPerShot01: Single;
    FCoolingRatePerSec: Single;
    FVentResetHeat01: Single;
    FRecoilKickMeters: Single;
    FShowPreview: Boolean;
    FState: TTurretGimbalState;
    FRecoilVelMps: Single;
    FPreviewRoot: TCastleTransform;
    FPreviewBarrelScene: TCastleScene;
    procedure SetPreset(const AValue: TTurretGimbalPreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TTurretGimbalPreset);
    procedure ResetGimbalAngles(const AYawDeg, APitchDeg: Single);

    { World-space unit direction along which the barrel currently points. }
    function CurrentBarrelWorldDirection: TVector3;

    { Step bounded yaw/pitch servos toward ATargetWorldPos, check WorldRay
      friendly-superstructure fire inhibit, and integrate recoil + cooling. }
    function StepServoTracking(
      const AWorldRoot: TCastleAbstractRootTransform;
      const ATargetWorldPos: TVector3;
      const ADtSec: Single): TTurretGimbalState;

    { Attempt to fire a round; returns False if overheated or blocked by a
      Friendly* / Superstructure* hull obstacle. }
    function FireCannonRound: Boolean;

    procedure RebuildPreview;
    procedure ClearPreview;
    function TurretSummaryBadge: String;

    property State: TTurretGimbalState read FState;
  published
    property Preset: TTurretGimbalPreset
      read FPreset write SetPreset default tgpHeavyBattleshipMainBattery;
    property Full360Traverse: Boolean
      read FFull360Traverse write FFull360Traverse default True;
    property MinYawDeg: Single read FMinYawDeg write FMinYawDeg;
    property MaxYawDeg: Single read FMaxYawDeg write FMaxYawDeg;
    property MinPitchDeg: Single read FMinPitchDeg write FMinPitchDeg;
    property MaxPitchDeg: Single read FMaxPitchDeg write FMaxPitchDeg;
    property YawSlewDegPerSec: Single read FYawSlewDegPerSec write FYawSlewDegPerSec;
    property PitchSlewDegPerSec: Single read FPitchSlewDegPerSec write FPitchSlewDegPerSec;
    property HeatPerShot01: Single read FHeatPerShot01 write FHeatPerShot01;
    property CoolingRatePerSec: Single read FCoolingRatePerSec write FCoolingRatePerSec;
    property VentResetHeat01: Single read FVentResetHeat01 write FVentResetHeat01;
    property RecoilKickMeters: Single read FRecoilKickMeters write FRecoilKickMeters;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function TurretGimbalPresetToString(const APreset: TTurretGimbalPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function TurretGimbalPresetToString(const APreset: TTurretGimbalPreset): String;
begin
  case APreset of
    tgpHeavyBattleshipMainBattery: Result := 'HeavyBattleshipMainBattery';
    tgpRapidCiwsAntiAirPhalanx:    Result := 'RapidCiwsAntiAirPhalanx';
    tgpSponsonCasemateLimitedArc:  Result := 'SponsonCasemateLimitedArc';
  end;
end;

function NormalizeSignedDeg180(const ADeg: Single): Single;
begin
  Result := ADeg - 360.0 * Floor((ADeg + 180.0) / 360.0);
end;

function GimbalAnglesToLocalDir(const AYawDeg, APitchDeg: Single): TVector3;
var
  YawR, PitchR, CosP: Single;
begin
  YawR := DegToRad(AYawDeg);
  PitchR := DegToRad(APitchDeg);
  CosP := Cos(PitchR);
  Result := Vector3(Sin(YawR) * CosP, Sin(PitchR), -Cos(YawR) * CosP);
end;

constructor TCastleTurretGimbal.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FState := Default(TTurretGimbalState);
  FRecoilVelMps := 0.0;
  ApplyPreset(tgpHeavyBattleshipMainBattery);
end;

destructor TCastleTurretGimbal.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleTurretGimbal.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'Full360Traverse', 'MinYawDeg', 'MaxYawDeg',
       'MinPitchDeg', 'MaxPitchDeg', 'YawSlewDegPerSec',
       'PitchSlewDegPerSec', 'HeatPerShot01', 'CoolingRatePerSec',
       'VentResetHeat01', 'RecoilKickMeters', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleTurretGimbal.SetPreset(const AValue: TTurretGimbalPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleTurretGimbal.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleTurretGimbal.ApplyPreset(const APreset: TTurretGimbalPreset);
begin
  FPreset := APreset;
  case APreset of
    tgpHeavyBattleshipMainBattery:
      begin
        FFull360Traverse := True;
        FMinYawDeg := -180.0;
        FMaxYawDeg := 180.0;
        FMinPitchDeg := -6.0;
        FMaxPitchDeg := 45.0;
        FYawSlewDegPerSec := 30.0;
        FPitchSlewDegPerSec := 16.0;
        FHeatPerShot01 := 0.35;
        FCoolingRatePerSec := 0.22;
        FVentResetHeat01 := 0.25;
        FRecoilKickMeters := 0.65;
      end;
    tgpRapidCiwsAntiAirPhalanx:
      begin
        FFull360Traverse := True;
        FMinYawDeg := -180.0;
        FMaxYawDeg := 180.0;
        FMinPitchDeg := -15.0;
        FMaxPitchDeg := 85.0;
        FYawSlewDegPerSec := 120.0;
        FPitchSlewDegPerSec := 95.0;
        FHeatPerShot01 := 0.14;
        FCoolingRatePerSec := 0.35;
        FVentResetHeat01 := 0.20;
        FRecoilKickMeters := 0.08;
      end;
    tgpSponsonCasemateLimitedArc:
      begin
        FFull360Traverse := False;
        FMinYawDeg := -45.0;
        FMaxYawDeg := 45.0;
        FMinPitchDeg := -10.0;
        FMaxPitchDeg := 25.0;
        FYawSlewDegPerSec := 48.0;
        FPitchSlewDegPerSec := 30.0;
        FHeatPerShot01 := 0.25;
        FCoolingRatePerSec := 0.25;
        FVentResetHeat01 := 0.25;
        FRecoilKickMeters := 0.32;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleTurretGimbal.ResetGimbalAngles(const AYawDeg, APitchDeg: Single);
begin
  if FFull360Traverse then
    FState.CurrentYawDeg := NormalizeSignedDeg180(AYawDeg)
  else
    FState.CurrentYawDeg := Clamped(AYawDeg, FMinYawDeg, FMaxYawDeg);
  FState.CurrentPitchDeg := Clamped(APitchDeg, FMinPitchDeg, FMaxPitchDeg);
  if FShowPreview then
    RebuildPreview;
end;

function TCastleTurretGimbal.CurrentBarrelWorldDirection: TVector3;
var
  WT: TMatrix4;
  LocalDir: TVector3;
begin
  LocalDir := GimbalAnglesToLocalDir(FState.CurrentYawDeg, FState.CurrentPitchDeg);
  if HasWorldTransform then WT := WorldTransform else WT := Transform;
  Result := WT.MultDirection(LocalDir);
  if Result.LengthSqr > 1e-8 then
    Result := Result.Normalize
  else
    Result := LocalDir;
end;

function TCastleTurretGimbal.StepServoTracking(
  const AWorldRoot: TCastleAbstractRootTransform;
  const ATargetWorldPos: TVector3; const ADtSec: Single): TTurretGimbalState;
const
  OmegaRecoil = 14.0;
var
  ActiveRoot: TCastleAbstractRootTransform;
  InvWT, WT: TMatrix4;
  LocalTarget, BarrelLocal, BarrelWorld, MuzzleWorld, ToTargetW: TVector3;
  DesiredYaw, DesiredPitch, DeltaYaw, DeltaPitch, MaxYawStep, MaxPitchStep: Single;
  SubSteps, I, K: Integer;
  SubDt, Accel, TargetDist, HitDist: Single;
  RH: TRayCollision;
  HitItem: TCastleTransform;
begin
  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;

  if HasWorldTransform then
  begin
    WT := WorldTransform;
    InvWT := WorldInverseTransform;
  end else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  LocalTarget := InvWT.MultPoint(ATargetWorldPos);
  if (Abs(LocalTarget.X) > 1e-5) or (Abs(LocalTarget.Z) > 1e-5) then
    DesiredYaw := RadToDeg(ArcTan2(LocalTarget.X, -LocalTarget.Z))
  else
    DesiredYaw := FState.CurrentYawDeg;

  DesiredPitch := RadToDeg(ArcTan2(LocalTarget.Y, Hypot(LocalTarget.X, LocalTarget.Z)));
  DesiredPitch := Clamped(DesiredPitch, FMinPitchDeg, FMaxPitchDeg);

  if ADtSec > 0.0 then
  begin
    MaxYawStep := Max(0.1, FYawSlewDegPerSec) * ADtSec;
    MaxPitchStep := Max(0.1, FPitchSlewDegPerSec) * ADtSec;

    if FFull360Traverse then
    begin
      DeltaYaw := NormalizeSignedDeg180(DesiredYaw - FState.CurrentYawDeg);
      FState.CurrentYawDeg := NormalizeSignedDeg180(
        FState.CurrentYawDeg + Clamped(DeltaYaw, -MaxYawStep, MaxYawStep));
    end else
    begin
      DesiredYaw := Clamped(DesiredYaw, FMinYawDeg, FMaxYawDeg);
      DeltaYaw := DesiredYaw - FState.CurrentYawDeg;
      FState.CurrentYawDeg := Clamped(
        FState.CurrentYawDeg + Clamped(DeltaYaw, -MaxYawStep, MaxYawStep),
        FMinYawDeg, FMaxYawDeg);
    end;

    DeltaPitch := DesiredPitch - FState.CurrentPitchDeg;
    FState.CurrentPitchDeg := Clamped(
      FState.CurrentPitchDeg + Clamped(DeltaPitch, -MaxPitchStep, MaxPitchStep),
      FMinPitchDeg, FMaxPitchDeg);

    { Critically-damped barrel recoil spring recovery }
    SubSteps := Clamped(Ceil(ADtSec / 0.005), 1, 512);
    SubDt := ADtSec / SubSteps;
    for I := 1 to SubSteps do
    begin
      Accel := -(OmegaRecoil * OmegaRecoil) * FState.RecoilOffsetMeters -
               (2.0 * OmegaRecoil) * FRecoilVelMps;
      FRecoilVelMps := FRecoilVelMps + Accel * SubDt;
      FState.RecoilOffsetMeters := Max(0.0,
        FState.RecoilOffsetMeters + FRecoilVelMps * SubDt);
    end;

    { Thermal barrel heat dissipation & steam-vent lockout reset }
    FState.BarrelHeat01 := Max(0.0,
      FState.BarrelHeat01 - Max(0.01, FCoolingRatePerSec) * ADtSec);
    if FState.IsOverheatedVenting and
       (FState.BarrelHeat01 <= Clamped(FVentResetHeat01, 0.05, 0.90)) then
      FState.IsOverheatedVenting := False;
  end;

  BarrelLocal := GimbalAnglesToLocalDir(FState.CurrentYawDeg, FState.CurrentPitchDeg);
  if LocalTarget.LengthSqr > 1e-6 then
    FState.AngularAimErrorDeg := RadToDeg(ArcCos(Clamped(
      TVector3.DotProduct(BarrelLocal, LocalTarget.Normalize), -1.0, 1.0)))
  else
    FState.AngularAimErrorDeg := 0.0;
  FState.OnTargetReady := FState.AngularAimErrorDeg <= 1.5;

  { Friendly hull / bridge superstructure WorldRay fire inhibit }
  FState.FriendlyHullBlocked := False;
  if ActiveRoot <> nil then
  begin
    MuzzleWorld := WT.MultPoint(TVector3.Zero);
    BarrelWorld := CurrentBarrelWorldDirection;
    ToTargetW := ATargetWorldPos - MuzzleWorld;
    TargetDist := Max(1.0, ToTargetW.Length);

    RH := ActiveRoot.WorldRay(MuzzleWorld, BarrelWorld);
    try
      if RH <> nil then
        for K := 0 to RH.Count - 1 do
        begin
          HitItem := RH[K].Item;
          if (HitItem = nil) or (HitItem = ActiveRoot) or (HitItem = Self) then
            Continue;
          if csTransient in HitItem.ComponentStyle then Continue;
          HitDist := PointsDistance(MuzzleWorld, RH[K].Point);
          if (HitDist > 0.15) and (HitDist < TargetDist - 0.25) and
             ((Pos('Friendly', HitItem.Name) > 0) or
              (Pos('Superstructure', HitItem.Name) > 0)) then
          begin
            FState.FriendlyHullBlocked := True;
            Break;
          end;
        end;
    finally
      FreeAndNil(RH);
    end;
  end;

  if FShowPreview then
    RebuildPreview;
  Result := FState;
end;

function TCastleTurretGimbal.FireCannonRound: Boolean;
begin
  if FState.IsOverheatedVenting or FState.FriendlyHullBlocked then
    Exit(False);

  Inc(FState.ShotsFiredCount);
  FState.RecoilOffsetMeters := Max(0.02, FRecoilKickMeters);
  FRecoilVelMps := 0.0;
  FState.BarrelHeat01 := FState.BarrelHeat01 + Max(0.01, FHeatPerShot01);
  if FState.BarrelHeat01 >= 1.0 then
  begin
    FState.BarrelHeat01 := 1.0;
    FState.IsOverheatedVenting := True;
  end;

  if FShowPreview then
    RebuildPreview;
  Result := True;
end;

procedure TCastleTurretGimbal.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewBarrelScene := nil;
  end;
end;

procedure TCastleTurretGimbal.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  BDir, Breech, Muzzle: TVector3;
  Pts: array[0..1] of TVector3;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'TurretGimbalPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewBarrelScene := TCastleScene.Create(FPreviewRoot);
  FPreviewBarrelScene.SetTransient;
  FPreviewBarrelScene.Name := 'TurretGimbalPreviewBarrel';
  FPreviewBarrelScene.Pickable := False;
  FPreviewBarrelScene.Collides := False;
  FPreviewRoot.Add(FPreviewBarrelScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  if FState.IsOverheatedVenting then
    MatNode.EmissiveColor := Vector3(1.0, 0.25, 0.18)
  else if FState.FriendlyHullBlocked then
    MatNode.EmissiveColor := Vector3(0.95, 0.78, 0.22)
  else
    MatNode.EmissiveColor := Vector3(0.38, 0.88, 1.0);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  BDir := GimbalAnglesToLocalDir(FState.CurrentYawDeg, FState.CurrentPitchDeg);
  Breech := -BDir * FState.RecoilOffsetMeters;
  Muzzle := BDir * (2.6 - FState.RecoilOffsetMeters);

  CoordNode := TCoordinateNode.Create;
  Pts[0] := Breech;
  Pts[1] := Muzzle;
  CoordNode.SetPoint(Pts);

  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([2]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewBarrelScene.Load(RootNode, True);
end;

function TCastleTurretGimbal.TurretSummaryBadge: String;
begin
  Result := FormatDot('[Turret:Yaw=%.0f Pitch=%.0f Heat=%.0f%%]', [
    FState.CurrentYawDeg, FState.CurrentPitchDeg, FState.BarrelHeat01 * 100.0]);
end;

initialization
  RegisterSerializableComponent(TCastleTurretGimbal, 'Dual-Axis Gimbal Turret');

end.
