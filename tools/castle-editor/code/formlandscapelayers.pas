{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Non-Destructive Landscape Edit Layers & Terrain-Carving
  Landscape Splines Studio featuring a Top-Down 4-Channel Splatmap + Hypsometric
  Spline Map, an East-West Cut/Fill Earthwork Profile Slice, an Interactive
  Edit Layer Stack, and Spline Corridor Inspector
  (Phase 394 — 114 UE Studios / 37 MCP). }
unit FormLandscapeLayers;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleLandscapeLayers, ToolLandscapeLayers;

type
  TLandscapeModifiedCallback = procedure(const UndoComment: String) of object;
  TLandscapeRefreshCallback = procedure of object;

  TLandscapeLayersForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TLandscapeModifiedCallback;
    FOnRefresh: TLandscapeRefreshCallback;

    FActiveLandscape: TCastleLandscapeLayerTerrain;

    FLblStatus: TLabel;
    FPaintMapAndSlice: TPaintBox;
    FPaintStack: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintSplatmapAndCutFillSlice(Sender: TObject);
    procedure PaintEditLayerStackAndSplines(Sender: TObject);

    procedure BtnSpawnAlpineClick(Sender: TObject);
    procedure BtnSpawnDesertClick(Sender: TObject);
    procedure BtnSpawnMoatClick(Sender: TObject);
    procedure BtnToggleSplineLayerClick(Sender: TObject);
    procedure BtnTogglePlateauLayerClick(Sender: TObject);
    procedure BtnHalfSplineOpacityClick(Sender: TObject);
    procedure BtnFullSplineOpacityClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TLandscapeModifiedCallback;
      const AOnRefresh: TLandscapeRefreshCallback);
  end;

implementation

function ClampByteCol(const V: Single): Byte;
begin
  Result := Byte(Round(EnsureRange(V, 0.0, 1.0) * 255));
end;

constructor TLandscapeLayersForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TLandscapeModifiedCallback;
  const AOnRefresh: TLandscapeRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Non-Destructive Landscape Edit Layers & Terrain-Carving Splines Studio (114 UE Studios / 37 MCP)';
  Position := poScreenCenter;
  Width := 1340;
  Height := 760;

  BuildUi;
  FActiveLandscape := TLandscapeLayersHelper.FindFirstLandscape(FDesignRoot);
  RefreshFromScene;
end;

