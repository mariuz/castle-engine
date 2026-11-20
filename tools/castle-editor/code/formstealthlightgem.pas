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

{ Visual Studio dialog for Tactical Stealth Light-Gem Meter, WorldRay Shadow
  Occlusion & Backlight Silhouette Studio (Phase 402). }
unit FormStealthLightGem;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleViewport,
  CastleStealthLightGem, ToolStealthLightGem;

type
  TStealthLightGemModifiedCallback = procedure(const UndoComment: String) of object;
  TStealthLightGemRefreshCallback = procedure of object;

  TStealthLightGemForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TStealthLightGemModifiedCallback;
    FOnRefresh: TStealthLightGemRefreshCallback;
    FLblSummary: TLabel;
    FPaintGem: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnPillarShadowClick(Sender: TObject);
    procedure BtnExposedTorchClick(Sender: TObject);
    procedure BtnBacklightClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintGemMeter(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TStealthLightGemModifiedCallback;
      const AOnRefresh: TStealthLightGemRefreshCallback);
  end;

implementation

constructor TStealthLightGemForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TStealthLightGemModifiedCallback;
  const AOnRefresh: TStealthLightGemRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Tactical Stealth Light-Gem & Backlight Silhouette Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TStealthLightGemForm.ActiveWorldRoot: TCastleAbstractRootTransform;
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

procedure TStealthLightGemForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnShadow, BtnExposed, BtnBacklight, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Cloister Shadow Demo';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnShadow := TButton.Create(Self);
  BtnShadow.Parent := PnlButtons;
  BtnShadow.SetBounds(190, 8, 145, 30);
  BtnShadow.Caption := 'Crouch Behind Pillar';
  BtnShadow.OnClick := @BtnPillarShadowClick;

  BtnExposed := TButton.Create(Self);
  BtnExposed.Parent := PnlButtons;
  BtnExposed.SetBounds(340, 8, 145, 30);
  BtnExposed.Caption := 'Step Into Torchlight';
  BtnExposed.OnClick := @BtnExposedTorchClick;

  BtnBacklight := TButton.Create(Self);
  BtnBacklight.Parent := PnlButtons;
  BtnBacklight.SetBounds(490, 8, 135, 30);
  BtnBacklight.Caption := 'Backlight Silhouette';
  BtnBacklight.OnClick := @BtnBacklightClick;

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

  FPaintGem := TPaintBox.Create(Self);
  FPaintGem.Parent := Self;
  FPaintGem.Align := alTop;
  FPaintGem.Height := 210;
  FPaintGem.OnPaint := @PaintGemMeter;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TStealthLightGemForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TStealthLightGemForm.RefreshView;
var
  Gem: TCastleStealthLightGem;
begin
  Gem := TStealthLightGemHelper.FindFirstGem(FDesignRoot);
  if Gem <> nil then
    FLblSummary.Caption := Gem.Name + '  ' + Gem.LightGemSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleStealthLightGem in scene — click "+ Spawn Cloister Shadow Demo".';
  FMemoReport.Lines.Text := TStealthLightGemHelper.GenerateMarkdownReport(Gem);
  FPaintGem.Invalidate;
end;

procedure TStealthLightGemForm.BtnSpawnDemoClick(Sender: TObject);
var
  Gem: TCastleStealthLightGem;
begin
  if TStealthLightGemHelper.SpawnGothicCloisterStealthDemo(FDesignRoot, FDesignOwner, Gem) then
    NotifyChanged('Spawn Stealth Light-Gem Demo');
end;

procedure TStealthLightGemForm.BtnPillarShadowClick(Sender: TObject);
var
  Gem: TCastleStealthLightGem;
