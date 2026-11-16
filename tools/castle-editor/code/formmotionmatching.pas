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

{ Motion Matching & Pose Search Trajectory Visualizer, Inertialization Decay
  Inspector & Stride Warping Studio Dialog (@link(TMotionMatchingForm))
  (Phase 327 — UE 6.0+ Pose Search & Motion Matching Parity). }
unit FormMotionMatching;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleMotionMatching, ToolMotionMatching;

type
  TMotionMatchingModifyCallback = procedure(const AUndoComment: String) of object;
  TMotionMatchingRefreshCallback = procedure of object;

  TMotionMatchingForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModify: TMotionMatchingModifyCallback;
    FOnRefresh: TMotionMatchingRefreshCallback;

    FDbs: TPoseSearchDbArray;
    FMatchers: TMotionMatcherArray;

    LblHeader: TLabel;
    ListMatchers: TListBox;
    LblDetails: TLabel;
    PaintTrajectory: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromDesign;
    function SelectedMatcher: TCastleMotionMatchingBehavior;
    procedure NotifyModified(const AComment: String);

    procedure ListMatchersClick(Sender: TObject);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnInputIdleClick(Sender: TObject);
    procedure BtnInputWalkClick(Sender: TObject);
    procedure BtnInputRunClick(Sender: TObject);
    procedure BtnInputPivot180Click(Sender: TObject);
    procedure BtnToggleStrafeClick(Sender: TObject);
    procedure BtnStep100msClick(Sender: TObject);
    procedure BtnBurst500msClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintTrajectoryPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModify: TMotionMatchingModifyCallback;
      const AOnRefresh: TMotionMatchingRefreshCallback);
  end;

implementation

constructor TMotionMatchingForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModify: TMotionMatchingModifyCallback;
  const AOnRefresh: TMotionMatchingRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModify := AOnModify;
  FOnRefresh := AOnRefresh;

  Caption := 'Castle Game Engine — Motion Matching, Pose Search Trajectory & Inertialization Studio';
  Width := 1180;
  Height := 730;
  Position := poMainFormCenter;

  BuildUi;
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModify) then
    FOnModify(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TMotionMatchingForm.BuildUi;
var
  PanelTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
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
  PanelTop.Height := 74;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Motion Matching & Pose Search Studio — Predicted Spring Trajectory, k-NN Pose Search, Inertialization & Stride Warping';

  MakeBtn(PanelTop, '+ Spawn Motion-Matched Hero', 12, 34, 206, @BtnSpawnDemoClick);
  MakeBtn(PanelTop, 'Idle Stop (0 m/s)', 224, 34, 126, @BtnInputIdleClick);
  MakeBtn(PanelTop, 'Walk (1.8 m/s)', 356, 34, 118, @BtnInputWalkClick);
  MakeBtn(PanelTop, 'Run (4.8 m/s)', 480, 34, 118, @BtnInputRunClick);
  MakeBtn(PanelTop, 'Sudden 180 Pivot!', 604, 34, 142, @BtnInputPivot180Click);
  MakeBtn(PanelTop, 'Toggle Strafe Lock', 752, 34, 138, @BtnToggleStrafeClick);
  MakeBtn(PanelTop, 'Step +0.10s', 896, 34, 116, @BtnStep100msClick);
  MakeBtn(PanelTop, 'Burst +0.50s', 1018, 34, 120, @BtnBurst500msClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Telemetry Markdown', 12, 6, 210, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 1050, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 420;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 6, 380, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Motion-Matched Character Rigs:';

  ListMatchers := TListBox.Create(Self);
  ListMatchers.Parent := PanelLeft;
  ListMatchers.SetBounds(12, 26, 396, 240);
  ListMatchers.OnClick := @ListMatchersClick;

  LblDetails := TLabel.Create(Self);
  LblDetails.Parent := PanelLeft;
  LblDetails.SetBounds(12, 276, 396, 130);
  LblDetails.WordWrap := True;
  LblDetails.Caption := '';

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintTrajectory := TPaintBox.Create(Self);
  PaintTrajectory.Parent := PanelCenter;
  PaintTrajectory.Align := alTop;
  PaintTrajectory.Height := 290;
  PaintTrajectory.OnPaint := @PaintTrajectoryPaint;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := PanelCenter;
  MemoReport.Align := alClient;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssAutoBoth;
  MemoReport.Font.Name := 'Monospace';
end;

function TMotionMatchingForm.SelectedMatcher: TCastleMotionMatchingBehavior;
var
  Idx: Integer;
begin
  Idx := ListMatchers.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FMatchers)) then
    Result := FMatchers[Idx]
  else if Length(FMatchers) > 0 then
    Result := FMatchers[0]
  else
    Result := nil;
