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

{ Unreal Engine 5.5-style Physics Asset Editor (PhAT / UPhysicsAsset) runtime
  (@link(TCastlePhysicsAsset)) featuring per-bone Capsule / Box / Sphere body
  fitting with analytic density-driven mass calculation, Simulated vs. Kinematic
  pinning, elliptical Swing1 / Swing2 & Twist angular joint constraint cones,
  symmetric Bone-Pair Collision Disable Matrix, interactive impulse poke
  simulation, and transient 3D ragdoll collider visualization
  (Phase 388 — UE 5.5 UPhysicsAsset & USkeletalBodySetup Parity). }
unit CastlePhysicsAsset;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Collision primitive shape fitted onto a skeletal bone (USkeletalBodySetup). }
  TPhAtShapeKind = (
    pskSphere,
    pskCapsule,
    pskBox
  );

  { Per-body simulation mode (EPhysicsType parity). }
  TPhAtPhysicsType = (
    pptSimulated,
    pptKinematic
  );

  { Built-in UE 5.5 PhAT Physics Asset starter presets. }
  TPhAtAssetPreset = (
    papCustom,
    papHumanoidRagdoll11Bodies,
    papKinematicPinnedUpperBodyTest,
    papHeavyArmoredBruteRagdoll
  );

  { Single skeletal bone collision body (USkeletalBodySetup parity). }
  TPhAtBodySetup = record
    BodyName: String;
    ShapeKind: TPhAtShapeKind;
    PhysicsType: TPhAtPhysicsType;
    Radius: Single;
    LengthMeters: Single;
    BoxExtents: TVector3;
    DensityKgPerM3: Single;
    MassKg: Single;
    RestPos: TVector3;
    { Live simulated ragdoll state }
    Position: TVector3;
    PrevPosition: TVector3;
    Velocity: TVector3;
    TwistAngleDeg: Single;
  end;
  TPhAtBodySetupArray = array of TPhAtBodySetup;

  { Angular joint constraint connecting ParentBody -> ChildBody (UPhysicsConstraintTemplate). }
  TPhAtJointConstraint = record
    ConstraintName: String;
    ParentBodyIndex: Integer;
    ChildBodyIndex: Integer;
    RestLength: Single;
    RestDir: TVector3;
    Swing1LimitDeg: Single; { Sagittal / Z swing cone half-angle }
    Swing2LimitDeg: Single; { Coronal / X swing cone half-angle }
    TwistLimitDeg: Single;  { Axial bone twist limit }
    DisableParentChildCollision: Boolean;
  end;
  TPhAtJointConstraintArray = array of TPhAtJointConstraint;

  { Symmetric pair entry in the Bone-Pair Collision Disable Table. }
  TPhAtDisabledPair = record
    BodyIndexA: Integer;
    BodyIndexB: Integer;
  end;
  TPhAtDisabledPairArray = array of TPhAtDisabledPair;

  { Unreal Engine 5.5-style Physics Asset (PhAT) ragdoll & joint-cone component. }
  TCastlePhysicsAsset = class(TCastleTransform)
  private
    FPreset: TPhAtAssetPreset;
    FGravityY: Single;
    FLinearDamping: Single;
    FFloorRestitution: Single;
    FSolverIterations: Integer;
    FShowColliderWirePreview: Boolean;

    FBodies: TPhAtBodySetupArray;
    FConstraints: TPhAtJointConstraintArray;
    FDisabledPairs: TPhAtDisabledPairArray;

    { Diagnostics }
    FSimTimeSec: Single;
    FPokeImpulseCount: Integer;
    FNonAdjacentBodyContacts: Integer;
    FPreviewContainer: TCastleTransform;

    procedure SetPreset(const AValue: TPhAtAssetPreset);
    procedure SetShowColliderWirePreview(const AValue: Boolean);
    function GetPhysicsAssetJson: String;
    procedure SetPhysicsAssetJson(const AValue: String);

    procedure ClearPreviewContainer;
    procedure SyncPreviewColliders;
    class function ClampDirectionToEllipticalSwingCone(
      const ADir, ARestDir: TVector3;
      const ASwing1Deg, ASwing2Deg: Single): TVector3; static;
    class function ComputeEllipticalSwingViolationDeg(
      const ADir, ARestDir: TVector3;
      const ASwing1Deg, ASwing2Deg: Single): Single; static;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Analytic geometry & mass calculation }
    class function ComputeBodyVolumeM3(const AShape: TPhAtShapeKind;
      const ARadius, ALength: Single; const ABoxExtents: TVector3): Single; static;
    class function ComputeBodyMassKg(const AShape: TPhAtShapeKind;
      const ARadius, ALength: Single; const ABoxExtents: TVector3;
      const ADensityKgPerM3: Single): Single; static;
    class function ShapeKindTitle(const AShape: TPhAtShapeKind): String; static;

    { Body, Constraint & Collision Matrix API }
    procedure ClearAsset;
    procedure ApplyPreset(const APreset: TPhAtAssetPreset);
    function FindBodyIndex(const ABodyName: String): Integer;
    function AddBody(const AName: String; const AShape: TPhAtShapeKind;
      const APhysType: TPhAtPhysicsType; const ARestPos: TVector3;
      const ARadius, ALength: Single; const ABoxExtents: TVector3;
      const ADensityKgPerM3: Single = 1020.0): Integer;
    procedure SetBodyPhysicsType(const ABodyName: String; const APhysType: TPhAtPhysicsType);
    function AddConstraint(const AParentBody, AChildBody: String;
      const ASwing1Deg, ASwing2Deg, ATwistDeg: Single): Integer;
    procedure SetConstraintLimits(const AConstraintIdx: Integer;
      const ASwing1Deg, ASwing2Deg, ATwistDeg: Single);

    procedure SetPairCollisionEnabled(const AIdxA, AIdxB: Integer; const AEnabled: Boolean);
    function IsPairCollisionEnabled(const AIdxA, AIdxB: Integer): Boolean;
    procedure DisableAllAdjacentBoneCollisions;

    { Ragdoll PBD Simulation & Interactive Poke Testing }
    procedure ResetToRestPose;
    function ApplyPokeImpulse(const ABodyName: String; const AImpulseNs: TVector3): Boolean;
    procedure StepSimulation(const ADeltaSeconds: Single);

    function TotalMassKg: Single;
    function DisabledPairCount: Integer;
    function MaxConstraintStretchErrorMeters: Single;
    function MaxConstraintConeViolationDeg: Single;
    function PhAtSummaryBadge: String;

    property Bodies: TPhAtBodySetupArray read FBodies;
    property Constraints: TPhAtJointConstraintArray read FConstraints;
    property SimTimeSec: Single read FSimTimeSec;
    property PokeImpulseCount: Integer read FPokeImpulseCount;
    property NonAdjacentBodyContacts: Integer read FNonAdjacentBodyContacts;
  published
    property GravityY: Single read FGravityY write FGravityY;
    property LinearDamping: Single read FLinearDamping write FLinearDamping;
    property FloorRestitution: Single read FFloorRestitution write FFloorRestitution;
    property SolverIterations: Integer read FSolverIterations write FSolverIterations default 8;
    property ShowColliderWirePreview: Boolean
      read FShowColliderWirePreview write SetShowColliderWirePreview default True;
    property PhysicsAssetJson: String read GetPhysicsAssetJson write SetPhysicsAssetJson;
    property Preset: TPhAtAssetPreset read FPreset write SetPreset default papHumanoidRagdoll11Bodies;
  end;

