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

{ Visual Studio dialog for Dual-Axis Gimbal Turret, Slew-Rate Servo,
  Critically-Damped Barrel Recoil & Thermal Overheat Vent Studio (Phase 413). }
unit FormTurretGimbal;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleTurretGimbal, ToolTurretGimbal;

type
  TTurretGimbalModifiedCallback = procedure(const UndoComment: String) of object;
  TTurretGimbalRefreshCallback = procedure of object;

  TTurretGimbalForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TTurretGimbalModifiedCallback;
    FOnRefresh: TTurretGimbalRefreshCallback;
    FLblSummary: TLabel;
    FPaintDial: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnSlewStarboardClick(Sender: TObject);
    procedure BtnFireSalvoClick(Sender: TObject);
    procedure BtnCoolVentClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintTurretDial(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TTurretGimbalModifiedCallback;
      const AOnRefresh: TTurretGimbalRefreshCallback);
  end;

implementation

constructor TTurretGimbalForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TTurretGimbalModifiedCallback;
  const AOnRefresh: TTurretGimbalRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Dual-Axis Gimbal Turret, Slew Servo, Recoil & Overheat Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TTurretGimbalForm.ActiveWorldRoot: TCastleAbstractRootTransform;
var
  I: Integer;
begin
  Result := nil;
  if FDesignRoot = nil then Exit;
  if FDesignRoot is TCastleViewport then
    Exit(TCastleViewport(FDesignRoot).Items);
  for I := 0 to FDesignRoot.ComponentCount - 1 do
    if FDesignRoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(FDesignRoot.Components[I]).Items);
end;

procedure TTurretGimbalForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnSlew, BtnFire, BtnCool, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Battleship Turret';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnSlew := TButton.Create(Self);
  BtnSlew.Parent := PnlButtons;
  BtnSlew.SetBounds(190, 8, 145, 30);
  BtnSlew.Caption := 'Slew Starboard (+0.8s)';
  BtnSlew.OnClick := @BtnSlewStarboardClick;

  BtnFire := TButton.Create(Self);
  BtnFire.Parent := PnlButtons;
  BtnFire.SetBounds(340, 8, 145, 30);
  BtnFire.Caption := 'Fire Cannon Round';
  BtnFire.OnClick := @BtnFireSalvoClick;

  BtnCool := TButton.Create(Self);
  BtnCool.Parent := PnlButtons;
  BtnCool.SetBounds(490, 8, 135, 30);
  BtnCool.Caption := 'Cool & Settle (+1.5s)';
  BtnCool.OnClick := @BtnCoolVentClick;

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

  FPaintDial := TPaintBox.Create(Self);
  FPaintDial.Parent := Self;
  FPaintDial.Align := alTop;
  FPaintDial.Height := 215;
  FPaintDial.OnPaint := @PaintTurretDial;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TTurretGimbalForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TTurretGimbalForm.RefreshView;
var
  T: TCastleTurretGimbal;
begin
  T := TTurretGimbalHelper.FindFirstTurret(FDesignRoot);
  if T <> nil then
    FLblSummary.Caption := T.Name + '  ' + T.TurretSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleTurretGimbal in scene — click "+ Spawn Battleship Turret".';
  FMemoReport.Lines.Text := TTurretGimbalHelper.GenerateMarkdownReport(T);
  FPaintDial.Invalidate;
end;

procedure TTurretGimbalForm.BtnSpawnDemoClick(Sender: TObject);
var
  T: TCastleTurretGimbal;
begin
  if TTurretGimbalHelper.SpawnBattleshipDeckTurretDemo(FDesignRoot, FDesignOwner, T) then
    NotifyChanged('Spawn Battleship Main Turret Demo');
end;

procedure TTurretGimbalForm.BtnSlewStarboardClick(Sender: TObject);
var
  T: TCastleTurretGimbal;
begin
  T := TTurretGimbalHelper.FindFirstTurret(FDesignRoot);
  if T = nil then Exit;
  T.StepServoTracking(ActiveWorldRoot, Vector3(15.0, 6.0, -10.0), 0.80);
  NotifyChanged('Step Turret Servo Slew');
end;

procedure TTurretGimbalForm.BtnFireSalvoClick(Sender: TObject);
var
  T: TCastleTurretGimbal;
begin
  T := TTurretGimbalHelper.FindFirstTurret(FDesignRoot);
  if T = nil then Exit;
  T.FireCannonRound;
  NotifyChanged('Fire Turret Cannon Round');
end;

procedure TTurretGimbalForm.BtnCoolVentClick(Sender: TObject);
var
  T: TCastleTurretGimbal;
begin
  T := TTurretGimbalHelper.FindFirstTurret(FDesignRoot);
  if T = nil then Exit;
  T.StepServoTracking(ActiveWorldRoot, Vector3(15.0, 6.0, -10.0), 1.50);
  NotifyChanged('Cool Turret & Recover Recoil');
end;

procedure TTurretGimbalForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TTurretGimbalForm.PaintTurretDial(Sender: TObject);
var
  C: TCanvas;
  W, H, CX, CY, BX, BY, HeatW: Integer;
  T: TCastleTurretGimbal;
  S: TTurretGimbalState;
  YawR: Single;
begin
  C := FPaintDial.Canvas;
  W := FPaintDial.Width;
  H := FPaintDial.Height;
  C.Brush.Color := RGBToColor(18, 22, 28);
  C.FillRect(0, 0, W, H);

  T := TTurretGimbalHelper.FindFirstTurret(FDesignRoot);
  if T = nil then Exit;
  S := T.State;

  CX := 130;
  CY := H div 2;
  C.Brush.Color := RGBToColor(32, 38, 48);
  C.Pen.Color := RGBToColor(120, 155, 195);
  C.Ellipse(CX - 76, CY - 76, CX + 76, CY + 76);

  YawR := DegToRad(S.CurrentYawDeg);
  BX := CX + Round(Sin(YawR) * (70.0 - S.RecoilOffsetMeters * 30.0));
  BY := CY - Round(Cos(YawR) * (70.0 - S.RecoilOffsetMeters * 30.0));
  C.Pen.Color := RGBToColor(95, 225, 255);
  C.Pen.Width := 4;
  C.MoveTo(CX, CY);
  C.LineTo(BX, BY);
  C.Pen.Width := 1;

  HeatW := Round((W - 280) * S.BarrelHeat01);
  C.Brush.Color := RGBToColor(45, 50, 62);
  C.FillRect(240, 65, W - 40, 95);
  if S.IsOverheatedVenting then
    C.Brush.Color := RGBToColor(245, 70, 55)
  else
    C.Brush.Color := RGBToColor(245, 175, 55);
  C.FillRect(240, 65, 240 + HeatW, 95);

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(240, 36, Format('Yaw %.1f deg | Pitch %.1f deg | Recoil %.2f m',
    [S.CurrentYawDeg, S.CurrentPitchDeg, S.RecoilOffsetMeters]));
  C.TextOut(240, 114, Format('Barrel Heat: %.0f%% | Vent Lockout: %s | Friendly Inhibit: %s',
    [S.BarrelHeat01 * 100.0, BoolToStr(S.IsOverheatedVenting, True),
     BoolToStr(S.FriendlyHullBlocked, True)]));
end;

end.
