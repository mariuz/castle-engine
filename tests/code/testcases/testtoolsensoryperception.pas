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

{ Automated tests for Phase 378 AI Sensory Perception Sight, Hearing & Scent Studio. }
unit TestToolSensoryPerception;

{$I castleconf.inc}

interface

uses Classes, SysUtils, Math, CastleTester;

type
  TTestToolSensoryPerception = class(TCastleTestCase)
  published
    procedure TestFovealVsPeripheralVisionConesAndWorldRaySolidWallOcclusion;
    procedure TestWallMuffledAcousticDecibelThresholdBloodhoundScentDecayAndJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleSensoryPerception, ToolSensoryPerception;

procedure TTestToolSensoryPerception.TestFovealVsPeripheralVisionConesAndWorldRaySolidWallOcclusion;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Sensor: TCastleSensoryPerception;
  SightWallBlocked, SightFovealClear, SightPeripheral, SightBehindBack: TSightEvaluation;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TSensoryPerceptionHelper.SpawnStealthCourtyardSensorDemo(Vp, RootOwner, Sensor));

    { CourtyardCoverWall sits at (0, 1.5, 8.0) with width 5.0m (-2.5..+2.5 X).
      1. Target directly behind wall at (0, 1.5, 13.0) must be blocked by WorldRay! }
    SightWallBlocked := Sensor.EvaluateSightTarget(Vp.Items, Vector3(0.0, 1.5, 13.0));
    AssertFalse(SightWallBlocked.Detected);
    AssertFalse(SightWallBlocked.LineOfSightClear);
    AssertEquals(Ord(svzOccludedByWall), Ord(SightWallBlocked.Zone));

    { 2. Target flanking past wall edge at (4.0, 1.65, 10.0) (~21.8 deg < 30 deg Fovea) -> Foveal Lock! }
    SightFovealClear := Sensor.EvaluateSightTarget(Vp.Items, Vector3(4.0, 1.65, 10.0));
    AssertTrue(SightFovealClear.Detected);
    AssertTrue(SightFovealClear.LineOfSightClear);
    AssertEquals(Ord(svzFovealLock), Ord(SightFovealClear.Zone));

    { 3. Target off to the side at (8.0, 1.65, 6.0) (~53.1 deg: > 30 deg Fovea, <= 75 deg Peripheral) -> Peripheral Glimpse! }
    SightPeripheral := Sensor.EvaluateSightTarget(Vp.Items, Vector3(8.0, 1.65, 6.0));
    AssertTrue(SightPeripheral.Detected);
    AssertEquals(Ord(svzPeripheralGlimpse), Ord(SightPeripheral.Zone));
    AssertTrue(SightFovealClear.AwarenessWeight > SightPeripheral.AwarenessWeight);

    { 4. Target behind guard's back at (0, 1.65, -5.0) (180 deg) -> Out of View! }
    SightBehindBack := Sensor.EvaluateSightTarget(Vp.Items, Vector3(0.0, 1.65, -5.0));
    AssertFalse(SightBehindBack.Detected);
    AssertEquals(Ord(svzOutOfView), Ord(SightBehindBack.Zone));
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolSensoryPerception.TestWallMuffledAcousticDecibelThresholdBloodhoundScentDecayAndJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Sensor, Restored: TCastleSensoryPerception;
  WhisperBehindWall, GunshotBehindWall: THearingEvaluation;
  BestScentPos: TVector3;
  BestScentTag, JsonStr: String;
  ScentScore1, ScentScore2: Single;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TSensoryPerceptionHelper.SpawnStealthCourtyardSensorDemo(Vp, RootOwner, Sensor));

    { 1. Footstep (62 dB) at 10m behind solid wall:
         62 - 20*log10(10) - 18(wall) = 62 - 20 - 18 = 24 dB < 35 dB threshold -> INAUDIBLE! }
    WhisperBehindWall := Sensor.EvaluateAcousticEvent(Vp.Items, Vector3(0.0, 1.65, 10.0), 62.0);
    AssertTrue(WhisperBehindWall.WallOccluded);
    AssertFalse(WhisperBehindWall.Audible);
    AssertSameValue(24.0, WhisperBehindWall.EffectiveDecibels, 0.25);

    { 2. Gunshot (95 dB) at 10m behind solid wall:
         95 - 20 - 18 = 57 dB >= 35 dB threshold -> AUDIBLE despite wall muffling! }
    GunshotBehindWall := Sensor.EvaluateAcousticEvent(Vp.Items, Vector3(0.0, 1.65, 10.0), 95.0);
    AssertTrue(GunshotBehindWall.WallOccluded);
    AssertTrue(GunshotBehindWall.Audible);
    AssertSameValue(57.0, GunshotBehindWall.EffectiveDecibels, 0.25);

    { 3. Bloodhound scent trail tracking & monotonic decay }
    Sensor.Preset := sppBloodhoundTracker;
    Sensor.DropScentBreadcrumb('FoxTrail', Vector3(4.0, 0.0, 3.0), 1.0);
    ScentScore1 := Sensor.SampleStrongestScent(BestScentPos, BestScentTag);
    AssertTrue(ScentScore1 > 0.5);
    AssertEquals('FoxTrail', BestScentTag);

    Sensor.StepSensoryDecay(12.5); // Half of 25s lifetime
    ScentScore2 := Sensor.SampleStrongestScent(BestScentPos, BestScentTag);
    AssertTrue((ScentScore2 > 0.0) and (ScentScore2 < ScentScore1));

    { 4. Verify csTransient-clean JSON roundtrip }
    JsonStr := ComponentToString(Sensor);
    AssertEquals(0, Pos('SensoryGizmoTransient', JsonStr));
    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleSensoryPerception;
    AssertEquals(Ord(sppBloodhoundTracker), Ord(Restored.Preset));
    AssertSameValue(18.0, Restored.ScentSniffRadiusMeters, 1e-3);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolSensoryPerception);
end.
