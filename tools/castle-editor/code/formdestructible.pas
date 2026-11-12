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

{ Interactive Destructible Voronoi Fracture, Radial Blast Impulse & Debris
  Lifecycle Studio (@link(TDestructibleForm)) featuring 1-click Stone/Crate/
  Crystal prop spawners, live 2D Voronoi cell diagram preview, interactive
  Blast Fracture detonation, Debris Simulation stepping, and Intact Reset
  (Phase 305). }
unit FormDestructible;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Spin, Graphics, Clipbrd,
  CastleVectors, CastleUtils, CastleTransform,
  CastleDestructible, ToolDestructible;

type
  TDestructibleModifiedCallback = procedure(const AComment: String) of object;
  TDestructibleRefreshViewportCallback = procedure of object;

  TDestructibleForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FSpawnPos: TVector3;
    FOnModified: TDestructibleModifiedCallback;
    FOnRefreshViewport: TDestructibleRefreshViewportCallback;

    FSummary: TDestructibleSummary;
    FCurrentProp: TCastleDestructibleBehavior;
    FSyncingUi: Boolean;

    LblHeader: TLabel;
    CmbProps: TComboBox;
    CmbPreset: TComboBox;
    SpinShardCount: TSpinEdit;
    SpinSeed: TSpinEdit;
    SpinMaxHealth: TFloatSpinEdit;
    SpinBlastImpulse: TFloatSpinEdit;
    SpinLifetime: TFloatSpinEdit;
    PaintVoronoi: TPaintBox;
    MemoLog: TMemo;

    procedure BuildUi;
    procedure RefreshProps(const APreferred: TCastleDestructibleBehavior = nil);
    procedure SyncControls;
    procedure NotifyModified(const AComment: String);

    procedure CmbPropsChange(Sender: TObject);
    procedure PropParamsChange(Sender: TObject);
    procedure BtnSpawnStoneClick(Sender: TObject);
    procedure BtnSpawnCrateClick(Sender: TObject);
    procedure BtnSpawnCrystalClick(Sender: TObject);
    procedure BtnDetonateClick(Sender: TObject);
    procedure BtnStepDebrisClick(Sender: TObject);
    procedure BtnResetIntactClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintVoronoiPaint(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner, AInitialComponent: TComponent;
      const ASpawnWorldPos: TVector3;
      const AOnModified: TDestructibleModifiedCallback;
      const AOnRefreshViewport: TDestructibleRefreshViewportCallback);
  end;

implementation

constructor TDestructibleForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner, AInitialComponent: TComponent;
  const ASpawnWorldPos: TVector3;
  const AOnModified: TDestructibleModifiedCallback;
  const AOnRefreshViewport: TDestructibleRefreshViewportCallback);
var
  InitD: TCastleDestructibleBehavior;
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FSpawnPos := ASpawnWorldPos;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Destructible Voronoi Fracture, Radial Blast Impulse & Debris Lifecycle Studio';
  Width := 1060;
  Height := 680;
  Position := poMainFormCenter;

  BuildUi;

  InitD := nil;
  if AInitialComponent is TCastleDestructibleBehavior then
    InitD := TCastleDestructibleBehavior(AInitialComponent)
  else if AInitialComponent is TCastleTransform then
    InitD := TCastleTransform(AInitialComponent).FindBehavior(
      TCastleDestructibleBehavior) as TCastleDestructibleBehavior;

  RefreshProps(InitD);
end;

