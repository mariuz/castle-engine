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

{ Visual Studio dialog for 3D Echolocation & Active Sonar Pulse
  (WorldRay Spherical Ping Wavefront, Two-Way Echo & Doppler Shift) Studio (Phase 414). }
unit FormSonarPulse;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleSonarPulse, ToolSonarPulse;

type
  TSonarPulseModifiedCallback = procedure(const UndoComment: String) of object;
  TSonarPulseRefreshCallback = procedure of object;

  TSonarPulseForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSonarPulseModifiedCallback;
    FOnRefresh: TSonarPulseRefreshCallback;
    FLblSummary: TLabel;
    FPaintScope: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    function ActiveWorldRoot: TCastleAbstractRootTransform;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnEmitPingClick(Sender: TObject);
    procedure BtnStepNearEchoClick(Sender: TObject);
    procedure BtnStepFarEchoClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintPhosphorScope(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSonarPulseModifiedCallback;
      const AOnRefresh: TSonarPulseRefreshCallback);
  end;

implementation

constructor TSonarPulseForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSonarPulseModifiedCallback;
  const AOnRefresh: TSonarPulseRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := '3D Echolocation & Active Sonar Pulse (Wavefront & Doppler) Studio';
  Position := poScreenCenter;
  Width := 780;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TSonarPulseForm.ActiveWorldRoot: TCastleAbstractRootTransform;
var
  I: Integer;
begin
  Result := nil;
  if FDesignRoot = nil then Exit;
  if FDesignRoot is TCastleViewport then
    Exit(TCastleViewport(FDesignRoot).Items);
  for I := 0 to FDesignRoot.ComponentCount - 1 do
    if FDesignRoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(FDesignRoot.Components[I]).Items);
end;

procedure TSonarPulseForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnPing, BtnNear, BtnFar, BtnCopy, BtnClose: TButton;
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
  BtnSpawn.SetBounds(10, 8, 175, 30);
  BtnSpawn.Caption := '+ Spawn Trench Sonar';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnPing := TButton.Create(Self);
  BtnPing.Parent := PnlButtons;
  BtnPing.SetBounds(190, 8, 135, 30);
  BtnPing.Caption := 'Emit New Ping';
  BtnPing.OnClick := @BtnEmitPingClick;

  BtnNear := TButton.Create(Self);
  BtnNear.Parent := PnlButtons;
  BtnNear.SetBounds(330, 8, 145, 30);
  BtnNear.Caption := 'Step +0.7s (Near Echo)';
  BtnNear.OnClick := @BtnStepNearEchoClick;

  BtnFar := TButton.Create(Self);
  BtnFar.Parent := PnlButtons;
  BtnFar.SetBounds(480, 8, 145, 30);
  BtnFar.Caption := 'Step +1.0s (Far Echo)';
  BtnFar.OnClick := @BtnStepFarEchoClick;

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

  FPaintScope := TPaintBox.Create(Self);
  FPaintScope.Parent := Self;
  FPaintScope.Align := alTop;
  FPaintScope.Height := 215;
  FPaintScope.OnPaint := @PaintPhosphorScope;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TSonarPulseForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TSonarPulseForm.RefreshView;
var
  S: TCastleSonarPulse;
begin
  S := TSonarPulseHelper.FindFirstSonar(FDesignRoot);
  if S <> nil then
    FLblSummary.Caption := S.Name + '  ' + S.SonarSummaryBadge
  else
    FLblSummary.Caption := 'No TCastleSonarPulse in scene — click "+ Spawn Trench Sonar".';
  FMemoReport.Lines.Text := TSonarPulseHelper.GenerateMarkdownReport(S);
  FPaintScope.Invalidate;
end;

procedure TSonarPulseForm.BtnSpawnDemoClick(Sender: TObject);
var
  S: TCastleSonarPulse;
begin
  if TSonarPulseHelper.SpawnTrenchSubmarineSonarDemo(FDesignRoot, FDesignOwner, S) then
    NotifyChanged('Spawn Trench Submarine Sonar Demo');
end;

procedure TSonarPulseForm.BtnEmitPingClick(Sender: TObject);
var
  S: TCastleSonarPulse;
begin
  S := TSonarPulseHelper.FindFirstSonar(FDesignRoot);
  if S = nil then Exit;
  S.EmitSonarPing(ActiveWorldRoot);
  NotifyChanged('Emit Active Sonar Ping');
end;

procedure TSonarPulseForm.BtnStepNearEchoClick(Sender: TObject);
var
  S: TCastleSonarPulse;
begin
  S := TSonarPulseHelper.FindFirstSonar(FDesignRoot);
  if S = nil then Exit;
  S.StepPulsePropagation(0.70);
  NotifyChanged('Step Sonar Wavefront (+0.70s)');
end;

procedure TSonarPulseForm.BtnStepFarEchoClick(Sender: TObject);
var
  S: TCastleSonarPulse;
begin
  S := TSonarPulseHelper.FindFirstSonar(FDesignRoot);
  if S = nil then Exit;
  S.StepPulsePropagation(1.00);
  NotifyChanged('Step Sonar Wavefront (+1.00s)');
end;

procedure TSonarPulseForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TSonarPulseForm.PaintPhosphorScope(Sender: TObject);
var
  C: TCanvas;
  W, H, CX, CY, RWave, I, PX, PY, G: Integer;
  S: TCastleSonarPulse;
  Ct: TSonarEchoContact;
begin
  C := FPaintScope.Canvas;
  W := FPaintScope.Width;
  H := FPaintScope.Height;
  C.Brush.Color := RGBToColor(10, 22, 18);
  C.FillRect(0, 0, W, H);

  S := TSonarPulseHelper.FindFirstSonar(FDesignRoot);
  if S = nil then Exit;

  CX := W div 2;
  CY := H div 2;
  C.Brush.Style := bsClear;
  C.Pen.Color := RGBToColor(35, 95, 65);
  C.Ellipse(CX - 90, CY - 90, CX + 90, CY + 90);

  RWave := Min(92, Round(S.WavefrontRadiusMeters * 2.2));
  C.Pen.Color := RGBToColor(70, 245, 165);
  C.Ellipse(CX - RWave, CY - RWave, CX + RWave, CY + RWave);

  C.Brush.Style := bsSolid;
  for I := 0 to S.ContactCount - 1 do
  begin
    Ct := S.GetContact(I);
    if Ct.EchoArrived and (Ct.PhosphorBrightness01 > 0.02) then
    begin
      PX := CX + Round(Ct.WorldHitPos.X * 2.2);
      PY := CY + Round(Ct.WorldHitPos.Z * 2.2);
      G := Round(80 + 175 * Ct.PhosphorBrightness01);
      C.Brush.Color := RGBToColor(40, G, 110);
      C.Ellipse(PX - 6, PY - 6, PX + 6, PY + 6);
    end;
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(16, H - 24, Format('t = %.2f s | Wavefront R = %.1f m | Revealed Blips: %d / %d',
    [S.ElapsedPingSec, S.WavefrontRadiusMeters, S.RevealedContactCount, S.ContactCount]));
end;

end.
