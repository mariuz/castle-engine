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

{ Dynamic 24-hour solar/lunar ephemeris, sky-dome & exponential fog
  synchronizer, wind vector field, and volumetric weather preset controller
  (@link(TCastleTimeOfDayWeather))
  (Phase 299 — UE 6.0 SkyAtmosphere & Volumetric Weather Parity). }
unit CastleTimeOfDayWeather;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, CastleViewport, X3DNodes;

type
  { Built-in 1-click atmospheric & weather condition presets. }
  TWeatherPreset = (
    wpCustom,
    wpClearSunny,
    wpGoldenDusk,
    wpOvercastFog,
    wpRainStorm,
    wpBlizzardSnow,
    wpBloodMoon
  );

  { Evaluated 24-hour ephemeris, lighting, sky-dome, fog, and weather state. }
  TTimeOfDayAtmosphereState = record
    TimeOfDayHours: Single;
    SolarElevationDeg: Single;
    SolarAzimuthDeg: Single;
    SunPositionOnDome: TVector3;
    ActiveLightDirection: TVector3;
    IsNightLunarMode: Boolean;
    DirectLightColor: TCastleColorRGB;
    DirectLightIntensity: Single;
    SkyTopColor: TCastleColorRGB;
    SkyEquatorColor: TCastleColorRGB;
    GroundEquatorColor: TCastleColorRGB;
    GroundBottomColor: TCastleColorRGB;
    FogColor: TCastleColorRGB;
    FogVisibilityRange: Single;
    CloudCoverage: Single;
    PrecipitationIntensity: Single;
    WindDirectionDeg: Single;
    WindSpeed: Single;
    WindVelocityWorld: TVector3;
  end;

  { Master 24-hour Time-of-Day & Weather controller synchronizing solar/lunar
    angles, @link(TCastleDirectionalLight), @link(TCastleBackground),
    @link(TCastleFog), and optional @link(TCastleViewport) environment slots. }
  TCastleTimeOfDayWeather = class(TCastleTransform)
  strict private
    FWeatherPreset: TWeatherPreset;
    FTimeOfDayHours: Single;
    FLatitudeDeg: Single;
    FDayOfYear: Integer;
    FDayLengthRealSeconds: Single;
    FAutoAdvanceInRuntime: Boolean;
    FAutoSyncRig: Boolean;
    FShowSolarCompassInViewport: Boolean;

    FCloudCoverage: Single;
    FPrecipitationIntensity: Single;
    FFogDensityMultiplier: Single;
    FWindDirectionDeg: Single;
    FWindSpeed: Single;

    FSunLight: TCastleDirectionalLight;
    FSkyBackground: TCastleBackground;
    FAtmosphereFog: TCastleFog;
    FTargetViewport: TCastleViewport;

    FLoadingPreset: Boolean;

    class function NormalizeHour24(const AHour: Single): Single; static;
    class function LerpRgb(const A, B: TCastleColorRGB; const T: Single): TCastleColorRGB; static;
    class function SmoothStep01(const T: Single): Single; static;

    procedure SetWeatherPreset(const Value: TWeatherPreset);
    procedure SetTimeOfDayHours(const Value: Single);
    procedure SetLatitudeDeg(const Value: Single);
    procedure SetDayOfYear(const Value: Integer);
    procedure SetDayLengthRealSeconds(const Value: Single);
    procedure SetCloudCoverage(const Value: Single);
    procedure SetPrecipitationIntensity(const Value: Single);
    procedure SetFogDensityMultiplier(const Value: Single);
    procedure SetWindDirectionDeg(const Value: Single);
    procedure SetWindSpeed(const Value: Single);

    procedure SetSunLight(const Value: TCastleDirectionalLight);
    procedure SetSkyBackground(const Value: TCastleBackground);
    procedure SetAtmosphereFog(const Value: TCastleFog);
    procedure SetTargetViewport(const Value: TCastleViewport);

    procedure MaybeAutoSync;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    const
      DefaultTimeOfDayHours = 10.5;
      DefaultLatitudeDeg = 35.0;
      DefaultDayOfYear = 172;
      DefaultDayLengthRealSeconds = 600.0;
      DefaultCloudCoverage = 0.12;
      DefaultPrecipitationIntensity = 0.0;
      DefaultFogDensityMultiplier = 1.0;
      DefaultWindDirectionDeg = 45.0;
      DefaultWindSpeed = 2.5;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    class function WeatherPresetDisplayName(const APreset: TWeatherPreset): String; static;

    { Deterministically evaluate solar ephemeris, sky dome colors, directional
      sun/moon light, fog range, and wind vector at any hour @code([0..24)). }
    function EvaluateAtmosphereAtHour(const AHour: Single): TTimeOfDayAtmosphereState;

    { Evaluate atmosphere state at the current @link(TimeOfDayHours). }
    function CurrentAtmosphere: TTimeOfDayAtmosphereState;

    { Apply a weather preset AND set @link(TimeOfDayHours) to its signature
      showcase hour (e.g. @code(18.25h) for Golden Dusk, @code(0.5h) for Blood Moon). }
    procedure ApplyPresetWithRecommendedHour(const APreset: TWeatherPreset);

    { Advance @link(TimeOfDayHours) according to @link(DayLengthRealSeconds)
      with clean 24-hour modulo wraparound and synchronize linked environment nodes. }
    procedure AdvanceTimeSeconds(const ARealSeconds: Single);

    { Push current @link(CurrentAtmosphere) values into @link(SunLight),
      @link(SkyBackground), @link(AtmosphereFog), and @link(TargetViewport). }
    procedure SynchronizeLinkedRig;

    { Formatted @code(HH:MM) 24-hour clock string for UI and Hierarchy badges. }
    function FormatClockHHMM: String;

    { Compact Hierarchy Tree badge, e.g. @code([ToD:10:30 Clear Sunny Elev=65deg]). }
    function TimeOfDaySummaryBadge: String;
  published
    property WeatherPreset: TWeatherPreset
      read FWeatherPreset write SetWeatherPreset default wpClearSunny;
    property TimeOfDayHours: Single
      read FTimeOfDayHours write SetTimeOfDayHours {$ifdef FPC}default DefaultTimeOfDayHours{$endif};
    property LatitudeDeg: Single
      read FLatitudeDeg write SetLatitudeDeg {$ifdef FPC}default DefaultLatitudeDeg{$endif};
    property DayOfYear: Integer
      read FDayOfYear write SetDayOfYear default DefaultDayOfYear;
    property DayLengthRealSeconds: Single
      read FDayLengthRealSeconds write SetDayLengthRealSeconds {$ifdef FPC}default DefaultDayLengthRealSeconds{$endif};
    property AutoAdvanceInRuntime: Boolean
      read FAutoAdvanceInRuntime write FAutoAdvanceInRuntime default false;
    property AutoSyncRig: Boolean
      read FAutoSyncRig write FAutoSyncRig default true;
    property ShowSolarCompassInViewport: Boolean
      read FShowSolarCompassInViewport write FShowSolarCompassInViewport default true;

    property CloudCoverage: Single
      read FCloudCoverage write SetCloudCoverage {$ifdef FPC}default DefaultCloudCoverage{$endif};
    property PrecipitationIntensity: Single
      read FPrecipitationIntensity write SetPrecipitationIntensity {$ifdef FPC}default DefaultPrecipitationIntensity{$endif};
    property FogDensityMultiplier: Single
      read FFogDensityMultiplier write SetFogDensityMultiplier {$ifdef FPC}default DefaultFogDensityMultiplier{$endif};
    property WindDirectionDeg: Single
      read FWindDirectionDeg write SetWindDirectionDeg {$ifdef FPC}default DefaultWindDirectionDeg{$endif};
    property WindSpeed: Single
      read FWindSpeed write SetWindSpeed {$ifdef FPC}default DefaultWindSpeed{$endif};

    property SunLight: TCastleDirectionalLight read FSunLight write SetSunLight;
    property SkyBackground: TCastleBackground read FSkyBackground write SetSkyBackground;
    property AtmosphereFog: TCastleFog read FAtmosphereFog write SetAtmosphereFog;
    property TargetViewport: TCastleViewport read FTargetViewport write SetTargetViewport;
  end;

