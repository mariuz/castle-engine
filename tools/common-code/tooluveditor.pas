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

{ Stateless scene authoring, UV projection/packing driver, and texel-density
  auditor for the Unreal Engine 5.5-style Modeling Mode UV Editor
  (@link(TUvEditorHelper), @link(TUvSceneAuditReport))
  (Phase 389 — UE 5.5 Modeling Mode UV Editor Parity + 32nd MCP Tool). }
unit ToolUvEditor;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleUvEditor;

type
  { Scene-wide UV & texel-density audit report. }
  TUvSceneAuditReport = record
    MeshCount: Integer;
    TotalTriangles: Integer;
    TotalIslands: Integer;
    TotalOverlappingPairs: Integer;
    TotalInvertedTriangles: Integer;
    AvgCoveragePercent: Single;
    AvgTexelsPerMeter: Single;
  end;

  { Scene spawner, batch UV auditor, and Markdown report builder. }
  TUvEditorHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class procedure CollectUvMeshes(const ADesignRoot: TComponent;
      const AList: TList); static;
    class function FindFirstUvMesh(const ADesignRoot: TComponent): TCastleUvEditorMesh; static;
    class function FindUvMeshByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleUvEditorMesh; static;

    class function SpawnUvMeshPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TUvMeshPreset;
      const AWorldPos: TVector3): TCastleUvEditorMesh; static;

    class function AuditUvMeshesInDesign(
      const ADesignRoot: TComponent): TUvSceneAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedMesh: TCastleUvEditorMesh): String; static;
  end;

implementation

uses
  Math, CastleUtils, CastleClassUtils, CastleUIControls;

class function TUvEditorHelper.FindParentViewportItems(
  const ADesignRoot: TComponent): TCastleTransform;

  function SearchVp(const C: TComponent): TCastleViewport;
  var
    UI: TCastleUserInterface;
    I: Integer;
  begin
    Result := nil;
    if C = nil then Exit;
    if C is TCastleViewport then Exit(TCastleViewport(C));
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
      begin
        Result := SearchVp(UI.Controls[I]);
        if Result <> nil then Exit;
      end;
    end;
  end;

var
  VP: TCastleViewport;
begin
  Result := nil;
  if ADesignRoot = nil then Exit;
  if ADesignRoot is TCastleTransform then
    Exit(TCastleTransform(ADesignRoot));
  VP := SearchVp(ADesignRoot);
  if VP <> nil then
    Result := VP.Items;
end;

class procedure TUvEditorHelper.CollectUvMeshes(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleUvEditorMesh) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Scan(UI.Controls[I]);
    end;
    if C is TCastleViewport then
      Scan(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Scan(T[I]);
    end;
  end;

begin
  if AList = nil then Exit;
  Scan(ADesignRoot);
end;

class function TUvEditorHelper.FindFirstUvMesh(
  const ADesignRoot: TComponent): TCastleUvEditorMesh;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectUvMeshes(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleUvEditorMesh(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TUvEditorHelper.FindUvMeshByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleUvEditorMesh;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstUvMesh(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleUvEditorMesh then
      Exit(TCastleUvEditorMesh(Found));
  end;

  L := TList.Create;
  try
    CollectUvMeshes(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleUvEditorMesh(L[I]).Name, AName) then
        Exit(TCastleUvEditorMesh(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TUvEditorHelper.SpawnUvMeshPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TUvMeshPreset;
  const AWorldPos: TVector3): TCastleUvEditorMesh;
var
  ParentT: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  Result := TCastleUvEditorMesh.Create(ADesignOwner);
  case APreset of
    umpCylindricalColumnSeamUnwrap:    BaseName := 'UV_CylindricalColumn';
    umpOverlappingStackedUvRepairDemo: BaseName := 'UV_StackedOverlapDemo';
  else
    BaseName := 'UV_Crate6Islands';
  end;
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleUvEditorMesh, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;

  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TUvEditorHelper.AuditUvMeshesInDesign(
  const ADesignRoot: TComponent): TUvSceneAuditReport;
var
  L: TList;
  M: TCastleUvEditorMesh;
  A: TUvLayoutAudit;
  I: Integer;
begin
  Result := Default(TUvSceneAuditReport);
  L := TList.Create;
  try
    CollectUvMeshes(ADesignRoot, L);
    Result.MeshCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      M := TCastleUvEditorMesh(L[I]);
      A := M.AuditUvLayout;
      Inc(Result.TotalTriangles, A.TriangleCount);
      Inc(Result.TotalIslands, A.IslandCount);
      Inc(Result.TotalOverlappingPairs, A.OverlappingPairCount);
      Inc(Result.TotalInvertedTriangles, A.InvertedTriangleCount);
      Result.AvgCoveragePercent := Result.AvgCoveragePercent + A.UvCoveragePercent;
      Result.AvgTexelsPerMeter := Result.AvgTexelsPerMeter + A.MeasuredTexelsPerMeter;
    end;
    if L.Count > 0 then
    begin
      Result.AvgCoveragePercent := Result.AvgCoveragePercent / L.Count;
      Result.AvgTexelsPerMeter := Result.AvgTexelsPerMeter / L.Count;
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TUvEditorHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedMesh: TCastleUvEditorMesh): String;
var
  Audit: TUvSceneAuditReport;
  SB: TStringList;
  I: Integer;
begin
  Audit := AuditUvMeshesInDesign(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# Modeling Mode UV Editor & Texel-Density Report (Phase 389 — UE 5.5 UVEditor Parity)');
    SB.Add('');
    SB.Add(Format('- **UV Meshes**: `%d` | **Triangles**: `%d` | **Islands**: `%d`',
      [Audit.MeshCount, Audit.TotalTriangles, Audit.TotalIslands]));
    SB.Add(Format('- **Overlapping Pairs**: `%d` | **Avg Fill**: `%.1f%%` | **Avg Texel Density**: `%.1f px/m`',
      [Audit.TotalOverlappingPairs, Audit.AvgCoveragePercent, Audit.AvgTexelsPerMeter]));
    if ASelectedMesh <> nil then
    begin
      SB.Add('');
      SB.Add('## Active UV Mesh: `' + ASelectedMesh.Name + '` ' + ASelectedMesh.UvSummaryBadge);
      for I := 0 to High(ASelectedMesh.Islands) do
        SB.Add(Format('- Island `#%d` (`%d` tris): UV=`(%.2f,%.2f)..(%.2f,%.2f)` World=`%.2f m^2` TD=`%.1f px/m`',
          [ASelectedMesh.Islands[I].IslandId,
           ASelectedMesh.Islands[I].TriangleCount,
           ASelectedMesh.Islands[I].MinUV.X, ASelectedMesh.Islands[I].MinUV.Y,
           ASelectedMesh.Islands[I].MaxUV.X, ASelectedMesh.Islands[I].MaxUV.Y,
           ASelectedMesh.Islands[I].WorldAreaM2,
           ASelectedMesh.Islands[I].TexelsPerMeter]));
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
