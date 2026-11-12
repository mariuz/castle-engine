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

{ Automated unit tests for Phase 307: Visual Node-Based PBR Material &
  X3D Shader Effect Graph Studio (@link(TCastleMaterialGraph),
  @link(TCastleMaterialGraphBehavior), @link(TMaterialGraphHelper)). }
unit TestToolMaterialGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolMaterialGraph = class(TCastleTestCase)
  published
    procedure TestTopologicalGlslCompilationCycleDetectionAndJsonRoundtrip;
    procedure TestAllPresetsLiveEffectNodeAttachmentTimeUniformAndPreviewEvaluator;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleTransform, CastleScene, CastleViewport,
  CastleComponentSerialize, X3DNodes, X3DFields,
  CastleMaterialGraph, ToolMaterialGraph;

procedure TTestToolMaterialGraph.TestTopologicalGlslCompilationCycleDetectionAndJsonRoundtrip;
var
  Graph, RestoredGraph: TCastleMaterialGraph;
  RestoredOwner: TComponent;
  N: TMaterialGraphNode;
  Errors: TStringList;
  VertSrc, FragSrc, JsonStr: String;
  PosNoise, PosMask, PosMix: SizeInt;
  Order: array[0..15] of Integer;
  OrderCount: Integer;
begin
  Graph := TCastleMaterialGraph.Create(nil);
  Errors := TStringList.Create;
  RestoredOwner := TComponent.Create(nil);
  try
    Graph.Name := 'DiamondTestGraph';
    Graph.LoadPreset(mgpTriplanarMossyRock);

    { Add a diamond share: feed RockNoise into both MossMask and a second Multiply node,
      plus connect a WindWave node to PositionOffset (pin 5). }
    N := TCastleMaterialGraph.MakeDefaultNode('TintBoost', mnkMultiply, 320, 120);
    N.Inputs[0] := 'RockMossMix';
    N.Inputs[1] := 'MossMask';
    Graph.AddOrUpdateNode(N);

    N := TCastleMaterialGraph.MakeDefaultNode('WindWave', mnkVertexWaveOffset, 320, 260);
    N.ParamA := 3.5;
    N.ParamB := 2.0;
    N.ParamC := 0.18;
    N.Inputs[0] := 'RockNoise';
    Graph.AddOrUpdateNode(N);

    AssertTrue(Graph.ConnectPin('Output', 0, 'TintBoost'));
    AssertTrue(Graph.ConnectPin('Output', 5, 'WindWave'));
    Graph.AlphaClipThreshold := 0.35;

    AssertTrue(Graph.HasVertexOffsetConnection);
    AssertTrue(Graph.ValidateGraph(Errors));
    AssertEquals(0, Errors.Count);

    VertSrc := Graph.BuildVertexShaderSource;
    FragSrc := Graph.BuildFragmentShaderSource;

    AssertTrue(Pos('PLUG_vertex_object_space_change', VertSrc) > 0);
    AssertTrue(Pos('WindWave', VertSrc) > 0);
    AssertTrue(Pos('PLUG_main_texture_apply', FragSrc) > 0);
    AssertTrue(Pos('PLUG_material_metallic_roughness', FragSrc) > 0);
    AssertTrue(Pos('PLUG_lighting_apply', FragSrc) > 0);
    AssertTrue(Pos('discard;', FragSrc) > 0);

    { Verify strict topological ordering in BaseColor stage:
      RockNoise -> MossMask & RockMossMix -> TintBoost }
    PosNoise := Pos('RockNoise =', FragSrc);
    PosMask := Pos('MossMask =', FragSrc);
    PosMix := Pos('TintBoost =', FragSrc);
    AssertTrue(PosNoise > 0);
    AssertTrue(PosMask > PosNoise);
    AssertTrue(PosMix > PosMask);

    { Deliberately introduce a cycle: RockNoise -> MossMask -> RockNoise }
    AssertTrue(Graph.ConnectPin('RockNoise', 0, 'MossMask'));
    Errors.Clear;
    AssertFalse(Graph.ValidateGraph(Errors));
    AssertTrue(Errors.Count > 0);
    AssertTrue(Pos('Cycle detected', Errors.Text) > 0);
    AssertFalse(Graph.BuildTopologicalOrder([Graph.FindOutputNodeIndex], Order, OrderCount));

    { Repair cycle back to ObjPos and test ComponentToString / StringToComponent JSON roundtrip }
    AssertTrue(Graph.ConnectPin('RockNoise', 0, 'ObjPos'));
    Errors.Clear;
    AssertTrue(Graph.ValidateGraph(Errors));

    JsonStr := ComponentToString(Graph);
    RestoredGraph := StringToComponent(JsonStr, RestoredOwner) as TCastleMaterialGraph;
    AssertTrue(RestoredGraph <> nil);
    AssertEquals(Graph.NodeCount, RestoredGraph.NodeCount);
    AssertSameValue(0.35, RestoredGraph.AlphaClipThreshold, 1e-4);
    AssertTrue(RestoredGraph.HasVertexOffsetConnection);
    AssertEquals('TintBoost', RestoredGraph.Nodes[RestoredGraph.FindOutputNodeIndex].Inputs[0]);
    AssertEquals('WindWave', RestoredGraph.Nodes[RestoredGraph.FindOutputNodeIndex].Inputs[5]);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(Errors);
    FreeAndNil(Graph);
  end;