procedure TLandscapeLayersForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlBottom, PnlRight: TPanel;
  BtnAlpine, BtnDesert, BtnMoat, BtnMuteSplines, BtnMutePlateau,
    BtnOp50, BtnOp100, BtnCopy, BtnClose: TButton;
  XPos: Integer;

  function MakeToolbarBtn(const ACaption: String; const AWidth: Integer;
    const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := PnlToolbar;
    Result.Left := XPos;
    Result.Top := 6;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    Inc(XPos, AWidth + 6);
  end;

begin
  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;
  PnlToolbar.Color := RGBToColor(34, 37, 45);

  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Top := 0;
  PnlTop.Height := 32;
  PnlTop.BevelOuter := bvNone;
  PnlTop.Color := RGBToColor(26, 28, 34);
  PnlToolbar.Top := 32;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 12;
  FLblStatus.Top := 8;
  FLblStatus.Font.Color := RGBToColor(225, 232, 245);
  FLblStatus.Font.Style := [fsBold];
  FLblStatus.Caption := 'Non-Destructive Landscape Edit Layers & Terrain-Carving Splines Ready.';

  XPos := 8;
  BtnAlpine := MakeToolbarBtn('+ Alpine Switchback', 158, @BtnSpawnAlpineClick);
  BtnDesert := MakeToolbarBtn('+ Desert Causeway', 146, @BtnSpawnDesertClick);
  BtnMoat := MakeToolbarBtn('+ Citadel Moat', 124, @BtnSpawnMoatClick);
  BtnMuteSplines := MakeToolbarBtn('Mute/Solo Splines', 154, @BtnToggleSplineLayerClick);
  BtnMutePlateau := MakeToolbarBtn('Toggle Plateau', 136, @BtnTogglePlateauLayerClick);
  BtnOp50 := MakeToolbarBtn('Spline Blend 50%', 142, @BtnHalfSplineOpacityClick);
  BtnOp100 := MakeToolbarBtn('Spline Blend 100%', 148, @BtnFullSplineOpacityClick);
  BtnCopy := MakeToolbarBtn('Copy Report', 102, @BtnCopyReportClick);
  BtnClose := MakeToolbarBtn('Close', 68, nil);
  BtnClose.ModalResult := mrOk;
  if (BtnAlpine <> nil) and (BtnDesert <> nil) and (BtnMoat <> nil) and
     (BtnMuteSplines <> nil) and (BtnMutePlateau <> nil) and
     (BtnOp50 <> nil) and (BtnOp100 <> nil) and (BtnCopy <> nil) then ;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 128;
  PnlBottom.BevelOuter := bvNone;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := PnlBottom;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;
  FMemoReport.Font.Name := 'Consolas';
  FMemoReport.Font.Size := 9;
  FMemoReport.Color := RGBToColor(18, 20, 26);
  FMemoReport.Font.Color := RGBToColor(208, 218, 232);

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 576;
  PnlRight.BevelOuter := bvNone;

  FPaintStack := TPaintBox.Create(Self);
  FPaintStack.Parent := PnlRight;
  FPaintStack.Align := alClient;
  FPaintStack.OnPaint := @PaintEditLayerStackAndSplines;

  FPaintMapAndSlice := TPaintBox.Create(Self);
  FPaintMapAndSlice.Parent := Self;
  FPaintMapAndSlice.Align := alClient;
  FPaintMapAndSlice.OnPaint := @PaintSplatmapAndCutFillSlice;
end;

procedure TLandscapeLayersForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh;
  RefreshFromScene;
end;

procedure TLandscapeLayersForm.RefreshFromScene;
var
  M: TLandscapeEarthworkMetrics;
begin
  if FActiveLandscape = nil then
    FActiveLandscape := TLandscapeLayersHelper.FindFirstLandscape(FDesignRoot);

  if FActiveLandscape <> nil then
  begin
    M := FActiveLandscape.Metrics;
    FLblStatus.Caption := Format(
      'Active: %s (%dx%d)  |  Layers: %d/%d  |  Splines: %d  |  Cut: %.0f m^3  |  Fill: %.0f m^3  |  Road: %.0f m^2  |  River: %.0f m^2',
      [FActiveLandscape.LandscapeKey, FActiveLandscape.GridRes, FActiveLandscape.GridRes,
       M.ActiveLayerCount, Length(FActiveLandscape.Layers), M.ActiveSplineCount,
       M.CutExcavatedVolumeM3, M.FillEmbankmentVolumeM3,
       M.RoadPaintedAreaM2, M.RiverPaintedAreaM2]);
  end else
    FLblStatus.Caption := 'No TCastleLandscapeLayerTerrain in scene — click "+ Alpine Switchback" to build layered terrain.';

  FMemoReport.Lines.Text := TLandscapeLayersHelper.GenerateMarkdownReport(
    FDesignRoot, FActiveLandscape);

  FPaintMapAndSlice.Invalidate;
  FPaintStack.Invalidate;
end;

procedure TLandscapeLayersForm.PaintSplatmapAndCutFillSlice(Sender: TObject);
var
  C: TCanvas;
  W, H, SplitY, MapX0, MapY0, MapSizePx, GX, GZ, SIdx, K,
    PX, PY, QX, QY, SliceZRow, ProfX0, ProfW, ProfBaseY: Integer;
  CellPx, HalfS, ElevNorm, Shade, R, G, B, BaseY, FinalY, MinE, MaxE, SpanE: Single;
  Sp: TVector4;
begin
  C := FPaintMapAndSlice.Canvas;
  W := Max(360, FPaintMapAndSlice.Width);
  H := Max(340, FPaintMapAndSlice.Height);
  SplitY := Round(H * 0.62);

  C.Brush.Color := RGBToColor(18, 22, 28);
  C.FillRect(0, 0, W, H);

  { Top Header }
  C.Brush.Color := RGBToColor(28, 36, 44);
  C.FillRect(0, 0, W, 28);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(124, 238, 168);
  C.TextOut(12, 6, 'Top-Down 4-Channel Splatmap + Splines  (Grass | Rock | Cobble | River)');
  C.Font.Style := [];

  { Bottom Header }
  C.Brush.Color := RGBToColor(28, 34, 46);
  C.FillRect(0, SplitY, W, SplitY + 28);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(136, 204, 255);
  C.TextOut(12, SplitY + 6, 'Z = 0 Cross-Section Slice  (Amber = Uncarved Base | Emerald = Cut & Fill Road)');
  C.Font.Style := [];

  if FActiveLandscape = nil then Exit;

  { 1. Render Top-Down 33x33 Height + Splatmap Grid }
  MapSizePx := Min(W - 190, SplitY - 44);
  MapX0 := 22;
  MapY0 := 36;
  CellPx := MapSizePx / Max(1, FActiveLandscape.GridRes);
  MinE := FActiveLandscape.Metrics.MinElevationM;
  MaxE := Max(MinE + 0.5, FActiveLandscape.Metrics.MaxElevationM);
  SpanE := MaxE - MinE;

  for GZ := 0 to FActiveLandscape.GridRes - 1 do
    for GX := 0 to FActiveLandscape.GridRes - 1 do
    begin
      ElevNorm := EnsureRange((FActiveLandscape.SampleHeightAtGrid(GX, GZ) - MinE) / SpanE, 0.0, 1.0);
      Shade := 0.55 + 0.50 * ElevNorm;
      Sp := FActiveLandscape.SampleSplatAtGrid(GX, GZ);

      R := (0.22 * Sp.X + 0.48 * Sp.Y + 0.84 * Sp.Z + 0.18 * Sp.W) * Shade;
      G := (0.56 * Sp.X + 0.47 * Sp.Y + 0.70 * Sp.Z + 0.62 * Sp.W) * Shade;
      B := (0.24 * Sp.X + 0.46 * Sp.Y + 0.36 * Sp.Z + 0.88 * Sp.W) * Shade;

      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(ClampByteCol(R), ClampByteCol(G), ClampByteCol(B));
      C.Pen.Style := psClear;
      C.Rectangle(
        MapX0 + Round(GX * CellPx),
        MapY0 + Round(GZ * CellPx),
        MapX0 + Round((GX + 1) * CellPx) + 1,
        MapY0 + Round((GZ + 1) * CellPx) + 1);
      C.Pen.Style := psSolid;
    end;

  C.Brush.Style := bsClear;
  C.Pen.Color := RGBToColor(86, 102, 128);
  C.Rectangle(MapX0, MapY0, MapX0 + MapSizePx, MapY0 + MapSizePx);

  { Overlay Spline Centerlines & Control Points }
  HalfS := FActiveLandscape.TerrainSizeM * 0.5;
  for SIdx := 0 to High(FActiveLandscape.Splines) do
    if FActiveLandscape.Splines[SIdx].Enabled and
       (Length(FActiveLandscape.Splines[SIdx].ControlPoints) >= 2) then
    begin
      if FActiveLandscape.Splines[SIdx].PaintChannel = lscRiverGravel then
        C.Pen.Color := RGBToColor(96, 232, 255)
      else
        C.Pen.Color := RGBToColor(255, 218, 86);
      C.Pen.Width := 2;
      for K := 0 to High(FActiveLandscape.Splines[SIdx].ControlPoints) - 1 do
      begin
        PX := MapX0 + Round(((FActiveLandscape.Splines[SIdx].ControlPoints[K].X + HalfS) /
          FActiveLandscape.TerrainSizeM) * MapSizePx);
        PY := MapY0 + Round(((FActiveLandscape.Splines[SIdx].ControlPoints[K].Z + HalfS) /
          FActiveLandscape.TerrainSizeM) * MapSizePx);
        QX := MapX0 + Round(((FActiveLandscape.Splines[SIdx].ControlPoints[K + 1].X + HalfS) /
          FActiveLandscape.TerrainSizeM) * MapSizePx);
        QY := MapY0 + Round(((FActiveLandscape.Splines[SIdx].ControlPoints[K + 1].Z + HalfS) /
          FActiveLandscape.TerrainSizeM) * MapSizePx);
        C.MoveTo(PX, PY);
        C.LineTo(QX, QY);
      end;
      C.Pen.Width := 1;

      for K := 0 to High(FActiveLandscape.Splines[SIdx].ControlPoints) do
      begin
        PX := MapX0 + Round(((FActiveLandscape.Splines[SIdx].ControlPoints[K].X + HalfS) /
          FActiveLandscape.TerrainSizeM) * MapSizePx);
        PY := MapY0 + Round(((FActiveLandscape.Splines[SIdx].ControlPoints[K].Z + HalfS) /
          FActiveLandscape.TerrainSizeM) * MapSizePx);
        C.Brush.Style := bsSolid;
        C.Brush.Color := clWhite;
        C.Pen.Color := RGBToColor(30, 34, 44);
        C.Ellipse(PX - 4, PY - 4, PX + 4, PY + 4);
      end;
    end;

  { Top-Down Splat Legend to the right of the square map }
  PX := MapX0 + MapSizePx + 18;
  PY := MapY0 + 8;
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(228, 236, 250);
  C.TextOut(PX, PY, '4-Channel Splat Legend');
  C.Font.Style := [];
  C.Font.Color := RGBToColor(118, 226, 134);
  C.TextOut(PX, PY + 26, '[Ch0] Meadow Grass');
  C.Font.Color := RGBToColor(186, 194, 210);
  C.TextOut(PX, PY + 48, '[Ch1] Auto-Slope Cliff Rock');
  C.Font.Color := RGBToColor(255, 216, 98);
  C.TextOut(PX, PY + 70, '[Ch2] Spline Cobble Road');
  C.Font.Color := RGBToColor(102, 224, 255);
  C.TextOut(PX, PY + 92, '[Ch3] Spline River Gravel');

  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 194, 108);
  C.TextOut(PX, PY + 128, 'Cut / Fill Earthwork');
  C.Font.Style := [];
  C.Font.Color := RGBToColor(255, 138, 146);
  C.TextOut(PX, PY + 152, Format('Excavated Cut: %.0f m^3',
    [FActiveLandscape.Metrics.CutExcavatedVolumeM3]));
  C.Font.Color := RGBToColor(118, 234, 178);
  C.TextOut(PX, PY + 174, Format('Embanked Fill: %.0f m^3',
    [FActiveLandscape.Metrics.FillEmbankmentVolumeM3]));

  { 2. Bottom Z = 0 Cross-Section Slice (Uncarved Base vs. Carved Spline Road) }
  SliceZRow := FActiveLandscape.GridRes div 2;
  ProfX0 := 24;
  ProfW := W - 48;
  ProfBaseY := H - 24;

  { Vertical Cut/Fill Delta Shading Bars }
  for GX := 0 to FActiveLandscape.GridRes - 1 do
  begin
    PX := ProfX0 + Round((GX / Max(1, FActiveLandscape.GridRes - 1)) * ProfW);
    BaseY := FActiveLandscape.SampleBaseBeforeSplinesAtGrid(GX, SliceZRow);
    FinalY := FActiveLandscape.SampleHeightAtGrid(GX, SliceZRow);
    PY := ProfBaseY - Round(((BaseY - MinE + 1.0) / (SpanE + 2.5)) * (H - SplitY - 62));
    QY := ProfBaseY - Round(((FinalY - MinE + 1.0) / (SpanE + 2.5)) * (H - SplitY - 62));
    if Abs(PY - QY) >= 2 then
    begin
      if FinalY < BaseY then
        C.Pen.Color := RGBToColor(186, 68, 78)   { Cut into hillside }
      else
        C.Pen.Color := RGBToColor(58, 142, 188); { Raised embankment fill }
      C.Pen.Width := 4;
      C.MoveTo(PX, PY);
      C.LineTo(PX, QY);
      C.Pen.Width := 1;
    end;
  end;

  { Uncarved Base Curve (Amber) }
  C.Pen.Color := RGBToColor(238, 168, 72);
  C.Pen.Width := 2;
  for GX := 1 to FActiveLandscape.GridRes - 1 do
  begin
    PX := ProfX0 + Round(((GX - 1) / Max(1, FActiveLandscape.GridRes - 1)) * ProfW);
    QX := ProfX0 + Round((GX / Max(1, FActiveLandscape.GridRes - 1)) * ProfW);
    BaseY := FActiveLandscape.SampleBaseBeforeSplinesAtGrid(GX - 1, SliceZRow);
    FinalY := FActiveLandscape.SampleBaseBeforeSplinesAtGrid(GX, SliceZRow);
    PY := ProfBaseY - Round(((BaseY - MinE + 1.0) / (SpanE + 2.5)) * (H - SplitY - 62));
    QY := ProfBaseY - Round(((FinalY - MinE + 1.0) / (SpanE + 2.5)) * (H - SplitY - 62));
    C.MoveTo(PX, PY);
    C.LineTo(QX, QY);
  end;

  { Final Composite Curve with Carved Road Bench & Embankments (Bright Emerald) }
  C.Pen.Color := RGBToColor(96, 248, 162);
  C.Pen.Width := 3;
  for GX := 1 to FActiveLandscape.GridRes - 1 do
  begin
    PX := ProfX0 + Round(((GX - 1) / Max(1, FActiveLandscape.GridRes - 1)) * ProfW);
    QX := ProfX0 + Round((GX / Max(1, FActiveLandscape.GridRes - 1)) * ProfW);
    BaseY := FActiveLandscape.SampleHeightAtGrid(GX - 1, SliceZRow);
    FinalY := FActiveLandscape.SampleHeightAtGrid(GX, SliceZRow);
    PY := ProfBaseY - Round(((BaseY - MinE + 1.0) / (SpanE + 2.5)) * (H - SplitY - 62));
    QY := ProfBaseY - Round(((FinalY - MinE + 1.0) / (SpanE + 2.5)) * (H - SplitY - 62));
    C.MoveTo(PX, PY);
    C.LineTo(QX, QY);
  end;
  C.Pen.Width := 1;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(196, 212, 234);
  C.TextOut(24, H - 20,
    'Red Bars = Hillside Excavation Cut  |  Blue Bars = Valley Causeway Embankment Fill  |  0.0m Drift on Mute!');
  C.Brush.Style := bsSolid;
