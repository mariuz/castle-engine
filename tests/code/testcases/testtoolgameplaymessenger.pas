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

{ Automated tests for Phase 373 Gameplay Message Bus & Squad Bark Queue Studio. }
unit TestToolGameplayMessenger;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolGameplayMessenger = class(TCastleTestCase)
  published
    procedure TestHierarchicalDotBoundaryPubSubRoutingAndExactChannelIsolation;
    procedure TestSquadBarkEmergencyPreemptionAntiSpamCooldownAndConfigJsonRoundtrip;
  end;

implementation

uses CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleGameplayMessenger, ToolGameplayMessenger;

procedure TTestToolGameplayMessenger.TestHierarchicalDotBoundaryPubSubRoutingAndExactChannelIsolation;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Bus: TCastleGameplayMessenger;
  SubHier, SubExact, SubFalsePrefix: TGameplayChannelSubscription;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TGameplayMessengerHelper.SpawnSquadCommsBusDemo(Vp, RootOwner, Bus));

    Bus.ClearAllState;
    Bus.RegisterChannelSubscription('SubAllDamage', 'Combat.Damage', True);
    Bus.RegisterChannelSubscription('SubExactDamage', 'Combat.Damage', False);
    Bus.RegisterChannelSubscription('SubTrapDamPrefix', 'Combat.Dam', True);

    { 1. Sub-channel 'Combat.Damage.Critical' matches hierarchical 'Combat.Damage' ONLY (not exact, and NOT 'Combat.Dam'!) }
    AssertEquals(1, Bus.BroadcastGameplayMessage('Combat.Damage.Critical', 'Paladin', 420.0, 'CritHit'));

    { 2. Exact 'Combat.Damage' matches both SubAllDamage and SubExactDamage (still NOT 'Combat.Dam'!) }
    AssertEquals(2, Bus.BroadcastGameplayMessage('Combat.Damage', 'Archer', 85.0, 'ArrowHit'));

    AssertTrue(Bus.FindSubscriptionById('SubAllDamage', SubHier));
    AssertTrue(Bus.FindSubscriptionById('SubExactDamage', SubExact));
    AssertTrue(Bus.FindSubscriptionById('SubTrapDamPrefix', SubFalsePrefix));

    AssertEquals(2, SubHier.DeliveredCount);
    AssertEquals(1, SubExact.DeliveredCount);
    AssertEquals('Dot-boundary check must prevent Combat.Dam from matching Combat.Damage',
      0, SubFalsePrefix.DeliveredCount);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolGameplayMessenger.TestSquadBarkEmergencyPreemptionAntiSpamCooldownAndConfigJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Bus, Restored: TCastleGameplayMessenger;
  DropReason, JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Bus := TCastleGameplayMessenger.Create(RootOwner);
    Bus.Name := 'SquadBus';

    { 1. Ambient patrol bark occupies radio channel for 3.0s }
    AssertTrue(Bus.RequestSquadBark('Bark.Ambient.Patrol', 'Guard_1',
      'All quiet here.', bpAmbientChatter, 3.0, 6.0, DropReason));
    AssertTrue(Bus.HasActiveBark);
    AssertEquals('Guard_1', Bus.ActiveBark.SpeakerName);

    { 2. Equal-priority ambient bark from Guard_2 while Guard_1 speaks is blocked }
    AssertFalse(Bus.RequestSquadBark('Bark.Ambient.Yawn', 'Guard_2',
      'Long shift...', bpAmbientChatter, 2.0, 5.0, DropReason));
    AssertEquals('CHANNEL_BUSY_HIGHER_OR_EQUAL_PRIORITY', DropReason);

    { 3. Higher-priority EMERGENCY bark immediately preempts Guard_1 mid-sentence! }
    AssertTrue(Bus.RequestSquadBark('Bark.Combat.GrenadeOut', 'Captain_Rex',
      'GRENADE! SCATTER!', bpCriticalEmergency, 2.0, 8.0, DropReason));
    AssertEquals(1, Bus.PreemptionCount);
    AssertEquals('Captain_Rex', Bus.ActiveBark.SpeakerName);

    { 4. Step 2.5s -> Captain_Rex finishes speaking, but 5.5s of 8.0s anti-spam cooldown remains on Bark.Combat.GrenadeOut! }
    Bus.StepMessenger(2.5);
    AssertFalse(Bus.HasActiveBark);
    AssertFalse(Bus.RequestSquadBark('Bark.Combat.GrenadeOut', 'Soldier_3',
      'GRENADE!', bpCriticalEmergency, 2.0, 8.0, DropReason));
    AssertEquals('SUPPRESSED_TAG_COOLDOWN', DropReason);
    AssertTrue(Bus.SuppressedSpamCount >= 2);

    { 5. Step remaining +6.0s -> anti-spam cooldown expires and bark is allowed again! }
    Bus.StepMessenger(6.0);
    AssertTrue(Bus.RequestSquadBark('Bark.Combat.GrenadeOut', 'Soldier_3',
      'Another grenade!', bpCriticalEmergency, 2.0, 8.0, DropReason));

    ReportMd := TGameplayMessengerHelper.GenerateMessengerReport(Bus);
    AssertTrue(Pos('Soldier_3', ReportMd) > 0);

    JsonStr := ComponentToString(Bus);
    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleGameplayMessenger;
    AssertEquals(Bus.SubscriptionCount, Restored.SubscriptionCount);
    AssertSameValue(Bus.DefaultBarkCooldownSec, Restored.DefaultBarkCooldownSec, 0.001);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolGameplayMessenger);
end.
