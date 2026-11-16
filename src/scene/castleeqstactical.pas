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

{ Environment Query System (EQS) Tactical Ring & Grid Candidate Generator,
  WorldRay Line-of-Sight Cover / Vantage Filtering, Elevation & Dot-Flank
  Scoring (@link(TCastleEqsQueryBehavior), @link(EvaluateDistanceBandScore),
  @link(EvaluateFlankRearScore))
  (Phase 319 — UE 6.0+ Environment Query System Parity). }
unit CastleEqsTactical;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform,
  CastleBehaviors, CastleScene;

type
  { Spatial candidate point layout around Querier or Threat context. }
  TEqsGeneratorShape = (
    egsConcentricRings,
    egsTacticalGrid
  );

  { Built-in tactical AI query presets. }
  TEqsPreset = (
    epCustom,
    epTakeCoverFromThreat,
    epSniperLineOfSightVantage,
    epFlankRearSurround
  );

  { Diagnostic & scoring record for a single EQS candidate world point. }
  TEqsCandidateItem = record
    WorldPos: TVector3;
    FilteredOut: Boolean;
    HasClearLoSToThreat: Boolean;
    RawScore: Single;
    NormalizedScore: Single;
    RejectReason: String;
  end;
  TEqsCandidateItemArray = array of TEqsCandidateItem;

  { Environment Query System (EQS) tactical spatial query behavior.
    Generates ring or grid candidate points on walkable world geometry, runs
    visibility occlusion / clear-LoS raycasts against @link(ThreatTransform),
    scores distance bands, high-ground elevation, and rear-flank dot angles,
    and optionally renders @code(csTransient) 3D debug score spheres. }
  TCastleEqsQueryBehavior = class(TCastleBehavior)
  public
    const
      DefaultInnerRadius = 2.5;
      DefaultOuterRadius = 10.0;
      DefaultRingCount = 3;
      DefaultPointsPerRing = 12;
      DefaultGridHalfExtent = 9.0;
      DefaultGridSpacing = 2.25;
      DefaultEyeHeightOffset = 1.25;
      DefaultMaxWalkableHeightDelta = 1.40;
      DefaultOptimalDistToThreat = 9.5;
      DefaultOptimalDistBandWidth = 8.0;
      DefaultMoveSpeedMps = 4.8;
  strict private
    FPreset: TEqsPreset;
    FGeneratorShape: TEqsGeneratorShape;
    FCenterAroundThreat: Boolean;
    FInnerRadius: Single;
    FOuterRadius: Single;
    FRingCount: Integer;
    FPointsPerRing: Integer;
    FGridHalfExtent: Single;
    FGridSpacing: Single;

    FThreatTransform: TCastleTransform;
    FEyeHeightOffset: Single;
    FMaxWalkableHeightDelta: Single;
    FRequireLoSOccludedFromThreat: Boolean;
    FRequireClearLoSToThreat: Boolean;

    FOptimalDistToThreat: Single;
    FOptimalDistBandWidth: Single;
    FDistanceBandWeight: Single;
    FProximityToQuerierWeight: Single;
    FElevationBonusWeight: Single;
    FRearFlankWeight: Single;

    FShowDebugSpheres: Boolean;
    FAutoMoveToBestSpot: Boolean;
    FMoveSpeedMps: Single;
    FQueryIntervalSec: Single;
    FQueryAccumulatorSec: Single;

    FCandidates: TEqsCandidateItemArray;
    FHasValidBestSpot: Boolean;
    FBestCandidateIndex: Integer;
    FBestWorldPos: TVector3;
    FBestScore: Single;

    FDebugRoot: TCastleTransform;

    procedure SetPreset(const Value: TEqsPreset);
    procedure SetThreatTransform(const Value: TCastleTransform);
    procedure SetShowDebugSpheres(const Value: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    function CheckClearLineOfSight(const FromEyeW, ToTargetEyeW: TVector3): Boolean;
    function ProjectCandidateToFloor(const CandidateXZ: TVector3;
      const BaseFloorY: Single; out OutGroundedPos: TVector3): Boolean;
    procedure RebuildDebugSpheres;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TEqsPreset): String; static;

    procedure ApplyPreset(const APreset: TEqsPreset);
    function RunQuery: Boolean;
    procedure StepEqsAgent(const Dt: Single);

    function CandidateCount: Integer;
    function ValidCandidateCount: Integer;
    function GetCandidate(const Index: Integer): TEqsCandidateItem;
    function EqsSummaryBadge: String;

    property HasValidBestSpot: Boolean read FHasValidBestSpot;
    property BestCandidateIndex: Integer read FBestCandidateIndex;
    property BestWorldPos: TVector3 read FBestWorldPos;
    property BestScore: Single read FBestScore;
  published
    property Preset: TEqsPreset read FPreset write SetPreset default epTakeCoverFromThreat;
    property GeneratorShape: TEqsGeneratorShape read FGeneratorShape write FGeneratorShape default egsTacticalGrid;
    property CenterAroundThreat: Boolean read FCenterAroundThreat write FCenterAroundThreat default false;
    property InnerRadius: Single read FInnerRadius write FInnerRadius {$ifdef FPC}default DefaultInnerRadius{$endif};
    property OuterRadius: Single read FOuterRadius write FOuterRadius {$ifdef FPC}default DefaultOuterRadius{$endif};
    property RingCount: Integer read FRingCount write FRingCount default DefaultRingCount;
    property PointsPerRing: Integer read FPointsPerRing write FPointsPerRing default DefaultPointsPerRing;
    property GridHalfExtent: Single read FGridHalfExtent write FGridHalfExtent {$ifdef FPC}default DefaultGridHalfExtent{$endif};
    property GridSpacing: Single read FGridSpacing write FGridSpacing {$ifdef FPC}default DefaultGridSpacing{$endif};

    property ThreatTransform: TCastleTransform read FThreatTransform write SetThreatTransform;
    property EyeHeightOffset: Single read FEyeHeightOffset write FEyeHeightOffset {$ifdef FPC}default DefaultEyeHeightOffset{$endif};
    property MaxWalkableHeightDelta: Single read FMaxWalkableHeightDelta write FMaxWalkableHeightDelta {$ifdef FPC}default DefaultMaxWalkableHeightDelta{$endif};
    property RequireLoSOccludedFromThreat: Boolean read FRequireLoSOccludedFromThreat write FRequireLoSOccludedFromThreat default true;
    property RequireClearLoSToThreat: Boolean read FRequireClearLoSToThreat write FRequireClearLoSToThreat default false;

    property OptimalDistToThreat: Single read FOptimalDistToThreat write FOptimalDistToThreat {$ifdef FPC}default DefaultOptimalDistToThreat{$endif};
    property OptimalDistBandWidth: Single read FOptimalDistBandWidth write FOptimalDistBandWidth {$ifdef FPC}default DefaultOptimalDistBandWidth{$endif};
    property DistanceBandWeight: Single read FDistanceBandWeight write FDistanceBandWeight {$ifdef FPC}default 1.0{$endif};
    property ProximityToQuerierWeight: Single read FProximityToQuerierWeight write FProximityToQuerierWeight {$ifdef FPC}default 1.2{$endif};
    property ElevationBonusWeight: Single read FElevationBonusWeight write FElevationBonusWeight {$ifdef FPC}default 0.0{$endif};
    property RearFlankWeight: Single read FRearFlankWeight write FRearFlankWeight {$ifdef FPC}default 0.0{$endif};

    property ShowDebugSpheres: Boolean read FShowDebugSpheres write SetShowDebugSpheres default false;
    property AutoMoveToBestSpot: Boolean read FAutoMoveToBestSpot write FAutoMoveToBestSpot default false;
    property MoveSpeedMps: Single read FMoveSpeedMps write FMoveSpeedMps {$ifdef FPC}default DefaultMoveSpeedMps{$endif};
    property QueryIntervalSec: Single read FQueryIntervalSec write FQueryIntervalSec {$ifdef FPC}default 0.5{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

{ Bell-shaped tactical distance band score in [0..1] peaking at @code(OptimalDist). }
function EvaluateDistanceBandScore(
  const ActualDist, OptimalDist, BandWidth: Single): Single;

{ Tactical flank score in [0..1]: 1.0 directly behind @code(ThreatForwardXZ)
  (180 deg rear arc), 0.5 at 90 deg side flank, 0.0 directly in front of threat. }
function EvaluateFlankRearScore(
  const ThreatPos, ThreatForwardW, CandidatePos: TVector3): Single;

implementation

uses
  Math, fpjson, jsonparser,
  CastleUtils, CastleComponentSerialize, CastleApplicationProperties, X3DNodes;

function EvaluateDistanceBandScore(
  const ActualDist, OptimalDist, BandWidth: Single): Single;
var
  SafeBand, NormDiff: Single;
begin
  SafeBand := Max(0.25, Abs(BandWidth));
  NormDiff := Abs(ActualDist - OptimalDist) / SafeBand;
  Result := Clamped(1.0 - Sqr(Clamped(NormDiff, 0.0, 1.0)), 0.0, 1.0);
end;

function EvaluateFlankRearScore(
  const ThreatPos, ThreatForwardW, CandidatePos: TVector3): Single;
var
  FlatFwd, ToCandFlat: TVector3;
  DotVal: Single;
begin
  FlatFwd := Vector3(ThreatForwardW.X, 0.0, ThreatForwardW.Z);
  if FlatFwd.LengthSqr < 1e-6 then
    FlatFwd := Vector3(0.0, 0.0, -1.0)
  else
    FlatFwd := FlatFwd.Normalize;

  ToCandFlat := Vector3(CandidatePos.X - ThreatPos.X, 0.0, CandidatePos.Z - ThreatPos.Z);
  if ToCandFlat.LengthSqr < 1e-6 then
    Exit(0.5);
  ToCandFlat := ToCandFlat.Normalize;

  { Dot = +1 in front of threat -> score 0.0; Dot = -1 behind threat -> score 1.0 }
  DotVal := Clamped(TVector3.DotProduct(FlatFwd, ToCandFlat), -1.0, 1.0);
  Result := (1.0 - DotVal) * 0.5;
end;

{ TCastleEqsQueryBehavior ---------------------------------------------------- }

constructor TCastleEqsQueryBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEyeHeightOffset := DefaultEyeHeightOffset;
  FMoveSpeedMps := DefaultMoveSpeedMps;
  FQueryIntervalSec := 0.5;
  FBestCandidateIndex := -1;
  ApplyPreset(epTakeCoverFromThreat);
end;

destructor TCastleEqsQueryBehavior.Destroy;
begin
  SetThreatTransform(nil);
  FreeAndNil(FDebugRoot);
  inherited;
end;

procedure TCastleEqsQueryBehavior.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FThreatTransform) then
    FThreatTransform := nil;
