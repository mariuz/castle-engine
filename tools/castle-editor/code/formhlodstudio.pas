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

{ Interactive World Partition Hierarchical LOD (HLOD) Spatial Cluster Baker,
  Proxy Topology Switcher & Camera Hysteresis Studio dialog (Phase 333). }
unit FormHlodStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, StrUtils,
  Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleHlodBaker, ToolHlodStudio;

type
  THlodModifyCallback = procedure(const AUndoComment: String) of object;
  THlodRefreshCallback = procedure of object;

  THlodStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: THlodModifyCallback;
    FOnRefreshViewport: THlodRefreshCallback;
    FSimCamPos: TVector3;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    ListCells: TListView;
    PaintMap: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange;
    procedure BtnSpawnDistrictClick(Sender: TObject);
    procedure BtnBakeClustersClick(Sender: TObject);
    procedure BtnCamNearClick(Sender: TObject);
    procedure BtnCamMidClick(Sender: TObject);
    procedure BtnCamFarClick(Sender: TObject);
    procedure BtnCycleProxyModeClick(Sender: TObject);
    procedure BtnRestoreFullClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintMapPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: THlodModifyCallback;
      const AOnRefreshViewport: THlodRefreshCallback);
  end;

implementation

constructor THlodStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: THlodModifyCallback;
  const AOnRefreshViewport: THlodRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FSimCamPos := Vector3(0.0, 8.0, 0.0);

  Caption := 'World Partition HLOD Spatial Cluster Baker & Draw-Call Merger Studio (UE 6.0+ HLOD Parity)';
  Width := 980;
  Height := 660;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure THlodStudioForm.BuildUi;
var
  TopBar, BodyPanel, LeftPanel, RightPanel, BtnRow1, BtnRow2: TPanel;
  Col: TListColumn;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 150): TButton;
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
  TopBar.Height := 124;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'World Partition Hierarchical LOD (HLOD) — Spatial Grid Cell Baker, Single-Draw Proxy Synthesis & Hysteresis Swapper';

  LabelTelemetry := TLabel.Create(Self);
  LabelTelemetry.Parent := TopBar;
  LabelTelemetry.Align := alTop;
  LabelTelemetry.BorderSpacing.Left := 6;
  LabelTelemetry.Caption := 'Telemetry: ready';

  BtnRow1 := TPanel.Create(Self);
  BtnRow1.Parent := TopBar;
  BtnRow1.Align := alTop;
  BtnRow1.Height := 38;
  BtnRow1.BevelOuter := bvNone;
  MakeBtn(BtnRow1, '+ Spawn 4-Block City (16)', @BtnSpawnDistrictClick, 185);
  MakeBtn(BtnRow1, 'Bake Spatial HLOD Cells', @BtnBakeClustersClick, 175);
  MakeBtn(BtnRow1, 'Cam Near (0m: Full Detail)', @BtnCamNearClick, 175);
  MakeBtn(BtnRow1, 'Cam Mid (26m: Deadband)', @BtnCamMidClick, 175);
  MakeBtn(BtnRow1, 'Cam Far (115m: All HLOD)', @BtnCamFarClick, 175);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Cycle Proxy Topology', @BtnCycleProxyModeClick, 175);
  MakeBtn(BtnRow2, 'Restore Full Detail Props', @BtnRestoreFullClick, 175);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 185);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  LeftPanel := TPanel.Create(Self);
  LeftPanel.Parent := BodyPanel;
  LeftPanel.Align := alLeft;
  LeftPanel.Width := 520;
  LeftPanel.BevelOuter := bvNone;

  ListCells := TListView.Create(Self);
  ListCells.Parent := LeftPanel;
  ListCells.Align := alClient;
  ListCells.BorderSpacing.Around := 6;
  ListCells.ViewStyle := vsReport;
  ListCells.RowSelect := True;
  ListCells.ReadOnly := True;

  Col := ListCells.Columns.Add; Col.Caption := 'Cell (X,Z)'; Col.Width := 82;
  Col := ListCells.Columns.Add; Col.Caption := 'Props'; Col.Width := 54;
  Col := ListCells.Columns.Add; Col.Caption := 'Base Tris'; Col.Width := 74;
  Col := ListCells.Columns.Add; Col.Caption := 'Proxy Tris'; Col.Width := 76;
  Col := ListCells.Columns.Add; Col.Caption := 'Cam Dist'; Col.Width := 78;
  Col := ListCells.Columns.Add; Col.Caption := 'Active Tier'; Col.Width := 135;

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := LeftPanel;
  MemoDiag.Align := alBottom;
  MemoDiag.Height := 135;
  MemoDiag.BorderSpacing.Around := 6;
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssVertical;

  RightPanel := TPanel.Create(Self);
  RightPanel.Parent := BodyPanel;
  RightPanel.Align := alClient;
  RightPanel.BevelOuter := bvLowered;
  RightPanel.BorderSpacing.Around := 6;

  PaintMap := TPaintBox.Create(Self);
  PaintMap.Parent := RightPanel;
  PaintMap.Align := alClient;
  PaintMap.OnPaint := @PaintMapPaint;
