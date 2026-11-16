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

{ Automated unit tests for Phase 318 2D Gradient-Band Locomotion Blend Space,
  Motion-Warped Root Motion & Frame-Exact Anim Montage Studio
  (@link(TCastleBlendSpace2DBehavior), @link(TCastleAnimMontageBehavior),
  @link(TBlendMontageHelper)). }
unit TestToolBlendMontage;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolBlendMontage = class(TCastleTestCase)
  strict private
    FFiredCueLog: TStringList;
    procedure HandleMontageNotify(Sender: TObject;
      const NotifyName, SectionName: String; const AtTimeSec: Single);
  published
    procedure TestGradientBandWeightsPartitionOfUnityShadowingDampingAndJson;
    procedure TestMontageComboBranchingFrameExactNotifiesTagWindowAndMotionWarp;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleBlendMontage, ToolBlendMontage;

procedure TTestToolBlendMontage.HandleMontageNotify(Sender: TObject;
  const NotifyName, SectionName: String; const AtTimeSec: Single);
begin
  if FFiredCueLog <> nil then
    FFiredCueLog.Add(SectionName + ':' + NotifyName);
end;

procedure TTestToolBlendMontage.TestGradientBandWeightsPartitionOfUnityShadowingDampingAndJson;
var
  OwnerComp, LoadedComp: TComponent;
  Vp: TCastleViewport;
  Hero, Dummy: TCastleTransform;
  Blend, LoadedBlend: TCastleBlendSpace2DBehavior;
  Montage: TCastleAnimMontageBehavior;
  SumW: Single;
  I: Integer;
  JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TBlendMontageHelper.SpawnHeroLocomotionAndMontageDemo(Vp, OwnerComp,
      Hero, Dummy, Blend, Montage);
    AssertTrue(Blend <> nil);

    { 1. Kronecker delta at exact sample coordinate: Idle at (0, 0) = 1.0, others = 0.0 }
    Blend.EvaluateImmediate(0.0, 0.0);
    AssertSameValue(1.0, Blend.GetSample(0).ComputedWeight, 1e-4);
    AssertSameValue(0.0, Blend.GetSample(1).ComputedWeight, 1e-4);
    AssertEquals('idle', Blend.DominantAnimationName);

    { 2. Collinear outer-ring shadowing: halfway between Idle (0,0) and WalkForward (0, 2.2) at (0, 1.1)
      must weight Idle=0.5, WalkForward=0.5, and completely shadow RunForward (0, 5.5) = 0.0! }
    Blend.EvaluateImmediate(0.0, 1.1);
    AssertSameValue(0.5, Blend.GetSample(0).ComputedWeight, 1e-3);
    AssertSameValue(0.5, Blend.GetSample(1).ComputedWeight, 1e-3);
    AssertSameValue(0.0, Blend.GetSample(2).ComputedWeight, 1e-4); // RunForward shadowed!
    AssertSameValue(0.0, Blend.GetSample(3).ComputedWeight, 1e-4); // SprintForward shadowed!

    { 3. Partition of unity across arbitrary diagonal strafe-run query (-45 deg, 3.8 m/s) }
    Blend.EvaluateImmediate(-45.0, 3.8);
    SumW := 0.0;
    for I := 0 to Blend.SampleCount - 1 do
    begin
      AssertTrue(Blend.GetSample(I).ComputedWeight >= -1e-6);
      SumW := SumW + Blend.GetSample(I).ComputedWeight;
    end;
    AssertSameValue(1.0, SumW, 1e-4);

    { 4. Exponential parameter damping toward TargetParamX/Y }
    Blend.EvaluateImmediate(0.0, 0.0);
    Blend.TargetParamX := 90.0;
    Blend.TargetParamY := 2.8;
    for I := 1 to 20 do
      Blend.StepBlendSpace(0.10);
    AssertSameValue(90.0, Blend.CurrentParamX, 0.5);
    AssertSameValue(2.8, Blend.CurrentParamY, 0.05);
    AssertEquals('strafe_right', Blend.DominantAnimationName);

    { 5. ConfigJson roundtrip via ComponentToString / StringToComponent }
    JsonStr := ComponentToString(Blend);
    LoadedComp := StringToComponent(JsonStr, OwnerComp);
    AssertTrue(LoadedComp is TCastleBlendSpace2DBehavior);
    LoadedBlend := TCastleBlendSpace2DBehavior(LoadedComp);
    AssertEquals(Blend.SampleCount, LoadedBlend.SampleCount);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolBlendMontage.TestMontageComboBranchingFrameExactNotifiesTagWindowAndMotionWarp;
