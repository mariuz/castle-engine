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

{ Automated unit tests for Phase 300 DataTables, Hierarchical Gameplay Tags &
  Curve-Driven Balance Sheet Studio (@link(TCastleDataTable),
  @link(TCastleGameplayTagBehavior), and @link(TDataTableStudioHelper)). }
unit TestToolDataTableStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolDataTableStudio = class(TCastleTestCase)
  published
    procedure TestTypedSpreadsheetCsvJsonRoundtripAndHierarchicalTagQueries;
    procedure TestProgressionCurvesRttiRowBindingSchemaAuditAndMarkdown;
  end;

implementation

uses
  CastleComponentSerialize, CastleTransform, CastleLivingBehaviors,
  EditorRegisterAllComponents,
  CastleDataTable, ToolDataTableStudio;

procedure TTestToolDataTableStudio.TestTypedSpreadsheetCsvJsonRoundtripAndHierarchicalTagQueries;
var
  DesignOwner, LoadedOwner: TComponent;
  World, LoadedWorld: TCastleTransform;
  DT, CsvCopy, LoadedDT: TCastleDataTable;
  DragonNode,MinionNode,DecoyNode: TCastleTransform;
  TagBeh: TCastleGameplayTagBehavior;
  BossRows: TDataRowKeyArray;
  MatchedTransforms: TDataTableTransformArray;
  CsvStr, JsonStr: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    World := TCastleTransform.Create(DesignOwner);
    World.Name := 'WorldRoot';

    DT := TDataTableStudioHelper.CreateDataTableInDesign(World, DesignOwner, 0);
    AssertTrue(DT <> nil);
    AssertEquals(5, DT.ColumnCount);
    AssertEquals(4, DT.RowCount);
    AssertSameValue(2500.0, DT.GetCellFloat('Elder_Dragon', 'MaxLife', 0.0), 0.01);
    AssertEquals(1500, DT.GetCellInt('Elder_Dragon', 'XPReward', 0));
    AssertTrue(DT.GetCellBool('Elder_Dragon', 'IsBoss', false));
    AssertFalse(DT.GetCellBool('Goblin_Scout', 'IsBoss', true));

    { 1. Hierarchical Gameplay Tag query on table rows (Enemy.Boss.* matches Dragon & Lich, NOT Goblin/Orc) }
    BossRows := DT.FindRowsMatchingTag('GameplayTag', 'Enemy.Boss.*');
    AssertEquals(2, Length(BossRows));
    AssertEquals('Elder_Dragon', BossRows[0]);
    AssertEquals('Lich_Sovereign', BossRows[1]);

    { Strict dot-segment boundary: 'Enemy.Boss' must NOT false-match 'Enemy.Bossy.Fake' }
    AssertTrue(TCastleGameplayTagBehavior.MatchesSingleTag('Enemy.Boss.Dragon', 'Enemy.Boss'));
    AssertTrue(TCastleGameplayTagBehavior.MatchesSingleTag('Enemy.Boss.Dragon', 'Enemy.Boss.*'));
    AssertFalse(TCastleGameplayTagBehavior.MatchesSingleTag('Enemy.Bossy.Fake', 'Enemy.Boss'));

    { 2. RFC-4180 CSV export/import roundtrip (including commas inside quoted multi-tag cells!) }
    CsvStr := DT.ExportCsv;
    CsvCopy := TCastleDataTable.Create(DesignOwner);
    CsvCopy.ImportCsv(CsvStr);
    AssertEquals(5, CsvCopy.ColumnCount);
    AssertEquals(4, CsvCopy.RowCount);
    AssertSameValue(1850.0, CsvCopy.GetCellFloat('Lich_Sovereign', 'MaxLife', 0.0), 0.01);
    AssertEquals(2, Length(CsvCopy.FindRowsMatchingTag('GameplayTag', 'Faction.Horde')));

    { 3. Scene transform Gameplay Tag behavior & HasAllTags / HasAnyTags }
    DragonNode := TCastleTransform.Create(DesignOwner);
    DragonNode.Name := 'DragonActor';
    World.Add(DragonNode);
    TagBeh := TDataTableStudioHelper.AttachGameplayTagsToTransform(
      DragonNode, DesignOwner, 'Enemy.Boss.Dragon, Element.Fire');
    AssertTrue(TagBeh.HasAllTags(['Enemy.Boss', 'Element.Fire']));
    AssertFalse(TagBeh.HasAllTags(['Enemy.Boss', 'Element.Ice']));
    AssertTrue(TagBeh.HasAnyTags(['Element.Ice', 'Element.Fire']));

    MinionNode := TCastleTransform.Create(DesignOwner);
    MinionNode.Name := 'GoblinActor';
    World.Add(MinionNode);
    TDataTableStudioHelper.AttachGameplayTagsToTransform(
      MinionNode, DesignOwner, 'Enemy.Minion.Goblin');

    DecoyNode := TCastleTransform.Create(DesignOwner);
    DecoyNode.Name := 'BossyDecoy';
    World.Add(DecoyNode);
    TDataTableStudioHelper.AttachGameplayTagsToTransform(
      DecoyNode, DesignOwner, 'Enemy.Bossy.Decoy');

    MatchedTransforms := TDataTableStudioHelper.FindTransformsMatchingGameplayTag(
      World, 'Enemy.Boss.*');
    AssertEquals(1, Length(MatchedTransforms));
    AssertTrue(MatchedTransforms[0] = DragonNode);

    { 4. ComponentToString / StringToComponent JSON roundtrip }
    JsonStr := ComponentToString(World);
    LoadedOwner := TComponent.Create(nil);
    try
      LoadedWorld := StringToComponent(JsonStr, LoadedOwner) as TCastleTransform;
      try
        LoadedDT := LoadedOwner.FindComponent(DT.Name) as TCastleDataTable;
        AssertTrue(LoadedDT <> nil);
        AssertEquals(4, LoadedDT.RowCount);
        AssertSameValue(2500.0, LoadedDT.GetCellFloat('Elder_Dragon', 'MaxLife', 0.0), 0.01);
      finally
        FreeAndNil(LoadedWorld);
      end;
    finally
      FreeAndNil(LoadedOwner);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolDataTableStudio.TestProgressionCurvesRttiRowBindingSchemaAuditAndMarkdown;
