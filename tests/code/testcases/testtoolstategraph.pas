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

{ Automated tests for @link(TCastleStateGraphBehavior) and
  @link(TStateGraphHelper) (Phase 288 — UE 5.9 / 6.0 StateTree Parity). }
unit TestToolStateGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolStateGraph = class(TCastleTestCase)
  strict private
    FLastFromState, FLastToState: String;
    FCueNames: TStringList;
    procedure HandleStateTransition(Sender: TObject;
      const FromStateId, ToStateId: String);
    procedure HandleStateCue(Sender: TObject;
      const CueName, Payload: String);
  published
    procedure TestStateGraphTransitionsWildcardActionsAndJsonRoundtrip;
    procedure TestTemplatesValidationAttachAndMermaidExport;
  end;

implementation

uses
  CastleVectors, CastleComponentSerialize, CastleTransform,
  CastleScene, CastleControls, CastleViewport,
  CastleStateGraph, ToolStateGraph;

procedure TTestToolStateGraph.HandleStateTransition(Sender: TObject;
  const FromStateId, ToStateId: String);
begin
  FLastFromState := FromStateId;
  FLastToState := ToStateId;
end;

procedure TTestToolStateGraph.HandleStateCue(Sender: TObject;
  const CueName, Payload: String);
begin
  if FCueNames <> nil then
    FCueNames.Add(CueName + ':' + Payload);
end;

procedure TTestToolStateGraph.TestStateGraphTransitionsWildcardActionsAndJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  GuardScene: TCastleScene;
  AlertLight: TCastlePointLight;
  StatusLabel: TCastleLabel;
  Graph, ReloadedGraph: TCastleStateGraphBehavior;
  SerializedJson: String;
  ReloadedRoot: TComponent;
begin
  FCueNames := TStringList.Create;
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    GuardScene := TCastleScene.Create(DesignOwner);
    GuardScene.Name := 'GuardMesh';

    AlertLight := TCastlePointLight.Create(DesignOwner);
    AlertLight.Name := 'AlertBeacon';
    AlertLight.Intensity := 0.0;
    GuardScene.Add(AlertLight);

    StatusLabel := TCastleLabel.Create(DesignOwner);
    StatusLabel.Name := 'HudAlertLabel';
    StatusLabel.Caption := 'CALM';

    Graph := TStateGraphHelper.AttachStateGraphToTransform(
      GuardScene, DesignOwner, 'GuardCombatFSM');
    Graph.OnStateTransition := @HandleStateTransition;
    Graph.OnStateCue := @HandleStateCue;

    TStateGraphHelper.ApplyGameplayTemplate(Graph, sgtAiPatrolChaseAttack);

    { Augment Chase and Flee states with concrete RTTI property actions }
    Graph.AddEntryAction('Chase', sakSetProperty, 'AlertBeacon', 'Intensity', '4.5', false);
    Graph.AddEntryAction('Chase', sakSetProperty, 'HudAlertLabel', 'Caption', 'HOSTILE SPOTTED', false);
    Graph.AddEntryAction('Chase', sakSetProperty, '$Parent', 'Translation', '3 0 -5', false);
    Graph.AddExitAction('Chase', sakSetProperty, 'AlertBeacon', 'Intensity', '0.5', false);

    AssertEquals(5, Graph.StateCount);
    AssertEquals(3, Graph.VariableCount);
    AssertEquals(8, Graph.TransitionCount);

    { 1. Start graph -> enters InitialStateId = 'Idle' }
    Graph.StartGraph;
    AssertEquals('Idle', Graph.ActiveStateId);
    AssertEquals('idle', Graph.LastPlayedAnimation);

    { 2. Elapsed-timer gate: Idle -> Patrol requires MinStateElapsedSec = 2.0s }
    Graph.StepGraph(1.2);
    AssertEquals('Idle', Graph.ActiveStateId);
    Graph.StepGraph(0.9);
    AssertEquals('Patrol', Graph.ActiveStateId);
    AssertEquals('walk', Graph.LastPlayedAnimation);

    { 3. Blackboard comparison: PlayerDistance <= 12 -> Chase + entry RTTI actions }
    Graph.SetFloat('PlayerDistance', 8.0);
    Graph.StepGraph(0.1);
    AssertEquals('Chase', Graph.ActiveStateId);
    AssertEquals('run', Graph.LastPlayedAnimation);
    AssertTrue(Graph.GetBool('Alerted'));
    AssertSameValue(4.5, AlertLight.Intensity, 0.001);
    AssertEquals('HOSTILE SPOTTED', StatusLabel.Caption);
    AssertVectorEquals(Vector3(3, 0, -5), GuardScene.Translation, 0.001);

    { 4. Melee range: PlayerDistance <= 2.5 -> Attack + OnMeleeStrike cue + Chase exit action }
    Graph.SetFloat('PlayerDistance', 1.8);
    Graph.StepGraph(0.05);
    AssertEquals('Attack', Graph.ActiveStateId);
    AssertEquals('attack', Graph.LastPlayedAnimation);
    AssertSameValue(0.5, AlertLight.Intensity, 0.001);
    AssertTrue(FCueNames.IndexOf('OnMeleeStrike:heavy') >= 0);

    { 5. High-priority Any-State ('*') interrupt: Health <= 20 -> Flee }
    Graph.SetFloat('Health', 14.0);
    Graph.StepGraph(0.05);
    AssertEquals('Flee', Graph.ActiveStateId);
    AssertEquals('Attack', FLastFromState);
    AssertEquals('Flee', FLastToState);
    AssertTrue(FCueNames.IndexOf('OnLowHealthRetreat:') >= 0);

    { 6. Full CGE JSON serialization roundtrip }
    Graph.MoveStateCanvas('Flee', 512.0, 288.0);
    SerializedJson := ComponentToString(GuardScene);
    ReloadedRoot := StringToComponent(SerializedJson, ReloadOwner);
    AssertTrue(ReloadedRoot is TCastleScene);
    ReloadedGraph := TCastleScene(ReloadedRoot).FindBehavior(
      TCastleStateGraphBehavior) as TCastleStateGraphBehavior;
    AssertTrue(ReloadedGraph <> nil);
    AssertEquals(5, ReloadedGraph.StateCount);
    AssertEquals(8, ReloadedGraph.TransitionCount);
    AssertEquals('Idle', ReloadedGraph.InitialStateId);
    AssertSameValue(512.0, ReloadedGraph.GetState(
      ReloadedGraph.FindStateIndex('Flee')).CanvasX, 0.01);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
    FreeAndNil(FCueNames);
  end;
