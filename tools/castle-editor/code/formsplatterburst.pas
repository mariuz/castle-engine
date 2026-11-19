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

{ Visual Studio dialog for Procedural Decal Splatter, WorldRay Directional Cone
  Burst & Grazing-Angle Streak Elongation Studio (Phase 395). }
unit FormSplatterBurst;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleSplatterBurst, ToolSplatterBurst;

type
  TSplatterBurstModifiedCallback = procedure(const UndoComment: String) of object;
  TSplatterBurstRefreshCallback = procedure of object;

  TSplatterBurstForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSplatterBurstModifiedCallback;
    FOnRefresh: TSplatterBurstRefreshCallback;
    FLblSummary: TLabel;
    FPaintSplats: TPaintBox;
    FMemoReport: TMemo;
    function FindViewport: TCastleViewport;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnCornerClick(Sender: TObject);
    procedure BtnGrazingBurstClick(Sender: TObject);
    procedure BtnFadeStepClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintSplatPreview(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSplatterBurstModifiedCallback;
      const AOnRefresh: TSplatterBurstRefreshCallback);
  end;

implementation

constructor TSplatterBurstForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSplatterBurstModifiedCallback;
  const AOnRefresh: TSplatterBurstRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Decal Splatter Burst & Grazing Streak Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TSplatterBurstForm.FindViewport: TCastleViewport;
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

procedure TSplatterBurstForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnGraze, BtnFade, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Corner & Spray Burst';
  BtnSpawn.OnClick := @BtnSpawnCornerClick;

  BtnGraze := TButton.Create(Self);
  BtnGraze.Parent := PnlButtons;
  BtnGraze.SetBounds(211, 8, 190, 30);
  BtnGraze.Caption := 'Fire Grazing Wall Burst';
  BtnGraze.OnClick := @BtnGrazingBurstClick;

  BtnFade := TButton.Create(Self);
  BtnFade.Parent := PnlButtons;
  BtnFade.SetBounds(407, 8, 190, 30);
  BtnFade.Caption := 'Step Evaporation (+4.0s)';
  BtnFade.OnClick := @BtnFadeStepClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintSplats := TPaintBox.Create(Self);
  FPaintSplats.Parent := Self;
  FPaintSplats.Align := alTop;
  FPaintSplats.Height := 200;
  FPaintSplats.OnPaint := @PaintSplatPreview;

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

procedure TSplatterBurstForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TSplatterBurstForm.RefreshView;
var
  B: TCastleSplatterBurst;
begin
  B := TSplatterBurstHelper.FindFirstBurst(FDesignRoot);
  if B = nil then
    FLblSummary.Caption := 'No TCastleSplatterBurst in scene. Click "+ Spawn Corner & Spray Burst".'
  else
    FLblSummary.Caption := B.SplatterSummaryBadge;
  FMemoReport.Lines.Text := TSplatterBurstHelper.GenerateMarkdownReport(B);
  FPaintSplats.Invalidate;
end;

procedure TSplatterBurstForm.BtnSpawnCornerClick(Sender: TObject);
var
  B: TCastleSplatterBurst;
begin
  if TSplatterBurstHelper.SpawnCornerRoomSplatterDemo(FDesignRoot, FDesignOwner, B) then
    NotifyChanged('Spawn Corner Room Splatter Burst');
end;

procedure TSplatterBurstForm.BtnGrazingBurstClick(Sender: TObject);
var
  B: TCastleSplatterBurst;
  VP: TCastleViewport;
begin
  B := TSplatterBurstHelper.FindFirstBurst(FDesignRoot);
  VP := FindViewport;
  if (B = nil) or (VP = nil) then Exit;
  B.EmitDirectionalBurst(VP.Items, Vector3(1.85, 1.5, 0.0),
    Vector3(0.15, 0.0, -1.0).Normalize);
  NotifyChanged('Emit Grazing Wall Splatter Burst');
end;

procedure TSplatterBurstForm.BtnFadeStepClick(Sender: TObject);
var
  B: TCastleSplatterBurst;
begin
  B := TSplatterBurstHelper.FindFirstBurst(FDesignRoot);
  if B = nil then Exit;
  B.StepEvaporationFade(4.0);
  NotifyChanged('Step Splatter Evaporation +4.0s');
end;

procedure TSplatterBurstForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TSplatterBurstForm.PaintSplatPreview(Sender: TObject);
var
  C: TCanvas;
  B: TCastleSplatterBurst;
  M: TSplatDecalMark;
  W, H, I, PX, PY, RX, RY: Integer;
begin
  C := FPaintSplats.Canvas;
  W := Max(20, FPaintSplats.Width);
  H := Max(20, FPaintSplats.Height);
  C.Brush.Color := RGBToColor(22, 24, 30);
  C.FillRect(0, 0, W, H);

  B := TSplatterBurstHelper.FindFirstBurst(FDesignRoot);
  if B = nil then Exit;

  C.Brush.Color := RGBToColor(255, 65, 175);
  for I := 0 to B.ActiveSplatCount - 1 do
  begin
    M := B.GetSplatMark(I);
    PX := (W div 2) + Round(M.WorldPos.X * 65.0);
    PY := (H - 30) - Round(M.WorldPos.Y * 42.0);
    RX := Max(3, Round(M.WidthMeters * 14.0));
    RY := Max(3, Round(M.LengthMeters * 14.0));
    C.Ellipse(PX - RX, PY - RY, PX + RX, PY + RY);
  end;
end;

end.
