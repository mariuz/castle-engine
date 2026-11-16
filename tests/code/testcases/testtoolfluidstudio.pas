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

{ Automated unit tests for Phase 330 2.5D Shallow-Water Virtual-Pipe Fluid
  Simulation, Mass Conservation, Waterfall Foam & Terrain WorldRay Baking Studio
  (@link(CastleShallowFluid), @link(ToolFluidStudio)). }
unit TestToolFluidStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolFluidStudio = class(TCastleTestCase)
  published
    procedure TestDamBreakExactVolumeMassConservationDownhillPoolingFoamAndWetness;
    procedure TestSpringInflowWorldRayTerrainBedBakeAndCleanJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTransform, CastleViewport, CastleScene, CastleComponentSerialize,
  CastleShallowFluid, ToolFluidStudio;

procedure TTestToolFluidStudio.TestDamBreakExactVolumeMassConservationDownhillPoolingFoamAndWetness;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Fluid: TCastleShallowFluidSurface;
  VolBefore, VolAfter, LowerBasinWaterSum: Double;
  PeakFoamDuringRun: Single;
  I, IX, IZ: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Fluid := TFluidStudioHelper.SpawnShallowFluidDemo(
      Vp, DesignOwner, sfpCraterLakeDamBreak);
    AssertTrue(Fluid <> nil);
    Fluid.ClearSprings;
    Fluid.RainRateMps := 0.0;
    Fluid.EvaporationRateMps := 0.0;

    VolBefore := Fluid.TotalWaterVolumeM3;
    AssertTrue(VolBefore > 50.0);

    { Initially the lower East basin (IX >= 20) is completely dry (0.0m) }
    AssertSameValue(0.0, Fluid.GetCellSample(24, 16).WaterDepth, 1e-5);

    PeakFoamDuringRun := 0.0;
    for I := 1 to 60 do
    begin
      Fluid.StepFluid(0.05);
      PeakFoamDuringRun := Max(PeakFoamDuringRun, Fluid.MaxFoamFactor);
    end;

    VolAfter := Fluid.TotalWaterVolumeM3;

    { 1. Virtual-Pipe Hydrostatic solver preserves exact water volume (<0.1% FP drift) }
    AssertSameValue(VolBefore, VolAfter, VolBefore * 0.001);

    { 2. Water surged downhill into the previously dry East basin (IX >= 20) }
    LowerBasinWaterSum := 0.0;
    for IZ := 2 to Fluid.GridResZ - 3 do
      for IX := 20 to Fluid.GridResX - 3 do
        LowerBasinWaterSum := LowerBasinWaterSum + Fluid.GetCellSample(IX, IZ).WaterDepth;
    AssertTrue(LowerBasinWaterSum > 15.0);

    { 3. Turbulent dam-break surge generated whitewater foam & shoreline wetness }
    AssertTrue(PeakFoamDuringRun > 0.05);
    AssertTrue(Fluid.GetCellSample(16, 16).Wetness > 0.50);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolFluidStudio.TestSpringInflowWorldRayTerrainBedBakeAndCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  TerraceBox: TCastleBox;
  Fluid, RestoredFluid: TCastleShallowFluidSurface;
  Vol0, Vol1: Double;
  SavedJson, Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);

    { Place a 4.0m-tall raised rock platform under the center of the viewport }
    TerraceBox := TCastleBox.Create(DesignOwner);
    TerraceBox.Name := 'RockTerraceCollider';
    TerraceBox.Size := Vector3(8.0, 4.0, 8.0);
    TerraceBox.Translation := Vector3(0.0, 2.0, 0.0); // Top surface at Y = 4.0m!
    Vp.Items.Add(TerraceBox);

    Fluid := TFluidStudioHelper.SpawnShallowFluidDemo(
      Vp, DesignOwner, sfpTerracedWaterfallPools);
    Fluid.ClearAllWaterAndFluxes;
    Fluid.ClearSprings;

    { 1. Bake terrain bed directly from WorldRay against TerraceBox -> center cell BedH = 4.0m! }
    Fluid.BakeTerrainBedFromWorld(20.0);
    AssertSameValue(4.0, Fluid.GetCellSample(Fluid.GridResX div 2, Fluid.GridResZ div 2).TerrainHeight, 0.05);

    { 2. Add a +3.0 m^3/s gushing spring and step 1.0s -> volume increases by exactly +3.0 m^3! }
    Fluid.AddSpringSource(0.0, 0.0, 3.0, 2.0, True);
    Vol0 := Fluid.TotalWaterVolumeM3;
    Fluid.StepFluid(0.50);
    Fluid.StepFluid(0.50);
    Vol1 := Fluid.TotalWaterVolumeM3;
    AssertSameValue(Vol0 + 3.0, Vol1, 0.05);

    { 3. Verify csTransient-clean JSON serialization roundtrip }
    SavedJson := ComponentToString(Fluid);
    AssertEquals(0, Pos('TriangleSet', SavedJson));
    RestoredOwner := TComponent.Create(nil);
    try
      RestoredFluid := StringToComponent(SavedJson, RestoredOwner) as TCastleShallowFluidSurface;
      AssertEquals(1, RestoredFluid.SpringCount);
      AssertSameValue(3.0, RestoredFluid.GetSpring(0).FlowRateM3PerSec, 1e-4);
    finally
      FreeAndNil(RestoredOwner);
    end;

    Md := TFluidStudioHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('2.5D Shallow-Water Fluid & Waterfall Report', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolFluidStudio);
end.
