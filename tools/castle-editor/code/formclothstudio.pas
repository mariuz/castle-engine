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

{ Interactive Verlet Cloth / Cape / Banner & Catenary Rope Wind Simulation
  Studio (@link(TClothStudioForm)) featuring 1-click cloth/cape/flag/rope
  spawners, wind & solver controls, interactive simulation stepping, a live 2D
  particle-grid & catenary-sag canvas, and Markdown export (Phase 313). }
unit FormClothStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleUtils,
  CastleClothRope, ToolClothStudio;

type
  TClothStudioModifiedCallback = procedure(const AComment: String) of object;
  TClothStudioRefreshViewportCallback = procedure of object;

  TClothStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TClothStudioModifiedCallback;
    FOnRefreshViewport: TClothStudioRefreshViewportCallback;

    FReport: TClothStudioAuditReport;

    LblHeader: TLabel;
    ListBodies: TListBox;
    EditWindX: TEdit;
    EditWindZ: TEdit;
    EditSolverIters: TEdit;
    PaintProfile: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function SelectedCloth: TCastleClothSurface;
    function SelectedRope: TCastleVerletRope;
    procedure RefreshAll;
    procedure SyncInspectorFromSelection;
    procedure NotifyChanged(const AComment: String);

    procedure ListBodiesClick(Sender: TObject);
    procedure BtnSpawnBannerClick(Sender: TObject);
    procedure BtnSpawnCapeSphereClick(Sender: TObject);
    procedure BtnSpawnFlagClick(Sender: TObject);
    procedure BtnSpawnCatenaryRopeClick(Sender: TObject);
    procedure BtnStepSimClick(Sender: TObject);
    procedure BtnResetRestClick(Sender: TObject);
    procedure BtnApplyWindSolverClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintProfilePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TClothStudioModifiedCallback;
      const AOnRefreshViewport: TClothStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TClothStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TClothStudioModifiedCallback;
  const AOnRefreshViewport: TClothStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Verlet Cloth / Cape / Banner & Catenary Rope Soft-Body Wind Studio';
  Width := 1120;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TClothStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TClothStudioForm.BuildUi;
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
  PanelTop.Height := 74;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Verlet Cloth & Rope Wind Studio — Distance/Bending Solver & Sphere Repulsion';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 30, 1100, 38);
  RowTop.BevelOuter := bvNone;

  MakeBtn(RowTop, '+ Royal Banner', 4, 4, 142, @BtnSpawnBannerClick);
  MakeBtn(RowTop, '+ Hero Cape + Sphere', 152, 4, 174, @BtnSpawnCapeSphereClick);
  MakeBtn(RowTop, '+ Wind Flag on Pole', 332, 4, 162, @BtnSpawnFlagClick);
  MakeBtn(RowTop, '+ Catenary Rope', 500, 4, 152, @BtnSpawnCatenaryRopeClick);
  MakeBtn(RowTop, 'Step Cloth & Ropes (+0.1s)', 658, 4, 206, @BtnStepSimClick);
  MakeBtn(RowTop, 'Reset Rest Shape', 870, 4, 154, @BtnResetRestClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Markdown Report', 12, 6, 190, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 990, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 360;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 8, 320, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Cloth Surfaces & Verlet Ropes:';

  ListBodies := TListBox.Create(Self);
  ListBodies.Parent := PanelLeft;
  ListBodies.SetBounds(10, 28, 340, 290);
  ListBodies.OnClick := @ListBodiesClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 332, 130, 18);
  Lbl.Caption := 'Wind X (m/s):';

  EditWindX := TEdit.Create(Self);
  EditWindX.Parent := PanelLeft;
  EditWindX.SetBounds(146, 328, 204, 26);
  EditWindX.Text := '0.4';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 368, 130, 18);
  Lbl.Caption := 'Wind Z (m/s):';

  EditWindZ := TEdit.Create(Self);
  EditWindZ.Parent := PanelLeft;
  EditWindZ.SetBounds(146, 364, 204, 26);
  EditWindZ.Text := '3.2';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 404, 130, 18);
  Lbl.Caption := 'Solver Iterations:';

  EditSolverIters := TEdit.Create(Self);
  EditSolverIters.Parent := PanelLeft;
  EditSolverIters.SetBounds(146, 400, 204, 26);
  EditSolverIters.Text := '8';

  MakeBtn(PanelLeft, 'Apply Wind & Solver Iterations', 10, 440, 340, @BtnApplyWindSolverClick);

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintProfile := TPaintBox.Create(Self);
  PaintProfile.Parent := PanelCenter;
  PaintProfile.Align := alTop;
  PaintProfile.Height := 330;
  PaintProfile.OnPaint := @PaintProfilePaint;

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelCenter;
  MemoDiag.Align := alClient;
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;
  MemoDiag.Font.Name := 'Monospace';
