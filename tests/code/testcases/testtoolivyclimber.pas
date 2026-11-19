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

{ Automated tests for Phase 379 Procedural Ivy, Vine & Root Surface Climber Studio. }
unit TestToolIvyClimber;

{$I castleconf.inc}

interface

uses Classes, SysUtils, Math, CastleTester;

type
  TTestToolIvyClimber = class(TCastleTestCase)
  published
    procedure TestMasonryWallThigmotropicClimbVsOpenAirDroopTermination;
    procedure TestSeededGrowthDeterminismPresetsAndTransientCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleIvyClimber, ToolIvyClimber;

procedure TTestToolIvyClimber.TestMasonryWallThigmotropicClimbVsOpenAirDroopTermination;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  WallIvy, OpenAirIvy: TCastleIvyClimber;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TIvyClimberHelper.SpawnMasonryWallIvyDemo(Vp, RootOwner, WallIvy));

    { 1. Ivy rooted at base of 3.6m masonry wall clings via WorldRay and climbs > 2.5m high! }
    AssertTrue(WallIvy.NodeCount >= 20);
    AssertTrue(WallIvy.AttachedNodeCount >= 18);
    AssertTrue(WallIvy.MaxReachedHeightY > 2.5);
    AssertTrue(WallIvy.TotalLeafCount >= 36);

    { 2. Ivy placed 30m away in empty air (no wall within AdhesionRadiusMeters) droops & stops quickly }
    OpenAirIvy := TCastleIvyClimber.Create(RootOwner);
    OpenAirIvy.Name := 'UnsupportedAirIvy';
    OpenAirIvy.Translation := Vector3(30.0, 1.0, 30.0);
    Vp.Items.Add(OpenAirIvy);
    OpenAirIvy.GrowIvyOnWorld(Vp.Items);

    AssertEquals('Unsupported ivy in empty air must have 0 wall-clung nodes',
      0, OpenAirIvy.AttachedNodeCount);
    AssertTrue(OpenAirIvy.NodeCount < WallIvy.NodeCount);
    AssertSameValue(1.0, OpenAirIvy.MaxReachedHeightY, 0.05);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolIvyClimber.TestSeededGrowthDeterminismPresetsAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Ivy, Restored: TCastleIvyClimber;
  CountPass1, LeavesPass1: Integer;
  LastNodePass1, LastNodePass2: TIvyGrowthNode;
  JsonStr: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TIvyClimberHelper.SpawnMasonryWallIvyDemo(Vp, RootOwner, Ivy));

    Ivy.Preset := ivpAutumnCrimsonCreeper;
    Ivy.RandomSeed := 777123;
    CountPass1 := Ivy.GrowIvyOnWorld(Vp.Items);
    LeavesPass1 := Ivy.TotalLeafCount;
    LastNodePass1 := Ivy.GetNode(CountPass1 - 1);

    { Regrowing with identical seed must produce bit-identical node count, leaf count & coordinates }
    AssertEquals(CountPass1, Ivy.GrowIvyOnWorld(Vp.Items));
    AssertEquals(LeavesPass1, Ivy.TotalLeafCount);
    LastNodePass2 := Ivy.GetNode(CountPass1 - 1);
    AssertSameValue(LastNodePass1.WorldPos.X, LastNodePass2.WorldPos.X, 1e-5);
    AssertSameValue(LastNodePass1.WorldPos.Y, LastNodePass2.WorldPos.Y, 1e-5);
    AssertSameValue(LastNodePass1.WorldPos.Z, LastNodePass2.WorldPos.Z, 1e-5);

    { Verify csTransient-clean JSON roundtrip }
    JsonStr := ComponentToString(Ivy);
    AssertEquals(0, Pos('IvyClimberTransientMesh', JsonStr));
    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleIvyClimber;
    AssertEquals(Ord(ivpAutumnCrimsonCreeper), Ord(Restored.Preset));
    AssertEquals(777123, Restored.RandomSeed);
    AssertEquals(4, Restored.PrimaryTendrils);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolIvyClimber);
end.
