// -*- compile-command: "./test_single_testcase.sh TTestToolDesignSandboxDiff" -*-
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

{ Automated tests for ToolDesignSandboxDiff (Phase 279: Non-Destructive Design
  Sandboxes & Visual Scene/UI Hierarchy + RTTI Property Diff & Selective Merge). }
unit TestToolDesignSandboxDiff;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolDesignSandboxDiff = class(TCastleTestCase)
  published
    procedure TestSandboxLifecyclePersistenceAndInstantiation;
    procedure TestVisualDiffAddedRemovedAndModified;
    procedure TestSelectiveRevertComponentsAndIndividualProperties;
  end;

implementation

uses
  CastleVectors, CastleUIControls, CastleControls, CastleViewport,
  CastleTransform, CastleScene, CastleComponentSerialize,
  ToolDesignSandboxDiff;

procedure BuildSampleDesign(const Owner: TComponent;
  out RootUI: TCastleUserInterface;
  out HeaderLabel: TCastleLabel;
  out Viewport: TCastleViewport;
  out CrateA, CrateB: TCastleBox);
begin
  RootUI := TCastleUserInterface.Create(Owner);
  RootUI.Name := 'GroupRoot';
  RootUI.FullSize := true;

  HeaderLabel := TCastleLabel.Create(Owner);
  HeaderLabel.Name := 'LabelHeader';
  HeaderLabel.Caption := 'Wave 1';
  RootUI.InsertFront(HeaderLabel);

  Viewport := TCastleViewport.Create(Owner);
  Viewport.Name := 'ViewportMain';
  Viewport.FullSize := true;
  RootUI.InsertFront(Viewport);

  CrateA := TCastleBox.Create(Owner);
  CrateA.Name := 'CrateA';
  CrateA.Translation := Vector3(1.0, 2.0, 3.0);
  CrateA.Size := Vector3(2.0, 2.0, 2.0);
  Viewport.Items.Add(CrateA);

  CrateB := TCastleBox.Create(Owner);
  CrateB.Name := 'CrateB';
  CrateB.Translation := Vector3(10.0, 0.0, -4.0);
  CrateB.Size := Vector3(3.0, 1.0, 3.0);
  Viewport.Items.Add(CrateB);
end;

procedure TTestToolDesignSandboxDiff.TestSandboxLifecyclePersistenceAndInstantiation;
var
  Owner1, Owner2: TComponent;
  RootUI, RestoredRoot: TCastleUserInterface;
  HeaderLabel, RestoredLabel: TCastleLabel;
  Viewport: TCastleViewport;
  CrateA, CrateB, RestoredCrateA: TCastleBox;
  Mgr1, Mgr2: TDesignSandboxManager;
  Entry: TDesignSandboxEntry;
  Filtered: TList;
  SavedJson: String;