end;

function TClothStudioForm.SelectedCloth: TCastleClothSurface;
var
  Idx: Integer;
begin
  Result := nil;
  if FReport = nil then
    Exit;
  Idx := ListBodies.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FReport.Cloths)) then
    Result := FReport.Cloths[Idx];
end;

function TClothStudioForm.SelectedRope: TCastleVerletRope;
var
  Idx, RIdx: Integer;
begin
  Result := nil;
  if FReport = nil then
    Exit;
  Idx := ListBodies.ItemIndex;
  RIdx := Idx - Length(FReport.Cloths);
  if (RIdx >= 0) and (RIdx < Length(FReport.Ropes)) then
    Result := FReport.Ropes[RIdx];
end;

procedure TClothStudioForm.RefreshAll;
var
  PrevIdx, I: Integer;
begin
  PrevIdx := ListBodies.ItemIndex;
  FreeAndNil(FReport);
  FReport := TClothStudioHelper.ScanDesign(FDesignRoot, FDesignOwner);

  ListBodies.Items.BeginUpdate;
  try
    ListBodies.Items.Clear;
    for I := 0 to High(FReport.Cloths) do
      ListBodies.Items.Add(Format('%s %s',
        [FReport.Cloths[I].Name, FReport.Cloths[I].ClothSummaryBadge]));
    for I := 0 to High(FReport.Ropes) do
      ListBodies.Items.Add(Format('%s %s',
        [FReport.Ropes[I].Name, FReport.Ropes[I].RopeSummaryBadge]));
    if ListBodies.Items.Count > 0 then
      ListBodies.ItemIndex := Clamped(Max(0, PrevIdx), 0, ListBodies.Items.Count - 1);
  finally
    ListBodies.Items.EndUpdate;
  end;

  LblHeader.Caption := Format(
    'Verlet Cloth & Rope Studio — %d Cloth(s) | %d Rope(s) | %d Particles | %d Triangles',
    [Length(FReport.Cloths), Length(FReport.Ropes),
     FReport.TotalParticles, FReport.TotalTriangles]);

  SyncInspectorFromSelection;
  MemoDiag.Lines.Text := TClothStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintProfile.Invalidate;
end;

procedure TClothStudioForm.SyncInspectorFromSelection;
var
  Cl: TCastleClothSurface;
  Rp: TCastleVerletRope;
begin
  Cl := SelectedCloth;
  if Cl <> nil then
  begin
    EditWindX.Text := FormatDot('%.1f', [Cl.WindVelocity.X]);
    EditWindZ.Text := FormatDot('%.1f', [Cl.WindVelocity.Z]);
    EditSolverIters.Text := IntToStr(Cl.SolverIterations);
    Exit;
  end;
  Rp := SelectedRope;
  if Rp <> nil then
  begin
    EditWindX.Text := FormatDot('%.1f', [Rp.WindVelocity.X]);
    EditWindZ.Text := FormatDot('%.1f', [Rp.WindVelocity.Z]);
    EditSolverIters.Text := IntToStr(Rp.SolverIterations);
  end;
end;

