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

{ Deterministic 3D convex-polyhedral Voronoi fracture solver, damage-threshold
  prop shattering (@link(TCastleDestructibleBehavior)), radial blast + angular
  spin debris kinematics, ground bounce, and timed scale-down debris cleanup
  (@link(TCastleDebrisShardBehavior)) (Phase 305 — UE 6.0 Chaos Fracture Parity). }
unit CastleDestructible;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleVectors, CastleBoxes, CastleClassUtils, CastleUtils, CastleTransform;

type
  { Surface & fracture-interior PBR material preset for Voronoi shards. }
  TDestructibleMaterialPreset = (
    dmpStoneMasonry,
    dmpWoodenCrate,
    dmpCrystalGlass,
    dmpScrapMetal,
    dmpObsidianCore
  );

  TVoronoiFacePolygon = array of TVector3;
  TVoronoiFacePolygonArray = array of TVoronoiFacePolygon;

  { Exact 3D convex-polyhedral Voronoi shard cell computed inside a prop box. }
  TVoronoiShardCell = record
    SiteLocal: TVector3;
    CentroidLocal: TVector3;
    BoundingRadius: Single;
    Volume: Single;
    FacesLocal: TVoronoiFacePolygonArray; { Vertices centered around CentroidLocal }
  end;
  TVoronoiShardCellArray = array of TVoronoiShardCell;

  { Per-shard ballistic, spin, ground-bounce & timed shrink lifecycle behavior. }
  TCastleDebrisShardBehavior = class(TCastleBehavior)
  strict private
    FLinearVelocity: TVector3;
    FSpinAxis: TVector3;
    FSpinSpeedRad: Single;
    FGravityY: Single;
    FGroundFloorY: Single;
    FRestitution: Single;
    FShardRadius: Single;
    FLifetimeSec: Single;
    FAgeSec: Single;
    FShrinkDurationSec: Single;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Advance debris shard kinematics by @code(ADeltaSeconds). Sets @code(OutExpired)
      when @code(AgeSec >= LifetimeSec). }
    procedure StepSimulation(const ADeltaSeconds: Single; out OutExpired: Boolean);

    property LinearVelocity: TVector3 read FLinearVelocity write FLinearVelocity;
    property SpinAxis: TVector3 read FSpinAxis write FSpinAxis;
    property SpinSpeedRad: Single read FSpinSpeedRad write FSpinSpeedRad;
    property GravityY: Single read FGravityY write FGravityY;
    property GroundFloorY: Single read FGroundFloorY write FGroundFloorY;
    property Restitution: Single read FRestitution write FRestitution;
    property ShardRadius: Single read FShardRadius write FShardRadius;
    property LifetimeSec: Single read FLifetimeSec write FLifetimeSec;
    property AgeSec: Single read FAgeSec write FAgeSec;
    property ShrinkDurationSec: Single read FShrinkDurationSec write FShrinkDurationSec;
  end;

  { Seeded 3D Voronoi destructible prop behavior with health/damage thresholds,
    radial blast impulses, and zero-leak transient debris lifecycle management. }
  TCastleDestructibleBehavior = class(TCastleBehavior)
  public const
    DefaultMaxHealth = Single(100.0);
    DefaultShardCount = 12;
    DefaultFractureSeed = 1337;
    DefaultCrackGap = Single(0.015);
    DefaultBlastImpulse = Single(4.5);
    DefaultBlastUpwardLift = Single(2.2);
    DefaultAngularImpulse = Single(5.0);
    DefaultDebrisLifetimeSec = Single(4.0);
    DefaultGroundFloorY = Single(0.0);
  strict private
    FMaxHealth: Single;
    FCurrentHealth: Single;
    FShardCount: Integer;
    FFractureSeed: Integer;
    FCrackGap: Single;
    FMaterialPreset: TDestructibleMaterialPreset;
    FBlastImpulse: Single;
    FBlastUpwardLift: Single;
    FAngularImpulse: Single;
    FDebrisLifetimeSec: Single;
    FGroundFloorY: Single;
    FFractureBoxSize: TVector3;
    FFractureBoxSizePersistent: TCastleVector3Persistent;
    FHideIntactVisualsOnFracture: Boolean;
    FShowVoronoiPreviewInViewport: Boolean;

    FIsFractured: Boolean;
    FSavedParentVisible: Boolean;
    FSavedParentCollides: Boolean;
    FDebrisRoot: TCastleTransform;

    function GetFractureBoxSizeForPersistent: TVector3;
    procedure SetFractureBoxSizeForPersistent(const AValue: TVector3);
    procedure SetFractureBoxSize(const Value: TVector3);
    procedure SetMaxHealth(const Value: Single);
    procedure SetCurrentHealth(const Value: Single);
    procedure SetShardCount(const Value: Integer);
    procedure SetCrackGap(const Value: Single);
    procedure SetBlastImpulse(const Value: Single);
    procedure SetDebrisLifetimeSec(const Value: Single);
    function ResolveLocalBounds(out OutCenter, OutSize: TVector3): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Subtract @code(ADamage) from @link(CurrentHealth) and automatically call
      @link(TriggerFracture) when health reaches @code(<= 0). }
    function ApplyDamage(const ADamage: Single;
      const ABlastOriginWorld: TVector3): Boolean;

    { Decompose prop bounds into seeded 3D convex Voronoi polyhedral shards and
      apply radial + upward + angular spin impulses from @code(ABlastOriginWorld). }
    function TriggerFracture(const ABlastOriginWorld: TVector3): Integer;

    { Advance all active debris shards by @code(ADeltaSeconds) and remove any
      expired shards. Returns remaining active shard count. }
    function StepDebrisSimulation(const ADeltaSeconds: Single): Integer;

    { Remove and free all transient debris shards without altering intact visibility. }
    procedure ClearDebris;

    { Restore intact prop visibility, collisions, and full @link(MaxHealth). }
    procedure ResetIntact;

    function ActiveShardCount: Integer;
    function GetShardTransform(const AIndex: Integer): TCastleTransform;
    function DestructibleSummaryBadge: String;

    property IsFractured: Boolean read FIsFractured;
    property FractureBoxSize: TVector3 read FFractureBoxSize write SetFractureBoxSize;
  published
    property MaxHealth: Single
      read FMaxHealth write SetMaxHealth
      {$ifdef FPC}default DefaultMaxHealth{$endif};
    property CurrentHealth: Single
      read FCurrentHealth write SetCurrentHealth
      {$ifdef FPC}default DefaultMaxHealth{$endif};
    property ShardCount: Integer
      read FShardCount write SetShardCount default DefaultShardCount;
    property FractureSeed: Integer
      read FFractureSeed write FFractureSeed default DefaultFractureSeed;
    property CrackGap: Single
      read FCrackGap write SetCrackGap
      {$ifdef FPC}default DefaultCrackGap{$endif};
    property MaterialPreset: TDestructibleMaterialPreset
      read FMaterialPreset write FMaterialPreset default dmpStoneMasonry;
    property BlastImpulse: Single
      read FBlastImpulse write SetBlastImpulse
      {$ifdef FPC}default DefaultBlastImpulse{$endif};
    property BlastUpwardLift: Single
      read FBlastUpwardLift write FBlastUpwardLift
      {$ifdef FPC}default DefaultBlastUpwardLift{$endif};
    property AngularImpulse: Single
      read FAngularImpulse write FAngularImpulse
      {$ifdef FPC}default DefaultAngularImpulse{$endif};
    property DebrisLifetimeSec: Single
      read FDebrisLifetimeSec write SetDebrisLifetimeSec
      {$ifdef FPC}default DefaultDebrisLifetimeSec{$endif};
    property GroundFloorY: Single
      read FGroundFloorY write FGroundFloorY
      {$ifdef FPC}default DefaultGroundFloorY{$endif};
    property FractureBoxSizePersistent: TCastleVector3Persistent
      read FFractureBoxSizePersistent;
    property HideIntactVisualsOnFracture: Boolean
      read FHideIntactVisualsOnFracture write FHideIntactVisualsOnFracture default true;
    property ShowVoronoiPreviewInViewport: Boolean
      read FShowVoronoiPreviewInViewport write FShowVoronoiPreviewInViewport default true;
  end;

