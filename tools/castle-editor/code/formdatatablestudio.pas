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

{ Interactive DataTables, Hierarchical Gameplay Tags & Progression Curve
  Balance Sheet Studio (@link(TDataTableStudioForm)) with inline spreadsheet
  editing, RFC-4180 CSV import/export, tag query filtering, and curve plotting
  (Phase 300 — UE 6.0 UDataTable, FGameplayTag & UCurveTable Parity). }
unit FormDataTableStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Grids, Dialogs, Graphics, Clipbrd,
  CastleUtils, CastleTransform,
  CastleDataTable, ToolDataTableStudio;

type
  TDataTableStudioModifiedCallback = procedure(const AComment: String) of object;
  TDataTableStudioRefreshViewportCallback = procedure of object;

  TDataTableStudioForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FSelectedComponent: TComponent;
    FOnModified: TDataTableStudioModifiedCallback;
    FOnRefreshViewport: TDataTableStudioRefreshViewportCallback;

    FTables: TDataTableComponentArray;

    ButtonTemplateEnemies: TButton;
    ButtonTemplateWeapons: TButton;
    ButtonTemplateLevels: TButton;
    ButtonExportCsv: TButton;
    ButtonImportCsv: TButton;
    ButtonApplyRowToSel: TButton;
    ButtonAttachTagToSel: TButton;
    ButtonCopyMarkdown: TButton;

    ListBoxTables: TListBox;
    EditTagQuery: TEdit;
    ButtonRunTagQuery: TButton;
    ComboCurveKind: TComboBox;
    EditCurveBase: TEdit;
    EditCurveGrowth: TEdit;
    EditCurveMaxLevel: TEdit;
    ButtonUpdateCurve: TButton;
    ButtonBakeCurveRows: TButton;

    GridTable: TStringGrid;
    ButtonAddRow: TButton;
    ButtonAddCol: TButton;
    ButtonCommitGrid: TButton;

    PaintBoxCurve: TPaintBox;
    MemoDiagnostics: TMemo;

    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    function ActiveTable: TCastleDataTable;
    procedure RefreshTableList(const ASelect: TCastleDataTable = nil);
    procedure PopulateGridFromActiveTable;
    procedure NotifyModified(const AComment: String);

    procedure ButtonTemplateEnemiesClick(Sender: TObject);
    procedure ButtonTemplateWeaponsClick(Sender: TObject);
    procedure ButtonTemplateLevelsClick(Sender: TObject);
    procedure ButtonExportCsvClick(Sender: TObject);
    procedure ButtonImportCsvClick(Sender: TObject);
    procedure ButtonApplyRowToSelClick(Sender: TObject);
    procedure ButtonAttachTagToSelClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);

    procedure ListBoxTablesClick(Sender: TObject);
    procedure ButtonRunTagQueryClick(Sender: TObject);
    procedure ButtonUpdateCurveClick(Sender: TObject);
    procedure ButtonBakeCurveRowsClick(Sender: TObject);
    procedure ButtonAddRowClick(Sender: TObject);
    procedure ButtonAddColClick(Sender: TObject);
    procedure ButtonCommitGridClick(Sender: TObject);

    procedure PaintBoxCurvePaint(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
      const AOnModified: TDataTableStudioModifiedCallback;
      const AOnRefreshViewport: TDataTableStudioRefreshViewportCallback);
  end;

implementation

{ TDataTableStudioForm ------------------------------------------------------- }

constructor TDataTableStudioForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
  const AOnModified: TDataTableStudioModifiedCallback;
  const AOnRefreshViewport: TDataTableStudioRefreshViewportCallback);
var
  InitTable: TCastleDataTable;