implementation

uses
  CastleComponentSerialize, CastleApplicationProperties;

{ TCastleTimeOfDayWeather ---------------------------------------------------- }

constructor TCastleTimeOfDayWeather.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWeatherPreset := wpClearSunny;
  FTimeOfDayHours := DefaultTimeOfDayHours;
  FLatitudeDeg := DefaultLatitudeDeg;
  FDayOfYear := DefaultDayOfYear;
  FDayLengthRealSeconds := DefaultDayLengthRealSeconds;
  FAutoAdvanceInRuntime := false;
  FAutoSyncRig := true;
  FShowSolarCompassInViewport := true;

  FCloudCoverage := DefaultCloudCoverage;
  FPrecipitationIntensity := DefaultPrecipitationIntensity;
  FFogDensityMultiplier := DefaultFogDensityMultiplier;
  FWindDirectionDeg := DefaultWindDirectionDeg;
  FWindSpeed := DefaultWindSpeed;
end;

destructor TCastleTimeOfDayWeather.Destroy;
begin
  SetSunLight(nil);
  SetSkyBackground(nil);
  SetAtmosphereFog(nil);
  SetTargetViewport(nil);
  inherited;
end;

function TCastleTimeOfDayWeather.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'WeatherPreset', 'TimeOfDayHours', 'LatitudeDeg', 'DayOfYear',
       'DayLengthRealSeconds', 'AutoAdvanceInRuntime', 'AutoSyncRig',
       'ShowSolarCompassInViewport', 'CloudCoverage', 'PrecipitationIntensity',
       'FogDensityMultiplier', 'WindDirectionDeg', 'WindSpeed',
       'SunLight', 'SkyBackground', 'AtmosphereFog', 'TargetViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleTimeOfDayWeather.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FSunLight then
      FSunLight := nil;
    if AComponent = FSkyBackground then
      FSkyBackground := nil;
    if AComponent = FAtmosphereFog then
      FAtmosphereFog := nil;
    if AComponent = FTargetViewport then
      FTargetViewport := nil;
  end;
