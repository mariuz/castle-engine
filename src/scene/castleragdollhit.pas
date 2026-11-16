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

{ Physical Animation Localized Hit-Reaction Impulse Propagation, Proportional-
  Derivative (PD) Pose Motor Springs, PBD Articulated Ragdoll Collapse &
  Smooth Get-Up Pose Recovery Runtime (@link(TCastlePhysicalHitRagdollBehavior))
  (Phase 331 — UE 6.0+ Chaos Physical Animation & Ragdoll Parity). }
unit CastleRagdollHit;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleScene;

type
  { 11-bone humanoid articulated physical animation hierarchy. }
  TRagdollBoneId = (
    rbiPelvis,
    rbiSpineChest,
    rbiHead,
    rbiUpperArmL,
    rbiForearmL,
    rbiUpperArmR,
    rbiForearmR,
    rbiThighL,
    rbiShinL,
    rbiThighR,
    rbiShinR
  );

  { Built-in Physical Animation stiffness & knockdown presets. }
  TPhysicalAnimPreset = (
    papCustom,
    papStiffArmoredKnight,
    papAgileFighterBalanced,
    papLooseZombieStagger
  );

  { Runtime mode of @link(TCastlePhysicalHitRagdollBehavior). }
  TPhysicalRagdollMode = (
    prmActivePhysicalHitReact,
    prmFullLimpRagdoll,
    prmGetUpBlendRecovery
  );

  { Live kinematic state of a single articulated bone node (parent-local meters). }
  TRagdollBoneState = record
    BoneId: TRagdollBoneId;
    ParentIndex: Integer; // -1 for Pelvis
    RestLocalPos: TVector3;
    RestLengthToParent: Single;
    CurLocalPos: TVector3;
    PrevLocalPos: TVector3;
    VelLocal: TVector3;
    FrozenRagdollPos: TVector3;
    InvMass: Single;
    BoneRadius: Single;
  end;

  { Physical animation hit-reaction & articulated PBD ragdoll behavior
    (@link(TCastleBehavior)) supporting localized limb impulses, multi-hop
    topological attenuation, critically-damped PD pose springs, full knockdown
    ragdoll collapse with floor collision, and Hermite stand-up recovery. }
  TCastlePhysicalHitRagdollBehavior = class(TCastleBehavior)
  public
    const
      DefaultSpringStiffnessKp = 130.0;
      DefaultDampingRatio = 1.0;
      DefaultImpulsePropagation = 0.48;
      DefaultKnockdownThreshold = 28.0;
      DefaultFloorLocalY = 0.0;
  strict private
    FPreset: TPhysicalAnimPreset;
    FMode: TPhysicalRagdollMode;
    FSpringStiffnessKp: Single;
    FDampingRatio: Single;
    FImpulsePropagation: Single;
    FKnockdownThreshold: Single;
    FFloorLocalY: Single;
    FBuildVisualRig: Boolean;
    FSimulateInEditor: Boolean;

    FBones: array [TRagdollBoneId] of TRagdollBoneState;
    FGetUpElapsedSec: Single;
    FGetUpDurationSec: Single;
    FLastHitBone: TRagdollBoneId;
    FLastHitMagnitude: Single;
    FTotalHitsReceived: Integer;

    FVisualRoot: TCastleTransform;
    FBoneBoxes: array [TRagdollBoneId] of TCastleBox;

    procedure SetPreset(const Value: TPhysicalAnimPreset);
    procedure SetBuildVisualRig(const Value: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    procedure InitHumanoidRestPose;
    function HopDistanceBetweenBones(const A, B: TRagdollBoneId): Integer;
    procedure SolveDistanceAndFloorConstraints(const EnforceRestLengths: Boolean);
    procedure RebuildOrSyncVisualRig;
  protected
    procedure ParentAfterAttach; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TPhysicalAnimPreset): String; static;
    class function BoneDisplayName(const ABone: TRagdollBoneId): String; static;
    class function ModeDisplayName(const AMode: TPhysicalRagdollMode): String; static;

    procedure ApplyPreset(const APreset: TPhysicalAnimPreset);
    procedure ResetToStandingPose;

    { Apply a directional impulse @code(ImpulseLocal) (in N*s / velocity units)
      to @code(TargetBone), propagating attenuated impulses across connected
      joints and triggering @code(prmFullLimpRagdoll) if @code(||Impulse|| >= KnockdownThreshold). }
    procedure ApplyHitImpulseAtBone(const TargetBone: TRagdollBoneId;
      const ImpulseLocal: TVector3);

    { Find the bone closest to @code(HitPointLocal) and apply @code(ImpulseLocal). }
    function ApplyPointHitImpulse(const HitPointLocal, ImpulseLocal: TVector3): TRagdollBoneId;

    procedure TriggerFullRagdoll(const InitialPelvisVel: TVector3);
    procedure BeginGetUpRecovery(const ADurationSec: Single = 0.75);

    procedure StepPhysicalAnimation(const TotalDt: Single);

    function GetBoneState(const ABone: TRagdollBoneId): TRagdollBoneState;
    function MaxPoseDeviationMeters: Single;
    function RagdollSummaryBadge: String;

    property Mode: TPhysicalRagdollMode read FMode;
    property LastHitBone: TRagdollBoneId read FLastHitBone;
    property LastHitMagnitude: Single read FLastHitMagnitude;
    property TotalHitsReceived: Integer read FTotalHitsReceived;
  published
    property Preset: TPhysicalAnimPreset
      read FPreset write SetPreset default papAgileFighterBalanced;
    property SpringStiffnessKp: Single
      read FSpringStiffnessKp write FSpringStiffnessKp {$ifdef FPC}default DefaultSpringStiffnessKp{$endif};
    property DampingRatio: Single
      read FDampingRatio write FDampingRatio {$ifdef FPC}default DefaultDampingRatio{$endif};
    property ImpulsePropagation: Single
      read FImpulsePropagation write FImpulsePropagation {$ifdef FPC}default DefaultImpulsePropagation{$endif};
    property KnockdownThreshold: Single
      read FKnockdownThreshold write FKnockdownThreshold {$ifdef FPC}default DefaultKnockdownThreshold{$endif};
    property FloorLocalY: Single
      read FFloorLocalY write FFloorLocalY {$ifdef FPC}default DefaultFloorLocalY{$endif};
    property BuildVisualRig: Boolean
      read FBuildVisualRig write SetBuildVisualRig default True;
    property SimulateInEditor: Boolean
      read FSimulateInEditor write FSimulateInEditor default False;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

