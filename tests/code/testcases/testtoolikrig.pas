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

{ Automated tests for Phase 304 Analytical Two-Bone IK, Foot Ground-Planting
  & Look-At Motion Rig Studio (@link(CastleIkRig), @link(ToolIkRig)). }
unit TestToolIkRig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  CastleTester, CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleViewport,
  CastleComponentSerialize, CastleIkRig, ToolIkRig;

type
  TTestToolIkRig = class(TCastleTestCase)
  published
    procedure TestTwoBoneIkLawOfCosinesPoleSoftReachAndGroundPlant;
    procedure TestLookAtConeClampingDampingAndJsonRoundtrip;
  end;

implementation

procedure TTestToolIkRig.TestTwoBoneIkLawOfCosinesPoleSoftReachAndGroundPlant;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Hip, Knee, Foot, FootTarget, KneePole: TCastleTransform;
  StepPlatform: TCastleBox;
  Ik: TCastleTwoBoneIkBehavior;
  HipW, KneeW, FootW: TVector3;
  DistUpper, DistLower, SoftSpan, HardSpan: Single;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    Ik := TIkRigHelper.CreateSampleLegIkRigInDesign(
      Vp, DesignOwner, Vector3(0.0, 0.0, 0.0),
      Hip, Knee, Foot, FootTarget, KneePole);
    AssertTrue(Ik <> nil);
    AssertSameValue(0.55, Ik.UpperBoneLength, 1e-4);
    AssertSameValue(0.55, Ik.LowerBoneLength, 1e-4);

    { 1. Reachable target: exact bone lengths L1 & L2 + exact effector arrival }
    Ik.SoftReachMargin := 0.0;
    FootTarget.Translation := Vector3(0.0, 0.25, 0.20);
    KneePole.Translation := Vector3(0.0, 0.60, 0.90);
    AssertTrue(Ik.SolveNow);

    HipW := GetIkHierarchyMatrix(Hip).MultPoint(TVector3.Zero);
    KneeW := GetIkHierarchyMatrix(Knee).MultPoint(TVector3.Zero);
    FootW := GetIkHierarchyMatrix(Foot).MultPoint(TVector3.Zero);

    DistUpper := PointsDistance(HipW, KneeW);
    DistLower := PointsDistance(KneeW, FootW);
    AssertSameValue(0.55, DistUpper, 2e-3);
    AssertSameValue(0.55, DistLower, 2e-3);
    AssertVectorEquals(Vector3(0.0, 0.25, 0.20), FootW, 2e-3);
    AssertTrue(KneeW.Z > 0.20);

    { 2. Flip PoleTransform to -Z -> Knee cleanly flips to negative Z plane }
    KneePole.Translation := Vector3(0.0, 0.60, -0.90);
    AssertTrue(Ik.SolveNow);
    KneeW := GetIkHierarchyMatrix(Knee).MultPoint(TVector3.Zero);
    FootW := GetIkHierarchyMatrix(Foot).MultPoint(TVector3.Zero);
    AssertTrue(KneeW.Z < -0.15);
    AssertSameValue(0.55, PointsDistance(HipW, KneeW), 2e-3);
    AssertSameValue(0.55, PointsDistance(KneeW, FootW), 2e-3);
    AssertVectorEquals(Vector3(0.0, 0.25, 0.20), FootW, 2e-3);

    { 3. SoftReachMargin hyperextension damping vs hard full extension }
    KneePole.Translation := Vector3(0.0, 0.60, 0.90);
    FootTarget.Translation := Vector3(0.0, 1.05, 1.08); { RawDist = 1.08 inside soft zone }
    Ik.SoftReachMargin := 0.22;
    AssertTrue(Ik.SolveNow);
    SoftSpan := PointsDistance(HipW, GetIkHierarchyMatrix(Foot).MultPoint(TVector3.Zero));

    Ik.SoftReachMargin := 0.0;
    AssertTrue(Ik.SolveNow);
    HardSpan := PointsDistance(HipW, GetIkHierarchyMatrix(Foot).MultPoint(TVector3.Zero));
    AssertTrue(SoftSpan < HardSpan - 0.02);
    AssertSameValue(1.08, HardSpan, 2e-3);

    { 4. Downward raycast ground foot planting onto stepped platform }
    StepPlatform := TCastleBox.Create(DesignOwner);
    StepPlatform.Name := 'SteppedPlatform';
    StepPlatform.Size := Vector3(2.0, 0.40, 2.0);
    StepPlatform.Translation := Vector3(0.0, 0.20, 0.20); { Top surface at Y = 0.40 }
    Vp.Items.Add(StepPlatform);

    FootTarget.Translation := Vector3(0.0, 0.0, 0.25);
    Ik.EnableGroundFootPlant := true;
    Ik.FootHeightOffset := 0.08;
    Ik.GroundRayCastHeight := 1.20;
    AssertTrue(Ik.SolveNow);

    FootW := GetIkHierarchyMatrix(Foot).MultPoint(TVector3.Zero);
    { Planted foot lifts from Y = 0.0 up to platform top 0.40 + offset 0.08 = 0.48 }
    AssertSameValue(0.48, FootW.Y, 1e-2);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolIkRig.TestLookAtConeClampingDampingAndJsonRoundtrip;
