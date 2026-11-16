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

{ Interactive Iris-Style Netcode Replication, Spatial Relevancy, Jitter-Buffered
  Snapshot Interpolation & Lag-Compensated Hitbox Rewind Studio
  (@link(TNetcodeStudioForm)) (Phase 321). }
unit FormNetcodeStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleNetcodeIris, ToolNetcodeStudio;

type
  TNetcodeStudioModifiedCallback = procedure(const AComment: String) of object;
  TNetcodeStudioRefreshViewportCallback = procedure of object;

  TNetcodeStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TNetcodeStudioModifiedCallback;
    FOnRefreshViewport: TNetcodeStudioRefreshViewportCallback;

    FMgrs: TNetManagerArray;
    FActors: TReplicatedBehaviorArray;
    FReport: TNetcodeAuditReport;
    FLastShotSummary: String;

    LblHeader: TLabel;
    ListActors: TListBox;
    PaintNet: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function ActiveMgr: TCastleNetReplicationManager;
    function PrimaryActor: TCastleReplicatedBehavior;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnSpawnArenaClick(Sender: TObject);
    procedure BtnStepSprintTickClick(Sender: TObject);
    procedure BtnFireLagCompShotClick(Sender: TObject);
    procedure BtnHighLatencyPresetClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintNetPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TNetcodeStudioModifiedCallback;
      const AOnRefreshViewport: TNetcodeStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TNetcodeStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TNetcodeStudioModifiedCallback;
  const AOnRefreshViewport: TNetcodeStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Iris Netcode Replication, Spatial Relevancy & Lag-Compensated Hitbox Rewind Studio';
  Width := 1140;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TNetcodeStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TNetcodeStudioForm.BuildUi;
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
  PanelTop.Height := 72;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.SetBounds(12, 8, 1080, 20);
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Iris Netcode Replication: scanning...';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 34, 1120, 32);
  RowTop.BevelOuter := bvNone;
  MakeBtn(RowTop, '+ Spawn Iris Arena Demo', 4, 2, 185, @BtnSpawnArenaClick);
  MakeBtn(RowTop, 'Sprint + Step Net (+0.10s)', 195, 2, 195, @BtnStepSprintTickClick);
  MakeBtn(RowTop, 'Fire Lag-Comp Rewind Shot!', 396, 2, 195, @BtnFireLagCompShotClick);
  MakeBtn(RowTop, 'Sim 220ms RTT + 12% Loss', 597, 2, 190, @BtnHighLatencyPresetClick);
  MakeBtn(RowTop, 'Copy Markdown Report', 793, 2, 175, @BtnCopyMarkdownClick);

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
  Lbl.Caption := 'Replicated Actors & Relevancy:';

  ListActors := TListBox.Create(Self);
  ListActors.Parent := PanelLeft;
  ListActors.SetBounds(10, 26, 320, 230);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 264, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Bandwidth, Rewind Shot & QA:';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelLeft;
  MemoDiag.SetBounds(10, 286, 320, 285);
  MemoDiag.Anchors := [akTop, akLeft, akBottom];
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintNet := TPaintBox.Create(Self);
  PaintNet.Parent := PanelCenter;
  PaintNet.Align := alClient;
  PaintNet.OnPaint := @PaintNetPaint;
end;

function TNetcodeStudioForm.ActiveMgr: TCastleNetReplicationManager;
begin
  if Length(FMgrs) > 0 then
    Result := FMgrs[0]
  else
    Result := nil;
end;

function TNetcodeStudioForm.PrimaryActor: TCastleReplicatedBehavior;
begin
  if Length(FActors) > 0 then
    Result := FActors[0]
  else
    Result := nil;
end;

procedure TNetcodeStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TNetcodeStudioForm.RefreshAll;
var
  I: Integer;
  M: TCastleNetReplicationManager;
