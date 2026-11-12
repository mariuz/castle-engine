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

{ Interactive SaveGame Slot Manager, Versioned World-State Snapshot &
  Deterministic Replay Recorder Studio (@link(TSaveReplayForm)) featuring
  1-click QuickSave / Checkpoint slot capture & restore, deterministic keyframe
  recording + cue markers, an interactive clickable Replay Scrub Timeline
  canvas, and Markdown/JSON export (Phase 315). }
unit FormSaveReplay;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleSaveReplay, ToolSaveReplay;

type
  TSaveReplayModifiedCallback = procedure(const AComment: String) of object;
  TSaveReplayRefreshViewportCallback = procedure of object;

  TSaveReplayForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSaveReplayModifiedCallback;
    FOnRefreshViewport: TSaveReplayRefreshViewportCallback;

    FReport: TSaveReplayAuditReport;

    LblHeader: TLabel;
    ListSlots: TListBox;
    ListCues: TListBox;
    PaintTimeline: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function ActiveSaveMgr: TCastleSaveSlotManager;
    function ActiveReplay: TCastleReplayRecorder;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnEnsureManagersClick(Sender: TObject);
    procedure BtnCaptureQuickSaveClick(Sender: TObject);
    procedure BtnCaptureCheckpointClick(Sender: TObject);
    procedure BtnRestoreSelectedSlotClick(Sender: TObject);
    procedure BtnDeleteSelectedSlotClick(Sender: TObject);
    procedure BtnRecordKeyframeClick(Sender: TObject);
    procedure BtnRecordCueMarkerClick(Sender: TObject);
    procedure BtnCopyReplayJsonClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintTimelinePaint(Sender: TObject);
    procedure PaintTimelineMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSaveReplayModifiedCallback;
      const AOnRefreshViewport: TSaveReplayRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TSaveReplayForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSaveReplayModifiedCallback;
  const AOnRefreshViewport: TSaveReplayRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'SaveGame Slot Manager, Versioned Checkpoint & Deterministic Replay Studio';
  Width := 1120;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TSaveReplayForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TSaveReplayForm.BuildUi;
