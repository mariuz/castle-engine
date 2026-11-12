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

{ Unified Editor Studio Hub, Categorized Quick-Launch Command Palette &
  Cross-Studio World Readiness Dashboard (@link(TStudioHubForm)) consolidating
  all 36 Horizon 2–5 studios with instant multi-token search, category filter
  pills, 1-click studio launch, a visual 0..100 World Readiness score gauge,
  cross-studio fix navigation, and executive Markdown export (Phase 316). }
unit FormStudioHub;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd, LCLType,
  CastleUtils, ToolStudioHub;

type
  TStudioLaunchByIdCallback = procedure(const AStudioId: String) of object;

  TStudioHubForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnLaunchStudio: TStudioLaunchByIdCallback;
    FPendingLaunchStudioId: String;

    FCategoryFilter: Integer;
    FFilteredStudios: TStudioCatalogEntryArray;
    FHealthReport: TStudioWorldHealthReport;

    LblHeader: TLabel;
    EditSearch: TEdit;
    ListStudios: TListBox;
    LblStudioDetails: TLabel;
    ListIssues: TListBox;
    PaintDashboard: TPaintBox;
    MemoExecutive: TMemo;

    procedure BuildUi;
    procedure RefreshCatalogList;
    procedure RefreshSelectedStudioDetails;
    procedure RefreshWorldAudit;
    procedure TriggerLaunchStudio(const AStudioId: String);

    procedure EditSearchChange(Sender: TObject);
    procedure EditSearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure BtnCategoryClick(Sender: TObject);
    procedure ListStudiosClick(Sender: TObject);
    procedure ListStudiosDblClick(Sender: TObject);
    procedure BtnLaunchSelectedClick(Sender: TObject);
    procedure BtnLaunchFixStudioClick(Sender: TObject);
    procedure BtnReAuditClick(Sender: TObject);
    procedure BtnCopyExecutiveClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintDashboardPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnLaunchStudio: TStudioLaunchByIdCallback);
    destructor Destroy; override;

    property PendingLaunchStudioId: String read FPendingLaunchStudioId;
  end;

implementation

constructor TStudioHubForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnLaunchStudio: TStudioLaunchByIdCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnLaunchStudio := AOnLaunchStudio;
  FCategoryFilter := -1;
  FPendingLaunchStudioId := '';

  Caption := 'Castle Game Engine — Unified Editor Studio Hub & World Readiness Dashboard';
  Width := 1180;
  Height := 740;
  Position := poMainFormCenter;

  BuildUi;
  RefreshCatalogList;
  RefreshWorldAudit;
end;

destructor TStudioHubForm.Destroy;
begin
  FreeAndNil(FHealthReport);
  inherited;
end;

procedure TStudioHubForm.BuildUi;
var
  PanelTop, RowCat, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  Btn, BtnClose: TButton;
  Cat: TStudioHubCategory;
  XPos: Integer;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent;
    const ATag: PtrInt = 0): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.Tag := ATag;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 104;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Unified Editor Studio Hub — Search & Launch Any Studio or Audit Cross-Studio World Readiness';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelTop;
  Lbl.SetBounds(12, 34, 110, 20);
  Lbl.Caption := 'Instant Search:';

  EditSearch := TEdit.Create(Self);
  EditSearch.Parent := PanelTop;
  EditSearch.SetBounds(118, 30, 680, 28);
  EditSearch.TextHint := 'Type keywords (e.g. "water buoyancy", "gas cooldown", "vcam shake", "csg", "phase 314") and press Enter...';
  EditSearch.OnChange := @EditSearchChange;
  EditSearch.OnKeyDown := @EditSearchKeyDown;

  MakeBtn(PanelTop, 'Launch Selected Studio ->', 810, 30, 210, @BtnLaunchSelectedClick);
  MakeBtn(PanelTop, 'Re-Audit World', 1028, 30, 136, @BtnReAuditClick);

  RowCat := TPanel.Create(Self);
  RowCat.Parent := PanelTop;
  RowCat.SetBounds(8, 66, 1160, 34);
  RowCat.BevelOuter := bvNone;

  XPos := 4;
  Btn := MakeBtn(RowCat, Format('All (%d)', [TStudioHubManager.StudioCount]),
    XPos, 2, 96, @BtnCategoryClick, -1);
  Inc(XPos, Btn.Width + 6);

  for Cat in TStudioHubCategory do
  begin
    Btn := MakeBtn(RowCat, TStudioHubManager.CategoryShortLabel(Cat),
      XPos, 2, 148, @BtnCategoryClick, Ord(Cat));
    Inc(XPos, Btn.Width + 6);
  end;

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Executive Markdown Report', 12, 6, 236, @BtnCopyExecutiveClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 1050, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 465;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 4, 420, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Matching Studios (Double-Click to Launch):';

  ListStudios := TListBox.Create(Self);
  ListStudios.Parent := PanelLeft;
  ListStudios.SetBounds(12, 24, 442, 336);
  ListStudios.OnClick := @ListStudiosClick;
  ListStudios.OnDblClick := @ListStudiosDblClick;

  LblStudioDetails := TLabel.Create(Self);
  LblStudioDetails.Parent := PanelLeft;
  LblStudioDetails.SetBounds(12, 366, 442, 46);
  LblStudioDetails.WordWrap := True;
  LblStudioDetails.Caption := '';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 418, 420, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Cross-Studio Integration Issues:';

  ListIssues := TListBox.Create(Self);
  ListIssues.Parent := PanelLeft;
  ListIssues.SetBounds(12, 438, 442, 108);

  MakeBtn(PanelLeft, 'Open Recommended Fix Studio ->', 12, 552, 442, @BtnLaunchFixStudioClick);

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintDashboard := TPaintBox.Create(Self);
  PaintDashboard.Parent := PanelCenter;
  PaintDashboard.Align := alTop;
  PaintDashboard.Height := 250;
  PaintDashboard.OnPaint := @PaintDashboardPaint;

  MemoExecutive := TMemo.Create(Self);
  MemoExecutive.Parent := PanelCenter;
  MemoExecutive.Align := alClient;
  MemoExecutive.ReadOnly := True;
  MemoExecutive.ScrollBars := ssAutoBoth;
  MemoExecutive.Font.Name := 'Monospace';