begin
  inherited CreateNew(AOwner, 1);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FSelectedComponent := ASelectedComponent;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'DataTables, Hierarchical Gameplay Tags & Balance Curve Studio';
  Width := 1080;
  Height := 720;
  Position := poMainFormCenter;
  Constraints.MinWidth := 920;
  Constraints.MinHeight := 620;

  BuildUi;

  InitTable := nil;
  if ASelectedComponent is TCastleDataTable then
    InitTable := TCastleDataTable(ASelectedComponent);
  RefreshTableList(InitTable);
end;

procedure TDataTableStudioForm.BuildUi;
var
  PanelTop, PanelBottom, PanelBody, PanelLeft, PanelRight: TPanel;
  YPos: Integer;
  LblList, LblTag, LblCurve, LblGrid, LblPlot: TLabel;

  function MakeTopBtn(const ACaption: String; const ALeft, AWidth: Integer;
    const AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := PanelTop;
    Result.Left := ALeft;
    Result.Top := 8;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
  end;

  function AddLabeledEdit(const AParent: TWinControl; const ATitle: String;
    var ATop: Integer; const ADefault: String): TEdit;
  var
    Lbl: TLabel;
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := AParent;
    Lbl.Left := 10;
    Lbl.Top := ATop + 4;
    Lbl.Caption := ATitle;

    Result := TEdit.Create(Self);
    Result.Parent := AParent;
    Result.Left := 162;
    Result.Top := ATop;
    Result.Width := 152;
    Result.Text := ADefault;
    Inc(ATop, 28);
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 46;
  PanelTop.BevelOuter := bvNone;

  ButtonTemplateEnemies := MakeTopBtn('+ Enemy Table', 8, 118, @ButtonTemplateEnemiesClick);
  ButtonTemplateWeapons := MakeTopBtn('+ Weapon Table', 130, 122, @ButtonTemplateWeaponsClick);
  ButtonTemplateLevels := MakeTopBtn('+ XP Curve Table', 256, 128, @ButtonTemplateLevelsClick);
  ButtonApplyRowToSel := MakeTopBtn('Apply Row -> Selected', 390, 152, @ButtonApplyRowToSelClick);
  ButtonAttachTagToSel := MakeTopBtn('Tag Selected...', 546, 118, @ButtonAttachTagToSelClick);
  ButtonExportCsv := MakeTopBtn('Export CSV...', 668, 108, @ButtonExportCsvClick);
  ButtonImportCsv := MakeTopBtn('Import CSV...', 780, 108, @ButtonImportCsvClick);
  ButtonCopyMarkdown := MakeTopBtn('Copy Report', 892, 108, @ButtonCopyMarkdownClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.Left := 12;
  LabelStatus.Top := 12;
  LabelStatus.Caption := 'Edit DataTable cells inline, query hierarchical Gameplay Tags (e.g. Enemy.Boss.*), or plot progression curves.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Anchors := [akTop, akRight];
  ButtonClose.Left := Width - 104;
  ButtonClose.Top := 6;
  ButtonClose.Width := 90;
  ButtonClose.Height := 30;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 326;
  PanelLeft.BevelOuter := bvLowered;

  LblList := TLabel.Create(Self);
  LblList.Parent := PanelLeft;
  LblList.Left := 10;
  LblList.Top := 8;
  LblList.Caption := 'DataTables in Design:';

  ListBoxTables := TListBox.Create(Self);
  ListBoxTables.Parent := PanelLeft;
  ListBoxTables.Left := 10;
  ListBoxTables.Top := 28;
  ListBoxTables.Width := 304;
  ListBoxTables.Height := 100;
  ListBoxTables.OnClick := @ListBoxTablesClick;

  LblTag := TLabel.Create(Self);
  LblTag.Parent := PanelLeft;
  LblTag.Left := 10;
  LblTag.Top := 136;
  LblTag.Caption := 'Gameplay Tag Query (e.g. Enemy.Boss.*):';

  EditTagQuery := TEdit.Create(Self);
  EditTagQuery.Parent := PanelLeft;
  EditTagQuery.Left := 10;
  EditTagQuery.Top := 156;
  EditTagQuery.Width := 210;
  EditTagQuery.Text := 'Enemy.Boss.*';

  ButtonRunTagQuery := TButton.Create(Self);
  ButtonRunTagQuery.Parent := PanelLeft;
  ButtonRunTagQuery.Left := 224;
  ButtonRunTagQuery.Top := 154;
  ButtonRunTagQuery.Width := 90;
  ButtonRunTagQuery.Height := 27;
  ButtonRunTagQuery.Caption := 'Query Tag';
  ButtonRunTagQuery.OnClick := @ButtonRunTagQueryClick;

  LblCurve := TLabel.Create(Self);
  LblCurve.Parent := PanelLeft;
  LblCurve.Left := 10;
  LblCurve.Top := 192;
  LblCurve.Caption := 'Progression Curve Formula:';

  ComboCurveKind := TComboBox.Create(Self);
  ComboCurveKind.Parent := PanelLeft;
  ComboCurveKind.Left := 10;
  ComboCurveKind.Top := 212;
  ComboCurveKind.Width := 304;
  ComboCurveKind.Style := csDropDownList;
  ComboCurveKind.Items.Add('Linear (Base + Rate * (L-1))');
  ComboCurveKind.Items.Add('Exponential (Base * Rate^(L-1))');
  ComboCurveKind.Items.Add('Polynomial (Base * L^Rate)');
  ComboCurveKind.Items.Add('Diminishing Returns (Asymptotic Cap)');
  ComboCurveKind.ItemIndex := 1;

  YPos := 246;
  EditCurveBase := AddLabeledEdit(PanelLeft, 'Base Value (L1):', YPos, '100.0');
  EditCurveGrowth := AddLabeledEdit(PanelLeft, 'Growth / Rate:', YPos, '1.15');
  EditCurveMaxLevel := AddLabeledEdit(PanelLeft, 'Max Level:', YPos, '20');

  ButtonUpdateCurve := TButton.Create(Self);
  ButtonUpdateCurve.Parent := PanelLeft;
  ButtonUpdateCurve.Left := 10;
  ButtonUpdateCurve.Top := YPos + 4;
  ButtonUpdateCurve.Width := 148;
  ButtonUpdateCurve.Height := 30;
  ButtonUpdateCurve.Caption := 'Update Curve Plot';
  ButtonUpdateCurve.OnClick := @ButtonUpdateCurveClick;

  ButtonBakeCurveRows := TButton.Create(Self);
  ButtonBakeCurveRows.Parent := PanelLeft;
  ButtonBakeCurveRows.Left := 166;
  ButtonBakeCurveRows.Top := YPos + 4;
  ButtonBakeCurveRows.Width := 148;
  ButtonBakeCurveRows.Height := 30;
  ButtonBakeCurveRows.Caption := 'Bake Level Rows';
  ButtonBakeCurveRows.OnClick := @ButtonBakeCurveRowsClick;
  Inc(YPos, 42);

  MemoDiagnostics := TMemo.Create(Self);
  MemoDiagnostics.Parent := PanelLeft;
  MemoDiagnostics.Left := 10;
  MemoDiagnostics.Top := YPos;
  MemoDiagnostics.Width := 304;
  MemoDiagnostics.Height := PanelLeft.Height - YPos - 10;
  MemoDiagnostics.Anchors := [akTop, akLeft, akRight, akBottom];
  MemoDiagnostics.ReadOnly := true;
  MemoDiagnostics.ScrollBars := ssVertical;

  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := PanelBody;
  PanelRight.Align := alClient;
  PanelRight.BevelOuter := bvNone;

  LblGrid := TLabel.Create(Self);
  LblGrid.Parent := PanelRight;
  LblGrid.Left := 12;
  LblGrid.Top := 8;
  LblGrid.Caption := 'Typed Spreadsheet Cells (Click any cell to edit, then click "Commit Grid Edits"):';

  GridTable := TStringGrid.Create(Self);
  GridTable.Parent := PanelRight;
  GridTable.Left := 12;
  GridTable.Top := 28;
  GridTable.Width := PanelRight.Width - 24;
  GridTable.Height := 310;
  GridTable.Anchors := [akTop, akLeft, akRight];
  GridTable.FixedCols := 0;
  GridTable.FixedRows := 1;
  GridTable.Options := GridTable.Options + [goEditing, goColSizing, goTabs];

  ButtonAddRow := TButton.Create(Self);
  ButtonAddRow.Parent := PanelRight;
  ButtonAddRow.Left := 12;
  ButtonAddRow.Top := 344;
  ButtonAddRow.Width := 110;
  ButtonAddRow.Height := 28;
  ButtonAddRow.Caption := '+ Add Row...';
  ButtonAddRow.OnClick := @ButtonAddRowClick;

  ButtonAddCol := TButton.Create(Self);
  ButtonAddCol.Parent := PanelRight;
  ButtonAddCol.Left := 128;
  ButtonAddCol.Top := 344;
  ButtonAddCol.Width := 130;
  ButtonAddCol.Height := 28;
  ButtonAddCol.Caption := '+ Add Column...';
  ButtonAddCol.OnClick := @ButtonAddColClick;

  ButtonCommitGrid := TButton.Create(Self);
  ButtonCommitGrid.Parent := PanelRight;
  ButtonCommitGrid.Left := 264;
  ButtonCommitGrid.Top := 344;
  ButtonCommitGrid.Width := 160;
  ButtonCommitGrid.Height := 28;
  ButtonCommitGrid.Caption := 'Commit Grid Edits';
  ButtonCommitGrid.OnClick := @ButtonCommitGridClick;

  LblPlot := TLabel.Create(Self);
  LblPlot.Parent := PanelRight;
  LblPlot.Left := 12;
  LblPlot.Top := 380;
  LblPlot.Caption := 'Progression Balance Curve Preview (Level 1 .. MaxLevel):';

  PaintBoxCurve := TPaintBox.Create(Self);
  PaintBoxCurve.Parent := PanelRight;
  PaintBoxCurve.Left := 12;
  PaintBoxCurve.Top := 400;
  PaintBoxCurve.Width := PanelRight.Width - 24;
  PaintBoxCurve.Height := PanelRight.Height - 410;
  PaintBoxCurve.Anchors := [akTop, akLeft, akRight, akBottom];
  PaintBoxCurve.OnPaint := @PaintBoxCurvePaint;
end;

function TDataTableStudioForm.ActiveTable: TCastleDataTable;
var
  Idx: Integer;
begin
  Result := nil;
  Idx := ListBoxTables.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FTables)) then
    Result := FTables[Idx];
