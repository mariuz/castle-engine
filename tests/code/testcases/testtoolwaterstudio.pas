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

{ Automated unit tests for Phase 308: Gerstner Ocean / River Water System,
  Shoreline Foam & Multi-Pontoon Buoyancy Studio (@link(TCastleWaterVolume),
  @link(TCastleBuoyancyBehavior), @link(TWaterStudioHelper)). }
unit TestToolWaterStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolWaterStudio = class(TCastleTestCase)
  published
    procedure TestGerstnerDispersionNormalsFootprintBoundsAndJsonRoundtrip;
    procedure TestFourPontoonBuoyancyEquilibriumRiverDriftAndPitchRollAlignment;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleComponentSerialize,
  CastleWaterSystem, ToolWaterStudio;

procedure TTestToolWaterStudio.TestGerstnerDispersionNormalsFootprintBoundsAndJsonRoundtrip;
var
  Water, RestoredWater: TCastleWaterVolume;
  RestoredOwner: TComponent;
  SurfY, Foam, MaxY, MinY, MaxFoam: Single;
  Norm, FlowVel: TVector3;
  I: Integer;
  JsonStr: String;
  P: TWaterBodyPreset;
begin
  Water := TCastleWaterVolume.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Water.Name := 'OceanTestVolume';
    Water.SizeX := 30.0;
    Water.SizeZ := 20.0;
    Water.Depth := 10.0;
    Water.ApplyPreset(wbpStormyHighSeas);

    { Query inside footprint: normals must be unit-length with positive Up Y,
      and wave elevations must span both positive crests and negative troughs }
    MaxY := -100.0;
    MinY := 100.0;
    MaxFoam := 0.0;
    for I := 0 to 40 do
    begin
      AssertTrue(Water.SampleSurfaceWorld(
        Vector3(-12.0 + I * 0.6, 0.0, 0.0), 1.2, SurfY, Norm, FlowVel, Foam));
      AssertSameValue(1.0, Norm.Length, 1e-3);
      AssertTrue(Norm.Y > 0.25);
      MaxY := Max(MaxY, SurfY);
      MinY := Min(MinY, SurfY);
      MaxFoam := Max(MaxFoam, Foam);
    end;
    AssertTrue(MaxY > 0.25);
    AssertTrue(MinY < -0.25);
    AssertTrue(MaxFoam > 0.10);

    { Outside [-15..+15] footprint must return false unless InfiniteOcean = true }
    AssertFalse(Water.SampleSurfaceWorld(Vector3(25.0, 0.0, 0.0), 1.2, SurfY, Norm, FlowVel, Foam));
    Water.InfiniteOcean := true;
    AssertTrue(Water.SampleSurfaceWorld(Vector3(25.0, 0.0, 0.0), 1.2, SurfY, Norm, FlowVel, Foam));
    Water.InfiniteOcean := false;

    { Cycle all presets cleanly }
    for P := wbpCalmLake to wbpToxicSwamp do
      Water.ApplyPreset(P);

    { Verify csTransient water mesh is NOT serialized into JSON roundtrip }
    Water.ApplyPreset(wbpFlowingRiver);
    JsonStr := ComponentToString(Water);
    AssertEquals(0, Pos('TriangleSet', JsonStr));

    RestoredWater := StringToComponent(JsonStr, RestoredOwner) as TCastleWaterVolume;
    AssertTrue(RestoredWater <> nil);
    AssertEquals(Ord(wbpFlowingRiver), Ord(RestoredWater.Preset));
    AssertSameValue(30.0, RestoredWater.SizeX, 1e-4);
    AssertSameValue(20.0, RestoredWater.SizeZ, 1e-4);
    AssertSameValue(Water.FlowSpeedX, RestoredWater.FlowSpeedX, 1e-4);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(Water);
  end;
end;

