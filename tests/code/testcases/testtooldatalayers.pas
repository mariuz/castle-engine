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

{ Automated tests for Phase 343 World Partition Runtime Data Layers,
  Parent/Sub-Layer Inheritance & Multi-Scenario Visibility Switching. }
unit TestToolDataLayers;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolDataLayers = class(TCastleTestCase)
  published
    procedure TestParentChildSubLayerInheritanceAndScenarioSwitching;
    procedure TestUnknownLayerWarningMermaidExportAndConfigJsonPresetRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleDataLayers, ToolDataLayers;

procedure TTestToolDataLayers.TestParentChildSubLayerInheritanceAndScenarioSwitching;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Mgr: TCastleDataLayerManager;
  Stall, Catapult, Rubble, Wall: TCastleTransform;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TDataLayersHelper.SpawnFortressScenarioDataLayersDemo(Vp, DesignOwner, Mgr));
    AssertTrue(Mgr <> nil);

    Stall := DesignOwner.FindComponent('MerchantStall_West') as TCastleTransform;
    Catapult := DesignOwner.FindComponent('SiegeTrebuchet_1') as TCastleTransform;
    Rubble := DesignOwner.FindComponent('CollapsedRubble_1') as TCastleTransform;
    Wall := DesignOwner.FindComponent('FortressCurtainWall') as TCastleTransform;
    AssertTrue((Stall <> nil) and (Catapult <> nil) and (Rubble <> nil) and (Wall <> nil));

    { 1. PeacetimeTown: MarketStalls active (2), Siege (4) & Ruins (2) unloaded via parent! }
    AssertEquals(8, Mgr.TaggedActorCount);
    AssertEquals(2, Mgr.ActivatedActorCount);
    AssertEquals(0, Mgr.LoadedHiddenActorCount);
    AssertEquals(6, Mgr.UnloadedActorCount);
    AssertTrue(Stall.Exists);
    AssertFalse(Catapult.Exists);
    AssertFalse(Rubble.Exists);
    AssertTrue(Wall.Exists);
    { Sub-layer SiegeCatapults has Desired=Activated, but parent CitySiege=Unloaded -> Effective=Unloaded }
    AssertTrue(Mgr.GetLayerDesiredState('SiegeCatapults') = dlrsActivated);
    AssertTrue(Mgr.EvaluateEffectiveLayerState('SiegeCatapults') = dlrsUnloaded);

    { 2. Switch to ActiveSiegeBattle: Civic becomes LoadedHidden (2), Siege becomes Activated (4) }
    AssertTrue(TDataLayersHelper.SwitchScenarioAndApply(Vp, dlspActiveSiegeBattle));
    AssertEquals(4, Mgr.ActivatedActorCount);
    AssertEquals(2, Mgr.LoadedHiddenActorCount);
    AssertEquals(2, Mgr.UnloadedActorCount);
    AssertFalse(Stall.Exists);
    AssertTrue(Catapult.Exists);
    AssertFalse(Rubble.Exists);

    { 3. Set parent CitySiege to LoadedHidden -> child SiegeCatapults inherits LoadedHidden }
    AssertTrue(Mgr.SetLayerState('CitySiege', dlrsLoadedHidden));
    Mgr.ApplyDataLayersToWorld(Vp.Items);
    AssertTrue(Mgr.EvaluateEffectiveLayerState('SiegeCatapults') = dlrsLoadedHidden);
    AssertFalse(Catapult.Exists);
    AssertEquals(0, Mgr.ActivatedActorCount);
    AssertEquals(6, Mgr.LoadedHiddenActorCount);

    { 4. PostWarRuins activates RubbleBarricades (2) }
    AssertTrue(TDataLayersHelper.SwitchScenarioAndApply(Vp, dlspPostWarRuins));
    AssertTrue(Rubble.Exists);
    AssertFalse(Stall.Exists);
    AssertFalse(Catapult.Exists);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolDataLayers.TestUnknownLayerWarningMermaidExportAndConfigJsonPresetRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Mgr, RestoredMgr: TCastleDataLayerManager;
  GhostProp: TCastleBox;
  GhostTag: TCastleDataLayerTagBehavior;
  Warnings: TStringList;
  Sum: TDataLayersStudioSummary;
  MermaidStr, JsonStr: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TDataLayersHelper.SpawnFortressScenarioDataLayersDemo(Vp, DesignOwner, Mgr));

    { 1. Attach an undefined layer tag and verify warning diagnostics }
    GhostProp := TCastleBox.Create(DesignOwner);
    GhostProp.Name := 'GhostProp';
    GhostTag := TCastleDataLayerTagBehavior.Create(DesignOwner);
    GhostTag.Name := 'GhostTag';
    GhostTag.LayerName := 'UndefinedSecretDungeon';
    GhostProp.AddBehavior(GhostTag);
    Vp.Items.Add(GhostProp);

    Sum := TDataLayersHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.MissingLayerTagsCount);
    AssertEquals(1, Sum.WarningsCount);
    AssertEquals(1, Warnings.Count);
    AssertFalse(GhostProp.Exists);

    { 2. Mermaid flowchart export }
    MermaidStr := Mgr.ExportMermaidHierarchy;
    AssertTrue(Pos('flowchart TD', MermaidStr) > 0);
    AssertTrue(Pos('CitySiege --> SiegeCatapults', MermaidStr) > 0);

    { 3. JSON roundtrip preserving custom parent state + dlspCustom without alphabetical reset }
    Mgr.ApplyScenarioPreset(dlspActiveSiegeBattle);
    Mgr.SetLayerState('BreachFires', dlrsLoadedHidden);
    JsonStr := ComponentToString(Mgr);

    RestoredMgr := StringToComponent(JsonStr, RestoredOwner) as TCastleDataLayerManager;
    AssertTrue(RestoredMgr <> nil);
    AssertTrue(RestoredMgr.ScenarioPreset = dlspCustom);
    AssertTrue(RestoredMgr.EvaluateEffectiveLayerState('SiegeCatapults') = dlrsActivated);
    AssertTrue(RestoredMgr.EvaluateEffectiveLayerState('BreachFires') = dlrsLoadedHidden);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolDataLayers);

end.
