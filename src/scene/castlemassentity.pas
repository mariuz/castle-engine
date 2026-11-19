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

{ MassEntity-Style Data-Oriented Structure-of-Arrays (SoA) Crowd Simulation,
  Zero-Allocation Spatial Hash Grid, Dijkstra Obstacle Flow-Field, 4-Tier
  Representation LOD & Single-Draw-Call Batched Swarm Mesh Runtime
  (@link(TCastleMassEntityManager))
  (Phase 328 — UE 6.0+ MassEntity & MassCrowd Parity). }
unit CastleMassEntity;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleScene, X3DNodes;

type
  { Built-in MassEntity swarm presets. }
  TMassSwarmPreset = (
    mspCustom,
    mspCityPedestrianFlow,
    mspBoidsMurmurationSwarm,
    mspSiegeInfantryCharge
  );

  { 4-tier UE MassRepresentation LOD classification by viewer distance. }
  TMassRepresentationTier = (
    mrtHighMesh,
    mrtMediumProxy,
    mrtLowBatchedPoint,
    mrtCulledOffscreen
  );

  { Circular XZ obstacle baked into the MassEntity flow field & hard collision pushout. }
  TMassCircularObstacle = record
    CenterX: Single;
    CenterZ: Single;
    Radius: Single;
  end;
  TMassCircularObstacleArray = array of TMassCircularObstacle;

  { Read-only snapshot of a single SoA entity for UI / unit-test inspection. }
  TMassEntitySnapshot = record
    PosX, PosY, PosZ: Single;
    VelX, VelZ: Single;
    HeadingRad: Single;
    LodTier: TMassRepresentationTier;
  end;

  { Data-oriented Structure-of-Arrays (SoA) crowd & swarm manager (@link(TCastleTransform))
    capable of stepping 1,000+ entities with O(1) spatial-hash neighbor queries,
    Dijkstra obstacle-avoiding goal flow fields, 4-tier viewer representation LODs,
    and single-draw-call @code(csTransient) X3D triangle batching. }
  TCastleMassEntityManager = class(TCastleTransform)
  public
    const
      DefaultEntityCount = 250;
      DefaultArenaHalfExtent = 24.0;
      DefaultSeparationRadius = 1.15;
      DefaultNeighborRadius = 3.50;
      DefaultSeparationWeight = 2.60;
      DefaultAlignmentWeight = 0.65;
      DefaultCohesionWeight = 0.35;
      DefaultGoalFlowWeight = 2.10;
      DefaultBaseSpeedMps = 3.20;
      DefaultHighMeshDist = 14.0;
      DefaultMediumProxyDist = 32.0;
      DefaultCullDist = 75.0;
      FlowGridResolution = 32;
      SpatialHashBuckets = 2048; // Power of 2
  strict private
    FPreset: TMassSwarmPreset;
    FTargetEntityCount: Integer;
    FArenaHalfExtent: Single;
    FSeparationRadius: Single;
    FNeighborRadius: Single;
    FSeparationWeight: Single;
    FAlignmentWeight: Single;
    FCohesionWeight: Single;
    FGoalFlowWeight: Single;
    FBaseSpeedMps: Single;
    FGoalPosXZ: TVector2;
    FGoalPosXZPersistent: TCastleVector2Persistent;
    FHighMeshDist: Single;
    FMediumProxyDist: Single;
    FCullDist: Single;
    FRandomSeed: Cardinal;
    FBuildVisualBatch: Boolean;
    FSimulateInEditor: Boolean;

    { Structure-of-Arrays (SoA) contiguous entity buffers }
    FCount: Integer;
    FPosX: array of Single;
    FPosY: array of Single;
    FPosZ: array of Single;
    FVelX: array of Single;
    FVelZ: array of Single;
    FHeadingRad: array of Single;
    FDesiredSpeed: array of Single;
    FLodTier: array of TMassRepresentationTier;
    FTierCounts: array [TMassRepresentationTier] of Integer;

    { Zero-allocation O(1) Spatial Hash Grid }
    FHashHead: array [0..SpatialHashBuckets - 1] of Integer;
    FHashNext: array of Integer;

    { Circular obstacles & 32x32 Dijkstra Goal Flow Field }
    FObstacles: TMassCircularObstacleArray;
    FFlowBlocked: array [0..FlowGridResolution - 1, 0..FlowGridResolution - 1] of Boolean;
    FFlowCost: array [0..FlowGridResolution - 1, 0..FlowGridResolution - 1] of Single;
    FFlowDirX: array [0..FlowGridResolution - 1, 0..FlowGridResolution - 1] of Single;
    FFlowDirZ: array [0..FlowGridResolution - 1, 0..FlowGridResolution - 1] of Single;
    FFlowDirty: Boolean;

    { Single-draw-call transient visual mesh }
    FBatchScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FLastStepTimeMs: Double;

    procedure SetPreset(const Value: TMassSwarmPreset);
    procedure SetTargetEntityCount(const Value: Integer);
    procedure SetArenaHalfExtent(const Value: Single);
    procedure SetGoalPosXZ(const Value: TVector2);
    function GetGoalPosXZForPersistent: TVector2;
    procedure SetGoalPosXZForPersistent(const AValue: TVector2);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    function HashCell(const CX, CZ: Integer): Integer; inline;
    procedure RebuildSpatialHash(const CellSize: Single);
    procedure RebuildVisualBatchMesh;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TMassSwarmPreset): String; static;

    procedure ApplyPreset(const APreset: TMassSwarmPreset);

    { Respawn @code(TargetEntityCount) SoA entities deterministically in @code(SpawnBoxMinXZ..SpawnBoxMaxXZ). }
    procedure RespawnEntitiesInBox(const SpawnMinXZ, SpawnMaxXZ: TVector2);
    procedure RespawnDefaultArena;

    procedure ClearObstacles;
    procedure AddObstacleCircleXZ(const ACenterX, ACenterZ, ARadius: Single);
    function ObstacleCount: Integer;
    function GetObstacle(const Index: Integer): TMassCircularObstacle;

    { Bake the 32x32 Dijkstra wave-propagation flow field toward @link(GoalPosXZ)
      routing smoothly around all registered circular obstacles. }
    procedure BakeGoalFlowField;
    function SampleFlowDirectionXZ(const WorldX, WorldZ: Single): TVector2;

    { Classify all entities into 4 UE MassRepresentation LOD tiers relative to @code(ViewerPos). }
    procedure UpdateRepresentationLods(const ViewerPos: TVector3);

    { Advance all SoA entities by @code(Dt) seconds using O(1) spatial hash separation,
      alignment, cohesion, Dijkstra flow-field steering, and hard obstacle pushout. }
    procedure StepSwarm(const Dt: Single);

    function ActiveEntityCount: Integer;
    function GetEntitySnapshot(const Index: Integer): TMassEntitySnapshot;
    function GetTierCount(const ATier: TMassRepresentationTier): Integer;
    function MeanPositionXZ: TVector2;
    function SwarmSummaryBadge: String;

    property GoalPosXZ: TVector2 read FGoalPosXZ write SetGoalPosXZ;
    property LastStepTimeMs: Double read FLastStepTimeMs;
  published
    property Preset: TMassSwarmPreset
      read FPreset write SetPreset default mspCityPedestrianFlow;
    property TargetEntityCount: Integer
      read FTargetEntityCount write SetTargetEntityCount default DefaultEntityCount;
    property ArenaHalfExtent: Single
      read FArenaHalfExtent write SetArenaHalfExtent {$ifdef FPC}default DefaultArenaHalfExtent{$endif};
    property SeparationRadius: Single
      read FSeparationRadius write FSeparationRadius {$ifdef FPC}default DefaultSeparationRadius{$endif};
    property NeighborRadius: Single
      read FNeighborRadius write FNeighborRadius {$ifdef FPC}default DefaultNeighborRadius{$endif};
    property SeparationWeight: Single
      read FSeparationWeight write FSeparationWeight {$ifdef FPC}default DefaultSeparationWeight{$endif};
    property AlignmentWeight: Single
      read FAlignmentWeight write FAlignmentWeight {$ifdef FPC}default DefaultAlignmentWeight{$endif};
    property CohesionWeight: Single
      read FCohesionWeight write FCohesionWeight {$ifdef FPC}default DefaultCohesionWeight{$endif};
    property GoalFlowWeight: Single
      read FGoalFlowWeight write FGoalFlowWeight {$ifdef FPC}default DefaultGoalFlowWeight{$endif};
    property BaseSpeedMps: Single
      read FBaseSpeedMps write FBaseSpeedMps {$ifdef FPC}default DefaultBaseSpeedMps{$endif};
    property GoalPosXZPersistent: TCastleVector2Persistent read FGoalPosXZPersistent;
    property HighMeshDist: Single
      read FHighMeshDist write FHighMeshDist {$ifdef FPC}default DefaultHighMeshDist{$endif};
    property MediumProxyDist: Single
      read FMediumProxyDist write FMediumProxyDist {$ifdef FPC}default DefaultMediumProxyDist{$endif};
    property CullDist: Single
      read FCullDist write FCullDist {$ifdef FPC}default DefaultCullDist{$endif};
    property RandomSeed: Cardinal read FRandomSeed write FRandomSeed default 1337;
    property BuildVisualBatch: Boolean read FBuildVisualBatch write FBuildVisualBatch default True;
    property SimulateInEditor: Boolean read FSimulateInEditor write FSimulateInEditor default False;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

