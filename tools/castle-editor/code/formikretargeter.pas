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

{ Unreal Engine 5.5-style Skeletal IK Retargeter dialog featuring a side-by-side
  Source vs. Target 16-joint skeleton viewport, 7-chain mapping inspector with
  FK/IK blend bars, T-pose <-> A-pose Reference Delta Compensation toggle, and
  stride-scaled Foot/Hand IK playback (Phase 387 — 107 UE Studios / 30 MCP). }
unit FormIkRetargeter;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleIkRetargeter, ToolIkRetargeter;

type
  TIkRetargetModifiedCallback = procedure(const UndoComment: String) of object;
  TIkRetargetRefreshCallback = procedure of object;

  TIkRetargeterForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TIkRetargetModifiedCallback;
    FOnRefresh: TIkRetargetRefreshCallback;

    FActiveRig: TCastleIkRetargeter;
    FSelectedChainIdx: Integer;

    FLblStatus: TLabel;
    FPaintRigs: TPaintBox;
    FPaintChains: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure DrawHumanoidSkeleton(const C: TCanvas; const APose: TIkHumanoidPose;
      const ACenterX, AFloorY: Integer; const APxPerMeter: Single;
      const ABoneColor, AJointColor: TColor; const ALabel: String);
    procedure PaintRigsCanvas(Sender: TObject);
    procedure PaintChainsCanvas(Sender: TObject);
    procedure ChainsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure BtnSpawnCompactClick(Sender: TObject);
    procedure BtnSpawnOgreClick(Sender: TObject);
    procedure BtnSpawnTwoHandClick(Sender: TObject);
    procedure BtnStepWalkClick(Sender: TObject);
    procedure BtnToggleRefCompClick(Sender: TObject);
    procedure BtnToggleChainIkClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TIkRetargetModifiedCallback;
      const AOnRefresh: TIkRetargetRefreshCallback);
  end;

implementation

constructor TIkRetargeterForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TIkRetargetModifiedCallback;
  const AOnRefresh: TIkRetargetRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FSelectedChainIdx := Ord(ircLeftLeg);

  Caption := 'Skeletal IK Retargeter — UIKRetargeter & 7-Chain FK/IK Mapper (108 UE Studios / 31 MCP)';
  Position := poScreenCenter;
  Width := 1280;
  Height := 720;

  BuildUi;
  FActiveRig := TIkRetargeterHelper.FindFirstIkRetargeter(FDesignRoot);
  RefreshFromScene;
end;