end;

procedure TTestToolMaterialGraph.TestAllPresetsLiveEffectNodeAttachmentTimeUniformAndPreviewEvaluator;
var
  DesignOwner: TComponent;
  Viewport: TCastleViewport;
  Graph: TCastleMaterialGraph;
  Sphere: TCastleSphere;
  Behav: TCastleMaterialGraphBehavior;
  RemoveMe: TRemoveType;
  P: TMaterialGraphPreset;
  LavaCenter, GoldCenter, HoloSample: TCastleColor;
  FoundClippedScanline: Boolean;
  StepIdx: Integer;
  Report: TMaterialGraphAuditReport;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Viewport := TCastleViewport.Create(DesignOwner);
    Viewport.Name := 'MainViewport';

    Graph := TMaterialGraphHelper.CreateMaterialGraphInDesign(
      Viewport, DesignOwner, mgpTriplanarMossyRock, 'HeroMaterialGraph');
    AssertTrue(Graph <> nil);

    Sphere := TMaterialGraphHelper.SpawnPreviewSphereWithGraph(Viewport, DesignOwner, Graph);
    AssertTrue(Sphere <> nil);

    Behav := Sphere.FindBehavior(TCastleMaterialGraphBehavior) as TCastleMaterialGraphBehavior;
    AssertTrue(Behav <> nil);
    AssertTrue(Behav.ActiveEffectNode <> nil);
    AssertEquals(2, Behav.ActiveEffectNode.FdParts.Count);
    AssertTrue(Behav.ActiveTimeField <> nil);

    RemoveMe := rtNone;
    Behav.Update(0.5, RemoveMe);
    Behav.Update(0.75, RemoveMe);
    AssertSameValue(1.25, Behav.ElapsedTime, 1e-4);
    AssertSameValue(1.25, Behav.ActiveTimeField.Value, 1e-4);

    { Cycle all 5 built-in presets and verify live EffectNode rebuild + CPU sphere preview }
    LavaCenter := Vector4(0, 0, 0, 0);
    GoldCenter := Vector4(0, 0, 0, 0);
    FoundClippedScanline := false;

    for P := mgpTriplanarMossyRock to mgpAnimatedWindWaveFoliage do
    begin
      Graph.LoadPreset(P);
      Behav.Update(0.1, RemoveMe);
      AssertTrue(Behav.ActiveEffectNode <> nil);
      AssertEquals(2, Behav.ActiveEffectNode.FdParts.Count);

      if P = mgpMoltenLavaCracks then
        LavaCenter := Graph.EvaluatePreviewPixel(0.45, 0.45, 0.5, false)
      else if P = mgpBrushedGoldMetal then
        GoldCenter := Graph.EvaluatePreviewPixel(0.45, 0.45, 0.5, false)
      else if P = mgpHologramScanline then
      begin
        for StepIdx := 20 to 80 do
        begin
          HoloSample := Graph.EvaluatePreviewPixel(0.5, StepIdx / 100.0, 0.25, false);
          if HoloSample.W < 0.01 then
            FoundClippedScanline := true;
        end;
      end;
    end;

    AssertTrue(FoundClippedScanline);
    AssertTrue(PointsDistance(LavaCenter.XYZ, GoldCenter.XYZ) > 0.08);

    Report := TMaterialGraphHelper.ScanDesign(Viewport, DesignOwner);
    try
      AssertEquals(1, Length(Report.Graphs));
      AssertEquals(1, Length(Report.Behaviors));
      AssertEquals(0, Report.Warnings.Count);
    finally
      FreeAndNil(Report);
    end;

    Md := TMaterialGraphHelper.BuildMarkdownReport(Viewport, DesignOwner, Graph);
    AssertTrue(Pos('# Castle Material & Shader Effect Graph Studio Report', Md) > 0);
    AssertTrue(Pos('PLUG_lighting_apply', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolMaterialGraph);
end.
