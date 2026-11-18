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

{ Visual Studio dialog for Multi-User Collaborative Presence Locks & 86-Studio Hub (Phase 366). }
unit FormCollabPresence;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, ToolCollabPresence, ToolStudioHub;

type
  TCollabPresenceModifiedCallback = procedure(const UndoComment: String) of object;
  TCollabPresenceRefreshCallback = procedure of object;

  TCollabPresenceForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TCollabPresenceModifiedCallback;
    FOnRefresh: TCollabPresenceRefreshCallback;
    FLastActionBanner: String;
    FPaintPresence: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnKeepClick(Sender: TObject);
    procedure BtnAliceGateClick(Sender: TObject);
    procedure BtnBobConflictHingeClick(Sender: TObject);
    procedure BtnBobSiblingSignClick(Sender: TObject);
    procedure BtnExpireStaleClick(Sender: TObject);
    procedure BtnCopyJsonClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintPresenceBoard(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TCollabPresenceModifiedCallback;
      const AOnRefresh: TCollabPresenceRefreshCallback);
  end;

implementation

constructor TCollabPresenceForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TCollabPresenceModifiedCallback;
  const AOnRefresh: TCollabPresenceRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FLastActionBanner := 'Ready — Multi-User Subtree Reservation Broker & 86-Studio Hub';
  Caption := 'Multi-User Collaborative Presence Locks & 86-Studio Hub Studio (Phase 366)';
  Width := 1020;
  Height := 650;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TCollabPresenceForm.BuildUi;
