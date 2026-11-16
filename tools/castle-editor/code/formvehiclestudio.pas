{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Interactive Chaos-Style Wheeled Vehicle, Raycast Spring-Damper Suspension,
  Ackermann Steering & Multi-Gear Drivetrain Studio (@link(TVehicleStudioForm))
  featuring 1-click Rally / Monster Truck / Recon Buggy & Test-Track spawners,
  interactive Throttle / Steer / Brake / Handbrake bench controls, a live dual
  Top-Down 4-Wheel Ackermann + Suspension Telemetry & Engine Torque Curve
  canvas, and Markdown export (Phase 317). }
unit FormVehicleStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleVehicleSystem, ToolVehicleStudio;

type
  TVehicleStudioModifiedCallback = procedure(const AComment: String) of object;
  TVehicleStudioRefreshViewportCallback = procedure of object;

  TVehicleStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TVehicleStudioModifiedCallback;
    FOnRefreshViewport: TVehicleStudioRefreshViewportCallback;

    FVehicles: TVehicleArray;
    FReport: TVehicleAuditReport;

    LblHeader: TLabel;
    ListVehicles: TListBox;
    PaintTelemetry: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function SelectedVehicle: TCastleWheeledVehicle;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnSpawnRallyCarClick(Sender: TObject);
    procedure BtnSpawnMonsterTruckClick(Sender: TObject);
    procedure BtnSpawnReconBuggyClick(Sender: TObject);
    procedure BtnSpawnTrackRampClick(Sender: TObject);
    procedure BtnDriveStraightClick(Sender: TObject);
    procedure BtnSteerRightClick(Sender: TObject);
    procedure BtnHandbrakeDriftClick(Sender: TObject);
    procedure BtnResetVehicleClick(Sender: TObject);
    procedure BtnStepPointOneClick(Sender: TObject);
    procedure BtnStepOneSecClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure ListVehiclesClick(Sender: TObject);
    procedure PaintTelemetryPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TVehicleStudioModifiedCallback;
      const AOnRefreshViewport: TVehicleStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TVehicleStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TVehicleStudioModifiedCallback;
  const AOnRefreshViewport: TVehicleStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Chaos Wheeled Vehicle, Raycast Suspension, Ackermann Steering & Drivetrain Studio';
  Width := 1140;
  Height := 710;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TVehicleStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TVehicleStudioForm.BuildUi;
var
  PanelTop, Row1, Row2, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  BtnClose: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 104;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.SetBounds(12, 8, 1080, 20);
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Wheeled Vehicles: scanning...';

  Row1 := TPanel.Create(Self);
  Row1.Parent := PanelTop;
  Row1.SetBounds(8, 32, 1120, 32);
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Rally Sports Car (AWD)', 4, 2, 185, @BtnSpawnRallyCarClick);
  MakeBtn(Row1, '+ Monster Truck (4x4)', 195, 2, 175, @BtnSpawnMonsterTruckClick);
  MakeBtn(Row1, '+ Recon Buggy (RWD)', 376, 2, 168, @BtnSpawnReconBuggyClick);
  MakeBtn(Row1, '+ Test Track + Jump Ramp', 550, 2, 190, @BtnSpawnTrackRampClick);
  MakeBtn(Row1, 'Copy Markdown Report', 748, 2, 175, @BtnCopyMarkdownClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := PanelTop;
  Row2.SetBounds(8, 68, 1120, 32);
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Full Throttle Straight', 4, 2, 165, @BtnDriveStraightClick);
  MakeBtn(Row2, 'Ackermann Right Turn', 175, 2, 165, @BtnSteerRightClick);
  MakeBtn(Row2, 'Handbrake Drift!', 346, 2, 145, @BtnHandbrakeDriftClick);
  MakeBtn(Row2, 'Reset Kinematics', 497, 2, 140, @BtnResetVehicleClick);
  MakeBtn(Row2, 'Step Vehicle (+0.1s)', 645, 2, 165, @BtnStepPointOneClick);
  MakeBtn(Row2, 'Step Burst (+1.0s)', 816, 2, 155, @BtnStepOneSecClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PanelBottom;
  BtnClose.Caption := 'Close';
  BtnClose.Width := 110;
  BtnClose.Height := 28;
  BtnClose.Top := 7;
  BtnClose.Left := Width - 130;
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.OnClick := @BtnCloseClick;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 340;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Vehicles in Design:';

  ListVehicles := TListBox.Create(Self);
  ListVehicles.Parent := PanelLeft;
  ListVehicles.SetBounds(10, 26, 320, 230);
  ListVehicles.OnClick := @ListVehiclesClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 264, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Suspension, Slip & Drivetrain QA:';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelLeft;
  MemoDiag.SetBounds(10, 286, 320, 265);
  MemoDiag.Anchors := [akTop, akLeft, akBottom];
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintTelemetry := TPaintBox.Create(Self);
  PaintTelemetry.Parent := PanelCenter;
  PaintTelemetry.Align := alClient;
  PaintTelemetry.OnPaint := @PaintTelemetryPaint;
end;

function TVehicleStudioForm.SelectedVehicle: TCastleWheeledVehicle;
var
  Idx: Integer;
begin
  Result := nil;
  Idx := ListVehicles.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FVehicles)) then
    Result := FVehicles[Idx];