implementation

uses
  fpjson, jsonparser;

{ Analytic Volume & Mass Helpers --------------------------------------------- }

class function TCastlePhysicsAsset.ComputeBodyVolumeM3(
  const AShape: TPhAtShapeKind; const ARadius, ALength: Single;
  const ABoxExtents: TVector3): Single;
var
  R, L: Single;
begin
  R := Max(0.005, ARadius);
  L := Max(0.0, ALength);
  case AShape of
    pskSphere:
      Result := (4.0 / 3.0) * Pi * R * R * R;
    pskCapsule:
      Result := Pi * R * R * L + (4.0 / 3.0) * Pi * R * R * R;
    pskBox:
      Result := Max(0.01, ABoxExtents.X) * Max(0.01, ABoxExtents.Y) * Max(0.01, ABoxExtents.Z);
  end;
end;

class function TCastlePhysicsAsset.ComputeBodyMassKg(
  const AShape: TPhAtShapeKind; const ARadius, ALength: Single;
  const ABoxExtents: TVector3; const ADensityKgPerM3: Single): Single;
begin
  Result := Max(0.05,
    ComputeBodyVolumeM3(AShape, ARadius, ALength, ABoxExtents) * Max(10.0, ADensityKgPerM3));
end;

class function TCastlePhysicsAsset.ShapeKindTitle(
  const AShape: TPhAtShapeKind): String;
begin
  case AShape of
    pskSphere:  Result := 'Sphere';
    pskCapsule: Result := 'Capsule';
    pskBox:     Result := 'Box';
  end;
end;

{ Elliptical Swing1 / Swing2 Cone Math --------------------------------------- }

procedure BuildRestOrthonormalBasis(const ARestDir: TVector3;
  out AxisRest, AxisSwing1, AxisSwing2: TVector3);
var
  RefUp: TVector3;
begin
  if ARestDir.LengthSqr < 1e-8 then
    AxisRest := Vector3(0, -1, 0)
  else
    AxisRest := ARestDir.Normalize;

  if Abs(AxisRest.Z) < 0.90 then
    RefUp := Vector3(0, 0, 1)
  else
    RefUp := Vector3(1, 0, 0);

  AxisSwing2 := TVector3.CrossProduct(AxisRest, RefUp).Normalize;
  AxisSwing1 := TVector3.CrossProduct(AxisSwing2, AxisRest).Normalize;
end;

class function TCastlePhysicsAsset.ClampDirectionToEllipticalSwingCone(
  const ADir, ARestDir: TVector3;
  const ASwing1Deg, ASwing2Deg: Single): TVector3;
var
  AxisR, Axis1, Axis2, D: TVector3;
  DotR, TotalAngleRad, Proj1, Proj2, LatLen,Ang1Deg, Ang2Deg: Single;
  Lim1, Lim2, NormEll, ClampedAngleRad: Single;
