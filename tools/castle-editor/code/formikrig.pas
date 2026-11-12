{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Interactive Analytical Two-Bone IK, Foot Ground-Planting & Look-At Motion
  Rig Studio (@link(TIkRigForm)) featuring 1-click Leg IK & Look-At Turret
  spawners, live Effector/Pole sliders, 2D Skeletal Chain + Aim Cone canvas,
  and Markdown rig audit export (Phase 304). }
unit FormIkRig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Spin, ComCtrls, Graphics, Clipbrd,
  CastleVectors, CastleUtils, CastleTransform,
  CastleIkRig, ToolIkRig;

type
  TIkRigModifiedCallback = procedure(const AComment: String) of object;
  TIkRigRefreshViewportCallback = procedure of object;

  TIkRigForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FSpawnPos: TVector3;
    FOnModified: TIkRigModifiedCallback;
    FOnRefreshViewport: TIkRigRefreshViewportCallback;

    FSummary: TIkRigSummary;
    FCurrentIk: TCastleTwoBoneIkBehavior;
    FCurrentLookAt: TCastleLookAtConstraintBehavior;
    FSyncingUi: Boolean;

    LblHeader: TLabel;
    CmbTwoBone: TComboBox;
    SpinUpperLen: TFloatSpinEdit;
    SpinLowerLen: TFloatSpinEdit;
    SpinSoftMargin: TFloatSpinEdit;
    ChkGroundPlant: TCheckBox;
    TrackTargetX: TTrackBar;
    TrackTargetY: TTrackBar;
    TrackTargetZ: TTrackBar;
    TrackPoleZ: TTrackBar;

    CmbLookAt: TComboBox;
    SpinMaxYaw: TFloatSpinEdit;
    SpinMaxPitch: TFloatSpinEdit;
    SpinDamping: TFloatSpinEdit;

    PaintRig: TPaintBox;
    MemoLog: TMemo;

    procedure BuildUi;
    procedure RefreshRigs(const APreferredIk: TCastleTwoBoneIkBehavior = nil;
      const APreferredLook: TCastleLookAtConstraintBehavior = nil);
    procedure SyncControlsFromSelection;
    procedure NotifyModified(const AComment: String);

    procedure CmbTwoBoneChange(Sender: TObject);
    procedure CmbLookAtChange(Sender: TObject);
    procedure IkParamsChange(Sender: TObject);
    procedure TargetSlidersChange(Sender: TObject);
    procedure LookAtParamsChange(Sender: TObject);
    procedure BtnSpawnLegRigClick(Sender: TObject);
    procedure BtnSpawnTurretClick(Sender: TObject);
    procedure BtnSolveAllClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintRigPaint(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner, AInitialComponent: TComponent;
      const ASpawnWorldPos: TVector3;
      const AOnModified: TIkRigModifiedCallback;
      const AOnRefreshViewport: TIkRigRefreshViewportCallback);
  end;

implementation

constructor TIkRigForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner, AInitialComponent: TComponent;
  const ASpawnWorldPos: TVector3;
  const AOnModified: TIkRigModifiedCallback;
  const AOnRefreshViewport: TIkRigRefreshViewportCallback);
var
  InitIk: TCastleTwoBoneIkBehavior;
  InitLook: TCastleLookAtConstraintBehavior;
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FSpawnPos := ASpawnWorldPos;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Analytical Two-Bone IK, Foot Ground-Planting & Look-At Motion Rig Studio';
  Width := 1060;
  Height := 690;
  Position := poMainFormCenter;

  BuildUi;

  InitIk := nil;
  InitLook := nil;
  if AInitialComponent is TCastleTwoBoneIkBehavior then
    InitIk := TCastleTwoBoneIkBehavior(AInitialComponent)
  else if AInitialComponent is TCastleLookAtConstraintBehavior then
    InitLook := TCastleLookAtConstraintBehavior(AInitialComponent)
  else if AInitialComponent is TCastleTransform then
  begin
    InitIk := TCastleTransform(AInitialComponent).FindBehavior(
      TCastleTwoBoneIkBehavior) as TCastleTwoBoneIkBehavior;
    InitLook := TCastleTransform(AInitialComponent).FindBehavior(
      TCastleLookAtConstraintBehavior) as TCastleLookAtConstraintBehavior;
  end;

  RefreshRigs(InitIk, InitLook);
