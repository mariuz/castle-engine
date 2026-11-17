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

{ Interactive Control Rig Procedural Multi-Bone Chain, FABRIK Solver, Twist
  Roll Distribution & Sine Wave Studio dialog (Phase 338). }
unit FormControlRig;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleControlRig, ToolControlRig;

type
  TControlRigModifyCallback = procedure(const AUndoComment: String) of object;
  TControlRigRefreshCallback = procedure of object;

  TControlRigForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TControlRigModifyCallback;
    FOnRefreshViewport: TControlRigRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintChain: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure MoveTargetTo(const APos: TVector3; const AComment: String);
    procedure BtnSpawnRigClick(Sender: TObject);
    procedure BtnNearReachClick(Sender: TObject);
    procedure BtnHighArcClick(Sender: TObject);
    procedure BtnOutReachClick(Sender: TObject);
    procedure BtnAddTwistClick(Sender: TObject);
    procedure BtnWaveStepClick(Sender: TObject);
    procedure BtnCyclePresetClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintChainPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TControlRigModifyCallback;
      const AOnRefreshViewport: TControlRigRefreshCallback);
  end;

implementation

constructor TControlRigForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TControlRigModifyCallback;
  const AOnRefreshViewport: TControlRigRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Control Rig Multi-Bone FABRIK, Twist Distribution & Wave Studio (UE 6.0+ Control Rig Parity)';
  Width := 1020;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TControlRigForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 152): TButton;
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
  TopBar.Height := 126;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'Control Rig Multi-Bone Chains — N-Joint FABRIK Convergence, Progressive Forearm/Spine Twist & Procedural Tail Waves';

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
  MakeBtn(BtnRow1, '+ Spawn 6-Joint FABRIK Arm', @BtnSpawnRigClick, 185);
  MakeBtn(BtnRow1, 'Target Near (2.4m)', @BtnNearReachClick, 150);
  MakeBtn(BtnRow1, 'Target High Arc (3.2m)', @BtnHighArcClick, 165);
  MakeBtn(BtnRow1, 'Target Out-of-Reach (7m)', @BtnOutReachClick, 178);
  MakeBtn(BtnRow1, 'Twist Roll +45°', @BtnAddTwistClick, 138);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Step Wave (+0.15s)', @BtnWaveStepClick, 152);
  MakeBtn(BtnRow2, 'Cycle Rig Preset', @BtnCyclePresetClick, 148);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 182);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 390;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintChain := TPaintBox.Create(Self);
  PaintChain.Parent := BodyPanel;
  PaintChain.Align := alClient;
  PaintChain.BorderSpacing.Around := 6;
  PaintChain.OnPaint := @PaintChainPaint;
end;

procedure TControlRigForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TControlRigForm.RefreshUi;
var
  Rig: TCastleControlRigBehavior;
begin
  Rig := TControlRigHelper.FindFirstControlRig(FDesignRoot);
  if Rig <> nil then
    LabelTelemetry.Caption := Format(
      '%s (%s) | Joints: %d | Reach: %.2fm | Iters: %d | TipErr: %.4fm | Drift: %.5fm | Twist: %.0f°',
      [Rig.Name, ControlRigPresetToDisplayName(Rig.Preset), Rig.JointCount,
       Rig.TotalChainLength, Rig.LastIterationsUsed, Rig.LastTipErrorMeters,
       Rig.MaxSegmentLengthDrift, Rig.EndEffectorTwistDeg])
  else
    LabelTelemetry.Caption := 'No TCastleControlRigBehavior in design — click "+ Spawn 6-Joint FABRIK Arm" to create a demo rig.';

  MemoReport.Lines.Text := TControlRigHelper.BuildMarkdownReport(FDesignRoot);
  PaintChain.Invalidate;
end;

procedure TControlRigForm.MoveTargetTo(const APos: TVector3; const AComment: String);
var
  Rig: TCastleControlRigBehavior;
  Comp: TComponent;
begin
  Rig := TControlRigHelper.FindFirstControlRig(FDesignRoot);
  if Rig = nil then Exit;
  Rig.EnableProceduralWave := False;
  if (FDesignOwner <> nil) and (Rig.EffectorTargetName <> '') then
  begin
    Comp := FDesignOwner.FindComponent(Rig.EffectorTargetName);
    if Comp is TCastleTransform then
      TCastleTransform(Comp).Translation := APos;
  end;
  Rig.SolveRig(0.0);
  NotifyChange(AComment);
end;

procedure TControlRigForm.BtnSpawnRigClick(Sender: TObject);
var
  Host, Target: TCastleTransform;
  Rig: TCastleControlRigBehavior;
begin
  if TControlRigHelper.SpawnRoboticArmControlRigDemo(FDesignRoot, FDesignOwner, Host, Target, Rig) then
    NotifyChange('Spawn Control Rig FABRIK Arm');
end;

procedure TControlRigForm.BtnNearReachClick(Sender: TObject);
begin
  MoveTargetTo(Vector3(0.8, 1.4, 1.7), 'Control Rig Near Target');
end;

procedure TControlRigForm.BtnHighArcClick(Sender: TObject);
begin
  MoveTargetTo(Vector3(-0.6, 2.8, 1.4), 'Control Rig High Arc Target');
end;

