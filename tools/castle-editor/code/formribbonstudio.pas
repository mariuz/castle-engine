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

{ Interactive Niagara-Style Sword-Slash / Projectile Ribbon Trail, Catmull-Rom
  Subdivider & Midpoint-Displaced Arc Lightning VFX Studio dialog (Phase 334). }
unit FormRibbonStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleRibbonTrail, ToolRibbonStudio;

type
  TRibbonModifyCallback = procedure(const AUndoComment: String) of object;
  TRibbonRefreshCallback = procedure of object;

  TRibbonStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TRibbonModifyCallback;
    FOnRefreshViewport: TRibbonRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintPreview: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnSwingSlashClick(Sender: TObject);
    procedure BtnDecayStepClick(Sender: TObject);
    procedure BtnCyclePresetClick(Sender: TObject);
    procedure BtnStrikeLightningClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintPreviewPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TRibbonModifyCallback;
      const AOnRefreshViewport: TRibbonRefreshCallback);
  end;

implementation

constructor TRibbonStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TRibbonModifyCallback;
  const AOnRefreshViewport: TRibbonRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Niagara Ribbon Slash Trail, Catmull-Rom Subdivider & Arc Lightning VFX Studio (UE 6.0+ Parity)';
  Width := 980;
  Height := 640;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TRibbonStudioForm.BuildUi;
var
  TopBar, BtnRow, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 152): TButton;
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
  TopBar.Height := 90;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'Niagara Ribbon Trail & Arc Lightning VFX — Dual-Socket Sword Arcs, Catmull-Rom Subdivider & Midpoint-Displaced Bolts';

  LabelTelemetry := TLabel.Create(Self);
  LabelTelemetry.Parent := TopBar;
  LabelTelemetry.Align := alTop;
  LabelTelemetry.BorderSpacing.Left := 6;
  LabelTelemetry.Caption := 'Telemetry: ready';

  BtnRow := TPanel.Create(Self);
  BtnRow.Parent := TopBar;
  BtnRow.Align := alTop;
  BtnRow.Height := 38;
  BtnRow.BevelOuter := bvNone;

  MakeBtn(BtnRow, '+ Spawn Slash + Tesla Arc', @BtnSpawnDemoClick, 178);
  MakeBtn(BtnRow, 'Swing 135° Katana Arc!', @BtnSwingSlashClick, 162);
  MakeBtn(BtnRow, 'Decay Trail (+0.10s)', @BtnDecayStepClick, 148);
  MakeBtn(BtnRow, 'Cycle Ribbon Preset', @BtnCyclePresetClick, 148);
  MakeBtn(BtnRow, 'Re-Strike Lightning!', @BtnStrikeLightningClick, 152);
  MakeBtn(BtnRow, 'Export Report...', @BtnExportClick, 128);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 380;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintPreview := TPaintBox.Create(Self);
  PaintPreview.Parent := BodyPanel;
  PaintPreview.Align := alClient;
  PaintPreview.BorderSpacing.Around := 6;
  PaintPreview.OnPaint := @PaintPreviewPaint;
end;

procedure TRibbonStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TRibbonStudioForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TRibbonStudioSummary;
  Rib: TCastleRibbonTrail;
  Beam: TCastleLightningBeam;
begin
  Warnings := TStringList.Create;
  try
    Sum := TRibbonStudioHelper.CollectSummary(FDesignRoot, Warnings);
    Rib := TRibbonStudioHelper.FindFirstRibbon(FDesignRoot);
    Beam := TRibbonStudioHelper.FindFirstLightning(FDesignRoot);
    if (Rib <> nil) or (Beam <> nil) then
      LabelTelemetry.Caption := Format(
        'Ribbons: %d (%d samples, %d tris, %.2fm arc) | Lightning Beams: %d (%d tris)',
        [Sum.RibbonCount, Sum.TotalActiveSamples, Sum.TotalRibbonTriangles,
         Sum.TotalArcLengthMeters, Sum.LightningCount, Sum.TotalLightningTriangles])
    else
      LabelTelemetry.Caption := 'No Ribbon/Lightning VFX in design — click "+ Spawn Slash + Tesla Arc" to create demo emitters.';

    MemoReport.Lines.Text := TRibbonStudioHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintPreview.Invalidate;
end;

procedure TRibbonStudioForm.BtnSpawnDemoClick(Sender: TObject);
var
  Rib: TCastleRibbonTrail;
  Beam: TCastleLightningBeam;
  Target: TCastleTransform;
begin
  if TRibbonStudioHelper.SpawnKatanaSlashAndLightningDemo(FDesignRoot, FDesignOwner, Rib, Beam, Target) then
    NotifyChange('Spawn Ribbon Slash & Lightning VFX');
end;

procedure TRibbonStudioForm.BtnSwingSlashClick(Sender: TObject);
var
  Rib: TCastleRibbonTrail;
begin
  Rib := TRibbonStudioHelper.FindFirstRibbon(FDesignRoot);
  if Rib = nil then Exit;
  TRibbonStudioHelper.SimulateSwordSlashArc(Rib, 12, 145.0);
  NotifyChange('Swing Katana Slash Arc');
end;

procedure TRibbonStudioForm.BtnDecayStepClick(Sender: TObject);
var
  Rib: TCastleRibbonTrail;
  WasEmit: Boolean;
begin
  Rib := TRibbonStudioHelper.FindFirstRibbon(FDesignRoot);
  if Rib = nil then Exit;
  WasEmit := Rib.Emitting;
  Rib.Emitting := False;
  Rib.StepTrail(0.10, False);
  Rib.Emitting := WasEmit;
  NotifyChange('Decay Ribbon Trail');