var
  DesignOwner, LoadedOwner: TComponent;
  Vp: TCastleViewport;
  TurretHead, AimTarget: TCastleTransform;
  Look: TCastleLookAtConstraintBehavior;
  HeadW, DirW, ClampedDirW, Step1DirW, Step5DirW: TVector3;
  YawDeg, PitchDeg: Single;
  SerializedJson, MdReport: String;
  LoadedRoot: TComponent;
  Sum: TIkRigSummary;
  I: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    Look := TIkRigHelper.CreateSampleLookAtTurretInDesign(
      Vp, DesignOwner, Vector3(0.0, 0.0, 0.0), TurretHead, AimTarget);
    AssertTrue(Look <> nil);
    Look.MaxYawDeg := 60.0;
    Look.MaxPitchDeg := 35.0;
    Look.DampingSpeed := 10.0;

    HeadW := GetIkHierarchyMatrix(TurretHead).MultPoint(TVector3.Zero);

    { 1. Target inside cone: aims directly toward AimTarget }
    AimTarget.Translation := HeadW + Vector3(0.8, 0.4, 2.5);
    AssertTrue(Look.ApplyLookAt(0.0));
    DirW := GetIkHierarchyMatrix(TurretHead).MultDirection(Vector3(0.0, 0.0, 1.0)).Normalize;
    AssertVectorEquals((AimTarget.Translation - HeadW).Normalize, DirW, 2e-3);

    { 2. Target far outside cone (90° yaw + steep upward pitch) -> clamped to ±60° / ±35° }
    AimTarget.Translation := HeadW + Vector3(5.0, 5.0, 0.0);
    AssertTrue(Look.ApplyLookAt(0.0));
    ClampedDirW := GetIkHierarchyMatrix(TurretHead).MultDirection(Vector3(0.0, 0.0, 1.0)).Normalize;
    YawDeg := RadToDeg(ArcTan2(ClampedDirW.X, ClampedDirW.Z));
    PitchDeg := RadToDeg(ArcSin(Clamped(ClampedDirW.Y, -1.0, 1.0)));
    AssertSameValue(60.0, YawDeg, 0.25);
    AssertSameValue(35.0, PitchDeg, 0.25);

    { 3. Exponential DampingSpeed smoothly interpolates across frame steps }
    AimTarget.Translation := HeadW + Vector3(0.0, 0.0, 3.0); { Straight ahead 0° }
    AssertTrue(Look.ApplyLookAt(0.05));
    Step1DirW := GetIkHierarchyMatrix(TurretHead).MultDirection(Vector3(0.0, 0.0, 1.0)).Normalize;
    AssertTrue(Step1DirW.Z > ClampedDirW.Z + 0.05);
    AssertTrue(Step1DirW.Z < 0.99); { Not instant }

    for I := 1 to 15 do
      Look.ApplyLookAt(0.08);
    Step5DirW := GetIkHierarchyMatrix(TurretHead).MultDirection(Vector3(0.0, 0.0, 1.0)).Normalize;
    AssertTrue(Step5DirW.Z > 0.995);

    { 4. JSON roundtrip + Markdown report }
    MdReport := TIkRigHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Look-At Aim Constraints', MdReport) > 0);
    AssertTrue(Pos('TurretHead', MdReport) > 0);

    SerializedJson := ComponentToString(Vp);
    LoadedOwner := TComponent.Create(nil);
    try
      LoadedRoot := StringToComponent(SerializedJson, LoadedOwner);
      Sum := TIkRigHelper.ScanIkRigs(LoadedRoot);
      AssertEquals(1, Length(Sum.LookAtRigs));
      AssertSameValue(60.0, Sum.LookAtRigs[0].MaxYawDeg, 1e-3);
      AssertSameValue(35.0, Sum.LookAtRigs[0].MaxPitchDeg, 1e-3);
      AssertTrue(Sum.LookAtRigs[0].LookTarget <> nil);
    finally
      FreeAndNil(LoadedOwner);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolIkRig);
end.
