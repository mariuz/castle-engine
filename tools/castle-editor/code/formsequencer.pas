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

{ Interactive Non-Linear Cinematic Sequencer & Multi-Track Dope-Sheet Studio
  (@link(TSequencerForm)) for @link(TCastleSequencePlayer)
  (Phase 287 — UE 5.9 / 6.0 Sequencer Parity). }
unit FormSequencer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Contnrs, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Spin, Dialogs, Graphics, Clipbrd, Types,
  CastleVectors, CastleClassUtils, CastleUtils, CastleTransform,
  CastleUIControls, CastleViewport, CastleSequencer, ToolSequencer;

type
  TSequencerModifiedCallback = procedure (const UndoComment: String) of object;
  TSequencerRefreshViewportCallback = procedure of object;

  TSequencerForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FInitialSelected: TComponent;
    FOnModified: TSequencerModifiedCallback;
    FOnRefreshViewport: TSequencerRefreshViewportCallback;

    FSequenceList: TList;
    FTargetComps: TStringList;
    FCameraComps: TStringList;
    FTracksSnapshot: TSequenceTrackDataArray;
    FCuesSnapshot: TSequenceCueDataArray;
    FSelectedTrackIdx: Integer;
    FScrubbingPlayhead: Boolean;
    FPreviewTimer: TTimer;

    { Top sequence & transport bar }
    ComboSequence: TComboBox;
    ButtonNewSequence: TButton;
    ButtonRewind: TButton;
    ButtonPlayPause: TButton;
    ButtonStop: TButton;
    ComboPlaybackMode: TComboBox;
    SpinDuration: TFloatSpinEdit;
    SpinTimeScale: TFloatSpinEdit;
    LabelPlayheadReadout: TLabel;

    { Center interactive dope-sheet canvas }
    PanelTimelineHost: TPanel;
    PaintBoxTimeline: TPaintBox;

    { Authoring strip }
    GroupKeyAuthoring: TGroupBox;
    ComboTargetComp: TComboBox;
    ComboPropPath: TComboBox;
    ComboEasing: TComboBox;
    ButtonCaptureLiveKey: TButton;
    ComboCameraCut: TComboBox;
    ButtonAddCameraCut: TButton;
    ButtonAddCue: TButton;

    { Bottom actions }
    ButtonToggleMuteTrack: TButton;
    ButtonDeleteTrack: TButton;
    ButtonCopyMarkdown: TButton;
    ButtonClose: TButton;

    procedure BuildUi;
    function ActiveSequence: TCastleSequencePlayer;
    procedure RefreshSequenceList(const SelectSeq: TCastleSequencePlayer = nil);
    procedure RefreshTargetAndCameraLists;
    procedure SyncSnapshotFromActiveSequence;
    procedure UpdatePlayheadLabel;

    function TimelineLeftMargin: Integer;
    function TimelineRightMargin: Integer;
    function TimeToPixelX(const TimeSec: Single): Integer;
    function PixelXToTime(const PX: Integer): Single;
    function RowHeightPx: Integer;
    function RulerHeightPx: Integer;
    function CueLaneHeightPx: Integer;

    procedure ScrubToTime(const NewTimeSec: Single);

    procedure PreviewTimerTick(Sender: TObject);
    procedure ComboSequenceChange(Sender: TObject);
    procedure ButtonNewSequenceClick(Sender: TObject);
    procedure ButtonRewindClick(Sender: TObject);
    procedure ButtonPlayPauseClick(Sender: TObject);
    procedure ButtonStopClick(Sender: TObject);
    procedure ComboPlaybackModeChange(Sender: TObject);
    procedure SpinDurationChange(Sender: TObject);
    procedure SpinTimeScaleChange(Sender: TObject);

    procedure PaintBoxTimelinePaint(Sender: TObject);
    procedure PaintBoxTimelineMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxTimelineMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure PaintBoxTimelineMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure ButtonCaptureLiveKeyClick(Sender: TObject);
    procedure ButtonAddCameraCutClick(Sender: TObject);
    procedure ButtonAddCueClick(Sender: TObject);
    procedure ButtonToggleMuteTrackClick(Sender: TObject);
    procedure ButtonDeleteTrackClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
      const AOnModified: TSequencerModifiedCallback;
      const AOnRefreshViewport: TSequencerRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

uses
  Math;

{ TSequencerForm ------------------------------------------------------------- }

constructor TSequencerForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
  const AOnModified: TSequencerModifiedCallback;
  const AOnRefreshViewport: TSequencerRefreshViewportCallback);
begin
  inherited CreateNew(AOwner);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FInitialSelected := AInitialSelected;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FSelectedTrackIdx := -1;

  FSequenceList := TList.Create;
  FTargetComps := TStringList.Create;
  FCameraComps := TStringList.Create;

  Caption := 'Cinematic Sequencer & Multi-Track Dope-Sheet Studio (UE 5.9 / 6.0 Sequencer Parity)';
  Width := 1060;
  Height := 640;
  Position := poMainFormCenter;

  BuildUi;

  FPreviewTimer := TTimer.Create(Self);
  FPreviewTimer.Interval := 33;
  FPreviewTimer.Enabled := false;
  FPreviewTimer.OnTimer := @PreviewTimerTick;

  RefreshTargetAndCameraLists;
  if FInitialSelected is TCastleSequencePlayer then
    RefreshSequenceList(TCastleSequencePlayer(FInitialSelected))
  else
    RefreshSequenceList(nil);
