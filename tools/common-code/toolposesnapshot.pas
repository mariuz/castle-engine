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

{ Stateless helper for Skeletal Pose Snapshot & Dash Ghost Trail Studio (Phase 375). }
unit ToolPoseSnapshot;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastlePoseSnapshot;

type
  TPoseSnapshotHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindPoseTrailInHierarchy(const Root: TComponent): TCastlePoseSnapshotTrail;
    class function SpawnDashGhostTrailDemo(const Root, DesignOwner: TComponent;
      out Trail: TCastlePoseSnapshotTrail): Boolean;
    class function GeneratePoseSnapshotReport(const Trail: TCastlePoseSnapshotTrail): String;
  end;

implementation

uses CastleUtils;

class function TPoseSnapshotHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TPoseSnapshotHelper.FindPoseTrailInHierarchy(
  const Root: TComponent): TCastlePoseSnapshotTrail;

  function WalkTransform(const T: TCastleTransform): TCastlePoseSnapshotTrail;
  var
    I: Integer;
  begin
    if T is TCastlePoseSnapshotTrail then
      Exit(TCastlePoseSnapshotTrail(T));
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
  if Root is TCastlePoseSnapshotTrail then Exit(TCastlePoseSnapshotTrail(Root));
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
    if Root.Components[I] is TCastlePoseSnapshotTrail then
      Exit(TCastlePoseSnapshotTrail(Root.Components[I]));
end;

class function TPoseSnapshotHelper.SpawnDashGhostTrailDemo(
  const Root, DesignOwner: TComponent;
  out Trail: TCastlePoseSnapshotTrail): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  I: Integer;
begin
  Result := False;
  Trail := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  Trail := FindPoseTrailInHierarchy(Root);
  if Trail = nil then
  begin
    Trail := TCastlePoseSnapshotTrail.Create(OwnerComp);
    Trail.Name := 'DashPoseTrail1';
    Trail.Preset := ptpCyberpunkCyanDash;
    Vp.Items.Add(Trail);
  end;
  Trail.UnfreezeStatuePose;
  Trail.ClearAllGhosts;
  for I := 0 to 3 do
  begin
    Trail.StepGhostDecay(0.10);
    Trail.CaptureDashAfterimage(Vector3(I * 1.85, 0.0, 0.0), 0.12 * I, I * 0.25);
  end;
  Result := True;
end;

class function TPoseSnapshotHelper.GeneratePoseSnapshotReport(
  const Trail: TCastlePoseSnapshotTrail): String;
var
  I: Integer;
  G: TPoseGhostEntry;
begin
  if Trail = nil then
    Exit('# Pose Snapshot & Dash Ghost Trail Report' + NL + NL +
      '_No `TCastlePoseSnapshotTrail` in scene._');

  Result :=
    '# Skeletal Pose Snapshot & Dash Ghost Trail Report (Phase 375)' + NL + NL +
    Format('- **Component**: `%s` %s', [Trail.Name, Trail.PoseSummaryBadge]) + NL +
    Format('- **Ring Buffer**: `%d / %d` active ghosts (Total captured: `%d`, Lifetime: `%.2f s`)', [
      Trail.ActiveGhostCount, Trail.MaxGhostCount, Trail.TotalCapturedCount, Trail.GhostLifetimeSec]) + NL +
    Format('- **Petrified Statue Lock**: `%s`', [BoolToStr(Trail.IsStatueFrozen, 'FROZEN_STONE_STATUE', 'UNLOCKED_LIVE')]) + NL + NL +
    '## Active Ring Buffer Slots' + NL;

  for I := 0 to Trail.MaxGhostCount - 1 do
  begin
    G := Trail.GetGhostSlot(I);
    if G.Active then
      Result := Result + Format(
        '- Slot `#%d` (Seq `%d`): Pos `(%.2f, %.2f, %.2f)` | Remaining `%.2f s` | Alpha `%.2f`' + NL,
        [I, G.SequenceNumber, G.WorldPos.X, G.WorldPos.Y, G.WorldPos.Z,
         G.RemainingLifeSec, G.CurrentAlpha]);
  end;
end;

end.
