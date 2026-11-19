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

{ Visual Studio dialog for 2.5D Atmospheric Cloud Shadow Scroller & Crepuscular
  Light-Shaft Studio (Phase 382). }
unit FormCloudShadows;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleViewport, CastleCloudShadows, ToolCloudShadows;

type
  TCloudShadowsModifiedCallback = procedure(const UndoComment: String) of object;
  TCloudShadowsRefreshCallback = procedure of object;

  TCloudShadowsForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TCloudShadowsModifiedCallback;
    FOnRefresh: TCloudShadowsRefreshCallback;
    FLblSummary: TLabel;
    FPaintShadowMap: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnAdvectWindClick(Sender: TObject);
    procedure BtnSunsetRaysClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintGroundTransmittance(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TCloudShadowsModifiedCallback;
      const AOnRefresh: TCloudShadowsRefreshCallback);
  end;

implementation

constructor TCloudShadowsForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TCloudShadowsModifiedCallback;
  const AOnRefresh: TCloudShadowsRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := '2.5D Atmospheric Cloud Shadow Scroller & Crepuscular Light-Shaft Studio';
  Width := 820;
  Height := 580;
  Position := poMainFormCenter;
  BuildUi;
  RefreshView;
end;

procedure TCloudShadowsForm.BuildUi;
var
  TopBar, BtnRow: TPanel;
  BtnSpawn, BtnStep, BtnSunset, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 6, 215, 30);
  BtnSpawn.Caption := '+ Spawn Sunlit Valley Cloud Deck';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := BtnRow;
  BtnStep.SetBounds(233, 6, 170, 30);
  BtnStep.Caption := 'Advect Wind (+2.5s Drift)';
  BtnStep.OnClick := @BtnAdvectWindClick;

  BtnSunset := TButton.Create(Self);
  BtnSunset.Parent := BtnRow;
  BtnSunset.SetBounds(411, 6, 195, 30);
  BtnSunset.Caption := 'Preset: Sunset God-Rays (16 deg)';
  BtnSunset.OnClick := @BtnSunsetRaysClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := BtnRow;
  BtnCopy.SetBounds(614, 6, 110, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := BtnRow;
  BtnClose.SetBounds(730, 6, 76, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;

  FPaintShadowMap := TPaintBox.Create(Self);
  FPaintShadowMap.Parent := Self;
  FPaintShadowMap.Align := alTop;
  FPaintShadowMap.Height := 250;
  FPaintShadowMap.OnPaint := @PaintGroundTransmittance;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TCloudShadowsForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TCloudShadowsForm.RefreshView;
var
  Sum: TCloudShadowStudioSummary;
begin
  Sum := TCloudShadowsHelper.CollectSummary(FDesignRoot);
  FLblSummary.Caption := Format(
    'Projectors: %d  |  Coverage: %.1f%%  |  Wind: %.1f m/s  |  Shadowed Valley Area: %.1f%%',
    [Sum.ProjectorCount, Sum.AvgCoveragePct, Sum.AvgWindMps, Sum.ShadowedGridFractionPct]);
  FMemoReport.Lines.Text := TCloudShadowsHelper.BuildMarkdownReport(FDesignRoot);
  FPaintShadowMap.Invalidate;
end;

procedure TCloudShadowsForm.BtnSpawnDemoClick(Sender: TObject);
var
  Proj: TCastleCloudShadowProjector;
begin
  if TCloudShadowsHelper.SpawnValleyCloudShadowDemo(FDesignRoot, FDesignOwner, Proj) then
    NotifyChanged('Spawn Valley Cloud Shadow Demo');
end;

procedure TCloudShadowsForm.BtnAdvectWindClick(Sender: TObject);
var
  Proj: TCastleCloudShadowProjector;
begin
  Proj := TCloudShadowsHelper.FindFirstProjector(FDesignRoot);
  if Proj <> nil then
  begin
    Proj.StepWindAdvection(2.5);
    RefreshView;
  end;
end;

procedure TCloudShadowsForm.BtnSunsetRaysClick(Sender: TObject);
var
  Proj: TCastleCloudShadowProjector;
begin
  Proj := TCloudShadowsHelper.FindFirstProjector(FDesignRoot);
  if Proj <> nil then
  begin
    Proj.ApplyPreset(cspBrokenSunsetGodRays);
    NotifyChanged('Switch Cloud Shadows to Sunset God-Rays');
  end;
end;

procedure TCloudShadowsForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TCloudShadowsForm.PaintGroundTransmittance(Sender: TObject);
const
  GridCols = 32;
  GridRows = 16;
var
  C: TCanvas;
  Proj: TCastleCloudShadowProjector;
  SunDir: TVector3;
  GX, GZ, X0, Y0, X1, Y1, Lum: Integer;
  WX, WZ: Single;
  S: TCloudShadowSample;
begin
  C := FPaintShadowMap.Canvas;
  C.Brush.Color := $001A1F18;
  C.FillRect(0, 0, FPaintShadowMap.Width, FPaintShadowMap.Height);

  Proj := TCloudShadowsHelper.FindFirstProjector(FDesignRoot);
  if Proj = nil then Exit;

  SunDir := Proj.EvaluateSunDirectionToSky;
  for GZ := 0 to GridRows - 1 do
    for GX := 0 to GridCols - 1 do
    begin
      WX := ((GX / Single(GridCols - 1)) - 0.5) * 320.0;
      WZ := ((GZ / Single(GridRows - 1)) - 0.5) * 240.0;
      S := Proj.SampleGroundShadowAt(Vector3(WX, 0.0, WZ), SunDir);
      Lum := EnsureRange(Round(S.DirectSunTransmittance01 * 215.0 + 25.0), 20, 245);
      C.Brush.Color := RGBToColor(Round(Lum * 0.92), Lum, Round(Lum * 0.78));
      X0 := (GX * FPaintShadowMap.Width) div GridCols;
      Y0 := (GZ * FPaintShadowMap.Height) div GridRows;
      X1 := ((GX + 1) * FPaintShadowMap.Width) div GridCols;
      Y1 := ((GZ + 1) * FPaintShadowMap.Height) div GridRows;
      C.FillRect(X0, Y0, X1, Y1);
    end;
end;

end.
