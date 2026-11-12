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

{ Automated unit tests for Phase 310: Gameplay Ability, Cooldown, Status
  Buff/Debuff & Attribute System (GAS) Studio (@link(CastleGameplayAbility),
  @link(ToolAbilityStudio)). }
unit TestToolAbilityStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolAbilityStudio = class(TCastleTestCase)
  published
    procedure TestAttributeModifierAggregatorCooldownCostAndJsonRoundtrip;
    procedure TestStackingDoTPurgeByTagImmunityCrowdControlBlockAndAudit;
  end;

implementation

uses
  CastleVectors, CastleComponentSerialize,
  CastleTransform, CastleViewport, CastleLivingBehaviors,
  CastleGameplayAbility, ToolAbilityStudio;

procedure TTestToolAbilityStudio.TestAttributeModifierAggregatorCooldownCostAndJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  Vp: TCastleViewport;
  Mage, Paladin, ReloadedMage: TCastleAbilitySystemBehavior;
  PaladinLiving: TCastleLiving;
  FlatSword, BerserkMul: TGasEffectDef;
  Reason, JsonStr: String;
  ReloadedRoot: TComponent;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    Mage := TAbilityStudioHelper.SpawnCombatActorWithGas(
      Vp, DesignOwner, 'MageHero', gapArcaneMage, Vector3(-2.0, 0.0, 0.0), True);
    Paladin := TAbilityStudioHelper.SpawnCombatActorWithGas(
      Vp, DesignOwner, 'PaladinTarget', gapVanguardPaladin, Vector3(2.0, 0.0, 0.0), True);
    AssertTrue(Mage <> nil);
    AssertTrue(Paladin <> nil);

    { 1. Exact UE GAS Aggregator: (Base 45 + Flat 15) * (1 + 0.25*2) * 1.2 = 60 * 1.5 * 1.2 = 108.0 }
    FlatSword := TGasEffectDef.CreateDefault('RuneSwordFlat');
    FlatSword.DurationSec := 10.0;
    FlatSword.TargetAttrName := 'AttackPower';
    FlatSword.ModOp := gmoFlatAdd;
    FlatSword.ModMagnitude := 15.0;
    Mage.RegisterEffectDef(FlatSword);

    BerserkMul := TGasEffectDef.CreateDefault('BerserkPotion');
    BerserkMul.DurationSec := 10.0;
    BerserkMul.TargetAttrName := 'AttackPower';
    BerserkMul.ModOp := gmoMultiply;
    BerserkMul.ModMagnitude := 1.2;
    Mage.RegisterEffectDef(BerserkMul);

    AssertTrue(Mage.ApplyEffectById('RuneSwordFlat', Reason));
    AssertTrue(Mage.ApplyEffectById('ArcaneSurgeBuff', Reason));
    AssertTrue(Mage.ApplyEffectById('ArcaneSurgeBuff', Reason)); { 2 stacks = +50% }
    AssertTrue(Mage.ApplyEffectById('BerserkPotion', Reason));
    AssertSameValue(108.0, Mage.GetCurrentValue('AttackPower'), 1e-3);

    { 2. Cast Fireball (25 Mana, 3.0s CD, -28 direct HP + IgniteBurnDoT -6 HP/s) at Paladin }
    AssertTrue(Mage.TryActivateAbility('Fireball', Paladin, Reason));
    AssertSameValue(95.0, Mage.GetCurrentValue('Mana'), 1e-3);
    AssertSameValue(3.0, Mage.GetRemainingCooldown('Fireball'), 1e-3);
    AssertSameValue(152.0, Paladin.GetCurrentValue('Health'), 1e-3);
    AssertEquals(1, Paladin.ActiveStacksOf('IgniteBurnDoT'));

    { Immediate recast blocked by cooldown }
    AssertFalse(Mage.TryActivateAbility('Fireball', Paladin, Reason));
    AssertTrue(Pos('cooldown', LowerCase(Reason)) > 0);

    { Step 1.0s -> Burn ticks -6 HP (152 -> 146) and syncs TCastleLiving.Life }
    TAbilityStudioHelper.StepAllGasSystems(Vp, DesignOwner, 1.0);
    AssertSameValue(146.0, Paladin.GetCurrentValue('Health'), 1e-3);
    PaladinLiving := Paladin.Parent.FindBehavior(TCastleLiving) as TCastleLiving;
    AssertTrue(PaladinLiving <> nil);
    AssertSameValue(146.0, PaladinLiving.Life, 1e-3);

    { 3. JSON serialization roundtrip }
    JsonStr := ComponentToString(Vp);
    ReloadedRoot := StringToComponent(JsonStr, ReloadOwner);
    AssertTrue(ReloadedRoot is TCastleViewport);
    ReloadedMage := ReloadOwner.FindComponent(Mage.Name) as TCastleAbilitySystemBehavior;
    AssertTrue(ReloadedMage <> nil);
    AssertSameValue(45.0, ReloadedMage.GetBaseValue('AttackPower'), 1e-3);
    AssertTrue(ReloadedMage.HasMatchingTag('Class.ArcaneMage'));
    AssertEquals(3, ReloadedMage.Abilities.Count);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolAbilityStudio.TestStackingDoTPurgeByTagImmunityCrowdControlBlockAndAudit;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Mage, Ranger: TCastleAbilitySystemBehavior;
  StunEff: TGasEffectDef;
  BadAbility: TGasAbilityDef;
  Reason, Md: String;
  Report: TAbilityStudioAuditReport;
