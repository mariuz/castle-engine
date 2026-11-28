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

{ Automated tests for Phase 382: PCG Visual Node Graph Editor (UPCGGraph Parity:
  Surface & Spline Samplers, Density Noise/Filter, WorldRay Normal Slope Filter,
  Spatial Difference, Union, Self-Pruning Zero-Overlap Invariant, Per-Node
  Point Inspection, DAG Cycle Guard, 102-Studio Hub & 25th MCP Tool
  cge_execute_pcg_graph). }
unit TestToolPcgGraph;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolPcgGraph = class(TCastleTestCase)
  published
    procedure TestForestRoadDifferenceSelfPruningZeroOverlapSeededDeterminismAndCleanJsonRoundtrip;
    procedure TestWorldRaySlopeFilterUnionAndCycleValidation;
    procedure TestUnified102StudioHubAnd25thMcpExecutePcgGraphTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastlePcgGraph, ToolPcgGraph, ToolStudioHub, ToolMcpServer;

procedure TTestToolPcgGraph.TestForestRoadDifferenceSelfPruningZeroOverlapSeededDeterminismAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  G, LoadedG: TCastlePcgGraph;
  SurfPts, DensePts, DiffPts, PrunePts, ReseedPts: TPcgPointArray;
  I, J, CountSeed1337: Integer;
  FirstPos1337: TVector3;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    G := TPcgGraphHelper.SpawnPcgPresetInDesign(
      VP, Root, pgpForestWithRoadClearing, Vector3(0, 0, 0));
    AssertTrue(G <> nil);
    AssertTrue(G.LastExecutionValid);
    AssertTrue(G.SpawnedMeshCount > 0);

    { 1. Per-node point-cloudmonotonicity & Road Clearing Difference }
    AssertTrue(G.EvaluateNodeOutput('Surface_Forest', SurfPts));
    AssertTrue(G.EvaluateNodeOutput('Filter_Dense', DensePts));
    AssertTrue(G.EvaluateNodeOutput('Diff_ClearRoad', DiffPts));
    AssertTrue(G.EvaluateNodeOutput('Prune_NoOverlap', PrunePts));

    AssertTrue(Length(SurfPts) > 80);
    AssertTrue(Length(DensePts) < Length(SurfPts));
    AssertTrue('Road Difference must subtract forest points intersecting the Z=0 road spline',
      Length(DiffPts) < Length(DensePts));
    AssertTrue(Length(PrunePts) <= Length(DiffPts));
    AssertEquals(Length(PrunePts), G.SpawnedMeshCount);

    { Every point surviving Diff_ClearRoad must clear the Z=0 road centerline! }
    for I := 0 to High(DiffPts) do
      AssertTrue('No tree point may remain inside the road centerline corridor',
        Abs(DiffPts[I].Position.Z) > 2.5);

    { 2. Self-Pruning Zero-Overlap Invariant }
    for I := 0 to High(PrunePts) - 1 do
      for J := I + 1 to High(PrunePts) do
        AssertFalse('Self-Pruning must guarantee 0 overlapping point bounds',
          TCastlePcgGraph.PointsBoundsOverlap3D(PrunePts[I], PrunePts[J], 1.0));

    { 3. Deterministic Seed Reproducibility }
    CountSeed1337 := G.SpawnedMeshCount;
    FirstPos1337 := PrunePts[0].Position;

    G.GraphSeed := 9001;
    AssertTrue(G.EvaluateNodeOutput('Prune_NoOverlap', ReseedPts));
    AssertTrue((Length(ReseedPts) <> CountSeed1337) or
      (not TVector3.Equals(ReseedPts[0].Position, FirstPos1337)));

    G.GraphSeed := 1337;
    AssertTrue(G.EvaluateNodeOutput('Prune_NoOverlap', ReseedPts));
    AssertEquals(CountSeed1337, Length(ReseedPts));
    AssertVectorEquals(FirstPos1337, ReseedPts[0].Position, 1e-4);

    { 4. Clean JSON Roundtrip without leaking SetTransient spawned instances }
    G.GraphSeed := 7777;
    JsonStr := ComponentToString(G);
    AssertTrue('SetTransient PCG_Inst_1 must not leak into serialized JSON',
      Pos('PCG_Inst_1', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedG := StringToComponent(JsonStr, LoadOwner) as TCastlePcgGraph;
      AssertTrue(LoadedG <> nil);
      AssertEquals(7777, LoadedG.GraphSeed);
      AssertEquals(G.SpawnedMeshCount, LoadedG.SpawnedMeshCount);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolPcgGraph.TestWorldRaySlopeFilterUnionAndCycleValidation;
var
  Root: TComponent;
  VP: TCastleViewport;
  FlatBox, SteepRamp: TCastleBox;
  G, CycleG: TCastlePcgGraph;
  N: TPcgGraphNode;
  FlatPts, SteepPts, UnionPts: TPcgPointArray;
  I: Integer;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    { Left half (X < 0): flat terrace (0 deg slope) }
    FlatBox := TCastleBox.Create(Root);
    FlatBox.Name := 'FlatTerrace';
    FlatBox.Size := Vector3(10.0, 1.0, 14.0);
    FlatBox.Translation := Vector3(-6.0, -0.5, 0.0);
    VP.Items.Add(FlatBox);

    { Right half (X > 0): 45-degree tilted ramp }
    SteepRamp := TCastleBox.Create(Root);
    SteepRamp.Name := 'SteepCliffRamp';
    SteepRamp.Size := Vector3(10.0, 1.0, 14.0);
    SteepRamp.Translation := Vector3(6.0, 0.0, 0.0);
    SteepRamp.Rotation := Vector4(0, 0, 1, DegToRad(45.0));
    VP.Items.Add(SteepRamp);

    G := TCastlePcgGraph.Create(Root);
    G.ClearGraph;
    G.VolumeHalfExtents := Vector3(9.0, 10.0, 4.0);
    G.ProjectToWorldRay := True;
    VP.Items.Add(G);

    N := TCastlePcgGraph.MakeDefaultNode('Surf', pnkSurfaceSampler, 20, 40);
    N.ParamA := 2.5;
    N.ParamB := 0.0; { Exact grid }
    G.AddOrUpdateNode(N);

    N := TCastlePcgGraph.MakeDefaultNode('FlatOnly', pnkNormalSlopeFilter, 220, 20);
    N.ParamA := 0.0;
    N.ParamB := 15.0;
    N.InputNode0 := 'Surf';
    G.AddOrUpdateNode(N);

    N := TCastlePcgGraph.MakeDefaultNode('SteepOnly', pnkNormalSlopeFilter, 220, 120);
    N.ParamA := 30.0;
    N.ParamB := 60.0;
    N.InputNode0 := 'Surf';
    G.AddOrUpdateNode(N);

    N := TCastlePcgGraph.MakeDefaultNode('BothUnion', pnkUnion, 420, 70);
    N.InputNode0 := 'FlatOnly';
    N.InputNode1 := 'SteepOnly';
    G.AddOrUpdateNode(N);

    AssertTrue(G.ExecuteGraph);
    AssertTrue(G.EvaluateNodeOutput('FlatOnly', FlatPts));
    AssertTrue(G.EvaluateNodeOutput('SteepOnly', SteepPts));
    AssertTrue(G.EvaluateNodeOutput('BothUnion', UnionPts));

    AssertTrue(Length(FlatPts) > 0);
    AssertTrue(Length(SteepPts) > 0);
    AssertEquals(Length(FlatPts) + Length(SteepPts), Length(UnionPts));

    for I := 0 to High(FlatPts) do
      AssertTrue('Flat slope filter must only accept terrace points (X < 0)',
        FlatPts[I].Position.X < 0.0);
    for I := 0 to High(SteepPts) do
      AssertTrue('Steep slope filter must only accept 45-deg ramp points (X > 0)',
        SteepPts[I].Position.X > 0.0);

    { Directed Cycle Detection }
    CycleG := TCastlePcgGraph.Create(Root);
    CycleG.ClearGraph;
    N := TCastlePcgGraph.MakeDefaultNode('NodeA', pnkBoundsModifier, 20, 20);
    N.InputNode0 := 'NodeB';
    CycleG.AddOrUpdateNode(N);
    N := TCastlePcgGraph.MakeDefaultNode('NodeB', pnkSelfPruning, 180, 20);
    N.InputNode0 := 'NodeA';
    CycleG.AddOrUpdateNode(N);

    AssertFalse(CycleG.ValidateGraph);
    AssertFalse(CycleG.ExecuteGraph);
    AssertTrue(CycleG.ValidationErrors.Count >= 1);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolPcgGraph.TestUnified102StudioHubAnd25thMcpExecutePcgGraphTool;
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
  { 1. Verify 102 UE Studios in Studio Hub (Phase 382 pcg_graph) }
  AssertEquals(118, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('pcg_graph', Entry));
  AssertEquals(382, Entry.PhaseNumber);

  { 2. Verify 25th MCP tool cge_execute_pcg_graph }
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Srv := TCastleMcpServer.Create(Root);
    Srv.AutonomyMode := mamEditWithUndo;
    Srv.StandaloneDesignRoot := VP;
    Srv.StandaloneDesignOwner := Root;

    ListResp := Srv.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
    OuterJson := GetJSON(ListResp);
    try
      ToolsArr := OuterJson.FindPath('result.tools') as TJSONArray;
      AssertTrue(ToolsArr <> nil);
      AssertEquals(41, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_execute_pcg_graph","arguments":{"action":"spawn_preset","preset":"forest_road"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['graphCount']);
        AssertEquals(1, PayloadObj.Integers['validGraphCount']);
        AssertTrue(PayloadObj.Integers['totalSpawnedInstances'] > 0);
        AssertEquals(118, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_execute_pcg_graph","arguments":{"action":"inspect_node","nodeId":"Diff_ClearRoad"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals('Diff_ClearRoad', PayloadObj.Strings['inspectedNodeId']);
        AssertTrue(PayloadObj.Integers['inspectedPointCount'] > 0);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolPcgGraph);
end.