implementation

uses
  Math, FpJson, JsonParser,
  CastleUtils, CastleColors, CastleComponentSerialize;

function SmoothStep01(const T: Single): Single; inline;
var
  U: Single;
begin
  U := Clamped(T, 0.0, 1.0);
  Result := U * U * (3.0 - 2.0 * U);
end;

{ TCastlePhysicalHitRagdollBehavior ------------------------------------------ }

constructor TCastlePhysicalHitRagdollBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSpringStiffnessKp := DefaultSpringStiffnessKp;
  FDampingRatio := DefaultDampingRatio;
  FImpulsePropagation := DefaultImpulsePropagation;
  FKnockdownThreshold := DefaultKnockdownThreshold;
  FFloorLocalY := DefaultFloorLocalY;
  FBuildVisualRig := True;
  FSimulateInEditor := False;

  InitHumanoidRestPose;
  ApplyPreset(papAgileFighterBalanced);
end;

procedure TCastlePhysicalHitRagdollBehavior.ParentAfterAttach;
begin
  inherited;
  if FBuildVisualRig then
    RebuildOrSyncVisualRig;
end;

function TCastlePhysicalHitRagdollBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'SpringStiffnessKp', 'DampingRatio', 'ImpulsePropagation',
       'KnockdownThreshold', 'FloorLocalY', 'BuildVisualRig',
       'SimulateInEditor', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastlePhysicalHitRagdollBehavior.PresetDisplayName(
  const APreset: TPhysicalAnimPreset): String;
