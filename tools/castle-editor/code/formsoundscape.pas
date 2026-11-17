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

{ Interactive Ambient Soundscape Biome Director, Elevation/Time-of-Day One-Shot
  Scatter & Acoustic Occlusion Studio dialog (Phase 345). }
unit FormSoundscape;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleSoundscape, ToolSoundscape;

type
  TSoundscapeModifyCallback = procedure(const AUndoComment: String) of object;
  TSoundscapeRefreshCallback = procedure of object;

  TSoundscapeForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSoundscapeModifyCallback;
    FOnRefreshViewport: TSoundscapeRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintRadar: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure RescatterContext(const AComment: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnDawnForestClick(Sender: TObject);
    procedure BtnMidnightCricketsClick(Sender: TObject);
    procedure BtnAlpinePeakClick(Sender: TObject);
    procedure BtnCavernEnclosureClick(Sender: TObject);
    procedure BtnStepCallsClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintRadarPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSoundscapeModifyCallback;
      const AOnRefreshViewport: TSoundscapeRefreshCallback);
  end;

implementation

constructor TSoundscapeForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSoundscapeModifyCallback;
  const AOnRefreshViewport: TSoundscapeRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Ambient Soundscape Biome Director & Acoustic Ray Occlusion Studio (UE 6.0+ Soundscape Parity)';
  Width := 1040;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TSoundscapeForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 160): TButton;
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
  LabelHeader.Caption := 'Ambient Soundscape Biome Director — Context-Reactive Palettes, 3D Hemisphere Scatter & WorldRay Acoustic Wall Muffling';

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
  MakeBtn(BtnRow1, '+ Spawn Acoustic Biome Demo', @BtnSpawnDemoClick, 198);
  MakeBtn(BtnRow1, 'Dawn Forest (07:00)', @BtnDawnForestClick, 158);
  MakeBtn(BtnRow1, 'Night Crickets (23:00)', @BtnMidnightCricketsClick, 168);
  MakeBtn(BtnRow1, 'Alpine Peak (85m Y)', @BtnAlpinePeakClick, 164);
  MakeBtn(BtnRow1, 'Cavern Drips (Indoor)', @BtnCavernEnclosureClick, 168);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Scatter + Step (+0.5s)', @BtnStepCallsClick, 174);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 184);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 410;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintRadar := TPaintBox.Create(Self);
  PaintRadar.Parent := BodyPanel;
  PaintRadar.Align := alClient;
  PaintRadar.BorderSpacing.Around := 6;
  PaintRadar.OnPaint := @PaintRadarPaint;
end;

procedure TSoundscapeForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TSoundscapeForm.RescatterContext(const AComment: String);
var
  D: TCastleSoundscapeDirector;
  RootT: TCastleTransform;
  I: Integer;
begin
  D := TSoundscapeHelper.FindFirstDirector(FDesignRoot);
  RootT := TSoundscapeHelper.ResolveRootTransform(FDesignRoot);
  if (D = nil) or (RootT = nil) then Exit;
  D.ClearActiveCalls;
  for I := 1 to 8 do
    D.SpawnScatterCall(RootT, Vector3(0.0, 1.7, 0.0));
  NotifyChange(AComment);
end;

procedure TSoundscapeForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TSoundscapeStudioSummary;
begin
  Warnings := TStringList.Create;
  try
    Sum := TSoundscapeHelper.CollectSummary(FDesignRoot, Warnings);
    LabelTelemetry.Caption := Format(
      'Dominant Biome: %s | Active 3D Calls: %d | Wall-Occluded (LPF 950Hz): %d | Total Spawned: %d',
      [Sum.DominantLayerName, Sum.ActiveCalls, Sum.OccludedCalls, Sum.TotalSpawned]);
    MemoReport.Lines.Text := TSoundscapeHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintRadar.Invalidate;
end;

procedure TSoundscapeForm.BtnSpawnDemoClick(Sender: TObject);
var
  D: TCastleSoundscapeDirector;
begin
  if TSoundscapeHelper.SpawnAcousticBiomeSoundscapeDemo(FDesignRoot, FDesignOwner, D) then
    NotifyChange('Spawn Ambient Soundscape Acoustic Demo');
end;

procedure TSoundscapeForm.BtnDawnForestClick(Sender: TObject);
var
  D: TCastleSoundscapeDirector;
begin
  D := TSoundscapeHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;
  D.HourOfDay := 7.0;
  D.ListenerAltitudeY := 4.0;
  D.IndoorEnclosureRatio := 0.0;
  RescatterContext('Soundscape Context: Dawn Forest');
