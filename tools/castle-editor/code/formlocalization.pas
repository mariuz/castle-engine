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

{ Interactive Localization (i18n) String Extractor, Live Viewport Locale
  Switcher & Pseudo-Localization Overflow Auditor (@link(TLocalizationForm))
  (Phase 294 — UE 5.9 / 6.0 Localization Dashboard Parity). }
unit FormLocalization;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, StrUtils, Forms, Controls, StdCtrls, ExtCtrls,
  ComCtrls, Dialogs, Clipbrd,
  CastleLocalizationTable, ToolLocalization;

type
  TLocalizationStudioModifiedCallback = procedure (const UndoComment: String) of object;
  TLocalizationStudioRefreshViewportCallback = procedure of object;

  TLocalizationForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TLocalizationStudioModifiedCallback;
    FOnRefreshViewport: TLocalizationStudioRefreshViewportCallback;

    FEditingLocale: String;

    { Top Toolbar }
    ButtonExtract: TButton;
    BtnLocaleEn: TButton;
    BtnLocaleDe: TButton;
    BtnLocaleJa: TButton;
    BtnLocaleEs: TButton;
    BtnLocalePseudo: TButton;
    ButtonAudit: TButton;
    ButtonExportCsv: TButton;
    ButtonImportCsv: TButton;
    ButtonCopyMarkdown: TButton;

    { Center String Table Grid }
    ListViewKeys: TListView;

    { Bottom Translation Editor + Audit Issues }
    EditKey: TEdit;
    EditSourceEn: TEdit;
    LabelTargetLocale: TLabel;
    EditTargetValue: TEdit;
    ButtonSaveRow: TButton;
    MemoAudit: TMemo;

    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    function EnsureMgr: TCastleLocalizationManager;
    procedure RefreshTableAndAudit;
    procedure SwitchLiveLocale(const ALocale: String);
    procedure NotifyModified(const Comment: String);

    procedure ButtonExtractClick(Sender: TObject);
    procedure LocaleButtonClick(Sender: TObject);
    procedure ButtonAuditClick(Sender: TObject);
    procedure ButtonExportCsvClick(Sender: TObject);
    procedure ButtonImportCsvClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure ListViewKeysSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ButtonSaveRowClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner: TComponent;
      const AOnModified: TLocalizationStudioModifiedCallback;
      const AOnRefreshViewport: TLocalizationStudioRefreshViewportCallback);
  end;

implementation

constructor TLocalizationForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner: TComponent;
  const AOnModified: TLocalizationStudioModifiedCallback;
  const AOnRefreshViewport: TLocalizationStudioRefreshViewportCallback);
var
  Mgr: TCastleLocalizationManager;
begin
  inherited CreateNew(AOwner, 0);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FEditingLocale := 'de';
  Mgr := TLocalizationHelper.FindManagerInDesign(FRootComponent);
  if (Mgr <> nil) and (not SameText(Mgr.ActiveLocale, 'en')) and
     (not SameText(Mgr.ActiveLocale, 'pseudo')) then
    FEditingLocale := Mgr.ActiveLocale;
  BuildUi;
  RefreshTableAndAudit;
end;

procedure TLocalizationForm.BuildUi;
var
  PanelTop, PanelLocales, PanelBottom, PanelEditor: TPanel;
  Col: TListColumn;
  Lbl: TLabel;

  function MakeLocaleBtn(const AParent: TWinControl; const ALeft, AWidth: Integer;
    const ACaption, ALocCode: String): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, 6, AWidth, 28);
    Result.Caption := ACaption;
    Result.Hint := ALocCode;
    Result.OnClick := @LocaleButtonClick;
  end;

