{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless Editor & Headless Helper for Geometry Script Procedural Mesh
  Operator Stacks & 3D L-System Botanical Trees
  (@link(TGeometryScriptHelper), @link(TGeometryScriptAuditReport))
  (Phase 325 — UE 6.0+ Geometry Script & PCG Vegetation Parity). }
unit ToolGeometryScript;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTransform, CastleViewport, CastleGeometryScript;

type
  TGeoScriptMeshArray = array of TCastleGeometryScriptMesh;
  TLSystemBotanicalArray = array of TCastleLSystemBotanical;

  { QA summary across all Geometry Script meshes and L-System botanicals. }
  TGeometryScriptAuditReport = class
  public
    GeoMeshCount: Integer;
    BotanicalCount: Integer;
    TotalProceduralTriangles: Integer;
    TotalBranches: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, and auditing
    @link(TCastleGeometryScriptMesh) and @link(TCastleLSystemBotanical). }
  TGeometryScriptHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanGeometryAndBotanicals(const RootComp, DesignOwner: TComponent;
      out OutMeshes: TGeoScriptMeshArray;
      out OutTrees: TLSystemBotanicalArray); static;

    class procedure SpawnGeometryAndTreeShowcaseDemo(
      const RootComp, DesignOwner: TComponent;
      out OutMesh: TCastleGeometryScriptMesh;
      out OutTree: TCastleLSystemBotanical); static;

    class function AuditGeometryScript(
      const RootComp, DesignOwner: TComponent): TGeometryScriptAuditReport; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleVectors;

constructor TGeometryScriptAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TGeometryScriptAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TGeometryScriptHelper.FindMainViewport(const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  Found: TCastleViewport;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  for I := 0 to RootComp.ComponentCount - 1 do
  begin
    Found := FindMainViewport(RootComp.Components[I]);
    if Found <> nil then
      Exit(Found);
  end;
end;

class procedure TGeometryScriptHelper.ScanGeometryAndBotanicals(
  const RootComp, DesignOwner: TComponent;
  out OutMeshes: TGeoScriptMeshArray;
  out OutTrees: TLSystemBotanicalArray);

  procedure AddMesh(const M: TCastleGeometryScriptMesh);
  var K: Integer;
  begin
    for K := 0 to High(OutMeshes) do if OutMeshes[K] = M then Exit;
    SetLength(OutMeshes, Length(OutMeshes) + 1);
    OutMeshes[High(OutMeshes)] := M;
  end;

  procedure AddTree(const T: TCastleLSystemBotanical);
  var K: Integer;
  begin
    for K := 0 to High(OutTrees) do if OutTrees[K] = T then Exit;
    SetLength(OutTrees, Length(OutTrees) + 1);
    OutTrees[High(OutTrees)] := T;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleGeometryScriptMesh then
      AddMesh(TCastleGeometryScriptMesh(C))
    else if C is TCastleLSystemBotanical then
      AddTree(TCastleLSystemBotanical(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutMeshes := nil;
  OutTrees := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TGeometryScriptHelper.SpawnGeometryAndTreeShowcaseDemo(
  const RootComp, DesignOwner: TComponent;
  out OutMesh: TCastleGeometryScriptMesh;
  out OutTree: TCastleLSystemBotanical);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  Idx: Integer;
begin
  OutMesh := nil;
  OutTree := nil;

  Vp := FindMainViewport(RootComp);
  if Vp <> nil then
    ParentTrans := Vp.Items
  else if RootComp is TCastleTransform then
    ParentTrans := TCastleTransform(RootComp)
  else
    Exit;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('GeoScriptAmphora_' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  OutMesh := TCastleGeometryScriptMesh.Create(OwnerToUse);
  OutMesh.Name := 'GeoScriptAmphora_' + IntToStr(Idx);
  OutMesh.Translation := Vector3(-2.5, 0.0, 0.0);
  OutMesh.ApplyPreset(gspTwistedThickAmphora);
  ParentTrans.Add(OutMesh);

  OutTree := TCastleLSystemBotanical.Create(OwnerToUse);
  OutTree.Name := 'LSystemOakTree_' + IntToStr(Idx);
  OutTree.Translation := Vector3(2.5, 0.0, 0.0);
  OutTree.ApplyPreset(lspBroadleafOakTree);
  ParentTrans.Add(OutTree);
end;

class function TGeometryScriptHelper.AuditGeometryScript(
  const RootComp, DesignOwner: TComponent): TGeometryScriptAuditReport;
var
  Meshes: TGeoScriptMeshArray;
  Trees: TLSystemBotanicalArray;
  I: Integer;
begin
  Result := TGeometryScriptAuditReport.Create;
  ScanGeometryAndBotanicals(RootComp, DesignOwner, Meshes, Trees);
  Result.GeoMeshCount := Length(Meshes);
  Result.BotanicalCount := Length(Trees);

  for I := 0 to High(Meshes) do
  begin
    Result.TotalProceduralTriangles := Result.TotalProceduralTriangles + Meshes[I].TriangleCount;
    if Meshes[I].TriangleCount > 25000 then
      Result.Warnings.Add(Format(
        'GeometryScriptMesh "%s" generates %d triangles — reduce RadialSegments or LinearSubdivide4x stages for mobile targets.',
        [Meshes[I].Name, Meshes[I].TriangleCount]));
  end;

  for I := 0 to High(Trees) do
  begin
    Result.TotalBranches := Result.TotalBranches + Trees[I].BranchSegmentCount;
    if Trees[I].Iterations >= 6 then
      Result.Warnings.Add(Format(
        'LSystemBotanical "%s" uses Iterations = %d — consider <= 4 iterations for real-time scenes.',
        [Trees[I].Name, Trees[I].Iterations]));
  end;
end;

class function TGeometryScriptHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Meshes: TGeoScriptMeshArray;
  Trees: TLSystemBotanicalArray;
  Rep: TGeometryScriptAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanGeometryAndBotanicals(RootComp, DesignOwner, Meshes, Trees);
  Rep := AuditGeometryScript(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Geometry Script Modifier Stack & 3D L-System Botanical Studio Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **Geometry Script Meshes:** %d (`%d` total triangles)',
      [Rep.GeoMeshCount, Rep.TotalProceduralTriangles]));
    SB.AppendLine(Format('- **3D L-System Botanicals:** %d (`%d` total branch segments)',
      [Rep.BotanicalCount, Rep.TotalBranches]));
    SB.AppendLine('');
    for I := 0 to High(Meshes) do
      SB.AppendLine(Format('- `%s`: %s (Area=%.2f m^2)',
        [Meshes[I].Name, Meshes[I].GeoSummaryBadge, Meshes[I].ComputedSurfaceArea]));
    for I := 0 to High(Trees) do
      SB.AppendLine(Format('- `%s`: %s (Height=%.2fm)',
        [Trees[I].Name, Trees[I].BotanicalSummaryBadge, Trees[I].CrownBoundsMaxY]));
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Rep);
  end;
end;

end.