{ Deterministic 3D convex-polyhedral Voronoi cell decomposition of @code(ABoxSize)
  centered at @code(ABoxCenter) using @code(AShardCount) Halton-seeded nuclei. }
function ComputeVoronoiFractureCells(
  const ABoxCenter, ABoxSize: TVector3;
  const AShardCount, ARandomSeed: Integer;
  const ACrackGap: Single): TVoronoiShardCellArray;

function DestructiblePresetDisplayName(const APreset: TDestructibleMaterialPreset): String;

implementation

uses
  CastleComponentSerialize, CastleScene, X3DNodes;

function DestructiblePresetDisplayName(const APreset: TDestructibleMaterialPreset): String;
begin
  case APreset of
    dmpStoneMasonry: Result := 'Stone Masonry';
    dmpWoodenCrate: Result := 'Wooden Crate';
    dmpCrystalGlass: Result := 'Crystal Glass';
    dmpScrapMetal: Result := 'Scrap Metal';
    dmpObsidianCore: Result := 'Obsidian Core';
  end;
end;

procedure GetDestructiblePresetMaterial(const APreset: TDestructibleMaterialPreset;
  out OutBaseColor, OutEmissive: TVector3;
  out OutRoughness, OutMetallic, OutRestitution: Single);
begin
  OutEmissive := TVector3.Zero;
  case APreset of
    dmpStoneMasonry:
      begin
        OutBaseColor := Vector3(0.56, 0.55, 0.52);
        OutRoughness := 0.88;
        OutMetallic := 0.02;
        OutRestitution := 0.25;
      end;
    dmpWoodenCrate:
      begin
        OutBaseColor := Vector3(0.62, 0.42, 0.22);
        OutRoughness := 0.78;
        OutMetallic := 0.0;
        OutRestitution := 0.32;
      end;
    dmpCrystalGlass:
      begin
        OutBaseColor := Vector3(0.55, 0.86, 0.96);
        OutEmissive := Vector3(0.06, 0.14, 0.20);
        OutRoughness := 0.12;
        OutMetallic := 0.10;
        OutRestitution := 0.48;
      end;
    dmpScrapMetal:
      begin
        OutBaseColor := Vector3(0.48, 0.50, 0.55);
        OutRoughness := 0.36;
        OutMetallic := 0.85;
        OutRestitution := 0.38;
      end;
    dmpObsidianCore:
      begin
        OutBaseColor := Vector3(0.16, 0.14, 0.20);
        OutEmissive := Vector3(0.22, 0.06, 0.02);
        OutRoughness := 0.28;
        OutMetallic := 0.25;
        OutRestitution := 0.30;
      end;
  end;
