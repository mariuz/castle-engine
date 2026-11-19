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

{ Visual Studio dialog for Dynamic Gravity Well, Planetary Walk & Tube Studio (Phase 381). }
unit FormGravityField;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleViewport, CastleGravityField, ToolGravityField;

type
  TGravityFieldModifiedCallback = procedure(const UndoComment: String) of object;
  TGravityFieldRefreshCallback = procedure of object;

  TGravityFieldForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TGravityFieldModifiedCallback;
    FOnRefresh: TGravityFieldRefreshCallback;
    FLblSummary: TLabel;
    FPaintField: TPaintBox;
    FMemoReport: TMemo;
    FProbeAngleRad: Single;
    FActorUp: TVector3;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnOrbitStepClick(Sender: TObject);
    procedure BtnSwitchRingTubeClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintGravityCrossSection(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TGravityFieldModifiedCallback;
      const AOnRefresh: TGravityFieldRefreshCallback);
  end;

implementation

constructor TGravityFieldForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TGravityFieldModifiedCallback;
  const AOnRefresh: TGravityFieldRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FProbeAngleRad := Pi * 0.5;
  FActorUp := Vector3(0, 1, 0);
  Caption := 'Dynamic Gravity Well, Planetary Spherical Walk & Tube Studio';
  Width := 820;
  Height := 580;
  Position := poMainFormCenter;
  BuildUi;
  RefreshView;
end;

procedure TGravityFieldForm.BuildUi;
var
  TopBar, BtnRow: TPanel;
  BtnSpawn, BtnStep, BtnTube, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 6, 220, 30);
  BtnSpawn.Caption := '+ Spawn Planetoid + Inversion Zone';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := BtnRow;
  BtnStep.SetBounds(238, 6, 175, 30);
  BtnStep.Caption := 'Walk Around Sphere (+30 deg)';
  BtnStep.OnClick := @BtnOrbitStepClick;

  BtnTube := TButton.Create(Self);
  BtnTube.Parent := BtnRow;
  BtnTube.SetBounds(421, 6, 185, 30);
  BtnTube.Caption := 'Preset: O''Neill Ringworld Tube';
  BtnTube.OnClick := @BtnSwitchRingTubeClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := BtnRow;
  BtnCopy.SetBounds(614, 6, 110, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := BtnRow;
  BtnClose.SetBounds(730, 6, 76, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;

  FPaintField := TPaintBox.Create(Self);
  FPaintField.Parent := Self;
  FPaintField.Align := alTop;
  FPaintField.Height := 250;
  FPaintField.OnPaint := @PaintGravityCrossSection;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TGravityFieldForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TGravityFieldForm.RefreshView;
var
  Sum: TGravityStudioSummary;
begin
  Sum := TGravityFieldHelper.CollectSummary(FDesignRoot);
  FLblSummary.Caption := Format(
    'Gravity Fields: %d  |  Planets: %d  |  Ringworld Tubes: %d  |  Box Zones: %d  |  Actor Up: (%.2f, %.2f, %.2f)',
    [Sum.FieldCount, Sum.PlanetCount, Sum.TubeCount, Sum.BoxZoneCount,
     FActorUp.X, FActorUp.Y, FActorUp.Z]);
  FMemoReport.Lines.Text := TGravityFieldHelper.BuildMarkdownReport(FDesignRoot);
  FPaintField.Invalidate;
end;

procedure TGravityFieldForm.BtnSpawnDemoClick(Sender: TObject);
var
  Planet, InvZone: TCastleGravityField;
begin
  if TGravityFieldHelper.SpawnPlanetoidAndInversionDemo(FDesignRoot, FDesignOwner, Planet, InvZone) then
    NotifyChanged('Spawn Planetoid & Inversion Gravity Demo');
end;

procedure TGravityFieldForm.BtnOrbitStepClick(Sender: TObject);
var
  Field: TCastleGravityField;
  ProbePos: TVector3;
  S: TGravitySample;
begin
  FProbeAngleRad := FProbeAngleRad - (Pi / 6.0);
  Field := TGravityFieldHelper.FindFirstGravityField(FDesignRoot);
  if Field <> nil then
    ProbePos := Field.WorldTranslation + Vector3(Cos(FProbeAngleRad) * Field.PlanetRadius,
      Sin(FProbeAngleRad) * Field.PlanetRadius, 0.0)
  else
    ProbePos := Vector3(Cos(FProbeAngleRad) * 8.0, Sin(FProbeAngleRad) * 8.0, 0.0);
  S := TCastleGravityField.EvaluateCompositeWorldGravity(FDesignRoot, ProbePos);
  FActorUp := TCastleGravityField.StepSmoothUpVectorSlerp(FActorUp, S.UpVector, 8.0, 0.25);
  RefreshView;
end;

procedure TGravityFieldForm.BtnSwitchRingTubeClick(Sender: TObject);
var
  Field: TCastleGravityField;
begin
  Field := TGravityFieldHelper.FindFirstGravityField(FDesignRoot);
  if Field <> nil then
  begin
    Field.ApplyPreset(gfpONeillRingworldTube);
    NotifyChanged('Switch Gravity Field to O''Neill Ringworld Tube');
  end;
end;

procedure TGravityFieldForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TGravityFieldForm.PaintGravityCrossSection(Sender: TObject);
var
  C: TCanvas;
  CX, CY, R, I, PX, PY, UX, UY: Integer;
  Ang: Single;
  Field: TCastleGravityField;
  SampleP: TVector3;
  S: TGravitySample;
begin
  C := FPaintField.Canvas;
  C.Brush.Color := $001E1914;
  C.FillRect(0, 0, FPaintField.Width, FPaintField.Height);

  CX := FPaintField.Width div 2;
  CY := FPaintField.Height div 2;
  R := 72;

  C.Pen.Color := $00C88838;
  C.Brush.Style := bsClear;
  C.Ellipse(CX - R, CY - R, CX + R, CY + R);
  C.Brush.Style := bsSolid;

  Field := TGravityFieldHelper.FindFirstGravityField(FDesignRoot);
  for I := 0 to 11 do
  begin
    Ang := (2.0 * Pi * I) / 12.0;
    PX := CX + Round(Cos(Ang) * (R + 10));
    PY := CY - Round(Sin(Ang) * (R + 10));
    if Field <> nil then
    begin
      SampleP := Field.WorldTranslation + Vector3(Cos(Ang) * (Field.PlanetRadius * 0.98),
        Sin(Ang) * (Field.PlanetRadius * 0.98), 0.0);
      S := Field.SampleFieldAtWorld(SampleP);
    end else
    begin
      S.UpVector := Vector3(Cos(Ang), Sin(Ang), 0.0);
    end;
    UX := PX + Round(S.UpVector.X * 22);
    UY := PY - Round(S.UpVector.Y * 22);
    C.Pen.Color := $0068E050;
    C.MoveTo(PX, PY);
    C.LineTo(UX, UY);
  end;

  { Highlight current actor probe }
  PX := CX + Round(Cos(FProbeAngleRad) * R);
  PY := CY - Round(Sin(FProbeAngleRad) * R);
  C.Brush.Color := $0040B8FF;
  C.Ellipse(PX - 6, PY - 6, PX + 6, PY + 6);
end;

end.
