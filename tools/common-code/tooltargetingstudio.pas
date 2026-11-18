{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless helper for Targeting System Preset Lock-On & Aim-Assist Studio (Phase 359). }
unit ToolTargetingStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleTargetingSystem;

type
  TTargetingStudioHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindTargetingInHierarchy(const Root: TComponent): TCastleTargetingBehavior;
    class function SpawnTargetingCombatRange(const Root, DesignOwner: TComponent;
      out PlayerActor: TCastleTransform;
      out Targeting: TCastleTargetingBehavior): Boolean;
    class function GenerateTargetingReport(const Targeting: TCastleTargetingBehavior): String;
  end;

implementation

class function TTargetingStudioHelper.FindViewport(const Root: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleViewport then Exit(TCastleViewport(Root));
  for I := 0 to Root.ComponentCount - 1 do
  begin
    Result := FindViewport(Root.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TTargetingStudioHelper.FindTargetingInHierarchy(const Root: TComponent): TCastleTargetingBehavior;

  function WalkTransform(const T: TCastleTransform): TCastleTargetingBehavior;
  var
    I: Integer;
  begin
    Result := T.FindBehavior(TCastleTargetingBehavior) as TCastleTargetingBehavior;
    if Result <> nil then Exit;
    for I := 0 to T.Count - 1 do
    begin
      Result := WalkTransform(T[I]);
      if Result <> nil then Exit;
    end;
  end;

var
  Vp: TCastleViewport;
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleTargetingBehavior then Exit(TCastleTargetingBehavior(Root));
  if Root is TCastleTransform then
  begin
    Result := WalkTransform(TCastleTransform(Root));
    if Result <> nil then Exit;
  end;
  Vp := FindViewport(Root);
  if (Vp <> nil) and (Vp.Items <> nil) then
  begin
    Result := WalkTransform(Vp.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to Root.ComponentCount - 1 do
    if Root.Components[I] is TCastleTargetingBehavior then
      Exit(TCastleTargetingBehavior(Root.Components[I]));
end;

class function TTargetingStudioHelper.SpawnTargetingCombatRange(const Root, DesignOwner: TComponent;
  out PlayerActor: TCastleTransform;
  out Targeting: TCastleTargetingBehavior): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  PBox, CoverWall: TCastleBox;

  procedure SpawnTargetDummy(const AName, AFaction: String; const APos: TVector3;
    const AThreat: Integer; const AHp: Single; const ACol: TCastleColor);
  var
    B: TCastleBox;
    TB: TCastleTargetableBehavior;
  begin
    if OwnerComp.FindComponent(AName) <> nil then Exit;
    B := TCastleBox.Create(OwnerComp);
    B.Name := AName;
    B.Size := Vector3(0.85, 1.85, 0.85);
    B.Translation := APos;
    B.Color := ACol;
    Vp.Items.Add(B);

    TB := TCastleTargetableBehavior.Create(OwnerComp);
    TB.Name := AName + '_Targetable';
    TB.FactionTag := AFaction;
    TB.ThreatPriorityTier := AThreat;
    TB.HealthRatio := AHp;
    B.AddBehavior(TB);
  end;

begin
  Result := False;
  PlayerActor := nil;
  Targeting := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  PlayerActor := OwnerComp.FindComponent('TargetingHeroPlayer') as TCastleTransform;
  if PlayerActor = nil then
  begin
    PBox := TCastleBox.Create(OwnerComp);
    PBox.Name := 'TargetingHeroPlayer';
    PBox.Size := Vector3(0.75, 1.80, 0.75);
    PBox.Translation := Vector3(0.0, 0.0, 0.0);
    PBox.Direction := Vector3(0.0, 0.0, -1.0);
    PBox.Color := Vector4(0.25, 0.72, 1.0, 1.0);
    Vp.Items.Add(PBox);
    PlayerActor := PBox;
  end;

  { 1. Left Grunt (-X, clear LoS), 2. Center Boss (Threat 10, clear LoS),
    3. Right Sniper (+X, clear LoS), 4. Occluded Enemy behind stone pillar,
    5. Friendly Wounded Medic Target (HP = 20%) }
  SpawnTargetDummy('EnemyGruntLeft', 'Enemy', Vector3(-4.8, 0.0, -10.0), 3, 0.90,
    Vector4(0.92, 0.52, 0.20, 1.0));
  SpawnTargetDummy('EnemyWarlordBoss', 'Enemy', Vector3(0.4, 0.0, -11.0), 10, 0.85,
    Vector4(0.96, 0.20, 0.22, 1.0));
  SpawnTargetDummy('EnemySniperRight', 'Enemy', Vector3(4.5, 0.0, -10.5), 5, 0.75,
    Vector4(0.88, 0.36, 0.92, 1.0));

  if OwnerComp.FindComponent('TargetingCoverWall') = nil then
  begin
    CoverWall := TCastleBox.Create(OwnerComp);
    CoverWall.Name := 'TargetingCoverWall';
    CoverWall.Size := Vector3(1.2, 3.2, 0.6);
    CoverWall.Translation := Vector3(-1.8, 1.2, -6.5);
    CoverWall.Color := Vector4(0.38, 0.40, 0.45, 1.0);
    Vp.Items.Add(CoverWall);
  end;
  SpawnTargetDummy('EnemyHiddenBehindWall', 'Enemy', Vector3(-1.8, 0.0, -9.5), 9, 1.0,
    Vector4(0.55, 0.22, 0.22, 1.0));

  SpawnTargetDummy('FriendlyTankFullHp', 'Friendly', Vector3(-3.8, 0.0, -8.5), 4, 0.95,
    Vector4(0.24, 0.88, 0.45, 1.0));
  SpawnTargetDummy('FriendlyScoutCriticalHp', 'Friendly', Vector3(2.2, 0.0, -9.0), 4, 0.18,
    Vector4(0.22, 0.95, 0.78, 1.0));

  Targeting := PlayerActor.FindBehavior(TCastleTargetingBehavior) as TCastleTargetingBehavior;
  if Targeting = nil then
  begin
    Targeting := TCastleTargetingBehavior.Create(OwnerComp);
    Targeting.Name := 'TargetingBehavior1';
    Targeting.Preset := tpkMeleeSoulsHardLockOn;
    PlayerActor.AddBehavior(Targeting);
  end;

  Targeting.EvaluateTargetingStack(Vector3(0.0, 1.25, 0.0), Vector3(0.0, 0.0, -1.0), Vp.Items);
  Result := True;
end;

class function TTargetingStudioHelper.GenerateTargetingReport(
  const Targeting: TCastleTargetingBehavior): String;
var
  I: Integer;
  E: TTargetCandidateEval;
  LockStr: String;
begin
  if Targeting = nil then
    Exit('# Targeting System Preset Report' + LineEnding + LineEnding +
         '_No `TCastleTargetingBehavior` found in design._');

  if Targeting.LockedTarget <> nil then
    LockStr := Targeting.LockedTarget.Name
  else
    LockStr := 'None';

  Result :=
    '# Targeting System Preset Stack Report (Phase 359)' + LineEnding + LineEnding +
    Format('- **Preset**: %s (`Faction=%s`, `MaxRange=%.1fm`, `HalfCone=%.0f deg`, `LoS=%s`)', [
      TargetingPresetToString(Targeting.Preset), Targeting.RequiredFactionTag,
      Targeting.MaxLockRangeMeters, Targeting.MaxHalfConeAngleDeg,
      BoolToStr(Targeting.RequireLineOfSight, True)]) + LineEnding +
    Format('- **Locked Target**: **`%s`** (`%d / %d` candidates passed filters)', [
      LockStr, Targeting.ValidCandidateCount, Targeting.CandidateCount]) + LineEnding + LineEnding +
    '| Candidate | Dist (m) | Cone (deg) | LoS | Status / Rejection | Score |' + LineEnding +
    '| :--- | :--- | :--- | :--- | :--- | :--- |' + LineEnding;

  for I := 0 to Targeting.CandidateCount - 1 do
  begin
    E := Targeting.GetCandidateEval(I);
    Result := Result + Format('| `%s` | `%.2f` | `%.1f` | %s | %s | `%.3f` |', [
      E.TargetName, E.DistanceMeters, E.ViewConeAngleDeg,
      BoolToStr(E.HasLineOfSight, 'CLEAR', 'OCCLUDED'),
      BoolToStr(E.PassedFilters, '**VALID**', E.RejectedReason),
      E.TotalWeightedScore]) + LineEnding;
  end;
end;

end.
