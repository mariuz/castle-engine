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

{ Stateless helper for Procedural Ivy, Vine & Root Surface Climber Studio (Phase 379). }
unit ToolIvyClimber;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions,
  CastleViewport, CastleIvyClimber;

type
  TIvyClimberHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindIvyInHierarchy(const Root: TComponent): TCastleIvyClimber;
    class function SpawnMasonryWallIvyDemo(const Root, DesignOwner: TComponent;
      out Ivy: TCastleIvyClimber): Boolean;
    class function GenerateIvyReport(const Ivy: TCastleIvyClimber): String;
  end;

implementation

uses CastleUtils;

class function TIvyClimberHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TIvyClimberHelper.FindIvyInHierarchy(
  const Root: TComponent): TCastleIvyClimber;

  function WalkTransform(const T: TCastleTransform): TCastleIvyClimber;
  var
    I: Integer;
  begin
    if T is TCastleIvyClimber then
      Exit(TCastleIvyClimber(T));
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
  if Root is TCastleIvyClimber then Exit(TCastleIvyClimber(Root));
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
    if Root.Components[I] is TCastleIvyClimber then
      Exit(TCastleIvyClimber(Root.Components[I]));
end;

class function TIvyClimberHelper.SpawnMasonryWallIvyDemo(
  const Root, DesignOwner: TComponent;
  out Ivy: TCastleIvyClimber): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  MasonryWall: TCastleBox;
begin
  Result := False;
  Ivy := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('IvyMasonryWall') = nil then
  begin
    MasonryWall := TCastleBox.Create(OwnerComp);
    MasonryWall.Name := 'IvyMasonryWall';
    MasonryWall.Size := Vector3(5.0, 3.6, 0.8);
    MasonryWall.Translation := Vector3(0.0, 1.8, 0.8); // Front face at Z = +0.4
    MasonryWall.Material := pmPhysical;
    MasonryWall.Color := Vector4(0.52, 0.50, 0.47, 1.0);
    Vp.Items.Add(MasonryWall);
  end;

  Ivy := FindIvyInHierarchy(Root);
  if Ivy = nil then
  begin
    Ivy := TCastleIvyClimber.Create(OwnerComp);
    Ivy.Name := 'CastleIvyClimber1';
    Ivy.Preset := ivpAncientCastleHedera;
    Ivy.Translation := Vector3(0.0, 0.15, 0.15); // Base of masonry wall
    Vp.Items.Add(Ivy);
  end;
  Ivy.GrowIvyOnWorld(Vp.Items);
  Result := True;
end;

class function TIvyClimberHelper.GenerateIvyReport(
  const Ivy: TCastleIvyClimber): String;
begin
  if Ivy = nil then
    Exit('# Procedural Ivy & Vine Climber Report' + NL + NL +
      '_No `TCastleIvyClimber` in scene._');

  Result :=
    '# Procedural Ivy, Vine & Root Surface Climber Report (Phase 379)' + NL + NL +
    Format('- **Climber**: `%s` %s', [Ivy.Name, Ivy.IvySummaryBadge]) + NL +
    Format('- **Botanical Solver**: Primary Tendrils `%d` | Max Steps `%d` (`%.2f m/step`) | Seed `%d`', [
      Ivy.PrimaryTendrils, Ivy.MaxStepsPerTendril, Ivy.StepLengthMeters, Ivy.RandomSeed]) + NL +
    Format('- **Tropism & Cling**: Phototropism `+%.2f Y` | Adhesion Radius `%.2f m` | Branching `%.0f%%`', [
      Ivy.PhototropismUp, Ivy.AdhesionRadiusMeters, Ivy.BranchProbability * 100.0]) + NL +
    Format('- **Grown Canopy**: `%d` total nodes (`%d` wall-clung), `%d` leaf clusters, Peak Height `Y = %.2f m`', [
      Ivy.NodeCount, Ivy.AttachedNodeCount, Ivy.TotalLeafCount, Ivy.MaxReachedHeightY]) + NL;
end;

end.
