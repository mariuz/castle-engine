{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Interactive Groom Strand Hair / Fur Clump Cards, Guide-Curve Clumping &
  Inertial Wind Studio dialog (Phase 348). }
unit FormGroomStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleGroomHair, ToolGroomStudio;

type
  TGroomModifyCallback = procedure(const AUndoComment: String) of object;
  TGroomRefreshCallback = procedure of object;

  TGroomStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TGroomModifyCallback;
    FOnRefreshViewport: TGroomRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintProfile: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure ApplyGroomStyle(const APreset: TGroomStylePreset; const ALabel: String);
    procedure BtnSpawnBustClick(Sender: TObject);
    procedure BtnHeroBobClick(Sender: TObject);
    procedure BtnCurlyRingletsClick(Sender: TObject);
    procedure BtnWolfManeClick(Sender: TObject);
    procedure BtnWindGustClick(Sender: TObject);
    procedure BtnStepPhysicsClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintProfilePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TGroomModifyCallback;
      const AOnRefreshViewport: TGroomRefreshCallback);
  end;

implementation

constructor TGroomStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TGroomModifyCallback;
  const AOnRefreshViewport: TGroomRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Groom Strand Hair / Fur Clump Cards & Inertial Wind Studio (UE 6.0+ UGroomComponent Parity)';
  Width := 1040;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TGroomStudioForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 160): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Align := alLeft;
    Result.BorderSpacing.Around := 4;
    Result.OnClick := AOnClick;
  end;

begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 128;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'Groom Strand Hair & Fur Studio — Fibonacci Scalp Guides, Root-to-Tip Lock Clumping, Curl/Frizz Cards & Verlet Wind Sway';

  LabelTelemetry := TLabel.Create(Self);
  LabelTelemetry.Parent := TopBar;
  LabelTelemetry.Align := alTop;
  LabelTelemetry.BorderSpacing.Left := 6;
  LabelTelemetry.Caption := 'Telemetry: ready';

  BtnRow1 := TPanel.Create(Self);
  BtnRow1.Parent := TopBar;
  BtnRow1.Align := alTop;
  BtnRow1.Height := 38;
  BtnRow1.BevelOuter := bvNone;
  MakeBtn(BtnRow1, '+ Spawn Groom Head Bust', @BtnSpawnBustClick, 186);
  MakeBtn(BtnRow1, 'Style: Hero Bob', @BtnHeroBobClick, 144);
  MakeBtn(BtnRow1, 'Style: Curly Ringlets', @BtnCurlyRingletsClick, 162);
  MakeBtn(BtnRow1, 'Style: Wolf Mane Fur', @BtnWolfManeClick, 162);
  MakeBtn(BtnRow1, 'Gust Wind (+5 m/s X)', @BtnWindGustClick, 168);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Step Strands (+0.04s)', @BtnStepPhysicsClick, 174);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 184);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 410;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintProfile := TPaintBox.Create(Self);
  PaintProfile.Parent := BodyPanel;
  PaintProfile.Align := alClient;
  PaintProfile.BorderSpacing.Around := 6;
  PaintProfile.OnPaint := @PaintProfilePaint;
end;

procedure TGroomStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TGroomStudioForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TGroomStudioSummary;
begin
  Warnings := TStringList.Create;
  try
    Sum := TGroomStudioHelper.CollectSummary(FDesignRoot, Warnings);
    LabelTelemetry.Caption := Format(
      'Grooms: %d | Guides: %d | Clumped Strands: %d | Tapered Card Triangles: %d',
      [Sum.GroomCount, Sum.TotalGuides, Sum.TotalStrands, Sum.TotalTriangles]);
    MemoReport.Lines.Text := TGroomStudioHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintProfile.Invalidate;
end;

procedure TGroomStudioForm.ApplyGroomStyle(const APreset: TGroomStylePreset;
  const ALabel: String);
var
  Head: TCastleTransform;
  G: TCastleGroomComponent;
