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

{ Interactive Visual State Machine & StateTree Graph Studio
  (@link(TStateGraphForm)) for @link(TCastleStateGraphBehavior), featuring
  a 2D Bézier-wire state node canvas, live blackboard tester, gameplay
  templates, and reachability validator
  (Phase 288 — UE 5.9 / 6.0 StateTree Parity). }
unit FormStateGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Spin, Dialogs, Graphics, Clipbrd, Types,
  CastleVectors, CastleClassUtils, CastleUtils, CastleTransform,
  CastleStateGraph, ToolStateGraph;

type
  TStateGraphModifiedCallback = procedure (const UndoComment: String) of object;
  TStateGraphRefreshViewportCallback = procedure of object;

  TStateGraphForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FInitialSelected: TComponent;
    FOnModified: TStateGraphModifiedCallback;
    FOnRefreshViewport: TStateGraphRefreshViewportCallback;

    FGraphs: TStateGraphInfoArray;
    FSelectedStateId: String;
    FSelectedTransitionIdx: Integer;
    FDraggingStateId: String;
    FDragOffsetX, FDragOffsetY: Single;
    FDragMoved: Boolean;
    FSimTimer: TTimer;
    FLastCueLog: String;

    { Top bar }
    ComboGraph: TComboBox;
    ButtonAttachNew: TButton;
    ButtonTplAi: TButton;
    ButtonTplDoor: TButton;
    ButtonTplUi: TButton;
    ButtonValidate: TButton;
    ButtonCopyMarkdown: TButton;

    { Center 2D Bézier node canvas }
    PanelCanvasHost: TPanel;
    PaintBoxGraph: TPaintBox;
    LabelCanvasHint: TLabel;

    { Right authoring & live simulation panel }
    PanelRight: TPanel;
    PageControlRight: TPageControl;

    { Tab 1: Live Simulation & Blackboard }
    TabLiveSim: TTabSheet;
    LabelSimStatus: TLabel;
    ButtonSimPlayPause: TButton;
    ButtonSimStep: TButton;
    ButtonSimReset: TButton;
    ListBlackboard: TListBox;
    EditLiveVarValue: TEdit;
    ButtonApplyLiveVar: TButton;
    ButtonToggleBoolVar: TButton;
    EditNewVarName: TEdit;
    ComboNewVarKind: TComboBox;
    EditNewVarDefault: TEdit;
    ButtonAddVariable: TButton;
    ButtonDeleteVariable: TButton;

    { Tab 2: States & Actions }
    TabStates: TTabSheet;
    ListStates: TListBox;
    EditStateId: TEdit;
    EditStateTitle: TEdit;
    ButtonAddOrUpdateState: TButton;
    ButtonSetInitialState: TButton;
    ButtonForceEnterState: TButton;
    ButtonDeleteState: TButton;
    ComboActionKind: TComboBox;
    EditActionTarget: TEdit;
    EditActionKey: TEdit;
    EditActionVal: TEdit;
    ButtonAddEntryAction: TButton;
    ButtonClearStateActions: TButton;

    { Tab 3: Transitions }
    TabTransitions: TTabSheet;
    ListTransitions: TListBox;
    ComboFromState: TComboBox;
    ComboToState: TComboBox;
    ComboCondOp: TComboBox;
    ComboCondVar: TComboBox;
    EditCondVal: TEdit;
    SpinMinElapsed: TFloatSpinEdit;
    SpinPriority: TSpinEdit;
    ButtonAddTransition: TButton;
    ButtonDeleteTransition: TButton;

    { Bottom close }
    ButtonClose: TButton;

    procedure BuildUi;
    function ActiveGraph: TCastleStateGraphBehavior;
    procedure RefreshGraphList(const SelectGraph: TCastleStateGraphBehavior = nil);
    procedure RefreshAllViews;
    procedure UpdateSimStatusLabel;
    procedure NotifyModified(const Comment: String);
    procedure NotifyViewportRefresh;

    function HitTestStateAt(const X, Y: Integer): String;
    procedure DrawCubicWire(const C: TCanvas; const X1, Y1, X2, Y2: Integer;
      const WireColor: TColor; const LabelText: String; const Highlighted: Boolean);

    procedure ComboGraphChange(Sender: TObject);
    procedure ButtonAttachNewClick(Sender: TObject);
    procedure ButtonTplAiClick(Sender: TObject);
    procedure ButtonTplDoorClick(Sender: TObject);
    procedure ButtonTplUiClick(Sender: TObject);
    procedure ButtonValidateClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);

    procedure PaintBoxGraphPaint(Sender: TObject);
    procedure PaintBoxGraphMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxGraphMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure PaintBoxGraphMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxGraphDblClick(Sender: TObject);

    procedure SimTimerTick(Sender: TObject);
    procedure ButtonSimPlayPauseClick(Sender: TObject);
    procedure ButtonSimStepClick(Sender: TObject);
    procedure ButtonSimResetClick(Sender: TObject);
    procedure OnGraphCueFired(Sender: TObject; const CueName, Payload: String);

    procedure ListBlackboardSelectionChange(Sender: TObject; User: Boolean);
    procedure ButtonApplyLiveVarClick(Sender: TObject);
    procedure ButtonToggleBoolVarClick(Sender: TObject);
    procedure ButtonAddVariableClick(Sender: TObject);
    procedure ButtonDeleteVariableClick(Sender: TObject);

    procedure ListStatesSelectionChange(Sender: TObject; User: Boolean);
    procedure ButtonAddOrUpdateStateClick(Sender: TObject);
    procedure ButtonSetInitialStateClick(Sender: TObject);
    procedure ButtonForceEnterStateClick(Sender: TObject);
    procedure ButtonDeleteStateClick(Sender: TObject);
    procedure ButtonAddEntryActionClick(Sender: TObject);
    procedure ButtonClearStateActionsClick(Sender: TObject);

    procedure ListTransitionsSelectionChange(Sender: TObject; User: Boolean);
    procedure ButtonAddTransitionClick(Sender: TObject);
    procedure ButtonDeleteTransitionClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
      const AOnModified: TStateGraphModifiedCallback;
      const AOnRefreshViewport: TStateGraphRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

const
  StateBoxW = 164;
  StateBoxH = 66;
  AnyStateBoxX = 56;
  AnyStateBoxY = 24;
  AnyStateBoxW = 148;
  AnyStateBoxH = 40;

constructor TStateGraphForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
  const AOnModified: TStateGraphModifiedCallback;
  const AOnRefreshViewport: TStateGraphRefreshViewportCallback);
var
  InitGraph: TCastleStateGraphBehavior;
begin
  inherited CreateNew(AOwner, 1);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FInitialSelected := AInitialSelected;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FSelectedStateId := '';
  FSelectedTransitionIdx := -1;
  FDraggingStateId := '';

  FSimTimer := TTimer.Create(Self);
  FSimTimer.Interval := 33;
  FSimTimer.Enabled := false;
  FSimTimer.OnTimer := @SimTimerTick;

  BuildUi;

  InitGraph := nil;
  if AInitialSelected is TCastleStateGraphBehavior then
    InitGraph := TCastleStateGraphBehavior(AInitialSelected)
  else if AInitialSelected is TCastleTransform then
    InitGraph := TCastleTransform(AInitialSelected).FindBehavior(
      TCastleStateGraphBehavior) as TCastleStateGraphBehavior;

  RefreshGraphList(InitGraph);
end;

destructor TStateGraphForm.Destroy;
var
  G: TCastleStateGraphBehavior;
