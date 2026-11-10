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

{ Spatial Viewport Annotations ("Canvas Pins") & Design Review Bookmarks
  manager dialog (Phase 283 — UE 5.9 Spatial Review Parity). }
unit FormDesignAnnotations;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Contnrs, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Spin, Dialogs, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleUIControls, CastleViewport,
  CastleDesignAnnotations, ToolDesignAnnotations;

type
  TDesignAnnotationsModifiedCallback = procedure (const UndoComment: String) of object;
  TDesignAnnotationsSelectCallback = procedure (const C: TComponent) of object;
  TDesignAnnotationsTogglePinsCallback = procedure (const AVisible: Boolean) of object;

  TDesignAnnotationsForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FActiveViewport: TCastleViewport;
    FDesignLabel: String;
    FOnModified: TDesignAnnotationsModifiedCallback;
    FOnSelectComponent: TDesignAnnotationsSelectCallback;
    FOnTogglePins: TDesignAnnotationsTogglePinsCallback;
    FReport: TDesignAnnotationAuditReport;
    FFilteredIndices: array of Integer;
    FUpdatingEditor: Boolean;

    LabelBanner: TLabel;
    CheckShowViewportPins: TCheckBox;
    ComboFilterCategory: TComboBox;
    ComboFilterStatus: TComboBox;
    EditSearch: TEdit;
    ListPins: TListView;

    { Selected pin editor controls }
    GroupEditor: TGroupBox;
    EditPinTitle: TEdit;
    ComboPinCategory: TComboBox;
    ComboPinStatus: TComboBox;
    SpinPinPriority: TSpinEdit;
    EditPinAuthor: TEdit;
    CheckPinVisible: TCheckBox;
    MemoPinComment: TMemo;
    ButtonSavePinEdits: TButton;
    ButtonCaptureCamera: TButton;
    ButtonJumpCamera: TButton;

    { Creation & batch toolbar }
    ButtonAdd3DPin: TButton;
    ButtonAdd2DPin: TButton;
    ButtonResolveAll: TButton;
    ButtonDeleteResolved: TButton;
    ButtonCopyMarkdown: TButton;
    ButtonClose: TButton;

    procedure BuildUi;
    procedure RefreshReportAndList(const SelectComp: TComponent = nil);
    procedure PopulateList(const SelectComp: TComponent = nil);
    function SelectedPinComponent: TComponent;
    procedure LoadSelectedPinIntoEditor;

    procedure FilterControlChange(Sender: TObject);
    procedure CheckShowViewportPinsChange(Sender: TObject);
    procedure ListPinsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListPinsDblClick(Sender: TObject);
    procedure ButtonSavePinEditsClick(Sender: TObject);
    procedure ButtonCaptureCameraClick(Sender: TObject);
    procedure ButtonJumpCameraClick(Sender: TObject);
    procedure ButtonAdd3DPinClick(Sender: TObject);
    procedure ButtonAdd2DPinClick(Sender: TObject);
    procedure ButtonResolveAllClick(Sender: TObject);
    procedure ButtonDeleteResolvedClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateManager(AOwner: TComponent;
      const ARootComponent, ADesignOwner: TComponent;
      const AActiveViewport: TCastleViewport;
      const ADesignLabel: String;
      const AInitialSelection: TComponent;
      const AShowPinsOverlay: Boolean;
      const AOnModified: TDesignAnnotationsModifiedCallback;
      const AOnSelectComponent: TDesignAnnotationsSelectCallback;
      const AOnTogglePins: TDesignAnnotationsTogglePinsCallback);
    destructor Destroy; override;
  end;

implementation

uses
  CastleUtils;

constructor TDesignAnnotationsForm.CreateManager(AOwner: TComponent;
  const ARootComponent, ADesignOwner: TComponent;
  const AActiveViewport: TCastleViewport;
  const ADesignLabel: String;
  const AInitialSelection: TComponent;
  const AShowPinsOverlay: Boolean;
  const AOnModified: TDesignAnnotationsModifiedCallback;
  const AOnSelectComponent: TDesignAnnotationsSelectCallback;
  const AOnTogglePins: TDesignAnnotationsTogglePinsCallback);
