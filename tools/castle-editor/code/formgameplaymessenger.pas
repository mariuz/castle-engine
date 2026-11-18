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

{ Visual Studio dialog for Gameplay Message Bus & Squad Bark Router (Phase 373). }
unit FormGameplayMessenger;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleGameplayMessenger, ToolGameplayMessenger;

type
  TGameplayMessengerModifiedCallback = procedure(const UndoComment: String) of object;
  TGameplayMessengerRefreshCallback = procedure of object;

  TGameplayMessengerForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TGameplayMessengerModifiedCallback;
    FOnRefresh: TGameplayMessengerRefreshCallback;
    FPaintComms: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveMessenger: TCastleGameplayMessenger;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnPubDamageClick(Sender: TObject);
    procedure BtnAmbientBarkClick(Sender: TObject);
    procedure BtnEmergencyPreemptClick(Sender: TObject);
    procedure BtnStepClockClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintCommsMonitor(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TGameplayMessengerModifiedCallback;
      const AOnRefresh: TGameplayMessengerRefreshCallback);
  end;

implementation

constructor TGameplayMessengerForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TGameplayMessengerModifiedCallback;
  const AOnRefresh: TGameplayMessengerRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Gameplay Message Bus & Squad AI Radio Bark Router Studio (Phase 373)';
  Width := 1000;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TGameplayMessengerForm.BuildUi;
var
  Lbl: TLabel;
  Row1, BodyPanel: TPanel;

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
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Align := alTop;
  Lbl.BorderSpacing.Around := 8;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'UE 6.0+ UGameplayMessageSubsystem — Dot-Boundary GameplayTag Pub/Sub, Anti-Spam Bark Cooldowns & Priority Preemption';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 42;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Squad Comms Bus', @BtnSpawnClick);
  MakeBtn(Row1, 'Publish Combat.Damage.Crit', @BtnPubDamageClick);
  MakeBtn(Row1, 'Guard Ambient Bark', @BtnAmbientBarkClick);
  MakeBtn(Row1, 'EMERGENCY Bark (Preempt!)', @BtnEmergencyPreemptClick);
  MakeBtn(Row1, 'Step Timers (+2.5s)', @BtnStepClockClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintComms := TPaintBox.Create(Self);
  FPaintComms.Parent := BodyPanel;
  FPaintComms.Align := alLeft;
  FPaintComms.Width := 490;
  FPaintComms.OnPaint := @PaintCommsMonitor;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TGameplayMessengerForm.ActiveMessenger: TCastleGameplayMessenger;
begin
  Result := TGameplayMessengerHelper.FindMessengerInHierarchy(FDesignRoot);
end;

procedure TGameplayMessengerForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TGameplayMessengerForm.RefreshView;
begin
  FMemoReport.Lines.Text := TGameplayMessengerHelper.GenerateMessengerReport(ActiveMessenger);
  FPaintComms.Invalidate;
end;

procedure TGameplayMessengerForm.BtnSpawnClick(Sender: TObject);
var
  M: TCastleGameplayMessenger;
begin
  if TGameplayMessengerHelper.SpawnSquadCommsBusDemo(FDesignRoot, FDesignOwner, M) then
    NotifyChange('Spawn Squad Comms Gameplay Message Bus');
end;

procedure TGameplayMessengerForm.BtnPubDamageClick(Sender: TObject);
var
  M: TCastleGameplayMessenger;
begin
  M := ActiveMessenger;
  if M = nil then Exit;
  M.BroadcastGameplayMessage('Combat.Damage.Critical', 'HeroPaladin', 420.0, 'SunfireBlade Crit!');
  NotifyChange('Broadcast Combat.Damage.Critical Message');
end;

procedure TGameplayMessengerForm.BtnAmbientBarkClick(Sender: TObject);
var
  M: TCastleGameplayMessenger;
  DropReason: String;
begin
  M := ActiveMessenger;
  if M = nil then Exit;
  M.RequestSquadBark('Bark.Ambient.SectorClear', 'Sentry_04',
    'Sector quiet... nothing on perimeter.', bpAmbientChatter, 3.5, 6.0, DropReason);
  NotifyChange('Request Guard Ambient Radio Bark');
end;

procedure TGameplayMessengerForm.BtnEmergencyPreemptClick(Sender: TObject);
var
  M: TCastleGameplayMessenger;
  DropReason: String;
begin
  M := ActiveMessenger;
  if M = nil then Exit;
  M.RequestSquadBark('Bark.Combat.SniperContact', 'Captain_Vance',
    'CONTACT NORTH RIDGE! TAKE COVER!', bpCriticalEmergency, 3.0, 8.0, DropReason);
  NotifyChange('Request Emergency Priority Preemption Bark');
end;

procedure TGameplayMessengerForm.BtnStepClockClick(Sender: TObject);
var
  M: TCastleGameplayMessenger;
begin
  M := ActiveMessenger;
  if M = nil then Exit;
  M.StepMessenger(2.5);
  NotifyChange('Step Bark & Cooldown Timers (+2.5s)');
end;

procedure TGameplayMessengerForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TGameplayMessengerHelper.GenerateMessengerReport(ActiveMessenger);
end;

procedure TGameplayMessengerForm.PaintCommsMonitor(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, Y, StartIdx: Integer;
  M: TCastleGameplayMessenger;
begin
  Cv := FPaintComms.Canvas;
  W := FPaintComms.Width;
  H := FPaintComms.Height;
  Cv.Brush.Color := RGBToColor(14, 20, 26);
  Cv.FillRect(0, 0, W, H);

  M := ActiveMessenger;
  if M = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Squad Comms Bus" to inspect Live Pub/Sub & Radio Barks.');
    Exit;
  end;

  if M.HasActiveBark then
    Cv.Brush.Color := RGBToColor(185, 65, 45)
  else
    Cv.Brush.Color := RGBToColor(32, 46, 58);
  Cv.Rectangle(14, 14, W - 14, 72);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  if M.HasActiveBark then
    Cv.TextOut(24, 34, Format('[%s] %s: "%s" (%.1fs)', [
      BarkPriorityToString(M.ActiveBark.Priority),
      M.ActiveBark.SpeakerName,
      M.ActiveBark.SubtitleText,
      M.ActiveBark.RemainingDurationSec]))
  else
    Cv.TextOut(24, 34, '[RADIO IDLE] Squad voice channel clear.');

  Y := 92;
  Cv.Font.Color := RGBToColor(135, 225, 175);
  StartIdx := Max(0, M.HistoryLineCount - 14);
  for I := StartIdx to M.HistoryLineCount - 1 do
  begin
    Cv.TextOut(16, Y, Copy(M.GetHistoryLine(I), 1, 68));
    Inc(Y, 22);
  end;
end;

end.