implementation

uses
  Math, FpJson, JsonParser,
  CastleUtils, CastleTimeUtils, CastleColors, CastleComponentSerialize;

{$PUSH}{$Q-}{$R-}
function NextXorShift32(var State: Cardinal): Single; inline;
begin
  if State = 0 then
    State := 2463534242;
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := (State and $00FFFFFF) / 16777216.0;
end;
{$POP}

{ TCastleMassEntityManager --------------------------------------------------- }

constructor TCastleMassEntityManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FArenaHalfExtent := DefaultArenaHalfExtent;
  FSeparationRadius := DefaultSeparationRadius;
  FNeighborRadius := DefaultNeighborRadius;
  FSeparationWeight := DefaultSeparationWeight;
  FAlignmentWeight := DefaultAlignmentWeight;
  FCohesionWeight := DefaultCohesionWeight;
  FGoalFlowWeight := DefaultGoalFlowWeight;
  FBaseSpeedMps := DefaultBaseSpeedMps;
  FGoalPosXZ := Vector2(0.0, -16.0);
  FHighMeshDist := DefaultHighMeshDist;
  FMediumProxyDist := DefaultMediumProxyDist;
  FCullDist := DefaultCullDist;
  FRandomSeed := 1337;
  FBuildVisualBatch := True;
  FSimulateInEditor := False;
  FFlowDirty := True;

  FGoalPosXZPersistent := TCastleVector2Persistent.Create(nil);
  FGoalPosXZPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetGoalPosXZForPersistent;
  FGoalPosXZPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetGoalPosXZForPersistent;
  FGoalPosXZPersistent.InternalDefaultValue := FGoalPosXZ;

  ApplyPreset(mspCityPedestrianFlow);
