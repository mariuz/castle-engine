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

{ Stateless Editor & Headless Helper for Environment Query System (EQS)
  Tactical Cover / Sniper Vantage / Flank Arena Spawning, Batch Query
  Evaluation & QA Diagnostics (@link(TEqsStudioHelper), @link(TEqsAuditReport))
  (Phase 319 — UE 6.0+ EQS Parity). }
unit ToolEqsStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleEqsTactical;

type
  TEqsBehaviorArray = array of TCastleEqsQueryBehavior;

  { QA summary across all EQS tactical query behaviors in a design. }
  TEqsAuditReport = class
  public
    QueryCount: Integer;
    SolvedCount: Integer;
    TotalCandidates: Integer;
    TotalValidCandidates: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, evaluating, and auditing
    @link(TCastleEqsQueryBehavior) instances. }
  TEqsStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanEqsBehaviors(const RootComp, DesignOwner: TComponent;
      out OutQueries: TEqsBehaviorArray); static;

    class procedure SpawnTacticalCoverArenaDemo(
      const RootComp, DesignOwner: TComponent;
      out OutAgent, OutThreat, OutCoverWall, OutSniperPlatform: TCastleTransform;
      out OutEqs: TCastleEqsQueryBehavior); static;

    class procedure RunAllQueries(const RootComp, DesignOwner: TComponent); static;

    class function AuditEqsQueries(
      const RootComp, DesignOwner: TComponent): TEqsAuditReport; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleColors, CastleScene;

constructor TEqsAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TEqsAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TEqsStudioHelper.FindMainViewport(const RootComp: TComponent): TCastleViewport;
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