begin
  inherited CreateNew(AOwner, 0);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FActiveViewport := AActiveViewport;
  FDesignLabel := ADesignLabel;
  FOnModified := AOnModified;
  FOnSelectComponent := AOnSelectComponent;
  FOnTogglePins := AOnTogglePins;

  Caption := 'Spatial Viewport Annotations ("Canvas Pins") & Review Bookmarks';
  Position := poMainFormCenter;
  Width := 940;
  Height := 640;
  Constraints.MinWidth := 780;
  Constraints.MinHeight := 520;

  BuildUi;
  CheckShowViewportPins.Checked := AShowPinsOverlay;
  RefreshReportAndList(AInitialSelection);
end;

destructor TDesignAnnotationsForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TDesignAnnotationsForm.BuildUi;
var
  TopPanel, FilterPanel, BottomPanel, MainSplitPanel, Row1, Row2, EditorBtns: TPanel;
  LblCatF, LblStatF, LblSearch, LblT, LblC, LblS, LblP, LblA, LblNote: TLabel;
  Col: TListColumn;
begin
  TopPanel := TPanel.Create(Self);
  TopPanel.Parent := Self;
  TopPanel.Align := alTop;
  TopPanel.AutoSize := true;
  TopPanel.BevelOuter := bvNone;
  TopPanel.BorderSpacing.Around := 8;

  LabelBanner := TLabel.Create(Self);
  LabelBanner.Parent := TopPanel;
  LabelBanner.Align := alTop;
  LabelBanner.Font.Style := [fsBold];
  LabelBanner.Caption := 'Scanning spatial design review pins...';

  CheckShowViewportPins := TCheckBox.Create(Self);
  CheckShowViewportPins.Parent := TopPanel;
  CheckShowViewportPins.Align := alTop;
  CheckShowViewportPins.BorderSpacing.Top := 4;
  CheckShowViewportPins.Caption := 'Show 3D Spatial Review Pin Callouts & Leader Badges in Viewport (Hidden Automatically at Game Runtime)';
  CheckShowViewportPins.OnChange := @CheckShowViewportPinsChange;

  FilterPanel := TPanel.Create(Self);
  FilterPanel.Parent := Self;
  FilterPanel.Align := alTop;
  FilterPanel.Height := 36;
  FilterPanel.BevelOuter := bvNone;
  FilterPanel.BorderSpacing.Left := 8;
  FilterPanel.BorderSpacing.Right := 8;

  LblCatF := TLabel.Create(Self);
  LblCatF.Parent := FilterPanel;
  LblCatF.Align := alLeft;
  LblCatF.Layout := tlCenter;
  LblCatF.Caption := 'Category:';
  LblCatF.BorderSpacing.Right := 4;

  ComboFilterCategory := TComboBox.Create(Self);
  ComboFilterCategory.Parent := FilterPanel;
  ComboFilterCategory.Align := alLeft;
  ComboFilterCategory.Width := 125;
  ComboFilterCategory.Style := csDropDownList;
  ComboFilterCategory.Items.Add('All Categories');
  ComboFilterCategory.Items.Add('Note');
  ComboFilterCategory.Items.Add('TODO');
  ComboFilterCategory.Items.Add('Bug');
  ComboFilterCategory.Items.Add('AI Prompt');
  ComboFilterCategory.ItemIndex := 0;
  ComboFilterCategory.BorderSpacing.Right := 12;
  ComboFilterCategory.OnChange := @FilterControlChange;

  LblStatF := TLabel.Create(Self);
  LblStatF.Parent := FilterPanel;
  LblStatF.Align := alLeft;
  LblStatF.Layout := tlCenter;
  LblStatF.Caption := 'Status:';
  LblStatF.BorderSpacing.Right := 4;

  ComboFilterStatus := TComboBox.Create(Self);
  ComboFilterStatus.Parent := FilterPanel;
  ComboFilterStatus.Align := alLeft;
  ComboFilterStatus.Width := 145;
  ComboFilterStatus.Style := csDropDownList;
  ComboFilterStatus.Items.Add('All Statuses');
  ComboFilterStatus.Items.Add('Unresolved Only');
  ComboFilterStatus.Items.Add('Open');
  ComboFilterStatus.Items.Add('In Progress');
  ComboFilterStatus.Items.Add('Resolved');
  ComboFilterStatus.ItemIndex := 0;
  ComboFilterStatus.BorderSpacing.Right := 12;
  ComboFilterStatus.OnChange := @FilterControlChange;

  LblSearch := TLabel.Create(Self);
  LblSearch.Parent := FilterPanel;
  LblSearch.Align := alLeft;
  LblSearch.Layout := tlCenter;
  LblSearch.Caption := 'Search:';
  LblSearch.BorderSpacing.Right := 4;

  EditSearch := TEdit.Create(Self);
  EditSearch.Parent := FilterPanel;
  EditSearch.Align := alClient;
  EditSearch.TextHint := 'Filter by title, comment, author, or component name...';
  EditSearch.OnChange := @FilterControlChange;

  BottomPanel := TPanel.Create(Self);
  BottomPanel.Parent := Self;
  BottomPanel.Align := alBottom;
  BottomPanel.Height := 44;
  BottomPanel.BevelOuter := bvNone;
  BottomPanel.BorderSpacing.Around := 6;

  ButtonAdd3DPin := TButton.Create(Self);
  ButtonAdd3DPin.Parent := BottomPanel;
  ButtonAdd3DPin.Align := alLeft;
  ButtonAdd3DPin.AutoSize := true;
  ButtonAdd3DPin.Caption := '+ Drop 3D Pin at Camera';
  ButtonAdd3DPin.BorderSpacing.Right := 6;
  ButtonAdd3DPin.OnClick := @ButtonAdd3DPinClick;

  ButtonAdd2DPin := TButton.Create(Self);
  ButtonAdd2DPin.Parent := BottomPanel;
  ButtonAdd2DPin.Align := alLeft;
  ButtonAdd2DPin.AutoSize := true;
  ButtonAdd2DPin.Caption := '+ Drop 2D UI Pin';
  ButtonAdd2DPin.BorderSpacing.Right := 12;
  ButtonAdd2DPin.OnClick := @ButtonAdd2DPinClick;

  ButtonResolveAll := TButton.Create(Self);
  ButtonResolveAll.Parent := BottomPanel;
  ButtonResolveAll.Align := alLeft;
  ButtonResolveAll.AutoSize := true;
  ButtonResolveAll.Caption := 'Mark All Resolved';
  ButtonResolveAll.BorderSpacing.Right := 6;
  ButtonResolveAll.OnClick := @ButtonResolveAllClick;

  ButtonDeleteResolved := TButton.Create(Self);
  ButtonDeleteResolved.Parent := BottomPanel;
  ButtonDeleteResolved.Align := alLeft;
  ButtonDeleteResolved.AutoSize := true;
  ButtonDeleteResolved.Caption := 'Delete Resolved';
  ButtonDeleteResolved.BorderSpacing.Right := 6;
  ButtonDeleteResolved.OnClick := @ButtonDeleteResolvedClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := BottomPanel;
  ButtonCopyMarkdown.Align := alLeft;
  ButtonCopyMarkdown.AutoSize := true;
  ButtonCopyMarkdown.Caption := 'Copy Markdown Checklist';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := BottomPanel;
  ButtonClose.Align := alRight;
  ButtonClose.Width := 96;
  ButtonClose.Caption := 'Close';
  ButtonClose.Cancel := true;
  ButtonClose.OnClick := @ButtonCloseClick;

  MainSplitPanel := TPanel.Create(Self);
  MainSplitPanel.Parent := Self;
  MainSplitPanel.Align := alClient;
  MainSplitPanel.BevelOuter := bvNone;
  MainSplitPanel.BorderSpacing.Around := 8;

  GroupEditor := TGroupBox.Create(Self);
  GroupEditor.Parent := MainSplitPanel;
  GroupEditor.Align := alBottom;
  GroupEditor.Height := 230;
  GroupEditor.Caption := 'Selected Review Pin Details & Camera Viewpoint Bookmark';
  GroupEditor.BorderSpacing.Top := 8;

  Row1 := TPanel.Create(Self);
  Row1.Parent := GroupEditor;
  Row1.Align := alTop;
  Row1.Height := 32;
  Row1.BevelOuter := bvNone;
  Row1.BorderSpacing.Around := 4;

  LblT := TLabel.Create(Self);
  LblT.Parent := Row1;
  LblT.Align := alLeft;
  LblT.Layout := tlCenter;
  LblT.Caption := 'Title:';
  LblT.BorderSpacing.Right := 4;

  EditPinTitle := TEdit.Create(Self);
  EditPinTitle.Parent := Row1;
  EditPinTitle.Align := alClient;
  EditPinTitle.BorderSpacing.Right := 10;

  LblC := TLabel.Create(Self);
  LblC.Parent := Row1;
  LblC.Align := alRight;
  LblC.Layout := tlCenter;
  LblC.Caption := 'Category:';
  LblC.BorderSpacing.Right := 4;

  ComboPinCategory := TComboBox.Create(Self);
  ComboPinCategory.Parent := Row1;
  ComboPinCategory.Align := alRight;
  ComboPinCategory.Width := 110;
  ComboPinCategory.Style := csDropDownList;
  ComboPinCategory.Items.Add('Note');
  ComboPinCategory.Items.Add('TODO');
  ComboPinCategory.Items.Add('Bug');
  ComboPinCategory.Items.Add('AI Prompt');
  ComboPinCategory.ItemIndex := 0;
  ComboPinCategory.BorderSpacing.Right := 10;

  LblS := TLabel.Create(Self);
  LblS.Parent := Row1;
  LblS.Align := alRight;
  LblS.Layout := tlCenter;
  LblS.Caption := 'Status:';
  LblS.BorderSpacing.Right := 4;

  ComboPinStatus := TComboBox.Create(Self);
  ComboPinStatus.Parent := Row1;
  ComboPinStatus.Align := alRight;
  ComboPinStatus.Width := 110;
  ComboPinStatus.Style := csDropDownList;
  ComboPinStatus.Items.Add('Open');
  ComboPinStatus.Items.Add('In Progress');
  ComboPinStatus.Items.Add('Resolved');
  ComboPinStatus.ItemIndex := 0;

  Row2 := TPanel.Create(Self);
  Row2.Parent := GroupEditor;
  Row2.Align := alTop;
  Row2.Height := 32;
  Row2.BevelOuter := bvNone;
  Row2.BorderSpacing.Around := 4;

  LblP := TLabel.Create(Self);
  LblP.Parent := Row2;
  LblP.Align := alLeft;
  LblP.Layout := tlCenter;
  LblP.Caption := 'Priority (1..5):';
  LblP.BorderSpacing.Right := 4;

  SpinPinPriority := TSpinEdit.Create(Self);
  SpinPinPriority.Parent := Row2;
  SpinPinPriority.Align := alLeft;
  SpinPinPriority.Width := 64;
  SpinPinPriority.MinValue := 1;
  SpinPinPriority.MaxValue := 5;
  SpinPinPriority.Value := 3;
  SpinPinPriority.BorderSpacing.Right := 12;

  LblA := TLabel.Create(Self);
  LblA.Parent := Row2;
  LblA.Align := alLeft;
  LblA.Layout := tlCenter;
  LblA.Caption := 'Author:';
  LblA.BorderSpacing.Right := 4;

  EditPinAuthor := TEdit.Create(Self);
  EditPinAuthor.Parent := Row2;
  EditPinAuthor.Align := alLeft;
  EditPinAuthor.Width := 160;
  EditPinAuthor.BorderSpacing.Right := 12;

  CheckPinVisible := TCheckBox.Create(Self);
  CheckPinVisible.Parent := Row2;
  CheckPinVisible.Align := alLeft;
  CheckPinVisible.Caption := 'Visible in Design Viewport';
  CheckPinVisible.Checked := true;

  EditorBtns := TPanel.Create(Self);
  EditorBtns.Parent := GroupEditor;
  EditorBtns.Align := alBottom;
  EditorBtns.Height := 36;
  EditorBtns.BevelOuter := bvNone;
  EditorBtns.BorderSpacing.Around := 4;

  ButtonSavePinEdits := TButton.Create(Self);
  ButtonSavePinEdits.Parent := EditorBtns;
  ButtonSavePinEdits.Align := alLeft;
  ButtonSavePinEdits.AutoSize := true;
  ButtonSavePinEdits.Caption := 'Apply Changes to Selected Pin';
  ButtonSavePinEdits.BorderSpacing.Right := 8;
  ButtonSavePinEdits.OnClick := @ButtonSavePinEditsClick;

  ButtonJumpCamera := TButton.Create(Self);
  ButtonJumpCamera.Parent := EditorBtns;
  ButtonJumpCamera.Align := alLeft;
  ButtonJumpCamera.AutoSize := true;
  ButtonJumpCamera.Caption := 'Select & Jump Camera to Pin';
  ButtonJumpCamera.BorderSpacing.Right := 8;
  ButtonJumpCamera.OnClick := @ButtonJumpCameraClick;

  ButtonCaptureCamera := TButton.Create(Self);
  ButtonCaptureCamera.Parent := EditorBtns;
  ButtonCaptureCamera.Align := alLeft;
  ButtonCaptureCamera.AutoSize := true;
  ButtonCaptureCamera.Caption := 'Save Current 3D Camera as Bookmark';
  ButtonCaptureCamera.OnClick := @ButtonCaptureCameraClick;

  LblNote := TLabel.Create(Self);
  LblNote.Parent := GroupEditor;
  LblNote.Align := alTop;
  LblNote.Caption := 'Comment / Reproduction Steps / AI Prompt Instructions:';
  LblNote.BorderSpacing.Left := 6;

  MemoPinComment := TMemo.Create(Self);
  MemoPinComment.Parent := GroupEditor;
  MemoPinComment.Align := alClient;
  MemoPinComment.ScrollBars := ssAutoVertical;
  MemoPinComment.BorderSpacing.Around := 4;

  ListPins := TListView.Create(Self);
  ListPins.Parent := MainSplitPanel;
  ListPins.Align := alClient;
  ListPins.ViewStyle := vsReport;
  ListPins.RowSelect := true;
  ListPins.ReadOnly := true;
  ListPins.OnSelectItem := @ListPinsSelectItem;
  ListPins.OnDblClick := @ListPinsDblClick;

  Col := ListPins.Columns.Add; Col.Caption := 'Space'; Col.Width := 54;
  Col := ListPins.Columns.Add; Col.Caption := 'Category'; Col.Width := 85;
  Col := ListPins.Columns.Add; Col.Caption := 'Status'; Col.Width := 90;
  Col := ListPins.Columns.Add; Col.Caption := 'Prio'; Col.Width := 46;
  Col := ListPins.Columns.Add; Col.Caption := 'Title'; Col.Width := 250;
  Col := ListPins.Columns.Add; Col.Caption := 'Bookmark'; Col.Width := 78;
  Col := ListPins.Columns.Add; Col.Caption := 'Author'; Col.Width := 100;
  Col := ListPins.Columns.Add; Col.Caption := 'Component'; Col.Width := 150;
