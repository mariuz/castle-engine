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

{ Interactive Deterministic Golden-Snapshot State Hasher & Cross-Run Drift
  Auditor Studio dialog (Phase 346). }
unit FormRegressionHarness;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, StrUtils,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  ToolRegressionHarness;

type
  TRegressionHarnessModifyCallback = procedure(const AUndoComment: String) of object;
  TRegressionHarnessRefreshCallback = procedure of object;

  TRegressionHarnessForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TRegressionHarnessModifyCallback;
    FOnRefreshViewport: TRegressionHarnessRefreshCallback;

    FGoldenSnapshot: TGoldenWorldSnapshot;
    FLastAudit: TDeterminismAuditResult;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintLedger: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure BtnCaptureGoldenClick(Sender: TObject);
    procedure BtnVerifyDeterminismClick(Sender: TObject);
    procedure BtnCompareGoldenClick(Sender: TObject);
    procedure BtnInjectDriftClick(Sender: TObject);
    procedure BtnExportGoldenJsonClick(Sender: TObject);
    procedure BtnExportMarkdownClick(Sender: TObject);
    procedure PaintLedgerPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TRegressionHarnessModifyCallback;
      const AOnRefreshViewport: TRegressionHarnessRefreshCallback);
    destructor Destroy; override;
  end;

implementation

constructor TRegressionHarnessForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TRegressionHarnessModifyCallback;
  const AOnRefreshViewport: TRegressionHarnessRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Deterministic Golden-Snapshot State Hasher & Cross-Run Drift Auditor Studio (UE 6.0+ Golden QA Parity)';
  Width := 1060;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  FGoldenSnapshot := TDeterminismRegressionHarness.CaptureWorldSnapshot(
    FDesignRoot, FDesignOwner, 'InitialGolden');
  FLastAudit := TDeterminismRegressionHarness.VerifyDualRunDeterminism(
    FDesignRoot, FDesignOwner, 20, 1.0 / 60.0, 20260346);
  RefreshUi;
end;

destructor TRegressionHarnessForm.Destroy;
begin
  FreeAndNil(FGoldenSnapshot);
  inherited Destroy;
end;

procedure TRegressionHarnessForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 170): TButton;
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
  TopBar.Height := 128;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'Deterministic Golden-Snapshot Regression Harness — 64-Bit FNV-1a World Hashing, Dual-Run Replay Parity & Per-Actor Drift Pinpointing';

  LabelTelemetry := TLabel.Create(Self);
  LabelTelemetry.Parent := TopBar;
  LabelTelemetry.Align := alTop;
  LabelTelemetry.BorderSpacing.Left := 6;
  LabelTelemetry.Caption := 'Telemetry: ready';

  BtnRow1 := TPanel.Create(Self);
  BtnRow1.Parent := TopBar;
  BtnRow1.Align := alTop;
  BtnRow1.Height := 38;
  BtnRow1.BevelOuter := bvNone;
  MakeBtn(BtnRow1, 'Capture Golden Baseline', @BtnCaptureGoldenClick, 184);
  MakeBtn(BtnRow1, 'Verify Dual-Run (20f Seeded)', @BtnVerifyDeterminismClick, 204);
  MakeBtn(BtnRow1, 'Diff Live vs. Golden', @BtnCompareGoldenClick, 168);
  MakeBtn(BtnRow1, 'Inject +0.25m Test Drift', @BtnInjectDriftClick, 184);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Save Golden JSON...', @BtnExportGoldenJsonClick, 168);
  MakeBtn(BtnRow2, 'Export Audit Markdown...', @BtnExportMarkdownClick, 184);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 430;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintLedger := TPaintBox.Create(Self);
  PaintLedger.Parent := BodyPanel;
  PaintLedger.Align := alClient;
  PaintLedger.BorderSpacing.Around := 6;
  PaintLedger.OnPaint := @PaintLedgerPaint;
end;

procedure TRegressionHarnessForm.RefreshUi;
begin
  LabelTelemetry.Caption := Format(
    'Verdict: %s | Hash A/B: %s / %s | Actors: %d | Drifts: %d (Max %.4fm)',
    [IfThen(FLastAudit.BitExactMatch, 'BIT-EXACT PASS', 'DRIFT DETECTED'),
     FLastAudit.RunAHashHex, FLastAudit.RunBHashHex,
     FLastAudit.ActorsCompared, FLastAudit.DriftedActorCount,
     FLastAudit.MaxPositionDriftMeters]);
  MemoReport.Lines.Text := TDeterminismRegressionHarness.BuildMarkdownReport(
    FLastAudit, FGoldenSnapshot);
  PaintLedger.Invalidate;
end;

procedure TRegressionHarnessForm.BtnCaptureGoldenClick(Sender: TObject);
begin
  FreeAndNil(FGoldenSnapshot);
  FGoldenSnapshot := TDeterminismRegressionHarness.CaptureWorldSnapshot(
    FDesignRoot, FDesignOwner, 'GoldenBaseline');
  FLastAudit := TDeterminismRegressionHarness.CompareSnapshots(
    FGoldenSnapshot, FGoldenSnapshot);
  FLastAudit.StateRestoredCleanly := True;
  RefreshUi;
end;

