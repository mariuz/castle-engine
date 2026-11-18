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

{ Automated tests for Phase 351 Chaos Mover 2.0 Stateless Kinematic Modes
  (GroundWalk, CrouchSlide, WallRun, BuoyantSwim, GrappleZip) & Bit-Exact
  128-Tick Rollback Rewind/Resimulation. }
unit TestToolMoverStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolMoverStudio = class(TCastleTestCase)
  published
    procedure TestStatelessModesSlideWallRunBuoyantSwimAndGrappleZipArrival;
    procedure TestBitExactRollbackRewindAndResimulationPlusCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform,
  CastleComponentSerialize,
  CastleMover2, ToolMoverStudio;

procedure TTestToolMoverStudio.TestStatelessModesSlideWallRunBuoyantSwimAndGrappleZipArrival;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Actor: TCastleTransform;
  Mover: TCastleMoverBehavior;
  Cmd: TMoverInputCmd;
  I: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TMoverStudioHelper.SpawnMover2ArenaDemo(Vp, DesignOwner, Actor, Mover));
    AssertTrue(Mover <> nil);

    { 1. CrouchSlide boosts horizontal speed > WalkMaxSpeed (7.0 -> 11.5 m/s) }
    Cmd := TMoverInputCmd.WalkForward(Vector3(0, 0, -1));
    Cmd.CrouchSlideHeld := True;
    Mover.AdvanceTick(Cmd, 1.0 / 60.0);
    AssertTrue(Mover.CurrentState.Mode = mlmCrouchSlide);
    AssertTrue(Mover.CurrentState.Velocity.Length > Mover.WalkMaxSpeed + 2.0);

    { 2. Jump -> WallRun glides along wall with 0.20x reduced gravity }
    Mover.ResetStateAtPosition(Vector3(-2.5, 2.5, 0.0), mlmAirFalling);
    for I := 1 to 15 do
    begin
      Cmd := TMoverInputCmd.WalkForward(Vector3(0, 0, -1));
      Cmd.WallRunHeld := True;
      Cmd.WallNormalXZ := Vector3(1, 0, 0);
      Mover.AdvanceTick(Cmd, 1.0 / 60.0);
    end;
    AssertTrue(Mover.CurrentState.Mode = mlmWallRun);
    AssertTrue(Mover.CurrentState.Position.Y > 2.2);
    AssertTrue(Mover.CurrentState.Position.Z < -1.5);

    { 3. BuoyantSwim floats submerged actor upward toward WaterSurfaceY = 0.0 }
    Mover.EnableWaterZone := True;
    Mover.WaterSurfaceY := 0.0;
    Mover.ResetStateAtPosition(Vector3(0.0, -3.0, 0.0), mlmAirFalling);
    for I := 1 to 45 do
      Mover.AdvanceTick(Default(TMoverInputCmd), 1.0 / 60.0);
    AssertTrue(Mover.CurrentState.Mode = mlmBuoyantSwim);
    AssertTrue(Mover.CurrentState.Position.Y > -1.8);
    Mover.EnableWaterZone := False;

    { 4. GrappleZip pulls character to (0, 8.5, -14) tower and auto-releases on arrival }
    Mover.ResetStateAtPosition(Vector3(0.0, 0.0, 0.0), mlmGroundWalk);
    for I := 1 to 60 do
    begin
      Cmd := Default(TMoverInputCmd);
      if I = 1 then
      begin
        Cmd.GrappleRequested := True;
        Cmd.GrappleTargetWorld := Vector3(0.0, 8.5, -14.0);
      end;
      Mover.AdvanceTick(Cmd, 1.0 / 60.0);
    end;
    AssertSameValue(0.0, PointsDistance(Vector3(0.0, 8.5, -14.0), Vector3(
      Mover.CurrentState.Position.X, 8.5, -14.0)), 0.1);
    AssertTrue(Mover.CurrentState.Mode <> mlmGrappleZip);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolMoverStudio.TestBitExactRollbackRewindAndResimulationPlusCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Actor: TCastleTransform;
  Mover, RestoredMover: TCastleMoverBehavior;
  WalkCmd, JumpCmd: TMoverInputCmd;
  PosBeforeRewind: TVector3;
  I: Integer;
  Warnings: TStringList;
  Sum: TMoverStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TMoverStudioHelper.SpawnMover2ArenaDemo(Vp, DesignOwner, Actor, Mover));
    Mover.ResetStateAtPosition(Vector3(0.0, 0.0, 0.0), mlmGroundWalk);

    WalkCmd := TMoverInputCmd.WalkForward(Vector3(0, 0, -1));
    for I := 1 to 30 do
      Mover.AdvanceTick(WalkCmd, 1.0 / 60.0);

    PosBeforeRewind := Mover.CurrentState.Position;
    AssertEquals(30, Mover.CurrentState.TickIndex);
    AssertSameValue(0.0, PosBeforeRewind.Y, 0.001);

    { 1. Replaying identical WalkCmd at Tick 15 yields 0.0000m bit-exact parity! }
    AssertTrue(Mover.RewindAndResimulateFromTick(15, WalkCmd, 1.0 / 60.0));
    AssertEquals(30, Mover.CurrentState.TickIndex);
    AssertSameValue(0.0, PointsDistance(PosBeforeRewind, Mover.CurrentState.Position), 0.00001);

    { 2. Retroactively injecting JumpPressed at Tick 15 re-simulates ticks 15..30 airborne! }
    JumpCmd := WalkCmd;
    JumpCmd.JumpPressed := True;
    AssertTrue(Mover.RewindAndResimulateFromTick(15, JumpCmd, 1.0 / 60.0));
    AssertEquals(30, Mover.CurrentState.TickIndex);
    AssertEquals(2, Mover.RollbackResimCount);
    AssertTrue(Mover.CurrentState.Position.Y > 0.80);
    AssertSameValue(Mover.CurrentState.Position.Y, Actor.Translation.Y, 0.001);

    Sum := TMoverStudioHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.MoverCount);
    ReportMd := TMoverStudioHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Chaos Mover 2.0 Rollback Character Locomotion Report', ReportMd) > 0);

    { 3. JSON roundtrip }
    Mover.GrapplePullSpeed := 28.5;
    JsonStr := ComponentToString(Mover);
    RestoredMover := StringToComponent(JsonStr, RestoredOwner) as TCastleMoverBehavior;
    AssertTrue(RestoredMover <> nil);
    AssertSameValue(28.5, RestoredMover.GrapplePullSpeed, 0.01);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolMoverStudio);

end.
