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

{ Gauntlet-Style Automated Playtest Bot Runner, Multi-System Smoke-Test
  Assertion Timeline & JUnit XML CI/CD Studio Dialog (@link(TPlaytestGauntletForm))
  (Phase 326 — UE 6.0+ Gauntlet Automation & Functional Testing Parity). }
unit FormPlaytestGauntlet;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleScalability,
  ToolPlaytestGauntlet;

type
  TGauntletStudioModifyCallback = procedure(const AUndoComment: String) of object;
  TGauntletStudioRefreshCallback = procedure of object;

  TPlaytestGauntletForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModify: TGauntletStudioModifyCallback;
    FOnRefresh: TGauntletStudioRefreshCallback;

    FLastConfig: TPlaytestGauntletConfig;
    FLastReport: TPlaytestGauntletReport;
    FShowingJUnitXml: Boolean;

    LblHeader: TLabel;
    ListAssertions: TListBox;
    MemoRunLog: TMemo;
    PaintTimeline: TPaintBox;
    MemoExport: TMemo;

    procedure BuildUi;
    procedure ExecuteGauntletPass(const ADurationSec: Single);
    procedure RefreshFromReport;
    procedure NotifyModified(const AComment: String);

    procedure BtnSpawnSandboxClick(Sender: TObject);
    procedure BtnRunSmoke2sClick(Sender: TObject);
    procedure BtnRunEndurance5sClick(Sender: TObject);
    procedure BtnSpawnKillZTrapClick(Sender: TObject);
    procedure BtnToggleXmlMarkdownClick(Sender: TObject);
    procedure BtnCopyJUnitXmlClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintTimelinePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModify: TGauntletStudioModifyCallback;
      const AOnRefresh: TGauntletStudioRefreshCallback);
    destructor Destroy; override;
  end;

implementation

constructor TPlaytestGauntletForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModify: TGauntletStudioModifyCallback;
  const AOnRefresh: TGauntletStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModify := AOnModify;
  FOnRefresh := AOnRefresh;
  FLastConfig := TPlaytestGauntletConfig.MakeDefault;
  FShowingJUnitXml := False;

  Caption := 'Castle Game Engine — Gauntlet Automated Playtest Bot & CI Smoke-Test Studio';
  Width := 1180;
  Height := 740;
  Position := poMainFormCenter;

  BuildUi;
  ExecuteGauntletPass(1.0);
end;

destructor TPlaytestGauntletForm.Destroy;
begin
  FreeAndNil(FLastReport);
  inherited;
end;