procedure TDestructibleForm.BuildUi;
var
  PnlTop, PnlBottom, PnlLeft, PnlRight: TPanel;
  BtnStone, BtnCrate, BtnCrystal, BtnDetonate, BtnStep, BtnReset, BtnReport, BtnClose: TButton;
  Lbl: TLabel;
  P: TDestructibleMaterialPreset;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 52;
  PnlTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PnlTop;
  LblHeader.Left := 14;
  LblHeader.Top := 14;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Destructible Voronoi Fracture Studio';

  BtnStone := TButton.Create(Self);
  BtnStone.Parent := PnlTop;
  BtnStone.SetBounds(455, 10, 140, 30);
  BtnStone.Caption := '+ Stone Column';
  BtnStone.OnClick := @BtnSpawnStoneClick;

  BtnCrate := TButton.Create(Self);
  BtnCrate.Parent := PnlTop;
  BtnCrate.SetBounds(602, 10, 140, 30);
  BtnCrate.Caption := '+ Wooden Crate';
  BtnCrate.OnClick := @BtnSpawnCrateClick;

  BtnCrystal := TButton.Create(Self);
  BtnCrystal.Parent := PnlTop;
  BtnCrystal.SetBounds(749, 10, 140, 30);
  BtnCrystal.Caption := '+ Crystal Spire';
  BtnCrystal.OnClick := @BtnSpawnCrystalClick;

  BtnReport := TButton.Create(Self);
  BtnReport.Parent := PnlTop;
  BtnReport.SetBounds(896, 10, 150, 30);
  BtnReport.Caption := 'Copy Markdown Report';
  BtnReport.OnClick := @BtnCopyReportClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 44;
  PnlBottom.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.SetBounds(938, 7, 110, 30);
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.Caption := 'Close';
  BtnClose.OnClick := @BtnCloseClick;

  PnlLeft := TPanel.Create(Self);
  PnlLeft.Parent := Self;
  PnlLeft.Align := alLeft;
  PnlLeft.Width := 450;
  PnlLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 10, 220, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Destructible Prop:';

  CmbProps := TComboBox.Create(Self);
  CmbProps.Parent := PnlLeft;
  CmbProps.SetBounds(14, 30, 420, 26);
  CmbProps.Style := csDropDownList;
  CmbProps.OnChange := @CmbPropsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 68, 120, 18);
  Lbl.Caption := 'Material Preset:';

  CmbPreset := TComboBox.Create(Self);
  CmbPreset.Parent := PnlLeft;
  CmbPreset.SetBounds(130, 64, 304, 26);
  CmbPreset.Style := csDropDownList;
  for P := Low(TDestructibleMaterialPreset) to High(TDestructibleMaterialPreset) do
    CmbPreset.Items.Add(DestructiblePresetDisplayName(P));
  CmbPreset.ItemIndex := 0;
  CmbPreset.OnChange := @PropParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 104, 110, 18);
  Lbl.Caption := 'Voronoi Cells:';
  SpinShardCount := TSpinEdit.Create(Self);
  SpinShardCount.Parent := PnlLeft;
  SpinShardCount.SetBounds(130, 100, 82, 26);
  SpinShardCount.MinValue := 2;
  SpinShardCount.MaxValue := 48;
  SpinShardCount.Value := 12;
  SpinShardCount.OnChange := @PropParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(226, 104, 95, 18);
  Lbl.Caption := 'Fracture Seed:';
  SpinSeed := TSpinEdit.Create(Self);
  SpinSeed.Parent := PnlLeft;
  SpinSeed.SetBounds(324, 100, 110, 26);
  SpinSeed.MinValue := 1;
  SpinSeed.MaxValue := 999999;
  SpinSeed.Value := 1337;
  SpinSeed.OnChange := @PropParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 140, 110, 18);
  Lbl.Caption := 'Max Health:';
  SpinMaxHealth := TFloatSpinEdit.Create(Self);
  SpinMaxHealth.Parent := PnlLeft;
  SpinMaxHealth.SetBounds(130, 136, 82, 26);
  SpinMaxHealth.MinValue := 1.0;
  SpinMaxHealth.MaxValue := 10000.0;
  SpinMaxHealth.Increment := 20.0;
  SpinMaxHealth.DecimalPlaces := 0;
  SpinMaxHealth.OnChange := @PropParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(226, 140, 95, 18);
  Lbl.Caption := 'Blast (m/s):';
  SpinBlastImpulse := TFloatSpinEdit.Create(Self);
  SpinBlastImpulse.Parent := PnlLeft;
  SpinBlastImpulse.SetBounds(324, 136, 110, 26);
  SpinBlastImpulse.MinValue := 0.0;
  SpinBlastImpulse.MaxValue := 50.0;
  SpinBlastImpulse.Increment := 0.5;
  SpinBlastImpulse.DecimalPlaces := 1;
  SpinBlastImpulse.OnChange := @PropParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 176, 110, 18);
  Lbl.Caption := 'Debris Life (s):';
  SpinLifetime := TFloatSpinEdit.Create(Self);
  SpinLifetime.Parent := PnlLeft;
  SpinLifetime.SetBounds(130, 172, 82, 26);
  SpinLifetime.MinValue := 0.5;
  SpinLifetime.MaxValue := 60.0;
  SpinLifetime.Increment := 0.5;
  SpinLifetime.DecimalPlaces := 1;
  SpinLifetime.OnChange := @PropParamsChange;

  BtnDetonate := TButton.Create(Self);
  BtnDetonate.Parent := PnlLeft;
  BtnDetonate.SetBounds(14, 212, 135, 34);
  BtnDetonate.Caption := 'Trigger Blast!';
  BtnDetonate.OnClick := @BtnDetonateClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlLeft;
  BtnStep.SetBounds(156, 212, 135, 34);
  BtnStep.Caption := 'Step Debris (+0.1s)';
  BtnStep.OnClick := @BtnStepDebrisClick;

  BtnReset := TButton.Create(Self);
  BtnReset.Parent := PnlLeft;
  BtnReset.SetBounds(298, 212, 136, 34);
  BtnReset.Caption := 'Reset Intact';
  BtnReset.OnClick := @BtnResetIntactClick;

  MemoLog := TMemo.Create(Self);
  MemoLog.Parent := PnlLeft;
  MemoLog.SetBounds(14, 258, 420, 314);
  MemoLog.Anchors := [akTop, akLeft, akBottom];
  MemoLog.ReadOnly := true;
  MemoLog.ScrollBars := ssVertical;

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alClient;
  PnlRight.BevelOuter := bvNone;

  PaintVoronoi := TPaintBox.Create(Self);
  PaintVoronoi.Parent := PnlRight;
  PaintVoronoi.Align := alClient;
  PaintVoronoi.OnPaint := @PaintVoronoiPaint;