end;

procedure THlodStudioForm.NotifyChange;
begin
  if Assigned(FOnModified) then
    FOnModified('HLOD Studio Edit');
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure THlodStudioForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: THlodStudioSummary;
  Mgr: TCastleHlodClusterManager;
  I: Integer;
  C: THlodClusterCell;
  Item: TListItem;
begin
  Warnings := TStringList.Create;
  try
    Sum := THlodStudioHelper.CollectSummary(FDesignRoot, Warnings);
    Mgr := THlodStudioHelper.FindFirstManager(FDesignRoot);
    if Mgr <> nil then
      LabelTelemetry.Caption := Format(
        '%s | Mode: %s | Switch: %.0fm ± %.0fm | Draws: %d / %d (-%.0f%%) | Tris: %d / %d',
        [Mgr.Name, HlodProxyModeToDisplayName(Mgr.ProxyMode),
         Mgr.HlodSwitchDistance, Mgr.HlodHysteresisMargin,
         Sum.EffectiveDrawCalls, Sum.BaselineDrawCalls, Sum.DrawCallSavingsPercent,
         Sum.EffectiveTriangles, Sum.BaselineTriangles])
    else
      LabelTelemetry.Caption := 'No TCastleHlodClusterManager in design — click "+ Spawn 4-Block City (16)" to create & bake a demo district.';

    ListCells.Items.BeginUpdate;
    try
      ListCells.Items.Clear;
      if Mgr <> nil then
        for I := 0 to Mgr.CellCount - 1 do
        begin
          C := Mgr.GetCell(I);
          Item := ListCells.Items.Add;
          Item.Caption := Format('(%d, %d)', [C.CellX, C.CellZ]);
          Item.SubItems.Add(IntToStr(C.SourcePropCount));
          Item.SubItems.Add(IntToStr(C.SourceTrianglesEstimate));
          Item.SubItems.Add(IntToStr(C.ProxyTrianglesCount));
          Item.SubItems.Add(Format('%.1f m', [C.LastCameraDistance]));
          if C.UsingHlodProxy then
            Item.SubItems.Add('HLOD Proxy (1 Draw)')
          else
            Item.SubItems.Add('Full Detail Props');
        end;
    finally
      ListCells.Items.EndUpdate;
    end;

    MemoDiag.Lines.BeginUpdate;
    try
      MemoDiag.Lines.Clear;
      MemoDiag.Lines.Add(Format('Simulated Camera Position: (%.1f, %.1f, %.1f)', [
        FSimCamPos.X, FSimCamPos.Y, FSimCamPos.Z]));
      if Warnings.Count = 0 then
        MemoDiag.Lines.Add('Status: All spatial HLOD cells healthy with hysteresis deadband protection.')
      else
        MemoDiag.Lines.AddStrings(Warnings);
    finally
      MemoDiag.Lines.EndUpdate;
    end;
  finally
    FreeAndNil(Warnings);
  end;
  PaintMap.Invalidate;
end;

procedure THlodStudioForm.BtnSpawnDistrictClick(Sender: TObject);
var
  Mgr: TCastleHlodClusterManager;
