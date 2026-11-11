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

{ Hierarchy discovery, 1-click RPG branching conversation + quest rig creation,
  RFC-4180 localization CSV export, graph auditing, and Markdown reporting for
  @link(TCastleDialogueTree), @link(TCastleQuestTracker), and
  @link(TCastleNpcDialogueBehavior) (Phase 302). }
unit ToolDialogueQuest;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleUiControls, CastleViewport,
  CastleDialogueQuest;

type
  TDialogueTreeComponentArray = array of TCastleDialogueTree;
  TQuestTrackerComponentArray = array of TCastleQuestTracker;
  TNpcDialogueBehaviorArray = array of TCastleNpcDialogueBehavior;

  { Hierarchy scan & graph audit summary for Dialogue & Quest Studio. }
  TDialogueQuestSummary = record
    Dialogues: TDialogueTreeComponentArray;
    QuestTrackers: TQuestTrackerComponentArray;
    NpcBehaviors: TNpcDialogueBehaviorArray;
    TotalNodes: Integer;
    TotalQuests: Integer;
    ActiveQuestsCount: Integer;
    CompletedQuestsCount: Integer;
    Warnings: array of String;
  end;

  { Stateless editor helper for Branching Dialogue, Quest Objectives & Narrative Graphs. }
  TDialogueQuestHelper = class
  public
    class function ScanDialogueAndQuests(
      const ARoot: TComponent): TDialogueQuestSummary;

    class function CreateSampleRpgQuestDialogueRig(
      const ARoot, ADesignOwner: TComponent): TCastleDialogueTree;

    class function AttachNpcDialogueBehavior(
      const ATarget: TCastleTransform; const ADesignOwner: TComponent;
      const ADialogue: TCastleDialogueTree;
      const ANpcName: String = 'Elder Rowan'): TCastleNpcDialogueBehavior;

    { Export all speaker lines and player choices of @code(ADialogue) as an
      RFC-4180 @code(Key,Speaker,SourceText) localization CSV. }
    class function ExportLocalizationCsv(
      const ADialogue: TCastleDialogueTree): String;

    class function BuildMarkdownReport(const ARoot: TComponent): String;
  end;

implementation

function ProposeUniqueNarrativeName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

