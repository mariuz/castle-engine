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

{ Design-time helper for Procedural Spiderweb, Radial WorldRay Wall Mooring,
  Logarithmic Capture Spiral & Dewdrop Silk Studio (Phase 392). }
unit ToolSpiderweb;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleSpiderweb;

type
  TSpiderwebHelper = class
  public
    class function FindFirstWeb(const ARoot: TComponent): TCastleSpiderwebGenerator;
    class function SpawnDungeonArchwayWebDemo(const ARoot, AOwner: TComponent;
      out AWeb: TCastleSpiderwebGenerator): Boolean;
    class function ExportWebJson(const AWeb: TCastleSpiderwebGenerator): String;
    class function ImportWebJson(const AWeb: TCastleSpiderwebGenerator;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AWeb: TCastleSpiderwebGenerator): String;
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

class function TSpiderwebHelper.FindFirstWeb(
  const ARoot: TComponent): TCastleSpiderwebGenerator;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleSpiderwebGenerator;
  var
    J: Integer;
  begin
    if T is TCastleSpiderwebGenerator then
      Exit(TCastleSpiderwebGenerator(T));
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
  if ARoot is TCastleSpiderwebGenerator then
    Exit(TCastleSpiderwebGenerator(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleSpiderwebGenerator then
      Exit(TCastleSpiderwebGenerator(ARoot.Components[I]));
end;

class function TSpiderwebHelper.SpawnDungeonArchwayWebDemo(
  const ARoot, AOwner: TComponent; out AWeb: TCastleSpiderwebGenerator): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;

  procedure AddFrameBox(const AName: String; const ASize, APos: TVector3);
  var
    B: TCastleBox;
  begin
    B := TCastleBox.Create(Own);
    B.Name := AName;
    B.Size := ASize;
    B.Translation := APos;
    B.Color := Vector4(0.34, 0.35, 0.38, 1.0);
    VP.Items.Add(B);
  end;

begin
  Result := False;
  AWeb := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Rectangular 3.6m x 3.4m stone dungeon archway framing XY plane }
  AddFrameBox('ArchwayFloorSill',   Vector3(4.4, 0.4, 1.2), Vector3(0.0, -0.2, 0.0));
  AddFrameBox('ArchwayCeilingLintel', Vector3(4.4, 0.4, 1.2), Vector3(0.0, 3.4, 0.0));
  AddFrameBox('ArchwayPillarWest',  Vector3(0.5, 3.6, 1.2), Vector3(-1.95, 1.6, 0.0));
  AddFrameBox('ArchwayPillarEast',  Vector3(0.5, 3.6, 1.2), Vector3( 1.95, 1.6, 0.0));

  AWeb := TCastleSpiderwebGenerator.Create(Own);
  AWeb.Name := 'CryptArchSpiderweb';
  AWeb.Translation := Vector3(0.45, 2.25, 0.0);
  AWeb.ApplyPreset(swpSymmetricGardenOrbWeb);
  VP.Items.Add(AWeb);

  AWeb.WeaveSpiderwebOnWorld(VP.Items);
  Result := True;
end;

class function TSpiderwebHelper.ExportWebJson(
  const AWeb: TCastleSpiderwebGenerator): String;
var
  Obj: TJSONObject;
begin
  if AWeb = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AWeb.Preset));
    Obj.Add('spokeCount', AWeb.SpokeCount);
    Obj.Add('spiralTurnCount', AWeb.SpiralTurnCount);
    Obj.Add('maxAnchorSearchRadiusMeters', AWeb.MaxAnchorSearchRadiusMeters);
    Obj.Add('silkGravitySagMeters', AWeb.SilkGravitySagMeters);
    Obj.Add('tornSectorRatio01', AWeb.TornSectorRatio01);
    Obj.Add('dewdropDensity01', AWeb.DewdropDensity01);
    Obj.Add('randomSeed', AWeb.RandomSeed);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TSpiderwebHelper.ImportWebJson(
  const AWeb: TCastleSpiderwebGenerator; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AWeb = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(AWeb.Preset));
    if (POrd >= Ord(Low(TSpiderwebPreset))) and (POrd <= Ord(High(TSpiderwebPreset))) then
      AWeb.Preset := TSpiderwebPreset(POrd);
    AWeb.SpokeCount := Obj.Get('spokeCount', AWeb.SpokeCount);
    AWeb.SpiralTurnCount := Obj.Get('spiralTurnCount', AWeb.SpiralTurnCount);
    AWeb.MaxAnchorSearchRadiusMeters := Obj.Get('maxAnchorSearchRadiusMeters', AWeb.MaxAnchorSearchRadiusMeters);
    AWeb.SilkGravitySagMeters := Obj.Get('silkGravitySagMeters', AWeb.SilkGravitySagMeters);
    AWeb.TornSectorRatio01 := Obj.Get('tornSectorRatio01', AWeb.TornSectorRatio01);
    AWeb.DewdropDensity01 := Obj.Get('dewdropDensity01', AWeb.DewdropDensity01);
    AWeb.RandomSeed := Obj.Get('randomSeed', AWeb.RandomSeed);
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TSpiderwebHelper.GenerateMarkdownReport(
  const AWeb: TCastleSpiderwebGenerator): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Procedural Orb-Weaver Spiderweb & Wall-Mooring Report');
    SL.Add('');
    if AWeb = nil then
    begin
      SL.Add('_No `TCastleSpiderwebGenerator` found in the active design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Generator**: `' + AWeb.Name + '` (`' +
      SpiderwebPresetToString(AWeb.Preset) + '`)');
    SL.Add(FormatDot('- **Wall-Moored Spokes**: `%d / %d` (`%d` spiral turns, Sag `%.3f m`)',
      [AWeb.AnchoredSpokeCount, AWeb.SpokeCount, AWeb.SpiralTurnCount,
       AWeb.SilkGravitySagMeters]));
    SL.Add(FormatDot('- **Woven Geometry**: `%d` silk segments, `%d` morning dewdrops (Torn `%.0f%%`)',
      [AWeb.SilkSegmentCount, AWeb.DewdropCount, AWeb.TornSectorRatio01 * 100.0]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
