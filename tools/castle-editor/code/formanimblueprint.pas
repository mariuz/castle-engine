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

{ Unreal Engine 5.5-style Animation Blueprint Editor dialog featuring a 2D
  AnimGraph pose pipeline canvas, frame-accurate AnimNotify & AnimNotifyState
  timeline track view, locomotion/aim/jump parameter controls, and live pose
  telemetry (Phase 383 — 103 UE Studios / 26 MCP). }
unit FormAnimBlueprint;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleAnimBlueprint, ToolAnimBlueprint;

type
  TAnimBlueprintModifiedCallback = procedure(const UndoComment: String) of object;
  TAnimBlueprintRefreshCallback = procedure of object;

  TAnimBlueprintForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TAnimBlueprintModifiedCallback;
    FOnRefresh: TAnimBlueprintRefreshCallback;

    FActiveBp: TCastleAnimBlueprint;
    FSelectedNodeId: String;
    FDraggingNode: Boolean;
    FDragOffsetX: Single;
    FDragOffsetY: Single;

    FLblStatus: TLabel;
    FPaintAnimGraph: TPaintBox;
    FPaintNotifyTrack: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);
    function HeaderColor(const AKind: TAnimGraphNodeKind): TColor;
    procedure DrawPoseWire(const C: TCanvas; const P0, P1: TPoint; const ACol: TColor);

    procedure PaintAnimGraphCanvas(Sender: TObject);
    procedure PaintNotifyTrackCanvas(Sender: TObject);
    procedure GraphMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure GraphMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GraphMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure BtnSpawnLocoAimClick(Sender: TObject);
    procedure BtnSpawnCombatSlotClick(Sender: TObject);
    procedure BtnIdleModeClick(Sender: TObject);
    procedure BtnSprintAimModeClick(Sender: TObject);
    procedure BtnToggleJumpClick(Sender: TObject);
    procedure BtnStepPoseClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TAnimBlueprintModifiedCallback;
      const AOnRefresh: TAnimBlueprintRefreshCallback);
  end;

implementation

const
  AnimNodeW = 166;
  AnimNodeH = 66;

constructor TAnimBlueprintForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TAnimBlueprintModifiedCallback;
  const AOnRefresh: TAnimBlueprintRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Animation Blueprint Editor — AnimGraph Pose Pipeline & AnimNotify Tracks (103 UE Studios / 26 MCP)';
  Position := poScreenCenter;
  Width := 1120;
  Height := 700;

  BuildUi;
  FActiveBp := TAnimBlueprintHelper.FindFirstAnimBlueprint(FDesignRoot);
  RefreshFromScene;
end;

