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

{ Hierarchical StateTree AI decision tree with live spatial evaluators,
  top-down selector EnterConditions, root-to-leaf ancestor preemption,
  timed task transitions, validation, and nested Mermaid export
  (Phase 337 — Unreal Engine 6.0+ StateTree parity). }
unit CastleStateTree;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleClassUtils, CastleUtils,
  CastleTransform;

type
  { Built-in hierarchical StateTree presets. }
  TStateTreePreset = (
    stpTacticalGuardSquad,
    stpBossPhaseController,
    stpCompanionUtilityMedic
  );

  { Comparison operators for StateTree EnterConditions and Transitions. }
  TStateTreeCompareOp = (
    stcoLess,
    stcoLessEqual,
    stcoGreater,
    stcoGreaterEqual,
    stcoEqual,
    stcoNotEqual
  );

  { Trigger event for a StateTree transition. }
  TStateTreeTransitionTrigger = (
    stttOnTickCondition,
    stttOnStateCompleted
  );

  { Single scalar parameter condition evaluated against the tree blackboard. }
  TStateTreeCondition = record
    ParamName: String;
    Op: TStateTreeCompareOp;
    Threshold: Single;
  end;

  { Transition rule attached to any parent or leaf StateTree node. }
  TStateTreeTransition = record
    Trigger: TStateTreeTransitionTrigger;
    HasCondition: Boolean;
    Condition: TStateTreeCondition;
    TargetStateName: String;
  end;

  { Single node in the hierarchical StateTree (ParentIndex = -1 for Root). }
  TStateTreeNode = record
    Name: String;
    ParentIndex: Integer;
    TaskAction: String;
    TaskDurationSec: Single;
    EnterConditions: array of TStateTreeCondition;
    Transitions: array of TStateTreeTransition;
  end;

  { Key/value blackboard parameter entry. }
  TStateTreeParam = record
    Name: String;
    Value: Single;
  end;

  { Hierarchical StateTree AI behavior executing global spatial evaluators,
    top-down selector drilldown, root-to-leaf ancestor interrupt preemption,
    and timed task completion. }
  TCastleStateTreeBehavior = class(TCastleBehavior)
  private
    FPreset: TStateTreePreset;
    FTargetTransformName: String;
    FAutoStepInUpdate: Boolean;
    FNodes: array of TStateTreeNode;
    FParams: array of TStateTreeParam;
    FActiveLeafIndex: Integer;
    FStateElapsedSec: Single;
    FTransitionCount: Integer;

    procedure SetPreset(const AValue: TStateTreePreset);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);

    procedure RunEvaluators;
    function ConditionsHold(const AConds: array of TStateTreeCondition): Boolean;
    function DrillDownSelectorFrom(const ANodeIdx: Integer): Integer;
    procedure EnterTargetStateByIndex(const ATargetIdx: Integer);
    function BuildLineageIndices(const ALeafIdx: Integer): TIntegerList;
    function GetActiveLeafStateName: String;
    function GetActiveStatePath: String;
    function GetActiveTaskAction: String;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ApplyPreset(const APreset: TStateTreePreset);
    procedure ClearTree;

    function AddStateNode(const AName: String; const AParentIndex: Integer;
      const ATaskAction: String = ''; const ATaskDurationSec: Single = 0.0): Integer;
    procedure AddEnterCondition(const ANodeIndex: Integer;
      const AParamName: String; const AOp: TStateTreeCompareOp; const AThreshold: Single);
    procedure AddTransition(const ANodeIndex: Integer;
      const ATrigger: TStateTreeTransitionTrigger; const AHasCondition: Boolean;
      const AParamName: String; const AOp: TStateTreeCompareOp;
      const AThreshold: Single; const ATargetStateName: String);

    procedure SetParam(const AName: String; const AValue: Single);
    function GetParam(const AName: String; const ADefault: Single = 0.0): Single;
    function FindNodeIndex(const AStateName: String): Integer;
    function NodeCount: Integer;
    function GetNode(const AIndex: Integer): TStateTreeNode;
    function IsNodeInActivePath(const AIndex: Integer): Boolean;

    { Re-run selector from Root (Node 0) to pick initial best leaf. }
    procedure RestartFromRoot;

    { Advance evaluators, check root-to-leaf preemption transitions, and tick
      active leaf task duration. }
    procedure StepTree(const Dt: Single);

    function ValidateTree(const AWarnings: TStrings): Boolean;
    function ExportMermaidHierarchyDiagram: String;
    function StateTreeSummaryBadge: String;

    property ActiveLeafIndex: Integer read FActiveLeafIndex;
    property ActiveLeafStateName: String read GetActiveLeafStateName;
    property ActiveStatePath: String read GetActiveStatePath;
    property ActiveTaskAction: String read GetActiveTaskAction;
    property StateElapsedSec: Single read FStateElapsedSec;
    property TransitionCount: Integer read FTransitionCount;
  published
    property Preset: TStateTreePreset read FPreset write SetPreset default stpTacticalGuardSquad;
    property TargetTransformName: String read FTargetTransformName write FTargetTransformName;
    property AutoStepInUpdate: Boolean read FAutoStepInUpdate write FAutoStepInUpdate default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

