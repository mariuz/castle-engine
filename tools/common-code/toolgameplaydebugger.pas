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

{ Stateless helper for GameplayDebugger Live 3D HUD Overlay & Channels Studio (Phase 363). }
unit ToolGameplayDebugger;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleGameplayDebugger;

type
  TGameplayDebuggerHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindDebuggerInHierarchy(const Root: TComponent): TCastleGameplayDebugger;
    class function SpawnMultiSubsystemDebugSandbox(const Root, DesignOwner: TComponent;
      out Debugger: TCastleGameplayDebugger;
      out HeroActor: TCastleTransform): Boolean;
    class function GenerateDebuggerReport(const Debugger: TCastleGameplayDebugger): String;
  end;

implementation

uses CastleStateTree, CastleTargetingSystem, CastleGameplayAbility,
  CastleMover2, CastleMassTraffic, CastleSurfaceGi;

class function TGameplayDebuggerHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TGameplayDebuggerHelper.FindDebuggerInHierarchy(const Root: TComponent): TCastleGameplayDebugger;

  function WalkTransform(const T: TCastleTransform): TCastleGameplayDebugger;
  var
    I: Integer;
  begin
    if T is TCastleGameplayDebugger then
      Exit(TCastleGameplayDebugger(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := WalkTransform(T[I]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

var
  Vp: TCastleViewport;
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleGameplayDebugger then Exit(TCastleGameplayDebugger(Root));
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
    if Root.Components[I] is TCastleGameplayDebugger then
      Exit(TCastleGameplayDebugger(Root.Components[I]));
end;

class function TGameplayDebuggerHelper.SpawnMultiSubsystemDebugSandbox(
  const Root, DesignOwner: TComponent;
  out Debugger: TCastleGameplayDebugger;
  out HeroActor: TCastleTransform): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  HeroBox, EnemyBox: TCastleBox;
  St: TCastleStateTreeBehavior;
  Targ: TCastleTargetingBehavior;
  Targetable: TCastleTargetableBehavior;
  Gas: TCastleAbilitySystemBehavior;
  Mov: TCastleMoverBehavior;
  Traffic: TCastleMassTrafficManager;
  Gi: TCastleSurfaceGiGrid;
begin
  Result := False;
  Debugger := nil;
  HeroActor := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  EnemyBox := OwnerComp.FindComponent('DebugBossTarget') as TCastleBox;
  if EnemyBox = nil then
  begin
    EnemyBox := TCastleBox.Create(OwnerComp);
    EnemyBox.Name := 'DebugBossTarget';
    EnemyBox.Size := Vector3(1.1, 2.1, 1.1);
    EnemyBox.Translation := Vector3(0.0, 1.05, -6.5);
    EnemyBox.Color := Vector4(0.92, 0.24, 0.24, 1.0);
    Vp.Items.Add(EnemyBox);

    Targetable := TCastleTargetableBehavior.Create(OwnerComp);
    Targetable.ThreatPriorityTier := 5;
    EnemyBox.AddBehavior(Targetable);
  end;

  HeroActor := OwnerComp.FindComponent('DebuggedPaladinHero') as TCastleTransform;
  if HeroActor = nil then
  begin
    HeroBox := TCastleBox.Create(OwnerComp);
    HeroBox.Name := 'DebuggedPaladinHero';
    HeroBox.Size := Vector3(0.85, 1.85, 0.85);
    HeroBox.Translation := Vector3(0.0, 0.92, 0.0);
    HeroBox.Color := Vector4(0.22, 0.78, 1.0, 1.0);
    Vp.Items.Add(HeroBox);
    HeroActor := HeroBox;

    St := TCastleStateTreeBehavior.Create(OwnerComp);
    St.ApplyPreset(stpTacticalGuardSquad);
    HeroBox.AddBehavior(St);

    Targ := TCastleTargetingBehavior.Create(OwnerComp);
    HeroBox.AddBehavior(Targ);
    Targ.EvaluateTargetingStack(HeroBox.WorldTranslation, Vector3(0, 0, -1), Vp.Items);

    Gas := TCastleAbilitySystemBehavior.Create(OwnerComp);
    Gas.GrantTag('Class.Paladin');
    Gas.GrantTag('Status.Buff.Aegis');
    HeroBox.AddBehavior(Gas);

    Mov := TCastleMoverBehavior.Create(OwnerComp);
    Mov.ResetStateAtPosition(HeroBox.Translation, mlmGroundWalk);
    Mov.AdvanceTick(TMoverInputCmd.WalkForward(Vector3(0, 0, -1)), 1.0 / 60.0);
    HeroBox.AddBehavior(Mov);
  end;

  if OwnerComp.FindComponent('DebugMassTraffic1') = nil then
  begin
    Traffic := TCastleMassTrafficManager.Create(OwnerComp);
    Traffic.Name := 'DebugMassTraffic1';
    Vp.Items.Add(Traffic);
  end;

  if OwnerComp.FindComponent('DebugSurfaceGi1') = nil then
  begin
    Gi := TCastleSurfaceGiGrid.Create(OwnerComp);
    Gi.Name := 'DebugSurfaceGi1';
    Vp.Items.Add(Gi);
    Gi.BakeIrradianceProbes(Vp.Items);
  end;

  Debugger := FindDebuggerInHierarchy(Root);
  if Debugger = nil then
  begin
    Debugger := TCastleGameplayDebugger.Create(OwnerComp);
    Debugger.Name := 'GameplayDebugger1';
    Debugger.DebuggedActorName := 'DebuggedPaladinHero';
    Debugger.EnableAllChannels;
    Vp.Items.Add(Debugger);
  end;

  Debugger.CollectSnapshotFromWorld(Vp.Items);
  Result := True;
end;

class function TGameplayDebuggerHelper.GenerateDebuggerReport(
  const Debugger: TCastleGameplayDebugger): String;
var
  Ch: TGameplayDebugChannel;
  I: Integer;
begin
  if Debugger = nil then
    Exit('# GameplayDebugger 3D HUD & Channels Report' + LineEnding + LineEnding +
         '_No `TCastleGameplayDebugger` found in design._');

  Result :=
    '# GameplayDebugger Live 3D HUD & Hotkey Channels Report (Phase 363)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Overlay Status** | **`%s`** (`ChannelMask = %d`) |', [
      BoolToStr(Debugger.OverlayActive, 'ACTIVE', 'HIDDEN'), Debugger.ChannelMask]) + LineEnding +
    Format('| **Debugged Actor** | `%s` (`%d` HUD lines, `%d` 3D beacons) |', [
      Debugger.ResolvedActorName, Debugger.HudLineCount, Debugger.MarkerCount]) + LineEnding + LineEnding +
    '## Numpad `0..5` Diagnostic Channels' + LineEnding +
    '| Hotkey Channel | State |' + LineEnding +
    '| :--- | :--- |' + LineEnding;

  for Ch := Low(TGameplayDebugChannel) to High(TGameplayDebugChannel) do
    Result := Result + Format('| `%s` | **`%s`** |', [
      GameplayDebugChannelName(Ch),
      BoolToStr(Debugger.IsChannelEnabled(Ch), 'ON', 'OFF')]) + LineEnding;

  Result := Result + LineEnding + '## Live Aggregated HUD Telemetry' + LineEnding;
  if Debugger.HudLineCount = 0 then
    Result := Result + '_(No active HUD lines — spawn sandbox or enable Numpad 0..5 channels)_' + LineEnding
  else
    for I := 0 to Debugger.HudLineCount - 1 do
      Result := Result + '- `' + Debugger.GetHudLine(I) + '`' + LineEnding;
end;

end.
