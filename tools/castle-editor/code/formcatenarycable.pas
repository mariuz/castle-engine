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

{ Visual Studio dialog for Procedural Catenary Cable, Powerline Sag & Hanging
  Lantern Garland Studio (Phase 385). }
unit FormCatenaryCable;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleCatenaryCable, ToolCatenaryCable;

type
  TCatenaryCableModifiedCallback = procedure(const UndoComment: String) of object;
  TCatenaryCableRefreshCallback = procedure of object;

  TCatenaryCableForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TCatenaryCableModifiedCallback;
    FOnRefresh: TCatenaryCableRefreshCallback;
    FLblSummary: TLabel;
    FPaintProfile: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnGarlandClick(Sender: TObject);
    procedure BtnStepSwayClick(Sender: TObject);
    procedure BtnPowerlineClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintCatenaryProfile(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TCatenaryCableModifiedCallback;
      const AOnRefresh: TCatenaryCableRefreshCallback);
  end;

implementation

constructor TCatenaryCableForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TCatenaryCableModifiedCallback;
  const AOnRefresh: TCatenaryCableRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Catenary Cable, Powerline Sag & Hanging Lantern Studio';
  Width := 840;
  Height := 580;
  Position := poMainFormCenter;
  BuildUi;
  RefreshView;
end;

procedure TCatenaryCableForm.BuildUi;
var
  TopBar, BtnRow: TPanel;
  BtnSpawn, BtnSway, BtnPower, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 6, 215, 30);
  BtnSpawn.Caption := '+ Spawn Festival Lantern Garland';
  BtnSpawn.OnClick := @BtnSpawnGarlandClick;

  BtnSway := TButton.Create(Self);
  BtnSway.Parent := BtnRow;
  BtnSway.SetBounds(233, 6, 175, 30);
  BtnSway.Caption := 'Step Wind Sway (+0.40s)';
  BtnSway.OnClick := @BtnStepSwayClick;

  BtnPower := TButton.Create(Self);
  BtnPower.Parent := BtnRow;
  BtnPower.SetBounds(416, 6, 200, 30);
  BtnPower.Caption := 'Preset: High-Voltage Powerline';
  BtnPower.OnClick := @BtnPowerlineClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := BtnRow;
  BtnCopy.SetBounds(624, 6, 115, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := BtnRow;
  BtnClose.SetBounds(747, 6, 76, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;

  FPaintProfile := TPaintBox.Create(Self);
  FPaintProfile.Parent := Self;
  FPaintProfile.Align := alTop;
  FPaintProfile.Height := 250;
  FPaintProfile.OnPaint := @PaintCatenaryProfile;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TCatenaryCableForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TCatenaryCableForm.RefreshView;
var
  Sum: TCatenaryStudioSummary;
begin
  Sum := TCatenaryCableHelper.CollectSummary(FDesignRoot);
  FLblSummary.Caption := Format(
    'Cables: %d  |  Arc Length: %.2f m  |  Midpoint Sag: %.2f m  |  Hanging Lanterns: %d',
    [Sum.CableCount, Sum.TotalArcLengthMeters, Sum.MaxMidpointSagMeters, Sum.TotalLanternAttachments]);
  FMemoReport.Lines.Text := TCatenaryCableHelper.BuildMarkdownReport(FDesignRoot);
  FPaintProfile.Invalidate;
end;

procedure TCatenaryCableForm.BtnSpawnGarlandClick(Sender: TObject);
var
  Cable: TCastleCatenaryCable;
begin
  if TCatenaryCableHelper.SpawnFestivalGarlandDemo(FDesignRoot, FDesignOwner, Cable) then
    NotifyChanged('Spawn Festival Lantern Garland');
end;

procedure TCatenaryCableForm.BtnStepSwayClick(Sender: TObject);
var
  Cable: TCastleCatenaryCable;
begin
  Cable := TCatenaryCableHelper.FindFirstCable(FDesignRoot);
  if Cable <> nil then
  begin
    Cable.StepWindSway(0.40);
    RefreshView;
  end;
end;

procedure TCatenaryCableForm.BtnPowerlineClick(Sender: TObject);
var
  Cable: TCastleCatenaryCable;
begin
  Cable := TCatenaryCableHelper.FindFirstCable(FDesignRoot);
  if Cable <> nil then
  begin
    Cable.ApplyPreset(ccpHighVoltagePowerline);
    NotifyChanged('Switch Cable to High-Voltage Powerline');
  end;
end;

procedure TCatenaryCableForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TCatenaryCableForm.PaintCatenaryProfile(Sender: TObject);
var
  C: TCanvas;
  Cable: TCastleCatenaryCable;
  I, PX, PY, PrevX, PrevY: Integer;
  Pt: TVector3;
  Att: TCatenaryLanternAttachment;
begin
  C := FPaintProfile.Canvas;
  C.Brush.Color := $00221A14;
  C.FillRect(0, 0, FPaintProfile.Width, FPaintProfile.Height);

  Cable := TCatenaryCableHelper.FindFirstCable(FDesignRoot);
  if (Cable = nil) or (Cable.KnotCount < 2) then Exit;

  C.Pen.Color := $00A0D8F0;
  C.Pen.Width := 2;
  PrevX := 0; PrevY := 0;
  for I := 0 to Cable.KnotCount - 1 do
  begin
    Pt := Cable.GetKnotWorld(I);
    PX := (FPaintProfile.Width div 2) + Round(Pt.X * 36.0);
    PY := FPaintProfile.Height - 30 - Round(Pt.Y * 28.0);
    if I = 0 then
      C.MoveTo(PX, PY)
    else
      C.LineTo(PrevX, PrevY);
    C.MoveTo(PX, PY);
    PrevX := PX; PrevY := PY;
  end;
  C.Pen.Width := 1;

  C.Brush.Color := $0038B8FF;
  for I := 0 to Cable.AttachmentCount - 1 do
  begin
    Att := Cable.GetAttachment(I);
    PX := (FPaintProfile.Width div 2) + Round(Att.WorldPos.X * 36.0);
    PY := FPaintProfile.Height - 30 - Round(Att.WorldPos.Y * 28.0);
    C.Ellipse(PX - 6, PY + 2, PX + 6, PY + 14);
  end;
end;

end.
