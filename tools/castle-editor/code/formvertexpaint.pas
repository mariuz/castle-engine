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

{ Unreal Engine 5.5-style Viewport Mesh Vertex Paint Mode Studio featuring an
  interactive 3D Shaded Mesh & Radial Falloff Brush Canvas (click/drag to paint
  Moss [R], Rain Puddle [G], Edge Wear [B], or Snow [A] with HeightLerp 4-layer
  material blending vs. Raw RGBA visualization) and a Multi-Layer RGBA Channel
  Mask & Coverage Inspector (Phase 396 — 116 UE Studios / 39 MCP). }
unit FormVertexPaint;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleVertexPaint, ToolVertexPaint;

type
  TVertexPaintModifiedCallback = procedure(const UndoComment: String) of object;
  TVertexPaintRefreshCallback = procedure of object;

  TVertexPaintForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TVertexPaintModifiedCallback;
    FOnRefresh: TVertexPaintRefreshCallback;

    FActiveMesh: TCastleVertexPaintMesh;
    FActiveChannel: TVertexPaintChannel;
    FHoverVertexIdx: Integer;
    FIsDraggingBrush: Boolean;

    FLblStatus: TLabel;
    FPaintMeshCanvas: TPaintBox;
    FPaintInspector: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    function ProjectVertex2D(const P: TVector3; const W, H: Integer): TPoint;
    function PickVertexAtScreen(const SX, SY: Integer): Integer;
    procedure ApplyStrokeAtScreen(const SX, SY: Integer; const AErase: Boolean);

    procedure PaintMeshViewport(Sender: TObject);
    procedure PaintChannelInspector(Sender: TObject);

    procedure MeshCanvasMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure MeshCanvasMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure MeshCanvasMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure BtnSpawnCobbleClick(Sender: TObject);
    procedure BtnSpawnWallClick(Sender: TObject);
    procedure BtnPaintMossStrokeClick(Sender: TObject);
    procedure BtnPaintPuddleStrokeClick(Sender: TObject);
    procedure BtnSmoothColorsClick(Sender: TObject);
    procedure BtnCycleViewModeClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TVertexPaintModifiedCallback;
      const AOnRefresh: TVertexPaintRefreshCallback);
  end;

implementation

constructor TVertexPaintForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TVertexPaintModifiedCallback;
  const AOnRefresh: TVertexPaintRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FActiveChannel := vpcGreen;
  FHoverVertexIdx := -1;
  FIsDraggingBrush := False;

  Caption := 'Viewport Mesh Vertex Paint Mode & Multi-Layer Blend Studio (MeshPaintMode — 116 UE Studios / 39 MCP)';
  Position := poScreenCenter;
  Width := 1340;
  Height := 760;

  BuildUi;
  FActiveMesh := TVertexPaintHelper.FindFirstVertexPaintMesh(FDesignRoot);
  if (FActiveMesh <> nil) and (FActiveMesh.VertexCount > 0) then
    FHoverVertexIdx := FActiveMesh.VertexCount div 2;
  RefreshFromScene;
end;

procedure TVertexPaintForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlBottom, PnlRight: TPanel;
  BtnCobble, BtnWall, BtnMoss, BtnPuddle, BtnSmooth, BtnView, BtnCopy, BtnClose: TButton;
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
  FLblStatus.Caption := 'Viewport Mesh Vertex Paint Mode Ready.';

  XPos := 8;
  BtnCobble := MakeToolbarBtn('+ Cobblestone Slab', 154, @BtnSpawnCobbleClick);
  BtnWall := MakeToolbarBtn('+ Bastion Wall', 132, @BtnSpawnWallClick);
  BtnMoss := MakeToolbarBtn('Brush Moss [R]', 138, @BtnPaintMossStrokeClick);
  BtnPuddle := MakeToolbarBtn('Brush Puddle [G]', 148, @BtnPaintPuddleStrokeClick);
  BtnSmooth := MakeToolbarBtn('Laplacian Smooth', 150, @BtnSmoothColorsClick);
  BtnView := MakeToolbarBtn('Cycle View (Mat/RGBA)', 176, @BtnCycleViewModeClick);
  BtnCopy := MakeToolbarBtn('Copy Report', 106, @BtnCopyReportClick);
  BtnClose := MakeToolbarBtn('Close', 72, nil);
  BtnClose.ModalResult := mrOk;
  if (BtnCobble <> nil) and (BtnWall <> nil) and (BtnMoss <> nil) and
     (BtnPuddle <> nil) and (BtnSmooth <> nil) and (BtnView <> nil) and
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
  PnlRight.Width := 592;
  PnlRight.BevelOuter := bvNone;

  FPaintInspector := TPaintBox.Create(Self);
  FPaintInspector.Parent := PnlRight;
  FPaintInspector.Align := alClient;
  FPaintInspector.OnPaint := @PaintChannelInspector;

  FPaintMeshCanvas := TPaintBox.Create(Self);
  FPaintMeshCanvas.Parent := Self;
  FPaintMeshCanvas.Align := alClient;
  FPaintMeshCanvas.OnPaint := @PaintMeshViewport;
  FPaintMeshCanvas.OnMouseDown := @MeshCanvasMouseDown;
  FPaintMeshCanvas.OnMouseMove := @MeshCanvasMouseMove;
  FPaintMeshCanvas.OnMouseUp := @MeshCanvasMouseUp;