end;

function HaltonRadicalInverse(AIndex: Integer; const ABase: Integer): Single;
var
  F: Single;
begin
  Result := 0.0;
  F := 1.0 / ABase;
  while AIndex > 0 do
  begin
    Result := Result + F * (AIndex mod ABase);
    AIndex := AIndex div ABase;
    F := F / ABase;
  end;
end;

function BuildInitialBoxFaces(const AMinP, AMaxP: TVector3): TVoronoiFacePolygonArray;
begin
  Result := nil;
  SetLength(Result, 6);
  { 0: -Z }
  SetLength(Result[0], 4);
  Result[0][0] := Vector3(AMinP.X, AMinP.Y, AMinP.Z);
  Result[0][1] := Vector3(AMinP.X, AMaxP.Y, AMinP.Z);
  Result[0][2] := Vector3(AMaxP.X, AMaxP.Y, AMinP.Z);
  Result[0][3] := Vector3(AMaxP.X, AMinP.Y, AMinP.Z);
  { 1: +Z }
  SetLength(Result[1], 4);
  Result[1][0] := Vector3(AMinP.X, AMinP.Y, AMaxP.Z);
  Result[1][1] := Vector3(AMaxP.X, AMinP.Y, AMaxP.Z);
  Result[1][2] := Vector3(AMaxP.X, AMaxP.Y, AMaxP.Z);
  Result[1][3] := Vector3(AMinP.X, AMaxP.Y, AMaxP.Z);
  { 2: -X }
  SetLength(Result[2], 4);
  Result[2][0] := Vector3(AMinP.X, AMinP.Y, AMinP.Z);
  Result[2][1] := Vector3(AMinP.X, AMinP.Y, AMaxP.Z);
  Result[2][2] := Vector3(AMinP.X, AMaxP.Y, AMaxP.Z);
  Result[2][3] := Vector3(AMinP.X, AMaxP.Y, AMinP.Z);
  { 3: +X }
  SetLength(Result[3], 4);
  Result[3][0] := Vector3(AMaxP.X, AMinP.Y, AMinP.Z);
  Result[3][1] := Vector3(AMaxP.X, AMaxP.Y, AMinP.Z);
  Result[3][2] := Vector3(AMaxP.X, AMaxP.Y, AMaxP.Z);
  Result[3][3] := Vector3(AMaxP.X, AMinP.Y, AMaxP.Z);
  { 4: -Y }
  SetLength(Result[4], 4);
  Result[4][0] := Vector3(AMinP.X, AMinP.Y, AMinP.Z);
  Result[4][1] := Vector3(AMaxP.X, AMinP.Y, AMinP.Z);
  Result[4][2] := Vector3(AMaxP.X, AMinP.Y, AMaxP.Z);
  Result[4][3] := Vector3(AMinP.X, AMinP.Y, AMaxP.Z);
  { 5: +Y }
  SetLength(Result[5], 4);
  Result[5][0] := Vector3(AMinP.X, AMaxP.Y, AMinP.Z);
  Result[5][1] := Vector3(AMinP.X, AMaxP.Y, AMaxP.Z);
  Result[5][2] := Vector3(AMaxP.X, AMaxP.Y, AMaxP.Z);
  Result[5][3] := Vector3(AMaxP.X, AMaxP.Y, AMinP.Z);
end;

{ Clip convex polyhedron @code(AFaces) to half-space @code((P - APlanePt) dot AOutNormal <= 0),
  adding a newly formed planar fracture cap face oriented with outward normal @code(AOutNormal). }
procedure ClipPolyhedronByHalfSpace(var AFaces: TVoronoiFacePolygonArray;
  const APlanePt, AOutNormal: TVector3);
const
  PlaneEps = 1e-5;
var
  NewFaces: TVoronoiFacePolygonArray;
  CapPts: TVoronoiFacePolygon;
  CapAngles: array of Single;
  FIdx, VIdx, OutFaceCount, CapCount, I, J: Integer;
  Face, ClippedFace: TVoronoiFacePolygon;
  PrevPt, CurPt, InterPt, CapCenter, AxisU, AxisV, Rel: TVector3;
  PrevDist, CurDist, T, TmpAngle: Single;
  TmpPt: TVector3;

  procedure AddUniqueCapPt(const P: TVector3);
  var
    K: Integer;
  begin
    for K := 0 to CapCount - 1 do
      if PointsDistanceSqr(CapPts[K], P) < 1e-7 then
        Exit;
    if CapCount >= Length(CapPts) then
      SetLength(CapPts, Max(8, CapCount * 2));
    CapPts[CapCount] := P;
    Inc(CapCount);
  end;

  procedure AppendFaceVert(var Poly: TVoronoiFacePolygon; var Count: Integer; const P: TVector3);
  begin
    if (Count > 0) and (PointsDistanceSqr(Poly[Count - 1], P) < 1e-8) then
      Exit;
    if Count >= Length(Poly) then
      SetLength(Poly, Max(8, Count * 2));
    Poly[Count] := P;
    Inc(Count);
  end;

var
  ClipVertCount: Integer;