begin
  Gem := TStealthLightGemHelper.FindFirstGem(FDesignRoot);
  if Gem = nil then Exit;
  Gem.Translation := Vector3(0.0, 1.2, -2.2);
  Gem.EvaluateLightGem(ActiveWorldRoot, Vector3(0.0, 1.2, -2.2),
    Vector3(-5.0, 1.7, -2.2), True, True);
  NotifyChanged('Evaluate Pillar Shadow Concealment');
end;

procedure TStealthLightGemForm.BtnExposedTorchClick(Sender: TObject);
var
  Gem: TCastleStealthLightGem;
begin
  Gem := TStealthLightGemHelper.FindFirstGem(FDesignRoot);
  if Gem = nil then Exit;
  Gem.Translation := Vector3(2.8, 1.6, 2.6);
  Gem.EvaluateLightGem(ActiveWorldRoot, Vector3(2.8, 1.6, 2.6),
    Vector3(-3.0, 1.7, 2.6), False, False);
  NotifyChanged('Evaluate Exposed Torchlight');
end;

procedure TStealthLightGemForm.BtnBacklightClick(Sender: TObject);
var
  Gem: TCastleStealthLightGem;
begin
  Gem := TStealthLightGemHelper.FindFirstGem(FDesignRoot);
  if Gem = nil then Exit;
  { Player stands in shadow at (3.5, 1.4, -3.5) with FarArchwayBrazier (3.5, 1.8, -10.0)
    directly behind them from Guard at (3.5, 1.7, +3.0)! }
  Gem.Translation := Vector3(3.5, 1.4, -3.5);
  Gem.EvaluateLightGem(ActiveWorldRoot, Vector3(3.5, 1.4, -3.5),
    Vector3(3.5, 1.7, 3.0), False, False);
  NotifyChanged('Evaluate Backlight Silhouette Exposure');
end;

procedure TStealthLightGemForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TStealthLightGemForm.PaintGemMeter(Sender: TObject);
var
  C: TCanvas;
  W, H, CX, CY, BarW: Integer;
  Gem: TCastleStealthLightGem;
  V: Single;
  Pts: array[0..3] of TPoint;
begin
  C := FPaintGem.Canvas;
  W := FPaintGem.Width;
  H := FPaintGem.Height;
  C.Brush.Color := RGBToColor(18, 20, 28);
  C.FillRect(0, 0, W, H);

  Gem := TStealthLightGemHelper.FindFirstGem(FDesignRoot);
  if Gem = nil then Exit;

  V := Clamped(Gem.LastSample.FinalVisibilityGem01, 0.0, 1.0);
  CX := 120;
  CY := H div 2;

  Pts[0] := Point(CX, CY - 64);
  Pts[1] := Point(CX + 52, CY);
  Pts[2] := Point(CX, CY + 64);
  Pts[3] := Point(CX - 52, CY);
  C.Brush.Color := RGBToColor(
    Round(35 + 220 * V),
    Round(55 + 165 * V),
    Round(90 + 40 * (1.0 - V)));
  C.Pen.Color := RGBToColor(235, 225, 180);
  C.Polygon(Pts);

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(210, 34, Format('Light-Gem Visibility: %.1f%% (Alert >= %.0f%%)',
    [V * 100.0, Gem.AlertThreshold01 * 100.0]));

  BarW := Round((W - 250) * V);
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(45, 50, 66);
  C.FillRect(210, 68, W - 40, 96);
  if V >= Gem.AlertThreshold01 then
    C.Brush.Color := RGBToColor(245, 185, 45)
  else
    C.Brush.Color := RGBToColor(60, 175, 125);
  C.FillRect(210, 68, 210 + BarW, 96);

  C.Brush.Style := bsClear;
  C.TextOut(210, 116, Format('Direct Light: %.1f%%   |   Backlight Silhouette: %.1f%%   |   Stance Scale: %.2fx',
    [Gem.LastSample.DirectIllumination01 * 100.0,
     Gem.LastSample.BacklightSilhouette01 * 100.0,
     Gem.LastSample.StanceConcealmentScale]));
end;

end.
