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

{ Scene-Graph Non-Destructive Prefab Property Overrides Studio dialog for
  @link(TCastleTransformDesign) and @link(TCastleDesign) instances
  (Phase 285 — UE 6.0 Scene Graph Parity). }
unit FormPrefabOverrides;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Contnrs, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, Clipbrd,
  CastleClassUtils, CastleTransform, CastleUIControls, CastleControls,
  CastlePrefabOverrides, ToolPrefabOverrides;

type
  TPrefabOverridesModifiedCallback = procedure (const UndoComment: String) of object;

  TPrefabOverridesForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TPrefabOverridesModifiedCallback;
    FPrefabInstances: TComponentList;
    FActiveRows: TPrefabOverrideRowArray;
    FChildList: TStringList;

    ComboPrefabInstance: TComboBox;
    LabelPrefabSummary: TLabel;

    { Add / Edit Override strip }
    GroupQuickSet: TGroupBox;
    ComboChildName: TComboBox;
    ComboPropPath: TComboBox;
    EditOverrideValue: TEdit;
    ButtonApplyOverride: TButton;
    ButtonCaptureLive: TButton;

    { Active Overrides table }
    ListOverrides: TListView;

    { Bottom action bar }
    ButtonRevertSelected: TButton;
    ButtonRevertAll: TButton;
    ButtonPromoteToSource: TButton;
    ButtonCopySummary: TButton;
    ButtonClose: TButton;

    procedure BuildUi;
    procedure PopulatePrefabInstances(const InitialSelection: TComponent);
    function SelectedPrefabInstance: TCastleComponent;
    procedure RefreshSelectedPrefabView;
    procedure RefreshChildPropPaths;
    procedure RefreshCurrentPropertyValuePreview;

    procedure ComboPrefabInstanceChange(Sender: TObject);
    procedure ComboChildNameChange(Sender: TObject);
    procedure ComboPropPathChange(Sender: TObject);
    procedure ListOverridesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ButtonApplyOverrideClick(Sender: TObject);
    procedure ButtonCaptureLiveClick(Sender: TObject);
    procedure ButtonRevertSelectedClick(Sender: TObject);
    procedure ButtonRevertAllClick(Sender: TObject);
    procedure ButtonPromoteToSourceClick(Sender: TObject);
    procedure ButtonCopySummaryClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner: TComponent;
      const AInitialSelection: TComponent;
      const AOnModified: TPrefabOverridesModifiedCallback);
    destructor Destroy; override;
  end;

implementation

uses
  FpJson, CastleUtils, CastleViewport;

constructor TPrefabOverridesForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner: TComponent;
  const AInitialSelection: TComponent;
  const AOnModified: TPrefabOverridesModifiedCallback);
begin
  inherited CreateNew(AOwner, 0);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FPrefabInstances := TComponentList.Create(false);
  FChildList := TStringList.Create;

  Caption := 'Scene-Graph Non-Destructive Prefab Property Overrides (TCastleTransformDesign / TCastleDesign)';
  Position := poMainFormCenter;
  Width := 940;
  Height := 600;
  Constraints.MinWidth := 780;
  Constraints.MinHeight := 480;

  BuildUi;
  PopulatePrefabInstances(AInitialSelection);
end;

destructor TPrefabOverridesForm.Destroy;
begin
  FreeAndNil(FChildList);
  FreeAndNil(FPrefabInstances);
  inherited;
end;

procedure TPrefabOverridesForm.BuildUi;
var
  TopPanel, TopRow, QuickRow, BottomPanel: TPanel;
  LblInst, LblChild, LblProp, LblVal: TLabel;
  Col: TListColumn;