begin
  if FSimTimer <> nil then
    FSimTimer.Enabled := false;
  G := ActiveGraph;
  if (G <> nil) and (G.OnStateCue = @OnGraphCueFired) then
    G.OnStateCue := nil;
  inherited Destroy;
end;

procedure TStateGraphForm.BuildUi;
var
  PanelTop, PanelBottom, PanelCenterWrap, RowPanel: TPanel;
  Lbl: TLabel;
begin
  Caption := 'Visual State Machine & Behavior Graph Studio (StateTree)';
  Position := poScreenCenter;
  Width := 1180;
  Height := 720;
  Constraints.MinWidth := 980;
  Constraints.MinHeight := 600;

  { Top selector + templates bar }
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 44;
  PanelTop.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelTop;
  Lbl.Caption := 'StateGraph:';
  Lbl.Left := 10;
  Lbl.Top := 13;

  ComboGraph := TComboBox.Create(Self);
  ComboGraph.Parent := PanelTop;
  ComboGraph.Style := csDropDownList;
  ComboGraph.Left := 82;
  ComboGraph.Top := 9;
  ComboGraph.Width := 230;
  ComboGraph.OnChange := @ComboGraphChange;

  ButtonAttachNew := TButton.Create(Self);
  ButtonAttachNew.Parent := PanelTop;
  ButtonAttachNew.Caption := '+ Attach StateGraph';
  ButtonAttachNew.Left := 320;
  ButtonAttachNew.Top := 8;
  ButtonAttachNew.Width := 136;
  ButtonAttachNew.Height := 28;
  ButtonAttachNew.OnClick := @ButtonAttachNewClick;

  ButtonTplAi := TButton.Create(Self);
  ButtonTplAi.Parent := PanelTop;
  ButtonTplAi.Caption := 'Tpl: AI Patrol/Attack';
  ButtonTplAi.Left := 464;
  ButtonTplAi.Top := 8;
  ButtonTplAi.Width := 142;
  ButtonTplAi.Height := 28;
  ButtonTplAi.OnClick := @ButtonTplAiClick;

  ButtonTplDoor := TButton.Create(Self);
  ButtonTplDoor.Parent := PanelTop;
  ButtonTplDoor.Caption := 'Tpl: Door';
  ButtonTplDoor.Left := 612;
  ButtonTplDoor.Top := 8;
  ButtonTplDoor.Width := 86;
  ButtonTplDoor.Height := 28;
  ButtonTplDoor.OnClick := @ButtonTplDoorClick;

  ButtonTplUi := TButton.Create(Self);
  ButtonTplUi.Parent := PanelTop;
  ButtonTplUi.Caption := 'Tpl: UI Flow';
  ButtonTplUi.Left := 704;
  ButtonTplUi.Top := 8;
  ButtonTplUi.Width := 94;
  ButtonTplUi.Height := 28;
  ButtonTplUi.OnClick := @ButtonTplUiClick;

  ButtonValidate := TButton.Create(Self);
  ButtonValidate.Parent := PanelTop;
  ButtonValidate.Caption := 'Validate';
  ButtonValidate.Left := 806;
  ButtonValidate.Top := 8;
  ButtonValidate.Width := 82;
  ButtonValidate.Height := 28;
  ButtonValidate.OnClick := @ButtonValidateClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.Caption := 'Copy Mermaid / MD';
  ButtonCopyMarkdown.Left := 894;
  ButtonCopyMarkdown.Top := 8;
  ButtonCopyMarkdown.Width := 136;
  ButtonCopyMarkdown.Height := 28;
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  { Bottom bar }
  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 40;
  PanelBottom.BevelOuter := bvNone;

  LabelCanvasHint := TLabel.Create(Self);
  LabelCanvasHint.Parent := PanelBottom;
  LabelCanvasHint.Left := 12;
  LabelCanvasHint.Top := 12;
  LabelCanvasHint.Caption :=
    'Drag state nodes to arrange on canvas | Double-click a state node to force-enter it live | Emerald border = Active State';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Caption := 'Close';
  ButtonClose.Anchors := [akTop, akRight];
  ButtonClose.Left := Width - 102;
  ButtonClose.Top := 6;
  ButtonClose.Width := 88;
  ButtonClose.Height := 28;
  ButtonClose.OnClick := @ButtonCloseClick;

  { Right panel }
  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := Self;
  PanelRight.Align := alRight;
  PanelRight.Width := 386;
  PanelRight.BevelOuter := bvNone;
  PanelRight.BorderSpacing.Around := 4;

  PageControlRight := TPageControl.Create(Self);
  PageControlRight.Parent := PanelRight;
  PageControlRight.Align := alClient;

  { --- Tab 1: Live Sim & Blackboard --- }
  TabLiveSim := TTabSheet.Create(PageControlRight);
  TabLiveSim.PageControl := PageControlRight;
  TabLiveSim.Caption := 'Live Sim & Blackboard';

  LabelSimStatus := TLabel.Create(Self);
  LabelSimStatus.Parent := TabLiveSim;
  LabelSimStatus.Align := alTop;
  LabelSimStatus.BorderSpacing.Around := 6;
  LabelSimStatus.Font.Style := [Graphics.fsBold];
  LabelSimStatus.Caption := 'Active: <none> | Elapsed: 0.00s';

  RowPanel := TPanel.Create(Self);
  RowPanel.Parent := TabLiveSim;
  RowPanel.Align := alTop;
  RowPanel.Height := 34;
  RowPanel.BevelOuter := bvNone;

  ButtonSimPlayPause := TButton.Create(Self);
  ButtonSimPlayPause.Parent := RowPanel;
  ButtonSimPlayPause.Caption := 'Start Live Sim';
  ButtonSimPlayPause.Left := 6;
  ButtonSimPlayPause.Top := 2;
  ButtonSimPlayPause.Width := 118;
  ButtonSimPlayPause.Height := 28;
  ButtonSimPlayPause.OnClick := @ButtonSimPlayPauseClick;

  ButtonSimStep := TButton.Create(Self);
  ButtonSimStep.Parent := RowPanel;
  ButtonSimStep.Caption := 'Step +0.5s';
  ButtonSimStep.Left := 130;
  ButtonSimStep.Top := 2;
  ButtonSimStep.Width := 96;
  ButtonSimStep.Height := 28;
  ButtonSimStep.OnClick := @ButtonSimStepClick;

  ButtonSimReset := TButton.Create(Self);
  ButtonSimReset.Parent := RowPanel;
  ButtonSimReset.Caption := 'Reset';
  ButtonSimReset.Left := 232;
  ButtonSimReset.Top := 2;
  ButtonSimReset.Width := 80;
  ButtonSimReset.Height := 28;
  ButtonSimReset.OnClick := @ButtonSimResetClick;

  ListBlackboard := TListBox.Create(Self);
  ListBlackboard.Parent := TabLiveSim;
  ListBlackboard.Align := alTop;
  ListBlackboard.Height := 180;
  ListBlackboard.BorderSpacing.Around := 6;
  ListBlackboard.OnSelectionChange := @ListBlackboardSelectionChange;

  RowPanel := TPanel.Create(Self);
  RowPanel.Parent := TabLiveSim;
  RowPanel.Align := alTop;
  RowPanel.Height := 72;
  RowPanel.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RowPanel;
  Lbl.Caption := 'Live Value:';
  Lbl.Left := 6;
  Lbl.Top := 8;

  EditLiveVarValue := TEdit.Create(Self);
  EditLiveVarValue.Parent := RowPanel;
  EditLiveVarValue.Left := 78;
  EditLiveVarValue.Top := 4;
  EditLiveVarValue.Width := 130;

  ButtonApplyLiveVar := TButton.Create(Self);
  ButtonApplyLiveVar.Parent := RowPanel;
  ButtonApplyLiveVar.Caption := 'Set Live';
  ButtonApplyLiveVar.Left := 214;
  ButtonApplyLiveVar.Top := 3;
  ButtonApplyLiveVar.Width := 74;
  ButtonApplyLiveVar.Height := 26;
  ButtonApplyLiveVar.OnClick := @ButtonApplyLiveVarClick;

  ButtonToggleBoolVar := TButton.Create(Self);
  ButtonToggleBoolVar.Parent := RowPanel;
  ButtonToggleBoolVar.Caption := 'Flip Bool';
  ButtonToggleBoolVar.Left := 292;
  ButtonToggleBoolVar.Top := 3;
  ButtonToggleBoolVar.Width := 74;
  ButtonToggleBoolVar.Height := 26;
  ButtonToggleBoolVar.OnClick := @ButtonToggleBoolVarClick;

  ButtonDeleteVariable := TButton.Create(Self);
  ButtonDeleteVariable.Parent := RowPanel;
  ButtonDeleteVariable.Caption := '- Delete Selected Variable';
  ButtonDeleteVariable.Left := 6;
  ButtonDeleteVariable.Top := 38;
  ButtonDeleteVariable.Width := 180;
  ButtonDeleteVariable.Height := 26;
  ButtonDeleteVariable.OnClick := @ButtonDeleteVariableClick;

  RowPanel := TPanel.Create(Self);
  RowPanel.Parent := TabLiveSim;
  RowPanel.Align := alClient;
  RowPanel.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RowPanel;
  Lbl.Caption := 'Add / Update Blackboard Variable:';
  Lbl.Font.Style := [Graphics.fsBold];
  Lbl.Left := 6;
  Lbl.Top := 6;

  EditNewVarName := TEdit.Create(Self);
  EditNewVarName.Parent := RowPanel;
  EditNewVarName.TextHint := 'VarName';
  EditNewVarName.Left := 6;
  EditNewVarName.Top := 28;
  EditNewVarName.Width := 118;

  ComboNewVarKind := TComboBox.Create(Self);
  ComboNewVarKind.Parent := RowPanel;
  ComboNewVarKind.Style := csDropDownList;
  ComboNewVarKind.Items.Add('float');
  ComboNewVarKind.Items.Add('int');
  ComboNewVarKind.Items.Add('bool');
  ComboNewVarKind.Items.Add('string');
  ComboNewVarKind.ItemIndex := 0;
  ComboNewVarKind.Left := 130;
  ComboNewVarKind.Top := 28;
  ComboNewVarKind.Width := 76;

  EditNewVarDefault := TEdit.Create(Self);
  EditNewVarDefault.Parent := RowPanel;
  EditNewVarDefault.Text := '0.0';
  EditNewVarDefault.Left := 212;
  EditNewVarDefault.Top := 28;
  EditNewVarDefault.Width := 76;

  ButtonAddVariable := TButton.Create(Self);
  ButtonAddVariable.Parent := RowPanel;
  ButtonAddVariable.Caption := '+ Add';
  ButtonAddVariable.Left := 294;
  ButtonAddVariable.Top := 27;
  ButtonAddVariable.Width := 72;
  ButtonAddVariable.Height := 26;
  ButtonAddVariable.OnClick := @ButtonAddVariableClick;

  { --- Tab 2: States & Actions --- }
  TabStates := TTabSheet.Create(PageControlRight);
  TabStates.PageControl := PageControlRight;
  TabStates.Caption := 'States & Actions';

  ListStates := TListBox.Create(Self);
  ListStates.Parent := TabStates;
  ListStates.Align := alTop;
  ListStates.Height := 170;
  ListStates.BorderSpacing.Around := 6;
  ListStates.OnSelectionChange := @ListStatesSelectionChange;

  RowPanel := TPanel.Create(Self);
  RowPanel.Parent := TabStates;
  RowPanel.Align := alClient;
  RowPanel.BevelOuter := bvNone;

  EditStateId := TEdit.Create(Self);
  EditStateId.Parent := RowPanel;
  EditStateId.TextHint := 'StateId (e.g. Patrol)';
  EditStateId.Left := 6;
  EditStateId.Top := 6;
  EditStateId.Width := 140;

  EditStateTitle := TEdit.Create(Self);
  EditStateTitle.Parent := RowPanel;
  EditStateTitle.TextHint := 'Display Title';
  EditStateTitle.Left := 152;
  EditStateTitle.Top := 6;
  EditStateTitle.Width := 212;

  ButtonAddOrUpdateState := TButton.Create(Self);
  ButtonAddOrUpdateState.Parent := RowPanel;
  ButtonAddOrUpdateState.Caption := '+ Add / Update';
  ButtonAddOrUpdateState.Left := 6;
  ButtonAddOrUpdateState.Top := 36;
  ButtonAddOrUpdateState.Width := 112;
  ButtonAddOrUpdateState.Height := 26;
  ButtonAddOrUpdateState.OnClick := @ButtonAddOrUpdateStateClick;

  ButtonSetInitialState := TButton.Create(Self);
  ButtonSetInitialState.Parent := RowPanel;
  ButtonSetInitialState.Caption := 'Set [INIT]';
  ButtonSetInitialState.Left := 122;
  ButtonSetInitialState.Top := 36;
  ButtonSetInitialState.Width := 82;
  ButtonSetInitialState.Height := 26;
  ButtonSetInitialState.OnClick := @ButtonSetInitialStateClick;

  ButtonForceEnterState := TButton.Create(Self);
  ButtonForceEnterState.Parent := RowPanel;
  ButtonForceEnterState.Caption := 'Enter Now';
  ButtonForceEnterState.Left := 208;
  ButtonForceEnterState.Top := 36;
  ButtonForceEnterState.Width := 80;
  ButtonForceEnterState.Height := 26;
  ButtonForceEnterState.OnClick := @ButtonForceEnterStateClick;

  ButtonDeleteState := TButton.Create(Self);
  ButtonDeleteState.Parent := RowPanel;
  ButtonDeleteState.Caption := '- Del';
  ButtonDeleteState.Left := 292;
  ButtonDeleteState.Top := 36;
  ButtonDeleteState.Width := 72;
  ButtonDeleteState.Height := 26;
  ButtonDeleteState.OnClick := @ButtonDeleteStateClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RowPanel;
  Lbl.Caption := 'Add Entry Action to Selected State:';
  Lbl.Font.Style := [Graphics.fsBold];
  Lbl.Left := 6;
  Lbl.Top := 74;

  ComboActionKind := TComboBox.Create(Self);
  ComboActionKind.Parent := RowPanel;
  ComboActionKind.Style := csDropDownList;
  ComboActionKind.Items.Add('Set Property');
  ComboActionKind.Items.Add('Set Blackboard Var');
  ComboActionKind.Items.Add('Play Animation');
  ComboActionKind.Items.Add('Fire Cue Event');
  ComboActionKind.ItemIndex := 2;
  ComboActionKind.Left := 6;
  ComboActionKind.Top := 96;
  ComboActionKind.Width := 156;

  EditActionTarget := TEdit.Create(Self);
  EditActionTarget.Parent := RowPanel;
  EditActionTarget.Text := '$Parent';
  EditActionTarget.TextHint := 'Target ($Parent or Name)';
  EditActionTarget.Left := 168;
  EditActionTarget.Top := 96;
  EditActionTarget.Width := 196;

  EditActionKey := TEdit.Create(Self);
  EditActionKey.Parent := RowPanel;
  EditActionKey.Text := 'walk';
  EditActionKey.TextHint := 'Prop / Anim / Var / Cue';
  EditActionKey.Left := 6;
  EditActionKey.Top := 126;
  EditActionKey.Width := 178;

  EditActionVal := TEdit.Create(Self);
  EditActionVal.Parent := RowPanel;
  EditActionVal.TextHint := 'Value / Payload';
  EditActionVal.Left := 190;
  EditActionVal.Top := 126;
  EditActionVal.Width := 174;

  ButtonAddEntryAction := TButton.Create(Self);
  ButtonAddEntryAction.Parent := RowPanel;
  ButtonAddEntryAction.Caption := '+ Add Entry Action';
  ButtonAddEntryAction.Left := 6;
  ButtonAddEntryAction.Top := 158;
  ButtonAddEntryAction.Width := 156;
  ButtonAddEntryAction.Height := 26;
  ButtonAddEntryAction.OnClick := @ButtonAddEntryActionClick;

  ButtonClearStateActions := TButton.Create(Self);
  ButtonClearStateActions.Parent := RowPanel;
  ButtonClearStateActions.Caption := 'Clear Actions';
  ButtonClearStateActions.Left := 168;
  ButtonClearStateActions.Top := 158;
  ButtonClearStateActions.Width := 120;
  ButtonClearStateActions.Height := 26;
  ButtonClearStateActions.OnClick := @ButtonClearStateActionsClick;

  { --- Tab 3: Transitions --- }
  TabTransitions := TTabSheet.Create(PageControlRight);
  TabTransitions.PageControl := PageControlRight;
  TabTransitions.Caption := 'Transitions';

  ListTransitions := TListBox.Create(Self);
  ListTransitions.Parent := TabTransitions;
  ListTransitions.Align := alTop;
  ListTransitions.Height := 180;
  ListTransitions.BorderSpacing.Around := 6;
  ListTransitions.OnSelectionChange := @ListTransitionsSelectionChange;

  RowPanel := TPanel.Create(Self);
  RowPanel.Parent := TabTransitions;
  RowPanel.Align := alClient;
  RowPanel.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RowPanel;
  Lbl.Caption := 'From -> To:';
  Lbl.Left := 6;
  Lbl.Top := 8;

  ComboFromState := TComboBox.Create(Self);
  ComboFromState.Parent := RowPanel;
  ComboFromState.Left := 82;
  ComboFromState.Top := 4;
  ComboFromState.Width := 134;

  ComboToState := TComboBox.Create(Self);
  ComboToState.Parent := RowPanel;
  ComboToState.Left := 224;
  ComboToState.Top := 4;
  ComboToState.Width := 140;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RowPanel;
  Lbl.Caption := 'Condition:';
  Lbl.Left := 6;
  Lbl.Top := 40;

  ComboCondVar := TComboBox.Create(Self);
  ComboCondVar.Parent := RowPanel;
  ComboCondVar.Left := 82;
  ComboCondVar.Top := 36;
  ComboCondVar.Width := 120;

  ComboCondOp := TComboBox.Create(Self);
  ComboCondOp.Parent := RowPanel;
  ComboCondOp.Style := csDropDownList;
  ComboCondOp.Items.Add('Always');
  ComboCondOp.Items.Add('==');
  ComboCondOp.Items.Add('!=');
  ComboCondOp.Items.Add('<');
  ComboCondOp.Items.Add('<=');
  ComboCondOp.Items.Add('>');
  ComboCondOp.Items.Add('>=');
  ComboCondOp.ItemIndex := 0;
  ComboCondOp.Left := 206;
  ComboCondOp.Top := 36;
  ComboCondOp.Width := 76;

  EditCondVal := TEdit.Create(Self);
  EditCondVal.Parent := RowPanel;
  EditCondVal.TextHint := 'Value';
  EditCondVal.Left := 286;
  EditCondVal.Top := 36;
  EditCondVal.Width := 78;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RowPanel;
  Lbl.Caption := 'Min Sec:';
  Lbl.Left := 6;
  Lbl.Top := 72;

  SpinMinElapsed := TFloatSpinEdit.Create(Self);
  SpinMinElapsed.Parent := RowPanel;
  SpinMinElapsed.DecimalPlaces := 2;
  SpinMinElapsed.MinValue := 0.0;
  SpinMinElapsed.MaxValue := 600.0;
  SpinMinElapsed.Increment := 0.25;
  SpinMinElapsed.Left := 82;
  SpinMinElapsed.Top := 68;
  SpinMinElapsed.Width := 92;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RowPanel;
  Lbl.Caption := 'Priority:';
  Lbl.Left := 184;
  Lbl.Top := 72;

  SpinPriority := TSpinEdit.Create(Self);
  SpinPriority.Parent := RowPanel;
  SpinPriority.MinValue := -100;
  SpinPriority.MaxValue := 100;
  SpinPriority.Left := 242;
  SpinPriority.Top := 68;
  SpinPriority.Width := 76;

  ButtonAddTransition := TButton.Create(Self);
  ButtonAddTransition.Parent := RowPanel;
  ButtonAddTransition.Caption := '+ Add Transition';
  ButtonAddTransition.Left := 6;
  ButtonAddTransition.Top := 104;
  ButtonAddTransition.Width := 160;
  ButtonAddTransition.Height := 28;
  ButtonAddTransition.OnClick := @ButtonAddTransitionClick;

  ButtonDeleteTransition := TButton.Create(Self);
  ButtonDeleteTransition.Parent := RowPanel;
  ButtonDeleteTransition.Caption := '- Delete Transition';
  ButtonDeleteTransition.Left := 176;
  ButtonDeleteTransition.Top := 104;
  ButtonDeleteTransition.Width := 156;
  ButtonDeleteTransition.Height := 28;
  ButtonDeleteTransition.OnClick := @ButtonDeleteTransitionClick;

  { Center 2D canvas }
  PanelCenterWrap := TPanel.Create(Self);
  PanelCenterWrap.Parent := Self;
  PanelCenterWrap.Align := alClient;
  PanelCenterWrap.BevelOuter := bvLowered;
  PanelCenterWrap.BorderSpacing.Around := 4;

  PanelCanvasHost := PanelCenterWrap;
  PaintBoxGraph := TPaintBox.Create(Self);
  PaintBoxGraph.Parent := PanelCanvasHost;
  PaintBoxGraph.Align := alClient;
  PaintBoxGraph.OnPaint := @PaintBoxGraphPaint;
  PaintBoxGraph.OnMouseDown := @PaintBoxGraphMouseDown;
  PaintBoxGraph.OnMouseMove := @PaintBoxGraphMouseMove;
  PaintBoxGraph.OnMouseUp := @PaintBoxGraphMouseUp;
  PaintBoxGraph.OnDblClick := @PaintBoxGraphDblClick;
