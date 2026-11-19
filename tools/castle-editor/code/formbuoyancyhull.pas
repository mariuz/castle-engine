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

{ Visual Studio dialog for Multi-Pontoon Buoyancy Hydrostatics, Spherical-Cap
  Submergence & Wave Righting-Torque Studio (Phase 391). }
unit FormBuoyancyHull;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleBuoyancyHull, ToolBuoyancyHull;

type
  TBuoyancyHullModifiedCallback = procedure(const UndoComment: String) of object;
  TBuoyancyHullRefreshCallback = procedure of object;

  TBuoyancyHullForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TBuoyancyHullModifiedCallback;
    FOnRefresh: TBuoyancyHullRefreshCallback;
    FLblSummary: TLabel;
    FPaintCrossSection: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnRaftClick(Sender: TObject);
    procedure BtnHeelTestClick(Sender: TObject);
    procedure BtnStepWavesClick(Sender: TObject);
    procedure BtnGunboatPresetClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintCrossSection(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TBuoyancyHullModifiedCallback;
      const AOnRefresh: TBuoyancyHullRefreshCallback);
  end;

implementation

constructor TBuoyancyHullForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TBuoyancyHullModifiedCallback;
  const AOnRefresh: TBuoyancyHullRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Multi-Pontoon Buoyancy Hydrostatics & Wave Righting-Torque Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TBuoyancyHullForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnHeel, BtnStep, BtnGunboat, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn 4-Pontoon Raft';
  BtnSpawn.OnClick := @BtnSpawnRaftClick;

  BtnHeel := TButton.Create(Self);
  BtnHeel.Parent := PnlButtons;
  BtnHeel.SetBounds(191, 8, 155, 30);
  BtnHeel.Caption := 'Heel Starboard +18 deg';
  BtnHeel.OnClick := @BtnHeelTestClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlButtons;
  BtnStep.SetBounds(352, 8, 150, 30);
  BtnStep.Caption := 'Step Waves (+0.8s)';
  BtnStep.OnClick := @BtnStepWavesClick;

  BtnGunboat := TButton.Create(Self);
  BtnGunboat.Parent := PnlButtons;
  BtnGunboat.SetBounds(508, 8, 145, 30);
  BtnGunboat.Caption := 'Preset: 6-Pt Gunboat';
  BtnGunboat.OnClick := @BtnGunboatPresetClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(659, 8, 105, 30);
  BtnCopy.Caption := 'Copy Report';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintCrossSection := TPaintBox.Create(Self);
  FPaintCrossSection.Parent := Self;
  FPaintCrossSection.Align := alTop;
  FPaintCrossSection.Height := 200;
  FPaintCrossSection.OnPaint := @PaintCrossSection;

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

procedure TBuoyancyHullForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TBuoyancyHullForm.RefreshView;
var
  H: TCastleBuoyancyHull;
begin
  H := TBuoyancyHullHelper.FindFirstHull(FDesignRoot);
  if H = nil then
    FLblSummary.Caption := 'No TCastleBuoyancyHull in scene. Click "+ Spawn 4-Pontoon Raft".'
  else
    FLblSummary.Caption := H.BuoyancySummaryBadge;
  FMemoReport.Lines.Text := TBuoyancyHullHelper.GenerateMarkdownReport(H);
  FPaintCrossSection.Invalidate;
end;

procedure TBuoyancyHullForm.BtnSpawnRaftClick(Sender: TObject);
var
  H: TCastleBuoyancyHull;
begin
  if TBuoyancyHullHelper.SpawnWaterBasinRaftDemo(FDesignRoot, FDesignOwner, H) then
    NotifyChanged('Spawn 4-Pontoon Buoyancy Raft');
end;

procedure TBuoyancyHullForm.BtnHeelTestClick(Sender: TObject);
var
  H: TCastleBuoyancyHull;
begin
  H := TBuoyancyHullHelper.FindFirstHull(FDesignRoot);
  if H = nil then Exit;
  H.SetAttitudeDeg(0.0, 18.0);
  NotifyChanged('Heel Hull +18 deg Starboard');
end;

procedure TBuoyancyHullForm.BtnStepWavesClick(Sender: TObject);
var
  H: TCastleBuoyancyHull;
begin
  H := TBuoyancyHullHelper.FindFirstHull(FDesignRoot);
  if H = nil then Exit;
  H.StepHydrostaticMotion(0.8);
  NotifyChanged('Step Buoyancy Hydrostatics +0.8s');
end;

procedure TBuoyancyHullForm.BtnGunboatPresetClick(Sender: TObject);
var
  H: TCastleBuoyancyHull;
begin
  H := TBuoyancyHullHelper.FindFirstHull(FDesignRoot);
  if H = nil then Exit;
  H.ApplyPreset(bhpPatrolGunboat6Pt);
  NotifyChanged('Switch to 6-Pontoon Patrol Gunboat');
end;

procedure TBuoyancyHullForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TBuoyancyHullForm.PaintCrossSection(Sender: TObject);
var
  C: TCanvas;
  Hull: TCastleBuoyancyHull;
  Pt: TPontoonSample;
  W, H, MidY, I, PX, PY, R: Integer;
begin
  C := FPaintCrossSection.Canvas;
  W := Max(20, FPaintCrossSection.Width);
  H := Max(20, FPaintCrossSection.Height);
  MidY := H div 2;
  C.Brush.Color := RGBToColor(18, 28, 42);
  C.FillRect(0, 0, W, MidY);
  C.Brush.Color := RGBToColor(18, 66, 108);
  C.FillRect(0, MidY, W, H);

  Hull := TBuoyancyHullHelper.FindFirstHull(FDesignRoot);
  if Hull = nil then Exit;

  for I := 0 to Hull.PontoonCount - 1 do
  begin
    Pt := Hull.GetPontoonSample(I);
    PX := (W div 2) + Round(Pt.WorldPos.X * 65.0);
    PY := MidY - Round((Pt.WorldPos.Y - Pt.WaterSurfaceY) * 65.0);
    R := Max(8, Round(Pt.RadiusMeters * 28.0));
    if Pt.SubmergedFraction01 > 0.05 then
      C.Brush.Color := RGBToColor(64, 220, 255)
    else
      C.Brush.Color := RGBToColor(245, 200, 72);
    C.Ellipse(PX - R, PY - R, PX + R, PY + R);
  end;
end;

end.
