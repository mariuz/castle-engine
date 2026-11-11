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

{ Interactive Variant Manager / Scene Configuration Sets & Live Preset
  Switcher (@link(TVariantManagerForm))
  (Phase 296 — UE 5.9 / 6.0 Variant Manager Parity). }
unit FormVariantManager;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, StrUtils, Forms, Controls, StdCtrls, ExtCtrls,
  ComCtrls, Dialogs, Clipbrd,
  CastleUtils, CastleComponentSerialize, CastleVariantSet, ToolVariantManager;

type
  TVariantManagerModifiedCallback = procedure (const UndoComment: String) of object;
  TVariantManagerRefreshViewportCallback = procedure of object;

  TVariantManagerForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FSelectedComponent: TComponent;
    FOnModified: TVariantManagerModifiedCallback;
    FOnRefreshViewport: TVariantManagerRefreshViewportCallback;

    FBaselineDiffJson: String;

    { Top Toolbar }
    ButtonAddSet: TButton;
    ButtonAddVariant: TButton;
    ButtonStartDiff: TButton;
    ButtonCommitDiff: TButton;
    ButtonCaptureSelected: TButton;
    ButtonCopyMarkdown: TButton;

    { Left Variant Sets & Variants Switcher }
    ListBoxSets: TListBox;
    ListBoxVariants: TListBox;
    ButtonActivateVariant: TButton;

    { Center Bindings Grid + Inline Binding Editor }
    ListViewBindings: TListView;
    EditCompName: TEdit;
    EditPropPath: TEdit;
    EditValueJson: TEdit;
    ButtonSaveBinding: TButton;

    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    function EnsureMgr: TCastleVariantSetManager;
    function CurrentSetName: String;
    function CurrentVariantName: String;
    procedure RefreshSets(const AKeepSetName: String = '');
    procedure RefreshVariants(const AKeepVariantName: String = '');
    procedure RefreshBindings;
    procedure NotifyModified(const Comment: String);

    procedure ButtonAddSetClick(Sender: TObject);
    procedure ButtonAddVariantClick(Sender: TObject);
    procedure ButtonStartDiffClick(Sender: TObject);
    procedure ButtonCommitDiffClick(Sender: TObject);
    procedure ButtonCaptureSelectedClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure ListBoxSetsSelectionChange(Sender: TObject; User: Boolean);
    procedure ListBoxVariantsSelectionChange(Sender: TObject; User: Boolean);
    procedure ButtonActivateVariantClick(Sender: TObject);
    procedure ListViewBindingsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ButtonSaveBindingClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
      const AOnModified: TVariantManagerModifiedCallback;
      const AOnRefreshViewport: TVariantManagerRefreshViewportCallback);
  end;

implementation

constructor TVariantManagerForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
  const AOnModified: TVariantManagerModifiedCallback;
  const AOnRefreshViewport: TVariantManagerRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FSelectedComponent := ASelectedComponent;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FBaselineDiffJson := '';
  BuildUi;
  if (FSelectedComponent <> nil) and (FSelectedComponent.Name <> '') then
    EditCompName.Text := FSelectedComponent.Name;
  RefreshSets;
end;

procedure TVariantManagerForm.BuildUi;
var
  PanelTop, PanelBottom, PanelLeft, PanelRightBottom: TPanel;
  Col: TListColumn;
  Lbl: TLabel;
