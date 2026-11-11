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

{ Interactive Branching Dialogue, Quest Objectives & Narrative Graph Studio
  (@link(TDialogueQuestForm)) featuring a 2D draggable directed speaker node
  canvas, live interactive conversation playthrough simulator, and quest
  blackboard inspector (Phase 302 — UE 6.0 Narrative / Parley Parity). }
unit FormDialogueQuest;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Grids, Graphics, Dialogs, Clipbrd,
  CastleUtils, CastleDialogueQuest, ToolDialogueQuest;

type
  TDialogueQuestModifiedCallback = procedure(const AComment: String) of object;
  TDialogueQuestRefreshViewportCallback = procedure of object;

  TDialogueQuestForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TDialogueQuestModifiedCallback;
    FOnRefreshViewport: TDialogueQuestRefreshViewportCallback;

    FSummary: TDialogueQuestSummary;
    FCurrentDialogue: TCastleDialogueTree;
    FSelectedNodeId: String;
    FDraggingNodeId: String;
    FDragOffsetX, FDragOffsetY: Integer;

    { Simulator state }
    FSimActiveNodeId: String;
    FSimAvailableChoices: TDialogueChoiceDefArray;

    LblHeaderSummary: TLabel;
    CmbDialogues: TComboBox;
    ListNodes: TListBox;
    GridQuests: TStringGrid;
    EditTagGrant: TEdit;
    PaintGraph: TPaintBox;

    LblSimSpeaker: TLabel;
    MemoSimDialogue: TMemo;
    ListSimChoices: TListBox;
    MemoLog: TMemo;

    procedure BuildUi;
    procedure RefreshHierarchy(const APreferredDialogue: TCastleDialogueTree = nil);
    procedure PopulateDialogueUi;
    procedure PopulateQuestGrid;
    procedure RestartSimulator;
    procedure UpdateSimulatorPrompt;
    procedure NotifyModified(const AComment: String);

    procedure CmbDialoguesChange(Sender: TObject);
    procedure ListNodesClick(Sender: TObject);
    procedure BtnCreateSampleClick(Sender: TObject);
    procedure BtnAddNodeClick(Sender: TObject);
    procedure BtnAddChoiceClick(Sender: TObject);
    procedure BtnGrantTagClick(Sender: TObject);
    procedure BtnValidateClick(Sender: TObject);
    procedure BtnCopyLocCsvClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure BtnSimRestartClick(Sender: TObject);
    procedure BtnSimChooseClick(Sender: TObject);
    procedure ListSimChoicesDblClick(Sender: TObject);

    procedure PaintGraphPaint(Sender: TObject);
    procedure PaintGraphMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintGraphMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure PaintGraphMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure BtnCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner, AInitialComponent: TComponent;
      const AOnModified: TDialogueQuestModifiedCallback;
      const AOnRefreshViewport: TDialogueQuestRefreshViewportCallback);
  end;

implementation

const
  GraphCardW = 210;
  GraphCardH = 78;

constructor TDialogueQuestForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner, AInitialComponent: TComponent;
  const AOnModified: TDialogueQuestModifiedCallback;
  const AOnRefreshViewport: TDialogueQuestRefreshViewportCallback);
var
  InitDlg: TCastleDialogueTree;
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Branching Dialogue, Quest Objectives & Narrative Graph Studio';
  Width := 1120;
  Height := 740;
  Position := poMainFormCenter;

  BuildUi;

  InitDlg := nil;
  if AInitialComponent is TCastleDialogueTree then
    InitDlg := TCastleDialogueTree(AInitialComponent)
  else
  if AInitialComponent is TCastleNpcDialogueBehavior then
    InitDlg := TCastleNpcDialogueBehavior(AInitialComponent).DialogueTree;

  RefreshHierarchy(InitDlg);
end;

