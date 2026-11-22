{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Niagara Modular Emitter Stack & Curve Editor dialog
  featuring the 4-stage Niagara Emitter Stack card (Emitter Spawn, Emitter
  Update, Particle Spawn, Particle Update), live XY particle & collision preview,
  a 4-key Size-over-Life LUT curve editor, and module reordering/toggling
  (Phase 385 — 105 UE Studios / 28 MCP). }
unit FormNiagaraStack;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleNiagaraStack, ToolNiagaraStack;

type
  TNiagaraStackModifiedCallback = procedure(const UndoComment: String) of object;
  TNiagaraStackRefreshCallback = procedure of object;

  TNiagaraStackForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TNiagaraStackModifiedCallback;
    FOnRefresh: TNiagaraStackRefreshCallback;

    FActiveSys: TCastleNiagaraSystem;
    FSelectedModuleId: String;

    FLblStatus: TLabel;
    FPaintStack: TPaintBox;
    FPaintPreview: TPaintBox;
    FPaintCurve: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);
    function StageHeaderColor(const AStage: TNiagaraStackStage): TColor;

    procedure PaintStackCanvas(Sender: TObject);
    procedure PaintParticlePreview(Sender: TObject);
    procedure PaintCurveEditor(Sender: TObject);
    procedure StackMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure BtnSpawnVortexClick(Sender: TObject);
    procedure BtnSpawnSparksClick(Sender: TObject);
    procedure BtnStepSimClick(Sender: TObject);
    procedure BtnToggleModClick(Sender: TObject);
    procedure BtnMoveUpClick(Sender: TObject);
    procedure BtnMoveDownClick(Sender: TObject);
    procedure BtnResetSimClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TNiagaraStackModifiedCallback;
      const AOnRefresh: TNiagaraStackRefreshCallback);
  end;

implementation

constructor TNiagaraStackForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TNiagaraStackModifiedCallback;
  const AOnRefresh: TNiagaraStackRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Niagara Modular Emitter Stack & Curve Editor (105 UE Studios / 28 MCP)';
  Position := poScreenCenter;
  Width := 1160;
  Height := 710;

  BuildUi;
  FActiveSys := TNiagaraStackHelper.FindFirstNiagaraSystem(FDesignRoot);
  RefreshFromScene;
end;

