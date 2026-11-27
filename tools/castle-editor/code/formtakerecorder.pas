{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Take Recorder & Live Link Real-Time Streaming Studio
  featuring a SMPTE Timecode Slate Header, 3D Mocap/CineCam Trajectory &
  Douglas-Peucker Keyframe Reduction Curve Viewport, and an ILiveLinkClient
  Subject Health & De-Jitter Buffer Inspector (Phase 397 — 117 UE Studios /
  40 MCP). }
unit FormTakeRecorder;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleTakeRecorder, ToolTakeRecorder;

type
  TTakeRecorderModifiedCallback = procedure(const UndoComment: String) of object;
  TTakeRecorderRefreshCallback = procedure of object;

  TTakeRecorderForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TTakeRecorderModifiedCallback;
    FOnRefresh: TTakeRecorderRefreshCallback;

    FActiveRec: TCastleTakeRecorder;

    FLblStatus: TLabel;
    FPaintTrajectory: TPaintBox;
    FPaintLiveLinkHub: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintTrajectoryAndCurveViewport(Sender: TObject);
    procedure PaintLiveLinkSubjectHub(Sender: TObject);

    procedure BtnSpawnMocapClick(Sender: TObject);
    procedure BtnSpawnChaseClick(Sender: TObject);
    procedure BtnRecordNextTakeClick(Sender: TObject);
    procedure BtnTightenToleranceClick(Sender: TObject);
    procedure BtnLoosenToleranceClick(Sender: TObject);
    procedure BtnSimulateStaleDropClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TTakeRecorderModifiedCallback;
      const AOnRefresh: TTakeRecorderRefreshCallback);
  end;

implementation

constructor TTakeRecorderForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TTakeRecorderModifiedCallback;
  const AOnRefresh: TTakeRecorderRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Take Recorder & Live Link Real-Time Streaming Studio (UTakeRecorder / ILiveLinkClient — 117 UE Studios / 40 MCP)';
  Position := poScreenCenter;
  Width := 1340;
  Height := 760;

  BuildUi;
  FActiveRec := TTakeRecorderHelper.FindFirstTakeRecorder(FDesignRoot);
  RefreshFromScene;
end;