procedure TDialogueQuestForm.BuildUi;
var
  TopBar, LeftPanel, RightSplit, SimPanel, BottomBar, TagRow, SimBtnRow: TPanel;
  BtnSample, BtnAddNode, BtnAddChoice, BtnValidate, BtnLocCsv, BtnReport: TButton;
  BtnGrantTag, BtnSimRestart, BtnSimChoose, BtnClose: TButton;
  LblDlg, LblNodes, LblQuests, LblGraph: TLabel;
begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 46;
  TopBar.BevelOuter := bvNone;

  BtnSample := TButton.Create(Self);
  BtnSample.Parent := TopBar;
  BtnSample.SetBounds(10, 8, 200, 30);
  BtnSample.Caption := '+ Sample RPG Dialogue + Quest';
  BtnSample.OnClick := @BtnCreateSampleClick;

  BtnAddNode := TButton.Create(Self);
  BtnAddNode.Parent := TopBar;
  BtnAddNode.SetBounds(216, 8, 110, 30);
  BtnAddNode.Caption := '+ Speaker Node';
  BtnAddNode.OnClick := @BtnAddNodeClick;

  BtnAddChoice := TButton.Create(Self);
  BtnAddChoice.Parent := TopBar;
  BtnAddChoice.SetBounds(332, 8, 110, 30);
  BtnAddChoice.Caption := '+ Player Choice';
  BtnAddChoice.OnClick := @BtnAddChoiceClick;

  BtnValidate := TButton.Create(Self);
  BtnValidate.Parent := TopBar;
  BtnValidate.SetBounds(448, 8, 118, 30);
  BtnValidate.Caption := 'Validate Graph';
  BtnValidate.OnClick := @BtnValidateClick;

  BtnLocCsv := TButton.Create(Self);
  BtnLocCsv.Parent := TopBar;
  BtnLocCsv.SetBounds(572, 8, 148, 30);
  BtnLocCsv.Caption := 'Copy Localization CSV';
  BtnLocCsv.OnClick := @BtnCopyLocCsvClick;

  BtnReport := TButton.Create(Self);
  BtnReport.Parent := TopBar;
  BtnReport.SetBounds(726, 8, 148, 30);
  BtnReport.Caption := 'Copy Markdown Report';
  BtnReport.OnClick := @BtnCopyReportClick;

  LblHeaderSummary := TLabel.Create(Self);
  LblHeaderSummary.Parent := TopBar;
  LblHeaderSummary.SetBounds(886, 15, 220, 20);
  LblHeaderSummary.Caption := '0 Dialogues';

  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 40;
  BottomBar.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := BottomBar;
  BtnClose.SetBounds(1000, 5, 104, 28);
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.Caption := 'Close';
  BtnClose.OnClick := @BtnCloseClick;

  LeftPanel := TPanel.Create(Self);
  LeftPanel.Parent := Self;
  LeftPanel.Align := alLeft;
  LeftPanel.Width := 330;
  LeftPanel.BevelOuter := bvNone;

  LblDlg := TLabel.Create(Self);
  LblDlg.Parent := LeftPanel;
  LblDlg.SetBounds(10, 8, 280, 18);
  LblDlg.Caption := 'Active Dialogue Tree:';

  CmbDialogues := TComboBox.Create(Self);
  CmbDialogues.Parent := LeftPanel;
  CmbDialogues.SetBounds(10, 28, 310, 26);
  CmbDialogues.Style := csDropDownList;
  CmbDialogues.OnChange := @CmbDialoguesChange;

  LblNodes := TLabel.Create(Self);
  LblNodes.Parent := LeftPanel;
  LblNodes.SetBounds(10, 62, 280, 18);
  LblNodes.Caption := 'Speaker Nodes:';

  ListNodes := TListBox.Create(Self);
  ListNodes.Parent := LeftPanel;
  ListNodes.SetBounds(10, 82, 310, 150);
  ListNodes.OnClick := @ListNodesClick;

  LblQuests := TLabel.Create(Self);
  LblQuests.Parent := LeftPanel;
  LblQuests.SetBounds(10, 240, 310, 18);
  LblQuests.Caption := 'Linked Quest Tracker & Objectives:';

  GridQuests := TStringGrid.Create(Self);
  GridQuests.Parent := LeftPanel;
  GridQuests.SetBounds(10, 260, 310, 185);
  GridQuests.ColCount := 3;
  GridQuests.RowCount := 2;
  GridQuests.FixedCols := 0;
  GridQuests.FixedRows := 1;
  GridQuests.ColWidths[0] := 125;
  GridQuests.ColWidths[1] := 75;
  GridQuests.ColWidths[2] := 95;
  GridQuests.Cells[0, 0] := 'Quest / Objective';
  GridQuests.Cells[1, 0] := 'State';
  GridQuests.Cells[2, 0] := 'Progress';

  TagRow := TPanel.Create(Self);
  TagRow.Parent := LeftPanel;
  TagRow.SetBounds(10, 452, 310, 34);
  TagRow.BevelOuter := bvNone;

  EditTagGrant := TEdit.Create(Self);
  EditTagGrant.Parent := TagRow;
  EditTagGrant.SetBounds(0, 4, 205, 26);
  EditTagGrant.Text := 'Item.SunfireRelic';

  BtnGrantTag := TButton.Create(Self);
  BtnGrantTag.Parent := TagRow;
  BtnGrantTag.SetBounds(210, 2, 100, 28);
  BtnGrantTag.Caption := 'Grant Tag';
  BtnGrantTag.OnClick := @BtnGrantTagClick;

  MemoLog := TMemo.Create(Self);
  MemoLog.Parent := LeftPanel;
  MemoLog.SetBounds(10, 492, 310, 150);
  MemoLog.ReadOnly := true;
  MemoLog.ScrollBars := ssVertical;

  RightSplit := TPanel.Create(Self);
  RightSplit.Parent := Self;
  RightSplit.Align := alClient;
  RightSplit.BevelOuter := bvNone;

  SimPanel := TPanel.Create(Self);
  SimPanel.Parent := RightSplit;
  SimPanel.Align := alBottom;
  SimPanel.Height := 220;
  SimPanel.BevelOuter := bvLowered;

  LblSimSpeaker := TLabel.Create(Self);
  LblSimSpeaker.Parent := SimPanel;
  LblSimSpeaker.SetBounds(12, 8, 520, 20);
  LblSimSpeaker.Font.Style := [fsBold];
  LblSimSpeaker.Caption := 'Interactive Conversation Playthrough Simulator';

  SimBtnRow := TPanel.Create(Self);
  SimBtnRow.Parent := SimPanel;
  SimBtnRow.SetBounds(540, 4, 235, 30);
  SimBtnRow.Anchors := [akTop, akRight];
  SimBtnRow.BevelOuter := bvNone;

  BtnSimRestart := TButton.Create(Self);
  BtnSimRestart.Parent := SimBtnRow;
  BtnSimRestart.SetBounds(0, 1, 108, 26);
  BtnSimRestart.Caption := 'Restart Sim';
  BtnSimRestart.OnClick := @BtnSimRestartClick;

  BtnSimChoose := TButton.Create(Self);
  BtnSimChoose.Parent := SimBtnRow;
  BtnSimChoose.SetBounds(114, 1, 118, 26);
  BtnSimChoose.Caption := 'Select Choice ->';
  BtnSimChoose.OnClick := @BtnSimChooseClick;

  MemoSimDialogue := TMemo.Create(Self);
  MemoSimDialogue.Parent := SimPanel;
  MemoSimDialogue.SetBounds(12, 34, 760, 62);
  MemoSimDialogue.Anchors := [akTop, akLeft, akRight];
  MemoSimDialogue.ReadOnly := true;

  ListSimChoices := TListBox.Create(Self);
  ListSimChoices.Parent := SimPanel;
  ListSimChoices.SetBounds(12, 102, 760, 108);
  ListSimChoices.Anchors := [akTop, akLeft, akRight, akBottom];
  ListSimChoices.OnDblClick := @ListSimChoicesDblClick;

  LblGraph := TLabel.Create(Self);
  LblGraph.Parent := RightSplit;
  LblGraph.Align := alTop;
  LblGraph.Caption := '  2D Directed Narrative Graph (drag speaker nodes to arrange; green = Entry, cyan = Active Sim Node):';

  PaintGraph := TPaintBox.Create(Self);
  PaintGraph.Parent := RightSplit;
  PaintGraph.Align := alClient;
  PaintGraph.OnPaint := @PaintGraphPaint;
  PaintGraph.OnMouseDown := @PaintGraphMouseDown;
  PaintGraph.OnMouseMove := @PaintGraphMouseMove;
  PaintGraph.OnMouseUp := @PaintGraphMouseUp;
