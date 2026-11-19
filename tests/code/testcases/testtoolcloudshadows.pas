{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 382 2.5D Atmospheric Cloud Shadow Scroller &
  Crepuscular Light-Shaft Studio. }
unit TestToolCloudShadows;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolCloudShadows = class(TCastleTestCase)
  published
    procedure TestZenithVsLowSunHorizontalShadowShiftCoverageMonotonicityAndAdvection;
    procedure TestHenyeyGreensteinForwardGodRayLobeVsBackscatterAndJsonRoundtrip;
  end;

implementation

uses
  Math, CastleVectors, CastleViewport, CastleComponentSerialize,
  CastleCloudShadows, ToolCloudShadows;

procedure TTestToolCloudShadows.TestZenithVsLowSunHorizontalShadowShiftCoverageMonotonicityAndAdvection;
var
  Owner: TComponent;
  Vp: TCastleViewport;
  Proj: TCastleCloudShadowProjector;
  ZenithS, LowSunS, BeforeWindS, AfterWindS: TCloudShadowSample;
  Frac0, FracMid, FracFull: Single;
begin
  Owner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    AssertTrue(TCloudShadowsHelper.SpawnValleyCloudShadowDemo(Vp, Owner, Proj));
    AssertTrue(Proj <> nil);

    { 1. Zenith sun (90 deg) projects straight down (0m offset) vs 45 deg East sun (+X = +Altitude) }
    Proj.CloudAltitudeMeters := 300.0;
    Proj.SunAzimuthDeg := 0.0;
    Proj.SunElevationDeg := 90.0;
    ZenithS := Proj.SampleGroundShadowAt(Vector3(10.0, 0.0, -20.0), Proj.EvaluateSunDirectionToSky);
    AssertSameValue(10.0, ZenithS.ProjectedCanopyXZ.X, 0.01);
    AssertSameValue(-20.0, ZenithS.ProjectedCanopyXZ.Y, 0.01);

    Proj.SunElevationDeg := 45.0;
    LowSunS := Proj.SampleGroundShadowAt(Vector3(10.0, 0.0, -20.0), Proj.EvaluateSunDirectionToSky);
    { At 45 deg elevation toward +X, cot(45 deg) = 1.0 -> CanopyX = 10 + 300 = 310m }
    AssertSameValue(310.0, LowSunS.ProjectedCanopyXZ.X, 0.25);
    AssertSameValue(-20.0, LowSunS.ProjectedCanopyXZ.Y, 0.05);

    { 2. Coverage monotonicity: 0.0 -> 0% shadow (1.0 transmittance), 0.5 -> partial, 1.0 -> 100% overcast }
    Proj.CloudCoverage01 := 0.0;
    Frac0 := Proj.ComputeCoverageFractionOverGrid(250.0, 16);
    AssertSameValue(0.0, Frac0, 0.0001);
    AssertSameValue(1.0, Proj.SampleGroundShadowAt(TVector3.Zero, Vector3(0, 1, 0)).DirectSunTransmittance01, 0.0001);

    Proj.CloudCoverage01 := 0.52;
    FracMid := Proj.ComputeCoverageFractionOverGrid(250.0, 16);
    AssertTrue((FracMid > 0.15) and (FracMid < 0.85));

    Proj.CloudCoverage01 := 1.0;
    FracFull := Proj.ComputeCoverageFractionOverGrid(250.0, 16);
    AssertSameValue(1.0, FracFull, 0.0001);

    { 3. Wind advection scrolls primary/detail UV offsets deterministically }
    Proj.ApplyPreset(cspSummerCumulusDrift);
    Proj.ResetWindScroll;
    BeforeWindS := Proj.SampleGroundShadowAt(Vector3(42.0, 0.0, 18.0), Proj.EvaluateSunDirectionToSky);
    Proj.StepWindAdvection(4.0);
    AssertTrue(Proj.ScrollPrimaryXZ.Length > 40.0);
    AfterWindS := Proj.SampleGroundShadowAt(Vector3(42.0, 0.0, 18.0), Proj.EvaluateSunDirectionToSky);
    AssertTrue(Abs(AfterWindS.CloudDensity01 - BeforeWindS.CloudDensity01) > 0.001);
  finally
    FreeAndNil(Owner);
  end;
end;

procedure TTestToolCloudShadows.TestHenyeyGreensteinForwardGodRayLobeVsBackscatterAndJsonRoundtrip;
var
  Owner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Proj, Restored: TCastleCloudShadowProjector;
  SunDir: TVector3;
  ForwardRayS, BackRayS: TCloudShadowSample;
  SavedJson, Cfg, Md: String;
begin
  Owner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    AssertTrue(TCloudShadowsHelper.SpawnValleyCloudShadowDemo(Vp, Owner, Proj));
    Proj.ApplyPreset(cspBrokenSunsetGodRays);
    Proj.CloudCoverage01 := 0.50;

    { Looking directly toward the solar disc produces > 10x stronger Mie god-ray shafts than looking 180 deg away }
    SunDir := Proj.EvaluateSunDirectionToSky;
    ForwardRayS := Proj.SampleGroundShadowAt(Vector3(25.0, 0.0, 25.0), SunDir);
    BackRayS := Proj.SampleGroundShadowAt(Vector3(25.0, 0.0, 25.0), -SunDir);
    AssertTrue(ForwardRayS.CrepuscularShaftIntensity > BackRayS.CrepuscularShaftIntensity * 10.0);

    Md := TCloudShadowsHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('2.5D Atmospheric Cloud Shadow & Crepuscular God-Ray Report', Md) > 0);

    { Verify csTransient canopy preview never leaks into serialized JSON + ConfigJson roundtrip }
    SavedJson := ComponentToString(Proj);
    AssertEquals(0, Pos('TransientCloudCanopyPreview', SavedJson));
    Cfg := Proj.ConfigJson;
    Restored := StringToComponent(SavedJson, RestoredOwner) as TCastleCloudShadowProjector;
    AssertTrue(Restored <> nil);
    Restored.ConfigJson := Cfg;
    AssertEquals(Ord(cspBrokenSunsetGodRays), Ord(Restored.Preset));
    AssertSameValue(0.84, Restored.MieAnisotropyG, 0.001);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(Owner);
  end;
end;

initialization
  RegisterTest(TTestToolCloudShadows);

end.