var
  OwnerComp: TComponent;
  Vp: TCastleViewport;
  Hero, Dummy: TCastleTransform;
  Blend: TCastleBlendSpace2DBehavior;
  Montage: TCastleAnimMontageBehavior;
  Rep: TBlendMontageAuditReport;
  DistXZ: Single;
  K: Integer;
begin
  FFiredCueLog := TStringList.Create;
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TBlendMontageHelper.SpawnHeroLocomotionAndMontageDemo(Vp, OwnerComp,
      Hero, Dummy, Blend, Montage);
    Montage.OnNotifyTriggered := {$ifdef FPC}@{$endif}HandleMontageNotify;

    { Hero starts at Z = +2.2, Dummy at Z = -2.0 (4.2m apart; standoff = 1.20m -> warped Z = -0.80) }
    AssertSameValue(4.2, Abs(Hero.Translation.Z - Dummy.Translation.Z), 1e-3);

    { 1. Play Slash1 WITHOUT queueing combo -> warps to 1.20m standoff and stops cleanly at 0.55s }
    AssertTrue(Montage.PlayMontageSection('Slash1'));
    for K := 1 to 7 do
      Montage.StepMontage(0.10);
    AssertFalse(Montage.IsPlaying);
    DistXZ := Sqrt(Sqr(Hero.Translation.X - Dummy.Translation.X) +
                   Sqr(Hero.Translation.Z - Dummy.Translation.Z));
    AssertSameValue(1.20, DistXZ, 0.03);
    AssertTrue(FFiredCueLog.IndexOf('Slash1:Cue.SwordWhoosh1') >= 0);
    AssertEquals(-1, FFiredCueLog.IndexOf('Slash2:Cue.SwordWhoosh2'));

    { 2. Play Slash1 AND queue combo during ComboWindow1 [0.30..0.54s] -> chains into Slash2 -> HeavyFinisher }
    FFiredCueLog.Clear;
    AssertTrue(Montage.PlayMontageSection('Slash1'));
    Montage.StepMontage(0.20); // t = 0.20s -> HitboxSlash1 active, ComboWindow1 not yet open
    AssertTrue(Montage.HasActiveMontageTag('Combat.HitboxActive'));
    AssertFalse(Montage.QueueComboInput);

    Montage.StepMontage(0.18); // t = 0.38s -> inside ComboWindow1!
    AssertTrue(Montage.HasActiveMontageTag('Montage.ComboWindow'));
    AssertTrue(Montage.QueueComboInput);

    Montage.StepMontage(0.25); // t = 0.63s -> chained into Slash2!
    AssertTrue(Montage.IsPlaying);
    AssertEquals('Slash2', Montage.CurrentSectionName);

    Montage.StepMontage(0.32); // t = 0.95s -> inside ComboWindow2!
    AssertTrue(Montage.QueueComboInput);
    Montage.StepMontage(0.40); // t = 1.35s -> chained into HeavyFinisher!
    AssertEquals('HeavyFinisher', Montage.CurrentSectionName);
    Montage.StepMontage(0.65); // finishes HeavyFinisher cleanly
    AssertFalse(Montage.IsPlaying);
    AssertTrue(FFiredCueLog.IndexOf('Slash2:Cue.SwordWhoosh2') >= 0);
    AssertTrue(FFiredCueLog.IndexOf('HeavyFinisher:Cue.HeavySlamImpact') >= 0);

    { 3. Dodge Roll i-Frame active tag window [0.06..0.42s] }
    Montage.ApplyPreset(mpDodgeRollInvuln);
    AssertTrue(Montage.PlayMontageSection('DodgeRoll'));
    Montage.StepMontage(0.15);
    AssertTrue(Montage.HasActiveMontageTag('Status.Immunity.DodgeIframe'));
    Montage.StepMontage(0.35); // t = 0.50s -> past i-frame window
    AssertFalse(Montage.HasActiveMontageTag('Status.Immunity.DodgeIframe'));

    Rep := TBlendMontageHelper.AuditBlendAndMontages(Vp, OwnerComp);
    try
      AssertEquals(1, Rep.BlendSpaceCount);
      AssertEquals(1, Rep.MontageCount);
      AssertEquals(0, Rep.Warnings.Count);
    finally
      FreeAndNil(Rep);
    end;
  finally
    FreeAndNil(OwnerComp);
    FreeAndNil(FFiredCueLog);
  end;
end;

initialization
  RegisterTest(TTestToolBlendMontage);
end.
