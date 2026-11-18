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

{ Visual Studio dialog for Camera Rig Rail Auto-Dolly & Co-Op Framing (Phase 352). }
unit FormCameraRail;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleCameraRigRail, ToolCameraRail;

type
  TCameraRailModifiedCallback = procedure(const UndoComment: String) of object;
  TCameraRailRefreshCallback = procedure of object;

  TCameraRailForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TCameraRailModifiedCallback;
    FOnRefresh: TCameraRailRefreshCallback;
    FPaintRail: TPaintBox;
    FMemoStats: TMemo;
    FLabelHeader: TLabel;
    procedure BuildUi;
    function ActiveRail: TCastleCameraRigRail;
    procedure NotifyChange(const AComment: String);
    procedure RefreshStats;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnPresetCanyonClick(Sender: TObject);
    procedure BtnPresetCorridorClick(Sender: TObject);
    procedure BtnPresetOrbitalClick(Sender: TObject);
    procedure BtnDeadzoneNudgeClick(Sender: TObject);
    procedure BtnSprintLookAheadClick(Sender: TObject);
    procedure BtnSeparateSplitClick(Sender: TObject);
    procedure BtnMergeCoOpClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintRailMap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TCameraRailModifiedCallback;
      const AOnRefresh: TCameraRailRefreshCallback);
  end;

implementation

constructor TCameraRailForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TCameraRailModifiedCallback;
  const AOnRefresh: TCameraRailRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Camera Rig Rail Closest-Point Auto-Dolly & Co-Op Framing Studio (Phase 352)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshStats;
end;

