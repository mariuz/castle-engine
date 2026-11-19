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

{ Stateless helper for AI Sensory Perception Sight, Hearing & Scent Studio (Phase 378). }
unit ToolSensoryPerception;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions,
  CastleViewport, CastleSensoryPerception;

type
  TSensoryPerceptionHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindSensorInHierarchy(const Root: TComponent): TCastleSensoryPerception;
    class function SpawnStealthCourtyardSensorDemo(const Root, DesignOwner: TComponent;
      out Sensor: TCastleSensoryPerception): Boolean;
    class function GenerateSensoryReport(const Sensor: TCastleSensoryPerception): String;
  end;

implementation

uses CastleUtils;

class function TSensoryPerceptionHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TSensoryPerceptionHelper.FindSensorInHierarchy(
  const Root: TComponent): TCastleSensoryPerception;

  function WalkTransform(const T: TCastleTransform): TCastleSensoryPerception;
  var
    I: Integer;
  begin
    if T is TCastleSensoryPerception then
      Exit(TCastleSensoryPerception(T));
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
  if Root is TCastleSensoryPerception then Exit(TCastleSensoryPerception(Root));
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
    if Root.Components[I] is TCastleSensoryPerception then
      Exit(TCastleSensoryPerception(Root.Components[I]));
end;

class function TSensoryPerceptionHelper.SpawnStealthCourtyardSensorDemo(
  const Root, DesignOwner: TComponent;
  out Sensor: TCastleSensoryPerception): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  WallBox: TCastleBox;
begin
  Result := False;
  Sensor := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('CourtyardCoverWall') = nil then
  begin
    WallBox := TCastleBox.Create(OwnerComp);
    WallBox.Name := 'CourtyardCoverWall';
    WallBox.Size := Vector3(5.0, 3.0, 0.6);
    WallBox.Translation := Vector3(0.0, 1.5, 8.0);
    WallBox.Material := pmPhysical;
    WallBox.Color := Vector4(0.45, 0.44, 0.48, 1.0);
    Vp.Items.Add(WallBox);
  end;

  Sensor := FindSensorInHierarchy(Root);
  if Sensor = nil then
  begin
    Sensor := TCastleSensoryPerception.Create(OwnerComp);
    Sensor.Name := 'GuardSensor1';
    Sensor.Preset := sppHumanGuardPatrol;
    Sensor.Translation := Vector3(0.0, 0.0, 0.0);
    Sensor.SensorYawDeg := 0.0;
    Vp.Items.Add(Sensor);
  end;
  Result := True;
end;

class function TSensoryPerceptionHelper.GenerateSensoryReport(
  const Sensor: TCastleSensoryPerception): String;
begin
  if Sensor = nil then
    Exit('# AI Sensory Perception Report' + NL + NL +
      '_No `TCastleSensoryPerception` in scene._');

  Result :=
    '# AI Sensory Perception Sight, Hearing & Scent Report (Phase 378)' + NL + NL +
    Format('- **Sensor**: `%s` %s', [Sensor.Name, Sensor.SensorySummaryBadge]) + NL +
    Format('- **Vision Cones**: Range `%.1f m` | Fovea `+/-%.1f deg` | Peripheral `+/-%.1f deg` | Eye Height `%.2f m`', [
      Sensor.SightRangeMeters, Sensor.FovealHalfAngleDeg,
      Sensor.PeripheralHalfAngleDeg, Sensor.EyeHeightMeters]) + NL +
    Format('- **Acoustic Hearing**: Threshold `%.1f dB` | Solid-Wall Muffle Penalty `-%.1f dB`', [
      Sensor.HearingThresholdDb, Sensor.WallMufflePenaltyDb]) + NL +
    Format('- **Olfactory Scent**: Sniff Radius `%.1f m` | Active Breadcrumbs `%d` | Lifetime `%.1f s`', [
      Sensor.ScentSniffRadiusMeters, Sensor.ActiveScentCount, Sensor.ScentLifetimeSec]) + NL +
    Format('- **Current Alertness**: `%.0f%%` — Last Stimulus: `%s` at `(%.2f, %.2f, %.2f)`', [
      Sensor.Awareness01 * 100.0, Sensor.LastStimulusSummary,
      Sensor.LastStimulusPos.X, Sensor.LastStimulusPos.Y, Sensor.LastStimulusPos.Z]) + NL;
end;

end.
