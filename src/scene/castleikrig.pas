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

{ Analytical law-of-cosines 3D Two-Bone IK solver, pole-vector bend control,
  downward ground foot-planting (@link(TCastleTwoBoneIkBehavior)), and angular
  cone-clamped damped Look-At constraints (@link(TCastleLookAtConstraintBehavior))
  (Phase 304 — UE 6.0 Control Rig, Full-Body IK & Aim Constraint Parity). }
unit CastleIkRig;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleVectors, CastleClassUtils, CastleUtils, CastleTransform;

type
  { Analytical 3D Two-Bone IK behavior solving Root -> MidJoint -> EndJoint
    toward @link(TargetTransform) in the @link(PoleTransform) plane, with
    optional soft-reach damping and downward raycast foot planting. }
  TCastleTwoBoneIkBehavior = class(TCastleBehavior)
  public const
    DefaultUpperBoneLength = Single(0.5);
    DefaultLowerBoneLength = Single(0.5);
    DefaultSoftReachMargin = Single(0.0);
    DefaultIkWeight = Single(1.0);
    DefaultFootHeightOffset = Single(0.08);
    DefaultGroundRayCastHeight = Single(1.2);
  strict private
    FMidJointTransform: TCastleTransform;
    FEndJointTransform: TCastleTransform;
    FTargetTransform: TCastleTransform;
    FPoleTransform: TCastleTransform;

    FUpperBoneLength: Single;
    FLowerBoneLength: Single;
    FSoftReachMargin: Single;
    FIkWeight: Single;
    FEnableGroundFootPlant: Boolean;
    FFootHeightOffset: Single;
    FGroundRayCastHeight: Single;
    FAlignFootToGroundNormal: Boolean;
    FAutoSolveEachFrame: Boolean;
    FShowRigInViewport: Boolean;

    FLastSolvedRootPos: TVector3;
    FLastSolvedMidPos: TVector3;
    FLastSolvedEndPos: TVector3;

    procedure SetMidJointTransform(const Value: TCastleTransform);
    procedure SetEndJointTransform(const Value: TCastleTransform);
    procedure SetTargetTransform(const Value: TCastleTransform);
    procedure SetPoleTransform(const Value: TCastleTransform);
    procedure SetUpperBoneLength(const Value: Single);
    procedure SetLowerBoneLength(const Value: Single);
    procedure SetSoftReachMargin(const Value: Single);
    procedure SetIkWeight(const Value: Single);
    procedure SetGroundRayCastHeight(const Value: Single);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Solve Two-Bone IK chain immediately and apply joint world transforms. }
    function SolveNow: Boolean;

    function IkSummaryBadge: String;

    property LastSolvedRootPos: TVector3 read FLastSolvedRootPos;
    property LastSolvedMidPos: TVector3 read FLastSolvedMidPos;
    property LastSolvedEndPos: TVector3 read FLastSolvedEndPos;
  published
    property MidJointTransform: TCastleTransform
      read FMidJointTransform write SetMidJointTransform;
    property EndJointTransform: TCastleTransform
      read FEndJointTransform write SetEndJointTransform;
    property TargetTransform: TCastleTransform
      read FTargetTransform write SetTargetTransform;
    property PoleTransform: TCastleTransform
      read FPoleTransform write SetPoleTransform;
    property UpperBoneLength: Single
      read FUpperBoneLength write SetUpperBoneLength
      {$ifdef FPC}default DefaultUpperBoneLength{$endif};
    property LowerBoneLength: Single
      read FLowerBoneLength write SetLowerBoneLength
      {$ifdef FPC}default DefaultLowerBoneLength{$endif};
    property SoftReachMargin: Single
      read FSoftReachMargin write SetSoftReachMargin
      {$ifdef FPC}default DefaultSoftReachMargin{$endif};
    property IkWeight: Single
      read FIkWeight write SetIkWeight
      {$ifdef FPC}default DefaultIkWeight{$endif};
    property EnableGroundFootPlant: Boolean
      read FEnableGroundFootPlant write FEnableGroundFootPlant default false;
    property FootHeightOffset: Single
      read FFootHeightOffset write FFootHeightOffset
      {$ifdef FPC}default DefaultFootHeightOffset{$endif};
    property GroundRayCastHeight: Single
      read FGroundRayCastHeight write SetGroundRayCastHeight
      {$ifdef FPC}default DefaultGroundRayCastHeight{$endif};
    property AlignFootToGroundNormal: Boolean
      read FAlignFootToGroundNormal write FAlignFootToGroundNormal default true;
    property AutoSolveEachFrame: Boolean
      read FAutoSolveEachFrame write FAutoSolveEachFrame default true;
    property ShowRigInViewport: Boolean
      read FShowRigInViewport write FShowRigInViewport default true;
  end;

  { Angular cone-clamped & damped Look-At aim constraint behavior for heads,
    turrets, eyes, and tracking cameras. }
  TCastleLookAtConstraintBehavior = class(TCastleBehavior)
  public const
    DefaultMaxYawDeg = Single(75.0);
    DefaultMaxPitchDeg = Single(50.0);
    DefaultWeight = Single(1.0);
    DefaultDampingSpeed = Single(12.0);
  strict private
    FLookTarget: TCastleTransform;
    FMaxYawDeg: Single;
    FMaxPitchDeg: Single;
    FWeight: Single;
    FDampingSpeed: Single;
    FReferenceForward: TVector3;
    FReferenceForwardPersistent: TCastleVector3Persistent;
    FAutoSolveEachFrame: Boolean;
    FShowConeInViewport: Boolean;

    function GetReferenceForwardForPersistent: TVector3;
    procedure SetReferenceForwardForPersistent(const AValue: TVector3);
    procedure SetReferenceForward(const Value: TVector3);
    procedure SetLookTarget(const Value: TCastleTransform);
    procedure SetMaxYawDeg(const Value: Single);
    procedure SetMaxPitchDeg(const Value: Single);
    procedure SetWeight(const Value: Single);
    procedure SetDampingSpeed(const Value: Single);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Solve Look-At aim constraint immediately (@code(ADeltaSeconds = 0) snaps
      instantly; @code(> 0) applies exponential @link(DampingSpeed) smoothing). }
    function ApplyLookAt(const ADeltaSeconds: Single = 0.0): Boolean;

    function LookAtSummaryBadge: String;

    property ReferenceForward: TVector3
      read FReferenceForward write SetReferenceForward;
  published
    property LookTarget: TCastleTransform
      read FLookTarget write SetLookTarget;
    property MaxYawDeg: Single
      read FMaxYawDeg write SetMaxYawDeg
      {$ifdef FPC}default DefaultMaxYawDeg{$endif};
    property MaxPitchDeg: Single
      read FMaxPitchDeg write SetMaxPitchDeg
      {$ifdef FPC}default DefaultMaxPitchDeg{$endif};
    property Weight: Single
      read FWeight write SetWeight
      {$ifdef FPC}default DefaultWeight{$endif};
    property DampingSpeed: Single
      read FDampingSpeed write SetDampingSpeed
      {$ifdef FPC}default DefaultDampingSpeed{$endif};
    property ReferenceForwardPersistent: TCastleVector3Persistent
      read FReferenceForwardPersistent;
    property AutoSolveEachFrame: Boolean
      read FAutoSolveEachFrame write FAutoSolveEachFrame default true;
    property ShowConeInViewport: Boolean
      read FShowConeInViewport write FShowConeInViewport default true;
  end;