end;

procedure TDesignAnnotationsForm.RefreshReportAndList(const SelectComp: TComponent);
begin
  FreeAndNil(FReport);
  FReport := TDesignAnnotationManager.ScanDesign(FRootComponent);

  LabelBanner.Caption := Format(
    'Total Pins: %d (%d 3D, %d 2D)  |  Open: %d  |  In Progress: %d  |  Resolved: %d  |  Actionable Blockers: %d Bug(s), %d TODO(s)  |  3D Camera Bookmarks: %d',
    [FReport.TotalPins, FReport.Pins3DCount, FReport.Pins2DCount,
     FReport.OpenCount, FReport.InProgressCount, FReport.ResolvedCount,
     FReport.UnresolvedBugCount, FReport.UnresolvedTodoCount,
     FReport.Bookmarked3DPins]);

  ButtonAdd3DPin.Enabled := (FActiveViewport <> nil) and (FDesignOwner <> nil);
  ButtonAdd2DPin.Enabled := (FRootComponent is TCastleUserInterface) and (FDesignOwner <> nil);

  PopulateList(SelectComp);
end;

procedure TDesignAnnotationsForm.PopulateList(const SelectComp: TComponent);
var
  CatFilter, StatFilter, I, SelectListIdx: Integer;
  Item: TListItem;
