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

{ Automated unit tests for Phase 328 MassEntity-Style Data-Oriented SoA Crowd
  Simulation, O(1) Spatial Hash Grid, Dijkstra Obstacle Flow-Field & 4-Tier
  Representation LOD Studio (@link(CastleMassEntity), @link(ToolMassEntity)). }
unit TestToolMassEntity;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolMassEntity = class(TCastleTestCase)
  published
    procedure TestSoASwarmSpatialHashSeparationObstacleAvoidanceAndFlowFieldRouting;
    procedure TestThousandEntityThroughputFourTierRepresentationLodsAndCleanJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleMassEntity, ToolMassEntity;

procedure TTestToolMassEntity.TestSoASwarmSpatialHashSeparationObstacleAvoidanceAndFlowFieldRouting;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Swarm: TCastleMassEntityManager;
  MeanBefore, MeanAfter: TVector2;
  SnapA, SnapB: TMassEntitySnapshot;
  I, J: Integer;
  MinPairDist, DistToObstacle: Single;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Swarm := TCastleMassEntityManager.Create(DesignOwner);
    Swarm.Name := 'FlowObstacleSwarm';
    Swarm.BuildVisualBatch := False;
    Swarm.TargetEntityCount := 180;
    Swarm.ClearObstacles;
    { Place a solid 4.0m radius circular obstacle directly between spawn (Z=+10) and goal (Z=-14) }
    Swarm.AddObstacleCircleXZ(0.0, -2.0, 4.0);
    Swarm.GoalPosXZ := Vector2(0.0, -14.0);
    Swarm.BakeGoalFlowField;
    Swarm.RespawnEntitiesInBox(Vector2(-5.0, 8.0), Vector2(5.0, 12.0));
    Vp.Items.Add(Swarm);

    MeanBefore := Swarm.MeanPositionXZ;
    for I := 1 to 100 do
      Swarm.StepSwarm(0.05);
    MeanAfter := Swarm.MeanPositionXZ;

    { 1. Swarm routes around the central obstacle and advances decisively toward Z=-14 }
    AssertTrue(MeanAfter.Y < MeanBefore.Y - 8.0);
    AssertTrue(MeanAfter.Y < 1.0);

    { 2. Every single entity respects the central obstacle circle (R=4.0m) }
    MinPairDist := 1e9;
    for I := 0 to Swarm.ActiveEntityCount - 1 do
    begin
      SnapA := Swarm.GetEntitySnapshot(I);
      DistToObstacle := Hypot(SnapA.PosX - 0.0, SnapA.PosZ - (-2.0));
      AssertTrue(DistToObstacle >= 4.0);

      for J := I + 1 to Swarm.ActiveEntityCount - 1 do
      begin
        SnapB := Swarm.GetEntitySnapshot(J);
        MinPairDist := Min(MinPairDist, Hypot(SnapA.PosX - SnapB.PosX, SnapA.PosZ - SnapB.PosZ));
      end;
    end;
    { Spatial hash separation prevents point-collapse pileups }
    AssertTrue(MinPairDist > 0.02);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolMassEntity.TestThousandEntityThroughputFourTierRepresentationLodsAndCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Swarm, RestoredSwarm: TCastleMassEntityManager;
  SavedJson, Md: String;
  TotalTierSum: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Swarm := TMassEntityHelper.SpawnMassSwarmArenaDemo(Vp, DesignOwner);
    AssertTrue(Swarm <> nil);

    { Scale up to 1,000 SoA entities distributed across [-45..+45] XZ }
    Swarm.ArenaHalfExtent := 60.0;
    Swarm.HighMeshDist := 12.0;
    Swarm.MediumProxyDist := 26.0;
    Swarm.CullDist := 42.0;
    Swarm.TargetEntityCount := 1000;
    Swarm.RespawnEntitiesInBox(Vector2(-48.0, -48.0), Vector2(48.0, 48.0));
    AssertEquals(1000, Swarm.ActiveEntityCount);

    { Step all 1,000 entities + rebuild single-draw-call visual batch }
    Swarm.StepSwarm(0.05);
    AssertTrue(Swarm.LastStepTimeMs < 500.0);

    { Classify all 1,000 entities into 4 UE MassRepresentation LOD buckets }
    Swarm.UpdateRepresentationLods(TVector3.Zero);
    AssertTrue(Swarm.GetTierCount(mrtHighMesh) > 0);
    AssertTrue(Swarm.GetTierCount(mrtMediumProxy) > 0);
    AssertTrue(Swarm.GetTierCount(mrtLowBatchedPoint) > 0);
    AssertTrue(Swarm.GetTierCount(mrtCulledOffscreen) > 0);

    TotalTierSum :=
      Swarm.GetTierCount(mrtHighMesh) +
      Swarm.GetTierCount(mrtMediumProxy) +
      Swarm.GetTierCount(mrtLowBatchedPoint) +
      Swarm.GetTierCount(mrtCulledOffscreen);
    AssertEquals(1000, TotalTierSum);

    { Verify csTransient-clean JSON serialization roundtrip }
    SavedJson := ComponentToString(Swarm);
    AssertEquals(0, Pos('TriangleSet', SavedJson));
    RestoredOwner := TComponent.Create(nil);
    try
      RestoredSwarm := StringToComponent(SavedJson, RestoredOwner) as TCastleMassEntityManager;
      AssertEquals(1000, RestoredSwarm.ActiveEntityCount);
      AssertEquals(2, RestoredSwarm.ObstacleCount);
    finally
      FreeAndNil(RestoredOwner);
    end;

    Md := TMassEntityHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('MassEntity Data-Oriented SoA Crowd Report', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolMassEntity);
end.
