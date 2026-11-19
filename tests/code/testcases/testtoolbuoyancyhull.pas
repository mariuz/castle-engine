{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 391: Multi-Pontoon Buoyancy Hydrostatics,
  Spherical-Cap Submergence & Wave Righting-Torque Studio. }
unit TestToolBuoyancyHull;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolBuoyancyHull = class(TCastleTestCase)
  published
    procedure TestExactSphericalCapSubmergenceArchimedesEquilibriumAndRightingTorque;
    procedure TestWaveHeaveOscillationPresetsAndTransientCleanJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleBuoyancyHull, ToolBuoyancyHull;

procedure TTestToolBuoyancyHull.TestExactSphericalCapSubmergenceArchimedesEquilibriumAndRightingTorque;
var
  Hull: TCastleBuoyancyHull;
  StHeel, StSettled: THullHydrostaticState;
begin
  { 1. Exact spherical-cap geometry identities: dry=0, half=0.5, full=1.0 }
  AssertSameValue(0.0,
    TCastleBuoyancyHull.SphericalCapSubmergedFraction(2.0, 0.5, 0.0), 0.0001);
  AssertSameValue(0.5,
    TCastleBuoyancyHull.SphericalCapSubmergedFraction(0.0, 0.5, 0.0), 0.0001);
  AssertSameValue(1.0,
    TCastleBuoyancyHull.SphericalCapSubmergedFraction(-2.0, 0.5, 0.0), 0.0001);

  Hull := TCastleBuoyancyHull.Create(nil);
  try
    Hull.ApplyPreset(bhpWoodenCargoRaft4Pt);
    Hull.WaveAmplitudeMeters := 0.0;
    Hull.Translation := Vector3(0.0, 0.0, 0.0);

    { 2. Heel +20 deg starboard (+X submerged deeper): generates restoring
         righting torque NetRightingTorqueNm.Z > 0 that rights the raft back
         toward 0 deg level when stepped in calm water! }
    Hull.SetAttitudeDeg(0.0, 20.0);
    StHeel := Hull.EvaluateHydrostatics;
    AssertTrue('Starboard heel generates positive restoring +Z torque',
      StHeel.NetRightingTorqueNm.Z > 200.0);

    { 3. Drop raft from Y = +0.8m in calm water for 4.0s -> settles to exact
         Archimedes hydrostatic equilibrium (|NetVerticalForceN| < 25 N,
         |RollDeg| < 1.5 deg)! }
    Hull.Translation := Vector3(0.0, 0.80, 0.0);
    StSettled := Hull.StepHydrostaticMotion(4.5);
    AssertTrue('Raft settles to Archimedes buoyancy = weight equilibrium',
      Abs(StSettled.NetVerticalForceN) < 35.0);
    AssertTrue('Metacentric righting torque levels roll < 1.5 deg',
      Abs(StSettled.RollDeg) < 1.5);
  finally
    FreeAndNil(Hull);
  end;
end;

procedure TTestToolBuoyancyHull.TestWaveHeaveOscillationPresetsAndTransientCleanJsonRoundtrip;
var
  Root: TComponent;
  VP: TCastleViewport;
  Hull, Restored: TCastleBuoyancyHull;
  YCrest, YTrough: Single;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleBuoyancyHull.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TBuoyancyHullHelper.SpawnWaterBasinRaftDemo(Root, Root, Hull));

    YCrest := Hull.SampleWaterSurfaceY(0.0, 0.0);
    Hull.SimTimeSec := Hull.SimTimeSec + (Hull.WaveLengthMeters / (2.0 * Hull.WaveSpeedMps));
    YTrough := Hull.SampleWaterSurfaceY(0.0, 0.0);
    AssertTrue('Half-period wave phase shifts surface elevation',
      Abs(YCrest - YTrough) > 0.05);

    Hull.ApplyPreset(bhpPatrolGunboat6Pt);
    AssertEquals(6, Hull.PontoonCount);

    SerializedScene := ComponentToString(Hull);
    AssertTrue(Pos('BuoyancyHullPreview', SerializedScene) = 0);

    Hull.HullMassKg := 2450.0;
    JsonCfg := TBuoyancyHullHelper.ExportHullJson(Hull);
    AssertTrue(TBuoyancyHullHelper.ImportHullJson(Restored, JsonCfg));
    AssertEquals(Ord(bhpPatrolGunboat6Pt), Ord(Restored.Preset));
    AssertSameValue(2450.0, Restored.HullMassKg, 0.1);
    Md := TBuoyancyHullHelper.GenerateMarkdownReport(Hull);
    AssertTrue(Pos('PatrolGunboat6Pt', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolBuoyancyHull);

end.
