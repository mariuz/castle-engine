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

{ Visual Studio dialog for Multi-Bounce Optical Laser, Mirror Reflection,
  Snell Prism Refraction & Beam-Break Cutoff Studio (Phase 411). }
unit FormLaserBeam;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleLaserBeam, ToolLaserBeam;

type
  TLaserBeamModifiedCallback = procedure(const UndoComment: String) of object;
  TLaserBeamRefreshCallback = procedure of object;

  TLaserBeamForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TLaserBeamModifiedCallback;
    FOnRefresh: TLaserBeamRefreshCallback;
    FLblSummary: TLabel;
    FPaintOptics: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    function FindCrateBlocker: TCastleTransform;
    procedure BtnSpawnPuzzleClick(Sender: TObject);
    procedure BtnSlideCrateInClick(Sender: TObject);
    procedure BtnClearCrateClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintLaserTopDown(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TLaserBeamModifiedCallback;
      const AOnRefresh: TLaserBeamRefreshCallback);
  end;

implementation

constructor TLaserBeamForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TLaserBeamModifiedCallback;
  const AOnRefresh: TLaserBeamRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Multi-Bounce Optical Laser, Mirror/Prism & Cutoff Gate Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TLaserBeamForm.ActiveWorldRoot: TCastleAbstractRootTransform;
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

function TLaserBeamForm.FindCrateBlocker: TCastleTransform;
var
  WR: TCastleAbstractRootTransform;
  I: Integer;
begin
  Result := nil;
  WR := ActiveWorldRoot;
  if WR = nil then Exit;
  for I := 0 to WR.Count - 1 do
    if WR[I].Name = 'Crate_BeamBlocker' then
      Exit(WR[I]);
end;

procedure TLaserBeamForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnBlock, BtnClear, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 8, 195, 30);
  BtnSpawn.Caption := '+ Spawn 2-Mirror Laser Puzzle';
  BtnSpawn.OnClick := @BtnSpawnPuzzleClick;

  BtnBlock := TButton.Create(Self);
  BtnBlock.Parent := PnlButtons;
  BtnBlock.SetBounds(210, 8, 175, 30);
  BtnBlock.Caption := 'Slide Crate Into Beam';
  BtnBlock.OnClick := @BtnSlideCrateInClick;

  BtnClear := TButton.Create(Self);
  BtnClear.Parent := PnlButtons;
  BtnClear.SetBounds(390, 8, 175, 30);
  BtnClear.Caption := 'Clear Crate (Power Goal)';
  BtnClear.OnClick := @BtnClearCrateClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(570, 8, 95, 30);
  BtnCopy.Caption := 'Copy Report';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlButtons;
  BtnClose.SetBounds(670, 8, 80, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;
  BtnClose.OnClick := nil;

  FPaintOptics := TPaintBox.Create(Self);
  FPaintOptics.Parent := Self;
  FPaintOptics.Align := alTop;
  FPaintOptics.Height := 215;
  FPaintOptics.OnPaint := @PaintLaserTopDown;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TLaserBeamForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TLaserBeamForm.RefreshView;
var
  L: TCastleLaserBeamRig;
begin
  L := TLaserBeamHelper.FindFirstLaser(FDesignRoot);
  if L <> nil then
    FLblSummary.Caption := L.Name + '  ' + L.LaserSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleLaserBeamRig in scene — click "+ Spawn 2-Mirror Laser Puzzle".';
  FMemoReport.Lines.Text := TLaserBeamHelper.GenerateMarkdownReport(L);
  FPaintOptics.Invalidate;
end;

procedure TLaserBeamForm.BtnSpawnPuzzleClick(Sender: TObject);
var
  L: TCastleLaserBeamRig;
begin
  if TLaserBeamHelper.SpawnTwoMirrorReceiverPuzzleDemo(FDesignRoot, FDesignOwner, L) then
    NotifyChanged('Spawn 2-Mirror Optical Laser Puzzle');
end;

procedure TLaserBeamForm.BtnSlideCrateInClick(Sender: TObject);
var
  L: TCastleLaserBeamRig;
  Crate: TCastleTransform;
begin
  L := TLaserBeamHelper.FindFirstLaser(FDesignRoot);
  Crate := FindCrateBlocker;
  if (L = nil) or (Crate = nil) then Exit;
  Crate.Translation := Vector3(3.0, 1.5, -5.0);
  L.TraceLaserBeam(ActiveWorldRoot);
  NotifyChanged('Block Optical Laser Beam With Crate');
end;

procedure TLaserBeamForm.BtnClearCrateClick(Sender: TObject);
var
  L: TCastleLaserBeamRig;
  Crate: TCastleTransform;
begin
  L := TLaserBeamHelper.FindFirstLaser(FDesignRoot);
  Crate := FindCrateBlocker;
  if (L = nil) or (Crate = nil) then Exit;
  Crate.Translation := Vector3(3.0, 1.5, -8.0);
  L.TraceLaserBeam(ActiveWorldRoot);
  NotifyChanged('Clear Crate To Restore Receiver Power');
end;

procedure TLaserBeamForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TLaserBeamForm.PaintLaserTopDown(Sender: TObject);
var
  C: TCanvas;
  W, H, I, OX, OY, X1, Y1, X2, Y2: Integer;
  L: TCastleLaserBeamRig;
  Seg: TLaserBeamSegment;
begin
  C := FPaintOptics.Canvas;
  W := FPaintOptics.Width;
  H := FPaintOptics.Height;
  C.Brush.Color := RGBToColor(16, 18, 26);
  C.FillRect(0, 0, W, H);

  L := TLaserBeamHelper.FindFirstLaser(FDesignRoot);
  if L = nil then Exit;

  OX := 220;
  OY := H - 42;
  if L.ReceiverPowered then
    C.Pen.Color := RGBToColor(65, 245, 130)
  else
    C.Pen.Color := RGBToColor(255, 70, 85);
  C.Pen.Width := 3;

  for I := 0 to L.SegmentCount - 1 do
  begin
    Seg := L.GetSegment(I);
    X1 := OX + Round(Seg.StartWorld.X * 42.0);
    Y1 := OY + Round(Seg.StartWorld.Z * 26.0);
    X2 := OX + Round(Seg.EndWorld.X * 42.0);
    Y2 := OY + Round(Seg.EndWorld.Z * 26.0);
    C.MoveTo(X1, Y1);
    C.LineTo(X2, Y2);
  end;
  C.Pen.Width := 1;

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(16, 12, Format('Segments: %d   |   Receiver Powered: %s (%s)',
    [L.SegmentCount, BoolToStr(L.ReceiverPowered, True), L.LastHitObjectName]));
end;

end.
