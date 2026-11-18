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

{ Stateless helper for Grid2D Cellular Fire Spread & Ash Studio (Phase 372). }
unit ToolFireGrid2D;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleFireGrid2D;

type
  TFireGrid2DHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindFireGridInHierarchy(const Root: TComponent): TCastleFireSpreadGrid;
    class function SpawnPrairieFireGridDemo(const Root, DesignOwner: TComponent;
      out Grid: TCastleFireSpreadGrid): Boolean;
    class function GenerateFireGridReport(const Grid: TCastleFireSpreadGrid): String;
  end;

implementation

class function TFireGrid2DHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TFireGrid2DHelper.FindFireGridInHierarchy(
  const Root: TComponent): TCastleFireSpreadGrid;

  function WalkTransform(const T: TCastleTransform): TCastleFireSpreadGrid;
  var
    I: Integer;
  begin
    if T is TCastleFireSpreadGrid then
      Exit(TCastleFireSpreadGrid(T));
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
  if Root is TCastleFireSpreadGrid then Exit(TCastleFireSpreadGrid(Root));
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
    if Root.Components[I] is TCastleFireSpreadGrid then
      Exit(TCastleFireSpreadGrid(Root.Components[I]));
end;

class function TFireGrid2DHelper.SpawnPrairieFireGridDemo(
  const Root, DesignOwner: TComponent;
  out Grid: TCastleFireSpreadGrid): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
begin
  Result := False;
  Grid := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  Grid := FindFireGridInHierarchy(Root);
  if Grid = nil then
  begin
    Grid := TCastleFireSpreadGrid.Create(OwnerComp);
    Grid.Name := 'FireSpreadGrid1';
    Grid.Preset := fgpDryGrasslandPrairie;
    Vp.Items.Add(Grid);
  end;
  Result := True;
end;

class function TFireGrid2DHelper.GenerateFireGridReport(
  const Grid: TCastleFireSpreadGrid): String;
var
  St: TFireGridStats;
begin
  if Grid = nil then
    Exit('# Grid2D Cellular Fire Spread & Ash Report' + LineEnding + LineEnding +
         '_No `TCastleFireSpreadGrid` found in design._');

  St := Grid.Stats;
  Result :=
    '# Grid2D Cellular Fire Spread & Ash Report (Phase 372)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Scenario** | `%s` (%s) |', [Grid.Name, FirePresetToString(Grid.Preset)]) + LineEnding +
    Format('| **Grid & Ignition Gate** | `%d x %d` (`%.1fm`) / `Ignition = %.0f C` (`MaxTemp = %.0f C`) |', [
      Grid.GridResolution, Grid.GridResolution, Grid.WorldSizeMeters,
      Grid.IgnitionThresholdC, St.MaxTemperatureC]) + LineEnding +
    Format('| **Wind & Monsoon Rain** | `Azimuth = %.0f deg` at `%.1f m/s` / `Rain = %.0f%%` |', [
      Grid.WindDirectionDeg, Grid.WindSpeedMps, Grid.RainIntensity * 100.0]) + LineEnding +
    Format('| **Active Burning Cells** | **`%d`** |', [St.BurningCells]) + LineEnding +
    Format('| **Charred Ash / Unburned / Stone** | `%d` ash / `%d` unburned / `%d` stone firebreak |', [
      St.CharredAshCells, St.UnburnedFuelCells, St.StoneFirebreakCells]);
end;

end.