end;

procedure TDialogueQuestForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TDialogueQuestForm.RefreshHierarchy(
  const APreferredDialogue: TCastleDialogueTree);
var
  I, PrefIdx: Integer;
begin
  FSummary := TDialogueQuestHelper.ScanDialogueAndQuests(FDesignRoot);
  LblHeaderSummary.Caption := Format('%d Dialogues | %d Quests',
    [Length(FSummary.Dialogues), FSummary.TotalQuests]);

  CmbDialogues.Items.BeginUpdate;
  try
    CmbDialogues.Items.Clear;
    PrefIdx := -1;
    for I := 0 to High(FSummary.Dialogues) do
    begin
      CmbDialogues.Items.AddObject(
        Format('%s (%d nodes)', [FSummary.Dialogues[I].Name, FSummary.Dialogues[I].NodeCount]),
        FSummary.Dialogues[I]);
      if FSummary.Dialogues[I] = APreferredDialogue then
        PrefIdx := I;
    end;
    if (PrefIdx < 0) and (CmbDialogues.Items.Count > 0) then
      PrefIdx := 0;
    CmbDialogues.ItemIndex := PrefIdx;
  finally
    CmbDialogues.Items.EndUpdate;
  end;

  if CmbDialogues.ItemIndex >= 0 then
    FCurrentDialogue := TCastleDialogueTree(CmbDialogues.Items.Objects[CmbDialogues.ItemIndex])
  else
    FCurrentDialogue := nil;

  PopulateDialogueUi;
  RestartSimulator;