end;

procedure TCastleTimeOfDayWeather.Loaded;
begin
  inherited;
  if FAutoSyncRig then
    SynchronizeLinkedRig;
end;

class function TCastleTimeOfDayWeather.NormalizeHour24(const AHour: Single): Single;
begin
  Result := Frac(AHour / 24.0) * 24.0;
  if Result < 0.0 then
    Result := Result + 24.0;
end;

class function TCastleTimeOfDayWeather.LerpRgb(
  const A, B: TCastleColorRGB; const T: Single): TCastleColorRGB;
var
  C: Single;
begin
  C := Clamped(T, 0.0, 1.0);
  Result := Vector3(
    A.X + (B.X - A.X) * C,
    A.Y + (B.Y - A.Y) * C,
    A.Z + (B.Z - A.Z) * C
  );
end;

class function TCastleTimeOfDayWeather.SmoothStep01(const T: Single): Single;
var
  C: Single;
begin
  C := Clamped(T, 0.0, 1.0);
  Result := C * C * (3.0 - 2.0 * C);
end;

class function TCastleTimeOfDayWeather.WeatherPresetDisplayName(
  const APreset: TWeatherPreset): String;
begin
  case APreset of
    wpCustom: Result := 'Custom';
    wpClearSunny: Result := 'Clear Sunny';
    wpGoldenDusk: Result := 'Golden Dusk';
    wpOvercastFog: Result := 'Overcast Fog';
    wpRainStorm: Result := 'Rain Storm';
    wpBlizzardSnow: Result := 'Blizzard Snow';
    wpBloodMoon: Result := 'Blood Moon';
  end;
end;

