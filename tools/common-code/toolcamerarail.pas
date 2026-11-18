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

{ Stateless helper for Camera Rig Rail & Co-Op Framing Studio (Phase 352). }
unit ToolCameraRail;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleCameraRigRail;

type
  TCameraRailHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindRailInHierarchy(const Root: TComponent): TCastleCameraRigRail;
    class function FindTransformByName(const Root: TComponent; const AName: String): TCastleTransform;
    class function SpawnCameraRailDemoArena(const Root, DesignOwner: TComponent;
      out Rail: TCastleCameraRigRail;
      out Player1, Player2: TCastleTransform): Boolean;
    class function GenerateCameraRailReport(const Rail: TCastleCameraRigRail): String;
  end;

implementation

uses StrUtils;

class function TCameraRailHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TCameraRailHelper.FindRailInHierarchy(const Root: TComponent): TCastleCameraRigRail;

  function WalkTransform(const T: TCastleTransform): TCastleCameraRigRail;
  var
    I: Integer;
  begin
    if T is TCastleCameraRigRail then
      Exit(TCastleCameraRigRail(T));
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
  if Root is TCastleCameraRigRail then Exit(TCastleCameraRigRail(Root));
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
    if Root.Components[I] is TCastleCameraRigRail then
      Exit(TCastleCameraRigRail(Root.Components[I]));
end;

class function TCameraRailHelper.FindTransformByName(const Root: TComponent;
  const AName: String): TCastleTransform;
var
  C: TComponent;
begin
  Result := nil;
  if Root = nil then Exit;
  if SameText(Root.Name, AName) and (Root is TCastleTransform) then
    Exit(TCastleTransform(Root));
  C := Root.FindComponent(AName);
  if C is TCastleTransform then
    Result := TCastleTransform(C);
end;

class function TCameraRailHelper.SpawnCameraRailDemoArena(const Root, DesignOwner: TComponent;
  out Rail: TCastleCameraRigRail;
  out Player1, Player2: TCastleTransform): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  FloorBox: TCastleBox;
  P1Sphere, P2Sphere: TCastleSphere;
begin
  Result := False;
  Rail := nil;
  Player1 := nil;
  Player2 := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('CameraRailCanyonFloor') = nil then
  begin
    FloorBox := TCastleBox.Create(OwnerComp);
    FloorBox.Name := 'CameraRailCanyonFloor';
    FloorBox.Size := Vector3(44.0, 0.5, 28.0);
    FloorBox.Translation := Vector3(0.0, -0.25, 0.0);
    FloorBox.Color := Vector4(0.20, 0.22, 0.26, 1.0);
    Vp.Items.Add(FloorBox);
  end;

  Player1 := FindTransformByName(OwnerComp, 'RailPlayer1');
  if Player1 = nil then
  begin
    P1Sphere := TCastleSphere.Create(OwnerComp);
    P1Sphere.Name := 'RailPlayer1';
    P1Sphere.Radius := 0.65;
    P1Sphere.Translation := Vector3(-2.0, 0.65, 0.0);
    P1Sphere.Color := Vector4(0.22, 0.68, 1.0, 1.0);
    Vp.Items.Add(P1Sphere);
    Player1 := P1Sphere;
  end;

  Player2 := FindTransformByName(OwnerComp, 'RailPlayer2');
  if Player2 = nil then
  begin
    P2Sphere := TCastleSphere.Create(OwnerComp);
    P2Sphere.Name := 'RailPlayer2';
    P2Sphere.Radius := 0.65;
    P2Sphere.Translation := Vector3(2.0, 0.65, 0.0);
    P2Sphere.Color := Vector4(1.0, 0.56, 0.18, 1.0);
    Vp.Items.Add(P2Sphere);
    Player2 := P2Sphere;
  end;

  Rail := FindRailInHierarchy(Root);
  if Rail = nil then
  begin
    Rail := TCastleCameraRigRail.Create(OwnerComp);
    Rail.Name := 'CameraRigRail1';
    Rail.Preset := crpSideScrollerCanyon;
    Rail.CoOpEnabled := True;
    Vp.Items.Add(Rail);
  end;
  Rail.PrimaryTarget := Player1;
  Rail.SecondaryCoOpTarget := Player2;
  Rail.SnapRigImmediate(Player1.WorldTranslation, Player2.WorldTranslation, True);
  Result := True;
end;

class function TCameraRailHelper.GenerateCameraRailReport(const Rail: TCastleCameraRigRail): String;
var
  R: TCameraRailResult;
begin
  if Rail = nil then
    Exit('# Camera Rig Rail Report' + LineEnding + LineEnding + '_No `TCastleCameraRigRail` found in design._');

  R := Rail.LastResult;
  Result :=
    '# Camera Rig Rail & Co-Op Framing Studio Report (Phase 352)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component Name** | `%s` |', [Rail.Name]) + LineEnding +
    Format('| **Preset** | %s (`ClosedLoop=%s`, `%d` knots) |', [
      CameraRailPresetToString(Rail.Preset), BoolToStr(Rail.ClosedLoop, True), Rail.ControlPointCount]) + LineEnding +
    Format('| **Rail Param `u`** | `%.4f` |', [R.RailParamU]) + LineEnding +
    Format('| **Camera World Pos** | `(%.2f, %.2f, %.2f)` |', [
      R.CameraWorldPos.X, R.CameraWorldPos.Y, R.CameraWorldPos.Z]) + LineEnding +
    Format('| **Predicted Focus** | `(%.2f, %.2f, %.2f)` (`LookAhead=%.2fs`) |', [
      R.PredictedFocusWorld.X, R.PredictedFocusWorld.Y, R.PredictedFocusWorld.Z, Rail.LookAheadTimeSec]) + LineEnding +
    Format('| **Deadzone Aim Focus** | `(%.2f, %.2f, %.2f)` (`±%.2fm x ±%.2fm`) |', [
      R.DeadzoneAimWorld.X, R.DeadzoneAimWorld.Y, R.DeadzoneAimWorld.Z,
      Rail.DeadzoneHalfWidthMeters, Rail.DeadzoneHalfHeightMeters]) + LineEnding +
    Format('| **Co-Op Separation** | `%.2f m` (Split > `%.1fm` / Merge < `%.1fm`) |', [
      R.PlayerSeparationMeters, Rail.SplitDistanceMeters, Rail.MergeDistanceMeters]) + LineEnding +
    Format('| **Director Mode & FOV** | **%s** (`FOV = %.1f deg`) |', [
      IfThen(R.ShouldSplitScreen, 'SPLIT-SCREEN 2P', 'SHARED SINGLE-VIEW'), R.EffectiveFieldOfViewDeg]);
end;

end.
