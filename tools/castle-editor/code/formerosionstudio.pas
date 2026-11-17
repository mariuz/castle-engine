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

{ Interactive Landscape Thermal Talus & Droplet Hydraulic Erosion, Sediment
  Deposition & Splatmap Baker Studio dialog (Phase 340). }
unit FormErosionStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleImages, CastleUtils,
  CastleErosionBaker, ToolErosionStudio;

type
  TErosionModifyCallback = procedure(const AUndoComment: String) of object;
  TErosionRefreshCallback = procedure of object;

  TErosionStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TErosionModifyCallback;
    FOnRefreshViewport: TErosionRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintHeightMap: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure BtnSpawnTerrainClick(Sender: TObject);
    procedure BtnThermalStepClick(Sender: TObject);
    procedure BtnHydraulicDropsClick(Sender: TObject);
    procedure BtnResetBedrockClick(Sender: TObject);
    procedure BtnCyclePresetClick(Sender: TObject);
    procedure BtnExportSplatPngClick(Sender: TObject);
    procedure BtnExportReportClick(Sender: TObject);
    procedure PaintHeightMapPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TErosionModifyCallback;
      const AOnRefreshViewport: TErosionRefreshCallback);
  end;

implementation

constructor TErosionStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TErosionModifyCallback;
  const AOnRefreshViewport: TErosionRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Landscape Thermal Talus & Hydraulic Raindrop Erosion Baker Studio (UE 6.0+ Erosion Parity)';
  Width := 1020;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TErosionStudioForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

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
  TopBar.Height := 126;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'Landscape Thermal & Hydraulic Erosion — Mass-Conserving Talus Repose, Raindrop Gullies & 4-Channel RGBA Splatmap Baker';

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
  MakeBtn(BtnRow1, '+ Spawn Eroded Peak', @BtnSpawnTerrainClick, 165);
  MakeBtn(BtnRow1, 'Thermal Talus (+15 Passes)', @BtnThermalStepClick, 180);
  MakeBtn(BtnRow1, 'Rain +2,000 Droplets', @BtnHydraulicDropsClick, 165);
  MakeBtn(BtnRow1, 'Reset Raw Bedrock', @BtnResetBedrockClick, 152);
  MakeBtn(BtnRow1, 'Cycle Landform Preset', @BtnCyclePresetClick, 165);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Export RGBA Splatmap PNG...', @BtnExportSplatPngClick, 200);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportReportClick, 182);

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

  PaintHeightMap := TPaintBox.Create(Self);
  PaintHeightMap.Parent := BodyPanel;
  PaintHeightMap.Align := alClient;
  PaintHeightMap.BorderSpacing.Around := 6;
  PaintHeightMap.OnPaint := @PaintHeightMapPaint;
end;

procedure TErosionStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TErosionStudioForm.RefreshUi;
var
  B: TCastleTerrainErosionBaker;
begin
  B := TErosionStudioHelper.FindFirstBaker(FDesignRoot);
  if B <> nil then
    LabelTelemetry.Caption := Format(
      '%s (%s) | Grid: %dx%d | Vol: %.0f m^3 | MaxSlope: %.1f° | Thermal: %d | Droplets: %d',
      [B.Name, ErosionPresetToDisplayName(B.Preset), B.GridSize, B.GridSize,
       B.TotalTerrainVolume, B.MaxSlopeAngleDeg, B.ThermalPassesRun, B.DropletsSimulated])
  else
    LabelTelemetry.Caption := 'No TCastleTerrainErosionBaker in design — click "+ Spawn Eroded Peak" to create a terrain.';

  MemoReport.Lines.Text := TErosionStudioHelper.BuildMarkdownReport(FDesignRoot);
  PaintHeightMap.Invalidate;
end;

procedure TErosionStudioForm.BtnSpawnTerrainClick(Sender: TObject);
var
  B: TCastleTerrainErosionBaker;
begin
  if TErosionStudioHelper.SpawnErodedAlpinePeakDemo(FDesignRoot, FDesignOwner, B) then
    NotifyChange('Spawn Eroded Alpine Peak');
end;

procedure TErosionStudioForm.BtnThermalStepClick(Sender: TObject);
var
  B: TCastleTerrainErosionBaker;
begin
  B := TErosionStudioHelper.FindFirstBaker(FDesignRoot);
  if B = nil then Exit;
  B.RunThermalErosionSteps(15);
  NotifyChange('Run 15 Thermal Talus Passes');
