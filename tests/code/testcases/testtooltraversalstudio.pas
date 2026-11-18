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

{ Automated tests for Phase 349 Parkour Traversal Ledge/Vault/Mantle Scanner,
  Overhead Ceiling Headroom Rejection & Bezier Root-Motion Warp Anchors. }
unit TestToolTraversalStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolTraversalStudio = class(TCastleTestCase)
  published
    procedure TestFiveObstacleClassificationsThinVaultVsThickMantleAndCeilingBlock;
    procedure TestBezierRootMotionWarpTrajectoryExecutionAndCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleTraversalParkour, ToolTraversalStudio;

procedure TTestToolTraversalStudio.TestFiveObstacleClassificationsThinVaultVsThickMantleAndCeilingBlock;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Runner: TCastleTransform;
  Trav: TCastleTraversalBehavior;
  LowCeiling: TCastleBox;
  P: TTraversalProbeResult;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TTraversalStudioHelper.SpawnParkourGymCourseDemo(Vp, DesignOwner, Runner, Trav));
    AssertTrue(Trav <> nil);

    { 1. Lane -8.0m: 0.40m Curb -> takStepUp }
    P := Trav.ScanObstacleAhead(Vp.Items, Vector3(-8.0, 0.0, 0.0), Vector3(0, 0, -1));
    AssertTrue(P.Action = takStepUp);
    AssertSameValue(0.40, P.ObstacleHeightAboveFeet, 0.03);

    { 2. Lane -4.0m: 1.05m x 0.45m Thin Fence -> takThinVaultOver (lands on far floor Y=0!) }
    P := Trav.ScanObstacleAhead(Vp.Items, Vector3(-4.0, 0.0, 0.0), Vector3(0, 0, -1));
    AssertTrue(P.Action = takThinVaultOver);
    AssertTrue(P.HasFarSideLanding);
    AssertSameValue(0.0, P.LandingAnchorWorld.Y, 0.05);
    AssertTrue(P.LandingAnchorWorld.Z < -1.8);

    { 3. Lane 0.0m: 1.20m x 2.60m Thick Crate -> takLowMantleOnto (lands atop Y=1.20m!) }
    P := Trav.ScanObstacleAhead(Vp.Items, Vector3(0.0, 0.0, 0.0), Vector3(0, 0, -1));
    AssertTrue(P.Action = takLowMantleOnto);
    AssertFalse(P.HasFarSideLanding);
    AssertSameValue(1.20, P.LandingAnchorWorld.Y, 0.03);

    { 4. Lane +4.0m: 2.20m High Ledge -> takHighLedgeClimb }
    P := Trav.ScanObstacleAhead(Vp.Items, Vector3(+4.0, 0.0, 0.0), Vector3(0, 0, -1));
    AssertTrue(P.Action = takHighLedgeClimb);
    AssertSameValue(2.20, P.LandingAnchorWorld.Y, 0.03);

    { 5. Lane +8.0m: 3.80m Sheer Tower (> MaxHighClimbHeight 2.65m) -> takBlockedSheerWall }
    P := Trav.ScanObstacleAhead(Vp.Items, Vector3(+8.0, 0.0, 0.0), Vector3(0, 0, -1));
    AssertTrue(P.Action = takBlockedSheerWall);

    { 6. Place a low ceiling 0.90m above the 1.20m Crate (< CapsuleClearanceHeight 1.75m):
         must reject mantle with BlockedByLowCeiling = True! }
    LowCeiling := TCastleBox.Create(DesignOwner);
    LowCeiling.Name := 'LowOverhangCeiling';
    LowCeiling.Size := Vector3(3.0, 0.4, 3.0);
    LowCeiling.Translation := Vector3(0.0, 1.20 + 0.90 + 0.20, -2.0);
    Vp.Items.Add(LowCeiling);

    P := Trav.ScanObstacleAhead(Vp.Items, Vector3(0.0, 0.0, 0.0), Vector3(0, 0, -1));
    AssertTrue(P.BlockedByLowCeiling);
    AssertTrue(P.Action = takBlockedSheerWall);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolTraversalStudio.TestBezierRootMotionWarpTrajectoryExecutionAndCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Runner: TCastleTransform;
  Trav, RestoredTrav: TCastleTraversalBehavior;
  VaultProbe: TTraversalProbeResult;
  MidPt: TVector3;
  Warnings: TStringList;
  Sum: TTraversalStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TTraversalStudioHelper.SpawnParkourGymCourseDemo(Vp, DesignOwner, Runner, Trav));

    { 1. Vault Bezier arc clears top of 1.05m fence at Alpha=0.5 and lands cleanly at Alpha=1.0 }
    Runner.Translation := Vector3(-4.0, 0.0, 0.0);
    VaultProbe := Trav.ScanFromParent(Vp.Items, Vector3(0, 0, -1));
    AssertTrue(VaultProbe.Action = takThinVaultOver);

    MidPt := TCastleTraversalBehavior.EvaluateWarpTrajectory(Runner.Translation, VaultProbe, 0.5);
    AssertTrue(MidPt.Y > 0.70);

    AssertTrue(Trav.BeginTraversalWarp(Runner.Translation, VaultProbe));
    Trav.StepTraversalWarp(Trav.WarpDurationSec);
    AssertFalse(Trav.IsWarping);
    AssertSameValue(0.0, PointsDistance(VaultProbe.LandingAnchorWorld, Runner.Translation), 0.002);

    Sum := TTraversalStudioHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.ScannerCount);
    ReportMd := TTraversalStudioHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Parkour Traversal & Root-Motion Warp Report', ReportMd) > 0);

    { 2. JSON roundtrip }
    Trav.MaxVaultThickness := 1.15;
    JsonStr := ComponentToString(Trav);
    RestoredTrav := StringToComponent(JsonStr, RestoredOwner) as TCastleTraversalBehavior;
    AssertTrue(RestoredTrav <> nil);
    AssertSameValue(1.15, RestoredTrav.MaxVaultThickness, 0.01);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolTraversalStudio);

end.