end;

procedure TLandscapeLayersForm.PaintEditLayerStackAndSplines(Sender: TObject);
var
  C: TCanvas;
  W, H, I, CardIdx, CardY, BarW, FillW, SplineTopY, RowY: Integer;
  ModeStr, DefStr: String;
begin
  C := FPaintStack.Canvas;
  W := Max(360, FPaintStack.Width);
  H := Max(340, FPaintStack.Height);

  C.Brush.Color := RGBToColor(24, 26, 33);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 214, 112);
  C.TextOut(12, 7, 'Non-Destructive Landscape Edit Layers  (Top-to-Bottom Stack)');
  C.Font.Style := [];

  if FActiveLandscape = nil then Exit;

  CardIdx := 0;
  for I := High(FActiveLandscape.Layers) downto 0 do
  begin
    CardY := 40 + CardIdx * 66;
    Inc(CardIdx);

    C.Brush.Style := bsSolid;
    if FActiveLandscape.Layers[I].ReservedForSplines then
    begin
      C.Brush.Color := RGBToColor(36, 54, 78);
      C.Pen.Color := RGBToColor(102, 184, 255);
    end else
    begin
      C.Brush.Color := RGBToColor(30, 34, 45);
      C.Pen.Color := RGBToColor(72, 84, 108);
    end;
    C.RoundRect(12, CardY, W - 12, CardY + 56, 8, 8);

    { Visibility Badge }
    if FActiveLandscape.Layers[I].Visible then
    begin
      C.Brush.Color := RGBToColor(42, 132, 82);
      C.Pen.Color := RGBToColor(112, 232, 158);
    end else
    begin
      C.Brush.Color := RGBToColor(92, 42, 48);
      C.Pen.Color := RGBToColor(218, 102, 112);
    end;
    C.RoundRect(22, CardY + 10, 74, CardY + 30, 6, 6);
    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := clWhite;
    if FActiveLandscape.Layers[I].Visible then
      C.TextOut(33, CardY + 13, 'LIVE')
    else
      C.TextOut(28, CardY + 13, 'MUTED');

    { Layer Title + Blend Mode }
    case FActiveLandscape.Layers[I].BlendMode of
      llbmAdditive:     ModeStr := 'Additive';
      llbmAlphaBlend:   ModeStr := 'AlphaBlend';
      llbmMinCarveOnly: ModeStr := 'MinCarve';
      llbmMaxRaiseOnly: ModeStr := 'MaxRaise';
    end;
    C.Font.Color := RGBToColor(238, 244, 255);
    C.TextOut(86, CardY + 9, FActiveLandscape.Layers[I].LayerName + '  [' + ModeStr + ']');
    C.Font.Style := [];

    if FActiveLandscape.Layers[I].ReservedForSplines then
    begin
      C.Font.Color := RGBToColor(255, 216, 108);
      C.TextOut(W - 186, CardY + 9, '[Reserved for Splines]');
    end;

    { Opacity Bar }
    BarW := W - 212;
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(18, 20, 26);
    C.Pen.Color := RGBToColor(62, 72, 90);
    C.Rectangle(86, CardY + 33, 86 + BarW, CardY + 47);

    FillW := Round(EnsureRange(FActiveLandscape.Layers[I].Opacity, 0.0, 1.0) * (BarW - 2));
    if FillW > 0 then
    begin
      C.Brush.Color := RGBToColor(78, 168, 246);
      C.Pen.Style := psClear;
      C.Rectangle(87, CardY + 34, 87 + FillW, CardY + 47);
      C.Pen.Style := psSolid;
    end;
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(198, 212, 232);
    C.TextOut(94 + BarW, CardY + 32, Format('Opacity %.0f%%',
      [FActiveLandscape.Layers[I].Opacity * 100.0]));
  end;

  { Landscape Splines Table }
  SplineTopY := 252;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, SplineTopY, W, SplineTopY + 30);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(126, 232, 186);
  C.TextOut(12, SplineTopY + 7, 'ULandscapeSplinesComponent  (Corridor Width, Falloff & Splat)');
  C.Font.Style := [];

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(29, 33, 43);
  C.FillRect(12, SplineTopY + 38, W - 12, SplineTopY + 62);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(174, 190, 216);
  C.TextOut(20, SplineTopY + 43, 'Spline Name');
  C.TextOut(228, SplineTopY + 43, 'HalfW / Falloff');
  C.TextOut(360, SplineTopY + 43, 'Deform Mode');
  C.TextOut(494, SplineTopY + 43, 'Pts');
  C.Font.Style := [];

  for I := 0 to High(FActiveLandscape.Splines) do
  begin
    RowY := SplineTopY + 64 + I * 36;
    C.Brush.Style := bsSolid;
    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(27, 30, 39)
    else
      C.Brush.Color := RGBToColor(23, 26, 34);
    C.FillRect(12, RowY, W - 12, RowY + 35);

    case FActiveLandscape.Splines[I].DeformMode of
      lsdmBothRaiseAndLower: DefStr := 'Cut + Fill';
      lsdmLowerOnlyTrench:   DefStr := 'Lower Trench';
      lsdmRaiseOnlyCauseway: DefStr := 'Raise Causeway';
    end;

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    if FActiveLandscape.Splines[I].PaintChannel = lscRiverGravel then
      C.Font.Color := RGBToColor(106, 226, 255)
    else
      C.Font.Color := RGBToColor(255, 218, 106);
    C.TextOut(20, RowY + 9, FActiveLandscape.Splines[I].SplineName);
    C.Font.Style := [];

    C.Font.Color := RGBToColor(214, 224, 240);
    C.TextOut(228, RowY + 9, Format('%.1fm / %.1fm',
      [FActiveLandscape.Splines[I].HalfWidthM, FActiveLandscape.Splines[I].SideFalloffM]));

    C.Font.Color := RGBToColor(138, 234, 178);
    C.TextOut(360, RowY + 9, DefStr);

    C.Font.Color := RGBToColor(198, 210, 232);
    C.TextOut(494, RowY + 9, IntToStr(Length(FActiveLandscape.Splines[I].ControlPoints)));
  end;
  C.Brush.Style := bsSolid;
