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

{ Automated tests for Phase 396: Squarified Scene Memory/Triangle Budget
  Treemap + 116-Studio Hub / 21st MCP Tool (cge_audit_scene_budget). }
unit TestToolBudgetTreemap;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolBudgetTreemap = class(TCastleTestCase)
  published
    procedure TestSquarifiedTreemapAreaPartitionNonOverlapAndOutlierDetection;
    procedure TestUnified116StudioHubCatalogAnd21stMcpAuditSceneBudgetTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  ToolBudgetTreemap, ToolStudioHub, ToolMcpServer;

procedure TTestToolBudgetTreemap.TestSquarifiedTreemapAreaPartitionNonOverlapAndOutlierDetection;
var
  Root: TComponent;
  VP: TCastleViewport;
  Rep, StrictRep: TSceneBudgetTreemapReport;
  SumCellArea, ExpectedCanvasArea, OverlapW, OverlapH: Single;
  I, J: Integer;
  A, B: TBudgetTreemapCell;
  Md: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TSceneBudgetTreemapAnalyzer.SpawnSyntheticHeavySceneDemo(Root, Root));

    Rep := TSceneBudgetTreemapAnalyzer.SharedAnalyzer.AnalyzeSceneTreemap(
      Root, 8192.0, 2048.0, 600.0, 400.0);

    { 5 weighted demo transforms: 4200 + 1800 + 960 + 480 + 220 = 7660 KB }
    AssertEquals(5, Rep.TotalComponents);
    AssertSameValue(7660.0, Rep.TotalEstimatedMemoryKB, 0.5);
    { Only BossTitanStatueUncompressed (4200 KB) exceeds 2048 KB cap }
    AssertEquals(1, Rep.OverBudgetNodeCount);
    AssertEquals('BossTitanStatueUncompressed', Rep.Cells[0].ComponentName);
    AssertTrue(Rep.Cells[0].IsOverNodeCap);

    { 1. Exact area conservation across [0..600] x [0..400] }
    ExpectedCanvasArea := 600.0 * 400.0;
    SumCellArea := 0.0;
    for I := 0 to High(Rep.Cells) do
    begin
      A := Rep.Cells[I];
      AssertTrue((A.RectW > 0.0) and (A.RectH > 0.0));
      SumCellArea := SumCellArea + (A.RectW * A.RectH);
    end;
    AssertSameValue(ExpectedCanvasArea, SumCellArea, 1.0);

    { 2. Pairwise interior non-overlap across all 5 squarified cells }
    for I := 0 to High(Rep.Cells) - 1 do
      for J := I + 1 to High(Rep.Cells) do
      begin
        A := Rep.Cells[I];
        B := Rep.Cells[J];
        OverlapW := Min(A.RectX + A.RectW, B.RectX + B.RectW) - Max(A.RectX, B.RectX);
        OverlapH := Min(A.RectY + A.RectH, B.RectY + B.RectH) - Max(A.RectY, B.RectY);
        AssertTrue('Squarified treemap cells must have zero interior overlap',
          (OverlapW <= 0.01) or (OverlapH <= 0.01));
      end;

    { 3. Compact Bruls-Huizing-van Wijk aspect ratio (< 3.5:1 across all cells) }
    AssertTrue('Squarified layout avoids thin slivers',
      Rep.WorstCellAspectRatio < 3.5);

    { Lowering PerNodeCapKB to 800 KB flags 3 outliers (4200, 1800, 960) }
    StrictRep := TSceneBudgetTreemapAnalyzer.SharedAnalyzer.AnalyzeSceneTreemap(
      Root, 8192.0, 800.0, 600.0, 400.0);
    AssertEquals(3, StrictRep.OverBudgetNodeCount);

    Md := TSceneBudgetTreemapAnalyzer.GenerateMarkdownReport(Rep);
    AssertTrue(Pos('BossTitanStatueUncompressed', Md) > 0);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolBudgetTreemap.TestUnified116StudioHubCatalogAnd21stMcpAuditSceneBudgetTool;
var
  Root: TComponent;
  VP: TCastleViewport;
  Entry: TStudioCatalogEntry;
  Srv: TCastleMcpServer;
  ListResp, CallResp, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  ToolsArr: TJSONArray;
  PayloadObj: TJSONObject;
begin
  { 1. Verify all 100 UE 5.x studios (Horizons 2-11, Phases 1-380) are registered }
  AssertEquals(113, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('ballistic_studio', Entry));
  AssertTrue(TStudioHubManager.FindStudioById('acoustic_space', Entry));
  AssertTrue(TStudioHubManager.FindStudioById('budget_treemap', Entry));
  AssertEquals(378, Entry.PhaseNumber);

  { 2. Verify 21st MCP tool cge_audit_scene_budget over JSON-RPC 2.0 }
  Root := TComponent.Create(nil);
  Srv := TCastleMcpServer.Create(nil);
  OuterJson := nil;
  InnerJson := nil;
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TSceneBudgetTreemapAnalyzer.SpawnSyntheticHeavySceneDemo(Root, Root));

    Srv.AutonomyMode := mamReadOnly;
    Srv.StandaloneDesignRoot := Root;
    Srv.StandaloneDesignOwner := Root;

    ListResp := Srv.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}', '');
    OuterJson := GetJSON(ListResp);
    ToolsArr := TJSONObject(OuterJson).Objects['result'].Arrays['tools'];
    AssertEquals(36, ToolsArr.Count);
    FreeAndNil(OuterJson);

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_audit_scene_budget","arguments":{"action":"audit_viewport","perNodeCapKB":1500}}}',
      '');
    OuterJson := GetJSON(CallResp);
    InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
    InnerJson := GetJSON(InnerText);
    PayloadObj := TJSONObject(InnerJson);
    AssertTrue(PayloadObj.Booleans['ok']);
    AssertEquals(113, PayloadObj.Integers['studioCatalogCount']);
    AssertEquals(2, PayloadObj.Integers['overBudgetNodeCount']);
    AssertEquals(5, PayloadObj.Arrays['cells'].Count);
  finally
    FreeAndNil(InnerJson);
    FreeAndNil(OuterJson);
    FreeAndNil(Srv);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolBudgetTreemap);

end.
