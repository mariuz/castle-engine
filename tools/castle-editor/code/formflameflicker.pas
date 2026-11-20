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

{ Visual Studio dialog for Procedural Torch & Campfire Blackbody Flicker,
  Wind-Draft Tilt, Gust Blowout & Wall Soot Studio (Phase 404). }
unit FormFlameFlicker;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleFlameFlicker, ToolFlameFlicker;

type
  TFlameFlickerModifiedCallback = procedure(const UndoComment: String) of object;
  TFlameFlickerRefreshCallback = procedure of object;

  TFlameFlickerForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TFlameFlickerModifiedCallback;
    FOnRefresh: TFlameFlickerRefreshCallback;
    FLblSummary: TLabel;
    FPaintFlame: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    procedure BtnSpawnSconceClick(Sender: TObject);
    procedure BtnStepDraftClick(Sender: TObject);
    procedure BtnGustBlowoutClick(Sender: TObject);
    procedure BtnReigniteClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintFlameSpectrum(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TFlameFlickerModifiedCallback;
      const AOnRefresh: TFlameFlickerRefreshCallback);
  end;

implementation

constructor TFlameFlickerForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TFlameFlickerModifiedCallback;
  const AOnRefresh: TFlameFlickerRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Torch Blackbody Flicker, Wind Blowout & Soot Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TFlameFlickerForm.ActiveWorldRoot: TCastleAbstractRootTransform;
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

procedure TFlameFlickerForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnDraft, BtnGust, BtnIgnite, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Wall Sconce + Soot';
  BtnSpawn.OnClick := @BtnSpawnSconceClick;

  BtnDraft := TButton.Create(Self);
  BtnDraft.Parent := PnlButtons;
  BtnDraft.SetBounds(190, 8, 145, 30);
  BtnDraft.Caption := 'Step Draft (4 m/s)';
  BtnDraft.OnClick := @BtnStepDraftClick;

  BtnGust := TButton.Create(Self);
  BtnGust.Parent := PnlButtons;
  BtnGust.SetBounds(340, 8, 150, 30);
  BtnGust.Caption := 'Gale Gust (14 m/s)';
  BtnGust.OnClick := @BtnGustBlowoutClick;

  BtnIgnite := TButton.Create(Self);
  BtnIgnite.Parent := PnlButtons;
  BtnIgnite.SetBounds(495, 8, 130, 30);
  BtnIgnite.Caption := 'Re-Ignite Torch';
  BtnIgnite.OnClick := @BtnReigniteClick;

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

  FPaintFlame := TPaintBox.Create(Self);
  FPaintFlame.Parent := Self;
  FPaintFlame.Align := alTop;
  FPaintFlame.Height := 210;
  FPaintFlame.OnPaint := @PaintFlameSpectrum;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TFlameFlickerForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TFlameFlickerForm.RefreshView;
var
  Rig: TCastleFlameFlickerRig;
begin
  Rig := TFlameFlickerHelper.FindFirstRig(FDesignRoot);
  if Rig <> nil then
    FLblSummary.Caption := Rig.Name + '  ' + Rig.FlameSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleFlameFlickerRig in scene — click "+ Spawn Wall Sconce + Soot".';
  FMemoReport.Lines.Text := TFlameFlickerHelper.GenerateMarkdownReport(Rig);
  FPaintFlame.Invalidate;
end;

procedure TFlameFlickerForm.BtnSpawnSconceClick(Sender: TObject);
var
  Rig: TCastleFlameFlickerRig;
begin
  if TFlameFlickerHelper.SpawnDungeonWallSconceDemo(FDesignRoot, FDesignOwner, Rig) then
    NotifyChanged('Spawn Dungeon Wall Torch Sconce');
end;

procedure TFlameFlickerForm.BtnStepDraftClick(Sender: TObject);
var
  Rig: TCastleFlameFlickerRig;