end;

class function TCastleEqsQueryBehavior.PresetDisplayName(const APreset: TEqsPreset): String;
begin
  case APreset of
    epCustom:                    Result := 'Custom EQS Query';
    epTakeCoverFromThreat:       Result := 'Take Cover (LoS Occluded)';
    epSniperLineOfSightVantage:  Result := 'Sniper Vantage (Clear LoS + High Ground)';
    epFlankRearSurround:         Result := 'Rear Flank Surround (180° Arc)';
  end;
end;

procedure TCastleEqsQueryBehavior.ApplyPreset(const APreset: TEqsPreset);
begin
  FPreset := APreset;
  case APreset of
    epTakeCoverFromThreat:
      begin
        FGeneratorShape := egsTacticalGrid;
        FCenterAroundThreat := False;
        FGridHalfExtent := 9.0;
        FGridSpacing := 2.0;
        FMaxWalkableHeightDelta := 1.35;
        FRequireLoSOccludedFromThreat := True;
        FRequireClearLoSToThreat := False;
        FOptimalDistToThreat := 10.0;
        FOptimalDistBandWidth := 9.0;
        FDistanceBandWeight := 1.0;
        FProximityToQuerierWeight := 1.35;
        FElevationBonusWeight := 0.0;
        FRearFlankWeight := 0.0;
      end;
    epSniperLineOfSightVantage:
      begin
        FGeneratorShape := egsTacticalGrid;
        FCenterAroundThreat := False;
        FGridHalfExtent := 12.0;
        FGridSpacing := 2.0;
        FMaxWalkableHeightDelta := 6.5;
        FRequireLoSOccludedFromThreat := False;
        FRequireClearLoSToThreat := True;
        FOptimalDistToThreat := 12.5;
        FOptimalDistBandWidth := 9.5;
        FDistanceBandWeight := 1.0;
        FProximityToQuerierWeight := 0.25;
        FElevationBonusWeight := 2.4;
        FRearFlankWeight := 0.0;
      end;
    epFlankRearSurround:
      begin
        FGeneratorShape := egsConcentricRings;
        FCenterAroundThreat := True;
        FInnerRadius := 3.5;
        FOuterRadius := 7.5;
        FRingCount := 3;
        FPointsPerRing := 12;
        FMaxWalkableHeightDelta := 1.8;
        FRequireLoSOccludedFromThreat := False;
        FRequireClearLoSToThreat := True;
        FOptimalDistToThreat := 5.0;
        FOptimalDistBandWidth := 4.5;
        FDistanceBandWeight := 0.8;
        FProximityToQuerierWeight := 0.20;
        FElevationBonusWeight := 0.0;
        FRearFlankWeight := 2.5;
      end;
    epCustom: ;
  end;
