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

{ Design-time helper for Dual-Axis Gimbal Turret, Slew-Rate Servo,
  Critically-Damped Barrel Recoil & Thermal Overheat Vent Studio (Phase 413). }
unit ToolTurretGimbal;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleTurretGimbal;

type
  TTurretGimbalHelper = class
  public
    class function FindFirstTurret(const ARoot: TComponent): TCastleTurretGimbal;
    class function SpawnBattleshipDeckTurretDemo(const ARoot, AOwner: TComponent;
      out ATurret: TCastleTurretGimbal): Boolean;
    class function ExportTurretJson(const ATurret: TCastleTurretGimbal): String;
    class function ImportTurretJson(const ATurret: TCastleTurretGimbal;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ATurret: TCastleTurretGimbal): String;
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

class function TTurretGimbalHelper.FindFirstTurret(
  const ARoot: TComponent): TCastleTurretGimbal;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleTurretGimbal;
  var
    J: Integer;
  begin
    if T is TCastleTurretGimbal then
      Exit(TCastleTurretGimbal(T));
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
  if ARoot is TCastleTurretGimbal then
    Exit(TCastleTurretGimbal(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleTurretGimbal then
      Exit(TCastleTurretGimbal(ARoot.Components[I]));
end;

class function TTurretGimbalHelper.SpawnBattleshipDeckTurretDemo(
  const ARoot, AOwner: TComponent; out ATurret: TCastleTurretGimbal): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  AftBridgeMast: TCastleBox;
begin
  Result := False;
  ATurret := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Friendly ship bridge mast aft (+Z = +5.0m) blocking rear friendly-fire! }
  AftBridgeMast := TCastleBox.Create(Own);
  AftBridgeMast.Name := 'FriendlyShipSuperstructureBridge';
  AftBridgeMast.Size := Vector3(3.0, 5.0, 2.0);
  AftBridgeMast.Translation := Vector3(0.0, 2.5, 5.0);
  AftBridgeMast.Color := Vector4(0.45, 0.50, 0.58, 1.0);
  VP.Items.Add(AftBridgeMast);

  ATurret := TCastleTurretGimbal.Create(Own);
  ATurret.Name := 'ForwardDeckMainTurret';
  ATurret.Translation := Vector3(0.0, 1.8, 0.0);
  ATurret.ApplyPreset(tgpHeavyBattleshipMainBattery);
  VP.Items.Add(ATurret);

  ATurret.StepServoTracking(VP.Items, Vector3(12.0, 4.0, -12.0), 0.50);
  Result := True;
end;

class function TTurretGimbalHelper.ExportTurretJson(
  const ATurret: TCastleTurretGimbal): String;
var
  Obj: TJSONObject;
begin
  if ATurret = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ATurret.Preset));
    Obj.Add('yaw_slew', ATurret.YawSlewDegPerSec);
    Obj.Add('pitch_slew', ATurret.PitchSlewDegPerSec);
    Obj.Add('heat_per_shot', ATurret.HeatPerShot01);
    Obj.Add('recoil_m', ATurret.RecoilKickMeters);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TTurretGimbalHelper.ImportTurretJson(
  const ATurret: TCastleTurretGimbal; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ATurret = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(ATurret.Preset));
    if (POrd >= Ord(Low(TTurretGimbalPreset))) and
       (POrd <= Ord(High(TTurretGimbalPreset))) then
      ATurret.ApplyPreset(TTurretGimbalPreset(POrd));
    ATurret.YawSlewDegPerSec := Obj.Get('yaw_slew', ATurret.YawSlewDegPerSec);
    ATurret.PitchSlewDegPerSec := Obj.Get('pitch_slew', ATurret.PitchSlewDegPerSec);
    ATurret.HeatPerShot01 := Obj.Get('heat_per_shot', ATurret.HeatPerShot01);
    ATurret.RecoilKickMeters := Obj.Get('recoil_m', ATurret.RecoilKickMeters);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TTurretGimbalHelper.GenerateMarkdownReport(
  const ATurret: TCastleTurretGimbal): String;
var
  SL: TStringList;
  S: TTurretGimbalState;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Dual-Axis Gimbal Turret, Slew Servo, Recoil & Overheat Report');
    SL.Add('');
    if ATurret = nil then
    begin
      SL.Add('_No `TCastleTurretGimbal` found in the current design._');
      Exit(SL.Text);
    end;
    S := ATurret.State;
    SL.Add('- **Turret**: `' + ATurret.Name + '` (`' +
      TurretGimbalPresetToString(ATurret.Preset) + '`)');
    SL.Add(FormatDot('- **Gimbal Pose**: Yaw `%.1f deg`, Pitch `%.1f deg` (Aim Error `%.2f deg`)',
      [S.CurrentYawDeg, S.CurrentPitchDeg, S.AngularAimErrorDeg]));
    SL.Add(FormatDot('- **Barrel Heat / Vent Lockout**: `%.0f%%` / `%s`',
      [S.BarrelHeat01 * 100.0, BoolToStr(S.IsOverheatedVenting, True)]));
    SL.Add(FormatDot('- **Recoil Offset / Friendly Inhibit**: `%.3f m` / `%s` (Shots `%d`)',
      [S.RecoilOffsetMeters, BoolToStr(S.FriendlyHullBlocked, True), S.ShotsFiredCount]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
