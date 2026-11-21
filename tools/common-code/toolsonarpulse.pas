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

{ Design-time helper for 3D Echolocation & Active Sonar Pulse
  (WorldRay Spherical Ping Wavefront, Two-Way Echo & Doppler Shift) Studio (Phase 414). }
unit ToolSonarPulse;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleSonarPulse;

type
  TSonarPulseHelper = class
  public
    class function FindFirstSonar(const ARoot: TComponent): TCastleSonarPulse;
    class function SpawnTrenchSubmarineSonarDemo(const ARoot, AOwner: TComponent;
      out ASonar: TCastleSonarPulse): Boolean;
    class function ExportSonarJson(const ASonar: TCastleSonarPulse): String;
    class function ImportSonarJson(const ASonar: TCastleSonarPulse;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ASonar: TCastleSonarPulse): String;
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

class function TSonarPulseHelper.FindFirstSonar(
  const ARoot: TComponent): TCastleSonarPulse;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleSonarPulse;
  var
    J: Integer;
  begin
    if T is TCastleSonarPulse then
      Exit(TCastleSonarPulse(T));
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
  if ARoot is TCastleSonarPulse then
    Exit(TCastleSonarPulse(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleSonarPulse then
      Exit(TCastleSonarPulse(ARoot.Components[I]));
end;

class function TSonarPulseHelper.SpawnTrenchSubmarineSonarDemo(
  const ARoot, AOwner: TComponent; out ASonar: TCastleSonarPulse): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  NearHull, FarAnechoicSub: TCastleBox;
begin
  Result := False;
  ASonar := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Near steel shipwreck hull at Z = -12m (two-way arrival @ c=40m/s is 0.60s!) }
  NearHull := TCastleBox.Create(Own);
  NearHull.Name := 'SteelWreckHull_Near';
  NearHull.Size := Vector3(5.0, 4.0, 2.0);
  NearHull.Translation := Vector3(0.0, 1.0, -13.0);
  NearHull.Color := Vector4(0.52, 0.58, 0.65, 1.0);
  VP.Items.Add(NearHull);

  { Distant stealth anechoic submarine at X = +32m (two-way arrival @ c=40m/s is 1.60s!) }
  FarAnechoicSub := TCastleBox.Create(Own);
  FarAnechoicSub.Name := 'StealthAnechoicSub_Far';
  FarAnechoicSub.Size := Vector3(2.0, 4.0, 6.0);
  FarAnechoicSub.Translation := Vector3(33.0, 1.0, 0.0);
  FarAnechoicSub.Color := Vector4(0.22, 0.24, 0.28, 1.0);
  VP.Items.Add(FarAnechoicSub);

  ASonar := TCastleSonarPulse.Create(Own);
  ASonar.Name := 'TacticalMotionSonar';
  ASonar.Translation := Vector3(0.0, 1.0, 0.0);
  ASonar.ApplyPreset(sppSciFiMotionTrackerPulse);
  VP.Items.Add(ASonar);

  ASonar.EmitSonarPing(VP.Items);
  Result := True;
end;

class function TSonarPulseHelper.ExportSonarJson(
  const ASonar: TCastleSonarPulse): String;
var
  Obj: TJSONObject;
begin
  if ASonar = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ASonar.Preset));
    Obj.Add('speed_mps', ASonar.PropagationSpeedMps);
    Obj.Add('carrier_hz', ASonar.CarrierFrequencyHz);
    Obj.Add('max_range_m', ASonar.MaxRangeMeters);
    Obj.Add('fade_sec', ASonar.PhosphorFadeSec);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TSonarPulseHelper.ImportSonarJson(
  const ASonar: TCastleSonarPulse; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ASonar = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(ASonar.Preset));
    if (POrd >= Ord(Low(TSonarPulsePreset))) and
       (POrd <= Ord(High(TSonarPulsePreset))) then
      ASonar.ApplyPreset(TSonarPulsePreset(POrd));
    ASonar.PropagationSpeedMps := Obj.Get('speed_mps', ASonar.PropagationSpeedMps);
    ASonar.CarrierFrequencyHz := Obj.Get('carrier_hz', ASonar.CarrierFrequencyHz);
    ASonar.MaxRangeMeters := Obj.Get('max_range_m', ASonar.MaxRangeMeters);
    ASonar.PhosphorFadeSec := Obj.Get('fade_sec', ASonar.PhosphorFadeSec);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TSonarPulseHelper.GenerateMarkdownReport(
  const ASonar: TCastleSonarPulse): String;
var
  SL: TStringList;
  I: Integer;
  C: TSonarEchoContact;
begin
  SL := TStringList.Create;
  try
    SL.Add('# 3D Echolocation & Active Sonar Pulse Report');
    SL.Add('');
    if ASonar = nil then
    begin
      SL.Add('_No `TCastleSonarPulse` found in the current design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Sonar**: `' + ASonar.Name + '` (`' +
      SonarPulsePresetToString(ASonar.Preset) + '`)');
    SL.Add(FormatDot('- **Wavefront**: `R = %.1f m` (`t = %.2f s`, Speed `%.0f m/s`)',
      [ASonar.WavefrontRadiusMeters, ASonar.ElapsedPingSec, ASonar.PropagationSpeedMps]));
    SL.Add(Format('- **Revealed Echoes**: `%d / %d`',
      [ASonar.RevealedContactCount, ASonar.ContactCount]));
    for I := 0 to ASonar.ContactCount - 1 do
    begin
      C := ASonar.GetContact(I);
      SL.Add(FormatDot('  - `%s`: `%.1f m` (2-way `%.2f s`, Bright `%.0f%%`, Doppler `%+.1f Hz`)',
        [C.TargetName, C.RangeMeters, C.TwoWayArrivalTimeSec,
         C.PhosphorBrightness01 * 100.0, C.DopplerShiftHz]));
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
