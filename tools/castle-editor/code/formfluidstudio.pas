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

{ 2.5D Shallow-Water Virtual-Pipe Fluid Simulation, Waterfall/Dam-Break Presets,
  Terrain Raycast Baker & Foam/Wetness Heatmap Studio Dialog
  (@link(TFluidStudioForm))
  (Phase 330 — UE 6.0+ Niagara Grid2D Shallow Water & Water 2.0 Parity). }
unit FormFluidStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleShallowFluid, ToolFluidStudio;

type
  TFluidStudioModifyCallback = procedure(const AUndoComment: String) of object;
  TFluidStudioRefreshCallback = procedure of object;

  TFluidStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModify: TFluidStudioModifyCallback;
    FOnRefresh: TFluidStudioRefreshCallback;

    FFluids: TShallowFluidArray;

    LblHeader: TLabel;
    ListFluids: TListBox;
    LblDetails: TLabel;
    PaintFluidMap: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromDesign;
    function SelectedFluid: TCastleShallowFluidSurface;
    procedure NotifyModified(const AComment: String);

    procedure ListFluidsClick(Sender: TObject);
    procedure BtnSpawnWaterfallClick(Sender: TObject);
    procedure BtnPresetDamBreakClick(Sender: TObject);
    procedure BtnPresetCanyonClick(Sender: TObject);
    procedure BtnRainBurstClick(Sender: TObject);
    procedure BtnBakeTerrainClick(Sender: TObject);
    procedure BtnStep100msClick(Sender: TObject);
    procedure BtnBurst1sClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintFluidMapPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModify: TFluidStudioModifyCallback;
      const AOnRefresh: TFluidStudioRefreshCallback);
  end;

implementation

constructor TFluidStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModify: TFluidStudioModifyCallback;
  const AOnRefresh: TFluidStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModify := AOnModify;
  FOnRefresh := AOnRefresh;

  Caption := 'Castle Game Engine — 2.5D Shallow-Water Fluid, Waterfall & Foam Studio';
  Width := 1180;
  Height := 730;
  Position := poMainFormCenter;

  BuildUi;
  RefreshFromDesign;
end;

procedure TFluidStudioForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModify) then
    FOnModify(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TFluidStudioForm.BuildUi;
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
  LblHeader.Caption := '2.5D Shallow-Water Virtual-Pipe Fluid Studio — Mass-Conserving Waterfalls, Springs, Dam-Break Waves & Velocity Foam';

  MakeBtn(PanelTop, '+ Spawn Terraced Waterfall', 12, 34, 206, @BtnSpawnWaterfallClick);
  MakeBtn(PanelTop, 'Preset: Dam-Break', 224, 34, 144, @BtnPresetDamBreakClick);
  MakeBtn(PanelTop, 'Preset: Canyon Rapids', 374, 34, 158, @BtnPresetCanyonClick);
  MakeBtn(PanelTop, 'Rainburst (+0.20m)', 538, 34, 148, @BtnRainBurstClick);
  MakeBtn(PanelTop, 'Bake Bed From World', 692, 34, 156, @BtnBakeTerrainClick);
  MakeBtn(PanelTop, 'Step +0.10s', 854, 34, 114, @BtnStep100msClick);
  MakeBtn(PanelTop, 'Burst +1.0s (10x)', 974, 34, 148, @BtnBurst1sClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Fluid Report Markdown', 12, 6, 214, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 1050, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 420;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 6, 380, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := '2.5D Shallow-Water Surfaces:';

  ListFluids := TListBox.Create(Self);
  ListFluids.Parent := PanelLeft;
  ListFluids.SetBounds(12, 26, 396, 240);
  ListFluids.OnClick := @ListFluidsClick;

  LblDetails := TLabel.Create(Self);
  LblDetails.Parent := PanelLeft;
  LblDetails.SetBounds(12, 276, 396, 130);
  LblDetails.WordWrap := True;
  LblDetails.Caption := '';

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintFluidMap := TPaintBox.Create(Self);
  PaintFluidMap.Parent := PanelCenter;
  PaintFluidMap.Align := alTop;
  PaintFluidMap.Height := 300;
  PaintFluidMap.OnPaint := @PaintFluidMapPaint;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := PanelCenter;
  MemoReport.Align := alClient;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssAutoBoth;
  MemoReport.Font.Name := 'Monospace';
end;

function TFluidStudioForm.SelectedFluid: TCastleShallowFluidSurface;
var
  Idx: Integer;
begin
  Idx := ListFluids.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FFluids)) then
    Result := FFluids[Idx]
  else if Length(FFluids) > 0 then
    Result := FFluids[0]
  else
    Result := nil;
