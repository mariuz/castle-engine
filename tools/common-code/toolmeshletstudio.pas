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

{ Stateless helper for Nanite-Style Meshlet Cluster & Normal-Cone Culler Studio (Phase 353). }
unit ToolMeshletStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport, CastleMeshletCluster;

type
  TMeshletStudioHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindClustererInHierarchy(const Root: TComponent): TCastleMeshletClusterer;
    class function SpawnMeshletClusterDemo(const Root, DesignOwner: TComponent;
      out Clusterer: TCastleMeshletClusterer): Boolean;
    class function GenerateMeshletReport(const Clusterer: TCastleMeshletClusterer): String;
  end;

implementation

class function TMeshletStudioHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TMeshletStudioHelper.FindClustererInHierarchy(const Root: TComponent): TCastleMeshletClusterer;

  function WalkTransform(const T: TCastleTransform): TCastleMeshletClusterer;
  var
    I: Integer;
  begin
    if T is TCastleMeshletClusterer then
      Exit(TCastleMeshletClusterer(T));
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
  if Root is TCastleMeshletClusterer then Exit(TCastleMeshletClusterer(Root));
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
    if Root.Components[I] is TCastleMeshletClusterer then
      Exit(TCastleMeshletClusterer(Root.Components[I]));
end;

class function TMeshletStudioHelper.SpawnMeshletClusterDemo(const Root, DesignOwner: TComponent;
  out Clusterer: TCastleMeshletClusterer): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  CamPos: TVector3;
begin
  Result := False;
  Clusterer := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  Clusterer := FindClustererInHierarchy(Root);
  if Clusterer = nil then
  begin
    Clusterer := TCastleMeshletClusterer.Create(OwnerComp);
    Clusterer.Name := 'NaniteMeshletClusterer1';
    Clusterer.Preset := mspHighPolyUvSphere;
    Vp.Items.Add(Clusterer);
  end;

  if Vp.Camera <> nil then
    CamPos := Vp.Camera.WorldTranslation
  else
    CamPos := Vector3(0, 0, 12.0);
  if CamPos.LengthSqr < 0.01 then
    CamPos := Vector3(0, 0, 12.0);
  Clusterer.EvaluateViewMeshletCulling(CamPos, 1080, 60.0);
  Result := True;
end;

class function TMeshletStudioHelper.GenerateMeshletReport(const Clusterer: TCastleMeshletClusterer): String;
var
  S: TMeshletViewStats;
  I, ShowCount: Integer;
  C: TMeshletClusterInfo;
begin
  if Clusterer = nil then
    Exit('# Nanite Meshlet Cluster Report' + LineEnding + LineEnding + '_No `TCastleMeshletClusterer` found in design._');

  S := Clusterer.LastViewStats;
  Result :=
    '# Nanite Meshlet Cluster & Normal-Cone Culler Report (Phase 353)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component** | `%s` (%s) |', [Clusterer.Name, MeshletPresetToString(Clusterer.Preset)]) + LineEnding +
    Format('| **Meshlet Budget Limits** | `MaxVertices = %d` / `MaxTriangles = %d` |', [
      Clusterer.MaxVerticesPerMeshlet, Clusterer.MaxTrianglesPerMeshlet]) + LineEnding +
    Format('| **Cluster Count & Source Tris** | `%d` meshlets (`%d` total triangles) |', [
      S.TotalClusters, S.TotalTriangles]) + LineEnding +
    Format('| **Backface-Cone Culled** | `%d` clusters (`%.1f%%` triangles skipped in O(1)) |', [
      S.BackfaceConeCulledClusters, S.CulledTrianglePercent]) + LineEnding +
    Format('| **Visible Submitted** | `%d` clusters (`%d` triangles) |', [
      S.VisibleClusters, S.VisibleTriangles]) + LineEnding +
    Format('| **Max Screen-Space Error** | `%.2f px` -> **Recommended DAG Tier: LOD %d** |', [
      S.MaxProjectedPixelError, S.RecommendedLodTier]) + LineEnding + LineEnding +
    '### Sample Cluster Bounds & Normal Cones' + LineEnding +
    '| Cluster | Verts / Tris | Radius (m) | Cone Half-Angle (deg) | Status |' + LineEnding +
    '| :--- | :--- | :--- | :--- | :--- |' + LineEnding;

  ShowCount := Clusterer.ClusterCount;
  if ShowCount > 8 then ShowCount := 8;
  for I := 0 to ShowCount - 1 do
  begin
    C := Clusterer.GetClusterInfo(I);
    Result := Result + Format('| `#%d` | `%dv / %dt` | `%.2f` | `%.1f` | %s |', [
      C.ClusterIndex, C.UniqueVertexCount, C.TriangleCount, C.BoundingRadius,
      C.NormalConeHalfAngleRad * (180.0 / Pi),
      BoolToStr(C.LastCulledByBackfaceCone, 'CULLED (Backface Cone)', 'VISIBLE')]) + LineEnding;
  end;
end;

end.