{ Closed-form law-of-cosines 3D Two-Bone IK solver.
  Guarantees @code(|OutMidJointPos - ARootPos| = AUpperLen),
  @code(|OutEffectorPos - OutMidJointPos| = ALowerLen), and places
  @code(OutMidJointPos) in the half-plane toward @code(APolePos). }
procedure SolveAnalyticalTwoBoneIk(
  const ARootPos, ATargetPos, APolePos: TVector3;
  const AUpperLen, ALowerLen, ASoftReachMargin: Single;
  out OutMidJointPos, OutEffectorPos: TVector3);

{ Accumulated hierarchy 4x4 matrix of @code(T) up to the design/world root. }
function GetIkHierarchyMatrix(const T: TCastleTransform): TMatrix4;

implementation

uses
  CastleComponentSerialize;

function GetIkHierarchyMatrix(const T: TCastleTransform): TMatrix4;
var
  Cur: TCastleTransform;
begin
  Result := TMatrix4.Identity;
  Cur := T;
  while (Cur <> nil) and (not (Cur is TCastleAbstractRootTransform)) do
  begin
    Result := Cur.Transform * Result;
    Cur := Cur.Parent;
  end;
end;

function GetIkWorldPos(const T: TCastleTransform): TVector3;
var
  M: TMatrix4;