end;

procedure TFluidStudioForm.RefreshFromDesign;
var
  I, PrevIdx: Integer;
  F: TCastleShallowFluidSurface;
begin
  PrevIdx := ListFluids.ItemIndex;
  TFluidStudioHelper.ScanFluids(FDesignRoot, FDesignOwner, FFluids);

  ListFluids.Items.BeginUpdate;
  try
    ListFluids.Items.Clear;
    for I := 0 to High(FFluids) do
      ListFluids.Items.Add(Format('%s  %s',
        [FFluids[I].Name, FFluids[I].FluidSummaryBadge]));
    if ListFluids.Items.Count > 0 then
      ListFluids.ItemIndex := Clamped(Max(0, PrevIdx), 0, ListFluids.Items.Count - 1);
  finally
    ListFluids.Items.EndUpdate;
  end;

  F := SelectedFluid;
  if F <> nil then
    LblDetails.Caption := Format(
      'Preset: %s  |  Grid: %dx%d (%.2fm cells)' + LineEnding +
      'Water Volume: %.2f m^3  |  Wet Cells: %d  |  Springs: %d' + LineEnding +
      'Peak Flow Speed: %.2f m/s  |  Peak Foam: %.0f%%',
      [TCastleShallowFluidSurface.PresetDisplayName(F.Preset),
       F.GridResX, F.GridResZ, F.CellSize,
       F.TotalWaterVolumeM3, F.WetCellCount, F.SpringCount,
       F.MaxFlowSpeedMps, F.MaxFoamFactor * 100.0])
  else
    LblDetails.Caption := 'Click "+ Spawn Terraced Waterfall" to create a 2.5D Shallow-Water grid.';

  MemoReport.Lines.Text := TFluidStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintFluidMap.Invalidate;
end;

procedure TFluidStudioForm.ListFluidsClick(Sender: TObject);
begin
  RefreshFromDesign;
end;

procedure TFluidStudioForm.BtnSpawnWaterfallClick(Sender: TObject);
begin
  TFluidStudioHelper.SpawnShallowFluidDemo(
    FDesignRoot, FDesignOwner, sfpTerracedWaterfallPools);
  NotifyModified('Spawn Terraced Waterfall Shallow-Water Surface');
  RefreshFromDesign;
end;

procedure TFluidStudioForm.BtnPresetDamBreakClick(Sender: TObject);
var
  F: TCastleShallowFluidSurface;
begin
  F := SelectedFluid;
  if F = nil then Exit;
  F.ApplyPreset(sfpCraterLakeDamBreak);
  NotifyModified('Apply Dam-Break Shallow-Water Preset');
  RefreshFromDesign;
end;

procedure TFluidStudioForm.BtnPresetCanyonClick(Sender: TObject);
var
  F: TCastleShallowFluidSurface;
begin
  F := SelectedFluid;
  if F = nil then Exit;
  F.ApplyPreset(sfpCanyonRiverRapids);
  NotifyModified('Apply Canyon Rapids Shallow-Water Preset');
  RefreshFromDesign;
end;

procedure TFluidStudioForm.BtnRainBurstClick(Sender: TObject);
var
  F: TCastleShallowFluidSurface;
begin
  F := SelectedFluid;
  if F = nil then Exit;
  F.AddRainBurstDepth(0.20);
  NotifyModified('Add +0.20m Rainburst');
  RefreshFromDesign;
end;

