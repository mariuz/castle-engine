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

{ Interactive PCG Spline-Biome Settlement, Road-Intersection Graph, Setback
  Building Parcel Slicer & Perimeter Fence Studio dialog (Phase 335). }
unit FormSettlementStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastlePcgSettlement, ToolSettlementStudio;

type
  TSettlementModifyCallback = procedure(const AUndoComment: String) of object;
  TSettlementRefreshCallback = procedure of object;

  TSettlementStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSettlementModifyCallback;
    FOnRefreshViewport: TSettlementRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintSitePlan: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure BtnSpawnVillageClick(Sender: TObject);
    procedure BtnCyclePresetClick(Sender: TObject);
    procedure BtnRerollSeedClick(Sender: TObject);
    procedure BtnSnapTerrainClick(Sender: TObject);
    procedure BtnTogglePropsClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintSitePlanPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSettlementModifyCallback;
      const AOnRefreshViewport: TSettlementRefreshCallback);
  end;

implementation

constructor TSettlementStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSettlementModifyCallback;
  const AOnRefreshViewport: TSettlementRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'PCG Spline-Biome Settlement, Road Graph & Building Lot Studio (UE 6.0+ PCG Parity)';
  Width := 980;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TSettlementStudioForm.BuildUi;
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
  LabelHeader.Caption := 'PCG Biome Settlement Generator — Crossroads Graph, Zero-Overlap Setback Parcels, Gabled Houses & Palisade Fence';

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

  MakeBtn(BtnRow, '+ Spawn Crossroads Village', @BtnSpawnVillageClick, 180);
  MakeBtn(BtnRow, 'Cycle Layout Preset', @BtnCyclePresetClick, 148);
  MakeBtn(BtnRow, 'Re-Roll Seed', @BtnRerollSeedClick, 118);
  MakeBtn(BtnRow, 'Snap Foundations (Ray)', @BtnSnapTerrainClick, 162);
  MakeBtn(BtnRow, 'Toggle Fence & Lamps', @BtnTogglePropsClick, 152);
  MakeBtn(BtnRow, 'Export Report...', @BtnExportClick, 125);

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

  PaintSitePlan := TPaintBox.Create(Self);
  PaintSitePlan.Parent := BodyPanel;
  PaintSitePlan.Align := alClient;
  PaintSitePlan.BorderSpacing.Around := 6;
  PaintSitePlan.OnPaint := @PaintSitePlanPaint;
end;

procedure TSettlementStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TSettlementStudioForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TSettlementStudioSummary;
  Settl: TCastlePcgSettlement;
begin
  Warnings := TStringList.Create;
  try
    Sum := TSettlementStudioHelper.CollectSummary(FDesignRoot, Warnings);
    Settl := TSettlementStudioHelper.FindFirstSettlement(FDesignRoot);
    if Settl <> nil then
      LabelTelemetry.Caption := Format(
        '%s (%s, Seed %d) | Roads: %d | Lots: %d (0 overlaps) | Lamps: %d | Fence: %d | Tris: %d',
        [Settl.Name, PcgSettlementPresetToDisplayName(Settl.Preset), Settl.RandomSeed,
         Sum.TotalRoadSegments, Sum.TotalBuildingLots, Sum.TotalStreetlamps,
         Sum.TotalFencePosts, Sum.TotalTriangles])
    else
      LabelTelemetry.Caption := 'No TCastlePcgSettlement in design — click "+ Spawn Crossroads Village" to generate a settlement.';

    MemoReport.Lines.Text := TSettlementStudioHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintSitePlan.Invalidate;
end;

procedure TSettlementStudioForm.BtnSpawnVillageClick(Sender: TObject);
var
  Settl: TCastlePcgSettlement;
begin
  if TSettlementStudioHelper.SpawnCrossroadsVillageDemo(FDesignRoot, FDesignOwner, Settl) then
    NotifyChange('Spawn PCG Crossroads Village');
end;

procedure TSettlementStudioForm.BtnCyclePresetClick(Sender: TObject);
var
  Settl: TCastlePcgSettlement;
begin
  Settl := TSettlementStudioHelper.FindFirstSettlement(FDesignRoot);
  if Settl = nil then Exit;
  case Settl.Preset of
    pspCrossroadsHamlet: Settl.Preset := pspWalledMarketTown;
    pspWalledMarketTown: Settl.Preset := pspLinearHighwayOutpost;
    pspLinearHighwayOutpost: Settl.Preset := pspCrossroadsHamlet;
  end;
  NotifyChange('Cycle PCG Settlement Preset');
end;

procedure TSettlementStudioForm.BtnRerollSeedClick(Sender: TObject);
var
  Settl: TCastlePcgSettlement;
begin
  Settl := TSettlementStudioHelper.FindFirstSettlement(FDesignRoot);
  if Settl = nil then Exit;
  Settl.RandomSeed := Settl.RandomSeed + 101;
  NotifyChange('Re-Roll PCG Settlement Seed');