procedure TCastleTimeOfDayWeather.MaybeAutoSync;
begin
  if FAutoSyncRig and (not (csLoading in ComponentState)) then
    SynchronizeLinkedRig;
end;

procedure TCastleTimeOfDayWeather.SetWeatherPreset(const Value: TWeatherPreset);
begin
  if FWeatherPreset = Value then
    Exit;
  FWeatherPreset := Value;
  if (not (csLoading in ComponentState)) and (Value <> wpCustom) then
  begin
    FLoadingPreset := true;
    try
      case Value of
        wpClearSunny:
          begin
            FCloudCoverage := 0.12;
            FPrecipitationIntensity := 0.0;
            FFogDensityMultiplier := 1.0;
            FWindDirectionDeg := 45.0;
            FWindSpeed := 2.5;
          end;
        wpGoldenDusk:
          begin
            FCloudCoverage := 0.28;
            FPrecipitationIntensity := 0.0;
            FFogDensityMultiplier := 1.45;
            FWindDirectionDeg := 250.0;
            FWindSpeed := 3.2;
          end;
        wpOvercastFog:
          begin
            FCloudCoverage := 0.85;
            FPrecipitationIntensity := 0.05;
            FFogDensityMultiplier := 4.2;
            FWindDirectionDeg := 110.0;
            FWindSpeed := 4.5;
          end;
        wpRainStorm:
          begin
            FCloudCoverage := 0.94;
            FPrecipitationIntensity := 0.88;
            FFogDensityMultiplier := 6.5;
            FWindDirectionDeg := 215.0;
            FWindSpeed := 14.0;
          end;
        wpBlizzardSnow:
          begin
            FCloudCoverage := 0.96;
            FPrecipitationIntensity := 0.95;
            FFogDensityMultiplier := 8.5;
            FWindDirectionDeg := 335.0;
            FWindSpeed := 18.5;
          end;
        wpBloodMoon:
          begin
            FCloudCoverage := 0.35;
            FPrecipitationIntensity := 0.0;
            FFogDensityMultiplier := 2.2;
            FWindDirectionDeg := 170.0;
            FWindSpeed := 5.0;
          end;
      end;
    finally
      FLoadingPreset := false;
    end;
  end;
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.ApplyPresetWithRecommendedHour(
  const APreset: TWeatherPreset);
begin
  SetWeatherPreset(APreset);
  case APreset of
    wpClearSunny: SetTimeOfDayHours(11.5);
    wpGoldenDusk: SetTimeOfDayHours(18.5);
    wpOvercastFog: SetTimeOfDayHours(9.0);
    wpRainStorm: SetTimeOfDayHours(15.0);
    wpBlizzardSnow: SetTimeOfDayHours(16.25);
    wpBloodMoon: SetTimeOfDayHours(0.5);
  else
    SynchronizeLinkedRig;
  end;
end;

procedure TCastleTimeOfDayWeather.SetTimeOfDayHours(const Value: Single);
var
  ClampedVal: Single;
begin
  ClampedVal := NormalizeHour24(Value);
  if SameValue(FTimeOfDayHours, ClampedVal, 1e-5) then
    Exit;
  FTimeOfDayHours := ClampedVal;
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetLatitudeDeg(const Value: Single);
var
  C: Single;
begin
  C := Clamped(Value, -89.5, 89.5);
  if SameValue(FLatitudeDeg, C, 1e-4) then
    Exit;
  FLatitudeDeg := C;
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetDayOfYear(const Value: Integer);
var
  C: Integer;
begin
  C := Clamped(Value, 1, 365);
  if FDayOfYear = C then
    Exit;
  FDayOfYear := C;
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetDayLengthRealSeconds(const Value: Single);
begin
  FDayLengthRealSeconds := Max(1.0, Value);
end;

procedure TCastleTimeOfDayWeather.SetCloudCoverage(const Value: Single);
var
  C: Single;
