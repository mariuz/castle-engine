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

{ Stateless helper for Procedural Foliage Wind Gust Field & Shockwave Studio (Phase 364). }
unit ToolWindStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleWindField;

type
  TWindStudioHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindWindDirectorInHierarchy(const Root: TComponent): TCastleWindFieldDirector;
    class function SpawnForestWindShockwaveDemo(const Root, DesignOwner: TComponent;
      out Director: TCastleWindFieldDirector): Boolean;
    class function GenerateWindReport(const Director: TCastleWindFieldDirector): String;
  end;

implementation

class function TWindStudioHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TWindStudioHelper.FindWindDirectorInHierarchy(const Root: TComponent): TCastleWindFieldDirector;

  function WalkTransform(const T: TCastleTransform): TCastleWindFieldDirector;
  var
    I: Integer;
  begin
    if T is TCastleWindFieldDirector then
      Exit(TCastleWindFieldDirector(T));
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
  if Root is TCastleWindFieldDirector then Exit(TCastleWindFieldDirector(Root));
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
    if Root.Components[I] is TCastleWindFieldDirector then
      Exit(TCastleWindFieldDirector(Root.Components[I]));
end;

class function TWindStudioHelper.SpawnForestWindShockwaveDemo(
  const Root, DesignOwner: TComponent;
  out Director: TCastleWindFieldDirector): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  FloorBox: TCastleBox;
begin
  Result := False;
  Director := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('WindGroveMeadowFloor') = nil then
  begin
    FloorBox := TCastleBox.Create(OwnerComp);
    FloorBox.Name := 'WindGroveMeadowFloor';
    FloorBox.Size := Vector3(24.0, 0.4, 24.0);
    FloorBox.Translation := Vector3(0.0, -0.2, 0.0);
    FloorBox.Color := Vector4(0.18, 0.28, 0.18, 1.0);
    Vp.Items.Add(FloorBox);
  end;

  Director := FindWindDirectorInHierarchy(Root);
  if Director = nil then
  begin
    Director := TCastleWindFieldDirector.Create(OwnerComp);
    Director.Name := 'WindFieldDirector1';
    Director.Preset := wbpGentleSpringBreeze;
    Vp.Items.Add(Director);
  end;
  Result := True;
end;

class function TWindStudioHelper.GenerateWindReport(
  const Director: TCastleWindFieldDirector): String;
var
  OriginSample, EastSample: TPivotPainterWindSample;
begin
  if Director = nil then
    Exit('# Procedural Foliage Wind & Shockwave Report' + LineEnding + LineEnding +
         '_No `TCastleWindFieldDirector` found in design._');

  OriginSample := Director.SamplePivotWindAtWorld(Vector3(0, 0, 0), 5.0);
  EastSample := Director.SamplePivotWindAtWorld(Vector3(8, 0, 0), 5.0);

  Result :=
    '# Procedural Foliage Wind Gust Field & Shockwave Report (Phase 364)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [Director.Name, WindPresetToString(Director.Preset)]) + LineEnding +
    Format('| **Azimuth & Base/Gust** | `%.0f deg` / `Base=%.1f m/s` + `Gust=%.1f m/s` (`%.2f Hz`) |', [
      Director.WindAzimuthDeg, Director.BaseWindSpeedMps, Director.GustAmplitudeMps, Director.GustFrequencyHz]) + LineEnding +
    Format('| **Active Shockwave Rings** | **`%d`** (`Elapsed = %.2fs`) |', [
      Director.ActiveShockwaveCount, Director.ElapsedTimeSec]) + LineEnding +
    Format('| **Center 5m Tree Bend** | `Trunk=(%.2f, %.2f)m` / `Branch=(%.2f, %.2f)m` |', [
      OriginSample.TrunkBendOffsetMeters.X, OriginSample.TrunkBendOffsetMeters.Z,
      OriginSample.BranchSwayOffsetMeters.X, OriginSample.BranchSwayOffsetMeters.Z]) + LineEnding +
    Format('| **East (+8m) Shockwave** | `NetSpeed=%.2f m/s` (`ShockContrib=%.2f m/s`) |', [
      EastSample.NetWindVelocityMps.Length, EastSample.ShockwaveContributionMps]);
end;

end.
