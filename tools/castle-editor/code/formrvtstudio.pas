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

{ Interactive Runtime Virtual Texture (RVT) Tile Page Cache & Persistent
  Snow/Mud Footstep Trail Studio dialog (Phase 350). }
unit FormRvtStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleImages, CastleTransform,
  CastleRuntimeVt, ToolRvtStudio;

type
  TRvtModifyCallback = procedure(const AUndoComment: String) of object;
  TRvtRefreshCallback = procedure of object;

  TRvtStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TRvtModifyCallback;
    FOnRefreshViewport: TRvtRefreshCallback;
    FWalkAngleRad: Single;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintSurface: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    function EnsureRvt: TCastleRuntimeVirtualTexture;
    procedure BtnSpawnSnowClick(Sender: TObject);
    procedure BtnStampCircleWalkClick(Sender: TObject);
    procedure BtnCycleMaterialClick(Sender: TObject);
    procedure BtnStressLruPagesClick(Sender: TObject);
    procedure BtnSnowfillHealClick(Sender: TObject);
    procedure BtnExportHeightPngClick(Sender: TObject);
    procedure PaintSurfacePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TRvtModifyCallback;
      const AOnRefreshViewport: TRvtRefreshCallback);
  end;

implementation

constructor TRvtStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TRvtModifyCallback;
  const AOnRefreshViewport: TRvtRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FWalkAngleRad := 0.0;

  Caption := 'Runtime Virtual Texture (RVT) LRU Tile Cache & Snow/Mud Trail Studio (UE 6.0+ RVT Parity)';
  Width := 1060;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TRvtStudioForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 165): TButton;
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
  LabelHeader.Caption := 'Runtime Virtual Texture & Deformable Trails — LRU Page-Table Residency, Snow/Mud Boot Ruts, Raised Rim Berms & Snowfill Recovery';

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
  MakeBtn(BtnRow1, '+ Spawn Alpine Snow Trail', @BtnSpawnSnowClick, 190);
  MakeBtn(BtnRow1, 'Stamp Boot Walk (+6)', @BtnStampCircleWalkClick, 166);
  MakeBtn(BtnRow1, 'Cycle Snow / Mud / Sand', @BtnCycleMaterialClick, 180);
  MakeBtn(BtnRow1, 'Stress 24 LRU Tile Loads', @BtnStressLruPagesClick, 184);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Snowfill Recovery (+2.5s)', @BtnSnowfillHealClick, 188);
  MakeBtn(BtnRow2, 'Export Heightmap PNG...', @BtnExportHeightPngClick, 184);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 400;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintSurface := TPaintBox.Create(Self);
  PaintSurface.Parent := BodyPanel;
  PaintSurface.Align := alClient;
  PaintSurface.BorderSpacing.Around := 6;
  PaintSurface.OnPaint := @PaintSurfacePaint;
end;

procedure TRvtStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

function TRvtStudioForm.EnsureRvt: TCastleRuntimeVirtualTexture;
begin
  Result := TRvtStudioHelper.FindFirstRvt(FDesignRoot);
  if Result = nil then
    TRvtStudioHelper.SpawnAlpineSnowfieldRvtDemo(FDesignRoot, FDesignOwner, Result);
end;

procedure TRvtStudioForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TRvtStudioSummary;
begin
  Warnings := TStringList.Create;
  try
    Sum := TRvtStudioHelper.CollectSummary(FDesignRoot, Warnings);
    LabelTelemetry.Caption := Format(
      'LRU Pages: %d / %d | Hits/Misses/Evictions: %d / %d / %d | Deepest Rut: %.3fm | Max Berm: +%.3fm',
      [Sum.OccupiedPages, Sum.TotalPageSlots, Sum.CacheHits, Sum.CacheMisses,
       Sum.Evictions, Sum.DeepestRutMeters, Sum.HighestBermMeters]);
    MemoReport.Lines.Text := TRvtStudioHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintSurface.Invalidate;
end;

procedure TRvtStudioForm.BtnSpawnSnowClick(Sender: TObject);
var
  R: TCastleRuntimeVirtualTexture;
begin
  if TRvtStudioHelper.SpawnAlpineSnowfieldRvtDemo(FDesignRoot, FDesignOwner, R) then
    NotifyChange('Spawn Alpine Snowfield RVT');
