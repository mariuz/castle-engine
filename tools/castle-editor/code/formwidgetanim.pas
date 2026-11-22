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

{ Unreal Engine 5.5-style UMG Widget Animation Timeline & Anchor Slot Designer
  dialog featuring a 16:9 UMG Canvas Designer with 9-Petal Anchor Flower gizmos,
  interactive 3x3 + Stretch Anchor Slot buttons, Forward/Reverse UI Event
  triggers, and a multi-track keyframe Sequencer Dope-Sheet with interactive
  playhead scrubbing (Phase 386 — 106 UE Studios / 29 MCP). }
unit FormWidgetAnim;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleUIControls,
  CastleWidgetAnim, ToolWidgetAnim;

type
  TWidgetAnimModifiedCallback = procedure(const UndoComment: String) of object;
  TWidgetAnimRefreshCallback = procedure of object;

  TWidgetAnimForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TWidgetAnimModifiedCallback;
    FOnRefresh: TWidgetAnimRefreshCallback;

    FActiveAnim: TCastleWidgetAnimator;
    FSelectedSlotIdx: Integer;

    FLblStatus: TLabel;
    FCmbClips: TComboBox;
    FPaintScreen: TPaintBox;
    FPaintTimeline: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure DrawAnchorFlower(const C: TCanvas; const AX, AY: Integer);
    procedure PaintUmgScreen(Sender: TObject);
    procedure PaintTimelineCanvas(Sender: TObject);
    procedure ScreenMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TimelineMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure CmbClipsChange(Sender: TObject);

    procedure BtnSpawnModalClick(Sender: TObject);
    procedure BtnSpawnHudClick(Sender: TObject);
    procedure BtnPlayFwdClick(Sender: TObject);
    procedure BtnPlayRevClick(Sender: TObject);
    procedure BtnStepClick(Sender: TObject);
    procedure BtnResetRestClick(Sender: TObject);
    procedure BtnFireShowClick(Sender: TObject);
    procedure BtnHoverEnterClick(Sender: TObject);
    procedure BtnHoverLeaveClick(Sender: TObject);
    procedure BtnAnchorPresetClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TWidgetAnimModifiedCallback;
      const AOnRefresh: TWidgetAnimRefreshCallback);
  end;

implementation

constructor TWidgetAnimForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TWidgetAnimModifiedCallback;
  const AOnRefresh: TWidgetAnimRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FSelectedSlotIdx := 0;

  Caption := 'UMG Widget Animation Timeline & Anchor Slot Designer (106 UE Studios / 29 MCP)';
  Position := poScreenCenter;
  Width := 1220;
  Height := 740;

  BuildUi;
  FActiveAnim := TWidgetAnimHelper.FindFirstWidgetAnimator(FDesignRoot);
  RefreshFromScene;
end;

procedure TWidgetAnimForm.BuildUi;
const
  GridAnchors: array[0..8] of TUmgAnchorPreset = (
    uapTopLeft,    uapTopCenter,    uapTopRight,
    uapCenterLeft, uapCenter,       uapCenterRight,
    uapBottomLeft, uapBottomCenter, uapBottomRight
  );
  GridCaptions: array[0..8] of String = (
    'TL', 'TC', 'TR',
    'CL', 'C',  'CR',
    'BL', 'BC', 'BR'
  );
