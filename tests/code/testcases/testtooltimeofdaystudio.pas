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

{ Automated unit tests for Phase 299 Dynamic Time-of-Day Solar Ephemeris,
  Sky/Atmosphere & Weather Controller Studio (@link(TCastleTimeOfDayWeather) and
  @link(TTimeOfDayStudioHelper)). }
unit TestToolTimeOfDayStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolTimeOfDayStudio = class(TCastleTestCase)
  published
    procedure TestSolarEphemerisRigSyncDayCycleWraparoundAndJsonRoundtrip;
    procedure TestWeatherPresetsFogCloudAttenuationBloodMoonAndDiagnostics;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleComponentSerialize,
  CastleUiControls, CastleViewport, CastleTransform, CastleScene,
  EditorRegisterAllComponents,
  CastleTimeOfDayWeather, ToolTimeOfDayStudio;

procedure TTestToolTimeOfDayStudio.TestSolarEphemerisRigSyncDayCycleWraparoundAndJsonRoundtrip;
var
  DesignOwner, LoadedOwner: TComponent;
  RootUi, LoadedRoot: TCastleUserInterface;
  Vp: TCastleViewport;
  Ctrl, LoadedCtrl: TCastleTimeOfDayWeather;
  SNoon, SMorning, SDusk, SMidnight: TTimeOfDayAtmosphereState;
  JsonStr: String;
  Sum: TTimeOfDayStudioSummary;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootUi';

    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';
    RootUi.InsertFront(Vp);

    Ctrl := TTimeOfDayStudioHelper.EnsureTimeOfDayRigInDesign(
      RootUi, DesignOwner, wpClearSunny);
    AssertTrue(Ctrl <> nil);
    AssertTrue(Ctrl.SunLight <> nil);
    AssertTrue(Ctrl.SkyBackground <> nil);
    AssertTrue(Ctrl.AtmosphereFog <> nil);
    AssertTrue(Ctrl.TargetViewport = Vp);
    AssertTrue(Vp.Background = Ctrl.SkyBackground);
    AssertTrue(Vp.Fog = Ctrl.AtmosphereFog);

    Sum := TTimeOfDayStudioHelper.ScanTimeOfDayControllers(RootUi);
    AssertEquals(1, Length(Sum.Controllers));
    AssertEquals(0, Length(Sum.Warnings));

    { 1. Solar Noon on Summer Solstice (Day 172, Lat 35N -> Elev = 90 - (35 - 23.44) = 78.44 deg, Az = 180 South) }
    Ctrl.LatitudeDeg := 35.0;
    Ctrl.DayOfYear := 172;
    Ctrl.TimeOfDayHours := 12.0;
    SNoon := Ctrl.CurrentAtmosphere;
    AssertSameValue(78.44, SNoon.SolarElevationDeg, 0.25);
    AssertSameValue(180.0, SNoon.SolarAzimuthDeg, 0.5);
    AssertFalse(SNoon.IsNightLunarMode);
    AssertTrue(Ctrl.SunLight.Intensity > 2.0);
    AssertTrue(Ctrl.SunLight.Direction.Y < -0.95);
    AssertTrue(Ctrl.SkyBackground.SkyTopColor.Z > Ctrl.SkyBackground.SkyTopColor.X);

    { 2. Morning (06:00 -> East) & Golden Dusk (18:30 -> West warm horizon) }
    SMorning := Ctrl.EvaluateAtmosphereAtHour(6.0);
    AssertTrue(SMorning.SolarAzimuthDeg < 105.0);
    AssertTrue(SMorning.SolarElevationDeg > 8.0);

    Ctrl.TimeOfDayHours := 18.75;
    SDusk := Ctrl.CurrentAtmosphere;
    AssertTrue(SDusk.SolarAzimuthDeg > 255.0);
    AssertTrue(Ctrl.SkyBackground.SkyEquatorColor.X > Ctrl.SkyBackground.SkyEquatorColor.Z);

    { 3. Midnight (00:00 -> Lunar Night Mode) }
    Ctrl.TimeOfDayHours := 0.0;
    SMidnight := Ctrl.CurrentAtmosphere;
    AssertTrue(SMidnight.SolarElevationDeg < -30.0);
    AssertTrue(SMidnight.IsNightLunarMode);
    AssertTrue(Ctrl.SunLight.Intensity < 0.25);

    { 4. 24-hour cycle wraparound (23.5h + 1.0h -> 0.5h) }
    Ctrl.DayLengthRealSeconds := 240.0; // 10 real seconds = 1 game hour
    Ctrl.TimeOfDayHours := 23.5;
    Ctrl.AdvanceTimeSeconds(10.0);
    AssertSameValue(0.5, Ctrl.TimeOfDayHours, 0.01);
    AssertEquals('00:30', Ctrl.FormatClockHHMM);

    { 5. JSON serialization roundtrip preserves rig links and parameters }
    Ctrl.ApplyPresetWithRecommendedHour(wpGoldenDusk);
    JsonStr := ComponentToString(RootUi);

    LoadedOwner := TComponent.Create(nil);
    try
      LoadedRoot := StringToComponent(JsonStr, LoadedOwner) as TCastleUserInterface;
      try
        LoadedCtrl := LoadedOwner.FindComponent(Ctrl.Name) as TCastleTimeOfDayWeather;
        AssertTrue(LoadedCtrl <> nil);
        AssertTrue(LoadedCtrl.WeatherPreset = wpGoldenDusk);
        AssertSameValue(18.5, LoadedCtrl.TimeOfDayHours, 0.01);
        AssertTrue(LoadedCtrl.SunLight <> nil);
        AssertTrue(LoadedCtrl.SkyBackground <> nil);
        AssertTrue(LoadedCtrl.AtmosphereFog <> nil);
      finally
        FreeAndNil(LoadedRoot);
      end;
    finally
      FreeAndNil(LoadedOwner);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolTimeOfDayStudio.TestWeatherPresetsFogCloudAttenuationBloodMoonAndDiagnostics;
