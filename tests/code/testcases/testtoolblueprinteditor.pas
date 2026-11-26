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

{ Automated tests for Phase 381: Blueprint Visual Scripting Editor
  (EventGraph, Construction Script, Variables, Latent Delay/Timeline,
  Breakpoints, Infinite-Loop Guard, Pascal Nativizer, 101-Studio Hub &
  24th MCP Tool cge_compile_blueprint). }
unit TestToolBlueprintEditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolBlueprintEditor = class(TCastleTestCase)
  published
    procedure TestConstructionScriptForLoopProceduralSpawningAndSpinTickAndCleanJsonRoundtrip;
    procedure TestSlidingDoorTimelineFlipFlopGateLatentDelayBreakpointsAndInfiniteLoopGuard;
    procedure TestBlueprintPascalNativizationUnified101StudioHubAnd24thMcpCompileBlueprintTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleBlueprint, ToolBlueprintEditor, ToolStudioHub, ToolMcpServer;

procedure TTestToolBlueprintEditor.TestConstructionScriptForLoopProceduralSpawningAndSpinTickAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Bp, LoadedBp: TCastleBlueprint;
  JsonStr: String;
  VarVal: TBlueprintValue;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Bp := TBlueprintEditorHelper.SpawnBlueprintPresetInDesign(
      VP, Root, bppPillarRowConstructionAndSpinPickup, Vector3(2, 0, -3));
    AssertTrue(Bp <> nil);
    AssertTrue(Bp.CompileStatus = bcsUpToDate);
    AssertEquals(4, Bp.ConstructionSpawnCount);

    { Live Construction Script rebuild when PillarCount changes 4 -> 7 }
    AssertTrue(Bp.SetVariableInt('PillarCount', 7));
    AssertTrue(Bp.RunConstructionScript);
    AssertEquals(7, Bp.ConstructionSpawnCount);

    { EventGraph BeginPlay + Tick rotation (90 deg/s * 1.0s = 90 deg) }
    AssertTrue(Bp.ExecuteBeginPlay);
    AssertEquals(1, Bp.PrintLog.Count);
    AssertTrue(Pos('BeginPlay Ready', Bp.PrintLog[0]) > 0);

    AssertTrue(Bp.StepBlueprintTick(0.5));
    AssertTrue(Bp.StepBlueprintTick(0.5));
    AssertSameValue(90.0, Bp.YawDegreesAccum, 0.01);

    { Clean JSON roundtrip: csTransient construction children are not duplicated }
    JsonStr := ComponentToString(Bp);
    AssertTrue('csTransient BP_Box_1 must not leak into serialized JSON',
      Pos('BP_Box_1', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedBp := StringToComponent(JsonStr, LoadOwner) as TCastleBlueprint;
      AssertTrue(LoadedBp <> nil);
      AssertTrue(LoadedBp.GetVariableValue('PillarCount', VarVal));
      AssertEquals(7, VarVal.IntVal);
      AssertEquals(7, LoadedBp.ConstructionSpawnCount);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolBlueprintEditor.TestSlidingDoorTimelineFlipFlopGateLatentDelayBreakpointsAndInfiniteLoopGuard;
var
  Root: TComponent;
  VP: TCastleViewport;
  DoorBp, ArmBp, LoopBp, BadBp: TCastleBlueprint;
  ArmedVal: TBlueprintValue;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    { 1. Sliding Door: Overlap #1 -> FlipFlop A -> Timeline 0..1s -> Y moves 0 -> 1.5 -> 3.0m }
    DoorBp := TBlueprintEditorHelper.SpawnBlueprintPresetInDesign(
      VP, Root, bppSlidingDoorTimelineAndGate, Vector3(0, 0, 0));
    AssertTrue(DoorBp.ExecuteActorBeginOverlap('PlayerHero'));
    AssertTrue(DoorBp.StepBlueprintTick(0.5));
    AssertSameValue(1.5, DoorBp.Translation.Y, 0.02);
    AssertTrue(DoorBp.StepBlueprintTick(0.5));
    AssertSameValue(3.0, DoorBp.Translation.Y, 0.02);
    AssertTrue(DoorBp.PrintLog.Count >= 1);

    { Overlap #2 -> FlipFlop B -> ReverseFromEnd -> Y returns 3.0 -> 0.0m }
    AssertTrue(DoorBp.ExecuteActorBeginOverlap('PlayerHero'));
    AssertTrue(DoorBp.StepBlueprintTick(1.0));
    AssertSameValue(0.0, DoorBp.Translation.Y, 0.02);

    { 2. Latent Delay + Node Breakpoint Pause & Resume }
    ArmBp := TBlueprintEditorHelper.SpawnBlueprintPresetInDesign(
      VP, Root, bppPatrolBranchAndLatentDelay, Vector3(4, 0, 0));
    AssertTrue(ArmBp.ToggleNodeBreakpoint('EG_SetArmed'));
    AssertTrue(ArmBp.ExecuteBeginPlay);
    AssertTrue(ArmBp.GetVariableValue('IsArmed', ArmedVal));
    AssertFalse(ArmedVal.BoolVal);

    { At t=0.25s (< 0.5s Delay), still waiting }
    AssertTrue(ArmBp.StepBlueprintTick(0.25));
    AssertFalse(ArmBp.IsPausedAtBreakpoint);

    { At t=0.50s, Delay completes and hits Breakpoint on EG_SetArmed! }
    AssertTrue(ArmBp.StepBlueprintTick(0.25));
    AssertTrue(ArmBp.IsPausedAtBreakpoint);
    AssertEquals('EG_SetArmed', ArmBp.PausedNodeId);
    AssertTrue(ArmBp.GetVariableValue('IsArmed', ArmedVal));
    AssertFalse('Variable must not mutate before ResumeFromBreakpoint', ArmedVal.BoolVal);

    { ResumeFromBreakpoint -> executes EG_SetArmed -> Branch(True) -> PrintString }
    AssertTrue(ArmBp.ResumeFromBreakpoint);
    AssertFalse(ArmBp.IsPausedAtBreakpoint);
    AssertTrue(ArmBp.GetVariableValue('IsArmed', ArmedVal));
    AssertTrue(ArmedVal.BoolVal);
    AssertEquals(1, ArmBp.PrintLog.Count);
    AssertEquals('Turret Armed After Delay', ArmBp.PrintLog[0]);

    { 3. Infinite-Loop Guard on cyclic Exec wire }
    LoopBp := TCastleBlueprint.Create(Root);
    LoopBp.ClearAllGraphs;
    LoopBp.MaxExecStepsPerCall := 64;
    LoopBp.AddOrUpdateNode(TCastleBlueprint.MakeDefaultNode('E0', bgkEventGraph, bnkEventBeginPlay, 20, 20));
    LoopBp.AddOrUpdateNode(TCastleBlueprint.MakeDefaultNode('S0', bgkEventGraph, bnkSequence, 180, 20));
    LoopBp.ConnectExec(bgkEventGraph, 'E0', 0, 'S0', 0);
    LoopBp.ConnectExec(bgkEventGraph, 'S0', 0, 'S0', 0);
    AssertTrue(LoopBp.CompileBlueprint);
    AssertFalse(LoopBp.ExecuteBeginPlay);
    AssertTrue(LoopBp.HaltedByInfiniteLoopGuard);

    { 4. Compiler catches undeclared variables & latent nodes inside Construction Script }
    BadBp := TCastleBlueprint.Create(Root);
    BadBp.ClearAllGraphs;
    BadBp.AddOrUpdateNode(TCastleBlueprint.MakeDefaultNode('BadVar', bgkEventGraph, bnkGetVariable, 20, 20, 'GhostVar'));
    BadBp.AddOrUpdateNode(TCastleBlueprint.MakeDefaultNode('BadDelay', bgkConstructionScript, bnkDelay, 20, 80));
    AssertFalse(BadBp.CompileBlueprint);
    AssertTrue(BadBp.CompileStatus = bcsError);
    AssertEquals(2, BadBp.CompileErrors.Count);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolBlueprintEditor.TestBlueprintPascalNativizationUnified101StudioHubAnd24thMcpCompileBlueprintTool;
var
  Root: TComponent;
  VP: TCastleViewport;
  Entry: TStudioCatalogEntry;
  Srv: TCastleMcpServer;
  ListResp, CallResp, InnerText, PasCode: String;
  OuterJson, InnerJson: TJSONData;
  ToolsArr: TJSONArray;
  PayloadObj: TJSONObject;
begin
  { 1. Verify 101 UE Studios in Studio Hub (Phase 381 blueprint_editor) }
  AssertEquals(114, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('blueprint_editor', Entry));
  AssertEquals(381, Entry.PhaseNumber);

  { 2. Verify 24th MCP tool cge_compile_blueprint (spawn_preset, fire_event, generate_pascal) }
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
      AssertEquals(37, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_compile_blueprint","arguments":{"action":"spawn_preset","preset":"colonnade"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['blueprintCount']);
        AssertEquals(1, PayloadObj.Integers['compiledOkCount']);
        AssertEquals(4, PayloadObj.Integers['totalConstructionMeshes']);
        AssertEquals(114, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_compile_blueprint","arguments":{"action":"generate_pascal"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        PasCode := PayloadObj.Strings['pascalUnit'];
        AssertTrue(Pos('TBP_ColonnadeAndPickupBehavior = class(TCastleBehavior)', PasCode) > 0);
        AssertTrue(Pos('procedure RunConstructionScript;', PasCode) > 0);
        AssertTrue(Pos('for LoopIdx_CS_Loop :=', PasCode) > 0);
        AssertTrue(Pos('Parent.Rotation := Vector4', PasCode) > 0);
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
  RegisterTest(TTestToolBlueprintEditor);
end.