begin
  case APreset of
    papCustom:               Result := 'Custom Physical Rig';
    papStiffArmoredKnight:   Result := 'Stiff Armored Knight';
    papAgileFighterBalanced: Result := 'Agile Fighter (Balanced)';
    papLooseZombieStagger:   Result := 'Loose Zombie Stagger';
  end;
end;

class function TCastlePhysicalHitRagdollBehavior.BoneDisplayName(
  const ABone: TRagdollBoneId): String;
begin
  case ABone of
    rbiPelvis:     Result := 'Pelvis';
    rbiSpineChest: Result := 'SpineChest';
    rbiHead:       Result := 'Head';
    rbiUpperArmL:  Result := 'UpperArm_L';
    rbiForearmL:   Result := 'Forearm_L';
    rbiUpperArmR:  Result := 'UpperArm_R';
    rbiForearmR:   Result := 'Forearm_R';
    rbiThighL:     Result := 'Thigh_L';
    rbiShinL:      Result := 'Shin_L';
    rbiThighR:     Result := 'Thigh_R';
    rbiShinR:      Result := 'Shin_R';
  end;
end;

class function TCastlePhysicalHitRagdollBehavior.ModeDisplayName(
  const AMode: TPhysicalRagdollMode): String;
begin
  case AMode of
    prmActivePhysicalHitReact: Result := 'ActivePDHitReact';
    prmFullLimpRagdoll:        Result := 'FullRagdoll';
    prmGetUpBlendRecovery:     Result := 'GetUpRecovery';
  end;
end;

procedure TCastlePhysicalHitRagdollBehavior.InitHumanoidRestPose;

  procedure DefBone(const B: TRagdollBoneId; const AParentIdx: Integer;
    const ARestPos: TVector3; const AInvMass, ARad: Single);
  begin
    FBones[B] := Default(TRagdollBoneState);
    FBones[B].BoneId := B;
    FBones[B].ParentIndex := AParentIdx;
    FBones[B].RestLocalPos := ARestPos;
    FBones[B].CurLocalPos := ARestPos;
    FBones[B].PrevLocalPos := ARestPos;
    FBones[B].VelLocal := TVector3.Zero;
    FBones[B].InvMass := AInvMass;
    FBones[B].BoneRadius := ARad;
    if AParentIdx >= 0 then
      FBones[B].RestLengthToParent := PointsDistance(
        ARestPos, FBones[TRagdollBoneId(AParentIdx)].RestLocalPos)
    else
      FBones[B].RestLengthToParent := 0.0;
  end;

begin
  DefBone(rbiPelvis,     -1,                  Vector3( 0.00, 0.92, 0.00), 0.55, 0.14);
  DefBone(rbiSpineChest, Ord(rbiPelvis),      Vector3( 0.00, 1.34, 0.00), 0.70, 0.15);
  DefBone(rbiHead,       Ord(rbiSpineChest),  Vector3( 0.00, 1.68, 0.00), 1.25, 0.12);
  DefBone(rbiUpperArmL,  Ord(rbiSpineChest),  Vector3(-0.28, 1.32, 0.00), 1.35, 0.08);
  DefBone(rbiForearmL,   Ord(rbiUpperArmL),   Vector3(-0.52, 1.04, 0.04), 1.65, 0.07);
  DefBone(rbiUpperArmR,  Ord(rbiSpineChest),  Vector3( 0.28, 1.32, 0.00), 1.35, 0.08);
  DefBone(rbiForearmR,   Ord(rbiUpperArmR),   Vector3( 0.52, 1.04, 0.04), 1.65, 0.07);
  DefBone(rbiThighL,     Ord(rbiPelvis),      Vector3(-0.14, 0.52, 0.00), 0.90, 0.09);
  DefBone(rbiShinL,      Ord(rbiThighL),      Vector3(-0.14, 0.10, 0.00), 1.15, 0.08);
  DefBone(rbiThighR,     Ord(rbiPelvis),      Vector3( 0.14, 0.52, 0.00), 0.90, 0.09);
  DefBone(rbiShinR,      Ord(rbiThighR),      Vector3( 0.14, 0.10, 0.00), 1.15, 0.08);
  FMode := prmActivePhysicalHitReact;