end;

procedure TIkRigForm.BuildUi;
var
  PnlTop, PnlBottom, PnlLeft, PnlRight: TPanel;
  BtnLeg, BtnTurret, BtnSolve, BtnReport, BtnClose: TButton;
  Lbl: TLabel;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 52;
  PnlTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PnlTop;
  LblHeader.Left := 14;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Analytical Two-Bone IK & Look-At Motion Rig Studio';

  BtnLeg := TButton.Create(Self);
  BtnLeg.Parent := PnlTop;
  BtnLeg.SetBounds(430, 10, 175, 30);
  BtnLeg.Caption := '+ Leg Two-Bone IK Rig';
  BtnLeg.OnClick := @BtnSpawnLegRigClick;

  BtnTurret := TButton.Create(Self);
  BtnTurret.Parent := PnlTop;
  BtnTurret.SetBounds(612, 10, 175, 30);
  BtnTurret.Caption := '+ Look-At Aim Turret';
  BtnTurret.OnClick := @BtnSpawnTurretClick;

  BtnSolve := TButton.Create(Self);
  BtnSolve.Parent := PnlTop;
  BtnSolve.SetBounds(794, 10, 130, 30);
  BtnSolve.Caption := 'Solve All Now';
  BtnSolve.OnClick := @BtnSolveAllClick;

  BtnReport := TButton.Create(Self);
  BtnReport.Parent := PnlTop;
  BtnReport.SetBounds(930, 10, 118, 30);
  BtnReport.Caption := 'Copy Report';
  BtnReport.OnClick := @BtnCopyReportClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 44;
  PnlBottom.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.SetBounds(938, 7, 110, 30);
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.Caption := 'Close';
  BtnClose.OnClick := @BtnCloseClick;

  PnlLeft := TPanel.Create(Self);
  PnlLeft.Parent := Self;
  PnlLeft.Align := alLeft;
  PnlLeft.Width := 455;
  PnlLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 8, 180, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Two-Bone IK Chain:';

  CmbTwoBone := TComboBox.Create(Self);
  CmbTwoBone.Parent := PnlLeft;
  CmbTwoBone.SetBounds(14, 28, 425, 26);
  CmbTwoBone.Style := csDropDownList;
  CmbTwoBone.OnChange := @CmbTwoBoneChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 62, 110, 18);
  Lbl.Caption := 'Upper L1 (m):';

  SpinUpperLen := TFloatSpinEdit.Create(Self);
  SpinUpperLen.Parent := PnlLeft;
  SpinUpperLen.SetBounds(105, 58, 78, 26);
  SpinUpperLen.MinValue := 0.05;
  SpinUpperLen.MaxValue := 5.0;
  SpinUpperLen.Increment := 0.05;
  SpinUpperLen.DecimalPlaces := 2;
  SpinUpperLen.OnChange := @IkParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(192, 62, 100, 18);
  Lbl.Caption := 'Lower L2 (m):';

  SpinLowerLen := TFloatSpinEdit.Create(Self);
  SpinLowerLen.Parent := PnlLeft;
  SpinLowerLen.SetBounds(280, 58, 78, 26);
  SpinLowerLen.MinValue := 0.05;
  SpinLowerLen.MaxValue := 5.0;
  SpinLowerLen.Increment := 0.05;
  SpinLowerLen.DecimalPlaces := 2;
  SpinLowerLen.OnChange := @IkParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 96, 110, 18);
  Lbl.Caption := 'Soft Reach (m):';

  SpinSoftMargin := TFloatSpinEdit.Create(Self);
  SpinSoftMargin.Parent := PnlLeft;
  SpinSoftMargin.SetBounds(105, 92, 78, 26);
  SpinSoftMargin.MinValue := 0.0;
  SpinSoftMargin.MaxValue := 1.0;
  SpinSoftMargin.Increment := 0.02;
  SpinSoftMargin.DecimalPlaces := 2;
  SpinSoftMargin.OnChange := @IkParamsChange;

  ChkGroundPlant := TCheckBox.Create(Self);
  ChkGroundPlant.Parent := PnlLeft;
  ChkGroundPlant.SetBounds(195, 95, 240, 22);
  ChkGroundPlant.Caption := 'Downward Raycast Foot Plant';
  ChkGroundPlant.OnChange := @IkParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 130, 120, 18);
  Lbl.Caption := 'Target Offset X:';
  TrackTargetX := TTrackBar.Create(Self);
  TrackTargetX.Parent := PnlLeft;
  TrackTargetX.SetBounds(130, 124, 310, 28);
  TrackTargetX.Min := -150;
  TrackTargetX.Max := 150;
  TrackTargetX.Position := 0;
  TrackTargetX.OnChange := @TargetSlidersChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 162, 120, 18);
  Lbl.Caption := 'Target Height Y:';
  TrackTargetY := TTrackBar.Create(Self);
  TrackTargetY.Parent := PnlLeft;
  TrackTargetY.SetBounds(130, 156, 310, 28);
  TrackTargetY.Min := -50;
  TrackTargetY.Max := 180;
  TrackTargetY.Position := 15;
  TrackTargetY.OnChange := @TargetSlidersChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 194, 120, 18);
  Lbl.Caption := 'Target Forward Z:';
  TrackTargetZ := TTrackBar.Create(Self);
  TrackTargetZ.Parent := PnlLeft;
  TrackTargetZ.SetBounds(130, 188, 310, 28);
  TrackTargetZ.Min := -150;
  TrackTargetZ.Max := 150;
  TrackTargetZ.Position := 18;
  TrackTargetZ.OnChange := @TargetSlidersChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 226, 120, 18);
  Lbl.Caption := 'Pole Vector Z:';
  TrackPoleZ := TTrackBar.Create(Self);
  TrackPoleZ.Parent := PnlLeft;
  TrackPoleZ.SetBounds(130, 220, 310, 28);
  TrackPoleZ.Min := -150;
  TrackPoleZ.Max := 150;
  TrackPoleZ.Position := 85;
  TrackPoleZ.OnChange := @TargetSlidersChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 268, 220, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Look-At Aim Constraint:';

  CmbLookAt := TComboBox.Create(Self);
  CmbLookAt.Parent := PnlLeft;
  CmbLookAt.SetBounds(14, 288, 425, 26);
  CmbLookAt.Style := csDropDownList;
  CmbLookAt.OnChange := @CmbLookAtChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(14, 324, 90, 18);
  Lbl.Caption := 'Max Yaw (°):';
  SpinMaxYaw := TFloatSpinEdit.Create(Self);
  SpinMaxYaw.Parent := PnlLeft;
  SpinMaxYaw.SetBounds(98, 320, 68, 26);
  SpinMaxYaw.MinValue := 5.0;
  SpinMaxYaw.MaxValue := 180.0;
  SpinMaxYaw.Increment := 5.0;
  SpinMaxYaw.DecimalPlaces := 0;
  SpinMaxYaw.OnChange := @LookAtParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(175, 324, 90, 18);
  Lbl.Caption := 'Max Pitch (°):';
  SpinMaxPitch := TFloatSpinEdit.Create(Self);
  SpinMaxPitch.Parent := PnlLeft;
  SpinMaxPitch.SetBounds(262, 320, 68, 26);
  SpinMaxPitch.MinValue := 5.0;
  SpinMaxPitch.MaxValue := 89.0;
  SpinMaxPitch.Increment := 5.0;
  SpinMaxPitch.DecimalPlaces := 0;
  SpinMaxPitch.OnChange := @LookAtParamsChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PnlLeft;
  Lbl.SetBounds(338, 324, 55, 18);
  Lbl.Caption := 'Damp:';
  SpinDamping := TFloatSpinEdit.Create(Self);
  SpinDamping.Parent := PnlLeft;
  SpinDamping.SetBounds(382, 320, 57, 26);
  SpinDamping.MinValue := 0.0;
  SpinDamping.MaxValue := 50.0;
  SpinDamping.Increment := 1.0;
  SpinDamping.DecimalPlaces := 1;
  SpinDamping.OnChange := @LookAtParamsChange;

  MemoLog := TMemo.Create(Self);
  MemoLog.Parent := PnlLeft;
  MemoLog.SetBounds(14, 358, 425, 224);
  MemoLog.Anchors := [akTop, akLeft, akBottom];
  MemoLog.ReadOnly := true;
  MemoLog.ScrollBars := ssVertical;

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alClient;
  PnlRight.BevelOuter := bvNone;

  PaintRig := TPaintBox.Create(Self);
  PaintRig.Parent := PnlRight;
  PaintRig.Align := alClient;
  PaintRig.OnPaint := @PaintRigPaint;
