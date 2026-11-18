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

{ Automated tests for Phase 368 Multi-Slot SmartObject Queue & Cooldown Studio. }
unit TestToolSmartObjectSlots;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolSmartObjectSlots = class(TCastleTestCase)
  published
    procedure TestFourSeatSaturationFifoWaitQueueCooldownBlockAndAutomaticPromotion;
    procedure TestRoleTagGateRejectionWithoutQueuePollutionWorldPoseAndCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleSmartObjectSlots, ToolSmartObjectSlots;

procedure TTestToolSmartObjectSlots.TestFourSeatSaturationFifoWaitQueueCooldownBlockAndAutomaticPromotion;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Station: TCastleMultiSlotSmartObject;
  SlotIdx, I: Integer;
  Reason: String;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TSmartObjectSlotsHelper.SpawnTavernSmartTableDemo(Vp, RootOwner, Station));

    { 1. First 4 patrons immediately claim all 4 seats (0..3) }
    for I := 1 to 4 do
      AssertTrue(Station.RequestClaimOrEnqueue(Format('Npc_%d', [I]), 'Role.Villager', SlotIdx, Reason));
    AssertEquals(0, Station.FreeSlotCount);
    AssertEquals(0, Station.WaitQueueCount);

    { 2. Npc_5 and Npc_6 arrive while full -> queued in strict FIFO order }
    AssertFalse(Station.RequestClaimOrEnqueue('Npc_5', 'Role.Villager', SlotIdx, Reason));
    AssertEquals('QUEUED_WAITING_FIFO', Reason);
    AssertFalse(Station.RequestClaimOrEnqueue('Npc_6', 'Role.Villager', SlotIdx, Reason));
    AssertEquals(2, Station.WaitQueueCount);

    { 3. Npc_2 finishes using Seat 1 -> enters 4.0s cooldown -> Npc_5 MUST wait until cooldown expires! }
    AssertTrue(Station.BeginUsingClaimedSlot('Npc_2'));
    AssertTrue(Station.ReleaseSlotAndStartCooldown('Npc_2'));
    AssertTrue(Station.GetSlot(1).State = sssCoolingDown);

    AssertEquals('Mid-cooldown step (2.0s < 4.0s) must not prematurely promote waiters',
      0, Station.StepSlotsAndPromoteQueue(2.0));
    AssertEquals(2, Station.WaitQueueCount);

    { 4. Cooldown finishes (+2.5s -> 4.5s total) -> FIFO head Npc_5 (NOT Npc_6!) is automatically promoted! }
    AssertEquals(1, Station.StepSlotsAndPromoteQueue(2.5));
    AssertEquals('Npc_5', Station.GetSlot(1).ActiveUserId);
    AssertEquals(1, Station.WaitQueueCount);
    AssertEquals('Npc_6', Station.GetWaiter(0).UserId);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolSmartObjectSlots.TestRoleTagGateRejectionWithoutQueuePollutionWorldPoseAndCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Station, Restored: TCastleMultiSlotSmartObject;
  SlotIdx: Integer;
  Reason, JsonStr, ReportMd: String;
  SlotPos, SlotFwd: TVector3;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Station := TCastleMultiSlotSmartObject.Create(RootOwner);
    Station.Name := 'BlacksmithForge';
    Station.Preset := smspBlacksmithDualForgeAnvil;

    { 1. Untrained farmer lacking Role.Blacksmith / Role.Apprentice is rejected without polluting FIFO queue }
    AssertFalse(Station.RequestClaimOrEnqueue('Peasant_1', 'Role.Farmer', SlotIdx, Reason));
    AssertEquals('REJECTED_MISSING_REQUIRED_TAG', Reason);
    AssertEquals(0, Station.WaitQueueCount);

    { 2. Hierarchical child tag Role.Blacksmith.Master satisfies Role.Blacksmith on Slot 0! }
    AssertTrue(Station.RequestClaimOrEnqueue('MasterGrom', 'Role.Blacksmith.Master', SlotIdx, Reason));
    AssertEquals(0, SlotIdx);
    AssertTrue(Station.GetSlotWorldPose(0, SlotPos, SlotFwd));
    AssertSameValue(-0.95, SlotPos.X, 0.001);
    AssertSameValue(1.0, SlotFwd.Z, 0.001); { 180 deg yaw faces +Z }

    ReportMd := TSmartObjectSlotsHelper.GenerateSmartSlotsReport(Station);
    AssertTrue(Pos('Role.Blacksmith', ReportMd) > 0);

    JsonStr := ComponentToString(Station);
    AssertEquals(0, Pos('TransientSmartSlotMarkers', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleMultiSlotSmartObject;
    AssertTrue(Restored.Preset = smspBlacksmithDualForgeAnvil);
    AssertEquals(2, Restored.SlotCount);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolSmartObjectSlots);
end.