end;

procedure TCastlePhysicalHitRagdollBehavior.ResetToStandingPose;
var
  B: TRagdollBoneId;
begin
  for B in TRagdollBoneId do
  begin
    FBones[B].CurLocalPos := FBones[B].RestLocalPos;
    FBones[B].PrevLocalPos := FBones[B].RestLocalPos;
    FBones[B].VelLocal := TVector3.Zero;
  end;
  FMode := prmActivePhysicalHitReact;
  FGetUpElapsedSec := 0.0;
  if FBuildVisualRig then
    RebuildOrSyncVisualRig;
end;

procedure TCastlePhysicalHitRagdollBehavior.SetPreset(const Value: TPhysicalAnimPreset);
begin
  if FPreset = Value then Exit;
  ApplyPreset(Value);
end;

procedure TCastlePhysicalHitRagdollBehavior.SetBuildVisualRig(const Value: Boolean);
begin
  if FBuildVisualRig = Value then Exit;
  FBuildVisualRig := Value;
  if not FBuildVisualRig then
    FreeAndNil(FVisualRoot)
  else
    RebuildOrSyncVisualRig;
end;

procedure TCastlePhysicalHitRagdollBehavior.ApplyPreset(
  const APreset: TPhysicalAnimPreset);
begin
  FPreset := APreset;
  case APreset of
    papStiffArmoredKnight:
      begin
        FSpringStiffnessKp := 220.0;
        FDampingRatio := 1.05;
        FImpulsePropagation := 0.35;
        FKnockdownThreshold := 45.0;
      end;
    papAgileFighterBalanced:
      begin
        FSpringStiffnessKp := 130.0;
        FDampingRatio := 1.00;
        FImpulsePropagation := 0.48;
        FKnockdownThreshold := 28.0;
      end;
    papLooseZombieStagger:
      begin
        FSpringStiffnessKp := 52.0;
        FDampingRatio := 0.72;
        FImpulsePropagation := 0.65;
        FKnockdownThreshold := 16.0;
      end;
  else
    Exit;
  end;
end;

function TCastlePhysicalHitRagdollBehavior.HopDistanceBetweenBones(
  const A, B: TRagdollBoneId): Integer;
var
  ChainA, ChainB: array [0..10] of Integer;
  LenA, LenB, Cur, IA, IB: Integer;
begin
  if A = B then Exit(0);
  LenA := 0;
  Cur := Ord(A);
  while Cur >= 0 do
  begin
    ChainA[LenA] := Cur;
    Inc(LenA);
    Cur := FBones[TRagdollBoneId(Cur)].ParentIndex;
  end;

  LenB := 0;
  Cur := Ord(B);
  while Cur >= 0 do
  begin
    ChainB[LenB] := Cur;
    Inc(LenB);
    Cur := FBones[TRagdollBoneId(Cur)].ParentIndex;
  end;

  for IA := 0 to LenA - 1 do
    for IB := 0 to LenB - 1 do
      if ChainA[IA] = ChainB[IB] then
        Exit(IA + IB);
  Result := 4;
end;

procedure TCastlePhysicalHitRagdollBehavior.ApplyHitImpulseAtBone(
  const TargetBone: TRagdollBoneId; const ImpulseLocal: TVector3);
var
  Mag, Atten: Single;
  B: TRagdollBoneId;
  Hops: Integer;
