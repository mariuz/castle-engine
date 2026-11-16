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

{ 3D Voxel SDF Cave, Natural Arch Overhang & Smooth CSG Sculpting Studio Dialog
  (@link(TVoxelStudioForm))
  (Phase 329 — UE 6.0+ Nanite Voxel Caves & Volumetric Overhangs Parity). }
unit FormVoxelStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleVoxelTerrain, ToolVoxelStudio;

type
  TVoxelStudioModifyCallback = procedure(const AUndoComment: String) of object;
  TVoxelStudioRefreshCallback = procedure of object;

  TVoxelStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModify: TVoxelStudioModifyCallback;
    FOnRefresh: TVoxelStudioRefreshCallback;

    FVolumes: TVoxelVolumeArray;
    FSliceY: Single;

    LblHeader: TLabel;
    ListVolumes: TListBox;
    ListBrushes: TListBox;
    PaintSdfSlice: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromDesign;
    function SelectedVolume: TCastleVoxelVolume;
    procedure NotifyModified(const AComment: String);

    procedure ListVolumesClick(Sender: TObject);
    procedure BtnSpawnCaveClick(Sender: TObject);
    procedure BtnPresetArchClick(Sender: TObject);
    procedure BtnPresetSkyIslandClick(Sender: TObject);
    procedure BtnCarveChamberClick(Sender: TObject);
    procedure BtnAddPillarClick(Sender: TObject);
    procedure BtnToggleBrushClick(Sender: TObject);
    procedure BtnCycleSliceYClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintSdfSlicePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModify: TVoxelStudioModifyCallback;
      const AOnRefresh: TVoxelStudioRefreshCallback);
  end;

implementation

constructor TVoxelStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModify: TVoxelStudioModifyCallback;
  const AOnRefresh: TVoxelStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModify := AOnModify;
  FOnRefresh := AOnRefresh;
  FSliceY := 2.35;

  Caption := 'Castle Game Engine — 3D Voxel SDF Cave, Overhang & Marching-Tetrahedra Studio';
  Width := 1180;
  Height := 730;
  Position := poMainFormCenter;

  BuildUi;
  RefreshFromDesign;
end;

procedure TVoxelStudioForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModify) then
    FOnModify(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TVoxelStudioForm.BuildUi;
var
  PanelTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
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
  PanelTop.Height := 74;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := '3D Voxel SDF Cave & Overhang Studio — Smooth Polynomial CSG Brushes, Walkthrough Tunnels & Crack-Free Isosurface Extraction';

  MakeBtn(PanelTop, '+ Spawn Walkthrough Cave', 12, 34, 194, @BtnSpawnCaveClick);
  MakeBtn(PanelTop, 'Preset: Stone Arch', 212, 34, 146, @BtnPresetArchClick);
  MakeBtn(PanelTop, 'Preset: Sky Island', 364, 34, 144, @BtnPresetSkyIslandClick);
  MakeBtn(PanelTop, '- Carve Side Chamber', 514, 34, 158, @BtnCarveChamberClick);
  MakeBtn(PanelTop, '+ Add Rock Pillar', 678, 34, 142, @BtnAddPillarClick);
  MakeBtn(PanelTop, 'Toggle Selected Brush', 826, 34, 162, @BtnToggleBrushClick);
  MakeBtn(PanelTop, 'Step Slice Y', 994, 34, 132, @BtnCycleSliceYClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Voxel Report Markdown', 12, 6, 214, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 1050, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 430;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 6, 390, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := '3D Voxel SDF Volumes:';

  ListVolumes := TListBox.Create(Self);
  ListVolumes.Parent := PanelLeft;
  ListVolumes.SetBounds(12, 26, 404, 170);
  ListVolumes.OnClick := @ListVolumesClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 204, 390, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Ordered Non-Destructive SDF Brush Stack:';

  ListBrushes := TListBox.Create(Self);
  ListBrushes.Parent := PanelLeft;
  ListBrushes.SetBounds(12, 224, 404, 370);

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintSdfSlice := TPaintBox.Create(Self);
  PaintSdfSlice.Parent := PanelCenter;
  PaintSdfSlice.Align := alTop;
  PaintSdfSlice.Height := 300;
  PaintSdfSlice.OnPaint := @PaintSdfSlicePaint;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := PanelCenter;
  MemoReport.Align := alClient;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssAutoBoth;
  MemoReport.Font.Name := 'Monospace';
end;

function TVoxelStudioForm.SelectedVolume: TCastleVoxelVolume;
var
  Idx: Integer;
begin
  Idx := ListVolumes.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FVolumes)) then
    Result := FVolumes[Idx]
  else if Length(FVolumes) > 0 then
    Result := FVolumes[0]
  else
    Result := nil;