end;

procedure TRibbonStudioForm.BtnCyclePresetClick(Sender: TObject);
var
  Rib: TCastleRibbonTrail;
begin
  Rib := TRibbonStudioHelper.FindFirstRibbon(FDesignRoot);
  if Rib = nil then Exit;
  case Rib.Preset of
    rtpKatanaSunfireSlash: Rib.ApplyPreset(rtpArcaneProjectileComet);
    rtpArcaneProjectileComet: Rib.ApplyPreset(rtpCyberNeonDriftTrail);
    rtpCyberNeonDriftTrail: Rib.ApplyPreset(rtpKatanaSunfireSlash);
  end;
  TRibbonStudioHelper.SimulateSwordSlashArc(Rib, 10, 135.0);
  NotifyChange('Cycle Ribbon Preset');
end;

procedure TRibbonStudioForm.BtnStrikeLightningClick(Sender: TObject);
var
  Beam: TCastleLightningBeam;
begin
  Beam := TRibbonStudioHelper.FindFirstLightning(FDesignRoot);
  if Beam = nil then Exit;
  Beam.StrikeNow(Beam.RandomSeed + 37);
  NotifyChange('Re-Strike Lightning Beam');
end;

procedure TRibbonStudioForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'ribbon_lightning_vfx_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TRibbonStudioHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TRibbonStudioForm.PaintPreviewPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, HalfW, Cx1, Cy1, Cx2, Cy2, I: Integer;
  Rib: TCastleRibbonTrail;
  Beam: TCastleLightningBeam;
  S0, S1: TRibbonSample;
  Seg: TLightningSegment;
  Pivot, BStart, BEnd, Span: TVector3;
  Scale1, Scale2: Single;
begin
  Cv := PaintPreview.Canvas;
  W := Max(120, PaintPreview.Width);
  H := Max(120, PaintPreview.Height);
  HalfW := W div 2;

  Cv.Brush.Color := RGBToColor(16, 18, 26);
  Cv.FillRect(0, 0, W, H);
  Cv.Pen.Color := RGBToColor(52, 60, 78);
  Cv.Line(HalfW, 0, HalfW, H);

  { Left pane: Top-down XZ Katana Ribbon Arc }
  Cx1 := HalfW div 2;
  Cy1 := (H * 2) div 3;
  Scale1 := Min(HalfW, H) / 4.8;
  Rib := TRibbonStudioHelper.FindFirstRibbon(FDesignRoot);
  if (Rib <> nil) and (Rib.ActiveSampleCount >= 2) then
  begin
    Pivot := Rib.WorldTranslation;
    for I := 0 to Rib.ActiveSampleCount - 2 do
    begin
      S0 := Rib.GetSample(I);
      S1 := Rib.GetSample(I + 1);
      Cv.Pen.Width := 2;
      Cv.Pen.Color := RGBToColor(255, Max(60, 220 - I * 16), 70);
      Cv.Line(
        Cx1 + Round((S0.PosTip.X - Pivot.X) * Scale1),
        Cy1 + Round((S0.PosTip.Z - Pivot.Z) * Scale1),
        Cx1 + Round((S1.PosTip.X - Pivot.X) * Scale1),
        Cy1 + Round((S1.PosTip.Z - Pivot.Z) * Scale1));
      Cv.Pen.Width := 1;
      Cv.Pen.Color := RGBToColor(180, 95, 45);
      Cv.Line(
        Cx1 + Round((S0.PosBase.X - Pivot.X) * Scale1),
        Cy1 + Round((S0.PosBase.Z - Pivot.Z) * Scale1),
        Cx1 + Round((S0.PosTip.X - Pivot.X) * Scale1),
        Cy1 + Round((S0.PosTip.Z - Pivot.Z) * Scale1));
    end;
  end;

  { Right pane: Projected Lightning Bolt & Forks }
  Cx2 := HalfW + (HalfW div 2);
  Cy2 := H div 2;
  Beam := TRibbonStudioHelper.FindFirstLightning(FDesignRoot);
  if (Beam <> nil) and (Beam.TotalSegmentCount > 0) then
  begin
    BStart := Beam.BoltStartWorld;
    BEnd := Beam.BoltEndWorld;
    Span := 0.5 * (BStart + BEnd);
    Scale2 := Min(HalfW, H) / Max(4.0, PointsDistance(BStart, BEnd) * 1.35);
    for I := 0 to Beam.TotalSegmentCount - 1 do
    begin
      Seg := Beam.GetSegment(I);
      if Seg.IsFork then
      begin
        Cv.Pen.Width := 1;
        Cv.Pen.Color := RGBToColor(115, 185, 255);
      end else
      begin
        Cv.Pen.Width := 2;
        Cv.Pen.Color := RGBToColor(215, 245, 255);
      end;
      Cv.Line(
        Cx2 + Round((Seg.A.X - Span.X) * Scale2),
        Cy2 + Round((Seg.A.Z - Span.Z) * Scale2),
        Cx2 + Round((Seg.B.X - Span.X) * Scale2),
        Cy2 + Round((Seg.B.Z - Span.Z) * Scale2));
    end;
  end;
  Cv.Pen.Width := 1;
  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(10, 8, 'Blade / Projectile Ribbon Arc (XZ)');
  Cv.TextOut(HalfW + 10, 8, 'Midpoint-Displaced Lightning & Forks (XZ)');
end;

end.