end;

destructor TCastleMassEntityManager.Destroy;
begin
  FreeAndNil(FGoalPosXZPersistent);
  inherited;
end;

procedure TCastleMassEntityManager.Loaded;
begin
  inherited;
  if FFlowDirty then
    BakeGoalFlowField;
  if FBuildVisualBatch then
    RebuildVisualBatchMesh;
end;

function TCastleMassEntityManager.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'TargetEntityCount', 'ArenaHalfExtent', 'SeparationRadius',
       'NeighborRadius', 'SeparationWeight', 'AlignmentWeight',
       'CohesionWeight', 'GoalFlowWeight', 'BaseSpeedMps',
       'GoalPosXZPersistent', 'HighMeshDist', 'MediumProxyDist', 'CullDist',
       'RandomSeed', 'BuildVisualBatch', 'SimulateInEditor', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleMassEntityManager.PresetDisplayName(
  const APreset: TMassSwarmPreset): String;
begin
  case APreset of
    mspCustom:                 Result := 'Custom MassEntity Swarm';
    mspCityPedestrianFlow:     Result := 'City Pedestrian Flow (250)';
    mspBoidsMurmurationSwarm:  Result := 'Boids Flock Murmuration (400)';
    mspSiegeInfantryCharge:    Result := 'Siege Infantry Charge (600)';
  end;
end;

procedure TCastleMassEntityManager.SetPreset(const Value: TMassSwarmPreset);
begin
  if FPreset = Value then
    Exit;
  ApplyPreset(Value);
end;

procedure TCastleMassEntityManager.SetTargetEntityCount(const Value: Integer);
var
  ClampedN: Integer;
begin
  ClampedN := Clamped(Value, 1, 20000);
  if FTargetEntityCount = ClampedN then
    Exit;
  FTargetEntityCount := ClampedN;
  RespawnDefaultArena;
end;

procedure TCastleMassEntityManager.SetArenaHalfExtent(const Value: Single);
begin
  FArenaHalfExtent := Clamped(Value, 4.0, 500.0);
  FFlowDirty := True;
end;

procedure TCastleMassEntityManager.SetGoalPosXZ(const Value: TVector2);
begin
  if TVector2.Equals(FGoalPosXZ, Value) then
    Exit;
  FGoalPosXZ := Value;
  FFlowDirty := True;
end;

function TCastleMassEntityManager.GetGoalPosXZForPersistent: TVector2;
begin
  Result := FGoalPosXZ;
end;

procedure TCastleMassEntityManager.SetGoalPosXZForPersistent(const AValue: TVector2);
begin
  GoalPosXZ := AValue;
end;

procedure TCastleMassEntityManager.ApplyPreset(const APreset: TMassSwarmPreset);
begin
  FPreset := APreset;
  case APreset of
    mspCityPedestrianFlow:
      begin
        FTargetEntityCount := 250;
        FBaseSpeedMps := 2.60;
        FSeparationWeight := 2.80;
        FAlignmentWeight := 0.45;
        FCohesionWeight := 0.20;
        FGoalFlowWeight := 2.40;
      end;
    mspBoidsMurmurationSwarm:
      begin
        FTargetEntityCount := 400;
        FBaseSpeedMps := 4.20;
        FSeparationWeight := 2.20;
        FAlignmentWeight := 1.65;
        FCohesionWeight := 1.10;
        FGoalFlowWeight := 1.15;
      end;
    mspSiegeInfantryCharge:
      begin
        FTargetEntityCount := 600;
        FBaseSpeedMps := 5.00;
        FSeparationWeight := 2.50;
        FAlignmentWeight := 0.95;
        FCohesionWeight := 0.45;
        FGoalFlowWeight := 2.85;
      end;
  else
    Exit;
  end;
  RespawnDefaultArena;
