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

{ Unreal Engine 5.5-style Static Lightmap & Ambient Occlusion Atlas Baker
  Studio featuring a 3D Baked Cornell Radiosity Room Viewport (Direct Sun
  Shadow + Red/Blue Diffuse Color Bleeding + Contact AO + UE Red Unbuilt
  Lighting Banner) and a Gutter-Dilated UV2 Lightmap Atlas Inspector
  (Phase 399 — 119 UE Studios / 42 MCP). }
unit FormLightmassBaker;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleLightmassBaker, ToolLightmassBaker;

type
  TLightmassModifiedCallback = procedure(const UndoComment: String) of object;
  TLightmassRefreshCallback = procedure of object;

  TLightmassBakerForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TLightmassModifiedCallback;
    FOnRefresh: TLightmassRefreshCallback;

    FActiveBaker: TCastleLightmassBaker;

    FLblStatus: TLabel;
    FPaintRoom3D: TPaintBox;
    FPaintAtlas2D: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintBakedRoomViewport(Sender: TObject);
    procedure PaintUv2LightmapAtlas(Sender: TObject);

    procedure BtnSpawnCornellClick(Sender: TObject);
    procedure BtnSpawnCloisterClick(Sender: TObject);
    procedure BtnBakeLightmapsClick(Sender: TObject);
    procedure BtnToggleBouncesClick(Sender: TObject);
    procedure BtnCycleChannelClick(Sender: TObject);
    procedure BtnMarkUnbuiltClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TLightmassModifiedCallback;
      const AOnRefresh: TLightmassRefreshCallback);
  end;

implementation

constructor TLightmassBakerForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TLightmassModifiedCallback;
  const AOnRefresh: TLightmassRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Static Lightmap & Ambient Occlusion Atlas Baker Studio (GPU Lightmass — 119 UE Studios / 42 MCP)';
  Position := poScreenCenter;
  Width := 1340;
  Height := 760;

  BuildUi;
  FActiveBaker := TLightmassBakerHelper.FindFirstLightmassBaker(FDesignRoot);
  RefreshFromScene;
end;

procedure TLightmassBakerForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlBottom, PnlRight: TPanel;
  BtnCornell, BtnCloister, BtnBake, BtnBounce, BtnChan, BtnUnbuilt, BtnCopy, BtnClose: TButton;
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
  FLblStatus.Caption := 'GPU Lightmass Static Lightmap & AO Baker Ready.';

  XPos := 8;
  BtnCornell := MakeToolbarBtn('+ Cornell GI Room', 148, @BtnSpawnCornellClick);
  BtnCloister := MakeToolbarBtn('+ Sunbeam Cloister', 152, @BtnSpawnCloisterClick);
  BtnBake := MakeToolbarBtn('Bake GPU Lightmass', 158, @BtnBakeLightmapsClick);
  BtnBounce := MakeToolbarBtn('Toggle 0 / 2 Bounces', 162, @BtnToggleBouncesClick);
  BtnChan := MakeToolbarBtn('Cycle View (Lit/GI/AO/UV2)', 194, @BtnCycleChannelClick);
  BtnUnbuilt := MakeToolbarBtn('Mark Unbuilt', 116, @BtnMarkUnbuiltClick);
  BtnCopy := MakeToolbarBtn('Copy Report', 104, @BtnCopyReportClick);
  BtnClose := MakeToolbarBtn('Close', 68, nil);
  BtnClose.ModalResult := mrOk;
  if (BtnCornell <> nil) and (BtnCloister <> nil) and (BtnBake <> nil) and
     (BtnBounce <> nil) and (BtnChan <> nil) and (BtnUnbuilt <> nil) and
     (BtnCopy <> nil) then ;

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
  PnlRight.Width := 590;
  PnlRight.BevelOuter := bvNone;

  FPaintAtlas2D := TPaintBox.Create(Self);
  FPaintAtlas2D.Parent := PnlRight;
  FPaintAtlas2D.Align := alClient;
  FPaintAtlas2D.OnPaint := @PaintUv2LightmapAtlas;

  FPaintRoom3D := TPaintBox.Create(Self);
  FPaintRoom3D.Parent := Self;
  FPaintRoom3D.Align := alClient;
  FPaintRoom3D.OnPaint := @PaintBakedRoomViewport;
end;

procedure TLightmassBakerForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh;
  RefreshFromScene;
end;

