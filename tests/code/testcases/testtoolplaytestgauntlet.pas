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

{ Automated unit tests for Phase 326 Gauntlet-Style Automated Playtest Bot
  Runner, Deterministic World-State Restoration, JUnit XML CI Export & 46-Studio
  MCP Integration (@link(ToolPlaytestGauntlet), @link(ToolStudioHub),
  @link(ToolMcpServer)). }
unit TestToolPlaytestGauntlet;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolPlaytestGauntlet = class(TCastleTestCase)
  published
    procedure TestGauntletMultiSystemSmokeRunWorldStateRestoreAndJUnitXmlExport;
    procedure TestGauntletKillZFallthroughDetectionAndMcp46StudioTools;
  end;

implementation

uses
  FpJson, JsonParser,
  CastleVectors, CastleTransform, CastleViewport,
  ToolPlaytestGauntlet, ToolMcpServer;

procedure TTestToolPlaytestGauntlet.TestGauntletMultiSystemSmokeRunWorldStateRestoreAndJUnitXmlExport;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Car, Hero: TCastleTransform;
  CarPosBefore, HeroPosBefore: TVector3;
  Cfg: TPlaytestGauntletConfig;
  Report: TPlaytestGauntletReport;
  XmlStr, MdStr: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'ViewportGauntlet';

    { Spawn the full multi-system Horizon 6 smoke-test sandbox }
    TPlaytestGauntletRunner.SpawnMultiSystemSmokeSandbox(Vp, DesignOwner);

    Car := DesignOwner.FindComponent('GauntletRallyCar') as TCastleTransform;
    Hero := DesignOwner.FindComponent('HeroCombatActor1') as TCastleTransform;
    AssertTrue(Car <> nil);
    AssertTrue(Hero <> nil);
    CarPosBefore := Car.Translation;
    HeroPosBefore := Hero.Translation;

    Cfg := TPlaytestGauntletConfig.MakeDefault;
    Cfg.TotalDurationSec := 2.0;
    Cfg.StepDtSec := 0.05;
    Cfg.RestoreDesignAfterRun := True;

    Report := TPlaytestGauntletRunner.RunSmokeTest(Vp, DesignOwner, Cfg);
    try
      AssertTrue(Report.AllPassed);
      AssertEquals(0, Report.FailedAssertionsCount);
      AssertEquals(6, Report.PassedAssertionsCount);
      AssertEquals(40, Report.TotalStepsExecuted);
      AssertTrue(Report.PeakVehicleSpeedKmh > 15.0);
      AssertTrue(Report.PeakDisplacementMeters > 1.0);
      AssertEquals(100, Report.WorldReadinessScore);
      AssertTrue(Report.StateRestoredCleanly);

      { Verify non-destructive restoration back to exact pre-run coordinates }
      AssertVectorEquals(CarPosBefore, Car.Translation, 0.001);
      AssertVectorEquals(HeroPosBefore, Hero.Translation, 0.001);

      { Verify valid JUnit XML & Markdown CI reports }
      XmlStr := TPlaytestGauntletRunner.BuildJUnitXmlReport(Report);
      AssertTrue(Pos('<?xml version="1.0"', XmlStr) > 0);
      AssertTrue(Pos('failures="0"', XmlStr) > 0);
      AssertTrue(Pos('KillZFloorFallthroughGuard', XmlStr) > 0);

      MdStr := TPlaytestGauntletRunner.BuildMarkdownReport(Report);
      AssertTrue(Pos('PASSED (0 Failures)', MdStr) > 0);
    finally
      FreeAndNil(Report);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolPlaytestGauntlet.TestGauntletKillZFallthroughDetectionAndMcp46StudioTools;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Cfg: TPlaytestGauntletConfig;
  Report: TPlaytestGauntletReport;
  XmlStr, RespStr, InnerText: String;
  Server: TCastleMcpServer;
  OuterJson, InnerJson: TJSONData;
begin
  DesignOwner := TComponent.Create(nil);
  Server := TCastleMcpServer.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'ViewportTrap';

    { 1. Spawn an ungrounded vehicle above KillZ = -2.0m with no floor collider }
    TPlaytestGauntletRunner.SpawnKillZTrapActor(Vp, DesignOwner, Vector3(0.0, 1.0, 0.0));

    Cfg := TPlaytestGauntletConfig.MakeDefault;
    Cfg.TotalDurationSec := 1.5;
    Cfg.StepDtSec := 0.05;
    Cfg.KillZMinY := -2.0;
    Cfg.EnforceFrameBudget := False;

    Report := TPlaytestGauntletRunner.RunSmokeTest(Vp, DesignOwner, Cfg);
    try
      AssertFalse(Report.AllPassed);
      AssertTrue(Report.FailedAssertionsCount >= 1);
      AssertTrue(Report.LowestObservedY < -2.0);

      XmlStr := TPlaytestGauntletRunner.BuildJUnitXmlReport(Report);
      AssertTrue(Pos('<failure message=', XmlStr) > 0);
      AssertTrue(Pos('Kill-Z threshold', XmlStr) > 0);
    finally
      FreeAndNil(Report);
    end;

    { 2. Verify TCastleMcpServer cge_list_studios (46 studios) & cge_audit_world_readiness }
    Server.AutonomyMode := mamReadOnly;
    Server.StandaloneDesignRoot := Vp;
    Server.StandaloneDesignOwner := DesignOwner;

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"cge_list_studios","arguments":{"query":"ackermann"}}}');
    OuterJson := GetJSON(RespStr);
    try
      InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerJson := GetJSON(InnerText);
      try
        AssertEquals(96, TJSONObject(InnerJson).Integers['totalCatalogCount']);
        AssertEquals(1, TJSONObject(InnerJson).Integers['matchedCount']);
        AssertEquals('vehicle_studio',
          TJSONObject(InnerJson).Arrays['studios'].Objects[0].Strings['studioId']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"cge_audit_world_readiness","arguments":{}}}');
    OuterJson := GetJSON(RespStr);
    try
      InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerJson := GetJSON(InnerText);
      try
        AssertEquals(100, TJSONObject(InnerJson).Integers['readinessScore']);
        AssertEquals(0, TJSONObject(InnerJson).Integers['issuesCount']);
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
  RegisterTest(TTestToolPlaytestGauntlet);
end.
