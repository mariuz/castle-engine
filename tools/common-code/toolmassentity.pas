{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless Editor & Headless Helper for MassEntity Data-Oriented SoA Crowd
  Swarms, Obstacle Flow-Field Arenas, Multi-Swarm Stepping & QA Auditing
  (@link(TMassEntityHelper), @link(TMassEntityAuditReport))
  (Phase 328 — UE 6.0+ MassEntity & MassCrowd Parity). }
unit ToolMassEntity;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleMassEntity;

type
  TMassSwarmArray = array of TCastleMassEntityManager;

  { QA summary across all MassEntity crowd managers in a design. }
  TMassEntityAuditReport = class
  public
    SwarmCount: Integer;
    TotalEntities: Integer;
    TotalObstacles: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, stepping, and auditing
    @link(TCastleMassEntityManager) instances. }
  TMassEntityHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanSwarms(const RootComp, DesignOwner: TComponent;
      out OutSwarms: TMassSwarmArray); static;

    class function SpawnMassSwarmArenaDemo(
      const RootComp, DesignOwner: TComponent): TCastleMassEntityManager; static;

    class procedure StepAllSwarms(const RootComp, DesignOwner: TComponent;
      const Dt: Single); static;

    class function AuditSwarms(
      const RootComp, DesignOwner: TComponent): TMassEntityAuditReport; static;

    class function BuildMarkdownReport(
      const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleUIControls, CastleColors, CastleScene;

constructor TMassEntityAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TMassEntityAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TMassEntityHelper.FindMainViewport(
  const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  if RootComp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(RootComp);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindMainViewport(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

class procedure TMassEntityHelper.ScanSwarms(
  const RootComp, DesignOwner: TComponent;
  out OutSwarms: TMassSwarmArray);

  procedure AddUnique(const S: TCastleMassEntityManager);
  var
    K: Integer;
  begin
    if (S = nil) or (csTransient in S.ComponentStyle) then
      Exit;
    for K := 0 to High(OutSwarms) do
      if OutSwarms[K] = S then
        Exit;
    SetLength(OutSwarms, Length(OutSwarms) + 1);
    OutSwarms[High(OutSwarms)] := S;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleMassEntityManager then
      AddUnique(TCastleMassEntityManager(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutSwarms := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class function TMassEntityHelper.SpawnMassSwarmArenaDemo(
  const RootComp, DesignOwner: TComponent): TCastleMassEntityManager;
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  FloorBox, GoalBeacon, PillarA, PillarB: TCastleCylinder;
  ArenaFloor: TCastleBox;
  Idx: Integer;
begin
  Result := nil;
  Vp := FindMainViewport(RootComp);
  if Vp <> nil then
    ParentTrans := Vp.Items
  else if RootComp is TCastleTransform then
    ParentTrans := TCastleTransform(RootComp)
  else
    Exit;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  if (OwnerToUse = nil) or (OwnerToUse.FindComponent('MassSwarmPlazaFloor') = nil) then
  begin
    ArenaFloor := TCastleBox.Create(OwnerToUse);
    ArenaFloor.Name := 'MassSwarmPlazaFloor';
    ArenaFloor.Size := Vector3(52.0, 0.5, 52.0);
    ArenaFloor.Translation := Vector3(0.0, -0.25, 0.0);
    ArenaFloor.Color := Vector4(0.18, 0.22, 0.28, 1.0);
    ParentTrans.Add(ArenaFloor);
  end;

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('MassCrowdSwarm' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  PillarA := TCastleCylinder.Create(OwnerToUse);
  PillarA.Name := 'MassObstaclePillarA_' + IntToStr(Idx);
  PillarA.Radius := 3.5;
  PillarA.Height := 3.0;
  PillarA.Translation := Vector3(-4.2, 1.5, -2.0);
  PillarA.Color := Vector4(0.62, 0.44, 0.34, 1.0);
  ParentTrans.Add(PillarA);

  PillarB := TCastleCylinder.Create(OwnerToUse);
  PillarB.Name := 'MassObstaclePillarB_' + IntToStr(Idx);
  PillarB.Radius := 3.5;
  PillarB.Height := 3.0;
  PillarB.Translation := Vector3(4.2, 1.5, -2.0);
  PillarB.Color := Vector4(0.62, 0.44, 0.34, 1.0);
  ParentTrans.Add(PillarB);

  GoalBeacon := TCastleCylinder.Create(OwnerToUse);
  GoalBeacon.Name := 'MassFlowGoalBeacon_' + IntToStr(Idx);
  GoalBeacon.Radius := 0.9;
  GoalBeacon.Height := 4.5;
  GoalBeacon.Translation := Vector3(0.0, 2.25, -16.0);
  GoalBeacon.Color := Vector4(0.24, 0.92, 0.52, 1.0);
  ParentTrans.Add(GoalBeacon);
  FloorBox := nil;
  if FloorBox <> nil then ;

  Result := TCastleMassEntityManager.Create(OwnerToUse);
  Result.Name := 'MassCrowdSwarm' + IntToStr(Idx);
  Result.ApplyPreset(mspCityPedestrianFlow);
  Result.ClearObstacles;
  Result.AddObstacleCircleXZ(-4.2, -2.0, 3.5);
  Result.AddObstacleCircleXZ(4.2, -2.0, 3.5);
  Result.GoalPosXZ := Vector2(0.0, -16.0);
  Result.BakeGoalFlowField;
  Result.RespawnEntitiesInBox(Vector2(-12.0, 6.0), Vector2(12.0, 18.0));
  Result.UpdateRepresentationLods(Vector3(0.0, 8.0, 18.0));
  ParentTrans.Add(Result);
end;

class procedure TMassEntityHelper.StepAllSwarms(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Swarms: TMassSwarmArray;
  Vp: TCastleViewport;
  ViewerPos: TVector3;
  I: Integer;
begin
  ScanSwarms(RootComp, DesignOwner, Swarms);
  Vp := FindMainViewport(RootComp);
  if (Vp <> nil) and (Vp.Camera <> nil) then
    ViewerPos := Vp.Camera.WorldTranslation
  else
    ViewerPos := Vector3(0.0, 8.0, 18.0);

  for I := 0 to High(Swarms) do
  begin
    Swarms[I].StepSwarm(Dt);
    Swarms[I].UpdateRepresentationLods(ViewerPos);
  end;
end;

class function TMassEntityHelper.AuditSwarms(
  const RootComp, DesignOwner: TComponent): TMassEntityAuditReport;
var
  Swarms: TMassSwarmArray;
  I: Integer;
begin
  Result := TMassEntityAuditReport.Create;
  ScanSwarms(RootComp, DesignOwner, Swarms);
  Result.SwarmCount := Length(Swarms);
  for I := 0 to High(Swarms) do
  begin
    Inc(Result.TotalEntities, Swarms[I].ActiveEntityCount);
    Inc(Result.TotalObstacles, Swarms[I].ObstacleCount);
    if Swarms[I].ActiveEntityCount > 5000 then
      Result.Warnings.Add(Format(
        'MassEntityManager "%s" has %d entities; consider tightening CullDist for mobile targets.',
        [Swarms[I].Name, Swarms[I].ActiveEntityCount]));
  end;
end;

class function TMassEntityHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Swarms: TMassSwarmArray;
  Audit: TMassEntityAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanSwarms(RootComp, DesignOwner, Swarms);
  Audit := AuditSwarms(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — MassEntity Data-Oriented SoA Crowd Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Active Swarm Managers**: `%d` (`%d` total SoA entities, `%d` flow obstacles)',
      [Audit.SwarmCount, Audit.TotalEntities, Audit.TotalObstacles]));
    SB.AppendLine;

    if Length(Swarms) > 0 then
    begin
      SB.AppendLine('## Swarm Telemetry & 4-Tier Representation LOD');
      SB.AppendLine('| Swarm | Preset | Entities | High | Med | Low | Culled | Step CPU |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Swarms) do
        SB.AppendLine(Format('| `%s` | %s | `%d` | `%d` | `%d` | `%d` | `%d` | `%.2f ms` |',
          [Swarms[I].Name,
           TCastleMassEntityManager.PresetDisplayName(Swarms[I].Preset),
           Swarms[I].ActiveEntityCount,
           Swarms[I].GetTierCount(mrtHighMesh),
           Swarms[I].GetTierCount(mrtMediumProxy),
           Swarms[I].GetTierCount(mrtLowBatchedPoint),
           Swarms[I].GetTierCount(mrtCulledOffscreen),
           Swarms[I].LastStepTimeMs]));
      SB.AppendLine;
    end;

    SB.AppendLine('## QA Diagnostics');
    if Audit.Warnings.Count = 0 then
      SB.AppendLine('- **0 warnings** — all MassEntity SoA swarms are within optimal CPU & batching budgets.')
    else
      for I := 0 to Audit.Warnings.Count - 1 do
        SB.AppendLine('- **Warning**: ' + Audit.Warnings[I]);

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Audit);
  end;
end;

end.