end;

procedure TVoxelStudioForm.RefreshFromDesign;
var
  I, PrevVol, PrevBrush: Integer;
  V: TCastleVoxelVolume;
  B: TVoxelBrushOp;
  EnTag: String;
begin
  PrevVol := ListVolumes.ItemIndex;
  PrevBrush := ListBrushes.ItemIndex;
  TVoxelStudioHelper.ScanVoxelVolumes(FDesignRoot, FDesignOwner, FVolumes);

  ListVolumes.Items.BeginUpdate;
  try
    ListVolumes.Items.Clear;
    for I := 0 to High(FVolumes) do
      ListVolumes.Items.Add(Format('%s  %s',
        [FVolumes[I].Name, FVolumes[I].VoxelSummaryBadge]));
    if ListVolumes.Items.Count > 0 then
      ListVolumes.ItemIndex := Clamped(Max(0, PrevVol), 0, ListVolumes.Items.Count - 1);
  finally
    ListVolumes.Items.EndUpdate;
  end;

  V := SelectedVolume;
  ListBrushes.Items.BeginUpdate;
  try
    ListBrushes.Items.Clear;
    if V <> nil then
    begin
      for I := 0 to V.BrushCount - 1 do
      begin
        B := V.GetBrush(I);
        if B.Enabled then EnTag := '[ON] ' else EnTag := '[OFF]';
        ListBrushes.Items.Add(Format('#%d %s %s (R=%.2fm, k=%.2f)',
          [I + 1, EnTag, TCastleVoxelVolume.BrushKindDisplayName(B.Kind),
           B.Radius, B.SmoothBlendK]));
      end;
      if ListBrushes.Items.Count > 0 then
        ListBrushes.ItemIndex := Clamped(Max(0, PrevBrush), 0, ListBrushes.Items.Count - 1);
    end;
  finally
    ListBrushes.Items.EndUpdate;
  end;

  MemoReport.Lines.Text := TVoxelStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintSdfSlice.Invalidate;
end;

procedure TVoxelStudioForm.ListVolumesClick(Sender: TObject);
begin
  RefreshFromDesign;
end;

procedure TVoxelStudioForm.BtnSpawnCaveClick(Sender: TObject);
begin
  TVoxelStudioHelper.SpawnVoxelCaveDemo(
    FDesignRoot, FDesignOwner, vvpWalkthroughCaveTunnel);
  NotifyModified('Spawn 3D Voxel Walkthrough Cave Volume');
  RefreshFromDesign;
end;

procedure TVoxelStudioForm.BtnPresetArchClick(Sender: TObject);
var
  V: TCastleVoxelVolume;
begin
  V := SelectedVolume;
  if V = nil then Exit;
  V.ApplyPreset(vvpNaturalStoneArchOverhang);
  NotifyModified('Apply Natural Stone Arch Voxel Preset');
  RefreshFromDesign;
end;

procedure TVoxelStudioForm.BtnPresetSkyIslandClick(Sender: TObject);
var
  V: TCastleVoxelVolume;
begin
  V := SelectedVolume;
  if V = nil then Exit;
  V.ApplyPreset(vvpFloatingSkyIslandPillars);
  NotifyModified('Apply Floating Sky Island Voxel Preset');
  RefreshFromDesign;
end;

procedure TVoxelStudioForm.BtnCarveChamberClick(Sender: TObject);
var
  V: TCastleVoxelVolume;