begin
  Caption := 'Localization (i18n) String Extractor, Live Locale Switcher & Pseudo-L10n Auditor (UE 5.9 / 6.0 Parity)';
  Width := 1060;
  Height := 690;
  Position := poMainFormCenter;
  Constraints.MinWidth := 900;
  Constraints.MinHeight := 580;

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 44;
  PanelTop.BevelOuter := bvNone;

  ButtonExtract := TButton.Create(Self);
  ButtonExtract.Parent := PanelTop;
  ButtonExtract.SetBounds(10, 7, 195, 30);
  ButtonExtract.Caption := 'Extract UI / 3D Strings';
  ButtonExtract.OnClick := @ButtonExtractClick;

  ButtonAudit := TButton.Create(Self);
  ButtonAudit.Parent := PanelTop;
  ButtonAudit.SetBounds(212, 7, 185, 30);
  ButtonAudit.Caption := 'Audit Missing & Overflows';
  ButtonAudit.OnClick := @ButtonAuditClick;

  ButtonExportCsv := TButton.Create(Self);
  ButtonExportCsv.Parent := PanelTop;
  ButtonExportCsv.SetBounds(404, 7, 135, 30);
  ButtonExportCsv.Caption := 'Export CSV...';
  ButtonExportCsv.OnClick := @ButtonExportCsvClick;

  ButtonImportCsv := TButton.Create(Self);
  ButtonImportCsv.Parent := PanelTop;
  ButtonImportCsv.SetBounds(546, 7, 135, 30);
  ButtonImportCsv.Caption := 'Import CSV...';
  ButtonImportCsv.OnClick := @ButtonImportCsvClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.SetBounds(688, 7, 175, 30);
  ButtonCopyMarkdown.Caption := 'Copy Audit Markdown';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  PanelLocales := TPanel.Create(Self);
  PanelLocales.Parent := Self;
  PanelLocales.Align := alTop;
  PanelLocales.Height := 40;
  PanelLocales.BevelOuter := bvLowered;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLocales;
  Lbl.SetBounds(10, 11, 155, 18);
  Lbl.Caption := 'Live Viewport Locale:';

  BtnLocaleEn := MakeLocaleBtn(PanelLocales, 170, 110, 'English (en)', 'en');
  BtnLocaleDe := MakeLocaleBtn(PanelLocales, 286, 115, 'German (de)', 'de');
  BtnLocaleJa := MakeLocaleBtn(PanelLocales, 407, 120, 'Japanese (ja)', 'ja');
  BtnLocaleEs := MakeLocaleBtn(PanelLocales, 533, 115, 'Spanish (es)', 'es');
  BtnLocalePseudo := MakeLocaleBtn(PanelLocales, 654, 240, '[!! Pseudo-L10n +35% Stress !!]', 'pseudo');

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

  PanelEditor := TPanel.Create(Self);
  PanelEditor.Parent := Self;
  PanelEditor.Align := alBottom;
  PanelEditor.Height := 210;
  PanelEditor.BorderSpacing.Around := 6;
  PanelEditor.BevelOuter := bvLowered;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelEditor;
  Lbl.SetBounds(10, 10, 80, 18);
  Lbl.Caption := 'String Key:';

  EditKey := TEdit.Create(Self);
  EditKey.Parent := PanelEditor;
  EditKey.SetBounds(100, 8, 280, 24);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelEditor;
  Lbl.SetBounds(392, 10, 88, 18);
  Lbl.Caption := 'Source (en):';

  EditSourceEn := TEdit.Create(Self);
  EditSourceEn.Parent := PanelEditor;
  EditSourceEn.SetBounds(484, 8, 420, 24);

  LabelTargetLocale := TLabel.Create(Self);
  LabelTargetLocale.Parent := PanelEditor;
  LabelTargetLocale.SetBounds(10, 42, 150, 18);
  LabelTargetLocale.Caption := 'Translation (de):';

  EditTargetValue := TEdit.Create(Self);
  EditTargetValue.Parent := PanelEditor;
  EditTargetValue.SetBounds(165, 38, 600, 24);

  ButtonSaveRow := TButton.Create(Self);
  ButtonSaveRow.Parent := PanelEditor;
  ButtonSaveRow.SetBounds(774, 36, 180, 28);
  ButtonSaveRow.Caption := 'Save Key / Translation';
  ButtonSaveRow.OnClick := @ButtonSaveRowClick;

  MemoAudit := TMemo.Create(Self);
  MemoAudit.Parent := PanelEditor;
  MemoAudit.SetBounds(10, 72, 1020, 128);
  MemoAudit.Anchors := [akLeft, akTop, akRight, akBottom];
  MemoAudit.ReadOnly := true;
  MemoAudit.ScrollBars := ssAutoBoth;

  ListViewKeys := TListView.Create(Self);
  ListViewKeys.Parent := Self;
  ListViewKeys.Align := alClient;
  ListViewKeys.BorderSpacing.Around := 6;
  ListViewKeys.ViewStyle := vsReport;
  ListViewKeys.RowSelect := true;
  ListViewKeys.ReadOnly := true;
  ListViewKeys.OnSelectItem := @ListViewKeysSelectItem;

  Col := ListViewKeys.Columns.Add;
  Col.Caption := 'Translation Key';
  Col.Width := 230;

  Col := ListViewKeys.Columns.Add;
  Col.Caption := 'Component.Property';
  Col.Width := 180;

  Col := ListViewKeys.Columns.Add;
  Col.Caption := 'Source (en)';
  Col.Width := 230;

  Col := ListViewKeys.Columns.Add;
  Col.Caption := 'Target Translation';
  Col.Width := 230;

  Col := ListViewKeys.Columns.Add;
  Col.Caption := 'Pseudo-L10n Preview';
  Col.Width := 160;
