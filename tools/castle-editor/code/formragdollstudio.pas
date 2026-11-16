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

{ Physical Animation Hit-Reaction Impulse, Articulated Ragdoll Collapse &
  Smooth Get-Up Recovery Studio Dialog (@link(TRagdollStudioForm))
  (Phase 331 — UE 6.0+ Chaos Physical Animation & Ragdoll Parity). }
unit FormRagdollStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleRagdollHit, ToolRagdollStudio;

type
  TRagdollStudioModifyCallback = procedure(const AUndoComment: String) of object;
  TRagdollStudioRefreshCallback = procedure of object;

  TRagdollStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModify: TRagdollStudioModifyCallback;
    FOnRefresh: TRagdollStudioRefreshCallback;

    FRigs: TRagdollBehaviorArray;

    LblHeader: TLabel;
    ListRigs: TListBox;
    LblDetails: TLabel;
    PaintSkeleton: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromDesign;
    function SelectedRig: TCastlePhysicalHitRagdollBehavior;
    procedure NotifyModified(const AComment: String);

    procedure ListRigsClick(Sender: TObject);
    procedure BtnSpawnRigClick(Sender: TObject);
    procedure BtnHeadshotClick(Sender: TObject);
    procedure BtnShoulderSlashClick(Sender: TObject);
    procedure BtnBlastKnockdownClick(Sender: TObject);
    procedure BtnGetUpRecoveryClick(Sender: TObject);
    procedure BtnCyclePresetClick(Sender: TObject);
    procedure BtnStep80msClick(Sender: TObject);
    procedure BtnBurst800msClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintSkeletonPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModify: TRagdollStudioModifyCallback;
      const AOnRefresh: TRagdollStudioRefreshCallback);
  end;

implementation

constructor TRagdollStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModify: TRagdollStudioModifyCallback;
  const AOnRefresh: TRagdollStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModify := AOnModify;
  FOnRefresh := AOnRefresh;

  Caption := 'Castle Game Engine — Physical Animation Hit-Reaction & Articulated Ragdoll Studio';
  Width := 1180;
  Height := 730;
  Position := poMainFormCenter;

  BuildUi;
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModify) then
    FOnModify(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TRagdollStudioForm.BuildUi;
var
  PanelTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  BtnClose: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 74;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Physical Animation & Ragdoll Studio — Localized Limb Impulses, PD Motor Springs, PBD Knockdown & Smooth Get-Up';

  MakeBtn(PanelTop, '+ Spawn Humanoid Rig', 12, 34, 174, @BtnSpawnRigClick);
  MakeBtn(PanelTop, 'Headshot Impulse!', 192, 34, 142, @BtnHeadshotClick);
  MakeBtn(PanelTop, 'Left Arm Slash!', 340, 34, 132, @BtnShoulderSlashClick);
  MakeBtn(PanelTop, 'Blast Knockdown!', 478, 34, 144, @BtnBlastKnockdownClick);
  MakeBtn(PanelTop, 'Stand Up Recovery', 628, 34, 146, @BtnGetUpRecoveryClick);
  MakeBtn(PanelTop, 'Cycle Stiffness', 780, 34, 124, @BtnCyclePresetClick);
  MakeBtn(PanelTop, 'Step +0.08s', 910, 34, 110, @BtnStep80msClick);
  MakeBtn(PanelTop, 'Burst +0.80s', 1026, 34, 120, @BtnBurst800msClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Ragdoll Report Markdown', 12, 6, 224, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 1050, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 420;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 6, 380, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Physical Animation Humanoid Rigs:';

  ListRigs := TListBox.Create(Self);
  ListRigs.Parent := PanelLeft;
  ListRigs.SetBounds(12, 26, 396, 240);
  ListRigs.OnClick := @ListRigsClick;

  LblDetails := TLabel.Create(Self);
  LblDetails.Parent := PanelLeft;
  LblDetails.SetBounds(12, 276, 396, 130);
  LblDetails.WordWrap := True;
  LblDetails.Caption := '';

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintSkeleton := TPaintBox.Create(Self);
  PaintSkeleton.Parent := PanelCenter;
  PaintSkeleton.Align := alTop;
  PaintSkeleton.Height := 300;
  PaintSkeleton.OnPaint := @PaintSkeletonPaint;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := PanelCenter;
  MemoReport.Align := alClient;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssAutoBoth;
  MemoReport.Font.Name := 'Monospace';
end;

function TRagdollStudioForm.SelectedRig: TCastlePhysicalHitRagdollBehavior;
var
  Idx: Integer;
begin
  Idx := ListRigs.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FRigs)) then
    Result := FRigs[Idx]
  else if Length(FRigs) > 0 then
    Result := FRigs[0]
  else
    Result := nil;
