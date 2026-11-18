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

{ Stateless helper for Chaos Flesh Tetrahedral Volume-XPBD Soft-Body Studio (Phase 354). }
unit ToolTetSoftBody;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleTetSoftBody;

type
  TTetSoftBodyHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindSoftBodyInHierarchy(const Root: TComponent): TCastleTetSoftBody;
    class function SpawnTetSoftBodyArena(const Root, DesignOwner: TComponent;
      out SoftBody: TCastleTetSoftBody): Boolean;
    class function GenerateTetSoftBodyReport(const SoftBody: TCastleTetSoftBody): String;
  end;

implementation

class function TTetSoftBodyHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TTetSoftBodyHelper.FindSoftBodyInHierarchy(const Root: TComponent): TCastleTetSoftBody;

  function WalkTransform(const T: TCastleTransform): TCastleTetSoftBody;
  var
    I: Integer;
  begin
    if T is TCastleTetSoftBody then
      Exit(TCastleTetSoftBody(T));
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
  if Root is TCastleTetSoftBody then Exit(TCastleTetSoftBody(Root));
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
    if Root.Components[I] is TCastleTetSoftBody then
      Exit(TCastleTetSoftBody(Root.Components[I]));
end;

class function TTetSoftBodyHelper.SpawnTetSoftBodyArena(const Root, DesignOwner: TComponent;
  out SoftBody: TCastleTetSoftBody): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  FloorBox: TCastleBox;
begin
  Result := False;
  SoftBody := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('TetSoftBodyAnvilFloor') = nil then
  begin
    FloorBox := TCastleBox.Create(OwnerComp);
    FloorBox.Name := 'TetSoftBodyAnvilFloor';
    FloorBox.Size := Vector3(16.0, 0.4, 16.0);
    FloorBox.Translation := Vector3(0.0, -0.2, 0.0);
    FloorBox.Color := Vector4(0.24, 0.25, 0.29, 1.0);
    Vp.Items.Add(FloorBox);
  end;

  SoftBody := FindSoftBodyInHierarchy(Root);
  if SoftBody = nil then
  begin
    SoftBody := TCastleTetSoftBody.Create(OwnerComp);
    SoftBody.Name := 'ChaosTetFlesh1';
    SoftBody.Preset := tsbpRubberBouncyCube;
    Vp.Items.Add(SoftBody);
  end;
  Result := True;
end;

class function TTetSoftBodyHelper.GenerateTetSoftBodyReport(const SoftBody: TCastleTetSoftBody): String;
var
  S: TTetSoftBodyStats;
begin
  if SoftBody = nil then
    Exit('# Chaos Flesh Tetrahedral Soft-Body Report' + LineEnding + LineEnding +
         '_No `TCastleTetSoftBody` found in design._');

  S := SoftBody.Stats;
  Result :=
    '# Chaos Flesh Tetrahedral Volume-XPBD Report (Phase 354)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component** | `%s` (%s) |', [SoftBody.Name, TetPresetToString(SoftBody.Preset)]) + LineEnding +
    Format('| **3D Lattice Topology** | `%dx%dx%d` cells -> `%d` vertices, `%d` tets, `%d` edges |', [
      SoftBody.CellsX, SoftBody.CellsY, SoftBody.CellsZ,
      S.VertexCount, S.TetrahedronCount, S.EdgeCount]) + LineEnding +
    Format('| **Rest vs. Current Volume** | `%.3f m^3` -> `%.3f m^3` (**`%.2f%%`**) |', [
      S.RestTotalVolume, S.CurrentTotalVolume, S.VolumeRatioPercent]) + LineEnding +
    Format('| **Inverted Tetrahedra (`V <= 0`)** | **`%d`** (`0 = 100%% Inversion-Free`) |', [
      S.InvertedTetCount]) + LineEnding +
    Format('| **Vertical Span `[MinY .. MaxY]`** | `[%.3f m .. %.3f m]` (`SimSteps = %d`) |', [
      S.MinVertexLocalY, S.MaxVertexLocalY, S.SimulationSteps]);
end;

end.
