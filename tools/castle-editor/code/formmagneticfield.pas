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

{ Visual Studio dialog for 3D Magnetic Dipole, Ferromagnetic Snap, Zero-G
  Mag-Boots & Eddy-Current Brake Studio (Phase 409). }
unit FormMagneticField;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleMagneticField, ToolMagneticField;

type
  TMagneticFieldModifiedCallback = procedure(const UndoComment: String) of object;
  TMagneticFieldRefreshCallback = procedure of object;

  TMagneticFieldForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMagneticFieldModifiedCallback;
    FOnRefresh: TMagneticFieldRefreshCallback;
    FLblSummary: TLabel;
    FPaintFlux: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnCranePresetClick(Sender: TObject);
    procedure BtnEddyPresetClick(Sender: TObject);
    procedure BtnToggleCoilClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintDipoleVectors(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMagneticFieldModifiedCallback;
      const AOnRefresh: TMagneticFieldRefreshCallback);
  end;

implementation

constructor TMagneticFieldForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMagneticFieldModifiedCallback;
  const AOnRefresh: TMagneticFieldRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := '3D Magnetic Dipole, Mag-Boots & Eddy-Current Brake Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TMagneticFieldForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnCrane, BtnEddy, BtnToggle, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Dipole + Hull Deck';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnCrane := TButton.Create(Self);
  BtnCrane.Parent := PnlButtons;
  BtnCrane.SetBounds(190, 8, 145, 30);
  BtnCrane.Caption := 'Scrapyard Crane';
  BtnCrane.OnClick := @BtnCranePresetClick;

  BtnEddy := TButton.Create(Self);
  BtnEddy.Parent := PnlButtons;
  BtnEddy.SetBounds(340, 8, 145, 30);
  BtnEddy.Caption := 'Coaster Eddy Brake';
  BtnEddy.OnClick := @BtnEddyPresetClick;

  BtnToggle := TButton.Create(Self);
  BtnToggle.Parent := PnlButtons;
  BtnToggle.SetBounds(490, 8, 135, 30);
  BtnToggle.Caption := 'Toggle Coil ON/OFF';
  BtnToggle.OnClick := @BtnToggleCoilClick;

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

  FPaintFlux := TPaintBox.Create(Self);
  FPaintFlux.Parent := Self;
  FPaintFlux.Align := alTop;
  FPaintFlux.Height := 215;
  FPaintFlux.OnPaint := @PaintDipoleVectors;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TMagneticFieldForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TMagneticFieldForm.RefreshView;
var
  M: TCastleMagneticField;
begin
  M := TMagneticFieldHelper.FindFirstMagnet(FDesignRoot);
  if M <> nil then
    FLblSummary.Caption := M.Name + '  ' + M.MagnetSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleMagneticField in scene — click "+ Spawn Dipole + Hull Deck".';
  FMemoReport.Lines.Text := TMagneticFieldHelper.GenerateMarkdownReport(M);
  FPaintFlux.Invalidate;
end;

procedure TMagneticFieldForm.BtnSpawnDemoClick(Sender: TObject);
var
  M: TCastleMagneticField;
begin
  if TMagneticFieldHelper.SpawnSpacecraftHullMagBootDemo(FDesignRoot, FDesignOwner, M) then
    NotifyChanged('Spawn Magnetic Dipole & Orbital Hull Demo');
end;

procedure TMagneticFieldForm.BtnCranePresetClick(Sender: TObject);
var
  M: TCastleMagneticField;
begin
  M := TMagneticFieldHelper.FindFirstMagnet(FDesignRoot);
  if M = nil then Exit;
  M.ApplyPreset(mfpScrapyardElectromagnetCrane);
  NotifyChanged('Switch to Scrapyard Electromagnet Crane');
end;

procedure TMagneticFieldForm.BtnEddyPresetClick(Sender: TObject);
var
  M: TCastleMagneticField;
begin
  M := TMagneticFieldHelper.FindFirstMagnet(FDesignRoot);
  if M = nil then Exit;
  M.ApplyPreset(mfpRailcoasterEddyBrake);
  NotifyChanged('Switch to Railcoaster Eddy-Current Brake');
end;

procedure TMagneticFieldForm.BtnToggleCoilClick(Sender: TObject);
var
  M: TCastleMagneticField;
begin
  M := TMagneticFieldHelper.FindFirstMagnet(FDesignRoot);
  if M = nil then Exit;
  M.CoilEnergized := not M.CoilEnergized;
  NotifyChanged('Toggle Electromagnet Coil');
end;

procedure TMagneticFieldForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TMagneticFieldForm.PaintDipoleVectors(Sender: TObject);
var
  C: TCanvas;
  W, H, GX, GY, SX, SY: Integer;
  M: TCastleMagneticField;
  B, Dir: TVector3;
  WX, WY: Single;
begin
  C := FPaintFlux.Canvas;
  W := FPaintFlux.Width;
  H := FPaintFlux.Height;
  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  M := TMagneticFieldHelper.FindFirstMagnet(FDesignRoot);
  if M = nil then Exit;

  C.Pen.Color := RGBToColor(80, 185, 255);
  for GX := 0 to 16 do
    for GY := 0 to 8 do
    begin
      WX := -4.0 + GX * 0.5;
      WY := -2.0 + GY * 0.5;
      if Hypot(WX, WY) < 0.45 then Continue;
      B := M.SampleBFieldTeslaAtWorld(M.Translation + Vector3(WX, WY, 0.0));
      SX := (W div 2) + Round(WX * 75.0);
      SY := (H div 2) - Round(WY * 42.0);
      if B.LengthSqr > 1e-12 then
      begin
        Dir := B.Normalize;
        C.MoveTo(SX, SY);
        C.LineTo(SX + Round(Dir.X * 14.0), SY - Round(Dir.Y * 14.0));
      end;
    end;

  C.Brush.Color := RGBToColor(235, 85, 70);
  C.FillRect((W div 2) - 10, (H div 2) - 18, (W div 2) + 10, H div 2);
  C.Brush.Color := RGBToColor(65, 130, 235);
  C.FillRect((W div 2) - 10, H div 2, (W div 2) + 10, (H div 2) + 18);
end;

end.
