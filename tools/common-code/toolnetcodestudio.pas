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

{ Stateless Editor & Headless Helper for Iris-Style Netcode Replication,
  Spatial Relevancy Culling, Snapshot Interpolation & Lag-Compensated Hitbox
  Rewind (@link(TNetcodeStudioHelper), @link(TNetcodeAuditReport))
  (Phase 321 — UE 6.0+ Iris Replication & Lag Compensation Parity). }
unit ToolNetcodeStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleNetcodeIris;

type
  TNetManagerArray = array of TCastleNetReplicationManager;

  { QA summary across all Iris replication managers and replicated actors in a design. }
  TNetcodeAuditReport = class
  public
    ManagerCount: Integer;
    ReplicatedActorCount: Integer;
    RelevantActorCount: Integer;
    EstimatedKbps: Single;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, stepping, and auditing
    @link(TCastleNetReplicationManager) and @link(TCastleReplicatedBehavior). }
  TNetcodeStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanNetcode(const RootComp, DesignOwner: TComponent;
      out OutManagers: TNetManagerArray;
      out OutActors: TReplicatedBehaviorArray); static;

    class procedure SpawnMultiplayerIrisArenaDemo(
      const RootComp, DesignOwner: TComponent;
      out OutManager: TCastleNetReplicationManager;
      out OutSprintTarget, OutFarCulledProp: TCastleTransform;
      out OutTargetRep, OutFarRep: TCastleReplicatedBehavior); static;

    class function AuditNetcode(
      const RootComp, DesignOwner: TComponent): TNetcodeAuditReport; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  Math,
  CastleColors, CastleScene;