var
  PnlTop, PnlToolbar, PnlRight, PnlBottom, PnlTimelineHost: TPanel;
  BtnModal, BtnHud, BtnPlayF, BtnPlayR, BtnStep, BtnReset, BtnCopy, BtnClose: TButton;
  BtnShow, BtnHovIn, BtnHovOut, BtnStrTop, BtnStrFull, BtnAnc: TButton;
  LblClip, LblAnc, LblEv: TLabel;
  R, Col, Idx: Integer;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 32;
  PnlTop.BevelOuter := bvNone;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 10;
  FLblStatus.Top := 8;
  FLblStatus.Caption := 'UMG Widget Animation Timeline & Anchor Designer Ready.';

  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;

  BtnModal := TButton.Create(Self);
  BtnModal.Parent := PnlToolbar;
  BtnModal.SetBounds(8, 6, 148, 30);
  BtnModal.Caption := '+ Modal Bounce Preset';
  BtnModal.OnClick := @BtnSpawnModalClick;

  BtnHud := TButton.Create(Self);
  BtnHud.Parent := PnlToolbar;
  BtnHud.SetBounds(160, 6, 148, 30);
  BtnHud.Caption := '+ HUD Damage & Toast';
  BtnHud.OnClick := @BtnSpawnHudClick;

  LblClip := TLabel.Create(Self);
  LblClip.Parent := PnlToolbar;
  LblClip.Left := 316;
  LblClip.Top := 13;
  LblClip.Caption := 'Clip:';

  FCmbClips := TComboBox.Create(Self);
  FCmbClips.Parent := PnlToolbar;
  FCmbClips.Style := csDropDownList;
  FCmbClips.SetBounds(350, 8, 168, 28);
  FCmbClips.OnChange := @CmbClipsChange;

  BtnPlayF := TButton.Create(Self);
  BtnPlayF.Parent := PnlToolbar;
  BtnPlayF.SetBounds(524, 6, 98, 30);
  BtnPlayF.Caption := 'Play Fwd';
  BtnPlayF.OnClick := @BtnPlayFwdClick;

  BtnPlayR := TButton.Create(Self);
  BtnPlayR.Parent := PnlToolbar;
  BtnPlayR.SetBounds(626, 6, 98, 30);
  BtnPlayR.Caption := 'Play Rev';
  BtnPlayR.OnClick := @BtnPlayRevClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlToolbar;
  BtnStep.SetBounds(728, 6, 102, 30);
  BtnStep.Caption := 'Step +0.10s';
  BtnStep.OnClick := @BtnStepClick;

  BtnReset := TButton.Create(Self);
  BtnReset.Parent := PnlToolbar;
  BtnReset.SetBounds(834, 6, 92, 30);
  BtnReset.Caption := 'Rest Pose';
  BtnReset.OnClick := @BtnResetRestClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlToolbar;
  BtnCopy.SetBounds(930, 6, 122, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyMarkdownClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 118;
  PnlBottom.BevelOuter := bvNone;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := PnlBottom;
  FMemoReport.Align := alClient;
  FMemoReport.ScrollBars := ssVertical;
  FMemoReport.ReadOnly := True;
  FMemoReport.Font.Name := 'Monospace';

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.Align := alRight;
  BtnClose.Width := 74;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;

  PnlTimelineHost := TPanel.Create(Self);
  PnlTimelineHost.Parent := Self;
  PnlTimelineHost.Align := alBottom;
  PnlTimelineHost.Height := 196;
  PnlTimelineHost.BevelOuter := bvLowered;

  FPaintTimeline := TPaintBox.Create(Self);
  FPaintTimeline.Parent := PnlTimelineHost;
  FPaintTimeline.Align := alClient;
  FPaintTimeline.OnPaint := @PaintTimelineCanvas;
  FPaintTimeline.OnMouseDown := @TimelineMouseDown;

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 256;
  PnlRight.BevelOuter := bvLowered;

  LblAnc := TLabel.Create(Self);
  LblAnc.Parent := PnlRight;
  LblAnc.Left := 12;
  LblAnc.Top := 10;
  LblAnc.Caption := '9-Point UMG Anchor Flower:';

  for R := 0 to 2 do
    for Col := 0 to 2 do
    begin
      Idx := R * 3 + Col;
      BtnAnc := TButton.Create(Self);
      BtnAnc.Parent := PnlRight;
      BtnAnc.SetBounds(14 + Col * 76, 32 + R * 34, 72, 30);
      BtnAnc.Caption := GridCaptions[Idx];
      BtnAnc.Tag := Ord(GridAnchors[Idx]);
      BtnAnc.OnClick := @BtnAnchorPresetClick;
    end;

  BtnStrTop := TButton.Create(Self);
  BtnStrTop.Parent := PnlRight;
  BtnStrTop.SetBounds(14, 138, 110, 28);
  BtnStrTop.Caption := 'Stretch H-Top';
  BtnStrTop.Tag := Ord(uapStretchHorizontalTop);
  BtnStrTop.OnClick := @BtnAnchorPresetClick;

  BtnStrFull := TButton.Create(Self);
  BtnStrFull.Parent := PnlRight;
  BtnStrFull.SetBounds(128, 138, 112, 28);
  BtnStrFull.Caption := 'Stretch Full';
  BtnStrFull.Tag := Ord(uapStretchFullScreen);
  BtnStrFull.OnClick := @BtnAnchorPresetClick;

  LblEv := TLabel.Create(Self);
  LblEv.Parent := PnlRight;
  LblEv.Left := 12;
  LblEv.Top := 180;
  LblEv.Caption := 'UI Event Trigger Bindings:';

  BtnShow := TButton.Create(Self);
  BtnShow.Parent := PnlRight;
  BtnShow.SetBounds(14, 202, 226, 30);
  BtnShow.Caption := 'Trigger OnShow (Modal Open)';
  BtnShow.OnClick := @BtnFireShowClick;

  BtnHovIn := TButton.Create(Self);
  BtnHovIn.Parent := PnlRight;
  BtnHovIn.SetBounds(14, 236, 226, 30);
  BtnHovIn.Caption := 'Hover Enter ConfirmBtn (Fwd)';
  BtnHovIn.OnClick := @BtnHoverEnterClick;

  BtnHovOut := TButton.Create(Self);
  BtnHovOut.Parent := PnlRight;
  BtnHovOut.SetBounds(14, 270, 226, 30);
  BtnHovOut.Caption := 'Hover Leave ConfirmBtn (Rev)';
  BtnHovOut.OnClick := @BtnHoverLeaveClick;

  FPaintScreen := TPaintBox.Create(Self);
  FPaintScreen.Parent := Self;
  FPaintScreen.Align := alClient;
  FPaintScreen.OnPaint := @PaintUmgScreen;
  FPaintScreen.OnMouseDown := @ScreenMouseDown;
end;

procedure TWidgetAnimForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TWidgetAnimForm.RefreshFromScene;
var
  I: Integer;
begin
  if (FActiveAnim = nil) and (FDesignRoot <> nil) then
    FActiveAnim := TWidgetAnimHelper.FindFirstWidgetAnimator(FDesignRoot);

  FCmbClips.Items.BeginUpdate;
  try
    FCmbClips.Items.Clear;
    if FActiveAnim <> nil then
    begin
      for I := 0 to High(FActiveAnim.Clips) do
        FCmbClips.Items.Add(Format('%s (%.2fs)',
          [FActiveAnim.Clips[I].ClipName, FActiveAnim.Clips[I].DurationSec]));
      if (FActiveAnim.ActiveClipIndex >= 0) and
         (FActiveAnim.ActiveClipIndex < FCmbClips.Items.Count) then
        FCmbClips.ItemIndex := FActiveAnim.ActiveClipIndex;
      FLblStatus.Caption := FActiveAnim.Name + '  ' + FActiveAnim.WidgetAnimSummaryBadge;
    end else
      FLblStatus.Caption := 'No TCastleWidgetAnimator in UI design — click "+ Modal Bounce Preset".';
  finally
    FCmbClips.Items.EndUpdate;
  end;

  FMemoReport.Text := TWidgetAnimHelper.GenerateMarkdownReport(FDesignRoot, FActiveAnim);
  FPaintScreen.Invalidate;
  FPaintTimeline.Invalidate;
end;

procedure TWidgetAnimForm.DrawAnchorFlower(const C: TCanvas; const AX, AY: Integer);
begin
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(255, 215, 72);
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(255, 196, 48);
  { 4 petals around (AX, AY) }
  C.Ellipse(AX - 11, AY - 4, AX - 2, AY + 5);
  C.Ellipse(AX + 3,  AY - 4, AX + 12, AY + 5);
  C.Ellipse(AX - 4,  AY - 11, AX + 5, AY - 2);
  C.Ellipse(AX - 4,  AY + 3,  AX + 5, AY + 12);
  C.Brush.Color := clWhite;
  C.Ellipse(AX - 3, AY - 3, AX + 4, AY + 4);
end;

procedure TWidgetAnimForm.PaintUmgScreen(Sender: TObject);
var
  C: TCanvas;
  W, H, ScrL, ScrT, ScrW, ScrH, I, AncX, AncY, WX, WY, WW, WH: Integer;
  ScaleRef: Single;
  MinUV, MaxUV, PivotUV: TVector2;
  S: TUmgManagedWidgetSlot;
begin
  C := FPaintScreen.Canvas;
  W := FPaintScreen.Width;
  H := FPaintScreen.Height;

  C.Brush.Color := RGBToColor(20, 22, 28);
  C.FillRect(0, 0, W, H);

  ScrW := Min(W - 36, Round((H - 36) * (16.0 / 9.0)));
  ScrH := Round(ScrW * (9.0 / 16.0));
  if ScrH > H - 28 then
  begin
    ScrH := H - 28;
    ScrW := Round(ScrH * (16.0 / 9.0));
  end;
  ScrL := (W - ScrW) div 2;
  ScrT := (H - ScrH) div 2;
  ScaleRef := ScrW / 1280.0;

  { 16:9 UMG Reference Canvas frame }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(30, 34, 44);
  C.Pen.Color := RGBToColor(72, 146, 228);
  C.Pen.Width := 1;
  C.Rectangle(ScrL, ScrT, ScrL + ScrW, ScrT + ScrH);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(148, 196, 248);
  C.TextOut(ScrL + 8, ScrT + 6, 'UMG Designer Viewport (1280x720 Virtual Reference)');

  if FActiveAnim = nil then Exit;

  for I := 0 to High(FActiveAnim.Slots) do
  begin
    S := FActiveAnim.Slots[I];
    TCastleWidgetAnimator.NormalizedAnchorFlowerMinMax(S.AnchorPreset, MinUV, MaxUV);
    PivotUV := (MinUV + MaxUV) * 0.5;

    AncX := ScrL + Round(PivotUV.X * ScrW);
    AncY := ScrT + ScrH - Round(PivotUV.Y * ScrH);

    if S.AnchorPreset = uapStretchFullScreen then
    begin
      WW := ScrW; WH := ScrH; WX := ScrL; WY := ScrT;
    end else if S.AnchorPreset in [uapStretchHorizontalTop, uapStretchHorizontalBottom] then
    begin
      WW := ScrW;
      WH := Max(8, Round(S.RestHeight * S.EvalScale * ScaleRef));
      WX := ScrL;
      WY := AncY - Round(S.EvalTransY * ScaleRef) - Round((1.0 - PivotUV.Y) * WH);
    end else
    begin
      WW := Max(12, Round(S.RestWidth * S.EvalScale * ScaleRef));
      WH := Max(10, Round(S.RestHeight * S.EvalScale * ScaleRef));
      WX := AncX + Round(S.EvalTransX * ScaleRef) - Round(PivotUV.X * WW);
      WY := AncY - Round(S.EvalTransY * ScaleRef) - Round((1.0 - PivotUV.Y) * WH);
    end;

    { Alpha-attenuated fill color }
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(
      EnsureRange(Round(Lerp(S.EvalOpacity, 30, S.EvalColorRGB.X * 255)), 0, 255),
      EnsureRange(Round(Lerp(S.EvalOpacity, 34, S.EvalColorRGB.Y * 255)), 0, 255),
      EnsureRange(Round(Lerp(S.EvalOpacity, 44, S.EvalColorRGB.Z * 255)), 0, 255));
    if I = FSelectedSlotIdx then
    begin
      C.Pen.Color := RGBToColor(92, 238, 148);
      C.Pen.Width := 2;
    end else
    begin
      C.Pen.Color := RGBToColor(110, 124, 148);
      C.Pen.Width := 1;
    end;
    C.RoundRect(WX, WY, WX + WW, WY + WH, 8, 8);

    C.Brush.Style := bsClear;
    C.Font.Color := clWhite;
    C.TextOut(WX + 8, WY + 6, Format('%s (a=%.2f)', [S.WidgetName, S.EvalOpacity]));

    if I = FSelectedSlotIdx then
    begin
      C.Pen.Style := psDot;
      C.Pen.Color := RGBToColor(255, 212, 72);
      C.Line(AncX, AncY, WX + WW div 2, WY + WH div 2);
      C.Pen.Style := psSolid;
      DrawAnchorFlower(C, AncX, AncY);
    end;
  end;
end;

procedure TWidgetAnimForm.PaintTimelineCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, LabelW, TrackL, TrackR, YRow, TIdx, KIdx, KX, PlayX: Integer;
  Clip: TUmgWidgetAnimClip;
  Dur: Single;
begin
  C := FPaintTimeline.Canvas;
  W := FPaintTimeline.Width;
  H := FPaintTimeline.Height;

  C.Brush.Color := RGBToColor(22, 24, 30);
  C.FillRect(0, 0, W, H);

  LabelW := 230;
  TrackL := LabelW + 12;
  TrackR := Max(TrackL + 120, W - 24);

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(32, 36, 46);
  C.FillRect(0, 0, W, 26);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(215, 226, 242);
  C.TextOut(10, 5, 'UMG Sequencer Tracks (Click timeline to scrub)');

  if (FActiveAnim = nil) or (FActiveAnim.ActiveClipIndex < 0) or
     (FActiveAnim.ActiveClipIndex > High(FActiveAnim.Clips)) then Exit;

  Clip := FActiveAnim.Clips[FActiveAnim.ActiveClipIndex];
  Dur := Max(0.01, Clip.DurationSec);

  C.TextOut(TrackL, 5, '0.00s');
  C.TextOut((TrackL + TrackR) div 2 - 16, 5, Format('%.2fs', [Dur * 0.5]));
  C.TextOut(TrackR - 36, 5, Format('%.2fs', [Dur]));

  YRow := 32;
  for TIdx := 0 to High(Clip.Tracks) do
  begin
    C.Brush.Style := bsSolid;
    if Odd(TIdx) then
      C.Brush.Color := RGBToColor(28, 31, 38)
    else
      C.Brush.Color := RGBToColor(34, 38, 46);
    C.FillRect(4, YRow, W - 4, YRow + 26);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(198, 214, 236);
    C.TextOut(10, YRow + 5, Clip.Tracks[TIdx].TargetWidgetName + '.' +
      TCastleWidgetAnimator.AnimPropertyTitle(Clip.Tracks[TIdx].Prop));

    C.Pen.Width := 2;
    C.Pen.Color := RGBToColor(68, 138, 218);
    C.Line(TrackL, YRow + 13, TrackR, YRow + 13);

    { Keyframe diamonds }
    C.Pen.Width := 1;
    C.Pen.Color := RGBToColor(18, 20, 24);
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(255, 204, 64);
    for KIdx := 0 to High(Clip.Tracks[TIdx].Keys) do
    begin
      KX := TrackL + Round(EnsureRange(Clip.Tracks[TIdx].Keys[KIdx].TimeSec / Dur, 0.0, 1.0) * (TrackR - TrackL));
      C.Polygon([Point(KX, YRow + 7), Point(KX + 6, YRow + 13),
                 Point(KX, YRow + 19), Point(KX - 6, YRow + 13)]);
    end;

    Inc(YRow, 28);
  end;

  { Playhead Scrubber }
  PlayX := TrackL + Round(EnsureRange(FActiveAnim.CurrentTimeSec / Dur, 0.0, 1.0) * (TrackR - TrackL));
  C.Pen.Width := 2;
  C.Pen.Color := RGBToColor(255, 82, 82);
  C.Line(PlayX, 4, PlayX, H - 4);
end;

procedure TWidgetAnimForm.ScreenMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (FActiveAnim = nil) or (Length(FActiveAnim.Slots) = 0) then Exit;
  FSelectedSlotIdx := (FSelectedSlotIdx + 1) mod Length(FActiveAnim.Slots);
  FPaintScreen.Invalidate;
end;

procedure TWidgetAnimForm.TimelineMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  TrackL, TrackR: Integer;
  Dur, T: Single;
begin
  if (FActiveAnim = nil) or (FActiveAnim.ActiveClipIndex < 0) then Exit;
  TrackL := 242;
  TrackR := Max(TrackL + 120, FPaintTimeline.Width - 24);
  Dur := Max(0.01, FActiveAnim.Clips[FActiveAnim.ActiveClipIndex].DurationSec);
  T := EnsureRange((X - TrackL) / Max(1, TrackR - TrackL), 0.0, 1.0) * Dur;
  FActiveAnim.ScrubTimeline(T);
  RefreshFromScene;
end;

procedure TWidgetAnimForm.CmbClipsChange(Sender: TObject);
begin
  if (FActiveAnim <> nil) and (FCmbClips.ItemIndex >= 0) then
  begin
    FActiveAnim.ActiveClipIndex := FCmbClips.ItemIndex;
    FActiveAnim.ScrubTimeline(0.0);
    RefreshFromScene;
  end;
end;

procedure TWidgetAnimForm.BtnSpawnModalClick(Sender: TObject);
begin
  FActiveAnim := TWidgetAnimHelper.SpawnWidgetAnimPresetInDesign(
    FDesignRoot, FDesignOwner, uwapModalPopupSlideBounceAndFade);
  if FActiveAnim <> nil then
    FActiveAnim.ScrubTimeline(0.35);
  NotifyChanged('Spawn UMG Modal Bounce Animation');
end;

procedure TWidgetAnimForm.BtnSpawnHudClick(Sender: TObject);
begin
  FActiveAnim := TWidgetAnimHelper.SpawnWidgetAnimPresetInDesign(
    FDesignRoot, FDesignOwner, uwapHudDamageToastAndHealthFlash);
  if FActiveAnim <> nil then
    FActiveAnim.ScrubTimeline(0.25);
  NotifyChanged('Spawn UMG HUD Damage & Toast Animation');
end;

procedure TWidgetAnimForm.BtnPlayFwdClick(Sender: TObject);
begin
  if (FActiveAnim = nil) or (FActiveAnim.ActiveClipIndex < 0) then Exit;
  FActiveAnim.PlayAnimation(
    FActiveAnim.Clips[FActiveAnim.ActiveClipIndex].ClipName, upmForward, 1, 1.0);
  FActiveAnim.StepAnimator(0.25);
  RefreshFromScene;
end;

procedure TWidgetAnimForm.BtnPlayRevClick(Sender: TObject);
begin
  if (FActiveAnim = nil) or (FActiveAnim.ActiveClipIndex < 0) then Exit;
  FActiveAnim.PlayAnimation(
    FActiveAnim.Clips[FActiveAnim.ActiveClipIndex].ClipName, upmReverse, 1, 1.0);
  FActiveAnim.StepAnimator(0.15);
  RefreshFromScene;
end;

procedure TWidgetAnimForm.BtnStepClick(Sender: TObject);
begin
  if FActiveAnim = nil then Exit;
  if not FActiveAnim.Playing then
  begin
    if FActiveAnim.ActiveClipIndex >= 0 then
      FActiveAnim.PlayAnimation(
        FActiveAnim.Clips[FActiveAnim.ActiveClipIndex].ClipName, upmForward, 1, 1.0);
  end;
  FActiveAnim.StepAnimator(0.10);
  RefreshFromScene;
end;

procedure TWidgetAnimForm.BtnResetRestClick(Sender: TObject);
begin
  if FActiveAnim = nil then Exit;
  FActiveAnim.StopAnimation(True);
  RefreshFromScene;
end;

procedure TWidgetAnimForm.BtnFireShowClick(Sender: TObject);
begin
  if FActiveAnim = nil then Exit;
  FActiveAnim.FireUiEvent('', uetOnShow);
  FActiveAnim.StepAnimator(0.35);
  RefreshFromScene;
end;

procedure TWidgetAnimForm.BtnHoverEnterClick(Sender: TObject);
begin
  if FActiveAnim = nil then Exit;
  FActiveAnim.FireUiEvent('ConfirmBtn', uetOnHoverEnter);
  FActiveAnim.StepAnimator(0.20);
  RefreshFromScene;
end;

procedure TWidgetAnimForm.BtnHoverLeaveClick(Sender: TObject);
begin
  if FActiveAnim = nil then Exit;
  FActiveAnim.FireUiEvent('ConfirmBtn', uetOnHoverLeave);
  FActiveAnim.StepAnimator(0.20);
  RefreshFromScene;
end;

procedure TWidgetAnimForm.BtnAnchorPresetClick(Sender: TObject);
var
  Preset: TUmgAnchorPreset;
begin
  if (FActiveAnim = nil) or (FSelectedSlotIdx < 0) or
     (FSelectedSlotIdx > High(FActiveAnim.Slots)) then Exit;
  Preset := TUmgAnchorPreset((Sender as TButton).Tag);
  FActiveAnim.SetWidgetAnchorPreset(FActiveAnim.Slots[FSelectedSlotIdx].WidgetName, Preset);
  NotifyChanged('Change UMG Widget Anchor Preset');
end;

procedure TWidgetAnimForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Text;
end;

end.