end;

procedure TDataTableStudioForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TDataTableStudioForm.RefreshTableList(const ASelect: TCastleDataTable);
var
  Sum: TDataTableStudioSummary;
  I, SelIdx: Integer;
begin
  Sum := TDataTableStudioHelper.ScanDataTablesAndTags(FRootComponent);
  FTables := Sum.Tables;

  ListBoxTables.Items.BeginUpdate;
  try
    ListBoxTables.Items.Clear;
    SelIdx := -1;
    for I := 0 to High(FTables) do
    begin
      ListBoxTables.Items.Add(Format('%s  %s',
        [FTables[I].Name, FTables[I].DataTableSummaryBadge]));
      if FTables[I] = ASelect then
        SelIdx := I;
    end;
    if (SelIdx < 0) and (Length(FTables) > 0) then
      SelIdx := 0;
    ListBoxTables.ItemIndex := SelIdx;
  finally
    ListBoxTables.Items.EndUpdate;
  end;

  PopulateGridFromActiveTable;
  MemoDiagnostics.Text := TDataTableStudioHelper.BuildMarkdownReport(FRootComponent);
  PaintBoxCurve.Invalidate;
end;

procedure TDataTableStudioForm.PopulateGridFromActiveTable;
var
  DT: TCastleDataTable;
  C, R: Integer;
  Col: TDataTableColumn;
  KeyStr: String;
