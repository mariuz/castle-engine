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

{ Stateless editor & headless test helpers for the Smart Objects, RVO Crowd
  Separation & Response-Curve Utility AI Studio (@link(TUtilityAiHelper))
  (Phase 314 — UE 6.0+ SmartObjects & Utility AI Parity). }
unit ToolUtilityAi;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleScene, CastleViewport,
  CastleUIControls, CastleUtilityAi;

type
  { Audit report summarizing all @link(TCastleSmartObject) stations and
    @link(TCastleUtilityAiBehavior) agents in a design. }
  TUtilityAiAuditReport = class
  public
    Stations: array of TCastleSmartObject;
    Agents: array of TCastleUtilityAiBehavior;
    TotalSlots: Integer;
    OccupiedSlots: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless authoring, crowd simulation & Markdown helper for Utility AI. }
  TUtilityAiHelper = class
  public
    class function ScanDesign(const RootComp, DesignOwner: TComponent): TUtilityAiAuditReport; static;
    class function ResolveTransformContainer(const RootComp: TComponent): TCastleTransform; static;

    class function SpawnSmartObjectInDesign(
      const RootComp, DesignOwner: TComponent;
      const APreset: TSmartObjectPreset;
      const APos: TVector3;
      const ABaseName: String = 'SmartStation'): TCastleSmartObject; static;

    class function SpawnUtilityAgentInDesign(
      const RootComp, DesignOwner: TComponent;
      const APreset: TUtilityAgentPreset;
      const APos: TVector3;
      const ABaseName: String = 'UtilityNpc'): TCastleUtilityAiBehavior; static;

    class procedure SpawnVillageSimulationDemo(const RootComp, DesignOwner: TComponent); static;

    class procedure StepAllUtilityAgents(
      const RootComp, DesignOwner: TComponent; const Dt: Single); static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleStringUtils;

function MakeUniqueUtilName(const OwnerComp: TComponent; const Base: String): String;
var
  Idx: Integer;
begin
  if (OwnerComp = nil) or (OwnerComp.FindComponent(Base) = nil) then
    Exit(Base);
  Idx := 1;
  repeat
    Result := Base + IntToStr(Idx);
    Inc(Idx);
  until OwnerComp.FindComponent(Result) = nil;
end;

{ TUtilityAiAuditReport ------------------------------------------------------ }

constructor TUtilityAiAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TUtilityAiAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TUtilityAiHelper ----------------------------------------------------------- }

class function TUtilityAiHelper.ResolveTransformContainer(
  const RootComp: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp).Items);
  if RootComp is TCastleTransform then
    Exit(TCastleTransform(RootComp));
  if RootComp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(RootComp);
    for I := 0 to UI.ControlsCount - 1 do
      if UI.Controls[I] is TCastleViewport then
        Exit(TCastleViewport(UI.Controls[I]).Items);
  end;
  Result := nil;
end;

class function TUtilityAiHelper.ScanDesign(
  const RootComp, DesignOwner: TComponent): TUtilityAiAuditReport;