end;

procedure TVertexPaintForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh;
  RefreshFromScene;
end;

procedure TVertexPaintForm.RefreshFromScene;
begin
  if FActiveMesh = nil then
    FActiveMesh := TVertexPaintHelper.FindFirstVertexPaintMesh(FDesignRoot);

  if FActiveMesh <> nil then
  begin
    if (FHoverVertexIdx < 0) or (FHoverVertexIdx >= FActiveMesh.VertexCount) then
      FHoverVertexIdx := FActiveMesh.VertexCount div 2;
    FLblStatus.Caption := Format(
      'Active Mesh: %s  |  Vertices: %d (%d Painted)  |  View: %s  |  Moss=%.0f%%  Puddle=%.0f%%  Wear=%.0f%%  Snow=%.0f%%',
      [FActiveMesh.Name,
       FActiveMesh.VertexCount,
       FActiveMesh.PaintedVertexCount,
       VertexPaintPreviewModeDisplayName(FActiveMesh.PreviewMode),
       FActiveMesh.AverageChannelWeight(vpcRed) * 100.0,
       FActiveMesh.AverageChannelWeight(vpcGreen) * 100.0,
       FActiveMesh.AverageChannelWeight(vpcBlue) * 100.0,
       FActiveMesh.AverageChannelWeight(vpcAlpha) * 100.0]);
  end else
    FLblStatus.Caption := 'No TCastleVertexPaintMesh in scene — click "+ Cobblestone Slab" to paint per-vertex RGBA weights.';

  FMemoReport.Lines.Text := TVertexPaintHelper.GenerateMarkdownReport(
    FDesignRoot, FActiveMesh);

  FPaintMeshCanvas.Invalidate;
  FPaintInspector.Invalidate;
end;

function TVertexPaintForm.ProjectVertex2D(const P: TVector3;
  const W, H: Integer): TPoint;
var
  ScalePx, IsoX, IsoY: Single;
begin
  ScalePx := Min((W - 120) / 13.5, (H - 120) / 9.2);
  if (FActiveMesh <> nil) and (FActiveMesh.Preset = vppRuinedArchwaySootWear) then
  begin
    IsoX := P.X * 0.92 + P.Z * 0.35;
    IsoY := (P.Y - 2.6) * 0.95 - P.Z * 0.22;
  end else
  begin
    { Elevated 38-degree isometric view over the cobblestone courtyard / cliff }
    IsoX := P.X * 0.86 - P.Z * 0.52;
    IsoY := P.Y * 1.15 - (P.X * 0.28 + P.Z * 0.62);
  end;
  Result.X := (W div 2) + Round(IsoX * ScalePx);
  Result.Y := (H div 2 + 18) - Round(IsoY * ScalePx);
end;

function TVertexPaintForm.PickVertexAtScreen(const SX, SY: Integer): Integer;
var
  I, W, H: Integer;
  Pt: TPoint;
  BestDistSq, DSq: Single;
