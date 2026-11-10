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

{ Modal dialog for managing Non-Destructive Design Sandboxes and performing
  Visual Scene/UI Hierarchy + RTTI Property Diff & Selective Revert/Merge
  (Unreal Engine 5.8 / 5.9 Content Sandboxes & Visual Diff parity). }
unit FormDesignSandboxDiff;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, CheckLst, Dialogs,
  ToolDesignSandboxDiff;

type
  TApplyMergedDesignCallback = procedure (const NewSerializedJson, UndoComment: String) of object;
  TGetLiveDesignJsonCallback = function: String of object;

  TDesignSandboxDiffForm = class(TForm)
  strict private
    FSandboxManager: TDesignSandboxManager;
    FDesignUrl: String;
    FCurrentDesignRoot: TComponent;
    FOnSaveSandboxes: TNotifyEvent;
    FOnApplyMergedJson: TApplyMergedDesignCallback;
    FGetLiveDesignJson: TGetLiveDesignJsonCallback;

    FSandboxEntries: Classes.TList;
    FBaseJsonList: TStringList;
    FBaseLabelList: TStringList;
    FDiffItemTags: TStringList;
    FCurrentReport: TDesignDiffReport;

    GroupSandboxes: TGroupBox;
    ListSandboxes: TListBox;
    PanelSandboxButtons: TPanel;
    BtnSaveSandbox: TButton;
    BtnActivateSandbox: TButton;
    BtnOverwriteSandbox: TButton;
    BtnRenameSandbox: TButton;
    BtnDeleteSandbox: TButton;

    GroupDiff: TGroupBox;
    PanelDiffTop: TPanel;
    LabelCompareAgainst: TLabel;
    ComboBaseSource: TComboBox;
    LabelDiffSummary: TLabel;
    CheckListDiff: TCheckListBox;
    SplitterDetails: TSplitter;
    MemoDetails: TMemo;

    PanelBottom: TPanel;
    BtnCheckAll: TButton;
    BtnUncheckAll: TButton;
    BtnRevertChecked: TButton;
    BtnCopyReport: TButton;
    BtnClose: TButton;

    function CurrentDesignJson: String;
    function SelectedSandboxEntry: TDesignSandboxEntry;
    procedure RefreshSandboxesUI(const SelectSandboxName: String = '');
    procedure RebuildBaseSourcesCombo;
    procedure RecomputeDiff;
    procedure UpdateSandboxButtonStates;

    procedure ListSandboxesClick(Sender: TObject);
    procedure ListSandboxesDblClick(Sender: TObject);
    procedure BtnSaveSandboxClick(Sender: TObject);
    procedure BtnActivateSandboxClick(Sender: TObject);
    procedure BtnOverwriteSandboxClick(Sender: TObject);
    procedure BtnRenameSandboxClick(Sender: TObject);
    procedure BtnDeleteSandboxClick(Sender: TObject);

    procedure ComboBaseSourceChange(Sender: TObject);
    procedure CheckListDiffSelectionChange(Sender: TObject; User: Boolean);
    procedure BtnCheckAllClick(Sender: TObject);
    procedure BtnUncheckAllClick(Sender: TObject);
    procedure BtnRevertCheckedClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent;
      const ASandboxManager: TDesignSandboxManager;
      const ADesignUrl: String;
      const ACurrentDesignRoot: TComponent;
      const AGetLiveDesignJson: TGetLiveDesignJsonCallback;
      const AOnSaveSandboxes: TNotifyEvent;
      const AOnApplyMergedJson: TApplyMergedDesignCallback);
    destructor Destroy; override;
  end;

implementation

uses
  Clipbrd, Graphics,
  CastleComponentSerialize, CastleFilesUtils, CastleUriUtils, CastleStringUtils,
  EditorUtils;

constructor TDesignSandboxDiffForm.CreateDialog(AOwner: TComponent;
  const ASandboxManager: TDesignSandboxManager;
  const ADesignUrl: String;
  const ACurrentDesignRoot: TComponent;
  const AGetLiveDesignJson: TGetLiveDesignJsonCallback;
  const AOnSaveSandboxes: TNotifyEvent;
  const AOnApplyMergedJson: TApplyMergedDesignCallback);