begin
  if T = nil then
    Exit(TVector3.Zero);
  M := GetIkHierarchyMatrix(T);
  Result := M.MultPoint(TVector3.Zero);
end;

procedure SetIkWorldPosAndView(const T: TCastleTransform;
  const AWorldPos, AWorldDir, AWorldUp: TVector3);
var
  ParentM, InvM: TMatrix4;
  LocalPos, LocalDir, LocalUp: TVector3;
begin
  if T = nil then
    Exit;

  if (T.Parent <> nil) and
     (not (T.Parent is TCastleAbstractRootTransform)) then
  begin
    ParentM := GetIkHierarchyMatrix(T.Parent);
    if ParentM.TryInverse(InvM) then
    begin
      LocalPos := InvM.MultPoint(AWorldPos);
      LocalDir := InvM.MultDirection(AWorldDir);
      LocalUp := InvM.MultDirection(AWorldUp);
    end else
    begin
      LocalPos := AWorldPos;
      LocalDir := AWorldDir;
      LocalUp := AWorldUp;
    end;
  end else
  begin
    LocalPos := AWorldPos;
    LocalDir := AWorldDir;
    LocalUp := AWorldUp;
  end;

  if LocalDir.LengthSqr < 1e-8 then
    LocalDir := Vector3(0.0, 0.0, 1.0)
  else
    LocalDir := LocalDir.Normalize;
  if LocalUp.LengthSqr < 1e-8 then
    LocalUp := Vector3(0.0, 1.0, 0.0)
  else
    LocalUp := LocalUp.Normalize;
  MakeVectorsOrthoOnTheirPlane(LocalUp, LocalDir);
  if LocalUp.LengthSqr < 1e-8 then
  begin
    if Abs(LocalDir.Y) < 0.9 then
      LocalUp := Vector3(0.0, 1.0, 0.0)
    else
      LocalUp := Vector3(1.0, 0.0, 0.0);
    MakeVectorsOrthoOnTheirPlane(LocalUp, LocalDir);
  end;
  LocalUp := LocalUp.Normalize;

  T.SetView(LocalPos, LocalDir, LocalUp);
end;

procedure SolveAnalyticalTwoBoneIk(
  const ARootPos, ATargetPos, APolePos: TVector3;
  const AUpperLen, ALowerLen, ASoftReachMargin: Single;
  out OutMidJointPos, OutEffectorPos: TVector3);
var
  L1, L2, MinD, MaxD, RawDist, D, SoftStart, CosAlpha, SinAlpha: Single;
  RawVec, ReachDir, PoleVec, BendPerp, FallbackAxis: TVector3;
begin
  L1 := Max(0.01, AUpperLen);
  L2 := Max(0.01, ALowerLen);
  MinD := Abs(L1 - L2) + 1e-4;
  MaxD := L1 + L2 - 1e-4;
  if MinD > MaxD then
    MinD := MaxD;

  RawVec := ATargetPos - ARootPos;
  RawDist := RawVec.Length;
  if RawDist < 1e-6 then
    ReachDir := Vector3(0.0, -1.0, 0.0)
  else
    ReachDir := RawVec / RawDist;

  if (ASoftReachMargin > 1e-4) and (RawDist > MaxD - ASoftReachMargin) then
  begin
    SoftStart := Max(MinD, MaxD - ASoftReachMargin);
    D := SoftStart + ASoftReachMargin *
      (1.0 - Exp(-Max(0.0, RawDist - SoftStart) / ASoftReachMargin));
    D := Clamped(D, MinD, MaxD);
  end else
    D := Clamped(RawDist, MinD, MaxD);

  CosAlpha := Clamped(
    (Sqr(L1) + Sqr(D) - Sqr(L2)) / (2.0 * L1 * D),
    -1.0, 1.0);
  SinAlpha := Sqrt(Max(0.0, 1.0 - Sqr(CosAlpha)));

  PoleVec := APolePos - ARootPos;
  BendPerp := PoleVec - ReachDir * TVector3.DotProduct(PoleVec, ReachDir);
  if BendPerp.LengthSqr < 1e-8 then
  begin
    if Abs(ReachDir.Z) < 0.9 then
      FallbackAxis := Vector3(0.0, 0.0, 1.0)
    else
      FallbackAxis := Vector3(1.0, 0.0, 0.0);
    BendPerp := FallbackAxis - ReachDir * TVector3.DotProduct(FallbackAxis, ReachDir);
  end;
  BendPerp := BendPerp.Normalize;

  OutMidJointPos := ARootPos + (ReachDir * CosAlpha + BendPerp * SinAlpha) * L1;
  OutEffectorPos := ARootPos + ReachDir * D;