begin
  TNetcodeStudioHelper.ScanNetcode(FDesignRoot, FDesignOwner, FMgrs, FActors);
  FreeAndNil(FReport);
  FReport := TNetcodeStudioHelper.AuditNetcode(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'Iris Managers: %d  |  Actors: %d (%d Relevant, %d Culled)  |  Bandwidth: %.1f kbps  |  Warnings: %d',
    [FReport.ManagerCount, FReport.ReplicatedActorCount, FReport.RelevantActorCount,
     FReport.ReplicatedActorCount - FReport.RelevantActorCount,
     FReport.EstimatedKbps, FReport.Warnings.Count]);

  ListActors.Items.BeginUpdate;
  try
    ListActors.Items.Clear;
    for I := 0 to High(FActors) do
      ListActors.Items.Add(Format('%s  %s', [FActors[I].Name, FActors[I].ReplicatedSummaryBadge]));
  finally
    ListActors.Items.EndUpdate;
  end;

  MemoDiag.Lines.BeginUpdate;
  try
    MemoDiag.Lines.Clear;
    M := ActiveMgr;
    if M <> nil then
    begin
      MemoDiag.Lines.Add(M.NetManagerSummaryBadge);
      MemoDiag.Lines.Add(Format('Server Clock: %.2fs  |  Client Render Time: %.2fs',
        [M.ServerClockSec, M.ClientRenderServerTimeSec]));
      MemoDiag.Lines.Add(Format('Packet Loss: %.1f%%  |  Jitter: ±%.0f ms',
        [M.SimulatedPacketLossPct, M.SimulatedJitterMs]));
      if FLastShotSummary <> '' then
      begin
        MemoDiag.Lines.Add('');
        MemoDiag.Lines.Add(FLastShotSummary);
      end;
      MemoDiag.Lines.Add('');
    end;
    if FReport.Warnings.Count = 0 then
      MemoDiag.Lines.Add('[OK] Iris replication graph & interpolation buffers healthy.')
    else
      for I := 0 to FReport.Warnings.Count - 1 do
        MemoDiag.Lines.Add('[WARN] ' + FReport.Warnings[I]);
  finally
    MemoDiag.Lines.EndUpdate;
  end;

  PaintNet.Invalidate;
end;

procedure TNetcodeStudioForm.BtnSpawnArenaClick(Sender: TObject);
var
  M: TCastleNetReplicationManager;
  T1, T2: TCastleTransform;
  R1, R2: TCastleReplicatedBehavior;
begin
  TNetcodeStudioHelper.SpawnMultiplayerIrisArenaDemo(
    FDesignRoot, FDesignOwner, M, T1, T2, R1, R2);
  NotifyChanged('Spawn Iris Multiplayer Arena Demo');
end;

procedure TNetcodeStudioForm.BtnStepSprintTickClick(Sender: TObject);
var
  M: TCastleNetReplicationManager;
  A: TCastleReplicatedBehavior;
begin
  M := ActiveMgr;
  A := PrimaryActor;
  if M = nil then Exit;
  if (A <> nil) and (A.Parent <> nil) then
    A.Parent.Translation := A.Parent.Translation + Vector3(0.60, 0.0, 0.0);
  M.StepReplication(FDesignRoot, FDesignOwner, 0.10, TVector3.Zero);
  NotifyChanged('Step Server Sprint + Iris Replication (+0.10s)');
end;

procedure TNetcodeStudioForm.BtnFireLagCompShotClick(Sender: TObject);
var
  M: TCastleNetReplicationManager;
  A, HitActor: TCastleReplicatedBehavior;
  ClientSawPos, RewoundCenter, RayDir: TVector3;
  RewindSec, UnrewoundDist: Single;