begin
  inherited CreateNew(AOwner);
  FSandboxManager := ASandboxManager;
  FDesignUrl := ADesignUrl;
  FCurrentDesignRoot := ACurrentDesignRoot;
  FGetLiveDesignJson := AGetLiveDesignJson;
  FOnSaveSandboxes := AOnSaveSandboxes;
  FOnApplyMergedJson := AOnApplyMergedJson;

  FSandboxEntries := Classes.TList.Create;
  FBaseJsonList := TStringList.Create;
  FBaseLabelList := TStringList.Create;
  FDiffItemTags := TStringList.Create;
  FCurrentReport := nil;

  Caption := 'Design Sandboxes & Visual Hierarchy / Property Diff & Merge';
  Position := poMainFormCenter;
  Width := 920;
  Height := 700;
  Constraints.MinWidth := 720;
  Constraints.MinHeight := 520;

  { 1. Top Sandboxes Group }
  GroupSandboxes := TGroupBox.Create(Self);
  GroupSandboxes.Parent := Self;
  GroupSandboxes.Align := alTop;
  GroupSandboxes.Height := 190;
  GroupSandboxes.BorderSpacing.Around := 8;
  GroupSandboxes.Caption := 'Non-Destructive Design Sandboxes (Lightweight Experimental Branches)';

  PanelSandboxButtons := TPanel.Create(Self);
  PanelSandboxButtons.Parent := GroupSandboxes;
  PanelSandboxButtons.Align := alRight;
  PanelSandboxButtons.Width := 220;
  PanelSandboxButtons.BevelOuter := bvNone;
  PanelSandboxButtons.BorderSpacing.Around := 6;

  BtnSaveSandbox := TButton.Create(Self);
  BtnSaveSandbox.Parent := PanelSandboxButtons;
  BtnSaveSandbox.Align := alTop;
  BtnSaveSandbox.Height := 28;
  BtnSaveSandbox.BorderSpacing.Bottom := 4;
  BtnSaveSandbox.Caption := '+ Save Current as Sandbox...';
  BtnSaveSandbox.OnClick := @BtnSaveSandboxClick;

  BtnActivateSandbox := TButton.Create(Self);
  BtnActivateSandbox.Parent := PanelSandboxButtons;
  BtnActivateSandbox.Align := alTop;
  BtnActivateSandbox.Height := 28;
  BtnActivateSandbox.BorderSpacing.Bottom := 4;
  BtnActivateSandbox.Caption := 'Switch / Activate Sandbox';
  BtnActivateSandbox.OnClick := @BtnActivateSandboxClick;

  BtnOverwriteSandbox := TButton.Create(Self);
  BtnOverwriteSandbox.Parent := PanelSandboxButtons;
  BtnOverwriteSandbox.Align := alTop;
  BtnOverwriteSandbox.Height := 28;
  BtnOverwriteSandbox.BorderSpacing.Bottom := 4;
  BtnOverwriteSandbox.Caption := 'Overwrite with Current';
  BtnOverwriteSandbox.OnClick := @BtnOverwriteSandboxClick;

  BtnRenameSandbox := TButton.Create(Self);
  BtnRenameSandbox.Parent := PanelSandboxButtons;
  BtnRenameSandbox.Align := alTop;
  BtnRenameSandbox.Height := 26;
  BtnRenameSandbox.BorderSpacing.Bottom := 4;
  BtnRenameSandbox.Caption := 'Rename Sandbox...';
  BtnRenameSandbox.OnClick := @BtnRenameSandboxClick;

  BtnDeleteSandbox := TButton.Create(Self);
  BtnDeleteSandbox.Parent := PanelSandboxButtons;
  BtnDeleteSandbox.Align := alTop;
  BtnDeleteSandbox.Height := 26;
  BtnDeleteSandbox.Caption := 'Delete Sandbox';
  BtnDeleteSandbox.OnClick := @BtnDeleteSandboxClick;

  ListSandboxes := TListBox.Create(Self);
  ListSandboxes.Parent := GroupSandboxes;
  ListSandboxes.Align := alClient;
  ListSandboxes.BorderSpacing.Around := 6;
  ListSandboxes.OnClick := @ListSandboxesClick;
  ListSandboxes.OnDblClick := @ListSandboxesDblClick;

  { 2. Bottom Buttons Bar }
  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 44;
  PanelBottom.BevelOuter := bvNone;
  PanelBottom.BorderSpacing.Around := 6;

  BtnCheckAll := TButton.Create(Self);
  BtnCheckAll.Parent := PanelBottom;
  BtnCheckAll.Align := alLeft;
  BtnCheckAll.Width := 96;
  BtnCheckAll.BorderSpacing.Right := 6;
  BtnCheckAll.Caption := 'Check All';
  BtnCheckAll.OnClick := @BtnCheckAllClick;

  BtnUncheckAll := TButton.Create(Self);
  BtnUncheckAll.Parent := PanelBottom;
  BtnUncheckAll.Align := alLeft;
  BtnUncheckAll.Width := 96;
  BtnUncheckAll.BorderSpacing.Right := 12;
  BtnUncheckAll.Caption := 'Uncheck All';
  BtnUncheckAll.OnClick := @BtnUncheckAllClick;

  BtnRevertChecked := TButton.Create(Self);
  BtnRevertChecked.Parent := PanelBottom;
  BtnRevertChecked.Align := alLeft;
  BtnRevertChecked.Width := 230;
  BtnRevertChecked.BorderSpacing.Right := 12;
  BtnRevertChecked.Caption := 'Revert Checked Items to Base';
  BtnRevertChecked.OnClick := @BtnRevertCheckedClick;

  BtnCopyReport := TButton.Create(Self);
  BtnCopyReport.Parent := PanelBottom;
  BtnCopyReport.Align := alLeft;
  BtnCopyReport.Width := 190;
  BtnCopyReport.Caption := 'Copy Unified Diff Report';
  BtnCopyReport.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PanelBottom;
  BtnClose.Align := alRight;
  BtnClose.Width := 100;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;
  BtnClose.Cancel := true;

  { 3. Client Visual Diff & Selective Merge Group }
  GroupDiff := TGroupBox.Create(Self);
  GroupDiff.Parent := Self;
  GroupDiff.Align := alClient;
  GroupDiff.BorderSpacing.Around := 8;
  GroupDiff.Caption := 'Visual Scene/UI Diff & Selective Merge (Compare Base vs. Current Live Design)';

  PanelDiffTop := TPanel.Create(Self);
  PanelDiffTop.Parent := GroupDiff;
  PanelDiffTop.Align := alTop;
  PanelDiffTop.Height := 58;
  PanelDiffTop.BevelOuter := bvNone;
  PanelDiffTop.BorderSpacing.Around := 6;

  LabelCompareAgainst := TLabel.Create(Self);
  LabelCompareAgainst.Parent := PanelDiffTop;
  LabelCompareAgainst.Align := alTop;
  LabelCompareAgainst.Caption := 'Compare Current Live Design against Base Source:';

  ComboBaseSource := TComboBox.Create(Self);
  ComboBaseSource.Parent := PanelDiffTop;
  ComboBaseSource.Align := alTop;
  ComboBaseSource.Style := csDropDownList;
  ComboBaseSource.BorderSpacing.Top := 2;
  ComboBaseSource.OnChange := @ComboBaseSourceChange;

  LabelDiffSummary := TLabel.Create(Self);
  LabelDiffSummary.Parent := GroupDiff;
  LabelDiffSummary.Align := alTop;
  LabelDiffSummary.BorderSpacing.Left := 8;
  LabelDiffSummary.BorderSpacing.Right := 8;
  LabelDiffSummary.BorderSpacing.Bottom := 4;
  LabelDiffSummary.Font.Bold := true;
  LabelDiffSummary.Caption := '';

  MemoDetails := TMemo.Create(Self);
  MemoDetails.Parent := GroupDiff;
  MemoDetails.Align := alBottom;
  MemoDetails.Height := 125;
  MemoDetails.BorderSpacing.Around := 6;
  MemoDetails.ReadOnly := true;
  MemoDetails.ScrollBars := ssAutoBoth;
  MemoDetails.Font.Name := 'Monospace';

  SplitterDetails := TSplitter.Create(Self);
  SplitterDetails.Parent := GroupDiff;
  SplitterDetails.Align := alBottom;
  SplitterDetails.Top := MemoDetails.Top - 4;

  CheckListDiff := TCheckListBox.Create(Self);
  CheckListDiff.Parent := GroupDiff;
  CheckListDiff.Align := alClient;
  CheckListDiff.BorderSpacing.Around := 6;
  CheckListDiff.OnSelectionChange := @CheckListDiffSelectionChange;

  RefreshSandboxesUI;
  RebuildBaseSourcesCombo;
  RecomputeDiff;