procedure TRegressionHarnessForm.BtnVerifyDeterminismClick(Sender: TObject);
begin
  FLastAudit := TDeterminismRegressionHarness.VerifyDualRunDeterminism(
    FDesignRoot, FDesignOwner, 20, 1.0 / 60.0, 20260346);
  RefreshUi;
end;

procedure TRegressionHarnessForm.BtnCompareGoldenClick(Sender: TObject);
var
  LiveSnap: TGoldenWorldSnapshot;
begin
  if FGoldenSnapshot = nil then
    FGoldenSnapshot := TDeterminismRegressionHarness.CaptureWorldSnapshot(
      FDesignRoot, FDesignOwner, 'GoldenBaseline');
  LiveSnap := TDeterminismRegressionHarness.CaptureWorldSnapshot(
    FDesignRoot, FDesignOwner, 'LiveCandidate');
  try
    FLastAudit := TDeterminismRegressionHarness.CompareSnapshots(FGoldenSnapshot, LiveSnap);
    FLastAudit.StateRestoredCleanly := True;
  finally
    FreeAndNil(LiveSnap);
  end;
  RefreshUi;
end;

procedure TRegressionHarnessForm.BtnInjectDriftClick(Sender: TObject);
var
  RootT: TCastleTransform;
  I: Integer;
begin
  RootT := TDeterminismRegressionHarness.ResolveRootTransform(FDesignRoot);
  if RootT = nil then Exit;
  for I := 0 to RootT.Count - 1 do
    if not (csTransient in RootT[I].ComponentStyle) then
    begin
      RootT[I].Translation := RootT[I].Translation + Vector3(0.25, 0.0, 0.0);
      if Assigned(FOnModified) then
        FOnModified('Inject +0.25m Regression Test Drift');
      if Assigned(FOnRefreshViewport) then
        FOnRefreshViewport();
      Break;
    end;
  BtnCompareGoldenClick(Sender);
end;

procedure TRegressionHarnessForm.BtnExportGoldenJsonClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  if FGoldenSnapshot = nil then Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Golden Snapshot JSON (*.json)|*.json';
    Dlg.DefaultExt := 'json';
    Dlg.FileName := 'golden_world_snapshot.json';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := FGoldenSnapshot.ExportJson;
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TRegressionHarnessForm.BtnExportMarkdownClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'determinism_regression_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TDeterminismRegressionHarness.BuildMarkdownReport(FLastAudit, FGoldenSnapshot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TRegressionHarnessForm.PaintLedgerPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, Y, BarW: Integer;
begin
  Cv := PaintLedger.Canvas;
  W := Max(200, PaintLedger.Width);
  H := Max(200, PaintLedger.Height);

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);

  { Verdict banner }
  if FLastAudit.BitExactMatch then
    Cv.Brush.Color := RGBToColor(34, 132, 78)
  else
    Cv.Brush.Color := RGBToColor(186, 54, 48);
  Cv.Pen.Color := RGBToColor(96, 114, 142);
  Cv.Rectangle(16, 14, W - 16, 66);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(28, 22, Format('64-Bit FNV-1a World Hash: %s  (%s)', [
    FLastAudit.RunBHashHex,
    IfThen(FLastAudit.BitExactMatch, 'BIT-EXACT DETERMINISTIC', 'DRIFT DETECTED')]));
  Cv.Font.Style := [];
  Cv.TextOut(28, 42, Format('Expected Golden: %s  |  Actors Audited: %d  |  Drifts: %d', [
    FLastAudit.RunAHashHex, FLastAudit.ActorsCompared, FLastAudit.DriftedActorCount]));

  Y := 82;
  if Length(FLastAudit.Drifts) > 0 then
  begin
    for I := 0 to Min(7, High(FLastAudit.Drifts)) do
    begin
      Cv.Brush.Color := RGBToColor(46, 28, 34);
      Cv.Rectangle(16, Y, W - 16, Y + 36);
      BarW := EnsureRange(Round(FLastAudit.Drifts[I].PositionDeltaMeters * 180.0), 18, W - 64);
      Cv.Brush.Color := RGBToColor(235, 78, 64);
      Cv.Rectangle(18, Y + 26, 18 + BarW, Y + 34);
      Cv.Brush.Style := bsClear;
      Cv.TextOut(24, Y + 6, Format('[%s] %s — %s', [
        FLastAudit.Drifts[I].DriftKind,
        FLastAudit.Drifts[I].ActorPath,
        FLastAudit.Drifts[I].Details]));
      Y := Y + 44;
    end;
  end else if FGoldenSnapshot <> nil then
  begin
    for I := 0 to Min(8, FGoldenSnapshot.ActorCount - 1) do
    begin
      Cv.Brush.Color := RGBToColor(26, 36, 48);
      Cv.Rectangle(16, Y, W - 16, Y + 32);
      Cv.Brush.Style := bsClear;
      Cv.Font.Color := RGBToColor(148, 228, 176);
      Cv.TextOut(24, Y + 8, Format('[MATCH %s]  %s (%s)', [
        IntToHex(FGoldenSnapshot.Digests[I].ActorHash64, 16),
        FGoldenSnapshot.Digests[I].ActorPath,
        FGoldenSnapshot.Digests[I].ClassNameStr]));
      Y := Y + 38;
    end;
  end;
end;

end.
