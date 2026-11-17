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

{ Interactive Gameplay Cue Combat Feedback, Hit-Stop Time-Dilation, Camera Punch
  & Floating Damage-Number Pool Studio dialog (Phase 342). }
unit FormGameplayCue;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleGameplayCue, ToolGameplayCue;

type
  TGameplayCueModifyCallback = procedure(const AUndoComment: String) of object;
  TGameplayCueRefreshCallback = procedure of object;

  TGameplayCueForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TGameplayCueModifyCallback;
    FOnRefreshViewport: TGameplayCueRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintArena: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    function EnsureDirector: TCastleGameplayCueDirector;
    procedure BtnSpawnDummyClick(Sender: TObject);
    procedure BtnLightSlashClick(Sender: TObject);
    procedure BtnCritStrikeClick(Sender: TObject);
    procedure BtnHealPulseClick(Sender: TObject);
    procedure BtnShieldBlockClick(Sender: TObject);
    procedure BtnStepRealTimeClick(Sender: TObject);
    procedure BtnBurstStressClick(Sender: TObject);
    procedure BtnClearClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintArenaPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TGameplayCueModifyCallback;
      const AOnRefreshViewport: TGameplayCueRefreshCallback);
  end;

implementation

constructor TGameplayCueForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TGameplayCueModifyCallback;
  const AOnRefreshViewport: TGameplayCueRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Gameplay Cue Combat Feedback, Hit-Stop & Floating Damage-Number Pool Studio (UE 6.0+ Gameplay Cues Parity)';
  Width := 1040;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TGameplayCueForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 150): TButton;
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
  LabelHeader.Caption := 'Gameplay Cue Combat Director — Tag-Routed Impacts, Hit-Stop Freeze TimeScale, Camera Punch & Zero-Alloc Popup Pool';

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
  MakeBtn(BtnRow1, '+ Spawn Training Dummy', @BtnSpawnDummyClick, 178);
  MakeBtn(BtnRow1, 'Cue: Slash (85)', @BtnLightSlashClick, 138);
  MakeBtn(BtnRow1, 'Cue: CRIT! (420)', @BtnCritStrikeClick, 144);
  MakeBtn(BtnRow1, 'Cue: +Heal (120)', @BtnHealPulseClick, 142);
  MakeBtn(BtnRow1, 'Cue: Parry Block', @BtnShieldBlockClick, 142);
  MakeBtn(BtnRow1, 'Step Unscaled (+0.05s)', @BtnStepRealTimeClick, 172);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Burst 20x Pool Stress', @BtnBurstStressClick, 168);
  MakeBtn(BtnRow2, 'Clear Popups', @BtnClearClick, 130);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 182);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 385;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintArena := TPaintBox.Create(Self);
  PaintArena.Parent := BodyPanel;
  PaintArena.Align := alClient;
  PaintArena.BorderSpacing.Around := 6;
  PaintArena.OnPaint := @PaintArenaPaint;
end;

procedure TGameplayCueForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

function TGameplayCueForm.EnsureDirector: TCastleGameplayCueDirector;
var
  Dummy: TCastleTransform;
begin
  Result := TGameplayCueHelper.FindFirstDirector(FDesignRoot);
  if Result = nil then
    TGameplayCueHelper.SpawnCombatTrainingDummyCueDemo(FDesignRoot, FDesignOwner, Dummy, Result);
end;

procedure TGameplayCueForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TGameplayCueStudioSummary;
  D: TCastleGameplayCueDirector;
  HitStopMs: Single;
begin
  Warnings := TStringList.Create;
  try
    Sum := TGameplayCueHelper.CollectSummary(FDesignRoot, Warnings);
    D := TGameplayCueHelper.FindFirstDirector(FDesignRoot);
    if D <> nil then
      HitStopMs := D.HitStopRemainingSec * 1000.0
    else
      HitStopMs := 0.0;
    LabelTelemetry.Caption := Format(
      'Active Popups: %d / %d pool | Total Dispatched: %d | World TimeScale: %.2fx (Hit-Stop Remaining: %.0f ms)',
      [Sum.ActivePopups, Sum.PoolCapacity, Sum.TotalTriggered, Sum.EffectiveTimeScale, HitStopMs]);
    MemoReport.Lines.Text := TGameplayCueHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintArena.Invalidate;
end;

procedure TGameplayCueForm.BtnSpawnDummyClick(Sender: TObject);
var
  Dummy: TCastleTransform;
  D: TCastleGameplayCueDirector;
begin
  if TGameplayCueHelper.SpawnCombatTrainingDummyCueDemo(FDesignRoot, FDesignOwner, Dummy, D) then
    NotifyChange('Spawn Gameplay Cue Training Dummy');
end;

procedure TGameplayCueForm.BtnLightSlashClick(Sender: TObject);
var
  D: TCastleGameplayCueDirector;
begin
  D := EnsureDirector;
  if D = nil then Exit;
  D.TriggerGameplayCue('GameplayCue.Damage.MeleeSlash', Vector3(0.0, 1.55, 0.0), 85.0);
  NotifyChange('Trigger GameplayCue.Damage.MeleeSlash');
end;

