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

{ Contextual Paired Animation Synchronizer with relative docking slots,
  approach-cone & WorldRay wall-clearance gating, Hermite root warp, and
  synchronized IK contact windows (Phase 358 — UE UContextualAnimSceneAsset). }
unit CastleContextualAnim;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Built-in multi-actor paired interaction presets. }
  TContextualAnimPreset = (
    capCustom,
    capStealthRearTakedown,
    capFrontParryRiposteFinisher,
    capCoOpWallBoostLift,
    capChestOpenDualTurnKey
  );

  { Pre-trigger eligibility, approach angle, and obstacle clearance result. }
  TContextualDockCheckResult = record
    CanTrigger: Boolean;
    BlockReason: String;
    TargetAnchorWorldPos: TVector3;
    TargetForwardWorldDir: TVector3;
    DesiredInstigatorDockWorldPos: TVector3;
    DesiredInstigatorForwardWorldDir: TVector3;
    InstigatorDistanceMeters: Single;
    ApproachAngleDiffDeg: Single;
    BlockedByWallCollision: Boolean;
  end;

  { Per-frame synchronized dual-actor pose & IK contact socket readout. }
  TContextualSyncFramePose = record
    NormalizedTime: Single;
    WarpAlpha: Single;
    InContactSyncWindow: Boolean;
    InstigatorWorldPos: TVector3;
    InstigatorForwardDir: TVector3;
    TargetWorldPos: TVector3;
    ContactHandIkWorldPos: TVector3;
  end;

  { Dual-actor contextual animation synchronizer matching Unreal Engine 6.0+
    UContextualAnimSceneAsset for stealth takedowns, parry finishers, and co-op boosts. }
  TCastleContextualAnimScene = class(TCastleTransform)
  private
    FPreset: TContextualAnimPreset;
    FDockLocalOffset: TVector3;
    FInstigatorFacesOppositeTarget: Boolean;
    FMaxTriggerDistance: Single;
    FMaxApproachAngleDeg: Single;
    FDurationSec: Single;
    FWarpEndNormalizedTime: Single;
    FContactStartNorm: Single;
    FContactEndNorm: Single;
    FLiftHeightMeters: Single;
    FWaistProbeHeight: Single;
    FShowDebugDockSlots: Boolean;
    FInstigatorActor: TCastleTransform;
    FTargetActor: TCastleTransform;
    FActive: Boolean;
    FElapsedSec: Single;
    FStartInstigatorWorldPos: TVector3;
    FStartInstigatorForwardDir: TVector3;
    FLockedDockCheck: TContextualDockCheckResult;
    FLastPose: TContextualSyncFramePose;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TContextualAnimPreset);
    procedure SetMaxTriggerDistance(const AValue: Single);
    procedure SetMaxApproachAngleDeg(const AValue: Single);
    procedure SetDurationSec(const AValue: Single);
    procedure SetWarpEndNormalizedTime(const AValue: Single);
    procedure SetLiftHeightMeters(const AValue: Single);
    procedure SetShowDebugDockSlots(const AValue: Boolean);
    procedure SetInstigatorActor(const AValue: TCastleTransform);
    procedure SetTargetActor(const AValue: TCastleTransform);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParamsOnly(const APreset: TContextualAnimPreset);
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
    procedure RebuildDockPreviewMesh;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function EvaluateDockingEligibility(
      const AInstigator, ATarget: TCastleTransform;
      const AWorldRoot: TCastleAbstractRootTransform): TContextualDockCheckResult;
    function BeginSynchronizedScene(
      const AInstigator, ATarget: TCastleTransform;
      const AWorldRoot: TCastleAbstractRootTransform): Boolean;
    function EvaluatePoseAtNormalizedTime(const ANormTime: Single): TContextualSyncFramePose;
    function StepSynchronizedScene(const Dt: Single): TContextualSyncFramePose;
    function ContextualSummaryBadge: String;
    property InstigatorActor: TCastleTransform read FInstigatorActor write SetInstigatorActor;
    property TargetActor: TCastleTransform read FTargetActor write SetTargetActor;
    property Active: Boolean read FActive;
    property LastDockCheck: TContextualDockCheckResult read FLockedDockCheck;
    property LastPose: TContextualSyncFramePose read FLastPose;
  published
    property Preset: TContextualAnimPreset read FPreset write SetPreset default capStealthRearTakedown;
    property MaxTriggerDistance: Single read FMaxTriggerDistance write SetMaxTriggerDistance {$ifdef FPC}default 3.0{$endif};
    property MaxApproachAngleDeg: Single read FMaxApproachAngleDeg write SetMaxApproachAngleDeg {$ifdef FPC}default 65.0{$endif};
    property DurationSec: Single read FDurationSec write SetDurationSec {$ifdef FPC}default 1.40{$endif};
    property WarpEndNormalizedTime: Single read FWarpEndNormalizedTime write SetWarpEndNormalizedTime {$ifdef FPC}default 0.35{$endif};
    property LiftHeightMeters: Single read FLiftHeightMeters write SetLiftHeightMeters {$ifdef FPC}default 0.0{$endif};
    property ShowDebugDockSlots: Boolean read FShowDebugDockSlots write SetShowDebugDockSlots default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function ContextualPresetToString(const APreset: TContextualAnimPreset): String;