end;

procedure TIkRigForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TIkRigForm.RefreshRigs(const APreferredIk: TCastleTwoBoneIkBehavior;
  const APreferredLook: TCastleLookAtConstraintBehavior);
var
  I, IkIdx, LookIdx: Integer;
  PName: String;
begin
  FSummary := TIkRigHelper.ScanIkRigs(FDesignRoot);
  LblHeader.Caption := Format(
    'Analytical Motion Rig Studio — %d Two-Bone IK Chains, %d Look-At Constraints',
    [Length(FSummary.TwoBoneRigs), Length(FSummary.LookAtRigs)]);

  CmbTwoBone.Items.BeginUpdate;
  try
    CmbTwoBone.Items.Clear;
    IkIdx := -1;
    for I := 0 to High(FSummary.TwoBoneRigs) do
    begin
      if FSummary.TwoBoneRigs[I].Parent <> nil then
        PName := FSummary.TwoBoneRigs[I].Parent.Name
      else
        PName := '(detached)';
      CmbTwoBone.Items.Add(Format('%s -> %s %s',
        [PName, FSummary.TwoBoneRigs[I].Name, FSummary.TwoBoneRigs[I].IkSummaryBadge]));
      if FSummary.TwoBoneRigs[I] = APreferredIk then
        IkIdx := I;
    end;
    if (IkIdx < 0) and (Length(FSummary.TwoBoneRigs) > 0) then
      IkIdx := 0;
    CmbTwoBone.ItemIndex := IkIdx;
  finally
    CmbTwoBone.Items.EndUpdate;
  end;
  if (IkIdx >= 0) and (IkIdx <= High(FSummary.TwoBoneRigs)) then
    FCurrentIk := FSummary.TwoBoneRigs[IkIdx]
  else
    FCurrentIk := nil;

  CmbLookAt.Items.BeginUpdate;
  try
    CmbLookAt.Items.Clear;
    LookIdx := -1;
    for I := 0 to High(FSummary.LookAtRigs) do
    begin
      if FSummary.LookAtRigs[I].Parent <> nil then
        PName := FSummary.LookAtRigs[I].Parent.Name
      else
        PName := '(detached)';
      CmbLookAt.Items.Add(Format('%s -> %s %s',
        [PName, FSummary.LookAtRigs[I].Name, FSummary.LookAtRigs[I].LookAtSummaryBadge]));
      if FSummary.LookAtRigs[I] = APreferredLook then
        LookIdx := I;
    end;
    if (LookIdx < 0) and (Length(FSummary.LookAtRigs) > 0) then
      LookIdx := 0;
    CmbLookAt.ItemIndex := LookIdx;
  finally
    CmbLookAt.Items.EndUpdate;
  end;
  if (LookIdx >= 0) and (LookIdx <= High(FSummary.LookAtRigs)) then
    FCurrentLookAt := FSummary.LookAtRigs[LookIdx]
  else
    FCurrentLookAt := nil;

  SyncControlsFromSelection;
  MemoLog.Lines.Text := TIkRigHelper.BuildMarkdownReport(FDesignRoot);
  PaintRig.Invalidate;