end;

procedure TDialogueQuestForm.PopulateDialogueUi;
var
  I: Integer;
  N: TDialogueNodeDef;
begin
  ListNodes.Items.BeginUpdate;
  try
    ListNodes.Items.Clear;
    if FCurrentDialogue <> nil then
      for I := 0 to FCurrentDialogue.NodeCount - 1 do
      begin
        N := FCurrentDialogue.GetNode(I);
        ListNodes.Items.Add(Format('[%s] %s (%d choices)',
          [N.NodeId, N.SpeakerName, Length(N.Choices)]));
      end;
    if (ListNodes.Items.Count > 0) and (FSelectedNodeId = '') then
    begin
      ListNodes.ItemIndex := 0;
      FSelectedNodeId := FCurrentDialogue.GetNode(0).NodeId;
    end;
  finally
    ListNodes.Items.EndUpdate;
  end;

  PopulateQuestGrid;
  PaintGraph.Invalidate;
end;

procedure TDialogueQuestForm.PopulateQuestGrid;
var
  Tracker: TCastleQuestTracker;
  Rows, QIdx, OIdx: Integer;
  Q: TQuestDefinition;
begin
  Tracker := nil;
  if FCurrentDialogue <> nil then
    Tracker := FCurrentDialogue.QuestTracker;
  if (Tracker = nil) and (Length(FSummary.QuestTrackers) > 0) then
    Tracker := FSummary.QuestTrackers[0];

  if (Tracker = nil) or (Tracker.QuestCount = 0) then
  begin
    GridQuests.RowCount := 2;
    GridQuests.Cells[0, 1] := '(no quests)';
    GridQuests.Cells[1, 1] := '-';
    GridQuests.Cells[2, 1] := '-';
    Exit;
  end;

  Rows := 1;
  for QIdx := 0 to Tracker.QuestCount - 1 do
  begin
    Q := Tracker.GetQuest(QIdx);
    Inc(Rows, 1 + Length(Q.Objectives));
  end;
  GridQuests.RowCount := Max(2, Rows);

  Rows := 1;
  for QIdx := 0 to Tracker.QuestCount - 1 do
  begin
    Q := Tracker.GetQuest(QIdx);
    GridQuests.Cells[0, Rows] := Q.Title;
    GridQuests.Cells[1, Rows] := TCastleQuestTracker.QuestStateToName(Q.State);
    GridQuests.Cells[2, Rows] := Format('%d XP', [Q.RewardXp]);
    Inc(Rows);
    for OIdx := 0 to High(Q.Objectives) do
    begin
      GridQuests.Cells[0, Rows] := '  - ' + Q.Objectives[OIdx].ObjectiveId;
      if Q.Objectives[OIdx].IsSatisfied then
        GridQuests.Cells[1, Rows] := 'Done'
      else
        GridQuests.Cells[1, Rows] := 'Open';
      GridQuests.Cells[2, Rows] := Format('%d / %d',
        [Q.Objectives[OIdx].CurrentCount, Q.Objectives[OIdx].RequiredCount]);
      Inc(Rows);
    end;
  end;
