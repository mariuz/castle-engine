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

{ Design-time helper for Milestone Phase 400: Voronoi Fracture Cell Cutter,
  Bond Graph & BFS Ground-Support Collapse Studio. }
unit ToolFractureVoronoi;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleFractureVoronoi;

type
  TFractureVoronoiHelper = class
  public
    class function FindFirstVolume(const ARoot: TComponent): TCastleVoronoiFractureVolume;
    class function SpawnMasonryWallFractureDemo(const ARoot, AOwner: TComponent;
      out AVol: TCastleVoronoiFractureVolume): Boolean;
    class function ExportVolumeJson(const AVol: TCastleVoronoiFractureVolume): String;
    class function ImportVolumeJson(const AVol: TCastleVoronoiFractureVolume;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AVol: TCastleVoronoiFractureVolume): String;
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

class function TFractureVoronoiHelper.FindFirstVolume(
  const ARoot: TComponent): TCastleVoronoiFractureVolume;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleVoronoiFractureVolume;
  var
    J: Integer;
  begin
    if T is TCastleVoronoiFractureVolume then
      Exit(TCastleVoronoiFractureVolume(T));
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
  if ARoot is TCastleVoronoiFractureVolume then
    Exit(TCastleVoronoiFractureVolume(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleVoronoiFractureVolume then
      Exit(TCastleVoronoiFractureVolume(ARoot.Components[I]));
end;

class function TFractureVoronoiHelper.SpawnMasonryWallFractureDemo(
  const ARoot, AOwner: TComponent; out AVol: TCastleVoronoiFractureVolume): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  FoundationPlinth: TCastleBox;
begin
  Result := False;
  AVol := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  FoundationPlinth := TCastleBox.Create(Own);
  FoundationPlinth.Name := 'FractureFoundationSlab';
  FoundationPlinth.Size := Vector3(8.0, 0.3, 4.0);
  FoundationPlinth.Translation := Vector3(0.0, -0.15, 0.0);
  FoundationPlinth.Color := Vector4(0.32, 0.33, 0.36, 1.0);
  VP.Items.Add(FoundationPlinth);

  AVol := TCastleVoronoiFractureVolume.Create(Own);
  AVol.Name := 'CastleMasonryFractureWall';
  AVol.ApplyPreset(vfpBrittleMasonryWall);
  VP.Items.Add(AVol);
  Result := True;
end;

class function TFractureVoronoiHelper.ExportVolumeJson(
  const AVol: TCastleVoronoiFractureVolume): String;
var
  Obj: TJSONObject;
begin
  if AVol = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AVol.Preset));
    Obj.Add('wallX', AVol.WallDimensions.X);
    Obj.Add('wallY', AVol.WallDimensions.Y);
    Obj.Add('wallZ', AVol.WallDimensions.Z);
    Obj.Add('shardCount', AVol.ShardCount);
    Obj.Add('bondTensileStrengthNs', AVol.BondTensileStrengthNs);
    Obj.Add('foundationHeightMeters', AVol.FoundationHeightMeters);
    Obj.Add('randomSeed', AVol.RandomSeed);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TFractureVoronoiHelper.ImportVolumeJson(
  const AVol: TCastleVoronoiFractureVolume; const AJson: String): Boolean;
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
    if (POrd >= Ord(Low(TVoronoiFracturePreset))) and
       (POrd <= Ord(High(TVoronoiFracturePreset))) then
      AVol.Preset := TVoronoiFracturePreset(POrd);
    AVol.WallDimensions := Vector3(
      Obj.Get('wallX', AVol.WallDimensions.X),
      Obj.Get('wallY', AVol.WallDimensions.Y),
      Obj.Get('wallZ', AVol.WallDimensions.Z));
    AVol.BondTensileStrengthNs := Obj.Get('bondTensileStrengthNs', AVol.BondTensileStrengthNs);
    AVol.FoundationHeightMeters := Obj.Get('foundationHeightMeters', AVol.FoundationHeightMeters);
    AVol.RandomSeed := Obj.Get('randomSeed', AVol.RandomSeed);
    AVol.ShardCount := Obj.Get('shardCount', AVol.ShardCount);
    AVol.GenerateVoronoiShards;
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TFractureVoronoiHelper.GenerateMarkdownReport(
  const AVol: TCastleVoronoiFractureVolume): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Voronoi Destruction Fracture & BFS Ground-Connectivity Report');
    SL.Add('');
    if AVol = nil then
    begin
      SL.Add('_No `TCastleVoronoiFractureVolume` found in the active design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Fracture Volume**: `' + AVol.Name + '` (`' +
      VoronoiPresetToString(AVol.Preset) + '`)');
    SL.Add(FormatDot('- **Voronoi Partition**: `%d` shards, Total Volume `%.3f m^3`',
      [AVol.ActualShardCount, AVol.TotalVolumeM3]));
    SL.Add(Format('- **Structural Bond Graph**: `%d` intact / `%d` broken (`%d` total bonds)',
      [AVol.IntactBondCount, AVol.BrokenBondCount, AVol.TotalBondCount]));
    SL.Add(Format('- **BFS Ground Connectivity**: `%d` supported shards, `%d` detached falling chunks',
      [AVol.SupportedShardCount, AVol.DetachedShardCount]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
