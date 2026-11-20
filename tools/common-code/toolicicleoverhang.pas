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

{ Design-time helper for Procedural Icicle, Stalactite & Cave Drip Overhang
  Studio (Phase 397). }
unit ToolIcicleOverhang;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleIcicleOverhang;

type
  TIcicleOverhangHelper = class
  public
    class function FindFirstOverhang(const ARoot: TComponent): TCastleIcicleOverhang;
    class function SpawnCavernOverhangDemo(const ARoot, AOwner: TComponent;
      out AOverhang: TCastleIcicleOverhang): Boolean;
    class function ExportOverhangJson(const AOverhang: TCastleIcicleOverhang): String;
    class function ImportOverhangJson(const AOverhang: TCastleIcicleOverhang;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AOverhang: TCastleIcicleOverhang): String;
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

class function TIcicleOverhangHelper.FindFirstOverhang(
  const ARoot: TComponent): TCastleIcicleOverhang;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleIcicleOverhang;
  var
    J: Integer;
  begin
    if T is TCastleIcicleOverhang then
      Exit(TCastleIcicleOverhang(T));
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
  if ARoot is TCastleIcicleOverhang then
    Exit(TCastleIcicleOverhang(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleIcicleOverhang then
      Exit(TCastleIcicleOverhang(ARoot.Components[I]));
end;

class function TIcicleOverhangHelper.SpawnCavernOverhangDemo(
  const ARoot, AOwner: TComponent; out AOverhang: TCastleIcicleOverhang): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  CaveFloor, HalfRoofLedge: TCastleBox;
begin
  Result := False;
  AOverhang := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  CaveFloor := TCastleBox.Create(Own);
  CaveFloor.Name := 'CavernFloorShelf';
  CaveFloor.Size := Vector3(14.0, 0.4, 12.0);
  CaveFloor.Translation := Vector3(0.0, -0.2, 0.0);
  CaveFloor.Color := Vector4(0.32, 0.30, 0.28, 1.0);
  VP.Items.Add(CaveFloor);

  { Overhang roof covers West half (X in [-6..+1]), leaving East half open sky! }
  HalfRoofLedge := TCastleBox.Create(Own);
  HalfRoofLedge.Name := 'CavernCeilingLedgeWest';
  HalfRoofLedge.Size := Vector3(7.0, 0.6, 10.0);
  HalfRoofLedge.Translation := Vector3(-2.5, 4.8, 0.0);
  HalfRoofLedge.Color := Vector4(0.42, 0.40, 0.36, 1.0);
  VP.Items.Add(HalfRoofLedge);

  AOverhang := TCastleIcicleOverhang.Create(Own);
  AOverhang.Name := 'CavernDripVolume';
  AOverhang.Translation := Vector3(0.0, 1.0, 0.0);
  AOverhang.ApplyPreset(iopLimestoneCaveStalactites);
  VP.Items.Add(AOverhang);

  AOverhang.GrowOverhangSpikes(VP.Items);
  Result := True;
end;

class function TIcicleOverhangHelper.ExportOverhangJson(
  const AOverhang: TCastleIcicleOverhang): String;
var
  Obj: TJSONObject;
begin
  if AOverhang = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AOverhang.Preset));
    Obj.Add('scanWidthMeters', AOverhang.ScanWidthMeters);
    Obj.Add('scanDepthMeters', AOverhang.ScanDepthMeters);
    Obj.Add('candidateProbeCount', AOverhang.CandidateProbeCount);
    Obj.Add('minSpikeLengthMeters', AOverhang.MinSpikeLengthMeters);
    Obj.Add('maxSpikeLengthMeters', AOverhang.MaxSpikeLengthMeters);
    Obj.Add('baseRadiusMeters', AOverhang.BaseRadiusMeters);
    Obj.Add('spawnFloorStalagmites', AOverhang.SpawnFloorStalagmites);
    Obj.Add('randomSeed', AOverhang.RandomSeed);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TIcicleOverhangHelper.ImportOverhangJson(
  const AOverhang: TCastleIcicleOverhang; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AOverhang = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(AOverhang.Preset));
    if (POrd >= Ord(Low(TIcicleOverhangPreset))) and
       (POrd <= Ord(High(TIcicleOverhangPreset))) then
      AOverhang.Preset := TIcicleOverhangPreset(POrd);
    AOverhang.ScanWidthMeters := Obj.Get('scanWidthMeters', AOverhang.ScanWidthMeters);
    AOverhang.ScanDepthMeters := Obj.Get('scanDepthMeters', AOverhang.ScanDepthMeters);
    AOverhang.CandidateProbeCount := Obj.Get('candidateProbeCount', AOverhang.CandidateProbeCount);
    AOverhang.MinSpikeLengthMeters := Obj.Get('minSpikeLengthMeters', AOverhang.MinSpikeLengthMeters);
    AOverhang.MaxSpikeLengthMeters := Obj.Get('maxSpikeLengthMeters', AOverhang.MaxSpikeLengthMeters);
    AOverhang.BaseRadiusMeters := Obj.Get('baseRadiusMeters', AOverhang.BaseRadiusMeters);
    AOverhang.SpawnFloorStalagmites := Obj.Get('spawnFloorStalagmites', AOverhang.SpawnFloorStalagmites);
    AOverhang.RandomSeed := Obj.Get('randomSeed', AOverhang.RandomSeed);
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TIcicleOverhangHelper.GenerateMarkdownReport(
  const AOverhang: TCastleIcicleOverhang): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Procedural Icicle, Stalactite & Cave Drip Overhang Report');
    SL.Add('');
    if AOverhang = nil then
    begin
      SL.Add('_No `TCastleIcicleOverhang` found in the active design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Overhang Volume**: `' + AOverhang.Name + '` (`' +
      IciclePresetToString(AOverhang.Preset) + '`)');
    SL.Add(FormatDot('- **Scan Box**: `%.1f m x %.1f m` (`%d` ceiling probes)',
      [AOverhang.ScanWidthMeters, AOverhang.ScanDepthMeters, AOverhang.CandidateProbeCount]));
    SL.Add(FormatDot('- **Generated Formations**: `%d` hanging spikes, `%d` paired floor stalagmites',
      [AOverhang.SpikeCount, AOverhang.PairedStalagmiteCount]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