end;

procedure TDialogueQuestForm.RestartSimulator;
begin
  FSimAvailableChoices := nil;
  if (FCurrentDialogue <> nil) and (FCurrentDialogue.NodeCount > 0) then
    FSimActiveNodeId := FCurrentDialogue.EntryNodeId
  else
    FSimActiveNodeId := '';
  UpdateSimulatorPrompt;
end;

procedure TDialogueQuestForm.UpdateSimulatorPrompt;
var
  NIdx, I: Integer;
  N: TDialogueNodeDef;
begin
  ListSimChoices.Items.Clear;
  FSimAvailableChoices := nil;

  if FCurrentDialogue = nil then
  begin
    LblSimSpeaker.Caption := 'Simulator: (No Dialogue Tree yet — click "+ Sample RPG Dialogue + Quest")';
    MemoSimDialogue.Text := '';
    PaintGraph.Invalidate;
    Exit;
  end;

  if FSimActiveNodeId = '' then
  begin
    LblSimSpeaker.Caption := 'Simulator: [Conversation Ended]';
    MemoSimDialogue.Text := 'End of conversation reached. Click "Restart Sim" to replay.';
    PopulateQuestGrid;
    PaintGraph.Invalidate;
    Exit;
  end;

  NIdx := FCurrentDialogue.FindNodeIndex(FSimActiveNodeId);
  if NIdx < 0 then
  begin
    LblSimSpeaker.Caption := 'Simulator: [Missing Node "' + FSimActiveNodeId + '"]';
    MemoSimDialogue.Text := '';
    PaintGraph.Invalidate;
    Exit;
  end;

  N := FCurrentDialogue.GetNode(NIdx);
  LblSimSpeaker.Caption := Format('Speaker: %s  (Node: %s | Key: %s)',
    [N.SpeakerName, N.NodeId, N.LocalizationKey]);
  MemoSimDialogue.Text := N.DialogueText;

  FSimAvailableChoices := FCurrentDialogue.GetAvailableChoices(FSimActiveNodeId);
  for I := 0 to High(FSimAvailableChoices) do
    ListSimChoices.Items.Add(Format('%d. %s  -> [%s]',
      [I + 1, FSimAvailableChoices[I].ChoiceText,
       IfThen(FSimAvailableChoices[I].TargetNodeId = '', 'END',
              FSimAvailableChoices[I].TargetNodeId)]));
  if ListSimChoices.Items.Count > 0 then
    ListSimChoices.ItemIndex := 0;

  PopulateQuestGrid;
  PaintGraph.Invalidate;
