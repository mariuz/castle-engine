{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Interactive 2D / 2.5D Bitmask Auto-Tilemap, Greedy Collider Mesher &
  Paper2D Sprite Flipbook Studio (@link(TTilemapStudioForm)) featuring an
  interactive clickable auto-tile paint grid displaying live 4-bit cardinal
  bitmasks (0..15) and cyan greedy-merged collider outlines (Phase 323). }
unit FormTilemapStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleTilemap2DPlus, ToolTilemapStudio;

type
  TTilemapStudioModifiedCallback = procedure(const AComment: String) of object;
  TTilemapStudioRefreshViewportCallback = procedure of object;

  TTilemapStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TTilemapStudioModifiedCallback;
    FOnRefreshViewport: TTilemapStudioRefreshViewportCallback;

    FMaps: TAutoTilemapArray;
    FFlipbooks: TFlipbook2DArray;
    FReport: TTilemapAuditReport;

    LblHeader: TLabel;
    ListItems: TListBox;
    PaintGrid: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function ActiveMap: TCastleAutoTilemap;
    function ActiveFb: TCastleFlipbook2D;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnPresetDungeonClick(Sender: TObject);
    procedure BtnPresetPlatformerClick(Sender: TObject);
    procedure BtnPlayAttackFlipbookClick(Sender: TObject);
    procedure BtnStepFlipbookClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintGridPaint(Sender: TObject);
    procedure PaintGridMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TTilemapStudioModifiedCallback;
      const AOnRefreshViewport: TTilemapStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TTilemapStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TTilemapStudioModifiedCallback;
  const AOnRefreshViewport: TTilemapStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := '2D / 2.5D Bitmask Auto-Tilemap, Greedy Collider & Paper2D Flipbook Studio';
  Width := 1140;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TTilemapStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TTilemapStudioForm.BuildUi;
