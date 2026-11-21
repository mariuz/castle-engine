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

{ Visual Studio dialog for Procedural Rain Puddle, Roof Shelter, Specular
  Wetness & Splash Ripple Studio (Phase 407). }
unit FormPuddleWetness;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastlePuddleWetness, ToolPuddleWetness;

type
  TPuddleWetnessModifiedCallback = procedure(const UndoComment: String) of object;
  TPuddleWetnessRefreshCallback = procedure of object;

  TPuddleWetnessForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TPuddleWetnessModifiedCallback;
    FOnRefresh: TPuddleWetnessRefreshCallback;
    FLblSummary: TLabel;
    FPaintPuddles: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    procedure BtnSpawnStormClick(Sender: TObject);
    procedure BtnSplashClick(Sender: TObject);
    procedure BtnStepRipplesClick(Sender: TObject);
    procedure BtnSunDryClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintWetnessMap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TPuddleWetnessModifiedCallback;
      const AOnRefresh: TPuddleWetnessRefreshCallback);
  end;

implementation

constructor TPuddleWetnessForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TPuddleWetnessModifiedCallback;
  const AOnRefresh: TPuddleWetnessRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Rain Puddle, Roof Shelter & Splash Ripple Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TPuddleWetnessForm.ActiveWorldRoot: TCastleAbstractRootTransform;
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

procedure TPuddleWetnessForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnSplash, BtnStep, BtnDry, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 8, 180, 30);
  BtnSpawn.Caption := '+ Spawn Alley + Porch Roof';
  BtnSpawn.OnClick := @BtnSpawnStormClick;

  BtnSplash := TButton.Create(Self);
  BtnSplash.Parent := PnlButtons;
  BtnSplash.SetBounds(195, 8, 145, 30);
  BtnSplash.Caption := 'Footstep Splash (0,0)';
  BtnSplash.OnClick := @BtnSplashClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlButtons;
  BtnStep.SetBounds(345, 8, 140, 30);
  BtnStep.Caption := 'Step Ripples (+0.3s)';
  BtnStep.OnClick := @BtnStepRipplesClick;

  BtnDry := TButton.Create(Self);
  BtnDry.Parent := PnlButtons;
  BtnDry.SetBounds(490, 8, 135, 30);
  BtnDry.Caption := 'Sun Dry (-20%)';
  BtnDry.OnClick := @BtnSunDryClick;

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

  FPaintPuddles := TPaintBox.Create(Self);
  FPaintPuddles.Parent := Self;
  FPaintPuddles.Align := alTop;
  FPaintPuddles.Height := 215;
  FPaintPuddles.OnPaint := @PaintWetnessMap;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TPuddleWetnessForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TPuddleWetnessForm.RefreshView;
var
  F: TCastlePuddleWetnessField;
begin
  F := TPuddleWetnessHelper.FindFirstField(FDesignRoot);
  if F <> nil then
    FLblSummary.Caption := F.Name + '  ' + F.PuddleSummaryBadge
  else
    FLblSummary.Caption := 'No TCastlePuddleWetnessField in scene — click "+ Spawn Alley + Porch Roof".';
  FMemoReport.Lines.Text := TPuddleWetnessHelper.GenerateMarkdownReport(F);
  FPaintPuddles.Invalidate;
end;

procedure TPuddleWetnessForm.BtnSpawnStormClick(Sender: TObject);
var
  F: TCastlePuddleWetnessField;
begin
  if TPuddleWetnessHelper.SpawnCobblestonePorchStormDemo(FDesignRoot, FDesignOwner, F) then
    NotifyChanged('Spawn Cobblestone Storm Puddle Field');
end;

procedure TPuddleWetnessForm.BtnSplashClick(Sender: TObject);
var
  F: TCastlePuddleWetnessField;
begin
  F := TPuddleWetnessHelper.FindFirstField(FDesignRoot);
  if F = nil then Exit;
  F.TriggerSplashAtWorld(TVector3.Zero, 5.5, 2.0);
  NotifyChanged('Trigger Puddle Footstep Splash');
end;

procedure TPuddleWetnessForm.BtnStepRipplesClick(Sender: TObject);
var
  F: TCastlePuddleWetnessField;
begin
  F := TPuddleWetnessHelper.FindFirstField(FDesignRoot);
  if F = nil then Exit;
  F.StepRipplesAndEvaporation(0.30, 0.0);
  NotifyChanged('Step Puddle Splash Ripples');
end;

procedure TPuddleWetnessForm.BtnSunDryClick(Sender: TObject);
var
  F: TCastlePuddleWetnessField;
begin
  F := TPuddleWetnessHelper.FindFirstField(FDesignRoot);
  if F = nil then Exit;
  F.StepRipplesAndEvaporation(1.0, 0.20);
  NotifyChanged('Evaporate Rain Puddles');
end;

procedure TPuddleWetnessForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TPuddleWetnessForm.PaintWetnessMap(Sender: TObject);
var
  C: TCanvas;
  W, H, GX, GZ, CellW, CellH: Integer;
  F: TCastlePuddleWetnessField;
  WR: TCastleAbstractRootTransform;
  Smp: TPuddleSurfaceSample;
  WX, WZ: Single;
begin
  C := FPaintPuddles.Canvas;
  W := FPaintPuddles.Width;
  H := FPaintPuddles.Height;
  C.Brush.Color := RGBToColor(18, 20, 26);
  C.FillRect(0, 0, W, H);

  F := TPuddleWetnessHelper.FindFirstField(FDesignRoot);
  if F = nil then Exit;
  WR := ActiveWorldRoot;

  CellW := Max(4, (W - 40) div 28);
  CellH := Max(4, (H - 44) div 16);
  for GX := 0 to 27 do
    for GZ := 0 to 15 do
    begin
      WX := -8.5 + GX * (17.0 / 27.0);
      WZ := -5.5 + GZ * (11.0 / 15.0);
      Smp := F.SampleSurfaceWetnessAtWorld(WR, Vector3(WX, 0.0, WZ));
      if Smp.RoofSheltered then
        C.Brush.Color := RGBToColor(145, 125, 95)
      else if Smp.StandingWaterDepthMeters > 0.002 then
        C.Brush.Color := RGBToColor(45, 145, 235)
      else
        C.Brush.Color := RGBToColor(62, 72, 86);
      C.FillRect(20 + GX * CellW, 12 + GZ * CellH,
                 20 + (GX + 1) * CellW - 1, 12 + (GZ + 1) * CellH - 1);
    end;

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(20, H - 24, 'Blue = Mirror Puddle | Slate = Damp Cobble | Tan = Dry Under Porch Roof');
end;

end.