end;

procedure TDestructibleForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TDestructibleForm.RefreshProps(const APreferred: TCastleDestructibleBehavior);
var
  I, SelIdx: Integer;
  PName: String;
begin
  FSummary := TDestructibleHelper.ScanDestructibles(FDesignRoot);
  LblHeader.Caption := Format(
    'Destructible Voronoi Studio — %d Props (%d Fractured, %d Active Debris Shards)',
    [Length(FSummary.Props), FSummary.FracturedPropCount, FSummary.ActiveDebrisShardCount]);

  CmbProps.Items.BeginUpdate;
  try
    CmbProps.Items.Clear;
    SelIdx := -1;
    for I := 0 to High(FSummary.Props) do
    begin
      if FSummary.Props[I].Parent <> nil then
        PName := FSummary.Props[I].Parent.Name
      else
        PName := '(detached)';
      CmbProps.Items.Add(Format('%s %s',
        [PName, FSummary.Props[I].DestructibleSummaryBadge]));
      if FSummary.Props[I] = APreferred then
        SelIdx := I;
    end;
    if (SelIdx < 0) and (Length(FSummary.Props) > 0) then
      SelIdx := 0;
    CmbProps.ItemIndex := SelIdx;
  finally
    CmbProps.Items.EndUpdate;
  end;

  if (SelIdx >= 0) and (SelIdx <= High(FSummary.Props)) then
    FCurrentProp := FSummary.Props[SelIdx]
  else
    FCurrentProp := nil;

  SyncControls;
  MemoLog.Lines.Text := TDestructibleHelper.BuildMarkdownReport(FDesignRoot);
  PaintVoronoi.Invalidate;
end;

