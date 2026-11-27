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

{ Automated tests for Phase 388: Physics Asset Editor (PhAT / UPhysicsAsset
  Parity: Analytic Capsule/Sphere/Box Mass Fitting, Kinematic Root Pinning,
  Elliptical Swing1/Swing2 Joint Cone Clamping under Heavy Poke Impulses,
  Symmetric Bone-Pair Collision Disable Matrix, 108-Studio Hub & 31st MCP Tool
  cge_simulate_physics_asset). }
unit TestToolPhysicsAsset;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolPhysicsAsset = class(TCastleTestCase)
  published
    procedure TestAnalyticBodyMassKinematicPinSwingConeClampingAndCleanJsonRoundtrip;
    procedure TestSymmetricBonePairCollisionDisableMatrixAndFullRagdollFloorDrop;
    procedure TestUnified108StudioHubAnd31stMcpSimulatePhysicsAssetTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastlePhysicsAsset, ToolPhysicsAsset, ToolStudioHub, ToolMcpServer;

procedure TTestToolPhysicsAsset.TestAnalyticBodyMassKinematicPinSwingConeClampingAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  PA, LoadedPA: TCastlePhysicsAsset;
  SphereVol, CapsVol, BoxVol: Single;
  StepIdx, HeadIdx, TorsoIdx: Integer;
  JsonStr: String;
