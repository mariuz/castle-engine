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

{ Unreal Engine 5.5-style Physics Asset Editor (PhAT / UPhysicsAsset) dialog
  featuring an interactive ragdoll capsule/sphere/box & Swing1/Swing2 joint-cone
  viewport, 11-body mass & Kinematic/Simulated inspector, Bone-Pair Collision
  Disable Matrix controls, and interactive limb poke impulse testing
  (Phase 388 — 108 UE Studios / 31 MCP). }
unit FormPhysicsAsset;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastlePhysicsAsset, ToolPhysicsAsset;

type
  TPhAtModifiedCallback = procedure(const UndoComment: String) of object;
  TPhAtRefreshCallback = procedure of object;

  TPhysicsAssetForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TPhAtModifiedCallback;
    FOnRefresh: TPhAtRefreshCallback;

    FActiveAsset: TCastlePhysicsAsset;
    FSelectedBodyIdx: Integer;

    FLblStatus: TLabel;
    FPaintViewport: TPaintBox;
    FPaintHierarchy: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintPhAtViewport(Sender: TObject);
    procedure PaintPhAtBodiesList(Sender: TObject);
    procedure BodiesListMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure BtnSpawnRagdollClick(Sender: TObject);
    procedure BtnSpawnPinnedClick(Sender: TObject);
    procedure BtnPokeLimbClick(Sender: TObject);
    procedure BtnStepSimClick(Sender: TObject);
    procedure BtnToggleKinematicClick(Sender: TObject);
    procedure BtnResetPoseClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TPhAtModifiedCallback;
      const AOnRefresh: TPhAtRefreshCallback);
  end;

implementation

constructor TPhysicsAssetForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TPhAtModifiedCallback;
  const AOnRefresh: TPhAtRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FSelectedBodyIdx := 4; { LowerArm_L }

  Caption := 'Physics Asset Editor (PhAT — Capsules, Swing1/Swing2 Cones & Ragdoll Poke) (108 UE Studios / 31 MCP)';
  Position := poScreenCenter;
  Width := 1260;
  Height := 720;

  BuildUi;
  FActiveAsset := TPhysicsAssetHelper.FindFirstPhysicsAsset(FDesignRoot);
  RefreshFromScene;
end;

