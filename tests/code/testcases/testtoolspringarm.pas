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

{ Automated tests for Phase 339 Spring-Arm Camera Collision Whisker Probe,
  Instant Wall Pull-In, Grazing Corner Catch & Smooth Lagged Recovery. }
unit TestToolSpringArm;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolSpringArm = class(TCastleTestCase)
  published
    procedure TestWhiskerWallOcclusionInstantPullInAndSmoothExponentialRecovery;
    procedure TestGrazingEdgeWhiskerDetectionPositionLagAndCsTransientCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleSpringArm, ToolSpringArm;

procedure TTestToolSpringArm.TestWhiskerWallOcclusionInstantPullInAndSmoothExponentialRecovery;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Hero, Wall: TCastleTransform;
  SA: TCastleSpringArm;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TSpringArmHelper.SpawnThirdPersonSpringArmCorridorDemo(
      Vp, DesignOwner, Hero, Wall, SA));
    AssertTrue(SA <> nil);

    { 1. Wall at Z = 12.0m (> 4.50m): full 4.50m boom length, 0 blocked whiskers }
    AssertFalse(SA.IsOccluded);
    AssertEquals(0, SA.BlockedWhiskerCount);
    AssertSameValue(4.50, SA.CurrentArmLength, 0.001);
    AssertVectorEquals(Vector3(0.0, 1.55, 4.50), SA.SolvedCameraWorldPos, 0.01);

    { 2. Slide wall inward to Z = 2.00m: instant pull-in to 2.00 - ProbeRadius(0.25) = 1.75m! }
    Wall.Translation := Vector3(0.0, 0.0, 2.00);
    SA.StepSpringArm(0.016, Vp.Items);
    AssertTrue(SA.IsOccluded);
    AssertEquals(5, SA.BlockedWhiskerCount);
    AssertSameValue(1.75, SA.CurrentArmLength, 0.01);
    AssertTrue(SA.SolvedCameraWorldPos.Z < 1.99);

    { 3. Clear wall back to Z = 20.0m: asymmetric smooth ease-out (no instant pop on 0.10s!) }
    Wall.Translation := Vector3(0.0, 0.0, 20.0);
    SA.StepSpringArm(0.10, Vp.Items);
    AssertFalse(SA.IsOccluded);
    AssertTrue(SA.CurrentArmLength > 2.10);
    AssertTrue(SA.CurrentArmLength < 4.30);

    { 4. Step 2.5s -> full smooth recovery to TargetArmLength = 4.50m }
    SA.StepSpringArm(2.50, Vp.Items);
    AssertSameValue(4.50, SA.CurrentArmLength, 0.01);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolSpringArm.TestGrazingEdgeWhiskerDetectionPositionLagAndCsTransientCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Hero, Wall: TCastleTransform;
  CornerWall: TCastleScene;
  SA, RestoredSA: TCastleSpringArm;
  Warnings: TStringList;
  Sum: TSpringArmStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TSpringArmHelper.SpawnThirdPersonSpringArmCorridorDemo(
      Vp, DesignOwner, Hero, Wall, SA));

    { 1. Grazing corner wall spanning X in [0.12 .. 2.12] at Z = 2.50m:
         Center ray at X = 0.0 misses completely, while +X whisker at X = +0.25m catches it! }
    CornerWall := TSpringArmHelper.CreateColliderWallScene(
      DesignOwner, 'GrazingCornerPillar', 1.0, 4.0, Vector3(1.12, 0.0, 2.50));
    Vp.Items.Add(CornerWall);

    SA.StepSpringArm(0.016, Vp.Items);
    AssertTrue(SA.IsOccluded);
    AssertFalse(SA.GetWhisker(0).Blocked); { Center ray clear }
    AssertTrue(SA.GetWhisker(1).Blocked);  { +X right whisker caught corner! }
    AssertSameValue(2.25, SA.CurrentArmLength, 0.02);

    CornerWall.Exists := False;
    SA.SnapToTargetImmediately;

    { 2. Exponential camera position lag when Hero dashes +6.0m along X }
    SA.EnablePositionLag := True;
    SA.PositionLagSpeed := 8.0;
    Hero.Translation := Vector3(6.0, 0.0, 0.0);
    SA.StepSpringArm(0.05, Vp.Items);
    AssertTrue(SA.SolvedAnchorWorldPos.X > 1.0);
    AssertTrue(SA.SolvedAnchorWorldPos.X < 5.5);

    Sum := TSpringArmHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.SpringArmCount);
    AssertEquals(0, Sum.WarningsCount);
    ReportMd := TSpringArmHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Spring-Arm Camera Whisker & Occlusion Report', ReportMd) > 0);

    { 3. Verify csTransient debug whisker mesh never leaks into serialized JSON }
    SA.TargetArmLength := 5.25;
    SA.ShoulderOffsetX := 0.45;
    JsonStr := ComponentToString(SA);
    AssertEquals(0, Pos('TransientSpringArmMesh', JsonStr));

    RestoredSA := StringToComponent(JsonStr, RestoredOwner) as TCastleSpringArm;
    AssertTrue(RestoredSA <> nil);
    AssertSameValue(5.25, RestoredSA.TargetArmLength, 0.01);
    AssertSameValue(0.45, RestoredSA.ShoulderOffsetX, 0.01);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolSpringArm);

end.