begin
  DT := ActiveTable;
  if DT = nil then
  begin
    GridTable.ColCount := 1;
    GridTable.RowCount := 1;
    GridTable.Cells[0, 0] := '(No DataTable)';
    Exit;
  end;

  ComboCurveKind.ItemIndex := Ord(DT.CurveKind);
  EditCurveBase.Text := FormatFloat('0.00', DT.CurveBaseValue);
  EditCurveGrowth.Text := FormatFloat('0.000', DT.CurveGrowthRate);
  EditCurveMaxLevel.Text := IntToStr(DT.CurveMaxLevel);

  GridTable.ColCount := DT.ColumnCount + 1;
  GridTable.RowCount := DT.RowCount + 1;
  GridTable.Cells[0, 0] := 'RowKey';
  GridTable.ColWidths[0] := 135;

  for C := 0 to DT.ColumnCount - 1 do
  begin
    Col := DT.GetColumn(C);
    GridTable.Cells[C + 1, 0] := Format('%s (%s)',
      [Col.ColumnName, TCastleDataTable.ColumnTypeToName(Col.ColumnType)]);
    GridTable.ColWidths[C + 1] := 135;
  end;

  for R := 0 to DT.RowCount - 1 do
  begin
    KeyStr := DT.GetRowKey(R);
    GridTable.Cells[0, R + 1] := KeyStr;
    for C := 0 to DT.ColumnCount - 1 do
    begin
      Col := DT.GetColumn(C);
      GridTable.Cells[C + 1, R + 1] := DT.GetCellString(KeyStr, Col.ColumnName, '');
    end;
  end;