begin
  BuildRestOrthonormalBasis(ARestDir, AxisR, Axis1, Axis2);
  if ADir.LengthSqr < 1e-8 then Exit(AxisR);
  D := ADir.Normalize;

  Lim1 := EnsureRange(ASwing1Deg, 1.0, 175.0);
  Lim2 := EnsureRange(ASwing2Deg, 1.0, 175.0);

  DotR := EnsureRange(TVector3.DotProduct(D, AxisR), -1.0, 1.0);
  TotalAngleRad := ArcCos(DotR);
  if TotalAngleRad < 1e-5 then Exit(D);

  Proj1 := TVector3.DotProduct(D, Axis1);
  Proj2 := TVector3.DotProduct(D, Axis2);
  LatLen := Sqrt(Proj1 * Proj1 + Proj2 * Proj2);
  if LatLen < 1e-6 then
  begin
    Proj1 := 1.0;
    Proj2 := 0.0;
    LatLen := 1.0;
  end;

  Ang1Deg := RadToDeg(TotalAngleRad) * (Proj1 / LatLen);
  Ang2Deg := RadToDeg(TotalAngleRad) * (Proj2 / LatLen);
  NormEll := Sqrt(Sqr(Ang1Deg / Lim1) + Sqr(Ang2Deg / Lim2));

  if NormEll <= 1.0 then
    Exit(D);

  { Project radially onto the Swing1/Swing2 cone boundary! }
  Ang1Deg := Ang1Deg / NormEll;
  Ang2Deg := Ang2Deg / NormEll;
  ClampedAngleRad := DegToRad(Sqrt(Ang1Deg * Ang1Deg + Ang2Deg * Ang2Deg));
  Result := (AxisR * Cos(ClampedAngleRad) +
    (Axis1 * (Proj1 / LatLen) + Axis2 * (Proj2 / LatLen)) * Sin(ClampedAngleRad)).Normalize;
end;

class function TCastlePhysicsAsset.ComputeEllipticalSwingViolationDeg(
  const ADir, ARestDir: TVector3;
  const ASwing1Deg, ASwing2Deg: Single): Single;
var
  Clamped: TVector3;
  DotVal: Single;
begin
  if ADir.LengthSqr < 1e-8 then Exit(0.0);
  Clamped := ClampDirectionToEllipticalSwingCone(ADir, ARestDir, ASwing1Deg, ASwing2Deg);
  DotVal := EnsureRange(TVector3.DotProduct(ADir.Normalize, Clamped), -1.0, 1.0);
  Result := RadToDeg(ArcCos(DotVal));
end;

{ TCastlePhysicsAsset -------------------------------------------------------- }

constructor TCastlePhysicsAsset.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGravityY := -9.81;
  FLinearDamping := 0.85;
  FFloorRestitution := 0.22;
  FSolverIterations := 8;
  FShowColliderWirePreview := True;
  ApplyPreset(papHumanoidRagdoll11Bodies);
end;

destructor TCastlePhysicsAsset.Destroy;
begin
  ClearPreviewContainer;
  inherited;
end;

procedure TCastlePhysicsAsset.Loaded;
begin
  inherited;
  SyncPreviewColliders;
end;