end;

procedure TVehicleStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TVehicleStudioForm.RefreshAll;
var
  SavedIdx, I: Integer;
  V: TCastleWheeledVehicle;
  W: TWheelTelemetry;
begin
  SavedIdx := ListVehicles.ItemIndex;
  TVehicleStudioHelper.ScanVehicles(FDesignRoot, FDesignOwner, FVehicles);
  FreeAndNil(FReport);
  FReport := TVehicleStudioHelper.AuditVehicles(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'Wheeled Vehicles: %d  |  Grounded Vehicles: %d (%d wheels)  |  Peak Speed: %.1f km/h  |  QA Warnings: %d',
    [FReport.VehicleCount, FReport.GroundedVehicleCount, FReport.TotalGroundedWheels,
     FReport.MaxSpeedKmh, FReport.Warnings.Count]);

  ListVehicles.Items.BeginUpdate;
  try
    ListVehicles.Items.Clear;
    for I := 0 to High(FVehicles) do
      ListVehicles.Items.Add(Format('%s  %s', [FVehicles[I].Name, FVehicles[I].VehicleSummaryBadge]));
  finally
    ListVehicles.Items.EndUpdate;
  end;

  if ListVehicles.Items.Count > 0 then
    ListVehicles.ItemIndex := Clamped(Max(0, SavedIdx), 0, ListVehicles.Items.Count - 1);

  MemoDiag.Lines.BeginUpdate;
  try
    MemoDiag.Lines.Clear;
    V := SelectedVehicle;
    if V <> nil then
    begin
      MemoDiag.Lines.Add(Format('Selected: %s (%s)', [V.Name, TCastleWheeledVehicle.PresetDisplayName(V.Preset)]));
      MemoDiag.Lines.Add(Format('Speed: %.1f km/h  |  Gear: G%d (%.2fx)  |  RPM: %.0f',
        [V.ForwardSpeedKmh, V.CurrentGear, V.CurrentGearRatio, V.EngineRpm]));
      MemoDiag.Lines.Add(Format('Inputs: Thr=%.2f  Steer=%.2f  Brk=%.2f  HB=%.2f',
        [V.ThrottleInput, V.SteerInput, V.BrakeInput, V.HandbrakeInput]));
      MemoDiag.Lines.Add('');
      for I := 0 to 3 do
      begin
        W := V.GetWheelTelemetry(I);
        MemoDiag.Lines.Add(Format('%s: Comp=%.0f%% (%.2fm) Fn=%.0fN Steer=%.1f° Slip=%.1f°',
          [W.WheelName, W.CompressionRatio * 100.0, W.CompressionMeters,
           W.NormalForceN, W.SteerAngleDeg, W.SlipAngleDeg]));
      end;
      MemoDiag.Lines.Add('');
    end;
    if FReport.Warnings.Count = 0 then
      MemoDiag.Lines.Add('[OK] All vehicle suspension springs & ground contacts healthy.')
    else
      for I := 0 to FReport.Warnings.Count - 1 do
        MemoDiag.Lines.Add('[WARN] ' + FReport.Warnings[I]);
  finally
    MemoDiag.Lines.EndUpdate;
  end;

  PaintTelemetry.Invalidate;
end;

procedure TVehicleStudioForm.BtnSpawnRallyCarClick(Sender: TObject);
begin
  TVehicleStudioHelper.SpawnTestTrackFloorAndRamp(FDesignRoot, FDesignOwner);
  TVehicleStudioHelper.SpawnVehicleInDesign(FDesignRoot, FDesignOwner, vpRallySportsCar, Vector3(-3.0, 0.0, 0.0));
  NotifyChanged('Spawn Rally Sports Car (AWD)');
end;

procedure TVehicleStudioForm.BtnSpawnMonsterTruckClick(Sender: TObject);
begin
  TVehicleStudioHelper.SpawnTestTrackFloorAndRamp(FDesignRoot, FDesignOwner);
  TVehicleStudioHelper.SpawnVehicleInDesign(FDesignRoot, FDesignOwner, vpOffroadMonsterTruck, Vector3(0.0, 0.0, 0.0));
  NotifyChanged('Spawn Offroad Monster Truck (4x4)');