end;

procedure TIkRigForm.SyncControlsFromSelection;
var
  RootW, TgtW, PoleW: TVector3;
begin
  FSyncingUi := true;
  try
    if FCurrentIk <> nil then
    begin
      SpinUpperLen.Value := FCurrentIk.UpperBoneLength;
      SpinLowerLen.Value := FCurrentIk.LowerBoneLength;
      SpinSoftMargin.Value := FCurrentIk.SoftReachMargin;
      ChkGroundPlant.Checked := FCurrentIk.EnableGroundFootPlant;
      if FCurrentIk.Parent <> nil then
        RootW := GetIkHierarchyMatrix(FCurrentIk.Parent).MultPoint(TVector3.Zero)
      else
        RootW := TVector3.Zero;
      if FCurrentIk.TargetTransform <> nil then
      begin
        TgtW := GetIkHierarchyMatrix(FCurrentIk.TargetTransform).MultPoint(TVector3.Zero);
        TrackTargetX.Position := Clamped(Round((TgtW.X - RootW.X) * 100.0), -150, 150);
        TrackTargetY.Position := Clamped(Round((TgtW.Y - (RootW.Y - 1.05)) * 100.0), -50, 180);
        TrackTargetZ.Position := Clamped(Round((TgtW.Z - RootW.Z) * 100.0), -150, 150);
      end;
      if FCurrentIk.PoleTransform <> nil then
      begin
        PoleW := GetIkHierarchyMatrix(FCurrentIk.PoleTransform).MultPoint(TVector3.Zero);
        TrackPoleZ.Position := Clamped(Round((PoleW.Z - RootW.Z) * 100.0), -150, 150);
      end;
    end;

    if FCurrentLookAt <> nil then
    begin
      SpinMaxYaw.Value := FCurrentLookAt.MaxYawDeg;
      SpinMaxPitch.Value := FCurrentLookAt.MaxPitchDeg;
      SpinDamping.Value := FCurrentLookAt.DampingSpeed;
    end;
  finally
    FSyncingUi := false;
  end;