begin
  TopPanel := TPanel.Create(Self);
  TopPanel.Parent := Self;
  TopPanel.Align := alTop;
  TopPanel.AutoSize := true;
  TopPanel.BevelOuter := bvNone;
  TopPanel.BorderSpacing.Around := 8;

  TopRow := TPanel.Create(Self);
  TopRow.Parent := TopPanel;
  TopRow.Align := alTop;
  TopRow.Height := 32;
  TopRow.BevelOuter := bvNone;

  LblInst := TLabel.Create(Self);
  LblInst.Parent := TopRow;
  LblInst.Align := alLeft;
  LblInst.Layout := tlCenter;
  LblInst.Caption := 'Prefab Instance:';
  LblInst.BorderSpacing.Right := 6;

  ButtonCaptureLive := TButton.Create(Self);
  ButtonCaptureLive.Parent := TopRow;
  ButtonCaptureLive.Align := alRight;
  ButtonCaptureLive.AutoSize := true;
  ButtonCaptureLive.Caption := 'Capture Live In-Memory Edits';
  ButtonCaptureLive.OnClick := @ButtonCaptureLiveClick;

  ComboPrefabInstance := TComboBox.Create(Self);
  ComboPrefabInstance.Parent := TopRow;
  ComboPrefabInstance.Align := alClient;
  ComboPrefabInstance.Style := csDropDownList;
  ComboPrefabInstance.BorderSpacing.Right := 8;
  ComboPrefabInstance.OnChange := @ComboPrefabInstanceChange;

  LabelPrefabSummary := TLabel.Create(Self);
  LabelPrefabSummary.Parent := TopPanel;
  LabelPrefabSummary.Align := alTop;
  LabelPrefabSummary.Font.Style := [fsBold];
  LabelPrefabSummary.BorderSpacing.Top := 6;
  LabelPrefabSummary.Caption := 'Select a TCastleTransformDesign or TCastleDesign instance.';

  GroupQuickSet := TGroupBox.Create(Self);
  GroupQuickSet.Parent := Self;
  GroupQuickSet.Align := alTop;
  GroupQuickSet.Height := 68;
  GroupQuickSet.Caption := 'Add or Update Per-Instance Child Property Override (Without Unlinking Url)';
  GroupQuickSet.BorderSpacing.Left := 8;
  GroupQuickSet.BorderSpacing.Right := 8;
  GroupQuickSet.BorderSpacing.Bottom := 6;

  QuickRow := TPanel.Create(Self);
  QuickRow.Parent := GroupQuickSet;
  QuickRow.Align := alClient;
  QuickRow.BevelOuter := bvNone;
  QuickRow.BorderSpacing.Around := 6;

  LblChild := TLabel.Create(Self);
  LblChild.Parent := QuickRow;
  LblChild.Align := alLeft;
  LblChild.Layout := tlCenter;
  LblChild.Caption := 'Child:';
  LblChild.BorderSpacing.Right := 4;

  ComboChildName := TComboBox.Create(Self);
  ComboChildName.Parent := QuickRow;
  ComboChildName.Align := alLeft;
  ComboChildName.Width := 180;
  ComboChildName.Style := csDropDownList;
  ComboChildName.BorderSpacing.Right := 10;
  ComboChildName.OnChange := @ComboChildNameChange;

  LblProp := TLabel.Create(Self);
  LblProp.Parent := QuickRow;
  LblProp.Align := alLeft;
  LblProp.Layout := tlCenter;
  LblProp.Caption := 'Property:';
  LblProp.BorderSpacing.Right := 4;

  ComboPropPath := TComboBox.Create(Self);
  ComboPropPath.Parent := QuickRow;
  ComboPropPath.Align := alLeft;
  ComboPropPath.Width := 230;
  ComboPropPath.Style := csDropDown;
  ComboPropPath.BorderSpacing.Right := 10;
  ComboPropPath.OnChange := @ComboPropPathChange;

  LblVal := TLabel.Create(Self);
  LblVal.Parent := QuickRow;
  LblVal.Align := alLeft;
  LblVal.Layout := tlCenter;
  LblVal.Caption := 'Value:';
  LblVal.BorderSpacing.Right := 4;

  ButtonApplyOverride := TButton.Create(Self);
  ButtonApplyOverride.Parent := QuickRow;
  ButtonApplyOverride.Align := alRight;
  ButtonApplyOverride.AutoSize := true;
  ButtonApplyOverride.Caption := 'Set Override';
  ButtonApplyOverride.OnClick := @ButtonApplyOverrideClick;

  EditOverrideValue := TEdit.Create(Self);
  EditOverrideValue.Parent := QuickRow;
  EditOverrideValue.Align := alClient;
  EditOverrideValue.BorderSpacing.Right := 8;

  BottomPanel := TPanel.Create(Self);
  BottomPanel.Parent := Self;
  BottomPanel.Align := alBottom;
  BottomPanel.Height := 44;
  BottomPanel.BevelOuter := bvNone;
  BottomPanel.BorderSpacing.Around := 6;

  ButtonRevertSelected := TButton.Create(Self);
  ButtonRevertSelected.Parent := BottomPanel;
  ButtonRevertSelected.Align := alLeft;
  ButtonRevertSelected.AutoSize := true;
  ButtonRevertSelected.Caption := 'Revert Selected Override to Prefab';
  ButtonRevertSelected.BorderSpacing.Right := 6;
  ButtonRevertSelected.OnClick := @ButtonRevertSelectedClick;

  ButtonRevertAll := TButton.Create(Self);
  ButtonRevertAll.Parent := BottomPanel;
  ButtonRevertAll.Align := alLeft;
  ButtonRevertAll.AutoSize := true;
  ButtonRevertAll.Caption := 'Revert All Overrides';
  ButtonRevertAll.BorderSpacing.Right := 12;
  ButtonRevertAll.OnClick := @ButtonRevertAllClick;

  ButtonPromoteToSource := TButton.Create(Self);
  ButtonPromoteToSource.Parent := BottomPanel;
  ButtonPromoteToSource.Align := alLeft;
  ButtonPromoteToSource.AutoSize := true;
  ButtonPromoteToSource.Caption := 'Apply Overrides to Source Prefab File...';
  ButtonPromoteToSource.BorderSpacing.Right := 8;
  ButtonPromoteToSource.OnClick := @ButtonPromoteToSourceClick;

  ButtonCopySummary := TButton.Create(Self);
  ButtonCopySummary.Parent := BottomPanel;
  ButtonCopySummary.Align := alLeft;
  ButtonCopySummary.AutoSize := true;
  ButtonCopySummary.Caption := 'Copy Overrides JSON';
  ButtonCopySummary.OnClick := @ButtonCopySummaryClick;

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := BottomPanel;
  ButtonClose.Align := alRight;
  ButtonClose.Width := 96;
  ButtonClose.Caption := 'Close';
  ButtonClose.Cancel := true;
  ButtonClose.OnClick := @ButtonCloseClick;

  ListOverrides := TListView.Create(Self);
  ListOverrides.Parent := Self;
  ListOverrides.Align := alClient;
  ListOverrides.BorderSpacing.Around := 8;
  ListOverrides.ViewStyle := vsReport;
  ListOverrides.RowSelect := true;
  ListOverrides.ReadOnly := true;
  ListOverrides.OnSelectItem := @ListOverridesSelectItem;

  Col := ListOverrides.Columns.Add; Col.Caption := 'Child Component'; Col.Width := 180;
  Col := ListOverrides.Columns.Add; Col.Caption := 'Class'; Col.Width := 155;
  Col := ListOverrides.Columns.Add; Col.Caption := 'Property Path [Overridden]'; Col.Width := 230;
  Col := ListOverrides.Columns.Add; Col.Caption := 'Prefab Source Default'; Col.Width := 165;
  Col := ListOverrides.Columns.Add; Col.Caption := 'Instance Override Value'; Col.Width := 175;