begin
  Owner1 := TComponent.Create(nil);
  Owner2 := TComponent.Create(nil);
  Mgr1 := TDesignSandboxManager.Create;
  Mgr2 := TDesignSandboxManager.Create;
  Filtered := TList.Create;
  try
    BuildSampleDesign(Owner1, RootUI, HeaderLabel, Viewport, CrateA, CrateB);

    Entry := Mgr1.CreateOrUpdateSandbox(
      'Baseline Layout', 'Initial two-crate layout',
      'castle-data:/gameviewmain.castle-user-interface', RootUI);
    AssertEquals('Baseline Layout', Entry.Name);
    AssertEquals('TCastleUserInterface', Entry.RootClassName);
    AssertTrue(Entry.ComponentCount >= 5);

    { Mutate live scene and create second sandbox }
    HeaderLabel.Caption := 'Night Boss Arena';
    CrateA.Translation := Vector3(-6.5, 4.0, 8.25);
    CrateA.Size := Vector3(4.0, 5.0, 6.0);
    Mgr1.CreateOrUpdateSandbox(
      'Experimental Arena', 'Elevated crate + boss banner',
      'castle-data:/gameviewmain.castle-user-interface', RootUI);

    Mgr1.CreateOrUpdateSandbox(
      'Unrelated Menu Variant', 'Other view',
      'castle-data:/gameviewmenu.castle-user-interface', RootUI);
    AssertEquals(3, Mgr1.Count);

    Mgr1.ListSandboxesForDesign('castle-data:/gameviewmain.castle-user-interface', Filtered);
    AssertEquals(2, Filtered.Count);

    AssertTrue(Mgr1.RenameSandbox('Experimental Arena', 'Boss Arena Pass 2',
      'castle-data:/gameviewmain.castle-user-interface'));
    AssertTrue(Mgr1.FindSandbox('Boss Arena Pass 2',
      'castle-data:/gameviewmain.castle-user-interface') <> nil);

    { Round-trip persistence through JSON }
    SavedJson := Mgr1.SaveToJsonString;
    Mgr2.LoadFromJsonString(SavedJson);
    AssertEquals(3, Mgr2.Count);

    Entry := Mgr2.FindSandbox('Boss Arena Pass 2',
      'castle-data:/gameviewmain.castle-user-interface');
    AssertTrue(Entry <> nil);

    { Instantiate Boss Arena Pass 2 into a clean owner }
    RestoredRoot := Mgr2.InstantiateSandbox(Entry, Owner2) as TCastleUserInterface;
    AssertTrue(RestoredRoot <> nil);
    RestoredLabel := Owner2.FindComponent('LabelHeader') as TCastleLabel;
    RestoredCrateA := Owner2.FindComponent('CrateA') as TCastleBox;
    AssertTrue(RestoredLabel <> nil);
    AssertTrue(RestoredCrateA <> nil);
    AssertEquals('Night Boss Arena', RestoredLabel.Caption);
    AssertVectorEquals(Vector3(-6.5, 4.0, 8.25), RestoredCrateA.Translation, 0.001);
    AssertVectorEquals(Vector3(4.0, 5.0, 6.0), RestoredCrateA.Size, 0.001);

    AssertTrue(Mgr2.DeleteSandbox('Unrelated Menu Variant',
      'castle-data:/gameviewmenu.castle-user-interface'));
    AssertEquals(2, Mgr2.Count);
  finally
    FreeAndNil(Filtered);
    FreeAndNil(Mgr2);
    FreeAndNil(Mgr1);
    FreeAndNil(Owner2);
    FreeAndNil(Owner1);
  end;
end;

procedure TTestToolDesignSandboxDiff.TestVisualDiffAddedRemovedAndModified;
var
  BaseOwner, TargetOwner: TComponent;
  BaseRoot, TargetRoot: TCastleUserInterface;
  BaseLabel, TargetLabel: TCastleLabel;
  BaseVP, TargetVP: TCastleViewport;
  BaseCrateA, BaseCrateB, TargetCrateA, TargetCrateB: TCastleBox;
  BonusSphere: TCastleSphere;
  Report, IdenticalReport: TDesignDiffReport;
  CompDiff: TDesignComponentDiff;
  SummaryText: String;
