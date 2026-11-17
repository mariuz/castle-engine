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

{ Interactive MegaLights Clustered Tile Light-Grid Culler, Procedural Gobo
  Cookie & Flicker Profile Studio dialog (Phase 341). }
unit FormMegaLights;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleMegaLights, ToolMegaLights;

type
  TMegaLightsModifyCallback = procedure(const AUndoComment: String) of object;
  TMegaLightsRefreshCallback = procedure of object;

  TMegaLightsForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMegaLightsModifyCallback;
    FOnRefreshViewport: TMegaLightsRefreshCallback;
    FPreviewGobo: TLightGoboPattern;
    FPreviewTimeSec: Single;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintHeatmap: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure BtnSpawnAlleyClick(Sender: TObject);
    procedure BtnRebuildClustersClick(Sender: TObject);
    procedure BtnStepFlickerClick(Sender: TObject);
    procedure BtnCamFarCullClick(Sender: TObject);
    procedure BtnCamNearRestoreClick(Sender: TObject);
    procedure BtnCycleGoboClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintHeatmapPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMegaLightsModifyCallback;
      const AOnRefreshViewport: TMegaLightsRefreshCallback);
  end;

implementation

constructor TMegaLightsForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMegaLightsModifyCallback;
  const AOnRefreshViewport: TMegaLightsRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FPreviewGobo := lgpWindowVenetianBlinds;
  FPreviewTimeSec := 0.0;

  Caption := 'MegaLights Clustered Light-Grid Culler, Gobo Cookie & Flicker Studio (UE 6.0+ MegaLights Parity)';
  Width := 1020;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TMegaLightsForm.BuildUi;
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
  LabelHeader.Caption := 'MegaLights Clustered Light-Grid & Light Functions — 3D Tile Overlap Heatmap, Distance Culling & Procedural Gobo Cookies';

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
  MakeBtn(BtnRow1, '+ Spawn 32-Light Neon Alley', @BtnSpawnAlleyClick, 192);
  MakeBtn(BtnRow1, 'Rebuild 3D Light Grid', @BtnRebuildClustersClick, 165);
  MakeBtn(BtnRow1, 'Step Flicker (+0.15s)', @BtnStepFlickerClick, 162);
  MakeBtn(BtnRow1, 'Cam Far (180m: Cull!)', @BtnCamFarCullClick, 162);
  MakeBtn(BtnRow1, 'Cam Alley (0m: Active)', @BtnCamNearRestoreClick, 168);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Cycle Gobo Cookie Mask', @BtnCycleGoboClick, 175);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 182);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 370;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintHeatmap := TPaintBox.Create(Self);
  PaintHeatmap.Parent := BodyPanel;
  PaintHeatmap.Align := alClient;
  PaintHeatmap.BorderSpacing.Around := 6;
  PaintHeatmap.OnPaint := @PaintHeatmapPaint;
end;

procedure TMegaLightsForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TMegaLightsForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TMegaLightsStudioSummary;
begin
  Warnings := TStringList.Create;
  try
    Sum := TMegaLightsHelper.CollectSummary(FDesignRoot, Warnings);
    LabelTelemetry.Caption := Format(
      'Lights Active/Total/Culled: %d / %d / %d | Peak Tile Overlap: %d | Overflow Tiles: %d | Gobo: %s',
      [Sum.ActiveLights, Sum.TotalLights, Sum.CulledLights,
       Sum.PeakTileLights, Sum.OverflowTiles, GoboPatternToDisplayName(FPreviewGobo)]);
    MemoReport.Lines.Text := TMegaLightsHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintHeatmap.Invalidate;
end;

procedure TMegaLightsForm.BtnSpawnAlleyClick(Sender: TObject);
var
  Mgr: TCastleMegaLightsManager;
begin
  if TMegaLightsHelper.SpawnCyberpunkAlleyMegaLightsDemo(FDesignRoot, FDesignOwner, Mgr) then
    NotifyChange('Spawn 32-Light MegaLights Alley');
end;

procedure TMegaLightsForm.BtnRebuildClustersClick(Sender: TObject);
var
  Mgr: TCastleMegaLightsManager;
  RootT: TCastleTransform;
begin
  Mgr := TMegaLightsHelper.FindFirstManager(FDesignRoot);
  RootT := TMegaLightsHelper.ResolveRootTransform(FDesignRoot);
  if (Mgr = nil) or (RootT = nil) then Exit;
  Mgr.RebuildLightClusters(RootT, Vector3(0, 2, 0));
  NotifyChange('Rebuild MegaLights 3D Cluster Grid');
end;

procedure TMegaLightsForm.BtnStepFlickerClick(Sender: TObject);
begin
  FPreviewTimeSec := FPreviewTimeSec + 0.15;
  TMegaLightsHelper.StepAllLightFunctions(FDesignRoot, 0.15);
  NotifyChange('Step Light-Function Flicker');
end;

