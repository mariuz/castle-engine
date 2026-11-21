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

{ Visual Studio dialog for Granular Rockslide, Talus Scree Cone &
  Angle-of-Repose Avalanche Studio (Phase 408). }
unit FormAvalancheSlide;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleAvalancheSlide, ToolAvalancheSlide;

type
  TAvalancheSlideModifiedCallback = procedure(const UndoComment: String) of object;
  TAvalancheSlideRefreshCallback = procedure of object;

  TAvalancheSlideForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TAvalancheSlideModifiedCallback;
    FOnRefresh: TAvalancheSlideRefreshCallback;
    FLblSummary: TLabel;
    FPaintProfile: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnBakeBermClick(Sender: TObject);
    procedure BtnStepSlideClick(Sender: TObject);
    procedure BtnWetSnowPresetClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintChuteCrossSection(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TAvalancheSlideModifiedCallback;
      const AOnRefresh: TAvalancheSlideRefreshCallback);
  end;

implementation

constructor TAvalancheSlideForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TAvalancheSlideModifiedCallback;
  const AOnRefresh: TAvalancheSlideRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Granular Rockslide, Talus Scree & Avalanche Runout Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TAvalancheSlideForm.ActiveWorldRoot: TCastleAbstractRootTransform;
var
  I: Integer;
begin
  Result := nil;
  if FDesignRoot = nil then Exit;
  if FDesignRoot is TCastleViewport then
    Exit(TCastleViewport(FDesignRoot).Items);
  for I := 0 to FDesignRoot.ComponentCount - 1 do
    if FDesignRoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(FDesignRoot.Components[I]).Items);
end;

procedure TAvalancheSlideForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnBerm, BtnStep, BtnSnow, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Chute + Berm';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnBerm := TButton.Create(Self);
  BtnBerm.Parent := PnlButtons;
  BtnBerm.SetBounds(190, 8, 145, 30);
  BtnBerm.Caption := 'Bake WorldRay Berm';
  BtnBerm.OnClick := @BtnBakeBermClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlButtons;
  BtnStep.SetBounds(340, 8, 145, 30);
  BtnStep.Caption := 'Step Slide (40 Passes)';
  BtnStep.OnClick := @BtnStepSlideClick;

  BtnSnow := TButton.Create(Self);
  BtnSnow.Parent := PnlButtons;
  BtnSnow.SetBounds(490, 8, 135, 30);
  BtnSnow.Caption := 'Wet Snow (16 deg)';
  BtnSnow.OnClick := @BtnWetSnowPresetClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(630, 8, 70, 30);
  BtnCopy.Caption := 'Copy MD';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlButtons;
  BtnClose.SetBounds(705, 8, 65, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;
  BtnClose.OnClick := nil;

  FPaintProfile := TPaintBox.Create(Self);
  FPaintProfile.Parent := Self;
  FPaintProfile.Align := alTop;
  FPaintProfile.Height := 215;
  FPaintProfile.OnPaint := @PaintChuteCrossSection;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TAvalancheSlideForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TAvalancheSlideForm.RefreshView;
var
  S: TCastleAvalancheSlide;
begin
  S := TAvalancheSlideHelper.FindFirstSlide(FDesignRoot);
  if S <> nil then
    FLblSummary.Caption := S.Name + '  ' + S.AvalancheSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleAvalancheSlide in scene — click "+ Spawn Chute + Berm".';
  FMemoReport.Lines.Text := TAvalancheSlideHelper.GenerateMarkdownReport(S);
  FPaintProfile.Invalidate;
end;

procedure TAvalancheSlideForm.BtnSpawnDemoClick(Sender: TObject);
var
  S: TCastleAvalancheSlide;
begin
  if TAvalancheSlideHelper.SpawnMountainChuteWithBermDemo(FDesignRoot, FDesignOwner, S) then
    NotifyChanged('Spawn Mountain Avalanche Chute Demo');
end;

procedure TAvalancheSlideForm.BtnBakeBermClick(Sender: TObject);
var
  S: TCastleAvalancheSlide;
begin
  S := TAvalancheSlideHelper.FindFirstSlide(FDesignRoot);
  if S = nil then Exit;
  S.BakeBedrockAndBermsFromWorld(ActiveWorldRoot);
  NotifyChanged('Bake WorldRay Avalanche Berm');
end;

procedure TAvalancheSlideForm.BtnStepSlideClick(Sender: TObject);
var
  S: TCastleAvalancheSlide;
begin
  S := TAvalancheSlideHelper.FindFirstSlide(FDesignRoot);
  if S = nil then Exit;
  S.StepAvalancheRelaxation(40);
  NotifyChanged('Step Mohr-Coulomb Avalanche Runout');
end;

procedure TAvalancheSlideForm.BtnWetSnowPresetClick(Sender: TObject);
var
  S: TCastleAvalancheSlide;
begin
  S := TAvalancheSlideHelper.FindFirstSlide(FDesignRoot);
  if S = nil then Exit;
  S.ApplyPreset(aspWetAlpineSlabAvalanche);
  S.StepAvalancheRelaxation(50);
  NotifyChanged('Switch to Wet Alpine Slab Avalanche');
end;

procedure TAvalancheSlideForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TAvalancheSlideForm.PaintChuteCrossSection(Sender: TObject);
var
  C: TCanvas;
  W, H, I, X0, X1, BaseY, BedTop, DebTop, ColW: Integer;
  S: TCastleAvalancheSlide;
  B: TAvalancheBinSample;
begin
  C := FPaintProfile.Canvas;
  W := FPaintProfile.Width;
  H := FPaintProfile.Height;
  C.Brush.Color := RGBToColor(18, 20, 26);
  C.FillRect(0, 0, W, H);

  S := TAvalancheSlideHelper.FindFirstSlide(FDesignRoot);
  if S = nil then Exit;

  BaseY := H - 30;
  ColW := Max(8, (W - 40) div AvalancheChuteBinCount);
  for I := 0 to AvalancheChuteBinCount - 1 do
  begin
    B := S.GetBinSample(I);
    X0 := 20 + I * ColW;
    X1 := X0 + ColW - 2;
    BedTop := BaseY - Round(B.BedrockElevationY * 12.0);
    DebTop := BaseY - Round(B.SurfaceElevationY * 12.0);

    C.Brush.Color := RGBToColor(75, 80, 92);
    C.FillRect(X0, BedTop, X1, BaseY);
    if B.DebrisDepthMeters > 0.01 then
    begin
      C.Brush.Color := RGBToColor(235, 175, 75);
      C.FillRect(X0, DebTop, X1, BedTop);
    end;
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(20, H - 24, Format('Slate = Bedrock/Berm | Gold = Granular Debris (Vol %.1f m^3, Runout %.1f m)',
    [S.TotalDebrisVolumeCubicMeters, S.MaxRunoutDistanceMeters]));
end;

end.
