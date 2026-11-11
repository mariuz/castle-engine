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

{ Automated unit tests for Phase 302 Branching Dialogue, Quest Objectives &
  Narrative Graph Studio (@link(TCastleDialogueTree), @link(TCastleQuestTracker),
  @link(TCastleNpcDialogueBehavior), and @link(TDialogueQuestHelper)). }
unit TestToolDialogueQuest;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolDialogueQuest = class(TCastleTestCase)
  published
    procedure TestBranchingChoiceConditionsQuestAutoCompletionAndPlaythrough;
    procedure TestGraphValidationLocalizationCsvExportAndJsonRoundtrip;
  end;

implementation

uses
  CastleComponentSerialize, CastleTransform,
  EditorRegisterAllComponents,
  CastleDialogueQuest, ToolDialogueQuest;

procedure TTestToolDialogueQuest.TestBranchingChoiceConditionsQuestAutoCompletionAndPlaythrough;
var
  DesignOwner: TComponent;
  World: TCastleTransform;
  Dlg: TCastleDialogueTree;
  Tracker: TCastleQuestTracker;
  Avail: TDialogueChoiceDefArray;
  NextNode: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    World := TCastleTransform.Create(DesignOwner);
    World.Name := 'WorldRoot';

    Dlg := TDialogueQuestHelper.CreateSampleRpgQuestDialogueRig(World, DesignOwner);
    AssertTrue(Dlg <> nil);
    Tracker := Dlg.QuestTracker;
    AssertTrue(Tracker <> nil);
    AssertEquals(Ord(qsLocked), Ord(Tracker.GetQuestState('Quest_SunfireRelic')));

    { 1. At Greeting: Charisma=12 (>=10 passes), Quest=Locked (passes), Item.SunfireRelic missing (filtered out!) }
    Avail := Dlg.GetAvailableChoices('Greeting');
    AssertEquals(3, Length(Avail));
    AssertEquals('PersuadeKey', Avail[0].ChoiceId);
    AssertEquals('AcceptPlea', Avail[1].ChoiceId);
    AssertEquals('LeaveNow', Avail[2].ChoiceId);

    { 2. Lowering Charisma to 5 hides PersuadeKey choice }
    Tracker.SetVariableFloat('Charisma', 5.0);
    Avail := Dlg.GetAvailableChoices('Greeting');
    AssertEquals(2, Length(Avail));
    AssertEquals('AcceptPlea', Avail[0].ChoiceId);

    { 3. Choosing AcceptPlea activates Quest_SunfireRelic and advances SpeakElder (1/1) }
    AssertTrue(Dlg.StepConversation('Greeting', 0, NextNode));
    AssertEquals('QuestAccepted', NextNode);
    AssertEquals(Ord(qsActive), Ord(Tracker.GetQuestState('Quest_SunfireRelic')));

    { 4. Granting Item.SunfireRelic unlocks HandOverRelic on Greeting, which completes
         the final required objective CollectRelic -> auto-completes quest + grants XP + RewardTag! }
    Tracker.GrantGameplayTag('Item.SunfireRelic');
    Avail := Dlg.GetAvailableChoices('Greeting');
    AssertEquals(2, Length(Avail));
    AssertEquals('HandOverRelic', Avail[0].ChoiceId);

    AssertTrue(Dlg.StepConversation('Greeting', 0, NextNode));
    AssertEquals('Victory', NextNode);
    AssertEquals(Ord(qsCompleted), Ord(Tracker.GetQuestState('Quest_SunfireRelic')));
    AssertSameValue(500.0, Tracker.GetVariableFloat('XP', 0.0), 1e-3);
    AssertTrue(Tracker.HasGameplayTag('Achievement.*'));

    { 5. Selecting terminal choice on Victory ends conversation with NextNode = '' }
    AssertTrue(Dlg.StepConversation('Victory', 0, NextNode));
    AssertEquals('', NextNode);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolDialogueQuest.TestGraphValidationLocalizationCsvExportAndJsonRoundtrip;
var
  DesignOwner, LoadedOwner: TComponent;
  World, LoadedWorld: TCastleTransform;
  Dlg: TCastleDialogueTree;
  Warns: TDialogueStringArray;
  CsvStr, JsonStr, Report: String;
  LoadedSum: TDialogueQuestSummary;
begin
  DesignOwner := TComponent.Create(nil);
  try
    World := TCastleTransform.Create(DesignOwner);
    World.Name := 'WorldRoot';

    Dlg := TDialogueQuestHelper.CreateSampleRpgQuestDialogueRig(World, DesignOwner);
    AssertTrue(Dlg.ValidateGraph(Warns));
    AssertEquals(0, Length(Warns));

    { 1. Localization CSV export contains header + speaker keys + player choice keys }
    CsvStr := TDialogueQuestHelper.ExportLocalizationCsv(Dlg);
    AssertTrue(Pos('Key,Speaker,SourceText', CsvStr) > 0);
    AssertTrue(Pos('dlg.elder.greeting,Elder Rowan,', CsvStr) > 0);
    AssertTrue(Pos('dlg.elder.c_accept,Player,', CsvStr) > 0);

    { 2. Injecting an unreachable orphan node & broken target triggers ValidateGraph }
    Dlg.AddNode('OrphanIsland', 'Ghost', 'Nobody can reach me.');
    Dlg.AddChoice('OrphanIsland', 'BrokenJump', 'Into the void', 'NonExistentNode');
    AssertFalse(Dlg.ValidateGraph(Warns));
    AssertTrue(Length(Warns) >= 2);

    Report := TDialogueQuestHelper.BuildMarkdownReport(World);
    AssertTrue(Pos('Graph & Narrative Diagnostics', Report) > 0);

    { 3. Remove orphan node -> graph valid again, then roundtrip via ComponentToString }
    AssertTrue(Dlg.RemoveNode('OrphanIsland'));
    AssertTrue(Dlg.ValidateGraph(Warns));

    JsonStr := ComponentToString(World);
    LoadedOwner := TComponent.Create(nil);
    try
      LoadedWorld := StringToComponent(JsonStr, LoadedOwner) as TCastleTransform;
      try
        LoadedSum := TDialogueQuestHelper.ScanDialogueAndQuests(LoadedWorld);
        AssertEquals(1, Length(LoadedSum.Dialogues));
        AssertEquals(4, LoadedSum.TotalNodes);
        AssertEquals(1, Length(LoadedSum.QuestTrackers));
        AssertEquals(1, LoadedSum.TotalQuests);
        AssertEquals(1, Length(LoadedSum.NpcBehaviors));
        AssertTrue(LoadedSum.Dialogues[0].QuestTracker = LoadedSum.QuestTrackers[0]);
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

initialization
  RegisterTest(TTestToolDialogueQuest);
end.