function FindWorldTransformContainer(const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindWorldTransformContainer(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

function CsvEscapeField(const S: String): String;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or
     (Pos(#10, S) > 0) or (Pos(#13, S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

{ TDialogueQuestHelper ------------------------------------------------------- }

class function TDialogueQuestHelper.ScanDialogueAndQuests(
  const ARoot: TComponent): TDialogueQuestSummary;
var
  OutSum: TDialogueQuestSummary;
  Visited: TList;

  procedure AppendWarning(const Msg: String);
  var
    N: Integer;
  begin
    N := Length(OutSum.Warnings);
    SetLength(OutSum.Warnings, N + 1);
    OutSum.Warnings[N] := Msg;
  end;

  procedure AddDialogue(const D: TCastleDialogueTree);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.Dialogues) do
      if OutSum.Dialogues[I] = D then
        Exit;
    SetLength(OutSum.Dialogues, Length(OutSum.Dialogues) + 1);
    OutSum.Dialogues[High(OutSum.Dialogues)] := D;
    Inc(OutSum.TotalNodes, D.NodeCount);
  end;

  procedure AddTracker(const QT: TCastleQuestTracker);
  var
    I, QIdx: Integer;
    Q: TQuestDefinition;
  begin
    for I := 0 to High(OutSum.QuestTrackers) do
      if OutSum.QuestTrackers[I] = QT then
        Exit;
    SetLength(OutSum.QuestTrackers, Length(OutSum.QuestTrackers) + 1);
    OutSum.QuestTrackers[High(OutSum.QuestTrackers)] := QT;
    Inc(OutSum.TotalQuests, QT.QuestCount);
    for QIdx := 0 to QT.QuestCount - 1 do
    begin
      Q := QT.GetQuest(QIdx);
      if Q.State = qsActive then
        Inc(OutSum.ActiveQuestsCount)
      else
      if Q.State = qsCompleted then
        Inc(OutSum.CompletedQuestsCount);
    end;
  end;

  procedure AddNpc(const NB: TCastleNpcDialogueBehavior);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.NpcBehaviors) do
      if OutSum.NpcBehaviors[I] = NB then
        Exit;
    SetLength(OutSum.NpcBehaviors, Length(OutSum.NpcBehaviors) + 1);
    OutSum.NpcBehaviors[High(OutSum.NpcBehaviors)] := NB;
  end;

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if Visited.IndexOf(C) >= 0 then
      Exit;
    Visited.Add(C);

    if C is TCastleDialogueTree then
      AddDialogue(TCastleDialogueTree(C));
    if C is TCastleQuestTracker then
      AddTracker(TCastleQuestTracker(C));
    if C is TCastleNpcDialogueBehavior then
      AddNpc(TCastleNpcDialogueBehavior(C));

    if C is TCastleViewport then
    begin
      VP := TCastleViewport(C);
      if VP.Items <> nil then
        Visit(VP.Items);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Visit(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Visit(T[I]);
    end;

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;

    if C is TCastleComponent then
      for I := 0 to TCastleComponent(C).NonVisualComponentsCount - 1 do
        Visit(TCastleComponent(C).NonVisualComponents[I]);
  end;

var
  I, J: Integer;
  GraphWarns: TDialogueStringArray;
begin
  OutSum := Default(TDialogueQuestSummary);
  if ARoot = nil then
  begin
    Result := OutSum;
    Exit;
  end;

  Visited := TList.Create;
  try
    Visit(ARoot);
  finally
    FreeAndNil(Visited);
  end;

  for I := 0 to High(OutSum.Dialogues) do
    if not OutSum.Dialogues[I].ValidateGraph(GraphWarns) then
      for J := 0 to High(GraphWarns) do
        AppendWarning(GraphWarns[J]);

  for I := 0 to High(OutSum.NpcBehaviors) do
    if OutSum.NpcBehaviors[I].DialogueTree = nil then
      AppendWarning(Format('NPC Behavior "%s" has no DialogueTree assigned.',
        [OutSum.NpcBehaviors[I].Name]));

  Result := OutSum;
end;

class function TDialogueQuestHelper.AttachNpcDialogueBehavior(
  const ATarget: TCastleTransform; const ADesignOwner: TComponent;
  const ADialogue: TCastleDialogueTree;
  const ANpcName: String): TCastleNpcDialogueBehavior;
var
  OwnerToUse: TComponent;
begin
  Result := nil;
  if ATarget = nil then
    Exit;
  Result := ATarget.FindBehavior(TCastleNpcDialogueBehavior) as TCastleNpcDialogueBehavior;
  if Result = nil then
  begin
    if ADesignOwner <> nil then
      OwnerToUse := ADesignOwner
    else
      OwnerToUse := ATarget.Owner;
    Result := TCastleNpcDialogueBehavior.Create(OwnerToUse);
    Result.Name := ProposeUniqueNarrativeName(OwnerToUse, 'NpcDialogue');
    ATarget.AddBehavior(Result);
  end;
  Result.NpcDisplayName := ANpcName;
  Result.DialogueTree := ADialogue;
end;

class function TDialogueQuestHelper.CreateSampleRpgQuestDialogueRig(
  const ARoot, ADesignOwner: TComponent): TCastleDialogueTree;
var
  OwnerToUse: TComponent;
  Tracker: TCastleQuestTracker;
  WorldCont, NpcTrans: TCastleTransform;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Tracker := TCastleQuestTracker.Create(OwnerToUse);
  Tracker.Name := ProposeUniqueNarrativeName(OwnerToUse, 'QuestTracker');
  Tracker.AddOrUpdateQuest(
    'Quest_SunfireRelic',
    'Recover the Sunfire Relic',
    'Speak with Elder Rowan and retrieve the Sunfire Relic from the sunken vault.',
    qsLocked, 500, 'Achievement.RelicBearer');
  Tracker.AddObjective('Quest_SunfireRelic', 'SpeakElder', 'Hear Elder Rowan''s plea', 1, false);
  Tracker.AddObjective('Quest_SunfireRelic', 'CollectRelic', 'Obtain the Sunfire Relic', 1, false);
  Tracker.SetVariableFloat('Charisma', 12.0);
  Tracker.SetVariableFloat('Gold', 100.0);

  Result := TCastleDialogueTree.Create(OwnerToUse);
  Result.Name := ProposeUniqueNarrativeName(OwnerToUse, 'ElderDialogue');
  Result.DialogueTitle := 'Elder Rowan — Sunfire Sanctuary';
  Result.DefaultSpeaker := 'Elder Rowan';
  Result.QuestTracker := Tracker;

  Result.AddNode('Greeting', 'Elder Rowan',
    'Traveler! Shadow creeps from the Sunken Vault, and the Sunfire Relic grows dim.',
    'dlg.elder.greeting', 50.0, 120.0);
  Result.AddNode('SecretShortcut', 'Elder Rowan',
    'Your silver tongue convinces me. Take this ancient key to bypass the outer gate.',
    'dlg.elder.shortcut', 340.0, 30.0);
  Result.AddNode('QuestAccepted', 'Elder Rowan',
    'May the embers guide your blade! Return when the Sunfire Relic is in your grasp.',
    'dlg.elder.accepted', 340.0, 150.0);
  Result.AddNode('Victory', 'Elder Rowan',
    'By the dawn! The Sunfire Relic blazes anew — the sanctuary is saved!',
    'dlg.elder.victory', 340.0, 270.0);

  Result.AddChoice('Greeting', 'PersuadeKey',
    '[Charisma >= 10] Reveal the vault''s secret shortcut.', 'SecretShortcut',
    'dlg.elder.c_persuade', dcoVarGte, 'Charisma', '10',
    dakGrantTag, 'Quest.VaultShortcutKey', '');
  Result.AddChoice('Greeting', 'AcceptPlea',
    'I will recover the Sunfire Relic for the village.', 'QuestAccepted',
    'dlg.elder.c_accept', dcoQuestState, 'Quest_SunfireRelic', 'Locked',
    dakAdvanceObjective, 'Quest_SunfireRelic:SpeakElder', '1');
  Result.AddChoice('Greeting', 'HandOverRelic',
    '[Requires Sunfire Relic] Present the recovered Sunfire Relic.', 'Victory',
    'dlg.elder.c_turnin', dcoHasTag, 'Item.SunfireRelic', '',
    dakAdvanceObjective, 'Quest_SunfireRelic:CollectRelic', '1');
  Result.AddChoice('Greeting', 'LeaveNow',
    'Farewell for now, Elder.', 'END', 'dlg.elder.c_leave');

  Result.AddChoice('SecretShortcut', 'BackFromShortcut',
    'Let us speak of the Sunfire Relic.', 'Greeting', 'dlg.elder.c_back1');
  Result.AddChoice('QuestAccepted', 'EndAccepted',
    'I depart at once.', 'END', 'dlg.elder.c_end_accept');
  Result.AddChoice('Victory', 'EndVictory',
    'Honor to the sanctuary.', 'END', 'dlg.elder.c_end_victory');

  if ARoot is TCastleComponent then
  begin
    TCastleComponent(ARoot).AddNonVisualComponent(Tracker);
    TCastleComponent(ARoot).AddNonVisualComponent(Result);
  end;

  WorldCont := FindWorldTransformContainer(ARoot);
  if WorldCont <> nil then
  begin
    NpcTrans := TCastleTransform.Create(OwnerToUse);
    NpcTrans.Name := ProposeUniqueNarrativeName(OwnerToUse, 'NpcElderRowan');
    NpcTrans.Translation := Vector3(0.0, 0.0, -3.0);
    AttachNpcDialogueBehavior(NpcTrans, OwnerToUse, Result, 'Elder Rowan');
    WorldCont.Add(NpcTrans);
  end;
end;

class function TDialogueQuestHelper.ExportLocalizationCsv(
  const ADialogue: TCastleDialogueTree): String;
var
  SB: TStringBuilder;
  I, J: Integer;
  N: TDialogueNodeDef;
begin
  if ADialogue = nil then
    Exit('');
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('Key,Speaker,SourceText');
    for I := 0 to ADialogue.NodeCount - 1 do
    begin
      N := ADialogue.GetNode(I);
      SB.AppendLine(Format('%s,%s,%s', [
        CsvEscapeField(N.LocalizationKey),
        CsvEscapeField(N.SpeakerName),
        CsvEscapeField(N.DialogueText)]));
      for J := 0 to High(N.Choices) do
        SB.AppendLine(Format('%s,%s,%s', [
          CsvEscapeField(N.Choices[J].LocalizationKey),
          'Player',
          CsvEscapeField(N.Choices[J].ChoiceText)]));
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

class function TDialogueQuestHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Sum: TDialogueQuestSummary;
  SB: TStringBuilder;
  I, J: Integer;
  QT: TCastleQuestTracker;
  Q: TQuestDefinition;
begin
  Sum := ScanDialogueAndQuests(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Narrative Dialogue & Quest Objectives Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Dialogue Trees**: `%d` (`%d` nodes) | **Quest Trackers**: `%d` (`%d` quests: `%d` Active, `%d` Completed) | **3D NPCs**: `%d`',
      [Length(Sum.Dialogues), Sum.TotalNodes,
       Length(Sum.QuestTrackers), Sum.TotalQuests,
       Sum.ActiveQuestsCount, Sum.CompletedQuestsCount,
       Length(Sum.NpcBehaviors)]));
    SB.AppendLine;

    for I := 0 to High(Sum.QuestTrackers) do
    begin
      QT := Sum.QuestTrackers[I];
      SB.AppendLine(Format('## Quest Tracker `%s`', [QT.Name]));
      SB.AppendLine('| Quest ID | Title | State | Objectives | Reward |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- |');
      for J := 0 to QT.QuestCount - 1 do
      begin
        Q := QT.GetQuest(J);
        SB.AppendLine(Format('| `%s` | %s | `%s` | `%d` | `%d XP` (`%s`) |',
          [Q.QuestId, Q.Title, TCastleQuestTracker.QuestStateToName(Q.State),
           Length(Q.Objectives), Q.RewardXp, Q.RewardTag]));
      end;
      SB.AppendLine;
    end;

    if Length(Sum.Warnings) > 0 then
    begin
      SB.AppendLine('## Graph & Narrative Diagnostics');
      for I := 0 to High(Sum.Warnings) do
        SB.AppendLine('- [!] ' + Sum.Warnings[I]);
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