end;

procedure TPrefabOverridesForm.PopulatePrefabInstances(const InitialSelection: TComponent);

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if TPrefabOverrideManager.IsSupportedPrefabInstance(C) and
       (FPrefabInstances.IndexOf(C) = -1) then
      FPrefabInstances.Add(C);

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end else
    if C is TCastleViewport then
    begin
      for I := 0 to TCastleViewport(C).ControlsCount - 1 do
        Walk(TCastleViewport(C).Controls[I]);
      Walk(TCastleViewport(C).Items);
    end else
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Walk(UI.Controls[I]);
    end;
  end;

var
  I, SelIdx, OvCnt: Integer;
  Inst: TComponent;
begin
  FPrefabInstances.Clear;
  ComboPrefabInstance.Items.Clear;
  Walk(FRootComponent);

  SelIdx := 0;
  for I := 0 to FPrefabInstances.Count - 1 do
  begin
    Inst := FPrefabInstances[I];
    OvCnt := TPrefabOverrideManager.ActiveOverrideCount(Inst);
    ComboPrefabInstance.Items.Add(Format('%s (%s) — %s [%d override(s)]',
      [Inst.Name, Inst.ClassName, TPrefabOverrideManager.GetPrefabUrl(Inst), OvCnt]));
    if Inst = InitialSelection then
      SelIdx := I;
  end;

  if ComboPrefabInstance.Items.Count > 0 then
    ComboPrefabInstance.ItemIndex := SelIdx;
  RefreshSelectedPrefabView;
