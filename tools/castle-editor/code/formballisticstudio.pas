{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Visual Studio dialog for Ballistic Trajectory, Aerodynamic Drag, Magnus Spin
  Drift & WorldRay Ricochet/Penetration Studio (Phase 387). }
unit FormBallisticStudio;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleBallisticSolver, ToolBallisticStudio;

type
  TBallisticStudioModifiedCallback = procedure(const UndoComment: String) of object;
  TBallisticStudioRefreshCallback = procedure of object;

  TBallisticStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TBallisticStudioModifiedCallback;
    FOnRefresh: TBallisticStudioRefreshCallback;
    FLblSummary: TLabel;
    FPaintArc: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnRangeClick(Sender: TObject);
    procedure BtnFirePenetrationClick(Sender: TObject);
    procedure BtnFireRicochetClick(Sender: TObject);
    procedure BtnMortarPresetClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintBallisticArc(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TBallisticStudioModifiedCallback;
      const AOnRefresh: TBallisticStudioRefreshCallback);
  end;

implementation

constructor TBallisticStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TBallisticStudioModifiedCallback;
  const AOnRefresh: TBallisticStudioRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Ballistic Trajectory, Wind Drift & Ricochet/Penetration Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 580;
  BuildUi;
  RefreshView;
end;

procedure TBallisticStudioForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnPen, BtnRic, BtnMortar, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 42;
  PnlTop.BevelOuter := bvNone;

  FLblSummary := TLabel.Create(Self);
  FLblSummary.Parent := PnlTop;
  FLblSummary.Left := 12;
  FLblSummary.Top := 12;
  FLblSummary.Caption := 'Ready.';

  PnlButtons := TPanel.Create(Self);
  PnlButtons.Parent := Self;
  PnlButtons.Align := alTop;
  PnlButtons.Height := 46;
  PnlButtons.BevelOuter := bvNone;

  BtnSpawn := TButton.Create(Self);
  BtnSpawn.Parent := PnlButtons;
  BtnSpawn.SetBounds(10, 8, 175, 30);
  BtnSpawn.Caption := '+ Spawn Firing Range';
  BtnSpawn.OnClick := @BtnSpawnRangeClick;

  BtnPen := TButton.Create(Self);
  BtnPen.Parent := PnlButtons;
  BtnPen.SetBounds(191, 8, 165, 30);
  BtnPen.Caption := 'Fire Thin-Cover Pen';
  BtnPen.OnClick := @BtnFirePenetrationClick;

  BtnRic := TButton.Create(Self);
  BtnRic.Parent := PnlButtons;
  BtnRic.SetBounds(362, 8, 155, 30);
  BtnRic.Caption := 'Fire Grazing Ricochet';
  BtnRic.OnClick := @BtnFireRicochetClick;

  BtnMortar := TButton.Create(Self);
  BtnMortar.Parent := PnlButtons;
  BtnMortar.SetBounds(523, 8, 130, 30);
  BtnMortar.Caption := 'Preset: 81mm Mortar';
  BtnMortar.OnClick := @BtnMortarPresetClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(659, 8, 108, 30);
  BtnCopy.Caption := 'Copy Report';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintArc := TPaintBox.Create(Self);
  FPaintArc.Parent := Self;
  FPaintArc.Align := alTop;
  FPaintArc.Height := 210;
  FPaintArc.OnPaint := @PaintBallisticArc;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := Self;
  BtnClose.Align := alBottom;
  BtnClose.Height := 34;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;
end;

procedure TBallisticStudioForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TBallisticStudioForm.RefreshView;
var
  L: TCastleBallisticLauncher;
begin
  L := TBallisticStudioHelper.FindFirstLauncher(FDesignRoot);
  if L = nil then
    FLblSummary.Caption := 'No TCastleBallisticLauncher in scene. Click "+ Spawn Firing Range".'
  else
    FLblSummary.Caption := L.BallisticSummaryBadge + '  Outcome=' +
      BallisticOutcomeToString(L.LastTrace.FinalOutcome);
  FMemoReport.Lines.Text := TBallisticStudioHelper.GenerateMarkdownReport(L);
  FPaintArc.Invalidate;
end;

procedure TBallisticStudioForm.BtnSpawnRangeClick(Sender: TObject);
var
  L: TCastleBallisticLauncher;