begin
  C := Clamped(Value, 0.0, 1.0);
  if SameValue(FCloudCoverage, C, 1e-4) then
    Exit;
  FCloudCoverage := C;
  if (not FLoadingPreset) and (not (csLoading in ComponentState)) then
    FWeatherPreset := wpCustom;
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetPrecipitationIntensity(const Value: Single);
var
  C: Single;
begin
  C := Clamped(Value, 0.0, 1.0);
  if SameValue(FPrecipitationIntensity, C, 1e-4) then
    Exit;
  FPrecipitationIntensity := C;
  if (not FLoadingPreset) and (not (csLoading in ComponentState)) then
    FWeatherPreset := wpCustom;
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetFogDensityMultiplier(const Value: Single);
var
  C: Single;
begin
  C := Clamped(Value, 0.1, 20.0);
  if SameValue(FFogDensityMultiplier, C, 1e-4) then
    Exit;
  FFogDensityMultiplier := C;
  if (not FLoadingPreset) and (not (csLoading in ComponentState)) then
    FWeatherPreset := wpCustom;
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetWindDirectionDeg(const Value: Single);
var
  C: Single;
begin
  C := Frac(Value / 360.0) * 360.0;
  if C < 0.0 then
    C := C + 360.0;
  if SameValue(FWindDirectionDeg, C, 1e-4) then
    Exit;
  FWindDirectionDeg := C;
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetWindSpeed(const Value: Single);
var
  C: Single;
begin
  C := Max(0.0, Value);
  if SameValue(FWindSpeed, C, 1e-4) then
    Exit;
  FWindSpeed := C;
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetSunLight(const Value: TCastleDirectionalLight);
begin
  if FSunLight = Value then
    Exit;
  if FSunLight <> nil then
    FSunLight.RemoveFreeNotification(Self);
  FSunLight := Value;
  if FSunLight <> nil then
    FSunLight.FreeNotification(Self);
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetSkyBackground(const Value: TCastleBackground);
begin
  if FSkyBackground = Value then
    Exit;
  if FSkyBackground <> nil then
    FSkyBackground.RemoveFreeNotification(Self);
  FSkyBackground := Value;
  if FSkyBackground <> nil then
    FSkyBackground.FreeNotification(Self);
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetAtmosphereFog(const Value: TCastleFog);
begin
  if FAtmosphereFog = Value then
    Exit;
  if FAtmosphereFog <> nil then
    FAtmosphereFog.RemoveFreeNotification(Self);
  FAtmosphereFog := Value;
  if FAtmosphereFog <> nil then
    FAtmosphereFog.FreeNotification(Self);
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.SetTargetViewport(const Value: TCastleViewport);
begin
  if FTargetViewport = Value then
    Exit;
  if FTargetViewport <> nil then
    FTargetViewport.RemoveFreeNotification(Self);
  FTargetViewport := Value;
  if FTargetViewport <> nil then
    FTargetViewport.FreeNotification(Self);
  MaybeAutoSync;
end;

function TCastleTimeOfDayWeather.EvaluateAtmosphereAtHour(
  const AHour: Single): TTimeOfDayAtmosphereState;
const
  NightSkyTop: TCastleColorRGB = (X: 0.015; Y: 0.024; Z: 0.065);
  NightSkyEquator: TCastleColorRGB = (X: 0.035; Y: 0.052; Z: 0.115);
  TwilightSkyTop: TCastleColorRGB = (X: 0.14; Y: 0.18; Z: 0.42);
  TwilightSkyEquator: TCastleColorRGB = (X: 0.94; Y: 0.44; Z: 0.18);
  DaySkyTop: TCastleColorRGB = (X: 0.16; Y: 0.44; Z: 0.86);
  DaySkyEquator: TCastleColorRGB = (X: 0.56; Y: 0.76; Z: 0.95);

  WarmSunriseSun: TCastleColorRGB = (X: 1.00; Y: 0.50; Z: 0.22);
  HighNoonSun: TCastleColorRGB = (X: 1.00; Y: 0.96; Z: 0.89);
  CoolMoonLight: TCastleColorRGB = (X: 0.52; Y: 0.65; Z: 0.92);
  CrimsonMoonLight: TCastleColorRGB = (X: 0.92; Y: 0.20; Z: 0.16);
  CrimsonNightSkyTop: TCastleColorRGB = (X: 0.11; Y: 0.018; Z: 0.032);
  CrimsonNightEquator: TCastleColorRGB = (X: 0.34; Y: 0.06; Z: 0.08);