var
  FoundStations, FoundAgents: TList;

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    UI: TCastleUserInterface;
    T: TCastleTransform;
  begin
    if C = nil then
      Exit;
    if (C is TCastleSmartObject) and (FoundStations.IndexOf(C) < 0) then
      FoundStations.Add(C);
    if (C is TCastleUtilityAiBehavior) and (FoundAgents.IndexOf(C) < 0) then
      FoundAgents.Add(C);

    if C is TCastleViewport then
      Traverse(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Traverse(UI.Controls[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      if not (csTransient in T.ComponentStyle) then
      begin
        for I := 0 to T.BehaviorsCount - 1 do
          Traverse(T.Behaviors[I]);
        for I := 0 to T.Count - 1 do
          Traverse(T[I]);
      end;
    end;
  end;

var
  I: Integer;
  SO: TCastleSmartObject;
begin
  Result := TUtilityAiAuditReport.Create;
  FoundStations := TList.Create;
  FoundAgents := TList.Create;
  try
    Traverse(RootComp);
    if DesignOwner <> nil then
      for I := 0 to DesignOwner.ComponentCount - 1 do
        Traverse(DesignOwner.Components[I]);

    SetLength(Result.Stations, FoundStations.Count);
    for I := 0 to FoundStations.Count - 1 do
    begin
      SO := TCastleSmartObject(FoundStations[I]);
      Result.Stations[I] := SO;
      Inc(Result.TotalSlots, SO.MaxUsers);
      Inc(Result.OccupiedSlots, SO.ActiveUserCount);
    end;

    SetLength(Result.Agents, FoundAgents.Count);
    for I := 0 to FoundAgents.Count - 1 do
      Result.Agents[I] := TCastleUtilityAiBehavior(FoundAgents[I]);

    if (Length(Result.Agents) > 0) and (Length(Result.Stations) = 0) then
      Result.Warnings.Add('Utility AI agents exist in the design without any TCastleSmartObject stations.');
  finally
    FreeAndNil(FoundAgents);
    FreeAndNil(FoundStations);
  end;
end;

class function TUtilityAiHelper.SpawnSmartObjectInDesign(
  const RootComp, DesignOwner: TComponent;
  const APreset: TSmartObjectPreset;
  const APos: TVector3;
  const ABaseName: String): TCastleSmartObject;
var
  OwnerToUse: TComponent;
  Container: TCastleTransform;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleSmartObject.Create(OwnerToUse);
  Result.Name := MakeUniqueUtilName(OwnerToUse, ABaseName);
  Result.Translation := APos;
  Result.ApplyPreset(APreset);

  Container := ResolveTransformContainer(RootComp);
  if Container <> nil then
    Container.Add(Result);
end;

class function TUtilityAiHelper.SpawnUtilityAgentInDesign(
  const RootComp, DesignOwner: TComponent;
  const APreset: TUtilityAgentPreset;
  const APos: TVector3;
  const ABaseName: String): TCastleUtilityAiBehavior;
var
  OwnerToUse: TComponent;
  Container: TCastleTransform;
  AgentCapsule: TCastleCylinder;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  AgentCapsule := TCastleCylinder.Create(OwnerToUse);
  AgentCapsule.Name := MakeUniqueUtilName(OwnerToUse, ABaseName);
  AgentCapsule.Radius := 0.35;
  AgentCapsule.Height := 1.70;
  AgentCapsule.Translation := APos;
  if APreset = uapVillagerArtisan then
    AgentCapsule.Color := Vector4(0.32, 0.68, 0.92, 1.0)
  else
    AgentCapsule.Color := Vector4(0.88, 0.38, 0.34, 1.0);

  Container := ResolveTransformContainer(RootComp);
  if Container <> nil then
    Container.Add(AgentCapsule);

  Result := TCastleUtilityAiBehavior.Create(OwnerToUse);
  Result.Name := MakeUniqueUtilName(OwnerToUse, ABaseName + 'AI');
  Result.ApplyPreset(APreset);
  AgentCapsule.AddBehavior(Result);
end;

class procedure TUtilityAiHelper.SpawnVillageSimulationDemo(
  const RootComp, DesignOwner: TComponent);
var
  A1, A2, A3: TCastleUtilityAiBehavior;
begin
  SpawnSmartObjectInDesign(RootComp, DesignOwner,
    sopCampfireRestBench, Vector3(-5.0, 0.0, -3.0), 'CampfireRest');
  SpawnSmartObjectInDesign(RootComp, DesignOwner,
    sopTavernMealTable, Vector3(5.0, 0.0, -3.0), 'TavernTable');
  SpawnSmartObjectInDesign(RootComp, DesignOwner,
    sopBlacksmithWorkAnvil, Vector3(0.0, 0.0, 5.0), 'BlacksmithAnvil');

  A1 := SpawnUtilityAgentInDesign(RootComp, DesignOwner,
    uapVillagerArtisan, Vector3(-1.2, 0.0, 0.0), 'VillagerRowan');
  A1.SetNeed('Energy', 0.20);

  A2 := SpawnUtilityAgentInDesign(RootComp, DesignOwner,
    uapVillagerArtisan, Vector3(0.0, 0.0, 0.3), 'VillagerMira');
  A2.SetNeed('Hunger', 0.18);

  A3 := SpawnUtilityAgentInDesign(RootComp, DesignOwner,
    uapTownGuard, Vector3(1.2, 0.0, 0.0), 'GuardGarrick');
  A3.SetNeed('Energy', 0.28);
end;

class procedure TUtilityAiHelper.StepAllUtilityAgents(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Report: TUtilityAiAuditReport;
  I: Integer;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    for I := 0 to High(Report.Agents) do
      Report.Agents[I].StepUtilityAi(Dt);
  finally
    FreeAndNil(Report);
  end;
end;

class function TUtilityAiHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Report: TUtilityAiAuditReport;
  SB: TStringBuilder;
  I, J: Integer;
  SO: TCastleSmartObject;
  AI: TCastleUtilityAiBehavior;
  ActorName, StationName: String;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Smart Objects, RVO Crowd Separation & Utility AI Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Smart Stations**: %d (`%d / %d` slots occupied) | **Utility AI Agents**: %d',
      [Length(Report.Stations), Report.OccupiedSlots, Report.TotalSlots, Length(Report.Agents)]));
    SB.AppendLine;

    if Length(Report.Stations) > 0 then
    begin
      SB.AppendLine('## Smart Object Stations');
      SB.AppendLine('| Station | Tag | Slots | Restores Need | Rate (/s) |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Report.Stations) do
      begin
        SO := Report.Stations[I];
        SB.AppendLine(Format('| `%s` | `%s` | %d / %d | `%s` | %.2f |',
          [SO.Name, SO.SmartObjectTag, SO.ActiveUserCount, SO.MaxUsers,
           SO.RestoresNeedName, SO.RestoreRatePerSec]));
      end;
      SB.AppendLine;
    end;

    if Length(Report.Agents) > 0 then
    begin
      SB.AppendLine('## Utility AI Agents');
      SB.AppendLine('| Agent | Action | Claimed Station | Needs |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for I := 0 to High(Report.Agents) do
      begin
        AI := Report.Agents[I];
        if AI.Parent <> nil then
          ActorName := AI.Parent.Name
        else
          ActorName := AI.Name;
        if AI.ClaimedSmartObject <> nil then
          StationName := AI.ClaimedSmartObject.Name
        else
          StationName := 'None';

        SB.Append(Format('| `%s` | `%s` | `%s` | ',
          [ActorName, AI.CurrentActionId, StationName]));
        for J := 0 to AI.Needs.Count - 1 do
          SB.Append(Format('%s=%.2f ', [AI.Needs[J].NeedName, AI.Needs[J].Value]));
        SB.AppendLine('|');
      end;
      SB.AppendLine;
    end;

    if Report.Warnings.Count > 0 then
    begin
      SB.AppendLine('## Warnings');
      for I := 0 to Report.Warnings.Count - 1 do
        SB.AppendLine('- ' + Report.Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Report);
  end;
end;

end.
