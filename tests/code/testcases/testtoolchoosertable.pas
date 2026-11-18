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

{ Automated tests for Phase 347 Chooser Tables Multi-Column Tag/Range/Bool
  Evaluation, Priority Tiering, Weighted Tie-Breaking & JSON Roundtrips. }
unit TestToolChooserTable;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolChooserTable = class(TCastleTestCase)
  published
    procedure TestMultiColumnTagPrefixNumericRangeBoolAndFallbackResolution;
    procedure TestWeightedTieBreakingRowValidationAndConfigJsonPresetRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform,
  CastleComponentSerialize,
  CastleChooserTable, ToolChooserTable;

procedure TTestToolChooserTable.TestMultiColumnTagPrefixNumericRangeBoolAndFallbackResolution;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Table: TCastleChooserTable;
  Chosen: TChooserRow;
  AssetUrl: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TChooserTableHelper.SpawnFootstepAndBarkChooserDemo(Vp, DesignOwner, Table));
    AssertTrue(Table <> nil);

    { 1. Hierarchical sub-tag 'Surface.Stone.Wet' matches 'Surface.Stone' + Sprint speed 6.2 }
    AssetUrl := Table.EvaluateChooser(
      TChooserContextQuery.Create('Surface.Stone.Wet', 'Stance.Sprint', 6.2, 0.0, True),
      Chosen);
    AssertEquals('castle-data:/sfx/footstep_stone_sprint.wav', AssetUrl);
    AssertSameValue(1.25, Chosen.ResultScale, 0.001);

    { 2. Crouch sneak on Stone selects quiet scuff with 0.35x volume scale }
    AssetUrl := Table.EvaluateChooser(
      TChooserContextQuery.Create('Surface.Stone', 'Stance.Crouch', 1.2, 0.0, True),
      Chosen);
    AssertEquals('castle-data:/sfx/footstep_stone_scuff_quiet.wav', AssetUrl);
    AssertSameValue(0.35, Chosen.ResultScale, 0.001);

    { 3. Unmatched surface ('Surface.Snow') falls back cleanly to Priority 0 wildcard row }
    AssetUrl := Table.EvaluateChooser(
      TChooserContextQuery.Create('Surface.Snow', 'Stance.Walk', 2.5, 0.0, True),
      Chosen);
    AssertEquals('castle-data:/sfx/footstep_generic_dirt.wav', AssetUrl);

    { 4. Melee preset: Airborne (BoolFlag=False) Greatsword triggers plunge slam }
    Table.ApplyPreset(chpMeleeComboMontage);
    AssetUrl := Table.EvaluateChooser(
      TChooserContextQuery.Create('Weapon.Greatsword', '', 1.0, 0.0, False),
      Chosen);
    AssertEquals('anim_greatsword_air_slam', AssetUrl);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolChooserTable.TestWeightedTieBreakingRowValidationAndConfigJsonPresetRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Table, RestoredTable: TCastleChooserTable;
  Chosen: TChooserRow;
  CountA, CountB, CountC, I: Integer;
  Warnings: TStringList;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TChooserTableHelper.SpawnFootstepAndBarkChooserDemo(Vp, DesignOwner, Table));

    { 1. AI Combat Barks: 3 equal-priority (Prio=20) rows with weights 3 : 2 : 1;
         unless HealthRatio <= 0.25 which preempts via Prio=35 medic bark! }
    Table.ApplyPreset(chpAiCombatBarkSelector);
    Table.RandomSeed := 424242;
    CountA := 0; CountB := 0; CountC := 0;
    for I := 1 to 120 do
    begin
      Table.EvaluateChooser(
        TChooserContextQuery.Create('Bark.Flank', 'Alert.Combat', 10.0, 0.85, True),
        Chosen);
      if Chosen.RowId = 'Bark_Flank_A' then Inc(CountA)
      else if Chosen.RowId = 'Bark_Flank_B' then Inc(CountB)
      else if Chosen.RowId = 'Bark_Flank_C' then Inc(CountC);
    end;
    AssertEquals(120, CountA + CountB + CountC);
    AssertTrue((CountA > CountB) and (CountB > CountC) and (CountC > 5));

    { Critical HP (0.15 <= 0.25) preempts with Priority 35 medic callout }
    AssertEquals('castle-data:/vo/npc_need_medic.ogg',
      Table.EvaluateChooser(
        TChooserContextQuery.Create('Bark.Flank', 'Alert.Combat', 10.0, 0.15, True),
        Chosen));

    { 2. Validation catches inverted numeric range }
    AssertTrue(Table.ValidateRows(Warnings));
    Table.Preset := chpCustom;
    Table.AddChooserRow('BadRange', 'castle-data:/sfx/bad.wav', 10, 1.0, 'X', '', 15.0, 5.0);
    AssertFalse(Table.ValidateRows(Warnings));
    AssertTrue(Warnings.Count >= 1);

    ReportMd := TChooserTableHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Context-Driven Chooser Tables Report', ReportMd) > 0);

    { 3. ConfigJson roundtrip preserving custom rows without alphabetical Preset overwrite }
    JsonStr := ComponentToString(Table);
    RestoredTable := StringToComponent(JsonStr, RestoredOwner) as TCastleChooserTable;
    AssertTrue(RestoredTable <> nil);
    AssertTrue(RestoredTable.Preset = chpCustom);
    AssertEquals(Table.RowCount, RestoredTable.RowCount);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolChooserTable);

end.
