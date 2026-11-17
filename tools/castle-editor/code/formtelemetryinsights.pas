{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Interactive Unreal Insights-Style Live Frame/Subsystem Telemetry Ring-Buffer,
  Hierarchical Flame-Graph Visualizer & Chrome/Perfetto Trace Exporter Studio
  dialog (Phase 336). }
unit FormTelemetryInsights;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  ToolTelemetryInsights;

type
  TTelemetryInsightsForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FProfiler: TTelemetryInsightsProfiler;
    FSelectedLogicalFrame: Integer;

    LabelHeader: TLabel;
    LabelStats: TLabel;
    PaintFlameGraph: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure BtnCaptureRunClick(Sender: TObject);
    procedure BtnInjectHitchClick(Sender: TObject);
    procedure BtnPrevFrameClick(Sender: TObject);
    procedure BtnNextFrameClick(Sender: TObject);
    procedure BtnJumpWorstClick(Sender: TObject);
    procedure BtnExportChromeJsonClick(Sender: TObject);
    procedure BtnExportMarkdownClick(Sender: TObject);
    procedure PaintFlameGraphPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent);
    destructor Destroy; override;
  end;

implementation

constructor TTelemetryInsightsForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FProfiler := TTelemetryInsightsProfiler.Create(120);
  FProfiler.CaptureLiveHierarchyProfileRun(FDesignRoot, FDesignOwner, 60);
  FSelectedLogicalFrame := Max(0, FProfiler.FindWorstFrameLogicalIndex);

  Caption := 'Unreal Insights Live Telemetry Ring-Buffer, Flame-Graph & Chrome-Trace Studio (UE 6.0+ Parity)';
  Width := 1040;
  Height := 670;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

destructor TTelemetryInsightsForm.Destroy;
begin
  FreeAndNil(FProfiler);
  inherited Destroy;
end;

procedure TTelemetryInsightsForm.BuildUi;
var
  TopBar, BtnRow, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 148): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Align := alLeft;
    Result.BorderSpacing.Around := 4;
    Result.OnClick := AOnClick;
  end;

begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 92;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'Unreal Insights Telemetry Studio — 120-Frame Ring Buffer, P50/P95/P99 Hitch Detector, Flame-Graph & Perfetto JSON Export';

  LabelStats := TLabel.Create(Self);
  LabelStats.Parent := TopBar;
  LabelStats.Align := alTop;
  LabelStats.BorderSpacing.Left := 6;
  LabelStats.Caption := 'Telemetry: ready';

  BtnRow := TPanel.Create(Self);
  BtnRow.Parent := TopBar;
  BtnRow.Align := alTop;
  BtnRow.Height := 38;
  BtnRow.BevelOuter := bvNone;

  MakeBtn(BtnRow, 'Capture 60-Frame Trace', @BtnCaptureRunClick, 162);
  MakeBtn(BtnRow, 'Inject 26ms Hitch!', @BtnInjectHitchClick, 140);
  MakeBtn(BtnRow, '< Prev', @BtnPrevFrameClick, 68);
  MakeBtn(BtnRow, 'Next >', @BtnNextFrameClick, 68);
  MakeBtn(BtnRow, 'Jump Worst Hitch', @BtnJumpWorstClick, 136);
  MakeBtn(BtnRow, 'Export Chrome Trace JSON...', @BtnExportChromeJsonClick, 188);
  MakeBtn(BtnRow, 'Export Report...', @BtnExportMarkdownClick, 126);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 340;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintFlameGraph := TPaintBox.Create(Self);
  PaintFlameGraph.Parent := BodyPanel;
  PaintFlameGraph.Align := alClient;
  PaintFlameGraph.BorderSpacing.Around := 6;
  PaintFlameGraph.OnPaint := @PaintFlameGraphPaint;
end;

procedure TTelemetryInsightsForm.RefreshUi;
var
  Stats: TTelemetryAggregateStats;
  Fr: TTelemetryFrameRecord;
begin
  Stats := FProfiler.ComputeAggregateStats(16.67);
  FSelectedLogicalFrame := EnsureRange(FSelectedLogicalFrame, 0, Max(0, FProfiler.RetainedFrameCount - 1));
  Fr := FProfiler.GetFrame(FSelectedLogicalFrame);

  LabelStats.Caption := Format(
    'Frames: %d | P50: %.2fms | P95: %.2fms | P99: %.2fms | Hitches (>16.67ms): %d | Selected Frame #%d: %.2fms (%d spans)',
    [Stats.CapturedFrames, Stats.P50FrameMs, Stats.P95FrameMs, Stats.P99FrameMs,
     Stats.HitchSpikeCount, Fr.FrameIndex, Fr.TotalDurationMicros / 1000.0, Fr.SpanCount]);

  MemoReport.Lines.Text := FProfiler.BuildMarkdownReport(16.67);
  PaintFlameGraph.Invalidate;
end;

procedure TTelemetryInsightsForm.BtnCaptureRunClick(Sender: TObject);
begin
  FProfiler.CaptureLiveHierarchyProfileRun(FDesignRoot, FDesignOwner, 60);
  FSelectedLogicalFrame := Max(0, FProfiler.FindWorstFrameLogicalIndex);
  RefreshUi;
end;

procedure TTelemetryInsightsForm.BtnInjectHitchClick(Sender: TObject);
begin
  FProfiler.RecordSyntheticFrame(4800, 7600, 2900, 4200, 6900);
  FSelectedLogicalFrame := Max(0, FProfiler.RetainedFrameCount - 1);
  RefreshUi;
