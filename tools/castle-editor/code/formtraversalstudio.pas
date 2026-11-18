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

{ Interactive Parkour Traversal Ledge/Vault/Mantle Scanner & Root-Motion Warp
  Anchor Studio dialog (Phase 349). }
unit FormTraversalStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, StrUtils,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleTraversalParkour, ToolTraversalStudio;

type
  TTraversalModifyCallback = procedure(const AUndoComment: String) of object;
  TTraversalRefreshCallback = procedure of object;

  TTraversalStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TTraversalModifyCallback;
    FOnRefreshViewport: TTraversalRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintArc: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure MoveRunnerAndScan(const ALaneX: Single; const ALabel: String);
    procedure BtnSpawnGymClick(Sender: TObject);
    procedure BtnLaneStepClick(Sender: TObject);
    procedure BtnLaneVaultClick(Sender: TObject);
    procedure BtnLaneMantleClick(Sender: TObject);
    procedure BtnLaneClimbClick(Sender: TObject);
    procedure BtnLaneWallClick(Sender: TObject);
    procedure BtnExecuteWarpClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintArcPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TTraversalModifyCallback;
      const AOnRefreshViewport: TTraversalRefreshCallback);
  end;

implementation

constructor TTraversalStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TTraversalModifyCallback;
  const AOnRefreshViewport: TTraversalRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Parkour Traversal Ledge/Vault/Mantle Scanner & Root-Motion Warp Studio (UE 6.0+ GASP Parity)';
  Width := 1060;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TTraversalStudioForm.BuildUi;
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
  TopBar.Height := 128;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'Parkour Traversal Ray-Scanner — StepUp / ThinVault / LowMantle / HighClimb Classification & Bezier Root-Motion Warp Anchors';

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
  MakeBtn(BtnRow1, '+ Spawn 5-Lane Parkour Gym', @BtnSpawnGymClick, 192);
  MakeBtn(BtnRow1, '1. Curb Step (0.4m)', @BtnLaneStepClick, 152);
  MakeBtn(BtnRow1, '2. Thin Vault (1.05m)', @BtnLaneVaultClick, 160);
  MakeBtn(BtnRow1, '3. Crate Mantle (1.2m)', @BtnLaneMantleClick, 166);
  MakeBtn(BtnRow1, '4. High Climb (2.2m)', @BtnLaneClimbClick, 158);
  MakeBtn(BtnRow1, '5. Sheer Wall (3.8m)', @BtnLaneWallClick, 158);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Execute Root-Motion Warp', @BtnExecuteWarpClick, 188);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 184);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 410;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintArc := TPaintBox.Create(Self);
  PaintArc.Parent := BodyPanel;
  PaintArc.Align := alClient;
  PaintArc.BorderSpacing.Around := 6;
  PaintArc.OnPaint := @PaintArcPaint;
end;

procedure TTraversalStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TTraversalStudioForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TTraversalStudioSummary;
begin
  Warnings := TStringList.Create;
  try
    Sum := TTraversalStudioHelper.CollectSummary(FDesignRoot, Warnings);
    LabelTelemetry.Caption := Format(
      'Action: %s | Montage: %s | Obstacle H: %.2fm | Top Depth: %.2fm',
      [Sum.LastActionName, IfThen(Sum.LastMontageId <> '', Sum.LastMontageId, '-'),
       Sum.LastObstacleHeight, Sum.LastObstacleDepth]);
    MemoReport.Lines.Text := TTraversalStudioHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintArc.Invalidate;
end;

procedure TTraversalStudioForm.MoveRunnerAndScan(const ALaneX: Single;
  const ALabel: String);
var
  Runner: TCastleTransform;
  T: TCastleTraversalBehavior;
  RootT: TCastleAbstractRootTransform;
begin
  T := TTraversalStudioHelper.FindFirstTraversal(FDesignRoot);
  if T = nil then
    TTraversalStudioHelper.SpawnParkourGymCourseDemo(FDesignRoot, FDesignOwner, Runner, T);
  RootT := TTraversalStudioHelper.ResolveRootTransform(FDesignRoot);
  if (T = nil) or (T.Parent = nil) or (RootT = nil) then Exit;

  T.Parent.Translation := Vector3(ALaneX, 0.0, 0.0);
  T.ScanFromParent(RootT, Vector3(0.0, 0.0, -1.0));
  NotifyChange(ALabel);
end;

procedure TTraversalStudioForm.BtnSpawnGymClick(Sender: TObject);
var
  Runner: TCastleTransform;
  T: TCastleTraversalBehavior;
begin
  if TTraversalStudioHelper.SpawnParkourGymCourseDemo(FDesignRoot, FDesignOwner, Runner, T) then
    NotifyChange('Spawn 5-Lane Parkour Traversal Gym');