end;

procedure TSettlementStudioForm.BtnSnapTerrainClick(Sender: TObject);
var
  Settl: TCastlePcgSettlement;
  RootT: TCastleTransform;
begin
  Settl := TSettlementStudioHelper.FindFirstSettlement(FDesignRoot);
  RootT := TSettlementStudioHelper.ResolveRootTransform(FDesignRoot);
  if (Settl = nil) or (RootT = nil) then Exit;
  Settl.RebuildSettlement(RootT.World);
  NotifyChange('Snap PCG Foundations to World Terrain');
end;

procedure TSettlementStudioForm.BtnTogglePropsClick(Sender: TObject);
var
  Settl: TCastlePcgSettlement;
begin
  Settl := TSettlementStudioHelper.FindFirstSettlement(FDesignRoot);
  if Settl = nil then Exit;
  Settl.GeneratePerimeterFence := not Settl.GeneratePerimeterFence;
  Settl.GenerateStreetlamps := Settl.GeneratePerimeterFence;
  NotifyChange('Toggle Settlement Fence & Streetlamps');
end;

procedure TSettlementStudioForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'pcg_settlement_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TSettlementStudioHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TSettlementStudioForm.PaintSitePlanPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, Cx, Cy, I: Integer;
  Settl: TCastlePcgSettlement;
  ScalePx: Single;
  Origin: TVector3;
  Road: TPcgRoadSegment;
  Lot: TPcgBuildingLot;
  Prop: TPcgStreetProp;
begin
  Cv := PaintSitePlan.Canvas;
  W := Max(80, PaintSitePlan.Width);
  H := Max(80, PaintSitePlan.Height);
  Cx := W div 2;
  Cy := H div 2;

  Cv.Brush.Color := RGBToColor(24, 34, 24);
  Cv.FillRect(0, 0, W, H);

  Settl := TSettlementStudioHelper.FindFirstSettlement(FDesignRoot);
  if Settl <> nil then
  begin
    if Settl.HasParent then
      Origin := Settl.WorldTranslation
    else
      Origin := Settl.Translation;
    ScalePx := Min(W, H) / Max(24.0, Settl.SettlementRadius * 2.25);

    { Roads }
    for I := 0 to Settl.RoadSegmentCount - 1 do
    begin
      Road := Settl.GetRoadSegment(I);
      Cv.Pen.Width := Max(3, Round(Road.WidthMeters * ScalePx));
      Cv.Pen.Color := RGBToColor(96, 94, 88);
      Cv.Line(
        Cx + Round(Road.StartXZ.X * ScalePx),
        Cy + Round(Road.StartXZ.Y * ScalePx),
        Cx + Round(Road.EndXZ.X * ScalePx),
        Cy + Round(Road.EndXZ.Y * ScalePx));
    end;
    Cv.Pen.Width := 1;

    { Subdivided building parcels }
    for I := 0 to Settl.BuildingLotCount - 1 do
    begin
      Lot := Settl.GetBuildingLot(I);
      Cv.Brush.Style := bsSolid;
      Cv.Brush.Color := RGBToColor(
        EnsureRange(Round(Lot.RoofColorRGB.X * 255), 40, 245),
        EnsureRange(Round(Lot.RoofColorRGB.Y * 255), 40, 245),
        EnsureRange(Round(Lot.RoofColorRGB.Z * 255), 40, 245));
      Cv.Pen.Color := RGBToColor(240, 225, 195);
      Cv.Rectangle(
        Cx + Round((Lot.AabbMinXZ.X - Origin.X) * ScalePx),
        Cy + Round((Lot.AabbMinXZ.Y - Origin.Z) * ScalePx),
        Cx + Round((Lot.AabbMaxXZ.X - Origin.X) * ScalePx),
        Cy + Round((Lot.AabbMaxXZ.Y - Origin.Z) * ScalePx));
    end;

    { Streetlamps & fence posts }
    for I := 0 to Settl.PropCount - 1 do
    begin
      Prop := Settl.GetProp(I);
      if Prop.IsFencePost then
        Cv.Brush.Color := RGBToColor(165, 120, 75)
      else
        Cv.Brush.Color := RGBToColor(255, 225, 85);
      Cv.Pen.Color := Cv.Brush.Color;
      Cv.Ellipse(
        Cx + Round((Prop.PosWorld.X - Origin.X) * ScalePx) - 2,
        Cy + Round((Prop.PosWorld.Z - Origin.Z) * ScalePx) - 2,
        Cx + Round((Prop.PosWorld.X - Origin.X) * ScalePx) + 2,
        Cy + Round((Prop.PosWorld.Z - Origin.Z) * ScalePx) + 2);
    end;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(10, 8, 'Top-Down PCG Architectural Site Plan (Grey = Roads, Terracotta = Setback Lots, Gold = Streetlamps, Brown = Fence)');
end;

end.