begin
  G := TGroomStudioHelper.FindFirstGroom(FDesignRoot);
  if G = nil then
    TGroomStudioHelper.SpawnScalpHeadGroomDemo(FDesignRoot, FDesignOwner, Head, G);
  if G = nil then Exit;
  G.ApplyStylePreset(APreset);
  NotifyChange(ALabel);
end;

procedure TGroomStudioForm.BtnSpawnBustClick(Sender: TObject);
var
  Head: TCastleTransform;
  G: TCastleGroomComponent;
begin
  if TGroomStudioHelper.SpawnScalpHeadGroomDemo(FDesignRoot, FDesignOwner, Head, G) then
    NotifyChange('Spawn Groom Character Bust');
end;

procedure TGroomStudioForm.BtnHeroBobClick(Sender: TObject);
begin
  ApplyGroomStyle(gspStylizedHeroBob, 'Groom Style: Stylized Hero Bob');
end;

procedure TGroomStudioForm.BtnCurlyRingletsClick(Sender: TObject);
begin
  ApplyGroomStyle(gspCurlyRinglets, 'Groom Style: Curly Ringlets');
end;

procedure TGroomStudioForm.BtnWolfManeClick(Sender: TObject);
begin
  ApplyGroomStyle(gspWolfManeFur, 'Groom Style: Wolf Mane Fur');
end;

procedure TGroomStudioForm.BtnWindGustClick(Sender: TObject);
var
  G: TCastleGroomComponent;
  I: Integer;
begin
  G := TGroomStudioHelper.FindFirstGroom(FDesignRoot);
  if G = nil then Exit;
  G.WindVelocity := Vector3(5.5, 0.4, 0.0);
  for I := 1 to 10 do
    G.StepGroomPhysics(0.025);
  NotifyChange('Apply Groom Wind Gust');
end;

procedure TGroomStudioForm.BtnStepPhysicsClick(Sender: TObject);
begin
  TGroomStudioHelper.StepAllGrooms(FDesignRoot, 0.04);
  NotifyChange('Step Groom Physics');
end;

procedure TGroomStudioForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'groom_hair_fur_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TGroomStudioHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TGroomStudioForm.PaintProfilePaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, CX, CY, HeadR, GIdx, CIdx, K, X0, Y0, X1, Y1: Integer;
  G: TCastleGroomComponent;
  P0, P1: TVector3;
  ScalePx: Single;
begin
  Cv := PaintProfile.Canvas;
  W := Max(200, PaintProfile.Width);
  H := Max(200, PaintProfile.Height);
  CX := W div 2;
  CY := H div 2 - 20;

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);

  G := TGroomStudioHelper.FindFirstGroom(FDesignRoot);
  if G <> nil then
  begin
    ScalePx := Min(W, H) * 0.42 / Max(0.35, G.ScalpRadius + G.StrandLength);
    HeadR := Round(G.ScalpRadius * ScalePx);

    { Scalp collision sphere }
    Cv.Brush.Color := RGBToColor(78, 66, 62);
    Cv.Pen.Color := RGBToColor(138, 118, 108);
    Cv.Ellipse(CX - HeadR, CY - HeadR, CX + HeadR, CY + HeadR);

    { Draw clumped child strands in XY side-profile }
    for GIdx := 0 to G.GuideCount - 1 do
      for CIdx := 0 to G.StrandsPerClump - 1 do
      begin
        if CIdx = 0 then
          Cv.Pen.Color := RGBToColor(246, 178, 86)
        else
          Cv.Pen.Color := RGBToColor(186, 116, 58);
        for K := 0 to G.SegmentsPerStrand - 1 do
        begin
          P0 := G.EvaluateChildStrandPointLocal(GIdx, CIdx, K);
          P1 := G.EvaluateChildStrandPointLocal(GIdx, CIdx, K + 1);
          X0 := CX + Round(P0.X * ScalePx);
          Y0 := CY - Round(P0.Y * ScalePx);
          X1 := CX + Round(P1.X * ScalePx);
          Y1 := CY - Round(P1.Y * ScalePx);
          Cv.Line(X0, Y0, X1, Y1);
        end;
      end;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(16, 10, 'XY Side-Profile Scalp Sphere Collision & Clumped Strand Locks');
  Cv.Font.Style := [];
end;

end.
