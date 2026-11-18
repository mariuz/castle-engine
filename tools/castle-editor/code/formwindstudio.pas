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

{ Visual Studio dialog for Procedural Foliage Wind Gust Field & Shockwave Impulse (Phase 364). }
unit FormWindStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleWindField, ToolWindStudio;

type
  TWindStudioModifiedCallback = procedure(const UndoComment: String) of object;
  TWindStudioRefreshCallback = procedure of object;

  TWindStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TWindStudioModifiedCallback;
    FOnRefresh: TWindStudioRefreshCallback;
    FPaintField: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveDirector: TCastleWindFieldDirector;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnBreezeClick(Sender: TObject);
    procedure BtnGaleClick(Sender: TObject);
    procedure BtnHurricaneClick(Sender: TObject);
    procedure BtnShockwaveClick(Sender: TObject);
    procedure BtnStepWaveClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintWindVectorField(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TWindStudioModifiedCallback;
      const AOnRefresh: TWindStudioRefreshCallback);
  end;

implementation

constructor TWindStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TWindStudioModifiedCallback;
  const AOnRefresh: TWindStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Foliage Wind Gust Field & Shockwave Impulse Studio (Phase 364)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TWindStudioForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ WindDirectionalSource & Pivot-Painter 2.0 — Beaufort Gust Waves, Trunk/Branch Sway & Radial Blast Shockwaves';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn 5-Tree Wind Grove', @BtnSpawnClick);
  MakeBtn(Row1, 'Preset: Gentle Breeze', @BtnBreezeClick);
  MakeBtn(Row1, 'Preset: Autumn Gale', @BtnGaleClick);
  MakeBtn(Row1, 'Preset: Hurricane Tempest', @BtnHurricaneClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Detonate Radial Shockwave (26 m/s!)', @BtnShockwaveClick);
  MakeBtn(Row2, 'Step Wind & Shockwave (+0.35s)', @BtnStepWaveClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintField := TPaintBox.Create(Self);
  FPaintField.Parent := BodyPanel;
  FPaintField.Align := alLeft;
  FPaintField.Width := 490;
  FPaintField.OnPaint := @PaintWindVectorField;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TWindStudioForm.ActiveDirector: TCastleWindFieldDirector;
begin
  Result := TWindStudioHelper.FindWindDirectorInHierarchy(FDesignRoot);
end;

procedure TWindStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TWindStudioForm.RefreshView;
begin
  FMemoReport.Lines.Text := TWindStudioHelper.GenerateWindReport(ActiveDirector);
  FPaintField.Invalidate;
end;

procedure TWindStudioForm.BtnSpawnClick(Sender: TObject);
var
  D: TCastleWindFieldDirector;
begin
  if TWindStudioHelper.SpawnForestWindShockwaveDemo(FDesignRoot, FDesignOwner, D) then
    NotifyChange('Spawn Forest Wind Grove & Shockwave Director');
end;

procedure TWindStudioForm.BtnBreezeClick(Sender: TObject);
var
  D: TCastleWindFieldDirector;
begin
  D := ActiveDirector;
  if D = nil then Exit;
  D.Preset := wbpGentleSpringBreeze;
  NotifyChange('Switch Wind to Gentle Spring Breeze');
end;

procedure TWindStudioForm.BtnGaleClick(Sender: TObject);
var
  D: TCastleWindFieldDirector;
begin
  D := ActiveDirector;
  if D = nil then Exit;
  D.Preset := wbpAutumnGaleSquall;
  NotifyChange('Switch Wind to Autumn Gale Squall');
end;

procedure TWindStudioForm.BtnHurricaneClick(Sender: TObject);
var
  D: TCastleWindFieldDirector;
begin
  D := ActiveDirector;
  if D = nil then Exit;
  D.Preset := wbpHurricaneTempest;
  NotifyChange('Switch Wind to Hurricane Tempest');
end;

procedure TWindStudioForm.BtnShockwaveClick(Sender: TObject);
var
  D: TCastleWindFieldDirector;
begin
  D := ActiveDirector;
  if D = nil then Exit;
  D.TriggerRadialShockwave(Vector3(0, 0, 0), 26.0, 14.0, 18.0);
  D.StepWindField(0.25);
  NotifyChange('Detonate Radial Shockwave Impulse');
end;

procedure TWindStudioForm.BtnStepWaveClick(Sender: TObject);
var
  D: TCastleWindFieldDirector;
begin
  D := ActiveDirector;
  if D = nil then Exit;
  D.StepWindField(0.35);
  NotifyChange('Step Wind & Shockwave Field');
end;

procedure TWindStudioForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TWindStudioHelper.GenerateWindReport(ActiveDirector);
end;

procedure TWindStudioForm.PaintWindVectorField(Sender: TObject);
var
  Cv: TCanvas;
  W, H, GX, GZ, PX, PY, EX, EY, I, RingPx: Integer;
  D: TCastleWindFieldDirector;
  S: TPivotPainterWindSample;
  Ring: TWindShockwaveRing;
begin
  Cv := FPaintField.Canvas;
  W := FPaintField.Width;
  H := FPaintField.Height;
  Cv.Brush.Color := RGBToColor(16, 24, 20);
  Cv.FillRect(0, 0, W, H);

  D := ActiveDirector;
  if D = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn 5-Tree Wind Grove" to inspect XZ Wind & Shockwave Vectors.');
    Exit;
  end;

  Cv.Pen.Color := RGBToColor(95, 225, 145);
  Cv.Pen.Width := 2;
  for GZ := -4 to 4 do
    for GX := -4 to 4 do
    begin
      PX := Round(W * 0.5 + GX * 46);
      PY := Round(H * 0.52 + GZ * 46);
      S := D.SamplePivotWindAtWorld(Vector3(GX * 2.5, 0.0, GZ * 2.5), 4.0);
      EX := PX + Round(S.NetWindVelocityMps.X * 1.4);
      EY := PY + Round(S.NetWindVelocityMps.Z * 1.4);
      Cv.Line(PX, PY, EX, EY);
    end;

  Cv.Brush.Style := bsClear;
  Cv.Pen.Color := RGBToColor(255, 155, 55);
  for I := 0 to D.ActiveShockwaveCount - 1 do
  begin
    Ring := D.GetShockwave(I);
    RingPx := Max(4, Round(Ring.CurrentRadiusMeters * (46.0 / 2.5)));
    Cv.Ellipse(W div 2 - RingPx, Round(H * 0.52) - RingPx,
               W div 2 + RingPx, Round(H * 0.52) + RingPx);
  end;

  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 10, Format('XZ Wind & Shockwaves | Base=%.1fm/s | Active Rings=%d', [
    D.BaseWindSpeedMps, D.ActiveShockwaveCount]));
end;

end.
