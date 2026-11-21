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

{ Design-time helper for Procedural Rain Puddle, Roof Shelter, Specular
  Wetness & Splash Ripple Studio (Phase 407). }
unit ToolPuddleWetness;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastlePuddleWetness;

type
  TPuddleWetnessHelper = class
  public
    class function FindFirstField(const ARoot: TComponent): TCastlePuddleWetnessField;
    class function SpawnCobblestonePorchStormDemo(const ARoot, AOwner: TComponent;
      out AField: TCastlePuddleWetnessField): Boolean;
    class function ExportFieldJson(const AField: TCastlePuddleWetnessField): String;
    class function ImportFieldJson(const AField: TCastlePuddleWetnessField;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AField: TCastlePuddleWetnessField): String;
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

class function TPuddleWetnessHelper.FindFirstField(
  const ARoot: TComponent): TCastlePuddleWetnessField;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastlePuddleWetnessField;
  var
    J: Integer;
  begin
    if T is TCastlePuddleWetnessField then
      Exit(TCastlePuddleWetnessField(T));
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
  if ARoot is TCastlePuddleWetnessField then
    Exit(TCastlePuddleWetnessField(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastlePuddleWetnessField then
      Exit(TCastlePuddleWetnessField(ARoot.Components[I]));
end;

class function TPuddleWetnessHelper.SpawnCobblestonePorchStormDemo(
  const ARoot, AOwner: TComponent; out AField: TCastlePuddleWetnessField): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  CobbleFloor, PorchAwning: TCastleBox;
begin
  Result := False;
  AField := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  CobbleFloor := TCastleBox.Create(Own);
  CobbleFloor.Name := 'AlleyCobblestonePavement';
  CobbleFloor.Size := Vector3(18.0, 0.3, 18.0);
  CobbleFloor.Translation := Vector3(0.0, -0.15, 0.0);
  CobbleFloor.Color := Vector4(0.32, 0.33, 0.36, 1.0);
  VP.Items.Add(CobbleFloor);

  { Wooden tavern porch awning sheltering X in [+3.5..+8.5], Z in [-3.0..+3.0] at Y = 3.2m }
  PorchAwning := TCastleBox.Create(Own);
  PorchAwning.Name := 'TavernRainShelterAwning';
  PorchAwning.Size := Vector3(5.0, 0.25, 6.0);
  PorchAwning.Translation := Vector3(6.0, 3.2, 0.0);
  PorchAwning.Color := Vector4(0.42, 0.28, 0.18, 1.0);
  VP.Items.Add(PorchAwning);

  AField := TCastlePuddleWetnessField.Create(Own);
  AField.Name := 'AlleyStormPuddleField';
  AField.ApplyPreset(pwpCobblestoneAlleyStorm);
  VP.Items.Add(AField);

  AField.TriggerSplashAtWorld(TVector3.Zero, 5.0, 1.8);
  Result := True;
end;

class function TPuddleWetnessHelper.ExportFieldJson(
  const AField: TCastlePuddleWetnessField): String;
var
  Obj: TJSONObject;
begin
  if AField = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AField.Preset));
    Obj.Add('width_m', AField.FieldWidthMeters);
    Obj.Add('depth_m', AField.FieldDepthMeters);
    Obj.Add('fill_01', AField.WaterFillLevel01);
    Obj.Add('wetness_01', AField.RainWetness01);
    Obj.Add('dry_rough', AField.DryRoughness);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TPuddleWetnessHelper.ImportFieldJson(
  const AField: TCastlePuddleWetnessField; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AField = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(AField.Preset));
    if (POrd >= Ord(Low(TPuddleWetnessPreset))) and
       (POrd <= Ord(High(TPuddleWetnessPreset))) then
      AField.ApplyPreset(TPuddleWetnessPreset(POrd));
    AField.FieldWidthMeters := Obj.Get('width_m', AField.FieldWidthMeters);
    AField.FieldDepthMeters := Obj.Get('depth_m', AField.FieldDepthMeters);
    AField.WaterFillLevel01 := Obj.Get('fill_01', AField.WaterFillLevel01);
    AField.RainWetness01 := Obj.Get('wetness_01', AField.RainWetness01);
    AField.DryRoughness := Obj.Get('dry_rough', AField.DryRoughness);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TPuddleWetnessHelper.GenerateMarkdownReport(
  const AField: TCastlePuddleWetnessField): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Procedural Rain Puddle, Roof Shelter & Splash Ripple Report');
    SL.Add('');
    if AField = nil then
    begin
      SL.Add('_No `TCastlePuddleWetnessField` found in the current design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Field**: `' + AField.Name + '` (`' +
      PuddleWetnessPresetToString(AField.Preset) + '`)');
    SL.Add(FormatDot('- **Footprint**: `%.1f m x %.1f m` (Max Basin `%.1f mm`)',
      [AField.FieldWidthMeters, AField.FieldDepthMeters,
       AField.MaxBasinDepthMeters * 1000.0]));
    SL.Add(FormatDot('- **Puddle Fill / Rain Wetness**: `%.0f%%` / `%.0f%%`',
      [AField.WaterFillLevel01 * 100.0, AField.RainWetness01 * 100.0]));
    SL.Add(FormatDot('- **Dry Roughness / Porous Darkening**: `%.2f` / `%.0f%%`',
      [AField.DryRoughness, AField.PorousDarkeningStrength01 * 100.0]));
    SL.Add(Format('- **Active Splash Ripples**: `%d / %d`',
      [AField.ActiveRippleCount, MaxPooledPuddleRipples]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
