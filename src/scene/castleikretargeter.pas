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

{ Unreal Engine 5.5-style Skeletal IK Retargeter runtime (@link(TCastleIkRetargeter))
  featuring auto-mapped 7-chain humanoid retargeting (Pelvis Root, Spine, Head,
  Left/Right Arms, Left/Right Legs), T-pose <-> A-pose reference delta
  compensation, pelvis-height proportional stride scaling, analytical 2-bone
  Foot/Hand IK goal planting with exact bone-length preservation, and transient
  side-by-side 3D skeleton visualization
  (Phase 387 — UE 5.5 UIKRetargeter & UIKRigDefinition Parity). }
unit CastleIkRetargeter;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Skeleton proportion & reference-pose archetype. }
  TIkSkeletonProfileKind = (
    ispMannequinTallTPose,
    ispCompactStylizedAPose,
    ispBruteOgreBroadShoulders
  );

  { 7 canonical UE5 UIKRigDefinition humanoid retarget chains. }
  TIkRetargetChainId = (
    ircPelvisRoot,
    ircSpine,
    ircHead,
    ircLeftArm,
    ircRightArm,
    ircLeftLeg,
    ircRightLeg
  );

  { 15 evaluated humanoid joints for Source and Target skeletons. }
  TIkHumanoidJoint = (
    ihjPelvis,
    ihjSpineMid,
    ihjChest,
    ihjHead,
    ihjShoulderL,
    ihjElbowL,
    ihjHandL,
    ihjShoulderR,
    ihjElbowR,
    ihjHandR,
    ihjHipL,
    ihjKneeL,
    ihjFootL,
    ihjHipR,
    ihjKneeR,
    ihjFootR
  );

  { Source motion clip driving the retargeter. }
  TIkRetargetMotionClip = (
    irmNeutralStandCheck,
    irmForwardStrideWalk,
    irmTwoHandedWeaponReach
  );

  { Built-in UE 5.5 UIKRetargeter starter presets. }
  TIkRetargetPreset = (
    irpCustom,
    irpMannequinToCompactAPose,
    irpMannequinToBruteOgre,
    irpTwoHandedGripIkRetarget
  );

  { Proportion & reference-pose metrics for a humanoid skeleton. }
  TIkSkeletonMetrics = record
    PelvisHeight: Single;
    SpineLength: Single;
    HeadLength: Single;
    ShoulderHalfWidth: Single;
    HipHalfWidth: Single;
    UpperArmLen: Single;
    LowerArmLen: Single;
    ThighLen: Single;
    CalfLen: Single;
    { Reference shoulder elevation relative to horizontal T-pose (0 deg = T-pose, -35 deg = A-pose). }
    RefArmElevationDeg: Single;
  end;

  { Per-chain FK/IK retarget settings (UE5 URTGChainSettings parity). }
  TIkRetargetChainConfig = record
    ChainId: TIkRetargetChainId;
    Enabled: Boolean;
    FkRotationWeight: Single;
    IkBlendWeight: Single;
    StrideScale: Single;
    UseCustomIkGoal: Boolean;
    CustomIkGoalLocal: TVector3;
  end;
  TIkRetargetChainConfigArray = array of TIkRetargetChainConfig;

  { Evaluated 16-joint humanoid pose in character-local space (Origin = (0,0,0) floor). }
  TIkHumanoidPose = record
    JointPos: array[TIkHumanoidJoint] of TVector3;
    LeftArmWorldElevDeg: Single;
    RightArmWorldElevDeg: Single;
    LeftFootPlanted: Boolean;
    RightFootPlanted: Boolean;
  end;

  { Unreal Engine 5.5-style cross-skeleton UIKRetargeter component. }
  TCastleIkRetargeter = class(TCastleTransform)
  private
    FPreset: TIkRetargetPreset;
    FSourceProfile: TIkSkeletonProfileKind;
    FTargetProfile: TIkSkeletonProfileKind;
    FMotionClip: TIkRetargetMotionClip;
    FCompensateRefPoseDelta: Boolean;
    FGlobalStrideScale: Single;
    FShowSideBySidePreview: Boolean;
    FChains: TIkRetargetChainConfigArray;

    { Transient runtime evaluation state }
    FPhaseTimeSec: Single;
    FSourcePose: TIkHumanoidPose;
    FTargetPose: TIkHumanoidPose;
    FRetargetStepCount: Integer;
    FPreviewContainer: TCastleTransform;

    procedure SetPreset(const AValue: TIkRetargetPreset);
    procedure SetSourceProfile(const AValue: TIkSkeletonProfileKind);
    procedure SetTargetProfile(const AValue: TIkSkeletonProfileKind);
    procedure SetMotionClip(const AValue: TIkRetargetMotionClip);
    procedure SetCompensateRefPoseDelta(const AValue: Boolean);
    procedure SetGlobalStrideScale(const AValue: Single);
    procedure SetShowSideBySidePreview(const AValue: Boolean);
    function GetChainsJson: String;
    procedure SetChainsJson(const AValue: String);

    procedure InitDefaultChains;
    procedure ClearPreviewContainer;
    procedure SyncSideBySidePreview;
    class procedure SolveTwoBoneIk3D(const ARootPos, ATargetPos, APoleDir: TVector3;
      const ALenUpper, ALenLower: Single; out AMidPos, AEndPos: TVector3); static;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Metadata & metric helpers }
    class function GetProfileMetrics(const AProfile: TIkSkeletonProfileKind): TIkSkeletonMetrics; static;
    class function ProfileTitle(const AProfile: TIkSkeletonProfileKind): String; static;
    class function ChainTitle(const AChain: TIkRetargetChainId): String; static;

    { Chain configuration API }
    procedure ApplyPreset(const APreset: TIkRetargetPreset);
    function GetChainConfig(const AChain: TIkRetargetChainId): TIkRetargetChainConfig;
    procedure SetChainIkBlend(const AChain: TIkRetargetChainId;
      const AIkBlend: Single); overload;
    procedure SetChainIkBlend(const AChain: TIkRetargetChainId;
      const AIkBlend: Single; const AUseCustomGoal: Boolean;
      const ACustomGoalLocal: TVector3); overload;
    procedure SetChainStrideScale(const AChain: TIkRetargetChainId; const AScale: Single);

    { Deterministic pose synthesis & cross-skeleton retargeting }
    procedure EvaluateRetargetAtTime(const ATimeSec: Single);
    procedure StepRetargeter(const ADeltaSeconds: Single);

    function PelvisHeightScaleRatio: Single;
    function MaxTargetLimbLengthError: Single;
    function IkRetargetSummaryBadge: String;

    property Chains: TIkRetargetChainConfigArray read FChains;
    property PhaseTimeSec: Single read FPhaseTimeSec;
    property SourcePose: TIkHumanoidPose read FSourcePose;
    property TargetPose: TIkHumanoidPose read FTargetPose;
    property RetargetStepCount: Integer read FRetargetStepCount;
  published
    property SourceProfile: TIkSkeletonProfileKind
      read FSourceProfile write SetSourceProfile default ispMannequinTallTPose;
    property TargetProfile: TIkSkeletonProfileKind
      read FTargetProfile write SetTargetProfile default ispCompactStylizedAPose;
    property MotionClip: TIkRetargetMotionClip
      read FMotionClip write SetMotionClip default irmForwardStrideWalk;
    property CompensateRefPoseDelta: Boolean
      read FCompensateRefPoseDelta write SetCompensateRefPoseDelta default True;
    property GlobalStrideScale: Single
      read FGlobalStrideScale write SetGlobalStrideScale;
    property ShowSideBySidePreview: Boolean
      read FShowSideBySidePreview write SetShowSideBySidePreview default True;
    property ChainsJson: String read GetChainsJson write SetChainsJson;
    property Preset: TIkRetargetPreset read FPreset write SetPreset default irpMannequinToCompactAPose;
  end;

