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

{ Motion Matching & Pose Search Locomotion Trajectory Database, Critically-Damped
  Inertialization Pose-Switch Blending & Analytical Stride Warping Runtime
  (@link(TCastlePoseSearchDatabase), @link(TCastleMotionMatchingBehavior),
  @link(PredictSpringTrajectoryXZ), @link(EvaluateInertializationDecay),
  @link(ComputeStrideWarpScale))
  (Phase 327 — UE 6.0+ Pose Search & Motion Matching Parity). }
unit CastleMotionMatching;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform;

type
  { Built-in Motion Matching Pose Search database presets. }
  TPoseSearchPreset = (
    psdpCustom,
    psdpLocomotionOmni8Way,
    psdpStealthCrouchTactical,
    psdpSprintParkourAgile
  );

  { Indexed pose feature vector inside @link(TCastlePoseSearchDatabase).
    All 2D trajectory vectors use character-local @code((X = Right, Y = Forward))
    coordinates in meters / unit direction vectors. }
  TPoseSearchEntry = record
    EntryId: String;
    ClipName: String;
    ClipGroupId: Integer;
    FrameIndexInClip: Integer;
    FrameTimeSec: Single;
    ClipDurationSec: Single;
    Looping: Boolean;
    LocomotionTag: String;
    AuthoredSpeedMps: Single;
    LeftFootLocal: TVector2;
    RightFootLocal: TVector2;
    IncomingForwardSpeedMps: Single;
    TrajectoryPos02: TVector2;
    TrajectoryPos05: TVector2;
    TrajectoryPos10: TVector2;
    TrajectoryFacing05: TVector2;
    TrajectoryFacing10: TVector2;
    EntryBiasCost: Single;
  end;
  TPoseSearchEntryArray = array of TPoseSearchEntry;

  { Cost breakdown returned by @link(TCastlePoseSearchDatabase.FindBestMatchingPose). }
  TPoseSearchCostBreakdown = record
    BestIndex: Integer;
    TrajectoryCost: Single;
    FacingCost: Single;
    FootAndMomentumCost: Single;
    TotalCost: Single;
    IsContiguousClip: Boolean;
  end;

  { Indexed trajectory & foot-feature Pose Search database (@link(TCastleComponent)). }
  TCastlePoseSearchDatabase = class(TCastleComponent)
  public
    const
      DefaultTrajectoryWeight = 1.50;
      DefaultFacingWeight = 1.10;
      DefaultFootPoseWeight = 0.65;
      DefaultMomentumWeight = 0.85;
      DefaultContinuingPoseBias = -0.22;
  strict private
    FPreset: TPoseSearchPreset;
    FTrajectoryWeight: Single;
    FFacingWeight: Single;
    FFootPoseWeight: Single;
    FMomentumWeight: Single;
    FContinuingPoseBias: Single;
    FEntries: TPoseSearchEntryArray;

    procedure SetPreset(const Value: TPoseSearchPreset);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TPoseSearchPreset): String; static;

    procedure ApplyPreset(const APreset: TPoseSearchPreset);
    procedure ClearEntries;
    function AddEntry(const AEntry: TPoseSearchEntry): Integer;
    function EntryCount: Integer;
    function GetEntry(const Index: Integer): TPoseSearchEntry;

    { Query the database for the minimum-cost locomotion pose matching the
      character's predicted local trajectory (@code(PredPos02/05/10),
      @code(PredFace05/10)), current foot offsets, and incoming local forward
      momentum. }
    function FindBestMatchingPose(
      const PredPos02, PredPos05, PredPos10: TVector2;
      const PredFace05, PredFace10: TVector2;
      const CurLeftFoot, CurRightFoot: TVector2;
      const CurForwardSpeedMps: Single;
      const CurrentEntryIndex: Integer): TPoseSearchCostBreakdown;

    function DatabaseSummaryBadge: String;
  published
    property Preset: TPoseSearchPreset
      read FPreset write SetPreset default psdpLocomotionOmni8Way;
    property TrajectoryWeight: Single
      read FTrajectoryWeight write FTrajectoryWeight {$ifdef FPC}default DefaultTrajectoryWeight{$endif};
    property FacingWeight: Single
      read FFacingWeight write FFacingWeight {$ifdef FPC}default DefaultFacingWeight{$endif};
    property FootPoseWeight: Single
      read FFootPoseWeight write FFootPoseWeight {$ifdef FPC}default DefaultFootPoseWeight{$endif};
    property MomentumWeight: Single
      read FMomentumWeight write FMomentumWeight {$ifdef FPC}default DefaultMomentumWeight{$endif};
    property ContinuingPoseBias: Single
      read FContinuingPoseBias write FContinuingPoseBias {$ifdef FPC}default DefaultContinuingPoseBias{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

  { Character locomotion behavior (@link(TCastleBehavior)) continuously predicting
    future spring trajectories, querying @link(TCastlePoseSearchDatabase), damping
    non-contiguous pose transitions via critically-damped Inertialization, and
    scaling stride length via @link(ComputeStrideWarpScale). }
  TCastleMotionMatchingBehavior = class(TCastleBehavior)
  public
    const
      DefaultSearchIntervalSec = 0.08;
      DefaultInertialHalfLifeSec = 0.12;
      DefaultTrajectoryResponsiveness = 6.0;
      DefaultMinStrideScale = 0.65;
      DefaultMaxStrideScale = 1.35;
  strict private
    FDatabase: TCastlePoseSearchDatabase;
    FSearchIntervalSec: Single;
    FInertialHalfLifeSec: Single;
    FTrajectoryResponsiveness: Single;
    FEnableStrideWarping: Boolean;
    FMinStrideScale: Single;
    FMaxStrideScale: Single;
    FDriveParentMovement: Boolean;
    FStrafeLockFacing: Boolean;
    FSimulateInEditor: Boolean;

    { Live locomotion & inertialization state }
    FDesiredWorldVelXZ: TVector2;
    FDesiredFacingWorldXZ: TVector2;
    FCurrentWorldVelXZ: TVector2;
    FCharacterYawRad: Single;
    FSearchTimerSec: Single;

    FCurrentEntryIndex: Integer;
    FCurrentClipName: String;
    FCurrentLocomotionTag: String;
    FCurrentClipTimeSec: Single;
    FActiveStrideWarpScale: Single;

    FInertialInitialOffset: Single;
    FInertialInitialVel: Single;
    FInertialElapsedSec: Single;
    FInertialBlendAlpha: Single;

    FLastSearchCost: TPoseSearchCostBreakdown;
    FPoseSwitchCount: Integer;
    FCurLeftFootLocal: TVector2;
    FCurRightFootLocal: TVector2;

    procedure SetDatabase(const Value: TCastlePoseSearchDatabase);
    procedure SetSearchIntervalSec(const Value: Single);
    procedure SetInertialHalfLifeSec(const Value: Single);
    procedure SyncParentAnimationIfNeeded(const ForceRestart: Boolean);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ResetMotionState;
    procedure SetDesiredWorldVelocityXZ(const AVelXZ: TVector2);
    procedure SetDesiredFacingWorldXZ(const AFacingXZ: TVector2);

    { Compute predicted character-local @code((Right, Forward)) positions and
      facings at @code(+0.20s, +0.50s, +1.00s) from current spring dynamics. }
    procedure PredictLocalTrajectory(
      out OutPos02, OutPos05, OutPos10: TVector2;
      out OutFace05, OutFace10: TVector2);

    procedure ForceImmediatePoseSearch;
    procedure StepMotionMatching(const Dt: Single);

    function MotionSummaryBadge: String;

    property DesiredWorldVelXZ: TVector2 read FDesiredWorldVelXZ write SetDesiredWorldVelocityXZ;
    property DesiredFacingWorldXZ: TVector2 read FDesiredFacingWorldXZ write SetDesiredFacingWorldXZ;
    property CurrentWorldVelXZ: TVector2 read FCurrentWorldVelXZ;
    property CharacterYawRad: Single read FCharacterYawRad write FCharacterYawRad;
    property CurrentEntryIndex: Integer read FCurrentEntryIndex;
    property CurrentClipName: String read FCurrentClipName;
    property CurrentLocomotionTag: String read FCurrentLocomotionTag;
    property CurrentClipTimeSec: Single read FCurrentClipTimeSec;
    property ActiveStrideWarpScale: Single read FActiveStrideWarpScale;
    property InertialBlendAlpha: Single read FInertialBlendAlpha;
    property LastSearchCost: TPoseSearchCostBreakdown read FLastSearchCost;
    property PoseSwitchCount: Integer read FPoseSwitchCount;
  published
    property Database: TCastlePoseSearchDatabase read FDatabase write SetDatabase;
    property SearchIntervalSec: Single
      read FSearchIntervalSec write SetSearchIntervalSec {$ifdef FPC}default DefaultSearchIntervalSec{$endif};
    property InertialHalfLifeSec: Single
      read FInertialHalfLifeSec write SetInertialHalfLifeSec {$ifdef FPC}default DefaultInertialHalfLifeSec{$endif};
    property TrajectoryResponsiveness: Single
      read FTrajectoryResponsiveness write FTrajectoryResponsiveness {$ifdef FPC}default DefaultTrajectoryResponsiveness{$endif};
    property EnableStrideWarping: Boolean
      read FEnableStrideWarping write FEnableStrideWarping default True;
    property MinStrideScale: Single
      read FMinStrideScale write FMinStrideScale {$ifdef FPC}default DefaultMinStrideScale{$endif};
    property MaxStrideScale: Single
      read FMaxStrideScale write FMaxStrideScale {$ifdef FPC}default DefaultMaxStrideScale{$endif};
    property DriveParentMovement: Boolean
      read FDriveParentMovement write FDriveParentMovement default True;
    property StrafeLockFacing: Boolean
      read FStrafeLockFacing write FStrafeLockFacing default False;
    property SimulateInEditor: Boolean
      read FSimulateInEditor write FSimulateInEditor default False;
  end;

{ Analytical spring-velocity trajectory displacement in 2D XZ over @code(HorizonSec)
  for first-order exponential responsiveness @code(dv/dt = k * (DesiredVel - v)):
  @code(DeltaP(T) = DesiredVel * T + ((CurrentVel - DesiredVel) / k) * (1 - exp(-k * T))). }
function PredictSpringTrajectoryXZ(const CurrentVelXZ, DesiredVelXZ: TVector2;
  const ResponsivenessHz, HorizonSec: Single): TVector2;

{ Transform a world XZ vector @code((WorldX, WorldZ)) into character-local
  @code((Right, Forward)) coordinates where @code(YawRad = 0) faces CGE @code(-Z). }
function WorldVecXZToCharacterLocal(const WorldVecXZ: TVector2;
  const CharacterYawRad: Single): TVector2;

{ Critically-damped Holden / UE Inertialization scalar decay with exact half-life:
  at @code(ElapsedSec = 0) returns @code(InitialOffset); for @code(InitialVelocity = 0)
  at @code(ElapsedSec = HalfLifeSec) returns @code(0.5 * InitialOffset) with zero overshoot. }
function EvaluateInertializationDecay(const InitialOffset, InitialVelocity,
  HalfLifeSec, ElapsedSec: Single): Single;

{ Analytical UE Stride Warping multiplier matching @code(DesiredGroundSpeedMps)
  to @code(AuthoredClipSpeedMps) clamped to @code([MinScale .. MaxScale]). }
function ComputeStrideWarpScale(const DesiredGroundSpeedMps, AuthoredClipSpeedMps,
  MinScale, MaxScale: Single): Single;

implementation

uses
  Math, FpJson, JsonParser,
  CastleUtils, CastleComponentSerialize, CastleScene;

const
  { Solution of (1 + u) * exp(-u) = 0.5 -> u = 1.67834699001666 }
  CritDampedHalfLifeOmegaFactor = 1.67834699;

function PredictSpringTrajectoryXZ(const CurrentVelXZ, DesiredVelXZ: TVector2;
  const ResponsivenessHz, HorizonSec: Single): TVector2;
var
  T, K, DecayTerm: Single;
begin
  T := Max(0.0, HorizonSec);
  if T <= 1e-6 then
    Exit(TVector2.Zero);
  K := Max(0.05, ResponsivenessHz);
  DecayTerm := (1.0 - Exp(-K * T)) / K;
  Result.X := DesiredVelXZ.X * T + (CurrentVelXZ.X - DesiredVelXZ.X) * DecayTerm;
  Result.Y := DesiredVelXZ.Y * T + (CurrentVelXZ.Y - DesiredVelXZ.Y) * DecayTerm;
end;

function WorldVecXZToCharacterLocal(const WorldVecXZ: TVector2;
  const CharacterYawRad: Single): TVector2;
var
  SinY, CosY: Single;
  RightXZ, FwdXZ: TVector2;
begin
  SinCos(CharacterYawRad, SinY, CosY);
  { In CGE, Yaw=0 faces -Z (0, -1) and Right is +X (1, 0); positive Yaw rotates CCW around +Y }
  FwdXZ := Vector2(-SinY, -CosY);
  RightXZ := Vector2(CosY, -SinY);
  Result.X := WorldVecXZ.X * RightXZ.X + WorldVecXZ.Y * RightXZ.Y;
  Result.Y := WorldVecXZ.X * FwdXZ.X + WorldVecXZ.Y * FwdXZ.Y;
end;

function EvaluateInertializationDecay(const InitialOffset, InitialVelocity,
  HalfLifeSec, ElapsedSec: Single): Single;
var
  T, SafeHalfLife, Omega0, ExpFactor: Single;
begin
  if ElapsedSec <= 0.0 then
    Exit(InitialOffset);
  T := ElapsedSec;
  SafeHalfLife := Max(0.005, HalfLifeSec);
  Omega0 := CritDampedHalfLifeOmegaFactor / SafeHalfLife;
  ExpFactor := Exp(-Omega0 * T);
  Result := (InitialOffset + (InitialVelocity + Omega0 * InitialOffset) * T) * ExpFactor;
end;

function ComputeStrideWarpScale(const DesiredGroundSpeedMps, AuthoredClipSpeedMps,
  MinScale, MaxScale: Single): Single;
var
  Lo, Hi: Single;
begin
  Lo := Max(0.1, Min(MinScale, MaxScale));
  Hi := Max(Lo, MaxScale);
  if AuthoredClipSpeedMps <= 0.05 then
    Exit(1.0);
  Result := Clamped(Abs(DesiredGroundSpeedMps) / AuthoredClipSpeedMps, Lo, Hi);
end;

function DistSq2D(const A, B: TVector2): Single; inline;
begin
  Result := Sqr(A.X - B.X) + Sqr(A.Y - B.Y);
end;

{ TCastlePoseSearchDatabase -------------------------------------------------- }

constructor TCastlePoseSearchDatabase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTrajectoryWeight := DefaultTrajectoryWeight;
  FFacingWeight := DefaultFacingWeight;
  FFootPoseWeight := DefaultFootPoseWeight;
  FMomentumWeight := DefaultMomentumWeight;
  FContinuingPoseBias := DefaultContinuingPoseBias;
  ApplyPreset(psdpLocomotionOmni8Way);
end;

function TCastlePoseSearchDatabase.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'TrajectoryWeight', 'FacingWeight', 'FootPoseWeight',
       'MomentumWeight', 'ContinuingPoseBias', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastlePoseSearchDatabase.PresetDisplayName(
  const APreset: TPoseSearchPreset): String;
begin
  case APreset of
    psdpCustom:                 Result := 'Custom Pose Search DB';
    psdpLocomotionOmni8Way:     Result := 'Omni 8-Way + 180 Pivot + Stop DB';
    psdpStealthCrouchTactical:  Result := 'Stealth Crouch Tactical Strafe DB';
    psdpSprintParkourAgile:     Result := 'Sprint & Agile Parkour Cuts DB';
  end;
end;

procedure TCastlePoseSearchDatabase.SetPreset(const Value: TPoseSearchPreset);
begin
  if FPreset = Value then
    Exit;
  ApplyPreset(Value);
end;

procedure TCastlePoseSearchDatabase.ClearEntries;
begin
  FEntries := nil;
end;

function TCastlePoseSearchDatabase.AddEntry(const AEntry: TPoseSearchEntry): Integer;
begin
  Result := Length(FEntries);
  SetLength(FEntries, Result + 1);
  FEntries[Result] := AEntry;
end;

function TCastlePoseSearchDatabase.EntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TCastlePoseSearchDatabase.GetEntry(const Index: Integer): TPoseSearchEntry;
begin
  if (Index >= 0) and (Index < Length(FEntries)) then
    Result := FEntries[Index]
  else
    Result := Default(TPoseSearchEntry);
end;

procedure TCastlePoseSearchDatabase.ApplyPreset(const APreset: TPoseSearchPreset);

  procedure AddSteadyClipFrames(const AGroupId: Integer;
    const AClipName, ATag: String; const ADurSec: Single;
    const ALocalVel, ALocalFacing: TVector2;
    const ASpeedMps, AStrideAmp, ABias: Single; const AFrameCount: Integer);
  var
    K: Integer;
    Phase, T: Single;
    E: TPoseSearchEntry;
  begin
    for K := 0 to AFrameCount - 1 do
    begin
      T := (K / Max(1, AFrameCount)) * ADurSec;
      Phase := (K / Max(1, AFrameCount)) * 2.0 * Pi;
      E := Default(TPoseSearchEntry);
      E.EntryId := Format('%s_f%d', [AClipName, K]);
      E.ClipName := AClipName;
      E.ClipGroupId := AGroupId;
      E.FrameIndexInClip := K;
      E.FrameTimeSec := T;
      E.ClipDurationSec := ADurSec;
      E.Looping := True;
      E.LocomotionTag := ATag;
      E.AuthoredSpeedMps := ASpeedMps;
      E.LeftFootLocal := Vector2(-0.14, Sin(Phase) * AStrideAmp);
      E.RightFootLocal := Vector2(0.14, -Sin(Phase) * AStrideAmp);
      E.IncomingForwardSpeedMps := ALocalVel.Y;
      E.TrajectoryPos02 := ALocalVel * 0.20;
      E.TrajectoryPos05 := ALocalVel * 0.50;
      E.TrajectoryPos10 := ALocalVel * 1.00;
      E.TrajectoryFacing05 := ALocalFacing;
      E.TrajectoryFacing10 := ALocalFacing;
      E.EntryBiasCost := ABias;
      AddEntry(E);
    end;
  end;

var
  WalkSpd, RunSpd, SprintSpd: Single;
  E: TPoseSearchEntry;
  K: Integer;
begin
  FPreset := APreset;
  if APreset = psdpCustom then
    Exit;

  ClearEntries;
  case APreset of
    psdpStealthCrouchTactical:
      begin
        WalkSpd := 1.25;
        RunSpd := 2.80;
        SprintSpd := 4.20;
      end;
    psdpSprintParkourAgile:
      begin
        WalkSpd := 2.10;
        RunSpd := 5.40;
        SprintSpd := 8.20;
      end;
  else
    begin
      WalkSpd := 1.80;
      RunSpd := 4.80;
      SprintSpd := 7.00;
    end;
  end;

  { 1. Idle (4 frames) }
  AddSteadyClipFrames(1, 'IdleBreathe', 'Idle', 1.20,
    Vector2(0.0, 0.0), Vector2(0.0, 1.0), 0.0, 0.02, 0.0, 4);

  { 2. Walk Forward (6 frames) }
  AddSteadyClipFrames(2, 'WalkForward', 'Walk', 1.00,
    Vector2(0.0, WalkSpd), Vector2(0.0, 1.0), WalkSpd, 0.28, 0.0, 6);

  { 3. Run Forward (6 frames) }
  AddSteadyClipFrames(3, 'RunForward', 'Run', 0.72,
    Vector2(0.0, RunSpd), Vector2(0.0, 1.0), RunSpd, 0.52, 0.0, 6);

  { 4. Sprint Forward (6 frames) }
  AddSteadyClipFrames(4, 'SprintForward', 'Sprint', 0.56,
    Vector2(0.0, SprintSpd), Vector2(0.0, 1.0), SprintSpd, 0.68, 0.0, 6);

  { 5. Strafe Left & Strafe Right (4 frames each, facing forward +Y) }
  AddSteadyClipFrames(5, 'StrafeLeft', 'StrafeLeft', 0.84,
    Vector2(-WalkSpd * 1.15, 0.0), Vector2(0.0, 1.0), WalkSpd * 1.15, 0.26, 0.02, 4);
  AddSteadyClipFrames(6, 'StrafeRight', 'StrafeRight', 0.84,
    Vector2(WalkSpd * 1.15, 0.0), Vector2(0.0, 1.0), WalkSpd * 1.15, 0.26, 0.02, 4);

  { 6. Walk Backward / Backpedal (4 frames, facing forward +Y while moving -Y) }
  AddSteadyClipFrames(7, 'WalkBackward', 'Backpedal', 1.00,
    Vector2(0.0, -WalkSpd * 0.90), Vector2(0.0, 1.0), WalkSpd * 0.90, 0.24, 0.03, 4);

  { 7. Transition Clip: PlantPivot180 (3 frames — high incoming +Forward momentum,
       reversing into -Forward (-Y) trajectory & -Y 180-deg turnaround facing!) }
  for K := 0 to 2 do
  begin
    E := Default(TPoseSearchEntry);
    E.EntryId := Format('PlantPivot180_f%d', [K]);
    E.ClipName := 'PlantPivot180';
    E.ClipGroupId := 8;
    E.FrameIndexInClip := K;
    E.FrameTimeSec := K * 0.12;
    E.ClipDurationSec := 0.55;
    E.Looping := False;
    E.LocomotionTag := 'Pivot180';
    E.AuthoredSpeedMps := RunSpd;
    E.LeftFootLocal := Vector2(-0.16, 0.38 - K * 0.18);
    E.RightFootLocal := Vector2(0.16, -0.24 + K * 0.14);
    E.IncomingForwardSpeedMps := RunSpd * (0.95 - 0.25 * K);
    E.TrajectoryPos02 := Vector2(0.0, 0.10 - 0.35 * K);
    E.TrajectoryPos05 := Vector2(0.0, -RunSpd * (0.28 + 0.08 * K));
    E.TrajectoryPos10 := Vector2(0.0, -RunSpd * (0.78 + 0.06 * K));
    E.TrajectoryFacing05 := Vector2(0.0, -1.0);
    E.TrajectoryFacing10 := Vector2(0.0, -1.0);
    E.EntryBiasCost := 0.05;
    AddEntry(E);
  end;

  { 8. Transition Clip: RunStopPlant (3 frames — high incoming +Forward momentum,
       decelerating rapidly to zero displacement while keeping +Y facing!) }
  for K := 0 to 2 do
  begin
    E := Default(TPoseSearchEntry);
    E.EntryId := Format('RunStopPlant_f%d', [K]);
    E.ClipName := 'RunStopPlant';
    E.ClipGroupId := 9;
    E.FrameIndexInClip := K;
    E.FrameTimeSec := K * 0.10;
    E.ClipDurationSec := 0.48;
    E.Looping := False;
    E.LocomotionTag := 'SuddenStop';
    E.AuthoredSpeedMps := WalkSpd;
    E.LeftFootLocal := Vector2(-0.15, 0.42 - K * 0.15);
    E.RightFootLocal := Vector2(0.15, -0.18);
    E.IncomingForwardSpeedMps := RunSpd * (0.85 - 0.30 * K);
    E.TrajectoryPos02 := Vector2(0.0, 0.26 - 0.08 * K);
    E.TrajectoryPos05 := Vector2(0.0, 0.34 - 0.10 * K);
    E.TrajectoryPos10 := Vector2(0.0, 0.36 - 0.10 * K);
    E.TrajectoryFacing05 := Vector2(0.0, 1.0);
    E.TrajectoryFacing10 := Vector2(0.0, 1.0);
    E.EntryBiasCost := 0.06;
    AddEntry(E);
  end;
end;

function TCastlePoseSearchDatabase.FindBestMatchingPose(
  const PredPos02, PredPos05, PredPos10: TVector2;
  const PredFace05, PredFace10: TVector2;
  const CurLeftFoot, CurRightFoot: TVector2;
  const CurForwardSpeedMps: Single;
  const CurrentEntryIndex: Integer): TPoseSearchCostBreakdown;
var
  I, CurGroup, CurFrame: Integer;
  TrajC, FaceC, FootMomC, TotalC: Single;
  IsContig: Boolean;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.BestIndex := -1;
  Result.TotalCost := 1e30;
  if Length(FEntries) = 0 then
    Exit;

  CurGroup := -1;
  CurFrame := -1;
  if (CurrentEntryIndex >= 0) and (CurrentEntryIndex < Length(FEntries)) then
  begin
    CurGroup := FEntries[CurrentEntryIndex].ClipGroupId;
    CurFrame := FEntries[CurrentEntryIndex].FrameIndexInClip;
  end;

  for I := 0 to High(FEntries) do
  begin
    TrajC := FTrajectoryWeight * (
      DistSq2D(PredPos02, FEntries[I].TrajectoryPos02) * 1.50 +
      DistSq2D(PredPos05, FEntries[I].TrajectoryPos05) * 1.15 +
      DistSq2D(PredPos10, FEntries[I].TrajectoryPos10) * 0.85);

    FaceC := FFacingWeight * (
      DistSq2D(PredFace05, FEntries[I].TrajectoryFacing05) +
      DistSq2D(PredFace10, FEntries[I].TrajectoryFacing10));

    FootMomC :=
      FFootPoseWeight * (
        DistSq2D(CurLeftFoot, FEntries[I].LeftFootLocal) +
        DistSq2D(CurRightFoot, FEntries[I].RightFootLocal)) +
      FMomentumWeight * Sqr((CurForwardSpeedMps - FEntries[I].IncomingForwardSpeedMps) * 0.25);

    IsContig := (CurGroup >= 0) and (FEntries[I].ClipGroupId = CurGroup) and
      ((FEntries[I].FrameIndexInClip = CurFrame) or
       (FEntries[I].FrameIndexInClip = CurFrame + 1) or
       (FEntries[I].Looping and (FEntries[I].FrameIndexInClip = 0)));

    TotalC := TrajC + FaceC + FootMomC + FEntries[I].EntryBiasCost;
    if IsContig then
      TotalC := TotalC + FContinuingPoseBias;

    if TotalC < Result.TotalCost then
    begin
      Result.BestIndex := I;
      Result.TrajectoryCost := TrajC;
      Result.FacingCost := FaceC;
      Result.FootAndMomentumCost := FootMomC;
      Result.TotalCost := TotalC;
      Result.IsContiguousClip := IsContig;
    end;
  end;
end;

function TCastlePoseSearchDatabase.GetConfigJson: String;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('trajectoryWeight', FTrajectoryWeight);
    Root.Add('facingWeight', FFacingWeight);
    Root.Add('footPoseWeight', FFootPoseWeight);
    Root.Add('momentumWeight', FMomentumWeight);
    Root.Add('continuingPoseBias', FContinuingPoseBias);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastlePoseSearchDatabase.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root: TJSONObject;
  PresetOrd: Integer;
begin
  if Trim(Value) = '' then
    Exit;
  Data := nil;
  try
    Data := GetJSON(Value);
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      PresetOrd := Root.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TPoseSearchPreset))) and
         (PresetOrd <= Ord(High(TPoseSearchPreset))) then
        ApplyPreset(TPoseSearchPreset(PresetOrd));
      FTrajectoryWeight := Root.Get('trajectoryWeight', FTrajectoryWeight);
      FFacingWeight := Root.Get('facingWeight', FFacingWeight);
      FFootPoseWeight := Root.Get('footPoseWeight', FFootPoseWeight);
      FMomentumWeight := Root.Get('momentumWeight', FMomentumWeight);
      FContinuingPoseBias := Root.Get('continuingPoseBias', FContinuingPoseBias);
    end;
  except
    { Keep current DB settings on malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastlePoseSearchDatabase.DatabaseSummaryBadge: String;
begin
  Result := Format('[PoseSearchDB:%s %d poses]',
    [PresetDisplayName(FPreset), Length(FEntries)]);
end;

{ TCastleMotionMatchingBehavior ---------------------------------------------- }

constructor TCastleMotionMatchingBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSearchIntervalSec := DefaultSearchIntervalSec;
  FInertialHalfLifeSec := DefaultInertialHalfLifeSec;
  FTrajectoryResponsiveness := DefaultTrajectoryResponsiveness;
  FEnableStrideWarping := True;
  FMinStrideScale := DefaultMinStrideScale;
  FMaxStrideScale := DefaultMaxStrideScale;
  FDriveParentMovement := True;
  FStrafeLockFacing := False;
  FSimulateInEditor := False;
  ResetMotionState;
end;

procedure TCastleMotionMatchingBehavior.ResetMotionState;
begin
  FDesiredWorldVelXZ := TVector2.Zero;
  FDesiredFacingWorldXZ := Vector2(0.0, -1.0);
  FCurrentWorldVelXZ := TVector2.Zero;
  FCharacterYawRad := 0.0;
  FSearchTimerSec := DefaultSearchIntervalSec;
  FCurrentEntryIndex := -1;
  FCurrentClipName := 'IdleBreathe';
  FCurrentLocomotionTag := 'Idle';
  FCurrentClipTimeSec := 0.0;
  FActiveStrideWarpScale := 1.0;
  FInertialInitialOffset := 0.0;
  FInertialInitialVel := 0.0;
  FInertialElapsedSec := 10.0;
  FInertialBlendAlpha := 0.0;
  FPoseSwitchCount := 0;
  FCurLeftFootLocal := Vector2(-0.14, 0.0);
  FCurRightFootLocal := Vector2(0.14, 0.0);
  FillChar(FLastSearchCost, SizeOf(FLastSearchCost), 0);
  FLastSearchCost.BestIndex := -1;
end;

procedure TCastleMotionMatchingBehavior.Notification(
  AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FDatabase) then
    FDatabase := nil;
end;

procedure TCastleMotionMatchingBehavior.SetDatabase(
  const Value: TCastlePoseSearchDatabase);
begin
  if FDatabase = Value then
    Exit;
  if FDatabase <> nil then
    FDatabase.RemoveFreeNotification(Self);
  FDatabase := Value;
  if FDatabase <> nil then
    FDatabase.FreeNotification(Self);
end;

procedure TCastleMotionMatchingBehavior.SetSearchIntervalSec(const Value: Single);
begin
  FSearchIntervalSec := Clamped(Value, 0.01, 1.0);
end;

procedure TCastleMotionMatchingBehavior.SetInertialHalfLifeSec(const Value: Single);
begin
  FInertialHalfLifeSec := Clamped(Value, 0.01, 1.0);
end;

function TCastleMotionMatchingBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Database', 'SearchIntervalSec', 'InertialHalfLifeSec',
       'TrajectoryResponsiveness', 'EnableStrideWarping', 'MinStrideScale',
       'MaxStrideScale', 'DriveParentMovement', 'StrafeLockFacing',
       'SimulateInEditor'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMotionMatchingBehavior.SetDesiredWorldVelocityXZ(
  const AVelXZ: TVector2);
begin
  FDesiredWorldVelXZ := AVelXZ;
end;

procedure TCastleMotionMatchingBehavior.SetDesiredFacingWorldXZ(
  const AFacingXZ: TVector2);
begin
  if AFacingXZ.Length > 1e-4 then
    FDesiredFacingWorldXZ := AFacingXZ.Normalize;
end;

procedure TCastleMotionMatchingBehavior.PredictLocalTrajectory(
  out OutPos02, OutPos05, OutPos10: TVector2;
  out OutFace05, OutFace10: TVector2);
var
  WorldOff02, WorldOff05, WorldOff10, TargetWorldFacing: TVector2;
begin
  WorldOff02 := PredictSpringTrajectoryXZ(
    FCurrentWorldVelXZ, FDesiredWorldVelXZ, FTrajectoryResponsiveness, 0.20);
  WorldOff05 := PredictSpringTrajectoryXZ(
    FCurrentWorldVelXZ, FDesiredWorldVelXZ, FTrajectoryResponsiveness, 0.50);
  WorldOff10 := PredictSpringTrajectoryXZ(
    FCurrentWorldVelXZ, FDesiredWorldVelXZ, FTrajectoryResponsiveness, 1.00);

  OutPos02 := WorldVecXZToCharacterLocal(WorldOff02, FCharacterYawRad);
  OutPos05 := WorldVecXZToCharacterLocal(WorldOff05, FCharacterYawRad);
  OutPos10 := WorldVecXZToCharacterLocal(WorldOff10, FCharacterYawRad);

  if FStrafeLockFacing then
    TargetWorldFacing := FDesiredFacingWorldXZ
  else if FDesiredWorldVelXZ.Length > 0.15 then
    TargetWorldFacing := FDesiredWorldVelXZ.Normalize
  else
    TargetWorldFacing := Vector2(-Sin(FCharacterYawRad), -Cos(FCharacterYawRad));

  OutFace05 := WorldVecXZToCharacterLocal(TargetWorldFacing, FCharacterYawRad);
  if OutFace05.Length > 1e-4 then
    OutFace05 := OutFace05.Normalize
  else
    OutFace05 := Vector2(0.0, 1.0);
  OutFace10 := OutFace05;
end;

procedure TCastleMotionMatchingBehavior.SyncParentAnimationIfNeeded(
  const ForceRestart: Boolean);
var
  Scn: TCastleScene;
begin
  if (Parent <> nil) and (Parent is TCastleScene) then
  begin
    Scn := TCastleScene(Parent);
    if Scn.HasAnimation(FCurrentClipName) and
       (ForceRestart or (Scn.CurrentAnimation = nil) or
        (Scn.CurrentAnimation.X3DName <> FCurrentClipName)) then
      Scn.PlayAnimation(FCurrentClipName, True);
  end;
end;

procedure TCastleMotionMatchingBehavior.ForceImmediatePoseSearch;
var
  Pos02, Pos05, Pos10, Face05, Face10, CurLocalVel: TVector2;
  Cost: TPoseSearchCostBreakdown;
  Chosen: TPoseSearchEntry;
  GroundSpd: Single;
  WasDisjointJump: Boolean;
begin
  if (FDatabase = nil) or (FDatabase.EntryCount = 0) then
    Exit;

  PredictLocalTrajectory(Pos02, Pos05, Pos10, Face05, Face10);
  CurLocalVel := WorldVecXZToCharacterLocal(FCurrentWorldVelXZ, FCharacterYawRad);

  Cost := FDatabase.FindBestMatchingPose(
    Pos02, Pos05, Pos10, Face05, Face10,
    FCurLeftFootLocal, FCurRightFootLocal, CurLocalVel.Y, FCurrentEntryIndex);
  FLastSearchCost := Cost;
  if Cost.BestIndex < 0 then
    Exit;

  Chosen := FDatabase.GetEntry(Cost.BestIndex);
  WasDisjointJump := (FCurrentEntryIndex >= 0) and (not Cost.IsContiguousClip);

  FCurrentEntryIndex := Cost.BestIndex;
  FCurrentClipName := Chosen.ClipName;
  FCurrentLocomotionTag := Chosen.LocomotionTag;
  if WasDisjointJump or (FPoseSwitchCount = 0) then
  begin
    FCurrentClipTimeSec := Chosen.FrameTimeSec;
    FCurLeftFootLocal := Chosen.LeftFootLocal;
    FCurRightFootLocal := Chosen.RightFootLocal;
    if WasDisjointJump then
    begin
      Inc(FPoseSwitchCount);
      FInertialInitialOffset := Clamped(FInertialBlendAlpha + 0.85, 0.50, 1.00);
      FInertialInitialVel := -1.20;
      FInertialElapsedSec := 0.0;
      FInertialBlendAlpha := FInertialInitialOffset;
    end else
      Inc(FPoseSwitchCount);
    SyncParentAnimationIfNeeded(True);
  end;

  GroundSpd := Max(FCurrentWorldVelXZ.Length, FDesiredWorldVelXZ.Length);
  if FEnableStrideWarping then
    FActiveStrideWarpScale := ComputeStrideWarpScale(
      GroundSpd, Chosen.AuthoredSpeedMps, FMinStrideScale, FMaxStrideScale)
  else
    FActiveStrideWarpScale := 1.0;
end;

procedure TCastleMotionMatchingBehavior.StepMotionMatching(const Dt: Single);
var
  SafeDt, K, AlphaVel, DesiredYaw, DeltaYaw, MaxTurnStep, GroundSpd: Single;
  Chosen: TPoseSearchEntry;
  TargetFacingW: TVector2;
begin
  SafeDt := Clamped(Dt, 0.0, 0.25);
  if SafeDt <= 0.0 then
    Exit;

  { 1. Advance spring-damped world velocity }
  K := Max(0.05, FTrajectoryResponsiveness);
  AlphaVel := 1.0 - Exp(-K * SafeDt);
  FCurrentWorldVelXZ.X := FCurrentWorldVelXZ.X + (FDesiredWorldVelXZ.X - FCurrentWorldVelXZ.X) * AlphaVel;
  FCurrentWorldVelXZ.Y := FCurrentWorldVelXZ.Y + (FDesiredWorldVelXZ.Y - FCurrentWorldVelXZ.Y) * AlphaVel;

  { 2. Periodic Pose Search query BEFORE turning yaw so sudden 180-deg input
       reversals are detected against the character's incoming forward heading }
  FSearchTimerSec := FSearchTimerSec + SafeDt;
  if FSearchTimerSec >= FSearchIntervalSec then
  begin
    FSearchTimerSec := 0.0;
    ForceImmediatePoseSearch;
  end;

  { 3. Advance character yaw toward movement direction or strafe-lock target }
  if FStrafeLockFacing then
    TargetFacingW := FDesiredFacingWorldXZ
  else if FCurrentWorldVelXZ.Length > 0.20 then
    TargetFacingW := FCurrentWorldVelXZ.Normalize
  else
    TargetFacingW := Vector2(-Sin(FCharacterYawRad), -Cos(FCharacterYawRad));

  if TargetFacingW.Length > 1e-4 then
  begin
    DesiredYaw := ArcTan2(-TargetFacingW.X, -TargetFacingW.Y);
    DeltaYaw := DesiredYaw - FCharacterYawRad;
    while DeltaYaw > Pi do DeltaYaw := DeltaYaw - 2.0 * Pi;
    while DeltaYaw < -Pi do DeltaYaw := DeltaYaw + 2.0 * Pi;
    MaxTurnStep := 7.5 * SafeDt;
    FCharacterYawRad := FCharacterYawRad + Clamped(DeltaYaw, -MaxTurnStep, MaxTurnStep);
  end;

  { 4. Advance clip playback clock, foot phase & Inertialization decay }
  if (FDatabase <> nil) and (FCurrentEntryIndex >= 0) and
     (FCurrentEntryIndex < FDatabase.EntryCount) then
  begin
    Chosen := FDatabase.GetEntry(FCurrentEntryIndex);
    GroundSpd := FCurrentWorldVelXZ.Length;
    if FEnableStrideWarping then
      FActiveStrideWarpScale := ComputeStrideWarpScale(
        GroundSpd, Chosen.AuthoredSpeedMps, FMinStrideScale, FMaxStrideScale)
    else
      FActiveStrideWarpScale := 1.0;

    FCurrentClipTimeSec := FCurrentClipTimeSec + SafeDt;
    if Chosen.ClipDurationSec > 0.05 then
    begin
      if Chosen.Looping then
      begin
        while FCurrentClipTimeSec >= Chosen.ClipDurationSec do
          FCurrentClipTimeSec := FCurrentClipTimeSec - Chosen.ClipDurationSec;
      end else if FCurrentClipTimeSec > Chosen.ClipDurationSec then
        FCurrentClipTimeSec := Chosen.ClipDurationSec;
    end;
    FCurLeftFootLocal := Vector2(-0.14, Sin((FCurrentClipTimeSec / Max(0.1, Chosen.ClipDurationSec)) * 2.0 * Pi) * 0.35);
    FCurRightFootLocal := Vector2(0.14, -FCurLeftFootLocal.Y);
  end;

  FInertialElapsedSec := FInertialElapsedSec + SafeDt;
  FInertialBlendAlpha := Clamped(
    EvaluateInertializationDecay(FInertialInitialOffset, FInertialInitialVel,
      FInertialHalfLifeSec, FInertialElapsedSec),
    0.0, 1.0);

  { 5. Drive Parent Transform world translation & yaw orientation if enabled }
  if FDriveParentMovement and (Parent <> nil) then
  begin
    Parent.Translation := Parent.Translation +
      Vector3(FCurrentWorldVelXZ.X * SafeDt, 0.0, FCurrentWorldVelXZ.Y * SafeDt);
    Parent.Rotation := Vector4(0.0, 1.0, 0.0, FCharacterYawRad);
  end;
end;

procedure TCastleMotionMatchingBehavior.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleDesignMode and (not FSimulateInEditor) then
    Exit;
  StepMotionMatching(SecondsPassed);
end;

function TCastleMotionMatchingBehavior.MotionSummaryBadge: String;
begin
  Result := Format('[MotionMatch:%s (%s) Stride=%.2fx Inert=%.0f%%]',
    [FCurrentClipName, FCurrentLocomotionTag,
     FActiveStrideWarpScale, FInertialBlendAlpha * 100.0]);
end;

initialization
  RegisterSerializableComponent(TCastlePoseSearchDatabase,
    ['Animation', 'Pose Search Database (Motion Matching)']);
  RegisterSerializableComponent(TCastleMotionMatchingBehavior,
    ['Animation', 'Motion Matching Locomotion Behavior']);
end.
