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

{ Design-time helper for Procedural Torch & Campfire Blackbody Flicker,
  Wind-Draft Tilt, Gust Blowout & Wall Soot Studio (Phase 404). }
unit ToolFlameFlicker;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleFlameFlicker;

type
  TFlameFlickerHelper = class
  public
    class function FindFirstRig(const ARoot: TComponent): TCastleFlameFlickerRig;
    class function SpawnDungeonWallSconceDemo(const ARoot, AOwner: TComponent;
      out ARig: TCastleFlameFlickerRig): Boolean;
    class function ExportRigJson(const ARig: TCastleFlameFlickerRig): String;
    class function ImportRigJson(const ARig: TCastleFlameFlickerRig;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ARig: TCastleFlameFlickerRig): String;
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

class function TFlameFlickerHelper.FindFirstRig(
  const ARoot: TComponent): TCastleFlameFlickerRig;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleFlameFlickerRig;
  var
    J: Integer;
  begin
    if T is TCastleFlameFlickerRig then
      Exit(TCastleFlameFlickerRig(T));
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
  if ARoot is TCastleFlameFlickerRig then
    Exit(TCastleFlameFlickerRig(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleFlameFlickerRig then
      Exit(TCastleFlameFlickerRig(ARoot.Components[I]));
end;

class function TFlameFlickerHelper.SpawnDungeonWallSconceDemo(
  const ARoot, AOwner: TComponent; out ARig: TCastleFlameFlickerRig): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  BackWall, LowArch: TCastleBox;
begin
  Result := False;
  ARig := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Dungeon stone wall 0.35m behind torch (-Z) + low vault arch 1.15m above torch (+Y) }
  BackWall := TCastleBox.Create(Own);
  BackWall.Name := 'SconceStoneBackWall';
  BackWall.Size := Vector3(3.0, 3.2, 0.4);
  BackWall.Translation := Vector3(0.0, 1.6, -0.55);
  BackWall.Color := Vector4(0.30, 0.31, 0.34, 1.0);
  VP.Items.Add(BackWall);

  LowArch := TCastleBox.Create(Own);
  LowArch.Name := 'SconceVaultCeiling';
  LowArch.Size := Vector3(3.0, 0.4, 2.4);
  LowArch.Translation := Vector3(0.0, 3.15, 0.0);
  LowArch.Color := Vector4(0.28, 0.29, 0.32, 1.0);
  VP.Items.Add(LowArch);

  ARig := TCastleFlameFlickerRig.Create(Own);
  ARig.Name := 'DungeonWallTorchSconce';
  ARig.Translation := Vector3(0.0, 1.85, 0.0);
  ARig.ApplyPreset(ffpDungeonWallSconceTorch);
  VP.Items.Add(ARig);

  ARig.StepFlameCombustion(0.18, Vector3(1.5, 0.0, 0.0));
  ARig.ProbeWallAndCeilingSoot(VP.Items);
  Result := True;
end;

class function TFlameFlickerHelper.ExportRigJson(
  const ARig: TCastleFlameFlickerRig): String;
var
  Obj: TJSONObject;
begin
  if ARig = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ARig.Preset));
    Obj.Add('base_kelvin', ARig.BaseKelvin);
    Obj.Add('kelvin_span', ARig.KelvinFlickerSpan);
    Obj.Add('base_intensity', ARig.BaseIntensity);
    Obj.Add('flicker_amp', ARig.FlickerAmplitude01);
    Obj.Add('blowout_mps', ARig.BlowoutWindSpeedMps);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TFlameFlickerHelper.ImportRigJson(
  const ARig: TCastleFlameFlickerRig; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ARig = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(ARig.Preset));
    if (POrd >= Ord(Low(TFlameFlickerPreset))) and
       (POrd <= Ord(High(TFlameFlickerPreset))) then
      ARig.ApplyPreset(TFlameFlickerPreset(POrd));
    ARig.BaseKelvin := Obj.Get('base_kelvin', ARig.BaseKelvin);
    ARig.KelvinFlickerSpan := Obj.Get('kelvin_span', ARig.KelvinFlickerSpan);
    ARig.BaseIntensity := Obj.Get('base_intensity', ARig.BaseIntensity);
    ARig.FlickerAmplitude01 := Obj.Get('flicker_amp', ARig.FlickerAmplitude01);
    ARig.BlowoutWindSpeedMps := Obj.Get('blowout_mps', ARig.BlowoutWindSpeedMps);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TFlameFlickerHelper.GenerateMarkdownReport(
  const ARig: TCastleFlameFlickerRig): String;
var
  SL: TStringList;
  S: TFlameFlickerSample;
  Soot: TWallSootProbeResult;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Procedural Torch Blackbody Flicker, Gust Blowout & Soot Report');
    SL.Add('');
    if ARig = nil then
    begin
      SL.Add('_No `TCastleFlameFlickerRig` found in the current design._');
      Exit(SL.Text);
    end;
    S := ARig.LastSample;
    Soot := ARig.LastSoot;
    SL.Add('- **Rig**: `' + ARig.Name + '` (`' +
      FlameFlickerPresetToString(ARig.Preset) + '`)');
    SL.Add(FormatDot('- **Lit State**: `%s` (Blowout Gust >= `%.1f m/s`)',
      [BoolToStr(ARig.IsLit, True), ARig.BlowoutWindSpeedMps]));
    SL.Add(FormatDot('- **Planckian Color Temp**: `%.0f K` -> RGB `(%.2f, %.2f, %.2f)`',
      [S.CurrentKelvin, S.BlackbodyRgb.X, S.BlackbodyRgb.Y, S.BlackbodyRgb.Z]));
    SL.Add(FormatDot('- **Combustion Intensity**: `%.2fx` | **Smoke Puff**: `%.0f%%`',
      [S.IntensityMultiplier, S.SmokePuffAlpha01 * 100.0]));
    SL.Add(FormatDot('- **WorldRay Soot Surfaces**: `%d` (Wall Darkening `%.0f%%`, Ceiling Darkening `%.0f%%`)',
      [Soot.SootSurfaceCount, Soot.WallSootDarkening01 * 100.0,
       Soot.CeilingSootDarkening01 * 100.0]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