end;

destructor TSequencerForm.Destroy;
begin
  if FPreviewTimer <> nil then
    FPreviewTimer.Enabled := false;
  FreeAndNil(FCameraComps);
  FreeAndNil(FTargetComps);
  FreeAndNil(FSequenceList);
  inherited;
end;

procedure TSequencerForm.BuildUi;
var
  PanelTop, RowSeq, RowTransport, PanelBottom, RowAuthor1, RowAuthor2: TPanel;
  LblSeq, LblDur, LblSpd, LblTarget, LblProp, LblEase, LblCam: TLabel;
begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Align := alTop;
  PanelTop.AutoSize := true;
  PanelTop.BevelOuter := bvNone;
  PanelTop.BorderSpacing.Around := 8;
  PanelTop.Parent := Self;

  RowSeq := TPanel.Create(Self);
  RowSeq.Align := alTop;
  RowSeq.Height := 34;
  RowSeq.BevelOuter := bvNone;
  RowSeq.Parent := PanelTop;

  LblSeq := TLabel.Create(Self);
  LblSeq.Align := alLeft;
  LblSeq.Caption := 'Active Sequence:';
  LblSeq.BorderSpacing.Right := 6;
  LblSeq.Parent := RowSeq;

  ComboSequence := TComboBox.Create(Self);
  ComboSequence.Align := alLeft;
  ComboSequence.Width := 250;
  ComboSequence.Style := csDropDownList;
  ComboSequence.OnChange := @ComboSequenceChange;
  ComboSequence.Parent := RowSeq;

  ButtonNewSequence := TButton.Create(Self);
  ButtonNewSequence.Align := alLeft;
  ButtonNewSequence.AutoSize := true;
  ButtonNewSequence.BorderSpacing.Left := 6;
  ButtonNewSequence.Caption := '+ New Sequence';
  ButtonNewSequence.OnClick := @ButtonNewSequenceClick;
  ButtonNewSequence.Parent := RowSeq;

  LabelPlayheadReadout := TLabel.Create(Self);
  LabelPlayheadReadout.Align := alRight;
  LabelPlayheadReadout.Font.Style := [Graphics.fsBold];
  LabelPlayheadReadout.Caption := 't = 0.00s / 5.00s';
  LabelPlayheadReadout.Parent := RowSeq;

  RowTransport := TPanel.Create(Self);
  RowTransport.Align := alTop;
  RowTransport.Height := 36;
  RowTransport.BevelOuter := bvNone;
  RowTransport.BorderSpacing.Top := 4;
  RowTransport.Parent := PanelTop;

  ButtonRewind := TButton.Create(Self);
  ButtonRewind.Align := alLeft;
  ButtonRewind.AutoSize := true;
  ButtonRewind.Caption := '|< 0.0s';
  ButtonRewind.OnClick := @ButtonRewindClick;
  ButtonRewind.Parent := RowTransport;

  ButtonPlayPause := TButton.Create(Self);
  ButtonPlayPause.Align := alLeft;
  ButtonPlayPause.Width := 94;
  ButtonPlayPause.BorderSpacing.Left := 4;
  ButtonPlayPause.Caption := 'Play';
  ButtonPlayPause.OnClick := @ButtonPlayPauseClick;
  ButtonPlayPause.Parent := RowTransport;

  ButtonStop := TButton.Create(Self);
  ButtonStop.Align := alLeft;
  ButtonStop.AutoSize := true;
  ButtonStop.BorderSpacing.Left := 4;
  ButtonStop.Caption := 'Stop';
  ButtonStop.OnClick := @ButtonStopClick;
  ButtonStop.Parent := RowTransport;

  ComboPlaybackMode := TComboBox.Create(Self);
  ComboPlaybackMode.Align := alLeft;
  ComboPlaybackMode.Width := 110;
  ComboPlaybackMode.BorderSpacing.Left := 8;
  ComboPlaybackMode.Style := csDropDownList;
  ComboPlaybackMode.Items.Add('Once');
  ComboPlaybackMode.Items.Add('Loop');
  ComboPlaybackMode.Items.Add('PingPong');
  ComboPlaybackMode.ItemIndex := 0;
  ComboPlaybackMode.OnChange := @ComboPlaybackModeChange;
  ComboPlaybackMode.Parent := RowTransport;

  LblDur := TLabel.Create(Self);
  LblDur.Align := alLeft;
  LblDur.BorderSpacing.Left := 12;
  LblDur.BorderSpacing.Right := 4;
  LblDur.Caption := 'Duration (s):';
  LblDur.Parent := RowTransport;

  SpinDuration := TFloatSpinEdit.Create(Self);
  SpinDuration.Align := alLeft;
  SpinDuration.Width := 76;
  SpinDuration.MinValue := 0.2;
  SpinDuration.MaxValue := 3600.0;
  SpinDuration.Increment := 0.5;
  SpinDuration.DecimalPlaces := 2;
  SpinDuration.Value := 5.0;
  SpinDuration.OnChange := @SpinDurationChange;
  SpinDuration.Parent := RowTransport;

  LblSpd := TLabel.Create(Self);
  LblSpd.Align := alLeft;
  LblSpd.BorderSpacing.Left := 10;
  LblSpd.BorderSpacing.Right := 4;
  LblSpd.Caption := 'Speed:';
  LblSpd.Parent := RowTransport;

  SpinTimeScale := TFloatSpinEdit.Create(Self);
  SpinTimeScale.Align := alLeft;
  SpinTimeScale.Width := 70;
  SpinTimeScale.MinValue := 0.05;
  SpinTimeScale.MaxValue := 10.0;
  SpinTimeScale.Increment := 0.25;
  SpinTimeScale.DecimalPlaces := 2;
  SpinTimeScale.Value := 1.0;
  SpinTimeScale.OnChange := @SpinTimeScaleChange;
  SpinTimeScale.Parent := RowTransport;

  { Bottom buttons }
  PanelBottom := TPanel.Create(Self);
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 44;
  PanelBottom.BevelOuter := bvNone;
  PanelBottom.BorderSpacing.Around := 8;
  PanelBottom.Parent := Self;

  ButtonToggleMuteTrack := TButton.Create(Self);
  ButtonToggleMuteTrack.Align := alLeft;
  ButtonToggleMuteTrack.AutoSize := true;
  ButtonToggleMuteTrack.Caption := 'Mute / Unmute Track';
  ButtonToggleMuteTrack.OnClick := @ButtonToggleMuteTrackClick;
  ButtonToggleMuteTrack.Parent := PanelBottom;

  ButtonDeleteTrack := TButton.Create(Self);
  ButtonDeleteTrack.Align := alLeft;
  ButtonDeleteTrack.AutoSize := true;
  ButtonDeleteTrack.BorderSpacing.Left := 6;
  ButtonDeleteTrack.Caption := 'Delete Selected Track';
  ButtonDeleteTrack.OnClick := @ButtonDeleteTrackClick;
  ButtonDeleteTrack.Parent := PanelBottom;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Align := alLeft;
  ButtonCopyMarkdown.AutoSize := true;
  ButtonCopyMarkdown.BorderSpacing.Left := 6;
  ButtonCopyMarkdown.Caption := 'Copy Markdown Summary';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;
  ButtonCopyMarkdown.Parent := PanelBottom;

  ButtonClose := TButton.Create(Self);
  ButtonClose.Align := alRight;
  ButtonClose.Width := 92;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;
  ButtonClose.Parent := PanelBottom;

  { Keyframe & Camera-Cut Authoring Box }
  GroupKeyAuthoring := TGroupBox.Create(Self);
  GroupKeyAuthoring.Align := alBottom;
  GroupKeyAuthoring.AutoSize := true;
  GroupKeyAuthoring.Caption := 'Keyframe, Camera-Cut & Event Cue Authoring (Inserts at Current Playhead Time)';
  GroupKeyAuthoring.BorderSpacing.Around := 8;
  GroupKeyAuthoring.Parent := Self;

  RowAuthor1 := TPanel.Create(Self);
  RowAuthor1.Align := alTop;
  RowAuthor1.Height := 34;
  RowAuthor1.BevelOuter := bvNone;
  RowAuthor1.BorderSpacing.Around := 4;
  RowAuthor1.Parent := GroupKeyAuthoring;

  LblTarget := TLabel.Create(Self);
  LblTarget.Align := alLeft;
  LblTarget.Caption := 'Target:';
  LblTarget.BorderSpacing.Right := 4;
  LblTarget.Parent := RowAuthor1;

  ComboTargetComp := TComboBox.Create(Self);
  ComboTargetComp.Align := alLeft;
  ComboTargetComp.Width := 180;
  ComboTargetComp.Style := csDropDownList;
  ComboTargetComp.Parent := RowAuthor1;

  LblProp := TLabel.Create(Self);
  LblProp.Align := alLeft;
  LblProp.BorderSpacing.Left := 8;
  LblProp.BorderSpacing.Right := 4;
  LblProp.Caption := 'Property:';
  LblProp.Parent := RowAuthor1;

  ComboPropPath := TComboBox.Create(Self);
  ComboPropPath.Align := alLeft;
  ComboPropPath.Width := 185;
  ComboPropPath.Items.Add('Translation');
  ComboPropPath.Items.Add('Scale');
  ComboPropPath.Items.Add('RotationPersistent.W');
  ComboPropPath.Items.Add('Intensity');
  ComboPropPath.Items.Add('Exists');
  ComboPropPath.Items.Add('Caption');
  ComboPropPath.Items.Add('FontSize');
  ComboPropPath.Items.Add('ColorPersistent.Red');
  ComboPropPath.Text := 'Translation';
  ComboPropPath.Parent := RowAuthor1;

  LblEase := TLabel.Create(Self);
  LblEase.Align := alLeft;
  LblEase.BorderSpacing.Left := 8;
  LblEase.BorderSpacing.Right := 4;
  LblEase.Caption := 'Easing:';
  LblEase.Parent := RowAuthor1;

  ComboEasing := TComboBox.Create(Self);
  ComboEasing.Align := alLeft;
  ComboEasing.Width := 115;
  ComboEasing.Style := csDropDownList;
  ComboEasing.Items.Add('SmoothStep');
  ComboEasing.Items.Add('Linear');
  ComboEasing.Items.Add('EaseInCubic');
  ComboEasing.Items.Add('EaseOutCubic');
  ComboEasing.Items.Add('Step');
  ComboEasing.ItemIndex := 0;
  ComboEasing.Parent := RowAuthor1;

  ButtonCaptureLiveKey := TButton.Create(Self);
  ButtonCaptureLiveKey.Align := alLeft;
  ButtonCaptureLiveKey.AutoSize := true;
  ButtonCaptureLiveKey.BorderSpacing.Left := 8;
  ButtonCaptureLiveKey.Caption := '+ Key Live Property';
  ButtonCaptureLiveKey.OnClick := @ButtonCaptureLiveKeyClick;
  ButtonCaptureLiveKey.Parent := RowAuthor1;

  RowAuthor2 := TPanel.Create(Self);
  RowAuthor2.Align := alTop;
  RowAuthor2.Height := 34;
  RowAuthor2.BevelOuter := bvNone;
  RowAuthor2.BorderSpacing.Around := 4;
  RowAuthor2.Parent := GroupKeyAuthoring;

  LblCam := TLabel.Create(Self);
  LblCam.Align := alLeft;
  LblCam.Caption := 'Camera Cut:';
  LblCam.BorderSpacing.Right := 4;
  LblCam.Parent := RowAuthor2;

  ComboCameraCut := TComboBox.Create(Self);
  ComboCameraCut.Align := alLeft;
  ComboCameraCut.Width := 180;
  ComboCameraCut.Style := csDropDownList;
  ComboCameraCut.Parent := RowAuthor2;

  ButtonAddCameraCut := TButton.Create(Self);
  ButtonAddCameraCut.Align := alLeft;
  ButtonAddCameraCut.AutoSize := true;
  ButtonAddCameraCut.BorderSpacing.Left := 6;
  ButtonAddCameraCut.Caption := '+ Add Camera Cut at Playhead';
  ButtonAddCameraCut.OnClick := @ButtonAddCameraCutClick;
  ButtonAddCameraCut.Parent := RowAuthor2;

  ButtonAddCue := TButton.Create(Self);
  ButtonAddCue.Align := alLeft;
  ButtonAddCue.AutoSize := true;
  ButtonAddCue.BorderSpacing.Left := 14;
  ButtonAddCue.Caption := '+ Add Event Cue Marker...';
  ButtonAddCue.OnClick := @ButtonAddCueClick;
  ButtonAddCue.Parent := RowAuthor2;

  { Center interactive Dope-Sheet Timeline }
  PanelTimelineHost := TPanel.Create(Self);
  PanelTimelineHost.Align := alClient;
  PanelTimelineHost.BevelOuter := bvLowered;
  PanelTimelineHost.BorderSpacing.Around := 8;
  PanelTimelineHost.Parent := Self;

  PaintBoxTimeline := TPaintBox.Create(Self);
  PaintBoxTimeline.Align := alClient;
  PaintBoxTimeline.OnPaint := @PaintBoxTimelinePaint;
  PaintBoxTimeline.OnMouseDown := @PaintBoxTimelineMouseDown;
  PaintBoxTimeline.OnMouseMove := @PaintBoxTimelineMouseMove;
  PaintBoxTimeline.OnMouseUp := @PaintBoxTimelineMouseUp;
  PaintBoxTimeline.Parent := PanelTimelineHost;
