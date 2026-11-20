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

{ Visual Studio dialog for Procedural Icicle, Stalactite & Cave Drip Overhang
  Studio (Phase 397). }
unit FormIcicleOverhang;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleIcicleOverhang, ToolIcicleOverhang;

type
  TIcicleOverhangModifiedCallback = procedure(const UndoComment: String) of object;
  TIcicleOverhangRefreshCallback = procedure of object;

  TIcicleOverhangForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TIcicleOverhangModifiedCallback;
    FOnRefresh: TIcicleOverhangRefreshCallback;
    FLblSummary: TLabel;
    FPaintProfile: TPaintBox;
    FMemoReport: TMemo;
    function FindViewport: TCastleViewport;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnCaveClick(Sender: TObject);
    procedure BtnWinterEaveClick(Sender: TObject);
    procedure BtnGlacialClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintSpikeCrossSection(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TIcicleOverhangModifiedCallback;
      const AOnRefresh: TIcicleOverhangRefreshCallback);
  end;

implementation

constructor TIcicleOverhangForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TIcicleOverhangModifiedCallback;
  const AOnRefresh: TIcicleOverhangRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Icicle, Stalactite & Cave Drip Overhang Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TIcicleOverhangForm.FindViewport: TCastleViewport;
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

procedure TIcicleOverhangForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnWinter, BtnGlacial, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Cavern Overhang & Grow';
  BtnSpawn.OnClick := @BtnSpawnCaveClick;

  BtnWinter := TButton.Create(Self);
  BtnWinter.Parent := PnlButtons;
  BtnWinter.SetBounds(211, 8, 185, 30);
  BtnWinter.Caption := 'Preset: Winter Roof Icicles';
  BtnWinter.OnClick := @BtnWinterEaveClick;

  BtnGlacial := TButton.Create(Self);
  BtnGlacial.Parent := PnlButtons;
  BtnGlacial.SetBounds(402, 8, 195, 30);
  BtnGlacial.Caption := 'Preset: Glacial Ice Cavern';
  BtnGlacial.OnClick := @BtnGlacialClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintProfile := TPaintBox.Create(Self);
  FPaintProfile.Parent := Self;
  FPaintProfile.Align := alTop;
  FPaintProfile.Height := 200;
  FPaintProfile.OnPaint := @PaintSpikeCrossSection;

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

procedure TIcicleOverhangForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TIcicleOverhangForm.RefreshView;
var
  O: TCastleIcicleOverhang;
begin
  O := TIcicleOverhangHelper.FindFirstOverhang(FDesignRoot);
  if O = nil then
    FLblSummary.Caption := 'No TCastleIcicleOverhang in scene. Click "+ Spawn Cavern Overhang & Grow".'
  else
    FLblSummary.Caption := O.IcicleSummaryBadge;
  FMemoReport.Lines.Text := TIcicleOverhangHelper.GenerateMarkdownReport(O);
  FPaintProfile.Invalidate;
end;

procedure TIcicleOverhangForm.BtnSpawnCaveClick(Sender: TObject);
var
  O: TCastleIcicleOverhang;
begin
  if TIcicleOverhangHelper.SpawnCavernOverhangDemo(FDesignRoot, FDesignOwner, O) then
    NotifyChanged('Spawn Cavern Overhang & Stalactites');
end;

procedure TIcicleOverhangForm.BtnWinterEaveClick(Sender: TObject);
var
  O: TCastleIcicleOverhang;
  VP: TCastleViewport;
begin
  O := TIcicleOverhangHelper.FindFirstOverhang(FDesignRoot);
  VP := FindViewport;
  if (O = nil) or (VP = nil) then Exit;
  O.ApplyPreset(iopRoofEaveWinterIcicles);
  O.GrowOverhangSpikes(VP.Items);
  NotifyChanged('Switch to Winter Roof Eave Icicles');
end;

procedure TIcicleOverhangForm.BtnGlacialClick(Sender: TObject);
var
  O: TCastleIcicleOverhang;
  VP: TCastleViewport;
begin
  O := TIcicleOverhangHelper.FindFirstOverhang(FDesignRoot);
  VP := FindViewport;
  if (O = nil) or (VP = nil) then Exit;
  O.ApplyPreset(iopGlacialIceCavern);
  O.GrowOverhangSpikes(VP.Items);
  NotifyChanged('Switch to Glacial Ice Cavern');
end;

procedure TIcicleOverhangForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TIcicleOverhangForm.PaintSpikeCrossSection(Sender: TObject);
var
  C: TCanvas;
  O: TCastleIcicleOverhang;
  S: TIcicleSpikeSample;
  W, H, I, PX, TopY, TipY, FloorY: Integer;
begin
  C := FPaintProfile.Canvas;
  W := Max(20, FPaintProfile.Width);
  H := Max(20, FPaintProfile.Height);
  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  O := TIcicleOverhangHelper.FindFirstOverhang(FDesignRoot);
  if O = nil then Exit;

  C.Pen.Color := RGBToColor(135, 225, 255);
  C.Pen.Width := 2;
  for I := 0 to O.SpikeCount - 1 do
  begin
    S := O.GetSpike(I);
    PX := (W div 2) + Round(S.CeilingAttachWorld.X * 52.0);
    TopY := H - 20 - Round(S.CeilingAttachWorld.Y * 32.0);
    TipY := H - 20 - Round(S.TipWorld.Y * 32.0);
    C.MoveTo(PX, TopY);
    C.LineTo(PX, TipY);
    if S.HasPairedStalagmite then
    begin
      FloorY := H - 20 - Round(S.FloorHitWorld.Y * 32.0);
      C.MoveTo(PX, FloorY);
      C.LineTo(PX, FloorY - Round(S.StalagmiteHeightMeters * 32.0));
    end;
  end;
end;

end.
