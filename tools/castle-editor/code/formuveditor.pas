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

{ Unreal Engine 5.5-style Modeling Mode UV Editor & Texel-Density Studio dialog
  featuring a [0..1] UV Checkerboard & Packed Island Canvas (highlighting
  distinct UV islands, texel gutter margins, and red overlapping UV triangles),
  plus a per-island Texel-Density (px/m) & Coverage Auditor
  (Phase 389 — 109 UE Studios / 32 MCP). }
unit FormUvEditor;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleUvEditor, ToolUvEditor;

type
  TUvEditorModifiedCallback = procedure(const UndoComment: String) of object;
  TUvEditorRefreshCallback = procedure of object;

  TUvEditorForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TUvEditorModifiedCallback;
    FOnRefresh: TUvEditorRefreshCallback;

    FActiveMesh: TCastleUvEditorMesh;

    FLblStatus: TLabel;
    FPaintUvSquare: TPaintBox;
    FPaintIslands: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);
    function IslandPaletteColor(const AIslandId: Integer): TColor;

    procedure PaintUvSquareCanvas(Sender: TObject);
    procedure PaintIslandsInspector(Sender: TObject);

    procedure BtnSpawnCrateClick(Sender: TObject);
    procedure BtnSpawnColumnClick(Sender: TObject);
    procedure BtnSpawnOverlapDemoClick(Sender: TObject);
    procedure BtnUnwrapBoxClick(Sender: TObject);
    procedure BtnUnwrapCylClick(Sender: TObject);
    procedure BtnConformalRelaxClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TUvEditorModifiedCallback;
      const AOnRefresh: TUvEditorRefreshCallback);
  end;

implementation

constructor TUvEditorForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TUvEditorModifiedCallback;
  const AOnRefresh: TUvEditorRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Modeling Mode UV Editor & Texel-Density Studio (109 UE Studios / 32 MCP)';
  Position := poScreenCenter;
  Width := 1280;
  Height := 720;

  BuildUi;
  FActiveMesh := TUvEditorHelper.FindFirstUvMesh(FDesignRoot);
  RefreshFromScene;
end;