end;

function TCastleEqsQueryBehavior.ProjectCandidateToFloor(
  const CandidateXZ: TVector3; const BaseFloorY: Single;
  out OutGroundedPos: TVector3): Boolean;
const
  ProbeTopHeight = 12.0;
var
  RayHit: TRayCollision;
  SavedPickQ, SavedPickT: Boolean;
  HitY: Single;
begin
  OutGroundedPos := Vector3(CandidateXZ.X, BaseFloorY, CandidateXZ.Z);
  if (Parent = nil) or (Parent.World = nil) then
    Exit(True);

  SavedPickQ := Parent.Pickable;
  Parent.Pickable := False;
  SavedPickT := False;
  if FThreatTransform <> nil then
  begin
    SavedPickT := FThreatTransform.Pickable;
    FThreatTransform.Pickable := False;
  end;
  try
    RayHit := Parent.World.WorldRay(
      Vector3(CandidateXZ.X, BaseFloorY + ProbeTopHeight, CandidateXZ.Z),
      Vector3(0.0, -1.0, 0.0));
    if RayHit <> nil then
    try
      if (RayHit.Transform <> nil) and (RayHit.Distance <= ProbeTopHeight + 8.0) then
      begin
        HitY := (BaseFloorY + ProbeTopHeight) - RayHit.Distance;
        if Abs(HitY - BaseFloorY) > FMaxWalkableHeightDelta then
          Exit(False);
        OutGroundedPos := Vector3(CandidateXZ.X, HitY, CandidateXZ.Z);
        Exit(True);
      end;
    finally
      FreeAndNil(RayHit);
    end;
  finally
    Parent.Pickable := SavedPickQ;
    if FThreatTransform <> nil then
      FThreatTransform.Pickable := SavedPickT;
  end;

  Result := False;