end;

procedure TRagdollStudioForm.RefreshFromDesign;
var
  I, PrevIdx: Integer;
  R: TCastlePhysicalHitRagdollBehavior;
begin
  PrevIdx := ListRigs.ItemIndex;
  TRagdollStudioHelper.ScanRagdolls(FDesignRoot, FDesignOwner, FRigs);

  ListRigs.Items.BeginUpdate;
  try
    ListRigs.Items.Clear;
    for I := 0 to High(FRigs) do
      ListRigs.Items.Add(Format('%s  %s',
        [FRigs[I].Name, FRigs[I].RagdollSummaryBadge]));
    if ListRigs.Items.Count > 0 then
      ListRigs.ItemIndex := Clamped(Max(0, PrevIdx), 0, ListRigs.Items.Count - 1);
  finally
    ListRigs.Items.EndUpdate;
  end;

  R := SelectedRig;
  if R <> nil then
    LblDetails.Caption := Format(
      'Preset: %s  |  Mode: %s' + LineEnding +
      'PD Stiffness Kp: %.0f  |  Knockdown Threshold: %.1f' + LineEnding +
      'Max Pose Deviation: %.3f m  |  Last Hit: %s (%.1f N*s, %d total)',
      [TCastlePhysicalHitRagdollBehavior.PresetDisplayName(R.Preset),
       TCastlePhysicalHitRagdollBehavior.ModeDisplayName(R.Mode),
       R.SpringStiffnessKp, R.KnockdownThreshold,
       R.MaxPoseDeviationMeters,
       TCastlePhysicalHitRagdollBehavior.BoneDisplayName(R.LastHitBone),
       R.LastHitMagnitude, R.TotalHitsReceived])
  else
    LblDetails.Caption := 'Click "+ Spawn Humanoid Rig" to create an 11-bone Physical Animation rig.';

  MemoReport.Lines.Text := TRagdollStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintSkeleton.Invalidate;
end;

procedure TRagdollStudioForm.ListRigsClick(Sender: TObject);
begin
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.BtnSpawnRigClick(Sender: TObject);
var
  Act: TCastleTransform;
  R: TCastlePhysicalHitRagdollBehavior;
begin
  TRagdollStudioHelper.SpawnPhysicalRagdollArenaDemo(
    FDesignRoot, FDesignOwner, Act, R);
  NotifyModified('Spawn Physical Animation Humanoid Rig');
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.BtnHeadshotClick(Sender: TObject);
var
  R: TCastlePhysicalHitRagdollBehavior;
begin
  R := SelectedRig;
  if R = nil then Exit;
  R.ApplyHitImpulseAtBone(rbiHead, Vector3(2.5, 1.5, 14.0));
  R.StepPhysicalAnimation(0.06);
  NotifyModified('Apply Headshot Physical Hit Impulse');
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.BtnShoulderSlashClick(Sender: TObject);
var
  R: TCastlePhysicalHitRagdollBehavior;
begin
  R := SelectedRig;
  if R = nil then Exit;
  R.ApplyHitImpulseAtBone(rbiForearmL, Vector3(-12.0, 4.0, 8.0));
  R.StepPhysicalAnimation(0.06);
  NotifyModified('Apply Left Arm Slash Hit Impulse');
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.BtnBlastKnockdownClick(Sender: TObject);
var
  R: TCastlePhysicalHitRagdollBehavior;
begin
  R := SelectedRig;
  if R = nil then Exit;
  R.ApplyHitImpulseAtBone(rbiSpineChest, Vector3(8.0, 12.0, 38.0));
  R.StepPhysicalAnimation(0.08);
  NotifyModified('Trigger Blast Knockdown Ragdoll');
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.BtnGetUpRecoveryClick(Sender: TObject);
var
  R: TCastlePhysicalHitRagdollBehavior;
begin
  R := SelectedRig;
  if R = nil then Exit;
  R.BeginGetUpRecovery(0.75);
  R.StepPhysicalAnimation(0.25);
  NotifyModified('Begin Ragdoll Get-Up Recovery');
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.BtnCyclePresetClick(Sender: TObject);
var
  R: TCastlePhysicalHitRagdollBehavior;
