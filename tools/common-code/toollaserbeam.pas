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

{ Design-time helper for Multi-Bounce Optical Laser, Mirror Reflection,
  Snell Prism Refraction & Beam-Break Cutoff Studio (Phase 411). }
unit ToolLaserBeam;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleLaserBeam;

type
  TLaserBeamHelper = class
  public
    class function FindFirstLaser(const ARoot: TComponent): TCastleLaserBeamRig;
    class function SpawnTwoMirrorReceiverPuzzleDemo(const ARoot, AOwner: TComponent;
      out ALaser: TCastleLaserBeamRig): Boolean;
    class function ExportLaserJson(const ALaser: TCastleLaserBeamRig): String;
    class function ImportLaserJson(const ALaser: TCastleLaserBeamRig;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ALaser: TCastleLaserBeamRig): String;
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

class function TLaserBeamHelper.FindFirstLaser(
  const ARoot: TComponent): TCastleLaserBeamRig;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleLaserBeamRig;
  var
    J: Integer;
  begin
    if T is TCastleLaserBeamRig then
      Exit(TCastleLaserBeamRig(T));
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
  if ARoot is TCastleLaserBeamRig then
    Exit(TCastleLaserBeamRig(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleLaserBeamRig then
      Exit(TCastleLaserBeamRig(ARoot.Components[I]));
end;

class function TLaserBeamHelper.SpawnTwoMirrorReceiverPuzzleDemo(
  const ARoot, AOwner: TComponent; out ALaser: TCastleLaserBeamRig): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  MirrorNW, MirrorNE, ReceiverCrystal, BlockerCrate: TCastleBox;
begin
  Result := False;
  ALaser := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { 1. 45-deg NW Mirror at (0, 1.5, -5): reflects -Z beam 90 deg East (+X)! }
  MirrorNW := TCastleBox.Create(Own);
  MirrorNW.Name := 'Mirror_NorthWest45';
  MirrorNW.Size := Vector3(2.0, 2.0, 0.24);
  MirrorNW.Translation := Vector3(0.0, 1.5, -5.0);
  MirrorNW.Rotation := Vector4(0.0, 1.0, 0.0, Pi * 0.25);
  MirrorNW.Color := Vector4(0.78, 0.88, 0.98, 1.0);
  VP.Items.Add(MirrorNW);

  { 2. -45-deg NE Mirror at (+6, 1.5, -5): reflects +X beam 90 deg South (+Z)! }
  MirrorNE := TCastleBox.Create(Own);
  MirrorNE.Name := 'Mirror_NorthEast45';
  MirrorNE.Size := Vector3(2.0, 2.0, 0.24);
  MirrorNE.Translation := Vector3(6.0, 1.5, -5.0);
  MirrorNE.Rotation := Vector4(0.0, 1.0, 0.0, -Pi * 0.25);
  MirrorNE.Color := Vector4(0.78, 0.88, 0.98, 1.0);
  VP.Items.Add(MirrorNE);

  { 3. Crystal Receiver Goal at (+6, 1.5, 0) }
  ReceiverCrystal := TCastleBox.Create(Own);
  ReceiverCrystal.Name := 'Receiver_CrystalGoal';
  ReceiverCrystal.Size := Vector3(1.0, 1.0, 1.0);
  ReceiverCrystal.Translation := Vector3(6.0, 1.5, 0.0);
  ReceiverCrystal.Color := Vector4(0.25, 0.95, 0.55, 1.0);
  VP.Items.Add(ReceiverCrystal);

  { 4. Movable solid blocker crate (initially parked aside at Z = -8.0) }
  BlockerCrate := TCastleBox.Create(Own);
  BlockerCrate.Name := 'Crate_BeamBlocker';
  BlockerCrate.Size := Vector3(1.0, 1.2, 1.0);
  BlockerCrate.Translation := Vector3(3.0, 1.5, -8.0);
  BlockerCrate.Color := Vector4(0.62, 0.42, 0.24, 1.0);
  VP.Items.Add(BlockerCrate);

  ALaser := TCastleLaserBeamRig.Create(Own);
  ALaser.Name := 'TempleRubyRelayLaser';
  ALaser.Translation := Vector3(0.0, 1.5, 0.0);
  ALaser.ApplyPreset(lbpRubyPuzzleRelayLaser);
  VP.Items.Add(ALaser);

  ALaser.TraceLaserBeam(VP.Items);
  Result := True;
end;

class function TLaserBeamHelper.ExportLaserJson(
  const ALaser: TCastleLaserBeamRig): String;
var
  Obj: TJSONObject;
begin
  if ALaser = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ALaser.Preset));
    Obj.Add('power_w', ALaser.EmitterPowerWatts);
    Obj.Add('max_bounces', ALaser.MaxBounces);
    Obj.Add('prism_ior', ALaser.PrismRefractiveIndex);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TLaserBeamHelper.ImportLaserJson(
  const ALaser: TCastleLaserBeamRig; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ALaser = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(ALaser.Preset));
    if (POrd >= Ord(Low(TLaserBeamPreset))) and
       (POrd <= Ord(High(TLaserBeamPreset))) then
      ALaser.ApplyPreset(TLaserBeamPreset(POrd));
    ALaser.EmitterPowerWatts := Obj.Get('power_w', ALaser.EmitterPowerWatts);
    ALaser.MaxBounces := Obj.Get('max_bounces', ALaser.MaxBounces);
    ALaser.PrismRefractiveIndex := Obj.Get('prism_ior', ALaser.PrismRefractiveIndex);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TLaserBeamHelper.GenerateMarkdownReport(
  const ALaser: TCastleLaserBeamRig): String;
var
  SL: TStringList;
  I: Integer;
  S: TLaserBeamSegment;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Multi-Bounce Optical Laser, Mirror/Prism & Cutoff Gate Report');
    SL.Add('');
    if ALaser = nil then
    begin
      SL.Add('_No `TCastleLaserBeamRig` found in the current design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Laser**: `' + ALaser.Name + '` (`' +
      LaserBeamPresetToString(ALaser.Preset) + '`)');
    SL.Add(FormatDot('- **Receiver Powered**: **`%s`** (`%s`, Delivered `%.2f W`)',
      [BoolToStr(ALaser.ReceiverPowered, True), ALaser.PoweredReceiverName,
       ALaser.DeliveredPowerWatts]));
    SL.Add(Format('- **Traced Beam Segments**: `%d` (Last Hit: `%s`)',
      [ALaser.SegmentCount, ALaser.LastHitObjectName]));
    for I := 0 to ALaser.SegmentCount - 1 do
    begin
      S := ALaser.GetSegment(I);
      SL.Add(FormatDot('  - Seg `%d`: `(%.1f, %.1f)` -> `(%.1f, %.1f)` [`%s`, `%.1f W`]',
        [I + 1, S.StartWorld.X, S.StartWorld.Z, S.EndWorld.X, S.EndWorld.Z,
         S.HitComponentName, S.PowerWatts]));
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