begin
  if THlodStudioHelper.SpawnCityDistrictHlodDemo(FDesignRoot, FDesignOwner, Mgr) then
  begin
    FSimCamPos := Vector3(0.0, 8.0, 0.0);
    Mgr.EvaluateCameraDistanceSwap(FSimCamPos,
      THlodStudioHelper.ResolveRootTransform(FDesignRoot), FDesignOwner);
    NotifyChange;
  end;
end;

procedure THlodStudioForm.BtnBakeClustersClick(Sender: TObject);
var
  Mgr: TCastleHlodClusterManager;
  RootT: TCastleTransform;
begin
  RootT := THlodStudioHelper.ResolveRootTransform(FDesignRoot);
  if RootT = nil then
    Exit;
  Mgr := THlodStudioHelper.FindFirstManager(FDesignRoot);
  if Mgr = nil then
  begin
    Mgr := TCastleHlodClusterManager.Create(FDesignOwner);
    Mgr.Name := 'HlodClusterManager';
    RootT.Add(Mgr);
  end;
  Mgr.BakeClustersFromHierarchy(RootT, FDesignOwner);
  NotifyChange;
end;

procedure THlodStudioForm.BtnCamNearClick(Sender: TObject);
var
  Mgr: TCastleHlodClusterManager;
begin
  Mgr := THlodStudioHelper.FindFirstManager(FDesignRoot);
  if Mgr = nil then Exit;
  FSimCamPos := Vector3(0.0, 6.0, 0.0);
  Mgr.EvaluateCameraDistanceSwap(FSimCamPos,
    THlodStudioHelper.ResolveRootTransform(FDesignRoot), FDesignOwner);
  NotifyChange;
end;

procedure THlodStudioForm.BtnCamMidClick(Sender: TObject);
var
  Mgr: TCastleHlodClusterManager;
begin
  Mgr := THlodStudioHelper.FindFirstManager(FDesignRoot);
  if Mgr = nil then Exit;
  { Places camera near (-24,-24) cell while leaving (+24,+24) far > 50m }
  FSimCamPos := Vector3(-18.0, 6.0, -18.0);
  Mgr.EvaluateCameraDistanceSwap(FSimCamPos,
    THlodStudioHelper.ResolveRootTransform(FDesignRoot), FDesignOwner);
  NotifyChange;
end;

procedure THlodStudioForm.BtnCamFarClick(Sender: TObject);
var
  Mgr: TCastleHlodClusterManager;
begin
  Mgr := THlodStudioHelper.FindFirstManager(FDesignRoot);
  if Mgr = nil then Exit;
  FSimCamPos := Vector3(0.0, 12.0, 115.0);
  Mgr.EvaluateCameraDistanceSwap(FSimCamPos,
    THlodStudioHelper.ResolveRootTransform(FDesignRoot), FDesignOwner);
  NotifyChange;
end;

procedure THlodStudioForm.BtnCycleProxyModeClick(Sender: TObject);
var
  Mgr: TCastleHlodClusterManager;
begin
  Mgr := THlodStudioHelper.FindFirstManager(FDesignRoot);
  if Mgr = nil then Exit;
  case Mgr.ProxyMode of
    hpmClusteredBoxes: Mgr.ProxyMode := hpmMergedCellBounds;
    hpmMergedCellBounds: Mgr.ProxyMode := hpmOctagonalPrism;
    hpmOctagonalPrism: Mgr.ProxyMode := hpmClusteredBoxes;
  end;
  NotifyChange;
end;

procedure THlodStudioForm.BtnRestoreFullClick(Sender: TObject);
var
  Mgr: TCastleHlodClusterManager;
begin
  Mgr := THlodStudioHelper.FindFirstManager(FDesignRoot);
  if Mgr = nil then Exit;
  Mgr.RestoreAllFullDetailProps(THlodStudioHelper.ResolveRootTransform(FDesignRoot), FDesignOwner);
  NotifyChange;
end;

procedure THlodStudioForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'hlod_cluster_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := THlodStudioHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure THlodStudioForm.PaintMapPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, Cx, Cy, I, P, X1, Y1, X2, Y2, CamPx, CamPy, RSwitch, RInner, ROuter: Integer;
  ScalePx: Single;
  Mgr: TCastleHlodClusterManager;
  Cell: THlodClusterCell;
