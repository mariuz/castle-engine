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

{ Design-time helper for Tactical Boss Telegraph & AoE Hazard Zone
  (Pizza-Cone, Safe-Eye Donut, Line Charge & Jumpable Shock-Ring) Studio (Phase 412). }
unit ToolBossArena;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleBossArena;

type
  TBossArenaHelper = class
  public
    class function FindFirstDirector(const ARoot: TComponent): TCastleBossHazardDirector;
    class function SpawnRaidBossOverlapArenaDemo(const ARoot, AOwner: TComponent;
      out ADir: TCastleBossHazardDirector): Boolean;
    class function ExportDirectorJson(const ADir: TCastleBossHazardDirector): String;
    class function ImportDirectorJson(const ADir: TCastleBossHazardDirector;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const ADir: TCastleBossHazardDirector): String;
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

class function TBossArenaHelper.FindFirstDirector(
  const ARoot: TComponent): TCastleBossHazardDirector;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleBossHazardDirector;
  var
    J: Integer;
  begin
    if T is TCastleBossHazardDirector then
      Exit(TCastleBossHazardDirector(T));
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
  if ARoot is TCastleBossHazardDirector then
    Exit(TCastleBossHazardDirector(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleBossHazardDirector then
      Exit(TCastleBossHazardDirector(ARoot.Components[I]));
end;

class function TBossArenaHelper.SpawnRaidBossOverlapArenaDemo(
  const ARoot, AOwner: TComponent; out ADir: TCastleBossHazardDirector): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  ArenaFloor, ShelterPillar: TCastleBox;
begin
  Result := False;
  ADir := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  ArenaFloor := TCastleBox.Create(Own);
  ArenaFloor.Name := 'BossRaidCircularFloor';
  ArenaFloor.Size := Vector3(32.0, 0.4, 32.0);
  ArenaFloor.Translation := Vector3(0.0, -0.2, 0.0);
  ArenaFloor.Color := Vector4(0.24, 0.22, 0.28, 1.0);
  VP.Items.Add(ArenaFloor);

  { Stone line-of-sight pillar at (0, 1.8, +6.0) sheltering players at Z = +9.0! }
  ShelterPillar := TCastleBox.Create(Own);
  ShelterPillar.Name := 'RaidLineOfSightPillar';
  ShelterPillar.Size := Vector3(2.2, 3.6, 1.4);
  ShelterPillar.Translation := Vector3(0.0, 1.8, 6.0);
  ShelterPillar.Color := Vector4(0.45, 0.44, 0.50, 1.0);
  VP.Items.Add(ShelterPillar);

  ADir := TCastleBossHazardDirector.Create(Own);
  ADir.Name := 'BossRaidTelegraphDirector';
  ADir.ApplyPreset(bapStoryReadableTelegraphs);
  VP.Items.Add(ADir);

  { 1. 45-deg Frontal Breath Pizza-Cone along +Z (R = 14m, pillar-shelterable!) }
  ADir.SpawnPizzaConeTelegraph('DragonBreathPizzaCone', TVector3.Zero,
    Vector3(0.0, 0.0, 1.0), 14.0, 45.0, 2.0, 450.0, True);
  { 2. Safe-Inner-Eye Annular Donut (safe inside R < 3.5m, lethal in 3.5m..12m!) }
  ADir.SpawnSafeEyeDonutTelegraph('AbyssalSafeEyeDonut', TVector3.Zero,
    3.5, 12.0, 2.5, 600.0);
  { 3. Expanding Jump-Over Shockwave Ring (Rmax = 10m, jump > 0.90m clears it!) }
  ADir.SpawnJumpShockwaveRing('EarthshakerJumpRing', TVector3.Zero,
    10.0, 0.85, 0.90, 2.0, 320.0);
  ADir.StepTelegraphs(1.0);

  ADir.EvaluatePlayerSafety(VP.Items, Vector3(0.0, 0.0, 5.0));
  Result := True;
end;

class function TBossArenaHelper.ExportDirectorJson(
  const ADir: TCastleBossHazardDirector): String;
var
  Obj: TJSONObject;
begin
  if ADir = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ADir.Preset));
    Obj.Add('windup_scale', ADir.WindupSpeedScale);
    Obj.Add('dmg_mult', ADir.DamageMultiplier);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TBossArenaHelper.ImportDirectorJson(
  const ADir: TCastleBossHazardDirector; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ADir = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    POrd := Obj.Get('preset', Ord(ADir.Preset));
    if (POrd >= Ord(Low(TBossArenaPreset))) and
       (POrd <= Ord(High(TBossArenaPreset))) then
      ADir.ApplyPreset(TBossArenaPreset(POrd));
    ADir.WindupSpeedScale := Obj.Get('windup_scale', ADir.WindupSpeedScale);
    ADir.DamageMultiplier := Obj.Get('dmg_mult', ADir.DamageMultiplier);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TBossArenaHelper.GenerateMarkdownReport(
  const ADir: TCastleBossHazardDirector): String;
var
  SL: TStringList;
  E: TBossHazardEvalResult;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Tactical Boss Telegraph & AoE Hazard Zone Report');
    SL.Add('');
    if ADir = nil then
    begin
      SL.Add('_No `TCastleBossHazardDirector` found in the current design._');
      Exit(SL.Text);
    end;
    E := ADir.LastEval;
    SL.Add('- **Director**: `' + ADir.Name + '` (`' +
      BossArenaPresetToString(ADir.Preset) + '`)');
    SL.Add(Format('- **Active Overlapping Telegraphs**: `%d` (Threatening Player: `%d`)',
      [ADir.TelegraphCount, E.ThreateningZoneCount]));
    SL.Add(FormatDot('- **Potential Unmitigated Damage**: `%.0f` (Max Windup `%.0f%%`)',
      [E.PotentialDamageSum, E.MaxWindupProgress01 * 100.0]));
    SL.Add(Format('- **Mitigations**: Donut Eye `%s` | Jump Ring `%s` | Pillar Shelter `%s`',
      [BoolToStr(E.SavedByInnerDonutEye, True),
       BoolToStr(E.SavedByJumpOverRing, True),
       BoolToStr(E.SavedByPillarShelter, True)]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
