{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Visual Studio dialog for Grappling Hook & Vine 3D Spherical Pendulum Swing,
  Motorized Winch Reel-In & Apex Release Studio (Phase 403). }
unit FormGrapplePendulum;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleGrapplePendulum, ToolGrapplePendulum;

type
  TGrapplePendulumModifiedCallback = procedure(const UndoComment: String) of object;
  TGrapplePendulumRefreshCallback = procedure of object;

  TGrapplePendulumForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TGrapplePendulumModifiedCallback;
    FOnRefresh: TGrapplePendulumRefreshCallback;
    FLblSummary: TLabel;
    FPaintArc: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnStepSwingClick(Sender: TObject);
    procedure BtnStepWinchClick(Sender: TObject);
    procedure BtnApexReleaseClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintPendulumArc(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TGrapplePendulumModifiedCallback;
      const AOnRefresh: TGrapplePendulumRefreshCallback);
  end;

implementation

constructor TGrapplePendulumForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TGrapplePendulumModifiedCallback;
  const AOnRefresh: TGrapplePendulumRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Grappling Hook Pendulum Swing, Winch Reel & Apex Jump Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TGrapplePendulumForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnSwing, BtnWinch, BtnApex, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 42;
  PnlTop.BevelOuter := bvNone;

  FLblSummary := TLabel.Create(Self);
  FLblSummary.Parent := PnlTop;
  FLblSummary.Left := 12;
  FLblSummary.Top := 12;
  FLblSummary.Caption := 'Ready.';

  PnlButtons := TPanel.Create(Self);
  PnlButtons.Parent := Self;
  PnlButtons.Align := alTop;
  PnlButtons.Height := 46;
  PnlButtons.BevelOuter := bvNone;

  BtnSpawn := TButton.Create(Self);
  BtnSpawn.Parent := PnlButtons;
  BtnSpawn.SetBounds(10, 8, 175, 30);
  BtnSpawn.Caption := '+ Spawn Gargoyle Swing';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnSwing := TButton.Create(Self);
  BtnSwing.Parent := PnlButtons;
  BtnSwing.SetBounds(190, 8, 145, 30);
  BtnSwing.Caption := 'Step Swing (+0.45s)';
  BtnSwing.OnClick := @BtnStepSwingClick;

  BtnWinch := TButton.Create(Self);
  BtnWinch.Parent := PnlButtons;
  BtnWinch.SetBounds(340, 8, 145, 30);
  BtnWinch.Caption := 'Winch Reel-In (+0.4s)';
  BtnWinch.OnClick := @BtnStepWinchClick;

  BtnApex := TButton.Create(Self);
  BtnApex.Parent := PnlButtons;
  BtnApex.SetBounds(490, 8, 135, 30);
  BtnApex.Caption := 'Apex Jump Release';
  BtnApex.OnClick := @BtnApexReleaseClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(630, 8, 70, 30);
  BtnCopy.Caption := 'Copy MD';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlButtons;
  BtnClose.SetBounds(705, 8, 65, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;
  BtnClose.OnClick := nil;

  FPaintArc := TPaintBox.Create(Self);
  FPaintArc.Parent := Self;
  FPaintArc.Align := alTop;
  FPaintArc.Height := 215;
  FPaintArc.OnPaint := @PaintPendulumArc;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TGrapplePendulumForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TGrapplePendulumForm.RefreshView;
var
  Rig: TCastleGrapplePendulum;
begin
  Rig := TGrapplePendulumHelper.FindFirstRig(FDesignRoot);
  if Rig <> nil then
    FLblSummary.Caption := Rig.Name + '  ' + Rig.GrappleSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleGrapplePendulum in scene — click "+ Spawn Gargoyle Swing".';
  FMemoReport.Lines.Text := TGrapplePendulumHelper.GenerateMarkdownReport(Rig);
  FPaintArc.Invalidate;
end;

procedure TGrapplePendulumForm.BtnSpawnDemoClick(Sender: TObject);
var
  Rig: TCastleGrapplePendulum;
begin
  if TGrapplePendulumHelper.SpawnGargoyleChasmSwingDemo(FDesignRoot, FDesignOwner, Rig) then
    NotifyChanged('Spawn Gargoyle Grapple Swing Demo');
end;

procedure TGrapplePendulumForm.BtnStepSwingClick(Sender: TObject);
var
  Rig: TCastleGrapplePendulum;
begin
  Rig := TGrapplePendulumHelper.FindFirstRig(FDesignRoot);
  if Rig = nil then Exit;
  Rig.StepPendulumSwing(0.45, False);
  NotifyChanged('Step Grapple Pendulum Swing');
end;

procedure TGrapplePendulumForm.BtnStepWinchClick(Sender: TObject);
var
  Rig: TCastleGrapplePendulum;
begin
  Rig := TGrapplePendulumHelper.FindFirstRig(FDesignRoot);
  if Rig = nil then Exit;
  Rig.StepPendulumSwing(0.40, True);
  NotifyChanged('Step Motorized Grapple Winch');
end;

procedure TGrapplePendulumForm.BtnApexReleaseClick(Sender: TObject);
var
  Rig: TCastleGrapplePendulum;
begin
  Rig := TGrapplePendulumHelper.FindFirstRig(FDesignRoot);
  if Rig = nil then Exit;
  Rig.ReleaseApexJump;
  Rig.StepPendulumSwing(0.25, False);
  NotifyChanged('Release Grapple Apex Jump');
end;

procedure TGrapplePendulumForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TGrapplePendulumForm.PaintPendulumArc(Sender: TObject);
var
  C: TCanvas;
  W, H, AX, AY, PX, PY, RadPx: Integer;
  Rig: TCastleGrapplePendulum;
  S: TGrappleSwingState;
  ScalePx: Single;
begin
  C := FPaintArc.Canvas;
  W := FPaintArc.Width;
  H := FPaintArc.Height;
  C.Brush.Color := RGBToColor(18, 22, 32);
  C.FillRect(0, 0, W, H);

  Rig := TGrapplePendulumHelper.FindFirstRig(FDesignRoot);
  if Rig = nil then Exit;
  S := Rig.State;

  AX := W div 2;
  AY := 26;
  ScalePx := 12.0;
  RadPx := Round(S.RopeLengthMeters * ScalePx);

  C.Brush.Style := bsClear;
  C.Pen.Color := RGBToColor(58, 72, 98);
  C.Pen.Style := psDot;
  C.Ellipse(AX - RadPx, AY - RadPx, AX + RadPx, AY + RadPx);
  C.Pen.Style := psSolid;

  PX := AX + Round((S.PlayerWorldPos.X - S.AnchorWorldPos.X) * ScalePx);
  PY := AY - Round((S.PlayerWorldPos.Y - S.AnchorWorldPos.Y) * ScalePx);

  if S.HookAttached then
  begin
    if S.RopeIsTaut then
      C.Pen.Color := RGBToColor(245, 195, 65)
    else
      C.Pen.Color := RGBToColor(120, 165, 220);
    C.Pen.Width := 2;
    C.MoveTo(AX, AY);
    C.LineTo(PX, PY);
    C.Pen.Width := 1;
  end;

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(220, 95, 60);
  C.Ellipse(AX - 6, AY - 6, AX + 6, AY + 6);

  C.Brush.Color := RGBToColor(70, 210, 145);
  C.Ellipse(PX - 8, PY - 8, PX + 8, PY + 8);

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(14, H - 26, Format('Anchor (%.1f, %.1f) -> Rider (%.1f, %.1f) | Speed %.2f m/s | Tension %.0f N',
    [S.AnchorWorldPos.X, S.AnchorWorldPos.Y,
     S.PlayerWorldPos.X, S.PlayerWorldPos.Y,
     S.VelocityMps.Length, S.CableTensionNewtons]));
end;

end.