end;

function TStateGraphForm.ActiveGraph: TCastleStateGraphBehavior;
var
  Idx: Integer;
begin
  Idx := ComboGraph.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FGraphs)) then
    Result := FGraphs[Idx].Graph
  else
    Result := nil;
end;

procedure TStateGraphForm.RefreshGraphList(const SelectGraph: TCastleStateGraphBehavior);
var
  I, SelIdx: Integer;
  G: TCastleStateGraphBehavior;
begin
  FGraphs := TStateGraphHelper.ScanStateGraphs(FRootComponent);
  ComboGraph.Items.BeginUpdate;
  try
    ComboGraph.Items.Clear;
    SelIdx := -1;
    for I := 0 to High(FGraphs) do
    begin
      ComboGraph.Items.Add(Format('%s on %s (%s)',
        [FGraphs[I].BehaviorName, FGraphs[I].ParentTransformName, FGraphs[I].GraphLabel]));
      if FGraphs[I].Graph = SelectGraph then
        SelIdx := I;
    end;
    if (SelIdx < 0) and (Length(FGraphs) > 0) then
      SelIdx := 0;
    ComboGraph.ItemIndex := SelIdx;
  finally
    ComboGraph.Items.EndUpdate;
  end;

  G := ActiveGraph;
  if G <> nil then
    G.OnStateCue := @OnGraphCueFired;
  RefreshAllViews;