begin
  Caption := 'Variant Manager / Scene Configuration Sets & Live Preset Switcher (UE 5.9 / 6.0 Parity)';
  Width := 1060;
  Height := 670;
  Position := poMainFormCenter;
  Constraints.MinWidth := 900;
  Constraints.MinHeight := 560;

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 44;
  PanelTop.BevelOuter := bvNone;

  ButtonAddSet := TButton.Create(Self);
  ButtonAddSet.Parent := PanelTop;
  ButtonAddSet.SetBounds(10, 7, 138, 30);
  ButtonAddSet.Caption := '+ Add Variant Set';
  ButtonAddSet.OnClick := @ButtonAddSetClick;

  ButtonAddVariant := TButton.Create(Self);
  ButtonAddVariant.Parent := PanelTop;
  ButtonAddVariant.SetBounds(154, 7, 128, 30);
  ButtonAddVariant.Caption := '+ Add Variant';
  ButtonAddVariant.OnClick := @ButtonAddVariantClick;

  ButtonStartDiff := TButton.Create(Self);
  ButtonStartDiff.Parent := PanelTop;
  ButtonStartDiff.SetBounds(288, 7, 165, 30);
  ButtonStartDiff.Caption := '1. Snapshot Baseline';
  ButtonStartDiff.OnClick := @ButtonStartDiffClick;

  ButtonCommitDiff := TButton.Create(Self);
  ButtonCommitDiff.Parent := PanelTop;
  ButtonCommitDiff.SetBounds(459, 7, 178, 30);
  ButtonCommitDiff.Caption := '2. Capture Diff -> Variant';
  ButtonCommitDiff.Enabled := false;
  ButtonCommitDiff.OnClick := @ButtonCommitDiffClick;

  ButtonCaptureSelected := TButton.Create(Self);
  ButtonCaptureSelected.Parent := PanelTop;
  ButtonCaptureSelected.SetBounds(643, 7, 195, 30);
  ButtonCaptureSelected.Caption := 'Snapshot Selected Component';
  ButtonCaptureSelected.OnClick := @ButtonCaptureSelectedClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.SetBounds(844, 7, 165, 30);
  ButtonCopyMarkdown.Caption := 'Copy Matrix Markdown';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 38;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.SetBounds(12, 10, 840, 18);
  LabelStatus.Caption := 'Ready.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Align := alRight;
  ButtonClose.Width := 96;
  ButtonClose.BorderSpacing.Around := 5;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := Self;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 280;
  PanelLeft.BorderSpacing.Around := 6;
  PanelLeft.BevelOuter := bvLowered;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 8, 200, 18);
  Lbl.Caption := 'Variant Sets (e.g. Lighting):';

  ListBoxSets := TListBox.Create(Self);
  ListBoxSets.Parent := PanelLeft;
  ListBoxSets.SetBounds(10, 28, 258, 210);
  ListBoxSets.OnSelectionChange := @ListBoxSetsSelectionChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 248, 220, 18);
  Lbl.Caption := 'Variants in Selected Set:';

  ListBoxVariants := TListBox.Create(Self);
  ListBoxVariants.Parent := PanelLeft;
  ListBoxVariants.SetBounds(10, 268, 258, 240);
  ListBoxVariants.OnSelectionChange := @ListBoxVariantsSelectionChange;

  ButtonActivateVariant := TButton.Create(Self);
  ButtonActivateVariant.Parent := PanelLeft;
  ButtonActivateVariant.SetBounds(10, 518, 258, 36);
  ButtonActivateVariant.Caption := 'Switch Viewport to Selected Variant';
  ButtonActivateVariant.OnClick := @ButtonActivateVariantClick;

  PanelRightBottom := TPanel.Create(Self);
  PanelRightBottom.Parent := Self;
  PanelRightBottom.Align := alBottom;
  PanelRightBottom.Height := 52;
  PanelRightBottom.BorderSpacing.Around := 6;
  PanelRightBottom.BevelOuter := bvLowered;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRightBottom;
  Lbl.SetBounds(10, 16, 70, 18);
  Lbl.Caption := 'Component:';

  EditCompName := TEdit.Create(Self);
  EditCompName.Parent := PanelRightBottom;
  EditCompName.SetBounds(86, 12, 165, 24);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRightBottom;
  Lbl.SetBounds(260, 16, 65, 18);
  Lbl.Caption := 'Property:';

  EditPropPath := TEdit.Create(Self);
  EditPropPath.Parent := PanelRightBottom;
  EditPropPath.SetBounds(326, 12, 215, 24);
  EditPropPath.Text := 'Intensity';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRightBottom;
  Lbl.SetBounds(550, 16, 68, 18);
  Lbl.Caption := 'JSON Val:';

  EditValueJson := TEdit.Create(Self);
  EditValueJson.Parent := PanelRightBottom;
  EditValueJson.SetBounds(620, 12, 190, 24);
  EditValueJson.Text := '1.0';

  ButtonSaveBinding := TButton.Create(Self);
  ButtonSaveBinding.Parent := PanelRightBottom;
  ButtonSaveBinding.SetBounds(818, 10, 190, 28);
  ButtonSaveBinding.Caption := 'Add / Update Binding';
  ButtonSaveBinding.OnClick := @ButtonSaveBindingClick;

  ListViewBindings := TListView.Create(Self);
  ListViewBindings.Parent := Self;
  ListViewBindings.Align := alClient;
  ListViewBindings.BorderSpacing.Around := 6;
  ListViewBindings.ViewStyle := vsReport;
  ListViewBindings.RowSelect := true;
  ListViewBindings.ReadOnly := true;
  ListViewBindings.OnSelectItem := @ListViewBindingsSelectItem;

  Col := ListViewBindings.Columns.Add;
  Col.Caption := 'Component';
  Col.Width := 180;

  Col := ListViewBindings.Columns.Add;
  Col.Caption := 'Dotted Property Path';
  Col.Width := 230;

  Col := ListViewBindings.Columns.Add;
  Col.Caption := 'Stored Variant Value';
  Col.Width := 170;

  Col := ListViewBindings.Columns.Add;
  Col.Caption := 'Current Live Value';
  Col.Width := 170;