class procedure TEqsStudioHelper.ScanEqsBehaviors(
  const RootComp, DesignOwner: TComponent;
  out OutQueries: TEqsBehaviorArray);

  procedure AddUnique(const Q: TCastleEqsQueryBehavior);
  var
    K: Integer;
  begin
    if (Q = nil) or (csTransient in Q.ComponentStyle) then
      Exit;
    for K := 0 to High(OutQueries) do
      if OutQueries[K] = Q then
        Exit;
    SetLength(OutQueries, Length(OutQueries) + 1);
    OutQueries[High(OutQueries)] := Q;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleEqsQueryBehavior then
      AddUnique(TCastleEqsQueryBehavior(C));
    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Walk(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutQueries := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TEqsStudioHelper.SpawnTacticalCoverArenaDemo(
  const RootComp, DesignOwner: TComponent;
  out OutAgent, OutThreat, OutCoverWall, OutSniperPlatform: TCastleTransform;
  out OutEqs: TCastleEqsQueryBehavior);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  FloorBox, WallBox, BalconyBox, AgentBox, ThreatBox: TCastleBox;
  Idx: Integer;
begin
  OutAgent := nil;
  OutThreat := nil;
  OutCoverWall := nil;
  OutSniperPlatform := nil;
  OutEqs := nil;

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

  if (OwnerToUse = nil) or (OwnerToUse.FindComponent('EqsArenaFloor') = nil) then
  begin
    FloorBox := TCastleBox.Create(OwnerToUse);
    FloorBox.Name := 'EqsArenaFloor';
    FloorBox.Size := Vector3(50.0, 1.0, 50.0);
    FloorBox.Translation := Vector3(0.0, -0.5, 0.0);
    FloorBox.Color := Vector4(0.24, 0.27, 0.30, 1.0);
    ParentTrans.Add(FloorBox);
  end;

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('EqsSquadAgent' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  WallBox := TCastleBox.Create(OwnerToUse);
  WallBox.Name := 'EqsCoverWall' + IntToStr(Idx);
  WallBox.Size := Vector3(6.5, 3.0, 1.2);
  WallBox.Translation := Vector3(0.0, 1.5, 0.0);
  WallBox.Color := Vector4(0.56, 0.58, 0.62, 1.0);
  ParentTrans.Add(WallBox);

  BalconyBox := TCastleBox.Create(OwnerToUse);
  BalconyBox.Name := 'EqsSniperBalcony' + IntToStr(Idx);
  BalconyBox.Size := Vector3(5.0, 2.8, 5.0);
  BalconyBox.Translation := Vector3(7.0, 1.4, 4.0);
  BalconyBox.Color := Vector4(0.42, 0.48, 0.58, 1.0);
  ParentTrans.Add(BalconyBox);

  ThreatBox := TCastleBox.Create(OwnerToUse);
  ThreatBox.Name := 'EqsHostileThreat' + IntToStr(Idx);
  ThreatBox.Size := Vector3(0.85, 1.80, 0.85);
  ThreatBox.Translation := Vector3(0.0, 0.90, -7.5);
  { Rotate 180 deg around Y so local -Z Forward points along +Z toward the arena }
  ThreatBox.Rotation := Vector4(0.0, 1.0, 0.0, Pi);
  ThreatBox.Color := Vector4(0.94, 0.26, 0.24, 1.0);
  ParentTrans.Add(ThreatBox);

  AgentBox := TCastleBox.Create(OwnerToUse);
  AgentBox.Name := 'EqsSquadAgent' + IntToStr(Idx);
  AgentBox.Size := Vector3(0.75, 1.80, 0.75);
  AgentBox.Translation := Vector3(2.0, 0.90, 3.5);
  AgentBox.Color := Vector4(0.22, 0.82, 0.56, 1.0);
  ParentTrans.Add(AgentBox);

  OutEqs := TCastleEqsQueryBehavior.Create(OwnerToUse);
  OutEqs.Name := 'EqsTacticalQuery_' + IntToStr(Idx);
  OutEqs.ThreatTransform := ThreatBox;
  OutEqs.ApplyPreset(epTakeCoverFromThreat);
  AgentBox.AddBehavior(OutEqs);
  OutEqs.RunQuery;

  OutAgent := AgentBox;
  OutThreat := ThreatBox;
  OutCoverWall := WallBox;
  OutSniperPlatform := BalconyBox;
end;

class procedure TEqsStudioHelper.RunAllQueries(const RootComp, DesignOwner: TComponent);
var
  Queries: TEqsBehaviorArray;
  I: Integer;
begin
  ScanEqsBehaviors(RootComp, DesignOwner, Queries);
  for I := 0 to High(Queries) do
    Queries[I].RunQuery;
end;

class function TEqsStudioHelper.AuditEqsQueries(
  const RootComp, DesignOwner: TComponent): TEqsAuditReport;
var
  Queries: TEqsBehaviorArray;
  Q: TCastleEqsQueryBehavior;
  I: Integer;
begin
  Result := TEqsAuditReport.Create;
  ScanEqsBehaviors(RootComp, DesignOwner, Queries);
  Result.QueryCount := Length(Queries);
  for I := 0 to High(Queries) do
  begin
    Q := Queries[I];
    Result.TotalCandidates := Result.TotalCandidates + Q.CandidateCount;
    Result.TotalValidCandidates := Result.TotalValidCandidates + Q.ValidCandidateCount;
    if Q.HasValidBestSpot then
      Inc(Result.SolvedCount);
    if Q.ThreatTransform = nil then
      Result.Warnings.Add(Format(
        'EQS Query "%s" has no ThreatTransform assigned — assign a target transform for accurate LoS and flank scoring.',
        [Q.Name]));
    if (Q.CandidateCount > 0) and (not Q.HasValidBestSpot) then
      Result.Warnings.Add(Format(
        'EQS Query "%s" (%s) rejected all %d candidates — add cover geometry or widen GridHalfExtent/OuterRadius.',
        [Q.Name, TCastleEqsQueryBehavior.PresetDisplayName(Q.Preset), Q.CandidateCount]));
  end;
end;

class function TEqsStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Queries: TEqsBehaviorArray;
  Rep: TEqsAuditReport;
  SB: TStringBuilder;
  Q: TCastleEqsQueryBehavior;
  I: Integer;
begin
  ScanEqsBehaviors(RootComp, DesignOwner, Queries);
  Rep := AuditEqsQueries(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Environment Query System (EQS) Tactical AI Studio Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **EQS Queries:** %d (`%d` solved, `%d / %d` valid candidates)',
      [Rep.QueryCount, Rep.SolvedCount, Rep.TotalValidCandidates, Rep.TotalCandidates]));
    SB.AppendLine('');
    for I := 0 to High(Queries) do
    begin
      Q := Queries[I];
      SB.AppendLine(Format('- `%s` %s -> Best=(%.2f, %.2f, %.2f) Score=%.2f',
        [Q.Name, Q.EqsSummaryBadge, Q.BestWorldPos.X, Q.BestWorldPos.Y, Q.BestWorldPos.Z, Q.BestScore]));
    end;
    if Rep.Warnings.Count > 0 then
    begin
      SB.AppendLine('');
      SB.AppendLine('## QA Warnings');
      for I := 0 to Rep.Warnings.Count - 1 do
        SB.AppendLine('- ' + Rep.Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Rep);
  end;
end;

end.