begin
  if FReport = nil then
    Exit;

  if ComboFilterCategory.ItemIndex <= 0 then
    CatFilter := -1
  else
    CatFilter := ComboFilterCategory.ItemIndex - 1;

  case ComboFilterStatus.ItemIndex of
    0: StatFilter := -1; // All
    1: StatFilter := -2; // Unresolved Only
  else
    StatFilter := ComboFilterStatus.ItemIndex - 2;
  end;

  SelectListIdx := -1;
  SetLength(FFilteredIndices, 0);
  ListPins.Items.BeginUpdate;
  try
    ListPins.Items.Clear;
    for I := 0 to High(FReport.Items) do
    begin
      if not TDesignAnnotationManager.MatchesFilter(
           FReport.Items[I], CatFilter, StatFilter, EditSearch.Text) then
        Continue;

      SetLength(FFilteredIndices, Length(FFilteredIndices) + 1);
      FFilteredIndices[High(FFilteredIndices)] := I;

      Item := ListPins.Items.Add;
      if FReport.Items[I].Is3D then
        Item.Caption := '3D'
      else
        Item.Caption := '2D UI';
      Item.SubItems.Add(DesignAnnotationCategoryDisplayName(FReport.Items[I].Category));
      Item.SubItems.Add(DesignAnnotationStatusDisplayName(FReport.Items[I].Status));
      Item.SubItems.Add('P' + IntToStr(FReport.Items[I].Priority));
      Item.SubItems.Add(FReport.Items[I].Title);
      if FReport.Items[I].HasCameraBookmark then
        Item.SubItems.Add('Saved Cam')
      else
        Item.SubItems.Add('-');
      Item.SubItems.Add(FReport.Items[I].Author);
      Item.SubItems.Add(FReport.Items[I].ComponentName);

      if (SelectComp <> nil) and (FReport.Items[I].Component = SelectComp) then
        SelectListIdx := ListPins.Items.Count - 1;
    end;
  finally
    ListPins.Items.EndUpdate;
  end;

  if (SelectListIdx >= 0) and (SelectListIdx < ListPins.Items.Count) then
    ListPins.ItemIndex := SelectListIdx
  else if ListPins.Items.Count > 0 then
    ListPins.ItemIndex := 0;

  LoadSelectedPinIntoEditor;
