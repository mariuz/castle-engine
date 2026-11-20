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

{ Visual Studio dialog for Multi-Leg Quadruped / Hexapod / Spider Gait Phase,
  WorldRay Slope Foot-Plant & Body Tilt Studio (Phase 398). }
unit FormQuadrupedGait;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleQuadrupedGait, ToolQuadrupedGait;

type
  TQuadrupedGaitModifiedCallback = procedure(const UndoComment: String) of object;
  TQuadrupedGaitRefreshCallback = procedure of object;

  TQuadrupedGaitForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TQuadrupedGaitModifiedCallback;
    FOnRefresh: TQuadrupedGaitRefreshCallback;
    FLblSummary: TLabel;
    FPaintPhases: TPaintBox;
    FMemoReport: TMemo;
    function FindViewport: TCastleViewport;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnStepCycleClick(Sender: TObject);
    procedure BtnSpider8Click(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintHildebrandDiagram(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TQuadrupedGaitModifiedCallback;
      const AOnRefresh: TQuadrupedGaitRefreshCallback);
  end;

implementation

constructor TQuadrupedGaitForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TQuadrupedGaitModifiedCallback;
  const AOnRefresh: TQuadrupedGaitRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Multi-Leg Quadruped / Hexapod / Spider Gait & Terrain Plant Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TQuadrupedGaitForm.FindViewport: TCastleViewport;
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

procedure TQuadrupedGaitForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnStep, BtnSpider, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.Caption := '+ Spawn 6-Leg Tripod + Ledge';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlButtons;
  BtnStep.SetBounds(211, 8, 185, 30);
  BtnStep.Caption := 'Step Gait Cycle (+0.12s)';
  BtnStep.OnClick := @BtnStepCycleClick;

  BtnSpider := TButton.Create(Self);
  BtnSpider.Parent := PnlButtons;
  BtnSpider.SetBounds(402, 8, 195, 30);
  BtnSpider.Caption := 'Preset: 8-Leg Giant Spider';
  BtnSpider.OnClick := @BtnSpider8Click;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintPhases := TPaintBox.Create(Self);
  FPaintPhases.Parent := Self;
  FPaintPhases.Align := alTop;
  FPaintPhases.Height := 200;
  FPaintPhases.OnPaint := @PaintHildebrandDiagram;

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

procedure TQuadrupedGaitForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TQuadrupedGaitForm.RefreshView;
var
  R: TCastleMultiLegGaitRig;
begin
  R := TQuadrupedGaitHelper.FindFirstRig(FDesignRoot);
  if R = nil then
    FLblSummary.Caption := 'No TCastleMultiLegGaitRig in scene. Click "+ Spawn 6-Leg Tripod + Ledge".'
  else
    FLblSummary.Caption := R.GaitSummaryBadge;
  FMemoReport.Lines.Text := TQuadrupedGaitHelper.GenerateMarkdownReport(R);
  FPaintPhases.Invalidate;
end;

procedure TQuadrupedGaitForm.BtnSpawnDemoClick(Sender: TObject);
var
  R: TCastleMultiLegGaitRig;
begin
  if TQuadrupedGaitHelper.SpawnSteppedRampGaitDemo(FDesignRoot, FDesignOwner, R) then
    NotifyChanged('Spawn 6-Leg Hexapod Tripod Demo');
end;

procedure TQuadrupedGaitForm.BtnStepCycleClick(Sender: TObject);
var
  R: TCastleMultiLegGaitRig;
  VP: TCastleViewport;
begin
  R := TQuadrupedGaitHelper.FindFirstRig(FDesignRoot);
  VP := FindViewport;
  if (R = nil) or (VP = nil) then Exit;
  R.StepGaitLocomotion(VP.Items, 0.12);
  NotifyChanged('Step Multi-Leg Gait +0.12s');
end;

procedure TQuadrupedGaitForm.BtnSpider8Click(Sender: TObject);
var
  R: TCastleMultiLegGaitRig;
  VP: TCastleViewport;
begin
  R := TQuadrupedGaitHelper.FindFirstRig(FDesignRoot);
  VP := FindViewport;
  if (R = nil) or (VP = nil) then Exit;
  R.ApplyPreset(mgpArachnidOctopod8Leg);
  R.EvaluateAtNormalizedCycle(VP.Items, R.GaitCycle01);
  NotifyChanged('Switch to 8-Leg Arachnid Gait');
end;

procedure TQuadrupedGaitForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TQuadrupedGaitForm.PaintHildebrandDiagram(Sender: TObject);
var
  C: TCanvas;
  R: TCastleMultiLegGaitRig;
  S: TLegFootSample;
  W, H, RowH, I, PX: Integer;
begin
  C := FPaintPhases.Canvas;
  W := Max(20, FPaintPhases.Width);
  H := Max(20, FPaintPhases.Height);
  C.Brush.Color := RGBToColor(18, 22, 28);
  C.FillRect(0, 0, W, H);

  R := TQuadrupedGaitHelper.FindFirstRig(FDesignRoot);
  if (R = nil) or (R.LegCount = 0) then Exit;

  RowH := Max(16, (H - 16) div R.LegCount);
  for I := 0 to R.LegCount - 1 do
  begin
    S := R.GetLegSample(I);
    if S.IsStanceGrounded then
      C.Brush.Color := RGBToColor(68, 218, 128)
    else
      C.Brush.Color := RGBToColor(245, 168, 60);
    PX := 20 + Round(S.LocalCyclePhase01 * (W - 40));
    C.FillRect(Max(20, PX - 12), 8 + I * RowH, Min(W - 20, PX + 12), 8 + I * RowH + RowH - 4);
  end;
end;

end.