function EvaluateStateTreeComparison(const LHS: Single;
  const AOp: TStateTreeCompareOp; const RHS: Single): Boolean;
function StateTreePresetToDisplayName(const APreset: TStateTreePreset): String;

implementation

uses
  fpjson, jsonparser,
  CastleComponentSerialize;

function EvaluateStateTreeComparison(const LHS: Single;
  const AOp: TStateTreeCompareOp; const RHS: Single): Boolean;
begin
  case AOp of
    stcoLess:         Result := LHS < RHS;
    stcoLessEqual:    Result := LHS <= RHS;
    stcoGreater:      Result := LHS > RHS;
    stcoGreaterEqual: Result := LHS >= RHS;
    stcoEqual:        Result := SameValue(LHS, RHS, 0.0005);
    stcoNotEqual:     Result := not SameValue(LHS, RHS, 0.0005);
  end;
end;

function StateTreePresetToDisplayName(const APreset: TStateTreePreset): String;
begin
  case APreset of
    stpTacticalGuardSquad:    Result := 'Tactical Guard Squad';
    stpBossPhaseController:   Result := 'Multi-Phase Raid Boss';
    stpCompanionUtilityMedic: Result := 'Companion Field Medic';
  end;
end;

{ TCastleStateTreeBehavior --------------------------------------------------- }

constructor TCastleStateTreeBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAutoStepInUpdate := True;
  FActiveLeafIndex := -1;
  ApplyPreset(stpTacticalGuardSquad);
end;

destructor TCastleStateTreeBehavior.Destroy;
begin
  ClearTree;
  SetLength(FParams, 0);
  inherited Destroy;
end;

function TCastleStateTreeBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'TargetTransformName', 'AutoStepInUpdate', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleStateTreeBehavior.ClearTree;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    FNodes[I] := Default(TStateTreeNode);
  SetLength(FNodes, 0);
  FActiveLeafIndex := -1;
  FStateElapsedSec := 0.0;
  FTransitionCount := 0;
end;

function TCastleStateTreeBehavior.AddStateNode(const AName: String;
  const AParentIndex: Integer; const ATaskAction: String;
  const ATaskDurationSec: Single): Integer;
var
  N: TStateTreeNode;
begin
  N := Default(TStateTreeNode);
  N.Name := AName;
  N.ParentIndex := AParentIndex;
  N.TaskAction := ATaskAction;
  N.TaskDurationSec := Max(0.0, ATaskDurationSec);
  Result := Length(FNodes);
  SetLength(FNodes, Result + 1);
  FNodes[Result] := N;
end;

procedure TCastleStateTreeBehavior.AddEnterCondition(const ANodeIndex: Integer;
  const AParamName: String; const AOp: TStateTreeCompareOp;
  const AThreshold: Single);
var
  C: TStateTreeCondition;
  Len: Integer;