end;

function TDesignAnnotationsForm.SelectedPinComponent: TComponent;
var
  Idx, ReportIdx: Integer;
begin
  Result := nil;
  if FReport = nil then
    Exit;
  Idx := ListPins.ItemIndex;
  if (Idx < 0) or (Idx > High(FFilteredIndices)) then
    Exit;
  ReportIdx := FFilteredIndices[Idx];
  if (ReportIdx >= 0) and (ReportIdx <= High(FReport.Items)) then
    Result := FReport.Items[ReportIdx].Component;
end;

procedure TDesignAnnotationsForm.LoadSelectedPinIntoEditor;
var
  C: TComponent;
  HasSel, Is3D: Boolean;
  Pin3D: TCastleDesignAnnotation;
  Pin2D: TCastleDesignAnnotationUi;
begin
  C := SelectedPinComponent;
  HasSel := (C is TCastleDesignAnnotation) or (C is TCastleDesignAnnotationUi);
  Is3D := C is TCastleDesignAnnotation;

  EditPinTitle.Enabled := HasSel;
  ComboPinCategory.Enabled := HasSel;
  ComboPinStatus.Enabled := HasSel;
  SpinPinPriority.Enabled := HasSel;
  EditPinAuthor.Enabled := HasSel;
  CheckPinVisible.Enabled := HasSel;
  MemoPinComment.Enabled := HasSel;
  ButtonSavePinEdits.Enabled := HasSel;
  ButtonJumpCamera.Enabled := HasSel;
  ButtonCaptureCamera.Enabled := Is3D and (FActiveViewport <> nil);

  FUpdatingEditor := true;
  try
    if C is TCastleDesignAnnotation then
    begin
      Pin3D := TCastleDesignAnnotation(C);
      GroupEditor.Caption := Format('Selected 3D Review Pin: %s', [Pin3D.Name]);
      EditPinTitle.Text := Pin3D.Title;
      ComboPinCategory.ItemIndex := Ord(Pin3D.Category);
      ComboPinStatus.ItemIndex := Ord(Pin3D.Status);
      SpinPinPriority.Value := Pin3D.Priority;
      EditPinAuthor.Text := Pin3D.Author;
      CheckPinVisible.Checked := Pin3D.ShowPinInViewport;
      MemoPinComment.Text := Pin3D.Comment;
    end else
    if C is TCastleDesignAnnotationUi then
    begin
      Pin2D := TCastleDesignAnnotationUi(C);
      GroupEditor.Caption := Format('Selected 2D UI Review Pin: %s', [Pin2D.Name]);
      EditPinTitle.Text := Pin2D.Title;
      ComboPinCategory.ItemIndex := Ord(Pin2D.Category);
      ComboPinStatus.ItemIndex := Ord(Pin2D.Status);
      SpinPinPriority.Value := Pin2D.Priority;
      EditPinAuthor.Text := Pin2D.Author;
      CheckPinVisible.Checked := Pin2D.ShowPinInViewport;
      MemoPinComment.Text := Pin2D.Comment;
    end else
    begin
      GroupEditor.Caption := 'Selected Review Pin Details (No Pin Selected)';
      EditPinTitle.Text := '';
      EditPinAuthor.Text := '';
      MemoPinComment.Text := '';
    end;
  finally
    FUpdatingEditor := false;
  end;