begin
  R := SelectedRig;
  if R = nil then Exit;
  case R.Preset of
    papAgileFighterBalanced: R.ApplyPreset(papStiffArmoredKnight);
    papStiffArmoredKnight:   R.ApplyPreset(papLooseZombieStagger);
  else
    R.ApplyPreset(papAgileFighterBalanced);
  end;
  NotifyModified('Cycle Physical Animation Stiffness Preset');
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.BtnStep80msClick(Sender: TObject);
begin
  TRagdollStudioHelper.StepAllRagdolls(FDesignRoot, FDesignOwner, 0.08);
  NotifyModified('Step Physical Animation Rigs (+0.08s)');
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.BtnBurst800msClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 1 to 10 do
    TRagdollStudioHelper.StepAllRagdolls(FDesignRoot, FDesignOwner, 0.08);
  NotifyModified('Burst Physical Animation Rigs (+0.80s)');
  RefreshFromDesign;
end;

procedure TRagdollStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := MemoReport.Lines.Text;
end;

procedure TRagdollStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TRagdollStudioForm.PaintSkeletonPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, FrontCX, SideCX, FloorPy: Integer;
  ScalePx: Single;
  R: TCastlePhysicalHitRagdollBehavior;
  B, PB: TRagdollBoneId;
  BS, PBS: TRagdollBoneState;
begin
  C := PaintSkeleton.Canvas;
  W := PaintSkeleton.Width;
  H := PaintSkeleton.Height;

  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  R := SelectedRig;
  if R = nil then Exit;

  FloorPy := H - 34;
  ScalePx := (FloorPy - 44) / 1.95;
  FrontCX := W div 4 + 20;
  SideCX := (W * 3) div 4 - 20;

  C.Pen.Color := RGBToColor(70, 84, 108);
  C.MoveTo(24, FloorPy);
  C.LineTo(W - 24, FloorPy);

  { Ghost authored rest skeleton (grey) + live simulated skeleton (cyan/red/gold) }
  for B in TRagdollBoneId do
  begin
    BS := R.GetBoneState(B);
    if BS.ParentIndex >= 0 then
    begin
      PB := TRagdollBoneId(BS.ParentIndex);
      PBS := R.GetBoneState(PB);

      { Front XY Ghost }
      C.Pen.Color := RGBToColor(58, 66, 82);
      C.Pen.Width := 1;
      C.MoveTo(FrontCX + Round(PBS.RestLocalPos.X * ScalePx), FloorPy - Round(PBS.RestLocalPos.Y * ScalePx));
      C.LineTo(FrontCX + Round(BS.RestLocalPos.X * ScalePx), FloorPy - Round(BS.RestLocalPos.Y * ScalePx));

      { Side ZY Ghost }
      C.MoveTo(SideCX + Round(PBS.RestLocalPos.Z * ScalePx), FloorPy - Round(PBS.RestLocalPos.Y * ScalePx));
      C.LineTo(SideCX + Round(BS.RestLocalPos.Z * ScalePx), FloorPy - Round(BS.RestLocalPos.Y * ScalePx));

      { Live skeleton }
      case R.Mode of
        prmActivePhysicalHitReact: C.Pen.Color := RGBToColor(74, 218, 255);
        prmFullLimpRagdoll:        C.Pen.Color := RGBToColor(250, 92, 82);
        prmGetUpBlendRecovery:     C.Pen.Color := RGBToColor(250, 208, 72);
      end;
      C.Pen.Width := 3;
      C.MoveTo(FrontCX + Round(PBS.CurLocalPos.X * ScalePx), FloorPy - Round(PBS.CurLocalPos.Y * ScalePx));
      C.LineTo(FrontCX + Round(BS.CurLocalPos.X * ScalePx), FloorPy - Round(BS.CurLocalPos.Y * ScalePx));

      C.MoveTo(SideCX + Round(PBS.CurLocalPos.Z * ScalePx), FloorPy - Round(PBS.CurLocalPos.Y * ScalePx));
      C.LineTo(SideCX + Round(BS.CurLocalPos.Z * ScalePx), FloorPy - Round(BS.CurLocalPos.Y * ScalePx));
      C.Pen.Width := 1;
    end;
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(200, 214, 236);
  C.Font.Style := [fsBold];
  C.TextOut(FrontCX - 80, 8, 'Front View (XY) — Ghost Rest vs Live PD');
  C.TextOut(SideCX - 80, 8, 'Side Knockback Profile (ZY)');
  C.Font.Style := [];
end;

end.
