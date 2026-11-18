{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Visual Studio dialog for Chaos Flesh Tetrahedral Volume-XPBD Soft-Body (Phase 354). }
unit FormTetSoftBody;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleTetSoftBody, ToolTetSoftBody;

type
  TTetSoftBodyModifiedCallback = procedure(const UndoComment: String) of object;
  TTetSoftBodyRefreshCallback = procedure of object;

  TTetSoftBodyForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TTetSoftBodyModifiedCallback;
    FOnRefresh: TTetSoftBodyRefreshCallback;
    FPaintLattice: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveBody: TCastleTetSoftBody;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnPresetRubberClick(Sender: TObject);
    procedure BtnPresetJelloClick(Sender: TObject);
    procedure BtnPresetPillarClick(Sender: TObject);
    procedure BtnDropBurstClick(Sender: TObject);
    procedure BtnRadialPunchClick(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintLatticeSlice(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TTetSoftBodyModifiedCallback;
      const AOnRefresh: TTetSoftBodyRefreshCallback);
  end;

implementation

constructor TTetSoftBodyForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TTetSoftBodyModifiedCallback;
  const AOnRefresh: TTetSoftBodyRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Chaos Flesh Tetrahedral Volume-Preserving XPBD Soft-Body Studio (Phase 354)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TTetSoftBodyForm.BuildUi;
var
  Lbl: TLabel;
  Row1, Row2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String; const AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Align := alLeft;
    Result.AutoSize := True;
    Result.BorderSpacing.Around := 4;
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
  end;

begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Align := alTop;
  Lbl.BorderSpacing.Around := 8;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'UE 6.0+ Chaos Flesh — 5-Tet-Per-Cell 3D Lattice, Exact Signed-Volume 6V XPBD (0 Inversions) & Radial Impact Dents';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Tetrahedral Flesh Cube', @BtnSpawnClick);
  MakeBtn(Row1, 'Preset: Rubber Cube', @BtnPresetRubberClick);
  MakeBtn(Row1, 'Preset: Gelatin Jello', @BtnPresetJelloClick);
  MakeBtn(Row1, 'Preset: Hanging Tendon', @BtnPresetPillarClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Step Gravity Drop (25 frames)', @BtnDropBurstClick);
  MakeBtn(Row2, 'Radial Hammer Slam (-14 m/s Y)', @BtnRadialPunchClick);
  MakeBtn(Row2, 'Reset Rest Lattice', @BtnResetClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintLattice := TPaintBox.Create(Self);
  FPaintLattice.Parent := BodyPanel;
  FPaintLattice.Align := alLeft;
  FPaintLattice.Width := 520;
  FPaintLattice.OnPaint := @PaintLatticeSlice;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TTetSoftBodyForm.ActiveBody: TCastleTetSoftBody;
begin
  Result := TTetSoftBodyHelper.FindSoftBodyInHierarchy(FDesignRoot);
end;

procedure TTetSoftBodyForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TTetSoftBodyForm.RefreshView;
begin
  FMemoReport.Lines.Text := TTetSoftBodyHelper.GenerateTetSoftBodyReport(ActiveBody);
  FPaintLattice.Invalidate;
end;

procedure TTetSoftBodyForm.BtnSpawnClick(Sender: TObject);
var
  B: TCastleTetSoftBody;
begin
  if TTetSoftBodyHelper.SpawnTetSoftBodyArena(FDesignRoot, FDesignOwner, B) then
    NotifyChange('Spawn Chaos Flesh Tetrahedral Soft-Body');
end;

procedure TTetSoftBodyForm.BtnPresetRubberClick(Sender: TObject);
var
  B: TCastleTetSoftBody;
begin
  B := ActiveBody;
  if B = nil then Exit;
  B.Preset := tsbpRubberBouncyCube;
  NotifyChange('Switch Tet Soft-Body to Rubber Cube');
end;

procedure TTetSoftBodyForm.BtnPresetJelloClick(Sender: TObject);
var
  B: TCastleTetSoftBody;
begin
  B := ActiveBody;
  if B = nil then Exit;
  B.Preset := tsbpGelatinJelloBlob;
  NotifyChange('Switch Tet Soft-Body to Gelatin Jello');
end;

procedure TTetSoftBodyForm.BtnPresetPillarClick(Sender: TObject);
var
  B: TCastleTetSoftBody;
begin
  B := ActiveBody;
  if B = nil then Exit;
  B.Preset := tsbpHangingFleshPillar;
  NotifyChange('Switch Tet Soft-Body to Hanging Flesh Tendon');
end;

procedure TTetSoftBodyForm.BtnDropBurstClick(Sender: TObject);
var
  B: TCastleTetSoftBody;
  I: Integer;
begin
  B := ActiveBody;
  if B = nil then Exit;
  for I := 1 to 25 do
    B.StepSimulation(1.0 / 60.0);
  NotifyChange('Step Tetrahedral Soft-Body Drop (25 frames)');
end;

procedure TTetSoftBodyForm.BtnRadialPunchClick(Sender: TObject);
var
  B: TCastleTetSoftBody;
  I: Integer;
begin
  B := ActiveBody;
  if B = nil then Exit;
  B.ApplyRadialImpactImpulse(Vector3(0.0, B.Stats.MaxVertexLocalY, 0.0), 1.8, Vector3(0.0, -14.0, 0.0));
  for I := 1 to 12 do
    B.StepSimulation(1.0 / 60.0);
  NotifyChange('Apply Radial Hammer Slam to Tetrahedral Soft-Body');
end;

procedure TTetSoftBodyForm.BtnResetClick(Sender: TObject);
var
  B: TCastleTetSoftBody;
begin
  B := ActiveBody;
  if B = nil then Exit;
  B.ResetToRestState;
  NotifyChange('Reset Tetrahedral Soft-Body Lattice');
end;

procedure TTetSoftBodyForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TTetSoftBodyHelper.GenerateTetSoftBodyReport(ActiveBody);
end;

procedure TTetSoftBodyForm.PaintLatticeSlice(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, PX, PY, FloorY: Integer;
  B: TCastleTetSoftBody;
  Pt: TVector3;
  S: TTetSoftBodyStats;
begin
  Cv := FPaintLattice.Canvas;
  W := FPaintLattice.Width;
  H := FPaintLattice.Height;
  Cv.Brush.Color := RGBToColor(22, 24, 30);
  Cv.FillRect(0, 0, W, H);

  B := ActiveBody;
  if B = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Tetrahedral Flesh Cube" to inspect XY Volumetric Deformation.');
    Exit;
  end;

  FloorY := Round(H * 0.84 - (B.FloorLocalY / 5.5) * (H * 0.68));
  Cv.Pen.Color := RGBToColor(95, 110, 130);
  Cv.Pen.Width := 2;
  Cv.Line(20, FloorY, W - 20, FloorY);

  S := B.Stats;
  Cv.Brush.Color := RGBToColor(70, 220, 175);
  for I := 0 to S.VertexCount - 1 do
  begin
    Pt := B.GetVertexPositionLocal(I);
    PX := Round(W * 0.50 + (Pt.X / 5.5) * (W * 0.68));
    PY := Round(H * 0.84 - (Pt.Y / 5.5) * (H * 0.68));
    Cv.Ellipse(PX - 4, PY - 4, PX + 4, PY + 4);
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 10, Format('XY Particle Projection | %d Tets | Vol=%.2f%% | Inverted=%d', [
    S.TetrahedronCount, S.VolumeRatioPercent, S.InvertedTetCount]));
end;

end.