begin
  M := ActiveMgr;
  A := PrimaryActor;
  if (M = nil) or (A = nil) then Exit;

  RewindSec := M.SimulatedRttMs * 0.0005 + M.ClientInterpDelayMs * 0.001;
  ClientSawPos := A.LastClientInterpPos;
  RayDir := (ClientSawPos - Vector3(0.0, 0.90, 0.0)).Normalize;

  if M.LagCompensatedRaycast(FDesignRoot, FDesignOwner,
       Vector3(0.0, 0.90, 0.0), RayDir, RewindSec,
       HitActor, RewoundCenter, UnrewoundDist) then
    FLastShotSummary := Format(
      '[HIT CONFIRMED] Rewound %.0fms -> hit "%s" at X=%.2fm (Unrewound live dist=%.2fm)!',
      [RewindSec * 1000.0, HitActor.Name, RewoundCenter.X, UnrewoundDist])
  else
    FLastShotSummary := '[MISS] Ray missed rewound hitboxes.';
  RefreshAll;
end;

procedure TNetcodeStudioForm.BtnHighLatencyPresetClick(Sender: TObject);
var
  M: TCastleNetReplicationManager;
begin
  M := ActiveMgr;
  if M = nil then Exit;
  M.SimulatedRttMs := 220.0;
  M.SimulatedJitterMs := 25.0;
  M.SimulatedPacketLossPct := 12.0;
  M.ClientInterpDelayMs := 120.0;
  NotifyChanged('Set High-Ping 220ms + 12% Loss Network Profile');
end;

procedure TNetcodeStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TNetcodeStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TNetcodeStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TNetcodeStudioForm.PaintNetPaint(Sender: TObject);
var
  C: TCanvas;
  M: TCastleNetReplicationManager;
  A: TCastleReplicatedBehavior;
  W, H, MidY, SrvX, CliX, ObsX: Integer;
begin
  C := PaintNet.Canvas;
  W := Max(200, PaintNet.Width);
  H := Max(200, PaintNet.Height);
  C.Brush.Color := RGBToColor(20, 24, 31);
  C.FillRect(0, 0, W, H);

  M := ActiveMgr;
  A := PrimaryActor;
  if (M = nil) or (A = nil) or (A.Parent = nil) then
  begin
    C.Font.Color := RGBToColor(190, 202, 218);
    C.TextOut(24, 24, 'Click "+ Spawn Iris Arena Demo" then "Sprint + Step Net (+0.10s)" to visualize lag compensation.');
    Exit;
  end;

  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.TextOut(20, 14, 'Authoritative Server Pose vs. Jitter-Buffered Client Ghost & Lag-Compensated Rewind');
  C.Font.Style := [];

  MidY := H div 2 - 20;
  ObsX := W div 2;
  SrvX := ObsX + Round(A.Parent.Translation.X * 42.0);
  CliX := ObsX + Round(A.LastClientInterpPos.X * 42.0);

  { Shooter at bottom center }
  C.Brush.Color := RGBToColor(64, 178, 250);
  C.Ellipse(ObsX - 12, H - 64, ObsX + 12, H - 40);
  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(150, 215, 255);
  C.TextOut(ObsX - 52, H - 34, 'CLIENT SHOOTER');

  { Ray line toward client-perceived hitbox }
  C.Pen.Color := RGBToColor(250, 210, 68);
  C.Pen.Style := psDash;
  C.Line(ObsX, H - 52, CliX, MidY);
  C.Pen.Style := psSolid;

  { Client interpolated / rewound hitbox }
  C.Brush.Color := RGBToColor(58, 216, 138);
  C.Pen.Color := RGBToColor(210, 255, 230);
  C.Ellipse(CliX - 24, MidY - 24, CliX + 24, MidY + 24);
  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(110, 245, 170);
  C.TextOut(CliX - 58, MidY - 46, Format('Client / Rewind (X=%.2fm)', [A.LastClientInterpPos.X]));

  { Authoritative live server hitbox }
  C.Brush.Color := RGBToColor(242, 74, 74);
  C.Pen.Color := RGBToColor(255, 210, 210);
  C.Ellipse(SrvX - 24, MidY - 24, SrvX + 24, MidY + 24);
  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(255, 135, 135);
  C.TextOut(SrvX - 52, MidY + 32, Format('Live Server (X=%.2fm)', [A.Parent.Translation.X]));
end;

end.
