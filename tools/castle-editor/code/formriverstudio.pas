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

{ Visual Studio dialog for River Spline Rapids, Width/Depth & Drift (Phase 361). }
unit FormRiverStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleRiverSpline, ToolRiverStudio;

type
  TRiverStudioModifiedCallback = procedure(const UndoComment: String) of object;
  TRiverStudioRefreshCallback = procedure of object;

  TRiverStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TRiverStudioModifiedCallback;
    FOnRefresh: TRiverStudioRefreshCallback;
    FKayakVel: TVector3;
    FPaintRiver: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveRiver: TCastleRiverSpline;
    function ActiveKayak: TCastleTransform;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnGorgeClick(Sender: TObject);
    procedure BtnWaterfallClick(Sender: TObject);
    procedure BtnValleyClick(Sender: TObject);
    procedure BtnDriftKayakClick(Sender: TObject);
    procedure BtnFloodSurgeClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintRiverProfile(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TRiverStudioModifiedCallback;
      const AOnRefresh: TRiverStudioRefreshCallback);
  end;

implementation

constructor TRiverStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TRiverStudioModifiedCallback;
  const AOnRefresh: TRiverStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FKayakVel := TVector3.Zero;
  Caption := 'Spline Water River / Rapids, Variable Width & Whitewater Studio (Phase 361)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TRiverStudioForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ WaterBodyRiver — Q = A * v Gorge Continuity Acceleration, Waterfall Slope Rapids, Foam & Kayak Drift';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Gorge River & Kayak', @BtnSpawnClick);
  MakeBtn(Row1, 'Preset: Mountain Gorge Rapids', @BtnGorgeClick);
  MakeBtn(Row1, 'Preset: Waterfall Cascade', @BtnWaterfallClick);
  MakeBtn(Row1, 'Preset: Meandering Stream', @BtnValleyClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Drift Kayak Downstream (+2.5s)', @BtnDriftKayakClick);
  MakeBtn(Row2, 'Spring Snowmelt Surge (Q = 32 m^3/s)', @BtnFloodSurgeClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintRiver := TPaintBox.Create(Self);
  FPaintRiver.Parent := BodyPanel;
  FPaintRiver.Align := alLeft;
  FPaintRiver.Width := 520;
  FPaintRiver.OnPaint := @PaintRiverProfile;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TRiverStudioForm.ActiveRiver: TCastleRiverSpline;
begin
  Result := TRiverStudioHelper.FindRiverInHierarchy(FDesignRoot);
end;

function TRiverStudioForm.ActiveKayak: TCastleTransform;
begin
  Result := nil;
  if FDesignOwner <> nil then
    Result := FDesignOwner.FindComponent('RiverKayak1') as TCastleTransform;
end;

procedure TRiverStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TRiverStudioForm.RefreshView;
begin
  FMemoReport.Lines.Text := TRiverStudioHelper.GenerateRiverReport(ActiveRiver);
  FPaintRiver.Invalidate;
end;

procedure TRiverStudioForm.BtnSpawnClick(Sender: TObject);
var
  R: TCastleRiverSpline;
  K: TCastleTransform;
begin
  if TRiverStudioHelper.SpawnMountainGorgeRiverDemo(FDesignRoot, FDesignOwner, R, K) then
  begin
    FKayakVel := TVector3.Zero;
    NotifyChange('Spawn Mountain Gorge River & Kayak');
  end;
end;

procedure TRiverStudioForm.BtnGorgeClick(Sender: TObject);
var
  R: TCastleRiverSpline;
begin
  R := ActiveRiver;
  if R = nil then Exit;
  R.Preset := rspMountainGorgeRapids;
  NotifyChange('Switch River to Mountain Gorge Rapids');
end;

procedure TRiverStudioForm.BtnWaterfallClick(Sender: TObject);
var
  R: TCastleRiverSpline;
begin
  R := ActiveRiver;
  if R = nil then Exit;
  R.Preset := rspWaterfallPlungeCascade;
  NotifyChange('Switch River to Waterfall Plunge Cascade');
end;

procedure TRiverStudioForm.BtnValleyClick(Sender: TObject);
var
  R: TCastleRiverSpline;
begin
  R := ActiveRiver;
  if R = nil then Exit;
  R.Preset := rspMeanderingValleyStream;
  NotifyChange('Switch River to Meandering Valley Stream');
end;

procedure TRiverStudioForm.BtnDriftKayakClick(Sender: TObject);
var
  R: TCastleRiverSpline;
  K: TCastleTransform;
  PosW: TVector3;
  I: Integer;
begin
  R := ActiveRiver;
  K := ActiveKayak;
  if (R = nil) or (K = nil) then Exit;
  PosW := K.Translation;
  for I := 1 to 25 do
    R.StepFloatingBodyAlongRiver(PosW, FKayakVel, 4.0, 0.10);
  K.Translation := PosW;
  NotifyChange('Drift Kayak Downstream Along River');
end;

procedure TRiverStudioForm.BtnFloodSurgeClick(Sender: TObject);
var
  R: TCastleRiverSpline;
begin
  R := ActiveRiver;
  if R = nil then Exit;
  R.DischargeCubicMps := 32.0;
  NotifyChange('Apply Spring Snowmelt Surge (32 m^3/s)');
end;

procedure TRiverStudioForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TRiverStudioHelper.GenerateRiverReport(ActiveRiver);
end;

procedure TRiverStudioForm.PaintRiverProfile(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, PX, PY, HalfWPx: Integer;
  R: TCastleRiverSpline;
  S: TRiverCrossSectionSample;
begin
  Cv := FPaintRiver.Canvas;
  W := FPaintRiver.Width;
  H := FPaintRiver.Height;
  Cv.Brush.Color := RGBToColor(18, 24, 32);
  Cv.FillRect(0, 0, W, H);

  R := ActiveRiver;
  if R = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Gorge River & Kayak" to inspect XZ Channel Width & Foam.');
    Exit;
  end;

  for I := 0 to 40 do
  begin
    S := R.SampleRiverAtParam(I / 40.0);
    PX := Round(W * 0.50 + (S.CenterWorldPos.X / 24.0) * (W * 0.42));
    PY := Round(H * 0.52 + (S.CenterWorldPos.Z / 20.0) * (H * 0.42));
    HalfWPx := Max(4, Round(S.WidthMeters * 3.2));
    Cv.Brush.Color := RGBToColor(
      Round(25 + S.WhitewaterFoamFactor * 225),
      Round(115 + S.WhitewaterFoamFactor * 135),
      Round(190 + S.WhitewaterFoamFactor * 65));
    Cv.Pen.Style := psClear;
    Cv.Ellipse(PX - HalfWPx, PY - HalfWPx, PX + HalfWPx, PY + HalfWPx);
  end;

  Cv.Pen.Style := psSolid;
  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 10, Format('XZ River Width & Foam | Peak Speed = %.2f m/s | Mean Foam = %.1f%%', [
    R.PeakFlowSpeedMps, R.MeanFoamFactor * 100.0]));
end;

end.