end;

procedure TStudioHubForm.RefreshCatalogList;
var
  I: Integer;
begin
  TStudioHubManager.FilterStudios(FCategoryFilter, EditSearch.Text, FFilteredStudios);

  ListStudios.Items.BeginUpdate;
  try
    ListStudios.Items.Clear;
    for I := 0 to High(FFilteredStudios) do
      ListStudios.Items.Add(Format('[%s] %s  (Phase %d)',
        [FFilteredStudios[I].ShortBadge,
         FFilteredStudios[I].Title,
         FFilteredStudios[I].PhaseNumber]));
    if ListStudios.Items.Count > 0 then
      ListStudios.ItemIndex := 0;
  finally
    ListStudios.Items.EndUpdate;
  end;

  RefreshSelectedStudioDetails;
end;

procedure TStudioHubForm.RefreshSelectedStudioDetails;
var
  Idx: Integer;
begin
  Idx := ListStudios.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FFilteredStudios)) then
    LblStudioDetails.Caption := Format('%s — %s',
      [TStudioHubManager.CategoryDisplayName(FFilteredStudios[Idx].Category),
       FFilteredStudios[Idx].Summary])
  else
    LblStudioDetails.Caption := 'No studios match the current search filter.';
end;

procedure TStudioHubForm.RefreshWorldAudit;
var
  I: Integer;
begin
  FreeAndNil(FHealthReport);
  FHealthReport := TStudioWorldHealthReport(
    TStudioHubManager.AuditEntireDesign(FDesignRoot, FDesignOwner));

  ListIssues.Items.BeginUpdate;
  try
    ListIssues.Items.Clear;
    if Length(FHealthReport.Issues) = 0 then
      ListIssues.Items.Add('0 Cross-Studio Issues — World is 100% Ship-Ready!')
    else
      for I := 0 to High(FHealthReport.Issues) do
        ListIssues.Items.Add(Format('[-%d pts -> %s] %s',
          [FHealthReport.Issues[I].SeverityPoints,
           FHealthReport.Issues[I].RecommendedStudioId,
           FHealthReport.Issues[I].MessageText]));
    if ListIssues.Items.Count > 0 then
      ListIssues.ItemIndex := 0;
  finally
    ListIssues.Items.EndUpdate;
  end;

  LblHeader.Caption := Format(
    'Unified Editor Studio Hub — %d Studios | World Readiness: %d/100 (%s) | %d Active Subsystems',
    [TStudioHubManager.StudioCount, FHealthReport.ReadinessScore,
     FHealthReport.ReadinessGrade, FHealthReport.TotalModernSubsystems]);

  MemoExecutive.Lines.Text := TStudioHubManager.BuildExecutiveMarkdownReport(
    FDesignRoot, FDesignOwner);
  PaintDashboard.Invalidate;
end;

procedure TStudioHubForm.TriggerLaunchStudio(const AStudioId: String);
begin
  if Trim(AStudioId) = '' then
    Exit;
  FPendingLaunchStudioId := AStudioId;
  ModalResult := mrOk;
  Close;
  if Assigned(FOnLaunchStudio) then
    FOnLaunchStudio(AStudioId);
end;

procedure TStudioHubForm.EditSearchChange(Sender: TObject);
begin
  RefreshCatalogList;
end;

