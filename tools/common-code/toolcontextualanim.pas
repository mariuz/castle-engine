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

{ Stateless helper for Contextual Paired Animation & Docking Studio (Phase 358). }
unit ToolContextualAnim;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleContextualAnim;

type
  TContextualAnimHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindContextualSceneInHierarchy(const Root: TComponent): TCastleContextualAnimScene;
    class function SpawnContextualPairedDojo(const Root, DesignOwner: TComponent;
      out CtxScene: TCastleContextualAnimScene;
      out Instigator, TargetGuard, BackWall: TCastleTransform): Boolean;
    class function GenerateContextualAnimReport(const CtxScene: TCastleContextualAnimScene): String;
  end;

implementation

class function TContextualAnimHelper.FindViewport(const Root: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleViewport then Exit(TCastleViewport(Root));
  for I := 0 to Root.ComponentCount - 1 do
  begin
    Result := FindViewport(Root.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TContextualAnimHelper.FindContextualSceneInHierarchy(const Root: TComponent): TCastleContextualAnimScene;

  function WalkTransform(const T: TCastleTransform): TCastleContextualAnimScene;
  var
    I: Integer;
  begin
    if T is TCastleContextualAnimScene then
      Exit(TCastleContextualAnimScene(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := WalkTransform(T[I]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

var
  Vp: TCastleViewport;
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleContextualAnimScene then Exit(TCastleContextualAnimScene(Root));
  if Root is TCastleTransform then
  begin
    Result := WalkTransform(TCastleTransform(Root));
    if Result <> nil then Exit;
  end;
  Vp := FindViewport(Root);
  if (Vp <> nil) and (Vp.Items <> nil) then
  begin
    Result := WalkTransform(Vp.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to Root.ComponentCount - 1 do
    if Root.Components[I] is TCastleContextualAnimScene then
      Exit(TCastleContextualAnimScene(Root.Components[I]));
end;

class function TContextualAnimHelper.SpawnContextualPairedDojo(const Root, DesignOwner: TComponent;
  out CtxScene: TCastleContextualAnimScene;
  out Instigator, TargetGuard, BackWall: TCastleTransform): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  FloorBox, InstBox, GuardBox, WallBox: TCastleBox;
begin
  Result := False;
  CtxScene := nil;
  Instigator := nil;
  TargetGuard := nil;
  BackWall := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('ContextualDojoFloor') = nil then
  begin
    FloorBox := TCastleBox.Create(OwnerComp);
    FloorBox.Name := 'ContextualDojoFloor';
    FloorBox.Size := Vector3(18.0, 0.4, 18.0);
    FloorBox.Translation := Vector3(0.0, -0.2, 0.0);
    FloorBox.Color := Vector4(0.22, 0.24, 0.28, 1.0);
    Vp.Items.Add(FloorBox);
  end;

  TargetGuard := OwnerComp.FindComponent('ContextualTargetGuard') as TCastleTransform;
  if TargetGuard = nil then
  begin
    GuardBox := TCastleBox.Create(OwnerComp);
    GuardBox.Name := 'ContextualTargetGuard';
    GuardBox.Size := Vector3(0.75, 1.80, 0.55);
    GuardBox.Translation := Vector3(0.0, 0.0, 0.0);
    GuardBox.Direction := Vector3(0.0, 0.0, -1.0);
    GuardBox.Color := Vector4(0.92, 0.30, 0.26, 1.0);
    Vp.Items.Add(GuardBox);
    TargetGuard := GuardBox;
  end;

  Instigator := OwnerComp.FindComponent('ContextualHeroInstigator') as TCastleTransform;
  if Instigator = nil then
  begin
    InstBox := TCastleBox.Create(OwnerComp);
    InstBox.Name := 'ContextualHeroInstigator';
    InstBox.Size := Vector3(0.75, 1.80, 0.55);
    InstBox.Translation := Vector3(0.55, 0.0, 2.15);
    InstBox.Direction := Vector3(0.0, 0.0, -1.0);
    InstBox.Color := Vector4(0.24, 0.72, 0.98, 1.0);
    Vp.Items.Add(InstBox);
    Instigator := InstBox;
  end;

  BackWall := OwnerComp.FindComponent('ContextualTestWall') as TCastleTransform;
  if BackWall = nil then
  begin
    WallBox := TCastleBox.Create(OwnerComp);
    WallBox.Name := 'ContextualTestWall';
    WallBox.Size := Vector3(5.0, 3.0, 0.5);
    WallBox.Translation := Vector3(0.0, 1.5, 6.0);
    WallBox.Color := Vector4(0.45, 0.46, 0.50, 1.0);
    Vp.Items.Add(WallBox);
    BackWall := WallBox;
  end;

  CtxScene := FindContextualSceneInHierarchy(Root);
  if CtxScene = nil then
  begin
    CtxScene := TCastleContextualAnimScene.Create(OwnerComp);
    CtxScene.Name := 'ContextualAnimScene1';
    CtxScene.Preset := capStealthRearTakedown;
    Vp.Items.Add(CtxScene);
  end;
  CtxScene.InstigatorActor := Instigator;
  CtxScene.TargetActor := TargetGuard;
  CtxScene.EvaluateDockingEligibility(Instigator, TargetGuard, Vp.Items);
  Result := True;
end;

class function TContextualAnimHelper.GenerateContextualAnimReport(
  const CtxScene: TCastleContextualAnimScene): String;
var
  D: TContextualDockCheckResult;
  P: TContextualSyncFramePose;
begin
  if CtxScene = nil then
    Exit('# Contextual Paired Animation Report' + LineEnding + LineEnding +
         '_No `TCastleContextualAnimScene` found in design._');

  D := CtxScene.LastDockCheck;
  P := CtxScene.LastPose;
  Result :=
    '# Contextual Paired Animation & Docking Studio Report (Phase 358)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [
      CtxScene.Name, ContextualPresetToString(CtxScene.Preset)]) + LineEnding +
    Format('| **Docking Eligibility** | **`%s`** %s |', [
      BoolToStr(D.CanTrigger, 'ELIGIBLE (CLEAR)', 'BLOCKED'),
      D.BlockReason]) + LineEnding +
    Format('| **Instigator Dist / Angle** | `%.2f m` (max `%.1fm`) / `%.1f deg` (max `%.0f deg`) |', [
      D.InstigatorDistanceMeters, CtxScene.MaxTriggerDistance,
      D.ApproachAngleDiffDeg, CtxScene.MaxApproachAngleDeg]) + LineEnding +
    Format('| **Desired Dock World Pos** | `(%.2f, %.2f, %.2f)` |', [
      D.DesiredInstigatorDockWorldPos.X, D.DesiredInstigatorDockWorldPos.Y, D.DesiredInstigatorDockWorldPos.Z]) + LineEnding +
    Format('| **Sync Timeline & Warp** | `t = %.2f` (`WarpAlpha = %.2f`, `InContactWindow = %s`) |', [
      P.NormalizedTime, P.WarpAlpha, BoolToStr(P.InContactSyncWindow, True)]) + LineEnding +
    Format('| **Shared IK Contact Socket** | `(%.2f, %.2f, %.2f)` |', [
      P.ContactHandIkWorldPos.X, P.ContactHandIkWorldPos.Y, P.ContactHandIkWorldPos.Z]);
end;

end.
