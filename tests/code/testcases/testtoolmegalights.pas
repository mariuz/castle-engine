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

{ Automated tests for Phase 341 MegaLights Clustered 3D Tile Light-Grid Culler,
  Procedural Gobo Cookie Masks & Flicker Behaviors. }
unit TestToolMegaLights;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolMegaLights = class(TCastleTestCase)
  published
    procedure TestClustered3DLightGridBinningHotspotDetectionAndDistanceCulling;
    procedure TestFlickerProfilesGoboCookiePatternsAndCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleMegaLights, ToolMegaLights;

procedure TTestToolMegaLights.TestClustered3DLightGridBinningHotspotDetectionAndDistanceCulling;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Mgr: TCastleMegaLightsManager;
  Light1: TCastlePointLight;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TMegaLightsHelper.SpawnCyberpunkAlleyMegaLightsDemo(Vp, DesignOwner, Mgr));
    AssertTrue(Mgr <> nil);

    { 1. Near camera at origin: all 32 lights active, central alley tiles populated }
    AssertEquals(32, Mgr.TotalSceneLights);
    AssertEquals(32, Mgr.ActiveUnculledLights);
    AssertEquals(0, Mgr.CulledDistantLights);
    AssertTrue(Mgr.HotspotMaxLightsInAnyTile >= 2);
    { Far corner high-ceiling tile away from central X=±3.6m alley is empty }
    AssertEquals(0, Mgr.SampleTileLightCount(0, 7, 0));

    Light1 := DesignOwner.FindComponent('AlleyNeonLight_1') as TCastlePointLight;
    AssertTrue(Light1 <> nil);
    AssertTrue(Light1.Exists);

    { 2. Far camera at Z = 220m (> DistanceCullMeters 65m + Radius 8.5m): culls all 32 lights }
    Mgr.RebuildLightClusters(Vp.Items, Vector3(0, 5, 220));
    AssertEquals(32, Mgr.TotalSceneLights);
    AssertEquals(0, Mgr.ActiveUnculledLights);
    AssertEquals(32, Mgr.CulledDistantLights);
    AssertFalse(Light1.Exists);

    { 3. Returning camera to origin restores all 32 lights }
    Mgr.RebuildLightClusters(Vp.Items, Vector3(0, 2, 0));
    AssertEquals(32, Mgr.ActiveUnculledLights);
    AssertTrue(Light1.Exists);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolMegaLights.TestFlickerProfilesGoboCookiePatternsAndCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Mgr, RestoredMgr: TCastleMegaLightsManager;
  TestLight: TCastlePointLight;
  Fn, RestoredFn: TCastleLightFunctionBehavior;
  I0, I1: Single;
  Warnings: TStringList;
  Sum: TMegaLightsStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TMegaLightsHelper.SpawnCyberpunkAlleyMegaLightsDemo(Vp, DesignOwner, Mgr));

    { 1. Verify Torch flicker modulates parent TCastlePointLight.Intensity non-negatively }
    TestLight := TCastlePointLight.Create(DesignOwner);
    TestLight.Name := 'CampfireTestLight';
    Vp.Items.Add(TestLight);
    Fn := TCastleLightFunctionBehavior.Create(DesignOwner);
    Fn.Name := 'CampfireFn';
    Fn.BaseIntensity := 20.0;
    Fn.FlickerAmplitude := 0.45;
    Fn.FlickerProfile := lfpTorchCampfirePerlin;
    Fn.GoboPattern := lgpWindowVenetianBlinds;
    TestLight.AddBehavior(Fn);

    I0 := Fn.StepLightFunction(0.05);
    I1 := Fn.StepLightFunction(0.11);
    AssertTrue(I0 > 0.0);
    AssertTrue(I1 > 0.0);
    AssertTrue(Abs(I1 - I0) > 0.01);
    AssertSameValue(I1, TestLight.Intensity, 0.001);

    { 2. Venetian blinds gobo alternates bright slat vs dark bar }
    AssertSameValue(1.0, EvaluateGoboCookieMask(lgpWindowVenetianBlinds, 0.5, 0.03, 0.0), 0.01);
    AssertSameValue(0.08, EvaluateGoboCookieMask(lgpWindowVenetianBlinds, 0.5, 0.10, 0.0), 0.01);
    AssertTrue(EvaluateGoboCookieMask(lgpUnderwaterCaustics, 0.35, 0.42, 0.5) >= 0.05);

    Sum := TMegaLightsHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.ManagerCount);
    AssertEquals(33, Sum.LightFunctionCount);
    ReportMd := TMegaLightsHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('MegaLights Clustered Grid & Light-Function Report', ReportMd) > 0);

    { 3. JSON roundtrip on both Manager and LightFunctionBehavior }
    Mgr.DistanceCullMeters := 82.5;
    JsonStr := ComponentToString(Mgr);
    RestoredMgr := StringToComponent(JsonStr, RestoredOwner) as TCastleMegaLightsManager;
    AssertTrue(RestoredMgr <> nil);
    AssertSameValue(82.5, RestoredMgr.DistanceCullMeters, 0.01);

    JsonStr := ComponentToString(Fn);
    RestoredFn := StringToComponent(JsonStr, RestoredOwner) as TCastleLightFunctionBehavior;
    AssertTrue(RestoredFn <> nil);
    AssertSameValue(20.0, RestoredFn.BaseIntensity, 0.01);
    AssertTrue(RestoredFn.GoboPattern = lgpWindowVenetianBlinds);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolMegaLights);

end.