end;

procedure TLandscapeLayersForm.BtnSpawnAlpineClick(Sender: TObject);
begin
  FActiveLandscape := TLandscapeLayersHelper.SpawnLandscapePresetInDesign(
    FDesignRoot, FDesignOwner, llpAlpinePassSwitchbackRoadAndRiver, Vector3(0, 0, 0));
  NotifyChanged('Spawn Alpine Switchback Landscape Edit Layers + Splines');
end;

procedure TLandscapeLayersForm.BtnSpawnDesertClick(Sender: TObject);
begin
  FActiveLandscape := TLandscapeLayersHelper.SpawnLandscapePresetInDesign(
    FDesignRoot, FDesignOwner, llpDesertCanyonHighwayCauseway, Vector3(72, 0, 0));
  NotifyChanged('Spawn Desert Canyon Causeway Landscape');
end;

procedure TLandscapeLayersForm.BtnSpawnMoatClick(Sender: TObject);
begin
  FActiveLandscape := TLandscapeLayersHelper.SpawnLandscapePresetInDesign(
    FDesignRoot, FDesignOwner, llpMedievalMoatAndCastleApproach, Vector3(-72, 0, 0));
  NotifyChanged('Spawn Citadel Moat & Causeway Landscape');
end;

procedure TLandscapeLayersForm.BtnToggleSplineLayerClick(Sender: TObject);
var
  Idx: Integer;