end;

{ TCastleTwoBoneIkBehavior --------------------------------------------------- }

constructor TCastleTwoBoneIkBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FUpperBoneLength := DefaultUpperBoneLength;
  FLowerBoneLength := DefaultLowerBoneLength;
  FSoftReachMargin := DefaultSoftReachMargin;
  FIkWeight := DefaultIkWeight;
  FEnableGroundFootPlant := false;
  FFootHeightOffset := DefaultFootHeightOffset;
  FGroundRayCastHeight := DefaultGroundRayCastHeight;
  FAlignFootToGroundNormal := true;
  FAutoSolveEachFrame := true;
  FShowRigInViewport := true;
end;

destructor TCastleTwoBoneIkBehavior.Destroy;
begin
  SetMidJointTransform(nil);
  SetEndJointTransform(nil);
  SetTargetTransform(nil);
  SetPoleTransform(nil);
  inherited;
end;

procedure TCastleTwoBoneIkBehavior.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FMidJointTransform then FMidJointTransform := nil;
    if AComponent = FEndJointTransform then FEndJointTransform := nil;
    if AComponent = FTargetTransform then FTargetTransform := nil;
    if AComponent = FPoleTransform then FPoleTransform := nil;
  end;
end;

procedure TCastleTwoBoneIkBehavior.SetMidJointTransform(const Value: TCastleTransform);
begin
  if FMidJointTransform <> Value then
  begin
    if FMidJointTransform <> nil then FMidJointTransform.RemoveFreeNotification(Self);
    FMidJointTransform := Value;
    if FMidJointTransform <> nil then FMidJointTransform.FreeNotification(Self);
  end;
end;

procedure TCastleTwoBoneIkBehavior.SetEndJointTransform(const Value: TCastleTransform);
begin
  if FEndJointTransform <> Value then
  begin
    if FEndJointTransform <> nil then FEndJointTransform.RemoveFreeNotification(Self);
    FEndJointTransform := Value;
    if FEndJointTransform <> nil then FEndJointTransform.FreeNotification(Self);
  end;
end;

procedure TCastleTwoBoneIkBehavior.SetTargetTransform(const Value: TCastleTransform);
begin
  if FTargetTransform <> Value then
  begin
    if FTargetTransform <> nil then FTargetTransform.RemoveFreeNotification(Self);
    FTargetTransform := Value;
    if FTargetTransform <> nil then FTargetTransform.FreeNotification(Self);
  end;
end;

procedure TCastleTwoBoneIkBehavior.SetPoleTransform(const Value: TCastleTransform);
begin
  if FPoleTransform <> Value then
  begin
    if FPoleTransform <> nil then FPoleTransform.RemoveFreeNotification(Self);
    FPoleTransform := Value;
    if FPoleTransform <> nil then FPoleTransform.FreeNotification(Self);
  end;
end;

procedure TCastleTwoBoneIkBehavior.SetUpperBoneLength(const Value: Single);
begin
  FUpperBoneLength := Max(0.02, Value);
end;

procedure TCastleTwoBoneIkBehavior.SetLowerBoneLength(const Value: Single);
begin
  FLowerBoneLength := Max(0.02, Value);
end;

procedure TCastleTwoBoneIkBehavior.SetSoftReachMargin(const Value: Single);
begin
  FSoftReachMargin := Clamped(Value, 0.0, 5.0);
end;

procedure TCastleTwoBoneIkBehavior.SetIkWeight(const Value: Single);
begin
  FIkWeight := Clamped(Value, 0.0, 1.0);
end;

procedure TCastleTwoBoneIkBehavior.SetGroundRayCastHeight(const Value: Single);
begin
  FGroundRayCastHeight := Max(0.1, Value);
end;

function TCastleTwoBoneIkBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'MidJointTransform', 'EndJointTransform', 'TargetTransform', 'PoleTransform',
       'UpperBoneLength', 'LowerBoneLength', 'SoftReachMargin', 'IkWeight',
       'EnableGroundFootPlant', 'FootHeightOffset', 'GroundRayCastHeight',
       'AlignFootToGroundNormal', 'AutoSolveEachFrame', 'ShowRigInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleTwoBoneIkBehavior.SolveNow: Boolean;
var
  RootPosW, TargetPosW, PolePosW, CurMidW, CurEndW: TVector3;
  SolvedMidW, SolvedEndW, BlendedMidW, BlendedEndW: TVector3;
  GroundNormW, RayStartW, UpperDirW, LowerDirW, PoleHintDirW, FootFwdW: TVector3;
  RayHit: TRayCollision;
  SavedPickR, SavedPickM, SavedPickE: Boolean;
begin
  Result := false;
  if (Parent = nil) or (FMidJointTransform = nil) or (FEndJointTransform = nil) then
    Exit;

  RootPosW := GetIkWorldPos(Parent);
  CurMidW := GetIkWorldPos(FMidJointTransform);
  CurEndW := GetIkWorldPos(FEndJointTransform);

  if FTargetTransform <> nil then
    TargetPosW := GetIkWorldPos(FTargetTransform)
  else
    TargetPosW := CurEndW;

  if FPoleTransform <> nil then
    PolePosW := GetIkWorldPos(FPoleTransform)
  else
    PolePosW := RootPosW + Vector3(0.0, 0.0, 1.0);

  GroundNormW := Vector3(0.0, 1.0, 0.0);
  if FEnableGroundFootPlant and (Parent.World <> nil) then
  begin
    SavedPickR := Parent.Pickable;
    SavedPickM := FMidJointTransform.Pickable;
    SavedPickE := FEndJointTransform.Pickable;
    Parent.Pickable := false;
    FMidJointTransform.Pickable := false;
    FEndJointTransform.Pickable := false;
    try
      RayStartW := TargetPosW + Vector3(0.0, FGroundRayCastHeight, 0.0);
      RayHit := Parent.World.WorldRay(RayStartW, Vector3(0.0, -1.0, 0.0));
      if RayHit <> nil then
      try
        if (RayHit.Transform <> nil) and
           (RayHit.Distance <= FGroundRayCastHeight * 2.5) then
        begin
          TargetPosW.Y := RayStartW.Y - RayHit.Distance + FFootHeightOffset;
          if (RayHit.Count > 0) and (RayHit.First.Triangle <> nil) and
             (RayHit.First.Item <> nil) and RayHit.First.Item.HasWorldTransform then
          begin
            GroundNormW := RayHit.First.Item.LocalToWorldDirection(
              RayHit.First.Triangle^.SceneSpace.Normal);
            if GroundNormW.LengthSqr < 1e-8 then
              GroundNormW := Vector3(0.0, 1.0, 0.0)
            else
              GroundNormW := GroundNormW.Normalize;
            if GroundNormW.Y < 0.0 then
              GroundNormW := -GroundNormW;
          end;
        end;
      finally
        FreeAndNil(RayHit);
      end;
    finally
      Parent.Pickable := SavedPickR;
      FMidJointTransform.Pickable := SavedPickM;
      FEndJointTransform.Pickable := SavedPickE;
    end;
  end;

  SolveAnalyticalTwoBoneIk(RootPosW, TargetPosW, PolePosW,
    FUpperBoneLength, FLowerBoneLength, FSoftReachMargin,
    SolvedMidW, SolvedEndW);

  BlendedMidW := Lerp(FIkWeight, CurMidW, SolvedMidW);
  BlendedEndW := Lerp(FIkWeight, CurEndW, SolvedEndW);

  UpperDirW := BlendedMidW - RootPosW;
  LowerDirW := BlendedEndW - BlendedMidW;
  PoleHintDirW := PolePosW - RootPosW;

  { Update top-down so both nested (Hip->Knee->Foot) and sibling hierarchies match exact world coords }
  SetIkWorldPosAndView(Parent, RootPosW, UpperDirW, PoleHintDirW);
  SetIkWorldPosAndView(FMidJointTransform, BlendedMidW, LowerDirW, PoleHintDirW);

  FootFwdW := PolePosW - BlendedEndW;
  FootFwdW.Y := 0.0;
  if FootFwdW.LengthSqr < 1e-6 then
    FootFwdW := Vector3(0.0, 0.0, 1.0);
  if FEnableGroundFootPlant and FAlignFootToGroundNormal then
    SetIkWorldPosAndView(FEndJointTransform, BlendedEndW, FootFwdW, GroundNormW)
  else
    SetIkWorldPosAndView(FEndJointTransform, BlendedEndW, FootFwdW, Vector3(0.0, 1.0, 0.0));

  FLastSolvedRootPos := RootPosW;
  FLastSolvedMidPos := BlendedMidW;
  FLastSolvedEndPos := BlendedEndW;
  Result := true;