begin
  Mag := ImpulseLocal.Length;
  if Mag <= 1e-5 then Exit;

  FLastHitBone := TargetBone;
  FLastHitMagnitude := Mag;
  Inc(FTotalHitsReceived);

  for B in TRagdollBoneId do
  begin
    Hops := HopDistanceBetweenBones(TargetBone, B);
    Atten := Power(Clamped(FImpulsePropagation, 0.05, 0.95), Hops);
    FBones[B].VelLocal := FBones[B].VelLocal +
      ImpulseLocal * (Atten * FBones[B].InvMass * 0.45);
  end;

  if Mag >= FKnockdownThreshold then
    FMode := prmFullLimpRagdoll;
end;

function TCastlePhysicalHitRagdollBehavior.ApplyPointHitImpulse(
  const HitPointLocal, ImpulseLocal: TVector3): TRagdollBoneId;
var
  B, BestB: TRagdollBoneId;
  BestDistSq, D: Single;
begin
  BestB := rbiSpineChest;
  BestDistSq := 1e30;
  for B in TRagdollBoneId do
  begin
    D := PointsDistanceSqr(HitPointLocal, FBones[B].CurLocalPos);
    if D < BestDistSq then
    begin
      BestDistSq := D;
      BestB := B;
    end;
  end;
  ApplyHitImpulseAtBone(BestB, ImpulseLocal);
  Result := BestB;
end;

procedure TCastlePhysicalHitRagdollBehavior.TriggerFullRagdoll(
  const InitialPelvisVel: TVector3);
var
  B: TRagdollBoneId;
begin
  FMode := prmFullLimpRagdoll;
  for B in TRagdollBoneId do
    FBones[B].VelLocal := FBones[B].VelLocal + InitialPelvisVel;
end;

procedure TCastlePhysicalHitRagdollBehavior.BeginGetUpRecovery(
  const ADurationSec: Single);
var
  B: TRagdollBoneId;
  GroundOffsetXZ: TVector3;
begin
  GroundOffsetXZ := Vector3(FBones[rbiPelvis].CurLocalPos.X, 0.0, FBones[rbiPelvis].CurLocalPos.Z);
  for B in TRagdollBoneId do
  begin
    { Recenter rest pose over fallen pelvis XZ or recenter fallen pose onto origin }
    FBones[B].CurLocalPos := FBones[B].CurLocalPos - GroundOffsetXZ;
    FBones[B].FrozenRagdollPos := FBones[B].CurLocalPos;
    FBones[B].VelLocal := TVector3.Zero;
  end;
  if Parent <> nil then
    Parent.Translation := Parent.Translation + GroundOffsetXZ;

  FGetUpElapsedSec := 0.0;
  FGetUpDurationSec := Max(0.10, ADurationSec);
  FMode := prmGetUpBlendRecovery;
end;

procedure TCastlePhysicalHitRagdollBehavior.SolveDistanceAndFloorConstraints(
  const EnforceRestLengths: Boolean);
var
  Iter: Integer;
  B, ParentB: TRagdollBoneId;
  Delta: TVector3;
  Dist, Diff, WSum, WChild, WParent, MinY: Single;
