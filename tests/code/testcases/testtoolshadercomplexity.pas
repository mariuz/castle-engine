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

{ Automated tests for Phase 416: Viewport Overdraw, Transparency Stacking &
  Shader ALU Complexity Auditor + 136-Studio Hub / 23rd MCP Tool
  (cge_audit_overdraw_shaders). }
unit TestToolShaderComplexity;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolShaderComplexity = class(TCastleTestCase)
  published
    procedure TestEarlyZOpaqueOcclusionVs6xTranslucentSmokeAluStacking;
    procedure TestUnified136StudioHubCatalogAnd23rdMcpAuditOverdrawShadersTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  ToolShaderComplexity, ToolStudioHub, ToolMcpServer;

procedure TTestToolShaderComplexity.TestEarlyZOpaqueOcclusionVs6xTranslucentSmokeAluStacking;
var
  Root: TComponent;
  VP: TCastleViewport;
  RepSmoke, RepOpaque: TShaderComplexityReport;
  I: Integer;
  WallCard: TCastleBox;
  Md: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TShaderComplexityAuditor.SpawnStackedSmokeOverdrawDemo(Root, Root));

    { 1. 6 stacked semi-transparent SmokePlumeCard billboards bypass Early-Z:
         PeakTranslucentOverdraw = 6 and PeakTileAluInstructions = 6 * 96 = 576! }
    RepSmoke := TShaderComplexityAuditor.SharedAuditor.AuditViewportOverdraw(
      Root, 3, 320);
    AssertEquals(8, RepSmoke.AnalyzedLayerCount);
    AssertEquals(2, RepSmoke.OpaqueLayerCount);
    AssertEquals(6, RepSmoke.TranslucentLayerCount);
    AssertEquals(6, RepSmoke.PeakTranslucentOverdraw);
    AssertEquals(576, RepSmoke.PeakTileAluInstructions);
    AssertTrue('Stacked center smoke plumes trigger crimson overdraw hotspot tiles',
      RepSmoke.HotspotTileCount > 15);

    Md := TShaderComplexityAuditor.GenerateMarkdownReport(RepSmoke);
    AssertTrue(Pos('SmokePlumeCard_1', Md) > 0);
  finally
    FreeAndNil(Root);
  end;

  { 2. Compare 6 stacked OPAQUE walls along the exact same Z sightline:
       Early-Z pays 48 ALU on front wall + 5 * 8 = 40 Early-Z cycles = 88 ALU (0 hotspots)! }
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    for I := 0 to 5 do
    begin
      WallCard := TCastleBox.Create(Root);
      WallCard.Name := Format('OpaqueCutoutCard_%d', [I + 1]);
      WallCard.Size := Vector3(5.0, 4.5, 0.08);
      WallCard.Translation := Vector3(0.0, 2.0, -2.5 + I * 1.0);
      WallCard.Color := Vector4(0.5, 0.5, 0.5, 1.0);
      VP.Items.Add(WallCard);
    end;
    RepOpaque := TShaderComplexityAuditor.SharedAuditor.AuditViewportOverdraw(
      Root, 3, 320);
    AssertEquals(0, RepOpaque.PeakTranslucentOverdraw);
    AssertEquals(88, RepOpaque.PeakTileAluInstructions);
    AssertEquals(0, RepOpaque.HotspotTileCount);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolShaderComplexity.TestUnified136StudioHubCatalogAnd23rdMcpAuditOverdrawShadersTool;
const
  Horizon11UeIds: array[0..13] of String = (
    'substrate_studio', 'fire_grid_2d', 'gameplay_messenger',
    'octahedral_impostor', 'pose_snapshot', 'macro_recorder',
    'gravity_field', 'cloud_shadows', 'prefab_diff_merge',
    'ballistic_studio', 'acoustic_space', 'budget_treemap',
    'lod_instancing', 'shader_complexity'
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
  for I := 0 to High(Horizon11UeIds) do
    AssertTrue('Missing Horizon 11 UE studio: ' + Horizon11UeIds[I],
      TStudioHubManager.FindStudioById(Horizon11UeIds[I], Entry));
  AssertEquals(380, Entry.PhaseNumber);

  { 2. Verify 23rd MCP tool cge_audit_overdraw_shaders over JSON-RPC 2.0 }
  Root := TComponent.Create(nil);
  Srv := TCastleMcpServer.Create(nil);
  OuterJson := nil;
  InnerJson := nil;
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TShaderComplexityAuditor.SpawnStackedSmokeOverdrawDemo(Root, Root));

    Srv.AutonomyMode := mamReadOnly;
    Srv.StandaloneDesignRoot := Root;
    Srv.StandaloneDesignOwner := Root;

    ListResp := Srv.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}', '');
    OuterJson := GetJSON(ListResp);
    ToolsArr := TJSONObject(OuterJson).Objects['result'].Arrays['tools'];
    AssertEquals(39, ToolsArr.Count);
    AssertTrue(Pos('cge_audit_overdraw_shaders', ListResp) > 0);
    FreeAndNil(OuterJson);

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_audit_overdraw_shaders","arguments":{"action":"audit_viewport","maxTranslucentLayers":3}}}',
      '');
    OuterJson := GetJSON(CallResp);
    InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
    InnerJson := GetJSON(InnerText);
    PayloadObj := TJSONObject(InnerJson);
    AssertTrue(PayloadObj.Booleans['ok']);
    AssertEquals(116, PayloadObj.Integers['studioCatalogCount']);
    AssertEquals(6, PayloadObj.Integers['peakTranslucentOverdraw']);
    AssertEquals(576, PayloadObj.Integers['peakTileAluInstructions']);
    AssertTrue(PayloadObj.Integers['hotspotTileCount'] > 15);
  finally
    FreeAndNil(InnerJson);
    FreeAndNil(OuterJson);
    FreeAndNil(Srv);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolShaderComplexity);

end.
