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

{ Visual Studio dialog for Substrate Multi-Slab Layered Material Mixer (Phase 367). }
unit FormSubstrateStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleSubstrateMaterial, ToolSubstrateStudio;

type
  TSubstrateStudioModifiedCallback = procedure(const UndoComment: String) of object;
  TSubstrateStudioRefreshCallback = procedure of object;

  TSubstrateStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSubstrateStudioModifiedCallback;
    FOnRefresh: TSubstrateStudioRefreshCallback;
    FPaintSlab: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveMaterial: TCastleSubstrateMaterial;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnCarPaintClick(Sender: TObject);
    procedure BtnScarabClick(Sender: TObject);
    procedure BtnVelvetClick(Sender: TObject);
    procedure BtnWetStoneClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintDirectionalAlbedoCurve(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSubstrateStudioModifiedCallback;
      const AOnRefresh: TSubstrateStudioRefreshCallback);
  end;

implementation

constructor TSubstrateStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSubstrateStudioModifiedCallback;
  const AOnRefresh: TSubstrateStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Substrate Multi-Slab Material Mixer & Energy Conservation Studio (Phase 367)';
  Width := 1000;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TSubstrateStudioForm.BuildUi;
var
  Lbl: TLabel;
  Row1, BodyPanel: TPanel;

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
  Lbl.Caption := 'UE 6.0+ Substrate (USubstrateMaterial) — Clear-Coat Beer-Lambert, Thin-Film Iridescence, Velvet Fuzz & <= 1.0 Energy Gate';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 42;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Substrate Shader Ball', @BtnSpawnClick);
  MakeBtn(Row1, 'Candy Clear-Coat', @BtnCarPaintClick);
  MakeBtn(Row1, 'Iridescent Scarab (520nm)', @BtnScarabClick);
  MakeBtn(Row1, 'Royal Fuzz Velvet', @BtnVelvetClick);
  MakeBtn(Row1, 'Wet Cobblestone', @BtnWetStoneClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintSlab := TPaintBox.Create(Self);
  FPaintSlab.Parent := BodyPanel;
  FPaintSlab.Align := alLeft;
  FPaintSlab.Width := 490;
  FPaintSlab.OnPaint := @PaintDirectionalAlbedoCurve;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TSubstrateStudioForm.ActiveMaterial: TCastleSubstrateMaterial;
begin
  Result := TSubstrateStudioHelper.FindSubstrateInHierarchy(FDesignRoot);
end;

procedure TSubstrateStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TSubstrateStudioForm.RefreshView;
begin
  FMemoReport.Lines.Text := TSubstrateStudioHelper.GenerateSubstrateReport(ActiveMaterial);
  FPaintSlab.Invalidate;
end;

procedure TSubstrateStudioForm.BtnSpawnClick(Sender: TObject);
var
  M: TCastleSubstrateMaterial;
begin
  if TSubstrateStudioHelper.SpawnSubstrateShaderBallDemo(FDesignRoot, FDesignOwner, M) then
    NotifyChange('Spawn Substrate Multi-Slab Shader Ball');
end;

procedure TSubstrateStudioForm.BtnCarPaintClick(Sender: TObject);
var
  M: TCastleSubstrateMaterial;
begin
  M := ActiveMaterial;
  if M = nil then Exit;
  M.Preset := subpAutomotiveCandyClearCoat;
  NotifyChange('Apply Automotive Candy Clear-Coat Substrate');
end;

procedure TSubstrateStudioForm.BtnScarabClick(Sender: TObject);
var
  M: TCastleSubstrateMaterial;
begin
  M := ActiveMaterial;
  if M = nil then Exit;
  M.Preset := subpIridescentScarabCarapace;
  NotifyChange('Apply Iridescent Scarab Carapace Substrate');
end;

procedure TSubstrateStudioForm.BtnVelvetClick(Sender: TObject);
var
  M: TCastleSubstrateMaterial;
begin
  M := ActiveMaterial;
  if M = nil then Exit;
  M.Preset := subpRoyalVelvetGoldTrim;
  NotifyChange('Apply Royal Velvet Fuzz Substrate');
end;

procedure TSubstrateStudioForm.BtnWetStoneClick(Sender: TObject);
var
  M: TCastleSubstrateMaterial;
begin
  M := ActiveMaterial;
  if M = nil then Exit;
  M.Preset := subpWetMossyCobblestone;
  NotifyChange('Apply Wet Mossy Cobblestone Substrate');
end;

procedure TSubstrateStudioForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TSubstrateStudioHelper.GenerateSubstrateReport(ActiveMaterial);
end;

procedure TSubstrateStudioForm.PaintDirectionalAlbedoCurve(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, X0, X1: Integer;
  M: TCastleSubstrateMaterial;
  S0, S1: TSubstrateEvalSample;
begin
  Cv := FPaintSlab.Canvas;
  W := FPaintSlab.Width;
  H := FPaintSlab.Height;
  Cv.Brush.Color := RGBToColor(16, 18, 24);
  Cv.FillRect(0, 0, W, H);

  M := ActiveMaterial;
  if M = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Substrate Shader Ball" to plot RGB Reflectance vs. CosThetaV.');
    Exit;
  end;

  { 100% Energy Conservation Ceiling line }
  Cv.Pen.Color := RGBToColor(240, 210, 80);
  Cv.Line(24, 52, W - 24, 52);

  Cv.Pen.Width := 2;
  for I := 1 to 39 do
  begin
    S0 := M.EvaluateSlabAtCosTheta(I / 40.0);
    S1 := M.EvaluateSlabAtCosTheta((I + 1) / 40.0);
    X0 := 24 + Round(((I - 1) / 39.0) * (W - 48));
    X1 := 24 + Round((I / 39.0) * (W - 48));

    Cv.Pen.Color := RGBToColor(255, 85, 85);
    Cv.Line(X0, H - 40 - Round(S0.TotalReflectanceRgb.X * (H - 96)),
            X1, H - 40 - Round(S1.TotalReflectanceRgb.X * (H - 96)));
    Cv.Pen.Color := RGBToColor(85, 245, 130);
    Cv.Line(X0, H - 40 - Round(S0.TotalReflectanceRgb.Y * (H - 96)),
            X1, H - 40 - Round(S1.TotalReflectanceRgb.Y * (H - 96)));
    Cv.Pen.Color := RGBToColor(90, 165, 255);
    Cv.Line(X0, H - 40 - Round(S0.TotalReflectanceRgb.Z * (H - 96)),
            X1, H - 40 - Round(S1.TotalReflectanceRgb.Z * (H - 96)));
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(16, 12, Format('Directional RGB Albedo vs. CosThetaV | Peak=%.3f <= 1.000 (%s)', [
    M.PeakDirectionalAlbedo, BoolToStr(M.EnergyConservedAcrossAngles, 'ENERGY CONSERVED', 'EXCEEDED')]));
end;

end.