end;

procedure TVehicleStudioForm.BtnSpawnReconBuggyClick(Sender: TObject);
begin
  TVehicleStudioHelper.SpawnTestTrackFloorAndRamp(FDesignRoot, FDesignOwner);
  TVehicleStudioHelper.SpawnVehicleInDesign(FDesignRoot, FDesignOwner, vpArmoredReconBuggy, Vector3(3.0, 0.0, 0.0));
  NotifyChanged('Spawn Armored Recon Buggy (RWD)');
end;

procedure TVehicleStudioForm.BtnSpawnTrackRampClick(Sender: TObject);
begin
  TVehicleStudioHelper.SpawnTestTrackFloorAndRamp(FDesignRoot, FDesignOwner);
  NotifyChanged('Spawn Vehicle Test Track & Jump Ramp');
end;

procedure TVehicleStudioForm.BtnDriveStraightClick(Sender: TObject);
var
  V: TCastleWheeledVehicle;
begin
  V := SelectedVehicle;
  if V = nil then Exit;
  V.ThrottleInput := 1.0;
  V.SteerInput := 0.0;
  V.BrakeInput := 0.0;
  V.HandbrakeInput := 0.0;
  NotifyChanged('Set Full Throttle Straight');
end;

procedure TVehicleStudioForm.BtnSteerRightClick(Sender: TObject);
var
  V: TCastleWheeledVehicle;
begin
  V := SelectedVehicle;
  if V = nil then Exit;
  V.ThrottleInput := 0.75;
  V.SteerInput := 0.85;
  V.BrakeInput := 0.0;
  V.HandbrakeInput := 0.0;
  NotifyChanged('Set Ackermann Right Turn');
end;

procedure TVehicleStudioForm.BtnHandbrakeDriftClick(Sender: TObject);
var
  V: TCastleWheeledVehicle;
begin
  V := SelectedVehicle;
  if V = nil then Exit;
  V.ThrottleInput := 0.85;
  V.SteerInput := 0.90;
  V.BrakeInput := 0.0;
  V.HandbrakeInput := 1.0;
  NotifyChanged('Engage Handbrake Drift');
end;

procedure TVehicleStudioForm.BtnResetVehicleClick(Sender: TObject);
var
  V: TCastleWheeledVehicle;
begin
  V := SelectedVehicle;
  if V = nil then Exit;
  V.ThrottleInput := 0.0;
  V.SteerInput := 0.0;
  V.BrakeInput := 0.0;
  V.HandbrakeInput := 0.0;
  V.Rotation := Vector4(0.0, 1.0, 0.0, 0.0);
  V.Translation := Vector3(V.Translation.X,
    V.SuspensionRestLength + V.WheelRadius * 0.92, 0.0);
  V.ResetKinematics;
  NotifyChanged('Reset Vehicle Kinematics');
end;

procedure TVehicleStudioForm.BtnStepPointOneClick(Sender: TObject);
begin
  TVehicleStudioHelper.StepAllVehicles(FDesignRoot, FDesignOwner, 0.10);
  NotifyChanged('Step Wheeled Vehicles (+0.1s)');
end;

procedure TVehicleStudioForm.BtnStepOneSecClick(Sender: TObject);
var
  K: Integer;
begin
  for K := 1 to 10 do
    TVehicleStudioHelper.StepAllVehicles(FDesignRoot, FDesignOwner, 0.10);
  NotifyChanged('Step Wheeled Vehicles (+1.0s)');
end;

procedure TVehicleStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TVehicleStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TVehicleStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TVehicleStudioForm.ListVehiclesClick(Sender: TObject);
begin
  RefreshAll;
end;

procedure TVehicleStudioForm.PaintTelemetryPaint(Sender: TObject);
var
  C: TCanvas;
  V: TCastleWheeledVehicle;
  MidX, W, H, Cx, Cy, BodyW, BodyH, I, Wx, Wy, BarH: Integer;
  WTel: TWheelTelemetry;
  AngRad, Dx, Dy: Single;
  PlotL, PlotR, PlotT, PlotB, Px, Py, PrevPx, PrevPy, StepIdx: Integer;
  SampleRpm, SampleTq, MaxPlotRpm: Single;