implementation

uses StrUtils, fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function ContextualPresetToString(const APreset: TContextualAnimPreset): String;
begin
  case APreset of
    capCustom: Result := 'Custom Paired Scene';
    capStealthRearTakedown: Result := 'Stealth Rear Takedown (Behind -Z)';
    capFrontParryRiposteFinisher: Result := 'Front Parry & Riposte Finisher';
    capCoOpWallBoostLift: Result := 'Co-Op Wall Boost & Vertical Lift';
    capChestOpenDualTurnKey: Result := 'Dual-Key Vault Synchronized Open';
  end;
end;

function SmoothStep01(const X: Single): Single;
var
  T: Single;
begin
  T := EnsureRange(X, 0.0, 1.0);
  Result := T * T * (3.0 - 2.0 * T);
end;

{ TCastleContextualAnimScene ------------------------------------------------- }

constructor TCastleContextualAnimScene.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := capStealthRearTakedown;
  FMaxTriggerDistance := 3.0;
  FMaxApproachAngleDeg := 65.0;
  FDurationSec := 1.40;
  FWarpEndNormalizedTime := 0.35;
  FContactStartNorm := 0.35;
  FContactEndNorm := 0.82;
  FLiftHeightMeters := 0.0;
  FWaistProbeHeight := 0.95;
  FShowDebugDockSlots := True;
  FActive := False;
  FElapsedSec := 0.0;
  ApplyPresetParamsOnly(capStealthRearTakedown);
  RebuildDockPreviewMesh;
end;

destructor TCastleContextualAnimScene.Destroy;
begin
  InstigatorActor := nil;
  TargetActor := nil;
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleContextualAnimScene.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FInstigatorActor then FInstigatorActor := nil;
    if AComponent = FTargetActor then FTargetActor := nil;
  end;
end;

procedure TCastleContextualAnimScene.SetInstigatorActor(const AValue: TCastleTransform);
begin
  if FInstigatorActor = AValue then Exit;
  if FInstigatorActor <> nil then FInstigatorActor.RemoveFreeNotification(Self);
  FInstigatorActor := AValue;
  if FInstigatorActor <> nil then FInstigatorActor.FreeNotification(Self);
end;

procedure TCastleContextualAnimScene.SetTargetActor(const AValue: TCastleTransform);
begin
  if FTargetActor = AValue then Exit;
  if FTargetActor <> nil then FTargetActor.RemoveFreeNotification(Self);
  FTargetActor := AValue;
  if FTargetActor <> nil then FTargetActor.FreeNotification(Self);
end;

