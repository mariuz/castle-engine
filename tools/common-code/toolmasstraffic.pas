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

{ Stateless helper for MassTraffic Multi-Lane Signal & IDM Headway Studio (Phase 355). }
unit ToolMassTraffic;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport, CastleMassTraffic;

type
  TMassTrafficHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindTrafficInHierarchy(const Root: TComponent): TCastleMassTrafficManager;
    class function SpawnMassTrafficCrossroads(const Root, DesignOwner: TComponent;
      out Traffic: TCastleMassTrafficManager): Boolean;
    class function GenerateMassTrafficReport(const Traffic: TCastleMassTrafficManager): String;
  end;

implementation

class function TMassTrafficHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TMassTrafficHelper.FindTrafficInHierarchy(const Root: TComponent): TCastleMassTrafficManager;

  function WalkTransform(const T: TCastleTransform): TCastleMassTrafficManager;
  var
    I: Integer;
  begin
    if T is TCastleMassTrafficManager then
      Exit(TCastleMassTrafficManager(T));
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
  if Root is TCastleMassTrafficManager then Exit(TCastleMassTrafficManager(Root));
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
    if Root.Components[I] is TCastleMassTrafficManager then
      Exit(TCastleMassTrafficManager(Root.Components[I]));
end;

class function TMassTrafficHelper.SpawnMassTrafficCrossroads(const Root, DesignOwner: TComponent;
  out Traffic: TCastleMassTrafficManager): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
begin
  Result := False;
  Traffic := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  Traffic := FindTrafficInHierarchy(Root);
  if Traffic = nil then
  begin
    Traffic := TCastleMassTrafficManager.Create(OwnerComp);
    Traffic.Name := 'CityMassTraffic1';
    Traffic.Preset := mtpDowntownCrossroads24;
    Vp.Items.Add(Traffic);
  end;
  Result := True;
end;

class function TMassTrafficHelper.GenerateMassTrafficReport(const Traffic: TCastleMassTrafficManager): String;
var
  S: TMassTrafficStats;
begin
  if Traffic = nil then
    Exit('# MassTraffic Multi-Lane & Signal Studio Report' + LineEnding + LineEnding +
         '_No `TCastleMassTrafficManager` found in design._');

  S := Traffic.Stats;
  Result :=
    '# MassTraffic Multi-Lane Signal & IDM Headway Report (Phase 355)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component** | `%s` (%s) |', [Traffic.Name, MassTrafficPresetToString(Traffic.Preset)]) + LineEnding +
    Format('| **Road Topology** | `%d` Directed Lanes (`4` Approaches x `2` Lanes) |', [S.LaneCount]) + LineEnding +
    Format('| **Active NEMA Signal Phase** | **`%s`** (`Transitions = %d`) |', [
      TrafficSignalPhaseToString(Traffic.SignalPhase), S.TotalPhaseTransitions]) + LineEnding +
    Format('| **Active Fleet & Mean Speed** | `%d` vehicles @ **`%.2f m/s`** (`Headway = %.2fs`) |', [
      S.ActiveVehicles, S.MeanSpeedMps, Traffic.SafeTimeHeadwaySec]) + LineEnding +
    Format('| **Stopped Red-Light Queue** | `%d` vehicles cleanly queued behind stop line |', [
      S.StoppedQueueCount]) + LineEnding +
    Format('| **Safety Invariants** | `RearEndOverlapCount = %d` / `SignalConflictCount = %d` |', [
      S.RearEndOverlapCount, S.SignalConflictCount]);
end;

end.
