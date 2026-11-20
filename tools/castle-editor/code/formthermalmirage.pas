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

{ Visual Studio dialog for Heat-Haze Mirage, Thermal Convection Plume &
  Underwater Caustic Refraction Field Studio (Phase 401). }
unit FormThermalMirage;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleThermalMirage, ToolThermalMirage;

type
  TThermalMirageModifiedCallback = procedure(const UndoComment: String) of object;
  TThermalMirageRefreshCallback = procedure of object;

  TThermalMirageForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TThermalMirageModifiedCallback;
    FOnRefresh: TThermalMirageRefreshCallback;
    FLblSummary: TLabel;
    FPaintField: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDesertClick(Sender: TObject);
    procedure BtnCoralCausticsClick(Sender: TObject);
    procedure BtnStepPhaseClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintRefractionMap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TThermalMirageModifiedCallback;
      const AOnRefresh: TThermalMirageRefreshCallback);
  end;

implementation

constructor TThermalMirageForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TThermalMirageModifiedCallback;
  const AOnRefresh: TThermalMirageRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Heat-Haze Mirage, Thermal Plume & Underwater Caustics Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TThermalMirageForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnReef, BtnStep, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Desert Highway Mirage';
  BtnSpawn.OnClick := @BtnSpawnDesertClick;

  BtnReef := TButton.Create(Self);
  BtnReef.Parent := PnlButtons;
  BtnReef.SetBounds(211, 8, 195, 30);
  BtnReef.Caption := 'Preset: Coral Reef Caustics';
  BtnReef.OnClick := @BtnCoralCausticsClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlButtons;
  BtnStep.SetBounds(412, 8, 185, 30);
  BtnStep.Caption := 'Step Shimmer (+0.65s)';
  BtnStep.OnClick := @BtnStepPhaseClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintField := TPaintBox.Create(Self);
  FPaintField.Parent := Self;
  FPaintField.Align := alTop;
  FPaintField.Height := 200;
  FPaintField.OnPaint := @PaintRefractionMap;

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

procedure TThermalMirageForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TThermalMirageForm.RefreshView;
var
  V: TCastleThermalMirageVolume;
begin
  V := TThermalMirageHelper.FindFirstVolume(FDesignRoot);
  if V = nil then
    FLblSummary.Caption := 'No TCastleThermalMirageVolume in scene. Click "+ Spawn Desert Highway Mirage".'
  else
    FLblSummary.Caption := V.MirageSummaryBadge;
  FMemoReport.Lines.Text := TThermalMirageHelper.GenerateMarkdownReport(V);
  FPaintField.Invalidate;
end;

procedure TThermalMirageForm.BtnSpawnDesertClick(Sender: TObject);
var
  V: TCastleThermalMirageVolume;
begin
  if TThermalMirageHelper.SpawnDesertHighwayMirageDemo(FDesignRoot, FDesignOwner, V) then
    NotifyChanged('Spawn Desert Highway Mirage Volume');
end;

procedure TThermalMirageForm.BtnCoralCausticsClick(Sender: TObject);
var
  V: TCastleThermalMirageVolume;
begin
  V := TThermalMirageHelper.FindFirstVolume(FDesignRoot);
  if V = nil then Exit;
  V.ApplyPreset(tmpSunlitCoralReefCaustics);
  NotifyChanged('Switch to Coral Reef Underwater Caustics');
end;

procedure TThermalMirageForm.BtnStepPhaseClick(Sender: TObject);
var
  V: TCastleThermalMirageVolume;
begin
  V := TThermalMirageHelper.FindFirstVolume(FDesignRoot);
  if V = nil then Exit;
  V.StepOpticalPhase(0.65);
  NotifyChanged('Step Optical Shimmer +0.65s');
end;

procedure TThermalMirageForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TThermalMirageForm.PaintRefractionMap(Sender: TObject);
var
  C: TCanvas;
  V: TCastleThermalMirageVolume;
  S: TThermalOpticalSample;
  W, H, GX, GZ, Lum: Integer;
  WX, WZ: Single;
begin
  C := FPaintField.Canvas;
  W := Max(20, FPaintField.Width);
  H := Max(20, FPaintField.Height);
  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  V := TThermalMirageHelper.FindFirstVolume(FDesignRoot);
  if V = nil then Exit;

  for GZ := 0 to 19 do
    for GX := 0 to 31 do
    begin
      WX := -8.0 + (GX / 31.0) * 16.0;
      WZ := -8.0 + (GZ / 19.0) * 16.0;
      S := V.SampleOpticalFieldAtWorld(Vector3(WX, 0.15, WZ), Vector3(0.0, 1.0, 20.0));
      if V.CausticContrast > 0.01 then
      begin
        Lum := Clamped(Round(40 + S.CausticLuminanceBoost * 95.0), 20, 255);
        C.Brush.Color := RGBToColor(Lum div 2, Lum, Min(255, Lum + 30));
      end else
      begin
        Lum := Clamped(Round(45 + S.InferiorMirageReflectivity01 * 195.0), 25, 255);
        C.Brush.Color := RGBToColor(Lum, Round(Lum * 0.78), Round(Lum * 0.45));
      end;
      C.FillRect((GX * W) div 32, (GZ * H) div 20, ((GX + 1) * W) div 32, ((GZ + 1) * H) div 20);
    end;
end;

end.