end;

procedure TDialogueQuestForm.CmbDialoguesChange(Sender: TObject);
begin
  if CmbDialogues.ItemIndex >= 0 then
    FCurrentDialogue := TCastleDialogueTree(CmbDialogues.Items.Objects[CmbDialogues.ItemIndex])
  else
    FCurrentDialogue := nil;
  FSelectedNodeId := '';
  PopulateDialogueUi;
  RestartSimulator;
end;

procedure TDialogueQuestForm.ListNodesClick(Sender: TObject);
begin
  if (FCurrentDialogue <> nil) and (ListNodes.ItemIndex >= 0) and
     (ListNodes.ItemIndex < FCurrentDialogue.NodeCount) then
  begin
    FSelectedNodeId := FCurrentDialogue.GetNode(ListNodes.ItemIndex).NodeId;
    PaintGraph.Invalidate;
  end;
end;

procedure TDialogueQuestForm.BtnCreateSampleClick(Sender: TObject);
var
  NewDlg: TCastleDialogueTree;
begin
  NewDlg := TDialogueQuestHelper.CreateSampleRpgQuestDialogueRig(FDesignRoot, FDesignOwner);
  if NewDlg <> nil then
  begin
    MemoLog.Lines.Add('Created sample RPG Dialogue + Quest rig: ' + NewDlg.Name);
    NotifyModified('Create Sample RPG Dialogue & Quest Rig');
    RefreshHierarchy(NewDlg);
  end;
end;

procedure TDialogueQuestForm.BtnAddNodeClick(Sender: TObject);
var
  NodeId, Speaker, LineText: String;
begin
  if FCurrentDialogue = nil then
    Exit;
  NodeId := Format('Node_%d', [FCurrentDialogue.NodeCount + 1]);
  if not InputQuery('New Speaker Node', 'Node ID:', NodeId) then
    Exit;
  Speaker := FCurrentDialogue.DefaultSpeaker;
  if not InputQuery('New Speaker Node', 'Speaker Name:', Speaker) then
    Exit;
  LineText := 'What news from the frontier?';
  if not InputQuery('New Speaker Node', 'Dialogue Line:', LineText) then
    Exit;

  FCurrentDialogue.AddNode(NodeId, Speaker, LineText, '',
    80.0 + (FCurrentDialogue.NodeCount mod 3) * 240.0,
    60.0 + (FCurrentDialogue.NodeCount div 3) * 110.0);
  FSelectedNodeId := NodeId;
  NotifyModified('Add Dialogue Node ' + NodeId);
  PopulateDialogueUi;
end;

procedure TDialogueQuestForm.BtnAddChoiceClick(Sender: TObject);
var
  ChoiceText, TargetId: String;
begin
  if (FCurrentDialogue = nil) or (FSelectedNodeId = '') then
    Exit;
  ChoiceText := 'Tell me more.';
  if not InputQuery('Add Player Choice', 'Player Choice Text:', ChoiceText) then
    Exit;
  TargetId := 'END';
  if not InputQuery('Add Player Choice', 'Target Node ID (or END):', TargetId) then
    Exit;

  FCurrentDialogue.AddChoice(FSelectedNodeId, '', ChoiceText, TargetId);
  NotifyModified('Add Dialogue Choice on ' + FSelectedNodeId);
  PopulateDialogueUi;
  UpdateSimulatorPrompt;
end;

procedure TDialogueQuestForm.BtnGrantTagClick(Sender: TObject);
var
  TagStr: String;