end;

procedure TDataTableStudioForm.ButtonTemplateEnemiesClick(Sender: TObject);
var
  DT: TCastleDataTable;
begin
  DT := TDataTableStudioHelper.CreateDataTableInDesign(FRootComponent, FDesignOwner, 0);
  if DT <> nil then
  begin
    NotifyModified('Create RPG Enemy DataTable');
    RefreshTableList(DT);
    LabelStatus.Caption := Format('Created "%s" with 4 enemy archetypes.', [DT.Name]);
  end;
end;

procedure TDataTableStudioForm.ButtonTemplateWeaponsClick(Sender: TObject);
var
  DT: TCastleDataTable;
begin
  DT := TDataTableStudioHelper.CreateDataTableInDesign(FRootComponent, FDesignOwner, 1);
  if DT <> nil then
  begin
    NotifyModified('Create Weapon Balance DataTable');
    RefreshTableList(DT);
    LabelStatus.Caption := Format('Created "%s" with weapon loot stats.', [DT.Name]);
  end;
end;

procedure TDataTableStudioForm.ButtonTemplateLevelsClick(Sender: TObject);
var
  DT: TCastleDataTable;
begin
  DT := TDataTableStudioHelper.CreateDataTableInDesign(FRootComponent, FDesignOwner, 2);
  if DT <> nil then
  begin
    NotifyModified('Create Level XP Progression DataTable');
    RefreshTableList(DT);
    LabelStatus.Caption := Format('Created "%s" with exponential XP curve rows.', [DT.Name]);
  end;
end;

procedure TDataTableStudioForm.ButtonExportCsvClick(Sender: TObject);
var
  DT: TCastleDataTable;
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  DT := ActiveTable;
  if DT = nil then
    Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := 'Export DataTable as CSV';
    Dlg.Filter := 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*';
    Dlg.DefaultExt := 'csv';
    Dlg.FileName := LowerCase(DT.TableTitle) + '.csv';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := DT.ExportCsv;
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
      LabelStatus.Caption := 'Exported CSV to ' + Dlg.FileName;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TDataTableStudioForm.ButtonImportCsvClick(Sender: TObject);
