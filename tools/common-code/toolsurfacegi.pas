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

{ Stateless helper for Lumen-Style Surface Cache SH2 GI Probe Studio (Phase 357). }
unit ToolSurfaceGi;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleSurfaceGi;

type
  TSurfaceGiHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindGiGridInHierarchy(const Root: TComponent): TCastleSurfaceGiGrid;
    class function SpawnCornellBounceAndRoofDemo(const Root, DesignOwner: TComponent;
      out GiGrid: TCastleSurfaceGiGrid): Boolean;
    class function GenerateSurfaceGiReport(const GiGrid: TCastleSurfaceGiGrid): String;
  end;

implementation

class function TSurfaceGiHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TSurfaceGiHelper.FindGiGridInHierarchy(const Root: TComponent): TCastleSurfaceGiGrid;

  function WalkTransform(const T: TCastleTransform): TCastleSurfaceGiGrid;
  var
    I: Integer;
  begin
    if T is TCastleSurfaceGiGrid then
      Exit(TCastleSurfaceGiGrid(T));
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
  if Root is TCastleSurfaceGiGrid then Exit(TCastleSurfaceGiGrid(Root));
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
    if Root.Components[I] is TCastleSurfaceGiGrid then
      Exit(TCastleSurfaceGiGrid(Root.Components[I]));
end;

class function TSurfaceGiHelper.SpawnCornellBounceAndRoofDemo(const Root, DesignOwner: TComponent;
  out GiGrid: TCastleSurfaceGiGrid): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;

  procedure EnsureColoredWall(const AName: String; const ASize, APos: TVector3; const ACol: TCastleColor);
  var
    B: TCastleBox;
  begin
    if OwnerComp.FindComponent(AName) <> nil then Exit;
    B := TCastleBox.Create(OwnerComp);
    B.Name := AName;
    B.Size := ASize;
    B.Translation := APos;
    B.Color := ACol;
    Vp.Items.Add(B);
  end;

begin
  Result := False;
  GiGrid := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  { Neutral stone floor }
  EnsureColoredWall('CornellFloor', Vector3(11.0, 0.4, 12.0), Vector3(0.0, -0.2, 0.0),
    Vector4(0.62, 0.62, 0.62, 1.0));
  { Saturated Red West Wall (-X) for red indirect color bleeding }
  EnsureColoredWall('CornellRedWestWall', Vector3(0.4, 4.2, 11.0), Vector3(-4.4, 2.1, 0.0),
    Vector4(0.95, 0.12, 0.10, 1.0));
  { Saturated Blue East Wall (+X) for blue indirect color bleeding }
  EnsureColoredWall('CornellBlueEastWall', Vector3(0.4, 4.2, 11.0), Vector3(4.4, 2.1, 0.0),
    Vector4(0.10, 0.22, 0.96, 1.0));
  { Half-courtyard Bunker Roof covering Z in [-6.0 .. -0.4] (leaving Z > 0 open to sky!) }
  EnsureColoredWall('CornellNorthBunkerRoof', Vector3(9.2, 0.4, 5.6), Vector3(0.0, 3.8, -3.2),
    Vector4(0.32, 0.34, 0.38, 1.0));

  GiGrid := FindGiGridInHierarchy(Root);
  if GiGrid = nil then
  begin
    GiGrid := TCastleSurfaceGiGrid.Create(OwnerComp);
    GiGrid.Name := 'SurfaceGiGrid1';
    GiGrid.Preset := sgpCornellColorBleedRoom;
    Vp.Items.Add(GiGrid);
  end;

  GiGrid.BakeIrradianceProbes(Vp.Items);
  Result := True;
end;

class function TSurfaceGiHelper.GenerateSurfaceGiReport(const GiGrid: TCastleSurfaceGiGrid): String;
var
  S: TSurfaceGiBakeStats;
  WestIrrad, EastIrrad: TVector3;
begin
  if GiGrid = nil then
    Exit('# Surface Cache SH2 GI Probe Report' + LineEnding + LineEnding +
         '_No `TCastleSurfaceGiGrid` found in design._');

  S := GiGrid.BakeStats;
  WestIrrad := GiGrid.SampleIrradianceAtWorld(Vector3(-3.0, 1.2, 0.0), Vector3(-1, 0, 0));
  EastIrrad := GiGrid.SampleIrradianceAtWorld(Vector3(3.0, 1.2, 0.0), Vector3(1, 0, 0));

  Result :=
    '# Lumen Surface Cache SH2 GI Probe & Sky-Occlusion Report (Phase 357)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component** | `%s` (%s) |', [GiGrid.Name, SurfaceGiPresetToString(GiGrid.Preset)]) + LineEnding +
    Format('| **3D Probe Lattice** | `%dx%dx%d` (`%d` L0+L1 SH2 probes, `%d` rays/probe) |', [
      GiGrid.GridX, GiGrid.GridY, GiGrid.GridZ, S.TotalProbes, GiGrid.RaysPerProbe]) + LineEnding +
    Format('| **WorldRay Bake Totals** | `%d` rays (`%d` sky escapes / `%d` bounce hits) |', [
      S.RaysCastCount, S.SkyHitCount, S.BounceSurfaceHitCount]) + LineEnding +
    Format('| **Mean Sky Visibility & Luma** | `%.1f%%` sky open | `Luma = %.3f` |', [
      S.MeanSkyVisibility * 100.0, S.MeanAmbientLuminance]) + LineEnding +
    Format('| **West (-X) SH2 Irradiance** | `RGB(%.3f, %.3f, %.3f)` |', [
      WestIrrad.X, WestIrrad.Y, WestIrrad.Z]) + LineEnding +
    Format('| **East (+X) SH2 Irradiance** | `RGB(%.3f, %.3f, %.3f)` |', [
      EastIrrad.X, EastIrrad.Y, EastIrrad.Z]);
end;

end.