end;

procedure TTestToolStateGraph.TestTemplatesValidationAttachAndMermaidExport;
var
  DesignOwner: TComponent;
  VP: TCastleViewport;
  DoorTransform: TCastleTransform;
  DoorGraph: TCastleStateGraphBehavior;
  Warnings: TStringList;
  Found: TStateGraphInfoArray;
  Markdown: String;
begin
  DesignOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    VP := TCastleViewport.Create(DesignOwner);
    VP.Name := 'ViewportMain';
    DoorTransform := TCastleTransform.Create(DesignOwner);
    DoorTransform.Name := 'CastleGateDoor';
    VP.Items.Add(DoorTransform);

    AssertTrue(DoorTransform = TStateGraphHelper.FindFirstTransformTarget(VP, nil));

    DoorGraph := TStateGraphHelper.AttachStateGraphToTransform(
      DoorTransform, DesignOwner, 'GateDoorFSM');
    TStateGraphHelper.ApplyGameplayTemplate(DoorGraph, sgtInteractiveDoor);

    { Clean template must pass reachability & variable validation }
    AssertTrue(TStateGraphHelper.ValidateGraph(DoorGraph, Warnings));
    AssertEquals(0, Warnings.Count);

    { Test Interactive Door lifecycle: Closed -> Opening -> Open -> auto-Close }
    DoorGraph.StartGraph;
    AssertEquals('Closed', DoorGraph.ActiveStateId);
    DoorGraph.SetBool('InteractPressed', true);
    DoorGraph.StepGraph(0.05);
    AssertEquals('Opening', DoorGraph.ActiveStateId);
    AssertFalse(DoorGraph.GetBool('InteractPressed'));
    DoorGraph.StepGraph(1.05);
    AssertEquals('Open', DoorGraph.ActiveStateId);
    DoorGraph.StepGraph(3.05);
    AssertEquals('Closed', DoorGraph.ActiveStateId);

    { Inject an unreachable island state & undeclared variable transition -> validator catches both }
    DoorGraph.AddOrUpdateState('OrphanSecretState', 'Unreachable', 800, 400);
    DoorGraph.AddTransition('Closed', 'Open', scoEqual, 'MissingKeyVar', 'true');
    AssertFalse(TStateGraphHelper.ValidateGraph(DoorGraph, Warnings));
    AssertEquals(2, Warnings.Count);

    { Remove invalid state & transition -> clean again }
    AssertTrue(DoorGraph.RemoveTransition(DoorGraph.TransitionCount - 1));
    AssertTrue(DoorGraph.RemoveState('OrphanSecretState'));
    AssertTrue(TStateGraphHelper.ValidateGraph(DoorGraph, Warnings));

    { ScanStateGraphs & Mermaid export }
    Found := TStateGraphHelper.ScanStateGraphs(VP);
    AssertEquals(1, Length(Found));
    AssertEquals('CastleGateDoor', Found[0].ParentTransformName);

    Markdown := TStateGraphHelper.FormatGraphMarkdown(DoorGraph);
    AssertTrue(Pos('stateDiagram-v2', Markdown) > 0);
    AssertTrue(Pos('[*] --> Closed', Markdown) > 0);
    AssertTrue(Pos('Opening --> Open', Markdown) > 0);

    { Also verify UI Menu Flow template }
    TStateGraphHelper.ApplyGameplayTemplate(DoorGraph, sgtUiMenuFlow);
    AssertTrue(TStateGraphHelper.ValidateGraph(DoorGraph, Warnings));
    AssertEquals(3, DoorGraph.StateCount);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolStateGraph);
end.