end;

procedure TMotionMatchingForm.RefreshFromDesign;
var
  I, PrevIdx: Integer;
  M: TCastleMotionMatchingBehavior;
begin
  PrevIdx := ListMatchers.ItemIndex;
  TMotionMatchingHelper.ScanMotionMatching(FDesignRoot, FDesignOwner, FDbs, FMatchers);

  ListMatchers.Items.BeginUpdate;
  try
    ListMatchers.Items.Clear;
    for I := 0 to High(FMatchers) do
      ListMatchers.Items.Add(Format('%s  %s',
        [FMatchers[I].Name, FMatchers[I].MotionSummaryBadge]));
    if ListMatchers.Items.Count > 0 then
      ListMatchers.ItemIndex := Clamped(Max(0, PrevIdx), 0, ListMatchers.Items.Count - 1);
  finally
    ListMatchers.Items.EndUpdate;
  end;

  M := SelectedMatcher;
  if M <> nil then
    LblDetails.Caption := Format(
      'Active Pose: %s (t = %.2fs, Tag = %s)' + LineEnding +
      'Search Cost: Total = %.3f (Traj %.3f | Face %.3f | Foot/Mom %.3f)' + LineEnding +
      'Stride Warp: %.2fx  |  Inertial Blend: %.0f%%  |  Switches: %d' + LineEnding +
      'World Speed: %.2f m/s  |  Strafe Lock: %s',
      [M.CurrentClipName, M.CurrentClipTimeSec, M.CurrentLocomotionTag,
       M.LastSearchCost.TotalCost, M.LastSearchCost.TrajectoryCost,
       M.LastSearchCost.FacingCost, M.LastSearchCost.FootAndMomentumCost,
       M.ActiveStrideWarpScale, M.InertialBlendAlpha * 100.0, M.PoseSwitchCount,
       M.CurrentWorldVelXZ.Length, BoolToStr(M.StrafeLockFacing, True)])
  else
    LblDetails.Caption := 'Click "+ Spawn Motion-Matched Hero" to create a Pose Search DB and character rig.';

  MemoReport.Lines.Text := TMotionMatchingHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintTrajectory.Invalidate;
end;

procedure TMotionMatchingForm.ListMatchersClick(Sender: TObject);
begin
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.BtnSpawnDemoClick(Sender: TObject);
var
  Hero: TCastleTransform;
  Db: TCastlePoseSearchDatabase;
  M: TCastleMotionMatchingBehavior;
begin
  TMotionMatchingHelper.SpawnMotionMatchingArenaDemo(
    FDesignRoot, FDesignOwner, Hero, Db, M);
  NotifyModified('Spawn Motion Matching Hero & Pose Search DB');
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.BtnInputIdleClick(Sender: TObject);
var
  M: TCastleMotionMatchingBehavior;
begin
  M := SelectedMatcher;
  if M = nil then Exit;
  M.DesiredWorldVelXZ := TVector2.Zero;
  M.ForceImmediatePoseSearch;
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.BtnInputWalkClick(Sender: TObject);
var
  M: TCastleMotionMatchingBehavior;
begin
  M := SelectedMatcher;
  if M = nil then Exit;
  M.DesiredWorldVelXZ := Vector2(0.0, -1.80);
  M.ForceImmediatePoseSearch;
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.BtnInputRunClick(Sender: TObject);
var
  M: TCastleMotionMatchingBehavior;
