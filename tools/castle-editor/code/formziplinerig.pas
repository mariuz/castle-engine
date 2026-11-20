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

{ Visual Studio dialog for Procedural Zipline, Pulley Trolley Gravity
  Acceleration, Hand-Brake & Momentum Vault Studio (Phase 399). }
unit FormZiplineRig;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleZiplineRig, ToolZiplineRig;

type
  TZiplineRigModifiedCallback = procedure(const UndoComment: String) of object;
  TZiplineRigRefreshCallback = procedure of object;

  TZiplineRigForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TZiplineRigModifiedCallback;
    FOnRefresh: TZiplineRigRefreshCallback;
    FLblSummary: TLabel;
    FPaintSpan: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnTowersClick(Sender: TObject);
    procedure BtnGlideFreeClick(Sender: TObject);
    procedure BtnHandBrakeClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintZiplineProfile(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TZiplineRigModifiedCallback;
      const AOnRefresh: TZiplineRigRefreshCallback);
  end;

implementation

constructor TZiplineRigForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TZiplineRigModifiedCallback;
  const AOnRefresh: TZiplineRigRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Zipline, Pulley Gravity Acceleration & Vault Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TZiplineRigForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnGlide, BtnBrake, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Canyon Zipline Span';
  BtnSpawn.OnClick := @BtnSpawnTowersClick;

  BtnGlide := TButton.Create(Self);
  BtnGlide.Parent := PnlButtons;
  BtnGlide.SetBounds(211, 8, 190, 30);
  BtnGlide.Caption := 'Step Free Glide (+0.65s)';
  BtnGlide.OnClick := @BtnGlideFreeClick;

  BtnBrake := TButton.Create(Self);
  BtnBrake.Parent := PnlButtons;
  BtnBrake.SetBounds(407, 8, 190, 30);
  BtnBrake.Caption := 'Step Hand-Brake (+0.65s)';
  BtnBrake.OnClick := @BtnHandBrakeClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintSpan := TPaintBox.Create(Self);
  FPaintSpan.Parent := Self;
  FPaintSpan.Align := alTop;
  FPaintSpan.Height := 200;
  FPaintSpan.OnPaint := @PaintZiplineProfile;

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

procedure TZiplineRigForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TZiplineRigForm.RefreshView;
var
  Z: TCastleZiplineRig;
begin
  Z := TZiplineRigHelper.FindFirstZipline(FDesignRoot);
  if Z = nil then
    FLblSummary.Caption := 'No TCastleZiplineRig in scene. Click "+ Spawn Canyon Zipline Span".'
  else
    FLblSummary.Caption := Z.ZiplineSummaryBadge;
  FMemoReport.Lines.Text := TZiplineRigHelper.GenerateMarkdownReport(Z);
  FPaintSpan.Invalidate;
end;

procedure TZiplineRigForm.BtnSpawnTowersClick(Sender: TObject);
var
  Z: TCastleZiplineRig;
begin
  if TZiplineRigHelper.SpawnCanyonZiplineTowersDemo(FDesignRoot, FDesignOwner, Z) then
    NotifyChanged('Spawn Canyon Zipline Towers');
end;

procedure TZiplineRigForm.BtnGlideFreeClick(Sender: TObject);
var
  Z: TCastleZiplineRig;
begin
  Z := TZiplineRigHelper.FindFirstZipline(FDesignRoot);
  if Z = nil then Exit;
  Z.StepZiplineRide(0.65, 0.0);
  NotifyChanged('Step Free Zipline Glide +0.65s');
end;

procedure TZiplineRigForm.BtnHandBrakeClick(Sender: TObject);
var
  Z: TCastleZiplineRig;
begin
  Z := TZiplineRigHelper.FindFirstZipline(FDesignRoot);
  if Z = nil then Exit;
  Z.StepZiplineRide(0.65, 1.0);
  NotifyChanged('Step Hand-Braked Zipline Glide +0.65s');
end;

procedure TZiplineRigForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TZiplineRigForm.PaintZiplineProfile(Sender: TObject);
var
  C: TCanvas;
  Z: TCastleZiplineRig;
  WPos, StartW, EndW, Tang: TVector3;
  W, H, I, PX, PY: Integer;
  MinY, MaxY: Single;
begin
  C := FPaintSpan.Canvas;
  W := Max(20, FPaintSpan.Width);
  H := Max(20, FPaintSpan.Height);
  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  Z := TZiplineRigHelper.FindFirstZipline(FDesignRoot);
  if Z = nil then Exit;

  Z.EvaluateCablePointAt(0.0, False, StartW, Tang);
  Z.EvaluateCablePointAt(1.0, False, EndW, Tang);
  MaxY := Max(StartW.Y, EndW.Y) + 0.5;
  MinY := Min(StartW.Y, EndW.Y) - 2.5;

  C.Pen.Color := RGBToColor(245, 200, 75);
  C.Pen.Width := 2;
  for I := 0 to 28 do
  begin
    Z.EvaluateCablePointAt(I / 28.0, True, WPos, Tang);
    PX := 20 + Round((I / 28.0) * (W - 40));
    PY := (H - 18) - Round(((WPos.Y - MinY) / Max(1.0, MaxY - MinY)) * (H - 36));
    if I = 0 then C.MoveTo(PX, PY) else C.LineTo(PX, PY);
  end;

  PX := 20 + Round(Z.LastState.NormalizedProgress01 * (W - 40));
  PY := (H - 18) - Round(((Z.LastState.WorldPulleyPos.Y - MinY) / Max(1.0, MaxY - MinY)) * (H - 36));
  C.Brush.Color := RGBToColor(64, 225, 255);
  C.Ellipse(PX - 6, PY - 6, PX + 6, PY + 6);
end;

end.
