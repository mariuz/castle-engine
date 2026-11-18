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

{ Stateless helper for Octahedral Billboard Impostor Atlas Studio (Phase 374). }
unit ToolOctahedralImpostor;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleOctahedralImpostor;

type
  TOctahedralImpostorHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindImpostorInHierarchy(const Root: TComponent): TCastleOctahedralImpostor;
    class function SpawnPineCanopyImpostorDemo(const Root, DesignOwner: TComponent;
      out Impostor: TCastleOctahedralImpostor): Boolean;
    class function GenerateImpostorReport(const Impostor: TCastleOctahedralImpostor): String;
  end;

implementation

uses CastleUtils;

class function TOctahedralImpostorHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TOctahedralImpostorHelper.FindImpostorInHierarchy(
  const Root: TComponent): TCastleOctahedralImpostor;

  function WalkTransform(const T: TCastleTransform): TCastleOctahedralImpostor;
  var
    I: Integer;
  begin
    if T is TCastleOctahedralImpostor then
      Exit(TCastleOctahedralImpostor(T));
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
  if Root is TCastleOctahedralImpostor then Exit(TCastleOctahedralImpostor(Root));
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
    if Root.Components[I] is TCastleOctahedralImpostor then
      Exit(TCastleOctahedralImpostor(Root.Components[I]));
end;

class function TOctahedralImpostorHelper.SpawnPineCanopyImpostorDemo(
  const Root, DesignOwner: TComponent;
  out Impostor: TCastleOctahedralImpostor): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
begin
  Result := False;
  Impostor := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  Impostor := FindImpostorInHierarchy(Root);
  if Impostor = nil then
  begin
    Impostor := TCastleOctahedralImpostor.Create(OwnerComp);
    Impostor.Name := 'PineCanopyImpostor1';
    Impostor.Preset := oipPineCanopy8x8;
    Vp.Items.Add(Impostor);
  end;
  Impostor.EvaluateCameraObserver(Vector3(35.0, 22.0, 55.0));
  Result := True;
end;

class function TOctahedralImpostorHelper.GenerateImpostorReport(
  const Impostor: TCastleOctahedralImpostor): String;
var
  S: TOctahedralBlendSample;
  ModeText: String;
begin
  if Impostor = nil then
    Exit('# Octahedral Impostor Report' + NL + NL + '_No `TCastleOctahedralImpostor` in scene._');

  S := Impostor.LastSample;
  if S.UseImpostorCard then
    ModeText := 'IMPOSTOR BILLBOARD CARD (2 tris)'
  else
    ModeText := 'HIGH-POLY SOURCE MESH';

  Result :=
    '# Octahedral Billboard Impostor Atlas Report (Phase 374)' + NL + NL +
    Format('- **Component**: `%s` %s', [Impostor.Name, Impostor.ImpostorSummaryBadge]) + NL +
    Format('- **Atlas Grid**: `%dx%d` (`%d` hemi-octahedral views, `%dx%d px` per tile in `%d px` atlas)', [
      Impostor.AtlasGridSize, Impostor.AtlasGridSize, Impostor.TotalAtlasViews,
      Impostor.TileResolutionPx, Impostor.TileResolutionPx, Impostor.AtlasResolutionPx]) + NL +
    Format('- **LOD Switchover**: `%.1f m` (Dither Band `%.1f m`) — Current Observer: `%.1f m` -> **%s**', [
      Impostor.SwitchDistanceMeters, Impostor.DitherTransitionBandMeters,
      S.DistanceMeters, ModeText]) + NL +
    Format('- **Hemi-Octahedral UV**: `(%.4f, %.4f)`', [S.Uv.X, S.Uv.Y]) + NL +
    Format('- **3-View Barycentric Blend**: Tile `#%d (%d,%d) w=%.3f` + Tile `#%d (%d,%d) w=%.3f` + Tile `#%d (%d,%d) w=%.3f` (Sum=`%.3f`)', [
      S.TileIndex0, S.Cell0X, S.Cell0Y, S.Weight0,
      S.TileIndex1, S.Cell1X, S.Cell1Y, S.Weight1,
      S.TileIndex2, S.Cell2X, S.Cell2Y, S.Weight2,
      S.Weight0 + S.Weight1 + S.Weight2]) + NL;
end;

end.
