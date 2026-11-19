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

{ Design-time helper for Acoustic Raytraced Reverb, Sabine/Eyring RT60 &
  Doorway Diffraction Obstruction Studio (Phase 388). }
unit ToolAcousticSpace;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleAcousticSpace;

type
  TAcousticSpaceHelper = class
  public
    class function FindFirstProbe(const ARoot: TComponent): TCastleAcousticProbe;
    class function SpawnStoneHallAndDoorwayDemo(const ARoot, AOwner: TComponent;
      out AProbe: TCastleAcousticProbe): Boolean;
    class function ConvertRoomToPaddedBooth(const ARoot: TComponent;
      const AProbe: TCastleAcousticProbe): TAcousticRoomReport;
    class function ExportProbeJson(const AProbe: TCastleAcousticProbe): String;
    class function ImportProbeJson(const AProbe: TCastleAcousticProbe;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AProbe: TCastleAcousticProbe): String;
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

class function TAcousticSpaceHelper.FindFirstProbe(
  const ARoot: TComponent): TCastleAcousticProbe;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleAcousticProbe;
  var
    J: Integer;
  begin
    if T is TCastleAcousticProbe then
      Exit(TCastleAcousticProbe(T));
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
  if ARoot is TCastleAcousticProbe then
    Exit(TCastleAcousticProbe(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleAcousticProbe then
      Exit(TCastleAcousticProbe(ARoot.Components[I]));
end;

class function TAcousticSpaceHelper.SpawnStoneHallAndDoorwayDemo(
  const ARoot, AOwner: TComponent; out AProbe: TCastleAcousticProbe): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;

  procedure AddStoneSlab(const AName: String; const ASize, APos: TVector3);
  var
    B: TCastleBox;
  begin
    B := TCastleBox.Create(Own);
    B.Name := AName;
    B.Size := ASize;
    B.Translation := APos;
    B.Color := Vector4(0.46, 0.48, 0.52, 1.0);
    VP.Items.Add(B);
  end;

begin
  Result := False;
  AProbe := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Enclosed 20m x 12m x 26m Stone Cathedral Nave + Partition Wall with East Doorway }
  AddStoneSlab('StoneCathedralFloor',   Vector3(20.0, 0.5, 26.0), Vector3(0.0, -0.25, 0.0));
  AddStoneSlab('StoneCathedralCeiling', Vector3(20.0, 0.5, 26.0), Vector3(0.0, 12.25, 0.0));
  AddStoneSlab('StoneCathedralNorth',   Vector3(20.0, 12.0, 0.5), Vector3(0.0, 6.0, -13.0));
  AddStoneSlab('StoneCathedralSouth',   Vector3(20.0, 12.0, 0.5), Vector3(0.0, 6.0, 13.0));
  AddStoneSlab('StoneCathedralWest',    Vector3(0.5, 12.0, 26.0), Vector3(-10.0, 6.0, 0.0));
  AddStoneSlab('StoneCathedralEast',    Vector3(0.5, 12.0, 26.0), Vector3(10.0, 6.0, 0.0));
  { Interior stone divider wall at Z = -3m leaving an open doorway gap around X = +6.5m }
  AddStoneSlab('StoneDividerWall',      Vector3(14.0, 12.0, 0.4), Vector3(-3.0, 6.0, -3.0));

  AProbe := TCastleAcousticProbe.Create(Own);
  AProbe.Name := 'CathedralListenerProbe';
  AProbe.Translation := Vector3(0.0, 1.7, 4.0);
  AProbe.ApplyPreset(acpCathedralStoneNave);
  VP.Items.Add(AProbe);

  AProbe.BakeRoomAcoustics(VP.Items);
  Result := True;
end;

class function TAcousticSpaceHelper.ConvertRoomToPaddedBooth(
  const ARoot: TComponent; const AProbe: TCastleAcousticProbe): TAcousticRoomReport;
var
  VP: TCastleViewport;
  I: Integer;
  T: TCastleTransform;
begin
  Result := Default(TAcousticRoomReport);
  if AProbe = nil then Exit;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  for I := 0 to VP.Items.Count - 1 do
  begin
    T := VP.Items[I];
    if Pos('StoneCathedral', T.Name) = 1 then
      T.Name := StringReplace(T.Name, 'StoneCathedral', 'PaddedFoam', []);
  end;
  AProbe.ApplyPreset(acpPaddedRecordingBooth);
  Result := AProbe.BakeRoomAcoustics(VP.Items);
end;

class function TAcousticSpaceHelper.ExportProbeJson(
  const AProbe: TCastleAcousticProbe): String;
var
  Obj: TJSONObject;
begin
  if AProbe = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AProbe.Preset));
    Obj.Add('rayCount', AProbe.RayCount);
    Obj.Add('maxProbeDistanceMeters', AProbe.MaxProbeDistanceMeters);
    Obj.Add('defaultWallAbsorption', AProbe.DefaultWallAbsorption);
    Obj.Add('airAttenuationPerMeter', AProbe.AirAttenuationPerMeter);
    Obj.Add('speedOfSoundMps', AProbe.SpeedOfSoundMps);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TAcousticSpaceHelper.ImportProbeJson(
  const AProbe: TCastleAcousticProbe; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AProbe = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(AProbe.Preset));
    if (POrd >= Ord(Low(TAcousticSpacePreset))) and
       (POrd <= Ord(High(TAcousticSpacePreset))) then
      AProbe.Preset := TAcousticSpacePreset(POrd);
    AProbe.RayCount := Obj.Get('rayCount', AProbe.RayCount);
    AProbe.MaxProbeDistanceMeters := Obj.Get('maxProbeDistanceMeters', AProbe.MaxProbeDistanceMeters);
    AProbe.DefaultWallAbsorption := Obj.Get('defaultWallAbsorption', AProbe.DefaultWallAbsorption);
    AProbe.AirAttenuationPerMeter := Obj.Get('airAttenuationPerMeter', AProbe.AirAttenuationPerMeter);
    AProbe.SpeedOfSoundMps := Obj.Get('speedOfSoundMps', AProbe.SpeedOfSoundMps);
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TAcousticSpaceHelper.GenerateMarkdownReport(
  const AProbe: TCastleAcousticProbe): String;