procedure TDestructibleForm.SyncControls;
begin
  FSyncingUi := true;
  try
    if FCurrentProp <> nil then
    begin
      CmbPreset.ItemIndex := Ord(FCurrentProp.MaterialPreset);
      SpinShardCount.Value := FCurrentProp.ShardCount;
      SpinSeed.Value := FCurrentProp.FractureSeed;
      SpinMaxHealth.Value := FCurrentProp.MaxHealth;
      SpinBlastImpulse.Value := FCurrentProp.BlastImpulse;
      SpinLifetime.Value := FCurrentProp.DebrisLifetimeSec;
    end;
  finally
    FSyncingUi := false;
  end;
end;

procedure TDestructibleForm.CmbPropsChange(Sender: TObject);
begin
  if (CmbProps.ItemIndex >= 0) and (CmbProps.ItemIndex <= High(FSummary.Props)) then
    FCurrentProp := FSummary.Props[CmbProps.ItemIndex]
  else
    FCurrentProp := nil;
  SyncControls;
  PaintVoronoi.Invalidate;
end;

procedure TDestructibleForm.PropParamsChange(Sender: TObject);
begin
  if FSyncingUi or (FCurrentProp = nil) then
    Exit;
  FCurrentProp.MaterialPreset := TDestructibleMaterialPreset(
    Clamped(CmbPreset.ItemIndex, 0, Ord(High(TDestructibleMaterialPreset))));
  FCurrentProp.ShardCount := SpinShardCount.Value;
  FCurrentProp.FractureSeed := SpinSeed.Value;
  FCurrentProp.MaxHealth := SpinMaxHealth.Value;
  if not FCurrentProp.IsFractured then
    FCurrentProp.CurrentHealth := SpinMaxHealth.Value;
  FCurrentProp.BlastImpulse := SpinBlastImpulse.Value;
  FCurrentProp.DebrisLifetimeSec := SpinLifetime.Value;
  NotifyModified('Update Destructible Voronoi Prop');
  PaintVoronoi.Invalidate;
end;

procedure TDestructibleForm.BtnSpawnStoneClick(Sender: TObject);
var
  D: TCastleDestructibleBehavior;
begin
  D := TDestructibleHelper.CreateDestructiblePropInDesign(
    FDesignRoot, FDesignOwner, dmpStoneMasonry, FSpawnPos);
  if D <> nil then
  begin
    NotifyModified('Spawn Stone Column Destructible');
    RefreshProps(D);
  end;
end;

procedure TDestructibleForm.BtnSpawnCrateClick(Sender: TObject);
var
  D: TCastleDestructibleBehavior;
begin
  D := TDestructibleHelper.CreateDestructiblePropInDesign(
    FDesignRoot, FDesignOwner, dmpWoodenCrate, FSpawnPos + Vector3(1.6, 0.0, 0.0));
  if D <> nil then
  begin
    NotifyModified('Spawn Wooden Crate Destructible');
    RefreshProps(D);
  end;
end;

procedure TDestructibleForm.BtnSpawnCrystalClick(Sender: TObject);
var
  D: TCastleDestructibleBehavior;
begin
  D := TDestructibleHelper.CreateDestructiblePropInDesign(
    FDesignRoot, FDesignOwner, dmpCrystalGlass, FSpawnPos + Vector3(-1.6, 0.0, 0.0));
  if D <> nil then
  begin
    NotifyModified('Spawn Crystal Spire Destructible');
    RefreshProps(D);
  end;
end;

procedure TDestructibleForm.BtnDetonateClick(Sender: TObject);
var
  BlastPos: TVector3;
begin
  if (FCurrentProp <> nil) and (FCurrentProp.Parent <> nil) then
  begin
    BlastPos := FCurrentProp.Parent.WorldTranslation + Vector3(0.0, -0.35, 0.45);
    FCurrentProp.TriggerFracture(BlastPos);
    if Assigned(FOnRefreshViewport) then
      FOnRefreshViewport();
    RefreshProps(FCurrentProp);
  end;
end;

procedure TDestructibleForm.BtnStepDebrisClick(Sender: TObject);
begin
  TDestructibleHelper.StepAllDebrisInHierarchy(FDesignRoot, 0.10);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshProps(FCurrentProp);
end;

procedure TDestructibleForm.BtnResetIntactClick(Sender: TObject);
begin
  TDestructibleHelper.ResetAllDestructiblesInHierarchy(FDesignRoot);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshProps(FCurrentProp);