function TCastlePhysicsAsset.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'GravityY') or
     (PropertyName = 'LinearDamping') or
     (PropertyName = 'SolverIterations') or
     (PropertyName = 'ShowColliderWirePreview') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastlePhysicsAsset.SetPreset(const AValue: TPhAtAssetPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastlePhysicsAsset.SetShowColliderWirePreview(const AValue: Boolean);
begin
  if FShowColliderWirePreview <> AValue then
  begin
    FShowColliderWirePreview := AValue;
    if not FShowColliderWirePreview then
      ClearPreviewContainer
    else
      SyncPreviewColliders;
  end;
end;

procedure TCastlePhysicsAsset.ClearPreviewContainer;
begin
  if FPreviewContainer <> nil then
    FreeAndNil(FPreviewContainer);
end;

procedure TCastlePhysicsAsset.SyncPreviewColliders;
var
  I: Integer;
  B: TCastleBox;
  Ext: TVector3;
begin
  ClearPreviewContainer;
  if (not FShowColliderWirePreview) or (Length(FBodies) = 0) then Exit;

  FPreviewContainer := TCastleTransform.Create(nil);
  FPreviewContainer.SetTransient;
  FPreviewContainer.Pickable := False;
  FPreviewContainer.Collides := False;
  FPreviewContainer.Name := 'PhAT_ColliderPreview';
  Add(FPreviewContainer);

  for I := 0 to High(FBodies) do
  begin
    B := TCastleBox.Create(FPreviewContainer);
    B.SetTransient;
    B.Pickable := False;
    B.Collides := False;
    case FBodies[I].ShapeKind of
      pskSphere:
        Ext := Vector3(FBodies[I].Radius * 2.0, FBodies[I].Radius * 2.0, FBodies[I].Radius * 2.0);
      pskCapsule:
        Ext := Vector3(FBodies[I].Radius * 2.0, FBodies[I].LengthMeters + FBodies[I].Radius * 2.0, FBodies[I].Radius * 2.0);
      pskBox:
        Ext := FBodies[I].BoxExtents;
    end;
    B.Size := Ext;
    B.Translation := FBodies[I].Position;
    if FBodies[I].PhysicsType = pptKinematic then
      B.Color := Vector4(1.00, 0.52, 0.22, 0.85)
    else
      B.Color := Vector4(0.32, 0.86, 0.98, 0.85);
    FPreviewContainer.Add(B);
  end;
end;

procedure TCastlePhysicsAsset.ClearAsset;
begin
  FBodies := nil;
  FConstraints := nil;
  FDisabledPairs := nil;
  FSimTimeSec := 0.0;
  FPokeImpulseCount := 0;
  FNonAdjacentBodyContacts := 0;
  ClearPreviewContainer;
end;

function TCastlePhysicsAsset.FindBodyIndex(const ABodyName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FBodies) do
    if SameText(FBodies[I].BodyName, ABodyName) then
      Exit(I);
  Result := -1;
end;

function TCastlePhysicsAsset.AddBody(const AName: String;
  const AShape: TPhAtShapeKind; const APhysType: TPhAtPhysicsType;
  const ARestPos: TVector3; const ARadius, ALength: Single;
  const ABoxExtents: TVector3; const ADensityKgPerM3: Single): Integer;
var
  B: TPhAtBodySetup;
begin
  Result := Length(FBodies);
  SetLength(FBodies, Result + 1);
  B := Default(TPhAtBodySetup);
  B.BodyName := AName;
  B.ShapeKind := AShape;
  B.PhysicsType := APhysType;
  B.Radius := Max(0.02, ARadius);
  B.LengthMeters := Max(0.0, ALength);
  B.BoxExtents := ABoxExtents;
  B.DensityKgPerM3 := Max(10.0, ADensityKgPerM3);
  B.MassKg := ComputeBodyMassKg(AShape, B.Radius, B.LengthMeters, ABoxExtents, B.DensityKgPerM3);
  B.RestPos := ARestPos;
  B.Position := ARestPos;
  B.PrevPosition := ARestPos;
  B.Velocity := TVector3.Zero;
  FBodies[Result] := B;
end;

procedure TCastlePhysicsAsset.SetBodyPhysicsType(const ABodyName: String;
  const APhysType: TPhAtPhysicsType);
var
  Idx: Integer;
begin
  Idx := FindBodyIndex(ABodyName);
  if Idx >= 0 then
  begin
    FBodies[Idx].PhysicsType := APhysType;
    if APhysType = pptKinematic then
      FBodies[Idx].Velocity := TVector3.Zero;
    SyncPreviewColliders;
  end;
end;

function TCastlePhysicsAsset.AddConstraint(const AParentBody, AChildBody: String;
  const ASwing1Deg, ASwing2Deg, ATwistDeg: Single): Integer;
var
  PIdx, CIdx: Integer;
  Delta: TVector3;
  C: TPhAtJointConstraint;
begin
  PIdx := FindBodyIndex(AParentBody);
  CIdx := FindBodyIndex(AChildBody);
  if (PIdx < 0) or (CIdx < 0) or (PIdx = CIdx) then Exit(-1);

  Delta := FBodies[CIdx].RestPos - FBodies[PIdx].RestPos;
  Result := Length(FConstraints);
  SetLength(FConstraints, Result + 1);
  C := Default(TPhAtJointConstraint);
  C.ConstraintName := AParentBody + '->' + AChildBody;
  C.ParentBodyIndex := PIdx;
  C.ChildBodyIndex := CIdx;
  C.RestLength := Max(0.02, Delta.Length);
  if Delta.LengthSqr > 1e-6 then
    C.RestDir := Delta.Normalize
  else
    C.RestDir := Vector3(0, -1, 0);
  C.Swing1LimitDeg := EnsureRange(ASwing1Deg, 2.0, 170.0);
  C.Swing2LimitDeg := EnsureRange(ASwing2Deg, 2.0, 170.0);
  C.TwistLimitDeg  := EnsureRange(ATwistDeg,  0.0, 170.0);
  C.DisableParentChildCollision := True;
  FConstraints[Result] := C;

  SetPairCollisionEnabled(PIdx, CIdx, False);
end;

procedure TCastlePhysicsAsset.SetConstraintLimits(const AConstraintIdx: Integer;
  const ASwing1Deg, ASwing2Deg, ATwistDeg: Single);
begin
  if (AConstraintIdx < 0) or (AConstraintIdx > High(FConstraints)) then Exit;
  FConstraints[AConstraintIdx].Swing1LimitDeg := EnsureRange(ASwing1Deg, 2.0, 170.0);
  FConstraints[AConstraintIdx].Swing2LimitDeg := EnsureRange(ASwing2Deg, 2.0, 170.0);
  FConstraints[AConstraintIdx].TwistLimitDeg  := EnsureRange(ATwistDeg,  0.0, 170.0);
end;

function TCastlePhysicsAsset.IsPairCollisionEnabled(const AIdxA, AIdxB: Integer): Boolean;
var
  Lo, Hi, I: Integer;
begin
  if AIdxA = AIdxB then Exit(False);
  Lo := Min(AIdxA, AIdxB);
  Hi := Max(AIdxA, AIdxB);
  for I := 0 to High(FDisabledPairs) do
    if (FDisabledPairs[I].BodyIndexA = Lo) and (FDisabledPairs[I].BodyIndexB = Hi) then
      Exit(False);
  Result := True;
end;

procedure TCastlePhysicsAsset.SetPairCollisionEnabled(
  const AIdxA, AIdxB: Integer; const AEnabled: Boolean);
var
  Lo, Hi, I, N: Integer;
begin
  if AIdxA = AIdxB then Exit;
  Lo := Min(AIdxA, AIdxB);
  Hi := Max(AIdxA, AIdxB);

  for I := 0 to High(FDisabledPairs) do
    if (FDisabledPairs[I].BodyIndexA = Lo) and (FDisabledPairs[I].BodyIndexB = Hi) then
    begin
      if AEnabled then
      begin
        FDisabledPairs[I] := FDisabledPairs[High(FDisabledPairs)];
        SetLength(FDisabledPairs, Length(FDisabledPairs) - 1);
      end;
      Exit;
    end;

  if not AEnabled then
  begin
    N := Length(FDisabledPairs);
    SetLength(FDisabledPairs, N + 1);
    FDisabledPairs[N].BodyIndexA := Lo;
    FDisabledPairs[N].BodyIndexB := Hi;
  end;
end;

procedure TCastlePhysicsAsset.DisableAllAdjacentBoneCollisions;
var
  I: Integer;
begin
  for I := 0 to High(FConstraints) do
    SetPairCollisionEnabled(
      FConstraints[I].ParentBodyIndex, FConstraints[I].ChildBodyIndex, False);
end;

procedure TCastlePhysicsAsset.ResetToRestPose;
var
  I: Integer;
begin
  for I := 0 to High(FBodies) do
  begin
    FBodies[I].Position := FBodies[I].RestPos;
    FBodies[I].PrevPosition := FBodies[I].RestPos;
    FBodies[I].Velocity := TVector3.Zero;
    FBodies[I].TwistAngleDeg := 0.0;
  end;
  FSimTimeSec := 0.0;
  FNonAdjacentBodyContacts := 0;
  SyncPreviewColliders;
end;

function TCastlePhysicsAsset.ApplyPokeImpulse(const ABodyName: String;
  const AImpulseNs: TVector3): Boolean;
var
  Idx: Integer;
begin
  Idx := FindBodyIndex(ABodyName);
  if (Idx < 0) or (FBodies[Idx].PhysicsType = pptKinematic) then
    Exit(False);
  FBodies[Idx].Velocity := FBodies[Idx].Velocity +
    AImpulseNs * (1.0 / Max(0.05, FBodies[Idx].MassKg));
  Inc(FPokeImpulseCount);
  Result := True;
end;

procedure TCastlePhysicsAsset.StepSimulation(const ADeltaSeconds: Single);
var
  Dt, DampingFactor, InvMassP, InvMassC, InvMassSum, Dist, Diff, MinSep, Pen,
    MinFloorOverhang: Single;
  I, J, Iter, PIdx, CIdx: Integer;
  HasKinematicBody: Boolean;
  Delta, ClampedDir, TargetChildPos, Corr, SepDir: TVector3;
begin
  Dt := EnsureRange(ADeltaSeconds, 0.0, 0.05);
  if (Dt <= 0.0) or (Length(FBodies) = 0) then Exit;

  FSimTimeSec := FSimTimeSec + Dt;
  DampingFactor := Max(0.0, 1.0 - FLinearDamping * Dt);

  { 1. Symplectic / PBD Predict Positions }
  for I := 0 to High(FBodies) do
  begin
    FBodies[I].PrevPosition := FBodies[I].Position;
    if FBodies[I].PhysicsType = pptSimulated then
    begin
      FBodies[I].Velocity.Y := FBodies[I].Velocity.Y + FGravityY * Dt;
      FBodies[I].Velocity := FBodies[I].Velocity * DampingFactor;
      FBodies[I].Position := FBodies[I].Position + FBodies[I].Velocity * Dt;
    end;
  end;

  { 2. Iterative Constraint Distance, Elliptical Swing1/Swing2 Cone, Collision & Floor Solver }
  for Iter := 1 to Max(2, FSolverIterations) do
  begin
    { 2a. Non-adjacent enabled body-pair collision separation }
    for I := 0 to High(FBodies) do
      for J := I + 1 to High(FBodies) do
        if IsPairCollisionEnabled(I, J) then
        begin
          Delta := FBodies[J].Position - FBodies[I].Position;
          Dist := Delta.Length;
          MinSep := FBodies[I].Radius + FBodies[J].Radius;
          if Dist < MinSep then
          begin
            if Iter = 1 then Inc(FNonAdjacentBodyContacts);
            if Dist > 1e-5 then
              SepDir := Delta / Dist
            else
              SepDir := Vector3(1, 0, 0);
            Pen := MinSep - Dist;
            if FBodies[I].PhysicsType = pptSimulated then InvMassP := 1.0 / FBodies[I].MassKg else InvMassP := 0.0;
            if FBodies[J].PhysicsType = pptSimulated then InvMassC := 1.0 / FBodies[J].MassKg else InvMassC := 0.0;
            InvMassSum := InvMassP + InvMassC;
            if InvMassSum > 1e-6 then
            begin
              FBodies[I].Position := FBodies[I].Position - SepDir * (Pen * (InvMassP / InvMassSum));
              FBodies[J].Position := FBodies[J].Position + SepDir * (Pen * (InvMassC / InvMassSum));
            end;
          end;
        end;

    { 2b. Ground floor Y >= Radius clamping }
    for I := 0 to High(FBodies) do
      if (FBodies[I].PhysicsType = pptSimulated) and
         (FBodies[I].Position.Y < FBodies[I].Radius) then
        FBodies[I].Position.Y := FBodies[I].Radius;

    { 2c. Parent -> Child rod length + Elliptical Swing1/Swing2 cone projection }
    for I := 0 to High(FConstraints) do
    begin
      PIdx := FConstraints[I].ParentBodyIndex;
      CIdx := FConstraints[I].ChildBodyIndex;
      if FBodies[PIdx].PhysicsType = pptSimulated then InvMassP := 1.0 / FBodies[PIdx].MassKg else InvMassP := 0.0;
      if FBodies[CIdx].PhysicsType = pptSimulated then InvMassC := 1.0 / FBodies[CIdx].MassKg else InvMassC := 0.0;
      InvMassSum := InvMassP + InvMassC;
      if InvMassSum < 1e-6 then Continue;

      Delta := FBodies[CIdx].Position - FBodies[PIdx].Position;
      Dist := Delta.Length;
      if Dist < 1e-5 then
      begin
        Delta := FConstraints[I].RestDir * FConstraints[I].RestLength;
        Dist := FConstraints[I].RestLength;
      end;

      { Distance projection }
      Diff := (Dist - FConstraints[I].RestLength) / Dist;
      Corr := Delta * Diff;
      FBodies[PIdx].Position := FBodies[PIdx].Position + Corr * (InvMassP / InvMassSum);
      FBodies[CIdx].Position := FBodies[CIdx].Position - Corr * (InvMassC / InvMassSum);

      { Swing1 / Swing2 angular cone clamp }
      Delta := FBodies[CIdx].Position - FBodies[PIdx].Position;
      ClampedDir := ClampDirectionToEllipticalSwingCone(
        Delta, FConstraints[I].RestDir,
        FConstraints[I].Swing1LimitDeg, FConstraints[I].Swing2LimitDeg);
      TargetChildPos := FBodies[PIdx].Position + ClampedDir * FConstraints[I].RestLength;
      Corr := TargetChildPos - FBodies[CIdx].Position;
      FBodies[CIdx].Position := FBodies[CIdx].Position + Corr * (InvMassC / InvMassSum);
      FBodies[PIdx].Position := FBodies[PIdx].Position - Corr * (InvMassP / InvMassSum);

      FBodies[CIdx].TwistAngleDeg := EnsureRange(
        FBodies[CIdx].TwistAngleDeg,
        -FConstraints[I].TwistLimitDeg, FConstraints[I].TwistLimitDeg);
    end;
  end;

  { 3. Final exact hierarchical cone pass (guarantees 0.0 deg cone violation & exact RestLength) }
  for I := 0 to High(FConstraints) do
  begin
    PIdx := FConstraints[I].ParentBodyIndex;
    CIdx := FConstraints[I].ChildBodyIndex;
    if FBodies[CIdx].PhysicsType = pptSimulated then
    begin
      Delta := FBodies[CIdx].Position - FBodies[PIdx].Position;
      ClampedDir := ClampDirectionToEllipticalSwingCone(
        Delta, FConstraints[I].RestDir,
        FConstraints[I].Swing1LimitDeg, FConstraints[I].Swing2LimitDeg);
      FBodies[CIdx].Position := FBodies[PIdx].Position + ClampedDir * FConstraints[I].RestLength;
    end;
  end;

  { 3b. Translation-invariant floor lift for unpinned ragdolls (preserves exact Child-Parent vectors!) }
  HasKinematicBody := False;
  MinFloorOverhang := 0.0;
  for I := 0 to High(FBodies) do
    if FBodies[I].PhysicsType = pptKinematic then
      HasKinematicBody := True
    else
      MinFloorOverhang := Min(MinFloorOverhang, FBodies[I].Position.Y - FBodies[I].Radius);

  if (not HasKinematicBody) and (MinFloorOverhang < 0.0) then
    for I := 0 to High(FBodies) do
      FBodies[I].Position.Y := FBodies[I].Position.Y - MinFloorOverhang;

  { 4. Derive post-solve PBD velocities + floor restitution }
  for I := 0 to High(FBodies) do
    if FBodies[I].PhysicsType = pptSimulated then
    begin
      FBodies[I].Velocity := (FBodies[I].Position - FBodies[I].PrevPosition) * (1.0 / Dt);
      if (FBodies[I].Position.Y <= FBodies[I].Radius + 1e-4) and (FBodies[I].Velocity.Y < 0.0) then
        FBodies[I].Velocity.Y := -FBodies[I].Velocity.Y * EnsureRange(FFloorRestitution, 0.0, 1.0);
    end;

  SyncPreviewColliders;
end;

function TCastlePhysicsAsset.TotalMassKg: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FBodies) do
    Result := Result + FBodies[I].MassKg;