end;

procedure TIkRigForm.CmbTwoBoneChange(Sender: TObject);
begin
  if (CmbTwoBone.ItemIndex >= 0) and (CmbTwoBone.ItemIndex <= High(FSummary.TwoBoneRigs)) then
    FCurrentIk := FSummary.TwoBoneRigs[CmbTwoBone.ItemIndex]
  else
    FCurrentIk := nil;
  SyncControlsFromSelection;
  PaintRig.Invalidate;
end;

procedure TIkRigForm.CmbLookAtChange(Sender: TObject);
begin
  if (CmbLookAt.ItemIndex >= 0) and (CmbLookAt.ItemIndex <= High(FSummary.LookAtRigs)) then
    FCurrentLookAt := FSummary.LookAtRigs[CmbLookAt.ItemIndex]
  else
    FCurrentLookAt := nil;
  SyncControlsFromSelection;
  PaintRig.Invalidate;
end;

procedure TIkRigForm.IkParamsChange(Sender: TObject);
begin
  if FSyncingUi or (FCurrentIk = nil) then
    Exit;
  FCurrentIk.UpperBoneLength := SpinUpperLen.Value;
  FCurrentIk.LowerBoneLength := SpinLowerLen.Value;
  FCurrentIk.SoftReachMargin := SpinSoftMargin.Value;
  FCurrentIk.EnableGroundFootPlant := ChkGroundPlant.Checked;
  FCurrentIk.SolveNow;
  NotifyModified('Update Two-Bone IK Rig');
  PaintRig.Invalidate;
end;

procedure TIkRigForm.TargetSlidersChange(Sender: TObject);
var
  RootW: TVector3;
begin
  if FSyncingUi or (FCurrentIk = nil) or (FCurrentIk.Parent = nil) then
    Exit;
  RootW := GetIkHierarchyMatrix(FCurrentIk.Parent).MultPoint(TVector3.Zero);
  if FCurrentIk.TargetTransform <> nil then
    FCurrentIk.TargetTransform.Translation := Vector3(
      RootW.X + TrackTargetX.Position * 0.01,
      (RootW.Y - 1.05) + TrackTargetY.Position * 0.01,
      RootW.Z + TrackTargetZ.Position * 0.01);
  if FCurrentIk.PoleTransform <> nil then
    FCurrentIk.PoleTransform.Translation := Vector3(
      RootW.X,
      RootW.Y - 0.45,
      RootW.Z + TrackPoleZ.Position * 0.01);
  FCurrentIk.SolveNow;
  NotifyModified('Move Two-Bone IK Target / Pole');
  PaintRig.Invalidate;
end;

procedure TIkRigForm.LookAtParamsChange(Sender: TObject);
begin
  if FSyncingUi or (FCurrentLookAt = nil) then
    Exit;
  FCurrentLookAt.MaxYawDeg := SpinMaxYaw.Value;
  FCurrentLookAt.MaxPitchDeg := SpinMaxPitch.Value;
  FCurrentLookAt.DampingSpeed := SpinDamping.Value;
  FCurrentLookAt.ApplyLookAt(0.0);
  NotifyModified('Update Look-At Constraint');
  PaintRig.Invalidate;