begin
  for Iter := 1 to 6 do
  begin
    if EnforceRestLengths then
      for B in TRagdollBoneId do
        if FBones[B].ParentIndex >= 0 then
        begin
          ParentB := TRagdollBoneId(FBones[B].ParentIndex);
          Delta := FBones[B].CurLocalPos - FBones[ParentB].CurLocalPos;
          Dist := Delta.Length;
          if Dist < 1e-5 then
          begin
            Delta := Vector3(0.0, 1.0, 0.0);
            Dist := 1.0;
          end;
          Diff := (Dist - FBones[B].RestLengthToParent) / Dist;
          WSum := FBones[B].InvMass + FBones[ParentB].InvMass;
          if WSum > 1e-5 then
          begin
            WChild := FBones[B].InvMass / WSum;
            WParent := FBones[ParentB].InvMass / WSum;
            FBones[B].CurLocalPos := FBones[B].CurLocalPos - Delta * (Diff * WChild);
            FBones[ParentB].CurLocalPos := FBones[ParentB].CurLocalPos + Delta * (Diff * WParent);
          end;
        end;

    for B in TRagdollBoneId do
    begin
      MinY := FFloorLocalY + FBones[B].BoneRadius;
      if FBones[B].CurLocalPos.Y < MinY then
      begin
        FBones[B].CurLocalPos.Y := MinY;
        if FBones[B].VelLocal.Y < 0.0 then
          FBones[B].VelLocal.Y := 0.0;
        { Ground friction on horizontal slide }
        FBones[B].VelLocal.X := FBones[B].VelLocal.X * 0.86;
        FBones[B].VelLocal.Z := FBones[B].VelLocal.Z * 0.86;
      end;
    end;
  end;
end;

procedure TCastlePhysicalHitRagdollBehavior.StepPhysicalAnimation(
  const TotalDt: Single);
const
  MaxSubDt = 0.01;
var
  SafeTotal, SubDt, Kd, BlendAlpha: Single;
  Steps, S: Integer;
  B: TRagdollBoneId;
  Accel: TVector3;
begin
  SafeTotal := Clamped(TotalDt, 0.0, 0.25);
  if SafeTotal <= 0.0 then Exit;

  if FMode = prmGetUpBlendRecovery then
  begin
    FGetUpElapsedSec := FGetUpElapsedSec + SafeTotal;
    BlendAlpha := SmoothStep01(FGetUpElapsedSec / Max(0.05, FGetUpDurationSec));
    for B in TRagdollBoneId do
    begin
      FBones[B].CurLocalPos := Lerp(BlendAlpha,
        FBones[B].FrozenRagdollPos, FBones[B].RestLocalPos);
      FBones[B].VelLocal := TVector3.Zero;
    end;
    if FGetUpElapsedSec >= FGetUpDurationSec then
      ResetToStandingPose
    else if FBuildVisualRig then
      RebuildOrSyncVisualRig;
    Exit;
  end;

  Steps := Max(1, Ceil(SafeTotal / MaxSubDt));
  SubDt := SafeTotal / Steps;
  Kd := 2.0 * Sqrt(Max(1.0, FSpringStiffnessKp)) * Max(0.15, FDampingRatio);

  for S := 1 to Steps do
  begin
    if FMode = prmActivePhysicalHitReact then
    begin
      { Semi-implicit Euler PD Motor Spring integration toward RestLocalPos }
      for B in TRagdollBoneId do
      begin
        Accel := (FBones[B].RestLocalPos - FBones[B].CurLocalPos) * FSpringStiffnessKp -
                 FBones[B].VelLocal * Kd;
        FBones[B].VelLocal := FBones[B].VelLocal + Accel * SubDt;
        FBones[B].CurLocalPos := FBones[B].CurLocalPos + FBones[B].VelLocal * SubDt;
      end;
      SolveDistanceAndFloorConstraints(False);
    end else
    begin
      { Full Limp Ragdoll: Gravity + PBD Articulated Bone Length & Floor Constraints }
      for B in TRagdollBoneId do
      begin
        FBones[B].PrevLocalPos := FBones[B].CurLocalPos;
        FBones[B].VelLocal.Y := FBones[B].VelLocal.Y - 9.81 * SubDt;
        FBones[B].VelLocal := FBones[B].VelLocal * (1.0 - 0.8 * SubDt);
        FBones[B].CurLocalPos := FBones[B].CurLocalPos + FBones[B].VelLocal * SubDt;
      end;
      SolveDistanceAndFloorConstraints(True);
      for B in TRagdollBoneId do
        FBones[B].VelLocal := (FBones[B].CurLocalPos - FBones[B].PrevLocalPos) * (1.0 / SubDt);
    end;
  end;

  if FBuildVisualRig then
    RebuildOrSyncVisualRig;