begin
  Rig := TFlameFlickerHelper.FindFirstRig(FDesignRoot);
  if Rig = nil then Exit;
  Rig.StepFlameCombustion(0.22, Vector3(4.0, 0.0, 0.0));
  Rig.ProbeWallAndCeilingSoot(ActiveWorldRoot);
  NotifyChanged('Step Torch Wind Draft');
end;

procedure TFlameFlickerForm.BtnGustBlowoutClick(Sender: TObject);
var
  Rig: TCastleFlameFlickerRig;
begin
  Rig := TFlameFlickerHelper.FindFirstRig(FDesignRoot);
  if Rig = nil then Exit;
  Rig.StepFlameCombustion(0.15, Vector3(14.0, 0.0, 0.0));
  NotifyChanged('Apply Dungeon Gale Blowout Gust');
end;

procedure TFlameFlickerForm.BtnReigniteClick(Sender: TObject);
var
  Rig: TCastleFlameFlickerRig;
begin
  Rig := TFlameFlickerHelper.FindFirstRig(FDesignRoot);
  if Rig = nil then Exit;
  Rig.ReigniteFlame;
  Rig.ProbeWallAndCeilingSoot(ActiveWorldRoot);
  NotifyChanged('Re-Ignite Torch Sconce');
end;

procedure TFlameFlickerForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TFlameFlickerForm.PaintFlameSpectrum(Sender: TObject);
var
  C: TCanvas;
  W, H, X, BX, BY, TipX, TipY: Integer;
  Rig: TCastleFlameFlickerRig;
  S: TFlameFlickerSample;
  RgbSpec: TVector3;
  Pts: array[0..2] of TPoint;
begin
  C := FPaintFlame.Canvas;
  W := FPaintFlame.Width;
  H := FPaintFlame.Height;
  C.Brush.Color := RGBToColor(20, 18, 24);
  C.FillRect(0, 0, W, H);

  { Draw Planckian 1500K .. 3500K spectrum strip on right }
  for X := 0 to 299 do
  begin
    RgbSpec := TCastleFlameFlickerRig.KelvinToBlackbodyRgb(1500.0 + X * (2000.0 / 300.0));
    C.Pen.Color := RGBToColor(
      Round(RgbSpec.X * 255), Round(RgbSpec.Y * 255), Round(RgbSpec.Z * 255));
    C.MoveTo(260 + X, 36);
    C.LineTo(260 + X, 76);
  end;

  Rig := TFlameFlickerHelper.FindFirstRig(FDesignRoot);
  if Rig = nil then Exit;
  S := Rig.LastSample;

  BX := 120;
  BY := H - 36;
  if Rig.IsLit then
  begin
    TipX := BX + Round(S.FlameTipLocalOffset.X * 220.0);
    TipY := BY - Round(S.FlameTipLocalOffset.Y * 260.0);
    Pts[0] := Point(BX - 24, BY);
    Pts[1] := Point(TipX, TipY);
    Pts[2] := Point(BX + 24, BY);
    C.Brush.Color := RGBToColor(
      Round(S.BlackbodyRgb.X * 255),
      Round(S.BlackbodyRgb.Y * 255),
      Round(S.BlackbodyRgb.Z * 255));
    C.Pen.Color := RGBToColor(255, 240, 180);
    C.Polygon(Pts);
  end else
  begin
    C.Brush.Color := RGBToColor(115, 118, 125);
    C.Ellipse(BX - 28, BY - 90, BX + 28, BY - 30);
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(260, 96, Format('Kelvin: %.0f K   |   Intensity: %.2fx   |   Lit: %s',
    [S.CurrentKelvin, S.IntensityMultiplier, BoolToStr(Rig.IsLit, True)]));
  C.TextOut(260, 128, Format('Wall Soot: %.0f%%   |   Ceiling Soot: %.0f%%   |   Surfaces: %d',
    [Rig.LastSoot.WallSootDarkening01 * 100.0,
     Rig.LastSoot.CeilingSootDarkening01 * 100.0,
     Rig.LastSoot.SootSurfaceCount]));
end;

end.