begin
  if (FCurrentDialogue = nil) or (FCurrentDialogue.QuestTracker = nil) then
    Exit;
  TagStr := Trim(EditTagGrant.Text);
  if TagStr = '' then
    Exit;
  FCurrentDialogue.QuestTracker.GrantGameplayTag(TagStr);
  MemoLog.Lines.Add('Granted Gameplay Tag: ' + TagStr);
  NotifyModified('Grant Narrative Tag ' + TagStr);
  UpdateSimulatorPrompt;
end;

procedure TDialogueQuestForm.BtnValidateClick(Sender: TObject);
var
  Warns: TDialogueStringArray;
  I: Integer;
begin
  if FCurrentDialogue = nil then
    Exit;
  MemoLog.Lines.Clear;
  if FCurrentDialogue.ValidateGraph(Warns) then
    MemoLog.Lines.Add('[OK] Graph "' + FCurrentDialogue.Name + '" has 0 broken links or orphan nodes.')
  else
    for I := 0 to High(Warns) do
      MemoLog.Lines.Add('[!] ' + Warns[I]);
end;

procedure TDialogueQuestForm.BtnCopyLocCsvClick(Sender: TObject);
begin
  if FCurrentDialogue = nil then
    Exit;
  Clipboard.AsText := TDialogueQuestHelper.ExportLocalizationCsv(FCurrentDialogue);
  MemoLog.Lines.Add('Copied Localization CSV to clipboard.');
end;

procedure TDialogueQuestForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TDialogueQuestHelper.BuildMarkdownReport(FDesignRoot);
  MemoLog.Lines.Add('Copied Narrative Markdown Report to clipboard.');
end;

procedure TDialogueQuestForm.BtnSimRestartClick(Sender: TObject);
begin
  RestartSimulator;
end;

procedure TDialogueQuestForm.BtnSimChooseClick(Sender: TObject);
var
  NextId: String;
begin
  if (FCurrentDialogue = nil) or (ListSimChoices.ItemIndex < 0) then
    Exit;
  if FCurrentDialogue.StepConversation(FSimActiveNodeId,
       ListSimChoices.ItemIndex, NextId) then
  begin
    MemoLog.Lines.Add(Format('[Sim] %s -> %s',
      [FSimActiveNodeId, IfThen(NextId = '', 'END', NextId)]));
    FSimActiveNodeId := NextId;
    NotifyModified('Simulate Dialogue Step');
    UpdateSimulatorPrompt;
  end;
end;

procedure TDialogueQuestForm.ListSimChoicesDblClick(Sender: TObject);
begin
  BtnSimChooseClick(Sender);
end;

procedure TDialogueQuestForm.PaintGraphPaint(Sender: TObject);
var
  C: TCanvas;
  I, J, TgtIdx, X1, Y1, X2, Y2, NX, NY: Integer;
  N, TgtN: TDialogueNodeDef;
  Snippet: String;