end;

function TCastlePhysicsAsset.DisabledPairCount: Integer;
begin
  Result := Length(FDisabledPairs);
end;

function TCastlePhysicsAsset.MaxConstraintStretchErrorMeters: Single;
var
  I: Integer;
  Len: Single;
begin
  Result := 0.0;
  for I := 0 to High(FConstraints) do
  begin
    Len := (FBodies[FConstraints[I].ChildBodyIndex].Position -
            FBodies[FConstraints[I].ParentBodyIndex].Position).Length;
    Result := Max(Result, Abs(Len - FConstraints[I].RestLength));
  end;
end;

function TCastlePhysicsAsset.MaxConstraintConeViolationDeg: Single;
var
  I: Integer;
  Delta: TVector3;
begin
  Result := 0.0;
  for I := 0 to High(FConstraints) do
  begin
    Delta := FBodies[FConstraints[I].ChildBodyIndex].Position -
             FBodies[FConstraints[I].ParentBodyIndex].Position;
    Result := Max(Result, ComputeEllipticalSwingViolationDeg(
      Delta, FConstraints[I].RestDir,
      FConstraints[I].Swing1LimitDeg, FConstraints[I].Swing2LimitDeg));
  end;
end;

{ Built-In UE 5.5 PhAT Presets ----------------------------------------------- }