end;

function TSequencerForm.ActiveSequence: TCastleSequencePlayer;
var
  Idx: Integer;
begin
  Idx := ComboSequence.ItemIndex;
  if (Idx >= 0) and (Idx < FSequenceList.Count) then
    Result := TCastleSequencePlayer(FSequenceList[Idx])
  else
    Result := nil;
end;

procedure TSequencerForm.RefreshTargetAndCameraLists;
var
  I, SelIdx: Integer;
begin
  TSequencerHelper.CollectNamedTargetComponents(FRootComponent, FTargetComps);
  SelIdx := -1;
  ComboTargetComp.Items.BeginUpdate;
  try
    ComboTargetComp.Items.Clear;
    for I := 0 to FTargetComps.Count - 1 do
    begin
      ComboTargetComp.Items.Add(FTargetComps[I] + ' (' +
        TObject(FTargetComps.Objects[I]).ClassName + ')');
      if TComponent(FTargetComps.Objects[I]) = FInitialSelected then
        SelIdx := I;
    end;
  finally
    ComboTargetComp.Items.EndUpdate;
  end;
  if (SelIdx < 0) and (ComboTargetComp.Items.Count > 0) then
    SelIdx := 0;
  ComboTargetComp.ItemIndex := SelIdx;

  TSequencerHelper.CollectCamerasInDesign(FRootComponent, FCameraComps);
  ComboCameraCut.Items.BeginUpdate;
  try
    ComboCameraCut.Items.Clear;
    for I := 0 to FCameraComps.Count - 1 do
      ComboCameraCut.Items.Add(FCameraComps[I]);
  finally
    ComboCameraCut.Items.EndUpdate;
  end;
  if ComboCameraCut.Items.Count > 0 then
    ComboCameraCut.ItemIndex := 0;
