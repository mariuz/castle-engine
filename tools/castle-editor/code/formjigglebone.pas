{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Interactive Secondary-Motion Jiggle Bone Springs, Gravity/Centrifugal Inertia
  & Spherical Limit Cone Studio dialog (Phase 344). }
unit FormJiggleBone;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleJiggleBone, ToolJiggleBone;

type
  TJiggleBoneModifyCallback = procedure(const AUndoComment: String) of object;
  TJiggleBoneRefreshCallback = procedure of object;

  TJiggleBoneForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TJiggleBoneModifyCallback;
    FOnRefreshViewport: TJiggleBoneRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintCone: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure BtnSpawnRigClick(Sender: TObject);
    procedure BtnDodgeRightClick(Sender: TObject);
    procedure BtnDodgeLeftClick(Sender: TObject);
    procedure BtnStepFrameClick(Sender: TObject);
    procedure BtnSettleClick(Sender: TObject);
    procedure BtnCyclePresetClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintConePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TJiggleBoneModifyCallback;
      const AOnRefreshViewport: TJiggleBoneRefreshCallback);
  end;

implementation

constructor TJiggleBoneForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TJiggleBoneModifyCallback;
  const AOnRefreshViewport: TJiggleBoneRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Secondary-Motion Jiggle Bone Springs & Spherical Limit Cone Studio (UE 6.0+ AnimNode_SpringBone Parity)';
  Width := 1040;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TJiggleBoneForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 160): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Align := alLeft;
    Result.BorderSpacing.Around := 4;
    Result.OnClick := AOnClick;
  end;

begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 128;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'Secondary-Motion Jiggle Bone Springs — Inertial Tip Whip, Gravity Sag, Damping Ratio & Spherical Limit Cones';

  LabelTelemetry := TLabel.Create(Self);
  LabelTelemetry.Parent := TopBar;
  LabelTelemetry.Align := alTop;
  LabelTelemetry.BorderSpacing.Left := 6;
  LabelTelemetry.Caption := 'Telemetry: ready';

  BtnRow1 := TPanel.Create(Self);
  BtnRow1.Parent := TopBar;
  BtnRow1.Align := alTop;
  BtnRow1.Height := 38;
  BtnRow1.BevelOuter := bvNone;
  MakeBtn(BtnRow1, '+ Spawn Fox-Ear & Pouch Rig', @BtnSpawnRigClick, 196);
  MakeBtn(BtnRow1, 'Jolt Dodge (+1.2m X)', @BtnDodgeRightClick, 162);
  MakeBtn(BtnRow1, 'Jolt Dodge (-1.2m X)', @BtnDodgeLeftClick, 162);
  MakeBtn(BtnRow1, 'Step Spring (+0.03s)', @BtnStepFrameClick, 162);
  MakeBtn(BtnRow1, 'Settle Equilibrium (2s)', @BtnSettleClick, 174);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Cycle Spring Preset', @BtnCyclePresetClick, 170);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 184);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 400;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintCone := TPaintBox.Create(Self);
  PaintCone.Parent := BodyPanel;
  PaintCone.Align := alClient;
  PaintCone.BorderSpacing.Around := 6;
  PaintCone.OnPaint := @PaintConePaint;
end;

procedure TJiggleBoneForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TJiggleBoneForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TJiggleBoneStudioSummary;
begin
  Warnings := TStringList.Create;
  try
    Sum := TJiggleBoneHelper.CollectSummary(FDesignRoot, Warnings);
    LabelTelemetry.Caption := Format(
      'Jiggle Springs: %d | Cone-Clamped: %d | Peak Deflection: %.1f deg | Peak Tip Speed: %.2f m/s',
      [Sum.JiggleBehaviorCount, Sum.ConeClampedCount, Sum.PeakDeflectionDeg, Sum.PeakTipSpeedMps]);
    MemoReport.Lines.Text := TJiggleBoneHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintCone.Invalidate;
end;

procedure TJiggleBoneForm.BtnSpawnRigClick(Sender: TObject);
var
  Carrier: TCastleTransform;
begin
  if TJiggleBoneHelper.SpawnCharacterJiggleRigDemo(FDesignRoot, FDesignOwner, Carrier) then
    NotifyChange('Spawn Jiggle Bone Character Rig');
