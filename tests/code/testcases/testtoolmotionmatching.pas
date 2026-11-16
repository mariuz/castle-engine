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

{ Automated unit tests for Phase 327 Motion Matching & Pose Search Locomotion
  Trajectory Database, Critically-Damped Inertialization & Stride Warping Studio
  (@link(CastleMotionMatching), @link(ToolMotionMatching)). }
unit TestToolMotionMatching;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolMotionMatching = class(TCastleTestCase)
  published
    procedure TestSpringTrajectoryPredictorInertializationHalfLifeAndStrideWarping;
    procedure TestPoseSearchSelectionSudden180PivotInertialSwitchContinuingBiasAndJson;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleMotionMatching, ToolMotionMatching;

procedure TTestToolMotionMatching.TestSpringTrajectoryPredictorInertializationHalfLifeAndStrideWarping;
var
  OffZero, OffSteady, OffAccel, LocalVec: TVector2;
  Decay0, DecayHalf, DecayLate: Single;
begin
  { 1. Exact spring-velocity trajectory predictor invariants }
  OffZero := PredictSpringTrajectoryXZ(Vector2(2.0, -3.0), Vector2(0.0, -5.0), 6.0, 0.0);
  AssertVectorEquals(TVector2.Zero, OffZero, 1e-5);

  { Constant velocity (Current == Desired) integrates to exact linear V * T }
  OffSteady := PredictSpringTrajectoryXZ(Vector2(1.5, -4.0), Vector2(1.5, -4.0), 6.0, 0.50);
  AssertVectorEquals(Vector2(0.75, -2.0), OffSteady, 1e-4);

  { Accelerating from rest toward (0, -6.0) over 1.0s lies strictly between 0 and -6.0 }
  OffAccel := PredictSpringTrajectoryXZ(TVector2.Zero, Vector2(0.0, -6.0), 6.0, 1.0);
  AssertTrue((OffAccel.Y < -4.5) and (OffAccel.Y > -6.0));

  { Character-local transform at Yaw=0 maps CGE Forward (0, -5) -> Local (Right=0, Forward=+5) }
  LocalVec := WorldVecXZToCharacterLocal(Vector2(2.0, -5.0), 0.0);
  AssertVectorEquals(Vector2(2.0, 5.0), LocalVec, 1e-4);

  { 2. Critically-damped Holden Inertialization exact half-life & monotonic non-overshoot }
  Decay0 := EvaluateInertializationDecay(1.0, 0.0, 0.12, 0.0);
  DecayHalf := EvaluateInertializationDecay(1.0, 0.0, 0.12, 0.12);
  DecayLate := EvaluateInertializationDecay(1.0, 0.0, 0.12, 0.60);
  AssertSameValue(1.0, Decay0, 1e-5);
  AssertSameValue(0.50, DecayHalf, 1e-4);
  AssertTrue((DecayLate > 0.0) and (DecayLate < 0.02));

  { 3. Analytical Stride Warping speed ratio & [MinScale..MaxScale] clamping }
  AssertSameValue(1.0, ComputeStrideWarpScale(0.0, 0.0, 0.65, 1.35), 1e-4);
  AssertSameValue(1.20, ComputeStrideWarpScale(2.16, 1.80, 0.65, 1.35), 1e-4);
  AssertSameValue(0.65, ComputeStrideWarpScale(0.50, 1.80, 0.65, 1.35), 1e-4);
  AssertSameValue(1.35, ComputeStrideWarpScale(4.00, 1.80, 0.65, 1.35), 1e-4);
end;

procedure TTestToolMotionMatching.TestPoseSearchSelectionSudden180PivotInertialSwitchContinuingBiasAndJson;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Hero: TCastleTransform;
  Db, RestoredDb: TCastlePoseSearchDatabase;
  Matcher: TCastleMotionMatchingBehavior;
  SwitchesBeforeSteady, I: Integer;
  SavedJson, Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    TMotionMatchingHelper.SpawnMotionMatchingArenaDemo(Vp, DesignOwner, Hero, Db, Matcher);
    AssertTrue(Hero <> nil);
    AssertTrue(Db <> nil);
    AssertTrue(Matcher <> nil);
    AssertTrue(Db.EntryCount >= 36);

    { 1. Zero desired velocity matches Idle }
    Matcher.DesiredWorldVelXZ := TVector2.Zero;
    Matcher.ForceImmediatePoseSearch;
    AssertEquals('Idle', Matcher.CurrentLocomotionTag);

    { 2. Steady 4.8 m/s forward (-Z) run matches RunForward }
    Matcher.DesiredWorldVelXZ := Vector2(0.0, -4.80);
    for I := 1 to 8 do
      Matcher.StepMotionMatching(0.05);
    AssertEquals('RunForward', Matcher.CurrentClipName);
    AssertTrue(Hero.Translation.Z < -1.0);

    { ContinuingPoseBias keeps steady-state locomotion in RunForward without chatter }
    SwitchesBeforeSteady := Matcher.PoseSwitchCount;
    for I := 1 to 6 do
      Matcher.StepMotionMatching(0.05);
    AssertEquals(SwitchesBeforeSteady, Matcher.PoseSwitchCount);

    { 3. Sudden 180-deg reversal (+Z while carrying high -Z forward momentum)
         selects PlantPivot180 and triggers Inertialization blend! }
    Matcher.DesiredWorldVelXZ := Vector2(0.0, 4.80);
    Matcher.ForceImmediatePoseSearch;
    AssertEquals('PlantPivot180', Matcher.CurrentClipName);
    AssertEquals('Pivot180', Matcher.CurrentLocomotionTag);
    AssertTrue(Matcher.PoseSwitchCount > SwitchesBeforeSteady);
    AssertTrue(Matcher.InertialBlendAlpha >= 0.50);

    { 4. Strafe-locked right movement selects StrafeRight }
    Matcher.ResetMotionState;
    Matcher.StrafeLockFacing := True;
    Matcher.DesiredFacingWorldXZ := Vector2(0.0, -1.0);
    Matcher.DesiredWorldVelXZ := Vector2(2.10, 0.0);
    for I := 1 to 4 do
      Matcher.StepMotionMatching(0.05);
    Matcher.ForceImmediatePoseSearch;
    AssertEquals('StrafeRight', Matcher.CurrentClipName);

    { 5. Serialization roundtrip of TCastlePoseSearchDatabase }
    Db.ApplyPreset(psdpSprintParkourAgile);
    Db.TrajectoryWeight := 2.25;
    SavedJson := ComponentToString(Db);
    RestoredOwner := TComponent.Create(nil);
    try
      RestoredDb := StringToComponent(SavedJson, RestoredOwner) as TCastlePoseSearchDatabase;
      AssertTrue(RestoredDb.Preset = psdpSprintParkourAgile);
      AssertSameValue(2.25, RestoredDb.TrajectoryWeight, 1e-4);
      AssertEquals(Db.EntryCount, RestoredDb.EntryCount);
    finally
      FreeAndNil(RestoredOwner);
    end;

    Md := TMotionMatchingHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('Motion Matching & Pose Search Telemetry Report', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolMotionMatching);
end.