end;

function TPrefabOverridesForm.SelectedPrefabInstance: TCastleComponent;
var
  Idx: Integer;
begin
  Idx := ComboPrefabInstance.ItemIndex;
  if (Idx >= 0) and (Idx < FPrefabInstances.Count) and
     (FPrefabInstances[Idx] is TCastleComponent) then
    Result := TCastleComponent(FPrefabInstances[Idx])
  else
    Result := nil;
end;

procedure TPrefabOverridesForm.RefreshSelectedPrefabView;
var
  Inst: TCastleComponent;
  HasInst: Boolean;
  I: Integer;
  Item: TListItem;
begin
  Inst := SelectedPrefabInstance;
  HasInst := Inst <> nil;

  ComboChildName.Enabled := HasInst;
  ComboPropPath.Enabled := HasInst;
  EditOverrideValue.Enabled := HasInst;
  ButtonApplyOverride.Enabled := HasInst;
  ButtonCaptureLive.Enabled := HasInst;
  ButtonRevertSelected.Enabled := HasInst;
  ButtonRevertAll.Enabled := HasInst;
  ButtonPromoteToSource.Enabled := HasInst;
  ButtonCopySummary.Enabled := HasInst;

  FChildList.Clear;
  ComboChildName.Items.Clear;
  ListOverrides.Items.Clear;
  SetLength(FActiveRows, 0);

  if not HasInst then
  begin
    LabelPrefabSummary.Caption :=
      'No TCastleTransformDesign or TCastleDesign instances found in this design.';
    Exit;
  end;

  TPrefabOverrideManager.ListPrefabChildren(Inst, FChildList);
  for I := 0 to FChildList.Count - 1 do
    ComboChildName.Items.Add(FChildList[I]);
  if ComboChildName.Items.Count > 0 then
    ComboChildName.ItemIndex := 0;
  RefreshChildPropPaths;

  TPrefabOverrideManager.DescribeActiveOverrides(Inst, FActiveRows);
  LabelPrefabSummary.Caption := Format(
    'Instance: %s  |  Source URL: %s  |  Loaded Children: %d  |  Active Overrides: %d',
    [Inst.Name, TPrefabOverrideManager.GetPrefabUrl(Inst),
     FChildList.Count, Length(FActiveRows)]);

  ListOverrides.Items.BeginUpdate;
  try
    for I := 0 to High(FActiveRows) do
    begin
      Item := ListOverrides.Items.Add;
      Item.Caption := FActiveRows[I].ChildName;
      Item.SubItems.Add(FActiveRows[I].ChildClass);
      Item.SubItems.Add(FActiveRows[I].PropPath);
      Item.SubItems.Add(FActiveRows[I].SourceDefaultText);
      Item.SubItems.Add(FActiveRows[I].OverriddenValueText);
    end;
  finally
    ListOverrides.Items.EndUpdate;
  end;

  ButtonRevertSelected.Enabled := Length(FActiveRows) > 0;
  ButtonRevertAll.Enabled := Length(FActiveRows) > 0;
  ButtonPromoteToSource.Enabled := Length(FActiveRows) > 0;
