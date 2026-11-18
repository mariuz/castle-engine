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

{ Interactive Chaos Mover 2.0 Rollback-Ready Kinematic Character Modes
  (Walk, Slide, Wall-Run, Swim & Grapple) Studio dialog (Phase 351). }
unit FormMoverStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleMover2, ToolMoverStudio;

type
  TMoverModifyCallback = procedure(const AUndoComment: String) of object;
  TMoverRefreshCallback = procedure of object;

  TMoverStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMoverModifyCallback;
    FOnRefreshViewport: TMoverRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintHistory: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    function EnsureMover: TCastleMoverBehavior;
    procedure BtnSpawnArenaClick(Sender: TObject);
    procedure BtnSprintJumpClick(Sender: TObject);
    procedure BtnCrouchSlideClick(Sender: TObject);
    procedure BtnWallRunClick(Sender: TObject);
    procedure BtnGrappleZipClick(Sender: TObject);
    procedure BtnRollbackJumpClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintHistoryPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMoverModifyCallback;
      const AOnRefreshViewport: TMoverRefreshCallback);
  end;

implementation

constructor TMoverStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMoverModifyCallback;
  const AOnRefreshViewport: TMoverRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Chaos Mover 2.0 Rollback-Ready Character Modes Studio (UE 6.0+ UMoverComponent Parity)';
  Width := 1060;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TMoverStudioForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 160): TButton;
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
  LabelHeader.Caption := 'Chaos Mover 2.0 — Pure Functional SyncState Locomotion (Walk, Slide, WallRun, Swim, Grapple) & 128-Tick Rollback Resimulation';

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
  MakeBtn(BtnRow1, '+ Spawn Mover 2.0 Arena', @BtnSpawnArenaClick, 184);
  MakeBtn(BtnRow1, 'Sprint + Jump (18f)', @BtnSprintJumpClick, 158);
  MakeBtn(BtnRow1, 'Crouch Slide (18f)', @BtnCrouchSlideClick, 154);
  MakeBtn(BtnRow1, 'Wall-Run Glide (20f)', @BtnWallRunClick, 162);
  MakeBtn(BtnRow1, 'Grapple Zip Tower (24f)', @BtnGrappleZipClick, 178);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Rollback -10f & Inject Jump!', @BtnRollbackJumpClick, 206);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 184);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 415;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintHistory := TPaintBox.Create(Self);
  PaintHistory.Parent := BodyPanel;
  PaintHistory.Align := alClient;
  PaintHistory.BorderSpacing.Around := 6;
  PaintHistory.OnPaint := @PaintHistoryPaint;
end;

procedure TMoverStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

function TMoverStudioForm.EnsureMover: TCastleMoverBehavior;
var
  Actor: TCastleTransform;
begin
  Result := TMoverStudioHelper.FindFirstMover(FDesignRoot);
  if Result = nil then
    TMoverStudioHelper.SpawnMover2ArenaDemo(FDesignRoot, FDesignOwner, Actor, Result);
end;

procedure TMoverStudioForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TMoverStudioSummary;
begin
  Warnings := TStringList.Create;
  try
    Sum := TMoverStudioHelper.CollectSummary(FDesignRoot, Warnings);
    LabelTelemetry.Caption := Format(
      'Mode: %s | Tick: #%d | Speed: %.2f m/s | Rollback Resimulations: %d',
      [Sum.ActiveModeName, Sum.CurrentTick, Sum.SpeedMps, Sum.RollbackResims]);
    MemoReport.Lines.Text := TMoverStudioHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintHistory.Invalidate;
end;

procedure TMoverStudioForm.BtnSpawnArenaClick(Sender: TObject);
var
  Actor: TCastleTransform;
  M: TCastleMoverBehavior;
begin
  if TMoverStudioHelper.SpawnMover2ArenaDemo(FDesignRoot, FDesignOwner, Actor, M) then
    NotifyChange('Spawn Mover 2.0 Arena');
end;

procedure TMoverStudioForm.BtnSprintJumpClick(Sender: TObject);
var
  M: TCastleMoverBehavior;
  Cmd: TMoverInputCmd;
  I: Integer;
begin
  M := EnsureMover;
  if M = nil then Exit;
  for I := 1 to 18 do
  begin
    Cmd := TMoverInputCmd.WalkForward(Vector3(0, 0, -1));
    Cmd.JumpPressed := (I = 4);
    M.AdvanceTick(Cmd, 1.0 / 60.0);
  end;
  NotifyChange('Mover 2.0 Sprint + Jump');
end;

procedure TMoverStudioForm.BtnCrouchSlideClick(Sender: TObject);
var
  M: TCastleMoverBehavior;
  Cmd: TMoverInputCmd;
  I: Integer;
