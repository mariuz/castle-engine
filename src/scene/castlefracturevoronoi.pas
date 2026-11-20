{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Procedural 3D Voronoi destruction fracture cutter, facet-sharing bond graph,
  radial impact shatter solver, and Breadth-First Search (BFS) ground-support
  connectivity collapse preventing floating sky-islands (Milestone Phase 400). }
unit CastleFractureVoronoi;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors;

type
  { Preset structural brittle/reinforced fracture profiles. }
  TVoronoiFracturePreset = (
    vfpBrittleMasonryWall,
    vfpReinforcedConcretePillar,
    vfpShatteredTemperedGlass
  );

  { Computed geometry, foundation support, and collapse kinematics of one Voronoi shard. }
  TVoronoiShardState = record
    ShardIndex: Integer;
    SeedLocalPos: TVector3;
    CenterLocalPos: TVector3;
    ApproxSize: TVector3;
    VolumeM3: Single;
    IsGroundAnchored: Boolean;
    IsSupportedByGroundGraph: Boolean;
    IsDetachedFalling: Boolean;
    CollapseOffsetLocal: TVector3;
    CollapseVelocityLocal: TVector3;
  end;

  { Structural tensile bond between two facet-sharing Voronoi shards. }
  TShardBond = record
    ShardA: Integer;
    ShardB: Integer;
    MidpointLocal: TVector3;
    TensileStrengthNs: Single;
    IsBroken: Boolean;
  end;

  { Scene transform partitioning a wall/pillar into volume-conserving 3D Voronoi
    shards with facet adjacency bonds and BFS ground-connectivity collapse. }
  TCastleVoronoiFractureVolume = class(TCastleTransform)
  private
    FPreset: TVoronoiFracturePreset;
    FWallDimensions: TVector3;
    FWallDimensionsPersistent: TCastleVector3Persistent;
    FShardCount: Integer;
    FBondTensileStrengthNs: Single;
    FFoundationHeightMeters: Single;
    FRandomSeed: Integer;
    FShowPreview: Boolean;
    FShards: array of TVoronoiShardState;
    FBonds: array of TShardBond;
    FIntactBondCount: Integer;
    FBrokenBondCount: Integer;
    FSupportedShardCount: Integer;
    FDetachedShardCount: Integer;
    FTotalVolumeM3: Single;
    FPreviewRoot: TCastleTransform;
    procedure SetPreset(const AValue: TVoronoiFracturePreset);
    procedure SetShardCount(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
    function GetWallDimForPersistent: TVector3;
    procedure SetWallDimForPersistent(const AValue: TVector3);
    procedure RecomputeSupportConnectivityBFS;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TVoronoiFracturePreset);

    { Partition WallDimensions into ShardCount stratified 3D Voronoi cells and
      build exact 6-neighbor facet-sharing structural bonds. }
    procedure GenerateVoronoiShards;

    { Apply a radial impact impulse (N*s) in local space, breaking weak bonds
      inside ARadiusMeters and triggering BFS ground-connectivity collapse. }
    function ApplyImpactImpulseAtLocal(const AImpactLocalPos: TVector3;
      const ARadiusMeters, AImpulseNs: Single): Integer;

    { Apply a radial impact impulse in world space. }
    function ApplyImpactImpulseAtWorld(const AImpactWorldPos: TVector3;
      const ARadiusMeters, AImpulseNs: Single): Integer;

    { Step gravity freefall and floor-rubble arrest for detached shards. }
    procedure StepDetachedCollapse(const ADtSec: Single);

    function ActualShardCount: Integer;
    function GetShardState(const AIndex: Integer): TVoronoiShardState;
    function TotalBondCount: Integer;
    procedure RebuildPreview;
    procedure ClearPreview;
    function FractureSummaryBadge: String;

    property WallDimensions: TVector3 read FWallDimensions write FWallDimensions;
    property IntactBondCount: Integer read FIntactBondCount;
    property BrokenBondCount: Integer read FBrokenBondCount;
    property SupportedShardCount: Integer read FSupportedShardCount;
    property DetachedShardCount: Integer read FDetachedShardCount;
    property TotalVolumeM3: Single read FTotalVolumeM3;
  published
    property Preset: TVoronoiFracturePreset
      read FPreset write SetPreset default vfpBrittleMasonryWall;
    property WallDimensionsPersistent: TCastleVector3Persistent
      read FWallDimensionsPersistent;
    property ShardCount: Integer
      read FShardCount write SetShardCount default 24;
    property BondTensileStrengthNs: Single
      read FBondTensileStrengthNs write FBondTensileStrengthNs;
    property FoundationHeightMeters: Single
      read FFoundationHeightMeters write FFoundationHeightMeters;
    property RandomSeed: Integer
      read FRandomSeed write FRandomSeed default 4000;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function VoronoiPresetToString(const APreset: TVoronoiFracturePreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function VoronoiPresetToString(const APreset: TVoronoiFracturePreset): String;
begin
  case APreset of
    vfpBrittleMasonryWall:       Result := 'BrittleMasonryWall';
    vfpReinforcedConcretePillar: Result := 'ReinforcedConcretePillar';
    vfpShatteredTemperedGlass:   Result := 'ShatteredTemperedGlass';
  end;
end;

{$PUSH}{$Q-}{$R-}
function VoronoiHash01(const ASeed, ASalt: Integer): Single;
var
  H: Cardinal;
begin
  H := Cardinal(ASeed) * Cardinal(747796405) +
       Cardinal(ASalt + 41) * Cardinal(2891336453) + Cardinal(1013904223);
  H := ((H shr ((H shr 28) + 4)) xor H) * Cardinal(277803737);
  H := (H shr 22) xor H;
  Result := (H and $00FFFFFF) / 16777216.0;
end;
{$POP}

{ TCastleVoronoiFractureVolume ----------------------------------------------- }

constructor TCastleVoronoiFractureVolume.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWallDimensions := Vector3(4.0, 3.6, 0.5);
  FWallDimensionsPersistent := TCastleVector3Persistent.Create(nil);
  FWallDimensionsPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetWallDimForPersistent;
  FWallDimensionsPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetWallDimForPersistent;
  FWallDimensionsPersistent.InternalDefaultValue := Vector3(4.0, 3.6, 0.5);
  FShardCount := 24;
  FRandomSeed := 4000;
  FShowPreview := True;
  ApplyPreset(vfpBrittleMasonryWall);
end;

destructor TCastleVoronoiFractureVolume.Destroy;
begin
  ClearPreview;
  FreeAndNil(FWallDimensionsPersistent);
  inherited Destroy;
end;

function TCastleVoronoiFractureVolume.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'WallDimensionsPersistent', 'ShardCount',
       'BondTensileStrengthNs', 'FoundationHeightMeters',
       'RandomSeed', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleVoronoiFractureVolume.GetWallDimForPersistent: TVector3;
begin
  Result := FWallDimensions;
end;

procedure TCastleVoronoiFractureVolume.SetWallDimForPersistent(
  const AValue: TVector3);
begin
  FWallDimensions := AValue;
  GenerateVoronoiShards;
end;

procedure TCastleVoronoiFractureVolume.SetPreset(
  const AValue: TVoronoiFracturePreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleVoronoiFractureVolume.SetShardCount(const AValue: Integer);
var
  ClampedN: Integer;
begin
  ClampedN := Clamped(AValue, 6, 64);
  if FShardCount = ClampedN then Exit;
  FShardCount := ClampedN;
  GenerateVoronoiShards;
end;

procedure TCastleVoronoiFractureVolume.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleVoronoiFractureVolume.ApplyPreset(
  const APreset: TVoronoiFracturePreset);
begin
  FPreset := APreset;
  case APreset of
    vfpBrittleMasonryWall:
      begin
        FWallDimensions := Vector3(4.0, 3.6, 0.50);
        FShardCount := 24;
        FBondTensileStrengthNs := 120.0;
        FFoundationHeightMeters := 0.35;
      end;
    vfpReinforcedConcretePillar:
      begin
        FWallDimensions := Vector3(1.4, 4.8, 1.4);
        FShardCount := 20;
        FBondTensileStrengthNs := 480.0;
        FFoundationHeightMeters := 0.45;
      end;
    vfpShatteredTemperedGlass:
      begin
        FWallDimensions := Vector3(3.2, 2.8, 0.12);
        FShardCount := 32;
        FBondTensileStrengthNs := 25.0;
        FFoundationHeightMeters := 0.25;
      end;
  end;
  GenerateVoronoiShards;
end;

procedure TCastleVoronoiFractureVolume.GenerateVoronoiShards;
const
  VX = 18;
  VY = 18;
  VZ = 4;
var
  W, H, D, VoxelVol, BestD2, Dist2: Single;
  N, ColsX, RowsY, I, IX, IY, IZ, VIdx, BestShard, A, B, BondCnt: Integer;
  VoxOwner: array of Integer;
  VoxCounts: array of Integer;
  MinP, MaxP, SumP: array of TVector3;
  AdjMatrix: array of Boolean;
  Pt: TVector3;

  function VoxelIndex(const X, Y, Z: Integer): Integer; inline;
  begin
    Result := (Z * VY + Y) * VX + X;
  end;

  procedure NoteAdjacency(const S1, S2: Integer);
  var
    LoS, HiS: Integer;
  begin
    if (S1 = S2) or (S1 < 0) or (S2 < 0) then Exit;
    LoS := Min(S1, S2);
    HiS := Max(S1, S2);
    AdjMatrix[LoS * N + HiS] := True;
  end;

begin
  W := Max(0.2, FWallDimensions.X);
  H := Max(0.4, FWallDimensions.Y);
  D := Max(0.08, FWallDimensions.Z);
  N := Clamped(FShardCount, 6, 64);

  SetLength(FShards, N);
  ColsX := Max(2, Round(Sqrt(N * (W / H))));
  RowsY := Max(2, Ceil(N / ColsX));

  for I := 0 to N - 1 do
  begin
    IX := I mod ColsX;
    IY := I div ColsX;
    FShards[I] := Default(TVoronoiShardState);
    FShards[I].ShardIndex := I;
    FShards[I].SeedLocalPos := Vector3(
      -0.5 * W + ((IX + 0.20 + 0.60 * VoronoiHash01(FRandomSeed, I * 3)) / ColsX) * W,
      ((Min(RowsY - 1, IY) + 0.20 + 0.60 * VoronoiHash01(FRandomSeed, I * 3 + 1)) / RowsY) * H,
      (VoronoiHash01(FRandomSeed, I * 3 + 2) - 0.5) * D * 0.75);
    FShards[I].CenterLocalPos := FShards[I].SeedLocalPos;
    FShards[I].ApproxSize := Vector3(W / ColsX, H / RowsY, D);
  end;

  SetLength(VoxOwner, VX * VY * VZ);
  SetLength(VoxCounts, N);
  SetLength(SumP, N);
  SetLength(MinP, N);
  SetLength(MaxP, N);
  for I := 0 to N - 1 do
  begin
    VoxCounts[I] := 0;
    SumP[I] := TVector3.Zero;
    MinP[I] := Vector3(1e9, 1e9, 1e9);
    MaxP[I] := Vector3(-1e9, -1e9, -1e9);
  end;

  VoxelVol := (W * H * D) / (VX * VY * VZ);
  for IZ := 0 to VZ - 1 do
    for IY := 0 to VY - 1 do
      for IX := 0 to VX - 1 do
      begin
        Pt := Vector3(
          -0.5 * W + ((IX + 0.5) / VX) * W,
          ((IY + 0.5) / VY) * H,
          -0.5 * D + ((IZ + 0.5) / VZ) * D);
        BestShard := 0;
        BestD2 := PointsDistanceSqr(Pt, FShards[0].SeedLocalPos);
        for I := 1 to N - 1 do
        begin
          Dist2 := PointsDistanceSqr(Pt, FShards[I].SeedLocalPos);
          if Dist2 < BestD2 then
          begin
            BestD2 := Dist2;
            BestShard := I;
          end;
        end;
        VIdx := VoxelIndex(IX, IY, IZ);
        VoxOwner[VIdx] := BestShard;
        Inc(VoxCounts[BestShard]);
        SumP[BestShard] := SumP[BestShard] + Pt;
        MinP[BestShard].X := Min(MinP[BestShard].X, Pt.X - 0.5 * (W / VX));
        MinP[BestShard].Y := Min(MinP[BestShard].Y, Pt.Y - 0.5 * (H / VY));
        MinP[BestShard].Z := Min(MinP[BestShard].Z, Pt.Z - 0.5 * (D / VZ));
        MaxP[BestShard].X := Max(MaxP[BestShard].X, Pt.X + 0.5 * (W / VX));
        MaxP[BestShard].Y := Max(MaxP[BestShard].Y, Pt.Y + 0.5 * (H / VY));
        MaxP[BestShard].Z := Max(MaxP[BestShard].Z, Pt.Z + 0.5 * (D / VZ));
        if IY = 0 then
          FShards[BestShard].IsGroundAnchored := True;
      end;

  FTotalVolumeM3 := 0.0;
  for I := 0 to N - 1 do
  begin
    if VoxCounts[I] > 0 then
    begin
      FShards[I].CenterLocalPos := SumP[I] / VoxCounts[I];
      FShards[I].VolumeM3 := VoxCounts[I] * VoxelVol;
      FShards[I].ApproxSize := Vector3(
        Max(0.08, (MaxP[I].X - MinP[I].X) * 0.88),
        Max(0.08, (MaxP[I].Y - MinP[I].Y) * 0.88),
        Max(0.06, (MaxP[I].Z - MinP[I].Z) * 0.92));
      if MinP[I].Y <= FFoundationHeightMeters then
        FShards[I].IsGroundAnchored := True;
    end else
      FShards[I].VolumeM3 := 0.0;
    FTotalVolumeM3 := FTotalVolumeM3 + FShards[I].VolumeM3;
  end;

  { Build exact 6-neighbor Voronoi facet adjacency bonds }
  SetLength(AdjMatrix, N * N);
  FillChar(AdjMatrix[0], Length(AdjMatrix) * SizeOf(Boolean), 0);
  for IZ := 0 to VZ - 1 do
    for IY := 0 to VY - 1 do
      for IX := 0 to VX - 1 do
      begin
        VIdx := VoxelIndex(IX, IY, IZ);
        if IX + 1 < VX then NoteAdjacency(VoxOwner[VIdx], VoxOwner[VoxelIndex(IX + 1, IY, IZ)]);
        if IY + 1 < VY then NoteAdjacency(VoxOwner[VIdx], VoxOwner[VoxelIndex(IX, IY + 1, IZ)]);
        if IZ + 1 < VZ then NoteAdjacency(VoxOwner[VIdx], VoxOwner[VoxelIndex(IX, IY, IZ + 1)]);
      end;

  BondCnt := 0;
  SetLength(FBonds, N * 6);
  for A := 0 to N - 2 do
    for B := A + 1 to N - 1 do
      if AdjMatrix[A * N + B] then
      begin
        if BondCnt >= Length(FBonds) then
          SetLength(FBonds, Length(FBonds) * 2);
        FBonds[BondCnt].ShardA := A;
        FBonds[BondCnt].ShardB := B;
        FBonds[BondCnt].MidpointLocal :=
          (FShards[A].CenterLocalPos + FShards[B].CenterLocalPos) * 0.5;
        FBonds[BondCnt].TensileStrengthNs := Max(1.0, FBondTensileStrengthNs);
        FBonds[BondCnt].IsBroken := False;
        Inc(BondCnt);
      end;
  SetLength(FBonds, BondCnt);

  RecomputeSupportConnectivityBFS;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleVoronoiFractureVolume.RecomputeSupportConnectivityBFS;
var
  Queue: array of Integer;
  QHead, QTail, I, Cur, Other, N: Integer;
begin
  N := Length(FShards);
  FIntactBondCount := 0;
  FBrokenBondCount := 0;
  for I := 0 to High(FBonds) do
    if FBonds[I].IsBroken then
      Inc(FBrokenBondCount)
    else
      Inc(FIntactBondCount);

  SetLength(Queue, Max(1, N));
  QHead := 0;
  QTail := 0;

  for I := 0 to N - 1 do
  begin
    FShards[I].IsSupportedByGroundGraph := FShards[I].IsGroundAnchored;
    if FShards[I].IsGroundAnchored then
    begin
      Queue[QTail] := I;
      Inc(QTail);
    end;
  end;

  { Breadth-First Search across unbroken structural bonds }
  while QHead < QTail do
  begin
    Cur := Queue[QHead];
    Inc(QHead);
    for I := 0 to High(FBonds) do
    begin
      if FBonds[I].IsBroken then Continue;
      if FBonds[I].ShardA = Cur then
        Other := FBonds[I].ShardB
      else if FBonds[I].ShardB = Cur then
        Other := FBonds[I].ShardA
      else
        Continue;

      if not FShards[Other].IsSupportedByGroundGraph then
      begin
        FShards[Other].IsSupportedByGroundGraph := True;
        Queue[QTail] := Other;
        Inc(QTail);
      end;
    end;
  end;

  FSupportedShardCount := 0;
  FDetachedShardCount := 0;
  for I := 0 to N - 1 do
  begin
    FShards[I].IsDetachedFalling := not FShards[I].IsSupportedByGroundGraph;
    if FShards[I].IsDetachedFalling then
      Inc(FDetachedShardCount)
    else
      Inc(FSupportedShardCount);
  end;
end;

function TCastleVoronoiFractureVolume.ApplyImpactImpulseAtLocal(
  const AImpactLocalPos: TVector3;
  const ARadiusMeters, AImpulseNs: Single): Integer;
var
  RadSafe, Dist, AttenImpulse: Single;
  I: Integer;
  DirOut: TVector3;
begin
  Result := 0;
  RadSafe := Max(0.05, ARadiusMeters);

  for I := 0 to High(FBonds) do
  begin
    if FBonds[I].IsBroken then Continue;
    Dist := PointsDistance(FBonds[I].MidpointLocal, AImpactLocalPos);
    if Dist <= RadSafe then
    begin
      AttenImpulse := AImpulseNs * (1.0 - 0.65 * (Dist / RadSafe));
      if AttenImpulse >= FBonds[I].TensileStrengthNs then
      begin
        FBonds[I].IsBroken := True;
        Inc(Result);
      end;
    end;
  end;

  { Direct blast onto foundation shards can also shear ground anchors }
  for I := 0 to High(FShards) do
  begin
    Dist := PointsDistance(FShards[I].CenterLocalPos, AImpactLocalPos);
    if Dist <= RadSafe then
    begin
      AttenImpulse := AImpulseNs * (1.0 - 0.65 * (Dist / RadSafe));
      if FShards[I].IsGroundAnchored and
         (AttenImpulse >= FBondTensileStrengthNs * 1.25) then
        FShards[I].IsGroundAnchored := False;
      DirOut := FShards[I].CenterLocalPos - AImpactLocalPos;
      if DirOut.LengthSqr < 1e-6 then
        DirOut := Vector3(0.0, 0.4, -1.0)
      else
        DirOut := DirOut.Normalize;
      FShards[I].CollapseVelocityLocal := FShards[I].CollapseVelocityLocal +
        DirOut * Clamped(AttenImpulse * 0.015, 0.0, 8.0);
    end;
  end;

  RecomputeSupportConnectivityBFS;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleVoronoiFractureVolume.ApplyImpactImpulseAtWorld(
  const AImpactWorldPos: TVector3;
  const ARadiusMeters, AImpulseNs: Single): Integer;
var
  InvWT, WT: TMatrix4;
begin
  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;
  Result := ApplyImpactImpulseAtLocal(
    InvWT.MultPoint(AImpactWorldPos), ARadiusMeters, AImpulseNs);
end;

procedure TCastleVoronoiFractureVolume.StepDetachedCollapse(const ADtSec: Single);
var
  I: Integer;
  Dt, MinRubbleY, CurY: Single;
begin
  if ADtSec <= 0.0 then Exit;
  Dt := Min(ADtSec, 0.25);

  for I := 0 to High(FShards) do
  begin
    if not FShards[I].IsDetachedFalling then Continue;
    FShards[I].CollapseVelocityLocal.Y :=
      FShards[I].CollapseVelocityLocal.Y - 9.81 * Dt;
    FShards[I].CollapseOffsetLocal := FShards[I].CollapseOffsetLocal +
      FShards[I].CollapseVelocityLocal * Dt;

    MinRubbleY := 0.5 * FShards[I].ApproxSize.Y;
    CurY := FShards[I].CenterLocalPos.Y + FShards[I].CollapseOffsetLocal.Y;
    if CurY < MinRubbleY then
    begin
      FShards[I].CollapseOffsetLocal.Y := MinRubbleY - FShards[I].CenterLocalPos.Y;
      FShards[I].CollapseVelocityLocal := FShards[I].CollapseVelocityLocal * 0.25;
      FShards[I].CollapseVelocityLocal.Y := 0.0;
    end;
  end;

  if FShowPreview then
    RebuildPreview;
end;

function TCastleVoronoiFractureVolume.ActualShardCount: Integer;
begin
  Result := Length(FShards);
end;

function TCastleVoronoiFractureVolume.GetShardState(
  const AIndex: Integer): TVoronoiShardState;
begin
  if (AIndex >= 0) and (AIndex < Length(FShards)) then
    Result := FShards[AIndex]
  else
    Result := Default(TVoronoiShardState);
end;

function TCastleVoronoiFractureVolume.TotalBondCount: Integer;
begin
  Result := Length(FBonds);
end;

procedure TCastleVoronoiFractureVolume.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
  end;
end;

procedure TCastleVoronoiFractureVolume.RebuildPreview;
var
  ShardBox: TCastleBox;
  I: Integer;
  S: TVoronoiShardState;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if (not FShowPreview) or (Length(FShards) = 0) then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'VoronoiFracturePreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  for I := 0 to High(FShards) do
  begin
    S := FShards[I];
    if S.VolumeM3 <= 1e-5 then Continue;
    ShardBox := TCastleBox.Create(FPreviewRoot);
    ShardBox.SetTransient;
    ShardBox.Pickable := False;
    ShardBox.Collides := False;
    ShardBox.Size := S.ApproxSize;
    ShardBox.Translation := S.CenterLocalPos + S.CollapseOffsetLocal;
    if S.IsDetachedFalling then
      ShardBox.Color := Vector4(0.94, 0.34, 0.28, 1.0)
    else if S.IsGroundAnchored then
      ShardBox.Color := Vector4(0.28, 0.78, 0.52, 1.0)
    else
      ShardBox.Color := Vector4(0.58, 0.62, 0.68, 1.0);
    FPreviewRoot.Add(ShardBox);
  end;

  Add(FPreviewRoot);
end;

function TCastleVoronoiFractureVolume.FractureSummaryBadge: String;
begin
  Result := Format('[Voronoi:%d/%d sup Bonds=%d/%d]', [
    FSupportedShardCount, Length(FShards), FIntactBondCount, Length(FBonds)]);
end;

initialization
  RegisterSerializableComponent(TCastleVoronoiFractureVolume, 'Voronoi Destruction Fracture Volume');

end.
