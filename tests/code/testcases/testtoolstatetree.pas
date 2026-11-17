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

{ Automated tests for Phase 337 StateTree Hierarchical AI Decision Tree,
  Spatial Evaluators, Ancestor Preemption & Mermaid Export. }
unit TestToolStateTree;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolStateTree = class(TCastleTestCase)
  published
    procedure TestHierarchicalSelectorDrilldownAncestorPreemptionAndTimedTaskCompletion;
    procedure TestPresetsTreeValidationMermaidExportAndCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleStateTree, ToolStateTree;

procedure TTestToolStateTree.TestHierarchicalSelectorDrilldownAncestorPreemptionAndTimedTaskCompletion;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Guard, Intruder: TCastleTransform;
  Tree: TCastleStateTreeBehavior;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TStateTreeHelper.SpawnTacticalGuardStateTreeDemo(
      Vp, DesignOwner, Guard, Intruder, Tree));
    AssertTrue(Tree <> nil);

    { 1. Intruder starts at Z = 22.0m (> 14m): evaluator selects Root/Patrol/WaypointWalk }
    Tree.StepTree(0.05);
    AssertTrue(Tree.GetParam('ThreatDistance', 0.0) > 20.0);
    AssertEquals('Root/Patrol/WaypointWalk', Tree.ActiveStatePath);
    AssertEquals('FollowPatrolRoute', Tree.ActiveTaskAction);

    { 2. Step past WaypointWalk TaskDurationSec (1.0s) -> stttOnStateCompleted -> LookoutScan }
    Tree.StepTree(1.05);
    AssertEquals('Root/Patrol/LookoutScan', Tree.ActiveStatePath);
    AssertEquals('SweepFlashlight360', Tree.ActiveTaskAction);

    { 3. Move Intruder to Z = 9.0m (<= 14m, > 3.5m) -> Patrol transitions to Combat -> RangedSuppress }
    Intruder.Translation := Vector3(0.0, 0.9, 9.0);
    Tree.StepTree(0.05);
    AssertEquals('Root/Combat/RangedSuppress', Tree.ActiveStatePath);
    AssertEquals('BurstFireRifle', Tree.ActiveTaskAction);
    AssertTrue(Tree.IsNodeInActivePath(Tree.FindNodeIndex('Root')));
    AssertTrue(Tree.IsNodeInActivePath(Tree.FindNodeIndex('Combat')));

    { 4. Move Intruder close to Z = 2.0m (<= 3.5m) -> RangedSuppress -> MeleeEngage }
    Intruder.Translation := Vector3(0.0, 0.9, 2.0);
    Tree.StepTree(0.05);
    AssertEquals('Root/Combat/MeleeEngage', Tree.ActiveStatePath);
    AssertEquals('SlashCombo', Tree.ActiveTaskAction);

    { 5. Drop HealthRatio to 0.15 (< 0.25): parent Combat transition preempts leaf MeleeEngage! }
    Tree.SetParam('HealthRatio', 0.15);
    Tree.StepTree(0.05);
    AssertEquals('Root/FleeSurvival/RetreatCover', Tree.ActiveStatePath);
    AssertEquals('SprintToCover', Tree.ActiveTaskAction);

    { 6. Finish RetreatCover (0.80s) -> transitions to UseMedkit }
    Tree.StepTree(0.85);
    AssertEquals('Root/FleeSurvival/UseMedkit', Tree.ActiveStatePath);
    AssertEquals('ChannelMedkit', Tree.ActiveTaskAction);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolStateTree.TestPresetsTreeValidationMermaidExportAndCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Guard, Intruder: TCastleTransform;
  Tree, RestoredTree: TCastleStateTreeBehavior;
  Warnings: TStringList;
  MermaidStr, JsonStr, ReportMd: String;
  Sum: TStateTreeStudioSummary;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TStateTreeHelper.SpawnTacticalGuardStateTreeDemo(
      Vp, DesignOwner, Guard, Intruder, Tree));

    { Boss preset phase preemption }
    Tree.Preset := stpBossPhaseController;
    AssertEquals('Root/ArmoredPhase1/GreatswordCleave', Tree.ActiveStatePath);
    Tree.SetParam('HealthRatio', 0.20);
    Tree.StepTree(0.05);
    AssertEquals('Root/EnragePhase3/MeteorCataclysm', Tree.ActiveStatePath);

    { Companion medic preset }
    Tree.Preset := stpCompanionUtilityMedic;
    AssertEquals('Root/SupportFollow/EscortFormation', Tree.ActiveStatePath);
    Tree.SetParam('AllyHealthRatio', 0.30);
    Tree.StepTree(0.05);
    AssertEquals('Root/EmergencyTriage/CastHealingWave', Tree.ActiveStatePath);

    { Validation + Mermaid }
    AssertTrue(Tree.ValidateTree(Warnings));
    AssertEquals(0, Warnings.Count);
    MermaidStr := Tree.ExportMermaidHierarchyDiagram;
    AssertTrue(Pos('stateDiagram-v2', MermaidStr) > 0);
    AssertTrue(Pos('state EmergencyTriage {', MermaidStr) > 0);

    Sum := TStateTreeHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.TreeCount);
    AssertEquals(0, Sum.ValidationWarningsCount);
    ReportMd := TStateTreeHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('StateTree Hierarchical AI Report', ReportMd) > 0);

    { Detect invalid transition target }
    Tree.AddTransition(0, stttOnTickCondition, False, '', stcoEqual, 0.0, 'NonExistentGhostState');
    AssertFalse(Tree.ValidateTree(Warnings));
    AssertTrue(Warnings.Count >= 1);

    { Restore clean preset & verify JSON roundtrip }
    Tree.ApplyPreset(stpBossPhaseController);
    Tree.SetParam('HealthRatio', 0.22);
    Tree.StepTree(0.05);
    JsonStr := ComponentToString(Tree);
    RestoredTree := StringToComponent(JsonStr, RestoredOwner) as TCastleStateTreeBehavior;
    AssertTrue(RestoredTree <> nil);
    AssertTrue(RestoredTree.Preset = stpBossPhaseController);
    AssertSameValue(0.22, RestoredTree.GetParam('HealthRatio', 1.0), 0.01);
    AssertEquals('MeteorCataclysm', RestoredTree.ActiveLeafStateName);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolStateTree);

end.