procedure TCastleContextualAnimScene.ApplyPresetParamsOnly(const APreset: TContextualAnimPreset);
begin
  case APreset of
    capStealthRearTakedown, capCustom:
      begin
        { Target forward is -Z in CGE; +1.05 Z is 1.05m directly BEHIND Target }
        FDockLocalOffset := Vector3(0.0, 0.0, 1.05);
        FInstigatorFacesOppositeTarget := False;
        FMaxTriggerDistance := 3.0;
        FMaxApproachAngleDeg := 65.0;
        FDurationSec := 1.40;
        FWarpEndNormalizedTime := 0.35;
        FContactStartNorm := 0.35;
        FContactEndNorm := 0.82;
        FLiftHeightMeters := 0.0;
      end;
    capFrontParryRiposteFinisher:
      begin
        { 1.25m in FRONT of Target (-Z), facing opposite Target }
        FDockLocalOffset := Vector3(0.0, 0.0, -1.25);
        FInstigatorFacesOppositeTarget := True;
        FMaxTriggerDistance := 3.4;
        FMaxApproachAngleDeg := 70.0;
        FDurationSec := 1.25;
        FWarpEndNormalizedTime := 0.30;
        FContactStartNorm := 0.30;
        FContactEndNorm := 0.78;
        FLiftHeightMeters := 0.0;
      end;
    capCoOpWallBoostLift:
      begin
        FDockLocalOffset := Vector3(0.0, 0.0, 0.90);
        FInstigatorFacesOppositeTarget := False;
        FMaxTriggerDistance := 3.2;
        FMaxApproachAngleDeg := 85.0;
        FDurationSec := 1.60;
        FWarpEndNormalizedTime := 0.35;
        FContactStartNorm := 0.35;
        FContactEndNorm := 1.00;
        FLiftHeightMeters := 2.10;
      end;
    capChestOpenDualTurnKey:
      begin
        FDockLocalOffset := Vector3(-0.65, 0.0, -0.85);
        FInstigatorFacesOppositeTarget := True;
        FMaxTriggerDistance := 2.8;
        FMaxApproachAngleDeg := 80.0;
        FDurationSec := 1.80;
        FWarpEndNormalizedTime := 0.40;
        FContactStartNorm := 0.40;
        FContactEndNorm := 0.95;
        FLiftHeightMeters := 0.0;
      end;
  end;
  RebuildDockPreviewMesh;
end;