begin
  Result := -1;
  if FActiveMesh = nil then Exit;
  W := Max(360, FPaintMeshCanvas.Width);
  H := Max(320, FPaintMeshCanvas.Height);
  BestDistSq := MaxSingle;
  for I := 0 to FActiveMesh.VertexCount - 1 do
  begin
    Pt := ProjectVertex2D(FActiveMesh.Vertices[I].Position, W, H);
    DSq := Sqr(Pt.X - SX) + Sqr(Pt.Y - SY);
    if DSq < BestDistSq then
    begin
      BestDistSq := DSq;
      Result := I;
    end;
  end;
end;

procedure TVertexPaintForm.ApplyStrokeAtScreen(const SX, SY: Integer;
  const AErase: Boolean);
var
  VIdx: Integer;
  TargetCol: TVector4;
  Mask: TVertexPaintChannelMask;
begin
  if FActiveMesh = nil then Exit;
  VIdx := PickVertexAtScreen(SX, SY);
  if VIdx < 0 then Exit;
  FHoverVertexIdx := VIdx;

  Mask := [FActiveChannel];
  TargetCol := TVector4.Zero;
  case FActiveChannel of
    vpcRed:   TargetCol.X := 1.0;
    vpcGreen: TargetCol.Y := 1.0;
    vpcBlue:  TargetCol.Z := 1.0;
    vpcAlpha: TargetCol.W := 1.0;
  end;

  FActiveMesh.ApplyBrushStroke(
    FActiveMesh.Vertices[VIdx].Position + FActiveMesh.Translation,
    FActiveMesh.BrushRadius, FActiveMesh.BrushFalloff, FActiveMesh.BrushStrength,
    TargetCol, Mask, AErase);
  RefreshFromScene;
end;

procedure TVertexPaintForm.MeshCanvasMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FActiveMesh = nil then Exit;
  FIsDraggingBrush := True;
  ApplyStrokeAtScreen(X, Y, (Button = mbRight) or (ssShift in Shift));
end;

procedure TVertexPaintForm.MeshCanvasMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  if FActiveMesh = nil then Exit;
  FHoverVertexIdx := PickVertexAtScreen(X, Y);
  if FIsDraggingBrush then
    ApplyStrokeAtScreen(X, Y, ssShift in Shift)
  else
    FPaintMeshCanvas.Invalidate;
end;

procedure TVertexPaintForm.MeshCanvasMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FIsDraggingBrush then
  begin
    FIsDraggingBrush := False;
    NotifyChanged('Paint Mesh Vertex RGBA Weights');
  end;
end;

procedure TVertexPaintForm.PaintMeshViewport(Sender: TObject);
type
  TTriDepth = record
    TriIdx: Integer;
    DepthZ: Single;
  end;
var
  C: TCanvas;
  W, H, I, J, ROuter, RInner: Integer;
  Order: array of TTriDepth;
  Tmp: TTriDepth;
  Tri: TVertexPaintTriangle;
  Pts: array[0..2] of TPoint;
  C0, C1, C2, AvgCol, SunDir, FaceN: TVector3;
  Surf0: TVertexPaintSurfaceSample;
  Shade, SpecBoost: Single;
  HoverPt: TPoint;
