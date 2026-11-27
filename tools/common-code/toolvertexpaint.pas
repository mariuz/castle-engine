{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless scene helper, preset spawner, multi-layer vertex weight auditor &
  Markdown report generator for Viewport Mesh Vertex Paint Mode (Phase 396). }
unit ToolVertexPaint;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleClassUtils, CastleVectors, CastleTransform, CastleViewport,
  CastleUIControls, CastleVertexPaint;

type
  TVertexPaintSceneAudit = record
    PaintedMeshCount: Integer;
    TotalVertices: Integer;
    TotalTriangles: Integer;
    TotalPaintedVertices: Integer;
    AvgMossPct: Single;
    AvgPuddlePct: Single;
    AvgWearPct: Single;
    AvgSnowPct: Single;
  end;

  TVertexPaintHelper = class
  public
    class procedure CollectVertexPaintMeshes(const ARoot: TComponent;
      const AList: TList); static;
    class function FindFirstVertexPaintMesh(const ARoot: TComponent): TCastleVertexPaintMesh; static;
    class function FindVertexPaintMeshByName(const ARoot, AOwner: TComponent;
      const AName: String): TCastleVertexPaintMesh; static;

    class function SpawnVertexPaintPresetInDesign(const ARoot, AOwner: TComponent;
      const APreset: TVertexPaintPreset;
      const APosition: TVector3): TCastleVertexPaintMesh; static;

    class function AuditVertexPaintInDesign(const ARoot: TComponent): TVertexPaintSceneAudit; static;
    class function GenerateMarkdownReport(const ARoot: TComponent;
      const ActiveMesh: TCastleVertexPaintMesh): String; static;
  end;

implementation

