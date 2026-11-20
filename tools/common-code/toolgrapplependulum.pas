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

{ Design-time helper for Grappling Hook & Vine 3D Spherical Pendulum Swing,
  Motorized Winch Reel-In & Apex Release Studio (Phase 403). }
unit ToolGrapplePendulum;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleGrapplePendulum;

type
  TGrapplePendulumHelper = class
  public
    class function FindFirstRig(const ARoot: TComponent): TCastleGrapplePendulum;
    class function SpawnGargoyleChasmSwingDemo(const ARoot, AOwner: TComponent;
      out ARig: TCastleGrapplePendulum): Boolean;
    class function ExportRigJson(const ARig: TCastleGrapplePendulum): String;
    class function ImportRigJson(const ARig: TCastleGrapplePendulum;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ARig: TCastleGrapplePendulum): String;
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

class function TGrapplePendulumHelper.FindFirstRig(
  const ARoot: TComponent): TCastleGrapplePendulum;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleGrapplePendulum;
  var
    J: Integer;
  begin
    if T is TCastleGrapplePendulum then
      Exit(TCastleGrapplePendulum(T));
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
  if ARoot is TCastleGrapplePendulum then
    Exit(TCastleGrapplePendulum(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleGrapplePendulum then
      Exit(TCastleGrapplePendulum(ARoot.Components[I]));
end;

class function TGrapplePendulumHelper.SpawnGargoyleChasmSwingDemo(
  const ARoot, AOwner: TComponent; out ARig: TCastleGrapplePendulum): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  ArchBeam: TCastleBox;
begin
  Result := False;
  ARig := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Overhead stone bridge arch beam centered at (0, 14.5, 0), underside at Y = 14.0 }
  ArchBeam := TCastleBox.Create(Own);
  ArchBeam.Name := 'ChasmOverheadGargoyleBeam';
  ArchBeam.Size := Vector3(4.0, 1.0, 4.0);
  ArchBeam.Translation := Vector3(0.0, 14.5, 0.0);
  ArchBeam.Color := Vector4(0.36, 0.35, 0.40, 1.0);
  VP.Items.Add(ArchBeam);

  ARig := TCastleGrapplePendulum.Create(Own);
  ARig.Name := 'ChasmGrappleRig';
  ARig.ApplyPreset(gppJungleVineTarzanSwing);
  VP.Items.Add(ARig);

  { Fire grapple hook from (-8, 8, 0) aiming toward (0, 14.2, 0) -> locks onto underside (L = 10.0m)! }
  ARig.FireGrappleHookRay(VP.Items, Vector3(-8.0, 8.0, 0.0),
    Vector3(8.0, 6.0, 0.0), TVector3.Zero);
  Result := True;
end;

class function TGrapplePendulumHelper.ExportRigJson(
  const ARig: TCastleGrapplePendulum): String;
var
  Obj: TJSONObject;
begin
  if ARig = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ARig.Preset));
    Obj.Add('max_range_m', ARig.MaxRangeMeters);
    Obj.Add('rider_mass_kg', ARig.RiderMassKg);
    Obj.Add('winch_speed_mps', ARig.WinchReelSpeedMps);
    Obj.Add('min_winch_m', ARig.MinWinchLengthMeters);
    Obj.Add('apex_up_mps', ARig.ApexJumpUpSpeedMps);
    Obj.Add('apex_fwd_mps', ARig.ApexJumpForwardBoostMps);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TGrapplePendulumHelper.ImportRigJson(
  const ARig: TCastleGrapplePendulum; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ARig = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(ARig.Preset));
    if (POrd >= Ord(Low(TGrapplePendulumPreset))) and
       (POrd <= Ord(High(TGrapplePendulumPreset))) then
      ARig.ApplyPreset(TGrapplePendulumPreset(POrd));
    ARig.MaxRangeMeters := Obj.Get('max_range_m', ARig.MaxRangeMeters);
    ARig.RiderMassKg := Obj.Get('rider_mass_kg', ARig.RiderMassKg);
    ARig.WinchReelSpeedMps := Obj.Get('winch_speed_mps', ARig.WinchReelSpeedMps);
    ARig.MinWinchLengthMeters := Obj.Get('min_winch_m', ARig.MinWinchLengthMeters);
    ARig.ApexJumpUpSpeedMps := Obj.Get('apex_up_mps', ARig.ApexJumpUpSpeedMps);
    ARig.ApexJumpForwardBoostMps := Obj.Get('apex_fwd_mps', ARig.ApexJumpForwardBoostMps);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TGrapplePendulumHelper.GenerateMarkdownReport(
  const ARig: TCastleGrapplePendulum): String;
var
  SL: TStringList;
  S: TGrappleSwingState;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Grappling Hook 3D Spherical Pendulum & Winch Report');
    SL.Add('');
    if ARig = nil then
    begin
      SL.Add('_No `TCastleGrapplePendulum` found in the current design._');
      Exit(SL.Text);
    end;
    S := ARig.State;
    SL.Add('- **Rig**: `' + ARig.Name + '` (`' +
      GrapplePendulumPresetToString(ARig.Preset) + '`)');
    SL.Add(FormatDot('- **Hook Attached**: `%s` (Taut: `%s`, Rope L = `%.2f m`)',
      [BoolToStr(S.HookAttached, True), BoolToStr(S.RopeIsTaut, True), S.RopeLengthMeters]));
    SL.Add(FormatDot('- **Anchor World Pos**: `(%.2f, %.2f, %.2f)`',
      [S.AnchorWorldPos.X, S.AnchorWorldPos.Y, S.AnchorWorldPos.Z]));
    SL.Add(FormatDot('- **Player World Pos**: `(%.2f, %.2f, %.2f)`',
      [S.PlayerWorldPos.X, S.PlayerWorldPos.Y, S.PlayerWorldPos.Z]));
    SL.Add(FormatDot('- **Tangential Speed**: `%.2f m/s`   |   **Cable Tension**: `%.0f N`',
      [S.VelocityMps.Length, S.CableTensionNewtons]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