end;

procedure TCastleTwoBoneIkBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited;
  if FAutoSolveEachFrame and (not CastleDesignMode) then
    SolveNow;
end;

function TCastleTwoBoneIkBehavior.IkSummaryBadge: String;
begin
  Result := Format('[2BoneIK:%.2f+%.2fm]', [FUpperBoneLength, FLowerBoneLength]);
end;

{ TCastleLookAtConstraintBehavior -------------------------------------------- }

constructor TCastleLookAtConstraintBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLookTarget := nil;
  FMaxYawDeg := DefaultMaxYawDeg;
  FMaxPitchDeg := DefaultMaxPitchDeg;
  FWeight := DefaultWeight;
  FDampingSpeed := DefaultDampingSpeed;
  FReferenceForward := Vector3(0.0, 0.0, 1.0);
  FAutoSolveEachFrame := true;
  FShowConeInViewport := true;

  FReferenceForwardPersistent := TCastleVector3Persistent.Create(nil);
  FReferenceForwardPersistent.InternalGetValue := @GetReferenceForwardForPersistent;
  FReferenceForwardPersistent.InternalSetValue := @SetReferenceForwardForPersistent;
  FReferenceForwardPersistent.InternalDefaultValue := FReferenceForward;
end;

destructor TCastleLookAtConstraintBehavior.Destroy;
begin
  SetLookTarget(nil);
  FreeAndNil(FReferenceForwardPersistent);
  inherited;
end;

procedure TCastleLookAtConstraintBehavior.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FLookTarget) then
    FLookTarget := nil;
end;

function TCastleLookAtConstraintBehavior.GetReferenceForwardForPersistent: TVector3;
begin
  Result := FReferenceForward;
end;

procedure TCastleLookAtConstraintBehavior.SetReferenceForwardForPersistent(
  const AValue: TVector3);
begin
  SetReferenceForward(AValue);
end;

procedure TCastleLookAtConstraintBehavior.SetReferenceForward(const Value: TVector3);
begin
  if Value.LengthSqr < 1e-8 then
    FReferenceForward := Vector3(0.0, 0.0, 1.0)
  else
    FReferenceForward := Value.Normalize;
end;

procedure TCastleLookAtConstraintBehavior.SetLookTarget(const Value: TCastleTransform);
begin
  if FLookTarget <> Value then
  begin
    if FLookTarget <> nil then FLookTarget.RemoveFreeNotification(Self);
    FLookTarget := Value;
    if FLookTarget <> nil then FLookTarget.FreeNotification(Self);
  end;
end;

procedure TCastleLookAtConstraintBehavior.SetMaxYawDeg(const Value: Single);
begin
  FMaxYawDeg := Clamped(Value, 1.0, 180.0);
end;

procedure TCastleLookAtConstraintBehavior.SetMaxPitchDeg(const Value: Single);
begin
  FMaxPitchDeg := Clamped(Value, 1.0, 89.5);
end;

procedure TCastleLookAtConstraintBehavior.SetWeight(const Value: Single);
begin
  FWeight := Clamped(Value, 0.0, 1.0);
end;

procedure TCastleLookAtConstraintBehavior.SetDampingSpeed(const Value: Single);
begin
  FDampingSpeed := Max(0.0, Value);
end;

function TCastleLookAtConstraintBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'LookTarget', 'MaxYawDeg', 'MaxPitchDeg', 'Weight', 'DampingSpeed',
       'ReferenceForwardPersistent', 'AutoSolveEachFrame', 'ShowConeInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleLookAtConstraintBehavior.ApplyLookAt(
  const ADeltaSeconds: Single): Boolean;
var
  SelfPosW, TargetPosW, ToTargetW: TVector3;
  ParentM, SelfM: TMatrix4;
  RefFwdW, RefUpW, RefRightW, CurDirW, ClampedDirW, BlendedDirW, FinalDirW: TVector3;
  YawRad, PitchRad, MaxYawR, MaxPitchR, CosP, Alpha: Single;