begin
  C := PaintTelemetry.Canvas;
  W := Max(200, PaintTelemetry.Width);
  H := Max(200, PaintTelemetry.Height);

  C.Brush.Color := RGBToColor(22, 26, 33);
  C.FillRect(0, 0, W, H);

  V := SelectedVehicle;
  if V = nil then
  begin
    C.Font.Color := RGBToColor(190, 200, 215);
    C.TextOut(24, 24, 'Click "+ Rally Sports Car (AWD)" above to inspect 4-wheel suspension & drivetrain telemetry.');
    Exit;
  end;

  MidX := W div 2;

  { Left panel: Top-Down 4-Wheel Ackermann Steering & Suspension Compression }
  C.Font.Color := RGBToColor(230, 238, 248);
  C.Font.Style := [fsBold];
  C.TextOut(16, 12, 'Top-Down Ackermann Steering & Suspension Load');
  C.Font.Style := [];

  Cx := MidX div 2;
  Cy := H div 2 + 10;
  BodyW := 96;
  BodyH := 176;

  C.Pen.Color := RGBToColor(90, 115, 145);
  C.Brush.Color := RGBToColor(38, 46, 58);
  C.RoundRect(Cx - BodyW div 2, Cy - BodyH div 2, Cx + BodyW div 2, Cy + BodyH div 2, 14, 14);

  for I := 0 to 3 do
  begin
    WTel := V.GetWheelTelemetry(I);
    if WTel.IsLeftSide then
      Wx := Cx - BodyW div 2 - 18
    else
      Wx := Cx + BodyW div 2 + 18;
    if WTel.IsFrontAxle then
      Wy := Cy - BodyH div 2 + 26
    else
      Wy := Cy + BodyH div 2 - 26;

    { Draw oriented wheel vector }
    AngRad := DegToRad(WTel.SteerAngleDeg);
    Dx := Sin(AngRad) * 20.0;
    Dy := -Cos(AngRad) * 20.0;
    C.Pen.Width := 6;
    if WTel.IsGrounded then
      C.Pen.Color := RGBToColor(58, 218, 142)
    else
      C.Pen.Color := RGBToColor(235, 90, 90);
    C.Line(Round(Wx - Dx), Round(Wy - Dy), Round(Wx + Dx), Round(Wy + Dy));
    C.Pen.Width := 1;

    { Draw compression bar next to wheel }
    BarH := Round(Clamped(WTel.CompressionRatio, 0.0, 1.0) * 38.0);
    C.Brush.Color := RGBToColor(45, 52, 64);
    C.FillRect(Wx - 6, Wy + 24, Wx + 6, Wy + 62);
    C.Brush.Color := RGBToColor(64, 178, 245);
    C.FillRect(Wx - 6, Wy + 62 - BarH, Wx + 6, Wy + 62);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(200, 212, 228);
    C.TextOut(Wx - 22, Wy + 65, Format('%.1f°', [WTel.SteerAngleDeg]));
  end;

  { Right panel: Engine Torque Curve & Live RPM / Gear Indicator }
  PlotL := MidX + 36;
  PlotR := W - 24;
  PlotT := 52;
  PlotB := H - 64;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(230, 238, 248);
  C.TextOut(PlotL, 12, Format('Engine Torque Curve (Peak %.0f Nm @ %.0f RPM)',
    [V.PeakTorqueNm, V.PeakTorqueRpm]));
  C.Font.Style := [];

  C.Pen.Color := RGBToColor(68, 78, 96);
  C.Brush.Color := RGBToColor(28, 33, 42);
  C.Rectangle(PlotL, PlotT, PlotR, PlotB);

  MaxPlotRpm := Max(2000.0, V.RedlineRpm * 1.08);
  PrevPx := PlotL;
  PrevPy := PlotB;
  C.Pen.Color := RGBToColor(245, 174, 56);
  C.Pen.Width := 2;
  for StepIdx := 0 to 60 do
  begin
    SampleRpm := (StepIdx / 60.0) * MaxPlotRpm;
    SampleTq := EvaluateEngineTorqueCurveNm(SampleRpm, V.IdleRpm,
      V.PeakTorqueRpm, V.RedlineRpm, V.PeakTorqueNm);
    Px := PlotL + Round((StepIdx / 60.0) * (PlotR - PlotL));
    Py := PlotB - Round(Clamped(SampleTq / Max(1.0, V.PeakTorqueNm * 1.1), 0.0, 1.0) * (PlotB - PlotT));
    if StepIdx > 0 then
      C.Line(PrevPx, PrevPy, Px, Py);
    PrevPx := Px;
    PrevPy := Py;
  end;
  C.Pen.Width := 1;

  { Live operating RPM vertical marker }
  Px := PlotL + Round(Clamped(V.EngineRpm / MaxPlotRpm, 0.0, 1.0) * (PlotR - PlotL));
  C.Pen.Color := RGBToColor(72, 230, 152);
  C.Line(Px, PlotT, Px, PlotB);
  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(120, 240, 180);
  C.TextOut(PlotL, PlotB + 12, Format('Speed: %.1f km/h  |  Gear: G%d  |  Engine: %.0f / %.0f RPM',
    [V.ForwardSpeedKmh, V.CurrentGear, V.EngineRpm, V.RedlineRpm]));
end;

end.