var
  Lbl: TLabel;
  Row1, Row2, BodyPanel: TPanel;

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
  Lbl.Caption := 'UE 6.0+ Multi-User Editing Parity — Ancestor/Descendant Subtree Locks, Lease Heartbeats, 86 Studios & 18 MCP Tools';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Collaborative Keep (Gate -> Hinge + Sign)', @BtnSpawnKeepClick);
  MakeBtn(Row1, 'Alice Locks "CastleGate" (30s)', @BtnAliceGateClick);
  MakeBtn(Row1, 'Copy Session JSON', @BtnCopyJsonClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Bob Tries Child "GateHinge" (Conflict Gate!)', @BtnBobConflictHingeClick);
  MakeBtn(Row2, 'Bob Locks Sibling "TavernSign" (Allowed)', @BtnBobSiblingSignClick);
  MakeBtn(Row2, 'Advance +35s & Expire Stale Leases', @BtnExpireStaleClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintPresence := TPaintBox.Create(Self);
  FPaintPresence.Parent := BodyPanel;
  FPaintPresence.Align := alLeft;
  FPaintPresence.Width := 490;
  FPaintPresence.OnPaint := @PaintPresenceBoard;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

procedure TCollabPresenceForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TCollabPresenceForm.RefreshView;
begin
  FMemoReport.Lines.Text :=
    '> Status: ' + FLastActionBanner + LineEnding + LineEnding +
    TCollabPresenceBroker.SharedBroker.GenerateCollabReport(FDesignRoot);
  FPaintPresence.Invalidate;
end;

procedure TCollabPresenceForm.BtnSpawnKeepClick(Sender: TObject);
begin
  if TCollabPresenceBroker.SpawnCollaborativeKeepDemo(FDesignRoot, FDesignOwner) then
  begin
    FLastActionBanner := 'Spawned CastleGate (-> GateHinge), TavernSign & WatchtowerBell.';
    NotifyChange('Spawn Collaborative Keep Demo Hierarchy');
  end;
end;

procedure TCollabPresenceForm.BtnAliceGateClick(Sender: TObject);
var
  Reason: String;
  B: TCollabPresenceBroker;
begin
  B := TCollabPresenceBroker.SharedBroker;
  B.UpdatePeerPresence('alice', 'Alice (Env Lead)', 'CastleGate', Vector3(-4, 3, 8));
  if B.AcquireSubtreeLock(FDesignRoot, 'alice', 'Alice (Env Lead)', 'CastleGate', 30.0, Reason) then
    FLastActionBanner := 'GRANTED: Alice locked subtree "CastleGate" (including child "GateHinge") for 30s.'
  else
    FLastActionBanner := 'DENIED: ' + Reason;
  RefreshView;
end;

procedure TCollabPresenceForm.BtnBobConflictHingeClick(Sender: TObject);
var
  Reason: String;
  B: TCollabPresenceBroker;
begin
  B := TCollabPresenceBroker.SharedBroker;
  B.UpdatePeerPresence('bob', 'Bob (Gameplay)', 'GateHinge', Vector3(-2, 2, 5));
  if B.AcquireSubtreeLock(FDesignRoot, 'bob', 'Bob (Gameplay)', 'GateHinge', 30.0, Reason) then
    FLastActionBanner := 'GRANTED: Bob locked "GateHinge".'
  else
    FLastActionBanner := 'BLOCKED CONFLICT: ' + Reason;
  RefreshView;
end;

procedure TCollabPresenceForm.BtnBobSiblingSignClick(Sender: TObject);
var
  Reason: String;
  B: TCollabPresenceBroker;
begin
  B := TCollabPresenceBroker.SharedBroker;
  B.UpdatePeerPresence('bob', 'Bob (Gameplay)', 'TavernSign', Vector3(4, 2.5, 6));
  if B.AcquireSubtreeLock(FDesignRoot, 'bob', 'Bob (Gameplay)', 'TavernSign', 30.0, Reason) then
    FLastActionBanner := 'GRANTED: Bob locked independent sibling subtree "TavernSign" in parallel!'
  else
    FLastActionBanner := 'DENIED: ' + Reason;
  RefreshView;
end;

procedure TCollabPresenceForm.BtnExpireStaleClick(Sender: TObject);
var
  ExpiredCnt: Integer;
begin
  TCollabPresenceBroker.SharedBroker.AdvanceClockSeconds(35.0);
  ExpiredCnt := TCollabPresenceBroker.SharedBroker.ExpireStaleLocks;
  FLastActionBanner := Format('Advanced +35.0s -> Automatically reclaimed %d expired stale lease(s).', [ExpiredCnt]);
  RefreshView;
end;

procedure TCollabPresenceForm.BtnCopyJsonClick(Sender: TObject);
begin
  Clipboard.AsText := TCollabPresenceBroker.SharedBroker.ExportSessionJson;
end;

procedure TCollabPresenceForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TCollabPresenceBroker.SharedBroker.GenerateCollabReport(FDesignRoot);
end;

procedure TCollabPresenceForm.PaintPresenceBoard(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, Y, BarW: Integer;
  B: TCollabPresenceBroker;
  L: TCollabSubtreeLock;
  RemRatio: Double;
begin
  Cv := FPaintPresence.Canvas;
  W := FPaintPresence.Width;
  H := FPaintPresence.Height;
  Cv.Brush.Color := RGBToColor(16, 20, 30);
  Cv.FillRect(0, 0, W, H);

  B := TCollabPresenceBroker.SharedBroker;
  Cv.Font.Color := RGBToColor(115, 235, 165);
  Cv.TextOut(16, 12, Format('Horizon 11 Unified Hub: %d Studios | 19 MCP Tools | Clock: %.1fs', [
    TStudioHubManager.StudioCount, B.CurrentTimeSec]));

  Y := 48;
  if B.ActiveLockCount = 0 then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, Y, 'No active subtree locks — click "Alice Locks CastleGate" to test.');
  end else
    for I := 0 to B.ActiveLockCount - 1 do
    begin
      L := B.GetLock(I);
      RemRatio := EnsureRange((L.LeaseExpiresAtSec - B.CurrentTimeSec) / 30.0, 0.05, 1.0);
      BarW := Round((W - 40) * RemRatio);
      Cv.Brush.Color := RGBToColor(52, 130, 215);
      Cv.Rectangle(16, Y, 16 + BarW, Y + 34);
      Cv.Brush.Style := bsClear;
      Cv.Font.Color := clWhite;
      Cv.TextOut(24, Y + 9, Format('%s -> Locked "%s" (%.1fs left, HB=%d)', [
        L.UserDisplayName, L.SubtreeRootName,
        Max(0.0, L.LeaseExpiresAtSec - B.CurrentTimeSec), L.HeartbeatCount]));
      Cv.Brush.Style := bsSolid;
      Inc(Y, 44);
    end;
end;

end.
