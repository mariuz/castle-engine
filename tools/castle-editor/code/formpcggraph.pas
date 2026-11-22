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

{ Unreal Engine 5.5-style PCG Visual Node Graph Editor dialog featuring an
  interactive directed point-cloud node graph canvas, per-node [N pts] badges,
  a live top-down XZ Point-Cloud & Bounds Inspector (I-key equivalent), seed
  cycling, and Markdown diagnostics (Phase 382 — 102 UE Studios / 25 MCP). }
unit FormPcgGraph;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastlePcgGraph, ToolPcgGraph;

type
  TPcgGraphModifiedCallback = procedure(const UndoComment: String) of object;
  TPcgGraphRefreshCallback = procedure of object;

  TPcgGraphForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TPcgGraphModifiedCallback;
    FOnRefresh: TPcgGraphRefreshCallback;

    FActiveGraph: TCastlePcgGraph;
    FInspectedNodeId: String;
    FDraggingNode: Boolean;
    FDragOffsetX: Single;
    FDragOffsetY: Single;
    FInspectedPoints: TPcgPointArray;

    FLblStatus: TLabel;
    FPaintGraph: TPaintBox;
    FPaintPointCloud: TPaintBox;
    FMemoTelemetry: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);
    function HeaderColor(const AKind: TPcgNodeKind): TColor;
    procedure DrawCubicWire(const C: TCanvas; const P0, P1: TPoint;
      const ACol: TColor; const AWidth: Integer);

    procedure PaintGraphCanvas(Sender: TObject);
    procedure PaintPointCloudInspector(Sender: TObject);
    procedure GraphMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure GraphMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GraphMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure BtnSpawnForestRoadClick(Sender: TObject);
    procedure BtnSpawnRockUnionClick(Sender: TObject);
    procedure BtnSpawnSplinePostsClick(Sender: TObject);
    procedure BtnExecuteClick(Sender: TObject);
    procedure BtnReseedClick(Sender: TObject);
    procedure BtnCycleInspectClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TPcgGraphModifiedCallback;
      const AOnRefresh: TPcgGraphRefreshCallback);
  end;

implementation

const
  PcgNodeW = 162;
  PcgNodeH = 68;

constructor TPcgGraphForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TPcgGraphModifiedCallback;
  const AOnRefresh: TPcgGraphRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'PCG Visual Node Graph Editor — Point-Cloud DAG & Inspector (102 UE Studios / 25 MCP)';
  Position := poScreenCenter;
  Width := 1120;
  Height := 690;

  BuildUi;
  FActiveGraph := TPcgGraphHelper.FindFirstPcgGraph(FDesignRoot);
  RefreshFromScene;
end;