procedure TTakeRecorderForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlBottom, PnlRight: TPanel;
  BtnMocap, BtnChase, BtnRec, BtnTight, BtnLoose, BtnDrop, BtnCopy, BtnClose: TButton;
  XPos: Integer;

  function MakeToolbarBtn(const ACaption: String; const AWidth: Integer;
    const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := PnlToolbar;
    Result.Left := XPos;
    Result.Top := 6;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    Inc(XPos, AWidth + 6);
  end;

begin
  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;
  PnlToolbar.Color := RGBToColor(34, 37, 45);

  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Top := 0;
  PnlTop.Height := 32;
  PnlTop.BevelOuter := bvNone;
  PnlTop.Color := RGBToColor(26, 28, 34);
  PnlToolbar.Top := 32;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 12;
  FLblStatus.Top := 8;
  FLblStatus.Font.Color := RGBToColor(225, 232, 245);
  FLblStatus.Font.Style := [fsBold];
  FLblStatus.Caption := 'Take Recorder & Live Link Hub Ready.';

  XPos := 8;
  BtnMocap := MakeToolbarBtn('+ Mocap+VCam Take', 156, @BtnSpawnMocapClick);
  BtnChase := MakeToolbarBtn('+ Vehicle Chase', 136, @BtnSpawnChaseClick);
  BtnRec := MakeToolbarBtn('Record Next Take (+1)', 168, @BtnRecordNextTakeClick);
  BtnTight := MakeToolbarBtn('ReduceKeys (0.5cm)', 154, @BtnTightenToleranceClick);
  BtnLoose := MakeToolbarBtn('ReduceKeys (4.0cm)', 154, @BtnLoosenToleranceClick);
  BtnDrop := MakeToolbarBtn('Test Stale/Drop Timeout', 176, @BtnSimulateStaleDropClick);
  BtnCopy := MakeToolbarBtn('Copy Report', 106, @BtnCopyReportClick);
  BtnClose := MakeToolbarBtn('Close', 72, nil);
  BtnClose.ModalResult := mrOk;
  if (BtnMocap <> nil) and (BtnChase <> nil) and (BtnRec <> nil) and
     (BtnTight <> nil) and (BtnLoose <> nil) and (BtnDrop <> nil) and
     (BtnCopy <> nil) then ;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 128;
  PnlBottom.BevelOuter := bvNone;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := PnlBottom;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;
  FMemoReport.Font.Name := 'Consolas';
  FMemoReport.Font.Size := 9;
  FMemoReport.Color := RGBToColor(18, 20, 26);
  FMemoReport.Font.Color := RGBToColor(208, 218, 232);

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 596;
  PnlRight.BevelOuter := bvNone;

  FPaintLiveLinkHub := TPaintBox.Create(Self);
  FPaintLiveLinkHub.Parent := PnlRight;
  FPaintLiveLinkHub.Align := alClient;
  FPaintLiveLinkHub.OnPaint := @PaintLiveLinkSubjectHub;

  FPaintTrajectory := TPaintBox.Create(Self);
  FPaintTrajectory.Parent := Self;
  FPaintTrajectory.Align := alClient;
  FPaintTrajectory.OnPaint := @PaintTrajectoryAndCurveViewport;
end;

procedure TTakeRecorderForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh;
  RefreshFromScene;
end;

procedure TTakeRecorderForm.RefreshFromScene;
begin
  if FActiveRec = nil then
    FActiveRec := TTakeRecorderHelper.FindFirstTakeRecorder(FDesignRoot);

  if FActiveRec <> nil then
    FLblStatus.Caption := Format(
      'Slate: %s (Take #%d)  |  SMPTE: %s  |  Keys: %d Raw -> %d Reduced (-%.1f%%)  |  LiveLink Green: %d/%d',
      [FActiveRec.SlateName,
       FActiveRec.TakeNumber,
       FActiveRec.FormatSmpteTimecode(FActiveRec.CurrentWorldTimeSec),
       FActiveRec.TotalRawKeyCount,
       FActiveRec.TotalReducedKeyCount,
       FActiveRec.KeyReductionPercent,
       FActiveRec.ActiveGreenSubjectCount(FActiveRec.CurrentWorldTimeSec),
       FActiveRec.SubjectCount])
  else
    FLblStatus.Caption := 'No TCastleTakeRecorder in scene — click "+ Mocap+VCam Take" to capture 60Hz LiveLink + Sequencer tracks.';

  FMemoReport.Lines.Text := TTakeRecorderHelper.GenerateMarkdownReport(
    FDesignRoot, FActiveRec);

  FPaintTrajectory.Invalidate;
  FPaintLiveLinkHub.Invalidate;
end;

procedure TTakeRecorderForm.PaintTrajectoryAndCurveViewport(Sender: TObject);
const
  TrackLineColors: array[0..2] of TColor = (
    $0078DC58, { Hero Green }
    $005CC8FF, { VCam Gold/Amber }
    $007A72FF  { Boss Coral }
  );
var
  C: TCanvas;
  W, H, SplitY, MapCenterX, MapCenterY, TIdx, I, PX, PY, QX, QY: Integer;
  ScalePx, MaxT: Single;
  Trk: TTakeRecordedTrack;
  K: TTakeKeyframe;

  function MapWorldX(const AX: Single): Integer;
  begin
    Result := MapCenterX + Round(AX * ScalePx);
  end;

  function MapWorldZ(const AZ: Single): Integer;
  begin
    Result := MapCenterY - Round(AZ * ScalePx);
  end;

begin
  C := FPaintTrajectory.Canvas;
  W := Max(360, FPaintTrajectory.Width);
  H := Max(320, FPaintTrajectory.Height);
  SplitY := Round(H * 0.58);

  C.Brush.Color := RGBToColor(18, 21, 28);
  C.FillRect(0, 0, W, H);

  { Top SMPTE Slate & 3D Top-Down Trajectory Viewport }
  C.Brush.Color := RGBToColor(28, 34, 46);
  C.FillRect(0, 0, W, 30);
  C.Brush.Color := RGBToColor(232, 54, 64);
  C.Ellipse(12, 8, 26, 22);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 226, 228);
  if FActiveRec <> nil then
    C.TextOut(32, 7, Format('REC SLATE: %s_Take%.2d  |  SMPTE %s  (Gold = Keys)',
      [FActiveRec.SlateName, FActiveRec.TakeNumber,
       FActiveRec.FormatSmpteTimecode(FActiveRec.CurrentWorldTimeSec)]))
  else
    C.TextOut(32, 7, 'Take Recorder Top-Down Trajectory & Keyframe Simplification Viewport');
  C.Font.Style := [];

  if (FActiveRec = nil) or (FActiveRec.TrackCount = 0) then Exit;

  ScalePx := Min((W - 120) / 12.5, (SplitY - 64) / 9.5);
  MapCenterX := W div 2 + 18;
  MapCenterY := 34 + (SplitY - 38) div 2 - 8;

  { Arena Grid }
  C.Pen.Color := RGBToColor(30, 35, 46);
  for I := -6 to 6 do
  begin
    PX := MapWorldX(I * 1.0);
    C.MoveTo(PX, 34);
    C.LineTo(PX, SplitY - 6);
  end;
  for I := -4 to 4 do
  begin
    PY := MapWorldZ(I * 1.0);
    C.MoveTo(12, PY);
    C.LineTo(W - 12, PY);
  end;

  { Draw Raw 60Hz samples vs Reduced Douglas-Peucker Keyframes }
  for TIdx := 0 to Min(2, FActiveRec.TrackCount - 1) do
  begin
    Trk := FActiveRec.Tracks[TIdx];
    { 1. Dense Raw 60Hz dots }
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(68, 92, 124);
    C.Pen.Color := RGBToColor(68, 92, 124);
    for I := 0 to High(Trk.RawKeys) do
    begin
      PX := MapWorldX(Trk.RawKeys[I].Location.X);
      PY := MapWorldZ(Trk.RawKeys[I].Location.Z);
      C.Pixels[PX, PY] := RGBToColor(112, 146, 188);
      C.Pixels[PX + 1, PY] := RGBToColor(112, 146, 188);
    end;

    { 2. Reduced Sequencer Polyline + Keyframe Diamonds }
    C.Pen.Color := TrackLineColors[TIdx];
    C.Pen.Width := 2;
    for I := 0 to High(Trk.ReducedKeys) - 1 do
    begin
      PX := MapWorldX(Trk.ReducedKeys[I].Location.X);
      PY := MapWorldZ(Trk.ReducedKeys[I].Location.Z);
      QX := MapWorldX(Trk.ReducedKeys[I + 1].Location.X);
      QY := MapWorldZ(Trk.ReducedKeys[I + 1].Location.Z);
      C.MoveTo(PX, PY);
      C.LineTo(QX, QY);
    end;
    C.Pen.Width := 1;

    C.Brush.Color := RGBToColor(255, 224, 96);
    C.Pen.Color := RGBToColor(28, 30, 38);
    for I := 0 to High(Trk.ReducedKeys) do
    begin
      PX := MapWorldX(Trk.ReducedKeys[I].Location.X);
      PY := MapWorldZ(Trk.ReducedKeys[I].Location.Z);
      C.Rectangle(PX - 3, PY - 3, PX + 4, PY + 4);
    end;

    if Length(Trk.ReducedKeys) > 0 then
    begin
      K := Trk.ReducedKeys[0];
      PX := MapWorldX(K.Location.X);
      PY := MapWorldZ(K.Location.Z);
      C.Brush.Style := bsClear;
      C.Font.Style := [fsBold];
      C.Font.Color := TrackLineColors[TIdx];
      C.TextOut(Max(14, Min(W - 180, PX + 6)), Max(36, PY - 16),
        Format('%s (%d->%d keys)', [Trk.TrackName, Length(Trk.RawKeys), Length(Trk.ReducedKeys)]));
      C.Font.Style := [];
    end;
  end;

  { Bottom Sequencer X(t) Curve Simplification Graph (Hero Track 0) }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(24, 28, 38);
  C.FillRect(0, SplitY, W, SplitY + 26);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(138, 212, 255);
  Trk := FActiveRec.Tracks[0];
  C.TextOut(12, SplitY + 5, Format(
    'Sequencer Curve: %s.X(t)  |  %d Raw -> %d Keys  |  MaxErr=%.4fm',
    [Trk.TrackName, Length(Trk.RawKeys), Length(Trk.ReducedKeys), Trk.MaxPosErrorM]));
  C.Font.Style := [];

  MaxT := 4.0;
  if Length(Trk.RawKeys) > 0 then
    MaxT := Max(0.5, Trk.RawKeys[High(Trk.RawKeys)].TimeSec);

  { Raw curve in cyan }
  C.Pen.Color := RGBToColor(68, 138, 188);
  for I := 0 to High(Trk.RawKeys) - 1 do
  begin
    PX := 24 + Round((Trk.RawKeys[I].TimeSec / MaxT) * (W - 48));
    PY := (H - 36) - Round(((Trk.RawKeys[I].Location.X + 5.0) / 10.0) * (H - SplitY - 72));
    QX := 24 + Round((Trk.RawKeys[I + 1].TimeSec / MaxT) * (W - 48));
    QY := (H - 36) - Round(((Trk.RawKeys[I + 1].Location.X + 5.0) / 10.0) * (H - SplitY - 72));
    C.MoveTo(PX, PY);
    C.LineTo(QX, QY);
  end;

  { Reduced curve & key markers in gold }
  C.Pen.Color := RGBToColor(255, 208, 76);
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(255, 224, 98);
  for I := 0 to High(Trk.ReducedKeys) do
  begin
    PX := 24 + Round((Trk.ReducedKeys[I].TimeSec / MaxT) * (W - 48));
    PY := (H - 36) - Round(((Trk.ReducedKeys[I].Location.X + 5.0) / 10.0) * (H - SplitY - 72));
    if I > 0 then
      C.LineTo(PX, PY);
    C.MoveTo(PX, PY);
    C.Ellipse(PX - 4, PY - 4, PX + 4, PY + 4);
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(184, 202, 228);
  C.TextOut(14, H - 22,
    'Douglas-Peucker ReduceKeys collapses linear spans to 2 keys while preserving sharp dodges & curves.');
  C.Brush.Style := bsSolid;
