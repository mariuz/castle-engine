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

{ Grappling hook & jungle-vine 3D spherical pendulum swing solver with WorldRay
  overhead anchor locking, unilateral taut-sphere vs. slack freefall constraint,
  motorized winch reel-in, and apex release boost (Phase 403). }
unit CastleGrapplePendulum;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset grappling hook & pendulum traversal profiles. }
  TGrapplePendulumPreset = (
    gppJungleVineTarzanSwing,
    gppBatmanMotorizedGrapnel,
    gppTitanODM3DManeuver
  );

  { Instantaneous 3D spherical pendulum & cable state. }
  TGrappleSwingState = record
    HookAttached: Boolean;
    AnchorWorldPos: TVector3;
    PlayerWorldPos: TVector3;
    VelocityMps: TVector3;
    RopeLengthMeters: Single;
    CurrentDistanceMeters: Single;
    RopeIsTaut: Boolean;
    CableTensionNewtons: Single;
  end;

  { 3D grappling hook & pendulum swing rig component. }
  TCastleGrapplePendulum = class(TCastleTransform)
  private
    FPreset: TGrapplePendulumPreset;
    FMaxRangeMeters: Single;
    FRiderMassKg: Single;
    FWinchReelSpeedMps: Single;
    FMinWinchLengthMeters: Single;
    FAirDragPerSec: Single;
    FApexJumpUpSpeedMps: Single;
    FApexJumpForwardBoostMps: Single;
    FShowPreview: Boolean;
    FState: TGrappleSwingState;
    FPreviewRoot: TCastleTransform;
    FPreviewCableScene: TCastleScene;
    procedure SetPreset(const AValue: TGrapplePendulumPreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TGrapplePendulumPreset);

    { Cast a WorldRay along AAimDir up to MaxRangeMeters and lock onto the
      nearest non-transient solid overhang, gargoyle, or ceiling beam. }
    function FireGrappleHookRay(
      const AWorldRoot: TCastleAbstractRootTransform;
      const APlayerStartWorld, AAimDir, AInitialVelocity: TVector3): Boolean;

    procedure AttachHookDirect(
      const AAnchorWorld, APlayerStartWorld, AInitialVelocity: TVector3;
      const ARopeLengthMeters: Single);

    { Sub-stepped unilateral spherical rope integration: slack ballistic flight
      inside the sphere (||P - A|| < L) and tangential-momentum-preserving
      spherical projection on the boundary (||P - A|| >= L). }
    function StepPendulumSwing(const ADtSec: Single;
      const AWinchReelingIn: Boolean): TGrappleSwingState;

    { Detach the grapple hook and apply upward + forward apex release boost. }
    function ReleaseApexJump: TVector3;

    procedure RebuildPreview;
    procedure ClearPreview;
    function GrappleSummaryBadge: String;

    property State: TGrappleSwingState read FState;
  published
    property Preset: TGrapplePendulumPreset
      read FPreset write SetPreset default gppJungleVineTarzanSwing;
    property MaxRangeMeters: Single
      read FMaxRangeMeters write FMaxRangeMeters;
    property RiderMassKg: Single
      read FRiderMassKg write FRiderMassKg;
    property WinchReelSpeedMps: Single
      read FWinchReelSpeedMps write FWinchReelSpeedMps;
    property MinWinchLengthMeters: Single
      read FMinWinchLengthMeters write FMinWinchLengthMeters;
    property AirDragPerSec: Single
      read FAirDragPerSec write FAirDragPerSec;
    property ApexJumpUpSpeedMps: Single
      read FApexJumpUpSpeedMps write FApexJumpUpSpeedMps;
    property ApexJumpForwardBoostMps: Single
      read FApexJumpForwardBoostMps write FApexJumpForwardBoostMps;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function GrapplePendulumPresetToString(const APreset: TGrapplePendulumPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function GrapplePendulumPresetToString(const APreset: TGrapplePendulumPreset): String;
begin
  case APreset of
    gppJungleVineTarzanSwing:  Result := 'JungleVineTarzanSwing';
    gppBatmanMotorizedGrapnel: Result := 'BatmanMotorizedGrapnel';
    gppTitanODM3DManeuver:     Result := 'TitanODM3DManeuver';
  end;
end;

constructor TCastleGrapplePendulum.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FState := Default(TGrappleSwingState);
  FState.AnchorWorldPos := Vector3(0.0, 12.0, 0.0);
  FState.PlayerWorldPos := Vector3(-6.0, 6.0, 0.0);
  FState.RopeLengthMeters := PointsDistance(FState.AnchorWorldPos, FState.PlayerWorldPos);
  FState.CurrentDistanceMeters := FState.RopeLengthMeters;
  ApplyPreset(gppJungleVineTarzanSwing);
end;

destructor TCastleGrapplePendulum.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleGrapplePendulum.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'MaxRangeMeters', 'RiderMassKg', 'WinchReelSpeedMps',
       'MinWinchLengthMeters', 'AirDragPerSec', 'ApexJumpUpSpeedMps',
       'ApexJumpForwardBoostMps', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleGrapplePendulum.SetPreset(const AValue: TGrapplePendulumPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleGrapplePendulum.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleGrapplePendulum.ApplyPreset(const APreset: TGrapplePendulumPreset);
begin
  FPreset := APreset;
  case APreset of
    gppJungleVineTarzanSwing:
      begin
        FMaxRangeMeters := 24.0;
        FRiderMassKg := 78.0;
        FWinchReelSpeedMps := 2.4;
        FMinWinchLengthMeters := 1.8;
        FAirDragPerSec := 0.03;
        FApexJumpUpSpeedMps := 4.8;
        FApexJumpForwardBoostMps := 2.2;
      end;
    gppBatmanMotorizedGrapnel:
      begin
        FMaxRangeMeters := 45.0;
        FRiderMassKg := 92.0;
        FWinchReelSpeedMps := 14.5;
        FMinWinchLengthMeters := 1.2;
        FAirDragPerSec := 0.05;
        FApexJumpUpSpeedMps := 6.5;
        FApexJumpForwardBoostMps := 4.0;
      end;
    gppTitanODM3DManeuver:
      begin
        FMaxRangeMeters := 65.0;
        FRiderMassKg := 68.0;
        FWinchReelSpeedMps := 22.0;
        FMinWinchLengthMeters := 1.5;
        FAirDragPerSec := 0.02;
        FApexJumpUpSpeedMps := 7.2;
        FApexJumpForwardBoostMps := 6.5;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleGrapplePendulum.FireGrappleHookRay(
  const AWorldRoot: TCastleAbstractRootTransform;
  const APlayerStartWorld, AAimDir, AInitialVelocity: TVector3): Boolean;
var
  ActiveRoot: TCastleAbstractRootTransform;
  Dir, BestHit: TVector3;
  BestDist, D: Single;
  RH: TRayCollision;
  K: Integer;
  Item: TCastleTransform;
begin
  Result := False;
  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;
  if (ActiveRoot = nil) or (AAimDir.LengthSqr < 1e-6) then Exit;

  Dir := AAimDir.Normalize;
  BestDist := Max(1.0, FMaxRangeMeters) + 1.0;
  BestHit := TVector3.Zero;

  RH := ActiveRoot.WorldRay(APlayerStartWorld, Dir);
  try
    if RH = nil then Exit;
    for K := 0 to RH.Count - 1 do
    begin
      Item := RH[K].Item;
      if (Item = nil) or (Item = ActiveRoot) or (Item = Self) then Continue;
      if csTransient in Item.ComponentStyle then Continue;
      D := PointsDistance(APlayerStartWorld, RH[K].Point);
      if (D >= 0.50) and (D <= FMaxRangeMeters) and (D < BestDist) then
      begin
        BestDist := D;
        BestHit := RH[K].Point;
        Result := True;
      end;
    end;
  finally
    FreeAndNil(RH);
  end;

  if Result then
    AttachHookDirect(BestHit, APlayerStartWorld, AInitialVelocity, BestDist);
end;

procedure TCastleGrapplePendulum.AttachHookDirect(
  const AAnchorWorld, APlayerStartWorld, AInitialVelocity: TVector3;
  const ARopeLengthMeters: Single);
begin
  FState.HookAttached := True;
  FState.AnchorWorldPos := AAnchorWorld;
  FState.PlayerWorldPos := APlayerStartWorld;
  FState.VelocityMps := AInitialVelocity;
  FState.CurrentDistanceMeters := PointsDistance(AAnchorWorld, APlayerStartWorld);
  FState.RopeLengthMeters := Max(FMinWinchLengthMeters,
    Max(0.5, ARopeLengthMeters));
  FState.RopeIsTaut := FState.CurrentDistanceMeters >= FState.RopeLengthMeters - 1e-3;
  FState.CableTensionNewtons := 0.0;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleGrapplePendulum.StepPendulumSwing(const ADtSec: Single;
  const AWinchReelingIn: Boolean): TGrappleSwingState;
const
  GravityVec: TVector3 = (X: 0.0; Y: -9.81; Z: 0.0);
var
  SubSteps, I: Integer;
  StepDt, OldL, NewL, Dist, VRad, Mass, TanSpeedSq: Single;
  P, V, Offset, RadOut: TVector3;
begin
  if ADtSec <= 0.0 then
    Exit(FState);

  SubSteps := Clamped(Ceil(ADtSec / 0.0025), 1, 2048);
  StepDt := ADtSec / SubSteps;
  P := FState.PlayerWorldPos;
  V := FState.VelocityMps;
  Mass := Max(10.0, FRiderMassKg);

  for I := 1 to SubSteps do
  begin
    V := V + GravityVec * StepDt;
    V := V * Max(0.0, 1.0 - FAirDragPerSec * StepDt);
    P := P + V * StepDt;

    if FState.HookAttached then
    begin
      OldL := FState.RopeLengthMeters;
      if AWinchReelingIn and (FWinchReelSpeedMps > 0.0) then
      begin
        NewL := Max(Max(0.5, FMinWinchLengthMeters),
          OldL - FWinchReelSpeedMps * StepDt);
        FState.RopeLengthMeters := NewL;
      end else
        NewL := OldL;

      Offset := P - FState.AnchorWorldPos;
      Dist := Offset.Length;

      if Dist >= NewL - 1e-4 then
      begin
        { Rope is TAUT on the spherical shell ||P - Anchor|| = NewL }
        FState.RopeIsTaut := True;
        if Dist > 1e-5 then
          RadOut := Offset / Dist
        else
          RadOut := Vector3(0.0, -1.0, 0.0);

        P := FState.AnchorWorldPos + RadOut * NewL;
        VRad := TVector3.DotProduct(V, RadOut);

        if AWinchReelingIn and (NewL < OldL) then
        begin
          { Strip outward velocity and inject motorized inward winch pull }
          if VRad > -FWinchReelSpeedMps then
            V := V - RadOut * VRad;
          { Partial angular-momentum spin-up as radius contracts }
          V := V * Power(OldL / Max(0.5, NewL), 0.35);
        end else
        if VRad > 0.0 then
        begin
          { Unilateral inextensible rope: strip outward radial velocity,
            preserving 100% of tangential pendulum speed }
          V := V - RadOut * VRad;
        end;

        TanSpeedSq := Max(0.0, V.LengthSqr - Sqr(TVector3.DotProduct(V, RadOut)));
        FState.CableTensionNewtons := Mass * (
          Max(0.0, TVector3.DotProduct(GravityVec, RadOut)) +
          TanSpeedSq / Max(0.35, NewL));
        FState.CurrentDistanceMeters := NewL;
      end else
      begin
        { Rope is SLACK inside the sphere: pure ballistic freefall, zero push }
        FState.RopeIsTaut := False;
        FState.CableTensionNewtons := 0.0;
        FState.CurrentDistanceMeters := Dist;
      end;
    end else
    begin
      FState.RopeIsTaut := False;
      FState.CableTensionNewtons := 0.0;
      FState.CurrentDistanceMeters := PointsDistance(FState.AnchorWorldPos, P);
    end;
  end;

  FState.PlayerWorldPos := P;
  FState.VelocityMps := V;
  if FShowPreview then
    RebuildPreview;
  Result := FState;
end;

function TCastleGrapplePendulum.ReleaseApexJump: TVector3;
var
  HorizDir: TVector3;
begin
  FState.HookAttached := False;
  FState.RopeIsTaut := False;
  FState.CableTensionNewtons := 0.0;

  HorizDir := Vector3(FState.VelocityMps.X, 0.0, FState.VelocityMps.Z);
  if HorizDir.LengthSqr > 1e-4 then
    HorizDir := HorizDir.Normalize
  else
    HorizDir := Vector3(1.0, 0.0, 0.0);

  FState.VelocityMps := Vector3(
    FState.VelocityMps.X + HorizDir.X * FApexJumpForwardBoostMps,
    Max(0.0, FState.VelocityMps.Y) + FApexJumpUpSpeedMps,
    FState.VelocityMps.Z + HorizDir.Z * FApexJumpForwardBoostMps);
  Result := FState.VelocityMps;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleGrapplePendulum.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewCableScene := nil;
  end;
end;

procedure TCastleGrapplePendulum.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  InvWT, WT: TMatrix4;
  Pts: array[0..1] of TVector3;
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
  FPreviewRoot.Name := 'GrapplePendulumPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewCableScene := TCastleScene.Create(FPreviewRoot);
  FPreviewCableScene.SetTransient;
  FPreviewCableScene.Name := 'GrapplePendulumPreviewCable';
  FPreviewCableScene.Pickable := False;
  FPreviewCableScene.Collides := False;
  FPreviewRoot.Add(FPreviewCableScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  if FState.HookAttached and FState.RopeIsTaut then
    MatNode.EmissiveColor := Vector3(0.95, 0.72, 0.22)
  else
    MatNode.EmissiveColor := Vector3(0.50, 0.65, 0.80);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  CoordNode := TCoordinateNode.Create;
  Pts[0] := InvWT.MultPoint(FState.AnchorWorldPos);
  Pts[1] := InvWT.MultPoint(FState.PlayerWorldPos);
  CoordNode.SetPoint(Pts);

  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([2]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewCableScene.Load(RootNode, True);
end;

function TCastleGrapplePendulum.GrappleSummaryBadge: String;
begin
  Result := FormatDot('[Grapple:L=%.1fm %.1fm/s T=%.0fN]', [
    FState.RopeLengthMeters,
    FState.VelocityMps.Length,
    FState.CableTensionNewtons]);
end;

initialization
  RegisterSerializableComponent(TCastleGrapplePendulum, 'Grapple Pendulum Swing Rig');

end.