end;

function TCastleEqsQueryBehavior.CheckClearLineOfSight(
  const FromEyeW, ToTargetEyeW: TVector3): Boolean;
var
  Delta, Dir: TVector3;
  FullDist: Single;
  RayHit: TRayCollision;
  SavedPickQ, SavedPickT: Boolean;
begin
  if (Parent = nil) or (Parent.World = nil) then
    Exit(True);

  Delta := ToTargetEyeW - FromEyeW;
  FullDist := Delta.Length;
  if FullDist < 0.15 then
    Exit(True);
  Dir := Delta / FullDist;

  SavedPickQ := Parent.Pickable;
  Parent.Pickable := False;
  SavedPickT := False;
  if FThreatTransform <> nil then
  begin
    SavedPickT := FThreatTransform.Pickable;
    FThreatTransform.Pickable := False;
  end;
  try
    RayHit := Parent.World.WorldRay(FromEyeW, Dir);
    if RayHit <> nil then
    try
      { Any solid obstacle hit closer than FullDist - 0.15 occludes Line of Sight }
      if (RayHit.Transform <> nil) and (RayHit.Distance < FullDist - 0.15) then
        Exit(False);
    finally
      FreeAndNil(RayHit);
    end;
  finally
    Parent.Pickable := SavedPickQ;
    if FThreatTransform <> nil then
      FThreatTransform.Pickable := SavedPickT;
  end;

  Result := True;
