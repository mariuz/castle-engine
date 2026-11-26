{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 346 Deterministic Golden-Snapshot 64-Bit FNV-1a
  World-State Hasher, Cross-Run Drift Pinpointer, Unified 66-Studio Hub Catalog
  & 16th MCP Tool (cge_verify_determinism_hash). }
unit TestToolRegressionHarness;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolRegressionHarness = class(TCastleTestCase)
  published
    procedure TestFnv1aGoldenSnapshotDualRunBitExactDeterminismAndDriftPinpointing;
    procedure TestUnified66StudioHubHorizon8CatalogAnd16thMcpDeterminismTool;
  end;

implementation

uses
  fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform,
  CastleDataLayers, CastleSoundscape,
  ToolDataLayers, ToolJiggleBone, ToolSoundscape,
  ToolRegressionHarness, ToolStudioHub, ToolMcpServer;

procedure TTestToolRegressionHarness.TestFnv1aGoldenSnapshotDualRunBitExactDeterminismAndDriftPinpointing;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  DataMgr: TCastleDataLayerManager;
  JiggleCarrier, Stall, Wall: TCastleTransform;
  SndDir: TCastleSoundscapeDirector;
  DualAudit, DriftAudit: TDeterminismAuditResult;
  GoldenSnap, CandidateSnap, ReloadedSnap: TGoldenWorldSnapshot;
  JsonStr, MdStr: String;
begin
  DesignOwner := TComponent.Create(nil);
  GoldenSnap := nil;
  CandidateSnap := nil;
  ReloadedSnap := nil;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TDataLayersHelper.SpawnFortressScenarioDataLayersDemo(Vp, DesignOwner, DataMgr));
    AssertTrue(TJiggleBoneHelper.SpawnCharacterJiggleRigDemo(Vp, DesignOwner, JiggleCarrier));
    AssertTrue(TSoundscapeHelper.SpawnAcousticBiomeSoundscapeDemo(Vp, DesignOwner, SndDir));

    { 1. Dual-run 24-frame seeded replay achieves bit-exact 64-bit FNV-1a parity & restores world }
    DualAudit := TDeterminismRegressionHarness.VerifyDualRunDeterminism(
      Vp, DesignOwner, 24, 1.0 / 60.0, 20260346);
    AssertTrue(DualAudit.BitExactMatch);
    AssertEquals(16, Length(DualAudit.RunAHashHex));
    AssertEquals(DualAudit.RunAHashHex, DualAudit.RunBHashHex);
    AssertEquals(0, DualAudit.DriftedActorCount);
    AssertTrue(DualAudit.StateRestoredCleanly);

    { 2. Capture Golden baseline, inject 2 distinct actor drifts (+0.35m pos + Exists flip), diff }
    GoldenSnap := TDeterminismRegressionHarness.CaptureWorldSnapshot(Vp, DesignOwner, 'GoldenBase');
    Stall := DesignOwner.FindComponent('MerchantStall_West') as TCastleTransform;
    Wall := DesignOwner.FindComponent('FortressCurtainWall') as TCastleTransform;
    AssertTrue((Stall <> nil) and (Wall <> nil));

    Stall.Translation := Stall.Translation + Vector3(0.35, 0.0, 0.0);
    Wall.Exists := False;

    CandidateSnap := TDeterminismRegressionHarness.CaptureWorldSnapshot(Vp, DesignOwner, 'Drifted');
    DriftAudit := TDeterminismRegressionHarness.CompareSnapshots(GoldenSnap, CandidateSnap);
    AssertFalse(DriftAudit.BitExactMatch);
    AssertEquals(2, DriftAudit.DriftedActorCount);
    AssertSameValue(0.35, DriftAudit.MaxPositionDriftMeters, 0.002);

    { 3. Golden JSON persistence & Markdown audit report }
    JsonStr := GoldenSnap.ExportJson;
    ReloadedSnap := TGoldenWorldSnapshot.Create;
    AssertTrue(ReloadedSnap.LoadFromJson(JsonStr));
    AssertEquals(GoldenSnap.WorldHashHex, ReloadedSnap.WorldHashHex);
    AssertEquals(GoldenSnap.ActorCount, ReloadedSnap.ActorCount);

    MdStr := TDeterminismRegressionHarness.BuildMarkdownReport(DriftAudit, GoldenSnap);
    AssertTrue(Pos('DRIFT DETECTED', MdStr) > 0);
    AssertTrue(Pos('MerchantStall_West', MdStr) > 0);
  finally
    FreeAndNil(ReloadedSnap);
    FreeAndNil(CandidateSnap);
    FreeAndNil(GoldenSnap);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolRegressionHarness.TestUnified66StudioHubHorizon8CatalogAnd16thMcpDeterminismTool;
const
  Horizon8Ids: array[0..9] of String = (
    'state_tree', 'control_rig', 'spring_arm', 'erosion_studio',
    'mega_lights', 'gameplay_cue', 'data_layers', 'jiggle_bone',
    'soundscape_studio', 'regression_harness'
  );
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Carrier: TCastleTransform;
  SndDir: TCastleSoundscapeDirector;
  Entry: TStudioCatalogEntry;
  HealthReport: TStudioWorldHealthReport;
  Server: TCastleMcpServer;
  RespStr, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  I: Integer;
begin
  { 1. Verify all 96 Horizon 2-11 studios are registered in TStudioHubManager }
  AssertEquals(112, TStudioHubManager.StudioCount);
  for I := 0 to High(Horizon8Ids) do
    AssertTrue('Missing Horizon 8 studio id: ' + Horizon8Ids[I],
      TStudioHubManager.FindStudioById(Horizon8Ids[I], Entry));

  DesignOwner := TComponent.Create(nil);
  Server := TCastleMcpServer.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TJiggleBoneHelper.SpawnCharacterJiggleRigDemo(Vp, DesignOwner, Carrier));
    AssertTrue(TSoundscapeHelper.SpawnAcousticBiomeSoundscapeDemo(Vp, DesignOwner, SndDir));

    { 2. Verify AuditEntireDesign counts Horizon 8 runtime subsystems }
    HealthReport := TStudioHubManager.AuditEntireDesign(Vp, DesignOwner);
    try
      AssertEquals(100, HealthReport.ReadinessScore);
      AssertTrue(HealthReport.TotalModernSubsystems >= 4);
    finally
      FreeAndNil(HealthReport);
    end;

    { 3. Verify 16th MCP tool: cge_verify_determinism_hash }
    Server.AutonomyMode := mamReadOnly;
    Server.StandaloneDesignRoot := Vp;
    Server.StandaloneDesignOwner := DesignOwner;

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":46,"method":"tools/call","params":{"name":"cge_verify_determinism_hash","arguments":{"steps":15,"seed":20260346}}}');
    OuterJson := GetJSON(RespStr);
    try
      InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerJson := GetJSON(InnerText);
      try
        AssertTrue(TJSONObject(InnerJson).Booleans['bitExactMatch']);
        AssertTrue(TJSONObject(InnerJson).Booleans['stateRestoredCleanly']);
        AssertEquals(0, TJSONObject(InnerJson).Integers['driftedActorCount']);
        AssertEquals(16, Length(TJSONObject(InnerJson).Strings['worldHashHex']));
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;
  finally
    FreeAndNil(Server);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolRegressionHarness);

end.