var
  DT: TCastleDataTable;
  Dlg: TOpenDialog;
  SL: TStringList;
begin
  DT := ActiveTable;
  if DT = nil then
    DT := TDataTableStudioHelper.CreateDataTableInDesign(FRootComponent, FDesignOwner, 0);
  if DT = nil then
    Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Import CSV into DataTable';
    Dlg.Filter := 'CSV Files (*.csv)|*.csv|All Files (*.*)|*.*';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.LoadFromFile(Dlg.FileName);
        DT.ImportCsv(SL.Text);
      finally
        FreeAndNil(SL);
      end;
      NotifyModified('Import CSV into ' + DT.Name);
      RefreshTableList(DT);
      LabelStatus.Caption := 'Imported CSV into ' + DT.Name;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TDataTableStudioForm.ButtonApplyRowToSelClick(Sender: TObject);
var
  DT: TCastleDataTable;
  RowIdx, Applied: Integer;
  RowKey: String;
begin
  DT := ActiveTable;
  if (DT = nil) or (FSelectedComponent = nil) then
  begin
    LabelStatus.Caption := 'Select a target component in Hierarchy and a row in GridTable first.';
    Exit;
  end;
  RowIdx := GridTable.Row;
  if (RowIdx < 1) or (RowIdx >= GridTable.RowCount) then
    RowIdx := 1;
  if RowIdx >= GridTable.RowCount then
    Exit;
  RowKey := GridTable.Cells[0, RowIdx];
  Applied := DT.ApplyRowToComponent(RowKey, FSelectedComponent, FDesignOwner);
  NotifyModified(Format('Apply DataTable Row "%s" to %s', [RowKey, FSelectedComponent.Name]));
  RefreshTableList(DT);
  LabelStatus.Caption := Format('Applied %d matching column(s) from row "%s" onto "%s".',
    [Applied, RowKey, FSelectedComponent.Name]);
end;

procedure TDataTableStudioForm.ButtonAttachTagToSelClick(Sender: TObject);
var
  TagStr: String;
begin
  if not (FSelectedComponent is TCastleTransform) then
  begin
    LabelStatus.Caption := 'Select a TCastleTransform in the Hierarchy first to attach Gameplay Tags.';
    Exit;
  end;
  TagStr := 'Enemy.Boss.Dragon, Status.Active';
  if InputQuery('Attach Gameplay Tags',
     'Enter comma-separated hierarchical Gameplay Tags (e.g. Enemy.Boss.Dragon):', TagStr) then
  begin
    TDataTableStudioHelper.AttachGameplayTagsToTransform(
      TCastleTransform(FSelectedComponent), FDesignOwner, TagStr);
    NotifyModified('Attach Gameplay Tags to ' + FSelectedComponent.Name);
    RefreshTableList(ActiveTable);
    LabelStatus.Caption := Format('Attached Gameplay Tags "%s" to "%s".',
      [TagStr, FSelectedComponent.Name]);
  end;
end;

procedure TDataTableStudioForm.ButtonCopyMarkdownClick(Sender: TObject);
var
  Rep: String;
begin
  Rep := TDataTableStudioHelper.BuildMarkdownReport(FRootComponent);
  Clipboard.AsText := Rep;
  MemoDiagnostics.Text := Rep;
  LabelStatus.Caption := 'Copied DataTable & Gameplay Tags Markdown report to clipboard.';
end;

procedure TDataTableStudioForm.ListBoxTablesClick(Sender: TObject);
begin
  PopulateGridFromActiveTable;
  PaintBoxCurve.Invalidate;
end;

procedure TDataTableStudioForm.ButtonRunTagQueryClick(Sender: TObject);
var
  DT: TCastleDataTable;
  QueryStr, Msg: String;
  C, I: Integer;
  Col: TDataTableColumn;
  RowMatches: TDataRowKeyArray;
  TransMatches: TDataTableTransformArray;