begin
  NewFaces := nil;
  CapPts := nil;
  CapAngles := nil;
  OutFaceCount := 0;
  CapCount := 0;

  for FIdx := 0 to High(AFaces) do
  begin
    Face := AFaces[FIdx];
    if Length(Face) < 3 then
      Continue;

    ClippedFace := nil;
    ClipVertCount := 0;
    PrevPt := Face[High(Face)];
    PrevDist := TVector3.DotProduct(PrevPt - APlanePt, AOutNormal);

    for VIdx := 0 to High(Face) do
    begin
      CurPt := Face[VIdx];
      CurDist := TVector3.DotProduct(CurPt - APlanePt, AOutNormal);

      if CurDist <= PlaneEps then
      begin
        if PrevDist > PlaneEps then
        begin
          T := Clamped(PrevDist / Max(1e-8, PrevDist - CurDist), 0.0, 1.0);
          InterPt := Lerp(T, PrevPt, CurPt);
          AppendFaceVert(ClippedFace, ClipVertCount, InterPt);
          AddUniqueCapPt(InterPt);
        end;
        AppendFaceVert(ClippedFace, ClipVertCount, CurPt);
        if Abs(CurDist) <= PlaneEps then
          AddUniqueCapPt(CurPt);
      end else
      if PrevDist <= PlaneEps then
      begin
        T := Clamped((-PrevDist) / Max(1e-8, CurDist - PrevDist), 0.0, 1.0);
        InterPt := Lerp(T, PrevPt, CurPt);
        AppendFaceVert(ClippedFace, ClipVertCount, InterPt);
        AddUniqueCapPt(InterPt);
      end;

      PrevPt := CurPt;
      PrevDist := CurDist;
    end;

    if (ClipVertCount > 1) and
       (PointsDistanceSqr(ClippedFace[0], ClippedFace[ClipVertCount - 1]) < 1e-8) then
      Dec(ClipVertCount);

    if ClipVertCount >= 3 then
    begin
      SetLength(ClippedFace, ClipVertCount);
      if OutFaceCount >= Length(NewFaces) then
        SetLength(NewFaces, Max(8, OutFaceCount * 2));
      NewFaces[OutFaceCount] := ClippedFace;
      Inc(OutFaceCount);
    end;
  end;

  if CapCount >= 3 then
  begin
    SetLength(CapPts, CapCount);
    CapCenter := TVector3.Zero;
    for I := 0 to CapCount - 1 do
      CapCenter := CapCenter + CapPts[I];
    CapCenter := CapCenter / CapCount;

    if Abs(AOutNormal.Y) < 0.9 then
      AxisU := TVector3.CrossProduct(Vector3(0.0, 1.0, 0.0), AOutNormal).Normalize
    else
      AxisU := TVector3.CrossProduct(Vector3(1.0, 0.0, 0.0), AOutNormal).Normalize;
    { AxisU x AxisV = AOutNormal }
    AxisV := TVector3.CrossProduct(AOutNormal, AxisU).Normalize;

    SetLength(CapAngles, CapCount);
    for I := 0 to CapCount - 1 do
    begin
      Rel := CapPts[I] - CapCenter;
      CapAngles[I] := ArcTan2(
        TVector3.DotProduct(Rel, AxisV),
        TVector3.DotProduct(Rel, AxisU));
    end;

    for I := 0 to CapCount - 2 do
      for J := I + 1 to CapCount - 1 do
        if CapAngles[J] < CapAngles[I] then
        begin
          TmpAngle := CapAngles[I]; CapAngles[I] := CapAngles[J]; CapAngles[J] := TmpAngle;
          TmpPt := CapPts[I]; CapPts[I] := CapPts[J]; CapPts[J] := TmpPt;
        end;

    if OutFaceCount >= Length(NewFaces) then
      SetLength(NewFaces, OutFaceCount + 1);
    NewFaces[OutFaceCount] := CapPts;
    Inc(OutFaceCount);
  end;

  SetLength(NewFaces, OutFaceCount);
  AFaces := NewFaces;
end;

function ComputeVoronoiFractureCells(
  const ABoxCenter, ABoxSize: TVector3;
  const AShardCount, ARandomSeed: Integer;
  const ACrackGap: Single): TVoronoiShardCellArray;
var
  Count, SeedBase, I, J, FIdx, VIdx, VertCount: Integer;
  SafeSize, MinP, MaxP, MarginMin, MarginMax, Span, Diff, OutNorm, PlanePt: TVector3;
  Sites: array of TVector3;
  Faces: TVoronoiFacePolygonArray;
  VertSum, V0, V1, V2, TetCentroid: TVector3;
  TetVol, TotalVol, MaxRadSqr, SafeGap: Single;
  OutCount: Integer;