end;

destructor TDesignSandboxDiffForm.Destroy;
begin
  FreeAndNil(FCurrentReport);
  FreeAndNil(FDiffItemTags);
  FreeAndNil(FBaseLabelList);
  FreeAndNil(FBaseJsonList);
  FreeAndNil(FSandboxEntries);
  inherited;
end;

function TDesignSandboxDiffForm.CurrentDesignJson: String;
begin
  if Assigned(FGetLiveDesignJson) then
    Result := FGetLiveDesignJson()
  else
  if FCurrentDesignRoot <> nil then
    Result := ComponentToString(FCurrentDesignRoot)
  else
    Result := '';
end;

function TDesignSandboxDiffForm.SelectedSandboxEntry: TDesignSandboxEntry;
var
  Idx: Integer;
begin
  Idx := ListSandboxes.ItemIndex;
  if (Idx >= 0) and (Idx < FSandboxEntries.Count) then
    Result := TDesignSandboxEntry(FSandboxEntries[Idx])
  else
    Result := nil;
end;

procedure TDesignSandboxDiffForm.UpdateSandboxButtonStates;
var
  HasSel: Boolean;
begin
  HasSel := SelectedSandboxEntry <> nil;
  BtnActivateSandbox.Enabled := HasSel;
  BtnOverwriteSandbox.Enabled := HasSel;
  BtnRenameSandbox.Enabled := HasSel;
  BtnDeleteSandbox.Enabled := HasSel;
