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

{ Stateless helper for Wall-Crevice & Seam Micro-Clutter Studio (Phase 370). }
unit ToolCreviceClutter;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleCreviceClutter;

type
  TCreviceClutterHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindClutterVolumeInHierarchy(const Root: TComponent): TCastleCreviceClutterVolume;
    class function SpawnCourtyardLWallDemo(const Root, DesignOwner: TComponent;
      out Volume: TCastleCreviceClutterVolume): Boolean;
    class function GenerateCreviceReport(const Volume: TCastleCreviceClutterVolume): String;
  end;

implementation

class function TCreviceClutterHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TCreviceClutterHelper.FindClutterVolumeInHierarchy(
  const Root: TComponent): TCastleCreviceClutterVolume;

  function WalkTransform(const T: TCastleTransform): TCastleCreviceClutterVolume;
  var
    I: Integer;
  begin
    if T is TCastleCreviceClutterVolume then
      Exit(TCastleCreviceClutterVolume(T));
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
  if Root is TCastleCreviceClutterVolume then Exit(TCastleCreviceClutterVolume(Root));
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
    if Root.Components[I] is TCastleCreviceClutterVolume then
      Exit(TCastleCreviceClutterVolume(Root.Components[I]));
end;

class function TCreviceClutterHelper.SpawnCourtyardLWallDemo(
  const Root, DesignOwner: TComponent;
  out Volume: TCastleCreviceClutterVolume): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  FloorBox, NorthWall, WestWall: TCastleBox;
begin
  Result := False;
  Volume := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('CreviceCourtyardFloor') = nil then
  begin
    FloorBox := TCastleBox.Create(OwnerComp);
    FloorBox.Name := 'CreviceCourtyardFloor';
    FloorBox.Size := Vector3(16.0, 0.4, 16.0);
    FloorBox.Translation := Vector3(0.0, -0.2, 0.0);
    FloorBox.Color := Vector4(0.28, 0.27, 0.25, 1.0);
    Vp.Items.Add(FloorBox);
  end;

  if OwnerComp.FindComponent('CreviceNorthWall') = nil then
  begin
    NorthWall := TCastleBox.Create(OwnerComp);
    NorthWall.Name := 'CreviceNorthWall';
    NorthWall.Size := Vector3(13.0, 3.2, 0.6);
    NorthWall.Translation := Vector3(-0.5, 1.6, -6.0);
    NorthWall.Color := Vector4(0.46, 0.44, 0.40, 1.0);
    Vp.Items.Add(NorthWall);
  end;

  if OwnerComp.FindComponent('CreviceWestWall') = nil then
  begin
    WestWall := TCastleBox.Create(OwnerComp);
    WestWall.Name := 'CreviceWestWall';
    WestWall.Size := Vector3(0.6, 3.2, 13.0);
    WestWall.Translation := Vector3(-6.0, 1.6, -0.5);
    WestWall.Color := Vector4(0.46, 0.44, 0.40, 1.0);
    Vp.Items.Add(WestWall);
  end;

  Volume := FindClutterVolumeInHierarchy(Root);
  if Volume = nil then
  begin
    Volume := TCastleCreviceClutterVolume.Create(OwnerComp);
    Volume.Name := 'CreviceClutterVolume1';
    Volume.Preset := ccpStoneMortarRubble;
    Vp.Items.Add(Volume);
  end;

  Volume.BakeCreviceClutterFromWorld(Vp.Items);
  Result := True;
end;

class function TCreviceClutterHelper.GenerateCreviceReport(
  const Volume: TCastleCreviceClutterVolume): String;
begin
  if Volume = nil then
    Exit('# Wall-Crevice & Seam Micro-Clutter Report' + LineEnding + LineEnding +
         '_No `TCastleCreviceClutterVolume` found in design._');

  Result :=
    '# Wall-Crevice & Seam Micro-Clutter Report (Phase 370)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [Volume.Name, CrevicePresetToString(Volume.Preset)]) + LineEnding +
    Format('| **Volume & Grid** | `%.1f x %.1f m` (`%d x %d` rays, `Seed = %d`) |', [
      Volume.VolumeExtentXZ, Volume.VolumeExtentXZ,
      Volume.GridResolution, Volume.GridResolution, Volume.RandomSeed]) + LineEnding +
    Format('| **Seam Skirt Width** | **`%.2f m`** (`Density = %.0f%%`) |', [
      Volume.SeamSkirtWidthMeters, Volume.DensityProbability * 100.0]) + LineEnding +
    Format('| **Baked Crevice Clutter** | **`%d` instances** (`%d` in concave L-corners, `0` in open center) |', [
      Volume.ClutterCount, Volume.InsideCornerItemCount]);
end;

end.