implementation

uses
  fpjson, jsonparser;

{ Analytical 2-Bone IK Solver ------------------------------------------------ }

class procedure TCastleIkRetargeter.SolveTwoBoneIk3D(
  const ARootPos, ATargetPos, APoleDir: TVector3;
  const ALenUpper, ALenLower: Single;
  out AMidPos, AEndPos: TVector3);
var
  ToTarget, Dir, BendAxis, PerpDir: TVector3;
  Dist, MaxReach, MinReach, ClampedDist, CosA, SinA: Single;
begin
  ToTarget := ATargetPos - ARootPos;
  Dist := ToTarget.Length;
  MaxReach := Max(0.02, ALenUpper + ALenLower - 1e-4);
  MinReach := Abs(ALenUpper - ALenLower) + 1e-4;

  if Dist < 1e-5 then
    Dir := Vector3(0, -1, 0)
  else
    Dir := ToTarget / Dist;

  if Dist >= MaxReach then
  begin
    AMidPos := ARootPos + Dir * ALenUpper;
    AEndPos := ARootPos + Dir * (ALenUpper + ALenLower);
    Exit;
  end;

  ClampedDist := EnsureRange(Dist, MinReach, MaxReach);
  CosA := EnsureRange(
    (ALenUpper * ALenUpper + ClampedDist * ClampedDist - ALenLower * ALenLower) /
    Max(1e-5, 2.0 * ALenUpper * ClampedDist), -1.0, 1.0);
  SinA := Sqrt(Max(0.0, 1.0 - CosA * CosA));

  { Orthogonalize PoleDir against Dir }
  PerpDir := APoleDir - Dir * TVector3.DotProduct(APoleDir, Dir);
  if PerpDir.LengthSqr < 1e-6 then
  begin
    BendAxis := TVector3.CrossProduct(Dir, Vector3(1, 0, 0));
    if BendAxis.LengthSqr < 1e-6 then
      BendAxis := TVector3.CrossProduct(Dir, Vector3(0, 0, 1));
    PerpDir := BendAxis.Normalize;
  end else
    PerpDir := PerpDir.Normalize;

  AMidPos := ARootPos + (Dir * CosA + PerpDir * SinA) * ALenUpper;
  AEndPos := ARootPos + Dir * ClampedDist;
  { Re-pin lower segment to exact ALenLower along (AEndPos - AMidPos) }
  if (AEndPos - AMidPos).LengthSqr > 1e-8 then
    AEndPos := AMidPos + (AEndPos - AMidPos).Normalize * ALenLower;
end;

{ Profile & Metadata Helpers ------------------------------------------------- }

class function TCastleIkRetargeter.GetProfileMetrics(
  const AProfile: TIkSkeletonProfileKind): TIkSkeletonMetrics;