end;

procedure TPrefabOverridesForm.RefreshChildPropPaths;
var
  Idx: Integer;
  ChildComp: TComponent;
  Paths: TStringList;
begin
  ComboPropPath.Items.Clear;
  Idx := ComboChildName.ItemIndex;
  if (Idx < 0) or (Idx >= FChildList.Count) then
    Exit;
  ChildComp := TComponent(FChildList.Objects[Idx]);
  Paths := TStringList.Create;
  try
    TPrefabOverrideManager.ListEditablePropertyPaths(ChildComp, Paths);
    ComboPropPath.Items.Assign(Paths);
    if ComboPropPath.Items.Count > 0 then
      ComboPropPath.ItemIndex := 0;
    RefreshCurrentPropertyValuePreview;
  finally
    FreeAndNil(Paths);
  end;
end;

procedure TPrefabOverridesForm.RefreshCurrentPropertyValuePreview;
var
  Idx: Integer;
  ChildComp: TComponent;
  ValJson: TJSONData;
begin
  Idx := ComboChildName.ItemIndex;
  if (Idx < 0) or (Idx >= FChildList.Count) or (Trim(ComboPropPath.Text) = '') then
    Exit;
  ChildComp := TComponent(FChildList.Objects[Idx]);
  ValJson := ReadRttiPropertyPathJson(ChildComp, Trim(ComboPropPath.Text));
  if ValJson <> nil then
  try
    if ValJson.JsonType = jtString then
      EditOverrideValue.Text := ValJson.AsString
    else if ValJson is TJSONFloatNumber then
      EditOverrideValue.Text := FloatToStrDot(ValJson.AsFloat)
    else
      EditOverrideValue.Text := ValJson.AsJSON;
  finally
    FreeAndNil(ValJson);
  end;
end;

procedure TPrefabOverridesForm.ComboPrefabInstanceChange(Sender: TObject);
begin
  RefreshSelectedPrefabView;
end;

procedure TPrefabOverridesForm.ComboChildNameChange(Sender: TObject);
begin
  RefreshChildPropPaths;
end;

procedure TPrefabOverridesForm.ComboPropPathChange(Sender: TObject);
begin
  RefreshCurrentPropertyValuePreview;
end;

procedure TPrefabOverridesForm.ListOverridesSelectItem(Sender: TObject;
  Item: TListItem; Selected: Boolean);
var
  RowIdx, CIdx: Integer;
begin
  if not Selected then
    Exit;
  RowIdx := ListOverrides.ItemIndex;
  if (RowIdx < 0) or (RowIdx > High(FActiveRows)) then
    Exit;
  CIdx := ComboChildName.Items.IndexOf(FActiveRows[RowIdx].ChildName);
  if CIdx >= 0 then
  begin
    ComboChildName.ItemIndex := CIdx;
    RefreshChildPropPaths;
    ComboPropPath.Text := FActiveRows[RowIdx].PropPath;
    RefreshCurrentPropertyValuePreview;
  end;
end;

procedure TPrefabOverridesForm.ButtonApplyOverrideClick(Sender: TObject);
var
  Inst: TCastleComponent;
  ChildName, PropPath: String;
begin
  Inst := SelectedPrefabInstance;
  ChildName := Trim(ComboChildName.Text);
  PropPath := Trim(ComboPropPath.Text);
  if (Inst = nil) or (ChildName = '') or (PropPath = '') then
    Exit;
  if TPrefabOverrideManager.SetOverrideFromString(
       Inst, FDesignOwner, ChildName, PropPath, EditOverrideValue.Text) then
  begin
    if Assigned(FOnModified) then
      FOnModified(Format('Set Prefab Override %s.%s on %s', [ChildName, PropPath, Inst.Name]));
    PopulatePrefabInstances(Inst);
  end else
    MessageDlg('Invalid Property or Value',
      Format('Could not apply "%s" to %s.%s — check property path and value syntax.',
        [EditOverrideValue.Text, ChildName, PropPath]),
      mtWarning, [mbOK], 0);
