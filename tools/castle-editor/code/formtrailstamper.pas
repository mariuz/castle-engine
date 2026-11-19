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

{ Visual Studio dialog for Interactive Snow, Mud & Sand Persistent Deformation
  Trail Stamper Studio (Phase 383). }
unit FormTrailStamper;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport, CastleTrailStamper, ToolTrailStamper;

type
  TTrailStamperModifiedCallback = procedure(const UndoComment: String) of object;
  TTrailStamperRefreshCallback = procedure of object;

  TTrailStamperForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TTrailStamperModifiedCallback;
    FOnRefresh: TTrailStamperRefreshCallback;
    FLblSummary: TLabel;
    FPaintGrid: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnSnowClick(Sender: TObject);
    procedure BtnStampCrossTrackClick(Sender: TObject);
    procedure BtnSnowfallRefillClick(Sender: TObject);
    procedure BtnMudPresetClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintDeformationHeatmap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TTrailStamperModifiedCallback;
      const AOnRefresh: TTrailStamperRefreshCallback);
  end;

implementation

constructor TTrailStamperForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TTrailStamperModifiedCallback;
  const AOnRefresh: TTrailStamperRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Interactive Snow, Mud & Sand Persistent Deformation Trail Studio';
  Width := 840;
  Height := 580;
  Position := poMainFormCenter;
  BuildUi;
  RefreshView;
end;

procedure TTrailStamperForm.BuildUi;
var
  TopBar, BtnRow: TPanel;
  BtnSpawn, BtnCross, BtnRefill, BtnMud, BtnCopy, BtnClose: TButton;
begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 40;
  TopBar.BevelOuter := bvNone;

  FLblSummary := TLabel.Create(Self);
  FLblSummary.Parent := TopBar;
  FLblSummary.Left := 12;
  FLblSummary.Top := 11;
  FLblSummary.Font.Style := [fsBold];

  BtnRow := TPanel.Create(Self);
  BtnRow.Parent := Self;
  BtnRow.Align := alTop;
  BtnRow.Height := 44;
  BtnRow.BevelOuter := bvNone;

  BtnSpawn := TButton.Create(Self);
  BtnSpawn.Parent := BtnRow;
  BtnSpawn.SetBounds(10, 6, 185, 30);
  BtnSpawn.Caption := '+ Spawn Alpine Snow Trail';
  BtnSpawn.OnClick := @BtnSpawnSnowClick;

  BtnCross := TButton.Create(Self);
  BtnCross.Parent := BtnRow;
  BtnCross.SetBounds(201, 6, 155, 30);
  BtnCross.Caption := 'Carve Cross Wheel Rut';
  BtnCross.OnClick := @BtnStampCrossTrackClick;

  BtnRefill := TButton.Create(Self);
  BtnRefill.Parent := BtnRow;
  BtnRefill.SetBounds(362, 6, 145, 30);
  BtnRefill.Caption := 'Snowfall Refill (+2s)';
  BtnRefill.OnClick := @BtnSnowfallRefillClick;

  BtnMud := TButton.Create(Self);
  BtnMud.Parent := BtnRow;
  BtnMud.SetBounds(513, 6, 125, 30);
  BtnMud.Caption := 'Preset: Wet Mud';
  BtnMud.OnClick := @BtnMudPresetClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := BtnRow;
  BtnCopy.SetBounds(644, 6, 105, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := BtnRow;
  BtnClose.SetBounds(755, 6, 70, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;

  FPaintGrid := TPaintBox.Create(Self);
  FPaintGrid.Parent := Self;
  FPaintGrid.Align := alTop;
  FPaintGrid.Height := 250;
  FPaintGrid.OnPaint := @PaintDeformationHeatmap;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TTrailStamperForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TTrailStamperForm.RefreshView;
var
  Sum: TTrailStamperStudioSummary;
begin
  Sum := TTrailStamperHelper.CollectSummary(FDesignRoot);
  FLblSummary.Caption := Format(
    'Stampers: %d  |  Deformed Cells: %d  |  Deepest Trough: %.3f m  |  Raised Rim Berm: +%.3f m',
    [Sum.StamperCount, Sum.TotalDeformedCells, Sum.DeepestTroughMeters, Sum.HighestBermMeters]);
  FMemoReport.Lines.Text := TTrailStamperHelper.BuildMarkdownReport(FDesignRoot);
  FPaintGrid.Invalidate;
end;

procedure TTrailStamperForm.BtnSpawnSnowClick(Sender: TObject);
var
  Stamper: TCastleTrailStamper;
begin
  if TTrailStamperHelper.SpawnAlpineSnowTrailDemo(FDesignRoot, FDesignOwner, Stamper) then
    NotifyChanged('Spawn Alpine Snow Trail Demo');
end;

procedure TTrailStamperForm.BtnStampCrossTrackClick(Sender: TObject);
var
  Stamper: TCastleTrailStamper;
begin
  Stamper := TTrailStamperHelper.FindFirstStamper(FDesignRoot);
  if Stamper <> nil then
  begin
    Stamper.StampFurrowSegmentWorld(Vector3(-7.0, 0.0, 6.0), Vector3(7.0, 0.0, -6.0), 1.20, 0.30);
    NotifyChanged('Carve Cross Wheel Rut');
  end;
end;

procedure TTrailStamperForm.BtnSnowfallRefillClick(Sender: TObject);
var
  Stamper: TCastleTrailStamper;
begin
  Stamper := TTrailStamperHelper.FindFirstStamper(FDesignRoot);
  if Stamper <> nil then
  begin
    Stamper.StepWeatherRefill(2.0);
    RefreshView;
  end;
end;

procedure TTrailStamperForm.BtnMudPresetClick(Sender: TObject);
var
  Stamper: TCastleTrailStamper;
begin
  Stamper := TTrailStamperHelper.FindFirstStamper(FDesignRoot);
  if Stamper <> nil then
  begin
    Stamper.ApplyPreset(tmpRainSoakedMud);
    NotifyChanged('Switch Trail Stamper to Rain-Soaked Mud');
  end;
end;

procedure TTrailStamperForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TTrailStamperForm.PaintDeformationHeatmap(Sender: TObject);
const
  VisRes = 32;
var
  C: TCanvas;
  Stamper: TCastleTrailStamper;
  GX, GZ, X0, Y0, X1, Y1, RCol, GCol, BCol: Integer;
  HalfSpan, WX, WZ, T: Single;
  S: TTrailStampSample;
begin
  C := FPaintGrid.Canvas;
  C.Brush.Color := $00282018;
  C.FillRect(0, 0, FPaintGrid.Width, FPaintGrid.Height);

  Stamper := TTrailStamperHelper.FindFirstStamper(FDesignRoot);
  if Stamper = nil then Exit;

  HalfSpan := Stamper.PatchSizeMeters * 0.5;
  for GZ := 0 to VisRes - 1 do
    for GX := 0 to VisRes - 1 do
    begin
      WX := Stamper.WorldTranslation.X + Lerp(GX / Single(VisRes - 1), -HalfSpan, HalfSpan);
      WZ := Stamper.WorldTranslation.Z + Lerp(GZ / Single(VisRes - 1), -HalfSpan, HalfSpan);
      S := Stamper.SampleDeformationAtWorld(Vector3(WX, 0.0, WZ));
      if S.DisplacementMeters < -0.005 then
      begin
        T := EnsureRange(-S.DisplacementMeters / Max(0.05, Stamper.MaxSinkDepthMeters), 0.0, 1.0);
        RCol := Round(Lerp(T, 210, 55));
        GCol := Round(Lerp(T, 225, 120));
        BCol := Round(Lerp(T, 240, 230));
      end else
      if S.DisplacementMeters > 0.005 then
      begin
        T := EnsureRange(S.DisplacementMeters / Max(0.02, Stamper.MaxSinkDepthMeters * 0.4), 0.0, 1.0);
        RCol := Round(Lerp(T, 220, 255));
        GCol := Round(Lerp(T, 228, 240));
        BCol := Round(Lerp(T, 238, 175));
      end else
      begin
        RCol := 215; GCol := 225; BCol := 235;
      end;
      C.Brush.Color := RGBToColor(RCol, GCol, BCol);
      X0 := (GX * FPaintGrid.Width) div VisRes;
      Y0 := (GZ * FPaintGrid.Height) div VisRes;
      X1 := ((GX + 1) * FPaintGrid.Width) div VisRes;
      Y1 := ((GZ + 1) * FPaintGrid.Height) div VisRes;
      C.FillRect(X0, Y0, X1, Y1);
    end;
end;

end.
