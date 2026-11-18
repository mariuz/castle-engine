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

{ Automated tests for Phase 372 Niagara Grid2D Cellular Fire Spread & Ash Studio. }
unit TestToolFireGrid2D;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolFireGrid2D = class(TCastleTestCase)
  published
    procedure TestDownwindFlameFrontAccelerationCharredBurnoutAndStoneFirebreakContainment;
    procedure TestHeavyMonsoonRainExtinguishDouseSplashAndTransientCleanJsonRoundtrip;
  end;

implementation

uses Math, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleFireGrid2D, ToolFireGrid2D;

procedure TTestToolFireGrid2D.TestDownwindFlameFrontAccelerationCharredBurnoutAndStoneFirebreakContainment;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Grid: TCastleFireSpreadGrid;
  StepIdx, IX, IZ, EastBurned, WestBurned, BeyondTrenchBurned: Integer;
  C: TFireGridCell;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TFireGrid2DHelper.SpawnPrairieFireGridDemo(Vp, RootOwner, Grid));

    Grid.ResetFuelGrid;
    Grid.WindDirectionDeg := 0.0; { Strong +X Eastward wind }
    Grid.WindSpeedMps := 10.0;
    AssertTrue(Grid.IgniteCell(6, 8));

    for StepIdx := 1 to 22 do
      Grid.StepCombustion(0.25);

    { 1. Origin cell (6,8) has consumed its fuel and transitioned to fcsCharredAsh }
    AssertTrue('Origin ignition cell must burn out to charred ash',
      Grid.GetCell(6, 8).State = fcsCharredAsh);

    { 2. Downwind East (+X, IX > 6) burned+burning area must exceed upwind West (-X, IX < 6) by > 2x }
    EastBurned := 0;
    WestBurned := 0;
    for IZ := 0 to Grid.GridResolution - 1 do
      for IX := 0 to Grid.GridResolution - 1 do
      begin
        C := Grid.GetCell(IX, IZ);
        if C.State in [fcsBurningActive, fcsCharredAsh] then
        begin
          if IX > 6 then Inc(EastBurned)
          else if IX < 6 then Inc(WestBurned);
        end;
      end;
    AssertTrue('Downwind +X firefront must burn > 2x more cells than upwind -X',
      EastBurned > Max(2, WestBurned * 2));

    { 3. Non-flammable stone trench at column IX = 9 completely blocks +X firefront from reaching IX >= 10! }
    Grid.Preset := fgpStoneFirebreakTrench;
    for StepIdx := 1 to 32 do
      Grid.StepCombustion(0.25);

    BeyondTrenchBurned := 0;
    for IZ := 0 to Grid.GridResolution - 1 do
      for IX := 10 to Grid.GridResolution - 1 do
        if Grid.GetCell(IX, IZ).State in [fcsBurningActive, fcsCharredAsh] then
          Inc(BeyondTrenchBurned);
    AssertEquals('Stone firebreak trench at IX=9 must block 100% of downwind flames', 0, BeyondTrenchBurned);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolFireGrid2D.TestHeavyMonsoonRainExtinguishDouseSplashAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Grid, Restored: TCastleFireSpreadGrid;
  X, Z, I: Integer;
  St: TFireGridStats;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Grid := TCastleFireSpreadGrid.Create(RootOwner);
    Grid.Name := 'MeadowFire';
    Grid.ResetFuelGrid;
    for Z := 6 to 8 do
      for X := 6 to 8 do
        Grid.IgniteCell(X, Z);
    AssertEquals(9, Grid.Stats.BurningCells);

    { Direct water splash douses center 3x3 immediately }
    Grid.DouseWaterSplash(7, 7, 0);
    AssertEquals(8, Grid.Stats.BurningCells);

    { Full monsoon rain extinguishes all remaining flames while preserving unburned meadow fuel }
    Grid.RainIntensity := 1.0;
    for I := 1 to 10 do
      St := Grid.StepCombustion(0.25);
    AssertEquals('Monsoon downpour must extinguish all active flames', 0, St.BurningCells);
    AssertTrue(St.UnburnedFuelCells > 240);

    ReportMd := TFireGrid2DHelper.GenerateFireGridReport(Grid);
    AssertTrue(Pos('Grid2D Cellular Fire Spread', ReportMd) > 0);

    JsonStr := ComponentToString(Grid);
    AssertEquals(0, Pos('TransientFireGridMesh', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleFireSpreadGrid;
    AssertSameValue(1.0, Restored.RainIntensity, 0.001);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolFireGrid2D);
end.