begin
  QueryStr := Trim(EditTagQuery.Text);
  Msg := Format('Tag Query "%s":', [QueryStr]);
  DT := ActiveTable;
  if DT <> nil then
    for C := 0 to DT.ColumnCount - 1 do
    begin
      Col := DT.GetColumn(C);
      if Col.ColumnType = dctTag then
      begin
        RowMatches := DT.FindRowsMatchingTag(Col.ColumnName, QueryStr);
        Msg := Msg + Format(' [%d table rows:', [Length(RowMatches)]);
        for I := 0 to High(RowMatches) do
          Msg := Msg + ' ' + RowMatches[I];
        Msg := Msg + ']';
      end;
    end;

  TransMatches := TDataTableStudioHelper.FindTransformsMatchingGameplayTag(FRootComponent, QueryStr);
  Msg := Msg + Format(' [%d scene transforms]', [Length(TransMatches)]);
  LabelStatus.Caption := Msg;
end;

procedure TDataTableStudioForm.ButtonUpdateCurveClick(Sender: TObject);
var
  DT: TCastleDataTable;
begin
  DT := ActiveTable;
  if DT = nil then
    Exit;
  DT.CurveKind := TBalanceCurveKind(Clamped(ComboCurveKind.ItemIndex, 0, Ord(High(TBalanceCurveKind))));
  DT.CurveBaseValue := StrToFloatDef(EditCurveBase.Text, DT.CurveBaseValue);
  DT.CurveGrowthRate := StrToFloatDef(EditCurveGrowth.Text, DT.CurveGrowthRate);
  DT.CurveMaxLevel := StrToIntDef(EditCurveMaxLevel.Text, DT.CurveMaxLevel);
  NotifyModified('Update DataTable Progression Curve');
  PaintBoxCurve.Invalidate;
  MemoDiagnostics.Text := TDataTableStudioHelper.BuildMarkdownReport(FRootComponent);
end;

procedure TDataTableStudioForm.ButtonBakeCurveRowsClick(Sender: TObject);
var
  DT: TCastleDataTable;
begin
  DT := ActiveTable;
  if DT = nil then
    Exit;
  ButtonUpdateCurveClick(Sender);
  DT.BakeProgressionCurveIntoColumn('ScaledValue', FDesignOwner);
  NotifyModified('Bake Progression Curve Rows into ' + DT.Name);
  RefreshTableList(DT);
  LabelStatus.Caption := Format('Baked %d progression level rows into "%s".',
    [DT.CurveMaxLevel, DT.Name]);
end;

procedure TDataTableStudioForm.ButtonAddRowClick(Sender: TObject);
var
  DT: TCastleDataTable;
  KeyStr: String;
begin
  DT := ActiveTable;
  if DT = nil then
    Exit;
  KeyStr := Format('Row_%d', [DT.RowCount + 1]);
  if InputQuery('Add DataTable Row', 'Enter unique RowKey:', KeyStr) then
  begin
    DT.AddOrUpdateRow(KeyStr);
    NotifyModified('Add Row "' + KeyStr + '" to ' + DT.Name);
    RefreshTableList(DT);
  end;
end;

procedure TDataTableStudioForm.ButtonAddColClick(Sender: TObject);
var
  DT: TCastleDataTable;
  SpecStr: String;
  ColonPos: Integer;
begin
  DT := ActiveTable;
  if DT = nil then
    Exit;
  SpecStr := 'Armor:Float';
  if InputQuery('Add DataTable Column',
     'Enter ColumnName:Type (Float, Int, Bool, String, Tag):', SpecStr) then
  begin
    ColonPos := Pos(':', SpecStr);
    if ColonPos > 0 then
      DT.AddColumn(Copy(SpecStr, 1, ColonPos - 1),
        TCastleDataTable.NameToColumnType(Copy(SpecStr, ColonPos + 1, MaxInt)))
    else
      DT.AddColumn(SpecStr, dctFloat);
    NotifyModified('Add Column to ' + DT.Name);
    RefreshTableList(DT);
  end;