end;

procedure TDesignSandboxDiffForm.RefreshSandboxesUI(const SelectSandboxName: String);
var
  I, SelectIdx: Integer;
  E: TDesignSandboxEntry;
  DescSuffix: String;
begin
  ListSandboxes.Items.BeginUpdate;
  try
    ListSandboxes.Items.Clear;
    FSandboxEntries.Clear;
    if FSandboxManager <> nil then
      FSandboxManager.ListSandboxesForDesign(FDesignUrl, FSandboxEntries);

    SelectIdx := -1;
    for I := 0 to FSandboxEntries.Count - 1 do
    begin
      E := TDesignSandboxEntry(FSandboxEntries[I]);
      if E.Description <> '' then
        DescSuffix := '  —  ' + E.Description
      else
        DescSuffix := '';
      ListSandboxes.Items.Add(Format('%s   [%s, %d components, %s]%s',
        [E.Name, E.RootClassName, E.ComponentCount, E.CreatedAtIso, DescSuffix]));
      if (SelectSandboxName <> '') and SameText(E.Name, SelectSandboxName) then
        SelectIdx := I;
    end;

    if (SelectIdx < 0) and (ListSandboxes.Items.Count > 0) then
      SelectIdx := 0;
    ListSandboxes.ItemIndex := SelectIdx;
  finally
    ListSandboxes.Items.EndUpdate;
  end;
  UpdateSandboxButtonStates;
end;

procedure TDesignSandboxDiffForm.RebuildBaseSourcesCombo;
var
  PrevLabel, DiskJson: String;
  I, NewIdx: Integer;
  E: TDesignSandboxEntry;
