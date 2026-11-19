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

{ Design-time helper for Gameplay Interaction Focus Scanner (WorldRay Gaze +
  Proximity Cone, Hold-Progress Ring & Obstruction Gate) Studio (Phase 394). }
unit ToolInteractScanner;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleInteractScanner;

type
  TInteractScannerHelper = class
  public
    class function FindFirstScanner(const ARoot: TComponent): TCastleInteractScanner;
    class function SpawnVaultRoomInteractDemo(const ARoot, AOwner: TComponent;
      out AScanner: TCastleInteractScanner): Boolean;
    class function ExportScannerJson(const AScanner: TCastleInteractScanner): String;
    class function ImportScannerJson(const AScanner: TCastleInteractScanner;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AScanner: TCastleInteractScanner): String;
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

class function TInteractScannerHelper.FindFirstScanner(
  const ARoot: TComponent): TCastleInteractScanner;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleInteractScanner;
  var
    J: Integer;
  begin
    if T is TCastleInteractScanner then
      Exit(TCastleInteractScanner(T));
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
  if ARoot is TCastleInteractScanner then
    Exit(TCastleInteractScanner(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleInteractScanner then
      Exit(TCastleInteractScanner(ARoot.Components[I]));
end;

class function TInteractScannerHelper.SpawnVaultRoomInteractDemo(
  const ARoot, AOwner: TComponent; out AScanner: TCastleInteractScanner): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  VaultDoorWall, KeycardConsole, BlockedLootChest, SideAmmoCrate: TCastleBox;
begin
  Result := False;
  AScanner := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Solid locked vault partition blocking through-wall looting }
  VaultDoorWall := TCastleBox.Create(Own);
  VaultDoorWall.Name := 'LockedVaultDoorSlab';
  VaultDoorWall.Size := Vector3(1.8, 2.6, 0.28);
  VaultDoorWall.Translation := Vector3(-0.9, 1.3, -2.0);
  VaultDoorWall.Color := Vector4(0.38, 0.40, 0.45, 1.0);
  VP.Items.Add(VaultDoorWall);

  { Behind-wall chest at (-0.9, 0.6, -2.9) -> closer in range, but blocked by door! }
  BlockedLootChest := TCastleBox.Create(Own);
  BlockedLootChest.Name := 'Interact_VaultChestBehindWall';
  BlockedLootChest.Size := Vector3(0.7, 0.5, 0.5);
  BlockedLootChest.Translation := Vector3(-0.9, 0.6, -2.9);
  BlockedLootChest.Color := Vector4(0.95, 0.72, 0.18, 1.0);
  VP.Items.Add(BlockedLootChest);

  { Clear keycard sabotage console right on the gaze axis at (0.35, 1.35, -2.6) }
  KeycardConsole := TCastleBox.Create(Own);
  KeycardConsole.Name := 'Interact_KeycardSabotageTerminal';
  KeycardConsole.Size := Vector3(0.45, 0.55, 0.25);
  KeycardConsole.Translation := Vector3(0.35, 1.35, -2.6);
  KeycardConsole.Color := Vector4(0.20, 0.88, 0.62, 1.0);
  VP.Items.Add(KeycardConsole);

  { Peripheral side crate at (1.25, 0.85, -2.5) -> lower gaze alignment }
  SideAmmoCrate := TCastleBox.Create(Own);
  SideAmmoCrate.Name := 'Interact_SideSupplyCrate';
  SideAmmoCrate.Size := Vector3(0.55, 0.45, 0.55);
  SideAmmoCrate.Translation := Vector3(1.25, 0.85, -2.5);
  SideAmmoCrate.Color := Vector4(0.42, 0.66, 0.88, 1.0);
  VP.Items.Add(SideAmmoCrate);

  AScanner := TCastleInteractScanner.Create(Own);
  AScanner.Name := 'PlayerCameraInteractScanner';
  AScanner.Translation := Vector3(0.0, 1.55, 0.0);
  AScanner.ApplyPreset(ispSurvivalTimedSabotage);
  VP.Items.Add(AScanner);

  AScanner.ScanBestInteractable(VP.Items);
  Result := True;
end;

class function TInteractScannerHelper.ExportScannerJson(
  const AScanner: TCastleInteractScanner): String;
var
  Obj: TJSONObject;
begin
  if AScanner = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AScanner.Preset));
    Obj.Add('maxInteractRangeMeters', AScanner.MaxInteractRangeMeters);
    Obj.Add('maxGazeHalfConeDeg', AScanner.MaxGazeHalfConeDeg);
    Obj.Add('gazeAngleWeight', AScanner.GazeAngleWeight);
    Obj.Add('proximityWeight', AScanner.ProximityWeight);
    Obj.Add('interactableNamePrefix', AScanner.InteractableNamePrefix);
    Obj.Add('requireUnobstructedLoS', AScanner.RequireUnobstructedLoS);
    Obj.Add('holdDurationSec', AScanner.HoldDurationSec);
    Obj.Add('releaseDecayRatePerSec', AScanner.ReleaseDecayRatePerSec);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TInteractScannerHelper.ImportScannerJson(
  const AScanner: TCastleInteractScanner; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AScanner = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(AScanner.Preset));
    if (POrd >= Ord(Low(TInteractScannerPreset))) and
       (POrd <= Ord(High(TInteractScannerPreset))) then
      AScanner.Preset := TInteractScannerPreset(POrd);
    AScanner.MaxInteractRangeMeters := Obj.Get('maxInteractRangeMeters', AScanner.MaxInteractRangeMeters);
    AScanner.MaxGazeHalfConeDeg := Obj.Get('maxGazeHalfConeDeg', AScanner.MaxGazeHalfConeDeg);
    AScanner.GazeAngleWeight := Obj.Get('gazeAngleWeight', AScanner.GazeAngleWeight);
    AScanner.ProximityWeight := Obj.Get('proximityWeight', AScanner.ProximityWeight);
    AScanner.InteractableNamePrefix := Obj.Get('interactableNamePrefix', AScanner.InteractableNamePrefix);
    AScanner.RequireUnobstructedLoS := Obj.Get('requireUnobstructedLoS', AScanner.RequireUnobstructedLoS);
    AScanner.HoldDurationSec := Obj.Get('holdDurationSec', AScanner.HoldDurationSec);
    AScanner.ReleaseDecayRatePerSec := Obj.Get('releaseDecayRatePerSec', AScanner.ReleaseDecayRatePerSec);
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TInteractScannerHelper.GenerateMarkdownReport(
  const AScanner: TCastleInteractScanner): String;
