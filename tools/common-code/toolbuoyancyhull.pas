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

{ Design-time helper for Multi-Pontoon Buoyancy Hydrostatics, Spherical-Cap
  Submergence & Wave Righting-Torque Studio (Phase 391). }
unit ToolBuoyancyHull;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleBuoyancyHull;

type
  TBuoyancyHullHelper = class
  public
    class function FindFirstHull(const ARoot: TComponent): TCastleBuoyancyHull;
    class function SpawnWaterBasinRaftDemo(const ARoot, AOwner: TComponent;
      out AHull: TCastleBuoyancyHull): Boolean;
    class function ExportHullJson(const AHull: TCastleBuoyancyHull): String;
    class function ImportHullJson(const AHull: TCastleBuoyancyHull;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AHull: TCastleBuoyancyHull): String;
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

class function TBuoyancyHullHelper.FindFirstHull(
  const ARoot: TComponent): TCastleBuoyancyHull;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleBuoyancyHull;
  var
    J: Integer;
  begin
    if T is TCastleBuoyancyHull then
      Exit(TCastleBuoyancyHull(T));
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
  if ARoot is TCastleBuoyancyHull then
    Exit(TCastleBuoyancyHull(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleBuoyancyHull then
      Exit(TCastleBuoyancyHull(ARoot.Components[I]));
end;

class function TBuoyancyHullHelper.SpawnWaterBasinRaftDemo(
  const ARoot, AOwner: TComponent; out AHull: TCastleBuoyancyHull): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  WaterSlab: TCastleBox;
begin
  Result := False;
  AHull := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  WaterSlab := TCastleBox.Create(Own);
  WaterSlab.Name := 'HarborWaterSurfaceSlab';
  WaterSlab.Size := Vector3(28.0, 0.12, 28.0);
  WaterSlab.Translation := Vector3(0.0, -0.06, 0.0);
  WaterSlab.Color := Vector4(0.10, 0.44, 0.72, 0.75);
  VP.Items.Add(WaterSlab);

  AHull := TCastleBuoyancyHull.Create(Own);
  AHull.Name := 'CargoRaftHull4Pt';
  AHull.Translation := Vector3(0.0, 0.45, 0.0);
  AHull.ApplyPreset(bhpWoodenCargoRaft4Pt);
  VP.Items.Add(AHull);

  AHull.StepHydrostaticMotion(1.2);
  Result := True;
end;

class function TBuoyancyHullHelper.ExportHullJson(
  const AHull: TCastleBuoyancyHull): String;
var
  Obj: TJSONObject;
begin
  if AHull = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AHull.Preset));
    Obj.Add('hullMassKg', AHull.HullMassKg);
    Obj.Add('fluidDensityKgM3', AHull.FluidDensityKgM3);
    Obj.Add('waterLevelY', AHull.WaterLevelY);
    Obj.Add('waveAmplitudeMeters', AHull.WaveAmplitudeMeters);
    Obj.Add('waveLengthMeters', AHull.WaveLengthMeters);
    Obj.Add('waveSpeedMps', AHull.WaveSpeedMps);
    Obj.Add('centerOfMassOffsetY', AHull.CenterOfMassOffsetY);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TBuoyancyHullHelper.ImportHullJson(
  const AHull: TCastleBuoyancyHull; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AHull = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(AHull.Preset));
    if (POrd >= Ord(Low(TBuoyancyHullPreset))) and (POrd <= Ord(High(TBuoyancyHullPreset))) then
      AHull.Preset := TBuoyancyHullPreset(POrd);
    AHull.HullMassKg := Obj.Get('hullMassKg', AHull.HullMassKg);
    AHull.FluidDensityKgM3 := Obj.Get('fluidDensityKgM3', AHull.FluidDensityKgM3);
    AHull.WaterLevelY := Obj.Get('waterLevelY', AHull.WaterLevelY);
    AHull.WaveAmplitudeMeters := Obj.Get('waveAmplitudeMeters', AHull.WaveAmplitudeMeters);
    AHull.WaveLengthMeters := Obj.Get('waveLengthMeters', AHull.WaveLengthMeters);
    AHull.WaveSpeedMps := Obj.Get('waveSpeedMps', AHull.WaveSpeedMps);
    AHull.CenterOfMassOffsetY := Obj.Get('centerOfMassOffsetY', AHull.CenterOfMassOffsetY);
    AHull.EvaluateHydrostatics;
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TBuoyancyHullHelper.GenerateMarkdownReport(
  const AHull: TCastleBuoyancyHull): String;
var
  SL: TStringList;
  S: THullHydrostaticState;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Multi-Pontoon Buoyancy Hydrostatics & Righting-Torque Report');
    SL.Add('');
    if AHull = nil then
    begin
      SL.Add('_No `TCastleBuoyancyHull` found in the active design._');
      Exit(SL.Text);
    end;
    S := AHull.LastState;
    SL.Add('- **Hull Name**: `' + AHull.Name + '` (`' +
      BuoyancyPresetToString(AHull.Preset) + '`)');
    SL.Add(FormatDot('- **Mass / Fluid Density**: `%.1f kg` / `%.1f kg/m^3` (`%d / %d` pontoons submerged)',
      [AHull.HullMassKg, AHull.FluidDensityKgM3, S.SubmergedPontoonCount, S.PontoonCount]));
    SL.Add(FormatDot('- **Displaced Volume / Buoyant Force**: `%.3f m^3` / `%.1f N` (Net Vertical `%.1f N`)',
      [S.TotalDisplacedVolumeM3, S.TotalBuoyantUpForceN, S.NetVerticalForceN]));
    SL.Add(FormatDot('- **Attitude & Righting Torque**: Roll `%.2f deg`, Pitch `%.2f deg`, Torque `(%.1f, %.1f, %.1f) Nm`',
      [S.RollDeg, S.PitchDeg, S.NetRightingTorqueNm.X, S.NetRightingTorqueNm.Y, S.NetRightingTorqueNm.Z]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
