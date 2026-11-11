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

{ Automated tests for @link(TCastleWaypointNode), @link(TCastleNavGrid),
  @link(TCastlePatrolAgentBehavior), and @link(TNavNetworkHelper)
  (Phase 290 — UE 5.9 / 6.0 MassAI, NavGrid & Perception Parity). }
unit TestToolNavNetwork;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolNavNetwork = class(TCastleTestCase)
  published
    procedure TestAStarObstacleAvoidanceBakeAndJsonRoundtrip;
    procedure TestPatrolLoopNavigationDwellAndSightHearingPerception;
  end;

implementation

uses
  CastleVectors, CastleComponentSerialize,
  CastleTransform, CastleScene, CastleViewport,
  CastleNavNetwork, ToolNavNetwork;

procedure TTestToolNavNetwork.TestAStarObstacleAvoidanceBakeAndJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  VP: TCastleViewport;
  WallBox, FloorSlab: TCastleBox;
  Grid, ReloadedGrid: TCastleNavGrid;
  Path: TVector3List;
  I: Integer;
  RoutedAroundWall: Boolean;
  JsonStr: String;
  ReloadedComp: TComponent;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  Path := TVector3List.Create;
  try
    VP := TCastleViewport.Create(DesignOwner);
    VP.Name := 'ViewportMain';

    { Walkable ground slab ignored via NavWalkableIgnoreTag }
    FloorSlab := TCastleBox.Create(DesignOwner);
    FloorSlab.Name := 'WalkableGround';
    FloorSlab.Size := Vector3(30, 0.2, 30);
    FloorSlab.Translation := Vector3(0, -0.1, 0);
    FloorSlab.Tag := NavWalkableIgnoreTag;
    VP.Items.Add(FloorSlab);

    { Blocking stone wall spanning X in [-4 .. +4], Z in [-0.6 .. +0.6], Y in [0 .. 2.5] }
    WallBox := TCastleBox.Create(DesignOwner);
    WallBox.Name := 'CenterBarrierWall';
    WallBox.Size := Vector3(8.0, 2.5, 1.2);
    WallBox.Translation := Vector3(0.0, 1.25, 0.0);
    VP.Items.Add(WallBox);

    Grid := TNavNetworkHelper.CreateOrBakeNavGrid(VP, DesignOwner, 24, 24, 1.0);
    AssertTrue(Grid <> nil);
    AssertTrue(Grid.BlockedCellCount > 0);

    { Center cell at (0, 0, 0) must be blocked by CenterBarrierWall }
    AssertTrue(Grid.IsCellBlocked(12, 12));
    { Far corner cell must remain walkable }
    AssertFalse(Grid.IsCellBlocked(2, 2));

    { A* path from (0, 0, -6) to (0, 0, +6) must route around [-4 .. +4] wall! }
    AssertTrue(Grid.FindPathWorld(Vector3(0, 0, -6), Vector3(0, 0, 6), Path));
    AssertTrue(Path.Count >= 4);

    RoutedAroundWall := false;
    for I := 0 to Path.Count - 1 do
    begin
      if Abs(Path.L[I].X) > 4.0 then
        RoutedAroundWall := true;
      { No waypoint on the path may pierce the solid wall interior }
      AssertFalse((Abs(Path.L[I].X) < 3.8) and (Abs(Path.L[I].Z) < 0.4));
    end;
    AssertTrue(RoutedAroundWall);

    { BlockedCellsData JSON persistence roundtrip }
    JsonStr := ComponentToString(Grid);
    ReloadedComp := StringToComponent(JsonStr, ReloadOwner);
    AssertTrue(ReloadedComp is TCastleNavGrid);
    ReloadedGrid := TCastleNavGrid(ReloadedComp);
    AssertEquals(Grid.BlockedCellCount, ReloadedGrid.BlockedCellCount);
    AssertTrue(ReloadedGrid.IsCellBlocked(12, 12));
  finally
    FreeAndNil(Path);
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolNavNetwork.TestPatrolLoopNavigationDwellAndSightHearingPerception;
var
  DesignOwner: TComponent;
  VP: TCastleViewport;
  FirstWP, WP2: TCastleWaypointNode;
  GuardEntity, PlayerEntity: TCastleTransform;
  Agent: TCastlePatrolAgentBehavior;
  ViaSight, ViaHearing: Boolean;
  Sum: TNavNetworkSummary;
  Md: String;
  StepIdx: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(DesignOwner);
    VP.Name := 'ViewportMain';

    FirstWP := TNavNetworkHelper.CreatePatrolLoop(
      VP, DesignOwner, Vector3(0, 0, 0), 4.0, 3);
    AssertTrue(FirstWP <> nil);
    FirstWP.WaitTimeSec := 1.0; // 1.0s dwell at Waypoint1
    WP2 := FirstWP.ResolveNextWaypoint(DesignOwner);
    AssertTrue(WP2 <> nil);

    GuardEntity := TCastleTransform.Create(DesignOwner);
    GuardEntity.Name := 'CastleGuard';
    GuardEntity.Translation := Vector3(0, 0, 0);
    GuardEntity.Direction := Vector3(0, 0, -1); // facing -Z
    VP.Items.Add(GuardEntity);

    Agent := TNavNetworkHelper.AttachPatrolAgent(
      GuardEntity, DesignOwner, FirstWP.Name, '');
    Agent.MoveSpeed := 5.0;
    Agent.SightRadius := 12.0;
    Agent.SightHalfAngleDeg := 45.0; // 90 deg total FOV
    Agent.HearingRadius := 4.0;

    { 1. Sight & Hearing perception cone tests }
    PlayerEntity := TCastleTransform.Create(DesignOwner);
    PlayerEntity.Name := 'StealthPlayer';
    VP.Items.Add(PlayerEntity);

    { Ahead at (0, 0, -9): inside 12m sight cone, outside 4m hearing sphere }
    PlayerEntity.Translation := Vector3(0, 0, -9);
    AssertTrue(Agent.CanPerceiveTarget(PlayerEntity, ViaSight, ViaHearing));
    AssertTrue(ViaSight);
    AssertFalse(ViaHearing);

    { Behind guard at (0, 0, +3): outside sight FOV cone, inside 4m hearing radius! }
    PlayerEntity.Translation := Vector3(0, 0, 3);
    AssertTrue(Agent.CanPerceiveTarget(PlayerEntity, ViaSight, ViaHearing));
    AssertFalse(ViaSight);
    AssertTrue(ViaHearing);

    { Far behind at (0, 0, +10): neither seen nor heard }
    PlayerEntity.Translation := Vector3(0, 0, 10);
    AssertFalse(Agent.CanPerceiveTarget(PlayerEntity, ViaSight, ViaHearing));

    { 2. Step patrol to reach FirstWP (4m away at 5m/s -> ~0.8s), verify dwell & advance to WP2 }
    for StepIdx := 1 to 5 do
      Agent.StepPatrol(0.25);
    AssertEquals(1, Agent.ReachedWaypointCount);
    AssertEquals(WP2.Name, Agent.CurrentWaypointName);

    { During the 1.0s dwell pause at FirstWP, guard stays near FirstWP }
    Agent.StepPatrol(0.4);
    AssertVectorEquals(FirstWP.WorldTranslation, GuardEntity.Translation, 0.05);

    { After dwell finishes, guard moves toward WP2 }
    Agent.StepPatrol(0.8);
    Agent.StepPatrol(0.5);
    AssertTrue(PointsDistance(FirstWP.WorldTranslation, GuardEntity.Translation) > 1.0);

    { 3. Network summary & Markdown export }
    Sum := TNavNetworkHelper.ScanNavNetwork(VP);
    AssertEquals(3, Length(Sum.Waypoints));
    AssertEquals(0, Sum.BrokenWaypointLinks);
    AssertEquals(1, Length(Sum.Agents));
    Md := TNavNetworkHelper.FormatNavReportMarkdown(Sum, VP);
    AssertTrue(Pos('CastleGuard', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolNavNetwork);
end.
