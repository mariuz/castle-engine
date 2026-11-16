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

{ Stateless Editor & Headless Helper for Motion Matching Pose Search Databases,
  Inertialized Character Locomotion Rigs, Multi-Agent Stepping & QA Auditing
  (@link(TMotionMatchingHelper), @link(TMotionMatchingAuditReport))
  (Phase 327 — UE 6.0+ Pose Search & Motion Matching Parity). }
unit ToolMotionMatching;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleMotionMatching;

type
  TPoseSearchDbArray = array of TCastlePoseSearchDatabase;
  TMotionMatcherArray = array of TCastleMotionMatchingBehavior;

  { QA summary across all Pose Search Databases & Motion Matching behaviors. }
  TMotionMatchingAuditReport = class
  public
    DatabaseCount: Integer;
    MatcherCount: Integer;
    UnboundMatcherCount: Integer;
    TotalIndexedPoses: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, stepping, and auditing
    @link(TCastlePoseSearchDatabase) and @link(TCastleMotionMatchingBehavior). }
  TMotionMatchingHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanMotionMatching(const RootComp, DesignOwner: TComponent;
      out OutDbs: TPoseSearchDbArray;
      out OutMatchers: TMotionMatcherArray); static;

    class procedure SpawnMotionMatchingArenaDemo(
      const RootComp, DesignOwner: TComponent;
      out OutHero: TCastleTransform;
      out OutDb: TCastlePoseSearchDatabase;
      out OutMatcher: TCastleMotionMatchingBehavior); static;

    class procedure StepAllMotionMatchers(const RootComp, DesignOwner: TComponent;
      const Dt: Single); static;

    class function AuditMotionMatchers(
      const RootComp, DesignOwner: TComponent): TMotionMatchingAuditReport; static;

    class function BuildMarkdownReport(
      const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleClassUtils, CastleUIControls, CastleColors, CastleScene;

constructor TMotionMatchingAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TMotionMatchingAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TMotionMatchingHelper.FindMainViewport(
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

class procedure TMotionMatchingHelper.ScanMotionMatching(
  const RootComp, DesignOwner: TComponent;
  out OutDbs: TPoseSearchDbArray;
  out OutMatchers: TMotionMatcherArray);

  procedure AddDbUnique(const D: TCastlePoseSearchDatabase);
  var
    K: Integer;
  begin
    if (D = nil) or (csTransient in D.ComponentStyle) then
      Exit;
    for K := 0 to High(OutDbs) do
      if OutDbs[K] = D then
        Exit;
    SetLength(OutDbs, Length(OutDbs) + 1);
    OutDbs[High(OutDbs)] := D;
  end;

  procedure AddMatcherUnique(const M: TCastleMotionMatchingBehavior);
  var
    K: Integer;
  begin
    if (M = nil) or (csTransient in M.ComponentStyle) then
      Exit;
    for K := 0 to High(OutMatchers) do
      if OutMatchers[K] = M then
        Exit;
    SetLength(OutMatchers, Length(OutMatchers) + 1);
    OutMatchers[High(OutMatchers)] := M;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    CC: TCastleComponent;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastlePoseSearchDatabase then
      AddDbUnique(TCastlePoseSearchDatabase(C))
    else if C is TCastleMotionMatchingBehavior then
      AddMatcherUnique(TCastleMotionMatchingBehavior(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        Walk(CC.NonVisualComponents[I]);
    end;
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
  OutDbs := nil;
  OutMatchers := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TMotionMatchingHelper.SpawnMotionMatchingArenaDemo(
  const RootComp, DesignOwner: TComponent;
  out OutHero: TCastleTransform;
  out OutDb: TCastlePoseSearchDatabase;
  out OutMatcher: TCastleMotionMatchingBehavior);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  FloorBox, HeroBox, NoseCone: TCastleBox;
  Idx: Integer;
begin
  OutHero := nil;
  OutDb := nil;
  OutMatcher := nil;

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

  if (OwnerToUse = nil) or (OwnerToUse.FindComponent('MotionMatchArenaFloor') = nil) then
  begin
    FloorBox := TCastleBox.Create(OwnerToUse);
    FloorBox.Name := 'MotionMatchArenaFloor';
    FloorBox.Size := Vector3(40.0, 0.5, 40.0);
    FloorBox.Translation := Vector3(0.0, -0.25, 0.0);
    FloorBox.Color := Vector4(0.20, 0.24, 0.30, 1.0);
    ParentTrans.Add(FloorBox);
  end;

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('MotionMatchHero' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  OutDb := TCastlePoseSearchDatabase.Create(OwnerToUse);
  OutDb.Name := 'PoseSearchLocomotionDb_' + IntToStr(Idx);
  OutDb.ApplyPreset(psdpLocomotionOmni8Way);
  if RootComp is TCastleComponent then
    TCastleComponent(RootComp).AddNonVisualComponent(OutDb);

  HeroBox := TCastleBox.Create(OwnerToUse);
  HeroBox.Name := 'MotionMatchHero' + IntToStr(Idx);
  HeroBox.Size := Vector3(0.70, 1.80, 0.50);
  HeroBox.Translation := Vector3(0.0, 0.90, 0.0);
  HeroBox.Color := Vector4(0.22, 0.76, 0.94, 1.0);
  ParentTrans.Add(HeroBox);

  { Transient forward-direction visor (-Z) so artist sees yaw turnaround clearly }
  NoseCone := TCastleBox.Create(HeroBox);
  NoseCone.SetTransient;
  NoseCone.Size := Vector3(0.42, 0.22, 0.38);
  NoseCone.Translation := Vector3(0.0, 0.55, -0.32);
  NoseCone.Color := Vector4(0.98, 0.78, 0.22, 1.0);
  HeroBox.Add(NoseCone);

  OutMatcher := TCastleMotionMatchingBehavior.Create(OwnerToUse);
  OutMatcher.Name := 'HeroMotionMatcher_' + IntToStr(Idx);
  OutMatcher.Database := OutDb;
  OutMatcher.ForceImmediatePoseSearch;
  HeroBox.AddBehavior(OutMatcher);

  OutHero := HeroBox;
end;

class procedure TMotionMatchingHelper.StepAllMotionMatchers(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Dbs: TPoseSearchDbArray;
  Matchers: TMotionMatcherArray;
  I: Integer;
begin
  ScanMotionMatching(RootComp, DesignOwner, Dbs, Matchers);
  for I := 0 to High(Matchers) do
    Matchers[I].StepMotionMatching(Dt);
end;

class function TMotionMatchingHelper.AuditMotionMatchers(
  const RootComp, DesignOwner: TComponent): TMotionMatchingAuditReport;
var
  Dbs: TPoseSearchDbArray;
  Matchers: TMotionMatcherArray;
  I: Integer;
begin
  Result := TMotionMatchingAuditReport.Create;
  ScanMotionMatching(RootComp, DesignOwner, Dbs, Matchers);
  Result.DatabaseCount := Length(Dbs);
  Result.MatcherCount := Length(Matchers);

  for I := 0 to High(Dbs) do
  begin
    Inc(Result.TotalIndexedPoses, Dbs[I].EntryCount);
    if Dbs[I].EntryCount = 0 then
      Result.Warnings.Add(Format('PoseSearchDatabase "%s" contains 0 indexed poses.',
        [Dbs[I].Name]));
  end;

  for I := 0 to High(Matchers) do
    if Matchers[I].Database = nil then
    begin
      Inc(Result.UnboundMatcherCount);
      Result.Warnings.Add(Format(
        'MotionMatchingBehavior "%s" has Database=nil; assign a TCastlePoseSearchDatabase.',
        [Matchers[I].Name]));
    end;
end;

class function TMotionMatchingHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Dbs: TPoseSearchDbArray;
  Matchers: TMotionMatcherArray;
  Audit: TMotionMatchingAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanMotionMatching(RootComp, DesignOwner, Dbs, Matchers);
  Audit := AuditMotionMatchers(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — Motion Matching & Pose Search Telemetry Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Pose Search Databases**: `%d` (`%d` total indexed poses)',
      [Audit.DatabaseCount, Audit.TotalIndexedPoses]));
    SB.AppendLine(Format('- **Motion-Matched Characters**: `%d`', [Audit.MatcherCount]));
    SB.AppendLine;

    if Length(Matchers) > 0 then
    begin
      SB.AppendLine('## Active Motion-Matched Rigs');
      SB.AppendLine('| Behavior | Active Clip | Tag | Cost | Stride Warp | Inertial Blend | Switches |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Matchers) do
        SB.AppendLine(Format('| `%s` | `%s` (`%.2fs`) | `%s` | `%.3f` | `%.2fx` | `%.0f%%` | `%d` |',
          [Matchers[I].Name, Matchers[I].CurrentClipName, Matchers[I].CurrentClipTimeSec,
           Matchers[I].CurrentLocomotionTag, Matchers[I].LastSearchCost.TotalCost,
           Matchers[I].ActiveStrideWarpScale, Matchers[I].InertialBlendAlpha * 100.0,
           Matchers[I].PoseSwitchCount]));
      SB.AppendLine;
    end;

    SB.AppendLine('## QA Diagnostics');
    if Audit.Warnings.Count = 0 then
      SB.AppendLine('- **0 warnings** — all Motion Matching rigs are bound to populated Pose Search databases.')
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
