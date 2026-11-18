{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless helper for the Chaos Mover 2.0 Rollback-Ready Kinematic Character
  Modes (Walk, Slide, Wall-Run, Swim & Grapple) Studio (Phase 351). }
unit ToolMoverStudio;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleMover2;

type
  TMoverStudioSummary = record
    MoverCount: Integer;
    CurrentTick: Integer;
    RollbackResims: Integer;
    ActiveModeName: String;
    SpeedMps: Single;
    WarningsCount: Integer;
  end;

  TMoverStudioHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstMover(const ARoot: TComponent): TCastleMoverBehavior; static;

    class function SpawnMover2ArenaDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out AActor: TCastleTransform;
      out AMover: TCastleMoverBehavior): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TMoverStudioSummary; static;

    class function BuildMarkdownReport(const ARoot: TComponent): String; static;
  end;

implementation

function MakeUniqueName(const AOwner: TComponent; const ABase: String): String;
var
  Idx: Integer;
begin
  Result := ABase;
  if (AOwner = nil) or (AOwner.FindComponent(Result) = nil) then
    Exit;
  Idx := 1;
  repeat
    Result := ABase + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function TMoverStudioHelper.ResolveRootTransform(
  const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

class function TMoverStudioHelper.FindFirstMover(
  const ARoot: TComponent): TCastleMoverBehavior;

  function ScanRec(const T: TCastleTransform): TCastleMoverBehavior;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleMoverBehavior then
        Exit(TCastleMoverBehavior(T.Behaviors[I]));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TMoverStudioHelper.SpawnMover2ArenaDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out AActor: TCastleTransform;
  out AMover: TCastleMoverBehavior): Boolean;
var
  RootT: TCastleTransform;
  TowerBeacon: TCastleSphere;
  WallPanel: TCastleBox;
  PawnCyl: TCastleCylinder;
  I: Integer;
begin
  AActor := nil;
  AMover := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  TowerBeacon := TCastleSphere.Create(ADesignOwner);
  TowerBeacon.Name := MakeUniqueName(ADesignOwner, 'MoverGrappleBeacon');
  TowerBeacon.Radius := 0.48;
  TowerBeacon.Translation := Vector3(0.0, 8.5, -14.0);
  TowerBeacon.Color := Vector4(0.26, 0.88, 0.96, 1.0);
  RootT.Add(TowerBeacon);

  WallPanel := TCastleBox.Create(ADesignOwner);
  WallPanel.Name := MakeUniqueName(ADesignOwner, 'MoverWallRunPanel');
  WallPanel.Size := Vector3(0.6, 4.5, 16.0);
  WallPanel.Translation := Vector3(-3.0, 2.25, -8.0);
  WallPanel.Color := Vector4(0.42, 0.46, 0.56, 1.0);
  RootT.Add(WallPanel);

  PawnCyl := TCastleCylinder.Create(ADesignOwner);
  PawnCyl.Name := MakeUniqueName(ADesignOwner, 'Mover2Character');
  PawnCyl.Radius := 0.36;
  PawnCyl.Height := 1.75;
  PawnCyl.Color := Vector4(0.96, 0.72, 0.24, 1.0);
  RootT.Add(PawnCyl);
  AActor := PawnCyl;

  AMover := TCastleMoverBehavior.Create(ADesignOwner);
  AMover.Name := MakeUniqueName(ADesignOwner, 'Mover2Behavior');
  PawnCyl.AddBehavior(AMover);
  AMover.ResetStateAtPosition(Vector3(0.0, 0.0, 0.0), mlmGroundWalk);

  for I := 1 to 12 do
    AMover.AdvanceTick(TMoverInputCmd.WalkForward(Vector3(0, 0, -1)), 1.0 / 60.0);
  Result := True;
end;

class function TMoverStudioHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TMoverStudioSummary;
var
  M: TCastleMoverBehavior;
begin
  Result := Default(TMoverStudioSummary);
  M := FindFirstMover(ARoot);
  if M = nil then
  begin
    Result.ActiveModeName := 'None';
    Exit;
  end;

  Result.MoverCount := 1;
  Result.CurrentTick := M.CurrentState.TickIndex;
  Result.RollbackResims := M.RollbackResimCount;
  Result.ActiveModeName := MoverModeToDisplayName(M.CurrentState.Mode);
  Result.SpeedMps := M.CurrentState.Velocity.Length;

  if M.WalkMaxSpeed <= 0.1 then
  begin
    Inc(Result.WarningsCount);
    if AWarnings <> nil then
      AWarnings.Add('WalkMaxSpeed <= 0.1 m/s; character ground locomotion is immobilized.');
  end;
end;

class function TMoverStudioHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TMoverStudioSummary;
  M: TCastleMoverBehavior;
  S: TMoverSyncState;
  SB: TStringBuilder;
  I, StartTick: Integer;
  H: TMoverHistoryEntry;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    M := FindFirstMover(ARoot);
    SB.AppendLine('# Castle Game Engine — Chaos Mover 2.0 Rollback Character Locomotion Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Active Locomotion Mode**: **%s** (`Tick #%d`, `%d` rollback resimulations)', [
      Sum.ActiveModeName, Sum.CurrentTick, Sum.RollbackResims]));
    if M <> nil then
    begin
      S := M.CurrentState;
      SB.AppendLine(Format('- **SyncState Position / Speed**: `(%.2f, %.2f, %.2f)` / `%.2f m/s`', [
        S.Position.X, S.Position.Y, S.Position.Z, Sum.SpeedMps]));
      SB.AppendLine;
      SB.AppendLine('| Tick | Mode | Position `(m)` | Speed `(m/s)` |');
      SB.AppendLine('| ---: | :--- | :--- | ---: |');
      StartTick := Max(1, S.TickIndex - 9);
      for I := StartTick to S.TickIndex do
        if M.GetHistoryEntryByTick(I, H) then
          SB.AppendLine(Format('| `%d` | `%s` | `(%.2f, %.2f, %.2f)` | `%.2f` |', [
            I, MoverModeToDisplayName(H.AfterState.Mode),
            H.AfterState.Position.X, H.AfterState.Position.Y, H.AfterState.Position.Z,
            H.AfterState.Velocity.Length]));
    end;
    if Warnings.Count > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('## Diagnostics');
      for I := 0 to Warnings.Count - 1 do
        SB.AppendLine('- ' + Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Warnings);
  end;
end;

end.