procedure TStudioHubForm.EditSearchKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    BtnLaunchSelectedClick(nil);
  end;
end;

procedure TStudioHubForm.BtnCategoryClick(Sender: TObject);
begin
  if Sender is TControl then
  begin
    FCategoryFilter := TControl(Sender).Tag;
    RefreshCatalogList;
  end;
end;

procedure TStudioHubForm.ListStudiosClick(Sender: TObject);
begin
  RefreshSelectedStudioDetails;
end;

procedure TStudioHubForm.ListStudiosDblClick(Sender: TObject);
begin
  BtnLaunchSelectedClick(Sender);
end;

procedure TStudioHubForm.BtnLaunchSelectedClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := ListStudios.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FFilteredStudios)) then
    TriggerLaunchStudio(FFilteredStudios[Idx].StudioId);
end;

procedure TStudioHubForm.BtnLaunchFixStudioClick(Sender: TObject);
var
  Idx: Integer;
begin
  if (FHealthReport = nil) or (Length(FHealthReport.Issues) = 0) then
    Exit;
  Idx := ListIssues.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FHealthReport.Issues)) then
    TriggerLaunchStudio(FHealthReport.Issues[Idx].RecommendedStudioId);
end;

procedure TStudioHubForm.BtnReAuditClick(Sender: TObject);
begin
  RefreshWorldAudit;
end;

procedure TStudioHubForm.BtnCopyExecutiveClick(Sender: TObject);
begin
  Clipboard.AsText := TStudioHubManager.BuildExecutiveMarkdownReport(
    FDesignRoot, FDesignOwner);
end;

procedure TStudioHubForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TStudioHubForm.PaintDashboardPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, Score, BarX, BarW, RowY, FillW: Integer;
  Cat: TStudioHubCategory;
  ScoreCol: TColor;
begin
  Cv := PaintDashboard.Canvas;
  W := PaintDashboard.Width;
  H := PaintDashboard.Height;

  Cv.Brush.Color := RGBToColor(18, 22, 30);
  Cv.FillRect(0, 0, W, H);

  if FHealthReport = nil then
    Exit;

  Score := FHealthReport.ReadinessScore;
  if Score >= 90 then
    ScoreCol := RGBToColor(68, 214, 132)
  else if Score >= 70 then
    ScoreCol := RGBToColor(244, 188, 66)
  else
    ScoreCol := RGBToColor(242, 92, 84);

  { Left Readiness Card }
  Cv.Brush.Style := bsSolid;
  Cv.Brush.Color := RGBToColor(14, 17, 24);
  Cv.Pen.Color := ScoreCol;
  Cv.Rectangle(18, 18, 240, H - 18);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := RGBToColor(210, 224, 244);
  Cv.Font.Style := [fsBold];
  Cv.TextOut(32, 32, 'WORLD READINESS');

  Cv.Font.Size := 28;
  Cv.Font.Color := ScoreCol;
  Cv.TextOut(36, 68, Format('%d / 100', [Score]));

  Cv.Font.Size := 0;
  Cv.Font.Color := RGBToColor(225, 234, 248);
  Cv.TextOut(32, 134, FHealthReport.ReadinessGrade);
  Cv.Font.Style := [];
  Cv.TextOut(32, 164, Format('3D Transforms: %d', [FHealthReport.TotalTransforms]));
  Cv.TextOut(32, 186, Format('2D UI Controls: %d', [FHealthReport.TotalUserInterfaces]));
  Cv.TextOut(32, 208, Format('Active Subsystems: %d', [FHealthReport.TotalModernSubsystems]));

  { Right 6-Domain Subsystem Breakdown Bars }
  BarX := 264;
  BarW := Max(120, W - BarX - 24);
  RowY := 24;

  for Cat in TStudioHubCategory do
  begin
    Cv.Brush.Style := bsClear;
    Cv.Font.Color := RGBToColor(215, 228, 245);
    Cv.TextOut(BarX, RowY,
      Format('%s (%d active)',
        [TStudioHubManager.CategoryDisplayName(Cat),
         FHealthReport.CategorySubsystemCounts[Cat]]));

    Cv.Brush.Style := bsSolid;
    Cv.Brush.Color := RGBToColor(28, 36, 48);
    Cv.Pen.Color := RGBToColor(58, 74, 98);
    Cv.Rectangle(BarX, RowY + 18, BarX + BarW, RowY + 30);

    FillW := Round(BarW * Clamped(FHealthReport.CategorySubsystemCounts[Cat] / 6.0, 0.0, 1.0));
    if FillW > 0 then
    begin
      Cv.Brush.Color := RGBToColor(78, 176, 246);
      Cv.FillRect(BarX + 1, RowY + 19, BarX + FillW, RowY + 29);
    end;

    Inc(RowY, 36);
  end;
end;

end.