end;

procedure TCastlePhysicalHitRagdollBehavior.RebuildOrSyncVisualRig;
var
  B: TRagdollBoneId;
  R: Single;
  Col: TCastleColor;
begin
  if Parent = nil then Exit;

  if FVisualRoot = nil then
  begin
    FVisualRoot := TCastleTransform.Create(Self);
    FVisualRoot.SetTransient;
    Parent.Add(FVisualRoot);
    for B in TRagdollBoneId do
    begin
      FBoneBoxes[B] := TCastleBox.Create(FVisualRoot);
      FBoneBoxes[B].SetTransient;
      FBoneBoxes[B].Pickable := False;
      R := FBones[B].BoneRadius * 1.9;
      FBoneBoxes[B].Size := Vector3(R, R, R);
      FVisualRoot.Add(FBoneBoxes[B]);
    end;
  end;

  case FMode of
    prmActivePhysicalHitReact: Col := Vector4(0.26, 0.82, 0.96, 1.0);
    prmFullLimpRagdoll:        Col := Vector4(0.95, 0.38, 0.32, 1.0);
    prmGetUpBlendRecovery:     Col := Vector4(0.96, 0.82, 0.28, 1.0);
  end;

  for B in TRagdollBoneId do
    if FBoneBoxes[B] <> nil then
    begin
      FBoneBoxes[B].Translation := FBones[B].CurLocalPos;
      if B = rbiHead then
        FBoneBoxes[B].Color := Vector4(0.98, 0.92, 0.78, 1.0)
      else
        FBoneBoxes[B].Color := Col;
    end;
end;

procedure TCastlePhysicalHitRagdollBehavior.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleDesignMode and (not FSimulateInEditor) then
    Exit;
  StepPhysicalAnimation(SecondsPassed);
end;

function TCastlePhysicalHitRagdollBehavior.GetBoneState(
  const ABone: TRagdollBoneId): TRagdollBoneState;
begin
  Result := FBones[ABone];
end;

function TCastlePhysicalHitRagdollBehavior.MaxPoseDeviationMeters: Single;
var
  B: TRagdollBoneId;
begin
  Result := 0.0;
  for B in TRagdollBoneId do
    Result := Max(Result, PointsDistance(FBones[B].CurLocalPos, FBones[B].RestLocalPos));
end;

function TCastlePhysicalHitRagdollBehavior.GetConfigJson: String;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('kp', FSpringStiffnessKp);
    Root.Add('damping', FDampingRatio);
    Root.Add('prop', FImpulsePropagation);
    Root.Add('knockdown', FKnockdownThreshold);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastlePhysicalHitRagdollBehavior.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root: TJSONObject;
  POrd: Integer;
begin
  if Trim(Value) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(Value);
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      POrd := Root.Get('preset', Ord(FPreset));
      if (POrd >= Ord(Low(TPhysicalAnimPreset))) and
         (POrd <= Ord(High(TPhysicalAnimPreset))) then
        FPreset := TPhysicalAnimPreset(POrd);
      FSpringStiffnessKp := Root.Get('kp', FSpringStiffnessKp);
      FDampingRatio := Root.Get('damping', FDampingRatio);
      FImpulsePropagation := Root.Get('prop', FImpulsePropagation);
      FKnockdownThreshold := Root.Get('knockdown', FKnockdownThreshold);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastlePhysicalHitRagdollBehavior.RagdollSummaryBadge: String;
begin
  Result := Format('[PhysAnim:%s %s Dev=%.2fm Hits=%d]',
    [PresetDisplayName(FPreset), ModeDisplayName(FMode),
     MaxPoseDeviationMeters, FTotalHitsReceived]);
end;

initialization
  RegisterSerializableComponent(TCastlePhysicalHitRagdollBehavior,
    ['Animation', 'Physical Animation Hit-React & Ragdoll Behavior']);
end.