begin
  BaseOwner := TComponent.Create(nil);
  TargetOwner := TComponent.Create(nil);
  Report := nil;
  IdenticalReport := nil;
  try
    BuildSampleDesign(BaseOwner, BaseRoot, BaseLabel, BaseVP, BaseCrateA, BaseCrateB);
    BuildSampleDesign(TargetOwner, TargetRoot, TargetLabel, TargetVP, TargetCrateA, TargetCrateB);

    { Identical designs have 0 differences }
    IdenticalReport := TDesignDiffEngine.CompareComponents(BaseRoot, TargetRoot);
    AssertFalse(IdenticalReport.HasDifferences);
    AssertEquals(0, IdenticalReport.AddedCount);
    AssertEquals(0, IdenticalReport.RemovedCount);
    AssertEquals(0, IdenticalReport.ModifiedCount);

    { Now mutate Target:
      1. Remove CrateB
      2. Add SphereBonus
      3. Modify CrateA (Translation + Size) and LabelHeader (Caption + FontSize) }
    FreeAndNil(TargetCrateB);

    BonusSphere := TCastleSphere.Create(TargetOwner);
    BonusSphere.Name := 'SphereBonus';
    BonusSphere.Radius := 2.5;
    BonusSphere.Translation := Vector3(0.0, 6.0, 0.0);
    TargetVP.Items.Add(BonusSphere);

    TargetCrateA.Translation := Vector3(8.0, 9.0, 10.0);
    TargetCrateA.Size := Vector3(5.0, 6.0, 7.0);
    TargetLabel.Caption := 'Boss Wave!';
    TargetLabel.FontSize := 42;

    Report := TDesignDiffEngine.CompareComponents(
      BaseRoot, TargetRoot, 'Saved Disk', 'Live Scene');
    AssertTrue(Report.HasDifferences);
    AssertEquals(1, Report.AddedCount);
    AssertEquals(1, Report.RemovedCount);
    AssertEquals(2, Report.ModifiedCount);
    AssertTrue(Report.TotalPropertyChanges >= 4);

    CompDiff := Report.FindComponentDiff('SphereBonus');
    AssertTrue(CompDiff <> nil);
    AssertTrue(CompDiff.DiffKind = ddkAdded);
    AssertEquals('TCastleSphere', CompDiff.TargetClassName);

    CompDiff := Report.FindComponentDiff('CrateB');
    AssertTrue(CompDiff <> nil);
    AssertTrue(CompDiff.DiffKind = ddkRemoved);
    AssertEquals('TCastleBox', CompDiff.BaseClassName);

    CompDiff := Report.FindComponentDiff('CrateA');
    AssertTrue(CompDiff <> nil);
    AssertTrue(CompDiff.DiffKind = ddkModified);
    { TranslationPersistent.X/Y/Z (3) + SizePersistent.X/Y/Z (3) = 6 }
    AssertEquals(6, CompDiff.PropertyDiffs.Count);

    SummaryText := Report.FormatUnifiedSummary;
    AssertTrue(Pos('+ SphereBonus (TCastleSphere)', SummaryText) > 0);
    AssertTrue(Pos('- CrateB (TCastleBox)', SummaryText) > 0);
    AssertTrue(Pos('~ CrateA (TCastleBox)', SummaryText) > 0);
  finally
    FreeAndNil(IdenticalReport);
    FreeAndNil(Report);
    FreeAndNil(TargetOwner);
    FreeAndNil(BaseOwner);
  end;
end;

procedure TTestToolDesignSandboxDiff.TestSelectiveRevertComponentsAndIndividualProperties;
var
  BaseOwner, TargetOwner, MergedOwner: TComponent;
  BaseRoot, TargetRoot, MergedRoot: TCastleUserInterface;
  BaseLabel, TargetLabel, MergedLabel: TCastleLabel;
  BaseVP, TargetVP, MergedVP: TCastleViewport;
  BaseCrateA, BaseCrateB, TargetCrateA, TargetCrateB,
    MergedCrateA, MergedCrateB: TCastleBox;
  BonusSphere: TCastleSphere;
  BaseJson, TargetJson, PartialMergedJson, FullRevertedJson: String;
  RevertComps, RevertProps: TStringList;
  FinalReport: TDesignDiffReport;