end;

procedure TRvtStudioForm.BtnStampCircleWalkClick(Sender: TObject);
var
  R: TCastleRuntimeVirtualTexture;
  I: Integer;
begin
  R := EnsureRvt;
  if R = nil then Exit;
  for I := 1 to 6 do
  begin
    FWalkAngleRad := FWalkAngleRad + 0.34;
    R.StampFootprintOrTire(Cos(FWalkAngleRad) * 6.5, Sin(FWalkAngleRad) * 6.5, 0.62, 0.25);
  end;
  NotifyChange('Stamp 6 Snow/Mud Boot Prints');
end;

procedure TRvtStudioForm.BtnCycleMaterialClick(Sender: TObject);
var
  R: TCastleRuntimeVirtualTexture;
begin
  R := EnsureRvt;
  if R = nil then Exit;
  case R.SurfaceMaterial of
    rsmAlpineFreshSnow: R.SurfaceMaterial := rsmPeatBogMud;
    rsmPeatBogMud:      R.SurfaceMaterial := rsmDesertDuneSand;
    rsmDesertDuneSand:  R.SurfaceMaterial := rsmAlpineFreshSnow;
  end;
  NotifyChange('Switch RVT Surface Material');
end;

procedure TRvtStudioForm.BtnStressLruPagesClick(Sender: TObject);
var
  R: TCastleRuntimeVirtualTexture;
  I: Integer;
begin
  R := EnsureRvt;
  if R = nil then Exit;
  for I := 0 to 23 do
    R.RequestVirtualTile(I mod R.VirtualGridTiles, (I * 3) mod R.VirtualGridTiles, 0);
  NotifyChange('Stress 24 RVT Virtual Page Requests');
end;

procedure TRvtStudioForm.BtnSnowfillHealClick(Sender: TObject);
var
  R: TCastleRuntimeVirtualTexture;
begin
  R := TRvtStudioHelper.FindFirstRvt(FDesignRoot);
  if R = nil then Exit;
  R.StepThermalSnowfillRecovery(2.5);
  NotifyChange('Step Snowfill Trail Recovery (+2.5s)');
end;

procedure TRvtStudioForm.BtnExportHeightPngClick(Sender: TObject);
var
  R: TCastleRuntimeVirtualTexture;
  Dlg: TSaveDialog;
  Img: TRGBImage;
begin
  R := TRvtStudioHelper.FindFirstRvt(FDesignRoot);
  if R = nil then Exit;
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'PNG Image (*.png)|*.png';
    Dlg.DefaultExt := 'png';
    Dlg.FileName := 'rvt_snow_displacement.png';
    if Dlg.Execute then
    begin
      Img := R.ExportDisplacementGrayscaleImage;
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

procedure TRvtStudioForm.PaintSurfacePaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, IX, IZ, CellW, CellH, Lum: Integer;
  R: TCastleRuntimeVirtualTexture;
  HVal: Single;
begin
  Cv := PaintSurface.Canvas;
  W := Max(200, PaintSurface.Width);
  H := Max(200, PaintSurface.Height);

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);

  R := TRvtStudioHelper.FindFirstRvt(FDesignRoot);
  if R <> nil then
  begin
    CellW := Max(3, (W - 32) div R.GridResolution);
    CellH := Max(3, (H - 48) div R.GridResolution);
    Cv.Pen.Style := psClear;
    for IZ := 0 to R.GridResolution - 1 do
      for IX := 0 to R.GridResolution - 1 do
      begin
        HVal := R.SampleDisplacementGrid(IX, IZ);
        Lum := EnsureRange(Round(180.0 + HVal * 360.0), 28, 252);
        if HVal < -0.01 then
          Cv.Brush.Color := RGBToColor(Round(Lum * 0.65), Round(Lum * 0.82), Lum)
        else
          Cv.Brush.Color := RGBToColor(Lum, Lum, Lum);
        Cv.Rectangle(16 + IX * CellW, 34 + IZ * CellH,
                     16 + (IX + 1) * CellW + 1, 34 + (IZ + 1) * CellH + 1);
      end;
    Cv.Pen.Style := psSolid;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(16, 10, 'Top-Down Deformable Snow/Mud Heightfield (Blue = Rut Depression, White = Berm Rim)');
  Cv.Font.Style := [];
end;

end.