procedure TFluidStudioForm.BtnBakeTerrainClick(Sender: TObject);
var
  F: TCastleShallowFluidSurface;
begin
  F := SelectedFluid;
  if F = nil then Exit;
  F.BakeTerrainBedFromWorld(25.0);
  NotifyModified('Bake Shallow-Water Bed From World Colliders');
  RefreshFromDesign;
end;

procedure TFluidStudioForm.BtnStep100msClick(Sender: TObject);
begin
  TFluidStudioHelper.StepAllFluids(FDesignRoot, FDesignOwner, 0.10);
  NotifyModified('Step Shallow-Water Fluids (+0.10s)');
  RefreshFromDesign;
end;

procedure TFluidStudioForm.BtnBurst1sClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 1 to 10 do
    TFluidStudioHelper.StepAllFluids(FDesignRoot, FDesignOwner, 0.10);
  NotifyModified('Burst Shallow-Water Fluids (+1.0s)');
  RefreshFromDesign;
end;

procedure TFluidStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := MemoReport.Lines.Text;
end;

procedure TFluidStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TFluidStudioForm.PaintFluidMapPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, CellPx, MapW, MapL, MapT, IX, IZ, RCol, GCol, BCol, CX, CY: Integer;
  F: TCastleShallowFluidSurface;
  S: TFluidCellSample;
  DepthT, FoamT: Single;
begin
  C := PaintFluidMap.Canvas;
  W := PaintFluidMap.Width;
  H := PaintFluidMap.Height;

  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  F := SelectedFluid;
  if F = nil then Exit;

  CellPx := Max(3, Min((W - 60) div Max(2, F.GridResX), (H - 44) div Max(2, F.GridResZ)));
  MapW := CellPx * F.GridResX;
  MapL := (W - MapW) div 2;
  MapT := 30;

  for IZ := 0 to F.GridResZ - 1 do
    for IX := 0 to F.GridResX - 1 do
    begin
      S := F.GetCellSample(IX, IZ);
      if S.WaterDepth > 0.005 then
      begin
        DepthT := Clamped(S.WaterDepth / 1.60, 0.15, 1.0);
        FoamT := Clamped(S.Foam, 0.0, 1.0);
        RCol := Round(Lerp(FoamT, 24.0 * (1.0 - DepthT * 0.5), 245.0));
        GCol := Round(Lerp(FoamT, 125.0 + 55.0 * (1.0 - DepthT), 252.0));
        BCol := Round(Lerp(FoamT, 185.0 + 60.0 * DepthT, 255.0));
      end else
      begin
        RCol := Clamped(Round(68 + S.TerrainHeight * 12 - S.Wetness * 26), 26, 145);
        GCol := Clamped(Round(62 + S.TerrainHeight * 11 - S.Wetness * 22), 24, 136);
        BCol := Clamped(Round(54 + S.TerrainHeight * 9 - S.Wetness * 14), 22, 125);
      end;

      C.Brush.Color := RGBToColor(RCol, GCol, BCol);
      C.FillRect(
        MapL + IX * CellPx,
        MapT + IZ * CellPx,
        MapL + (IX + 1) * CellPx,
        MapT + (IZ + 1) * CellPx);

      if ((IX and 1) = 0) and ((IZ and 1) = 0) and (Hypot(S.VelX, S.VelZ) > 0.25) then
      begin
        CX := MapL + IX * CellPx + CellPx div 2;
        CY := MapT + IZ * CellPx + CellPx div 2;
        C.Pen.Color := RGBToColor(255, 236, 140);
        C.MoveTo(CX, CY);
        C.LineTo(
          CX + Clamped(Round(S.VelX * 2.5), -CellPx, CellPx),
          CY + Clamped(Round(S.VelZ * 2.5), -CellPx, CellPx));
      end;
    end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(200, 214, 236);
  C.Font.Style := [fsBold];
  C.TextOut(16, 7, 'Top-Down 2.5D Shallow-Water Depth, Whitewater Foam, Damp Shoreline Wetness & Flow Vectors');
  C.Font.Style := [];
end;

end.
