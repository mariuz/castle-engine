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

{ Visual Studio dialog for Aerodynamic Wing / Sail Foil Polar & Stall (Phase 369). }
unit FormAeroFoil;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleAeroFoil, ToolAeroFoil;

type
  TAeroFoilModifiedCallback = procedure(const UndoComment: String) of object;
  TAeroFoilRefreshCallback = procedure of object;

  TAeroFoilForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TAeroFoilModifiedCallback;
    FOnRefresh: TAeroFoilRefreshCallback;
    FGliderVel: TVector3;
    FPaintPolar: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveFoil: TCastleAeroFoilBehavior;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnGliderClick(Sender: TObject);
    procedure BtnWingsuitClick(Sender: TObject);
    procedure BtnSailClick(Sender: TObject);
    procedure BtnSoarThermalClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintPolarCurves(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TAeroFoilModifiedCallback;
      const AOnRefresh: TAeroFoilRefreshCallback);
  end;

implementation

constructor TAeroFoilForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TAeroFoilModifiedCallback;
  const AOnRefresh: TAeroFoilRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FGliderVel := Vector3(0.0, 0.0, -16.0);
  Caption := 'Aerodynamic Wing / Sail Foil Polar (CL, CD), Critical Stall & Thermal Studio (Phase 369)';
  Width := 1000;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TAeroFoilForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ Flight/Sail Aerodynamics — Prandtl Finite-Wing CL(alpha), Induced Drag CD(alpha), Stall Drop & Thermal Soaring';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 42;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Glider & Thermal Column', @BtnSpawnClick);
  MakeBtn(Row1, 'Hang-Glider (AR=10)', @BtnGliderClick);
  MakeBtn(Row1, 'Wingsuit (AR=2.8)', @BtnWingsuitClick);
  MakeBtn(Row1, 'Schooner Mainsail', @BtnSailClick);
  MakeBtn(Row1, 'Step Thermal Soar (+1.0s)', @BtnSoarThermalClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintPolar := TPaintBox.Create(Self);
  FPaintPolar.Parent := BodyPanel;
  FPaintPolar.Align := alLeft;
  FPaintPolar.Width := 500;
  FPaintPolar.OnPaint := @PaintPolarCurves;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TAeroFoilForm.ActiveFoil: TCastleAeroFoilBehavior;
begin
  Result := TAeroFoilHelper.FindAeroFoilInHierarchy(FDesignRoot);
end;

procedure TAeroFoilForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TAeroFoilForm.RefreshView;
begin
  FMemoReport.Lines.Text := TAeroFoilHelper.GenerateAeroReport(ActiveFoil);
  FPaintPolar.Invalidate;
end;

procedure TAeroFoilForm.BtnSpawnClick(Sender: TObject);
var
  G: TCastleTransform;
  F: TCastleAeroFoilBehavior;
begin
  if TAeroFoilHelper.SpawnGliderThermalCanyonDemo(FDesignRoot, FDesignOwner, G, F) then
  begin
    FGliderVel := Vector3(0.0, 0.0, -16.0);
    NotifyChange('Spawn Soaring Glider & Thermal Updraft Column');
  end;
end;

procedure TAeroFoilForm.BtnGliderClick(Sender: TObject);
var
  F: TCastleAeroFoilBehavior;
begin
  F := ActiveFoil;
  if F = nil then Exit;
  F.Preset := afpHangGliderHighAspectWing;
  NotifyChange('Apply Hang-Glider High-Aspect Wing Preset');
end;

procedure TAeroFoilForm.BtnWingsuitClick(Sender: TObject);
var
  F: TCastleAeroFoilBehavior;
begin
  F := ActiveFoil;
  if F = nil then Exit;
  F.Preset := afpWingsuitDeltaMembrane;
  NotifyChange('Apply Wingsuit Delta Membrane Preset');
end;

procedure TAeroFoilForm.BtnSailClick(Sender: TObject);
var
  F: TCastleAeroFoilBehavior;
begin
  F := ActiveFoil;
  if F = nil then Exit;
  F.Preset := afpSchoonerMainsailCanvas;
  NotifyChange('Apply Schooner Mainsail Preset');
end;

procedure TAeroFoilForm.BtnSoarThermalClick(Sender: TObject);
var
  F: TCastleAeroFoilBehavior;
  PosW: TVector3;
  I: Integer;
begin
  F := ActiveFoil;
  if (F = nil) or (F.Parent = nil) then Exit;
  PosW := F.Parent.Translation;
  for I := 1 to 20 do
    F.StepGliderFlight(PosW, FGliderVel, 4.0, TVector3.Zero, 0.05);
  NotifyChange('Step Glider Thermal Soaring (+1.0s)');
end;

procedure TAeroFoilForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TAeroFoilHelper.GenerateAeroReport(ActiveFoil);
end;

procedure TAeroFoilForm.PaintPolarCurves(Sender: TObject);
var
  Cv: TCanvas;
  W, H, Deg, X0, X1, MidY, StallX: Integer;
  F: TCastleAeroFoilBehavior;
  P0, P1: TAeroFoilPolarSample;
begin
  Cv := FPaintPolar.Canvas;
  W := FPaintPolar.Width;
  H := FPaintPolar.Height;
  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);

  F := ActiveFoil;
  if F = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Glider & Thermal Column" to plot CL(alpha) & CD(alpha).');
    Exit;
  end;

  MidY := Round(H * 0.68);
  Cv.Pen.Color := RGBToColor(70, 80, 96);
  Cv.Line(24, MidY, W - 24, MidY);

  StallX := 24 + Round(((F.CriticalStallAngleDeg + 10.0) / 55.0) * (W - 48));
  Cv.Pen.Color := RGBToColor(245, 95, 75);
  Cv.Line(StallX, 40, StallX, H - 30);

  Cv.Pen.Width := 2;
  for Deg := -10 to 44 do
  begin
    P0 := F.EvaluatePolarAtAlphaDeg(Deg);
    P1 := F.EvaluatePolarAtAlphaDeg(Deg + 1);
    X0 := 24 + Round(((Deg + 10.0) / 55.0) * (W - 48));
    X1 := 24 + Round(((Deg + 11.0) / 55.0) * (W - 48));

    { Lift CL in Cyan }
    Cv.Pen.Color := RGBToColor(75, 215, 255);
    Cv.Line(X0, MidY - Round(P0.LiftCoeffCL * 155),
            X1, MidY - Round(P1.LiftCoeffCL * 155));

    { Drag CD in Amber }
    Cv.Pen.Color := RGBToColor(255, 180, 65);
    Cv.Line(X0, MidY - Round(P0.DragCoeffCD * 155),
            X1, MidY - Round(P1.DragCoeffCD * 155));
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(16, 12, Format('CL (Cyan) & CD (Amber) vs Alpha [-10..45 deg] | Stall Gate = %.1f deg', [
    F.CriticalStallAngleDeg]));
end;

end.
