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

{ Visual Studio dialog for Mechanical Gear Train, Rack-and-Pinion, Belt Pulley
  & Odd-Cycle Jam Detection Studio (Phase 415). }
unit FormGearLinkage;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleGearLinkage, ToolGearLinkage;

type
  TGearLinkageModifiedCallback = procedure(const UndoComment: String) of object;
  TGearLinkageRefreshCallback = procedure of object;

  TGearLinkageForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TGearLinkageModifiedCallback;
    FOnRefresh: TGearLinkageRefreshCallback;
    FLblSummary: TLabel;
    FPaintTrain: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnStepCrankClick(Sender: TObject);
    procedure BtnTriggerJamClick(Sender: TObject);
    procedure BtnBeltPresetClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintGearSchematic(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TGearLinkageModifiedCallback;
      const AOnRefresh: TGearLinkageRefreshCallback);
  end;

implementation

constructor TGearLinkageForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TGearLinkageModifiedCallback;
  const AOnRefresh: TGearLinkageRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Mechanical Gear Train, Rack-and-Pinion & Clockwork Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

procedure TGearLinkageForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnCrank, BtnJam, BtnBelt, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 8, 180, 30);
  BtnSpawn.Caption := '+ Spawn Portcullis Gearbox';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnCrank := TButton.Create(Self);
  BtnCrank.Parent := PnlButtons;
  BtnCrank.SetBounds(195, 8, 140, 30);
  BtnCrank.Caption := 'Crank Gate (+1.0s)';
  BtnCrank.OnClick := @BtnStepCrankClick;

  BtnJam := TButton.Create(Self);
  BtnJam.Parent := PnlButtons;
  BtnJam.SetBounds(340, 8, 145, 30);
  BtnJam.Caption := 'Test 3-Gear Odd Jam';
  BtnJam.OnClick := @BtnTriggerJamClick;

  BtnBelt := TButton.Create(Self);
  BtnBelt.Parent := PnlButtons;
  BtnBelt.SetBounds(490, 8, 135, 30);
  BtnBelt.Caption := 'Sawmill Belt Pulley';
  BtnBelt.OnClick := @BtnBeltPresetClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(630, 8, 70, 30);
  BtnCopy.Caption := 'Copy MD';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlButtons;
  BtnClose.SetBounds(705, 8, 65, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;
  BtnClose.OnClick := nil;

  FPaintTrain := TPaintBox.Create(Self);
  FPaintTrain.Parent := Self;
  FPaintTrain.Align := alTop;
  FPaintTrain.Height := 215;
  FPaintTrain.OnPaint := @PaintGearSchematic;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TGearLinkageForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TGearLinkageForm.RefreshView;
var
  G: TCastleGearLinkage;
begin
  G := TGearLinkageHelper.FindFirstLinkage(FDesignRoot);
  if G <> nil then
    FLblSummary.Caption := G.Name + '  ' + G.GearSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleGearLinkage in scene — click "+ Spawn Portcullis Gearbox".';
  FMemoReport.Lines.Text := TGearLinkageHelper.GenerateMarkdownReport(G);
  FPaintTrain.Invalidate;
end;

procedure TGearLinkageForm.BtnSpawnDemoClick(Sender: TObject);
var
  G: TCastleGearLinkage;
begin
  if TGearLinkageHelper.SpawnPortcullisGearboxDemo(FDesignRoot, FDesignOwner, G) then
    NotifyChanged('Spawn Portcullis Compound Gearbox');
end;

procedure TGearLinkageForm.BtnStepCrankClick(Sender: TObject);
var
  G: TCastleGearLinkage;
begin
  G := TGearLinkageHelper.FindFirstLinkage(FDesignRoot);
  if G = nil then Exit;
  G.StepClockwork(1.0);
  NotifyChanged('Crank Portcullis Gearbox (+1.0s)');
end;

procedure TGearLinkageForm.BtnTriggerJamClick(Sender: TObject);
var
  G: TCastleGearLinkage;
begin
  G := TGearLinkageHelper.FindFirstLinkage(FDesignRoot);
  if G = nil then Exit;
  G.ClearMechanism;
  G.AddGearWheel('TriGear_A', Vector3(-0.7, 1.5, 0.0), 20, 0.5);
  G.AddGearWheel('TriGear_B', Vector3(0.7, 1.5, 0.0), 20, 0.5);
  G.AddGearWheel('TriGear_C', Vector3(0.0, 2.5, 0.0), 20, 0.5);
  G.AddCouplingLink(0, 1, glkExternalSpurMesh);
  G.AddCouplingLink(1, 2, glkExternalSpurMesh);
  G.AddCouplingLink(2, 0, glkExternalSpurMesh);
  G.SolveGearTrainKinematics;
  NotifyChanged('Trigger Contradictory 3-Gear Odd Loop Jam');
end;

procedure TGearLinkageForm.BtnBeltPresetClick(Sender: TObject);
var
  G: TCastleGearLinkage;
begin
  G := TGearLinkageHelper.FindFirstLinkage(FDesignRoot);
  if G = nil then Exit;
  G.ApplyPreset(glpBeltDrivenSawmillPulley);
  NotifyChanged('Switch to Belt-Driven Sawmill Pulley');
end;

procedure TGearLinkageForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TGearLinkageForm.PaintGearSchematic(Sender: TObject);
var
  C: TCanvas;
  W, H, I, GX, GY, R: Integer;
  G: TCastleGearLinkage;
  N: TGearWheelNode;
begin
  C := FPaintTrain.Canvas;
  W := FPaintTrain.Width;
  H := FPaintTrain.Height;
  C.Brush.Color := RGBToColor(22, 20, 18);
  C.FillRect(0, 0, W, H);

  G := TGearLinkageHelper.FindFirstLinkage(FDesignRoot);
  if G = nil then Exit;

  for I := 0 to G.NodeCount - 1 do
  begin
    N := G.GetNode(I);
    GX := (W div 2) + Round(N.LocalCenter.X * 110.0);
    GY := (H div 2) + 20 - Round((N.LocalCenter.Y - 1.5) * 80.0);
    if N.IsLinearRack then
    begin
      C.Brush.Color := RGBToColor(150, 165, 185);
      C.FillRect(GX - 12, GY - 60 - Round(N.LinearPositionMeters * 25.0),
                 GX + 12, GY + 60 - Round(N.LinearPositionMeters * 25.0));
    end else
    begin
      R := Max(14, Round(N.PitchRadiusMeters * 58.0));
      if G.IsJammedLoop then
        C.Brush.Color := RGBToColor(215, 65, 55)
      else
        C.Brush.Color := RGBToColor(225, 175, 75);
      C.Ellipse(GX - R, GY - R, GX + R, GY + R);
      C.Pen.Color := RGBToColor(35, 30, 25);
      C.MoveTo(GX, GY);
      C.LineTo(GX + Round(Cos(N.AngleRad) * R), GY - Round(Sin(N.AngleRad) * R));
    end;
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(16, 12, Format('Jammed: %s   |   Nodes: %d   |   Links: %d',
    [BoolToStr(G.IsJammedLoop, True), G.NodeCount, G.LinkCount]));
end;

end.