begin
  M := EnsureMover;
  if M = nil then Exit;
  for I := 1 to 18 do
  begin
    Cmd := TMoverInputCmd.WalkForward(Vector3(0, 0, -1));
    Cmd.CrouchSlideHeld := True;
    M.AdvanceTick(Cmd, 1.0 / 60.0);
  end;
  NotifyChange('Mover 2.0 Crouch Slide');
end;

procedure TMoverStudioForm.BtnWallRunClick(Sender: TObject);
var
  M: TCastleMoverBehavior;
  Cmd: TMoverInputCmd;
  I: Integer;
begin
  M := EnsureMover;
  if M = nil then Exit;
  Cmd := TMoverInputCmd.WalkForward(Vector3(0, 0, -1));
  Cmd.JumpPressed := True;
  M.AdvanceTick(Cmd, 1.0 / 60.0);
  for I := 1 to 20 do
  begin
    Cmd := TMoverInputCmd.WalkForward(Vector3(0, 0, -1));
    Cmd.WallRunHeld := True;
    Cmd.WallNormalXZ := Vector3(1, 0, 0);
    M.AdvanceTick(Cmd, 1.0 / 60.0);
  end;
  NotifyChange('Mover 2.0 Wall-Run');
end;

procedure TMoverStudioForm.BtnGrappleZipClick(Sender: TObject);
var
  M: TCastleMoverBehavior;
  Cmd: TMoverInputCmd;
  I: Integer;
begin
  M := EnsureMover;
  if M = nil then Exit;
  for I := 1 to 24 do
  begin
    Cmd := Default(TMoverInputCmd);
    if I = 1 then
    begin
      Cmd.GrappleRequested := True;
      Cmd.GrappleTargetWorld := Vector3(0.0, 8.5, -14.0);
    end;
    M.AdvanceTick(Cmd, 1.0 / 60.0);
  end;
  NotifyChange('Mover 2.0 Grapple-Hook Zip');
end;

procedure TMoverStudioForm.BtnRollbackJumpClick(Sender: TObject);
var
  M: TCastleMoverBehavior;
  TargetTick: Integer;
  JumpCmd: TMoverInputCmd;
begin
  M := EnsureMover;
  if M = nil then Exit;
  TargetTick := Max(1, M.CurrentState.TickIndex - 10);
  JumpCmd := TMoverInputCmd.WalkForward(Vector3(0, 0, -1));
  JumpCmd.JumpPressed := True;
  if M.RewindAndResimulateFromTick(TargetTick, JumpCmd, 1.0 / 60.0) then
    NotifyChange('Mover 2.0 Rollback Rewind & Resimulate');
end;

procedure TMoverStudioForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'mover2_rollback_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TMoverStudioHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TMoverStudioForm.PaintHistoryPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, GroundY, StartT, EndT, T, PX, PY, PrevX, PrevY: Integer;
  M: TCastleMoverBehavior;
  Entry: TMoverHistoryEntry;
  HasPrev: Boolean;
begin
  Cv := PaintHistory.Canvas;
  W := Max(200, PaintHistory.Width);
  H := Max(200, PaintHistory.Height);
  GroundY := H - 58;

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);
  Cv.Pen.Color := RGBToColor(64, 78, 98);
  Cv.Line(20, GroundY, W - 20, GroundY);

  M := TMoverStudioHelper.FindFirstMover(FDesignRoot);
  if M <> nil then
  begin
    EndT := M.CurrentState.TickIndex;
    StartT := Max(1, EndT - 90);
    HasPrev := False;
    PrevX := 30;
    PrevY := GroundY;

    for T := StartT to EndT do
      if M.GetHistoryEntryByTick(T, Entry) then
      begin
        PX := EnsureRange(36 + Round((-Entry.AfterState.Position.Z) * 26.0), 24, W - 24);
        PY := EnsureRange(GroundY - Round(Entry.AfterState.Position.Y * 32.0), 42, GroundY + 36);
        case Entry.AfterState.Mode of
          mlmGroundWalk:  Cv.Brush.Color := RGBToColor(68, 210, 120);
          mlmAirFalling:  Cv.Brush.Color := RGBToColor(246, 186, 62);
          mlmCrouchSlide: Cv.Brush.Color := RGBToColor(86, 176, 250);
          mlmWallRun:     Cv.Brush.Color := RGBToColor(210, 102, 248);
          mlmBuoyantSwim: Cv.Brush.Color := RGBToColor(46, 212, 218);
          mlmGrappleZip:  Cv.Brush.Color := RGBToColor(250, 96, 78);
        end;
        Cv.Pen.Color := Cv.Brush.Color;
        if HasPrev then
          Cv.Line(PrevX, PrevY, PX, PY);
        Cv.Ellipse(PX - 4, PY - 4, PX + 4, PY + 4);
        PrevX := PX;
        PrevY := PY;
        HasPrev := True;
      end;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(16, 10, 'ZY Rollback SyncState Trajectory (Color-Coded by Locomotion Mode)');
  Cv.Font.Style := [];
end;

end.
