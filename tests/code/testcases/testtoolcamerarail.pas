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

{ Automated tests for Phase 352 Camera Rig Rail & Co-Op Framing Studio. }
unit TestToolCameraRail;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolCameraRail = class(TCastleTestCase)
  published
    procedure TestClosestPointAutoDollyVelocityLookAheadAndInnerDeadzoneStillness;
    procedure TestCoOpHysteresisSplitMergeDynamicFovClosedOrbitalLoopAndJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleCameraRigRail, ToolCameraRail;

procedure TTestToolCameraRail.TestClosestPointAutoDollyVelocityLookAheadAndInnerDeadzoneStillness;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Rail: TCastleCameraRigRail;
  P1, P2: TCastleTransform;
  SnapRes, DeadzoneRes, SprintRes: TCameraRailResult;
  I: Integer;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TCameraRailHelper.SpawnCameraRailDemoArena(Vp, RootOwner, Rail, P1, P2));
    AssertTrue(Rail <> nil);

    Rail.CoOpEnabled := False;
    Rail.LookAheadTimeSec := 0.40;
    Rail.DeadzoneHalfWidthMeters := 0.85;
    Rail.DeadzoneHalfHeightMeters := 0.60;

    SnapRes := Rail.SnapRigImmediate(Vector3(0.0, 1.0, 0.0), TVector3.Zero, False);
    AssertSameValue(0.50, SnapRes.RailParamU, 0.03);
    AssertVectorEquals(Vector3(0.0, 1.0, 0.0), SnapRes.DeadzoneAimWorld, 0.01);

    { Small +0.35m lateral nudge inside +-0.85m deadzone must cause ZERO aim rotation swim }
    DeadzoneRes := Rail.EvaluateAndStepRig(Vector3(0.35, 1.0, 0.0), TVector3.Zero,
      TVector3.Zero, False, 0.10);
    AssertTrue('Inner deadzone must hold DeadzoneAimWorld rock-steady',
      PointsDistance(SnapRes.DeadzoneAimWorld, DeadzoneRes.DeadzoneAimWorld) < 0.001);

    { Sprint to X = +8.0m with +6.0 m/s velocity -> PredictedFocus leads to X = +10.40m }
    for I := 1 to 16 do
      SprintRes := Rail.EvaluateAndStepRig(Vector3(8.0, 1.0, 0.0), Vector3(6.0, 0.0, 0.0),
        TVector3.Zero, False, 1.0 / 30.0);

    AssertSameValue(10.40, SprintRes.PredictedFocusWorld.X, 0.02);
    AssertTrue('Closest-point auto-dolly must advance past u = 0.78', SprintRes.RailParamU > 0.78);
    AssertTrue('CameraWorldPos.X must dolly eastward past +7.5m', SprintRes.CameraWorldPos.X > 7.5);
    AssertTrue('DeadzoneAimWorld.X must track target outside deadzone', SprintRes.DeadzoneAimWorld.X > 8.5);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolCameraRail.TestCoOpHysteresisSplitMergeDynamicFovClosedOrbitalLoopAndJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Rail, RestoredRail: TCastleCameraRigRail;
  R4m, R12mPreSplit, R17mSplit, R12mHysteresisHold, R8mMerged: TCameraRailResult;
  JsonStr, ReportMd: String;
  ClosestOrbital: TVector3;
  OrbitalU: Single;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Rail := TCastleCameraRigRail.Create(RootOwner);
    Rail.Name := 'CoOpRail';
    Rail.CoOpEnabled := True;
    Rail.SplitDistanceMeters := 14.0;
    Rail.MergeDistanceMeters := 10.0;
    Rail.BaseFovDeg := 55.0;
    Rail.MaxCoOpFovDeg := 75.0;

    { 1. Close together (4m): single view, modest FOV }
    R4m := Rail.SnapRigImmediate(Vector3(-2.0, 1.0, 0.0), Vector3(2.0, 1.0, 0.0), True);
    AssertFalse(R4m.ShouldSplitScreen);
    AssertSameValue(0.0, R4m.PredictedFocusWorld.X, 0.02);
    AssertTrue((R4m.EffectiveFieldOfViewDeg > 59.0) and (R4m.EffectiveFieldOfViewDeg < 63.0));

    { 2. Medium separation (12m < Split 14m): still single view, wider FOV }
    R12mPreSplit := Rail.EvaluateAndStepRig(Vector3(-6.0, 1.0, 0.0), TVector3.Zero,
      Vector3(6.0, 1.0, 0.0), True, 0.10);
    AssertFalse(R12mPreSplit.ShouldSplitScreen);
    AssertTrue('Dynamic Co-Op FOV must widen past 70 deg before splitting',
      R12mPreSplit.EffectiveFieldOfViewDeg > 70.0);

    { 3. Wide separation (17m > Split 14m): triggers split-screen! }
    R17mSplit := Rail.EvaluateAndStepRig(Vector3(-8.5, 1.0, 0.0), TVector3.Zero,
      Vector3(8.5, 1.0, 0.0), True, 0.10);
    AssertTrue('17m > 14m must activate split-screen', R17mSplit.ShouldSplitScreen);
    AssertSameValue(55.0, R17mSplit.EffectiveFieldOfViewDeg, 0.01);

    { 4. Step back into hysteresis deadband (12m in [10m..14m]): MUST remain split! }
    R12mHysteresisHold := Rail.EvaluateAndStepRig(Vector3(-6.0, 1.0, 0.0), TVector3.Zero,
      Vector3(6.0, 1.0, 0.0), True, 0.10);
    AssertTrue('Hysteresis band [10m..14m] must prevent premature merge flicker',
      R12mHysteresisHold.ShouldSplitScreen);

    { 5. Step inside MergeDistanceMeters (8m < 10m): cleanly re-merges! }
    R8mMerged := Rail.EvaluateAndStepRig(Vector3(-4.0, 1.0, 0.0), TVector3.Zero,
      Vector3(4.0, 1.0, 0.0), True, 0.10);
    AssertFalse('8m < 10m must re-merge into single shared camera', R8mMerged.ShouldSplitScreen);

    { 6. Closed orbital ring + JSON roundtrip }
    Rail.Preset := crpBossArenaOrbitalRing;
    AssertTrue(Rail.ClosedLoop);
    OrbitalU := Rail.FindClosestRailParam(Vector3(0.0, 3.0, -20.0), ClosestOrbital);
    AssertSameValue(0.75, OrbitalU, 0.04);

    ReportMd := TCameraRailHelper.GenerateCameraRailReport(Rail);
    AssertTrue(Pos('Boss Arena Closed Orbital Ring', ReportMd) > 0);

    JsonStr := ComponentToString(Rail);
    AssertEquals(0, Pos('TransientCameraRailPreview', JsonStr));

    RestoredRail := StringToComponent(JsonStr, RestoredOwner) as TCastleCameraRigRail;
    AssertTrue(RestoredRail.ClosedLoop);
    AssertEquals(8, RestoredRail.ControlPointCount);
    AssertSameValue(14.0, RestoredRail.SplitDistanceMeters, 0.01);
    AssertEquals(1, RestoredRail.Count);
    AssertTrue(csTransient in RestoredRail[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolCameraRail);
end.
