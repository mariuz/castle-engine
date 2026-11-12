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

{ Hierarchy discovery, 1-click Two-Bone Leg IK & Look-At Aim Turret spawners,
  batch solver execution, rig diagnostics, and Markdown reporting for
  @link(TCastleTwoBoneIkBehavior) and @link(TCastleLookAtConstraintBehavior)
  (Phase 304). }
unit ToolIkRig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleUiControls, CastleViewport,
  CastleIkRig;

type
  TTwoBoneIkBehaviorArray = array of TCastleTwoBoneIkBehavior;
  TLookAtConstraintBehaviorArray = array of TCastleLookAtConstraintBehavior;

  { Hierarchy scan & diagnostics summary for Analytical IK & Motion Rig Studio. }
  TIkRigSummary = record
    TwoBoneRigs: TTwoBoneIkBehaviorArray;
    LookAtRigs: TLookAtConstraintBehaviorArray;
    GroundPlantCount: Integer;
    Warnings: array of String;
  end;

  { Stateless editor helper for Analytical Two-Bone IK & Look-At Constraints. }
  TIkRigHelper = class
  public
    class function ScanIkRigs(const ARoot: TComponent): TIkRigSummary;

    class function CreateSampleLegIkRigInDesign(
      const ARoot, ADesignOwner: TComponent;
      const ABasePos: TVector3;
      out OutHip, OutKnee, OutFoot, OutTarget, OutPole: TCastleTransform
    ): TCastleTwoBoneIkBehavior;

    class function CreateSampleLookAtTurretInDesign(
      const ARoot, ADesignOwner: TComponent;
      const ABasePos: TVector3;
      out OutTurretHead, OutAimTarget: TCastleTransform
    ): TCastleLookAtConstraintBehavior;

    class function SolveAllIkInHierarchy(
      const ARoot: TComponent;
      const ADeltaSeconds: Single = 0.0): Integer;

    class function BuildMarkdownReport(const ARoot: TComponent): String;
  end;

implementation

uses
  CastleScene, X3DNodes;

function ProposeUniqueIkName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