procedure TMegaLightsForm.BtnCamFarCullClick(Sender: TObject);
var
  Mgr: TCastleMegaLightsManager;
  RootT: TCastleTransform;
begin
  Mgr := TMegaLightsHelper.FindFirstManager(FDesignRoot);
  RootT := TMegaLightsHelper.ResolveRootTransform(FDesignRoot);
  if (Mgr = nil) or (RootT = nil) then Exit;
  Mgr.RebuildLightClusters(RootT, Vector3(0, 10, 180));
  NotifyChange('MegaLights Far Camera Distance Cull');
end;

procedure TMegaLightsForm.BtnCamNearRestoreClick(Sender: TObject);
var
  Mgr: TCastleMegaLightsManager;
  RootT: TCastleTransform;
begin
  Mgr := TMegaLightsHelper.FindFirstManager(FDesignRoot);
  RootT := TMegaLightsHelper.ResolveRootTransform(FDesignRoot);
  if (Mgr = nil) or (RootT = nil) then Exit;
  Mgr.RebuildLightClusters(RootT, Vector3(0, 2, 0));
  NotifyChange('MegaLights Near Alley Restore');
end;

procedure TMegaLightsForm.BtnCycleGoboClick(Sender: TObject);
begin
  case FPreviewGobo of
    lgpNone:                 FPreviewGobo := lgpWindowVenetianBlinds;
    lgpWindowVenetianBlinds: FPreviewGobo := lgpUnderwaterCaustics;
    lgpUnderwaterCaustics:   FPreviewGobo := lgpCathedralRoseGrate;
    lgpCathedralRoseGrate:   FPreviewGobo := lgpIndustrialFanBlades;
    lgpIndustrialFanBlades:  FPreviewGobo := lgpNone;
  end;
  RefreshUi;
end;

procedure TMegaLightsForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'megalights_cluster_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TMegaLightsHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TMegaLightsForm.PaintHeatmapPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, HalfW, X, Z, Cnt, CellW, CellH, GoboRes, Lum: Integer;
  Mgr: TCastleMegaLightsManager;
  MaskVal: Single;
begin
  Cv := PaintHeatmap.Canvas;
  W := Max(160, PaintHeatmap.Width);
  H := Max(160, PaintHeatmap.Height);
  HalfW := W div 2;

  Cv.Brush.Color := RGBToColor(16, 18, 24);
  Cv.FillRect(0, 0, W, H);
  Cv.Pen.Color := RGBToColor(52, 60, 76);
  Cv.Line(HalfW, 0, HalfW, H);

  { Left pane: Top-down XZ clustered tile light-density heatmap }
  Mgr := TMegaLightsHelper.FindFirstManager(FDesignRoot);
  if Mgr <> nil then
  begin
    CellW := Max(4, (HalfW - 24) div Mgr.TilesX);
    CellH := Max(4, (H - 42) div Mgr.TilesZ);
    for Z := 0 to Mgr.TilesZ - 1 do
      for X := 0 to Mgr.TilesX - 1 do
      begin
        Cnt := Mgr.MaxColumnLightCountXZ(X, Z);
        if Cnt = 0 then
          Cv.Brush.Color := RGBToColor(24, 28, 36)
        else if Cnt <= Mgr.MaxLightsPerCluster div 2 then
          Cv.Brush.Color := RGBToColor(38, 128, 96)
        else if Cnt <= Mgr.MaxLightsPerCluster then
          Cv.Brush.Color := RGBToColor(218, 168, 48)
        else
          Cv.Brush.Color := RGBToColor(235, 65, 58);
        Cv.Pen.Color := RGBToColor(35, 42, 52);
        Cv.Rectangle(12 + X * CellW, 30 + Z * CellH,
                     12 + (X + 1) * CellW, 30 + (Z + 1) * CellH);
      end;
  end;

  { Right pane: Procedural Gobo Cookie UV preview }
  GoboRes := 36;
  CellW := Max(3, (HalfW - 32) div GoboRes);
  CellH := Max(3, (H - 48) div GoboRes);
  Cv.Pen.Style := psClear;
  for Z := 0 to GoboRes - 1 do
    for X := 0 to GoboRes - 1 do
    begin
      MaskVal := EvaluateGoboCookieMask(FPreviewGobo,
        X / Single(GoboRes - 1), Z / Single(GoboRes - 1), FPreviewTimeSec);
      Lum := EnsureRange(Round(MaskVal * 245.0), 8, 250);
      Cv.Brush.Color := RGBToColor(Lum, Round(Lum * 0.92), Round(Lum * 0.72));
      Cv.Rectangle(HalfW + 16 + X * CellW, 30 + Z * CellH,
                   HalfW + 16 + (X + 1) * CellW + 1, 30 + (Z + 1) * CellH + 1);
    end;
  Cv.Pen.Style := psSolid;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 8, 'Clustered XZ Light-Tile Density Heatmap');
  Cv.TextOut(HalfW + 16, 8, 'Gobo Cookie: ' + GoboPatternToDisplayName(FPreviewGobo));
end;

end.
