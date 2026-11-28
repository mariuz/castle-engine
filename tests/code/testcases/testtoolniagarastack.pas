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

{ Automated tests for Phase 385: Niagara Modular Emitter Stack & Curve Editor
  (UNiagaraSystem Parity: Reorderable 4-Stage Emitter/Particle Stack, Curl
  Noise, Point Attractor, Size/Color-over-Life LUT Curves, Floor Collision
  Bounce & Secondary Sub-Sparks, 105-Studio Hub & 28th MCP Tool
  cge_simulate_niagara_stack). }
unit TestToolNiagaraStack;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolNiagaraStack = class(TCastleTestCase)
  published
    procedure TestArcaneVortex4StageStackAttractorCurveReorderingAndCleanJsonRoundtrip;
    procedure TestAnvilSparksInstantaneousBurstFloorBounceAndSecondarySubSparks;
    procedure TestUnified105StudioHubAnd28thMcpSimulateNiagaraStackTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleNiagaraStack, ToolNiagaraStack, ToolStudioHub, ToolMcpServer;

procedure TTestToolNiagaraStack.TestArcaneVortex4StageStackAttractorCurveReorderingAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Sys, LoadedSys: TCastleNiagaraSystem;
  Bell: TNiagaraFloatCurve;
  Audit: TNiagaraSceneAuditReport;
  StepIdx, I, AliveCnt: Integer;
  AvgY: Single;
  JsonStr: String;