end;

procedure TDesignAnnotationsForm.FilterControlChange(Sender: TObject);
begin
  PopulateList(SelectedPinComponent);
end;

procedure TDesignAnnotationsForm.CheckShowViewportPinsChange(Sender: TObject);
begin
  if Assigned(FOnTogglePins) then
    FOnTogglePins(CheckShowViewportPins.Checked);
end;

procedure TDesignAnnotationsForm.ListPinsSelectItem(Sender: TObject;
  Item: TListItem; Selected: Boolean);
begin
  if Selected then
    LoadSelectedPinIntoEditor;
end;

procedure TDesignAnnotationsForm.ListPinsDblClick(Sender: TObject);
begin
  ButtonJumpCameraClick(Sender);
end;

procedure TDesignAnnotationsForm.ButtonSavePinEditsClick(Sender: TObject);
var
  C: TComponent;
  Pin3D: TCastleDesignAnnotation;
  Pin2D: TCastleDesignAnnotationUi;
begin
  if FUpdatingEditor then
    Exit;
  C := SelectedPinComponent;
  if C is TCastleDesignAnnotation then
  begin
    Pin3D := TCastleDesignAnnotation(C);
    Pin3D.Title := Trim(EditPinTitle.Text);
    Pin3D.Category := TDesignAnnotationCategory(ComboPinCategory.ItemIndex);
    Pin3D.Status := TDesignAnnotationStatus(ComboPinStatus.ItemIndex);
    Pin3D.Priority := SpinPinPriority.Value;
    Pin3D.Author := Trim(EditPinAuthor.Text);
    Pin3D.ShowPinInViewport := CheckPinVisible.Checked;
    Pin3D.Comment := Trim(MemoPinComment.Text);
    if Assigned(FOnModified) then
      FOnModified('Edit Spatial Review Pin ' + Pin3D.Name);
    RefreshReportAndList(C);
  end else
  if C is TCastleDesignAnnotationUi then
  begin
    Pin2D := TCastleDesignAnnotationUi(C);
    Pin2D.Title := Trim(EditPinTitle.Text);
    Pin2D.Category := TDesignAnnotationCategory(ComboPinCategory.ItemIndex);
    Pin2D.Status := TDesignAnnotationStatus(ComboPinStatus.ItemIndex);
    Pin2D.Priority := SpinPinPriority.Value;
    Pin2D.Author := Trim(EditPinAuthor.Text);
    Pin2D.ShowPinInViewport := CheckPinVisible.Checked;
    Pin2D.Comment := Trim(MemoPinComment.Text);
    if Assigned(FOnModified) then
      FOnModified('Edit UI Review Pin ' + Pin2D.Name);
    RefreshReportAndList(C);
  end;
