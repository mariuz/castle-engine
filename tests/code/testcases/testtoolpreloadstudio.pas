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

{ Automated tests for Phase 365 Async Asset Preloader & VRAM Residency Studio. }
unit TestToolPreloadStudio;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolPreloadStudio = class(TCastleTestCase)
  published
    procedure TestPriorityOrderFrameBudgetThrottlingAndHitchFreeMultiFrameDrain;
    procedure TestPinnedHandleProtectionLruVramEvictionAndConfigJsonRoundtrip;
  end;

implementation

uses CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleAssetPreloader, ToolPreloadStudio;

procedure TTestToolPreloadStudio.TestPriorityOrderFrameBudgetThrottlingAndHitchFreeMultiFrameDrain;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Queue: TCastleAssetPreloadQueue;
  Step1, Step2: TPreloadFrameStepResult;
  BossE, SparksE, CrateE, CloudsE: TPreloadAssetEntry;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TPreloadStudioHelper.SpawnBossAirlockPreloadDemo(Vp, RootOwner, Queue));

    Queue.ClearQueue;
    Queue.MaxBudgetMsPerFrame := 2.5;
    Queue.MaxVramBudgetMB := 512.0;

    { Enqueue 4 requests out-of-order (each costing 1.1 ms -> max 2 fit inside 2.5 ms/frame!) }
    Queue.EnqueueAssetRequest('castle-data:/env/distant_clouds.ktx2', prpBackgroundPrefetch, 24.0, 1.1, False);
    Queue.EnqueueAssetRequest('castle-data:/fx/sword_sparks.x3d', prpHighCombatVfx, 18.0, 1.1, False);
    Queue.EnqueueAssetRequest('castle-data:/cutscene/boss_intro_rig.gltf', prpCriticalCutscene, 40.0, 1.1, True);
    Queue.EnqueueAssetRequest('castle-data:/props/wooden_crate.gltf', prpNormalGameplay, 12.0, 1.1, False);

    { Frame 1: Strictly warms Critical + HighVFX (2.2 ms <= 2.5 ms) and defers Normal + Background to prevent frame hitch! }
    Step1 := Queue.StepFrameWarmupBudget;
    AssertEquals(2, Step1.AssetsWarmedThisFrame);
    AssertSameValue(2.2, Step1.FrameTimeSpentMs, 0.01);
    AssertEquals(2, Step1.RemainingQueuedCount);

    AssertTrue(Queue.FindEntryByUrl('castle-data:/cutscene/boss_intro_rig.gltf', BossE));
    AssertTrue(Queue.FindEntryByUrl('castle-data:/fx/sword_sparks.x3d', SparksE));
    AssertTrue(Queue.FindEntryByUrl('castle-data:/props/wooden_crate.gltf', CrateE));
    AssertTrue(Queue.FindEntryByUrl('castle-data:/env/distant_clouds.ktx2', CloudsE));

    AssertTrue(BossE.State = prsResidentLoaded);
    AssertTrue(SparksE.State = prsResidentLoaded);
    AssertTrue(CrateE.State = prsQueuedPending);
    AssertTrue(CloudsE.State = prsQueuedPending);

    { Frame 2: Drains remaining Normal + Background within 2.2 ms }
    Step2 := Queue.StepFrameWarmupBudget;
    AssertEquals(2, Step2.AssetsWarmedThisFrame);
    AssertEquals(0, Step2.RemainingQueuedCount);
    AssertSameValue(94.0, Step2.ResidentVramMB, 0.01);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolPreloadStudio.TestPinnedHandleProtectionLruVramEvictionAndConfigJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Queue, Restored: TCastleAssetPreloadQueue;
  StepRes: TPreloadFrameStepResult;
  PaladinE, RoomAE, RoomBE, RoomCE: TPreloadAssetEntry;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Queue := TCastleAssetPreloadQueue.Create(RootOwner);
    Queue.Name := 'VramLruQueue';
    Queue.ClearQueue;
    Queue.MaxBudgetMsPerFrame := 10.0;
    Queue.MaxVramBudgetMB := 100.0;

    { Load 3 assets totaling 95 MB <= 100 MB (Paladin is oldest, but PINNED!) }
    Queue.EnqueueAssetRequest('castle-data:/hero/paladin_body.gltf', prpCriticalCutscene, 40.0, 1.0, True);
    Queue.EnqueueAssetRequest('castle-data:/dungeon/room_a.gltf', prpNormalGameplay, 30.0, 1.0, False);
    Queue.EnqueueAssetRequest('castle-data:/dungeon/room_b.gltf', prpNormalGameplay, 25.0, 1.0, False);
    Queue.StepFrameWarmupBudget;
    AssertSameValue(95.0, Queue.CurrentResidentVramMB, 0.01);

    { Refresh room_a so room_b becomes the least-recently-used unpinned asset }
    AssertTrue(Queue.TouchResidentAsset('castle-data:/dungeon/room_a.gltf'));

    { Load room_c (25 MB) -> 95 + 25 = 120 MB > 100 MB -> MUST evict room_b while preserving pinned paladin_body & touched room_a! }
    Queue.EnqueueAssetRequest('castle-data:/dungeon/room_c.gltf', prpHighCombatVfx, 25.0, 1.0, False);
    StepRes := Queue.StepFrameWarmupBudget;
    AssertEquals(1, StepRes.EvictedCountThisFrame);
    AssertSameValue(95.0, Queue.CurrentResidentVramMB, 0.01);

    AssertTrue(Queue.FindEntryByUrl('castle-data:/hero/paladin_body.gltf', PaladinE));
    AssertTrue(Queue.FindEntryByUrl('castle-data:/dungeon/room_a.gltf', RoomAE));
    AssertTrue(Queue.FindEntryByUrl('castle-data:/dungeon/room_b.gltf', RoomBE));
    AssertTrue(Queue.FindEntryByUrl('castle-data:/dungeon/room_c.gltf', RoomCE));

    AssertTrue('Pinned Paladin handle must never be evicted by LRU', PaladinE.State = prsResidentLoaded);
    AssertTrue('Recently touched room_a must stay resident', RoomAE.State = prsResidentLoaded);
    AssertTrue('Least-recently-used unpinned room_b must be evicted', RoomBE.State = prsEvictedCold);
    AssertTrue('New room_c must become resident', RoomCE.State = prsResidentLoaded);

    ReportMd := TPreloadStudioHelper.GeneratePreloadReport(Queue);
    AssertTrue(Pos('EVICTED_LRU', ReportMd) > 0);

    JsonStr := ComponentToString(Queue);
    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleAssetPreloadQueue;
    AssertEquals(4, Restored.EntryCount);
    AssertEquals(3, Restored.ResidentCount);
    AssertEquals(1, Restored.PinnedResidentCount);
    AssertSameValue(95.0, Restored.CurrentResidentVramMB, 0.01);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolPreloadStudio);
end.