begin
  M := SelectedMatcher;
  if M = nil then Exit;
  M.DesiredWorldVelXZ := Vector2(0.0, -4.80);
  M.ForceImmediatePoseSearch;
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.BtnInputPivot180Click(Sender: TObject);
var
  M: TCastleMotionMatchingBehavior;
  CurFwd: TVector2;
begin
  M := SelectedMatcher;
  if M = nil then Exit;
  CurFwd := Vector2(-Sin(M.CharacterYawRad), -Cos(M.CharacterYawRad));
  if M.CurrentWorldVelXZ.Length < 2.5 then
  begin
    M.DesiredWorldVelXZ := CurFwd * 4.80;
    M.StepMotionMatching(0.35);
  end;
  { Command instant 180-deg opposite velocity! }
  M.DesiredWorldVelXZ := -CurFwd * 4.80;
  M.ForceImmediatePoseSearch;
  NotifyModified('Trigger Motion Matching 180 Pivot');
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.BtnToggleStrafeClick(Sender: TObject);
var
  M: TCastleMotionMatchingBehavior;
begin
  M := SelectedMatcher;
  if M = nil then Exit;
  M.StrafeLockFacing := not M.StrafeLockFacing;
  if M.StrafeLockFacing then
  begin
    M.DesiredFacingWorldXZ := Vector2(0.0, -1.0);
    M.DesiredWorldVelXZ := Vector2(2.10, 0.0);
  end;
  M.ForceImmediatePoseSearch;
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.BtnStep100msClick(Sender: TObject);
begin
  TMotionMatchingHelper.StepAllMotionMatchers(FDesignRoot, FDesignOwner, 0.10);
  NotifyModified('Step Motion Matching (+0.10s)');
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.BtnBurst500msClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 1 to 10 do
    TMotionMatchingHelper.StepAllMotionMatchers(FDesignRoot, FDesignOwner, 0.05);
  NotifyModified('Burst Motion Matching (+0.50s)');
  RefreshFromDesign;
end;

procedure TMotionMatchingForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := MemoReport.Lines.Text;
end;

procedure TMotionMatchingForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TMotionMatchingForm.PaintTrajectoryPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, RadarCX, RadarCY, RadarR, ChartL, ChartR, ChartT, ChartB, I, X1, Y1, X2, Y2: Integer;
  M: TCastleMotionMatchingBehavior;
  Pos02, Pos05, Pos10, Face05, Face10: TVector2;
  Chosen: TPoseSearchEntry;
  ScalePx, TSec, ValA, ValB: Single;

  function LocalToRadarX(const LX: Single): Integer;
  begin
    Result := RadarCX + Round(LX * ScalePx);
  end;

  function LocalToRadarY(const LY: Single): Integer;
  begin
    Result := RadarCY - Round(LY * ScalePx);
  end;

