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

{ Visual Studio dialog for Dynamic Foliage/Grass Trample, Radial Shockwave
  Blast Flatten & Damped Spring-Back Bend Field Studio (Phase 393). }
unit FormFoliageTrample;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleFoliageTrample, ToolFoliageTrample;

type
  TFoliageTrampleModifiedCallback = procedure(const UndoComment: String) of object;
  TFoliageTrampleRefreshCallback = procedure of object;

  TFoliageTrampleForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TFoliageTrampleModifiedCallback;
    FOnRefresh: TFoliageTrampleRefreshCallback;
    FLblSummary: TLabel;
    FPaintBendMap: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnMeadowClick(Sender: TObject);
    procedure BtnGrenadeBlastClick(Sender: TObject);
    procedure BtnStepRecoveryClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintBendField(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TFoliageTrampleModifiedCallback;
      const AOnRefresh: TFoliageTrampleRefreshCallback);
  end;

implementation

constructor TFoliageTrampleForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TFoliageTrampleModifiedCallback;
  const AOnRefresh: TFoliageTrampleRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Dynamic Foliage Trample, Shockwave Flatten & Spring-Back Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TFoliageTrampleForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnBlast, BtnSpring, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn Golden Wheat Field';
  BtnSpawn.OnClick := @BtnSpawnMeadowClick;

  BtnBlast := TButton.Create(Self);
  BtnBlast.Parent := PnlButtons;
  BtnBlast.SetBounds(201, 8, 195, 30);
  BtnBlast.Caption := 'Detonate Shockwave (R=6m)';
  BtnBlast.OnClick := @BtnGrenadeBlastClick;

  BtnSpring := TButton.Create(Self);
  BtnSpring.Parent := PnlButtons;
  BtnSpring.SetBounds(402, 8, 195, 30);
  BtnSpring.Caption := 'Elastic Spring-Back (+0.5s)';
  BtnSpring.OnClick := @BtnStepRecoveryClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintBendMap := TPaintBox.Create(Self);
  FPaintBendMap.Parent := Self;
  FPaintBendMap.Align := alTop;
  FPaintBendMap.Height := 210;
  FPaintBendMap.OnPaint := @PaintBendField;

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

procedure TFoliageTrampleForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TFoliageTrampleForm.RefreshView;
var
  F: TCastleFoliageTrampleField;
begin
  F := TFoliageTrampleHelper.FindFirstField(FDesignRoot);
  if F = nil then
    FLblSummary.Caption := 'No TCastleFoliageTrampleField in scene. Click "+ Spawn Golden Wheat Field".'
  else
    FLblSummary.Caption := F.TrampleSummaryBadge;
  FMemoReport.Lines.Text := TFoliageTrampleHelper.GenerateMarkdownReport(F);
  FPaintBendMap.Invalidate;
end;

procedure TFoliageTrampleForm.BtnSpawnMeadowClick(Sender: TObject);
var
  F: TCastleFoliageTrampleField;
begin
  if TFoliageTrampleHelper.SpawnWheatFieldDemo(FDesignRoot, FDesignOwner, F) then
    NotifyChanged('Spawn Golden Wheat Trample Field');
end;

procedure TFoliageTrampleForm.BtnGrenadeBlastClick(Sender: TObject);
var
  F: TCastleFoliageTrampleField;
begin
  F := TFoliageTrampleHelper.FindFirstField(FDesignRoot);
  if F = nil then Exit;
  F.TriggerShockwaveBlast(Vector3(1.5, 0.0, 0.0), 6.0, 1.0);
  NotifyChanged('Trigger Radial Shockwave Foliage Flatten');
end;

procedure TFoliageTrampleForm.BtnStepRecoveryClick(Sender: TObject);
var
  F: TCastleFoliageTrampleField;
begin
  F := TFoliageTrampleHelper.FindFirstField(FDesignRoot);
  if F = nil then Exit;
  F.StepElasticSpringBack(0.5);
  NotifyChanged('Step Elastic Stalk Recovery +0.5s');
end;

procedure TFoliageTrampleForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TFoliageTrampleForm.PaintBendField(Sender: TObject);
var
  C: TCanvas;
  Fld: TCastleFoliageTrampleField;
  Smp: TFoliageBendSample;
  W, H, GX, GZ, PX, PY: Integer;
  HalfExt, WX, WZ: Single;
begin
  C := FPaintBendMap.Canvas;
  W := Max(20, FPaintBendMap.Width);
  H := Max(20, FPaintBendMap.Height);
  C.Brush.Color := RGBToColor(20, 28, 18);
  C.FillRect(0, 0, W, H);

  Fld := TFoliageTrampleHelper.FindFirstField(FDesignRoot);
  if Fld = nil then Exit;

  HalfExt := Fld.FieldExtentMeters * 0.5;
  C.Pen.Color := RGBToColor(235, 200, 72);
  for GZ := 0 to 15 do
    for GX := 0 to 23 do
    begin
      WX := -HalfExt + ((GX + 0.5) / 24.0) * Fld.FieldExtentMeters;
      WZ := -HalfExt + ((GZ + 0.5) / 16.0) * Fld.FieldExtentMeters;
      Smp := Fld.SampleBendAtWorld(Vector3(WX, 0.0, WZ));
      PX := 20 + Round(((GX + 0.5) / 24.0) * (W - 40));
      PY := 16 + Round(((GZ + 0.5) / 16.0) * (H - 32));
      C.MoveTo(PX, PY);
      C.LineTo(PX + Round(Smp.BendXZ.X * 14.0), PY + Round(Smp.BendXZ.Y * 14.0));
    end;
end;

end.
