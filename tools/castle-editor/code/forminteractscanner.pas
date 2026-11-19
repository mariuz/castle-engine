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

{ Visual Studio dialog for Gameplay Interaction Focus Scanner (WorldRay Gaze +
  Proximity Cone, Hold-Progress Ring & Obstruction Gate) Studio (Phase 394). }
unit FormInteractScanner;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleInteractScanner, ToolInteractScanner;

type
  TInteractScannerModifiedCallback = procedure(const UndoComment: String) of object;
  TInteractScannerRefreshCallback = procedure of object;

  TInteractScannerForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TInteractScannerModifiedCallback;
    FOnRefresh: TInteractScannerRefreshCallback;
    FLblSummary: TLabel;
    FPaintHoldRing: TPaintBox;
    FMemoReport: TMemo;
    function FindViewport: TCastleViewport;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnVaultClick(Sender: TObject);
    procedure BtnHoldStepClick(Sender: TObject);
    procedure BtnReleaseDecayClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintHoldRing(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TInteractScannerModifiedCallback;
      const AOnRefresh: TInteractScannerRefreshCallback);
  end;

implementation

constructor TInteractScannerForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TInteractScannerModifiedCallback;
  const AOnRefresh: TInteractScannerRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Gameplay Interaction Focus Scanner & Hold-Progress Ring Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TInteractScannerForm.FindViewport: TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if FDesignRoot = nil then Exit;
  if FDesignRoot is TCastleViewport then Exit(TCastleViewport(FDesignRoot));
  for I := 0 to FDesignRoot.ComponentCount - 1 do
    if FDesignRoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(FDesignRoot.Components[I]));
end;

procedure TInteractScannerForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnHold, BtnRelease, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 8, 190, 30);
  BtnSpawn.Caption := '+ Spawn Vault Interact Room';
  BtnSpawn.OnClick := @BtnSpawnVaultClick;

  BtnHold := TButton.Create(Self);
  BtnHold.Parent := PnlButtons;
  BtnHold.SetBounds(206, 8, 195, 30);
  BtnHold.Caption := 'Hold [F] Sabotage (+0.45s)';
  BtnHold.OnClick := @BtnHoldStepClick;

  BtnRelease := TButton.Create(Self);
  BtnRelease.Parent := PnlButtons;
  BtnRelease.SetBounds(407, 8, 190, 30);
  BtnRelease.Caption := 'Release Early (-0.30s Decay)';
  BtnRelease.OnClick := @BtnReleaseDecayClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintHoldRing := TPaintBox.Create(Self);
  FPaintHoldRing.Parent := Self;
  FPaintHoldRing.Align := alTop;
  FPaintHoldRing.Height := 200;
  FPaintHoldRing.OnPaint := @PaintHoldRing;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := Self;
  BtnClose.Align := alBottom;
  BtnClose.Height := 34;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;
end;

procedure TInteractScannerForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TInteractScannerForm.RefreshView;
var
  S: TCastleInteractScanner;
begin
  S := TInteractScannerHelper.FindFirstScanner(FDesignRoot);
  if S = nil then
    FLblSummary.Caption := 'No TCastleInteractScanner in scene. Click "+ Spawn Vault Interact Room".'
  else
    FLblSummary.Caption := S.InteractSummaryBadge;
  FMemoReport.Lines.Text := TInteractScannerHelper.GenerateMarkdownReport(S);
  FPaintHoldRing.Invalidate;
end;

procedure TInteractScannerForm.BtnSpawnVaultClick(Sender: TObject);
var
  S: TCastleInteractScanner;
begin
  if TInteractScannerHelper.SpawnVaultRoomInteractDemo(FDesignRoot, FDesignOwner, S) then
    NotifyChanged('Spawn Vault Interaction Focus Room');
end;

procedure TInteractScannerForm.BtnHoldStepClick(Sender: TObject);
var
  S: TCastleInteractScanner;
  VP: TCastleViewport;
  TrigName: String;
begin
  S := TInteractScannerHelper.FindFirstScanner(FDesignRoot);
  VP := FindViewport;
  if (S = nil) or (VP = nil) then Exit;
  S.StepHoldInteraction(VP.Items, True, 0.45, TrigName);
  RefreshView;
end;

procedure TInteractScannerForm.BtnReleaseDecayClick(Sender: TObject);
var
  S: TCastleInteractScanner;
  VP: TCastleViewport;
  TrigName: String;
begin
  S := TInteractScannerHelper.FindFirstScanner(FDesignRoot);
  VP := FindViewport;
  if (S = nil) or (VP = nil) then Exit;
  S.StepHoldInteraction(VP.Items, False, 0.30, TrigName);
  RefreshView;
end;

procedure TInteractScannerForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TInteractScannerForm.PaintHoldRing(Sender: TObject);
var
  C: TCanvas;
  S: TCastleInteractScanner;
  W, H, BarW: Integer;
begin
  C := FPaintHoldRing.Canvas;
  W := Max(20, FPaintHoldRing.Width);
  H := Max(20, FPaintHoldRing.Height);
  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  S := TInteractScannerHelper.FindFirstScanner(FDesignRoot);
  if S = nil then Exit;

  C.Brush.Color := RGBToColor(38, 48, 62);
  C.FillRect(40, H div 2 - 16, W - 40, H div 2 + 16);
  BarW := Round(S.HoldProgress01 * (W - 80));
  C.Brush.Color := RGBToColor(70, 235, 155);
  C.FillRect(40, H div 2 - 16, 40 + BarW, H div 2 + 16);
  C.Font.Color := RGBToColor(235, 245, 255);
  C.Brush.Style := bsClear;
  C.TextOut(40, H div 2 - 42, 'Focus: ' + S.FocusedTargetName +
    FormatDot('  (Hold %.0f%%)', [S.HoldProgress01 * 100.0]));
end;

end.
