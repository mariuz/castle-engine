{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 406: Automated LOD Chain & GPU Draw-Call Instancing
  Optimizer + 126-Studio Hub / 22nd MCP Tool (cge_optimize_lod_instancing). }
unit TestToolLodInstancing;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolLodInstancing = class(TCastleTestCase)
  published
    procedure TestGpuInstancingBatchReductionAnd4TierScreenSizeHysteresisLodChain;
    procedure TestUnified126StudioHubCatalogAnd22ndMcpOptimizeLodInstancingTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  ToolLodInstancing, ToolStudioHub, ToolMcpServer;

procedure TTestToolLodInstancing.TestGpuInstancingBatchReductionAnd4TierScreenSizeHysteresisLodChain;
var
  Root: TComponent;
  VP: TCastleViewport;
  Rep, StrictRep: TLodInstancingReport;
  LPlan: TAssetLodChainPlan;
  I: Integer;
  Md: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TLodInstancingOptimizer.SpawnColonnadeInstancingDemo(Root, Root));

    { 10 stone pillars + 8 iron lanterns + 1 hero statue = 19 baseline draws ->
      1 pillar batch + 1 lantern batch + 1 hero statue = 3 draws (-16 saved = 84.2%!) }
    Rep := TLodInstancingOptimizer.SharedOptimizer.AnalyzeSceneInstancingAndLod(
      Root, 2, 60.0, 500);
    AssertEquals(19, Rep.TotalAnalyzedTransforms);
    AssertEquals(19, Rep.BaselineDrawCalls);
    AssertEquals(3, Rep.OptimizedDrawCalls);
    AssertEquals(16, Rep.PotentialDrawCallReduction);
    AssertEquals(2, Rep.BatchGroupCount);
    AssertEquals(3, Rep.HighPolyLodCandidateCount);

    { Verify 4-tier LOD distances strictly increase and triangle counts strictly
      decrease with exact 1.12x exit hysteresis anti-pop deadband }
    for I := 0 to High(Rep.LodPlans) do
    begin
      LPlan := Rep.LodPlans[I];
      AssertTrue(LPlan.Tiers[1].EnterDistanceMeters > 1.0);
      AssertTrue(LPlan.Tiers[2].EnterDistanceMeters > LPlan.Tiers[1].EnterDistanceMeters);
      AssertTrue(LPlan.Tiers[3].EnterDistanceMeters > LPlan.Tiers[2].EnterDistanceMeters);
      AssertSameValue(LPlan.Tiers[2].EnterDistanceMeters * 1.12,
        LPlan.Tiers[2].ExitHysteresisMeters, 0.01);
      AssertTrue(LPlan.Tiers[0].TargetTriangles > LPlan.Tiers[1].TargetTriangles);
      AssertTrue(LPlan.Tiers[1].TargetTriangles > LPlan.Tiers[2].TargetTriangles);
      AssertTrue(LPlan.Tiers[2].TargetTriangles > LPlan.Tiers[3].TargetTriangles);
    end;

    { Raising AMinBatchInstances to 9 batches only the 10-pillar group (-9 draws -> 10 draws) }
    StrictRep := TLodInstancingOptimizer.SharedOptimizer.AnalyzeSceneInstancingAndLod(
      Root, 9, 60.0, 500);
    AssertEquals(1, StrictRep.BatchGroupCount);
    AssertEquals(9, StrictRep.PotentialDrawCallReduction);
    AssertEquals(10, StrictRep.OptimizedDrawCalls);

    Md := TLodInstancingOptimizer.GenerateMarkdownReport(Rep);
    AssertTrue(Pos('HeroCathedralGuardianStatue', Md) > 0);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolLodInstancing.TestUnified126StudioHubCatalogAnd22ndMcpOptimizeLodInstancingTool;
const
  Horizon11OptIds: array[0..2] of String = (
    'budget_treemap', 'lod_instancing', 'shader_complexity'
  );
var
  Root: TComponent;
  VP: TCastleViewport;
  Entry: TStudioCatalogEntry;
  I: Integer;
  Srv: TCastleMcpServer;
  ListResp, CallResp, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  ToolsArr: TJSONArray;
  PayloadObj: TJSONObject;
begin
  { 1. Verify all 100 UE 5.x studios (Horizons 2-11, Phases 1-380) are registered }
  AssertEquals(116, TStudioHubManager.StudioCount);
  for I := 0 to High(Horizon11OptIds) do
    AssertTrue('Missing UE optimization studio: ' + Horizon11OptIds[I],
      TStudioHubManager.FindStudioById(Horizon11OptIds[I], Entry));
  AssertTrue(TStudioHubManager.FindStudioById('lod_instancing', Entry));
  AssertEquals(379, Entry.PhaseNumber);

  { 2. Verify 22nd MCP tool cge_optimize_lod_instancing over JSON-RPC 2.0 }
  Root := TComponent.Create(nil);
  Srv := TCastleMcpServer.Create(nil);
  OuterJson := nil;
  InnerJson := nil;
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TLodInstancingOptimizer.SpawnColonnadeInstancingDemo(Root, Root));

    Srv.AutonomyMode := mamReadOnly;
    Srv.StandaloneDesignRoot := Root;
    Srv.StandaloneDesignOwner := Root;

    ListResp := Srv.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}', '');
    OuterJson := GetJSON(ListResp);
    ToolsArr := TJSONObject(OuterJson).Objects['result'].Arrays['tools'];
    AssertEquals(39, ToolsArr.Count);
    AssertTrue(Pos('cge_optimize_lod_instancing', ListResp) > 0);
    FreeAndNil(OuterJson);

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_optimize_lod_instancing","arguments":{"action":"analyze_scene","minBatchInstances":2}}}',
      '');
    OuterJson := GetJSON(CallResp);
    InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
    InnerJson := GetJSON(InnerText);
    PayloadObj := TJSONObject(InnerJson);
    AssertTrue(PayloadObj.Booleans['ok']);
    AssertEquals(116, PayloadObj.Integers['studioCatalogCount']);
    AssertEquals(19, PayloadObj.Integers['baselineDrawCalls']);
    AssertEquals(3, PayloadObj.Integers['optimizedDrawCalls']);
    AssertEquals(16, PayloadObj.Integers['savedDrawCalls']);
    AssertEquals(3, PayloadObj.Arrays['lodPlans'].Count);
  finally
    FreeAndNil(InnerJson);
    FreeAndNil(OuterJson);
    FreeAndNil(Srv);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolLodInstancing);

end.
