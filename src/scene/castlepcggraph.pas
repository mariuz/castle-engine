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

{ Unreal Engine 5.5-style Procedural Content Generation (PCG) visual node graph
  component (@link(TCastlePcgGraph)), point-cloud attribute stream (@link(TPcgPoint)),
  spatial Difference / Union / Self-Pruning operators, per-node point inspection,
  and deterministic transient mesh spawning (Phase 382 — UE 5.5 UPCGGraph Parity). }
unit CastlePcgGraph;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors, X3DNodes;

type
  { PCG graph node operators matching Unreal Engine 5.5 UPCGGraph nodes. }
  TPcgNodeKind = (
    { Samplers }
    pnkSurfaceSampler,
    pnkSplineSampler,
    { Point Modifiers & Noise }
    pnkDensityNoise,
    pnkBoundsModifier,
    pnkTransformPoints,
    { Filters }
    pnkDensityFilter,
    pnkNormalSlopeFilter,
    { Spatial Set Operations }
    pnkDifference,
    pnkUnion,
    pnkSelfPruning,
    { Terminal Spawner }
    pnkStaticMeshSpawner
  );

  { Procedural primitive shape used by StaticMeshSpawner when MeshUrl is empty. }
  TPcgPrimitiveMeshKind = (
    pmkBox,
    pmkPineCylinder,
    pmkBoulderSphere
  );

  { Built-in UE5 PCG starter graph presets. }
  TPcgGraphPreset = (
    pgpCustom,
    pgpForestWithRoadClearing,
    pgpRockOutcropAndShrubUnion,
    pgpSplineFenceColonnade
  );

  { Single point inside a PCG point-cloud stream (UE 5.5 FPCGPoint parity). }
  TPcgPoint = record
    Position: TVector3;
    SurfaceNormal: TVector3;
    RotationYawDeg: Single;
    Scale: TVector3;
    BoundsHalfExtents: TVector3;
    Density: Single;
    Steepness: Single;
    Seed: Cardinal;
    Color: TVector3;
  end;
  TPcgPointArray = array of TPcgPoint;

  { Node instance inside a @link(TCastlePcgGraph) directed acyclic pipeline. }
  TPcgGraphNode = record
    NodeId: String;
    Kind: TPcgNodeKind;
    PosX: Single;
    PosY: Single;
    Enabled: Boolean;
    { Node-specific parameters:
      - SurfaceSampler: ParamA = CellStep (m), ParamB = Looseness (0..1), VecA = PointHalfExtents
      - SplineSampler:  ParamA = StepDist (m), VecA = StartLocal, VecB = EndLocal, ParamB = CorridorHalfWidth
      - DensityNoise:   ParamA = Frequency, ParamB = MinDensity, ParamC = MaxDensity
      - BoundsModifier: ParamA = BoundsScaleFactor
      - TransformPoints:ParamA = YawMaxDeg, ParamB = ScaleMin, ParamC = ScaleMax, VecA = MaxOffsetXYZ
      - DensityFilter:  ParamA = LowerBound, ParamB = UpperBound, BoolFlag = InvertFilter
      - NormalSlopeFilter: ParamA = MinSlopeDeg, ParamB = MaxSlopeDeg
      - Difference:     BoolFlag = BinaryRemove (True = hard remove overlaps, False = continuous density)
      - SelfPruning:    ParamA = RadiusScale (multiplier on XY BoundsHalfExtents)
      - StaticMeshSpawner: PrimKind, AssetUrl, VecA = BaseSizeXYZ, VecB = ColorRGB }
    ParamA: Single;
    ParamB: Single;
    ParamC: Single;
    BoolFlag: Boolean;
    VecA: TVector3;
    VecB: TVector3;
    PrimKind: TPcgPrimitiveMeshKind;
    AssetUrl: String;
    { Incoming upstream NodeIds (Pin 0 = Primary/Source, Pin 1 = Secondary/Differences) }
    InputNode0: String;
    InputNode1: String;
    { Cached telemetry from most recent ExecuteGraph / EvaluateNodeOutput }
    LastOutputCount: Integer;
  end;
  TPcgGraphNodeArray = array of TPcgGraphNode;

  { Unreal Engine 5.5-style PCG Volume & Directed Point-Cloud Node Graph. }
  TCastlePcgGraph = class(TCastleTransform)
  private
    FPreset: TPcgGraphPreset;
    FGraphSeed: Integer;
    FVolumeHalfExtents: TVector3;
    FProjectToWorldRay: Boolean;
    FAutoExecuteOnLoad: Boolean;
    FNodes: TPcgGraphNodeArray;

    FValidationErrors: TStringList;
    FSpawnContainer: TCastleTransform;
    FSpawnedMeshCount: Integer;
    FLastExecutionValid: Boolean;

    procedure SetPreset(const AValue: TPcgGraphPreset);
    procedure SetGraphSeed(const AValue: Integer);
    function GetGraphJson: String;
    procedure SetGraphJson(const AValue: String);

    procedure ClearSpawnedMeshes;
    procedure EnsureSpawnContainer;
    function EvaluateNodeRecursive(const ANodeIdx: Integer;
      var VisitState: array of Byte;
      var CachedValid: array of Boolean;
      var CachedStreams: array of TPcgPointArray): TPcgPointArray;
    procedure InstantiateSpawnerMeshes(const ANode: TPcgGraphNode;
      const APoints: TPcgPointArray);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Node metadata helpers }
    class function NodeKindTitle(const AKind: TPcgNodeKind): String; static;
    class function NodeInputPinCount(const AKind: TPcgNodeKind): Integer; static;
    class function NodeInputPinName(const AKind: TPcgNodeKind; const PinIdx: Integer): String; static;
    class function MakeDefaultNode(const ANodeId: String; const AKind: TPcgNodeKind;
      const AX: Single = 60; const AY: Single = 80): TPcgGraphNode; static;

    { Deterministic spatial hash helpers }
    class function HashUint32(const AValue: Cardinal): Cardinal; static;
    class function HashFloat01(const ASeed: Cardinal; const ASalt: Cardinal): Single; static;
    class function ValueNoise3D(const P: TVector3; const ASeed: Cardinal): Single; static;
    class function PointsBoundsOverlap3D(const A, B: TPcgPoint;
      const ARadiusScale: Single = 1.0): Boolean; static;

    { Graph authoring API }
    procedure ClearGraph;
    procedure ApplyPreset(const APreset: TPcgGraphPreset);
    function FindNodeIndex(const ANodeId: String): Integer;
    function AddOrUpdateNode(const ANode: TPcgGraphNode): Integer;
    function RemoveNode(const ANodeId: String): Boolean;
    function SetNodePosition(const ANodeId: String; const AX, AY: Single): Boolean;
    function ConnectNodes(const AFromNodeId, AToNodeId: String;
      const AToInputPin: Integer = 0): Boolean;

    { DAG Validation, Per-Node Point Inspection & Full Execution }
    function ValidateGraph: Boolean;
    function EvaluateNodeOutput(const ANodeId: String;
      out OutPoints: TPcgPointArray): Boolean;
    function ExecuteGraph: Boolean;

    function PcgSummaryBadge: String;

    property Nodes: TPcgGraphNodeArray read FNodes;
    property ValidationErrors: TStringList read FValidationErrors;
    property SpawnedMeshCount: Integer read FSpawnedMeshCount;
    property LastExecutionValid: Boolean read FLastExecutionValid;
    property VolumeHalfExtents: TVector3 read FVolumeHalfExtents write FVolumeHalfExtents;
  published
    property GraphSeed: Integer read FGraphSeed write SetGraphSeed default 1337;
    property ProjectToWorldRay: Boolean read FProjectToWorldRay write FProjectToWorldRay default True;
    property AutoExecuteOnLoad: Boolean read FAutoExecuteOnLoad write FAutoExecuteOnLoad default True;
    property GraphJson: String read GetGraphJson write SetGraphJson;
    property Preset: TPcgGraphPreset read FPreset write SetPreset default pgpForestWithRoadClearing;
  end;