begin
  { 1. Verify exact analytic Sphere, Capsule, and Box volume & mass formulas }
  SphereVol := TCastlePhysicsAsset.ComputeBodyVolumeM3(pskSphere, 0.10, 0.0, TVector3.Zero);
  AssertSameValue((4.0 / 3.0) * Pi * 0.001, SphereVol, 1e-6);
  CapsVol := TCastlePhysicsAsset.ComputeBodyVolumeM3(pskCapsule, 0.10, 0.30, TVector3.Zero);
  AssertSameValue(Pi * 0.01 * 0.30 + SphereVol, CapsVol, 1e-6);
  BoxVol := TCastlePhysicsAsset.ComputeBodyVolumeM3(pskBox, 0.10, 0.0, Vector3(0.20, 0.30, 0.40));
  AssertSameValue(0.024, BoxVol, 1e-6);

  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    PA := TPhysicsAssetHelper.SpawnPhysicsAssetPresetInDesign(
      VP, Root, papKinematicPinnedUpperBodyTest, Vector3(0, 0, 0));
    AssertTrue(PA <> nil);
    AssertEquals(11, Length(PA.Bodies));
    AssertEquals(10, Length(PA.Constraints));
    AssertEquals(10, PA.DisabledPairCount);

    TorsoIdx := PA.FindBodyIndex('SpineTorso');
    HeadIdx  := PA.FindBodyIndex('Head');
    AssertTrue((TorsoIdx >= 0) and (HeadIdx >= 0));

    { 2. Kinematic SpineTorso refuses poke impulse and remains pinned at Y=1.38m,
         while Head receives a massive +60 Ns lateral poke and is strictly clamped inside
         its 35/30 deg elliptical Swing1/Swing2 cone with < 0.05 deg violation! }
    AssertFalse('Kinematic body ignores poke impulse',
      PA.ApplyPokeImpulse('SpineTorso', Vector3(50, 0, 0)));
    AssertTrue('Simulated Head accepts poke impulse',
      PA.ApplyPokeImpulse('Head', Vector3(60.0, 0.0, 25.0)));

    for StepIdx := 1 to 12 do
      PA.StepSimulation(0.02);

    AssertSameValue(1.38, PA.Bodies[TorsoIdx].Position.Y, 1e-4);
    AssertTrue('Head deflected laterally under poke', PA.Bodies[HeadIdx].Position.X > 0.05);
    AssertTrue('All 10 joint cones strictly enforced (< 0.05 deg violation)',
      PA.MaxConstraintConeViolationDeg < 0.05);
    AssertTrue('All 10 joint rod lengths preserved (< 1mm stretch)',
      PA.MaxConstraintStretchErrorMeters < 1e-3);

    { 3. SetTransient-clean JSON serialization roundtrip }
    JsonStr := ComponentToString(PA);
    AssertTrue('SetTransient PhAT_ColliderPreview must not leak into serialized JSON',
      Pos('PhAT_ColliderPreview', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedPA := StringToComponent(JsonStr, LoadOwner) as TCastlePhysicsAsset;
      AssertTrue(LoadedPA <> nil);
      AssertEquals(11, Length(LoadedPA.Bodies));
      AssertEquals(10, Length(LoadedPA.Constraints));
      AssertEquals(10, LoadedPA.DisabledPairCount);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolPhysicsAsset.TestSymmetricBonePairCollisionDisableMatrixAndFullRagdollFloorDrop;
var
  Root: TComponent;
  VP: TCastleViewport;
  Rag, Brute: TCastlePhysicsAsset;
  PelvisIdx, TorsoIdx, CalfLIdx, CalfRIdx, StepIdx: Integer;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Rag := TPhysicsAssetHelper.SpawnPhysicsAssetPresetInDesign(
      VP, Root, papHumanoidRagdoll11Bodies, Vector3(0, 0, 0));
    PelvisIdx := Rag.FindBodyIndex('Pelvis');
    TorsoIdx  := Rag.FindBodyIndex('SpineTorso');
    CalfLIdx  := Rag.FindBodyIndex('Calf_L');
    CalfRIdx  := Rag.FindBodyIndex('Calf_R');

    { 1. Adjacent Pelvis<->SpineTorso collision is disabled symmetrically,
         while non-adjacent Calf_L<->Calf_R is enabled by default and can be toggled }
    AssertFalse(Rag.IsPairCollisionEnabled(PelvisIdx, TorsoIdx));
    AssertFalse(Rag.IsPairCollisionEnabled(TorsoIdx, PelvisIdx));
    AssertTrue(Rag.IsPairCollisionEnabled(CalfLIdx, CalfRIdx));

    Rag.SetPairCollisionEnabled(CalfLIdx, CalfRIdx, False);
    AssertFalse(Rag.IsPairCollisionEnabled(CalfRIdx, CalfLIdx));
    AssertEquals(11, Rag.DisabledPairCount);
    Rag.SetPairCollisionEnabled(CalfRIdx, CalfLIdx, True);
    AssertTrue(Rag.IsPairCollisionEnabled(CalfLIdx, CalfRIdx));
    AssertEquals(10, Rag.DisabledPairCount);

    { 2. Full ragdoll drop under gravity settles cleanly above Y=0 floor without cone violations }
    for StepIdx := 1 to 25 do
      Rag.StepSimulation(0.03);
    AssertTrue('Pelvis dropped under gravity from 1.02m', Rag.Bodies[PelvisIdx].Position.Y < 0.95);
    AssertTrue('Floor keeps Calf_L above ground', Rag.Bodies[CalfLIdx].Position.Y >= Rag.Bodies[CalfLIdx].Radius - 1e-4);
    AssertTrue(Rag.MaxConstraintConeViolationDeg < 0.05);

    { 3. Heavy Armored Brute has significantly higher mass than standard humanoid }
    Brute := TPhysicsAssetHelper.SpawnPhysicsAssetPresetInDesign(
      VP, Root, papHeavyArmoredBruteRagdoll, Vector3(3, 0, 0));
    AssertTrue('Armored Brute mass > 2x standard humanoid mass',
      Brute.TotalMassKg > Rag.TotalMassKg * 2.0);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolPhysicsAsset.TestUnified108StudioHubAnd31stMcpSimulatePhysicsAssetTool;
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
  { 1. Verify 108 UE Studios in Studio Hub (Phase 388 physics_asset_phat) }
  AssertEquals(116, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('physics_asset_phat', Entry));
  AssertEquals(388, Entry.PhaseNumber);

  { 2. Verify 31st MCP tool cge_simulate_physics_asset }
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
      AssertEquals(39, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_simulate_physics_asset","arguments":{"action":"spawn_preset","preset":"pinned_test"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['assetCount']);
        AssertEquals(11, PayloadObj.Integers['totalBodies']);
        AssertEquals(10, PayloadObj.Integers['totalConstraints']);
        AssertEquals(10, PayloadObj.Integers['totalDisabledPairs']);
        AssertEquals(116, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_simulate_physics_asset","arguments":{"action":"poke_body","bodyName":"LowerArm_L","deltaSec":0.04}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['pokeImpulseCount']);
        AssertTrue(PayloadObj.Floats['maxConeViolationDeg'] < 0.05);
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
  RegisterTest(TTestToolPhysicsAsset);
end.