begin
  if (ANodeIndex < 0) or (ANodeIndex > High(FNodes)) then
    Exit;
  C := Default(TStateTreeCondition);
  C.ParamName := AParamName;
  C.Op := AOp;
  C.Threshold := AThreshold;
  Len := Length(FNodes[ANodeIndex].EnterConditions);
  SetLength(FNodes[ANodeIndex].EnterConditions, Len + 1);
  FNodes[ANodeIndex].EnterConditions[Len] := C;
end;

procedure TCastleStateTreeBehavior.AddTransition(const ANodeIndex: Integer;
  const ATrigger: TStateTreeTransitionTrigger; const AHasCondition: Boolean;
  const AParamName: String; const AOp: TStateTreeCompareOp;
  const AThreshold: Single; const ATargetStateName: String);
var
  Tr: TStateTreeTransition;
  Len: Integer;
begin
  if (ANodeIndex < 0) or (ANodeIndex > High(FNodes)) then
    Exit;
  Tr := Default(TStateTreeTransition);
  Tr.Trigger := ATrigger;
  Tr.HasCondition := AHasCondition;
  Tr.Condition.ParamName := AParamName;
  Tr.Condition.Op := AOp;
  Tr.Condition.Threshold := AThreshold;
  Tr.TargetStateName := ATargetStateName;
  Len := Length(FNodes[ANodeIndex].Transitions);
  SetLength(FNodes[ANodeIndex].Transitions, Len + 1);
  FNodes[ANodeIndex].Transitions[Len] := Tr;
end;

procedure TCastleStateTreeBehavior.SetParam(const AName: String;
  const AValue: Single);
var
  I: Integer;
begin
  for I := 0 to High(FParams) do
    if SameText(FParams[I].Name, AName) then
    begin
      FParams[I].Value := AValue;
      Exit;
    end;
  I := Length(FParams);
  SetLength(FParams, I + 1);
  FParams[I] := Default(TStateTreeParam);
  FParams[I].Name := AName;
  FParams[I].Value := AValue;
end;

function TCastleStateTreeBehavior.GetParam(const AName: String;
  const ADefault: Single): Single;
var
  I: Integer;
begin
  for I := 0 to High(FParams) do
    if SameText(FParams[I].Name, AName) then
      Exit(FParams[I].Value);
  Result := ADefault;
end;