procedure TLightmassBakerForm.RefreshFromScene;
begin
  if FActiveBaker = nil then
    FActiveBaker := TLightmassBakerHelper.FindFirstLightmassBaker(FDesignRoot);

  if FActiveBaker <> nil then
    FLblStatus.Caption := Format(
      'Baker: %s  |  Atlas: %dx%d (%d Interior + %d Dilated)  |  Bounces: %d  |  Avg AO: %.1f%%  |  Avg GI: %.3f  |  View: %s',
      [FActiveBaker.Name,
       FActiveBaker.AtlasResolution, FActiveBaker.AtlasResolution,
       FActiveBaker.ValidInteriorTexelCount,
       FActiveBaker.DilatedBorderTexelCount,
       FActiveBaker.IndirectBounces,
       FActiveBaker.AverageSkyAo01 * 100.0,
       FActiveBaker.AverageIndirectLuminance,
       LightmassViewChannelDisplayName(FActiveBaker.ViewChannel)])
  else
    FLblStatus.Caption := 'No TCastleLightmassBaker in scene — click "+ Cornell GI Room" to bake UV2 radiosity & AO.';

  FMemoReport.Lines.Text := TLightmassBakerHelper.GenerateMarkdownReport(
    FDesignRoot, FActiveBaker);

  FPaintRoom3D.Invalidate;
  FPaintAtlas2D.Invalidate;
end;

procedure TLightmassBakerForm.PaintBakedRoomViewport(Sender: TObject);
const
  DrawOrder: array[0..5] of Integer = (3, 1, 2, 0, 4, 5);
var
  C: TCanvas;
  W, H, OrderIdx, CIdx, LX, LY: Integer;
  ScalePx: Single;
  Ch: TLightmassSurfaceChart;
  P0, P1, P2, P3: TVector3;
  QuadPts: array[0..3] of TPoint;
  DispCol: TVector3;

  function Project3D(const V: TVector3): TPoint;
  var
    Persp, DepthZ: Single;
  begin
    { Perspective Cornell Box camera at (0, 2.2, 8.2) looking toward -Z }
    DepthZ := Max(2.5, 8.2 - V.Z);
    Persp := 5.8 / DepthZ;
    Result.X := (W div 2) + Round(V.X * Persp * ScalePx);
    Result.Y := (H div 2 + 24) - Round((V.Y - 1.95) * Persp * ScalePx);
  end;

begin
  C := FPaintRoom3D.Canvas;
  W := Max(360, FPaintRoom3D.Width);
  H := Max(320, FPaintRoom3D.Height);

  C.Brush.Color := RGBToColor(16, 19, 25);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(28, 34, 46);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(126, 206, 255);
  C.TextOut(12, 7, '3D Baked Radiosity & Contact AO Viewport  (Cornell Box Perspective)');
  C.Font.Style := [];

  if FActiveBaker = nil then Exit;

  ScalePx := Min((W - 96) / 6.6, (H - 110) / 5.0);

  { Render all 6 baked UV2 charts in 3D perspective painter order:
    BackWall(3), LeftWall(1), RightWall(2), Floor(0), OccluderTop(4), OccluderFront(5) }
  C.Pen.Style := psClear;
  for OrderIdx := 0 to 5 do
  begin
    CIdx := DrawOrder[OrderIdx];
    if CIdx >= FActiveBaker.ChartCount then Continue;
    Ch := FActiveBaker.Charts[CIdx];
    for LY := 0 to Ch.AtlasH - 1 do
      for LX := 0 to Ch.AtlasW - 1 do
      begin
        P0 := Ch.PatchOrigin + Ch.AxisU * (LX / Ch.AtlasW) + Ch.AxisV * (LY / Ch.AtlasH);
        P1 := Ch.PatchOrigin + Ch.AxisU * ((LX + 1) / Ch.AtlasW) + Ch.AxisV * (LY / Ch.AtlasH);
        P2 := Ch.PatchOrigin + Ch.AxisU * ((LX + 1) / Ch.AtlasW) + Ch.AxisV * ((LY + 1) / Ch.AtlasH);
        P3 := Ch.PatchOrigin + Ch.AxisU * (LX / Ch.AtlasW) + Ch.AxisV * ((LY + 1) / Ch.AtlasH);

        QuadPts[0] := Project3D(P0);
        QuadPts[1] := Project3D(P1);
        QuadPts[2] := Project3D(P2);
        QuadPts[3] := Project3D(P3);

        DispCol := FActiveBaker.EvaluateAtlasDisplayRGB(Ch.AtlasX + LX, Ch.AtlasY + LY);
        C.Brush.Style := bsSolid;
        C.Brush.Color := RGBToColor(
          EnsureRange(Round(Power(EnsureRange(DispCol.X, 0.0, 1.0), 0.82) * 255), 0, 255),
          EnsureRange(Round(Power(EnsureRange(DispCol.Y, 0.0, 1.0), 0.82) * 255), 0, 255),
          EnsureRange(Round(Power(EnsureRange(DispCol.Z, 0.0, 1.0), 0.82) * 255), 0, 255));
        C.Polygon(QuadPts);
      end;
  end;
  C.Pen.Style := psSolid;

  { Classic UE Red Unbuilt Lighting Warning HUD when invalidated! }
  if FActiveBaker.LightingNeedsRebuild then
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(148, 28, 34);
    C.FillRect(16, 40, 412, 68);
    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(255, 228, 228);
    C.TextOut(26, 46, 'LIGHTING NEEDS TO BE REBUILT (1 unbuilt volume)');
    C.Font.Style := [];
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(188, 206, 232);
  C.TextOut(14, H - 24,
    'Red Left Wall & Blue Right Wall bleed diffuse GI onto white floor; Center Block casts shadow & AO.');
  C.Brush.Style := bsSolid;