end;

function TCastleEqsQueryBehavior.RunQuery: Boolean;
var
  QuerierPos, ThreatPos, ThreatFwd, CenterPos, GroundedPos: TVector3;
  QuerierFloorY, ThreatFloorY, R, Ang, StepXZ, XOff, ZOff: Single;
  RawPoints: array of TVector3;
  RingIdx, PtIdx, StepsCount, GX, GZ, I: Integer;
  DistThreat, DistQuerier, MaxDistQ, RawS, MinRaw, MaxRaw: Single;
  ClearLoS, OnFloor: Boolean;
begin
  FCandidates := nil;
  FHasValidBestSpot := False;
  FBestCandidateIndex := -1;
  FBestWorldPos := TVector3.Zero;
  FBestScore := 0.0;

  if Parent = nil then
    Exit(False);

  QuerierPos := Parent.Translation;
  QuerierFloorY := Max(0.0, QuerierPos.Y - 0.90);
  if FThreatTransform <> nil then
  begin
    ThreatPos := FThreatTransform.Translation;
    ThreatFloorY := Max(0.0, ThreatPos.Y - 0.90);
    ThreatFwd := RotatePointAroundAxis(FThreatTransform.Rotation, Vector3(0.0, 0.0, -1.0)).Normalize;
  end else
  begin
    ThreatPos := QuerierPos + Vector3(0.0, 0.0, -10.0);
    ThreatFloorY := QuerierFloorY;
    ThreatFwd := Vector3(0.0, 0.0, 1.0);
  end;

  if FCenterAroundThreat then
    CenterPos := ThreatPos
  else
    CenterPos := QuerierPos;

  { 1. Generate raw XZ sample coordinates }
  RawPoints := nil;
  case FGeneratorShape of
    egsConcentricRings:
      begin
        for RingIdx := 0 to Max(1, FRingCount) - 1 do
        begin
          if FRingCount <= 1 then
            R := FOuterRadius
          else
            R := Lerp(RingIdx / (FRingCount - 1), FInnerRadius, FOuterRadius);
          for PtIdx := 0 to Max(4, FPointsPerRing) - 1 do
          begin
            Ang := (2.0 * Pi * PtIdx) / Max(4, FPointsPerRing);
            SetLength(RawPoints, Length(RawPoints) + 1);
            RawPoints[High(RawPoints)] := Vector3(
              CenterPos.X + Cos(Ang) * R, QuerierFloorY, CenterPos.Z + Sin(Ang) * R);
          end;
        end;
      end;
    egsTacticalGrid:
      begin
        StepXZ := Max(0.5, FGridSpacing);
        StepsCount := Max(1, Round(FGridHalfExtent / StepXZ));
        for GZ := -StepsCount to StepsCount do
          for GX := -StepsCount to StepsCount do
          begin
            XOff := GX * StepXZ;
            ZOff := GZ * StepXZ;
            SetLength(RawPoints, Length(RawPoints) + 1);
            RawPoints[High(RawPoints)] := Vector3(
              CenterPos.X + XOff, QuerierFloorY, CenterPos.Z + ZOff);
          end;
      end;
  end;

  SetLength(FCandidates, Length(RawPoints));
  MaxDistQ := Max(2.0, FGridHalfExtent * 1.8);
  if FGeneratorShape = egsConcentricRings then
    MaxDistQ := Max(MaxDistQ, (QuerierPos - CenterPos).Length + FOuterRadius);

  MinRaw := MaxSingle;
  MaxRaw := -MaxSingle;

  { 2. Filter & score each candidate }
  for I := 0 to High(RawPoints) do
  begin
    OnFloor := ProjectCandidateToFloor(RawPoints[I], QuerierFloorY, GroundedPos);
    FCandidates[I].WorldPos := GroundedPos;
    FCandidates[I].FilteredOut := False;
    FCandidates[I].RawScore := 0.0;
    FCandidates[I].NormalizedScore := 0.0;
    FCandidates[I].RejectReason := '';

    if not OnFloor then
    begin
      FCandidates[I].FilteredOut := True;
      FCandidates[I].RejectReason := 'Unwalkable/WallTop';
      Continue;
    end;

    ClearLoS := CheckClearLineOfSight(
      GroundedPos + Vector3(0.0, FEyeHeightOffset, 0.0),
      Vector3(ThreatPos.X, ThreatFloorY + FEyeHeightOffset, ThreatPos.Z));
    FCandidates[I].HasClearLoSToThreat := ClearLoS;

    if FRequireLoSOccludedFromThreat and ClearLoS then
    begin
      FCandidates[I].FilteredOut := True;
      FCandidates[I].RejectReason := 'ExposedToThreatLoS';
      Continue;
    end;

    if FRequireClearLoSToThreat and (not ClearLoS) then
    begin
      FCandidates[I].FilteredOut := True;
      FCandidates[I].RejectReason := 'BlockedLoSToThreat';
      Continue;
    end;

    DistThreat := Vector3(GroundedPos.X - ThreatPos.X, 0.0, GroundedPos.Z - ThreatPos.Z).Length;
    DistQuerier := Vector3(GroundedPos.X - QuerierPos.X, 0.0, GroundedPos.Z - QuerierPos.Z).Length;

    RawS := 0.0;
    if FDistanceBandWeight > 0.0 then
      RawS := RawS + FDistanceBandWeight *
        EvaluateDistanceBandScore(DistThreat, FOptimalDistToThreat, FOptimalDistBandWidth);

    if FProximityToQuerierWeight > 0.0 then
      RawS := RawS + FProximityToQuerierWeight *
        Clamped(1.0 - (DistQuerier / MaxDistQ), 0.0, 1.0);

    if FElevationBonusWeight > 0.0 then
      RawS := RawS + FElevationBonusWeight *
        Clamped((GroundedPos.Y - ThreatFloorY) / 4.0, -0.5, 1.5);

    if FRearFlankWeight > 0.0 then
      RawS := RawS + FRearFlankWeight *
        EvaluateFlankRearScore(ThreatPos, ThreatFwd, GroundedPos);

    FCandidates[I].RawScore := RawS;
    MinRaw := Min(MinRaw, RawS);
    MaxRaw := Max(MaxRaw, RawS);
  end;

  { 3. Normalize valid candidate scores into [0..1] and pick winner }
  for I := 0 to High(FCandidates) do
    if not FCandidates[I].FilteredOut then
    begin
      if MaxRaw > MinRaw + 1e-5 then
        FCandidates[I].NormalizedScore :=
          (FCandidates[I].RawScore - MinRaw) / (MaxRaw - MinRaw)
      else
        FCandidates[I].NormalizedScore := 1.0;

      if (not FHasValidBestSpot) or (FCandidates[I].RawScore > FBestScore) then
      begin
        FHasValidBestSpot := True;
        FBestScore := FCandidates[I].RawScore;
        FBestCandidateIndex := I;
        FBestWorldPos := FCandidates[I].WorldPos;
      end;
    end;

  if FShowDebugSpheres then
    RebuildDebugSpheres;

  Result := FHasValidBestSpot;
