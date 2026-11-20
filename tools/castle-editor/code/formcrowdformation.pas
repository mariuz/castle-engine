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

{ Visual Studio dialog for Tactical Squad & Crowd Formation Controller
  (Wedge, Phalanx, Shield-Circle, Column & WorldRay Obstacle Split) Studio (Phase 405). }
unit FormCrowdFormation;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleCrowdFormation, ToolCrowdFormation;

type
  TCrowdFormationModifiedCallback = procedure(const UndoComment: String) of object;
  TCrowdFormationRefreshCallback = procedure of object;

  TCrowdFormationForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TCrowdFormationModifiedCallback;
    FOnRefresh: TCrowdFormationRefreshCallback;
    FLblSummary: TLabel;
    FPaintSlots: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnWedgeClick(Sender: TObject);
    procedure BtnPhalanxClick(Sender: TObject);
    procedure BtnShieldCircleClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintSquadRadar(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TCrowdFormationModifiedCallback;
      const AOnRefresh: TCrowdFormationRefreshCallback);
  end;

implementation

constructor TCrowdFormationForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TCrowdFormationModifiedCallback;
  const AOnRefresh: TCrowdFormationRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Tactical Squad Formation (Wedge, Phalanx, Shield-Circle) Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TCrowdFormationForm.ActiveWorldRoot: TCastleAbstractRootTransform;
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

procedure TCrowdFormationForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnWedge, BtnPhalanx, BtnCircle, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 8, 185, 30);
  BtnSpawn.Caption := '+ Spawn Squad + Boulder Pass';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnWedge := TButton.Create(Self);
  BtnWedge.Parent := PnlButtons;
  BtnWedge.SetBounds(200, 8, 135, 30);
  BtnWedge.Caption := 'Cavalry V-Wedge';
  BtnWedge.OnClick := @BtnWedgeClick;

  BtnPhalanx := TButton.Create(Self);
  BtnPhalanx.Parent := PnlButtons;
  BtnPhalanx.SetBounds(340, 8, 135, 30);
  BtnPhalanx.Caption := 'Hoplite Phalanx';
  BtnPhalanx.OnClick := @BtnPhalanxClick;

  BtnCircle := TButton.Create(Self);
  BtnCircle.Parent := PnlButtons;
  BtnCircle.SetBounds(480, 8, 145, 30);
  BtnCircle.Caption := 'VIP Shield-Circle';
  BtnCircle.OnClick := @BtnShieldCircleClick;

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

  FPaintSlots := TPaintBox.Create(Self);
  FPaintSlots.Parent := Self;
  FPaintSlots.Align := alTop;
  FPaintSlots.Height := 220;
  FPaintSlots.OnPaint := @PaintSquadRadar;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TCrowdFormationForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TCrowdFormationForm.RefreshView;
var
  F: TCastleCrowdFormation;
begin
  F := TCrowdFormationHelper.FindFirstFormation(FDesignRoot);
  if F <> nil then
    FLblSummary.Caption := F.Name + '  ' + F.FormationSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleCrowdFormation in scene — click "+ Spawn Squad + Boulder Pass".';
  FMemoReport.Lines.Text := TCrowdFormationHelper.GenerateMarkdownReport(F);
  FPaintSlots.Invalidate;
end;

procedure TCrowdFormationForm.BtnSpawnDemoClick(Sender: TObject);
var
  F: TCastleCrowdFormation;
begin
  if TCrowdFormationHelper.SpawnSquadPassWithBoulderDemo(FDesignRoot, FDesignOwner, F) then
    NotifyChanged('Spawn Squad Pass & Boulder Split Demo');
end;

procedure TCrowdFormationForm.BtnWedgeClick(Sender: TObject);
var
  F: TCastleCrowdFormation;
begin
  F := TCrowdFormationHelper.FindFirstFormation(FDesignRoot);
  if F = nil then Exit;
  F.FormationShape := sfsCavalryVWedge;
  F.SolveFormationSlots(ActiveWorldRoot);
  NotifyChanged('Switch Squad to Cavalry V-Wedge');
end;

procedure TCrowdFormationForm.BtnPhalanxClick(Sender: TObject);
var
  F: TCastleCrowdFormation;
begin
  F := TCrowdFormationHelper.FindFirstFormation(FDesignRoot);
  if F = nil then Exit;
  F.FormationShape := sfsHoplitesPhalanxGrid;
  F.SolveFormationSlots(ActiveWorldRoot);
  NotifyChanged('Switch Squad to Hoplite Phalanx');
end;

procedure TCrowdFormationForm.BtnShieldCircleClick(Sender: TObject);
var
  F: TCastleCrowdFormation;
begin
  F := TCrowdFormationHelper.FindFirstFormation(FDesignRoot);
  if F = nil then Exit;
  F.FormationShape := sfsVipOutwardShieldCircle;
  F.SolveFormationSlots(ActiveWorldRoot);
  NotifyChanged('Switch Squad to Outward VIP Shield-Circle');
end;

procedure TCrowdFormationForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TCrowdFormationForm.PaintSquadRadar(Sender: TObject);
var
  C: TCanvas;
  W, H, CX, CY, I, SX, SY, FX, FY: Integer;
  F: TCastleCrowdFormation;
  Slot: TSquadFormationSlot;
  ScalePx: Single;
begin
  C := FPaintSlots.Canvas;
  W := FPaintSlots.Width;
  H := FPaintSlots.Height;
  C.Brush.Color := RGBToColor(18, 24, 22);
  C.FillRect(0, 0, W, H);

  F := TCrowdFormationHelper.FindFirstFormation(FDesignRoot);
  if F = nil then Exit;

  CX := W div 2;
  CY := 52;
  ScalePx := 14.0;

  for I := 0 to F.SlotCount - 1 do
  begin
    Slot := F.GetSlot(I);
    SX := CX + Round(Slot.WorldPosition.X * ScalePx);
    SY := CY + Round(Slot.WorldPosition.Z * ScalePx);
    FX := SX + Round(Slot.WorldForward.X * 12.0);
    FY := SY + Round(Slot.WorldForward.Z * 12.0);

    C.Pen.Color := RGBToColor(220, 235, 250);
    C.MoveTo(SX, SY);
    C.LineTo(FX, FY);

    if I = 0 then
      C.Brush.Color := RGBToColor(245, 200, 55)
    else if Slot.ObstacleDeflected then
      C.Brush.Color := RGBToColor(240, 110, 65)
    else
      C.Brush.Color := RGBToColor(65, 205, 145);
    C.Ellipse(SX - 6, SY - 6, SX + 6, SY + 6);
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(14, H - 26, Format('%s | %d Units | %d Snapped | %d Boulder-Split Slots (orange)',
    [SquadFormationShapeToString(F.FormationShape), F.SlotCount,
     F.GroundSnappedSlotCount, F.ObstacleAvoidedSlotCount]));
end;

end.