procedure TPcgGraphForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlRight, PnlBottom: TPanel;
  LblCloud: TLabel;
  BtnForest, BtnRock, BtnPosts, BtnExec, BtnSeed, BtnInsp, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 34;
  PnlTop.BevelOuter := bvNone;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 10;
  FLblStatus.Top := 9;
  FLblStatus.Caption := 'PCG Visual Node Graph Editor Ready.';

  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;

  BtnForest := TButton.Create(Self);
  BtnForest.Parent := PnlToolbar;
  BtnForest.SetBounds(8, 6, 158, 30);
  BtnForest.Caption := '+ Forest - Road Diff';
  BtnForest.OnClick := @BtnSpawnForestRoadClick;

  BtnRock := TButton.Create(Self);
  BtnRock.Parent := PnlToolbar;
  BtnRock.SetBounds(170, 6, 146, 30);
  BtnRock.Caption := '+ Rock/Shrub Union';
  BtnRock.OnClick := @BtnSpawnRockUnionClick;

  BtnPosts := TButton.Create(Self);
  BtnPosts.Parent := PnlToolbar;
  BtnPosts.SetBounds(320, 6, 134, 30);
  BtnPosts.Caption := '+ Spline Posts';
  BtnPosts.OnClick := @BtnSpawnSplinePostsClick;

  BtnExec := TButton.Create(Self);
  BtnExec.Parent := PnlToolbar;
  BtnExec.SetBounds(460, 6, 118, 30);
  BtnExec.Caption := 'Execute Graph';
  BtnExec.OnClick := @BtnExecuteClick;

  BtnSeed := TButton.Create(Self);
  BtnSeed.Parent := PnlToolbar;
  BtnSeed.SetBounds(582, 6, 114, 30);
  BtnSeed.Caption := 'Re-Seed (+1)';
  BtnSeed.OnClick := @BtnReseedClick;

  BtnInsp := TButton.Create(Self);
  BtnInsp.Parent := PnlToolbar;
  BtnInsp.SetBounds(700, 6, 146, 30);
  BtnInsp.Caption := 'Next Inspect (I)';
  BtnInsp.OnClick := @BtnCycleInspectClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlToolbar;
  BtnCopy.SetBounds(850, 6, 128, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 155;
  PnlBottom.BevelOuter := bvNone;

  FMemoTelemetry := TMemo.Create(Self);
  FMemoTelemetry.Parent := PnlBottom;
  FMemoTelemetry.Align := alClient;
  FMemoTelemetry.ScrollBars := ssVertical;
  FMemoTelemetry.ReadOnly := True;
  FMemoTelemetry.Font.Name := 'Monospace';

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.Align := alRight;
  BtnClose.Width := 74;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 320;
  PnlRight.BevelOuter := bvLowered;

  LblCloud := TLabel.Create(Self);
  LblCloud.Parent := PnlRight;
  LblCloud.Align := alTop;
  LblCloud.Caption := '  XZ Point-Cloud & Bounds Inspector';

  FPaintPointCloud := TPaintBox.Create(Self);
  FPaintPointCloud.Parent := PnlRight;
  FPaintPointCloud.Align := alClient;
  FPaintPointCloud.OnPaint := @PaintPointCloudInspector;

  FPaintGraph := TPaintBox.Create(Self);
  FPaintGraph.Parent := Self;
  FPaintGraph.Align := alClient;
  FPaintGraph.OnPaint := @PaintGraphCanvas;
  FPaintGraph.OnMouseDown := @GraphMouseDown;
  FPaintGraph.OnMouseMove := @GraphMouseMove;
  FPaintGraph.OnMouseUp := @GraphMouseUp;
end;

procedure TPcgGraphForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TPcgGraphForm.RefreshFromScene;
begin
  if (FActiveGraph = nil) and (FDesignRoot <> nil) then
    FActiveGraph := TPcgGraphHelper.FindFirstPcgGraph(FDesignRoot);

  FInspectedPoints := nil;
  if FActiveGraph <> nil then
  begin
    if (FInspectedNodeId = '') or (FActiveGraph.FindNodeIndex(FInspectedNodeId) < 0) then
      if Length(FActiveGraph.Nodes) > 0 then
        FInspectedNodeId := FActiveGraph.Nodes[High(FActiveGraph.Nodes)].NodeId;

    if FInspectedNodeId <> '' then
      FActiveGraph.EvaluateNodeOutput(FInspectedNodeId, FInspectedPoints);

    FLblStatus.Caption := Format('%s  %s  |  Inspecting Node: "%s" (%d pts)',
      [FActiveGraph.Name, FActiveGraph.PcgSummaryBadge,
       FInspectedNodeId, Length(FInspectedPoints)]);
  end else
    FLblStatus.Caption := 'No TCastlePcgGraph in design yet — click "+ Forest - Road Diff" to spawn.';

  FMemoTelemetry.Text := TPcgGraphHelper.GenerateMarkdownReport(FDesignRoot, FActiveGraph);
  FPaintGraph.Invalidate;
  FPaintPointCloud.Invalidate;
end;

function TPcgGraphForm.HeaderColor(const AKind: TPcgNodeKind): TColor;
begin
  case AKind of
    pnkSurfaceSampler, pnkSplineSampler:
      Result := RGBToColor(34, 126, 68);
    pnkDensityNoise, pnkBoundsModifier, pnkTransformPoints:
      Result := RGBToColor(28, 114, 126);
    pnkDensityFilter, pnkNormalSlopeFilter:
      Result := RGBToColor(168, 112, 28);
    pnkDifference, pnkUnion, pnkSelfPruning:
      Result := RGBToColor(118, 52, 152);
  else
    Result := RGBToColor(38, 88, 162);
  end;
end;

procedure TPcgGraphForm.DrawCubicWire(const C: TCanvas;
  const P0, P1: TPoint; const ACol: TColor; const AWidth: Integer);
var
  Pts: array[0..16] of TPoint;
  TangentDX, T, OneMinusT, C1X, C2X: Single;
  S: Integer;
begin
  TangentDX := Max(42.0, Abs(P1.X - P0.X) * 0.45);
  C1X := P0.X + TangentDX;
  C2X := P1.X - TangentDX;
  for S := 0 to 16 do
  begin
    T := S / 16.0;
    OneMinusT := 1.0 - T;
    Pts[S].X := Round(
      OneMinusT * OneMinusT * OneMinusT * P0.X +
      3 * OneMinusT * OneMinusT * T * C1X +
      3 * OneMinusT * T * T * C2X +
      T * T * T * P1.X);
    Pts[S].Y := Round(
      OneMinusT * OneMinusT * OneMinusT * P0.Y +
      3 * OneMinusT * OneMinusT * T * P0.Y +
      3 * OneMinusT * T * T * P1.Y +
      T * T * T * P1.Y);
  end;
  C.Pen.Color := ACol;
  C.Pen.Width := AWidth;
  C.Polyline(Pts);
end;

procedure TPcgGraphForm.PaintGraphCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, GX, GY, I, SrcIdx: Integer;
  N, SrcN: TPcgGraphNode;
  BoxR: TRect;
  BadgeStr: String;
begin
  C := FPaintGraph.Canvas;
  W := FPaintGraph.Width;
  H := FPaintGraph.Height;

  C.Brush.Color := RGBToColor(26, 29, 34);
  C.FillRect(0, 0, W, H);

  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(38, 42, 49);
  GX := 0;
  while GX < W do begin C.Line(GX, 0, GX, H); Inc(GX, 20); end;
  GY := 0;
  while GY < H do begin C.Line(0, GY, W, GY); Inc(GY, 20); end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(84, 96, 110);
  C.TextOut(W - 185, H - 24, 'UE 5.5 PCG NODE GRAPH');

  if FActiveGraph = nil then Exit;

  { Wires }
  for I := 0 to High(FActiveGraph.Nodes) do
  begin
    N := FActiveGraph.Nodes[I];
    if N.InputNode0 <> '' then
    begin
      SrcIdx := FActiveGraph.FindNodeIndex(N.InputNode0);
      if SrcIdx >= 0 then
      begin
        SrcN := FActiveGraph.Nodes[SrcIdx];
        DrawCubicWire(C,
          Point(Round(SrcN.PosX) + PcgNodeW, Round(SrcN.PosY) + 42),
          Point(Round(N.PosX), Round(N.PosY) + 36),
          RGBToColor(112, 224, 148), 2);
      end;
    end;
    if N.InputNode1 <> '' then
    begin
      SrcIdx := FActiveGraph.FindNodeIndex(N.InputNode1);
      if SrcIdx >= 0 then
      begin
        SrcN := FActiveGraph.Nodes[SrcIdx];
        DrawCubicWire(C,
          Point(Round(SrcN.PosX) + PcgNodeW, Round(SrcN.PosY) + 42),
          Point(Round(N.PosX), Round(N.PosY) + 54),
          RGBToColor(242, 168, 72), 2);
      end;
    end;
  end;

  { Nodes }
  for I := 0 to High(FActiveGraph.Nodes) do
  begin
    N := FActiveGraph.Nodes[I];
    BoxR := Rect(Round(N.PosX), Round(N.PosY),
      Round(N.PosX) + PcgNodeW, Round(N.PosY) + PcgNodeH);

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(42, 46, 54);
    if SameText(FInspectedNodeId, N.NodeId) then
    begin
      C.Pen.Color := RGBToColor(96, 232, 255);
      C.Pen.Width := 3;
    end else
    begin
      C.Pen.Color := RGBToColor(18, 20, 24);
      C.Pen.Width := 1;
    end;
    C.RoundRect(BoxR, 8, 8);

    C.Brush.Color := HeaderColor(N.Kind);
    C.FillRect(BoxR.Left + 2, BoxR.Top + 2, BoxR.Right - 2, BoxR.Top + 24);

    C.Brush.Style := bsClear;
    C.Font.Color := clWhite;
    C.TextOut(BoxR.Left + 7, BoxR.Top + 5, Copy(TCastlePcgGraph.NodeKindTitle(N.Kind), 1, 20));

    C.Font.Color := RGBToColor(200, 212, 224);
    C.TextOut(BoxR.Left + 8, BoxR.Top + 30, N.NodeId);

    BadgeStr := Format('%d pts', [N.LastOutputCount]);
    C.Font.Color := RGBToColor(126, 238, 152);
    C.TextOut(BoxR.Right - 8 - C.TextWidth(BadgeStr), BoxR.Bottom - 20, BadgeStr);
  end;
end;

procedure TPcgGraphForm.PaintPointCloudInspector(Sender: TObject);
var
  C: TCanvas;
  W, H, CX, CY, PX, PZ, RX, RZ, I, Bright: Integer;
  SpanX, SpanZ, ScalePix: Single;
  Pt: TPcgPoint;
begin
  C := FPaintPointCloud.Canvas;
  W := FPaintPointCloud.Width;
  H := FPaintPointCloud.Height;

  C.Brush.Color := RGBToColor(20, 24, 28);
  C.FillRect(0, 0, W, H);

  CX := W div 2;
  CY := H div 2;
  C.Pen.Color := RGBToColor(48, 56, 66);
  C.Pen.Width := 1;
  C.Line(CX, 0, CX, H);
  C.Line(0, CY, W, CY);

  if FActiveGraph = nil then Exit;
  SpanX := Max(2.0, FActiveGraph.VolumeHalfExtents.X * 2.3);
  SpanZ := Max(2.0, FActiveGraph.VolumeHalfExtents.Z * 2.3);
  ScalePix := Min(W / SpanX, H / SpanZ);

  for I := 0 to High(FInspectedPoints) do
  begin
    Pt := FInspectedPoints[I];
    PX := CX + Round(Pt.Position.X * ScalePix);
    PZ := CY + Round(Pt.Position.Z * ScalePix);
    RX := Max(2, Round(Pt.BoundsHalfExtents.X * Pt.Scale.X * ScalePix));
    RZ := Max(2, Round(Pt.BoundsHalfExtents.Z * Pt.Scale.Z * ScalePix));

    Bright := EnsureRange(Round(75 + Pt.Density * 180), 40, 255);
    C.Brush.Style := bsClear;
    C.Pen.Color := RGBToColor(40, Bright div 2, 65);
    C.Rectangle(PX - RX, PZ - RZ, PX + RX, PZ + RZ);

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(64, Bright, 112);
    C.Pen.Color := C.Brush.Color;
    C.Ellipse(PX - 3, PZ - 3, PX + 4, PZ + 4);
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(145, 228, 255);
  C.TextOut(8, 8, Format('Inspect: %s (%d pts)', [FInspectedNodeId, Length(FInspectedPoints)]));
end;

procedure TPcgGraphForm.GraphMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  N: TPcgGraphNode;
begin
  if (FActiveGraph = nil) or (Button <> mbLeft) then Exit;
  for I := High(FActiveGraph.Nodes) downto 0 do
  begin
    N := FActiveGraph.Nodes[I];
    if (X >= Round(N.PosX)) and (X <= Round(N.PosX) + PcgNodeW) and
       (Y >= Round(N.PosY)) and (Y <= Round(N.PosY) + PcgNodeH) then
    begin
      FInspectedNodeId := N.NodeId;
      FDraggingNode := True;
      FDragOffsetX := X - N.PosX;
      FDragOffsetY := Y - N.PosY;
      RefreshFromScene;
      Exit;
    end;
  end;
end;

procedure TPcgGraphForm.GraphMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
begin
  if FDraggingNode and (FActiveGraph <> nil) and (FInspectedNodeId <> '') then
  begin
    FActiveGraph.SetNodePosition(FInspectedNodeId,
      Max(8.0, X - FDragOffsetX), Max(8.0, Y - FDragOffsetY));
    FPaintGraph.Invalidate;
  end;
end;

procedure TPcgGraphForm.GraphMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingNode then
  begin
    FDraggingNode := False;
    NotifyChanged('Move PCG Node');
  end;
end;

procedure TPcgGraphForm.BtnSpawnForestRoadClick(Sender: TObject);
begin
  FActiveGraph := TPcgGraphHelper.SpawnPcgPresetInDesign(
    FDesignRoot, FDesignOwner, pgpForestWithRoadClearing, Vector3(0, 0, 0));
  FInspectedNodeId := 'Prune_NoOverlap';
  NotifyChanged('Spawn PCG Forest + Road Clearing Graph');
end;

procedure TPcgGraphForm.BtnSpawnRockUnionClick(Sender: TObject);
begin
  FActiveGraph := TPcgGraphHelper.SpawnPcgPresetInDesign(
    FDesignRoot, FDesignOwner, pgpRockOutcropAndShrubUnion, Vector3(26, 0, 0));
  FInspectedNodeId := 'Prune_Biome';
  NotifyChanged('Spawn PCG Rock & Shrub Union Graph');
end;

procedure TPcgGraphForm.BtnSpawnSplinePostsClick(Sender: TObject);
begin
  FActiveGraph := TPcgGraphHelper.SpawnPcgPresetInDesign(
    FDesignRoot, FDesignOwner, pgpSplineFenceColonnade, Vector3(0, 0, 22));
  FInspectedNodeId := 'Spawn_Posts';
  NotifyChanged('Spawn PCG Spline Colonnade Graph');
end;

procedure TPcgGraphForm.BtnExecuteClick(Sender: TObject);
begin
  if FActiveGraph = nil then Exit;
  FActiveGraph.ExecuteGraph;
  NotifyChanged('Execute PCG Graph');
end;

procedure TPcgGraphForm.BtnReseedClick(Sender: TObject);
begin
  if FActiveGraph = nil then Exit;
  FActiveGraph.GraphSeed := FActiveGraph.GraphSeed + 1;
  NotifyChanged('Re-Seed PCG Graph');
end;

procedure TPcgGraphForm.BtnCycleInspectClick(Sender: TObject);
var
  Idx: Integer;
begin
  if (FActiveGraph = nil) or (Length(FActiveGraph.Nodes) = 0) then Exit;
  Idx := FActiveGraph.FindNodeIndex(FInspectedNodeId);
  Idx := (Idx + 1) mod Length(FActiveGraph.Nodes);
  FInspectedNodeId := FActiveGraph.Nodes[Idx].NodeId;
  RefreshFromScene;
end;

procedure TPcgGraphForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoTelemetry.Text;
end;

end.
