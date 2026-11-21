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

{ Visual Studio dialog for Tactical Boss Telegraph & AoE Hazard Zone
  (Pizza-Cone, Safe-Eye Donut, Line Charge & Jumpable Shock-Ring) Studio (Phase 412). }
unit FormBossArena;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleBossArena, ToolBossArena;

type
  TBossArenaModifiedCallback = procedure(const UndoComment: String) of object;
  TBossArenaRefreshCallback = procedure of object;

  TBossArenaForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TBossArenaModifiedCallback;
    FOnRefresh: TBossArenaRefreshCallback;
    FLblSummary: TLabel;
    FPaintArena: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnTestDonutEyeClick(Sender: TObject);
    procedure BtnTestPillarHideClick(Sender: TObject);
    procedure BtnTestAirJumpClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintRaidRadar(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TBossArenaModifiedCallback;
      const AOnRefresh: TBossArenaRefreshCallback);
  end;

implementation

constructor TBossArenaForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TBossArenaModifiedCallback;
  const AOnRefresh: TBossArenaRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Boss Telegraph & AoE Hazard (Cone, Donut, Shock-Ring) Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TBossArenaForm.ActiveWorldRoot: TCastleAbstractRootTransform;
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

procedure TBossArenaForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnEye, BtnPillar, BtnJump, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Raid Arena Combo';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnEye := TButton.Create(Self);
  BtnEye.Parent := PnlButtons;
  BtnEye.SetBounds(190, 8, 145, 30);
  BtnEye.Caption := 'Hug Safe Donut Eye';
  BtnEye.OnClick := @BtnTestDonutEyeClick;

  BtnPillar := TButton.Create(Self);
  BtnPillar.Parent := PnlButtons;
  BtnPillar.SetBounds(340, 8, 145, 30);
  BtnPillar.Caption := 'Hide Behind Pillar';
  BtnPillar.OnClick := @BtnTestPillarHideClick;

  BtnJump := TButton.Create(Self);
  BtnJump.Parent := PnlButtons;
  BtnJump.SetBounds(490, 8, 135, 30);
  BtnJump.Caption := 'Jump Over Shock-Ring';
  BtnJump.OnClick := @BtnTestAirJumpClick;

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

  FPaintArena := TPaintBox.Create(Self);
  FPaintArena.Parent := Self;
  FPaintArena.Align := alTop;
  FPaintArena.Height := 215;
  FPaintArena.OnPaint := @PaintRaidRadar;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TBossArenaForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TBossArenaForm.RefreshView;
var
  D: TCastleBossHazardDirector;
begin
  D := TBossArenaHelper.FindFirstDirector(FDesignRoot);
  if D <> nil then
    FLblSummary.Caption := D.Name + '  ' + D.HazardSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleBossHazardDirector in scene — click "+ Spawn Raid Arena Combo".';
  FMemoReport.Lines.Text := TBossArenaHelper.GenerateMarkdownReport(D);
  FPaintArena.Invalidate;
end;

procedure TBossArenaForm.BtnSpawnDemoClick(Sender: TObject);
var
  D: TCastleBossHazardDirector;
begin
  if TBossArenaHelper.SpawnRaidBossOverlapArenaDemo(FDesignRoot, FDesignOwner, D) then
    NotifyChanged('Spawn Boss Raid Telegraph Arena');
end;

procedure TBossArenaForm.BtnTestDonutEyeClick(Sender: TObject);
var
  D: TCastleBossHazardDirector;
begin
  D := TBossArenaHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;
  D.EvaluatePlayerSafety(ActiveWorldRoot, Vector3(0.0, 0.0, -2.0));
  NotifyChanged('Evaluate Safe Inner Donut Eye');
end;

procedure TBossArenaForm.BtnTestPillarHideClick(Sender: TObject);
var
  D: TCastleBossHazardDirector;
begin
  D := TBossArenaHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;
  D.EvaluatePlayerSafety(ActiveWorldRoot, Vector3(0.0, 0.0, 9.0));
  NotifyChanged('Evaluate Pillar Line-Of-Sight Shelter');
end;

procedure TBossArenaForm.BtnTestAirJumpClick(Sender: TObject);
var
  D: TCastleBossHazardDirector;
begin
  D := TBossArenaHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;
  D.EvaluatePlayerSafety(ActiveWorldRoot, Vector3(-5.0, 1.35, 0.0));
  NotifyChanged('Evaluate Airborne Jump Over Shockwave Ring');
end;

procedure TBossArenaForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TBossArenaForm.PaintRaidRadar(Sender: TObject);
var
  C: TCanvas;
  W, H, CX, CY, ROut, RIn: Integer;
  D: TCastleBossHazardDirector;
begin
  C := FPaintArena.Canvas;
  W := FPaintArena.Width;
  H := FPaintArena.Height;
  C.Brush.Color := RGBToColor(22, 18, 28);
  C.FillRect(0, 0, W, H);

  D := TBossArenaHelper.FindFirstDirector(FDesignRoot);
  if D = nil then Exit;

  CX := W div 2;
  CY := H div 2;
  ROut := 84;
  RIn := 28;

  C.Brush.Color := RGBToColor(195, 55, 50);
  C.Pen.Color := RGBToColor(255, 165, 80);
  C.Ellipse(CX - ROut, CY - ROut, CX + ROut, CY + ROut);

  C.Brush.Color := RGBToColor(42, 165, 95);
  C.Ellipse(CX - RIn, CY - RIn, CX + RIn, CY + RIn);

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(16, H - 24, Format('Red = Lethal Donut/Cone | Green Center = Safe Melee Eye | Threats: %d (%.0f Dmg)',
    [D.LastEval.ThreateningZoneCount, D.LastEval.PotentialDamageSum]));
end;

end.
