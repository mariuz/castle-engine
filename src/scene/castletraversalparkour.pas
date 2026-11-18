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

{ Parkour traversal obstacle ray-scanner & root-motion warp anchor solver
  classifying StepUp, ThinVaultOver, LowMantleOnto, HighLedgeClimb, and
  BlockedSheerWall (including overhead ceiling headroom rejection)
  (Phase 349 — Unreal Engine 6.0+ GASP Traversal Parity). }
unit CastleTraversalParkour;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleClassUtils, CastleUtils,
  CastleTransform;

type
  { Parkour traversal maneuver classified from multi-ray geometry scanning. }
  TTraversalActionKind = (
    takNoneClearPath,
    takStepUp,
    takThinVaultOver,
    takLowMantleOnto,
    takHighLedgeClimb,
    takBlockedSheerWall
  );

  { Complete geometric & motion-warping anchor solution for a scanned obstacle. }
  TTraversalProbeResult = record
    Action: TTraversalActionKind;
    HasObstacle: Boolean;
    BlockedByLowCeiling: Boolean;
    ForwardDistance: Single;
    ObstacleHeightAboveFeet: Single;
    ObstacleTopDepth: Single;
    HasFarSideLanding: Boolean;
    FrontEdgeAnchorWorld: TVector3;
    LandingAnchorWorld: TVector3;
    SuggestedMontageId: String;
  end;

  { Parkour traversal scanner & Bezier root-motion warp behavior. }
  TCastleTraversalBehavior = class(TCastleBehavior)
  private
    FForwardReachMeters: Single;
    FMaxStepUpHeight: Single;
    FMaxLowMantleHeight: Single;
    FMaxHighClimbHeight: Single;
    FMaxVaultThickness: Single;
    FCapsuleClearanceHeight: Single;
    FWarpDurationSec: Single;

    FLastProbe: TTraversalProbeResult;
    FIsWarping: Boolean;
    FWarpAlpha: Single;
    FWarpStartWorld: TVector3;

    procedure SetForwardReachMeters(const AValue: Single);
    procedure SetMaxVaultThickness(const AValue: Single);
    procedure SetCapsuleClearanceHeight(const AValue: Single);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Multi-ray forward/top/ceiling/far-drop obstacle scanner against AWorld. }
    function ScanObstacleAhead(const AWorld: TCastleAbstractRootTransform;
      const AFeetWorldPos, AForwardDirXZ: TVector3): TTraversalProbeResult;

    { Convenience overload reading Parent's world position & -Z/+Z forward. }
    function ScanFromParent(const AWorld: TCastleAbstractRootTransform;
      const AForwardDirXZ: TVector3): TTraversalProbeResult;

    { Evaluate 2-phase Bezier/Hermite root-motion warp trajectory at Alpha [0..1]. }
    class function EvaluateWarpTrajectory(const AStartFeetWorld: TVector3;
      const AProbe: TTraversalProbeResult; const AAlpha: Single): TVector3; static;

    function BeginTraversalWarp(const AStartFeetWorld: TVector3;
      const AProbe: TTraversalProbeResult): Boolean;
    procedure StepTraversalWarp(const ADt: Single);

    function TraversalSummaryBadge: String;

    property LastProbe: TTraversalProbeResult read FLastProbe;
    property IsWarping: Boolean read FIsWarping;
    property WarpAlpha: Single read FWarpAlpha;
  published
    property ForwardReachMeters: Single
      read FForwardReachMeters write SetForwardReachMeters {$ifdef FPC}default 1.80{$endif};
    property MaxStepUpHeight: Single
      read FMaxStepUpHeight write FMaxStepUpHeight {$ifdef FPC}default 0.55{$endif};
    property MaxLowMantleHeight: Single
      read FMaxLowMantleHeight write FMaxLowMantleHeight {$ifdef FPC}default 1.45{$endif};
    property MaxHighClimbHeight: Single
      read FMaxHighClimbHeight write FMaxHighClimbHeight {$ifdef FPC}default 2.65{$endif};
    property MaxVaultThickness: Single
      read FMaxVaultThickness write SetMaxVaultThickness {$ifdef FPC}default 0.90{$endif};
    property CapsuleClearanceHeight: Single
      read FCapsuleClearanceHeight write SetCapsuleClearanceHeight {$ifdef FPC}default 1.75{$endif};
    property WarpDurationSec: Single
      read FWarpDurationSec write FWarpDurationSec {$ifdef FPC}default 0.65{$endif};
  end;

function TraversalActionToDisplayName(const AAction: TTraversalActionKind): String;
function TraversalActionMontageId(const AAction: TTraversalActionKind): String;

implementation

uses
  CastleComponentSerialize;

function TraversalActionToDisplayName(const AAction: TTraversalActionKind): String;
begin
  case AAction of
    takNoneClearPath:    Result := 'Clear Path';
    takStepUp:           Result := 'Quick Step-Up';
    takThinVaultOver:    Result := 'Thin Barrier Vault';
    takLowMantleOnto:    Result := 'Chest Mantle Onto';
    takHighLedgeClimb:   Result := 'High Ledge Hang-Climb';
    takBlockedSheerWall: Result := 'Blocked Wall / Ceiling';
  end;
end;

function TraversalActionMontageId(const AAction: TTraversalActionKind): String;
begin
  case AAction of
    takNoneClearPath:    Result := '';
    takStepUp:           Result := 'anim_traversal_step_up';
    takThinVaultOver:    Result := 'anim_traversal_vault_one_hand';
    takLowMantleOnto:    Result := 'anim_traversal_mantle_1m';
    takHighLedgeClimb:   Result := 'anim_traversal_climb_2m';
    takBlockedSheerWall: Result := '';
  end;
end;

{ TCastleTraversalBehavior --------------------------------------------------- }

constructor TCastleTraversalBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FForwardReachMeters := 1.80;
  FMaxStepUpHeight := 0.55;
  FMaxLowMantleHeight := 1.45;
  FMaxHighClimbHeight := 2.65;
  FMaxVaultThickness := 0.90;
  FCapsuleClearanceHeight := 1.75;
  FWarpDurationSec := 0.65;
  FLastProbe := Default(TTraversalProbeResult);
end;

function TCastleTraversalBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'ForwardReachMeters', 'MaxStepUpHeight', 'MaxLowMantleHeight',
       'MaxHighClimbHeight', 'MaxVaultThickness', 'CapsuleClearanceHeight',
       'WarpDurationSec'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleTraversalBehavior.SetForwardReachMeters(const AValue: Single);
begin
  FForwardReachMeters := EnsureRange(AValue, 0.30, 6.0);
end;

procedure TCastleTraversalBehavior.SetMaxVaultThickness(const AValue: Single);
begin
  FMaxVaultThickness := EnsureRange(AValue, 0.15, 3.0);
end;

procedure TCastleTraversalBehavior.SetCapsuleClearanceHeight(const AValue: Single);
begin
  FCapsuleClearanceHeight := EnsureRange(AValue, 0.40, 3.5);
end;

function RaycastFirstDist(const AWorld: TCastleAbstractRootTransform;
  const AOrigin, ADir: TVector3; out AHitDist: Single): Boolean;
var
  Hit: TRayCollision;
begin
  Result := False;
  AHitDist := 1e9;
  if AWorld = nil then Exit;
  Hit := AWorld.WorldRay(AOrigin, ADir);
  try
    if (Hit <> nil) and (Hit.Distance >= 0.0) then
    begin
      AHitDist := Hit.Distance;
      Result := True;
    end;
  finally
    FreeAndNil(Hit);
  end;
end;

function TCastleTraversalBehavior.ScanObstacleAhead(
  const AWorld: TCastleAbstractRootTransform;
  const AFeetWorldPos, AForwardDirXZ: TVector3): TTraversalProbeResult;
var
  Fwd, ShinOrigin, FrontHitXZ, StepOrigin, TopProbeOrigin, CeilOrigin, DepthOrigin: TVector3;
  SavedParentExists, FoundClearOpening: Boolean;
  HitDist, ScanY, TopRayStartY, TopY, HeightAboveFeet, ProbeStep, D, SampleY, FarFloorY: Single;
begin
  Result := Default(TTraversalProbeResult);
  Result.Action := takNoneClearPath;
  if AWorld = nil then
  begin
    FLastProbe := Result;
    Exit;
  end;

  Fwd := Vector3(AForwardDirXZ.X, 0.0, AForwardDirXZ.Z);
  if Fwd.LengthSqr < 1e-8 then
    Fwd := Vector3(0.0, 0.0, -1.0)
  else
    Fwd := Fwd.Normalize;

  SavedParentExists := (Parent <> nil) and Parent.Exists;
  if Parent <> nil then
    Parent.Exists := False;
  try
    { 1. Forward shin-level probe }
    ShinOrigin := AFeetWorldPos + Vector3(0.0, 0.30, 0.0);
    if (not RaycastFirstDist(AWorld, ShinOrigin, Fwd, HitDist)) or
       (HitDist > FForwardReachMeters) then
    begin
      FLastProbe := Result;
      Exit;
    end;

    Result.HasObstacle := True;
    Result.ForwardDistance := HitDist;
    FrontHitXZ := Vector3(
      AFeetWorldPos.X + Fwd.X * HitDist,
      AFeetWorldPos.Y,
      AFeetWorldPos.Z + Fwd.Z * HitDist);

    { 2. Step upward along the obstacle face to find the exact lip opening
         (works cleanly underneath indoor ceilings and overhangs!) }
    FoundClearOpening := False;
    TopRayStartY := AFeetWorldPos.Y + FMaxHighClimbHeight + 0.30;
    ScanY := AFeetWorldPos.Y + 0.25;
    while ScanY <= AFeetWorldPos.Y + FMaxHighClimbHeight + 0.25 do
    begin
      StepOrigin := Vector3(
        FrontHitXZ.X - Fwd.X * 0.15,
        ScanY,
        FrontHitXZ.Z - Fwd.Z * 0.15);
      if (not RaycastFirstDist(AWorld, StepOrigin, Fwd, HitDist)) or (HitDist > 0.35) then
      begin
        FoundClearOpening := True;
        TopRayStartY := ScanY + 0.05;
        Break;
      end;
      ScanY := ScanY + 0.20;
    end;

    if not FoundClearOpening then
    begin
      Result.ObstacleHeightAboveFeet := FMaxHighClimbHeight + 0.50;
      Result.Action := takBlockedSheerWall;
      FLastProbe := Result;
      Exit;
    end;

    { Downward top-surface snap from just inside the cleared opening }
    TopProbeOrigin := Vector3(
      FrontHitXZ.X + Fwd.X * 0.12,
      TopRayStartY,
      FrontHitXZ.Z + Fwd.Z * 0.12);

    if not RaycastFirstDist(AWorld, TopProbeOrigin, Vector3(0, -1, 0), HitDist) then
    begin
      Result.Action := takBlockedSheerWall;
      FLastProbe := Result;
      Exit;
    end;

    TopY := TopRayStartY - HitDist;
    HeightAboveFeet := TopY - AFeetWorldPos.Y;
    Result.ObstacleHeightAboveFeet := HeightAboveFeet;
    Result.FrontEdgeAnchorWorld := Vector3(FrontHitXZ.X, TopY, FrontHitXZ.Z);

    if (HeightAboveFeet > FMaxHighClimbHeight) or (HeightAboveFeet <= 0.05) then
    begin
      Result.Action := takBlockedSheerWall;
      FLastProbe := Result;
      Exit;
    end;

    { 3. Overhead ceiling headroom probe above top ledge }
    CeilOrigin := Result.FrontEdgeAnchorWorld + Fwd * 0.20 + Vector3(0.0, 0.05, 0.0);
    if RaycastFirstDist(AWorld, CeilOrigin, Vector3(0, +1, 0), HitDist) and
       (HitDist < FCapsuleClearanceHeight) then
    begin
      Result.BlockedByLowCeiling := True;
      Result.Action := takBlockedSheerWall;
      FLastProbe := Result;
      Exit;
    end;

    { 4. Thickness / far-side drop scan across obstacle top }
    Result.ObstacleTopDepth := FMaxVaultThickness + 0.50;
    Result.HasFarSideLanding := False;
    FarFloorY := AFeetWorldPos.Y;
    ProbeStep := 0.15;
    D := 0.20;
    while D <= FMaxVaultThickness + 0.35 do
    begin
      DepthOrigin := Vector3(
        FrontHitXZ.X + Fwd.X * D,
        TopY + 0.50,
        FrontHitXZ.Z + Fwd.Z * D);
      if RaycastFirstDist(AWorld, DepthOrigin, Vector3(0, -1, 0), HitDist) then
        SampleY := (TopY + 0.50) - HitDist
      else
        SampleY := AFeetWorldPos.Y;

      if SampleY < TopY - 0.40 then
      begin
        Result.ObstacleTopDepth := D;
        Result.HasFarSideLanding := D <= FMaxVaultThickness;
        FarFloorY := SampleY;
        Break;
      end;
      D := D + ProbeStep;
    end;

    { 5. Classify parkour maneuver & compute LandingAnchorWorld }
    if HeightAboveFeet <= FMaxStepUpHeight then
    begin
      Result.Action := takStepUp;
      Result.LandingAnchorWorld := Vector3(
        FrontHitXZ.X + Fwd.X * 0.45, TopY, FrontHitXZ.Z + Fwd.Z * 0.45);
    end else if (HeightAboveFeet <= FMaxLowMantleHeight) and Result.HasFarSideLanding then
    begin
      Result.Action := takThinVaultOver;
      Result.LandingAnchorWorld := Vector3(
        FrontHitXZ.X + Fwd.X * (Result.ObstacleTopDepth + 0.65),
        FarFloorY,
        FrontHitXZ.Z + Fwd.Z * (Result.ObstacleTopDepth + 0.65));
    end else if HeightAboveFeet <= FMaxLowMantleHeight then
    begin
      Result.Action := takLowMantleOnto;
      Result.LandingAnchorWorld := Vector3(
        FrontHitXZ.X + Fwd.X * 0.60, TopY, FrontHitXZ.Z + Fwd.Z * 0.60);
    end else
    begin
      Result.Action := takHighLedgeClimb;
      Result.LandingAnchorWorld := Vector3(
        FrontHitXZ.X + Fwd.X * 0.60, TopY, FrontHitXZ.Z + Fwd.Z * 0.60);
    end;

    Result.SuggestedMontageId := TraversalActionMontageId(Result.Action);
    FLastProbe := Result;
  finally
    if Parent <> nil then
      Parent.Exists := SavedParentExists;
  end;
end;

function TCastleTraversalBehavior.ScanFromParent(
  const AWorld: TCastleAbstractRootTransform;
  const AForwardDirXZ: TVector3): TTraversalProbeResult;
var
  FeetPos: TVector3;
begin
  if (Parent <> nil) and Parent.HasParent then
    FeetPos := Parent.WorldTranslation
  else if Parent <> nil then
    FeetPos := Parent.Translation
  else
    FeetPos := TVector3.Zero;
  Result := ScanObstacleAhead(AWorld, FeetPos, AForwardDirXZ);
end;

class function TCastleTraversalBehavior.EvaluateWarpTrajectory(
  const AStartFeetWorld: TVector3;
  const AProbe: TTraversalProbeResult; const AAlpha: Single): TVector3;
var
  T, OneMinusT, ClearanceY: Single;
  ApexCtrl: TVector3;
begin
  T := EnsureRange(AAlpha, 0.0, 1.0);
  if not (AProbe.Action in [takStepUp, takThinVaultOver, takLowMantleOnto, takHighLedgeClimb]) then
    Exit(AStartFeetWorld);

  if AProbe.Action = takThinVaultOver then
    ClearanceY := 0.38
  else
    ClearanceY := 0.22;

  ApexCtrl := Lerp(0.5, AProbe.FrontEdgeAnchorWorld, AProbe.LandingAnchorWorld)
    + Vector3(0.0, ClearanceY, 0.0);
  ApexCtrl.Y := Max(ApexCtrl.Y, AProbe.FrontEdgeAnchorWorld.Y + ClearanceY);

  OneMinusT := 1.0 - T;
  Result := AStartFeetWorld * (OneMinusT * OneMinusT)
          + ApexCtrl * (2.0 * OneMinusT * T)
          + AProbe.LandingAnchorWorld * (T * T);
end;

function TCastleTraversalBehavior.BeginTraversalWarp(
  const AStartFeetWorld: TVector3; const AProbe: TTraversalProbeResult): Boolean;
begin
  Result := AProbe.Action in [takStepUp, takThinVaultOver, takLowMantleOnto, takHighLedgeClimb];
  if not Result then Exit;
  FLastProbe := AProbe;
  FWarpStartWorld := AStartFeetWorld;
  FWarpAlpha := 0.0;
  FIsWarping := True;
end;

procedure TCastleTraversalBehavior.StepTraversalWarp(const ADt: Single);
var
  PosW: TVector3;
begin
  if not FIsWarping then Exit;
  FWarpAlpha := Min(1.0, FWarpAlpha + Max(0.0, ADt) / Max(0.10, FWarpDurationSec));
  PosW := EvaluateWarpTrajectory(FWarpStartWorld, FLastProbe, FWarpAlpha);
  if Parent <> nil then
    Parent.Translation := PosW;
  if FWarpAlpha >= 1.0 then
    FIsWarping := False;
end;

function TCastleTraversalBehavior.TraversalSummaryBadge: String;
begin
  Result := Format('[Parkour:%s H=%.2fm]', [
    TraversalActionToDisplayName(FLastProbe.Action),
    FLastProbe.ObstacleHeightAboveFeet
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleTraversalBehavior,
    ['Animation & Rigging', 'Parkour Traversal & Warp Scanner (TCastleTraversalBehavior)']);

end.