implementation

uses
  fpjson, jsonparser;

{ Deterministic Hashing & Spatial 3D Value Noise ----------------------------- }

class function TCastlePcgGraph.HashUint32(const AValue: Cardinal): Cardinal;
var
  X: Cardinal;
begin
  {$PUSH}{$R-}{$Q-}
  X := AValue;
  X := (X xor (X shr 16)) * Cardinal($7FEB352D);
  X := (X xor (X shr 15)) * Cardinal($846CA68B);
  X := X xor (X shr 16);
  Result := X;
  {$POP}
end;

class function TCastlePcgGraph.HashFloat01(const ASeed: Cardinal;
  const ASalt: Cardinal): Single;
var
  H: Cardinal;
begin
  {$PUSH}{$R-}{$Q-}
  H := HashUint32(ASeed xor (ASalt * Cardinal($9E3779B9)));
  {$POP}
  Result := (H and $00FFFFFF) / 16777215.0;
end;

class function TCastlePcgGraph.ValueNoise3D(const P: TVector3;
  const ASeed: Cardinal): Single;

  function LatticeVal(const IX, IY, IZ: Integer): Single;
  var
    Mix: Cardinal;
  begin
    {$PUSH}{$R-}{$Q-}
    Mix := ASeed
      xor (Cardinal(IX) * Cardinal(73856093))
      xor (Cardinal(IY) * Cardinal(19349663))
      xor (Cardinal(IZ) * Cardinal(83492791));
    {$POP}
    Result := HashFloat01(Mix, $517CC1B7);
  end;

var
  X0, Y0, Z0: Integer;
  FX, FY, FZ, UX, UY, UZ: Single;
  C000, C100, C010, C110, C001, C101, C011, C111: Single;
  X00, X10, X01, X11, Y0V, Y1V: Single;
begin
  X0 := Floor(P.X);
  Y0 := Floor(P.Y);
  Z0 := Floor(P.Z);
  FX := P.X - X0;
  FY := P.Y - Y0;
  FZ := P.Z - Z0;
  UX := FX * FX * (3.0 - 2.0 * FX);
  UY := FY * FY * (3.0 - 2.0 * FY);
  UZ := FZ * FZ * (3.0 - 2.0 * FZ);

  C000 := LatticeVal(X0,     Y0,     Z0);
  C100 := LatticeVal(X0 + 1, Y0,     Z0);
  C010 := LatticeVal(X0,     Y0 + 1, Z0);
  C110 := LatticeVal(X0 + 1, Y0 + 1, Z0);
  C001 := LatticeVal(X0,     Y0,     Z0 + 1);
  C101 := LatticeVal(X0 + 1, Y0,     Z0 + 1);
  C011 := LatticeVal(X0,     Y0 + 1, Z0 + 1);
  C111 := LatticeVal(X0 + 1, Y0 + 1, Z0 + 1);

  X00 := Lerp(UX, C000, C100);
  X10 := Lerp(UX, C010, C110);
  X01 := Lerp(UX, C001, C101);
  X11 := Lerp(UX, C011, C111);
  Y0V := Lerp(UY, X00, X10);
  Y1V := Lerp(UY, X01, X11);
  Result := EnsureRange(Lerp(UZ, Y0V, Y1V), 0.0, 1.0);
end;

class function TCastlePcgGraph.PointsBoundsOverlap3D(
  const A, B: TPcgPoint; const ARadiusScale: Single): Boolean;
var
  ScaleK: Single;
  AX, AY, AZ, BX, BY, BZ: Single;
begin
  ScaleK := Max(0.05, ARadiusScale);
  AX := A.BoundsHalfExtents.X * A.Scale.X * ScaleK;
  AY := A.BoundsHalfExtents.Y * A.Scale.Y * ScaleK;
  AZ := A.BoundsHalfExtents.Z * A.Scale.Z * ScaleK;
  BX := B.BoundsHalfExtents.X * B.Scale.X * ScaleK;
  BY := B.BoundsHalfExtents.Y * B.Scale.Y * ScaleK;
  BZ := B.BoundsHalfExtents.Z * B.Scale.Z * ScaleK;

  Result :=
    (Abs(A.Position.X - B.Position.X) < (AX + BX)) and
    (Abs(A.Position.Y - B.Position.Y) < (AY + BY)) and
    (Abs(A.Position.Z - B.Position.Z) < (AZ + BZ));
end;

{ TCastlePcgGraph ------------------------------------------------------------ }

constructor TCastlePcgGraph.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGraphSeed := 1337;
  FVolumeHalfExtents := Vector3(12.0, 8.0, 12.0);
  FProjectToWorldRay := True;
  FAutoExecuteOnLoad := True;
  FValidationErrors := TStringList.Create;
  ApplyPreset(pgpForestWithRoadClearing);