begin
  PrevLabel := ComboBaseSource.Text;
  ComboBaseSource.Items.BeginUpdate;
  try
    ComboBaseSource.Items.Clear;
    FBaseJsonList.Clear;
    FBaseLabelList.Clear;

    if (FDesignUrl <> '') and UriFileExists(FDesignUrl) then
    begin
      try
        DiskJson := FileToString(FDesignUrl);
        ComboBaseSource.Items.Add('Saved File on Disk (' + ExtractURIName(FDesignUrl) + ')');
        FBaseJsonList.Add(DiskJson);
        FBaseLabelList.Add('Saved File (' + ExtractURIName(FDesignUrl) + ')');
      except
        { Ignore unreadable disk file }
      end;
    end;

    for I := 0 to FSandboxEntries.Count - 1 do
    begin
      E := TDesignSandboxEntry(FSandboxEntries[I]);
      ComboBaseSource.Items.Add('Sandbox: ' + E.Name + ' (' + E.CreatedAtIso + ')');
      FBaseJsonList.Add(E.SerializedJson);
      FBaseLabelList.Add('Sandbox "' + E.Name + '"');
    end;

    NewIdx := -1;
    if PrevLabel <> '' then
      NewIdx := ComboBaseSource.Items.IndexOf(PrevLabel);
    if (NewIdx < 0) and (ComboBaseSource.Items.Count > 0) then
      NewIdx := 0;
    ComboBaseSource.ItemIndex := NewIdx;
  finally
    ComboBaseSource.Items.EndUpdate;
  end;
end;

procedure TDesignSandboxDiffForm.RecomputeDiff;
var
  Idx, I, J: Integer;
  BaseJson, BaseLabel, LiveJson: String;
  CD: TDesignComponentDiff;
  PD: TDesignPropertyDiff;
begin
  FreeAndNil(FCurrentReport);
  CheckListDiff.Items.BeginUpdate;
  try
    CheckListDiff.Items.Clear;
    FDiffItemTags.Clear;

    Idx := ComboBaseSource.ItemIndex;
    if (Idx < 0) or (Idx >= FBaseJsonList.Count) then
    begin
      LabelDiffSummary.Caption :=
        'Save the design to disk or create at least one Design Sandbox above to compare changes.';
      MemoDetails.Lines.Text :=
        'No Base comparison snapshot is available yet.' + LineEnding +
        'Click "+ Save Current as Sandbox..." above to create a baseline snapshot, then modify your scene/UI to inspect and selectively revert changes.';
      BtnRevertChecked.Enabled := false;
      BtnCopyReport.Enabled := false;
      Exit;
    end;

    BaseJson := FBaseJsonList[Idx];
    BaseLabel := FBaseLabelList[Idx];
    LiveJson := CurrentDesignJson;

    FCurrentReport := TDesignDiffEngine.CompareJson(
      BaseJson, LiveJson, BaseLabel, 'Current Live Design', false);

    LabelDiffSummary.Caption := FCurrentReport.SummaryLine;

    for I := 0 to FCurrentReport.Components.Count - 1 do
    begin
      CD := FCurrentReport.Components[I];
      case CD.DiffKind of
        ddkAdded:
          begin
            CheckListDiff.Items.Add(Format('[+ Added] %s (%s)  at %s   [Check to delete added component]',
              [CD.ComponentName, CD.TargetClassName, CD.TargetHierarchyPath]));
            FDiffItemTags.Add('COMP::' + CD.ComponentName);
          end;
        ddkRemoved:
          begin
            CheckListDiff.Items.Add(Format('[- Removed] %s (%s)  was at %s   [Check to restore removed component]',
              [CD.ComponentName, CD.BaseClassName, CD.BaseHierarchyPath]));
            FDiffItemTags.Add('COMP::' + CD.ComponentName);
          end;
        ddkModified:
          begin
            CheckListDiff.Items.Add(Format('[~ Modified] %s (%s) — %d changed properties   [Check to revert entire component]',
              [CD.ComponentName, CD.DisplayClassName, CD.PropertyDiffs.Count]));
            FDiffItemTags.Add('COMP::' + CD.ComponentName);
            for J := 0 to CD.PropertyDiffs.Count - 1 do
            begin
              PD := CD.PropertyDiffs[J];
              CheckListDiff.Items.Add(Format('      [prop] %s.%s:   %s   ->   %s',
                [CD.ComponentName, PD.PropertyPath, PD.BaseValueText, PD.TargetValueText]));
              FDiffItemTags.Add('PROP::' + CD.ComponentName + '::' + PD.PropertyPath);
            end;
          end;
      end;
    end;
  finally
    CheckListDiff.Items.EndUpdate;
  end;

  MemoDetails.Lines.Text := FCurrentReport.FormatUnifiedSummary;
  BtnRevertChecked.Enabled := CheckListDiff.Items.Count > 0;
  BtnCopyReport.Enabled := FCurrentReport <> nil;
