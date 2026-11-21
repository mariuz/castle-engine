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

{ Design-time helper for Granular Rockslide, Talus Scree Cone &
  Angle-of-Repose Avalanche Studio (Phase 408). }
unit ToolAvalancheSlide;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleAvalancheSlide;

type
  TAvalancheSlideHelper = class
  public
    class function FindFirstSlide(const ARoot: TComponent): TCastleAvalancheSlide;
    class function SpawnMountainChuteWithBermDemo(const ARoot, AOwner: TComponent;
      out ASlide: TCastleAvalancheSlide): Boolean;
    class function ExportSlideJson(const ASlide: TCastleAvalancheSlide): String;
    class function ImportSlideJson(const ASlide: TCastleAvalancheSlide;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ASlide: TCastleAvalancheSlide): String;
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

class function TAvalancheSlideHelper.FindFirstSlide(
  const ARoot: TComponent): TCastleAvalancheSlide;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleAvalancheSlide;
  var
    J: Integer;
  begin
    if T is TCastleAvalancheSlide then
      Exit(TCastleAvalancheSlide(T));
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
  if ARoot is TCastleAvalancheSlide then
    Exit(TCastleAvalancheSlide(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleAvalancheSlide then
      Exit(TCastleAvalancheSlide(ARoot.Components[I]));
end;

class function TAvalancheSlideHelper.SpawnMountainChuteWithBermDemo(
  const ARoot, AOwner: TComponent; out ASlide: TCastleAvalancheSlide): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  ValleyFloor, DeflectionBerm: TCastleBox;
begin
  Result := False;
  ASlide := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  ValleyFloor := TCastleBox.Create(Own);
  ValleyFloor.Name := 'AvalancheValleyRoadbed';
  ValleyFloor.Size := Vector3(26.0, 0.4, 8.0);
  ValleyFloor.Translation := Vector3(12.0, -0.2, 0.0);
  ValleyFloor.Color := Vector4(0.30, 0.34, 0.28, 1.0);
  VP.Items.Add(ValleyFloor);

  { Concrete avalanche retention wall at X = 15.5m (Bin 15), height 6.0m }
  DeflectionBerm := TCastleBox.Create(Own);
  DeflectionBerm.Name := 'ConcreteSnowShedBerm';
  DeflectionBerm.Size := Vector3(1.4, 6.0, 8.0);
  DeflectionBerm.Translation := Vector3(15.5, 3.0, 0.0);
  DeflectionBerm.Color := Vector4(0.55, 0.56, 0.60, 1.0);
  VP.Items.Add(DeflectionBerm);

  ASlide := TCastleAvalancheSlide.Create(Own);
  ASlide.Name := 'AlpineGraniteRockslide';
  ASlide.ApplyPreset(aspGraniteTalusRockslide);
  VP.Items.Add(ASlide);
  Result := True;
end;

class function TAvalancheSlideHelper.ExportSlideJson(
  const ASlide: TCastleAvalancheSlide): String;
var
  Obj: TJSONObject;
begin
  if ASlide = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ASlide.Preset));
    Obj.Add('length_m', ASlide.ChuteLengthMeters);
    Obj.Add('width_m', ASlide.ChuteWidthMeters);
    Obj.Add('repose_deg', ASlide.AngleOfReposeDeg);
    Obj.Add('mobility', ASlide.FlowMobility01);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TAvalancheSlideHelper.ImportSlideJson(
  const ASlide: TCastleAvalancheSlide; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ASlide = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(ASlide.Preset));
    if (POrd >= Ord(Low(TAvalancheSlidePreset))) and
       (POrd <= Ord(High(TAvalancheSlidePreset))) then
      ASlide.ApplyPreset(TAvalancheSlidePreset(POrd));
    ASlide.ChuteLengthMeters := Obj.Get('length_m', ASlide.ChuteLengthMeters);
    ASlide.ChuteWidthMeters := Obj.Get('width_m', ASlide.ChuteWidthMeters);
    ASlide.AngleOfReposeDeg := Obj.Get('repose_deg', ASlide.AngleOfReposeDeg);
    ASlide.FlowMobility01 := Obj.Get('mobility', ASlide.FlowMobility01);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TAvalancheSlideHelper.GenerateMarkdownReport(
  const ASlide: TCastleAvalancheSlide): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Granular Rockslide, Talus Scree & Avalanche Runout Report');
    SL.Add('');
    if ASlide = nil then
    begin
      SL.Add('_No `TCastleAvalancheSlide` found in the current design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Chute**: `' + ASlide.Name + '` (`' +
      AvalancheSlidePresetToString(ASlide.Preset) + '`)');
    SL.Add(FormatDot('- **Angle of Repose / Mobility**: `%.1f deg` / `%.2f`',
      [ASlide.AngleOfReposeDeg, ASlide.FlowMobility01]));
    SL.Add(FormatDot('- **Conserved Debris Volume**: `%.2f m^3`',
      [ASlide.TotalDebrisVolumeCubicMeters]));
    SL.Add(FormatDot('- **Toe Runout Distance**: `%.2f m`   |   **Max Active Talus Slope**: `%.1f deg`',
      [ASlide.MaxRunoutDistanceMeters, ASlide.MaxActiveSlopeDeg]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