procedure TClothStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TClothStudioForm.ListBodiesClick(Sender: TObject);
begin
  SyncInspectorFromSelection;
  PaintProfile.Invalidate;
end;

procedure TClothStudioForm.BtnSpawnBannerClick(Sender: TObject);
begin
  TClothStudioHelper.SpawnClothInDesign(
    FDesignRoot, FDesignOwner, cpRoyalBanner, Vector3(-2.0, 3.0, 0.0), 'RoyalBanner');
  NotifyChanged('Spawn Verlet Royal Banner');
end;

procedure TClothStudioForm.BtnSpawnCapeSphereClick(Sender: TObject);
var
  Cape: TCastleClothSurface;
begin
  Cape := TClothStudioHelper.SpawnClothInDesign(
    FDesignRoot, FDesignOwner, cpHeroShoulderCape, Vector3(0.0, 2.8, 0.0), 'HeroCape');
  TClothStudioHelper.SpawnColliderSphereForCloth(
    FDesignRoot, FDesignOwner, Cape, Vector3(0.0, 1.9, -0.35), 0.55);
  Cape.StepSimulation(0.25);
  NotifyChanged('Spawn Hero Cape + Repulsion Sphere');
end;

procedure TClothStudioForm.BtnSpawnFlagClick(Sender: TObject);
var
  Flag: TCastleClothSurface;
begin
  Flag := TClothStudioHelper.SpawnClothInDesign(
    FDesignRoot, FDesignOwner, cpWindFlagOnPole, Vector3(2.0, 3.2, 0.0), 'WindFlag');
  Flag.StepSimulation(0.2);
  NotifyChanged('Spawn Wind Flag on Pole');
end;

procedure TClothStudioForm.BtnSpawnCatenaryRopeClick(Sender: TObject);
var
  Rp: TCastleVerletRope;
begin
  Rp := TClothStudioHelper.SpawnVerletRopeInDesign(
    FDesignRoot, FDesignOwner, rpmBothEndsCatenary,
    Vector3(-2.5, 3.0, -2.0), Vector3(5.0, 0.0, 0.0), 6.2, 'CatenaryRope');
  Rp.StepSimulation(0.5);
  NotifyChanged('Spawn Catenary Verlet Rope');
end;

procedure TClothStudioForm.BtnStepSimClick(Sender: TObject);
begin
  TClothStudioHelper.StepAllClothAndRopes(FDesignRoot, FDesignOwner, 0.10);
  NotifyChanged('Step Verlet Cloth & Rope Simulation (+0.1s)');
end;

procedure TClothStudioForm.BtnResetRestClick(Sender: TObject);
begin
  TClothStudioHelper.ResetAllClothAndRopes(FDesignRoot, FDesignOwner);
  NotifyChanged('Reset Verlet Cloth & Rope Rest Shapes');
end;

procedure TClothStudioForm.BtnApplyWindSolverClick(Sender: TObject);
var
  Cl: TCastleClothSurface;
  Rp: TCastleVerletRope;
  WX, WZ: Single;
  Iters: Integer;
begin
  Cl := SelectedCloth;
  if Cl <> nil then
  begin
    WX := StrToFloatDefDot(Trim(EditWindX.Text), Cl.WindVelocity.X);
    WZ := StrToFloatDefDot(Trim(EditWindZ.Text), Cl.WindVelocity.Z);
    Iters := StrToIntDef(Trim(EditSolverIters.Text), Cl.SolverIterations);
    Cl.WindVelocity := Vector3(WX, Cl.WindVelocity.Y, WZ);
    Cl.SolverIterations := Iters;
    NotifyChanged('Update Cloth Wind & Solver Iterations');
    Exit;
  end;

  Rp := SelectedRope;
  if Rp <> nil then
  begin
    WX := StrToFloatDefDot(Trim(EditWindX.Text), Rp.WindVelocity.X);
    WZ := StrToFloatDefDot(Trim(EditWindZ.Text), Rp.WindVelocity.Z);
    Iters := StrToIntDef(Trim(EditSolverIters.Text), Rp.SolverIterations);
    Rp.WindVelocity := Vector3(WX, Rp.WindVelocity.Y, WZ);
    Rp.SolverIterations := Iters;
    NotifyChanged('Update Rope Wind & Solver Iterations');
  end;
