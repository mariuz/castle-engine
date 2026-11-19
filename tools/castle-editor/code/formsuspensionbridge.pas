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

{ Visual Studio dialog for Procedural Rope Suspension Bridge, Live-Load Plank
  Deflection, Roll Tilt & Broken-Slat Hazard Studio (Phase 389). }
unit FormSuspensionBridge;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleSuspensionBridge, ToolSuspensionBridge;

type
  TSuspensionBridgeModifiedCallback = procedure(const UndoComment: String) of object;
  TSuspensionBridgeRefreshCallback = procedure of object;

  TSuspensionBridgeForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSuspensionBridgeModifiedCallback;
    FOnRefresh: TSuspensionBridgeRefreshCallback;
    FLblSummary: TLabel;
    FPaintSpan: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnSpanClick(Sender: TObject);
    procedure BtnStepHeavyKnightClick(Sender: TObject);
    procedure BtnRottedTrapClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintBridgeProfile(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSuspensionBridgeModifiedCallback;
      const AOnRefresh: TSuspensionBridgeRefreshCallback);
  end;

implementation

constructor TSuspensionBridgeForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSuspensionBridgeModifiedCallback;
  const AOnRefresh: TSuspensionBridgeRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Rope Suspension Bridge & Live-Load Deflection Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TSuspensionBridgeForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnLoad, BtnTrap, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Jungle Chasm Span';
  BtnSpawn.OnClick := @BtnSpawnSpanClick;

  BtnLoad := TButton.Create(Self);
  BtnLoad.Parent := PnlButtons;
  BtnLoad.SetBounds(201, 8, 195, 30);
  BtnLoad.Caption := 'Apply 260kg Off-Center Troll';
  BtnLoad.OnClick := @BtnStepHeavyKnightClick;

  BtnTrap := TButton.Create(Self);
  BtnTrap.Parent := PnlButtons;
  BtnTrap.SetBounds(402, 8, 195, 30);
  BtnTrap.Caption := 'Preset: Rotted Chasm Trap';
  BtnTrap.OnClick := @BtnRottedTrapClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintSpan := TPaintBox.Create(Self);
  FPaintSpan.Parent := Self;
  FPaintSpan.Align := alTop;
  FPaintSpan.Height := 200;
  FPaintSpan.OnPaint := @PaintBridgeProfile;

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

procedure TSuspensionBridgeForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TSuspensionBridgeForm.RefreshView;
var
  B: TCastleSuspensionBridge;
begin
  B := TSuspensionBridgeHelper.FindFirstBridge(FDesignRoot);
  if B = nil then
    FLblSummary.Caption := 'No TCastleSuspensionBridge in scene. Click "+ Spawn Jungle Chasm Span".'
  else
    FLblSummary.Caption := B.BridgeSummaryBadge;
  FMemoReport.Lines.Text := TSuspensionBridgeHelper.GenerateMarkdownReport(B);
  FPaintSpan.Invalidate;
end;

procedure TSuspensionBridgeForm.BtnSpawnSpanClick(Sender: TObject);
var
  B: TCastleSuspensionBridge;
begin
  if TSuspensionBridgeHelper.SpawnChasmBridgeDemo(FDesignRoot, FDesignOwner, B) then
    NotifyChanged('Spawn Jungle Chasm Suspension Bridge');
end;

procedure TSuspensionBridgeForm.BtnStepHeavyKnightClick(Sender: TObject);
var
  B: TCastleSuspensionBridge;
begin
  B := TSuspensionBridgeHelper.FindFirstBridge(FDesignRoot);
  if B = nil then Exit;
  B.ApplyWalkerLoad(0.38, 0.65, 260.0);
  NotifyChanged('Apply 260kg Off-Center Live Load on Bridge');
end;

procedure TSuspensionBridgeForm.BtnRottedTrapClick(Sender: TObject);
var
  B: TCastleSuspensionBridge;
begin
  B := TSuspensionBridgeHelper.FindFirstBridge(FDesignRoot);
  if B = nil then Exit;
  B.ApplyPreset(sbpRottedChasmTrapBridge);
  NotifyChanged('Switch to Rotted Chasm Trap Bridge');
end;

procedure TSuspensionBridgeForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TSuspensionBridgeForm.PaintBridgeProfile(Sender: TObject);
var
  C: TCanvas;
  B: TCastleSuspensionBridge;
  P: TBridgePlankState;
  W, H, I, PX, PY: Integer;
  ScaleY: Single;
begin
  C := FPaintSpan.Canvas;
  W := Max(10, FPaintSpan.Width);
  H := Max(10, FPaintSpan.Height);
  C.Brush.Color := RGBToColor(20, 24, 30);
  C.FillRect(0, 0, W, H);

  B := TSuspensionBridgeHelper.FindFirstBridge(FDesignRoot);
  if (B = nil) or (B.PlankStateCount < 2) then
  begin
    C.Font.Color := RGBToColor(185, 200, 220);
    C.TextOut(14, H div 2 - 8, 'Suspension Deck Sag & Broken-Plank Canvas');
    Exit;
  end;

  ScaleY := (H - 54) / Max(1.5, B.MaxTotalDropMeters + 0.5);
  for I := 0 to B.PlankStateCount - 1 do
  begin
    P := B.GetPlankState(I);
    PX := 20 + Round(P.NormalizedT * (W - 40));
    PY := 28 + Round(-(P.RestSagY + P.LiveLoadDropY) * ScaleY);
    if P.IsBrokenGap then
    begin
      C.Brush.Color := RGBToColor(225, 65, 65);
      C.Ellipse(PX - 3, PY - 3, PX + 3, PY + 3);
    end else
    begin
      C.Brush.Color := RGBToColor(215, 165, 92);
      C.FillRect(PX - 4, PY - 3, PX + 4, PY + 3);
    end;
  end;
end;

end.