var
  DesignOwner: TComponent;
  World: TCastleRootTransform;
  Ctrl, Unlinked: TCastleTimeOfDayWeather;
  ClearLux, ClearFogRange, StormLux, StormFogRange: Single;
  Sum: TTimeOfDayStudioSummary;
  Report: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    World := TCastleRootTransform.Create(DesignOwner);
    World.Name := 'WorldRoot';

    Ctrl := TTimeOfDayStudioHelper.EnsureTimeOfDayRigInDesign(
      World, DesignOwner, wpClearSunny);
    Ctrl.TimeOfDayHours := 12.0;
    ClearLux := Ctrl.SunLight.Intensity;
    ClearFogRange := Ctrl.AtmosphereFog.VisibilityRange;
    AssertTrue(ClearLux > 2.0);
    AssertTrue(ClearFogRange > 400.0);

    { Switch to Rain Storm at Noon: heavy cloud attenuation + dense fog + 14 m/s wind }
    Ctrl.WeatherPreset := wpRainStorm;
    StormLux := Ctrl.SunLight.Intensity;
    StormFogRange := Ctrl.AtmosphereFog.VisibilityRange;
    AssertTrue(Ctrl.CloudCoverage > 0.90);
    AssertTrue(Ctrl.PrecipitationIntensity > 0.80);
    AssertTrue(StormLux < ClearLux * 0.30);
    AssertTrue(StormFogRange < 60.0);
    AssertSameValue(14.0, Ctrl.CurrentAtmosphere.WindVelocityWorld.Length, 0.05);

    { Blood Moon preset at 00:30: crimson lunar direct light }
    Ctrl.ApplyPresetWithRecommendedHour(wpBloodMoon);
    AssertTrue(Ctrl.CurrentAtmosphere.IsNightLunarMode);
    AssertTrue(Ctrl.SunLight.Color.X > 0.85);
    AssertTrue(Ctrl.SunLight.Color.X > Ctrl.SunLight.Color.Z * 4.0);

    { Unlinked controller triggers diagnostic warnings }
    Unlinked := TCastleTimeOfDayWeather.Create(DesignOwner);
    Unlinked.Name := 'UnlinkedController';
    World.Add(Unlinked);

    Sum := TTimeOfDayStudioHelper.ScanTimeOfDayControllers(World);
    AssertEquals(2, Length(Sum.Controllers));
    AssertTrue(Length(Sum.Warnings) >= 3);

    Report := TTimeOfDayStudioHelper.BuildMarkdownReport(World);
    AssertTrue(Pos('Blood Moon', Report) > 0);
    AssertTrue(Pos('12:00', Report) > 0);
    AssertTrue(Pos('Environment Warnings', Report) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolTimeOfDayStudio);
end.