end;

procedure TSequencerForm.RefreshSequenceList(const SelectSeq: TCastleSequencePlayer);
var
  I, SelIdx: Integer;
  S: TCastleSequencePlayer;
begin
  TSequencerHelper.CollectSequencePlayers(FRootComponent, FSequenceList);
  SelIdx := -1;
  ComboSequence.Items.BeginUpdate;
  try
    ComboSequence.Items.Clear;
    for I := 0 to FSequenceList.Count - 1 do
    begin
      S := TCastleSequencePlayer(FSequenceList[I]);
      ComboSequence.Items.Add(Format('%s — %s (%.1fs)',
        [S.Name, S.SequenceLabel, S.Duration]));
      if S = SelectSeq then
        SelIdx := I;
    end;
  finally
    ComboSequence.Items.EndUpdate;
  end;
  if (SelIdx < 0) and (ComboSequence.Items.Count > 0) then
    SelIdx := 0;
  ComboSequence.ItemIndex := SelIdx;
  SyncSnapshotFromActiveSequence;
end;

procedure TSequencerForm.SyncSnapshotFromActiveSequence;
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if Seq = nil then
  begin
    FTracksSnapshot := nil;
    FCuesSnapshot := nil;
    FSelectedTrackIdx := -1;
    LabelPlayheadReadout.Caption := 'No Sequence (click "+ New Sequence")';
    PaintBoxTimeline.Invalidate;
    Exit;
  end;

  Seq.TargetRoot := FRootComponent as TCastleComponent;
  FTracksSnapshot := Seq.GetTracksSnapshot;
  FCuesSnapshot := Seq.GetCuesSnapshot;
  if FSelectedTrackIdx > High(FTracksSnapshot) then
    FSelectedTrackIdx := High(FTracksSnapshot);

  SpinDuration.Value := Seq.Duration;
  SpinTimeScale.Value := Seq.TimeScale;
  ComboPlaybackMode.ItemIndex := Ord(Seq.PlaybackMode);
  UpdatePlayheadLabel;
  PaintBoxTimeline.Invalidate;
