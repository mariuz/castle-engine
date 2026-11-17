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

{ Interactive Spring-Arm Camera Collision Whisker Probe, Instant Pull-In &
  Smooth Lagged Boom Recovery Studio dialog (Phase 339). }
unit FormSpringArm;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleSpringArm, ToolSpringArm;

type
  TSpringArmModifyCallback = procedure(const AUndoComment: String) of object;
  TSpringArmRefreshCallback = procedure of object;

  TSpringArmForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSpringArmModifyCallback;
    FOnRefreshViewport: TSpringArmRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintBoom: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure MoveCorridorWallZ(const AZ: Single; const ADt: Single; const AComment: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnWallCloseClick(Sender: TObject);
    procedure BtnWallClearClick(Sender: TObject);
    procedure BtnStepEaseClick(Sender: TObject);
    procedure BtnOrbitYawClick(Sender: TObject);
    procedure BtnSwapShoulderClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintBoomPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSpringArmModifyCallback;
      const AOnRefreshViewport: TSpringArmRefreshCallback);
  end;

implementation

constructor TSpringArmForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSpringArmModifyCallback;
  const AOnRefreshViewport: TSpringArmRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Spring-Arm Camera Whisker Occlusion, Pull-In & Lag Recovery Studio (UE 6.0+ USpringArmComponent Parity)';
  Width := 1020;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TSpringArmForm.BuildUi;
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
  LabelHeader.Caption := 'Spring-Arm Camera Collision Boom — 5-Whisker Ray Bundle, Instant Wall Pull-In, Smooth Ease-Out & Shoulder Swap';

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
  MakeBtn(BtnRow1, '+ Spawn Hero + Corridor Wall', @BtnSpawnDemoClick, 192);
  MakeBtn(BtnRow1, 'Slide Wall In (2.0m: Pull-In!)', @BtnWallCloseClick, 185);
  MakeBtn(BtnRow1, 'Clear Wall (12m: Open)', @BtnWallClearClick, 168);
  MakeBtn(BtnRow1, 'Step Recovery (+0.15s)', @BtnStepEaseClick, 168);
  MakeBtn(BtnRow1, 'Orbit Yaw +30°', @BtnOrbitYawClick, 132);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Swap Over-Shoulder (±0.45m)', @BtnSwapShoulderClick, 195);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 182);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 380;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintBoom := TPaintBox.Create(Self);
  PaintBoom.Parent := BodyPanel;
  PaintBoom.Align := alClient;
  PaintBoom.BorderSpacing.Around := 6;
  PaintBoom.OnPaint := @PaintBoomPaint;
end;

procedure TSpringArmForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TSpringArmForm.RefreshUi;
var
  SA: TCastleSpringArm;
begin
  SA := TSpringArmHelper.FindFirstSpringArm(FDesignRoot);
  if SA <> nil then
    LabelTelemetry.Caption := Format(
      '%s | Arm: %.2f / %.2f m (Compression: %.0f%%) | Occluded: %s (%d/5 whiskers) | Cam: (%.2f, %.2f, %.2f)',
      [SA.Name, SA.CurrentArmLength, SA.TargetArmLength,
       SA.CompressionRatio * 100.0, BoolToStr(SA.IsOccluded, 'YES', 'No'),
       SA.BlockedWhiskerCount, SA.SolvedCameraWorldPos.X,
       SA.SolvedCameraWorldPos.Y, SA.SolvedCameraWorldPos.Z])
  else
    LabelTelemetry.Caption := 'No TCastleSpringArm in design — click "+ Spawn Hero + Corridor Wall" to create a demo rig.';

  MemoReport.Lines.Text := TSpringArmHelper.BuildMarkdownReport(FDesignRoot);
  PaintBoom.Invalidate;
end;

procedure TSpringArmForm.MoveCorridorWallZ(const AZ, ADt: Single;
  const AComment: String);
var
  SA: TCastleSpringArm;
  RootT: TCastleTransform;
  Comp: TComponent;
begin
  SA := TSpringArmHelper.FindFirstSpringArm(FDesignRoot);
  RootT := TSpringArmHelper.ResolveRootTransform(FDesignRoot);
  if (SA = nil) or (RootT = nil) then Exit;
  if FDesignOwner <> nil then
  begin
    Comp := FDesignOwner.FindComponent('SpringArmCorridorWall');
    if Comp is TCastleTransform then
      TCastleTransform(Comp).Translation := Vector3(0.0, 0.0, AZ);
  end;
  SA.StepSpringArm(ADt, RootT.World);
  NotifyChange(AComment);
end;

procedure TSpringArmForm.BtnSpawnDemoClick(Sender: TObject);
var
  Hero, Wall: TCastleTransform;
  SA: TCastleSpringArm;
begin
  if TSpringArmHelper.SpawnThirdPersonSpringArmCorridorDemo(FDesignRoot, FDesignOwner, Hero, Wall, SA) then
    NotifyChange('Spawn Third-Person SpringArm Corridor');
end;

procedure TSpringArmForm.BtnWallCloseClick(Sender: TObject);
begin
  MoveCorridorWallZ(2.0, 0.016, 'SpringArm Instant Wall Pull-In');
end;