begin
  C := PaintGraph.Canvas;
  C.Brush.Color := RGBToColor(24, 28, 34);
  C.FillRect(0, 0, PaintGraph.Width, PaintGraph.Height);

  if FCurrentDialogue = nil then
    Exit;

  { 1. Directed edges }
  for I := 0 to FCurrentDialogue.NodeCount - 1 do
  begin
    N := FCurrentDialogue.GetNode(I);
    X1 := Round(N.CanvasX) + GraphCardW;
    for J := 0 to High(N.Choices) do
    begin
      if (N.Choices[J].TargetNodeId = '') or
         SameText(N.Choices[J].TargetNodeId, 'END') then
        Continue;
      TgtIdx := FCurrentDialogue.FindNodeIndex(N.Choices[J].TargetNodeId);
      if TgtIdx < 0 then
        Continue;
      TgtN := FCurrentDialogue.GetNode(TgtIdx);
      Y1 := Round(N.CanvasY) + 34 + Min(34, J * 12);
      X2 := Round(TgtN.CanvasX);
      Y2 := Round(TgtN.CanvasY) + GraphCardH div 2;

      if N.Choices[J].ConditionOp <> dcoNone then
        C.Pen.Color := RGBToColor(245, 195, 70)
      else
        C.Pen.Color := RGBToColor(95, 180, 240);
      C.Pen.Width := 2;
      C.Line(X1, Y1, X2, Y2);
      C.Brush.Color := C.Pen.Color;
      C.Ellipse(X2 - 4, Y2 - 4, X2 + 4, Y2 + 4);
    end;
  end;

  { 2. Speaker node cards }
  for I := 0 to FCurrentDialogue.NodeCount - 1 do
  begin
    N := FCurrentDialogue.GetNode(I);
    NX := Round(N.CanvasX);
    NY := Round(N.CanvasY);

    C.Brush.Color := RGBToColor(38, 44, 54);
    if SameText(N.NodeId, FSimActiveNodeId) then
      C.Pen.Color := RGBToColor(65, 225, 255)
    else
    if SameText(N.NodeId, FSelectedNodeId) then
      C.Pen.Color := RGBToColor(255, 215, 80)
    else
      C.Pen.Color := RGBToColor(90, 100, 118);
    C.Pen.Width := 2;
    C.RoundRect(NX, NY, NX + GraphCardW, NY + GraphCardH, 8, 8);

    if SameText(N.NodeId, FCurrentDialogue.EntryNodeId) then
      C.Brush.Color := RGBToColor(40, 145, 92)
    else
      C.Brush.Color := RGBToColor(52, 82, 128);
    C.Pen.Style := psClear;
    C.Rectangle(NX + 2, NY + 2, NX + GraphCardW - 2, NY + 24);
    C.Pen.Style := psSolid;

    C.Brush.Style := bsClear;
    C.Font.Color := clWhite;
    C.Font.Style := [fsBold];
    C.TextOut(NX + 8, NY + 5, Format('%s — %s', [N.NodeId, N.SpeakerName]));

    C.Font.Style := [];
    C.Font.Color := RGBToColor(215, 222, 232);
    Snippet := Copy(N.DialogueText, 1, 28);
    if Length(N.DialogueText) > 28 then
      Snippet := Snippet + '...';
    C.TextOut(NX + 8, NY + 30, Snippet);

    C.Font.Color := RGBToColor(150, 210, 175);
    C.TextOut(NX + 8, NY + 52, Format('%d choice(s)', [Length(N.Choices)]));
    C.Brush.Style := bsSolid;
  end;
end;

procedure TDialogueQuestForm.PaintGraphMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I, NX, NY: Integer;
  N: TDialogueNodeDef;
begin
  if (Button <> mbLeft) or (FCurrentDialogue = nil) then
    Exit;
  for I := FCurrentDialogue.NodeCount - 1 downto 0 do
  begin
    N := FCurrentDialogue.GetNode(I);
    NX := Round(N.CanvasX);
    NY := Round(N.CanvasY);
    if (X >= NX) and (X <= NX + GraphCardW) and
       (Y >= NY) and (Y <= NY + GraphCardH) then
    begin
      FSelectedNodeId := N.NodeId;
      FDraggingNodeId := N.NodeId;
      FDragOffsetX := X - NX;
      FDragOffsetY := Y - NY;
      ListNodes.ItemIndex := I;
      PaintGraph.Invalidate;
      Exit;
    end;
  end;
end;

procedure TDialogueQuestForm.PaintGraphMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  if (FDraggingNodeId <> '') and (FCurrentDialogue <> nil) then
  begin
    FCurrentDialogue.SetNodeCanvasPos(FDraggingNodeId,
      Max(8.0, X - FDragOffsetX),
      Max(8.0, Y - FDragOffsetY));
    PaintGraph.Invalidate;
  end;
end;

procedure TDialogueQuestForm.PaintGraphMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingNodeId <> '' then
  begin
    FDraggingNodeId := '';
    NotifyModified('Move Dialogue Graph Node');
  end;
end;

procedure TDialogueQuestForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

end.
