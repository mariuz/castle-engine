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

{ Automated tests for Phase 342 Gameplay Cue Combat Feedback, Hit-Stop
  Time-Dilation, Camera Punch & Fixed-Capacity Floating Damage-Number Pool. }
unit TestToolGameplayCue;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolGameplayCue = class(TCastleTestCase)
  published
    procedure TestCriticalStrikeHitStopUnscaledPopupArcAndTimeScaleRecovery;
    procedure TestFixedCapacityPoolOldestSlotRecyclingAndCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform,
  CastleComponentSerialize,
  CastleGameplayCue, ToolGameplayCue;

procedure TTestToolGameplayCue.TestCriticalStrikeHitStopUnscaledPopupArcAndTimeScaleRecovery;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Dummy: TCastleTransform;
  D: TCastleGameplayCueDirector;
  SlotIdx: Integer;
  S0, S1: TGameplayCuePopupSlot;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TGameplayCueHelper.SpawnCombatTrainingDummyCueDemo(Vp, DesignOwner, Dummy, D));
    AssertTrue(D <> nil);
    AssertSameValue(1.0, D.EffectiveWorldTimeScale, 0.001);

    { 1. Critical strike triggers HitStopTimeScale (0.05x) & camera punch }
    SlotIdx := D.TriggerGameplayCue('GameplayCue.Damage.Critical', Vector3(0.0, 1.75, 0.0), 420.0);
    AssertEquals(1, D.ActivePopupCount);
    AssertSameValue(0.05, D.EffectiveWorldTimeScale, 0.001);
    AssertSameValue(0.09, D.HitStopRemainingSec, 0.001);
    AssertTrue(D.CameraPunchOffset.Length > 0.15);

    S0 := D.GetPopupSlot(SlotIdx);
    AssertTrue(S0.Active);
    AssertTrue(S0.Kind = gckCriticalStrike);
    AssertEquals('420 CRIT!', S0.DisplayText);

    { 2. During Hit-Stop (0.04s < 0.09s), unscaled StepDirector still advances popup arc upward }
    D.StepDirector(0.04);
    AssertSameValue(0.05, D.EffectiveWorldTimeScale, 0.001);
    S1 := D.GetPopupSlot(SlotIdx);
    AssertTrue(S1.WorldPos.Y > S0.WorldPos.Y + 0.10);

    { 3. Stepping past CritHitStopDurationSec (another +0.06s -> 0.10s total) restores 1.0x world time }
    D.StepDirector(0.06);
    AssertSameValue(0.0, D.HitStopRemainingSec, 0.001);
    AssertSameValue(1.0, D.EffectiveWorldTimeScale, 0.001);
    AssertTrue(D.CameraPunchOffset.Length < 0.25);

    { 4. Stepping beyond DefaultPopupLifetimeSec (1.15s) expires popup cleanly }
    D.StepDirector(1.20);
    AssertEquals(0, D.ActivePopupCount);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolGameplayCue.TestFixedCapacityPoolOldestSlotRecyclingAndCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Dummy: TCastleTransform;
  D, RestoredD: TCastleGameplayCueDirector;
  I: Integer;
  Warnings: TStringList;
  Sum: TGameplayCueStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TGameplayCueHelper.SpawnCombatTrainingDummyCueDemo(Vp, DesignOwner, Dummy, D));
    D.MaxPooledPopups := 12;
    AssertEquals(12, D.PoolCapacity);

    { 1. Dispatch 30 staggered cues into a 12-slot pool: oldest slots recycle with 0 overflow }
    for I := 1 to 30 do
    begin
      if (I mod 3) = 0 then
        D.TriggerGameplayCue('GameplayCue.Status.Heal', Vector3(0, 1.5, 0), 50 + I)
      else if (I mod 5) = 0 then
        D.TriggerGameplayCue('GameplayCue.Combat.ShieldParry', Vector3(0, 1.5, 0), 0)
      else
        D.TriggerGameplayCue('GameplayCue.Damage.Slash', Vector3(0, 1.5, 0), 25 + I);
      D.StepDirector(0.02);
    end;

    AssertEquals(12, D.PoolCapacity);
    AssertEquals(12, D.ActivePopupCount);
    AssertEquals(30, D.TotalCuesTriggered);

    Sum := TGameplayCueHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.DirectorCount);
    AssertEquals(12, Sum.ActivePopups);
    AssertEquals(30, Sum.TotalTriggered);
    ReportMd := TGameplayCueHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Gameplay Cue, Hit-Stop & Combat Feedback Report', ReportMd) > 0);

    { 2. Transient burst mesh is never baked into serialized JSON }
    D.HitStopTimeScale := 0.08;
    JsonStr := ComponentToString(D);
    AssertEquals(0, Pos('TransientGameplayCueMesh', JsonStr));

    RestoredD := StringToComponent(JsonStr, RestoredOwner) as TCastleGameplayCueDirector;
    AssertTrue(RestoredD <> nil);
    AssertEquals(12, RestoredD.MaxPooledPopups);
    AssertSameValue(0.08, RestoredD.HitStopTimeScale, 0.001);
    AssertEquals(0, RestoredD.Count);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolGameplayCue);

end.