end;

procedure TErosionStudioForm.BtnHydraulicDropsClick(Sender: TObject);
var
  B: TCastleTerrainErosionBaker;
begin
  B := TErosionStudioHelper.FindFirstBaker(FDesignRoot);
  if B = nil then Exit;
  B.RunHydraulicDroplets(2000);
  NotifyChange('Simulate 2,000 Hydraulic Raindrops');
end;

procedure TErosionStudioForm.BtnResetBedrockClick(Sender: TObject);
var
  B: TCastleTerrainErosionBaker;
begin
  B := TErosionStudioHelper.FindFirstBaker(FDesignRoot);
  if B = nil then Exit;
  B.ResetHeightfieldToPreset;
  NotifyChange('Reset Terrain to Raw Bedrock');
end;

procedure TErosionStudioForm.BtnCyclePresetClick(Sender: TObject);
var
  B: TCastleTerrainErosionBaker;
begin
  B := TErosionStudioHelper.FindFirstBaker(FDesignRoot);
  if B = nil then Exit;
  case B.Preset of
    etpAlpineVolcanicCone:    B.Preset := etpMesaPlateauEscarpment;
    etpMesaPlateauEscarpment: B.Preset := etpTwinRidgesValley;
    etpTwinRidgesValley:      B.Preset := etpAlpineVolcanicCone;
  end;
  NotifyChange('Cycle Erosion Landform Preset');
end;

procedure TErosionStudioForm.BtnExportSplatPngClick(Sender: TObject);
var
  B: TCastleTerrainErosionBaker;
  Dlg: TSaveDialog;
  Img: TRGBAlphaImage;
begin
  B := TErosionStudioHelper.FindFirstBaker(FDesignRoot);
  if B = nil then Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'PNG 4-Channel Splatmap (*.png)|*.png';
    Dlg.DefaultExt := 'png';
    Dlg.FileName := 'eroded_splatmap.png';
    if Dlg.Execute then
    begin
      Img := B.ExportSplatmapRgbaImage;
      try
        SaveImage(Img, Dlg.FileName);
      finally
        FreeAndNil(Img);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TErosionStudioForm.BtnExportReportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'erosion_baker_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TErosionStudioHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TErosionStudioForm.PaintHeightMapPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, X, Z, N, CellW, CellH, R, G, Bl: Integer;
  Baker: TCastleTerrainErosionBaker;
  Peak, Elev, Sed, Flw: Single;
begin
  Cv := PaintHeightMap.Canvas;
  W := Max(120, PaintHeightMap.Width);
  H := Max(120, PaintHeightMap.Height);
  Cv.Brush.Color := RGBToColor(18, 22, 26);
  Cv.FillRect(0, 0, W, H);

  Baker := TErosionStudioHelper.FindFirstBaker(FDesignRoot);
  if Baker <> nil then
  begin
    N := Baker.GridSize;
    Peak := Max(1.0, Baker.PeakElevation);
    CellW := Max(2, (W - 24) div N);
    CellH := Max(2, (H - 36) div N);
    Cv.Pen.Style := psClear;
    for Z := 0 to N - 1 do
      for X := 0 to N - 1 do
      begin
        Elev := EnsureRange(Baker.SampleHeight(X, Z) / Peak, 0.0, 1.0);
        Sed := EnsureRange(Baker.SampleSediment(X, Z) * 2.5, 0.0, 1.0);
        Flw := EnsureRange(Baker.SampleFlow(X, Z) * 0.40, 0.0, 1.0);

        R := Round(Lerp(Elev, 45.0, 195.0) * (1.0 - 0.5 * Flw) + Sed * 65.0);
        G := Round(Lerp(Elev, 95.0, 190.0) * (1.0 - 0.25 * Flw) + Sed * 35.0);
        Bl := Round(Lerp(Elev, 42.0, 185.0) + Flw * 145.0);

        Cv.Brush.Color := RGBToColor(
          EnsureRange(R, 0, 255),
          EnsureRange(G, 0, 255),
          EnsureRange(Bl, 0, 255));
        Cv.Rectangle(12 + X * CellW, 28 + Z * CellH,
                     12 + (X + 1) * CellW + 1, 28 + (Z + 1) * CellH + 1);
      end;
    Cv.Pen.Style := psSolid;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 6, 'Top-Down Elevation, Blue Hydraulic Flow Gullies & Tan Alluvial Sediment Aprons');
end;

end.
