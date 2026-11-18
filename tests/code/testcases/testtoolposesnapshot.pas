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

{ Automated tests for Phase 375 Skeletal Pose Snapshot & Dash Ghost Trail Studio. }
unit TestToolPoseSnapshot;

{$I castleconf.inc}

interface

uses Classes, SysUtils, Math, CastleTester;

type
  TTestToolPoseSnapshot = class(TCastleTestCase)
  published
    procedure TestFixedRingBufferEvictionMonotonicAlphaDecayAndExpiration;
    procedure TestPetrifiedStatueFreezeBlocksDashCapturesAndConfigJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastlePoseSnapshot, ToolPoseSnapshot;

procedure TTestToolPoseSnapshot.TestFixedRingBufferEvictionMonotonicAlphaDecayAndExpiration;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Trail: TCastlePoseSnapshotTrail;
  I: Integer;
  SlotBefore, SlotAfter: TPoseGhostEntry;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TPoseSnapshotHelper.SpawnDashGhostTrailDemo(Vp, RootOwner, Trail));

    Trail.ClearAllGhosts;
    Trail.MaxGhostCount := 4;
    Trail.GhostLifetimeSec := 1.0;
    Trail.InitialAlpha := 0.80;

    { 1. Capture 6 dash poses into a capacity-4 ring buffer -> active count stays capped at 4! }
    for I := 0 to 5 do
      AssertTrue(Trail.CaptureDashAfterimage(Vector3(I * 2.0, 0.0, 0.0), 0.0, 0.25) >= 0);

    AssertEquals(4, Trail.ActiveGhostCount);
    AssertEquals(6, Trail.TotalCapturedCount);

    { Slots 0 and 1 were overwritten in-place by captures #5 (x=8) and #6 (x=10) }
    AssertEquals(5, Trail.GetGhostSlot(0).SequenceNumber);
    AssertSameValue(8.0, Trail.GetGhostSlot(0).WorldPos.X, 1e-4);
    AssertEquals(6, Trail.GetGhostSlot(1).SequenceNumber);
    AssertSameValue(10.0, Trail.GetGhostSlot(1).WorldPos.X, 1e-4);

    { 2. Step 0.50s -> alpha decays linearly to 50% of InitialAlpha (0.40) }
    SlotBefore := Trail.GetGhostSlot(0);
    Trail.StepGhostDecay(0.50);
    SlotAfter := Trail.GetGhostSlot(0);
    AssertTrue(SlotAfter.CurrentAlpha < SlotBefore.CurrentAlpha);
    AssertSameValue(0.40, SlotAfter.CurrentAlpha, 1e-3);

    { 3. Step remaining +0.55s -> all 4 afterimages expire cleanly }
    Trail.StepGhostDecay(0.55);
    AssertEquals(0, Trail.ActiveGhostCount);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolPoseSnapshot.TestPetrifiedStatueFreezeBlocksDashCapturesAndConfigJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Trail, Restored: TCastlePoseSnapshotTrail;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Trail := TCastlePoseSnapshotTrail.Create(RootOwner);
    Trail.Name := 'HeroPoseTrail';
    Trail.Preset := ptpShadowStepViolet;

    { 1. Freeze character into petrified stone statue -> dash afterimage captures are rejected (-1) }
    Trail.FreezeStatuePose(Vector3(12.5, 0.0, -4.0), 0.75, 0.50);
    AssertTrue(Trail.IsStatueFrozen);
    AssertEquals(-1, Trail.CaptureDashAfterimage(Vector3(14.0, 0.0, -4.0), 0.75, 0.60));
    AssertEquals(0, Trail.ActiveGhostCount);

    ReportMd := TPoseSnapshotHelper.GeneratePoseSnapshotReport(Trail);
    AssertTrue(Pos('FROZEN_STONE_STATUE', ReportMd) > 0);

    { 2. Verify JSON roundtrip preserves frozen statue state & violet preset without csTransient child leak }
    JsonStr := ComponentToString(Trail);
    AssertEquals('csTransient preview must not serialize into JSON', 0, Pos('PoseSnapshotTransientRoot', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastlePoseSnapshotTrail;
    AssertTrue(Restored.IsStatueFrozen);
    AssertSameValue(12.5, Restored.FrozenWorldPos.X, 1e-3);
    AssertEquals(Ord(ptpShadowStepViolet), Ord(Restored.Preset));
    AssertEquals(8, Restored.MaxGhostCount);

    { 3. Unfreeze statue -> dash captures work again! }
    Restored.UnfreezeStatuePose;
    AssertFalse(Restored.IsStatueFrozen);
    AssertTrue(Restored.CaptureDashAfterimage(Vector3(15.0, 0.0, -4.0), 0.75, 0.70) >= 0);
    AssertEquals(1, Restored.ActiveGhostCount);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolPoseSnapshot);
end.