end;

procedure TCastleMassEntityManager.ClearObstacles;
begin
  FObstacles := nil;
  FFlowDirty := True;
end;

procedure TCastleMassEntityManager.AddObstacleCircleXZ(
  const ACenterX, ACenterZ, ARadius: Single);
var
  N: Integer;
begin
  N := Length(FObstacles);
  SetLength(FObstacles, N + 1);
  FObstacles[N].CenterX := ACenterX;
  FObstacles[N].CenterZ := ACenterZ;
  FObstacles[N].Radius := Max(0.25, ARadius);
  FFlowDirty := True;
end;

function TCastleMassEntityManager.ObstacleCount: Integer;
begin
  Result := Length(FObstacles);
end;

function TCastleMassEntityManager.GetObstacle(
  const Index: Integer): TMassCircularObstacle;
begin
  if (Index >= 0) and (Index < Length(FObstacles)) then
    Result := FObstacles[Index]
  else
    Result := Default(TMassCircularObstacle);
end;

procedure TCastleMassEntityManager.RespawnEntitiesInBox(
  const SpawnMinXZ, SpawnMaxXZ: TVector2);
var
  Seed: Cardinal;
  I, K: Integer;
  PX, PZ, DX, DZ, Dist, PushR: Single;
begin
  FCount := Max(1, FTargetEntityCount);
  SetLength(FPosX, FCount);
  SetLength(FPosY, FCount);
  SetLength(FPosZ, FCount);
  SetLength(FVelX, FCount);
  SetLength(FVelZ, FCount);
  SetLength(FHeadingRad, FCount);
  SetLength(FDesiredSpeed, FCount);
  SetLength(FLodTier, FCount);
  SetLength(FHashNext, FCount);

  Seed := FRandomSeed;
  if Seed = 0 then
    Seed := 1337;

  for I := 0 to FCount - 1 do
  begin
    PX := SpawnMinXZ.X + NextXorShift32(Seed) * (SpawnMaxXZ.X - SpawnMinXZ.X);
    PZ := SpawnMinXZ.Y + NextXorShift32(Seed) * (SpawnMaxXZ.Y - SpawnMinXZ.Y);

    for K := 0 to High(FObstacles) do
    begin
      DX := PX - FObstacles[K].CenterX;
      DZ := PZ - FObstacles[K].CenterZ;
      Dist := Hypot(DX, DZ);
      PushR := FObstacles[K].Radius + 0.45;
      if Dist < PushR then
      begin
        if Dist < 1e-4 then
        begin
          DX := 1.0;
          DZ := 0.0;
          Dist := 1.0;
        end;
        PX := FObstacles[K].CenterX + (DX / Dist) * PushR;
        PZ := FObstacles[K].CenterZ + (DZ / Dist) * PushR;
      end;
    end;

    FPosX[I] := PX;
    FPosY[I] := 0.0;
    FPosZ[I] := PZ;
    FVelX[I] := 0.0;
    FVelZ[I] := -FBaseSpeedMps * 0.25;
    FHeadingRad[I] := 0.0;
    FDesiredSpeed[I] := FBaseSpeedMps * (0.88 + 0.24 * NextXorShift32(Seed));
    FLodTier[I] := mrtHighMesh;
  end;

  FTierCounts[mrtHighMesh] := FCount;
  FTierCounts[mrtMediumProxy] := 0;
  FTierCounts[mrtLowBatchedPoint] := 0;
  FTierCounts[mrtCulledOffscreen] := 0;

  if FBuildVisualBatch then
    RebuildVisualBatchMesh;
end;

procedure TCastleMassEntityManager.RespawnDefaultArena;
var
  Span: Single;
begin
  Span := FArenaHalfExtent * 0.70;
  RespawnEntitiesInBox(Vector2(-Span, 4.0), Vector2(Span, Span));
end;

procedure TCastleMassEntityManager.BakeGoalFlowField;
const
  InfCost = 1e20;
  Neighbors8: array [0..7, 0..1] of Integer = (
    (-1, 0), (1, 0), (0, -1), (0, 1),
    (-1, -1), (1, -1), (-1, 1), (1, 1)
  );
var
  CellSpan, WX, WZ, StepCost, CandCost, CLeft, CRight, CDown, CUp, GX, GZ, GLen: Single;
  IX, IZ, K, GoalIX, GoalIZ, CurX, CurZ, NX, NZ, D: Integer;
  Changed: Boolean;