end;

function TVariantManagerForm.EnsureMgr: TCastleVariantSetManager;
begin
  Result := TVariantManagerHelper.EnsureManagerInDesign(FRootComponent, FDesignOwner);
end;

function TVariantManagerForm.CurrentSetName: String;
var
  Mgr: TCastleVariantSetManager;
begin
  Result := '';
  Mgr := TVariantManagerHelper.FindManagerInDesign(FRootComponent);
  if (Mgr <> nil) and (ListBoxSets.ItemIndex >= 0) and
     (ListBoxSets.ItemIndex < Mgr.SetCount) then
    Result := Mgr.GetSet(ListBoxSets.ItemIndex).SetName;
end;

function TVariantManagerForm.CurrentVariantName: String;
var
  Mgr: TCastleVariantSetManager;
  Grp: TVariantSetGroup;
begin
  Result := '';
  Mgr := TVariantManagerHelper.FindManagerInDesign(FRootComponent);
  if (Mgr <> nil) and (ListBoxSets.ItemIndex >= 0) and
     (ListBoxSets.ItemIndex < Mgr.SetCount) then
  begin
    Grp := Mgr.GetSet(ListBoxSets.ItemIndex);
    if (ListBoxVariants.ItemIndex >= 0) and
       (ListBoxVariants.ItemIndex < Length(Grp.Variants)) then
      Result := Grp.Variants[ListBoxVariants.ItemIndex].VariantName;
  end;
end;

