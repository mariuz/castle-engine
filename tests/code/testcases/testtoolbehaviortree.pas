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

{ Automated tests for Phase 384: Behavior Tree & Blackboard Visual Editor
  (UBehaviorTree Parity: Selector, Sequence, SimpleParallel, ExecutionIndex
  Left-to-Right Priority Ordering, Decorator Observer Aborts [LowerPriority &
  Self], Periodic Branch Services, 104-Studio Hub & 27th MCP Tool
  cge_tick_behavior_tree). }
unit TestToolBehaviorTree;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolBehaviorTree = class(TCastleTestCase)
  published
    procedure TestLowerPriorityPreemptionSelfAbortPeriodicServiceAndCleanJsonRoundtrip;
    procedure TestSimpleParallelConcurrentBackgroundSubtreeAndAmmoFallback;
    procedure TestUnified104StudioHubAnd27thMcpTickBehaviorTreeTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleBehaviorTree, ToolBehaviorTree, ToolStudioHub, ToolMcpServer;

procedure TTestToolBehaviorTree.TestLowerPriorityPreemptionSelfAbortPeriodicServiceAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Bt, LoadedBt: TCastleBehaviorTree;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Bt := TBehaviorTreeHelper.SpawnBehaviorTreePresetInDesign(
      VP, Root, btpTacticalGuardObserverAborts, Vector3(0, 0, 0));
    AssertTrue(Bt <> nil);
    AssertTrue(Bt.LastTreeValid);

    { 1. HasLineOfSight = False -> Selector skips Seq_Combat and enters lower-priority Seq_Patrol!
         MoveTo PatrolPoint (-4,0,0) @ 4 m/s reaches (-4,0,0) in 1.0s and Sequence immediately enters Task_PatrolWait (Running)! }
    AssertTrue(Bt.TickBehaviorTree(1.0) = btsRunning);
    AssertEquals('Task_PatrolWait', Bt.RunningLeafNodeId);
    AssertSameValue(-4.0, Bt.Translation.X, 1e-3);

    { Tick 0.5s inside Task_PatrolWait -> still waiting (0.5 / 4.0s) }
    AssertTrue(Bt.TickBehaviorTree(0.5) = btsRunning);
    AssertEquals('Task_PatrolWait', Bt.RunningLeafNodeId);
    AssertEquals(0, Bt.AbortCount);

    { 2. Spot Enemy! Set HasLineOfSight := True while mid-Wait in lower-priority Patrol ->
         ObserverAborts = Both triggers LowerPriority preemption into Task_ChaseTarget! }
    Bt.SetBlackboardBool('HasLineOfSight', True);
    AssertTrue(Bt.TickBehaviorTree(0.50) = btsRunning);
    AssertEquals(1, Bt.AbortCount);
    AssertEquals('Task_ChaseTarget', Bt.RunningLeafNodeId);
    AssertTrue('Guard moved +3.0m from -4.0 toward TargetLocation (+8.0)',
      Bt.Translation.X > -1.1);
    { Periodic Service (0.25s interval) ticked twice during 0.50s inside Seq_Combat! }
    AssertEquals(2, Bt.ServiceTickCount);

    { 3. Lose Sight mid-chase! Set HasLineOfSight := False ->
         ObserverAborts = Both triggers Self abort out of Task_ChaseTarget back to Patrol! }
    Bt.SetBlackboardBool('HasLineOfSight', False);
    AssertTrue(Bt.TickBehaviorTree(0.25) = btsRunning);
    AssertEquals(2, Bt.AbortCount);
    AssertEquals('Task_MovePatrol', Bt.RunningLeafNodeId);

    { 4. SetTransient-clean JSON roundtrip }
    Bt.SetBlackboardFloat('DistanceToTarget', 12.5);
    JsonStr := ComponentToString(Bt);
    AssertTrue('SetTransient BT_AgentPreview must not leak into serialized JSON',
      Pos('BT_AgentPreview', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedBt := StringToComponent(JsonStr, LoadOwner) as TCastleBehaviorTree;
      AssertTrue(LoadedBt <> nil);
      AssertSameValue(12.5, LoadedBt.GetBlackboardFloat('DistanceToTarget'), 1e-3);
      AssertEquals(Length(Bt.Nodes), Length(LoadedBt.Nodes));
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolBehaviorTree.TestSimpleParallelConcurrentBackgroundSubtreeAndAmmoFallback;
var
  Root: TComponent;
  VP: TCastleViewport;
  ParBt, AmmoBt, BadBt: TCastleBehaviorTree;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    { 1. SimpleParallel runs Main_MoveCover (6m @ 3 m/s = 2.0s) while firing Bg_SuppressShot every tick! }
    ParBt := TBehaviorTreeHelper.SpawnBehaviorTreePresetInDesign(
      VP, Root, btpSimpleParallelSuppressAndMove, Vector3(0, 0, 0));
    AssertTrue(ParBt.TickBehaviorTree(0.5) = btsRunning);
    AssertTrue(ParBt.TickBehaviorTree(0.5) = btsRunning);
    AssertTrue(ParBt.TickBehaviorTree(0.5) = btsRunning);
    AssertEquals('Background suppression task fired on all 3 Running ticks',
      3, ParBt.GetBlackboardInt('BurstShotsFired'));
    { Final 0.5s reaches CoverPoint (6,0,0) -> Main Task succeeds and finishes SimpleParallel! }
    AssertTrue(ParBt.TickBehaviorTree(0.5) = btsSucceeded);
    AssertSameValue(6.0, ParBt.Translation.X, 1e-3);

    { 2. Selector with Decorator > 0 Ammo fires twice (2->1->0), then falls back to Reload (+6)! }
    AmmoBt := TBehaviorTreeHelper.SpawnBehaviorTreePresetInDesign(
      VP, Root, btpAmmoReloadFallbackSequence, Vector3(0, 0, -4));
    AssertEquals(2, AmmoBt.GetBlackboardInt('AmmoCount'));
    AssertTrue(AmmoBt.TickBehaviorTree(0.1) = btsSucceeded);
    AssertEquals(1, AmmoBt.GetBlackboardInt('AmmoCount'));
    AssertTrue(AmmoBt.TickBehaviorTree(0.1) = btsSucceeded);
    AssertEquals(0, AmmoBt.GetBlackboardInt('AmmoCount'));
    { Now AmmoCount == 0 -> Decorator on Task_FireRound fails -> Selector falls back to Task_ReloadMag (+6)! }
    AssertTrue(AmmoBt.TickBehaviorTree(0.1) = btsSucceeded);
    AssertEquals(6, AmmoBt.GetBlackboardInt('AmmoCount'));

    { 3. Validation rejects tree with 0 Root nodes }
    BadBt := TCastleBehaviorTree.Create(Root);
    BadBt.ClearTree;
    AssertFalse(BadBt.ValidateBehaviorTree);
    AssertTrue(BadBt.TickBehaviorTree(0.1) = btsFailed);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolBehaviorTree.TestUnified104StudioHubAnd27thMcpTickBehaviorTreeTool;
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
  { 1. Verify 104 UE Studios in Studio Hub (Phase 384 behavior_tree) }
  AssertEquals(112, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('behavior_tree', Entry));
  AssertEquals(384, Entry.PhaseNumber);

  { 2. Verify 27th MCP tool cge_tick_behavior_tree }
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
      AssertEquals(35, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_tick_behavior_tree","arguments":{"action":"spawn_preset","preset":"tactical_guard"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['treeCount']);
        AssertEquals(1, PayloadObj.Integers['validTreeCount']);
        AssertEquals(8, PayloadObj.Integers['totalNodeCount']);
        AssertEquals(112, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_tick_behavior_tree","arguments":{"action":"tick","deltaSec":0.5}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals('Task_MovePatrol', PayloadObj.Strings['runningLeafNodeId']);
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
  RegisterTest(TTestToolBehaviorTree);
end.
