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

{ Interactive MetaSound Procedural PCM Synth, Surface-Tagged Footstep Switcher
  & Quartz Beat-Quantized Music Stem Studio (@link(TMetaSoundStudioForm))
  featuring a live PCM Oscilloscope + ADSR Envelope + 4-Stem Beat-Grid Mixer
  canvas (Phase 322). }
unit FormMetaSoundStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleMetaSound, ToolMetaSoundStudio;

type
  TMetaSoundStudioModifiedCallback = procedure(const AComment: String) of object;
  TMetaSoundStudioRefreshViewportCallback = procedure of object;

  TMetaSoundStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMetaSoundStudioModifiedCallback;
    FOnRefreshViewport: TMetaSoundStudioRefreshViewportCallback;

    FSynths: TMetaSynthArray;
    FFoots: TFootstepBehaviorArray;
    FDirs: TMusicDirectorArray;
    FSamples: TSinglePcmArray;
    FReport: TMetaSoundAuditReport;

    LblHeader: TLabel;
    ListItems: TListBox;
    PaintScope: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function ActiveSynth: TCastleMetaSoundSynth;
    function ActiveFoot: TCastleFootstepSurfaceBehavior;
    function ActiveDir: TCastleMusicStemDirector;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnPresetLaserClick(Sender: TObject);
    procedure BtnPresetChimeClick(Sender: TObject);
    procedure BtnPresetBoomClick(Sender: TObject);
    procedure BtnStepWalkerClick(Sender: TObject);
    procedure BtnQueueCombatStemClick(Sender: TObject);
    procedure BtnStepQuartzClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintScopePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMetaSoundStudioModifiedCallback;
      const AOnRefreshViewport: TMetaSoundStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TMetaSoundStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMetaSoundStudioModifiedCallback;
  const AOnRefreshViewport: TMetaSoundStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'MetaSound Procedural PCM Synth, Surface Footsteps & Quartz Music Studio';
  Width := 1140;
  Height := 710;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TMetaSoundStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TMetaSoundStudioForm.BuildUi;
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
  LblHeader.Caption := 'MetaSound & Quartz Audio: scanning...';

  Row1 := TPanel.Create(Self);
  Row1.Parent := PanelTop;
  Row1.SetBounds(8, 32, 1120, 32);
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn MetaSound + Footsteps + Quartz', 4, 2, 265, @BtnSpawnDemoClick);
  MakeBtn(Row1, 'Patch: Laser Zap', 275, 2, 140, @BtnPresetLaserClick);
  MakeBtn(Row1, 'Patch: Crystal Chime', 421, 2, 155, @BtnPresetChimeClick);
  MakeBtn(Row1, 'Patch: Sub-Boom', 582, 2, 140, @BtnPresetBoomClick);
  MakeBtn(Row1, 'Copy Markdown', 728, 2, 140, @BtnCopyMarkdownClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := PanelTop;
  Row2.SetBounds(8, 68, 1120, 32);
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Walk Across Stone/Wood/Metal (+2.5m)', 4, 2, 260, @BtnStepWalkerClick);
  MakeBtn(Row2, 'Queue Combat Stem (Next Bar)', 270, 2, 215, @BtnQueueCombatStemClick);
  MakeBtn(Row2, 'Step Quartz Clock (+0.25s)', 491, 2, 195, @BtnStepQuartzClick);

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
  Lbl.Caption := 'MetaSound, Footstep & Quartz Nodes:';

  ListItems := TListBox.Create(Self);
  ListItems.Parent := PanelLeft;
  ListItems.SetBounds(10, 26, 320, 225);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 260, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'PCM RMS, Surface Hits & Musical Clock:';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelLeft;
  MemoDiag.SetBounds(10, 282, 320, 265);
  MemoDiag.Anchors := [akTop, akLeft, akBottom];
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintScope := TPaintBox.Create(Self);
  PaintScope.Parent := PanelCenter;
  PaintScope.Align := alClient;
  PaintScope.OnPaint := @PaintScopePaint;
end;

function TMetaSoundStudioForm.ActiveSynth: TCastleMetaSoundSynth;
begin
  if Length(FSynths) > 0 then Result := FSynths[0] else Result := nil;
end;

function TMetaSoundStudioForm.ActiveFoot: TCastleFootstepSurfaceBehavior;
begin
  if Length(FFoots) > 0 then Result := FFoots[0] else Result := nil;
end;

function TMetaSoundStudioForm.ActiveDir: TCastleMusicStemDirector;
begin
  if Length(FDirs) > 0 then Result := FDirs[0] else Result := nil;
end;

procedure TMetaSoundStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TMetaSoundStudioForm.RefreshAll;
var
  I: Integer;
  S: TCastleMetaSoundSynth;
  F: TCastleFootstepSurfaceBehavior;
  D: TCastleMusicStemDirector;
begin
  TMetaSoundStudioHelper.ScanMetaSound(FDesignRoot, FDesignOwner, FSynths, FFoots, FDirs);
  FreeAndNil(FReport);
  FReport := TMetaSoundStudioHelper.AuditMetaSound(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'MetaSound Synths: %d  |  Surface Footsteps: %d  |  Quartz Stem Directors: %d  |  QA Warnings: %d',
    [FReport.SynthCount, FReport.FootstepCount, FReport.MusicDirectorCount, FReport.Warnings.Count]);

  ListItems.Items.BeginUpdate;
  try
    ListItems.Items.Clear;
    for I := 0 to High(FSynths) do
      ListItems.Items.Add(FSynths[I].Name + '  ' + FSynths[I].SynthSummaryBadge);
    for I := 0 to High(FFoots) do
      ListItems.Items.Add(FFoots[I].Name + '  ' + FFoots[I].FootstepSummaryBadge);
    for I := 0 to High(FDirs) do
      ListItems.Items.Add(FDirs[I].Name + '  ' + FDirs[I].MusicSummaryBadge);
  finally
    ListItems.Items.EndUpdate;
  end;

  S := ActiveSynth;
  if S <> nil then
    S.SynthesizePcmSamples(FSamples)
  else
    FSamples := nil;

  MemoDiag.Lines.BeginUpdate;
  try
    MemoDiag.Lines.Clear;
    if S <> nil then
      MemoDiag.Lines.Add(Format('Synth Peak=%.2f  RMS=%.2f  Samples=%d',
        [S.LastPeakAmplitude, S.LastRmsAmplitude, Length(FSamples)]));
    F := ActiveFoot;
    if F <> nil then
      MemoDiag.Lines.Add(Format('Footstep Surface=%s  Freq=%.0fHz  Cutoff=%.0fHz',
        [TCastleFootstepSurfaceBehavior.SurfaceDisplayName(F.LastSurface),
         F.LastStepFreqHz, F.LastStepCutoffHz]));
    D := ActiveDir;
    if D <> nil then
      MemoDiag.Lines.Add(Format('Quartz Clock=%.2fs  Bar %d.%d  Pending=%d',
        [D.ClockSec, D.CurrentBarNumber, D.CurrentBeatInBar, D.PendingStateIndex]));
    MemoDiag.Lines.Add('');
    if FReport.Warnings.Count = 0 then
      MemoDiag.Lines.Add('[OK] All procedural audio & Quartz stem nodes healthy.')
    else
      for I := 0 to FReport.Warnings.Count - 1 do
        MemoDiag.Lines.Add('[WARN] ' + FReport.Warnings[I]);
  finally
    MemoDiag.Lines.EndUpdate;
  end;

  PaintScope.Invalidate;
end;

procedure TMetaSoundStudioForm.BtnSpawnDemoClick(Sender: TObject);
var
  S: TCastleMetaSoundSynth;
  W: TCastleTransform;
  F: TCastleFootstepSurfaceBehavior;
  D: TCastleMusicStemDirector;
begin
  TMetaSoundStudioHelper.SpawnAudioPlaygroundDemo(FDesignRoot, FDesignOwner, S, W, F, D);
  NotifyChanged('Spawn MetaSound + Surface Footsteps + Quartz Demo');
end;

procedure TMetaSoundStudioForm.BtnPresetLaserClick(Sender: TObject);
var S: TCastleMetaSoundSynth;
begin
  S := ActiveSynth; if S = nil then Exit;
  S.ApplyPreset(mspLaserZapDownSweep);
  NotifyChanged('MetaSound Patch: Sci-Fi Laser Zap');
end;

procedure TMetaSoundStudioForm.BtnPresetChimeClick(Sender: TObject);
var S: TCastleMetaSoundSynth;
begin
  S := ActiveSynth; if S = nil then Exit;
  S.ApplyPreset(mspUiCrystalChime);
  NotifyChanged('MetaSound Patch: UI Crystal Chime');
end;

procedure TMetaSoundStudioForm.BtnPresetBoomClick(Sender: TObject);
var S: TCastleMetaSoundSynth;
begin
  S := ActiveSynth; if S = nil then Exit;
  S.ApplyPreset(mspExplosionSubBoom);
  NotifyChanged('MetaSound Patch: Explosion Sub-Boom');
end;

procedure TMetaSoundStudioForm.BtnStepWalkerClick(Sender: TObject);
var
  F: TCastleFootstepSurfaceBehavior;
  NewX: Single;
begin
  F := ActiveFoot;
  if (F = nil) or (F.Parent = nil) then Exit;
  NewX := F.Parent.Translation.X + 2.5;
  if NewX > 6.5 then NewX := -5.0;
  F.Parent.Translation := Vector3(NewX, F.Parent.Translation.Y, F.Parent.Translation.Z);
  F.AccumulateTravelDistance(2.5);
  NotifyChanged('Walk Across Surface Pads');
end;

procedure TMetaSoundStudioForm.BtnQueueCombatStemClick(Sender: TObject);
var D: TCastleMusicStemDirector;
begin
  D := ActiveDir; if D = nil then Exit;
  if D.ActiveStateIndex = 2 then
    D.RequestMusicState(0)
  else
    D.RequestMusicState(2);
  NotifyChanged('Queue Quartz Stem Transition');
end;

procedure TMetaSoundStudioForm.BtnStepQuartzClick(Sender: TObject);
var D: TCastleMusicStemDirector;
begin
  D := ActiveDir; if D = nil then Exit;
  D.StepMusicClock(0.25);
  NotifyChanged('Step Quartz Musical Clock (+0.25s)');
end;

procedure TMetaSoundStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TMetaSoundStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TMetaSoundStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TMetaSoundStudioForm.PaintScopePaint(Sender: TObject);
var
  C: TCanvas;
  D: TCastleMusicStemDirector;
  W, H, ScL, ScR, ScT, ScB, MidY, I, Idx, Px, Py, PrevX, PrevY, BarW: Integer;
begin
  C := PaintScope.Canvas;
  W := Max(200, PaintScope.Width);
  H := Max(200, PaintScope.Height);
  C.Brush.Color := RGBToColor(20, 24, 31);
  C.FillRect(0, 0, W, H);

  if Length(FSamples) = 0 then
  begin
    C.Font.Color := RGBToColor(190, 202, 218);
    C.TextOut(24, 24, 'Click "+ Spawn MetaSound + Footsteps + Quartz" to visualize synthesized PCM waveforms & stems.');
    Exit;
  end;

  { Top half: PCM Oscilloscope }
  ScL := 24; ScR := W - 24; ScT := 40; ScB := (H * 54) div 100;
  MidY := (ScT + ScB) div 2;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.TextOut(ScL, 14, 'Synthesized 16-Bit PCM Waveform Oscilloscope (Biquad Low-Pass + ADSR)');
  C.Font.Style := [];
  C.Pen.Color := RGBToColor(64, 76, 94);
  C.Brush.Color := RGBToColor(28, 33, 42);
  C.Rectangle(ScL, ScT, ScR, ScB);

  PrevX := ScL; PrevY := MidY;
  C.Pen.Color := RGBToColor(68, 224, 156);
  for I := 0 to Max(1, ScR - ScL) do
  begin
    Idx := Round((I / Max(1, ScR - ScL)) * High(FSamples));
    Px := ScL + I;
    Py := MidY - Round(FSamples[Idx] * ((ScB - ScT) * 0.44));
    if I > 0 then C.Line(PrevX, PrevY, Px, Py);
    PrevX := Px; PrevY := Py;
  end;

  { Bottom half: Quartz 4-Stem Vertical Mixer }
  D := ActiveDir;
  if D <> nil then
  begin
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(232, 240, 250);
    C.Brush.Style := bsClear;
    C.TextOut(ScL, ScB + 18, Format('Quartz Beat-Quantized Stem Mixer — %s', [D.MusicSummaryBadge]));
    C.Font.Style := [];
    for I := 0 to 3 do
    begin
      Py := ScB + 50 + I * 36;
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(210, 220, 236);
      C.TextOut(ScL, Py + 4, TCastleMusicStemDirector.StemStateName(I));
      BarW := Round(Clamped(D.GetStemWeight(I), 0.0, 1.0) * (ScR - ScL - 120));
      C.Brush.Color := RGBToColor(40, 48, 60);
      C.FillRect(ScL + 95, Py, ScR, Py + 24);
      C.Brush.Color := RGBToColor(78, 174, 248);
      C.FillRect(ScL + 95, Py, ScL + 95 + BarW, Py + 24);
    end;
  end;
end;

end.
