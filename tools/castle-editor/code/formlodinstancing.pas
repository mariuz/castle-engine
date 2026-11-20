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

{ Visual Studio dialog for Automated LOD Chain & GPU Draw-Call Instancing
  Optimizer + 126-Studio Hub / 22nd MCP Tool (Phase 406). }
unit FormLodInstancing;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleViewport,
  ToolLodInstancing, ToolStudioHub;

type
  TLodInstancingModifiedCallback = procedure(const UndoComment: String) of object;
  TLodInstancingRefreshCallback = procedure of object;

  TLodInstancingForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TLodInstancingModifiedCallback;
    FOnRefresh: TLodInstancingRefreshCallback;
    FLblSummary: TLabel;
    FPaintBars: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshAnalysis(const AMinBatch: Integer);
    procedure BtnSpawnColonnadeClick(Sender: TObject);
    procedure BtnAnalyzeDefaultClick(Sender: TObject);
    procedure BtnStrictBatchClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintInstancingChart(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TLodInstancingModifiedCallback;
      const AOnRefresh: TLodInstancingRefreshCallback);
  end;

implementation

constructor TLodInstancingForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TLodInstancingModifiedCallback;
  const AOnRefresh: TLodInstancingRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Automated LOD Chain & GPU Draw-Call Instancing Optimizer (126 Studios / 22 MCP)';
  Position := poScreenCenter;
  Width := 800;
  Height := 580;
  BuildUi;
  RefreshAnalysis(2);
end;

procedure TLodInstancingForm.BuildUi;
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
  BtnSpawn.SetBounds(10, 8, 195, 30);
  BtnSpawn.Caption := '+ Spawn Colonnade Demo (19)';
  BtnSpawn.OnClick := @BtnSpawnColonnadeClick;

  BtnAudit := TButton.Create(Self);
  BtnAudit.Parent := PnlButtons;
  BtnAudit.SetBounds(210, 8, 175, 30);
  BtnAudit.Caption := 'Analyze Instancing (>=2)';
  BtnAudit.OnClick := @BtnAnalyzeDefaultClick;

  BtnStrict := TButton.Create(Self);
  BtnStrict.Parent := PnlButtons;
  BtnStrict.SetBounds(390, 8, 175, 30);
  BtnStrict.Caption := 'Large Batches Only (>=9)';
  BtnStrict.OnClick := @BtnStrictBatchClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(570, 8, 95, 30);
  BtnCopy.Caption := 'Copy Report';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlButtons;
  BtnClose.SetBounds(670, 8, 80, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;
  BtnClose.OnClick := nil;

  FPaintBars := TPaintBox.Create(Self);
  FPaintBars.Parent := Self;
  FPaintBars.Align := alTop;
  FPaintBars.Height := 210;
  FPaintBars.OnPaint := @PaintInstancingChart;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TLodInstancingForm.RefreshAnalysis(const AMinBatch: Integer);
var
  Rep: TLodInstancingReport;
begin
  Rep := TLodInstancingOptimizer.SharedOptimizer.AnalyzeSceneInstancingAndLod(
    FDesignRoot, AMinBatch, 60.0, 500);
  FLblSummary.Caption := Format(
    'Draws: %d -> %d (-%.1f%%) | Batches: %d | 4-Tier LOD Plans: %d | Hub: %d Studios',
    [Rep.BaselineDrawCalls, Rep.OptimizedDrawCalls, Rep.ReductionPercent,
     Rep.BatchGroupCount, Rep.HighPolyLodCandidateCount,
     TStudioHubManager.StudioCount]);
  FMemoReport.Lines.Text := TLodInstancingOptimizer.GenerateMarkdownReport(Rep);
  FPaintBars.Invalidate;
end;

procedure TLodInstancingForm.BtnSpawnColonnadeClick(Sender: TObject);
begin
  if TLodInstancingOptimizer.SpawnColonnadeInstancingDemo(FDesignRoot, FDesignOwner) then
  begin
    if Assigned(FOnModified) then FOnModified('Spawn Colonnade Instancing Demo');
    if Assigned(FOnRefresh) then FOnRefresh();
    RefreshAnalysis(2);
  end;
end;

procedure TLodInstancingForm.BtnAnalyzeDefaultClick(Sender: TObject);
begin
  RefreshAnalysis(2);
end;

procedure TLodInstancingForm.BtnStrictBatchClick(Sender: TObject);
begin
  RefreshAnalysis(9);
end;

procedure TLodInstancingForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TLodInstancingForm.PaintInstancingChart(Sender: TObject);
var
  C: TCanvas;
  W, H, BaseW, OptW: Integer;
  Rep: TLodInstancingReport;
  MaxDraws: Integer;
begin
  C := FPaintBars.Canvas;
  W := FPaintBars.Width;
  H := FPaintBars.Height;
  C.Brush.Color := RGBToColor(18, 22, 30);
  C.FillRect(0, 0, W, H);

  Rep := TLodInstancingOptimizer.SharedOptimizer.LastReport;
  MaxDraws := Max(1, Rep.BaselineDrawCalls);

  BaseW := Round((W - 220) * (Rep.BaselineDrawCalls / MaxDraws));
  OptW := Round((W - 220) * (Rep.OptimizedDrawCalls / MaxDraws));

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(16, 36, Format('Unbatched Baseline: %d draws', [Rep.BaselineDrawCalls]));
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(225, 90, 70);
  C.FillRect(200, 32, 200 + BaseW, 60);

  C.Brush.Style := bsClear;
  C.TextOut(16, 86, Format('GPU-Instanced: %d draws', [Rep.OptimizedDrawCalls]));
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(65, 200, 130);
  C.FillRect(200, 82, 200 + Max(6, OptW), 110);

  C.Brush.Style := bsClear;
  C.TextOut(16, 145, Format(
    'Saved Draw Calls: %d (%.1f%%)   |   Auto-LOD Chains: %d   |   Unified Catalog: %d Studios / 22 MCP Tools',
    [Rep.PotentialDrawCallReduction, Rep.ReductionPercent,
     Rep.HighPolyLodCandidateCount, TStudioHubManager.StudioCount]));
end;

end.