end;

procedure TTakeRecorderForm.PaintLiveLinkSubjectHub(Sender: TObject);
var
  C: TCanvas;
  W, H, I, RowY: Integer;
  Subj: TLiveLinkSubjectStream;
  Sample: TLiveLinkFrameSample;
  St: TLiveLinkSubjectStatus;
  LedCol: TColor;
  Trk: TTakeRecordedTrack;
  RedPct: Single;
begin
  C := FPaintLiveLinkHub.Canvas;
  W := Max(360, FPaintLiveLinkHub.Width);
  H := Max(320, FPaintLiveLinkHub.Height);

  C.Brush.Color := RGBToColor(24, 26, 33);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 214, 112);
  C.TextOut(12, 7, 'ILiveLinkClient Subject Stream Hub & Sequencer Track Audit');
  C.Font.Style := [];

  if FActiveRec = nil then Exit;

  { Section 1: LiveLink Subjects with Green/Yellow/Red Health LEDs }
  C.Brush.Color := RGBToColor(29, 33, 43);
  C.FillRect(10, 38, W - 10, 62);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(172, 188, 214);
  C.TextOut(34, 43, 'LiveLink Subject Name');
  C.TextOut(252, 43, 'UE Role');
  C.TextOut(432, 43, 'Buffer / Status');
  C.Font.Style := [];

  for I := 0 to FActiveRec.SubjectCount - 1 do
  begin
    Subj := FActiveRec.Subjects[I];
    FActiveRec.EvaluateLiveLinkSubject(Subj.SubjectName,
      FActiveRec.CurrentWorldTimeSec, Sample, St);

    RowY := 66 + I * 58;
    C.Brush.Style := bsSolid;
    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(28, 31, 41)
    else
      C.Brush.Color := RGBToColor(24, 27, 36);
    C.FillRect(10, RowY, W - 10, RowY + 54);

    case St of
      llsActiveGreen: LedCol := RGBToColor(72, 232, 118);
      llsStaleYellow: LedCol := RGBToColor(255, 204, 68);
      llsDroppedRed:  LedCol := RGBToColor(248, 78, 84);
    end;
    C.Brush.Color := LedCol;
    C.Pen.Color := RGBToColor(16, 18, 24);
    C.Ellipse(18, RowY + 9, 30, RowY + 21);

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(214, 232, 255);
    C.TextOut(36, RowY + 7, Subj.SubjectName);
    C.Font.Style := [];

    C.Font.Color := RGBToColor(186, 202, 226);
    C.TextOut(252, RowY + 7, LiveLinkRoleDisplayName(Subj.Role));

    C.Font.Color := LedCol;
    C.TextOut(432, RowY + 7, Format('%.0fms | %s',
      [Subj.EvaluationOffsetSec * 1000.0, LiveLinkStatusDisplayName(St)]));

    C.Font.Color := RGBToColor(148, 166, 194);
    C.TextOut(36, RowY + 29, Format(
      'Target: %s  |  Loc=(%.2f, %.2f, %.2f)  |  FOV=%.1f  Focus=%.1fm',
      [Subj.TargetActorName,
       Sample.Location.X, Sample.Location.Y, Sample.Location.Z,
       Sample.FovDeg, Sample.FocusDistanceM]));
  end;

  { Section 2: Recorded Sequencer Tracks & ReduceKeys Compression }
  RowY := 254;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(29, 33, 43);
  C.FillRect(10, RowY, W - 10, RowY + 24);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(172, 188, 214);
  C.TextOut(18, RowY + 5, 'Sequencer Track');
  C.TextOut(196, RowY + 5, 'Raw 60Hz');
  C.TextOut(288, RowY + 5, 'Reduced Keys');
  C.TextOut(420, RowY + 5, 'Max Drift Error');
  C.Font.Style := [];

  for I := 0 to FActiveRec.TrackCount - 1 do
  begin
    Trk := FActiveRec.Tracks[I];
    RowY := 282 + I * 36;
    if RowY + 32 > H - 10 then Break;

    C.Brush.Style := bsSolid;
    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(27, 30, 39)
    else
      C.Brush.Color := RGBToColor(23, 26, 34);
    C.FillRect(10, RowY, W - 10, RowY + 32);

    RedPct := 0.0;
    if Length(Trk.RawKeys) > 0 then
      RedPct := (1.0 - Length(Trk.ReducedKeys) / Length(Trk.RawKeys)) * 100.0;

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(126, 242, 174);
    C.TextOut(18, RowY + 8, Trk.TrackName);
    C.Font.Style := [];
    C.Font.Color := RGBToColor(196, 210, 232);
    C.TextOut(196, RowY + 8, Format('%d keys', [Length(Trk.RawKeys)]));
    C.Font.Color := RGBToColor(255, 218, 108);
    C.TextOut(288, RowY + 8, Format('%d (-%.0f%%)', [Length(Trk.ReducedKeys), RedPct]));
    C.Font.Color := RGBToColor(138, 216, 255);
    C.TextOut(420, RowY + 8, Format('%.4f m (<= %.3fm)',
      [Trk.MaxPosErrorM, FActiveRec.PosReduceToleranceM]));
  end;
  C.Brush.Style := bsSolid;
