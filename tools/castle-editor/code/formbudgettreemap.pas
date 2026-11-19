{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Visual Studio dialog for Squarified Scene Memory/Triangle Budget Treemap +
  116-Studio Hub / 21st MCP Tool (Phase 396). }
unit FormBudgetTreemap;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils,
  ToolBudgetTreemap, ToolStudioHub;

type
  TBudgetTreemapModifiedCallback = procedure(const UndoComment: String) of object;
  TBudgetTreemapRefreshCallback = procedure of object;

  TBudgetTreemapForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TBudgetTreemapModifiedCallback;
    FOnRefresh: TBudgetTreemapRefreshCallback;
    FLblSummary: TLabel;
    FPaintTreemap: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnReauditClick(Sender: TObject);
    procedure BtnStrictCapClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintTreemap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TBudgetTreemapModifiedCallback;
      const AOnRefresh: TBudgetTreemapRefreshCallback);
  end;

implementation

constructor TBudgetTreemapForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TBudgetTreemapModifiedCallback;
  const AOnRefresh: TBudgetTreemapRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Squarified Scene Budget Treemap & 116-Studio Hub / 21st MCP Tool';
  Position := poScreenCenter;
  Width := 790;
  Height := 580;
  BuildUi;
  RefreshView;
end;

procedure TBudgetTreemapForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnAudit, BtnStrict, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 42;
  PnlTop.BevelOuter := bvNone;

  FLblSummary := TLabel.Create(Self);
  FLblSummary.Parent := PnlTop;
  FLblSummary.Left := 12;
  FLblSummary.Top := 12;
  FLblSummary.Caption := 'Ready.';

  PnlButtons := TPanel.Create(Self);
  PnlButtons.Parent := Self;
  PnlButtons.Align := alTop;
  PnlButtons.Height := 46;
  PnlButtons.BevelOuter := bvNone;

  BtnSpawn := TButton.Create(Self);
  BtnSpawn.Parent := PnlButtons;
  BtnSpawn.SetBounds(10, 8, 200, 30);
  BtnSpawn.Caption := '+ Spawn Multi-Scale Scene Demo';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnAudit := TButton.Create(Self);
  BtnAudit.Parent := PnlButtons;
  BtnAudit.SetBounds(216, 8, 175, 30);
  BtnAudit.Caption := 'Audit Scene (2048 KB Cap)';
  BtnAudit.OnClick := @BtnReauditClick;

  BtnStrict := TButton.Create(Self);
  BtnStrict.Parent := PnlButtons;
  BtnStrict.SetBounds(397, 8, 185, 30);
  BtnStrict.Caption := 'Strict Mobile Cap (800 KB)';
  BtnStrict.OnClick := @BtnStrictCapClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(588, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintTreemap := TPaintBox.Create(Self);
  FPaintTreemap.Parent := Self;
  FPaintTreemap.Align := alTop;
  FPaintTreemap.Height := 220;
  FPaintTreemap.OnPaint := @PaintTreemap;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := Self;
  BtnClose.Align := alBottom;
  BtnClose.Height := 34;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;
end;

procedure TBudgetTreemapForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TBudgetTreemapForm.RefreshView;
var
  Rep: TSceneBudgetTreemapReport;
begin
  Rep := TSceneBudgetTreemapAnalyzer.SharedAnalyzer.AnalyzeSceneTreemap(
    FDesignRoot,
    TSceneBudgetTreemapAnalyzer.SharedAnalyzer.SceneBudgetLimitKB,
    TSceneBudgetTreemapAnalyzer.SharedAnalyzer.PerNodeCapKB,
    Max(64, FPaintTreemap.Width), Max(64, FPaintTreemap.Height));
  FLblSummary.Caption := FormatDot(
    '[Treemap: %.0f / %.0f KB (%d outliers) | %d Studios]',
    [Rep.TotalEstimatedMemoryKB, Rep.SceneBudgetLimitKB,
     Rep.OverBudgetNodeCount, TStudioHubManager.StudioCount]);
  FMemoReport.Lines.Text := TSceneBudgetTreemapAnalyzer.GenerateMarkdownReport(Rep);
  FPaintTreemap.Invalidate;
end;

procedure TBudgetTreemapForm.BtnSpawnDemoClick(Sender: TObject);
begin
  if TSceneBudgetTreemapAnalyzer.SpawnSyntheticHeavySceneDemo(FDesignRoot, FDesignOwner) then
    NotifyChanged('Spawn Budget Treemap Demo Scene');
end;

procedure TBudgetTreemapForm.BtnReauditClick(Sender: TObject);
begin
  TSceneBudgetTreemapAnalyzer.SharedAnalyzer.PerNodeCapKB := 2048.0;
  RefreshView;
end;

procedure TBudgetTreemapForm.BtnStrictCapClick(Sender: TObject);
begin
  TSceneBudgetTreemapAnalyzer.SharedAnalyzer.PerNodeCapKB := 800.0;
  RefreshView;
end;

procedure TBudgetTreemapForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TBudgetTreemapForm.PaintTreemap(Sender: TObject);
var
  C: TCanvas;
  Rep: TSceneBudgetTreemapReport;
  Cell: TBudgetTreemapCell;
  W, H, I, X1, Y1, X2, Y2: Integer;
begin
  C := FPaintTreemap.Canvas;
  W := Max(32, FPaintTreemap.Width);
  H := Max(32, FPaintTreemap.Height);
  C.Brush.Color := RGBToColor(15, 19, 26);
  C.FillRect(0, 0, W, H);

  Rep := TSceneBudgetTreemapAnalyzer.SharedAnalyzer.AnalyzeSceneTreemap(
    FDesignRoot,
    TSceneBudgetTreemapAnalyzer.SharedAnalyzer.SceneBudgetLimitKB,
    TSceneBudgetTreemapAnalyzer.SharedAnalyzer.PerNodeCapKB, W, H);

  C.Pen.Color := RGBToColor(14, 18, 24);
  C.Pen.Width := 2;
  for I := 0 to High(Rep.Cells) do
  begin
    Cell := Rep.Cells[I];
    X1 := Round(Cell.RectX);
    Y1 := Round(Cell.RectY);
    X2 := Round(Cell.RectX + Cell.RectW);
    Y2 := Round(Cell.RectY + Cell.RectH);
    if Cell.IsOverNodeCap then
      C.Brush.Color := RGBToColor(215, 62, 58)
    else
      C.Brush.Color := RGBToColor(46, 138, 196);
    C.Rectangle(X1, Y1, X2, Y2);
    if (X2 - X1 > 48) and (Y2 - Y1 > 20) then
    begin
      C.Font.Color := RGBToColor(245, 248, 255);
      C.Brush.Style := bsClear;
      C.TextOut(X1 + 5, Y1 + 4, Cell.ComponentName);
      C.Brush.Style := bsSolid;
    end;
  end;
end;

end.