end;

procedure TClothStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TClothStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TClothStudioForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TClothStudioForm.PaintProfilePaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, OX, OY, C, R, I, X0, Y0, X1, Y1: Integer;
  ScalePx: Single;
  Cl: TCastleClothSurface;
  Rp: TCastleVerletRope;
  P0, P1: TVector3;
begin
  Cv := PaintProfile.Canvas;
  W := PaintProfile.Width;
  H := PaintProfile.Height;

  Cv.Brush.Color := RGBToColor(18, 22, 30);
  Cv.FillRect(0, 0, W, H);

  OX := W div 2;
  OY := 58;
  ScalePx := 95.0;

  Cl := SelectedCloth;
  if Cl <> nil then
  begin
    Cv.Font.Color := RGBToColor(220, 232, 248);
    Cv.Brush.Style := bsClear;
    Cv.TextOut(16, 12, Format('Cloth Particle Grid Projection: %s (%dx%d | Stretch %.3fx)',
      [Cl.Name, Cl.Cols, Cl.Rows, Cl.MaxStretchRatio]));

    Cv.Pen.Color := RGBToColor(86, 178, 245);
    for R := 0 to Cl.Rows - 1 do
      for C := 0 to Cl.Cols - 1 do
      begin
        P0 := Cl.GetParticleLocalPos(C, R);
        X0 := OX + Round((P0.X + P0.Z * 0.45) * ScalePx);
        Y0 := OY - Round(P0.Y * ScalePx);

        if C + 1 < Cl.Cols then
        begin
          P1 := Cl.GetParticleLocalPos(C + 1, R);
          X1 := OX + Round((P1.X + P1.Z * 0.45) * ScalePx);
          Y1 := OY - Round(P1.Y * ScalePx);
          Cv.Line(X0, Y0, X1, Y1);
        end;
        if R + 1 < Cl.Rows then
        begin
          P1 := Cl.GetParticleLocalPos(C, R + 1);
          X1 := OX + Round((P1.X + P1.Z * 0.45) * ScalePx);
          Y1 := OY - Round(P1.Y * ScalePx);
          Cv.Line(X0, Y0, X1, Y1);
        end;

        if Cl.IsParticlePinned(C, R) then
        begin
          Cv.Brush.Style := bsSolid;
          Cv.Brush.Color := RGBToColor(250, 198, 72);
          Cv.Ellipse(X0 - 4, Y0 - 4, X0 + 4, Y0 + 4);
        end;
      end;
    Exit;
  end;

  Rp := SelectedRope;
  if Rp <> nil then
  begin
    Cv.Font.Color := RGBToColor(220, 232, 248);
    Cv.Brush.Style := bsClear;
    Cv.TextOut(16, 12, Format('Verlet Rope Catenary Profile: %s (%d segs | Lowest Sag Y = %.2fm)',
      [Rp.Name, Rp.SegmentCount, Rp.LowestSagLocalY]));

    OX := (W div 2) - 180;
    ScalePx := 72.0;
    Cv.Pen.Color := RGBToColor(235, 178, 92);
    Cv.Pen.Width := 2;
    for I := 0 to Rp.NodeCount - 2 do
    begin
      P0 := Rp.GetNodeLocalPos(I);
      P1 := Rp.GetNodeLocalPos(I + 1);
      X0 := OX + Round(P0.X * ScalePx);
      Y0 := OY - Round(P0.Y * ScalePx);
      X1 := OX + Round(P1.X * ScalePx);
      Y1 := OY - Round(P1.Y * ScalePx);
      Cv.Line(X0, Y0, X1, Y1);
    end;
    Cv.Pen.Width := 1;
  end;
end;

end.