end;

procedure TLightmassBakerForm.PaintUv2LightmapAtlas(Sender: TObject);
var
  C: TCanvas;
  W, H, Res, CellPx, OffX, OffY, X, Y, I, RowY: Integer;
  Col: TVector3;
  Ch: TLightmassSurfaceChart;
  Tex: TLightmassTexel;
begin
  C := FPaintAtlas2D.Canvas;
  W := Max(360, FPaintAtlas2D.Width);
  H := Max(320, FPaintAtlas2D.Height);

  C.Brush.Color := RGBToColor(24, 26, 33);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 214, 112);
  C.TextOut(12, 7, 'Packed UV2 Lightmap & AO Atlas (2px Dilated Seam Gutters)');
  C.Font.Style := [];

  if FActiveBaker = nil then Exit;

  Res := FActiveBaker.AtlasResolution;
  CellPx := Max(4, Min((W - 48) div Res, 290 div Res));
  OffX := 20;
  OffY := 42;

  for Y := 0 to Res - 1 do
    for X := 0 to Res - 1 do
    begin
      Col := FActiveBaker.EvaluateAtlasDisplayRGB(X, Y);
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(
        EnsureRange(Round(Power(EnsureRange(Col.X, 0.0, 1.0), 0.85) * 255), 0, 255),
        EnsureRange(Round(Power(EnsureRange(Col.Y, 0.0, 1.0), 0.85) * 255), 0, 255),
        EnsureRange(Round(Power(EnsureRange(Col.Z, 0.0, 1.0), 0.85) * 255), 0, 255));
      C.FillRect(
        OffX + X * CellPx,
        OffY + (Res - 1 - Y) * CellPx,
        OffX + (X + 1) * CellPx,
        OffY + (Res - Y) * CellPx);
    end;

  { Outline interior chart borders in crisp cyan so 2px dilated ring outside is visible! }
  C.Brush.Style := bsClear;
  C.Pen.Color := RGBToColor(112, 214, 255);
  for I := 0 to FActiveBaker.ChartCount - 1 do
  begin
    Ch := FActiveBaker.Charts[I];
    C.Rectangle(
      OffX + Ch.AtlasX * CellPx,
      OffY + (Res - (Ch.AtlasY + Ch.AtlasH)) * CellPx,
      OffX + (Ch.AtlasX + Ch.AtlasW) * CellPx,
      OffY + (Res - Ch.AtlasY) * CellPx);
  end;

  { Right-side Atlas Legend }
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(206, 224, 248);
  C.TextOut(OffX + Res * CellPx + 18, OffY + 8, 'UV2 Atlas Metrics');
  C.Font.Style := [];
  C.Font.Color := RGBToColor(168, 188, 216);
  C.TextOut(OffX + Res * CellPx + 18, OffY + 32,
    Format('Resolution: %dx%d', [Res, Res]));
  C.TextOut(OffX + Res * CellPx + 18, OffY + 52,
    Format('Charts: %d (Zero Overlap)', [FActiveBaker.ChartCount]));
  C.TextOut(OffX + Res * CellPx + 18, OffY + 72,
    Format('Interior: %d texels', [FActiveBaker.ValidInteriorTexelCount]));
  C.TextOut(OffX + Res * CellPx + 18, OffY + 92,
    Format('Dilated: %d texels', [FActiveBaker.DilatedBorderTexelCount]));
  C.TextOut(OffX + Res * CellPx + 18, OffY + 112,
    Format('Raw Seam Leaks: %d', [FActiveBaker.UndilatedAdjacentGutterCount]));
  C.TextOut(OffX + Res * CellPx + 18, OffY + 132,
    Format('Rays/Texel: %d',
      [TCastleLightmassBaker.RaysPerTexelForQuality(FActiveBaker.QualityTier)]));

  { Bottom Per-Chart Radiosity Table }
  RowY := OffY + Res * CellPx + 14;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(29, 33, 43);
  C.FillRect(12, RowY, W - 12, RowY + 24);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(172, 188, 214);
  C.TextOut(20, RowY + 4, 'UV2 Chart');
  C.TextOut(224, RowY + 4, 'Tile (X,Y,W,H)');
  C.TextOut(356, RowY + 4, 'Indirect GI');
  C.TextOut(492, RowY + 4, 'Sky AO');
  C.Font.Style := [];

  for I := 0 to FActiveBaker.ChartCount - 1 do
  begin
    Ch := FActiveBaker.Charts[I];
    Tex := FActiveBaker.SampleChartTexelNearUV(I, 0.5, 0.5);
    RowY := (OffY + Res * CellPx + 40) + I * 26;
    if RowY + 24 > H - 6 then Break;

    C.Brush.Style := bsSolid;
    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(27, 30, 39)
    else
      C.Brush.Color := RGBToColor(23, 26, 34);
    C.FillRect(12, RowY, W - 12, RowY + 24);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(142, 224, 255);
    C.TextOut(20, RowY + 4, Ch.ChartName);
    C.Font.Color := RGBToColor(196, 210, 232);
    C.TextOut(224, RowY + 4, Format('(%d,%d %dx%d)',
      [Ch.AtlasX, Ch.AtlasY, Ch.AtlasW, Ch.AtlasH]));
    C.TextOut(356, RowY + 4, Format('(%.2f, %.2f, %.2f)',
      [Tex.IndirectRGB.X, Tex.IndirectRGB.Y, Tex.IndirectRGB.Z]));
    C.TextOut(492, RowY + 4, Format('%.0f%%', [Tex.SkyAo01 * 100.0]));
  end;
  C.Brush.Style := bsSolid;