end;

procedure TDesignAnnotationsForm.ButtonCaptureCameraClick(Sender: TObject);
var
  C: TComponent;
  Cam: TCastleTransform;
begin
  C := SelectedPinComponent;
  if (C is TCastleDesignAnnotation) and (FActiveViewport <> nil) then
  begin
    Cam := FActiveViewport.InternalCamera;
    if Cam = nil then
      Cam := FActiveViewport.Camera;
    if TCastleDesignAnnotation(C).CaptureCameraFrom(Cam) then
    begin
      if Assigned(FOnModified) then
        FOnModified('Save Camera Bookmark on ' + C.Name);
      RefreshReportAndList(C);
    end;
  end;
end;

procedure TDesignAnnotationsForm.ButtonJumpCameraClick(Sender: TObject);
var
  C: TComponent;
begin
  C := SelectedPinComponent;
  if C = nil then
    Exit;
  if Assigned(FOnSelectComponent) then
    FOnSelectComponent(C);
  if (C is TCastleDesignAnnotation) and (FActiveViewport <> nil) then
    TDesignAnnotationManager.JumpViewportTo3DPin(
      FActiveViewport, TCastleDesignAnnotation(C));
end;

procedure TDesignAnnotationsForm.ButtonAdd3DPinClick(Sender: TObject);
var
  NewPin: TCastleDesignAnnotation;
