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

{ Automated tests for Phase 359 Targeting System Preset Lock-On & Aim-Assist Studio. }
unit TestToolTargetingStudio;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolTargetingStudio = class(TCastleTestCase)
  published
    procedure TestMeleeBossLockWorldRayCoverRejectionAndRightStickFlickSwitching;
    procedure TestHealerCriticalLowestHpTriageAimMagnetismAndJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleTargetingSystem, ToolTargetingStudio;

procedure TTestToolTargetingStudio.TestMeleeBossLockWorldRayCoverRejectionAndRightStickFlickSwitching;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Player, Locked, FlickLeft, FlickRight: TCastleTransform;
  Targeting: TCastleTargetingBehavior;
  I: Integer;
  Ev: TTargetCandidateEval;
  FoundBlockedWallEnemy: Boolean;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TTargetingStudioHelper.SpawnTargetingCombatRange(Vp, RootOwner, Player, Targeting));
    AssertTrue(Targeting <> nil);

    { 1. Melee Hard Lock-On: selects EnemyWarlordBoss (center + Threat 10) while rejecting
         EnemyHiddenBehindWall via WorldRay LoS and Friendly allies via FactionTag! }
    Locked := Targeting.EvaluateTargetingStack(Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
    AssertTrue(Locked <> nil);
    AssertEquals('EnemyWarlordBoss', Locked.Name);
    AssertEquals(3, Targeting.ValidCandidateCount);

    FoundBlockedWallEnemy := False;
    for I := 0 to Targeting.CandidateCount - 1 do
    begin
      Ev := Targeting.GetCandidateEval(I);
      if Ev.TargetName = 'EnemyHiddenBehindWall' then
      begin
        FoundBlockedWallEnemy := True;
        AssertFalse(Ev.HasLineOfSight);
        AssertEquals('BLOCKED_LINE_OF_SIGHT', Ev.RejectedReason);
      end;
    end;
    AssertTrue(FoundBlockedWallEnemy);

    { 2. Flick Right-Stick LEFT (-1.0) -> switches from Boss to EnemyGruntLeft! }
    FlickLeft := Targeting.SwitchLockedTargetHorizontal(-1.0,
      Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
    AssertEquals('EnemyGruntLeft', FlickLeft.Name);

    { 3. Re-lock Boss and flick Right-Stick RIGHT (+1.0) -> switches to EnemySniperRight! }
    Targeting.EvaluateTargetingStack(Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
    FlickRight := Targeting.SwitchLockedTargetHorizontal(1.0,
      Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
    AssertEquals('EnemySniperRight', FlickRight.Name);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolTargetingStudio.TestHealerCriticalLowestHpTriageAimMagnetismAndJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Player, HealerPick, RestoredPlayer: TCastleTransform;
  Targeting, RestoredTargeting: TCastleTargetingBehavior;
  RawAim, MagAim, ToScout: TVector3;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TTargetingStudioHelper.SpawnTargetingCombatRange(Vp, RootOwner, Player, Targeting));

    { 1. Healer Friendly Lowest-HP preset: ignores Enemies and picks FriendlyScoutCriticalHp (18% HP) over Tank (95% HP)! }
    Targeting.Preset := tpkHealerFriendlyLowestHp;
    HealerPick := Targeting.EvaluateTargetingStack(Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
    AssertTrue(HealerPick <> nil);
    AssertEquals('FriendlyScoutCriticalHp', HealerPick.Name);

    { 2. Aim-assist magnetism pulls RawAim closer to LockedTarget's aim point }
    Targeting.MagnetismStrength := 0.50;
    RawAim := Vector3(0.0, 0.0, -1.0);
    MagAim := Targeting.ComputeMagnetizedAimDir(Vector3(0, 1.25, 0), RawAim);
    ToScout := (Vector3(2.2, 1.20, -9.0) - Vector3(0, 1.25, 0)).Normalize;
    AssertTrue('Magnetized aim must bend closer toward locked target than raw aim',
      TVector3.DotProduct(MagAim, ToScout) > TVector3.DotProduct(RawAim, ToScout) + 0.01);

    ReportMd := TTargetingStudioHelper.GenerateTargetingReport(Targeting);
    AssertTrue(Pos('Healer Friendly Triage', ReportMd) > 0);

    JsonStr := ComponentToString(Player);
    RestoredPlayer := StringToComponent(JsonStr, RestoredOwner) as TCastleTransform;
    RestoredTargeting := RestoredPlayer.FindBehavior(TCastleTargetingBehavior) as TCastleTargetingBehavior;
    AssertTrue(RestoredTargeting <> nil);
    AssertTrue(RestoredTargeting.Preset = tpkHealerFriendlyLowestHp);
    AssertSameValue(0.50, RestoredTargeting.MagnetismStrength, 0.01);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolTargetingStudio);
end.
