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

{ Hierarchy discovery, 1-click solar/sky/fog rig builder, 24-hour ephemeris
  schedule generator, and Markdown diagnostics for @link(TCastleTimeOfDayWeather)
  (Phase 299 — UE 6.0 SkyAtmosphere & Volumetric Weather Studio). }
unit ToolTimeOfDayStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils,
  CastleTransform, CastleScene, CastleUiControls, CastleViewport,
  CastleTimeOfDayWeather;

type
  TTimeOfDayControllerArray = array of TCastleTimeOfDayWeather;

  { Hierarchy scan & rig health summary for Time-of-Day & Weather Studio. }
  TTimeOfDayStudioSummary = record
    Controllers: TTimeOfDayControllerArray;
    DirectionalLightsCount: Integer;
    BackgroundsCount: Integer;
    FogsCount: Integer;
    ViewportsCount: Integer;
    FirstViewport: TCastleViewport;
    FirstDirectionalLight: TCastleDirectionalLight;
    FirstBackground: TCastleBackground;
    FirstFog: TCastleFog;
    Warnings: array of String;
  end;

  { Stateless editor helper for @link(TCastleTimeOfDayWeather) studios. }
  TTimeOfDayStudioHelper = class
  public
    { Discover all @link(TCastleTimeOfDayWeather) controllers, lights,
      backgrounds, fogs, and viewports in @code(ARoot). }
    class function ScanTimeOfDayControllers(
      const ARoot: TComponent): TTimeOfDayStudioSummary;

    { Ensure a complete Time-of-Day + SunLight + SkyBackground + AtmosphereFog
      rig exists in @code(ARoot), creating and wiring any missing components. }
    class function EnsureTimeOfDayRigInDesign(
      const ARoot, ADesignOwner: TComponent;
      const APreset: TWeatherPreset = wpClearSunny): TCastleTimeOfDayWeather;

    { Re-synchronize every @link(TCastleTimeOfDayWeather) controller in @code(ARoot). }
    class function SynchronizeAllControllers(const ARoot: TComponent): Integer;

    { Build a Markdown report including active controller state and a 24-hour
      key-hour ephemeris table (`00:00`, `06:00`, `09:00`, `12:00`, `15:00`, `18:00`, `21:00`). }
    class function BuildMarkdownReport(const ARoot: TComponent): String;
  end;

implementation

function ProposeUniqueTimeOfDayName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