var
  SL: TStringList;
  R: TAcousticRoomReport;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Raytraced Room Acoustics (Sabine/Eyring RT60 & UTD Diffraction)');
    SL.Add('');
    if AProbe = nil then
    begin
      SL.Add('_No `TCastleAcousticProbe` found in the active design._');
      Exit(SL.Text);
    end;
    R := AProbe.LastRoom;
    SL.Add('- **Probe Name**: `' + AProbe.Name + '` (`' +
      AcousticPresetToString(AProbe.Preset) + '`)');
    SL.Add(FormatDot('- **Fibonacci Rays**: `%d` cast (`%d` wall hits, `%d` sky escapes -> Leak `%.1f%%`)',
      [R.RayCount, R.HitRayCount, R.EscapedSkyRayCount, R.OutdoorLeak01 * 100.0]));
    SL.Add(FormatDot('- **Estimated Geometry**: Volume `%.1f m^3`, Surface `%.1f m^2`, Mean Alpha `%.3f`',
      [R.EstimatedVolumeM3, R.EstimatedSurfaceAreaM2, R.MeanAbsorption01]));
    SL.Add(FormatDot('- **Reverb Decay**: Sabine RT60 `%.2f s`, Eyring RT60 `%.2f s`, Predelay `%.1f ms`, Wet Mix `%.0f%%`',
      [R.SabineRt60Sec, R.EyringRt60Sec, R.PredelayMs, R.WetReverbMix01 * 100.0]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