procedure TUvEditorForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlRight, PnlBottom: TPanel;
  BtnCrate, BtnCol, BtnOvl, BtnBox, BtnCyl, BtnRelax, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 32;
  PnlTop.BevelOuter := bvNone;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 10;
  FLblStatus.Top := 8;
  FLblStatus.Caption := 'Modeling Mode UV Editor & Texel-Density Studio Ready.';

  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;

  BtnCrate := TButton.Create(Self);
  BtnCrate.Parent := PnlToolbar;
  BtnCrate.SetBounds(8, 6, 158, 30);
  BtnCrate.Caption := '+ 6-Island Crate UV';
  BtnCrate.OnClick := @BtnSpawnCrateClick;

  BtnCol := TButton.Create(Self);
  BtnCol.Parent := PnlToolbar;
  BtnCol.SetBounds(170, 6, 174, 30);
  BtnCol.Caption := '+ Cylindrical Column UV';
  BtnCol.OnClick := @BtnSpawnColumnClick;

  BtnOvl := TButton.Create(Self);
  BtnOvl.Parent := PnlToolbar;
  BtnOvl.SetBounds(348, 6, 172, 30);
  BtnOvl.Caption := '+ Overlap Audit Demo';
  BtnOvl.OnClick := @BtnSpawnOverlapDemoClick;

  BtnBox := TButton.Create(Self);
  BtnBox.Parent := PnlToolbar;
  BtnBox.SetBounds(524, 6, 168, 30);
  BtnBox.Caption := 'Box Unwrap + Pack';
  BtnBox.OnClick := @BtnUnwrapBoxClick;

  BtnCyl := TButton.Create(Self);
  BtnCyl.Parent := PnlToolbar;
  BtnCyl.SetBounds(696, 6, 168, 30);
  BtnCyl.Caption := 'Cylinder Seam + Pack';
  BtnCyl.OnClick := @BtnUnwrapCylClick;

  BtnRelax := TButton.Create(Self);
  BtnRelax.Parent := PnlToolbar;
  BtnRelax.SetBounds(868, 6, 156, 30);
  BtnRelax.Caption := 'Conformal + Pack';
  BtnRelax.OnClick := @BtnConformalRelaxClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlToolbar;
  BtnCopy.SetBounds(1028, 6, 128, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyMarkdownClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 136;
  PnlBottom.BevelOuter := bvNone;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := PnlBottom;
  FMemoReport.Align := alClient;
  FMemoReport.ScrollBars := ssVertical;
  FMemoReport.ReadOnly := True;
  FMemoReport.Font.Name := 'Monospace';

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.Align := alRight;
  BtnClose.Width := 74;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 490;
  PnlRight.BevelOuter := bvLowered;

  FPaintIslands := TPaintBox.Create(Self);
  FPaintIslands.Parent := PnlRight;
  FPaintIslands.Align := alClient;
  FPaintIslands.OnPaint := @PaintIslandsInspector;

  FPaintUvSquare := TPaintBox.Create(Self);
  FPaintUvSquare.Parent := Self;
  FPaintUvSquare.Align := alClient;
  FPaintUvSquare.OnPaint := @PaintUvSquareCanvas;
end;

procedure TUvEditorForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TUvEditorForm.RefreshFromScene;
begin
  if (FActiveMesh = nil) and (FDesignRoot <> nil) then
    FActiveMesh := TUvEditorHelper.FindFirstUvMesh(FDesignRoot);

  if FActiveMesh <> nil then
  begin
    FActiveMesh.AuditUvLayout;
    FLblStatus.Caption := FActiveMesh.Name + '  ' + FActiveMesh.UvSummaryBadge +
      Format('  TargetTD=%.0f px/m  Res=%dx%d',
        [FActiveMesh.TargetTexelsPerMeter, FActiveMesh.TextureResolution, FActiveMesh.TextureResolution]);
  end else
    FLblStatus.Caption := 'No TCastleUvEditorMesh in design — click "+ 6-Island Crate UV".';

  FMemoReport.Text := TUvEditorHelper.GenerateMarkdownReport(FDesignRoot, FActiveMesh);
  FPaintUvSquare.Invalidate;
  FPaintIslands.Invalidate;
end;

function TUvEditorForm.IslandPaletteColor(const AIslandId: Integer): TColor;
begin
  case Abs(AIslandId) mod 6 of
    0: Result := RGBToColor(58, 128, 208);
    1: Result := RGBToColor(52, 166, 108);
    2: Result := RGBToColor(196, 124, 48);
    3: Result := RGBToColor(148, 86, 198);
    4: Result := RGBToColor(48, 168, 178);
  else
    Result := RGBToColor(186, 82, 124);
  end;
end;

procedure TUvEditorForm.PaintUvSquareCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, SqSize, SqL, SqT, GX, GY, CellPx, I: Integer;
  P0, P1, P2: TPoint;
  HasOverlap: Boolean;
begin
  C := FPaintUvSquare.Canvas;
  W := FPaintUvSquare.Width;
  H := FPaintUvSquare.Height;

  C.Brush.Color := RGBToColor(18, 20, 26);
  C.FillRect(0, 0, W, H);

  SqSize := Min(W - 48, H - 52);
  SqL := (W - SqSize) div 2;
  SqT := (H - SqSize) div 2 + 10;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(148, 206, 255);
  C.TextOut(SqL, 8, 'UV [0..1] Unit Square (8x8 Texel Checkerboard & Packed Islands)');

  { 8x8 UV Checkerboard background }
  CellPx := Max(4, SqSize div 8);
  for GY := 0 to 7 do
    for GX := 0 to 7 do
    begin
      C.Brush.Style := bsSolid;
      if Odd(GX + GY) then
        C.Brush.Color := RGBToColor(34, 38, 46)
      else
        C.Brush.Color := RGBToColor(26, 29, 36);
      C.FillRect(
        SqL + GX * CellPx,
        SqT + GY * CellPx,
        Min(SqL + SqSize, SqL + (GX + 1) * CellPx),
        Min(SqT + SqSize, SqT + (GY + 1) * CellPx));
    end;

  C.Brush.Style := bsClear;
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(92, 148, 218);
  C.Rectangle(SqL, SqT, SqL + SqSize, SqT + SqSize);

  if FActiveMesh = nil then Exit;

  HasOverlap := FActiveMesh.LastAudit.OverlappingPairCount > 0;
  for I := 0 to High(FActiveMesh.Triangles) do
  begin
    P0.X := SqL + Round(FActiveMesh.Triangles[I].UV[0].X * SqSize);
    P0.Y := SqT + SqSize - Round(FActiveMesh.Triangles[I].UV[0].Y * SqSize);
    P1.X := SqL + Round(FActiveMesh.Triangles[I].UV[1].X * SqSize);
    P1.Y := SqT + SqSize - Round(FActiveMesh.Triangles[I].UV[1].Y * SqSize);
    P2.X := SqL + Round(FActiveMesh.Triangles[I].UV[2].X * SqSize);
    P2.Y := SqT + SqSize - Round(FActiveMesh.Triangles[I].UV[2].Y * SqSize);

    C.Brush.Style := bsSolid;
    if HasOverlap then
    begin
      C.Brush.Color := RGBToColor(156, 42, 48);
      C.Pen.Color := RGBToColor(255, 112, 112);
    end else
    begin
      C.Brush.Color := IslandPaletteColor(FActiveMesh.Triangles[I].IslandId);
      C.Pen.Color := RGBToColor(232, 242, 255);
    end;
    C.Polygon([P0, P1, P2]);
  end;
end;

procedure TUvEditorForm.PaintIslandsInspector(Sender: TObject);
var
  C: TCanvas;
  W, H, YRow, I, BarW: Integer;
  Isl: TUvIslandInfo;
  Ratio: Single;
begin
  C := FPaintIslands.Canvas;
  W := FPaintIslands.Width;
  H := FPaintIslands.Height;

  C.Brush.Color := RGBToColor(24, 26, 32);
  C.FillRect(0, 0, W, H);

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(36, 42, 54);
  C.FillRect(0, 0, W, 30);
  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(12, 7, 'Packed UV Islands & World-Space Texel Density (px/m)');

  if FActiveMesh = nil then Exit;

  YRow := 38;
  for I := 0 to High(FActiveMesh.Islands) do
  begin
    Isl := FActiveMesh.Islands[I];
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(34, 38, 46);
    C.Pen.Color := RGBToColor(20, 22, 26);
    C.Rectangle(8, YRow, W - 8, YRow + 56);

    { Island swatch }
    C.Brush.Color := IslandPaletteColor(Isl.IslandId);
    C.Rectangle(16, YRow + 10, 32, YRow + 46);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(228, 236, 248);
    C.TextOut(42, YRow + 7, Format('Island #%d  (%d tris, %.2f m^2)',
      [Isl.IslandId, Isl.TriangleCount, Isl.WorldAreaM2]));
    C.Font.Color := RGBToColor(152, 208, 255);
    C.TextOut(42, YRow + 29, Format('UV (%.2f,%.2f)..(%.2f,%.2f)   TD=%.0f px/m',
      [Isl.MinUV.X, Isl.MinUV.Y, Isl.MaxUV.X, Isl.MaxUV.Y, Isl.TexelsPerMeter]));

    { Texel Density gauge relative to TargetTexelsPerMeter }
    Ratio := EnsureRange(Isl.TexelsPerMeter / Max(1.0, FActiveMesh.TargetTexelsPerMeter), 0.0, 1.5);
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(20, 22, 28);
    C.Rectangle(W - 118, YRow + 18, W - 16, YRow + 36);
    BarW := Round((Ratio / 1.5) * 100);
    if (Ratio >= 0.75) and (Ratio <= 1.25) then
      C.Brush.Color := RGBToColor(78, 228, 136)
    else
      C.Brush.Color := RGBToColor(92, 178, 255);
    C.FillRect(W - 117, YRow + 19, W - 117 + BarW, YRow + 35);

    Inc(YRow, 62);
  end;
end;

procedure TUvEditorForm.BtnSpawnCrateClick(Sender: TObject);
begin
  FActiveMesh := TUvEditorHelper.SpawnUvMeshPresetInDesign(
    FDesignRoot, FDesignOwner, umpArchitecturalCrate6Islands, Vector3(0, 0, 0));
  NotifyChanged('Spawn 6-Island Crate UV Mesh');
end;

procedure TUvEditorForm.BtnSpawnColumnClick(Sender: TObject);
begin
  FActiveMesh := TUvEditorHelper.SpawnUvMeshPresetInDesign(
    FDesignRoot, FDesignOwner, umpCylindricalColumnSeamUnwrap, Vector3(3, 0, 0));
  NotifyChanged('Spawn Cylindrical Column UV Mesh');
end;

procedure TUvEditorForm.BtnSpawnOverlapDemoClick(Sender: TObject);
begin
  FActiveMesh := TUvEditorHelper.SpawnUvMeshPresetInDesign(
    FDesignRoot, FDesignOwner, umpOverlappingStackedUvRepairDemo, Vector3(-3, 0, 0));
  NotifyChanged('Spawn Overlapping UV Audit Demo');
end;

procedure TUvEditorForm.BtnUnwrapBoxClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveMesh.AutoUnwrapAndPack(upmBox6FaceTriplanar);
  NotifyChanged('Auto Box-6-Face Unwrap & Shelf Pack UVs');
end;

procedure TUvEditorForm.BtnUnwrapCylClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveMesh.AutoUnwrapAndPack(upmCylindricalSeam);
  NotifyChanged('Auto Cylindrical Seam Unwrap & Pack UVs');
end;

procedure TUvEditorForm.BtnConformalRelaxClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveMesh.AutoUnwrapAndPack(upmConformalSeamRelax);
  NotifyChanged('Conformal Seam Relax & Pack UVs');
end;

procedure TUvEditorForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Text;
end;

end.