end;

procedure TIkRigForm.BtnSpawnLegRigClick(Sender: TObject);
var
  Hip, Knee, Foot, Tgt, Pole: TCastleTransform;
  Ik: TCastleTwoBoneIkBehavior;
begin
  Ik := TIkRigHelper.CreateSampleLegIkRigInDesign(
    FDesignRoot, FDesignOwner, FSpawnPos, Hip, Knee, Foot, Tgt, Pole);
  if Ik <> nil then
  begin
    NotifyModified('Create Leg Two-Bone IK Rig');
    RefreshRigs(Ik, FCurrentLookAt);
  end;
end;

procedure TIkRigForm.BtnSpawnTurretClick(Sender: TObject);
var
  Head, Tgt: TCastleTransform;
  Look: TCastleLookAtConstraintBehavior;
begin
  Look := TIkRigHelper.CreateSampleLookAtTurretInDesign(
    FDesignRoot, FDesignOwner, FSpawnPos + Vector3(1.5, 0.0, 0.0), Head, Tgt);
  if Look <> nil then
  begin
    NotifyModified('Create Look-At Aim Turret');
    RefreshRigs(FCurrentIk, Look);
  end;
end;

procedure TIkRigForm.BtnSolveAllClick(Sender: TObject);
begin
  TIkRigHelper.SolveAllIkInHierarchy(FDesignRoot, 0.0);
  NotifyModified('Solve All IK & Look-At Rigs');
  RefreshRigs(FCurrentIk, FCurrentLookAt);
end;

procedure TIkRigForm.BtnCopyReportClick(Sender: TObject);
var
  Rep: String;
begin
  Rep := TIkRigHelper.BuildMarkdownReport(FDesignRoot);
  Clipboard.AsText := Rep;
  MemoLog.Lines.Text := Rep;
end;

procedure TIkRigForm.PaintRigPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, SplitY, HipX, HipY, KneeX, KneeY, FootX, FootY, TgtX, TgtY, PoleX, PoleY, RadPx: Integer;
  ScalePx, YawW, PitchH: Single;
  RootW, MidW, EndW, TgtW, PoleW: TVector3;
  ConeCx, ConeCy: Integer;