end;

procedure TLightmassBakerForm.BtnSpawnCornellClick(Sender: TObject);
begin
  FActiveBaker := TLightmassBakerHelper.SpawnLightmassPresetInDesign(
    FDesignRoot, FDesignOwner, lbpCornellColorBleedRoom, Vector3(0, 0, 0));
  NotifyChanged('Spawn Cornell Color-Bleed GPU Lightmass Baker');
end;

procedure TLightmassBakerForm.BtnSpawnCloisterClick(Sender: TObject);
begin
  FActiveBaker := TLightmassBakerHelper.SpawnLightmassPresetInDesign(
    FDesignRoot, FDesignOwner, lbpArchwaySunbeamCloister, Vector3(8, 0, 0));
  NotifyChanged('Spawn Sunbeam Cloister GPU Lightmass Baker');
end;

procedure TLightmassBakerForm.BtnBakeLightmapsClick(Sender: TObject);
begin
  if FActiveBaker = nil then Exit;
  FActiveBaker.BakeStaticLightmaps;
  NotifyChanged('Bake Static UV2 Lightmaps & Sky AO');
end;

procedure TLightmassBakerForm.BtnToggleBouncesClick(Sender: TObject);
begin
  if FActiveBaker = nil then Exit;
  if FActiveBaker.IndirectBounces > 0 then
    FActiveBaker.IndirectBounces := 0
  else
    FActiveBaker.IndirectBounces := 2;
  FActiveBaker.BakeStaticLightmaps;
  NotifyChanged(Format('Bake GPU Lightmass (%d Bounces)', [FActiveBaker.IndirectBounces]));
end;

procedure TLightmassBakerForm.BtnCycleChannelClick(Sender: TObject);
begin
  if FActiveBaker = nil then Exit;
  if FActiveBaker.ViewChannel = High(TLightmassViewChannel) then
    FActiveBaker.ViewChannel := Low(TLightmassViewChannel)
  else
    FActiveBaker.ViewChannel := Succ(FActiveBaker.ViewChannel);
  RefreshFromScene;
end;

procedure TLightmassBakerForm.BtnMarkUnbuiltClick(Sender: TObject);
begin
  if FActiveBaker = nil then Exit;
  FActiveBaker.InvalidateLighting;
  RefreshFromScene;
end;

procedure TLightmassBakerForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
  FLblStatus.Caption := 'Copied GPU Lightmass Static Lightmap Report to Clipboard.';
end;

end.