end;

procedure TJiggleBoneForm.BtnDodgeRightClick(Sender: TObject);
begin
  TJiggleBoneHelper.JoltCarrierImpulse(FDesignRoot, Vector3(+1.2, 0.0, 0.0), 0.02);
  NotifyChange('Jolt Jiggle Rig +X');
end;

procedure TJiggleBoneForm.BtnDodgeLeftClick(Sender: TObject);
begin
  TJiggleBoneHelper.JoltCarrierImpulse(FDesignRoot, Vector3(-1.2, 0.0, 0.0), 0.02);
  NotifyChange('Jolt Jiggle Rig -X');
end;

procedure TJiggleBoneForm.BtnStepFrameClick(Sender: TObject);
begin
  TJiggleBoneHelper.StepAllJiggleBones(FDesignRoot, 0.03);
  NotifyChange('Step Jiggle Bone Springs');
end;

procedure TJiggleBoneForm.BtnSettleClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 1 to 60 do
    TJiggleBoneHelper.StepAllJiggleBones(FDesignRoot, 1.0 / 30.0);
  NotifyChange('Settle Jiggle Bone Springs');
end;

procedure TJiggleBoneForm.BtnCyclePresetClick(Sender: TObject);
var
  J: TCastleJiggleBoneBehavior;
  NextP: TJiggleSpringPreset;
begin
  J := TJiggleBoneHelper.FindFirstJiggleBehavior(FDesignRoot);
  if J = nil then Exit;
  case J.Preset of
    jspBouncyFoxEars:      NextP := jspWhippyRadioAntenna;
    jspWhippyRadioAntenna: NextP := jspHeavyLeatherPouch;
    jspHeavyLeatherPouch:  NextP := jspSoftSilkRibbon;
  else
    NextP := jspBouncyFoxEars;
  end;
  J.ApplySpringPreset(NextP);
  NotifyChange('Cycle Jiggle Spring Preset');
end;

procedure TJiggleBoneForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'jiggle_bone_springs_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TJiggleBoneHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TJiggleBoneForm.PaintConePaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, CX, CY, ConeR, TipX, TipY: Integer;
  J: TCastleJiggleBoneBehavior;
  Delta: TVector3;
  NormScale: Single;
begin
  Cv := PaintCone.Canvas;
  W := Max(200, PaintCone.Width);
  H := Max(200, PaintCone.Height);
  CX := W div 2;
  CY := H div 2 + 12;
  ConeR := Min(W, H) div 2 - 46;

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);

  { Polar spherical cone boundary }
  Cv.Brush.Color := RGBToColor(24, 32, 46);
  Cv.Pen.Color := RGBToColor(82, 168, 240);
  Cv.Pen.Width := 2;
  Cv.Ellipse(CX - ConeR, CY - ConeR, CX + ConeR, CY + ConeR);
  Cv.Pen.Width := 1;
  Cv.Pen.Color := RGBToColor(46, 58, 78);
  Cv.Line(CX - ConeR, CY, CX + ConeR, CY);
  Cv.Line(CX, CY - ConeR, CX, CY + ConeR);

  J := TJiggleBoneHelper.FindFirstJiggleBehavior(FDesignRoot);
  if J <> nil then
  begin
    Delta := J.CurrentTipWorld - J.RestTipWorld;
    NormScale := ConeR / Max(0.05, J.BoneLength * Sin(DegToRad(Max(5.0, J.MaxConeAngleDeg))));
    TipX := EnsureRange(CX + Round(Delta.X * NormScale), CX - ConeR, CX + ConeR);
    TipY := EnsureRange(CY - Round(Delta.Z * NormScale), CY - ConeR, CY + ConeR);

    Cv.Pen.Color := RGBToColor(250, 182, 64);
    Cv.Pen.Width := 3;
    Cv.Line(CX, CY, TipX, TipY);
    Cv.Pen.Width := 1;
    Cv.Brush.Color := RGBToColor(255, 118, 56);
    Cv.Ellipse(TipX - 9, TipY - 9, TipX + 9, TipY + 9);
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(16, 10, 'Polar Spherical Limit-Cone Radar (Rest Axis vs. Live Inertial Tip)');
  Cv.Font.Style := [];
end;

end.