function FindIkWorldContainer(const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindIkWorldContainer(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

procedure AttachTransientJointVisual(const AJoint: TCastleTransform;
  const ABoxSize, ABoxOffset, ABaseColor: TVector3);
var
  PreviewScene: TCastleScene;
  Root: TX3DRootNode;
  Box: TBoxNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Trans: TTransformNode;
begin
  if AJoint = nil then
    Exit;

  PreviewScene := TCastleScene.Create(AJoint);
  PreviewScene.SetTransient;
  PreviewScene.Pickable := false;
  PreviewScene.Collides := false;

  Root := TX3DRootNode.Create;
  Box := TBoxNode.CreateWithTransform(Shape, Trans);
  Box.Size := ABoxSize;
  Trans.Translation := ABoxOffset;

  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := ABaseColor;
  Mat.Roughness := 0.45;
  App.Material := Mat;
  Shape.Appearance := App;

  Root.AddChildren(Trans);
  PreviewScene.Load(Root, true);
  AJoint.Add(PreviewScene);
end;

{ TIkRigHelper --------------------------------------------------------------- }

class function TIkRigHelper.ScanIkRigs(const ARoot: TComponent): TIkRigSummary;

  procedure AddWarn(const S: String);
  var
    N: Integer;
  begin
    N := Length(Result.Warnings);
    SetLength(Result.Warnings, N + 1);
    Result.Warnings[N] := S;
  end;

  procedure Visit(const C: TComponent);
  var
    I, N: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    Vp: TCastleViewport;
    Ik: TCastleTwoBoneIkBehavior;
    Look: TCastleLookAtConstraintBehavior;
  begin
    if C = nil then
      Exit;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      if not (csTransient in T.ComponentStyle) then
      begin
        for I := 0 to T.BehaviorsCount - 1 do
        begin
          if T.Behaviors[I] is TCastleTwoBoneIkBehavior then
          begin
            Ik := TCastleTwoBoneIkBehavior(T.Behaviors[I]);
            N := Length(Result.TwoBoneRigs);
            SetLength(Result.TwoBoneRigs, N + 1);
            Result.TwoBoneRigs[N] := Ik;
            if Ik.EnableGroundFootPlant then
              Inc(Result.GroundPlantCount);
            if Ik.MidJointTransform = nil then
              AddWarn(Format('Two-Bone IK on "%s" has nil MidJointTransform.', [T.Name]));
            if Ik.EndJointTransform = nil then
              AddWarn(Format('Two-Bone IK on "%s" has nil EndJointTransform.', [T.Name]));
            if Ik.TargetTransform = nil then
              AddWarn(Format('Two-Bone IK on "%s" has nil TargetTransform.', [T.Name]));
          end else
          if T.Behaviors[I] is TCastleLookAtConstraintBehavior then
          begin
            Look := TCastleLookAtConstraintBehavior(T.Behaviors[I]);
            N := Length(Result.LookAtRigs);
            SetLength(Result.LookAtRigs, N + 1);
            Result.LookAtRigs[N] := Look;
            if Look.LookTarget = nil then
              AddWarn(Format('Look-At Constraint on "%s" has nil LookTarget.', [T.Name]));
          end;
        end;
        for I := 0 to T.Count - 1 do
          Visit(T[I]);
      end;
    end else
    if C is TCastleViewport then
    begin
      Vp := TCastleViewport(C);
      Visit(Vp.Items);
      for I := 0 to Vp.ControlsCount - 1 do
        Visit(Vp.Controls[I]);
    end else
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;
  end;

begin
  Result := Default(TIkRigSummary);
  Visit(ARoot);
end;

class function TIkRigHelper.CreateSampleLegIkRigInDesign(
  const ARoot, ADesignOwner: TComponent;
  const ABasePos: TVector3;
  out OutHip, OutKnee, OutFoot, OutTarget, OutPole: TCastleTransform
): TCastleTwoBoneIkBehavior;
var
  Container, RigGroup: TCastleTransform;
begin
  Result := nil;
  OutHip := nil;
  OutKnee := nil;
  OutFoot := nil;
  OutTarget := nil;
  OutPole := nil;

  Container := FindIkWorldContainer(ARoot);
  if Container = nil then
    Exit;

  RigGroup := TCastleTransform.Create(ADesignOwner);
  RigGroup.Name := ProposeUniqueIkName(ADesignOwner, 'LegIkRig');
  RigGroup.Translation := TVector3.Zero;
  Container.Add(RigGroup);

  OutHip := TCastleTransform.Create(ADesignOwner);
  OutHip.Name := ProposeUniqueIkName(ADesignOwner, 'LegHip');
  OutHip.Translation := ABasePos + Vector3(0.0, 1.05, 0.0);
  AttachTransientJointVisual(OutHip,
    Vector3(0.11, 0.11, 0.55), Vector3(0.0, 0.0, 0.275), Vector3(0.22, 0.72, 0.95));
  RigGroup.Add(OutHip);

  OutKnee := TCastleTransform.Create(ADesignOwner);
  OutKnee.Name := ProposeUniqueIkName(ADesignOwner, 'LegKnee');
  OutKnee.Translation := Vector3(0.0, -0.55, 0.12);
  AttachTransientJointVisual(OutKnee,
    Vector3(0.09, 0.09, 0.55), Vector3(0.0, 0.0, 0.275), Vector3(0.28, 0.88, 0.65));
  OutHip.Add(OutKnee);

  OutFoot := TCastleTransform.Create(ADesignOwner);
  OutFoot.Name := ProposeUniqueIkName(ADesignOwner, 'LegFoot');
  OutFoot.Translation := Vector3(0.0, -0.50, -0.12);
  AttachTransientJointVisual(OutFoot,
    Vector3(0.16, 0.08, 0.28), Vector3(0.0, 0.0, 0.09), Vector3(0.95, 0.75, 0.25));
  OutKnee.Add(OutFoot);

  OutTarget := TCastleTransform.Create(ADesignOwner);
  OutTarget.Name := ProposeUniqueIkName(ADesignOwner, 'LegFootTarget');
  OutTarget.Translation := ABasePos + Vector3(0.0, 0.15, 0.18);
  AttachTransientJointVisual(OutTarget,
    Vector3(0.14, 0.14, 0.14), TVector3.Zero, Vector3(0.98, 0.35, 0.32));
  RigGroup.Add(OutTarget);

  OutPole := TCastleTransform.Create(ADesignOwner);
  OutPole.Name := ProposeUniqueIkName(ADesignOwner, 'LegKneePole');
  OutPole.Translation := ABasePos + Vector3(0.0, 0.60, 0.85);
  AttachTransientJointVisual(OutPole,
    Vector3(0.12, 0.12, 0.12), TVector3.Zero, Vector3(0.98, 0.82, 0.22));
  RigGroup.Add(OutPole);

  Result := TCastleTwoBoneIkBehavior.Create(ADesignOwner);
  Result.Name := ProposeUniqueIkName(ADesignOwner, 'TwoBoneLegIk');
  Result.UpperBoneLength := 0.55;
  Result.LowerBoneLength := 0.55;
  Result.SoftReachMargin := 0.08;
  Result.MidJointTransform := OutKnee;
  Result.EndJointTransform := OutFoot;
  Result.TargetTransform := OutTarget;
  Result.PoleTransform := OutPole;
  OutHip.AddBehavior(Result);

  Result.SolveNow;
end;

class function TIkRigHelper.CreateSampleLookAtTurretInDesign(
  const ARoot, ADesignOwner: TComponent;
  const ABasePos: TVector3;
  out OutTurretHead, OutAimTarget: TCastleTransform
): TCastleLookAtConstraintBehavior;
var
  Container, Pedestal: TCastleTransform;
begin
  Result := nil;
  OutTurretHead := nil;
  OutAimTarget := nil;

  Container := FindIkWorldContainer(ARoot);
  if Container = nil then
    Exit;

  Pedestal := TCastleTransform.Create(ADesignOwner);
  Pedestal.Name := ProposeUniqueIkName(ADesignOwner, 'TurretPedestal');
  Pedestal.Translation := ABasePos;
  AttachTransientJointVisual(Pedestal,
    Vector3(0.45, 0.55, 0.45), Vector3(0.0, 0.275, 0.0), Vector3(0.35, 0.38, 0.44));
  Container.Add(Pedestal);

  OutTurretHead := TCastleTransform.Create(ADesignOwner);
  OutTurretHead.Name := ProposeUniqueIkName(ADesignOwner, 'TurretHead');
  OutTurretHead.Translation := Vector3(0.0, 0.65, 0.0);
  AttachTransientJointVisual(OutTurretHead,
    Vector3(0.24, 0.22, 0.65), Vector3(0.0, 0.0, 0.28), Vector3(0.88, 0.38, 0.82));
  Pedestal.Add(OutTurretHead);

  OutAimTarget := TCastleTransform.Create(ADesignOwner);
  OutAimTarget.Name := ProposeUniqueIkName(ADesignOwner, 'TurretAimTarget');
  OutAimTarget.Translation := ABasePos + Vector3(0.85, 1.05, 2.20);
  AttachTransientJointVisual(OutAimTarget,
    Vector3(0.16, 0.16, 0.16), TVector3.Zero, Vector3(0.98, 0.45, 0.85));
  Container.Add(OutAimTarget);

  Result := TCastleLookAtConstraintBehavior.Create(ADesignOwner);
  Result.Name := ProposeUniqueIkName(ADesignOwner, 'TurretLookAt');
  Result.LookTarget := OutAimTarget;
  Result.MaxYawDeg := 65.0;
  Result.MaxPitchDeg := 40.0;
  Result.DampingSpeed := 10.0;
  OutTurretHead.AddBehavior(Result);

  Result.ApplyLookAt(0.0);
end;

class function TIkRigHelper.SolveAllIkInHierarchy(
  const ARoot: TComponent; const ADeltaSeconds: Single): Integer;
var
  Sum: TIkRigSummary;
  I: Integer;
begin
  Result := 0;
  Sum := ScanIkRigs(ARoot);
  for I := 0 to High(Sum.TwoBoneRigs) do
    if Sum.TwoBoneRigs[I].SolveNow then
      Inc(Result);
  for I := 0 to High(Sum.LookAtRigs) do
    if Sum.LookAtRigs[I].ApplyLookAt(ADeltaSeconds) then
      Inc(Result);
end;

class function TIkRigHelper.BuildMarkdownReport(const ARoot: TComponent): String;
var
  Sum: TIkRigSummary;
  SB: TStringBuilder;
  I: Integer;
  Ik: TCastleTwoBoneIkBehavior;
  Look: TCastleLookAtConstraintBehavior;
  ParentName, MidName, EndName, TgtName: String;
begin
  Sum := ScanIkRigs(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Analytical Two-Bone IK & Look-At Motion Rig Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **Two-Bone IK Chains**: %d (Ground Foot-Plant Enabled: %d)',
      [Length(Sum.TwoBoneRigs), Sum.GroundPlantCount]));
    SB.AppendLine(Format('- **Look-At Aim Constraints**: %d',
      [Length(Sum.LookAtRigs)]));
    SB.AppendLine(Format('- **Rig Diagnostics Warnings**: %d',
      [Length(Sum.Warnings)]));
    SB.AppendLine('');

    if Length(Sum.TwoBoneRigs) > 0 then
    begin
      SB.AppendLine('## Two-Bone IK Chains');
      SB.AppendLine('| Root Bone | Mid Joint | End Effector | Target | L1 + L2 (m) | Soft Margin | Ground Plant |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :---: | :---: | :---: |');
      for I := 0 to High(Sum.TwoBoneRigs) do
      begin
        Ik := Sum.TwoBoneRigs[I];
        if Ik.Parent <> nil then ParentName := Ik.Parent.Name else ParentName := '(nil)';
        if Ik.MidJointTransform <> nil then MidName := Ik.MidJointTransform.Name else MidName := '(nil)';
        if Ik.EndJointTransform <> nil then EndName := Ik.EndJointTransform.Name else EndName := '(nil)';
        if Ik.TargetTransform <> nil then TgtName := Ik.TargetTransform.Name else TgtName := '(nil)';
        SB.AppendLine(Format('| `%s` | `%s` | `%s` | `%s` | %.2f + %.2f | %.2f | %s |',
          [ParentName, MidName, EndName, TgtName,
           Ik.UpperBoneLength, Ik.LowerBoneLength, Ik.SoftReachMargin,
           BoolToStr(Ik.EnableGroundFootPlant, 'Yes', 'No')]));
      end;
      SB.AppendLine('');
    end;

    if Length(Sum.LookAtRigs) > 0 then
    begin
      SB.AppendLine('## Look-At Aim Constraints');
      SB.AppendLine('| Constrained Transform | Target | Yaw Cone | Pitch Cone | Weight | Damping |');
      SB.AppendLine('| :--- | :--- | :---: | :---: | :---: | :---: |');
      for I := 0 to High(Sum.LookAtRigs) do
      begin
        Look := Sum.LookAtRigs[I];
        if Look.Parent <> nil then ParentName := Look.Parent.Name else ParentName := '(nil)';
        if Look.LookTarget <> nil then TgtName := Look.LookTarget.Name else TgtName := '(nil)';
        SB.AppendLine(Format('| `%s` | `%s` | ±%.0f° | ±%.0f° | %.2f | %.1f |',
          [ParentName, TgtName, Look.MaxYawDeg, Look.MaxPitchDeg,
           Look.Weight, Look.DampingSpeed]));
      end;
      SB.AppendLine('');
    end;

    if Length(Sum.Warnings) > 0 then
    begin
      SB.AppendLine('## Diagnostics Warnings');
      for I := 0 to High(Sum.Warnings) do
        SB.AppendLine('- ' + Sum.Warnings[I]);
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
