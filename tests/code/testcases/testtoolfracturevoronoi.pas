{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Milestone Phase 400: Voronoi Fracture Cell Cutter, Bond
  Graph & BFS Ground-Support Collapse Studio. }
unit TestToolFractureVoronoi;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolFractureVoronoi = class(TCastleTestCase)
  published
    procedure TestVolumeConservingVoronoiPartitionAndBfsFloatingParapetCollapse;
    procedure TestReinforcedConcreteStrengthResistanceRubbleSettleAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleFractureVoronoi, ToolFractureVoronoi;

procedure TTestToolFractureVoronoi.TestVolumeConservingVoronoiPartitionAndBfsFloatingParapetCollapse;
var
  Root: TComponent;
  VP: TCastleViewport;
  Wall: TCastleVoronoiFractureVolume;
  ExpectedVol: Single;
  I: Integer;
  S: TVoronoiShardState;
  SawTopDetached: Boolean;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TFractureVoronoiHelper.SpawnMasonryWallFractureDemo(Root, Root, Wall));

    { 1. Exact Voronoi partition volume conservation (4.0 * 3.6 * 0.5 = 7.20 m^3)
         and 100% initial BFS ground-graph support (0 detached chunks) }
    ExpectedVol := Wall.WallDimensions.X * Wall.WallDimensions.Y * Wall.WallDimensions.Z;
    AssertSameValue(ExpectedVol, Wall.TotalVolumeM3, 0.02);
    AssertEquals(Wall.ActualShardCount, Wall.SupportedShardCount);
    AssertEquals(0, Wall.DetachedShardCount);
    AssertTrue(Wall.TotalBondCount >= 30);

    { 2. Sever all structural bonds across the mid-height waist band (Y = 1.6m)
         with R = 1.3m cannon impacts across X = -1.4, 0.0, +1.4 so top parapet
         shards at Y > 3.1m are OUTSIDE the blast radius yet lose all ground paths! }
    Wall.ApplyImpactImpulseAtLocal(Vector3(-1.4, 1.6, 0.0), 1.3, 650.0);
    Wall.ApplyImpactImpulseAtLocal(Vector3( 0.0, 1.6, 0.0), 1.3, 650.0);
    Wall.ApplyImpactImpulseAtLocal(Vector3( 1.4, 1.6, 0.0), 1.3, 650.0);

    SawTopDetached := False;
    for I := 0 to Wall.ActualShardCount - 1 do
    begin
      S := Wall.GetShardState(I);
      if S.CenterLocalPos.Y > 3.05 then
      begin
        SawTopDetached := True;
        AssertTrue('Unsupported upper parapet shard detaches via BFS (no sky islands!)',
          S.IsDetachedFalling);
      end;
    end;
    AssertTrue(SawTopDetached);
    AssertTrue(Wall.DetachedShardCount >= 8);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolFractureVoronoi.TestReinforcedConcreteStrengthResistanceRubbleSettleAndJsonRoundtrip;
var
  Pillar, Restored: TCastleVoronoiFractureVolume;
  I: Integer;
  S: TVoronoiShardState;
  SerializedScene, JsonCfg, Md: String;
begin
  Pillar := TCastleVoronoiFractureVolume.Create(nil);
  Restored := TCastleVoronoiFractureVolume.Create(nil);
  try
    { Reinforced concrete (480 Ns) shrugs off a light 150 Ns hammer tap with 0 broken bonds }
    Pillar.ApplyPreset(vfpReinforcedConcretePillar);
    AssertEquals(0, Pillar.ApplyImpactImpulseAtLocal(Vector3(0.0, 2.0, 0.0), 1.5, 150.0));
    AssertEquals(0, Pillar.DetachedShardCount);

    { Shattered tempered glass (25 Ns) shatters immediately & settles onto Y >= 0 rubble }
    Pillar.ApplyPreset(vfpShatteredTemperedGlass);
    AssertTrue(Pillar.ApplyImpactImpulseAtLocal(Vector3(0.0, 1.2, 0.0), 2.5, 220.0) >= 15);
    for I := 1 to 10 do
      Pillar.StepDetachedCollapse(0.15);
    for I := 0 to Pillar.ActualShardCount - 1 do
    begin
      S := Pillar.GetShardState(I);
      AssertTrue('Rubble shards never fall below floor Y = 0',
        S.CenterLocalPos.Y + S.CollapseOffsetLocal.Y >= 0.0);
    end;

    SerializedScene := ComponentToString(Pillar);
    AssertTrue(Pos('VoronoiFracturePreview', SerializedScene) = 0);

    Pillar.RandomSeed := 9090;
    JsonCfg := TFractureVoronoiHelper.ExportVolumeJson(Pillar);
    AssertTrue(TFractureVoronoiHelper.ImportVolumeJson(Restored, JsonCfg));
    AssertEquals(Ord(vfpShatteredTemperedGlass), Ord(Restored.Preset));
    AssertEquals(9090, Restored.RandomSeed);
    Md := TFractureVoronoiHelper.GenerateMarkdownReport(Pillar);
    AssertTrue(Pos('ShatteredTemperedGlass', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Pillar);
  end;
end;

initialization
  RegisterTest(TTestToolFractureVoronoi);

end.