begin
  DesignOwner := TComponent.Create(nil);
  try
    { 1. Dot-boundary hierarchical Gameplay Tag matching }
    AssertTrue(MatchesGasTagPattern('Status.Debuff.Fire.Burn', 'Status.Debuff.Fire.*'));
    AssertTrue(MatchesGasTagPattern('Status.Debuff.Fire', 'Status.Debuff.Fire.*'));
    AssertFalse(MatchesGasTagPattern('Status.Debuff.Fire2', 'Status.Debuff.Fire.*'));

    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';
    Mage := TAbilityStudioHelper.SpawnCombatActorWithGas(
      Vp, DesignOwner, 'TestMage', gapArcaneMage, TVector3.Zero, False);
    Ranger := TAbilityStudioHelper.SpawnCombatActorWithGas(
      Vp, DesignOwner, 'TestRanger', gapShadowRanger, Vector3(3.0, 0.0, 0.0), False);
    AssertTrue(Ranger <> nil);

    { 2. Stack IgniteBurnDoT 2x (-12 HP/s) on Mage, step 1s -> 100 -> 88 HP }
    AssertTrue(Mage.ApplyEffectById('IgniteBurnDoT'));
    AssertTrue(Mage.ApplyEffectById('IgniteBurnDoT'));
    AssertEquals(2, Mage.ActiveStacksOf('IgniteBurnDoT'));
    Mage.StepSimulation(1.0);
    AssertSameValue(88.0, Mage.GetCurrentValue('Health'), 1e-3);

    { 3. Cast ArcaneWard -> FireImmunityWard ('Status.Debuff.Fire.*') purges existing burn
         AND blocks subsequent IgniteBurnDoT applications! }
    AssertTrue(Mage.TryActivateAbility('ArcaneWard', nil, Reason));
    AssertEquals(0, Mage.ActiveStacksOf('IgniteBurnDoT'));
    AssertTrue(Mage.IsImmuneToTag('Status.Debuff.Fire.Burn'));
    AssertFalse(Mage.ApplyEffectById('IgniteBurnDoT', Reason));
    AssertTrue(Pos('immunity', LowerCase(Reason)) > 0);

    { 4. Apply CrowdControl Stun -> blocks Fireball until stun duration (2.0s) expires }
    StunEff := TGasEffectDef.CreateDefault('ShockStun');
    StunEff.EffectTag := 'Status.CrowdControl.Stun';
    StunEff.GrantedTag := 'Status.CrowdControl.Stun';
    StunEff.DurationSec := 2.0;
    Mage.RegisterEffectDef(StunEff);
    AssertTrue(Mage.ApplyEffectDef(StunEff, Reason));
    AssertFalse(Mage.CanActivateAbility('Fireball', Reason));
    AssertTrue(Pos('blocked by tag', LowerCase(Reason)) > 0);

    Mage.StepSimulation(2.1);
    AssertTrue(Mage.CanActivateAbility('Fireball', Reason));

    { 5. Audit catches undeclared CostAttrName & builds Markdown report }
    BadAbility := TGasAbilityDef.CreateDefault('FuryStrike');
    BadAbility.CostAttrName := 'FuryPool';
    BadAbility.CostAmount := 40.0;
    Ranger.RegisterAbility(BadAbility);

    Report := TAbilityStudioHelper.ScanDesign(Vp, DesignOwner);
    try
      AssertEquals(2, Length(Report.Systems));
      AssertEquals(1, Report.Warnings.Count);
      AssertTrue(Pos('FuryPool', Report.Warnings[0]) > 0);
    finally
      FreeAndNil(Report);
    end;

    Md := TAbilityStudioHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('TestMage', Md) > 0);
    AssertTrue(Pos('FireImmunityWard', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolAbilityStudio);
end.
