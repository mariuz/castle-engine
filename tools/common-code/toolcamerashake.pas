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

{ Stateless helper for Cinematic Camera Shake, Recoil & FOV Kickback Studio (Phase 371). }
unit ToolCameraShake;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleCameraShake;

type
  TCameraShakeHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindShakeDirectorInHierarchy(const Root: TComponent): TCastleCameraShakeDirector;
    class function SpawnFiringRangeShakeDemo(const Root, DesignOwner: TComponent;
      out Director: TCastleCameraShakeDirector): Boolean;
    class function GenerateShakeReport(const Director: TCastleCameraShakeDirector): String;
  end;

implementation

class function TCameraShakeHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TCameraShakeHelper.FindShakeDirectorInHierarchy(
  const Root: TComponent): TCastleCameraShakeDirector;

  function WalkTransform(const T: TCastleTransform): TCastleCameraShakeDirector;
  var
    I: Integer;
  begin
    if T is TCastleCameraShakeDirector then
      Exit(TCastleCameraShakeDirector(T));
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
  if Root is TCastleCameraShakeDirector then Exit(TCastleCameraShakeDirector(Root));
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
    if Root.Components[I] is TCastleCameraShakeDirector then
      Exit(TCastleCameraShakeDirector(Root.Components[I]));
end;

class function TCameraShakeHelper.SpawnFiringRangeShakeDemo(
  const Root, DesignOwner: TComponent;
  out Director: TCastleCameraShakeDirector): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  BarrelBox: TCastleBox;
begin
  Result := False;
  Director := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('ExplosiveRangeBarrel') = nil then
  begin
    BarrelBox := TCastleBox.Create(OwnerComp);
    BarrelBox.Name := 'ExplosiveRangeBarrel';
    BarrelBox.Size := Vector3(0.9, 1.3, 0.9);
    BarrelBox.Translation := Vector3(0.0, 0.65, -8.0);
    BarrelBox.Color := Vector4(0.92, 0.24, 0.18, 1.0);
    Vp.Items.Add(BarrelBox);
  end;

  Director := FindShakeDirectorInHierarchy(Root);
  if Director = nil then
  begin
    Director := TCastleCameraShakeDirector.Create(OwnerComp);
    Director.Name := 'CameraShakeDirector1';
    Director.Preset := cspHeavyShotgunKickback;
    Vp.Items.Add(Director);
  end;
  Result := True;
end;

class function TCameraShakeHelper.GenerateShakeReport(
  const Director: TCastleCameraShakeDirector): String;
var
  F: TCameraShakeFrameOffset;
begin
  if Director = nil then
    Exit('# Cinematic Camera Shake, Recoil & FOV Kick Report' + LineEnding + LineEnding +
         '_No `TCastleCameraShakeDirector` found in design._');

  F := Director.LastFrame;
  Result :=
    '# Cinematic Camera Shake, Recoil & FOV Kick Report (Phase 371)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [Director.Name, CameraShakePresetToString(Director.Preset)]) + LineEnding +
    Format('| **Accessibility Scale & Cap** | `GlobalShakeScale = %.0f%%` / `MaxPitchRollCap = %.1f deg` |', [
      Director.GlobalShakeScale * 100.0, Director.MaxPitchRollCapDeg]) + LineEnding +
    Format('| **Blast Falloff Radii** | `InnerFull = %.1f m` -> `OuterZero = %.1f m` |', [
      Director.InnerFullBlastRadiusMeters, Director.OuterZeroBlastRadiusMeters]) + LineEnding +
    Format('| **Active Envelope Layers** | **`%d`** (`CombinedTrauma = %.2f`) |', [
      Director.ActiveLayerCount, F.CombinedTrauma]) + LineEnding +
    Format('| **Current Angular Offset** | `Pitch=%+.2f deg` / `Yaw=%+.2f deg` / `Roll=%+.2f deg` |', [
      F.PitchYawRollDeg.X, F.PitchYawRollDeg.Y, F.PitchYawRollDeg.Z]) + LineEnding +
    Format('| **FOV Kickback & Pos Offset** | **`%+.2f deg FOV`** / `Pos=(%+.3f, %+.3f, %+.3f)m` |', [
      F.FovDeltaDegrees, F.PositionOffsetLocal.X, F.PositionOffsetLocal.Y, F.PositionOffsetLocal.Z]);
end;

end.
