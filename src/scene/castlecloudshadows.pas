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

{ 2.5D atmospheric wind-advected dual-octave cloud shadow projector, solar
  elevation ground-offset ray projection, and Henyey-Greenstein crepuscular
  light-shaft evaluator (Phase 382). }
unit CastleCloudShadows;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Atmospheric cloud deck presets. }
  TCloudShadowPreset = (
    cspSummerCumulusDrift,
    cspStormOvercastFront,
    cspBrokenSunsetGodRays
  );

  { Ground transmittance and crepuscular god-ray evaluation at a world point. }
  TCloudShadowSample = record
    CloudDensity01: Single;
    DirectSunTransmittance01: Single;
    CrepuscularShaftIntensity: Single;
    ProjectedCanopyXZ: TVector2;
  end;

  { Projects dual-octave wind-advected cloud transmittance and Mie crepuscular
    god-rays onto arbitrary 3D ground coordinates. }
  TCastleCloudShadowProjector = class(TCastleTransform)
  private
    FPreset: TCloudShadowPreset;
    FCloudAltitudeMeters: Single;
    FCloudCoverage01: Single;
    FCloudSoftness01: Single;
    FCloudTileScaleMeters: Single;
    FWindSpeedMps: Single;
    FWindDirectionDeg: Single;
    FDetailOctaveMix01: Single;
    FShadowMaxDarkening01: Single;
    FSunElevationDeg: Single;
    FSunAzimuthDeg: Single;
    FMieAnisotropyG: Single;
    FShowPreviewGrid: Boolean;
    FScrollPrimaryXZ: TVector2;
    FScrollDetailXZ: TVector2;
    FElapsedWindSec: Single;
    FPreviewRoot: TCastleTransform;
    procedure SetPreset(const AValue: TCloudShadowPreset);
    procedure SetCloudAltitudeMeters(const AValue: Single);
    procedure SetCloudCoverage01(const AValue: Single);
    procedure SetCloudSoftness01(const AValue: Single);
    procedure SetCloudTileScaleMeters(const AValue: Single);
    procedure SetWindSpeedMps(const AValue: Single);
    procedure SetDetailOctaveMix01(const AValue: Single);
    procedure SetShadowMaxDarkening01(const AValue: Single);
    procedure SetSunElevationDeg(const AValue: Single);
    procedure SetMieAnisotropyG(const AValue: Single);
    procedure SetShowPreviewGrid(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure RebuildPreviewCanopy;
    function EvaluateCanopyNoise01(const ACanopyXZ: TVector2): Single;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ApplyPreset(const APreset: TCloudShadowPreset);
    procedure StepWindAdvection(const ADtSec: Single);
    procedure ResetWindScroll;

    { Unit direction vector pointing from the ground toward the solar disc. }
    function EvaluateSunDirectionToSky: TVector3;

    { Evaluate cloud density, direct sun transmittance, and crepuscular shaft intensity. }
    function SampleGroundShadowAt(const AWorldGroundPos: TVector3;
      const AViewDirToSky: TVector3): TCloudShadowSample;

    { Measure fraction of grid samples with CloudDensity01 > 0.5 over [-AHalfSpan..+AHalfSpan]. }
    function ComputeCoverageFractionOverGrid(const AHalfSpanMeters: Single;
      const AGridRes: Integer = 16): Single;

    function CloudSummaryBadge: String;

    property ScrollPrimaryXZ: TVector2 read FScrollPrimaryXZ;
    property ElapsedWindSec: Single read FElapsedWindSec;
  published
    property Preset: TCloudShadowPreset read FPreset write SetPreset default cspSummerCumulusDrift;
    property CloudAltitudeMeters: Single read FCloudAltitudeMeters write SetCloudAltitudeMeters;
    property CloudCoverage01: Single read FCloudCoverage01 write SetCloudCoverage01;
    property CloudSoftness01: Single read FCloudSoftness01 write SetCloudSoftness01;
    property CloudTileScaleMeters: Single read FCloudTileScaleMeters write SetCloudTileScaleMeters;
    property WindSpeedMps: Single read FWindSpeedMps write SetWindSpeedMps;
    property WindDirectionDeg: Single read FWindDirectionDeg write FWindDirectionDeg;
    property DetailOctaveMix01: Single read FDetailOctaveMix01 write SetDetailOctaveMix01;
    property ShadowMaxDarkening01: Single read FShadowMaxDarkening01 write SetShadowMaxDarkening01;
    property SunElevationDeg: Single read FSunElevationDeg write SetSunElevationDeg;
    property SunAzimuthDeg: Single read FSunAzimuthDeg write FSunAzimuthDeg;
    property MieAnisotropyG: Single read FMieAnisotropyG write SetMieAnisotropyG;
    property ShowPreviewGrid: Boolean read FShowPreviewGrid write SetShowPreviewGrid default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored False;
  end;

implementation

uses FpJson, JsonParser, CastleUtils;

{$PUSH}{$Q-}{$R-}
function Hash2DCloud(const IX, IZ: Integer): Single;
var
  H: Cardinal;
begin
  H := Cardinal(IX) * Cardinal(374761393) + Cardinal(IZ) * Cardinal(668265263);
  H := (H xor (H shr 13)) * Cardinal(1274126177);
  H := H xor (H shr 16);
  Result := (H and $00FFFFFF) / 16777215.0;
end;
{$POP}

function SmoothValueNoise2D(const X, Z: Single): Single;
var
  IX, IZ: Integer;
  FX, FZ, UX, UZ, V00, V10, V01, V11: Single;
begin
  IX := Floor(X);
  IZ := Floor(Z);
  FX := X - IX;
  FZ := Z - IZ;
  UX := FX * FX * (3.0 - 2.0 * FX);
  UZ := FZ * FZ * (3.0 - 2.0 * FZ);
  V00 := Hash2DCloud(IX, IZ);
  V10 := Hash2DCloud(IX + 1, IZ);
  V01 := Hash2DCloud(IX, IZ + 1);
  V11 := Hash2DCloud(IX + 1, IZ + 1);
  Result := Lerp(UZ, Lerp(UX, V00, V10), Lerp(UX, V01, V11));
end;

function SmoothStepEdge(const Edge0, Edge1, X: Single): Single;
var
  T: Single;
begin
  if Edge1 <= Edge0 + 1e-5 then
  begin
    if X >= Edge0 then Exit(1.0) else Exit(0.0);
  end;
  T := EnsureRange((X - Edge0) / (Edge1 - Edge0), 0.0, 1.0);
  Result := T * T * (3.0 - 2.0 * T);
end;

function HenyeyGreensteinPhase(const CosTheta, G: Single): Single;
var
  G2, Denom: Single;
begin
  G2 := G * G;
  Denom := Max(1e-4, 1.0 + G2 - 2.0 * G * EnsureRange(CosTheta, -1.0, 1.0));
  Result := (1.0 - G2) / (Denom * Sqrt(Denom));
end;

{ TCastleCloudShadowProjector ------------------------------------------------ }

constructor TCastleCloudShadowProjector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCloudAltitudeMeters := 320.0;
  FCloudCoverage01 := 0.48;
  FCloudSoftness01 := 0.22;
  FCloudTileScaleMeters := 160.0;
  FWindSpeedMps := 12.0;
  FWindDirectionDeg := 35.0;
  FDetailOctaveMix01 := 0.35;
  FShadowMaxDarkening01 := 0.72;
  FSunElevationDeg := 45.0;
  FSunAzimuthDeg := 135.0;
  FMieAnisotropyG := 0.76;
  FShowPreviewGrid := True;
  ApplyPreset(cspSummerCumulusDrift);
end;

destructor TCastleCloudShadowProjector.Destroy;
begin
  FreeAndNil(FPreviewRoot);
  inherited Destroy;
end;

function TCastleCloudShadowProjector.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'CloudAltitudeMeters', 'CloudCoverage01', 'CloudSoftness01',
       'CloudTileScaleMeters', 'WindSpeedMps', 'WindDirectionDeg',
       'DetailOctaveMix01', 'ShadowMaxDarkening01', 'SunElevationDeg',
       'SunAzimuthDeg', 'MieAnisotropyG', 'ShowPreviewGrid'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleCloudShadowProjector.ApplyPreset(const APreset: TCloudShadowPreset);
begin
  FPreset := APreset;
  case APreset of
    cspSummerCumulusDrift:
      begin
        FCloudAltitudeMeters := 320.0;
        FCloudCoverage01 := 0.48;
        FCloudSoftness01 := 0.22;
        FCloudTileScaleMeters := 160.0;
        FWindSpeedMps := 12.0;
        FWindDirectionDeg := 35.0;
        FDetailOctaveMix01 := 0.35;
        FShadowMaxDarkening01 := 0.72;
        FSunElevationDeg := 45.0;
        FSunAzimuthDeg := 135.0;
        FMieAnisotropyG := 0.76;
      end;
    cspStormOvercastFront:
      begin
        FCloudAltitudeMeters := 220.0;
        FCloudCoverage01 := 0.86;
        FCloudSoftness01 := 0.30;
        FCloudTileScaleMeters := 240.0;
        FWindSpeedMps := 24.0;
        FWindDirectionDeg := 70.0;
        FDetailOctaveMix01 := 0.42;
        FShadowMaxDarkening01 := 0.88;
        FSunElevationDeg := 32.0;
        FSunAzimuthDeg := 110.0;
        FMieAnisotropyG := 0.65;
      end;
    cspBrokenSunsetGodRays:
      begin
        FCloudAltitudeMeters := 400.0;
        FCloudCoverage01 := 0.54;
        FCloudSoftness01 := 0.18;
        FCloudTileScaleMeters := 140.0;
        FWindSpeedMps := 8.5;
        FWindDirectionDeg := 15.0;
        FDetailOctaveMix01 := 0.38;
        FShadowMaxDarkening01 := 0.78;
        FSunElevationDeg := 16.0;
        FSunAzimuthDeg := 250.0;
        FMieAnisotropyG := 0.84;
      end;
  end;
  RebuildPreviewCanopy;
end;

procedure TCastleCloudShadowProjector.SetPreset(const AValue: TCloudShadowPreset);
begin
  if FPreset <> AValue then
    ApplyPreset(AValue);
end;

procedure TCastleCloudShadowProjector.SetCloudAltitudeMeters(const AValue: Single);
begin
  FCloudAltitudeMeters := Max(10.0, AValue);
end;

procedure TCastleCloudShadowProjector.SetCloudCoverage01(const AValue: Single);
begin
  FCloudCoverage01 := EnsureRange(AValue, 0.0, 1.0);
  RebuildPreviewCanopy;
end;

procedure TCastleCloudShadowProjector.SetCloudSoftness01(const AValue: Single);
begin
  FCloudSoftness01 := EnsureRange(AValue, 0.01, 0.50);
end;

procedure TCastleCloudShadowProjector.SetCloudTileScaleMeters(const AValue: Single);
begin
  FCloudTileScaleMeters := Max(10.0, AValue);
end;

procedure TCastleCloudShadowProjector.SetWindSpeedMps(const AValue: Single);
begin
  FWindSpeedMps := Max(0.0, AValue);
end;

procedure TCastleCloudShadowProjector.SetDetailOctaveMix01(const AValue: Single);
begin
  FDetailOctaveMix01 := EnsureRange(AValue, 0.0, 1.0);
end;

procedure TCastleCloudShadowProjector.SetShadowMaxDarkening01(const AValue: Single);
begin
  FShadowMaxDarkening01 := EnsureRange(AValue, 0.0, 1.0);
end;

procedure TCastleCloudShadowProjector.SetSunElevationDeg(const AValue: Single);
begin
  FSunElevationDeg := EnsureRange(AValue, 5.0, 90.0);
end;

procedure TCastleCloudShadowProjector.SetMieAnisotropyG(const AValue: Single);
begin
  FMieAnisotropyG := EnsureRange(AValue, 0.0, 0.95);
end;

procedure TCastleCloudShadowProjector.SetShowPreviewGrid(const AValue: Boolean);
begin
  if FShowPreviewGrid <> AValue then
  begin
    FShowPreviewGrid := AValue;
    RebuildPreviewCanopy;
  end;
end;

procedure TCastleCloudShadowProjector.RebuildPreviewCanopy;
var
  PatchBox: TCastleBox;
  IX, IZ: Integer;
  Dens: Single;
begin
  FreeAndNil(FPreviewRoot);
  if not FShowPreviewGrid then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  FPreviewRoot.Name := 'TransientCloudCanopyPreview';

  for IZ := -2 to 2 do
    for IX := -2 to 2 do
    begin
      Dens := EvaluateCanopyNoise01(Vector2(IX * 28.0, IZ * 28.0));
      if Dens > 0.25 then
      begin
        PatchBox := TCastleBox.Create(FPreviewRoot);
        PatchBox.SetTransient;
        PatchBox.Pickable := False;
        PatchBox.Collides := False;
        PatchBox.Size := Vector3(22.0, 1.2 + Dens * 2.5, 22.0);
        PatchBox.Translation := Vector3(IX * 28.0, 26.0, IZ * 28.0);
        PatchBox.Color := Vector4(0.92, 0.95, 1.0, 0.45);
        FPreviewRoot.Add(PatchBox);
      end;
    end;

  Add(FPreviewRoot);
end;

procedure TCastleCloudShadowProjector.StepWindAdvection(const ADtSec: Single);
var
  Rad: Single;
  WindDirXZ: TVector2;
begin
  if ADtSec <= 0.0 then Exit;
  FElapsedWindSec := FElapsedWindSec + ADtSec;
  Rad := DegToRad(FWindDirectionDeg);
  WindDirXZ := Vector2(Cos(Rad), Sin(Rad));
  FScrollPrimaryXZ := FScrollPrimaryXZ + WindDirXZ * (FWindSpeedMps * ADtSec);
  FScrollDetailXZ := FScrollDetailXZ + WindDirXZ * (FWindSpeedMps * 1.45 * ADtSec);
end;

procedure TCastleCloudShadowProjector.ResetWindScroll;
begin
  FScrollPrimaryXZ := TVector2.Zero;
  FScrollDetailXZ := TVector2.Zero;
  FElapsedWindSec := 0.0;
end;

procedure TCastleCloudShadowProjector.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  StepWindAdvection(Min(SecondsPassed, 0.1));
end;

function TCastleCloudShadowProjector.EvaluateSunDirectionToSky: TVector3;
var
  ElevRad, AzimRad, CosElev: Single;
begin
  ElevRad := DegToRad(FSunElevationDeg);
  AzimRad := DegToRad(FSunAzimuthDeg);
  CosElev := Cos(ElevRad);
  Result := Vector3(CosElev * Cos(AzimRad), Sin(ElevRad), CosElev * Sin(AzimRad));
  if Result.LengthSqr > 1e-8 then
    Result := Result.Normalize
  else
    Result := Vector3(0, 1, 0);
end;

function TCastleCloudShadowProjector.EvaluateCanopyNoise01(const ACanopyXZ: TVector2): Single;
var
  InvScale, N1, N2, Combined, Threshold, HalfSoft: Single;
  P1, P2: TVector2;
begin
  if FCloudCoverage01 <= 0.0001 then
    Exit(0.0);
  if FCloudCoverage01 >= 0.9999 then
    Exit(1.0);

  InvScale := 1.0 / Max(10.0, FCloudTileScaleMeters);
  P1 := (ACanopyXZ - FScrollPrimaryXZ) * InvScale;
  P2 := (ACanopyXZ - FScrollDetailXZ) * (InvScale * 2.73) + Vector2(17.3, -9.1);
  N1 := SmoothValueNoise2D(P1.X, P1.Y);
  N2 := SmoothValueNoise2D(P2.X, P2.Y);
  Combined := Lerp(FDetailOctaveMix01, N1, N2);

  Threshold := 1.0 - FCloudCoverage01;
  HalfSoft := FCloudSoftness01 * 0.5;
  Result := SmoothStepEdge(Threshold - HalfSoft, Threshold + HalfSoft, Combined);
end;

function TCastleCloudShadowProjector.SampleGroundShadowAt(
  const AWorldGroundPos: TVector3; const AViewDirToSky: TVector3): TCloudShadowSample;
var
  SunDir, ViewU: TVector3;
  DeltaH, RayScale, EdgeRim, CosSunView: Single;
begin
  Result := Default(TCloudShadowSample);
  SunDir := EvaluateSunDirectionToSky;
  DeltaH := Max(0.0, FCloudAltitudeMeters - AWorldGroundPos.Y);
  RayScale := DeltaH / Max(0.08, SunDir.Y);

  Result.ProjectedCanopyXZ := Vector2(
    AWorldGroundPos.X + SunDir.X * RayScale,
    AWorldGroundPos.Z + SunDir.Z * RayScale);

  Result.CloudDensity01 := EvaluateCanopyNoise01(Result.ProjectedCanopyXZ);
  Result.DirectSunTransmittance01 := EnsureRange(
    1.0 - FShadowMaxDarkening01 * Result.CloudDensity01, 0.0, 1.0);

  { Crepuscular shafts peak along broken cloud edges 4*d*(1-d) + sunlit gaps,
    strongly boosted in the forward Mie solar lobe }
  if AViewDirToSky.LengthSqr > 1e-8 then
    ViewU := AViewDirToSky.Normalize
  else
    ViewU := SunDir;
  CosSunView := TVector3.DotProduct(ViewU, SunDir);
  EdgeRim := 0.25 * Result.DirectSunTransmittance01 +
    0.75 * (4.0 * Result.CloudDensity01 * (1.0 - Result.CloudDensity01));
  Result.CrepuscularShaftIntensity := EdgeRim * HenyeyGreensteinPhase(CosSunView, FMieAnisotropyG);
end;

function TCastleCloudShadowProjector.ComputeCoverageFractionOverGrid(
  const AHalfSpanMeters: Single; const AGridRes: Integer): Single;
var
  N, IX, IZ, ShadowedCells: Integer;
  X, Z: Single;
  S: TCloudShadowSample;
  SunDir: TVector3;
begin
  N := Max(2, AGridRes);
  ShadowedCells := 0;
  SunDir := EvaluateSunDirectionToSky;
  for IZ := 0 to N - 1 do
    for IX := 0 to N - 1 do
    begin
      X := Lerp(IX / Single(N - 1), -AHalfSpanMeters, AHalfSpanMeters);
      Z := Lerp(IZ / Single(N - 1), -AHalfSpanMeters, AHalfSpanMeters);
      S := SampleGroundShadowAt(Vector3(X, 0.0, Z), SunDir);
      if S.CloudDensity01 >= 0.5 then
        Inc(ShadowedCells);
    end;
  Result := ShadowedCells / Single(N * N);
end;

function TCastleCloudShadowProjector.CloudSummaryBadge: String;
begin
  Result := Format('[Clouds:Cov=%.0f%% Wind=%.1fm/s Alt=%.0fm]', [
    FCloudCoverage01 * 100.0, FWindSpeedMps, FCloudAltitudeMeters]);
end;

function TCastleCloudShadowProjector.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('cloudAltitudeMeters', FCloudAltitudeMeters);
    Obj.Add('cloudCoverage01', FCloudCoverage01);
    Obj.Add('cloudSoftness01', FCloudSoftness01);
    Obj.Add('cloudTileScaleMeters', FCloudTileScaleMeters);
    Obj.Add('windSpeedMps', FWindSpeedMps);
    Obj.Add('windDirectionDeg', FWindDirectionDeg);
    Obj.Add('detailOctaveMix01', FDetailOctaveMix01);
    Obj.Add('shadowMaxDarkening01', FShadowMaxDarkening01);
    Obj.Add('sunElevationDeg', FSunElevationDeg);
    Obj.Add('sunAzimuthDeg', FSunAzimuthDeg);
    Obj.Add('mieAnisotropyG', FMieAnisotropyG);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleCloudShadowProjector.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Data := nil;
    end;
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      FPreset := TCloudShadowPreset(EnsureRange(Obj.Get('preset', Ord(FPreset)), 0, Ord(High(TCloudShadowPreset))));
      FCloudAltitudeMeters := Max(10.0, Obj.Get('cloudAltitudeMeters', FCloudAltitudeMeters));
      FCloudCoverage01 := EnsureRange(Obj.Get('cloudCoverage01', FCloudCoverage01), 0.0, 1.0);
      FCloudSoftness01 := EnsureRange(Obj.Get('cloudSoftness01', FCloudSoftness01), 0.01, 0.50);
      FCloudTileScaleMeters := Max(10.0, Obj.Get('cloudTileScaleMeters', FCloudTileScaleMeters));
      FWindSpeedMps := Max(0.0, Obj.Get('windSpeedMps', FWindSpeedMps));
      FWindDirectionDeg := Obj.Get('windDirectionDeg', FWindDirectionDeg);
      FDetailOctaveMix01 := EnsureRange(Obj.Get('detailOctaveMix01', FDetailOctaveMix01), 0.0, 1.0);
      FShadowMaxDarkening01 := EnsureRange(Obj.Get('shadowMaxDarkening01', FShadowMaxDarkening01), 0.0, 1.0);
      FSunElevationDeg := EnsureRange(Obj.Get('sunElevationDeg', FSunElevationDeg), 5.0, 90.0);
      FSunAzimuthDeg := Obj.Get('sunAzimuthDeg', FSunAzimuthDeg);
      FMieAnisotropyG := EnsureRange(Obj.Get('mieAnisotropyG', FMieAnisotropyG), 0.0, 0.95);
      RebuildPreviewCanopy;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleCloudShadowProjector,
    ['Environment & Weather', 'Cloud Shadow & God-Ray Projector (TCastleCloudShadowProjector)']);

end.