begin
  CellSpan := (2.0 * FArenaHalfExtent) / FlowGridResolution;

  { 1. Rasterize circular obstacles into blocked cells (with 0.5m agent inflation) }
  for IZ := 0 to FlowGridResolution - 1 do
    for IX := 0 to FlowGridResolution - 1 do
    begin
      WX := -FArenaHalfExtent + (IX + 0.5) * CellSpan;
      WZ := -FArenaHalfExtent + (IZ + 0.5) * CellSpan;
      FFlowBlocked[IX, IZ] := False;
      for K := 0 to High(FObstacles) do
        if Sqr(WX - FObstacles[K].CenterX) + Sqr(WZ - FObstacles[K].CenterZ) <=
           Sqr(FObstacles[K].Radius + 0.45) then
        begin
          FFlowBlocked[IX, IZ] := True;
          Break;
        end;
      FFlowCost[IX, IZ] := InfCost;
    end;

  GoalIX := Clamped(Floor(((FGoalPosXZ.X + FArenaHalfExtent) / (2.0 * FArenaHalfExtent)) * FlowGridResolution),
    0, FlowGridResolution - 1);
  GoalIZ := Clamped(Floor(((FGoalPosXZ.Y + FArenaHalfExtent) / (2.0 * FArenaHalfExtent)) * FlowGridResolution),
    0, FlowGridResolution - 1);
  FFlowBlocked[GoalIX, GoalIZ] := False;
  FFlowCost[GoalIX, GoalIZ] := 0.0;

  { 2. Iterative 8-connected Bellman-Ford / Eikonal relaxation on 32x32 grid }
  repeat
    Changed := False;
    for IZ := 0 to FlowGridResolution - 1 do
      for IX := 0 to FlowGridResolution - 1 do
        if (not FFlowBlocked[IX, IZ]) and (FFlowCost[IX, IZ] < InfCost * 0.5) then
        begin
          CurX := IX;
          CurZ := IZ;
          for D := 0 to 7 do
          begin
            NX := CurX + Neighbors8[D, 0];
            NZ := CurZ + Neighbors8[D, 1];
            if (NX < 0) or (NX >= FlowGridResolution) or
               (NZ < 0) or (NZ >= FlowGridResolution) or
               FFlowBlocked[NX, NZ] then
              Continue;
            if D < 4 then
              StepCost := CellSpan
            else
              StepCost := CellSpan * 1.41421356;
            CandCost := FFlowCost[CurX, CurZ] + StepCost;
            if CandCost + 1e-4 < FFlowCost[NX, NZ] then
            begin
              FFlowCost[NX, NZ] := CandCost;
              Changed := True;
            end;
          end;
        end;
  until not Changed;

  { 3. Compute negative gradient (-dCost/dX, -dCost/dZ) flow vectors }
  for IZ := 0 to FlowGridResolution - 1 do
    for IX := 0 to FlowGridResolution - 1 do
    begin
      if FFlowBlocked[IX, IZ] then
      begin
        WX := -FArenaHalfExtent + (IX + 0.5) * CellSpan;
        WZ := -FArenaHalfExtent + (IZ + 0.5) * CellSpan;
        GX := FGoalPosXZ.X - WX;
        GZ := FGoalPosXZ.Y - WZ;
      end else
      begin
        CLeft := FFlowCost[Max(0, IX - 1), IZ];
        if CLeft >= InfCost * 0.5 then CLeft := FFlowCost[IX, IZ];
        CRight := FFlowCost[Min(FlowGridResolution - 1, IX + 1), IZ];
        if CRight >= InfCost * 0.5 then CRight := FFlowCost[IX, IZ];
        CDown := FFlowCost[IX, Max(0, IZ - 1)];
        if CDown >= InfCost * 0.5 then CDown := FFlowCost[IX, IZ];
        CUp := FFlowCost[IX, Min(FlowGridResolution - 1, IZ + 1)];
        if CUp >= InfCost * 0.5 then CUp := FFlowCost[IX, IZ];
        GX := CLeft - CRight;
        GZ := CDown - CUp;
      end;
      GLen := Hypot(GX, GZ);
      if GLen > 1e-5 then
      begin
        FFlowDirX[IX, IZ] := GX / GLen;
        FFlowDirZ[IX, IZ] := GZ / GLen;
      end else
      begin
        FFlowDirX[IX, IZ] := 0.0;
        FFlowDirZ[IX, IZ] := 0.0;
      end;
    end;

  FFlowDirty := False;
end;

function TCastleMassEntityManager.SampleFlowDirectionXZ(
  const WorldX, WorldZ: Single): TVector2;
var
  IX, IZ: Integer;
  DirectGoal: TVector2;
begin
  if FFlowDirty then
    BakeGoalFlowField;

  DirectGoal := Vector2(FGoalPosXZ.X - WorldX, FGoalPosXZ.Y - WorldZ);
  if DirectGoal.Length < 1.25 then
  begin
    if DirectGoal.Length > 1e-4 then
      Exit(DirectGoal.Normalize)
    else
      Exit(TVector2.Zero);
  end;

  IX := Clamped(Floor(((WorldX + FArenaHalfExtent) / (2.0 * FArenaHalfExtent)) * FlowGridResolution),
    0, FlowGridResolution - 1);
  IZ := Clamped(Floor(((WorldZ + FArenaHalfExtent) / (2.0 * FArenaHalfExtent)) * FlowGridResolution),
    0, FlowGridResolution - 1);
  Result := Vector2(FFlowDirX[IX, IZ], FFlowDirZ[IX, IZ]);
  if Result.Length <= 1e-4 then
    Result := DirectGoal.Normalize;