end;

procedure TTelemetryInsightsForm.BtnPrevFrameClick(Sender: TObject);
begin
  FSelectedLogicalFrame := Max(0, FSelectedLogicalFrame - 1);
  RefreshUi;
end;

procedure TTelemetryInsightsForm.BtnNextFrameClick(Sender: TObject);
begin
  FSelectedLogicalFrame := Min(Max(0, FProfiler.RetainedFrameCount - 1), FSelectedLogicalFrame + 1);
  RefreshUi;
end;

procedure TTelemetryInsightsForm.BtnJumpWorstClick(Sender: TObject);
begin
  FSelectedLogicalFrame := Max(0, FProfiler.FindWorstFrameLogicalIndex);
  RefreshUi;
end;

procedure TTelemetryInsightsForm.BtnExportChromeJsonClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Chrome / Perfetto Trace JSON (*.json)|*.json';
    Dlg.DefaultExt := 'json';
    Dlg.FileName := 'castle_telemetry_trace.json';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := FProfiler.ExportChromeTraceJson;
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TTelemetryInsightsForm.BtnExportMarkdownClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'telemetry_insights_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := FProfiler.BuildMarkdownReport(16.67);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TTelemetryInsightsForm.PaintFlameGraphPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, TopSparkH, I, N, BarW, BarX, BarTop, BudgetY: Integer;
  Fr: TTelemetryFrameRecord;
  Sp: TTelemetrySpanEvent;
  Ms, MaxScaleMs: Double;
  X1, X2, RowY, RowH: Integer;
  RelStart, RelDur: Double;
begin
  Cv := PaintFlameGraph.Canvas;
  W := Max(160, PaintFlameGraph.Width);
  H := Max(160, PaintFlameGraph.Height);
  TopSparkH := H div 2 - 10;

  Cv.Brush.Color := RGBToColor(18, 20, 26);
  Cv.FillRect(0, 0, W, H);

  N := FProfiler.RetainedFrameCount;
  if N > 0 then
  begin
    MaxScaleMs := 25.0;
    for I := 0 to N - 1 do
      MaxScaleMs := Max(MaxScaleMs, FProfiler.GetFrame(I).TotalDurationMicros / 1000.0 * 1.12);

    BarW := Max(3, (W - 24) div Max(1, N));
    for I := 0 to N - 1 do
    begin
      Fr := FProfiler.GetFrame(I);
      Ms := Fr.TotalDurationMicros / 1000.0;
      BarX := 12 + I * BarW;
      BarTop := TopSparkH - Round((Ms / MaxScaleMs) * (TopSparkH - 28));
      if Ms > 16.67 then
        Cv.Brush.Color := RGBToColor(235, 75, 65)
      else
        Cv.Brush.Color := RGBToColor(68, 178, 118);
      if I = FSelectedLogicalFrame then
        Cv.Pen.Color := RGBToColor(255, 220, 75)
      else
        Cv.Pen.Color := RGBToColor(30, 34, 42);
      Cv.Rectangle(BarX, Max(24, BarTop), BarX + BarW - 1, TopSparkH);
    end;

    { 16.67ms 60Hz budget line }
    BudgetY := TopSparkH - Round((16.67 / MaxScaleMs) * (TopSparkH - 28));
    Cv.Pen.Color := RGBToColor(250, 200, 70);
    Cv.Pen.Style := psDash;
    Cv.Line(10, BudgetY, W - 10, BudgetY);
    Cv.Pen.Style := psSolid;

    { Bottom pane: Hierarchical Flame-Graph for Selected Frame }
    Fr := FProfiler.GetFrame(FSelectedLogicalFrame);
    RowH := 34;
    for I := 0 to Fr.SpanCount - 1 do
    begin
      Sp := Fr.Spans[I];
      RelStart := (Sp.StartMicros - Fr.FrameStartMicros) / Max(1.0, Double(Fr.TotalDurationMicros));
      RelDur := Sp.DurationMicros / Max(1.0, Double(Fr.TotalDurationMicros));
      X1 := 12 + Round(RelStart * (W - 24));
      X2 := Max(X1 + 6, 12 + Round((RelStart + RelDur) * (W - 24)));
      RowY := TopSparkH + 28 + Sp.Depth * (RowH + 4);

      case Sp.Depth of
        0: Cv.Brush.Color := RGBToColor(62, 108, 175);
        1: Cv.Brush.Color := RGBToColor(212, 118, 52);
      else
        Cv.Brush.Color := RGBToColor(168, 82, 165);
      end;
      Cv.Pen.Color := RGBToColor(235, 240, 250);
      Cv.Rectangle(X1, RowY, X2, RowY + RowH);
      Cv.Brush.Style := bsClear;
      Cv.Font.Color := clWhite;
      if (X2 - X1) > 48 then
        Cv.TextOut(X1 + 4, RowY + 8, Format('%s (%.2fms)', [Sp.SpanName, Sp.DurationMicros / 1000.0]));
      Cv.Brush.Style := bsSolid;
    end;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 6, '120-Frame Ring-Buffer History (Dashed Gold = 16.67ms 60Hz Budget, Red = Hitch Spike)');
  Cv.TextOut(12, TopSparkH + 8, 'Selected Frame Hierarchical Flame-Graph Spans (Depth 0..2)');
end;

end.
