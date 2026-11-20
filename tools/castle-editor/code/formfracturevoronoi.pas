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

{ Visual Studio dialog for Milestone Phase 400: Voronoi Fracture Cell Cutter,
  Bond Graph & BFS Ground-Support Collapse Studio. }
unit FormFractureVoronoi;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleFractureVoronoi, ToolFractureVoronoi;

type
  TFractureVoronoiModifiedCallback = procedure(const UndoComment: String) of object;
  TFractureVoronoiRefreshCallback = procedure of object;

  TFractureVoronoiForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TFractureVoronoiModifiedCallback;
    FOnRefresh: TFractureVoronoiRefreshCallback;
    FLblSummary: TLabel;
    FPaintCells: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnWallClick(Sender: TObject);
    procedure BtnBreachWaistClick(Sender: TObject);
    procedure BtnStepCollapseClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintVoronoiWall(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TFractureVoronoiModifiedCallback;
      const AOnRefresh: TFractureVoronoiRefreshCallback);
  end;

implementation

constructor TFractureVoronoiForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TFractureVoronoiModifiedCallback;
  const AOnRefresh: TFractureVoronoiRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Voronoi Destruction Fracture & BFS Ground-Connectivity Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TFractureVoronoiForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnBreach, BtnFall, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 8, 195, 30);
  BtnSpawn.Caption := '+ Spawn Voronoi Masonry Wall';
  BtnSpawn.OnClick := @BtnSpawnWallClick;

  BtnBreach := TButton.Create(Self);
  BtnBreach.Parent := PnlButtons;
  BtnBreach.SetBounds(211, 8, 195, 30);
  BtnBreach.Caption := 'Shatter Waist Band (Cannon)';
  BtnBreach.OnClick := @BtnBreachWaistClick;

  BtnFall := TButton.Create(Self);
  BtnFall.Parent := PnlButtons;
  BtnFall.SetBounds(412, 8, 185, 30);
  BtnFall.Caption := 'Step Gravity Collapse (+0.4s)';
  BtnFall.OnClick := @BtnStepCollapseClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintCells := TPaintBox.Create(Self);
  FPaintCells.Parent := Self;
  FPaintCells.Align := alTop;
  FPaintCells.Height := 210;
  FPaintCells.OnPaint := @PaintVoronoiWall;

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

procedure TFractureVoronoiForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TFractureVoronoiForm.RefreshView;
var
  V: TCastleVoronoiFractureVolume;
begin
  V := TFractureVoronoiHelper.FindFirstVolume(FDesignRoot);
  if V = nil then
    FLblSummary.Caption := 'No TCastleVoronoiFractureVolume in scene. Click "+ Spawn Voronoi Masonry Wall".'
  else
    FLblSummary.Caption := V.FractureSummaryBadge;
  FMemoReport.Lines.Text := TFractureVoronoiHelper.GenerateMarkdownReport(V);
  FPaintCells.Invalidate;
end;

procedure TFractureVoronoiForm.BtnSpawnWallClick(Sender: TObject);
var
  V: TCastleVoronoiFractureVolume;
begin
  if TFractureVoronoiHelper.SpawnMasonryWallFractureDemo(FDesignRoot, FDesignOwner, V) then
    NotifyChanged('Spawn Voronoi Masonry Fracture Wall');
end;

procedure TFractureVoronoiForm.BtnBreachWaistClick(Sender: TObject);
var
  V: TCastleVoronoiFractureVolume;
begin
  V := TFractureVoronoiHelper.FindFirstVolume(FDesignRoot);
  if V = nil then Exit;
  V.ApplyImpactImpulseAtLocal(Vector3(-1.2, 1.5, 0.0), 1.8, 600.0);
  V.ApplyImpactImpulseAtLocal(Vector3( 1.2, 1.5, 0.0), 1.8, 600.0);
  NotifyChanged('Shatter Voronoi Waist Band');
end;

procedure TFractureVoronoiForm.BtnStepCollapseClick(Sender: TObject);
var
  V: TCastleVoronoiFractureVolume;
begin
  V := TFractureVoronoiHelper.FindFirstVolume(FDesignRoot);
  if V = nil then Exit;
  V.StepDetachedCollapse(0.4);
  NotifyChanged('Step Detached Voronoi Collapse +0.4s');
end;

procedure TFractureVoronoiForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TFractureVoronoiForm.PaintVoronoiWall(Sender: TObject);
var
  C: TCanvas;
  V: TCastleVoronoiFractureVolume;
  S: TVoronoiShardState;
  W, H, I, PX, PY, RX, RY: Integer;
begin
  C := FPaintCells.Canvas;
  W := Max(20, FPaintCells.Width);
  H := Max(20, FPaintCells.Height);
  C.Brush.Color := RGBToColor(16, 20, 26);
  C.FillRect(0, 0, W, H);

  V := TFractureVoronoiHelper.FindFirstVolume(FDesignRoot);
  if V = nil then Exit;

  for I := 0 to V.ActualShardCount - 1 do
  begin
    S := V.GetShardState(I);
    PX := (W div 2) + Round((S.CenterLocalPos.X + S.CollapseOffsetLocal.X) * 65.0);
    PY := (H - 18) - Round((S.CenterLocalPos.Y + S.CollapseOffsetLocal.Y) * 44.0);
    RX := Max(8, Round(S.ApproxSize.X * 28.0));
    RY := Max(6, Round(S.ApproxSize.Y * 20.0));
    if S.IsDetachedFalling then
      C.Brush.Color := RGBToColor(230, 72, 65)
    else if S.IsGroundAnchored then
      C.Brush.Color := RGBToColor(68, 205, 130)
    else
      C.Brush.Color := RGBToColor(120, 145, 175);
    C.Rectangle(PX - RX, PY - RY, PX + RX, PY + RY);
  end;
end;

end.