end;

{$PUSH}{$Q-}{$R-}
function TCastleMassEntityManager.HashCell(const CX, CZ: Integer): Integer;
begin
  Result := Integer(((Cardinal(CX) * Cardinal(73856093)) xor (Cardinal(CZ) * Cardinal(19349663))) and
    Cardinal(SpatialHashBuckets - 1));
end;
{$POP}

procedure TCastleMassEntityManager.RebuildSpatialHash(const CellSize: Single);
var
  I, CX, CZ, Bucket: Integer;
  InvCell: Single;
begin
  for I := 0 to SpatialHashBuckets - 1 do
    FHashHead[I] := -1;
  if Length(FHashNext) < FCount then
    SetLength(FHashNext, FCount);

  InvCell := 1.0 / Max(0.25, CellSize);
  for I := 0 to FCount - 1 do
  begin
    CX := Floor(FPosX[I] * InvCell);
    CZ := Floor(FPosZ[I] * InvCell);
    Bucket := HashCell(CX, CZ);
    FHashNext[I] := FHashHead[Bucket];
    FHashHead[Bucket] := I;
  end;
end;

procedure TCastleMassEntityManager.StepSwarm(const Dt: Single);
var
  StepTimer: TTimerResult;
  SafeDt, CellSize, InvCell, SepRadSq, NeighRadSq: Single;
  I, J, K, CX, CZ, DXCell, DZCell, Bucket, NeighCount: Integer;
  PX, PZ, DX, DZ, DistSq, Dist, InvDist: Single;
  SepX, SepZ, AlignX, AlignZ, CohX, CohZ, SteerX, SteerZ, SteerLen, MaxSpd, ObsR: Single;
  FlowDir: TVector2;
begin
  SafeDt := Clamped(Dt, 0.0, 0.20);
  if (SafeDt <= 0.0) or (FCount <= 0) then
    Exit;

  StepTimer := Timer;
  if FFlowDirty then
    BakeGoalFlowField;

  CellSize := Max(FSeparationRadius, FNeighborRadius);
  InvCell := 1.0 / Max(0.25, CellSize);
  SepRadSq := Sqr(Max(0.20, FSeparationRadius));
  NeighRadSq := Sqr(Max(FSeparationRadius, FNeighborRadius));

  RebuildSpatialHash(CellSize);

  for I := 0 to FCount - 1 do
  begin
    PX := FPosX[I];
    PZ := FPosZ[I];
    CX := Floor(PX * InvCell);
    CZ := Floor(PZ * InvCell);

    SepX := 0.0;
    SepZ := 0.0;
    AlignX := 0.0;
    AlignZ := 0.0;
    CohX := 0.0;
    CohZ := 0.0;
    NeighCount := 0;

    { O(1) 3x3 Spatial Hash Neighborhood Query }
    for DZCell := -1 to 1 do
      for DXCell := -1 to 1 do
      begin
        Bucket := HashCell(CX + DXCell, CZ + DZCell);
        J := FHashHead[Bucket];
        while J >= 0 do
        begin
          if J <> I then
          begin
            DX := PX - FPosX[J];
            DZ := PZ - FPosZ[J];
            DistSq := DX * DX + DZ * DZ;
            if DistSq < NeighRadSq then
            begin
              Inc(NeighCount);
              AlignX := AlignX + FVelX[J];
              AlignZ := AlignZ + FVelZ[J];
              CohX := CohX + FPosX[J];
              CohZ := CohZ + FPosZ[J];

              if DistSq < SepRadSq then
              begin
                if DistSq < 1e-6 then
                begin
                  SepX := SepX + ((I and 1) * 2 - 1) * 1.0;
                  SepZ := SepZ + (((I shr 1) and 1) * 2 - 1) * 1.0;
                end else
                begin
                  Dist := Sqrt(DistSq);
                  InvDist := (FSeparationRadius - Dist) / (Dist * FSeparationRadius);
                  SepX := SepX + DX * InvDist;
                  SepZ := SepZ + DZ * InvDist;
                end;
              end;
            end;
          end;
          J := FHashNext[J];
        end;
      end;

    if NeighCount > 0 then
    begin
      AlignX := (AlignX / NeighCount) - FVelX[I];
      AlignZ := (AlignZ / NeighCount) - FVelZ[I];
      CohX := (CohX / NeighCount) - PX;
      CohZ := (CohZ / NeighCount) - PZ;
    end;

    SteerLen := Hypot(SepX, SepZ);
    if SteerLen > 1.25 then
    begin
      SepX := (SepX / SteerLen) * 1.25;
      SepZ := (SepZ / SteerLen) * 1.25;
    end;

    FlowDir := SampleFlowDirectionXZ(PX, PZ);
    MaxSpd := FDesiredSpeed[I];

    SteerX :=
      SepX * FSeparationWeight * MaxSpd +
      AlignX * FAlignmentWeight +
      CohX * FCohesionWeight +
      FlowDir.X * MaxSpd * FGoalFlowWeight;
    SteerZ :=
      SepZ * FSeparationWeight * MaxSpd +
      AlignZ * FAlignmentWeight +
      CohZ * FCohesionWeight +
      FlowDir.Y * MaxSpd * FGoalFlowWeight;

    FVelX[I] := FVelX[I] + (SteerX - FVelX[I]) * Min(1.0, 6.5 * SafeDt);
    FVelZ[I] := FVelZ[I] + (SteerZ - FVelZ[I]) * Min(1.0, 6.5 * SafeDt);

    SteerLen := Hypot(FVelX[I], FVelZ[I]);
    if SteerLen > MaxSpd then
    begin
      FVelX[I] := (FVelX[I] / SteerLen) * MaxSpd;
      FVelZ[I] := (FVelZ[I] / SteerLen) * MaxSpd;
    end;

    PX := PX + FVelX[I] * SafeDt;
    PZ := PZ + FVelZ[I] * SafeDt;

    { Hard obstacle pushout & arena wall clamp }
    for K := 0 to High(FObstacles) do
    begin
      DX := PX - FObstacles[K].CenterX;
      DZ := PZ - FObstacles[K].CenterZ;
      Dist := Hypot(DX, DZ);
      ObsR := FObstacles[K].Radius + 0.25;
      if Dist < ObsR then
      begin
        if Dist < 1e-5 then
        begin
          DX := 1.0;
          DZ := 0.0;
          Dist := 1.0;
        end;
        PX := FObstacles[K].CenterX + (DX / Dist) * ObsR;
        PZ := FObstacles[K].CenterZ + (DZ / Dist) * ObsR;
      end;
    end;

    PX := Clamped(PX, -FArenaHalfExtent, FArenaHalfExtent);
    PZ := Clamped(PZ, -FArenaHalfExtent, FArenaHalfExtent);

    FPosX[I] := PX;
    FPosZ[I] := PZ;
    if Hypot(FVelX[I], FVelZ[I]) > 0.05 then
      FHeadingRad[I] := ArcTan2(-FVelX[I], -FVelZ[I]);
  end;

  if FBuildVisualBatch then
    RebuildVisualBatchMesh;

  FLastStepTimeMs := StepTimer.ElapsedTime * 1000.0;
