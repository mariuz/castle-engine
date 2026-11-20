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

{ Design-time helper for Procedural Zipline, Pulley Trolley Gravity
  Acceleration, Hand-Brake & Momentum Vault Studio (Phase 399). }
unit ToolZiplineRig;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleZiplineRig;

type
  TZiplineRigHelper = class
  public
    class function FindFirstZipline(const ARoot: TComponent): TCastleZiplineRig;
    class function SpawnCanyonZiplineTowersDemo(const ARoot, AOwner: TComponent;
      out AZipline: TCastleZiplineRig): Boolean;
    class function ExportZiplineJson(const AZipline: TCastleZiplineRig): String;
    class function ImportZiplineJson(const AZipline: TCastleZiplineRig;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AZipline: TCastleZiplineRig): String;
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

class function TZiplineRigHelper.FindFirstZipline(
  const ARoot: TComponent): TCastleZiplineRig;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleZiplineRig;
  var
    J: Integer;
  begin
    if T is TCastleZiplineRig then
      Exit(TCastleZiplineRig(T));
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
  if ARoot is TCastleZiplineRig then
    Exit(TCastleZiplineRig(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleZiplineRig then
      Exit(TCastleZiplineRig(ARoot.Components[I]));
end;

class function TZiplineRigHelper.SpawnCanyonZiplineTowersDemo(
  const ARoot, AOwner: TComponent; out AZipline: TCastleZiplineRig): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  HighTower, LowTower: TCastleBox;
begin
  Result := False;
  AZipline := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  HighTower := TCastleBox.Create(Own);
  HighTower.Name := 'ZiplineUpperLaunchTower';
  HighTower.Size := Vector3(1.2, 12.0, 1.2);
  HighTower.Translation := Vector3(0.0, 6.0, 0.0);
  HighTower.Color := Vector4(0.48, 0.36, 0.24, 1.0);
  VP.Items.Add(HighTower);

  LowTower := TCastleBox.Create(Own);
  LowTower.Name := 'ZiplineLowerLandingTower';
  LowTower.Size := Vector3(1.2, 3.0, 1.2);
  LowTower.Translation := Vector3(0.0, 1.5, -32.0);
  LowTower.Color := Vector4(0.48, 0.36, 0.24, 1.0);
  VP.Items.Add(LowTower);

  AZipline := TCastleZiplineRig.Create(Own);
  AZipline.Name := 'AlpineCanyonZiplineSpan';
  AZipline.Translation := Vector3(0.0, 11.8, 0.0);
  AZipline.ApplyPreset(zrpAlpineCanyonZipline);
  VP.Items.Add(AZipline);

  AZipline.AttachRiderAtProgress(0.04, 1.2);
  Result := True;
end;

class function TZiplineRigHelper.ExportZiplineJson(
  const AZipline: TCastleZiplineRig): String;
var
  Obj: TJSONObject;
begin
  if AZipline = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AZipline.Preset));
    Obj.Add('endX', AZipline.EndOffsetLocal.X);
    Obj.Add('endY', AZipline.EndOffsetLocal.Y);
    Obj.Add('endZ', AZipline.EndOffsetLocal.Z);
    Obj.Add('unloadedSagMeters', AZipline.UnloadedSagMeters);
    Obj.Add('handBrakeDecelMps2', AZipline.HandBrakeDecelMps2);
    Obj.Add('vaultJumpUpSpeedMps', AZipline.VaultJumpUpSpeedMps);
    Obj.Add('riderMassKg', AZipline.RiderMassKg);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TZiplineRigHelper.ImportZiplineJson(
  const AZipline: TCastleZiplineRig; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AZipline = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(AZipline.Preset));
    if (POrd >= Ord(Low(TZiplinePreset))) and (POrd <= Ord(High(TZiplinePreset))) then
      AZipline.Preset := TZiplinePreset(POrd);
    AZipline.EndOffsetLocal := Vector3(
      Obj.Get('endX', AZipline.EndOffsetLocal.X),
      Obj.Get('endY', AZipline.EndOffsetLocal.Y),
      Obj.Get('endZ', AZipline.EndOffsetLocal.Z));
    AZipline.UnloadedSagMeters := Obj.Get('unloadedSagMeters', AZipline.UnloadedSagMeters);
    AZipline.HandBrakeDecelMps2 := Obj.Get('handBrakeDecelMps2', AZipline.HandBrakeDecelMps2);
    AZipline.VaultJumpUpSpeedMps := Obj.Get('vaultJumpUpSpeedMps', AZipline.VaultJumpUpSpeedMps);
    AZipline.RiderMassKg := Obj.Get('riderMassKg', AZipline.RiderMassKg);
    AZipline.RebuildPreview;
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TZiplineRigHelper.GenerateMarkdownReport(
  const AZipline: TCastleZiplineRig): String;
var
  SL: TStringList;
  S: TZiplineRiderState;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Procedural Zipline, Pulley Acceleration & Vault Launch Report');
    SL.Add('');
    if AZipline = nil then
    begin
      SL.Add('_No `TCastleZiplineRig` found in the active design._');
      Exit(SL.Text);
    end;
    S := AZipline.LastState;
    SL.Add('- **Zipline**: `' + AZipline.Name + '` (`' +
      ZiplinePresetToString(AZipline.Preset) + '`)');
    SL.Add(FormatDot('- **Span Chord / Drop**: `%.1f m` (`EndOffset=(%.1f, %.1f, %.1f) m`)',
      [AZipline.ChordLengthMeters, AZipline.EndOffsetLocal.X,
       AZipline.EndOffsetLocal.Y, AZipline.EndOffsetLocal.Z]));
    SL.Add(FormatDot('- **Pulley State**: Riding=`%s`, Progress=`%.1f%%`, Speed=`%.2f m/s`, LiveSag=`%.3f m`, Arrested=`%s`',
      [BoolToStr(S.IsRiding, True), S.NormalizedProgress01 * 100.0,
       S.SpeedMps, S.LiveRiderSagMeters, BoolToStr(S.ReachedArrestorStop, True)]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