end;

destructor TCastlePcgGraph.Destroy;
begin
  ClearSpawnedMeshes;
  FreeAndNil(FValidationErrors);
  inherited;
end;

procedure TCastlePcgGraph.Loaded;
begin
  inherited;
  if FAutoExecuteOnLoad then
    ExecuteGraph;
end;

function TCastlePcgGraph.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'GraphSeed') or
     (PropertyName = 'ProjectToWorldRay') or
     (PropertyName = 'AutoExecuteOnLoad') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastlePcgGraph.SetPreset(const AValue: TPcgGraphPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastlePcgGraph.SetGraphSeed(const AValue: Integer);
begin
  if FGraphSeed <> AValue then
  begin
    FGraphSeed := AValue;
    if not (csLoading in ComponentState) then
      ExecuteGraph;
  end;
end;

class function TCastlePcgGraph.NodeKindTitle(const AKind: TPcgNodeKind): String;
begin
  case AKind of
    pnkSurfaceSampler:    Result := 'Surface Sampler';
    pnkSplineSampler:     Result := 'Spline Sampler';
    pnkDensityNoise:      Result := 'Density Noise';
    pnkBoundsModifier:    Result := 'Bounds Modifier';
    pnkTransformPoints:   Result := 'Transform Points';
    pnkDensityFilter:     Result := 'Density Filter';
    pnkNormalSlopeFilter: Result := 'Normal Slope Filter';
    pnkDifference:        Result := 'Difference (A - B)';
    pnkUnion:             Result := 'Union (A + B)';
    pnkSelfPruning:       Result := 'Self Pruning';
    pnkStaticMeshSpawner: Result := 'Static Mesh Spawner';
  end;
end;

class function TCastlePcgGraph.NodeInputPinCount(const AKind: TPcgNodeKind): Integer;
begin
  case AKind of
    pnkSurfaceSampler, pnkSplineSampler: Result := 0;
    pnkDifference, pnkUnion:             Result := 2;
  else
    Result := 1;
  end;
end;

class function TCastlePcgGraph.NodeInputPinName(const AKind: TPcgNodeKind;
  const PinIdx: Integer): String;
begin
  case AKind of
    pnkDifference:
      if PinIdx = 0 then Result := 'Source' else Result := 'Differences';
    pnkUnion:
      if PinIdx = 0 then Result := 'Stream A' else Result := 'Stream B';
  else
    Result := 'In';
  end;
end;

class function TCastlePcgGraph.MakeDefaultNode(const ANodeId: String;
  const AKind: TPcgNodeKind; const AX, AY: Single): TPcgGraphNode;
begin
  Result := Default(TPcgGraphNode);
  Result.NodeId := ANodeId;
  Result.Kind := AKind;
  Result.PosX := AX;
  Result.PosY := AY;
  Result.Enabled := True;

  case AKind of
    pnkSurfaceSampler:
      begin
        Result.ParamA := 2.4;  { Cell step (m) }
        Result.ParamB := 0.35; { Looseness jitter }
        Result.VecA := Vector3(0.95, 2.0, 0.95); { Point half-extents }
      end;
    pnkSplineSampler:
      begin
        Result.ParamA := 1.5;  { Step along spline (m) }
        Result.ParamB := 2.2;  { Corridor half-width (m) }
        Result.VecA := Vector3(-12.0, 0.0, 0.0);
        Result.VecB := Vector3(12.0, 0.0, 0.0);
      end;
    pnkDensityNoise:
      begin
        Result.ParamA := 0.18; { Frequency }
        Result.ParamB := 0.05; { MinDensity }
        Result.ParamC := 1.00; { MaxDensity }
      end;
    pnkBoundsModifier:
      Result.ParamA := 1.5;
    pnkTransformPoints:
      begin
        Result.ParamA := 360.0; { Random yaw range }
        Result.ParamB := 0.85;  { Uniform scale min }
        Result.ParamC := 1.30;  { Uniform scale max }
        Result.VecA := Vector3(0.25, 0.0, 0.25);
      end;
    pnkDensityFilter:
      begin
        Result.ParamA := 0.38; { LowerBound }
        Result.ParamB := 1.00; { UpperBound }
        Result.BoolFlag := False;
      end;
    pnkNormalSlopeFilter:
      begin
        Result.ParamA := 0.0;  { MinSlopeDeg }
        Result.ParamB := 30.0; { MaxSlopeDeg }
      end;
    pnkDifference:
      Result.BoolFlag := True; { Binary hard exclusion }
    pnkSelfPruning:
      Result.ParamA := 1.0;    { Bounds radius scale }
    pnkStaticMeshSpawner:
      begin
        Result.PrimKind := pmkPineCylinder;
        Result.VecA := Vector3(0.7, 2.8, 0.7);
        Result.VecB := Vector3(0.20, 0.58, 0.26);
      end;
  end;
end;

procedure TCastlePcgGraph.ClearSpawnedMeshes;
begin
  if FSpawnContainer <> nil then
    FreeAndNil(FSpawnContainer);
  FSpawnedMeshCount := 0;
end;

procedure TCastlePcgGraph.EnsureSpawnContainer;
begin
  if FSpawnContainer = nil then
  begin
    FSpawnContainer := TCastleTransform.Create(nil);
    FSpawnContainer.SetTransient;
    FSpawnContainer.Name := 'PCG_SpawnedInstances';
    Add(FSpawnContainer);
  end;
end;

procedure TCastlePcgGraph.ClearGraph;
begin
  ClearSpawnedMeshes;
  FNodes := nil;
  FValidationErrors.Clear;
  FLastExecutionValid := False;
end;

function TCastlePcgGraph.FindNodeIndex(const ANodeId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if SameText(FNodes[I].NodeId, ANodeId) then
      Exit(I);
  Result := -1;
end;

function TCastlePcgGraph.AddOrUpdateNode(const ANode: TPcgGraphNode): Integer;
begin
  Result := FindNodeIndex(ANode.NodeId);
  if Result < 0 then
  begin
    Result := Length(FNodes);
    SetLength(FNodes, Result + 1);
  end;
  FNodes[Result] := ANode;
end;

function TCastlePcgGraph.RemoveNode(const ANodeId: String): Boolean;
var
  Idx, I: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then Exit(False);
  for I := 0 to High(FNodes) do
  begin
    if SameText(FNodes[I].InputNode0, ANodeId) then FNodes[I].InputNode0 := '';
    if SameText(FNodes[I].InputNode1, ANodeId) then FNodes[I].InputNode1 := '';
  end;
  for I := Idx to High(FNodes) - 1 do
    FNodes[I] := FNodes[I + 1];
  SetLength(FNodes, Length(FNodes) - 1);
  Result := True;
end;

function TCastlePcgGraph.SetNodePosition(const ANodeId: String;
  const AX, AY: Single): Boolean;
var
  Idx: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then Exit(False);
  FNodes[Idx].PosX := AX;
  FNodes[Idx].PosY := AY;
  Result := True;
end;

function TCastlePcgGraph.ConnectNodes(const AFromNodeId, AToNodeId: String;
  const AToInputPin: Integer): Boolean;
var
  ToIdx: Integer;
begin
  if (FindNodeIndex(AFromNodeId) < 0) then Exit(False);
  ToIdx := FindNodeIndex(AToNodeId);
  if ToIdx < 0 then Exit(False);
  if AToInputPin = 1 then
    FNodes[ToIdx].InputNode1 := AFromNodeId
  else
    FNodes[ToIdx].InputNode0 := AFromNodeId;
  Result := True;
end;

{ Validation ----------------------------------------------------------------- }

function TCastlePcgGraph.ValidateGraph: Boolean;
var
  I, J: Integer;
  Colors: array of Byte;

  function HasCycleDfs(const Idx: Integer): Boolean;
  var
    In0, In1: Integer;
  begin
    Result := False;
    Colors[Idx] := 1;
    if FNodes[Idx].InputNode0 <> '' then
    begin
      In0 := FindNodeIndex(FNodes[Idx].InputNode0);
      if In0 >= 0 then
      begin
        if Colors[In0] = 1 then Exit(True);
        if (Colors[In0] = 0) and HasCycleDfs(In0) then Exit(True);
      end;
    end;
    if FNodes[Idx].InputNode1 <> '' then
    begin
      In1 := FindNodeIndex(FNodes[Idx].InputNode1);
      if In1 >= 0 then
      begin
        if Colors[In1] = 1 then Exit(True);
        if (Colors[In1] = 0) and HasCycleDfs(In1) then Exit(True);
      end;
    end;
    Colors[Idx] := 2;
  end;

begin
  FValidationErrors.Clear;

  for I := 0 to High(FNodes) do
  begin
    if Trim(FNodes[I].NodeId) = '' then
      FValidationErrors.Add('PCG node has an empty NodeId.');
    for J := I + 1 to High(FNodes) do
      if SameText(FNodes[I].NodeId, FNodes[J].NodeId) then
        FValidationErrors.Add(Format('Duplicate PCG NodeId "%s".', [FNodes[I].NodeId]));

    if (FNodes[I].InputNode0 <> '') and (FindNodeIndex(FNodes[I].InputNode0) < 0) then
      FValidationErrors.Add(Format('Node "%s" Input 0 references missing node "%s".',
        [FNodes[I].NodeId, FNodes[I].InputNode0]));

    if (FNodes[I].InputNode1 <> '') and (FindNodeIndex(FNodes[I].InputNode1) < 0) then
      FValidationErrors.Add(Format('Node "%s" Input 1 references missing node "%s".',
        [FNodes[I].NodeId, FNodes[I].InputNode1]));
  end;

  SetLength(Colors, Length(FNodes));
  for I := 0 to High(Colors) do Colors[I] := 0;
  for I := 0 to High(FNodes) do
    if (Colors[I] = 0) and HasCycleDfs(I) then
      FValidationErrors.Add(Format('Directed cycle detected in PCG graph at node "%s".',
        [FNodes[I].NodeId]));

  Result := FValidationErrors.Count = 0;
end;

{ Point-Cloud Pipeline Operators --------------------------------------------- }

function TCastlePcgGraph.EvaluateNodeRecursive(const ANodeIdx: Integer;
  var VisitState: array of Byte;
  var CachedValid: array of Boolean;
  var CachedStreams: array of TPcgPointArray): TPcgPointArray;
var
  N: TPcgGraphNode;
  In0Idx, In1Idx: Integer;
  Stream0, Stream1: TPcgPointArray;
  Step, Looseness, PX, PZ, SegLen, DistAlong, TParam, SlopeDeg, DotUp,
  NoiseVal, LowerD, UpperD, ScaleU, YawDeg: Single;
  GX, GZ, Nx, Nz, I, J, OutCnt, StepsCount: Integer;
  PtSeed, GraphSeedU: Cardinal;
  Pt, TempPt: TPcgPoint;
  RayHit: TRayCollision;
  HitPos, HitNorm, WorldOrigin, DirVec: TVector3;
  KeepPt, OverlapsAny, HasWorldSurfaces, FoundRayHit: Boolean;

  function IsSelfOrDescendant(const AItem: TCastleTransform): Boolean;
  var
    Cur: TCastleTransform;
  begin
    Cur := AItem;
    while Cur <> nil do
    begin
      if Cur = Self then Exit(True);
      Cur := Cur.Parent;
    end;
    Result := False;
  end;

begin
  Result := nil;
  if (ANodeIdx < 0) or (ANodeIdx > High(FNodes)) then Exit;
  if CachedValid[ANodeIdx] then
    Exit(CachedStreams[ANodeIdx]);
  if VisitState[ANodeIdx] = 1 then
    Exit; { Cycle guard }

  VisitState[ANodeIdx] := 1;
  N := FNodes[ANodeIdx];
  {$PUSH}{$R-}{$Q-}
  GraphSeedU := Cardinal(FGraphSeed);
  {$POP}

  Stream0 := nil;
  Stream1 := nil;
  if (NodeInputPinCount(N.Kind) >= 1) and (N.InputNode0 <> '') then
  begin
    In0Idx := FindNodeIndex(N.InputNode0);
    if In0Idx >= 0 then
      Stream0 := EvaluateNodeRecursive(In0Idx, VisitState, CachedValid, CachedStreams);
  end;
  if (NodeInputPinCount(N.Kind) >= 2) and (N.InputNode1 <> '') then
  begin
    In1Idx := FindNodeIndex(N.InputNode1);
    if In1Idx >= 0 then
      Stream1 := EvaluateNodeRecursive(In1Idx, VisitState, CachedValid, CachedStreams);
  end;

  if not N.Enabled then
  begin
    Result := Copy(Stream0);
    FNodes[ANodeIdx].LastOutputCount := Length(Result);
    CachedStreams[ANodeIdx] := Result;
    CachedValid[ANodeIdx] := True;
    VisitState[ANodeIdx] := 2;
    Exit;
  end;

  case N.Kind of
    pnkSurfaceSampler:
      begin
        Step := Max(0.35, N.ParamA);
        Looseness := EnsureRange(N.ParamB, 0.0, 1.0);
        Nx := Max(1, Floor((FVolumeHalfExtents.X * 2.0) / Step));
        Nz := Max(1, Floor((FVolumeHalfExtents.Z * 2.0) / Step));
        SetLength(Result, (Nx + 1) * (Nz + 1));
        OutCnt := 0;
        HasWorldSurfaces := False;
        if FProjectToWorldRay and (World <> nil) then
          for J := 0 to World.Count - 1 do
            if (World[J] <> Self) and
               (not (csTransient in World[J].ComponentStyle)) and
               (not World[J].BoundingBox.IsEmpty) then
            begin
              HasWorldSurfaces := True;
              Break;
            end;

        for GZ := 0 to Nz do
          for GX := 0 to Nx do
          begin
            {$PUSH}{$R-}{$Q-}
            PtSeed := HashUint32(GraphSeedU xor (Cardinal(GX) * Cardinal(73856093)) xor (Cardinal(GZ) * Cardinal(83492791)));
            {$POP}
            PX := -FVolumeHalfExtents.X + GX * Step +
              (HashFloat01(PtSeed, 11) - 0.5) * Step * Looseness;
            PZ := -FVolumeHalfExtents.Z + GZ * Step +
              (HashFloat01(PtSeed, 23) - 0.5) * Step * Looseness;

            HitPos := Vector3(PX, 0.0, PZ);
            HitNorm := Vector3(0.0, 1.0, 0.0);
            FoundRayHit := False;

            if FProjectToWorldRay and (World <> nil) then
            begin
              WorldOrigin := LocalToWorld(Vector3(PX, FVolumeHalfExtents.Y + 4.0, PZ));
              RayHit := World.WorldRay(WorldOrigin, Vector3(0, -1, 0));
              try
                if (RayHit <> nil) and (RayHit.Count > 0) then
                  for J := 0 to RayHit.Count - 1 do
                    if (RayHit[J].Item <> nil) and
                       (RayHit[J].Item <> World) and
                       (not (csTransient in RayHit[J].Item.ComponentStyle)) and
                       (not IsSelfOrDescendant(RayHit[J].Item)) then
                    begin
                      FoundRayHit := True;
                      HitPos := WorldToLocal(RayHit[J].Point);
                      if (RayHit[J].Triangle <> nil) and RayHit[J].Item.HasWorldTransform then
                        HitNorm := RayHit[J].Item.LocalToWorldDirection(RayHit[J].Triangle^.SceneSpace.Normal)
                      else if RayHit[J].Item.HasWorldTransform then
                        HitNorm := RayHit[J].Item.LocalToWorldDirection(Vector3(0, 1, 0))
                      else
                        HitNorm := RayHit[J].Item.Transform.MultDirection(Vector3(0, 1, 0));
                      if HitNorm.LengthSqr > 1e-6 then
                        HitNorm := HitNorm.Normalize
                      else
                        HitNorm := Vector3(0, 1, 0);
                      if HitNorm.Y < 0.0 then
                        HitNorm := -HitNorm;
                      Break;
                    end;
              finally
                FreeAndNil(RayHit);
              end;
              if HasWorldSurfaces and (not FoundRayHit) then
                Continue;
            end;

            Pt := Default(TPcgPoint);
            Pt.Position := HitPos;
            Pt.SurfaceNormal := HitNorm;
            Pt.RotationYawDeg := 0.0;
            Pt.Scale := Vector3(1.0, 1.0, 1.0);
            Pt.BoundsHalfExtents := Vector3(
              Max(0.05, N.VecA.X), Max(0.05, N.VecA.Y), Max(0.05, N.VecA.Z));
            Pt.Density := 1.0;
            Pt.Steepness := 0.5;
            Pt.Seed := PtSeed;
            Pt.Color := Vector3(0.25, 0.78, 0.35);
            Result[OutCnt] := Pt;
            Inc(OutCnt);
          end;
        SetLength(Result, OutCnt);
      end;

    pnkSplineSampler:
      begin
        Step := Max(0.25, N.ParamA);
        DirVec := N.VecB - N.VecA;
        SegLen := DirVec.Length;
        StepsCount := Max(1, Floor(SegLen / Step));
        SetLength(Result, StepsCount + 1);
        for I := 0 to StepsCount do
        begin
          DistAlong := Min(SegLen, I * Step);
          if SegLen > 1e-5 then
            TParam := DistAlong / SegLen
          else
            TParam := 0.0;
          Pt := Default(TPcgPoint);
          Pt.Position := Lerp(TParam, N.VecA, N.VecB);
          Pt.SurfaceNormal := Vector3(0, 1, 0);
          if (Abs(DirVec.X) > 1e-5) or (Abs(DirVec.Z) > 1e-5) then
            Pt.RotationYawDeg := RadToDeg(ArcTan2(DirVec.X, DirVec.Z))
          else
            Pt.RotationYawDeg := 0.0;
          Pt.Scale := Vector3(1, 1, 1);
          Pt.BoundsHalfExtents := Vector3(
            Max(0.1, N.ParamB), Max(0.5, N.ParamB), Max(0.1, N.ParamB));
          Pt.Density := 1.0;
          Pt.Steepness := 1.0;
          {$PUSH}{$R-}{$Q-}
          Pt.Seed := HashUint32(GraphSeedU xor (Cardinal(I) * Cardinal(2654435761)));
          {$POP}
          Pt.Color := Vector3(0.88, 0.62, 0.22);
          Result[I] := Pt;
        end;
      end;

    pnkDensityNoise:
      begin
        Result := Copy(Stream0);
        for I := 0 to High(Result) do
        begin
          NoiseVal := ValueNoise3D(Result[I].Position * Max(0.001, N.ParamA), GraphSeedU);
          Result[I].Density := EnsureRange(
            Result[I].Density * Lerp(NoiseVal, N.ParamB, N.ParamC), 0.0, 1.0);
        end;
      end;

    pnkBoundsModifier:
      begin
        Result := Copy(Stream0);
        ScaleU := Max(0.05, N.ParamA);
        for I := 0 to High(Result) do
          Result[I].BoundsHalfExtents := Result[I].BoundsHalfExtents * ScaleU;
      end;

    pnkTransformPoints:
      begin
        Result := Copy(Stream0);
        for I := 0 to High(Result) do
        begin
          PtSeed := Result[I].Seed;
          Result[I].Position := Result[I].Position + Vector3(
            (HashFloat01(PtSeed, 101) * 2.0 - 1.0) * N.VecA.X,
            (HashFloat01(PtSeed, 103) * 2.0 - 1.0) * N.VecA.Y,
            (HashFloat01(PtSeed, 107) * 2.0 - 1.0) * N.VecA.Z);
          YawDeg := HashFloat01(PtSeed, 109) * N.ParamA;
          Result[I].RotationYawDeg := Result[I].RotationYawDeg + YawDeg;
          ScaleU := Lerp(HashFloat01(PtSeed, 113), Max(0.05, N.ParamB), Max(0.05, N.ParamC));
          Result[I].Scale := Result[I].Scale * ScaleU;
        end;
      end;

    pnkDensityFilter:
      begin
        LowerD := Min(N.ParamA, N.ParamB);
        UpperD := Max(N.ParamA, N.ParamB);
        SetLength(Result, Length(Stream0));
        OutCnt := 0;
        for I := 0 to High(Stream0) do
        begin
          KeepPt := (Stream0[I].Density >= LowerD) and (Stream0[I].Density <= UpperD);
          if N.BoolFlag then KeepPt := not KeepPt;
          if KeepPt then
          begin
            Result[OutCnt] := Stream0[I];
            Inc(OutCnt);
          end;
        end;
        SetLength(Result, OutCnt);
      end;

    pnkNormalSlopeFilter:
      begin
        SetLength(Result, Length(Stream0));
        OutCnt := 0;
        for I := 0 to High(Stream0) do
        begin
          DotUp := EnsureRange(TVector3.DotProduct(Stream0[I].SurfaceNormal, Vector3(0, 1, 0)), -1.0, 1.0);
          SlopeDeg := RadToDeg(ArcCos(DotUp));
          KeepPt := (SlopeDeg >= N.ParamA) and (SlopeDeg <= N.ParamB);
          if N.BoolFlag then KeepPt := not KeepPt;
          if KeepPt then
          begin
            Result[OutCnt] := Stream0[I];
            Inc(OutCnt);
          end;
        end;
        SetLength(Result, OutCnt);
      end;

    pnkDifference:
      begin
        SetLength(Result, Length(Stream0));
        OutCnt := 0;
        for I := 0 to High(Stream0) do
        begin
          OverlapsAny := False;
          for J := 0 to High(Stream1) do
            if PointsBoundsOverlap3D(Stream0[I], Stream1[J], 1.0) then
            begin
              OverlapsAny := True;
              Break;
            end;
          if not OverlapsAny then
          begin
            Result[OutCnt] := Stream0[I];
            Inc(OutCnt);
          end else if not N.BoolFlag then
          begin
            Pt := Stream0[I];
            Pt.Density := Max(0.0, Pt.Density - 0.5);
            if Pt.Density > 0.01 then
            begin
              Result[OutCnt] := Pt;
              Inc(OutCnt);
            end;
          end;
        end;
        SetLength(Result, OutCnt);
      end;

    pnkUnion:
      begin
        SetLength(Result, Length(Stream0) + Length(Stream1));
        OutCnt := 0;
        for I := 0 to High(Stream0) do
        begin
          Result[OutCnt] := Stream0[I];
          Inc(OutCnt);
        end;
        for I := 0 to High(Stream1) do
        begin
          Result[OutCnt] := Stream1[I];
          Inc(OutCnt);
        end;
      end;

    pnkSelfPruning:
      begin
        { Sort deterministically by descending Density, tie-broken by Seed }
        Stream1 := Copy(Stream0);
        for I := 0 to High(Stream1) - 1 do
          for J := I + 1 to High(Stream1) do
            if (Stream1[J].Density > Stream1[I].Density + 1e-6) or
               ((Abs(Stream1[J].Density - Stream1[I].Density) <= 1e-6) and
                (Stream1[J].Seed < Stream1[I].Seed)) then
            begin
              TempPt := Stream1[I];
              Stream1[I] := Stream1[J];
              Stream1[J] := TempPt;
            end;

        SetLength(Result, Length(Stream1));
        OutCnt := 0;
        ScaleU := Max(0.1, N.ParamA);
        for I := 0 to High(Stream1) do
        begin
          OverlapsAny := False;
          for J := 0 to OutCnt - 1 do
            if PointsBoundsOverlap3D(Stream1[I], Result[J], ScaleU) then
            begin
              OverlapsAny := True;
              Break;
            end;
          if not OverlapsAny then
          begin
            Result[OutCnt] := Stream1[I];
            Inc(OutCnt);
          end;
        end;
        SetLength(Result, OutCnt);
      end;

    pnkStaticMeshSpawner:
      Result := Copy(Stream0);
  end;

  FNodes[ANodeIdx].LastOutputCount := Length(Result);
  CachedStreams[ANodeIdx] := Result;
  CachedValid[ANodeIdx] := True;
  VisitState[ANodeIdx] := 2;
end;

procedure TCastlePcgGraph.InstantiateSpawnerMeshes(const ANode: TPcgGraphNode;
  const APoints: TPcgPointArray);
var
  I: Integer;
  BoxM: TCastleBox;
  CylM: TCastleCylinder;
  SphM: TCastleSphere;
  ScnM: TCastleScene;
  ChildT: TCastleTransform;
  Col4: TCastleColor;
begin
  if Length(APoints) = 0 then Exit;
  EnsureSpawnContainer;
  Col4 := Vector4(
    EnsureRange(ANode.VecB.X, 0.0, 1.0),
    EnsureRange(ANode.VecB.Y, 0.0, 1.0),
    EnsureRange(ANode.VecB.Z, 0.0, 1.0), 1.0);

  for I := 0 to High(APoints) do
  begin
    if Trim(ANode.AssetUrl) <> '' then
    begin
      ScnM := TCastleScene.Create(FSpawnContainer);
      ScnM.SetTransient;
      ScnM.Url := ANode.AssetUrl;
      ChildT := ScnM;
    end else
      case ANode.PrimKind of
        pmkPineCylinder:
          begin
            CylM := TCastleCylinder.Create(FSpawnContainer);
            CylM.SetTransient;
            CylM.Radius := Max(0.05, ANode.VecA.X * 0.5);
            CylM.Height := Max(0.1, ANode.VecA.Y);
            CylM.Color := Col4;
            ChildT := CylM;
          end;
        pmkBoulderSphere:
          begin
            SphM := TCastleSphere.Create(FSpawnContainer);
            SphM.SetTransient;
            SphM.Radius := Max(0.05, ANode.VecA.X * 0.5);
            SphM.Color := Col4;
            ChildT := SphM;
          end;
      else
        begin
          BoxM := TCastleBox.Create(FSpawnContainer);
          BoxM.SetTransient;
          BoxM.Size := Vector3(
            Max(0.05, ANode.VecA.X),
            Max(0.05, ANode.VecA.Y),
            Max(0.05, ANode.VecA.Z));
          BoxM.Color := Col4;
          ChildT := BoxM;
        end;
      end;

    Inc(FSpawnedMeshCount);
    ChildT.Name := Format('PCG_Inst_%d', [FSpawnedMeshCount]);
    ChildT.Translation := APoints[I].Position + Vector3(0, ANode.VecA.Y * 0.5 * APoints[I].Scale.Y, 0);
    ChildT.Rotation := Vector4(0, 1, 0, DegToRad(APoints[I].RotationYawDeg));
    ChildT.Scale := APoints[I].Scale;
    FSpawnContainer.Add(ChildT);
  end;
end;

function TCastlePcgGraph.EvaluateNodeOutput(const ANodeId: String;
  out OutPoints: TPcgPointArray): Boolean;
var
  Idx, I: Integer;
  VisitState: array of Byte;
  CachedValid: array of Boolean;
  CachedStreams: array of TPcgPointArray;
begin
  OutPoints := nil;
  Idx := FindNodeIndex(ANodeId);
  if (Idx < 0) or (not ValidateGraph) then
    Exit(False);

  SetLength(VisitState, Length(FNodes));
  SetLength(CachedValid, Length(FNodes));
  SetLength(CachedStreams, Length(FNodes));
  for I := 0 to High(FNodes) do
  begin
    VisitState[I] := 0;
    CachedValid[I] := False;
  end;

  OutPoints := EvaluateNodeRecursive(Idx, VisitState, CachedValid, CachedStreams);
  Result := True;
end;

function TCastlePcgGraph.ExecuteGraph: Boolean;
var
  I: Integer;
  VisitState: array of Byte;
  CachedValid: array of Boolean;
  CachedStreams: array of TPcgPointArray;
  Pts: TPcgPointArray;
begin
  ClearSpawnedMeshes;
  if not ValidateGraph then
  begin
    FLastExecutionValid := False;
    Exit(False);
  end;

  SetLength(VisitState, Length(FNodes));
  SetLength(CachedValid, Length(FNodes));
  SetLength(CachedStreams, Length(FNodes));
  for I := 0 to High(FNodes) do
  begin
    VisitState[I] := 0;
    CachedValid[I] := False;
    FNodes[I].LastOutputCount := 0;
  end;

  { Evaluate all nodes so per-node LastOutputCount badges are populated, and
    instantiate transient meshes for every active pnkStaticMeshSpawner }
  for I := 0 to High(FNodes) do
  begin
    Pts := EvaluateNodeRecursive(I, VisitState, CachedValid, CachedStreams);
    if FNodes[I].Enabled and (FNodes[I].Kind = pnkStaticMeshSpawner) then
      InstantiateSpawnerMeshes(FNodes[I], Pts);
  end;

  FLastExecutionValid := True;
  Result := True;
end;

{ Built-In UE5 PCG Presets --------------------------------------------------- }

procedure TCastlePcgGraph.ApplyPreset(const APreset: TPcgGraphPreset);
var
  N: TPcgGraphNode;
begin
  FPreset := APreset;
  if APreset = pgpCustom then Exit;

  ClearGraph;
  FPreset := APreset;

  case APreset of
    pgpForestWithRoadClearing:
      begin
        FVolumeHalfExtents := Vector3(12.0, 8.0, 12.0);

        N := MakeDefaultNode('Surface_Forest', pnkSurfaceSampler, 30, 50);
        N.ParamA := 2.4;
        N.ParamB := 0.30;
        N.VecA := Vector3(1.05, 2.0, 1.05);
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Noise_Canopy', pnkDensityNoise, 220, 50);
        N.ParamA := 0.22;
        N.ParamB := 0.05;
        N.ParamC := 1.00;
        N.InputNode0 := 'Surface_Forest';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Filter_Dense', pnkDensityFilter, 410, 50);
        N.ParamA := 0.35;
        N.ParamB := 1.00;
        N.InputNode0 := 'Noise_Canopy';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Spline_Road', pnkSplineSampler, 220, 210);
        N.ParamA := 1.2;
        N.ParamB := 2.6; { 5.2m wide road clearing }
        N.VecA := Vector3(-13.0, 0.0, 0.0);
        N.VecB := Vector3(13.0, 0.0, 0.0);
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Diff_ClearRoad', pnkDifference, 600, 110);
        N.BoolFlag := True;
        N.InputNode0 := 'Filter_Dense';
        N.InputNode1 := 'Spline_Road';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Prune_NoOverlap', pnkSelfPruning, 790, 110);
        N.ParamA := 1.0;
        N.InputNode0 := 'Diff_ClearRoad';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Xform_Natural', pnkTransformPoints, 790, 240);
        N.ParamA := 360.0;
        N.ParamB := 0.85;
        N.ParamC := 1.35;
        N.VecA := Vector3(0.20, 0.0, 0.20);
        N.InputNode0 := 'Prune_NoOverlap';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Spawn_Pines', pnkStaticMeshSpawner, 980, 175);
        N.PrimKind := pmkPineCylinder;
        N.VecA := Vector3(0.9, 3.2, 0.9);
        N.VecB := Vector3(0.18, 0.56, 0.25);
        N.InputNode0 := 'Xform_Natural';
        AddOrUpdateNode(N);
      end;

    pgpRockOutcropAndShrubUnion:
      begin
        FVolumeHalfExtents := Vector3(10.0, 8.0, 10.0);

        N := MakeDefaultNode('Surface_Meadow', pnkSurfaceSampler, 30, 100);
        N.ParamA := 2.8;
        N.VecA := Vector3(0.9, 1.5, 0.9);
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Noise_Clusters', pnkDensityNoise, 220, 100);
        N.ParamA := 0.28;
        N.ParamB := 0.0;
        N.ParamC := 1.0;
        N.InputNode0 := 'Surface_Meadow';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Filter_Rocks', pnkDensityFilter, 420, 45);
        N.ParamA := 0.68;
        N.ParamB := 1.00;
        N.InputNode0 := 'Noise_Clusters';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Filter_Shrubs', pnkDensityFilter, 420, 175);
        N.ParamA := 0.35;
        N.ParamB := 0.62;
        N.InputNode0 := 'Noise_Clusters';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Union_Biome', pnkUnion, 620, 105);
        N.InputNode0 := 'Filter_Rocks';
        N.InputNode1 := 'Filter_Shrubs';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Prune_Biome', pnkSelfPruning, 810, 105);
        N.ParamA := 1.0;
        N.InputNode0 := 'Union_Biome';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Spawn_Boulders', pnkStaticMeshSpawner, 990, 105);
        N.PrimKind := pmkBoulderSphere;
        N.VecA := Vector3(1.2, 1.0, 1.2);
        N.VecB := Vector3(0.52, 0.50, 0.48);
        N.InputNode0 := 'Prune_Biome';
        AddOrUpdateNode(N);
      end;

    pgpSplineFenceColonnade:
      begin
        N := MakeDefaultNode('Spline_Path', pnkSplineSampler, 60, 110);
        N.ParamA := 2.0;
        N.ParamB := 0.5;
        N.VecA := Vector3(-10.0, 0.0, -6.0);
        N.VecB := Vector3(10.0, 0.0, 6.0);
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Spawn_Posts', pnkStaticMeshSpawner, 320, 110);
        N.PrimKind := pmkBox;
        N.VecA := Vector3(0.35, 1.6, 0.35);
        N.VecB := Vector3(0.62, 0.44, 0.26);
        N.InputNode0 := 'Spline_Path';
        AddOrUpdateNode(N);
      end;
  end;

  if not (csLoading in ComponentState) then
    ExecuteGraph;
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastlePcgGraph.GetGraphJson: String;
var
  Root, Obj: TJSONObject;
  NodesArr, VecArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    VecArr := TJSONArray.Create;
    VecArr.Add(FVolumeHalfExtents.X);
    VecArr.Add(FVolumeHalfExtents.Y);
    VecArr.Add(FVolumeHalfExtents.Z);
    Root.Add('extents', VecArr);

    NodesArr := TJSONArray.Create;
    for I := 0 to High(FNodes) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', FNodes[I].NodeId);
      Obj.Add('kind', Ord(FNodes[I].Kind));
      Obj.Add('x', FNodes[I].PosX);
      Obj.Add('y', FNodes[I].PosY);
      Obj.Add('en', FNodes[I].Enabled);
      Obj.Add('pa', FNodes[I].ParamA);
      Obj.Add('pb', FNodes[I].ParamB);
      Obj.Add('pc', FNodes[I].ParamC);
      Obj.Add('bf', FNodes[I].BoolFlag);
      Obj.Add('pk', Ord(FNodes[I].PrimKind));
      Obj.Add('url', FNodes[I].AssetUrl);
      Obj.Add('in0', FNodes[I].InputNode0);
      Obj.Add('in1', FNodes[I].InputNode1);
      VecArr := TJSONArray.Create;
      VecArr.Add(FNodes[I].VecA.X);
      VecArr.Add(FNodes[I].VecA.Y);
      VecArr.Add(FNodes[I].VecA.Z);
      Obj.Add('va', VecArr);
      VecArr := TJSONArray.Create;
      VecArr.Add(FNodes[I].VecB.X);
      VecArr.Add(FNodes[I].VecB.Y);
      VecArr.Add(FNodes[I].VecB.Z);
      Obj.Add('vb', VecArr);
      NodesArr.Add(Obj);
    end;
    Root.Add('nodes', NodesArr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastlePcgGraph.SetGraphJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, Obj: TJSONObject;
  Arr, VecArr: TJSONArray;
  I: Integer;
  N: TPcgGraphNode;
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
    ClearGraph;
    FPreset := pgpCustom;

    VecArr := Root.Find('extents', jtArray) as TJSONArray;
    if (VecArr <> nil) and (VecArr.Count >= 3) then
      FVolumeHalfExtents := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);

    Arr := Root.Find('nodes', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          N := MakeDefaultNode(
            Obj.Get('id', 'PCG_' + IntToStr(I)),
            TPcgNodeKind(EnsureRange(Obj.Get('kind', 0), 0, Ord(High(TPcgNodeKind)))),
            Obj.Get('x', 60.0),
            Obj.Get('y', 80.0));
          N.Enabled := Obj.Get('en', True);
          N.ParamA := Obj.Get('pa', N.ParamA);
          N.ParamB := Obj.Get('pb', N.ParamB);
          N.ParamC := Obj.Get('pc', N.ParamC);
          N.BoolFlag := Obj.Get('bf', N.BoolFlag);
          N.PrimKind := TPcgPrimitiveMeshKind(EnsureRange(Obj.Get('pk', 0), 0, Ord(High(TPcgPrimitiveMeshKind))));
          N.AssetUrl := Obj.Get('url', '');
          N.InputNode0 := Obj.Get('in0', '');
          N.InputNode1 := Obj.Get('in1', '');
          VecArr := Obj.Find('va', jtArray) as TJSONArray;
          if (VecArr <> nil) and (VecArr.Count >= 3) then
            N.VecA := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);
          VecArr := Obj.Find('vb', jtArray) as TJSONArray;
          if (VecArr <> nil) and (VecArr.Count >= 3) then
            N.VecB := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);
          AddOrUpdateNode(N);
        end;

    if (not (csLoading in ComponentState)) and FAutoExecuteOnLoad then
      ExecuteGraph;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastlePcgGraph.PcgSummaryBadge: String;
var
  StateStr: String;
begin
  if FLastExecutionValid then
    StateStr := 'OK'
  else
    StateStr := Format('ERR:%d', [FValidationErrors.Count]);
  Result := Format('[PCG:%s Seed=%d Nodes=%d Spawned=%d]',
    [StateStr, FGraphSeed, Length(FNodes), FSpawnedMeshCount]);
end;

initialization
  RegisterSerializableComponent(TCastlePcgGraph, 'PCG Visual Node Graph Volume');
end.