procedure TControlRigForm.BtnOutReachClick(Sender: TObject);
begin
  MoveTargetTo(Vector3(0.0, 2.5, 6.5), 'Control Rig Out-of-Reach Stretch');
end;

procedure TControlRigForm.BtnAddTwistClick(Sender: TObject);
var
  Rig: TCastleControlRigBehavior;
begin
  Rig := TControlRigHelper.FindFirstControlRig(FDesignRoot);
  if Rig = nil then Exit;
  Rig.EndEffectorTwistDeg := Rig.EndEffectorTwistDeg + 45.0;
  NotifyChange('Distribute Progressive Twist +45°');
end;

procedure TControlRigForm.BtnWaveStepClick(Sender: TObject);
var
  Rig: TCastleControlRigBehavior;
begin
  Rig := TControlRigHelper.FindFirstControlRig(FDesignRoot);
  if Rig = nil then Exit;
  Rig.EnableProceduralWave := True;
  Rig.SolveRig(0.15);
  NotifyChange('Step Control Rig Procedural Wave');
end;

procedure TControlRigForm.BtnCyclePresetClick(Sender: TObject);
var
  Rig: TCastleControlRigBehavior;
begin
  Rig := TControlRigHelper.FindFirstControlRig(FDesignRoot);
  if Rig = nil then Exit;
  case Rig.Preset of
    crpRoboticArmFabrik:   Rig.Preset := crpProceduralTailWave;
    crpProceduralTailWave: Rig.Preset := crpDragonNeckAim;
    crpDragonNeckAim:      Rig.Preset := crpRoboticArmFabrik;
  end;
  Rig.SolveRig(0.10);
  NotifyChange('Cycle Control Rig Preset');
end;

procedure TControlRigForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'control_rig_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TControlRigHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TControlRigForm.PaintChainPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, HalfW, Cx1, Cy1, Cx2, Cy2, I, RReach: Integer;
  Rig: TCastleControlRigBehavior;
  ScalePx: Single;
  RootP, A, B: TVector3;
begin
  Cv := PaintChain.Canvas;
  W := Max(120, PaintChain.Width);
  H := Max(120, PaintChain.Height);
  HalfW := W div 2;

  Cv.Brush.Color := RGBToColor(18, 22, 28);
  Cv.FillRect(0, 0, W, H);
  Cv.Pen.Color := RGBToColor(52, 60, 76);
  Cv.Line(HalfW, 0, HalfW, H);

  Rig := TControlRigHelper.FindFirstControlRig(FDesignRoot);
  if (Rig <> nil) and (Rig.JointCount >= 2) then
  begin
    RootP := Rig.JointWorldPos(0);
    ScalePx := Min(HalfW, H) / Max(4.5, Rig.TotalChainLength * 2.35);
    Cx1 := HalfW div 2;
    Cy1 := (H * 3) div 5;
    Cx2 := HalfW + (HalfW div 2);
    Cy2 := H div 2;

    RReach := Round(Rig.TotalChainLength * ScalePx);
    Cv.Brush.Style := bsClear;
    Cv.Pen.Style := psDot;
    Cv.Pen.Color := RGBToColor(78, 118, 152);
    Cv.Ellipse(Cx1 - RReach, Cy1 - RReach, Cx1 + RReach, Cy1 + RReach);
    Cv.Ellipse(Cx2 - RReach, Cy2 - RReach, Cx2 + RReach, Cy2 + RReach);
    Cv.Pen.Style := psSolid;

    for I := 0 to Rig.JointCount - 2 do
    begin
      A := Rig.JointWorldPos(I) - RootP;
      B := Rig.JointWorldPos(I + 1) - RootP;
      Cv.Pen.Width := 3;
      Cv.Pen.Color := RGBToColor(80, 215, 245);
      Cv.Line(Cx1 + Round(A.Z * ScalePx), Cy1 - Round(A.Y * ScalePx),
              Cx1 + Round(B.Z * ScalePx), Cy1 - Round(B.Y * ScalePx));
      Cv.Line(Cx2 + Round(A.X * ScalePx), Cy2 + Round(A.Z * ScalePx),
              Cx2 + Round(B.X * ScalePx), Cy2 + Round(B.Z * ScalePx));
    end;
    Cv.Pen.Width := 1;

    Cv.Brush.Style := bsSolid;
    for I := 0 to Rig.JointCount - 1 do
    begin
      A := Rig.JointWorldPos(I) - RootP;
      Cv.Brush.Color := RGBToColor(255, 210, 75);
      Cv.Pen.Color := clWhite;
      Cv.Ellipse(Cx1 + Round(A.Z * ScalePx) - 4, Cy1 - Round(A.Y * ScalePx) - 4,
                 Cx1 + Round(A.Z * ScalePx) + 4, Cy1 - Round(A.Y * ScalePx) + 4);
      Cv.Ellipse(Cx2 + Round(A.X * ScalePx) - 4, Cy2 + Round(A.Z * ScalePx) - 4,
                 Cx2 + Round(A.X * ScalePx) + 4, Cy2 + Round(A.Z * ScalePx) + 4);
    end;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(10, 8, 'Side Elevation (ZY) + Reach Sphere');
  Cv.TextOut(HalfW + 10, 8, 'Top Plan (XZ) + Reach Sphere');
end;

end.