begin
  Cv := PaintMap.Canvas;
  W := Max(64, PaintMap.Width);
  H := Max(64, PaintMap.Height);
  Cx := W div 2;
  Cy := H div 2;
  ScalePx := Min(W, H) / 260.0;

  Cv.Brush.Color := RGBToColor(20, 24, 30);
  Cv.FillRect(0, 0, W, H);

  Cv.Pen.Color := RGBToColor(45, 52, 64);
  Cv.Line(Cx, 0, Cx, H);
  Cv.Line(0, Cy, W, Cy);

  Mgr := THlodStudioHelper.FindFirstManager(FDesignRoot);
  if Mgr <> nil then
  begin
    CamPx := Cx + Round(FSimCamPos.X * ScalePx);
    CamPy := Cy + Round(FSimCamPos.Z * ScalePx);
    RSwitch := Round(Mgr.HlodSwitchDistance * ScalePx);
    RInner := Round(Max(1.0, Mgr.HlodSwitchDistance - Mgr.HlodHysteresisMargin) * ScalePx);
    ROuter := Round((Mgr.HlodSwitchDistance + Mgr.HlodHysteresisMargin) * ScalePx);

    Cv.Brush.Style := bsClear;
    Cv.Pen.Style := psDot;
    Cv.Pen.Color := RGBToColor(90, 150, 210);
    Cv.Ellipse(CamPx - RInner, CamPy - RInner, CamPx + RInner, CamPy + RInner);
    Cv.Ellipse(CamPx - ROuter, CamPy - ROuter, CamPx + ROuter, CamPy + ROuter);
    Cv.Pen.Style := psSolid;
    Cv.Pen.Color := RGBToColor(235, 195, 70);
    Cv.Ellipse(CamPx - RSwitch, CamPy - RSwitch, CamPx + RSwitch, CamPy + RSwitch);

    for I := 0 to Mgr.CellCount - 1 do
    begin
      Cell := Mgr.GetCell(I);
      X1 := Cx + Round(Cell.WorldMin.X * ScalePx);
      Y1 := Cy + Round(Cell.WorldMin.Z * ScalePx);
      X2 := Cx + Round(Cell.WorldMax.X * ScalePx);
      Y2 := Cy + Round(Cell.WorldMax.Z * ScalePx);

      if Cell.UsingHlodProxy then
      begin
        Cv.Brush.Style := bsSolid;
        Cv.Brush.Color := RGBToColor(48, 92, 148);
        Cv.Pen.Color := RGBToColor(110, 195, 255);
      end else
      begin
        Cv.Brush.Style := bsSolid;
        Cv.Brush.Color := RGBToColor(38, 86, 56);
        Cv.Pen.Color := RGBToColor(105, 225, 140);
      end;
      Cv.Rectangle(X1, Y1, X2, Y2);

      if not Cell.UsingHlodProxy then
      begin
        Cv.Brush.Color := RGBToColor(150, 240, 175);
        for P := 0 to Cell.SourcePropCount - 1 do
          Cv.Rectangle(
            Cx + Round(Cell.Props[P].WorldMin.X * ScalePx),
            Cy + Round(Cell.Props[P].WorldMin.Z * ScalePx),
            Cx + Round(Cell.Props[P].WorldMax.X * ScalePx),
            Cy + Round(Cell.Props[P].WorldMax.Z * ScalePx));
      end;

      Cv.Brush.Style := bsClear;
      Cv.Font.Color := clWhite;
      Cv.TextOut(X1 + 4, Y1 + 4,
        IfThen(Cell.UsingHlodProxy, 'HLOD (1 Draw)', 'Full Detail'));
    end;

    Cv.Brush.Style := bsSolid;
    Cv.Brush.Color := RGBToColor(255, 215, 70);
    Cv.Pen.Color := clWhite;
    Cv.Ellipse(CamPx - 5, CamPy - 5, CamPx + 5, CamPy + 5);
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := RGBToColor(210, 220, 232);
  Cv.TextOut(10, 8, 'Top-Down Spatial XZ HLOD Grid (Green = Full Detail Props, Blue = Merged 1-Draw HLOD Proxy, Gold = Switch Ring)');
end;

end.