end;

procedure TCastleMassEntityManager.UpdateRepresentationLods(
  const ViewerPos: TVector3);
var
  I: Integer;
  WorldPt: TVector3;
  DistSq, HighSq, MedSq, CullSq: Single;
  T: TMassRepresentationTier;
begin
  for T in TMassRepresentationTier do
    FTierCounts[T] := 0;

  HighSq := Sqr(Max(1.0, FHighMeshDist));
  MedSq := Sqr(Max(FHighMeshDist + 1.0, FMediumProxyDist));
  CullSq := Sqr(Max(FMediumProxyDist + 1.0, FCullDist));

  for I := 0 to FCount - 1 do
  begin
    WorldPt := Translation + Vector3(FPosX[I], FPosY[I], FPosZ[I]);
    DistSq := PointsDistanceSqr(WorldPt, ViewerPos);
    if DistSq <= HighSq then
      FLodTier[I] := mrtHighMesh
    else if DistSq <= MedSq then
      FLodTier[I] := mrtMediumProxy
    else if DistSq <= CullSq then
      FLodTier[I] := mrtLowBatchedPoint
    else
      FLodTier[I] := mrtCulledOffscreen;
    Inc(FTierCounts[FLodTier[I]]);
  end;
end;

procedure TCastleMassEntityManager.RebuildVisualBatchMesh;
const
  MaxVisualDarts = 800;
var
  RootNode: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
  VisCount, I, BaseV: Integer;
  SinH, CosH, FX, FZ, RX, RZ, PX, PY, PZ: Single;