begin
  Result := nil;
  Sites := nil;
  Count := Clamped(AShardCount, 2, 48);
  SafeSize := Vector3(
    Max(0.10, ABoxSize.X),
    Max(0.10, ABoxSize.Y),
    Max(0.10, ABoxSize.Z));
  MinP := ABoxCenter - SafeSize * 0.5;
  MaxP := ABoxCenter + SafeSize * 0.5;

  { Keep Voronoi nuclei inside inner 76% of the box so cells stay well-proportioned }
  MarginMin := ABoxCenter - SafeSize * 0.38;
  MarginMax := ABoxCenter + SafeSize * 0.38;
  Span := MarginMax - MarginMin;

  SeedBase := Abs(ARandomSeed * 37 + 17) mod 4093 + 1;
  SetLength(Sites, Count);
  for I := 0 to Count - 1 do
  begin
    Sites[I] := Vector3(
      MarginMin.X + HaltonRadicalInverse(SeedBase + I * 3, 2) * Span.X,
      MarginMin.Y + HaltonRadicalInverse(SeedBase + I * 5, 3) * Span.Y,
      MarginMin.Z + HaltonRadicalInverse(SeedBase + I * 7, 5) * Span.Z);
  end;

  SafeGap := Clamped(ACrackGap, 0.0, Min(Min(SafeSize.X, SafeSize.Y), SafeSize.Z) * 0.15);
  SetLength(Result, Count);
  OutCount := 0;

  for I := 0 to Count - 1 do
  begin
    Faces := BuildInitialBoxFaces(MinP, MaxP);
    for J := 0 to Count - 1 do
      if J <> I then
      begin
        Diff := Sites[J] - Sites[I];
        if Diff.LengthSqr < 1e-8 then
          Continue;
        OutNorm := Diff.Normalize;
        PlanePt := (Sites[I] + Sites[J]) * 0.5 - OutNorm * (SafeGap * 0.5);
        ClipPolyhedronByHalfSpace(Faces, PlanePt, OutNorm);
        if Length(Faces) < 4 then
          Break;
      end;

    if Length(Faces) < 4 then
      Continue;

    { Compute exact polyhedron volume & volume-weighted centroid around Sites[I] }
    TotalVol := 0.0;
    VertSum := TVector3.Zero;
    VertCount := 0;
    Result[OutCount].CentroidLocal := TVector3.Zero;

    for FIdx := 0 to High(Faces) do
    begin
      for VIdx := 0 to High(Faces[FIdx]) do
      begin
        VertSum := VertSum + Faces[FIdx][VIdx];
        Inc(VertCount);
      end;
      V0 := Faces[FIdx][0];
      for VIdx := 1 to High(Faces[FIdx]) - 1 do
      begin
        V1 := Faces[FIdx][VIdx];
        V2 := Faces[FIdx][VIdx + 1];
        TetVol := TVector3.DotProduct(
          V0 - Sites[I],
          TVector3.CrossProduct(V1 - Sites[I], V2 - Sites[I])) / 6.0;
        if TetVol > 0.0 then
        begin
          TetCentroid := (Sites[I] + V0 + V1 + V2) * 0.25;
          Result[OutCount].CentroidLocal :=
            Result[OutCount].CentroidLocal + TetCentroid * TetVol;
          TotalVol := TotalVol + TetVol;
        end;
      end;
    end;

    if TotalVol > 1e-7 then
      Result[OutCount].CentroidLocal := Result[OutCount].CentroidLocal / TotalVol
    else if VertCount > 0 then
      Result[OutCount].CentroidLocal := VertSum / VertCount
    else
      Continue;

    MaxRadSqr := 1e-4;
    for FIdx := 0 to High(Faces) do
      for VIdx := 0 to High(Faces[FIdx]) do
      begin
        Faces[FIdx][VIdx] := Faces[FIdx][VIdx] - Result[OutCount].CentroidLocal;
        MaxRadSqr := Max(MaxRadSqr, Faces[FIdx][VIdx].LengthSqr);
      end;

    Result[OutCount].SiteLocal := Sites[I];
    Result[OutCount].Volume := Max(0.0, TotalVol);
    Result[OutCount].BoundingRadius := Sqrt(MaxRadSqr);
    Result[OutCount].FacesLocal := Faces;
    Inc(OutCount);
  end;

  SetLength(Result, OutCount);
end;

procedure AttachTransientVoronoiShardMesh(const AShardTransform: TCastleTransform;
  const ACell: TVoronoiShardCell; const APreset: TDestructibleMaterialPreset;
  const AColorTintFactor: Single);
var
  PreviewScene: TCastleScene;
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
  Coord: TCoordinateNode;
  Norm: TNormalNode;
  Verts, Norms: array of TVector3;
  FIdx, VIdx, OutIdx, TriCount: Integer;
  V0, V1, V2, FaceNorm, BaseCol, EmissiveCol: TVector3;
  Rough, Metal, Restit: Single;
begin
  if AShardTransform = nil then
    Exit;

  TriCount := 0;
  for FIdx := 0 to High(ACell.FacesLocal) do
    if Length(ACell.FacesLocal[FIdx]) >= 3 then
      Inc(TriCount, Length(ACell.FacesLocal[FIdx]) - 2);
  if TriCount <= 0 then
    Exit;

  Verts := nil;
  Norms := nil;
  SetLength(Verts, TriCount * 3);
  SetLength(Norms, TriCount * 3);
  OutIdx := 0;

  for FIdx := 0 to High(ACell.FacesLocal) do
  begin
    if Length(ACell.FacesLocal[FIdx]) < 3 then
      Continue;
    V0 := ACell.FacesLocal[FIdx][0];
    for VIdx := 1 to High(ACell.FacesLocal[FIdx]) - 1 do
    begin
      V1 := ACell.FacesLocal[FIdx][VIdx];
      V2 := ACell.FacesLocal[FIdx][VIdx + 1];
      FaceNorm := TVector3.CrossProduct(V1 - V0, V2 - V0);
      if FaceNorm.LengthSqr < 1e-10 then
        FaceNorm := Vector3(0.0, 1.0, 0.0)
      else
        FaceNorm := FaceNorm.Normalize;
      Verts[OutIdx] := V0; Norms[OutIdx] := FaceNorm; Inc(OutIdx);
      Verts[OutIdx] := V1; Norms[OutIdx] := FaceNorm; Inc(OutIdx);
      Verts[OutIdx] := V2; Norms[OutIdx] := FaceNorm; Inc(OutIdx);
    end;
  end;

  GetDestructiblePresetMaterial(APreset, BaseCol, EmissiveCol, Rough, Metal, Restit);
  BaseCol := BaseCol * AColorTintFactor;

  PreviewScene := TCastleScene.Create(AShardTransform);
  PreviewScene.SetTransient;
  PreviewScene.Pickable := false;
  PreviewScene.Collides := false;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := Vector3(
    Clamped(BaseCol.X, 0.0, 1.0),
    Clamped(BaseCol.Y, 0.0, 1.0),
    Clamped(BaseCol.Z, 0.0, 1.0));
  Mat.EmissiveColor := EmissiveCol;
  Mat.Roughness := Rough;
  Mat.Metallic := Metal;
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := true;
  Coord := TCoordinateNode.Create;
  Coord.SetPoint(Verts);
  Norm := TNormalNode.Create;
  Norm.SetVector(Norms);
  TriSet.Coord := Coord;
  TriSet.Normal := Norm;
  Shape.Geometry := TriSet;

  Root.AddChildren(Shape);
  PreviewScene.Load(Root, true);
  AShardTransform.Add(PreviewScene);
