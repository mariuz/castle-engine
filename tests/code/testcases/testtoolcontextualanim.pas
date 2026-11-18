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

{ Automated tests for Phase 358 Contextual Paired Animation & Docking Studio. }
unit TestToolContextualAnim;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolContextualAnim = class(TCastleTestCase)
  published
    procedure TestRearTakedownApproachConeWallClearanceRejectionAndExactDockWarp;
    procedure TestCoOpWallBoostVerticalLiftFrontParryAndTransientCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleContextualAnim, ToolContextualAnim;

procedure TTestToolContextualAnim.TestRearTakedownApproachConeWallClearanceRejectionAndExactDockWarp;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  CtxScene: TCastleContextualAnimScene;
  Instigator, Guard, Wall: TCastleTransform;
  FrontAttempt, WallBlockedAttempt: TContextualDockCheckResult;
  MidPose: TContextualSyncFramePose;
  I: Integer;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TContextualAnimHelper.SpawnContextualPairedDojo(Vp, RootOwner,
      CtxScene, Instigator, Guard, Wall));

    { 1. Standing in FRONT of guard (-Z) must fail Rear Stealth Takedown approach cone! }
    Instigator.Translation := Vector3(0.0, 0.0, -2.0);
    FrontAttempt := CtxScene.EvaluateDockingEligibility(Instigator, Guard, Vp.Items);
    AssertFalse('Front approach must NOT trigger a Rear Stealth Takedown', FrontAttempt.CanTrigger);
    AssertEquals('APPROACH_ANGLE_MISMATCH', FrontAttempt.BlockReason);

    { 2. Guard standing with back flush against Wall (Z = 6.0, half-thick 0.25 -> Z = 5.35)
         must reject Rear Takedown via WorldRay obstacle check so player never warps into wall! }
    Guard.Translation := Vector3(0.0, 0.0, 5.35);
    Instigator.Translation := Vector3(0.35, 0.0, 6.20);
    WallBlockedAttempt := CtxScene.EvaluateDockingEligibility(Instigator, Guard, Vp.Items);
    AssertFalse('Wall blocking dock slot must prevent warping Instigator into solid geometry',
      WallBlockedAttempt.CanTrigger);
    AssertTrue(WallBlockedAttempt.BlockedByWallCollision);
    AssertEquals('OBSTACLE_BLOCKS_DOCK_SLOT', WallBlockedAttempt.BlockReason);

    { 3. Clear open rear approach: warps Instigator cleanly to exact (0, 0, +1.05) dock slot! }
    Guard.Translation := Vector3(0.0, 0.0, 0.0);
    Instigator.Translation := Vector3(0.65, 0.0, 2.15);
    AssertTrue(CtxScene.BeginSynchronizedScene(Instigator, Guard, Vp.Items));

    for I := 1 to 10 do
      MidPose := CtxScene.StepSynchronizedScene(CtxScene.DurationSec * 0.05);

    AssertTrue('At NormTime = 0.50, WarpAlpha must equal 1.0 and contact sync window must be active',
      MidPose.InContactSyncWindow);
    AssertSameValue(1.0, MidPose.WarpAlpha, 0.001);
    AssertVectorEquals(Vector3(0.0, 0.0, 1.05), Instigator.Translation, 0.02);
    AssertVectorEquals(Vector3(0.0, 0.0, -1.0), Instigator.Direction, 0.02);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolContextualAnim.TestCoOpWallBoostVerticalLiftFrontParryAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  CtxScene, Restored: TCastleContextualAnimScene;
  Instigator, Partner, Wall: TCastleTransform;
  EndPose: TContextualSyncFramePose;
  I: Integer;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TContextualAnimHelper.SpawnContextualPairedDojo(Vp, RootOwner,
      CtxScene, Instigator, Partner, Wall));

    CtxScene.Preset := capCoOpWallBoostLift;
    Partner.Translation := Vector3(0.0, 0.0, 0.0);
    Instigator.Translation := Vector3(0.25, 0.0, 1.80);

    AssertTrue(CtxScene.BeginSynchronizedScene(Instigator, Partner, Vp.Items));
    for I := 1 to 20 do
      EndPose := CtxScene.StepSynchronizedScene(CtxScene.DurationSec * 0.05);

    AssertFalse('Scene must complete cleanly at NormalizedTime = 1.0', CtxScene.Active);
    AssertSameValue(2.10, EndPose.InstigatorWorldPos.Y, 0.02);
    AssertSameValue(2.10, Instigator.Translation.Y, 0.02);

    CtxScene.Preset := capFrontParryRiposteFinisher;
    ReportMd := TContextualAnimHelper.GenerateContextualAnimReport(CtxScene);
    AssertTrue(Pos('Front Parry & Riposte Finisher', ReportMd) > 0);

    JsonStr := ComponentToString(CtxScene);
    AssertEquals(0, Pos('TransientContextualAnimPreview', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleContextualAnimScene;
    AssertTrue(Restored.Preset = capFrontParryRiposteFinisher);
    AssertSameValue(3.4, Restored.MaxTriggerDistance, 0.01);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolContextualAnim);
end.