var
  PanelTop, RowTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
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
  LblHeader.Caption := 'SaveGame & Deterministic Replay Studio — Schema Checkpoints & Timeline Scrubbing';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 30, 1100, 38);
  RowTop.BevelOuter := bvNone;

  MakeBtn(RowTop, '+ Ensure Save & Replay Managers', 4, 4, 232, @BtnEnsureManagersClick);
  MakeBtn(RowTop, 'Capture QuickSave0', 242, 4, 168, @BtnCaptureQuickSaveClick);
  MakeBtn(RowTop, '+ New Checkpoint Slot', 416, 4, 178, @BtnCaptureCheckpointClick);
  MakeBtn(RowTop, 'Record Replay Frame (+0.25s)', 600, 4, 218, @BtnRecordKeyframeClick);
  MakeBtn(RowTop, '+ Cue Marker', 824, 4, 130, @BtnRecordCueMarkerClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Markdown Report', 12, 6, 190, @BtnCopyMarkdownClick);
  MakeBtn(PanelBottom, 'Copy Replay JSON', 210, 6, 165, @BtnCopyReplayJsonClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 990, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 365;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 320, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'SaveGame & Checkpoint Slots:';

  ListSlots := TListBox.Create(Self);
  ListSlots.Parent := PanelLeft;
  ListSlots.SetBounds(10, 26, 345, 210);

  MakeBtn(PanelLeft, 'Restore Selected Save Slot', 10, 244, 220, @BtnRestoreSelectedSlotClick);
  MakeBtn(PanelLeft, 'Delete Slot', 236, 244, 119, @BtnDeleteSelectedSlotClick);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 284, 320, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Replay Timeline Cue Events:';

  ListCues := TListBox.Create(Self);
  ListCues.Parent := PanelLeft;
  ListCues.SetBounds(10, 304, 345, 236);

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintTimeline := TPaintBox.Create(Self);
  PaintTimeline.Parent := PanelCenter;
  PaintTimeline.Align := alTop;
  PaintTimeline.Height := 250;
  PaintTimeline.OnPaint := @PaintTimelinePaint;
  PaintTimeline.OnMouseDown := @PaintTimelineMouseDown;

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelCenter;
  MemoDiag.Align := alClient;
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;
  MemoDiag.Font.Name := 'Monospace';
end;

function TSaveReplayForm.ActiveSaveMgr: TCastleSaveSlotManager;
begin
  if (FReport <> nil) and (Length(FReport.SaveManagers) > 0) then
    Result := FReport.SaveManagers[0]
  else
    Result := nil;
end;

function TSaveReplayForm.ActiveReplay: TCastleReplayRecorder;
begin
  if (FReport <> nil) and (Length(FReport.ReplayRecorders) > 0) then
    Result := FReport.ReplayRecorders[0]
  else
    Result := nil;
end;

procedure TSaveReplayForm.RefreshAll;
var
  SM: TCastleSaveSlotManager;
  RR: TCastleReplayRecorder;
  I, PrevIdx: Integer;
begin
  PrevIdx := ListSlots.ItemIndex;
  FreeAndNil(FReport);
  FReport := TSaveReplayHelper.ScanDesign(FDesignRoot, FDesignOwner);

  SM := ActiveSaveMgr;
  ListSlots.Items.BeginUpdate;
  try
    ListSlots.Items.Clear;
    if SM <> nil then
      for I := 0 to SM.Slots.Count - 1 do
        ListSlots.Items.Add(Format('%s — "%s" (v%d, %s)',
          [SM.Slots[I].SlotId, SM.Slots[I].SlotTitle,
           SM.Slots[I].SchemaVersion, SM.Slots[I].TimestampIso]));
    if ListSlots.Items.Count > 0 then
      ListSlots.ItemIndex := Clamped(Max(0, PrevIdx), 0, ListSlots.Items.Count - 1);
  finally
    ListSlots.Items.EndUpdate;
  end;

  RR := ActiveReplay;
  ListCues.Items.BeginUpdate;
  try
    ListCues.Items.Clear;
    if RR <> nil then
      for I := 0 to RR.CueEvents.Count - 1 do
        ListCues.Items.Add(Format('[%.2fs] %s (%s)',
          [RR.CueEvents[I].TimeSec, RR.CueEvents[I].CueId, RR.CueEvents[I].Payload]));
  finally
    ListCues.Items.EndUpdate;
  end;

  LblHeader.Caption := Format(
    'SaveGame & Replay Studio — %d Save Slot(s) | %d Replay Keyframe(s) (Click Timeline to Scrub)',
    [FReport.TotalSaveSlots, FReport.TotalReplayFrames]);

  MemoDiag.Lines.Text := TSaveReplayHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintTimeline.Invalidate;
end;

procedure TSaveReplayForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TSaveReplayForm.BtnEnsureManagersClick(Sender: TObject);
begin
  TSaveReplayHelper.EnsureSaveSlotManagerInDesign(FDesignRoot, FDesignOwner);
  TSaveReplayHelper.EnsureReplayRecorderInDesign(FDesignRoot, FDesignOwner);
  NotifyChanged('Add SaveSlotManager & ReplayRecorder');
end;

procedure TSaveReplayForm.BtnCaptureQuickSaveClick(Sender: TObject);
var
  SM: TCastleSaveSlotManager;
begin
  SM := TSaveReplayHelper.EnsureSaveSlotManagerInDesign(FDesignRoot, FDesignOwner);
  SM.SaveSlot('QuickSave0', 'QuickSave Snapshot', FDesignRoot, FDesignOwner);
  NotifyChanged('Capture QuickSave0 World Snapshot');
end;

procedure TSaveReplayForm.BtnCaptureCheckpointClick(Sender: TObject);
var
  SM: TCastleSaveSlotManager;
  SlotName: String;
begin
  SM := TSaveReplayHelper.EnsureSaveSlotManagerInDesign(FDesignRoot, FDesignOwner);
  SlotName := Format('Checkpoint%d', [SM.Slots.Count + 1]);
  SM.SaveSlot(SlotName, 'Editor World Checkpoint', FDesignRoot, FDesignOwner);
  NotifyChanged('Capture ' + SlotName);
end;

procedure TSaveReplayForm.BtnRestoreSelectedSlotClick(Sender: TObject);
var
  SM: TCastleSaveSlotManager;
  Idx: Integer;
begin
  SM := ActiveSaveMgr;
  Idx := ListSlots.ItemIndex;
  if (SM = nil) or (Idx < 0) or (Idx >= SM.Slots.Count) then
    Exit;
  if SM.LoadSlot(SM.Slots[Idx].SlotId, FDesignRoot, FDesignOwner) then
    NotifyChanged('Restore Save Slot ' + SM.Slots[Idx].SlotId);
end;

procedure TSaveReplayForm.BtnDeleteSelectedSlotClick(Sender: TObject);
var
  SM: TCastleSaveSlotManager;
  Idx: Integer;
begin
  SM := ActiveSaveMgr;
  Idx := ListSlots.ItemIndex;
  if (SM = nil) or (Idx < 0) or (Idx >= SM.Slots.Count) then
    Exit;
  SM.DeleteSlot(SM.Slots[Idx].SlotId);
  NotifyChanged('Delete Save Slot');
end;

procedure TSaveReplayForm.BtnRecordKeyframeClick(Sender: TObject);
var
  RR: TCastleReplayRecorder;
begin
  RR := TSaveReplayHelper.EnsureReplayRecorderInDesign(FDesignRoot, FDesignOwner);
  if RR.FrameCount = 0 then
    RR.RecordFrame(FDesignRoot, 0.0, FDesignOwner)
  else
    RR.RecordFrame(FDesignRoot, 0.25, FDesignOwner);
  NotifyChanged('Record Replay Keyframe');
end;

procedure TSaveReplayForm.BtnRecordCueMarkerClick(Sender: TObject);
var
  RR: TCastleReplayRecorder;
begin
  RR := TSaveReplayHelper.EnsureReplayRecorderInDesign(FDesignRoot, FDesignOwner);
  if RR.FrameCount = 0 then
    RR.RecordFrame(FDesignRoot, 0.0, FDesignOwner);
  RR.RecordCue(Format('Cue_%d', [RR.CueEvents.Count + 1]), 'EditorBookmark');
  NotifyChanged('Record Replay Cue Marker');
end;

procedure TSaveReplayForm.BtnCopyReplayJsonClick(Sender: TObject);
var
  RR: TCastleReplayRecorder;
begin
  RR := ActiveReplay;
  if RR <> nil then
    Clipboard.AsText := RR.ExportReplayJson;
end;

procedure TSaveReplayForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TSaveReplayHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TSaveReplayForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TSaveReplayForm.PaintTimelinePaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, BarX0, BarX1, BarY, BarH, I, KX, PlayX: Integer;
  RR: TCastleReplayRecorder;
  Dur, U: Single;
begin
  Cv := PaintTimeline.Canvas;
  W := PaintTimeline.Width;
  H := PaintTimeline.Height;

  Cv.Brush.Color := RGBToColor(18, 22, 30);
  Cv.FillRect(0, 0, W, H);

  BarX0 := 28;
  BarX1 := Max(BarX0 + 100, W - 28);
  BarY := 72;
  BarH := 78;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := RGBToColor(220, 232, 248);
  Cv.TextOut(BarX0, 14, 'Deterministic Replay Scrubber (Click anywhere on track to interpolate world pose)');

  Cv.Brush.Style := bsSolid;
  Cv.Brush.Color := RGBToColor(26, 32, 44);
  Cv.Pen.Color := RGBToColor(68, 86, 114);
  Cv.Rectangle(BarX0, BarY, BarX1, BarY + BarH);

  RR := ActiveReplay;
  if (RR = nil) or (RR.FrameCount = 0) then
  begin
    Cv.Brush.Style := bsClear;
    Cv.Font.Color := RGBToColor(150, 165, 190);
    Cv.TextOut(BarX0 + 16, BarY + 28,
      'No keyframes recorded yet — move 3D transforms and click "Record Replay Frame (+0.25s)".');
    Exit;
  end;

  Dur := Max(0.01, RR.DurationSec);

  { Draw keyframe diamonds }
  for I := 0 to RR.Keyframes.Count - 1 do
  begin
    U := Clamped(RR.Keyframes[I].TimeSec / Dur, 0.0, 1.0);
    KX := BarX0 + Round(U * (BarX1 - BarX0));
    Cv.Brush.Style := bsSolid;
    Cv.Brush.Color := RGBToColor(86, 186, 248);
    Cv.Pen.Color := clWhite;
    Cv.Ellipse(KX - 5, BarY + 22, KX + 5, BarY + 32);
  end;

  { Draw cue flags }
  for I := 0 to RR.CueEvents.Count - 1 do
  begin
    U := Clamped(RR.CueEvents[I].TimeSec / Dur, 0.0, 1.0);
    KX := BarX0 + Round(U * (BarX1 - BarX0));
    Cv.Pen.Color := RGBToColor(250, 196, 76);
    Cv.Line(KX, BarY + 42, KX, BarY + BarH - 6);
  end;

  { Draw scrub playhead }
  U := Clamped(RR.CurrentScrubTimeSec / Dur, 0.0, 1.0);
  PlayX := BarX0 + Round(U * (BarX1 - BarX0));
  Cv.Pen.Color := RGBToColor(255, 92, 92);
  Cv.Pen.Width := 2;
  Cv.Line(PlayX, BarY - 10, PlayX, BarY + BarH + 10);
  Cv.Pen.Width := 1;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := RGBToColor(255, 196, 128);
  Cv.TextOut(BarX0, BarY + BarH + 22,
    Format('Scrub Time: %s s / %s s  |  Keyframes: %d  |  Cues: %d',
      [FormatDot('%.2f', [RR.CurrentScrubTimeSec]),
       FormatDot('%.2f', [RR.DurationSec]),
       RR.FrameCount, RR.CueEvents.Count]));
end;

procedure TSaveReplayForm.PaintTimelineMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  RR: TCastleReplayRecorder;
  BarX0, BarX1: Integer;
  U: Single;
begin
  RR := ActiveReplay;
  if (RR = nil) or (RR.FrameCount = 0) then
    Exit;
  BarX0 := 28;
  BarX1 := Max(BarX0 + 100, PaintTimeline.Width - 28);
  U := Clamped((X - BarX0) / (BarX1 - BarX0), 0.0, 1.0);
  RR.ScrubToTime(FDesignRoot, U * RR.DurationSec, FDesignOwner);
  NotifyChanged('Scrub Replay to ' + FormatDot('%.2f', [RR.CurrentScrubTimeSec]) + 's');
end;

end.
