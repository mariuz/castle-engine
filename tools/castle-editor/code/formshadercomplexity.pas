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

{ Visual Studio dialog for Viewport Overdraw, Transparency Stacking & Shader
  ALU Complexity Auditor + 136-Studio Hub / 23rd MCP Tool (Phase 416). }
unit FormShaderComplexity;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleViewport,
  ToolShaderComplexity, ToolStudioHub;

type
  TShaderComplexityModifiedCallback = procedure(const UndoComment: String) of object;
  TShaderComplexityRefreshCallback = procedure of object;

  TShaderComplexityForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TShaderComplexityModifiedCallback;
    FOnRefresh: TShaderComplexityRefreshCallback;
    FLblSummary: TLabel;
    FPaintHeatmap: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshAudit(const ATransCap: Integer);
    procedure BtnSpawnSmokeClick(Sender: TObject);
    procedure BtnAuditDesktopClick(Sender: TObject);
    procedure BtnAuditMobileClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintOverdrawHeatmap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TShaderComplexityModifiedCallback;
      const AOnRefresh: TShaderComplexityRefreshCallback);
  end;

implementation

constructor TShaderComplexityForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TShaderComplexityModifiedCallback;
  const AOnRefresh: TShaderComplexityRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Viewport Overdraw & Shader ALU Complexity Auditor (136 Studios / 23 MCP)';
  Position := poScreenCenter;
  Width := 800;
  Height := 580;
  BuildUi;
  RefreshAudit(3);
end;

procedure TShaderComplexityForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnDesk, BtnMob, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn 6x Smoke Overdraw';
  BtnSpawn.OnClick := @BtnSpawnSmokeClick;

  BtnDesk := TButton.Create(Self);
  BtnDesk.Parent := PnlButtons;
  BtnDesk.SetBounds(210, 8, 175, 30);
  BtnDesk.Caption := 'Desktop Cap (<=3 Layers)';
  BtnDesk.OnClick := @BtnAuditDesktopClick;

  BtnMob := TButton.Create(Self);
  BtnMob.Parent := PnlButtons;
  BtnMob.SetBounds(390, 8, 175, 30);
  BtnMob.Caption := 'Strict Mobile (<=1 Layer)';
  BtnMob.OnClick := @BtnAuditMobileClick;

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

  FPaintHeatmap := TPaintBox.Create(Self);
  FPaintHeatmap.Parent := Self;
  FPaintHeatmap.Align := alTop;
  FPaintHeatmap.Height := 220;
  FPaintHeatmap.OnPaint := @PaintOverdrawHeatmap;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TShaderComplexityForm.RefreshAudit(const ATransCap: Integer);
var
  Rep: TShaderComplexityReport;
begin
  Rep := TShaderComplexityAuditor.SharedAuditor.AuditViewportOverdraw(
    FDesignRoot, ATransCap, 320);
  FLblSummary.Caption := Format(
    'Peak Overdraw: %dx | Peak ALU: %d instr | Hotspot Tiles: %d | Hub: %d Studios / 23 MCP',
    [Rep.PeakTranslucentOverdraw, Rep.PeakTileAluInstructions,
     Rep.HotspotTileCount, TStudioHubManager.StudioCount]);
  FMemoReport.Lines.Text := TShaderComplexityAuditor.GenerateMarkdownReport(Rep);
  FPaintHeatmap.Invalidate;
end;

procedure TShaderComplexityForm.BtnSpawnSmokeClick(Sender: TObject);
begin
  if TShaderComplexityAuditor.SpawnStackedSmokeOverdrawDemo(FDesignRoot, FDesignOwner) then
  begin
    if Assigned(FOnModified) then FOnModified('Spawn Stacked Smoke Overdraw Demo');
    if Assigned(FOnRefresh) then FOnRefresh();
    RefreshAudit(3);
  end;
end;

procedure TShaderComplexityForm.BtnAuditDesktopClick(Sender: TObject);
begin
  RefreshAudit(3);
end;

procedure TShaderComplexityForm.BtnAuditMobileClick(Sender: TObject);
begin
  RefreshAudit(1);
end;

procedure TShaderComplexityForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TShaderComplexityForm.PaintOverdrawHeatmap(Sender: TObject);
var
  C: TCanvas;
  W, H, Row, Col, CW, CH, Alu, X0, Y0: Integer;
  Rep: TShaderComplexityReport;
begin
  C := FPaintHeatmap.Canvas;
  W := FPaintHeatmap.Width;
  H := FPaintHeatmap.Height;
  C.Brush.Color := RGBToColor(14, 18, 22);
  C.FillRect(0, 0, W, H);

  Rep := TShaderComplexityAuditor.SharedAuditor.LastReport;
  CW := Max(4, (W - 40) div OverdrawGridCols);
  CH := Max(4, (H - 36) div OverdrawGridRows);

  for Row := 0 to OverdrawGridRows - 1 do
    for Col := 0 to OverdrawGridCols - 1 do
    begin
      Alu := Rep.TileAluCosts[OverdrawGridRows - 1 - Row, Col];
      if Alu = 0 then
        C.Brush.Color := RGBToColor(18, 24, 30)
      else if Alu <= 80 then
        C.Brush.Color := RGBToColor(40, 175, 95)
      else if Alu <= 320 then
        C.Brush.Color := RGBToColor(235, 185, 55)
      else
        C.Brush.Color := RGBToColor(245, 55, 75);
      X0 := 20 + Col * CW;
      Y0 := 8 + Row * CH;
      C.FillRect(X0, Y0, X0 + CW - 1, Y0 + CH - 1);
    end;

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(20, H - 22, 'Green = Early-Z Opaque (<=80 ALU) | Gold = Moderate | Crimson = Stacked Alpha Hotspot (>320 ALU)');
end;

end.
