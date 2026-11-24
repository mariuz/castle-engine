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

{ Automated tests for Phase 386 Three-Way Scene & Prefab Diff/Merge Inspector
  + 106-Studio Hub / 20-Tool MCP Upgrade. }
unit TestToolPrefabDiffMerge;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolPrefabDiffMerge = class(TCastleTestCase)
  published
    procedure TestNonConflictingThreeWayPropertyAndChildNodeAutoMergeVsTrueConflictResolution;
    procedure TestUnified106StudioHubCatalogAnd20thMcpDiffMergeSceneTool;
  end;

implementation

uses
  FpJson, JsonParser,
  CastleVectors, CastleTransform, CastleViewport, CastleScene,
  CastleComponentSerialize, ToolStudioHub, ToolMcpServer, ToolPrefabDiffMerge;

procedure TTestToolPrefabDiffMerge.TestNonConflictingThreeWayPropertyAndChildNodeAutoMergeVsTrueConflictResolution;
var
  OwnerOurs, OwnerTheirs: TComponent;
  BaseJson, OursJson, TheirsJson, MergedOursJson, MergedTheirsJson, Md: String;
  RepOurs, RepTheirs: TThreeWayMergeReport;
  RehydratedOurs, RehydratedTheirs: TCastleTransform;
  HeroMerged, CrateOurs, CrateTheirs, TowerMerged: TComponent;
begin
  OwnerOurs := TComponent.Create(nil);
  OwnerTheirs := TComponent.Create(nil);
  try
    TPrefabDiffMergeEngine.BuildSyntheticBranchConflictScenario(BaseJson, OursJson, TheirsJson);

    { 1. Merge with mcpPreferOurs:
         - Hero.Translation (6,1,0) from Ours + Hero.Scale (1.5,1.5,1.5) from Theirs BOTH auto-merge!
         - WatchtowerTheirs child added in Theirs auto-inserts into Merged!
         - SupplyCrateAlpha.Tag conflict (42 vs 99, Base=10) resolves to 42! }
    MergedOursJson := TPrefabDiffMergeEngine.ComputeThreeWayMerge(
      BaseJson, OursJson, TheirsJson, mcpPreferOurs, RepOurs);
    AssertTrue(RepOurs.AutoMergedCount >= 3);
    AssertEquals(1, RepOurs.AddedNodesCount);
    AssertEquals(1, RepOurs.ConflictCount);

    RehydratedOurs := StringToComponent(MergedOursJson, OwnerOurs) as TCastleTransform;
    AssertTrue(RehydratedOurs <> nil);
    HeroMerged := OwnerOurs.FindComponent('VanguardHero');
    CrateOurs := OwnerOurs.FindComponent('SupplyCrateAlpha');
    TowerMerged := OwnerOurs.FindComponent('WatchtowerTheirs');
    AssertTrue(HeroMerged is TCastleTransform);
    AssertTrue(CrateOurs <> nil);
    AssertTrue(TowerMerged is TCastleTransform);
    AssertVectorEquals(Vector3(6.0, 1.0, 0.0), TCastleTransform(HeroMerged).Translation, 0.001);
    AssertVectorEquals(Vector3(1.5, 1.5, 1.5), TCastleTransform(HeroMerged).Scale, 0.001);
    AssertEquals(42, CrateOurs.Tag);

    { 2. Merge with mcpPreferTheirs: SupplyCrateAlpha.Tag conflict resolves to 99 }
    MergedTheirsJson := TPrefabDiffMergeEngine.ComputeThreeWayMerge(
      BaseJson, OursJson, TheirsJson, mcpPreferTheirs, RepTheirs);
    AssertEquals(1, RepTheirs.ConflictCount);
    RehydratedTheirs := StringToComponent(MergedTheirsJson, OwnerTheirs) as TCastleTransform;
    AssertTrue(RehydratedTheirs <> nil);
    CrateTheirs := OwnerTheirs.FindComponent('SupplyCrateAlpha');
    AssertTrue(CrateTheirs <> nil);
    AssertEquals(99, CrateTheirs.Tag);

    Md := TPrefabDiffMergeEngine.BuildMarkdownReport(RepOurs);
    AssertTrue(Pos('Three-Way Scene & Prefab Diff/Merge Report', Md) > 0);
  finally
    FreeAndNil(OwnerTheirs);
    FreeAndNil(OwnerOurs);
  end;