end;

{ TCastleDebrisShardBehavior ------------------------------------------------- }

constructor TCastleDebrisShardBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLinearVelocity := TVector3.Zero;
  FSpinAxis := Vector3(0.0, 1.0, 0.0);
  FSpinSpeedRad := 0.0;
  FGravityY := -9.81;
  FGroundFloorY := 0.0;
  FRestitution := 0.30;
  FShardRadius := 0.12;
  FLifetimeSec := 4.0;
  FAgeSec := 0.0;
  FShrinkDurationSec := 0.75;
end;

procedure TCastleDebrisShardBehavior.StepSimulation(const ADeltaSeconds: Single;
  out OutExpired: Boolean);
var
  Dt, MinY, Remain, ScaleFactor, CurAngle: Single;
  NewPos: TVector3;
begin
  OutExpired := false;
  if (Parent = nil) or (ADeltaSeconds <= 0.0) then
  begin
    OutExpired := FAgeSec >= FLifetimeSec;
    Exit;
  end;

  Dt := Min(ADeltaSeconds, 0.25);
  FAgeSec := FAgeSec + Dt;
  if FAgeSec >= FLifetimeSec then
  begin
    OutExpired := true;
    Exit;
  end;

  FLinearVelocity.Y := FLinearVelocity.Y + FGravityY * Dt;
  NewPos := Parent.Translation + FLinearVelocity * Dt;

  MinY := FGroundFloorY + FShardRadius * 0.5;
  if NewPos.Y <= MinY then
  begin
    NewPos.Y := MinY;
    if FLinearVelocity.Y < 0.0 then
      FLinearVelocity.Y := -FLinearVelocity.Y * FRestitution;
    FLinearVelocity.X := FLinearVelocity.X * Max(0.0, 1.0 - 2.2 * Dt);
    FLinearVelocity.Z := FLinearVelocity.Z * Max(0.0, 1.0 - 2.2 * Dt);
    FSpinSpeedRad := FSpinSpeedRad * Max(0.0, 1.0 - 3.0 * Dt);
  end;

  Parent.Translation := NewPos;

  if Abs(FSpinSpeedRad) > 1e-4 then
  begin
    CurAngle := Parent.Rotation.W + FSpinSpeedRad * Dt;
    if FSpinAxis.LengthSqr < 1e-6 then
      FSpinAxis := Vector3(0.0, 1.0, 0.0);
    Parent.Rotation := Vector4(FSpinAxis.Normalize, CurAngle);
  end;

  Remain := FLifetimeSec - FAgeSec;
  if (FShrinkDurationSec > 1e-3) and (Remain < FShrinkDurationSec) then
  begin
    ScaleFactor := Clamped(Remain / FShrinkDurationSec, 0.02, 1.0);
    Parent.Scale := Vector3(ScaleFactor, ScaleFactor, ScaleFactor);
  end;
end;

procedure TCastleDebrisShardBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
var
  Expired: Boolean;
begin
  inherited;
  if not CastleDesignMode then
  begin
    StepSimulation(SecondsPassed, Expired);
    if Expired and (Parent <> nil) then
      Parent.Exists := false;
  end;
end;

{ TCastleDestructibleBehavior ------------------------------------------------ }

constructor TCastleDestructibleBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMaxHealth := DefaultMaxHealth;
  FCurrentHealth := DefaultMaxHealth;
  FShardCount := DefaultShardCount;
  FFractureSeed := DefaultFractureSeed;
  FCrackGap := DefaultCrackGap;
  FMaterialPreset := dmpStoneMasonry;
  FBlastImpulse := DefaultBlastImpulse;
  FBlastUpwardLift := DefaultBlastUpwardLift;
  FAngularImpulse := DefaultAngularImpulse;
  FDebrisLifetimeSec := DefaultDebrisLifetimeSec;
  FGroundFloorY := DefaultGroundFloorY;
  FFractureBoxSize := Vector3(1.0, 1.4, 1.0);
  FHideIntactVisualsOnFracture := true;
  FShowVoronoiPreviewInViewport := true;
  FIsFractured := false;
  FSavedParentVisible := true;
  FSavedParentCollides := true;
  FDebrisRoot := nil;

  FFractureBoxSizePersistent := TCastleVector3Persistent.Create(nil);
  FFractureBoxSizePersistent.InternalGetValue := @GetFractureBoxSizeForPersistent;
  FFractureBoxSizePersistent.InternalSetValue := @SetFractureBoxSizeForPersistent;
  FFractureBoxSizePersistent.InternalDefaultValue := FFractureBoxSize;