begin
  C := FPaintMeshCanvas.Canvas;
  W := Max(360, FPaintMeshCanvas.Width);
  H := Max(320, FPaintMeshCanvas.Height);

  C.Brush.Color := RGBToColor(18, 21, 28);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(28, 34, 46);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(126, 206, 255);
  C.TextOut(12, 7, '3D Mesh Paint Viewport  (LMB=Paint | Shift/RMB=Erase | Red/Cyan Ring=Falloff)');
  C.Font.Style := [];

  if (FActiveMesh = nil) or (FActiveMesh.TriangleCount = 0) then Exit;

  { Back-to-front painter sort for crisp 3D isometric surface rendering }
  SetLength(Order, FActiveMesh.TriangleCount);
  for I := 0 to High(Order) do
  begin
    Tri := FActiveMesh.Triangles[I];
    Order[I].TriIdx := I;
    Order[I].DepthZ := (FActiveMesh.Vertices[Tri.V0].Position.Z +
                        FActiveMesh.Vertices[Tri.V1].Position.Z +
                        FActiveMesh.Vertices[Tri.V2].Position.Z) / 3.0;
  end;
  for I := 0 to High(Order) - 1 do
    for J := I + 1 to High(Order) do
      if Order[J].DepthZ < Order[I].DepthZ then
      begin
        Tmp := Order[I];
        Order[I] := Order[J];
        Order[J] := Tmp;
      end;

  SunDir := Vector3(0.45, 0.80, -0.38).Normalize;
  C.Pen.Color := RGBToColor(36, 42, 54);
  C.Pen.Width := 1;

  for I := 0 to High(Order) do
  begin
    Tri := FActiveMesh.Triangles[Order[I].TriIdx];
    Pts[0] := ProjectVertex2D(FActiveMesh.Vertices[Tri.V0].Position, W, H);
    Pts[1] := ProjectVertex2D(FActiveMesh.Vertices[Tri.V1].Position, W, H);
    Pts[2] := ProjectVertex2D(FActiveMesh.Vertices[Tri.V2].Position, W, H);

    C0 := FActiveMesh.EvaluateDisplayColorRGB(Tri.V0);
    C1 := FActiveMesh.EvaluateDisplayColorRGB(Tri.V1);
    C2 := FActiveMesh.EvaluateDisplayColorRGB(Tri.V2);
    AvgCol := (C0 + C1 + C2) / 3.0;

    FaceN := (FActiveMesh.Vertices[Tri.V0].Normal +
              FActiveMesh.Vertices[Tri.V1].Normal +
              FActiveMesh.Vertices[Tri.V2].Normal).Normalize;
    Shade := 0.48 + 0.52 * Max(0.0, TVector3.DotProduct(FaceN, SunDir));

    { Wet puddle specular sky glint in HeightLerp Material mode! }
    SpecBoost := 0.0;
    if FActiveMesh.PreviewMode = vpmMaterialHeightLerp then
    begin
      Surf0 := FActiveMesh.EvaluateBlendedSurface(Tri.V0);
      if Surf0.EffectivePuddle > 0.25 then
        SpecBoost := Surf0.EffectivePuddle * Power(Max(0.0, FaceN.Y), 6.0) * 0.42;
    end;

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(
      EnsureRange(Round((AvgCol.X * Shade + SpecBoost * 0.75) * 255), 0, 255),
      EnsureRange(Round((AvgCol.Y * Shade + SpecBoost * 0.88) * 255), 0, 255),
      EnsureRange(Round((AvgCol.Z * Shade + SpecBoost * 1.00) * 255), 0, 255));
    C.Polygon(Pts);
  end;

  { Draw UE 5.5 Spherical Falloff Brush Gizmo (Outer Radius + Inner Full-Strength Ring) }
  if (FHoverVertexIdx >= 0) and (FHoverVertexIdx < FActiveMesh.VertexCount) then
  begin
    HoverPt := ProjectVertex2D(FActiveMesh.Vertices[FHoverVertexIdx].Position, W, H);
    ROuter := Max(18, Round(FActiveMesh.BrushRadius * 36.0));
    RInner := Max(6, Round(ROuter * (1.0 - FActiveMesh.BrushFalloff)));

    C.Brush.Style := bsClear;
    C.Pen.Width := 2;
    C.Pen.Color := RGBToColor(255, 92, 102);
    C.Ellipse(HoverPt.X - ROuter, HoverPt.Y - ROuter, HoverPt.X + ROuter, HoverPt.Y + ROuter);

    C.Pen.Width := 1;
    C.Pen.Color := RGBToColor(96, 226, 255);
    C.Ellipse(HoverPt.X - RInner, HoverPt.Y - RInner, HoverPt.X + RInner, HoverPt.Y + RInner);

    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(255, 224, 132);
    C.TextOut(Max(12, Min(W - 220, HoverPt.X - 68)), Max(36, HoverPt.Y - ROuter - 20),
      Format('Brush R=%.1fm  Falloff=%.0f%%',
        [FActiveMesh.BrushRadius, FActiveMesh.BrushFalloff * 100.0]));
    C.Font.Style := [];
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(188, 206, 232);
  C.TextOut(14, H - 26,
    'HeightLerp fills mortar crevices with Moss [R] & Rain Puddles [G] (Rough=0.06) before covering stones.');
  C.Brush.Style := bsSolid;
end;