end;

procedure TStateGraphForm.RefreshAllViews;
var
  G: TCastleStateGraphBehavior;
  I: Integer;
  V: TStateBlackboardVarData;
  S: TStateNodeData;
  T: TStateTransitionData;
  InitTag: String;
begin
  G := ActiveGraph;

  ListBlackboard.Items.BeginUpdate;
  ComboCondVar.Items.BeginUpdate;
  try
    ListBlackboard.Items.Clear;
    ComboCondVar.Items.Clear;
    if G <> nil then
      for I := 0 to G.VariableCount - 1 do
      begin
        V := G.GetVariable(I);
        ListBlackboard.Items.Add(Format('%s [%s] = %s (def: %s)',
          [V.VarName, StateVarKindToString(V.Kind),
           G.FormatBlackboardValue(V.VarName), V.DefaultStr]));
        ComboCondVar.Items.Add(V.VarName);
      end;
  finally
    ComboCondVar.Items.EndUpdate;
    ListBlackboard.Items.EndUpdate;
  end;

  ListStates.Items.BeginUpdate;
  ComboFromState.Items.BeginUpdate;
  ComboToState.Items.BeginUpdate;
  try
    ListStates.Items.Clear;
    ComboFromState.Items.Clear;
    ComboToState.Items.Clear;
    ComboFromState.Items.Add('*');
    if G <> nil then
      for I := 0 to G.StateCount - 1 do
      begin
        S := G.GetState(I);
        if SameText(S.StateId, G.InitialStateId) then
          InitTag := ' [INIT]'
        else
          InitTag := '';
        ListStates.Items.Add(Format('%s (%s)%s  [%d entry / %d exit]',
          [S.StateId, S.DisplayName, InitTag,
           Length(S.EntryActions), Length(S.ExitActions)]));
        ComboFromState.Items.Add(S.StateId);
        ComboToState.Items.Add(S.StateId);
      end;
    if (ComboFromState.ItemIndex < 0) and (ComboFromState.Items.Count > 0) then
      ComboFromState.ItemIndex := Min(1, ComboFromState.Items.Count - 1);
    if (ComboToState.ItemIndex < 0) and (ComboToState.Items.Count > 0) then
      ComboToState.ItemIndex := 0;
  finally
    ComboToState.Items.EndUpdate;
    ComboFromState.Items.EndUpdate;
    ListStates.Items.EndUpdate;
  end;

  ListTransitions.Items.BeginUpdate;
  try
    ListTransitions.Items.Clear;
    if G <> nil then
      for I := 0 to G.TransitionCount - 1 do
      begin
        T := G.GetTransition(I);
        ListTransitions.Items.Add(Format('%s -> %s : %s',
          [T.FromStateId, T.ToStateId, FormatTransitionSummary(T)]));
      end;
  finally
    ListTransitions.Items.EndUpdate;
  end;

  UpdateSimStatusLabel;
  PaintBoxGraph.Invalidate;
