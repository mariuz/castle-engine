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

{ Design-time helper for Multi-Leg Quadruped / Hexapod / Spider Gait Phase,
  WorldRay Slope Foot-Plant & Body Tilt Studio (Phase 398). }
unit ToolQuadrupedGait;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleQuadrupedGait;

type
  TQuadrupedGaitHelper = class
  public
    class function FindFirstRig(const ARoot: TComponent): TCastleMultiLegGaitRig;
    class function SpawnSteppedRampGaitDemo(const ARoot, AOwner: TComponent;
      out ARig: TCastleMultiLegGaitRig): Boolean;
    class function ExportRigJson(const ARig: TCastleMultiLegGaitRig): String;
    class function ImportRigJson(const ARig: TCastleMultiLegGaitRig;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ARig: TCastleMultiLegGaitRig): String;
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

class function TQuadrupedGaitHelper.FindFirstRig(
  const ARoot: TComponent): TCastleMultiLegGaitRig;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleMultiLegGaitRig;
  var
    J: Integer;
  begin
    if T is TCastleMultiLegGaitRig then
      Exit(TCastleMultiLegGaitRig(T));
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
  if ARoot is TCastleMultiLegGaitRig then
    Exit(TCastleMultiLegGaitRig(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleMultiLegGaitRig then
      Exit(TCastleMultiLegGaitRig(ARoot.Components[I]));
end;

class function TQuadrupedGaitHelper.SpawnSteppedRampGaitDemo(
  const ARoot, AOwner: TComponent; out ARig: TCastleMultiLegGaitRig): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  RearFloor, FrontElevatedStep: TCastleBox;
begin
  Result := False;
  ARig := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  RearFloor := TCastleBox.Create(Own);
  RearFloor.Name := 'GaitRearGroundSlab';
  RearFloor.Size := Vector3(10.0, 0.4, 10.0);
  RearFloor.Translation := Vector3(0.0, -0.2, 0.0);
  RearFloor.Color := Vector4(0.36, 0.38, 0.34, 1.0);
  VP.Items.Add(RearFloor);

  { Elevated front rock ledge at Z < 0 (top Y = +0.42m) }
  FrontElevatedStep := TCastleBox.Create(Own);
  FrontElevatedStep.Name := 'GaitFrontElevatedRock';
  FrontElevatedStep.Size := Vector3(6.0, 0.42, 4.0);
  FrontElevatedStep.Translation := Vector3(0.0, 0.21, -2.0);
  FrontElevatedStep.Color := Vector4(0.48, 0.44, 0.38, 1.0);
  VP.Items.Add(FrontElevatedStep);

  ARig := TCastleMultiLegGaitRig.Create(Own);
  ARig.Name := 'QuadrupedWalkerRig';
  ARig.Translation := Vector3(0.0, 0.85, 0.0);
  ARig.ApplyPreset(mgpHexapodInsectTripod6Leg);
  VP.Items.Add(ARig);

  ARig.EvaluateAtNormalizedCycle(VP.Items, 0.15);
  Result := True;
end;

class function TQuadrupedGaitHelper.ExportRigJson(
  const ARig: TCastleMultiLegGaitRig): String;
var
  Obj: TJSONObject;
begin
  if ARig = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ARig.Preset));
    Obj.Add('legCount', ARig.LegCount);
    Obj.Add('bodyClearanceHeightMeters', ARig.BodyClearanceHeightMeters);
    Obj.Add('legLateralSpreadMeters', ARig.LegLateralSpreadMeters);
    Obj.Add('strideLengthMeters', ARig.StrideLengthMeters);
    Obj.Add('swingStepHeightMeters', ARig.SwingStepHeightMeters);
    Obj.Add('dutyFactor01', ARig.DutyFactor01);
    Obj.Add('moveSpeedMps', ARig.MoveSpeedMps);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TQuadrupedGaitHelper.ImportRigJson(
  const ARig: TCastleMultiLegGaitRig; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ARig = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(ARig.Preset));
    if (POrd >= Ord(Low(TMultiLegGaitPreset))) and
       (POrd <= Ord(High(TMultiLegGaitPreset))) then
      ARig.Preset := TMultiLegGaitPreset(POrd);
    ARig.LegCount := Obj.Get('legCount', ARig.LegCount);
    ARig.BodyClearanceHeightMeters := Obj.Get('bodyClearanceHeightMeters', ARig.BodyClearanceHeightMeters);
    ARig.LegLateralSpreadMeters := Obj.Get('legLateralSpreadMeters', ARig.LegLateralSpreadMeters);
    ARig.StrideLengthMeters := Obj.Get('strideLengthMeters', ARig.StrideLengthMeters);
    ARig.SwingStepHeightMeters := Obj.Get('swingStepHeightMeters', ARig.SwingStepHeightMeters);
    ARig.DutyFactor01 := Obj.Get('dutyFactor01', ARig.DutyFactor01);
    ARig.MoveSpeedMps := Obj.Get('moveSpeedMps', ARig.MoveSpeedMps);
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TQuadrupedGaitHelper.GenerateMarkdownReport(
  const ARig: TCastleMultiLegGaitRig): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Multi-Leg Quadruped / Hexapod / Arachnid Gait Studio Report');
    SL.Add('');
    if ARig = nil then
    begin
      SL.Add('_No `TCastleMultiLegGaitRig` found in the active design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Rig Name**: `' + ARig.Name + '` (`' +
      MultiLegPresetToString(ARig.Preset) + '`)');
    SL.Add(FormatDot('- **Cycle / Grounded Stability**: `%.2f` (`%d / %d` legs grounded, Duty `%.0f%%`)',
      [ARig.GaitCycle01, ARig.GroundedLegCount, ARig.LegCount, ARig.DutyFactor01 * 100.0]));
    SL.Add(FormatDot('- **Terrain Body Slope Adaptation**: Pitch `%.2f deg`, Roll `%.2f deg`',
      [ARig.BodyPitchDeg, ARig.BodyRollDeg]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