procedure TVertexPaintForm.PaintChannelInspector(Sender: TObject);
const
  ChanNames: array[TVertexPaintChannel] of String = (
    '[R] Moss / Lichen Layer',
    '[G] Rain Puddle / Wetness (Rough=0.06)',
    '[B] Edge Wear / Torch Soot',
    '[A] Snow / Mortar Dust Cap'
  );
  ChanColors: array[TVertexPaintChannel] of TColor = (
    $004CD66E, { Greenish-Red badge }
    $00FFBA48, { Puddle Cyan-Blue }
    $0066B2FF, { Warm Wear Amber }
    $00F8F2EC  { Snow White }
  );
var
  C: TCanvas;
  W, H, RowY, BarW, FillW, I, SampleIdx: Integer;
  Ch: TVertexPaintChannel;
  Pct, Energy: Single;
  V: TVertexPaintVertex;
  Surf: TVertexPaintSurfaceSample;
begin
  C := FPaintInspector.Canvas;
  W := Max(360, FPaintInspector.Width);
  H := Max(320, FPaintInspector.Height);

  C.Brush.Color := RGBToColor(24, 26, 33);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 214, 112);
  C.TextOut(12, 7, 'Mesh Paint RGBA Channel Masks & HeightLerp Coverage');
  C.Font.Style := [];

  if FActiveMesh = nil then Exit;

  { Brush Settings Card }
  C.Brush.Color := RGBToColor(29, 33, 44);
  C.FillRect(12, 40, W - 12, 108);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(212, 226, 248);
  C.TextOut(22, 48, Format('Brush Settings  |  Active: %s',
    [ChanNames[FActiveChannel]]));
  C.Font.Style := [];
  C.Font.Color := RGBToColor(168, 186, 214);
  C.TextOut(22, 70, Format(
    'Radius: %.2fm  |  Falloff: %.2f  |  Strength: %.2f  |  HeightLerp: %.2f',
    [FActiveMesh.BrushRadius, FActiveMesh.BrushFalloff,
     FActiveMesh.BrushStrength, FActiveMesh.HeightLerpContrast]));
  C.TextOut(22, 88, Format(
    'Preview Mode: %s   |   Mesh Grid: %dx%d (%d tris)',
    [VertexPaintPreviewModeDisplayName(FActiveMesh.PreviewMode),
     FActiveMesh.GridCols, FActiveMesh.GridRows, FActiveMesh.TriangleCount]));

  { 4 RGBA Channel Coverage Bars + Roughness Seam Energy }
  BarW := W - 48;
  for Ch := Low(TVertexPaintChannel) to High(TVertexPaintChannel) do
  begin
    RowY := 120 + Ord(Ch) * 58;
    C.Brush.Style := bsSolid;
    if Ch = FActiveChannel then
      C.Brush.Color := RGBToColor(34, 48, 68)
    else
      C.Brush.Color := RGBToColor(28, 31, 40);
    C.FillRect(12, RowY, W - 12, RowY + 52);

    Pct := FActiveMesh.AverageChannelWeight(Ch) * 100.0;
    Energy := FActiveMesh.ComputeChannelRoughnessEnergy(Ch);

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := ChanColors[Ch];
    C.TextOut(22, RowY + 6, ChanNames[Ch]);
    C.Font.Style := [];
    C.Font.Color := RGBToColor(186, 202, 226);
    C.TextOut(W - 220, RowY + 6, Format('Avg: %5.1f%%  |  Seam: %.4f', [Pct, Energy]));

    { Progress Track }
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(17, 19, 25);
    C.FillRect(22, RowY + 28, 22 + BarW, RowY + 42);

    FillW := Round(EnsureRange(Pct / 100.0, 0.0, 1.0) * BarW);
    if FillW > 0 then
    begin
      C.Brush.Color := ChanColors[Ch];
      C.FillRect(22, RowY + 28, 22 + FillW, RowY + 42);
    end;
  end;

  { Sampled Vertex HeightLerp Table }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(29, 33, 43);
  C.FillRect(12, 360, W - 12, 384);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(172, 188, 214);
  C.TextOut(20, 365, 'Vertex');
  C.TextOut(90, 365, 'RGBA Weights');
  C.TextOut(286, 365, 'Height01');
  C.TextOut(368, 365, 'PBR Roughness');
  C.Font.Style := [];

  for I := 0 to 4 do
  begin
    SampleIdx := EnsureRange((I * (FActiveMesh.VertexCount - 1)) div 4,
      0, FActiveMesh.VertexCount - 1);
    V := FActiveMesh.Vertices[SampleIdx];
    Surf := FActiveMesh.EvaluateBlendedSurface(SampleIdx);
    RowY := 388 + I * 26;
    if RowY + 24 > H - 8 then Break;

    C.Brush.Style := bsSolid;
    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(27, 30, 39)
    else
      C.Brush.Color := RGBToColor(23, 26, 34);
    C.FillRect(12, RowY, W - 12, RowY + 24);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(182, 216, 255);
    C.TextOut(20, RowY + 4, Format('#%3d', [SampleIdx]));
    C.Font.Color := RGBToColor(206, 218, 236);
    C.TextOut(90, RowY + 4, Format('(%.2f, %.2f, %.2f, %.2f)',
      [V.ColorRGBA.X, V.ColorRGBA.Y, V.ColorRGBA.Z, V.ColorRGBA.W]));
    C.TextOut(286, RowY + 4, Format('%.2f', [V.MicroHeight01]));
    if Surf.Roughness < 0.20 then
      C.Font.Color := RGBToColor(102, 224, 255)
    else
      C.Font.Color := RGBToColor(196, 212, 232);
    C.TextOut(368, RowY + 4, Format('%.2f (%s)',
      [Surf.Roughness, IfThen(Surf.Roughness < 0.20, 'Mirror Puddle', 'Stone/Moss')]));
  end;
  C.Brush.Style := bsSolid;