end;

procedure TDestructibleForm.BtnCopyReportClick(Sender: TObject);
var
  Rep: String;
begin
  Rep := TDestructibleHelper.BuildMarkdownReport(FDesignRoot);
  Clipboard.AsText := Rep;
  MemoLog.Lines.Text := Rep;
end;

procedure TDestructibleForm.PaintVoronoiPaint(Sender: TObject);
const
  GridStep = 6;
var
  C: TCanvas;
  W, H, Margin, RectX, RectY, RectW, RectH, GX, GY, BestIdx, I, SX, SY: Integer;
  Cells: TVoronoiShardCellArray;
  BoxS, SampleLocal: TVector3;
  BestDist, D: Single;
  HueR, HueG, HueB: Byte;
begin
  C := PaintVoronoi.Canvas;
  W := PaintVoronoi.Width;
  H := PaintVoronoi.Height;

  C.Brush.Color := RGBToColor(18, 21, 28);
  C.FillRect(0, 0, W, H);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(215, 228, 245);
  C.TextOut(14, 10, '2D X-Y Voronoi Fracture Cross-Section Preview (Z = 0 Slice)');

  if FCurrentProp = nil then
  begin
    C.Font.Color := RGBToColor(145, 160, 180);
    C.TextOut(18, H div 2, 'Click "+ Stone Column", "+ Wooden Crate", or "+ Crystal Spire" to preview fracture cells.');
    Exit;
  end;

  BoxS := FCurrentProp.FractureBoxSize;
  Cells := ComputeVoronoiFractureCells(
    TVector3.Zero, BoxS, FCurrentProp.ShardCount, FCurrentProp.FractureSeed, FCurrentProp.CrackGap);

  Margin := 46;
  RectW := Max(80, W - Margin * 2);
  RectH := Max(80, H - Margin * 2 - 16);
  RectX := Margin;
  RectY := Margin + 12;

  C.Brush.Style := bsSolid;
  GY := 0;
  while GY < RectH do
  begin
    GX := 0;
    while GX < RectW do
    begin
      SampleLocal := Vector3(
        ((GX + GridStep * 0.5) / RectW - 0.5) * BoxS.X,
        (0.5 - (GY + GridStep * 0.5) / RectH) * BoxS.Y,
        0.0);
      BestIdx := 0;
      BestDist := 1e30;
      for I := 0 to High(Cells) do
      begin
        D := PointsDistanceSqr(SampleLocal, Cells[I].SiteLocal);
        if D < BestDist then
        begin
          BestDist := D;
          BestIdx := I;
        end;
      end;
      HueR := 55 + ((BestIdx * 67 + 29) mod 155);
      HueG := 65 + ((BestIdx * 103 + 51) mod 145);
      HueB := 80 + ((BestIdx * 149 + 73) mod 145);
      C.Brush.Color := RGBToColor(HueR, HueG, HueB);
      C.FillRect(RectX + GX, RectY + GY,
        Min(RectX + RectW, RectX + GX + GridStep - 1),
        Min(RectY + RectH, RectY + GY + GridStep - 1));
      Inc(GX, GridStep);
    end;
    Inc(GY, GridStep);
  end;

  { Draw Voronoi seed nuclei }
  C.Brush.Color := RGBToColor(255, 225, 95);
  C.Pen.Color := RGBToColor(20, 20, 25);
  for I := 0 to High(Cells) do
  begin
    SX := RectX + Round((Cells[I].SiteLocal.X / Max(0.1, BoxS.X) + 0.5) * RectW);
    SY := RectY + Round((0.5 - Cells[I].SiteLocal.Y / Max(0.1, BoxS.Y)) * RectH);
    C.Ellipse(SX - 4, SY - 4, SX + 4, SY + 4);
  end;

  C.Brush.Style := bsClear;
  C.Pen.Color := RGBToColor(115, 145, 185);
  C.Rectangle(RectX, RectY, RectX + RectW, RectY + RectH);
end;

procedure TDestructibleForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

end.