procedure TPhysicsAssetForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlRight, PnlBottom: TPanel;
  BtnRag, BtnPin, BtnPoke, BtnStep, BtnKin, BtnReset, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 32;
  PnlTop.BevelOuter := bvNone;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 10;
  FLblStatus.Top := 8;
  FLblStatus.Caption := 'Physics Asset Editor (PhAT) Ready.';

  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;

  BtnRag := TButton.Create(Self);
  BtnRag.Parent := PnlToolbar;
  BtnRag.SetBounds(8, 6, 174, 30);
  BtnRag.Caption := '+ 11-Body Ragdoll Asset';
  BtnRag.OnClick := @BtnSpawnRagdollClick;

  BtnPin := TButton.Create(Self);
  BtnPin.Parent := PnlToolbar;
  BtnPin.SetBounds(186, 6, 182, 30);
  BtnPin.Caption := '+ Pinned Hanging Test';
  BtnPin.OnClick := @BtnSpawnPinnedClick;

  BtnPoke := TButton.Create(Self);
  BtnPoke.Parent := PnlToolbar;
  BtnPoke.SetBounds(372, 6, 168, 30);
  BtnPoke.Caption := 'Poke Selected (+35 Ns)';
  BtnPoke.OnClick := @BtnPokeLimbClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlToolbar;
  BtnStep.SetBounds(544, 6, 128, 30);
  BtnStep.Caption := 'Step Sim +0.04s';
  BtnStep.OnClick := @BtnStepSimClick;

  BtnKin := TButton.Create(Self);
  BtnKin.Parent := PnlToolbar;
  BtnKin.SetBounds(676, 6, 166, 30);
  BtnKin.Caption := 'Toggle Kinematic Pin';
  BtnKin.OnClick := @BtnToggleKinematicClick;

  BtnReset := TButton.Create(Self);
  BtnReset.Parent := PnlToolbar;
  BtnReset.SetBounds(846, 6, 108, 30);
  BtnReset.Caption := 'Reset Pose';
  BtnReset.OnClick := @BtnResetPoseClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlToolbar;
  BtnCopy.SetBounds(958, 6, 128, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyMarkdownClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 136;
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
  PnlRight.Width := 460;
  PnlRight.BevelOuter := bvLowered;

  FPaintHierarchy := TPaintBox.Create(Self);
  FPaintHierarchy.Parent := PnlRight;
  FPaintHierarchy.Align := alClient;
  FPaintHierarchy.OnPaint := @PaintPhAtBodiesList;
  FPaintHierarchy.OnMouseDown := @BodiesListMouseDown;

  FPaintViewport := TPaintBox.Create(Self);
  FPaintViewport.Parent := Self;
  FPaintViewport.Align := alClient;
  FPaintViewport.OnPaint := @PaintPhAtViewport;
end;

procedure TPhysicsAssetForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TPhysicsAssetForm.RefreshFromScene;
begin
  if (FActiveAsset = nil) and (FDesignRoot <> nil) then
    FActiveAsset := TPhysicsAssetHelper.FindFirstPhysicsAsset(FDesignRoot);

  if FActiveAsset <> nil then
    FLblStatus.Caption := FActiveAsset.Name + '  ' + FActiveAsset.PhAtSummaryBadge +
      Format('  DisabledPairs=%d  Pokes=%d',
        [FActiveAsset.DisabledPairCount, FActiveAsset.PokeImpulseCount])
  else
    FLblStatus.Caption := 'No TCastlePhysicsAsset in design — click "+ 11-Body Ragdoll Asset".';

  FMemoReport.Text := TPhysicsAssetHelper.GenerateMarkdownReport(FDesignRoot, FActiveAsset);
  FPaintViewport.Invalidate;
  FPaintHierarchy.Invalidate;
end;

procedure TPhysicsAssetForm.PaintPhAtViewport(Sender: TObject);

  function ProjPt(const V: TVector3; const CX, FloorY: Integer; const ScalePx: Single): TPoint;
  begin
    Result.X := CX + Round((V.X * 0.94 + V.Z * 0.36) * ScalePx);
    Result.Y := FloorY - Round(V.Y * ScalePx);
  end;

var
  C: TCanvas;
  W, H, CX, FloorY, I, RadPx, HalfH: Integer;
  ScalePx, ConeRad: Single;
  PP, PC, ConeL, ConeR: TPoint;
  Rest2D: TVector2;
begin
  C := FPaintViewport.Canvas;
  W := FPaintViewport.Width;
  H := FPaintViewport.Height;

  C.Brush.Color := RGBToColor(18, 20, 26);
  C.FillRect(0, 0, W, H);

  CX := W div 2;
  FloorY := H - 52;
  ScalePx := 210.0;

  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(68, 78, 96);
  C.Line(20, FloorY, W - 20, FloorY);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(148, 206, 255);
  C.TextOut(14, 10, 'PhAT Viewport (Capsules, Kinematic Pins & Swing1/Swing2 Cones)');

  if FActiveAsset = nil then Exit;

  { 1. Draw Swing1/Swing2 Angular Constraint Cones & Joint Links }
  for I := 0 to High(FActiveAsset.Constraints) do
  begin
    PP := ProjPt(FActiveAsset.Bodies[FActiveAsset.Constraints[I].ParentBodyIndex].Position, CX, FloorY, ScalePx);
    PC := ProjPt(FActiveAsset.Bodies[FActiveAsset.Constraints[I].ChildBodyIndex].Position,  CX, FloorY, ScalePx);

    { Yellow Swing Cone Wedge }
    Rest2D := Vector2(FActiveAsset.Constraints[I].RestDir.X, -FActiveAsset.Constraints[I].RestDir.Y);
    if Rest2D.LengthSqr < 1e-4 then Rest2D := Vector2(0, 1) else Rest2D := Rest2D.Normalize;
    ConeRad := DegToRad(FActiveAsset.Constraints[I].Swing2LimitDeg);
    ConeL.X := PP.X + Round((Rest2D.X * Cos(ConeRad) - Rest2D.Y * Sin(ConeRad)) * 34);
    ConeL.Y := PP.Y + Round((Rest2D.X * Sin(ConeRad) + Rest2D.Y * Cos(ConeRad)) * 34);
    ConeR.X := PP.X + Round((Rest2D.X * Cos(-ConeRad) - Rest2D.Y * Sin(-ConeRad)) * 34);
    ConeR.Y := PP.Y + Round((Rest2D.X * Sin(-ConeRad) + Rest2D.Y * Cos(-ConeRad)) * 34);

    C.Pen.Width := 1;
    C.Pen.Color := RGBToColor(238, 192, 62);
    C.Line(PP.X, PP.Y, ConeL.X, ConeL.Y);
    C.Line(PP.X, PP.Y, ConeR.X, ConeR.Y);
    C.Line(ConeL.X, ConeL.Y, ConeR.X, ConeR.Y);

    C.Pen.Width := 2;
    C.Pen.Color := RGBToColor(112, 168, 232);
    C.Line(PP.X, PP.Y, PC.X, PC.Y);
  end;

  { 2. Draw Fitted Collision Bodies }
  for I := 0 to High(FActiveAsset.Bodies) do
  begin
    PP := ProjPt(FActiveAsset.Bodies[I].Position, CX, FloorY, ScalePx);
    RadPx := Max(8, Round(FActiveAsset.Bodies[I].Radius * ScalePx));
    HalfH := Max(RadPx, Round((FActiveAsset.Bodies[I].LengthMeters * 0.5 + FActiveAsset.Bodies[I].Radius) * ScalePx));

    C.Brush.Style := bsSolid;
    if FActiveAsset.Bodies[I].PhysicsType = pptKinematic then
      C.Brush.Color := RGBToColor(196, 88, 38)
    else if I = FSelectedBodyIdx then
      C.Brush.Color := RGBToColor(52, 148, 96)
    else
      C.Brush.Color := RGBToColor(38, 86, 132);

    if I = FSelectedBodyIdx then
    begin
      C.Pen.Width := 2;
      C.Pen.Color := RGBToColor(96, 244, 152);
    end else
    begin
      C.Pen.Width := 1;
      C.Pen.Color := RGBToColor(156, 214, 255);
    end;

    case FActiveAsset.Bodies[I].ShapeKind of
      pskSphere:
        C.Ellipse(PP.X - RadPx, PP.Y - RadPx, PP.X + RadPx, PP.Y + RadPx);
      pskBox:
        C.Rectangle(PP.X - RadPx - 8, PP.Y - RadPx, PP.X + RadPx + 8, PP.Y + RadPx);
      pskCapsule:
        C.RoundRect(PP.X - RadPx, PP.Y - HalfH, PP.X + RadPx, PP.Y + HalfH, RadPx * 2, RadPx * 2);
    end;
  end;
end;

procedure TPhysicsAssetForm.PaintPhAtBodiesList(Sender: TObject);
var
  C: TCanvas;
  W, H, YRow, I: Integer;
  B: TPhAtBodySetup;
begin
  C := FPaintHierarchy.Canvas;
  W := FPaintHierarchy.Width;
  H := FPaintHierarchy.Height;

  C.Brush.Color := RGBToColor(24, 26, 32);
  C.FillRect(0, 0, W, H);

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(36, 42, 54);
  C.FillRect(0, 0, W, 30);
  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(12, 7, 'Skeletal Body Setups & Constraints (Click to select)');

  if FActiveAsset = nil then Exit;

  YRow := 36;
  for I := 0 to High(FActiveAsset.Bodies) do
  begin
    B := FActiveAsset.Bodies[I];
    C.Brush.Style := bsSolid;
    if I = FSelectedBodyIdx then
      C.Brush.Color := RGBToColor(54, 68, 92)
    else
      C.Brush.Color := RGBToColor(34, 38, 46);
    C.Pen.Color := RGBToColor(20, 22, 26);
    C.Rectangle(8, YRow, W - 8, YRow + 36);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(228, 236, 248);
    C.TextOut(16, YRow + 9, Format('%s  [%s]',
      [B.BodyName, TCastlePhysicsAsset.ShapeKindTitle(B.ShapeKind)]));

    if B.PhysicsType = pptKinematic then
      C.Font.Color := RGBToColor(255, 168, 86)
    else
      C.Font.Color := RGBToColor(118, 232, 158);
    C.TextOut(W - 210, YRow + 9, Format('%s  (%.1f kg)',
      [BoolToStr(B.PhysicsType = pptKinematic, 'Kinematic', 'Simulated'), B.MassKg]));

    Inc(YRow, 39);
  end;
end;

procedure TPhysicsAssetForm.BodiesListMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  if FActiveAsset = nil then Exit;
  Idx := (Y - 36) div 39;
  if (Idx >= 0) and (Idx <= High(FActiveAsset.Bodies)) then
  begin
    FSelectedBodyIdx := Idx;
    FPaintViewport.Invalidate;
    FPaintHierarchy.Invalidate;
  end;
end;

procedure TPhysicsAssetForm.BtnSpawnRagdollClick(Sender: TObject);
begin
  FActiveAsset := TPhysicsAssetHelper.SpawnPhysicsAssetPresetInDesign(
    FDesignRoot, FDesignOwner, papHumanoidRagdoll11Bodies, Vector3(0, 0, 0));
  NotifyChanged('Spawn PhAT 11-Body Ragdoll Asset');
end;

procedure TPhysicsAssetForm.BtnSpawnPinnedClick(Sender: TObject);
begin
  FActiveAsset := TPhysicsAssetHelper.SpawnPhysicsAssetPresetInDesign(
    FDesignRoot, FDesignOwner, papKinematicPinnedUpperBodyTest, Vector3(2.5, 0, 0));
  NotifyChanged('Spawn PhAT Kinematic Pinned Ragdoll');
end;

procedure TPhysicsAssetForm.BtnPokeLimbClick(Sender: TObject);
begin
  if (FActiveAsset = nil) or (FSelectedBodyIdx < 0) or
     (FSelectedBodyIdx > High(FActiveAsset.Bodies)) then Exit;
  FActiveAsset.ApplyPokeImpulse(
    FActiveAsset.Bodies[FSelectedBodyIdx].BodyName, Vector3(28.0, 14.0, 12.0));
  FActiveAsset.StepSimulation(0.04);
  RefreshFromScene;
end;

procedure TPhysicsAssetForm.BtnStepSimClick(Sender: TObject);
begin
  if FActiveAsset = nil then Exit;
  FActiveAsset.StepSimulation(0.04);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshFromScene;
end;

procedure TPhysicsAssetForm.BtnToggleKinematicClick(Sender: TObject);
var
  CurType: TPhAtPhysicsType;
begin
  if (FActiveAsset = nil) or (FSelectedBodyIdx < 0) or
     (FSelectedBodyIdx > High(FActiveAsset.Bodies)) then Exit;
  CurType := FActiveAsset.Bodies[FSelectedBodyIdx].PhysicsType;
  if CurType = pptKinematic then
    FActiveAsset.SetBodyPhysicsType(FActiveAsset.Bodies[FSelectedBodyIdx].BodyName, pptSimulated)
  else
    FActiveAsset.SetBodyPhysicsType(FActiveAsset.Bodies[FSelectedBodyIdx].BodyName, pptKinematic);
  NotifyChanged('Toggle PhAT Body Kinematic Pin');
end;

procedure TPhysicsAssetForm.BtnResetPoseClick(Sender: TObject);
begin
  if FActiveAsset = nil then Exit;
  FActiveAsset.ResetToRestPose;
  RefreshFromScene;
end;

procedure TPhysicsAssetForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Text;
end;

end.
