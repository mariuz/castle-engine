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

{ Design-time helper for Heat-Haze Mirage, Thermal Convection Plume &
  Underwater Caustic Refraction Field Studio (Phase 401). }
unit ToolThermalMirage;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleThermalMirage;

type
  TThermalMirageHelper = class
  public
    class function FindFirstVolume(const ARoot: TComponent): TCastleThermalMirageVolume;
    class function SpawnDesertHighwayMirageDemo(const ARoot, AOwner: TComponent;
      out AVol: TCastleThermalMirageVolume): Boolean;
    class function ExportVolumeJson(const AVol: TCastleThermalMirageVolume): String;
    class function ImportVolumeJson(const AVol: TCastleThermalMirageVolume;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AVol: TCastleThermalMirageVolume): String;
  end;

implementation

uses
  CastleUtils;

function FindViewportInTree(const ARoot: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleViewport then Exit(TCastleViewport(ARoot));
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindViewportInTree(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TThermalMirageHelper.FindFirstVolume(
  const ARoot: TComponent): TCastleThermalMirageVolume;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleThermalMirageVolume;
  var
    J: Integer;
  begin
    if T is TCastleThermalMirageVolume then
      Exit(TCastleThermalMirageVolume(T));
    for J := 0 to T.Count - 1 do
    begin
      Result := SearchTransform(T[J]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleThermalMirageVolume then
    Exit(TCastleThermalMirageVolume(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleThermalMirageVolume then
      Exit(TCastleThermalMirageVolume(ARoot.Components[I]));
end;

class function TThermalMirageHelper.SpawnDesertHighwayMirageDemo(
  const ARoot, AOwner: TComponent; out AVol: TCastleThermalMirageVolume): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  AsphaltStrip: TCastleBox;
begin
  Result := False;
  AVol := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  AsphaltStrip := TCastleBox.Create(Own);
  AsphaltStrip.Name := 'DesertHighwayAsphalt';
  AsphaltStrip.Size := Vector3(12.0, 0.2, 34.0);
  AsphaltStrip.Translation := Vector3(0.0, -0.1, 0.0);
  AsphaltStrip.Color := Vector4(0.18, 0.19, 0.22, 1.0);
  VP.Items.Add(AsphaltStrip);

  AVol := TCastleThermalMirageVolume.Create(Own);
  AVol.Name := 'DesertMirageRefractionZone';
  AVol.ApplyPreset(tmpDesertAsphaltMirage);
  VP.Items.Add(AVol);
  Result := True;
end;

class function TThermalMirageHelper.ExportVolumeJson(
  const AVol: TCastleThermalMirageVolume): String;
var
  Obj: TJSONObject;
begin
  if AVol = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AVol.Preset));
    Obj.Add('extX', AVol.VolumeExtents.X);
    Obj.Add('extY', AVol.VolumeExtents.Y);
    Obj.Add('extZ', AVol.VolumeExtents.Z);
    Obj.Add('surfaceDeltaTempCelsius', AVol.SurfaceDeltaTempCelsius);
    Obj.Add('shimmerDistortionAmplitude', AVol.ShimmerDistortionAmplitude);
    Obj.Add('mirageCriticalGrazingDeg', AVol.MirageCriticalGrazingDeg);
    Obj.Add('causticContrast', AVol.CausticContrast);
    Obj.Add('waterDepthMeters', AVol.WaterDepthMeters);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TThermalMirageHelper.ImportVolumeJson(
  const AVol: TCastleThermalMirageVolume; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AVol = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(AVol.Preset));
    if (POrd >= Ord(Low(TThermalMiragePreset))) and
       (POrd <= Ord(High(TThermalMiragePreset))) then
      AVol.Preset := TThermalMiragePreset(POrd);
    AVol.VolumeExtents := Vector3(
      Obj.Get('extX', AVol.VolumeExtents.X),
      Obj.Get('extY', AVol.VolumeExtents.Y),
      Obj.Get('extZ', AVol.VolumeExtents.Z));
    AVol.SurfaceDeltaTempCelsius := Obj.Get('surfaceDeltaTempCelsius', AVol.SurfaceDeltaTempCelsius);
    AVol.ShimmerDistortionAmplitude := Obj.Get('shimmerDistortionAmplitude', AVol.ShimmerDistortionAmplitude);
    AVol.MirageCriticalGrazingDeg := Obj.Get('mirageCriticalGrazingDeg', AVol.MirageCriticalGrazingDeg);
    AVol.CausticContrast := Obj.Get('causticContrast', AVol.CausticContrast);
    AVol.WaterDepthMeters := Obj.Get('waterDepthMeters', AVol.WaterDepthMeters);
    AVol.RebuildPreview;
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TThermalMirageHelper.GenerateMarkdownReport(
  const AVol: TCastleThermalMirageVolume): String;
var
  SL: TStringList;
  S: TThermalOpticalSample;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Heat-Haze Mirage, Thermal Convection & Underwater Caustics Report');
    SL.Add('');
    if AVol = nil then
    begin
      SL.Add('_No `TCastleThermalMirageVolume` found in the active design._');
      Exit(SL.Text);
    end;
    S := AVol.SampleOpticalFieldAtWorld(Vector3(0.0, 0.12, -10.0), Vector3(0.0, 1.1, 18.0));
    SL.Add('- **Optical Volume**: `' + AVol.Name + '` (`' +
      ThermalMiragePresetToString(AVol.Preset) + '`)');
    SL.Add(FormatDot('- **Thermal Delta / Shimmer**: `+%.1f C` / `%.4f` UV (Plume `%.2f m/s`)',
      [AVol.SurfaceDeltaTempCelsius, AVol.ShimmerDistortionAmplitude, AVol.PlumeRiseSpeedMps]));
    SL.Add(FormatDot('- **Grazing Mirage / Reef Caustics**: Mirage `%.1f%%`, Updraft `%.2f m/s`, Caustic Boost `%.2fx`',
      [S.InferiorMirageReflectivity01 * 100.0, S.UpdraftVelocityMps, S.CausticLuminanceBoost]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
