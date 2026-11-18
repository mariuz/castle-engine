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

{ Nanite-style 64v/124t meshlet cluster builder, bounding-sphere + normal-cone
  backface cluster culler, and screen-space pixel-error LOD evaluator (Phase 353). }
unit CastleMeshletCluster;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Procedural high-density source geometry presets for meshlet partitioning. }
  TMeshletSourcePreset = (
    mspCustom,
    mspHighPolyUvSphere,
    mspTwistedTorusRing,
    mspDisplacedTerrainPatch
  );

  { Per-cluster metadata matching UE Nanite / GPU mesh-shader cluster descriptors. }
  TMeshletClusterInfo = record
    ClusterIndex: Integer;
    TriangleCount: Integer;
    UniqueVertexCount: Integer;
    BoundingCenterLocal: TVector3;
    BoundingRadius: Single;
    NormalConeAxisLocal: TVector3;
    NormalConeHalfAngleRad: Single;
    ConeSinCutoff: Single;
    DegenerateCone: Boolean;
    GeometricErrorMeters: Single;
    LastCulledByBackfaceCone: Boolean;
  end;

  { Aggregated per-view cluster culling and screen-space error telemetry. }
  TMeshletViewStats = record
    TotalClusters: Integer;
    TotalTriangles: Integer;
    VisibleClusters: Integer;
    BackfaceConeCulledClusters: Integer;
    VisibleTriangles: Integer;
    CulledTrianglePercent: Single;
    MaxProjectedPixelError: Single;
    RecommendedLodTier: Integer;
  end;

  { Component that partitions dense triangle meshes into spatially coherent
    64-vertex / 124-triangle meshlets with bounding spheres and normal cones for
    O(1) per-cluster backface rejection and screen-space LOD error diagnostics. }
  TCastleMeshletClusterer = class(TCastleTransform)
  private
    FPreset: TMeshletSourcePreset;
    FMaxVerticesPerMeshlet: Integer;
    FMaxTrianglesPerMeshlet: Integer;
    FPixelErrorThreshold: Single;
    FShowColorCodedMeshlets: Boolean;
    FHideCulledClustersInPreview: Boolean;
    FSourceVertices: TVector3List;
    FSourceIndices: TInt32List;
    FTriangleClusterOwner: array of Integer;
    FClusters: array of TMeshletClusterInfo;
    FLastViewStats: TMeshletViewStats;
    FLastCameraWorldPos: TVector3;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TMeshletSourcePreset);
    procedure SetMaxVerticesPerMeshlet(const AValue: Integer);
    procedure SetMaxTrianglesPerMeshlet(const AValue: Integer);
    procedure SetPixelErrorThreshold(const AValue: Single);
    procedure SetShowColorCodedMeshlets(const AValue: Boolean);
    procedure SetHideCulledClustersInPreview(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure GeneratePresetGeometry(const APreset: TMeshletSourcePreset);
    procedure PartitionSourceIntoMeshlets;
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
    function LocalPointToWorldSafe(const LocalPt: TVector3): TVector3;
    function LocalDirToWorldSafe(const LocalDir: TVector3): TVector3;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure BuildFromTriangles(const AVertices: TVector3List; const AIndices: TInt32List);
    function ClusterCount: Integer;
    function GetClusterInfo(const AIndex: Integer): TMeshletClusterInfo;
    function SourceTriangleCount: Integer;
    function EvaluateViewMeshletCulling(const CameraWorldPos: TVector3;
      const ViewportHeightPx: Integer = 1080;
      const VerticalFovDeg: Single = 60.0): TMeshletViewStats;
    procedure RebuildClusterPreviewMesh;
    function MeshletSummaryBadge: String;
    property LastViewStats: TMeshletViewStats read FLastViewStats;
  published
    property Preset: TMeshletSourcePreset read FPreset write SetPreset default mspHighPolyUvSphere;
    property MaxVerticesPerMeshlet: Integer read FMaxVerticesPerMeshlet write SetMaxVerticesPerMeshlet default 64;
    property MaxTrianglesPerMeshlet: Integer read FMaxTrianglesPerMeshlet write SetMaxTrianglesPerMeshlet default 124;
    property PixelErrorThreshold: Single read FPixelErrorThreshold write SetPixelErrorThreshold {$ifdef FPC}default 1.5{$endif};
    property ShowColorCodedMeshlets: Boolean read FShowColorCodedMeshlets write SetShowColorCodedMeshlets default True;
    property HideCulledClustersInPreview: Boolean read FHideCulledClustersInPreview write SetHideCulledClustersInPreview default False;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function MeshletPresetToString(const APreset: TMeshletSourcePreset): String;
function MeshletClusterColorRGB(const AClusterIndex: Integer): TVector3;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function MeshletPresetToString(const APreset: TMeshletSourcePreset): String;
begin
  case APreset of
    mspCustom: Result := 'Custom Triangle Mesh';
    mspHighPolyUvSphere: Result := 'High-Poly UV Sphere (1,536 tris)';
    mspTwistedTorusRing: Result := 'Twisted Torus Ring (1,296 tris)';
    mspDisplacedTerrainPatch: Result := 'Displaced Ridge Patch (1,568 tris)';
  end;
end;

{$PUSH}{$Q-}{$R-}
function MeshletClusterColorRGB(const AClusterIndex: Integer): TVector3;
var
  H, X, C, M: Single;
  Sector: Integer;
begin
  H := Frac(Cardinal(AClusterIndex + 1) * 0.61803398875) * 6.0;
  C := 0.68;
  X := C * (1.0 - Abs(Frac(H * 0.5) * 2.0 - 1.0));
  M := 0.24;
  Sector := Floor(H) mod 6;
  case Sector of
    0: Result := Vector3(C + M, X + M, M);
    1: Result := Vector3(X + M, C + M, M);
    2: Result := Vector3(M, C + M, X + M);
    3: Result := Vector3(M, X + M, C + M);
    4: Result := Vector3(X + M, M, C + M);
  else
    Result := Vector3(C + M, M, X + M);
  end;
end;
{$POP}

{ TCastleMeshletClusterer ---------------------------------------------------- }

constructor TCastleMeshletClusterer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSourceVertices := TVector3List.Create;
  FSourceIndices := TInt32List.Create;
  FPreset := mspHighPolyUvSphere;
  FMaxVerticesPerMeshlet := 64;
  FMaxTrianglesPerMeshlet := 124;
  FPixelErrorThreshold := 1.5;
  FShowColorCodedMeshlets := True;
  FHideCulledClustersInPreview := False;
  FLastCameraWorldPos := Vector3(0, 0, 12.0);
  GeneratePresetGeometry(mspHighPolyUvSphere);
  PartitionSourceIntoMeshlets;
  EvaluateViewMeshletCulling(FLastCameraWorldPos, 1080, 60.0);
end;

destructor TCastleMeshletClusterer.Destroy;
begin
  ClearTransientScene;
  FreeAndNil(FSourceIndices);
  FreeAndNil(FSourceVertices);
  inherited Destroy;
end;

procedure TCastleMeshletClusterer.SetPreset(const AValue: TMeshletSourcePreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> mspCustom then
  begin
    GeneratePresetGeometry(AValue);
    PartitionSourceIntoMeshlets;
    EvaluateViewMeshletCulling(FLastCameraWorldPos, 1080, 60.0);
  end;
end;

procedure TCastleMeshletClusterer.SetMaxVerticesPerMeshlet(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 16, 256);
  if FMaxVerticesPerMeshlet = V then Exit;
  FMaxVerticesPerMeshlet := V;
  PartitionSourceIntoMeshlets;
  EvaluateViewMeshletCulling(FLastCameraWorldPos, 1080, 60.0);
end;

procedure TCastleMeshletClusterer.SetMaxTrianglesPerMeshlet(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 16, 512);
  if FMaxTrianglesPerMeshlet = V then Exit;
  FMaxTrianglesPerMeshlet := V;
  PartitionSourceIntoMeshlets;
  EvaluateViewMeshletCulling(FLastCameraWorldPos, 1080, 60.0);
end;

procedure TCastleMeshletClusterer.SetPixelErrorThreshold(const AValue: Single);
begin
  FPixelErrorThreshold := EnsureRange(AValue, 0.1, 32.0);
  EvaluateViewMeshletCulling(FLastCameraWorldPos, 1080, 60.0);
end;

procedure TCastleMeshletClusterer.SetShowColorCodedMeshlets(const AValue: Boolean);
begin
  if FShowColorCodedMeshlets = AValue then Exit;
  FShowColorCodedMeshlets := AValue;
  if not FShowColorCodedMeshlets then
    ClearTransientScene
  else
    RebuildClusterPreviewMesh;
end;

procedure TCastleMeshletClusterer.SetHideCulledClustersInPreview(const AValue: Boolean);
begin
  if FHideCulledClustersInPreview = AValue then Exit;
  FHideCulledClustersInPreview := AValue;
  RebuildClusterPreviewMesh;
end;

procedure TCastleMeshletClusterer.BuildFromTriangles(const AVertices: TVector3List;
  const AIndices: TInt32List);
begin
  FPreset := mspCustom;
  FSourceVertices.Clear;
  FSourceIndices.Clear;
  if (AVertices <> nil) and (AIndices <> nil) then
  begin
    FSourceVertices.Assign(AVertices);
    FSourceIndices.Assign(AIndices);
  end;
  PartitionSourceIntoMeshlets;
  EvaluateViewMeshletCulling(FLastCameraWorldPos, 1080, 60.0);
end;

procedure TCastleMeshletClusterer.GeneratePresetGeometry(const APreset: TMeshletSourcePreset);
const
  SphereSlices = 32;
  SphereStacks = 24;
  TorusMajorSegs = 36;
  TorusMinorSegs = 18;
  PatchGridN = 28;
var
  I, J, RowA, RowB: Integer;
  Phi0, Theta0, R, X, Y, Z, MajorR, MinorR, U, V, H: Single;
begin
  FSourceVertices.Clear;
  FSourceIndices.Clear;

  case APreset of
    mspHighPolyUvSphere, mspCustom:
      begin
        R := 3.5;
        for I := 0 to SphereStacks do
        begin
          Phi0 := Pi * (I / SphereStacks);
          for J := 0 to SphereSlices do
          begin
            Theta0 := 2.0 * Pi * (J / SphereSlices);
            X := R * Sin(Phi0) * Cos(Theta0);
            Y := R * Cos(Phi0);
            Z := R * Sin(Phi0) * Sin(Theta0);
            FSourceVertices.Add(Vector3(X, Y, Z));
          end;
        end;
        for I := 0 to SphereStacks - 1 do
          for J := 0 to SphereSlices - 1 do
          begin
            RowA := I * (SphereSlices + 1) + J;
            RowB := (I + 1) * (SphereSlices + 1) + J;
            { Outward CCW winding so (V1-V0) x (V2-V0) points radially outward }
            FSourceIndices.Add(RowA);
            FSourceIndices.Add(RowA + 1);
            FSourceIndices.Add(RowB + 1);

            FSourceIndices.Add(RowA);
            FSourceIndices.Add(RowB + 1);
            FSourceIndices.Add(RowB);
          end;
      end;

    mspTwistedTorusRing:
      begin
        MajorR := 3.4;
        MinorR := 1.15;
        for I := 0 to TorusMajorSegs do
        begin
          U := 2.0 * Pi * (I / TorusMajorSegs);
          for J := 0 to TorusMinorSegs do
          begin
            V := 2.0 * Pi * (J / TorusMinorSegs);
            R := MinorR * (1.0 + 0.18 * Sin(3.0 * U + V));
            X := (MajorR + R * Cos(V)) * Cos(U);
            Y := R * Sin(V);
            Z := (MajorR + R * Cos(V)) * Sin(U);
            FSourceVertices.Add(Vector3(X, Y, Z));
          end;
        end;
        for I := 0 to TorusMajorSegs - 1 do
          for J := 0 to TorusMinorSegs - 1 do
          begin
            RowA := I * (TorusMinorSegs + 1) + J;
            RowB := (I + 1) * (TorusMinorSegs + 1) + J;
            FSourceIndices.Add(RowA);
            FSourceIndices.Add(RowB);
            FSourceIndices.Add(RowB + 1);

            FSourceIndices.Add(RowA);
            FSourceIndices.Add(RowB + 1);
            FSourceIndices.Add(RowA + 1);
          end;
      end;

    mspDisplacedTerrainPatch:
      begin
        for I := 0 to PatchGridN do
          for J := 0 to PatchGridN do
          begin
            X := ((J / PatchGridN) - 0.5) * 10.0;
            Z := ((I / PatchGridN) - 0.5) * 10.0;
            H := 1.2 * Sin(X * 0.65) * Cos(Z * 0.65) + 0.35 * Cos(X * 1.4 + Z);
            FSourceVertices.Add(Vector3(X, H, Z));
          end;
        for I := 0 to PatchGridN - 1 do
          for J := 0 to PatchGridN - 1 do
          begin
            RowA := I * (PatchGridN + 1) + J;
            RowB := (I + 1) * (PatchGridN + 1) + J;
            { Outward +Y upward normal }
            FSourceIndices.Add(RowA);
            FSourceIndices.Add(RowB);
            FSourceIndices.Add(RowB + 1);

            FSourceIndices.Add(RowA);
            FSourceIndices.Add(RowB + 1);
            FSourceIndices.Add(RowA + 1);
          end;
      end;
  end;
end;

procedure TCastleMeshletClusterer.PartitionSourceIntoMeshlets;
var
  TriCount, VCount, T, I, NewUnique, SharedVerts, BestT, CurClusterIdx: Integer;
  MinB, MaxB, Span, V0, V1, V2, SumNormals, Axis, ClusterCenter, SeedCenter, SeedNormal: TVector3;
  TriCentroids: array of TVector3;
  TriNormals: array of TVector3;
  TriAssigned: array of Boolean;
  ClusterVertStamp: array of Integer;
  ActiveTriList: array of Integer;
  CurUniqueVerts, CurTris, StampId, AssignedCount: Integer;
  MaxDist, Dist, MinDot, DotVal, MaxHalfAng, AvgEdgeLen, MaxRadiusSqCap,
  CandDistSq, CandScore, BestScore: Single;

  function ComputeTriOutwardNormal(const PA, PB, PC: TVector3): TVector3;
  var
    RawN, Mid: TVector3;
  begin
    RawN := TVector3.CrossProduct(PB - PA, PC - PA);
    if RawN.LengthSqr > 1e-12 then
      Result := RawN.Normalize
    else
    begin
      Mid := (PA + PB + PC) * (1.0 / 3.0);
      if Mid.LengthSqr > 1e-8 then
        Result := Mid.Normalize
      else
        Result := Vector3(0, 1, 0);
    end;
  end;

  function HasVertexInCurrent(const VIdx: Integer): Boolean;
  begin
    Result := ClusterVertStamp[VIdx] = StampId;
  end;

  procedure FinalizeCurrentCluster;
  var
    K, TriIdx, IA, IB: Integer;
    PA, PB, TN: TVector3;
  begin
    if CurTris = 0 then Exit;
    SetLength(FClusters, CurClusterIdx + 1);
    FClusters[CurClusterIdx].ClusterIndex := CurClusterIdx;
    FClusters[CurClusterIdx].TriangleCount := CurTris;
    FClusters[CurClusterIdx].UniqueVertexCount := CurUniqueVerts;

    ClusterCenter := TVector3.Zero;
    SumNormals := TVector3.Zero;
    AvgEdgeLen := 0.0;
    for K := 0 to CurTris - 1 do
    begin
      TriIdx := ActiveTriList[K];
      FTriangleClusterOwner[TriIdx] := CurClusterIdx;
      IA := FSourceIndices[TriIdx * 3];
      IB := FSourceIndices[TriIdx * 3 + 1];
      PA := FSourceVertices[IA];
      PB := FSourceVertices[IB];
      ClusterCenter := ClusterCenter + TriCentroids[TriIdx];
      AvgEdgeLen := AvgEdgeLen + PointsDistance(PA, PB);
      SumNormals := SumNormals + TriNormals[TriIdx];
    end;
    ClusterCenter := ClusterCenter * (1.0 / CurTris);
    AvgEdgeLen := AvgEdgeLen / CurTris;
    FClusters[CurClusterIdx].BoundingCenterLocal := ClusterCenter;

    MaxDist := 0.01;
    for K := 0 to CurTris - 1 do
    begin
      TriIdx := ActiveTriList[K];
      Dist := PointsDistance(ClusterCenter, FSourceVertices[FSourceIndices[TriIdx * 3]]);
      if Dist > MaxDist then MaxDist := Dist;
      Dist := PointsDistance(ClusterCenter, FSourceVertices[FSourceIndices[TriIdx * 3 + 1]]);
      if Dist > MaxDist then MaxDist := Dist;
      Dist := PointsDistance(ClusterCenter, FSourceVertices[FSourceIndices[TriIdx * 3 + 2]]);
      if Dist > MaxDist then MaxDist := Dist;
    end;
    FClusters[CurClusterIdx].BoundingRadius := MaxDist;

    if SumNormals.LengthSqr > 1e-8 then
      Axis := SumNormals.Normalize
    else
      Axis := Vector3(0, 1, 0);
    FClusters[CurClusterIdx].NormalConeAxisLocal := Axis;

    MinDot := 1.0;
    for K := 0 to CurTris - 1 do
    begin
      TriIdx := ActiveTriList[K];
      TN := TriNormals[TriIdx];
      DotVal := TVector3.DotProduct(TN, Axis);
      if DotVal < MinDot then
        MinDot := DotVal;
    end;

    MaxHalfAng := ArcCos(EnsureRange(MinDot, -1.0, 1.0));
    FClusters[CurClusterIdx].NormalConeHalfAngleRad := MaxHalfAng;
    if MaxHalfAng >= (Pi * 0.495) then
    begin
      FClusters[CurClusterIdx].DegenerateCone := True;
      FClusters[CurClusterIdx].ConeSinCutoff := 1.0;
    end else
    begin
      FClusters[CurClusterIdx].DegenerateCone := False;
      FClusters[CurClusterIdx].ConeSinCutoff := Sin(MaxHalfAng);
    end;
    FClusters[CurClusterIdx].GeometricErrorMeters :=
      Max(0.002, AvgEdgeLen * (0.15 + 0.50 * Sin(Min(Pi * 0.5, MaxHalfAng))));
    FClusters[CurClusterIdx].LastCulledByBackfaceCone := False;
    Inc(CurClusterIdx);
  end;

  procedure AddTriangleToCurrent(const ATriIdx: Integer);
  var
    VA, VB, VC: Integer;
  begin
    VA := FSourceIndices[ATriIdx * 3];
    VB := FSourceIndices[ATriIdx * 3 + 1];
    VC := FSourceIndices[ATriIdx * 3 + 2];
    if not HasVertexInCurrent(VA) then
    begin
      ClusterVertStamp[VA] := StampId;
      Inc(CurUniqueVerts);
    end;
    if not HasVertexInCurrent(VB) then
    begin
      ClusterVertStamp[VB] := StampId;
      Inc(CurUniqueVerts);
    end;
    if not HasVertexInCurrent(VC) then
    begin
      ClusterVertStamp[VC] := StampId;
      Inc(CurUniqueVerts);
    end;
    ActiveTriList[CurTris] := ATriIdx;
    Inc(CurTris);
    TriAssigned[ATriIdx] := True;
    Inc(AssignedCount);
  end;

var
  IA, IB, IC: Integer;
begin
  SetLength(FClusters, 0);
  TriCount := FSourceIndices.Count div 3;
  VCount := FSourceVertices.Count;
  SetLength(FTriangleClusterOwner, TriCount);
  if (TriCount = 0) or (VCount = 0) then Exit;

  MinB := FSourceVertices[0];
  MaxB := FSourceVertices[0];
  for I := 1 to VCount - 1 do
  begin
    if FSourceVertices[I].X < MinB.X then MinB.X := FSourceVertices[I].X;
    if FSourceVertices[I].Y < MinB.Y then MinB.Y := FSourceVertices[I].Y;
    if FSourceVertices[I].Z < MinB.Z then MinB.Z := FSourceVertices[I].Z;
    if FSourceVertices[I].X > MaxB.X then MaxB.X := FSourceVertices[I].X;
    if FSourceVertices[I].Y > MaxB.Y then MaxB.Y := FSourceVertices[I].Y;
    if FSourceVertices[I].Z > MaxB.Z then MaxB.Z := FSourceVertices[I].Z;
  end;
  Span := MaxB - MinB;
  { Cap cluster centroid spread to ~28% of mesh diagonal so bounding spheres stay tight }
  MaxRadiusSqCap := Max(0.25, Sqr(Span.Length * 0.24));

  SetLength(TriCentroids, TriCount);
  SetLength(TriNormals, TriCount);
  SetLength(TriAssigned, TriCount);
  for T := 0 to TriCount - 1 do
  begin
    V0 := FSourceVertices[FSourceIndices[T * 3]];
    V1 := FSourceVertices[FSourceIndices[T * 3 + 1]];
    V2 := FSourceVertices[FSourceIndices[T * 3 + 2]];
    TriCentroids[T] := (V0 + V1 + V2) * (1.0 / 3.0);
    TriNormals[T] := ComputeTriOutwardNormal(V0, V1, V2);
    TriAssigned[T] := False;
  end;

  SetLength(ClusterVertStamp, VCount);
  for I := 0 to VCount - 1 do
    ClusterVertStamp[I] := 0;
  SetLength(ActiveTriList, FMaxTrianglesPerMeshlet);

  CurClusterIdx := 0;
  StampId := 1;
  AssignedCount := 0;

  for I := 0 to TriCount - 1 do
  begin
    if TriAssigned[I] then Continue;

    CurUniqueVerts := 0;
    CurTris := 0;
    SeedCenter := TriCentroids[I];
    SeedNormal := TriNormals[I];
    AddTriangleToCurrent(I);

    while (CurTris < FMaxTrianglesPerMeshlet) and (AssignedCount < TriCount) do
    begin
      BestT := -1;
      BestScore := 1e30;
      for T := I + 1 to TriCount - 1 do
      begin
        if TriAssigned[T] then Continue;
        CandDistSq := PointsDistanceSqr(TriCentroids[T], SeedCenter);
        if CandDistSq > MaxRadiusSqCap then Continue;
        if TVector3.DotProduct(TriNormals[T], SeedNormal) < 0.55 then Continue;

        IA := FSourceIndices[T * 3];
        IB := FSourceIndices[T * 3 + 1];
        IC := FSourceIndices[T * 3 + 2];
        NewUnique := 0;
        SharedVerts := 0;
        if HasVertexInCurrent(IA) then Inc(SharedVerts) else Inc(NewUnique);
        if IB <> IA then
          if HasVertexInCurrent(IB) then Inc(SharedVerts) else Inc(NewUnique);
        if (IC <> IA) and (IC <> IB) then
          if HasVertexInCurrent(IC) then Inc(SharedVerts) else Inc(NewUnique);

        if CurUniqueVerts + NewUnique > FMaxVerticesPerMeshlet then Continue;

        CandScore := CandDistSq - SharedVerts * 0.35;
        if CandScore < BestScore then
        begin
          BestScore := CandScore;
          BestT := T;
        end;
      end;

      if BestT < 0 then
        Break;
      AddTriangleToCurrent(BestT);
    end;

    FinalizeCurrentCluster;
    Inc(StampId);
  end;
end;

function TCastleMeshletClusterer.ClusterCount: Integer;
begin
  Result := Length(FClusters);
end;

function TCastleMeshletClusterer.GetClusterInfo(const AIndex: Integer): TMeshletClusterInfo;
begin
  if (AIndex >= 0) and (AIndex < Length(FClusters)) then
    Result := FClusters[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleMeshletClusterer.SourceTriangleCount: Integer;
begin
  Result := FSourceIndices.Count div 3;
end;

function TCastleMeshletClusterer.LocalPointToWorldSafe(const LocalPt: TVector3): TVector3;
begin
  if Parent <> nil then
    Result := LocalToWorld(LocalPt)
  else
    Result := Translation + LocalPt;
end;

function TCastleMeshletClusterer.LocalDirToWorldSafe(const LocalDir: TVector3): TVector3;
begin
  if Parent <> nil then
    Result := LocalToWorldDirection(LocalDir)
  else
    Result := LocalDir;
end;

function TCastleMeshletClusterer.EvaluateViewMeshletCulling(const CameraWorldPos: TVector3;
  const ViewportHeightPx: Integer; const VerticalFovDeg: Single): TMeshletViewStats;
var
  I: Integer;
  CenterW, AxisW, CamToCenter, DirCamToCenter: TVector3;
  Dist, Radius, SinBeta, CosBeta, CosTheta, SinTheta, CosThetaPlusBeta,
  ProjScale, PixErr: Single;
  Culled: Boolean;
begin
  FLastCameraWorldPos := CameraWorldPos;
  FillChar(Result, SizeOf(Result), 0);
  Result.TotalClusters := Length(FClusters);
  Result.TotalTriangles := SourceTriangleCount;
  if Result.TotalClusters = 0 then
  begin
    FLastViewStats := Result;
    Exit;
  end;

  ProjScale := Max(64, ViewportHeightPx) /
    (2.0 * Tan(DegToRad(EnsureRange(VerticalFovDeg, 15.0, 120.0)) * 0.5));

  for I := 0 to High(FClusters) do
  begin
    CenterW := LocalPointToWorldSafe(FClusters[I].BoundingCenterLocal);
    AxisW := LocalDirToWorldSafe(FClusters[I].NormalConeAxisLocal);
    if AxisW.LengthSqr > 1e-8 then
      AxisW := AxisW.Normalize
    else
      AxisW := Vector3(0, 1, 0);

    Radius := FClusters[I].BoundingRadius;
    CamToCenter := CenterW - CameraWorldPos;
    Dist := CamToCenter.Length;

    Culled := False;
    if (not FClusters[I].DegenerateCone) and (Dist > Radius + 1e-4) then
    begin
      DirCamToCenter := CamToCenter * (1.0 / Dist);
      CosTheta := TVector3.DotProduct(DirCamToCenter, AxisW);
      SinBeta := Radius / Dist;
      { Only when theta + beta < 90 deg (i.e. CosTheta > SinBeta) can all rays lie
        within < 90 deg of the outward normal cone! }
      if CosTheta > SinBeta then
      begin
        CosBeta := Sqrt(Max(0.0, 1.0 - SinBeta * SinBeta));
        SinTheta := Sqrt(Max(0.0, 1.0 - CosTheta * CosTheta));
        CosThetaPlusBeta := CosTheta * CosBeta - SinTheta * SinBeta;
        if CosThetaPlusBeta > FClusters[I].ConeSinCutoff then
          Culled := True;
      end;
    end;

    FClusters[I].LastCulledByBackfaceCone := Culled;
    if Culled then
      Inc(Result.BackfaceConeCulledClusters)
    else
    begin
      Inc(Result.VisibleClusters);
      Inc(Result.VisibleTriangles, FClusters[I].TriangleCount);
      PixErr := (FClusters[I].GeometricErrorMeters / Max(0.25, Dist - Radius)) * ProjScale;
      if PixErr > Result.MaxProjectedPixelError then
        Result.MaxProjectedPixelError := PixErr;
    end;
  end;

  if Result.TotalTriangles > 0 then
    Result.CulledTrianglePercent :=
      100.0 * (Result.TotalTriangles - Result.VisibleTriangles) / Result.TotalTriangles;

  if Result.MaxProjectedPixelError > FPixelErrorThreshold * 2.0 then
    Result.RecommendedLodTier := 0
  else if Result.MaxProjectedPixelError > FPixelErrorThreshold then
    Result.RecommendedLodTier := 1
  else
    Result.RecommendedLodTier := 2;

  FLastViewStats := Result;
  if FShowColorCodedMeshlets then
    RebuildClusterPreviewMesh;
end;

procedure TCastleMeshletClusterer.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientMeshletClusters';
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;
  FTransientScene.CastShadows := False;
  FTransientScene.RenderOptions.Lighting := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  FCoordNode := TCoordinateNode.Create;
  FColorNode := TColorNode.Create;
  TriSet.Coord := FCoordNode;
  TriSet.Color := FColorNode;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);
  FTransientScene.Load(Root, True);
  Add(FTransientScene);
end;

procedure TCastleMeshletClusterer.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleMeshletClusterer.RebuildClusterPreviewMesh;
var
  Verts, Cols: TVector3List;
  T, TriCount, CIdx: Integer;
  Col: TVector3;
begin
  if not FShowColorCodedMeshlets then Exit;
  EnsureTransientScene;
  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    TriCount := SourceTriangleCount;
    for T := 0 to TriCount - 1 do
    begin
      CIdx := FTriangleClusterOwner[T];
      if (CIdx >= 0) and (CIdx < Length(FClusters)) and FClusters[CIdx].LastCulledByBackfaceCone then
      begin
        if FHideCulledClustersInPreview then
          Continue;
        Col := MeshletClusterColorRGB(CIdx) * 0.22;
      end else
        Col := MeshletClusterColorRGB(CIdx);

      Verts.Add(FSourceVertices[FSourceIndices[T * 3]]);
      Verts.Add(FSourceVertices[FSourceIndices[T * 3 + 1]]);
      Verts.Add(FSourceVertices[FSourceIndices[T * 3 + 2]]);
      Cols.Add(Col);
      Cols.Add(Col);
      Cols.Add(Col);
    end;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleMeshletClusterer.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('maxVerts', FMaxVerticesPerMeshlet);
    Obj.Add('maxTris', FMaxTrianglesPerMeshlet);
    Obj.Add('pixelErr', FPixelErrorThreshold);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleMeshletClusterer.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      FMaxVerticesPerMeshlet := EnsureRange(Obj.Get('maxVerts', FMaxVerticesPerMeshlet), 16, 256);
      FMaxTrianglesPerMeshlet := EnsureRange(Obj.Get('maxTris', FMaxTrianglesPerMeshlet), 16, 512);
      FPixelErrorThreshold := EnsureRange(Obj.Get('pixelErr', FPixelErrorThreshold), 0.1, 32.0);
      PresetOrd := Obj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TMeshletSourcePreset))) and
         (PresetOrd <= Ord(High(TMeshletSourcePreset))) then
      begin
        FPreset := TMeshletSourcePreset(PresetOrd);
        if FPreset <> mspCustom then
          GeneratePresetGeometry(FPreset);
      end;
      PartitionSourceIntoMeshlets;
      EvaluateViewMeshletCulling(FLastCameraWorldPos, 1080, 60.0);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleMeshletClusterer.MeshletSummaryBadge: String;
begin
  Result := Format('[Meshlet:%d/%d vis -%.0f%% tris LOD%d]', [
    FLastViewStats.VisibleClusters,
    FLastViewStats.TotalClusters,
    FLastViewStats.CulledTrianglePercent,
    FLastViewStats.RecommendedLodTier]);
end;

initialization
  RegisterSerializableComponent(TCastleMeshletClusterer, ['Rendering', 'Nanite Meshlet Clusterer & Cone Culler']);
end.