var
  SL: TStringList;
  I: Integer;
  C: TInteractCandidateScore;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Gameplay Interaction Focus Scanner & Hold-Progress Report');
    SL.Add('');
    if AScanner = nil then
    begin
      SL.Add('_No `TCastleInteractScanner` found in the active design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Scanner**: `' + AScanner.Name + '` (`' +
      InteractPresetToString(AScanner.Preset) + '`)');
    SL.Add('- **Focused Target**: `' + AScanner.FocusedTargetName + '` (`' +
      InteractStatusToString(AScanner.HoldStatus) + '`)');
    SL.Add(FormatDot('- **Hold Progress / Completed**: `%.0f%%` of `%.2f s` (`%d` completed)',
      [AScanner.HoldProgress01 * 100.0, AScanner.HoldDurationSec,
       AScanner.CompletedInteractionsCount]));
    SL.Add('');
    SL.Add('## Candidate Scores');
    for I := 0 to AScanner.CandidateCount - 1 do
    begin
      C := AScanner.GetCandidate(I);
      SL.Add(FormatDot('- `%s`: Dist=`%.2f m`, Gaze=`%.1f deg`, WallBlocked=`%s`, Score=`%.3f`',
        [C.TargetName, C.DistanceMeters, C.GazeAngleDeg,
         BoolToStr(C.ObstructedByWall, True), C.TotalScore]));
    end;
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