end;

procedure TTraversalStudioForm.BtnLaneStepClick(Sender: TObject);
begin
  MoveRunnerAndScan(-8.0, 'Scan Parkour Lane 1: Curb StepUp');
end;

procedure TTraversalStudioForm.BtnLaneVaultClick(Sender: TObject);
begin
  MoveRunnerAndScan(-4.0, 'Scan Parkour Lane 2: Thin Barrier Vault');
end;

procedure TTraversalStudioForm.BtnLaneMantleClick(Sender: TObject);
begin
  MoveRunnerAndScan(0.0, 'Scan Parkour Lane 3: Crate Mantle');
end;

procedure TTraversalStudioForm.BtnLaneClimbClick(Sender: TObject);
begin
  MoveRunnerAndScan(+4.0, 'Scan Parkour Lane 4: High Ledge Climb');
end;

procedure TTraversalStudioForm.BtnLaneWallClick(Sender: TObject);
begin
  MoveRunnerAndScan(+8.0, 'Scan Parkour Lane 5: Sheer Blocked Wall');
end;

procedure TTraversalStudioForm.BtnExecuteWarpClick(Sender: TObject);
var
  T: TCastleTraversalBehavior;
begin
  T := TTraversalStudioHelper.FindFirstTraversal(FDesignRoot);
  if (T = nil) or (T.Parent = nil) then Exit;
  if T.BeginTraversalWarp(T.Parent.Translation, T.LastProbe) then
  begin
    T.StepTraversalWarp(T.WarpDurationSec);
    NotifyChange('Execute Parkour Root-Motion Warp');
  end;
end;

procedure TTraversalStudioForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'parkour_traversal_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TTraversalStudioHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TTraversalStudioForm.PaintArcPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, GroundY, StartX, ObsX, ObsW, ObsH, I, X0, Y0, X1, Y1: Integer;
  T: TCastleTraversalBehavior;
  P: TTraversalProbeResult;
  ScalePx: Single;
  StartW, Pt0, Pt1: TVector3;
begin
  Cv := PaintArc.Canvas;
  W := Max(200, PaintArc.Width);
  H := Max(200, PaintArc.Height);
  GroundY := H - 64;
  StartX := 96;
  ScalePx := 92.0;

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);
  Cv.Pen.Color := RGBToColor(68, 82, 104);
  Cv.Line(20, GroundY, W - 20, GroundY);

  T := TTraversalStudioHelper.FindFirstTraversal(FDesignRoot);
  if T <> nil then
  begin
    P := T.LastProbe;
    if P.HasObstacle then
    begin
      ObsX := StartX + Round(P.ForwardDistance * ScalePx);
      ObsW := Max(18, Round(Min(2.8, P.ObstacleTopDepth) * ScalePx));
      ObsH := EnsureRange(Round(P.ObstacleHeightAboveFeet * ScalePx), 12, GroundY - 40);

      Cv.Brush.Color := RGBToColor(58, 76, 104);
      Cv.Pen.Color := RGBToColor(112, 144, 186);
      Cv.Rectangle(ObsX, GroundY - ObsH, ObsX + ObsW, GroundY);

      { Bezier root-motion warp trajectory }
      StartW := Vector3(P.FrontEdgeAnchorWorld.X, P.FrontEdgeAnchorWorld.Y - P.ObstacleHeightAboveFeet,
        P.FrontEdgeAnchorWorld.Z + P.ForwardDistance);
      if P.Action in [takStepUp, takThinVaultOver, takLowMantleOnto, takHighLedgeClimb] then
      begin
        Cv.Pen.Color := RGBToColor(78, 228, 138);
        Cv.Pen.Width := 3;
        for I := 0 to 23 do
        begin
          Pt0 := TCastleTraversalBehavior.EvaluateWarpTrajectory(StartW, P, I / 24.0);
          Pt1 := TCastleTraversalBehavior.EvaluateWarpTrajectory(StartW, P, (I + 1) / 24.0);
          X0 := StartX + Round((StartW.Z - Pt0.Z) * ScalePx);
          Y0 := GroundY - Round((Pt0.Y - StartW.Y) * ScalePx);
          X1 := StartX + Round((StartW.Z - Pt1.Z) * ScalePx);
          Y1 := GroundY - Round((Pt1.Y - StartW.Y) * ScalePx);
          Cv.Line(X0, Y0, X1, Y1);
        end;
        Cv.Pen.Width := 1;
      end;
    end;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(16, 10, 'Side-Profile Obstacle Cross-Section & Bezier Root-Motion Warp Arc');
  Cv.Font.Style := [];
end;

end.
