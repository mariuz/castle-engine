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

{ Automated tests for Phase 370 Wall-Crevice & Seam Micro-Clutter Studio. }
unit TestToolCreviceClutter;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolCreviceClutter = class(TCastleTestCase)
  published
    procedure TestConcaveWallSeamAccumulationOpenCenterCleanlinessAndSeededDeterminism;
    procedure TestSkirtWidthScalingPresetsAndTransientCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleCreviceClutter, ToolCreviceClutter;

procedure TTestToolCreviceClutter.TestConcaveWallSeamAccumulationOpenCenterCleanlinessAndSeededDeterminism;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Volume: TCastleCreviceClutterVolume;
  FirstCount, SecondCount, I, OpenCenterCount: Integer;
  FirstPos0: TVector3;
  Item: TCreviceClutterItem;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TCreviceClutterHelper.SpawnCourtyardLWallDemo(Vp, RootOwner, Volume));

    FirstCount := Volume.ClutterCount;
    AssertTrue('L-Wall courtyard must accumulate > 12 crevice clutter items along North/West seams',
      FirstCount > 12);
    AssertTrue('Concave North-West L-corner must register multi-wall inside-corner items',
      Volume.InsideCornerItemCount >= 1);

    { Every spawned item must hug a wall within SeamSkirtWidthMeters — 0 items in open SE courtyard! }
    OpenCenterCount := 0;
    for I := 0 to FirstCount - 1 do
    begin
      Item := Volume.GetClutterItem(I);
      AssertTrue(Item.WallDistanceMeters <= Volume.SeamSkirtWidthMeters + 0.01);
      if (Item.WorldPos.X > -2.5) and (Item.WorldPos.Z > -2.5) then
        Inc(OpenCenterCount);
    end;
    AssertEquals('Open courtyard away from walls must remain 100% clutter-free', 0, OpenCenterCount);

    { Seeded determinism }
    FirstPos0 := Volume.GetClutterItem(0).WorldPos;
    SecondCount := Volume.BakeCreviceClutterFromWorld(Vp.Items);
    AssertEquals(FirstCount, SecondCount);
    AssertVectorEquals(FirstPos0, Volume.GetClutterItem(0).WorldPos, 0.0001);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolCreviceClutter.TestSkirtWidthScalingPresetsAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Volume, Restored: TCastleCreviceClutterVolume;
  NarrowCnt, WideCnt: Integer;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TCreviceClutterHelper.SpawnCourtyardLWallDemo(Vp, RootOwner, Volume));

    Volume.Preset := ccpMossyDungeonPebbles; { 1.20m skirt }
    NarrowCnt := Volume.BakeCreviceClutterFromWorld(Vp.Items);

    Volume.Preset := ccpAutumnWindblownLeaves; { 2.10m skirt, 92% density }
    WideCnt := Volume.BakeCreviceClutterFromWorld(Vp.Items);
    AssertTrue('Wider 2.10m autumn leaf skirt must bake more clutter than 1.20m narrow pebble skirt',
      WideCnt > NarrowCnt);

    ReportMd := TCreviceClutterHelper.GenerateCreviceReport(Volume);
    AssertTrue(Pos('Windblown Autumn Leaf Drift Skirt', ReportMd) > 0);

    JsonStr := ComponentToString(Volume);
    AssertEquals(0, Pos('TransientCreviceClutterMesh', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleCreviceClutterVolume;
    AssertTrue(Restored.Preset = ccpAutumnWindblownLeaves);
    AssertEquals(WideCnt, Restored.ClutterCount);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolCreviceClutter);
end.
