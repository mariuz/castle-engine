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

{ Design-time helper for Procedural Rope Suspension Bridge, Live-Load Plank
  Deflection, Roll Tilt & Broken-Slat Hazard Studio (Phase 389). }
unit ToolSuspensionBridge;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleSuspensionBridge;

type
  TSuspensionBridgeHelper = class
  public
    class function FindFirstBridge(const ARoot: TComponent): TCastleSuspensionBridge;
    class function SpawnChasmBridgeDemo(const ARoot, AOwner: TComponent;
      out ABridge: TCastleSuspensionBridge): Boolean;
    class function ExportBridgeJson(const ABridge: TCastleSuspensionBridge): String;
    class function ImportBridgeJson(const ABridge: TCastleSuspensionBridge;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ABridge: TCastleSuspensionBridge): String;
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

class function TSuspensionBridgeHelper.FindFirstBridge(
  const ARoot: TComponent): TCastleSuspensionBridge;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleSuspensionBridge;
  var
    J: Integer;
  begin
    if T is TCastleSuspensionBridge then
      Exit(TCastleSuspensionBridge(T));
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
  if ARoot is TCastleSuspensionBridge then
    Exit(TCastleSuspensionBridge(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleSuspensionBridge then
      Exit(TCastleSuspensionBridge(ARoot.Components[I]));
end;

class function TSuspensionBridgeHelper.SpawnChasmBridgeDemo(
  const ARoot, AOwner: TComponent; out ABridge: TCastleSuspensionBridge): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  CliffNorth, CliffSouth: TCastleBox;
begin
  Result := False;
  ABridge := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  CliffSouth := TCastleBox.Create(Own);
  CliffSouth.Name := 'ChasmAbutmentSouth';
  CliffSouth.Size := Vector3(8.0, 6.0, 4.0);
  CliffSouth.Translation := Vector3(0.0, 1.0, 2.0);
  CliffSouth.Color := Vector4(0.38, 0.35, 0.31, 1.0);
  VP.Items.Add(CliffSouth);

  CliffNorth := TCastleBox.Create(Own);
  CliffNorth.Name := 'ChasmAbutmentNorth';
  CliffNorth.Size := Vector3(8.0, 6.0, 4.0);
  CliffNorth.Translation := Vector3(0.0, 1.0, -26.0);
  CliffNorth.Color := Vector4(0.38, 0.35, 0.31, 1.0);
  VP.Items.Add(CliffNorth);

  ABridge := TCastleSuspensionBridge.Create(Own);
  ABridge.Name := 'JungleChasmSpan';
  ABridge.Translation := Vector3(0.0, 4.0, 0.0);
  ABridge.ApplyPreset(sbpJungleVineFootbridge);
  VP.Items.Add(ABridge);
  ABridge.RebuildBridge;
  Result := True;
end;

class function TSuspensionBridgeHelper.ExportBridgeJson(
  const ABridge: TCastleSuspensionBridge): String;
var
  Obj: TJSONObject;
begin
  if ABridge = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ABridge.Preset));
    Obj.Add('spanLengthMeters', ABridge.SpanLengthMeters);
    Obj.Add('endElevationDeltaY', ABridge.EndElevationDeltaY);
    Obj.Add('deckWidthMeters', ABridge.DeckWidthMeters);
    Obj.Add('plankCount', ABridge.PlankCount);
    Obj.Add('baseSagRatio', ABridge.BaseSagRatio);
    Obj.Add('cableTensionStiffnessNPerM', ABridge.CableTensionStiffnessNPerM);
    Obj.Add('brokenPlankRatio01', ABridge.BrokenPlankRatio01);
    Obj.Add('randomSeed', ABridge.RandomSeed);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TSuspensionBridgeHelper.ImportBridgeJson(
  const ABridge: TCastleSuspensionBridge; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ABridge = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(ABridge.Preset));
    if (POrd >= Ord(Low(TSuspensionBridgePreset))) and
       (POrd <= Ord(High(TSuspensionBridgePreset))) then
      ABridge.Preset := TSuspensionBridgePreset(POrd);
    ABridge.SpanLengthMeters := Obj.Get('spanLengthMeters', ABridge.SpanLengthMeters);
    ABridge.EndElevationDeltaY := Obj.Get('endElevationDeltaY', ABridge.EndElevationDeltaY);
    ABridge.DeckWidthMeters := Obj.Get('deckWidthMeters', ABridge.DeckWidthMeters);
    ABridge.PlankCount := Obj.Get('plankCount', ABridge.PlankCount);
    ABridge.BaseSagRatio := Obj.Get('baseSagRatio', ABridge.BaseSagRatio);
    ABridge.CableTensionStiffnessNPerM := Obj.Get('cableTensionStiffnessNPerM', ABridge.CableTensionStiffnessNPerM);
    ABridge.BrokenPlankRatio01 := Obj.Get('brokenPlankRatio01', ABridge.BrokenPlankRatio01);
    ABridge.RandomSeed := Obj.Get('randomSeed', ABridge.RandomSeed);
    ABridge.RebuildBridge;
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TSuspensionBridgeHelper.GenerateMarkdownReport(
  const ABridge: TCastleSuspensionBridge): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Procedural Rope Suspension Bridge & Live-Load Deflection Report');
    SL.Add('');
    if ABridge = nil then
    begin
      SL.Add('_No `TCastleSuspensionBridge` found in the active design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Bridge Name**: `' + ABridge.Name + '` (`' +
      SuspensionBridgePresetToString(ABridge.Preset) + '`)');
    SL.Add(FormatDot('- **Span / Width**: `%.1f m` x `%.2f m` (`%d` intact planks, `%d` broken gaps)',
      [ABridge.SpanLengthMeters, ABridge.DeckWidthMeters,
       ABridge.IntactPlankCount, ABridge.BrokenGapCount]));
    SL.Add(FormatDot('- **Max Total Sag + Live Deflection**: `%.3f m` (Live Load Active: `%s`, `%.1f kg` at `t=%.2f`)',
      [ABridge.MaxTotalDropMeters, BoolToStr(ABridge.HasLiveLoad, True),
       ABridge.LoadMassKg, ABridge.LoadNormalizedT]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