begin
  if (FActiveViewport = nil) or (FDesignOwner = nil) then
    Exit;
  NewPin := TDesignAnnotationManager.Create3DPinInViewport(
    FActiveViewport, FDesignOwner, dacTodo, 'New 3D Review Pin', true, 5.0);
  if NewPin <> nil then
  begin
    if Assigned(FOnModified) then
      FOnModified('Add 3D Spatial Review Pin ' + NewPin.Name);
    if Assigned(FOnSelectComponent) then
      FOnSelectComponent(NewPin);
    RefreshReportAndList(NewPin);
  end;
end;

procedure TDesignAnnotationsForm.ButtonAdd2DPinClick(Sender: TObject);
var
  NewPin: TCastleDesignAnnotationUi;
begin
  if not (FRootComponent is TCastleUserInterface) or (FDesignOwner = nil) then
    Exit;
  NewPin := TDesignAnnotationManager.Create2DPinInUi(
    TCastleUserInterface(FRootComponent), FDesignOwner, dacNote, 'New 2D UI Review Pin');
  if NewPin <> nil then
  begin
    if Assigned(FOnModified) then
      FOnModified('Add 2D UI Review Pin ' + NewPin.Name);
    if Assigned(FOnSelectComponent) then
      FOnSelectComponent(NewPin);
    RefreshReportAndList(NewPin);
  end;
end;

procedure TDesignAnnotationsForm.ButtonResolveAllClick(Sender: TObject);
var
  Count: Integer;
begin
  Count := TDesignAnnotationManager.MarkAllResolved(FRootComponent, -1);
  if Count > 0 then
  begin
    if Assigned(FOnModified) then
      FOnModified(Format('Resolve %d Spatial Review Pin(s)', [Count]));
    RefreshReportAndList(SelectedPinComponent);
  end;
end;

procedure TDesignAnnotationsForm.ButtonDeleteResolvedClick(Sender: TObject);
var
  Count: Integer;
begin
  Count := TDesignAnnotationManager.DeleteResolvedPins(FRootComponent);
  if Count > 0 then
  begin
    if Assigned(FOnModified) then
      FOnModified(Format('Delete %d Resolved Review Pin(s)', [Count]));
    RefreshReportAndList(nil);
  end;
end;

procedure TDesignAnnotationsForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  if FReport <> nil then
  begin
    Clipboard.AsText := FReport.FormatMarkdownChecklist(FDesignLabel);
    MessageDlg('Copied Checklist',
      'Spatial Design Review Markdown checklist copied to clipboard.',
      mtInformation, [mbOK], 0);
  end;
end;

procedure TDesignAnnotationsForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