end;

procedure TSequencerForm.UpdatePlayheadLabel;
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if Seq <> nil then
    LabelPlayheadReadout.Caption := Format('Playhead: t = %.2fs / %.2fs  (%d Tracks, %d Keys)',
      [Seq.CurrentTime, Seq.Duration, Length(FTracksSnapshot), Seq.TotalKeyCount]);
end;

function TSequencerForm.TimelineLeftMargin: Integer;
begin
  Result := 230;
end;

function TSequencerForm.TimelineRightMargin: Integer;
begin
  Result := 24;
end;

function TSequencerForm.RulerHeightPx: Integer;
begin
  Result := 28;
end;

function TSequencerForm.CueLaneHeightPx: Integer;
begin
  Result := 24;
end;

function TSequencerForm.RowHeightPx: Integer;
begin
  Result := 30;
end;

function TSequencerForm.TimeToPixelX(const TimeSec: Single): Integer;
var
  Seq: TCastleSequencePlayer;
  AvailW: Integer;
  Dur: Single;
begin
  Seq := ActiveSequence;
  if Seq <> nil then
    Dur := Max(0.1, Seq.Duration)
  else
    Dur := 5.0;
  AvailW := Max(80, PaintBoxTimeline.Width - TimelineLeftMargin - TimelineRightMargin);
  Result := TimelineLeftMargin + Round((Clamped(TimeSec, 0.0, Dur) / Dur) * AvailW);
end;

function TSequencerForm.PixelXToTime(const PX: Integer): Single;
var
  Seq: TCastleSequencePlayer;
  AvailW: Integer;
  Dur: Single;
begin
  Seq := ActiveSequence;
  if Seq <> nil then
    Dur := Max(0.1, Seq.Duration)
  else
    Dur := 5.0;
  AvailW := Max(80, PaintBoxTimeline.Width - TimelineLeftMargin - TimelineRightMargin);
  Result := Clamped(((PX - TimelineLeftMargin) / AvailW) * Dur, 0.0, Dur);
end;

procedure TSequencerForm.ScrubToTime(const NewTimeSec: Single);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if Seq = nil then
    Exit;
  Seq.EvaluateAtTime(NewTimeSec);
  UpdatePlayheadLabel;
  PaintBoxTimeline.Invalidate;
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport;
end;