end;

procedure TDataTableStudioForm.ButtonCommitGridClick(Sender: TObject);
var
  DT: TCastleDataTable;
  R, C: Integer;
  KeyStr: String;
  Col: TDataTableColumn;
  Issues: TDataRowKeyArray;
begin
  DT := ActiveTable;
  if DT = nil then
    Exit;

  for R := 1 to GridTable.RowCount - 1 do
  begin
    KeyStr := Trim(GridTable.Cells[0, R]);
    if KeyStr = '' then
      Continue;
    DT.AddOrUpdateRow(KeyStr);
    for C := 0 to DT.ColumnCount - 1 do
    begin
      Col := DT.GetColumn(C);
      DT.SetCellString(KeyStr, Col.ColumnName, GridTable.Cells[C + 1, R]);
    end;
  end;

  NotifyModified('Commit Spreadsheet Edits in ' + DT.Name);
  RefreshTableList(DT);
  if DT.ValidateSchemaCells(Issues) then
    LabelStatus.Caption := 'Committed all grid edits — 0 schema validation errors.'
  else
    LabelStatus.Caption := Format('Committed edits with %d schema warning(s) — check Diagnostics.',
      [Length(Issues)]);
end;

procedure TDataTableStudioForm.PaintBoxCurvePaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, PlotW, PlotH, L, MaxL, CurX, CurY, PrevX, PrevY: Integer;
  DT: TCastleDataTable;
  MaxV, MinV, SpanV, Val: Single;
begin
  Cv := PaintBoxCurve.Canvas;
  W := PaintBoxCurve.Width;
  H := PaintBoxCurve.Height;
  Cv.Brush.Color := RGBToColor(20, 24, 32);
  Cv.FillRect(0, 0, W, H);

  DT := ActiveTable;
  if DT = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(18, H div 2 - 8,
      'Create or select a TCastleDataTable to preview its progression balance curve.');
    Exit;
  end;

  MaxL := Max(2, DT.CurveMaxLevel);
  MinV := DT.EvaluateProgressionCurve(1);
  MaxV := MinV;
  for L := 2 to MaxL do
  begin
    Val := DT.EvaluateProgressionCurve(L);
    if Val < MinV then MinV := Val;
    if Val > MaxV then MaxV := Val;
  end;
  SpanV := Max(0.001, MaxV - Min(0.0, MinV));

  PlotW := Max(40, W - 64);
  PlotH := Max(40, H - 46);

  Cv.Pen.Color := RGBToColor(75, 85, 105);
  Cv.Pen.Width := 1;
  Cv.Line(44, 16, 44, 16 + PlotH);
  Cv.Line(44, 16 + PlotH, 44 + PlotW, 16 + PlotH);

  Cv.Pen.Color := RGBToColor(80, 215, 155);
  Cv.Pen.Width := 2;
  PrevX := 44;
  PrevY := 16 + PlotH;
  for L := 1 to MaxL do
  begin
    Val := DT.EvaluateProgressionCurve(L);
    CurX := 44 + Round(((L - 1) / Max(1, MaxL - 1)) * PlotW);
    CurY := 16 + PlotH - Round(((Val - Min(0.0, MinV)) / SpanV) * PlotH);
    if L > 1 then
      Cv.Line(PrevX, PrevY, CurX, CurY);
    Cv.Brush.Color := RGBToColor(255, 215, 80);
    Cv.Ellipse(CurX - 3, CurY - 3, CurX + 3, CurY + 3);
    PrevX := CurX;
    PrevY := CurY;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(52, 18, Format('%s  |  L1 = %.2f  ->  L%d = %.2f',
    [TCastleDataTable.CurveKindDisplayName(DT.CurveKind),
     DT.EvaluateProgressionCurve(1), MaxL, DT.EvaluateProgressionCurve(MaxL)]));
end;

procedure TDataTableStudioForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