end;

procedure TVertexPaintForm.BtnSpawnCobbleClick(Sender: TObject);
begin
  FActiveMesh := TVertexPaintHelper.SpawnVertexPaintPresetInDesign(
    FDesignRoot, FDesignOwner, vppCobblestoneWallMossPuddles, Vector3(0, 0, 0));
  NotifyChanged('Spawn Cobblestone Courtyard Vertex Paint Mesh');
end;

procedure TVertexPaintForm.BtnSpawnWallClick(Sender: TObject);
begin
  FActiveMesh := TVertexPaintHelper.SpawnVertexPaintPresetInDesign(
    FDesignRoot, FDesignOwner, vppRuinedArchwaySootWear, Vector3(0, 0, -6));
  NotifyChanged('Spawn Ruined Bastion Wall Vertex Paint Mesh');
end;

procedure TVertexPaintForm.BtnPaintMossStrokeClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveChannel := vpcRed;
  FActiveMesh.ApplyBrushStroke(
    FActiveMesh.Translation + Vector3(-2.0, 0.0, 1.2),
    2.6, 0.45, 0.90, Vector4(1, 0, 0, 0), [vpcRed], False);
  NotifyChanged('Paint Radial Moss [R] Vertex Stroke');
end;

procedure TVertexPaintForm.BtnPaintPuddleStrokeClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveChannel := vpcGreen;
  FActiveMesh.ApplyBrushStroke(
    FActiveMesh.Translation + Vector3(0.4, -0.2, -0.4),
    2.5, 0.50, 0.92, Vector4(0, 1, 0, 0), [vpcGreen], False);
  NotifyChanged('Paint Radial Rain Puddle [G] Vertex Stroke');
end;

procedure TVertexPaintForm.BtnSmoothColorsClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveMesh.SmoothVertexColors(FActiveMesh.Translation, 5.0, 0.65,
    TCastleVertexPaintMesh.AllPaintChannels, True);
  NotifyChanged('Smooth Vertex RGBA Weights (1-Ring Laplacian)');
end;

procedure TVertexPaintForm.BtnCycleViewModeClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  if FActiveMesh.PreviewMode = High(TVertexPaintBlendPreviewMode) then
    FActiveMesh.PreviewMode := Low(TVertexPaintBlendPreviewMode)
  else
    FActiveMesh.PreviewMode := Succ(FActiveMesh.PreviewMode);
  RefreshFromScene;
end;

procedure TVertexPaintForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
  FLblStatus.Caption := 'Copied Viewport Mesh Vertex Paint Report to Clipboard.';
end;

end.