end;

procedure TStateGraphForm.UpdateSimStatusLabel;
var
  G: TCastleStateGraphBehavior;
  ActStr, CueSuffix: String;
begin
  G := ActiveGraph;
  if G = nil then
  begin
    LabelSimStatus.Caption := 'No TCastleStateGraphBehavior in design (click "+ Attach StateGraph")';
    Exit;
  end;
  if G.ActiveStateId <> '' then
    ActStr := G.ActiveStateId
  else
    ActStr := '<idle>';
  if FLastCueLog <> '' then
    CueSuffix := ' | Cue: ' + FLastCueLog
  else
    CueSuffix := '';
  LabelSimStatus.Caption := Format('Active: %s (%.2fs) | Hops: %d%s',
    [ActStr, G.ActiveStateElapsed, G.TotalTransitionCount, CueSuffix]);
end;

procedure TStateGraphForm.NotifyModified(const Comment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(Comment);
  NotifyViewportRefresh;
end;

procedure TStateGraphForm.NotifyViewportRefresh;
begin
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport;
end;

procedure TStateGraphForm.DrawCubicWire(const C: TCanvas;
  const X1, Y1, X2, Y2: Integer; const WireColor: TColor;
  const LabelText: String; const Highlighted: Boolean);
const
  Segs = 20;
var
  I: Integer;
  T, U, CX1, CY1, CX2, CY2, PX, PY, PrevX, PrevY, MidX, MidY: Single;
  DX, DY, Len, UX, UY, NX, NY: Single;
  ArrowPts: array [0..2] of TPoint;
  Tw, Th: Integer;
begin
  DX := Abs(X2 - X1);
  CX1 := X1 + Max(44.0, DX * 0.42);
  CY1 := Y1;
  CX2 := X2 - Max(44.0, DX * 0.42);
  CY2 := Y2;

  C.Pen.Color := WireColor;
  C.Pen.Width := IfThen(Highlighted, 3, 2);

  PrevX := X1;
  PrevY := Y1;
  MidX := (X1 + X2) * 0.5;
  MidY := (Y1 + Y2) * 0.5;

  for I := 1 to Segs do
  begin
    T := I / Segs;
    U := 1.0 - T;
    PX := (U * U * U) * X1 + 3 * (U * U * T) * CX1 +
          3 * (U * T * T) * CX2 + (T * T * T) * X2;
    PY := (U * U * U) * Y1 + 3 * (U * U * T) * CY1 +
          3 * (U * T * T) * CY2 + (T * T * T) * Y2;
    C.Line(Round(PrevX), Round(PrevY), Round(PX), Round(PY));
    if I = Segs div 2 then
    begin
      MidX := PX;
      MidY := PY;
    end;
    PrevX := PX;
    PrevY := PY;
  end;

  { Arrowhead at destination }
  DX := X2 - CX2;
  DY := Y2 - CY2;
  Len := Sqrt(DX * DX + DY * DY);
  if Len < 0.001 then
  begin
    DX := 1.0;
    DY := 0.0;
    Len := 1.0;
  end;
  UX := DX / Len;
  UY := DY / Len;
  NX := -UY;
  NY := UX;

  ArrowPts[0] := Point(X2, Y2);
  ArrowPts[1] := Point(Round(X2 - UX * 10 + NX * 5), Round(Y2 - UY * 10 + NY * 5));
  ArrowPts[2] := Point(Round(X2 - UX * 10 - NX * 5), Round(Y2 - UY * 10 - NY * 5));
  C.Brush.Style := bsSolid;
  C.Brush.Color := WireColor;
  C.Polygon(ArrowPts);
  C.Pen.Width := 1;

  if LabelText <> '' then
  begin
    C.Font.Size := 8;
    Tw := C.TextWidth(LabelText);
    Th := C.TextHeight(LabelText);
    C.Brush.Color := $241F1C;
    C.Pen.Color := WireColor;
    C.RoundRect(Round(MidX) - Tw div 2 - 5, Round(MidY) - Th div 2 - 3,
      Round(MidX) + Tw div 2 + 5, Round(MidY) + Th div 2 + 3, 6, 6);
    C.Brush.Style := bsClear;
    C.Font.Color := $F0EAE4;
    C.TextOut(Round(MidX) - Tw div 2, Round(MidY) - Th div 2, LabelText);
  end;
end;

procedure TStateGraphForm.PaintBoxGraphPaint(Sender: TObject);
const
  GridStep = 28;
var
  C: TCanvas;
  G: TCastleStateGraphBehavior;
  W, H, X, Y, I, SrcIdx, DstIdx: Integer;
  X1, Y1, X2, Y2, BoxX, BoxY: Integer;
  HasWildcard, IsActive, IsSelected, IsInit: Boolean;
  S, SrcS, DstS: TStateNodeData;
  T: TStateTransitionData;
  WireCol, BorderCol, HeaderCol: TColor;
  SubText: String;
begin
  C := PaintBoxGraph.Canvas;
  W := PaintBoxGraph.Width;
  H := PaintBoxGraph.Height;

  { Dark UE StateTree slate canvas + subtle grid }
  C.Brush.Style := bsSolid;
  C.Brush.Color := $1E1B18;
  C.FillRect(0, 0, W, H);

  C.Pen.Color := $2A2622;
  C.Pen.Width := 1;
  X := 0;
  while X < W do
  begin
    C.Line(X, 0, X, H);
    Inc(X, GridStep);
  end;
  Y := 0;
  while Y < H do
  begin
    C.Line(0, Y, W, Y);
    Inc(Y, GridStep);
  end;

  G := ActiveGraph;
  if (G = nil) or (G.StateCount = 0) then
  begin
    C.Brush.Style := bsClear;
    C.Font.Color := $A8A098;
    C.Font.Size := 10;
    C.TextOut(28, 28,
      'Click "+ Attach StateGraph" and choose a template (AI Patrol/Attack, Door, or UI Flow) to populate the canvas.');
    Exit;
  end;

  HasWildcard := false;
  for I := 0 to G.TransitionCount - 1 do
    if G.GetTransition(I).FromStateId = '*' then
      HasWildcard := true;

  { 1. Draw Bézier transition wires }
  for I := 0 to G.TransitionCount - 1 do
  begin
    T := G.GetTransition(I);
    DstIdx := G.FindStateIndex(T.ToStateId);
    if DstIdx < 0 then
      Continue;
    DstS := G.GetState(DstIdx);
    X2 := Round(DstS.CanvasX);
    Y2 := Round(DstS.CanvasY) + StateBoxH div 2 + ((I mod 3) - 1) * 8;

    if T.FromStateId = '*' then
    begin
      X1 := AnyStateBoxX + AnyStateBoxW;
      Y1 := AnyStateBoxY + AnyStateBoxH div 2;
      WireCol := $48A8F8; // Amber/Orange Any-State interrupt
    end else
    begin
      SrcIdx := G.FindStateIndex(T.FromStateId);
      if SrcIdx < 0 then
        Continue;
      SrcS := G.GetState(SrcIdx);
      X1 := Round(SrcS.CanvasX) + StateBoxW;
      Y1 := Round(SrcS.CanvasY) + StateBoxH div 2 + ((I mod 3) - 1) * 8;
      if SameText(G.ActiveStateId, T.FromStateId) and
         G.EvaluateTransitionCondition(T) then
        WireCol := $78E048
      else
        WireCol := $B89868;
    end;

    if I = FSelectedTransitionIdx then
      WireCol := $50E8FF;

    DrawCubicWire(C, X1, Y1, X2, Y2, WireCol,
      FormatTransitionSummary(T), I = FSelectedTransitionIdx);
  end;

  { 2. Draw Any-State (*) hub node if present }
  if HasWildcard then
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := $22344E;
    C.Pen.Color := $48A8F8;
    C.Pen.Width := 2;
    C.RoundRect(AnyStateBoxX, AnyStateBoxY,
      AnyStateBoxX + AnyStateBoxW, AnyStateBoxY + AnyStateBoxH, 10, 10);
    C.Brush.Style := bsClear;
    C.Font.Style := [Graphics.fsBold];
    C.Font.Size := 9;
    C.Font.Color := $88D0FF;
    C.TextOut(AnyStateBoxX + 14, AnyStateBoxY + 11, '* Any State Interrupt');
    C.Pen.Width := 1;
  end;

  { 3. Draw State Nodes }
  for I := 0 to G.StateCount - 1 do
  begin
    S := G.GetState(I);
    BoxX := Round(S.CanvasX);
    BoxY := Round(S.CanvasY);
    IsActive := SameText(S.StateId, G.ActiveStateId);
    IsSelected := SameText(S.StateId, FSelectedStateId);
    IsInit := SameText(S.StateId, G.InitialStateId);

    if IsActive then
    begin
      BorderCol := $68E040; // Emerald active state
      HeaderCol := $285824;
    end else
    if IsSelected then
    begin
      BorderCol := $58D8FF; // Gold/Cyan selected
      HeaderCol := $483A28;
    end else
    if IsInit then
    begin
      BorderCol := $E8A848; // Sky-blue Initial state
      HeaderCol := $443422;
    end else
    begin
      BorderCol := $6A625A;
      HeaderCol := $342F2B;
    end;

    C.Brush.Style := bsSolid;
    C.Brush.Color := $2B2724;
    C.Pen.Color := BorderCol;
    C.Pen.Width := IfThen(IsActive or IsSelected, 3, 1);
    C.RoundRect(BoxX, BoxY, BoxX + StateBoxW, BoxY + StateBoxH, 10, 10);

    C.Brush.Color := HeaderCol;
    C.Pen.Style := psClear;
    C.RoundRect(BoxX + 2, BoxY + 2, BoxX + StateBoxW - 2, BoxY + 26, 8, 8);
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;

    C.Brush.Style := bsClear;
    C.Font.Style := [Graphics.fsBold];
    C.Font.Size := 9;
    C.Font.Color := $FAF6F2;
    SubText := S.DisplayName;
    if IsInit then
      SubText := '[INIT] ' + SubText;
    C.TextOut(BoxX + 8, BoxY + 6, SubText);

    C.Font.Style := [];
    C.Font.Size := 8;
    C.Font.Color := $C2B8AE;
    C.TextOut(BoxX + 8, BoxY + 30,
      Format('id: %s  actions: %d', [S.StateId, Length(S.EntryActions)]));

    if IsActive then
    begin
      C.Font.Color := $88FF70;
      C.TextOut(BoxX + 8, BoxY + 46, Format('ACTIVE (%.2fs)', [G.ActiveStateElapsed]));
    end else
    if S.Comment <> '' then
    begin
      C.Font.Color := $968C82;
      C.TextOut(BoxX + 8, BoxY + 46, Copy(S.Comment, 1, 24));
    end;
  end;
end;

function TStateGraphForm.HitTestStateAt(const X, Y: Integer): String;
var
  G: TCastleStateGraphBehavior;
  I, BoxX, BoxY: Integer;
  S: TStateNodeData;
begin
  Result := '';
  G := ActiveGraph;
  if G = nil then
    Exit;
  for I := G.StateCount - 1 downto 0 do
  begin
    S := G.GetState(I);
    BoxX := Round(S.CanvasX);
    BoxY := Round(S.CanvasY);
    if (X >= BoxX) and (X <= BoxX + StateBoxW) and
       (Y >= BoxY) and (Y <= BoxY + StateBoxH) then
      Exit(S.StateId);
  end;
end;

procedure TStateGraphForm.PaintBoxGraphMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  G: TCastleStateGraphBehavior;
  HitId: String;
  Idx: Integer;
  S: TStateNodeData;
begin
  if Button <> mbLeft then
    Exit;
  G := ActiveGraph;
  if G = nil then
    Exit;

  HitId := HitTestStateAt(X, Y);
  FSelectedStateId := HitId;
  FDragMoved := false;
  if HitId <> '' then
  begin
    Idx := G.FindStateIndex(HitId);
    if Idx >= 0 then
    begin
      S := G.GetState(Idx);
      FDraggingStateId := HitId;
      FDragOffsetX := X - S.CanvasX;
      FDragOffsetY := Y - S.CanvasY;
      if Idx < ListStates.Items.Count then
        ListStates.ItemIndex := Idx;
      EditStateId.Text := S.StateId;
      EditStateTitle.Text := S.DisplayName;
    end;
  end else
    FDraggingStateId := '';

  PaintBoxGraph.Invalidate;
end;

procedure TStateGraphForm.PaintBoxGraphMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  G: TCastleStateGraphBehavior;
  NewX, NewY: Single;
begin
  if FDraggingStateId = '' then
    Exit;
  G := ActiveGraph;
  if G = nil then
    Exit;
  NewX := Max(8.0, X - FDragOffsetX);
  NewY := Max(8.0, Y - FDragOffsetY);
  if G.MoveStateCanvas(FDraggingStateId, NewX, NewY) then
  begin
    FDragMoved := true;
    PaintBoxGraph.Invalidate;
  end;
end;

procedure TStateGraphForm.PaintBoxGraphMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (FDraggingStateId <> '') and FDragMoved then
    NotifyModified('Move StateGraph node ' + FDraggingStateId);
  FDraggingStateId := '';
  FDragMoved := false;
end;

procedure TStateGraphForm.PaintBoxGraphDblClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if (G <> nil) and (FSelectedStateId <> '') then
  begin
    G.ForceEnterState(FSelectedStateId);
    UpdateSimStatusLabel;
    PaintBoxGraph.Invalidate;
    NotifyViewportRefresh;
  end;
end;

procedure TStateGraphForm.ComboGraphChange(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if G <> nil then
    G.OnStateCue := @OnGraphCueFired;
  RefreshAllViews;
end;

procedure TStateGraphForm.ButtonAttachNewClick(Sender: TObject);
var
  TargetT: TCastleTransform;
  NewG: TCastleStateGraphBehavior;
begin
  TargetT := TStateGraphHelper.FindFirstTransformTarget(FRootComponent, FInitialSelected);
  if TargetT = nil then
  begin
    MessageDlg('Attach StateGraph',
      'Select or add a TCastleTransform (or TCastleViewport) in the design first.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  NewG := TStateGraphHelper.AttachStateGraphToTransform(TargetT, FDesignOwner, 'AI StateTree');
  TStateGraphHelper.ApplyGameplayTemplate(NewG, sgtAiPatrolChaseAttack);
  NotifyModified('Attach TCastleStateGraphBehavior to ' + TargetT.Name);
  RefreshGraphList(NewG);
end;

procedure TStateGraphForm.ButtonTplAiClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if G = nil then
  begin
    ButtonAttachNewClick(Sender);
    Exit;
  end;
  TStateGraphHelper.ApplyGameplayTemplate(G, sgtAiPatrolChaseAttack);
  NotifyModified('Apply AI Patrol/Chase/Attack StateTree template');
  RefreshAllViews;
end;

procedure TStateGraphForm.ButtonTplDoorClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if G = nil then
  begin
    ButtonAttachNewClick(Sender);
    G := ActiveGraph;
  end;
  if G = nil then
    Exit;
  TStateGraphHelper.ApplyGameplayTemplate(G, sgtInteractiveDoor);
  NotifyModified('Apply Interactive Door StateTree template');
  RefreshAllViews;
end;

procedure TStateGraphForm.ButtonTplUiClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if G = nil then
  begin
    ButtonAttachNewClick(Sender);
    G := ActiveGraph;
  end;
  if G = nil then
    Exit;
  TStateGraphHelper.ApplyGameplayTemplate(G, sgtUiMenuFlow);
  NotifyModified('Apply UI Menu Flow StateTree template');
  RefreshAllViews;
end;

procedure TStateGraphForm.ButtonValidateClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
  Warnings: TStringList;
begin
  G := ActiveGraph;
  Warnings := TStringList.Create;
  try
    if TStateGraphHelper.ValidateGraph(G, Warnings) then
      MessageDlg('StateGraph Validation Passed',
        Format('"%s" passed all reachability, initial-state, and blackboard checks (%d states, %d transitions).',
          [G.GraphLabel, G.StateCount, G.TransitionCount]),
        mtInformation, [mbOK], 0)
    else
      MessageDlg('StateGraph Validation Warnings',
        Warnings.Text, mtWarning, [mbOK], 0);
  finally
    FreeAndNil(Warnings);
  end;
end;

procedure TStateGraphForm.ButtonCopyMarkdownClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if G = nil then
    Exit;
  Clipboard.AsText := TStateGraphHelper.FormatGraphMarkdown(G);
  MessageDlg('Copied Mermaid StateDiagram',
    'Markdown + Mermaid stateDiagram-v2 copied to clipboard.',
    mtInformation, [mbOK], 0);
end;

procedure TStateGraphForm.SimTimerTick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if G = nil then
  begin
    FSimTimer.Enabled := false;
    ButtonSimPlayPause.Caption := 'Start Live Sim';
    Exit;
  end;
  G.StepGraph(0.033);
  UpdateSimStatusLabel;
  PaintBoxGraph.Invalidate;
  NotifyViewportRefresh;
end;

procedure TStateGraphForm.ButtonSimPlayPauseClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if G = nil then
    Exit;
  FSimTimer.Enabled := not FSimTimer.Enabled;
  if FSimTimer.Enabled then
  begin
    G.StartGraph;
    ButtonSimPlayPause.Caption := 'Pause Live Sim';
  end else
    ButtonSimPlayPause.Caption := 'Start Live Sim';
  RefreshAllViews;
end;

procedure TStateGraphForm.ButtonSimStepClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if G = nil then
    Exit;
  G.StepGraph(0.5);
  RefreshAllViews;
  NotifyViewportRefresh;
end;

procedure TStateGraphForm.ButtonSimResetClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  FSimTimer.Enabled := false;
  ButtonSimPlayPause.Caption := 'Start Live Sim';
  FLastCueLog := '';
  G := ActiveGraph;
  if G <> nil then
    G.ResetGraph;
  RefreshAllViews;
  NotifyViewportRefresh;
end;

procedure TStateGraphForm.OnGraphCueFired(Sender: TObject;
  const CueName, Payload: String);
begin
  if Payload <> '' then
    FLastCueLog := CueName + '(' + Payload + ')'
  else
    FLastCueLog := CueName;
end;

procedure TStateGraphForm.ListBlackboardSelectionChange(Sender: TObject; User: Boolean);
var
  G: TCastleStateGraphBehavior;
  Idx: Integer;
  V: TStateBlackboardVarData;
begin
  G := ActiveGraph;
  Idx := ListBlackboard.ItemIndex;
  if (G = nil) or (Idx < 0) or (Idx >= G.VariableCount) then
    Exit;
  V := G.GetVariable(Idx);
  EditLiveVarValue.Text := G.FormatBlackboardValue(V.VarName);
  EditNewVarName.Text := V.VarName;
  EditNewVarDefault.Text := V.DefaultStr;
end;

procedure TStateGraphForm.ButtonApplyLiveVarClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
  Idx: Integer;
  V: TStateBlackboardVarData;
begin
  G := ActiveGraph;
  Idx := ListBlackboard.ItemIndex;
  if (G = nil) or (Idx < 0) or (Idx >= G.VariableCount) then
    Exit;
  V := G.GetVariable(Idx);
  G.SetBlackboardFromString(V.VarName, EditLiveVarValue.Text);
  if G.ActiveStateId <> '' then
    G.StepGraph(0.0);
  RefreshAllViews;
  ListBlackboard.ItemIndex := Idx;
  NotifyViewportRefresh;
end;

procedure TStateGraphForm.ButtonToggleBoolVarClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
  Idx: Integer;
  V: TStateBlackboardVarData;
begin
  G := ActiveGraph;
  Idx := ListBlackboard.ItemIndex;
  if (G = nil) or (Idx < 0) or (Idx >= G.VariableCount) then
    Exit;
  V := G.GetVariable(Idx);
  G.SetBool(V.VarName, not G.GetBool(V.VarName));
  if G.ActiveStateId <> '' then
    G.StepGraph(0.0);
  RefreshAllViews;
  ListBlackboard.ItemIndex := Idx;
  NotifyViewportRefresh;
end;

procedure TStateGraphForm.ButtonAddVariableClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if (G = nil) or (Trim(EditNewVarName.Text) = '') then
    Exit;
  G.AddOrUpdateVariable(Trim(EditNewVarName.Text),
    StringToStateVarKind(ComboNewVarKind.Text), EditNewVarDefault.Text);
  NotifyModified('Add/Update StateGraph variable ' + Trim(EditNewVarName.Text));
  RefreshAllViews;
end;

procedure TStateGraphForm.ButtonDeleteVariableClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
  Idx: Integer;
  V: TStateBlackboardVarData;
begin
  G := ActiveGraph;
  Idx := ListBlackboard.ItemIndex;
  if (G = nil) or (Idx < 0) or (Idx >= G.VariableCount) then
    Exit;
  V := G.GetVariable(Idx);
  if G.RemoveVariable(V.VarName) then
  begin
    NotifyModified('Delete StateGraph variable ' + V.VarName);
    RefreshAllViews;
  end;
end;

procedure TStateGraphForm.ListStatesSelectionChange(Sender: TObject; User: Boolean);
var
  G: TCastleStateGraphBehavior;
  Idx: Integer;
  S: TStateNodeData;
begin
  G := ActiveGraph;
  Idx := ListStates.ItemIndex;
  if (G = nil) or (Idx < 0) or (Idx >= G.StateCount) then
    Exit;
  S := G.GetState(Idx);
  FSelectedStateId := S.StateId;
  EditStateId.Text := S.StateId;
  EditStateTitle.Text := S.DisplayName;
  PaintBoxGraph.Invalidate;
end;

procedure TStateGraphForm.ButtonAddOrUpdateStateClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
  IdStr: String;
  ExistingIdx: Integer;
  PosX, PosY: Single;
begin
  G := ActiveGraph;
  IdStr := Trim(EditStateId.Text);
  if (G = nil) or (IdStr = '') then
    Exit;
  ExistingIdx := G.FindStateIndex(IdStr);
  if ExistingIdx >= 0 then
  begin
    PosX := G.GetState(ExistingIdx).CanvasX;
    PosY := G.GetState(ExistingIdx).CanvasY;
  end else
  begin
    PosX := 80 + (G.StateCount mod 4) * 200;
    PosY := 120 + (G.StateCount div 4) * 110;
  end;
  G.AddOrUpdateState(IdStr, EditStateTitle.Text, PosX, PosY);
  FSelectedStateId := IdStr;
  NotifyModified('Add/Update StateGraph state ' + IdStr);
  RefreshAllViews;
end;

procedure TStateGraphForm.ButtonSetInitialStateClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if (G = nil) or (FSelectedStateId = '') then
    Exit;
  G.InitialStateId := FSelectedStateId;
  NotifyModified('Set StateGraph initial state to ' + FSelectedStateId);
  RefreshAllViews;
end;

procedure TStateGraphForm.ButtonForceEnterStateClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if (G = nil) or (FSelectedStateId = '') then
    Exit;
  G.ForceEnterState(FSelectedStateId);
  RefreshAllViews;
  NotifyViewportRefresh;
end;

procedure TStateGraphForm.ButtonDeleteStateClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
  DelId: String;
begin
  G := ActiveGraph;
  DelId := FSelectedStateId;
  if (G = nil) or (DelId = '') then
    Exit;
  if G.RemoveState(DelId) then
  begin
    FSelectedStateId := '';
    NotifyModified('Delete StateGraph state ' + DelId);
    RefreshAllViews;
  end;
end;

procedure TStateGraphForm.ButtonAddEntryActionClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
  Kind: TStateActionKind;
begin
  G := ActiveGraph;
  if (G = nil) or (FSelectedStateId = '') or (Trim(EditActionKey.Text) = '') then
    Exit;
  case ComboActionKind.ItemIndex of
    0: Kind := sakSetProperty;
    1: Kind := sakSetBlackboardVar;
    2: Kind := sakPlayAnimation;
    else Kind := sakFireCue;
  end;
  if G.AddEntryAction(FSelectedStateId, Kind, EditActionTarget.Text,
       EditActionKey.Text, EditActionVal.Text, true) then
  begin
    NotifyModified('Add entry action to state ' + FSelectedStateId);
    RefreshAllViews;
  end;
end;

procedure TStateGraphForm.ButtonClearStateActionsClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if (G = nil) or (FSelectedStateId = '') then
    Exit;
  if G.ClearStateActions(FSelectedStateId) then
  begin
    NotifyModified('Clear actions on state ' + FSelectedStateId);
    RefreshAllViews;
  end;
end;

procedure TStateGraphForm.ListTransitionsSelectionChange(Sender: TObject; User: Boolean);
begin
  FSelectedTransitionIdx := ListTransitions.ItemIndex;
  PaintBoxGraph.Invalidate;
end;

procedure TStateGraphForm.ButtonAddTransitionClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
  Op: TStateConditionOp;
begin
  G := ActiveGraph;
  if G = nil then
    Exit;
  Op := StringToStateConditionOp(ComboCondOp.Text);
  if G.AddTransition(ComboFromState.Text, ComboToState.Text, Op,
       ComboCondVar.Text, EditCondVal.Text, SpinMinElapsed.Value,
       SpinPriority.Value) >= 0 then
  begin
    NotifyModified(Format('Add StateGraph transition %s -> %s',
      [ComboFromState.Text, ComboToState.Text]));
    RefreshAllViews;
  end;
end;

procedure TStateGraphForm.ButtonDeleteTransitionClick(Sender: TObject);
var
  G: TCastleStateGraphBehavior;
begin
  G := ActiveGraph;
  if (G = nil) or (ListTransitions.ItemIndex < 0) then
    Exit;
  if G.RemoveTransition(ListTransitions.ItemIndex) then
  begin
    FSelectedTransitionIdx := -1;
    NotifyModified('Delete StateGraph transition');
    RefreshAllViews;
  end;
end;

procedure TStateGraphForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