end;

procedure TCastleEqsQueryBehavior.RebuildDebugSpheres;
var
  I: Integer;
  Sph: TCastleSphere;
  S: Single;
begin
  FreeAndNil(FDebugRoot);
  if (not FShowDebugSpheres) or (Parent = nil) or (Parent.World = nil) then
    Exit;

  FDebugRoot := TCastleTransform.Create(Self);
  FDebugRoot.SetTransient;
  FDebugRoot.Pickable := False;
  FDebugRoot.Collides := False;
  Parent.World.Add(FDebugRoot);

  for I := 0 to High(FCandidates) do
  begin
    if FCandidates[I].FilteredOut then
      Continue;
    Sph := TCastleSphere.Create(FDebugRoot);
    Sph.SetTransient;
    Sph.Pickable := False;
    Sph.Collides := False;
    S := FCandidates[I].NormalizedScore;
    if I = FBestCandidateIndex then
    begin
      Sph.Radius := 0.28;
      Sph.Color := Vector4(0.18, 0.96, 0.48, 1.0);
    end else
    begin
      Sph.Radius := 0.16;
      Sph.Color := Vector4(Lerp(S, 0.92, 0.22), Lerp(S, 0.36, 0.84), 0.24, 1.0);
    end;
    Sph.Translation := FCandidates[I].WorldPos + Vector3(0.0, 0.25, 0.0);
    FDebugRoot.Add(Sph);
  end;