procedure TIkRetargeterForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlRight, PnlBottom: TPanel;
  BtnCompact, BtnOgre, BtnTwoHand, BtnStep, BtnRefDelta, BtnTogIk, BtnCopy, BtnClose: TButton;
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
  FLblStatus.Caption := 'Skeletal IK Retargeter Ready.';

  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;

  BtnCompact := TButton.Create(Self);
  BtnCompact.Parent := PnlToolbar;
  BtnCompact.SetBounds(8, 6, 192, 30);
  BtnCompact.Caption := '+ Manny -> Compact A-Pose';
  BtnCompact.OnClick := @BtnSpawnCompactClick;

  BtnOgre := TButton.Create(Self);
  BtnOgre.Parent := PnlToolbar;
  BtnOgre.SetBounds(204, 6, 168, 30);
  BtnOgre.Caption := '+ Manny -> Brute Ogre';
  BtnOgre.OnClick := @BtnSpawnOgreClick;

  BtnTwoHand := TButton.Create(Self);
  BtnTwoHand.Parent := PnlToolbar;
  BtnTwoHand.SetBounds(376, 6, 166, 30);
  BtnTwoHand.Caption := '+ Two-Handed Grip IK';
  BtnTwoHand.OnClick := @BtnSpawnTwoHandClick;

  BtnStep := TButton.Create(Self);
  BtnStep.Parent := PnlToolbar;
  BtnStep.SetBounds(546, 6, 132, 30);
  BtnStep.Caption := 'Step Walk +0.12s';
  BtnStep.OnClick := @BtnStepWalkClick;

  BtnRefDelta := TButton.Create(Self);
  BtnRefDelta.Parent := PnlToolbar;
  BtnRefDelta.SetBounds(682, 6, 168, 30);
  BtnRefDelta.Caption := 'Toggle T/A-Pose Delta';
  BtnRefDelta.OnClick := @BtnToggleRefCompClick;

  BtnTogIk := TButton.Create(Self);
  BtnTogIk.Parent := PnlToolbar;
  BtnTogIk.SetBounds(854, 6, 150, 30);
  BtnTogIk.Caption := 'Toggle Chain FK/IK';
  BtnTogIk.OnClick := @BtnToggleChainIkClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlToolbar;
  BtnCopy.SetBounds(1008, 6, 128, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyMarkdownClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 142;
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
  PnlRight.Width := 430;
  PnlRight.BevelOuter := bvLowered;

  FPaintChains := TPaintBox.Create(Self);
  FPaintChains.Parent := PnlRight;
  FPaintChains.Align := alClient;
  FPaintChains.OnPaint := @PaintChainsCanvas;
  FPaintChains.OnMouseDown := @ChainsMouseDown;

  FPaintRigs := TPaintBox.Create(Self);
  FPaintRigs.Parent := Self;
  FPaintRigs.Align := alClient;
  FPaintRigs.OnPaint := @PaintRigsCanvas;
end;

procedure TIkRetargeterForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TIkRetargeterForm.RefreshFromScene;
begin
  if (FActiveRig = nil) and (FDesignRoot <> nil) then
    FActiveRig := TIkRetargeterHelper.FindFirstIkRetargeter(FDesignRoot);

  if FActiveRig <> nil then
    FLblStatus.Caption := Format('%s  (%s -> %s)  RefDelta=%s  %s',
      [FActiveRig.Name,
       TCastleIkRetargeter.ProfileTitle(FActiveRig.SourceProfile),
       TCastleIkRetargeter.ProfileTitle(FActiveRig.TargetProfile),
       BoolToStr(FActiveRig.CompensateRefPoseDelta, 'ON', 'OFF'),
       FActiveRig.IkRetargetSummaryBadge])
  else
    FLblStatus.Caption := 'No TCastleIkRetargeter in design — click "+ Manny -> Compact A-Pose".';

  FMemoReport.Text := TIkRetargeterHelper.GenerateMarkdownReport(FDesignRoot, FActiveRig);
  FPaintRigs.Invalidate;
  FPaintChains.Invalidate;
end;

procedure TIkRetargeterForm.DrawHumanoidSkeleton(const C: TCanvas;
  const APose: TIkHumanoidPose; const ACenterX, AFloorY: Integer;
  const APxPerMeter: Single; const ABoneColor, AJointColor: TColor;
  const ALabel: String);

  function ProjPt(const V: TVector3): TPoint;
  begin
    { Oblique 3/4 front-side projection so both shoulder width (X) and stride (Z) are visible! }
    Result.X := ACenterX + Round((V.X * 0.90 + V.Z * 0.42) * APxPerMeter);
    Result.Y := AFloorY - Round(V.Y * APxPerMeter);
  end;

  procedure DrawBone(const J0, J1: TIkHumanoidJoint);
  var
    P0, P1: TPoint;
  begin
    P0 := ProjPt(APose.JointPos[J0]);
    P1 := ProjPt(APose.JointPos[J1]);
    C.Line(P0.X, P0.Y, P1.X, P1.Y);
  end;

var
  J: TIkHumanoidJoint;
  P: TPoint;
begin
  C.Brush.Style := bsClear;
  C.Font.Color := ABoneColor;
  C.TextOut(ACenterX - 115, 14, ALabel);

  C.Pen.Width := 3;
  C.Pen.Color := ABoneColor;
  DrawBone(ihjPelvis, ihjSpineMid);
  DrawBone(ihjSpineMid, ihjChest);
  DrawBone(ihjChest, ihjHead);
  DrawBone(ihjChest, ihjShoulderL);
  DrawBone(ihjShoulderL, ihjElbowL);
  DrawBone(ihjElbowL, ihjHandL);
  DrawBone(ihjChest, ihjShoulderR);
  DrawBone(ihjShoulderR, ihjElbowR);
  DrawBone(ihjElbowR, ihjHandR);
  DrawBone(ihjPelvis, ihjHipL);
  DrawBone(ihjHipL, ihjKneeL);
  DrawBone(ihjKneeL, ihjFootL);
  DrawBone(ihjPelvis, ihjHipR);
  DrawBone(ihjHipR, ihjKneeR);
  DrawBone(ihjKneeR, ihjFootR);

  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(18, 20, 26);
  C.Brush.Style := bsSolid;
  C.Brush.Color := AJointColor;
  for J in TIkHumanoidJoint do
  begin
    P := ProjPt(APose.JointPos[J]);
    C.Ellipse(P.X - 4, P.Y - 4, P.X + 5, P.Y + 5);
  end;

  { Highlight planted IK foot goals }
  C.Brush.Style := bsClear;
  C.Pen.Width := 2;
  C.Pen.Color := RGBToColor(255, 208, 64);
  if APose.LeftFootPlanted then
  begin
    P := ProjPt(APose.JointPos[ihjFootL]);
    C.Ellipse(P.X - 9, P.Y - 9, P.X + 10, P.Y + 10);
  end;
  if APose.RightFootPlanted then
  begin
    P := ProjPt(APose.JointPos[ihjFootR]);
    C.Ellipse(P.X - 9, P.Y - 9, P.X + 10, P.Y + 10);
  end;
end;

procedure TIkRetargeterForm.PaintRigsCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, FloorY: Integer;
begin
  C := FPaintRigs.Canvas;
  W := FPaintRigs.Width;
  H := FPaintRigs.Height;

  C.Brush.Color := RGBToColor(18, 20, 26);
  C.FillRect(0, 0, W, H);

  FloorY := H - 56;
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(68, 78, 96);
  C.Line(20, FloorY, W - 20, FloorY);

  if FActiveRig = nil then Exit;

  DrawHumanoidSkeleton(C, FActiveRig.SourcePose, W div 4 + 10, FloorY, 155.0,
    RGBToColor(92, 198, 255), clWhite,
    'SOURCE: ' + TCastleIkRetargeter.ProfileTitle(FActiveRig.SourceProfile));

  DrawHumanoidSkeleton(C, FActiveRig.TargetPose, (W * 3) div 4 - 10, FloorY, 155.0,
    RGBToColor(86, 236, 146), RGBToColor(255, 224, 92),
    'TARGET: ' + TCastleIkRetargeter.ProfileTitle(FActiveRig.TargetProfile));
end;

procedure TIkRetargeterForm.PaintChainsCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, YRow, I, BarW: Integer;
  Ch: TIkRetargetChainConfig;
begin
  C := FPaintChains.Canvas;
  W := FPaintChains.Width;
  H := FPaintChains.Height;

  C.Brush.Color := RGBToColor(24, 26, 32);
  C.FillRect(0, 0, W, H);

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(36, 42, 54);
  C.FillRect(0, 0, W, 30);
  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(12, 7, '7 Humanoid Retarget Chains (Click chain to select)');

  if FActiveRig = nil then Exit;

  YRow := 38;
  for I := 0 to High(FActiveRig.Chains) do
  begin
    Ch := FActiveRig.Chains[I];
    C.Brush.Style := bsSolid;
    if I = FSelectedChainIdx then
      C.Brush.Color := RGBToColor(54, 66, 88)
    else
      C.Brush.Color := RGBToColor(34, 38, 46);
    C.Pen.Color := RGBToColor(20, 22, 26);
    C.Rectangle(8, YRow, W - 8, YRow + 54);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(225, 234, 246);
    C.TextOut(16, YRow + 6, TCastleIkRetargeter.ChainTitle(Ch.ChainId));
    C.Font.Color := RGBToColor(156, 206, 255);
    C.TextOut(16, YRow + 28, Format('FK=%.2f   IK=%.2f   Stride=%.2fx',
      [Ch.FkRotationWeight, Ch.IkBlendWeight, Ch.StrideScale]));

    { IK Blend Progress Bar }
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(22, 24, 30);
    C.Rectangle(W - 134, YRow + 18, W - 18, YRow + 34);
    BarW := Round(EnsureRange(Ch.IkBlendWeight, 0.0, 1.0) * 114);
    if BarW > 0 then
    begin
      C.Brush.Color := RGBToColor(86, 232, 142);
      C.FillRect(W - 133, YRow + 19, W - 133 + BarW, YRow + 33);
    end;

    Inc(YRow, 58);
  end;
end;

procedure TIkRetargeterForm.ChainsMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  if FActiveRig = nil then Exit;
  Idx := (Y - 38) div 58;
  if (Idx >= 0) and (Idx <= High(FActiveRig.Chains)) then
  begin
    FSelectedChainIdx := Idx;
    FPaintChains.Invalidate;
  end;
end;

procedure TIkRetargeterForm.BtnSpawnCompactClick(Sender: TObject);
begin
  FActiveRig := TIkRetargeterHelper.SpawnIkRetargetPresetInDesign(
    FDesignRoot, FDesignOwner, irpMannequinToCompactAPose, Vector3(0, 0, 0));
  FActiveRig.StepRetargeter(0.20);
  NotifyChanged('Spawn IK Retargeter Mannequin -> Compact A-Pose');
end;

procedure TIkRetargeterForm.BtnSpawnOgreClick(Sender: TObject);
begin
  FActiveRig := TIkRetargeterHelper.SpawnIkRetargetPresetInDesign(
    FDesignRoot, FDesignOwner, irpMannequinToBruteOgre, Vector3(3, 0, 0));
  FActiveRig.StepRetargeter(0.20);
  NotifyChanged('Spawn IK Retargeter Mannequin -> Brute Ogre');
end;

procedure TIkRetargeterForm.BtnSpawnTwoHandClick(Sender: TObject);
begin
  FActiveRig := TIkRetargeterHelper.SpawnIkRetargetPresetInDesign(
    FDesignRoot, FDesignOwner, irpTwoHandedGripIkRetarget, Vector3(-3, 0, 0));
  NotifyChanged('Spawn IK Retargeter Two-Handed Grip');
end;

procedure TIkRetargeterForm.BtnStepWalkClick(Sender: TObject);
begin
  if FActiveRig = nil then Exit;
  FActiveRig.StepRetargeter(0.12);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshFromScene;
end;

procedure TIkRetargeterForm.BtnToggleRefCompClick(Sender: TObject);
begin
  if FActiveRig = nil then Exit;
  FActiveRig.CompensateRefPoseDelta := not FActiveRig.CompensateRefPoseDelta;
  NotifyChanged('Toggle T-Pose / A-Pose Reference Delta Compensation');
end;

procedure TIkRetargeterForm.BtnToggleChainIkClick(Sender: TObject);
var
  ChId: TIkRetargetChainId;
  CurIk: Single;
begin
  if FActiveRig = nil then Exit;
  ChId := TIkRetargetChainId(EnsureRange(FSelectedChainIdx, 0, Ord(High(TIkRetargetChainId))));
  CurIk := FActiveRig.GetChainConfig(ChId).IkBlendWeight;
  if CurIk > 0.5 then
    FActiveRig.SetChainIkBlend(ChId, 0.0)
  else
    FActiveRig.SetChainIkBlend(ChId, 1.0);
  NotifyChanged('Toggle Retarget Chain IK Blend');
end;

procedure TIkRetargeterForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Text;
end;

end.