procedure TSpringArmForm.BtnWallClearClick(Sender: TObject);
begin
  MoveCorridorWallZ(12.0, 0.05, 'SpringArm Clear Wall Obstacle');
end;

procedure TSpringArmForm.BtnStepEaseClick(Sender: TObject);
var
  SA: TCastleSpringArm;
  RootT: TCastleTransform;
begin
  SA := TSpringArmHelper.FindFirstSpringArm(FDesignRoot);
  RootT := TSpringArmHelper.ResolveRootTransform(FDesignRoot);
  if (SA = nil) or (RootT = nil) then Exit;
  SA.StepSpringArm(0.15, RootT.World);
  NotifyChange('Step SpringArm Recovery +0.15s');
end;

procedure TSpringArmForm.BtnOrbitYawClick(Sender: TObject);
var
  SA: TCastleSpringArm;
  RootT: TCastleTransform;
begin
  SA := TSpringArmHelper.FindFirstSpringArm(FDesignRoot);
  RootT := TSpringArmHelper.ResolveRootTransform(FDesignRoot);
  if (SA = nil) or (RootT = nil) then Exit;
  SA.YawDeg := SA.YawDeg + 30.0;
  SA.StepSpringArm(0.05, RootT.World);
  NotifyChange('Orbit SpringArm Yaw +30°');
end;

procedure TSpringArmForm.BtnSwapShoulderClick(Sender: TObject);
var
  SA: TCastleSpringArm;
  RootT: TCastleTransform;
begin
  SA := TSpringArmHelper.FindFirstSpringArm(FDesignRoot);
  RootT := TSpringArmHelper.ResolveRootTransform(FDesignRoot);
  if (SA = nil) or (RootT = nil) then Exit;
  if SA.ShoulderOffsetX >= 0.0 then
    SA.ShoulderOffsetX := -0.45
  else
    SA.ShoulderOffsetX := +0.45;
  SA.StepSpringArm(0.05, RootT.World);
  NotifyChange('Swap SpringArm Over-Shoulder Offset');
end;

procedure TSpringArmForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'spring_arm_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TSpringArmHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TSpringArmForm.PaintBoomPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, Cx, Cy, I, RTarget, CamX, CamY, AncX, AncY: Integer;
  SA: TCastleSpringArm;
  ScalePx: Single;
  Origin, CamRel: TVector3;
  Ray: TSpringArmWhiskerRay;
begin
  Cv := PaintBoom.Canvas;
  W := Max(120, PaintBoom.Width);
  H := Max(120, PaintBoom.Height);
  Cx := W div 2;
  Cy := H div 2;

  Cv.Brush.Color := RGBToColor(18, 22, 28);
  Cv.FillRect(0, 0, W, H);

  SA := TSpringArmHelper.FindFirstSpringArm(FDesignRoot);
  if SA <> nil then
  begin
    Origin := SA.SolvedAnchorWorldPos;
    ScalePx := Min(W, H) / Max(6.0, SA.TargetArmLength * 2.6);
    RTarget := Round(SA.TargetArmLength * ScalePx);

    Cv.Brush.Style := bsClear;
    Cv.Pen.Style := psDot;
    Cv.Pen.Color := RGBToColor(80, 120, 160);
    Cv.Ellipse(Cx - RTarget, Cy - RTarget, Cx + RTarget, Cy + RTarget);
    Cv.Pen.Style := psSolid;

    { 5 Whiskers }
    for I := 0 to 4 do
    begin
      Ray := SA.GetWhisker(I);
      if Ray.Blocked then
        Cv.Pen.Color := RGBToColor(255, 110, 65)
      else
        Cv.Pen.Color := RGBToColor(85, 190, 245);
      Cv.Line(
        Cx + Round((Ray.OriginWorld.X - Origin.X) * ScalePx),
        Cy + Round((Ray.OriginWorld.Z - Origin.Z) * ScalePx),
        Cx + Round((Ray.EndWorld.X - Origin.X) * ScalePx),
        Cy + Round((Ray.EndWorld.Z - Origin.Z) * ScalePx));
    end;

    { Solved Camera Boom }
    CamRel := SA.SolvedCameraWorldPos - Origin;
    AncX := Cx;
    AncY := Cy;
    CamX := Cx + Round(CamRel.X * ScalePx);
    CamY := Cy + Round(CamRel.Z * ScalePx);
    Cv.Pen.Width := 3;
    if SA.IsOccluded then
      Cv.Pen.Color := RGBToColor(255, 75, 75)
    else
      Cv.Pen.Color := RGBToColor(95, 240, 145);
    Cv.Line(AncX, AncY, CamX, CamY);
    Cv.Pen.Width := 1;

    Cv.Brush.Style := bsSolid;
    Cv.Brush.Color := RGBToColor(70, 195, 255);
    Cv.Ellipse(AncX - 6, AncY - 6, AncX + 6, AncY + 6);
    Cv.Brush.Color := RGBToColor(255, 215, 75);
    Cv.Ellipse(CamX - 7, CamY - 7, CamX + 7, CamY + 7);
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 8, 'Top-Down XZ Spring-Arm 5-Whisker Probe (Cyan = Pivot, Gold = Solved Camera, Orange = Blocked Whisker)');
end;

end.