begin
  if TBallisticStudioHelper.SpawnFiringRangeDemo(FDesignRoot, FDesignOwner, L) then
    NotifyChanged('Spawn Ballistic Firing Range');
end;

procedure TBallisticStudioForm.BtnFirePenetrationClick(Sender: TObject);
var
  L: TCastleBallisticLauncher;
begin
  L := TBallisticStudioHelper.FindFirstLauncher(FDesignRoot);
  if L = nil then Exit;
  TBallisticStudioHelper.FireThinCoverPenetrationTest(L, FDesignRoot);
  NotifyChanged('Fire Thin-Cover Penetration Shot');
end;

procedure TBallisticStudioForm.BtnFireRicochetClick(Sender: TObject);
var
  L: TCastleBallisticLauncher;
begin
  L := TBallisticStudioHelper.FindFirstLauncher(FDesignRoot);
  if L = nil then Exit;
  TBallisticStudioHelper.FireGrazingRicochetTest(L, FDesignRoot);
  NotifyChanged('Fire Grazing Ricochet Shot');
end;

procedure TBallisticStudioForm.BtnMortarPresetClick(Sender: TObject);
var
  L: TCastleBallisticLauncher;
begin
  L := TBallisticStudioHelper.FindFirstLauncher(FDesignRoot);
  if L = nil then Exit;
  L.ApplyPreset(blpMortarHighArcHE);
  L.SimulateTrajectory(nil, Vector3(0.0, 1.0, 0.0),
    Vector3(0.0, 0.707, -0.707).Normalize);
  L.RebuildPreview;
  NotifyChanged('Switch to 81mm Mortar High-Arc Preset');
end;

procedure TBallisticStudioForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TBallisticStudioForm.PaintBallisticArc(Sender: TObject);
var
  C: TCanvas;
  L: TCastleBallisticLauncher;
  T: TBallisticTraceResult;
  W, H, I, PX, PY: Integer;
  MinZ, MaxZ, MinY, MaxY, ZVal, YVal: Single;
begin
  C := FPaintArc.Canvas;
  W := Max(10, FPaintArc.Width);
  H := Max(10, FPaintArc.Height);
  C.Brush.Color := RGBToColor(18, 22, 30);
  C.FillRect(0, 0, W, H);

  L := TBallisticStudioHelper.FindFirstLauncher(FDesignRoot);
  if (L = nil) or (L.LastTrace.SampleCount < 2) then
  begin
    C.Font.Color := RGBToColor(180, 195, 215);
    C.TextOut(14, H div 2 - 8, 'Ballistic Profile Canvas (spawn firing range to trace arc)');
    Exit;
  end;

  T := L.LastTrace;
  MinZ := T.Samples[0].WorldPos.Z;
  MaxZ := MinZ;
  MinY := 0.0;
  MaxY := Max(2.5, T.MaxApexY + 0.5);
  for I := 0 to T.SampleCount - 1 do
  begin
    ZVal := -T.Samples[I].WorldPos.Z;
    if I = 0 then
    begin
      MinZ := ZVal;
      MaxZ := ZVal;
    end else
    begin
      if ZVal < MinZ then MinZ := ZVal;
      if ZVal > MaxZ then MaxZ := ZVal;
    end;
    if T.Samples[I].WorldPos.Y < MinY then
      MinY := T.Samples[I].WorldPos.Y;
  end;
  if MaxZ - MinZ < 1.0 then MaxZ := MinZ + 1.0;

  C.Pen.Color := RGBToColor(255, 198, 56);
  C.Pen.Width := 2;
  for I := 0 to T.SampleCount - 1 do
  begin
    ZVal := -T.Samples[I].WorldPos.Z;
    YVal := T.Samples[I].WorldPos.Y;
    PX := 16 + Round(((ZVal - MinZ) / (MaxZ - MinZ)) * (W - 32));
    PY := (H - 18) - Round(((YVal - MinY) / Max(0.5, MaxY - MinY)) * (H - 36));
    if I = 0 then
      C.MoveTo(PX, PY)
    else
      C.LineTo(PX, PY);
    if T.Samples[I].EventKind in [bioGrazingRicochet, bioThinCoverPenetrated] then
    begin
      C.Brush.Color := RGBToColor(64, 235, 180);
      C.Ellipse(PX - 4, PY - 4, PX + 4, PY + 4);
    end;
  end;
end;

end.
