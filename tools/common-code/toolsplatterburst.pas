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

{ Design-time helper for Procedural Decal Splatter, WorldRay Directional Cone
  Burst & Grazing-Angle Streak Elongation Studio (Phase 395). }
unit ToolSplatterBurst;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleSplatterBurst;

type
  TSplatterBurstHelper = class
  public
    class function FindFirstBurst(const ARoot: TComponent): TCastleSplatterBurst;
    class function SpawnCornerRoomSplatterDemo(const ARoot, AOwner: TComponent;
      out ABurst: TCastleSplatterBurst): Boolean;
    class function ExportBurstJson(const ABurst: TCastleSplatterBurst): String;
    class function ImportBurstJson(const ABurst: TCastleSplatterBurst;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ABurst: TCastleSplatterBurst): String;
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

class function TSplatterBurstHelper.FindFirstBurst(
  const ARoot: TComponent): TCastleSplatterBurst;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleSplatterBurst;
  var
    J: Integer;
  begin
    if T is TCastleSplatterBurst then
      Exit(TCastleSplatterBurst(T));
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
  if ARoot is TCastleSplatterBurst then
    Exit(TCastleSplatterBurst(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleSplatterBurst then
      Exit(TCastleSplatterBurst(ARoot.Components[I]));
end;

class function TSplatterBurstHelper.SpawnCornerRoomSplatterDemo(
  const ARoot, AOwner: TComponent; out ABurst: TCastleSplatterBurst): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  FloorSlab, NorthWall, EastWall: TCastleBox;
begin
  Result := False;
  ABurst := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  FloorSlab := TCastleBox.Create(Own);
  FloorSlab.Name := 'SplatterArenaFloor';
  FloorSlab.Size := Vector3(12.0, 0.4, 12.0);
  FloorSlab.Translation := Vector3(0.0, -0.2, -3.0);
  FloorSlab.Color := Vector4(0.52, 0.54, 0.56, 1.0);
  VP.Items.Add(FloorSlab);

  NorthWall := TCastleBox.Create(Own);
  NorthWall.Name := 'SplatterNorthWall';
  NorthWall.Size := Vector3(12.0, 5.0, 0.4);
  NorthWall.Translation := Vector3(0.0, 2.5, -5.0);
  NorthWall.Color := Vector4(0.62, 0.64, 0.68, 1.0);
  VP.Items.Add(NorthWall);

  EastWall := TCastleBox.Create(Own);
  EastWall.Name := 'SplatterEastWall';
  EastWall.Size := Vector3(0.4, 5.0, 12.0);
  EastWall.Translation := Vector3(2.2, 2.5, -3.0);
  EastWall.Color := Vector4(0.58, 0.60, 0.64, 1.0);
  VP.Items.Add(EastWall);

  ABurst := TCastleSplatterBurst.Create(Own);
  ABurst.Name := 'PaintballSplatterEmitter';
  ABurst.Translation := Vector3(1.6, 1.5, 0.0);
  ABurst.ApplyPreset(sbpPaintballNeonSplash);
  VP.Items.Add(ABurst);

  { Spray toward NE corner so rays hit NorthWall head-on and EastWall at a graze }
  ABurst.EmitDirectionalBurst(VP.Items, Vector3(1.6, 1.5, 0.0),
    Vector3(0.18, -0.10, -1.0).Normalize);
  Result := True;
end;

class function TSplatterBurstHelper.ExportBurstJson(
  const ABurst: TCastleSplatterBurst): String;
var
  Obj: TJSONObject;
begin
  if ABurst = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ABurst.Preset));
    Obj.Add('dropletRayCount', ABurst.DropletRayCount);
    Obj.Add('coneHalfAngleDeg', ABurst.ConeHalfAngleDeg);
    Obj.Add('maxSprayRangeMeters', ABurst.MaxSprayRangeMeters);
    Obj.Add('baseDropletRadiusMeters', ABurst.BaseDropletRadiusMeters);
    Obj.Add('maxStreakAspectRatio', ABurst.MaxStreakAspectRatio);
    Obj.Add('maxActiveSplats', ABurst.MaxActiveSplats);
    Obj.Add('decalLifetimeSec', ABurst.DecalLifetimeSec);
    Obj.Add('randomSeed', ABurst.RandomSeed);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TSplatterBurstHelper.ImportBurstJson(
  const ABurst: TCastleSplatterBurst; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ABurst = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(ABurst.Preset));
    if (POrd >= Ord(Low(TSplatterBurstPreset))) and
       (POrd <= Ord(High(TSplatterBurstPreset))) then
      ABurst.Preset := TSplatterBurstPreset(POrd);
    ABurst.DropletRayCount := Obj.Get('dropletRayCount', ABurst.DropletRayCount);
    ABurst.ConeHalfAngleDeg := Obj.Get('coneHalfAngleDeg', ABurst.ConeHalfAngleDeg);
    ABurst.MaxSprayRangeMeters := Obj.Get('maxSprayRangeMeters', ABurst.MaxSprayRangeMeters);
    ABurst.BaseDropletRadiusMeters := Obj.Get('baseDropletRadiusMeters', ABurst.BaseDropletRadiusMeters);
    ABurst.MaxStreakAspectRatio := Obj.Get('maxStreakAspectRatio', ABurst.MaxStreakAspectRatio);
    ABurst.MaxActiveSplats := Obj.Get('maxActiveSplats', ABurst.MaxActiveSplats);
    ABurst.DecalLifetimeSec := Obj.Get('decalLifetimeSec', ABurst.DecalLifetimeSec);
    ABurst.RandomSeed := Obj.Get('randomSeed', ABurst.RandomSeed);
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TSplatterBurstHelper.GenerateMarkdownReport(
  const ABurst: TCastleSplatterBurst): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Procedural Decal Splatter Burst & Grazing Streak Report');
    SL.Add('');
    if ABurst = nil then
    begin
      SL.Add('_No `TCastleSplatterBurst` found in the active design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Emitter**: `' + ABurst.Name + '` (`' +
      SplatterPresetToString(ABurst.Preset) + '`)');
    SL.Add(FormatDot('- **Active Decals / Ring Cap**: `%d / %d` (Droplets/Burst `%d`, Cone `%.1f deg`)',
      [ABurst.ActiveSplatCount, ABurst.MaxActiveSplats, ABurst.DropletRayCount,
       ABurst.ConeHalfAngleDeg]));
    SL.Add(FormatDot('- **Mean Grazing Streak Elongation**: `%.2fx` (Max Cap `%.1fx`, Lifetime `%.1f s`)',
      [ABurst.MeanStreakAspectRatio, ABurst.MaxStreakAspectRatio, ABurst.DecalLifetimeSec]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
