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

{ Stateless scene authoring, multi-graph executor, per-node point inspector,
  and diagnostic helper for the Unreal Engine 5.5-style PCG Visual Node Graph
  Editor (@link(TPcgGraphHelper), @link(TPcgSceneAuditReport))
  (Phase 382 — UE 5.5 UPCGGraph Parity + 25th MCP Tool). }
unit ToolPcgGraph;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastlePcgGraph;

type
  { Summary audit across all @link(TCastlePcgGraph) volumes in the open design. }
  TPcgSceneAuditReport = record
    GraphCount: Integer;
    ValidGraphCount: Integer;
    ErrorGraphCount: Integer;
    TotalNodeCount: Integer;
    TotalSpawnedInstances: Integer;
  end;

  { Scene spawner, batch PCG executor, and Markdown report builder. }
  TPcgGraphHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class function FindFirstPcgGraph(const ADesignRoot: TComponent): TCastlePcgGraph; static;
    class function FindPcgGraphByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastlePcgGraph; static;
    class procedure CollectPcgGraphs(const ADesignRoot: TComponent;
      const AList: TList); static;

    class function SpawnPcgPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TPcgGraphPreset;
      const AWorldPos: TVector3): TCastlePcgGraph; static;

    class function ExecuteAllPcgGraphsInDesign(
      const ADesignRoot: TComponent;
      out OutErrorMessages: String): TPcgSceneAuditReport; static;

    class function AuditPcgGraphsInDesign(
      const ADesignRoot: TComponent): TPcgSceneAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedGraph: TCastlePcgGraph): String; static;
  end;

implementation

uses
  CastleUtils, CastleClassUtils, CastleUIControls;

class function TPcgGraphHelper.FindParentViewportItems(
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

class procedure TPcgGraphHelper.CollectPcgGraphs(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastlePcgGraph) and (AList.IndexOf(C) < 0) then
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

class function TPcgGraphHelper.FindFirstPcgGraph(
  const ADesignRoot: TComponent): TCastlePcgGraph;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectPcgGraphs(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastlePcgGraph(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TPcgGraphHelper.FindPcgGraphByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastlePcgGraph;
var
  L: TList;
  I: Integer;
  Found: TComponent;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstPcgGraph(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastlePcgGraph then
      Exit(TCastlePcgGraph(Found));
  end;

  L := TList.Create;
  try
    CollectPcgGraphs(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastlePcgGraph(L[I]).Name, AName) then
        Exit(TCastlePcgGraph(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TPcgGraphHelper.SpawnPcgPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TPcgGraphPreset;
  const AWorldPos: TVector3): TCastlePcgGraph;
var
  ParentT: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  Result := TCastlePcgGraph.Create(ADesignOwner);
  case APreset of
    pgpRockOutcropAndShrubUnion: BaseName := 'PCG_RockShrubBiome';
    pgpSplineFenceColonnade:     BaseName := 'PCG_SplineColonnade';
  else
    BaseName := 'PCG_ForestRoadClearing';
  end;
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastlePcgGraph, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;
  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TPcgGraphHelper.ExecuteAllPcgGraphsInDesign(
  const ADesignRoot: TComponent;
  out OutErrorMessages: String): TPcgSceneAuditReport;
var
  L: TList;
  ErrList: TStringList;
  G: TCastlePcgGraph;
  I, E: Integer;
begin
  OutErrorMessages := '';
  L := TList.Create;
  ErrList := TStringList.Create;
  try
    CollectPcgGraphs(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
    begin
      G := TCastlePcgGraph(L[I]);
      if not G.ExecuteGraph then
        for E := 0 to G.ValidationErrors.Count - 1 do
          ErrList.Add(Format('[%s] %s', [G.Name, G.ValidationErrors[E]]));
    end;
    OutErrorMessages := Trim(ErrList.Text);
    Result := AuditPcgGraphsInDesign(ADesignRoot);
  finally
    FreeAndNil(ErrList);
    FreeAndNil(L);
  end;
end;

class function TPcgGraphHelper.AuditPcgGraphsInDesign(
  const ADesignRoot: TComponent): TPcgSceneAuditReport;
var
  L: TList;
  G: TCastlePcgGraph;
  I: Integer;
begin
  Result := Default(TPcgSceneAuditReport);
  L := TList.Create;
  try
    CollectPcgGraphs(ADesignRoot, L);
    Result.GraphCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      G := TCastlePcgGraph(L[I]);
      if G.LastExecutionValid then
        Inc(Result.ValidGraphCount)
      else
        Inc(Result.ErrorGraphCount);
      Inc(Result.TotalNodeCount, Length(G.Nodes));
      Inc(Result.TotalSpawnedInstances, G.SpawnedMeshCount);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TPcgGraphHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedGraph: TCastlePcgGraph): String;
var
  Audit: TPcgSceneAuditReport;
  SB: TStringList;
  I: Integer;
begin
  Audit := AuditPcgGraphsInDesign(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# PCG Visual Node Graph Report (Phase 382 — UE 5.5 UPCGGraph Parity)');
    SB.Add('');
    SB.Add(Format('- **PCG Volumes**: `%d` (`%d` Valid, `%d` Errors)',
      [Audit.GraphCount, Audit.ValidGraphCount, Audit.ErrorGraphCount]));
    SB.Add(Format('- **Total Graph Nodes**: `%d`', [Audit.TotalNodeCount]));
    SB.Add(Format('- **Total Spawned Meshes**: `%d`', [Audit.TotalSpawnedInstances]));
    if ASelectedGraph <> nil then
    begin
      SB.Add('');
      SB.Add('## Active PCG Graph: `' + ASelectedGraph.Name + '` ' + ASelectedGraph.PcgSummaryBadge);
      for I := 0 to High(ASelectedGraph.Nodes) do
        SB.Add(Format('- `%s` (%s): **%d pts**',
          [ASelectedGraph.Nodes[I].NodeId,
           TCastlePcgGraph.NodeKindTitle(ASelectedGraph.Nodes[I].Kind),
           ASelectedGraph.Nodes[I].LastOutputCount]));
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