class procedure TVertexPaintHelper.CollectVertexPaintMeshes(
  const ARoot: TComponent; const AList: TList);

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    CC: TCastleComponent;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleVertexPaintMesh) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        Traverse(CC.NonVisualComponents[I]);
    end;
    if C is TCastleViewport then
      Traverse(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Traverse(UI.Controls[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Traverse(T[I]);
    end;
  end;

begin
  if (ARoot = nil) or (AList = nil) then Exit;
  Traverse(ARoot);
end;

class function TVertexPaintHelper.FindFirstVertexPaintMesh(
  const ARoot: TComponent): TCastleVertexPaintMesh;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectVertexPaintMeshes(ARoot, L);
    if L.Count > 0 then
      Result := TCastleVertexPaintMesh(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TVertexPaintHelper.FindVertexPaintMeshByName(
  const ARoot, AOwner: TComponent; const AName: String): TCastleVertexPaintMesh;
var
  L: TList;
  I: Integer;
  C: TComponent;
begin
  if Trim(AName) = '' then
    Exit(FindFirstVertexPaintMesh(ARoot));

  Result := nil;
  if AOwner <> nil then
  begin
    C := AOwner.FindComponent(AName);
    if C is TCastleVertexPaintMesh then
      Exit(TCastleVertexPaintMesh(C));
  end;

  L := TList.Create;
  try
    CollectVertexPaintMeshes(ARoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleVertexPaintMesh(L[I]).Name, AName) then
        Exit(TCastleVertexPaintMesh(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TVertexPaintHelper.SpawnVertexPaintPresetInDesign(
  const ARoot, AOwner: TComponent;
  const APreset: TVertexPaintPreset;
  const APosition: TVector3): TCastleVertexPaintMesh;
var
  ParentItems: TCastleTransform;
  VP: TCastleViewport;
  I: Integer;
  BaseName: String;
begin
  Result := nil;
  if ARoot = nil then Exit;

  ParentItems := nil;
  if ARoot is TCastleViewport then
    ParentItems := TCastleViewport(ARoot).Items
  else if ARoot is TCastleTransform then
    ParentItems := TCastleTransform(ARoot)
  else if ARoot is TCastleUserInterface then
  begin
    for I := 0 to TCastleUserInterface(ARoot).ControlsCount - 1 do
      if TCastleUserInterface(ARoot).Controls[I] is TCastleViewport then
      begin
        VP := TCastleViewport(TCastleUserInterface(ARoot).Controls[I]);
        ParentItems := VP.Items;
        Break;
      end;
  end;
  if ParentItems = nil then Exit;

  Result := TCastleVertexPaintMesh.Create(AOwner);
  case APreset of
    vppCobblestoneWallMossPuddles: BaseName := 'VP_CobblestoneCourtyard';
    vppRuinedArchwaySootWear:      BaseName := 'VP_RuinedBastionWall';
    vppTerrainCliffSnowLichen:     BaseName := 'VP_AlpineCliffOutcrop';
  end;
  if AOwner <> nil then
    Result.Name := ProposeComponentName(TCastleVertexPaintMesh, AOwner, BaseName)
  else
    Result.Name := BaseName;
  Result.Preset := APreset;
  Result.Translation := APosition;
  ParentItems.Add(Result);
end;

class function TVertexPaintHelper.AuditVertexPaintInDesign(
  const ARoot: TComponent): TVertexPaintSceneAudit;
var
  L: TList;
  I: Integer;
  M: TCastleVertexPaintMesh;
begin
  Result := Default(TVertexPaintSceneAudit);
  L := TList.Create;
  try
    CollectVertexPaintMeshes(ARoot, L);
    Result.PaintedMeshCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      M := TCastleVertexPaintMesh(L[I]);
      Inc(Result.TotalVertices, M.VertexCount);
      Inc(Result.TotalTriangles, M.TriangleCount);
      Inc(Result.TotalPaintedVertices, M.PaintedVertexCount);
      Result.AvgMossPct := Result.AvgMossPct + M.AverageChannelWeight(vpcRed) * 100.0;
      Result.AvgPuddlePct := Result.AvgPuddlePct + M.AverageChannelWeight(vpcGreen) * 100.0;
      Result.AvgWearPct := Result.AvgWearPct + M.AverageChannelWeight(vpcBlue) * 100.0;
      Result.AvgSnowPct := Result.AvgSnowPct + M.AverageChannelWeight(vpcAlpha) * 100.0;
    end;
    if L.Count > 0 then
    begin
      Result.AvgMossPct := Result.AvgMossPct / L.Count;
      Result.AvgPuddlePct := Result.AvgPuddlePct / L.Count;
      Result.AvgWearPct := Result.AvgWearPct / L.Count;
      Result.AvgSnowPct := Result.AvgSnowPct / L.Count;
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TVertexPaintHelper.GenerateMarkdownReport(
  const ARoot: TComponent; const ActiveMesh: TCastleVertexPaintMesh): String;
var
  Audit: TVertexPaintSceneAudit;
  SB: TStringBuilder;
begin
  Audit := AuditVertexPaintInDesign(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Viewport Mesh Vertex Paint Mode Report (Phase 396 — UE 5.5 MeshPaintMode Parity)');
    SB.AppendLine(Format('- **Scene Summary**: `%d` Vertex-Painted Meshes | `%d` Vertices (`%d` Painted) | `%d` Triangles',
      [Audit.PaintedMeshCount, Audit.TotalVertices, Audit.TotalPaintedVertices, Audit.TotalTriangles]));
    if ActiveMesh <> nil then
    begin
      SB.AppendLine(Format('- **Active Mesh**: `%s` (`%s`, Preview: `%s`, HeightLerp Contrast: `%.2f`)',
        [ActiveMesh.Name,
         VertexPaintPresetDisplayName(ActiveMesh.Preset),
         VertexPaintPreviewModeDisplayName(ActiveMesh.PreviewMode),
         ActiveMesh.HeightLerpContrast]));
      SB.AppendLine;
      SB.AppendLine('| RGBA Channel | Material Layer | Avg Weight | Roughness Seam Energy |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      SB.AppendLine(Format('| `[R]` Red | Moss / Damp Lichen | `%.1f%%` | `%.5f` |',
        [ActiveMesh.AverageChannelWeight(vpcRed) * 100.0,
         ActiveMesh.ComputeChannelRoughnessEnergy(vpcRed)]));
      SB.AppendLine(Format('| `[G]` Green | Rain Puddle / Wetness (`Rough=0.06`) | `%.1f%%` | `%.5f` |',
        [ActiveMesh.AverageChannelWeight(vpcGreen) * 100.0,
         ActiveMesh.ComputeChannelRoughnessEnergy(vpcGreen)]));
      SB.AppendLine(Format('| `[B]` Blue | Edge Chipped Wear / Torch Soot | `%.1f%%` | `%.5f` |',
        [ActiveMesh.AverageChannelWeight(vpcBlue) * 100.0,
         ActiveMesh.ComputeChannelRoughnessEnergy(vpcBlue)]));
      SB.AppendLine(Format('| `[A]` Alpha | Snow / Mortar Dust Cap | `%.1f%%` | `%.5f` |',
        [ActiveMesh.AverageChannelWeight(vpcAlpha) * 100.0,
         ActiveMesh.ComputeChannelRoughnessEnergy(vpcAlpha)]));
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