procedure TPlaytestGauntletForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModify) then
    FOnModify(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TPlaytestGauntletForm.BuildUi;
var
  PanelTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  BtnClose: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 74;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Gauntlet Automated Playtest Runner — Multi-System Smoke Bot, Kill-Z/NaN Guards & JUnit XML CI Export';

  MakeBtn(PanelTop, '+ Spawn Multi-System Sandbox', 12, 34, 214, @BtnSpawnSandboxClick);
  MakeBtn(PanelTop, 'Run 2.0s Smoke Bot (Restore)', 232, 34, 214, @BtnRunSmoke2sClick);
  MakeBtn(PanelTop, 'Run 5.0s Endurance Bot', 452, 34, 184, @BtnRunEndurance5sClick);
  MakeBtn(PanelTop, '+ Spawn Kill-Z Trap (Test Fail)', 642, 34, 214, @BtnSpawnKillZTrapClick);
  MakeBtn(PanelTop, 'Toggle Markdown / JUnit XML', 862, 34, 210, @BtnToggleXmlMarkdownClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy JUnit XML (CI/CD)', 12, 6, 196, @BtnCopyJUnitXmlClick);
  MakeBtn(PanelBottom, 'Copy Markdown Report', 216, 6, 196, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 1050, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 450;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 4, 420, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Gauntlet Invariant Assertions:';

  ListAssertions := TListBox.Create(Self);
  ListAssertions.Parent := PanelLeft;
  ListAssertions.SetBounds(12, 24, 426, 260);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 292, 420, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Automated Playtest Step Log:';

  MemoRunLog := TMemo.Create(Self);
  MemoRunLog.Parent := PanelLeft;
  MemoRunLog.SetBounds(12, 312, 426, 290);
  MemoRunLog.ReadOnly := True;
  MemoRunLog.ScrollBars := ssAutoBoth;
  MemoRunLog.Font.Name := 'Monospace';

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintTimeline := TPaintBox.Create(Self);
  PaintTimeline.Parent := PanelCenter;
  PaintTimeline.Align := alTop;
  PaintTimeline.Height := 260;
  PaintTimeline.OnPaint := @PaintTimelinePaint;

  MemoExport := TMemo.Create(Self);
  MemoExport.Parent := PanelCenter;
  MemoExport.Align := alClient;
  MemoExport.ReadOnly := True;
  MemoExport.ScrollBars := ssAutoBoth;
  MemoExport.Font.Name := 'Monospace';
end;

procedure TPlaytestGauntletForm.ExecuteGauntletPass(const ADurationSec: Single);
begin
  FreeAndNil(FLastReport);
  FLastConfig.TotalDurationSec := ADurationSec;
  FLastConfig.StepDtSec := 0.05;
  FLastConfig.RestoreDesignAfterRun := True;
  FLastReport := TPlaytestGauntletRunner.RunSmokeTest(
    FDesignRoot, FDesignOwner, FLastConfig);
  RefreshFromReport;
end;

procedure TPlaytestGauntletForm.RefreshFromReport;
var
  I: Integer;
  TagStr: String;
begin
  ListAssertions.Items.BeginUpdate;
  try
    ListAssertions.Items.Clear;
    if FLastReport <> nil then
      for I := 0 to High(FLastReport.Assertions) do
      begin
        if FLastReport.Assertions[I].Passed then
          TagStr := '[PASS]'
        else
          TagStr := '[FAIL]';
        ListAssertions.Items.Add(Format('%s %s — %s',
          [TagStr,
           FLastReport.Assertions[I].AssertionName,
           FLastReport.Assertions[I].MeasuredMetric]));
      end;
  finally
    ListAssertions.Items.EndUpdate;
  end;

  if FLastReport <> nil then
  begin
    MemoRunLog.Lines.Assign(FLastReport.LogLines);
    if FShowingJUnitXml then
      MemoExport.Lines.Text := TPlaytestGauntletRunner.BuildJUnitXmlReport(FLastReport)
    else
      MemoExport.Lines.Text := TPlaytestGauntletRunner.BuildMarkdownReport(FLastReport);
  end;

  PaintTimeline.Invalidate;
end;

procedure TPlaytestGauntletForm.BtnSpawnSandboxClick(Sender: TObject);
begin
  TPlaytestGauntletRunner.SpawnMultiSystemSmokeSandbox(FDesignRoot, FDesignOwner);
  NotifyModified('Spawn Multi-System Gauntlet Smoke Sandbox');
  ExecuteGauntletPass(2.0);
end;

procedure TPlaytestGauntletForm.BtnRunSmoke2sClick(Sender: TObject);
begin
  ExecuteGauntletPass(2.0);
end;

procedure TPlaytestGauntletForm.BtnRunEndurance5sClick(Sender: TObject);
begin
  ExecuteGauntletPass(5.0);
end;

procedure TPlaytestGauntletForm.BtnSpawnKillZTrapClick(Sender: TObject);
begin
  FLastConfig.KillZMinY := -2.0;
  TPlaytestGauntletRunner.SpawnKillZTrapActor(
    FDesignRoot, FDesignOwner, Vector3(8.0, 1.0, -4.0));
  NotifyModified('Spawn Ungrounded Kill-Z Trap Actor');
  ExecuteGauntletPass(1.5);
end;

procedure TPlaytestGauntletForm.BtnToggleXmlMarkdownClick(Sender: TObject);
begin
  FShowingJUnitXml := not FShowingJUnitXml;
  RefreshFromReport;
end;

procedure TPlaytestGauntletForm.BtnCopyJUnitXmlClick(Sender: TObject);
begin
  if FLastReport <> nil then
    Clipboard.AsText := TPlaytestGauntletRunner.BuildJUnitXmlReport(FLastReport);
end;

procedure TPlaytestGauntletForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  if FLastReport <> nil then
    Clipboard.AsText := TPlaytestGauntletRunner.BuildMarkdownReport(FLastReport);
end;

procedure TPlaytestGauntletForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TPlaytestGauntletForm.PaintTimelinePaint(Sender: TObject);
var
  C: TCanvas;
  W, H, PlotL, PlotR, PlotT, PlotB, PlotW, PlotH, I, X1, Y1, X2, Y2, KillZY: Integer;
  BannerCol: TColor;
  MinYVal, MaxYVal, MaxDispVal, NormY, NormDisp: Single;
begin
  C := PaintTimeline.Canvas;
  W := PaintTimeline.Width;
  H := PaintTimeline.Height;

  C.Brush.Color := RGBToColor(20, 24, 32);
  C.FillRect(0, 0, W, H);

  if FLastReport = nil then
    Exit;

  if FLastReport.AllPassed then
    BannerCol := RGBToColor(34, 148, 86)
  else
    BannerCol := RGBToColor(196, 56, 56);

  C.Brush.Color := BannerCol;
  C.FillRect(12, 10, W - 12, 52);
  C.Font.Color := clWhite;
  C.Font.Style := [fsBold];
  if FLastReport.AllPassed then
    C.TextOut(22, 16, Format('GAUNTLET SMOKE PASS  |  %d / %d Assertions Passed  |  %.2fs (%d steps in %.1f ms)',
      [FLastReport.PassedAssertionsCount, Length(FLastReport.Assertions),
       FLastReport.SimulatedDurationSec, FLastReport.TotalStepsExecuted, FLastReport.WallTimeMs]))
  else
    C.TextOut(22, 16, Format('GAUNTLET FAILURE DETECTED  |  %d Failed / %d Total  |  LowestY=%.2fm (%s)',
      [FLastReport.FailedAssertionsCount, Length(FLastReport.Assertions),
       FLastReport.LowestObservedY, FLastReport.LowestObservedActor]));

  C.Font.Style := [];
  C.TextOut(22, 33, Format('Peak Vehicle Speed: %.1f km/h  |  Peak Displacement: %.2fm  |  Readiness: %d/100  |  Restored: %s',
    [FLastReport.PeakVehicleSpeedKmh, FLastReport.PeakDisplacementMeters,
     FLastReport.WorldReadinessScore, BoolToStr(FLastReport.StateRestoredCleanly, True)]));

  PlotL := 48;
  PlotR := W - 20;
  PlotT := 68;
  PlotB := H - 26;
  PlotW := Max(20, PlotR - PlotL);
  PlotH := Max(20, PlotB - PlotT);

  C.Brush.Color := RGBToColor(14, 17, 24);
  C.Pen.Color := RGBToColor(58, 68, 86);
  C.Rectangle(PlotL, PlotT, PlotR, PlotB);

  if Length(FLastReport.StepSamples) < 2 then
    Exit;

  MinYVal := Min(FLastConfig.KillZMinY - 1.0, FLastReport.LowestObservedY - 1.0);
  MinYVal := Max(MinYVal, -60.0);
  MaxYVal := 8.0;
  MaxDispVal := Max(1.0, FLastReport.PeakDisplacementMeters * 1.15);

  { Dashed Kill-Z line }
  if (FLastConfig.KillZMinY >= MinYVal) and (FLastConfig.KillZMinY <= MaxYVal) then
  begin
    NormY := (FLastConfig.KillZMinY - MinYVal) / Max(0.01, MaxYVal - MinYVal);
    KillZY := PlotB - Round(NormY * PlotH);
    C.Pen.Color := RGBToColor(220, 72, 72);
    C.Pen.Style := psDash;
    C.MoveTo(PlotL, KillZY);
    C.LineTo(PlotR, KillZY);
    C.Pen.Style := psSolid;
    C.Font.Color := RGBToColor(240, 110, 110);
    C.TextOut(PlotL + 6, Max(PlotT + 2, KillZY - 16),
      Format('Kill-Z Threshold (%.1fm)', [FLastConfig.KillZMinY]));
  end;

  { Cyan curve: Peak Actor Displacement (m) }
  C.Pen.Color := RGBToColor(72, 198, 245);
  C.Pen.Width := 2;
  for I := 0 to High(FLastReport.StepSamples) - 1 do
  begin
    X1 := PlotL + Round((I / High(FLastReport.StepSamples)) * PlotW);
    X2 := PlotL + Round(((I + 1) / High(FLastReport.StepSamples)) * PlotW);
    NormDisp := Clamped(FLastReport.StepSamples[I].MaxDisplacementM / MaxDispVal, 0.0, 1.0);
    Y1 := PlotB - Round(NormDisp * PlotH);
    NormDisp := Clamped(FLastReport.StepSamples[I + 1].MaxDisplacementM / MaxDispVal, 0.0, 1.0);
    Y2 := PlotB - Round(NormDisp * PlotH);
    C.MoveTo(X1, Y1);
    C.LineTo(X2, Y2);
  end;

  { Green/Red curve: Lowest Actor Y Elevation }
  for I := 0 to High(FLastReport.StepSamples) - 1 do
  begin
    if FLastReport.StepSamples[I + 1].StepHealthy then
      C.Pen.Color := RGBToColor(92, 224, 136)
    else
      C.Pen.Color := RGBToColor(245, 86, 86);
    X1 := PlotL + Round((I / High(FLastReport.StepSamples)) * PlotW);
    X2 := PlotL + Round(((I + 1) / High(FLastReport.StepSamples)) * PlotW);
    NormY := Clamped((FLastReport.StepSamples[I].MinActorY - MinYVal) / Max(0.01, MaxYVal - MinYVal), 0.0, 1.0);
    Y1 := PlotB - Round(NormY * PlotH);
    NormY := Clamped((FLastReport.StepSamples[I + 1].MinActorY - MinYVal) / Max(0.01, MaxYVal - MinYVal), 0.0, 1.0);
    Y2 := PlotB - Round(NormY * PlotH);
    C.MoveTo(X1, Y1);
    C.LineTo(X2, Y2);
  end;
  C.Pen.Width := 1;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(175, 190, 215);
  C.TextOut(PlotL + 6, PlotB + 5,
    'Green/Red = Min Actor Elevation Y (m)   |   Cyan = Peak Dynamic Actor Displacement (m)');
end;

end.