procedure TCastleContextualAnimScene.SetPreset(const AValue: TContextualAnimPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> capCustom then
    ApplyPresetParamsOnly(AValue);
end;

procedure TCastleContextualAnimScene.SetMaxTriggerDistance(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.5, 25.0);
  if SameValue(FMaxTriggerDistance, V, 1e-4) then Exit;
  FMaxTriggerDistance := V;
end;

procedure TCastleContextualAnimScene.SetMaxApproachAngleDeg(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 5.0, 180.0);
  if SameValue(FMaxApproachAngleDeg, V, 1e-4) then Exit;
  FMaxApproachAngleDeg := V;
end;

procedure TCastleContextualAnimScene.SetDurationSec(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.2, 15.0);
  if SameValue(FDurationSec, V, 1e-4) then Exit;
  FDurationSec := V;
end;

procedure TCastleContextualAnimScene.SetWarpEndNormalizedTime(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.05, 0.95);
  if SameValue(FWarpEndNormalizedTime, V, 1e-4) then Exit;
  FWarpEndNormalizedTime := V;
end;

procedure TCastleContextualAnimScene.SetLiftHeightMeters(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 10.0);
  if SameValue(FLiftHeightMeters, V, 1e-4) then Exit;
  FLiftHeightMeters := V;
end;

procedure TCastleContextualAnimScene.SetShowDebugDockSlots(const AValue: Boolean);
begin
  if FShowDebugDockSlots = AValue then Exit;
  FShowDebugDockSlots := AValue;
  if not FShowDebugDockSlots then
    ClearTransientScene
  else
    RebuildDockPreviewMesh;
end;

function TCastleContextualAnimScene.EvaluateDockingEligibility(
  const AInstigator, ATarget: TCastleTransform;
  const AWorldRoot: TCastleAbstractRootTransform): TContextualDockCheckResult;
var
  RootWorld: TCastleAbstractRootTransform;
  TargetPos, TargetFwd, TargetRight, DockPos, DesiredApproachFromTarget,
  ActualFromTarget, RayStart, RayVec: TVector3;
  RayLen, CosAng: Single;
  RayHit: TRayCollision;
  K: Integer;
  HitItem: TCastleTransform;
begin
  FillChar(Result, SizeOf(Result), 0);
  if (AInstigator = nil) or (ATarget = nil) then
  begin
    Result.BlockReason := 'MISSING_ACTORS';
    Exit;
  end;

  TargetPos := ATarget.WorldTranslation;
  TargetFwd := ATarget.Direction;
  TargetFwd.Y := 0.0;
  if TargetFwd.LengthSqr < 1e-6 then
    TargetFwd := Vector3(0, 0, -1)
  else
    TargetFwd := TargetFwd.Normalize;

  TargetRight := TVector3.CrossProduct(TargetFwd, Vector3(0, 1, 0)).Normalize;

  { Map FDockLocalOffset where -Z is TargetFwd and +X is TargetRight }
  DockPos := TargetPos
    + TargetRight * FDockLocalOffset.X
    + Vector3(0, FDockLocalOffset.Y, 0)
    + TargetFwd * (-FDockLocalOffset.Z);

  Result.TargetAnchorWorldPos := TargetPos;
  Result.TargetForwardWorldDir := TargetFwd;
  Result.DesiredInstigatorDockWorldPos := DockPos;
  if FInstigatorFacesOppositeTarget then
    Result.DesiredInstigatorForwardWorldDir := -TargetFwd
  else
    Result.DesiredInstigatorForwardWorldDir := TargetFwd;

  Result.InstigatorDistanceMeters := PointsDistance(AInstigator.WorldTranslation, TargetPos);
  if Result.InstigatorDistanceMeters > FMaxTriggerDistance then
  begin
    Result.BlockReason := 'DISTANCE_OUT_OF_RANGE';
    FLockedDockCheck := Result;
    Exit;
  end;

  DesiredApproachFromTarget := DockPos - TargetPos;
  DesiredApproachFromTarget.Y := 0.0;
  ActualFromTarget := AInstigator.WorldTranslation - TargetPos;
  ActualFromTarget.Y := 0.0;
  if (DesiredApproachFromTarget.LengthSqr > 1e-6) and (ActualFromTarget.LengthSqr > 1e-6) then
  begin
    CosAng := TVector3.DotProduct(DesiredApproachFromTarget.Normalize, ActualFromTarget.Normalize);
    Result.ApproachAngleDiffDeg := RadToDeg(ArcCos(EnsureRange(CosAng, -1.0, 1.0)));
  end else
    Result.ApproachAngleDiffDeg := 0.0;

  if Result.ApproachAngleDiffDeg > FMaxApproachAngleDeg then
  begin
    Result.BlockReason := 'APPROACH_ANGLE_MISMATCH';
    FLockedDockCheck := Result;
    Exit;
  end;

  if AWorldRoot <> nil then
    RootWorld := AWorldRoot
  else
    RootWorld := ATarget.World;

  if RootWorld <> nil then
  begin
    RayStart := TargetPos + Vector3(0, FWaistProbeHeight, 0);
    RayVec := (DockPos + Vector3(0, FWaistProbeHeight, 0)) - RayStart;
    RayLen := RayVec.Length;
    if RayLen > 0.05 then
    begin
      RayHit := RootWorld.WorldRay(RayStart, RayVec * (1.0 / RayLen));
      try
        if (RayHit <> nil) and (RayHit.Distance <= RayLen + 0.18) then
        begin
          for K := 0 to RayHit.Count - 1 do
          begin
            HitItem := RayHit[K].Item;
            if (HitItem = nil) or (HitItem = RootWorld) or (HitItem = Self) or
               (HitItem = AInstigator) or (HitItem = ATarget) then
              Continue;
            if csTransient in HitItem.ComponentStyle then
              Continue;
            Result.BlockedByWallCollision := True;
            Result.BlockReason := 'OBSTACLE_BLOCKS_DOCK_SLOT';
            FLockedDockCheck := Result;
            Exit;
          end;
        end;
      finally
        FreeAndNil(RayHit);
      end;
    end;
  end;

  Result.CanTrigger := True;
  Result.BlockReason := '';
  FLockedDockCheck := Result;
end;

function TCastleContextualAnimScene.BeginSynchronizedScene(
  const AInstigator, ATarget: TCastleTransform;
  const AWorldRoot: TCastleAbstractRootTransform): Boolean;
var
  CheckRes: TContextualDockCheckResult;
begin
  InstigatorActor := AInstigator;
  TargetActor := ATarget;
  CheckRes := EvaluateDockingEligibility(AInstigator, ATarget, AWorldRoot);
  if not CheckRes.CanTrigger then
  begin
    FActive := False;
    Exit(False);
  end;

  FStartInstigatorWorldPos := AInstigator.WorldTranslation;
  FStartInstigatorForwardDir := AInstigator.Direction;
  if FStartInstigatorForwardDir.LengthSqr < 1e-6 then
    FStartInstigatorForwardDir := CheckRes.DesiredInstigatorForwardWorldDir
  else
    FStartInstigatorForwardDir := FStartInstigatorForwardDir.Normalize;

  FElapsedSec := 0.0;
  FActive := True;
  FLastPose := EvaluatePoseAtNormalizedTime(0.0);
  if FShowDebugDockSlots then
    RebuildDockPreviewMesh;
  Result := True;
end;

function TCastleContextualAnimScene.EvaluatePoseAtNormalizedTime(
  const ANormTime: Single): TContextualSyncFramePose;
var
  U, LiftU: Single;
  BlendedDir, DockPos: TVector3;
begin
  U := EnsureRange(ANormTime, 0.0, 1.0);
  Result.NormalizedTime := U;
  Result.WarpAlpha := SmoothStep01(U / Max(0.05, FWarpEndNormalizedTime));
  Result.InContactSyncWindow := (U >= FContactStartNorm) and (U <= FContactEndNorm);

  DockPos := FLockedDockCheck.DesiredInstigatorDockWorldPos;
  if (FLiftHeightMeters > 0.0) and (U > FContactStartNorm) then
  begin
    LiftU := SmoothStep01((U - FContactStartNorm) / Max(0.05, 1.0 - FContactStartNorm));
    DockPos.Y := DockPos.Y + FLiftHeightMeters * LiftU;
  end;

  Result.InstigatorWorldPos := Lerp(Result.WarpAlpha, FStartInstigatorWorldPos, DockPos);
  BlendedDir := Lerp(Result.WarpAlpha, FStartInstigatorForwardDir,
    FLockedDockCheck.DesiredInstigatorForwardWorldDir);
  if BlendedDir.LengthSqr > 1e-6 then
    Result.InstigatorForwardDir := BlendedDir.Normalize
  else
    Result.InstigatorForwardDir := Vector3(0, 0, -1);

  Result.TargetWorldPos := FLockedDockCheck.TargetAnchorWorldPos;
  { Synchronized hand/shoulder IK contact socket directly between docked pair }
  Result.ContactHandIkWorldPos :=
    Lerp(0.5, Result.InstigatorWorldPos, Result.TargetWorldPos) + Vector3(0.0, 1.25, 0.0);
end;

function TCastleContextualAnimScene.StepSynchronizedScene(const Dt: Single): TContextualSyncFramePose;
var
  NormT: Single;
begin
  if not FActive then
    Exit(FLastPose);

  FElapsedSec := FElapsedSec + Max(0.0, Dt);
  NormT := EnsureRange(FElapsedSec / Max(0.1, FDurationSec), 0.0, 1.0);
  Result := EvaluatePoseAtNormalizedTime(NormT);
  FLastPose := Result;

  if FInstigatorActor <> nil then
  begin
    FInstigatorActor.Translation := Result.InstigatorWorldPos;
    FInstigatorActor.Direction := Result.InstigatorForwardDir;
  end;

  if NormT >= 1.0 then
    FActive := False;
  if FShowDebugDockSlots then
    RebuildDockPreviewMesh;
end;

procedure TCastleContextualAnimScene.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientContextualAnimPreview';
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

procedure TCastleContextualAnimScene.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleContextualAnimScene.RebuildDockPreviewMesh;
var
  Verts, Cols: TVector3List;
  TargetMarker, DockMarker, ContactMarker: TVector3;

  procedure EmitDiamond(const Pt: TVector3; const R: Single; const Col: TVector3);
  var
    TopP, BotP, E1, E2, E3, E4: TVector3;
  begin
    TopP := Pt + Vector3(0, R, 0);
    BotP := Pt + Vector3(0, -R, 0);
    E1 := Pt + Vector3(R, 0, 0);
    E2 := Pt + Vector3(0, 0, R);
    E3 := Pt + Vector3(-R, 0, 0);
    E4 := Pt + Vector3(0, 0, -R);
    Verts.Add(TopP); Verts.Add(E1); Verts.Add(E2);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
    Verts.Add(TopP); Verts.Add(E2); Verts.Add(E3);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
    Verts.Add(TopP); Verts.Add(E3); Verts.Add(E4);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
    Verts.Add(TopP); Verts.Add(E4); Verts.Add(E1);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
    Verts.Add(BotP); Verts.Add(E2); Verts.Add(E1);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
    Verts.Add(BotP); Verts.Add(E3); Verts.Add(E2);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
    Verts.Add(BotP); Verts.Add(E4); Verts.Add(E3);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
    Verts.Add(BotP); Verts.Add(E1); Verts.Add(E4);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
  end;

begin
  if not FShowDebugDockSlots then Exit;
  EnsureTransientScene;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    TargetMarker := Vector3(0, 0.25, 0);
    DockMarker := FDockLocalOffset + Vector3(0, 0.25, 0);
    ContactMarker := (TargetMarker + DockMarker) * 0.5 + Vector3(0, 1.0, 0);

    EmitDiamond(TargetMarker, 0.28, Vector3(0.95, 0.32, 0.28));
    EmitDiamond(DockMarker, 0.28, Vector3(0.24, 0.88, 0.56));
    EmitDiamond(ContactMarker, 0.18, Vector3(1.0, 0.84, 0.22));

    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleContextualAnimScene.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('dx', FDockLocalOffset.X);
    Obj.Add('dy', FDockLocalOffset.Y);
    Obj.Add('dz', FDockLocalOffset.Z);
    Obj.Add('faceOpp', FInstigatorFacesOppositeTarget);
    Obj.Add('maxDist', FMaxTriggerDistance);
    Obj.Add('maxAng', FMaxApproachAngleDeg);
    Obj.Add('dur', FDurationSec);
    Obj.Add('liftH', FLiftHeightMeters);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleContextualAnimScene.SetConfigJson(const AValue: String);
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
      if (PresetOrd >= Ord(Low(TContextualAnimPreset))) and
         (PresetOrd <= Ord(High(TContextualAnimPreset))) then
        FPreset := TContextualAnimPreset(PresetOrd);
      FDockLocalOffset.X := Obj.Get('dx', FDockLocalOffset.X);
      FDockLocalOffset.Y := Obj.Get('dy', FDockLocalOffset.Y);
      FDockLocalOffset.Z := Obj.Get('dz', FDockLocalOffset.Z);
      FInstigatorFacesOppositeTarget := Obj.Get('faceOpp', FInstigatorFacesOppositeTarget);
      FMaxTriggerDistance := EnsureRange(Obj.Get('maxDist', FMaxTriggerDistance), 0.5, 25.0);
      FMaxApproachAngleDeg := EnsureRange(Obj.Get('maxAng', FMaxApproachAngleDeg), 5.0, 180.0);
      FDurationSec := EnsureRange(Obj.Get('dur', FDurationSec), 0.2, 15.0);
      FLiftHeightMeters := EnsureRange(Obj.Get('liftH', FLiftHeightMeters), 0.0, 10.0);
      RebuildDockPreviewMesh;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleContextualAnimScene.ContextualSummaryBadge: String;
begin
  Result := Format('[CtxAnim:%s t=%.2f %s]', [
    ContextualPresetToString(FPreset),
    FLastPose.NormalizedTime,
    IfThen(FLockedDockCheck.CanTrigger, 'READY', 'GATED')]);
end;

initialization
  RegisterSerializableComponent(TCastleContextualAnimScene, ['Animation', 'Contextual Paired Anim Synchronizer']);
end.
