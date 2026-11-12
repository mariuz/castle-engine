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

{ Interactive Real-Time Frame Budget Profiler, Draw-Call / VRAM Analyzer &
  5-Tier Scalability Studio (@link(TFrameProfilerForm)) featuring `Mobile 60Hz`
  / `Handheld 60Hz` / `Desktop 60Hz` / `WebAssembly 60Hz` budget gauges, top
  heavy offender ranking, and 1-click `Low .. Cinematic` scalability tier
  switching (Phase 306). }
unit FormFrameProfiler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Grids, Graphics, Clipbrd,
  CastleUtils, CastleScalability, ToolFrameProfiler;

type
  TFrameProfilerModifiedCallback = procedure(const AComment: String) of object;
  TFrameProfilerRefreshViewportCallback = procedure of object;

  TFrameProfilerForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TFrameProfilerModifiedCallback;
    FOnRefreshViewport: TFrameProfilerRefreshViewportCallback;

    FPlatform: TPlatformBudgetProfile;
    FReport: TFrameBudgetAuditReport;

    LblHeader: TLabel;
    CmbPlatform: TComboBox;
    PaintBars: TPaintBox;
    GridOffenders: TStringGrid;
    MemoViolations: TMemo;

    procedure BuildUi;
    procedure RefreshAudit;
    procedure ApplyTier(const ATier: TScalabilityTier);

    procedure CmbPlatformChange(Sender: TObject);
    procedure BtnTierLowClick(Sender: TObject);
    procedure BtnTierMediumClick(Sender: TObject);
    procedure BtnTierHighClick(Sender: TObject);
    procedure BtnTierEpicClick(Sender: TObject);
    procedure BtnTierCinematicClick(Sender: TObject);
    procedure BtnApplyRecommendedClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure PaintBarsPaint(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TFrameProfilerModifiedCallback;
      const AOnRefreshViewport: TFrameProfilerRefreshViewportCallback);
  end;

implementation

constructor TFrameProfilerForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TFrameProfilerModifiedCallback;
  const AOnRefreshViewport: TFrameProfilerRefreshViewportCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FPlatform := pbpDesktop60Hz;

  Caption := 'Real-Time Frame Budget Profiler, Draw-Call / VRAM Analyzer & 5-Tier Scalability Studio';
  Width := 1080;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAudit;
end;