end;

destructor TCastleDestructibleBehavior.Destroy;
begin
  ClearDebris;
  FreeAndNil(FFractureBoxSizePersistent);
  inherited;
end;

function TCastleDestructibleBehavior.GetFractureBoxSizeForPersistent: TVector3;
begin
  Result := FFractureBoxSize;
end;

procedure TCastleDestructibleBehavior.SetFractureBoxSizeForPersistent(
  const AValue: TVector3);
begin
  SetFractureBoxSize(AValue);
end;

procedure TCastleDestructibleBehavior.SetFractureBoxSize(const Value: TVector3);
begin
  FFractureBoxSize := Vector3(
    Max(0.10, Value.X),
    Max(0.10, Value.Y),
    Max(0.10, Value.Z));
end;

procedure TCastleDestructibleBehavior.SetMaxHealth(const Value: Single);
begin
  FMaxHealth := Max(1.0, Value);
  if FCurrentHealth > FMaxHealth then
    FCurrentHealth := FMaxHealth;
end;

procedure TCastleDestructibleBehavior.SetCurrentHealth(const Value: Single);
begin
  FCurrentHealth := Clamped(Value, 0.0, FMaxHealth);
end;

procedure TCastleDestructibleBehavior.SetShardCount(const Value: Integer);
begin
  FShardCount := Clamped(Value, 2, 48);
end;

procedure TCastleDestructibleBehavior.SetCrackGap(const Value: Single);
begin
  FCrackGap := Clamped(Value, 0.0, 0.20);
end;

procedure TCastleDestructibleBehavior.SetBlastImpulse(const Value: Single);
begin
  FBlastImpulse := Max(0.0, Value);
end;

procedure TCastleDestructibleBehavior.SetDebrisLifetimeSec(const Value: Single);
begin
  FDebrisLifetimeSec := Max(0.20, Value);
end;

function TCastleDestructibleBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'MaxHealth', 'CurrentHealth', 'ShardCount', 'FractureSeed', 'CrackGap',
       'MaterialPreset', 'BlastImpulse', 'BlastUpwardLift', 'AngularImpulse',
       'DebrisLifetimeSec', 'GroundFloorY', 'FractureBoxSizePersistent',
       'HideIntactVisualsOnFracture', 'ShowVoronoiPreviewInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleDestructibleBehavior.ResolveLocalBounds(
  out OutCenter, OutSize: TVector3): Boolean;
var
  B: TBox3D;
begin
  Result := false;
  OutCenter := TVector3.Zero;
  OutSize := FFractureBoxSize;
  if Parent = nil then
    Exit;

  B := Parent.LocalBoundingBox;
  if (not B.IsEmpty) and
     (B.SizeX >= 0.08) and (B.SizeY >= 0.08) and (B.SizeZ >= 0.08) then
  begin
    OutCenter := B.Center;
    OutSize := B.Size;
  end;
  Result := true;
end;

function TCastleDestructibleBehavior.ApplyDamage(const ADamage: Single;
  const ABlastOriginWorld: TVector3): Boolean;
begin
  Result := false;
  if (ADamage <= 0.0) or FIsFractured then
    Exit;
  FCurrentHealth := Max(0.0, FCurrentHealth - ADamage);
  if FCurrentHealth <= 0.0 then
    Result := TriggerFracture(ABlastOriginWorld) > 0;
end;

function TCastleDestructibleBehavior.TriggerFracture(
  const ABlastOriginWorld: TVector3): Integer;
var
  LocalCenter, LocalSize, ShardWorldPos, PropWorldCenter, RadialDir, SpinAx: TVector3;
  BaseCol, EmissiveCol: TVector3;
  Rough, Metal, Restit, DistToBlast, Falloff, Tint: Single;
  Cells: TVoronoiShardCellArray;
  Container, ShardT: TCastleTransform;
  ShardBeh: TCastleDebrisShardBehavior;
  ParentM: TMatrix4;
  Cur: TCastleTransform;
  I: Integer;