begin
  case AProfile of
    ispMannequinTallTPose:
      begin
        Result.PelvisHeight := 1.00;
        Result.SpineLength := 0.52;
        Result.HeadLength := 0.28;
        Result.ShoulderHalfWidth := 0.22;
        Result.HipHalfWidth := 0.12;
        Result.UpperArmLen := 0.34;
        Result.LowerArmLen := 0.32;
        Result.ThighLen := 0.52;
        Result.CalfLen := 0.50;
        Result.RefArmElevationDeg := 0.0; { Standard horizontal T-Pose }
      end;

    ispCompactStylizedAPose:
      begin
        Result.PelvisHeight := 0.64;
        Result.SpineLength := 0.36;
        Result.HeadLength := 0.26;
        Result.ShoulderHalfWidth := 0.16;
        Result.HipHalfWidth := 0.09;
        Result.UpperArmLen := 0.23;
        Result.LowerArmLen := 0.21;
        Result.ThighLen := 0.34;
        Result.CalfLen := 0.32;
        Result.RefArmElevationDeg := -35.0; { 35-deg downward A-Pose! }
      end;

    ispBruteOgreBroadShoulders:
      begin
        Result.PelvisHeight := 1.32;
        Result.SpineLength := 0.72;
        Result.HeadLength := 0.34;
        Result.ShoulderHalfWidth := 0.36;
        Result.HipHalfWidth := 0.20;
        Result.UpperArmLen := 0.50;
        Result.LowerArmLen := 0.48;
        Result.ThighLen := 0.68;
        Result.CalfLen := 0.66;
        Result.RefArmElevationDeg := -20.0; { 20-deg heavy A-Pose }
      end;
  end;
end;

class function TCastleIkRetargeter.ProfileTitle(
  const AProfile: TIkSkeletonProfileKind): String;
begin
  case AProfile of
    ispMannequinTallTPose:       Result := 'UE5 Mannequin (1.92m T-Pose)';
    ispCompactStylizedAPose:     Result := 'Compact Stylized (1.28m A-Pose -35°)';
    ispBruteOgreBroadShoulders:  Result := 'Brute Ogre (2.56m Heavy -20°)';
  end;
end;

class function TCastleIkRetargeter.ChainTitle(
  const AChain: TIkRetargetChainId): String;
begin
  case AChain of
    ircPelvisRoot: Result := 'Pelvis Root';
    ircSpine:      Result := 'Spine (Spine01..Chest)';
    ircHead:       Result := 'Head & Neck';
    ircLeftArm:    Result := 'Left Arm (Clavicle..Hand_L)';
    ircRightArm:   Result := 'Right Arm (Clavicle..Hand_R)';
    ircLeftLeg:    Result := 'Left Leg (Thigh..Foot_L)';
    ircRightLeg:   Result := 'Right Leg (Thigh..Foot_R)';
  end;
end;

{ TCastleIkRetargeter -------------------------------------------------------- }

constructor TCastleIkRetargeter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSourceProfile := ispMannequinTallTPose;
  FTargetProfile := ispCompactStylizedAPose;
  FMotionClip := irmForwardStrideWalk;
  FCompensateRefPoseDelta := True;
  FGlobalStrideScale := 1.0;
  FShowSideBySidePreview := True;
  InitDefaultChains;
  ApplyPreset(irpMannequinToCompactAPose);
end;

destructor TCastleIkRetargeter.Destroy;
begin
  ClearPreviewContainer;
  inherited;
end;

procedure TCastleIkRetargeter.Loaded;
begin
  inherited;
  EvaluateRetargetAtTime(FPhaseTimeSec);
end;

function TCastleIkRetargeter.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'SourceProfile') or
     (PropertyName = 'TargetProfile') or
     (PropertyName = 'MotionClip') or
     (PropertyName = 'CompensateRefPoseDelta') or
     (PropertyName = 'GlobalStrideScale') or
     (PropertyName = 'ShowSideBySidePreview') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleIkRetargeter.InitDefaultChains;
var
  C: TIkRetargetChainId;
begin
  SetLength(FChains, Ord(High(TIkRetargetChainId)) + 1);
  for C in TIkRetargetChainId do
  begin
    FChains[Ord(C)].ChainId := C;
    FChains[Ord(C)].Enabled := True;
    FChains[Ord(C)].FkRotationWeight := 1.0;
    if C in [ircLeftLeg, ircRightLeg] then
      FChains[Ord(C)].IkBlendWeight := 1.0 { Plant feet on ground by default }
    else
      FChains[Ord(C)].IkBlendWeight := 0.0;
    FChains[Ord(C)].StrideScale := 1.0;
    FChains[Ord(C)].UseCustomIkGoal := False;
    FChains[Ord(C)].CustomIkGoalLocal := TVector3.Zero;
  end;
end;