end;

function TLocalizationForm.EnsureMgr: TCastleLocalizationManager;
begin
  Result := TLocalizationHelper.EnsureManagerInDesign(FRootComponent, FDesignOwner);
end;

procedure TLocalizationForm.NotifyModified(const Comment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(Comment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TLocalizationForm.RefreshTableAndAudit;
var
  Mgr: TCastleLocalizationManager;
  Rep: TLocalizationAuditReport;
  I: Integer;
  E: TLocalizationStringEntry;
  It: TListItem;
  EnVal, TargetVal, PseudoVal: String;
  FoundEn, FoundTarget, UsedFb: Boolean;
begin
  LabelTargetLocale.Caption := Format('Translation (%s):', [FEditingLocale]);
  Mgr := TLocalizationHelper.FindManagerInDesign(FRootComponent);

  ListViewKeys.Items.BeginUpdate;
  try
    ListViewKeys.Items.Clear;
    if Mgr <> nil then
      for I := 0 to Mgr.EntryCount - 1 do
      begin
        E := Mgr.GetEntry(I);
        EnVal := Mgr.GetExactTranslation(E.Key, Mgr.FallbackLocale, FoundEn);
        TargetVal := Mgr.GetExactTranslation(E.Key, FEditingLocale, FoundTarget);
        PseudoVal := Mgr.ResolveTranslation(E.Key, 'pseudo', UsedFb);

        It := ListViewKeys.Items.Add;
        It.Caption := E.Key;
        It.SubItems.Add(IfThen(E.ComponentName <> '', E.ComponentName + '.' + E.PropertyName, '(unbound)'));
        It.SubItems.Add(EnVal);
        It.SubItems.Add(IfThen(FoundTarget, TargetVal, '<missing>'));
        It.SubItems.Add(PseudoVal);
      end;
  finally
    ListViewKeys.Items.EndUpdate;
  end;

  Rep := TLocalizationHelper.AuditHierarchyLocalization(
    FRootComponent, ['de', 'ja', 'es', 'pseudo']);
  MemoAudit.Lines.BeginUpdate;
  try
    MemoAudit.Lines.Clear;
    if Length(Rep.Issues) = 0 then
      MemoAudit.Lines.Add('Audit clean — 0 missing translations and 0 fixed-width overflow warnings.')
    else
      for I := 0 to High(Rep.Issues) do
        MemoAudit.Lines.Add(Format('[%s | %s] %s',
          [IfThen(Rep.Issues[I].Kind = likMissingTranslation, 'MISSING', 'OVERFLOW'),
           Rep.Issues[I].Locale, Rep.Issues[I].Message]));
  finally
    MemoAudit.Lines.EndUpdate;
  end;

  if Mgr <> nil then
    LabelStatus.Caption := Format(
      'Active Locale: "%s" | Editing Column: "%s" | Keys: %d | Missing: %d | Overflows: %d',
      [Mgr.ActiveLocale, FEditingLocale, Rep.EntryCount,
       Rep.MissingTranslationCount, Rep.OverflowWarningCount])
  else
    LabelStatus.Caption := 'No LocalizationManager in design yet — click "Extract UI / 3D Strings" to create and populate.';
end;

procedure TLocalizationForm.SwitchLiveLocale(const ALocale: String);
var
  Mgr: TCastleLocalizationManager;
  AppliedCount: Integer;
begin
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  if Mgr.EntryCount = 0 then
    TLocalizationHelper.ExtractTranslatableStringsFromHierarchy(FRootComponent, Mgr);

  if (not SameText(ALocale, 'en')) and (not SameText(ALocale, 'pseudo')) then
    FEditingLocale := ALocale;

  AppliedCount := Mgr.ApplyLocaleToHierarchy(FRootComponent, ALocale);
  RefreshTableAndAudit;
  NotifyModified(Format('Switch Live Viewport Locale to %s (%d props)', [ALocale, AppliedCount]));
end;

procedure TLocalizationForm.ButtonExtractClick(Sender: TObject);
var
  Mgr: TCastleLocalizationManager;
  Added: Integer;
begin
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  Added := TLocalizationHelper.ExtractTranslatableStringsFromHierarchy(FRootComponent, Mgr);
  RefreshTableAndAudit;
  NotifyModified(Format('Extract %d Localization Strings', [Added]));
end;

procedure TLocalizationForm.LocaleButtonClick(Sender: TObject);
begin
  if Sender is TButton then
    SwitchLiveLocale(TButton(Sender).Hint);
end;

procedure TLocalizationForm.ButtonAuditClick(Sender: TObject);
begin
  RefreshTableAndAudit;
end;

procedure TLocalizationForm.ButtonExportCsvClick(Sender: TObject);
var
  Mgr: TCastleLocalizationManager;
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := 'Export Localization String Table CSV';
    Dlg.DefaultExt := 'csv';
    Dlg.Filter := 'CSV String Table (*.csv)|*.csv|All Files (*.*)|*.*';
    Dlg.FileName := 'localization_strings.csv';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := Mgr.ExportCsv;
        SL.SaveToFile(Dlg.FileName);
        LabelStatus.Caption := 'Exported CSV string table to ' + Dlg.FileName;
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TLocalizationForm.ButtonImportCsvClick(Sender: TObject);
var
  Mgr: TCastleLocalizationManager;
  Dlg: TOpenDialog;
  SL: TStringList;
  Rows: Integer;
begin
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Import Localization String Table CSV';
    Dlg.Filter := 'CSV String Table (*.csv)|*.csv|All Files (*.*)|*.*';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.LoadFromFile(Dlg.FileName);
        Rows := Mgr.ImportCsv(SL.Text);
        RefreshTableAndAudit;
        NotifyModified(Format('Import %d Localization CSV Rows', [Rows]));
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TLocalizationForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TLocalizationHelper.FormatLocalizationMarkdown(
    FRootComponent, ['de', 'ja', 'es', 'pseudo']);
  LabelStatus.Caption := 'Copied Localization Audit & CSV Markdown report to clipboard.';
end;

procedure TLocalizationForm.ListViewKeysSelectItem(Sender: TObject;
  Item: TListItem; Selected: Boolean);
var
  Mgr: TCastleLocalizationManager;
  Found: Boolean;
begin
  if (not Selected) or (Item = nil) then
    Exit;
  EditKey.Text := Item.Caption;
  Mgr := TLocalizationHelper.FindManagerInDesign(FRootComponent);
  if Mgr <> nil then
  begin
    EditSourceEn.Text := Mgr.GetExactTranslation(Item.Caption, Mgr.FallbackLocale, Found);
    EditTargetValue.Text := Mgr.GetExactTranslation(Item.Caption, FEditingLocale, Found);
  end;
end;

procedure TLocalizationForm.ButtonSaveRowClick(Sender: TObject);
var
  Mgr: TCastleLocalizationManager;
  K: String;
begin
  K := Trim(EditKey.Text);
  if K = '' then
    Exit;
  Mgr := EnsureMgr;
  if Mgr = nil then
    Exit;
  if EditSourceEn.Text <> '' then
    Mgr.SetTranslation(K, Mgr.FallbackLocale, EditSourceEn.Text);
  if EditTargetValue.Text <> '' then
    Mgr.SetTranslation(K, FEditingLocale, EditTargetValue.Text);
  if SameText(Mgr.ActiveLocale, FEditingLocale) or
     SameText(Mgr.ActiveLocale, Mgr.FallbackLocale) then
    Mgr.ApplyLocaleToHierarchy(FRootComponent, Mgr.ActiveLocale);
  RefreshTableAndAudit;
  NotifyModified('Update Localization Key ' + K);
end;

procedure TLocalizationForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