end;

procedure TTakeRecorderForm.BtnSpawnMocapClick(Sender: TObject);
begin
  FActiveRec := TTakeRecorderHelper.SpawnTakeRecorderPresetInDesign(
    FDesignRoot, FDesignOwner, trpMocapDuelAndCineCam, Vector3(0, 0, 0));
  NotifyChanged('Spawn Mocap Duel + VCam Take Recorder');
end;

procedure TTakeRecorderForm.BtnSpawnChaseClick(Sender: TObject);
begin
  FActiveRec := TTakeRecorderHelper.SpawnTakeRecorderPresetInDesign(
    FDesignRoot, FDesignOwner, trpVehicleChasePhysicsTake, Vector3(0, 0, -4));
  NotifyChanged('Spawn Vehicle Chase Take Recorder');
end;

procedure TTakeRecorderForm.BtnRecordNextTakeClick(Sender: TObject);
begin
  if FActiveRec = nil then Exit;
  FActiveRec.SimulatePresetTakeCapture(4.0);
  NotifyChanged(Format('Record New Take %s #%d', [FActiveRec.SlateName, FActiveRec.TakeNumber]));
end;

procedure TTakeRecorderForm.BtnTightenToleranceClick(Sender: TObject);
begin
  if FActiveRec = nil then Exit;
  FActiveRec.ReduceAllTracks(0.005, 0.15);
  NotifyChanged('ReduceKeys High-Precision (0.5 cm / 0.15 deg)');
end;

procedure TTakeRecorderForm.BtnLoosenToleranceClick(Sender: TObject);
begin
  if FActiveRec = nil then Exit;
  FActiveRec.ReduceAllTracks(0.040, 0.80);
  NotifyChanged('ReduceKeys Aggressive Compression (4.0 cm / 0.80 deg)');
end;

procedure TTakeRecorderForm.BtnSimulateStaleDropClick(Sender: TObject);
begin
  if FActiveRec = nil then Exit;
  { Advance WorldTime by +0.45s without new packets -> Stale Yellow warning! }
  FActiveRec.CurrentWorldTimeSec := FActiveRec.CurrentWorldTimeSec + 0.45;
  RefreshFromScene;
end;

procedure TTakeRecorderForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
  FLblStatus.Caption := 'Copied Take Recorder & Live Link Report to Clipboard.';
end;

end.