begin
  V := SelectedVolume;
  if V = nil then Exit;
  V.AddBrush(vbkCarveSphere, Vector3(3.2, 2.5, 0.0), TVector3.Zero, 2.30, 0.55, True);
  V.RebuildVoxelFieldAndMesh;
  NotifyModified('Carve Spherical Voxel Side Chamber');
  RefreshFromDesign;
end;

procedure TVoxelStudioForm.BtnAddPillarClick(Sender: TObject);
var
  V: TCastleVoxelVolume;
begin
  V := SelectedVolume;
  if V = nil then Exit;
  V.AddBrush(vbkUnionCapsule, Vector3(-1.4, 0.2, 0.0), Vector3(-1.4, 5.2, 0.0), 0.72, 0.45, True);
  V.RebuildVoxelFieldAndMesh;
  NotifyModified('Add Voxel Stalagmite Pillar');
  RefreshFromDesign;
end;

procedure TVoxelStudioForm.BtnToggleBrushClick(Sender: TObject);
var
  V: TCastleVoxelVolume;
  Idx: Integer;
begin
  V := SelectedVolume;
  Idx := ListBrushes.ItemIndex;
  if (V = nil) or (Idx < 0) or (Idx >= V.BrushCount) then Exit;
  V.SetBrushEnabled(Idx, not V.GetBrush(Idx).Enabled);
  NotifyModified('Toggle Voxel SDF Brush');
  RefreshFromDesign;
end;

procedure TVoxelStudioForm.BtnCycleSliceYClick(Sender: TObject);
begin
  FSliceY := FSliceY + 1.15;
  if FSliceY > 6.5 then
    FSliceY := 0.20;
  PaintSdfSlice.Invalidate;
end;

procedure TVoxelStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := MemoReport.Lines.Text;
end;

procedure TVoxelStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TVoxelStudioForm.PaintSdfSlicePaint(Sender: TObject);
const
  GridN = 44;
var
  C: TCanvas;
  W, H, MapSize, MapL, MapT, IX, IZ, CellPx, Shade: Integer;
  V: TCastleVoxelVolume;
  SpanX, SpanZ, WX, WZ, D: Single;
  Ext: TVector3;
begin
  C := PaintSdfSlice.Canvas;
  W := PaintSdfSlice.Width;
  H := PaintSdfSlice.Height;

  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  V := SelectedVolume;
  if V = nil then
    Exit;

  CellPx := Max(3, Min((W - 60) div GridN, (H - 46) div GridN));
  MapSize := CellPx * GridN;
  MapL := (W - MapSize) div 2;
  MapT := 30;
  Ext := V.VolumeWorldExtent;
  SpanX := Max(2.0, Ext.X);
  SpanZ := Max(2.0, Ext.Z);

  for IZ := 0 to GridN - 1 do
    for IX := 0 to GridN - 1 do
    begin
      WX := ((IX + 0.5) / GridN - 0.5) * SpanX;
      WZ := ((IZ + 0.5) / GridN - 0.5) * SpanZ;
      D := V.SampleSdfAtLocalPos(Vector3(WX, FSliceY, WZ));
      if Abs(D) < 0.28 then
        C.Brush.Color := RGBToColor(255, 214, 78) // Isosurface cave wall contour!
      else if D < 0.0 then
      begin
        Shade := Clamped(Round(120 + D * 12), 54, 130);
        C.Brush.Color := RGBToColor(Shade, Round(Shade * 0.88), Round(Shade * 0.76));
      end else
      begin
        Shade := Clamped(Round(28 + D * 4), 22, 68);
        C.Brush.Color := RGBToColor(18, Shade, Shade + 22);
      end;
      C.FillRect(
        MapL + IX * CellPx,
        MapT + IZ * CellPx,
        MapL + (IX + 1) * CellPx,
        MapT + (IZ + 1) * CellPx);
    end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(200, 214, 236);
  C.Font.Style := [fsBold];
  C.TextOut(16, 7, Format(
    'Horizontal XZ SDF Slice at Y = %.2fm  |  Brown = Solid Rock (d<0)  |  Gold = Cave Wall Isosurface (d=0)  |  Blue = Walkable Air (d>0)',
    [FSliceY]));
  C.Font.Style := [];
end;

end.