var
  PanelTop, RowTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  BtnClose: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 72;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.SetBounds(12, 8, 1080, 20);
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Auto-Tilemaps & Flipbooks: scanning...';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 34, 1120, 32);
  RowTop.BevelOuter := bvNone;
  MakeBtn(RowTop, '+ Spawn Auto-Tile Dungeon + Flipbook', 4, 2, 245, @BtnSpawnDemoClick);
  MakeBtn(RowTop, 'Preset: Dungeon', 255, 2, 135, @BtnPresetDungeonClick);
  MakeBtn(RowTop, 'Preset: 2.5D Platformer', 396, 2, 175, @BtnPresetPlatformerClick);
  MakeBtn(RowTop, 'Play AttackSlash Clip', 577, 2, 165, @BtnPlayAttackFlipbookClick);
  MakeBtn(RowTop, 'Step Flipbook (+0.10s)', 748, 2, 170, @BtnStepFlipbookClick);
  MakeBtn(RowTop, 'Copy Markdown', 924, 2, 135, @BtnCopyMarkdownClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PanelBottom;
  BtnClose.Caption := 'Close';
  BtnClose.Width := 110;
  BtnClose.Height := 28;
  BtnClose.Top := 7;
  BtnClose.Left := Width - 130;
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.OnClick := @BtnCloseClick;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 340;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Tilemaps & Paper2D Flipbooks:';

  ListItems := TListBox.Create(Self);
  ListItems.Parent := PanelLeft;
  ListItems.SetBounds(10, 26, 320, 230);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 264, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Greedy Collider Reduction & UV Stats:';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelLeft;
  MemoDiag.SetBounds(10, 286, 320, 285);
  MemoDiag.Anchors := [akTop, akLeft, akBottom];
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintGrid := TPaintBox.Create(Self);
  PaintGrid.Parent := PanelCenter;
  PaintGrid.Align := alClient;
  PaintGrid.OnPaint := @PaintGridPaint;
  PaintGrid.OnMouseDown := @PaintGridMouseDown;
end;

function TTilemapStudioForm.ActiveMap: TCastleAutoTilemap;
begin
  if Length(FMaps) > 0 then Result := FMaps[0] else Result := nil;
end;

function TTilemapStudioForm.ActiveFb: TCastleFlipbook2D;
begin
  if Length(FFlipbooks) > 0 then Result := FFlipbooks[0] else Result := nil;
end;

procedure TTilemapStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TTilemapStudioForm.RefreshAll;
var
  I: Integer;
  M: TCastleAutoTilemap;
  Fb: TCastleFlipbook2D;
  U0, V0, U1, V1: Single;
begin
  TTilemapStudioHelper.ScanTilemapsAndFlipbooks(FDesignRoot, FDesignOwner, FMaps, FFlipbooks);
  FreeAndNil(FReport);
  FReport := TTilemapStudioHelper.AuditTilemaps(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'Auto-Tilemaps: %d (%d solid -> %d greedy boxes)  |  Flipbooks: %d  |  QA Warnings: %d',
    [FReport.TilemapCount, FReport.TotalSolidCells, FReport.TotalMergedColliders,
     FReport.FlipbookCount, FReport.Warnings.Count]);

  ListItems.Items.BeginUpdate;
  try
    ListItems.Items.Clear;
    for I := 0 to High(FMaps) do
      ListItems.Items.Add(FMaps[I].Name + '  ' + FMaps[I].TilemapSummaryBadge);
    for I := 0 to High(FFlipbooks) do
      ListItems.Items.Add(FFlipbooks[I].Name + '  ' + FFlipbooks[I].FlipbookSummaryBadge);
  finally
    ListItems.Items.EndUpdate;
  end;

  MemoDiag.Lines.BeginUpdate;
  try
    MemoDiag.Lines.Clear;
    M := ActiveMap;
    if M <> nil then
      MemoDiag.Lines.Add(Format('Greedy Meshing: %d cells -> %d boxes',
        [M.SolidCellCount, M.MergedColliderCount]));
    Fb := ActiveFb;
    if Fb <> nil then
    begin
      Fb.CurrentUvBounds(U0, V0, U1, V1);
      MemoDiag.Lines.Add(Format('Flipbook: %s  Frame=%d  UV=(%.2f,%.2f..%.2f,%.2f)',
        [Fb.ActiveClipName, Fb.CurrentAtlasFrameIndex, U0, V0, U1, V1]));
    end;
    MemoDiag.Lines.Add('');
    if FReport.Warnings.Count = 0 then
      MemoDiag.Lines.Add('[OK] All auto-tilemaps & Paper2D flipbooks healthy.')
    else
      for I := 0 to FReport.Warnings.Count - 1 do
        MemoDiag.Lines.Add('[WARN] ' + FReport.Warnings[I]);
  finally
    MemoDiag.Lines.EndUpdate;
  end;

  PaintGrid.Invalidate;
end;

procedure TTilemapStudioForm.BtnSpawnDemoClick(Sender: TObject);
var
  M: TCastleAutoTilemap;
  F: TCastleFlipbook2D;
begin
  TTilemapStudioHelper.SpawnAutoTileDungeonAndFlipbookDemo(FDesignRoot, FDesignOwner, M, F);
  NotifyChanged('Spawn Auto-Tile Dungeon + Paper2D Flipbook');
end;

procedure TTilemapStudioForm.BtnPresetDungeonClick(Sender: TObject);
var M: TCastleAutoTilemap;
begin
  M := ActiveMap; if M = nil then Exit;
  M.ApplyPreset(tmpDungeonRoomsAndCorridors);
  NotifyChanged('Apply Dungeon Auto-Tilemap Preset');
end;

procedure TTilemapStudioForm.BtnPresetPlatformerClick(Sender: TObject);
var M: TCastleAutoTilemap;
begin
  M := ActiveMap; if M = nil then Exit;
  M.ApplyPreset(tmpSideScrollerPlatformer);
  NotifyChanged('Apply 2.5D Platformer Auto-Tilemap Preset');
end;

procedure TTilemapStudioForm.BtnPlayAttackFlipbookClick(Sender: TObject);
var Fb: TCastleFlipbook2D;
begin
  Fb := ActiveFb; if Fb = nil then Exit;
  Fb.PlayClip('AttackSlash');
  NotifyChanged('Play Flipbook Clip AttackSlash');
end;

procedure TTilemapStudioForm.BtnStepFlipbookClick(Sender: TObject);
var Fb: TCastleFlipbook2D;
begin
  Fb := ActiveFb; if Fb = nil then Exit;
  Fb.StepFlipbook(0.10);
  NotifyChanged('Step Flipbook2D (+0.10s)');
end;

procedure TTilemapStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TTilemapStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TTilemapStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TTilemapStudioForm.PaintGridMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  M: TCastleAutoTilemap;
  CellPx, OriginX, OriginY, GX, GY: Integer;
begin
  M := ActiveMap;
  if M = nil then Exit;
  CellPx := Min((PaintGrid.Width - 48) div Max(1, M.GridWidth),
                (PaintGrid.Height - 72) div Max(1, M.GridHeight));
  if CellPx < 8 then Exit;
  OriginX := 24;
  OriginY := 48;
  GX := (X - OriginX) div CellPx;
  GY := (M.GridHeight - 1) - ((Y - OriginY) div CellPx);
  if (GX >= 0) and (GX < M.GridWidth) and (GY >= 0) and (GY < M.GridHeight) then
  begin
    if M.GetTile(GX, GY) = TCastleAutoTilemap.TileEmpty then
      M.SetTile(GX, GY, TCastleAutoTilemap.TileSolidWall, True)
    else
      M.SetTile(GX, GY, TCastleAutoTilemap.TileEmpty, True);
    NotifyChanged('Paint Auto-Tilemap Cell');
  end;
end;

procedure TTilemapStudioForm.PaintGridPaint(Sender: TObject);
var
  C: TCanvas;
  M: TCastleAutoTilemap;
  W, H, CellPx, OriginX, OriginY, GX, GY, Rx, Ry, I: Integer;
  Mask4: Byte;
  R: TMergedTileRect;
begin
  C := PaintGrid.Canvas;
  W := Max(200, PaintGrid.Width);
  H := Max(200, PaintGrid.Height);
  C.Brush.Color := RGBToColor(20, 24, 31);
  C.FillRect(0, 0, W, H);

  M := ActiveMap;
  if M = nil then
  begin
    C.Font.Color := RGBToColor(190, 202, 218);
    C.TextOut(24, 24, 'Click "+ Spawn Auto-Tile Dungeon + Flipbook" then click cells to paint & inspect greedy colliders.');
    Exit;
  end;

  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.TextOut(24, 14, 'Interactive Auto-Tile Grid (Click cells to toggle — Numbers = 4-Bit Mask, Cyan = Greedy Collider)');
  C.Font.Style := [];

  CellPx := Min((W - 48) div Max(1, M.GridWidth), (H - 72) div Max(1, M.GridHeight));
  OriginX := 24;
  OriginY := 48;

  for GY := 0 to M.GridHeight - 1 do
    for GX := 0 to M.GridWidth - 1 do
    begin
      Rx := OriginX + GX * CellPx;
      Ry := OriginY + (M.GridHeight - 1 - GY) * CellPx;
      if M.GetTile(GX, GY) <> TCastleAutoTilemap.TileEmpty then
      begin
        Mask4 := M.ComputeCardinalMask4Bit(GX, GY);
        C.Brush.Color := RGBToColor(54, 76, 108);
        C.Pen.Color := RGBToColor(78, 102, 138);
        C.Rectangle(Rx, Ry, Rx + CellPx, Ry + CellPx);
        C.Brush.Style := bsClear;
        C.Font.Color := RGBToColor(225, 238, 255);
        C.TextOut(Rx + 5, Ry + 4, IntToStr(Mask4));
      end else
      begin
        C.Brush.Color := RGBToColor(28, 33, 42);
        C.Pen.Color := RGBToColor(44, 52, 66);
        C.Rectangle(Rx, Ry, Rx + CellPx, Ry + CellPx);
      end;
    end;

  { Highlight greedy-merged collider rectangles in bright cyan }
  C.Brush.Style := bsClear;
  C.Pen.Color := RGBToColor(58, 232, 218);
  C.Pen.Width := 2;
  for I := 0 to M.MergedColliderCount - 1 do
  begin
    R := M.GetMergedRect(I);
    Rx := OriginX + R.StartX * CellPx;
    Ry := OriginY + (M.GridHeight - (R.StartY + R.SpanH)) * CellPx;
    C.Rectangle(Rx + 1, Ry + 1, Rx + R.SpanW * CellPx - 1, Ry + R.SpanH * CellPx - 1);
  end;
  C.Pen.Width := 1;
end;

end.