procedure TCameraRailForm.BuildUi;
var
  TopBar, Row2, BodyPanel: TPanel;

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
  FLabelHeader := TLabel.Create(Self);
  FLabelHeader.Parent := Self;
  FLabelHeader.Align := alTop;
  FLabelHeader.BorderSpacing.Around := 8;
  FLabelHeader.Font.Style := [fsBold];
  FLabelHeader.Caption := 'UE 6.0+ Camera Rig Rail — Closest-Point Catmull-Rom Auto-Dolly, Velocity Look-Ahead, Deadzone Aim & 2P Split/Merge Hysteresis';

  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 40;
  TopBar.BevelOuter := bvNone;
  MakeBtn(TopBar, '+ Spawn Canyon Rail & 2P Demo', @BtnSpawnClick);
  MakeBtn(TopBar, 'Preset: Canyon Side-Scroll', @BtnPresetCanyonClick);
  MakeBtn(TopBar, 'Preset: S-Curve Corridor', @BtnPresetCorridorClick);
  MakeBtn(TopBar, 'Preset: Boss Orbital Ring', @BtnPresetOrbitalClick);
  MakeBtn(TopBar, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Nudge P1 Inside Deadzone (+0.35m)', @BtnDeadzoneNudgeClick);
  MakeBtn(Row2, 'Sprint P1 East (+6m + 6m/s Look-Ahead)', @BtnSprintLookAheadClick);
  MakeBtn(Row2, 'Separate Co-Op P2 (18m -> SPLIT)', @BtnSeparateSplitClick);
  MakeBtn(Row2, 'Reunite Co-Op P2 (4m -> MERGE)', @BtnMergeCoOpClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintRail := TPaintBox.Create(Self);
  FPaintRail.Parent := BodyPanel;
  FPaintRail.Align := alLeft;
  FPaintRail.Width := 540;
  FPaintRail.OnPaint := @PaintRailMap;

  FMemoStats := TMemo.Create(Self);
  FMemoStats.Parent := BodyPanel;
  FMemoStats.Align := alClient;
  FMemoStats.ReadOnly := True;
  FMemoStats.ScrollBars := ssAutoBoth;
  FMemoStats.Font.Name := 'Monospace';
end;

function TCameraRailForm.ActiveRail: TCastleCameraRigRail;
begin
  Result := TCameraRailHelper.FindRailInHierarchy(FDesignRoot);
end;

procedure TCameraRailForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshStats;
end;

procedure TCameraRailForm.RefreshStats;
begin
  FMemoStats.Lines.Text := TCameraRailHelper.GenerateCameraRailReport(ActiveRail);
  FPaintRail.Invalidate;
end;

procedure TCameraRailForm.BtnSpawnClick(Sender: TObject);
var
  Rail: TCastleCameraRigRail;
  P1, P2: TCastleTransform;
begin
  if TCameraRailHelper.SpawnCameraRailDemoArena(FDesignRoot, FDesignOwner, Rail, P1, P2) then
    NotifyChange('Spawn Camera Rig Rail & Co-Op Demo');
end;

procedure TCameraRailForm.BtnPresetCanyonClick(Sender: TObject);
var
  Rail: TCastleCameraRigRail;
begin
  Rail := ActiveRail;
  if Rail = nil then Exit;
  Rail.Preset := crpSideScrollerCanyon;
  Rail.StepFromTargets(0.0);
  NotifyChange('Switch Camera Rail to Canyon Side-Scroller');
end;

procedure TCameraRailForm.BtnPresetCorridorClick(Sender: TObject);
var
  Rail: TCastleCameraRigRail;
begin
  Rail := ActiveRail;
  if Rail = nil then Exit;
  Rail.Preset := crpScurvedCorridorChase;
  Rail.StepFromTargets(0.0);
  NotifyChange('Switch Camera Rail to S-Curve Corridor');
end;

procedure TCameraRailForm.BtnPresetOrbitalClick(Sender: TObject);
var
  Rail: TCastleCameraRigRail;
begin
  Rail := ActiveRail;
  if Rail = nil then Exit;
  Rail.Preset := crpBossArenaOrbitalRing;
  Rail.StepFromTargets(0.0);
  NotifyChange('Switch Camera Rail to Boss Orbital Ring');
end;

procedure TCameraRailForm.BtnDeadzoneNudgeClick(Sender: TObject);
var
  Rail: TCastleCameraRigRail;
  P1: TCastleTransform;
begin
  Rail := ActiveRail;
  if (Rail = nil) or (Rail.PrimaryTarget = nil) then Exit;
  P1 := Rail.PrimaryTarget;
  P1.Translation := P1.Translation + Vector3(0.35, 0, 0);
  Rail.StepFromTargets(0.10);
  NotifyChange('Nudge Player 1 Inside Camera Deadzone');
end;

procedure TCameraRailForm.BtnSprintLookAheadClick(Sender: TObject);
var
  Rail: TCastleCameraRigRail;
  P1, P2: TCastleTransform;
  P2Pos: TVector3;
  I: Integer;
begin
  Rail := ActiveRail;
  if (Rail = nil) or (Rail.PrimaryTarget = nil) then Exit;
  P1 := Rail.PrimaryTarget;
  P2 := Rail.SecondaryCoOpTarget;
  P1.Translation := P1.Translation + Vector3(6.0, 0, 0);
  if P2 <> nil then
    P2Pos := P2.WorldTranslation
  else
    P2Pos := TVector3.Zero;
  for I := 1 to 12 do
    Rail.EvaluateAndStepRig(P1.WorldTranslation, Vector3(6.0, 0, 0),
      P2Pos, P2 <> nil, 1.0 / 30.0);
  NotifyChange('Sprint Player 1 East with Velocity Look-Ahead');
end;

procedure TCameraRailForm.BtnSeparateSplitClick(Sender: TObject);
var
  Rail: TCastleCameraRigRail;
begin
  Rail := ActiveRail;
  if (Rail = nil) or (Rail.PrimaryTarget = nil) or (Rail.SecondaryCoOpTarget = nil) then Exit;
  Rail.CoOpEnabled := True;
  Rail.PrimaryTarget.Translation := Vector3(-9.0, 0.65, 0.0);
  Rail.SecondaryCoOpTarget.Translation := Vector3(9.0, 0.65, 0.0);
  Rail.StepFromTargets(0.25);
  NotifyChange('Separate Co-Op Players Beyond Split Threshold');
end;

procedure TCameraRailForm.BtnMergeCoOpClick(Sender: TObject);
var
  Rail: TCastleCameraRigRail;
begin
  Rail := ActiveRail;
  if (Rail = nil) or (Rail.PrimaryTarget = nil) or (Rail.SecondaryCoOpTarget = nil) then Exit;
  Rail.CoOpEnabled := True;
  Rail.PrimaryTarget.Translation := Vector3(-2.0, 0.65, 0.0);
  Rail.SecondaryCoOpTarget.Translation := Vector3(2.0, 0.65, 0.0);
  Rail.StepFromTargets(0.25);
  NotifyChange('Reunite Co-Op Players Inside Merge Threshold');
end;

procedure TCameraRailForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TCameraRailHelper.GenerateCameraRailReport(ActiveRail);
end;

procedure TCameraRailForm.PaintRailMap(Sender: TObject);
var
  C: TCanvas;
  W, H, I: Integer;
  Rail: TCastleCameraRigRail;
  R: TCameraRailResult;

  function MapXZ(const Pt: TVector3): TPoint;
  begin
    Result.X := Round(W * 0.5 + (Pt.X / 22.0) * (W * 0.44));
    Result.Y := Round(H * 0.5 + (Pt.Z / 22.0) * (H * 0.44));
  end;

var
  PtA, PtB, CamPt, AimPt, PredPt, P1Pt, P2Pt: TPoint;
begin
  C := FPaintRail.Canvas;
  W := FPaintRail.Width;
  H := FPaintRail.Height;
  C.Brush.Color := RGBToColor(22, 26, 34);
  C.FillRect(0, 0, W, H);

  Rail := ActiveRail;
  if Rail = nil then
  begin
    C.Font.Color := clSilver;
    C.TextOut(18, 22, 'Click "+ Spawn Canyon Rail & 2P Demo" to inspect XZ Rail & Framing.');
    Exit;
  end;

  { Draw Catmull-Rom rail }
  C.Pen.Color := RGBToColor(55, 215, 250);
  C.Pen.Width := 3;
  for I := 0 to 47 do
  begin
    PtA := MapXZ(Rail.EvaluateRailWorld(I / 48.0));
    PtB := MapXZ(Rail.EvaluateRailWorld((I + 1) / 48.0));
    C.Line(PtA.X, PtA.Y, PtB.X, PtB.Y);
  end;

  R := Rail.LastResult;
  CamPt := MapXZ(R.CameraWorldPos);
  AimPt := MapXZ(R.DeadzoneAimWorld);
  PredPt := MapXZ(R.PredictedFocusWorld);

  { Sightline from camera dolly to deadzone aim }
  C.Pen.Color := RGBToColor(255, 215, 70);
  C.Pen.Width := 2;
  C.Line(CamPt.X, CamPt.Y, AimPt.X, AimPt.Y);

  { Players }
  if Rail.PrimaryTarget <> nil then
  begin
    P1Pt := MapXZ(Rail.PrimaryTarget.WorldTranslation);
    C.Brush.Color := RGBToColor(60, 175, 255);
    C.Ellipse(P1Pt.X - 7, P1Pt.Y - 7, P1Pt.X + 7, P1Pt.Y + 7);
  end;
  if (Rail.SecondaryCoOpTarget <> nil) and Rail.CoOpEnabled then
  begin
    P2Pt := MapXZ(Rail.SecondaryCoOpTarget.WorldTranslation);
    C.Brush.Color := RGBToColor(255, 145, 55);
    C.Ellipse(P2Pt.X - 7, P2Pt.Y - 7, P2Pt.X + 7, P2Pt.Y + 7);
  end;

  { Predicted look-ahead diamond & camera carriage }
  C.Brush.Color := RGBToColor(90, 240, 130);
  C.Rectangle(PredPt.X - 5, PredPt.Y - 5, PredPt.X + 5, PredPt.Y + 5);

  if R.ShouldSplitScreen then
    C.Brush.Color := RGBToColor(255, 95, 75)
  else
    C.Brush.Color := RGBToColor(255, 220, 60);
  C.Ellipse(CamPt.X - 8, CamPt.Y - 8, CamPt.X + 8, CamPt.Y + 8);

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(12, 10, Format('Top-Down XZ Rail | u=%.3f | FOV=%.1f deg | %s', [
    R.RailParamU, R.EffectiveFieldOfViewDeg,
    BoolToStr(R.ShouldSplitScreen, 'SPLIT-SCREEN 2P', 'SINGLE SHARED VIEW')]));
end;

end.