function FindWorldItemsContainer(const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindWorldItemsContainer(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

{ TTimeOfDayStudioHelper ----------------------------------------------------- }

class function TTimeOfDayStudioHelper.ScanTimeOfDayControllers(
  const ARoot: TComponent): TTimeOfDayStudioSummary;
var
  OutSum: TTimeOfDayStudioSummary;
  Visited: TList;

  procedure AppendWarning(const Msg: String);
  var
    N: Integer;
  begin
    N := Length(OutSum.Warnings);
    SetLength(OutSum.Warnings, N + 1);
    OutSum.Warnings[N] := Msg;
  end;

  procedure AddController(const C: TCastleTimeOfDayWeather);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.Controllers) do
      if OutSum.Controllers[I] = C then
        Exit;
    SetLength(OutSum.Controllers, Length(OutSum.Controllers) + 1);
    OutSum.Controllers[High(OutSum.Controllers)] := C;
  end;

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if Visited.IndexOf(C) >= 0 then
      Exit;
    Visited.Add(C);

    if C is TCastleTimeOfDayWeather then
      AddController(TCastleTimeOfDayWeather(C));

    if C is TCastleDirectionalLight then
    begin
      Inc(OutSum.DirectionalLightsCount);
      if OutSum.FirstDirectionalLight = nil then
        OutSum.FirstDirectionalLight := TCastleDirectionalLight(C);
    end;

    if C is TCastleBackground then
    begin
      Inc(OutSum.BackgroundsCount);
      if OutSum.FirstBackground = nil then
        OutSum.FirstBackground := TCastleBackground(C);
    end;

    if C is TCastleFog then
    begin
      Inc(OutSum.FogsCount);
      if OutSum.FirstFog = nil then
        OutSum.FirstFog := TCastleFog(C);
    end;

    if C is TCastleViewport then
    begin
      VP := TCastleViewport(C);
      Inc(OutSum.ViewportsCount);
      if OutSum.FirstViewport = nil then
        OutSum.FirstViewport := VP;
      if VP.Background <> nil then
        Visit(VP.Background);
      if VP.Fog <> nil then
        Visit(VP.Fog);
      if VP.Items <> nil then
        Visit(VP.Items);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Visit(T[I]);
    end;

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;

    if C is TCastleComponent then
      for I := 0 to TCastleComponent(C).NonVisualComponentsCount - 1 do
        Visit(TCastleComponent(C).NonVisualComponents[I]);
  end;

var
  I: Integer;
  Ctrl: TCastleTimeOfDayWeather;
begin
  OutSum := Default(TTimeOfDayStudioSummary);
  if ARoot = nil then
  begin
    Result := OutSum;
    Exit;
  end;

  Visited := TList.Create;
  try
    Visit(ARoot);
  finally
    FreeAndNil(Visited);
  end;

  if Length(OutSum.Controllers) > 1 then
    AppendWarning(Format(
      '%d TCastleTimeOfDayWeather controllers exist in the design; a single master controller is recommended.',
      [Length(OutSum.Controllers)]));

  for I := 0 to High(OutSum.Controllers) do
  begin
    Ctrl := OutSum.Controllers[I];
    if Ctrl.SunLight = nil then
      AppendWarning(Format('Controller "%s" has no SunLight (TCastleDirectionalLight) assigned.',
        [Ctrl.Name]));
    if Ctrl.SkyBackground = nil then
      AppendWarning(Format('Controller "%s" has no SkyBackground (TCastleBackground) assigned.',
        [Ctrl.Name]));
    if Ctrl.AtmosphereFog = nil then
      AppendWarning(Format('Controller "%s" has no AtmosphereFog (TCastleFog) assigned.',
        [Ctrl.Name]));
  end;

  Result := OutSum;
end;

class function TTimeOfDayStudioHelper.EnsureTimeOfDayRigInDesign(
  const ARoot, ADesignOwner: TComponent;
  const APreset: TWeatherPreset): TCastleTimeOfDayWeather;
var
  Sum: TTimeOfDayStudioSummary;
  Container: TCastleTransform;
  OwnerToUse: TComponent;
  NonVisualHost: TCastleComponent;
  Sun: TCastleDirectionalLight;
  Sky: TCastleBackground;
  Fog: TCastleFog;
begin
  Result := nil;
  if ARoot = nil then
    Exit;

  Container := FindWorldItemsContainer(ARoot);
  if Container = nil then
    Exit;

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Sum := ScanTimeOfDayControllers(ARoot);

  if Sum.FirstViewport <> nil then
    NonVisualHost := Sum.FirstViewport
  else if ARoot is TCastleComponent then
    NonVisualHost := TCastleComponent(ARoot)
  else
    NonVisualHost := Container;

  { 1. Ensure SunLight }
  Sun := Sum.FirstDirectionalLight;
  if Sun = nil then
  begin
    Sun := TCastleDirectionalLight.Create(OwnerToUse);
    Sun.Name := ProposeUniqueTimeOfDayName(OwnerToUse, 'SunLight');
    Sun.Translation := Vector3(0.0, 14.0, 0.0);
    Sun.Shadows := true;
    Container.Add(Sun);
  end;

  { 2. Ensure SkyBackground }
  Sky := Sum.FirstBackground;
  if Sky = nil then
  begin
    Sky := TCastleBackground.Create(OwnerToUse);
    Sky.Name := ProposeUniqueTimeOfDayName(OwnerToUse, 'SkyBackground');
    Sky.SmoothEquator := 0.12;
    if NonVisualHost <> nil then
      NonVisualHost.AddNonVisualComponent(Sky);
  end;

  { 3. Ensure AtmosphereFog }
  Fog := Sum.FirstFog;
  if Fog = nil then
  begin
    Fog := TCastleFog.Create(OwnerToUse);
    Fog.Name := ProposeUniqueTimeOfDayName(OwnerToUse, 'AtmosphereFog');
    Fog.FogType := TCastleFog.DefaultFogType;
    if NonVisualHost <> nil then
      NonVisualHost.AddNonVisualComponent(Fog);
  end;

  { 4. Ensure Master TimeOfDayController }
  if Length(Sum.Controllers) > 0 then
    Result := Sum.Controllers[0]
  else
  begin
    Result := TCastleTimeOfDayWeather.Create(OwnerToUse);
    Result.Name := ProposeUniqueTimeOfDayName(OwnerToUse, 'TimeOfDayController');
    Result.Translation := Vector3(0.0, 2.0, 0.0);
    Container.Add(Result);
  end;

  if Result.SunLight = nil then
    Result.SunLight := Sun;
  if Result.SkyBackground = nil then
    Result.SkyBackground := Sky;
  if Result.AtmosphereFog = nil then
    Result.AtmosphereFog := Fog;
  if (Result.TargetViewport = nil) and (Sum.FirstViewport <> nil) then
    Result.TargetViewport := Sum.FirstViewport;

  Result.ApplyPresetWithRecommendedHour(APreset);
  Result.SynchronizeLinkedRig;
end;

class function TTimeOfDayStudioHelper.SynchronizeAllControllers(
  const ARoot: TComponent): Integer;
var
  Sum: TTimeOfDayStudioSummary;
  I: Integer;
begin
  Sum := ScanTimeOfDayControllers(ARoot);
  Result := Length(Sum.Controllers);
  for I := 0 to High(Sum.Controllers) do
    Sum.Controllers[I].SynchronizeLinkedRig;
end;

class function TTimeOfDayStudioHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
const
  KeyHours: array [0..6] of Single = (0.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0);
var
  Sum: TTimeOfDayStudioSummary;
  SB: TStringBuilder;
  I, K: Integer;
  C: TCastleTimeOfDayWeather;
  S: TTimeOfDayAtmosphereState;
begin
  Sum := ScanTimeOfDayControllers(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Dynamic Time-of-Day, Solar Ephemeris & Weather Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Time-of-Day Controllers**: `%d`', [Length(Sum.Controllers)]));
    SB.AppendLine(Format('- **Directional Lights**: `%d` | **Backgrounds**: `%d` | **Fogs**: `%d` | **Viewports**: `%d`',
      [Sum.DirectionalLightsCount, Sum.BackgroundsCount, Sum.FogsCount, Sum.ViewportsCount]));
    SB.AppendLine;

    for I := 0 to High(Sum.Controllers) do
    begin
      C := Sum.Controllers[I];
      S := C.CurrentAtmosphere;
      SB.AppendLine(Format('## Controller `%s` (%s @ `%s`)',
        [C.Name, TCastleTimeOfDayWeather.WeatherPresetDisplayName(C.WeatherPreset), C.FormatClockHHMM]));
      SB.AppendLine(Format('- **Latitude / Day of Year**: `%.1f deg` / Day `%d` | **Day Length**: `%.1f s`',
        [C.LatitudeDeg, C.DayOfYear, C.DayLengthRealSeconds]));
      SB.AppendLine(Format('- **Current Solar Elevation / Azimuth**: `%.1f deg` / `%.1f deg` (`LunarNight=%s`)',
        [S.SolarElevationDeg, S.SolarAzimuthDeg, BoolToStr(S.IsNightLunarMode, true)]));
      SB.AppendLine(Format('- **Clouds / Precip / Fog Vis / Wind**: `%.2f` / `%.2f` / `%.1f m` / `%.1f m/s @ %.0f deg`',
        [S.CloudCoverage, S.PrecipitationIntensity, S.FogVisibilityRange, S.WindSpeed, S.WindDirectionDeg]));
      SB.AppendLine;
      SB.AppendLine('| Clock | Solar Elev | Azimuth | Mode | Light Lux | Fog Vis (m) | Sky Zenith RGB |');
      SB.AppendLine('| :--- | ---: | ---: | :--- | ---: | ---: | :--- |');
      for K := 0 to High(KeyHours) do
      begin
        S := C.EvaluateAtmosphereAtHour(KeyHours[K]);
        SB.AppendLine(Format('| `%.2d:00` | `%.1f deg` | `%.1f deg` | %s | `%.2f` | `%.1f` | `(%.2f, %.2f, %.2f)` |',
          [Round(KeyHours[K]), S.SolarElevationDeg, S.SolarAzimuthDeg,
            BoolToStr(S.IsNightLunarMode, 'Lunar', 'Solar'),
           S.DirectLightIntensity, S.FogVisibilityRange,
           S.SkyTopColor.X, S.SkyTopColor.Y, S.SkyTopColor.Z]));
      end;
      SB.AppendLine;
    end;

    if Length(Sum.Warnings) > 0 then
    begin
      SB.AppendLine('## Environment Warnings');
      for I := 0 to High(Sum.Warnings) do
        SB.AppendLine('- [!] ' + Sum.Warnings[I]);
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