procedure TCastlePhysicsAsset.ApplyPreset(const APreset: TPhAtAssetPreset);
var
  Dens, RadScale, ConeScale: Single;
  RootPhys: TPhAtPhysicsType;
begin
  FPreset := APreset;
  if APreset = papCustom then Exit;

  ClearAsset;
  FPreset := APreset;

  Dens := 1020.0;
  RadScale := 1.0;
  ConeScale := 1.0;
  RootPhys := pptSimulated;

  if APreset = papKinematicPinnedUpperBodyTest then
    RootPhys := pptKinematic
  else if APreset = papHeavyArmoredBruteRagdoll then
  begin
    Dens := 1850.0;
    RadScale := 1.25;
    ConeScale := 0.55;
  end;

  { 11 Articulated Ragdoll Bodies }
  AddBody('Pelvis',     pskBox,     RootPhys,     Vector3( 0.00, 1.02, 0.0), 0.14 * RadScale, 0.0,  Vector3(0.32, 0.18, 0.22) * RadScale, Dens);
  AddBody('SpineTorso', pskCapsule, RootPhys,     Vector3( 0.00, 1.38, 0.0), 0.15 * RadScale, 0.30, Vector3(0.30, 0.36, 0.22), Dens);
  AddBody('Head',       pskSphere,  pptSimulated, Vector3( 0.00, 1.72, 0.0), 0.12 * RadScale, 0.0,  Vector3(0.24, 0.24, 0.24), Dens);

  AddBody('UpperArm_L', pskCapsule, pptSimulated, Vector3(-0.30, 1.42, 0.0), 0.065 * RadScale, 0.26, Vector3(0.13, 0.26, 0.13), Dens);
  AddBody('LowerArm_L', pskCapsule, pptSimulated, Vector3(-0.56, 1.26, 0.0), 0.055 * RadScale, 0.24, Vector3(0.11, 0.24, 0.11), Dens);
  AddBody('UpperArm_R', pskCapsule, pptSimulated, Vector3( 0.30, 1.42, 0.0), 0.065 * RadScale, 0.26, Vector3(0.13, 0.26, 0.13), Dens);
  AddBody('LowerArm_R', pskCapsule, pptSimulated, Vector3( 0.56, 1.26, 0.0), 0.055 * RadScale, 0.24, Vector3(0.11, 0.24, 0.11), Dens);

  AddBody('Thigh_L',    pskCapsule, pptSimulated, Vector3(-0.13, 0.64, 0.0), 0.090 * RadScale, 0.36, Vector3(0.18, 0.36, 0.18), Dens);
  AddBody('Calf_L',     pskCapsule, pptSimulated, Vector3(-0.13, 0.24, 0.0), 0.070 * RadScale, 0.34, Vector3(0.14, 0.34, 0.14), Dens);
  AddBody('Thigh_R',    pskCapsule, pptSimulated, Vector3( 0.13, 0.64, 0.0), 0.090 * RadScale, 0.36, Vector3(0.18, 0.36, 0.18), Dens);
  AddBody('Calf_R',     pskCapsule, pptSimulated, Vector3( 0.13, 0.24, 0.0), 0.070 * RadScale, 0.34, Vector3(0.14, 0.34, 0.14), Dens);

  { 10 Anatomical Swing1 / Swing2 / Twist Constraints }
  AddConstraint('Pelvis',     'SpineTorso', 32.0 * ConeScale, 28.0 * ConeScale, 25.0);
  AddConstraint('SpineTorso', 'Head',       35.0 * ConeScale, 30.0 * ConeScale, 40.0);
  AddConstraint('SpineTorso', 'UpperArm_L', 75.0 * ConeScale, 65.0 * ConeScale, 45.0);
  AddConstraint('UpperArm_L', 'LowerArm_L', 65.0 * ConeScale, 15.0 * ConeScale, 20.0);
  AddConstraint('SpineTorso', 'UpperArm_R', 75.0 * ConeScale, 65.0 * ConeScale, 45.0);
  AddConstraint('UpperArm_R', 'LowerArm_R', 65.0 * ConeScale, 15.0 * ConeScale, 20.0);
  AddConstraint('Pelvis',     'Thigh_L',    55.0 * ConeScale, 40.0 * ConeScale, 25.0);
  AddConstraint('Thigh_L',    'Calf_L',     60.0 * ConeScale, 12.0 * ConeScale, 15.0);
  AddConstraint('Pelvis',     'Thigh_R',    55.0 * ConeScale, 40.0 * ConeScale, 25.0);
  AddConstraint('Thigh_R',    'Calf_R',     60.0 * ConeScale, 12.0 * ConeScale, 15.0);

  ResetToRestPose;
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastlePhysicsAsset.GetPhysicsAssetJson: String;
var
  Root, BObj, CObj, PObj: TJSONObject;
  BArr, CArr, PArr, VecArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    BArr := TJSONArray.Create;
    for I := 0 to High(FBodies) do
    begin
      BObj := TJSONObject.Create;
      BObj.Add('name', FBodies[I].BodyName);
      BObj.Add('shape', Ord(FBodies[I].ShapeKind));
      BObj.Add('phys', Ord(FBodies[I].PhysicsType));
      BObj.Add('r', FBodies[I].Radius);
      BObj.Add('len', FBodies[I].LengthMeters);
      BObj.Add('dens', FBodies[I].DensityKgPerM3);
      VecArr := TJSONArray.Create;
      VecArr.Add(FBodies[I].BoxExtents.X);
      VecArr.Add(FBodies[I].BoxExtents.Y);
      VecArr.Add(FBodies[I].BoxExtents.Z);
      BObj.Add('ext', VecArr);
      VecArr := TJSONArray.Create;
      VecArr.Add(FBodies[I].RestPos.X);
      VecArr.Add(FBodies[I].RestPos.Y);
      VecArr.Add(FBodies[I].RestPos.Z);
      BObj.Add('rest', VecArr);
      BArr.Add(BObj);
    end;
    Root.Add('bodies', BArr);

    CArr := TJSONArray.Create;
    for I := 0 to High(FConstraints) do
    begin
      CObj := TJSONObject.Create;
      CObj.Add('p', FBodies[FConstraints[I].ParentBodyIndex].BodyName);
      CObj.Add('c', FBodies[FConstraints[I].ChildBodyIndex].BodyName);
      CObj.Add('s1', FConstraints[I].Swing1LimitDeg);
      CObj.Add('s2', FConstraints[I].Swing2LimitDeg);
      CObj.Add('tw', FConstraints[I].TwistLimitDeg);
      CArr.Add(CObj);
    end;
    Root.Add('constraints', CArr);

    PArr := TJSONArray.Create;
    for I := 0 to High(FDisabledPairs) do
    begin
      PObj := TJSONObject.Create;
      PObj.Add('a', FDisabledPairs[I].BodyIndexA);
      PObj.Add('b', FDisabledPairs[I].BodyIndexB);
      PArr.Add(PObj);
    end;
    Root.Add('disabledPairs', PArr);

    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastlePhysicsAsset.SetPhysicsAssetJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, BObj, CObj, PObj: TJSONObject;
  BArr, CArr, PArr, VecArr: TJSONArray;
  I: Integer;
  Ext, RestP: TVector3;
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
    ClearAsset;
    FPreset := papCustom;

    BArr := Root.Find('bodies', jtArray) as TJSONArray;
    if BArr <> nil then
      for I := 0 to BArr.Count - 1 do
        if BArr.Items[I] is TJSONObject then
        begin
          BObj := TJSONObject(BArr.Items[I]);
          Ext := Vector3(0.2, 0.2, 0.2);
          VecArr := BObj.Find('ext', jtArray) as TJSONArray;
          if (VecArr <> nil) and (VecArr.Count >= 3) then
            Ext := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);
          RestP := TVector3.Zero;
          VecArr := BObj.Find('rest', jtArray) as TJSONArray;
          if (VecArr <> nil) and (VecArr.Count >= 3) then
            RestP := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);
          AddBody(
            BObj.Get('name', 'Body_' + IntToStr(I)),
            TPhAtShapeKind(EnsureRange(BObj.Get('shape', 1), 0, Ord(High(TPhAtShapeKind)))),
            TPhAtPhysicsType(EnsureRange(BObj.Get('phys', 0), 0, Ord(High(TPhAtPhysicsType)))),
            RestP, BObj.Get('r', 0.08), BObj.Get('len', 0.25), Ext, BObj.Get('dens', 1020.0));
        end;

    CArr := Root.Find('constraints', jtArray) as TJSONArray;
    if CArr <> nil then
      for I := 0 to CArr.Count - 1 do
        if CArr.Items[I] is TJSONObject then
        begin
          CObj := TJSONObject(CArr.Items[I]);
          AddConstraint(
            CObj.Get('p', ''), CObj.Get('c', ''),
            CObj.Get('s1', 45.0), CObj.Get('s2', 45.0), CObj.Get('tw', 25.0));
        end;

    FDisabledPairs := nil;
    PArr := Root.Find('disabledPairs', jtArray) as TJSONArray;
    if PArr <> nil then
      for I := 0 to PArr.Count - 1 do
        if PArr.Items[I] is TJSONObject then
        begin
          PObj := TJSONObject(PArr.Items[I]);
          SetPairCollisionEnabled(PObj.Get('a', 0), PObj.Get('b', 0), False);
        end;

    ResetToRestPose;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastlePhysicsAsset.PhAtSummaryBadge: String;
begin
  Result := Format('[PhAT:Bodies=%d Joints=%d Mass=%.1fkg ConeErr=%.2fdeg]',
    [Length(FBodies), Length(FConstraints), TotalMassKg, MaxConstraintConeViolationDeg]);
end;

initialization
  RegisterSerializableComponent(TCastlePhysicsAsset, 'Physics Asset (PhAT Ragdoll)');
end.