begin
  if FActiveLandscape = nil then Exit;
  Idx := FActiveLandscape.FindLayerIndex('02_LandscapeSplines');
  if Idx >= 0 then
  begin
    FActiveLandscape.SetLayerVisible('02_LandscapeSplines',
      not FActiveLandscape.Layers[Idx].Visible);
    NotifyChanged('Toggle Non-Destructive Landscape Splines Edit Layer');
  end;
end;

procedure TLandscapeLayersForm.BtnTogglePlateauLayerClick(Sender: TObject);
var
  Idx: Integer;
begin
  if FActiveLandscape = nil then Exit;
  Idx := FActiveLandscape.FindLayerIndex('01_SculptedPlateaus');
  if Idx >= 0 then
  begin
    FActiveLandscape.SetLayerVisible('01_SculptedPlateaus',
      not FActiveLandscape.Layers[Idx].Visible);
    NotifyChanged('Toggle Non-Destructive Sculpted Plateaus Edit Layer');
  end;
end;

procedure TLandscapeLayersForm.BtnHalfSplineOpacityClick(Sender: TObject);
begin
  if FActiveLandscape = nil then Exit;
  FActiveLandscape.SetLayerOpacity('02_LandscapeSplines', 0.50);
  NotifyChanged('Set Landscape Splines Edit Layer Opacity = 50%');
end;

procedure TLandscapeLayersForm.BtnFullSplineOpacityClick(Sender: TObject);
begin
  if FActiveLandscape = nil then Exit;
  FActiveLandscape.SetLayerOpacity('02_LandscapeSplines', 1.00);
  NotifyChanged('Set Landscape Splines Edit Layer Opacity = 100%');
end;

procedure TLandscapeLayersForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
  FLblStatus.Caption := 'Copied Landscape Edit Layers & Splines Report to Clipboard.';
end;

end.
