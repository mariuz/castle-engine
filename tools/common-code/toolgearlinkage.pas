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

{ Design-time helper for Mechanical Gear Train, Rack-and-Pinion, Belt Pulley &
  Odd-Cycle Jam Detection Studio (Phase 415). }
unit ToolGearLinkage;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleGearLinkage;

type
  TGearLinkageHelper = class
  public
    class function FindFirstLinkage(const ARoot: TComponent): TCastleGearLinkage;
    class function SpawnPortcullisGearboxDemo(const ARoot, AOwner: TComponent;
      out ALinkage: TCastleGearLinkage): Boolean;
    class function ExportLinkageJson(const ALinkage: TCastleGearLinkage): String;
    class function ImportLinkageJson(const ALinkage: TCastleGearLinkage;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ALinkage: TCastleGearLinkage): String;
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

class function TGearLinkageHelper.FindFirstLinkage(
  const ARoot: TComponent): TCastleGearLinkage;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleGearLinkage;
  var
    J: Integer;
  begin
    if T is TCastleGearLinkage then
      Exit(TCastleGearLinkage(T));
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
  if ARoot is TCastleGearLinkage then
    Exit(TCastleGearLinkage(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleGearLinkage then
      Exit(TCastleGearLinkage(ARoot.Components[I]));
end;

class function TGearLinkageHelper.SpawnPortcullisGearboxDemo(
  const ARoot, AOwner: TComponent; out ALinkage: TCastleGearLinkage): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
begin
  Result := False;
  ALinkage := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  ALinkage := TCastleGearLinkage.Create(Own);
  ALinkage.Name := 'PortcullisGateClockwork';
  ALinkage.ApplyPreset(glpPortcullisWinchCompoundTrain);
  VP.Items.Add(ALinkage);
  Result := True;
end;

class function TGearLinkageHelper.ExportLinkageJson(
  const ALinkage: TCastleGearLinkage): String;
var
  Obj: TJSONObject;
begin
  if ALinkage = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ALinkage.Preset));
    Obj.Add('motor_rpm', ALinkage.MotorInputRpm);
    Obj.Add('motor_torque_nm', ALinkage.MotorInputTorqueNm);
    Obj.Add('efficiency', ALinkage.StageEfficiency01);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TGearLinkageHelper.ImportLinkageJson(
  const ALinkage: TCastleGearLinkage; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ALinkage = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(ALinkage.Preset));
    if (POrd >= Ord(Low(TGearLinkagePreset))) and
       (POrd <= Ord(High(TGearLinkagePreset))) then
      ALinkage.ApplyPreset(TGearLinkagePreset(POrd));
    ALinkage.MotorInputRpm := Obj.Get('motor_rpm', ALinkage.MotorInputRpm);
    ALinkage.MotorInputTorqueNm := Obj.Get('motor_torque_nm', ALinkage.MotorInputTorqueNm);
    ALinkage.StageEfficiency01 := Obj.Get('efficiency', ALinkage.StageEfficiency01);
    ALinkage.SolveGearTrainKinematics;
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TGearLinkageHelper.GenerateMarkdownReport(
  const ALinkage: TCastleGearLinkage): String;
var
  SL: TStringList;
  I: Integer;
  G: TGearWheelNode;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Mechanical Gear Train, Rack-and-Pinion & Jam Detection Report');
    SL.Add('');
    if ALinkage = nil then
    begin
      SL.Add('_No `TCastleGearLinkage` found in the current design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Mechanism**: `' + ALinkage.Name + '` (`' +
      GearLinkagePresetToString(ALinkage.Preset) + '`)');
    SL.Add(Format('- **Jammed Loop**: **`%s`** %s',
      [BoolToStr(ALinkage.IsJammedLoop, True), ALinkage.JammedReason]));
    for I := 0 to ALinkage.NodeCount - 1 do
    begin
      G := ALinkage.GetNode(I);
      if G.IsLinearRack then
        SL.Add(FormatDot('  - Rack `%s`: Speed `%+.2f m/s`, Lift `%.2f m`, Force `%.1f N`',
          [G.Name, G.SolvedRpm, G.LinearPositionMeters, G.SolvedTorqueNm]))
      else
        SL.Add(FormatDot('  - Gear `%s` (`%dT`): `%+.1f RPM`, Torque `%.1f Nm`, Angle `%.1f deg`',
          [G.Name, G.ToothCount, G.SolvedRpm, G.SolvedTorqueNm, RadToDeg(G.AngleRad)]));
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
