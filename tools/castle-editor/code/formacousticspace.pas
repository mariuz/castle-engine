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

{ Visual Studio dialog for Acoustic Raytraced Reverb, Sabine/Eyring RT60 &
  Doorway Diffraction Obstruction Studio (Phase 388). }
unit FormAcousticSpace;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleAcousticSpace, ToolAcousticSpace;

type
  TAcousticSpaceModifiedCallback = procedure(const UndoComment: String) of object;
  TAcousticSpaceRefreshCallback = procedure of object;

  TAcousticSpaceForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TAcousticSpaceModifiedCallback;
    FOnRefresh: TAcousticSpaceRefreshCallback;
    FLblSummary: TLabel;
    FPaintDecay: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnCathedralClick(Sender: TObject);
    procedure BtnPaddedBoothClick(Sender: TObject);
    procedure BtnDoorwayObstructionClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintDecayEnvelope(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TAcousticSpaceModifiedCallback;
      const AOnRefresh: TAcousticSpaceRefreshCallback);
  end;

implementation

constructor TAcousticSpaceForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TAcousticSpaceModifiedCallback;
  const AOnRefresh: TAcousticSpaceRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Acoustic Raytraced Reverb (RT60) & Doorway Diffraction Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TAcousticSpaceForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnBooth, BtnDiffract, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Stone Cathedral Hall';
  BtnSpawn.OnClick := @BtnSpawnCathedralClick;

  BtnBooth := TButton.Create(Self);
  BtnBooth.Parent := PnlButtons;
  BtnBooth.SetBounds(211, 8, 185, 30);
  BtnBooth.Caption := 'Convert to Padded Booth';
  BtnBooth.OnClick := @BtnPaddedBoothClick;

  BtnDiffract := TButton.Create(Self);
  BtnDiffract.Parent := PnlButtons;
  BtnDiffract.SetBounds(402, 8, 200, 30);
  BtnDiffract.Caption := 'Test Doorway Diffraction LPF';
  BtnDiffract.OnClick := @BtnDoorwayObstructionClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(608, 8, 130, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintDecay := TPaintBox.Create(Self);
  FPaintDecay.Parent := Self;
  FPaintDecay.Align := alTop;
  FPaintDecay.Height := 200;
  FPaintDecay.OnPaint := @PaintDecayEnvelope;

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

procedure TAcousticSpaceForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TAcousticSpaceForm.RefreshView;
var
  P: TCastleAcousticProbe;
begin
  P := TAcousticSpaceHelper.FindFirstProbe(FDesignRoot);
  if P = nil then
    FLblSummary.Caption := 'No TCastleAcousticProbe in scene. Click "+ Spawn Stone Cathedral Hall".'
  else
    FLblSummary.Caption := P.AcousticSummaryBadge;
  FMemoReport.Lines.Text := TAcousticSpaceHelper.GenerateMarkdownReport(P);
  FPaintDecay.Invalidate;
end;

procedure TAcousticSpaceForm.BtnSpawnCathedralClick(Sender: TObject);
var
  P: TCastleAcousticProbe;
begin
  if TAcousticSpaceHelper.SpawnStoneHallAndDoorwayDemo(FDesignRoot, FDesignOwner, P) then
    NotifyChanged('Spawn Stone Cathedral Acoustic Hall');
end;

procedure TAcousticSpaceForm.BtnPaddedBoothClick(Sender: TObject);
var
  P: TCastleAcousticProbe;
begin
  P := TAcousticSpaceHelper.FindFirstProbe(FDesignRoot);
  if P = nil then Exit;
  TAcousticSpaceHelper.ConvertRoomToPaddedBooth(FDesignRoot, P);
  NotifyChanged('Convert Acoustic Hall to Padded Foam Booth');
end;

procedure TAcousticSpaceForm.BtnDoorwayObstructionClick(Sender: TObject);
var
  P: TCastleAcousticProbe;
  VP: TCastleViewport;
  Obs: TAcousticObstructionSample;
  I: Integer;
begin
  P := TAcousticSpaceHelper.FindFirstProbe(FDesignRoot);
  if P = nil then Exit;
  VP := nil;
  for I := 0 to FDesignRoot.ComponentCount - 1 do
    if FDesignRoot.Components[I] is TCastleViewport then
      VP := TCastleViewport(FDesignRoot.Components[I]);
  if (VP = nil) or (VP.Items = nil) then Exit;
  Obs := P.EvaluateSourceObstruction(
    VP.Items, Vector3(0.0, 1.7, -8.0), Vector3(6.8, 1.7, -3.0));
  FMemoReport.Lines.Add('');
  FMemoReport.Lines.Add(FormatDot(
    '- **Doorway Diffraction Probe**: DirectLoS=`%s`, ViaPortal=`%s`, Detour=`+%.2f m`, LPF=`%.0f Hz`, Gain=`%.2f`',
    [BoolToStr(Obs.DirectLineOfSight, True),
     BoolToStr(Obs.DiffractedViaPortal, True),
     Obs.DetourExcessMeters, Obs.LowPassCutoffHz, Obs.DirectGain01]));
end;

procedure TAcousticSpaceForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TAcousticSpaceForm.PaintDecayEnvelope(Sender: TObject);
var
  C: TCanvas;
  P: TCastleAcousticProbe;
  W, H, X, PY: Integer;
  TMax, TSec, DbDecay: Single;
begin
  C := FPaintDecay.Canvas;
  W := Max(10, FPaintDecay.Width);
  H := Max(10, FPaintDecay.Height);
  C.Brush.Color := RGBToColor(16, 22, 32);
  C.FillRect(0, 0, W, H);

  P := TAcousticSpaceHelper.FindFirstProbe(FDesignRoot);
  if (P = nil) or (P.LastRoom.SabineRt60Sec <= 0.001) then
  begin
    C.Font.Color := RGBToColor(180, 200, 220);
    C.TextOut(14, H div 2 - 8, '-60 dB Impulse Reverberation Curve (spawn room to trace)');
    Exit;
  end;

  TMax := Max(1.0, P.LastRoom.SabineRt60Sec * 1.25);
  C.Pen.Color := RGBToColor(70, 205, 255);
  C.Pen.Width := 2;
  for X := 16 to W - 16 do
  begin
    TSec := ((X - 16) / Max(1, W - 32)) * TMax;
    DbDecay := Clamped((TSec / Max(0.02, P.LastRoom.SabineRt60Sec)) * 60.0, 0.0, 60.0);
    PY := 16 + Round((DbDecay / 60.0) * (H - 32));
    if X = 16 then C.MoveTo(X, PY) else C.LineTo(X, PY);
  end;
end;

end.