function TCastleStateTreeBehavior.FindNodeIndex(const AStateName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if SameText(FNodes[I].Name, AStateName) then
      Exit(I);
  Result := -1;
end;

function TCastleStateTreeBehavior.NodeCount: Integer;
begin
  Result := Length(FNodes);
end;

function TCastleStateTreeBehavior.GetNode(const AIndex: Integer): TStateTreeNode;
begin
  if (AIndex >= 0) and (AIndex <= High(FNodes)) then
    Result := FNodes[AIndex]
  else
    Result := Default(TStateTreeNode);
end;

procedure TCastleStateTreeBehavior.ApplyPreset(const APreset: TStateTreePreset);
var
  IdxRoot, IdxFlee, IdxRetreat, IdxCombat, IdxMelee, IdxRanged,
  IdxPatrol, IdxWalk, IdxScan: Integer;
begin
  FPreset := APreset;
  ClearTree;
  SetLength(FParams, 0);

  case APreset of
    stpTacticalGuardSquad:
      begin
        SetParam('HealthRatio', 1.0);
        SetParam('ThreatDistance', 24.0);

        IdxRoot := AddStateNode('Root', -1);

        { Priority 1 branch: FleeSurvival (HealthRatio < 0.25) }
        IdxFlee := AddStateNode('FleeSurvival', IdxRoot);
        AddEnterCondition(IdxFlee, 'HealthRatio', stcoLess, 0.25);
        AddTransition(IdxFlee, stttOnTickCondition, True, 'HealthRatio', stcoGreaterEqual, 0.60, 'Root');
        IdxRetreat := AddStateNode('RetreatCover', IdxFlee, 'SprintToCover', 0.80);
        AddStateNode('UseMedkit', IdxFlee, 'ChannelMedkit', 0.0);
        AddTransition(IdxRetreat, stttOnStateCompleted, False, '', stcoEqual, 0.0, 'UseMedkit');

        { Priority 2 branch: Combat (ThreatDistance <= 14.0) }
        IdxCombat := AddStateNode('Combat', IdxRoot);
        AddEnterCondition(IdxCombat, 'ThreatDistance', stcoLessEqual, 14.0);
        { Parent-level preemption rules on Combat interrupt ANY active Combat leaf! }
        AddTransition(IdxCombat, stttOnTickCondition, True, 'HealthRatio', stcoLess, 0.25, 'FleeSurvival');
        AddTransition(IdxCombat, stttOnTickCondition, True, 'ThreatDistance', stcoGreater, 16.0, 'Patrol');

        IdxMelee := AddStateNode('MeleeEngage', IdxCombat, 'SlashCombo', 0.0);
        AddEnterCondition(IdxMelee, 'ThreatDistance', stcoLessEqual, 3.5);
        AddTransition(IdxMelee, stttOnTickCondition, True, 'ThreatDistance', stcoGreater, 4.2, 'RangedSuppress');

        IdxRanged := AddStateNode('RangedSuppress', IdxCombat, 'BurstFireRifle', 0.0);
        AddTransition(IdxRanged, stttOnTickCondition, True, 'ThreatDistance', stcoLessEqual, 3.5, 'MeleeEngage');

        { Priority 3 fallback branch: Patrol }
        IdxPatrol := AddStateNode('Patrol', IdxRoot);
        AddTransition(IdxPatrol, stttOnTickCondition, True, 'HealthRatio', stcoLess, 0.25, 'FleeSurvival');
        AddTransition(IdxPatrol, stttOnTickCondition, True, 'ThreatDistance', stcoLessEqual, 14.0, 'Combat');

        IdxWalk := AddStateNode('WaypointWalk', IdxPatrol, 'FollowPatrolRoute', 1.0);
        IdxScan := AddStateNode('LookoutScan', IdxPatrol, 'SweepFlashlight360', 0.8);
        AddTransition(IdxWalk, stttOnStateCompleted, False, '', stcoEqual, 0.0, 'LookoutScan');
        AddTransition(IdxScan, stttOnStateCompleted, False, '', stcoEqual, 0.0, 'WaypointWalk');
      end;

    stpBossPhaseController:
      begin
        SetParam('HealthRatio', 1.0);
        SetParam('ThreatDistance', 8.0);
        IdxRoot := AddStateNode('Root', -1);

        IdxFlee := AddStateNode('EnragePhase3', IdxRoot);
        AddEnterCondition(IdxFlee, 'HealthRatio', stcoLess, 0.30);
        AddStateNode('MeteorCataclysm', IdxFlee, 'CastMeteorStorm', 0.0);

        IdxCombat := AddStateNode('ArmoredPhase1', IdxRoot);
        AddTransition(IdxCombat, stttOnTickCondition, True, 'HealthRatio', stcoLess, 0.30, 'EnragePhase3');
        AddStateNode('GreatswordCleave', IdxCombat, 'HeavyCleaveArc', 0.0);
      end;

    stpCompanionUtilityMedic:
      begin
        SetParam('AllyHealthRatio', 1.0);
        SetParam('ThreatDistance', 12.0);
        IdxRoot := AddStateNode('Root', -1);

        IdxFlee := AddStateNode('EmergencyTriage', IdxRoot);
        AddEnterCondition(IdxFlee, 'AllyHealthRatio', stcoLess, 0.45);
        AddTransition(IdxFlee, stttOnTickCondition, True, 'AllyHealthRatio', stcoGreaterEqual, 0.85, 'SupportFollow');
        AddStateNode('CastHealingWave', IdxFlee, 'HealLeaderBurst', 0.0);

        IdxPatrol := AddStateNode('SupportFollow', IdxRoot);
        AddTransition(IdxPatrol, stttOnTickCondition, True, 'AllyHealthRatio', stcoLess, 0.45, 'EmergencyTriage');
        AddStateNode('EscortFormation', IdxPatrol, 'StayFlankOffset', 0.0);
      end;
  end;

  RestartFromRoot;
end;

procedure TCastleStateTreeBehavior.SetPreset(const AValue: TStateTreePreset);
begin
  if FPreset = AValue then
    Exit;
  ApplyPreset(AValue);
end;

function TCastleStateTreeBehavior.ConditionsHold(
  const AConds: array of TStateTreeCondition): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to High(AConds) do
    if not EvaluateStateTreeComparison(
         GetParam(AConds[I].ParamName, 0.0),
         AConds[I].Op,
         AConds[I].Threshold) then
      Exit(False);
end;

function TCastleStateTreeBehavior.DrillDownSelectorFrom(
  const ANodeIdx: Integer): Integer;
var
  I: Integer;
  HasAnyChild: Boolean;
begin
  Result := ANodeIdx;
  if (ANodeIdx < 0) or (ANodeIdx > High(FNodes)) then
    Exit;

  HasAnyChild := False;
  for I := 0 to High(FNodes) do
    if FNodes[I].ParentIndex = ANodeIdx then
    begin
      HasAnyChild := True;
      if ConditionsHold(FNodes[I].EnterConditions) then
        Exit(DrillDownSelectorFrom(I));
    end;

  { Fallback to last child if none matched explicit EnterConditions }
  if HasAnyChild then
    for I := High(FNodes) downto 0 do
      if FNodes[I].ParentIndex = ANodeIdx then
        Exit(DrillDownSelectorFrom(I));
end;

procedure TCastleStateTreeBehavior.EnterTargetStateByIndex(
  const ATargetIdx: Integer);
var
  ResolvedLeaf: Integer;
begin
  if (ATargetIdx < 0) or (ATargetIdx > High(FNodes)) then
    Exit;
  ResolvedLeaf := DrillDownSelectorFrom(ATargetIdx);
  if ResolvedLeaf <> FActiveLeafIndex then
  begin
    FActiveLeafIndex := ResolvedLeaf;
    FStateElapsedSec := 0.0;
    Inc(FTransitionCount);
  end else
    FStateElapsedSec := 0.0;
end;

procedure TCastleStateTreeBehavior.RestartFromRoot;
begin
  RunEvaluators;
  if Length(FNodes) = 0 then
  begin
    FActiveLeafIndex := -1;
    Exit;
  end;
  FActiveLeafIndex := DrillDownSelectorFrom(0);
  FStateElapsedSec := 0.0;
end;

procedure TCastleStateTreeBehavior.RunEvaluators;
var
  SearchOwner: TComponent;
  TargetComp: TComponent;
  TargetT: TCastleTransform;
  PosA, PosB: TVector3;
begin
  if (Parent = nil) or (FTargetTransformName = '') then
    Exit;
  SearchOwner := Owner;
  if SearchOwner = nil then
    SearchOwner := Parent.Owner;
  if SearchOwner = nil then
    Exit;
  TargetComp := SearchOwner.FindComponent(FTargetTransformName);
  if TargetComp is TCastleTransform then
  begin
    TargetT := TCastleTransform(TargetComp);
    if Parent.HasParent then
      PosA := Parent.WorldTranslation
    else
      PosA := Parent.Translation;
    if TargetT.HasParent then
      PosB := TargetT.WorldTranslation
    else
      PosB := TargetT.Translation;
    SetParam('ThreatDistance', PointsDistance(PosA, PosB));
  end;
end;

function TCastleStateTreeBehavior.BuildLineageIndices(
  const ALeafIdx: Integer): TIntegerList;
var
  Cur, GuardSteps: Integer;
  Rev: TIntegerList;
  I: Integer;
begin
  Result := TIntegerList.Create;
  if (ALeafIdx < 0) or (ALeafIdx > High(FNodes)) then
    Exit;
  Rev := TIntegerList.Create;
  try
    Cur := ALeafIdx;
    GuardSteps := 0;
    while (Cur >= 0) and (Cur <= High(FNodes)) and (GuardSteps <= Length(FNodes)) do
    begin
      Rev.Add(Cur);
      Cur := FNodes[Cur].ParentIndex;
      Inc(GuardSteps);
    end;
    for I := Rev.Count - 1 downto 0 do
      Result.Add(Rev[I]);
  finally
    FreeAndNil(Rev);
  end;
end;

function TCastleStateTreeBehavior.IsNodeInActivePath(
  const AIndex: Integer): Boolean;
var
  Lineage: TIntegerList;
begin
  Lineage := BuildLineageIndices(FActiveLeafIndex);
  try
    Result := Lineage.IndexOf(AIndex) >= 0;
  finally
    FreeAndNil(Lineage);
  end;
end;

procedure TCastleStateTreeBehavior.StepTree(const Dt: Single);
var
  Lineage: TIntegerList;
  L, NodeIdx, TIdx, DestIdx: Integer;
  Tr: TStateTreeTransition;
  CompletedNow: Boolean;
begin
  RunEvaluators;
  if (FActiveLeafIndex < 0) or (FActiveLeafIndex > High(FNodes)) then
  begin
    RestartFromRoot;
    Exit;
  end;

  FStateElapsedSec := FStateElapsedSec + Max(0.0, Dt);
  CompletedNow := (FNodes[FActiveLeafIndex].TaskDurationSec > 0.0) and
                  (FStateElapsedSec >= FNodes[FActiveLeafIndex].TaskDurationSec);

  { Evaluate transitions from Root -> Parent -> Leaf so ancestor states preempt leaves! }
  Lineage := BuildLineageIndices(FActiveLeafIndex);
  try
    for L := 0 to Lineage.Count - 1 do
    begin
      NodeIdx := Lineage[L];
      for TIdx := 0 to High(FNodes[NodeIdx].Transitions) do
      begin
        Tr := FNodes[NodeIdx].Transitions[TIdx];
        if (Tr.Trigger = stttOnStateCompleted) and
           ((NodeIdx <> FActiveLeafIndex) or (not CompletedNow)) then
          Continue;
        if Tr.HasCondition and
           (not EvaluateStateTreeComparison(
              GetParam(Tr.Condition.ParamName, 0.0),
              Tr.Condition.Op,
              Tr.Condition.Threshold)) then
          Continue;
        DestIdx := FindNodeIndex(Tr.TargetStateName);
        if DestIdx >= 0 then
        begin
          EnterTargetStateByIndex(DestIdx);
          Exit;
        end;
      end;
    end;
  finally
    FreeAndNil(Lineage);
  end;
end;

procedure TCastleStateTreeBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if FAutoStepInUpdate then
    StepTree(Min(SecondsPassed, 0.1));
end;

function TCastleStateTreeBehavior.GetActiveLeafStateName: String;
begin
  if (FActiveLeafIndex >= 0) and (FActiveLeafIndex <= High(FNodes)) then
    Result := FNodes[FActiveLeafIndex].Name
  else
    Result := 'None';
end;

function TCastleStateTreeBehavior.GetActiveStatePath: String;
var
  Lineage: TIntegerList;
  I: Integer;
begin
  Lineage := BuildLineageIndices(FActiveLeafIndex);
  try
    Result := '';
    for I := 0 to Lineage.Count - 1 do
    begin
      if Result <> '' then
        Result := Result + '/';
      Result := Result + FNodes[Lineage[I]].Name;
    end;
  finally
    FreeAndNil(Lineage);
  end;
end;

function TCastleStateTreeBehavior.GetActiveTaskAction: String;
begin
  if (FActiveLeafIndex >= 0) and (FActiveLeafIndex <= High(FNodes)) then
    Result := FNodes[FActiveLeafIndex].TaskAction
  else
    Result := '';
end;

function TCastleStateTreeBehavior.ValidateTree(
  const AWarnings: TStrings): Boolean;
var
  I, T: Integer;
begin
  Result := True;
  if Length(FNodes) = 0 then
  begin
    Result := False;
    if AWarnings <> nil then
      AWarnings.Add('StateTree has 0 nodes.');
    Exit;
  end;

  for I := 0 to High(FNodes) do
  begin
    if (I > 0) and ((FNodes[I].ParentIndex < 0) or (FNodes[I].ParentIndex >= Length(FNodes))) then
    begin
      Result := False;
      if AWarnings <> nil then
        AWarnings.Add(Format('State "%s" has invalid ParentIndex %d.', [
          FNodes[I].Name, FNodes[I].ParentIndex]));
    end;
    for T := 0 to High(FNodes[I].Transitions) do
      if FindNodeIndex(FNodes[I].Transitions[T].TargetStateName) < 0 then
      begin
        Result := False;
        if AWarnings <> nil then
          AWarnings.Add(Format('State "%s" has transition to missing target "%s".', [
            FNodes[I].Name, FNodes[I].Transitions[T].TargetStateName]));
      end;
  end;
end;

function TCastleStateTreeBehavior.ExportMermaidHierarchyDiagram: String;
var
  SB: TStringBuilder;

  procedure EmitSubtree(const AParentIdx: Integer; const AIndent: String);
  var
    I, C, T: Integer;
    HasChildren: Boolean;
  begin
    for I := 0 to High(FNodes) do
      if FNodes[I].ParentIndex = AParentIdx then
      begin
        HasChildren := False;
        for C := 0 to High(FNodes) do
          if FNodes[C].ParentIndex = I then
          begin
            HasChildren := True;
            Break;
          end;
        if HasChildren then
        begin
          SB.AppendLine(Format('%sstate %s {', [AIndent, FNodes[I].Name]));
          EmitSubtree(I, AIndent + '  ');
          SB.AppendLine(Format('%s}', [AIndent]));
        end else
          SB.AppendLine(Format('%s%s : %s', [AIndent, FNodes[I].Name, FNodes[I].TaskAction]));

        for T := 0 to High(FNodes[I].Transitions) do
          SB.AppendLine(Format('%s%s --> %s', [
            AIndent, FNodes[I].Name, FNodes[I].Transitions[T].TargetStateName]));
      end;
  end;

begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('stateDiagram-v2');
    if Length(FNodes) > 0 then
    begin
      SB.AppendLine('  [*] --> ' + FNodes[0].Name);
      EmitSubtree(0, '  ');
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

function TCastleStateTreeBehavior.StateTreeSummaryBadge: String;
begin
  Result := Format('[StateTree:%s Act=%s #%d]', [
    GetActiveStatePath, GetActiveTaskAction, FTransitionCount
  ]);
end;

function TCastleStateTreeBehavior.GetConfigJson: String;
var
  RootObj, PObj: TJSONObject;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    PObj := TJSONObject.Create;
    for I := 0 to High(FParams) do
      PObj.Add(FParams[I].Name, FParams[I].Value);
    RootObj.Add('params', PObj);
    RootObj.Add('activeState', GetActiveLeafStateName);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleStateTreeBehavior.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, PObj: TJSONObject;
  I, SavedIdx, PresetOrd: Integer;
  SavedName: String;
begin
  if Trim(AValue) = '' then
    Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Data := nil;
    end;
    if not (Data is TJSONObject) then
      Exit;
    RootObj := TJSONObject(Data);
    PresetOrd := RootObj.Get('preset', Ord(FPreset));
    if (PresetOrd >= Ord(Low(TStateTreePreset))) and
       (PresetOrd <= Ord(High(TStateTreePreset))) and
       (TStateTreePreset(PresetOrd) <> FPreset) then
      ApplyPreset(TStateTreePreset(PresetOrd));

    PObj := RootObj.Find('params', jtObject) as TJSONObject;
    if PObj <> nil then
      for I := 0 to PObj.Count - 1 do
        SetParam(PObj.Names[I], PObj.Items[I].AsFloat);
    SavedName := RootObj.Get('activeState', '');
    SavedIdx := FindNodeIndex(SavedName);
    if SavedIdx >= 0 then
      FActiveLeafIndex := SavedIdx
    else
      RestartFromRoot;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleStateTreeBehavior,
    ['AI & Gameplay', 'StateTree Hierarchical AI (TCastleStateTreeBehavior)']);

end.