var
  H, DeclRad, LatRad, HourAngleRad, SinElev, ElevRad, AzRad: Single;
  EastComp, NorthComp: Single;
  DayFactor, TwilightBand, NightFactor, SunWarmth: Single;
  OvercastTone: TCastleColorRGB;
  CloudBlend, BaseFogRange, WindRad: Single;
  LunarDome: TVector3;
begin
  FillChar(Result, SizeOf(Result), 0);
  H := NormalizeHour24(AHour);
  Result.TimeOfDayHours := H;

  { 1. Exact spherical solar ephemeris (+Y=Zenith, -Z=North, +X=East, +Z=South). }
  DeclRad := DegToRad(23.44) * Sin(2.0 * Pi * (FDayOfYear - 81) / 365.0);
  LatRad := DegToRad(FLatitudeDeg);
  HourAngleRad := DegToRad((H - 12.0) * 15.0);

  SinElev := Clamped(
    Sin(LatRad) * Sin(DeclRad) + Cos(LatRad) * Cos(DeclRad) * Cos(HourAngleRad),
    -1.0, 1.0);
  ElevRad := ArcSin(SinElev);
  Result.SolarElevationDeg := RadToDeg(ElevRad);

  EastComp := -Cos(DeclRad) * Sin(HourAngleRad);
  NorthComp := Cos(LatRad) * Sin(DeclRad) - Sin(LatRad) * Cos(DeclRad) * Cos(HourAngleRad);

  AzRad := ArcTan2(EastComp, NorthComp);
  if AzRad < 0.0 then
    AzRad := AzRad + 2.0 * Pi;
  Result.SolarAzimuthDeg := RadToDeg(AzRad);

  Result.SunPositionOnDome := Vector3(EastComp, SinElev, -NorthComp);
  if Result.SunPositionOnDome.LengthSqr > 1e-8 then
    Result.SunPositionOnDome := Result.SunPositionOnDome.Normalize
  else
    Result.SunPositionOnDome := Vector3(0.0, 1.0, 0.0);

  { 2. Day / Twilight / Lunar Night transitions. }
  DayFactor := SmoothStep01((Result.SolarElevationDeg + 2.0) / 20.0);
  NightFactor := SmoothStep01((-Result.SolarElevationDeg - 2.0) / 14.0);
  TwilightBand := Clamped(1.0 - Abs(Result.SolarElevationDeg - 2.0) / 14.0, 0.0, 1.0);
  TwilightBand := SmoothStep01(TwilightBand);

  Result.IsNightLunarMode := Result.SolarElevationDeg < -4.0;
  if not Result.IsNightLunarMode then
  begin
    { Sun shines downward from dome toward world origin; clamp slight grazing angle near horizon. }
    Result.ActiveLightDirection := -Result.SunPositionOnDome;
    if Result.ActiveLightDirection.Y > -0.06 then
    begin
      Result.ActiveLightDirection.Y := -0.06;
      Result.ActiveLightDirection := Result.ActiveLightDirection.Normalize;
    end;

    SunWarmth := SmoothStep01(Clamped(Result.SolarElevationDeg / 28.0, 0.0, 1.0));
    Result.DirectLightColor := LerpRgb(WarmSunriseSun, HighNoonSun, SunWarmth);
    Result.DirectLightIntensity := Lerp(SmoothStep01(Clamped((Result.SolarElevationDeg + 4.0) / 55.0, 0.0, 1.0)), 0.18, 2.45);
  end else
  begin
    { Lunar mode: moon sits opposite the sun across the dome and casts soft downward light. }
    LunarDome := Vector3(-Result.SunPositionOnDome.X, Abs(Result.SunPositionOnDome.Y), -Result.SunPositionOnDome.Z);
    if LunarDome.Y < 0.25 then
      LunarDome.Y := 0.25;
    LunarDome := LunarDome.Normalize;
    Result.ActiveLightDirection := -LunarDome;

    if FWeatherPreset = wpBloodMoon then
    begin
      Result.DirectLightColor := CrimsonMoonLight;
      Result.DirectLightIntensity := Lerp(NightFactor, 0.14, 0.36);
    end else
    begin
      Result.DirectLightColor := CoolMoonLight;
      Result.DirectLightIntensity := Lerp(NightFactor, 0.08, 0.20);
    end;
  end;

  { 3. Sky Dome colors (Night -> Twilight -> Day). }
  if FWeatherPreset = wpBloodMoon then
  begin
    Result.SkyTopColor := LerpRgb(CrimsonNightSkyTop, DaySkyTop, DayFactor);
    Result.SkyEquatorColor := LerpRgb(CrimsonNightEquator, DaySkyEquator, DayFactor);
  end else
  begin
    Result.SkyTopColor := LerpRgb(NightSkyTop, DaySkyTop, DayFactor);
    Result.SkyEquatorColor := LerpRgb(NightSkyEquator, DaySkyEquator, DayFactor);
  end;

  if TwilightBand > 0.001 then
  begin
    Result.SkyTopColor := LerpRgb(Result.SkyTopColor, TwilightSkyTop, TwilightBand * 0.55);
    Result.SkyEquatorColor := LerpRgb(Result.SkyEquatorColor, TwilightSkyEquator, TwilightBand * 0.85);
  end;

  { 4. Cloud & Weather Overcast attenuation. }
  Result.CloudCoverage := FCloudCoverage;
  Result.PrecipitationIntensity := FPrecipitationIntensity;
  CloudBlend := FCloudCoverage * 0.85;

  if FWeatherPreset = wpBlizzardSnow then
    OvercastTone := LerpRgb(Vector3(0.10, 0.13, 0.18), Vector3(0.76, 0.81, 0.88), DayFactor)
  else
    OvercastTone := LerpRgb(Vector3(0.05, 0.06, 0.09), Vector3(0.38, 0.42, 0.48), DayFactor);

  Result.SkyTopColor := LerpRgb(Result.SkyTopColor, OvercastTone, CloudBlend);
  Result.SkyEquatorColor := LerpRgb(Result.SkyEquatorColor, OvercastTone * 1.06, CloudBlend);
  Result.DirectLightIntensity := Result.DirectLightIntensity *
    (1.0 - 0.72 * FCloudCoverage - 0.14 * FPrecipitationIntensity);
  Result.DirectLightIntensity := Max(0.03, Result.DirectLightIntensity);

  { Desaturate direct light slightly under heavy clouds. }
  if (FCloudCoverage > 0.25) and (FWeatherPreset <> wpBloodMoon) then
    Result.DirectLightColor := LerpRgb(Result.DirectLightColor, OvercastTone * 1.35, FCloudCoverage * 0.45);

  Result.GroundEquatorColor := Result.SkyEquatorColor * 0.52;
  Result.GroundBottomColor := LerpRgb(Vector3(0.02, 0.02, 0.03), Vector3(0.16, 0.15, 0.13), DayFactor);
  if FWeatherPreset = wpBlizzardSnow then
    Result.GroundBottomColor := LerpRgb(Vector3(0.14, 0.16, 0.20), Vector3(0.68, 0.72, 0.78), DayFactor);

  { 5. Exponential Fog color & visibility range. }
  Result.FogColor := LerpRgb(Result.SkyEquatorColor, OvercastTone, FCloudCoverage * 0.5);
  BaseFogRange := Lerp(DayFactor, 220.0, 480.0);
  BaseFogRange := BaseFogRange / Max(0.1, FFogDensityMultiplier);
  BaseFogRange := BaseFogRange * (1.0 - 0.48 * FPrecipitationIntensity);
  Result.FogVisibilityRange := Clamped(BaseFogRange, 12.0, 2000.0);

  { 6. Wind vector in world XZ plane (0=North -Z, 90=East +X). }
  Result.WindDirectionDeg := FWindDirectionDeg;
  Result.WindSpeed := FWindSpeed;
  WindRad := DegToRad(FWindDirectionDeg);
  Result.WindVelocityWorld := Vector3(
    Sin(WindRad) * FWindSpeed,
    0.0,
    -Cos(WindRad) * FWindSpeed
  );
