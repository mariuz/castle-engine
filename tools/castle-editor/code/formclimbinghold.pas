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

{ Visual Studio dialog for Procedural Free-Climbing Hold Scanner
  (WorldRay Ledge/Crack Graph, Limb Reach & Overhang Stamina) Studio (Phase 410). }
unit FormClimbingHold;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleClimbingHold, ToolClimbingHold;

type
  TClimbingHoldModifiedCallback = procedure(const UndoComment: String) of object;
  TClimbingHoldRefreshCallback = procedure of object;

  TClimbingHoldForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TClimbingHoldModifiedCallback;
    FOnRefresh: TClimbingHoldRefreshCallback;
    FLblSummary: TLabel;
    FPaintWall: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnRescanClick(Sender: TObject);
    procedure BtnAssassinPresetClick(Sender: TObject);
    procedure BtnArmoredPresetClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintClimbGraph(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TClimbingHoldModifiedCallback;
      const AOnRefresh: TClimbingHoldRefreshCallback);
  end;

implementation

constructor TClimbingHoldForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TClimbingHoldModifiedCallback;
  const AOnRefresh: TClimbingHoldRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Free-Climbing Hold Scanner, Reach Graph & Overhang Stamina Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TClimbingHoldForm.ActiveWorldRoot: TCastleAbstractRootTransform;
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

procedure TClimbingHoldForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnScan, BtnAssn, BtnArmor, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Tower + Ledges';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnScan := TButton.Create(Self);
  BtnScan.Parent := PnlButtons;
  BtnScan.SetBounds(190, 8, 145, 30);
  BtnScan.Caption := 'Rescan WorldRay Lips';
  BtnScan.OnClick := @BtnRescanClick;

  BtnAssn := TButton.Create(Self);
  BtnAssn.Parent := PnlButtons;
  BtnAssn.SetBounds(340, 8, 145, 30);
  BtnAssn.Caption := 'Assassin Speed Scaler';
  BtnAssn.OnClick := @BtnAssassinPresetClick;

  BtnArmor := TButton.Create(Self);
  BtnArmor.Parent := PnlButtons;
  BtnArmor.SetBounds(490, 8, 135, 30);
  BtnArmor.Caption := 'Heavy Mountaineer';
  BtnArmor.OnClick := @BtnArmoredPresetClick;

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

  FPaintWall := TPaintBox.Create(Self);
  FPaintWall.Parent := Self;
  FPaintWall.Align := alTop;
  FPaintWall.Height := 215;
  FPaintWall.OnPaint := @PaintClimbGraph;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TClimbingHoldForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TClimbingHoldForm.RefreshView;
var
  S: TCastleClimbingHoldScanner;
begin
  S := TClimbingHoldHelper.FindFirstScanner(FDesignRoot);
  if S <> nil then
    FLblSummary.Caption := S.Name + '  ' + S.ClimbSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleClimbingHoldScanner in scene — click "+ Spawn Tower + Ledges".';
  FMemoReport.Lines.Text := TClimbingHoldHelper.GenerateMarkdownReport(S);
  FPaintWall.Invalidate;
end;

procedure TClimbingHoldForm.BtnSpawnDemoClick(Sender: TObject);
var
  S: TCastleClimbingHoldScanner;
begin
  if TClimbingHoldHelper.SpawnTowerClimbDynoRouteDemo(FDesignRoot, FDesignOwner, S) then
    NotifyChanged('Spawn Free-Climbing Tower Route Demo');
end;

procedure TClimbingHoldForm.BtnRescanClick(Sender: TObject);
var
  S: TCastleClimbingHoldScanner;
begin
  S := TClimbingHoldHelper.FindFirstScanner(FDesignRoot);
  if S = nil then Exit;
  S.ScanCliffLedgeHolds(ActiveWorldRoot);
  NotifyChanged('Rescan Cliff Handholds');
end;

procedure TClimbingHoldForm.BtnAssassinPresetClick(Sender: TObject);
var
  S: TCastleClimbingHoldScanner;
begin
  S := TClimbingHoldHelper.FindFirstScanner(FDesignRoot);
  if S = nil then Exit;
  S.ApplyPreset(chpAssassinSpeedScaler);
  NotifyChanged('Switch to Assassin Speed Scaler');
end;

procedure TClimbingHoldForm.BtnArmoredPresetClick(Sender: TObject);
var
  S: TCastleClimbingHoldScanner;
begin
  S := TClimbingHoldHelper.FindFirstScanner(FDesignRoot);
  if S = nil then Exit;
  S.ApplyPreset(chpHeavyArmoredMountaineer);
  NotifyChanged('Switch to Heavy Armored Mountaineer');
end;

procedure TClimbingHoldForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TClimbingHoldForm.PaintClimbGraph(Sender: TObject);
var
  C: TCanvas;
  W, H, I, J, X1, Y1, X2, Y2: Integer;
  S: TCastleClimbingHoldScanner;
  H1, H2: TClimbingHoldNode;
  D: Single;
begin
  C := FPaintWall.Canvas;
  W := FPaintWall.Width;
  H := FPaintWall.Height;
  C.Brush.Color := RGBToColor(24, 26, 32);
  C.FillRect(0, 0, W, H);

  S := TClimbingHoldHelper.FindFirstScanner(FDesignRoot);
  if S = nil then Exit;

  for I := 0 to S.HoldCount - 2 do
    for J := I + 1 to S.HoldCount - 1 do
    begin
      H1 := S.GetHold(I);
      H2 := S.GetHold(J);
      D := PointsDistance(H1.WorldGripPos, H2.WorldGripPos);
      if D <= S.MaxDynoLeapReachMeters then
      begin
        X1 := (W div 2) + Round(H1.WorldGripPos.X * 65.0);
        Y1 := H - 24 - Round(H1.WorldGripPos.Y * 26.0);
        X2 := (W div 2) + Round(H2.WorldGripPos.X * 65.0);
        Y2 := H - 24 - Round(H2.WorldGripPos.Y * 26.0);
        if D <= S.MaxStaticLimbReachMeters then
          C.Pen.Color := RGBToColor(70, 225, 130)
        else
          C.Pen.Color := RGBToColor(245, 185, 55);
        C.MoveTo(X1, Y1);
        C.LineTo(X2, Y2);
      end;
    end;

  for I := 0 to S.HoldCount - 1 do
  begin
    H1 := S.GetHold(I);
    X1 := (W div 2) + Round(H1.WorldGripPos.X * 65.0);
    Y1 := H - 24 - Round(H1.WorldGripPos.Y * 26.0);
    C.Brush.Color := RGBToColor(240, 210, 120);
    C.Ellipse(X1 - 6, Y1 - 6, X1 + 6, Y1 + 6);
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(16, 12, 'Green = Static Arm Reach | Gold = Dyno Leap Edge | East Face = Smooth Sheer (0 Holds)');
end;

end.