end;

procedure TDesignSandboxDiffForm.ListSandboxesClick(Sender: TObject);
begin
  UpdateSandboxButtonStates;
end;

procedure TDesignSandboxDiffForm.ListSandboxesDblClick(Sender: TObject);
begin
  if SelectedSandboxEntry <> nil then
    BtnActivateSandboxClick(Sender);
end;

procedure TDesignSandboxDiffForm.BtnSaveSandboxClick(Sender: TObject);
var
  SandboxName, SandboxDesc: String;
begin
  SandboxName := Format('Variant %d', [FSandboxEntries.Count + 1]);
  if not InputQuery('New Design Sandbox',
       'Enter a name for this experimental Design Sandbox:', SandboxName) then
    Exit;
  if Trim(SandboxName) = '' then
  begin
    ErrorBox('Sandbox name cannot be empty.');
    Exit;
  end;
  SandboxDesc := '';
  InputQuery('Design Sandbox Description (Optional)',
    'Optional short note describing what this sandbox tests:', SandboxDesc);

  FSandboxManager.CreateOrUpdateSandboxFromJson(
    SandboxName, SandboxDesc, FDesignUrl, CurrentDesignJson);
  if Assigned(FOnSaveSandboxes) then
    FOnSaveSandboxes(Self);

  RefreshSandboxesUI(SandboxName);
  RebuildBaseSourcesCombo;
  RecomputeDiff;
end;

procedure TDesignSandboxDiffForm.BtnActivateSandboxClick(Sender: TObject);
var
  E: TDesignSandboxEntry;
begin
  E := SelectedSandboxEntry;
  if (E = nil) or not Assigned(FOnApplyMergedJson) then
    Exit;

  FOnApplyMergedJson(E.SerializedJson,
    Format('Switch to Design Sandbox "%s"', [E.Name]));
  RecomputeDiff;
end;

procedure TDesignSandboxDiffForm.BtnOverwriteSandboxClick(Sender: TObject);
var
  E: TDesignSandboxEntry;
begin
  E := SelectedSandboxEntry;
  if E = nil then
    Exit;
  if not YesNoBox('Overwrite Design Sandbox',
       Format('Overwrite sandbox "%s" with the current live design state?', [E.Name])) then
    Exit;

  FSandboxManager.CreateOrUpdateSandboxFromJson(
    E.Name, E.Description, FDesignUrl, CurrentDesignJson);
  if Assigned(FOnSaveSandboxes) then
    FOnSaveSandboxes(Self);

  RefreshSandboxesUI(E.Name);
  RebuildBaseSourcesCombo;
  RecomputeDiff;
end;

procedure TDesignSandboxDiffForm.BtnRenameSandboxClick(Sender: TObject);
var
  E: TDesignSandboxEntry;
  NewName: String;
begin
  E := SelectedSandboxEntry;
  if E = nil then
    Exit;
  NewName := E.Name;
  if InputQuery('Rename Design Sandbox', 'New sandbox name:', NewName) then
  begin
    if not FSandboxManager.RenameSandbox(E.Name, NewName, FDesignUrl) then
    begin
      ErrorBox('Could not rename sandbox (name may be empty or already in use).');
      Exit;
    end;
    if Assigned(FOnSaveSandboxes) then
      FOnSaveSandboxes(Self);
    RefreshSandboxesUI(NewName);
    RebuildBaseSourcesCombo;
    RecomputeDiff;
  end;