begin
  Result := false;
  if (Parent = nil) or (FLookTarget = nil) then
    Exit;

  SelfPosW := GetIkWorldPos(Parent);
  TargetPosW := GetIkWorldPos(FLookTarget);
  ToTargetW := TargetPosW - SelfPosW;
  if ToTargetW.LengthSqr < 1e-8 then
    Exit;
  ToTargetW := ToTargetW.Normalize;

  if (Parent.Parent <> nil) and
     (not (Parent.Parent is TCastleAbstractRootTransform)) then
    ParentM := GetIkHierarchyMatrix(Parent.Parent)
  else
    ParentM := TMatrix4.Identity;

  RefFwdW := ParentM.MultDirection(FReferenceForward);
  if RefFwdW.LengthSqr < 1e-8 then
    RefFwdW := Vector3(0.0, 0.0, 1.0)
  else
    RefFwdW := RefFwdW.Normalize;
  RefUpW := ParentM.MultDirection(Vector3(0.0, 1.0, 0.0));
  if RefUpW.LengthSqr < 1e-8 then
    RefUpW := Vector3(0.0, 1.0, 0.0)
  else
    RefUpW := RefUpW.Normalize;
  MakeVectorsOrthoOnTheirPlane(RefUpW, RefFwdW);
  RefUpW := RefUpW.Normalize;
  RefRightW := TVector3.CrossProduct(RefUpW, RefFwdW).Normalize;

  YawRad := ArcTan2(
    TVector3.DotProduct(ToTargetW, RefRightW),
    TVector3.DotProduct(ToTargetW, RefFwdW));
  PitchRad := ArcSin(Clamped(TVector3.DotProduct(ToTargetW, RefUpW), -1.0, 1.0));

  MaxYawR := DegToRad(FMaxYawDeg);
  MaxPitchR := DegToRad(FMaxPitchDeg);
  YawRad := Clamped(YawRad, -MaxYawR, MaxYawR);
  PitchRad := Clamped(PitchRad, -MaxPitchR, MaxPitchR);

  CosP := Cos(PitchRad);
  ClampedDirW := (
    RefFwdW * (CosP * Cos(YawRad)) +
    RefRightW * (CosP * Sin(YawRad)) +
    RefUpW * Sin(PitchRad)).Normalize;

  BlendedDirW := Lerp(FWeight, RefFwdW, ClampedDirW);
  if BlendedDirW.LengthSqr < 1e-8 then
    BlendedDirW := RefFwdW
  else
    BlendedDirW := BlendedDirW.Normalize;

  if (ADeltaSeconds > 0.0) and (FDampingSpeed > 0.0) then
  begin
    SelfM := GetIkHierarchyMatrix(Parent);
    CurDirW := SelfM.MultDirection(Vector3(0.0, 0.0, 1.0));
    if CurDirW.LengthSqr < 1e-8 then
      CurDirW := RefFwdW
    else
      CurDirW := CurDirW.Normalize;
    Alpha := 1.0 - Exp(-FDampingSpeed * ADeltaSeconds);
    FinalDirW := Lerp(Alpha, CurDirW, BlendedDirW);
    if FinalDirW.LengthSqr < 1e-8 then
      FinalDirW := BlendedDirW
    else
      FinalDirW := FinalDirW.Normalize;
  end else
    FinalDirW := BlendedDirW;

  SetIkWorldPosAndView(Parent, SelfPosW, FinalDirW, RefUpW);
  Result := true;
end;

procedure TCastleLookAtConstraintBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited;
  if FAutoSolveEachFrame and (not CastleDesignMode) then
    ApplyLookAt(SecondsPassed);
end;

function TCastleLookAtConstraintBehavior.LookAtSummaryBadge: String;
begin
  Result := Format('[LookAt:±%.0f°/±%.0f°]', [FMaxYawDeg, FMaxPitchDeg]);
end;

initialization
  RegisterSerializableComponent(TCastleTwoBoneIkBehavior,
    ['Animation & Rigging', 'Two-Bone IK Behavior']);
  RegisterSerializableComponent(TCastleLookAtConstraintBehavior,
    ['Animation & Rigging', 'Look-At Constraint Behavior']);
end.