procedure TTestToolWaterStudio.TestFourPontoonBuoyancyEquilibriumRiverDriftAndPitchRollAlignment;
var
  DesignOwner: TComponent;
  Viewport: TCastleViewport;
  River, Swell: TCastleWaterVolume;
  SunkenCrate, DroppedCrate, SwellBoat: TCastleBox;
  B1, B2, BSwell: TCastleBuoyancyBehavior;
  StepIdx: Integer;
  Report: TWaterStudioAuditReport;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Viewport := TCastleViewport.Create(DesignOwner);
    Viewport.Name := 'MainViewport';

    River := TWaterStudioHelper.SpawnWaterVolume(
      Viewport, DesignOwner, wbpFlowingRiver, Vector3(0, 0, 0));
    AssertTrue(River <> nil);
    River.SizeX := 80.0;
    River.SizeZ := 30.0;
    River.FlowSpeedX := 3.2;

    SunkenCrate := TWaterStudioHelper.SpawnFloatingCrate(
      Viewport, DesignOwner, River, Vector3(-6.0, -1.1, 0.0));
    DroppedCrate := TWaterStudioHelper.SpawnFloatingCrate(
      Viewport, DesignOwner, River, Vector3(-6.0, 2.2, 4.0));
    AssertTrue(SunkenCrate <> nil);
    AssertTrue(DroppedCrate <> nil);

    B1 := SunkenCrate.FindBehavior(TCastleBuoyancyBehavior) as TCastleBuoyancyBehavior;
    B2 := DroppedCrate.FindBehavior(TCastleBuoyancyBehavior) as TCastleBuoyancyBehavior;
    AssertTrue(B1 <> nil);
    AssertTrue(B2 <> nil);

    { Step 60 frames (6.0 seconds total at 0.1s/step):
      1. SunkenCrate rises from -1.1m to surface equilibrium,
      2. DroppedCrate falls from +2.2m into water and settles near surface,
      3. Both drift downstream along +X due to FlowSpeedX = 3.2 m/s! }
    for StepIdx := 1 to 60 do
      TWaterStudioHelper.StepAllWaterAndBuoyancy(Viewport, DesignOwner, 0.1);

    AssertTrue(Abs(SunkenCrate.Translation.Y) < 0.65);
    AssertTrue(Abs(DroppedCrate.Translation.Y) < 0.65);
    AssertTrue(B1.SubmergedPontoonCount > 0);
    AssertTrue(B2.SubmergedPontoonCount > 0);
    AssertTrue(SunkenCrate.Translation.X > -1.0); // drifted > 5m downstream!
    AssertTrue(DroppedCrate.Translation.X > -2.5);

    { Verify pitch/roll alignment on a steep ocean swell }
    Swell := TWaterStudioHelper.SpawnWaterVolume(
      Viewport, DesignOwner, wbpStormyHighSeas, Vector3(0, 0, 60.0));
    Swell.WaveAmplitude := 1.4;
    Swell.WaveLength := 16.0;
    SwellBoat := TWaterStudioHelper.SpawnFloatingCrate(
      Viewport, DesignOwner, Swell, Vector3(2.3, 0.0, 60.0));
    BSwell := SwellBoat.FindBehavior(TCastleBuoyancyBehavior) as TCastleBuoyancyBehavior;
    AssertTrue(BSwell <> nil);
    for StepIdx := 1 to 25 do
    begin
      Swell.StepSimulation(0.08);
      BSwell.StepBuoyancy(0.08);
    end;
    AssertTrue((Abs(SwellBoat.Up.X) > 0.01) or (Abs(SwellBoat.Up.Z) > 0.01));
    AssertTrue(SwellBoat.Up.Y > 0.65);

    Report := TWaterStudioHelper.ScanDesign(Viewport, DesignOwner);
    try
      AssertEquals(2, Length(Report.WaterVolumes));
      AssertEquals(3, Length(Report.BuoyantHulls));
    finally
      FreeAndNil(Report);
    end;

    Md := TWaterStudioHelper.BuildMarkdownReport(Viewport, DesignOwner);
    AssertTrue(Pos('# Castle Gerstner Water & 4-Pontoon Buoyancy Studio Report', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolWaterStudio);
end.