begin
  C := PaintTrajectory.Canvas;
  W := PaintTrajectory.Width;
  H := PaintTrajectory.Height;

  C.Brush.Color := RGBToColor(18, 22, 30);
  C.FillRect(0, 0, W, H);

  RadarCX := 175;
  RadarCY := H div 2 + 10;
  RadarR := Min(120, (H - 48) div 2);
  ScalePx := RadarR / 6.0;

  { Left pane: Character-Local Trajectory Radar (+Y = Forward, +X = Right) }
  C.Pen.Color := RGBToColor(52, 64, 84);
  C.Brush.Color := RGBToColor(12, 16, 22);
  C.Ellipse(RadarCX - RadarR, RadarCY - RadarR, RadarCX + RadarR, RadarCY + RadarR);
  C.MoveTo(RadarCX - RadarR, RadarCY);
  C.LineTo(RadarCX + RadarR, RadarCY);
  C.MoveTo(RadarCX, RadarCY - RadarR);
  C.LineTo(RadarCX, RadarCY + RadarR);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(185, 200, 225);
  C.Font.Style := [fsBold];
  C.TextOut(16, 8, 'Local Trajectory Radar (+0.2s / +0.5s / +1.0s)');
  C.Font.Style := [];

  M := SelectedMatcher;
  if M <> nil then
  begin
    M.PredictLocalTrajectory(Pos02, Pos05, Pos10, Face05, Face10);

    { Matched DB pose trajectory in green }
    if (M.Database <> nil) and (M.CurrentEntryIndex >= 0) and
       (M.CurrentEntryIndex < M.Database.EntryCount) then
    begin
      Chosen := M.Database.GetEntry(M.CurrentEntryIndex);
      C.Pen.Color := RGBToColor(84, 224, 132);
      C.Pen.Width := 2;
      C.MoveTo(RadarCX, RadarCY);
      C.LineTo(LocalToRadarX(Chosen.TrajectoryPos02.X), LocalToRadarY(Chosen.TrajectoryPos02.Y));
      C.LineTo(LocalToRadarX(Chosen.TrajectoryPos05.X), LocalToRadarY(Chosen.TrajectoryPos05.Y));
      C.LineTo(LocalToRadarX(Chosen.TrajectoryPos10.X), LocalToRadarY(Chosen.TrajectoryPos10.Y));
    end;

    { Predicted spring trajectory in cyan }
    C.Pen.Color := RGBToColor(68, 198, 255);
    C.Pen.Width := 2;
    C.MoveTo(RadarCX, RadarCY);
    C.LineTo(LocalToRadarX(Pos02.X), LocalToRadarY(Pos02.Y));
    C.LineTo(LocalToRadarX(Pos05.X), LocalToRadarY(Pos05.Y));
    C.LineTo(LocalToRadarX(Pos10.X), LocalToRadarY(Pos10.Y));
    C.Pen.Width := 1;
  end;

  { Right pane: Critically-Damped Inertialization Decay Curve }
  ChartL := 355;
  ChartR := W - 20;
  ChartT := 34;
  ChartB := H - 30;

  C.Font.Color := RGBToColor(185, 200, 225);
  C.Font.Style := [fsBold];
  C.TextOut(ChartL, 8, 'Critically-Damped Inertialization Blend Decay & Stride Warp');
  C.Font.Style := [];

  C.Brush.Color := RGBToColor(12, 16, 22);
  C.Pen.Color := RGBToColor(52, 64, 84);
  C.Rectangle(ChartL, ChartT, ChartR, ChartB);

  if (M <> nil) and (ChartR > ChartL + 30) then
  begin
    C.Pen.Color := RGBToColor(245, 176, 66);
    C.Pen.Width := 2;
    for I := 0 to 39 do
    begin
      TSec := (I / 40.0) * 0.50;
      ValA := Clamped(EvaluateInertializationDecay(1.0, 0.0, M.InertialHalfLifeSec, TSec), 0.0, 1.0);
      TSec := ((I + 1) / 40.0) * 0.50;
      ValB := Clamped(EvaluateInertializationDecay(1.0, 0.0, M.InertialHalfLifeSec, TSec), 0.0, 1.0);
      X1 := ChartL + Round((I / 40.0) * (ChartR - ChartL));
      X2 := ChartL + Round(((I + 1) / 40.0) * (ChartR - ChartL));
      Y1 := ChartB - Round(ValA * (ChartB - ChartT - 12));
      Y2 := ChartB - Round(ValB * (ChartB - ChartT - 12));
      C.MoveTo(X1, Y1);
      C.LineTo(X2, Y2);
    end;
    C.Pen.Width := 1;

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(245, 210, 130);
    C.TextOut(ChartL + 10, ChartT + 8, Format(
      'Pose: %s (%s)  |  HalfLife = %.2fs  |  Live Inertial = %.0f%%  |  Stride = %.2fx',
      [M.CurrentClipName, M.CurrentLocomotionTag,
       M.InertialHalfLifeSec, M.InertialBlendAlpha * 100.0, M.ActiveStrideWarpScale]));
  end;
end;

end.