procedure TGameplayCueForm.BtnCritStrikeClick(Sender: TObject);
var
  D: TCastleGameplayCueDirector;
begin
  D := EnsureDirector;
  if D = nil then Exit;
  D.TriggerGameplayCue('GameplayCue.Damage.Critical', Vector3(0.0, 1.75, 0.0), 420.0, True);
  NotifyChange('Trigger GameplayCue.Damage.Critical');
end;

procedure TGameplayCueForm.BtnHealPulseClick(Sender: TObject);
var
  D: TCastleGameplayCueDirector;
begin
  D := EnsureDirector;
  if D = nil then Exit;
  D.TriggerGameplayCue('GameplayCue.Status.Heal', Vector3(0.0, 1.40, 0.0), 120.0);
  NotifyChange('Trigger GameplayCue.Status.Heal');
end;

procedure TGameplayCueForm.BtnShieldBlockClick(Sender: TObject);
var
  D: TCastleGameplayCueDirector;
begin
  D := EnsureDirector;
  if D = nil then Exit;
  D.TriggerGameplayCue('GameplayCue.Combat.ShieldParry', Vector3(0.0, 1.50, 0.0), 0.0);
  NotifyChange('Trigger GameplayCue.Combat.ShieldParry');
end;

procedure TGameplayCueForm.BtnStepRealTimeClick(Sender: TObject);
var
  D: TCastleGameplayCueDirector;
begin
  D := TGameplayCueHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;
  D.StepDirector(0.05);
  NotifyChange('Step Gameplay Cue Director (+0.05s)');
end;

procedure TGameplayCueForm.BtnBurstStressClick(Sender: TObject);
var
  D: TCastleGameplayCueDirector;
  I: Integer;
begin
  D := EnsureDirector;
  if D = nil then Exit;
  for I := 1 to 20 do
  begin
    if (I mod 5) = 0 then
      D.TriggerGameplayCue('GameplayCue.Damage.Critical', Vector3(0, 1.65, 0), 250 + I * 10, True)
    else
      D.TriggerGameplayCue('GameplayCue.Damage.RapidHit', Vector3(0, 1.45, 0), 40 + I * 3);
    D.StepDirector(0.015);
  end;
  NotifyChange('Burst 20x Gameplay Cue Pool Stress');
end;

procedure TGameplayCueForm.BtnClearClick(Sender: TObject);
var
  D: TCastleGameplayCueDirector;
begin
  D := TGameplayCueHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;
  D.ClearAllPopups;
  NotifyChange('Clear Gameplay Cue Popups');
end;

procedure TGameplayCueForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'gameplay_cue_combat_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TGameplayCueHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TGameplayCueForm.PaintArenaPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, GroundY, CenterX, I, PX, PY, BarW: Integer;
  D: TCastleGameplayCueDirector;
  Slot: TGameplayCuePopupSlot;
begin
  Cv := PaintArena.Canvas;
  W := Max(200, PaintArena.Width);
  H := Max(200, PaintArena.Height);
  GroundY := H - 56;
  CenterX := W div 2;

  Cv.Brush.Color := RGBToColor(18, 20, 28);
  Cv.FillRect(0, 0, W, H);

  { Ground baseline & training dummy silhouette }
  Cv.Pen.Color := RGBToColor(68, 76, 94);
  Cv.Line(20, GroundY, W - 20, GroundY);
  Cv.Brush.Color := RGBToColor(148, 86, 62);
  Cv.Rectangle(CenterX - 26, GroundY - 120, CenterX + 26, GroundY);

  D := TGameplayCueHelper.FindFirstDirector(FDesignRoot);
  if D <> nil then
  begin
    { Hit-Stop TimeScale bar }
    Cv.Brush.Color := RGBToColor(32, 38, 50);
    Cv.Rectangle(20, 16, 260, 38);
    BarW := Round(236 * D.EffectiveWorldTimeScale);
    if D.HitStopRemainingSec > 0.0 then
      Cv.Brush.Color := RGBToColor(245, 92, 66)
    else
      Cv.Brush.Color := RGBToColor(64, 198, 118);
    Cv.Rectangle(22, 18, 22 + BarW, 36);

    { Active floating combat popups }
    Cv.Brush.Style := bsClear;
    for I := 0 to D.PoolCapacity - 1 do
    begin
      Slot := D.GetPopupSlot(I);
      if not Slot.Active then Continue;
      PX := EnsureRange(CenterX + Round(Slot.WorldPos.X * 68.0), 24, W - 90);
      PY := EnsureRange(GroundY - Round(Slot.WorldPos.Y * 68.0), 46, GroundY - 12);
      Cv.Font.Color := RGBToColor(
        EnsureRange(Round(Slot.ColorRGB.X * 255), 40, 255),
        EnsureRange(Round(Slot.ColorRGB.Y * 255), 40, 255),
        EnsureRange(Round(Slot.ColorRGB.Z * 255), 40, 255));
      if Slot.Kind = gckCriticalStrike then
        Cv.Font.Style := [fsBold]
      else
        Cv.Font.Style := [];
      Cv.TextOut(PX, PY, Slot.DisplayText);
    end;
    Cv.Font.Style := [];
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(272, 19, 'Hit-Stop World TimeScale & Parabolic Combat Popups');
end;

end.