constructor TNetcodeAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TNetcodeAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TNetcodeStudioHelper.FindMainViewport(const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  Found: TCastleViewport;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  for I := 0 to RootComp.ComponentCount - 1 do
  begin
    Found := FindMainViewport(RootComp.Components[I]);
    if Found <> nil then
      Exit(Found);
  end;
end;

class procedure TNetcodeStudioHelper.ScanNetcode(
  const RootComp, DesignOwner: TComponent;
  out OutManagers: TNetManagerArray;
  out OutActors: TReplicatedBehaviorArray);

  procedure AddMgrUnique(const M: TCastleNetReplicationManager);
  var
    K: Integer;
  begin
    if (M = nil) or (csTransient in M.ComponentStyle) then
      Exit;
    for K := 0 to High(OutManagers) do
      if OutManagers[K] = M then
        Exit;
    SetLength(OutManagers, Length(OutManagers) + 1);
    OutManagers[High(OutManagers)] := M;
  end;

  procedure WalkManagers(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleNetReplicationManager then
      AddMgrUnique(TCastleNetReplicationManager(C));
    for I := 0 to C.ComponentCount - 1 do
      WalkManagers(C.Components[I]);
    if C is TCastleViewport then
      WalkManagers(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        WalkManagers(T[I]);
    end;
  end;

begin
  OutManagers := nil;
  WalkManagers(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    WalkManagers(DesignOwner);
  CollectReplicatedBehaviors(RootComp, DesignOwner, OutActors);
end;

class procedure TNetcodeStudioHelper.SpawnMultiplayerIrisArenaDemo(
  const RootComp, DesignOwner: TComponent;
  out OutManager: TCastleNetReplicationManager;
  out OutSprintTarget, OutFarCulledProp: TCastleTransform;
  out OutTargetRep, OutFarRep: TCastleReplicatedBehavior);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  TargetBox, FarBox: TCastleBox;
  Idx: Integer;
begin
  OutManager := nil;
  OutSprintTarget := nil;
  OutFarCulledProp := nil;
  OutTargetRep := nil;
  OutFarRep := nil;

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

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('NetSprintTarget' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  OutManager := TCastleNetReplicationManager.Create(OwnerToUse);
  OutManager.Name := 'IrisReplicationMgr_' + IntToStr(Idx);

  TargetBox := TCastleBox.Create(OwnerToUse);
  TargetBox.Name := 'NetSprintTarget' + IntToStr(Idx);
  TargetBox.Size := Vector3(0.85, 1.80, 0.85);
  TargetBox.Translation := Vector3(0.0, 0.90, -10.0);
  TargetBox.Color := Vector4(0.96, 0.34, 0.28, 1.0);
  ParentTrans.Add(TargetBox);

  OutTargetRep := TCastleReplicatedBehavior.Create(OwnerToUse);
  OutTargetRep.Name := 'RepSprintTarget_' + IntToStr(Idx);
  OutTargetRep.NetId := Cardinal(100 + Idx);
  OutTargetRep.BasePriority := 3.0;
  OutTargetRep.NetCullDistance := 45.0;
  OutTargetRep.HitboxRadius := 0.70;
  OutTargetRep.HitboxHeightOffset := 0.0; // TargetBox origin is already at Y=0.90 center
  TargetBox.AddBehavior(OutTargetRep);

  FarBox := TCastleBox.Create(OwnerToUse);
  FarBox.Name := 'NetFarDistantCrate' + IntToStr(Idx);
  FarBox.Size := Vector3(1.2, 1.2, 1.2);
  FarBox.Translation := Vector3(0.0, 0.60, -120.0); // > 45m NetCullDistance
  FarBox.Color := Vector4(0.45, 0.50, 0.56, 1.0);
  ParentTrans.Add(FarBox);

  OutFarRep := TCastleReplicatedBehavior.Create(OwnerToUse);
  OutFarRep.Name := 'RepFarCrate_' + IntToStr(Idx);
  OutFarRep.NetId := Cardinal(200 + Idx);
  OutFarRep.BasePriority := 0.5;
  OutFarRep.NetCullDistance := 45.0;
  FarBox.AddBehavior(OutFarRep);

  OutSprintTarget := TargetBox;
  OutFarCulledProp := FarBox;
  OutManager.StepReplication(RootComp, DesignOwner, 0.05, TVector3.Zero);
end;

class function TNetcodeStudioHelper.AuditNetcode(
  const RootComp, DesignOwner: TComponent): TNetcodeAuditReport;
var
  Mgrs: TNetManagerArray;
  Actors: TReplicatedBehaviorArray;
  I: Integer;
begin
  Result := TNetcodeAuditReport.Create;
  ScanNetcode(RootComp, DesignOwner, Mgrs, Actors);
  Result.ManagerCount := Length(Mgrs);
  Result.ReplicatedActorCount := Length(Actors);

  for I := 0 to High(Actors) do
    if Actors[I].LastRelevant then
      Inc(Result.RelevantActorCount);

  for I := 0 to High(Mgrs) do
    Result.EstimatedKbps := Max(Result.EstimatedKbps, Mgrs[I].EstimatedBandwidthKbps);

  if (Result.ReplicatedActorCount > 0) and (Result.ManagerCount = 0) then
    Result.Warnings.Add(
      'Design contains TCastleReplicatedBehavior actors without a TCastleNetReplicationManager — spawn an Iris Replication Manager.');

  for I := 0 to High(Mgrs) do
    if Mgrs[I].ClientInterpDelayMs < (1000.0 / Max(1.0, Mgrs[I].ServerTickHz)) then
      Result.Warnings.Add(Format(
        'NetManager "%s" ClientInterpDelayMs (%.0fms) is shorter than 1 server tick (%.0fms) — client interpolation may stutter.',
        [Mgrs[I].Name, Mgrs[I].ClientInterpDelayMs, 1000.0 / Max(1.0, Mgrs[I].ServerTickHz)]));
end;

class function TNetcodeStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Mgrs: TNetManagerArray;
  Actors: TReplicatedBehaviorArray;
  Rep: TNetcodeAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanNetcode(RootComp, DesignOwner, Mgrs, Actors);
  Rep := AuditNetcode(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Iris Netcode Replication, Interpolation & Hitbox Rewind Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **Replication Managers:** %d (`%.1f kbps` peak)',
      [Rep.ManagerCount, Rep.EstimatedKbps]));
    SB.AppendLine(Format('- **Replicated Actors:** %d (`%d` relevant, `%d` spatially culled)',
      [Rep.ReplicatedActorCount, Rep.RelevantActorCount,
       Rep.ReplicatedActorCount - Rep.RelevantActorCount]));
    SB.AppendLine('');
    for I := 0 to High(Mgrs) do
      SB.AppendLine(Format('- `%s`: %s', [Mgrs[I].Name, Mgrs[I].NetManagerSummaryBadge]));
    for I := 0 to High(Actors) do
      SB.AppendLine(Format('- `%s`: %s', [Actors[I].Name, Actors[I].ReplicatedSummaryBadge]));
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Rep);
  end;
end;

end.