end;

function TCastleTimeOfDayWeather.CurrentAtmosphere: TTimeOfDayAtmosphereState;
begin
  Result := EvaluateAtmosphereAtHour(FTimeOfDayHours);
end;

procedure TCastleTimeOfDayWeather.AdvanceTimeSeconds(const ARealSeconds: Single);
var
  DeltaHours: Single;
begin
  DeltaHours := (ARealSeconds / Max(1.0, FDayLengthRealSeconds)) * 24.0;
  FTimeOfDayHours := NormalizeHour24(FTimeOfDayHours + DeltaHours);
  MaybeAutoSync;
end;

procedure TCastleTimeOfDayWeather.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited;
  if FAutoAdvanceInRuntime and (CastleApplicationMode = appRunning) and
     (SecondsPassed > 0.0) then
    AdvanceTimeSeconds(SecondsPassed);
end;

procedure TCastleTimeOfDayWeather.SynchronizeLinkedRig;
var
  S: TTimeOfDayAtmosphereState;
  SafeUp: TVector3;
begin
  S := CurrentAtmosphere;

  if FSunLight <> nil then
  begin
    if Abs(S.ActiveLightDirection.Y) > 0.98 then
      SafeUp := Vector3(0.0, 0.0, -1.0)
    else
      SafeUp := Vector3(0.0, 1.0, 0.0);
    FSunLight.SetView(S.ActiveLightDirection, SafeUp);
    FSunLight.Color := S.DirectLightColor;
    FSunLight.Intensity := S.DirectLightIntensity;
  end;

  if FSkyBackground <> nil then
  begin
    FSkyBackground.SkyTopColor := S.SkyTopColor;
    FSkyBackground.SkyEquatorColor := S.SkyEquatorColor;
    FSkyBackground.GroundEquatorColor := S.GroundEquatorColor;
    FSkyBackground.GroundBottomColor := S.GroundBottomColor;
  end;

  if FAtmosphereFog <> nil then
  begin
    FAtmosphereFog.Color := S.FogColor;
    FAtmosphereFog.FogType := ftExponential;
    FAtmosphereFog.VisibilityRange := S.FogVisibilityRange;
  end;

  if FTargetViewport <> nil then
  begin
    if (FSkyBackground <> nil) and (FTargetViewport.Background <> FSkyBackground) then
      FTargetViewport.Background := FSkyBackground;
    if (FAtmosphereFog <> nil) and (FTargetViewport.Fog <> FAtmosphereFog) then
      FTargetViewport.Fog := FAtmosphereFog;
  end;
end;

function TCastleTimeOfDayWeather.FormatClockHHMM: String;
var
  TotalMins, HH, MM: Integer;
begin
  TotalMins := Round(NormalizeHour24(FTimeOfDayHours) * 60.0) mod 1440;
  if TotalMins < 0 then
    TotalMins := TotalMins + 1440;
  HH := TotalMins div 60;
  MM := TotalMins mod 60;
  Result := Format('%.2d:%.2d', [HH, MM]);
end;

function TCastleTimeOfDayWeather.TimeOfDaySummaryBadge: String;
var
  S: TTimeOfDayAtmosphereState;
begin
  S := CurrentAtmosphere;
  Result := Format('[ToD:%s %s Elev=%ddeg]', [
    FormatClockHHMM,
    WeatherPresetDisplayName(FWeatherPreset),
    Round(S.SolarElevationDeg)
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleTimeOfDayWeather,
    ['Environment', 'Time-of-Day & Weather Controller']);
end.