procedure TNiagaraStackForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlRight, PnlCurveHost, PnlBottom: TPanel;
  BtnVortex, BtnSparks, BtnStep, BtnTog, BtnUp, BtnDn, BtnReset, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 34;
  PnlTop.BevelOuter := bvNone;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 10;
  FLblStatus.Top := 9;
  FLblStatus.Caption := 'Niagara Modular Emitter Stack Ready.';

  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;

  BtnVortex := TButton.Create(Self);
  BtnVortex.Parent := PnlToolbar;
  BtnVortex.SetBounds(8, 6, 152, 30);
  BtnVortex.Caption := '+ Vortex Portal Stack';
  BtnVortex.OnClick := @BtnSpawnVortexClick;

  BtnSparks := TButton.Create(Self);
  BtnSparks.Parent := PnlToolbar;
  BtnSparks.SetBounds(164, 6, 158, 30);
  BtnSparks.Caption := '+ Collision Sparks Stack';
  BtnSparks.OnClick := @BtnSpawnSparksClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlToolbar;
  BtnStep.SetBounds(326, 6, 114, 30);
  BtnStep.Caption := 'Step +0.10s';
  BtnStep.OnClick := @BtnStepSimClick;

  BtnTog := TButton.Create(Self);
  BtnTog.Parent := PnlToolbar;
  BtnTog.SetBounds(444, 6, 118, 30);
  BtnTog.Caption := 'Toggle Module';
  BtnTog.OnClick := @BtnToggleModClick;

  BtnUp := TButton.Create(Self);
  BtnUp.Parent := PnlToolbar;
  BtnUp.SetBounds(566, 6, 86, 30);
  BtnUp.Caption := 'Move Up';
  BtnUp.OnClick := @BtnMoveUpClick;

  BtnDn := TButton.Create(Self);
  BtnDn.Parent := PnlToolbar;
  BtnDn.SetBounds(656, 6, 94, 30);
  BtnDn.Caption := 'Move Down';
  BtnDn.OnClick := @BtnMoveDownClick;

  BtnReset := TButton.Create(Self);
  BtnReset.Parent := PnlToolbar;
  BtnReset.SetBounds(754, 6, 88, 30);
  BtnReset.Caption := 'Reset Sim';
  BtnReset.OnClick := @BtnResetSimClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlToolbar;
  BtnCopy.SetBounds(846, 6, 126, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyMarkdownClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 150;
  PnlBottom.BevelOuter := bvNone;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := PnlBottom;
  FMemoReport.Align := alClient;
  FMemoReport.ScrollBars := ssVertical;
  FMemoReport.ReadOnly := True;
  FMemoReport.Font.Name := 'Monospace';

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.Align := alRight;
  BtnClose.Width := 74;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 420;
  PnlRight.BevelOuter := bvLowered;

  PnlCurveHost := TPanel.Create(Self);
  PnlCurveHost.Parent := PnlRight;
  PnlCurveHost.Align := alBottom;
  PnlCurveHost.Height := 175;
  PnlCurveHost.BevelOuter := bvLowered;

  FPaintCurve := TPaintBox.Create(Self);
  FPaintCurve.Parent := PnlCurveHost;
  FPaintCurve.Align := alClient;
  FPaintCurve.OnPaint := @PaintCurveEditor;

  FPaintPreview := TPaintBox.Create(Self);
  FPaintPreview.Parent := PnlRight;
  FPaintPreview.Align := alClient;
  FPaintPreview.OnPaint := @PaintParticlePreview;

  FPaintStack := TPaintBox.Create(Self);
  FPaintStack.Parent := Self;
  FPaintStack.Align := alClient;
  FPaintStack.OnPaint := @PaintStackCanvas;
  FPaintStack.OnMouseDown := @StackMouseDown;
end;

procedure TNiagaraStackForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TNiagaraStackForm.RefreshFromScene;
begin
  if (FActiveSys = nil) and (FDesignRoot <> nil) then
    FActiveSys := TNiagaraStackHelper.FindFirstNiagaraSystem(FDesignRoot);

  if FActiveSys <> nil then
  begin
    if (FSelectedModuleId = '') and (Length(FActiveSys.Modules) > 0) then
      FSelectedModuleId := FActiveSys.Modules[0].ModuleId;
    FLblStatus.Caption := FActiveSys.Name + '  ' + FActiveSys.NiagaraSummaryBadge;
  end else
    FLblStatus.Caption := 'No TCastleNiagaraSystem in design yet — click "+ Vortex Portal Stack".';

  FMemoReport.Text := TNiagaraStackHelper.GenerateMarkdownReport(FDesignRoot, FActiveSys);
  FPaintStack.Invalidate;
  FPaintPreview.Invalidate;
  FPaintCurve.Invalidate;
end;

function TNiagaraStackForm.StageHeaderColor(const AStage: TNiagaraStackStage): TColor;
begin
  case AStage of
    nssEmitterSpawn,
    nssEmitterUpdate:  Result := RGBToColor(38, 96, 168);
  else
    Result := RGBToColor(40, 128, 72);
  end;
end;

procedure TNiagaraStackForm.PaintStackCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, CardL, CardR, YCursor, I: Integer;
  St: TNiagaraStackStage;
  M: TNiagaraModule;
begin
  C := FPaintStack.Canvas;
  W := FPaintStack.Width;
  H := FPaintStack.Height;

  C.Brush.Color := RGBToColor(26, 28, 33);
  C.FillRect(0, 0, W, H);

  if FActiveSys = nil then Exit;

  CardL := 28;
  CardR := Max(CardL + 280, W - 28);
  YCursor := 16;

  { UE5 Niagara Orange Emitter Header }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(196, 98, 28);
  C.Pen.Color := RGBToColor(18, 20, 24);
  C.RoundRect(CardL, YCursor, CardR, YCursor + 34, 8, 8);
  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(CardL + 12, YCursor + 9, 'NE_' + FActiveSys.Name + '  (4-Stage Modular Stack)');
  Inc(YCursor, 40);

  for St in TNiagaraStackStage do
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := StageHeaderColor(St);
    C.FillRect(CardL, YCursor, CardR, YCursor + 24);
    C.Brush.Style := bsClear;
    C.Font.Color := clWhite;
    C.TextOut(CardL + 10, YCursor + 4, TCastleNiagaraSystem.StageTitle(St));
    Inc(YCursor, 26);

    for I := 0 to High(FActiveSys.Modules) do
      if FActiveSys.Modules[I].Stage = St then
      begin
        M := FActiveSys.Modules[I];
        C.Brush.Style := bsSolid;
        if SameText(FSelectedModuleId, M.ModuleId) then
          C.Brush.Color := RGBToColor(62, 72, 92)
        else
          C.Brush.Color := RGBToColor(42, 46, 54);
        C.Pen.Color := RGBToColor(24, 26, 30);
        C.Rectangle(CardL + 8, YCursor, CardR - 8, YCursor + 26);

        { Enable checkbox indicator }
        if M.Enabled then
          C.Brush.Color := RGBToColor(78, 222, 118)
        else
          C.Brush.Color := RGBToColor(96, 96, 104);
        C.Rectangle(CardL + 16, YCursor + 6, CardL + 28, YCursor + 18);

        C.Brush.Style := bsClear;
        C.Font.Color := RGBToColor(225, 232, 242);
        C.TextOut(CardL + 36, YCursor + 5,
          TCastleNiagaraSystem.ModuleKindTitle(M.Kind) + '  [' + M.ModuleId + ']');
        Inc(YCursor, 28);
      end;
    Inc(YCursor, 8);
  end;
end;

procedure TNiagaraStackForm.PaintParticlePreview(Sender: TObject);
var
  C: TCanvas;
  W, H, CX, FloorY, PX, PY, Rad, I: Integer;
  P: TNiagaraParticle;
begin
  C := FPaintPreview.Canvas;
  W := FPaintPreview.Width;
  H := FPaintPreview.Height;

  C.Brush.Color := RGBToColor(16, 18, 24);
  C.FillRect(0, 0, W, H);

  CX := W div 2;
  FloorY := H - 48;
  C.Pen.Color := RGBToColor(68, 76, 92);
  C.Line(12, FloorY, W - 12, FloorY);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(145, 212, 255);
  C.TextOut(10, 8, 'Niagara Live XY Viewport');

  if FActiveSys = nil then Exit;

  for I := 0 to High(FActiveSys.Particles) do
    if FActiveSys.Particles[I].Alive then
    begin
      P := FActiveSys.Particles[I];
      PX := CX + Round(P.Position.X * 36.0);
      PY := FloorY - Round(P.Position.Y * 36.0);
      Rad := Max(2, Round(P.CurrentSize * 26.0));
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(
        EnsureRange(Round(P.ColorRGBA.X * 255), 0, 255),
        EnsureRange(Round(P.ColorRGBA.Y * 255), 0, 255),
        EnsureRange(Round(P.ColorRGBA.Z * 255), 0, 255));
      C.Pen.Color := C.Brush.Color;
      C.Ellipse(PX - Rad, PY - Rad, PX + Rad + 1, PY + Rad + 1);
    end;
end;

procedure TNiagaraStackForm.PaintCurveEditor(Sender: TObject);
var
  C: TCanvas;
  W, H, LPad, RPad, TPad, BPad, S, X0, Y0, X1, Y1: Integer;
  CurveVal: TNiagaraFloatCurve;
  T0, T1, V0, V1: Single;
begin
  C := FPaintCurve.Canvas;
  W := FPaintCurve.Width;
  H := FPaintCurve.Height;

  C.Brush.Color := RGBToColor(22, 24, 30);
  C.FillRect(0, 0, W, H);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(200, 212, 228);
  C.TextOut(10, 6, 'Scale Size by Life Curve (NormalizedAge 0..1)');

  LPad := 24; RPad := W - 18; TPad := 28; BPad := H - 18;
  C.Pen.Color := RGBToColor(58, 66, 78);
  C.Rectangle(LPad, TPad, RPad, BPad);

  CurveVal := TNiagaraFloatCurve.DefaultBellCurve;
  C.Pen.Color := RGBToColor(96, 232, 148);
  C.Pen.Width := 2;
  for S := 0 to 31 do
  begin
    T0 := S / 32.0;
    T1 := (S + 1) / 32.0;
    V0 := CurveVal.Evaluate(T0);
    V1 := CurveVal.Evaluate(T1);
    X0 := LPad + Round(T0 * (RPad - LPad));
    X1 := LPad + Round(T1 * (RPad - LPad));
    Y0 := BPad - Round((V0 / 1.5) * (BPad - TPad));
    Y1 := BPad - Round((V1 / 1.5) * (BPad - TPad));
    C.Line(X0, Y0, X1, Y1);
  end;
end;

procedure TNiagaraStackForm.StackMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  YCursor, I: Integer;
  St: TNiagaraStackStage;
begin
  if (FActiveSys = nil) or (Button <> mbLeft) then Exit;
  YCursor := 56;
  for St in TNiagaraStackStage do
  begin
    Inc(YCursor, 26);
    for I := 0 to High(FActiveSys.Modules) do
      if FActiveSys.Modules[I].Stage = St then
      begin
        if (Y >= YCursor) and (Y <= YCursor + 26) then
        begin
          FSelectedModuleId := FActiveSys.Modules[I].ModuleId;
          FPaintStack.Invalidate;
          Exit;
        end;
        Inc(YCursor, 28);
      end;
    Inc(YCursor, 8);
  end;
end;

procedure TNiagaraStackForm.BtnSpawnVortexClick(Sender: TObject);
begin
  FActiveSys := TNiagaraStackHelper.SpawnNiagaraPresetInDesign(
    FDesignRoot, FDesignOwner, nspArcaneVortexPortal, Vector3(0, 0, 0));
  FActiveSys.StepSystem(0.35);
  NotifyChanged('Spawn Niagara Vortex Stack');
end;

procedure TNiagaraStackForm.BtnSpawnSparksClick(Sender: TObject);
begin
  FActiveSys := TNiagaraStackHelper.SpawnNiagaraPresetInDesign(
    FDesignRoot, FDesignOwner, nspAnvilSparksCollisionBurst, Vector3(3, 0, 0));
  FActiveSys.StepSystem(0.25);
  NotifyChanged('Spawn Niagara Collision Sparks Stack');
end;

procedure TNiagaraStackForm.BtnStepSimClick(Sender: TObject);
begin
  if FActiveSys = nil then Exit;
  FActiveSys.StepSystem(0.10);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshFromScene;
end;

procedure TNiagaraStackForm.BtnToggleModClick(Sender: TObject);
begin
  if (FActiveSys = nil) or (FSelectedModuleId = '') then Exit;
  FActiveSys.ToggleModuleEnabled(FSelectedModuleId);
  NotifyChanged('Toggle Niagara Module');
end;

procedure TNiagaraStackForm.BtnMoveUpClick(Sender: TObject);
begin
  if (FActiveSys = nil) or (FSelectedModuleId = '') then Exit;
  if FActiveSys.MoveModuleOrder(FSelectedModuleId, -1) then
    NotifyChanged('Move Niagara Module Up');
end;

procedure TNiagaraStackForm.BtnMoveDownClick(Sender: TObject);
begin
  if (FActiveSys = nil) or (FSelectedModuleId = '') then Exit;
  if FActiveSys.MoveModuleOrder(FSelectedModuleId, 1) then
    NotifyChanged('Move Niagara Module Down');
end;

procedure TNiagaraStackForm.BtnResetSimClick(Sender: TObject);
begin
  if FActiveSys = nil then Exit;
  FActiveSys.ResetSimulation;
  RefreshFromScene;
end;

procedure TNiagaraStackForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Text;
end;

end.
