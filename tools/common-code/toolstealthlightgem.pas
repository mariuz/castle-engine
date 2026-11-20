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

{ Design-time helper for Tactical Stealth Light-Gem Meter, WorldRay Shadow
  Occlusion & Backlight Silhouette Studio (Phase 402). }
unit ToolStealthLightGem;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleStealthLightGem;

type
  TStealthLightGemHelper = class
  public
    class function FindFirstGem(const ARoot: TComponent): TCastleStealthLightGem;
    class function SpawnGothicCloisterStealthDemo(const ARoot, AOwner: TComponent;
      out AGem: TCastleStealthLightGem): Boolean;
    class function ExportGemJson(const AGem: TCastleStealthLightGem): String;
    class function ImportGemJson(const AGem: TCastleStealthLightGem;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AGem: TCastleStealthLightGem): String;
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

class function TStealthLightGemHelper.FindFirstGem(
  const ARoot: TComponent): TCastleStealthLightGem;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleStealthLightGem;
  var
    J: Integer;
  begin
    if T is TCastleStealthLightGem then
      Exit(TCastleStealthLightGem(T));
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
  if ARoot is TCastleStealthLightGem then
    Exit(TCastleStealthLightGem(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleStealthLightGem then
      Exit(TCastleStealthLightGem(ARoot.Components[I]));
end;

class function TStealthLightGemHelper.SpawnGothicCloisterStealthDemo(
  const ARoot, AOwner: TComponent; out AGem: TCastleStealthLightGem): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  Pillar: TCastleBox;
begin
  Result := False;
  AGem := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Stone cloister pillar at (0, 1.5, 0) casting shadow along -Z from North Torch at Z = +4.0 }
  Pillar := TCastleBox.Create(Own);
  Pillar.Name := 'CloisterShadowPillar';
  Pillar.Size := Vector3(1.6, 3.2, 1.2);
  Pillar.Translation := Vector3(0.0, 1.6, 0.0);
  Pillar.Color := Vector4(0.32, 0.34, 0.38, 1.0);
  VP.Items.Add(Pillar);

  AGem := TCastleStealthLightGem.Create(Own);
  AGem.Name := 'ThiefStealthLightGem';
  AGem.ApplyPreset(slpMasterThiefShadowCloak);
  AGem.Translation := Vector3(0.0, 1.2, -2.2);
  { North wall sconce at Z = +4.0 (blocked by CloisterShadowPillar at Z = -2.2,
    fully exposed at X = +3.5) }
  AGem.AddPointTorch('NorthCourtyardSconce', Vector3(0.0, 2.0, 4.0), 2.4, 14.0);
  { Far South archway brazier at Z = -10.0 for backlight silhouette testing }
  AGem.AddPointTorch('FarArchwayBrazier', Vector3(3.5, 1.8, -10.0), 1.8, 7.0);
  VP.Items.Add(AGem);

  AGem.EvaluateLightGem(VP.Items, Vector3(0.0, 1.2, -2.2),
    Vector3(-5.0, 1.7, -2.2), True, True);
  Result := True;
end;

class function TStealthLightGemHelper.ExportGemJson(
  const AGem: TCastleStealthLightGem): String;
var
  Obj: TJSONObject;
begin
  if AGem = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AGem.Preset));
    Obj.Add('ambient_floor', AGem.AmbientMoonlightFloor01);
    Obj.Add('crouch_mult', AGem.CrouchConcealmentMultiplier);
    Obj.Add('still_mult', AGem.StillnessConcealmentMultiplier);
    Obj.Add('backlight_gain', AGem.BacklightSilhouetteGain);
    Obj.Add('backlight_cone_deg', AGem.BacklightAlignmentConeDeg);
    Obj.Add('alert_threshold', AGem.AlertThreshold01);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TStealthLightGemHelper.ImportGemJson(
  const AGem: TCastleStealthLightGem; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AGem = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(AGem.Preset));
    if (POrd >= Ord(Low(TStealthLightGemPreset))) and
       (POrd <= Ord(High(TStealthLightGemPreset))) then
      AGem.ApplyPreset(TStealthLightGemPreset(POrd));
    AGem.AmbientMoonlightFloor01 := Obj.Get('ambient_floor', AGem.AmbientMoonlightFloor01);
    AGem.CrouchConcealmentMultiplier := Obj.Get('crouch_mult', AGem.CrouchConcealmentMultiplier);
    AGem.StillnessConcealmentMultiplier := Obj.Get('still_mult', AGem.StillnessConcealmentMultiplier);
    AGem.BacklightSilhouetteGain := Obj.Get('backlight_gain', AGem.BacklightSilhouetteGain);
    AGem.BacklightAlignmentConeDeg := Obj.Get('backlight_cone_deg', AGem.BacklightAlignmentConeDeg);
    AGem.AlertThreshold01 := Obj.Get('alert_threshold', AGem.AlertThreshold01);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TStealthLightGemHelper.GenerateMarkdownReport(
  const AGem: TCastleStealthLightGem): String;
var
  SL: TStringList;
  S: TStealthLightGemSample;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Tactical Stealth Light-Gem & Backlight Silhouette Report');
    SL.Add('');
    if AGem = nil then
    begin
      SL.Add('_No `TCastleStealthLightGem` found in the current design._');
      Exit(SL.Text);
    end;
    S := AGem.LastSample;
    SL.Add('- **Sensor**: `' + AGem.Name + '` (`' +
      StealthLightGemPresetToString(AGem.Preset) + '`)');
    SL.Add(FormatDot('- **Registered Torches**: `%d` (`%d` visible, `%d` WorldRay-shadowed)',
      [AGem.TorchCount, S.VisibleTorchCount, S.ShadowedTorchCount]));
    SL.Add(FormatDot('- **Direct Illumination**: `%.1f%%`',
      [S.DirectIllumination01 * 100.0]));
    SL.Add(FormatDot('- **Backlight Silhouette Contrast**: `%.1f%%`',
      [S.BacklightSilhouette01 * 100.0]));
    SL.Add(FormatDot('- **Stance Concealment Multiplier**: `%.2fx`',
      [S.StanceConcealmentScale]));
    SL.Add(FormatDot('- **Final Light-Gem Visibility**: **`%.1f%%`** (Alert >= `%.0f%%`)',
      [S.FinalVisibilityGem01 * 100.0, AGem.AlertThreshold01 * 100.0]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