end;

procedure TCastleEqsQueryBehavior.StepEqsAgent(const Dt: Single);
var
  DeltaFlat: TVector3;
  Dist, MaxStep: Single;
begin
  if (Parent = nil) or (Dt <= 0.0) then
    Exit;

  FQueryAccumulatorSec := FQueryAccumulatorSec + Dt;
  if (not FHasValidBestSpot) or (FQueryAccumulatorSec >= Max(0.05, FQueryIntervalSec)) then
  begin
    FQueryAccumulatorSec := 0.0;
    RunQuery;
  end;

  if FAutoMoveToBestSpot and FHasValidBestSpot then
  begin
    DeltaFlat := Vector3(
      FBestWorldPos.X - Parent.Translation.X,
      0.0,
      FBestWorldPos.Z - Parent.Translation.Z);
    Dist := DeltaFlat.Length;
    if Dist > 0.03 then
    begin
      MaxStep := Min(Dist, FMoveSpeedMps * Dt);
      Parent.Translation := Vector3(
        Parent.Translation.X + (DeltaFlat.X / Dist) * MaxStep,
        FBestWorldPos.Y + 0.90,
        Parent.Translation.Z + (DeltaFlat.Z / Dist) * MaxStep);
    end;
  end;
end;

procedure TCastleEqsQueryBehavior.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleApplicationMode = appRunning then
    StepEqsAgent(SecondsPassed);
end;

function TCastleEqsQueryBehavior.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'GeneratorShape') or
     (PropertyName = 'ThreatTransform') or
     (PropertyName = 'RequireLoSOccludedFromThreat') or
     (PropertyName = 'RequireClearLoSToThreat') or
     (PropertyName = 'OptimalDistToThreat') or
     (PropertyName = 'ShowDebugSpheres') or
     (PropertyName = 'AutoMoveToBestSpot') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleEqsQueryBehavior.CandidateCount: Integer;
