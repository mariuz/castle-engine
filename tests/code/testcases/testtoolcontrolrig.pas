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

{ Automated tests for Phase 338 Control Rig Procedural Multi-Bone Chain,
  FABRIK Convergence, Progressive Twist Roll & Sine Tail Waves. }
unit TestToolControlRig;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolControlRig = class(TCastleTestCase)
  published
    procedure TestMultiBoneFabrikReachableConvergenceOutOfReachStretchAndExactSegmentLengths;
    procedure TestProgressiveTwistDistributionProceduralTailWaveAndCsTransientCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleControlRig, ToolControlRig;

procedure TTestToolControlRig.TestMultiBoneFabrikReachableConvergenceOutOfReachStretchAndExactSegmentLengths;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Host, Target: TCastleTransform;
  Rig: TCastleControlRigBehavior;
  I: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TControlRigHelper.SpawnRoboticArmControlRigDemo(
      Vp, DesignOwner, Host, Target, Rig));
    AssertTrue(Rig <> nil);
    AssertEquals(6, Rig.JointCount);
    AssertSameValue(4.00, Rig.TotalChainLength, 0.001);

    { 1. Reachable target (1.2, 2.0, 1.5 -> Dist = 2.77m < 4.00m):
         Root stays pinned at origin, tip converges < 0.005m, all 5 segments = 0.80m }
    Target.Translation := Vector3(1.2, 2.0, 1.5);
    Rig.SolveRig(0.0);
    AssertVectorEquals(Vector3(0, 0, 0), Rig.JointWorldPos(0), 0.0005);
    AssertVectorEquals(Vector3(1.2, 2.0, 1.5), Rig.JointWorldPos(5), 0.005);
    AssertTrue(Rig.MaxSegmentLengthDrift < 0.0005);
    for I := 0 to 4 do
      AssertSameValue(0.80, PointsDistance(Rig.JointWorldPos(I), Rig.JointWorldPos(I + 1)), 0.001);

    { 2. Out-of-reach target (0, 0, 8.0 -> Dist = 8.0m > 4.0m):
         Chain stretches straight along +Z to (0, 0, 4.0) with 0 segment drift }
    Target.Translation := Vector3(0.0, 0.0, 8.0);
    Rig.SolveRig(0.0);
    AssertVectorEquals(Vector3(0, 0, 0), Rig.JointWorldPos(0), 0.0005);
    AssertVectorEquals(Vector3(0, 0, 4.0), Rig.JointWorldPos(5), 0.001);
    AssertTrue(Rig.MaxSegmentLengthDrift < 0.0005);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolControlRig.TestProgressiveTwistDistributionProceduralTailWaveAndCsTransientCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Host, Target: TCastleTransform;
  Rig, RestoredRig: TCastleControlRigBehavior;
  Warnings: TStringList;
  Sum: TControlRigStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TControlRigHelper.SpawnRoboticArmControlRigDemo(
      Vp, DesignOwner, Host, Target, Rig));

    { 1. Progressive anti-candy-wrapper twist roll across 6 joints: 0..90 deg in 18 deg steps }
    Rig.EndEffectorTwistDeg := 90.0;
    AssertSameValue(0.0, Rig.GetJoint(0).TwistRollDeg, 0.01);
    AssertSameValue(18.0, Rig.GetJoint(1).TwistRollDeg, 0.01);
    AssertSameValue(36.0, Rig.GetJoint(2).TwistRollDeg, 0.01);
    AssertSameValue(54.0, Rig.GetJoint(3).TwistRollDeg, 0.01);
    AssertSameValue(72.0, Rig.GetJoint(4).TwistRollDeg, 0.01);
    AssertSameValue(90.0, Rig.GetJoint(5).TwistRollDeg, 0.01);

    { 2. Procedural 8-joint sinusoidal tail wave }
    Rig.Preset := crpProceduralTailWave;
    AssertEquals(8, Rig.JointCount);
    Rig.SolveRig(0.20);
    AssertTrue(Abs(Rig.JointWorldPos(7).X) > 0.02);
    AssertTrue(Rig.MaxSegmentLengthDrift < 0.0005);

    Sum := TControlRigHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.RigCount);
    AssertEquals(0, Sum.WarningsCount);
    ReportMd := TControlRigHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Control Rig Multi-Bone FABRIK & Twist Report', ReportMd) > 0);

    { 3. Verify csTransient visual rig mesh never leaks into Host or Rig JSON }
    Rig.EndEffectorTwistDeg := 60.0;
    JsonStr := ComponentToString(Host);
    AssertEquals(0, Pos('TransientControlRigMesh', JsonStr));

    JsonStr := ComponentToString(Rig);
    RestoredRig := StringToComponent(JsonStr, RestoredOwner) as TCastleControlRigBehavior;
    AssertTrue(RestoredRig <> nil);
    AssertTrue(RestoredRig.Preset = crpProceduralTailWave);
    AssertEquals(8, RestoredRig.JointCount);
    AssertSameValue(60.0, RestoredRig.EndEffectorTwistDeg, 0.01);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolControlRig);

end.