end;

procedure TTestToolPrefabDiffMerge.TestUnified106StudioHubCatalogAnd20thMcpDiffMergeSceneTool;
const
  Horizon11MidIds: array[0..2] of String = (
    'gravity_field', 'cloud_shadows', 'prefab_diff_merge'
  );
var
  Entry: TStudioCatalogEntry;
  I: Integer;
  Owner: TComponent;
  Vp: TCastleViewport;
  Mcp: TCastleMcpServer;
  ListResp, CallResp, BaseJson, OursJson, TheirsJson: String;
  ReqRoot, ReqParams, ReqArgs: TJSONObject;
  RespData, PayloadData: TJSONData;
  ToolsArr: TJSONArray;
  PayloadObj: TJSONObject;
begin
  { 1. Verify all 100 UE 5.x studios (Horizons 2-11, Phases 1-380) are registered }
  AssertEquals(108, TStudioHubManager.StudioCount);
  for I := 0 to High(Horizon11MidIds) do
  begin
    AssertTrue(TStudioHubManager.FindStudioById(Horizon11MidIds[I], Entry));
    AssertEquals(373 + I, Entry.PhaseNumber);
  end;

  { 2. Verify 20th MCP tool cge_diff_merge_scene in tools/list and live JSON-RPC execution }
  Owner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    Vp.Name := 'MergeViewport';
    Mcp := TCastleMcpServer.Create(Owner);
    Mcp.AutonomyMode := mamEditWithUndo;
    Mcp.StandaloneDesignRoot := Vp;
    Mcp.StandaloneDesignOwner := Owner;

    ListResp := Mcp.HandleJsonRpcString('{"jsonrpc":"2.0","id":86,"method":"tools/list","params":{}}');
    RespData := GetJSON(ListResp);
    try
      ToolsArr := (RespData as TJSONObject).Objects['result'].Arrays['tools'];
      AssertEquals(31, ToolsArr.Count);
      AssertTrue(Pos('cge_diff_merge_scene', ListResp) > 0);
    finally
      FreeAndNil(RespData);
    end;

    TPrefabDiffMergeEngine.BuildSyntheticBranchConflictScenario(BaseJson, OursJson, TheirsJson);
    ReqRoot := TJSONObject.Create;
    try
      ReqRoot.Add('jsonrpc', '2.0');
      ReqRoot.Add('id', 87);
      ReqRoot.Add('method', 'tools/call');
      ReqParams := TJSONObject.Create;
      ReqParams.Add('name', 'cge_diff_merge_scene');
      ReqArgs := TJSONObject.Create;
      ReqArgs.Add('action', 'diff_three_way');
      ReqArgs.Add('baseJson', BaseJson);
      ReqArgs.Add('oursJson', OursJson);
      ReqArgs.Add('theirsJson', TheirsJson);
      ReqArgs.Add('conflictPolicy', 'prefer_theirs');
      ReqParams.Add('arguments', ReqArgs);
      ReqRoot.Add('params', ReqParams);
      CallResp := Mcp.HandleJsonRpcString(ReqRoot.AsJSON);
    finally
      FreeAndNil(ReqRoot);
    end;

    RespData := GetJSON(CallResp);
    try
      PayloadData := GetJSON(
        (RespData as TJSONObject).Objects['result'].Arrays['content'].Objects[0].Strings['text']);
      try
        PayloadObj := PayloadData as TJSONObject;
        AssertTrue(PayloadObj.Booleans['ok']);
        AssertEquals(108, PayloadObj.Integers['studioCatalogCount']);
        AssertEquals(1, PayloadObj.Integers['conflictCount']);
        AssertTrue(PayloadObj.Integers['autoMergedCount'] >= 3);
        AssertTrue(Pos('WatchtowerTheirs', PayloadObj.Strings['mergedJson']) > 0);
      finally
        FreeAndNil(PayloadData);
      end;
    finally
      FreeAndNil(RespData);
    end;
  finally
    FreeAndNil(Owner);
  end;
end;

initialization
  RegisterTest(TTestToolPrefabDiffMerge);

end.