procedure TAnimBlueprintForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlNotifyBand, PnlBottom: TPanel;
  BtnLoco, BtnSlot, BtnIdle, BtnSprint, BtnJump, BtnStep, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 34;
  PnlTop.BevelOuter := bvNone;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 10;
  FLblStatus.Top := 9;
  FLblStatus.Caption := 'Animation Blueprint Editor Ready.';

  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;

  BtnLoco := TButton.Create(Self);
  BtnLoco.Parent := PnlToolbar;
  BtnLoco.SetBounds(8, 6, 166, 30);
  BtnLoco.Caption := '+ Spawn Loco+Aim+IK BP';
  BtnLoco.OnClick := @BtnSpawnLocoAimClick;

  BtnSlot := TButton.Create(Self);
  BtnSlot.Parent := PnlToolbar;
  BtnSlot.SetBounds(178, 6, 152, 30);
  BtnSlot.Caption := '+ Combat Slot BP';
  BtnSlot.OnClick := @BtnSpawnCombatSlotClick;

  BtnIdle := TButton.Create(Self);
  BtnIdle.Parent := PnlToolbar;
  BtnIdle.SetBounds(334, 6, 110, 30);
  BtnIdle.Caption := 'Idle (0 m/s)';
  BtnIdle.OnClick := @BtnIdleModeClick;

  BtnSprint := TButton.Create(Self);
  BtnSprint.Parent := PnlToolbar;
  BtnSprint.SetBounds(448, 6, 148, 30);
  BtnSprint.Caption := 'Sprint + Rifle Aim';
  BtnSprint.OnClick := @BtnSprintAimModeClick;

  BtnJump := TButton.Create(Self);
  BtnJump.Parent := PnlToolbar;
  BtnJump.SetBounds(600, 6, 130, 30);
  BtnJump.Caption := 'Toggle Jump Air';
  BtnJump.OnClick := @BtnToggleJumpClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlToolbar;
  BtnStep.SetBounds(734, 6, 122, 30);
  BtnStep.Caption := 'Step +0.15s';
  BtnStep.OnClick := @BtnStepPoseClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlToolbar;
  BtnCopy.SetBounds(860, 6, 126, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyMarkdownClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 165;
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

  PnlNotifyBand := TPanel.Create(Self);
  PnlNotifyBand.Parent := Self;
  PnlNotifyBand.Align := alBottom;
  PnlNotifyBand.Height := 115;
  PnlNotifyBand.BevelOuter := bvLowered;

  FPaintNotifyTrack := TPaintBox.Create(Self);
  FPaintNotifyTrack.Parent := PnlNotifyBand;
  FPaintNotifyTrack.Align := alClient;
  FPaintNotifyTrack.OnPaint := @PaintNotifyTrackCanvas;

  FPaintAnimGraph := TPaintBox.Create(Self);
  FPaintAnimGraph.Parent := Self;
  FPaintAnimGraph.Align := alClient;
  FPaintAnimGraph.OnPaint := @PaintAnimGraphCanvas;
  FPaintAnimGraph.OnMouseDown := @GraphMouseDown;
  FPaintAnimGraph.OnMouseMove := @GraphMouseMove;
  FPaintAnimGraph.OnMouseUp := @GraphMouseUp;
end;

procedure TAnimBlueprintForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TAnimBlueprintForm.RefreshFromScene;
begin
  if (FActiveBp = nil) and (FDesignRoot <> nil) then
    FActiveBp := TAnimBlueprintHelper.FindFirstAnimBlueprint(FDesignRoot);

  if FActiveBp <> nil then
    FLblStatus.Caption := Format('%s  %s  |  Playhead=%.2fs  TriggeredNotifies=%d',
      [FActiveBp.Name, FActiveBp.AnimBlueprintSummaryBadge,
       FActiveBp.PlayheadTimeSec, FActiveBp.TriggeredNotifies.Count])
  else
    FLblStatus.Caption := 'No TCastleAnimBlueprint in design yet — click "+ Spawn Loco+Aim+IK BP".';

  FMemoReport.Text := TAnimBlueprintHelper.GenerateMarkdownReport(FDesignRoot, FActiveBp);
  FPaintAnimGraph.Invalidate;
  FPaintNotifyTrack.Invalidate;
end;

function TAnimBlueprintForm.HeaderColor(const AKind: TAnimGraphNodeKind): TColor;
begin
  case AKind of
    ankStateMachine:        Result := RGBToColor(116, 48, 152);
    ankSequencePlayer,
    ankBlendSpacePlayer:    Result := RGBToColor(36, 126, 68);
    ankSaveCachedPose,
    ankUseCachedPose:       Result := RGBToColor(28, 118, 126);
    ankLayeredBlendPerBone,
    ankSlotOverride:        Result := RGBToColor(38, 88, 162);
    ankTwoBoneIk:           Result := RGBToColor(168, 118, 28);
  else
    Result := RGBToColor(158, 38, 44);
  end;
end;

procedure TAnimBlueprintForm.DrawPoseWire(const C: TCanvas;
  const P0, P1: TPoint; const ACol: TColor);
var
  Pts: array[0..16] of TPoint;
  TangentDX, T, OneMinusT, C1X, C2X: Single;
  S: Integer;
begin
  TangentDX := Max(42.0, Abs(P1.X - P0.X) * 0.45);
  C1X := P0.X + TangentDX;
  C2X := P1.X - TangentDX;
  for S := 0 to 16 do
  begin
    T := S / 16.0;
    OneMinusT := 1.0 - T;
    Pts[S].X := Round(
      OneMinusT * OneMinusT * OneMinusT * P0.X +
      3 * OneMinusT * OneMinusT * T * C1X +
      3 * OneMinusT * T * T * C2X +
      T * T * T * P1.X);
    Pts[S].Y := Round(
      OneMinusT * OneMinusT * OneMinusT * P0.Y +
      3 * OneMinusT * OneMinusT * T * P0.Y +
      3 * OneMinusT * T * T * P1.Y +
      T * T * T * P1.Y);
  end;
  C.Pen.Color := ACol;
  C.Pen.Width := 3;
  C.Polyline(Pts);
end;

procedure TAnimBlueprintForm.PaintAnimGraphCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, GX, GY, I, SrcIdx: Integer;
  N, SrcN: TAnimGraphNode;
  BoxR: TRect;
begin
  C := FPaintAnimGraph.Canvas;
  W := FPaintAnimGraph.Width;
  H := FPaintAnimGraph.Height;

  C.Brush.Color := RGBToColor(28, 30, 35);
  C.FillRect(0, 0, W, H);

  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(40, 44, 52);
  GX := 0;
  while GX < W do begin C.Line(GX, 0, GX, H); Inc(GX, 20); end;
  GY := 0;
  while GY < H do begin C.Line(0, GY, W, GY); Inc(GY, 20); end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(86, 98, 114);
  C.TextOut(W - 180, H - 24, 'UE 5.5 ANIMGRAPH');

  if FActiveBp = nil then Exit;

  { Pose wires }
  for I := 0 to High(FActiveBp.Nodes) do
  begin
    N := FActiveBp.Nodes[I];
    if N.InputPoseNode0 <> '' then
    begin
      SrcIdx := FActiveBp.FindNodeIndex(N.InputPoseNode0);
      if SrcIdx >= 0 then
      begin
        SrcN := FActiveBp.Nodes[SrcIdx];
        DrawPoseWire(C,
          Point(Round(SrcN.PosX) + AnimNodeW, Round(SrcN.PosY) + 40),
          Point(Round(N.PosX), Round(N.PosY) + 36),
          RGBToColor(245, 245, 245));
      end;
    end;
    if N.InputPoseNode1 <> '' then
    begin
      SrcIdx := FActiveBp.FindNodeIndex(N.InputPoseNode1);
      if SrcIdx >= 0 then
      begin
        SrcN := FActiveBp.Nodes[SrcIdx];
        DrawPoseWire(C,
          Point(Round(SrcN.PosX) + AnimNodeW, Round(SrcN.PosY) + 40),
          Point(Round(N.PosX), Round(N.PosY) + 52),
          RGBToColor(255, 182, 58));
      end;
    end;
  end;

  { Pose nodes }
  for I := 0 to High(FActiveBp.Nodes) do
  begin
    N := FActiveBp.Nodes[I];
    BoxR := Rect(Round(N.PosX), Round(N.PosY),
      Round(N.PosX) + AnimNodeW, Round(N.PosY) + AnimNodeH);

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(44, 48, 56);
    if SameText(FSelectedNodeId, N.NodeId) then
    begin
      C.Pen.Color := RGBToColor(255, 204, 52);
      C.Pen.Width := 2;
    end else
    begin
      C.Pen.Color := RGBToColor(18, 20, 24);
      C.Pen.Width := 1;
    end;
    C.RoundRect(BoxR, 8, 8);

    C.Brush.Color := HeaderColor(N.Kind);
    C.FillRect(BoxR.Left + 2, BoxR.Top + 2, BoxR.Right - 2, BoxR.Top + 24);

    C.Brush.Style := bsClear;
    C.Font.Color := clWhite;
    C.TextOut(BoxR.Left + 8, BoxR.Top + 5, Copy(TCastleAnimBlueprint.NodeKindTitle(N.Kind), 1, 21));

    C.Font.Color := RGBToColor(208, 216, 228);
    C.TextOut(BoxR.Left + 8, BoxR.Top + 30, N.NodeId);
    if N.Kind in [ankSaveCachedPose, ankUseCachedPose] then
      C.TextOut(BoxR.Left + 8, BoxR.Top + 46, '[' + N.CachePoseName + ']');
  end;
end;

procedure TAnimBlueprintForm.PaintNotifyTrackCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, TrackLeft, TrackRight, TrackSpan, X0, X1, YRow, PlayX, I: Integer;
  Ev: TAnimNotifyEvent;
begin
  C := FPaintNotifyTrack.Canvas;
  W := FPaintNotifyTrack.Width;
  H := FPaintNotifyTrack.Height;

  C.Brush.Color := RGBToColor(22, 24, 29);
  C.FillRect(0, 0, W, H);

  TrackLeft := 150;
  TrackRight := Max(TrackLeft + 100, W - 24);
  TrackSpan := TrackRight - TrackLeft;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(186, 198, 214);
  C.TextOut(10, 8, 'AnimNotify Timeline (0.00s .. 1.00s)');

  C.Pen.Color := RGBToColor(64, 72, 84);
  C.Pen.Width := 1;
  C.Rectangle(TrackLeft, 28, TrackRight, H - 10);

  if FActiveBp = nil then Exit;

  for I := 0 to High(FActiveBp.Notifies) do
  begin
    Ev := FActiveBp.Notifies[I];
    YRow := 36 + (I mod 3) * 22;
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(200, 210, 224);
    C.TextOut(10, YRow, Copy(Ev.NotifyName, 1, 18));

    X0 := TrackLeft + Round((Ev.TriggerTimeSec / TCastleAnimBlueprint.DefaultClipDurationSec) * TrackSpan);
    if Ev.Kind = ankInstantNotify then
    begin
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(255, 196, 48);
      C.Pen.Color := clWhite;
      C.Ellipse(X0 - 6, YRow + 2, X0 + 6, YRow + 14);
    end else
    begin
      X1 := TrackLeft + Round((Ev.EndTimeSec / TCastleAnimBlueprint.DefaultClipDurationSec) * TrackSpan);
      C.Brush.Style := bsSolid;
      if Ev.ActiveWindowNow then
        C.Brush.Color := RGBToColor(64, 216, 128)
      else
        C.Brush.Color := RGBToColor(52, 124, 196);
      C.Pen.Color := clWhite;
      C.Rectangle(X0, YRow + 2, Max(X0 + 8, X1), YRow + 16);
    end;
  end;

  { Red playhead bar }
  PlayX := TrackLeft + Round((FActiveBp.PlayheadTimeSec / TCastleAnimBlueprint.DefaultClipDurationSec) * TrackSpan);
  C.Pen.Color := RGBToColor(245, 68, 68);
  C.Pen.Width := 2;
  C.Line(PlayX, 24, PlayX, H - 6);
end;

procedure TAnimBlueprintForm.GraphMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  N: TAnimGraphNode;
begin
  if (FActiveBp = nil) or (Button <> mbLeft) then Exit;
  for I := High(FActiveBp.Nodes) downto 0 do
  begin
    N := FActiveBp.Nodes[I];
    if (X >= Round(N.PosX)) and (X <= Round(N.PosX) + AnimNodeW) and
       (Y >= Round(N.PosY)) and (Y <= Round(N.PosY) + AnimNodeH) then
    begin
      FSelectedNodeId := N.NodeId;
      FDraggingNode := True;
      FDragOffsetX := X - N.PosX;
      FDragOffsetY := Y - N.PosY;
      FPaintAnimGraph.Invalidate;
      Exit;
    end;
  end;
  FSelectedNodeId := '';
  FPaintAnimGraph.Invalidate;
end;

procedure TAnimBlueprintForm.GraphMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
begin
  if FDraggingNode and (FActiveBp <> nil) and (FSelectedNodeId <> '') then
  begin
    FActiveBp.SetNodePosition(FSelectedNodeId,
      Max(8.0, X - FDragOffsetX), Max(8.0, Y - FDragOffsetY));
    FPaintAnimGraph.Invalidate;
  end;
end;

procedure TAnimBlueprintForm.GraphMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingNode then
  begin
    FDraggingNode := False;
    NotifyChanged('Move AnimGraph Node');
  end;
end;

procedure TAnimBlueprintForm.BtnSpawnLocoAimClick(Sender: TObject);
begin
  FActiveBp := TAnimBlueprintHelper.SpawnAnimBlueprintPresetInDesign(
    FDesignRoot, FDesignOwner, abpLocomotionUpperBodyAimAndFootIk, Vector3(0, 0, 0));
  NotifyChanged('Spawn Locomotion + UpperBody Aim + Foot IK AnimBlueprint');
end;

procedure TAnimBlueprintForm.BtnSpawnCombatSlotClick(Sender: TObject);
begin
  FActiveBp := TAnimBlueprintHelper.SpawnAnimBlueprintPresetInDesign(
    FDesignRoot, FDesignOwner, abpCombatSlotMontageOverride, Vector3(2.5, 0, 0));
  NotifyChanged('Spawn Combat Slot Montage AnimBlueprint');
end;

procedure TAnimBlueprintForm.BtnIdleModeClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.IsInAir := False;
  FActiveBp.SpeedMps := 0.0;
  FActiveBp.UpperBodyAimWeight := 0.0;
  FActiveBp.StepAnimBlueprint(0.0);
  NotifyChanged('Set AnimBlueprint Idle');
end;

procedure TAnimBlueprintForm.BtnSprintAimModeClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.IsInAir := False;
  FActiveBp.SpeedMps := 6.0;
  FActiveBp.UpperBodyAimWeight := 1.0;
  FActiveBp.StepAnimBlueprint(0.0);
  NotifyChanged('Set AnimBlueprint Sprint + Rifle Aim');
end;

procedure TAnimBlueprintForm.BtnToggleJumpClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.IsInAir := not FActiveBp.IsInAir;
  FActiveBp.StepAnimBlueprint(0.0);
  NotifyChanged('Toggle AnimBlueprint Jump Air');
end;

procedure TAnimBlueprintForm.BtnStepPoseClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.StepAnimBlueprint(0.15);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshFromScene;
end;

procedure TAnimBlueprintForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Text;
end;

end.