procedure TFrameProfilerForm.BuildUi;
var
  PnlTop, PnlTierBar, PnlBottom, PnlGauges, PnlLower: TPanel;
  BtnLow, BtnMed, BtnHigh, BtnEpic, BtnCine, BtnRec, BtnCopy, BtnClose: TButton;
  Lbl: TLabel;
  P: TPlatformBudgetProfile;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 48;
  PnlTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PnlTop;
  LblHeader.Left := 14;
  LblHeader.Top := 14;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Frame Budget Profiler & Scalability Studio';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlTop;
  Lbl.SetBounds(610, 14, 115, 18);
  Lbl.Caption := 'Target Envelope:';

  CmbPlatform := TComboBox.Create(Self);
  CmbPlatform.Parent := PnlTop;
  CmbPlatform.SetBounds(726, 10, 175, 28);
  CmbPlatform.Style := csDropDownList;
  for P := Low(TPlatformBudgetProfile) to High(TPlatformBudgetProfile) do
    CmbPlatform.Items.Add(PlatformBudgetDisplayName(P));
  CmbPlatform.ItemIndex := Ord(pbpDesktop60Hz);
  CmbPlatform.OnChange := @CmbPlatformChange;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlTop;
  BtnCopy.SetBounds(910, 9, 155, 30);
  BtnCopy.Caption := 'Copy Markdown Audit';
  BtnCopy.OnClick := @BtnCopyMarkdownClick;

  PnlTierBar := TPanel.Create(Self);
  PnlTierBar.Parent := Self;
  PnlTierBar.Align := alTop;
  PnlTierBar.Height := 46;
  PnlTierBar.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlTierBar;
  Lbl.SetBounds(14, 13, 150, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := '5-Tier Scalability Group:';

  BtnLow := TButton.Create(Self);
  BtnLow.Parent := PnlTierBar;
  BtnLow.SetBounds(175, 8, 105, 30);
  BtnLow.Caption := '1. Low';
  BtnLow.OnClick := @BtnTierLowClick;

  BtnMed := TButton.Create(Self);
  BtnMed.Parent := PnlTierBar;
  BtnMed.SetBounds(286, 8, 105, 30);
  BtnMed.Caption := '2. Medium';
  BtnMed.OnClick := @BtnTierMediumClick;

  BtnHigh := TButton.Create(Self);
  BtnHigh.Parent := PnlTierBar;
  BtnHigh.SetBounds(397, 8, 105, 30);
  BtnHigh.Caption := '3. High (1.0x)';
  BtnHigh.OnClick := @BtnTierHighClick;

  BtnEpic := TButton.Create(Self);
  BtnEpic.Parent := PnlTierBar;
  BtnEpic.SetBounds(508, 8, 105, 30);
  BtnEpic.Caption := '4. Epic';
  BtnEpic.OnClick := @BtnTierEpicClick;

  BtnCine := TButton.Create(Self);
  BtnCine.Parent := PnlTierBar;
  BtnCine.SetBounds(619, 8, 115, 30);
  BtnCine.Caption := '5. Cinematic';
  BtnCine.OnClick := @BtnTierCinematicClick;

  BtnRec := TButton.Create(Self);
  BtnRec.Parent := PnlTierBar;
  BtnRec.SetBounds(752, 8, 313, 30);
  BtnRec.Caption := 'Auto-Apply Recommended Tier for Target';
  BtnRec.OnClick := @BtnApplyRecommendedClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 44;
  PnlBottom.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.SetBounds(955, 7, 110, 30);
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.Caption := 'Close';
  BtnClose.OnClick := @BtnCloseClick;

  PnlGauges := TPanel.Create(Self);
  PnlGauges.Parent := Self;
  PnlGauges.Align := alTop;
  PnlGauges.Height := 255;
  PnlGauges.BevelOuter := bvNone;

  PaintBars := TPaintBox.Create(Self);
  PaintBars.Parent := PnlGauges;
  PaintBars.Align := alClient;
  PaintBars.OnPaint := @PaintBarsPaint;

  PnlLower := TPanel.Create(Self);
  PnlLower.Parent := Self;
  PnlLower.Align := alClient;
  PnlLower.BevelOuter := bvNone;

  GridOffenders := TStringGrid.Create(Self);
  GridOffenders.Parent := PnlLower;
  GridOffenders.Align := alClient;
  GridOffenders.ColCount := 6;
  GridOffenders.RowCount := 2;
  GridOffenders.FixedCols := 0;
  GridOffenders.FixedRows := 1;
  GridOffenders.Options := GridOffenders.Options + [goRowSelect, goColSizing];
  GridOffenders.ColWidths[0] := 175;
  GridOffenders.ColWidths[1] := 125;
  GridOffenders.ColWidths[2] := 85;
  GridOffenders.ColWidths[3] := 105;
  GridOffenders.ColWidths[4] := 105;
  GridOffenders.ColWidths[5] := 115;
  GridOffenders.Cells[0, 0] := 'Component';
  GridOffenders.Cells[1, 0] := 'Category';
  GridOffenders.Cells[2, 0] := 'Draw Calls';
  GridOffenders.Cells[3, 0] := 'Triangles';
  GridOffenders.Cells[4, 0] := 'Est. VRAM';
  GridOffenders.Cells[5, 0] := 'Cost Score';

  MemoViolations := TMemo.Create(Self);
  MemoViolations.Parent := PnlLower;
  MemoViolations.Align := alRight;
  MemoViolations.Width := 345;
  MemoViolations.ReadOnly := true;
  MemoViolations.ScrollBars := ssVertical;
end;

procedure TFrameProfilerForm.RefreshAudit;
var
  I, Rows: Integer;
  TierStr: String;
begin
  FReport := TFrameBudgetProfiler.AuditHierarchy(FDesignRoot, FPlatform);
  if FReport.ActiveScalabilityManager <> nil then
    TierStr := ScalabilityTierDisplayName(FReport.ActiveScalabilityManager.ActiveTier)
  else
    TierStr := 'High (Default)';

  LblHeader.Caption := Format(
    'Frame Budget Profiler — Est. %.2f ms / %.2f ms [%s] | Active Tier: %s | Recommended: %s',
    [FReport.EstimatedGpuFrameMs, FReport.BudgetSpec.TargetFrameTimeMs,
     BoolToStr(FReport.OverallPassBudget, 'PASS', 'OVER BUDGET'),
     TierStr, ScalabilityTierDisplayName(FReport.RecommendedTier)]);

  Rows := Max(2, Length(FReport.TopOffenders) + 1);
  GridOffenders.RowCount := Rows;
  if Length(FReport.TopOffenders) = 0 then
  begin
    for I := 0 to 5 do
      GridOffenders.Cells[I, 1] := '';
    GridOffenders.Cells[0, 1] := '(Scene empty / clean)';
  end else
    for I := 0 to High(FReport.TopOffenders) do
    begin
      GridOffenders.Cells[0, I + 1] := FReport.TopOffenders[I].ComponentName;
      GridOffenders.Cells[1, I + 1] := FReport.TopOffenders[I].Category;
      GridOffenders.Cells[2, I + 1] := IntToStr(FReport.TopOffenders[I].EstimatedDrawCalls);
      GridOffenders.Cells[3, I + 1] := IntToStr(FReport.TopOffenders[I].EstimatedTriangles);
      GridOffenders.Cells[4, I + 1] := Format('%d KB', [FReport.TopOffenders[I].EstimatedVramBytes div 1024]);
      GridOffenders.Cells[5, I + 1] := Format('%.1f', [FReport.TopOffenders[I].CostScore]);
    end;

  MemoViolations.Lines.Text := TFrameBudgetProfiler.BuildMarkdownReport(FDesignRoot, FPlatform);
  PaintBars.Invalidate;
end;

procedure TFrameProfilerForm.ApplyTier(const ATier: TScalabilityTier);
begin
  TFrameBudgetProfiler.ApplyScalabilityTierToDesign(FDesignRoot, FDesignOwner, ATier);
  if Assigned(FOnModified) then
    FOnModified('Apply Scalability Tier: ' + ScalabilityTierDisplayName(ATier));
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAudit;
end;

procedure TFrameProfilerForm.CmbPlatformChange(Sender: TObject);
begin
  FPlatform := TPlatformBudgetProfile(
    Clamped(CmbPlatform.ItemIndex, 0, Ord(High(TPlatformBudgetProfile))));
  RefreshAudit;
end;

procedure TFrameProfilerForm.BtnTierLowClick(Sender: TObject);
begin
  ApplyTier(stLow);
end;

procedure TFrameProfilerForm.BtnTierMediumClick(Sender: TObject);
begin
  ApplyTier(stMedium);
end;

procedure TFrameProfilerForm.BtnTierHighClick(Sender: TObject);
begin
  ApplyTier(stHigh);
end;

procedure TFrameProfilerForm.BtnTierEpicClick(Sender: TObject);
begin
  ApplyTier(stEpic);
end;

procedure TFrameProfilerForm.BtnTierCinematicClick(Sender: TObject);
begin
  ApplyTier(stCinematic);
end;

procedure TFrameProfilerForm.BtnApplyRecommendedClick(Sender: TObject);
begin
  ApplyTier(FReport.RecommendedTier);
end;

procedure TFrameProfilerForm.BtnCopyMarkdownClick(Sender: TObject);
var
  Md: String;
begin
  Md := TFrameBudgetProfiler.BuildMarkdownReport(FDesignRoot, FPlatform);
  Clipboard.AsText := Md;
  MemoViolations.Lines.Text := Md;
end;

procedure TFrameProfilerForm.PaintBarsPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, BarLeft, BarWidth: Integer;

  procedure DrawGauge(const ARowIdx: Integer; const ALabel, AValueText: String;
    const ARatio: Single);
  var
    Y, FillW: Integer;
    FillCol: TColor;
  begin
    Y := 14 + ARowIdx * 38;
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(215, 228, 245);
    C.TextOut(16, Y + 3, ALabel);

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(32, 38, 50);
    C.Pen.Color := RGBToColor(60, 72, 92);
    C.Rectangle(BarLeft, Y, BarLeft + BarWidth, Y + 24);

    if ARatio > 1.001 then
      FillCol := RGBToColor(235, 72, 72)
    else if ARatio > 0.75 then
      FillCol := RGBToColor(240, 182, 55)
    else
      FillCol := RGBToColor(62, 205, 125);

    FillW := Round(Clamped(ARatio, 0.0, 1.0) * (BarWidth - 2));
    if FillW > 0 then
    begin
      C.Brush.Color := FillCol;
      C.FillRect(BarLeft + 1, Y + 1, BarLeft + 1 + FillW, Y + 23);
    end;

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(240, 245, 255);
    C.TextOut(BarLeft + 10, Y + 4, Format('%s  (%.0f%%)', [AValueText, ARatio * 100.0]));
  end;

begin
  C := PaintBars.Canvas;
  W := PaintBars.Width;
  H := PaintBars.Height;
  BarLeft := 210;
  BarWidth := Max(220, W - BarLeft - 24);

  C.Brush.Color := RGBToColor(18, 22, 30);
  C.FillRect(0, 0, W, H);

  DrawGauge(0, 'GPU Frame Budget (60 Hz)',
    Format('%.2f / %.2f ms', [FReport.EstimatedGpuFrameMs, FReport.BudgetSpec.TargetFrameTimeMs]),
    FReport.EstimatedGpuFrameMs / Max(0.1, FReport.BudgetSpec.TargetFrameTimeMs));
  DrawGauge(1, 'Estimated Draw Calls',
    Format('%d / %d', [FReport.EstimatedDrawCalls, FReport.BudgetSpec.MaxDrawCalls]),
    FReport.EstimatedDrawCalls / Max(1, FReport.BudgetSpec.MaxDrawCalls));
  DrawGauge(2, 'Scene Triangles',
    Format('%d / %d', [FReport.EstimatedTriangles, FReport.BudgetSpec.MaxTriangles]),
    FReport.EstimatedTriangles / Max(1, FReport.BudgetSpec.MaxTriangles));
  DrawGauge(3, 'Texture & RT VRAM',
    Format('%.1f / %.0f MB', [FReport.EstimatedTextureVramMB, FReport.BudgetSpec.MaxTextureVramMB]),
    FReport.EstimatedTextureVramMB / Max(1.0, FReport.BudgetSpec.MaxTextureVramMB));
  DrawGauge(4, 'Shadow-Casting Lights',
    Format('%d / %d', [FReport.ShadowCastingLightsCount, FReport.BudgetSpec.MaxShadowLights]),
    FReport.ShadowCastingLightsCount / Max(1, FReport.BudgetSpec.MaxShadowLights));
  DrawGauge(5, 'Active VFX Particles',
    Format('%d / %d', [FReport.ActiveParticleBudget, FReport.BudgetSpec.MaxActiveParticles]),
    FReport.ActiveParticleBudget / Max(1, FReport.BudgetSpec.MaxActiveParticles));
end;

procedure TFrameProfilerForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

end.
