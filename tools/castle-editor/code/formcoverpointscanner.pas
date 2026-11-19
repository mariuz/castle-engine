{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Visual Studio dialog for Tactical Cover Point Scanner, Crouch-Peek / Corner-Lean
  & Threat Exposure Studio (Phase 384). }
unit FormCoverPointScanner;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleCoverPointScanner, ToolCoverPointScanner;

type
  TCoverPointScannerModifiedCallback = procedure(const UndoComment: String) of object;
  TCoverPointScannerRefreshCallback = procedure of object;

  TCoverPointScannerForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TCoverPointScannerModifiedCallback;
    FOnRefresh: TCoverPointScannerRefreshCallback;
    FLblSummary: TLabel;
    FPaintRadar: TPaintBox;
    FMemoReport: TMemo;
    function FindViewportRoot: TCastleViewport;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnArenaClick(Sender: TObject);
    procedure BtnSingleSniperClick(Sender: TObject);
    procedure BtnDualFlankersClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintCoverRadar(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TCoverPointScannerModifiedCallback;
      const AOnRefresh: TCoverPointScannerRefreshCallback);
  end;

implementation

constructor TCoverPointScannerForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TCoverPointScannerModifiedCallback;
  const AOnRefresh: TCoverPointScannerRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Tactical Cover Point Scanner, Crouch-Peek & Threat Flanking Studio';
  Width := 840;
  Height := 580;
  Position := poMainFormCenter;
  BuildUi;
  RefreshView;
end;

function TCoverPointScannerForm.FindViewportRoot: TCastleViewport;
var
  I: Integer;
begin
  if FDesignRoot = nil then Exit(nil);
  if FDesignRoot is TCastleViewport then Exit(TCastleViewport(FDesignRoot));
  for I := 0 to FDesignRoot.ComponentCount - 1 do
    if FDesignRoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(FDesignRoot.Components[I]));
  Result := nil;
end;

procedure TCoverPointScannerForm.BuildUi;
var
  TopBar, BtnRow: TPanel;
  BtnSpawn, BtnNorth, BtnFlank, BtnCopy, BtnClose: TButton;
begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 40;
  TopBar.BevelOuter := bvNone;

  FLblSummary := TLabel.Create(Self);
  FLblSummary.Parent := TopBar;
  FLblSummary.Left := 12;
  FLblSummary.Top := 11;
  FLblSummary.Font.Style := [fsBold];

  BtnRow := TPanel.Create(Self);
  BtnRow.Parent := Self;
  BtnRow.Align := alTop;
  BtnRow.Height := 44;
  BtnRow.BevelOuter := bvNone;

  BtnSpawn := TButton.Create(Self);
  BtnSpawn.Parent := BtnRow;
  BtnSpawn.SetBounds(10, 6, 210, 30);
  BtnSpawn.Caption := '+ Spawn Killhouse & Bake Cover';
  BtnSpawn.OnClick := @BtnSpawnArenaClick;

  BtnNorth := TButton.Create(Self);
  BtnNorth.Parent := BtnRow;
  BtnNorth.SetBounds(228, 6, 190, 30);
  BtnNorth.Caption := 'Test North Sniper (0, 0, -14)';
  BtnNorth.OnClick := @BtnSingleSniperClick;

  BtnFlank := TButton.Create(Self);
  BtnFlank.Parent := BtnRow;
  BtnFlank.SetBounds(426, 6, 200, 30);
  BtnFlank.Caption := 'Test North + East Crossfire';
  BtnFlank.OnClick := @BtnDualFlankersClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := BtnRow;
  BtnCopy.SetBounds(634, 6, 110, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := BtnRow;
  BtnClose.SetBounds(752, 6, 74, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;

  FPaintRadar := TPaintBox.Create(Self);
  FPaintRadar.Parent := Self;
  FPaintRadar.Align := alTop;
  FPaintRadar.Height := 250;
  FPaintRadar.OnPaint := @PaintCoverRadar;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TCoverPointScannerForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TCoverPointScannerForm.RefreshView;
var
  Sum: TCoverScannerStudioSummary;
begin
  Sum := TCoverPointScannerHelper.CollectSummary(FDesignRoot);
  FLblSummary.Caption := Format(
    'Cover Points: %d  |  Waist Peek: %d  |  Full Corner-Lean: %d  |  Safe Against Threats: %d',
    [Sum.TotalCoverNodes, Sum.WaistPeekNodes, Sum.FullCornerNodes, Sum.SafeNodesCount]);
  FMemoReport.Lines.Text := TCoverPointScannerHelper.BuildMarkdownReport(FDesignRoot);
  FPaintRadar.Invalidate;
end;

procedure TCoverPointScannerForm.BtnSpawnArenaClick(Sender: TObject);
var
  Scanner: TCastleCoverPointScanner;
begin
  if TCoverPointScannerHelper.SpawnKillhouseCoverArena(FDesignRoot, FDesignOwner, Scanner) then
    NotifyChanged('Spawn Killhouse Cover Arena');
end;

procedure TCoverPointScannerForm.BtnSingleSniperClick(Sender: TObject);
var
  Scanner: TCastleCoverPointScanner;
  Vp: TCastleViewport;
  Best: TCoverNodeCandidate;
begin
  Scanner := TCoverPointScannerHelper.FindFirstScanner(FDesignRoot);
  Vp := FindViewportRoot;
  if (Scanner <> nil) and (Vp <> nil) then
  begin
    Scanner.EvaluateBestCoverAgainstThreats(Vp.Items, [Vector3(0.0, 0.0, -14.0)], Best);
    NotifyChanged('Evaluate North Sniper Cover');
  end;
end;

procedure TCoverPointScannerForm.BtnDualFlankersClick(Sender: TObject);
var
  Scanner: TCastleCoverPointScanner;
  Vp: TCastleViewport;
  Best: TCoverNodeCandidate;
begin
  Scanner := TCoverPointScannerHelper.FindFirstScanner(FDesignRoot);
  Vp := FindViewportRoot;
  if (Scanner <> nil) and (Vp <> nil) then
  begin
    Scanner.EvaluateBestCoverAgainstThreats(Vp.Items,
      [Vector3(0.0, 0.0, -14.0), Vector3(14.0, 0.0, 2.0)], Best);
    NotifyChanged('Evaluate Dual Crossfire Cover');
  end;
end;

procedure TCoverPointScannerForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TCoverPointScannerForm.PaintCoverRadar(Sender: TObject);
var
  C: TCanvas;
  Scanner: TCastleCoverPointScanner;
  CX, CY, I, PX, PY: Integer;
  ScalePx: Single;
  N: TCoverNodeCandidate;
begin
  C := FPaintRadar.Canvas;
  C.Brush.Color := $001B1E22;
  C.FillRect(0, 0, FPaintRadar.Width, FPaintRadar.Height);

  Scanner := TCoverPointScannerHelper.FindFirstScanner(FDesignRoot);
  if Scanner = nil then Exit;

  CX := FPaintRadar.Width div 2;
  CY := FPaintRadar.Height div 2;
  ScalePx := 9.5;

  for I := 0 to Scanner.CoverNodeCount - 1 do
  begin
    N := Scanner.GetCoverNode(I);
    PX := CX + Round(N.WorldPos.X * ScalePx);
    PY := CY + Round(N.WorldPos.Z * ScalePx);
    if not N.ProtectedFromThreats then
      C.Brush.Color := $003840E0
    else if N.Posture = cpkFullStandingCornerLean then
      C.Brush.Color := $00F0D040
    else
      C.Brush.Color := $0058E050;
    C.Ellipse(PX - 5, PY - 5, PX + 5, PY + 5);
  end;
end;

end.
