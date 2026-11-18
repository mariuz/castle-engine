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

{ Visual Studio dialog for Cinematic Camera Shake, Recoil & FOV Kickback (Phase 371). }
unit FormCameraShake;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleCameraShake, ToolCameraShake;

type
  TCameraShakeModifiedCallback = procedure(const UndoComment: String) of object;
  TCameraShakeRefreshCallback = procedure of object;

  TCameraShakeForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TCameraShakeModifiedCallback;
    FOnRefresh: TCameraShakeRefreshCallback;
    FPaintReticle: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveDirector: TCastleCameraShakeDirector;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnShotgunClick(Sender: TObject);
    procedure BtnBlastClick(Sender: TObject);
    procedure BtnStepDecayClick(Sender: TObject);
    procedure BtnToggleMotionSafeClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintReticleKick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TCameraShakeModifiedCallback;
      const AOnRefresh: TCameraShakeRefreshCallback);
  end;

implementation

constructor TCameraShakeForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TCameraShakeModifiedCallback;
  const AOnRefresh: TCameraShakeRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Cinematic Camera Shake, Directional Recoil & FOV Kickback Studio (Phase 371)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TCameraShakeForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ UCameraShakeBase — Trauma^2 Perlin Harmonics, Directional Muzzle Recoil, FOV Kick & Motion-Sickness Scale';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 42;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Firing Range Director', @BtnSpawnClick);
  MakeBtn(Row1, 'Fire Shotgun Recoil (+FOV!)', @BtnShotgunClick);
  MakeBtn(Row1, 'Detonate 8m Barrel Blast', @BtnBlastClick);
  MakeBtn(Row1, 'Step Decay (+0.12s)', @BtnStepDecayClick);
  MakeBtn(Row1, 'Toggle 0% Accessibility Scale', @BtnToggleMotionSafeClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintReticle := TPaintBox.Create(Self);
  FPaintReticle.Parent := BodyPanel;
  FPaintReticle.Align := alLeft;
  FPaintReticle.Width := 480;
  FPaintReticle.OnPaint := @PaintReticleKick;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TCameraShakeForm.ActiveDirector: TCastleCameraShakeDirector;
begin
  Result := TCameraShakeHelper.FindShakeDirectorInHierarchy(FDesignRoot);
end;

procedure TCameraShakeForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TCameraShakeForm.RefreshView;
begin
  FMemoReport.Lines.Text := TCameraShakeHelper.GenerateShakeReport(ActiveDirector);
  FPaintReticle.Invalidate;
end;

procedure TCameraShakeForm.BtnSpawnClick(Sender: TObject);
var
  D: TCastleCameraShakeDirector;
begin
  if TCameraShakeHelper.SpawnFiringRangeShakeDemo(FDesignRoot, FDesignOwner, D) then
    NotifyChange('Spawn Firing Range Camera Shake Director');
end;

procedure TCameraShakeForm.BtnShotgunClick(Sender: TObject);
var
  D: TCastleCameraShakeDirector;
begin
  D := ActiveDirector;
  if D = nil then Exit;
  D.TriggerPresetShake(cspHeavyShotgunKickback, 1.0);
  D.StepCameraShakes(0.02);
  NotifyChange('Trigger Heavy Shotgun Recoil & FOV Kick');
end;

procedure TCameraShakeForm.BtnBlastClick(Sender: TObject);
var
  D: TCastleCameraShakeDirector;
begin
  D := ActiveDirector;
  if D = nil then Exit;
  D.TriggerWorldExplosionShake(Vector3(0, 0.65, -8.0), TVector3.Zero, 1.0);
  D.StepCameraShakes(0.03);
  NotifyChange('Trigger 8m Explosive Barrel Concussion Shake');
end;

procedure TCameraShakeForm.BtnStepDecayClick(Sender: TObject);
var
  D: TCastleCameraShakeDirector;
begin
  D := ActiveDirector;
  if D = nil then Exit;
  D.StepCameraShakes(0.12);
  NotifyChange('Step Camera Shake Decay (+0.12s)');
end;

procedure TCameraShakeForm.BtnToggleMotionSafeClick(Sender: TObject);
var
  D: TCastleCameraShakeDirector;
begin
  D := ActiveDirector;
  if D = nil then Exit;
  if D.GlobalShakeScale > 0.01 then
    D.GlobalShakeScale := 0.0
  else
    D.GlobalShakeScale := 1.0;
  D.StepCameraShakes(0.0);
  NotifyChange('Toggle Accessibility GlobalShakeScale');
end;

procedure TCameraShakeForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TCameraShakeHelper.GenerateShakeReport(ActiveDirector);
end;

procedure TCameraShakeForm.PaintReticleKick(Sender: TObject);
var
  Cv: TCanvas;
  W, H, CX, CY, RX, RY, FovR: Integer;
  D: TCastleCameraShakeDirector;
  F: TCameraShakeFrameOffset;
begin
  Cv := FPaintReticle.Canvas;
  W := FPaintReticle.Width;
  H := FPaintReticle.Height;
  Cv.Brush.Color := RGBToColor(16, 18, 26);
  Cv.FillRect(0, 0, W, H);

  D := ActiveDirector;
  if D = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Firing Range Director" to preview Reticle & FOV Kick.');
    Exit;
  end;

  CX := W div 2;
  CY := H div 2;
  F := D.LastFrame;

  Cv.Pen.Color := RGBToColor(70, 80, 96);
  Cv.Line(CX - 90, CY, CX + 90, CY);
  Cv.Line(CX, CY - 90, CX, CY + 90);

  RX := CX + Round(F.PitchYawRollDeg.Y * 14.0);
  RY := CY - Round(F.PitchYawRollDeg.X * 14.0);
  FovR := Max(18, 56 + Round(F.FovDeltaDegrees * 8.0));

  Cv.Brush.Style := bsClear;
  Cv.Pen.Width := 2;
  Cv.Pen.Color := RGBToColor(255, 190, 65);
  Cv.Ellipse(RX - FovR, RY - FovR, RX + FovR, RY + FovR);

  Cv.Font.Color := clWhite;
  Cv.TextOut(14, 12, Format('Reticle Recoil & FOV Ring | Pitch=%+.2fd | FOV=%+.2fd | Layers=%d', [
    F.PitchYawRollDeg.X, F.FovDeltaDegrees, D.ActiveLayerCount]));
end;

end.