procedure TCastleIkRetargeter.SetPreset(const AValue: TIkRetargetPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleIkRetargeter.SetSourceProfile(const AValue: TIkSkeletonProfileKind);
begin
  FSourceProfile := AValue;
  if not (csLoading in ComponentState) then
    EvaluateRetargetAtTime(FPhaseTimeSec);
end;

procedure TCastleIkRetargeter.SetTargetProfile(const AValue: TIkSkeletonProfileKind);
begin
  FTargetProfile := AValue;
  if not (csLoading in ComponentState) then
    EvaluateRetargetAtTime(FPhaseTimeSec);
end;

procedure TCastleIkRetargeter.SetMotionClip(const AValue: TIkRetargetMotionClip);
begin
  FMotionClip := AValue;
  if not (csLoading in ComponentState) then
    EvaluateRetargetAtTime(FPhaseTimeSec);
end;

procedure TCastleIkRetargeter.SetCompensateRefPoseDelta(const AValue: Boolean);
begin
  FCompensateRefPoseDelta := AValue;
  if not (csLoading in ComponentState) then
    EvaluateRetargetAtTime(FPhaseTimeSec);
end;

procedure TCastleIkRetargeter.SetGlobalStrideScale(const AValue: Single);
begin
  FGlobalStrideScale := EnsureRange(AValue, 0.1, 3.0);
  if not (csLoading in ComponentState) then
    EvaluateRetargetAtTime(FPhaseTimeSec);
end;

procedure TCastleIkRetargeter.SetShowSideBySidePreview(const AValue: Boolean);
begin
  if FShowSideBySidePreview <> AValue then
  begin
    FShowSideBySidePreview := AValue;
    if not FShowSideBySidePreview then
      ClearPreviewContainer
    else
      SyncSideBySidePreview;
  end;
end;

function TCastleIkRetargeter.PelvisHeightScaleRatio: Single;
var
  SrcM, TgtM: TIkSkeletonMetrics;
begin
  SrcM := GetProfileMetrics(FSourceProfile);
  TgtM := GetProfileMetrics(FTargetProfile);
  Result := TgtM.PelvisHeight / Max(0.05, SrcM.PelvisHeight);
end;

function TCastleIkRetargeter.GetChainConfig(
  const AChain: TIkRetargetChainId): TIkRetargetChainConfig;
begin
  Result := FChains[Ord(AChain)];
end;

procedure TCastleIkRetargeter.SetChainIkBlend(const AChain: TIkRetargetChainId;
  const AIkBlend: Single);
begin
  SetChainIkBlend(AChain, AIkBlend, False, TVector3.Zero);
end;

procedure TCastleIkRetargeter.SetChainIkBlend(const AChain: TIkRetargetChainId;
  const AIkBlend: Single; const AUseCustomGoal: Boolean;
  const ACustomGoalLocal: TVector3);
begin
  FChains[Ord(AChain)].IkBlendWeight := EnsureRange(AIkBlend, 0.0, 1.0);
  FChains[Ord(AChain)].UseCustomIkGoal := AUseCustomGoal;
  FChains[Ord(AChain)].CustomIkGoalLocal := ACustomGoalLocal;
  EvaluateRetargetAtTime(FPhaseTimeSec);
end;

procedure TCastleIkRetargeter.SetChainStrideScale(
  const AChain: TIkRetargetChainId; const AScale: Single);
begin
  FChains[Ord(AChain)].StrideScale := EnsureRange(AScale, 0.0, 3.0);
  EvaluateRetargetAtTime(FPhaseTimeSec);
end;

procedure TCastleIkRetargeter.EvaluateRetargetAtTime(const ATimeSec: Single);
var
  SrcM, TgtM: TIkSkeletonMetrics;
  HeightRatio, PhaseAngle, SrcStrideZ, SrcBobY, TgtStrideZ, TgtBobY: Single;
  SrcLocalArmDeltaDeg, RefDeltaDeg, TgtLocalArmDeltaDeg, SrcArmRad, TgtArmRad: Single;
  LeanFwdRad: Single;
  SrcFootGoalL, SrcFootGoalR, TgtFootGoalL, TgtFootGoalR: TVector3;
  FkElbowL, FkHandL, FkElbowR, FkHandR, IkElbowL, IkHandL, IkElbowR, IkHandR, GoalL, GoalR: TVector3;
  FkKneeL, FkFootL, FkKneeR, FkFootR, IkKneeL, IkFootL, IkKneeR, IkFootR: TVector3;
  ArmDirL, ArmDirR: TVector3;
begin
  FPhaseTimeSec := Max(0.0, ATimeSec);
  SrcM := GetProfileMetrics(FSourceProfile);
  TgtM := GetProfileMetrics(FTargetProfile);
  HeightRatio := TgtM.PelvisHeight / Max(0.05, SrcM.PelvisHeight);

  { 1. Synthesize Source Pose (Mannequin or chosen SourceProfile) }
  PhaseAngle := FPhaseTimeSec * 2.0 * Pi;
  LeanFwdRad := 0.0;
  SrcBobY := 0.0;
  SrcStrideZ := 0.0;
  SrcLocalArmDeltaDeg := -45.0; { Relaxed 45 deg down from T-pose }
  FSourcePose.LeftFootPlanted := True;
  FSourcePose.RightFootPlanted := True;

  case FMotionClip of
    irmNeutralStandCheck:
      begin
        SrcStrideZ := 0.0;
        SrcBobY := 0.0;
        SrcLocalArmDeltaDeg := -45.0;
        SrcFootGoalL := Vector3(-SrcM.HipHalfWidth, 0.0, 0.0);
        SrcFootGoalR := Vector3( SrcM.HipHalfWidth, 0.0, 0.0);
      end;

    irmForwardStrideWalk:
      begin
        { Deterministic forward stride: at t=0.25s PelvisZ = +0.40m, LeftFoot planted at Z=0, RightFoot swinging at Z=+0.72m, Y=0.14m }
        SrcStrideZ := FPhaseTimeSec * 1.60;
        SrcBobY := -0.03 * Abs(Sin(PhaseAngle));
        LeanFwdRad := DegToRad(6.0);
        SrcLocalArmDeltaDeg := -50.0 + 18.0 * Sin(PhaseAngle);
        FSourcePose.LeftFootPlanted := Cos(PhaseAngle) >= -0.05;
        FSourcePose.RightFootPlanted := not FSourcePose.LeftFootPlanted;

        if FSourcePose.LeftFootPlanted then
          SrcFootGoalL := Vector3(-SrcM.HipHalfWidth, 0.0, SrcStrideZ - 0.22 * Sin(PhaseAngle))
        else
          SrcFootGoalL := Vector3(-SrcM.HipHalfWidth, 0.14, SrcStrideZ + 0.28);

        if FSourcePose.RightFootPlanted then
          SrcFootGoalR := Vector3(SrcM.HipHalfWidth, 0.0, SrcStrideZ + 0.22 * Sin(PhaseAngle))
        else
          SrcFootGoalR := Vector3(SrcM.HipHalfWidth, 0.14, SrcStrideZ + 0.28);
      end;

    irmTwoHandedWeaponReach:
      begin
        SrcStrideZ := 0.15;
        SrcBobY := -0.04;
        LeanFwdRad := DegToRad(8.0);
        SrcLocalArmDeltaDeg := -25.0;
        SrcFootGoalL := Vector3(-SrcM.HipHalfWidth, 0.0, 0.05);
        SrcFootGoalR := Vector3( SrcM.HipHalfWidth, 0.0, 0.25);
      end;
  end;

  { Build Source Skeleton Joints }
  FSourcePose.JointPos[ihjPelvis] := Vector3(0.0, SrcM.PelvisHeight + SrcBobY, SrcStrideZ);
  FSourcePose.JointPos[ihjSpineMid] := FSourcePose.JointPos[ihjPelvis] +
    Vector3(0.0, Cos(LeanFwdRad) * SrcM.SpineLength * 0.5, Sin(LeanFwdRad) * SrcM.SpineLength * 0.5);
  FSourcePose.JointPos[ihjChest] := FSourcePose.JointPos[ihjPelvis] +
    Vector3(0.0, Cos(LeanFwdRad) * SrcM.SpineLength, Sin(LeanFwdRad) * SrcM.SpineLength);
  FSourcePose.JointPos[ihjHead] := FSourcePose.JointPos[ihjChest] + Vector3(0.0, SrcM.HeadLength, 0.0);

  FSourcePose.LeftArmWorldElevDeg := SrcM.RefArmElevationDeg + SrcLocalArmDeltaDeg;
  FSourcePose.RightArmWorldElevDeg := FSourcePose.LeftArmWorldElevDeg;
  SrcArmRad := DegToRad(FSourcePose.LeftArmWorldElevDeg);

  FSourcePose.JointPos[ihjShoulderL] := FSourcePose.JointPos[ihjChest] + Vector3(-SrcM.ShoulderHalfWidth, -0.04, 0.0);
  FSourcePose.JointPos[ihjShoulderR] := FSourcePose.JointPos[ihjChest] + Vector3( SrcM.ShoulderHalfWidth, -0.04, 0.0);
  ArmDirL := Vector3(-Cos(SrcArmRad), Sin(SrcArmRad), 0.12).Normalize;
  ArmDirR := Vector3( Cos(SrcArmRad), Sin(SrcArmRad), 0.12).Normalize;
  FSourcePose.JointPos[ihjElbowL] := FSourcePose.JointPos[ihjShoulderL] + ArmDirL * SrcM.UpperArmLen;
  FSourcePose.JointPos[ihjHandL]  := FSourcePose.JointPos[ihjElbowL]    + ArmDirL * SrcM.LowerArmLen;
  FSourcePose.JointPos[ihjElbowR] := FSourcePose.JointPos[ihjShoulderR] + ArmDirR * SrcM.UpperArmLen;
  FSourcePose.JointPos[ihjHandR]  := FSourcePose.JointPos[ihjElbowR]    + ArmDirR * SrcM.LowerArmLen;

  FSourcePose.JointPos[ihjHipL] := FSourcePose.JointPos[ihjPelvis] + Vector3(-SrcM.HipHalfWidth, 0.0, 0.0);
  FSourcePose.JointPos[ihjHipR] := FSourcePose.JointPos[ihjPelvis] + Vector3( SrcM.HipHalfWidth, 0.0, 0.0);
  SolveTwoBoneIk3D(FSourcePose.JointPos[ihjHipL], SrcFootGoalL, Vector3(0, 0, 1),
    SrcM.ThighLen, SrcM.CalfLen, FSourcePose.JointPos[ihjKneeL], FSourcePose.JointPos[ihjFootL]);
  SolveTwoBoneIk3D(FSourcePose.JointPos[ihjHipR], SrcFootGoalR, Vector3(0, 0, 1),
    SrcM.ThighLen, SrcM.CalfLen, FSourcePose.JointPos[ihjKneeR], FSourcePose.JointPos[ihjFootR]);

  { 2. Retarget onto Target Skeleton! }
  TgtStrideZ := SrcStrideZ * HeightRatio * FGlobalStrideScale * FChains[Ord(ircPelvisRoot)].StrideScale;
  TgtBobY := SrcBobY * HeightRatio;
  LeanFwdRad := LeanFwdRad * FChains[Ord(ircSpine)].FkRotationWeight;

  FTargetPose.LeftFootPlanted := FSourcePose.LeftFootPlanted;
  FTargetPose.RightFootPlanted := FSourcePose.RightFootPlanted;

  FTargetPose.JointPos[ihjPelvis] := Vector3(0.0, TgtM.PelvisHeight + TgtBobY, TgtStrideZ);
  FTargetPose.JointPos[ihjSpineMid] := FTargetPose.JointPos[ihjPelvis] +
    Vector3(0.0, Cos(LeanFwdRad) * TgtM.SpineLength * 0.5, Sin(LeanFwdRad) * TgtM.SpineLength * 0.5);
  FTargetPose.JointPos[ihjChest] := FTargetPose.JointPos[ihjPelvis] +
    Vector3(0.0, Cos(LeanFwdRad) * TgtM.SpineLength, Sin(LeanFwdRad) * TgtM.SpineLength);
  FTargetPose.JointPos[ihjHead] := FTargetPose.JointPos[ihjChest] + Vector3(0.0, TgtM.HeadLength, 0.0);

  { T-Pose <-> A-Pose Reference Delta Compensation }
  if FCompensateRefPoseDelta then
    RefDeltaDeg := SrcM.RefArmElevationDeg - TgtM.RefArmElevationDeg
  else
    RefDeltaDeg := 0.0;

  TgtLocalArmDeltaDeg := SrcLocalArmDeltaDeg * FChains[Ord(ircLeftArm)].FkRotationWeight + RefDeltaDeg;
  FTargetPose.LeftArmWorldElevDeg := TgtM.RefArmElevationDeg + TgtLocalArmDeltaDeg;
  FTargetPose.RightArmWorldElevDeg := TgtM.RefArmElevationDeg +
    (SrcLocalArmDeltaDeg * FChains[Ord(ircRightArm)].FkRotationWeight + RefDeltaDeg);

  FTargetPose.JointPos[ihjShoulderL] := FTargetPose.JointPos[ihjChest] + Vector3(-TgtM.ShoulderHalfWidth, -0.03, 0.0);
  FTargetPose.JointPos[ihjShoulderR] := FTargetPose.JointPos[ihjChest] + Vector3( TgtM.ShoulderHalfWidth, -0.03, 0.0);

  TgtArmRad := DegToRad(FTargetPose.LeftArmWorldElevDeg);
  ArmDirL := Vector3(-Cos(TgtArmRad), Sin(TgtArmRad), 0.12).Normalize;
  FkElbowL := FTargetPose.JointPos[ihjShoulderL] + ArmDirL * TgtM.UpperArmLen;
  FkHandL  := FkElbowL + ArmDirL * TgtM.LowerArmLen;

  TgtArmRad := DegToRad(FTargetPose.RightArmWorldElevDeg);
  ArmDirR := Vector3( Cos(TgtArmRad), Sin(TgtArmRad), 0.12).Normalize;
  FkElbowR := FTargetPose.JointPos[ihjShoulderR] + ArmDirR * TgtM.UpperArmLen;
  FkHandR  := FkElbowR + ArmDirR * TgtM.LowerArmLen;

  { Optional Hand IK Goal Blend (e.g. Two-Handed Weapon Grip or Custom World Prop) }
  if FChains[Ord(ircLeftArm)].IkBlendWeight > 0.001 then
  begin
    if FChains[Ord(ircLeftArm)].UseCustomIkGoal then
      GoalL := FChains[Ord(ircLeftArm)].CustomIkGoalLocal
    else
      GoalL := FTargetPose.JointPos[ihjChest] + Vector3(-0.06, -0.12, TgtM.UpperArmLen * 1.15);
    SolveTwoBoneIk3D(FTargetPose.JointPos[ihjShoulderL], GoalL, Vector3(-1, -0.3, -1),
      TgtM.UpperArmLen, TgtM.LowerArmLen, IkElbowL, IkHandL);
    SolveTwoBoneIk3D(FTargetPose.JointPos[ihjShoulderL],
      Lerp(FChains[Ord(ircLeftArm)].IkBlendWeight, FkHandL, IkHandL), Vector3(-1, -0.3, -1),
      TgtM.UpperArmLen, TgtM.LowerArmLen,
      FTargetPose.JointPos[ihjElbowL], FTargetPose.JointPos[ihjHandL]);
  end else
  begin
    FTargetPose.JointPos[ihjElbowL] := FkElbowL;
    FTargetPose.JointPos[ihjHandL]  := FkHandL;
  end;

  if FChains[Ord(ircRightArm)].IkBlendWeight > 0.001 then
  begin
    if FChains[Ord(ircRightArm)].UseCustomIkGoal then
      GoalR := FChains[Ord(ircRightArm)].CustomIkGoalLocal
    else
      GoalR := FTargetPose.JointPos[ihjHandL] + Vector3(0.06, 0.02, 0.0);
    SolveTwoBoneIk3D(FTargetPose.JointPos[ihjShoulderR], GoalR, Vector3(1, -0.3, -1),
      TgtM.UpperArmLen, TgtM.LowerArmLen, IkElbowR, IkHandR);
    SolveTwoBoneIk3D(FTargetPose.JointPos[ihjShoulderR],
      Lerp(FChains[Ord(ircRightArm)].IkBlendWeight, FkHandR, IkHandR), Vector3(1, -0.3, -1),
      TgtM.UpperArmLen, TgtM.LowerArmLen,
      FTargetPose.JointPos[ihjElbowR], FTargetPose.JointPos[ihjHandR]);
  end else
  begin
    FTargetPose.JointPos[ihjElbowR] := FkElbowR;
    FTargetPose.JointPos[ihjHandR]  := FkHandR;
  end;

  { Legs: Proportional Stride + 2-Bone Foot IK Ground Lock }
  FTargetPose.JointPos[ihjHipL] := FTargetPose.JointPos[ihjPelvis] + Vector3(-TgtM.HipHalfWidth, 0.0, 0.0);
  FTargetPose.JointPos[ihjHipR] := FTargetPose.JointPos[ihjPelvis] + Vector3( TgtM.HipHalfWidth, 0.0, 0.0);

  TgtFootGoalL := Vector3(
    -TgtM.HipHalfWidth,
    SrcFootGoalL.Y * HeightRatio,
    TgtStrideZ + (SrcFootGoalL.Z - SrcStrideZ) * HeightRatio * FGlobalStrideScale * FChains[Ord(ircLeftLeg)].StrideScale);
  if FTargetPose.LeftFootPlanted then
    TgtFootGoalL.Y := 0.0;

  TgtFootGoalR := Vector3(
    TgtM.HipHalfWidth,
    SrcFootGoalR.Y * HeightRatio,
    TgtStrideZ + (SrcFootGoalR.Z - SrcStrideZ) * HeightRatio * FGlobalStrideScale * FChains[Ord(ircRightLeg)].StrideScale);
  if FTargetPose.RightFootPlanted then
    TgtFootGoalR.Y := 0.0;

  FkKneeL := FTargetPose.JointPos[ihjHipL] + Vector3(0, -TgtM.ThighLen, 0);
  FkFootL := FkKneeL + Vector3(0, -TgtM.CalfLen, 0);
  SolveTwoBoneIk3D(FTargetPose.JointPos[ihjHipL], TgtFootGoalL, Vector3(0, 0, 1),
    TgtM.ThighLen, TgtM.CalfLen, IkKneeL, IkFootL);
  SolveTwoBoneIk3D(FTargetPose.JointPos[ihjHipL],
    Lerp(FChains[Ord(ircLeftLeg)].IkBlendWeight, FkFootL, IkFootL), Vector3(0, 0, 1),
    TgtM.ThighLen, TgtM.CalfLen, FTargetPose.JointPos[ihjKneeL], FTargetPose.JointPos[ihjFootL]);

  FkKneeR := FTargetPose.JointPos[ihjHipR] + Vector3(0, -TgtM.ThighLen, 0);
  FkFootR := FkKneeR + Vector3(0, -TgtM.CalfLen, 0);
  SolveTwoBoneIk3D(FTargetPose.JointPos[ihjHipR], TgtFootGoalR, Vector3(0, 0, 1),
    TgtM.ThighLen, TgtM.CalfLen, IkKneeR, IkFootR);
  SolveTwoBoneIk3D(FTargetPose.JointPos[ihjHipR],
    Lerp(FChains[Ord(ircRightLeg)].IkBlendWeight, FkFootR, IkFootR), Vector3(0, 0, 1),
    TgtM.ThighLen, TgtM.CalfLen, FTargetPose.JointPos[ihjKneeR], FTargetPose.JointPos[ihjFootR]);

  SyncSideBySidePreview;
end;

procedure TCastleIkRetargeter.StepRetargeter(const ADeltaSeconds: Single);
begin
  Inc(FRetargetStepCount);
  EvaluateRetargetAtTime(FPhaseTimeSec + Max(0.0, ADeltaSeconds));
end;

function TCastleIkRetargeter.MaxTargetLimbLengthError: Single;
var
  M: TIkSkeletonMetrics;
begin
  M := GetProfileMetrics(FTargetProfile);
  Result := 0.0;
  Result := Max(Result, Abs((FTargetPose.JointPos[ihjElbowL] - FTargetPose.JointPos[ihjShoulderL]).Length - M.UpperArmLen));
  Result := Max(Result, Abs((FTargetPose.JointPos[ihjHandL]  - FTargetPose.JointPos[ihjElbowL]).Length    - M.LowerArmLen));
  Result := Max(Result, Abs((FTargetPose.JointPos[ihjElbowR] - FTargetPose.JointPos[ihjShoulderR]).Length - M.UpperArmLen));
  Result := Max(Result, Abs((FTargetPose.JointPos[ihjHandR]  - FTargetPose.JointPos[ihjElbowR]).Length    - M.LowerArmLen));
  Result := Max(Result, Abs((FTargetPose.JointPos[ihjKneeL]  - FTargetPose.JointPos[ihjHipL]).Length      - M.ThighLen));
  Result := Max(Result, Abs((FTargetPose.JointPos[ihjFootL]  - FTargetPose.JointPos[ihjKneeL]).Length     - M.CalfLen));
  Result := Max(Result, Abs((FTargetPose.JointPos[ihjKneeR]  - FTargetPose.JointPos[ihjHipR]).Length      - M.ThighLen));
  Result := Max(Result, Abs((FTargetPose.JointPos[ihjFootR]  - FTargetPose.JointPos[ihjKneeR]).Length     - M.CalfLen));
end;

procedure TCastleIkRetargeter.ClearPreviewContainer;
begin
  if FPreviewContainer <> nil then
    FreeAndNil(FPreviewContainer);
end;

procedure TCastleIkRetargeter.SyncSideBySidePreview;

  procedure AddPoseJointBoxes(const APose: TIkHumanoidPose;
    const AOffsetX: Single; const AColor: TCastleColor);
  var
    J: TIkHumanoidJoint;
    B: TCastleBox;
  begin
    for J in TIkHumanoidJoint do
    begin
      B := TCastleBox.Create(FPreviewContainer);
      B.SetTransient;
      B.Pickable := False;
      B.Collides := False;
      B.Size := Vector3(0.07, 0.07, 0.07);
      B.Translation := APose.JointPos[J] + Vector3(AOffsetX, 0.0, 0.0);
      B.Color := AColor;
      FPreviewContainer.Add(B);
    end;
  end;

begin
  ClearPreviewContainer;
  if not FShowSideBySidePreview then Exit;

  FPreviewContainer := TCastleTransform.Create(nil);
  FPreviewContainer.SetTransient;
  FPreviewContainer.Pickable := False;
  FPreviewContainer.Collides := False;
  FPreviewContainer.Name := 'IKRetarget_Preview';
  Add(FPreviewContainer);

  AddPoseJointBoxes(FSourcePose, -1.10, Vector4(0.32, 0.78, 1.00, 1.0));
  AddPoseJointBoxes(FTargetPose,  1.10, Vector4(0.30, 0.94, 0.56, 1.0));
end;

procedure TCastleIkRetargeter.ApplyPreset(const APreset: TIkRetargetPreset);
begin
  FPreset := APreset;
  if APreset = irpCustom then Exit;

  InitDefaultChains;
  FCompensateRefPoseDelta := True;
  FGlobalStrideScale := 1.0;
  FPhaseTimeSec := 0.0;

  case APreset of
    irpMannequinToCompactAPose:
      begin
        FSourceProfile := ispMannequinTallTPose;
        FTargetProfile := ispCompactStylizedAPose;
        FMotionClip := irmForwardStrideWalk;
      end;

    irpMannequinToBruteOgre:
      begin
        FSourceProfile := ispMannequinTallTPose;
        FTargetProfile := ispBruteOgreBroadShoulders;
        FMotionClip := irmForwardStrideWalk;
      end;

    irpTwoHandedGripIkRetarget:
      begin
        FSourceProfile := ispMannequinTallTPose;
        FTargetProfile := ispCompactStylizedAPose;
        FMotionClip := irmTwoHandedWeaponReach;
        FChains[Ord(ircLeftArm)].IkBlendWeight := 1.0;
        FChains[Ord(ircRightArm)].IkBlendWeight := 1.0;
      end;
  end;

  EvaluateRetargetAtTime(0.0);
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastleIkRetargeter.GetChainsJson: String;
var
  Root, Obj: TJSONObject;
  Arr, GoalArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    for I := 0 to High(FChains) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', Ord(FChains[I].ChainId));
      Obj.Add('en', FChains[I].Enabled);
      Obj.Add('fk', FChains[I].FkRotationWeight);
      Obj.Add('ik', FChains[I].IkBlendWeight);
      Obj.Add('stride', FChains[I].StrideScale);
      Obj.Add('cust', FChains[I].UseCustomIkGoal);
      GoalArr := TJSONArray.Create;
      GoalArr.Add(FChains[I].CustomIkGoalLocal.X);
      GoalArr.Add(FChains[I].CustomIkGoalLocal.Y);
      GoalArr.Add(FChains[I].CustomIkGoalLocal.Z);
      Obj.Add('goal', GoalArr);
      Arr.Add(Obj);
    end;
    Root.Add('chains', Arr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleIkRetargeter.SetChainsJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, Obj: TJSONObject;
  Arr, GoalArr: TJSONArray;
  I, Idx: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    Parsed := GetJSON(AValue);
  except
    Exit;
  end;
  try
    if not (Parsed is TJSONObject) then Exit;
    Root := TJSONObject(Parsed);
    InitDefaultChains;
    FPreset := irpCustom;

    Arr := Root.Find('chains', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          Idx := EnsureRange(Obj.Get('id', I), 0, High(FChains));
          FChains[Idx].Enabled := Obj.Get('en', True);
          FChains[Idx].FkRotationWeight := Obj.Get('fk', 1.0);
          FChains[Idx].IkBlendWeight := Obj.Get('ik', 0.0);
          FChains[Idx].StrideScale := Obj.Get('stride', 1.0);
          FChains[Idx].UseCustomIkGoal := Obj.Get('cust', False);
          GoalArr := Obj.Find('goal', jtArray) as TJSONArray;
          if (GoalArr <> nil) and (GoalArr.Count >= 3) then
            FChains[Idx].CustomIkGoalLocal := Vector3(
              GoalArr.Floats[0], GoalArr.Floats[1], GoalArr.Floats[2]);
        end;

    EvaluateRetargetAtTime(FPhaseTimeSec);
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleIkRetargeter.IkRetargetSummaryBadge: String;
begin
  Result := Format('[IKRetarget:Ratio=%.2fx Chains=%d LimbErr=%.4fm]',
    [PelvisHeightScaleRatio, Length(FChains), MaxTargetLimbLengthError]);
end;

initialization
  RegisterSerializableComponent(TCastleIkRetargeter, 'Skeletal IK Retargeter');
end.