var
  DesignOwner: TComponent;
  World: TCastleTransform;
  DT: TCastleDataTable;
  Actor: TCastleTransform;
  Living: TCastleLiving;
  TagBeh: TCastleGameplayTagBehavior;
  Issues: TDataRowKeyArray;
  Applied: Integer;
  Report: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    World := TCastleTransform.Create(DesignOwner);
    World.Name := 'WorldRoot';

    { 1. Progression Curve formulas: Linear, Exponential, Polynomial, DiminishingReturns }
    AssertSameValue(100.0, TCastleDataTable.EvaluateCurveValue(bckLinear, 100.0, 25.0, 1), 0.01);
    AssertSameValue(200.0, TCastleDataTable.EvaluateCurveValue(bckLinear, 100.0, 25.0, 5), 0.01);
    AssertSameValue(400.0, TCastleDataTable.EvaluateCurveValue(bckExponential, 100.0, 2.0, 3), 0.01);
    AssertSameValue(90.0, TCastleDataTable.EvaluateCurveValue(bckPolynomial, 10.0, 2.0, 3), 0.01);
    AssertSameValue(50.0, TCastleDataTable.EvaluateCurveValue(bckDiminishingReturns, 100.0, 1.0, 1), 0.01);
    AssertTrue(TCastleDataTable.EvaluateCurveValue(bckDiminishingReturns, 100.0, 1.0, 100) < 100.0);
    AssertTrue(TCastleDataTable.EvaluateCurveValue(bckDiminishingReturns, 100.0, 1.0, 100) > 98.5);

    { 2. Live RTTI Row-to-Component binding onto TCastleLiving & TCastleTransform }
    DT := TDataTableStudioHelper.CreateDataTableInDesign(World, DesignOwner, 0);
    DT.AddColumn('Tag', dctInt, '0');
    DT.SetCellString('Elder_Dragon', 'Tag', '99');

    Actor := TCastleTransform.Create(DesignOwner);
    Actor.Name := 'BossDragonTransform';
    World.Add(Actor);

    Living := TCastleLiving.Create(DesignOwner);
    Living.Name := 'BossLiving';
    Actor.AddBehavior(Living);

    Applied := DT.ApplyRowToComponent('Elder_Dragon', Living, DesignOwner);
    AssertTrue(Applied >= 1);
    AssertSameValue(2500.0, Living.MaxLife, 0.01);

    Applied := DT.ApplyRowToComponent('Elder_Dragon', Actor, DesignOwner);
    AssertTrue(Applied >= 2);
    AssertEquals(99, Actor.Tag);
    TagBeh := Actor.FindBehavior(TCastleGameplayTagBehavior) as TCastleGameplayTagBehavior;
    AssertTrue(TagBeh <> nil);
    AssertTrue(TagBeh.HasTag('Enemy.Boss.Dragon'));

    { 3. Schema validation catches bad Float / Bool cells }
    AssertTrue(DT.ValidateSchemaCells(Issues));
    DT.SetCellString('Goblin_Scout', 'MaxLife', 'not_a_float');
    DT.SetCellString('Goblin_Scout', 'IsBoss', 'maybe');
    AssertFalse(DT.ValidateSchemaCells(Issues));
    AssertEquals(2, Length(Issues));

    Report := TDataTableStudioHelper.BuildMarkdownReport(World);
    AssertTrue(Pos('Elder_Dragon', Report) > 0);
    AssertTrue(Pos('Schema & Tag Diagnostics', Report) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolDataTableStudio);
end.
