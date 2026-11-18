{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Visual Studio dialog for Grid2D Cellular Fire Spread & Ash (Phase 372). }
unit FormFireGrid2D;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleFireGrid2D, ToolFireGrid2D;

type
  TFireGrid2DModifiedCallback = procedure(const UndoComment: String) of object;
  TFireGrid2DRefreshCallback = procedure of object;

  TFireGrid2DForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TFireGrid2DModifiedCallback;
    FOnRefresh: TFireGrid2DRefreshCallback;
    FPaintGrid: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveGrid: TCastleFireSpreadGrid;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnPrairieClick(Sender: TObject);
    procedure BtnFirebreakClick(Sender: TObject);
    procedure BtnStepBurnClick(Sender: TObject);
    procedure BtnMonsoonDouseClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintFireHeatmap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TFireGrid2DModifiedCallback;
      const AOnRefresh: TFireGrid2DRefreshCallback);
  end;

implementation

constructor TFireGrid2DForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TFireGrid2DModifiedCallback;
  const AOnRefresh: TFireGrid2DRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Niagara Grid2D Cellular Fire Spread, Firebreak & Rain Studio (Phase 372)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TFireGrid2DForm.BuildUi;
var
  Lbl: TLabel;
  Row1, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String; const AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Align := alLeft;
    Result.AutoSize := True;
    Result.BorderSpacing.Around := 4;
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
  end;

begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Align := alTop;
  Lbl.BorderSpacing.Around := 8;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'UE 6.0+ Niagara Grid2D Combustion — Downwind Flame Advection, Stone Firebreak Trenches, Ash Burnout & Rain Douse';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 42;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn 16x16 Prairie Fire Grid', @BtnSpawnClick);
  MakeBtn(Row1, 'Dry Prairie (+X Wind)', @BtnPrairieClick);
  MakeBtn(Row1, 'Stone Firebreak Trench', @BtnFirebreakClick);
  MakeBtn(Row1, 'Step Combustion (+1.0s)', @BtnStepBurnClick);
  MakeBtn(Row1, 'Unleash Monsoon Rain (Extinguish!)', @BtnMonsoonDouseClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintGrid := TPaintBox.Create(Self);
  FPaintGrid.Parent := BodyPanel;
  FPaintGrid.Align := alLeft;
  FPaintGrid.Width := 480;
  FPaintGrid.OnPaint := @PaintFireHeatmap;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TFireGrid2DForm.ActiveGrid: TCastleFireSpreadGrid;
begin
  Result := TFireGrid2DHelper.FindFireGridInHierarchy(FDesignRoot);
end;

procedure TFireGrid2DForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TFireGrid2DForm.RefreshView;
begin
  FMemoReport.Lines.Text := TFireGrid2DHelper.GenerateFireGridReport(ActiveGrid);
  FPaintGrid.Invalidate;
end;

procedure TFireGrid2DForm.BtnSpawnClick(Sender: TObject);
var
  G: TCastleFireSpreadGrid;
begin
  if TFireGrid2DHelper.SpawnPrairieFireGridDemo(FDesignRoot, FDesignOwner, G) then
    NotifyChange('Spawn 16x16 Prairie Fire Spread Grid');
end;

procedure TFireGrid2DForm.BtnPrairieClick(Sender: TObject);
var
  G: TCastleFireSpreadGrid;
begin
  G := ActiveGrid;
  if G = nil then Exit;
  G.Preset := fgpDryGrasslandPrairie;
  NotifyChange('Reset to Dry Grassland Prairie Fire');
end;

procedure TFireGrid2DForm.BtnFirebreakClick(Sender: TObject);
var
  G: TCastleFireSpreadGrid;
begin
  G := ActiveGrid;
  if G = nil then Exit;
  G.Preset := fgpStoneFirebreakTrench;
  NotifyChange('Apply Stone Firebreak Trench Scenario');
end;

procedure TFireGrid2DForm.BtnStepBurnClick(Sender: TObject);
var
  G: TCastleFireSpreadGrid;
  I: Integer;
begin
  G := ActiveGrid;
  if G = nil then Exit;
  for I := 1 to 4 do
    G.StepCombustion(0.25);
  NotifyChange('Step Cellular Fire Spread (+1.0s)');
end;

procedure TFireGrid2DForm.BtnMonsoonDouseClick(Sender: TObject);
var
  G: TCastleFireSpreadGrid;
  I: Integer;
begin
  G := ActiveGrid;
  if G = nil then Exit;
  G.RainIntensity := 1.0;
  for I := 1 to 6 do
    G.StepCombustion(0.25);
  NotifyChange('Douse Fire Grid with Monsoon Downpour');
end;

procedure TFireGrid2DForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TFireGrid2DHelper.GenerateFireGridReport(ActiveGrid);
end;

procedure TFireGrid2DForm.PaintFireHeatmap(Sender: TObject);
var
  Cv: TCanvas;
  W, H, IX, IZ, Res, CellPx, OX, OY: Integer;
  G: TCastleFireSpreadGrid;
  Cell: TFireGridCell;
begin
  Cv := FPaintGrid.Canvas;
  W := FPaintGrid.Width;
  H := FPaintGrid.Height;
  Cv.Brush.Color := RGBToColor(16, 18, 22);
  Cv.FillRect(0, 0, W, H);

  G := ActiveGrid;
  if G = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn 16x16 Prairie Fire Grid" to inspect Grid2D Combustion.');
    Exit;
  end;

  Res := Max(1, G.GridResolution);
  CellPx := Min((W - 40) div Res, (H - 64) div Res);
  OX := (W - Res * CellPx) div 2;
  OY := 42;

  for IZ := 0 to Res - 1 do
    for IX := 0 to Res - 1 do
    begin
      Cell := G.GetCell(IX, IZ);
      case Cell.State of
        fcsUnburnedFuel:      Cv.Brush.Color := RGBToColor(52, 145, 62);
        fcsBurningActive:     Cv.Brush.Color := RGBToColor(255, 130, 28);
        fcsCharredAsh:        Cv.Brush.Color := RGBToColor(42, 40, 44);
        fcsNonFlammableStone: Cv.Brush.Color := RGBToColor(145, 150, 162);
      end;
      Cv.Rectangle(OX + IX * CellPx, OY + IZ * CellPx,
                   OX + (IX + 1) * CellPx - 1, OY + (IZ + 1) * CellPx - 1);
    end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(16, 12, Format('Grid2D Fire | Burning=%d | Ash=%d | Stone=%d', [
    G.Stats.BurningCells, G.Stats.CharredAshCells, G.Stats.StoneFirebreakCells]));
end;

end.