begin
  Result := 0;
  if (Parent = nil) or (not ResolveLocalBounds(LocalCenter, LocalSize)) then
    Exit;

  ClearDebris;

  if not FIsFractured then
  begin
    FSavedParentVisible := Parent.Visible;
    FSavedParentCollides := Parent.Collides;
  end;

  if FHideIntactVisualsOnFracture then
  begin
    Parent.Visible := false;
    Parent.Collides := false;
  end;
  FIsFractured := true;
  FCurrentHealth := 0.0;

  { Accumulate Parent world matrix }
  ParentM := TMatrix4.Identity;
  Cur := Parent;
  while (Cur <> nil) and (not (Cur is TCastleAbstractRootTransform)) do
  begin
    ParentM := Cur.Transform * ParentM;
    Cur := Cur.Parent;
  end;
  PropWorldCenter := ParentM.MultPoint(LocalCenter);

  if Parent.Parent <> nil then
    Container := Parent.Parent
  else
    Container := Parent;

  Cells := ComputeVoronoiFractureCells(
    LocalCenter, LocalSize, FShardCount, FFractureSeed, FCrackGap);
  if Length(Cells) = 0 then
    Exit;

  GetDestructiblePresetMaterial(FMaterialPreset, BaseCol, EmissiveCol, Rough, Metal, Restit);

  FDebrisRoot := TCastleTransform.Create(nil);
  FDebrisRoot.SetTransient;
  FDebrisRoot.Name := Parent.Name + '_VoronoiDebris';
  Container.Add(FDebrisRoot);

  for I := 0 to High(Cells) do
  begin
    ShardWorldPos := ParentM.MultPoint(Cells[I].CentroidLocal);

    ShardT := TCastleTransform.Create(FDebrisRoot);
    ShardT.SetTransient;
    ShardT.Translation := ShardWorldPos;

    Tint := 0.86 + 0.28 * HaltonRadicalInverse(FFractureSeed + I * 11 + 3, 7);
    AttachTransientVoronoiShardMesh(ShardT, Cells[I], FMaterialPreset, Tint);

    RadialDir := ShardWorldPos - ABlastOriginWorld;
    DistToBlast := RadialDir.Length;
    if DistToBlast < 1e-4 then
      RadialDir := ShardWorldPos - PropWorldCenter;
    if RadialDir.LengthSqr < 1e-6 then
      RadialDir := Vector3(
        HaltonRadicalInverse(I + 2, 2) - 0.5,
        0.5,
        HaltonRadicalInverse(I + 2, 3) - 0.5).Normalize
    else
      RadialDir := RadialDir.Normalize;

    Falloff := 1.0 / (1.0 + 0.18 * DistToBlast);

    ShardBeh := TCastleDebrisShardBehavior.Create(ShardT);
    ShardBeh.SetTransient;
    ShardBeh.LinearVelocity :=
      RadialDir * (FBlastImpulse * Falloff * (0.85 + 0.30 * HaltonRadicalInverse(I + 5, 2))) +
      Vector3(0.0, FBlastUpwardLift * Falloff, 0.0);

    SpinAx := TVector3.CrossProduct(Vector3(0.0, 1.0, 0.0), RadialDir);
    if SpinAx.LengthSqr < 1e-5 then
      SpinAx := Vector3(1.0, 0.0, 0.0)
    else
      SpinAx := SpinAx.Normalize;
    ShardBeh.SpinAxis := SpinAx;
    ShardBeh.SpinSpeedRad := FAngularImpulse * (0.7 + 0.6 * HaltonRadicalInverse(I + 7, 3));
    ShardBeh.GroundFloorY := FGroundFloorY;
    ShardBeh.Restitution := Restit;
    ShardBeh.ShardRadius := Max(0.05, Cells[I].BoundingRadius);
    ShardBeh.LifetimeSec := FDebrisLifetimeSec;
    ShardT.AddBehavior(ShardBeh);

    FDebrisRoot.Add(ShardT);
    Inc(Result);
  end;
end;

function TCastleDestructibleBehavior.StepDebrisSimulation(
  const ADeltaSeconds: Single): Integer;
var
  I: Integer;
  ShardT: TCastleTransform;
  Beh: TCastleDebrisShardBehavior;
  Expired: Boolean;
begin
  Result := 0;
  if FDebrisRoot = nil then
    Exit;

  for I := FDebrisRoot.Count - 1 downto 0 do
  begin
    ShardT := FDebrisRoot[I];
    Beh := ShardT.FindBehavior(TCastleDebrisShardBehavior) as TCastleDebrisShardBehavior;
    if Beh <> nil then
    begin
      Beh.StepSimulation(ADeltaSeconds, Expired);
      if Expired then
      begin
        FDebrisRoot.Remove(ShardT);
        FreeAndNil(ShardT);
      end else
        Inc(Result);
    end;
  end;

  if FDebrisRoot.Count = 0 then
    ClearDebris;
end;

procedure TCastleDestructibleBehavior.ClearDebris;
begin
  if FDebrisRoot <> nil then
  begin
    if FDebrisRoot.Parent <> nil then
      FDebrisRoot.Parent.Remove(FDebrisRoot);
    FreeAndNil(FDebrisRoot);
  end;
end;

procedure TCastleDestructibleBehavior.ResetIntact;
begin
  ClearDebris;
  if FIsFractured and (Parent <> nil) then
  begin
    Parent.Visible := FSavedParentVisible;
    Parent.Collides := FSavedParentCollides;
  end;
  FIsFractured := false;
  FCurrentHealth := FMaxHealth;
end;

function TCastleDestructibleBehavior.ActiveShardCount: Integer;
begin
  if FDebrisRoot <> nil then
    Result := FDebrisRoot.Count
  else
    Result := 0;
end;

function TCastleDestructibleBehavior.GetShardTransform(
  const AIndex: Integer): TCastleTransform;
begin
  if (FDebrisRoot <> nil) and (AIndex >= 0) and (AIndex < FDebrisRoot.Count) then
    Result := FDebrisRoot[AIndex]
  else
    Result := nil;
end;

procedure TCastleDestructibleBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited;
  if (not CastleDesignMode) and (FDebrisRoot <> nil) then
    StepDebrisSimulation(SecondsPassed);
end;

function TCastleDestructibleBehavior.DestructibleSummaryBadge: String;
begin
  if FIsFractured then
    Result := Format('[Fractured:%d shards]', [ActiveShardCount])
  else
    Result := Format('[Fracture:%d cells %.0fHP]', [FShardCount, FCurrentHealth]);
end;

initialization
  RegisterSerializableComponent(TCastleDestructibleBehavior,
    ['Physics & Destruction', 'Destructible Voronoi Fracture Behavior']);
end.