end;

procedure TDesignSandboxDiffForm.BtnDeleteSandboxClick(Sender: TObject);
var
  E: TDesignSandboxEntry;
begin
  E := SelectedSandboxEntry;
  if E = nil then
    Exit;
  if not YesNoBox('Delete Design Sandbox',
       Format('Delete Design Sandbox "%s"?', [E.Name])) then
    Exit;

  FSandboxManager.DeleteSandbox(E.Name, FDesignUrl);
  if Assigned(FOnSaveSandboxes) then
    FOnSaveSandboxes(Self);

  RefreshSandboxesUI;
  RebuildBaseSourcesCombo;
  RecomputeDiff;
end;

procedure TDesignSandboxDiffForm.ComboBaseSourceChange(Sender: TObject);
begin
  RecomputeDiff;
end;

procedure TDesignSandboxDiffForm.CheckListDiffSelectionChange(Sender: TObject;
  User: Boolean);
var
  Idx: Integer;
begin
  Idx := CheckListDiff.ItemIndex;
  if (Idx >= 0) and (Idx < CheckListDiff.Items.Count) then
    MemoDetails.Lines.Text :=
      'Selected Diff Item:' + LineEnding +
      '  ' + Trim(CheckListDiff.Items[Idx]) + LineEnding + LineEnding +
      FCurrentReport.FormatUnifiedSummary;
end;

procedure TDesignSandboxDiffForm.BtnCheckAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to CheckListDiff.Items.Count - 1 do
    CheckListDiff.Checked[I] := true;
end;

procedure TDesignSandboxDiffForm.BtnUncheckAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to CheckListDiff.Items.Count - 1 do
    CheckListDiff.Checked[I] := false;
end;

procedure TDesignSandboxDiffForm.BtnRevertCheckedClick(Sender: TObject);
var
  BaseIdx, I: Integer;
  RevertComps, RevertProps: TStringList;
  TagStr, MergedJson: String;
begin
  BaseIdx := ComboBaseSource.ItemIndex;
  if (BaseIdx < 0) or (BaseIdx >= FBaseJsonList.Count) or
     (not Assigned(FOnApplyMergedJson)) then
    Exit;

  RevertComps := TStringList.Create;
  RevertProps := TStringList.Create;
  try
    for I := 0 to CheckListDiff.Items.Count - 1 do
      if CheckListDiff.Checked[I] and (I < FDiffItemTags.Count) then
      begin
        TagStr := FDiffItemTags[I];
        if IsPrefix('COMP::', TagStr, false) then
          RevertComps.Add(PrefixRemove('COMP::', TagStr, false))
        else
        if IsPrefix('PROP::', TagStr, false) then
          RevertProps.Add(PrefixRemove('PROP::', TagStr, false));
      end;

    if (RevertComps.Count = 0) and (RevertProps.Count = 0) then
    begin
      InfoBox('Check one or more components or properties in the diff list first.');
      Exit;
    end;

    MergedJson := TDesignDiffEngine.RevertSelectedToBase(
      FBaseJsonList[BaseIdx], CurrentDesignJson, RevertComps, RevertProps);

    FOnApplyMergedJson(MergedJson,
      Format('Selective Diff Revert from %s (%d comps, %d props)',
        [FBaseLabelList[BaseIdx], RevertComps.Count, RevertProps.Count]));
    RecomputeDiff;
  finally
    FreeAndNil(RevertProps);
    FreeAndNil(RevertComps);
  end;
end;

procedure TDesignSandboxDiffForm.BtnCopyReportClick(Sender: TObject);
begin
  if FCurrentReport = nil then
    Exit;
  Clipboard.AsText := FCurrentReport.FormatUnifiedSummary;
  InfoBox('Copied Unified Visual Design Diff report to clipboard.');
end;

end.