begin
  VisCount := Min(FCount, MaxVisualDarts);
  if FBatchScene = nil then
  begin
    FBatchScene := TCastleScene.Create(Self);
    FBatchScene.SetTransient;
    FBatchScene.Pickable := False;
    Add(FBatchScene);

    RootNode := TX3DRootNode.Create;
    Shape := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Mat.BaseColor := Vector3(0.26, 0.78, 0.96);
    Mat.Roughness := 0.45;
    App.Material := Mat;
    Shape.Appearance := App;

    TriSet := TTriangleSetNode.Create;
    TriSet.Solid := False;
    FCoordNode := TCoordinateNode.Create;
    TriSet.Coord := FCoordNode;
    Shape.Geometry := TriSet;
    RootNode.AddChildren(Shape);
    FBatchScene.Load(RootNode, True);
  end;

  if FCoordNode = nil then
    Exit;

  FCoordNode.FdPoint.Count := VisCount * 3;
  for I := 0 to VisCount - 1 do
  begin
    SinCos(FHeadingRad[I], SinH, CosH);
    FX := -SinH;
    FZ := -CosH;
    RX := CosH;
    RZ := -SinH;
    PX := FPosX[I];
    PY := FPosY[I] + 0.35;
    PZ := FPosZ[I];

    BaseV := I * 3;
    FCoordNode.FdPoint.Items.L[BaseV]     := Vector3(PX + FX * 0.48, PY + 0.12, PZ + FZ * 0.48);
    FCoordNode.FdPoint.Items.L[BaseV + 1] := Vector3(PX - FX * 0.32 - RX * 0.26, PY, PZ - FZ * 0.32 - RZ * 0.26);
    FCoordNode.FdPoint.Items.L[BaseV + 2] := Vector3(PX - FX * 0.32 + RX * 0.26, PY, PZ - FZ * 0.32 + RZ * 0.26);
  end;
  FCoordNode.FdPoint.Changed;
end;

procedure TCastleMassEntityManager.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleDesignMode and (not FSimulateInEditor) then
    Exit;
  StepSwarm(SecondsPassed);
end;

function TCastleMassEntityManager.ActiveEntityCount: Integer;
begin
  Result := FCount;
end;

function TCastleMassEntityManager.GetEntitySnapshot(
  const Index: Integer): TMassEntitySnapshot;
begin
  if (Index >= 0) and (Index < FCount) then
  begin
    Result.PosX := FPosX[Index];
    Result.PosY := FPosY[Index];
    Result.PosZ := FPosZ[Index];
    Result.VelX := FVelX[Index];
    Result.VelZ := FVelZ[Index];
    Result.HeadingRad := FHeadingRad[Index];
    Result.LodTier := FLodTier[Index];
  end else
    Result := Default(TMassEntitySnapshot);
end;

function TCastleMassEntityManager.GetTierCount(
  const ATier: TMassRepresentationTier): Integer;
begin
  Result := FTierCounts[ATier];
end;

function TCastleMassEntityManager.MeanPositionXZ: TVector2;
var
  I: Integer;
  SumX, SumZ: Double;
begin
  if FCount <= 0 then
    Exit(TVector2.Zero);
  SumX := 0.0;
  SumZ := 0.0;
  for I := 0 to FCount - 1 do
  begin
    SumX := SumX + FPosX[I];
    SumZ := SumZ + FPosZ[I];
  end;
  Result := Vector2(SumX / FCount, SumZ / FCount);
end;

function TCastleMassEntityManager.GetConfigJson: String;
var
  Root, ObsObj: TJSONObject;
  ObsArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('targetEntityCount', FTargetEntityCount);
    ObsArr := TJSONArray.Create;
    for I := 0 to High(FObstacles) do
    begin
      ObsObj := TJSONObject.Create;
      ObsObj.Add('x', FObstacles[I].CenterX);
      ObsObj.Add('z', FObstacles[I].CenterZ);
      ObsObj.Add('r', FObstacles[I].Radius);
      ObsArr.Add(ObsObj);
    end;
    Root.Add('obstacles', ObsArr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleMassEntityManager.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, ObsObj: TJSONObject;
  ObsArr: TJSONArray;
  I, PresetOrd: Integer;
begin
  if Trim(Value) = '' then
    Exit;
  Data := nil;
  try
    Data := GetJSON(Value);
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      ClearObstacles;
      if Root.Find('obstacles') is TJSONArray then
      begin
        ObsArr := TJSONArray(Root.Find('obstacles'));
        for I := 0 to ObsArr.Count - 1 do
          if ObsArr.Items[I] is TJSONObject then
          begin
            ObsObj := TJSONObject(ObsArr.Items[I]);
            AddObstacleCircleXZ(ObsObj.Get('x', 0.0), ObsObj.Get('z', 0.0), ObsObj.Get('r', 2.0));
          end;
      end;
      PresetOrd := Root.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TMassSwarmPreset))) and
         (PresetOrd <= Ord(High(TMassSwarmPreset))) then
        FPreset := TMassSwarmPreset(PresetOrd);
      SetTargetEntityCount(Root.Get('targetEntityCount', FTargetEntityCount));
      BakeGoalFlowField;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleMassEntityManager.SwarmSummaryBadge: String;
begin
  Result := Format('[MassECS:%d entities %d obs %.2fms]',
    [FCount, Length(FObstacles), FLastStepTimeMs]);
end;

initialization
  RegisterSerializableComponent(TCastleMassEntityManager,
    ['AI & Crowds', 'MassEntity SoA Crowd & Flow-Field Manager']);
end.