begin
  BaseOwner := TComponent.Create(nil);
  TargetOwner := TComponent.Create(nil);
  MergedOwner := TComponent.Create(nil);
  RevertComps := TStringList.Create;
  RevertProps := TStringList.Create;
  FinalReport := nil;
  try
    BuildSampleDesign(BaseOwner, BaseRoot, BaseLabel, BaseVP, BaseCrateA, BaseCrateB);
    BuildSampleDesign(TargetOwner, TargetRoot, TargetLabel, TargetVP, TargetCrateA, TargetCrateB);

    FreeAndNil(TargetCrateB);

    BonusSphere := TCastleSphere.Create(TargetOwner);
    BonusSphere.Name := 'SphereBonus';
    BonusSphere.Radius := 2.5;
    TargetVP.Items.Add(BonusSphere);

    TargetCrateA.Translation := Vector3(8.0, 9.0, 10.0);
    TargetCrateA.Size := Vector3(5.0, 6.0, 7.0);
    TargetLabel.Caption := 'Boss Wave!';
    TargetLabel.FontSize := 42;

    BaseJson := ComponentToString(BaseRoot);
    TargetJson := ComponentToString(TargetRoot);

    { Step 1: Selectively revert:
      - Added 'SphereBonus' -> removed
      - Removed 'CrateB' -> restored
      - Properties 'CrateA::TranslationPersistent.X/Y/Z' -> reverted to (1,2,3), Size stays (5,6,7)
      - Property 'LabelHeader::FontSize' -> reverted to default (0), Caption stays 'Boss Wave!' }
    RevertComps.Add('SphereBonus');
    RevertComps.Add('CrateB');
    RevertProps.Add('CrateA::TranslationPersistent.X');
    RevertProps.Add('CrateA::TranslationPersistent.Y');
    RevertProps.Add('CrateA::TranslationPersistent.Z');
    RevertProps.Add('LabelHeader::FontSize');

    PartialMergedJson := TDesignDiffEngine.RevertSelectedToBase(
      BaseJson, TargetJson, RevertComps, RevertProps);

    MergedRoot := StringToComponent(PartialMergedJson, MergedOwner) as TCastleUserInterface;
    AssertTrue(MergedRoot <> nil);
    AssertTrue(MergedOwner.FindComponent('SphereBonus') = nil);

    MergedVP := MergedOwner.FindComponent('ViewportMain') as TCastleViewport;
    MergedCrateB := MergedOwner.FindComponent('CrateB') as TCastleBox;
    AssertTrue(MergedCrateB <> nil);
    AssertTrue(MergedCrateB.Parent = MergedVP.Items);
    AssertVectorEquals(Vector3(10.0, 0.0, -4.0), MergedCrateB.Translation, 0.001);

    MergedCrateA := MergedOwner.FindComponent('CrateA') as TCastleBox;
    AssertTrue(MergedCrateA <> nil);
    AssertVectorEquals(Vector3(1.0, 2.0, 3.0), MergedCrateA.Translation, 0.001);
    AssertVectorEquals(Vector3(5.0, 6.0, 7.0), MergedCrateA.Size, 0.001);

    MergedLabel := MergedOwner.FindComponent('LabelHeader') as TCastleLabel;
    AssertTrue(MergedLabel <> nil);
    AssertEquals('Boss Wave!', MergedLabel.Caption);
    AssertSameValue(0.0, MergedLabel.FontSize, 0.001);

    { Step 2: Revert the remaining two modified components completely -> 0 diffs vs BaseJson }
    RevertComps.Clear;
    RevertProps.Clear;
    RevertComps.Add('CrateA');
    RevertComps.Add('LabelHeader');

    FullRevertedJson := TDesignDiffEngine.RevertSelectedToBase(
      BaseJson, PartialMergedJson, RevertComps, RevertProps);

    FinalReport := TDesignDiffEngine.CompareJson(BaseJson, FullRevertedJson);
    AssertFalse(FinalReport.HasDifferences);
    AssertEquals(0, FinalReport.AddedCount);
    AssertEquals(0, FinalReport.RemovedCount);
    AssertEquals(0, FinalReport.ModifiedCount);
  finally
    FreeAndNil(FinalReport);
    FreeAndNil(RevertProps);
    FreeAndNil(RevertComps);
    FreeAndNil(MergedOwner);
    FreeAndNil(TargetOwner);
    FreeAndNil(BaseOwner);
  end;
end;

initialization
  RegisterTest(TTestToolDesignSandboxDiff);
end.