procedure TVariantManagerForm.NotifyModified(const Comment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(Comment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TVariantManagerForm.RefreshSets(const AKeepSetName: String);
var
  Mgr: TCastleVariantSetManager;
  I, SelIdx: Integer;
  Grp: TVariantSetGroup;
begin
  Mgr := TVariantManagerHelper.FindManagerInDesign(FRootComponent);
  SelIdx := 0;
  ListBoxSets.Items.BeginUpdate;
  try
    ListBoxSets.Items.Clear;
    if Mgr <> nil then
      for I := 0 to Mgr.SetCount - 1 do
      begin
        Grp := Mgr.GetSet(I);
        ListBoxSets.Items.Add(Format('%s [Active: %s]',
          [Grp.SetName, IfThen(Grp.ActiveVariantName <> '', Grp.ActiveVariantName, '-')]));
        if (AKeepSetName <> '') and SameText(Grp.SetName, AKeepSetName) then
          SelIdx := I;
      end;
    if ListBoxSets.Items.Count > 0 then
      ListBoxSets.ItemIndex := Clamped(SelIdx, 0, ListBoxSets.Items.Count - 1);
  finally
    ListBoxSets.Items.EndUpdate;
  end;
  RefreshVariants;
end;

procedure TVariantManagerForm.RefreshVariants(const AKeepVariantName: String);
var
  Mgr: TCastleVariantSetManager;
  Grp: TVariantSetGroup;
  I, SelIdx: Integer;
begin
  Mgr := TVariantManagerHelper.FindManagerInDesign(FRootComponent);
  SelIdx := 0;
  ListBoxVariants.Items.BeginUpdate;
  try
    ListBoxVariants.Items.Clear;
    if (Mgr <> nil) and (ListBoxSets.ItemIndex >= 0) and
       (ListBoxSets.ItemIndex < Mgr.SetCount) then
    begin
      Grp := Mgr.GetSet(ListBoxSets.ItemIndex);
      for I := 0 to High(Grp.Variants) do
      begin
        ListBoxVariants.Items.Add(Format('%s (%d bindings)%s',
          [Grp.Variants[I].VariantName, Length(Grp.Variants[I].Bindings),
           IfThen(SameText(Grp.Variants[I].VariantName, Grp.ActiveVariantName), ' *ACTIVE*', '')]));
        if (AKeepVariantName <> '') and SameText(Grp.Variants[I].VariantName, AKeepVariantName) then
          SelIdx := I;
      end;
      if ListBoxVariants.Items.Count > 0 then
        ListBoxVariants.ItemIndex := Clamped(SelIdx, 0, ListBoxVariants.Items.Count - 1);
    end;
  finally
    ListBoxVariants.Items.EndUpdate;
  end;
  RefreshBindings;
end;

procedure TVariantManagerForm.RefreshBindings;
var
  Mgr: TCastleVariantSetManager;
  Grp: TVariantSetGroup;
  Opt: TVariantOption;
  I: Integer;
  It: TListItem;
  Comp: TComponent;
  LiveVal: String;
begin
  ListViewBindings.Items.BeginUpdate;
  try
    ListViewBindings.Items.Clear;
    Mgr := TVariantManagerHelper.FindManagerInDesign(FRootComponent);
    if (Mgr <> nil) and (ListBoxSets.ItemIndex >= 0) and
       (ListBoxSets.ItemIndex < Mgr.SetCount) then
    begin
      Grp := Mgr.GetSet(ListBoxSets.ItemIndex);
      if (ListBoxVariants.ItemIndex >= 0) and
         (ListBoxVariants.ItemIndex < Length(Grp.Variants)) then
      begin
        Opt := Grp.Variants[ListBoxVariants.ItemIndex];
        for I := 0 to High(Opt.Bindings) do
        begin
          Comp := TCastleVariantSetManager.FindComponentInHierarchy(
            FRootComponent, Opt.Bindings[I].ComponentName);
          if Comp <> nil then
            LiveVal := TCastleVariantSetManager.ReadPropertyPathAsJson(
              Comp, Opt.Bindings[I].PropertyPath)
          else
            LiveVal := '<missing comp>';

          It := ListViewBindings.Items.Add;
          It.Caption := Opt.Bindings[I].ComponentName;
          It.SubItems.Add(Opt.Bindings[I].PropertyPath);
          It.SubItems.Add(Opt.Bindings[I].ValueJson);
          It.SubItems.Add(LiveVal);
        end;
      end;
    end;
  finally
    ListViewBindings.Items.EndUpdate;
  end;
end;

procedure TVariantManagerForm.ButtonAddSetClick(Sender: TObject);
var
  Mgr: TCastleVariantSetManager;
  SName: String;
begin
  SName := 'Lighting';
  if not InputQuery('New Variant Set', 'Enter Variant Set group name (e.g. Lighting, Quality, Props):', SName) then
    Exit;
  if Trim(SName) = '' then
    Exit;
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  Mgr.EnsureVariant(SName, 'Default');
  RefreshSets(SName);
  NotifyModified('Add Variant Set ' + SName);
end;

procedure TVariantManagerForm.ButtonAddVariantClick(Sender: TObject);
var
  Mgr: TCastleVariantSetManager;
  SName, VName: String;
begin
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  SName := CurrentSetName;
  if SName = '' then
    SName := 'Lighting';
  VName := 'Sunset';
  if not InputQuery('New Variant in "' + SName + '"', 'Enter Variant name:', VName) then
    Exit;
  if Trim(VName) = '' then
    Exit;
  Mgr.EnsureVariant(SName, VName);
  RefreshSets(SName);
  RefreshVariants(VName);
  NotifyModified('Add Variant ' + SName + '/' + VName);
end;

procedure TVariantManagerForm.ButtonStartDiffClick(Sender: TObject);
begin
  if FRootComponent = nil then
    Exit;
  FBaselineDiffJson := ComponentToString(FRootComponent);
  ButtonCommitDiff.Enabled := FBaselineDiffJson <> '';
  LabelStatus.Caption := 'Baseline snapshot captured! Edit properties in the Inspector, then click "2. Capture Diff -> Variant".';
end;

procedure TVariantManagerForm.ButtonCommitDiffClick(Sender: TObject);
var
  Mgr: TCastleVariantSetManager;
  SName, VName: String;
  Cnt: Integer;
begin
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  SName := CurrentSetName;
  if SName = '' then
    SName := 'Lighting';
  VName := CurrentVariantName;
  if VName = '' then
    VName := 'Modified';
  Cnt := TVariantManagerHelper.CaptureHierarchyDifferenceIntoVariant(
    FBaselineDiffJson, FRootComponent, Mgr, SName, VName);
  RefreshSets(SName);
  RefreshVariants(VName);
  LabelStatus.Caption := Format('Captured %d modified property bindings into %s / %s.',
    [Cnt, SName, VName]);
  NotifyModified(Format('Capture %d Variant Diffs into %s/%s', [Cnt, SName, VName]));
end;

procedure TVariantManagerForm.ButtonCaptureSelectedClick(Sender: TObject);
var
  Mgr: TCastleVariantSetManager;
  SName, VName: String;
  Cnt: Integer;
begin
  if (FSelectedComponent = nil) or (FSelectedComponent.Name = '') then
  begin
    LabelStatus.Caption := 'Select a named component in the Hierarchy before opening or enter a binding below.';
    Exit;
  end;
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  SName := CurrentSetName;
  if SName = '' then
    SName := 'Props';
  VName := CurrentVariantName;
  if VName = '' then
    VName := 'StateA';
  Cnt := Mgr.CaptureComponentSnapshotIntoVariant(FSelectedComponent, SName, VName);
  RefreshSets(SName);
  RefreshVariants(VName);
  LabelStatus.Caption := Format('Captured %d properties from "%s" into %s / %s.',
    [Cnt, FSelectedComponent.Name, SName, VName]);
  NotifyModified('Snapshot Component into Variant');
end;

procedure TVariantManagerForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TVariantManagerHelper.FormatVariantManagerMarkdown(FRootComponent);
  LabelStatus.Caption := 'Copied Variant Manager Configuration Matrix Markdown to clipboard.';
end;

procedure TVariantManagerForm.ListBoxSetsSelectionChange(Sender: TObject; User: Boolean);
begin
  RefreshVariants;
end;

procedure TVariantManagerForm.ListBoxVariantsSelectionChange(Sender: TObject; User: Boolean);
begin
  RefreshBindings;
end;

procedure TVariantManagerForm.ButtonActivateVariantClick(Sender: TObject);
var
  Mgr: TCastleVariantSetManager;
  SName, VName: String;
  Applied: Integer;
begin
  Mgr := TVariantManagerHelper.FindManagerInDesign(FRootComponent);
  SName := CurrentSetName;
  VName := CurrentVariantName;
  if (Mgr = nil) or (SName = '') or (VName = '') then
    Exit;
  Applied := Mgr.ApplyVariant(FRootComponent, SName, VName);
  RefreshSets(SName);
  RefreshVariants(VName);
  LabelStatus.Caption := Format('Activated Variant "%s / %s" (%d property bindings applied live).',
    [SName, VName, Applied]);
  NotifyModified(Format('Activate Variant %s/%s', [SName, VName]));
end;

procedure TVariantManagerForm.ListViewBindingsSelectItem(Sender: TObject;
  Item: TListItem; Selected: Boolean);
begin
  if (not Selected) or (Item = nil) or (Item.SubItems.Count < 2) then
    Exit;
  EditCompName.Text := Item.Caption;
  EditPropPath.Text := Item.SubItems[0];
  EditValueJson.Text := Item.SubItems[1];
end;

procedure TVariantManagerForm.ButtonSaveBindingClick(Sender: TObject);
var
  Mgr: TCastleVariantSetManager;
  SName, VName: String;
begin
  if (Trim(EditCompName.Text) = '') or (Trim(EditPropPath.Text) = '') then
    Exit;
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  SName := CurrentSetName;
  if SName = '' then
    SName := 'Lighting';
  VName := CurrentVariantName;
  if VName = '' then
    VName := 'Default';
  Mgr.SetVariantBinding(SName, VName, Trim(EditCompName.Text),
    Trim(EditPropPath.Text), Trim(EditValueJson.Text));
  RefreshSets(SName);
  RefreshVariants(VName);
  NotifyModified('Update Variant Property Binding');
end;

procedure TVariantManagerForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