begin
  Result := Length(FCandidates);
end;

function TCastleEqsQueryBehavior.ValidCandidateCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FCandidates) do
    if not FCandidates[I].FilteredOut then
      Inc(Result);
end;

function TCastleEqsQueryBehavior.GetCandidate(const Index: Integer): TEqsCandidateItem;
begin
  Result := FCandidates[Clamped(Index, 0, Max(0, High(FCandidates)))];
end;

function TCastleEqsQueryBehavior.EqsSummaryBadge: String;
begin
  Result := Format('[EQS:%s %d/%d valid]', [
    PresetDisplayName(FPreset), ValidCandidateCount, CandidateCount]);
end;

procedure TCastleEqsQueryBehavior.SetPreset(const Value: TEqsPreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

procedure TCastleEqsQueryBehavior.SetThreatTransform(const Value: TCastleTransform);
begin
  if FThreatTransform <> Value then
  begin
    if FThreatTransform <> nil then
      FThreatTransform.RemoveFreeNotification(Self);
    FThreatTransform := Value;
    if FThreatTransform <> nil then
      FThreatTransform.FreeNotification(Self);
  end;
end;

procedure TCastleEqsQueryBehavior.SetShowDebugSpheres(const Value: Boolean);
begin
  if FShowDebugSpheres <> Value then
  begin
    FShowDebugSpheres := Value;
    RebuildDebugSpheres;
  end;
end;

function TCastleEqsQueryBehavior.GetConfigJson: String;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('shape', Ord(FGeneratorShape));
    Root.Add('aroundThreat', FCenterAroundThreat);
    Root.Add('innerR', FInnerRadius);
    Root.Add('outerR', FOuterRadius);
    Root.Add('rings', FRingCount);
    Root.Add('ptsPerRing', FPointsPerRing);
    Root.Add('gridHalf', FGridHalfExtent);
    Root.Add('gridStep', FGridSpacing);
    Root.Add('occluded', FRequireLoSOccludedFromThreat);
    Root.Add('clearLoS', FRequireClearLoSToThreat);
    Root.Add('optDist', FOptimalDistToThreat);
    Root.Add('elevW', FElevationBonusWeight);
    Root.Add('flankW', FRearFlankWeight);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleEqsQueryBehavior.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root: TJSONObject;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FPreset := TEqsPreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TEqsPreset))));
      FGeneratorShape := TEqsGeneratorShape(Clamped(Root.Get('shape', Ord(FGeneratorShape)),
        0, Ord(High(TEqsGeneratorShape))));
      FCenterAroundThreat := Root.Get('aroundThreat', FCenterAroundThreat);
      FInnerRadius := Max(0.5, Root.Get('innerR', FInnerRadius));
      FOuterRadius := Max(FInnerRadius + 0.5, Root.Get('outerR', FOuterRadius));
      FRingCount := Max(1, Root.Get('rings', FRingCount));
      FPointsPerRing := Max(4, Root.Get('ptsPerRing', FPointsPerRing));
      FGridHalfExtent := Max(1.0, Root.Get('gridHalf', FGridHalfExtent));
      FGridSpacing := Max(0.5, Root.Get('gridStep', FGridSpacing));
      FRequireLoSOccludedFromThreat := Root.Get('occluded', FRequireLoSOccludedFromThreat);
      FRequireClearLoSToThreat := Root.Get('clearLoS', FRequireClearLoSToThreat);
      FOptimalDistToThreat := Max(0.5, Root.Get('optDist', FOptimalDistToThreat));
      FElevationBonusWeight := Root.Get('elevW', FElevationBonusWeight);
      FRearFlankWeight := Root.Get('flankW', FRearFlankWeight);
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleEqsQueryBehavior,
    ['AI & Gameplay', 'EQS Tactical Spatial Query (Cover / Vantage / Flank)']);
end.