begin
  C := PaintRig.Canvas;
  W := PaintRig.Width;
  H := PaintRig.Height;
  SplitY := (H * 3) div 5;

  C.Brush.Color := RGBToColor(18, 22, 30);
  C.FillRect(0, 0, W, H);

  C.Font.Color := RGBToColor(210, 225, 245);
  C.Brush.Style := bsClear;
  C.TextOut(14, 10, '2D Sagittal Z-Y Two-Bone IK Chain Diagram');

  if (FCurrentIk <> nil) and (FCurrentIk.Parent <> nil) then
  begin
    FCurrentIk.SolveNow;
    RootW := FCurrentIk.LastSolvedRootPos;
    MidW := FCurrentIk.LastSolvedMidPos;
    EndW := FCurrentIk.LastSolvedEndPos;
    if FCurrentIk.TargetTransform <> nil then
      TgtW := GetIkHierarchyMatrix(FCurrentIk.TargetTransform).MultPoint(TVector3.Zero)
    else
      TgtW := EndW;
    if FCurrentIk.PoleTransform <> nil then
      PoleW := GetIkHierarchyMatrix(FCurrentIk.PoleTransform).MultPoint(TVector3.Zero)
    else
      PoleW := RootW + Vector3(0.0, 0.0, 0.8);

    ScalePx := Min(W, SplitY) * 0.34 / Max(0.35, FCurrentIk.UpperBoneLength + FCurrentIk.LowerBoneLength);
    HipX := W div 2;
    HipY := Round(SplitY * 0.30);
    RadPx := Round((FCurrentIk.UpperBoneLength + FCurrentIk.LowerBoneLength) * ScalePx);

    { Reach boundary circle }
    C.Pen.Color := RGBToColor(52, 68, 92);
    C.Pen.Width := 1;
    C.Pen.Style := psDot;
    C.Ellipse(HipX - RadPx, HipY - RadPx, HipX + RadPx, HipY + RadPx);
    C.Pen.Style := psSolid;

    KneeX := HipX + Round((MidW.Z - RootW.Z) * ScalePx);
    KneeY := HipY - Round((MidW.Y - RootW.Y) * ScalePx);
    FootX := HipX + Round((EndW.Z - RootW.Z) * ScalePx);
    FootY := HipY - Round((EndW.Y - RootW.Y) * ScalePx);
    TgtX := HipX + Round((TgtW.Z - RootW.Z) * ScalePx);
    TgtY := HipY - Round((TgtW.Y - RootW.Y) * ScalePx);
    PoleX := HipX + Round((PoleW.Z - RootW.Z) * ScalePx);
    PoleY := HipY - Round((PoleW.Y - RootW.Y) * ScalePx);

    { Pole hint line }
    C.Pen.Color := RGBToColor(235, 195, 65);
    C.Pen.Width := 1;
    C.MoveTo(KneeX, KneeY);
    C.LineTo(PoleX, PoleY);

    { Upper & lower bones }
    C.Pen.Color := RGBToColor(65, 205, 250);
    C.Pen.Width := 4;
    C.MoveTo(HipX, HipY);
    C.LineTo(KneeX, KneeY);
    C.Pen.Color := RGBToColor(80, 235, 165);
    C.LineTo(FootX, FootY);
    C.Pen.Width := 1;

    { Joint markers }
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(65, 205, 250);
    C.Ellipse(HipX - 6, HipY - 6, HipX + 6, HipY + 6);
    C.Brush.Color := RGBToColor(80, 235, 165);
    C.Ellipse(KneeX - 6, KneeY - 6, KneeX + 6, KneeY + 6);
    C.Brush.Color := RGBToColor(245, 205, 75);
    C.Ellipse(FootX - 6, FootY - 6, FootX + 6, FootY + 6);

    { Pole diamond & Target crosshair }
    C.Brush.Color := RGBToColor(250, 210, 60);
    C.Rectangle(PoleX - 5, PoleY - 5, PoleX + 5, PoleY + 5);
    C.Pen.Color := RGBToColor(250, 95, 90);
    C.Pen.Width := 2;
    C.MoveTo(TgtX - 9, TgtY); C.LineTo(TgtX + 9, TgtY);
    C.MoveTo(TgtX, TgtY - 9); C.LineTo(TgtX, TgtY + 9);
    C.Pen.Width := 1;
  end else
  begin
    C.Font.Color := RGBToColor(145, 160, 180);
    C.TextOut(18, SplitY div 2, 'Click "+ Leg Two-Bone IK Rig" to spawn an interactive chain.');
  end;

  { Divider & Look-At Cone Diagram }
  C.Pen.Color := RGBToColor(45, 55, 72);
  C.MoveTo(10, SplitY);
  C.LineTo(W - 10, SplitY);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(210, 225, 245);
  C.TextOut(14, SplitY + 10, 'Look-At Angular Yaw / Pitch Cone Limit');

  ConeCx := W div 2;
  ConeCy := SplitY + (H - SplitY) div 2 + 8;
  C.Pen.Color := RGBToColor(60, 72, 92);
  C.MoveTo(ConeCx - 160, ConeCy); C.LineTo(ConeCx + 160, ConeCy);
  C.MoveTo(ConeCx, ConeCy - 75); C.LineTo(ConeCx, ConeCy + 75);

  if FCurrentLookAt <> nil then
  begin
    YawW := (FCurrentLookAt.MaxYawDeg / 180.0) * 150.0;
    PitchH := (FCurrentLookAt.MaxPitchDeg / 90.0) * 70.0;
    C.Pen.Color := RGBToColor(230, 105, 220);
    C.Pen.Width := 2;
    C.Ellipse(
      Round(ConeCx - YawW), Round(ConeCy - PitchH),
      Round(ConeCx + YawW), Round(ConeCy + PitchH));
    C.Pen.Width := 1;
    C.Font.Color := RGBToColor(235, 155, 230);
    C.TextOut(ConeCx + 12, ConeCy - Round(PitchH) - 18,
      Format('±%.0f° Yaw / ±%.0f° Pitch', [FCurrentLookAt.MaxYawDeg, FCurrentLookAt.MaxPitchDeg]));
  end;
end;

procedure TIkRigForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

end.
