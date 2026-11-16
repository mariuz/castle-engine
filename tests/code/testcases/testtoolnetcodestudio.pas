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

{ Automated unit tests for Phase 321 Iris-Style Netcode Replication Graph,
  Spatial Relevancy Culling, Priority Starvation Protection, Snapshot SLerp
  Interpolation & Server-Authoritative Lag-Compensated Hitbox Rewind Studio
  (@link(TCastleNetReplicationManager), @link(TCastleReplicatedBehavior),
  @link(TNetcodeStudioHelper)). }
unit TestToolNetcodeStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolNetcodeStudio = class(TCastleTestCase)
  published
    procedure TestIrisSpatialRelevancyCullingPriorityStarvationProtectionAndInterpolation;
    procedure TestServerLagCompensatedHitboxRewindConfirmedHitVsUnrewoundMiss;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize, CastleNetcodeIris, ToolNetcodeStudio;

procedure TTestToolNetcodeStudio.TestIrisSpatialRelevancyCullingPriorityStarvationProtectionAndInterpolation;
var
  OwnerComp: TComponent;
  Vp: TCastleViewport;
  Mgr: TCastleNetReplicationManager;
  SprintT, FarCrate, PropB, BossFar: TCastleTransform;
  SprintRep, FarRep, PropBRep, BossRep: TCastleReplicatedBehavior;
  InterpPos: TVector3;
  InterpRot: TVector4;
  K: Integer;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TNetcodeStudioHelper.SpawnMultiplayerIrisArenaDemo(
      Vp, OwnerComp, Mgr, SprintT, FarCrate, SprintRep, FarRep);

    { Add a second near prop + a distant AlwaysRelevant Boss at Z = -150m }
    PropB := TCastleBox.Create(OwnerComp);
    PropB.Translation := Vector3(4.0, 0.9, -8.0);
    Vp.Items.Add(PropB);
    PropBRep := TCastleReplicatedBehavior.Create(OwnerComp);
    PropBRep.BasePriority := 1.0;
    PropB.AddBehavior(PropBRep);

    BossFar := TCastleBox.Create(OwnerComp);
    BossFar.Translation := Vector3(0.0, 2.0, -150.0);
    Vp.Items.Add(BossFar);
    BossRep := TCastleReplicatedBehavior.Create(OwnerComp);
    BossRep.BasePriority := 2.0;
    BossRep.AlwaysRelevant := True;
    BossFar.AddBehavior(BossRep);

    { Tight bandwidth budget: 18 bytes/tick = ONLY 1 actor can send per tick!
      Verify starvation protection ensures ALL 3 relevant actors (SprintRep, PropBRep, BossRep)
      get turns across 12 ticks, while spatially culled FarRep (120m > 45m) sends 0 packets! }
    Mgr.ResetSimulation;
    SprintRep.ResetNetState;
    FarRep.ResetNetState;
    PropBRep.ResetNetState;
    BossRep.ResetNetState;
    Mgr.ServerTickHz := 20.0;
    Mgr.MaxBytesPerTick := 18;
    Mgr.SimulatedRttMs := 60.0;
    Mgr.SimulatedJitterMs := 0.0;
    Mgr.ClientInterpDelayMs := 50.0;

    for K := 1 to 12 do
    begin
      SprintT.Translation := Vector3(K * 0.5, 0.90, -10.0);
      Mgr.StepReplication(Vp, OwnerComp, 0.05, TVector3.Zero);
    end;

    AssertEquals(0, FarRep.SentPacketCount); // Spatially culled!
    AssertFalse(FarRep.LastRelevant);
    AssertTrue(BossRep.SentPacketCount >= 2); // AlwaysRelevant overrides 150m distance!
    AssertTrue(SprintRep.SentPacketCount >= 4);
    AssertTrue(PropBRep.SentPacketCount >= 2); // Starvation-protected!

    AssertTrue(SprintRep.EvaluateClientInterpolatedPose(
      Mgr.ClientRenderServerTimeSec, InterpPos, InterpRot));
    AssertTrue((InterpPos.X > 1.0) and (InterpPos.X < 6.0));
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolNetcodeStudio.TestServerLagCompensatedHitboxRewindConfirmedHitVsUnrewoundMiss;
var
  OwnerComp, LoadedComp: TComponent;
  Vp: TCastleViewport;
  Mgr, LoadedMgr: TCastleNetReplicationManager;
  SprintT, FarCrate: TCastleTransform;
  SprintRep, FarRep, HitActor: TCastleReplicatedBehavior;
  RewoundCenter, AimOrigin, AimDir: TVector3;
  UnrewoundDist: Single;
  Rep: TNetcodeAuditReport;
  JsonStr: String;
  K: Integer;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TNetcodeStudioHelper.SpawnMultiplayerIrisArenaDemo(
      Vp, OwnerComp, Mgr, SprintT, FarCrate, SprintRep, FarRep);

    Mgr.ResetSimulation;
    SprintRep.ResetNetState;
    Mgr.MaxBytesPerTick := 180;
    Mgr.ServerTickHz := 20.0;
    Mgr.SimulatedRttMs := 200.0;
    Mgr.ClientInterpDelayMs := 100.0;

    { Move SprintT at constant 6.0 m/s along +X from X = 0.0 (t=0) to X = 6.0m (t=1.0s) }
    SprintT.Translation := Vector3(0.0, 0.90, -10.0);
    SprintRep.RecordServerHistoryPose(0.0, 2.0);
    for K := 1 to 20 do
    begin
      SprintT.Translation := Vector3(K * 0.30, 0.90, -10.0); // 6.0m at K=20 (t=1.00s)
      Mgr.StepReplication(Vp, OwnerComp, 0.05, TVector3.Zero);
    end;
    AssertSameValue(6.0, SprintT.Translation.X, 1e-3);

    { Shooter at (4.20, 0.90, 0.0) fires straight along -Z at X = 4.20m (where target WAS 0.30s ago at t=0.70s!) }
    AimOrigin := Vector3(4.20, 0.90, 0.0);
    AimDir := Vector3(0.0, 0.0, -1.0);

    { 1. With RewindDurationSec = 0.0s (no lag compensation): MISSES because target is at X = 6.00m (dist 1.80m > 0.70m)! }
    AssertFalse(Mgr.LagCompensatedRaycast(Vp, OwnerComp, AimOrigin, AimDir, 0.0,
      HitActor, RewoundCenter, UnrewoundDist));
    AssertSameValue(1.80, UnrewoundDist, 0.02);

    { 2. With RewindDurationSec = 0.30s (100ms one-way + 200ms interp/reaction): CONFIRMED HIT at X = 4.20m! }
    AssertTrue(Mgr.LagCompensatedRaycast(Vp, OwnerComp, AimOrigin, AimDir, 0.30,
      HitActor, RewoundCenter, UnrewoundDist));
    AssertTrue(HitActor = SprintRep);
    AssertSameValue(4.20, RewoundCenter.X, 0.05);
    AssertSameValue(1.80, UnrewoundDist, 0.02);

    JsonStr := ComponentToString(Mgr);
    LoadedComp := StringToComponent(JsonStr, OwnerComp);
    AssertTrue(LoadedComp is TCastleNetReplicationManager);
    LoadedMgr := TCastleNetReplicationManager(LoadedComp);
    AssertSameValue(200.0, LoadedMgr.SimulatedRttMs, 1e-2);

    Rep := TNetcodeStudioHelper.AuditNetcode(Vp, OwnerComp);
    try
      AssertEquals(2, Rep.ManagerCount);
      AssertEquals(0, Rep.Warnings.Count);
    finally
      FreeAndNil(Rep);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolNetcodeStudio);
end.
