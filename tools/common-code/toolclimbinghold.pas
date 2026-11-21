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

{ Design-time helper for Procedural Free-Climbing Hold Scanner
  (WorldRay Ledge/Crack Graph, Limb Reach & Overhang Stamina) Studio (Phase 410). }
unit ToolClimbingHold;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleClimbingHold;

type
  TClimbingHoldHelper = class
  public
    class function FindFirstScanner(const ARoot: TComponent): TCastleClimbingHoldScanner;
    class function SpawnTowerClimbDynoRouteDemo(const ARoot, AOwner: TComponent;
      out AScanner: TCastleClimbingHoldScanner): Boolean;
    class function ExportScannerJson(const AScanner: TCastleClimbingHoldScanner): String;
    class function ImportScannerJson(const AScanner: TCastleClimbingHoldScanner;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AScanner: TCastleClimbingHoldScanner): String;
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

class function TClimbingHoldHelper.FindFirstScanner(
  const ARoot: TComponent): TCastleClimbingHoldScanner;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleClimbingHoldScanner;
  var
    J: Integer;
  begin
    if T is TCastleClimbingHoldScanner then
      Exit(TCastleClimbingHoldScanner(T));
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
  if ARoot is TCastleClimbingHoldScanner then
    Exit(TCastleClimbingHoldScanner(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleClimbingHoldScanner then
      Exit(TCastleClimbingHoldScanner(ARoot.Components[I]));
end;

class function TClimbingHoldHelper.SpawnTowerClimbDynoRouteDemo(
  const ARoot, AOwner: TComponent; out AScanner: TCastleClimbingHoldScanner): Boolean;
const
  { 4 protruding stone bricks on the West face (with a 2.35m Dyno gap to summit!),
    while the East half (+X) of the sheer monolith has ZERO protruding bricks! }
  LedgeCoords: array[0..3] of TVector3 = (
    (X: -1.50; Y: 1.00; Z: -2.65),
    (X: -0.75; Y: 2.25; Z: -2.65),
    (X: -1.50; Y: 3.55; Z: -2.65),
    (X: -1.50; Y: 5.90; Z: -2.65)
  );
var
  VP: TCastleViewport;
  Own: TComponent;
  CliffWall, Brick: TCastleBox;
  I: Integer;
begin
  Result := False;
  AScanner := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Sheer smooth tower wall face at Z = -2.80 (centered at Z = -3.10, Size.Z = 0.60) }
  CliffWall := TCastleBox.Create(Own);
  CliffWall.Name := 'SheerMonolithTowerWall';
  CliffWall.Size := Vector3(7.0, 8.5, 0.60);
  CliffWall.Translation := Vector3(0.0, 4.25, -3.10);
  CliffWall.Color := Vector4(0.35, 0.36, 0.40, 1.0);
  VP.Items.Add(CliffWall);

  for I := 0 to High(LedgeCoords) do
  begin
    Brick := TCastleBox.Create(Own);
    Brick.Name := Format('ClimbProtrudingLedge_%d', [I + 1]);
    Brick.Size := Vector3(0.55, 0.22, 0.34);
    Brick.Translation := LedgeCoords[I];
    Brick.Color := Vector4(0.68, 0.58, 0.42, 1.0);
    VP.Items.Add(Brick);
  end;

  AScanner := TCastleClimbingHoldScanner.Create(Own);
  AScanner.Name := 'TowerClimbRouteScanner';
  AScanner.ApplyPreset(chpAthleticRockClimber);
  VP.Items.Add(AScanner);

  AScanner.ScanCliffLedgeHolds(VP.Items);
  Result := True;
end;

class function TClimbingHoldHelper.ExportScannerJson(
  const AScanner: TCastleClimbingHoldScanner): String;
var
  Obj: TJSONObject;
begin
  if AScanner = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AScanner.Preset));
    Obj.Add('min_lip_m', AScanner.MinLedgeLipDepthMeters);
    Obj.Add('static_reach_m', AScanner.MaxStaticLimbReachMeters);
    Obj.Add('dyno_reach_m', AScanner.MaxDynoLeapReachMeters);
    Obj.Add('stamina_drain', AScanner.BaseStaminaDrainPerSec);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TClimbingHoldHelper.ImportScannerJson(
  const AScanner: TCastleClimbingHoldScanner; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AScanner = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(AScanner.Preset));
    if (POrd >= Ord(Low(TClimbingHoldPreset))) and
       (POrd <= Ord(High(TClimbingHoldPreset))) then
      AScanner.ApplyPreset(TClimbingHoldPreset(POrd));
    AScanner.MinLedgeLipDepthMeters := Obj.Get('min_lip_m', AScanner.MinLedgeLipDepthMeters);
    AScanner.MaxStaticLimbReachMeters := Obj.Get('static_reach_m', AScanner.MaxStaticLimbReachMeters);
    AScanner.MaxDynoLeapReachMeters := Obj.Get('dyno_reach_m', AScanner.MaxDynoLeapReachMeters);
    AScanner.BaseStaminaDrainPerSec := Obj.Get('stamina_drain', AScanner.BaseStaminaDrainPerSec);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TClimbingHoldHelper.GenerateMarkdownReport(
  const AScanner: TCastleClimbingHoldScanner): String;
var
  SL: TStringList;
  StaticOk, DynoOk: Boolean;
  HopsStatic, HopsDyno: Integer;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Free-Climbing Hold Scanner, Reach Graph & Overhang Stamina Report');
    SL.Add('');
    if AScanner = nil then
    begin
      SL.Add('_No `TCastleClimbingHoldScanner` found in the current design._');
      Exit(SL.Text);
    end;
    StaticOk := AScanner.CanReachSummitBFS(1.5, 5.5, False, HopsStatic);
    DynoOk := AScanner.CanReachSummitBFS(1.5, 5.5, True, HopsDyno);
    SL.Add('- **Scanner**: `' + AScanner.Name + '` (`' +
      ClimbingHoldPresetToString(AScanner.Preset) + '`)');
    SL.Add(Format('- **Extracted Ledge Holds**: `%d` (`%d` static edges, `%d` Dyno edges)',
      [AScanner.HoldCount, AScanner.StaticEdgeCount, AScanner.DynoEdgeCount]));
    SL.Add(Format('- **Summit Reachable (Static Only)**: `%s`   |   **With Dyno Leap**: `%s` (`%d` hops)',
      [BoolToStr(StaticOk, True), BoolToStr(DynoOk, True), HopsDyno]));
    SL.Add(FormatDot('- **Stamina Drain**: Vertical `%.1f/s` | `+35 deg` Overhang `%.1f/s`',
      [AScanner.ComputeStaminaDrainPerSec(0.0, 0.0),
       AScanner.ComputeStaminaDrainPerSec(35.0, 0.0)]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
