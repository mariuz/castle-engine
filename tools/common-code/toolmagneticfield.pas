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

{ Design-time helper for 3D Magnetic Dipole, Ferromagnetic Snap, Zero-G
  Mag-Boots & Eddy-Current Brake Studio (Phase 409). }
unit ToolMagneticField;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleMagneticField;

type
  TMagneticFieldHelper = class
  public
    class function FindFirstMagnet(const ARoot: TComponent): TCastleMagneticField;
    class function SpawnSpacecraftHullMagBootDemo(const ARoot, AOwner: TComponent;
      out AMag: TCastleMagneticField): Boolean;
    class function ExportMagnetJson(const AMag: TCastleMagneticField): String;
    class function ImportMagnetJson(const AMag: TCastleMagneticField;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AMag: TCastleMagneticField): String;
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

class function TMagneticFieldHelper.FindFirstMagnet(
  const ARoot: TComponent): TCastleMagneticField;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleMagneticField;
  var
    J: Integer;
  begin
    if T is TCastleMagneticField then
      Exit(TCastleMagneticField(T));
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
  if ARoot is TCastleMagneticField then
    Exit(TCastleMagneticField(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleMagneticField then
      Exit(TCastleMagneticField(ARoot.Components[I]));
end;

class function TMagneticFieldHelper.SpawnSpacecraftHullMagBootDemo(
  const ARoot, AOwner: TComponent; out AMag: TCastleMagneticField): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  HullPlate: TCastleBox;
begin
  Result := False;
  AMag := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Inverted orbital hull ceiling plate at Y = 5.0m (underside at Y = 4.8m) }
  HullPlate := TCastleBox.Create(Own);
  HullPlate.Name := 'OrbitalSteelHullDeck';
  HullPlate.Size := Vector3(12.0, 0.4, 12.0);
  HullPlate.Translation := Vector3(0.0, 5.0, 0.0);
  HullPlate.Color := Vector4(0.42, 0.48, 0.56, 1.0);
  VP.Items.Add(HullPlate);

  AMag := TCastleMagneticField.Create(Own);
  AMag.Name := 'CoreMagneticDipole';
  AMag.ApplyPreset(mfpScrapyardElectromagnetCrane);
  VP.Items.Add(AMag);
  Result := True;
end;

class function TMagneticFieldHelper.ExportMagnetJson(
  const AMag: TCastleMagneticField): String;
var
  Obj: TJSONObject;
begin
  if AMag = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AMag.Preset));
    Obj.Add('energized', AMag.CoilEnergized);
    Obj.Add('dipole_moment', AMag.DipoleMomentAmpSqM);
    Obj.Add('eddy_gain', AMag.EddyConductivityGain);
    Obj.Add('snap_range_m', AMag.MagBootSnapRangeMeters);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TMagneticFieldHelper.ImportMagnetJson(
  const AMag: TCastleMagneticField; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AMag = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(AMag.Preset));
    if (POrd >= Ord(Low(TMagneticFieldPreset))) and
       (POrd <= Ord(High(TMagneticFieldPreset))) then
      AMag.ApplyPreset(TMagneticFieldPreset(POrd));
    AMag.CoilEnergized := Obj.Get('energized', AMag.CoilEnergized);
    AMag.DipoleMomentAmpSqM := Obj.Get('dipole_moment', AMag.DipoleMomentAmpSqM);
    AMag.EddyConductivityGain := Obj.Get('eddy_gain', AMag.EddyConductivityGain);
    AMag.MagBootSnapRangeMeters := Obj.Get('snap_range_m', AMag.MagBootSnapRangeMeters);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TMagneticFieldHelper.GenerateMarkdownReport(
  const AMag: TCastleMagneticField): String;
var
  SL: TStringList;
  BPole, BEq: TVector3;
begin
  SL := TStringList.Create;
  try
    SL.Add('# 3D Magnetic Dipole, Mag-Boots & Eddy-Current Brake Report');
    SL.Add('');
    if AMag = nil then
    begin
      SL.Add('_No `TCastleMagneticField` found in the current design._');
      Exit(SL.Text);
    end;
    BPole := AMag.SampleBFieldTeslaAtWorld(AMag.Translation + Vector3(0.0, 2.0, 0.0));
    BEq := AMag.SampleBFieldTeslaAtWorld(AMag.Translation + Vector3(2.0, 0.0, 0.0));
    SL.Add('- **Magnet**: `' + AMag.Name + '` (`' +
      MagneticFieldPresetToString(AMag.Preset) + '`)');
    SL.Add(FormatDot('- **Dipole Moment / Energized**: `%.2e A*m^2` / `%s`',
      [AMag.DipoleMomentAmpSqM, BoolToStr(AMag.CoilEnergized, True)]));
    SL.Add(FormatDot('- **Polar |B| @ 2.0m**: `%.4f T`   |   **Equatorial |B| @ 2.0m**: `%.4f T` (`2.0x` Dipole Ratio)',
      [BPole.Length, BEq.Length]));
    SL.Add(FormatDot('- **Lenz Eddy Brake Gain**: `%.1f`   |   **Mag-Boot Snap Range**: `%.2f m`',
      [AMag.EddyConductivityGain, AMag.MagBootSnapRangeMeters]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