end;

procedure TPrefabOverridesForm.ButtonCaptureLiveClick(Sender: TObject);
var
  Inst: TCastleComponent;
  Cnt: Integer;
begin
  Inst := SelectedPrefabInstance;
  if Inst = nil then
    Exit;
  Cnt := TPrefabOverrideManager.CaptureLiveEditsFromInstance(Inst, FDesignOwner);
  if Assigned(FOnModified) then
    FOnModified(Format('Capture %d Prefab Override(s) on %s', [Cnt, Inst.Name]));
  PopulatePrefabInstances(Inst);
end;

procedure TPrefabOverridesForm.ButtonRevertSelectedClick(Sender: TObject);
var
  Inst: TCastleComponent;
  RowIdx: Integer;
begin
  Inst := SelectedPrefabInstance;
  RowIdx := ListOverrides.ItemIndex;
  if (Inst = nil) or (RowIdx < 0) or (RowIdx > High(FActiveRows)) then
    Exit;
  if TPrefabOverrideManager.RevertSingleOverride(
       Inst, FActiveRows[RowIdx].ChildName, FActiveRows[RowIdx].PropPath) then
  begin
    if Assigned(FOnModified) then
      FOnModified(Format('Revert Prefab Override %s.%s on %s',
        [FActiveRows[RowIdx].ChildName, FActiveRows[RowIdx].PropPath, Inst.Name]));
    PopulatePrefabInstances(Inst);
  end;
end;

procedure TPrefabOverridesForm.ButtonRevertAllClick(Sender: TObject);
var
  Inst: TCastleComponent;
begin
  Inst := SelectedPrefabInstance;
  if Inst = nil then
    Exit;
  if TPrefabOverrideManager.RevertAllOverrides(Inst) then
  begin
    if Assigned(FOnModified) then
      FOnModified('Revert All Prefab Overrides on ' + Inst.Name);
    PopulatePrefabInstances(Inst);
  end;
end;

procedure TPrefabOverridesForm.ButtonPromoteToSourceClick(Sender: TObject);
var
  Inst: TCastleComponent;
  SavedUrl: String;
begin
  Inst := SelectedPrefabInstance;
  if Inst = nil then
    Exit;
  if MessageDlg('Apply Overrides to Source Prefab',
       Format('Write all %d active override(s) permanently into source prefab "%s"?' + LineEnding +
              'Every instance referencing this URL will inherit the promoted values.',
              [Length(FActiveRows), TPrefabOverrideManager.GetPrefabUrl(Inst)]),
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  if TPrefabOverrideManager.ApplyOverridesToSourcePrefab(Inst, SavedUrl) then
  begin
    TPrefabOverrideManager.ReapplyAllInHierarchy(FRootComponent);
    if Assigned(FOnModified) then
      FOnModified('Apply Overrides to Source Prefab ' + SavedUrl);
    PopulatePrefabInstances(Inst);
  end else
    MessageDlg('Apply Failed',
      'Could not save overrides back to source prefab file.', mtError, [mbOK], 0);
end;

procedure TPrefabOverridesForm.ButtonCopySummaryClick(Sender: TObject);
var
  Inst: TCastleComponent;
  Ov: TCastlePrefabOverride;
begin
  Inst := SelectedPrefabInstance;
  if Inst = nil then
    Exit;
  Ov := TPrefabOverrideManager.FindOverrideComponent(Inst);
  if (Ov <> nil) and (Ov.OverridesJson <> '') then
    Clipboard.AsText := Ov.OverridesJson
  else
    Clipboard.AsText := '{}';
end;

procedure TPrefabOverridesForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
