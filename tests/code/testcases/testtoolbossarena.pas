{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 412: Tactical Boss Telegraph & AoE Hazard Zone
  (Pizza-Cone, Safe-Eye Donut, Line Charge & Jumpable Shock-Ring) Studio. }
unit TestToolBossArena;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolBossArena = class(TCastleTestCase)
  published
    procedure TestOverlappingConeDonutSafeInnerEyeAndWorldRayPillarShelter;
    procedure TestJumpableExpandingShockwaveRingChargeLaneAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleBossArena, ToolBossArena;

procedure TTestToolBossArena.TestOverlappingConeDonutSafeInnerEyeAndWorldRayPillarShelter;
var
  Root: TComponent;
  VP: TCastleViewport;
  Dir: TCastleBossHazardDirector;
  EvalTripleHit, EvalRearSafeEye, EvalBehindPillar: TBossHazardEvalResult;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TBossArenaHelper.SpawnRaidBossOverlapArenaDemo(Root, Root, Dir));

    { 1. At (0, 0, +5.0) in front of the pillar: player stands inside ALL THREE
         telegraphs simultaneously (45-deg +Z Cone + 3.5..12m Donut + R=5m Shock-Ring)! }
    EvalTripleHit := Dir.EvaluatePlayerSafety(VP.Items, Vector3(0.0, 0.0, 5.0));
    AssertEquals(3, EvalTripleHit.ThreateningZoneCount);
    AssertSameValue(450.0 + 600.0 + 320.0, EvalTripleHit.PotentialDamageSum, 0.5);

    { 2. Tuck close behind boss at (0, 0, -2.0): outside frontal +Z cone, inside
         R < 3.5m safe donut eye, and inside R = 5.0m shock-ring -> 0 threats! }
    EvalRearSafeEye := Dir.EvaluatePlayerSafety(VP.Items, Vector3(0.0, 0.0, -2.0));
    AssertEquals(0, EvalRearSafeEye.ThreateningZoneCount);
    AssertTrue(EvalRearSafeEye.SavedByInnerDonutEye);
    AssertSameValue(0.0, EvalRearSafeEye.PotentialDamageSum, 0.01);

    { 3. Hide behind RaidLineOfSightPillar (Z = +6.0) at (0, 0, +13.0): outside 12m
         donut and R=5m ring, inside 14m DragonBreathPizzaCone, yet WorldRay hits
         RaidLineOfSightPillar -> SavedByPillarShelter = True and 0 damage! }
    EvalBehindPillar := Dir.EvaluatePlayerSafety(VP.Items, Vector3(0.0, 0.0, 13.0));
    AssertTrue('Stone raid pillar blocks frontal dragon breath cone via WorldRay',
      EvalBehindPillar.SavedByPillarShelter);
    AssertEquals(0, EvalBehindPillar.ThreateningZoneCount);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolBossArena.TestJumpableExpandingShockwaveRingChargeLaneAndJsonRoundtrip;
var
  Dir, Restored: TCastleBossHazardDirector;
  EvalGrounded, EvalAirborneJump, EvalLaneHit, EvalLaneDodge: TBossHazardEvalResult;
  SerializedScene, JsonCfg, Md: String;
begin
  Dir := TCastleBossHazardDirector.Create(nil);
  Restored := TCastleBossHazardDirector.Create(nil);
  try
    { 1. Expanding shockwave ring at R = 10m * (1.0s / 2.0s) = 5.0m:
         grounded player (Y = 0) gets hit; jumping player (Y = 1.35m > 0.90m) clears it! }
    Dir.SpawnJumpShockwaveRing('ShockRing', TVector3.Zero, 10.0, 0.80, 0.90, 2.0, 300.0);
    Dir.StepTelegraphs(1.0);

    EvalGrounded := Dir.EvaluatePlayerSafety(nil, Vector3(5.0, 0.0, 0.0));
    AssertEquals(1, EvalGrounded.ThreateningZoneCount);

    EvalAirborneJump := Dir.EvaluatePlayerSafety(nil, Vector3(5.0, 1.35, 0.0));
    AssertEquals(0, EvalAirborneJump.ThreateningZoneCount);
    AssertTrue('Jumping above 0.90m clears the expanding ground shockwave ring',
      EvalAirborneJump.SavedByJumpOverRing);

    { 2. Rotated linear bull-charge lane along (+1, 0, +1) }
    Dir.ClearTelegraphs;
    Dir.SpawnLinearChargeLane('MinotaurCharge', TVector3.Zero,
      Vector3(1.0, 0.0, 1.0), 12.0, 1.5, 1.5, 500.0);
    EvalLaneHit := Dir.EvaluatePlayerSafety(nil, Vector3(4.0, 0.0, 4.0));
    EvalLaneDodge := Dir.EvaluatePlayerSafety(nil, Vector3(4.0, 0.0, -4.0));
    AssertEquals(1, EvalLaneHit.ThreateningZoneCount);
    AssertEquals(0, EvalLaneDodge.ThreateningZoneCount);

    SerializedScene := ComponentToString(Dir);
    AssertTrue(Pos('BossArenaPreview', SerializedScene) = 0);

    Dir.ApplyPreset(bapSavageRaidOverlapCombo);
    Dir.DamageMultiplier := 2.75;
    JsonCfg := TBossArenaHelper.ExportDirectorJson(Dir);
    AssertTrue(TBossArenaHelper.ImportDirectorJson(Restored, JsonCfg));
    AssertEquals(Ord(bapSavageRaidOverlapCombo), Ord(Restored.Preset));
    AssertSameValue(2.75, Restored.DamageMultiplier, 0.01);
    Md := TBossArenaHelper.GenerateMarkdownReport(Dir);
    AssertTrue(Pos('SavageRaidOverlapCombo', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Dir);
  end;
end;

initialization
  RegisterTest(TTestToolBossArena);

end.