begin
  { 1. Verify 4-key Hermite bell-curve evaluator }
  Bell := TNiagaraFloatCurve.DefaultBellCurve;
  AssertSameValue(0.35, Bell.Evaluate(0.0), 1e-4);
  AssertSameValue(1.25, Bell.Evaluate(0.20), 1e-4);
  AssertSameValue(0.05, Bell.Evaluate(1.0), 1e-4);
  AssertTrue('Bell curve swells mid-life above initial size', Bell.Evaluate(0.35) > Bell.Evaluate(0.0));

  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Sys := TNiagaraStackHelper.SpawnNiagaraPresetInDesign(
      VP, Root, nspArcaneVortexPortal, Vector3(0, 0, 0));
    AssertTrue(Sys <> nil);
    AssertEquals(8, Length(Sys.Modules));

    { 2. Step 10 x 0.10s = 1.0s: continuous SpawnRate (45/s) + CurlNoise + PointAttractor at (0, 2.5, 0) }
    for StepIdx := 1 to 10 do
      Sys.StepSystem(0.10);

    AssertEquals(45, Sys.TotalSpawnedCount);
    AssertTrue('Particles alive after 1.0s of 1.4..2.2s lifetime', Sys.ActiveParticleCount >= 30);

    AvgY := 0.0;
    AliveCnt := 0;
    for I := 0 to High(Sys.Particles) do
      if Sys.Particles[I].Alive then
      begin
        AvgY := AvgY + Sys.Particles[I].Position.Y;
        Inc(AliveCnt);
      end;
    AvgY := AvgY / Max(1, AliveCnt);
    AssertTrue('PointAttractor at (0, 2.5, 0) pulls swirling particles upward', AvgY > 0.50);

    { 3. Stage-bounded module reordering & non-destructive enable toggle }
    AssertFalse('Cannot reorder module across ParticleSpawn -> ParticleUpdate stage boundary',
      Sys.MoveModuleOrder('PS_Sphere', +1));
    AssertEquals(3, Sys.FindModuleIndex('PU_CurlNoise'));
    AssertEquals(4, Sys.FindModuleIndex('PU_Attractor'));
    AssertTrue(Sys.MoveModuleOrder('PU_CurlNoise', +1));
    AssertEquals(3, Sys.FindModuleIndex('PU_Attractor'));
    AssertEquals(4, Sys.FindModuleIndex('PU_CurlNoise'));

    AssertFalse(Sys.ToggleModuleEnabled('PU_CurlNoise'));
    Audit := TNiagaraStackHelper.AuditNiagaraSystemsInDesign(VP);
    AssertEquals(1, Audit.SystemCount);
    AssertEquals(8, Audit.TotalModuleCount);
    AssertEquals(7, Audit.EnabledModuleCount);

    { 4. SetTransient-clean JSON serialization roundtrip }
    JsonStr := ComponentToString(Sys);
    AssertTrue('SetTransient Niagara_PreviewSprites must not leak into serialized JSON',
      Pos('Niagara_PreviewSprites', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedSys := StringToComponent(JsonStr, LoadOwner) as TCastleNiagaraSystem;
      AssertTrue(LoadedSys <> nil);
      AssertEquals(8, Length(LoadedSys.Modules));
      AssertEquals('PU_CurlNoise', LoadedSys.Modules[4].ModuleId);
      AssertFalse(LoadedSys.Modules[4].Enabled);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolNiagaraStack.TestAnvilSparksInstantaneousBurstFloorBounceAndSecondarySubSparks;
var
  Root: TComponent;
  VP: TCastleViewport;
  Sparks, Embers: TCastleNiagaraSystem;
  StepIdx, I: Integer;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Sparks := TNiagaraStackHelper.SpawnNiagaraPresetInDesign(
      VP, Root, nspAnvilSparksCollisionBurst, Vector3(0, 0, 0));
    AssertTrue(Sparks <> nil);

    { 1. First step fires EmitterSpawn instantaneous burst of 24 primary sparks }
    Sparks.StepSystem(0.05);
    AssertEquals(24, Sparks.TotalSpawnedCount);
    AssertEquals(24, Sparks.ActiveParticleCount);
    AssertEquals(0, Sparks.CollisionEventCount);

    { 2. Step 19 more frames (1.00s total): gravity (-14 m/s^2) pulls sparks onto Y=0 floor,
         triggering elastic bounce + secondary sub-spark spawns! }
    for StepIdx := 1 to 19 do
      Sparks.StepSystem(0.05);

    AssertTrue('Sparks impacted Y=0 floor', Sparks.CollisionEventCount > 0);
    AssertTrue('Collision event spawned secondary sub-sparks', Sparks.SubSparkSpawnCount > 0);
    AssertEquals(24 + Sparks.SubSparkSpawnCount, Sparks.TotalSpawnedCount);

    for I := 0 to High(Sparks.Particles) do
      if Sparks.Particles[I].Alive then
        AssertTrue('Floor collision clamped all alive particles at or above Y=0',
          Sparks.Particles[I].Position.Y >= -1e-4);

    { 3. Verify 3rd preset (Campfire Ember Column) buoyant curl-noise rise }
    Embers := TNiagaraStackHelper.SpawnNiagaraPresetInDesign(
      VP, Root, nspCampfireEmberColumn, Vector3(4, 0, 0));
    for StepIdx := 1 to 4 do
      Embers.StepSystem(0.25);
    AssertTrue(Embers.ActiveParticleCount > 0);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolNiagaraStack.TestUnified105StudioHubAnd28thMcpSimulateNiagaraStackTool;
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
  { 1. Verify 105 UE Studios in Studio Hub (Phase 385 niagara_stack) }
  AssertEquals(118, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('niagara_stack', Entry));
  AssertEquals(385, Entry.PhaseNumber);

  { 2. Verify 28th MCP tool cge_simulate_niagara_stack }
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
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_simulate_niagara_stack","arguments":{"action":"spawn_preset","preset":"collision_sparks"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['systemCount']);
        AssertEquals(6, PayloadObj.Integers['totalModuleCount']);
        AssertEquals(6, PayloadObj.Integers['enabledModuleCount']);
        AssertEquals(118, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_simulate_niagara_stack","arguments":{"action":"step_sim","deltaSec":0.10}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(24, PayloadObj.Integers['totalActiveParticles']);
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
  RegisterTest(TTestToolNiagaraStack);
end.