procedure TSequencerForm.PreviewTimerTick(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if (Seq = nil) or (not Seq.Playing) then
  begin
    FPreviewTimer.Enabled := false;
    ButtonPlayPause.Caption := 'Play';
    Exit;
  end;

  Seq.Step(0.033);
  if not Seq.Playing then
  begin
    FPreviewTimer.Enabled := false;
    ButtonPlayPause.Caption := 'Play';
  end;
  UpdatePlayheadLabel;
  PaintBoxTimeline.Invalidate;
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport;
end;

procedure TSequencerForm.ComboSequenceChange(Sender: TObject);
begin
  FPreviewTimer.Enabled := false;
  ButtonPlayPause.Caption := 'Play';
  SyncSnapshotFromActiveSequence;
end;

procedure TSequencerForm.ButtonNewSequenceClick(Sender: TObject);
var
  NewSeq: TCastleSequencePlayer;
begin
  NewSeq := TSequencerHelper.CreateSequencePlayerInDesign(
    FRootComponent, FDesignOwner, 'Cutscene', 5.0, true);
  if NewSeq <> nil then
  begin
    if Assigned(FOnModified) then
      FOnModified('Create Sequence Player ' + NewSeq.Name);
    RefreshSequenceList(NewSeq);
  end;
end;

procedure TSequencerForm.ButtonRewindClick(Sender: TObject);
begin
  ScrubToTime(0.0);
end;

procedure TSequencerForm.ButtonPlayPauseClick(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if Seq = nil then
    Exit;
  if Seq.Playing then
  begin
    Seq.Pause;
    FPreviewTimer.Enabled := false;
    ButtonPlayPause.Caption := 'Play';
  end else
  begin
    Seq.Play;
    FPreviewTimer.Enabled := true;
    ButtonPlayPause.Caption := 'Pause';
  end;
end;

procedure TSequencerForm.ButtonStopClick(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if Seq = nil then
    Exit;
  Seq.Stop;
  FPreviewTimer.Enabled := false;
  ButtonPlayPause.Caption := 'Play';
  UpdatePlayheadLabel;
  PaintBoxTimeline.Invalidate;
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport;
end;

procedure TSequencerForm.ComboPlaybackModeChange(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if (Seq <> nil) and (ComboPlaybackMode.ItemIndex >= 0) then
    Seq.PlaybackMode := TSequencePlaybackMode(ComboPlaybackMode.ItemIndex);
end;

procedure TSequencerForm.SpinDurationChange(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if Seq <> nil then
  begin
    Seq.Duration := SpinDuration.Value;
    UpdatePlayheadLabel;
    PaintBoxTimeline.Invalidate;
  end;
end;

procedure TSequencerForm.SpinTimeScaleChange(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if Seq <> nil then
    Seq.TimeScale := SpinTimeScale.Value;
end;

procedure TSequencerForm.PaintBoxTimelinePaint(Sender: TObject);
var
  C: TCanvas;
  W, H, LeftM, TopTracksY, RowTop, KX, CY, PlayX, I, K, StepCount: Integer;
  Seq: TCastleSequencePlayer;
  Dur, TickStep, T: Single;
  Diamond: array [0..3] of TPoint;
  TrackCol: TColor;
  HeaderLabel: String;
begin
  C := PaintBoxTimeline.Canvas;
  W := PaintBoxTimeline.Width;
  H := PaintBoxTimeline.Height;
  LeftM := TimelineLeftMargin;

  { Background }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(22, 26, 34);
  C.FillRect(0, 0, W, H);

  { Left Track Header Gutter }
  C.Brush.Color := RGBToColor(30, 35, 46);
  C.FillRect(0, 0, LeftM, H);

  { Top Ruler Bar }
  C.Brush.Color := RGBToColor(16, 20, 27);
  C.FillRect(0, 0, W, RulerHeightPx);
  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(185, 205, 230);
  C.TextOut(10, 6, 'Track / Target.Property');

  Seq := ActiveSequence;
  if Seq = nil then
  begin
    C.Font.Color := RGBToColor(170, 185, 205);
    C.TextOut(LeftM + 24, H div 2 - 10,
      'Click "+ New Sequence" above to create a multi-track timeline in this design.');
    Exit;
  end;

  Dur := Max(0.1, Seq.Duration);
  if Dur <= 3.0 then
    TickStep := 0.25
  else if Dur <= 10.0 then
    TickStep := 0.5
  else if Dur <= 30.0 then
    TickStep := 2.0
  else
    TickStep := 5.0;

  { Draw Time Ruler ticks & vertical gridlines }
  StepCount := Round(Dur / TickStep);
  for I := 0 to StepCount do
  begin
    T := Min(Dur, I * TickStep);
    KX := TimeToPixelX(T);
    C.Pen.Style := psSolid;
    C.Pen.Color := RGBToColor(38, 46, 60);
    C.Line(KX, RulerHeightPx, KX, H);
    C.Pen.Color := RGBToColor(110, 130, 158);
    C.Line(KX, RulerHeightPx - 7, KX, RulerHeightPx);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(175, 195, 220);
    C.TextOut(KX - 10, 5, Format('%.1fs', [T]));
  end;

  { Cue Marker Lane }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(28, 32, 42);
  C.FillRect(0, RulerHeightPx, W, RulerHeightPx + CueLaneHeightPx);
  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(235, 195, 85);
  C.TextOut(10, RulerHeightPx + 4, 'Event Cues');
  for I := 0 to High(FCuesSnapshot) do
  begin
    KX := TimeToPixelX(FCuesSnapshot[I].TimeSec);
    CY := RulerHeightPx + CueLaneHeightPx div 2;
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(245, 196, 62);
    C.Pen.Color := RGBToColor(255, 230, 130);
    C.Rectangle(KX - 4, CY - 6, KX + 5, CY + 6);
    C.Brush.Style := bsClear;
    C.TextOut(KX + 7, RulerHeightPx + 4, FCuesSnapshot[I].CueName);
  end;

  { Track Rows & Keyframe Diamonds }
  TopTracksY := RulerHeightPx + CueLaneHeightPx;
  for I := 0 to High(FTracksSnapshot) do
  begin
    RowTop := TopTracksY + I * RowHeightPx;
    C.Brush.Style := bsSolid;
    if I = FSelectedTrackIdx then
      C.Brush.Color := RGBToColor(44, 62, 88)
    else if (I and 1) = 0 then
      C.Brush.Color := RGBToColor(25, 30, 40)
    else
      C.Brush.Color := RGBToColor(29, 35, 46);
    C.FillRect(0, RowTop, W, RowTop + RowHeightPx);

    case FTracksSnapshot[I].Kind of
      stkVector3Property: TrackCol := RGBToColor(68, 208, 245);
      stkFloatProperty:   TrackCol := RGBToColor(62, 225, 150);
      stkBoolProperty:    TrackCol := RGBToColor(245, 178, 66);
      stkStringProperty:  TrackCol := RGBToColor(186, 132, 250);
      stkCameraCut:       TrackCol := RGBToColor(250, 98, 135);
    end;
    if FTracksSnapshot[I].Muted then
      TrackCol := RGBToColor(115, 122, 135);

    { Color accent bar }
    C.Brush.Color := TrackCol;
    C.FillRect(0, RowTop + 2, 5, RowTop + RowHeightPx - 2);

    HeaderLabel := FTracksSnapshot[I].TargetName + '.' + FTracksSnapshot[I].PropPath;
    if FTracksSnapshot[I].Muted then
      HeaderLabel := '[M] ' + HeaderLabel;
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(225, 234, 246);
    C.TextOut(10, RowTop + 7, Copy(HeaderLabel, 1, 28));

    { Connecting span line between first and last keyframe }
    if Length(FTracksSnapshot[I].Keys) >= 2 then
    begin
      C.Pen.Color := TrackCol;
      C.Pen.Width := 2;
      C.Line(
        TimeToPixelX(FTracksSnapshot[I].Keys[0].TimeSec),
        RowTop + RowHeightPx div 2,
        TimeToPixelX(FTracksSnapshot[I].Keys[High(FTracksSnapshot[I].Keys)].TimeSec),
        RowTop + RowHeightPx div 2);
      C.Pen.Width := 1;
    end;

    { Keyframe Diamonds }
    for K := 0 to High(FTracksSnapshot[I].Keys) do
    begin
      KX := TimeToPixelX(FTracksSnapshot[I].Keys[K].TimeSec);
      CY := RowTop + RowHeightPx div 2;
      Diamond[0] := Point(KX, CY - 6);
      Diamond[1] := Point(KX + 6, CY);
      Diamond[2] := Point(KX, CY + 6);
      Diamond[3] := Point(KX - 6, CY);
      C.Brush.Style := bsSolid;
      C.Brush.Color := TrackCol;
      C.Pen.Color := RGBToColor(255, 255, 255);
      C.Polygon(Diamond);
    end;
  end;

  { Gutter divider }
  C.Pen.Color := RGBToColor(68, 82, 104);
  C.Line(LeftM, 0, LeftM, H);

  { Red Playhead Line + Cap }
  PlayX := TimeToPixelX(Seq.CurrentTime);
  C.Pen.Color := RGBToColor(255, 76, 88);
  C.Pen.Width := 2;
  C.Line(PlayX, 0, PlayX, H);
  C.Pen.Width := 1;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(255, 76, 88);
  C.Rectangle(PlayX - 6, 0, PlayX + 7, 13);
end;

procedure TSequencerForm.PaintBoxTimelineMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  RowIdx: Integer;
begin
  if ActiveSequence = nil then
    Exit;

  if Y >= RulerHeightPx + CueLaneHeightPx then
  begin
    RowIdx := (Y - RulerHeightPx - CueLaneHeightPx) div RowHeightPx;
    if (RowIdx >= 0) and (RowIdx <= High(FTracksSnapshot)) then
    begin
      FSelectedTrackIdx := RowIdx;
      PaintBoxTimeline.Invalidate;
    end;
  end;

  if (Button = mbLeft) and (X >= TimelineLeftMargin - 6) then
  begin
    FScrubbingPlayhead := true;
    ScrubToTime(PixelXToTime(X));
  end;
end;

procedure TSequencerForm.PaintBoxTimelineMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  if FScrubbingPlayhead then
    ScrubToTime(PixelXToTime(X));
end;

procedure TSequencerForm.PaintBoxTimelineMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    FScrubbingPlayhead := false;
end;

procedure TSequencerForm.ButtonCaptureLiveKeyClick(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
  TargetC: TComponent;
  Ease: TSequenceEasing;
begin
  Seq := ActiveSequence;
  if Seq = nil then
  begin
    ButtonNewSequenceClick(Sender);
    Seq := ActiveSequence;
  end;
  if (Seq = nil) or (ComboTargetComp.ItemIndex < 0) or
     (ComboTargetComp.ItemIndex >= FTargetComps.Count) then
    Exit;

  TargetC := TComponent(FTargetComps.Objects[ComboTargetComp.ItemIndex]);
  case ComboEasing.ItemIndex of
    1: Ease := seLinear;
    2: Ease := seEaseInCubic;
    3: Ease := seEaseOutCubic;
    4: Ease := seStep;
  else
    Ease := seSmoothStep;
  end;

  if TSequencerHelper.CaptureLivePropertyKey(
       Seq, TargetC, Trim(ComboPropPath.Text), Seq.CurrentTime, Ease) then
  begin
    if Assigned(FOnModified) then
      FOnModified(Format('Keyframe %s.%s at %.2fs',
        [TargetC.Name, Trim(ComboPropPath.Text), Seq.CurrentTime]));
    SyncSnapshotFromActiveSequence;
  end else
    MessageDlg('Sequencer',
      Format('Could not read property "%s" on "%s".',
        [Trim(ComboPropPath.Text), TargetC.Name]),
      mtWarning, [mbOK], 0);
end;

procedure TSequencerForm.ButtonAddCameraCutClick(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
  Vp: TCastleViewport;
  CamName: String;
begin
  Seq := ActiveSequence;
  if Seq = nil then
  begin
    ButtonNewSequenceClick(Sender);
    Seq := ActiveSequence;
  end;
  Vp := TSequencerHelper.FindFirstViewport(FRootComponent);
  if (Seq = nil) or (Vp = nil) or (Trim(Vp.Name) = '') or
     (ComboCameraCut.ItemIndex < 0) then
    Exit;

  CamName := ComboCameraCut.Items[ComboCameraCut.ItemIndex];
  Seq.AddOrUpdateCameraCutKey(Vp.Name, Seq.CurrentTime, CamName);
  Seq.EvaluateAtTime(Seq.CurrentTime);
  if Assigned(FOnModified) then
    FOnModified(Format('Add Camera Cut to %s at %.2fs', [CamName, Seq.CurrentTime]));
  SyncSnapshotFromActiveSequence;
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport;
end;

procedure TSequencerForm.ButtonAddCueClick(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
  CueName: String;
begin
  Seq := ActiveSequence;
  if Seq = nil then
    Exit;
  CueName := 'OnCueEvent';
  if InputQuery('Add Event Cue Marker',
       Format('Cue name at t = %.2fs:', [Seq.CurrentTime]), CueName) and
     (Trim(CueName) <> '') then
  begin
    Seq.AddEventCue(Seq.CurrentTime, Trim(CueName), '');
    if Assigned(FOnModified) then
      FOnModified('Add Sequence Event Cue ' + Trim(CueName));
    SyncSnapshotFromActiveSequence;
  end;
end;

procedure TSequencerForm.ButtonToggleMuteTrackClick(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if (Seq = nil) or (FSelectedTrackIdx < 0) or
     (FSelectedTrackIdx > High(FTracksSnapshot)) then
    Exit;
  Seq.SetTrackMuted(FSelectedTrackIdx, not FTracksSnapshot[FSelectedTrackIdx].Muted);
  if Assigned(FOnModified) then
    FOnModified('Toggle Sequence Track Mute');
  SyncSnapshotFromActiveSequence;
end;

procedure TSequencerForm.ButtonDeleteTrackClick(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if (Seq = nil) or (FSelectedTrackIdx < 0) or
     (FSelectedTrackIdx > High(FTracksSnapshot)) then
    Exit;
  if Seq.RemoveTrack(FSelectedTrackIdx) then
  begin
    if Assigned(FOnModified) then
      FOnModified('Delete Sequence Track');
    SyncSnapshotFromActiveSequence;
  end;
end;

procedure TSequencerForm.ButtonCopyMarkdownClick(Sender: TObject);
var
  Seq: TCastleSequencePlayer;
begin
  Seq := ActiveSequence;
  if Seq <> nil then
    Clipboard.AsText := TSequencerHelper.FormatSequenceMarkdown(Seq);
end;

procedure TSequencerForm.ButtonCloseClick(Sender: TObject);
begin
  FPreviewTimer.Enabled := false;
  ModalResult := mrOk;
end;

end.
