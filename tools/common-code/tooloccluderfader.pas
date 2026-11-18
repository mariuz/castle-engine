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

{ Stateless helper for Smart Camera Collision Occluder Cutaway & Foliage Parting Studio (Phase 362). }
unit ToolOccluderFader;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleOccluderFader;

type
  TOccluderFaderHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindFaderInHierarchy(const Root: TComponent): TCastleCameraOccluderFader;
    class function SpawnArpgCourtyardCutawayDemo(const Root, DesignOwner: TComponent;
      out Fader: TCastleCameraOccluderFader;
      out HeroActor, FrontWall, SidePillar: TCastleTransform): Boolean;
    class function GenerateOccluderReport(const Fader: TCastleCameraOccluderFader): String;
  end;

implementation

class function TOccluderFaderHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TOccluderFaderHelper.FindFaderInHierarchy(const Root: TComponent): TCastleCameraOccluderFader;

  function WalkTransform(const T: TCastleTransform): TCastleCameraOccluderFader;
  var
    I: Integer;
  begin
    if T is TCastleCameraOccluderFader then
      Exit(TCastleCameraOccluderFader(T));
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
  if Root is TCastleCameraOccluderFader then Exit(TCastleCameraOccluderFader(Root));
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
    if Root.Components[I] is TCastleCameraOccluderFader then
      Exit(TCastleCameraOccluderFader(Root.Components[I]));
end;

class function TOccluderFaderHelper.SpawnArpgCourtyardCutawayDemo(
  const Root, DesignOwner: TComponent;
  out Fader: TCastleCameraOccluderFader;
  out HeroActor, FrontWall, SidePillar: TCastleTransform): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  FloorBox, WallBox, PillarBox, HeroBox: TCastleBox;
begin
  Result := False;
  Fader := nil;
  HeroActor := nil;
  FrontWall := nil;
  SidePillar := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('CutawayFloor') = nil then
  begin
    FloorBox := TCastleBox.Create(OwnerComp);
    FloorBox.Name := 'CutawayFloor';
    FloorBox.Tag := OccluderIgnoreTag;
    FloorBox.Size := Vector3(20.0, 0.4, 20.0);
    FloorBox.Translation := Vector3(0.0, -0.2, 0.0);
    FloorBox.Color := Vector4(0.22, 0.26, 0.22, 1.0);
    Vp.Items.Add(FloorBox);
  end;

  FrontWall := OwnerComp.FindComponent('CastleFrontWallOccluder') as TCastleTransform;
  if FrontWall = nil then
  begin
    WallBox := TCastleBox.Create(OwnerComp);
    WallBox.Name := 'CastleFrontWallOccluder';
    WallBox.Size := Vector3(6.0, 4.2, 0.5);
    WallBox.Translation := Vector3(0.0, 2.1, 4.0);
    WallBox.Color := Vector4(0.68, 0.62, 0.54, 1.0);
    Vp.Items.Add(WallBox);
    FrontWall := WallBox;
  end;

  SidePillar := OwnerComp.FindComponent('CourtyardEastPillar') as TCastleTransform;
  if SidePillar = nil then
  begin
    PillarBox := TCastleBox.Create(OwnerComp);
    PillarBox.Name := 'CourtyardEastPillar';
    PillarBox.Size := Vector3(1.2, 4.0, 1.2);
    PillarBox.Translation := Vector3(6.5, 2.0, 4.0);
    PillarBox.Color := Vector4(0.55, 0.58, 0.64, 1.0);
    Vp.Items.Add(PillarBox);
    SidePillar := PillarBox;
  end;

  HeroActor := OwnerComp.FindComponent('CutawayHeroActor') as TCastleTransform;
  if HeroActor = nil then
  begin
    HeroBox := TCastleBox.Create(OwnerComp);
    HeroBox.Name := 'CutawayHeroActor';
    HeroBox.Tag := OccluderIgnoreTag;
    HeroBox.Size := Vector3(0.8, 1.8, 0.8);
    HeroBox.Translation := Vector3(0.0, 0.9, 0.0);
    HeroBox.Color := Vector4(0.24, 0.78, 0.98, 1.0);
    Vp.Items.Add(HeroBox);
    HeroActor := HeroBox;
  end;

  Fader := FindFaderInHierarchy(Root);
  if Fader = nil then
  begin
    Fader := TCastleCameraOccluderFader.Create(OwnerComp);
    Fader.Name := 'CameraOccluderFader1';
    Fader.Preset := ofpIsometricArpgRoofCutaway;
    Vp.Items.Add(Fader);
  end;

  Fader.StepOccluderAndFoliage(Vp.Items, Vector3(0.0, 3.2, 10.0),
    Vector3(0.0, 1.2, 0.0), [HeroActor.Translation], 0.50);
  Result := True;
end;

class function TOccluderFaderHelper.GenerateOccluderReport(
  const Fader: TCastleCameraOccluderFader): String;
var
  I: Integer;
  E: TOccluderTrackedEntry;
begin
  if Fader = nil then
    Exit('# Camera Occluder Cutaway & Foliage Parting Report' + LineEnding + LineEnding +
         '_No `TCastleCameraOccluderFader` found in design._');

  Result :=
    '# Camera Occluder Cutaway & Foliage Parting Report (Phase 362)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [Fader.Name, OccluderPresetToString(Fader.Preset)]) + LineEnding +
    Format('| **Cutaway Target Opacity** | **`%.0f%%`** (`FadeIn=%.1f/s`, `Restore=%.1f/s`) |', [
      Fader.CutawayMinOpacity * 100.0, Fader.FadeInSpeed, Fader.RestoreOpacitySpeed]) + LineEnding +
    Format('| **Active Faded Occluders** | **`%d`** (`%d` tracked) |', [
      Fader.ActiveFadedCount, Fader.TrackedCount]) + LineEnding +
    Format('| **Foliage Parting Halo** | `Radius = %.2fm` / `MaxBend = %.0f deg` (`%d` parted blades) |', [
      Fader.FoliagePartingRadius, Fader.FoliageMaxBendDegrees, Fader.PartedBladeCount]) + LineEnding + LineEnding +
    '## Tracked Occluder Transforms' + LineEnding +
    '| Transform | Opacity | Blocking Sightline |' + LineEnding +
    '| :--- | :--- | :--- |' + LineEnding;

  if Fader.TrackedCount = 0 then
    Result := Result + '| _(Sightline clear — all walls at 100% opacity)_ | `100%` | `NO` |' + LineEnding
  else
    for I := 0 to Fader.TrackedCount - 1 do
    begin
      E := Fader.GetTrackedEntry(I);
      Result := Result + Format('| `%s` | **`%.0f%%`** | `%s` |', [
        E.TransformName,
        E.CurrentOpacity * 100.0,
        BoolToStr(E.CurrentlyBlockingRay, 'YES (CUTAWAY)', 'Recovering')]) + LineEnding;
    end;
end;

end.