end;

procedure TSoundscapeForm.BtnMidnightCricketsClick(Sender: TObject);
var
  D: TCastleSoundscapeDirector;
begin
  D := TSoundscapeHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;
  D.HourOfDay := 23.0;
  D.ListenerAltitudeY := 4.0;
  D.IndoorEnclosureRatio := 0.0;
  RescatterContext('Soundscape Context: Nocturnal Crickets');
end;

procedure TSoundscapeForm.BtnAlpinePeakClick(Sender: TObject);
var
  D: TCastleSoundscapeDirector;
begin
  D := TSoundscapeHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;
  D.HourOfDay := 13.0;
  D.ListenerAltitudeY := 85.0;
  D.IndoorEnclosureRatio := 0.0;
  RescatterContext('Soundscape Context: High-Peak Alpine Wind');
end;

procedure TSoundscapeForm.BtnCavernEnclosureClick(Sender: TObject);
var
  D: TCastleSoundscapeDirector;
begin
  D := TSoundscapeHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;
  D.IndoorEnclosureRatio := 0.85;
  RescatterContext('Soundscape Context: Subterranean Cavern Drips');
end;

procedure TSoundscapeForm.BtnStepCallsClick(Sender: TObject);
var
  D: TCastleSoundscapeDirector;
  RootT: TCastleTransform;
begin
  D := TSoundscapeHelper.FindFirstDirector(FDesignRoot);
  RootT := TSoundscapeHelper.ResolveRootTransform(FDesignRoot);
  if (D = nil) or (RootT = nil) then Exit;
  D.StepSoundscape(RootT, Vector3(0.0, 1.7, 0.0), 0.50);
  NotifyChange('Step Ambient Soundscape (+0.5s)');
end;

procedure TSoundscapeForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'ambient_soundscape_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TSoundscapeHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TSoundscapeForm.PaintRadarPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, CX, CY, Rad, I, EX, EZ: Integer;
  D: TCastleSoundscapeDirector;
  C: TSoundscapeActiveCall;
  ScalePx: Single;
begin
  Cv := PaintRadar.Canvas;
  W := Max(200, PaintRadar.Width);
  H := Max(200, PaintRadar.Height);
  CX := W div 2;
  CY := H div 2 + 12;
  Rad := Min(W, H) div 2 - 42;

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);

  { Listener XZ acoustic radar }
  Cv.Brush.Color := RGBToColor(22, 28, 40);
  Cv.Pen.Color := RGBToColor(58, 76, 102);
  Cv.Ellipse(CX - Rad, CY - Rad, CX + Rad, CY + Rad);

  { Stone bunker wall silhouette at Z = -5.5m }
  D := TSoundscapeHelper.FindFirstDirector(FDesignRoot);
  if D <> nil then
  begin
    ScalePx := Rad / Max(5.0, D.SpawnRadiusMax);
    Cv.Brush.Color := RGBToColor(96, 104, 120);
    Cv.Rectangle(CX - Round(8.0 * ScalePx), CY - Round(6.1 * ScalePx),
                 CX + Round(8.0 * ScalePx), CY - Round(4.9 * ScalePx));

    for I := 0 to D.CallPoolCapacity - 1 do
    begin
      C := D.GetActiveCall(I);
      if not C.Active then Continue;
      EX := EnsureRange(CX + Round(C.WorldPos.X * ScalePx), 16, W - 16);
      EZ := EnsureRange(CY + Round(C.WorldPos.Z * ScalePx), 36, H - 16);
      if C.Occluded then
      begin
        Cv.Pen.Color := RGBToColor(238, 86, 72);
        Cv.Brush.Color := RGBToColor(238, 86, 72);
      end else
      begin
        Cv.Pen.Color := RGBToColor(68, 218, 132);
        Cv.Brush.Color := RGBToColor(68, 218, 132);
      end;
      Cv.Line(CX, CY, EX, EZ);
      Cv.Ellipse(EX - 6, EZ - 6, EX + 6, EZ + 6);
    end;
  end;

  Cv.Brush.Color := RGBToColor(86, 178, 255);
  Cv.Ellipse(CX - 7, CY - 7, CX + 7, CY + 7);
  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(16, 10, 'Top-Down XZ Acoustic Radar (Green = Clear 20kHz LOS, Red = Wall-Occluded 950Hz)');
  Cv.Font.Style := [];
end;

end.
